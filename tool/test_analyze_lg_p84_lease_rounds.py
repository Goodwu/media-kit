import hashlib
import json
from pathlib import Path
import struct
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).parent))
import analyze_lg_p84_lease_rounds as m
import test_lg_p84_capture_round as fixtures


def write_json(path, data):
    path.write_text(json.dumps(data))


def update_receipt(directory):
    root = directory / 'capture'
    summary = json.loads((directory / 'summary.json').read_text())
    manifest_path = root / Path(summary['captureEvent']['file']).name
    manifest = json.loads(manifest_path.read_text())
    receipt = {'manifestSha256': hashlib.sha256(manifest_path.read_bytes()).hexdigest(), 'files': {}}
    for key, name in manifest['files'].items():
        data = (root / name).read_bytes()
        receipt['files'][key] = {'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()}
    write_json(root / 'collection.json', receipt)


def make_round(directory, mode, pid, capture_id):
    directory = Path(directory)
    root = directory / 'capture'
    root.mkdir(parents=True)
    event, manifest, files = fixtures.fixture(True, True)
    old = 'mks-yuv-compare-123-99'
    new = f'mks-yuv-compare-{pid}-{capture_id}'
    manifest.update(pid=pid, capture_id=capture_id)
    manifest['files'] = {key: name.replace(old, new) for key, name in manifest['files'].items()}
    event.update(id=str(capture_id), file=m.capture.REMOTE + new + '.json')
    for remote, data in files.items():
        name = Path(remote).name.replace(old, new)
        (root / name).write_bytes(json.dumps(manifest).encode() if remote.endswith('.json') else data)
    summary = {'schema': 1, 'status': 'completed-capture', 'restorationVerified': True,
        'captureStatusBeforeCleanup': 'completed-capture', 'hdrLabStopped': True,
        'serial': 's', 'pid': str(pid), 'requestedPTS': 35.035,
        'repeatRequested': True, 'sampleTapRequested': True, 'invariantBRequested': False,
        'oracleMode': None, 'oracleProbeRequested': False, 'singlePairRequested': False,
        'quadOrderRequested': False, 'quadReverse': None, 'requestedInputFbo': None,
        'expectedCaptureSchema': 3, 'captureEvent': event,
        'displayControls': {'brightness': 64, 'expectedBacklight': 64, 'expectedPanelThermalStatus': '0'},
        'apk': {'sha256': 'a'*64, 'bytes': 1234},
        'controls': m.capture.controls(35.035, True, True, lease_target=bool(mode)),
        'sourceReceipt': {'verified': True, 'serial': 's', 'deviceSource': '/source.mp4',
                          'deviceSha256': 'b'*64, 'hostSha256': 'b'*64,
                          'deviceBytes': 123, 'hostBytes': 123, 'returncode': 0}}
    write_json(directory / 'summary.json', summary)
    update_receipt(directory)
    return directory


def change_summary(directory, change):
    path = directory / 'summary.json'
    data = json.loads(path.read_text())
    change(data)
    write_json(path, data)


def change_manifest(directory, change):
    summary = json.loads((directory / 'summary.json').read_text())
    path = directory / 'capture' / Path(summary['captureEvent']['file']).name
    data = json.loads(path.read_text())
    change(data)
    write_json(path, data)
    update_receipt(directory)


def change_word(directory, key, offset, value, update=True):
    root = directory / 'capture'
    summary = json.loads((directory / 'summary.json').read_text())
    manifest = json.loads((root / Path(summary['captureEvent']['file']).name).read_text())
    path = root / manifest['files'][key]
    data = bytearray(path.read_bytes())
    struct.pack_into('<I', data, offset*4, value)
    path.write_bytes(data)
    if update:
        update_receipt(directory)


class LeaseRoundAnalysisTests(unittest.TestCase):
    def rounds(self, root, count=2):
        return [make_round(Path(root)/str(i), mode, 123+i, 99+i)
                for i, mode in enumerate((0, 1, 0)[:count])]

    def test_compares_same_branch_and_correct_repetition_offsets(self):
        with tempfile.TemporaryDirectory() as tmp:
            off, on = self.rounds(tmp)
            # B2 Y; A2 Android half RGB; A2 UV. Changes in first repetition
            # must not masquerade as B2 or A2 values.
            change_word(on, 'lib', 26+7, 0x3f800000)
            change_word(on, 'android', 1, 0x3f000000)
            change_word(on, 'lib', 26+20, 0x3e800000)
            change_word(on, 'lib', 1, 0x3e000000)
            result = m.analyze_rounds([off, on])
            self.assertEqual(result['status'], 'exploratory-cross-round-comparison')
            self.assertFalse(result['acceptance'])
            self.assertFalse(result['input_pixel_identity_proven'])
            self.assertTrue(result['shaderSourcesIdentical'])
            self.assertIsNone(result['off_anchor_A2_B2_stages_bit_equal'])
            pairs = result['off_vs_on']
            self.assertEqual(pairs['B2']['yuv']['bit_mismatches'], 1)
            self.assertEqual(pairs['A2']['half_rgb']['bit_mismatches'], 1)
            self.assertEqual(pairs['A2']['sample_uv']['bit_mismatches'], 1)
            self.assertEqual(pairs['B2']['pre_rgb']['bit_mismatches'], 0)
            self.assertEqual(pairs['A2']['yuv']['bit_mismatches'], 0)

    def test_A_B_A_anchor_reports_equality_and_drift_without_proving_input(self):
        with tempfile.TemporaryDirectory() as tmp:
            off, on, anchor = self.rounds(tmp, 3)
            result = m.analyze_rounds([off, on, anchor])
            self.assertTrue(result['off_anchor_A2_B2_stages_bit_equal'])
            self.assertFalse(result['input_pixel_identity_proven'])
            self.assertTrue(any('chronology is not independently verified' in text
                                for text in result['limitations']))
            change_word(anchor, 'lib', 26+7, 0x3f800000)
            result = m.analyze_rounds([off, on, anchor])
            self.assertFalse(result['off_anchor_A2_B2_stages_bit_equal'])
            self.assertEqual(result['off_vs_off_anchor']['B2']['yuv']['bit_mismatches'], 1)

    def test_restoration_failure_requires_explicit_exploration(self):
        with tempfile.TemporaryDirectory() as tmp:
            off, on = self.rounds(tmp)
            change_summary(on, lambda s: s.update(status='restoration-failed', restorationVerified=False,
                                                  restoreErrors=['screen-state-not-restored']))
            with self.assertRaisesRegex(ValueError, 'round-not-complete-and-restored'):
                m.analyze_rounds([off, on])
            result = m.analyze_rounds([off, on], allow_restore_failure=True)
            self.assertFalse(result['rounds'][1]['restorationVerified'])
            self.assertEqual(result['rounds'][1]['restoreErrors'], ['screen-state-not-restored'])
            self.assertFalse(result['acceptance'])
            change_summary(on, lambda s: s.update(status='failed'))
            with self.assertRaisesRegex(ValueError, 'round-not-complete-and-restored'):
                m.analyze_rounds([off, on], allow_restore_failure=True)

    def test_other_failures_cannot_hide_behind_restoration_failure(self):
        for key, value in (('reason', 'capture-round-timeout'), ('stopError', 'stop failed'),
                           ('captureCloseError', 'log failed'), ('restorationError', 'read failed'),
                           ('nativeFailure', {}), ('captureStatusBeforeCleanup', 'failed'), ('hdrLabStopped', False)):
            with self.subTest(key=key), tempfile.TemporaryDirectory() as tmp:
                off, on = self.rounds(tmp)
                change_summary(on, lambda s: s.update(status='restoration-failed', restorationVerified=False,
                                                      restoreErrors=['screen-state-not-restored'], **{key: value}))
                with self.assertRaises(ValueError):
                    m.analyze_rounds([off, on], allow_restore_failure=True)

    def test_legacy_restoration_failure_needs_post_collection_heartbeat(self):
        with tempfile.TemporaryDirectory() as tmp:
            off, on = self.rounds(tmp)
            def legacy(s):
                s.pop('captureStatusBeforeCleanup')
                s.update(status='restoration-failed', restorationVerified=False,
                         restoreErrors=['screen-state-not-restored'], postCollectionHeartbeatWatermark=10,
                         qualityBefore={'status': 'observation-heartbeat', 'pid': 124, 'heartbeat': 3, 'runId': 'x'},
                         qualityAfter={'status': 'observation-heartbeat', 'pid': 124, 'heartbeat': 12, 'runId': 'x'})
            change_summary(on, legacy)
            result = m.analyze_rounds([off, on], allow_restore_failure=True)
            self.assertEqual(result['rounds'][1]['captureCompletionScope'],
                             'legacy-post-collection-evidence-not-explicit-status')
            for field, value in (('pid', 999), ('runId', 'different'), ('heartbeat', 9)):
                with self.subTest(field=field):
                    original = json.loads((on/'summary.json').read_text())
                    change_summary(on, lambda s: s['qualityAfter'].update({field: value}))
                    with self.assertRaisesRegex(ValueError, 'legacy-round-missing-post-collection-evidence'):
                        m.analyze_rounds([off, on], allow_restore_failure=True)
                    write_json(on/'summary.json', original)
            change_summary(on, lambda s: s.pop('qualityAfter'))
            with self.assertRaisesRegex(ValueError, 'legacy-round-missing-post-collection-evidence'):
                m.analyze_rounds([off, on], allow_restore_failure=True)

    def test_legacy_success_scope_does_not_claim_heartbeat_check(self):
        with tempfile.TemporaryDirectory() as tmp:
            off, on = self.rounds(tmp)
            change_summary(on, lambda s: s.pop('captureStatusBeforeCleanup'))
            result = m.analyze_rounds([off, on])
            self.assertEqual(result['rounds'][1]['captureCompletionScope'], 'legacy-final-success-status')

    def test_anchor_name_does_not_claim_first_repetition(self):
        with tempfile.TemporaryDirectory() as tmp:
            off, on, anchor = self.rounds(tmp, 3)
            change_word(anchor, 'lib', 1, 0x3f800000)
            result = m.analyze_rounds([off, on, anchor])
            self.assertTrue(result['off_anchor_A2_B2_stages_bit_equal'])
            self.assertNotIn('off_anchor_all_captured_stages_bit_equal', result)
            self.assertTrue(any('A1/B1' in text for text in result['limitations']))

    def test_identity_controls_and_mode_drift_are_rejected(self):
        changes = {
            'apk': lambda s: s['apk'].update(sha256='c'*64),
            'media': lambda s: s['sourceReceipt'].update(hostSha256='c'*64, deviceSha256='c'*64),
            'serial': lambda s: s.update(serial='other'),
            'display': lambda s: s['displayControls'].update(brightness=255),
            'control': lambda s: s['controls'].update({'debug.mks.yuv_inv': '1'}),
            'lease': lambda s: s['controls'].update({m.LEASE_PROPERTY: '0'}),
            'mode': lambda s: s.update(oracleMode=0),
            'pts': lambda s: s.update(requestedPTS=600.0),
            'pid': lambda s: s.update(pid='123'),
        }
        for key, change in changes.items():
            with self.subTest(key=key), tempfile.TemporaryDirectory() as tmp:
                off, on = self.rounds(tmp)
                change_summary(on, change)
                with self.assertRaises((ValueError, RuntimeError)):
                    m.analyze_rounds([off, on])
        with tempfile.TemporaryDirectory() as tmp:
            off, on = self.rounds(tmp)
            change_manifest(on, lambda d: d.update(target_width=2, roi={'x': 0, 'y': 0, 'w': 1, 'h': 1}))
            with self.assertRaises((ValueError, RuntimeError)):
                m.analyze_rounds([off, on])

    def test_receipt_tampering_and_nonfinite_or_coverage_fail_closed(self):
        for fault in ('payload-hash', 'manifest-hash', 'nonfinite', 'coverage'):
            with self.subTest(fault=fault), tempfile.TemporaryDirectory() as tmp:
                off, on = self.rounds(tmp)
                if fault == 'manifest-hash':
                    summary = json.loads((on/'summary.json').read_text())
                    manifest = on/'capture'/Path(summary['captureEvent']['file']).name
                    manifest.write_bytes(manifest.read_bytes()+b' ')
                elif fault == 'payload-hash':
                    change_word(on, 'lib', 26+7, 0x3f800000, update=False)
                elif fault == 'nonfinite':
                    change_word(on, 'lib', 26+7, 0x7f800000)
                else:
                    change_word(on, 'lib', 26, 0)
                with self.assertRaises((ValueError, RuntimeError)):
                    m.analyze_rounds([off, on])

    def test_shader_change_is_reported_not_claimed_comparable(self):
        with tempfile.TemporaryDirectory() as tmp:
            off, on = self.rounds(tmp)
            root = on/'capture'
            summary = json.loads((on/'summary.json').read_text())
            manifest = json.loads((root/Path(summary['captureEvent']['file']).name).read_text())
            path = root/manifest['files']['candidate']
            path.write_bytes(path.read_bytes()+b'// changed shader\n')
            update_receipt(on)
            result = m.analyze_rounds([off, on])
            self.assertFalse(result['shaderSourcesIdentical'])
            self.assertNotEqual(result['shaderSha256'][0]['candidate'], result['shaderSha256'][1]['candidate'])
            self.assertFalse(result['acceptance'])

    def test_duplicate_round_and_missing_identity_are_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            off, on = self.rounds(tmp)
            with self.assertRaisesRegex(ValueError, 'duplicate-round'):
                m.analyze_rounds([off, off])
            change_summary(on, lambda s: s['sourceReceipt'].pop('deviceSource'))
            with self.assertRaises(ValueError):
                m.analyze_rounds([off, on])


if __name__ == '__main__':
    unittest.main()
