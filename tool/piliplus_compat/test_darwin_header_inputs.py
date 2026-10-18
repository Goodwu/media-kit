import hashlib
import io
import os
from pathlib import Path
import tarfile
import tempfile
import unittest

from darwin_header_inputs import verify_sdk_headers


@unittest.skipIf(os.name == 'nt', 'Darwin file modes and symlinks')
class HeaderInputsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.sdk = Path(self.temp.name)
        self.common = self.sdk / 'media_kit_video/common/darwin'
        self.cache = self.common / '.cache/headers'; self.cache.mkdir(parents=True)
        self.archive = self.cache / 'mpv-v0.36.0.tar.gz'
        (self.cache / 'mpv.tar.gz').symlink_to(self.archive.name)
        self.outputs = {}
        for platform in ('ios', 'macos'):
            output = self.sdk / f'media_kit_video/{platform}/Headers/mpv'
            output.mkdir(parents=True); self.outputs[platform] = output
            (output / 'client.h').write_bytes(b'client declaration\n')
            (output / 'render.h').write_bytes(b'render declaration\n')
        self.write_archive()

    def write_archive(self, extra=None, omit=False):
        with tarfile.open(self.archive, 'w:gz') as archive:
            if not omit:
                for path in self.outputs['ios'].iterdir():
                    archive.add(path, arcname='mpv-0.36.0/libmpv/' + path.name)
            if extra is not None:
                archive.addfile(*extra)
        checksum = hashlib.sha256(self.archive.read_bytes()).hexdigest()
        (self.common / 'Makefile').write_text('MPV_HEADERS_VERSION=v0.36.0\nMPV_HEADERS_SHA256SUM=' + checksum + '\n')

    def bad(self, platform='ios'):
        with self.assertRaises((ValueError, OSError)):
            verify_sdk_headers(self.sdk, platform)

    def test_exact_platform_projection_and_cache(self):
        for platform in self.outputs:
            result = verify_sdk_headers(self.sdk, platform)
            self.assertEqual(len(result['records']), 4)
            self.assertFalse(result['latestNativeSourceVerified'])
            self.assertIn(f'media_kit_video/{platform}/Headers/mpv/client.h', result['records'])

    def test_changed_header(self):
        (self.outputs['ios'] / 'client.h').write_bytes(b'changed'); self.bad()

    def test_missing_header(self):
        (self.outputs['ios'] / 'client.h').unlink(); self.bad()

    def test_added_header_or_source(self):
        (self.outputs['ios'] / 'injected.c').write_bytes(b'source'); self.bad()

    def test_nested_input_is_not_exempted(self):
        path = self.outputs['ios'] / 'build/injected.c'; path.parent.mkdir()
        path.write_bytes(b'source'); self.bad()

    def test_changed_archive(self):
        with self.archive.open('ab') as stream: stream.write(b'bad')
        self.bad()

    def test_archive_symlink_rejected(self):
        data = self.archive.read_bytes(); self.archive.unlink()
        target = self.cache / 'foreign.tar.gz'; target.write_bytes(data)
        self.archive.symlink_to(target.name); self.bad()

    def test_cache_alias_must_be_exact(self):
        alias = self.cache / 'mpv.tar.gz'; alias.unlink()
        alias.symlink_to('./' + self.archive.name); self.bad()

    def test_unlisted_cached_input(self):
        (self.cache / 'foreign.tar.gz').write_bytes(b'foreign'); self.bad()

    def test_symlink_header_rejected(self):
        path = self.outputs['ios'] / 'client.h'; path.unlink()
        path.symlink_to(self.outputs['macos'] / 'client.h'); self.bad()

    def test_symlink_output_directory_rejected(self):
        path = self.outputs['ios']; moved = path.with_name('elsewhere')
        path.rename(moved); path.symlink_to(moved, target_is_directory=True); self.bad()

    def test_header_mode_checked(self):
        (self.outputs['ios'] / 'client.h').chmod(0o755); self.bad()

    def test_duplicate_declaration(self):
        with (self.common / 'Makefile').open('a') as stream: stream.write('MPV_HEADERS_VERSION=v1.0\n')
        self.bad()

    def test_missing_declaration(self):
        (self.common / 'Makefile').write_text('MPV_HEADERS_VERSION=v0.36.0\n'); self.bad()

    def test_duplicate_projected_header(self):
        member = tarfile.TarInfo('mpv-0.36.0/libmpv/client.h'); member.size = 3
        self.write_archive((member, io.BytesIO(b'bad'))); self.bad()

    def test_traversal_rejected(self):
        member = tarfile.TarInfo('mpv-0.36.0/libmpv/../bad.h'); member.size = 3
        self.write_archive((member, io.BytesIO(b'bad'))); self.bad()

    def test_nested_projection_rejected(self):
        member = tarfile.TarInfo('mpv-0.36.0/libmpv/nested/bad.h'); member.size = 3
        self.write_archive((member, io.BytesIO(b'bad'))); self.bad()

    def test_nonregular_archive_header_rejected(self):
        member = tarfile.TarInfo('mpv-0.36.0/libmpv/linked.h')
        member.type = tarfile.SYMTYPE; member.linkname = 'client.h'
        self.write_archive((member, None)); self.bad()

    def test_empty_projection_rejected(self):
        self.write_archive(omit=True); self.bad()

    def test_unrelated_source_does_not_become_header_input(self):
        member = tarfile.TarInfo('mpv-0.36.0/player/client.c'); member.size = 3
        self.write_archive((member, io.BytesIO(b'foo')))
        self.assertEqual(len(verify_sdk_headers(self.sdk, 'ios')['records']), 4)

    def test_platform_rejected(self):
        self.bad('android')
