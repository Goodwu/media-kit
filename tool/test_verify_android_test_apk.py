#!/usr/bin/env python3
"""Tests for native artifact identity across JAR and Android APK packaging."""
import importlib.util
import json
from pathlib import Path
import shutil
import tempfile
import unittest
import zipfile

spec = importlib.util.spec_from_file_location(
    'apk_verifier', Path(__file__).with_name('verify_android_test_apk.py'))
verifier = importlib.util.module_from_spec(spec)
spec.loader.exec_module(verifier)


class VerifyApkNative(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.jar_path = self.root / 'default-arm64-v8a.jar'
        self.apk_path = self.root / 'app-release.apk'
        self.candidate_path = self.root / 'native-candidate.json'
        self.output_path = self.root / 'native-verification.json'
        strip_path = shutil.which('strip')
        self.strip_path = Path(strip_path)
        markers = b' surfacetexture MKSURF: version android-native-dv-bridge-api native_dv_api_version '
        self.members = {
            name: (b'bytes:' + name.encode() + markers
                   if name.endswith('/libmpv.so') else b'bytes:' + name.encode())
            for name in verifier.EXPECTED
        }
        self.write_artifacts()

    def tearDown(self):
        self.temp.cleanup()

    def write_artifacts(self, apk_members=None, extra_abi=None, duplicate=False):
        self.jar_path.parent.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(self.jar_path, 'w') as archive:
            for name, data in self.members.items():
                archive.writestr(name, data)
        apk_members = self.members if apk_members is None else apk_members
        with zipfile.ZipFile(self.apk_path, 'w') as archive:
            for name, data in apk_members.items():
                archive.writestr(name, data)
            archive.writestr('lib/arm64-v8a/libapp.so', b'app')
            if extra_abi:
                archive.writestr(extra_abi, b'foreign')
            if duplicate:
                archive.writestr(next(iter(self.members)), b'duplicate')
        jar_sha = verifier.sha(self.jar_path.read_bytes())
        records, inputs = {}, {}
        for name, data in self.members.items():
            digest = verifier.sha(data)
            records[name] = {'sha256': digest}
            filename = name.split('/')[-1]
            if filename == 'libmediakitandroidhelper.so':
                helper_apk = self.root / 'helper.apk'
                with zipfile.ZipFile(helper_apk, 'w') as archive:
                    archive.writestr(name, data)
                inputs[filename] = {'sha256': digest, 'apk': str(helper_apk), 'member': name}
            else:
                source = self.root / filename
                source.write_bytes(data)
                inputs[filename] = {'sha256': digest, 'path': str(source)}
        packaging = {'status': 'packaged-unreviewed', 'jarSha256': jar_sha,
                     'members': records, 'inputs': inputs}
        (self.root / 'packaging.json').write_text(json.dumps(packaging))
        candidate = {'status': 'built-unreviewed', 'sourceDrift': False,
                     'jarSha256': jar_sha, 'sourcesBefore': {},
                     'ndk': {'tools': {'llvm-strip': {
                         'path': str(self.strip_path),
                         'sha256': verifier.sha(self.strip_path.read_bytes()),
                     }}}}
        self.candidate_path.write_text(json.dumps(candidate))

    def replace_libmpv_and_refresh_receipts(self, data):
        name = 'lib/arm64-v8a/libmpv.so'
        changed = dict(self.members)
        changed[name] = data
        self.members = changed
        self.write_artifacts()

    def test_current_native_libraries_are_bound_and_receipt_is_written(self):
        result = verifier.verify(self.apk_path, self.jar_path,
                                 self.candidate_path, self.output_path,
                                 required_marker=['surfacetexture', 'android-native-dv-bridge-api'])
        self.assertEqual(result['status'], 'verified')
        self.assertTrue(self.output_path.is_file())

    def test_stale_libmpv_in_apk_is_rejected(self):
        altered = dict(self.members)
        altered['lib/arm64-v8a/libmpv.so'] = b'old published library'
        self.write_artifacts(apk_members=altered)
        with self.assertRaisesRegex(ValueError, 'canonical stripped JAR bytes'):
            verifier.verify(self.apk_path, self.jar_path,
                             self.candidate_path, self.output_path)

    def test_foreign_abi_is_rejected(self):
        self.write_artifacts(extra_abi='lib/armeabi-v7a/libmpv.so')
        with self.assertRaisesRegex(ValueError, 'unexpected ABIs'):
            verifier.verify(self.apk_path, self.jar_path,
                             self.candidate_path, self.output_path)

    def test_duplicate_apk_native_member_is_rejected(self):
        self.write_artifacts(duplicate=True)
        with self.assertRaisesRegex(ValueError, 'duplicate ZIP members'):
            verifier.verify(self.apk_path, self.jar_path,
                             self.candidate_path, self.output_path)

    def test_missing_required_capability_marker_is_rejected(self):
        libmpv = self.members['lib/arm64-v8a/libmpv.so']
        self.replace_libmpv_and_refresh_receipts(libmpv.replace(b'surfacetexture', b'absent__________'))
        with self.assertRaisesRegex(ValueError, 'lacks required current-fork capabilities'):
            verifier.verify(self.apk_path, self.jar_path,
                             self.candidate_path, self.output_path,
                             required_marker=['surfacetexture'])

    def test_changed_receipt_strip_tool_is_rejected(self):
        candidate = json.loads(self.candidate_path.read_text())
        candidate['ndk']['tools']['llvm-strip']['sha256'] = '0' * 64
        self.candidate_path.write_text(json.dumps(candidate))
        with self.assertRaisesRegex(ValueError, 'llvm-strip is missing or differs'):
            verifier.verify(self.apk_path, self.jar_path,
                             self.candidate_path, self.output_path)


if __name__ == '__main__':
    unittest.main()
