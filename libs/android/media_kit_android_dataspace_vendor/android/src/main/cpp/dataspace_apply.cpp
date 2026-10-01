// Vendor dataspace apply path for the Huawei LYA-AL00 test device, moved
// out of media_kit_hdr_lab as a controlled deliverable (requirement R5).
//
// This is the ONLY native code in the vendor subpackage. The private window
// ABI (perform op 19) is confined here to the exact arm64 firmware and a
// 10-bit window, and every application is verified by reading the dataspace
// back. Diagnostics probes (late PQ, EGL HDR, Vulkan HDR) intentionally do
// NOT live here — they stay in the hdr_lab test app's own .so.
//
// The Java gate (SDK == 29 + exact fingerprint + BT2020_PQ) runs before this
// code is ever reached; the checks below are defense in depth, not the gate.
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
