/* Standalone API24 true-YUV byte equivalence probe. No media, display or
 * system changes. A public AImageReader owns the offscreen consumer surface.
 * A: generated RGB -> real RGBA16F -> same CSC -> layout(yuv).
 * B: identical RGB expression -> half-store emulation -> CSC -> layout(yuv).
 * Pixel equality here is not a playback or optical-panel acceptance test.
 */
#define _DEFAULT_SOURCE
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES3/gl3.h>
#include <android/native_window.h>
#include <media/NdkImageReader.h>
#include <errno.h>
#include <fcntl.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

enum { W=256, H=256, PLANES=3, PASSES=8 };
struct run {
 EGLDisplay d; EGLContext c; EGLSurface s; AImageReader *reader;
 GLuint vao, tex, fbo, pattern, old_yuv, fused_yuv;
 int visual, config_id, egl_error, gl_error, plane_count;
 int requested_client_version, renderable_type, surface_type, actual_major, actual_minor;
 FILE *trace;
 bool current, complete, cleanup; const char *stage; char error[256];
 char renderer[256], version[256], glsl[256]; bool yuv_ext;
 uint64_t mismatch, repeat_a_mismatch, repeat_b_mismatch, total;
 uint64_t pattern_diff[PLANES];
 int64_t timestamps[PASSES]; unsigned minv[3], maxv[3]; int first_plane, first_x, first_y, first_a, first_b;
 uint8_t *capture[PASSES][PLANES];
};
static bool fail(struct run *r,const char *msg) {
 snprintf(r->error,sizeof(r->error),"%s",msg);EGLint e=eglGetError();if(!r->egl_error||r->egl_error==EGL_SUCCESS)r->egl_error=e;GLenum g=glGetError();if(!r->gl_error)r->gl_error=g;return false;
}
static bool glok(struct run *r,const char *msg) { GLenum e=glGetError();if(e){r->gl_error=(int)e;snprintf(r->error,sizeof(r->error),"%s",msg);return false;}return true; }
static const char *vertex="#version 300 es\nvoid main(){float x=float((gl_VertexID&1)<<2)-1.;float y=float((gl_VertexID&2)<<1)-1.;gl_Position=vec4(x,y,0.,1.);}";
/* Deliberately deterministic pixel-position expression; neutral/colour ramps,
 * near-black values and saturated excursions. Each 2x2 block is constant so
 * A/B compare the same chroma support, without assuming a UV downsample filter.
 */
static const char *body=
 "precision highp float;precision highp int;\n"
 "uniform highp int pattern_id;vec3 baseRgb(){ivec2 p=ivec2(gl_FragCoord.xy)/2;float u=float(p.x)/127.;float v=float(p.y%32)/31.;int band=p.y/32;"
 "if(band==0)return vec3(u,u,u);"
 "if(band==1){float t=u*u*0.001;return vec3(t,t*(0.75+0.25*v),t*(0.25+0.75*v));}"
 "if(band==2)return vec3(u,v,1.-u);"
 "float k=float((p.x+p.y)%17)*0.00001;return vec3(k,u,1.-v);}\n"
 "vec3 sourceRgb(){vec3 p=baseRgb();return pattern_id==0?p:vec3(0.15+0.70*(1.-p.r),0.08+0.82*(1.-p.b),0.10+0.75*p.g);}\n"
 "float halfStore(float v){uint raw=floatBitsToUint(v);uint mag=raw&0x7fffffffu;float b=unpackHalf2x16(packHalf2x16(vec2(v,0.))).x;"
 "if(mag==0u||mag>=0x38800000u)return b;uint sign=raw&0x80000000u;int e=int(mag>>23u)-127;if(e< -24)return uintBitsToFloat(sign);"
 "uint h=((mag&0x7fffffu)|0x800000u)>>uint(-e-1);float q=float(h)*0.000000059604644775390625;return uintBitsToFloat(floatBitsToUint(q)|sign);}\n"
 "vec3 csc(vec3 rgb){float y=0.2627*rgb.r+0.6780*rgb.g+0.0593*rgb.b;float cb=(rgb.b-y)*0.5/(1.-0.0593);float cr=(rgb.r-y)*0.5/(1.-0.2627);return vec3(y,cb+0.5,cr+0.5);}\n";
static GLuint shader(struct run *r,GLenum type,const char *src) {
 GLuint s=glCreateShader(type);glShaderSource(s,1,&src,NULL);glCompileShader(s);GLint ok=0;glGetShaderiv(s,GL_COMPILE_STATUS,&ok);
 if(!ok){glGetShaderInfoLog(s,sizeof(r->error),NULL,r->error);glDeleteShader(s);return 0;}return s;
}
static GLuint program(struct run *r,int mode) {
 char fragment[8192];
 const char *out=mode==0?"out highp vec4 color;void main(){color=vec4(sourceRgb(),1.);}":mode==1?
 "uniform highp sampler2D src;layout(yuv) out highp vec3 color;void main(){vec3 rgb=texelFetch(src,ivec2(gl_FragCoord.xy),0).rgb;color=csc(rgb);}":
 "layout(yuv) out highp vec3 color;void main(){vec3 rgb=sourceRgb();rgb=vec3(halfStore(rgb.r),halfStore(rgb.g),halfStore(rgb.b));color=csc(rgb);}";
 snprintf(fragment,sizeof(fragment),"#version 300 es\n%s%s%s",mode?"#extension GL_EXT_YUV_target : require\n":"",body,out);
 GLuint vs=shader(r,GL_VERTEX_SHADER,vertex),fs=vs?shader(r,GL_FRAGMENT_SHADER,fragment):0,p=0;
 if(vs&&fs){p=glCreateProgram();glAttachShader(p,vs);glAttachShader(p,fs);glLinkProgram(p);GLint ok=0;glGetProgramiv(p,GL_LINK_STATUS,&ok);if(!ok){glGetProgramInfoLog(p,sizeof(r->error),NULL,r->error);glDeleteProgram(p);p=0;}}
 if(vs)glDeleteShader(vs);if(fs)glDeleteShader(fs);return p;
}
static bool setup(struct run *r) {
 r->stage="image-reader";
 if(AImageReader_new(W,H,AIMAGE_FORMAT_YUV_420_888,3,&r->reader)!=AMEDIA_OK)return fail(r,"AImageReader_new YUV_420_888 unsupported");
 ANativeWindow *window=NULL;if(AImageReader_getWindow(r->reader,&window)!=AMEDIA_OK||!window)return fail(r,"AImageReader_getWindow failed");
 r->d=eglGetDisplay(EGL_DEFAULT_DISPLAY);if(r->d==EGL_NO_DISPLAY||!eglInitialize(r->d,NULL,NULL))return fail(r,"eglInitialize failed");
 EGLint n=0;if(!eglGetConfigs(r->d,NULL,0,&n)||n<=0||n>4096)return fail(r,"EGL configuration enumeration failed");
 EGLConfig *configs=calloc((size_t)n,sizeof(*configs)),cfg=NULL;if(!configs)return fail(r,"config allocation failed");
 if(eglGetConfigs(r->d,configs,n,&n))for(int i=0;i<n;i++){EGLint id=0,visual=0;eglGetConfigAttrib(r->d,configs[i],EGL_CONFIG_ID,&id);eglGetConfigAttrib(r->d,configs[i],EGL_NATIVE_VISUAL_ID,&visual);if(id==49&&visual==0x7fa30c04){cfg=configs[i];r->config_id=id;r->visual=visual;break;}}
 free(configs);if(!cfg)return fail(r,"LG config49/native visual 0x7fa30c04 absent");
 const struct {EGLint key,want;} attrs[]={{EGL_COLOR_BUFFER_TYPE,0x3300},{0x3301,0x3302},{0x3311,2},{0x3312,0x3313},{0x3317,0x3318},{0x330a,0x330b},{0x331a,0x331c}};
 for(unsigned i=0;i<sizeof(attrs)/sizeof(attrs[0]);i++){EGLint v=-1;if(!eglGetConfigAttrib(r->d,cfg,attrs[i].key,&v)||v!=attrs[i].want)return fail(r,"config49 YUV attribute mismatch");}
 r->stage="config-capabilities";
 EGLint renderable=0,surface_type=0;
 if(!eglGetConfigAttrib(r->d,cfg,EGL_RENDERABLE_TYPE,&renderable)||!eglGetConfigAttrib(r->d,cfg,EGL_SURFACE_TYPE,&surface_type))return fail(r,"config capability query failed");
 r->renderable_type=renderable;r->surface_type=surface_type;
 fprintf(r->trace,"config_renderable_type=0x%x config_surface_type=0x%x window_before=%d:%d:0x%x\n",renderable,surface_type,ANativeWindow_getWidth(window),ANativeWindow_getHeight(window),ANativeWindow_getFormat(window));fflush(r->trace);fsync(fileno(r->trace));
 if(!(surface_type&EGL_WINDOW_BIT))return fail(r,"config49 lacks window capability");
 r->stage="window-geometry";
 int geometry_rc=ANativeWindow_setBuffersGeometry(window,W,H,r->visual);
 fprintf(r->trace,"geometry_rc=%d window_after=%d:%d:0x%x\n",geometry_rc,ANativeWindow_getWidth(window),ANativeWindow_getHeight(window),ANativeWindow_getFormat(window));fflush(r->trace);fsync(fileno(r->trace));
 if(geometry_rc)return fail(r,"ImageReader rejected NV12 native geometry");
 r->stage="bind-es-api";EGLBoolean bind_ok=eglBindAPI(EGL_OPENGL_ES_API);EGLint bind_error=eglGetError();
 fprintf(r->trace,"bind_api_ok=%u bind_api_error=0x%x\n",bind_ok,bind_error);fflush(r->trace);fsync(fileno(r->trace));
 if(!bind_ok||bind_error!=EGL_SUCCESS){r->egl_error=bind_error;return fail(r,"eglBindAPI failed");}
 /* Match mpv's GLES primary flags=0 request, then its no-flags fallback.
  * The only CLI-controlled variable is requested client version 2 or 3. */
 EGLint ca[]={EGL_CONTEXT_FLAGS_KHR,0,EGL_CONTEXT_CLIENT_VERSION,r->requested_client_version,EGL_NONE};
 r->stage="create-context-primary";r->c=eglCreateContext(r->d,cfg,EGL_NO_CONTEXT,ca);EGLint ce=eglGetError();
 fprintf(r->trace,"context_primary_ok=%d context_primary_error=0x%x requested_client_version=%d flags=0\n",r->c!=EGL_NO_CONTEXT,ce,r->requested_client_version);fflush(r->trace);fsync(fileno(r->trace));
 if(r->c==EGL_NO_CONTEXT){r->stage="create-context-fallback";r->c=eglCreateContext(r->d,cfg,EGL_NO_CONTEXT,&ca[2]);ce=eglGetError();fprintf(r->trace,"context_fallback_ok=%d context_fallback_error=0x%x\n",r->c!=EGL_NO_CONTEXT,ce);fflush(r->trace);fsync(fileno(r->trace));}
 if(r->c==EGL_NO_CONTEXT||ce!=EGL_SUCCESS){r->egl_error=ce;return fail(r,"eglCreateContext failed");}
 r->stage="create-window-surface";r->s=eglCreateWindowSurface(r->d,cfg,window,NULL);EGLint se=eglGetError();
 fprintf(r->trace,"window_surface_ok=%d window_surface_error=0x%x\n",r->s!=EGL_NO_SURFACE,se);fflush(r->trace);fsync(fileno(r->trace));
 if(r->s==EGL_NO_SURFACE||se!=EGL_SUCCESS){r->egl_error=se;return fail(r,"eglCreateWindowSurface failed");}
 r->stage="make-current";EGLBoolean mc=eglMakeCurrent(r->d,r->s,r->s,r->c);EGLint me=eglGetError();
 fprintf(r->trace,"make_current_ok=%u make_current_error=0x%x\n",mc,me);fflush(r->trace);fsync(fileno(r->trace));
 if(!mc||me!=EGL_SUCCESS){r->egl_error=me;return fail(r,"eglMakeCurrent failed");}
 r->current=true;snprintf(r->renderer,sizeof(r->renderer),"%s",glGetString(GL_RENDERER));snprintf(r->version,sizeof(r->version),"%s",glGetString(GL_VERSION));snprintf(r->glsl,sizeof(r->glsl),"%s",glGetString(GL_SHADING_LANGUAGE_VERSION));
 int parsed_major=0,parsed_minor=0;
 fprintf(r->trace,"actual_gl=%s actual_glsl=%s\n",r->version,r->glsl);fflush(r->trace);fsync(fileno(r->trace));
 if(sscanf(r->version,"OpenGL ES %d.%d",&parsed_major,&parsed_minor)!=2||parsed_major<3)return fail(r,"Actual GLES version below3; no relaxed shader path");
 glGetIntegerv(GL_MAJOR_VERSION,&r->actual_major);glGetIntegerv(GL_MINOR_VERSION,&r->actual_minor);
 if(r->actual_major<3||!glok(r,"GLES3 capability version query failed"))return fail(r,"Actual GLES3 capability unavailable");
 const char *ext=(const char *)glGetString(GL_EXTENSIONS);r->yuv_ext=ext&&strstr(ext,"GL_EXT_YUV_target");if(!r->yuv_ext)return fail(r,"GL_EXT_YUV_target absent");
 glDisable(GL_BLEND);glDisable(GL_DEPTH_TEST);glDisable(GL_STENCIL_TEST);glDisable(GL_CULL_FACE);glDisable(GL_SCISSOR_TEST);glDisable(GL_DITHER);glColorMask(GL_TRUE,GL_TRUE,GL_TRUE,GL_TRUE);
 glGenVertexArrays(1,&r->vao);glBindVertexArray(r->vao);glViewport(0,0,W,H);
 glGenTextures(1,&r->tex);glBindTexture(GL_TEXTURE_2D,r->tex);glTexStorage2D(GL_TEXTURE_2D,1,GL_RGBA16F,W,H);glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MIN_FILTER,GL_NEAREST);glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MAG_FILTER,GL_NEAREST);
 glGenFramebuffers(1,&r->fbo);glBindFramebuffer(GL_FRAMEBUFFER,r->fbo);glFramebufferTexture2D(GL_FRAMEBUFFER,GL_COLOR_ATTACHMENT0,GL_TEXTURE_2D,r->tex,0);
 if(glCheckFramebufferStatus(GL_FRAMEBUFFER)!=GL_FRAMEBUFFER_COMPLETE)return fail(r,"RGBA16F FBO incomplete");
 r->pattern=program(r,0);r->old_yuv=program(r,1);r->fused_yuv=program(r,2);if(!r->pattern||!r->old_yuv||!r->fused_yuv)return false;
 return glok(r,"GL setup error");
}
static bool acquire(struct run *r,int pass) {
 AImage *image=NULL;media_status_t rc=AMEDIA_IMGREADER_NO_BUFFER_AVAILABLE;
 for(int i=0;i<200&&rc==AMEDIA_IMGREADER_NO_BUFFER_AVAILABLE;i++){rc=AImageReader_acquireNextImage(r->reader,&image);if(rc==AMEDIA_IMGREADER_NO_BUFFER_AVAILABLE)usleep(10000);}
 if(rc!=AMEDIA_OK||!image)return fail(r,"No readable YUV image after swap (or producer/consumer format mismatch)");
 if(AImage_getTimestamp(image,&r->timestamps[pass])!=AMEDIA_OK||r->timestamps[pass]<=0||(pass&&r->timestamps[pass]<=r->timestamps[pass-1])){AImage_delete(image);return fail(r,"Image timestamp is stale or unavailable");}
 int32_t width=0,height=0,format=0,planes=0;AImage_getWidth(image,&width);AImage_getHeight(image,&height);AImage_getFormat(image,&format);AImage_getNumberOfPlanes(image,&planes);
 if(width!=W||height!=H||format!=AIMAGE_FORMAT_YUV_420_888||planes!=3){AImage_delete(image);return fail(r,"Image format/size/plane contract mismatch");}r->plane_count=planes;
 for(int p=0;p<PLANES;p++){
  uint8_t *data=NULL;int length=0;int32_t row=0,pixel=0;int w=p?W/2:W,h=p?H/2:H;
  if(AImage_getPlaneData(image,p,&data,&length)!=AMEDIA_OK||AImage_getPlaneRowStride(image,p,&row)!=AMEDIA_OK||AImage_getPlanePixelStride(image,p,&pixel)!=AMEDIA_OK||!data||row<=0||pixel<=0||length<=0||(int64_t)(h-1)*row+(int64_t)(w-1)*pixel>=length){AImage_delete(image);return fail(r,"Invalid image plane bounds");}
  r->capture[pass][p]=malloc((size_t)w*h);if(!r->capture[pass][p]){AImage_delete(image);return fail(r,"capture allocation failed");}
  for(int y=0;y<h;y++)for(int x=0;x<w;x++)r->capture[pass][p][y*w+x]=data[y*row+x*pixel];
 }
 AImage_delete(image);return true;
}
static bool execute(struct run *r) {
 if(!setup(r))return false;
 /* A(P0),B(P1),B(P0),A(P1),B(P1),A(P0),A(P1),B(P0).
  * Non-alternating second half detects repeated/stale two-buffer histories.
  * Each swap is consumed and released before the next; no timing claim. */
 const bool baseline_mode[PASSES]={true,false,false,true,false,true,true,false};
 const int pattern_id[PASSES]={0,1,0,1,1,0,1,0};
 for(int i=0;i<PASSES;i++){
  bool baseline=baseline_mode[i];r->stage=baseline?"baseline-render":"fused-render";
  if(baseline){glBindFramebuffer(GL_FRAMEBUFFER,r->fbo);glUseProgram(r->pattern);glUniform1i(glGetUniformLocation(r->pattern,"pattern_id"),pattern_id[i]);glDrawArrays(GL_TRIANGLES,0,3);if(!glok(r,"RGB16F draw failed"))return false;}
  glBindFramebuffer(GL_FRAMEBUFFER,0);glUseProgram(baseline?r->old_yuv:r->fused_yuv);
  if(!baseline)glUniform1i(glGetUniformLocation(r->fused_yuv,"pattern_id"),pattern_id[i]);
  if(baseline){glActiveTexture(GL_TEXTURE0);glBindTexture(GL_TEXTURE_2D,r->tex);glUniform1i(glGetUniformLocation(r->old_yuv,"src"),0);}
  glDrawArrays(GL_TRIANGLES,0,3);if(!glok(r,"layout(yuv) draw failed"))return false;
  if(!eglSwapBuffers(r->d,r->s))return fail(r,"YUV swap failed");if(!acquire(r,i))return false;
 }
 r->stage="compare";r->first_plane=-1;
 for(int p=0;p<PLANES;p++){
  int w=p?W/2:W,h=p?H/2:H;r->minv[p]=255;r->maxv[p]=0;
  for(int y=0;y<h;y++)for(int x=0;x<w;x++){
   int k=y*w+x;uint8_t a=r->capture[0][p][k];
   if(a<r->minv[p])r->minv[p]=a;if(a>r->maxv[p])r->maxv[p]=a;
   r->pattern_diff[p]+=a!=r->capture[3][p][k];
   /* Compare P0 baseline0 with fused2 and P1 baseline3 with fused1. */
   const int ai[2]={0,3},bi[2]={2,1};
   for(int pair=0;pair<2;pair++){
    uint8_t av=r->capture[ai[pair]][p][k],bv=r->capture[bi[pair]][p][k];r->total++;
    if(av!=bv){r->mismatch++;if(r->first_plane<0){r->first_plane=p;r->first_x=x;r->first_y=y;r->first_a=av;r->first_b=bv;}}
   }
   r->repeat_a_mismatch+=a!=r->capture[5][p][k];
   r->repeat_a_mismatch+=r->capture[3][p][k]!=r->capture[6][p][k];
   r->repeat_b_mismatch+=r->capture[1][p][k]!=r->capture[4][p][k];
   r->repeat_b_mismatch+=r->capture[2][p][k]!=r->capture[7][p][k];
  }
  if(r->pattern_diff[p]<(uint64_t)w*h/8)return fail(r,"Distinct-pattern plane check failed; stale/repeated image cannot pass");
  if(r->maxv[p]-r->minv[p]<8)return fail(r,"Plane dynamic-range sanity failed; empty/stale capture cannot pass");
 }
 r->complete=true;return true;
}
static void cleanup(struct run *r) {
 bool clean=true;
 if(r->current){if(r->pattern)glDeleteProgram(r->pattern);if(r->old_yuv)glDeleteProgram(r->old_yuv);if(r->fused_yuv)glDeleteProgram(r->fused_yuv);if(r->fbo)glDeleteFramebuffers(1,&r->fbo);if(r->tex)glDeleteTextures(1,&r->tex);if(r->vao)glDeleteVertexArrays(1,&r->vao);GLenum e=glGetError();if(e){r->gl_error=e;clean=false;}if(!eglMakeCurrent(r->d,EGL_NO_SURFACE,EGL_NO_SURFACE,EGL_NO_CONTEXT))clean=false;}
 if(r->s!=EGL_NO_SURFACE&&!eglDestroySurface(r->d,r->s))clean=false;if(r->c!=EGL_NO_CONTEXT&&!eglDestroyContext(r->d,r->c))clean=false;if(r->d!=EGL_NO_DISPLAY&&!eglTerminate(r->d))clean=false;if(r->reader)AImageReader_delete(r->reader);
 for(int i=0;i<PASSES;i++)for(int p=0;p<PLANES;p++)free(r->capture[i][p]);r->cleanup=clean;
}
int main(int argc,char **argv) {
 if(argc!=3||(strcmp(argv[2],"2")&&strcmp(argv[2],"3"))){fprintf(stderr,"usage: %s /new/result.txt 2|3\n",argv[0]);return 64;}
 int fd=open(argv[1],O_CREAT|O_EXCL|O_WRONLY|O_CLOEXEC,0600);if(fd<0){perror("exclusive result");return 73;}FILE *out=fdopen(fd,"w");if(!out){close(fd);return 74;}
 fprintf(out,"status=running completed=0 pid=%ld\n",(long)getpid());fflush(out);fsync(fd);alarm(30);
 struct run r={.d=EGL_NO_DISPLAY,.c=EGL_NO_CONTEXT,.s=EGL_NO_SURFACE,.stage="startup",.requested_client_version=atoi(argv[2]),.trace=out};bool ok=execute(&r);cleanup(&r);ok &= r.cleanup && !r.gl_error;
 fprintf(out,"status=%s completed=%d cleanup=%d stage=%s\n",!ok?"unsupported-or-error":r.mismatch||r.repeat_a_mismatch||r.repeat_b_mismatch?"mismatch":"pass-on-tested-synthetic-yuv-only",r.complete,r.cleanup,r.stage);
 fprintf(out,"error=%s egl_error=0x%x gl_error=0x%x renderer=%s version=%s\n",r.error,r.egl_error,r.gl_error,r.renderer,r.version);
 fprintf(out,"config_id=%d visual=0x%x yuv_ext=%d plane_count=%d bytes=%llu mismatch=%llu repeat_a=%llu repeat_b=%llu\n",r.config_id,r.visual,r.yuv_ext,r.plane_count,(unsigned long long)r.total,(unsigned long long)r.mismatch,(unsigned long long)r.repeat_a_mismatch,(unsigned long long)r.repeat_b_mismatch);
 fprintf(out,"ranges=%u-%u,%u-%u,%u-%u first_diff=%d:%d:%d:%d:%d\n",r.minv[0],r.maxv[0],r.minv[1],r.maxv[1],r.minv[2],r.maxv[2],r.first_plane,r.first_x,r.first_y,r.first_a,r.first_b);
 fprintf(out,"pattern_diff=%llu,%llu,%llu\n",(unsigned long long)r.pattern_diff[0],(unsigned long long)r.pattern_diff[1],(unsigned long long)r.pattern_diff[2]);
 fprintf(out,"timestamps_ns=");for(int i=0;i<PASSES;i++)fprintf(out,"%s%lld",i?",":"",(long long)r.timestamps[i]);fputc('\n',out);
 fprintf(out,"limits=synthetic-source;not-playback;not-panel;API24-ImageReader-consumer-may-reject-LG-NV12;no-timing-or-power-claim;YUV420-subsampling-compared-as-raw-planes\n");
 bool written=!ferror(out)&&!fflush(out)&&!fsync(fd);if(fclose(out))written=false;alarm(0);return !written?74:!ok?2:r.mismatch||r.repeat_a_mismatch||r.repeat_b_mismatch?3:0;
}
