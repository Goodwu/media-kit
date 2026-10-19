import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

from dependency_plan import AuditError
from direction_b_inputs import ALLOWED, apply_direction_b, blob


class DirectionBInputsTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.app, self.sdk, self.out = [self.root / name for name in ('app', 'sdk', 'out')]
        for root in (self.app, self.sdk, self.out): root.mkdir()
        self.name = 'lib/plugin/pl_player/controller.dart'
        p = self.app / self.name
        p.parent.mkdir(parents=True); p.write_text('old player\n')
        self.git('init', '-q')
        self.git('config', 'user.name', 'Test')
        self.git('config', 'user.email', 'test@example.invalid')
        self.git('add', '.'); self.git('commit', '-qm', 'original')
        p.write_text('explicit session\n')
        patch = self.git('diff', '--binary')
        self.git('checkout', '--', '.')
        self.recipe = self.sdk / 'tool/piliplus_compat/direction_b'
        self.recipe.mkdir(parents=True)
        (self.recipe / 'player-integration.patch').write_bytes(patch)
        self.manifest = {'version': 1, 'decision': 'B-approved-20261019',
            'patchSha256': hashlib.sha256(patch).hexdigest(),
            'files': {self.name: {'before': blob(b'old player\n'),
                                  'after': blob(b'explicit session\n')}}}
        self.sdk_git('init', '-q')
        self.sdk_git('config', 'user.name', 'Test')
        self.sdk_git('config', 'user.email', 'test@example.invalid')
        self.sdk_git('config', 'core.autocrlf', 'false')
        self.save()

    def sdk_git(self, *args):
        return subprocess.check_output(['git', '-C', str(self.sdk), *args], stderr=subprocess.STDOUT)

    def git(self, *args):
        return subprocess.check_output(['git', '-C', str(self.app), *args], stderr=subprocess.STDOUT)

    def save(self):
        (self.recipe / 'manifest.json').write_text(json.dumps(self.manifest))
        self.sdk_git('add', '.')
        self.sdk_git('commit', '--allow-empty', '-qm', 'reviewed recipe')

    def test_applies_only_reviewed_diff_and_retains_original_identity(self):
        before = self.git('rev-parse', 'HEAD').decode().strip()
        result = apply_direction_b(self.app, self.sdk, self.out)
        self.assertEqual(result['upstreamCommit'], before)
        self.assertNotEqual(result['integratedCommit'], before)
        self.assertFalse(result['zeroPatch'])
        self.assertEqual(self.git('status', '--porcelain'), b'')
        self.assertEqual((self.app / self.name).read_text(), 'explicit session\n')

    def test_upstream_blob_change_is_rejected_before_write(self):
        self.manifest['files'][self.name]['before'] = '0' * 40; self.save()
        with self.assertRaises(AuditError): apply_direction_b(self.app, self.sdk, self.out)
        self.assertEqual((self.app / self.name).read_text(), 'old player\n')

    def test_business_and_native_paths_are_not_authorized(self):
        for name in ('lib/http/video.dart', 'android/app/MainActivity.kt', '../escape'):
            self.manifest['files'] = {name: {'before': '', 'after': ''}}; self.save()
            with self.assertRaises(AuditError): apply_direction_b(self.app, self.sdk, self.out)

    def test_patch_digest_is_required(self):
        self.manifest['patchSha256'] = '0' * 64; self.save()
        with self.assertRaises(AuditError): apply_direction_b(self.app, self.sdk, self.out)

    def test_dirty_input_is_rejected(self):
        (self.app / self.name).write_text('uncommitted work\n')
        with self.assertRaises(AuditError): apply_direction_b(self.app, self.sdk, self.out)

    def test_wrong_postimage_cannot_be_certified(self):
        self.manifest['files'][self.name]['after'] = '0' * 40; self.save()
        with self.assertRaises(AuditError): apply_direction_b(self.app, self.sdk, self.out)
        self.assertFalse((self.out / 'direction-b-applied.patch').exists())

    def test_windows_checkout_line_endings_do_not_change_reviewed_patch(self):
        self.sdk_git('config', 'core.autocrlf', 'true')
        patch = self.recipe / 'player-integration.patch'
        patch.write_bytes(patch.read_bytes().replace(b'\n', b'\r\n'))
        result = apply_direction_b(self.app, self.sdk, self.out)
        self.assertEqual(result['patchSha256'], self.manifest['patchSha256'])
        self.assertNotIn(b'\r\n', (self.out / 'direction-b-input.patch').read_bytes())
        self.assertEqual((self.app / self.name).read_text(), 'explicit session\n')

    def test_committed_patch_tamper_is_not_line_ending_normalized(self):
        patch = self.recipe / 'player-integration.patch'
        patch.write_bytes(patch.read_bytes().replace(b'explicit session', b'unreviewed code'))
        self.sdk_git('add', '.'); self.sdk_git('commit', '-qm', 'tampered recipe')
        with self.assertRaises(AuditError): apply_direction_b(self.app, self.sdk, self.out)
        self.assertEqual((self.app / self.name).read_text(), 'old player\n')

    def test_allowlist_contains_only_reviewed_dart_player_binding_paths(self):
        self.assertEqual(len(ALLOWED), 7)
        self.assertTrue(all(name.startswith('lib/') and name.endswith('.dart') for name in ALLOWED))


if __name__ == '__main__': unittest.main()
