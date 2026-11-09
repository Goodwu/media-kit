"""Exercise mp_sws_scale's error propagation with host doubles.

This does not execute FFmpeg, zimg, real image scaling, or a device.
"""
from pathlib import Path
import subprocess
import tempfile
import unittest

from test_lg_p84_mapper_contract import function


SOURCE = Path(__file__).resolve().parents[2] / 'mpv/video/sws_utils.c'


class SoftwareScaleTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        source = SOURCE.read_text()
        start = source.index('static struct mp_image *check_alignment(')
        end = source.index('// Scale from src to dst', start)
        functions = source[start:end] + 'int ' + function(source, 'mp_sws_scale')
        cls.temp = tempfile.TemporaryDirectory()
        root = Path(cls.temp.name)
        cls.exe = root / 'sws-test'
        path = root / 'sws-test.c'
        path.write_text(STUBS + functions + CASES)
        subprocess.run(['clang', '-std=c11', '-Wall', '-Wextra', '-Werror',
                        str(path), '-o', str(cls.exe)], check=True, timeout=30)

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    def test_negative_scale_return_is_propagated(self):
        subprocess.run([str(self.exe), 'negative'], check=True, timeout=5)

    def test_nonnegative_and_reused_context(self):
        subprocess.run([str(self.exe), 'success'], check=True, timeout=5)

    def test_reinit_zimg_and_alignment_failures(self):
        subprocess.run([str(self.exe), 'other'], check=True, timeout=5)


STUBS = r'''
#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#define HAVE_ZIMG 1
#define MP_IMAGE_BYTE_ALIGN 64
#define MP_IS_ALIGNED(x,a) (((x)&((a)-1))==0)
#define mp_assert assert
#define MP_ERR(...) ((void)0)
#define mp_verbose(log,...) ((void)(log))
#define PL_COLOR_SYSTEM_XYZ 1
#define PL_COLOR_TRC_GAMMA22 2
#define PL_COLOR_PRIM_BT_709 3
struct mp_log { int unused; };
struct mp_image_params { struct { int sys; } repr; struct { int transfer,primaries; } color; };
struct mp_image {
    struct mp_image_params params;
    int num_planes,imgfmt,w,h;
    uint8_t *planes[4]; int stride[4];
};
struct mp_sws_context {
    struct mp_image_params src,dst; struct mp_log *log; bool zimg_ok;
    void *zimg,*sws; struct mp_image *aligned_src,*aligned_dst;
};
static int injected,reinit_result,scale_calls,copies,allocs,zcalls;
static bool alloc_fail,zresult;
static struct mp_image pool[4];
static _Alignas(64) uint8_t data[8][1024];
static uint8_t *scale_src,*scale_dst;
static int mp_sws_reinit(struct mp_sws_context *ctx) { (void)ctx; return reinit_result; }
static bool mp_zimg_convert(void *z,struct mp_image *d,struct mp_image *s) {
    (void)z;(void)d;(void)s;zcalls++;return zresult;
}
static struct mp_image *mp_image_alloc(int fmt,int w,int h) {
    if (alloc_fail) return NULL;
    assert(allocs<4);int n=allocs++;
    pool[n]=(struct mp_image){.num_planes=1,.imgfmt=fmt,.w=w,.h=h,
                              .planes={data[n+2]},.stride={32}};
    return &pool[n];
}
static void mp_image_copy_attributes(struct mp_image *d,struct mp_image *s) {
    d->params=s->params;
}
static void mp_image_copy(struct mp_image *d,struct mp_image *s) {
    copies++;d->planes[0][0]=s->planes[0][0];
}
static int sws_scale(void *ctx,const uint8_t *const *src,const int *src_stride,
                     int y,int h,uint8_t *const *dst,const int *dst_stride) {
    (void)ctx;assert(src_stride[0]==32 && dst_stride[0]==32 && y==0 && h==10);
    scale_calls++;scale_src=(uint8_t *)src[0];scale_dst=dst[0];
    assert(src[0][0]==0x27);dst[0][0]=0x4a;return injected;
}
'''


CASES = r'''
static void reset(void) {
    memset(data,0,sizeof(data));memset(pool,0,sizeof(pool));
    injected=reinit_result=scale_calls=copies=allocs=zcalls=0;
    alloc_fail=zresult=false;scale_src=scale_dst=NULL;
}
static struct mp_image image(int n,int unaligned,int h) {
    return (struct mp_image){.num_planes=1,.w=16,.h=h,
                             .planes={data[n]+unaligned},.stride={32}};
}
static void scale_result(int result,int unaligned_src,int unaligned_dst) {
    reset();injected=result;
    struct mp_image src=image(0,unaligned_src,10),dst=image(1,unaligned_dst,8);
    struct mp_sws_context ctx={0};src.planes[0][0]=0x27;dst.planes[0][0]=0x19;
    int got=mp_sws_scale(&ctx,&dst,&src);
    assert(got==(result<0 ? result : 0));
    assert(scale_calls==1 && allocs==unaligned_src+unaligned_dst);
    assert(scale_src==(unaligned_src ? ctx.aligned_src->planes[0] : src.planes[0]));
    assert(scale_dst==(unaligned_dst ? ctx.aligned_dst->planes[0] : dst.planes[0]));
    assert(copies==unaligned_src+(result>=0 && unaligned_dst));
    if (unaligned_dst)
        assert(dst.planes[0][0]==(result<0 ? 0x19 : 0x4a));
    else
        assert(dst.planes[0][0]==0x4a); /* An error may have partially written dst. */
}
static void failures(void) {
    const int errors[]={-22,-12,-1};
    for (unsigned i=0;i<sizeof(errors)/sizeof(errors[0]);i++)
        for (int src=0;src<2;src++) for (int dst=0;dst<2;dst++)
            scale_result(errors[i],src,dst);
}
static void successes(void) {
    const int values[]={0,3,8,9};
    for (unsigned i=0;i<sizeof(values)/sizeof(values[0]);i++)
        for (int src=0;src<2;src++) for (int dst=0;dst<2;dst++)
            scale_result(values[i],src,dst);
    reset();struct mp_image src=image(0,0,10),dst=image(1,1,8);
    struct mp_sws_context ctx={0};src.planes[0][0]=0x27;dst.planes[0][0]=0x19;
    injected=-12;assert(mp_sws_scale(&ctx,&dst,&src)==-12);
    assert(ctx.aligned_dst && allocs==1 && copies==0 && dst.planes[0][0]==0x19);
    injected=0;assert(mp_sws_scale(&ctx,&dst,&src)==0);
    assert(allocs==1 && copies==1 && scale_calls==2 && dst.planes[0][0]==0x4a);
}
static void other(void) {
    reset();struct mp_image src=image(0,0,10),dst=image(1,0,8);
    struct mp_sws_context ctx={0};src.planes[0][0]=0x27;
    reinit_result=-22;assert(mp_sws_scale(&ctx,&dst,&src)==-22);
    assert(!scale_calls && !zcalls && !allocs && !copies);
    reinit_result=0;ctx.zimg_ok=true;zresult=false;
    assert(mp_sws_scale(&ctx,&dst,&src)==-1 && zcalls==1 && !scale_calls);
    zresult=true;assert(mp_sws_scale(&ctx,&dst,&src)==0 && zcalls==2 && !scale_calls);
    ctx.zimg_ok=false;reinit_result=1;injected=8;
    assert(mp_sws_scale(&ctx,&dst,&src)==0 && scale_calls==1 && !allocs && !copies);
    reset();src=image(0,1,10);dst=image(1,0,8);ctx=(struct mp_sws_context){0};
    alloc_fail=true;
    assert(mp_sws_scale(&ctx,&dst,&src)==-1 && !scale_calls && !allocs && !copies);
    reset();src=image(0,0,10);dst=image(1,1,8);ctx=(struct mp_sws_context){0};
    alloc_fail=true;
    assert(mp_sws_scale(&ctx,&dst,&src)==-1 && !scale_calls && !allocs && !copies);
}
int main(int argc,char **argv) {
    assert(argc==2);
    if (!strcmp(argv[1],"negative")) failures();
    else if (!strcmp(argv[1],"success")) successes();
    else if (!strcmp(argv[1],"other")) other();
    else assert(false);
    return 0;
}
'''


if __name__ == '__main__':
    unittest.main()
