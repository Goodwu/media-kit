import hashlib
import io
import os
from pathlib import Path
import tarfile
import tempfile
import unittest
from darwin_bundle_inputs import verify_bundle, stripped_path


@unittest.skipIf(os.name == 'nt', 'Darwin file modes and symlinks')
class DarwinInputsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bin = self.root / 'Frameworks/Mpv.xcframework/macos-arm64_x86_64/Mpv.framework/Versions/A/Mpv'
        self.bin.parent.mkdir(parents=True); self.bin.write_bytes(b'native fixture'); self.bin.chmod(0o755)
        self.link = self.bin.parent.parent / 'Current'; self.link.symlink_to('A', target_is_directory=True)
        symlink = self.root / 'Frameworks/.symlinks/mpv/macos'; symlink.parent.mkdir(parents=True)
        symlink.symlink_to('../../Mpv.xcframework/macos-arm64_x86_64', target_is_directory=True)
        self.archive = self.root / '.cache/xcframeworks/libmpv-xcframeworks-1.0-macos-universal.tar.gz'
        self.archive.parent.mkdir(parents=True)
        (self.archive.parent / 'libmpv-xcframeworks-macos-universal.tar.gz').symlink_to(self.archive.name)
        self.make_archive()

    def make_archive(self, extra=None):
        with tarfile.open(self.archive, 'w:gz') as archive:
            archive.add(self.root / 'Frameworks/Mpv.xcframework', arcname='bundle/Mpv.xcframework')
            if extra is not None:
                member = tarfile.TarInfo(extra); member.size = 3
                archive.addfile(member, io.BytesIO(b'bad'))
        checksum = hashlib.sha256(self.archive.read_bytes()).hexdigest()
        (self.root / 'Makefile').write_text('MPV_XCFRAMEWORKS_VERSION=1.0\nMPV_XCFRAMEWORKS_SHA256SUM=' + checksum + '\n')

    def test_exact_archive_is_verified_but_not_latest_source(self):
        result = verify_bundle(self.root, 'macos')
        self.assertFalse(result['latestNativeSourceVerified'])
        self.assertIn('Frameworks/.symlinks/mpv/macos', result['records'])

    def test_changed_framework_binary_rejected(self):
        self.bin.write_bytes(b'foreign binary')
        with self.assertRaises(ValueError): verify_bundle(self.root, 'macos')

    def test_changed_archive_rejected(self):
        with self.archive.open('ab') as file: file.write(b'changed')
        with self.assertRaises(ValueError): verify_bundle(self.root, 'macos')

    def test_new_file_cannot_hide_inside_frameworks(self):
        (self.bin.parent / 'injected.h').write_text('source')
        with self.assertRaises(ValueError): verify_bundle(self.root, 'macos')

    def test_link_spelling_and_destination_are_checked(self):
        self.link.unlink(); self.link.symlink_to('A/../A', target_is_directory=True)
        with self.assertRaises(ValueError): verify_bundle(self.root, 'macos')

    def test_mode_change_rejected(self):
        self.bin.chmod(0o644)
        with self.assertRaises(ValueError): verify_bundle(self.root, 'macos')

    def test_missing_binary_rejected(self):
        self.bin.unlink()
        with self.assertRaises(OSError): verify_bundle(self.root, 'macos')

    def test_duplicate_declaration_rejected(self):
        with (self.root / 'Makefile').open('a') as file: file.write('MPV_XCFRAMEWORKS_VERSION=2.0\n')
        with self.assertRaises(ValueError): verify_bundle(self.root, 'macos')

    def test_traversal_archive_rejected(self):
        self.make_archive('bundle/../../evil')
        with self.assertRaises(ValueError): verify_bundle(self.root, 'macos')

    def test_duplicate_archive_member_rejected(self):
        self.make_archive('bundle/Mpv.xcframework/macos-arm64_x86_64/Mpv.framework/Versions/A/Mpv')
        with self.assertRaises(ValueError): verify_bundle(self.root, 'macos')

class StripTests(unittest.TestCase):
    def test_strip_exactly_one_component(self):
        self.assertEqual(stripped_path('bundle/X/file'), 'X/file')
        self.assertEqual(stripped_path('./X/file'), 'X/file')
        self.assertIsNone(stripped_path('bundle/'))
        for path in ('/root/file', 'bundle/../escape', 'bundle/a//file', 'bundle/a\\file'):
            with self.assertRaises(ValueError): stripped_path(path)
