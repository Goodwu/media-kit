/* Host-only EGL/GLES doubles for the full PQ probe main.  No GPU is used. */
#ifndef LG_PQ_LUT_HOST_GL_H
#define LG_PQ_LUT_HOST_GL_H

#include <stddef.h>
#include <stdint.h>

typedef unsigned int GLenum;
typedef unsigned int GLuint;
typedef int GLint;
typedef int GLsizei;
typedef unsigned char GLboolean;
typedef float GLfloat;
typedef uint64_t GLuint64;
typedef void *EGLDisplay;
typedef void *EGLContext;
typedef void *EGLSurface;
typedef void *EGLConfig;
typedef int EGLint;
typedef unsigned int EGLBoolean;
typedef void (*EGLProc)(void);
void *lg_pq_host_malloc(size_t size);
void *lg_pq_host_sample_malloc(int index, size_t size);
void lg_pq_host_free(void *ptr);
#define GL_APIENTRY
#define EGL_DEFAULT_DISPLAY ((void *)0)
#define EGL_NO_CONTEXT ((void *)0)
#define EGL_NO_SURFACE ((void *)0)
#define EGL_SURFACE_TYPE 1
#define EGL_PBUFFER_BIT 2
#define EGL_RENDERABLE_TYPE 3
#define EGL_OPENGL_ES3_BIT 4
#define EGL_NONE 5
#define EGL_CONTEXT_CLIENT_VERSION 6
#define EGL_WIDTH 7
#define EGL_HEIGHT 8
#define GL_NO_ERROR 0
#define GL_RENDERER 1
#define GL_VERSION 2
#define GL_EXTENSIONS 3
#define GL_VERTEX_SHADER 4
#define GL_FRAGMENT_SHADER 5
#define GL_COMPILE_STATUS 6
#define GL_LINK_STATUS 7
#define GL_TEXTURE_2D 8
#define GL_RGBA16F 9
#define GL_RGBA 10
#define GL_HALF_FLOAT 11
#define GL_TEXTURE_MIN_FILTER 12
#define GL_TEXTURE_MAG_FILTER 13
#define GL_NEAREST 14
#define GL_R16F 15
#define GL_RED 16
#define GL_LINEAR 17
#define GL_TEXTURE_WRAP_S 18
#define GL_TEXTURE_WRAP_T 19
#define GL_CLAMP_TO_EDGE 20
#define GL_FRAMEBUFFER 21
#define GL_COLOR_ATTACHMENT0 22
#define GL_FRAMEBUFFER_COMPLETE 23
#define GL_SCISSOR_TEST 24
#define GL_BLEND 25
#define GL_DEPTH_TEST 26
#define GL_STENCIL_TEST 27
#define GL_CULL_FACE 28
#define GL_RASTERIZER_DISCARD 29
#define GL_DITHER 30
#define GL_TRUE 1
#define GL_PIXEL_PACK_BUFFER 31
#define GL_PACK_ALIGNMENT 32
#define GL_PACK_ROW_LENGTH 33
#define GL_PACK_SKIP_PIXELS 34
#define GL_PACK_SKIP_ROWS 35
#define GL_COLOR 36
#define GL_TRIANGLES 37
#define GL_FLOAT 38
#define GL_TEXTURE0 39
#define GL_TEXTURE1 40

EGLDisplay eglGetDisplay(void *native);
EGLBoolean eglInitialize(EGLDisplay d, EGLint *major, EGLint *minor);
EGLBoolean eglChooseConfig(EGLDisplay d, const EGLint *attrs, EGLConfig *cfg,
                           EGLint count, EGLint *found);
EGLContext eglCreateContext(EGLDisplay d, EGLConfig cfg, EGLContext share,
                            const EGLint *attrs);
EGLSurface eglCreatePbufferSurface(EGLDisplay d, EGLConfig cfg, const EGLint *attrs);
EGLBoolean eglMakeCurrent(EGLDisplay d, EGLSurface draw, EGLSurface read, EGLContext ctx);
EGLBoolean eglTerminate(EGLDisplay d);
EGLProc eglGetProcAddress(const char *name);
GLenum glGetError(void);
const unsigned char *glGetString(GLenum name);
void glGetIntegerv(GLenum name, GLint *value);
GLuint glCreateShader(GLenum type);
void glShaderSource(GLuint shader, GLsizei count, const char *const *source, const GLint *length);
void glCompileShader(GLuint shader);
void glGetShaderiv(GLuint shader, GLenum name, GLint *value);
void glGetShaderInfoLog(GLuint shader, GLsizei size, GLsizei *length, char *log);
void glDeleteShader(GLuint shader);
GLuint glCreateProgram(void);
void glAttachShader(GLuint program, GLuint shader);
void glLinkProgram(GLuint program);
void glGetProgramiv(GLuint program, GLenum name, GLint *value);
void glGetProgramInfoLog(GLuint program, GLsizei size, GLsizei *length, char *log);
void glDeleteProgram(GLuint program);
GLint glGetUniformLocation(GLuint program, const char *name);
void glGenTextures(GLsizei count, GLuint *ids);
void glBindTexture(GLenum target, GLuint texture);
void glTexStorage2D(GLenum target, GLsizei levels, GLenum format, GLsizei width, GLsizei height);
void glTexSubImage2D(GLenum target, GLint level, GLint x, GLint y, GLsizei width,
                     GLsizei height, GLenum format, GLenum type, const void *pixels);
void glTexParameteri(GLenum target, GLenum name, GLint value);
void glGenFramebuffers(GLsizei count, GLuint *ids);
void glBindFramebuffer(GLenum target, GLuint framebuffer);
void glFramebufferTexture2D(GLenum target, GLenum attachment, GLenum textarget,
                            GLuint texture, GLint level);
GLenum glCheckFramebufferStatus(GLenum target);
void glViewport(GLint x, GLint y, GLsizei width, GLsizei height);
void glDisable(GLenum capability);
void glColorMask(GLboolean r, GLboolean g, GLboolean b, GLboolean a);
void glBindBuffer(GLenum target, GLuint buffer);
void glPixelStorei(GLenum name, GLint value);
void glReadBuffer(GLenum buffer);
void glDrawBuffers(GLsizei count, const GLenum *buffers);
void glClearBufferfv(GLenum buffer, GLint drawbuffer, const GLfloat *value);
void glUseProgram(GLuint program);
void glUniform1i(GLint location, GLint value);
void glDrawArrays(GLenum mode, GLint first, GLsizei count);
void glReadPixels(GLint x, GLint y, GLsizei width, GLsizei height,
                  GLenum format, GLenum type, void *pixels);
void glActiveTexture(GLenum texture);
void glFlush(void);

#endif
