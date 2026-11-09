/* Deterministic control-flow doubles, not an EGL/GLES implementation. */
#include "lg_pq_lut_host_gl.h"

#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define EXPECTED_TIMING_DRAWS (3 * 6 * (30 + 120))

static GLuint next_id = 1, program, canary_program, current_program;
static GLuint source_texture, output_texture, framebuffer, attached_texture;
static GLuint bound_framebuffer, textures[2];
static int active_texture, viewport_w, viewport_h, output_w, output_h;
static int source_unit=-1, lut_unit=-1, disabled, color_mask, pack_buffer=-1;
static int pack_state, read_buffer, draw_buffer;
static GLint phase, current_mode;
static int clears, draws, reads, timing_draws, timing_started, program_deleted;
static int accuracy_draws, accuracy_reads, query_generated, query_begun, query_deleted;
static int egl_terminated, egl_detached, bad_attempts;
static int failure, stop_requested;
static void *allocations[32];
static int allocation_count, free_count, allocation_attempts, failed_allocation;
static int sample_attempts, sample_failed = -1;
static GLuint live_queries[128];
static int live_query_count, cleanup_errors;
static EGLDisplay initialized_display, context_display;
static EGLContext created_context, current_context;
static int display_terminated;

#define HOST_DISPLAY ((EGLDisplay)(uintptr_t)1)
#define HOST_CONTEXT ((EGLContext)(uintptr_t)2)
#define HOST_SURFACE ((EGLSurface)(uintptr_t)3)

/* Used only when the host test redirects the probe's malloc/free calls. */
void *lg_pq_host_malloc(size_t size)
{
    allocation_attempts++;
    const char *fail=getenv("LG_PQ_HOST_FAIL_ALLOC");
    if (fail && atoi(fail)==allocation_attempts) {
        failed_allocation=allocation_attempts;
        return NULL;
    }
    void *ptr=malloc(size);
    if (ptr) {
        if (allocation_count >= (int)(sizeof(allocations)/sizeof(allocations[0]))) abort();
        allocations[allocation_count++]=ptr;
    }
    return ptr;
}
void *lg_pq_host_sample_malloc(int index, size_t size)
{
    sample_attempts++;
    const char *fail = getenv("LG_PQ_HOST_FAIL_SAMPLE");
    if (fail && atoi(fail) == index) {
        sample_failed = index;
        return NULL;
    }
    return lg_pq_host_malloc(size);
}
void lg_pq_host_free(void *ptr)
{
    if (!ptr) return;
    for (int i=allocation_count-1;i>=0;i--) {
        if (allocations[i]==ptr) {
            allocations[i]=NULL;
            free_count++;
            free(ptr);
            return;
        }
    }
    failure=1;
}

static void dump_trace(void)
{
    const char *path = getenv("LG_PQ_HOST_TRACE");
    if (!path) return;
    FILE *file = fopen(path, "w");
    if (!file) abort();
    fprintf(file, "clears=%d draws=%d reads=%d timing_draws=%d deleted=%d failure=%d "
                  "framebuffer=%u bound_fbo=%u attachment=%u output=%u source=%u "
                  "bound_source=%u source_unit=%d lut_unit=%d accuracy_draws=%d "
                  "accuracy_reads=%d query_generated=%d query_begun=%d query_deleted=%d "
                  "terminated=%d detached=%d bad_attempts=%d allocated=%d freed=%d "
                  "alloc_attempts=%d alloc_failed=%d sample_attempts=%d sample_failed=%d "
                  "query_live=%d cleanup_errors=%d current=%d\n",
            clears, draws, reads, timing_draws, program_deleted, failure, framebuffer,
            bound_framebuffer, attached_texture, output_texture, source_texture,
            textures[0], source_unit, lut_unit, accuracy_draws, accuracy_reads,
            query_generated, query_begun, query_deleted, egl_terminated, egl_detached,
            bad_attempts, allocation_count, free_count, allocation_attempts, failed_allocation,
            sample_attempts, sample_failed, live_query_count, cleanup_errors,
            current_context != EGL_NO_CONTEXT);
    fclose(file);
}

static int require(int condition)
{
    if (!condition) failure = 1;
    return condition;
}

EGLDisplay eglGetDisplay(void *native) { (void)native; atexit(dump_trace); return HOST_DISPLAY; }
EGLBoolean eglInitialize(EGLDisplay d, EGLint *major, EGLint *minor)
{ (void)major; (void)minor; initialized_display=d; return 1; }
EGLBoolean eglChooseConfig(EGLDisplay d, const EGLint *a, EGLConfig *cfg,
                           EGLint n, EGLint *found)
{ (void)d; (void)a; (void)n; *cfg=(void *)1; *found=1; return 1; }
EGLContext eglCreateContext(EGLDisplay d, EGLConfig c, EGLContext s, const EGLint *a)
{
    (void)c; (void)s; (void)a;
    if (d != initialized_display || !d || display_terminated) {
        cleanup_errors++;
        return EGL_NO_CONTEXT;
    }
    context_display=d;
    return created_context=HOST_CONTEXT;
}
EGLSurface eglCreatePbufferSurface(EGLDisplay d, EGLConfig c, const EGLint *a)
{ (void)d; (void)c; (void)a; return HOST_SURFACE; }
EGLBoolean eglMakeCurrent(EGLDisplay d, EGLSurface draw, EGLSurface read, EGLContext c)
{
    if (d != initialized_display || !d || display_terminated) {
        cleanup_errors++;
        return 0;
    }
    if (draw==EGL_NO_SURFACE && read==EGL_NO_SURFACE && c==EGL_NO_CONTEXT) {
        egl_detached++;
        current_context=EGL_NO_CONTEXT;
        return 1;
    }
    if (draw!=HOST_SURFACE || read!=HOST_SURFACE || c!=created_context || d!=context_display) {
        cleanup_errors++;
        return 0;
    }
    current_context=c;
    return 1;
}
EGLBoolean eglTerminate(EGLDisplay d)
{
    if (d != initialized_display || !d || display_terminated) {
        cleanup_errors++;
        return 0;
    }
    if (current_context != EGL_NO_CONTEXT)
        cleanup_errors++; /* This probe's local cleanup contract detaches first. */
    egl_terminated++;
    display_terminated=1;
    return 1;
}
GLenum glGetError(void) { return failure || stop_requested ? 1 : GL_NO_ERROR; }
const unsigned char *glGetString(GLenum name)
{
    if (name == GL_RENDERER) return (const unsigned char *)"host double";
    if (name == GL_VERSION) return (const unsigned char *)"OpenGL ES 3.2 host double";
    return (const unsigned char *)"GL_EXT_disjoint_timer_query GL_EXT_color_buffer_float";
}
void glGetIntegerv(GLenum name, GLint *value) { (void)name; *value=0; }

static void query_gen(GLsizei n, GLuint *ids)
{
    query_generated+=n;
    if (current_context != created_context || !current_context || display_terminated) {
        cleanup_errors++;
        while (n--) *ids++=0;
        return;
    }
    while (n--) {
        if (live_query_count >= (int)(sizeof(live_queries)/sizeof(live_queries[0]))) abort();
        *ids=next_id++;
        live_queries[live_query_count++]=*ids++;
    }
}
static void query_del(GLsizei n, const GLuint *ids)
{
    query_deleted+=n;
    if (current_context != created_context || !current_context || display_terminated) {
        cleanup_errors++;
        return;
    }
    while (n--) {
        GLuint id=*ids++;
        if (!id) continue; /* Deleting zero is a no-op, not deletion of a live query. */
        int i=0;
        while (i<live_query_count && live_queries[i]!=id) i++;
        if (i==live_query_count) {
            cleanup_errors++;
            continue;
        }
        live_queries[i]=live_queries[--live_query_count];
    }
}
static void query_begin(GLenum type, GLuint id) { (void)type; (void)id; query_begun++; }
static void query_end(GLenum type) { (void)type; }
static void query_getiv(GLenum type, GLenum name, GLint *out)
{ (void)type; *out=name==0x8864 ? 64 : 0; }
static void query_getuiv(GLuint id, GLenum name, GLuint *out)
{ (void)id; (void)name; *out=1; }
static void query_getu64(GLuint id, GLenum name, GLuint64 *out)
{ (void)id; (void)name; *out=100; }
EGLProc eglGetProcAddress(const char *name)
{
    if (!strcmp(name,"glGenQueriesEXT")) return (EGLProc)query_gen;
    if (!strcmp(name,"glDeleteQueriesEXT")) return (EGLProc)query_del;
    if (!strcmp(name,"glBeginQueryEXT")) return (EGLProc)query_begin;
    if (!strcmp(name,"glEndQueryEXT")) return (EGLProc)query_end;
    if (!strcmp(name,"glGetQueryivEXT")) return (EGLProc)query_getiv;
    if (!strcmp(name,"glGetQueryObjectuivEXT")) return (EGLProc)query_getuiv;
    if (!strcmp(name,"glGetQueryObjectui64vEXT")) return (EGLProc)query_getu64;
    return NULL;
}
GLuint glCreateShader(GLenum type) { (void)type; return next_id++; }
void glShaderSource(GLuint s, GLsizei n, const char *const *src, const GLint *len)
{ (void)s; (void)n; (void)src; (void)len; }
void glCompileShader(GLuint s) { (void)s; }
void glGetShaderiv(GLuint s, GLenum n, GLint *v) { (void)s; (void)n; *v=1; }
void glGetShaderInfoLog(GLuint s, GLsizei n, GLsizei *len, char *log)
{ (void)s; (void)n; (void)len; (void)log; }
void glDeleteShader(GLuint s) { (void)s; }
GLuint glCreateProgram(void)
{
    GLuint id=next_id++;
    if (!program) program=id; else canary_program=id;
    return id;
}
void glAttachShader(GLuint p, GLuint s) { (void)p; (void)s; }
void glLinkProgram(GLuint p) { (void)p; }
void glGetProgramiv(GLuint p, GLenum n, GLint *v) { (void)p; (void)n; *v=1; }
void glGetProgramInfoLog(GLuint p, GLsizei n, GLsizei *len, char *log)
{ (void)p; (void)n; (void)len; (void)log; }
void glDeleteProgram(GLuint p) { if (p==canary_program) program_deleted++; }
GLint glGetUniformLocation(GLuint p, const char *name)
{
    if (p==canary_program && !strcmp(name,"u_phase")) return 7;
    if (p==program && !strcmp(name,"u_src")) return 8;
    if (p==program && !strcmp(name,"u_lut")) return 9;
    if (p==program && !strcmp(name,"u_mode")) return 10;
    return -1;
}
void glGenTextures(GLsizei n, GLuint *ids) { while (n--) *ids++=next_id++; }
void glBindTexture(GLenum t, GLuint id) { require(t==GL_TEXTURE_2D);textures[active_texture]=id; }
void glTexStorage2D(GLenum t, GLsizei l, GLenum f, GLsizei w, GLsizei h)
{
    (void)l; (void)w; (void)h; require(t==GL_TEXTURE_2D && textures[active_texture]);
    if (f==GL_RGBA16F && !source_texture) source_texture=textures[active_texture];
    else if (f==GL_RGBA16F) {
        output_texture=textures[active_texture];output_w=w;output_h=h;
    }
}
void glTexSubImage2D(GLenum t, GLint l, GLint x, GLint y, GLsizei w, GLsizei h,
                     GLenum f, GLenum ty, const void *data)
{ (void)t; (void)l; (void)x; (void)y; (void)w; (void)h; (void)f; (void)ty; (void)data; }
void glTexParameteri(GLenum t, GLenum n, GLint v) { (void)t; (void)n; (void)v; }
void glGenFramebuffers(GLsizei n, GLuint *ids)
{ require(n==1);*ids=framebuffer=next_id++; }
void glBindFramebuffer(GLenum t, GLuint id)
{ require(t==GL_FRAMEBUFFER);bound_framebuffer=id; }
void glFramebufferTexture2D(GLenum t, GLenum a, GLenum tt, GLuint id, GLint l)
{
    require(t==GL_FRAMEBUFFER && a==GL_COLOR_ATTACHMENT0 && tt==GL_TEXTURE_2D &&
            l==0 && bound_framebuffer==framebuffer);
    attached_texture=id;
}
/* Completeness is intentionally reported successful even for a missing
 * attachment, so the trace ledger catches a falsely accepted FBO identity. */
GLenum glCheckFramebufferStatus(GLenum t) { (void)t; return GL_FRAMEBUFFER_COMPLETE; }
void glViewport(GLint x, GLint y, GLsizei w, GLsizei h)
{ require(!x && !y);viewport_w=w;viewport_h=h; }
void glDisable(GLenum cap)
{ if (require(cap>=GL_SCISSOR_TEST && cap<=GL_DITHER)) disabled|=1<<(cap-GL_SCISSOR_TEST); }
void glColorMask(GLboolean r, GLboolean g, GLboolean b, GLboolean a)
{ color_mask=r && g && b && a; }
void glBindBuffer(GLenum t, GLuint b) { require(t==GL_PIXEL_PACK_BUFFER);pack_buffer=(int)b; }
void glPixelStorei(GLenum n, GLint v)
{
    if (require(n>=GL_PACK_ALIGNMENT && n<=GL_PACK_SKIP_ROWS)) {
        if (require(v==(n==GL_PACK_ALIGNMENT ? 4 : 0))) pack_state|=1<<(n-GL_PACK_ALIGNMENT);
    }
}
void glReadBuffer(GLenum b) { read_buffer=b==GL_COLOR_ATTACHMENT0; }
void glDrawBuffers(GLsizei n, const GLenum *b) { draw_buffer=n==1 && *b==GL_COLOR_ATTACHMENT0; }
void glClearBufferfv(GLenum b, GLint d, const GLfloat *v)
{
    require(b==GL_COLOR && !d && v[0]==-2 && v[1]==3 && v[2]==-4 && v[3]==0);
    require(framebuffer && bound_framebuffer==framebuffer && attached_texture==output_texture &&
            output_texture && viewport_w==output_w && viewport_h==output_h && disabled==0x7f &&
            color_mask && !pack_buffer && pack_state==0xf && read_buffer && draw_buffer);
    clears++;phase=0;
}
void glUseProgram(GLuint p) { current_program=p; }
void glUniform1i(GLint loc, GLint value)
{
    if (loc==7) { require(current_program==canary_program);phase=value; }
    if (loc==8) { require(current_program==program);source_unit=value; }
    if (loc==9) { require(current_program==program);lut_unit=value; }
    if (loc==10) { require(current_program==program);current_mode=value; }
}
void glDrawArrays(GLenum mode, GLint first, GLsizei count)
{
    (void)mode; (void)first; (void)count;
    if (current_program==canary_program && !timing_started) {
        require(clears==1 && reads==draws+1 && phase==draws+1);
        draws++;
    } else {
        timing_started=1;
        require(current_program==program && clears==1 && draws==2 && reads==3 && program_deleted==1 &&
                source_unit==0 && lut_unit==1 && source_texture && textures[0]==source_texture &&
                bound_framebuffer==framebuffer && attached_texture==output_texture);
        if (getenv("LG_PQ_HOST_ACCURACY") && timing_draws==EXPECTED_TIMING_DRAWS) {
            accuracy_draws++;
            require(accuracy_draws==accuracy_reads+1 && current_mode>=1 && current_mode<=3);
        } else {
            timing_draws++;
            /* Default mode still stops before timing, preserving the original
             * canary entry-order test. Accuracy mode uses fake query results. */
            if (!getenv("LG_PQ_HOST_ACCURACY")) stop_requested=1;
        }
    }
}
void glReadPixels(GLint x, GLint y, GLsizei w, GLsizei h, GLenum format, GLenum type, void *data)
{
    (void)x; (void)y; (void)format; (void)type;
    float *pixels=data;
    if (timing_started) {
        require(getenv("LG_PQ_HOST_ACCURACY") && timing_draws==EXPECTED_TIMING_DRAWS &&
                accuracy_draws==accuracy_reads+1 && bound_framebuffer==framebuffer &&
                attached_texture==output_texture && w==viewport_w && h==viewport_h);
        const char *read_env=getenv("LG_PQ_HOST_BAD_READ");
        const char *comp_env=getenv("LG_PQ_HOST_BAD_COMPONENT");
        const char *kind=getenv("LG_PQ_HOST_BAD_KIND");
        int bad_read=read_env ? atoi(read_env) : -1;
        int bad_component=comp_env ? atoi(comp_env) : 0;
        size_t total=(size_t)w*(size_t)h*4;
        if (accuracy_reads==bad_read && bad_component>=0 && (size_t)bad_component<total && kind)
            bad_attempts++;
        for (size_t i=0;i<total;i++) {
            if (accuracy_reads==bad_read && i==(size_t)bad_component && kind && !strcmp(kind,"skip"))
                continue;
            pixels[i]=(i%4==3) ? 1.0f : 0.5f;
            if (accuracy_reads==bad_read && i==(size_t)bad_component && kind) {
                if (!strcmp(kind,"nan")) pixels[i]=NAN;
                else if (!strcmp(kind,"inf")) pixels[i]=INFINITY;
                else if (!strcmp(kind,"large")) pixels[i]=1e20f;
            }
        }
        accuracy_reads++;
        return;
    }
    require(clears==1 && draws==reads && phase==reads &&
            bound_framebuffer==framebuffer && attached_texture==output_texture &&
            w==viewport_w && h==viewport_h);
    for (int yy=0;yy<h;yy++) for (int xx=0;xx<w;xx++) {
        size_t i=((size_t)yy*(size_t)w+(size_t)xx)*4;
        if (!phase) { pixels[i]=-2;pixels[i+1]=3;pixels[i+2]=-4;pixels[i+3]=0; }
        else {
            pixels[i]=2+(xx&1)*0.5f+phase*0.25f;
            pixels[i+1]=-1-(yy&1)*0.5f-phase*0.25f;
            pixels[i+2]=4+((xx+yy)&1)*0.5f+phase*0.25f;pixels[i+3]=1;
        }
    }
    reads++;
    const char *bad=getenv("LG_PQ_HOST_BAD_PHASE");
    if (bad && atoi(bad)==phase) pixels[0]+=0.25f;
}
void glActiveTexture(GLenum texture)
{ if (require(texture==GL_TEXTURE0 || texture==GL_TEXTURE1)) active_texture=texture-GL_TEXTURE0; }
void glFlush(void) { }
