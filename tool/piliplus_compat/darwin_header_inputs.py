"""Check Darwin's separately downloaded libmpv headers, not native freshness.

The common Darwin Makefile downloads an SDK-declared archive and copies only
mpv-<tag>/libmpv/*.h to the platform Headers/mpv directory. Verify that exact
projection, the cached archive and its symlink; never exempt a directory.
"""
from pathlib import Path
import hashlib
import os
import re
import stat
import tarfile

from darwin_bundle_inputs import check_file, check_link, checked_path, digest


def _plain_directory(sdk: Path, relative: str) -> Path:
    current = sdk
    for component in relative.split('/'):
        current = current / component
        if not stat.S_ISDIR(current.lstat().st_mode):
            raise ValueError('Header input directory is not a real directory: ' + relative)
    return current


def _input_paths(root: Path, sdk: Path) -> set[str]:
    result = set()
    for directory, dirs, files in os.walk(root, followlinks=False):
        for name in dirs + files:
            path = Path(directory) / name
            mode = path.lstat().st_mode
            if stat.S_ISDIR(mode):
                continue
            if not (stat.S_ISREG(mode) or stat.S_ISLNK(mode)):
                raise ValueError('Unsupported header input type: ' + str(path))
            result.add(path.relative_to(sdk).as_posix())
    return result


def verify_sdk_headers(sdk: Path, platform: str) -> dict:
    if platform not in ('ios', 'macos'):
        raise ValueError('Unsupported Darwin header platform')
    sdk = sdk.resolve(strict=True)
    common = 'media_kit_video/common/darwin'
    makefile_path = checked_path(sdk, common + '/Makefile')
    if not stat.S_ISREG(makefile_path.lstat().st_mode):
        raise ValueError('Header Makefile is not a regular file')
    makefile = makefile_path.read_bytes()
    text = makefile.decode('utf-8')
    versions = re.findall(r'^MPV_HEADERS_VERSION=(v?[0-9]+(?:\.[0-9]+)+)$', text, re.M)
    hashes = re.findall(r'^MPV_HEADERS_SHA256SUM=([0-9a-f]{64})$', text, re.M)
    if len(versions) != 1 or len(hashes) != 1:
        raise ValueError('Ambiguous SDK header archive declaration')
    version, checksum = versions[0], hashes[0]
    cache = common + '/.cache/headers'
    output = f'media_kit_video/{platform}/Headers/mpv'
    _plain_directory(sdk, cache)
    _plain_directory(sdk, output)
    archive_name = f'mpv-{version}.tar.gz'
    relative_archive = cache + '/' + archive_name
    archive = checked_path(sdk, relative_archive)
    if not stat.S_ISREG(archive.lstat().st_mode):
        raise ValueError('Header archive is not a regular file')
    size = archive.stat().st_size
    if size > 256 * 1024**2:
        raise ValueError('Header archive exceeds size bound')
    with archive.open('rb') as source:
        if digest(source) != checksum:
            raise ValueError('Header archive SHA-256 differs from SDK Makefile')
    records = {relative_archive: {'type': 'file', 'size': size, 'sha256': checksum}}
    alias = cache + '/mpv.tar.gz'
    records[alias] = check_link(sdk, alias, archive_name)
    prefix = f'mpv-{version.removeprefix("v")}/libmpv/'
    headers = set()
    with tarfile.open(archive, 'r:gz') as bundle:
        for index, member in enumerate(bundle):
            if index >= 100000:
                raise ValueError('Header archive exceeds member bound')
            name = member.name
            if name.startswith('/') or '\\' in name or '\x00' in name or '..' in name.split('/'):
                raise ValueError('Unsafe header archive path')
            if not (name.startswith(prefix) and name.endswith('.h')):
                continue
            leaf = name[len(prefix):]
            if not re.fullmatch(r'[A-Za-z0-9_][A-Za-z0-9_.-]*\.h', leaf):
                raise ValueError('Ambiguous header archive projection: ' + name)
            if leaf in headers:
                raise ValueError('Duplicate header archive entry: ' + leaf)
            if not member.isfile() or member.size > 16 * 1024**2:
                raise ValueError('Unsupported header archive entry: ' + name)
            headers.add(leaf)
            relative = output + '/' + leaf
            with bundle.extractfile(member) as source:
                header_checksum = digest(source)
            records[relative] = check_file(sdk, relative, member.size, header_checksum)
            if bool((sdk / relative).stat().st_mode & 0o111) != bool(member.mode & 0o111):
                raise ValueError('Header executable mode differs: ' + relative)
    if not headers:
        raise ValueError('SDK archive contains no libmpv headers')
    actual = _input_paths(sdk / cache, sdk) | _input_paths(sdk / output, sdk)
    if actual != set(records):
        raise ValueError('Unexpected/missing header inputs: ' + str(sorted(actual ^ set(records))[:20]))
    return {'records': records, 'archiveVersion': version, 'archiveSha256': checksum,
            'makefileSha256': hashlib.sha256(makefile).hexdigest(),
            'scope': 'downloaded-header-byte-integrity-only',
            'latestNativeSourceVerified': False}
