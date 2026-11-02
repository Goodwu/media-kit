/*
 * Standalone, one-shot GLES 3 quantization diagnostic. It never opens media,
 * touches another process's EGL context, or changes device settings.
 *
 * A: RGBA32F input -> real RGBA16F attachment -> integer bit capture.
 * B: same input -> GLSL packHalf2x16/unpackHalf2x16 -> integer bit capture.
 * Integer capture is self-tested before any equivalence conclusion. This is
 * not a test of a YUV drawable, the playback renderer, or panel appearance.
 */
#include <errno.h>
#include <float.h>
#include <inttypes.h>
#include <math.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static uint32_t float_bits(float value)
{
    uint32_t bits;
    memcpy(&bits, &value, sizeof(bits));
    return bits;
}

static float bits_float(uint32_t bits)
{
    float value;
    memcpy(&value, &bits, sizeof(value));
    return value;
}

/* Exact binary16 -> binary32 decode; no host half type/compiler conversion. */
static float half_float(uint16_t h)
{
    uint32_t sign = (uint32_t)(h & 0x8000u) << 16;
    uint32_t exponent = (h >> 10) & 31u;
    uint32_t fraction = h & 1023u;
    if (!exponent) {
        if (!fraction)
            return bits_float(sign);
        int e = -14;
        while (!(fraction & 1024u)) {
            fraction <<= 1;
            e--;
        }
        return bits_float(sign | (uint32_t)(e + 127) << 23 |
                          (fraction & 1023u) << 13);
    }
    if (exponent == 31)
        return bits_float(sign | 0x7f800000u | fraction << 13);
    return bits_float(sign | (exponent + 112u) << 23 | fraction << 13);
}

enum { DATA_LIMIT = 300000, TEX_WIDTH = 512, FIRST_DIFFS = 24 };

enum half_value_class { HALF_ZERO, HALF_SUBNORMAL, HALF_NORMAL,
                        HALF_NONFINITE, HALF_OTHER, HALF_CLASS_COUNT };

/* Classify the captured FP32 value, not merely its FP32 exponent. A sampled
 * binary16 subnormal is a normal FP32 value and an exact multiple of 2^-24. */
static enum half_value_class half_value_class(uint32_t bits)
{
    uint32_t magnitude = bits & 0x7fffffffu;
    if (!magnitude) return HALF_ZERO;
    if (magnitude >= 0x7f800000u) return HALF_NONFINITE;
    if (magnitude < 0x38800000u) {
        double units = ldexp((double)bits_float(magnitude), 24);
        return units >= 1.0 && units <= 1023.0 && floor(units) == units
            ? HALF_SUBNORMAL : HALF_OTHER;
    }
    return magnitude <= 0x477fe000u && (magnitude & 0x1fffu) == 0
        ? HALF_NORMAL : HALF_OTHER;
}

/* CPU observation models only for nonzero finite |input| < 2^-14. They are
 * predictions to compare with the measured storage path, not GPU guarantees.
 * Reconstruction uses the independently tested half decoder. */
static bool small_model_bits(uint32_t bits, bool rne, uint32_t *result)
{
    uint32_t magnitude = bits & 0x7fffffffu;
    if (!magnitude || magnitude >= 0x38800000u) return false;
    int exponent = (int)(magnitude >> 23) - 127;
    uint32_t h = 0;
    if (exponent >= (rne ? -25 : -24)) {
        unsigned shift = (unsigned)(-exponent - 1);
        if (shift < 14 || shift > 24) return false;
        uint32_t significand = (magnitude & 0x7fffffu) | 0x800000u;
        h = significand >> shift;
        if (rne) {
            uint32_t remainder = significand & ((1u << shift) - 1u);
            uint32_t midpoint = 1u << (shift - 1u);
            h += remainder > midpoint || (remainder == midpoint && (h & 1u));
        }
    }
    *result = float_bits(half_float((uint16_t)(h | (bits >> 16 & 0x8000u))));
    return true;
}

static size_t make_values(float *values)
{
    size_t n = 0;
    for (unsigned h = 0; h <= 0x7bffu; h++) {
        float lo = half_float((uint16_t)h);
        float part[4] = {lo, 0, 0, 0};
        unsigned count = 1;
        if (h < 0x7bffu) {
            float hi = half_float((uint16_t)(h + 1));
            /* Sum is exact in double; midpoint is exactly representable f32. */
            float mid = (float)(((double)lo + (double)hi) * 0.5);
            part[1] = nextafterf(mid, -INFINITY);
            part[2] = mid;
            part[3] = nextafterf(mid, INFINITY);
            count = 4;
        }
        for (unsigned k = 0; k < count; k++) {
            values[n++] = part[k];
            values[n++] = -part[k];
        }
    }
    const uint32_t special[] = {
        0x00000001u, 0x80000001u, 0x007fffffu, 0x807fffffu,
        0x00800000u, 0x80800000u, 0x3f7fffffu, 0x3f800000u,
        0x3f800001u, 0x477fefffu, 0x477ff000u, 0x477ff001u,
        0xc77fefffu, 0xc77ff000u, 0xc77ff001u, 0x7f7fffffu,
        0x7f800000u, 0xff800000u, 0x7fc00001u, 0xffc00001u,
        0x7fc12345u, 0x7fffffffu,
    };
    for (size_t i = 0; i < sizeof(special) / sizeof(special[0]); i++)
        values[n++] = bits_float(special[i]);
    return n;
}

static bool host_selftest(void)
{
    const struct { uint16_t h; uint32_t f; } cases[] = {
        {0x0000, 0x00000000}, {0x8000, 0x80000000},
        {0x0001, 0x33800000}, {0x03ff, 0x387fc000},
        {0x0400, 0x38800000}, {0x3c00, 0x3f800000},
        {0x7bff, 0x477fe000}, {0x7c00, 0x7f800000},
        {0xfc00, 0xff800000}, {0x7e01, 0x7fc02000},
    };
    for (size_t i = 0; i < sizeof(cases) / sizeof(cases[0]); i++) {
        if (float_bits(half_float(cases[i].h)) != cases[i].f)
            return false;
    }
    if (half_value_class(0x80000000u) != HALF_ZERO ||
        half_value_class(0x33800000u) != HALF_SUBNORMAL ||
        half_value_class(0xb87fc000u) != HALF_SUBNORMAL ||
        half_value_class(0x38800000u) != HALF_NORMAL ||
        half_value_class(0x477fe000u) != HALF_NORMAL ||
        half_value_class(0x3f800001u) != HALF_OTHER ||
        half_value_class(0x00000001u) != HALF_OTHER ||
        half_value_class(0xffc00001u) != HALF_NONFINITE)
        return false;
    for (unsigned h = 1; h <= 0x7bffu; h++) {
        if (!(half_float((uint16_t)h) > half_float((uint16_t)(h - 1))))
            return false;
        if (float_bits(half_float((uint16_t)(h | 0x8000u))) !=
            (float_bits(half_float((uint16_t)h)) | 0x80000000u))
            return false;
    }
    float *values = malloc(DATA_LIMIT * sizeof(*values));
    if (!values)
        return false;
    size_t n = make_values(values);
    bool ok = n == 253968 && n < DATA_LIMIT;
    const struct { uint32_t input, rne, rtz; } small_cases[] = {
        {0x33000000, 0x00000000, 0x00000000}, /* exact half-unit, ties-even */
        {0x33000001, 0x33800000, 0x00000000},
        {0x33c00000, 0x34000000, 0x33800000}, /* 1.5 half units */
        {0x34200000, 0x34000000, 0x34000000}, /* 2.5, ties-even */
        {0x34200001, 0x34400000, 0x34000000},
        {0x387fffff, 0x38800000, 0x387fc000}, /* RNE carry to half-normal */
        {0x00000001, 0x00000000, 0x00000000},
    };
    for (size_t i = 0; i < sizeof(small_cases)/sizeof(small_cases[0]); i++) {
        for (unsigned sign = 0; sign < 2; sign++) {
            uint32_t s = sign ? 0x80000000u : 0;
            uint32_t a = 0, b = 0;
            ok &= small_model_bits(small_cases[i].input | s, true, &a) && a == (small_cases[i].rne | s);
            ok &= small_model_bits(small_cases[i].input | s, false, &b) && b == (small_cases[i].rtz | s);
        }
    }
    const uint32_t excluded[] = {0, 0x80000000, 0x38800000, 0xb8800000,
        0x3f800000, 0x477fe000, 0x477ff000, 0x477ff001, 0x7f800000, 0xff800000, 0x7fc00001};
    for (size_t i = 0; i < sizeof(excluded)/sizeof(excluded[0]); i++) {
        uint32_t out = 0xdeadbeefu;
        ok &= !small_model_bits(excluded[i], false, &out) && out == 0xdeadbeefu;
        ok &= !small_model_bits(excluded[i], true, &out) && out == 0xdeadbeefu;
    }
    for (size_t i = 0; i < n; i++) {
        uint32_t bits = float_bits(values[i]), magnitude = bits & 0x7fffffffu;
        if (!magnitude || magnitude >= 0x38800000u) continue;
        /* Independent double arithmetic reference, unlike integer shifts. */
        double units = ldexp(fabs((double)values[i]), 24);
        double base = floor(units), fraction = units - base;
        for (unsigned rne = 0; rne < 2; rne++) {
            double count = base + (rne && (fraction > 0.5 ||
                (fraction == 0.5 && fmod(base, 2.0) != 0.0)));
            uint32_t expected = float_bits((float)ldexp(count, -24)) | (bits & 0x80000000u);
            uint32_t actual = 0;
            ok &= small_model_bits(bits, rne != 0, &actual) && actual == expected;
        }
    }
    free(values);
    return ok;
}

#ifdef LG_HALF_HOST_TEST
int main(void)
{
    if (!host_selftest()) {
        fputs("CPU half decode/dataset self-test failed\n", stderr);
        return 1;
    }
    puts("CPU half decode, value-class, small RNE/RTZ models and 253968-value dataset self-tests passed");
    return 0;
}
#else
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES3/gl3.h>
#include <fcntl.h>
#include <unistd.h>

struct diff {
    size_t pixel;
    unsigned channel;
    uint32_t input[3], a, b;
};

struct compare {
    uint64_t components, mismatches, finite_input_components;
    uint64_t finite_input_mismatches, nonfinite_input_mismatches;
    uint64_t finite_output_components, finite_output_mismatches;
    uint64_t nonfinite_output_mismatches, pq_domain_mismatches;
    uint64_t pq_domain_components, signed_zero_mismatches;
    uint64_t mismatch_baseline_class[HALF_CLASS_COUNT];
    double max_finite_abs;
    unsigned first_count;
    struct diff first[FIRST_DIFFS];
};

struct small_observation {
    uint64_t input_zero, input_f32_subnormal, input_below_half_min;
    uint64_t input_half_subnormal_interval, input_half_normal_or_larger, input_nonfinite;
    uint64_t modeled_components, rne_match, rne_mismatch, rtz_match, rtz_mismatch;
    uint64_t both_match, rne_only_match, rtz_only_match, neither_match;
    uint64_t baseline_class[HALF_CLASS_COUNT];
    uint64_t rne_mismatch_baseline_class[HALF_CLASS_COUNT];
    uint64_t rtz_mismatch_baseline_class[HALF_CLASS_COUNT];
};

struct run {
    EGLDisplay display;
    EGLContext context;
    EGLSurface surface;
    bool initialized, current, cleanup_complete;
    GLuint vao, input, half, integer_tex, half_fbo, integer_fbo;
    GLuint copy_program, capture[2][2], self_program;
    char vendor[256], renderer[512], version[256], glsl[256];
    char extensions[32768], error[4096], stage[128];
    GLenum half_status, integer_status;
    unsigned gl_errors, first_gl_error;
    unsigned egl_error, cleanup_gl_errors, cleanup_egl_error;
    unsigned width, height;
    size_t samples, pixels;
    bool integer_selftest, input_transfer_valid;
    uint64_t input_normal_mismatches, input_subnormal_mismatches;
    uint64_t input_nonfinite_mismatches;
    struct compare quant, csc;
    struct small_observation small;
    const char *candidate_mode;
    bool highp_small_rtz;
};

static void text_copy(char *dst, size_t size, const char *src)
{
    snprintf(dst, size, "%s", src ? src : "");
}

static bool fail(struct run *r, const char *message)
{
    text_copy(r->error, sizeof(r->error), message);
    return false;
}

static bool gl_ok(struct run *r, const char *stage)
{
    text_copy(r->stage, sizeof(r->stage), stage);
    GLenum error;
    bool ok = true;
    for (unsigned i = 0; i < 32 && (error = glGetError()) != GL_NO_ERROR; i++) {
        if (!r->gl_errors)
            r->first_gl_error = error;
        r->gl_errors++;
        ok = false;
    }
    if (!ok)
        snprintf(r->error, sizeof(r->error), "GL error at %s (first=0x%x)",
                 stage, r->first_gl_error);
    return ok;
}

static const char vertex[] =
    "#version 300 es\n"
    "void main(){float x=float((gl_VertexID&1)<<2)-1.0;"
    "float y=float((gl_VertexID&2)<<1)-1.0;gl_Position=vec4(x,y,0.,1.);}\n";
static const char copy_fragment[] =
    "#version 300 es\nprecision highp float;\n"
    "uniform highp sampler2D src;out highp vec4 color;\n"
    "void main(){color=texelFetch(src,ivec2(gl_FragCoord.xy),0);}\n";
static const char capture_body[] =
    "precision highp float;precision highp int;\n"
    "uniform highp sampler2D src;layout(location=0) out highp uvec4 bits;\n"
    "#if HIGHP_SMALL_RTZ\n"
    "highp float smallRtzHypothesis(highp float value,highp float builtinValue){\n"
    "highp uint raw=floatBitsToUint(value);highp uint mag=raw&0x7fffffffu;\n"
    "if(mag==0u||mag>=0x38800000u)return builtinValue;\n"
    "highp uint sign=raw&0x80000000u;highp int e=int(mag>>23u)-127;\n"
    "if(e< -24)return uintBitsToFloat(sign);\n"
    "highp uint shift=uint(-e-1);highp uint sig=(mag&0x7fffffu)|0x800000u;\n"
    "highp uint h=sig>>shift;highp float q=float(h)*0.000000059604644775390625;\n"
    "return uintBitsToFloat(floatBitsToUint(q)|sign);}\n"
    "#endif\n"
    "void main(){highp vec3 rgb=texelFetch(src,ivec2(gl_FragCoord.xy),0).rgb;\n"
    "#if QUANTIZE_INPUT\n"
    "highp vec3 q;q.rg=unpackHalf2x16(packHalf2x16(rgb.rg));"
    "q.b=unpackHalf2x16(packHalf2x16(vec2(rgb.b,0.0))).x;\n"
    "#if HIGHP_SMALL_RTZ\n"
    "q.r=smallRtzHypothesis(rgb.r,q.r);q.g=smallRtzHypothesis(rgb.g,q.g);q.b=smallRtzHypothesis(rgb.b,q.b);\n"
    "#endif\n"
    "rgb=q;\n"
    "#endif\n"
    "#if APPLY_CSC\n"
    /* Same highp arithmetic/order/constants as context_android.c yuv_diag_fs.
     * layout(yuv) is deliberately not used: these are numeric bit captures,
     * not a validation of the driver's final YUV conversion or quantization. */
    "float y=0.2627*rgb.r+0.6780*rgb.g+0.0593*rgb.b;"
    "float cb=(rgb.b-y)*0.5/(1.0-0.0593);"
    "float cr=(rgb.r-y)*0.5/(1.0-0.2627);"
    "rgb=vec3(y,cb+0.5,cr+0.5);\n"
    "#endif\n"
    "bits=uvec4(floatBitsToUint(rgb),0x3f800000u);}\n";
static const char self_fragment[] =
    "#version 300 es\nprecision highp int;\n"
    "layout(location=0) out highp uvec4 bits;\n"
    "void main(){uint i=uint(gl_FragCoord.y)*512u+uint(gl_FragCoord.x);"
    "bits=uvec4(0x01234567u,0x89abcdefu,i^0x13579bdfu,0x3f800000u);}\n";

static GLuint shader(struct run *r, GLenum type, const char *source)
{
    GLuint object = glCreateShader(type);
    glShaderSource(object, 1, &source, NULL);
    glCompileShader(object);
    GLint ok = 0;
    glGetShaderiv(object, GL_COMPILE_STATUS, &ok);
    if (!ok) {
        GLsizei size = 0;
        char log[3500] = {0};
        glGetShaderInfoLog(object, sizeof(log), &size, log);
        snprintf(r->error, sizeof(r->error), "Shader compile failed: %.3500s", log);
        glDeleteShader(object);
        return 0;
    }
    return object;
}

static GLuint program(struct run *r, const char *fragment)
{
    GLuint vs = shader(r, GL_VERTEX_SHADER, vertex);
    GLuint fs = vs ? shader(r, GL_FRAGMENT_SHADER, fragment) : 0;
    if (!vs || !fs) {
        if (vs) glDeleteShader(vs);
        return 0;
    }
    GLuint object = glCreateProgram();
    glAttachShader(object, vs); glAttachShader(object, fs);
    glLinkProgram(object);
    glDeleteShader(vs); glDeleteShader(fs);
    GLint ok = 0;
    glGetProgramiv(object, GL_LINK_STATUS, &ok);
    if (!ok) {
        char log[3500] = {0}; GLsizei size = 0;
        glGetProgramInfoLog(object, sizeof(log), &size, log);
        snprintf(r->error, sizeof(r->error), "Program link failed: %.3500s", log);
        glDeleteProgram(object);
        return 0;
    }
    return object;
}

static bool init_egl(struct run *r)
{
    text_copy(r->stage, sizeof(r->stage), "egl-init");
    r->display = eglGetDisplay(EGL_DEFAULT_DISPLAY);
    if (r->display == EGL_NO_DISPLAY || !eglInitialize(r->display, NULL, NULL))
        { r->egl_error = eglGetError(); return fail(r, "eglGetDisplay/eglInitialize failed; shell GPU permission or display may be unsupported"); }
    r->initialized = true;
    if (!eglBindAPI(EGL_OPENGL_ES_API))
        { r->egl_error = eglGetError(); return fail(r, "eglBindAPI failed"); }
    const EGLint config_attributes[] = {
        EGL_SURFACE_TYPE, EGL_PBUFFER_BIT, EGL_RENDERABLE_TYPE, EGL_OPENGL_ES3_BIT_KHR,
        EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8, EGL_BLUE_SIZE, 8, EGL_ALPHA_SIZE, 8,
        EGL_NONE,
    };
    EGLConfig config; EGLint count = 0;
    if (!eglChooseConfig(r->display, config_attributes, &config, 1, &count) || count != 1)
        { r->egl_error = eglGetError(); return fail(r, "No GLES3 pbuffer config"); }
    const EGLint surface_attributes[] = {EGL_WIDTH, 1, EGL_HEIGHT, 1, EGL_NONE};
    const EGLint context_attributes[] = {EGL_CONTEXT_CLIENT_VERSION, 3, EGL_NONE};
    r->surface = eglCreatePbufferSurface(r->display, config, surface_attributes);
    r->context = eglCreateContext(r->display, config, EGL_NO_CONTEXT, context_attributes);
    if (r->surface == EGL_NO_SURFACE || r->context == EGL_NO_CONTEXT ||
        !eglMakeCurrent(r->display, r->surface, r->surface, r->context))
        { r->egl_error = eglGetError(); return fail(r, "GLES3 pbuffer/context creation or make-current failed"); }
    r->current = true;
    text_copy(r->vendor, sizeof(r->vendor), (const char *)glGetString(GL_VENDOR));
    text_copy(r->renderer, sizeof(r->renderer), (const char *)glGetString(GL_RENDERER));
    text_copy(r->version, sizeof(r->version), (const char *)glGetString(GL_VERSION));
    text_copy(r->glsl, sizeof(r->glsl), (const char *)glGetString(GL_SHADING_LANGUAGE_VERSION));
    text_copy(r->extensions, sizeof(r->extensions), (const char *)glGetString(GL_EXTENSIONS));
    GLint major = 0; glGetIntegerv(GL_MAJOR_VERSION, &major);
    if (major < 3)
        return fail(r, "Context is not GLES3");
    return gl_ok(r, "egl-context-identification");
}

static GLuint make_texture(GLenum internal, unsigned width, unsigned height,
                           GLenum format, GLenum type, const void *data)
{
    GLuint object = 0; glGenTextures(1, &object);
    glBindTexture(GL_TEXTURE_2D, object);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glTexImage2D(GL_TEXTURE_2D, 0, (GLint)internal, (GLsizei)width, (GLsizei)height,
                 0, format, type, data);
    return object;
}

static GLenum attach(GLuint *fbo, GLuint texture)
{
    glGenFramebuffers(1, fbo); glBindFramebuffer(GL_FRAMEBUFFER, *fbo);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, texture, 0);
    GLenum buffer = GL_COLOR_ATTACHMENT0; glDrawBuffers(1, &buffer);
    return glCheckFramebufferStatus(GL_FRAMEBUFFER);
}

static bool draw(struct run *r, GLuint prog, GLuint target, GLuint source,
                 const char *stage)
{
    glBindFramebuffer(GL_FRAMEBUFFER, target);
    glViewport(0, 0, (GLsizei)r->width, (GLsizei)r->height);
    glUseProgram(prog); glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, source);
    GLint location = glGetUniformLocation(prog, "src");
    if (location >= 0) glUniform1i(location, 0);
    glDrawArrays(GL_TRIANGLES, 0, 3);
    return gl_ok(r, stage);
}

static bool capture(struct run *r, GLuint prog, GLuint source, uint32_t *bits,
                    const char *stage)
{
    /* Different sentinels ensure untouched memory/empty readback cannot pass. */
    memset(bits, 0xa5, r->pixels * 4 * sizeof(*bits));
    const GLuint sentinel[] = {0xdeadbeefu, 0x12345678u, 0xabcdef09u, 0xdeadc0deu};
    glBindFramebuffer(GL_FRAMEBUFFER, r->integer_fbo);
    glClearBufferuiv(GL_COLOR, 0, sentinel);
    if (!gl_ok(r, "integer-capture-clear-sentinel")) return false;
    if (!draw(r, prog, r->integer_fbo, source, stage)) return false;
    glReadPixels(0, 0, (GLsizei)r->width, (GLsizei)r->height,
                 GL_RGBA_INTEGER, GL_UNSIGNED_INT, bits);
    if (!gl_ok(r, stage)) return false;
    for (size_t i = 0; i < r->pixels; i++)
        if (bits[i*4+3] != 0x3f800000u)
            return fail(r, "Capture coverage sentinel survived: draw/readback incomplete");
    return true;
}

static void compare(struct compare *s, const float *input, const uint32_t *a,
                    const uint32_t *b, size_t count)
{
    for (size_t i = 0; i < count; i++) {
        bool pq = true;
        for (unsigned k = 0; k < 3; k++)
            pq &= isfinite(input[i*4+k]) && input[i*4+k] >= 0.0f && input[i*4+k] <= 1.0f;
        for (unsigned k = 0; k < 3; k++) {
            uint32_t av = a[i*4+k], bv = b[i*4+k];
            float af = bits_float(av), bf = bits_float(bv);
            bool finite = isfinite(input[i*4+k]);
            s->components++;
            if (isfinite(af) && isfinite(bf)) s->finite_output_components++;
            if (finite) s->finite_input_components++;
            if (pq) s->pq_domain_components++;
            if (av == bv) continue;
            s->mismatches++;
            s->mismatch_baseline_class[half_value_class(av)]++;
            if (finite) s->finite_input_mismatches++;
            else s->nonfinite_input_mismatches++;
            if (pq) s->pq_domain_mismatches++;
            if ((av & 0x7fffffffu) == 0 && (bv & 0x7fffffffu) == 0)
                s->signed_zero_mismatches++;
            if (isfinite(af) && isfinite(bf)) {
                s->finite_output_mismatches++;
                double difference = fabs((double)af - bf);
                if (difference > s->max_finite_abs) s->max_finite_abs = difference;
            } else s->nonfinite_output_mismatches++;
            if (s->first_count < FIRST_DIFFS) {
                struct diff *d = &s->first[s->first_count++];
                d->pixel = i; d->channel = k; d->a = av; d->b = bv;
                for (unsigned j = 0; j < 3; j++) d->input[j] = float_bits(input[i*4+j]);
            }
        }
    }
}

static bool observe_storage_models(struct small_observation *s,
                                   const float *input, const uint32_t *baseline,
                                   size_t count)
{
    for (size_t i = 0; i < count; i++) for (unsigned k = 0; k < 3; k++) {
        uint32_t bits = float_bits(input[i*4+k]), magnitude = bits & 0x7fffffffu;
        if (!magnitude) s->input_zero++;
        else if (magnitude >= 0x7f800000u) s->input_nonfinite++;
        else if (magnitude < 0x00800000u) s->input_f32_subnormal++;
        else if (magnitude < 0x33800000u) s->input_below_half_min++;
        else if (magnitude < 0x38800000u) s->input_half_subnormal_interval++;
        else s->input_half_normal_or_larger++;
        if (!magnitude || magnitude >= 0x38800000u) continue;
        uint32_t rne = 0, rtz = 0;
        if (!small_model_bits(bits, true, &rne) || !small_model_bits(bits, false, &rtz))
            return false;
        uint32_t actual = baseline[i*4+k];
        enum half_value_class type = half_value_class(actual);
        bool rne_ok = rne == actual, rtz_ok = rtz == actual;
        s->modeled_components++;
        s->baseline_class[type]++;
        if (rne_ok) s->rne_match++;
        else { s->rne_mismatch++; s->rne_mismatch_baseline_class[type]++; }
        if (rtz_ok) s->rtz_match++;
        else { s->rtz_mismatch++; s->rtz_mismatch_baseline_class[type]++; }
        if (rne_ok && rtz_ok) s->both_match++;
        else if (rne_ok) s->rne_only_match++;
        else if (rtz_ok) s->rtz_only_match++;
        else s->neither_match++;
    }
    return true;
}

static bool run_gpu(struct run *r)
{
    if (!host_selftest()) return fail(r, "CPU decoder/dataset self-test failed");
    float *values = calloc(DATA_LIMIT, sizeof(*values));
    if (!values) return fail(r, "Input-value allocation failed");
    r->samples = make_values(values); r->width = TEX_WIDTH;
    r->height = (unsigned)((r->samples + TEX_WIDTH - 1) / TEX_WIDTH);
    r->pixels = (size_t)r->width * r->height;
    float *input = malloc(r->pixels * 4 * sizeof(*input));
    uint32_t *a = malloc(r->pixels * 4 * sizeof(*a));
    uint32_t *b = malloc(r->pixels * 4 * sizeof(*b));
    bool ok = false;
    if (!input || !a || !b) { fail(r, "GPU staging allocation failed"); goto done; }
    for (size_t i = 0; i < r->pixels; i++) {
        input[i*4] = values[i % r->samples];
        input[i*4+1] = values[(i + 7918) % r->samples];
        input[i*4+2] = values[(i + 15400) % r->samples];
        input[i*4+3] = 1.0f;
    }
    const float corners[][3] = {
        {0,0,0}, {1,1,1}, {1,0,0}, {0,1,0}, {0,0,1},
        {1,1,0}, {1,0,1}, {0,1,1}, {0.5f,0.5f,0.5f},
        {0.001f,0.002f,0.003f}, {0.1f,0.7f,0.9f},
    };
    for (size_t i = 0; i < sizeof(corners)/sizeof(corners[0]); i++)
        for (unsigned k = 0; k < 3; k++) input[i*4+k] = corners[i][k];
    if (!init_egl(r)) goto done;
    glDisable(GL_BLEND); glDisable(GL_SCISSOR_TEST); glDisable(GL_DEPTH_TEST);
    glDisable(GL_STENCIL_TEST); glDisable(GL_CULL_FACE); glDisable(GL_DITHER);
    glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE);
    glPixelStorei(GL_PACK_ALIGNMENT, 1); glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
    glGenVertexArrays(1, &r->vao); glBindVertexArray(r->vao);
    r->input = make_texture(GL_RGBA32F, r->width, r->height, GL_RGBA, GL_FLOAT, input);
    r->half = make_texture(GL_RGBA16F, r->width, r->height, GL_RGBA, GL_HALF_FLOAT, NULL);
    r->integer_tex = make_texture(GL_RGBA32UI, r->width, r->height, GL_RGBA_INTEGER, GL_UNSIGNED_INT, NULL);
    r->half_status = attach(&r->half_fbo, r->half);
    r->integer_status = attach(&r->integer_fbo, r->integer_tex);
    if (!gl_ok(r, "texture-fbo-setup")) goto done;
    if (r->half_status != GL_FRAMEBUFFER_COMPLETE || r->integer_status != GL_FRAMEBUFFER_COMPLETE) {
        fail(r, "RGBA16F or RGBA32UI framebuffer unsupported/incomplete"); goto done;
    }
    r->copy_program = program(r, copy_fragment);
    r->self_program = program(r, self_fragment);
    if (!r->copy_program || !r->self_program) goto done;
    if (!capture(r, r->self_program, 0, a, "integer-readback-selftest")) goto done;
    r->integer_selftest = true;
    for (size_t i = 0; i < r->pixels; i++) {
        const uint32_t expected[] = {0x01234567u, 0x89abcdefu, (uint32_t)i ^ 0x13579bdfu, 0x3f800000u};
        for (unsigned k = 0; k < 4; k++) if (a[i*4+k] != expected[k]) r->integer_selftest = false;
    }
    if (!r->integer_selftest) { fail(r, "Integer write/read self-test failed (empty or altered readback)"); goto done; }
    for (unsigned q = 0; q < 2; q++) for (unsigned c = 0; c < 2; c++) {
        char source[4096];
        snprintf(source, sizeof(source), "#version 300 es\n#define QUANTIZE_INPUT %u\n#define APPLY_CSC %u\n#define HIGHP_SMALL_RTZ %u\n%s",
                 q, c, r->highp_small_rtz ? 1u : 0u, capture_body);
        r->capture[q][c] = program(r, source);
    }
    if (!r->capture[0][0] || !r->capture[0][1] ||
        !r->capture[1][0] || !r->capture[1][1]) goto done;
    if (!capture(r, r->capture[0][0], r->input, a, "input-transfer-selftest")) goto done;
    for (size_t i = 0; i < r->samples; i++) for (unsigned k = 0; k < 3; k++) {
        uint32_t expected = float_bits(input[i*4+k]);
        if (a[i*4+k] == expected) continue;
        if (!isfinite(input[i*4+k])) { r->input_nonfinite_mismatches++; continue; }
        if ((expected & 0x7f800000u) == 0 && (expected & 0x7fffffu)) r->input_subnormal_mismatches++;
        else r->input_normal_mismatches++;
    }
    r->input_transfer_valid = r->input_normal_mismatches == 0 &&
                              r->input_subnormal_mismatches == 0;
    if (!r->input_transfer_valid) {
        fail(r, "Unsupported input domain: a finite RGBA32F input changed bits before comparison (including subnormal/signed zero)");
        goto done;
    }
    if (!draw(r, r->copy_program, r->half_fbo, r->input, "real-rgba16f-storage")) goto done;
    if (!capture(r, r->capture[0][0], r->half, a, "half-storage-bit-capture") ||
        !capture(r, r->capture[1][0], r->input, b, "pack-unpack-bit-capture")) goto done;
    if (!observe_storage_models(&r->small, input, a, r->samples)) {
        fail(r, "CPU small-value observation model rejected an in-domain input"); goto done;
    }
    compare(&r->quant, input, a, b, r->samples);
    if (!capture(r, r->capture[0][1], r->half, a, "half-storage-csc-bit-capture") ||
        !capture(r, r->capture[1][1], r->input, b, "pack-unpack-csc-bit-capture")) goto done;
    compare(&r->csc, input, a, b, r->samples);
    ok = gl_ok(r, "complete");
done:
    free(values); free(input); free(a); free(b);
    return ok;
}

static void cleanup(struct run *r)
{
    r->cleanup_complete = true;
    if (r->current) {
        glDeleteProgram(r->copy_program); glDeleteProgram(r->self_program);
        for (unsigned q = 0; q < 2; q++) for (unsigned c = 0; c < 2; c++) glDeleteProgram(r->capture[q][c]);
        glDeleteFramebuffers(1, &r->half_fbo); glDeleteFramebuffers(1, &r->integer_fbo);
        glDeleteTextures(1, &r->input); glDeleteTextures(1, &r->half);
        glDeleteTextures(1, &r->integer_tex); glDeleteVertexArrays(1, &r->vao);
        for (unsigned i = 0; i < 32 && glGetError() != GL_NO_ERROR; i++)
            r->cleanup_gl_errors++;
        if (r->cleanup_gl_errors) r->cleanup_complete = false;
        if (!eglMakeCurrent(r->display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT))
            r->cleanup_complete = false;
    }
    if (r->initialized) {
        if (r->context != EGL_NO_CONTEXT && !eglDestroyContext(r->display, r->context)) r->cleanup_complete = false;
        if (r->surface != EGL_NO_SURFACE && !eglDestroySurface(r->display, r->surface)) r->cleanup_complete = false;
        if (!eglTerminate(r->display)) r->cleanup_complete = false;
        r->cleanup_egl_error = eglGetError();
        if (r->cleanup_egl_error != EGL_SUCCESS) r->cleanup_complete = false;
    }
}

static void json_string(FILE *f, const char *text)
{
    fputc('"', f);
    for (const unsigned char *p = (const unsigned char *)text; *p; p++) {
        if (*p == '"' || *p == '\\') { fputc('\\', f); fputc(*p, f); }
        else if (*p < 32) fprintf(f, "\\u%04x", *p);
        else fputc(*p, f);
    }
    fputc('"', f);
}

static void print_compare(FILE *f, const struct compare *s)
{
    fprintf(f, "{\"components\":%"PRIu64",\"bitMismatches\":%"PRIu64
            ",\"finiteInputComponents\":%"PRIu64",\"finiteInputBitMismatches\":%"PRIu64
            ",\"nonfiniteInputBitMismatches\":%"PRIu64",\"finiteOutputComponents\":%"PRIu64
            ",\"finiteOutputBitMismatches\":%"PRIu64",\"nonfiniteOutputBitMismatches\":%"PRIu64
            ",\"pqDomainComponents\":%"PRIu64",\"pqDomainBitMismatches\":%"PRIu64
            ",\"signedZeroBitMismatches\":%"PRIu64",\"maxFiniteAbsDifference\":%.17g,"
            "\"mismatchByBaselineValueClass\":{\"halfZero\":%"PRIu64",\"halfSubnormal\":%"PRIu64
            ",\"halfNormal\":%"PRIu64",\"nonfinite\":%"PRIu64",\"other\":%"PRIu64"},\"firstDifferences\":[",
            s->components, s->mismatches, s->finite_input_components,
            s->finite_input_mismatches, s->nonfinite_input_mismatches, s->finite_output_components,
            s->finite_output_mismatches, s->nonfinite_output_mismatches, s->pq_domain_components,
            s->pq_domain_mismatches, s->signed_zero_mismatches, s->max_finite_abs,
            s->mismatch_baseline_class[HALF_ZERO], s->mismatch_baseline_class[HALF_SUBNORMAL],
            s->mismatch_baseline_class[HALF_NORMAL], s->mismatch_baseline_class[HALF_NONFINITE],
            s->mismatch_baseline_class[HALF_OTHER]);
    for (unsigned i = 0; i < s->first_count; i++) {
        const struct diff *d = &s->first[i];
        fprintf(f, "%s{\"pixel\":%zu,\"channel\":%u,\"inputRGBBits\":[\"%08"PRIx32"\",\"%08"PRIx32"\",\"%08"PRIx32"\"],\"baselineBits\":\"%08"PRIx32"\",\"candidateBits\":\"%08"PRIx32"\"}",
                i ? "," : "", d->pixel, d->channel, d->input[0], d->input[1], d->input[2], d->a, d->b);
    }
    fputs("]}", f);
}

static void print_classes(FILE *f, const uint64_t counts[HALF_CLASS_COUNT])
{
    fprintf(f, "{\"halfZero\":%"PRIu64",\"halfSubnormal\":%"PRIu64
            ",\"halfNormal\":%"PRIu64",\"nonfinite\":%"PRIu64",\"other\":%"PRIu64"}",
            counts[HALF_ZERO], counts[HALF_SUBNORMAL], counts[HALF_NORMAL],
            counts[HALF_NONFINITE], counts[HALF_OTHER]);
}

static void print_models(FILE *f, const struct small_observation *s)
{
    fputs("{\"scope\":\"Observed baseline vs CPU hypotheses for nonzero finite abs(input)<2^-14 only; no whole-GPU rounding rule is asserted\",", f);
    fprintf(f, "\"inputDomainComponents\":{\"zero\":%"PRIu64",\"float32Subnormal\":%"PRIu64
            ",\"normalFloat32BelowHalfMinSubnormal\":%"PRIu64",\"halfSubnormalInterval\":%"PRIu64
            ",\"halfNormalOrLargerFinite\":%"PRIu64",\"nonfinite\":%"PRIu64"},"
            "\"modeledComponents\":%"PRIu64",\"rneMatches\":%"PRIu64",\"rneMismatches\":%"PRIu64
            ",\"rtzMatches\":%"PRIu64",\"rtzMismatches\":%"PRIu64",\"bothMatch\":%"PRIu64
            ",\"rneOnlyMatch\":%"PRIu64",\"rtzOnlyMatch\":%"PRIu64",\"neitherMatch\":%"PRIu64
            ",\"modeledBaselineValueClass\":",
            s->input_zero, s->input_f32_subnormal, s->input_below_half_min,
            s->input_half_subnormal_interval, s->input_half_normal_or_larger,
            s->input_nonfinite, s->modeled_components, s->rne_match, s->rne_mismatch,
            s->rtz_match, s->rtz_mismatch, s->both_match, s->rne_only_match,
            s->rtz_only_match, s->neither_match);
    print_classes(f, s->baseline_class);
    fputs(",\"rneMismatchBaselineValueClass\":", f); print_classes(f, s->rne_mismatch_baseline_class);
    fputs(",\"rtzMismatchBaselineValueClass\":", f); print_classes(f, s->rtz_mismatch_baseline_class);
    fputc('}', f);
}

static bool write_result(FILE *f, const struct run *r, bool completed)
{
    /* The FD was exclusively created and already contains a non-success
     * running record. Interrupting this rewrite can only leave running,
     * empty or partial JSON, never a prior invocation's successful result. */
    if (fflush(f) || ftruncate(fileno(f), 0) || fseek(f, 0, SEEK_SET))
        return false;
    const char *status = !completed ? "unsupported-or-error" :
        r->quant.finite_input_mismatches ? "finite-quantization-mismatch" :
        r->csc.finite_output_mismatches ? "finite-csc-mismatch" :
        (r->input_nonfinite_mismatches || r->quant.mismatches || r->csc.mismatches) ?
        "differences-outside-finite-pq-gates" : "bit-equal-on-tested-dataset";
    fprintf(f, "{\"schemaVersion\":1,\"status\":"); json_string(f, status);
    fputs(",\"candidateMode\":", f); json_string(f, r->candidate_mode);
    fprintf(f, ",\"completed\":%s,\"stage\":", completed ? "true" : "false"); json_string(f, r->stage);
    fputs(",\"error\":", f); json_string(f, r->error);
    fputs(",\"GLVendor\":", f); json_string(f, r->vendor);
    fputs(",\"GLRenderer\":", f); json_string(f, r->renderer);
    fputs(",\"GLVersion\":", f); json_string(f, r->version);
    fputs(",\"GLSLVersion\":", f); json_string(f, r->glsl);
    fputs(",\"GLExtensions\":", f); json_string(f, r->extensions);
    fprintf(f, ",\"width\":%u,\"height\":%u,\"samplePixels\":%zu,\"allocatedPixels\":%zu,"
            "\"rgba16fFboStatus\":%u,\"rgba32uiFboStatus\":%u,\"glErrorCount\":%u,\"firstGlError\":%u,\"eglError\":%u,"
            "\"cleanupComplete\":%s,\"cleanupGlErrors\":%u,\"cleanupEglError\":%u,"
            "\"integerReadbackSelftest\":%s,\"inputTransferValid\":%s,\"inputNormalBitMismatches\":%"PRIu64
            ",\"inputSubnormalBitMismatches\":%"PRIu64",\"inputNonfiniteBitMismatches\":%"PRIu64
            ",\"quantizationFiniteInputsBitEqual\":%s,\"cscFiniteOutputsBitEqual\":%s,\"cscPQDomainBitEqual\":%s,\"quantization\":",
            r->width, r->height, r->samples, r->pixels, r->half_status, r->integer_status,
            r->gl_errors, r->first_gl_error, r->egl_error,
            r->cleanup_complete ? "true" : "false", r->cleanup_gl_errors, r->cleanup_egl_error,
            r->integer_selftest ? "true" : "false",
            r->input_transfer_valid ? "true" : "false", r->input_normal_mismatches,
            r->input_subnormal_mismatches, r->input_nonfinite_mismatches,
            completed && r->quant.finite_input_components && !r->quant.finite_input_mismatches ? "true" : "false",
            completed && r->csc.finite_output_components && !r->csc.finite_output_mismatches ? "true" : "false",
            completed && r->csc.pq_domain_components && !r->csc.pq_domain_mismatches ? "true" : "false");
    print_compare(f, &r->quant); fputs(",\"csc\":", f); print_compare(f, &r->csc);
    fputs(",\"smallBaselineModelObservation\":", f); print_models(f, &r->small);
    fputs(",\"limits\":[\"Synthetic values, not captured renderer output or media frames.\","
          "\"CSC comparison uses highp numeric RGB capture, not layout(yuv) or NV12 driver output.\","
          "\"Nonfinite payloads and signed zero remain explicitly counted; no numeric tolerance is used.\","
          "\"highp-small-rtz is a hypothesis mode, not an assumed GPU rounding rule; only actual comparisons decide equality.\","
          "\"Only this process EGL pbuffer is used; no media, display settings or existing context are modified.\","
          "\"Equality here cannot prove fused playback shader, source-frame, YUV carrier or panel equivalence.\"]}\n", f);
    bool ok = !ferror(f) && fflush(f) == 0;
    if (ok && fsync(fileno(f))) ok = false;
    return ok;
}

int main(int argc, char **argv)
{
    if (argc < 2 || argc > 3 || (argc == 3 && strcmp(argv[2], "builtin") && strcmp(argv[2], "highp-small-rtz"))) {
        fprintf(stderr, "usage: %s /new/result.json [builtin|highp-small-rtz]\n", argv[0]); return 64;
    }
    const char *candidate = argc == 3 ? argv[2] : "builtin";
    int output_fd = open(argv[1], O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0600);
    if (output_fd < 0) {
        fprintf(stderr, "Refusing existing/unwritable result path %s: %s\n", argv[1], strerror(errno));
        return 73;
    }
    FILE *output = fdopen(output_fd, "w");
    if (!output) { close(output_fd); return 74; }
    if (fprintf(output, "{\"schemaVersion\":1,\"status\":\"running\",\"completed\":false,\"candidateMode\":\"%s\",\"pid\":%ld}\n", candidate, (long)getpid()) < 0 ||
        fflush(output) || fsync(output_fd)) {
        fclose(output);
        return 74;
    }
    /* Default SIGALRM terminates a stalled isolated diagnostic, never leaves
     * a long-running GPU workload. A missing result is not an equality pass. */
    alarm(30);
    struct run *r = calloc(1, sizeof(*r));
    if (!r) { fclose(output); return 70; }
    r->candidate_mode = candidate;
    r->highp_small_rtz = strcmp(candidate, "highp-small-rtz") == 0;
    r->display = EGL_NO_DISPLAY; r->context = EGL_NO_CONTEXT; r->surface = EGL_NO_SURFACE;
    bool complete = run_gpu(r);
    cleanup(r);
    complete &= r->cleanup_complete;
    bool written = write_result(output, r, complete);
    if (fclose(output)) written = false;
    int result = !written ? 74 : !complete ? 2 :
        (r->quant.finite_input_mismatches || r->csc.finite_output_mismatches) ? 3 :
        (r->input_nonfinite_mismatches || r->quant.mismatches || r->csc.mismatches) ? 4 : 0;
    free(r);
    alarm(0);
    return result;
}
#endif
