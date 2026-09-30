#include <jni.h>
#include <android/native_window.h>
#include <android/native_window_jni.h>
#include <android/data_space.h>
#include <android/hardware_buffer.h>
#include <cstdint>
#include <android/log.h>
#include <dlfcn.h>

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
