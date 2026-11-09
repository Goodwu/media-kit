/* Standalone LG Adreno 530 PQ-encode LUT cost/accuracy probe.
 *
 * Purpose: bound the GPU cost of the analytic ST.2084 encode inside the fused
 * YUV output pass, and measure the accuracy of replacing it with a small 1D
 * LUT (float16 texture, LINEAR, linear or sqrt index domain). This is a
 * decision input for the P84 perf round 2 "PQ small lookup table" track; it
 * is not an APK, not playback, and not a production acceptance artifact.
 *
 * Variants (all share the production tail: mks_half_store + BT.2020 NCL CSC,
 * both copied verbatim from the libplacebo dispatch fusion tail):
 *   identity            texel -> half -> CSC                     (cost floor)
 *   analytic            texel -> PQ encode (2 pow, 1 div) -> ...  (production)
 *   lut<size>-<warp>    texel -> LUT lookup -> ...
 *
 * Timing uses GL_EXT_disjoint_timer_query with a non-blocking ring and
 * interleaved sets to average DVFS drift. Unlike the in-production
 * mks_gpu_timer (whose retirement point is eglSwapBuffers), this standalone
 * probe issues one glFlush per timed batch: a pbuffer has no swap, and the
 * driver never retires the queries without one. This is a deliberately
 * different submission cadence from production, so absolute times are not
 * production times; variant-to-variant comparison is the probe's purpose.
 * Accuracy compares full-screen RGBA16F readbacks of the Y/Cb/Cr output
 * after the half-store RGB and CSC stages, plus a CPU double reference grid.
 * GL_GPU_DISJOINT_EXT is consumed only by this process's context.
 */
#include <float.h>
#include <inttypes.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#define PROBE_W 2672
#define PROBE_H 1336
#define RING 16
#define WARMUP_FRAMES 30
#define TIMED_FRAMES 120
#define SETS 3
#define DRAIN_TIMEOUT_SECONDS 20
#define PQ_DOMAIN 49.26108374384236 /* 10000 / 203 (PL_COLOR_SDR_WHITE) */
#define PQ_SCALE 0.0203             /* 203 / 10000 */

static double lut_domain_value(int index, int size, int warp)
{
    double u = (double)index / (double)(size - 1);
    return PQ_DOMAIN * (warp ? u * u : u);
}

#define GLQ(expr) do { \
    expr; \
    if (gl_error_step()) { \
        fprintf(stderr, "PQLUT verdict=fail reason=gl_error operation=%s\n", #expr); \
        return 2; \
    } \
} while (0)

static const double PQ_M1 = 2610.0 / 4096 / 4;
static const double PQ_M2 = 2523.0 / 4096 * 128;
static const double PQ_C1 = 3424.0 / 4096;
static const double PQ_C2 = 2413.0 / 4096 * 32;
static const double PQ_C3 = 2392.0 / 4096 * 32;

static uint32_t lcg_state = 0x1234abcd;
static uint32_t lcg(void) { lcg_state = lcg_state * 1664525u + 1013904223u; return lcg_state; }

static double src_value(void) /* sequential deterministic draws */
{
    double r = (double)(lcg() >> 8) / 16777216.0;
    return PQ_DOMAIN * (0.85 * pow(r, 8.0) + 0.15 * r);
}


/* ---- CPU half <-> float ---- */
static uint16_t f32_to_f16(double value)
{
    union { float f; uint32_t u; } bits = { (float)value };
    uint32_t raw = bits.u, sign = (raw >> 16) & 0x8000u, mag = raw & 0x7fffffffu;
    if (mag > 0x7f800000u)
        return (uint16_t)(sign | 0x7e00u); /* canonical quiet NaN */
    if (mag >= 0x47800000u)
        return (uint16_t)(sign | 0x7c00u); /* overflow -> inf */
    if (mag < 0x38800000u) { /* zero or subnormal */
        if (mag < 0x33000000u)
            return (uint16_t)sign;
        int e = (int)(mag >> 23) - 127;
        uint32_t h = ((mag & 0x7fffffu) | 0x800000u) >> (unsigned)(-e - 1);
        return (uint16_t)(sign | h);
    }
    int e = (int)(mag >> 23) - 127 + 15;
    uint32_t m10 = (mag >> 13) & 0x3ffu, rem = mag & 0x1fffu;
    if (rem > 0x1000u || (rem == 0x1000u && (m10 & 1u)))
        m10++;
    if (m10 == 0x400u) { m10 = 0; e++; } /* 10-bit mantissa carry: 0x3ff -> 0x400 */
    return (uint16_t)(sign | ((uint32_t)e << 10) | m10);
}

static double f16_to_f32(uint16_t h)
{
    int sign = (h & 0x8000u) ? -1 : 1;
    uint32_t exp = (h >> 10) & 0x1fu, frac = h & 0x3ffu;
    if (exp == 0)
        return sign * ldexp((double)frac, -24);
    if (exp == 31)
        return frac ? NAN : sign * INFINITY;
    return sign * ldexp((double)frac + 1024.0, (int)exp - 25);
}

/* Count representable finite half steps, treating both zeros as one value. */
static int half_ulp_distance(uint16_t a, uint16_t b)
{
    int ma = a & 0x7fffu, mb = b & 0x7fffu;
    int ra = (a & 0x8000u) ? -ma : ma;
    int rb = (b & 0x8000u) ? -mb : mb;
    return abs(ra - rb);
}

/* Reject before the double-to-float cast and before publishing half bits. */
static int checked_half(double value, uint16_t *out)
{
    if (!isfinite(value) || fabs(value) > FLT_MAX)
        return 0;
    uint16_t h = f32_to_f16(value);
    if ((h & 0x7c00u) == 0x7c00u)
        return 0;
    *out = h;
    return 1;
}

static double pq_encode_double(double x)
{
    double v = x * PQ_SCALE;
    if (v < 0) v = 0;
    double p = pow(v, PQ_M1);
    double q = (PQ_C1 + PQ_C2 * p) / (1.0 + PQ_C3 * p);
    return pow(q, PQ_M2);
}

#ifdef LG_PQ_HOST_TEST
/* Host-only CPU self-test: half conversion round trips and ST.2084 anchors
 * (values independently computed in double with the published constants). */
static int host_test(void)
{
    struct { double x, want; } anchors[] = {
        { 0.0, 7.152557373046875e-07 },
        { 1.0, 0.58056640625 },
        { 4.926108374384236, 0.751953125 },
        { 49.26108374384236, 1.0 },
        { 0.1, 0.3583984375 },
        { 10.0, 0.8291015625 },
    };
    int failures = 0;
    uint16_t checked = 0;
    if (half_ulp_distance(0x8001u, 0x0001u) != 2) {
        printf("PQLUT-HOST half_ulp_mismatch\n");
        failures++;
    }
    if (!checked_half(1.0, &checked) || checked != 0x3c00u ||
        checked_half(NAN, &checked) || checked_half(INFINITY, &checked)) {
        printf("PQLUT-HOST checked_half_mismatch\n");
        failures++;
    }
    for (size_t i = 0; i < sizeof(anchors) / sizeof(anchors[0]); i++) {
        double got = f16_to_f32(f32_to_f16(pq_encode_double(anchors[i].x)));
        double exact = pq_encode_double(anchors[i].x);
        if (got != anchors[i].want) {
            printf("PQLUT-HOST anchor_mismatch i=%zu x=%.9f got=%.9g want=%.9g exact=%.9g\n",
                   i, anchors[i].x, got, anchors[i].want, exact);
            failures++;
        }
    }
    /* mantissa carry boundaries (review-found rounding defects) */
    struct { double x; uint16_t want; } carries[] = {
        { 1.99951171875, 0x4000 }, /* 2.0 - 1 ULP(f32 at 2.0) rounds UP to 2.0 */
        { 7.998046875, 0x4800 },   /* 8.0 - 1 ULP rounds UP to 8.0 */
        { 0.99951171875, 0x3bff }, /* 1.0 - 1 ULP(half): exactly representable */
    };
    for (size_t i = 0; i < sizeof(carries) / sizeof(carries[0]); i++) {
        uint16_t got = f32_to_f16(carries[i].x);
        if (got != carries[i].want) {
            printf("PQLUT-HOST carry_mismatch i=%zu x=%.9g got=0x%04x want=0x%04x\n",
                   i, carries[i].x, got, carries[i].want);
            failures++;
        }
    }
    /* half round trip on a spread of values; tolerance = half an ULP of the
     * half format at that magnitude (values finer than one ULP cannot round
     * trip exactly) */
    for (int i = 0; i < 4096; i++) {
        double v = ldexp((double)i, -8);
        uint16_t h = f32_to_f16(v);
        double back = f16_to_f32(h);
        uint16_t h2 = f32_to_f16(back);
        int e = 0;
        frexp(v, &e);
        double ulp = ldexp(1.0, (e > -14 ? e : -14) - 11);
        if (h2 != h || fabs(back - v) > ulp * 0.5) {
            printf("PQLUT-HOST roundtrip_mismatch i=%d\n", i);
            failures++;
        }
    }
    /* fill/reference sequence contract: the fill consumes one random draw per
     * pixel, the four anchors overwrite texels 0-3 AFTER all draws, and the
     * final source value is half-quantized. The CPU reference in the device
     * main must replay exactly this; these five expectations pin it (review
     * regression: anchors unquantized and sequence shifted by four). */
    lcg_state = 0x1234abcd;
    {
        static const double anchors[4] = { 0.0, 1.0, 4.9261, PQ_DOMAIN };
        static const double wants[5] = { 0.0, 1.0, 4.92578125, 49.25, 3.61328125 };
        for (int p = 0; p < 5; p++) {
            double raw = src_value();
            double chosen = (p < 4) ? anchors[p] : raw;
            double got = f16_to_f32(f32_to_f16(chosen));
            if (got != wants[p]) {
                printf("PQLUT-HOST sequence_mismatch p=%d got=%.9g want=%.9g\n",
                       p, got, wants[p]);
                failures++;
            }
        }
    }
    for (int size = 1024; size <= 4096; size *= 4) {
        for (int warp = 0; warp <= 1; warp++) {
            double first = lut_domain_value(0, size, warp);
            double last = lut_domain_value(size - 1, size, warp);
            if (first != 0.0 || last != PQ_DOMAIN ||
                f32_to_f16(pq_encode_double(first)) != f32_to_f16(pq_encode_double(0.0)) ||
                f32_to_f16(pq_encode_double(last)) != f32_to_f16(pq_encode_double(PQ_DOMAIN))) {
                printf("PQLUT-HOST lut_endpoints_mismatch size=%d warp=%d\n", size, warp);
                failures++;
            }
        }
    }
    printf("PQLUT-HOST verdict=%s\n", failures ? "fail" : "pass");
    return failures ? 1 : 0;
}

int main(void) { return host_test(); }
#else /* !LG_PQ_HOST_TEST */

#include <EGL/egl.h>
#include <GLES3/gl31.h>

/* ---- probe state ---- */
static int gl_error_count;
static EGLDisplay display;
static EGLContext context;
static EGLSurface surface;
static struct {
    void (GL_APIENTRY *gen)(GLsizei, GLuint *);
    void (GL_APIENTRY *del)(GLsizei, const GLuint *);
    void (GL_APIENTRY *begin)(GLenum, GLuint);
    void (GL_APIENTRY *end)(GLenum);
    void (GL_APIENTRY *getiv)(GLenum, GLenum, GLint *);
    void (GL_APIENTRY *getuiv)(GLuint, GLenum, GLuint *);
    void (GL_APIENTRY *getu64)(GLuint, GLenum, GLuint64 *);
} q;
static GLuint ring_ids[RING];
static int ring_pending[RING];
static int ring_active = -1;
static uint64_t attempts, issued, results, disjoint_drop;
static uint64_t *collect;
static int collect_cap, collect_n;
static uint64_t stale_drop;

static int gl_error_step(void)
{
    GLenum err = glGetError();
    if (err != GL_NO_ERROR) {
        gl_error_count++;
        fprintf(stderr, "PQLUT gl_error=0x%04x count=%d\n", err, gl_error_count);
    }
    return err != GL_NO_ERROR;
}

static int has_ext(const char *needle)
{
    const char *ext = (const char *)glGetString(GL_EXTENSIONS);
    if (!ext) return 0;
    size_t len = strlen(ext);
    if (len > SIZE_MAX - 4) return 0;
    char *padded = malloc(len + 4);
    if (!padded) return 0;
    snprintf(padded, len + 3, " %s ", ext);
    char framed[128];
    snprintf(framed, sizeof(framed), " %s ", needle);
    int found = strstr(padded, framed) != NULL;
    free(padded);
    return found;
}

static int now_seconds(double *seconds)
{
    struct timespec ts;
    if (clock_gettime(CLOCK_MONOTONIC, &ts) ||
        ts.tv_nsec < 0 || ts.tv_nsec >= 1000000000L)
        return 0;
    *seconds = (double)ts.tv_sec + ts.tv_nsec / 1e9;
    return 1;
}

static int timer_poll(void)
{
    GLint disjoint = 0;
    glGetIntegerv(0x8FBB /* GL_GPU_DISJOINT_EXT */, &disjoint);
    if (gl_error_step()) return 0;
    if (disjoint) {
        disjoint_drop++;
        return 0;
    }
    for (int i = 0; i < RING; i++) {
        if (!ring_pending[i]) continue;
        GLuint ready = 0;
        q.getuiv(ring_ids[i], 0x8867 /* GL_QUERY_RESULT_AVAILABLE */, &ready);
        if (gl_error_step()) return 0;
        if (!ready) continue;
        GLuint64 ns = 0;
        q.getu64(ring_ids[i], 0x8866 /* GL_QUERY_RESULT */, &ns);
        if (gl_error_step()) return 0;
        glGetIntegerv(0x8FBB, &disjoint);
        if (gl_error_step()) return 0;
        if (disjoint) {
            disjoint_drop++;
            return 0;
        }
        if (!ns || !collect || collect_n >= collect_cap) return 0;
        collect[collect_n++] = ns;
        ring_pending[i] = 0;
        results++;
    }
    return 1;
}

static int timer_begin(void)
{
    attempts++;
    GLint current = 0;
    q.getiv(0x88BF /* GL_TIME_ELAPSED_EXT */, 0x8865 /* GL_CURRENT_QUERY_EXT */, &current);
    if (gl_error_step()) return 0;
    if (current || ring_active >= 0) return 0;
    if (!timer_poll()) return 0;
    for (int i = 0; i < RING; i++) {
        if (ring_pending[i]) continue;
        q.begin(0x88BF, ring_ids[i]);
        if (gl_error_step()) return 0;
        ring_active = i;
        issued++;
        return 1;
    }
    return 0;
}

static int timer_end(void)
{
    if (ring_active < 0 || ring_active >= RING || ring_pending[ring_active]) return 0;
    q.end(0x88BF);
    if (gl_error_step()) return 0;
    ring_pending[ring_active] = 1;
    ring_active = -1;
    return 1;
}

static int drain_deadline_check(struct timespec start, struct timespec *last)
{
    struct timespec now;
    if (clock_gettime(CLOCK_MONOTONIC, &now) ||
        now.tv_nsec < 0 || now.tv_nsec >= 1000000000L ||
        now.tv_sec < last->tv_sec ||
        (now.tv_sec == last->tv_sec && now.tv_nsec < last->tv_nsec))
        return -1;
    *last = now;
    if (now.tv_sec - start.tv_sec > DRAIN_TIMEOUT_SECONDS ||
        (now.tv_sec - start.tv_sec == DRAIN_TIMEOUT_SECONDS &&
         now.tv_nsec >= start.tv_nsec))
        return 1;
    return 0;
}

static int drain_all(void)
{
    struct timespec start;
    if (clock_gettime(CLOCK_MONOTONIC, &start) ||
        start.tv_nsec < 0 || start.tv_nsec >= 1000000000L)
        return 0;
    struct timespec last = start;
    for (int guard = 0; guard < 20000; guard++) {
        int deadline = drain_deadline_check(start, &last);
        if (deadline < 0) return 0;
        if (deadline > 0) break;
        if (!timer_poll()) return 0;
        deadline = drain_deadline_check(start, &last);
        if (deadline < 0) return 0;
        if (deadline > 0) break;
        int pending = 0;
        for (int i = 0; i < RING; i++)
            if (ring_pending[i]) pending = 1;
        if (!pending) return 1;
        if (usleep(1000)) return 0;
    }
    for (int i = 0; i < RING; i++)
        if (ring_pending[i]) stale_drop++;
    return 0;
}

/* ---- shaders ---- */
static const char *VS =
    "#version 310 es\n"
    "void main(){ vec2 p=vec2(float((gl_VertexID<<1)&2),float(gl_VertexID&2));"
    " gl_Position=vec4(p*2.0-1.0,0.0,1.0); }\n";

static const char *CANARY_FS =
    "#version 310 es\n"
    "precision highp float;\n"
    "precision highp int;\n"
    "uniform int u_phase;\n"
    "out vec4 o;\n"
    "void main(){ ivec2 p=ivec2(gl_FragCoord.xy);\n"
    "o=vec4(2.0+float(p.x&1)*0.5+float(u_phase)*0.25,\n"
    "       -1.0-float(p.y&1)*0.5-float(u_phase)*0.25,\n"
    "       4.0+float((p.x+p.y)&1)*0.5+float(u_phase)*0.25,1.0); }\n";

static const char *FS =
    "#version 310 es\n"
    "precision highp float;\n"
    "precision highp int;\n"
    "uniform highp sampler2D u_src;\n"
    "uniform highp sampler2D u_lut;\n"
    "uniform int u_mode;\n" /* 0 identity, 1 analytic, 2 lut-linear, 3 lut-sqrt */
    "out vec4 o;\n"
    "highp float mks_half_store(highp float value) {\n"
    "highp uint raw=floatBitsToUint(value); highp uint mag=raw&0x7fffffffu;\n"
    "if(mag==0u||mag>=0x38800000u) return unpackHalf2x16(packHalf2x16(vec2(value,0.0))).x;\n"
    "highp uint sign=raw&0x80000000u; highp int e=int(mag>>23u)-127;\n"
    "if(e< -24) return uintBitsToFloat(sign);\n"
    "highp uint h=((mag&0x7fffffu)|0x800000u)>>uint(-e-1);\n"
    "highp float q=float(h)*0.000000059604644775390625;\n"
    "return uintBitsToFloat(floatBitsToUint(q)|sign); }\n"
    "highp float pq_encode(highp float x){\n"
    "highp float v=x*0.0203;\n"
    "highp float p=pow(v,0.1593017578125);\n"
    "highp float q=(0.8359375+18.8515625*p)/(1.0+18.6875*p);\n"
    "return pow(q,78.84375); }\n"
    "highp float lut_lookup(highp float x, int warp){\n"
    "highp float f=clamp(x*0.0203,0.0,1.0);\n"
    "if(warp==3) f=sqrt(f);\n"
    "highp float n=float(textureSize(u_lut,0).x);\n"
    "return texture(u_lut,vec2((f*(n-1.0)+0.5)/n,0.5)).r; }\n"
    "void main(){\n"
    "ivec2 c=ivec2(gl_FragCoord.xy);\n"
    "vec3 x=texelFetch(u_src,c,0).rgb;\n"
    "vec3 pq;\n"
    "if(u_mode==0) pq=x;\n"
    "else if(u_mode==1) pq=vec3(pq_encode(x.r),pq_encode(x.g),pq_encode(x.b));\n"
    "else pq=vec3(lut_lookup(x.r,u_mode),lut_lookup(x.g,u_mode),lut_lookup(x.b,u_mode));\n"
    "vec3 h=vec3(mks_half_store(pq.r),mks_half_store(pq.g),mks_half_store(pq.b));\n"
    "float y=0.2627*h.r+0.6780*h.g+0.0593*h.b;\n"
    "float cb=(h.b-y)*0.5/(1.0-0.0593);\n"
    "float cr=(h.r-y)*0.5/(1.0-0.2627);\n"
    "o=vec4(y,cb+0.5,cr+0.5,1.0); }\n";

static GLuint compile(GLenum type, const char *src)
{
    GLuint s = glCreateShader(type);
    glShaderSource(s, 1, &src, NULL);
    glCompileShader(s);
    GLint ok = 0;
    glGetShaderiv(s, GL_COMPILE_STATUS, &ok);
    if (!ok) {
        char log[2048] = { 0 };
        glGetShaderInfoLog(s, sizeof(log), NULL, log);
        fprintf(stderr, "PQLUT shader_compile_failed type=0x%04x log=%s\n", type, log);
        glDeleteShader(s);
        return 0;
    }
    return s;
}

static GLuint link_program(const char *fragment)
{
    GLuint vs = compile(GL_VERTEX_SHADER, VS), frag = compile(GL_FRAGMENT_SHADER, fragment);
    if (!vs || !frag) {
        if (vs) glDeleteShader(vs);
        if (frag) glDeleteShader(frag);
        return 0;
    }
    GLuint p = glCreateProgram();
    glAttachShader(p, vs);
    glAttachShader(p, frag);
    glLinkProgram(p);
    GLint ok = 0;
    glGetProgramiv(p, GL_LINK_STATUS, &ok);
    glDeleteShader(vs);
    glDeleteShader(frag);
    if (!ok) {
        char log[2048] = { 0 };
        glGetProgramInfoLog(p, sizeof(log), NULL, log);
        fprintf(stderr, "PQLUT link_failed log=%s\n", log);
        return 0;
    }
    return p;
}

static int cmp_u64(const void *a, const void *b)
{
    uint64_t x = *(const uint64_t *)a, y = *(const uint64_t *)b;
    return (x > y) - (x < y);
}

/* The exact dyadic values survive a binary16 render target and detect
 * unwritten pixels, stale phases and swapped or clamped channels. */
static int canary_check(const float *pixels, int width, int height, int phase)
{
    if (!pixels || width <= 0 || height <= 0 || phase < 0 || phase > 2)
        return 0;
    if ((size_t)height > SIZE_MAX / (size_t)width / 4)
        return 0;
    for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
            size_t i = ((size_t)y * (size_t)width + (size_t)x) * 4;
            float expected[4];
            if (phase == 0) {
                expected[0] = -2.0f; expected[1] = 3.0f;
                expected[2] = -4.0f; expected[3] = 0.0f;
            } else {
                expected[0] = 2.0f + (x & 1) * 0.5f + phase * 0.25f;
                expected[1] = -1.0f - (y & 1) * 0.5f - phase * 0.25f;
                expected[2] = 4.0f + ((x + y) & 1) * 0.5f + phase * 0.25f;
                expected[3] = 1.0f;
            }
            for (int c = 0; c < 4; c++) {
                if (!isfinite(pixels[i + c]) || pixels[i + c] != expected[c])
                    return 0;
            }
        }
    }
    return 1;
}

int main(void)
{
    alarm(900);
    setvbuf(stdout, NULL, _IOLBF, 0);

    display = eglGetDisplay(EGL_DEFAULT_DISPLAY);
    eglInitialize(display, NULL, NULL);
    EGLConfig cfg;
    EGLint ncfg = 0;
    const EGLint cattr[] = { EGL_SURFACE_TYPE, EGL_PBUFFER_BIT, EGL_RENDERABLE_TYPE,
                             EGL_OPENGL_ES3_BIT, EGL_NONE };
    eglChooseConfig(display, cattr, &cfg, 1, &ncfg);
    if (!ncfg) { printf("PQLUT verdict=fail reason=config\n"); return 2; }
    const EGLint cctx[] = { EGL_CONTEXT_CLIENT_VERSION, 3, EGL_NONE };
    context = eglCreateContext(display, cfg, EGL_NO_CONTEXT, cctx);
    if (context == EGL_NO_CONTEXT) { printf("PQLUT verdict=fail reason=context\n"); return 2; }
    const EGLint pattr[] = { EGL_WIDTH, 64, EGL_HEIGHT, 64, EGL_NONE };
    surface = eglCreatePbufferSurface(display, cfg, pattr);
    if (surface == EGL_NO_SURFACE || !eglMakeCurrent(display, surface, surface, context)) {
        printf("PQLUT verdict=fail reason=make_current\n");
        return 2;
    }

    const char *renderer = (const char *)glGetString(GL_RENDERER);
    const char *version = (const char *)glGetString(GL_VERSION);
    printf("PQLUT renderer=%s version=%s\n", renderer ? renderer : "?", version ? version : "?");
    GLint gles_major = 0, gles_minor = 0;
    sscanf(version ? version : "", "OpenGL ES %d.%d", &gles_major, &gles_minor);
    int timer_ext = has_ext("GL_EXT_disjoint_timer_query");
    int float_ext = has_ext("GL_EXT_color_buffer_float");
    int half_linear = gles_major > 3 || (gles_major == 3 && gles_minor >= 2) ||
                      has_ext("GL_OES_texture_half_float_linear");
    printf("PQLUT caps ext_timer=%d ext_color_buffer_float=%d half_float_linear=%d gles=%d.%d\n",
           timer_ext, float_ext, half_linear, gles_major, gles_minor);
    if (!timer_ext || !float_ext || !half_linear) {
        printf("PQLUT verdict=fail reason=caps\n");
        return 2;
    }

#define LOAD(field, symbol) q.field = (void *)eglGetProcAddress(symbol)
    LOAD(gen, "glGenQueriesEXT");
    LOAD(del, "glDeleteQueriesEXT");
    LOAD(begin, "glBeginQueryEXT");
    LOAD(end, "glEndQueryEXT");
    LOAD(getiv, "glGetQueryivEXT");
    LOAD(getuiv, "glGetQueryObjectuivEXT");
    LOAD(getu64, "glGetQueryObjectui64vEXT");
#undef LOAD
    if (!q.gen || !q.del || !q.begin || !q.end || !q.getiv || !q.getuiv || !q.getu64) {
        printf("PQLUT verdict=fail reason=entries\n");
        return 2;
    }
    GLint bits = 0;
    q.getiv(0x88BF, 0x8864 /* GL_QUERY_COUNTER_BITS_EXT */, &bits);
    printf("PQLUT timer_counter_bits=%d\n", bits);
    if (bits < 32) { printf("PQLUT verdict=fail reason=counter_bits\n"); return 2; }
    GLQ(q.gen(RING, ring_ids));

    GLuint program = link_program(FS);
    if (!program) { printf("PQLUT verdict=fail reason=program\n"); return 2; }
    GLint u_src = glGetUniformLocation(program, "u_src");
    GLint u_lut = glGetUniformLocation(program, "u_lut");
    GLint u_mode = glGetUniformLocation(program, "u_mode");
    if (u_src < 0 || u_lut < 0 || u_mode < 0) {
        printf("PQLUT verdict=fail reason=uniforms src=%d lut=%d mode=%d\n", u_src, u_lut, u_mode);
        return 2;
    }

    /* Source texture: float16 RGBA, mostly low luminance with a tail. */
    size_t pixels = (size_t)PROBE_W * PROBE_H;
    uint16_t *src = malloc(pixels * 8);
    if (!src) { printf("PQLUT verdict=fail reason=oom\n"); return 2; }
    for (size_t i = 0; i < pixels; i++) {
        double v = src_value();
        uint16_t h = f32_to_f16(v);
        src[i * 4 + 0] = h; src[i * 4 + 1] = h; src[i * 4 + 2] = h; src[i * 4 + 3] = 0x3c00u;
    }
    src[0] = 0; src[1] = 0; src[2] = 0;                             /* texel0: 0.0 */
    src[4] = f32_to_f16(1.0); src[5] = src[4]; src[6] = src[4];     /* texel1: 203 nits */
    src[8] = f32_to_f16(4.9261); src[9] = src[8]; src[10] = src[8]; /* texel2: 1000 nits */
    src[12] = f32_to_f16(PQ_DOMAIN); src[13] = src[12]; src[14] = src[12];

    GLuint tex_src = 0;
    GLQ(glGenTextures(1, &tex_src));
    GLQ(glBindTexture(GL_TEXTURE_2D, tex_src));
    GLQ(glTexStorage2D(GL_TEXTURE_2D, 1, GL_RGBA16F, PROBE_W, PROBE_H));
    GLQ(glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, PROBE_W, PROBE_H, GL_RGBA, GL_HALF_FLOAT, src));
    GLQ(glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST));
    GLQ(glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST));

    /* LUT textures: {1024,4096} x {linear,sqrt}. Values: double PQ -> half. */
    struct { int size; int warp; GLuint tex; } luts[4] = {
        { 1024, 0, 0 }, { 1024, 1, 0 }, { 4096, 0, 0 }, { 4096, 1, 0 } };
    for (int i = 0; i < 4; i++) {
        uint16_t *data = malloc((size_t)luts[i].size * 2);
        if (!data) { printf("PQLUT verdict=fail reason=oom\n"); return 2; }
        for (int e = 0; e < luts[i].size; e++) {
            double x = lut_domain_value(e, luts[i].size, luts[i].warp);
            data[e] = f32_to_f16(pq_encode_double(x));
        }
        GLQ(glGenTextures(1, &luts[i].tex));
        GLQ(glBindTexture(GL_TEXTURE_2D, luts[i].tex));
        GLQ(glTexStorage2D(GL_TEXTURE_2D, 1, GL_R16F, luts[i].size, 1));
        GLQ(glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, luts[i].size, 1, GL_RED, GL_HALF_FLOAT, data));
        GLQ(glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR));
        GLQ(glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR));
        GLQ(glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE));
        GLQ(glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE));
        free(data);
    }
    free(src);

    /* Render target: RGBA16F FBO at the production surface size. */
    GLuint tex_out = 0, fbo = 0;
    GLQ(glGenTextures(1, &tex_out));
    GLQ(glBindTexture(GL_TEXTURE_2D, tex_out));
    GLQ(glTexStorage2D(GL_TEXTURE_2D, 1, GL_RGBA16F, PROBE_W, PROBE_H));
    GLQ(glGenFramebuffers(1, &fbo));
    GLQ(glBindFramebuffer(GL_FRAMEBUFFER, fbo));
    GLQ(glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, tex_out, 0));
    if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) {
        printf("PQLUT verdict=fail reason=fbo_incomplete\n");
        return 2;
    }
    GLQ(glViewport(0, 0, PROBE_W, PROBE_H));

    printf("PQLUT phase=canary\n");
    GLuint canary_program = link_program(CANARY_FS);
    if (!canary_program) { printf("PQLUT verdict=fail reason=canary_program\n"); return 2; }
    GLint canary_phase = glGetUniformLocation(canary_program, "u_phase");
    if (canary_phase < 0) { printf("PQLUT verdict=fail reason=canary_uniform\n"); return 2; }
    float *canary = malloc(pixels * 4 * sizeof(*canary));
    if (!canary) { printf("PQLUT verdict=fail reason=oom\n"); return 2; }
    GLQ(glBindFramebuffer(GL_FRAMEBUFFER, fbo));
    GLQ(glViewport(0, 0, PROBE_W, PROBE_H));
    GLQ(glDisable(GL_SCISSOR_TEST));
    GLQ(glDisable(GL_BLEND));
    GLQ(glDisable(GL_DEPTH_TEST));
    GLQ(glDisable(GL_STENCIL_TEST));
    GLQ(glDisable(GL_CULL_FACE));
    GLQ(glDisable(GL_RASTERIZER_DISCARD));
    GLQ(glDisable(GL_DITHER));
    GLQ(glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE));
    GLQ(glBindBuffer(GL_PIXEL_PACK_BUFFER, 0));
    GLQ(glPixelStorei(GL_PACK_ALIGNMENT, 4));
    GLQ(glPixelStorei(GL_PACK_ROW_LENGTH, 0));
    GLQ(glPixelStorei(GL_PACK_SKIP_PIXELS, 0));
    GLQ(glPixelStorei(GL_PACK_SKIP_ROWS, 0));
    GLQ(glReadBuffer(GL_COLOR_ATTACHMENT0));
    const GLenum draw_buffer = GL_COLOR_ATTACHMENT0;
    GLQ(glDrawBuffers(1, &draw_buffer));
    const GLfloat clear[4] = { -2.0f, 3.0f, -4.0f, 0.0f };
    GLQ(glClearBufferfv(GL_COLOR, 0, clear));
    for (int phase = 0; phase < 3; phase++) {
        if (phase) {
            GLQ(glUseProgram(canary_program));
            GLQ(glUniform1i(canary_phase, phase));
            GLQ(glDrawArrays(GL_TRIANGLES, 0, 3));
        }
        for (size_t i = 0; i < pixels * 4; i++)
            canary[i] = NAN;
        GLQ(glReadPixels(0, 0, PROBE_W, PROBE_H, GL_RGBA, GL_FLOAT, canary));
        if (!canary_check(canary, PROBE_W, PROBE_H, phase)) {
            printf("PQLUT verdict=fail reason=canary phase=%d\n", phase);
            return 2;
        }
    }
    free(canary);
    GLQ(glDeleteProgram(canary_program));
    printf("PQLUT canary=pass scope=clear-draw-read\n");

    struct { const char *name; int mode; int lut; } variants[6] = {
        { "identity", 0, -1 }, { "analytic", 1, -1 },
        { "lut1024-linear", 2, 0 }, { "lut1024-sqrt", 3, 1 },
        { "lut4096-linear", 2, 2 }, { "lut4096-sqrt", 3, 3 } };

    uint64_t *samples[6] = { 0 };
    int sample_counts[6] = { 0 };
    for (int v = 0; v < 6; v++) {
        samples[v] = malloc(sizeof(uint64_t) * TIMED_FRAMES * SETS);
        if (!samples[v]) {
            printf("PQLUT verdict=fail reason=oom\n");
            for (int i = 0; i < 6; i++)
                free(samples[i]);
            q.del(RING, ring_ids);
            eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
            eglTerminate(display);
            return 2;
        }
    }

    GLQ(glUseProgram(program));
    GLQ(glUniform1i(u_src, 0));
    GLQ(glUniform1i(u_lut, 1));
    GLQ(glActiveTexture(GL_TEXTURE0));
    GLQ(glBindTexture(GL_TEXTURE_2D, tex_src));
    double started;
    if (!now_seconds(&started)) {
        printf("PQLUT verdict=fail reason=clock\n");
        return 2;
    }
    for (int set = 0; set < SETS; set++) {
        for (int v = 0; v < 6; v++) {
            printf("PQLUT phase=timing set=%d variant=%s\n", set, variants[v].name);
            GLQ(glActiveTexture(GL_TEXTURE1));
            GLQ(glBindTexture(GL_TEXTURE_2D,
                              variants[v].lut >= 0 ? luts[variants[v].lut].tex : tex_src));
            GLQ(glUniform1i(u_mode, variants[v].mode));
            collect = samples[v];
            collect_cap = TIMED_FRAMES * SETS;
            collect_n = sample_counts[v]; /* resume this variant's position */
            for (int f = 0; f < WARMUP_FRAMES; f++)
                GLQ(glDrawArrays(GL_TRIANGLES, 0, 3));
            int set_start = collect_n;
            uint64_t issued_start = issued, results_start = results;
            for (int f = 0; f < TIMED_FRAMES; f++) {
                if (!timer_begin()) {
                    printf("PQLUT verdict=fail reason=timer_begin\n");
                    return 2;
                }
                GLQ(glDrawArrays(GL_TRIANGLES, 0, 3));
                if (!timer_end()) {
                    printf("PQLUT verdict=fail reason=timer_end\n");
                    return 2;
                }
                /* A pbuffer has no swap; submit at most a ring of queries,
                 * then retire it before the next batch. Driver behavior and
                 * potential blocking remain unverified on the target GPU. */
                if ((f + 1) % RING == 0 || f + 1 == TIMED_FRAMES) {
                    GLQ(glFlush());
                    if (!drain_all()) {
                        printf("PQLUT verdict=fail reason=timer_drain gl_errors=%d stale_drop=%" PRIu64 "\n",
                               gl_error_count, stale_drop);
                        return 2;
                    }
                }
            }
            if (!timer_poll() || ring_active >= 0 ||
                collect_n - set_start != TIMED_FRAMES ||
                issued - issued_start != TIMED_FRAMES ||
                results - results_start != TIMED_FRAMES) {
                printf("PQLUT verdict=fail reason=timer_incomplete_set\n");
                return 2;
            }
            sample_counts[v] = collect_n;
            collect = NULL;
            collect_n = 0;
        }
    }
    double finished;
    if (!now_seconds(&finished) || finished < started) {
        printf("PQLUT verdict=fail reason=clock\n");
        return 2;
    }
    double elapsed = finished - started;
    printf("PQLUT timing wall_seconds=%.2f attempts=%" PRIu64 " issued=%" PRIu64
           " results=%" PRIu64 " disjoint_drop=%" PRIu64 "\n",
           elapsed, attempts, issued, results, disjoint_drop);

    for (int v = 0; v < 6; v++) {
        qsort(samples[v], sample_counts[v], sizeof(uint64_t), cmp_u64);
        uint64_t sum = 0;
        for (int i = 0; i < sample_counts[v]; i++) sum += samples[v][i];
        double mean = sample_counts[v] ? (double)sum / sample_counts[v] : 0;
        double median = sample_counts[v] ? (double)samples[v][sample_counts[v] / 2] : 0;
        printf("PQLUT variant=%s count=%d median_ns=%.0f mean_ns=%.0f min_ns=%.0f max_ns=%.0f\n",
               variants[v].name, sample_counts[v], median, mean,
               sample_counts[v] ? (double)samples[v][0] : 0,
               sample_counts[v] ? (double)samples[v][sample_counts[v] - 1] : 0);
    }

    printf("PQLUT phase=accuracy\n");
    /* Accuracy: analytic FBO readback vs each LUT variant, full screen.
     * Read RGBA16F as GL_RGBA/GL_FLOAT and convert to half on the CPU. The
     * validity of this readback remains unverified until the canary passes;
     * the cause of the earlier failed HALF_FLOAT attempt is not established. */
    size_t comps = pixels * 3;
    float *accf = malloc(pixels * 16);
    float *basef = malloc(pixels * 16);
    uint16_t *acc = malloc(pixels * 8); /* RGBA half entries */
    uint16_t *base = malloc(pixels * 8);
    if (!accf || !basef || !acc || !base) {
        printf("PQLUT verdict=fail reason=oom\n");
        goto accuracy_failure;
    }
    GLQ(glBindFramebuffer(GL_FRAMEBUFFER, fbo));
    GLQ(glUseProgram(program));
    GLQ(glUniform1i(u_mode, 1));
    GLQ(glDrawArrays(GL_TRIANGLES, 0, 3));
    for (size_t i = 0; i < pixels * 4; i++)
        basef[i] = NAN;
    GLQ(glReadPixels(0, 0, PROBE_W, PROBE_H, GL_RGBA, GL_FLOAT, basef));
    for (size_t i = 0; i < pixels * 4; i++) {
        if (!checked_half(basef[i], &base[i])) {
            printf("PQLUT verdict=fail reason=accuracy_value variant=analytic read=0 pixel=%zu component=%zu\n",
                   i / 4, i % 4);
            goto accuracy_failure;
        }
    }
    for (int v = 2; v < 6; v++) {
        GLQ(glUseProgram(program));
        GLQ(glActiveTexture(GL_TEXTURE1));
        GLQ(glBindTexture(GL_TEXTURE_2D, luts[variants[v].lut].tex));
        GLQ(glUniform1i(u_mode, variants[v].mode));
        GLQ(glDrawArrays(GL_TRIANGLES, 0, 3));
        for (size_t i = 0; i < pixels * 4; i++)
            accf[i] = NAN;
        GLQ(glReadPixels(0, 0, PROBE_W, PROBE_H, GL_RGBA, GL_FLOAT, accf));
        for (size_t i = 0; i < pixels * 4; i++) {
            if (!checked_half(accf[i], &acc[i])) {
                printf("PQLUT verdict=fail reason=accuracy_value variant=%s read=%d pixel=%zu component=%zu\n",
                       variants[v].name, v - 1, i / 4, i % 4);
                goto accuracy_failure;
            }
        }
        long diffs = 0;
        double max_abs = 0;
        int max_ulp = 0;
        for (size_t p = 0; p < pixels; p++) {
            for (int c = 0; c < 3; c++) {
                uint16_t a = base[p * 4 + c], b = acc[p * 4 + c];
                if (a == b) continue;
                diffs++;
                double d = fabs(f16_to_f32(a) - f16_to_f32(b));
                if (d > max_abs) max_abs = d;
                int ulp = half_ulp_distance(a, b);
                if (ulp > max_ulp) max_ulp = ulp;
            }
        }
        printf("PQLUT accuracy variant=%s comps=%zu differing=%ld max_abs=%.9f max_ulp=%d\n",
               variants[v].name, comps, diffs, max_abs, max_ulp);
    }

    printf("PQLUT phase=cpu_reference\n");
    /* CPU double reference: full production tail on 256 texels. The fill
     * consumed one lcg draw per pixel BEFORE the anchor overwrite, so texels
     * 0-3 own draws 1-4 (discarded values) and texel p>=4 owns draw p+1.
     * GPU pow differs from double; report exact mismatches and +/-1 half-ULP
     * agreement separately. */
    long cpu_diffs = 0, cpu_within1ulp = 0;
    double cpu_max = 0;
    lcg_state = 0x1234abcd;
    for (int p = 0; p < 256; p++) {
        /* Replay the fill sequence exactly: one random draw per pixel, then
         * the anchor overwrite for texels 0-3, then half quantization of the
         * FINAL value (the GPU source texture holds half bits, so e.g. the
         * 1000-nit anchor is 4.92578125, not 4.9261). */
        double raw = src_value();
        double chosen = raw;
        if (p == 0) chosen = 0.0;
        else if (p == 1) chosen = 1.0;
        else if (p == 2) chosen = 4.9261;
        else if (p == 3) chosen = PQ_DOMAIN;
        uint16_t chosen_half;
        if (!checked_half(chosen, &chosen_half)) {
            printf("PQLUT verdict=fail reason=cpu_reference_value stage=source pixel=%d\n", p);
            goto accuracy_failure;
        }
        double v16 = f16_to_f32(chosen_half);
        double pq[3];
        for (int c = 0; c < 3; c++) {
            uint16_t pq_half;
            if (!checked_half(pq_encode_double(v16), &pq_half)) {
                printf("PQLUT verdict=fail reason=cpu_reference_value stage=pq pixel=%d component=%d\n", p, c);
                goto accuracy_failure;
            }
            pq[c] = f16_to_f32(pq_half);
        }
        double y = 0.2627 * pq[0] + 0.6780 * pq[1] + 0.0593 * pq[2];
        double cb = (pq[2] - y) * 0.5 / (1.0 - 0.0593);
        double cr = (pq[0] - y) * 0.5 / (1.0 - 0.2627);
        double want[3] = { y, cb + 0.5, cr + 0.5 };
        for (int c = 0; c < 3; c++) {
            uint16_t wh;
            if (!checked_half(want[c], &wh)) {
                printf("PQLUT verdict=fail reason=cpu_reference_value stage=tail pixel=%d component=%d\n", p, c);
                goto accuracy_failure;
            }
            double gpu = f16_to_f32(base[(size_t)p * 4 + c]);
            double d = fabs(gpu - f16_to_f32(wh));
            if (d > cpu_max) cpu_max = d;
            if (base[(size_t)p * 4 + c] != wh) {
                cpu_diffs++;
                int ulp = half_ulp_distance(base[(size_t)p * 4 + c], wh);
                if (ulp <= 1) cpu_within1ulp++;
            }
        }
    }
    printf("PQLUT cpu_reference comps=%ld exact_mismatch=%ld within1ulp=%ld max_abs=%.9f"
           " note=GPU-pow-vs-double-full-tail\n",
           (long)256 * 3, cpu_diffs, cpu_within1ulp, cpu_max);

    q.del(RING, ring_ids);
    eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    eglTerminate(display);
    printf("PQLUT gl_errors=%d disjoint_drop=%" PRIu64 "\n", gl_error_count, disjoint_drop);
    int ok = gl_error_count == 0 && disjoint_drop == 0 &&
             results == (uint64_t)TIMED_FRAMES * SETS * 6;
    /* Execution and numerical validation are not yet closed; never expose a
     * passing diagnostic verdict until the canary and anchor gates exist. */
    printf("PQLUT validation=unverified reason=missing_canary_and_anchor_gates\n");
    ok = 0;
    for (int v = 0; v < 6; v++) {
        if (sample_counts[v] != TIMED_FRAMES * SETS) ok = 0;
        free(samples[v]);
    }
    free(acc);
    free(base);
    free(accf);
    free(basef);
    printf("PQLUT verdict=%s\n", ok ? "pass" : "fail");
    return ok ? 0 : 2;

accuracy_failure:
    for (int v = 0; v < 6; v++)
        free(samples[v]);
    free(acc);
    free(base);
    free(accf);
    free(basef);
    q.del(RING, ring_ids);
    eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    eglTerminate(display);
    return 2;
}

#endif /* !LG_PQ_HOST_TEST */
