"""Verify downloaded Darwin build inputs against the SDK's declared archive.

This is byte/type/link integrity for T1, NOT proof that the binaries were built
from the latest mpv/FFmpeg sources. No archive is extracted by this verifier.
"""
from pathlib import Path, PurePosixPath
import hashlib
import os
import re
import stat
import tarfile


def digest(stream) -> str:
    result = hashlib.sha256()
    while chunk := stream.read(1024 * 1024):
        result.update(chunk)
    return result.hexdigest()


def checked_path(root: Path, relative: str) -> Path:
    path = root / relative
    if not path.parent.resolve(strict=True).is_relative_to(root.resolve(strict=True)):
        raise ValueError('Native input parent escaped root: ' + relative)
    return path


def check_file(root: Path, relative: str, size: int, checksum: str) -> dict:
    path = checked_path(root, relative)
    if not stat.S_ISREG(path.lstat().st_mode):
        raise ValueError('Expected regular native input: ' + relative)
    with path.open('rb') as source:
        if path.stat().st_size != size or digest(source) != checksum:
            raise ValueError('Native input differs from declared archive: ' + relative)
    return {'type': 'file', 'size': size, 'sha256': checksum}


def check_link(root: Path, relative: str, target: str) -> dict:
    path = checked_path(root, relative)
    if not path.is_symlink() or os.readlink(path) != target:
        raise ValueError('Native input link differs: ' + relative)
    if not path.resolve(strict=True).is_relative_to(root.resolve(strict=True)):
        raise ValueError('Native input link escaped root: ' + relative)
    return {'type': 'symlink', 'target': target}


def stripped_path(name: str) -> str | None:
    # Mirror tar --strip-components 1 without silently normalizing '..'.
    if name.startswith('/') or '\\' in name or '\x00' in name:
        raise ValueError('Unsafe native archive path')
    parts = name.rstrip('/').split('/')
    if any(p == '..' for p in parts):
        raise ValueError('Unsafe native archive path')
    parts = parts[1:]
    if not parts:
        return None
    if any(p in ('', '.', '..') for p in parts):
        raise ValueError('Ambiguous native archive path')
    return '/'.join(parts)


def verify_bundle(platform_root: Path, platform: str) -> dict:
    if platform not in ('ios', 'macos'):
        raise ValueError('Unsupported Darwin bundle platform')
    makefile = (platform_root / 'Makefile').read_bytes()
    text = makefile.decode('utf-8')
    versions = re.findall(r'^MPV_XCFRAMEWORKS_VERSION=([0-9.]+)$', text, re.M)
    hashes = re.findall(r'^MPV_XCFRAMEWORKS_SHA256SUM=([0-9a-f]{64})$', text, re.M)
    if len(versions) != 1 or len(hashes) != 1:
        raise ValueError('Ambiguous SDK archive declaration')
    name = f'libmpv-xcframeworks-{versions[0]}-{platform}-universal.tar.gz'
    archive_relative = '.cache/xcframeworks/' + name
    archive = checked_path(platform_root, archive_relative)
    if not stat.S_ISREG(archive.lstat().st_mode):
        raise ValueError('Native archive must be a regular file')
    with archive.open('rb') as source:
        if digest(source) != hashes[0]:
            raise ValueError('Native archive SHA-256 differs from SDK Makefile')
    records = {archive_relative: {'type': 'file', 'sha256': hashes[0], 'size': archive.stat().st_size}}
    link = f'.cache/xcframeworks/libmpv-xcframeworks-{platform}-universal.tar.gz'
    records[link] = check_link(platform_root, link, name)
    seen = set()
    with tarfile.open(archive, 'r:gz') as bundle:
        for member in bundle:
            relative = stripped_path(member.name)
            if relative is None:
                continue
            if relative in seen:
                raise ValueError('Duplicate native archive entry: ' + relative)
            seen.add(relative)
            target = 'Frameworks/' + relative
            path = checked_path(platform_root, target)
            if member.isdir():
                if not stat.S_ISDIR(path.lstat().st_mode):
                    raise ValueError('Native archive directory changed: ' + target)
            elif member.isfile():
                if member.size > 2 * 1024**3:
                    raise ValueError('Native archive member exceeds bound')
                with bundle.extractfile(member) as source:
                    checksum = digest(source)
                records[target] = check_file(platform_root, target, member.size, checksum)
                if bool(path.stat().st_mode & 0o111) != bool(member.mode & 0o111):
                    raise ValueError('Native archive executable mode changed: ' + target)
            elif member.issym():
                if member.linkname.startswith('/') or '\\' in member.linkname:
                    raise ValueError('Unsafe archive symlink: ' + target)
                records[target] = check_link(platform_root, target, member.linkname)
            else:
                raise ValueError('Unsupported native archive entry type: ' + target)
    mpv = platform_root / 'Frameworks/Mpv.xcframework'
    if not mpv.is_dir() or mpv.is_symlink():
        raise ValueError('Native archive missing Mpv.xcframework')
    for child in mpv.iterdir():
        if child.is_dir() and not child.is_symlink():
            fields = child.name.split('-')
            slug = '-'.join(fields[i] for i in (0, 2) if i < len(fields))
            relative = 'Frameworks/.symlinks/mpv/' + slug
            target = '../../Mpv.xcframework/' + child.name
            records[relative] = check_link(platform_root, relative, target)
    # No unlisted file may hide in an otherwise correctly downloaded directory.
    actual = set()
    for base in ('Frameworks', '.cache/xcframeworks'):
        for directory, dirs, files in os.walk(platform_root / base, followlinks=False):
            for name in dirs + files:
                path = Path(directory) / name
                if path.is_symlink() or path.is_file():
                    actual.add(path.relative_to(platform_root).as_posix())
    if actual != set(records):
        raise ValueError('Unexpected/missing native bundle files: ' + str(sorted(actual ^ set(records))[:20]))
    return {'archiveSha256': hashes[0], 'archiveVersion': versions[0],
            'makefileSha256': hashlib.sha256(makefile).hexdigest(), 'records': records,
            'scope': 'downloaded-input-byte-integrity-only', 'latestNativeSourceVerified': False}


def verify_sdk_bundles(sdk: Path, platform: str) -> dict:
    if platform not in ('ios', 'macos'):
        return {'records': {}, 'scope': 'not-applicable'}
    relative = f'libs/{platform}/media_kit_libs_{platform}_video/{platform}'
    result = verify_bundle(sdk / relative, platform)
    result['records'] = {relative + '/' + key: value for key, value in result['records'].items()}
    # Headers are downloaded by media_kit_video's separate common Makefile.
    from darwin_header_inputs import verify_sdk_headers
    headers = verify_sdk_headers(sdk, platform)
    result['records'].update(headers.pop('records'))
    result['headers'] = headers
    return result
