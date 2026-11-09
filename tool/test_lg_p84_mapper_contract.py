"""Host checks for the disabled target-lease gate; not a GPU/lifecycle test."""
import ctypes
import os
from pathlib import Path
import re
import struct
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2] / 'mpv'
SURFACE = ROOT / 'video/out/hwdec/hwdec_surfacetexture.c'
HWDEC = ROOT / 'video/out/gpu/hwdec.c'
NEXT = ROOT / 'video/out/vo_gpu_next.c'


def function(source, name):
    match = re.search(r'(?m)^(?:static )?(?:void|int|bool|uint64_t|float)\s+' + re.escape(name) + r'\s*\(', source)
    if not match:
        raise ValueError('missing function: ' + name)
    position = source.index(name, match.start())
    opening = source.index('{', position)
    level = 0
    for index in range(opening, len(source)):
        if source[index] == '{':
            level += 1
        elif source[index] == '}':
            level -= 1
            if not level:
                return source[position: index + 1]
    raise ValueError('unclosed function: ' + name)


class GateTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        code = SURFACE.read_text()
        gate = 'static void ' + function(code, 'lease_dims_for_map')
        cls.temp = tempfile.TemporaryDirectory()
        root = Path(cls.temp.name)
        path = root / 'gate.c'
        path.write_text('''#include <stdbool.h>\n#include <stdint.h>\n
struct rect { int x0, y0, x1, y1; };
struct params { int w,h,rotate,vflip,p_w,p_h; struct rect crop; };
struct request { bool allow_full_frame_scale; int target_w,target_h; };
struct priv { bool opt_lease_target; };
struct ra_hwdec_mapper { void *priv; struct params src_params; int caps; struct request map_request; };
#define RA_HWDEC_CAP_MAP_GEOMETRY 1
#define mp_rect rect
static bool mp_image_crop_valid(struct params *p) {
    return p->crop.x1 > p->crop.x0 && p->crop.y1 > p->crop.y0 &&
           p->crop.x0 >= 0 && p->crop.y0 >= 0 &&
           p->crop.x1 <= p->w && p->crop.y1 <= p->h;
}
''' + gate + '''
void run_gate(int opt, int caps, int allow, int sw, int sh, int dw, int dh,
              int rotate, int flip, int pw, int ph, int x0, int y0, int x1, int y1,
              int *outw, int *outh) {
    struct priv p = {.opt_lease_target = opt};
    struct ra_hwdec_mapper m = {.priv = &p, .caps = caps,
        .src_params = {.w=sw, .h=sh, .rotate=rotate, .vflip=flip, .p_w=pw, .p_h=ph,
                       .crop={x0,y0,x1,y1}},
        .map_request = {.allow_full_frame_scale=allow, .target_w=dw, .target_h=dh}};
    lease_dims_for_map(&m, outw, outh);
}
''')
        library = root / 'gate.dylib'
        subprocess.run([os.environ.get('CC', 'cc'), '-std=c11', '-Wall', '-Werror',
                        '-dynamiclib', str(path), '-o', str(library)], check=True)
        cls.lib = ctypes.CDLL(str(library))
        cls.lib.run_gate.argtypes = [ctypes.c_int] * 15 + [ctypes.POINTER(ctypes.c_int)] * 2
        cls.lib.run_gate.restype = None

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    def gate(self, **changes):
        args = dict(opt=1, caps=1, allow=1, sw=3840, sh=1920, dw=2672, dh=1336,
                    rotate=0, flip=0, pw=1, ph=1, x0=0, y0=0, x1=0, y1=0)
        args.update(changes)
        w, h = ctypes.c_int(), ctypes.c_int()
        self.lib.run_gate(*args.values(), ctypes.byref(w), ctypes.byref(h))
        return w.value, h.value

    def test_opt_in_and_full_frame_downsample(self):
        self.assertEqual(self.gate(), (2672, 1336))
        self.assertEqual(self.gate(x1=3840, y1=1920), (2672, 1336))
        for changes in ({'opt': 0}, {'caps': 0}, {'allow': 0}, {'rotate': 90},
                        {'flip': 1}, {'pw': 2}, {'x0': 1, 'x1': 3840, 'y1': 1920},
                        {'dw': 2673}, {'dw': 3840, 'dh': 1920},
                        {'dw': 7680, 'dh': 3840}, {'dw': 0}):
            with self.subTest(changes=changes):
                self.assertEqual(self.gate(**changes), (3840, 1920))

    def test_gpu_next_consumer_opt_in_contract(self):
        text = NEXT.read_text()
        self.assertIn('ra_hwdec_mapper_create_with_caps(\n        hwdec, par, '
                      'RA_HWDEC_CAP_MAP_GEOMETRY)', text)
        self.assertIn('ra_hwdec_mapper_map_with_request(p->hwdec_mapper, mpi, reqp)', text)
        acquire = function(text, 'hwdec_acquire')
        self.assertIn('.target_w = fp->vo->dwidth', acquire)
        self.assertIn('.target_h = fp->vo->dheight', acquire)
        self.assertIn('Unexpected hwdec lease geometry', acquire)
        self.assertIn('fp->lease_w = tex0->params.w', acquire)
        # The stale lease marker is cleared before any failure return.
        self.assertLess(acquire.index('fp->lease_w = fp->lease_h = 0'),
                        acquire.index('hwdec_reconfig'))
        # The renderer's acquire-local copy is moved into the verified
        # physical space after every success, and never on a failure path.
        self.assertIn('hwdec_lease_rescale_frame(p, mpi, frame)', acquire)
        self.assertGreater(acquire.index('hwdec_lease_rescale_frame'),
                           acquire.index('hwdec_reconfig'))
        self.assertIn('mks_fgt_resume', acquire)
        self.assertNotIn('hwdec_mapped_scale', text)
        self.assertNotIn('hwdec_lease_rect(', text)
        self.assertNotIn('dst_params.w =', text)
        self.assertNotIn('dst_params.h =', text)
        # Queue frames keep classic source-space geometry; the fusion gate
        # checks logical full-frame in source space.
        draw = function(text, 'draw_frame')
        self.assertIn('apply_crop(image, p->src, vo->params->w, vo->params->h)', draw)
        rejects = function(text, 'fusion_frame_rejects')
        self.assertIn('fusion_full_rect(image->crop, mpi->w, mpi->h)', rejects)
        screenshot = function(text, 'video_screenshot')
        self.assertIn('apply_crop(&image, src, mpi->params.w, mpi->params.h)', screenshot)

    def test_clear_and_publish_are_separate(self):
        common = HWDEC.read_text()
        unmap = function(common, 'ra_hwdec_mapper_unmap')
        self.assertIn('mapper->map_geometry = (struct ra_hwdec_map_geometry){0}', unmap)
        self.assertIn('mapper->map_request = (struct ra_hwdec_map_request){0}', unmap)
        body = function(SURFACE.read_text(), 'mapper_map')
        self.assertNotIn('mapper->dst_params.w =', body)
        self.assertNotIn('mapper->dst_params.h =', body)
        self.assertLess(body.index('fence-create-failed at publish'), body.rindex('mapper_publish_lease(mapper)'))


class RescaleFrameTests(unittest.TestCase):
    """hwdec_lease_rescale_frame: acquire-local copy into lease space."""
    @classmethod
    def setUpClass(cls):
        helper = ('static float ' + function(NEXT.read_text(), 'hwdec_scale_overlay_endpoint') + '\n' +
                  'static void ' + function(NEXT.read_text(), 'hwdec_lease_rescale_frame'))
        cls.temp = tempfile.TemporaryDirectory()
        root = Path(cls.temp.name)
        path = root / 'rescale.c'
        path.write_text('''#include <math.h>\n#include <stdbool.h>\n#include <stddef.h>\n#include <stdlib.h>\n
#define MP_ERR(...) ((void)0)
#define MPMIN(a, b) ((a) < (b) ? (a) : (b))
struct pl_rect2df { float x0, y0, x1, y1; };
struct pl_overlay_part { struct pl_rect2df src, dst; };
#define PL_OVERLAY_COORDS_SRC_CROP 1
#define PL_OVERLAY_COORDS_DST_CROP 2
struct pl_overlay { const struct pl_overlay_part *parts; int num_parts; int coords; };
struct plane { int unused; };
struct pl_frame { void *user_data; int num_planes; struct plane planes[4];
    struct pl_rect2df crop; struct pl_overlay *overlays; int num_overlays; };
struct params { int w, h, rotate, vflip; };
struct mp_image { void *priv; struct params params; };
struct frame_priv { int lease_w, lease_h; void *rescale_ctx; };
struct priv { int unused; };
struct ta_node { void *ptr; struct ta_node *next; };
struct ta_ctx { struct ta_node *head; };
static void *talloc_new(void *parent) {
    (void)parent;
    return calloc(1, sizeof(struct ta_ctx));
}
static void *talloc_size(void *ctx, size_t size) {
    if (!ctx) return NULL;
    struct ta_ctx *c = ctx;
    struct ta_node *n = malloc(sizeof(*n));
    if (!n) return NULL;
    n->ptr = calloc(1, size);
    if (!n->ptr) { free(n); return NULL; }
    n->next = c->head; c->head = n;
    return n->ptr;
}
#define talloc_array(ctx, type, count) ((type *) talloc_size(ctx, sizeof(type) * (size_t)(count)))
static void talloc_free(void *ctx) {
    struct ta_ctx *c = ctx;
    if (!c) return;
    while (c->head) { struct ta_node *n = c->head; c->head = n->next;
                      free(n->ptr); free(n); }
    free(c);
}
''' + helper + '''
void run_rescale(int lease_w, int lease_h, int sw, int sh, int rotate, int vflip,
                 int coords, float x0, float y0, float x1, float y1,
                 int num_overlays, float *out_crop, int *out_num_overlays,
                 float *shared_dst_y1, float *copy_dst_x1, float *copy_src_x1,
                 int *out_has_ctx) {
    struct frame_priv fp = {.lease_w = lease_w, .lease_h = lease_h};
    struct mp_image mpi = {.params = {.w = sw, .h = sh, .rotate = rotate, .vflip = vflip},
                           .priv = &fp};
    struct priv p = {0};
    struct pl_frame frame = {.crop = {x0, y0, x1, y1}};
    // Crop-relative part spanning the full crop width; the Y extent doubles
    // as the shared-state marker (its scaled value always differs).
    struct pl_overlay_part parts[1] = {{.src = {0, 0, 7, 7},
                                        .dst = {0, y0, x1 - x0, y1}}};
    struct pl_overlay ol = {.parts = parts, .num_parts = 1, .coords = coords};
    if (num_overlays) { frame.overlays = &ol; frame.num_overlays = 1; }
    hwdec_lease_rescale_frame(&p, &mpi, &frame);
    out_crop[0] = frame.crop.x0; out_crop[1] = frame.crop.y0;
    out_crop[2] = frame.crop.x1; out_crop[3] = frame.crop.y1;
    *out_num_overlays = frame.num_overlays;
    *shared_dst_y1 = parts[0].dst.y1;
    *copy_dst_x1 = frame.overlays ? frame.overlays[0].parts[0].dst.x1 : 0.0f;
    *copy_src_x1 = frame.overlays ? frame.overlays[0].parts[0].src.x1 : 0.0f;
    *out_has_ctx = fp.rescale_ctx != NULL;
    talloc_free(fp.rescale_ctx);
}
''')
        library = root / 'rescale.dylib'
        subprocess.run([os.environ.get('CC', 'cc'), '-std=c11', '-Wall', '-Werror',
                        '-dynamiclib', str(path), '-o', str(library)], check=True)
        cls.lib = ctypes.CDLL(str(library))
        cls.lib.run_rescale.argtypes = [ctypes.c_int] * 7 + [ctypes.c_float] * 4 + \
            [ctypes.c_int, ctypes.POINTER(ctypes.c_float), ctypes.POINTER(ctypes.c_int),
             ctypes.POINTER(ctypes.c_float), ctypes.POINTER(ctypes.c_float),
             ctypes.POINTER(ctypes.c_float), ctypes.POINTER(ctypes.c_int)]

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    def rescale(self, **changes):
        args = dict(lease_w=0, lease_h=0, sw=3840, sh=1920, rotate=0, vflip=0,
                    coords=1, x0=0.0, y0=0.0, x1=3840.0, y1=1920.0,
                    num_overlays=0)
        args.update(changes)
        crop = (ctypes.c_float * 4)()
        num_overlays, has_ctx = ctypes.c_int(), ctypes.c_int()
        shared_y1, copy_x1, copy_src_x1 = (ctypes.c_float(), ctypes.c_float(),
                                           ctypes.c_float())
        self.lib.run_rescale(*args.values(), crop, ctypes.byref(num_overlays),
                             ctypes.byref(shared_y1), ctypes.byref(copy_x1),
                             ctypes.byref(copy_src_x1), ctypes.byref(has_ctx))
        return (tuple(crop), num_overlays.value, shared_y1.value,
                copy_x1.value, copy_src_x1.value, has_ctx.value)

    def test_no_lease_keeps_classic_source_space(self):
        crop, overlays, shared_y1, copy_x1, copy_src_x1, has_ctx = self.rescale()
        self.assertEqual(crop, (0.0, 0.0, 3840.0, 1920.0))
        self.assertEqual((overlays, copy_x1, copy_src_x1, has_ctx), (0, 0.0, 0.0, 0))
        self.assertEqual(shared_y1, 1920.0)
        partial = self.rescale(x0=100, x1=3740)
        self.assertEqual(partial[0], (100.0, 0.0, 3740.0, 1920.0))

    def test_full_frame_snapshots_onto_full_lease(self):
        crop, overlays, shared_y1, copy_x1, copy_src_x1, has_ctx = self.rescale(
            lease_w=2672, lease_h=1336, num_overlays=1)
        self.assertEqual(crop, (0.0, 0.0, 2672.0, 1336.0))
        # Full-span part snaps exactly onto the fixed crop extent; the atlas
        # src stays put; the shared state keeps the source-space marker.
        self.assertEqual(copy_x1, 2672.0)
        self.assertEqual(copy_src_x1, 7.0)
        self.assertEqual((overlays, shared_y1, has_ctx), (1, 1920.0, 1))

    def test_partial_rect_scales_with_rounding(self):
        crop, _, _, _, _, _ = self.rescale(lease_w=2672, lease_h=1336,
                                           x0=100, y0=50, x1=3740, y1=1870)
        self.assertEqual(crop, (70.0, 35.0, 2602.0, 1301.0))

    def test_collapse_guard_keeps_nonempty_crop(self):
        crop, _, _, _, _, _ = self.rescale(lease_w=2672, lease_h=1336,
                                           x0=100, x1=100.4)
        self.assertEqual((crop[0], crop[1]), (70.0, 0.0))
        self.assertEqual((crop[2], crop[3]), (71.0, 1336.0))
        crop, _, _, _, _, _ = self.rescale(lease_w=2672, lease_h=1336,
                                           y0=100, y1=100.4)
        self.assertEqual((crop[0], crop[1]), (0.0, 70.0))
        self.assertEqual((crop[2], crop[3]), (2672.0, 71.0))

    def test_orientation_never_scales(self):
        base = (0.0, 0.0, 3840.0, 1920.0)
        self.assertEqual(self.rescale(lease_w=2672, lease_h=1336, rotate=90)[0], base)
        self.assertEqual(self.rescale(lease_w=2672, lease_h=1336, vflip=1)[0], base)

    def test_empty_source_crop_order_preserved(self):
        crop, _, _, _, _, _ = self.rescale(lease_w=2672, lease_h=1336,
                                           x0=500, x1=100)
        self.assertEqual(crop, (348.0, 0.0, 70.0, 1336.0))

    def test_narrow_crop_part_keeps_proportion(self):
        # Source crop [100,101] at lease ratio 672/3840: the crop rounds to
        # [18,18] and is fixed to [18,19]; a full-span part must still cover
        # 100% of the fixed crop extent instead of shrinking to the raw ratio.
        crop, overlays, shared_y1, copy_x1, _, has_ctx = self.rescale(
            lease_w=672, lease_h=336, x0=100, x1=101, num_overlays=1)
        self.assertEqual((crop[0], crop[1]), (18.0, 0.0))
        self.assertEqual((crop[2], crop[3]), (19.0, 336.0))
        self.assertEqual((overlays, has_ctx), (1, 1))
        self.assertEqual(copy_x1, 1.0)
        self.assertEqual(shared_y1, 1920.0)

    def test_dst_crop_parts_copied_verbatim(self):
        crop, overlays, shared_y1, copy_x1, _, has_ctx = self.rescale(
            lease_w=2672, lease_h=1336, coords=2, num_overlays=1)
        self.assertEqual(crop, (0.0, 0.0, 2672.0, 1336.0))
        self.assertEqual((overlays, has_ctx), (1, 1))
        # Target-space part keeps its source-space value verbatim.
        self.assertEqual(copy_x1, 3840.0)
        self.assertEqual(shared_y1, 1920.0)

class LifecycleTests(unittest.TestCase):
    def test_actual_common_map_and_unmap_wrappers(self):
        source = HWDEC.read_text()
        wrappers = ('void ' + function(source, 'ra_hwdec_mapper_unmap') + '\n' +
                    'int ' + function(source, 'ra_hwdec_mapper_map') + '\n' +
                    'int ' + function(source, 'ra_hwdec_mapper_map_with_request'))
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'lifecycle.c'
            library = Path(tmp) / 'lifecycle.dylib'
            path.write_text('''#include <stdbool.h>\n#include <stddef.h>\n
struct mp_image { int unused; };
struct ra_hwdec_map_geometry { bool valid; int width; };
struct ra_hwdec_map_request { bool allow_full_frame_scale; int target_w, target_h; };
struct ra_hwdec_mapper;
struct driver { int (*map)(struct ra_hwdec_mapper *); void (*unmap)(struct ra_hwdec_mapper *); };
struct ra_hwdec_mapper { struct driver *driver; unsigned caps; struct mp_image *src;
    struct ra_hwdec_map_geometry map_geometry; struct ra_hwdec_map_request map_request; };
#define RA_HWDEC_CAP_MAP_GEOMETRY 1
static int calls, unmaps, saw_previous, saw_request, fail, fail_ref;
static void mp_image_unrefp(struct mp_image **p) { *p = NULL; }
static void mp_image_setrefp(struct mp_image **p, struct mp_image *img) {
    *p = fail_ref ? NULL : img;
}
int ra_hwdec_mapper_map_with_request(struct ra_hwdec_mapper *, struct mp_image *,
                                     const struct ra_hwdec_map_request *);
''' + wrappers + '''
static void driver_unmap(struct ra_hwdec_mapper *m) {
    unmaps++; saw_previous += m->map_geometry.valid;
}
static int driver_map(struct ra_hwdec_mapper *m) {
    calls++; saw_request = m->map_request.allow_full_frame_scale ? m->map_request.target_w : 0;
    m->map_geometry = (struct ra_hwdec_map_geometry){.valid=true, .width=123};
    return fail ? -1 : 0;
}
int run_lifecycle(void) {
    struct driver d = {.map=driver_map, .unmap=driver_unmap};
    struct ra_hwdec_mapper m = {.driver=&d};
    struct mp_image img = {0};
    struct ra_hwdec_map_request req = {.allow_full_frame_scale=true, .target_w=2672, .target_h=1336};
    if (ra_hwdec_mapper_map_with_request(&m, &img, &req) || saw_request || !m.map_geometry.valid ||
        m.map_request.allow_full_frame_scale || calls != 1 || unmaps != 1) return 1;
    m.caps = RA_HWDEC_CAP_MAP_GEOMETRY;
    if (ra_hwdec_mapper_map_with_request(&m, &img, &req) || saw_request != 2672 ||
        !m.map_geometry.valid || m.map_request.allow_full_frame_scale || saw_previous != 1) return 2;
    fail = 1;
    if (ra_hwdec_mapper_map_with_request(&m, &img, &req) != -1 || saw_request != 2672 ||
        m.map_geometry.valid || m.src || m.map_request.allow_full_frame_scale || calls != 3 ||
        unmaps != 4 || saw_previous != 3) return 3;
    fail = 0;
    if (ra_hwdec_mapper_map(&m, &img) || saw_request || !m.map_geometry.valid) return 4;
    ra_hwdec_mapper_unmap(&m);
    if (m.map_geometry.valid || m.src || m.map_request.allow_full_frame_scale) return 5;
    int before_calls = calls, before_unmaps = unmaps;
    fail_ref = 1;
    if (ra_hwdec_mapper_map_with_request(&m, &img, &req) != -1 ||
        calls != before_calls || unmaps != before_unmaps + 1 || m.src ||
        m.map_geometry.valid || m.map_request.allow_full_frame_scale) return 6;
    fail_ref = 0;
    if (ra_hwdec_mapper_map_with_request(&m, &img, &req) || calls != before_calls + 1 ||
        !m.map_geometry.valid || saw_request != 2672 || m.map_request.allow_full_frame_scale)
        return 7;
    ra_hwdec_mapper_unmap(&m);
    return 0;
}
''')
            subprocess.run([os.environ.get('CC', 'cc'), '-std=c11', '-Wall', '-Werror',
                            '-dynamiclib', str(path), '-o', str(library)], check=True)
            lib = ctypes.CDLL(str(library))
            lib.run_lifecycle.restype = ctypes.c_int
            self.assertEqual(lib.run_lifecycle(), 0)


if __name__ == '__main__':
    unittest.main()
