import unittest
from generated_macos import migrate_macos_config
from generated_apple import blob, is_generated_configuration

class MacOSGeneratorTests(unittest.TestCase):
    def test_minimum_and_xcode_metadata_match_reviewed_generator(self):
        source = b'objectVersion = 46;\nLastUpgradeCheck = 1300;\nMACOSX_DEPLOYMENT_TARGET = 10.14;\n'
        expected = b'objectVersion = 54;\nLastUpgradeCheck = 1510;\nMACOSX_DEPLOYMENT_TARGET = 12.0;\n'
        self.assertEqual(migrate_macos_config('macos/Runner.xcodeproj/project.pbxproj', source), expected)
    def test_podfile_preserves_other_content(self):
        source = b"platform :osx, '10.14'\nrequire 'original'\n"
        self.assertEqual(migrate_macos_config('macos/Podfile', source),
                         b"platform :osx, '12.0'\nrequire 'original'\n")
    def test_newer_versions_are_never_lowered(self):
        source = b'objectVersion = 77;\nLastUpgradeCheck = 2700;\nMACOSX_DEPLOYMENT_TARGET = 15.0;\n'
        self.assertEqual(migrate_macos_config('macos/Runner.xcodeproj/project.pbxproj', source), source)
    def test_scheme_change_is_exact(self):
        path = 'macos/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme'
        source = b'<Scheme LastUpgradeVersion = "1300">\n</Scheme>\n'
        expected = migrate_macos_config(path, source)
        self.assertIn(b'"1510"', expected)
        record = {path: {'before': blob(source), 'after': blob(expected)}}
        self.assertTrue(is_generated_configuration(path, blob(source), expected, record))
        self.assertFalse(is_generated_configuration(path, blob(source), expected+b'<Injection/>', record))
    def test_unknown_path_rejected(self):
        with self.assertRaises(ValueError): migrate_macos_config('macos/Runner/AppDelegate.swift', b'code')
