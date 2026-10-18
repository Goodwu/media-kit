from pathlib import Path
import contextlib
import io
import json
import os
import sys
import tempfile
import unittest
from private_flutter_cache import copy_flutter_cache
import build_original as build
from generated_apple import blob, migrate_ios_config


class BuildCorrectionsTests(unittest.TestCase):
    @unittest.skipIf(os.name == 'nt', 'symlink privilege not assumed')
    def test_versioned_framework_links_and_independent_bytes(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d); source = root / 'cache'; dest = root / 'private'
            binary = source / 'FlutterMacOS.framework/Versions/A/FlutterMacOS'
            binary.parent.mkdir(parents=True); binary.write_bytes(b'framework')
            (binary.parent / 'Resources').mkdir()
            framework = source / 'FlutterMacOS.framework'
            (framework / 'Versions/Current').symlink_to('A', target_is_directory=True)
            (framework / 'FlutterMacOS').symlink_to('Versions/Current/FlutterMacOS')
            (framework / 'Resources').symlink_to('Versions/Current/Resources', target_is_directory=True)
            receipt = copy_flutter_cache(source, dest)
            self.assertEqual(receipt['linkCount'], 3)
            for relative in receipt['links']:
                self.assertTrue((dest / relative).is_symlink())
            (dest / binary.relative_to(source)).write_bytes(b'private')
            self.assertEqual(binary.read_bytes(), b'framework')

    @unittest.skipIf(os.name == 'nt', 'symlink privilege not assumed')
    def test_absolute_internal_link_rebased(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d); source = root / 'cache'; source.mkdir()
            (source / 'data').write_bytes(b'data'); (source / 'link').symlink_to(source / 'data')
            dest = root / 'private'; copy_flutter_cache(source, dest)
            self.assertEqual((dest / 'link').resolve(), dest / 'data')

    @unittest.skipIf(os.name == 'nt', 'symlink privilege not assumed')
    def test_escaping_or_dangling_cache_links_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d); source = root / 'cache'; source.mkdir()
            (root / 'outside').write_bytes(b'outside'); link = source / 'link'
            link.symlink_to('../outside')
            with self.assertRaises(ValueError): copy_flutter_cache(source, root / 'private')
            self.assertFalse((root / 'private').exists())
            link.unlink(); link.symlink_to('missing')
            with self.assertRaises(OSError): copy_flutter_cache(source, root / 'private')

    def test_windows_console_cannot_change_actual_compiler_status(self):
        with tempfile.TemporaryDirectory() as d:
            out = Path(d); runner = build.Runner(out)
            buffer = io.BytesIO(); console = io.TextIOWrapper(buffer, encoding='cp1252')
            with contextlib.redirect_stdout(console):
                status = runner.run('unicode', [sys.executable, '-c',
                    "import sys; sys.stdout.buffer.write('\\u221a Built'.encode('utf-8'))"], out)
            console.flush()
            self.assertEqual(status, 0)
            self.assertIn('√ Built', (out / 'unicode.log').read_text(encoding='utf-8'))
            self.assertEqual(json.loads((out / 'build-receipt.json').read_text())['steps'][-1]['exitCode'], 0)

    def test_exact_apple_config_not_a_broad_source_exception(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d); p = root / 'ios/Podfile'; p.parent.mkdir()
            before = b"platform :ios, '14.0'\n# keep\n"; after = migrate_ios_config(before)
            manifest = {'ios/Podfile': {'mode': '100644', 'blob': blob(before)}}
            configs = {'ios/Podfile': {'before': blob(before), 'after': blob(after), 'generator': 'test'}}
            p.write_bytes(after)
            record = build.verify_tracked(root, manifest, build.GENERATED_TRACKED, configs)
            self.assertFalse(record['allTrackedBytesUnchanged'])
            self.assertIn('ios/Podfile', record['generatedPlatformConfigurationChanges'])
            p.write_bytes(after + b'foreign code\n')
            with self.assertRaises(build.AuditError):
                build.verify_tracked(root, manifest, build.GENERATED_TRACKED, configs)
