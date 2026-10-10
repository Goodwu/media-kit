// LG firmware metadata adapter interface (A4 architecture decision 3: the
// "exact firmware metadata adapter" responsibility, isolated from the
// generic dataspace channel in dataspace_apply.cpp).
//
// Pure file reorganization: exported symbol names, JNI signatures, behavior
// and log strings are unchanged from the pre-split single-file build. The
// JNI registrations in dataspace_apply.cpp delegate here; the extern "C"
// mkvendor_* exports remain the frozen contract bound by Dart FFI and mpv's
// dlsym. The lgfw:: entry point is internal to this plugin (hidden
// visibility) and must not gain external binders.
#ifndef MEDIA_KIT_DATASPACE_VENDOR_LG_FW_ADAPTER_H_
#define MEDIA_KIT_DATASPACE_VENDOR_LG_FW_ADAPTER_H_

#include <jni.h>

#include <cstdint>

struct ANativeWindow;

namespace lgfw {

// The exact body of the LgPqDataSpaceExt JNI entry (same gates, same logs):
// takes the surface reference, runs the gated set path, releases the window.
__attribute__((visibility("hidden"))) jboolean nativeApplyPqDataSpace(
    JNIEnv* env, jclass clazz, jobject surface, jint dataSpace,
    jboolean visual278Experiment);

}  // namespace lgfw

extern "C" {

// Frozen export names; signatures and behavior are unchanged. Bound by Dart
// FFI (mkvendor_*) and mpv's dlsym.
void mkvendor_set_diag_dataspace(int32_t ds);
int mkvendor_apply_diag_to_window(void* anw);
void mkvendor_set_yuv_diag_enabled(int32_t enabled);
int mkvendor_yuv_diag_enabled(void);
void mkvendor_arm_yuv_diag(uint64_t owner_key, uint32_t generation);
void mkvendor_disarm_yuv_diag(void);

// ADDITIVE (P8.4 A5 V1 review fix, not part of the frozen contract above):
// read-only binding query for the Java-side authorization-termination rule.
// Returns 1 while the flag is armed and fills the current (owner_key,
// generation) binding (0/0 = legacy unbound arm); returns 0 when disarmed.
// Bound only by the in-process JNI registration; no mpv/FFI consumer.
int mkvendor_yuv_diag_binding(uint64_t* out_owner_key, uint32_t* out_generation);

}  // extern "C"

#endif  // MEDIA_KIT_DATASPACE_VENDOR_LG_FW_ADAPTER_H_
