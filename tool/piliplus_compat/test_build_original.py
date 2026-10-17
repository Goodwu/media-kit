import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

import build_original as build


class BuildGuardTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.root = self.base / 'source'
        self.root.mkdir()
        self.git('init', '-q')
        self.git('config', 'user.name', 'test')
        self.git('config', 'user.email', 'test@example.invalid')
        self.git('config', 'core.autocrlf', 'false')
        self.write('pubspec.yaml', 'name: app\n')
        self.write('lib/main.dart', 'void main() {}\n')
        self.write('pubspec.lock', 'old\n')
        self.commit()

    def git(self, *args):
        return build.git(self.root, *args)

    def write(self, name, content):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding='utf-8')

    def commit(self):
        self.git('add', '.')
        self.git('commit', '-qm', 'fixture')

    def test_clone_and_manifest_preserve_exact_source(self):
        manifest = build.tracked_manifest(self.root)
        dest = self.base / 'stage'
        commit = self.git('rev-parse', 'HEAD').decode().strip()
        build.clone_exact(self.root, dest, commit)
        self.assertTrue(build.verify_tracked(dest, manifest)['originalSourceUnchanged'])

    def test_changed_source_rejected_even_with_git_assume_unchanged(self):
        manifest = build.tracked_manifest(self.root)
        self.git('update-index', '--assume-unchanged', 'lib/main.dart')
        self.write('lib/main.dart', 'void hacked() {}\n')
        with self.assertRaises(build.AuditError):
            build.verify_tracked(self.root, manifest, build.GENERATED_TRACKED)

    def test_deleted_original_rejected(self):
        manifest = build.tracked_manifest(self.root)
        (self.root / 'lib/main.dart').unlink()
        with self.assertRaises(build.AuditError):
            build.verify_tracked(self.root, manifest)

    @unittest.skipIf(os.name == 'nt', 'POSIX executable mode')
    def test_mode_change_rejected(self):
        manifest = build.tracked_manifest(self.root)
        (self.root / 'lib/main.dart').chmod(0o755)
        with self.assertRaises(build.AuditError):
            build.verify_tracked(self.root, manifest)

    def test_generated_lock_recorded_not_hidden(self):
        manifest = build.tracked_manifest(self.root)
        self.write('pubspec.lock', 'new\n')
        result = build.verify_tracked(self.root, manifest, build.GENERATED_TRACKED)
        self.assertIn('pubspec.lock', result['generatedChanges'])
        with self.assertRaises(build.AuditError):
            build.verify_tracked(self.root, manifest)

    def test_new_source_rejected_even_when_gitignored(self):
        self.write('.gitignore', 'lib/new.dart\n')
        self.commit()
        self.write('lib/new.dart', 'void injected() {}\n')
        with self.assertRaises(build.AuditError):
            build.verify_added(self.root, app=True)

    def test_asset_build_directory_not_exempted(self):
        self.write('assets/build/review.bin', 'new resource')
        with self.assertRaises(build.AuditError):
            build.verify_added(self.root, app=True)

    def test_build_output_permitted_not_app_source(self):
        self.write('build/app/intermediates/something', 'generated')
        self.assertEqual(build.verify_added(self.root, app=True)['generatedFileCount'], 1)

    @unittest.skipIf(os.name == 'nt', 'symlink creation privilege not assumed')
    def test_file_replaced_by_symlink_rejected(self):
        manifest = build.tracked_manifest(self.root)
        file = self.root / 'lib/main.dart'
        file.unlink()
        file.symlink_to('../pubspec.yaml')
        with self.assertRaises(build.AuditError):
            build.verify_tracked(self.root, manifest)

    def test_local_uri_handles_encoded_spaces(self):
        path = self.base / 'with space'
        path.mkdir()
        self.assertEqual(build.local_uri(self.root / 'file', path.as_uri()), path.resolve())

    def test_nonlocal_uri_rejected(self):
        for uri in ('https://example.invalid/lib', 'file://other-host/foo', 'file:///a?q=1'):
            with self.assertRaises(build.AuditError):
                build.local_uri(self.root / 'file', uri)

    def test_native_only_package_without_lib_is_accepted(self):
        root = self.base / 'native_plugin'
        root.mkdir()
        file = self.base / 'package_config.json'
        row = {'name': 'native_plugin', 'rootUri': root.as_uri(), 'packageUri': 'lib/'}
        file.write_text(json.dumps({'configVersion': 2, 'packages': [row]}))
        self.assertEqual(build.resolution_roots(file)['native_plugin'], root)
        self.assertFalse((root / 'lib').exists())

    @unittest.skipIf(os.name == 'nt', 'symlink privilege not assumed')
    def test_existing_lib_symlink_escape_is_rejected(self):
        root = self.base / 'native_plugin'
        root.mkdir()
        (root / 'lib').symlink_to(self.root / 'lib', target_is_directory=True)
        file = self.base / 'package_config.json'
        row = {'name': 'native_plugin', 'rootUri': root.as_uri(), 'packageUri': 'lib/'}
        file.write_text(json.dumps({'configVersion': 2, 'packages': [row]}))
        with self.assertRaises(build.AuditError):
            build.resolution_roots(file)

    def test_absent_package_root_still_rejected(self):
        file = self.base / 'package_config.json'
        row = {'name': 'missing', 'rootUri': (self.base / 'absent').as_uri(), 'packageUri': 'lib/'}
        file.write_text(json.dumps({'configVersion': 2, 'packages': [row]}))
        with self.assertRaises(OSError):
            build.resolution_roots(file)

    def test_resolution_duplicate_rejected(self):
        (self.root / 'lib').mkdir(exist_ok=True)
        row = {'name': 'app', 'rootUri': self.root.as_uri(), 'packageUri': 'lib/'}
        file = self.base / 'package_config.json'
        file.write_text(json.dumps({'configVersion': 2, 'packages': [row, row]}))
        with self.assertRaises(build.AuditError):
            build.resolution_roots(file)

    def test_resolution_library_escape_rejected(self):
        file = self.base / 'package_config.json'
        row = {'name': 'app', 'rootUri': self.root.as_uri(), 'packageUri': '../'}
        file.write_text(json.dumps({'configVersion': 2, 'packages': [row]}))
        with self.assertRaises(build.AuditError):
            build.resolution_roots(file)

    def test_windows_symlink_separator_representation(self):
        self.assertEqual(build.symlink_payload(r'..\common\a.swift', windows=True),
                         b'../common/a.swift')
        self.assertEqual(build.symlink_payload(r'..\common\a.swift', windows=False),
                         b'..\\common\\a.swift')
        self.assertNotEqual(build.symlink_payload(r'C:\common\a.swift', windows=True),
                            b'../common/a.swift')

    def test_generated_android_registration_is_an_exact_exception(self):
        self.write('android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java',
                   '// Generated file. Do not edit.\n')
        self.assertEqual(build.verify_added(self.root, app=True)['generatedFileCount'], 1)
        self.write('android/app/src/main/java/io/flutter/plugins/NotGenerated.java', 'class Foreign {}')
        with self.assertRaises(build.AuditError):
            build.verify_added(self.root, app=True)

    def test_runner_persists_failure_and_actual_exit(self):
        out = self.base / 'output'
        out.mkdir()
        runner = build.Runner(out)
        import sys
        with self.assertRaises(build.AuditError):
            runner.run('failure', [sys.executable, '-c', 'raise SystemExit(7)'], self.root)
        data = json.loads((out / 'build-receipt.json').read_text())
        self.assertEqual(data['steps'][-1]['exitCode'], 7)
        self.assertEqual(data['nativeSourceFreshness'], 'not-verified')


if __name__ == '__main__':
    unittest.main()
