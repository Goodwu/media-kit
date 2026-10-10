// Vendor dataspace apply path for the Huawei LYA-AL00 test device, moved
// out of media_kit_hdr_lab as a controlled deliverable (requirement R5).
//
// A4 architecture decision 3: this file keeps the generic entry channel —
// the LYA private-window path below and the JNI registrations — while the
// LG firmware metadata adapter (window/hook gates, EGL capability
// re-checks, perform/query slot logic, YUV diag arm state, mkvendor_*
// exports) lives in lg_fw_adapter.cpp and is only delegated to. Diagnostics
// probes (late PQ, EGL HDR, Vulkan HDR) intentionally do NOT live in this
// package — they stay in the hdr_lab test app's own .so.
//
// The Java gate (SDK == 29 + exact fingerprint + BT2020_PQ) runs before this
// code is ever reached; the checks below are defense in depth, not the gate.
//
// E1 exception (MKSURF-E1, producer-commit-boundary injection experiment):
// mkvendor_set_diag_dataspace / mkvendor_apply_diag_to_window (lg_fw_adapter.cpp)
// re-run the exact same gated LG set path, but at the mpv EGL producer's window
// creation point instead of the Java surfaceCreated/binding point. The
// dataspace VALUE never changes (the lab arms 0x11C60000 = BT2020 PQ /
// LIMITED, the same value the Java path applies); only the injection
// point/timing moves. It is a lab switch: the diag atomic defaults to 0 and
// a 0 value makes every export a strict no-op, so default builds are
// bit-identical in behavior to before. This is not a new diagnostics probe;
// the probes themselves still live in the hdr_lab test app's own .so.
#include <jni.h>
#include <android/native_window.h>
#include <android/native_window_jni.h>
#include <android/hardware_buffer.h>
#include <android/data_space.h>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <dlfcn.h>
#include <android/log.h>
#include <sys/system_properties.h>

#include "lg_fw_adapter.h"

static bool lyaPqWindow(ANativeWindow* window) {
  char sdk[PROP_VALUE_MAX] = {};
  char fingerprint[PROP_VALUE_MAX] = {};
  return ANativeWindow_getFormat(window) == AHARDWAREBUFFER_FORMAT_R10G10B10A2_UNORM &&
      __system_property_get("ro.build.version.sdk", sdk) > 0 &&
      std::strcmp(sdk, "29") == 0 &&
      __system_property_get("ro.build.fingerprint", fingerprint) > 0 &&
      std::strcmp(fingerprint,
          "HUAWEI/LYA-AL00/HWLYA:10/HUAWEILYA-AL00/10.1.0.163C00:user/release-keys") == 0;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_alexmercerind_media_1kit_1android_1dataspace_1vendor_LyaPqDataSpaceExt_nativeApplyPqDataSpace(
    JNIEnv* env, jclass, jobject surface) {
  if (surface == nullptr) return JNI_FALSE;
  ANativeWindow* window = ANativeWindow_fromSurface(env, surface);
  if (window == nullptr) return JNI_FALSE;
  jboolean applied = JNI_FALSE;
  if (lyaPqWindow(window)) {
    void* library = dlopen("libandroid.so", RTLD_NOW | RTLD_LOCAL);
    using GetBuffersDataSpace = int32_t (*)(ANativeWindow*);
    const auto get_dataspace = library == nullptr ? nullptr
        : reinterpret_cast<GetBuffersDataSpace>(
            dlsym(library, "ANativeWindow_getBuffersDataSpace"));
    // This firmware's public setter rejects PQ during its HDR support
    // query, before reaching the window setter. The private ABI is confined
    // to the exact arm64 firmware and 10-bit window proven by the device
    // probe.
#if defined(__aarch64__)
    using WindowPerform = int (*)(ANativeWindow*, int, ...);
    WindowPerform perform = nullptr;
    std::memcpy(&perform,
        reinterpret_cast<const char*>(window) + 0x98, sizeof(perform));
    const int fallback_result = perform == nullptr
        ? -1 : perform(window, 19, ADATASPACE_BT2020_PQ);
    const int32_t actual = get_dataspace == nullptr ? -1 : get_dataspace(window);
    __android_log_print(ANDROID_LOG_INFO, "media_kit_vendor_ext",
        "p5PqFirmwareFallback perform=%d actual=%d expected=%d",
        fallback_result, actual, ADATASPACE_BT2020_PQ);
    if (fallback_result == 0 && actual == ADATASPACE_BT2020_PQ) applied = JNI_TRUE;
#endif
    if (library != nullptr) dlclose(library);
  }
  ANativeWindow_release(window);
  return applied;
}

// ---------------------------------------------------------------------------
// LG JNI registrations (A4 module split): the LG firmware adapter lives in
// lg_fw_adapter.cpp; these entries keep their exact JNI signatures and
// delegate to it, so the exported Java surface is unchanged. The host gate
// test (lg_native_gate_host_test.py) compiles this section together with the
// adapter. Extraction marker: LG JNI registrations:
extern "C" JNIEXPORT jboolean JNICALL
Java_com_alexmercerind_media_1kit_1android_1dataspace_1vendor_LgPqDataSpaceExt_nativeApplyPqDataSpace(
    JNIEnv* env, jclass clazz, jobject surface, jint dataSpace, jboolean visual278Experiment) {
  return lgfw::nativeApplyPqDataSpace(env, clazz, surface, dataSpace,
      visual278Experiment);
}

extern "C" JNIEXPORT void JNICALL
Java_com_alexmercerind_media_1kit_1android_1dataspace_1vendor_LgPqDataSpaceExt_nativeSetYuvDiagEnabled(
    JNIEnv*, jclass, jint enabled) {
  mkvendor_set_yuv_diag_enabled(enabled);
}

extern "C" JNIEXPORT void JNICALL
Java_com_alexmercerind_media_1kit_1android_1dataspace_1vendor_LgPqDataSpaceExt_nativeArmYuvDiag(
    JNIEnv*, jclass, jlong owner_key, jint generation) {
  mkvendor_arm_yuv_diag(static_cast<uint64_t>(owner_key),
      static_cast<uint32_t>(generation));
}

extern "C" JNIEXPORT void JNICALL
Java_com_alexmercerind_media_1kit_1android_1dataspace_1vendor_LgPqDataSpaceExt_nativeDisarmYuvDiag(
    JNIEnv*, jclass) {
  mkvendor_disarm_yuv_diag();
}

// P8.4 A5 V2 review fix: read-only binding snapshot for the Java-side
// authorization-termination rule (revoke/clear/unregister must disarm a
// matching arm). Returns long[2]{owner_key, generation} while armed, null
// when disarmed. Additive JNI entry; the pre-existing entries above keep
// their exact signatures.
extern "C" JNIEXPORT jlongArray JNICALL
Java_com_alexmercerind_media_1kit_1android_1dataspace_1vendor_LgPqDataSpaceExt_nativeYuvDiagBinding(
    JNIEnv* env, jclass) {
  uint64_t owner_key = 0;
  uint32_t generation = 0;
  if (mkvendor_yuv_diag_binding(&owner_key, &generation) == 0) return nullptr;
  jlongArray out = env->NewLongArray(2);
  if (out == nullptr) return nullptr;
  const jlong values[2] = {static_cast<jlong>(owner_key),
                           static_cast<jlong>(generation)};
  env->SetLongArrayRegion(out, 0, 2, values);
  return out;
}
