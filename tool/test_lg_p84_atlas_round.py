import json
import copy
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import MagicMock, patch
from types import SimpleNamespace

sys.path.insert(0, str(Path(__file__).parent))
import lg_p84_atlas_round as m


def line(event, pid='123', **changes):
    diagnostic = event == 'capture-diagnostic-invalid'
    fields = {'event': event, 'id': '1', 'generation': '2', 'source_pts': '35.035000000'}
    fields.update({'android': '1', 'lib': '1'} if event == 'armed' else {
        'file': m.REMOTE+f'mks-yuv-atlas-{pid}-1'+('.diagnostic-invalid' if diagnostic else '')+'.json',
        'comparison_pass': 'refused' if diagnostic else 'unknown'})
    fields.update(changes)
    return f'10-30 01:00:00.001 {pid} {pid} I flutter : MKS-YUV-ATLAS '+' '.join(f'{k}={v}' for k,v in fields.items())


class AtlasTests(unittest.TestCase):
    def fixture(self, diagnostic=False):
        from test_analyze_lg_yuv_capture import AtlasCaptureTest, bits
        fixture = AtlasCaptureTest()
        fixture.setUp()
        self.addCleanup(fixture.doCleanups)
        if diagnostic:
            fixture.payload['atlas_a'][0] = bits(.875)
            fixture.mark_difference(2)
        manifest = copy.deepcopy(fixture.m)
        event = {'event': 'capture-diagnostic-invalid' if diagnostic else 'capture-complete', 'id': '1',
                 'generation': '2', 'source_pts': '35.035000000',
                 'file': m.REMOTE+'mks-yuv-atlas-123-1'+('.diagnostic-invalid' if diagnostic else '')+'.json',
                 'comparison_pass': 'refused' if diagnostic else 'unknown'}
        files = {event['file']: json.dumps(manifest).encode()}
        files.update({m.REMOTE+name: (fixture.root/name).read_bytes() for name in manifest['files'].values()})
        return event, manifest, files

    def test_controls_opt_in_only_atlas_and_disable_legacy_experiments(self):
        controls = m.controls(35.035)
        self.assertEqual(controls[m.ATLAS_PROPERTY], '1')
        self.assertEqual(controls['debug.mks.yuv_compare'], '1')
        self.assertEqual(controls['debug.mks.yuv_fusion'], '1')
        for key in (m.capture_host.REPEAT_PROPERTY, m.capture_host.TAP_PROPERTY,
                    m.capture_host.INVARIANT_PROPERTY, m.capture_host.ORACLE_PROPERTY,
                    m.capture_host.ORACLE_MODE_PROPERTY, m.capture_host.PROBE_PROPERTY,
                    m.capture_host.SINGLE_PROPERTY, m.capture_host.QUAD_PROPERTY,
                    m.capture_host.QUAD_REVERSE_PROPERTY, m.thermal.INPUT_FBO_PROPERTY,
                    'debug.mks.yuv_fail_gl', 'debug.mks.yuv_fail_commit', 'debug.mks.gpu_timing'):
            self.assertEqual(controls[key], '0', key)

    def test_atlas_property_is_in_original_snapshot(self):
        adb = m.AtlasAdb.__new__(m.AtlasAdb)
        adb.call = MagicMock(return_value='old\n')
        props = adb.properties()
        self.assertEqual(props[m.ATLAS_PROPERTY], 'old')
        self.assertTrue(set(m.controls(35.035)).issubset(props))

    def test_binary_transfer_exact_size_type_and_bounded_deadline(self):
        with tempfile.TemporaryDirectory() as directory:
            adb = m.AtlasAdb.__new__(m.AtlasAdb)
            adb.prefix = ['adb', '-s', 'serial']
            adb.receipts = Path(directory)/'commands.ndjson'
            adb.shell = MagicMock(return_value='8\n')
            adb.deadline = time.monotonic()+30
            result = subprocess.CompletedProcess([], 0, b'12345678', b'')
            with patch.object(m.subprocess, 'run', return_value=result) as run:
                self.assertEqual(adb.read_file('/safe.bin', 8), b'12345678')
                self.assertLessEqual(run.call_args.kwargs['timeout'], 30)
                result.stdout = b'1234'
                with self.assertRaisesRegex(RuntimeError, 'incomplete'):
                    adb.read_file('/safe.bin', 8)
                for size in ('0', '-1', '9', '8\n8', ''):
                    adb.shell.return_value = size
                    with self.assertRaisesRegex(RuntimeError, 'size-or-type'):
                        adb.read_file('/safe.bin', 8)
            adb.deadline = time.monotonic()-1
            with self.assertRaisesRegex(RuntimeError, 'timeout'):
                adb.read_file('/safe.bin', 8)
            self.assertEqual(len(adb.receipts.read_text().splitlines()), 2)

    def test_expired_deadline_prevents_device_call(self):
        adb = m.AtlasAdb.__new__(m.AtlasAdb)
        adb.deadline = time.monotonic()-1
        with patch.object(m.capture_host.CaptureAdb, 'call') as base:
            with self.assertRaisesRegex(RuntimeError, 'atlas-round-timeout'):
                adb.call(['shell', 'date'])
            base.assert_not_called()

    def test_transaction_fresh_pid_seek_identity_and_unique_endpoint(self):
        valid = ['seek', line('armed'), line('capture-complete')]
        self.assertEqual(m.completion(valid, '123', 0, 35.035)['id'], '1')
        self.assertIsNone(m.completion(valid, '456', 0, 35.035))
        self.assertIsNone(m.completion(['seek', line('armed')], '123', 0, 35.035))
        bads = [valid[1:], ['seek', line('capture-complete')], valid+[line('capture-complete')],
                ['seek', line('armed', lib='0'), line('capture-complete')],
                ['seek', line('armed'), line('capture-complete', generation='3')],
                ['seek', line('armed'), line('capture-complete', source_pts='35.036')],
                ['seek', line('armed'), line('capture-complete', source_pts='nan')],
                ['seek', line('armed'), line('capture-complete', file=m.REMOTE+'mks-yuv-atlas-456-1.json')],
                ['seek', line('armed'), line('capture-complete', comparison_pass='pass')],
                ['seek', line('armed')+' id=2', line('capture-complete')],
                ['seek', line('unknown')], ['seek', line('armed').replace('MKS-YUV-ATLAS ', 'MKS-YUV-ATLAS-LIB ')]]
        for rows in bads:
            with self.subTest(rows=rows), self.assertRaises(RuntimeError):
                m.completion(rows, '123', 0, 35.035)
        with self.assertRaises(m.AtlasDiagnosticEvent):
            m.completion(['seek', line('armed'), line('capture-diagnostic-invalid')], '123', 0, 35.035)
        with self.assertRaisesRegex(RuntimeError, 'multiple'):
            m.completion(valid+[line('capture-diagnostic-invalid')], '123', 0, 35.035)

    def test_terminal_errors_take_priority_even_after_complete(self):
        for event in ('capture-failed', 'config-invalid', 'cleanup-deferred'):
            rows = ['seek', line('armed'), line('capture-complete'), line(event, reason='owner-lost', requires_force_stop='1')]
            with self.subTest(event=event), self.assertRaises(m.capture_host.NativeCaptureFailure) as rejected:
                m.completion(rows, '123', 0, 35.035)
            self.assertEqual(rejected.exception.fields['reason'], 'owner-lost')
            self.assertEqual(rejected.exception.fields['requires_force_stop'], '1')
        legacy = line('capture-failed', reason='lost-frame').replace('MKS-YUV-ATLAS ', 'MKS-YUV-COMPARE ')
        with self.assertRaises(m.capture_host.NativeCaptureFailure):
            m.completion(['seek', line('armed'), line('capture-complete'), legacy], '123', 0, 35.035)
        lib = ('10-30 01:00:00.001 123 123 I flutter : MKS-YUV-ATLAS-LIB '
               'event=rejected reason=source-abi stage=atlas_a')
        for rows in ([lib], ['seek', line('armed'), line('capture-complete'), lib]):
            with self.assertRaises(m.capture_host.NativeCaptureFailure) as rejected:
                m.completion(rows, '123', 0, 35.035)
            self.assertEqual(rejected.exception.fields['reason'], 'source-abi')
            self.assertEqual(rejected.exception.fields['stage'], 'atlas_a')
        for bad in (lib.replace('event=rejected', 'event=unknown'), lib.replace('MKS-YUV-ATLAS-LIB ', 'MKS-YUV-ATLAS ')):
            with self.assertRaisesRegex(RuntimeError, 'unknown-atlas-event'):
                m.completion([bad], '123', -1, 35.035)

    def test_manifest_exact_event_request_fullscreen_and_file_identity(self):
        event, manifest, _ = self.fixture()
        self.assertEqual(set(m.validate_manifest(manifest, event, '123', 35.035)), set(m.SUFFIXES))
        mutations = {'pid': 456, 'capture_id': 2, 'generation': 3, 'source_pts': 35.035003,
                     'current_pts': 35.036, 'target_pts': 35.036, 'width': True, 'pixels': 1,
                     'rgba_words': 7, 'atlas_words': 5, 'framebuffer': [7,8,7],
                     'program_tokens': ['11','22','12'], 'draw_epoch_after': ['0','1','0'],
                     'atlas_complete': False, 'android_swap_succeeded': False}
        for key, value in mutations.items():
            changed = copy.deepcopy(manifest);changed[key] = value
            with self.subTest(key=key), self.assertRaises((RuntimeError, m.analyzer.InvalidCapture)):
                m.validate_manifest(changed, event, '123', 35.035)
        for key in manifest['files']:
            changed = copy.deepcopy(manifest)
            changed['files'][key] = changed['files'][key].replace('-123-', '-456-')
            with self.subTest(file=key), self.assertRaisesRegex(RuntimeError, 'file-identity'):
                m.validate_manifest(changed, event, '123', 35.035)
        changed = copy.deepcopy(manifest)
        changed['width'] = 4096;changed['height'] = 4096;changed['pixels'] = 4096*4096
        with self.assertRaisesRegex(m.analyzer.InvalidCapture, 'budget'):
            m.validate_manifest(changed, event, '123', 35.035)

    def test_collect_all_ten_files_immutable_and_analyze_actual_bytes(self):
        for diagnostic in (False, True):
            event, manifest, files = self.fixture(diagnostic)
            with self.subTest(diagnostic=diagnostic), tempfile.TemporaryDirectory() as directory:
                adb = MagicMock();adb.read_file.side_effect = lambda path, maximum: files[path]
                result = m.collect(adb, event, '123', 35.035, Path(directory)/'capture', MagicMock())
                self.assertEqual(result['status'], 'diagnostic-invalid' if diagnostic else 'captured-floats-bit-equal')
                self.assertFalse(result['quality_pass']);self.assertFalse(result['production_equivalence_established'])
                self.assertEqual(adb.read_file.call_count, 22)
                collection = json.loads((Path(directory)/'capture'/'collection.json').read_text())
                self.assertEqual(len(collection['files']), 10)
                for key, receipt in collection['files'].items():
                    self.assertEqual(receipt['bytes'], len(files[m.REMOTE+manifest['files'][key]]))

    def test_payload_truncation_mutation_coverage_and_nonfinite_cannot_pass(self):
        import struct
        for scenario in ('truncated', 'changed-second-read', 'manifest-changed', 'coverage', 'nonfinite', 'half', 'source'):
            with self.subTest(scenario=scenario), tempfile.TemporaryDirectory() as directory:
                event, manifest, files = self.fixture()
                key = 'atlas' if scenario == 'coverage' else 'a0_before'
                name = m.REMOTE+manifest['files'][key]
                if scenario == 'truncated':files[name] = files[name][:-4]
                if scenario == 'coverage':files[name] = files[name][:8]+struct.pack('<I', 0)+files[name][12:]
                if scenario in ('nonfinite', 'half'):
                    files[name] = struct.pack('<f', float('nan') if scenario == 'nonfinite' else .1)+files[name][4:]
                if scenario == 'source':
                    source = m.REMOTE+manifest['files']['atlas_fragment']
                    files[source] += b'// unaccounted source change\n'
                count = {}
                def read(path, maximum):
                    count[path] = count.get(path, 0)+1
                    data = files[path]
                    if count[path] == 2 and ((scenario == 'changed-second-read' and path == name) or
                                            (scenario == 'manifest-changed' and path == event['file'])):
                        return data[:-1]+bytes([data[-1]^1])
                    return data
                adb = MagicMock();adb.read_file.side_effect = read
                target = Path(directory)/'capture'
                with self.assertRaises((RuntimeError, m.analyzer.InvalidCapture)):
                    m.collect(adb, event, '123', 35.035, target, MagicMock())
                self.assertTrue((target/Path(event['file']).name).is_file())
                if scenario in ('coverage', 'nonfinite', 'half', 'source'):
                    self.assertTrue((target/'collection.json').is_file())
                    self.assertEqual(json.loads((target/'analysis.json').read_text())['status'], 'invalid-capture')

    def test_analysis_worker_is_terminated_on_cancel_or_guard_failure(self):
        for failure in (KeyboardInterrupt(), RuntimeError('thermal-cap')):
            with self.subTest(failure=failure), tempfile.TemporaryDirectory() as directory:
                proc = MagicMock();proc.poll.side_effect = [None, None]
                with patch.object(m.subprocess, 'Popen', return_value=proc):
                    with self.assertRaises(type(failure)):
                        m.analyze_with_guard(Path(directory)/'manifest.json', Path(directory), MagicMock(side_effect=failure))
                proc.terminate.assert_called_once();proc.wait.assert_called_once()

    def setup_run(self, directory):
        from test_lg_p84_capture_round import CaptureRoundTests
        adb, args = CaptureRoundTests().setup_run(directory)
        adb.properties.return_value = {key: 'old' for key in m.controls(args.pts)}
        return adb, args

    def test_full_round_actual_analysis_live_heartbeat_failures_and_restoration(self):
        for scenario in ('complete', 'diagnostic', 'cancel', 'thermal', 'resume', 'stale', 'logcat', 'native-terminal',
                         'late-terminal', 'missing-payload', 'restore-failure'):
            with self.subTest(scenario=scenario), tempfile.TemporaryDirectory() as directory:
                adb, args = self.setup_run(directory)
                diagnostic = scenario == 'diagnostic'
                event, manifest, files = self.fixture(diagnostic)
                sequence = 0
                root = Path(args.output)
                state = {'logcatAlive': True}
                from test_lg_p84_quality_round import QualityTests, quality as quality_line
                row = QualityTests().persistent();row['owner']['sourcePath'] = args.source
                row['properties']['path'] = args.source
                pids = iter(['111', None]);adb.lab_pid.side_effect = lambda: next(pids, '123')
                capture = MagicMock();capture.state.side_effect = lambda: dict(state)
                original_call = adb.call.side_effect
                def call(argv):
                    nonlocal sequence
                    if argv[:2] == ['shell', 'getprop']:return m.controls(args.pts)[argv[2]]
                    if argv[:3] == ['shell', 'am', 'start']:
                        if scenario == 'cancel':raise KeyboardInterrupt()
                        lines = [quality_line('seek-started'), line('armed'), line(event['event'])]
                        lines += [quality_line('invalidated')] if diagnostic else [quality_line('ready-for-observation')]
                        if scenario == 'native-terminal':lines.append(line('capture-failed', reason='lost-owner'))
                        (root/'flutter-logcat.txt').write_text('\n'.join(lines))
                    if argv[:2] == ['exec-out', 'cat']:
                        sequence += scenario != 'stale'
                        return json.dumps({**row, 'heartbeat': sequence or 1})+'\n'
                    return original_call(argv)
                adb.call.side_effect = call
                def read(path, maximum):
                    if scenario == 'missing-payload' and path.endswith('.atlas.bin'):
                        raise RuntimeError('missing-atlas-payload')
                    return files[path]
                adb.read_file.side_effect = read
                if scenario == 'restore-failure':adb.restore.return_value = ['setprop-failed']
                real_collect = m.collect
                def collect(*values):
                    result = real_collect(*values)
                    if scenario == 'thermal':adb.snapshot.return_value['raw']['gpu_thermal_pwrlevel'] = '4'
                    if scenario == 'resume':row['properties']['pause'] = 'no'
                    if scenario == 'logcat':state['logcatAlive'] = False
                    if scenario == 'late-terminal':
                        with (root/'flutter-logcat.txt').open('a') as out:out.write('\n'+line('capture-failed', reason='late-owner-loss'))
                    return result
                original_fresh = m.quality.fresh_heartbeat
                def fresh(load, previous, timeout=5):return original_fresh(load, previous, timeout=.01 if scenario == 'stale' else timeout)
                with patch.object(m, 'AtlasAdb', return_value=adb), patch.object(m.thermal, 'LogCapture', return_value=capture), \
                        patch.object(m, 'collect', side_effect=collect), patch.object(m.quality, 'fresh_heartbeat', side_effect=fresh):
                    result = m.run(args)
                self.assertTrue(result['hdrLabStopped']);capture.close.assert_called_once()
                adb.restore.assert_called_once();self.assertIsNone(adb.deadline)
                self.assertEqual(adb.restore.call_args.args[1][m.ATLAS_PROPERTY], 'old')
                if scenario == 'complete':
                    self.assertEqual(result['status'], 'completed-atlas-diagnostic', result)
                    self.assertGreater(result['qualityAfter']['heartbeat'], result['postCollectionHeartbeatWatermark']+1)
                elif diagnostic:
                    self.assertEqual(result['status'], 'diagnostic-invalid', result)
                    self.assertTrue(result['diagnosticFilesCollected']);self.assertEqual(sequence, 0)
                else:
                    self.assertEqual(result['status'], 'restoration-failed' if scenario == 'restore-failure' else 'failed', result)
                self.assertEqual(result['restorationVerified'], scenario != 'restore-failure')
                self.assertFalse(result['quality_pass']);self.assertFalse(result['production_equivalence_established'])

    def test_wrong_property_readbacks_and_identity_fail_before_launch_restore(self):
        for scenario in ('atlas-readback', 'legacy-readback', 'missing-snapshot', 'APK', 'source', 'surviving', 'reused'):
            with self.subTest(scenario=scenario), tempfile.TemporaryDirectory() as directory:
                adb, args = self.setup_run(directory)
                if scenario == 'APK':adb.source_hash.return_value = {'sha256': 'b'*64}
                if scenario == 'source':adb.shell.return_value = '124'
                if scenario == 'missing-snapshot':adb.properties.return_value.pop(m.ATLAS_PROPERTY)
                pids = iter(['111', '111' if scenario == 'surviving' else None])
                adb.lab_pid.side_effect = lambda: next(pids, '111' if scenario == 'reused' else '123')
                original = adb.call.side_effect
                def call(argv):
                    if argv[:2] == ['shell', 'getprop']:
                        value = m.controls(args.pts)[argv[2]]
                        if scenario == 'atlas-readback' and argv[2] == m.ATLAS_PROPERTY:return '0'
                        if scenario == 'legacy-readback' and argv[2] == m.capture_host.PROBE_PROPERTY:return '1'
                        return value
                    return original(argv)
                adb.call.side_effect = call
                with patch.object(m, 'AtlasAdb', return_value=adb), patch.object(m.thermal, 'LogCapture'):
                    result = m.run(args)
                self.assertNotEqual(result['status'], 'completed-atlas-diagnostic')
                self.assertTrue(result['restorationVerified'])
                self.assertEqual(adb.restore.call_count, 0 if scenario in ('APK','source') else 1)
                starts = [call for call in adb.call.call_args_list if call.args[0][:3] == ['shell','am','start']]
                self.assertEqual(len(starts), int(scenario == 'reused'))

    def test_cli_explicit_opt_in_and_diagnostic_never_success(self):
        common = ['tool', '--serial', 's', '--output', '/unused', '--pts', '35.035', '--source-receipt', '/receipt',
                  '--expected-apk-sha256', 'a'*64, '--expected-panel-thermal-status', '0']
        with patch.object(sys, 'argv', common), patch.object(m, 'AtlasAdb') as adb, self.assertRaises(SystemExit):
            m.main()
        adb.assert_not_called()
        for status, analysis, expected in (('completed-atlas-diagnostic','captured-floats-bit-equal',0),
                                           ('diagnostic-invalid','captured-floats-bit-equal',2),
                                           ('completed-atlas-diagnostic','diagnostic-invalid',2)):
            result = {'status':status,'analysis':{'status':analysis},'restorationVerified':True,'quality_pass':False}
            with patch.object(sys, 'argv', common+['--atlas']), patch.object(m, 'run', return_value=result), patch('builtins.print'):
                self.assertEqual(m.main(), expected)


if __name__ == '__main__':
    unittest.main()
