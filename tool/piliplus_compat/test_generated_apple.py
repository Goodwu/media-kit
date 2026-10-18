from pathlib import Path
import hashlib
import tempfile
import unittest
from generated_apple import (blob, engine_podspec, is_generated_configuration,
                             migrate_ios_config, verify_generated_apple, verify_generators)

class GeneratedAppleTests(unittest.TestCase):
    def test_exact_deployment_migration(self):
        before = b"platform :ios, '14.0'\n# keep this\nIPHONEOS_DEPLOYMENT_TARGET = 13.0;\n"
        after = b"platform :ios, '15.0'\n# keep this\nIPHONEOS_DEPLOYMENT_TARGET = 15.0;\n"
        self.assertEqual(migrate_ios_config(before), after)

    def test_exact_minimum_os_removal(self):
        before = b'<dict>\n  <key>MinimumOSVersion</key>\n  <string>14.0</string>\n  <key>Other</key>\n</dict>\n'
        self.assertEqual(migrate_ios_config(before), b'<dict>\n  <key>Other</key>\n</dict>\n')

    def test_source_change_cannot_hide_in_migration(self):
        before = b"platform :ios, '14.0'\n# original\n"
        expected = migrate_ios_config(before)
        records = {'ios/Podfile': {'before': blob(before), 'after': blob(expected)}}
        self.assertTrue(is_generated_configuration('ios/Podfile', blob(before), expected, records))
        self.assertFalse(is_generated_configuration('ios/Podfile', blob(before), expected + b'exec something\n', records))
        self.assertFalse(is_generated_configuration('ios/Podfile', 'other-blob', expected, records))
        self.assertFalse(is_generated_configuration('ios/Other', blob(before), expected, records))

    def test_future_minimums_not_rewritten(self):
        before = b"platform :ios, '16.0'\nIPHONEOS_DEPLOYMENT_TARGET = 16.0;\n"
        self.assertEqual(migrate_ios_config(before), before)

    def test_extract_static_heredoc_only(self):
        src = "def flutter_install_ios_engine_pod(x)\n    podspec.write <<~EOF\n      # generated\n      Pod::Spec.new\n    EOF\nend\ndef flutter_install_macos_engine_pod(x)\n"
        self.assertEqual(engine_podspec(src), b'# generated\nPod::Spec.new\n')
        with self.assertRaises(ValueError): engine_podspec(src.replace('Pod::Spec.new', '#{unsafe}'))

    def test_new_file_matches_frozen_bytes(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d); p = root / 'ios/Flutter/Flutter.podspec'; p.parent.mkdir(parents=True)
            p.write_bytes(b'expected')
            record = {'size': 8, 'sha256': hashlib.sha256(b'expected').hexdigest()}
            verify_generated_apple(root, 'ios/Flutter/Flutter.podspec', record)
            p.write_bytes(b'changed!')
            with self.assertRaises(ValueError): verify_generated_apple(root, 'ios/Flutter/Flutter.podspec', record)
            with self.assertRaises(ValueError): verify_generated_apple(root, 'ios/Podfile', record)

    def test_missing_generator_is_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            with self.assertRaises(OSError): verify_generators(Path(d))
