"""Exercise the real software screenshot control flow with host doubles.

This checks snapshot timing and propagation, not real OSD, image scaling or GPU.
"""
from pathlib import Path
import subprocess
import tempfile
import unittest


SOURCE = Path(__file__).resolve().parents[2] / 'mpv/player/screenshot.c'


class SoftwareScreenshotTests(unittest.TestCase):
    def test_window_geometry_snapshot_and_fallback(self):
        source = SOURCE.read_text()
        start = source.index('static void add_osd(')
        end = source.index('struct mp_image *convert_image(', start)
        functions = source[start:end]
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / 'test.c'
            executable = Path(temp) / 'test'
            path.write_text(STUBS + functions + CASES)
            subprocess.run(['clang', '-std=c11', '-Wall', '-Wextra', '-Werror',
                            str(path), '-o', str(executable)], check=True, timeout=30)
            subprocess.run([str(executable)], check=True, timeout=5)


STUBS = r'''
#include <assert.h>
#include <stdbool.h>
#include <string.h>
#define MODE_SCALED 1
#define MODE_SUBTITLES 2
#define MODE_OSD 4
#define OSD_DRAW_SUB_ONLY 1
#define OSD_DRAW_OSD_ONLY 2
#define VOCTRL_SCREENSHOT 1
#define VOCTRL_SCREENSHOT_WIN 2
#define IMGFMT_IS_HWACCEL(x) ((x) == 99)
#define MP_VERBOSE(...) ((void)0)
#define MP_ERR(...) ((void)0)

struct mp_rect { int x0,y0,x1,y1; };
struct mp_image_params { int w,h; struct mp_rect crop; };
struct mp_image { int imgfmt,w,h; struct mp_image_params params; };
struct mp_osd_res { int w,h,ml,mr,mt,mb; double display_par; };
struct image_writer_opts { bool high_bit_depth; };
struct options { bool screenshot_sw; struct image_writer_opts *screenshot_image_opts; };
struct vo { bool config_ok; void *osd; };
struct MPContext { struct options *opts; struct vo *video_out; void *osd;
                   void *screenshot_ctx; double video_pts; };
struct voctrl_screenshot { bool scaled,subs,osd,high_bit_depth,native_csp;
                           struct mp_image *res; };
struct mp_sws_context { int unused; };
static struct mp_image source_image, crop_image, output_image, hardware_image;
static struct mp_sws_context sws;
static struct mp_osd_res window_res, original_res, draw_res[2];
static int get_count, control_count, window_count, draw_count, scale_count, free_count;
static int wait_count, draw_flags[2], expected_mode;
static int source_frees, crop_frees, output_frees, sws_frees, crop_calls;
static bool source_live,crop_live,output_live,sws_live;
static bool filtered, hardware_success, window_success, alloc_fail, no_frame, resize_during_wait;
static bool crop_needed, ref_fail, scale_fail;
static bool live_image(struct mp_image *image) {
    if (image==&source_image) return source_live;
    if (image==&crop_image) return crop_live;
    if (image==&output_image) return output_live;
    return image==&hardware_image;
}
static bool same_res(struct mp_osd_res a, struct mp_osd_res b) {
    return a.w==b.w && a.h==b.h && a.ml==b.ml && a.mr==b.mr &&
           a.mt==b.mt && a.mb==b.mb && a.display_par==b.display_par;
}
static bool osd_get_render_subs_in_filter(void *osd) { (void)osd;return filtered; }
static struct mp_osd_res osd_get_vo_res(void *osd) {
    (void)osd;assert(wait_count==1);get_count++;return window_res;
}
static struct mp_osd_res osd_res_from_image_params(const struct mp_image_params *p) {
    return (struct mp_osd_res){.w=p->w,.h=p->h,.display_par=1};
}
static bool osd_res_equals(struct mp_osd_res a,struct mp_osd_res b) { return same_res(a,b); }
static void osd_draw_on_image(void *osd,struct mp_osd_res res,double pts,int flags,
                              struct mp_image *image) {
    (void)osd;(void)pts;assert(image && live_image(image));
    assert(flags==OSD_DRAW_SUB_ONLY || flags==OSD_DRAW_OSD_ONLY);
    assert(draw_count<2);draw_flags[draw_count]=flags;draw_res[draw_count++]=res;
}
static void vo_wait_frame(struct vo *vo) {
    (void)vo;wait_count++;
    if (resize_during_wait) window_res=original_res;
}
static bool image_writer_flexible_csp(const struct image_writer_opts *opts) { (void)opts;return true; }
static void vo_control(struct vo *vo,int cmd,void *arg) {
    (void)vo;
    if (cmd==VOCTRL_SCREENSHOT) {
        struct voctrl_screenshot *ctrl=arg;control_count++;
        assert(ctrl->scaled==!!(expected_mode&MODE_SCALED));
        assert(ctrl->subs==!!(expected_mode&MODE_SUBTITLES));
        assert(ctrl->osd==!!(expected_mode&MODE_OSD));
        window_res=(struct mp_osd_res){.w=333,.h=222,.display_par=1};
        if (hardware_success) ctrl->res=&hardware_image;
    } else {
        assert(cmd==VOCTRL_SCREENSHOT_WIN);window_count++;
        if (window_success) *(struct mp_image **)arg=&hardware_image;
    }
}
static struct mp_image *vo_get_current_frame(struct vo *vo) {
    (void)vo;return no_frame ? NULL : &source_image;
}
static struct mp_image *mp_image_hw_download(struct mp_image *image,void *x) { (void)image;(void)x;return NULL; }
static void talloc_free(void *p) {
    if (!p) return;
    free_count++;
    if (p==&source_image) { assert(source_live && ++source_frees==1);source_live=false; }
    else if (p==&crop_image) { assert(crop_live && ++crop_frees==1);crop_live=false; }
    else if (p==&output_image) { assert(output_live && ++output_frees==1);output_live=false; }
    else if (p==&sws) { assert(sws_live && ++sws_frees==1);sws_live=false; }
    else assert(false);
}
static bool mp_image_crop_valid(const struct mp_image_params *p) { (void)p;return crop_needed; }
static int mp_rect_w(struct mp_rect r) { return r.x1-r.x0; }
static int mp_rect_h(struct mp_rect r) { return r.y1-r.y0; }
static struct mp_image *mp_image_new_ref(struct mp_image *p) {
    assert(p==&source_image && source_live);if (ref_fail) return NULL;
    assert(!crop_live);crop_image=*p;crop_live=true;return &crop_image;
}
static void mp_image_crop_rc(struct mp_image *p,struct mp_rect r) {
    assert(p==&crop_image && crop_live);
    assert(r.x0==source_image.params.crop.x0 && r.y0==source_image.params.crop.y0);
    assert(r.x1==source_image.params.crop.x1 && r.y1==source_image.params.crop.y1);
    crop_calls++;p->w=p->params.w=mp_rect_w(r);p->h=p->params.h=mp_rect_h(r);
}
static struct mp_image *mp_image_alloc(int fmt,int w,int h) {
    if (alloc_fail) return NULL;
    assert(!output_live);output_live=true;
    output_image=(struct mp_image){.imgfmt=fmt,.w=w,.h=h,.params={.w=w,.h=h}};
    return &output_image;
}
static struct mp_sws_context *mp_sws_alloc(void *p) {
    (void)p;assert(!sws_live);sws_live=true;return &sws;
}
static int mp_sws_scale(struct mp_sws_context *s,struct mp_image *dst,struct mp_image *src) {
    assert(s==&sws && sws_live && dst==&output_image && output_live);
    assert(src==(crop_needed ? &crop_image : &source_image) && live_image(src));
    scale_count++;window_res=(struct mp_osd_res){.w=999,.h=777,.display_par=3};
    return scale_fail ? -1 : 0;
}
static void mp_image_params_guess_csp(struct mp_image_params *p) {
    assert((p==&source_image.params && source_live) || (p==&crop_image.params && crop_live) ||
           (p==&output_image.params && output_live) || p==&hardware_image.params);
}
'''


CASES = r'''
static void reset(void) {
    source_image=(struct mp_image){.imgfmt=1,.w=640,.h=480,.params={.w=640,.h=480}};
    hardware_image=(struct mp_image){.imgfmt=1,.w=800,.h=450,.params={.w=800,.h=450}};
    original_res=(struct mp_osd_res){.w=1920,.h=1080,.ml=11,.mr=22,.mt=33,.mb=44,.display_par=1.25};
    window_res=original_res;memset(draw_res,0,sizeof(draw_res));memset(draw_flags,0,sizeof(draw_flags));
    get_count=control_count=window_count=draw_count=scale_count=free_count=0;
    wait_count=expected_mode=source_frees=crop_frees=output_frees=sws_frees=crop_calls=0;
    source_live=true;crop_live=output_live=sws_live=false;
    filtered=hardware_success=window_success=alloc_fail=no_frame=resize_during_wait=false;
    crop_needed=ref_fail=scale_fail=false;
}
int main(void) {
    struct image_writer_opts writer={.high_bit_depth=true};
    struct options opts={.screenshot_image_opts=&writer};
    struct vo vo={.config_ok=true};
    struct MPContext ctx={.opts=&opts,.video_out=&vo,.video_pts=12};
    for (int mode=0;mode<8;mode++) {
        for (int sw=0;sw<2;sw++) for (int hw=0;hw<2;hw++) for (int filter=0;filter<2;filter++) {
            reset();opts.screenshot_sw=sw;hardware_success=hw;filtered=filter;
            int effective=filter ? mode & ~MODE_SUBTITLES : mode;expected_mode=effective;
            struct mp_image *got=screenshot_get(&ctx,mode,true);
            assert(wait_count==1 && get_count==!!(effective&MODE_SCALED));
            if (!sw && hw) {
                assert(got==&hardware_image && control_count==1 && !scale_count && !draw_count);
                assert(!source_frees && !sws_frees && !free_count);
            } else {
                int expected_draws=!!(effective&MODE_SUBTITLES)+!!(effective&MODE_OSD);
                assert(got && draw_count==expected_draws);
                int draw=0;
                if (effective&MODE_SUBTITLES) assert(draw_flags[draw++]==OSD_DRAW_SUB_ONLY);
                if (effective&MODE_OSD) assert(draw_flags[draw++]==OSD_DRAW_OSD_ONLY);
                assert(control_count==!sw);
                assert(window_count==(!sw && (effective&7)==7));
                if (effective&MODE_SCALED) {
                    assert(got==&output_image && got->w==1920 && got->h==1080 && scale_count==1);
                    assert(source_frees==1 && sws_frees==1 && free_count==2);
                    for (int i=0;i<draw_count;i++) assert(same_res(draw_res[i],original_res));
                } else {
                    assert(got==&source_image && !scale_count);
                    assert(!source_frees && !sws_frees && !free_count);
                    for (int i=0;i<draw_count;i++) assert(draw_res[i].w==640 && draw_res[i].h==480);
                }
            }
        }
    }
    reset();opts.screenshot_sw=false;expected_mode=MODE_SCALED|MODE_OSD;window_res.w=0;
    assert(screenshot_get(&ctx,expected_mode,true)==NULL && !scale_count && !draw_count);
    assert(source_frees==1 && free_count==1);
    reset();opts.screenshot_sw=true;expected_mode=MODE_SCALED|MODE_OSD;window_res.h=-1;
    assert(screenshot_get(&ctx,expected_mode,true)==NULL && !scale_count && !draw_count);
    assert(source_frees==1 && free_count==1);
    reset();opts.screenshot_sw=false;expected_mode=MODE_SCALED|MODE_OSD;
    window_res.w=0;hardware_success=true;
    assert(screenshot_get(&ctx,expected_mode,true)==&hardware_image && get_count==1 && !free_count);
    reset();opts.screenshot_sw=false;expected_mode=7;window_res.w=0;window_success=true;
    assert(screenshot_get(&ctx,expected_mode,true)==&hardware_image && get_count==1);
    assert(window_count==1 && !scale_count && !draw_count && !free_count);
    reset();opts.screenshot_sw=true;expected_mode=MODE_SCALED|MODE_OSD;alloc_fail=true;
    assert(screenshot_get(&ctx,expected_mode,true)==NULL && source_frees==1 && !draw_count);
    reset();opts.screenshot_sw=true;expected_mode=MODE_OSD;no_frame=true;
    assert(screenshot_get(&ctx,expected_mode,true)==NULL && !free_count && !draw_count);
    reset();opts.screenshot_sw=true;expected_mode=MODE_SCALED|MODE_OSD;scale_fail=true;
    assert(screenshot_get(&ctx,expected_mode,true)==NULL);
    assert(scale_count==1 && !draw_count && source_frees==1 && output_frees==1 && sws_frees==1);
    assert(free_count==3);
    reset();opts.screenshot_sw=true;expected_mode=MODE_SCALED|MODE_OSD;crop_needed=ref_fail=true;
    source_image.params.crop=(struct mp_rect){10,20,610,460};
    assert(screenshot_get(&ctx,expected_mode,true)==NULL);
    assert(!crop_calls && !scale_count && !draw_count && source_frees==1 && free_count==1);
    reset();opts.screenshot_sw=true;expected_mode=MODE_SCALED|MODE_OSD;crop_needed=true;
    source_image.params.crop=(struct mp_rect){10,20,610,460};
    assert(screenshot_get(&ctx,expected_mode,true)==&output_image);
    assert(crop_calls==1 && scale_count==1 && draw_count==1);
    assert(source_frees==1 && crop_frees==1 && sws_frees==1 && !output_frees && free_count==3);
    reset();opts.screenshot_sw=true;expected_mode=MODE_SCALED|MODE_OSD;crop_needed=scale_fail=true;
    source_image.params.crop=(struct mp_rect){10,20,610,460};
    assert(screenshot_get(&ctx,expected_mode,true)==NULL);
    assert(crop_calls==1 && scale_count==1 && !draw_count);
    assert(source_frees==1 && crop_frees==1 && output_frees==1 && sws_frees==1 && free_count==4);
    reset();opts.screenshot_sw=true;expected_mode=MODE_SCALED|MODE_OSD;
    original_res=window_res=(struct mp_osd_res){.w=640,.h=480,.display_par=1};
    assert(screenshot_get(&ctx,expected_mode,true)==&source_image);
    assert(source_live && !scale_count && !free_count && draw_count==1);
    reset();opts.screenshot_sw=true;expected_mode=MODE_SCALED|MODE_OSD;crop_needed=true;
    source_image.params.crop=(struct mp_rect){10,20,610,460};
    original_res=window_res=(struct mp_osd_res){.w=600,.h=440,.display_par=1};
    assert(screenshot_get(&ctx,expected_mode,true)==&crop_image);
    assert(crop_live && source_frees==1 && crop_calls==1 && !scale_count && draw_count==1);
    assert(!crop_frees && !output_frees && !sws_frees && free_count==1);
    reset();opts.screenshot_sw=true;expected_mode=MODE_SCALED|MODE_OSD;
    resize_during_wait=true;window_res.w=333;window_res.h=222;
    assert(screenshot_get(&ctx,expected_mode,true)==&output_image && wait_count==1);
    assert(output_image.w==original_res.w && output_image.h==original_res.h);
    assert(draw_count==1 && same_res(draw_res[0],original_res));
    reset();opts.screenshot_sw=false;expected_mode=MODE_SCALED|MODE_OSD;hardware_success=true;
    vo.config_ok=false;assert(!screenshot_get(&ctx,expected_mode,true));
    assert(!wait_count && !get_count && !control_count);vo.config_ok=true;
    return 0;
}
'''


if __name__ == '__main__':
    unittest.main()
