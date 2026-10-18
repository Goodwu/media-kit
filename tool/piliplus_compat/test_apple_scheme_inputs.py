from pathlib import Path
import unittest
from apple_scheme_inputs import expected_scheme, expected_workspace, metal

class AppleSchemeTests(unittest.TestCase):
    def test_macos_metal_flag_and_version_exact(self):
        original = b'<Scheme LastUpgradeVersion = "1300">\n  debugServiceExtension = "internal"\n</Scheme>\n'
        expected = b'<Scheme LastUpgradeVersion = "1510">\n  debugServiceExtension = "internal"\n  enableGPUValidationMode = "1"\n</Scheme>\n'
        self.assertEqual(expected_scheme('macos', original), expected)

    def test_explicit_metal_choice_unchanged(self):
        text = 'debugServiceExtension = "internal"\nenableGPUValidationMode = "0"\n'
        self.assertEqual(metal(text), text)

    def test_ios_lldb_exact_and_idempotent(self):
        text = b'      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"\n'
        actual = expected_scheme('ios', text)
        self.assertEqual(actual, text+b'      customLLDBInitFile = "$(SRCROOT)/Flutter/ephemeral/flutter_lldbinit"\n')
        self.assertEqual(expected_scheme('ios', actual), actual)

    def test_explicit_lldb_choice_not_replaced(self):
        text = b'<Scheme customLLDBInitFile="custom"/>\n'
        self.assertEqual(expected_scheme('ios', text), text)

    def test_workspace_only_inserts_pods_reference(self):
        text = b'<Workspace>\n  <!-- original -->\n</Workspace>\n'
        actual = expected_workspace(text)
        self.assertEqual(actual, b'<Workspace>\n  <!-- original -->\n   <FileRef\n      location = "group:Pods/Pods.xcodeproj">\n   </FileRef>\n</Workspace>\n')
        self.assertEqual(expected_workspace(actual), actual)
        with self.assertRaises(ValueError): expected_workspace(b'<unknown>')
