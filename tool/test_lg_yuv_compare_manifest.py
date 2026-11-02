"""Validate actual VO manifest formatting with CPU API doubles, not GPU evidence."""
from pathlib import Path
import json
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'mpv/video/out/vo_gpu_next.c'


def save_function():
    text = SOURCE.read_text()
    start = text.index('static bool compare_save(')
    return text[start:text.index('\nstatic void compare_poll(', start)]


def poll_function():
    text = SOURCE.read_text()
    start = text.index('static void compare_poll(')
    return text[start:text.index('\n}\n#endif',start)+2]


STUBS = r'''
#include <stdio.h>
#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <inttypes.h>
#include <string.h>
#include <unistd.h>
#include <stdarg.h>
#include "video/out/yuv_compare_vo.h"
#define PL_HAVE_MKS_YUV_COMPARE_REPEAT 1
#define PL_HAVE_MKS_YUV_COMPARE_SAMPLE_TAP 1
#define PL_HAVE_MKS_YUV_COMPARE_INVARIANT_B 1
#define PL_HAVE_MKS_YUV_COMPARE_UV_ORACLE 1
#define PL_HAVE_MKS_YUV_COMPARE_ORACLE_PROBE 1
#define PL_HAVE_MKS_YUV_COMPARE_ORACLE_SINGLE_PAIR 1
#define PL_HAVE_MKS_YUV_COMPARE_QUAD_ORDER 1
static char event_log[2048];
static void capture_log(const char *format,...) {
    va_list args;va_start(args,format);vsnprintf(event_log,sizeof(event_log),format,args);va_end(args);
}
#define MP_ERR(vo,...) capture_log(__VA_ARGS__)
struct priv {
    void *gpu, *fusion_target, *ra_ctx;
    uint32_t *compare_words,*compare_probe_words;
    size_t compare_num_words,compare_num_probe_words;
    bool compare_uv_probe,compare_uv_single,compare_quad_order,compare_quad_reverse,compare_active,compare_terminal;
    int64_t compare_deadline;
    bool compare_repeat, compare_epoch_valid, compare_sample_tap, compare_invariant_b, compare_uv_oracle, compare_uv_oracle_use_a;
    uint64_t compare_error_epoch, compare_id, compare_generation;
    uint64_t compare_frame_id, compare_frame_token;
    double compare_source_pts, compare_current_pts, compare_target_pts;
    int compare_width, compare_height, compare_x, compare_y, compare_w, compare_h;
};
struct vo { struct priv *priv; };
struct pl_opengl_yuv_compare_result {
    size_t words,uv_oracle_probe_words;
    bool uv_oracle_probe,uv_oracle_single_pair,quad_order,quad_order_reverse,candidate_ok,baseline_ok;
    uint64_t capture_id,generation;
    uint64_t shader_body_hash, program_tokens[4];
    unsigned repetitions, words_per_pixel, sample_sites;
    bool sample_tap;
    uint64_t sample_tap_body_hash;
    bool invariant_b;
    char invariant_uv_identifier[8];
    bool uv_oracle, uv_oracle_use_a;
    unsigned uv_oracle_barriers;
    bool uv_oracle_barrier_ok[2];
    uint64_t uv_oracle_barrier_epoch_before[2], uv_oracle_barrier_epoch_after[2];
    bool draw_ok[4];
    uint64_t draw_epoch_before[4], draw_epoch_after[4];
};
struct mks_yuv_compare_result {
 const uint32_t *words;size_t num_words;uint64_t capture_id,generation;
 struct {int x,y,w,h;} roi;bool swap_succeeded;
};
static const char *a0_vertex="#version 310 es\nout vec2 _uv;\nvoid main() {\n gl_Position=vec4(0);\n}\n";
static const char *b_vertex="#version 310 es\nout vec2 _uv;\ninvariant gl_Position;\ninvariant _uv;\nvoid main() {\n gl_Position=vec4(0);\n}\n";
static bool owner_current=true;
static bool compare_current(struct priv *p) { (void)p; return owner_current; }
static bool oracle_mode;
static bool pl_opengl_yuv_compare_sources(void *g, void *t, const char **b,
                                         const char **a, const char **v) {
    (void)g; (void)t; *b=oracle_mode?"B oracle modified source":"B tap body source"; *a="A tap body source"; *v=a0_vertex; return true;
}
static const char *body_mode="";
static bool pl_opengl_yuv_compare_bodies(void *g, void *t, const char **original,
                                        const char **tap) {
    (void)g; (void)t; *original="original body"; *tap="tap body";
    if (!strcmp(body_mode,"missing-original")) *original="";
    if (!strcmp(body_mode,"missing-tap")) *tap="";
    if (!strcmp(body_mode,"unrelated-tap")) *tap="unrelated body";
    return strcmp(body_mode,"bodies-failed")!=0;
}
static bool pl_opengl_yuv_compare_vertices(void *g, void *t, const char **b,
                                          const char **a0) {
    (void)g; (void)t; *b=b_vertex; *a0=a0_vertex;
    if (!strcmp(body_mode,"bad-vertex")) *b=a0_vertex;
    if (!strcmp(body_mode,"wrong-a0")) *a0="another vertex";
    return strcmp(body_mode,"vertices-failed")!=0;
}
enum { PL_PRIM_TRIANGLE_STRIP=1,PL_FMT_FLOAT=5 };
struct pl_opengl_yuv_compare_quad_attrib {
 char name[32],format_name[32],glsl_type[16];int fmt_type;bool opaque;int num_planes;
 int location,num_components,component_depth[4],host_bits[4],sample_order[4];size_t offset,texel_size;
};
struct pl_opengl_yuv_compare_quad_layout {
 int primitive;bool indexed;int vertex_count,num_attributes,position_attrib;size_t stride,byte_size;
 struct {int x0,y0,x1,y1;} viewport,scissors;
 struct pl_opengl_yuv_compare_quad_attrib attributes[16];
};
static bool quad_reverse;
static uint8_t quad_a[64],quad_b[64];
static bool pl_opengl_yuv_compare_quad_payloads(void *g,void *t,const uint8_t **a,const uint8_t **b,
 struct pl_opengl_yuv_compare_quad_layout *out) {
 (void)g;(void)t;
 uint32_t values[16]={0xbf800000,0xbf800000,0,0,0x3f800000,0xbf800000,0x3f800000,0,
  0xbf800000,0x3f800000,0,0x3f800000,0x3f800000,0x3f800000,0x3f800000,0x3f800000};
 memcpy(quad_a,values,sizeof(values));
 for(size_t i=0;i<4;i++)memcpy(quad_b+16*i,quad_a+16*(quad_reverse?3-i:i),16);
 *a=quad_a;*b=quad_b;
 *out=(struct pl_opengl_yuv_compare_quad_layout){.primitive=PL_PRIM_TRIANGLE_STRIP,
 .vertex_count=4,.num_attributes=2,.position_attrib=0,.stride=16,.byte_size=64,
 .viewport={0,0,2672,1336},.scissors={0,0,2672,1336},
 .attributes={{.name="position",.format_name="rg32f",.glsl_type="vec2",.fmt_type=PL_FMT_FLOAT,
  .location=0,.num_components=2,.component_depth={32,32},.host_bits={32,32},.sample_order={0,1,2,3},.offset=0,.texel_size=8},
 {.name="uv",.format_name="rg32f",.glsl_type="vec2",.fmt_type=PL_FMT_FLOAT,
  .location=1,.num_components=2,.component_depth={32,32},.host_bits={32,32},.sample_order={0,1,2,3},.offset=8,.texel_size=8}}};
 if(!strcmp(body_mode,"quad-getter-failed"))return false;
 if(!strcmp(body_mode,"quad-wrong-byte"))quad_b[15]^=1;
 if(!strcmp(body_mode,"quad-bad-count"))out->vertex_count=3;
 if(!strcmp(body_mode,"quad-indexed"))out->indexed=true;
 if(!strcmp(body_mode,"quad-bad-stride"))out->stride=0;
 if(!strcmp(body_mode,"quad-large-stride"))out->stride=1025;
 if(!strcmp(body_mode,"quad-bad-size"))out->byte_size--;
 if(!strcmp(body_mode,"quad-scissor"))out->scissors.x0=1;
 if(!strcmp(body_mode,"quad-viewport"))out->viewport.y1--;
 if(!strcmp(body_mode,"quad-no-position"))out->position_attrib=2;
 if(!strcmp(body_mode,"quad-too-many-attrs"))out->num_attributes=17;
 if(!strcmp(body_mode,"quad-no-attrs"))out->num_attributes=0;
 if(!strcmp(body_mode,"quad-overlap"))out->attributes[1].offset=4;
 if(!strcmp(body_mode,"quad-offset"))out->attributes[1].offset=16;
 if(!strcmp(body_mode,"quad-depth"))out->attributes[1].component_depth[0]=16;
 if(!strcmp(body_mode,"quad-host-bits"))out->attributes[1].host_bits[0]=16;
 if(!strcmp(body_mode,"quad-sample-order"))out->attributes[1].sample_order[0]=1;
 if(!strcmp(body_mode,"quad-location"))out->attributes[1].location=0;
 if(!strcmp(body_mode,"quad-type"))out->attributes[1].fmt_type=0;
 if(!strcmp(body_mode,"quad-opaque"))out->attributes[1].opaque=true;
 if(!strcmp(body_mode,"quad-planar"))out->attributes[1].num_planes=1;
 if(!strcmp(body_mode,"quad-name"))strcpy(out->attributes[1].name,"unsafe\\\"name");
 if(!strcmp(body_mode,"quad-format"))memset(out->attributes[1].format_name,'x',32);
 if(!strcmp(body_mode,"quad-glsl"))strcpy(out->attributes[1].glsl_type,"vec3");
 if(!strcmp(body_mode,"quad-texel"))out->attributes[1].texel_size=12;
 if(!strcmp(body_mode,"quad-nonfinite")) {uint32_t nan=0x7fc00000u;memcpy(quad_a,&nan,4);memcpy(quad_b+(quad_reverse?48:0),&nan,4);}
 return true;
}
static char manifest[16384];
static int writes,fail_write_index;
static bool expect_diag_files;
static bool compare_write_exclusive(const char *path, const void *data, size_t bytes) {
    writes++;
    assert((strstr(path,".diagnostic-invalid.")!=NULL)==expect_diag_files);
    if (writes==fail_write_index) return false;
    if (strstr(path,".baseline-vertices.bin"))assert(bytes==64 && !memcmp(data,quad_a,64));
    if (strstr(path,".candidate-vertices.bin"))assert(bytes==64 && !memcmp(data,quad_b,64));
    if (strstr(path,".json")) {
        if (bytes>=sizeof(manifest)) return false;
        memcpy(manifest,data,bytes); manifest[bytes]=0;
    }
    return true;
}
'''

MAIN = r'''
int main(int argc, char **argv) {
    if (argc>2) body_mode=argv[2];
    bool quad=argc>1 && (!strcmp(argv[1],"quad0") || !strcmp(argv[1],"quad1"));
    quad_reverse=quad && !strcmp(argv[1],"quad1");
    bool single=quad || (argc>1 && (!strcmp(argv[1],"single0") || !strcmp(argv[1],"single1")));
    bool probe_mode=single || (argc>1 && (!strcmp(argv[1],"probe0") || !strcmp(argv[1],"probe1")));
    bool oracle=probe_mode || (argc>1 && (!strcmp(argv[1],"oracle0") || !strcmp(argv[1],"oracle1")));
    bool use_a=oracle && (!strcmp(argv[1],"oracle1") || !strcmp(argv[1],"probe1") || !strcmp(argv[1],"single1"));
    oracle_mode=oracle;
    bool invariant=argc>1 && !strcmp(argv[1],"inv");
    bool tap=oracle || invariant || (argc>1 && !strcmp(argv[1],"tap"));
    bool repeat=tap || (argc>1 && !strcmp(argv[1],"repeat"));
    struct priv p={.compare_repeat=repeat,.compare_sample_tap=tap,.compare_invariant_b=invariant,.compare_uv_oracle=oracle,.compare_uv_oracle_use_a=use_a,.compare_uv_probe=probe_mode,.compare_uv_single=single,.compare_quad_order=quad,.compare_quad_reverse=quad_reverse,.compare_epoch_valid=true,
        .compare_error_epoch=7,.compare_id=UINT64_MAX,.compare_generation=2,
        .compare_frame_id=11,.compare_frame_token=13,.compare_source_pts=35.035,
        .compare_current_pts=35.035,.compare_target_pts=35.035,
        .compare_width=2672,.compare_height=1336,.compare_x=1304,.compare_y=636,
        .compare_w=64,.compare_h=64};
    uint32_t sidecar[1]={0};p.compare_probe_words=sidecar;
    p.compare_num_probe_words=4096*(single?10:20);
    struct vo vo={.priv=&p};
    struct pl_opengl_yuv_compare_result lib={.words=4096*(tap?26:14)*(repeat&&!single?2:1),
        .sample_tap=tap,.words_per_pixel=tap?26:14,.sample_sites=tap?1:0,
        .sample_tap_body_hash=UINT64_MAX,.invariant_b=invariant,.invariant_uv_identifier="_uv",
        .uv_oracle=oracle,.uv_oracle_use_a=use_a,.uv_oracle_barriers=2,
        .uv_oracle_probe=probe_mode,.uv_oracle_single_pair=single,.quad_order=quad,.quad_order_reverse=quad_reverse,.uv_oracle_probe_words=4096*(single?10:20),
        .uv_oracle_barrier_ok={true,true},.uv_oracle_barrier_epoch_before={7,7},
        .uv_oracle_barrier_epoch_after={7,7},
        .shader_body_hash=UINT64_MAX,.repetitions=repeat&&!single?2:1,
        .draw_ok={true,true,true,true},.program_tokens={UINT64_MAX,2,UINT64_MAX,2},
        .draw_epoch_before={7,7,7,7},.draw_epoch_after={7,7,7,7}};
    if(single) {
        lib.uv_oracle_barriers=1;lib.uv_oracle_barrier_ok[1]=false;
        lib.uv_oracle_barrier_epoch_before[1]=lib.uv_oracle_barrier_epoch_after[1]=0;
        for(int i=2;i<4;i++) {
            lib.draw_ok[i]=false;lib.program_tokens[i]=0;
            lib.draw_epoch_before[i]=lib.draw_epoch_after[i]=0;
        }
    }
    uint32_t android_words[1]={0};
    struct mks_yuv_compare_result android={.words=android_words,.num_words=4096*7};
    if (argc>2 && !strcmp(argv[2],"bad-token")) {if(single)lib.program_tokens[1]=0;else lib.program_tokens[2]--;}
    if (argc>2 && !strcmp(argv[2],"bad-epoch")) lib.draw_epoch_after[single?1:3]++;
    if (argc>2 && !strcmp(argv[2],"bad-site")) lib.sample_sites++;
    if (argc>2 && !strcmp(argv[2],"bad-stride")) lib.words_per_pixel=14;
    if (argc>2 && !strcmp(argv[2],"bad-uv")) memcpy(lib.invariant_uv_identifier,"no nul!!",8);
    if (argc>2 && !strcmp(argv[2],"wrong-mode")) lib.invariant_b=false;
    if (argc>2 && !strcmp(argv[2],"bad-oracle-mode")) lib.uv_oracle_use_a=!use_a;
    if (argc>2 && !strcmp(argv[2],"bad-barrier-count")) lib.uv_oracle_barriers=single?2:1;
    if (argc>2 && !strcmp(argv[2],"bad-barrier-ok")) lib.uv_oracle_barrier_ok[single?0:1]=false;
    if (argc>2 && !strcmp(argv[2],"bad-barrier-epoch")) lib.uv_oracle_barrier_epoch_after[0]++;
    if (argc>2 && !strcmp(argv[2],"wrong-single-mode")) lib.uv_oracle_single_pair=false;
    if (argc>2 && !strcmp(argv[2],"quad-wrong-mode"))lib.quad_order_reverse=!quad_reverse;
    if (argc>2 && !strcmp(argv[2],"quad-wrong-framework"))lib.quad_order=false;
    if (argc>2 && !strcmp(argv[2],"quad-use-a"))p.compare_uv_oracle_use_a=lib.uv_oracle_use_a=true;
    uint32_t mask=0;
    if (argc>2 && !strcmp(argv[2],"diag")) mask=1;
    if (argc>2 && !strcmp(argv[2],"diag-all")) mask=127;
    if (argc>2 && !strcmp(argv[2],"bad-mask")) mask=128;
    if (argc>2 && !strcmp(argv[2],"missing-probe")) p.compare_probe_words=NULL;
    if (argc>2 && !strcmp(argv[2],"bad-probe-size")) lib.uv_oracle_probe_words--;
    if (argc>2 && !strcmp(argv[2],"wrong-probe-mode")) lib.uv_oracle_probe=false;
    expect_diag_files=mask!=0;
    bool ok=compare_save(&vo,&lib,&android,mask);
    if (!ok) return writes ? 2 : 1;
    if (writes!=(quad?10:(invariant||probe_mode)?8:tap?7:6)) return 3;
    assert(strstr(event_log,mask?"event=capture-diagnostic-invalid ":"event=capture-complete "));
    assert(!mask || !strstr(event_log,"event=capture-complete "));
    fputs(manifest,stdout);
    return 0;
}
'''


POLL_STUBS = r"""
enum {PL_OPENGL_YUV_COMPARE_FAILED=-1,PL_OPENGL_YUV_COMPARE_PENDING=0,
      PL_OPENGL_YUV_COMPARE_COMPLETE=1,MKS_YUV_COMPARE_FAILED=-1,MKS_YUV_COMPARE_READY=2};
static uint32_t raw_base[104],raw_probe[40],raw_android[14],out_base[104],out_probe[40];
static struct pl_opengl_yuv_compare_result native_lib;
static struct mks_yuv_compare_result native_android;
static int lib_status,android_status,probe_status,a_calls,l_calls,p_calls,aborts;
static int64_t mp_time_ns(void) { return 100; }
static void compare_fail_transaction(struct vo *vo,const char *reason) {
 (void)reason;aborts++;vo->priv->compare_active=false;vo->priv->compare_terminal=true;
}
static int mks_android_yuv_compare_poll(void *ctx,struct mks_yuv_compare_result *out) {
 (void)ctx;a_calls++;*out=native_android;return android_status;
}
static int pl_opengl_yuv_compare_poll(void *gpu,void *target,uint32_t *words,size_t cap,
                                     struct pl_opengl_yuv_compare_result *out) {
 (void)gpu;(void)target;l_calls++;assert(cap>=native_lib.words);memcpy(words,raw_base,native_lib.words*sizeof(*words));
 *out=native_lib;return lib_status;
}
static int pl_opengl_yuv_compare_probe_poll(void *gpu,void *target,uint32_t *words,size_t cap) {
 (void)gpu;(void)target;p_calls++;
 if(cap<native_lib.uv_oracle_probe_words)return PL_OPENGL_YUV_COMPARE_FAILED;
 memcpy(words,raw_probe,native_lib.uv_oracle_probe_words*sizeof(*words));return probe_status;
}
static void reset_poll(struct priv *p) {
 *p=(struct priv){.fusion_target=(void*)1,.compare_repeat=true,.compare_sample_tap=true,
  .compare_uv_oracle=true,.compare_uv_oracle_use_a=true,.compare_uv_probe=true,
  .compare_epoch_valid=true,.compare_error_epoch=7,.compare_id=7,.compare_generation=2,
  .compare_frame_id=11,.compare_frame_token=13,.compare_source_pts=35.035,
  .compare_current_pts=35.035,.compare_target_pts=35.035,.compare_width=32,.compare_height=16,
  .compare_x=2,.compare_y=2,.compare_w=2,.compare_h=1,.compare_active=true,.compare_deadline=1000,
  .compare_words=out_base,.compare_num_words=104,.compare_probe_words=out_probe,.compare_num_probe_words=40};
 native_lib=(struct pl_opengl_yuv_compare_result){.words=104,.uv_oracle_probe_words=40,
  .uv_oracle_probe=true,.candidate_ok=true,.baseline_ok=true,.capture_id=7,.generation=2,
  .repetitions=2,.draw_ok={true,true,true,true},.program_tokens={11,22,11,22},
  .draw_epoch_before={7,7,7,7},.draw_epoch_after={7,7,7,7},.sample_tap=true,
  .words_per_pixel=26,.sample_sites=1,.sample_tap_body_hash=234,.shader_body_hash=123,
  .uv_oracle=true,.uv_oracle_use_a=true,.uv_oracle_barriers=2,
  .uv_oracle_barrier_ok={true,true},.uv_oracle_barrier_epoch_before={7,7},
  .uv_oracle_barrier_epoch_after={7,7}};
 native_android=(struct mks_yuv_compare_result){.words=raw_android,.num_words=14,
  .capture_id=7,.generation=2,.roi={2,2,2,1},.swap_succeeded=true};
 memset(raw_base,0,sizeof(raw_base));memset(raw_probe,0,sizeof(raw_probe));
 memset(raw_android,0,sizeof(raw_android));raw_android[0]=raw_android[7]=1;
 for(int i=0;i<4;i++) {
  int b=i*26,r=i*10;
  raw_base[b]=raw_base[b+10]=raw_base[b+19]=raw_base[b+25]=1;
  raw_base[b+14]=raw_base[b+20]=0x3f000000u;
  raw_base[b+15]=raw_base[b+21]=0x3e800000u;
  raw_probe[r]=raw_probe[r+1]=raw_probe[r+2]=raw_probe[r+3]=raw_probe[r+4]=1;
  raw_probe[r+5]=raw_base[b+20];raw_probe[r+6]=raw_base[b+21];raw_probe[r+8]=raw_probe[r+9]=1;
 }
 writes=fail_write_index=a_calls=l_calls=p_calls=aborts=0;
 manifest[0]=event_log[0]=0;expect_diag_files=false;owner_current=oracle_mode=true;body_mode="";
 lib_status=probe_status=PL_OPENGL_YUV_COMPARE_COMPLETE;android_status=MKS_YUV_COMPARE_READY;
}
static void reset_quad_poll(struct priv *p,bool reverse) {
 reset_poll(p);p->compare_uv_single=true;p->compare_num_words=52;p->compare_num_probe_words=20;
 p->compare_uv_oracle_use_a=false;p->compare_quad_order=true;p->compare_quad_reverse=reverse;
 p->compare_width=2672;p->compare_height=1336;quad_reverse=reverse;
 native_lib.uv_oracle_single_pair=true;native_lib.repetitions=1;native_lib.words=52;
 native_lib.uv_oracle_probe_words=20;native_lib.uv_oracle_barriers=1;
 native_lib.uv_oracle_use_a=false;native_lib.quad_order=true;native_lib.quad_order_reverse=reverse;
 raw_probe[9]=raw_probe[19]=0;
}
"""

POLL_TEST = r"""
int main(void) {
 struct priv p;struct vo vo={.priv=&p};
 reset_poll(&p);compare_poll(&vo);
 assert(writes==8 && !p.compare_active && !p.compare_terminal);
 assert(strstr(event_log,"event=capture-complete ") && strstr(manifest,"\"status\":\"complete\""));
 reset_poll(&p);raw_probe[3]=0;raw_probe[7]=2;raw_probe[8]=0;raw_probe[9]=2;raw_base[19]=0;
 expect_diag_files=true;compare_poll(&vo);
 assert(writes==8 && !p.compare_active && p.compare_terminal);
 assert(strstr(event_log,"event=capture-diagnostic-invalid ") && !strstr(event_log,"event=capture-complete "));
 assert(strstr(manifest,"\"status\":\"diagnostic-invalid\"") && strstr(manifest,"\"oracle_cpu_validation_mask\":1,"));
 reset_poll(&p);raw_probe[7]=2;expect_diag_files=true;compare_poll(&vo);
 assert(writes==8 && p.compare_terminal && strstr(manifest,"\"oracle_cpu_validation_mask\":7,"));
 reset_poll(&p);raw_probe[22]=0;compare_poll(&vo);
 assert(!writes && p.compare_terminal && strstr(event_log,"event=capture-failed ") && strstr(event_log,"bad_probe_word=20"));
 reset_poll(&p);raw_android[7]=0;compare_poll(&vo);
 assert(!writes && p.compare_terminal && strstr(event_log,"bad_android_word=7"));
 reset_poll(&p);native_lib.capture_id++;compare_poll(&vo);
 assert(!writes && p.compare_terminal && strstr(event_log,"identities=0"));
 reset_poll(&p);lib_status=PL_OPENGL_YUV_COMPARE_PENDING;compare_poll(&vo);
 assert(!writes && p.compare_active && !p.compare_terminal && !p_calls);
 reset_poll(&p);probe_status=PL_OPENGL_YUV_COMPARE_PENDING;compare_poll(&vo);
 assert(!writes && p.compare_active && !p.compare_terminal && p_calls==1);
 probe_status=PL_OPENGL_YUV_COMPARE_COMPLETE;compare_poll(&vo);
 assert(writes==8 && !p.compare_active && !p.compare_terminal && p_calls==2);
 reset_poll(&p);probe_status=PL_OPENGL_YUV_COMPARE_FAILED;compare_poll(&vo);
 assert(!writes && p.compare_terminal && strstr(event_log,"event=capture-failed "));
 reset_poll(&p);native_lib.draw_epoch_before[2]++;compare_poll(&vo);
 assert(!writes && p.compare_terminal);
 reset_poll(&p);owner_current=false;compare_poll(&vo);
 assert(aborts==1 && !writes && !a_calls && !l_calls && !p_calls && p.compare_terminal);
 reset_poll(&p);p.compare_uv_probe=false;native_lib.uv_oracle_probe=false;native_lib.uv_oracle_probe_words=0;
 raw_base[19]=0;compare_poll(&vo);
 assert(!writes && !p_calls && p.compare_terminal && strstr(event_log,"event=capture-failed "));
 reset_poll(&p);fail_write_index=8;compare_poll(&vo);
 assert(writes==8 && !manifest[0] && p.compare_terminal && strstr(event_log,"event=capture-failed "));
 assert(!strstr(event_log,"event=capture-complete "));
 reset_poll(&p);p.compare_uv_single=true;p.compare_num_words=52;p.compare_num_probe_words=20;
 native_lib.uv_oracle_single_pair=true;native_lib.repetitions=1;native_lib.words=52;
 native_lib.uv_oracle_probe_words=20;native_lib.uv_oracle_barriers=1;
 native_lib.uv_oracle_barrier_ok[1]=false;
 for(int i=2;i<4;i++) {native_lib.draw_ok[i]=false;native_lib.program_tokens[i]=0;}
 compare_poll(&vo);
 assert(writes==8 && !p.compare_terminal && strstr(manifest,"\"schema\":7"));
 assert(strstr(manifest,"\"programs_reused\":false") && strstr(manifest,"\"draw_order\":[\"A1\",\"B1\"]"));
 reset_poll(&p);p.compare_uv_single=true;p.compare_num_words=52;p.compare_num_probe_words=20;
 native_lib.uv_oracle_single_pair=true;native_lib.repetitions=1;native_lib.words=52;
 native_lib.uv_oracle_probe_words=20;native_lib.uv_oracle_barriers=1;
 raw_probe[3]=0;raw_probe[7]=2;raw_probe[8]=0;raw_probe[9]=2;raw_base[19]=0;
 expect_diag_files=true;compare_poll(&vo);
 assert(writes==8 && p.compare_terminal && strstr(manifest,"\"schema\":7"));
 assert(strstr(event_log,"event=capture-diagnostic-invalid "));
 reset_poll(&p);p.compare_uv_single=true;p.compare_num_words=52;p.compare_num_probe_words=20;
 native_lib.uv_oracle_single_pair=true;native_lib.repetitions=1;native_lib.words=52;
 native_lib.uv_oracle_probe_words=20;native_lib.uv_oracle_barriers=2;compare_poll(&vo);
 assert(!writes && p.compare_terminal); // single mode cannot grant a two-barrier receipt
 for(int rev=0;rev<2;rev++) {
  reset_quad_poll(&p,rev);compare_poll(&vo);
  assert(writes==10 && !p.compare_terminal && strstr(manifest,"\"schema\":8"));
  assert(strstr(event_log,"quad_order=1") && strstr(event_log,rev?"quad_order_reverse=1":"quad_order_reverse=0"));
  reset_quad_poll(&p,rev);raw_probe[3]=0;raw_probe[7]=2;raw_probe[8]=0;raw_probe[9]=2;raw_base[19]=0;
  expect_diag_files=true;compare_poll(&vo);
  assert(writes==10 && p.compare_terminal && strstr(event_log,"event=capture-diagnostic-invalid "));
  reset_quad_poll(&p,rev);body_mode="quad-wrong-byte";compare_poll(&vo);
  assert(!writes && p.compare_terminal && strstr(event_log,"event=capture-failed "));
  reset_quad_poll(&p,rev);native_lib.quad_order_reverse=!rev;compare_poll(&vo);
  assert(!writes && p.compare_terminal);
  reset_quad_poll(&p,rev);fail_write_index=10;compare_poll(&vo);
  assert(writes==10 && !manifest[0] && p.compare_terminal && !strstr(event_log,"event=capture-complete "));
 }
 return 0;
}
"""


class ManifestTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not shutil.which('clang'):
            raise unittest.SkipTest('clang unavailable')
        cls.temp = tempfile.TemporaryDirectory()
        cls.exe = Path(cls.temp.name) / 'manifest'
        c = Path(cls.temp.name) / 'manifest.c'
        c.write_text(STUBS + save_function() + MAIN)
        subprocess.run(['clang','-std=c11','-Wall','-Wextra','-Werror',
                        '-I'+str(ROOT/'mpv'),str(c),'-lm','-o',str(cls.exe)],check=True)

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    def run_manifest(self, *args):
        return json.loads(subprocess.check_output([str(self.exe),*args],text=True))

    def test_actual_poll_hard_gates_and_invalid_terminal(self):
        c=Path(self.temp.name)/'poll.c'
        exe=Path(self.temp.name)/'poll'
        c.write_text(STUBS+save_function()+POLL_STUBS+poll_function()+POLL_TEST)
        subprocess.run(['clang','-std=c11','-Wall','-Wextra','-Werror',
                        '-I'+str(ROOT/'mpv'),str(c),'-lm','-o',str(exe)],check=True)
        subprocess.run([str(exe)],check=True)

    def test_single_schema_unchanged(self):
        m=self.run_manifest()
        self.assertEqual(m['schema'],1)
        self.assertNotIn('repetitions',m)
        self.assertNotIn('draw_epoch_before',m)
        self.assertEqual(m['lib_words'],4096*14)
        self.assertEqual(m['android_words'],4096*7)

    def test_repeat_schema_and_exact_strings(self):
        m=self.run_manifest('repeat')
        self.assertEqual(m['schema'],2)
        self.assertEqual(m['repetitions'],2)
        self.assertEqual(m['draw_order'],['B1','A1','B2','A2'])
        self.assertEqual(m['draw_ok'],dict.fromkeys(['B1','A1','B2','A2'],True))
        self.assertEqual(m['program_tokens'],[str(2**64-1),'2',str(2**64-1),'2'])
        self.assertEqual(m['draw_epoch_before'],['7']*4)
        self.assertEqual(m['draw_epoch_after'],['7']*4)
        self.assertTrue(m['same_input_snapshot'])
        self.assertTrue(m['programs_reused'])
        self.assertEqual(m['assertion_scope'],'same frozen renderer input state and resource handles; no texture pixel hash')
        self.assertEqual(m['lib_words'],4096*14*2)
        self.assertEqual(m['android_words'],4096*7)
        self.assertEqual(m['source_pts'],m['current_pts'])
        self.assertEqual(m['current_pts'],m['target_pts'])
        self.assertGreater(m['frame_id'],0)
        self.assertGreater(m['frame_token'],0)
        self.assertEqual(len(m['files']),5)
        self.assertTrue(all('/' not in name for name in m['files'].values()))

    def test_tap_schema_uses_actual_instrumented_scope(self):
        m=self.run_manifest('tap')
        self.assertEqual(m['schema'],3)
        self.assertEqual(m['repetitions'],2)
        self.assertIs(m['sample_tap'],True)
        self.assertEqual(m['sample_tap_site_count'],1)
        self.assertEqual(m['words_per_pixel'],26)
        self.assertEqual(m['lib_words'],4096*26*2)
        self.assertEqual(len(m['files']),6)
        self.assertTrue(m['files']['original_body'].endswith('.original-body.glsl'))
        self.assertEqual(m['android_words'],4096*7)
        self.assertEqual(m['sample_tap_body_hash'],str(2**64-1))
        self.assertEqual(m['shader_body_hash'],str(2**64-1))
        self.assertEqual(m['instrumentation_scope'],'actual single textureLod site UV and sampled RGB; instrumentation may change shader compilation; not an unmodified shader')
        for mode in ['bad-site','bad-stride','bad-token','bad-epoch',
                     'missing-original','missing-tap','unrelated-tap','bodies-failed']:
            result=subprocess.run([str(self.exe),'tap',mode],capture_output=True)
            self.assertEqual(result.returncode,1)
            self.assertFalse(result.stdout)

    def test_b_only_invariant_schema_and_separate_vertices(self):
        m=self.run_manifest('inv')
        self.assertEqual(m['schema'],4)
        self.assertIs(m['invariant_b'],True)
        self.assertEqual(m['invariant_uv_identifier'],'_uv')
        self.assertEqual(m['draw_order'],['B1','A01','B2','A02'])
        self.assertEqual(m['draw_ok'],dict.fromkeys(['B1','A01','B2','A02'],True))
        self.assertEqual(len(m['files']),7)
        self.assertTrue(m['files']['candidate_vertex'].endswith('.candidate-vertex.glsl'))
        self.assertTrue(m['files']['vertex'].endswith('.vertex.glsl'))
        self.assertEqual(m['words_per_pixel'],26)
        self.assertEqual(m['lib_words'],4096*26*2)
        self.assertEqual(m['android_words'],4096*7)
        for mode in ['bad-vertex','wrong-a0','vertices-failed','bad-uv','wrong-mode',
                     'missing-original','bad-site','bad-token','bad-epoch']:
            result=subprocess.run([str(self.exe),'inv',mode],capture_output=True)
            self.assertEqual(result.returncode,1)
            self.assertFalse(result.stdout)

    def test_oracle_framework_uniform_modes_and_barriers(self):
        for mode,use_a in [('oracle0',False),('oracle1',True)]:
            m=self.run_manifest(mode)
            self.assertEqual(m['schema'],5)
            self.assertIs(m['uv_oracle'],True)
            self.assertIs(m['uv_oracle_use_a'],use_a)
            self.assertEqual(m['uv_oracle_barriers'],2)
            self.assertEqual(m['uv_oracle_barrier_ok'],[True,True])
            self.assertEqual(m['uv_oracle_barrier_epoch_before'],['7','7'])
            self.assertEqual(m['uv_oracle_barrier_epoch_after'],['7','7'])
            self.assertEqual(m['draw_order'],['A1','B1','A2','B2'])
            self.assertEqual(m['draw_ok'],dict.fromkeys(['A1','B1','A2','B2'],True))
            self.assertEqual(len(m['files']),6)
            self.assertNotIn('candidate_vertex',m['files'])
            self.assertNotIn('invariant_b',m)
            self.assertEqual(m['lib_words'],4096*26*2)
            self.assertEqual(m['android_words'],4096*7)
            for failure in ['bad-oracle-mode','bad-barrier-count','bad-barrier-ok',
                            'bad-barrier-epoch','bad-token','bad-epoch','missing-tap']:
                result=subprocess.run([str(self.exe),mode,failure],capture_output=True)
                self.assertEqual(result.returncode,1)
                self.assertFalse(result.stdout)

    def test_probe_complete_and_separate_invalid_evidence(self):
        for mode in ['probe0','probe1']:
            m=self.run_manifest(mode)
            self.assertEqual(m['schema'],6)
            self.assertEqual(m['status'],'complete')
            self.assertTrue(m['uv_oracle_probe'])
            self.assertEqual(m['uv_oracle_probe_words'],4096*20)
            self.assertEqual(m['uv_oracle_probe_words_per_pixel'],10)
            self.assertEqual(m['uv_oracle_probe_status'],'complete')
            self.assertTrue(m['oracle_preconditions_valid'])
            self.assertEqual(m['oracle_cpu_validation_mask'],0)
            self.assertEqual(m['oracle_cpu_validation_reasons'],[])
            self.assertEqual(len(m['files']),7)
            self.assertTrue(m['files']['oracle_probe'].endswith('.oracle-probe.bin'))
            diag=self.run_manifest(mode,'diag')
            self.assertEqual(diag['status'],'diagnostic-invalid')
            self.assertFalse(diag['oracle_preconditions_valid'])
            self.assertEqual(diag['oracle_cpu_validation_mask'],1)
            self.assertEqual(diag['oracle_cpu_validation_reasons'],['gpu-dependency-invalid'])
            self.assertTrue(all('.diagnostic-invalid.' in name for name in diag['files'].values()))
            self.assertTrue(all('.diagnostic-invalid.' not in name for name in m['files'].values()))
            for failure in ['missing-probe','bad-probe-size','wrong-probe-mode','bad-mask','bad-epoch']:
                r=subprocess.run([str(self.exe),mode,failure],capture_output=True)
                self.assertEqual(r.returncode,1)
                self.assertFalse(r.stdout)
        diag=self.run_manifest('probe1','diag-all')
        self.assertEqual(diag['oracle_cpu_validation_reasons'],['gpu-dependency-invalid',
            'reason-mismatch','dependency-flag-mismatch','selected-source-mismatch',
            'base-site-mismatch','observed-a-uv-mismatch','selected-a-uv-mismatch'])
        r=subprocess.run([str(self.exe),'oracle1','diag'],capture_output=True)
        self.assertEqual(r.returncode,1)

    def test_single_pair_schema_has_only_active_receipts(self):
        for mode in ['single0','single1']:
            m=self.run_manifest(mode)
            self.assertEqual(m['schema'],7)
            self.assertTrue(m['uv_oracle_single_pair'])
            self.assertEqual(m['repetitions'],1)
            self.assertEqual(m['draw_order'],['A1','B1'])
            self.assertEqual(m['draw_ok'],dict.fromkeys(['A1','B1'],True))
            self.assertFalse(m['programs_reused'])
            self.assertEqual(len(m['program_tokens']),2)
            self.assertEqual(m['draw_epoch_before'],['7','7'])
            self.assertEqual(m['draw_epoch_after'],['7','7'])
            self.assertEqual(m['uv_oracle_barriers'],1)
            self.assertEqual(m['uv_oracle_barrier_ok'],[True])
            self.assertEqual(m['uv_oracle_barrier_epoch_before'],['7'])
            self.assertEqual(m['uv_oracle_barrier_epoch_after'],['7'])
            self.assertEqual(m['lib_words'],4096*26)
            self.assertEqual(m['uv_oracle_probe_words'],4096*10)
            self.assertEqual(m['android_words'],4096*7)
            self.assertEqual(len(m['files']),7)
            diag=self.run_manifest(mode,'diag')
            self.assertEqual(diag['schema'],7)
            self.assertEqual(diag['status'],'diagnostic-invalid')
            self.assertTrue(all('.diagnostic-invalid.' in n for n in diag['files'].values()))
            for bad in ['bad-token','bad-epoch','bad-barrier-count','bad-barrier-ok',
                        'bad-barrier-epoch','wrong-single-mode','bad-probe-size']:
                r=subprocess.run([str(self.exe),mode,bad],capture_output=True)
                self.assertEqual(r.returncode,1)
                self.assertFalse(r.stdout)

    def test_quad_schema_archives_exact_payload_and_layout(self):
        for mode, reverse in [('quad0', False), ('quad1', True)]:
            m=self.run_manifest(mode)
            self.assertEqual(m['schema'],8)
            self.assertTrue(m['quad_order'])
            self.assertIs(m['quad_order_reverse'],reverse)
            self.assertFalse(m['uv_oracle_use_a'])
            self.assertTrue(m['uv_oracle_single_pair'])
            self.assertEqual(m['draw_order'],['A1','B1'])
            self.assertFalse(m['programs_reused'])
            self.assertEqual(len(m['files']),9)
            self.assertTrue(m['files']['baseline_vertices'].endswith('.baseline-vertices.bin'))
            self.assertTrue(m['files']['candidate_vertices'].endswith('.candidate-vertices.bin'))
            q=m['quad_vertex_layout']
            self.assertEqual(q['primitive'],'triangle_strip')
            self.assertFalse(q['indexed'])
            self.assertEqual(q['vertex_count'],4)
            self.assertEqual(q['stride'],16)
            self.assertEqual(q['byte_size'],64)
            self.assertEqual(q['num_attributes'],2)
            self.assertEqual(q['position_attrib'],0)
            self.assertEqual(q['viewport'],[0,0,2672,1336])
            self.assertEqual(q['scissors'],q['viewport'])
            self.assertEqual([a['offset'] for a in q['attributes']],[0,8])
            for a in q['attributes']:
                self.assertEqual(a['host_bits'],[32,32,0,0])
                self.assertEqual(a['sample_order'],[0,1,2,3])
                self.assertEqual(a['fmt_type'],'float32')
                self.assertFalse(a['opaque'])
                self.assertEqual(a['num_planes'],0)
            diag=self.run_manifest(mode,'diag')
            self.assertEqual(diag['schema'],8)
            self.assertEqual(diag['status'],'diagnostic-invalid')
            self.assertTrue(all('.diagnostic-invalid.' in name for name in diag['files'].values()))
            for bad in ['quad-getter-failed','quad-wrong-byte','quad-bad-count','quad-indexed',
                        'quad-bad-stride','quad-large-stride','quad-bad-size','quad-scissor',
                        'quad-viewport','quad-no-position','quad-too-many-attrs','quad-no-attrs',
                        'quad-overlap','quad-offset','quad-depth','quad-host-bits','quad-sample-order',
                        'quad-location','quad-type','quad-opaque','quad-planar','quad-name','quad-format','quad-glsl',
                        'quad-texel','quad-nonfinite','quad-wrong-mode','quad-wrong-framework',
                        'quad-use-a','bad-epoch','bad-barrier-count','wrong-single-mode']:
                r=subprocess.run([str(self.exe),mode,bad],capture_output=True)
                self.assertEqual(r.returncode,1,(mode,bad,r.stderr))
                self.assertFalse(r.stdout)

    def test_failed_draw_identity_writes_nothing(self):
        for mode in ['bad-token','bad-epoch']:
            result=subprocess.run([str(self.exe),'repeat',mode],capture_output=True)
            self.assertEqual(result.returncode,1)
            self.assertFalse(result.stdout)


if __name__ == '__main__':
    unittest.main()
