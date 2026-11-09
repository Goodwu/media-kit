"""Host checks for the standalone PQ LUT probe's error and timeout boundaries.

These compile the actual macro/timer functions with doubles; no GPU is used.
"""
from pathlib import Path
import os
import re
import struct
import subprocess
import tempfile
import unittest


SOURCE = Path(__file__).resolve().parent / 'native/lg_pq_lut_probe.c'


def extract_function(source, name):
    match = re.search(r'(?m)^static\s+(?:int|void|bool|uint16_t)\s+' + re.escape(name) + r'\s*\(', source)
    if not match:
        raise ValueError('missing function: ' + name)
    opening = source.index('{', match.end())
    depth = 0
    for index in range(opening, len(source)):
        depth += (source[index] == '{') - (source[index] == '}')
        if not depth:
            return source[match.start():index + 1]
    raise ValueError('unclosed function: ' + name)


def run_c(source):
    with tempfile.TemporaryDirectory() as tmp:
        path, exe = Path(tmp) / 'test.c', Path(tmp) / 'test'
        path.write_text(source)
        subprocess.run(['clang', '-std=c11', '-Wall', '-Wextra', '-Werror',
                        str(path), '-o', str(exe)], check=True, timeout=30)
        subprocess.run([str(exe)], check=True, timeout=5)


class PqLutFailClosedTests(unittest.TestCase):
    def test_extension_lookup_handles_allocation_failure_and_exact_tokens(self):
        source = SOURCE.read_text()
        lookup = extract_function(source, 'has_ext')
        run_c('''#include <assert.h>\n#include <stdio.h>\n#include <stdlib.h>\n#include <string.h>\n
#define GL_EXTENSIONS 0
static const char *extensions;
static int fail_alloc, allocations, frees;
static const unsigned char *glGetString(int name) {
    assert(name == GL_EXTENSIONS);
    return (const unsigned char *)extensions;
}
static void *test_malloc(size_t size) {
    allocations++;
    return fail_alloc ? NULL : malloc(size);
}
static void test_free(void *ptr) { if (ptr) frees++; free(ptr); }
#define malloc test_malloc
#define free test_free
''' + lookup + '''
int main(void) {
    extensions = NULL;
    assert(!has_ext("GL_EXT_color_buffer_float") && allocations == 0);
    extensions = "GL_EXT_disjoint_timer_query GL_EXT_color_buffer_float GL_OES_texture_half_float_linear";
    assert(has_ext("GL_EXT_disjoint_timer_query"));
    assert(has_ext("GL_EXT_color_buffer_float"));
    assert(has_ext("GL_OES_texture_half_float_linear"));
    assert(!has_ext("GL_EXT_color_buffer"));
    assert(!has_ext("EXT_color_buffer_float"));
    assert(!has_ext("GL_EXT_color_buffer_float_extra"));
    assert(allocations == 6 && frees == 6);
    fail_alloc = 1;
    assert(!has_ext("GL_EXT_color_buffer_float"));
    assert(allocations == 7 && frees == 6);
    return 0;
}
''')

    def test_full_main_capability_allocation_failures_stop_before_queries(self):
        source = SOURCE.read_text()
        includes = '#include <EGL/egl.h>\n#include <GLES3/gl31.h>'
        self.assertEqual(source.count(includes), 1)
        source = source.replace(includes, '#include "lg_pq_lut_host_gl.h"\n'
                               '#define malloc lg_pq_host_malloc\n#define free lg_pq_host_free')
        native = SOURCE.parent
        stubs = (native / 'lg_pq_lut_host_gl.c').read_text()
        version = 'OpenGL ES 3.2 host double'
        extensions = 'GL_EXT_disjoint_timer_query GL_EXT_color_buffer_float'
        self.assertEqual(stubs.count(version), 1)
        self.assertEqual(stubs.count(extensions), 1)
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            cfile, double, exe, trace = (tmp / 'probe.c', tmp / 'gl.c',
                                         tmp / 'probe', tmp / 'trace')
            cfile.write_text(source)
            for minor in (2, 0):
                double.write_text(stubs if minor == 2 else
                                  stubs.replace(version, 'OpenGL ES 3.0 host double')
                                  .replace(extensions, extensions + ' GL_OES_texture_half_float_linear'))
                subprocess.run(['clang', '-std=c11', '-D_DARWIN_C_SOURCE', '-Wall', '-Wextra',
                                '-Werror', '-I', str(native), str(cfile), str(double),
                                '-lm', '-o', str(exe)], check=True, timeout=30)
                for allocation in range(1, 3 if minor == 2 else 4):
                    with self.subTest(gles=f'3.{minor}', allocation=allocation):
                        trace.unlink(missing_ok=True)
                        env = {key: value for key, value in os.environ.items()
                               if not key.startswith('LG_PQ_HOST_')}
                        env.update(LG_PQ_HOST_TRACE=str(trace),
                                   LG_PQ_HOST_FAIL_ALLOC=str(allocation))
                        result = subprocess.run([str(exe)], env=env, capture_output=True,
                                                text=True, timeout=15)
                        self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
                        self.assertIn('PQLUT verdict=fail reason=caps', result.stdout)
                        state = dict(item.split('=') for item in trace.read_text().split())
                        self.assertEqual(state['failure'], '0')
                        self.assertEqual((state['clears'], state['draws'], state['reads']),
                                         ('0', '0', '0'))
                        attempts = int(state['alloc_attempts'])
                        self.assertGreaterEqual(attempts, allocation)
                        self.assertEqual(state['alloc_failed'], str(allocation))
                        self.assertEqual(int(state['allocated']), attempts - 1)
                        self.assertEqual(state['freed'], state['allocated'])
                        self.assertEqual((state['query_generated'], state['query_begun'],
                                          state['query_deleted'], state['timing_draws'],
                                          state['accuracy_reads']), ('0', '0', '0', '0', '0'))

    def test_full_main_timing_sample_allocation_failures_stop_before_timing(self):
        # Exercise the real device main with controlled host allocations and
        # GL/query doubles. This is not a real EGL or GPU cleanup test.
        source = SOURCE.read_text()
        includes = '#include <EGL/egl.h>\n#include <GLES3/gl31.h>'
        self.assertEqual(source.count(includes), 1)
        source = source.replace(includes, '#include "lg_pq_lut_host_gl.h"\n'
                               '#define malloc lg_pq_host_malloc\n#define free lg_pq_host_free')
        allocation_site = 'samples[v] = malloc(sizeof(uint64_t) * TIMED_FRAMES * SETS);'
        self.assertEqual(source.count(allocation_site), 1)
        source = source.replace(allocation_site,
            'samples[v] = lg_pq_host_sample_malloc(v, sizeof(uint64_t) * TIMED_FRAMES * SETS);')
        for before, after in (('#define PROBE_W 2672', '#define PROBE_W 16'),
                              ('#define PROBE_H 1336', '#define PROBE_H 16')):
            self.assertEqual(source.count(before), 1)
            source = source.replace(before, after)
        native = SOURCE.parent
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            cfile, exe, trace = tmp / 'probe.c', tmp / 'probe', tmp / 'trace'
            cfile.write_text(source)
            subprocess.run(['clang', '-std=c11', '-D_DARWIN_C_SOURCE', '-Wall', '-Wextra',
                            '-Werror', '-I', str(native), str(cfile),
                            str(native / 'lg_pq_lut_host_gl.c'), '-lm', '-o', str(exe)],
                           check=True, timeout=30)
            for index in range(6):
                with self.subTest(sample=index):
                    trace.unlink(missing_ok=True)
                    env = {key: value for key, value in os.environ.items()
                           if not key.startswith('LG_PQ_HOST_')}
                    env.update(LG_PQ_HOST_TRACE=str(trace), LG_PQ_HOST_ACCURACY='1',
                               LG_PQ_HOST_FAIL_SAMPLE=str(index))
                    result = subprocess.run([str(exe)], env=env, capture_output=True,
                                            text=True, timeout=15)
                    self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
                    state = dict(item.split('=') for item in trace.read_text().split())
                    self.assertEqual(state['failure'], '0', result.stdout + result.stderr)
                    self.assertEqual(state['sample_failed'], str(index))
                    self.assertGreaterEqual(int(state['sample_attempts']), 1)
                    self.assertEqual(state['allocated'], state['alloc_attempts'])
                    self.assertEqual(state['freed'], state['allocated'])
                    self.assertGreater(int(state['query_generated']), 0)
                    self.assertGreaterEqual(int(state['detached']), 1)
                    self.assertEqual([state[key] for key in
                                      ('query_live', 'cleanup_errors', 'current', 'query_begun',
                                       'timing_draws', 'accuracy_reads', 'terminated')],
                                     ['0', '0', '0', '0', '0', '0', '1'])
                    self.assertIn('PQLUT verdict=fail reason=oom', result.stdout)
                    self.assertNotIn('PQLUT phase=timing', result.stdout)
                    self.assertNotIn('PQLUT phase=accuracy', result.stdout)
                    self.assertNotIn('PQLUT validation=unverified', result.stdout)

    def test_canary_verifies_clear_draw_and_readback(self):
        source = SOURCE.read_text()
        check = extract_function(source, 'canary_check')
        start = source.index('    printf("PQLUT phase=canary\\n");')
        end = source.index('    struct { const char *name; int mode; int lut; } variants', start)
        run_c(CANARY_STUBS + check + '\nstatic int execute(void) {\n' +
              source[start:end] + '\nreturn 0;\n}\n' + CANARY_CASES)

    def test_full_device_main_reaches_canary_before_timing(self):
        # Compile the complete device main (not an extracted block) with host
        # doubles. Deliberately stop at the first timing draw after checking
        # program restoration; this cannot validate GLSL, real GL, or timing.
        source = SOURCE.read_text()
        includes = '#include <EGL/egl.h>\n#include <GLES3/gl31.h>'
        self.assertEqual(source.count(includes), 1)
        source = source.replace(includes, '#include "lg_pq_lut_host_gl.h"')
        native = SOURCE.parent
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            cfile, exe, trace = tmp / 'probe.c', tmp / 'probe', tmp / 'trace'
            cfile.write_text(source)
            subprocess.run(['clang', '-std=c11', '-D_DARWIN_C_SOURCE', '-Wall', '-Wextra',
                            '-Werror', '-I', str(native), str(cfile),
                            str(native / 'lg_pq_lut_host_gl.c'), '-lm', '-o', str(exe)],
                           check=True, timeout=30)
            for phase in (-1, 0, 1, 2):
                with self.subTest(phase=phase):
                    trace.unlink(missing_ok=True)
                    env = {key: value for key, value in os.environ.items()
                           if not key.startswith('LG_PQ_HOST_')}
                    env['LG_PQ_HOST_TRACE'] = str(trace)
                    if phase >= 0:
                        env['LG_PQ_HOST_BAD_PHASE'] = str(phase)
                    else:
                        env.pop('LG_PQ_HOST_BAD_PHASE', None)
                    result = subprocess.run([str(exe)], env=env, capture_output=True,
                                            text=True, timeout=15)
                    self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
                    state = dict(item.split('=') for item in trace.read_text().split())
                    self.assertEqual(state['failure'], '0', result.stdout + result.stderr)
                    if phase < 0:
                        self.assertEqual([state[k] for k in ('clears', 'draws', 'reads',
                                                             'timing_draws', 'deleted')],
                                         ['1', '2', '3', '1', '1'])
                        self.assertIn('PQLUT canary=pass', result.stdout)
                    else:
                        self.assertEqual(int(state['reads']), phase + 1)
                        self.assertEqual(int(state['draws']), phase)
                        self.assertEqual(state['timing_draws'], '0')
                        self.assertIn(f'PQLUT verdict=fail reason=canary phase={phase}',
                                      result.stdout)
                        self.assertNotIn('PQLUT canary=pass', result.stdout)

    def test_half_numeric_ulp_distance_all_finite_encodings(self):
        source = SOURCE.read_text()
        distance = extract_function(source, 'half_ulp_distance')
        run_c('''#include <assert.h>\n#include <math.h>\n#include <stdint.h>\n#include <stdlib.h>\n
''' + distance + '''
int main(void) {
    assert(half_ulp_distance(0x0000,0x8000)==0);
    assert(half_ulp_distance(0x0001,0x8001)==2);
    assert(half_ulp_distance(0xfbff,0x0001)==31744);
    assert(half_ulp_distance(0xfbff,0x7bff)==63486);
    assert(half_ulp_distance(0x3c00,0x3c01)==1);
    assert(half_ulp_distance(0xbc00,0xbc01)==1);
    uint16_t prev=0xfbff;
    for (int code=0xfbfe;code>=0x8000;code--) {
        assert(half_ulp_distance(prev,(uint16_t)code)==1);
        prev=(uint16_t)code;
    }
    assert(half_ulp_distance(prev,0x0000)==0);
    prev=0x0000;
    for (unsigned code=1;code<=0x7bff;code++) {
        assert(half_ulp_distance(prev,(uint16_t)code)==1);
        assert(half_ulp_distance((uint16_t)code,0)==(int)code);
        assert(half_ulp_distance((uint16_t)(code|0x8000),0)==(int)code);
        assert(half_ulp_distance((uint16_t)code,(uint16_t)(code|0x8000))==2*(int)code);
        assert(half_ulp_distance(0,(uint16_t)code)==half_ulp_distance((uint16_t)code,0));
        prev=(uint16_t)code;
    }
    return 0;
}
''')

    def test_full_main_reports_cross_sign_ulp_distances(self):
        source = SOURCE.read_text()
        includes = '#include <EGL/egl.h>\n#include <GLES3/gl31.h>'
        self.assertEqual(source.count(includes), 1)
        source = source.replace(includes, '#include "lg_pq_lut_host_gl.h"')
        source = source.replace('#define PROBE_W 2672', '#define PROBE_W 16')
        source = source.replace('#define PROBE_H 1336', '#define PROBE_H 16')
        native = SOURCE.parent
        stubs = (native / 'lg_pq_lut_host_gl.c').read_text()
        target = '            pixels[i]=(i%4==3) ? 1.0f : 0.5f;'
        self.assertEqual(stubs.count(target), 1)
        injected = '''            pixels[i]=(i%4==3) ? 1.0f : 0.5f;
            if (i==0) { pixels[i]=accuracy_reads ? 0.0f : -0.0f; bad_attempts++; }
            if (i==1) { pixels[i]=accuracy_reads ? 0x1p-24f : -0x1p-24f; bad_attempts++; }
            if (i==2) { pixels[i]=accuracy_reads ? 0x1p-24f : -65504.0f; bad_attempts++; }
            if (i>=4 && i%4!=3) { pixels[i]=0.0f; bad_attempts++; }'''
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            cfile, double, exe, trace = (tmp / 'probe.c', tmp / 'gl.c',
                                         tmp / 'probe', tmp / 'trace')
            cfile.write_text(source)
            double.write_text(stubs.replace(target, injected))
            subprocess.run(['clang', '-std=c11', '-D_DARWIN_C_SOURCE', '-Wall', '-Wextra',
                            '-Werror', '-I', str(native), str(cfile), str(double),
                            '-lm', '-o', str(exe)], check=True, timeout=30)
            env = {key: value for key, value in os.environ.items()
                   if not key.startswith('LG_PQ_HOST_')}
            env.update(LG_PQ_HOST_TRACE=str(trace), LG_PQ_HOST_ACCURACY='1')
            result = subprocess.run([str(exe)], env=env, capture_output=True,
                                    text=True, timeout=15)
            self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
            state = dict(item.split('=') for item in trace.read_text().split())
            self.assertEqual((state['failure'], state['accuracy_reads'], state['bad_attempts']),
                             ('0', '5', '3840'))
            self.assertIn('PQLUT cpu_reference comps=768 exact_mismatch=768 within1ulp=0',
                          result.stdout)
            accuracy = re.findall(r'^PQLUT accuracy variant=(\S+) comps=(\d+) differing=(\d+) '
                                  r'max_abs=([0-9.]+) max_ulp=(\d+)$', result.stdout, re.MULTILINE)
            self.assertEqual(len(accuracy), 4, result.stdout)
            for name, comps, differing, max_abs, max_ulp in accuracy:
                self.assertEqual((comps, differing, max_ulp), ('768', '3', '31744'), name)
                self.assertGreater(float(max_abs), 65503.0)
            self.assertIn('PQLUT validation=unverified', result.stdout)
            self.assertIn('PQLUT verdict=fail', result.stdout)

    def test_cpu_reference_counts_numeric_zero_and_one_ulp(self):
        # Vary only a temporary copy of the reference input and fake readback;
        # keep checked_half, the CPU loop, and both statistics unmodified.
        source = SOURCE.read_text()
        includes = '#include <EGL/egl.h>\n#include <GLES3/gl31.h>'
        self.assertEqual(source.count(includes), 1)
        source = source.replace(includes, '#include "lg_pq_lut_host_gl.h"')
        source = source.replace('#define PROBE_W 2672', '#define PROBE_W 16')
        source = source.replace('#define PROBE_H 1336', '#define PROBE_H 16')
        boundary = 'checked_half(want[c], &wh)'
        self.assertEqual(source.count(boundary), 1)
        source = source.replace(boundary,
            'checked_half(((void)want[c], p == atoi(getenv("LG_PQ_HOST_TEST_PIXEL")) && '
            'c == atoi(getenv("LG_PQ_HOST_TEST_COMPONENT"))) ? '
            'strtod(getenv("LG_PQ_HOST_TEST_REFERENCE"), NULL) : 0.0, &wh)')
        native = SOURCE.parent
        stubs = (native / 'lg_pq_lut_host_gl.c').read_text()
        target = '            pixels[i]=(i%4==3) ? 1.0f : 0.5f;'
        self.assertEqual(stubs.count(target), 1)
        injected = '''            pixels[i]=(i%4==3) ? 1.0f : (accuracy_reads ? 2.0f : 0.0f);
            if (i==(size_t)atoi(getenv("LG_PQ_HOST_TEST_PIXEL"))*4 +
                  (size_t)atoi(getenv("LG_PQ_HOST_TEST_COMPONENT")))
                pixels[i]=strtof(getenv(accuracy_reads ? "LG_PQ_HOST_TEST_REFERENCE" :
                                      "LG_PQ_HOST_TEST_READBACK"), NULL);
            if (i%4!=3) bad_attempts++;'''
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            cfile, double, exe, trace = (tmp / 'probe.c', tmp / 'gl.c',
                                         tmp / 'probe', tmp / 'trace')
            cfile.write_text(source)
            double.write_text(stubs.replace(target, injected))
            subprocess.run(['clang', '-std=c11', '-D_DARWIN_C_SOURCE', '-Wall', '-Wextra',
                            '-Werror', '-I', str(native), str(cfile), str(double),
                            '-lm', '-o', str(exe)], check=True, timeout=30)
            # One non-exact analytic component per process prevents different
            # distance classes from cancelling; LUT reads have distinct values.
            cases = (
                ('exact', '0x1p0', '0x1p0', 0, 0),
                ('positive-read-negative-zero', '-0x0p0', '0x0p0', 1, 1),
                ('negative-read-positive-zero', '0x0p0', '-0x0p0', 1, 1),
                ('negative-minsub-to-zero', '0x0p0', '-0x1p-24', 1, 1),
                ('positive-minsub-to-negative-zero', '-0x0p0', '0x1p-24', 1, 1),
                ('cross-zero-two-steps', '0x1p-24', '-0x1p-24', 1, 0),
                ('positive-adjacent', '0x1p0', '0x1.004p0', 1, 1),
                ('negative-adjacent', '-0x1p0', '-0x1.004p0', 1, 1),
                ('positive-two-steps', '0x1p0', '0x1.008p0', 1, 0),
                ('negative-two-steps', '-0x1p0', '-0x1.008p0', 1, 0),
            )
            def check_case(name, pixel, component, reference, readback, mismatch, within1):
                with self.subTest(name=name, pixel=pixel, component=component):
                    trace.unlink(missing_ok=True)
                    env = {key: value for key, value in os.environ.items()
                           if not key.startswith('LG_PQ_HOST_')}
                    env.update(LG_PQ_HOST_TRACE=str(trace), LG_PQ_HOST_ACCURACY='1',
                               LG_PQ_HOST_TEST_PIXEL=str(pixel),
                               LG_PQ_HOST_TEST_COMPONENT=str(component),
                               LG_PQ_HOST_TEST_REFERENCE=reference,
                               LG_PQ_HOST_TEST_READBACK=readback)
                    result = subprocess.run([str(exe)], env=env, capture_output=True,
                                            text=True, timeout=15)
                    self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
                    state = dict(item.split('=') for item in trace.read_text().split())
                    self.assertEqual((state['failure'], state['accuracy_reads'],
                                      state['bad_attempts']), ('0', '5', '3840'))
                    reports = re.findall(
                        r'^PQLUT cpu_reference comps=(\d+) exact_mismatch=(\d+) '
                        r'within1ulp=(\d+) max_abs=([0-9.]+) note=',
                        result.stdout, re.MULTILINE)
                    self.assertEqual(len(reports), 1, result.stdout)
                    comps, diffs, near, max_abs = reports[0]
                    self.assertEqual((comps, diffs, near),
                                     ('768', str(mismatch), str(within1)))
                    expected_abs = abs(float.fromhex(readback) - float.fromhex(reference))
                    self.assertAlmostEqual(float(max_abs), expected_abs, delta=5.1e-10)
                    self.assertIn('PQLUT validation=unverified', result.stdout)
                    self.assertIn('PQLUT verdict=fail', result.stdout)

            for name, reference, readback, mismatch, within1 in cases:
                check_case(name, 0, 0, reference, readback, mismatch, within1)
            # Independently move a positive within-one count over every CPU
            # reference component, so a skipped pixel or channel is visible.
            for pixel in range(256):
                for component in range(3):
                    check_case('position', pixel, component,
                               '0x1p0', '0x1.004p0', 1, 1)

    def test_cpu_reference_anchors_use_analytic_readback(self):
        # Keep the actual source/PQ/CSC reference untouched. Only the fake GL
        # reads vary; the dyadic anchor codes are independent CPU expectations.
        source = SOURCE.read_text()
        includes = '#include <EGL/egl.h>\n#include <GLES3/gl31.h>'
        self.assertEqual(source.count(includes), 1)
        source = source.replace(includes, '#include "lg_pq_lut_host_gl.h"')
        source = source.replace('#define PROBE_W 2672', '#define PROBE_W 16')
        source = source.replace('#define PROBE_H 1336', '#define PROBE_H 16')
        native = SOURCE.parent
        stubs = (native / 'lg_pq_lut_host_gl.c').read_text()
        target = '            pixels[i]=(i%4==3) ? 1.0f : 0.5f;'
        self.assertEqual(stubs.count(target), 1)
        injected = '''            pixels[i]=(i%4==3) ? 1.0f : (accuracy_reads ? -2.0f : 0.0f);
            if (!accuracy_reads && i%4!=3 && i/4<4) {
                static const float y[4] = { 0x1.8p-21f, 0x1.294p-1f,
                                             0x1.81p-1f, 0x1p0f };
                pixels[i]=(i%4==0) ? y[i/4] : 0x1p-1f;
            }
            if (!accuracy_reads && i==17)
                pixels[i]=strtof(getenv("LG_PQ_HOST_TEST_SENTINEL"), NULL);
            if (!accuracy_reads && i==(size_t)atoi(getenv("LG_PQ_HOST_TEST_COMPONENT")))
                pixels[i]=strtof(getenv("LG_PQ_HOST_TEST_READBACK"), NULL);
            if (i%4!=3) bad_attempts++;'''
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            cfile, double, exe, trace = (tmp / 'probe.c', tmp / 'gl.c',
                                         tmp / 'probe', tmp / 'trace')
            cfile.write_text(source)
            double.write_text(stubs.replace(target, injected))
            subprocess.run(['clang', '-std=c11', '-D_DARWIN_C_SOURCE', '-Wall', '-Wextra',
                            '-Werror', '-I', str(native), str(cfile), str(double),
                            '-lm', '-o', str(exe)], check=True, timeout=30)
            anchors = (0x000c, 0x38a5, 0x3a04, 0x3c00)
            for pixel, y in enumerate(anchors):
                for component in range(3):
                    center = y if component == 0 else 0x3800
                    for step in (-2, -1, 0, 1, 2):
                        with self.subTest(pixel=pixel, component=component, step=step):
                            trace.unlink(missing_ok=True)
                            value = struct.unpack('>e', struct.pack('>H', center + step))[0]
                            env = {key: val for key, val in os.environ.items()
                                   if not key.startswith('LG_PQ_HOST_')}
                            env.update(LG_PQ_HOST_TRACE=str(trace), LG_PQ_HOST_ACCURACY='1',
                                       LG_PQ_HOST_TEST_COMPONENT=str(pixel * 4 + component),
                                       LG_PQ_HOST_TEST_READBACK=value.hex(),
                                       LG_PQ_HOST_TEST_SENTINEL='-0x1p0')
                            result = subprocess.run([str(exe)], env=env, capture_output=True,
                                                    text=True, timeout=15)
                            self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
                            state = dict(item.split('=') for item in trace.read_text().split())
                            self.assertEqual((state['failure'], state['accuracy_reads'],
                                              state['bad_attempts']), ('0', '5', '3840'))
                            mismatch = 756 + (step != 0)
                            within1 = int(abs(step) == 1)
                            self.assertIn(f'PQLUT cpu_reference comps=768 exact_mismatch={mismatch} '
                                          f'within1ulp={within1} max_abs=1.500000000 ',
                                          result.stdout)
                            self.assertIn('PQLUT validation=unverified', result.stdout)
                            self.assertIn('PQLUT verdict=fail', result.stdout)

    def test_half_conversion_rejects_bad_values_without_changing_finite_rounding(self):
        source = SOURCE.read_text()
        convert = extract_function(source, 'f32_to_f16')
        checked = extract_function(source, 'checked_half')
        self.assertEqual(checked.count('f32_to_f16(value)'), 1)
        checked = checked.replace('f32_to_f16(value)', 'checked_converter(value)')
        run_c('''#include <assert.h>\n#include <float.h>\n#include <math.h>\n#include <stdint.h>\n''' +
              convert + '''
static int converter_calls;
static uint16_t checked_converter(double value) {
    assert(isfinite(value) && fabs(value)<=FLT_MAX);
    converter_calls++;
    return f32_to_f16(value);
}
''' + checked + '''
int main(void) {
    union { uint32_t u; float f; } bits;
    uint16_t out;
    bits.u=0x7fc12345u; assert(f32_to_f16(bits.f)==0x7e00u);
    bits.u=0xffc12345u; assert(f32_to_f16(bits.f)==0xfe00u);
    assert(f32_to_f16(INFINITY)==0x7c00u && f32_to_f16(-INFINITY)==0xfc00u);
    const double bad[] = { NAN, INFINITY, -INFINITY, DBL_MAX, -DBL_MAX, 65520.0, -65520.0 };
    for (unsigned i=0;i<sizeof(bad)/sizeof(bad[0]);i++) {
        int before=converter_calls;
        out=0x1234u; assert(!checked_half(bad[i], &out) && out==0x1234u);
        if (i<5) assert(converter_calls==before); /* reject before unsafe cast */
    }
    struct { double value; uint16_t want; } values[] = {
        { 0.0, 0x0000 }, { -0.0, 0x8000 }, { 1.0, 0x3c00 },
        { 65504.0, 0x7bff }, { 65505.0, 0x7bff }, { -65505.0, 0xfbff },
        { 0x1.00200004p0, 0x3c00 },
    };
    for (unsigned i=0;i<sizeof(values)/sizeof(values[0]);i++) {
        out=0x1234u; assert(checked_half(values[i].value, &out) && out==values[i].want);
    }
    bits.u=0x33000001u; assert(checked_half(bits.f, &out) && out==0x0000u);
    bits.u=0x33c00000u; assert(checked_half(bits.f, &out) && out==0x0001u);
    bits.u=0x387fe000u; assert(checked_half(bits.f, &out) && out==0x03ffu);
    return 0;
}
''')

    def test_full_main_rejects_bad_accuracy_readbacks(self):
        # Small dimensions and fake query results reach the actual main's
        # accuracy/reference paths; this says nothing about GPU execution.
        source = SOURCE.read_text()
        includes = '#include <EGL/egl.h>\n#include <GLES3/gl31.h>'
        self.assertEqual(source.count(includes), 1)
        source = source.replace(includes, '#include "lg_pq_lut_host_gl.h"\n'
                               '#define malloc lg_pq_host_malloc\n#define free lg_pq_host_free')
        source = source.replace('#define PROBE_W 2672', '#define PROBE_W 16')
        source = source.replace('#define PROBE_H 1336', '#define PROBE_H 16')
        for name in ('chosen', 'pq', 'want'):
            target = {'chosen': 'checked_half(chosen, &chosen_half)',
                      'pq': 'checked_half(pq_encode_double(v16), &pq_half)',
                      'want': 'checked_half(want[c], &wh)'}[name]
            self.assertEqual(source.count(target), 1)
        native = SOURCE.parent
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            cfile, exe, trace = tmp / 'probe.c', tmp / 'probe', tmp / 'trace'
            cfile.write_text(source)
            subprocess.run(['clang', '-std=c11', '-D_DARWIN_C_SOURCE', '-Wall', '-Wextra',
                            '-Werror', '-I', str(native), str(cfile),
                            str(native / 'lg_pq_lut_host_gl.c'), '-lm', '-o', str(exe)],
                           check=True, timeout=30)

            def execute(bad_read=None, component=0, kind='nan', fail_alloc=None):
                trace.unlink(missing_ok=True)
                env = {key: value for key, value in os.environ.items()
                       if not key.startswith('LG_PQ_HOST_')}
                env.update(LG_PQ_HOST_TRACE=str(trace), LG_PQ_HOST_ACCURACY='1')
                if bad_read is not None:
                    env.update(LG_PQ_HOST_BAD_READ=str(bad_read),
                               LG_PQ_HOST_BAD_COMPONENT=str(component), LG_PQ_HOST_BAD_KIND=kind)
                if fail_alloc is not None:
                    env['LG_PQ_HOST_FAIL_ALLOC'] = str(fail_alloc)
                result = subprocess.run([str(exe)], env=env, capture_output=True, text=True, timeout=15)
                state = dict(item.split('=') for item in trace.read_text().split())
                self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
                self.assertEqual(state['failure'], '0', result.stdout + result.stderr)
                self.assertEqual(state['alloc_attempts'], '18')
                self.assertEqual(state['allocated'], '17' if fail_alloc is not None else '18')
                self.assertEqual(state['alloc_failed'], str(fail_alloc or 0))
                self.assertEqual(state['freed'], state['allocated'])
                self.assertEqual((state['query_deleted'], state['detached'], state['terminated']),
                                 ('16', '1', '1'))
                return result, state

            result, state = execute()
            self.assertEqual([state[k] for k in ('timing_draws', 'accuracy_draws', 'accuracy_reads',
                                                 'query_deleted', 'terminated', 'bad_attempts')],
                             ['2700', '5', '5', '16', '1', '0'])
            self.assertIn('PQLUT phase=cpu_reference', result.stdout)
            self.assertIn('PQLUT validation=unverified', result.stdout)
            self.assertIn('PQLUT verdict=fail', result.stdout)
            for allocation in (15, 16, 17, 18):
                with self.subTest(fail_allocation=allocation):
                    result, state = execute(fail_alloc=allocation)
                    self.assertEqual(state['accuracy_reads'], '0')
                    self.assertIn('PQLUT verdict=fail reason=oom', result.stdout)
                    self.assertNotIn('PQLUT phase=cpu_reference', result.stdout)
            for read in range(5):
                for index in range(4):
                    for kind in ('nan', 'inf', 'large', 'skip'):
                        with self.subTest(read=read, component=index, kind=kind):
                            result, state = execute(read, index, kind)
                            self.assertEqual(int(state['accuracy_reads']), read + 1)
                            self.assertEqual(state['bad_attempts'], '1')
                            self.assertIn('PQLUT verdict=fail reason=accuracy_value', result.stdout)
                            self.assertIn(f'read={read}', result.stdout)
                            self.assertIn('pixel=0', result.stdout)
                            self.assertIn(f'component={index}', result.stdout)
                            self.assertNotIn('PQLUT phase=cpu_reference', result.stdout)
                            self.assertEqual((state['query_deleted'], state['terminated']), ('16', '1'))
            for index in (4, 15 * 4 + 2, 16 * 4 + 1, 255 * 4 + 3):
                for read in (0, 1, 4):
                    for kind in ('nan', 'skip'):
                        with self.subTest(read=read, index=index, kind=kind):
                            result, state = execute(read, index, kind)
                            self.assertEqual((state['accuracy_reads'], state['bad_attempts']),
                                             (str(read + 1), '1'))
                            self.assertIn('PQLUT verdict=fail reason=accuracy_value', result.stdout)
                            self.assertIn(f'pixel={index // 4} component={index % 4}', result.stdout)
                            self.assertNotIn('PQLUT phase=cpu_reference', result.stdout)
                            self.assertEqual((state['query_deleted'], state['terminated']), ('16', '1'))

            # Inject nonfinite values at each actual CPU-reference conversion
            # boundary; only the temporary compiled source is altered.
            for stage, target in (
                ('source', 'checked_half(chosen, &chosen_half)'),
                ('pq', 'checked_half(pq_encode_double(v16), &pq_half)'),
                ('tail', 'checked_half(want[c], &wh)'),
            ):
                with self.subTest(stage=stage):
                    expr = {'source': 'checked_half(((void)chosen, NAN), &chosen_half)',
                            'pq': 'checked_half(((void)v16, NAN), &pq_half)',
                            'tail': 'checked_half(((void)want[c], NAN), &wh)'}[stage]
                    cfile.write_text(source.replace(target, expr))
                    subprocess.run(['clang', '-std=c11', '-D_DARWIN_C_SOURCE', '-Wall', '-Wextra',
                                    '-Werror', '-I', str(native), str(cfile),
                                    str(native / 'lg_pq_lut_host_gl.c'), '-lm', '-o', str(exe)],
                                   check=True, timeout=30)
                    result, state = execute()
                    self.assertEqual(state['accuracy_reads'], '5')
                    self.assertIn(f'PQLUT verdict=fail reason=cpu_reference_value stage={stage}',
                                  result.stdout)
                    self.assertNotIn('PQLUT cpu_reference comps=', result.stdout)
                    self.assertEqual((state['query_deleted'], state['terminated']), ('16', '1'))

    def test_unvalidated_probe_never_reports_pass(self):
        source = SOURCE.read_text()
        self.assertIn('PQLUT validation=unverified reason=missing_canary_and_anchor_gates', source)
        match = re.search(r'(?s)int ok = gl_error_count == 0.*?return ok \? 0 : 2;', source)
        self.assertIsNotNone(match)
        verdict = match.group()
        verdict = verdict[:verdict.index('    free(acc);')] + '    return ok ? 0 : 2;'
        run_c('''#include <assert.h>\n#include <stdint.h>\n#include <stdio.h>\n#include <stdlib.h>\n
#define TIMED_FRAMES 120
#define SETS 3
static int gl_error_count;
static uint64_t disjoint_drop,results;
static int check(void) {
    int sample_counts[6];uint64_t *samples[6];
    for (int v=0;v<6;v++) { sample_counts[v]=TIMED_FRAMES*SETS;samples[v]=malloc(1); }
''' + verdict + '''
}
int main(void) {
    results=(uint64_t)TIMED_FRAMES*SETS*6;
    assert(check()==2);return 0;
}
''')

    def test_glq_evaluates_once_and_fails_closed(self):
        source = SOURCE.read_text()
        start = source.index('#define GLQ(expr)')
        end = source.index('\n\n', start)
        macro = source[start:end]
        run_c('''#include <assert.h>\n#include <stdio.h>\n
static int calls, checks, fail;
static int gl_error_step(void) { checks++; return fail; }
''' + macro + '''
static int execute(void) { GLQ(calls++); return 0; }
int main(void) {
    assert(execute()==0 && calls==1 && checks==1);
    fail=1;
    assert(execute()==2 && calls==2 && checks==2);
    return 0;
}
''')

    def test_batch_never_draws_without_a_query_and_retirements_are_checked(self):
        source = SOURCE.read_text()
        self.assertIn('static int timer_begin(void)', source)
        self.assertIn('static int timer_end(void)', source)
        self.assertIn('static int timer_poll(void)', source)
        self.assertRegex(source, r'(?s)if \(!timer_begin\(\)\).*?return 2;')
        self.assertRegex(source, r'(?s)if \(!timer_end\(\)\).*?return 2;')
        self.assertIn('(f + 1) % RING == 0 || f + 1 == TIMED_FRAMES', source)

    def test_actual_batch_schedule_and_begin_failure(self):
        source = SOURCE.read_text()
        start = source.index('            int set_start = collect_n;')
        end = source.index('            sample_counts[v] = collect_n;', start)
        batch = source[start:end + len('            sample_counts[v] = collect_n;')]
        run_c('''#include <assert.h>\n#include <inttypes.h>\n#include <stdint.h>\n#include <stdio.h>\n
#define RING 16
#define TIMED_FRAMES 120
#define GL_TRIANGLES 4
#define GLQ(x) do { x; } while (0)
static int active,pending,collect_n,sample_counts[1],gl_error_count;
static uint64_t issued,results,stale_drop;
static int ring_active=-1,flushes,draws,drains,fail_begin_at,fail_end_at,fail_drain_at;
static int drop_issued,drop_results,drop_sample,fail_final_poll;
static int timer_begin(void) {
    if (fail_begin_at && draws==fail_begin_at) return 0;
    assert(!active && pending<RING);active=1;ring_active=0;issued++;return 1;
}
static void glDrawArrays(int a,int b,int c) { (void)a;(void)b;(void)c;assert(active);draws++; }
static int timer_end(void) {
    assert(active);if (fail_end_at && draws==fail_end_at) return 0;
    active=0;ring_active=-1;pending++;return 1;
}
static void glFlush(void) { flushes++; }
static int drain_all(void) {
    assert(!active && pending>0 && pending<=RING);
    if (++drains==fail_drain_at) return 0;
    collect_n+=pending;results+=pending;pending=0;return 1;
}
static int timer_poll(void) {
    if (drop_issued) issued--;
    if (drop_results) results--;
    if (drop_sample) collect_n--;
    return !fail_final_poll;
}
static int run(void) { int v=0;
''' + batch + '''
return 0; }
static void reset(void) {
    active=pending=collect_n=sample_counts[0]=gl_error_count=0;
    issued=results=stale_drop=0;
    ring_active=-1;flushes=draws=drains=0;
    fail_begin_at=fail_end_at=fail_drain_at=0;
    drop_issued=drop_results=drop_sample=fail_final_poll=0;
}
int main(void) {
    assert(run()==0);
    assert(draws==120 && flushes==8 && drains==8 && collect_n==120 && sample_counts[0]==120);
    reset();fail_begin_at=17;
    assert(run()==2 && draws==17 && flushes==1 && drains==1);
    reset();fail_end_at=17;
    assert(run()==2 && draws==17 && flushes==1 && drains==1);
    reset();fail_drain_at=2;
    assert(run()==2 && draws==32 && flushes==2 && drains==2);
    reset();drop_issued=1;assert(run()==2 && draws==120);
    reset();drop_results=1;assert(run()==2 && draws==120);
    reset();drop_sample=1;assert(run()==2 && draws==120);
    reset();fail_final_poll=1;assert(run()==2 && draws==120);
    return 0;
}
''')

    def test_actual_timer_poll_and_begin_fail_closed(self):
        source = SOURCE.read_text()
        timer = (extract_function(source, 'timer_poll') + '\n' +
                 extract_function(source, 'timer_begin'))
        run_c('''#include <assert.h>\n#include <stdint.h>\n
#define RING 2
typedef unsigned int GLenum;
typedef unsigned int GLuint;
typedef int GLint;
typedef uint64_t GLuint64;
static GLuint ring_ids[RING]={1,2};
static int ring_pending[RING],ring_active=-1,gl_error_count;
static uint64_t attempts,issued,results,disjoint_drop,*collect;
static int collect_n,collect_cap;
static int error_pending,checks,get_calls,begin_calls,ready_calls,result_calls;
static int fail_second_check;
static int gl_error_step(void) {
    int error=error_pending; error_pending=0; checks++;
    if (error) gl_error_count++;
    return error;
}
static void glGetIntegerv(GLenum name, GLint *out) {
    (void)name; *out=0;
    if (++get_calls==2 && fail_second_check) error_pending=1;
}
static void getiv(GLenum type, GLenum name, GLint *out) {
    (void)type; (void)name; *out=0;
}
static void getuiv(GLuint id, GLenum name, GLuint *out) {
    (void)id; (void)name; ready_calls++; *out=1;
}
static void getu64(GLuint id, GLenum name, GLuint64 *out) {
    (void)id; (void)name; result_calls++; *out=100;
}
static void begin(GLenum type, GLuint id) { (void)type; (void)id; begin_calls++; }
static struct {
    void (*getiv)(GLenum,GLenum,GLint *);
    void (*getuiv)(GLuint,GLenum,GLuint *);
    void (*getu64)(GLuint,GLenum,GLuint64 *);
    void (*begin)(GLenum,GLuint);
} q={getiv,getuiv,getu64,begin};
''' + timer + '''
int main(void) {
    uint64_t sample[2]={0}; collect=sample; collect_cap=2;
    ring_pending[0]=1; fail_second_check=1;
    timer_poll();
    assert(get_calls==2 && ready_calls==1 && result_calls==1);
    assert(gl_error_count==1 && ring_pending[0]==1 && results==0 && collect_n==0);
    gl_error_count=error_pending=checks=get_calls=ready_calls=result_calls=0;
    timer_begin();
    assert(gl_error_count==1 && begin_calls==0 && issued==0 && ring_active==-1);
    assert(ring_pending[0]==1 && results==0 && collect_n==0);
    return 0;
}
''')

    def test_lut_shader_scales_normalized_endpoints(self):
        source = SOURCE.read_text()
        self.assertIn('uniform highp sampler2D u_src;', source)
        self.assertIn('uniform highp sampler2D u_lut;', source)
        self.assertIn('texture(u_lut,vec2((f*(n-1.0)+0.5)/n,0.5)).r', source)
        for size in (1024, 4096):
            for f in (0.0, 0.25, 0.5, 1.0):
                with self.subTest(size=size, f=f):
                    coordinate = (f * (size - 1) + 0.5) / size
                    self.assertAlmostEqual(coordinate * size - 0.5, f * (size - 1))

    def test_timer_state_machine_rejects_unusable_measurements(self):
        source = SOURCE.read_text()
        timer = '\n'.join(extract_function(source, name)
                          for name in ('timer_poll', 'timer_begin', 'timer_end'))
        run_c('''#include <assert.h>\n#include <stdint.h>\n
#define RING 2
typedef unsigned int GLenum;
typedef unsigned int GLuint;
typedef int GLint;
typedef uint64_t GLuint64;
static GLuint ring_ids[RING]={11,22};
static int ring_pending[RING],ring_active=-1,gl_error_count;
static uint64_t attempts,issued,results,disjoint_drop,*collect;
static int collect_n,collect_cap;
static int fail_gl,disjoint,current,ready[2],begins,ends;
static int fail_begin_gl,fail_end_gl,disjoint_after_result;
static uint64_t values[2];
static int idx(GLuint id) { assert(id==11 || id==22);return id==11 ? 0 : 1; }
static int gl_error_step(void) { int fail=fail_gl;fail_gl=0;gl_error_count+=fail;return fail; }
static void glGetIntegerv(GLenum name,GLint *out) { (void)name;*out=disjoint; }
static void getiv(GLenum type,GLenum name,GLint *out) { (void)type;(void)name;*out=current; }
static void getuiv(GLuint id,GLenum name,GLuint *out) { (void)name;*out=ready[idx(id)]; }
static void getu64(GLuint id,GLenum name,GLuint64 *out) {
    (void)name;*out=values[idx(id)];if (disjoint_after_result) disjoint=1;
}
static void begin(GLenum type,GLuint id) {
    (void)type;(void)id;begins++;if (fail_begin_gl) fail_gl=1;
}
static void end(GLenum type) { (void)type;ends++;if (fail_end_gl) fail_gl=1; }
static struct {
    void (*getiv)(GLenum,GLenum,GLint *);void (*getuiv)(GLuint,GLenum,GLuint *);
    void (*getu64)(GLuint,GLenum,GLuint64 *);void (*begin)(GLenum,GLuint);
    void (*end)(GLenum);
} q={getiv,getuiv,getu64,begin,end};
''' + timer + '''
int main(void) {
    uint64_t samples[2]={0};collect=samples;collect_cap=2;
    assert(!timer_end() && ends==0);
    assert(timer_begin() && ring_active==0 && issued==1 && begins==1);
    assert(!timer_begin() && begins==1);
    assert(timer_end() && ring_pending[0] && ring_active==-1 && ends==1);
    assert(timer_begin() && ring_active==1 && timer_end());
    assert(!timer_begin() && begins==2 && issued==2);
    ready[1]=1;values[1]=200;
    assert(timer_poll() && collect_n==1 && samples[0]==200 && ring_pending[0]);
    assert(!ring_pending[1] && results==1);
    ready[0]=1;values[0]=0;
    assert(!timer_poll() && ring_pending[0] && collect_n==1 && results==1);
    values[0]=100;collect_cap=1;
    assert(!timer_poll() && ring_pending[0] && collect_n==1 && results==1);
    collect_cap=2;collect=0;
    assert(!timer_poll() && ring_pending[0] && results==1);
    collect=samples;disjoint=1;
    assert(!timer_poll() && ring_pending[0] && disjoint_drop==1 && results==1);
    disjoint=0;
    assert(timer_poll() && !ring_pending[0] && collect_n==2 && samples[1]==100 && results==2);
    assert(timer_poll() && collect_n==2 && results==2);
    current=9;assert(!timer_begin() && begins==2);current=0;
    fail_gl=1;assert(!timer_begin() && begins==2 && gl_error_count==1);
    fail_begin_gl=1;assert(!timer_begin() && ring_active==-1 && issued==2);
    fail_begin_gl=0;assert(timer_begin() && ring_active==0 && issued==3);
    fail_end_gl=1;assert(!timer_end() && ring_active==0 && !ring_pending[0]);
    /* The production main terminates on an end error. Reset only this fake GL
     * state to test the independent result/disjoint failure path below. */
    fail_end_gl=0;ring_active=-1;ring_pending[0]=1;
    collect_n=0;ready[0]=1;values[0]=100;disjoint_after_result=1;
    assert(!timer_poll() && ring_pending[0] && collect_n==0 && disjoint_drop==2);
    return 0;
}
''')

    def test_main_clock_fails_closed(self):
        source = SOURCE.read_text()
        clock = extract_function(source, 'now_seconds')
        start = source.index('    double started;')
        end = source.index('    for (int set = 0;', start)
        before = source[start:end]
        start = source.index('    double finished;')
        end = source.index('    printf("PQLUT timing wall_seconds=', start)
        after = source[start:end]
        run_c('''#include <assert.h>\n#include <stdint.h>\n#include <stdio.h>\n
#define CLOCK_MONOTONIC 1
struct timespec { long tv_sec,tv_nsec; };
static int calls,fail_at,bad_at,backwards;
static double elapsed_seen;
int clock_gettime(int clock,struct timespec *ts) {
    assert(clock==CLOCK_MONOTONIC);calls++;
    if (calls==fail_at) return -1;
    ts->tv_sec=calls==2 && backwards ? 9 : 10;
    ts->tv_nsec=calls==bad_at ? 1000000000L : calls*100;
    return 0;
}
''' + clock + '''
static int execute(void) {
''' + before + after + '''
    elapsed_seen=elapsed;return 0;
}
int main(void) {
    assert(execute()==0 && elapsed_seen>0);
    calls=0;fail_at=1;assert(execute()==2);
    calls=0;fail_at=2;assert(execute()==2);
    calls=fail_at=0;bad_at=1;assert(execute()==2);
    calls=0;bad_at=2;assert(execute()==2);
    calls=bad_at=0;backwards=1;assert(execute()==2);
    return 0;
}
''')

    def test_drain_fails_on_timeout_or_poll_error(self):
        source = SOURCE.read_text()
        deadline = (extract_function(source, 'drain_deadline_check')
                    if 'static int drain_deadline_check(' in source else '')
        drain = deadline + '\n' + extract_function(source, 'drain_all')
        run_c('''#include <assert.h>\n#include <stdint.h>\n
#define RING 2
#define DRAIN_TIMEOUT_SECONDS 20
#define CLOCK_MONOTONIC 1
struct timespec { long tv_sec, tv_nsec; };
static int ring_pending[RING], polls, sleeps, clocks;
static int complete_at, fail_poll, fail_sleep, fail_clock_at, bad_clock_at, backward_at;
static int advance_after_bad_start;
static uint64_t stale_drop, clock_ns, sleep_advance, poll_advance;
int clock_gettime(int clock, struct timespec *ts) {
    assert(clock==CLOCK_MONOTONIC); clocks++;
    if (clocks==fail_clock_at) return -1;
    if (clocks==2 && advance_after_bad_start) clock_ns+=2000000000ull;
    uint64_t value=clock_ns;
    if (clocks==backward_at) value--;
    ts->tv_sec=(long)(value/1000000000u);
    ts->tv_nsec=(long)(value%1000000000u);
    if (clocks==bad_clock_at) ts->tv_nsec=1000000000L;
    return 0;
}
static int usleep(unsigned usec) {
    assert(usec==1000); sleeps++; clock_ns+=sleep_advance; return fail_sleep ? -1 : 0;
}
static int timer_poll(void) {
    polls++;clock_ns+=poll_advance;
    if (polls==complete_at) ring_pending[0]=0;
    return !fail_poll;
}
''' + drain + '''
static void reset(void) {
    ring_pending[0]=1;ring_pending[1]=0;
    polls=sleeps=clocks=complete_at=fail_poll=fail_sleep=0;
    fail_clock_at=bad_clock_at=backward_at=advance_after_bad_start=0;
    stale_drop=0;clock_ns=100000000000ull;sleep_advance=poll_advance=0;
}
int main(void) {
    reset();complete_at=2;sleep_advance=1000000;
    assert(drain_all()==1 && polls==2 && sleeps==1 && !stale_drop);
    reset();sleep_advance=50000000;
    assert(drain_all()==0 && polls==400 && sleeps==400 && stale_drop==1);
    assert(ring_pending[0]==1);
    reset();complete_at=1;poll_advance=20000000000ull;
    assert(drain_all()==0 && polls==1 && !sleeps);
    reset();complete_at=1;poll_advance=19999999999ull;
    assert(drain_all()==1 && polls==1 && !sleeps);
    reset();complete_at=1;poll_advance=21000000000ull;
    assert(drain_all()==0 && polls==1 && !sleeps);
    reset();ring_pending[1]=1;sleep_advance=21000000000ull;
    assert(drain_all()==0 && polls==1 && sleeps==1 && stale_drop==2);
    reset();fail_poll=1;
    assert(drain_all()==0 && polls==1 && !sleeps && !stale_drop);
    reset();fail_clock_at=1;assert(drain_all()==0 && !polls && !sleeps);
    reset();fail_clock_at=2;assert(drain_all()==0 && !polls && !sleeps);
    reset();fail_clock_at=3;assert(drain_all()==0 && polls==1 && !sleeps);
    reset();bad_clock_at=1;advance_after_bad_start=1;complete_at=1;
    assert(drain_all()==0 && clocks==1 && !polls);
    reset();bad_clock_at=2;assert(drain_all()==0 && !polls);
    reset();backward_at=3;assert(drain_all()==0 && polls==1 && !sleeps);
    reset();clock_ns+=500;backward_at=3;
    assert(drain_all()==0 && polls==1 && !sleeps);
    reset();fail_sleep=1;assert(drain_all()==0 && polls==1 && sleeps==1);
    reset();assert(drain_all()==0 && polls==20000 && sleeps==20000 && stale_drop==1);
    return 0;
}
''')


CANARY_STUBS = r'''
#include <assert.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#define PROBE_W 4
#define PROBE_H 3
#define GL_FRAMEBUFFER 1
#define GL_SCISSOR_TEST 2
#define GL_BLEND 3
#define GL_DEPTH_TEST 4
#define GL_STENCIL_TEST 5
#define GL_CULL_FACE 6
#define GL_RASTERIZER_DISCARD 7
#define GL_DITHER 8
#define GL_TRUE 1
#define GL_PIXEL_PACK_BUFFER 9
#define GL_PACK_ALIGNMENT 10
#define GL_PACK_ROW_LENGTH 11
#define GL_PACK_SKIP_PIXELS 12
#define GL_PACK_SKIP_ROWS 13
#define GL_COLOR_ATTACHMENT0 14
#define GL_COLOR 15
#define GL_TRIANGLES 16
#define GL_RGBA 17
#define GL_FLOAT 18
#define GLQ(expr) do { expr; if (gl_error_step()) return 2; } while (0)
typedef unsigned GLuint;
typedef unsigned GLenum;
typedef int GLint;
typedef float GLfloat;
static const char *CANARY_FS="canary";
static GLuint fbo=41;
static size_t pixels=PROBE_W*PROBE_H;
static int program_fail,uniform_fail,fail_read,corrupt_phase,corrupt_kind;
static int corrupt_pixel,corrupt_channel,rendered_phase,stale_phase;
static int checks,read_calls,draws,current_phase,deleted,clears,setup_mask,bound,used;
static int setup_extra,fail_at;
static float framebuffer[PROBE_W*PROBE_H*4],previous[PROBE_W*PROBE_H*4];
static void *allocation;
static void *test_malloc(size_t size) { assert(!allocation);return allocation=malloc(size); }
static void test_free(void *ptr) { assert(ptr==allocation);free(ptr);allocation=NULL; }
#define malloc test_malloc
#define free test_free
static int gl_error_step(void) { return ++checks==fail_at; }
static GLuint link_program(const char *s) { assert(s==CANARY_FS);return program_fail ? 0 : 21; }
static GLint glGetUniformLocation(GLuint p,const char *name) {
    assert(p==21 && name[0]=='u');return uniform_fail ? -1 : 11;
}
static void glBindFramebuffer(int target,GLuint f) { assert(target==GL_FRAMEBUFFER && f==fbo);bound=1; }
static void glViewport(int x,int y,int w,int h) {
    assert(!x && !y && w==PROBE_W && h==PROBE_H);setup_extra|=1<<0;
}
static void glDisable(int flag) { assert(flag>=GL_SCISSOR_TEST && flag<=GL_DITHER);setup_mask|=1<<flag; }
static void glColorMask(int a,int b,int c,int d) { assert(a && b && c && d);setup_extra|=1<<1; }
static void glBindBuffer(int target,GLuint b) {
    assert(target==GL_PIXEL_PACK_BUFFER && !b);setup_extra|=1<<2;
}
static void glPixelStorei(int name,int value) {
    assert((name==GL_PACK_ALIGNMENT && value==4) ||
           (name>=GL_PACK_ROW_LENGTH && name<=GL_PACK_SKIP_ROWS && !value));
    setup_extra|=1<<(3+name-GL_PACK_ALIGNMENT);
}
static void glReadBuffer(int b) { assert(b==GL_COLOR_ATTACHMENT0);setup_extra|=1<<7; }
static void glDrawBuffers(int n,const GLenum *b) {
    assert(n==1 && *b==GL_COLOR_ATTACHMENT0);setup_extra|=1<<8;
}
static void glClearBufferfv(int b,int drawbuffer,const GLfloat *v) {
    assert(b==GL_COLOR && !drawbuffer && v[0]==-2 && v[1]==3 && v[2]==-4 && v[3]==0);
    assert(bound && setup_mask==0x1fc && setup_extra==0x1ff);
    for (size_t i=0;i<pixels;i++) for (int c=0;c<4;c++) framebuffer[i*4+c]=v[c];
    clears++;current_phase=rendered_phase=0;
}
static void glUseProgram(GLuint p) { assert(p==21);used=1; }
static void glUniform1i(GLint location,int phase) { assert(location==11 && used);current_phase=phase; }
static void glDrawArrays(int mode,int first,int count) {
    assert(mode==GL_TRIANGLES && first==0 && count==3 && used && current_phase==draws+1);
    for (size_t i=0;i<pixels*4;i++) previous[i]=framebuffer[i];
    for (int y=0;y<PROBE_H;y++) for (int x=0;x<PROBE_W;x++) {
        size_t i=((size_t)y*PROBE_W+x)*4;
        framebuffer[i]=2+(x&1)*0.5f+current_phase*0.25f;
        framebuffer[i+1]=-1-(y&1)*0.5f-current_phase*0.25f;
        framebuffer[i+2]=4+((x+y)&1)*0.5f+current_phase*0.25f;
        framebuffer[i+3]=1;
    }
    rendered_phase=current_phase;draws++;
}
static void glReadPixels(int x,int y,int w,int h,int format,int type,float *p) {
    assert(!x && !y && w==PROBE_W && h==PROBE_H && format==GL_RGBA && type==GL_FLOAT);
    assert(clears==1 && current_phase==read_calls && rendered_phase==current_phase);
    assert(setup_mask==0x1fc && setup_extra==0x1ff);
    for (size_t i=0;i<pixels*4;i++) assert(isnan(p[i]));
    read_calls++;
    if (fail_read) return;
    for (size_t i=0;i<pixels*4;i++)
        p[i]=current_phase==stale_phase ? previous[i] : framebuffer[i];
    if (current_phase==corrupt_phase) {
        size_t i=(size_t)corrupt_pixel*4+corrupt_channel;
        if (corrupt_kind==1) p[i]=NAN;
        if (corrupt_kind==2) p[i]=INFINITY;
        if (corrupt_kind==3) p[i]=-INFINITY;
        if (corrupt_kind==4) p[i]+=0.25f;
        if (corrupt_kind==5) {
            size_t j=(size_t)corrupt_pixel*4+(corrupt_channel+1)%4;
            float saved=p[i];p[i]=p[j];p[j]=saved;
        }
    }
}
static void glDeleteProgram(GLuint p) { assert(p==21);deleted++; }
'''


CANARY_CASES = r'''
static void reset(void) {
    if (allocation) { free(allocation);assert(!allocation); }
    program_fail=uniform_fail=fail_read=corrupt_kind=checks=read_calls=draws=0;
    current_phase=deleted=clears=setup_mask=setup_extra=bound=used=fail_at=0;
    corrupt_phase=rendered_phase=stale_phase=-1;
}
int main(void) {
    reset();assert(execute()==0 && read_calls==3 && draws==2 && clears==1 && deleted==1);
    int checkpoints=checks;
    reset();program_fail=1;assert(execute()==2 && !read_calls);
    reset();uniform_fail=1;assert(execute()==2 && !read_calls);
    reset();fail_read=1;assert(execute()==2 && read_calls==1 && !draws);
    for (int phase=0;phase<3;phase++) for (int pixel=0;pixel<PROBE_W*PROBE_H;pixel++)
    for (int channel=0;channel<4;channel++) for (int kind=1;kind<=5;kind++) {
        reset();corrupt_phase=phase;corrupt_pixel=pixel;corrupt_channel=channel;corrupt_kind=kind;
        assert(execute()==2 && read_calls==phase+1 && draws==phase);
    }
    for (int phase=1;phase<3;phase++) {
        reset();stale_phase=phase;assert(execute()==2 && read_calls==phase+1);
    }
    for (int at=1;at<=checkpoints;at++) {
        reset();fail_at=at;assert(execute()==2 && checks==at);
    }
    reset();
    float good[4]={-2,3,-4,0};
    assert(!canary_check(NULL,1,1,0));
    assert(!canary_check(good,0,1,0) && !canary_check(good,1,0,0));
    assert(!canary_check(good,-1,1,0) && !canary_check(good,1,-1,0));
    assert(!canary_check(good,1,1,-1) && !canary_check(good,1,1,3));
    return 0;
}
'''


if __name__ == '__main__':
    unittest.main()
