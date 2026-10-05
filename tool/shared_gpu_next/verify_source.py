#!/usr/bin/env python3
"""Verify the entire prepared source, including unchanged pinned baseline files."""
import argparse
import hashlib
import json
from pathlib import Path
import tarfile


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def verify(archive_path, source):
    here = Path(__file__).resolve().parent
    manifest = json.loads((here / 'manifest.json').read_text())
    required = {'meson.build', 'video/out/libmpv.h', 'video/out/vo_gpu_next.c', 'video/out/vo_libmpv.c'}
    required.update('video/out/gpu_next/' + name + suffix
        for name in ('frame', 'hwdec', 'libmpv_gl_pl', 'libmpv_gpu_next', 'renderer', 'target')
        for suffix in ('.c', '.h'))
    if set(manifest['files']) != required:
        raise ValueError('manifest must cover the complete 16-file shared core')
    if digest(archive_path) != manifest['base_archive_sha256']:
        raise ValueError('baseline archive checksum mismatch')
    if digest(here / 'mpv-0.41-shared-core.patch') != manifest['patch_sha256']:
        raise ValueError('shared patch checksum mismatch')
    expected = {}
    with tarfile.open(archive_path) as archive:
        for member in archive:
            relative = Path(member.name).relative_to(manifest['base'])
            if '..' in relative.parts or relative.is_absolute():
                raise ValueError('unsafe archive path')
            if member.isfile():
                if relative.as_posix() in expected:
                    raise ValueError('duplicate archive file')
                stream = archive.extractfile(member)
                expected[relative.as_posix()] = hashlib.sha256(stream.read()).hexdigest()
            elif not member.isdir():
                raise ValueError('unsupported archive entry')
    for name, hashes in manifest['files'].items():
        if expected.get(name) != hashes['before']:
            raise ValueError('baseline manifest mismatch: ' + name)
        expected[name] = hashes['after']
    actual = {}
    for path in source.rglob('*'):
        if path.is_symlink():
            raise ValueError('source symlink forbidden: ' + str(path))
        if path.is_file():
            actual[path.relative_to(source).as_posix()] = digest(path)
        elif not path.is_dir():
            raise ValueError('unsupported source entry: ' + str(path))
    if actual != expected:
        changed = sorted(name for name in actual.keys() | expected.keys()
                         if actual.get(name) != expected.get(name))
        raise ValueError('prepared source differs from pinned tree: ' + ', '.join(changed[:10]))
    canonical = json.dumps(actual, sort_keys=True, separators=(',', ':')).encode()
    return {'source_tree_sha256': hashlib.sha256(canonical).hexdigest(),
            'file_count': len(actual), 'base_archive_sha256': digest(archive_path),
            'manifest_sha256': digest(here / 'manifest.json'),
            'patch_sha256': manifest['patch_sha256']}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('archive', type=Path)
    parser.add_argument('source', type=Path)
    args = parser.parse_args()
    try:
        print(json.dumps(verify(args.archive, args.source), indent=2))
    except (ValueError, OSError) as error:
        parser.error(str(error))


if __name__ == '__main__':
    main()
