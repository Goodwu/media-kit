// Software render bridge for the OHOS emulator: attaches to a live mpv
// handle, renders frames through libmpv's software render API into a CPU
// buffer, and submits them to the Flutter texture surface through the
// NativeWindow producer API (RequestBuffer → map → memcpy → FlushBuffer).
// The engine's TLHC external-texture consumer owns the surface; creating our
// own EGL window surface on it would starve the consumer's buffer queue
// (observed as "bind external with nullptr gbuffer").
//
// Loaded from Dart via DynamicLibrary.open('libmediakit_ohos_sw.so'). libmpv
// is NOT linked: it is already loaded by media_kit, so dlopen("libmpv.so")
// binds to the same instance and the mpv handle address passed from Dart is
// used directly.
#include <native_buffer/native_buffer.h>
#include <native_window/external_window.h>
#include <hilog/log.h>
#include <unistd.h>

#include <dlfcn.h>
#include <cerrno>
#include <cstdio>
#include <string>

#include <atomic>
#include <chrono>
#include <cstdint>
#include <cstring>
#include <mutex>
#include <thread>
#include <vector>

namespace {

constexpr unsigned int kDomain = 0xD0016;
constexpr char kTag[] = "MkSwRender";

// mpv render API surface, bound via dlsym (signatures from render.h).
struct MpvRenderApi {
  void* handle = nullptr;
  int (*render_context_create)(void** ctx, void* mpv, void* params) = nullptr;
  void (*render_context_free)(void* ctx) = nullptr;
  int (*render_context_render)(void* ctx, void* params) = nullptr;
};

// render.h mpv_render_param_type values (kept literal: the header is not
// shipped with the libmpv archive).
constexpr int kParamInvalid = 0;
constexpr int kParamApiType = 1;
constexpr int kParamSwSize = 17;
constexpr int kParamSwFormat = 18;
constexpr int kParamSwStride = 19;
constexpr int kParamSwPointer = 20;
constexpr char kApiTypeSw[] = "sw";
constexpr char kSwFormatRgba[] = "rgb0";

// Mirrors mpv_render_param { enum type; void* data; } from render.h.
struct MpvRenderParam {
  int type;
  void* data;
};

std::mutex g_mutex;
std::atomic<bool> g_running{false};
// Window attach state: the render context may exist (and render into the
// internal buffer) long before any surface is attached; submission only
// runs while a window is attached. Swapping windows never frees the ctx.
std::atomic<bool> g_window_attached{false};
std::atomic<uint64_t> g_frames{0};
std::atomic<uint64_t> g_submitted{0};
std::atomic<uint64_t> g_pixel_sum{0};
std::thread g_thread;
OHNativeWindow* g_window = nullptr;
void* g_mpv_handle = nullptr;
MpvRenderApi g_api;
int g_width = 0;
int g_height = 0;

// In-memory log tail polled from Dart through FFI. Both channels exist
// because hilog drops LOG_APP from this module on the emulator and the file
// mirror below silently failed in earlier rounds (errno now recorded once).
std::mutex g_log_mutex;
std::string g_logbuf;
char g_log_out[16384];

void LogRing(const char* line) {
  std::lock_guard<std::mutex> lock(g_log_mutex);
  g_logbuf.append(line);
  g_logbuf.push_back('\n');
  constexpr size_t kLogCap = 12 * 1024;
  if (g_logbuf.size() > kLogCap) g_logbuf.erase(0, g_logbuf.size() - kLogCap);
}

void LogFile(const char* line) {
  // hilog drops LOG_APP from this module on the emulator; mirror to the
  // app files dir where the Dart side can read it back.
  FILE* f = fopen("/data/storage/el2/base/files/sw_log.txt", "a");
  if (f) {
    fputs(line, f);
    fputc('\n', f);
    fclose(f);
    return;
  }
  static std::atomic<bool> warned{false};
  if (!warned.exchange(true)) {
    char msg[128];
    std::snprintf(msg, sizeof(msg), "log file open failed errno=%d", errno);
    OH_LOG_Print(LOG_APP, LOG_INFO, kDomain, kTag, "[%{public}s]", msg);
    LogRing(msg);
  }
}

void Log(const char* message) {
  LogRing(message);
  OH_LOG_Print(LOG_APP, LOG_INFO, kDomain, kTag, "[%{public}s]", message);
  LogFile(message);
}

void LogValue(const char* message, int64_t value) {
  char line[160];
  std::snprintf(line, sizeof(line), "%s %lld", message,
                static_cast<long long>(value));
  Log(line);
}

const char* SymbolPath(void* symbol) {
  Dl_info info{};
  if (dladdr(symbol, &info) != 0 && info.dli_fname != nullptr) {
    return info.dli_fname;
  }
  return "?";
}

// Binding evidence: log where each resolution route points. A render context
// created through a second libmpv copy never sees the player's video chain
// (observed as vo_libmpv repeating "render() not being called or stuck" while
// our render calls succeed and produce zero pixels).
void Forensics(void* dart_create) {
  void* rtld_create = dlsym(RTLD_DEFAULT, "mpv_render_context_create");
  void* handle = dlopen("libmpv.so", RTLD_NOW);
  void* dlopen_create =
      handle ? dlsym(handle, "mpv_render_context_create") : nullptr;
  char line[768];
  std::snprintf(line, sizeof(line), "sym dart=%p rtld=%p dlopen=%p",
                dart_create, rtld_create, dlopen_create);
  Log(line);
  if (dart_create) {
    std::snprintf(line, sizeof(line), "origin dart -> %s",
                  SymbolPath(dart_create));
    Log(line);
  }
  if (rtld_create) {
    std::snprintf(line, sizeof(line), "origin rtld -> %s",
                  SymbolPath(rtld_create));
    Log(line);
  }
  if (dlopen_create) {
    std::snprintf(line, sizeof(line), "origin dlopen -> %s",
                  SymbolPath(dlopen_create));
    Log(line);
  }
  const char* verdict;
  if (dart_create && dlopen_create && dart_create != dlopen_create) {
    verdict = "SECOND libmpv copy (dlopen differs from dart)";
  } else if (dart_create && rtld_create && dart_create != rtld_create) {
    verdict = "rtld instance differs from dart";
  } else {
    verdict = "same copy";
  }
  std::snprintf(line, sizeof(line), "bind verdict: %s", verdict);
  Log(line);
}

bool BindMpvApi() {
  // The app process already loaded libmpv (media_kit FFI). Prefer binding
  // THAT instance: a namespace-isolated dlopen may load a second copy, and
  // a render context on the copy never sees the player's video chain
  // (observed as "render() not being called" + black output).
  void* create_default = dlsym(RTLD_DEFAULT, "mpv_render_context_create");
  if (create_default != nullptr) {
    g_api.render_context_create =
        reinterpret_cast<decltype(g_api.render_context_create)>(create_default);
    g_api.render_context_free =
        reinterpret_cast<decltype(g_api.render_context_free)>(
            dlsym(RTLD_DEFAULT, "mpv_render_context_free"));
    g_api.render_context_render =
        reinterpret_cast<decltype(g_api.render_context_render)>(
            dlsym(RTLD_DEFAULT, "mpv_render_context_render"));
    if (g_api.render_context_free && g_api.render_context_render) {
      g_api.handle = nullptr;  // borrowed from the global scope
      Log("bind: RTLD_DEFAULT");
      return true;
    }
  }
  g_api.handle = dlopen("libmpv.so", RTLD_NOW);
  if (!g_api.handle) {
    Log("dlopen libmpv.so failed");
    return false;
  }
  g_api.render_context_create =
      reinterpret_cast<decltype(g_api.render_context_create)>(
          dlsym(g_api.handle, "mpv_render_context_create"));
  g_api.render_context_free =
      reinterpret_cast<decltype(g_api.render_context_free)>(
          dlsym(g_api.handle, "mpv_render_context_free"));
  g_api.render_context_render =
      reinterpret_cast<decltype(g_api.render_context_render)>(
          dlsym(g_api.handle, "mpv_render_context_render"));
  if (!g_api.render_context_create || !g_api.render_context_free ||
      !g_api.render_context_render) {
    Log("dlsym mpv render api failed");
    return false;
  }
  Log("bind: dlopen libmpv.so");
  return true;
}

void RenderLoop() {
  Log("RL: entry");

  // The consumer owns the window format; a producer-side SET_FORMAT could
  // break its already-attached buffers. Only the geometry is adapted.

  void* render_context = nullptr;
  MpvRenderParam create_params[] = {
      {kParamApiType, const_cast<char*>(kApiTypeSw)},
      {kParamInvalid, nullptr},
  };
  if (g_api.render_context_create(&render_context, g_mpv_handle,
                                  create_params) < 0) {
    g_running.store(false);
    Log("RL: mpv_render_context_create(sw) failed");
    return;
  }
  Log("RL: sw render context created");

  std::vector<uint8_t> pixels;
  uint64_t rendered = 0;
  uint64_t submitted = 0;
  int logged_w = -1;
  int logged_h = -1;
  while (g_running.load()) {
    int w = 0;
    int h = 0;
    if (OH_NativeWindow_NativeWindowHandleOpt(g_window, GET_BUFFER_GEOMETRY,
                                              &h, &w) == 0 &&
        w > 0 && h > 0) {
      g_width = w;
      g_height = h;
    }
    if (g_width != logged_w || g_height != logged_h) {
      char line[96];
      std::snprintf(line, sizeof(line), "RL: geometry %dx%d", g_width,
                    g_height);
      Log(line);
      logged_w = g_width;
      logged_h = g_height;
    }
    if (g_width <= 0 || g_height <= 0) {
      std::this_thread::sleep_for(std::chrono::milliseconds(30));
      continue;
    }
    const int width = g_width;
    const int height = g_height;
    const size_t src_stride = static_cast<size_t>(width) * 4;
    if (pixels.size() != src_stride * height) {
      pixels.assign(src_stride * height, 0);
      LogValue("RL: buffer sized", static_cast<int64_t>(pixels.size()));
    }

    int size[2] = {width, height};
    size_t stride = src_stride;
    void* format = const_cast<char*>(kSwFormatRgba);
    MpvRenderParam params[] = {
        {kParamSwSize, size},
        {kParamSwFormat, format},
        {kParamSwStride, &stride},
        {kParamSwPointer, pixels.data()},
        {kParamInvalid, nullptr},
    };
    if (g_api.render_context_render(render_context, params) < 0) {
      Log("RL: mpv software render failed");
      break;
    }
    uint64_t sample = 0;
    for (size_t i = 0; i < pixels.size(); i += 97) sample += pixels[i];
    g_pixel_sum.store(sample);
    rendered++;
    g_frames.store(rendered);
    if (rendered == 1) {
      LogValue("RL: first render ok", static_cast<int64_t>(width));
    }

    if (!g_window_attached.load() || g_window == nullptr) {
      // No consumer window yet (or between swaps): render into the internal
      // buffer only, so the mpv render context keeps draining frames.
      std::this_thread::sleep_for(std::chrono::milliseconds(25));
      continue;
    }
    OHNativeWindowBuffer* window_buffer = nullptr;
    int fence = -1;
    int rc = OH_NativeWindow_NativeWindowRequestBuffer(g_window,
                                                       &window_buffer, &fence);
    if (rc != 0 || window_buffer == nullptr) {
      LogValue("RL: request buffer failed", rc);
      std::this_thread::sleep_for(std::chrono::milliseconds(15));
      continue;
    }
    OH_NativeBuffer* buffer = nullptr;
    if (OH_NativeBuffer_FromNativeWindowBuffer(window_buffer, &buffer) != 0 ||
        buffer == nullptr) {
      Log("RL: from native window buffer failed");
      continue;
    }
    void* vir = nullptr;
    OH_NativeBuffer_Planes planes{};
    if (fence >= 0) {
      rc = OH_NativeBuffer_MapWaitFence(buffer, fence, &vir);
      close(fence);
    } else {
      rc = OH_NativeBuffer_MapPlanes(buffer, &vir, &planes);
    }
    if (rc != 0 || vir == nullptr) {
      LogValue("RL: map failed", rc);
      OH_NativeBuffer_Unmap(buffer);
      continue;
    }
    // planes[0].stride is only filled by MapPlanes; fall back to a packed
    // row when the fence-wait path was taken.
    const size_t dst_stride = planes.planes[0].rowStride > 0
                                  ? planes.planes[0].rowStride
                                  : src_stride;
    const size_t row_bytes =
        dst_stride < src_stride ? dst_stride : src_stride;
    for (int y = 0; y < height; y++) {
      std::memcpy(static_cast<uint8_t*>(vir) + y * dst_stride,
                  pixels.data() + y * src_stride, row_bytes);
    }
    OH_NativeBuffer_Unmap(buffer);

    Region::Rect rect{0, 0, static_cast<uint32_t>(width), static_cast<uint32_t>(height)};
    Region region{&rect, 1};
    if (OH_NativeWindow_NativeWindowFlushBuffer(g_window, window_buffer, -1,
                                                region) == 0) {
      submitted++;
      g_submitted.store(submitted);
    }
    if ((rendered % 120) == 0) {
      LogValue("RL: frames", static_cast<int64_t>(rendered));
      LogValue("RL: submitted", static_cast<int64_t>(submitted));
      LogValue("RL: pixel_sum", static_cast<int64_t>(g_pixel_sum.load()));
    }
    std::this_thread::sleep_for(std::chrono::milliseconds(25));
  }

  if (render_context) g_api.render_context_free(render_context);
  LogValue("RL: stopped, frames", static_cast<int64_t>(rendered));
  LogValue("RL: stopped, submitted", static_cast<int64_t>(submitted));
}

int32_t StartImpl(int64_t surface_id, int64_t mpv_handle, void* dart_create,
                  void* dart_free, void* dart_render) {
  std::lock_guard<std::mutex> lock(g_mutex);
  if (g_running.load()) {
    Log("already running");
    return -1;
  }
  Forensics(dart_create);
  if (dart_create && dart_free && dart_render) {
    // Symbols resolved by Dart through the same DynamicLibrary instance
    // media_kit opened: immune to linker-namespace second copies.
    g_api.render_context_create =
        reinterpret_cast<decltype(g_api.render_context_create)>(dart_create);
    g_api.render_context_free =
        reinterpret_cast<decltype(g_api.render_context_free)>(dart_free);
    g_api.render_context_render =
        reinterpret_cast<decltype(g_api.render_context_render)>(dart_render);
    g_api.handle = nullptr;  // borrowed
    Log("bind: dart-resolved symbols");
  } else if (!BindMpvApi()) {
    return -2;
  }
  g_mpv_handle = reinterpret_cast<void*>(static_cast<uintptr_t>(mpv_handle));
  if (!g_mpv_handle) return -3;
  g_width = g_height = 0;
  g_frames.store(0);
  g_submitted.store(0);
  g_window_attached.store(false);
  if (surface_id != 0) {
    if (OH_NativeWindow_CreateNativeWindowFromSurfaceId(
            static_cast<uint64_t>(surface_id), &g_window) != 0 ||
        !g_window) {
      Log("native window from surface id failed");
      return -4;
    }
    g_window_attached.store(true);
  }
  g_running.store(true);
  g_thread = std::thread(RenderLoop);
  LogValue("sw renderer started, mpv handle", mpv_handle);
  return 0;
}

}  // namespace

extern "C" {

int32_t mk_sw_start(int64_t surface_id, int64_t mpv_handle) {
  return StartImpl(surface_id, mpv_handle, nullptr, nullptr, nullptr);
}

int32_t mk_sw_start_ex(int64_t surface_id, int64_t mpv_handle, void* create,
                       void* free_fn, void* render) {
  return StartImpl(surface_id, mpv_handle, create, free_fn, render);
}

int32_t mk_sw_set_surface(int64_t surface_id, int32_t width, int32_t height) {
  std::lock_guard<std::mutex> lock(g_mutex);
  if (!g_running.load()) return -1;
  OHNativeWindow* window = nullptr;
  if (surface_id == 0 ||
      OH_NativeWindow_CreateNativeWindowFromSurfaceId(
          static_cast<uint64_t>(surface_id), &window) != 0 ||
      !window) {
    Log("set surface: native window from surface id failed");
    return -2;
  }
  // The engine's TLHC consumer leaves the surface at its default 3x3
  // geometry and never resizes it; RequestBuffer then returns 3x3 buffers
  // (observed as a 36-byte render buffer and a zero pixel sum). The
  // external_window.h contract expects the producer to set the geometry
  // before requesting buffers — do so with the caller-provided size.
  if (width > 0 && height > 0 &&
      OH_NativeWindow_NativeWindowHandleOpt(window, SET_BUFFER_GEOMETRY,
                                            width, height) != 0) {
    Log("set surface: SET_BUFFER_GEOMETRY failed");
  } else {
    LogValue("set surface: geometry", (int64_t)width);
    LogValue("set surface: geometry h", (int64_t)height);
  }
  // The render loop reads g_window between frames; swap under the same
  // lock the loop's geometry reads do NOT take, so retire the old window
  // only after publishing the new one.
  OHNativeWindow* previous = g_window;
  g_window = window;
  g_window_attached.store(true);
  g_width = g_height = 0;
  if (previous) {
    OH_NativeWindow_DestroyNativeWindow(previous);
  }
  LogValue("set surface", surface_id);
  return 0;
}

int32_t mk_sw_set_geometry(int32_t width, int32_t height) {
  std::lock_guard<std::mutex> lock(g_mutex);
  if (!g_running.load() || g_window == nullptr) return -1;
  if (width <= 0 || height <= 0) return -2;
  if (OH_NativeWindow_NativeWindowHandleOpt(g_window, SET_BUFFER_GEOMETRY,
                                            width, height) != 0) {
    Log("set geometry: SET_BUFFER_GEOMETRY failed");
    return -3;
  }
  // Force the loop to re-query and reallocate its render buffer.
  g_width = g_height = 0;
  LogValue("set geometry w", width);
  LogValue("set geometry h", height);
  return 0;
}

void mk_sw_stop(void) {
  {
    std::lock_guard<std::mutex> lock(g_mutex);
    if (!g_running.exchange(false)) return;
  }
  if (g_thread.joinable()) g_thread.join();
  if (g_window) {
    OH_NativeWindow_DestroyNativeWindow(g_window);
    g_window = nullptr;
  }
  g_mpv_handle = nullptr;
  LogValue("sw renderer stopped, frames",
           static_cast<int64_t>(g_frames.load()));
  LogValue("sw renderer stopped, submitted",
           static_cast<int64_t>(g_submitted.load()));
}

int64_t mk_sw_frames(void) { return static_cast<int64_t>(g_frames.load()); }

int64_t mk_sw_submitted(void) {
  return static_cast<int64_t>(g_submitted.load());
}

int64_t mk_sw_pixel_sum(void) {
  return static_cast<int64_t>(g_pixel_sum.load());
}

int32_t mk_sw_log_take(void) {
  std::lock_guard<std::mutex> lock(g_log_mutex);
  const size_t cap = sizeof(g_log_out) - 1;
  const size_t n = g_logbuf.size() < cap ? g_logbuf.size() : cap;
  if (n > 0) std::memcpy(g_log_out, g_logbuf.data(), n);
  g_log_out[n] = '\0';
  g_logbuf.clear();
  return static_cast<int32_t>(n);
}

const char* mk_sw_log_buffer(void) { return g_log_out; }

}  // extern "C"
