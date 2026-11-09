"""Test the offline lease request plan; no device or timing claims."""
from contextlib import redirect_stderr, redirect_stdout
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import types
import unittest


SOURCE = Path(__file__).with_name('lg_p84_lease_control_plan.py')
TARGET = 'debug.mks.st_lease_target'


class ObservedIO:
    """Reject observed Python audit events, not a general-purpose sandbox."""

    def __init__(self):
        self.active = False
        self.events = []
        sys.addaudithook(self._hook)

    def _hook(self, event, args):
        if self.active and (event == 'open' or event.startswith(
                ('os.', 'subprocess.', 'socket.', 'ctypes.'))):
            self.events.append(event)
            raise AssertionError('unexpected audited operation: ' + event)

    def __enter__(self):
        self.events.clear()
        self.active = True
        return self

    def __exit__(self, exc_type, exc, tb):
        self.active = False
        if self.events and exc_type is None:
            raise AssertionError('audited operations were attempted: ' + repr(self.events))
        return False


# Load the source bytes before observing module execution, so the permitted read
# is not confused with I/O initiated by the module. This exercises its top-level
# code, not the import loader's own cache/read behaviour.
code = compile(SOURCE.read_bytes(), str(SOURCE), 'exec')
plan = types.ModuleType('lease_control_plan')
plan.__file__ = str(SOURCE)
observed_io = ObservedIO()
output = io.StringIO()
with redirect_stdout(output), redirect_stderr(output), observed_io:
    exec(code, plan.__dict__)
if output.getvalue():
    raise AssertionError('unexpected module output: ' + output.getvalue())


class LeaseControlPlanTests(unittest.TestCase):
    def test_same_sync_target_only_and_interleaved_order(self):
        common = {
            'debug.mks.thermal_trace': '1', 'debug.mks.defer_publish_flush': '0',
            'debug.mks.gpu_timing': '0', 'debug.mks.yuv_fusion': '1',
            'debug.mks.yuv_fusion_table': '0', 'debug.mks.yuv_fail_commit': '0',
            'debug.mks.yuv_fail_gl': '0', 'debug.mks.st_fbo': '0',
            'debug.mks.st_lease_rgba16': '0',
        }
        self.assertEqual(plan.TARGET, TARGET)
        for sync in ('display-resample', 'audio'):
            value = plan.build_lease_control_plan(video_sync=sync)
            self.assertEqual(value['pairCount'], 3)
            self.assertEqual([[r['mode'] for r in pair['plannedRounds']] for pair in value['pairs']],
                             [['baseline', 'candidate'], ['candidate', 'baseline'],
                              ['baseline', 'candidate']])
            ids = set()
            for number, pair in enumerate(value['pairs'], 1):
                self.assertEqual(pair['pairId'], f'pair-{number:02d}')
                rounds = {r['mode']: r for r in pair['plannedRounds']}
                self.assertEqual(set(rounds), {'baseline', 'candidate'})
                for mode, target in (('baseline', '0'), ('candidate', '1')):
                    row = rounds[mode]
                    ids.add(row['roundId'])
                    self.assertEqual(row['roundId'], f'pair-{number:02d}-'+('A' if target == '0' else 'B'))
                    self.assertEqual(row['requestedProperties'], {
                        **common, 'debug.mks.thermal_sync': sync, TARGET: target})
                a, b = (rounds[k]['requestedProperties'] for k in ('baseline', 'candidate'))
                self.assertEqual({key for key in a if a[key] != b[key]}, {TARGET})
            self.assertEqual(len(ids), 6)

    def test_evidence_stays_unqualified_and_plan_is_json(self):
        value = plan.build_lease_control_plan(video_sync='audio')
        self.assertEqual(value['schema'], 'lg-p84-lease-control-plan/v1')
        self.assertEqual(value['artifactKind'], 'requested-control-plan')
        self.assertIs(value['executionAllowed'], False)
        self.assertIs(value['m2Eligible'], False)
        self.assertEqual(value['m2Verdict'], 'not-evaluated')
        self.assertEqual(value['planChecks'], {'controlDeltaOnly': True})
        self.assertEqual(value['evidence'], {
            'requested': 'planned-only', 'readback': 'not-collected',
            'published': 'not-collected', 'consumed': 'not-collected',
            'timing': 'unsupported-for-M2', 'samePackage': 'unverified'})
        self.assertEqual(set(value['unbound']), {
            'apk-and-loaded-native-source', 'source-identity', 'thermal-anchor',
            'duration-and-stable-window', 'device-state-and-actual-order'})
        self.assertNotIn('validCompletedProfile', value)
        self.assertNotIn('status', value)
        self.assertEqual(json.loads(json.dumps(value, allow_nan=False)), value)

    def test_bad_inputs_and_extra_arguments_are_rejected(self):
        class Sync(str):
            pass

        class Count(int):
            pass

        with self.assertRaises(TypeError):
            plan.build_lease_control_plan()
        for value in ('', ' audio', 'audio ', 'Audio', 'sync', None, 0, True, Sync('audio')):
            with self.subTest(sync=value), self.assertRaises(ValueError):
                plan.build_lease_control_plan(video_sync=value)
        for count in (True, False, -1, 0, 2, 33, 3.0, '3', None, Count(3)):
            with self.subTest(count=count), self.assertRaises(ValueError):
                plan.build_lease_control_plan(video_sync='audio', pair_count=count)
        for extra in ('experiment', 'lease_target', 'gpu_timing', 'receipt', 'serial',
                      'output', 'execute', 'm2Eligible', 'verified'):
            with self.subTest(extra=extra), self.assertRaises(TypeError):
                plan.build_lease_control_plan(video_sync='audio', **{extra: True})
        self.assertEqual(len(plan.build_lease_control_plan(video_sync='audio', pair_count=32)['pairs']), 32)

    def test_pairs_and_subsequent_results_do_not_share_mutable_controls(self):
        first = plan.build_lease_control_plan(video_sync='audio')
        reference = plan.build_lease_control_plan(video_sync='audio')
        a, b = first['pairs'][0]['plannedRounds']
        a['requestedProperties'][plan.TARGET] = 'changed'
        self.assertEqual(b['requestedProperties'][plan.TARGET], '1')
        self.assertEqual(first['pairs'][1], reference['pairs'][1])
        self.assertEqual(plan.build_lease_control_plan(video_sync='audio'), reference)

    def test_delta_guard_checks_keys_and_direction(self):
        a, b = {plan.TARGET: '0', 'sync': 'audio'}, {plan.TARGET: '1', 'sync': 'audio'}
        plan._check_pair(a, b)
        for other in ({plan.TARGET: '0', 'sync': 'audio'},
                      {plan.TARGET: '1', 'sync': 'display-resample'},
                      {plan.TARGET: '1'}, {plan.TARGET: '1', 'sync': 'audio', 'extra': '0'}):
            with self.subTest(other=other), self.assertRaises(ValueError):
                plan._check_pair(a, other)
        with self.assertRaises(ValueError):
            plan._check_pair({plan.TARGET: '1'}, {plan.TARGET: '0'})
        for a, b in (({}, {}), ({'sync': 'audio'}, {'sync': 'audio'}),
                     ({'sync': 'audio'}, {'sync': 'display-resample'})):
            with self.subTest(a=a, b=b), self.assertRaises(ValueError):
                plan._check_pair(a, b)

    def test_module_execution_and_calls_reject_observed_io(self):
        class Sync(str):
            pass

        class Count(int):
            pass

        output = io.StringIO()
        with redirect_stdout(output), redirect_stderr(output), observed_io:
            for sync in ('display-resample', 'audio'):
                for count in range(3, 33):
                    plan.build_lease_control_plan(video_sync=sync, pair_count=count)
            for kwargs in ({'video_sync': 'bad'}, {'video_sync': Sync('audio')},
                           {'video_sync': 'audio', 'pair_count': 2},
                           {'video_sync': 'audio', 'pair_count': 33},
                           {'video_sync': 'audio', 'pair_count': Count(3)},
                           {'video_sync': 'audio', 'pair_count': True}):
                try:
                    plan.build_lease_control_plan(**kwargs)
                except ValueError:
                    pass
                else:
                    raise AssertionError('invalid input unexpectedly accepted')
            for a, b in (({}, {}), ({TARGET: '0'}, {TARGET: '1'}),
                         ({TARGET: '1'}, {TARGET: '0'})):
                try:
                    plan._check_pair(a, b)
                except ValueError:
                    if a == {TARGET: '0'} and b == {TARGET: '1'}:
                        raise
                else:
                    if a != {TARGET: '0'} or b != {TARGET: '1'}:
                        raise AssertionError('invalid pair unexpectedly accepted')
        self.assertEqual(output.getvalue(), '')
        self.assertNotIn('lg_p84_thermal_round', plan.__dict__)
        self.assertNotIn('lg_p84_instant_perf', plan.__dict__)

    def test_direct_invocation_has_no_output_or_cwd_files(self):
        with tempfile.TemporaryDirectory() as root:
            result = subprocess.run([sys.executable, '-I', '-B', str(SOURCE)], cwd=root,
                                    capture_output=True, text=True, check=True, timeout=5)
            self.assertEqual(result.stdout, '')
            self.assertEqual(result.stderr, '')
            self.assertEqual(list(Path(root).iterdir()), [])


if __name__ == '__main__':
    unittest.main()
