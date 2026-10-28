#!/usr/bin/env python3
"""Evidence gates: actual link closure, dirty source bytes and source drift."""
import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest import mock

spec = importlib.util.spec_from_file_location('native_builder', Path(__file__).with_name('build_android_native.py'))
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)


class EvidenceGates(unittest.TestCase):
    def test_link_closure_ignores_unrelated_edges_and_deduplicates(self):
        text = ('build other: c_LINKER\n LINK_ARGS = /foreign/libbad.a\n'
                'build libmpv.so: c_LINKER main.o | /ndk/libatomic.a\n'
                ' LINK_ARGS = -shared /ndk/libatomic.a /prefix/libavcodec.a /prefix/libplacebo.a /prefix/libavcodec.a\n')
        self.assertEqual(builder.archive_paths(text), ['/ndk/libatomic.a', '/prefix/libavcodec.a', '/prefix/libplacebo.a'])
        with self.assertRaisesRegex(ValueError, 'formal libmpv'):
            builder.archive_paths('build old.so: c_LINKER\n LINK_ARGS = /bad/old.a\n')

    def test_local_dirty_and_untracked_source_bytes_are_frozen(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            def git(*args):
                subprocess.run(['git', '-C', temp, *args], check=True, capture_output=True)
            git('init', '-q')
            git('config', 'user.email', 'build-evidence@example.invalid')
            git('config', 'user.name', 'Build Evidence Test')
            (root / 'source.c').write_text('int version = 1;\n')
            git('add', 'source.c')
            git('commit', '-qm', 'fixture')
            clean = builder.git_source(root)
            (root / 'source.c').write_text('int version = 2;\n')
            (root / 'extra.c').write_text('int extra;\n')
            dirty = builder.git_source(root)
            self.assertNotEqual(clean['sha256'], dirty['sha256'])
            self.assertEqual(clean['head'], dirty['head'])
            self.assertIn('extra.c', dirty['files'])
            with self.assertRaisesRegex(ValueError, 'changed during build'):
                builder.require_same({'mpv': clean}, {'mpv': dirty})
            (root / 'source.c').unlink()
            deleted = builder.git_source(root)
            self.assertEqual(deleted['files']['source.c'], {'deleted': True})

    def test_changed_ndk_is_rejected_before_incremental_build(self):
        with tempfile.TemporaryDirectory() as temp:
            task = builder.Builder.__new__(builder.Builder)
            task.mpv_build = Path(temp)
            (task.mpv_build / 'build.ninja').write_text(
                'build libmpv.so: c_LINKER main.o | /configured/ndk/toolchains/llvm/prebuilt/host/libatomic.a\n'
                ' LINK_ARGS = -shared /prefix/libavcodec.a\n')
            task.ndk = Path('/different/ndk')
            task.bin = task.ndk / 'bin'
            with mock.patch.object(builder, 'capture', return_value='compiler identity'):
                with self.assertRaisesRegex(ValueError, 'differs from configured'):
                    task.validate_configuration()

    def test_installed_archive_must_match_current_build_bytes(self):
        with tempfile.TemporaryDirectory() as temp:
            task = builder.Builder.__new__(builder.Builder)
            task.prefix = Path(temp) / 'prefix'
            (task.prefix / 'lib').mkdir(parents=True)
            built = Path(temp) / 'libexample.a'
            built.write_bytes(b'current local build')
            installed = task.prefix / 'lib/libexample.a'
            installed.write_bytes(b'stale cache')
            task.receipt = {'archives': {}}
            with self.assertRaisesRegex(ValueError, 'does not match current'):
                task.install_archive(built)
            installed.write_bytes(built.read_bytes())
            task.install_archive(built)
            self.assertEqual(task.receipt['archives'][str(installed.resolve())]['sha256'], builder.sha(built))

    def test_source_drift_checks_key_set(self):
        builder.require_same({'mpv': {'sha256': 'same'}}, {'mpv': {'sha256': 'same'}})
        with self.assertRaises(ValueError):
            builder.require_same({'mpv': {}}, {'mpv': {}, 'unexpected': {}})


if __name__ == '__main__':
    unittest.main()
