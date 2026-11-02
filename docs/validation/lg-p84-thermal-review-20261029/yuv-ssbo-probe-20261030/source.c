/* Standalone API24 SSBO capability probe. Own EGL contexts only.
 * RGB SSBO execution, YUV shader compilation, and YUV SSBO execution are
 * distinct results. Failure to create the ImageReader window never passes
 * the YUV execution gate. No display/system settings or media are touched. */
#define _DEFAULT_SOURCE
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES3/gl31.h>
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

enum { W=16, H=16, PIXELS=W*H, WORDS=PIXELS*5 };
struct probe {
 FILE *out; EGLDisplay d; EGLContext c; EGLSurface s; AImageReader *reader;
 GLuint vao, ssbo, rgb, yuv; GLsync fence; bool current, cleanup_ok;
 bool rgb_executed, yuv_compiled, yuv_executed; int frag_blocks, bindings;
 GLint64 max_block; uint64_t coverage_bad, payload_bad; const char *stage;
 char error[512]; GLenum gl_error; EGLint egl_error;
};
static void persist(struct probe *p) { fflush(p->out); fsync(fileno(p->out)); }
static bool fail(struct probe *p,const char *reason) {
 snprintf(p->error,sizeof(p->error),"%s",reason); return false;
}
static bool glok(struct probe *p,const char *where) {
 GLenum e=glGetError(); if(!e)return true;
 p->gl_error=e;snprintf(p->error,sizeof(p->error),"%s GL=0x%x",where,e);return false;
}
static bool eglok(struct probe *p,EGLBoolean ok,const char *where) {
 EGLint e=eglGetError();fprintf(p->out,"egl_call=%s ok=%d error=0x%x\n",where,ok,e);persist(p);
 if(ok&&e==EGL_SUCCESS)return true;p->egl_error=e;return fail(p,where);
}
static const char *vs="#version 310 es\nvoid main(){float x=float((gl_VertexID&1)<<2)-1.;float y=float((gl_VertexID&2)<<1)-1.;gl_Position=vec4(x,y,0.,1.);}";
static GLuint shader(struct probe *p,GLenum type,const char *text) {
 GLuint s=glCreateShader(type);glShaderSource(s,1,&text,NULL);glCompileShader(s);GLint ok=0;glGetShaderiv(s,GL_COMPILE_STATUS,&ok);
 if(!ok){char log[2048]={0};glGetShaderInfoLog(s,sizeof(log),NULL,log);fprintf(p->out,"shader_error=%s\n",log);persist(p);glDeleteShader(s);fail(p,"shader compile failed");return 0;}return s;
}
static GLuint program(struct probe *p,bool yuv) {
 char fs[4096];snprintf(fs,sizeof(fs),
 "#version 310 es\n%s precision highp float;precision highp int;\n"
 "layout(std430,binding=0) buffer Capture{uint data[];};\n%s"
 "void main(){ivec2 pos=ivec2(gl_FragCoord.xy);uint i=uint(pos.y*16+pos.x);"
 "vec3 v=vec3((pos.x&1)==0?0.25:0.75,(pos.y&1)==0?0.125:0.875,0.5);"
 "uint prior=atomicAdd(data[i*5u],1u);if(prior==0u){data[i*5u+1u]=floatBitsToUint(v.r);data[i*5u+2u]=floatBitsToUint(v.g);data[i*5u+3u]=floatBitsToUint(v.b);data[i*5u+4u]=0xa5000000u|i;}%s}",
 yuv?"#extension GL_EXT_YUV_target : require\n":"",
 yuv?"layout(yuv) out highp vec3 color;\n":"layout(location=0) out highp vec4 color;\n",
 yuv?"color=v;":"color=vec4(v,1.0);");
 GLuint v=shader(p,GL_VERTEX_SHADER,vs),f=v?shader(p,GL_FRAGMENT_SHADER,fs):0,pr=0;
 if(v&&f){pr=glCreateProgram();glAttachShader(pr,v);glAttachShader(pr,f);glLinkProgram(pr);GLint ok=0;glGetProgramiv(pr,GL_LINK_STATUS,&ok);if(!ok){char log[2048]={0};glGetProgramInfoLog(pr,sizeof(log),NULL,log);fprintf(p->out,"link_error=%s\n",log);persist(p);glDeleteProgram(pr);pr=0;fail(p,"program link failed");}}
 if(v)glDeleteShader(v);if(f)glDeleteShader(f);return pr;
}
static bool caps(struct probe *p) {
 const char *version=(const char *)glGetString(GL_VERSION),*ext=(const char *)glGetString(GL_EXTENSIONS);
 fprintf(p->out,"renderer=%s version=%s glsl=%s\n",glGetString(GL_RENDERER),version,glGetString(GL_SHADING_LANGUAGE_VERSION));
 GLint major=0,minor=0;glGetIntegerv(GL_MAJOR_VERSION,&major);glGetIntegerv(GL_MINOR_VERSION,&minor);
 if(major<3||(major==3&&minor<1))return fail(p,"actual GLES3.1 required");
 glGetIntegerv(GL_MAX_FRAGMENT_SHADER_STORAGE_BLOCKS,&p->frag_blocks);glGetIntegerv(GL_MAX_SHADER_STORAGE_BUFFER_BINDINGS,&p->bindings);glGetInteger64v(GL_MAX_SHADER_STORAGE_BLOCK_SIZE,&p->max_block);
 fprintf(p->out,"fragment_ssbo_blocks=%d ssbo_bindings=%d max_block_bytes=%lld required_bytes=%zu yuv_extension=%d\n",p->frag_blocks,p->bindings,(long long)p->max_block,sizeof(uint32_t)*WORDS,ext&&strstr(ext,"GL_EXT_YUV_target")!=NULL);persist(p);
 if(!glok(p,"limits")||p->frag_blocks<1||p->bindings<1||p->max_block<(GLint64)(sizeof(uint32_t)*WORDS))return fail(p,"fragment SSBO limits insufficient");
 return true;
}
static bool resources(struct probe *p) {
 glGenVertexArrays(1,&p->vao);glBindVertexArray(p->vao);glGenBuffers(1,&p->ssbo);glBindBuffer(GL_SHADER_STORAGE_BUFFER,p->ssbo);
 glBufferData(GL_SHADER_STORAGE_BUFFER,sizeof(uint32_t)*WORDS,NULL,GL_STREAM_READ);glBindBufferBase(GL_SHADER_STORAGE_BUFFER,0,p->ssbo);
 glViewport(0,0,W,H);glDisable(GL_BLEND);glDisable(GL_DEPTH_TEST);glDisable(GL_STENCIL_TEST);glDisable(GL_CULL_FACE);glDisable(GL_SCISSOR_TEST);glDisable(GL_DITHER);
 return glok(p,"resources");
}
static uint32_t bits(float f) {uint32_t r;memcpy(&r,&f,sizeof(r));return r;}
static bool draw_read(struct probe *p,GLuint prog,bool yuv) {
 uint32_t zero[WORDS]={0};glBindBuffer(GL_SHADER_STORAGE_BUFFER,p->ssbo);glBufferSubData(GL_SHADER_STORAGE_BUFFER,0,sizeof(zero),zero);glBindBufferBase(GL_SHADER_STORAGE_BUFFER,0,p->ssbo);
 glBindFramebuffer(GL_FRAMEBUFFER,0);glUseProgram(prog);glDrawArrays(GL_TRIANGLES,0,3);
 if(!glok(p,"draw"))return false;
 glMemoryBarrier(GL_BUFFER_UPDATE_BARRIER_BIT|GL_SHADER_STORAGE_BARRIER_BIT);p->fence=glFenceSync(GL_SYNC_GPU_COMMANDS_COMPLETE,0);glFlush();
 if(!p->fence||!glok(p,"barrier/fence"))return fail(p,"fence creation failed");
 bool signaled=false;for(int i=0;i<500;i++){GLenum s=glClientWaitSync(p->fence,0,0);if(s==GL_ALREADY_SIGNALED||s==GL_CONDITION_SATISFIED){signaled=true;break;}if(s==GL_WAIT_FAILED)return fail(p,"fence wait failed");usleep(10000);}
 if(!signaled)return fail(p,"async fence timeout");
 glDeleteSync(p->fence);p->fence=NULL;
 uint32_t *v=glMapBufferRange(GL_SHADER_STORAGE_BUFFER,0,sizeof(zero),GL_MAP_READ_BIT);if(!v)return fail(p,"SSBO map failed");
 uint64_t bad_count=0,bad_payload=0;for(int y=0;y<H;y++)for(int x=0;x<W;x++){int i=y*W+x;bad_count+=v[i*5]!=1;bad_payload+=v[i*5+1]!=bits((x&1)?0.75f:0.25f)||v[i*5+2]!=bits((y&1)?0.875f:0.125f)||v[i*5+3]!=bits(0.5f)||v[i*5+4]!=(0xa5000000u|(uint32_t)i);}
 GLboolean unmapped=glUnmapBuffer(GL_SHADER_STORAGE_BUFFER);p->coverage_bad+=bad_count;p->payload_bad+=bad_payload;
 fprintf(p->out,"execution=%s pixels=%d coverage_bad=%llu payload_bad=%llu unmap=%u\n",yuv?"yuv":"rgb",PIXELS,(unsigned long long)bad_count,(unsigned long long)bad_payload,unmapped);persist(p);
 if(!unmapped||!glok(p,"readback")||bad_count||bad_payload)return fail(p,"SSBO coverage/payload/readback failed");
 return true;
}
static bool release_context(struct probe *p) {
 bool ok=true;if(p->current){if(p->fence)glDeleteSync(p->fence);if(p->rgb)glDeleteProgram(p->rgb);if(p->yuv)glDeleteProgram(p->yuv);if(p->ssbo)glDeleteBuffers(1,&p->ssbo);if(p->vao)glDeleteVertexArrays(1,&p->vao);if(!glok(p,"cleanup GL"))ok=false;if(!eglMakeCurrent(p->d,EGL_NO_SURFACE,EGL_NO_SURFACE,EGL_NO_CONTEXT))ok=false;}
 p->current=false;p->fence=NULL;p->rgb=p->yuv=p->ssbo=p->vao=0;
 if(p->s!=EGL_NO_SURFACE&&!eglDestroySurface(p->d,p->s))ok=false;if(p->c!=EGL_NO_CONTEXT&&!eglDestroyContext(p->d,p->c))ok=false;p->s=EGL_NO_SURFACE;p->c=EGL_NO_CONTEXT;return ok;
}
static bool setup_rgb(struct probe *p) {
 p->stage="rgb-pbuffer";EGLint at[]={EGL_SURFACE_TYPE,EGL_PBUFFER_BIT,EGL_RENDERABLE_TYPE,EGL_OPENGL_ES3_BIT_KHR,EGL_RED_SIZE,8,EGL_GREEN_SIZE,8,EGL_BLUE_SIZE,8,EGL_NONE};EGLConfig cfg;EGLint n=0;
 if(!eglChooseConfig(p->d,at,&cfg,1,&n)||n!=1)return fail(p,"RGB pbuffer config unavailable");
 EGLint ca[]={EGL_CONTEXT_CLIENT_VERSION,3,EGL_NONE},pa[]={EGL_WIDTH,W,EGL_HEIGHT,H,EGL_NONE};p->c=eglCreateContext(p->d,cfg,EGL_NO_CONTEXT,ca);if(!eglok(p,p->c!=EGL_NO_CONTEXT,"rgb-context"))return false;
 p->s=eglCreatePbufferSurface(p->d,cfg,pa);if(!eglok(p,p->s!=EGL_NO_SURFACE,"rgb-pbuffer"))return false;
 if(!eglok(p,eglMakeCurrent(p->d,p->s,p->s,p->c),"rgb-current"))return false;p->current=true;
 if(!caps(p)||!resources(p))return false;p->rgb=program(p,false);if(!p->rgb||!draw_read(p,p->rgb,false))return false;p->rgb_executed=true;
 const char *ext=(const char *)glGetString(GL_EXTENSIONS);if(!ext||!strstr(ext,"GL_EXT_YUV_target"))return fail(p,"YUV extension unavailable");
 p->stage="yuv-ssbo-compile-on-rgb-context";p->yuv=program(p,true);p->yuv_compiled=p->yuv!=0;fprintf(p->out,"yuv_ssbo_compiled_on_rgb_context=%d yuv_executed=0\n",p->yuv_compiled);persist(p);return p->yuv_compiled&&glok(p,"YUV compile");
}
static bool setup_yuv(struct probe *p) {
 p->stage="yuv-window";if(AImageReader_new(W,H,AIMAGE_FORMAT_YUV_420_888,2,&p->reader)!=AMEDIA_OK)return fail(p,"YUV ImageReader unavailable");ANativeWindow *w=NULL;if(AImageReader_getWindow(p->reader,&w)!=AMEDIA_OK||!w)return fail(p,"ImageReader window unavailable");
 EGLint n=0;if(!eglGetConfigs(p->d,NULL,0,&n)||n<1||n>4096)return fail(p,"config enumeration failed");EGLConfig *all=calloc((size_t)n,sizeof(*all)),cfg=NULL;if(!all)return fail(p,"config allocation failed");
 if(eglGetConfigs(p->d,all,n,&n))for(int i=0;i<n;i++){EGLint id=0,visual=0;eglGetConfigAttrib(p->d,all[i],EGL_CONFIG_ID,&id);eglGetConfigAttrib(p->d,all[i],EGL_NATIVE_VISUAL_ID,&visual);if(id==49&&visual==0x7fa30c04){cfg=all[i];break;}}free(all);if(!cfg)return fail(p,"LG config49 absent");
 int rc=ANativeWindow_setBuffersGeometry(w,W,H,0x7fa30c04);fprintf(p->out,"yuv_geometry_rc=%d actual=%d:%d:0x%x\n",rc,ANativeWindow_getWidth(w),ANativeWindow_getHeight(w),ANativeWindow_getFormat(w));persist(p);if(rc)return fail(p,"YUV geometry failed");
 EGLint ca[]={EGL_CONTEXT_FLAGS_KHR,0,EGL_CONTEXT_CLIENT_VERSION,2,EGL_NONE};p->c=eglCreateContext(p->d,cfg,EGL_NO_CONTEXT,ca);EGLint e=eglGetError();fprintf(p->out,"yuv-context-primary=%d error=0x%x\n",p->c!=EGL_NO_CONTEXT,e);persist(p);
 if(p->c==EGL_NO_CONTEXT){p->c=eglCreateContext(p->d,cfg,EGL_NO_CONTEXT,&ca[2]);if(!eglok(p,p->c!=EGL_NO_CONTEXT,"yuv-context-fallback"))return false;}else if(e!=EGL_SUCCESS){p->egl_error=e;return fail(p,"YUV context error");}
 p->s=eglCreateWindowSurface(p->d,cfg,w,NULL);if(!eglok(p,p->s!=EGL_NO_SURFACE,"yuv-window-surface"))return false;
 if(!eglok(p,eglMakeCurrent(p->d,p->s,p->s,p->c),"yuv-current"))return false;p->current=true;
 if(!caps(p)||!resources(p))return false;p->yuv=program(p,true);if(!p->yuv)return false;
 p->stage="yuv-ssbo-execute";if(!draw_read(p,p->yuv,true))return false;p->yuv_executed=true;return true;
}
int main(int argc,char **argv) {
 if(argc!=2){fprintf(stderr,"usage: %s /new/result.txt\n",argv[0]);return 64;}int fd=open(argv[1],O_CREAT|O_EXCL|O_WRONLY|O_CLOEXEC,0600);if(fd<0){perror("exclusive result");return 73;}FILE *out=fdopen(fd,"w");if(!out){close(fd);return 74;}alarm(30);
 struct probe p={.out=out,.d=EGL_NO_DISPLAY,.c=EGL_NO_CONTEXT,.s=EGL_NO_SURFACE,.stage="startup"};fprintf(out,"status=running completed=0 pid=%ld\n",(long)getpid());persist(&p);
 p.d=eglGetDisplay(EGL_DEFAULT_DISPLAY);bool ok=p.d!=EGL_NO_DISPLAY&&eglok(&p,eglInitialize(p.d,NULL,NULL),"initialize")&&eglok(&p,eglBindAPI(EGL_OPENGL_ES_API),"bind-api");
 if(ok)ok=setup_rgb(&p);bool released=release_context(&p);if(ok&&released)ok=setup_yuv(&p);else ok=false;
 p.cleanup_ok=release_context(&p)&&released;if(p.reader)AImageReader_delete(p.reader);if(p.d!=EGL_NO_DISPLAY&&!eglTerminate(p.d))p.cleanup_ok=false;
 fprintf(out,"status=%s completed=%d cleanup=%d rgb_ssbo_executed=%d yuv_ssbo_compiled=%d yuv_ssbo_executed=%d stage=%s\n",ok&&p.cleanup_ok?"pass-on-tested-synthetic-yuv-ssbo-only":"unsupported-or-error",ok,p.cleanup_ok,p.rgb_executed,p.yuv_compiled,p.yuv_executed,p.stage);
 fprintf(out,"error=%s gl_error=0x%x egl_error=0x%x coverage_bad=%llu payload_bad=%llu\n",p.error,p.gl_error,p.egl_error,(unsigned long long)p.coverage_bad,(unsigned long long)p.payload_bad);
 fprintf(out,"limits=synthetic-capability-only;RGB-execution-or-shader-compilation-is-not-YUV-execution;not-playback;not-raw-NV12;not-panel;not-performance\n");persist(&p);bool written=!ferror(out)&&!fflush(out)&&!fsync(fd);if(fclose(out))written=false;alarm(0);return !written?74:ok&&p.cleanup_ok?0:2;
}
