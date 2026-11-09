"""Exercise the gpu-next acquire/release callbacks with host doubles.

This does not run libplacebo, a real hwdec mapper, or a GPU.
"""
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).parent))
from test_lg_p84_mapper_contract import function


ROOT = Path(__file__).resolve().parents[2] / 'mpv'
NEXT = ROOT / 'video/out/vo_gpu_next.c'

STUBS = r'''
#include <assert.h>
#include <math.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>

#define MP_ERR(...) ((void)0)
#define MPMIN(a, b) ((a) < (b) ? (a) : (b))
typedef void *pl_gpu;
struct texture { int id; bool live; struct { int w, h; } params; };
typedef struct texture *pl_tex;
struct ra { bool pl; };
struct ra_hwdec { int unused; };
struct rect { int x0, y0, x1, y1; };
struct ra_hwdec_map_geometry { bool valid; int logical_w, logical_h;
    struct rect logical_rect, mapped_rect; };
struct ra_hwdec_map_request { bool allow_full_frame_scale; int target_w, target_h; };
#define RA_HWDEC_CAP_MAP_GEOMETRY 1u
struct ra_hwdec_mapper { struct ra *ra; unsigned caps;
    struct ra_hwdec_map_geometry map_geometry; };
struct params { int w, h, rotate, vflip; };
struct mp_image { void *priv; struct params params; };
struct vo { void *priv; int dwidth, dheight; };
struct frame_priv { struct vo *vo; struct ra_hwdec *hwdec; int lease_w, lease_h;
    void *rescale_ctx; };
struct plane { pl_tex texture; };
struct pl_rect2df { float x0, y0, x1, y1; };
struct pl_overlay_part { struct pl_rect2df src, dst; };
#define PL_OVERLAY_COORDS_SRC_CROP 1
#define PL_OVERLAY_COORDS_DST_CROP 2
struct pl_overlay { const struct pl_overlay_part *parts; int num_parts; int coords; };
struct pl_frame { void *user_data; int num_planes; struct plane planes[4];
    struct pl_rect2df crop; struct pl_overlay *overlays; int num_overlays; };
struct priv { struct ra_hwdec_mapper *hwdec_mapper; pl_gpu gpu; };

// Minimal talloc double tracking children per context for the rescale copies.
// Production talloc wrappers abort on OOM; the doubles never return NULL.
struct ta_node { void *ptr; struct ta_node *next; };
struct ta_ctx { struct ta_node *head; };
static int ta_allocs, ta_frees;
static void *talloc_new(void *parent) {
    (void)parent;
    ta_allocs++;
    return calloc(1, sizeof(struct ta_ctx));
}
static void *talloc_size(void *ctx, size_t size) {
    if (!ctx) return NULL;
    struct ta_ctx *c = ctx;
    struct ta_node *n = malloc(sizeof(*n));
    if (!n) return NULL;
    n->ptr = calloc(1, size);
    if (!n->ptr) { free(n); return NULL; }
    n->next = c->head; c->head = n; ta_allocs++;
    return n->ptr;
}
#define talloc_array(ctx, type, count) ((type *) talloc_size(ctx, sizeof(type) * (size_t)(count)))
static void talloc_free(void *ctx) {
    struct ta_ctx *c = ctx;
    if (!c) return;
    while (c->head) { struct ta_node *n = c->head; c->head = n->next;
                      free(n->ptr); free(n); }
    free(c); ta_frees++;
}


// Frame GPU timing owner: disabled stub for host tests (all no-ops).
struct mks_fgt_owner { bool enabled, armed; };
static struct mks_fgt_owner fgt_stub = { .enabled = false, .armed = false };
static struct mks_fgt_owner *mks_fgt_get_global(void) { return &fgt_stub; }
static void __attribute__((unused)) mks_fgt_suspend(struct mks_fgt_owner *o, int w) { (void)o; (void)w; }
static void __attribute__((unused)) mks_fgt_resume(struct mks_fgt_owner *o, int w) { (void)o; (void)w; }
static bool __attribute__((unused)) mks_fgt_ready(struct mks_fgt_owner *o) { return false; }
static void __attribute__((unused)) mks_fgt_ticket_open(struct mks_fgt_owner *o, double p, int f, int m, int h, int r) { (void)o; }
static void __attribute__((unused)) mks_fgt_render_begin(struct mks_fgt_owner *o, int k) { (void)o; (void)k; }
static void __attribute__((unused)) mks_fgt_render_end(struct mks_fgt_owner *o, bool ok) { (void)o; (void)ok; }
static void __attribute__((unused)) mks_fgt_draw_exit(struct mks_fgt_owner *o, bool p) { (void)o; (void)p; }
static void __attribute__((unused)) mks_fgt_draw_seal(struct mks_fgt_owner *o, bool p) { (void)o; (void)p; }
static void __attribute__((unused)) mks_fgt_flip_close(struct mks_fgt_owner *o, bool ep, bool g, bool sr) { (void)o; }
static void __attribute__((unused)) mks_fgt_submit_result(struct mks_fgt_owner *o, bool ok) { (void)o; (void)ok; }
static void __attribute__((unused)) mks_fgt_swap_issue(struct mks_fgt_owner *o) { (void)o; }
static void __attribute__((unused)) mks_fgt_swap_result(struct mks_fgt_owner *o, bool ok, int sd, bool cf) { (void)o; }
static void __attribute__((unused)) mks_fgt_copy_begin(struct mks_fgt_owner *o, int *si) { (void)o; (void)si; }
static void __attribute__((unused)) mks_fgt_copy_end(struct mks_fgt_owner *o) { (void)o; }
static void __attribute__((unused)) mks_fgt_copy_record(struct mks_fgt_owner *o, double p, int a, int b, int c, int d, bool e, const char *f, int g, bool h) { (void)o; }
static void __attribute__((unused)) mks_fgt_final_begin(struct mks_fgt_owner *o) { (void)o; }
static void __attribute__((unused)) mks_fgt_final_end(struct mks_fgt_owner *o) { (void)o; }
static void __attribute__((unused)) mks_fgt_bypass(struct mks_fgt_owner *o, int f, const char *s, bool tf) { (void)o; }
#define MKS_FGT_SUSP_ACQ 1
#define MKS_FGT_SUSP_REL 2
#define MKS_FGT_ROUTE_FUSED 0

static struct ra ra;
static struct ra_hwdec_mapper mapper;
static struct priv p;
static struct vo vo;
static struct frame_priv fp;
static struct mp_image image;
static struct pl_frame frame;
static struct texture textures[4];
static int fail_config, fail_map, fail_plane, mapped, unmapped, wrapped, destroyed;
static bool mapping_live;
static struct ra_hwdec_map_request seen_req_copy;
static int seen_req_valid;
static int ra_pl_get(struct ra *r) { assert(r); return r->pl; }
static bool hwdec_reconfig(struct priv *priv, struct ra_hwdec *hwdec,
                           const struct params *params) {
    (void)hwdec; (void)params;
    priv->hwdec_mapper=fail_config ? NULL : &mapper;
    return !fail_config;
}
static int ra_hwdec_mapper_map_with_request(struct ra_hwdec_mapper *m,
        struct mp_image *img, const struct ra_hwdec_map_request *req) {
    assert(m==&mapper && img==&image && !mapping_live); mapped++;
    if (req) { seen_req_copy = *req; seen_req_valid = 1; } else seen_req_valid = 0;
    mapping_live=!fail_map;
    return fail_map ? -1 : 0;
}
static void ra_hwdec_mapper_unmap(struct ra_hwdec_mapper *m) {
    assert(m==&mapper);
    if (!ra.pl) for (int i=0;i<4;i++) assert(!textures[i].live);
    mapping_live=false; unmapped++;
}
static pl_tex hwdec_get_tex(struct priv *priv, int n) {
    assert(priv==&p && mapping_live && n>=0 && n<4);
    if (n==fail_plane) return NULL;
    assert(!textures[n].live); textures[n].live=true; wrapped++;
    return &textures[n];
}
static void pl_tex_destroy(pl_gpu gpu, pl_tex *tex) {
    (void)gpu;
    if (!*tex) return;
    assert(mapping_live && (*tex)->live); (*tex)->live=false; *tex=NULL; destroyed++;
}
'''

TEST = r'''
static struct pl_overlay_part shared_parts[2];
static struct pl_overlay shared_overlay;

static void reset(bool is_pl) {
    ra=(struct ra){.pl=is_pl}; mapper=(struct ra_hwdec_mapper){.ra=&ra};
    p=(struct priv){0}; vo=(struct vo){.priv=&p};
    fp=(struct frame_priv){.vo=&vo};
    image=(struct mp_image){.priv=&fp,.params={.w=3840,.h=1920}};
    frame=(struct pl_frame){.user_data=&image,.num_planes=3};
    for (int i=0;i<4;i++) textures[i]=(struct texture){.id=i};
    fail_config=fail_map=mapped=unmapped=wrapped=destroyed=0; fail_plane=-1;
    mapping_live=false; seen_req_valid=0;
    ta_allocs=0; ta_frees=0;
}
static void set_geometry(int mapped_w, int mapped_h) {
    mapper.caps = RA_HWDEC_CAP_MAP_GEOMETRY;
    mapper.map_geometry = (struct ra_hwdec_map_geometry){
        .valid=true, .logical_w=3840, .logical_h=1920,
        .logical_rect={0,0,3840,1920}, .mapped_rect={0,0,mapped_w,mapped_h}};
    textures[0].params.w=mapped_w; textures[0].params.h=mapped_h;
}
static void reset_overlays(int coords) {
    shared_parts[0]=(struct pl_overlay_part){.src={0,0,10,10},.dst={0,0,3840,1920}};
    shared_parts[1]=(struct pl_overlay_part){.src={10,0,20,10},.dst={100,200,3940,2120}};
    shared_overlay=(struct pl_overlay){.parts=shared_parts,.num_parts=2,.coords=coords};
}
static void target_setup(void) {
    reset(false); vo.dwidth=2672; vo.dheight=1336; set_geometry(2672,1336);
    frame.crop=(struct pl_rect2df){0,0,3840,1920};
}
static void config_failure(void) {
    reset(false); fail_config=1;
    assert(!hwdec_acquire(NULL,&frame));
    hwdec_release(NULL,&frame);
    assert(!p.hwdec_mapper && !mapped && !unmapped && !destroyed);
}
static void map_failure(void) {
    reset(false); vo.dwidth=2672; vo.dheight=1336; fail_map=1;
    assert(!hwdec_acquire(NULL,&frame));
    hwdec_release(NULL,&frame);
    assert(mapped==1 && unmapped==1 && !wrapped && !destroyed);
}
static void partial_failure(int planes, int failed) {
    reset(false); frame.num_planes=planes; fail_plane=failed;
    assert(!hwdec_acquire(NULL,&frame));
    hwdec_release(NULL,&frame);
    assert(mapped==1 && unmapped==1 && wrapped==failed && destroyed==failed);
    assert(!mapping_live && !fp.lease_w && !fp.lease_h && !fp.rescale_ctx);
    for (int i=0;i<planes;i++) assert(!frame.planes[i].texture && !textures[i].live);
}
static void successful_acquire(bool is_pl) {
    reset(is_pl);
    assert(hwdec_acquire(NULL,&frame));
    hwdec_release(NULL,&frame);
    assert(mapped==1 && unmapped==1 && wrapped==3 && destroyed==(is_pl ? 0 : 3));
    for (int i=0;i<3;i++) assert(textures[i].live==is_pl);
}
static void request_matches_display(void) {
    reset(false); vo.dwidth=2672; vo.dheight=1336;
    assert(hwdec_acquire(NULL,&frame));
    assert(seen_req_valid && seen_req_copy.allow_full_frame_scale &&
           seen_req_copy.target_w==2672 && seen_req_copy.target_h==1336);
    assert(!fp.lease_w && !fp.lease_h);
    hwdec_release(NULL,&frame);
}
static void zero_display_sends_no_request(void) {
    reset(false);
    assert(hwdec_acquire(NULL,&frame));
    assert(!seen_req_valid);
    hwdec_release(NULL,&frame);
}
static void target_lease_recorded(void) {
    target_setup();
    assert(hwdec_acquire(NULL,&frame));
    assert(fp.lease_w==2672 && fp.lease_h==1336);
    hwdec_release(NULL,&frame);
}
static void source_size_lease_not_recorded(void) {
    reset(false); vo.dwidth=2672; vo.dheight=1336; set_geometry(3840,1920);
    assert(hwdec_acquire(NULL,&frame));
    assert(!fp.lease_w && !fp.lease_h);
    hwdec_release(NULL,&frame);
}
static void unpublished_geometry_keeps_classic(void) {
    reset(false); vo.dwidth=2672; vo.dheight=1336;
    mapper.caps=RA_HWDEC_CAP_MAP_GEOMETRY;
    textures[0].params.w=2672; textures[0].params.h=1336;
    assert(hwdec_acquire(NULL,&frame));
    assert(!fp.lease_w && !fp.lease_h);
    hwdec_release(NULL,&frame);
}
static void bad_geometry_fails_closed(void) {
    reset(false); vo.dwidth=2672; vo.dheight=1336; set_geometry(2672,1336);
    mapper.map_geometry.logical_h=1921;
    assert(!hwdec_acquire(NULL,&frame)); hwdec_release(NULL,&frame);
    reset(false); vo.dwidth=2672; vo.dheight=1336; set_geometry(2672,1336);
    mapper.map_geometry.mapped_rect.x1=2671;
    assert(!hwdec_acquire(NULL,&frame)); hwdec_release(NULL,&frame);
    reset(false); vo.dwidth=2672; vo.dheight=1336; set_geometry(2672,1336);
    image.params.rotate=90;
    assert(!hwdec_acquire(NULL,&frame)); hwdec_release(NULL,&frame);
    reset(false); vo.dwidth=2672; vo.dheight=1336; set_geometry(3840,1920);
    image.params.rotate=90;
    assert(hwdec_acquire(NULL,&frame));
    assert(!fp.lease_w && !fp.lease_h);
    hwdec_release(NULL,&frame);
    reset(false); vo.dwidth=2672; vo.dheight=1336; set_geometry(2672,1336);
    mapper.map_geometry.mapped_rect.x1=3840;
    assert(!hwdec_acquire(NULL,&frame)); hwdec_release(NULL,&frame);
}
static void stale_lease_cleared_on_failures(void) {
    target_setup();
    assert(hwdec_acquire(NULL,&frame)); hwdec_release(NULL,&frame);
    assert(fp.lease_w==2672 && !fp.rescale_ctx);
    fail_map=1;
    assert(!hwdec_acquire(NULL,&frame)); hwdec_release(NULL,&frame);
    assert(!fp.lease_w && !fp.lease_h && !fp.rescale_ctx);
    fail_map=0; fail_config=1;
    assert(!hwdec_acquire(NULL,&frame)); hwdec_release(NULL,&frame);
    assert(!fp.lease_w && !fp.rescale_ctx);
    fail_config=0;
}
static void rescale_full_crop(void) {
    target_setup();
    assert(hwdec_acquire(NULL,&frame));
    assert(frame.crop.x0==0 && frame.crop.y0==0 &&
           frame.crop.x1==2672 && frame.crop.y1==1336);
    assert(!frame.overlays && !frame.num_overlays && !fp.rescale_ctx);
    hwdec_release(NULL,&frame);
    assert(!fp.rescale_ctx);
}
static void rescale_partial_crop(void) {
    target_setup();
    frame.crop=(struct pl_rect2df){100,50,3740,1870};
    assert(hwdec_acquire(NULL,&frame));
    assert(frame.crop.x0==70 && frame.crop.y0==35 &&
           frame.crop.x1==2602 && frame.crop.y1==1301);
    hwdec_release(NULL,&frame);
}
static void rescale_zero_collapse_guard(void) {
    target_setup();
    frame.crop=(struct pl_rect2df){100,0,100.4f,1920};
    assert(hwdec_acquire(NULL,&frame));
    assert(frame.crop.x0==70 && frame.crop.x1==71);
    hwdec_release(NULL,&frame);
}
static void rescale_scaled_overlays(void) {
    target_setup(); reset_overlays(PL_OVERLAY_COORDS_SRC_CROP);
    frame.overlays=&shared_overlay; frame.num_overlays=1;
    assert(hwdec_acquire(NULL,&frame));
    assert(frame.overlays && frame.overlays!=&shared_overlay);
    assert(frame.overlays[0].num_parts==2);
    const struct pl_overlay_part *p0=&frame.overlays[0].parts[0];
    assert(p0->dst.x0==0 && p0->dst.x1==(float)(3840.0*(2672.0/3840.0)) &&
           p0->dst.y1==(float)(1920.0*(1336.0/1920.0)));
    assert(p0->src.x0==0 && p0->src.x1==10);
    const struct pl_overlay_part *p1=&frame.overlays[0].parts[1];
    assert(p1->dst.x0==(float)(100.0*(2672.0/3840.0)) &&
           p1->dst.y0==(float)(200.0*(1336.0/1920.0)) &&
           p1->dst.x1==(float)(3940.0*(2672.0/3840.0)) &&
           p1->dst.y1==(float)(2120.0*(1336.0/1920.0)));
    assert(p1->src.x0==10 && p1->src.x1==20);
    assert(shared_overlay.parts==shared_parts && shared_parts[0].dst.x1==3840);
    assert(shared_parts[1].dst.x1==3940);
    assert(fp.rescale_ctx!=NULL);
    hwdec_release(NULL,&frame);
    assert(!fp.rescale_ctx);
}
static void factor1_keeps_classic(void) {
    reset(false); vo.dwidth=2672; vo.dheight=1336; set_geometry(3840,1920);
    reset_overlays(PL_OVERLAY_COORDS_SRC_CROP);
    frame.crop=(struct pl_rect2df){0,0,3840,1920};
    frame.overlays=&shared_overlay; frame.num_overlays=1;
    assert(hwdec_acquire(NULL,&frame));
    assert(frame.crop.x1==3840 && frame.overlays==&shared_overlay &&
           !fp.rescale_ctx);
    hwdec_release(NULL,&frame);
}
static void dst_crop_overlays_copied_verbatim(void) {
    target_setup(); reset_overlays(PL_OVERLAY_COORDS_DST_CROP);
    frame.overlays=&shared_overlay; frame.num_overlays=1;
    assert(hwdec_acquire(NULL,&frame));
    // Target-space parts must not move with the sampled crop, but they are
    // still acquire-local copies and the shared state stays untouched.
    assert(frame.overlays && frame.overlays!=&shared_overlay);
    assert(frame.overlays[0].num_parts==2);
    const struct pl_overlay_part *p0=&frame.overlays[0].parts[0];
    assert(p0->dst.x0==0 && p0->dst.y0==0 && p0->dst.x1==3840 && p0->dst.y1==1920);
    const struct pl_overlay_part *p1=&frame.overlays[0].parts[1];
    assert(p1->dst.x0==100 && p1->dst.y0==200 && p1->dst.x1==3940 && p1->dst.y1==2120);
    assert(shared_overlay.parts==shared_parts && shared_parts[0].dst.x1==3840);
    assert(fp.rescale_ctx!=NULL);
    hwdec_release(NULL,&frame);
    assert(!fp.rescale_ctx);
}
static void repeated_acquire_release_cycles(void) {
    target_setup(); reset_overlays(PL_OVERLAY_COORDS_SRC_CROP);
    frame.overlays=&shared_overlay; frame.num_overlays=1;
    // Sequential renderer passes: every pass starts from a fresh copy of
    // the queue frame (whose overlays pointer is the shared, unscaled
    // state), every acquire allocates a fresh rescale context (ctx +
    // overlays array + parts array), every release frees it, and the
    // shared subtitle state never accumulates scaled values.
    for (int i=1;i<=3;i++) {
        // Every renderer pass rebuilds its copy from the queue frame,
        // including the classic source-space crop.
        frame.crop=(struct pl_rect2df){0,0,3840,1920};
        frame.overlays=&shared_overlay; frame.num_overlays=1;
        int allocs_before=ta_allocs, frees_before=ta_frees;
        assert(hwdec_acquire(NULL,&frame));
        assert(fp.rescale_ctx);
        assert(frame.crop.x1==2672 && frame.crop.y1==1336);
        assert(frame.overlays && frame.overlays!=&shared_overlay);
        assert(frame.overlays[0].parts[1].dst.x1==(float)(3940.0*(2672.0/3840.0)));
        assert(ta_allocs==allocs_before+3);
        hwdec_release(NULL,&frame);
        assert(!fp.rescale_ctx && ta_frees==frees_before+1);
        assert(shared_parts[1].dst.x1==3940);
    }
}
int main(void) {
    config_failure(); map_failure();
    for (int planes=1;planes<=4;planes++)
        for (int failed=0;failed<planes;failed++) partial_failure(planes,failed);
    successful_acquire(false); successful_acquire(true);
    request_matches_display(); zero_display_sends_no_request();
    target_lease_recorded(); source_size_lease_not_recorded();
    unpublished_geometry_keeps_classic(); bad_geometry_fails_closed();
    stale_lease_cleared_on_failures();
    rescale_full_crop(); rescale_partial_crop(); rescale_zero_collapse_guard();
    rescale_scaled_overlays(); dst_crop_overlays_copied_verbatim();
    factor1_keeps_classic(); repeated_acquire_release_cycles();
    return 0;
}
'''


class HwdecAcquireTests(unittest.TestCase):
    def test_actual_acquire_release_callbacks(self):
        source = NEXT.read_text()
        callbacks = ('static float ' + function(source, 'hwdec_scale_overlay_endpoint') + '\n' +
                     'static void ' + function(source, 'hwdec_lease_rescale_frame') + '\n' +
                     'static bool ' + function(source, 'hwdec_acquire') + '\n' +
                     'static void ' + function(source, 'hwdec_release'))
        with tempfile.TemporaryDirectory() as tmp:
            path, exe = Path(tmp) / 'acquire.c', Path(tmp) / 'acquire'
            path.write_text(STUBS + callbacks + '\n' + TEST)
            subprocess.run(['clang', '-std=c11', '-Wall', '-Werror', str(path),
                            '-o', str(exe)], check=True)
            subprocess.run([str(exe)], check=True)


if __name__ == '__main__':
    unittest.main()
