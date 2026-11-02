"""Production UV-table final-tap material gate tests.

Two layers (the repository's established pattern):
1. Source assertions pinning the real gate in libplacebo dispatch.c: the
   seed-material comparison exists, compares the fields that determine the
   recorded UV geometry (dims/sampler/format), rejects via goto error before
   generate_shaders, and the GL-only symbol reference stays inside the
   PL_HAVE_OPENGL guard (no-GL link regression).
2. A compiled behavioral check of the same comparison logic against matching
   and drifted tap textures.
"""
from pathlib import Path
import subprocess
import tempfile
import unittest

LIB = Path('/Users/wuweiwei1/src/libplacebo/src/dispatch.c')
SOURCE = LIB.read_text()


class GateSourceTests(unittest.TestCase):
    def test_material_comparison_exists_with_guard(self):
        start = SOURCE.index('if (gen_params.uv_table_storage && !gen_params.uv_table_ident) {')
        end = SOURCE.index('    generate_shaders(dp, &gen_params', start)
        block = SOURCE[start:end]
        self.assertIn('pl_opengl_uv_atlas_table_seed_material(dp->gpu)', block)
        self.assertIn('tap_tex->params.w != seed_mat->input_width', block)
        self.assertIn('tap_tex->params.h != seed_mat->input_height', block)
        self.assertIn('tap_tex->sampler_type != seed_mat->sampler_type', block)
        self.assertIn('tap_tex->params.format->type != seed_mat->format_type', block)
        self.assertIn('tap_tex->params.format->num_components != seed_mat->num_components', block)
        self.assertIn('event=table-input-mismatch', block)
        # 失配拒绝必须先于 generate_shaders（pass 缓存前）
        self.assertIn('goto error;', block)
        # GL-only 符号必须整体在 PL_HAVE_OPENGL 守卫内
        guard = block.index('#ifdef PL_HAVE_OPENGL')
        call = block.index('pl_opengl_uv_atlas_table_seed_material(dp->gpu)')
        endif = block.index('#endif', call)
        self.assertLess(guard, call)
        self.assertLess(call, endif)

    def test_tap_admission_uses_shared_helper(self):
        # 生产与 compare 必须同调一个校验助手（复审 P2：消除双标准）
        start = SOURCE.index('if (gen_params.uv_table_storage && !gen_params.uv_table_ident) {')
        end = SOURCE.index('    generate_shaders(dp, &gen_params', start)
        block = SOURCE[start:end]
        self.assertIn('mks_tap_site_supported(dp, sh, &params, &site)', block)
        self.assertNotIn('matching_tex++', block, '生产块不得再自带宽松版循环')
        self.assertIn('reason=tap-not-unique', block)
        # 共享助手本身承载 compare 全套条件
        hs = SOURCE.index('static pl_tex mks_tap_site_supported(')
        he = SOURCE.index('\n}', hs)
        helper = SOURCE[hs:he]
        for cond in ('sampled_tex == 1', 'matching_tex == 1', 'matching_uv == 1',
                     'PL_FMT_UNORM', 'PL_FMT_SNORM', 'vec2'):
            self.assertIn(cond, helper)


GATE_C = r'''
#include <stdio.h>
#include <string.h>
// Field-for-field replica of the dispatch comparison (dispatch.c
// tap-resolution block): same operators, same order, same reject event.
struct fmt { int type, num_components; };
struct tex { int w, h, sampler_type; struct fmt *format; };
struct material { int input_width, input_height, sampler_type;
                  int format_type, num_components; };
static int rejected;
static const char *reason;
static int check(struct tex *t, const struct material *m)
{
    if (!m ||
        t->w != m->input_width ||
        t->h != m->input_height ||
        t->sampler_type != m->sampler_type ||
        !t->format ||
        t->format->type != m->format_type ||
        t->format->num_components != m->num_components) {
        rejected++;
        reason = "table-input-mismatch";
        return 0;
    }
    return 1;
}
int main(int argc, char **argv)
{
    struct fmt f = { 1, 4 }, other = { 2, 4 };
    struct tex t = { 3840, 1920, 1, &f };
    struct material m = { 3840, 1920, 1, 1, 4 };
    if (argc > 1 && !strcmp(argv[1], "dims")) t.w = 2672;
    if (argc > 1 && !strcmp(argv[1], "sampler")) t.sampler_type = 99;
    if (argc > 1 && !strcmp(argv[1], "format")) t.format = &other;
    if (argc > 1 && !strcmp(argv[1], "comps")) m.num_components = 2;
    if (argc > 1 && !strcmp(argv[1], "nomat")) {
        struct tex t2 = t; const struct material *m2 = NULL;
        int ok2 = check(&t2, m2);
        printf("ok=%d rejected=%d\n", ok2, rejected);
        return 0;
    }
    int ok = check(&t, &m);
    printf("ok=%d rejected=%d\n", ok, rejected);
    return 0;
}
'''


class GateBehaviorTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory()
        c = Path(cls.temp.name) / 'gate.c'
        c.write_text(GATE_C)
        exe = Path(cls.temp.name) / 'gate'
        subprocess.run(['clang', '-std=c11', '-Wall', '-Werror', str(c), '-o', str(exe)],
                       check=True, capture_output=True)
        cls.exe = exe

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    def run_case(self, arg=''):
        return subprocess.run([str(self.exe)] + ([arg] if arg else []),
                              capture_output=True, text=True).stdout.strip()

    def test_matching_passes(self):
        self.assertEqual(self.run_case(), 'ok=1 rejected=0')

    def test_dimension_drift_rejects(self):
        self.assertEqual(self.run_case('dims'), 'ok=0 rejected=1')

    def test_sampler_drift_rejects(self):
        self.assertEqual(self.run_case('sampler'), 'ok=0 rejected=1')

    def test_format_type_drift_rejects(self):
        self.assertEqual(self.run_case('format'), 'ok=0 rejected=1')

    def test_component_count_drift_rejects(self):
        self.assertEqual(self.run_case('comps'), 'ok=0 rejected=1')

    def test_missing_material_rejects(self):
        self.assertEqual(self.run_case('nomat'), 'ok=0 rejected=1')


if __name__ == '__main__':
    unittest.main()
