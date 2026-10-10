// Native bridge for the opt-in "surfacetexture" hardware decoder backend
// (API 24+ SurfaceTexture full-GPU import), per phase1-design-spec §4 / §2.4.
//
// This translation unit is inert unless an owner explicitly initializes it;
// the default rendering route never calls into it and is unaffected.
// Exports:
//   - static JNI entry points for MediaCodecSurfaceTextureBridge
//     (nativeInit / nativeOnFrame / nativeSetDiagnostics), and
//   - the mkst_* C API dlsym'd by the mpv-side importer (WP-A):
//       int         mkst_init(uint64_t owner_key, uint32_t generation)
//       int         mkst_ensure_init(void)    -> verify-only: 1 initialized /
//                                                 0 not; NEVER initializes
//       void*       mkst_create_decoder_window(void)  -> ANativeWindow*
//                                                     (acquired, mpv-owned)
//       int         mkst_latch(int timeout_ms, uint64_t* out_ts_ns)
//       int         mkst_get_texture_name(void)
//       void*       mkst_get_surface_jobject(void)  -> Surface jobject
//                                                      (global ref, bridge-
//                                                      owned; do NOT delete)
//       int         mkst_shutdown(void)       -> explicit teardown, idempotent
//       const char* mkst_version(void)
//       int         mkst_diag_enabled(void)   -> diagnostics flag (0/1)
//       void        mkst_set_diag_enabled(int)  -> direct setter (Dart FFI)
//
// Authorization model: the Java explicit init (nativeInit, called with the
// FNV-1a64 hash of the experiment owner token plus the platform-view
// generation) is the ONLY initialization entry. The native side stores only
// the derived key, never the raw token. Every runtime gate is fail-closed
// with one log line: create requires an initialized bridge and no live
// window (single window per owner generation); latch / get_texture_name /
// get_surface_jobject require the live window; after shutdown everything
// refuses until a fresh init rebinds.
//
// Threading contract: mkst_create_decoder_window / mkst_latch /
// mkst_shutdown run on the mpv GL thread (caller holds a current EGL
// context for updateTexImage). The frame-available callback runs on an
// arbitrary Java thread and only touches the mutex-protected counters —
// never GL objects, never JNI method calls on the SurfaceTexture. Each
// window's listener carries a per-window token as its native handle; the
// callback is counted only while that exact token is the live window's
// current token, so a stale listener from a torn-down window is a no-op.
//
// Consuming-side serial constraint (P2-1 close-out): the lifecycle callers
// are the ONE mpv GL thread and strictly serial — create / latch / shutdown
// never overlap each other, and nothing latches across or after a teardown
// (a latch spanning a shutdown is excluded by the importer: the locks alone
// do not protect cross-JNI-segment generation consistency — reviewer
// counterexample latch-shutdown-ordered). Should lifecycle calls ever be
// allowed from multiple threads, a token check at the post-updateTexImage
// latched_counter write-back must be added FIRST.
//
// Lock discipline: see the comment on MkstLifecycle below.

#include <jni.h>
#include <android/log.h>
#include <android/native_window.h>
#include <android/native_window_jni.h>
#include <GLES2/gl2.h>

#include <atomic>
#include <cerrno>
#include <cstdint>
#include <ctime>
#include <new>

#include <dlfcn.h>
#include <pthread.h>

#ifndef MKSURF_VERSION
#define MKSURF_VERSION "surfacetexture-poc-r2"
#endif

#define MKSURF_LOG_TAG "MKSURF"
#define MKSURF_LOGI(...) __android_log_print(ANDROID_LOG_INFO, MKSURF_LOG_TAG, __VA_ARGS__)
#define MKSURF_LOGW(...) __android_log_print(ANDROID_LOG_WARN, MKSURF_LOG_TAG, __VA_ARGS__)

namespace {

// ---------------------------------------------------------------------------
// MKST-LIFECYCLE-BEGIN — the bridge's shared state plus its pure lifecycle
// state machine. Depends only on <cstdint>, <pthread.h> and <atomic> plus
// inert JNI/GL field types (jobject/GLuint carry no behavior), so the host
// harness (mkst_lifecycle_host_test.py) compiles this section verbatim and
// declares those two field types itself.
//
// Lock discipline (frozen contract):
//   - lifecycle.lock serializes the state transitions init / shutdown /
//     create / destroy. create and shutdown hold it for their whole body —
//     the serialized transition IS the body, including the JNI/GL section.
//   - g_state.lock (runtime window record) is always taken AFTER
//     lifecycle.lock, never before; taking state.lock and then lifecycle.lock
//     is forbidden.
//   - mkst_latch and nativeOnFrame take ONLY g_state.lock and never touch
//     lifecycle.lock, so a latching GL thread cannot deadlock against a
//     lifecycle transition; the latch's condition wait releases g_state.lock
//     while blocked, which lets shutdown publish valid=false immediately.
//   - Consuming-side serial constraint (P2-1 close-out): the lifecycle
//     callers (mkst_create_decoder_window / mkst_latch / mkst_shutdown) are
//     the ONE mpv GL thread, strictly serial — latch never overlaps
//     create/shutdown and never spans a teardown; that combination is
//     excluded by the caller because the locks do NOT protect
//     cross-JNI-segment generation consistency (a latch parked inside
//     updateTexImage can write latched_counter onto a torn record —
//     reviewer counterexample latch-shutdown-ordered; the product keeps no
//     cross-segment token check because the single-thread model needs none).
//     If multi-thread lifecycle is ever legalized, add a token check at the
//     post-updateTexImage latched_counter write-back first.
//
// Per-window revocable frame-callback handle (P8.4 A5 fix): the Java
// listener's native handle is NOT the static state address anymore but a
// token minted per decoder-window create and carried by that window's
// listener instance. Tokens are intentionally NEVER freed — a stale
// callback's raw pointer is only ever compared (never dereferenced unless
// it is the exact current token), and never-freed allocations remove the
// address-reuse (ABA) window entirely. Shutdown revokes the current token
// (alive=false, frame_token=null) under g_state.lock before any JNI
// teardown, so a queued callback from a previous window is a strict no-op:
// it can no longer bump a NEW window's frame counter (the fixed
// &g_state identity it used to compare against survived shutdown/recreate
// and let a stale listener pollute the next generation).
struct MkstWindowToken {
    std::atomic<bool> alive{false};
};

// All shared state lives in a single static struct that is never freed. A
// stale frame callback can therefore only hit the mutex and observe
// valid=false or a revoked token — there is no use-after-free path on the
// callback thread.
struct BridgeState {
    pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
    pthread_cond_t cond = PTHREAD_COND_INITIALIZER;
    // A decoder window exists and has not been shut down. Invariant: valid
    // == true implies the lifecycle record is initialized and window-active
    // (create publishes both under both locks; shutdown clears both). The
    // runtime gates (latch / getters / frame callback) rely on this
    // invariant and read ONLY this flag, never the lifecycle lock.
    bool valid = false;
    GLuint tex_name = 0;
    // The current window's revocable callback handle (see MkstWindowToken).
    // Written only by create (with valid=true) and shutdown (revoke, then
    // null) under this lock; nativeOnFrame accepts a callback handle only
    // when it equals this pointer, is alive, and valid holds.
    MkstWindowToken* frame_token = nullptr;
    // Incremented by the frame listener callback (under lock, with signal).
    uint64_t frame_counter = 0;
    // Frames already consumed by mkst_latch on the GL thread.
    uint64_t latched_counter = 0;
    // Global refs held for the latch/shutdown paths; all released together
    // in mkst_shutdown.
    jobject surface_texture = nullptr;
    jobject surface = nullptr;      // Kept so shutdown can Surface.release().
    jobject listener = nullptr;     // MediaCodecSurfaceTextureBridge instance.
    // Per-window frame-callback dispatcher ("mksurf-latch" HandlerThread +
    // Handler bound to it). Only touched from the GL thread (create /
    // shutdown are serialized by the lifecycle lock); the callback thread
    // itself never touches GL objects — nativeOnFrame only bumps the
    // mutex-protected counter.
    jobject handler = nullptr;
    jobject handler_thread = nullptr;
};

BridgeState g_state;

struct MkstLifecycle {
    pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
    bool initialized = false;    // An owner explicitly initialized the bridge
                                 // (mkst_init); cleared only by shutdown.
    bool window_active = false;  // create committed; the ANativeWindow itself
                                 // is owned and released by the mpv importer.
    uint64_t owner_key = 0;      // FNV-1a64 of the owner token (raw token is
                                 // never stored natively).
    uint32_t generation = 0;     // Platform-view generation of the owner.
};

// Owner-binding decision for mkst_init.
//   0  bound: fresh init, identical tuple (idempotent), or rebind while no
//      window is active — with no live window the latest explicit init owns
//      the single-instance bridge.
//  -1  refused: initialized with a different owner tuple while a window is
//      active; the live window keeps its owner (fail-closed).
int mkst_lc_init(MkstLifecycle* lc, uint64_t owner_key, uint32_t generation) {
    pthread_mutex_lock(&lc->lock);
    if (lc->initialized && lc->owner_key == owner_key &&
        lc->generation == generation) {
        pthread_mutex_unlock(&lc->lock);
        return 0;
    }
    if (lc->initialized && lc->window_active) {
        pthread_mutex_unlock(&lc->lock);
        return -1;
    }
    lc->initialized = true;
    lc->owner_key = owner_key;
    lc->generation = generation;
    pthread_mutex_unlock(&lc->lock);
    return 0;
}

// Verify-only probe: 1 = initialized, 0 = not. NEVER initializes; the Java
// explicit init is the only initialization entry.
int mkst_lc_verify(MkstLifecycle* lc) {
    pthread_mutex_lock(&lc->lock);
    const int ready = lc->initialized ? 1 : 0;
    pthread_mutex_unlock(&lc->lock);
    return ready;
}

// create gate; called with lc->lock HELD (the create body holds it for the
// whole attempt). 0 = may create (initialized, no live window), -1 = refused
// (fail-closed: uninitialized, or a window is already active).
int mkst_lc_create_gate_locked(MkstLifecycle* lc) {
    if (!lc->initialized) return -1;
    if (lc->window_active) return -1;
    return 0;
}

// create commit; called with lc->lock HELD after the window is fully built
// and published to the runtime record.
void mkst_lc_create_commit_locked(MkstLifecycle* lc) {
    lc->window_active = true;
}

// Explicit teardown: clears the binding and the window-active record.
// Idempotent. Returns 1 when a live binding was torn down, 0 when already
// down (the mkst_shutdown wrapper logs only the former). MUST be called with
// lc->lock HELD — mkst_shutdown holds the lifecycle lock for its whole body,
// and a self-locking convenience wrapper here would invite a self-deadlock
// on the non-recursive mutex.
int mkst_lc_shutdown_locked(MkstLifecycle* lc) {
    const bool was = lc->initialized || lc->window_active;
    lc->initialized = false;
    lc->window_active = false;
    lc->owner_key = 0;
    lc->generation = 0;
    return was ? 1 : 0;
}
// MKST-LIFECYCLE-END (the block lives inside the enclosing anonymous
// namespace; the host harness wraps the extracted text in its own).
// Internal helpers follow. ---------------------------------------------------

MkstLifecycle g_lifecycle;

// JNI class/method resources are resolved only from the Java-called
// nativeInit (a thread with Java frames, so FindClass resolves through the
// app classloader). Guarded by g_lifecycle.lock; read lock-free by
// mkst_init, which refuses while it is 0.
std::atomic<int> g_resources_ready{0};

// JavaVM is written from the Java-called nativeInit and read from the
// mpv GL thread (get_env_or_attach) without any other synchronization, so it
// must be atomic. Relaxed ordering suffices: the Java nativeInit call
// happens-before the first mkst_* use (the runtime gates refuse everything
// until the explicit init bound an owner), and there is no other
// cross-thread release pattern.
std::atomic<JavaVM*> g_vm{nullptr};
// Diagnostics switch for the mpv-side driver's small-area readback probes
// (dlsym'd via mkst_diag_enabled). Written only from the Java-called
// nativeSetDiagnostics; read lock-free elsewhere, so it must be atomic.
// Relaxed ordering suffices — it is a pure advisory flag, not a
// synchronization point. Default 0: diagnostics off, performance playback
// unaffected.
std::atomic<int> g_diag_enabled{0};
// Global ref cached at init time on a thread with Java frames on the stack
// (the nativeInit path). FindClass for an app class from the bare mpv
// GL thread would resolve through the system classloader and fail; the
// cached ref makes create_decoder_window classloader-independent.
jclass g_bridge_class = nullptr;
jclass g_surfacetexture_class = nullptr;  // Boot classpath class.
jclass g_surface_class = nullptr;         // Boot classpath class.
jclass g_handlerthread_class = nullptr;   // Boot classpath class.
jclass g_handler_class = nullptr;         // Boot classpath class.

jmethodID g_mid_bridge_ctor = nullptr;      // (J)V
jmethodID g_mid_st_ctor = nullptr;          // (IZ)V — API 11+, used on API 24.
jmethodID g_mid_update_tex_image = nullptr; // ()V
jmethodID g_mid_get_timestamp = nullptr;    // ()J
// Two-argument listener registration (API 16+): the explicit Handler pins
// dispatch to the dedicated "mksurf-latch" thread. The one-argument overload
// dispatches on the registration thread's Looper — the main thread here —
// whose cold-start congestion delayed onFrameAvailable until latches timed
// out.
jmethodID g_mid_st_set_listener =
    nullptr;  // (Landroid/graphics/SurfaceTexture$OnFrameAvailableListener;Landroid/os/Handler;)V
jmethodID g_mid_surface_ctor =
    nullptr;  // (Landroid/graphics/SurfaceTexture;)V
jmethodID g_mid_surface_release = nullptr;  // ()V
jmethodID g_mid_thread_ctor = nullptr;      // HandlerThread (Ljava/lang/String;)V
jmethodID g_mid_thread_start = nullptr;     // HandlerThread ()V
jmethodID g_mid_thread_get_looper = nullptr;  // HandlerThread ()Landroid/os/Looper;
jmethodID g_mid_thread_quit = nullptr;      // HandlerThread ()Z
jmethodID g_mid_handler_ctor = nullptr;     // Handler (Landroid/os/Looper;)V

// FFmpeg JNI helpers, resolved from the already-loaded libmpv. The bridge
// deliberately does NOT link libavutil; dlopen with RTLD_NOLOAD keeps this a
// pure observer of libmpv's process state.
typedef JavaVM* (*AvJniGetJavaVmFn)(void* log_ctx);
typedef int (*AvJniSetJavaVmFn)(void* vm, void* log_ctx);

// Returns an env for the current thread, attaching it if needed. Attached
// threads are never detached: the bridge is a process-resident helper and
// the mpv GL thread returns here for every latch.
JNIEnv* get_env_or_attach(const char* where) {
    JavaVM* vm = g_vm.load(std::memory_order_relaxed);
    if (vm == nullptr) return nullptr;
    JNIEnv* env = nullptr;
    if (vm->GetEnv(reinterpret_cast<void**>(&env), JNI_VERSION_1_6) == JNI_OK) {
        return env;
    }
    if (vm->AttachCurrentThread(&env, nullptr) != JNI_OK) {
        MKSURF_LOGW("%s: AttachCurrentThread failed", where);
        return nullptr;
    }
    MKSURF_LOGI("%s: attached JVM thread (process-resident, no detach)", where);
    return env;
}

void clear_pending_exception(JNIEnv* env, const char* where) {
    if (env->ExceptionCheck() == JNI_TRUE) {
        MKSURF_LOGW("%s: pending JNI exception cleared", where);
        env->ExceptionClear();
    }
}

jmethodID require_method(JNIEnv* env, jclass clazz, const char* name,
                         const char* signature, bool is_static) {
    jmethodID mid = is_static ? env->GetStaticMethodID(clazz, name, signature)
                              : env->GetMethodID(clazz, name, signature);
    if (mid == nullptr) {
        MKSURF_LOGW("init: method missing: %s %s", name, signature);
        clear_pending_exception(env, "init:GetMethodID");
    }
    return mid;
}

// One-time JNI resource resolution. Runs ONLY from the Java-called
// nativeInit (under g_lifecycle.lock): that thread has Java frames, so
// FindClass resolves through the app classloader. Sets g_resources_ready
// only when every class and method ID resolved; any miss leaves it closed.
void do_init_resources(JNIEnv* env) {
    void* libmpv = dlopen("libmpv.so", RTLD_NOLOAD | RTLD_LOCAL);
    AvJniGetJavaVmFn av_jni_get_java_vm = nullptr;
    AvJniSetJavaVmFn av_jni_set_java_vm = nullptr;
    if (libmpv != nullptr) {
        av_jni_get_java_vm =
            reinterpret_cast<AvJniGetJavaVmFn>(dlsym(libmpv, "av_jni_get_java_vm"));
        av_jni_set_java_vm =
            reinterpret_cast<AvJniSetJavaVmFn>(dlsym(libmpv, "av_jni_set_java_vm"));
    } else {
        MKSURF_LOGW("init: libmpv not loaded (NOLOAD)");
    }

    // The JavaVM is cached by nativeInit before this runs (same call, same
    // thread). The av_jni_get_java_vm fallback only covers the same VM
    // arriving through FFmpeg first; without it the resource pass stays
    // closed.
    if (g_vm.load(std::memory_order_relaxed) == nullptr && av_jni_get_java_vm != nullptr) {
        g_vm.store(static_cast<JavaVM*>(av_jni_get_java_vm(nullptr)),
                   std::memory_order_relaxed);
    }
    if (g_vm.load(std::memory_order_relaxed) == nullptr) {
        MKSURF_LOGW("init: no JavaVM available (nativeInit not called)");
        return;
    }

    // Only seed FFmpeg's VM when none was set; never override an existing
    // registration.
    if (av_jni_get_java_vm != nullptr && av_jni_set_java_vm != nullptr &&
        av_jni_get_java_vm(nullptr) == nullptr) {
        const int set_result =
            av_jni_set_java_vm(g_vm.load(std::memory_order_relaxed), nullptr);
        MKSURF_LOGI("init: av_jni_set_java_vm result=%d", set_result);
    }

    // Cache the bridge class global ref HERE: this thread still has Java
    // frames, so FindClass resolves through the app classloader. Fail closed
    // when that is impossible (e.g. resources demanded from a bare native
    // thread — mkst_init refuses instead of resolving).
    const char* bridge_class_name =
        "com/alexmercerind/media_kit_video/platformview/MediaCodecSurfaceTextureBridge";
    jclass bridge_local = env->FindClass(bridge_class_name);
    if (bridge_local == nullptr) {
        clear_pending_exception(env, "init:FindClass(bridge)");
        MKSURF_LOGW("init: bridge class not found (no app classloader on thread)");
        return;
    }
    g_bridge_class = static_cast<jclass>(env->NewGlobalRef(bridge_local));
    env->DeleteLocalRef(bridge_local);
    if (g_bridge_class == nullptr) {
        MKSURF_LOGW("init: bridge class global ref failed");
        return;
    }
    g_mid_bridge_ctor = require_method(env, g_bridge_class, "<init>", "(J)V", false);
    if (g_mid_bridge_ctor == nullptr) return;

    jclass st_local = env->FindClass("android/graphics/SurfaceTexture");
    if (st_local == nullptr) {
        clear_pending_exception(env, "init:FindClass(SurfaceTexture)");
        return;
    }
    g_surfacetexture_class = static_cast<jclass>(env->NewGlobalRef(st_local));
    env->DeleteLocalRef(st_local);
    if (g_surfacetexture_class == nullptr) return;

    g_mid_st_ctor = require_method(env, g_surfacetexture_class, "<init>", "(IZ)V", false);
    g_mid_update_tex_image =
        require_method(env, g_surfacetexture_class, "updateTexImage", "()V", false);
    g_mid_get_timestamp =
        require_method(env, g_surfacetexture_class, "getTimestamp", "()J", false);
    g_mid_st_set_listener =
        require_method(env, g_surfacetexture_class, "setOnFrameAvailableListener",
                       "(Landroid/graphics/SurfaceTexture$OnFrameAvailableListener;"
                       "Landroid/os/Handler;)V", false);
    if (g_mid_st_ctor == nullptr || g_mid_update_tex_image == nullptr ||
        g_mid_get_timestamp == nullptr || g_mid_st_set_listener == nullptr) {
        return;
    }

    jclass surface_local = env->FindClass("android/view/Surface");
    if (surface_local == nullptr) {
        clear_pending_exception(env, "init:FindClass(Surface)");
        return;
    }
    g_surface_class = static_cast<jclass>(env->NewGlobalRef(surface_local));
    env->DeleteLocalRef(surface_local);
    if (g_surface_class == nullptr) return;

    g_mid_surface_ctor =
        require_method(env, g_surface_class, "<init>", "(Landroid/graphics/SurfaceTexture;)V", false);
    g_mid_surface_release = require_method(env, g_surface_class, "release", "()V", false);
    if (g_mid_surface_ctor == nullptr || g_mid_surface_release == nullptr) {
        return;
    }

    // Frame-callback dispatcher infrastructure. Only the classes and method
    // IDs are resolved here (fail-closed on any miss); the HandlerThread and
    // Handler instances are created per decoder window in
    // mkst_create_decoder_window and quit/released in mkst_shutdown, so
    // every window owns a live dispatcher (a thread quit at shutdown must
    // never be reused by a later create).
    jclass handlerht_local = env->FindClass("android/os/HandlerThread");
    if (handlerht_local == nullptr) {
        clear_pending_exception(env, "init:FindClass(HandlerThread)");
        return;
    }
    g_handlerthread_class = static_cast<jclass>(env->NewGlobalRef(handlerht_local));
    env->DeleteLocalRef(handlerht_local);
    if (g_handlerthread_class == nullptr) return;

    g_mid_thread_ctor =
        require_method(env, g_handlerthread_class, "<init>", "(Ljava/lang/String;)V", false);
    g_mid_thread_start = require_method(env, g_handlerthread_class, "start", "()V", false);
    g_mid_thread_get_looper =
        require_method(env, g_handlerthread_class, "getLooper", "()Landroid/os/Looper;", false);
    g_mid_thread_quit = require_method(env, g_handlerthread_class, "quit", "()Z", false);
    if (g_mid_thread_ctor == nullptr || g_mid_thread_start == nullptr ||
        g_mid_thread_get_looper == nullptr || g_mid_thread_quit == nullptr) {
        return;
    }

    jclass handler_local = env->FindClass("android/os/Handler");
    if (handler_local == nullptr) {
        clear_pending_exception(env, "init:FindClass(Handler)");
        return;
    }
    g_handler_class = static_cast<jclass>(env->NewGlobalRef(handler_local));
    env->DeleteLocalRef(handler_local);
    if (g_handler_class == nullptr) return;

    g_mid_handler_ctor =
        require_method(env, g_handler_class, "<init>", "(Landroid/os/Looper;)V", false);
    if (g_mid_handler_ctor == nullptr) return;

    g_resources_ready.store(1, std::memory_order_release);
    MKSURF_LOGI("init: resources resolved version=%s", MKSURF_VERSION);
}

// Releases every local ref and native resource a failed create attempt is
// still holding. Each failure branch passes exactly the objects that are
// alive at that point (null otherwise):
//   - [handler_local]/[ht_local]: per-window dispatcher objects; a STARTED
//     HandlerThread is quit BEFORE its refs are dropped, so a failed create
//     never leaks a running dispatcher thread (quit on a never-started
//     HandlerThread is a legal no-op).
//   - [listener_registered]: the two-argument setOnFrameAvailableListener
//     already succeeded on [st_local]; the rollback detaches it explicitly
//     so the resource accounting never depends on SurfaceTexture GC timing.
//   - [surface_local] + release_surface: the java Surface wrapper exists;
//     when its window was never handed to the importer the rollback
//     releases it (Surface.release) instead of waiting for a finalizer.
//   - [token]: the per-window callback token minted for this attempt. It is
//     REVOKED (alive=false), never freed — the listener instance carrying it
//     may already exist JVM-side, and the token memory must stay valid for
//     the raw pointer comparison in nativeOnFrame (see MkstWindowToken).
void abort_create(JNIEnv* env, jobject st_local, jobject listener_local,
                  jobject surface_local, bool release_surface,
                  jobject handler_local, jobject ht_local,
                  bool listener_registered, MkstWindowToken* token, GLuint tex) {
    if (listener_registered && st_local != nullptr && listener_local != nullptr &&
        g_mid_st_set_listener != nullptr) {
        env->CallVoidMethod(st_local, g_mid_st_set_listener, nullptr, nullptr);
        clear_pending_exception(env, "create:rollback-clearListener");
    }
    if (surface_local != nullptr && release_surface &&
        g_mid_surface_release != nullptr) {
        env->CallVoidMethod(surface_local, g_mid_surface_release);
        clear_pending_exception(env, "create:rollback-surfaceRelease");
    }
    if (ht_local != nullptr && g_mid_thread_quit != nullptr) {
        env->CallBooleanMethod(ht_local, g_mid_thread_quit);
        clear_pending_exception(env, "create:rollback-quit");
    }
    if (handler_local != nullptr) env->DeleteLocalRef(handler_local);
    if (ht_local != nullptr) env->DeleteLocalRef(ht_local);
    if (surface_local != nullptr) env->DeleteLocalRef(surface_local);
    if (listener_local != nullptr) env->DeleteLocalRef(listener_local);
    if (st_local != nullptr) env->DeleteLocalRef(st_local);
    if (token != nullptr) token->alive.store(false, std::memory_order_relaxed);
    if (tex != 0) glDeleteTextures(1, &tex);
}

}  // namespace

// ---------------------------------------------------------------------------
// Static JNI entry points for MediaCodecSurfaceTextureBridge.
// ---------------------------------------------------------------------------

// mkst_* state transition consumed by nativeInit; defined with the C API
// below.
extern "C" int mkst_init(uint64_t owner_key, uint32_t generation);

extern "C" JNIEXPORT jboolean JNICALL
Java_com_alexmercerind_media_1kit_1video_platformview_MediaCodecSurfaceTextureBridge_nativeInit(
    JNIEnv* env, jclass, jlong owner_key, jint generation) {
    // This is only ever called from Java, so the VM is always obtainable
    // here; cache it for the mkst_* paths that run on native threads.
    if (g_vm.load(std::memory_order_relaxed) == nullptr) {
        JavaVM* vm = nullptr;
        if (env->GetJavaVM(&vm) == JNI_OK) {
            g_vm.store(vm, std::memory_order_relaxed);
        }
    }
    // Platform-view generations are 1-based; 0 means "no generation" and
    // must not bind (fail-closed).
    if (generation <= 0) {
        MKSURF_LOGW("nativeInit: refused (generation=%d)", generation);
        return JNI_FALSE;
    }
    // Resource resolution runs under the lifecycle lock so a concurrent
    // create can never observe half-resolved class/method globals.
    pthread_mutex_lock(&g_lifecycle.lock);
    if (g_resources_ready.load(std::memory_order_relaxed) == 0) {
        do_init_resources(env);
    }
    const int ready = g_resources_ready.load(std::memory_order_relaxed);
    pthread_mutex_unlock(&g_lifecycle.lock);
    if (ready == 0) {
        MKSURF_LOGW("nativeInit: resources unavailable (fail-closed)");
        return JNI_FALSE;
    }
    return mkst_init(static_cast<uint64_t>(owner_key),
                     static_cast<uint32_t>(generation)) == 0
               ? JNI_TRUE
               : JNI_FALSE;
}

extern "C" JNIEXPORT void JNICALL
Java_com_alexmercerind_media_1kit_1video_platformview_MediaCodecSurfaceTextureBridge_nativeOnFrame(
    JNIEnv*, jclass, jlong handle) {
    // Counter bump only: no GL, no JNI calls on Java objects, no exceptions.
    // [handle] is the per-window token minted by the create that built this
    // listener (see MkstWindowToken). Tokens are never freed, so comparing
    // the raw value is safe even for a listener whose window is long gone:
    // a stale token simply never equals the current window's token, and only
    // the exact live (valid + current + alive) token is ever dereferenced.
    // This closes the cross-generation hole where the fixed &g_state handle
    // identity survived shutdown/recreate and let a queued callback from a
    // torn-down window bump the NEXT window's frame counter. Takes ONLY
    // g_state.lock (never the lifecycle lock — see the lock discipline
    // above).
    if (handle == 0) return;
    auto* token = reinterpret_cast<MkstWindowToken*>(
        static_cast<uintptr_t>(handle));
    pthread_mutex_lock(&g_state.lock);
    if (g_state.valid && g_state.frame_token == token &&
        token->alive.load(std::memory_order_relaxed)) {
        ++g_state.frame_counter;
        pthread_cond_signal(&g_state.cond);
    }
    pthread_mutex_unlock(&g_state.lock);
}

extern "C" JNIEXPORT void JNICALL
Java_com_alexmercerind_media_1kit_1video_platformview_MediaCodecSurfaceTextureBridge_nativeSetDiagnostics(
    JNIEnv*, jclass, jboolean enabled) {
    // Atomic store only: no JNI object access, no exception surface.
    g_diag_enabled.store(enabled != JNI_FALSE ? 1 : 0, std::memory_order_relaxed);
    MKSURF_LOGI("diagnostics %s", enabled != JNI_FALSE ? "enabled" : "disabled");
}

// ---------------------------------------------------------------------------
// mkst_* C API consumed by the mpv-side importer.
// ---------------------------------------------------------------------------

extern "C" JNIEXPORT int mkst_init(uint64_t owner_key, uint32_t generation) {
    // Only the Java-called nativeInit resolves the JNI resources; this C
    // entry is the pure state transition and refuses while they are missing.
    if (g_resources_ready.load(std::memory_order_acquire) == 0) {
        MKSURF_LOGW("init: refused (resources unresolved; Java nativeInit must run first)");
        return -1;
    }
    const int rc = mkst_lc_init(&g_lifecycle, owner_key, generation);
    if (rc != 0) {
        MKSURF_LOGW("init: refused (owner_key=%llu generation=%u; live window"
                    " keeps its owner)",
                    static_cast<unsigned long long>(owner_key), generation);
    } else {
        MKSURF_LOGI("init: bound owner_key=%llu generation=%u version=%s",
                    static_cast<unsigned long long>(owner_key), generation,
                    MKSURF_VERSION);
    }
    return rc;
}

extern "C" JNIEXPORT int mkst_ensure_init(void) {
    // Verify-only: 1 = an owner explicitly initialized the bridge, 0 = not.
    // Never initializes; the Java nativeInit is the only initialization
    // entry, so a native-first call can never poison the Java-side init.
    return mkst_lc_verify(&g_lifecycle);
}

// The whole create body runs under g_lifecycle.lock (serialized transition;
// see the lock discipline above).
static void* do_create_decoder_window_locked() {
    // Caller is the mpv GL thread: it may not be attached to the JVM yet.
    // Attach and stay attached (process-resident helper, see
    // get_env_or_attach).
    JNIEnv* env = get_env_or_attach("create");
    if (env == nullptr) {
        MKSURF_LOGW("create: no JNIEnv");
        return nullptr;
    }

    // OES texture created here; the importer wraps this exact name
    // (mkst_get_texture_name) and must not GenTextures its own.
    GLuint tex = 0;
    glGenTextures(1, &tex);
    if (tex == 0) {
        MKSURF_LOGW("create: glGenTextures failed");
        return nullptr;
    }

    jobject st_local = env->NewObject(g_surfacetexture_class, g_mid_st_ctor,
                                      static_cast<jint>(tex), JNI_FALSE);
    if (st_local == nullptr || env->ExceptionCheck() == JNI_TRUE) {
        clear_pending_exception(env, "create:NewObject(SurfaceTexture)");
        MKSURF_LOGW("create: SurfaceTexture(%u) failed", tex);
        abort_create(env, nullptr, nullptr, nullptr, false, nullptr, nullptr,
                     false, nullptr, tex);
        return nullptr;
    }

    // Mint the per-window callback handle BEFORE the listener exists: the
    // listener carries it as its native handle for its whole lifetime (see
    // MkstWindowToken). Never freed — revoked instead (rollback + shutdown).
    MkstWindowToken* token = new (std::nothrow) MkstWindowToken();
    if (token == nullptr) {
        MKSURF_LOGW("create: callback token allocation failed");
        abort_create(env, st_local, nullptr, nullptr, false, nullptr, nullptr,
                     false, nullptr, tex);
        return nullptr;
    }
    token->alive.store(true, std::memory_order_relaxed);

    const jlong handle = static_cast<jlong>(reinterpret_cast<uintptr_t>(token));
    jobject listener_local = env->NewObject(g_bridge_class, g_mid_bridge_ctor, handle);
    if (listener_local == nullptr || env->ExceptionCheck() == JNI_TRUE) {
        clear_pending_exception(env, "create:NewObject(bridge)");
        MKSURF_LOGW("create: bridge listener instance failed");
        abort_create(env, st_local, nullptr, nullptr, false, nullptr, nullptr,
                     false, token, tex);
        return nullptr;
    }

    // Dedicated dispatch thread for frame-available callbacks (see
    // do_init_resources). Built per window, after the bridge listener
    // instance exists; every failure below rolls back everything created so
    // far, including the started thread.
    jstring name_local = env->NewStringUTF("mksurf-latch");
    if (name_local == nullptr || env->ExceptionCheck() == JNI_TRUE) {
        clear_pending_exception(env, "create:NewStringUTF");
        MKSURF_LOGW("create: handler thread name failed");
        abort_create(env, st_local, listener_local, nullptr, false, nullptr,
                     nullptr, false, token, tex);
        return nullptr;
    }
    jobject ht_local = env->NewObject(g_handlerthread_class, g_mid_thread_ctor, name_local);
    env->DeleteLocalRef(name_local);
    if (ht_local == nullptr || env->ExceptionCheck() == JNI_TRUE) {
        clear_pending_exception(env, "create:NewObject(HandlerThread)");
        MKSURF_LOGW("create: HandlerThread failed");
        abort_create(env, st_local, listener_local, nullptr, false, nullptr,
                     nullptr, false, token, tex);
        return nullptr;
    }
    env->CallVoidMethod(ht_local, g_mid_thread_start);
    if (env->ExceptionCheck() == JNI_TRUE) {
        clear_pending_exception(env, "create:HandlerThread.start");
        MKSURF_LOGW("create: HandlerThread.start failed");
        // abort_create quits even a never-started thread (a legal no-op).
        abort_create(env, st_local, listener_local, nullptr, false, nullptr,
                     ht_local, false, token, tex);
        return nullptr;
    }

    jobject looper_local = env->CallObjectMethod(ht_local, g_mid_thread_get_looper);
    if (looper_local == nullptr || env->ExceptionCheck() == JNI_TRUE) {
        clear_pending_exception(env, "create:HandlerThread.getLooper");
        MKSURF_LOGW("create: getLooper failed");
        // Roll the started thread back before giving up.
        abort_create(env, st_local, listener_local, nullptr, false, nullptr,
                     ht_local, false, token, tex);
        return nullptr;
    }
    jobject handler_local = env->NewObject(g_handler_class, g_mid_handler_ctor, looper_local);
    env->DeleteLocalRef(looper_local);
    if (handler_local == nullptr || env->ExceptionCheck() == JNI_TRUE) {
        clear_pending_exception(env, "create:NewObject(Handler)");
        MKSURF_LOGW("create: Handler failed");
        abort_create(env, st_local, listener_local, nullptr, false, nullptr,
                     ht_local, false, token, tex);
        return nullptr;
    }

    // Two-argument registration (API 16+): callbacks dispatch on the
    // dedicated thread's Handler instead of the registration thread's
    // Looper.
    env->CallVoidMethod(st_local, g_mid_st_set_listener, listener_local, handler_local);
    if (env->ExceptionCheck() == JNI_TRUE) {
        clear_pending_exception(env, "create:setOnFrameAvailableListener");
        MKSURF_LOGW("create: setOnFrameAvailableListener failed");
        // A throwing registration did not attach the listener; the rollback
        // quits the started dispatcher thread.
        abort_create(env, st_local, listener_local, nullptr, false,
                     handler_local, ht_local, false, token, tex);
        return nullptr;
    }

    jobject surface_local = env->NewObject(g_surface_class, g_mid_surface_ctor, st_local);
    if (surface_local == nullptr || env->ExceptionCheck() == JNI_TRUE) {
        clear_pending_exception(env, "create:NewObject(Surface)");
        MKSURF_LOGW("create: Surface(SurfaceTexture) failed");
        // The listener IS registered at this point: the rollback detaches it,
        // quits the dispatcher thread, and drops every local ref.
        abort_create(env, st_local, listener_local, nullptr, false,
                     handler_local, ht_local, true, token, tex);
        return nullptr;
    }

    ANativeWindow* window = ANativeWindow_fromSurface(env, surface_local);
    if (window == nullptr) {
        clear_pending_exception(env, "create:ANativeWindow_fromSurface");
        MKSURF_LOGW("create: ANativeWindow_fromSurface failed");
        // No ANativeWindow reference was acquired; release the java Surface
        // wrapper deterministically and quit the dispatcher thread.
        abort_create(env, st_local, listener_local, surface_local, true,
                     handler_local, ht_local, true, token, tex);
        return nullptr;
    }

    // Keep global refs for everything the latch/shutdown paths still need.
    // All five allocations are checked BEFORE any local ref is dropped, so a
    // rollback here can detach the listener, release the Surface and quit
    // the dispatcher thread through still-valid local refs. (The earlier
    // revision deleted ht_local first and then fell back to that stale local
    // ref for the quit call — a use-after-DeleteLocalRef.)
    jobject st_global = env->NewGlobalRef(st_local);
    jobject surface_global = env->NewGlobalRef(surface_local);
    jobject listener_global = env->NewGlobalRef(listener_local);
    jobject handler_global = env->NewGlobalRef(handler_local);
    jobject thread_global = env->NewGlobalRef(ht_local);
    if (st_global == nullptr || surface_global == nullptr || listener_global == nullptr ||
        handler_global == nullptr || thread_global == nullptr) {
        clear_pending_exception(env, "create:NewGlobalRef");
        MKSURF_LOGW("create: global ref allocation failed");
        abort_create(env, st_local, listener_local, surface_local, true,
                     handler_local, ht_local, true, token, tex);
        if (handler_global != nullptr) env->DeleteGlobalRef(handler_global);
        if (thread_global != nullptr) env->DeleteGlobalRef(thread_global);
        if (listener_global != nullptr) env->DeleteGlobalRef(listener_global);
        if (surface_global != nullptr) env->DeleteGlobalRef(surface_global);
        if (st_global != nullptr) env->DeleteGlobalRef(st_global);
        ANativeWindow_release(window);
        return nullptr;
    }
    env->DeleteLocalRef(surface_local);
    env->DeleteLocalRef(listener_local);
    env->DeleteLocalRef(handler_local);
    env->DeleteLocalRef(ht_local);
    env->DeleteLocalRef(st_local);

    pthread_mutex_lock(&g_state.lock);
    g_state.tex_name = tex;
    g_state.frame_counter = 0;
    g_state.latched_counter = 0;
    g_state.surface_texture = st_global;
    g_state.surface = surface_global;
    g_state.listener = listener_global;
    g_state.handler = handler_global;
    g_state.handler_thread = thread_global;
    g_state.frame_token = token;
    g_state.valid = true;
    pthread_mutex_unlock(&g_state.lock);

    MKSURF_LOGI("create: version=%s tex=%u", MKSURF_VERSION, tex);
    return window;
}

extern "C" JNIEXPORT void* mkst_create_decoder_window(void) {
    pthread_mutex_lock(&g_lifecycle.lock);
    if (mkst_lc_create_gate_locked(&g_lifecycle) != 0) {
        const bool initialized = g_lifecycle.initialized;
        const bool window_active = g_lifecycle.window_active;
        pthread_mutex_unlock(&g_lifecycle.lock);
        MKSURF_LOGW("create: refused (initialized=%d window_active=%d)",
                    initialized ? 1 : 0, window_active ? 1 : 0);
        return nullptr;
    }
    void* window = do_create_decoder_window_locked();
    if (window == nullptr) {
        pthread_mutex_unlock(&g_lifecycle.lock);
        return nullptr;
    }
    mkst_lc_create_commit_locked(&g_lifecycle);
    pthread_mutex_unlock(&g_lifecycle.lock);
    return window;
}

extern "C" JNIEXPORT int mkst_latch(int timeout_ms, uint64_t* out_ts_ns) {
    if (out_ts_ns == nullptr) return -1;
    *out_ts_ns = 0;

    // Runtime gate: the live-window record IS the initialized+window-active
    // pair (invariant on g_state.valid, see BridgeState). This path takes
    // ONLY g_state.lock — never the lifecycle lock (lock discipline above).
    pthread_mutex_lock(&g_state.lock);
    if (!g_state.valid || g_state.surface_texture == nullptr) {
        pthread_mutex_unlock(&g_state.lock);
        MKSURF_LOGW("latch: refused (no live decoder window)");
        return -1;
    }
    // Bounded wait until the listener reports a frame beyond what this
    // thread already latched. The deadline is computed once: the total wait
    // is capped at timeout_ms regardless of spurious wakeups.
    timespec deadline;
    clock_gettime(CLOCK_REALTIME, &deadline);
    deadline.tv_sec += timeout_ms / 1000;
    deadline.tv_nsec += static_cast<long>(timeout_ms % 1000) * 1000000L;
    if (deadline.tv_nsec >= 1000000000L) {
        deadline.tv_sec += 1;
        deadline.tv_nsec -= 1000000000L;
    }
    int wait_rc = 0;
    while (g_state.frame_counter <= g_state.latched_counter && wait_rc == 0) {
        wait_rc = pthread_cond_timedwait(&g_state.cond, &g_state.lock, &deadline);
    }
    if (wait_rc != 0 && wait_rc != ETIMEDOUT) {
        pthread_mutex_unlock(&g_state.lock);
        MKSURF_LOGW("latch: cond wait error=%d", wait_rc);
        return -1;
    }
    const bool has_frame = g_state.frame_counter > g_state.latched_counter;
    if (!has_frame) {
        // Diagnostic probe (run5): distinguish (a) "frame queued but the
        // onFrameAvailable -> nativeOnFrame chain is broken" from (b) "frame
        // never queued by the codec". The caller is the GL thread, so a
        // probe updateTexImage here is legal. Counters are read under the
        // mutex and logged outside it. Return semantics unchanged (still 1).
        const uint64_t frames_snapshot = g_state.frame_counter;
        const uint64_t latched_snapshot = g_state.latched_counter;
        const bool valid_snapshot = g_state.valid;
        const jobject surface_texture = g_state.surface_texture;
        pthread_mutex_unlock(&g_state.lock);

        long long ts_after_update = 0;
        if (valid_snapshot && surface_texture != nullptr) {
            JNIEnv* env = get_env_or_attach("latch-timeout-diag");
            if (env != nullptr) {
                env->CallVoidMethod(surface_texture, g_mid_update_tex_image);
                if (env->ExceptionCheck() == JNI_TRUE) {
                    clear_pending_exception(env, "latch-timeout-diag:updateTexImage");
                    MKSURF_LOGW("latch-timeout-diag: updateTexImage failed branch=-2"
                                " frame_counter=%lld latched=%lld valid=%d",
                                static_cast<long long>(frames_snapshot),
                                static_cast<long long>(latched_snapshot),
                                valid_snapshot ? 1 : 0);
                    return 1;
                }
                const jlong ts = env->CallLongMethod(surface_texture, g_mid_get_timestamp);
                if (env->ExceptionCheck() == JNI_TRUE) {
                    clear_pending_exception(env, "latch-timeout-diag:getTimestamp");
                    MKSURF_LOGW("latch-timeout-diag: getTimestamp failed branch=-2"
                                " frame_counter=%lld latched=%lld valid=%d",
                                static_cast<long long>(frames_snapshot),
                                static_cast<long long>(latched_snapshot),
                                valid_snapshot ? 1 : 0);
                    return 1;
                }
                ts_after_update = static_cast<long long>(ts);
            }
        }
        MKSURF_LOGW("latch-timeout-diag: frame_counter=%lld latched=%lld"
                    " ts_after_update=%lld valid=%d",
                    static_cast<long long>(frames_snapshot),
                    static_cast<long long>(latched_snapshot), ts_after_update,
                    valid_snapshot ? 1 : 0);
        return 1;  // No new frame within the budget; caller keeps its lease.
    }
    const uint64_t target = g_state.frame_counter;
    const jobject surface_texture = g_state.surface_texture;
    pthread_mutex_unlock(&g_state.lock);

    JNIEnv* env = get_env_or_attach("latch");
    if (env == nullptr) {
        MKSURF_LOGW("latch: no JNIEnv");
        return -1;
    }

    // updateTexImage runs on this (GL) thread, with the caller's EGL context
    // current, so the OES texture content lands in this context.
    env->CallVoidMethod(surface_texture, g_mid_update_tex_image);
    if (env->ExceptionCheck() == JNI_TRUE) {
        clear_pending_exception(env, "latch:updateTexImage");
        return -1;
    }
    // Consumed: record the latch before reading the timestamp so a
    // timestamp failure cannot turn into a repeated updateTexImage.
    pthread_mutex_lock(&g_state.lock);
    g_state.latched_counter = target;
    pthread_mutex_unlock(&g_state.lock);

    const jlong ts = env->CallLongMethod(surface_texture, g_mid_get_timestamp);
    if (env->ExceptionCheck() == JNI_TRUE) {
        clear_pending_exception(env, "latch:getTimestamp");
        return -1;
    }
    *out_ts_ns = static_cast<uint64_t>(ts);
    return 0;
}

extern "C" JNIEXPORT int mkst_get_texture_name(void) {
    pthread_mutex_lock(&g_state.lock);
    const bool live = g_state.valid;
    const int name = live ? static_cast<int>(g_state.tex_name) : 0;
    pthread_mutex_unlock(&g_state.lock);
    if (!live) {
        MKSURF_LOGW("get_texture_name: refused (no live decoder window)");
    }
    return name;
}

// The java Surface object backing the decoder window, kept as a global ref
// exactly so the mpv-side importer can hand the jobject to FFmpeg's
// mediacodec wrapper (mediacodec_jni_configure reads window->surface; a bare
// ANativeWindow pointer leaves it NULL and the decoder silently runs in
// buffer mode, never queuing frames into the SurfaceTexture). Returns NULL
// before create_decoder_window / after mkst_shutdown. The returned jobject
// is owned by the bridge (global ref); the caller must NOT delete it.
extern "C" JNIEXPORT void* mkst_get_surface_jobject(void) {
    pthread_mutex_lock(&g_state.lock);
    const bool live = g_state.valid;
    void* surface = live ? static_cast<void*>(g_state.surface) : nullptr;
    pthread_mutex_unlock(&g_state.lock);
    if (!live) {
        MKSURF_LOGW("get_surface_jobject: refused (no live decoder window)");
    }
    return surface;
}

extern "C" JNIEXPORT const char* mkst_version(void) {
    return MKSURF_VERSION;
}

// Diagnostics flag queried by the mpv-side driver via dlsym. Non-zero means
// an explicit diagnostics session is active and the caller may run its
// small-area readback probes; performance playback must keep it 0 (default).
extern "C" JNIEXPORT int mkst_diag_enabled(void) {
    return g_diag_enabled.load(std::memory_order_relaxed);
}

// Direct C setter for diagnostics (Dart FFI callable; no JNIEnv needed —
// pure atomic store). Same flag as nativeSetDiagnostics.
extern "C" JNIEXPORT void mkst_set_diag_enabled(int enabled) {
    g_diag_enabled.store(enabled != 0 ? 1 : 0, std::memory_order_relaxed);
}

extern "C" JNIEXPORT int mkst_shutdown(void) {
    // Serialized transition: the lifecycle lock is held for the whole
    // teardown (lock discipline above). The binding is torn down FIRST, so
    // every lifecycle gate refuses from this point on even while the JNI
    // teardown below is still running. The _locked teardown step is used
    // because this function already holds the lifecycle lock.
    pthread_mutex_lock(&g_lifecycle.lock);
    if (mkst_lc_shutdown_locked(&g_lifecycle) == 0) {
        pthread_mutex_unlock(&g_lifecycle.lock);
        MKSURF_LOGI("shutdown: no-op (already down)");
        return 0;  // Idempotent.
    }
    // Stop counter accounting first: any in-flight frame callback now
    // observes valid=false or a revoked token and is dropped. The per-window
    // callback token is revoked BEFORE the listener is detached below, so a
    // callback already dispatched on the "mksurf-latch" thread becomes a
    // native no-op at this point (its old handle is neither current nor
    // alive) and can never pollute a successor window's counters.
    pthread_mutex_lock(&g_state.lock);
    g_state.valid = false;
    if (g_state.frame_token != nullptr) {
        g_state.frame_token->alive.store(false, std::memory_order_relaxed);
    }
    const uint64_t frames_total = g_state.frame_counter;
    const uint64_t latched_total = g_state.latched_counter;
    pthread_mutex_unlock(&g_state.lock);

    JNIEnv* env = get_env_or_attach("shutdown");
    const jobject surface_texture = g_state.surface_texture;
    const jobject surface = g_state.surface;
    const jobject listener = g_state.listener;
    const jobject handler = g_state.handler;
    const jobject handler_thread = g_state.handler_thread;
    if (env != nullptr) {
        if (surface != nullptr && g_mid_surface_release != nullptr) {
            env->CallVoidMethod(surface, g_mid_surface_release);
            clear_pending_exception(env, "shutdown:Surface.release");
        }
        if (surface_texture != nullptr && g_mid_st_set_listener != nullptr) {
            // Detach the listener (two-argument form; the handler may be
            // null here — only the listener removal matters). The
            // SurfaceTexture itself is handed back to the GC when our global
            // ref goes away (its finalizer releases the native side).
            env->CallVoidMethod(surface_texture, g_mid_st_set_listener, nullptr, handler);
            clear_pending_exception(env, "shutdown:clearListener");
        }
        if (listener != nullptr) env->DeleteGlobalRef(listener);
        if (surface_texture != nullptr) env->DeleteGlobalRef(surface_texture);
        if (surface != nullptr) env->DeleteGlobalRef(surface);
        // quit() does NOT join: a callback already dispatched (or still
        // queued) on the "mksurf-latch" thread can run after shutdown
        // returns. That is harmless by construction here — the token
        // revocation above makes every such late nativeOnFrame a strict
        // no-op (the old window's handle is neither the current token nor
        // alive), and the token memory itself is never freed so the stale
        // pointer comparison stays valid. No join is attempted: shutdown
        // runs on the mpv GL thread and must not wait on arbitrary Java
        // threads.
        if (handler_thread != nullptr && g_mid_thread_quit != nullptr) {
            env->CallBooleanMethod(handler_thread, g_mid_thread_quit);
            clear_pending_exception(env, "shutdown:handlerThread.quit");
        }
        if (handler != nullptr) env->DeleteGlobalRef(handler);
        if (handler_thread != nullptr) env->DeleteGlobalRef(handler_thread);
    }
    // The ANativeWindow is NOT released here: it is owned and released by
    // the mpv-side importer (mkst_create_decoder_window documented the
    // acquire; the driver documents the release).
    pthread_mutex_lock(&g_state.lock);
    g_state.surface_texture = nullptr;
    g_state.surface = nullptr;
    g_state.listener = nullptr;
    g_state.handler = nullptr;
    g_state.handler_thread = nullptr;
    g_state.frame_token = nullptr;
    g_state.tex_name = 0;
    g_state.frame_counter = 0;
    g_state.latched_counter = 0;
    pthread_mutex_unlock(&g_state.lock);
    pthread_mutex_unlock(&g_lifecycle.lock);
    MKSURF_LOGI("shutdown: complete version=%s frames=%lld latched=%lld",
                MKSURF_VERSION, static_cast<long long>(frames_total),
                static_cast<long long>(latched_total));
    return 0;
}
