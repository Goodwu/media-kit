"""Run the real SurfaceTexture mapper and map wrappers against host doubles.

This exercises lease control flow, not FFmpeg, SurfaceTexture, GL, or a device.
"""
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).parent))
from test_lg_p84_mapper_contract import function


ROOT = Path(__file__).resolve().parents[2] / 'mpv'
SURFACE = ROOT / 'video/out/hwdec/hwdec_surfacetexture.c'
HWDEC = ROOT / 'video/out/gpu/hwdec.c'


STUBS = r'''
#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <inttypes.h>
#include <math.h>
#include <stddef.h>
#include <string.h>

#define MKSURF_POOL_SIZE 4
#define MKSURF_KEEP_RETIRED 2
#define MKSURF_NO_SLOT (-1)
#define MKSURF_CONSUMED_SIZE 64
#define MKSURF_EVICTED_SIZE 16
#define MKSURF_LATCH_TIMEOUT_MS 50
#define MKSURF_LATCH_GRACE_COUNT 2
#define MKSURF_LATCH_GRACE_TIMEOUT_MS 250
#define MKSURF_STALE_FPS_FALLBACK_S 0.5
#define MKSURF_STALE_FLOOR_S 0.1
#define MKS_ST_DIAG_READBACK 0
#define MP_ST_PUBLISH_DEFER_30FPS 2
#define GL_SYNC_GPU_COMMANDS_COMPLETE 1
#define GL_SYNC_FLUSH_COMMANDS_BIT 2
#define GL_ALREADY_SIGNALED 3
#define GL_CONDITION_SATISFIED 4
#define GL_TIMEOUT_EXPIRED 5
#define MKSURF_REAP_TIMEOUT_MS 50
#define MP_TIME_MS_TO_NS(ms) ((uint64_t)(ms) * UINT64_C(1000000))
#define RA_HWDEC_CAP_MAP_GEOMETRY 1
#define IMGFMT_MEDIACODEC 3
#define MP_ARRAY_SIZE(a) (sizeof(a) / sizeof((a)[0]))
#define MP_ERR(...) ((void)0)
#define MP_WARN(...) ((void)0)
#define MP_INFO(...) ((void)0)
#define MP_DBG(...) ((void)0)
#define mp_assert assert

typedef unsigned GLuint;
typedef unsigned GLenum;
typedef void *GLsync;
typedef void AVMediaCodecBuffer;
struct mp_rect { int x0, y0, x1, y1; };
struct mp_image_params { int w,h,rotate,vflip,p_w,p_h; struct mp_rect crop; };
struct mp_image { int imgfmt; void *planes[4]; double pts,nominal_fps; };
struct ra_hwdec_map_geometry {
    bool valid; int logical_w,logical_h; struct mp_rect logical_rect,mapped_rect;
};
struct ra_hwdec_map_request { bool allow_full_frame_scale; int target_w,target_h; };
struct ra_tex { int w,h; };
struct ra_tex_params {
    int dimensions,w,h,d; void *format; bool render_src,render_dst,src_linear;
};
struct mkst_slot { struct ra_tex *tex; GLuint name; int w,h; };
struct mkst_lease {
    struct mp_image *source; double src_pts; uint64_t latch_ts; GLsync fence;
    int slot; struct ra_hwdec_map_geometry geometry;
};
struct mkst_consumed { void *buffer; double pts; bool used; };
struct thermal {
    bool enabled; uint64_t lease_reuse,lease_copy,latch,publish_flush,retire_flush;
    uint64_t fps_fallback,publish_deferred; double pts,nominal_fps;
    int flush_policy,flush_override; bool defer_publish_flush;
};
struct options { int publish_flush; };
typedef struct GL {
    GLsync (*FenceSync)(GLenum, unsigned);
    void (*DeleteSync)(GLsync);
    void (*Flush)(void);
    GLenum (*ClientWaitSync)(GLsync, unsigned, uint64_t);
    void (*DeleteFramebuffers)(int, const GLuint *);
    void (*DeleteProgram)(GLuint);
} GL;
struct priv {
    GL *gl; struct thermal thermal; struct options *flush_opts; void *flush_opts_cache;
    void *fmt; struct { int unused; } gpu_copy_timer;
    GLuint fbo,program,program_target,oes_tex_name; struct ra_tex *oes_tex;
    int flush_override; bool logged_flush_decision,defer_publish_flush;
    bool slot_fbo_reuse; uint64_t slot_fbo_fallbacks;
    bool opt_lease_target,have_fence;
    int logged_lease_w,logged_lease_h;
    struct mkst_slot slots[MKSURF_POOL_SIZE]; struct mkst_lease cur;
    struct mkst_lease retired[MKSURF_POOL_SIZE-1]; int retired_count;
    struct mkst_consumed consumed[MKSURF_CONSUMED_SIZE]; int consumed_next;
    struct mkst_consumed evicted[MKSURF_EVICTED_SIZE]; int evicted_next;
    uint64_t release_count,release_failed_count,consumed_overflow_count;
    uint64_t horizon_overflow_count,idempotent_reacquire_count,nonfinite_pts_count;
    uint64_t latch_count,latch_timeout_count,stale_drop_count;
    uint64_t fence_created_count,fence_deleted_count,fence_create_failed_count;
    uint64_t publish_deferred_count,publish_flush_count,retire_flush_count,reap_stuck_count;
    uint64_t retire_count,reap_count,pool_peak; int latch_attempts; bool logged_fps_fallback;
};
struct owner { void *priv; };
struct priv_owner { int (*latch)(int, uint64_t *); };
struct ra_hwdec_mapper;
struct driver { int (*map)(struct ra_hwdec_mapper *); void (*unmap)(struct ra_hwdec_mapper *); };
struct ra_hwdec_mapper {
    struct driver *driver; struct priv *priv; struct owner *owner; void *ra;
    struct mp_image_params src_params,dst_params; unsigned caps;
    struct ra_hwdec_map_request map_request; struct ra_hwdec_map_geometry map_geometry;
    struct mp_image *src; struct ra_tex *tex[4];
};

static int releases,latches,draws,refs,unrefs,fences_deleted,fence_flushes,fence_waits;
static int textures_created,textures_freed;
static bool fail_slot,fail_draw,fail_ref,fail_setref,fail_fence,stuck_fence;
static uint64_t next_timestamp,latched_timestamp;
static int64_t latch_offset_ns;
static int latch_result;
static void *expected_release_buffer,*released_buffer,*latched_buffer;
static struct ra_tex textures[32];
static bool texture_live[32];
static void *texture_content_buffer[32];
static uint64_t texture_content_timestamp[32];
struct fake_fence { bool live; };
struct fake_wait { GLsync fence; uint64_t timeout; };
static struct fake_fence fence_objects[64];
static struct fake_wait wait_events[128];
static int fence_objects_created;
static struct fake_fence *checked_fence(GLsync fence) {
    for (int i=0;i<fence_objects_created;i++) {
        if (fence==&fence_objects[i]) { assert(fence_objects[i].live); return &fence_objects[i]; }
    }
    assert(false); return NULL;
}
static GLsync gl_fence(GLenum condition, unsigned flags) {
    assert(condition==GL_SYNC_GPU_COMMANDS_COMPLETE && flags==0);
    if (fail_fence) return NULL;
    assert(fence_objects_created<(int)MP_ARRAY_SIZE(fence_objects));
    struct fake_fence *fence=&fence_objects[fence_objects_created++];
    fence->live=true; return fence;
}
static void gl_delete(GLsync fence) { checked_fence(fence)->live=false; fences_deleted++; }
static void gl_flush(void) { fence_flushes++; }
static GLenum gl_wait(GLsync fence, unsigned flags, uint64_t timeout) {
    checked_fence(fence); assert(flags==GL_SYNC_FLUSH_COMMANDS_BIT);
    assert(fence_waits<(int)MP_ARRAY_SIZE(wait_events));
    wait_events[fence_waits++]=(struct fake_wait){fence,timeout};
    return stuck_fence ? GL_TIMEOUT_EXPIRED : GL_ALREADY_SIGNALED;
}
static void gl_delete_framebuffers(int count, const GLuint *names) { (void)count;(void)names; }
static void gl_delete_program(GLuint name) { (void)name; }
static GL gl={gl_fence,gl_delete,gl_flush,gl_wait,gl_delete_framebuffers,gl_delete_program};
static void m_config_cache_update(void *p) { (void)p; }
static void mks_thermal_report(struct thermal *p, bool end) { (void)p;(void)end; }
static void mks_gpu_timer_uninit(void *timer) { (void)timer; }
static void slot_fbo_report(struct ra_hwdec_mapper *mapper, bool final) { (void)mapper;(void)final; }
static void thermal_report_errors(struct priv *p) { (void)p; }
static bool mp_image_crop_valid(const struct mp_image_params *p) {
    return p->crop.x1 > p->crop.x0 && p->crop.y1 > p->crop.y0 &&
           p->crop.x0 >= 0 && p->crop.y0 >= 0 &&
           p->crop.x1 <= p->w && p->crop.y1 <= p->h;
}
struct fake_image { struct mp_image image; bool live; };
static struct fake_image image_refs[128];
static int image_refs_created;
static void mp_image_unrefp(struct mp_image **p) {
    if (!*p) return;
    for (int i=0;i<image_refs_created;i++) {
        if (*p==&image_refs[i].image) {
            assert(image_refs[i].live); image_refs[i].live=false; unrefs++; *p=NULL; return;
        }
    }
    assert(false);
}
static struct mp_image *new_ref(struct mp_image *img) {
    assert(img && image_refs_created<(int)MP_ARRAY_SIZE(image_refs));
    struct fake_image *ref=&image_refs[image_refs_created++];
    ref->image=*img; ref->live=true; refs++; return &ref->image;
}
static void mp_image_setrefp(struct mp_image **p, struct mp_image *img) {
    if (*p!=img) { mp_image_unrefp(p); *p=img && !fail_setref ? new_ref(img) : NULL; }
}
static struct mp_image *mp_image_new_ref(struct mp_image *img) {
    return fail_ref ? NULL : new_ref(img);
}
static int av_mediacodec_release_buffer(AVMediaCodecBuffer *buf, int render) {
    assert(buf && buf==expected_release_buffer && render==1);
    released_buffer=buf; releases++; return 0;
}
static int latch(int timeout, uint64_t *timestamp) {
    assert(timeout > 0 && released_buffer); latches++;
    if (latch_result) return latch_result;
    assert(latch_offset_ns >= 0 || next_timestamp >= (uint64_t)(-latch_offset_ns));
    *timestamp=latch_offset_ns >= 0 ? next_timestamp+(uint64_t)latch_offset_ns
                                    : next_timestamp-(uint64_t)(-latch_offset_ns);
    latched_timestamp=*timestamp; latched_buffer=released_buffer;
    return 0;
}
static void ra_tex_free(void *ra, struct ra_tex **tex) {
    (void)ra; assert(tex);
    if (!*tex) return;
    for (int i=0;i<textures_created;i++) {
        if (*tex==&textures[i]) {
            assert(texture_live[i]); texture_live[i]=false; textures_freed++; *tex=NULL; return;
        }
    }
    assert(false);
}
static struct ra_tex *ra_tex_create(void *ra, const struct ra_tex_params *params) {
    (void)ra;
    if (fail_slot) return NULL;
    assert(params->dimensions==2 && params->d==1 && params->w>0 && params->h>0);
    assert(params->render_src && params->render_dst && params->src_linear);
    assert(textures_created<(int)MP_ARRAY_SIZE(textures));
    texture_live[textures_created]=true;
    struct ra_tex *tex=&textures[textures_created++];
    *tex=(struct ra_tex){params->w,params->h}; return tex;
}
static void ra_gl_get_raw_tex(void *ra, struct ra_tex *tex, GLuint *name, GLenum *target) {
    (void)ra; assert(tex); *name=(GLuint)(tex-textures+1); *target=7;
}
static bool ra_gl_get_owned_fbo(void *ra, struct ra_tex *tex, GLuint *fbo) {
    (void)ra;(void)tex;*fbo=0;return false;
}
static bool draw_copy(struct ra_hwdec_mapper *mapper, GLuint name, GLuint fbo,
                      int w, int h, bool target, bool measure, double pts) {
    (void)fbo;(void)pts; assert(name && name<=(GLuint)textures_created && w>0 && h>0 && measure);
    assert(texture_live[name-1]);
    assert(target == (w != 3840 || h != 1920)); draws++;
    if (fail_draw) return false;
    assert(mapper->src && latched_buffer==mapper->src->planes[3]);
    texture_content_buffer[name-1]=latched_buffer;
    texture_content_timestamp[name-1]=latched_timestamp;
    return true;
}
static bool mp_st_defer_publish(int policy, double fps, int override) {
    (void)policy;(void)fps;(void)override;return false;
}
static bool mp_st_publish_fps_allowed(double fps) { (void)fps;return true; }
'''


TEST = r'''
static struct priv p;
static struct options opts;
static struct priv_owner owner_priv={.latch=latch};
static struct owner owner={.priv=&owner_priv};
static struct driver driver={.map=mapper_map,.unmap=mapper_unmap};
static struct ra_hwdec_mapper mapper;
static struct mp_image frames[8];
static struct ra_hwdec_map_request target={true,2672,1336};

static void reset(bool caps) {
    memset(&p,0,sizeof(p)); memset(&mapper,0,sizeof(mapper)); memset(frames,0,sizeof(frames));
    memset(textures,0,sizeof(textures)); memset(texture_live,0,sizeof(texture_live));
    memset(texture_content_buffer,0,sizeof(texture_content_buffer));
    memset(texture_content_timestamp,0,sizeof(texture_content_timestamp));
    memset(fence_objects,0,sizeof(fence_objects)); memset(wait_events,0,sizeof(wait_events));
    memset(image_refs,0,sizeof(image_refs)); fence_objects_created=image_refs_created=0;
    expected_release_buffer=released_buffer=latched_buffer=NULL;
    next_timestamp=latched_timestamp=0; latch_offset_ns=0; latch_result=0;
    p.cur.slot=MKSURF_NO_SLOT;
    for (int i=0;i<MKSURF_POOL_SIZE-1;i++) p.retired[i].slot=MKSURF_NO_SLOT;
    p.gl=&gl; p.opt_lease_target=true; p.flush_opts=&opts; p.flush_override=-1;
    mapper=(struct ra_hwdec_mapper){.driver=&driver,.priv=&p,.owner=&owner,
        .src_params={.w=3840,.h=1920,.p_w=1,.p_h=1},
        .dst_params={.w=3840,.h=1920},.caps=caps ? RA_HWDEC_CAP_MAP_GEOMETRY : 0};
    for (int i=0;i<8;i++) frames[i]=(struct mp_image){.imgfmt=IMGFMT_MEDIACODEC,
        .planes={[3]=(void *)(uintptr_t)(i+1)},.pts=(double)(i+1),.nominal_fps=30};
    releases=latches=draws=refs=unrefs=fences_deleted=fence_flushes=fence_waits=0;
    textures_created=textures_freed=0;
    fail_slot=fail_draw=fail_ref=fail_setref=fail_fence=stuck_fence=false;
}
static int map_frame(int n, const struct ra_hwdec_map_request *req) {
    next_timestamp=(uint64_t)(frames[n].pts * 1000000000.0);
    expected_release_buffer=frames[n].planes[3];
    return ra_hwdec_mapper_map_with_request(&mapper,&frames[n],req);
}
static void assert_texture_content(struct ra_tex *tex, void *buffer, uint64_t timestamp) {
    for (int i=0;i<textures_created;i++) {
        if (tex==&textures[i]) {
            assert(texture_live[i] && texture_content_buffer[i]==buffer);
            assert(texture_content_timestamp[i]==timestamp);
            return;
        }
    }
    assert(false);
}
static void geometry(int w,int h) {
    assert(mapper.map_geometry.valid && mapper.tex[0]);
    assert(p.cur.source && p.cur.slot>=0 && p.cur.slot<MKSURF_POOL_SIZE);
    assert_texture_content(mapper.tex[0],p.cur.source->planes[3],p.cur.latch_ts);
    assert(mapper.map_geometry.logical_w==3840 && mapper.map_geometry.logical_h==1920);
    assert(mapper.map_geometry.logical_rect.x0==0 && mapper.map_geometry.logical_rect.y0==0);
    assert(mapper.map_geometry.logical_rect.x1==3840 && mapper.map_geometry.logical_rect.y1==1920);
    assert(mapper.map_geometry.mapped_rect.x0==0 && mapper.map_geometry.mapped_rect.y0==0);
    assert(mapper.map_geometry.mapped_rect.x1==w && mapper.map_geometry.mapped_rect.y1==h);
    assert(mapper.tex[0]->w==w && mapper.tex[0]->h==h);
    assert(mapper.dst_params.w==3840 && mapper.dst_params.h==1920);
    assert(!mapper.map_request.allow_full_frame_scale);
}
static void absent(void) {
    assert(!mapper.map_geometry.valid && !mapper.tex[0] && !mapper.src);
    assert(!mapper.map_request.allow_full_frame_scale);
}
static void cleanup(void) {
    ra_hwdec_mapper_unmap(&mapper);
    mapper_uninit(&mapper);
    absent();
    assert(p.retired_count==0 && p.cur.slot==MKSURF_NO_SLOT);
    assert(p.fence_created_count==p.fence_deleted_count);
    assert(fence_objects_created==fences_deleted && textures_created==textures_freed);
    assert(refs==unrefs && refs==image_refs_created);
    for (int i=0;i<fence_objects_created;i++) assert(!fence_objects[i].live);
    for (int i=0;i<image_refs_created;i++) assert(!image_refs[i].live);
    for (int i=0;i<textures_created;i++) assert(!texture_live[i]);
}
static void test_retired_redraw_preserves_actual_geometry(void) {
    reset(true); p.have_fence=true;
    assert(map_frame(0,&target)==0); geometry(2672,1336);
    struct ra_tex *small=mapper.tex[0];
    assert(releases==1 && latches==1 && draws==1);
    assert(map_frame(1,NULL)==0); geometry(3840,1920);
    assert(mapper.tex[0]!=small && p.retired_count==1);
    assert(releases==2 && latches==2 && draws==2);
    assert(map_frame(0,NULL)==0); geometry(2672,1336);
    assert(mapper.tex[0]==small && p.retired_count==1);
    assert(releases==2 && latches==2 && draws==2);
    assert(map_frame(1,&target)==0); geometry(3840,1920);
    assert(releases==2 && latches==2 && draws==2);
    assert(fences_deleted==4);
    cleanup();
}
static void test_old_consumer_cannot_request_scaling(void) {
    reset(false);
    assert(map_frame(0,&target)==0);
    assert(mapper.tex[0] && mapper.tex[0]->w==3840 && mapper.tex[0]->h==1920);
    assert(!mapper.map_geometry.valid && !mapper.map_request.allow_full_frame_scale);
    assert(releases==1 && latches==1 && draws==1);
    cleanup();
}
static void test_resize_recreates_only_a_free_slot(void) {
    reset(true); p.have_fence=true;
    assert(map_frame(0,&target)==0); geometry(2672,1336);
    struct ra_tex *small=mapper.tex[0];
    assert(map_frame(1,NULL)==0); geometry(3840,1920);
    assert(textures_created==2 && textures_freed==0);
    struct ra_tex *full=mapper.tex[0];
    struct ra_hwdec_map_request smaller={true,1920,960};
    assert(map_frame(2,&smaller)==0); geometry(1920,960);
    assert(p.retired_count==2 && textures_created==3 && textures_freed==0);
    assert(p.retired[0].slot==0 && p.retired[1].slot==1);
    assert(p.slots[0].tex==small && p.slots[1].tex==full);
    assert(map_frame(3,&target)==0); geometry(2672,1336);
    assert(textures_created==3 && textures_freed==0);
    assert(p.slots[0].tex==small);
    assert(releases==4 && latches==4 && draws==4);
    assert(map_frame(4,&smaller)==0); geometry(1920,960);
    assert(textures_created==4 && textures_freed==1);
    assert(p.slots[1].tex!=full && releases==5 && latches==5 && draws==5);
    cleanup();
}
/* Renderer cache hits skip these mapper calls. This models their effect on
 * mapper lifetime only; it does not implement a renderer or queue. */
static void test_retired_horizon_with_cache_hits(bool use_target) {
    reset(use_target); p.have_fence=true;
    const struct ra_hwdec_map_request *req=use_target ? &target : NULL;
    struct ra_tex *b_tex=NULL;
    struct mp_image *b_source=NULL;
    int b_slot=MKSURF_NO_SLOT;
    uint64_t b_latch_ts=0;
    for (int n=0;n<3;n++) {
        assert(map_frame(n,req)==0);
        assert(p.cur.source && p.cur.source->planes[3]==frames[n].planes[3]);
        assert(p.cur.src_pts==frames[n].pts && p.cur.slot>=0);
        assert(mapper.tex[0] && mapper.tex[0]==p.slots[p.cur.slot].tex);
        assert(p.cur.latch_ts==latched_timestamp);
        assert_texture_content(mapper.tex[0],frames[n].planes[3],latched_timestamp);
        assert(mapper.tex[0]->w==(use_target ? 2672 : 3840));
        assert(mapper.tex[0]->h==(use_target ? 1336 : 1920));
        if (n==1) {
            b_tex=mapper.tex[0]; b_source=p.cur.source;
            b_slot=p.cur.slot; b_latch_ts=p.cur.latch_ts;
        }
        GLsync publish_fence=p.cur.fence;
        struct fake_fence *publish_object=checked_fence(publish_fence);
        int fence_count_before=fence_objects_created;
        int delete_count_before=fences_deleted;
        ra_hwdec_mapper_unmap(&mapper); absent();
        assert(!publish_object->live && fences_deleted==delete_count_before+1);
        assert(fence_objects_created==fence_count_before+1);
        assert(p.retired[n].fence && p.retired[n].fence!=publish_fence);
        assert(checked_fence(p.retired[n].fence)==&fence_objects[fence_count_before]);
    }
    assert(p.retired_count==3 && releases==3 && latches==3 && draws==3);
    assert(p.retired[0].source->planes[3]==frames[0].planes[3]);
    assert(p.retired[1].source==b_source && p.retired[1].slot==b_slot);
    GLsync a_fence=p.retired[0].fence;
    struct fake_fence *a_fence_object=checked_fence(a_fence);
    int waits_before=fence_waits, deletes_before=fences_deleted;
    assert(map_frame(3,req)==0);
    assert(p.retired_count==2 && p.reap_count==1 && p.reap_stuck_count==0);
    assert(p.retired[0].source==b_source && p.retired[1].source->planes[3]==frames[2].planes[3]);
    assert(fence_waits==waits_before+1 && wait_events[waits_before].fence==a_fence);
    assert(wait_events[waits_before].timeout==0 && !a_fence_object->live);
    assert(fences_deleted==deletes_before+1);
    assert(p.cur.source && p.cur.source->planes[3]==frames[3].planes[3]);
    assert(p.cur.src_pts==frames[3].pts && mapper.tex[0]==p.slots[p.cur.slot].tex);
    assert(p.cur.latch_ts==latched_timestamp);
    assert_texture_content(mapper.tex[0],frames[3].planes[3],latched_timestamp);
    assert(releases==4 && latches==4 && draws==4);
    ra_hwdec_mapper_unmap(&mapper); absent();
    assert(p.retired_count==3 && p.retired[2].source->planes[3]==frames[3].planes[3]);
    assert(map_frame(0,req)<0); absent();
    assert(p.horizon_overflow_count==1 && releases==4 && latches==4 && draws==4);
    assert(map_frame(1,req)==0);
    assert(p.cur.source==b_source && p.cur.source->planes[3]==frames[1].planes[3]);
    assert(p.cur.src_pts==frames[1].pts && p.cur.latch_ts==b_latch_ts && p.cur.slot==b_slot);
    assert(mapper.tex[0]==b_tex && p.slots[b_slot].tex==b_tex && p.retired_count==2);
    assert_texture_content(b_tex,frames[1].planes[3],b_latch_ts);
    assert(p.retired[0].source->planes[3]==frames[2].planes[3]);
    assert(p.retired[1].source->planes[3]==frames[3].planes[3]);
    if (use_target) geometry(2672,1336);
    else assert(!mapper.map_geometry.valid && b_tex->w==3840 && b_tex->h==1920);
    assert(releases==4 && latches==4 && draws==4);
    cleanup();
}
static void test_latch_offsets_and_failures(bool use_target) {
    const struct ra_hwdec_map_request *req=use_target ? &target : NULL;
    const int64_t offsets[]={INT64_C(1000000),-INT64_C(1000000)};
    for (unsigned i=0;i<MP_ARRAY_SIZE(offsets);i++) {
        reset(use_target); p.have_fence=true; latch_offset_ns=offsets[i];
        frames[0].pts=1.234567;
        assert(map_frame(0,req)==0);
        uint64_t actual=(uint64_t)((int64_t)next_timestamp+offsets[i]);
        assert(latched_timestamp==actual && p.cur.latch_ts==actual);
        assert_texture_content(mapper.tex[0],frames[0].planes[3],actual);
        assert(releases==1 && latches==1 && draws==1);
        ra_hwdec_mapper_unmap(&mapper); absent();
        latch_offset_ns=0;
        assert(map_frame(0,req)==0);
        assert(p.cur.latch_ts==actual && latched_timestamp==actual);
        assert_texture_content(mapper.tex[0],frames[0].planes[3],actual);
        assert(releases==1 && latches==1 && draws==1);
        cleanup();
    }
    const int results[]={1,-1};
    for (unsigned i=0;i<MP_ARRAY_SIZE(results);i++) {
        reset(use_target); latch_result=results[i];
        assert(map_frame(0,req)<0); absent();
        assert(releases==1 && latches==1 && draws==0 && !latched_buffer);
        latch_result=0;
        assert(map_frame(0,req)<0); absent();
        assert(releases==1 && latches==1 && draws==0);
        cleanup();
    }
    reset(use_target); latch_offset_ns=INT64_C(101000000);
    assert(map_frame(0,req)<0); absent();
    assert(releases==1 && latches==1 && draws==0 && p.stale_drop_count==1);
    cleanup();
}
static void test_retire_fence_failure_and_stuck_reap(void) {
    reset(true); p.have_fence=true;
    assert(map_frame(0,&target)==0); geometry(2672,1336);
    fail_fence=true;
    ra_hwdec_mapper_unmap(&mapper); absent();
    assert(p.retired_count==1 && !p.retired[0].fence && p.fence_create_failed_count==1);
    fail_fence=false;
    assert(map_frame(0,NULL)==0); geometry(2672,1336);
    assert(releases==1 && latches==1 && draws==1);
    ra_hwdec_mapper_unmap(&mapper); absent();
    assert(p.retired_count==1 && p.retired[0].fence);
    GLsync stuck=p.retired[0].fence;
    stuck_fence=true; retire_reap(&mapper,0);
    assert(p.retired_count==0 && p.reap_stuck_count==1 && fence_waits==2);
    assert(wait_events[0].fence==stuck && wait_events[0].timeout==0);
    assert(wait_events[1].fence==stuck &&
           wait_events[1].timeout==MP_TIME_MS_TO_NS(MKSURF_REAP_TIMEOUT_MS));
    assert(map_frame(0,&target)<0); absent();
    assert(releases==1 && latches==1 && draws==1);
    cleanup();
}
static void test_disabled_target_still_reuses_old_small_lease(void) {
    reset(true); p.have_fence=true;
    assert(map_frame(0,&target)==0); geometry(2672,1336);
    struct ra_tex *small=mapper.tex[0];
    fail_draw=true;
    assert(map_frame(1,&target)<0); absent();
    assert(!p.opt_lease_target && releases==2 && latches==2 && draws==2);
    fail_draw=false;
    assert(map_frame(0,NULL)==0); geometry(2672,1336);
    assert(mapper.tex[0]==small && releases==2 && latches==2 && draws==2);
    assert(map_frame(2,&target)==0); geometry(3840,1920);
    assert(releases==3 && latches==3 && draws==3);
    assert(map_frame(1,&target)<0); absent();
    assert(releases==3 && latches==3 && draws==3);
    cleanup();
}
static void test_ref_failure_preserves_retired_lease(void) {
    reset(true); p.have_fence=true;
    assert(map_frame(0,&target)==0); geometry(2672,1336);
    struct ra_tex *small=mapper.tex[0];
    assert(releases==1 && latches==1 && draws==1);
    fail_setref=true;
    assert(map_frame(1,&target)<0); absent();
    assert(p.retired_count==1 && p.opt_lease_target);
    assert(releases==1 && latches==1 && draws==1);
    fail_setref=false;
    assert(map_frame(0,NULL)==0); geometry(2672,1336);
    assert(mapper.tex[0]==small && releases==1 && latches==1 && draws==1);
    assert(map_frame(1,&target)==0); geometry(2672,1336);
    assert(releases==2 && latches==2 && draws==2);
    cleanup();
}
static void test_fresh_failure_with_retired_lease(int fault) {
    reset(true); p.have_fence=true;
    assert(map_frame(0,&target)==0); geometry(2672,1336);
    struct ra_tex *small=mapper.tex[0];
    ra_hwdec_mapper_unmap(&mapper); absent();
    assert(p.retired_count==1 && p.retired[0].fence);
    fail_slot=fault==0; fail_draw=fault==1; fail_ref=fault==2; fail_fence=fault==3;
    assert(map_frame(1,&target)<0); absent();
    assert(p.retired_count==1 && releases==2 && latches==2);
    assert(draws==(fault==0 ? 1 : 2));
    int failed_draws=draws;
    fail_slot=fail_draw=fail_ref=fail_fence=false;
    assert(map_frame(0,NULL)==0); geometry(2672,1336);
    assert(mapper.tex[0]==small && releases==2 && latches==2 && draws==failed_draws);
    assert(map_frame(2,&target)==0);
    geometry(fault<2 ? 3840 : 2672,fault<2 ? 1920 : 1336);
    assert(releases==3 && latches==3 && draws==failed_draws+1);
    assert(map_frame(1,&target)<0); absent();
    assert(releases==3 && latches==3 && draws==failed_draws+1);
    cleanup();
}
static void test_fresh_failure(int fault) {
    reset(true); p.have_fence=true;
    fail_slot=fault==0; fail_draw=fault==1; fail_ref=fault==2; fail_fence=fault==3;
    assert(map_frame(0,&target)<0); absent();
    assert(releases==1 && latches==1 && draws==(fault==0 ? 0 : 1));
    assert(p.opt_lease_target==(fault>=2));
    fail_slot=fail_draw=fail_ref=fail_fence=false;
    assert(map_frame(0,&target)<0); absent();
    assert(releases==1 && latches==1);
    assert(map_frame(1,&target)==0);
    geometry(fault<2 ? 3840 : 2672,fault<2 ? 1920 : 1336);
    assert(releases==2 && latches==2);
    cleanup();
}
int main(void) {
    test_retired_redraw_preserves_actual_geometry();
    test_old_consumer_cannot_request_scaling();
    struct ra_tex *empty_tex=NULL;
    ra_tex_free(NULL,&empty_tex);
    assert(!empty_tex);
    test_resize_recreates_only_a_free_slot();
    test_retired_horizon_with_cache_hits(false);
    test_retired_horizon_with_cache_hits(true);
    test_latch_offsets_and_failures(false);
    test_latch_offsets_and_failures(true);
    test_retire_fence_failure_and_stuck_reap();
    test_disabled_target_still_reuses_old_small_lease();
    test_ref_failure_preserves_retired_lease();
    for (int i=0;i<4;i++) {
        test_fresh_failure(i);
        test_fresh_failure_with_retired_lease(i);
    }
    return 0;
}
'''


def check_fixture_constants(surface):
    names = ('POOL_SIZE', 'KEEP_RETIRED', 'NO_SLOT', 'CONSUMED_SIZE', 'EVICTED_SIZE',
             'LATCH_TIMEOUT_MS', 'LATCH_GRACE_COUNT', 'LATCH_GRACE_TIMEOUT_MS',
             'STALE_FPS_FALLBACK_S', 'STALE_FLOOR_S', 'REAP_TIMEOUT_MS')
    for suffix in names:
        name = 'MKSURF_' + suffix
        pattern = rf'^#define\s+{name}\s+([^\s/]+)\s*$'
        source_values = re.findall(pattern, surface, re.MULTILINE)
        fixture_values = re.findall(pattern, STUBS, re.MULTILINE)
        if len(source_values) != 1 or source_values != fixture_values:
            raise AssertionError(f'{name}: source={source_values}, fixture={fixture_values}')


class SurfaceLeaseTests(unittest.TestCase):
    def test_actual_mapper_lifecycle_with_host_doubles(self):
        surface = SURFACE.read_text()
        check_fixture_constants(surface)
        common = HWDEC.read_text()
        names = ('lease_dims_for_map', 'lease_matches', 'retired_find', 'fence_delete',
                 'fence_create', 'lease_release', 'consumed_find', 'evicted_find',
                 'consumed_add', 'retired_take', 'retire_reap', 'mapper_publish_lease',
                 'mapper_adopt_retired', 'take_slot', 'mapper_map', 'mapper_unmap', 'mapper_uninit')
        returns = ('void', 'bool', 'int', 'void', 'GLsync', 'void', 'bool', 'bool',
                   'void', 'struct mkst_lease', 'void', 'void', 'void', 'int', 'int', 'void', 'void')
        # The shared extractor normally handles void/int functions; keep the
        # return types here so the compiled code is copied from real bodies.
        def extract(name, result):
            if result in ('void', 'int'):
                return 'static ' + result + ' ' + function(surface, name)
            marker = 'static ' + result + ' ' + name + '('
            start = surface.index(marker)
            opening = surface.index('{', start)
            depth = 0
            for i in range(opening, len(surface)):
                depth += (surface[i] == '{') - (surface[i] == '}')
                if depth == 0:
                    return surface[start:i+1]
            raise ValueError('unclosed function: ' + name)
        selected = '\n'.join(extract(name, result) for name, result in zip(names, returns))
        wrappers = ('void ' + function(common, 'ra_hwdec_mapper_unmap') + '\n' +
                    'int ra_hwdec_mapper_map_with_request(struct ra_hwdec_mapper *, struct mp_image *, '
                    'const struct ra_hwdec_map_request *);\n' +
                    'int ' + function(common, 'ra_hwdec_mapper_map') + '\n' +
                    'int ' + function(common, 'ra_hwdec_mapper_map_with_request'))
        with tempfile.TemporaryDirectory() as tmp:
            path, exe = Path(tmp)/'lease.c', Path(tmp)/'lease'
            path.write_text(STUBS + selected + '\n' + wrappers + '\n' + TEST)
            subprocess.run(['clang', '-std=c11', '-Wall', '-Werror', str(path), '-lm', '-o', str(exe)],
                           check=True, timeout=30)
            subprocess.run([str(exe)], check=True, timeout=5)


if __name__ == '__main__':
    unittest.main()
