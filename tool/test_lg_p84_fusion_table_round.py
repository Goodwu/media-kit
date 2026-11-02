"""Unit tests for the production fusion-table round tool."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import MagicMock, patch
from types import SimpleNamespace

sys.path.insert(0, str(Path(__file__).parent))
import lg_p84_fusion_table_round as m


def line(event, pid='123', **extra):
    fields = {'event': event}
    fields.update(extra)
    return f'10-31 23:00:00.001 {pid} {pid} I flutter : MKS-FUSION-TABLE ' + \
        ' '.join(f'{k}={v}' for k, v in fields.items())


class FusionTableTests(unittest.TestCase):
    def test_controls_enable_table_and_keep_diagnostic_defaults(self):
        controls = m.table_controls(35.035)
        self.assertEqual(controls[m.TABLE_PROPERTY], '1')
        self.assertEqual(controls['debug.mks.yuv_fusion'], '1')
        self.assertEqual(controls['debug.mks.yuv_compare'], '0')
        self.assertEqual(controls[m.capture_host.ATLAS_PROPERTY], '0')
        self.assertEqual(controls[m.capture_host.ATLAS_REUSE_PROPERTY], '0')
        for key in (m.capture_host.REPEAT_PROPERTY, m.capture_host.TAP_PROPERTY,
                    m.capture_host.ORACLE_PROPERTY, 'debug.mks.yuv_fail_gl'):
            self.assertEqual(controls[key], '0', key)

    def test_table_rows_events_and_terminal_detection(self):
        rows = m.table_rows([line('ready', cache_id='5'), line('table-invalidated')], '123')
        self.assertEqual([r['event'] for _, r in rows], ['ready', 'table-invalidated'])
        self.assertEqual(m.TABLE_EVENTS[:4][1], 'seed-retry')
        with self.assertRaisesRegex(RuntimeError, 'malformed'):
            m.table_rows(['10-31 23:00:00.001 123 123 I flutter : MKS-FUSION-TABLE cache_id=1'], '123')

    def test_full_round_ready_and_stable_then_restores(self):
        with tempfile.TemporaryDirectory() as directory:
            from test_lg_p84_capture_round import CaptureRoundTests
            adb, args = CaptureRoundTests().setup_run(directory)
            adb.properties.return_value = {key: 'old' for key in m.table_controls(args.pts)}
            args.observe = 0
            args.timeout = 30
            root = Path(args.output)
            state = {'logcatAlive': True}
            pids = iter(['111', None])
            adb.lab_pid.side_effect = lambda: next(pids, '123')
            capture = MagicMock()
            capture.state.side_effect = lambda: dict(state)
            base_call = adb.call.side_effect

            def call(argv):
                if argv[:2] == ['shell', 'getprop']:
                    return m.table_controls(args.pts).get(argv[2], '')
                if argv[:3] == ['shell', 'am', 'start']:
                    (root/'flutter-logcat.txt').write_text('\n'.join([
                        line('ready', cache_id='42', failures='0')]))
                return base_call(argv)
            adb.call.side_effect = call
            with patch.object(m, 'AtlasAdb', return_value=adb), \
                    patch.object(m.thermal, 'LogCapture', return_value=capture):
                result = m.run(args)
            self.assertEqual(result['status'], 'completed-fusion-table-check', result)
            self.assertEqual(result['readyReceipt']['cache_id'], '42')
            self.assertTrue(result['hdrLabStopped'])
            self.assertIsNone(result.get('reason'))
            adb.restore.assert_called_once()
            self.assertEqual(adb.restore.call_args.args[1][m.TABLE_PROPERTY], 'old')

    def test_round_fails_when_table_invalidated_during_observation(self):
        with tempfile.TemporaryDirectory() as directory:
            from test_lg_p84_capture_round import CaptureRoundTests
            adb, args = CaptureRoundTests().setup_run(directory)
            adb.properties.return_value = {key: 'old' for key in m.table_controls(args.pts)}
            args.observe = 0
            args.timeout = 30
            root = Path(args.output)
            pids = iter(['111', None])
            adb.lab_pid.side_effect = lambda: next(pids, '123')
            capture = MagicMock()
            capture.state.side_effect = lambda: {'logcatAlive': True}
            base_call = adb.call.side_effect

            def call(argv):
                if argv[:2] == ['shell', 'getprop']:
                    return m.table_controls(args.pts).get(argv[2], '')
                if argv[:3] == ['shell', 'am', 'start']:
                    (root/'flutter-logcat.txt').write_text('\n'.join([
                        line('ready', cache_id='42'), line('table-invalidated')]))
                return base_call(argv)
            adb.call.side_effect = call
            with patch.object(m, 'AtlasAdb', return_value=adb), \
                    patch.object(m.thermal, 'LogCapture', return_value=capture):
                result = m.run(args)
            self.assertNotEqual(result['status'], 'completed-fusion-table-check')
            self.assertTrue(result.get('reason', '').startswith('fusion-table-'))
            self.assertTrue(result.get('restorationVerified'))


    def test_seed_retry_is_transient_in_wait_loop(self):
        # wait loop must tolerate seed-retry while waiting for ready
        rows = m.table_rows([line('seed-retry'), line('ready', cache_id='9')], '123')
        self.assertEqual([r['event'] for _, r in rows], ['seed-retry', 'ready'])

    def test_controls_property_combination_reaches_ready_path(self):
        # P0-3 regression: production mode must not need any compare
        # transaction; caps are driven by the table property alone.
        controls = m.table_controls(35.035)
        self.assertEqual(controls['debug.mks.yuv_compare'], '0')
        self.assertEqual(controls['debug.mks.yuv_compare_pts'], '')
        self.assertEqual(controls[m.TABLE_PROPERTY], '1')
        self.assertNotIn('', [controls['debug.mks.quality_pts']])


if __name__ == '__main__':
    unittest.main()
