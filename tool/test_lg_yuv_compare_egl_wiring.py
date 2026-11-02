"""Exercise the actual diagnostic EGL wiring helpers with host API doubles.

This verifies default-off and rejection policy, not the Android EGL driver.
"""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

SOURCE = Path(__file__).resolve().parents[2] / 'mpv/video/out/gpu_next/context.c'


def function(text, name):
    start = text.index('static ', text.index('// EGL 1.4'))
    start = text.rfind('static ', start, text.index(name) + len(name))
    brace = text.index('{', text.index(name, start))
    depth = 1
    end = brace + 1
    while depth:
        depth += (text[end] == '{') - (text[end] == '}')
        end += 1
    return text[start:end]


STUBS = r'''
#include <assert.h>
#include <stdbool.h>
#include <string.h>
#define EGL_NO_DISPLAY ((void*)0)
#define EGL_NO_CONTEXT ((void*)0)
#define EGL_NO_SURFACE ((void*)0)
#define EGL_DRAW 1
#define EGL_READ 2
#define RTLD_DEFAULT ((void*)0)
#define MP_ERR(...) ((void)0)
typedef void (*pl_voidfunc_t)(void);
struct gpu_ctx { void *ra_ctx; };
struct GL { void *(*get_fn)(void*,const char*); void *fn_ctx; };
struct pl_opengl_params {
    void *egl_display, *egl_context;
    pl_voidfunc_t (*get_proc_addr_ex)(void*,const char*);
    void *proc_ctx;
    bool diagnostic_yuv_compare_caps;
};
static bool owner;
static int calls, owner_calls, fallback_calls, token;
static void *display, *context, *draw, *read;
static void token_fn(void) {}
static void fallback_fn(void) {}
static void *proc;
static bool mks_android_yuv_compare_owner_current(void *c) {
    (void)c; owner_calls++; return owner;
}
static void *eglGetCurrentDisplay(void) { calls++; return display; }
static void *eglGetCurrentContext(void) { calls++; return context; }
static void *eglGetCurrentSurface(int which) { calls++; return which==EGL_DRAW?draw:read; }
static void *dlsym(void *scope, const char *name) {
    (void)scope; (void)name; fallback_calls++; return (void*)fallback_fn;
}
static void *get_proc(void *ctx, const char *name) {
    assert(ctx==&token); (void)name; return proc;
}
'''

TEST = r'''
int main(void) {
    struct gpu_ctx ctx = {0};
    struct GL gl = {.get_fn=get_proc,.fn_ctx=&token};
    struct pl_opengl_params p={0}, before=p;
    assert(configure_yuv_compare_egl(&ctx,&p,&gl,false));
    assert(!memcmp(&p,&before,sizeof(p)) && calls==0 && owner_calls==0);
    assert(!configure_yuv_compare_egl(&ctx,&p,&gl,true));
    assert(!memcmp(&p,&before,sizeof(p)) && calls==0);
    owner=true;
    display=&token; context=&token; draw=&token; read=&token;
    void **handles[]={&display,&context,&draw,&read};
    for (int i=0;i<4;i++) {
        *handles[i]=0;
        assert(!configure_yuv_compare_egl(&ctx,&p,&gl,true));
        assert(!memcmp(&p,&before,sizeof(p)));
        *handles[i]=&token;
    }
    assert(configure_yuv_compare_egl(&ctx,&p,&gl,true));
    assert(p.egl_display==display && p.egl_context==context);
    assert(p.get_proc_addr_ex==yuv_compare_get_proc && p.proc_ctx==&gl);
#ifdef PL_HAVE_MKS_YUV_COMPARE_CAPS
    assert(p.diagnostic_yuv_compare_caps);
#else
    assert(!p.diagnostic_yuv_compare_caps);
#endif
    proc=(void*)token_fn;
    assert(yuv_compare_get_proc(&gl,"eglGetCurrentContext")==token_fn && fallback_calls==0);
    proc=0;
    assert(yuv_compare_get_proc(&gl,"glSomeMissingFunction")==0 && fallback_calls==0);
    assert(yuv_compare_get_proc(&gl,"eglGetCurrentContext")==fallback_fn && fallback_calls==1);
    return 0;
}
'''


class Wiring(unittest.TestCase):
    def test_actual_helpers_default_off_owner_and_loader(self):
        compiler = shutil.which('clang')
        self.assertIsNotNone(compiler)
        text = SOURCE.read_text()
        # The diagnostic compare session keeps the strict owner/loader
        # contract; the production table drives the same capability cache
        # but degrades to no-cache instead of failing init.
        self.assertIn('bool compare_session = !strcmp(yuv_compare, "1");', text)
        self.assertIn('bool diagnostic_compare = compare_session;', text)
        self.assertIn('if (compare_session)\n                goto err_out;', text)
        self.assertIn('MKS-FUSION-TABLE event=caps-unavailable playback-continues', text)
        helpers = function(text, 'yuv_compare_get_proc') + '\n' + function(text, 'configure_yuv_compare_egl')
        for caps in (False, True):
            with self.subTest(caps=caps), tempfile.TemporaryDirectory() as directory:
                source = Path(directory) / 'test.c'
                binary = Path(directory) / 'test'
                source.write_text(('#define PL_HAVE_MKS_YUV_COMPARE_CAPS 1\n' if caps else '') + STUBS + helpers + TEST)
                subprocess.run([compiler, '-std=c11', '-Wall', '-Wextra', '-Werror', str(source), '-o', str(binary)], check=True, capture_output=True)
                subprocess.run([str(binary)], check=True, capture_output=True)


if __name__ == '__main__':
    unittest.main()
