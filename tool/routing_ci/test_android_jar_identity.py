import hashlib
from pathlib import Path
import tempfile
import unittest
import warnings
import zipfile

from tool.routing_ci.android_jar_identity import MARKERS, release_arm64_identity, verify_jar


def entry(name='asset-arm64-v8a.jar', destination='default-arm64-v8a.jar', sha='a' * 64):
    return (f'["url": "https://github.com/example/repo/releases/download/v1/{name}", '
            f'"sha256": "{sha}", "destination": file("$buildDir/v1/{destination}")]')


class ReleaseIdentityTests(unittest.TestCase):
    def test_old_and_suffixed_release_asset_names(self):
        for name in ('asset-arm64-v8a.jar', 'asset-arm64-v8a-vkweak.jar', 'new-name.jar'):
            url, sha = release_arm64_identity(entry(name))
            self.assertTrue(url.endswith('/' + name))
            self.assertEqual(sha, 'a' * 64)

    def test_abi_selected_from_destination_not_another_url(self):
        text = entry(destination='default-x86.jar') + '\n' + entry('right.jar')
        self.assertTrue(release_arm64_identity(text)[0].endswith('/right.jar'))

    def test_missing_duplicate_bad_hash_and_url_fail_closed(self):
        for text in ('', entry() + '\n' + entry(), entry(sha='invalid'),
                     entry().replace('https://', 'http://')):
            with self.subTest(text=text), self.assertRaises(ValueError):
                release_arm64_identity(text)

    def test_comment_cannot_authorize_release(self):
        with self.assertRaises(ValueError):
            release_arm64_identity('// ' + entry())

    def test_current_repository_gradle_is_parsed(self):
        root = Path(__file__).resolve().parents[2]
        gradle = root / 'libs/android/media_kit_libs_android_video/android/build.gradle'
        url, digest = release_arm64_identity(gradle.read_text())
        self.assertTrue(url.endswith('.jar'))
        self.assertEqual(len(digest), 64)

    def check(self, payload, digest=None, member='lib/arm64-v8a/libmpv.so', duplicate=False):
        with tempfile.TemporaryDirectory() as temp:
            jar = Path(temp) / 'test.jar'
            with warnings.catch_warnings():
                warnings.simplefilter('ignore', UserWarning)
                with zipfile.ZipFile(jar, 'w') as archive:
                    archive.writestr(member, payload)
                    if duplicate:
                        archive.writestr(member, payload)
            verify_jar(jar, digest or hashlib.sha256(jar.read_bytes()).hexdigest())

    def test_valid_checksum_and_markers(self):
        self.check(b'\0'.join(MARKERS))

    def test_wrong_checksum_and_missing_marker_rejected(self):
        for payload, digest in ((b'\0'.join(MARKERS), '0' * 64), (MARKERS[0], None)):
            with self.assertRaises(ValueError):
                self.check(payload, digest)

    def test_wrong_abi_and_duplicate_member_rejected(self):
        with self.assertRaises(ValueError):
            self.check(b'\0'.join(MARKERS), member='lib/x86/libmpv.so')
        with self.assertRaises(ValueError):
            self.check(b'\0'.join(MARKERS), duplicate=True)


if __name__ == '__main__':
    unittest.main()
