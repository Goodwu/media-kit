"""Host harness for the mkst bridge lifecycle state machine (A2 acceptance
gate: full lifecycle matrix + concurrent-transition races).

Extracts the MKST-LIFECYCLE block, the real nativeOnFrame AND the real
mkst_latch body from the actual mediakit_surfacetexture_bridge.cpp verbatim.
Since the P8.4 A5 V2 fix the lifecycle block ALSO carries the shared runtime
record (MkstWindowToken / BridgeState / g_state): the create/shutdown mirrors
below therefore execute the real serialized transitions including the
g_state.lock publication. The JNI/GL window build between gate and publish
stays device-only; it carries no lifecycle or runtime-record decision.

P8.4 A5 r2-residual (review P2-1) restructure of the races — the earlier
revision had three reviewer-identified problems, all closed here:
  1. `create_ok > 0` depended on scheduling (a legal schedule where the
     shutdown threads win the lifecycle lock first permanently clears
     `initialized`, so every create is refused — reviewer counterexample
     native/race-legal-schedule.cpp: create threads started 50ms late).
     FIX: the necessary transitions (init + one create per round) are made
     SERIALLY before a barrier releases the racer threads; assertions count
     ONLY those guaranteed transitions, and race outcomes are asserted as
     invariants/identities only. A `create_ok > 0`-style assert on racer
     outcomes is deliberately FORBIDDEN here.
  2. A single init meant the first successful shutdown permanently cleared
     `initialized`, so the whole race degenerated to at most one successful
     create. FIX: multi-round init/create/shutdown/recreate loops (every
     round re-inits serially), plus one case with init racers inside the
     race (concurrent rebind cycle).
  3. No real mkst_latch execution. FIX: the real latch body is extracted
     verbatim (its updateTexImage/getTimestamp JNI calls are inert shims —
     the gate, deadline, cond-wait and counter-consumption decisions are the
     real ones under the real g_state.lock) and raced against shutdown /
     create(+rebind).

Lifecycle matrix — single judging criterion (P2-1 FINAL close-out, CR
终裁 a+b): allowed and forbidden are each stated as ONE criterion, not a
per-pair enumeration. Production contract: the bridge header
(mediakit_surfacetexture_bridge.cpp) plus the mpv importer call chain
cited below (extracted read-only from ~/src/mpv).

  ALLOWED (single criterion; what the race cases below verify): every
  init/create/shutdown state transition is serialized by the ONE
  lifecycle.lock — create and shutdown hold it for their WHOLE body
  (bridge lock discipline: "the serialized transition IS the body,
  including the JNI/GL section") — and no transition state is written
  back outside that lock. Whether the product actually races multiple
  sessions/owners is irrelevant to the criterion: the races below
  exercise mutual init/create/shutdown concurrency as lock-level stress
  and assert exactly the criterion — the transition identity (every
  committed window torn exactly once; window vs init teardowns counted
  separately) and lifecycle/runtime-record consistency
  (race_init_vs_shutdown, race_create_vs_shutdown_rounds,
  race_init_create_shutdown_cycle, reviewer's 50ms-late create schedule
  included). Also host-verified under the same model: callback vs
  lifecycle — stale-frame cross-generation regression below (real
  nativeOnFrame) + reviewer callback-race stays green (closed in the
  A5 V2 fix; kept, no regression).

  Window-lease wording (CR ①, tightened): the window_active gate proves
  ONLY "at most one SUCCESSFULLY CREATED window at any instant" — a
  single successful-window LEASE. It does NOT prove "only one
  initialized instance": an init'd-but-window-less binding can exist
  (the latest explicit init owns the single-instance bridge while no
  window is active — the mkst_lc_init rebind rule,
  mediakit_surfacetexture_bridge.cpp:175-180), and an importer whose
  create was refused keeps running initialized but window-less. Such an
  instance holds NO shutdown right and NO latch right (mpv-side
  ownership-gate evidence, CR ②): owns_decoder_window is set ONLY
  immediately after create_decoder_window SUCCEEDS, independent of
  every later init step (hwdec_surfacetexture.c:423-438); uninit gates
  mkst_shutdown on it (hwdec_surfacetexture.c:509-510), so a
  refused-create / never-created instance's teardown leaves the shared
  bridge untouched; and mkst_latch fires only inside mapper_map of a
  live window (hwdec_surfacetexture.c:1291 — the sole latch call site)
  whose bridge gate refuses without a live window record
  (mediakit_surfacetexture_bridge.cpp:846).

  Ownership self-clear (CR ④): uninit consumes the ownership —
  owns_decoder_window self-clears at teardown ("the flag self-clears so
  a repeated uninit stays inert", hwdec_surfacetexture.c:512-514) — so
  a late second teardown of an OLD owner never fires mkst_shutdown
  again and cannot destroy a NEW lease; the bridge-side mkst_shutdown
  is itself idempotent (already-down -> the _locked step returns 0 and
  logs "no-op (already down)", mediakit_surfacetexture_bridge.cpp:
  1003-1007). mpv Reviewer final-verification table, relayed verbatim
  in the CR ruling: 上述各路径重复 teardown | 无重复 shutdown、纹理删除或窗口释放.

  Owner mapper/latch vs uninit same-thread serialization (CR ③ —
  call-chain artifact from ~/src/mpv, file:line refs; NOT extrapolated
  from the mpv Reviewer's partial-acquire PASS). The registered
  callbacks (hwdec_surfacetexture.c:1511-1523: init/uninit :1516-1517,
  mapper init/uninit/map/unmap :1520-1523) all execute on the ONE vo
  thread:
  - latch path: vo_gpu_next ->draw_frame (vo_gpu_next.c:1018) runs
    pl_render_image_mix in-body (:1454); the pl_frame acquire callback
    is hwdec_acquire (wired :705, body :604) -> ra_hwdec_mapper_map
    (:612) -> driver->map (gpu/hwdec.c:170, dispatch :174) ->
    mapper_map (hwdec_surfacetexture.c:1166), whose ONLY mkst_latch
    call site is o->latch (:1291). vo_gpu equivalent: ->draw_frame
    (vo_gpu.c:73) -> gl_video_render_frame (vo_gpu.c:82; gpu/video.c:
    3444) -> pass_render_frame (gpu/video.c:3501 -> :3102) ->
    pass_upload_image (:3775) -> ra_hwdec_mapper_map.
  - unmap path: hwdec_release (vo_gpu_next.c:625 -> :635) and
    unref_current_image (gpu/video.c:1090 -> :1096) ->
    ra_hwdec_mapper_unmap (gpu/hwdec.c:161, dispatch :163-164) ->
    mapper_unmap (hwdec_surfacetexture.c:1413); ra_hwdec_mapper_free
    unmaps first (gpu/hwdec.c:154-155).
  - uninit path: vo.c vo_thread (:1126) is the single vo thread; its
    loop calls render_frame (:1154), the ONLY caller of
    vo->driver->draw_frame (:1019); after the loop breaks on terminate
    the SAME function calls vo->driver->uninit (:1228). vo_gpu: uninit
    (vo_gpu.c:279) -> gl_video_uninit (vo_gpu.c:283; gpu/video.c:4112)
    -> ra_hwdec_ctx_uninit (:4118) -> ra_hwdec_uninit per driver
    (gpu/hwdec.c:294 -> :114-117) -> uninit
    (hwdec_surfacetexture.c:484) -> p->shutdown() (:509-510).
    vo_gpu_next: uninit (vo_gpu_next.c:2127) -> ra_hwdec_ctx_uninit
    (:2140). The VOCTRL/screenshot side path (vo_gpu_next.c:1603 ->
    :1777, wired at control :1892-1893) reaches the mapper only via
    mp_dispatch_queue_process on the same vo thread (vo.c:1149).
    vo.h fixes the thread model: wakeup() is "the only vo_driver
    function" callable from another thread (vo.h:430-431).
  Conclusion: the importer's mapper/latch and its uninit ->
  mkst_shutdown are strictly serial on the single vo thread — ③ holds
  by call chain, not by extrapolation.

  call constraints (production facts, unchanged):
  - mkst_create_decoder_window / mkst_latch / mkst_shutdown run on the
    ONE mpv GL thread with the caller's EGL context current
    (updateTexImage is legal only there), STRICTLY SERIALLY: one call
    returns before the next begins, and nothing latches across or after
    a teardown on that thread. The lifecycle.lock additionally
    serializes create and shutdown bodies; mkst_latch takes ONLY
    g_state.lock — exactly why a latch's post-updateTexImage write-back
    sits outside every transition's serialization.
  - nativeInit (owner binding) runs on a Java thread; Java nativeInit is
    the only initialization entry (mkst_init refuses while resources
    are unresolved).
  - nativeOnFrame (frame callback) runs on the per-window "mksurf-latch"
    HandlerThread (arbitrary Java thread); it touches only the
    mutex-protected counter — no GL, no JNI calls on Java objects.

  FORBIDDEN (single criterion): ANY cross-generation overlap between a
  latch and a window create/shutdown — the latch's latched_counter
  write-back spans the updateTexImage JNI segment OUTSIDE the
  serialization a transition commits under, so an overlapping
  transition can publish valid=false / a fresh generation under a
  parked latch. create-vs-shutdown and init-vs-create /
  init-vs-shutdown mutual concurrency is NOT forbidden — it is the
  ALLOWED criterion above and the races exercise it as stress.
  - MKST-FORBIDDEN: latch-shutdown-ordered — any latch overlapping a
    create/shutdown/rebind (latch vs shutdown; latch vs
    create/rebind). The counterexample is characterized (reviewer
    latch-shutdown-ordered.cpp, deterministic): a latch parked INSIDE
    updateTexImage — between its g_state.lock gate and the post-JNI
    latched_counter write-back — lets a concurrent shutdown clear the
    record, and the resumed latch then writes latched_counter=1 onto
    the torn record (reviewer log: "valid=0 frame=0 latched=1"; the
    quiescent invariant frame==0 && latched==0 violated).
    Characterization: the locks do NOT protect cross-JNI-segment
    generation consistency; production excludes the combination via the
    serial call constraints; the host makes no concurrency-safety
    declaration for it. forbidden_latch_spans_shutdown_documented below
    pins this: it replays the ordered schedule deterministically and
    asserts the DOCS classification (marker above, injected as a
    constant) plus the hazard shape — never a count final-state safety
    property. The two real-latch race cases keep running as lock-level
    stress (deadlock-freedom: the cond wait releases g_state.lock so a
    lifecycle transition publishes valid=false without waiting;
    documented latch return values) but assert only latch-independent
    properties — the transition identity and lifecycle-record
    consistency, never the counter final state.
  - latch called SERIALLY after a shutdown is NOT the forbidden pair: it
    takes the uninitialized refusal path (-1) — matrix cell below, passing.
  - two concurrent mkst_latch callers (single GL-thread latch is the
    production model; a second latch thread would be a caller-contract
    violation, not a bridge property).
  - updateTexImage outside the GL thread's EGL context (device-side
    discipline).
  - taking g_state.lock and then lifecycle.lock (lock-order inversion; the
    frozen lock discipline forbids it in the code itself).
  - a second decoder window while one is active (the gate refuses; matrix).

  device-pending cells (host CANNOT verify — registered, not silently
  claimed as covered):
  1. Real updateTexImage/getTimestamp against a SurfaceTexture whose Surface
     is released by a shutdown (real JNI/VM timing; excluded in production
     by the serial call constraints above — exercised by the euv device
     rounds, not by this host).
  2. Real EGL-context behavior across create/latch/shutdown on the mpv GL
     thread (host threads are stand-ins; the caller-side serialization is
     device-verified).
"""
import pathlib
import subprocess
import tempfile

source = pathlib.Path(__file__).resolve().parents[2] / 'src/main/cpp/mediakit_surfacetexture_bridge.cpp'
text = source.read_text()
actual = text[text.index('// MKST-LIFECYCLE-BEGIN'):text.index('// MKST-LIFECYCLE-END')]
# In the real file the block lives inside the translation unit's anonymous
# namespace; the harness reproduces that linkage explicitly.
actual = 'namespace {\n' + actual + '\n}  // namespace\n'

# The real nativeOnFrame (production counter gate): extracted verbatim from
# the JNI entry section, from its extern "C" declaration line to its closing
# brace. It references MkstWindowToken/g_state from the lifecycle block.
sig = ('Java_com_alexmercerind_media_1kit_1video_platformview_'
       'MediaCodecSurfaceTextureBridge_nativeOnFrame(')
sig_at = text.index(sig)
fn_at = text.rindex('extern "C" JNIEXPORT void JNICALL', 0, sig_at)
end_at = text.index('\n}\n', sig_at) + len('\n}\n')
on_frame = text[fn_at:end_at]

# The real mkst_latch body (P2-1 fix 3): extracted verbatim from the C API
# section. Its get_env_or_attach / jmethodID / SurfaceTexture-JNI references
# resolve to the inert shims in the prelude; every lock, gate, deadline,
# cond-wait and counter decision is the production one.
latch_sig = 'extern "C" JNIEXPORT int mkst_latch(int timeout_ms, uint64_t* out_ts_ns) {'
latch_at = text.index(latch_sig)
latch_end = text.index('\n}\n', latch_at) + len('\n}\n')
latch = text[latch_at:latch_end]

prelude = r'''
#include <cassert>
#include <cerrno>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <ctime>
#include <pthread.h>
#include <atomic>
#include <chrono>
#include <thread>
#include <vector>
// JNI/GL surface shims: the extracted code uses these only as inert field
// and parameter types (no behavior), exactly as the block comment states.
#define JNIEXPORT
#define JNICALL
#define JNI_TRUE 1
#define JNI_FALSE 0
// The production MKSURF_LOG* macros go to logcat; host prints to stderr.
#define MKSURF_LOGI(...) do { fprintf(stderr, __VA_ARGS__); fprintf(stderr, "\n"); } while (0)
#define MKSURF_LOGW(...) do { fprintf(stderr, __VA_ARGS__); fprintf(stderr, "\n"); } while (0)
using jclass = void*;
using jlong = long long;
using jint = int;
using jboolean = unsigned char;
using GLuint = unsigned int;
using jobject = void*;
using jmethodID = void*;
// Inert JNIEnv shim for the REAL mkst_latch body: the JNI SurfaceTexture
// calls (updateTexImage/getTimestamp) are exactly what stays device-only.
// The shim returns a fixed nonce timestamp so a successful latch's full
// return path (consume -> updateTexImage -> record -> getTimestamp) executes.
// P2-1 close-out negative-lock gate: while g_update_pause_armed is false
// (every other case) this is fully transparent. One case arms it to park a
// latch INSIDE updateTexImage — the reviewer's ordered schedule — so the
// forbidden latch-spans-shutdown characterization is deterministic instead
// of scheduler-dependent.
static std::atomic<bool> g_update_pause_armed{false};
static std::atomic<bool> g_update_parked{false};
static std::atomic<bool> g_update_resume{false};
struct JNIEnv {
    void CallVoidMethod(jobject, jmethodID, ...) {
        if (g_update_pause_armed.load(std::memory_order_acquire)) {
            g_update_parked.store(true, std::memory_order_release);
            while (!g_update_resume.load(std::memory_order_acquire)) {
                std::this_thread::yield();
            }
            g_update_parked.store(false, std::memory_order_release);
        }
    }
    jlong CallLongMethod(jobject, jmethodID, ...) { return 0x00FF1234LL; }
    jboolean ExceptionCheck() { return JNI_FALSE; }
};
static JNIEnv g_fake_env;
// Production get_env_or_attach attaches the mpv GL thread to the JVM; host
// always has the fake env. The state/lock decisions around it are real.
static JNIEnv* get_env_or_attach(const char*) { return &g_fake_env; }
// Production helper clears a pending JNI exception; the shim env never has
// one (the shim's ExceptionCheck is always false), so this only satisfies
// the real latch body's call sites.
static void clear_pending_exception(JNIEnv*, const char*) {}
// jmethodID globals the real latch body dereferences (never called for real
// on host — the shim methods ignore them).
static jmethodID g_mid_update_tex_image = reinterpret_cast<jmethodID>(0x2);
static jmethodID g_mid_get_timestamp = reinterpret_cast<jmethodID>(0x3);
'''

harness = r'''
// --- harness mirrors of the real wrapper sections (state decisions only) ---

// Mirror of mkst_create_decoder_window's serialized section INCLUDING the
// runtime-record publication under g_state.lock: gate under the lifecycle
// lock, publish (fresh token + counters + live SurfaceTexture record +
// valid) under g_state.lock, commit under the lifecycle lock — the same
// order production uses. The surface_texture placeholder (never dereferenced
// on host) exists so the REAL mkst_latch gate
// (!valid || surface_texture == nullptr) behaves exactly like production; a
// null record would refuse every latch for a mirror-only reason. A token is
// minted per create exactly like production (never freed; test-process
// leakage is bounded and irrelevant).
static int lc_create(MkstLifecycle* lc) {
    pthread_mutex_lock(&lc->lock);
    if (mkst_lc_create_gate_locked(lc) != 0) {
        pthread_mutex_unlock(&lc->lock);
        return -1;
    }
    auto* token = new MkstWindowToken();
    token->alive.store(true, std::memory_order_relaxed);
    pthread_mutex_lock(&g_state.lock);
    g_state.tex_name = 1;  // Placeholder: the GL name is device-only.
    g_state.frame_counter = 0;
    g_state.latched_counter = 0;
    g_state.surface_texture = reinterpret_cast<jobject>(
        static_cast<uintptr_t>(0x1));  // Placeholder: JNI deref is device-only.
    g_state.frame_token = token;
    g_state.valid = true;
    pthread_mutex_unlock(&g_state.lock);
    mkst_lc_create_commit_locked(lc);
    pthread_mutex_unlock(&lc->lock);
    return 0;
}

// Harness-only accounting, updated INSIDE lc_shutdown while the lifecycle
// lock is held (create/shutdown bodies are serialized by it, so the
// classification below is exact): a successful shutdown revoked a live
// window (frame_token was set) or tore an initialization-only binding
// (frame_token already null). P2-1 fix: window teardowns and init teardowns
// are counted SEPARATELY and never conflated into one "torn_down" number.
static uint64_t h_window_teardowns = 0;
static uint64_t h_init_teardowns = 0;

// Mirror of mkst_shutdown's serialized section: lifecycle teardown FIRST
// (every lifecycle gate refuses from here on), then the runtime-record
// revocation (valid=false + token revoke + counters) under g_state.lock.
static int lc_shutdown(MkstLifecycle* lc) {
    pthread_mutex_lock(&lc->lock);
    if (mkst_lc_shutdown_locked(lc) == 0) {
        pthread_mutex_unlock(&lc->lock);
        return 0;
    }
    pthread_mutex_lock(&g_state.lock);
    g_state.valid = false;
    if (g_state.frame_token != nullptr) {
        g_state.frame_token->alive.store(false, std::memory_order_relaxed);
        ++h_window_teardowns;
    } else {
        ++h_init_teardowns;
    }
    g_state.frame_token = nullptr;
    g_state.surface_texture = nullptr;
    g_state.frame_counter = 0;
    g_state.latched_counter = 0;
    pthread_mutex_unlock(&g_state.lock);
    pthread_mutex_unlock(&lc->lock);
    return 1;
}

static void reset_runtime_record() {
    pthread_mutex_lock(&g_state.lock);
    g_state.valid = false;
    g_state.frame_token = nullptr;
    g_state.surface_texture = nullptr;
    g_state.frame_counter = 0;
    g_state.latched_counter = 0;
    pthread_mutex_unlock(&g_state.lock);
}

// --- deadlock watchdog: a hung race case must fail, not hang CI ---
static std::atomic<bool> g_done{false};
static void watchdog() {
    const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(60);
    while (!g_done.load() && std::chrono::steady_clock::now() < deadline) {
        std::this_thread::sleep_for(std::chrono::milliseconds(50));
    }
    if (!g_done.load()) {
        fprintf(stderr, "DEADLOCK: race case did not finish in 60s\n");
        std::_Exit(2);
    }
}

// Single-use barrier (macOS host has no pthread_barrier): releases every
// racer only after the serial guaranteed phase committed. Fresh instance per
// phase; never reused.
struct Barrier {
    pthread_mutex_t m = PTHREAD_MUTEX_INITIALIZER;
    pthread_cond_t c = PTHREAD_COND_INITIALIZER;
    int left;
    explicit Barrier(int n) : left(n) {}
    void wait() {
        pthread_mutex_lock(&m);
        if (--left == 0) {
            pthread_cond_broadcast(&c);
        } else {
            pthread_cond_wait(&c, &m);
        }
        pthread_mutex_unlock(&m);
    }
};

struct RunState {
    bool initialized;
    bool window_active;
    bool valid;
    uint64_t owner_key;
    uint32_t generation;
    uint64_t frame;
    uint64_t latched;
};

static RunState snapshot(MkstLifecycle* lc) {
    pthread_mutex_lock(&lc->lock);
    RunState s{};
    s.initialized = lc->initialized;
    s.window_active = lc->window_active;
    s.owner_key = lc->owner_key;
    s.generation = lc->generation;
    pthread_mutex_unlock(&lc->lock);
    pthread_mutex_lock(&g_state.lock);
    s.valid = g_state.valid;
    s.frame = g_state.frame_counter;
    s.latched = g_state.latched_counter;
    pthread_mutex_unlock(&g_state.lock);
    return s;
}

static bool consistent(const RunState& s, const std::vector<uint64_t>& keys,
                       const std::vector<uint32_t>& gens) {
    if (s.window_active && !s.initialized) return false;
    if (!s.initialized && (s.owner_key != 0 || s.generation != 0)) return false;
    if (s.initialized) {
        bool known = false;
        for (size_t i = 0; i < keys.size(); ++i) {
            if (s.owner_key == keys[i] && s.generation == gens[i]) known = true;
        }
        if (!known) return false;
    }
    return true;
}

// Quiescent (post-join, single-threaded) invariants of the runtime record
// against the lifecycle record.
static void assert_quiescent(const RunState& s, const std::vector<uint64_t>& keys,
                             const std::vector<uint32_t>& gens) {
    assert(consistent(s, keys, gens));
    assert(s.valid == s.window_active);  // create/shutdown publish them in step
    if (s.window_active) {
        assert(s.latched <= s.frame);  // a latch never consumes unproduced frames
    } else {
        assert(s.frame == 0 && s.latched == 0);  // torn windows leave no counters
    }
}

// P2-1 close-out: lifecycle-record-only quiescence for the cases that race
// the REAL latch against lifecycle transitions. The counter final state is
// deliberately NOT asserted there: latch/shutdown (and latch/create/rebind)
// concurrency is a FORBIDDEN combination (MKST-FORBIDDEN:
// latch-shutdown-ordered in the module docstring) whose counter hazard is
// pinned deterministically by forbidden_latch_spans_shutdown_documented
// below. Only the latch-independent properties hold and are checked: the
// lifecycle record stays consistent and valid tracks window_active (both
// are lifecycle-driven; the latch never writes them).
static void assert_lifecycle_quiescent(const RunState& s,
                                       const std::vector<uint64_t>& keys,
                                       const std::vector<uint32_t>& gens) {
    assert(consistent(s, keys, gens));
    assert(s.valid == s.window_active);  // create/shutdown publish them in step
}

// The transition-count identity (P2-1): every window committed after the
// accounting baseline — serial guaranteed ones plus racer successes — is
// torn by EXACTLY one window teardown, except a possibly final live one.
// Successful shutdowns split into window teardowns and init-only teardowns;
// the two are counted separately and never conflated.
static void assert_transition_identity(uint64_t guaranteed_windows,
                                       uint64_t racer_creates,
                                       uint64_t window_teardowns,
                                       uint64_t init_teardowns,
                                       uint64_t shutdown_oks,
                                       const RunState& fin) {
    const uint64_t created = guaranteed_windows + racer_creates;
    assert(created == window_teardowns + (fin.window_active ? 1u : 0u));
    assert(shutdown_oks == window_teardowns + init_teardowns);
}

// Serial guaranteed phase per round: clear any racer leftover, re-init, and
// commit one window. Both transitions are ASSERTED here — they are the
// guaranteed conversions the barrier then hands to the racers (P2-1 fix 1).
static void guaranteed_init_create(MkstLifecycle* lc, uint64_t key, uint32_t gen) {
    lc_shutdown(lc);  // Leftover from the previous round, if any.
    assert(mkst_lc_verify(lc) == 0);
    assert(mkst_lc_init(lc, key, gen) == 0);
    assert(lc_create(lc) == 0);
}

// Feed the CURRENT window through the REAL callback entry (what the
// "mksurf-latch" HandlerThread does in production). A token read here can go
// stale before nativeOnFrame runs — the production token revocation makes
// that a strict no-op, which is exactly the behavior under test.
static void feed_current_window(int frames) {
    for (int i = 0; i < frames; ++i) {
        pthread_mutex_lock(&g_state.lock);
        MkstWindowToken* tok = g_state.frame_token;
        const bool valid = g_state.valid;
        pthread_mutex_unlock(&g_state.lock);
        if (valid && tok != nullptr) {
            Java_com_alexmercerind_media_1kit_1video_platformview_MediaCodecSurfaceTextureBridge_nativeOnFrame(
                nullptr, nullptr,
                static_cast<jlong>(reinterpret_cast<uintptr_t>(tok)));
        }
    }
}

static void test_lifecycle_matrix() {
    MkstLifecycle lc;
    const uint64_t k1 = 0xAAAA1111AAAA1111ULL, k2 = 0xBBBB2222BBBB2222ULL;
    const uint32_t g1 = 7, g2 = 9;

    // ensure_init before any init: verify-only reads 0.
    assert(mkst_lc_verify(&lc) == 0);

    // init fresh + idempotent same-tuple repeat.
    assert(mkst_lc_init(&lc, k1, g1) == 0);
    assert(mkst_lc_init(&lc, k1, g1) == 0);
    assert(mkst_lc_verify(&lc) == 1);

    // create gate passes once; second create is refused (single window).
    assert(lc_create(&lc) == 0);
    assert(lc_create(&lc) == -1);

    // Different tuple while the window is active: refused, owner unchanged.
    assert(mkst_lc_init(&lc, k2, g2) == -1);
    RunState s = snapshot(&lc);
    assert(s.initialized && s.window_active && s.owner_key == k1 && s.generation == g1);

    // Latch/get gates are the initialized+window-active pair; the REAL latch
    // gate is exercised by the latch races below (it refuses without a live
    // window record and consumes only new frames).
    s = snapshot(&lc);
    assert(s.window_active && s.valid);

    // Shutdown: explicit teardown, idempotent (second call is a no-op).
    assert(lc_shutdown(&lc) == 1);
    assert(lc_shutdown(&lc) == 0);
    s = snapshot(&lc);
    assert(!s.initialized && !s.window_active && s.owner_key == 0 && s.generation == 0);
    assert(mkst_lc_verify(&lc) == 0);

    // Latch SERIALLY after a shutdown: refused (-1) on the no-live-window
    // path before any JNI call; the timestamp stays zero. Matrix cell for
    // the serial suffix — the CONCURRENT latch-vs-shutdown pair is a
    // forbidden combination (module docstring, MKST-FORBIDDEN:
    // latch-shutdown-ordered), pinned by
    // forbidden_latch_spans_shutdown_documented below.
    {
        uint64_t cell_ts = 0;
        assert(mkst_latch(1, &cell_ts) == -1);
        assert(cell_ts == 0);
    }
    s = snapshot(&lc);
    assert(s.frame == 0 && s.latched == 0);  // The refusal consumed nothing.

    // Rebind after shutdown with a different tuple: allowed.
    assert(mkst_lc_init(&lc, k2, g2) == 0);
    s = snapshot(&lc);
    assert(s.initialized && !s.window_active && s.owner_key == k2 && s.generation == g2);
    assert(lc_create(&lc) == 0);
    assert(lc_create(&lc) == -1);
    assert(lc_shutdown(&lc) == 1);

    // Tuple change with NO active window: latest explicit init wins the
    // single-instance binding (documented rebind; only the active window
    // refuses a foreign tuple).
    assert(mkst_lc_init(&lc, k1, g1) == 0);
    assert(mkst_lc_init(&lc, k2, g2) == 0);
    s = snapshot(&lc);
    assert(s.initialized && s.owner_key == k2 && s.generation == g2);
    assert(lc_shutdown(&lc) == 1);

    // Wrapper-pattern teardown (mkst_shutdown shape): hold the lifecycle
    // lock and use the _locked step; the locking wrapper must never be
    // called under a held lock (self-deadlock on a non-recursive mutex).
    assert(mkst_lc_init(&lc, k1, g1) == 0);
    pthread_mutex_lock(&lc.lock);
    const int torn = mkst_lc_shutdown_locked(&lc);
    pthread_mutex_unlock(&lc.lock);
    assert(torn == 1);
    assert(mkst_lc_verify(&lc) == 0);
}

static void race_init_vs_shutdown() {
    MkstLifecycle lc;
    const std::vector<uint64_t> keys = {0x1111ULL, 0x2222ULL, 0x3333ULL};
    const std::vector<uint32_t> gens = {1, 2, 3};
    std::vector<std::thread> threads;
    for (int t = 0; t < 8; ++t) {
        threads.emplace_back([t, &lc, &keys, &gens] {
            for (int i = 0; i < 20000; ++i) {
                if ((t + i) % 2 == 0) {
                    mkst_lc_init(&lc, keys[(t + i) % keys.size()],
                                 gens[(t + i) % gens.size()]);
                } else {
                    lc_shutdown(&lc);
                }
            }
        });
    }
    for (auto& th : threads) th.join();
    RunState s = snapshot(&lc);
    assert(consistent(s, keys, gens));
    assert(!s.window_active);
}

// P2-1 fixes 1+2: guaranteed serial init+create per round, then a barrier
// releases the racers; assertions count only the guaranteed transitions and
// check race outcomes as identities. The create threads start 50ms late —
// the reviewer's legal-schedule counterexample (their
// race-legal-schedule.cpp asserted create_ok > 0 and failed on exactly this
// schedule); with guaranteed conversions the identity assertions hold on any
// legal schedule, so the counterexample no longer fails the test.
static void race_create_vs_shutdown_rounds() {
    MkstLifecycle lc;
    const uint64_t k1 = 0x4444555544445555ULL;
    const uint32_t g1 = 3;
    const int kRounds = 4;
    for (int r = 0; r < kRounds; ++r) {
        guaranteed_init_create(&lc, k1, g1);  // Counted, asserted, guaranteed.
        // Accounting baseline AFTER the serial phase: only racer-phase
        // transitions enter the identity.
        std::atomic<int> create_ok{0}, torn_down{0};
        const uint64_t wt0 = h_window_teardowns, it0 = h_init_teardowns;
        Barrier barrier(9);  // 4 create + 4 shutdown racers + main.
        std::vector<std::thread> threads;
        for (int t = 0; t < 4; ++t) {
            threads.emplace_back([t, &lc, &barrier, &create_ok] {
                std::this_thread::sleep_for(std::chrono::milliseconds(50));
                barrier.wait();
                for (int i = 0; i < 20000; ++i) {
                    if (lc_create(&lc) == 0) create_ok.fetch_add(1);
                }
            });
        }
        for (int t = 0; t < 4; ++t) {
            threads.emplace_back([&lc, &barrier, &torn_down] {
                barrier.wait();
                for (int i = 0; i < 20000; ++i) {
                    if (lc_shutdown(&lc) == 1) torn_down.fetch_add(1);
                }
            });
        }
        barrier.wait();
        for (auto& th : threads) th.join();
        const RunState fin = snapshot(&lc);
        assert_quiescent(fin, {k1}, {g1});
        assert_transition_identity(
            1, static_cast<uint64_t>(create_ok.load()),
            h_window_teardowns - wt0, h_init_teardowns - it0,
            static_cast<uint64_t>(torn_down.load()), fin);
        fprintf(stderr,
                "race_create_vs_shutdown round %d: racer_create_ok=%d"
                " racer_shutdown_ok=%d window_teardowns=%llu init_teardowns=%llu\n",
                r, create_ok.load(), torn_down.load(),
                (unsigned long long)(h_window_teardowns - wt0),
                (unsigned long long)(h_init_teardowns - it0));
    }
}

// P2-1 fix 2 (concurrent recreate): init racers INSIDE the race, so the
// legal interleavings cycle rebind -> create -> teardown repeatedly instead
// of degenerating after the first shutdown (single-init limitation).
static void race_init_create_shutdown_cycle() {
    MkstLifecycle lc;
    const std::vector<uint64_t> keys = {0x1111ULL, 0x2222ULL, 0x3333ULL};
    const std::vector<uint32_t> gens = {1, 2, 3};
    guaranteed_init_create(&lc, keys[0], gens[0]);
    std::atomic<int> create_ok{0}, torn_down{0};
    const uint64_t wt0 = h_window_teardowns, it0 = h_init_teardowns;
    Barrier barrier(9);  // 2 init + 3 create + 3 shutdown racers + main.
    std::vector<std::thread> threads;
    for (int t = 0; t < 2; ++t) {
        threads.emplace_back([t, &lc, &barrier, &keys, &gens] {
            barrier.wait();
            for (int i = 0; i < 20000; ++i) {
                mkst_lc_init(&lc, keys[t % keys.size()], gens[t % gens.size()]);
            }
        });
    }
    for (int t = 0; t < 3; ++t) {
        threads.emplace_back([t, &lc, &barrier, &create_ok] {
            std::this_thread::sleep_for(std::chrono::milliseconds(50));
            barrier.wait();
            for (int i = 0; i < 20000; ++i) {
                if (lc_create(&lc) == 0) create_ok.fetch_add(1);
            }
        });
    }
    for (int t = 0; t < 3; ++t) {
        threads.emplace_back([&lc, &barrier, &torn_down] {
            barrier.wait();
            for (int i = 0; i < 20000; ++i) {
                if (lc_shutdown(&lc) == 1) torn_down.fetch_add(1);
            }
        });
    }
    barrier.wait();
    for (auto& th : threads) th.join();
    const RunState fin = snapshot(&lc);
    assert_quiescent(fin, keys, gens);
    assert_transition_identity(
        1, static_cast<uint64_t>(create_ok.load()),
        h_window_teardowns - wt0, h_init_teardowns - it0,
        static_cast<uint64_t>(torn_down.load()), fin);
    fprintf(stderr,
            "race_init_create_shutdown_cycle: racer_create_ok=%d"
            " racer_shutdown_ok=%d window_teardowns=%llu init_teardowns=%llu\n",
            create_ok.load(), torn_down.load(),
            (unsigned long long)(h_window_teardowns - wt0),
            (unsigned long long)(h_init_teardowns - it0));
}

// Real-latch race (P2-1 fix 3; reclassified by the P2-1 close-out): the
// REAL mkst_latch body runs against concurrent shutdowns after a guaranteed
// window + guaranteed successful latch. This races a FORBIDDEN combination
// (MKST-FORBIDDEN: latch-shutdown-ordered) and is kept as lock-level stress
// only. Asserts: every latch outcome is one of the documented return
// values; no deadlock (the cond wait releases g_state.lock, so shutdown
// publishes valid=false without waiting for the latch); transition identity;
// lifecycle-record consistency via assert_lifecycle_quiescent. Whether the
// racer latch ever succeeds is a legal scheduling outcome and is NOT
// asserted; the COUNTER FINAL STATE is NOT asserted (a latch write-back
// spanning a teardown can leave latched>0 on a torn record — the
// characterized counterexample, excluded in production by the
// single-GL-thread serial model).
static void race_latch_vs_shutdown() {
    reset_runtime_record();
    MkstLifecycle lc;
    const uint64_t k1 = 0x6666666666666666ULL;
    const uint32_t g1 = 6;
    // Guaranteed phase (serial): window + one frame + one real latch that
    // MUST succeed (guaranteed transition, counted/asserted here).
    assert(mkst_lc_init(&lc, k1, g1) == 0);
    assert(lc_create(&lc) == 0);
    const jlong handle = static_cast<jlong>(reinterpret_cast<uintptr_t>(
        g_state.frame_token));
    Java_com_alexmercerind_media_1kit_1video_platformview_MediaCodecSurfaceTextureBridge_nativeOnFrame(
        nullptr, nullptr, handle);
    assert(g_state.frame_counter == 1);
    uint64_t ts = 0;
    assert(mkst_latch(100, &ts) == 0);
    assert(ts == 0x00FF1234);  // The shim timestamp: full return path ran.
    assert(g_state.latched_counter == 1);

    std::atomic<int> latch_consumed{0}, latch_timeout{0}, latch_refused{0},
        torn_down{0};
    const uint64_t wt0 = h_window_teardowns, it0 = h_init_teardowns;
    Barrier barrier(6);  // 1 latch + 1 feeder + 3 shutdown racers + main.
    std::vector<std::thread> threads;
    threads.emplace_back([&lc, &barrier, &latch_consumed, &latch_timeout,
                          &latch_refused] {
        barrier.wait();
        uint64_t lts = 0;
        for (int i = 0; i < 5000; ++i) {
            const int rc = mkst_latch(1, &lts);
            assert(rc == 0 || rc == 1 || rc == -1);  // Documented outcomes only.
            if (rc == 0) latch_consumed.fetch_add(1);
            else if (rc == 1) latch_timeout.fetch_add(1);
            else latch_refused.fetch_add(1);
        }
    });
    threads.emplace_back([&barrier] {
        barrier.wait();
        feed_current_window(40000);
    });
    for (int t = 0; t < 3; ++t) {
        threads.emplace_back([&lc, &barrier, &torn_down] {
            barrier.wait();
            for (int i = 0; i < 20000; ++i) {
                if (lc_shutdown(&lc) == 1) torn_down.fetch_add(1);
            }
        });
    }
    barrier.wait();
    for (auto& th : threads) th.join();
    const RunState fin = snapshot(&lc);
    // Forbidden combination (see head comment): lifecycle-record-only
    // quiescence; the counter final state is deliberately not asserted.
    assert_lifecycle_quiescent(fin, {k1}, {g1});
    // No create racers: the guaranteed window is the only window ever
    // committed after the baseline.
    assert_transition_identity(1, 0, h_window_teardowns - wt0,
                               h_init_teardowns - it0,
                               static_cast<uint64_t>(torn_down.load()), fin);
    fprintf(stderr,
            "race_latch_vs_shutdown: latch consumed=%d timeout=%d refused=%d"
            " shutdown_ok=%d\n",
            latch_consumed.load(), latch_timeout.load(), latch_refused.load(),
            torn_down.load());
}

// Real-latch vs create/rebind (P2-1 fix 3; reclassified by the P2-1
// close-out): guaranteed serial window + latch, then latch + create +
// shutdown + init racers cycle (with the reviewer's 50ms-late create
// schedule). This races FORBIDDEN combinations (MKST-FORBIDDEN:
// latch-shutdown-ordered) and is kept as lock-level stress only. The latch
// racer outcomes are asserted only as documented return values; create
// successes enter the transition identity; lifecycle-record consistency via
// assert_lifecycle_quiescent. The COUNTER FINAL STATE is NOT asserted (a
// latch write-back spanning a teardown/recreate can land on a foreign
// generation — the characterized counterexample, excluded in production by
// the single-GL-thread serial model).
static void race_latch_vs_create() {
    reset_runtime_record();
    MkstLifecycle lc;
    const std::vector<uint64_t> keys = {0x7777777777777777ULL, 0x1111ULL,
                                        0x2222ULL};
    const std::vector<uint32_t> gens = {7, 1, 2};
    // Guaranteed phase (serial): init + window + frame + one real latch.
    assert(mkst_lc_init(&lc, keys[0], gens[0]) == 0);
    assert(lc_create(&lc) == 0);
    const jlong handle = static_cast<jlong>(reinterpret_cast<uintptr_t>(
        g_state.frame_token));
    Java_com_alexmercerind_media_1kit_1video_platformview_MediaCodecSurfaceTextureBridge_nativeOnFrame(
        nullptr, nullptr, handle);
    uint64_t ts = 0;
    assert(mkst_latch(100, &ts) == 0);
    assert(g_state.latched_counter == 1);

    std::atomic<int> latch_consumed{0}, latch_timeout{0}, latch_refused{0},
        create_ok{0}, torn_down{0};
    const uint64_t wt0 = h_window_teardowns, it0 = h_init_teardowns;
    Barrier barrier(9);  // 1 latch + 1 feeder + 2 create + 2 shutdown + 2 init + main.
    std::vector<std::thread> threads;
    threads.emplace_back([&barrier, &latch_consumed, &latch_timeout,
                          &latch_refused] {
        barrier.wait();
        uint64_t lts = 0;
        for (int i = 0; i < 5000; ++i) {
            const int rc = mkst_latch(1, &lts);
            assert(rc == 0 || rc == 1 || rc == -1);
            if (rc == 0) latch_consumed.fetch_add(1);
            else if (rc == 1) latch_timeout.fetch_add(1);
            else latch_refused.fetch_add(1);
        }
    });
    threads.emplace_back([&barrier] {
        barrier.wait();
        feed_current_window(40000);
    });
    for (int t = 0; t < 2; ++t) {
        threads.emplace_back([t, &lc, &barrier, &create_ok] {
            std::this_thread::sleep_for(std::chrono::milliseconds(50));
            barrier.wait();
            for (int i = 0; i < 20000; ++i) {
                if (lc_create(&lc) == 0) create_ok.fetch_add(1);
            }
        });
    }
    for (int t = 0; t < 2; ++t) {
        threads.emplace_back([&lc, &barrier, &torn_down] {
            barrier.wait();
            for (int i = 0; i < 20000; ++i) {
                if (lc_shutdown(&lc) == 1) torn_down.fetch_add(1);
            }
        });
    }
    for (int t = 1; t < 3; ++t) {  // Rebind racers: tuples 1 and 2.
        threads.emplace_back([t, &lc, &barrier, &keys, &gens] {
            barrier.wait();
            for (int i = 0; i < 20000; ++i) {
                mkst_lc_init(&lc, keys[t], gens[t]);
            }
        });
    }
    barrier.wait();
    for (auto& th : threads) th.join();
    const RunState fin = snapshot(&lc);
    // Forbidden combination (see head comment): lifecycle-record-only
    // quiescence; the counter final state is deliberately not asserted.
    assert_lifecycle_quiescent(fin, keys, gens);
    assert_transition_identity(1, static_cast<uint64_t>(create_ok.load()),
                               h_window_teardowns - wt0,
                               h_init_teardowns - it0,
                               static_cast<uint64_t>(torn_down.load()), fin);
    fprintf(stderr,
            "race_latch_vs_create: latch consumed=%d timeout=%d refused=%d"
            " racer_create_ok=%d shutdown_ok=%d\n",
            latch_consumed.load(), latch_timeout.load(), latch_refused.load(),
            create_ok.load(), torn_down.load());
}

// P2-1 close-out negative lock (reviewer counterexample
// latch-shutdown-ordered.cpp, reviewer close condition 1): deterministic
// replay of the FORBIDDEN ordered schedule — the latch is parked INSIDE
// updateTexImage (between its g_state.lock gate and the post-JNI
// latched_counter write-back), a shutdown tears the record down, then the
// latch resumes and writes across the teardown.
//
// What IS asserted here:
//   1. Docs classification: the combination is declared forbidden. The
//      Python driver injects MKST_FORBIDDEN_LATCH_SHUTDOWN_ORDERED iff its
//      docstring carries the "MKST-FORBIDDEN: latch-shutdown-ordered"
//      marker and asserts the stale lock-level-legality claim is gone.
//   2. The counterexample's hazard shape reproduces deterministically on
//      this schedule: the latch completes (rc == 0, shim timestamp) and its
//      write-back lands AFTER the teardown, leaving latched>0 on a torn
//      record (the reviewer log's "valid=0 frame=0 latched=1"). This pins
//      the CURRENT product semantics (no cross-segment token check — see
//      the bridge header comment); if multi-thread lifecycle is ever
//      legalized, that comment's token-check precondition and this pin must
//      change together.
//
// What is deliberately NOT asserted: count final-state SAFETY for this
// combination. assert_quiescent is intentionally not applied — the pinned
// state violates it BY DESIGN of the forbidden schedule, which is exactly
// why production excludes the combination (single GL thread serializes
// create/latch/shutdown; nothing latches across a teardown).
static void forbidden_latch_spans_shutdown_documented() {
#ifdef MKST_FORBIDDEN_LATCH_SHUTDOWN_ORDERED
    // Docs marker present: the forbidden classification is load-bearing.
#else
    assert(!"latch/shutdown ordered concurrency must be declared forbidden"
            " (missing MKST-FORBIDDEN docstring marker)");
#endif
    reset_runtime_record();
    MkstLifecycle lc;
    const uint64_t k1 = 0x8888888888888888ULL;
    const uint32_t g1 = 8;
    assert(mkst_lc_init(&lc, k1, g1) == 0);
    assert(lc_create(&lc) == 0);
    const jlong handle = static_cast<jlong>(reinterpret_cast<uintptr_t>(
        g_state.frame_token));
    Java_com_alexmercerind_media_1kit_1video_platformview_MediaCodecSurfaceTextureBridge_nativeOnFrame(
        nullptr, nullptr, handle);
    assert(g_state.frame_counter == 1);

    // Park the latch inside updateTexImage, then run the shutdown exactly
    // as the reviewer's ordered schedule does (the latch holds NO
    // g_state.lock while parked — that gap is the characterized hole).
    g_update_pause_armed.store(true, std::memory_order_release);
    std::thread latch_thread([] {
        uint64_t lts = 0;
        const int rc = mkst_latch(1000, &lts);
        assert(rc == 0);  // The write-back completed across the teardown.
        assert(lts == 0x00FF1234);
    });
    while (!g_update_parked.load(std::memory_order_acquire)) {
        std::this_thread::yield();
    }
    assert(lc_shutdown(&lc) == 1);
    g_update_resume.store(true, std::memory_order_release);
    latch_thread.join();
    g_update_pause_armed.store(false, std::memory_order_release);
    g_update_resume.store(false, std::memory_order_release);

    const RunState fin = snapshot(&lc);
    assert(!fin.initialized && !fin.window_active && !fin.valid);
    // Hazard shape (NOT a safety assertion): the write-back landed on the
    // torn record. Reachable ONLY through the forbidden combination — that
    // is the characterization the docs now fix.
    assert(fin.frame == 0 && fin.latched == 1);
    fprintf(stderr,
            "forbidden latch-spans-shutdown replay (docs: FORBIDDEN,"
            " MKST-FORBIDDEN: latch-shutdown-ordered): valid=%d frame=%llu"
            " latched=%llu\n",
            fin.valid ? 1 : 0, (unsigned long long)fin.frame,
            (unsigned long long)fin.latched);
}

// P8.4 A5 V2 regression (reviewer counterexample native/stale-frame.cpp):
// a queued callback carrying a torn-down window's handle must have ZERO
// effect on the next window's counters. Uses the REAL nativeOnFrame
// extracted verbatim above, not a harness copy.
static void stale_frame_callback_cross_generation() {
    reset_runtime_record();
    MkstLifecycle lc;
    assert(mkst_lc_init(&lc, 0x51515151ULL, 5) == 0);
    assert(lc_create(&lc) == 0);
    MkstWindowToken* old_token = g_state.frame_token;
    const jlong old_handle =
        static_cast<jlong>(reinterpret_cast<uintptr_t>(old_token));
    assert(lc_shutdown(&lc) == 1);
    // Recreate (next window generation): a NEW token is minted and the
    // counters restart from zero.
    assert(mkst_lc_init(&lc, 0x51515151ULL, 5) == 0);
    assert(lc_create(&lc) == 0);
    MkstWindowToken* new_token = g_state.frame_token;
    assert(new_token != nullptr && new_token != old_token);
    assert(g_state.frame_counter == 0);

    // Late callback from the torn-down window: ignored — zero effect on the
    // new window (the fixed &g_state identity it used to compare against
    // counted 1 here before the fix).
    Java_com_alexmercerind_media_1kit_1video_platformview_MediaCodecSurfaceTextureBridge_nativeOnFrame(
        nullptr, nullptr, old_handle);
    assert(g_state.frame_counter == 0);
    // A zero handle is ignored outright.
    Java_com_alexmercerind_media_1kit_1video_platformview_MediaCodecSurfaceTextureBridge_nativeOnFrame(
        nullptr, nullptr, 0);
    assert(g_state.frame_counter == 0);
    // The CURRENT window's handle still counts.
    Java_com_alexmercerind_media_1kit_1video_platformview_MediaCodecSurfaceTextureBridge_nativeOnFrame(
        nullptr, nullptr,
        static_cast<jlong>(reinterpret_cast<uintptr_t>(new_token)));
    assert(g_state.frame_counter == 1);

    // After shutdown the stale AND the now-revoked current handle are both
    // inert: no resurrection, no counter growth.
    assert(lc_shutdown(&lc) == 1);
    Java_com_alexmercerind_media_1kit_1video_platformview_MediaCodecSurfaceTextureBridge_nativeOnFrame(
        nullptr, nullptr, old_handle);
    Java_com_alexmercerind_media_1kit_1video_platformview_MediaCodecSurfaceTextureBridge_nativeOnFrame(
        nullptr, nullptr,
        static_cast<jlong>(reinterpret_cast<uintptr_t>(new_token)));
    assert(g_state.frame_counter == 0);
}

int main() {
    test_lifecycle_matrix();
    {
        std::thread w(watchdog);
        race_init_vs_shutdown();
        race_create_vs_shutdown_rounds();
        race_init_create_shutdown_cycle();
        race_latch_vs_shutdown();
        race_latch_vs_create();
        forbidden_latch_spans_shutdown_documented();
        stale_frame_callback_cross_generation();
        g_done.store(true);
        w.join();
    }
    puts("mkst lifecycle core: matrix (init idem/refuse/rebind, create x2,"
         " verify-only, shutdown idem, latch-after-shutdown refusal) +"
         " guaranteed-transition races (init vs shutdown; create vs shutdown"
         " rounds with serial init+create per round and identity assertions,"
         " reviewer's 50ms schedule included; concurrent rebind cycle; REAL"
         " mkst_latch vs shutdown and vs create/rebind as lock-level stress"
         " only) + forbidden latch-spans-shutdown negative lock (docs:"
         " FORBIDDEN, hazard shape pinned) + stale-frame cross-generation"
         " regression passed");
}
'''

# --- P2-1 close-out negative lock (reviewer close condition 1) --------------
# ANY latch overlapping a window create/shutdown — latch vs shutdown and
# latch vs create/rebind — is a FORBIDDEN combination (matrix block in the
# module docstring above). create-vs-shutdown and init-vs-* races are the
# ALLOWED lifecycle.lock-serialized criterion, NOT forbidden. The
# declaration itself is machine-checked
# before any C++ runs: the docstring must carry the MKST-FORBIDDEN marker
# and the stale lock-level-legality claim must be gone. The C++ negative
# case's docs constant is injected IFF the marker is present, so
# forbidden_latch_spans_shutdown_documented asserts "the docs declare this
# combination forbidden" (plus the deterministic hazard shape) — never a
# count final-state safety property.
_FORBIDDEN_MARKER = 'MKST-FORBIDDEN: latch-shutdown-ordered'
_STALE_CLAIM = 'legal at the lock level'
if _FORBIDDEN_MARKER not in __doc__:
    raise AssertionError(
        'docstring must declare latch/shutdown ordered concurrency forbidden'
        ' (missing marker: ' + _FORBIDDEN_MARKER + ')')
if _STALE_CLAIM in __doc__:
    raise AssertionError(
        'stale claim ' + repr(_STALE_CLAIM) + ' must not survive the P2-1'
        ' close-out reclassification')
forbidden_define = '#define MKST_FORBIDDEN_LATCH_SHUTDOWN_ORDERED 1\n'

with tempfile.TemporaryDirectory(prefix='mkst-lifecycle-') as tmp:
    cpp = pathlib.Path(tmp) / 'test.cpp'
    cpp.write_text(forbidden_define + prelude + actual + '\n' + on_frame + '\n'
                   + latch + '\n' + harness)
    exe = pathlib.Path(tmp) / 'test'
    subprocess.run(['clang++', '-std=c++17', '-O2', '-pthread',
                    str(cpp), '-o', str(exe)], check=True)
    subprocess.run([str(exe)], check=True)
