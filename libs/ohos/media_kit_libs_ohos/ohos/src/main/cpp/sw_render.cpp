// Software render bridge for the OHOS emulator: attaches to a live mpv
// handle, renders frames through libmpv's software render API into a CPU
// buffer, and blits them onto the Flutter texture surface with a minimal
// EGL/GLES pipeline. Modeled on the Luna E2 probe (which demonstrably
// displays on the emulator where the GL video outputs render black).
//
// Loaded from Dart via DynamicLibrary.open('libmediakit_sw.so'). libmpv is
// NOT linked: it is already loaded by media_kit, so dlopen("libmpv.so")
// binds to the same instance and the mpv handle address passed from Dart is
// used directly.
#include <EGL/egl.h>
#include <GLES3/gl3.h>
#include <dlfcn.h>
#include <hilog/log.h>
#include <native_window/external_window.h>

#include <atomic>
#include <condition_variable>
#include <cstdint>
#include <cstring>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

namespace {

constexpr unsigned int kDomain = 0xD0016;
constexpr char kTag[] = "MkSwRender";

// mpv render API surface, bound via dlsym ( signatures from render.h ).
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
constexpr char kSwFormatRgba[] = "rgba";

// Mirrors mpv_render_param { enum type; void* data; } from render.h.
struct MpvRenderParam {
  int type;
  void* data;
};

std::mutex g_mutex;
std::atomic<bool> g_running{false};
std::atomic<uint64_t> g_frames{0};
std::thread g_thread;
OHNativeWindow* g_window = nullptr;
void* g_mpv_handle = nullptr;
MpvRenderApi g_api;
int g_width = 0;
int g_height = 0;

void Log(const char* message) {
  OH_LOG_Print(LOG_APP, LOG_INFO, kDomain, kTag, "[%{public}s]", message);
}

void LogValue(const char* message, int64_t value) {
  OH_LOG_Print(LOG_APP, LOG_INFO, kDomain, kTag, "[%{public}s %{public}lld]",
               message, value);
}

bool BindMpvApi() {
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
  return true;
}

GLuint CompileShader(GLenum type, const char* source) {
  GLuint shader = glCreateShader(type);
  glShaderSource(shader, 1, &source, nullptr);
  glCompileShader(shader);
  GLint ok = GL_FALSE;
  glGetShaderiv(shader, GL_COMPILE_STATUS, &ok);
  if (!ok) {
    glDeleteShader(shader);
    return 0;
  }
  return shader;
}

GLuint BuildProgram() {
  static constexpr char vs[] =
      "#version 300 es\nlayout(location=0) in vec2 p;layout(location=1) in "
      "vec2 t;out vec2 uv;void main(){uv=t;gl_Position=vec4(p,0,1);}";
  static constexpr char fs[] =
      "#version 300 es\nprecision mediump float;in vec2 uv;uniform sampler2D "
      "frame;out vec4 c;void main(){c=vec4(texture(frame,uv).rgb,1.0);}";
  GLuint v = CompileShader(GL_VERTEX_SHADER, vs);
  GLuint f = CompileShader(GL_FRAGMENT_SHADER, fs);
  if (!v || !f) return 0;
  GLuint program = glCreateProgram();
  glAttachShader(program, v);
  glAttachShader(program, f);
  glLinkProgram(program);
  glDeleteShader(v);
  glDeleteShader(f);
  GLint ok = GL_FALSE;
  glGetProgramiv(program, GL_LINK_STATUS, &ok);
  if (!ok) {
    glDeleteProgram(program);
    return 0;
  }
  return program;
}

// Renders one software frame and blits it. EGL context must be current.
bool RenderOnce(void* render_context, std::vector<uint8_t>* pixels,
                GLuint texture, GLuint program, GLuint vbo) {
  int size[2] = {g_width, g_height};
  size_t stride = static_cast<size_t>(g_width) * 4;
  void* pointer = pixels->data();
  void* format = const_cast<char*>(kSwFormatRgba);
  MpvRenderParam params[] = {
      {kParamApiType, const_cast<char*>(kApiTypeSw)},
      {kParamSwSize, size},
      {kParamSwFormat, format},
      {kParamSwStride, &stride},
      {kParamSwPointer, pointer},
      {kParamInvalid, nullptr},
  };
  if (g_api.render_context_render(render_context, params) < 0) {
    Log("mpv software render failed");
    return false;
  }

  glBindTexture(GL_TEXTURE_2D, texture);
  glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, g_width, g_height, GL_RGBA,
                  GL_UNSIGNED_BYTE, pixels->data());
  glViewport(0, 0, g_width, g_height);
  glClearColor(0, 0, 0, 1);
  glClear(GL_COLOR_BUFFER_BIT);
  glUseProgram(program);
  glActiveTexture(GL_TEXTURE0);
  glBindTexture(GL_TEXTURE_2D, texture);
  glUniform1i(glGetUniformLocation(program, "frame"), 0);
  glBindBuffer(GL_ARRAY_BUFFER, vbo);
  glEnableVertexAttribArray(0);
  glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 4 * sizeof(float), nullptr);
  glEnableVertexAttribArray(1);
  glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, 4 * sizeof(float),
                        reinterpret_cast<void*>(2 * sizeof(float)));
  glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
  glDisableVertexAttribArray(0);
  glDisableVertexAttribArray(1);
  return true;
}

void RenderLoop() {
  Log("RL: entry");
  EGLDisplay display = eglGetDisplay(EGL_DEFAULT_DISPLAY);
  Log("RL: display got");
  if (display == EGL_NO_DISPLAY || !eglInitialize(display, nullptr, nullptr)) {
    g_running.store(false);
    Log("eglInitialize failed");
    return;
  }
  Log("RL: egl initialized");
  const EGLint attrs[] = {EGL_SURFACE_TYPE,      EGL_WINDOW_BIT,
                          EGL_RENDERABLE_TYPE,   EGL_OPENGL_ES3_BIT,
                          EGL_RED_SIZE,          8,
                          EGL_GREEN_SIZE,        8,
                          EGL_BLUE_SIZE,         8,
                          EGL_ALPHA_SIZE,        8,
                          EGL_NONE};
  EGLConfig config = nullptr;
  EGLint count = 0;
  if (!eglChooseConfig(display, attrs, &config, 1, &count) || count != 1) {
    g_running.store(false);
    Log("eglChooseConfig failed");
    return;
  }
  Log("RL: config chosen");
  const EGLint context_attrs[] = {EGL_CONTEXT_CLIENT_VERSION, 3, EGL_NONE};
  EGLContext context =
      eglCreateContext(display, config, EGL_NO_CONTEXT, context_attrs);
  EGLSurface surface = eglCreateWindowSurface(
      display, config, reinterpret_cast<EGLNativeWindowType>(g_window),
      nullptr);
  if (context == EGL_NO_CONTEXT || surface == EGL_NO_SURFACE ||
      !eglMakeCurrent(display, surface, surface, context)) {
    g_running.store(false);
    Log("EGL setup failed");
    return;
  }
  Log("RL: makecurrent ok");
  Log("EGL context ready");

  void* render_context = nullptr;
  MpvRenderParam create_params[] = {
      {kParamApiType, const_cast<char*>(kApiTypeSw)},
      {kParamInvalid, nullptr},
  };
  if (g_api.render_context_create(&render_context, g_mpv_handle,
                                  create_params) < 0) {
    g_running.store(false);
    Log("mpv_render_context_create(sw) failed");
    return;
  }
  Log("RL: sw render ctx created");
  Log("mpv sw render context created");

  Log("RL: building program");
  GLuint program = BuildProgram();
  GLuint texture = 0;
  GLuint vbo = 0;
  const float vertices[] = {-1, -1, 0, 1, 1, -1, 1, 1, -1, 1, 0, 0, 1, 1, 1, 0};
  glGenBuffers(1, &vbo);
  glBindBuffer(GL_ARRAY_BUFFER, vbo);
  glBufferData(GL_ARRAY_BUFFER, sizeof(vertices), vertices, GL_STATIC_DRAW);
  glGenTextures(1, &texture);
  glBindTexture(GL_TEXTURE_2D, texture);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);

  std::vector<uint8_t> pixels;
  uint64_t rendered = 0;
  while (g_running.load()) {
    // Follow the consumer window geometry every frame: the Dart side resizes
    // the texture buffer when video parameters arrive.
    int w = 0;
    int h = 0;
    if (OH_NativeWindow_NativeWindowHandleOpt(g_window, GET_BUFFER_GEOMETRY,
                                              &h, &w) == 0 && w > 0 && h > 0) {
      g_width = w;
      g_height = h;
    }
    if (g_width <= 0 || g_height <= 0) {
      std::this_thread::sleep_for(std::chrono::milliseconds(30));
      continue;
    }
    const size_t needed =
        static_cast<size_t>(g_width) * static_cast<size_t>(g_height) * 4;
    if (pixels.size() != needed) {
      pixels.assign(needed, 0);
      glBindTexture(GL_TEXTURE_2D, texture);
      glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, g_width, g_height, 0, GL_RGBA,
                   GL_UNSIGNED_BYTE, pixels.data());
      LogValue("buffer sized", needed);
    }

    if (!RenderOnce(render_context, &pixels, texture, program, vbo)) break;
    if ((rendered % 30) == 0) { LogValue("RL: frame swapped", rendered + 1); }
    if (!eglSwapBuffers(display, surface)) {
      Log("eglSwapBuffers failed");
      break;
    }
    g_frames.store(++rendered);
    std::this_thread::sleep_for(std::chrono::milliseconds(30));
  }

  glDeleteTextures(1, &texture);
  glDeleteBuffers(1, &vbo);
  if (program) glDeleteProgram(program);
  if (render_context) g_api.render_context_free(render_context);
  eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
  eglDestroySurface(display, surface);
  eglDestroyContext(display, context);
  Log("sw render loop stopped");
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
  if (OH_NativeWindow_CreateNativeWindowFromSurfaceId(
          static_cast<uint64_t>(surface_id), &g_window) != 0 ||
      !g_window) {
    Log("native window from surface id failed");
    return -4;
  }
  g_width = g_height = 0;
  g_frames.store(0);
  g_running.store(true);
  g_thread = std::thread(RenderLoop);
  LogValue("sw renderer started, mpv handle", mpv_handle);
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
  LogValue("sw renderer stopped, frames", static_cast<int64_t>(g_frames.load()));
}

int64_t mk_sw_frames(void) { return static_cast<int64_t>(g_frames.load()); }

}  // extern "C"
