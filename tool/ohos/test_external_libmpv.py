"""Run real CMake selection logic without an OHOS compiler or network."""
import hashlib
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
HELPER = ROOT / 'libs/ohos/media_kit_libs_ohos/ohos/src/main/cpp/external_libmpv.cmake'
ARCHIVE = 'MEDIA_KIT_OHOS_LIBMPV_ARCHIVE'
DIGEST = 'MEDIA_KIT_OHOS_LIBMPV_SHA256'

class ExternalNativeInputTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.archive = self.root / 'current native.zip'
        self.data = b'only a fixture; no prebuilt code'
        self.archive.write_bytes(self.data)
        self.sha = hashlib.sha256(self.data).hexdigest()
        self.script = self.root / 'test.cmake'
        self.script.write_text('include("' + str(HELPER) + '")\n'
            'set(path "historical.zip")\nset(sha "historical-sha")\n'
            'media_kit_ohos_external_libmpv(path sha external)\n'
            'message(STATUS "RESULT=${path}|${sha}|${external}")\n')

    def run_cmake(self, extra):
        env = {k: v for k, v in os.environ.items() if k not in (ARCHIVE, DIGEST)}
        env.update(extra)
        return subprocess.run(['cmake', '-P', str(self.script)], env=env,
            text=True, capture_output=True, timeout=10)

    def test_omitted_pair_preserves_release_path(self):
        result = self.run_cmake({})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('RESULT=historical.zip|historical-sha|FALSE', result.stdout)

    def test_current_input_and_spaces(self):
        result = self.run_cmake({ARCHIVE: str(self.archive), DIGEST: self.sha})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(f'RESULT={self.archive}|{self.sha}|TRUE', result.stdout)

    def test_uppercase_sha(self):
        self.assertEqual(self.run_cmake({ARCHIVE: str(self.archive),
            DIGEST: self.sha.upper()}).returncode, 0)

    def test_incomplete_or_empty_pair_rejected(self):
        for extra in ({ARCHIVE: str(self.archive)}, {DIGEST: self.sha},
                      {ARCHIVE: '', DIGEST: ''}):
            with self.subTest(extra=extra):
                self.assertNotEqual(self.run_cmake(extra).returncode, 0)

    def test_bad_digest_rejected(self):
        for sha in ('z' * 64, '1' * 63, self.sha + 'x'):
            with self.subTest(sha=sha):
                self.assertNotEqual(self.run_cmake({ARCHIVE: str(self.archive),
                    DIGEST: sha}).returncode, 0)

    def test_mismatch_never_deletes_input(self):
        result = self.run_cmake({ARCHIVE: str(self.archive), DIGEST: '0' * 64})
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('refusing release fallback', result.stderr)
        self.assertEqual(self.archive.read_bytes(), self.data)

    def test_non_file_or_relative_path_rejected(self):
        for path in ('relative.zip', str(self.root), str(self.root / 'absent.zip')):
            with self.subTest(path=path):
                self.assertNotEqual(self.run_cmake({ARCHIVE: path,
                    DIGEST: self.sha}).returncode, 0)

    def test_tampering_after_success_is_detected(self):
        extra = {ARCHIVE: str(self.archive), DIGEST: self.sha}
        self.assertEqual(self.run_cmake(extra).returncode, 0)
        self.archive.write_bytes(b'changed')
        self.assertNotEqual(self.run_cmake(extra).returncode, 0)
        self.assertEqual(self.archive.read_bytes(), b'changed')

if __name__ == '__main__':
    unittest.main()
