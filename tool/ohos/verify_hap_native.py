#!/usr/bin/env python3
"""Verify the exact current-build libmpv is packaged as an ARM64 shared object.

This is a compile/provenance gate, never a playback/HDR certificate.
"""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import struct
import zipfile


def arm64_shared(data: bytes) -> None:
    if len(data) < 64 or data[:6] != b'\x7fELF\x02\x01':
        raise ValueError('Expected little-endian ELF64')
    kind, machine = struct.unpack_from('<HH', data, 16)
    if kind != 3 or machine != 183:
        raise ValueError('Expected AArch64 ET_DYN shared library')


def verify(hap: Path, library: Path) -> dict:
    expected = library.read_bytes()
    arm64_shared(expected)
    digest = hashlib.sha256(expected).hexdigest()
    with zipfile.ZipFile(hap) as archive:
        names = archive.namelist()
        if len(names) != len(set(names)):
            raise ValueError('Duplicate HAP member names')
        candidates = [n for n in names if Path(n).name in ('libmpv.so', 'libmpv.so.2')]
        if candidates != ['libs/arm64-v8a/libmpv.so']:
            raise ValueError(f'Unexpected libmpv payload paths: {candidates}')
        actual = archive.read(candidates[0])
        arm64_shared(actual)
        if hashlib.sha256(actual).hexdigest() != digest:
            raise ValueError('HAP contains a different libmpv than this build; investigate stripping or stale artifacts')
        bridges = {}
        for name in ('libmediakit_ohos_hdr.so', 'libmediakit_ohos_sw.so'):
            path = 'libs/arm64-v8a/' + name
            if path not in names:
                raise ValueError(f'Missing native bridge: {name}')
            data = archive.read(path)
            arm64_shared(data)
            bridges[path] = hashlib.sha256(data).hexdigest()
    return {'schema': 1, 'scope': 'SDK-direction-B-HAP-compilation-and-native-identity',
            'hap': hap.name, 'hapSha256': hashlib.sha256(hap.read_bytes()).hexdigest(),
            'abi': 'arm64-v8a', 'libmpvSha256': digest, 'bridgeSha256': bridges,
            'nativeLibraryMatchesCurrentBuild': True,
            'applicationPiliPlusBuilt': False, 'devicePlayback': 'not-run',
            'hdrDisplayVerification': 'not-run'}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('hap', type=Path)
    parser.add_argument('library', type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    result = verify(args.hap, args.library)
    args.output.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result, indent=2))
    return 0

if __name__ == '__main__':
    raise SystemExit(main())
