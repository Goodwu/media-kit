#!/usr/bin/env python3
"""Check the configured release JAR, not a latest-source build candidate.

Select by Gradle's destination ABI, not by a release asset's spelling. A
suffix such as -vkweak must not disable checksum or required marker checks.
No archive member is executed.
"""
from __future__ import annotations

import argparse
import hashlib
from pathlib import Path, PurePosixPath
import re
import subprocess
import tempfile
from urllib.parse import urlparse
import zipfile

MARKERS = (
    b'P5 direct external YUV sampler enabled', b'dovi rescale k=%.6f',
    b'dovi-p5-fast-path', b'dovi-p5-pipeline',
    b'Dolby Vision RPU export enabled',
)
ENTRY = re.compile(
    r'\[\s*"url"\s*:\s*"(?P<url>[^"]+)"\s*,\s*'
    r'"sha256"\s*:\s*"(?P<sha>[0-9a-f]{64})"\s*,\s*'
    r'"destination"\s*:\s*file\("(?P<destination>[^"]+)"\)\s*\]'
)


def release_arm64_identity(gradle: str) -> tuple[str, str]:
    # Restrict matches to actual one-line entries, not commented examples.
    entries = [m for line in gradle.splitlines()
               if not line.lstrip().startswith('//')
               for m in ENTRY.finditer(line)
               if PurePosixPath(m['destination']).name == 'default-arm64-v8a.jar']
    if len(entries) != 1:
        raise ValueError(f'Expected one arm64 release declaration, found {len(entries)}')
    url, sha = entries[0]['url'], entries[0]['sha']
    parsed = urlparse(url)
    if parsed.scheme != 'https' or parsed.username or parsed.password or not parsed.path.endswith('.jar'):
        raise ValueError('Invalid HTTPS release JAR URL')
    return url, sha


def verify_jar(jar: Path, expected: str) -> None:
    actual = hashlib.sha256(jar.read_bytes()).hexdigest()
    if actual != expected:
        raise ValueError(f'SHA256 mismatch: {actual} != {expected}')
    member = 'lib/arm64-v8a/libmpv.so'
    with zipfile.ZipFile(jar) as archive:
        if archive.namelist().count(member) != 1:
            raise ValueError('Expected exactly one arm64 libmpv.so')
        if archive.getinfo(member).file_size > 256 * 1024 * 1024:
            raise ValueError('Unexpectedly large libmpv.so')
        so = archive.read(member)
    missing = [m.decode() for m in MARKERS if m not in so]
    if missing:
        raise ValueError(f'libmpv.so missing version markers: {missing}')


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--gradle', type=Path, default=Path(
        'libs/android/media_kit_libs_android_video/android/build.gradle'))
    args = parser.parse_args()
    url, sha = release_arm64_identity(args.gradle.read_text(encoding='utf-8'))
    print(f'release_url={url}\nrelease_sha256={sha}', flush=True)
    with tempfile.TemporaryDirectory(prefix='routing-jar-identity-') as temp:
        jar = Path(temp) / 'arm64.jar'
        subprocess.run(['curl', '--fail', '--location', '--proto', '=https',
                        '--retry', '3', '--connect-timeout', '20', '--max-time', '300',
                        url, '--output', str(jar)], check=True)
        verify_jar(jar, sha)
    print('Release checksum and markers verified; NOT latest-native-source acceptance.')


if __name__ == '__main__':
    main()
