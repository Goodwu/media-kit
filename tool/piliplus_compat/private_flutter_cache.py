"""Independent Flutter cache copy that preserves versioned framework structure."""
from pathlib import Path
import os
import shutil


def copy_flutter_cache(source: Path, destination: Path) -> dict:
    source = source.resolve(strict=True)
    if destination.exists() or destination.is_symlink():
        raise ValueError('Flutter cache destination already exists')
    links = {}
    # Do not traverse symlink directories; validate all targets before copying.
    for directory, dirs, files in os.walk(source, followlinks=False):
        for name in dirs + files:
            path = Path(directory) / name
            if not path.is_symlink():
                continue
            target = path.resolve(strict=True)  # cycles/dangling links fail
            if not target.is_relative_to(source):
                raise ValueError('Flutter cache link escapes source: ' + str(path))
            relative = path.relative_to(source)
            raw = os.readlink(path)
            links[relative.as_posix()] = {'originalTarget': raw,
                'targetWithinCache': target.relative_to(source).as_posix(),
                'targetIsDirectory': target.is_dir()}
    shutil.copytree(source, destination, symlinks=True)
    for relative, record in links.items():
        link = destination / relative
        if os.path.isabs(record['originalTarget']):
            link.unlink()
            target = destination / record['targetWithinCache']
            link.symlink_to(os.path.relpath(target, link.parent),
                            target_is_directory=record['targetIsDirectory'])
        if not link.is_symlink() or not link.resolve(strict=True).is_relative_to(destination.resolve()):
            raise ValueError('Flutter cache link did not remain private: ' + relative)
        record['privateTarget'] = os.readlink(link)
    return {'mode': 'independent-bytes-preserved-internal-symlinks',
            'linkCount': len(links), 'links': links}
