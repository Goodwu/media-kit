#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES3/gl3.h>
#include <GLES2/gl2ext.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#define TIME_ELAPSED_EXT 0x88BF
#define GPU_DISJOINT_EXT 0x8FBB
#define QUERY_COUNTER_BITS_EXT 0x8864
int main(void) {
 alarm(20);
 EGLDisplay d=eglGetDisplay(EGL_DEFAULT_DISPLAY); EGLint maj=0,min=0,n=0;
 if(d==EGL_NO_DISPLAY||!eglInitialize(d,&maj,&min)){puts("egl_init_failed");return 2;}
 EGLint ca[]={EGL_SURFACE_TYPE,EGL_PBUFFER_BIT,EGL_RENDERABLE_TYPE,EGL_OPENGL_ES3_BIT_KHR,EGL_RED_SIZE,8,EGL_GREEN_SIZE,8,EGL_BLUE_SIZE,8,EGL_NONE}; EGLConfig cfg;
 if(!eglChooseConfig(d,ca,&cfg,1,&n)||n!=1){puts("config_failed");return 2;}
 EGLint pa[]={EGL_WIDTH,256,EGL_HEIGHT,256,EGL_NONE},ctxa[]={EGL_CONTEXT_CLIENT_VERSION,3,EGL_NONE};
 EGLSurface s=eglCreatePbufferSurface(d,cfg,pa); EGLContext c=eglCreateContext(d,cfg,EGL_NO_CONTEXT,ctxa);
 if(s==EGL_NO_SURFACE||c==EGL_NO_CONTEXT||!eglMakeCurrent(d,s,s,c)){puts("context_failed");return 2;}
 const char *ext=(const char *)glGetString(GL_EXTENSIONS);printf("renderer=%s timer_extension=%d\n",glGetString(GL_RENDERER),ext&&strstr(ext,"GL_EXT_disjoint_timer_query")!=NULL);
 PFNGLGENQUERIESEXTPROC gen=(PFNGLGENQUERIESEXTPROC)eglGetProcAddress("glGenQueriesEXT");
 PFNGLDELETEQUERIESEXTPROC del=(PFNGLDELETEQUERIESEXTPROC)eglGetProcAddress("glDeleteQueriesEXT");
 PFNGLBEGINQUERYEXTPROC begin=(PFNGLBEGINQUERYEXTPROC)eglGetProcAddress("glBeginQueryEXT");
 PFNGLENDQUERYEXTPROC end=(PFNGLENDQUERYEXTPROC)eglGetProcAddress("glEndQueryEXT");
 PFNGLGETQUERYIVEXTPROC info=(PFNGLGETQUERYIVEXTPROC)eglGetProcAddress("glGetQueryivEXT");
 PFNGLGETQUERYOBJECTUIVEXTPROC get=(PFNGLGETQUERYOBJECTUIVEXTPROC)eglGetProcAddress("glGetQueryObjectuivEXT");
 PFNGLGETQUERYOBJECTUI64VEXTPROC get64=(PFNGLGETQUERYOBJECTUI64VEXTPROC)eglGetProcAddress("glGetQueryObjectui64vEXT");
 if(!gen||!del||!begin||!end||!info||!get||!get64||!ext||!strstr(ext,"GL_EXT_disjoint_timer_query")){puts("functions_unavailable");return 2;}
 GLint bits=0;info(TIME_ELAPSED_EXT,QUERY_COUNTER_BITS_EXT,&bits);printf("elapsed_counter_bits=%d\n",bits); if(bits<=0)return 2;
 GLuint q=0,ready=0;gen(1,&q);begin(TIME_ELAPSED_EXT,q);for(int i=0;i<256;i++){glClearColor((float)i/256,0.3f,0.7f,1);glClear(GL_COLOR_BUFFER_BIT);}end(TIME_ELAPSED_EXT);glFlush();
 for(int i=0;i<500&&!ready;i++){get(q,GL_QUERY_RESULT_AVAILABLE,&ready);if(!ready)usleep(10000);}
 GLint disjoint=1;glGetIntegerv(GPU_DISJOINT_EXT,&disjoint);GLuint64EXT ns=0;if(ready)get64(q,GL_QUERY_RESULT,&ns);GLenum err=glGetError();printf("ready=%u disjoint=%d elapsed_ns=%llu gl_error=%u\n",ready,disjoint,(unsigned long long)ns,err);
 del(1,&q);eglMakeCurrent(d,EGL_NO_SURFACE,EGL_NO_SURFACE,EGL_NO_CONTEXT);eglDestroyContext(d,c);eglDestroySurface(d,s);eglTerminate(d);return ready&&!disjoint&&!err&&ns>0?0:3;
}
