// LG firmware metadata adapter (A4 architecture decision 3: the "exact
// firmware metadata adapter" responsibility, isolated from the generic
// dataspace channel in dataspace_apply.cpp). Everything LG-specific lives
// here: the window/hook gates, the public-EGL capability re-checks, the
// gated perform/query slot logic, the E1 producer injection exports, and the
// YUV diag binding arm state.
//
// Pure file reorganization: exported symbol names, JNI signatures, behavior
// and log strings are unchanged from the pre-split single-file build. The
// host gate test (lg_native_gate_host_test.py) compiles this file together
// with the JNI registrations in dataspace_apply.cpp; the YUV diag window
// branch is armed-context only and every gate keeps its fail-closed refusal.
#include "lg_fw_adapter.h"

#include <android/log.h>
#include <android/native_window.h>
#include <android/native_window_jni.h>
#include <sys/system_properties.h>
#include <EGL/egl.h>

#include <atomic>
#include <cstdint>
#include <cstring>
#include <dlfcn.h>
#include <vector>

// Vendor dataspace apply path for the LG lucye (Android 7.0/API 24) test
// device. Same discipline as the LYA path in dataspace_apply.cpp: read-only
// Java gate runs first, and the native side re-verifies the opaque-struct
// slot layout via the harmless query(FORMAT) hook before any perform call.
// The LGE-custom layout (probe evidence lg-dataspace-probe-r32) puts query at
// 0x90 and perform at 0x98; Android 7.0 has no GET message. Hook/format
// checks are ABI safety checks; perform success proves setter acceptance,
// not readback.
// Local logcat only: pointer identities are not exported in channel reports.
static void lgPqDiagnostic(const char* stage, const char* reason,
    jobject surface, ANativeWindow* window, int format, jint dataSpace) {
  __android_log_print(ANDROID_LOG_INFO, "media_kit_vendor_ext",
      "lgPqApply stage=%s reason=%s surfaceRef=%p window=%p format=%d/0x%x dataSpace=%d/0x%x",
      stage, reason, reinterpret_cast<void*>(surface), window, format,
      static_cast<unsigned int>(format), static_cast<int>(dataSpace),
      static_cast<unsigned int>(dataSpace));
}

// Observe only an already-initialized default display (the producer owns
// its lifecycle). Never initialize/terminate it or create a context here.
static bool lgVisual278ConfigMatches(const EGLint* values) {
  return values[0] == 278 && values[1] == 10 && values[2] == 10 &&
      values[3] == 10 && values[4] == 2 && (values[5] & EGL_WINDOW_BIT) &&
      (values[6] & EGL_OPENGL_ES2_BIT) && (values[6] & 0x40 /* ES3 */) &&
      values[7] == EGL_NON_CONFORMANT_CONFIG;
}

static bool lgVisual278Capability() {
  const EGLDisplay display = eglGetDisplay(EGL_DEFAULT_DISPLAY);
  EGLint count = 0;
  if (display == EGL_NO_DISPLAY || !eglGetConfigs(display, nullptr, 0, &count) ||
      count <= 0 || count > 1024) return false;
  std::vector<EGLConfig> configs(count);
  EGLint actual = 0;
  if (!eglGetConfigs(display, configs.data(), count, &actual) ||
      actual <= 0 || actual > count) return false;
  for (int i = 0; i < actual; ++i) {
    const EGLint attrs[] = {EGL_NATIVE_VISUAL_ID, EGL_RED_SIZE, EGL_GREEN_SIZE,
        EGL_BLUE_SIZE, EGL_ALPHA_SIZE, EGL_SURFACE_TYPE, EGL_RENDERABLE_TYPE,
        EGL_CONFIG_CAVEAT, EGL_CONFIG_ID};
    EGLint values[9] = {};
    bool read = true;
    for (int a = 0; a < 9; ++a) {
      if (!eglGetConfigAttrib(display, configs[i], attrs[a], &values[a])) {
        read = false;
        break;
      }
    }
    if (read && lgVisual278ConfigMatches(values)) {
      __android_log_print(ANDROID_LOG_INFO, "media_kit_vendor_ext",
          "lgPqApply visual278 experimental capability config=%d bits=10/10/10/2 caveat=NON_CONFORMANT acceptedExperimentally=true verified=false",
          values[8]);
      return true;
    }
  }
  return false;
}

// MKS YUV diag (config49): public-EGL capability re-verification for the NV12
// window format 0x7FA30C04 (Gate-1a probed as YUV configs 49-52 on this
// device). Independent of lgVisual278Capability: the YUV diag branch is its
// own experiment and never inherits the visual278 authorization. The tokens
// are local (same values as the yuv_config_probe.c forensics).
#ifndef EGL_YUV_BUFFER_EXT
#define EGL_YUV_BUFFER_EXT 0x3300
#endif
static constexpr int kMksYuvNv12Format = 0x7FA30C04;

// c1: YUV diag authorization state, one source for BOTH entries (producer
// dlsym path and JNI path). [g_yuv_diag_format] records the expected window
// format at arm time (fixed by the diag design to the config49 NV12 format),
// so the format gates verify the window against the recorded expectation and
// not just against the armed flag.
static std::atomic<int32_t> g_yuv_diag_enabled{0}; // 0 = off.
static std::atomic<int32_t> g_yuv_diag_format{0};  // 0 = not recorded.
// c1-owner: the owner tuple that armed the flag through the bound-arm entry
// (mkvendor_arm_yuv_diag). The tuple 0/0 means "no owner binding" — the
// legacy unbound arm (mkvendor_set_yuv_diag_enabled). The owner_key is the
// FNV-1a64 of the owner token computed Java-side; the raw token is never
// stored natively. Pure advisory record: the window gates keep verifying the
// flag, the arm-time format and the public-EGL capability.
static std::atomic<uint64_t> g_yuv_diag_owner_key{0};
static std::atomic<uint32_t> g_yuv_diag_generation{0};

static bool lgYuvConfig49Capability() {
  const EGLDisplay display = eglGetDisplay(EGL_DEFAULT_DISPLAY);
  EGLint count = 0;
  if (display == EGL_NO_DISPLAY || !eglGetConfigs(display, nullptr, 0, &count) ||
      count <= 0 || count > 1024) return false;
  std::vector<EGLConfig> configs(count);
  EGLint actual = 0;
  if (!eglGetConfigs(display, configs.data(), count, &actual) ||
      actual <= 0 || actual > count) return false;
  for (int i = 0; i < actual; ++i) {
    EGLint vid = 0, type = 0, id = 0;
    if (!eglGetConfigAttrib(display, configs[i], EGL_NATIVE_VISUAL_ID, &vid) ||
        !eglGetConfigAttrib(display, configs[i], EGL_COLOR_BUFFER_TYPE,
            &type) ||
        !eglGetConfigAttrib(display, configs[i], EGL_CONFIG_ID, &id)) {
      continue;
    }
    if (vid == kMksYuvNv12Format && type == EGL_YUV_BUFFER_EXT) {
      __android_log_print(ANDROID_LOG_INFO, "media_kit_vendor_ext",
          "lgPqApply yuv-config49 capability config=%d format=0x%x yuvBuffer=true acceptedExperimentally=true verified=false",
          id, static_cast<unsigned int>(kMksYuvNv12Format));
      return true;
    }
  }
  return false;
}

static const char* lgPqWindowRefusal(ANativeWindow* window, int* format,
    bool visual278Experiment, bool yuvDiagExperiment) {
#if defined(__aarch64__)
  char sdk[PROP_VALUE_MAX] = {};
  char fingerprint[PROP_VALUE_MAX] = {};
  char model[PROP_VALUE_MAX] = {};
  if (sizeof(void*) != 8) return "process-pointer-size";
  if (__system_property_get("ro.product.model", model) <= 0) return "model-missing";
  if (std::strcmp(model, "LG-H870DS") != 0) return "model-mismatch";
  *format = ANativeWindow_getFormat(window);
  if (*format != AHARDWAREBUFFER_FORMAT_R10G10B10A2_UNORM &&
      !(visual278Experiment && *format == 278) &&
      !(yuvDiagExperiment && *format == kMksYuvNv12Format)) {
    return "window-format-not-43-experiment-disabled-or-unsupported";
  }
  if (__system_property_get("ro.build.version.sdk", sdk) <= 0) return "sdk-missing";
  if (std::strcmp(sdk, "24") != 0) return "sdk-mismatch";
  if (__system_property_get("ro.build.fingerprint", fingerprint) <= 0) return "fingerprint-missing";
  if (std::strcmp(fingerprint,
      "lge/lucye_global_com/lucye:7.0/NRD90U/172921900e77a:user/release-keys") != 0) {
    return "fingerprint-mismatch";
  }
  if (*format == 278 && !lgVisual278Capability()) return "visual278-public-egl-capability-unavailable";
  if (*format == kMksYuvNv12Format && !lgYuvConfig49Capability()) {
    return "yuv-config49-public-egl-capability-unavailable";
  }
  if (yuvDiagExperiment && *format == kMksYuvNv12Format &&
      g_yuv_diag_format.load(std::memory_order_relaxed) != *format) {
    // The window carries the diag format but the arm-time record disagrees:
    // refuse rather than trusting the flag alone.
    return "yuv-diag-expected-format-mismatch";
  }
  return nullptr;
#else
  return "process-not-aarch64";
#endif
}

// Check executable ownership before calling even the query slot. A plausible
// address and a successful query alone do not prove a private window layout.
static const char* lgHookPairRefusal(void* query, void* perform) {
  Dl_info q = {}, p = {};
  if (query == nullptr) return "query-hook-null";
  if (perform == nullptr) return "perform-hook-null";
  if (dladdr(query, &q) == 0) return "query-hook-owner-unresolved";
  if (dladdr(perform, &p) == 0) return "perform-hook-owner-unresolved";
  if (q.dli_fbase != p.dli_fbase) return "hook-owner-base-mismatch";
  if (q.dli_fname == nullptr || p.dli_fname == nullptr) return "hook-owner-name-null";
  if (std::strcmp(q.dli_fname, "/system/lib64/libgui.so") != 0) return "query-hook-owner-mismatch";
  if (std::strcmp(p.dli_fname, "/system/lib64/libgui.so") != 0) return "perform-hook-owner-mismatch";
  if (reinterpret_cast<uintptr_t>(perform) !=
      reinterpret_cast<uintptr_t>(query) + 0x18) return "hook-offset-mismatch";
  return nullptr;
}

// Internal set path shared by the JNI entry and the E1 diag injection:
// everything after an ANativeWindow* is already in hand (no fromSurface and
// no release here — the caller owns the window reference). Returns 1 when the
// gated perform was applied, 0 when a gate refused or the perform was not
// invoked. [surfaceForLog] is only the existing local-logcat diagnostic
// reference and may be null on the non-JNI (E1) path.
static int lgApplyPqDataSpaceToWindow(ANativeWindow* window,
    jobject surfaceForLog, jint dataSpace, bool visual278Experiment,
    bool yuvDiagExperiment) {
  int windowFormat = -999; // Not sampled when an earlier gate short-circuits.
  const char* refusal = (dataSpace == 0x09c60000 || dataSpace == 0x11c60000)
      ? lgPqWindowRefusal(window, &windowFormat, visual278Experiment,
            yuvDiagExperiment) : "dataspace-not-whitelisted";
  lgPqDiagnostic(refusal == nullptr ? "device-window-gate" : "refused",
      refusal == nullptr ? "accepted" : refusal, surfaceForLog, window, windowFormat, dataSpace);
  if (refusal != nullptr) return 0;
  // c2: dual-layer range contract. In YUV diag mode the window dataspace
  // label is FORCED to PQ/LIMITED (0x11C60000) regardless of the requested PQ
  // variant: the RGBA16F offscreen carries FULL-range normalized PQ for the
  // layout(yuv) shader to sample, and the final NV12 window must stay
  // LIMITED with the 0x11C60000 producer state. A second session dataspace
  // request with PQ/FULL (0x09C60000) arriving through the Java path must
  // not override it.
  const jint performDataSpace = yuvDiagExperiment
      ? static_cast<jint>(0x11c60000) : dataSpace;
  if (performDataSpace != dataSpace) {
    __android_log_print(ANDROID_LOG_INFO, "media_kit_vendor_ext",
        "lgPqApply stage=yuv-diag-range-lock requested=0x%x applied=0x11c60000 "
        "reason=dual-layer-contract-offscreen-full-window-limited",
        static_cast<unsigned int>(dataSpace));
  }
  const uint8_t* base = reinterpret_cast<const uint8_t*>(window);
  void* queryPtr = nullptr;
  void* performPtr = nullptr;
  std::memcpy(&queryPtr, base + 0x90, sizeof(queryPtr));
  std::memcpy(&performPtr, base + 0x98, sizeof(performPtr));
  const uintptr_t q = reinterpret_cast<uintptr_t>(queryPtr);
  const uintptr_t pf = reinterpret_cast<uintptr_t>(performPtr);
  // Android arm64 shared-library code addresses live around 0x7xxxxxxxxx.
  const bool plausible =
      queryPtr != nullptr && performPtr != nullptr &&
      q >= 0x7000000000ULL && q < 0x8000000000ULL &&
      pf >= 0x7000000000ULL && pf < 0x8000000000ULL;
  const char* hookRefusal = plausible
      ? lgHookPairRefusal(queryPtr, performPtr) : "hook-address-not-plausible";
  __android_log_print(ANDROID_LOG_INFO, "media_kit_vendor_ext",
      "lgPqApply stage=hook-gate window=%p query=%p perform=%p reason=%s",
      window, queryPtr, performPtr, hookRefusal == nullptr ? "accepted" : hookRefusal);
  if (hookRefusal != nullptr) {
    __android_log_print(ANDROID_LOG_WARN, "media_kit_vendor_ext",
        "lgPqApply stage=refused window=%p reason=%s; refusing to call",
        window, hookRefusal);
    return 0;
  }
  using QueryFn = int (*)(const ANativeWindow*, int, int*);
  int format = -999;
  const int qret =
      reinterpret_cast<QueryFn>(queryPtr)(window, 2 /* FORMAT */, &format);
  lgPqDiagnostic("query", qret != 0 ? "query-failed" :
      format != windowFormat ? "query-window-format-mismatch" : "accepted",
      surfaceForLog, window, format, dataSpace);
  using PerformFn = int (*)(ANativeWindow*, int, ...);
  // 19 = NATIVE_WINDOW_SET_BUFFERS_DATASPACE (AOSP standard).
  const int result = qret == 0 &&
          format == windowFormat
      ? reinterpret_cast<PerformFn>(performPtr)(
            window, 19, static_cast<int>(performDataSpace))
      : -1;
  __android_log_print(ANDROID_LOG_INFO, "media_kit_vendor_ext",
      "lgPqApply stage=perform window=%p qret=%d format=%d perform=%d invoked=%d dataSpace=%d reason=%s",
      window, qret, format, result,
      qret == 0 && format == windowFormat,
      static_cast<int>(performDataSpace),
      qret != 0 || format != windowFormat
          ? "not-invoked" : result == 0 ? "setter-accepted-no-readback" : "perform-failed");
  return (qret == 0 && result == 0) ? 1 : 0;
}

namespace lgfw {

// The exact body of the LgPqDataSpaceExt JNI entry (A4 split: the Java
// registration in dataspace_apply.cpp forwards here; gates, logs and the
// YUV diag state read are unchanged). c1: the JNI entry reads the same YUV
// diag state as the producer (dlsym) entry, so a Session dataspace request
// on the NV12 window is not refused by the format gate while the diag is
// armed. Known diagnostic-period limitation (reviewer-noted): the flag is
// process-global; while armed it authorizes any window whose format matches
// the arm-time recorded config49 NV12 format — it does not bind a specific
// window identity (the lab cannot know mpv's ANativeWindow). Exposure is
// bounded by the single-Session lab and the open-end disarm. All
// hardware/API24/fingerprint/format/EGL-capability gates still run inside
// lgApplyPqDataSpaceToWindow below.
jboolean nativeApplyPqDataSpace(JNIEnv* env, jclass clazz, jobject surface,
    jint dataSpace, jboolean visual278Experiment) {
  (void)clazz;
  if (surface == nullptr) {
    lgPqDiagnostic("refused", "surface-null", surface, nullptr, -999, dataSpace);
    return JNI_FALSE;
  }
  ANativeWindow* window = ANativeWindow_fromSurface(env, surface);
  if (window == nullptr) {
    lgPqDiagnostic("refused", "window-null", surface, window, -999, dataSpace);
    return JNI_FALSE;
  }
  const int applied =
      lgApplyPqDataSpaceToWindow(window, surface, dataSpace,
          visual278Experiment == JNI_TRUE,
          /*yuvDiagExperiment=*/g_yuv_diag_enabled.load(
              std::memory_order_relaxed) != 0);
  ANativeWindow_release(window);
  return applied != 0 ? JNI_TRUE : JNI_FALSE;
}

}  // namespace lgfw

// ---------------------------------------------------------------------------
// E1 (MKSURF-E1): producer-commit-boundary dataspace injection experiment.
// The arm value is stored in a plain atomic (0 = off, the default); the
// applier re-runs lgApplyPqDataSpaceToWindow — the exact same gated set path
// as the JNI channel above — on a window pointer the host already holds, so
// no ANativeWindow_fromSurface/acquire happens here. The
// visual278Experiment allowance is armed-context: the diag value is only
// armed by the LG visual278 lab flow, where the format-278 public EGL
// capability is still re-verified by lgPqWindowRefusal/lgVisual278Capability
// before any perform. Both exports are extern "C" JNIEXPORT so Dart FFI
// (mkvendor_set_diag_dataspace) and mpv's dlsym
// (mkvendor_apply_diag_to_window) can bind the same symbols.
static std::atomic<int32_t> g_diag_dataspace{0}; // 0 = off.

extern "C" JNIEXPORT void mkvendor_set_diag_dataspace(int32_t ds) {
  // Pure state store: no JNIEnv, no window access, safe from any thread.
  g_diag_dataspace.store(ds, std::memory_order_relaxed);
}

extern "C" JNIEXPORT int mkvendor_apply_diag_to_window(void* anw) {
  if (anw == nullptr) return 0;
  const int32_t ds = g_diag_dataspace.load(std::memory_order_relaxed);
  if (ds == 0) return 0; // Off: strict no-op, identical to the pre-E1 build.
  // The allowed dataspace set (0x09c60000 / 0x11c60000) is enforced again
  // inside the shared gate; anything else refuses there. The YUV diag flag
  // is armed-context only: the 0x7FA30C04 format allowance is re-verified
  // against the public EGL capability inside the shared gate.
  return lgApplyPqDataSpaceToWindow(static_cast<ANativeWindow*>(anw), nullptr,
      static_cast<jint>(ds), /*visual278Experiment=*/true,
      /*yuvDiagExperiment=*/g_yuv_diag_enabled.load(std::memory_order_relaxed) != 0);
}

// ---------------------------------------------------------------------------
// MKS YUV diag (phase3-decision, lab-gated, default off): independent
// authorization flag for the config49 8-bit NV12 output diagnostic branch.
// This deliberately does NOT inherit the visual278 authorization: it has its
// own runtime switch, its own public-EGL capability re-verification
// (lgYuvConfig49Capability below), and the dataspace VALUE is unchanged
// (0x11C60000 = BT2020 PQ / LIMITED). Both exports are extern "C" JNIEXPORT
// so Dart FFI (mkvendor_set_yuv_diag_enabled) and mpv's dlsym
// (mkvendor_yuv_diag_enabled) bind the same state; the default 0 keeps every
// consumer (including the new 0x7FA30C04 branch in lgPqWindowRefusal) a
// strict no-op identical to the pre-diag build. The atomic itself is declared
// next to g_diag_dataspace above.
extern "C" JNIEXPORT void mkvendor_set_yuv_diag_enabled(int32_t enabled) {
  // Pure state store: no JNIEnv, no window access, safe from any thread.
  g_yuv_diag_enabled.store(enabled ? 1 : 0, std::memory_order_relaxed);
  // c1: record (or clear) the expected window format at arm/disarm time; the
  // format gates verify the window against this record.
  g_yuv_diag_format.store(enabled ? kMksYuvNv12Format : 0,
      std::memory_order_relaxed);
  // c1-owner: the legacy entry arms WITHOUT an owner binding — clear any
  // tuple a previous bound arm left behind so the 0/0 convention (unbound)
  // holds for as long as this arm is active.
  g_yuv_diag_owner_key.store(0, std::memory_order_relaxed);
  g_yuv_diag_generation.store(0, std::memory_order_relaxed);
}

extern "C" JNIEXPORT int mkvendor_yuv_diag_enabled(void) {
  return g_yuv_diag_enabled.load(std::memory_order_relaxed);
}

// c1-owner revocation support (P8.4 A5 V2 review fix): read-only snapshot of
// the current arm state for the Java authorization-termination rule. The
// three loads are independent relaxed reads — the caller (Java, holding the
// extension monitor) only needs a coherent-enough view to decide a disarm,
// and the disarm itself is the authoritative mkvendor_disarm_yuv_diag call.
// Additive export: the frozen mkvendor_* contract above is unchanged and
// this symbol has no mpv/FFI binder (JNI registration only).
extern "C" JNIEXPORT int mkvendor_yuv_diag_binding(uint64_t* out_owner_key,
    uint32_t* out_generation) {
  if (out_owner_key == nullptr || out_generation == nullptr) return 0;
  *out_owner_key = g_yuv_diag_owner_key.load(std::memory_order_relaxed);
  *out_generation = g_yuv_diag_generation.load(std::memory_order_relaxed);
  return g_yuv_diag_enabled.load(std::memory_order_relaxed);
}

// c1-owner bound arm (A2 authorization model): records the owner tuple and
// arms in one store sequence. owner_key=0/generation=0 is the documented
// "unbound" tuple and is accepted as the exact legacy-arm equivalent — the
// flag, format record and capability gates are identical either way. Pure
// state store: no JNIEnv, no window access, safe from any thread.
extern "C" JNIEXPORT void mkvendor_arm_yuv_diag(uint64_t owner_key,
    uint32_t generation) {
  g_yuv_diag_owner_key.store(owner_key, std::memory_order_relaxed);
  g_yuv_diag_generation.store(generation, std::memory_order_relaxed);
  g_yuv_diag_enabled.store(1, std::memory_order_relaxed);
  g_yuv_diag_format.store(kMksYuvNv12Format, std::memory_order_relaxed);
  __android_log_print(ANDROID_LOG_INFO, "media_kit_vendor_ext",
      "yuvDiag arm bound=1 owner_key=%llu generation=%u format=0x%x",
      static_cast<unsigned long long>(owner_key),
      static_cast<unsigned int>(generation),
      static_cast<unsigned int>(kMksYuvNv12Format));
}

// c1-owner disarm: clears the armed flag, the arm-time format record AND the
// owner binding. Idempotent; the default (all-zero) state makes every
// consumer a strict no-op identical to the pre-diag build.
extern "C" JNIEXPORT void mkvendor_disarm_yuv_diag(void) {
  g_yuv_diag_enabled.store(0, std::memory_order_relaxed);
  g_yuv_diag_format.store(0, std::memory_order_relaxed);
  g_yuv_diag_owner_key.store(0, std::memory_order_relaxed);
  g_yuv_diag_generation.store(0, std::memory_order_relaxed);
  __android_log_print(ANDROID_LOG_INFO, "media_kit_vendor_ext",
      "yuvDiag disarm bound=0");
}
