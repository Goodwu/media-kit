"""Joint contract: real schema10 VO serializer plus real source builders vs analyzer.

The harness compiles the actual yuv_atlas_read_impl.h functions and the actual
schema9 serializer extracted from vo_gpu_next.c with CPU API doubles and the
real libplacebo B0/probe source builders, archives real files, and the
independent analyzer re-derives every number. Host evidence only; not device,
GPU, YUV, panel or production proof.
"""
from pathlib import Path
import json
import re
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'mpv/video/out/vo_gpu_next.c'
PLACEBO = ROOT / 'libplacebo/src'
sys.path.insert(0, str(Path(__file__).parent))
from tool.analyze_lg_yuv_capture import analyze, validate_atlas_read_pair

SEED_NONCE = '0123456789abcdef0123456789abcdef'


def schema9_functions():
    text = SOURCE.read_text()
    start = text.index('static bool atlas_result_valid(')
    end = text.index('\n#endif\n\nstatic bool compare_save(', start)
    return text[start:end]


SHA = r'''
/* Compact SHA-256 standing in for libavutil; only the digest is contracted. */
struct AVSHA { unsigned int state[8]; unsigned long long bits; unsigned char buf[64]; size_t len; };
static const unsigned int sha_k[64]={
0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2};
#define ROR(x,n) (((x)>>(n))|((x)<<(32-(n))))
static void sha_block(struct AVSHA *s,const unsigned char *p){
 unsigned int w[64],a,b,c,d,e,f,g,h,t1,t2;int i;
 for(i=0;i<16;i++)w[i]=(unsigned)p[i*4]<<24|(unsigned)p[i*4+1]<<16|(unsigned)p[i*4+2]<<8|p[i*4+3];
 for(i=16;i<64;i++){unsigned s0=ROR(w[i-15],7)^ROR(w[i-15],18)^(w[i-15]>>3);
  unsigned s1=ROR(w[i-2],17)^ROR(w[i-2],19)^(w[i-2]>>10);w[i]=w[i-16]+s0+w[i-7]+s1;}
 a=s->state[0];b=s->state[1];c=s->state[2];d=s->state[3];e=s->state[4];f=s->state[5];
 g=s->state[6];h=s->state[7];
 for(i=0;i<64;i++){unsigned S1=ROR(e,6)^ROR(e,11)^ROR(e,25);unsigned ch=(e&f)^(~e&g);
  t1=h+S1+ch+sha_k[i]+w[i];unsigned S0=ROR(a,2)^ROR(a,13)^ROR(a,22);
  unsigned mj=(a&b)^(a&c)^(b&c);t2=S0+mj;h=g;g=f;f=e;e=d+t1;d=c;c=b;b=a;a=t1+t2;}
 s->state[0]+=a;s->state[1]+=b;s->state[2]+=c;s->state[3]+=d;
 s->state[4]+=e;s->state[5]+=f;s->state[6]+=g;s->state[7]+=h;}
static struct AVSHA *av_sha_alloc(void){return calloc(1,sizeof(struct AVSHA));}
static int av_sha_init(struct AVSHA *s,int bits){
 if(!s||bits!=256)return -1;
 s->state[0]=0x6a09e667;s->state[1]=0xbb67ae85;s->state[2]=0x3c6ef372;s->state[3]=0xa54ff53a;
 s->state[4]=0x510e527f;s->state[5]=0x9b05688c;s->state[6]=0x1f83d9ab;s->state[7]=0x5be0cd19;
 s->bits=0;s->len=0;return 0;}
static void av_sha_update(struct AVSHA *s,const void *data,size_t n){
 const unsigned char *p=data;s->bits+=(unsigned long long)n*8;
 while(n){size_t room=64-s->len;size_t take=n<room?n:room;
  memcpy(s->buf+s->len,p,take);s->len+=take;p+=take;n-=take;
  if(s->len==64){sha_block(s,s->buf);s->len=0;}}}
static void av_sha_final(struct AVSHA *s,unsigned char *out){
 unsigned long long bits=s->bits;unsigned char pad=0x80;int i;
 av_sha_update(s,&pad,1);pad=0;
 while(s->len!=56)av_sha_update(s,&pad,1);
 for(i=7;i>=0;i--){unsigned char b=(unsigned char)(bits>>(8*i));av_sha_update(s,&b,1);}
 for(i=0;i<8;i++){out[i*4]=s->state[i]>>24;out[i*4+1]=s->state[i]>>16;
  out[i*4+2]=s->state[i]>>8;out[i*4+3]=s->state[i];}}
static void av_free(void *p){free(p);}
'''

BASE = r'''
#include <stdio.h>
#include <stdlib.h>
#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <inttypes.h>
#include <string.h>
#include <unistd.h>
#include <stdarg.h>
#include <fcntl.h>
#include <math.h>
#include <errno.h>
''' + SHA + r'''
#include "video/out/yuv_atlas_read.h"
#include "atlas_read.h"
#define MPMIN(a,b) ((a)<(b)?(a):(b))
#define PROP_VALUE_MAX 92
#define SEED_NONCE "0123456789abcdef0123456789abcdef"
static void capture_log(const char *format,...) {
    va_list args;va_start(args,format);
    vfprintf(stdout,format,args);
    va_end(args);
}
#define MP_ERR(vo,...) capture_log(__VA_ARGS__)
#define PL_HAVE_MKS_UV_ATLAS_ANCHOR 1
#define PL_HAVE_MKS_UV_ATLAS_READ 1
enum {PL_PRIM_TRIANGLE_STRIP=1,PL_FMT_FLOAT=3,PL_SAMPLER_NORMAL=0};
enum {PL_OPENGL_UV_ATLAS_ANCHOR_FAILED=-1,PL_OPENGL_UV_ATLAS_ANCHOR_PENDING=0,
 PL_OPENGL_UV_ATLAS_ANCHOR_COMPLETE=1};
typedef struct pl_opengl_uv_atlas_anchor_s *pl_opengl_uv_atlas_anchor;
typedef struct pl_opengl_uv_atlas_cache_s *pl_opengl_uv_atlas_cache;
typedef struct pl_opengl_uv_atlas_read_s *pl_opengl_uv_atlas_read;
struct pl_opengl_yuv_compare_quad_attrib {
 char name[32],format_name[32],glsl_type[16];int fmt_type;bool opaque;int num_planes;
 int location,num_components,component_depth[4],host_bits[4],sample_order[4];size_t offset,texel_size;
};
struct pl_opengl_yuv_compare_quad_layout {
 int primitive;bool indexed;int vertex_count,num_attributes,position_attrib;size_t stride,byte_size;
 struct {int x0,y0,x1,y1;} viewport,scissors;
 struct pl_opengl_yuv_compare_quad_attrib attributes[16];
};
#define GL_RGBA16F 0x881Au
#define PL_OPENGL_OUTPUT_RGB16F_TO_BT2020_FULL_YUV 2
typedef struct pl_tex_s *pl_tex;
struct pl_opengl_wrap_params {unsigned framebuffer;int width,height;unsigned iformat;int output_encoding;};
#define pl_opengl_wrap_params(...) (struct pl_opengl_wrap_params){ __VA_ARGS__ }
struct pl_frame {void *user_data;int num_planes;struct {pl_tex texture;} planes[4];};
struct pl_frame_mix {const struct pl_frame **frames;};
struct pl_render_params {int marker;};
struct pl_swapchain_frame {void *fbo;};
struct ra_yuv_fusion_target {uint64_t token,generation;int w,h;unsigned framebuffer;bool flipped;};
struct mp_image {double pts;};
struct vo_frame {const struct mp_image *current;uint64_t frame_id;};
struct mks_yuv_compare_roi {int x,y,w,h;};
enum {MKS_YUV_COMPARE_FAILED=-1,MKS_YUV_COMPARE_ARMED=1,MKS_YUV_COMPARE_PENDING=2,MKS_YUV_COMPARE_READY=3};
struct mks_yuv_compare_result {
 uint64_t capture_id,generation;struct mks_yuv_compare_roi roi;
 const uint32_t *words;size_t num_words;bool swap_succeeded;
};
struct pl_opengl_uv_atlas_anchor_params {uint64_t capture_id,generation;};
struct pl_opengl_uv_atlas_anchor_result {
 uint64_t capture_id,generation;int width,height;size_t pixels,rgba_words,atlas_words;
 bool draw_ok[3],readback_ok[3],half_exact[3];uint64_t program_tokens[3];
 uint64_t draw_epoch_before[3],draw_epoch_after[3],readback_epoch_before[3],readback_epoch_after[3],finish_epoch;
 unsigned framebuffer[3],read_format,read_type;
 bool source_abi_ok,fence_signaled,atlas_complete,anchor_equal;
 size_t mismatches_before_atlas,mismatches_before_after,bad_half_components[3],bad_atlas_pixels;
};
struct pl_opengl_uv_atlas_material {
 int input_width,input_height,sampler_type,sample_mode,address_mode;
 int format_type,num_components,component_depth[4],host_bits[4],sample_order[4];
 char format_name[32];
 uint32_t num_variables,uniform_bytes;
 char uniform_names[16][32];
 uint32_t uniform_offsets[16],uniform_sizes[16],uniform_types[16];
 uint32_t uniform_dim_v[16],uniform_dim_m[16],uniform_dim_a[16];
 uint8_t uniforms[4096];
};
struct pl_opengl_uv_atlas_cache_info {
 uint64_t cache_id,seed_capture_id,generation;int width,height;
 size_t pixels,atlas_words;unsigned int storage_buffer;uint64_t storage_offset,storage_size;
};
struct pl_opengl_uv_atlas_read_params {uint64_t capture_id,generation;unsigned int ordinal;};
struct pl_opengl_uv_atlas_read_result {
 uint64_t capture_id,cache_id,seed_capture_id,generation;
 unsigned int ordinal;int width,height;size_t pixels,rgba_words,probe_words;
 bool signature_match,draw_ok[3],readback_ok[3],baseline_ok,fence_signaled;
 uint64_t program_tokens[3];uint64_t b0_program_token;
 uint64_t seed_input_texture_token,input_texture_token;
 uint64_t draw_epoch_before[3],draw_epoch_after[3];
 uint64_t readback_epoch_before[3],readback_epoch_after[3],finish_epoch;
 unsigned int probe_modes[2];
 size_t bad_uv_pixels,bad_half_pixels;bool uv_equal,half_equal;unsigned int reject_reason;
};
struct priv {
 void *gpu,*ra_ctx,*rr,*sw;
 pl_tex fusion_target;
 uint64_t fusion_generation;
 bool compare_atlas,atlas_reuse,atlas_wait_expired;
 void *atlas_anchor;void *atlas_cache;void *atlas_read;
 struct pl_opengl_uv_atlas_cache_info atlas_cache_info;
 enum mp_yuv_atlas_read_phase atlas_phase;
 unsigned int atlas_ordinal;
 double atlas_second_pts,atlas_seed_pts;
 uint64_t atlas_seed_id,atlas_seed_frame_id,atlas_seed_frame_token;
 uint64_t atlas_seed_image,atlas_input_image;
 uint64_t atlas_renderer_id,atlas_renderer_generation;
 char atlas_nonce[33],atlas_seed_manifest[128],atlas_seed_sha[65],atlas_signature[65];
 bool compare_enabled;
 bool compare_started,compare_active,compare_a_ready;
 bool compare_terminal,compare_fatal_context,compare_frame_open;
 double compare_target_pts,compare_source_pts,compare_current_pts;
 int compare_width,compare_height;
 uint64_t compare_id,compare_generation,compare_error_epoch;
 uint64_t compare_frame_id,compare_frame_token;
 bool compare_epoch_valid;
 int compare_x,compare_y,compare_w,compare_h;
 int64_t compare_deadline;
};
struct vo {struct priv *priv;};
static bool atlas_save(struct vo *,const struct pl_opengl_uv_atlas_anchor_result *,
 const struct mks_yuv_compare_result *,bool *);
static bool atlas_read_seed_saved(struct priv *,const char *,size_t,const char *);
static void atlas_read_seed_ready(struct vo *);
static bool atlas_consumer_render(struct vo *,const struct vo_frame *,
 const struct pl_frame_mix *,const struct pl_frame *,const struct pl_render_params *,
 const struct pl_swapchain_frame *,const struct ra_yuv_fusion_target *);
static void atlas_reuse_poll(struct vo *);
static void atlas_read_wait_poll(struct vo *);
static struct priv *g_p;
static struct mp_image seed_frame_image={.pts=35.035};
static struct mp_image second_frame_image={.pts=600.032766667};
static int64_t now_ns=1000;
static int64_t mp_time_ns(void){return now_ns;}
static uint64_t fake_epoch=7;
static bool pl_opengl_error_epoch(void *g,uint64_t *out){(void)g;*out=fake_epoch;return true;}
static bool owner_current=true;
static bool compare_current(struct priv *p){(void)p;return owner_current;}
static bool read_baseline=true;
static bool compare_baseline_ok(struct priv *p){(void)p;return read_baseline;}
static int aborts;
static void compare_fail_transaction(struct vo *vo,const char *reason){
 (void)reason;aborts++;vo->priv->compare_terminal=true;vo->priv->compare_active=false;}
static void vo_redraw(struct vo *vo){(void)vo;capture_log("VO event=redraw\n");}
static const char *fake_ack="";
static int __system_property_get(const char *name,char *value){
 if(name&&!strcmp(name,"debug.mks.atlas_ack")&&fake_ack[0]){
  strcpy(value,fake_ack);return (int)strlen(fake_ack);}
 value[0]=0;return 0;}
static bool mks_android_yuv_compare_owner_current(void *ctx){(void)ctx;return owner_current;}
static bool mks_android_yuv_compare_restore_owner(void *ctx){(void)ctx;return false;}
static void mks_android_yuv_compare_cancel(void *ctx){(void)ctx;capture_log("MKSD event=cancel\n");}
static bool android_arm_ok=true;
static bool mks_android_yuv_compare_arm(void *ctx,uint64_t id,uint64_t gen,struct mks_yuv_compare_roi roi){
 (void)ctx;assert(id&&gen);assert(roi.w==2&&roi.h==1);return android_arm_ok;}
static uint32_t android_data[14],seed_android_words[14],read_a0[8],read_uv[8],read_half[8],
 seed_rgb[8],seed_atlas[6];
static struct mks_yuv_compare_result live_android,seed_android;
static int android_status=MKS_YUV_COMPARE_READY;
static int mks_android_yuv_compare_poll(void *ctx,struct mks_yuv_compare_result *out){
 (void)ctx;*out=live_android;
 out->capture_id=g_p->compare_id;out->generation=g_p->compare_generation;
 out->roi.x=g_p->compare_x;out->roi.y=g_p->compare_y;
 out->roi.w=g_p->compare_w;out->roi.h=g_p->compare_h;
 return android_status;}
static void pl_tex_destroy(void *gpu,pl_tex *tex){(void)gpu;*tex=NULL;}
static pl_tex pl_opengl_wrap(void *gpu,struct pl_opengl_wrap_params params){
 (void)gpu;assert(params.width==2&&params.height==1&&params.iformat==GL_RGBA16F&&
  params.output_encoding==PL_OPENGL_OUTPUT_RGB16F_TO_BT2020_FULL_YUV);return (pl_tex)88;}
static bool render_ok=true;
static bool pl_render_image_mix(void *rr,const struct pl_frame_mix *mix,
 const struct pl_frame *target,const struct pl_render_params *params){
 (void)rr;assert(mix&&mix->frames[0]&&target&&params);return render_ok;}
static void pl_gpu_flush(void *gpu){(void)gpu;}
static bool anchor_promote_ok=true;
static void *pl_opengl_uv_atlas_promote(void **anchor){(void)anchor;
 return anchor_promote_ok?(void*)77:NULL;}
static bool pl_opengl_uv_atlas_cache_info(void *cache,struct pl_opengl_uv_atlas_cache_info *info,
 const uint32_t **atlas){(void)cache;
 g_p->atlas_cache_info=(struct pl_opengl_uv_atlas_cache_info){.cache_id=77,
  .seed_capture_id=g_p->atlas_seed_id,.generation=g_p->compare_generation,
  .width=2,.height=1,.pixels=2,.atlas_words=6,.storage_buffer=9,
  .storage_offset=0,.storage_size=24};
 if(info)*info=g_p->atlas_cache_info;if(atlas)*atlas=seed_atlas;return true;}
static int cache_destroys,read_cancels;
static bool pl_opengl_uv_atlas_cache_destroy(void **cache){(void)cache;cache_destroys++;*cache=NULL;return true;}
static void *pl_opengl_uv_atlas_anchor_arm(void *gpu,void *target,
 const struct pl_opengl_uv_atlas_anchor_params *p){(void)gpu;(void)target;(void)p;return NULL;}
static bool pl_opengl_uv_atlas_anchor_data(void *h,const uint32_t **b,const uint32_t **m,
 const uint32_t **a,const uint32_t **uv){(void)h;*b=seed_rgb;*m=seed_rgb;*a=seed_rgb;*uv=seed_atlas;return true;}
static const char A0_FRAGMENT[] =
 "#version 310 es\n"
 "precision highp float;\n"
 "out vec4 out_color;\n"
 "uniform sampler2D _1a2b;\n"
 "uniform vec4 _3c4d;\n"
 "vec4 _e5f6() {\n"
 "// pl_shader_sample_direct\n"
 "vec4 color = vec4(_3c4d) * vec4(textureLod(_1a2b, _0a1b, 0.0));\n"
 "return color;\n"
 "}\n"
 "void main() {\nout_color = _e5f6();\n}";
static const char ORIGINAL_BODY[] =
 "vec4 _e5f6() {\n"
 "// pl_shader_sample_direct\n"
 "vec4 color = vec4(_3c4d) * vec4(textureLod(_1a2b, _0a1b, 0.0));\n"
 "return color;\n"
 "}\n";
static char *built_middle;
static const char *middle_fallback = A0_FRAGMENT;
static const char VERTEX_SOURCE[] =
 "#version 310 es\n"
 "layout(location = 0) in vec2 position;\n"
 "layout(location = 1) in vec2 uv0;\n"
 "out vec2 _uv;\n"
 "void main() {\n"
 "vec2 va_pos = position;\n"
 "gl_Position = vec4(va_pos, 0.0, 1.0);\n"
 "_uv = uv0;\n"
 "}\n";
static bool pl_opengl_uv_atlas_anchor_sources(void *h,const char **a0,const char **af,
 const char **v,const char **orig){(void)h;*a0=A0_FRAGMENT;
 *af=built_middle?built_middle:middle_fallback;*v=VERTEX_SOURCE;*orig=ORIGINAL_BODY;return true;}
static uint8_t quad_bytes[64];
static struct pl_opengl_yuv_compare_quad_layout quad_layout;
static bool pl_opengl_uv_atlas_anchor_vertices(void *h,const uint8_t **data,
 struct pl_opengl_yuv_compare_quad_layout *q){(void)h;*data=quad_bytes;*q=quad_layout;return true;}
static struct pl_opengl_uv_atlas_anchor_result seed_result;
static int anchor_status=1;
static int pl_opengl_uv_atlas_anchor_poll(void *h,struct pl_opengl_uv_atlas_anchor_result *out){
 (void)h;*out=seed_result;return anchor_status;}
static int read_arms;
static bool read_arm_ok=true;
static pl_opengl_uv_atlas_read pl_opengl_uv_atlas_read_arm(void *cache,pl_tex rgb,pl_tex yuv,
 const struct pl_opengl_uv_atlas_read_params *params){
 (void)cache;read_arms++;assert(rgb==(pl_tex)55&&yuv==(pl_tex)88&&params->capture_id&&
  params->generation==g_p->compare_generation&&params->ordinal==g_p->atlas_ordinal);
 return read_arm_ok?(pl_opengl_uv_atlas_read)(uintptr_t)(16+params->ordinal):NULL;}
static bool pl_opengl_uv_atlas_read_baseline_ok(pl_opengl_uv_atlas_read r){(void)r;return read_baseline;}
static struct pl_opengl_uv_atlas_read_result read_result;
static int read_status=1; /* COMPLETE */
static int pl_opengl_uv_atlas_read_poll(pl_opengl_uv_atlas_read r,
 struct pl_opengl_uv_atlas_read_result *out){(void)r;*out=read_result;
 out->capture_id=g_p->compare_id;out->cache_id=g_p->atlas_cache_info.cache_id;
 out->seed_capture_id=g_p->atlas_seed_id;out->generation=g_p->compare_generation;
 out->ordinal=g_p->atlas_ordinal;return read_status;}
static bool pl_opengl_uv_atlas_read_data(pl_opengl_uv_atlas_read r,const uint32_t **a0,
 const uint32_t **uv,const uint32_t **half){(void)r;*a0=read_a0;*uv=read_uv;*half=read_half;return true;}
static char *built_b0,*built_probe;
static struct pl_opengl_uv_atlas_material live_material;
static const struct pl_opengl_uv_atlas_material *material_for_signature;
static const uint8_t *signature_vertices;
static const struct pl_opengl_yuv_compare_quad_layout *signature_layout;
static bool pl_opengl_uv_atlas_read_sources(pl_opengl_uv_atlas_read r,const char **a0,
 const char **b0,const char **probe,const char **vertex,const char **body){
 (void)r;*a0=A0_FRAGMENT;*b0=built_b0;*probe=built_probe;*vertex=VERTEX_SOURCE;
 *body=ORIGINAL_BODY;return true;}
static bool pl_opengl_uv_atlas_read_signature(pl_opengl_uv_atlas_read r,
 const struct pl_opengl_uv_atlas_material **seed,
 const struct pl_opengl_uv_atlas_material **current,const uint8_t **vertices,
 struct pl_opengl_yuv_compare_quad_layout *layout){(void)r;
 *seed=&live_material;*current=material_for_signature?material_for_signature:&live_material;
 *vertices=signature_vertices;*layout=*signature_layout;return true;}
static bool pl_opengl_uv_atlas_read_cancel(void **read){(void)read;read_cancels++;*read=NULL;return true;}
static const char *save_dir;
static int manifest_writes,fail_write_index;
static bool compare_write_exclusive(const char *path,const void *data,size_t bytes){
 const char *name=strrchr(path,'/');name=name?name+1:path;
 char full[512];if(!save_dir||snprintf(full,sizeof(full),"%s/%s",save_dir,name)>=(int)sizeof(full))return false;
 if(manifest_writes+1==fail_write_index)return false;
 int fd=open(full,O_WRONLY|O_CREAT|O_EXCL|O_CLOEXEC,0600);
 if(fd<0)return false;
 const unsigned char *src=data;bool ok=true;
 while(bytes){ssize_t n=write(fd,src,bytes);
  if(n<0&&errno==EINTR)continue;
  if(n<=0){ok=false;break;}src+=n;bytes-=(size_t)n;}
 ok=!close(fd)&&ok;
 if(ok)manifest_writes++;
 return ok;}
'''

STATE = r'''
static void reset(struct priv *p){
 memset(p,0,sizeof(*p));
 p->gpu=(void*)1;p->rr=(void*)2;p->ra_ctx=(void*)3;
 p->compare_atlas=p->atlas_reuse=true;
 p->atlas_renderer_id=2;p->atlas_renderer_generation=999;
 strcpy(p->atlas_nonce,SEED_NONCE);
 p->atlas_second_pts=600.032766667;
 p->compare_target_pts=35.035;
 p->compare_width=2;p->compare_height=1;
 fake_epoch=7;
 p->compare_error_epoch=fake_epoch;
 p->compare_epoch_valid=true;
 aborts=0;now_ns=1000;
 owner_current=true;read_baseline=true;render_ok=true;android_arm_ok=true;
 android_status=MKS_YUV_COMPARE_READY;
 read_arms=0;read_arm_ok=true;read_status=1;read_cancels=0;cache_destroys=0;
 anchor_promote_ok=true;manifest_writes=0;fail_write_index=0;
 material_for_signature=NULL;fake_ack="";
 memset(android_data,0,sizeof(android_data));android_data[0]=android_data[7]=1;
 memset(seed_android_words,0,sizeof(seed_android_words));seed_android_words[0]=seed_android_words[7]=1;
 live_android=(struct mks_yuv_compare_result){.generation=2,.roi={0,0,2,1},
  .words=android_data,.num_words=14,.swap_succeeded=true};
 seed_android=(struct mks_yuv_compare_result){.generation=2,.roi={0,0,2,1},
  .words=seed_android_words,.num_words=14,.swap_succeeded=true};
 /* Half-exact RGB: 1.0 and -1.0 words only; all three anchor stages equal. */
 for(int i=0;i<8;i++)seed_rgb[i]=(i%4==3)?0x3f800000:((i%8<2)?0x3f800000:0xbf800000);
 seed_result=(struct pl_opengl_uv_atlas_anchor_result){.capture_id=UINT64_MAX,.generation=2,
  .width=2,.height=1,.pixels=2,.rgba_words=8,.atlas_words=6,.draw_ok={true,true,true},
  .readback_ok={true,true,true},.half_exact={true,true,true},.program_tokens={11,22,11},
  .draw_epoch_before={7,7,7},.draw_epoch_after={7,7,7},.readback_epoch_before={7,7,7},
  .readback_epoch_after={7,7,7},.finish_epoch=7,.framebuffer={55,55,55},
  .read_format=6408,.read_type=5126,.source_abi_ok=true,.fence_signaled=true,
  .atlas_complete=true,.anchor_equal=true,.mismatches_before_atlas=0,
  .mismatches_before_after=0,.bad_half_components={0,0,0},.bad_atlas_pixels=0};
 seed_atlas[0]=0x3f000000;seed_atlas[1]=0x3e800000;seed_atlas[2]=1;
 seed_atlas[3]=0x3f000000;seed_atlas[4]=0x3e800000;seed_atlas[5]=1;
 memset(quad_bytes,0,sizeof(quad_bytes));
 static const uint32_t corners[16]={0xbf800000,0xbf800000,0,0, 0x3f800000,0xbf800000,0x3f800000,0,
  0xbf800000,0x3f800000,0,0x3f800000, 0x3f800000,0x3f800000,0x3f800000,0x3f800000};
 memcpy(quad_bytes,corners,sizeof(corners));
 quad_layout=(struct pl_opengl_yuv_compare_quad_layout){.primitive=PL_PRIM_TRIANGLE_STRIP,
  .vertex_count=4,.num_attributes=2,.position_attrib=0,.stride=16,.byte_size=64,
  .viewport={0,0,2,1},.scissors={0,0,2,1},
  .attributes={{.name="position",.format_name="rg32f",.glsl_type="vec2",.fmt_type=PL_FMT_FLOAT,
   .location=0,.num_components=2,.component_depth={32,32},.host_bits={32,32},
   .sample_order={0,1,2,3},.offset=0,.texel_size=8},
  {.name="uv0",.format_name="rg32f",.glsl_type="vec2",.fmt_type=PL_FMT_FLOAT,
   .location=1,.num_components=2,.component_depth={32,32},.host_bits={32,32},
   .sample_order={0,1,2,3},.offset=8,.texel_size=8}}};
 signature_vertices=quad_bytes;signature_layout=&quad_layout;
 live_material=(struct pl_opengl_uv_atlas_material){.input_width=1920,.input_height=1080,
  .sampler_type=PL_SAMPLER_NORMAL,.sample_mode=1,.address_mode=1,.format_type=1,
  .num_components=4,.component_depth={8,8,8,8},.host_bits={8,8,8,8},.sample_order={0,1,2,3}};
 strcpy(live_material.format_name,"rgba8");
 live_material.num_variables=1;live_material.uniform_bytes=16;
 strcpy(live_material.uniform_names[0],"_3c4d");
 live_material.uniform_offsets[0]=0;live_material.uniform_sizes[0]=16;
 live_material.uniform_types[0]=3;live_material.uniform_dim_v[0]=4;
 live_material.uniform_dim_m[0]=1;live_material.uniform_dim_a[0]=1;
 memcpy(live_material.uniforms,"\x00\x00\x80\x3f\x00\x00\x80\x3f\x00\x00\x80\x3f\x00\x00\x80\x3f",16);
 free(built_b0);free(built_probe);free(built_middle);
 built_b0=mks_atlas_b0(A0_FRAGMENT,ORIGINAL_BODY,2,1);
 built_probe=built_b0?mks_atlas_probe(built_b0,2,1):NULL;
 built_middle=mks_atlas_fragment(A0_FRAGMENT,ORIGINAL_BODY,2,1);
 assert(built_b0&&built_probe&&built_middle);
 for(int pixel=0;pixel<2;pixel++){
  read_a0[pixel*4+0]=seed_rgb[pixel*4+0];read_a0[pixel*4+1]=seed_rgb[pixel*4+1];
  read_a0[pixel*4+2]=seed_rgb[pixel*4+2];read_a0[pixel*4+3]=0x3f800000;
  read_uv[pixel*4+0]=1;read_uv[pixel*4+1]=seed_atlas[pixel*3+0];
  read_uv[pixel*4+2]=seed_atlas[pixel*3+1];read_uv[pixel*4+3]=1;
  read_half[pixel*4+0]=1;read_half[pixel*4+1]=read_a0[pixel*4+0];
  read_half[pixel*4+2]=read_a0[pixel*4+1];read_half[pixel*4+3]=read_a0[pixel*4+2];}
 read_result=(struct pl_opengl_uv_atlas_read_result){.generation=2,.width=2,.height=1,
  .pixels=2,.rgba_words=8,.probe_words=8,.signature_match=true,.draw_ok={true,true,true},
  .readback_ok={true,true,true},.baseline_ok=true,.fence_signaled=true,
  .b0_program_token=33,.draw_epoch_before={7,7,7},.draw_epoch_after={7,7,7},
  .readback_epoch_before={7,7,7},.readback_epoch_after={7,7,7},.finish_epoch=7,
  .probe_modes={0,1},.bad_uv_pixels=0,.bad_half_pixels=0,.uv_equal=true,.half_equal=true,
  .reject_reason=0};
 read_result.program_tokens[0]=11;read_result.program_tokens[1]=22;read_result.program_tokens[2]=22;
 read_result.seed_input_texture_token=read_result.input_texture_token=44;
}

static void seed_ready_for_reuse(struct vo *vo){
 struct priv *p=vo->priv;
 p->compare_started=p->compare_active=true;
 p->compare_id=1000;p->compare_generation=2;
 p->compare_frame_id=11;p->compare_frame_token=13;
 p->compare_source_pts=p->compare_current_pts=35.035;
 p->compare_x=0;p->compare_y=0;p->compare_w=2;p->compare_h=1;
 p->atlas_phase=MP_ATLAS_SEED_PENDING;
 p->atlas_seed_id=p->compare_id;
 p->atlas_seed_frame_id=11;p->atlas_seed_frame_token=13;
 p->atlas_seed_pts=35.035;p->atlas_seed_image=(uint64_t)(uintptr_t)&seed_frame_image;
 p->atlas_anchor=(void*)55;
 seed_result.capture_id=p->compare_id;
 seed_android.capture_id=p->compare_id;
 bool invalid=false;
 if(!atlas_save(vo,&seed_result,&seed_android,&invalid))
  {capture_log("HARNESS event=seed-save-failed\n");exit(3);}
 assert(p->atlas_seed_sha[0]&&p->atlas_seed_manifest[0]);
 atlas_read_seed_ready(vo);
}

static void expect_state(struct priv *p,enum mp_yuv_atlas_read_phase phase){
 if(p->atlas_phase!=phase){capture_log("HARNESS event=unexpected-phase actual=%d want=%d\n",
  (int)p->atlas_phase,(int)phase);exit(4);}
}
'''

MAIN = r'''
int main(int argc,char **argv){
 if(argc<3){fprintf(stderr,"usage: %s MODE SAVE_DIR\n",argv[0]);return 64;}
 save_dir=argv[2];
 struct priv p;struct vo vo={.priv=&p};g_p=&p;
 reset(&p);
 if(!strcmp(argv[1],"reuse")||!strcmp(argv[1],"reuse-diag")||!strcmp(argv[1],"reuse-bad-signature")){
  seed_ready_for_reuse(&vo);
  expect_state(&p,MP_ATLAS_T1_REDRAW);
  struct vo_frame frame={.current=&seed_frame_image,.frame_id=11};
  struct pl_frame source_frame={.user_data=&seed_frame_image};
  const struct pl_frame *frames[]={&source_frame};
  struct pl_frame_mix mix={.frames=frames};
  struct pl_frame target={0};
  struct pl_render_params params={.marker=123};
  struct pl_swapchain_frame swframe={.fbo=(void*)55};
  struct ra_yuv_fusion_target desc={.token=14,.generation=2,.w=2,.h=1};
  if(!strcmp(argv[1],"reuse-bad-signature")){
   static struct pl_opengl_uv_atlas_material drifted;
   drifted=live_material;drifted.uniforms[0]^=1;
   material_for_signature=&drifted;
  }
  assert(!atlas_consumer_render(&vo,&frame,&mix,&target,&params,&swframe,&desc));
  if(!strcmp(argv[1],"reuse-bad-signature")){
   expect_state(&p,MP_ATLAS_T1_PENDING);
   atlas_reuse_poll(&vo);
   expect_state(&p,MP_ATLAS_REJECTED);
   assert(read_cancels==1&&cache_destroys==1);
   return 0;
  }
  expect_state(&p,MP_ATLAS_T1_PENDING);
  if(!strcmp(argv[1],"reuse-diag")){
   read_uv[1]^=1; /* archive stage 1 as diagnostic-invalid */
   read_result.bad_uv_pixels=1;read_result.uv_equal=false;
  }
  atlas_reuse_poll(&vo);
  expect_state(&p,MP_ATLAS_WAIT_ACK);
  assert(read_arms==1&&!p.compare_active&&!p.compare_started);
  static char ack[64];
  snprintf(ack,sizeof(ack),"%s:%"PRIu64,SEED_NONCE,p.atlas_cache_info.cache_id);
  fake_ack=ack;
  atlas_read_wait_poll(&vo);
  expect_state(&p,MP_ATLAS_WAIT_T2);
  read_uv[1]=seed_atlas[0];
  read_result.bad_uv_pixels=0;read_result.uv_equal=true;
  read_result.seed_input_texture_token=read_result.input_texture_token=45;
  struct vo_frame frame2={.current=&second_frame_image,.frame_id=12};
  struct pl_frame source2={.user_data=&second_frame_image};
  const struct pl_frame *frames2[]={&source2};
  struct pl_frame_mix mix2={.frames=frames2};
  struct ra_yuv_fusion_target desc2={.token=15,.generation=2,.w=2,.h=1};
  assert(!atlas_consumer_render(&vo,&frame2,&mix2,&target,&params,&swframe,&desc2));
  expect_state(&p,MP_ATLAS_T2_PENDING);
  atlas_reuse_poll(&vo);
  expect_state(&p,MP_ATLAS_DONE);
  assert(read_arms==2&&!p.atlas_wait_expired);
  return 0;
 }
 if(!strcmp(argv[1],"reuse-bad-renderer")){
  seed_ready_for_reuse(&vo);
  p.atlas_renderer_id=3;
  struct vo_frame frame={.current=&seed_frame_image,.frame_id=11};
  struct pl_frame source_frame={.user_data=&seed_frame_image};
  const struct pl_frame *frames[]={&source_frame};
  struct pl_frame_mix mix={.frames=frames};
  struct pl_frame target={0};
  struct pl_render_params params={.marker=123};
  struct pl_swapchain_frame swframe={.fbo=(void*)55};
  struct ra_yuv_fusion_target desc={.token=14,.generation=2,.w=2,.h=1};
  assert(!atlas_consumer_render(&vo,&frame,&mix,&target,&params,&swframe,&desc));
  expect_state(&p,MP_ATLAS_REJECTED);
  assert(read_arms==0&&cache_destroys==1);
  return 0;
 }
 if(!strcmp(argv[1],"reuse-bad-t1-frame")){
  seed_ready_for_reuse(&vo);
  struct mp_image other={.pts=35.036};
  struct vo_frame frame={.current=&other,.frame_id=99};
  struct pl_frame source_frame={.user_data=&other};
  const struct pl_frame *frames[]={&source_frame};
  struct pl_frame_mix mix={.frames=frames};
  struct pl_frame target={0};
  struct pl_render_params params={.marker=123};
  struct pl_swapchain_frame swframe={.fbo=(void*)55};
  struct ra_yuv_fusion_target desc={.token=14,.generation=2,.w=2,.h=1};
  assert(!atlas_consumer_render(&vo,&frame,&mix,&target,&params,&swframe,&desc));
  expect_state(&p,MP_ATLAS_REJECTED);
  assert(read_arms==0);
  return 0;
 }
 if(!strcmp(argv[1],"reuse-bad-ack")){
  seed_ready_for_reuse(&vo);
  struct vo_frame frame={.current=&seed_frame_image,.frame_id=11};
  struct pl_frame source_frame={.user_data=&seed_frame_image};
  const struct pl_frame *frames[]={&source_frame};
  struct pl_frame_mix mix={.frames=frames};
  struct pl_frame target={0};
  struct pl_render_params params={.marker=123};
  struct pl_swapchain_frame swframe={.fbo=(void*)55};
  struct ra_yuv_fusion_target desc={.token=14,.generation=2,.w=2,.h=1};
  assert(!atlas_consumer_render(&vo,&frame,&mix,&target,&params,&swframe,&desc));
  expect_state(&p,MP_ATLAS_T1_PENDING);
  atlas_reuse_poll(&vo);
  expect_state(&p,MP_ATLAS_WAIT_ACK);
  static char stale[64];
  snprintf(stale,sizeof(stale),"%s:wrong",SEED_NONCE);
  fake_ack=stale;
  struct vo_frame frame2={.current=&second_frame_image,.frame_id=12};
  struct pl_frame source2={.user_data=&second_frame_image};
  const struct pl_frame *frames2[]={&source2};
  struct pl_frame_mix mix2={.frames=frames2};
  struct ra_yuv_fusion_target desc2={.token=15,.generation=2,.w=2,.h=1};
  assert(!atlas_consumer_render(&vo,&frame2,&mix2,&target,&params,&swframe,&desc2));
  expect_state(&p,MP_ATLAS_REJECTED);
  assert(read_arms==1);
  return 0;
 }
 if(!strcmp(argv[1],"reuse-bad-save")){
  seed_ready_for_reuse(&vo);
  fail_write_index=14; /* first stage archive writes fail (11 seed + 3 in) */
  struct vo_frame frame={.current=&seed_frame_image,.frame_id=11};
  struct pl_frame source_frame={.user_data=&seed_frame_image};
  const struct pl_frame *frames[]={&source_frame};
  struct pl_frame_mix mix={.frames=frames};
  struct pl_frame target={0};
  struct pl_render_params params={.marker=123};
  struct pl_swapchain_frame swframe={.fbo=(void*)55};
  struct ra_yuv_fusion_target desc={.token=14,.generation=2,.w=2,.h=1};
  assert(!atlas_consumer_render(&vo,&frame,&mix,&target,&params,&swframe,&desc));
  atlas_reuse_poll(&vo);
  expect_state(&p,MP_ATLAS_REJECTED);
  return 0;
 }
 fprintf(stderr,"unknown mode %s\n",argv[1]);return 64;
}
'''


class AtlasReadVoTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory()
        cls.exe = Path(cls.temp.name) / 'atlas_read'
        c = Path(cls.temp.name) / 'atlas_read.c'
        c.write_text(BASE + schema9_functions() + STATE + MAIN)
        subprocess.run(['clang', '-std=c11', '-Wall', '-Wextra', '-Werror',
                        '-Wno-unused-function', '-I' + str(ROOT / 'mpv'),
                        '-I' + str(ROOT / 'mpv/video/out'),
                        '-I' + str(PLACEBO), str(c), '-lm', '-o', str(cls.exe)],
                       check=True)

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    def run_mode(self, mode):
        out = Path(self.temp.name) / mode
        out.mkdir(exist_ok=False)
        proc = subprocess.run([str(self.exe), mode, str(out)],
                              capture_output=True, text=True)
        return out, proc

    def manifests(self, out):
        return sorted(p for p in out.glob('mks-uv-atlas-read-*.json')
                      if not p.name.endswith('-material.json'))

    def seed_manifest(self, out):
        found = list(out.glob('mks-yuv-atlas-*.json'))
        assert len(found) == 1, found
        return found[0]

    def test_full_reuse_pair_passes_analyzer(self):
        out, proc = self.run_mode('reuse')
        self.assertEqual(proc.returncode, 0, proc.stderr + proc.stdout)
        seed_analysis = analyze(self.seed_manifest(out))
        self.assertEqual(seed_analysis['schema'], 9)
        self.assertEqual(seed_analysis['status'], 'captured-floats-bit-equal')
        found = self.manifests(out)
        self.assertEqual(len(found), 2)
        first_analysis = analyze(found[0], seed_root=out)
        self.assertEqual(first_analysis['schema'], 10)
        self.assertEqual(first_analysis['status'], 'captured-floats-bit-equal')
        self.assertEqual(first_analysis['identity']['ordinal'], 1)
        self.assertTrue(first_analysis['within_frame_fullscreen_uv_half_equal'])
        self.assertFalse(first_analysis['quality_pass'])
        second_analysis = analyze(found[1], seed_root=out)
        self.assertEqual(second_analysis['identity']['ordinal'], 2)
        pair = validate_atlas_read_pair(found[0], found[1], out)
        self.assertTrue(pair['cross_pts_reuse_validated'])
        self.assertFalse(pair['yuv_equality_measured'])
        events = re.findall(r'MKS-UV-ATLAS-READ event=([a-z-]+)', proc.stdout)
        self.assertEqual(events, ['seed-promoted', 'armed', 'capture-complete',
                                  'promoted-ready', 'ack-accepted', 'armed',
                                  'capture-complete'])
        arms = re.findall(r'event=armed id=\d+ generation=\d+ ordinal=(\d) '
                          r'cache_id=\d+ source_pts=[\d.]+ android=(\d) lib=(\d)',
                          proc.stdout)
        self.assertEqual(arms, [('1', '1', '1'), ('2', '1', '1')])
        for path in found:
            m = json.loads(path.read_text())
            self.assertEqual(m['diagnostic_cache_settings'],
                             {'skip_caching_single_frame': True,
                              'preserve_mixing_cache': False})
            self.assertIs(m['b0_drawn'], False)
            self.assertEqual(m['status'], 'complete')

    def test_diagnostic_stage_still_archives(self):
        out, proc = self.run_mode('reuse-diag')
        self.assertEqual(proc.returncode, 0, proc.stderr + proc.stdout)
        analyze(self.seed_manifest(out))
        found = self.manifests(out)
        self.assertEqual(len(found), 2)
        self.assertIn('diagnostic-invalid', found[0].name)
        first = analyze(found[0], seed_root=out)
        self.assertEqual(first['status'], 'diagnostic-invalid')
        self.assertEqual(first['read_validation_mask'], 1)
        second = analyze(found[1], seed_root=out)
        self.assertEqual(second['status'], 'captured-floats-bit-equal')

    def test_signature_drift_fails_stage_archive(self):
        out, proc = self.run_mode('reuse-bad-signature')
        self.assertEqual(proc.returncode, 0, proc.stderr + proc.stdout)
        self.assertEqual(self.manifests(out), [])
        self.assertIn('capture-failed', proc.stdout)

    def test_renderer_change_refuses_before_arm(self):
        out, proc = self.run_mode('reuse-bad-renderer')
        self.assertEqual(proc.returncode, 0, proc.stderr + proc.stdout)
        self.assertEqual(self.manifests(out), [])
        self.assertIn('capture-failed', proc.stdout)
        self.assertNotIn('event=armed', proc.stdout)

    def test_t1_identity_mismatch_refuses(self):
        out, proc = self.run_mode('reuse-bad-t1-frame')
        self.assertEqual(proc.returncode, 0, proc.stderr + proc.stdout)
        self.assertEqual(self.manifests(out), [])
        self.assertIn('capture-failed', proc.stdout)

    def test_t2_without_valid_ack_refuses(self):
        out, proc = self.run_mode('reuse-bad-ack')
        self.assertEqual(proc.returncode, 0, proc.stderr + proc.stdout)
        self.assertEqual(len(self.manifests(out)), 1)
        self.assertIn('capture-failed', proc.stdout)

    def test_archive_write_failure_rejects(self):
        out, proc = self.run_mode('reuse-bad-save')
        self.assertEqual(proc.returncode, 0, proc.stderr + proc.stdout)
        self.assertIn('capture-failed', proc.stdout)


if __name__ == '__main__':
    unittest.main()
