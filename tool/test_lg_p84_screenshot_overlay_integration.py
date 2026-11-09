"""Exercise screenshot and overlay control flow with host resource doubles.

This extracts the production callbacks, but the OSD renderer, talloc, libplacebo
and GPU are doubles. It does not verify real subtitle pixels or GPU lifetime.
"""
from pathlib import Path
import subprocess
import tempfile
import unittest

from test_lg_p84_mapper_contract import function
from test_lg_p84_screenshot_osd import STUBS as SCREENSHOT_STUBS, NEXT


OVERLAY_STUBS = r'''
#define SUBBITMAP_COUNT 2
#define SUBBITMAP_BGRA 0
#define SUBBITMAP_LIBASS 1
#define PL_COLOR_PRIM_BT_709 1
#define PL_COLOR_TRC_SRGB 1
#define PL_COLOR_SDR_WHITE 100
#define PL_OVERLAY_NORMAL 1
#define PL_OVERLAY_MONOCHROME 2
#define PL_ALPHA_PREMULTIPLIED 1
#define PL_ALPHA_INDEPENDENT 2
#define MPMAX(a,b) ((a) > (b) ? (a) : (b))
#define MP_TARRAY_POP(p,n,out) ((n)>0 ? (*(out)=(p)[--(n)],true) : false)
#define MP_TARRAY_APPEND(ctx,p,n,value) do { \
    (void)(ctx); assert(!(p) && (n)==0 && parts_allocations<2); \
    (p)=malloc(sizeof(*(p))); assert(p); \
    parts_objects[parts_allocations]=p; parts_live[parts_allocations++]=true; \
    (p)[(n)++]=(value); \
} while (0)

struct pl_overlay_part { struct rect src,dst; float color[4]; };
struct pl_overlay { pl_tex tex; struct pl_overlay_part *parts; int num_parts;
    struct color color; int coords,mode; struct { int alpha; } repr; };
struct sub_bitmap { int src_x,src_y,w,h,x,y,dw,dh; struct { unsigned color; } libass; };
struct packed_image { unsigned char *planes[4]; int stride[4]; };
struct sub_bitmaps { int render_index,format,num_parts,packed_w,packed_h;
    bool video_color_space; struct packed_image *packed; struct sub_bitmap *parts; };
struct sub_bitmap_list { int num_items; struct sub_bitmaps **items; };
struct next_options { int image_subs_hdr_peak,sub_hdr_peak; };
static const bool mp_draw_sub_formats[SUBBITMAP_COUNT]={true,true};
static struct sub_bitmap_list list;
static struct sub_bitmaps items[2];
static struct sub_bitmaps *item_ptrs[2];
static struct sub_bitmap bitmaps[2];
static struct packed_image packed;
static struct texture pool_atlas[2],allocated_atlas[2];
static struct pl_overlay_part *parts_objects[2];
static bool parts_live[2];
static unsigned char pixels[16];
static int osd_calls,osd_frees,uploads,recreates,parts_allocations;
static int fail_recreate_at,fail_upload_at,draw_flags_seen;
static int want_count,want_attempts,want_uploads,want_published,want_coords;
static int want_width,want_height;
static bool use_pool,replace_atlas,large_atlas;
static struct mp_osd_res osd_res_seen;
static int transient_parts_frees;

static struct sub_bitmap_list *osd_render(void *osd,struct mp_osd_res res,double pts,
                                          int flags,const bool *formats) {
    (void)osd;(void)pts;(void)formats; osd_calls++;draw_flags_seen=flags;osd_res_seen=res;
    list.num_items=0;
    if (!(flags & OSD_DRAW_OSD_ONLY)) item_ptrs[list.num_items++]=&items[0];
    if (!(flags & OSD_DRAW_SUB_ONLY)) item_ptrs[list.num_items++]=&items[1];
    list.items=item_ptrs;return &list;
}
static bool pl_tex_recreate(pl_gpu gpu,pl_tex *tex,struct pl_tex_params *params) {
    (void)gpu;int n=++recreates;
    int expected=use_pool && large_atlas ? 4 : 2;
    assert(n<=2 && params->w==expected && params->h==expected);
    assert(params->host_writable && params->sampleable);
    if (*tex && replace_atlas) {
        assert((*tex)->live);
        (*tex)->live=false;
        *tex=NULL;
    }
    if (n==fail_recreate_at) return false;
    if (!*tex) *tex=&allocated_atlas[n-1];
    (*tex)->params=*params;(*tex)->live=true;return true;
}
static bool pl_tex_upload(pl_gpu gpu,struct pl_tex_transfer_params *params) {
    (void)gpu;int n=++uploads;
    pl_tex expected=use_pool && !replace_atlas ? &pool_atlas[1-(recreates-1)] :
                                               &allocated_atlas[recreates-1];
    assert(params->tex==expected && params->tex->live && n<=2);
    assert(params->ptr==pixels && params->row_pitch==8);
    assert(params->rc.x1==2 && params->rc.y1==2);
    return n!=fail_upload_at;
}
static void check_overlay_render(struct pl_frame *image,struct pl_frame *target) {
    struct pl_frame *frame=expected_blend ? image : target;
    assert(recreates==want_attempts && uploads==want_uploads);
    assert(frame->num_overlays==want_published);
    for (int i=0;i<want_published;i++) {
        struct pl_overlay *overlay=&frame->overlays[i];
        int item=item_ptrs[i]==&items[0] ? 0 : 1;
        pl_tex expected=use_pool && !replace_atlas ? &pool_atlas[1-i] : &allocated_atlas[i];
        assert(overlay->tex==expected && overlay->tex->live);
        assert(overlay->parts==parts_objects[i] && parts_live[i] && overlay->num_parts==1);
        assert(overlay->parts[0].src.x0==3+item && overlay->parts[0].src.x1==5+item);
        assert(overlay->parts[0].src.y0==5+item && overlay->parts[0].src.y1==7+item);
        assert(overlay->parts[0].dst.x0==10+item && overlay->parts[0].dst.x1==12+item);
        assert(overlay->parts[0].dst.y0==20+item && overlay->parts[0].dst.y1==22+item);
        assert(overlay->coords==want_coords);
        assert(overlay->mode==(item==0 ? PL_OVERLAY_NORMAL : PL_OVERLAY_MONOCHROME));
    }
    assert(fbo.live && fbo.params.w==want_width && fbo.params.h==want_height);
}
static void check_alloc_size(int w,int h) {
    assert(w==want_width && h==want_height);
}
static void check_overlay_download(struct pl_tex_transfer_params *params) {
    assert(params->tex==&fbo && params->tex->live);
    assert(params->ptr==download_pixels && params->row_pitch==want_width*4);
}
static bool pl_color_transfer_is_hdr(int value) { (void)value;return false; }
static bool pl_color_space_is_hdr(const struct color *value) { (void)value;return false; }
static void overlay_talloc_free(void *ptr) {
    if (ptr==&list) { osd_frees++;return; }
    if (!ptr) return;
    for (int i=0;i<parts_allocations;i++) {
        if (ptr==parts_objects[i]) {
            assert(parts_live[i]);parts_live[i]=false;transient_parts_frees++;return;
        }
    }
    assert(!"unknown parts allocation");
}
'''


INTEGRATION_TEST = r'''
static void run_integration(int blend,bool scaled,bool subs,bool osd,
                            bool render,bool download,int fail_recreate,int fail_upload,
                            bool from_pool,bool replace,bool large) {
    struct gl_video_opts opts={.blend_subs=blend};struct opts_cache cache={.opts=&opts};
    struct options options={0};struct ra_ctx ra={0};
    pl_tex pool[2]={&pool_atlas[0],&pool_atlas[1]};
    struct next_options next={.image_subs_hdr_peak=-1};
    struct priv p={.pars=&options,.ra_ctx=&ra,.opts_cache=&cache,.next_opts=&next,
        .src={0,0,200,100},.dst={0,0,100,50},.osd_res={.w=100,.h=50},
        .sub_tex=pool,.num_sub_tex=from_pool ? 2 : 0,.osd_fmt={&fmt,&fmt}};
    struct image_params pars={.w=200,.h=100};struct vo vo={.priv=&p,.params=&pars};
    struct frame_priv fp={0};struct mp_image mpi={.priv=&fp,.params=pars};
    struct pl_frame image={.user_data=&mpi,.num_overlays=1};frames[0]=&image;
    struct texture original_tex={.id=10,.live=true};
    play_state=blend ? &fp.subs : &p.osd_state;
    play_state->marker=7;
    play_state->entries[0]=(struct osd_entry){.tex=&original_tex,.parts=&original_part,.num_parts=1};
    struct voctrl_screenshot args={.scaled=scaled,.subs=subs,.osd=osd};
    expected_blend=blend;render_ok=render;download_ok=download;
    osd_calls=osd_frees=uploads=recreates=parts_allocations=0;
    transient_parts_frees=tex_destroys=renders=downloads=0;
    for (int i=0;i<2;i++) { parts_objects[i]=NULL;parts_live[i]=false; }
    fail_recreate_at=fail_recreate;fail_upload_at=fail_upload;
    use_pool=from_pool;replace_atlas=replace;large_atlas=large;
    want_count=(subs ? 1 : 0)+(osd ? 1 : 0);
    want_attempts=want_uploads=want_published=0;
    for (int i=1;i<=want_count;i++) {
        want_attempts++;
        if (i==fail_recreate) break;
        want_uploads++;
        if (i==fail_upload) break;
        want_published++;
    }
    want_coords=blend==BLEND_SUBS_VIDEO ? PL_OVERLAY_COORDS_SRC_CROP :
                blend ? PL_OVERLAY_COORDS_DST_CROP : PL_OVERLAY_COORDS_DST_FRAME;
    want_width=scaled ? 100 : 200;want_height=scaled ? 50 : 100;
    packed=(struct packed_image){.planes={pixels},.stride={8}};
    for (int i=0;i<2;i++) {
        pool_atlas[i]=(struct texture){.params={.w=large ? 4 : 2,.h=large ? 4 : 2},
                                      .id=20+i,.live=from_pool};
        allocated_atlas[i]=(struct texture){.id=30+i};
        bitmaps[i]=(struct sub_bitmap){.src_x=3+i,.src_y=5+i,.w=2,.h=2,
                                        .x=10+i,.y=20+i,.dw=2,.dh=2};
        items[i]=(struct sub_bitmaps){.render_index=i ? MAX_OSD_PARTS-1 : 0,.format=i,.num_parts=1,
            .packed_w=2,.packed_h=2,.packed=&packed,.parts=&bitmaps[i]};
        item_ptrs[i]=&items[i];
    }
    video_screenshot(&vo,&args);
    assert(osd_calls==1 && osd_frees==1);
    assert(draw_flags_seen==((!subs ? OSD_DRAW_OSD_ONLY : 0) |
                             (!osd ? OSD_DRAW_SUB_ONLY : 0)));
    assert(osd_res_seen.w==(blend==BLEND_SUBS_VIDEO || !scaled ? 200 : 100));
    assert(osd_res_seen.h==(blend==BLEND_SUBS_VIDEO || !scaled ? 100 : 50));
    assert(play_state->marker==7 && play_state->entries[0].tex==&original_tex);
    assert(play_state->entries[0].parts==&original_part && original_tex.live);
    assert(parts_allocations==want_published && transient_parts_frees==want_published);
    for (int i=0;i<parts_allocations;i++) {
        assert(!parts_live[i]);free(parts_objects[i]);
    }
    assert(renders==1 && downloads==(render ? 1 : 0));
    assert((args.res!=NULL)==(render && download));
    assert(!fbo.live);
    assert(p.num_sub_tex==(from_pool ? 2-want_attempts : 0));
    for (int i=0;i<2;i++) {
        assert(pool_atlas[i].live==(from_pool && i<p.num_sub_tex));
        assert(!allocated_atlas[i].live);
    }
    free(args.res);
}
int main(void) {
    for (int blend=0;blend<=2;blend++)
        for (int scaled=0;scaled<=1;scaled++)
            for (int subs=0;subs<=1;subs++)
                for (int osd=0;osd<=1;osd++)
                    for (int pool=0;pool<=1;pool++)
                        for (int replace=0;replace<=pool;replace++)
                            for (int large=0;large<=pool;large++) {
                                run_integration(blend,scaled,subs,osd,false,false,0,0,pool,replace,large);
                                run_integration(blend,scaled,subs,osd,true,false,0,0,pool,replace,large);
                                run_integration(blend,scaled,subs,osd,true,true,0,0,pool,replace,large);
                                for (int i=1;i<=2;i++) {
                                    run_integration(blend,scaled,subs,osd,true,true,i,0,pool,replace,large);
                                    run_integration(blend,scaled,subs,osd,true,true,0,i,pool,replace,large);
                                }
                            }
    return 0;
}
'''


def integration_stubs():
    code = SCREENSHOT_STUBS
    code = code.replace('#define PL_COLOR_TRC_SRGB 1\n', '')
    code = code.replace('#define MAX_OSD_PARTS 4', '#define MAX_OSD_PARTS 5')
    code = code.replace('struct color { int primaries,transfer,hdr; };',
                        'struct pl_hdr_metadata { float max_luma; };\n'
                        'struct color { int primaries,transfer; struct pl_hdr_metadata hdr; };')
    code = code.replace('struct tex_params', 'struct pl_tex_params')
    code = code.replace('struct transfer_params', 'struct pl_tex_transfer_params')
    code = code.replace('struct part { int x; };',
                        'struct pl_overlay_part;\nstruct part { int x; };')
    code = code.replace('struct osd_entry { pl_tex tex; struct part *parts; int num_parts; };',
                        'struct osd_entry { pl_tex tex; struct pl_overlay_part *parts; int num_parts; };')
    code = code.replace('struct osd_state { struct osd_entry entries[MAX_OSD_PARTS]; int marker; };',
                        'struct pl_overlay;\nstruct osd_state { struct osd_entry entries[MAX_OSD_PARTS]; '
                        'struct pl_overlay *overlays; int marker; };')
    code = code.replace('void *user_data;\n    struct {',
                        'void *user_data; struct pl_overlay *overlays;\n    struct {')
    code = code.replace('bool blit_dst,renderable,host_readable,storable;',
                        'bool blit_dst,renderable,host_readable,storable,host_writable,sampleable;')
    code = code.replace('pl_tex tex; void *ptr; int row_pitch;',
                        'pl_tex tex; void *ptr; int row_pitch; struct { int x1,y1; } rc;')
    code = code.replace('struct priv { pl_options pars;',
                        'struct next_options;\nstruct priv { struct next_options *next_opts; '
                        'pl_tex *sub_tex; int num_sub_tex; pl_fmt osd_fmt[2]; pl_options pars;')
    code = code.replace('struct vo { struct priv *priv; struct image_params *params; };',
                        'struct vo { struct priv *priv; struct image_params *params; void *osd; };')
    start = code.index('static void update_overlays(')
    end = code.index('static bool pl_render_image(', start)
    code = code[:start] + code[end:]
    code = code.replace('static int updates,renders,downloads,tex_destroys,parts_frees;',
                        'static int renders,downloads,tex_destroys;')
    code = code.replace('static int expected_flags,expected_coords,expected_blend;',
                        'static int expected_blend;')
    code = code.replace('static struct part original_part, scratch_part;',
                        'static struct part original_part;')
    code = code.replace('static struct osd_state *play_state,*screen_state;',
                        'static struct osd_state *play_state;')
    code = code.replace('static struct texture fbo, atlas;', 'static struct texture fbo;')
    code = code.replace('static void talloc_free(void *p) { if (p) { assert(p==&scratch_part);parts_frees++; } }', '')
    code = code.replace('static bool pl_render_image(',
                        'static void check_overlay_render(struct pl_frame *,struct pl_frame *);\n'
                        'static void check_overlay_download(struct pl_tex_transfer_params *);\n'
                        'static void check_alloc_size(int,int);\n'
                        'static bool pl_render_image(')
    code = code.replace('(void)rr;(void)target;(void)p;\n    if (!expected_blend)',
                        '(void)rr;(void)p;check_overlay_render(image,target);\n    if (!expected_blend)')
    code = code.replace('(void)format;(void)w;(void)h;return calloc(1,sizeof(struct mp_image));',
                        '(void)format;check_alloc_size(w,h);struct mp_image *out=calloc(1,sizeof(*out));\n'
                        '    if (out) { out->planes[0]=download_pixels;out->stride[0]=w*4; }\n'
                        '    assert(w>0 && h>0);return out;')
    code = code.replace('(void)gpu;(void)params;downloads++;return download_ok;',
                        '(void)gpu;check_overlay_download(params);downloads++;return download_ok;')
    code = code.replace('static struct texture fbo;',
                        'static struct texture fbo;\nstatic unsigned char download_pixels[16];')
    return code


class ScreenshotOverlayIntegrationTests(unittest.TestCase):
    def test_real_callbacks_with_resource_doubles(self):
        source = NEXT.read_text()
        overlay = 'static void ' + function(source, 'update_overlays')
        screenshot = 'static void ' + function(source, 'video_screenshot')
        stubs = integration_stubs()
        # The production struct contains an inline overlay array. Complete that
        # type before declaring the test struct rather than replacing ownership.
        stubs = stubs.replace('struct pl_overlay;\nstruct osd_state',
                              'struct pl_overlay { pl_tex tex; struct pl_overlay_part *parts; '
                              'int num_parts; struct color color; int coords,mode; '
                              'struct { int alpha; } repr; };\nstruct osd_state')
        stubs = stubs.replace('struct pl_overlay *overlays; int marker;',
                              'struct pl_overlay overlays[MAX_OSD_PARTS]; int marker;')
        overlay_stubs = OVERLAY_STUBS.replace(
            'struct pl_overlay { pl_tex tex; struct pl_overlay_part *parts; int num_parts;\n'
            '    struct color color; int coords,mode; struct { int alpha; } repr; };\n', '')
        stubs = stubs.replace('struct part original_part;',
                              'struct pl_overlay_part original_part;')
        with tempfile.TemporaryDirectory() as tmp:
            path, exe = Path(tmp) / 'integration.c', Path(tmp) / 'integration'
            path.write_text(stubs + overlay_stubs + '\n#define talloc_free overlay_talloc_free\n' +
                            overlay + '\n' + screenshot + '\n' + INTEGRATION_TEST)
            subprocess.run(['clang', '-std=c11', '-Wall', '-Wextra', '-Werror',
                            '-Wno-unused-parameter', '-Wno-unused-function',
                            str(path), '-o', str(exe)], check=True)
            subprocess.run([str(exe)], check=True)


if __name__ == '__main__':
    unittest.main()
