import struct
import tempfile
from pathlib import Path
import unittest
import zipfile

from verify_hap_native import verify

class NativePayloadTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.hap = self.root / 'entry-default-unsigned.hap'
        self.lib = self.root / 'libmpv.so'
        elf = bytearray(64)
        elf[:6] = b'\x7fELF\x02\x01'
        struct.pack_into('<HH', elf, 16, 3, 183)
        self.elf = bytes(elf)
        self.lib.write_bytes(self.elf)

    def package(self, payload=None, bridges=True, path='libs/arm64-v8a/libmpv.so'):
        with zipfile.ZipFile(self.hap, 'w') as z:
            z.writestr(path, self.elf if payload is None else payload)
            if bridges:
                for name in ('hdr', 'sw'):
                    z.writestr(f'libs/arm64-v8a/libmediakit_ohos_{name}.so', self.elf)

    def test_exact_library_and_both_bridges(self):
        self.package()
        result = verify(self.hap, self.lib)
        self.assertTrue(result['nativeLibraryMatchesCurrentBuild'])
        self.assertFalse(result['applicationPiliPlusBuilt'])
        self.assertEqual(result['devicePlayback'], 'not-run')

    def test_old_library_rejected(self):
        self.package(payload=self.elf + b'old build')
        with self.assertRaisesRegex(ValueError, 'different libmpv'):
            verify(self.hap, self.lib)

    def test_wrong_architecture_rejected(self):
        wrong = bytearray(self.elf)
        struct.pack_into('<H', wrong, 18, 62)
        self.package(payload=wrong)
        with self.assertRaisesRegex(ValueError, 'AArch64'):
            verify(self.hap, self.lib)

    def test_missing_bridge_rejected(self):
        self.package(bridges=False)
        with self.assertRaisesRegex(ValueError, 'Missing native bridge'):
            verify(self.hap, self.lib)

    def test_wrong_payload_path_rejected(self):
        self.package(path='libs/x86_64/libmpv.so')
        with self.assertRaisesRegex(ValueError, 'payload paths'):
            verify(self.hap, self.lib)

    def test_non_elf_rejected(self):
        self.package(payload=b'not native code')
        with self.assertRaisesRegex(ValueError, 'ELF64'):
            verify(self.hap, self.lib)

if __name__ == '__main__':
    unittest.main()
