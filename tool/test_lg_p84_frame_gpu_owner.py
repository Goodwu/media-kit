"""E1 host tests for the M2' frame GPU timer owner (mks_frame_gpu_timer.h).

Drives the real header with a fake GL vtable: context-global read-and-clear
DISJOINT injection only (no per-query disjoint), per-query AVAILABLE, call
tracking for the zero-Flush/Finish assertions, and ledger identity checks.
Not a GPU/driver test.
"""
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2] / 'mpv'
HEADER = ROOT / 'video/out/mks_frame_gpu_timer.h'

STUBS = r'''
#include <assert.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <inttypes.h>
#include <stdlib.h>

struct mp_log;
struct GL;





typedef long long GLint64;
#define GL_QUERY_RESULT_AVAILABLE 0x8867
#define GL_QUERY_RESULT 0x8866
typedef unsigned int GLuint;
typedef unsigned int GLenum;
typedef int GLint;
typedef unsigned long long GLuint64;

// fake clock
static uint64_t fake_now = 1000000;
static uint64_t mp_time_ns(void) { return fake_now += 1000; }

// ---- fake GL ----
#define FAKE_Q 128
enum { FQ_FREE, FQ_ALLOC, FQ_BOUND, FQ_ENDED, FQ_DELETED };
struct fake_gl_state {
    bool disjoint;                 // context-wide read-and-clear flag
    bool available[FAKE_Q];
    int name_state[FAKE_Q];        // index by query NAME (1-based ids)
    GLuint current;                // current bound query name, 0 = none
    // call tracking
    char calls[512][64];
    int ncalls;
} fg;
static void fg_reset(void) {
    memset(&fg, 0, sizeof(fg));
    for (int i = 0; i < FAKE_Q; i++) fg.name_state[i] = FQ_FREE;
}
static void fg_track(const char *what) {
    if (fg.ncalls < 512) snprintf(fg.calls[fg.ncalls++], 64, "%s", what);
}
static int fg_find_slot(const GLuint *ids, int n, GLuint name) {
    for (int i = 0; i < n; i++) if (ids[i] == name) return i;
    return -1;
}
static void fg_gen(int n, unsigned int *ids) {
    fg_track("GenQueries");
    int placed = 0;
    for (GLuint name = 1; name < FAKE_Q && placed < n; name++)
        if (fg.name_state[name] == FQ_FREE) { ids[placed++] = name; fg.name_state[name] = FQ_ALLOC; }
}
static void fg_del(int n, const unsigned int *ids) {
    fg_track("DeleteQueries");
    for (int i = 0; i < n; i++) {
        int s = fg_find_slot(NULL, 0, ids[i]);
        (void)s;
        if (ids[i] < FAKE_Q) fg.name_state[ids[i]] = FQ_DELETED;
    }
}
static void fg_begin(unsigned int target, unsigned int name) {
    fg_track("BeginQuery");
    // GL: a name whose previous query has ended is legal to restart.
    assert(fg.name_state[name] == FQ_ALLOC || fg.name_state[name] == FQ_ENDED);
    assert(fg.current == 0); // one bound query at a time
    fg.name_state[name] = FQ_BOUND;
    fg.current = name;
}
static void fg_end(unsigned int target) {
    fg_track("EndQuery");
    assert(fg.current);
    fg.name_state[fg.current] = FQ_ENDED;
    fg.current = 0;
}
static void fg_getqiv(unsigned int target, unsigned int pname, int *params) {
    if (pname == 0x8865) *params = (int)fg.current;
    else if (pname == 0x8864) *params = 32;
    else assert(0);
}
static void fg_getiv(unsigned int pname, int *params) {
    if (pname == 0x8FBB) { *params = fg.disjoint ? 1 : 0; fg.disjoint = false; fg_track("DISJOINT-READ"); }
    else if (pname == 0x8865) *params = (GLint)fg.current;
    else if (pname == 0x8864) *params = 32;
    else { printf("fg_getiv unhandled pname=0x%x\n", pname); assert(0); }
}
static GLuint64 fg_result[FAKE_Q];
static void fg_getobj_uiv(unsigned int name, unsigned int pname, unsigned int *params) {
    if (pname == 0x8867) { *params = fg.available[name] ? 1 : 0; fg_track("AVAILABLE"); }
    else if (pname == 0x8866) { *params = (GLuint)fg_result[name]; fg_track("RESULT"); }
    else assert(0);
}
static void fg_getobj_u64(unsigned int name, unsigned int pname, unsigned long long *params) {
    assert(pname == 0x8866);
    *params = fg_result[name];
    fg_track("RESULT64");
}
static void *cur_ctx;
static void *fg_get_ctx(void) { return cur_ctx; }
static struct fake_gl_extra {
    int begin_calls, end_calls, gen_calls, del_calls;
} fge;

// the header redefines names; include after our fakes
#define emit_capture_n 0
struct mks_fgt_owner;
static char emitted[4096][600];
static int emitted_n;
static void emit_cb(void *ud, const char *line) {
    (void)ud;
    if (emitted_n < 4096) snprintf(emitted[emitted_n++], 600, "%s", line);
}
static void emitted_reset(void) { emitted_n = 0; }
static int emitted_count(void) { return emitted_n; }
static const char *emitted_at(int i) { return emitted[i]; }
'''

TEST = r'''
static struct mks_fgt_owner o;
static struct mks_fgt_gl glvt;
static const GLuint64 NS1 = 1500000;

static void fg_end_semantic(GLenum target, GLuint name) { (void)target; (void)name; }

static void hook_init(const char *mode) {
    memset(&glvt, 0, sizeof(glvt));
    glvt.gen_queries = fg_gen;
    glvt.delete_queries = fg_del;
    glvt.begin_query = fg_begin;
    glvt.end_query = fg_end;
    glvt.get_integerv = fg_getiv;
    glvt.get_query_object_uiv = fg_getobj_uiv;
    glvt.get_query_object_ui64v = fg_getobj_u64;
    glvt.get_current_context = fg_get_ctx;
    glvt.get_query_iv = fg_getqiv;
    fg_reset();
    cur_ctx = (void *)0x1234;
    emitted_reset();
    memset(&o, 0, sizeof(o));
    o.fgt = glvt;
    mks_fgt_init(&o, NULL, mode, emit_cb, NULL, fg_get_ctx);
    if (getenv("FGT_DEBUG"))
        printf("init mode=%s enabled=%d armed=%d ctx=%p entry_ok_done\n",
               mode, o.enabled, o.armed, cur_ctx);
    fge.begin_calls = 0;
}

// helpers to drive a standard fresh-copy fused ticket
static int tk_idx(void) { return o.active; }
static bool open_ticket(uint64_t pts) {
    bool ok = mks_fgt_ticket_open(&o, pts, 1, 1, 1, MKS_FGT_ROUTE_FUSED);
    assert(ok);
    mks_fgt_render_begin(&o, 1);
    mks_fgt_suspend(&o, MKS_FGT_SUSP_ACQ);
    return ok;
}
static void close_fresh_flow(void) {
    mks_fgt_resume(&o, MKS_FGT_SUSP_ACQ);
    mks_fgt_render_end(&o, true);
    mks_fgt_draw_seal(&o, true);
    mks_fgt_swap_issue(&o);
    mks_fgt_submit_result(&o, true);
    mks_fgt_swap_result(&o, true, 0, false);
    mks_fgt_flip_close(&o, true, false, false);
}
static void make_all_available(void) {
    for (int i = 0; i < FAKE_Q; i++) fg.available[i] = true;
    fg_result[0] = NS1;
}

static void test_normal_r1_flow(void) {
    hook_init("frame");
    assert(o.enabled && o.armed && !o.halted);
    open_ticket(10.0);
    if (getenv("FGT_DEBUG"))
        printf("pre-copy: active=%d susp=%d render_entry=%d active_seg=%d refused_copy_outside=%"PRIu64" refused_no_ticket=%"PRIu64" refused_other=%"PRIu64"\n",
               o.active, o.susp, o.render_entry, o.active_seg,
               o.refused_copy_outside, o.refused_no_ticket, o.refused_other);
    if (!mks_fgt_copy_begin(&o, NULL)) {
        for (int i = 0; i < emitted_n; i++)
            printf("CAP[%d]=%s\n", i, emitted_at(i));
        printf("invariant=%s enabled=%d\n", o.invariant, o.enabled);
        assert(0);
    }
    make_all_available();
    mks_fgt_copy_end(&o);
    mks_fgt_copy_record(&o, 10.0, 3840, 1920, 3840, 1920, false, "seg", 1, true);
    close_fresh_flow();
    mks_fgt_poll(&o);
    struct mks_fgt_ticket *tk = &o.tickets[tk_idx()];
    assert(tk->measure == MKS_FGT_M_SWAP_SEALED);
    assert(tk->submit == MKS_FGT_SUB_OK);
    assert(tk->present == MKS_FGT_PR_SWAP_OK);
    assert(tk->num_segs == 3); // pre + copy + post
    assert(tk->segs[0].kind == MKS_FGT_K_RENDER_PRE && tk->segs[0].tstate == MKS_FGT_TS_RESOLVED);
    assert(tk->segs[1].kind == MKS_FGT_K_COPY && tk->segs[1].tstate == MKS_FGT_TS_RESOLVED);
    assert(tk->segs[2].kind == MKS_FGT_K_RENDER_POST && tk->segs[2].tstate == MKS_FGT_TS_RESOLVED);
    assert(tk->copies_ok == 1);
    assert(o.bind == 3 && o.rel_result == 3 && o.busy_normal == 0);
    // zero forbidden GL calls
    for (int i = 0; i < fg.ncalls; i++) {
        assert(strncmp(fg.calls[i], "Flush", 5) != 0);
        assert(strncmp(fg.calls[i], "Finish", 6) != 0);
        assert(strncmp(fg.calls[i], "Fence", 5) != 0);
        assert(strncmp(fg.calls[i], "ClientWait", 10) != 0);
    }
}

static void test_r2_carried_span(void) {
    hook_init("frame-span");
    open_ticket(20.0);
    assert(mks_fgt_copy_begin(&o, NULL)); // opens span, carried
    make_all_available();
    mks_fgt_copy_end(&o);                 // span continues
    assert(o.active_seg >= 0 && o.carried);
    mks_fgt_resume(&o, MKS_FGT_SUSP_ACQ); // carried: no new Begin
    assert(o.carried == false);
    mks_fgt_render_end(&o, true);         // span closes here
    mks_fgt_draw_seal(&o, true);
    mks_fgt_swap_issue(&o);
    mks_fgt_swap_result(&o, true, 0, false);
    mks_fgt_flip_close(&o, true, false, false);
    mks_fgt_poll(&o);
    struct mks_fgt_ticket *tk = &o.tickets[tk_idx()];
    // R2: span1 (pre-acquire) ended at suspend(acq); span2 (copy+post, carried)
    // ended at render_end. Two physical queries, both resolved.
    assert(tk->num_segs == 2);
    assert(tk->segs[0].kind == MKS_FGT_K_SPAN && tk->segs[0].tstate == MKS_FGT_TS_RESOLVED);
    assert(tk->segs[1].kind == MKS_FGT_K_SPAN && tk->segs[1].tstate == MKS_FGT_TS_RESOLVED);
    assert(o.bind == 2 && o.rel_result == 2);
}

static void test_frame_count_zero_gl(void) {
    hook_init("frame-count");
    int gen_calls_before = fg.ncalls;
    open_ticket(30.0);
    assert(mks_fgt_copy_begin(&o, NULL));
    mks_fgt_copy_end(&o);
    mks_fgt_copy_record(&o, 30.0, 3840, 1920, 2672, 1336, true, "seg", 1, true);
    close_fresh_flow();
    struct mks_fgt_ticket *tk = &o.tickets[tk_idx()];
    assert(tk->num_segs == 3);
    for (int i = 0; i < tk->num_segs; i++)
        assert(tk->segs[i].tstate == MKS_FGT_TS_NOT_TIMED && !tk->segs[i].issued);
    assert(tk->copies_ok == 1);
    // frame-count: no GL query calls at all after init
    assert(o.bind == 0 && o.rel_result == 0 && o.busy_normal == 0);
    (void)gen_calls_before;
}

static void test_sealed_semantics(void) {
    hook_init("frame");
    open_ticket(40.0);
    mks_fgt_draw_seal(&o, true);
    // render/copy Begin refused after draw_sealed
    int pre_calls = fg.ncalls;
    assert(!mks_fgt_copy_begin(&o, NULL));
    assert(o.refused_after_seal == 1);
    // final is allowed after draw_sealed (split route)
    mks_fgt_final_begin(&o);
    mks_fgt_final_end(&o);
    mks_fgt_swap_issue(&o);
    mks_fgt_swap_result(&o, false, 0, false);
    mks_fgt_flip_close(&o, true, false, false);
    (void)pre_calls;
    // new ticket: swap_sealed rejects final too
    open_ticket(41.0);
    mks_fgt_swap_issue(&o);
    mks_fgt_swap_result(&o, true, 0, false);
    mks_fgt_flip_close(&o, true, false, false);
    // all Begin refused after swap_sealed: open a fresh ticket and seal it
    open_ticket(42.0);
    mks_fgt_draw_seal(&o, true);
    mks_fgt_swap_issue(&o);
    mks_fgt_swap_result(&o, true, 0, false);
    mks_fgt_flip_close(&o, true, false, false);
}

static void test_hol_scenario_A(void) {
    hook_init("frame");
    // T0: fresh copy stays in flight forever (its query never AVAILABLE).
    open_ticket(50.0);
    assert(mks_fgt_copy_begin(&o, NULL));
    int t0_idx = tk_idx();
    struct mks_fgt_ticket *t0 = &o.tickets[t0_idx];
    assert(t0->num_segs == 2); // helper's render.pre + copy
    int t0_query = (int)t0->segs[1].query;
    // Abandoned-look flow, but acquire/release stay paired (production
    // guarantees this): resume, render_end, then seal and settle without
    // ever making T0's copy query available.
    mks_fgt_resume(&o, MKS_FGT_SUSP_ACQ);
    mks_fgt_render_end(&o, true);
    mks_fgt_draw_seal(&o, false);
    mks_fgt_flip_close(&o, false, true, false); // no_swap:guard_unpending
    // 33 later tickets, each fully settled; all queries available except T0's.
    for (int i = 0; i < 33; i++) {
        assert(mks_fgt_ticket_open(&o, 51.0 + i, 1, 1, 1, MKS_FGT_ROUTE_FUSED));
        mks_fgt_render_begin(&o, 1);
        mks_fgt_suspend(&o, MKS_FGT_SUSP_ACQ);
        for (int q = 0; q < FAKE_Q; q++)
            if (q != t0_query) fg.available[q] = true;
        if (!mks_fgt_copy_begin(&o, NULL)) {
            fprintf(stderr, "HOL iter=%d invariant=%s enabled=%d active_seg=%d "
                    "susp=%d render_entry=%d halted=%d refused_co=%"PRIu64
                    " refused_ring=%"PRIu64"\n", i, o.invariant,
                    o.enabled, o.active_seg, o.susp, o.render_entry, o.halted,
                    o.refused_copy_outside, o.refused_ring_full);
            for (int k = 0; k < emitted_n; k++)
                fprintf(stderr, "CAP[%d]=%s\n", k, emitted_at(k));
            assert(0);
        }
        mks_fgt_copy_end(&o);
        mks_fgt_copy_record(&o, 51.0 + i, 3840, 1920, 2672, 1336, true, "seg", 1, true);
        mks_fgt_resume(&o, MKS_FGT_SUSP_ACQ);
        mks_fgt_render_end(&o, true);
        mks_fgt_draw_seal(&o, true);
        mks_fgt_swap_issue(&o);
        mks_fgt_submit_result(&o, true);
        mks_fgt_swap_result(&o, true, 0, false);
        mks_fgt_flip_close(&o, true, false, false);
        mks_fgt_poll(&o);
    }
    // T0 went HOL: logical terminal hol_drop on the in-flight copy segment.
    assert(t0->reclaim == MKS_FGT_RC_HOL);
    assert(t0->num_segs >= 2);
    assert(t0->segs[1].kind == MKS_FGT_K_COPY);
    assert(t0->segs[1].tstate == MKS_FGT_TS_HOL_DROP);
    fprintf(stderr, "DBG HOL: hol_tickets=%"PRIu64" t0.reclaim=%d t0s1=%s t_next=%d\n",
            o.hol_tickets, t0->reclaim, mks_fgt_tstate_name(t0->segs[1].tstate),
            o.t_next);
    assert(o.hol_tickets == 1);
    // T0 was emitted despite blocking the head (hol path), order preserved.
    int found = 0;
    for (int i = 0; i < emitted_n; i++) {
        int t; if (sscanf(emitted_at(i), "MKS-FGPU-T session=%*s t=%d", &t) == 1 && t == 1)
            found = 1;
    }
    assert(found); // T0 (t_seq=1) emitted via the hol path despite blocking the head
}

static void test_ctx_lost_main_sequence(void) {
    hook_init("frame");
    open_ticket(60.0);
    assert(mks_fgt_copy_begin(&o, NULL));
    // switch context and attempt an End path: suspend triggers close_active → halt
    cur_ctx = (void *)0x9999;
    mks_fgt_copy_end(&o); // close_active → can_end false → halt
    assert(o.halted);
    struct mks_fgt_ticket *tk = &o.tickets[tk_idx()];
    assert(tk->segs[1].tstate == MKS_FGT_TS_CTX_LOST);
    // halted: Begin refused, no GL query calls
    int calls_before = fg.ncalls;
    assert(!mks_fgt_copy_begin(&o, NULL));
    assert(o.refused_ctx_lost >= 1);
    mks_fgt_render_begin(&o, 2);
    mks_fgt_final_begin(&o);
    mks_fgt_poll(&o);
    assert(fg.ncalls == calls_before); // zero GL calls while halted
    // context restored: still halted
    cur_ctx = (void *)0x1234;
    mks_fgt_poll(&o);
    assert(!mks_fgt_copy_begin(&o, NULL));
    // uninit in matching context: unique cleanup End + delete all
    fprintf(stderr, "DBG ctxlost: rel_uc=%"PRIu64" leak_c=%"PRIu64" busy_c=%d "
            "halted=%d t0s0=%s t0s1=%s\n", o.rel_uninit_ctxlost,
            o.leak_ctxlost, o.busy_ctxlost, o.halted,
            mks_fgt_tstate_name(tk->segs[0].tstate),
            mks_fgt_tstate_name(tk->segs[1].tstate));
    mks_fgt_uninit(&o);
    fprintf(stderr, "DBG after: rel_uc=%"PRIu64" gl_del=%"PRIu64"\n",
            o.rel_uninit_ctxlost, o.gl_deleted);
    // pre and copy both halted: two ctx_lost segments, two ctxlost slots.
    assert(o.rel_uninit_ctxlost == 2);
    assert(o.leak_ctxlost == 0 && o.leak_quarantine == 0);
    assert(o.gl_deleted == MKS_FGT_SLOTS && o.gl_leaked == 0);
    assert(o.uninit_end_count == 1);
}

static void test_ctx_mismatch_uninit_leak(void) {
    hook_init("frame");
    open_ticket(70.0);
    assert(mks_fgt_copy_begin(&o, NULL));
    mks_fgt_copy_end(&o);
    cur_ctx = (void *)0x8888; // mismatched at uninit
    mks_fgt_uninit(&o);
    assert(o.gl_leaked == MKS_FGT_SLOTS && o.gl_deleted == 0);
    assert(o.halted);
}

static void test_seg_ref_encodings(void) {
    hook_init("frame");
    open_ticket(80.0);
    int seg = -1;
    assert(mks_fgt_copy_begin(&o, &seg));
    assert(seg >= 0);
    // draw error case: record still references the issued segment
    make_all_available();
    mks_fgt_copy_end(&o);
    mks_fgt_copy_record(&o, 80.0, 3840, 1920, 3840, 1920, false, "seg", seg, false);
    mks_fgt_resume(&o, MKS_FGT_SUSP_ACQ);
    mks_fgt_render_end(&o, true);
    mks_fgt_draw_seal(&o, true);
    mks_fgt_swap_issue(&o);
    mks_fgt_swap_result(&o, true, 0, false);
    mks_fgt_flip_close(&o, true, false, false);
    mks_fgt_poll(&o);
    struct mks_fgt_ticket *tk = &o.tickets[tk_idx()];
    assert(tk->copies_ok == 0); // publish not reported as ok
    assert(tk->segs[seg].tstate == MKS_FGT_TS_RESOLVED);
    // pre_draw_fail encoding: no Begin request, none:pre_draw, no ticket impact
    o.pre_draw_fail++;
    mks_fgt_copy_record(&o, 80.5, 3840, 1920, 3840, 1920, false, "none:pre_draw", -1, false);
    mks_fgt_uninit(&o);
}

static void test_foreign_query_refused(void) {
    hook_init("frame");
    open_ticket(90.0);
    // simulate a foreign active query
    fg.current = 55;
    mks_fgt_suspend(&o, MKS_FGT_SUSP_ACQ);
    assert(!mks_fgt_copy_begin(&o, NULL));
    assert(o.refused_foreign_query == 1);
    struct mks_fgt_ticket *tk = &o.tickets[tk_idx()];
    assert(tk->foreign & MKS_FGT_F_FOREIGN_Q);
    fg.current = 0;
    mks_fgt_resume(&o, MKS_FGT_SUSP_ACQ);
    mks_fgt_uninit(&o);
}

static void test_off_mode_silent(void) {
    hook_init("off");
    assert(!o.enabled && !o.armed);
    assert(!mks_fgt_ticket_open(&o, 1.0, 1, 1, 1, MKS_FGT_ROUTE_FUSED));
    assert(emitted_count() == 0);
}

static void test_equations_final(void) {
    hook_init("frame");
    for (int i = 0; i < 3; i++) {
        open_ticket(100.0 + i);
        make_all_available();
        assert(mks_fgt_copy_begin(&o, NULL));
        mks_fgt_copy_end(&o);
        mks_fgt_copy_record(&o, 100.0 + i, 3840, 1920, 2672, 1336, true, "seg", 1, true);
        close_fresh_flow();
        mks_fgt_poll(&o);
    }
    mks_fgt_uninit(&o);
    // ⑷a/⑷b for kind=copy in a clean flow: every copy attempt issued and
    // resolved. Count issued copy-kind segments from the emitted tickets.
    uint64_t attempt = o.copy_calls;
    // After B3, emitted tickets are recycled (t_seq=-1). Count copy segments
    // from the emitted log lines instead.
    int issued_copy = 0, resolved_copy = 0;
    for (int i = 0; i < emitted_n; i++) {
        const char *l = emitted_at(i);
        if (strncmp(l, "MKS-FGPU-G ", 11) == 0 &&
            strstr(l, "kind=copy") && strstr(l, "issued=1")) {
            issued_copy++;
            if (strstr(l, "tstate=resolved")) resolved_copy++;
        }
    }
    assert(attempt == (uint64_t)issued_copy);
    assert(resolved_copy == issued_copy);
    // resource closure
    assert(o.bind == o.rel_result + o.rel_disjoint_normal + o.rel_late +
        o.rel_disjoint_quarantine + o.rel_uninit_normal + o.rel_uninit_quarantine +
        o.rel_uninit_ctxlost + o.leak_ctxlost + o.leak_quarantine +
        o.busy_normal + o.busy_quarantine + o.busy_ctxlost);
    assert(o.busy_normal == 0 && o.busy_quarantine == 0 && o.busy_ctxlost == 0);
    assert(o.gl_deleted + o.gl_leaked == MKS_FGT_SLOTS);
    // X2/X4
    assert(o.rel_uninit_normal == 0);
    // emission order: strict t_seq for T lines
    int last_t = 0;
    for (int i = 0; i < emitted_n; i++) {
        const char *l = emitted_at(i);
        if (!strncmp(l, "MKS-FGPU-T session=", 19)) {
            int t = 0;
            const char *p = strstr(l, " t=");
            if (p) sscanf(p, " t=%d", &t);
            if (t != last_t + 1)
                fprintf(stderr, "ORDER: i=%d got t=%d expected %d line=%.60s\n",
                        i, t, last_t + 1, l);
            assert(t == last_t + 1); last_t = t;
        }
    }
}

static void test_inflight_pending_drop(void) {
    hook_init("frame");
    open_ticket(110.0);
    assert(mks_fgt_copy_begin(&o, NULL)); // in flight, never available
    mks_fgt_copy_end(&o);
    mks_fgt_copy_record(&o, 110.0, 3840, 1920, 3840, 1920, false, "seg", 1, true);
    close_fresh_flow();
    // copy query never becomes available
    mks_fgt_uninit(&o);
    struct mks_fgt_ticket *tk = &o.tickets[tk_idx()];
    fprintf(stderr, "DBG pending: rel_un=%"PRIu64" s0=%s s1=%s num=%d busy_n=%d\n",
            o.rel_uninit_normal, mks_fgt_tstate_name(tk->segs[0].tstate),
            mks_fgt_tstate_name(tk->segs[1].tstate), tk->num_segs, o.busy_normal);
    // render.pre, copy and render.post are all still in flight at uninit.
    assert(tk->segs[0].tstate == MKS_FGT_TS_PENDING_DROP);
    assert(tk->segs[1].tstate == MKS_FGT_TS_PENDING_DROP);
    assert(tk->segs[2].tstate == MKS_FGT_TS_PENDING_DROP);
    assert(o.rel_uninit_normal == 3);
    assert(o.gl_deleted == MKS_FGT_SLOTS);
}

static void test_ring_full_accounting(void) {
    hook_init("frame");
    make_all_available();
    const int N = MKS_FGT_MAX_COPIES + 4;
    for (int i = 0; i < N; i++) {
        open_ticket(200.0 + i);
        assert(mks_fgt_copy_begin(&o, NULL));
        mks_fgt_copy_end(&o);
        mks_fgt_copy_record(&o, 200.0 + i, 3840, 1920, 2672, 1336, true, "seg", 1, true);
        close_fresh_flow();
        mks_fgt_poll(&o);
    }
    mks_fgt_uninit(&o);
    // Ring filled and stopped storing, but C lines, c_seq and accounting
    // continue unconditionally past capacity.
    assert(o.copy_next == MKS_FGT_MAX_COPIES);      // ring bounded
    assert(o.copy_count == N);                       // total counter monotonic
    assert(o.copy_emitted == (uint64_t)N);           // one C line per copy
    int c_lines = 0, max_c = 0;
    for (int i = 0; i < emitted_n; i++) {
        const char *l = emitted_at(i);
        if (strncmp(l, "MKS-FGPU-C ", 11) == 0) {
            int c = 0;
            sscanf(l, "MKS-FGPU-C session=%*s c=%d", &c);
            if (c > max_c) max_c = c;
            c_lines++;
        }
    }
    assert(c_lines == N);
    assert(max_c == N);
    // The last emitted T line (ticket beyond ring capacity) still has copies_ok=1.
    int last_t = -1;
    for (int i = emitted_n - 1; i >= 0; i--) {
        if (strncmp(emitted_at(i), "MKS-FGPU-T ", 11) == 0) { last_t = i; break; }
    }
    assert(last_t >= 0);
    assert(strstr(emitted_at(last_t), "copies_ok=1") != NULL);
}

static void test_suspend_counting(void) {
    hook_init("frame");
    open_ticket(300.0); // open_ticket suspends ACQ once
    struct mks_fgt_ticket *tk = &o.tickets[tk_idx()];
    assert(tk->acquires == 1);
    assert(tk->releases == 0);
    assert(mks_fgt_copy_begin(&o, NULL));
    mks_fgt_copy_end(&o);
    mks_fgt_copy_record(&o, 300.0, 3840, 1920, 2672, 1336, true, "seg", 1, true);
    mks_fgt_resume(&o, MKS_FGT_SUSP_ACQ);
    mks_fgt_suspend(&o, MKS_FGT_SUSP_REL);
    assert(tk->acquires == 1);
    assert(tk->releases == 1);
    // Nested suspend while already suspended: flagged, NOT double counted.
    mks_fgt_suspend(&o, MKS_FGT_SUSP_REL);
    assert(tk->releases == 1);
    assert(tk->foreign & MKS_FGT_F_NESTED);
    mks_fgt_resume(&o, MKS_FGT_SUSP_REL);
    mks_fgt_render_end(&o, true);
    mks_fgt_draw_seal(&o, true);
    mks_fgt_swap_issue(&o);
    mks_fgt_submit_result(&o, true);
    mks_fgt_swap_result(&o, true, 0, false);
    mks_fgt_flip_close(&o, true, false, false);
    mks_fgt_poll(&o);
    mks_fgt_uninit(&o);
    assert(tk->acquires == 1 && tk->releases == 1);
}

int main(void) {
    test_normal_r1_flow();
    test_r2_carried_span();
    test_frame_count_zero_gl();
    test_sealed_semantics();
    test_hol_scenario_A();
    test_ctx_lost_main_sequence();
    test_ctx_mismatch_uninit_leak();
    test_seg_ref_encodings();
    test_foreign_query_refused();
    test_off_mode_silent();
    test_equations_final();
    test_inflight_pending_drop();
    test_ring_full_accounting();
    test_suspend_counting();
    printf("E1 owner tests: all passed\n");
    return 0;
}
'''

FULL = STUBS + HEADER.read_text() + '\n' + TEST


class FrameGpuOwnerTests(unittest.TestCase):
    def test_owner_core_e1(self):
        with tempfile.TemporaryDirectory() as tmp:
            path, exe = Path(tmp) / 'owner.c', Path(tmp) / 'owner'
            path.write_text(FULL)
            subprocess.run(['clang', '-std=c11', '-Wall', '-Werror', '-Wno-unused-function',
                            str(path), '-o', str(exe)], check=True)
            subprocess.run([str(exe)], check=True)


if __name__ == '__main__':
    unittest.main()
