"""Check the real screenshot callback's OSD ownership using host doubles.

This covers control flow and distinct resources, not libass, libplacebo or GPU pixels.
"""
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).parent))
from test_lg_p84_mapper_contract import function


NEXT = Path(__file__).resolve().parents[2] / 'mpv/video/out/vo_gpu_next.c'

STUBS = r'''
#include <assert.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>
#define MAX_OSD_PARTS 4
#define MP_ARRAY_SIZE(a) (sizeof(a)/sizeof((a)[0]))
#define MP_ERR(...) ((void)0)
#define mp_assert assert
#define MPSWAP(type,a,b) do { type tmp=(a); (a)=(b); (b)=tmp; } while (0)
#define TA_FREEP(p) do { free(*(p)); *(p)=NULL; } while (0)
#define PL_API_VER 340
#define BLEND_SUBS_VIDEO 1
enum pl_overlay_coords { PL_OVERLAY_COORDS_SRC_CROP=1, PL_OVERLAY_COORDS_DST_CROP,
                         PL_OVERLAY_COORDS_DST_FRAME };
#define OSD_DRAW_OSD_ONLY 1
#define OSD_DRAW_SUB_ONLY 2
#define IMGFMT_RGBA64 1
#define IMGFMT_RGBA 2
#define IMGFMT_RGB0 3
#define PL_FMT_UNORM 1
#define PL_FMT_CAP_RENDERABLE 1
#define PL_FMT_CAP_HOST_READABLE 2
#define PL_FMT_CAP_STORABLE 4
#define PL_COLOR_TRC_SRGB 1
#define PL_COLOR_TRC_GAMMA22 2
#define pl_tex_params(...) (&(struct tex_params){__VA_ARGS__})
#define pl_tex_transfer_params(...) (&(struct transfer_params){__VA_ARGS__})

typedef void *pl_gpu;
struct color { int primaries,transfer,hdr; };
struct repr { int levels; };
struct rect { float x0,y0,x1,y1; };
struct mp_rect { int x0,y0,x1,y1; };
struct image_params { int w,h,rotate,p_w,p_h; struct mp_rect crop; struct color color; struct repr repr; };
struct mp_image { void *priv; double pts; struct image_params params; unsigned char *planes[4]; int stride[4]; };
struct mp_osd_res { int w,h; float ml,mr,mt,mb,display_par; };
struct fmt { int caps; };
typedef struct fmt *pl_fmt;
struct tex_params { int w,h; pl_fmt format; bool blit_dst,renderable,host_readable,storable; };
struct texture { struct tex_params params; int id; bool live; };
typedef struct texture *pl_tex;
struct transfer_params { pl_tex tex; void *ptr; int row_pitch; };
struct part { int x; };
struct osd_entry { pl_tex tex; struct part *parts; int num_parts; };
struct osd_state { struct osd_entry entries[MAX_OSD_PARTS]; int marker; };
struct pl_frame { struct color color; struct repr repr; int num_planes,num_overlays; struct rect crop; void *user_data;
    struct { pl_tex texture; int components; int component_mapping[4]; } planes[4]; };
struct frame_priv { struct osd_state subs; };
struct pl_frame_mix { int num_frames; const struct pl_frame **frames; };
enum pl_queue_status { PL_QUEUE_ERR=-1, QUEUE_OK=0, PL_QUEUE_EOF=1 };
struct pl_queue_params { double pts; int drift_compensation; };
#define pl_queue_params(...) (&(struct pl_queue_params){__VA_ARGS__})
struct pl_peak_detect_params { bool allow_delayed; };
struct pl_render_params { void *info_callback; bool skip_caching_single_frame,preserve_mixing_cache;
    void *frame_mixer; struct pl_peak_detect_params *peak_detect_params; };
struct options { struct pl_render_params params; int color_map_params; };
typedef struct options *pl_options;
struct gl_video_opts { int blend_subs,treat_srgb_as_power22; };
struct opts_cache { struct gl_video_opts *opts; };
struct ra_ctx { struct { bool want_alpha; } opts; };
struct priv { pl_options pars; pl_gpu gpu; void *rr,*queue; double last_pts;
    struct mp_rect src,dst; struct mp_osd_res osd_res; struct ra_ctx *ra_ctx;
    struct opts_cache *opts_cache; struct osd_state osd_state; };
struct vo { struct priv *priv; struct image_params *params; };
struct voctrl_screenshot { struct mp_image *res; bool scaled,high_bit_depth,native_csp,subs,osd; };
static struct repr pl_color_repr_rgb;
static struct color pl_color_space_srgb;
static struct fmt fmt={.caps=7};
static struct texture fbo, atlas;
static struct part original_part, scratch_part;
static struct osd_state *play_state,*screen_state;
static int updates,renders,downloads,tex_destroys,parts_frees;
static int expected_flags,expected_coords,expected_blend;
static bool render_ok,download_ok;
static const struct pl_frame *frames[1];
static void update_options(struct vo *vo) { (void)vo; }
static int pl_queue_update(void *q, struct pl_frame_mix *mix, struct pl_queue_params *params) {
    (void)q;(void)params; mix->num_frames=1; mix->frames=frames; return QUEUE_OK;
}
static void mp_image_params_get_dsize(struct image_params *p,int *w,int *h) { *w=p->w;*h=p->h; }
static bool mp_image_crop_valid(struct image_params *p) { (void)p;return false; }
static void mp_rect_rotate(struct mp_rect *r,int w,int h,int rotate) { (void)r;(void)w;(void)h;(void)rotate; }
static int mp_rect_w(struct mp_rect r) { return r.x1-r.x0; }
static int mp_rect_h(struct mp_rect r) { return r.y1-r.y0; }
static pl_fmt pl_find_fmt(pl_gpu gpu,int type,int components,int depth,int sample,int caps) {
    (void)gpu;(void)type;(void)components;(void)depth;(void)sample;(void)caps;return &fmt;
}
static pl_tex pl_tex_create(pl_gpu gpu,struct tex_params *params) {
    (void)gpu; fbo=(struct texture){.params=*params,.id=1,.live=true};return &fbo;
}
static void apply_target_options(struct priv *p,struct pl_frame *f,int z,bool b) { (void)p;(void)f;(void)z;(void)b; }
static void apply_crop(struct pl_frame *f,struct mp_rect r,int w,int h) {
    (void)w;(void)h; f->crop=(struct rect){r.x0,r.y0,r.x1,r.y1};
}
static void update_tm_viz(int *p,struct pl_frame *f) { (void)p;(void)f; }
static float pl_rect_w(struct rect r) { return r.x1-r.x0; }
static float pl_rect_h(struct rect r) { return r.y1-r.y0; }
static void update_overlays(struct vo *vo,struct mp_osd_res res,int flags,int coords,
                            struct osd_state *state,struct pl_frame *frame,struct mp_image *src) {
    (void)vo;(void)res;(void)src;
    assert(flags==expected_flags && coords==expected_coords);
    assert((expected_blend && frame->user_data) || (!expected_blend && !frame->user_data));
    updates++; screen_state=state;
    assert(state!=play_state);
    state->marker=99; state->entries[0]=(struct osd_entry){.tex=&atlas,.parts=&scratch_part,.num_parts=1};
    atlas.live=true;
}
static bool pl_render_image(void *rr,struct pl_frame *image,struct pl_frame *target,struct pl_render_params *p) {
    (void)rr;(void)target;(void)p;
    if (!expected_blend) assert(image->num_overlays==0);
    renders++;return render_ok;
}
static struct mp_image *mp_image_alloc(int format,int w,int h) {
    (void)format;(void)w;(void)h;return calloc(1,sizeof(struct mp_image));
}
static bool pl_tex_download(pl_gpu gpu,struct transfer_params *params) {
    (void)gpu;(void)params;downloads++;return download_ok;
}
static void pl_tex_destroy(pl_gpu gpu,pl_tex *tex) {
    (void)gpu;if (!*tex) return;assert((*tex)->live);(*tex)->live=false;*tex=NULL;tex_destroys++;
}
static void talloc_free(void *p) { if (p) { assert(p==&scratch_part);parts_frees++; } }
'''

TEST = r'''
static void run_case(int blend,bool scaled,bool subs,bool osd,bool render,bool download) {
    struct gl_video_opts opts={.blend_subs=blend}; struct opts_cache cache={.opts=&opts};
    struct options options={0}; struct ra_ctx ra={0};
    struct priv p={.pars=&options,.ra_ctx=&ra,.opts_cache=&cache,
        .src={0,0,100,50},.dst={0,0,100,50},.osd_res={.w=100,.h=50}};
    struct vo vo={.priv=&p}; struct frame_priv fp={0};
    struct image_params pars={.w=100,.h=50};vo.params=&pars;
    struct mp_image mpi={.priv=&fp,.params=pars};
    struct pl_frame image={.user_data=&mpi,.num_overlays=1}; frames[0]=&image;
    struct texture original_tex={.id=10,.live=true};
    play_state=blend ? &fp.subs : &p.osd_state;
    play_state->marker=7;play_state->entries[0]=(struct osd_entry){.tex=&original_tex,.parts=&original_part,.num_parts=1};
    struct voctrl_screenshot args={.scaled=scaled,.subs=subs,.osd=osd};
    updates=renders=downloads=tex_destroys=parts_frees=0;screen_state=NULL;
    expected_blend=blend;
    expected_flags=(!subs ? OSD_DRAW_OSD_ONLY : 0) | (!osd ? OSD_DRAW_SUB_ONLY : 0);
    expected_coords=blend==BLEND_SUBS_VIDEO ? PL_OVERLAY_COORDS_SRC_CROP :
                    blend ? PL_OVERLAY_COORDS_DST_CROP : PL_OVERLAY_COORDS_DST_FRAME;
    render_ok=render;download_ok=download;
    video_screenshot(&vo,&args);
    assert(updates==1 && screen_state && screen_state!=play_state);
    assert(play_state->marker==7 && play_state->entries[0].tex==&original_tex);
    assert(play_state->entries[0].parts==&original_part && original_tex.live);
    assert(tex_destroys==2 && parts_frees==1 && !atlas.live && !fbo.live);
    assert(renders==1 && downloads==(render ? 1 : 0));
    assert((args.res!=NULL)==(render && download));
    free(args.res);
}
int main(void) {
    for (int blend=0;blend<=2;blend++)
        for (int scaled=0;scaled<=1;scaled++)
            for (int subs=0;subs<=1;subs++)
                for (int osd=0;osd<=1;osd++) {
                    run_case(blend,scaled,subs,osd,false,false);
                    run_case(blend,scaled,subs,osd,true,false);
                    run_case(blend,scaled,subs,osd,true,true);
                }
    return 0;
}
'''


class ScreenshotOsdTests(unittest.TestCase):
    def test_screenshot_uses_private_osd_and_cleans_it(self):
        source = NEXT.read_text()
        body = 'static void ' + function(source, 'video_screenshot')
        with tempfile.TemporaryDirectory() as tmp:
            path, exe = Path(tmp) / 'screenshot.c', Path(tmp) / 'screenshot'
            path.write_text(STUBS + body + '\n' + TEST)
            subprocess.run(['clang', '-std=c11', '-Wall', '-Wextra', '-Werror',
                            '-Wno-unused-parameter', '-Wno-unused-function',
                            str(path), '-o', str(exe)], check=True)
            subprocess.run([str(exe)], check=True)


if __name__ == '__main__':
    unittest.main()
