#include <jni.h>
#include <android/native_window.h>
#include <android/native_window_jni.h>
#include <android/data_space.h>
#include <android/hardware_buffer.h>
#include <cstdint>
#include <android/log.h>
#include <dlfcn.h>
#include <chrono>

extern "C" JNIEXPORT jboolean JNICALL
Java_com_alexmercerind_media_1kit_1video_platformview_PlatformVideoView_setSurfaceDataSpace(
    JNIEnv* env, jclass, jobject surface, jint dataspace,
    jboolean probe_srgb_on_failure) {
  if (surface == nullptr) return JNI_FALSE;

  ANativeWindow* window = ANativeWindow_fromSurface(env, surface);
  if (window == nullptr) return JNI_FALSE;


  // The symbol was added in API 28, while this plugin supports older Android
  // releases. Resolve it at runtime so loading the plugin remains safe there.
  void* library = dlopen("libandroid.so", RTLD_NOW | RTLD_LOCAL);
  using SetBuffersDataSpace = int (*)(ANativeWindow*, int32_t);
  const auto set_buffers_dataspace = library == nullptr
      ? nullptr
      : reinterpret_cast<SetBuffersDataSpace>(
          dlsym(library, "ANativeWindow_setBuffersDataSpace"));
  int result = set_buffers_dataspace == nullptr
      ? -1
      : set_buffers_dataspace(window, dataspace);
  const int public_result = result;
  using GetBuffersDataSpace = int32_t (*)(ANativeWindow*);
  const auto get_buffers_dataspace = library == nullptr
      ? nullptr
      : reinterpret_cast<GetBuffersDataSpace>(
          dlsym(library, "ANativeWindow_getBuffersDataSpace"));
  int32_t actual_dataspace = get_buffers_dataspace == nullptr
      ? -1
      : get_buffers_dataspace(window);

  // Vendor-private dataspace retries live out of tree: the Java side calls
  // the registered PlatformVideoView.SurfaceDataSpaceExt when this public
  // NDK path rejects the dataspace. This bridge only ever uses public APIs.

  int srgb_probe_result = -1;
  int reset_result = -1;
  if (probe_srgb_on_failure == JNI_TRUE && result != 0 &&
      set_buffers_dataspace != nullptr) {
    srgb_probe_result = set_buffers_dataspace(window, ADATASPACE_SRGB);
    if (srgb_probe_result == 0) {
      reset_result = set_buffers_dataspace(window, ADATASPACE_UNKNOWN);
    }
  }

  actual_dataspace = get_buffers_dataspace == nullptr
      ? -1
      : get_buffers_dataspace(window);

  __android_log_print(
      ANDROID_LOG_INFO,
      "media_kit_hdr_bridge",
      "setBuffersDataSpace symbol=%s dataspace=%d publicResult=%d result=%d srgbProbe=%d resetUnknown=%d format=%d size=%dx%d actualDataspace=%d",
      set_buffers_dataspace == nullptr ? "missing" : "resolved",
      dataspace,
      public_result,
      result,
      srgb_probe_result,
      reset_result,
      ANativeWindow_getFormat(window),
      ANativeWindow_getWidth(window),
      ANativeWindow_getHeight(window),
      actual_dataspace);

  ANativeWindow_release(window);
  if (library != nullptr) dlclose(library);
  return result == 0 && (dataspace != ADATASPACE_BT2020_PQ ||
      actual_dataspace == dataspace) ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT jint JNICALL
Java_com_alexmercerind_media_1kit_1video_platformview_PlatformVideoView_getSurfaceDataSpace(
    JNIEnv* env, jclass, jobject surface) {
  if (surface == nullptr) return -1;
  ANativeWindow* window = ANativeWindow_fromSurface(env, surface);
  if (window == nullptr) return -1;
  void* library = dlopen("libandroid.so", RTLD_NOW | RTLD_LOCAL);
  using GetBuffersDataSpace = int32_t (*)(ANativeWindow*);
  const auto get_buffers_dataspace = library == nullptr ? nullptr
      : reinterpret_cast<GetBuffersDataSpace>(
          dlsym(library, "ANativeWindow_getBuffersDataSpace"));
  const int32_t actual = get_buffers_dataspace == nullptr
      ? -1
      : get_buffers_dataspace(window);
  if (library != nullptr) dlclose(library);
  ANativeWindow_release(window);
  return actual;
}

// Owner broker: clears the mpv wakeup callback from the Java side. A host
// that destroys the FlutterEngine without Dart-side disposal leaves mpv
// playing; when the Dart isolate teardown invalidates the NativeCallable
// trampoline registered as the wakeup callback, the next mpv wakeup would
// call freed executable memory. Clearing the callback at engine detach
// removes that native -> Dart edge while the trampoline is still mapped.
extern "C" JNIEXPORT void JNICALL
Java_com_alexmercerind_media_1kit_1video_MpvOwnerBroker_nativeClearWakeupCallback(
    JNIEnv*, jclass, jlong ctx) {
  void* libmpv = dlopen("libmpv.so", RTLD_NOLOAD | RTLD_NOW | RTLD_LOCAL);
  if (libmpv == nullptr) {
    __android_log_print(ANDROID_LOG_WARN, "media_kit_owner_broker",
                        "clearWakeup: libmpv not loaded");
    return;
  }
  using SetWakeupCallback = void (*)(void*, void (*)(void*), void*);
  const auto set_wakeup_callback =
      reinterpret_cast<SetWakeupCallback>(
          dlsym(libmpv, "mpv_set_wakeup_callback"));
  if (set_wakeup_callback == nullptr) {
    __android_log_print(ANDROID_LOG_WARN, "media_kit_owner_broker",
                        "clearWakeup: mpv_set_wakeup_callback unavailable");
    return;
  }
  set_wakeup_callback(reinterpret_cast<void*>(ctx), nullptr, nullptr);
  __android_log_print(ANDROID_LOG_INFO, "media_kit_owner_broker",
                      "clearWakeup: ctx=0x%llx",
                      static_cast<unsigned long long>(ctx));
}

// Owner broker: terminates and frees a native mpv handle from the Java side.
// Runs on the broker's background thread after the wakeup callback has been
// cleared, so no native -> Dart edge and no in-flight Dart call exists when
// mpv joins its own threads and releases the handle.
extern "C" JNIEXPORT void JNICALL
Java_com_alexmercerind_media_1kit_1video_MpvOwnerBroker_nativeTerminateDestroy(
    JNIEnv*, jclass, jlong ctx) {
  void* libmpv = dlopen("libmpv.so", RTLD_NOLOAD | RTLD_NOW | RTLD_LOCAL);
  if (libmpv == nullptr) {
    __android_log_print(ANDROID_LOG_WARN, "media_kit_owner_broker",
                        "terminate: libmpv not loaded");
    return;
  }
  using TerminateDestroy = void (*)(void*);
  const auto terminate_destroy =
      reinterpret_cast<TerminateDestroy>(
          dlsym(libmpv, "mpv_terminate_destroy"));
  if (terminate_destroy == nullptr) {
    __android_log_print(ANDROID_LOG_WARN, "media_kit_owner_broker",
                        "terminate: mpv_terminate_destroy unavailable");
    return;
  }
  __android_log_print(ANDROID_LOG_INFO, "media_kit_owner_broker",
                      "terminate begin: ctx=0x%llx",
                      static_cast<unsigned long long>(ctx));
  terminate_destroy(reinterpret_cast<void*>(ctx));
  __android_log_print(ANDROID_LOG_INFO, "media_kit_owner_broker",
                      "terminate complete: ctx=0x%llx",
                      static_cast<unsigned long long>(ctx));
}

// Pipeline probe: answers once per process whether the loaded mpv fork
// carries the P5 dovi rescale pipeline, through a read-only capability
// property on a disposable mpv instance (approved plan B, 2026-10-02).
//
// Why a disposable instance satisfies R1.1 (a capability query must never
// interfere with in-process EGL users): the probe instance is created with
// no vo and no surface, is never given any media, and only reads one
// property — it therefore never reaches eglInitialize/eglTerminate or any
// other interface that would disturb the EGL state of the process.
//
// Why RTLD_NOLOAD is safe: the plugin's onAttachedToEngine pins libmpv
// through System.loadLibrary("mpv") before the Java probe class runs, so
// the already-loaded library is always found here; the probe never loads
// libmpv itself.
//
// Return jint is three-state:
//   1  the fork property `dovi-p5-pipeline` is present and true — the P5
//      rescale pipeline is available;
//   0  unavailable: the property read failed (an upstream build has no such
//      property — a legitimate result, not an error) or the property is
//      false;
//  -1  mechanical probe failure: libmpv not loaded, a symbol missing, or
//      create/initialize failed. No verdict was reached; the Java side
//      consumes -1 conservatively as false.
// All mpv handles are void* and the format enum is hardcoded because this
// bridge does not link the libmpv client headers (libmpv is resolved at
// runtime through dlsym, like the owner broker above).
extern "C" JNIEXPORT jint JNICALL
Java_com_alexmercerind_media_1kit_1video_MpvPipelineProbe_nativeProbeP5Pipeline(
    JNIEnv*, jclass) {
  const auto begin = std::chrono::steady_clock::now();
  void* libmpv = dlopen("libmpv.so", RTLD_NOLOAD | RTLD_NOW | RTLD_LOCAL);
  if (libmpv == nullptr) {
    __android_log_print(ANDROID_LOG_WARN, "media_kit_pipeline_probe",
                        "probe: libmpv not loaded");
    return -1;
  }
  using Create = void* (*)(void);
  using SetOptionString = int (*)(void*, const char*, const char*);
  using Initialize = int (*)(void*);
  // MPV_FORMAT_FLAG == 3 per mpv client.h `mpv_format`; hardcoded because
  // this bridge never includes the libmpv headers.
  using GetProperty = int (*)(void*, const char*, int, void*);
  using TerminateDestroy = void (*)(void*);
  const auto create = reinterpret_cast<Create>(dlsym(libmpv, "mpv_create"));
  const auto set_option_string =
      reinterpret_cast<SetOptionString>(dlsym(libmpv, "mpv_set_option_string"));
  const auto initialize =
      reinterpret_cast<Initialize>(dlsym(libmpv, "mpv_initialize"));
  const auto get_property =
      reinterpret_cast<GetProperty>(dlsym(libmpv, "mpv_get_property"));
  const auto terminate_destroy =
      reinterpret_cast<TerminateDestroy>(dlsym(libmpv, "mpv_terminate_destroy"));
  if (create == nullptr || set_option_string == nullptr ||
      initialize == nullptr || get_property == nullptr ||
      terminate_destroy == nullptr) {
    __android_log_print(ANDROID_LOG_WARN, "media_kit_pipeline_probe",
                        "probe: mpv symbols unavailable create=%d option=%d init=%d property=%d terminate=%d",
                        create == nullptr, set_option_string == nullptr,
                        initialize == nullptr, get_property == nullptr,
                        terminate_destroy == nullptr);
    return -1;
  }

  void* ctx = create();
  if (ctx == nullptr) {
    __android_log_print(ANDROID_LOG_WARN, "media_kit_pipeline_probe",
                        "probe: mpv_create failed");
    return -1;
  }

  jint result = -1;
  int property_error = -1;
  int initialize_error = -1;
  // Closed instance: never read the user's mpv configuration file.
  const int config_error = set_option_string(ctx, "config", "no");
  if (config_error == 0) {
    initialize_error = initialize(ctx);
    if (initialize_error == 0) {
      int flag = 0;
      // A failed read means the loaded mpv has no such property (upstream
      // build): unavailable, a verdict — not a mechanical failure.
      property_error = get_property(ctx, "dovi-p5-pipeline", 3, &flag);
      result = property_error == 0 ? (flag != 0 ? 1 : 0) : 0;
    }
  }
  // Every path releases the disposable instance.
  terminate_destroy(ctx);

  const auto elapsed_ms = std::chrono::duration_cast<std::chrono::milliseconds>(
      std::chrono::steady_clock::now() - begin).count();
  __android_log_print(ANDROID_LOG_INFO, "media_kit_pipeline_probe",
                      "probe: result=%d config=%d initialize=%d property=%d elapsedMs=%lld",
                      result, config_error, initialize_error, property_error,
                      static_cast<long long>(elapsed_ms));
  return result;
}
