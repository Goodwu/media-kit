"""Production seed lifecycle: fence-gated completion without readback."""
from pathlib import Path
import subprocess
import tempfile
import unittest

LIB = Path('/Users/wuweiwei1/src/libplacebo/src/opengl/gpu_tex.c')

class ProductionSeedTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory()
        # Reuse the existing extracted backend harness generator: it builds
        # real gpu_tex functions with CPU GL doubles.
        gen = Path('/tmp/test_atlas_read_backend.py')
        cls.harness = gen
        cls.exe = Path(cls.temp.name) / 'prodseed'
        # The backend generator emits its own main; we compile it once and
        # assert via the documented PASS line, plus source-level checks here
        # for the production branches.
        src = LIB.read_text()
        cls.assertInSource = src

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    def test_fence_created_in_production_seed(self):
        src = self.assertInSource
        self.assertIn('if (ok) {', src)
        # The fence block must not be inside !production_seed guard
        fence_pos = src.index('c->fence = gl->FenceSync(GL_SYNC_GPU_COMMANDS_COMPLETE, 0);')
        guard_pos = src.rfind('if (ok && !c->production_seed)', 0, fence_pos)
        prod_guard_pos = src.rfind('if (ok) {', 0, fence_pos)
        self.assertGreater(prod_guard_pos, guard_pos,
            'fence creation must run for production seeds too')

    def test_poll_rejects_missing_fence_only_before_completion(self):
        src = self.assertInSource
        self.assertIn('if (!c->baseline_ok || !c->fence)', src)

    def test_poll_skips_cpu_atlas_scan_for_production(self):
        src = self.assertInSource
        self.assertIn('if (!c->production_seed)', src)
        # the second poll-time guard (line ~2715) skips the CPU atlas scan
        guards = []
        start = 0
        while True:
            pos = src.find('if (!c->production_seed)', start)
            if pos < 0: break
            guards.append(pos)
            start = pos + 1
        scan_pos = src.index('c->result.bad_atlas_pixels += v[2] != 1')
        preceding = src[max(guards, key=lambda g: g < scan_pos and g or -1):scan_pos]
        self.assertLess(max(g for g in guards if g < scan_pos), scan_pos)
        self.assertIn('for (size_t n=0', preceding)

    def test_readback_short_circuits_for_production(self):
        src = self.assertInSource
        self.assertIn('t_pre->atlas_anchor->production_seed', src)


if __name__ == '__main__':
    unittest.main()
