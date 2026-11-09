"""Exercise extracted renderer cache selection with the real mapper doubles.

The queue, renderer state, GPU and codec are doubles; this does not execute
libplacebo's complete render pass or prove a real playback sequence.
"""
from pathlib import Path
import subprocess
import tempfile
import unittest

from test_lg_p84_mapper_contract import function
from test_lg_p84_surface_lease import HWDEC, STUBS, SURFACE, TEST, check_fixture_constants


RENDERER = (Path.home() / 'src/libmpv-android-video-build-dv-experiment/'
            'buildscripts/deps/libplacebo/src/renderer.c')


def mapper_functions():
    surface = SURFACE.read_text()
    check_fixture_constants(surface)
    names = ('lease_dims_for_map', 'lease_matches', 'retired_find', 'fence_delete',
             'fence_create', 'lease_release', 'consumed_find', 'evicted_find',
             'consumed_add', 'retired_take', 'retire_reap', 'mapper_publish_lease',
             'mapper_adopt_retired', 'take_slot', 'mapper_map', 'mapper_unmap', 'mapper_uninit')
    returns = ('void', 'bool', 'int', 'void', 'GLsync', 'void', 'bool', 'bool',
               'void', 'struct mkst_lease', 'void', 'void', 'void', 'int', 'int', 'void', 'void')

    def extract(name, result):
        if result in ('void', 'int'):
            return 'static ' + result + ' ' + function(surface, name)
        start = surface.index('static ' + result + ' ' + name + '(')
        opening = surface.index('{', start)
        depth = 0
        for i in range(opening, len(surface)):
            depth += (surface[i] == '{') - (surface[i] == '}')
            if depth == 0:
                return surface[start:i + 1]
        raise ValueError('unclosed function: ' + name)

    common = HWDEC.read_text()
    selected = '\n'.join(extract(name, result) for name, result in zip(names, returns))
    wrappers = ('void ' + function(common, 'ra_hwdec_mapper_unmap') + '\n' +
                'int ra_hwdec_mapper_map_with_request(struct ra_hwdec_mapper *, struct mp_image *, '
                'const struct ra_hwdec_map_request *);\n' +
                'int ' + function(common, 'ra_hwdec_mapper_map') + '\n' +
                'int ' + function(common, 'ra_hwdec_mapper_map_with_request'))
    return selected + '\n' + wrappers


class MixCacheTests(unittest.TestCase):
    def test_cache_selection_and_mapper_retirement(self):
        renderer = RENDERER.read_text()
        start = renderer.index('        struct cached_frame *f = NULL;',
                               renderer.index('bool pl_render_image_mix('))
        end = renderer.index('        if (!can_reuse) {', start)
        selection = renderer[start:end]
        regression = TEST.replace('int main(void) {', 'static int regression_main(void) {', 1)
        with tempfile.TemporaryDirectory() as tmp:
            source, exe = Path(tmp) / 'test.c', Path(tmp) / 'test'
            source.write_text(STUBS + mapper_functions() + regression + CACHE_STUBS +
                              selection + CACHE_FINISH + CASES)
            subprocess.run(['clang', '-std=c11', '-Wall', '-Wextra', '-Werror',
                            str(source), '-lm', '-o', str(exe)], check=True, timeout=30)
            subprocess.run([str(exe)], check=True, timeout=5)


CACHE_STUBS = r'''
struct rect2d { int x0,y0,x1,y1; };
struct fake_tex { struct { int w,h; } params; };
struct cached_frame {
    uint64_t signature,params_hash;
    bool evict;
    struct fake_tex *tex,storage;
    struct rect2d crop;
    int color,profile;
};
struct image { int index; struct rect2d crop; };
struct cache_list { struct cached_frame elem[16]; int num; };
struct renderer { struct cache_list frames; };
struct render_params { bool skip_caching_single_frame,preserve_mixing_cache; };
struct params_info { bool trivial; uint64_t hash; };
struct target { int color,profile; };
#define PL_TRACE(...) ((void)0)
#define PL_ARRAY_GROW(owner,array) do { (void)(owner); assert((array).num<16); } while (0)
static bool pl_rect2d_eq(struct rect2d a,struct rect2d b) {
    return a.x0==b.x0 && a.y0==b.y0 && a.x1==b.x1 && a.y1==b.y1;
}
static bool pl_color_space_equal(const int *a,const int *b) { return *a==*b; }
static bool pl_icc_profile_equal(const int *a,const int *b) { return *a==*b; }
static int acquisitions[4],last_failed;
static struct ra_tex *published[4];
static struct ra_hwdec_map_request target_request;
static int render(struct renderer *rr,struct image *images,int count,uint64_t salt,
                  bool single_frame,struct render_params *params,int out_w,int out_h) {
    struct params_info par_info={.hash=42};
    struct target value={0};struct target *target=&value;
    struct image *refimg=&images[count>1 ? 1 : 0];
    for (int i=0;i<count;i++) {
        uint64_t sig=(uint64_t)(images[i].index+1)^salt;
        float weight=1.0f;
        const struct image *img=&images[i];
'''


CACHE_FINISH = r'''
        if (!can_reuse) {
            acquisitions[img->index]++;
            if (map_frame(img->index,&target_request)<0) {
                last_failed=img->index;
                return -1;
            }
            assert(p.cur.source && p.cur.source->planes[3]==frames[img->index].planes[3]);
            assert(p.cur.src_pts==frames[img->index].pts && p.cur.slot>=0);
            assert(mapper.tex[0] && mapper.tex[0]==p.slots[p.cur.slot].tex);
            assert_texture_content(mapper.tex[0],frames[img->index].planes[3],p.cur.latch_ts);
            if (target_request.allow_full_frame_scale) geometry(2672,1336);
            else assert(mapper.tex[0]->w==3840 && mapper.tex[0]->h==1920);
            published[img->index]=mapper.tex[0];
            ra_hwdec_mapper_unmap(&mapper);
            f->storage.params.w=out_w;f->storage.params.h=out_h;f->tex=&f->storage;
            f->crop=img->crop;f->params_hash=par_info.hash;
            f->color=target->color;f->profile=target->profile;
        }
    }
    return 0;
fallback:
    return -2;
}
'''


CASES = r'''
static void scenario(bool use_target,int change) {
    reset(use_target);p.have_fence=true;
    target_request=use_target ? target : (struct ra_hwdec_map_request){0};
    memset(acquisitions,0,sizeof(acquisitions));memset(published,0,sizeof(published));last_failed=-1;
    struct renderer rr={0};
    struct render_params params={.preserve_mixing_cache=true};
    struct image images[4];
    for (int i=0;i<4;i++) images[i]=(struct image){.index=i,.crop={0,0,3840,1920}};
    assert(render(&rr,images,3,0,false,&params,2672,1336)==0);
    assert(releases==3 && latches==3 && draws==3 && p.retired_count==3);
    assert(published[0] && published[0]->w==(use_target ? 2672 : 3840));
    assert(published[0]->h==(use_target ? 1336 : 1920));
    assert(render(&rr,images,3,0,false,&params,2672,1336)==0);
    assert(acquisitions[0]==1 && acquisitions[1]==1 && acquisitions[2]==1);
    assert(render(&rr,images,4,0,false,&params,2672,1336)==0);
    assert(acquisitions[0]==1 && acquisitions[3]==1 && p.reap_count==1);
    assert(p.retired[0].source->planes[3]==frames[1].planes[3]);
    assert(releases==4 && latches==4 && draws==4 && !p.reap_stuck_count);
    if (change==0) {
        assert(render(&rr,images,4,UINT64_C(1)<<48,false,&params,2672,1336)==-1);
    } else {
        /* Separate width and height changes isolate both strict comparisons. */
        int out_w=change==1 ? 1920 : 2672;
        int out_h=change==1 ? 1336 : 960;
        /* preserve=true accepts an old-size cache: resize alone need not reacquire. */
        assert(render(&rr,images,4,0,false,&params,out_w,out_h)==0);
        assert(acquisitions[0]==1);
        params.preserve_mixing_cache=false;
        assert(render(&rr,images,4,0,false,&params,out_w,out_h)==-1);
    }
    assert(last_failed==0 && acquisitions[0]==2 && p.horizon_overflow_count==1);
    assert(releases==4 && latches==4 && draws==4);
    assert(map_frame(1,NULL)==0 && releases==4 && latches==4 && draws==4);
    assert(p.cur.source && p.cur.source->planes[3]==frames[1].planes[3]);
    assert(p.cur.src_pts==frames[1].pts && p.cur.slot>=0);
    assert(mapper.tex[0]==published[1] && p.slots[p.cur.slot].tex==published[1]);
    assert_texture_content(mapper.tex[0],frames[1].planes[3],p.cur.latch_ts);
    assert(mapper.tex[0]->w==(use_target ? 2672 : 3840));
    assert(mapper.tex[0]->h==(use_target ? 1336 : 1920));
    cleanup();
}
/* Isolate each strict comparison with matching signature, dimensions and all
 * earlier predicates true. The mapper remains real extracted control flow. */
static void strict_compatibility(bool use_target,int mismatch,bool preserve) {
    reset(use_target);p.have_fence=true;
    target_request=use_target ? target : (struct ra_hwdec_map_request){0};
    memset(acquisitions,0,sizeof(acquisitions));memset(published,0,sizeof(published));last_failed=-1;
    struct renderer rr={0};
    struct render_params params={.preserve_mixing_cache=preserve};
    struct image images[4];
    for (int i=0;i<4;i++) images[i]=(struct image){.index=i,.crop={0,0,3840,1920}};
    assert(render(&rr,images,3,0,false,&params,2672,1336)==0);
    assert(render(&rr,images,4,0,false,&params,2672,1336)==0);
    assert(rr.frames.num==4 && p.reap_count==1);
    assert(acquisitions[0]==1 && releases==4 && latches==4 && draws==4);
    struct cached_frame *a=&rr.frames.elem[0];
    assert(a->signature==1 && a->tex && a->tex->params.w==2672 && a->tex->params.h==1336);
    assert(pl_rect2d_eq(a->crop,images[0].crop) && a->params_hash==42);
    assert(a->color==0 && a->profile==0);
    if (mismatch==0) a->crop.x0=1;
    else if (mismatch==1) a->params_hash++;
    else if (mismatch==2) a->color=1;
    else if (mismatch==3) a->profile=1;
    else assert(mismatch==4); /* unchanged: strict reuse positive control */
    int result=render(&rr,images,4,0,false,&params,2672,1336);
    if (mismatch<4 && !preserve) {
        assert(result==-1 && last_failed==0 && acquisitions[0]==2);
        assert(p.horizon_overflow_count==1);
    } else {
        assert(result==0 && last_failed==-1 && acquisitions[0]==1);
        assert(p.horizon_overflow_count==0);
    }
    assert(releases==4 && latches==4 && draws==4);
    cleanup();
}
int main(void) {
    assert(regression_main()==0);
    for (int change=0;change<3;change++) {
        scenario(false,change);scenario(true,change);
    }
    for (int mismatch=0;mismatch<5;mismatch++)
        for (int preserve=0;preserve<2;preserve++) {
            strict_compatibility(false,mismatch,preserve);
            strict_compatibility(true,mismatch,preserve);
        }
    return 0;
}
'''


if __name__ == '__main__':
    unittest.main()
