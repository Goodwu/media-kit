import unittest
from generated_xcconfig import digest, is_generated_cocoapods_include


class GeneratedXcconfigTests(unittest.TestCase):
    source = b'#include "ephemeral/Flutter-Generated.xcconfig"\n'
    debug = 'macos/Flutter/Flutter-Debug.xcconfig'
    prefix = b'#include? "Pods/Target Support Files/Pods-Runner/Pods-Runner.debug.xcconfig"\n'

    def test_exact_debug_and_release_generation(self):
        for mode in ('Debug', 'Release'):
            path = f'macos/Flutter/Flutter-{mode}.xcconfig'
            prefix = self.prefix.replace(b'debug', mode.lower().encode())
            self.assertTrue(is_generated_cocoapods_include(path, digest(self.source), prefix + self.source))

    def test_original_input_bytes_cannot_be_changed(self):
        for change in (b'OTHER=YES\n', b'\n', b'// comment\n'):
            self.assertFalse(is_generated_cocoapods_include(self.debug, digest(self.source), self.prefix + self.source + change))

    def test_original_line_endings_cannot_be_normalized(self):
        self.assertFalse(is_generated_cocoapods_include(self.debug, digest(self.source), self.prefix + self.source.replace(b'\n', b'\r\n')))

    def test_no_blanket_xcconfig_exemption(self):
        for path in ('ios/Flutter/Debug.xcconfig', 'macos/Runner/Configs/AppInfo.xcconfig', 'elsewhere/Flutter-Debug.xcconfig'):
            self.assertFalse(is_generated_cocoapods_include(path, digest(self.source), self.prefix + self.source))

    def test_wrong_mode_and_include_order_rejected(self):
        self.assertFalse(is_generated_cocoapods_include(self.debug, digest(self.source), self.prefix.replace(b'debug', b'release') + self.source))
        self.assertFalse(is_generated_cocoapods_include(self.debug, digest(self.source), self.source + self.prefix))

    def test_duplicate_or_preexisting_pods_include_rejected(self):
        self.assertFalse(is_generated_cocoapods_include(self.debug, digest(self.source), self.prefix * 2 + self.source))
        prior = self.prefix + self.source
        self.assertFalse(is_generated_cocoapods_include(self.debug, digest(prior), self.prefix + prior))

    def test_changed_include_cannot_escape(self):
        for prefix in (self.prefix.replace(b'Pods/', b'../../Pods/'), self.prefix.replace(b'#include?', b'#include')):
            self.assertFalse(is_generated_cocoapods_include(self.debug, digest(self.source), prefix + self.source))


if __name__ == '__main__':
    unittest.main()
