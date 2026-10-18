import os
from pathlib import Path
import tempfile
import unittest
import subprocess

from generated_gradle import WRAPPERS, capture_gradle_wrappers, verify_generated_wrapper
import build_original as build


class GeneratedGradleTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        base = Path(self.temp.name)
        self.flutter = base / 'flutter'
        self.app = base / 'app'
        self.app.mkdir()
        subprocess.run(['git', 'init', '-q', str(self.app)], check=True)
        for relative in WRAPPERS:
            data = ('wrapper ' + relative).encode()
            source = self.flutter / 'bin/cache/artifacts/gradle_wrapper' / relative
            source.parent.mkdir(parents=True, exist_ok=True)
            source.write_bytes(data)
            target = self.app / 'android' / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
            target.chmod(0o755)
        self.records = capture_gradle_wrappers(self.flutter)

    def test_exact_generated_wrapper_bytes_admitted_and_recorded(self):
        result = build.verify_added(self.app, app=True, generated_wrappers=self.records)
        self.assertEqual(len(result['verifiedGradleWrappers']), 3)

    def test_names_without_provenance_are_rejected(self):
        with self.assertRaises(build.AuditError):
            build.verify_added(self.app, app=True)

    def test_tampered_file_rejected_after_freezing(self):
        (self.app / 'android/gradlew').write_text('injected')
        with self.assertRaises(build.AuditError):
            build.verify_added(self.app, app=True, generated_wrappers=self.records)

    def test_frozen_digest_survives_source_and_destination_replacement(self):
        for path in (self.flutter / 'bin/cache/artifacts/gradle_wrapper/gradlew',
                     self.app / 'android/gradlew'):
            path.write_text('both changed')
        with self.assertRaises(build.AuditError):
            build.verify_added(self.app, app=True, generated_wrappers=self.records)

    def test_unrelated_new_android_input_rejected(self):
        (self.app / 'android/extra.gradle').write_text('injected')
        with self.assertRaises(build.AuditError):
            build.verify_added(self.app, app=True, generated_wrappers=self.records)

    @unittest.skipIf(os.name == 'nt', 'symlink privilege not assumed')
    def test_linked_generated_file_rejected(self):
        target = self.app / 'android/gradlew'
        target.unlink()
        target.symlink_to(self.flutter / 'bin/cache/artifacts/gradle_wrapper/gradlew')
        with self.assertRaises(build.AuditError):
            build.verify_added(self.app, app=True, generated_wrappers=self.records)

    @unittest.skipIf(os.name == 'nt', 'POSIX executable mode')
    def test_executable_mode_required(self):
        (self.app / 'android/gradlew').chmod(0o644)
        with self.assertRaises(build.AuditError):
            build.verify_added(self.app, app=True, generated_wrappers=self.records)

    def test_missing_flutter_source_is_not_accepted(self):
        (self.flutter / 'bin/cache/artifacts/gradle_wrapper/gradlew').unlink()
        with self.assertRaises(OSError):
            capture_gradle_wrappers(self.flutter)
