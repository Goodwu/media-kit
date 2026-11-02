#!/usr/bin/env python3
import importlib.util
import base64
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('thermal_round', Path(__file__).with_name('lg_p84_thermal_round.py'))
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)


class ThermalRoundTests(unittest.TestCase):
    def fbo_state(self, requested='1'):
        tracker = {'configCount': 0, 'requested': None, 'rows': [], 'error': None}
        m.input_fbo_feed(tracker, 'MKS-INPUT-FBO event=config requested='+requested, 0)
        for count, at in ((1, 1), (300, 11), (600, 21)):
            m.input_fbo_feed(tracker, ('MKS-INPUT-FBO requested='+requested+
                f' slot_attempts={count if requested=="1" else 0} shared_attempts={count if requested=="0" else 0}'
                ' fallbacks=0 copy_failures=0 final=0'), at)
        return {'inputFbo': tracker, 'hostMonotonic': 22,
                'nativeImportIdentity': {'instance': '0x123', 'start_ns': '1'}, 'nativeImportChanged': False}

    def test_fbo_requires_actual_path_progress_within_valid_window_and_fresh_report(self):
        for expected in ('0', '1'):
            state = self.fbo_state(expected)
            self.assertIsNone(m.input_fbo_error(state, expected, since=10))
            self.assertIn('requested-path', m.input_fbo_error(state, '0' if expected=='1' else '1'))
            self.assertIn('no-progress', m.input_fbo_error(state, expected, since=20))
            state['hostMonotonic'] = 41
            self.assertIn('stale', m.input_fbo_error(state, expected))
        self.assertIsNone(m.input_fbo_error({}, '1', strict=False))
        self.assertIn('missing', m.input_fbo_error({}, '1'))

    def test_fbo_multiple_mappers_rollback_fallback_failures_and_wrong_path_are_invalid(self):
        for change in ('duplicate-config', 'rollback', 'fallback', 'failure', 'shared', 'final', 'mapper', 'identity'):
            state = self.fbo_state()
            tracker = state['inputFbo']
            line = 'MKS-INPUT-FBO requested=1 slot_attempts=900 shared_attempts=0 fallbacks=0 copy_failures=0 final=0'
            if change == 'duplicate-config':m.input_fbo_feed(tracker, 'MKS-INPUT-FBO event=config requested=1', 22)
            elif change == 'mapper':state['nativeImportChanged'] = True
            elif change == 'identity':state['nativeImportIdentity'] = {}
            else:
                substitutions = {'rollback': ('slot_attempts=900','slot_attempts=1'), 'fallback':('fallbacks=0','fallbacks=1'),
                    'failure':('copy_failures=0','copy_failures=1'), 'shared':('shared_attempts=0','shared_attempts=1'),
                    'final':('final=0','final=1')}
                a,b = substitutions[change];m.input_fbo_feed(tracker, line.replace(a,b), 22)
            with self.subTest(change=change):self.assertIsNotNone(m.input_fbo_error(state, '1', since=10))
        for line in ('MKS-INPUT-FBO invalid override; using original shared FBO',
                     'MKS-INPUT-FBO event=unknown requested=1',
                     'MKS-INPUT-FBO requested=1 slot_attempts=1 shared_attempts=0 fallbacks=0 copy_failures=0 final=0 requested=0'):
            state = self.fbo_state();m.input_fbo_feed(state['inputFbo'],line,22)
            self.assertIsNotNone(m.input_fbo_error(state,'1'))

    def test_fbo_log_capture_buffers_startup_then_binds_exact_process(self):
        from unittest.mock import MagicMock
        stamp = m.dt.datetime.now(m.dt.timezone(m.dt.timedelta(hours=8))).strftime('%m-%d %H:%M:%S.%f')[:-3]
        with tempfile.TemporaryDirectory() as d:
            adb = MagicMock();adb.shell.return_value = str(int(m.time.time()));adb.prefix = ['adb','-s','S']
            capture = m.LogCapture(adb,Path(d))
            proc = MagicMock();proc.poll.return_value = None
            proc.stdout = iter([f'{stamp} 999 999 I flutter : MKS-INPUT-FBO event=config requested=0\n',
                f'{stamp} 123 123 I flutter : MKS-INPUT-FBO event=config requested=1\n',
                f'{stamp} 123 123 I flutter : MKS-INPUT-FBO requested=1 slot_attempts=1 shared_attempts=0 fallbacks=0 copy_failures=0 final=0\n'])
            with patch.object(m.subprocess,'Popen',return_value=proc) as launch:capture.start();capture.thread.join(timeout=3)
            self.addCleanup(launch.call_args.kwargs['stderr'].close)
            capture.flutter_stream = None  # Mock stream ended before binding.
            capture.set_expected_pid('123')
            state = capture.state()
            self.assertEqual(state['inputFbo']['configCount'],1)
            self.assertEqual(state['inputFbo']['requested'],'1')
            self.assertIsNone(m.input_fbo_error(state,'1'))
            capture.close()
            launch.call_args.kwargs['stderr'].close()

    def test_fbo_property_snapshot_and_restore_includes_empty_original(self):
        with tempfile.TemporaryDirectory() as d:
            adb = m.Adb('S',Path(d))
            with patch.object(adb,'call',return_value=''):props = adb.properties()
            self.assertIn(m.INPUT_FBO_PROPERTY,props)
            with patch.object(adb,'shell') as shell:adb.restore({},props)
            self.assertIn("setprop debug.mks.st_fbo ''",[c.args[0] for c in shell.call_args_list])

    def test_explicit_lg_temperature_contract_and_missing_nodes(self):
        self.assertEqual(m.temperature({'battery_type': 'battery', 'battery_temp': '37300', 'vts_type': 'vts', 'vts_temp': '485'}), (37.3, 48.5))
        self.assertEqual(m.temperature({'battery_type': 'tsens', 'battery_temp': '491', 'vts_type': 'wrong', 'vts_temp': '485'}), (None, None))

    def test_thresholds_apply_identically_to_both_modes(self):
        self.assertEqual(m.abort_reason({'batteryC': 45, 'vtsC': 40}, {}), 'battery-at-or-above-45C')
        self.assertEqual(m.abort_reason({'batteryC': 37, 'vtsC': 48.5}, {}), 'vts-at-or-above-48.5C')
        self.assertEqual(m.abort_reason({}, {'hotEventsLast30s': 2}), 'fresh-system-check-hot')
        self.assertIsNone(m.abort_reason({'batteryC': 44.9, 'vtsC': 48.4}, {'hotEventsLast30s': 0}))

    def test_log_json_extract_not_stale_prefix_or_malformed(self):
        self.assertEqual(m.parse_thermal_json('10-29 I/flutter: THERMAL_JSON {"serial":2,"phase":"sample"}'), {'serial': 2, 'phase': 'sample'})
        self.assertIsNone(m.parse_thermal_json('unrelated {"serial":2}'))
        self.assertIsNone(m.parse_thermal_json('THERMAL_JSON broken'))

    def test_proc_stat_with_spaces_and_parentheses(self):
        # proc numeric fields 3..15: state through stime.
        self.assertEqual(m.proc_cpu_ticks('123 (thread (name)) S 1 2 3 4 5 6 7 8 9 10 110 220'), 330)
        self.assertIsNone(m.proc_cpu_ticks('malformed'))

    def test_restore_attempts_all_entries_even_after_failure(self):
        with tempfile.TemporaryDirectory() as d:
            adb = m.Adb('SERIAL', Path(d))
            calls = []
            def call(args, **kwargs):
                calls.append(args)
                if args[-1] == '162':
                    raise RuntimeError('write failed')
                return ''
            with patch.object(adb, 'call', side_effect=call), patch.object(adb, 'shell', side_effect=lambda script: calls.append(script)):
                errors = adb.restore({'screen_brightness': '162', 'user_rotation': 'null'}, {'debug.mks.thermal_sync': ''})
            self.assertEqual(len(errors), 1)
            self.assertIn(['shell', 'settings', 'delete', 'system', 'user_rotation'], calls)
            self.assertTrue(any(isinstance(v, str) and 'thermal_sync' in v for v in calls))

    def test_complete_runtime_contract_and_wrong_hardware(self):
        lab = {'pid': 100, 'runId': '100:unique', 'phase': 'sample', 'serial': 1, 'mode': 'audio', 'properties': {'video-sync': 'audio', 'hwdec-current': 'surfacetexture', 'vo': 'gpu-next', 'target-trc': 'pq', 'target-peak': '1000', 'target-prim': 'bt.2020', 'gamma': '0', 'pause': 'no'}, 'report': {'verified': True, 'source': {'kind': 'dolbyVisionP84'}, 'actual': {'strategy': 'baseLayerConvert'}}}
        state = {'lab': lab, 'labAgeSeconds': 1, 'playbackSerial': 1, 'playbackRunId': '100:unique', 'playbackPid': '100', 'labPid': '100'}
        self.assertIsNone(m.runtime_error(state, 'audio'))
        lab['properties']['hwdec-current'] = 'no'
        self.assertEqual(m.runtime_error(state, 'audio'), 'runtime-property-mismatch:hwdec-current')
        self.assertEqual(m.runtime_error({'lab':lab, 'labAgeSeconds':31, 'playbackSerial': 1, 'playbackRunId': '100:unique', 'playbackPid': '100', 'labPid': '100'}, 'audio'), 'missing-or-stale-THERMAL_JSON')


    def test_restart_with_same_open_serial_cannot_complete_window(self):
        lab = {'pid': 200, 'runId': '200:new', 'serial': 1, 'phase': 'sample', 'mode': 'audio'}
        state = {'lab': lab, 'labAgeSeconds': 1, 'playbackSerial': 1,
                 'playbackRunId': '100:first', 'playbackPid': '100', 'labPid': '200'}
        self.assertEqual(m.runtime_error(state, 'audio', '200'), 'playback-run-id-drift-or-missing')
        lab['runId'] = '100:first'
        self.assertEqual(m.runtime_error(state, 'audio', '200'), 'harness-frozen-pid-mismatch')



    def multipart(self, row, count=3):
        data = base64.b64encode(json.dumps(row).encode()).decode()
        size = (len(data) + count - 1) // count
        chunks = [data[i:i+size] for i in range(0, len(data), size)]
        return ['THERMAL_JSON_PART ' + json.dumps({'r': row['runId'], 'n': row['sampleOrdinal'], 'i': i, 'c': len(chunks), 'd': chunk}) for i, chunk in enumerate(chunks)]

    def test_multipart_only_complete_bound_identity_is_accepted(self):
        row = {'schemaVersion': 1, 'runId': '100:unique', 'pid': 100, 'serial': 3, 'sampleOrdinal': 7, 'properties': {'gamma': '0'}}
        parts = self.multipart(row)
        assembler = m.ThermalLogAssembler()
        self.assertIsNone(assembler.feed(parts[2], '100', 0))
        self.assertIsNone(assembler.feed(parts[0], '200', 1))
        self.assertIsNone(assembler.feed(parts[0], '100', 2))
        self.assertEqual(assembler.feed(parts[1], '100', 3), row)
        for part in parts:
            result = assembler.feed(part, '100', 4)
        self.assertIsNone(result)  # replay of the same ordinal

    def test_multipart_timeout_and_count_conflict_reject_partial(self):
        row = {'schemaVersion': 1, 'runId': '100:unique', 'pid': 100, 'serial': 3, 'sampleOrdinal': 7}
        parts = self.multipart(row)
        assembler = m.ThermalLogAssembler(ttl=20)
        assembler.feed(parts[0], '100', 0)
        assembler.feed(parts[1], '100', 21)
        self.assertIsNone(assembler.feed(parts[2], '100', 22))
        self.assertEqual(assembler.expired_groups, 1)
        changed = json.loads(parts[1].split(' ', 1)[1]); changed['c'] += 1
        self.assertIsNone(assembler.feed('THERMAL_JSON_PART ' + json.dumps(changed), '100', 23))
        self.assertGreater(assembler.rejected_parts, 0)

    def test_auto_restore_accepts_scalar_change_but_manual_is_strict(self):
        old = {'screen_brightness_mode': '1', 'screen_brightness': '162', 'user_rotation': '0'}
        new = dict(old, screen_brightness='163')
        self.assertEqual(m.restoration_matches(old, new, {}, {}, []), (True, True))
        self.assertEqual(m.restoration_matches(old, new, {}, {}, ['write failed']), (False, True))
        old['screen_brightness_mode'] = new['screen_brightness_mode'] = '0'
        self.assertEqual(m.restoration_matches(old, new, {}, {}, []), (False, False))

    def test_restore_scalar_precedes_auto_mode(self):
        with tempfile.TemporaryDirectory() as d:
            adb = m.Adb('SERIAL', Path(d))
            calls = []
            with patch.object(adb, 'call', side_effect=lambda args: calls.append(args) or ''):
                self.assertEqual(adb.restore({'screen_brightness_mode': '1', 'screen_brightness': '162'}, {}), [])
            self.assertEqual(calls[0][-2:], ['screen_brightness', '162'])
            self.assertEqual(calls[-1][-2:], ['screen_brightness_mode', '1'])



    def test_numeric_mpv_formatting_is_equivalent_but_nonfinite_rejected(self):
        lab = {'pid': 100, 'runId': '100:unique', 'phase': 'sample', 'serial': 1, 'mode': 'audio',
               'properties': {'video-sync': 'audio', 'hwdec-current': 'surfacetexture', 'vo': 'gpu-next',
                              'target-trc': 'pq', 'target-peak': '1000.000000', 'target-prim': 'bt.2020',
                              'gamma': '0.000000', 'pause': 'no'},
               'report': {'verified': True, 'source': {'kind': 'dolbyVisionP84'}, 'actual': {'strategy': 'baseLayerConvert'}}}
        state = {'lab': lab, 'labAgeSeconds': 1, 'playbackSerial': 1,
                 'playbackRunId': '100:unique', 'playbackPid': '100', 'labPid': '100'}
        self.assertIsNone(m.runtime_error(state, 'audio'))
        for key, values in [('gamma', ['nan', 'inf', '-inf', '0.001']), ('target-peak', ['nan', 'inf', 'auto', '500'])]:
            original = lab['properties'][key]
            for value in values:
                lab['properties'][key] = value
                self.assertEqual(m.runtime_error(state, 'audio'), 'runtime-property-mismatch:' + key)
            lab['properties'][key] = original


if __name__ == '__main__':
    unittest.main()
