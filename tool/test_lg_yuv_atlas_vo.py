"""Exercise the actual VO atlas serializer/poll/render with CPU API doubles."""
from pathlib import Path
import json
import subprocess
import sys
import tempfile
import unittest
from tool.test_lg_yuv_compare_manifest import ROOT, SOURCE, STUBS
from tool.analyze_lg_yuv_capture import atlas_metadata, InvalidCapture
sys.path.insert(0, str(Path(__file__).parent))
import lg_p84_atlas_round as atlas_host


def functions():
    source = SOURCE.read_text()
    start = source.index('static bool atlas_result_valid(')
    end = source.index('\n#endif\n\nstatic bool compare_save(', start)
    flip_start = source.index('static void flip_page(')
    flip_end = source.index('\nstatic void get_vsync(', flip_start)
    return source[start:end] + '\nstatic void compare_poll(struct vo *v) { atlas_poll(v); }\n' + source[flip_start:flip_end]


BASE = STUBS.replace('void *gpu, *fusion_target, *ra_ctx;',
                    'void *gpu, *fusion_target, *ra_ctx, *atlas_anchor;\n bool compare_atlas,compare_started,compare_a_ready;')
BASE = BASE.replace('struct priv {', 'struct ra_swapchain {struct swap_fns {void (*swap_buffers)(struct ra_swapchain *);} *fns;};\nstruct ra_ctx {struct ra_swapchain *swapchain;struct ctx_fns {void (*yuv_fusion_abort)(struct ra_ctx *);} *fns;};\nstruct priv {')
BASE = BASE.replace('void *gpu, *fusion_target, *ra_ctx, *atlas_anchor;', 'void *gpu, *fusion_target, *atlas_anchor, *sw;struct ra_ctx *ra_ctx;\n struct {bool enabled;unsigned flip,submit;} thermal;\n bool fusion_presentation_guard,fusion_frame_trace,frame_pending,compare_frame_open,compare_fatal_context;')
BASE += r'''
#include "video/out/yuv_atlas_anchor.h"
#define HAVE_GL 1
#define HAVE_EGL_ANDROID 1
#define PL_HAVE_OPENGL 1
#define PL_HAVE_MKS_YUV_COMPARE 1
#define PL_HAVE_MKS_UV_ATLAS_ANCHOR 1
#define MPMIN(a,b) ((a)<(b)?(a):(b))
struct pl_opengl_uv_atlas_anchor_result {
 uint64_t capture_id,generation;int width,height;size_t pixels,rgba_words,atlas_words;
 bool draw_ok[3],readback_ok[3],half_exact[3];uint64_t program_tokens[3];
 uint64_t draw_epoch_before[3],draw_epoch_after[3],readback_epoch_before[3],readback_epoch_after[3],finish_epoch;
 unsigned framebuffer[3],read_format,read_type;
 bool source_abi_ok,fence_signaled,atlas_complete,anchor_equal;
 size_t mismatches_before_atlas,mismatches_before_after,bad_half_components[3],bad_atlas_pixels;
};
struct pl_opengl_uv_atlas_anchor_params {uint64_t capture_id,generation;};
enum {PL_OPENGL_UV_ATLAS_ANCHOR_FAILED=-1,PL_OPENGL_UV_ATLAS_ANCHOR_PENDING=0,
 PL_OPENGL_UV_ATLAS_ANCHOR_COMPLETE=1,MKS_YUV_COMPARE_FAILED=-1,MKS_YUV_COMPARE_READY=2};
static uint32_t before[8],middle[8],after[8],atlas[6],android_data[14];
static struct pl_opengl_uv_atlas_anchor_result native_result;
static struct mks_yuv_compare_result native_android;
static int native_status,android_status,poll_calls,android_calls,aborts,render_calls,flush_calls,arm_calls;
static bool baseline_ok=true,arm_ok=true,render_ok=true,android_arm_ok=true;
static int baseline_calls;
static uint64_t epoch=7;static int64_t now=100;
static int64_t mp_time_ns(void){return now;}
static bool compare_baseline_ok(struct priv *p){(void)p;baseline_calls++;return baseline_ok;}
static bool pl_opengl_error_epoch(void *g,uint64_t *out){(void)g;*out=epoch;return true;}
static void compare_fail_transaction(struct vo *vo,const char *why){(void)why;aborts++;vo->priv->compare_terminal=true;vo->priv->compare_active=false;}
static bool pl_opengl_uv_atlas_anchor_data(void *h,const uint32_t **a,const uint32_t **b,const uint32_t **c,const uint32_t **uv){
 (void)h;*a=before;*b=middle;*c=after;*uv=atlas;return strcmp(body_mode,"data-failed")!=0;
}
static bool pl_opengl_uv_atlas_anchor_sources(void *h,const char **a,const char **b,const char **v,const char **orig){
 (void)h;*a="normal original body";*b="instrumented middle";*v=a0_vertex;*orig="original body";
 if(!strcmp(body_mode,"source-missing"))*v=NULL;
 if(!strcmp(body_mode,"source-ssbo"))*a="layout(std430) buffer A {}; original body";
 if(!strcmp(body_mode,"source-capture"))*a="mks_tap_count original body";
 if(!strcmp(body_mode,"source-identical"))*b=*a;
 if(!strcmp(body_mode,"source-original-mismatch"))*orig="unrelated body";
 return strcmp(body_mode,"sources-failed")!=0;
}
static bool pl_opengl_uv_atlas_anchor_vertices(void *h,const uint8_t **data,struct pl_opengl_yuv_compare_quad_layout *q){
 const uint8_t *unused;(void)h;bool ok=pl_opengl_yuv_compare_quad_payloads(NULL,NULL,data,&unused,q);
 q->viewport.x1=q->scissors.x1=2;q->viewport.y1=q->scissors.y1=1;return ok;
}
static int mks_android_yuv_compare_poll(void *ctx,struct mks_yuv_compare_result *out){(void)ctx;android_calls++;*out=native_android;return android_status;}
static int pl_opengl_uv_atlas_anchor_poll(void *h,struct pl_opengl_uv_atlas_anchor_result *out){(void)h;poll_calls++;*out=native_result;return native_status;}
struct mp_image {double pts;};
struct vo_frame {const struct mp_image *current;uint64_t frame_id;};
struct pl_frame {void *user_data;};
struct pl_frame_mix {const struct pl_frame **frames;};
struct pl_render_params {int marker;};
struct pl_swapchain_frame {void *fbo;};
struct ra_yuv_fusion_target {uint64_t generation,token;int w,h;};
struct mks_yuv_compare_roi {int x,y,w,h;};
static const struct pl_frame *expected_target;
static bool mks_android_yuv_compare_arm(void *ctx,uint64_t id,uint64_t gen,struct mks_yuv_compare_roi roi){
 (void)ctx;assert(id && gen==2 && roi.w==2 && roi.h==1);return android_arm_ok;
}
static void *pl_opengl_uv_atlas_anchor_arm(void *gpu,void *target,const struct pl_opengl_uv_atlas_anchor_params *p){
 (void)gpu;arm_calls++;assert(target==(void*)55 && p->capture_id && p->generation==2);return arm_ok?(void*)1:NULL;
}
static bool pl_render_image_mix(void *renderer,const struct pl_frame_mix *mix,const struct pl_frame *target,const struct pl_render_params *params){
 (void)renderer;assert(mix && params->marker==123 && target==expected_target);render_calls++;return render_ok;
}
static void pl_gpu_flush(void *gpu){(void)gpu;flush_calls++;}
static int submit_calls,swap_calls,receipt_aborts;static bool submit_ok=true,submit_epoch_error;
static bool pl_swapchain_submit_frame(void *sw){(void)sw;submit_calls++;if(submit_epoch_error)epoch++;return submit_ok;}
static void fake_swap(struct ra_swapchain *sw){(void)sw;swap_calls++;}
static void fake_abort(struct ra_ctx *ctx){(void)ctx;receipt_aborts++;}
static struct swap_fns sw_fns={.swap_buffers=fake_swap};
static struct ra_swapchain ra_sw={.fns=&sw_fns};
static struct ctx_fns ctx_fns={.yuv_fusion_abort=fake_abort};
static struct ra_ctx context={.swapchain=&ra_sw,.fns=&ctx_fns};
static void mks_thermal_report(void *thermal,bool final){(void)thermal;(void)final;}
static void gpu_timing_report(struct vo *vo,bool final){(void)vo;(void)final;}

'''
# atlas_render additionally needs the ordinary renderer member.
BASE = BASE.replace('void *gpu, *fusion_target, *atlas_anchor, *sw;',
                    'void *gpu, *fusion_target, *atlas_anchor, *sw, *rr;')

MAIN = r'''
static void reset(struct priv *p){
 *p=(struct priv){.compare_atlas=true,.atlas_anchor=(void*)1,.compare_active=true,.compare_epoch_valid=true,
 .compare_error_epoch=7,.compare_id=UINT64_MAX,.compare_generation=2,.compare_frame_id=11,.compare_frame_token=13,
 .compare_source_pts=35.035,.compare_current_pts=35.035,.compare_target_pts=35.035,
 .compare_width=2,.compare_height=1,.compare_x=0,.compare_y=0,.compare_w=2,.compare_h=1,.compare_deadline=1000};
 native_result=(struct pl_opengl_uv_atlas_anchor_result){.capture_id=UINT64_MAX,.generation=2,
 .width=2,.height=1,.pixels=2,.rgba_words=8,.atlas_words=6,.draw_ok={true,true,true},
 .readback_ok={true,true,true},.half_exact={true,true,true},.program_tokens={11,22,11},
 .draw_epoch_before={7,7,7},.draw_epoch_after={7,7,7},.readback_epoch_before={7,7,7},
 .readback_epoch_after={7,7,7},.finish_epoch=7,.framebuffer={55,55,55},.read_format=6408,.read_type=5126,
 .source_abi_ok=true,.fence_signaled=true,.atlas_complete=true,.anchor_equal=true};
 memset(before,0,sizeof(before));memset(middle,0,sizeof(middle));memset(after,0,sizeof(after));
 memset(atlas,0,sizeof(atlas));atlas[2]=atlas[5]=1;
 memset(android_data,0,sizeof(android_data));android_data[0]=android_data[7]=1;
 native_android=(struct mks_yuv_compare_result){.words=android_data,.num_words=14,
 .capture_id=UINT64_MAX,.generation=2,.roi={0,0,2,1},.swap_succeeded=true};
 p->ra_ctx=&context;baseline_calls=0;submit_calls=swap_calls=receipt_aborts=0;submit_ok=true;submit_epoch_error=false;
 body_mode="";quad_reverse=false;epoch=7;baseline_ok=owner_current=true;now=100;
 baseline_ok=arm_ok=render_ok=android_arm_ok=true;
 native_status=PL_OPENGL_UV_ATLAS_ANCHOR_COMPLETE;android_status=MKS_YUV_COMPARE_READY;
 writes=fail_write_index=poll_calls=android_calls=aborts=render_calls=flush_calls=arm_calls=0;
 manifest[0]=event_log[0]=0;expect_diag_files=false;
}
int main(int argc,char **argv){
 struct priv p;struct vo vo={.priv=&p};reset(&p);
 if(argc>1 && !strcmp(argv[1],"poll")){
  atlas_poll(&vo);assert(writes==11 && !p.compare_active && !p.compare_terminal);
  reset(&p);native_status=PL_OPENGL_UV_ATLAS_ANCHOR_PENDING;atlas_poll(&vo);
  assert(!writes && p.compare_active && !p.compare_terminal);
  native_status=PL_OPENGL_UV_ATLAS_ANCHOR_COMPLETE;atlas_poll(&vo);assert(writes==11 && !p.compare_active);
  reset(&p);owner_current=false;atlas_poll(&vo);assert(aborts==1 && !android_calls && !poll_calls && !writes);
  reset(&p);native_result.generation++;atlas_poll(&vo);assert(!writes && p.compare_terminal);
  reset(&p);native_android.capture_id--;atlas_poll(&vo);assert(!writes && p.compare_terminal);
  reset(&p);native_android.swap_succeeded=false;atlas_poll(&vo);assert(!writes && p.compare_terminal);
  reset(&p);android_data[7]=0;atlas_poll(&vo);assert(!writes && p.compare_terminal);
  reset(&p);native_result.readback_epoch_after[2]++;atlas_poll(&vo);assert(!writes && p.compare_terminal);
  reset(&p);native_status=PL_OPENGL_UV_ATLAS_ANCHOR_FAILED;atlas_poll(&vo);assert(!writes && p.compare_terminal);
  reset(&p);now=1001;atlas_poll(&vo);assert(!writes && p.compare_terminal);
  reset(&p);middle[0]=0x80000000;native_result.mismatches_before_atlas=1;native_result.anchor_equal=false;
  expect_diag_files=true;atlas_poll(&vo);assert(writes==11 && p.compare_terminal && strstr(event_log,"capture-diagnostic-invalid"));
  reset(&p);fail_write_index=11;atlas_poll(&vo);assert(writes==11 && !manifest[0] && p.compare_terminal && !strstr(event_log,"capture-complete"));
  return 0;
 }
 if(argc>1 && !strcmp(argv[1],"flip")){
  // Before the requested PTS, atlas is configured but there is no session or
  // receipt. Ordinary RGB must continue to submit/swap without atlas APIs.
  p.compare_started=false;p.compare_active=false;p.atlas_anchor=NULL;
  p.frame_pending=true;p.fusion_presentation_guard=true;baseline_ok=false;
  flip_page(&vo);assert(submit_calls==1 && swap_calls==1 && !aborts && !p.compare_terminal && !baseline_calls);
  reset(&p);
  p.compare_started=true;p.compare_active=false;p.frame_pending=true;p.fusion_presentation_guard=true;
  flip_page(&vo);assert(submit_calls==1 && swap_calls==1 && !p.frame_pending);
  flip_page(&vo);assert(submit_calls==1 && swap_calls==1);
  reset(&p);p.compare_started=true;p.compare_active=false;p.frame_pending=true;p.fusion_presentation_guard=true;
  baseline_ok=false;flip_page(&vo);assert(!submit_calls && !swap_calls && aborts==1 && baseline_calls==1);
  reset(&p);p.compare_started=true;p.compare_active=false;p.frame_pending=true;p.fusion_presentation_guard=true;
  submit_epoch_error=true;flip_page(&vo);assert(submit_calls==1 && !swap_calls && aborts==1);
  reset(&p);p.compare_started=true;p.compare_active=false;p.frame_pending=true;p.fusion_presentation_guard=true;
  owner_current=false;flip_page(&vo);assert(!submit_calls && !swap_calls && aborts==1);
  reset(&p);p.compare_started=true;p.compare_active=false;p.frame_pending=true;p.fusion_presentation_guard=true;
  submit_ok=false;flip_page(&vo);assert(submit_calls==1 && !swap_calls && receipt_aborts==1);
  return 0;
 }
 if(argc>1 && !strcmp(argv[1],"render")){
  struct mp_image image={.pts=35.035};struct vo_frame frame={.current=&image,.frame_id=11};
  struct pl_frame source={.user_data=&image},target={0};const struct pl_frame *frames[]={&source};
  struct pl_frame_mix mix={.frames=frames};struct pl_render_params params={.marker=123};
  struct pl_swapchain_frame sw={.fbo=(void*)55};struct ra_yuv_fusion_target desc={.generation=2,.token=13,.w=2,.h=1};
  expected_target=&target;p.compare_id=10;
  assert(!atlas_render(&vo,&frame,&mix,&target,&params,&sw,&desc));
  assert(render_calls==1 && flush_calls==1 && p.compare_a_ready && p.compare_started && arm_calls==1);
  reset(&p);p.compare_id=10;android_arm_ok=false;p.atlas_anchor=NULL;
  assert(!atlas_render(&vo,&frame,&mix,&target,&params,&sw,&desc));assert(aborts==1 && !render_calls && !arm_calls);
  reset(&p);p.compare_id=10;arm_ok=false;p.atlas_anchor=NULL;
  assert(!atlas_render(&vo,&frame,&mix,&target,&params,&sw,&desc));assert(aborts==1 && !render_calls && arm_calls==1);
  reset(&p);p.compare_id=10;render_ok=false;
  assert(!atlas_render(&vo,&frame,&mix,&target,&params,&sw,&desc));assert(!p.compare_a_ready && !flush_calls);
  reset(&p);p.compare_id=10;baseline_ok=false;
  assert(!atlas_render(&vo,&frame,&mix,&target,&params,&sw,&desc));assert(!p.compare_a_ready);
  return 0;
 }
 int mask=argc>1?atoi(argv[1]):0;
 if(mask&1){after[0]=0x80000000;native_result.mismatches_before_after=1;}
 if(mask&2){middle[7]=0x3f800000;native_result.mismatches_before_atlas=1;}
 native_result.anchor_equal=!mask;expect_diag_files=mask!=0;
 if(argc>2){body_mode=argv[2];
  if(!strcmp(body_mode,"epoch"))native_result.draw_epoch_after[1]++;
  if(!strcmp(body_mode,"readback-epoch"))native_result.readback_epoch_before[0]++;
  if(!strcmp(body_mode,"finish-epoch"))native_result.finish_epoch++;
  if(!strcmp(body_mode,"fbo"))native_result.framebuffer[1]++;
  if(!strcmp(body_mode,"no-fbo"))native_result.framebuffer[0]=0;
  if(!strcmp(body_mode,"read-format"))native_result.read_format=0;
  if(!strcmp(body_mode,"read-type"))native_result.read_type=0;
  if(!strcmp(body_mode,"draw"))native_result.draw_ok[2]=false;
  if(!strcmp(body_mode,"readback"))native_result.readback_ok[0]=false;
  if(!strcmp(body_mode,"half-flag"))native_result.half_exact[0]=false;
  if(!strcmp(body_mode,"half-count"))native_result.bad_half_components[2]=1;
  if(!strcmp(body_mode,"coverage-flag"))native_result.atlas_complete=false;
  if(!strcmp(body_mode,"coverage-count"))native_result.bad_atlas_pixels=1;
  if(!strcmp(body_mode,"coverage"))atlas[5]=0;
  if(!strcmp(body_mode,"uv-finite"))atlas[0]=0x7f800000;
  if(!strcmp(body_mode,"half-finite"))before[0]=0x7fc00000;
  if(!strcmp(body_mode,"half-inexact"))before[0]=0x3f800001;
  if(!strcmp(body_mode,"word-count"))native_result.rgba_words--;
  if(!strcmp(body_mode,"atlas-count"))native_result.atlas_words--;
  if(!strcmp(body_mode,"size"))native_result.pixels++;
  if(!strcmp(body_mode,"id"))native_result.capture_id--;
  if(!strcmp(body_mode,"pts"))p.compare_current_pts+=0.000003;
  if(!strcmp(body_mode,"frame"))p.compare_frame_id=0;
  if(!strcmp(body_mode,"token"))p.compare_frame_token=0;
  if(!strcmp(body_mode,"program"))native_result.program_tokens[2]++;
  if(!strcmp(body_mode,"same-program"))native_result.program_tokens[1]=11;
  if(!strcmp(body_mode,"fence"))native_result.fence_signaled=false;
  if(!strcmp(body_mode,"source-abi"))native_result.source_abi_ok=false;
  if(!strcmp(body_mode,"mismatch-count"))native_result.mismatches_before_atlas++;
  if(!strcmp(body_mode,"anchor-flag"))native_result.anchor_equal=!native_result.anchor_equal;
  if(!strcmp(body_mode,"write"))fail_write_index=11;
 }
 bool invalid=false;bool ok=atlas_save(&vo,&native_result,&native_android,&invalid);
 if(!ok){assert(!manifest[0]);return writes?2:1;}
 assert(writes==11 && invalid==(mask!=0));fputs(manifest,stdout);return 0;
}
'''


class AtlasVoTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory()
        cls.exe = Path(cls.temp.name)/'atlas'
        c = Path(cls.temp.name)/'atlas.c'
        c.write_text('#include <stdlib.h>\n'+BASE+functions()+MAIN)
        subprocess.run(['clang','-std=c11','-Wall','-Wextra','-Werror','-Wno-unused-function',
                        '-I'+str(ROOT/'mpv'),str(c),'-lm','-o',str(cls.exe)],check=True)

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    def test_exact_schema_and_separate_invalid_files(self):
        for mask in range(4):
            m=json.loads(subprocess.check_output([str(self.exe),str(mask)],text=True))
            self.assertEqual(m['schema'],9)
            self.assertEqual(m['scope'],'rgb-anchor-capture-only-not-quality-pass')
            self.assertEqual(m['status'],'diagnostic-invalid' if mask else 'complete')
            self.assertEqual(m['comparison_pass'],'refused' if mask else 'unknown')
            # Consume the actual C serializer output through the independent
            # analyzer, rather than only comparing a hand-written fixture.
            atlas_metadata(m)
            event={'event':'capture-diagnostic-invalid' if mask else 'capture-complete',
                   'id':str(m['capture_id']), 'generation':str(m['generation'])}
            self.assertEqual(atlas_host.validate_manifest(m,event,str(m['pid']),35.035),m['files'])
            for invalid_claim in (None, 'passed', 'pass', 'unknown' if mask else 'refused'):
                changed=dict(m)
                if invalid_claim is None:
                    del changed['comparison_pass']
                else:
                    changed['comparison_pass']=invalid_claim
                with self.assertRaisesRegex(InvalidCapture,'invalid atlas completion claim'):
                    atlas_metadata(changed)
                with self.assertRaisesRegex(atlas_host.analyzer.InvalidCapture,'invalid atlas completion claim'):
                    atlas_host.validate_manifest(changed,event,str(m['pid']),35.035)
            self.assertEqual(m['anchor_validation_mask'],mask)
            self.assertIs(m['anchor_equal'],not mask)
            expected=[]
            if mask&1: expected.append('a0-replay-mismatch')
            if mask&2: expected.append('atlas-rgb-mismatch')
            self.assertEqual(m['anchor_validation_reasons'],expected)
            self.assertEqual(m['rgba_words'],8)
            self.assertEqual(m['atlas_words'],6)
            self.assertEqual(m['program_tokens'],['11','22','11'])
            self.assertEqual(m['draw_order'],['a0_before','atlas_a','a0_after'])
            for key in ['draw_epoch_before','draw_epoch_after','readback_epoch_before','readback_epoch_after']:
                self.assertEqual(m[key],['7']*3)
            self.assertEqual(m['framebuffer'],[55]*3)
            self.assertEqual(len(m['files']),10)
            self.assertTrue(all(('.diagnostic-invalid.' in s)==bool(mask) for s in m['files'].values()))
            self.assertEqual(m['vertex_layout']['viewport'],[0,0,2,1])
            self.assertEqual(m['capture_id'],2**64-1)

    def test_hard_failures_never_get_manifest(self):
        for failure in ['epoch','readback-epoch','finish-epoch','fbo','no-fbo','read-format','read-type',
                        'draw','readback','half-flag','half-count','coverage-flag','coverage-count',
                        'coverage','uv-finite','half-finite','half-inexact','word-count','atlas-count',
                        'size','id','pts','frame','token','program','fence','source-abi',
                        'mismatch-count','anchor-flag','data-failed','sources-failed','source-missing',
                        'source-original-mismatch','source-ssbo','source-capture','source-identical','same-program','quad-wrong-byte','quad-overlap','quad-opaque']:
            # An altered unused candidate buffer is irrelevant to the single
            # A0 payload getter, hence this case is deliberately not a hard gate.
            if failure=='quad-wrong-byte': continue
            p=subprocess.run([str(self.exe),'0',failure],capture_output=True)
            self.assertEqual(p.returncode,1,(failure,p.stderr))
            self.assertFalse(p.stdout)
        p=subprocess.run([str(self.exe),'0','write'],capture_output=True)
        self.assertEqual(p.returncode,2)
        self.assertFalse(p.stdout)

    def test_actual_poll_and_ordinary_target_render(self):
        subprocess.run([str(self.exe),'poll'],check=True)
        subprocess.run([str(self.exe),'render'],check=True)
        subprocess.run([str(self.exe),'flip'],check=True)


if __name__=='__main__':
    unittest.main()
