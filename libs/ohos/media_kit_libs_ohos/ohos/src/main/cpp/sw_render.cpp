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
#include <cstdio>

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

void LogFile(const char* line) {
  // hilog drops LOG_APP from this module on the emulator; mirror to the
  // app files dir where the Dart side can read it back.
  FILE* f = fopen("/data/storage/el2/base/files/sw_log.txt", "a");
  if (f) {
    fputs(line, f);
    fputc('\n', f);
    fclose(f);
  }
}

void Log(const char* message) {
  OH_LOG_Print(LOG_APP, LOG_INFO, kDomain, kTag, "[%{public}s]", message);
  LogFile(message);
}

void LogValue(const char* message, int64_t value) {
  OH_LOG_Print(LOG_APP, LOG_INFO, kDomain, kTag,
               "[%{public}s %{public}lld]", message, value);
  char line[160];
  std::snprintf(line, sizeof(line), "%s %lld", message,
                static_cast<long long>(value));
  LogFile(line);
}

void LogSymbolOrigin(const char* via, void* symbol) {
  Dl_info info{};
  if (dladdr(symbol, &info) != 0 && info.dli_fname != nullptr) {
    char line[512];
    std::snprintf(line, sizeof(line), "sym %s -> %s", via, info.dli_fname);
    LogFile(line);
    OH_LOG_Print(LOG_APP, LOG_INFO, kDomain, kTag,
                 "[%{public}s]", line);
  } else {
    Log("sym origin unknown");
  }
}

bool BindMpvApi() {
  // The app process already loaded libmpv (media_kit FFI). Prefer binding
  // THAT instance: a namespace-isolated dlopen may load a second copy, and
  // a render context on the copy never sees the player's video chain
  // (observed as "render() not being called" + black output).
  void* create_default = dlsym(RTLD_DEFAULT, "mpv_render_context_create");
  if (create_default != nullptr) {
    LogSymbolOrigin("RTLD_DEFAULT", create_default);
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
      return true;
    }
  }
  g_api.handle = dlopen("libmpv.so", RTLD_NOW);
  if (!g_api.handle) {
    Log("dlopen libmpv.so failed");
    return false;
  }
  if (create_default != nullptr) {
    void* create_local = dlsym(g_api.handle, "mpv_render_context_create");
    if (create_local != create_default) {
      Log("SECOND libmpv copy detected");
    }
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
  while (g_running.load()) {
    int w = 0;
    int h = 0;
    if (OH_NativeWindow_NativeWindowHandleOpt(g_window, GET_BUFFER_GEOMETRY,
                                              &h, &w) == 0 &&
        w > 0 && h > 0) {
      g_width = w;
      g_height = h;
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
    }
    std::this_thread::sleep_for(std::chrono::milliseconds(25));
  }

  if (render_context) g_api.render_context_free(render_context);
  LogValue("RL: stopped, frames", static_cast<int64_t>(rendered));
  LogValue("RL: stopped, submitted", static_cast<int64_t>(submitted));
}

}  // namespace

extern "C" {

int32_t mk_sw_start(int64_t surface_id, int64_t mpv_handle) {
  std::lock_guard<std::mutex> lock(g_mutex);
  if (g_running.load()) {
    Log("already running");
    return -1;
  }
  if (!BindMpvApi()) return -2;
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

int32_t mk_sw_set_surface(int64_t surface_id) {
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

}  // extern "C"
