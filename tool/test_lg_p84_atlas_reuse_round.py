"""Host transaction tests for the atlas-reuse round over real archived stages."""
import json
import copy
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import MagicMock, patch
from types import SimpleNamespace

sys.path.insert(0, str(Path(__file__).parent))
import lg_p84_atlas_reuse_round as m


class AtlasReuseRoundTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # One real harness execution provides the seed plus both stage
        # archives; every later assertion reuses those actual bytes.
        from test_lg_yuv_atlas_read_vo import AtlasReadVoTest
        cls.harness = AtlasReadVoTest()
        cls.harness.setUpClass()

    @classmethod
    def tearDownClass(cls):
        cls.harness.tearDownClass()

    def archives(self):
        out = Path(tempfile.mkdtemp()) / 'reuse'
        out.mkdir(parents=True)
        proc = subprocess.run([str(self.harness.exe), 'reuse', str(out)],
                              capture_output=True, text=True, check=True)
        pid = next(iter(out.glob('mks-yuv-atlas-*.json'))).name.split('-')[3]
        return out, pid, proc.stdout

    def fixture(self):
        out, pid, events = self.archives()
        files = {m.REMOTE + path.name: path.read_bytes() for path in out.iterdir() if path.is_file()}
        manifests = sorted(p for p in out.glob('mks-uv-atlas-read-*.json')
                           if not p.name.endswith('-material.json'))
        stage1 = json.loads(manifests[0].read_text())
        nonce = '0123456789abcdef0123456789abcdef'
        promotion = {'nonce': nonce, 'cache_id': '77', 'cache_generation': '2',
                     'renderer_id': '2', 'renderer_generation': '999',
                     'signature': stage1['signature'],
                     'seed_capture_id': str(stage1['seed_capture_id']),
                     'seed_pts': '35.035000000', 't2_pts': '600.032766667',
                     'stage': '1', 'ordinal': '1'}
        runner = [{'runId': f'{pid}:unique', 'ordinal': 1, 'pid': int(pid), 'nonce': nonce,
                   'status': 'awaiting-host-ack', 'promotion': promotion,
                   'owner': {'sourcePath': '/source.mp4', 'generation': 7}}]
        return out, pid, events, files, promotion, runner, nonce

    def wrapped(self, events, pid):
        lines = []
        for number, line in enumerate(events.splitlines()):
            if not line.strip():
                continue
            lines.append(f'10-30 01:00:00.{number:02d}0 {pid} {pid} I flutter : {line}')
        return lines

    def setup_run(self, directory, scenario='complete', runner_rows=None):
        from test_lg_p84_capture_round import CaptureRoundTests
        adb, args = CaptureRoundTests().setup_run(directory)
        out, pid, events, files, promotion, runner, nonce = self.fixture()
        runner = runner_rows if runner_rows is not None else runner
        adb.properties.return_value = {key: 'old' for key in m.controls(35.035, 600.032766667, nonce)}
        args.first = 35.035
        args.second = 600.032766667
        args.nonce = nonce
        root = Path(args.output)
        state = {'logcatAlive': True}
        from test_lg_p84_quality_round import quality as quality_line
        pid_iter = iter(['111', None])
        adb.lab_pid.side_effect = lambda: next(pid_iter, pid)
        capture = MagicMock()
        capture.state.side_effect = lambda: dict(state)
        base_call = adb.call.side_effect
        ack_value = {'v': ''}

        def call(argv):
            if argv[:2] == ['shell', 'setprop'] and argv[2] == m.ACK:
                ack_value['v'] = argv[3]
                return ''
            if argv[:2] == ['shell', 'getprop']:
                if argv[2] == m.ACK:
                    if scenario == 'ack-readback' and ack_value['v']:
                        return 'stale'
                    return ack_value['v']
                return m.controls(args.first, args.second, nonce).get(argv[2], '')
            if argv[:3] == ['shell', 'am', 'start']:
                if scenario == 'cancel':
                    raise KeyboardInterrupt()
                # Real order: the lab seeks to the second PTS between the
                # native ACK receipt and the second armed transaction.
                wrapped_lines = self.wrapped(events, pid)
                split = next(i for i, item in enumerate(wrapped_lines)
                             if 'event=ack-accepted' in item)
                after_ack, after_native_ack = wrapped_lines[:split+1], wrapped_lines[split+1:]
                lines = [quality_line('seek-started', pid=pid, ordinal=1,
                                      run=f'{pid}:unique', pts=args.first)]
                lines += [item for item in after_ack]
                lines += [quality_line('ready-for-observation', pid=pid, ordinal=1,
                                       run=f'{pid}:unique', pts=args.first),
                          quality_line('seek-started', pid=pid, ordinal=2,
                                       run=f'{pid}:unique', pts=args.second)]
                lines += after_native_ack
                lines += [quality_line('ready-for-observation', pid=pid, ordinal=2,
                                       run=f'{pid}:unique', pts=args.second)]
                if scenario == 'native-terminal':
                    lines.append(f'10-30 01:00:09.90 {pid} {pid} I flutter : '
                                 'MKS-UV-ATLAS-READ event=capture-failed id=9 ordinal=1 '
                                 'cache_id=77 reason=lost-owner reject_reason=5 fallback_original=1')
                if scenario == 'promote-before-seek':
                    lines = [item for item in lines if 'P84_QUALITY' not in item]
                (root/'flutter-logcat.txt').write_text('\n'.join(lines))
            if argv[:2] == ['exec-out', 'cat']:
                # Path-sensitive stub: the runner file is the atlas-reuse one;
                # any other cat request must fail the round.
                if m.REMOTE+f'p84-atlas-reuse-{pid}.ndjson' in argv:
                    return '\n'.join(json.dumps(row) for row in runner)+'\n'
                raise RuntimeError('unexpected-cat:'+argv[-1])
            return base_call(argv)
        adb.call.side_effect = call

        def read(path, maximum):
            data = files.get(path)
            if data is None:
                raise RuntimeError('missing-payload:'+path)
            if scenario == 'missing-payload' and path.endswith('.seed-atlas.bin'):
                raise RuntimeError('missing-stage-payload')
            return data
        adb.read_file.side_effect = read
        return adb, args, pid, capture

    def test_controls_explicit_reuse_distinct_pts_and_clean_ack(self):
        controls = m.controls(35.035, 600.032766667, 'a'*32)
        self.assertEqual(controls[m.REUSE], '1')
        self.assertEqual(controls[m.PTS2], '600.032766667')
        self.assertEqual(controls[m.NONCE], 'a'*32)
        self.assertEqual(controls[m.ACK], '')
        self.assertEqual(controls[m.capture_host.ATLAS_PROPERTY], '1')
        self.assertEqual(controls['debug.mks.yuv_compare'], '1')
        self.assertEqual(controls['debug.mks.yuv_fusion'], '1')
        for key in (m.capture_host.REPEAT_PROPERTY, m.capture_host.TAP_PROPERTY,
                    m.capture_host.INVARIANT_PROPERTY, m.capture_host.ORACLE_PROPERTY,
                    m.capture_host.PROBE_PROPERTY, m.capture_host.SINGLE_PROPERTY,
                    m.capture_host.QUAD_PROPERTY, m.thermal.INPUT_FBO_PROPERTY,
                    'debug.mks.gpu_timing', 'debug.mks.yuv_fail_gl'):
            self.assertEqual(controls[key], '0', key)
        with self.assertRaises(ValueError):
            m.controls(35.035, 35.035, 'a'*32)
        with self.assertRaises(ValueError):
            m.controls(35.035, 600.032766667, 'ZZ')

    def test_read_rows_and_handshake_identity(self):
        pid = '123'
        nonce = '0123456789abcdef0123456789abcdef'
        good = (f'10-30 01:00:00.000 {pid} {pid} I flutter : MKS-UV-ATLAS-READ '
                'event=promoted-ready stage=1 ordinal=1 nonce=' + nonce +
                ' cache_id=77 cache_generation=2 renderer_id=2 renderer_generation=999 '
                'signature=' + 'b'*64 + ' seed_capture_id=5 seed_pts=35.035000000 '
                't2_pts=600.032766667')
        rows = m.read_rows([good], pid)
        receipt = m.handshake(rows[0][2], nonce, 35.035, 600.032766667)
        self.assertEqual(receipt['cache_id'], '77')
        for change in ({'nonce': 'f'*32}, {'stage': '2'}, {'signature': 'z'*64},
                       {'cache_id': '0'}, {'seed_pts': '35.040000000'},
                       {'t2_pts': '600.040000000'}):
            bad = good.replace(*next(iter(change.items()))).__str__()
            key, value = next(iter(change.items()))
            bad = good.replace(re.search(key+r'=[^\s]+', good).group(0), f'{key}={value}')
            with self.assertRaises(RuntimeError):
                m.handshake(m.read_rows([bad], pid)[0][2], nonce, 35.035, 600.032766667)
        failed = (f'10-30 01:00:00.000 {pid} {pid} I flutter : MKS-UV-ATLAS-READ '
                  'event=capture-failed id=1 ordinal=1 cache_id=77 reason=x reject_reason=5 fallback_original=1')
        with self.assertRaises(m.capture_host.NativeCaptureFailure):
            m.read_rows([failed], pid)
        unknown = (f'10-30 01:00:00.000 {pid} {pid} I flutter : MKS-UV-ATLAS-READ '
                   'event=mystery id=1')
        with self.assertRaisesRegex(RuntimeError, 'unknown-atlas-read-event'):
            m.read_rows([unknown], pid)

    def test_full_round_with_real_archives_pair_and_restoration(self):
        for scenario in ('complete', 'native-terminal', 'promote-before-seek',
                         'missing-payload', 'cancel', 'ack-readback'):
            with self.subTest(scenario=scenario), tempfile.TemporaryDirectory() as directory:
                adb, args, pid, capture = self.setup_run(directory, scenario)
                root = Path(args.output)
                pids = iter(['111', None])
                adb.lab_pid.side_effect = lambda: next(pids, pid)
                with patch.object(m, 'AtlasAdb', return_value=adb), \
                        patch.object(m.thermal, 'LogCapture', return_value=capture):
                    result = m.run(args)
                self.assertTrue(result['hdrLabStopped'])
                capture.close.assert_called_once()
                adb.restore.assert_called_once()
                self.assertIsNone(adb.deadline)
                self.assertEqual(adb.restore.call_args.args[1][m.REUSE], 'old')
                self.assertEqual(adb.restore.call_args.args[1][m.ACK], 'old')
                if scenario == 'complete':
                    self.assertEqual(result['status'], 'completed-atlas-reuse', result)
                    self.assertTrue(result['pair']['cross_pts_reuse_validated'])
                    self.assertFalse(result['pair']['yuv_equality_measured'])
                    self.assertEqual(result['stage1']['ordinal'], 1)
                    self.assertEqual(result['stage2']['ordinal'], 2)
                    self.assertEqual(result['stage1']['signature'], result['stage2']['signature'])
                elif scenario == 'ack-readback':
                    self.assertIn('ack-readback-mismatch', result.get('reason', ''), result)
                elif scenario == 'native-terminal':
                    self.assertIn('native-capture-failed', result.get('reason', ''), result)
                    self.assertIn('nativeFailure', result)
                elif scenario == 'promote-before-seek':
                    self.assertIn('promotion-before-first-seek', result.get('reason', ''), result)
                elif scenario == 'missing-payload':
                    self.assertNotEqual(result['status'], 'completed-atlas-reuse', result)
                self.assertEqual(result.get('quality_pass'), False)

    def test_runner_rows_missing_or_stale_promotion_fail_before_ack(self):
        with tempfile.TemporaryDirectory() as directory:
            adb, args, pid, capture = self.setup_run(directory, runner_rows=[])
            with patch.object(m, 'AtlasAdb', return_value=adb), \
                    patch.object(m.thermal, 'LogCapture', return_value=capture):
                result = m.run(args)
            self.assertIn('lab-runner-rows-missing', result.get('reason', ''), result)
            self.assertNotEqual(result['status'], 'completed-atlas-reuse')

    def test_cli_opt_in_distinct_pts_nonce_and_exit_codes(self):
        common = ['tool', '--serial', 's', '--output', '/unused', '--first', '35.035',
                  '--second', '600.032766667', '--source-receipt', '/receipt',
                  '--expected-apk-sha256', 'a'*64, '--expected-panel-thermal-status', '0']
        with patch.object(sys, 'argv', common), patch.object(m, 'AtlasAdb') as adb, \
                self.assertRaises(SystemExit):
            m.main()
        adb.assert_not_called()
        with patch.object(sys, 'argv', common+['--first', '35.035', '--second', '35.035',
                                               '--atlas-reuse']), self.assertRaises(SystemExit):
            m.main()
        with patch.object(sys, 'argv', common + ['--nonce', 'XYZ', '--atlas-reuse']), \
                self.assertRaises(SystemExit):
            m.main()
        for status, pair, expected in (('completed-atlas-reuse', {'cross_pts_reuse_validated': True}, 0),
                                       ('completed-atlas-reuse', {'cross_pts_reuse_validated': False}, 2),
                                       ('failed', {'cross_pts_reuse_validated': True}, 2)):
            result = {'status': status, 'pair': pair, 'restorationVerified': True,
                      'quality_pass': False}
            with patch.object(sys, 'argv', common+['--atlas-reuse']), \
                    patch.object(m, 'run', return_value=result), patch('builtins.print'):
                self.assertEqual(m.main(), expected)


if __name__ == '__main__':
    unittest.main()
