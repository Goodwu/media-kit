"""Exact generated Gradle-wrapper provenance, never a path-only exemption."""
from pathlib import Path
import hashlib
import os
import stat

WRAPPERS = ('gradlew', 'gradlew.bat', 'gradle/wrapper/gradle-wrapper.jar')


def _payload(path: Path, boundary: Path) -> bytes:
    if path.is_symlink() or not path.resolve(strict=True).is_relative_to(boundary.resolve(strict=True)):
        raise ValueError('Generated wrapper source escaped or is a symlink: ' + str(path))
    if not stat.S_ISREG(path.lstat().st_mode):
        raise ValueError('Generated wrapper must be a regular file: ' + str(path))
    return path.read_bytes()


def capture_gradle_wrappers(flutter: Path) -> dict:
    # Flutter GradleUtils.injectGradleWrapperIfNeeded copies precisely these
    # files from this cache directory; it does not overwrite existing files.
    cache = flutter / 'bin/cache/artifacts/gradle_wrapper'
    result = {}
    for relative in WRAPPERS:
        source = cache / relative
        data = _payload(source, flutter)
        result['android/' + relative] = {
            'source': str(source), 'sha256': hashlib.sha256(data).hexdigest(),
            'size': len(data), 'generator': 'Flutter GradleUtils.injectGradleWrapperIfNeeded',
        }
    return result


def verify_generated_wrapper(root: Path, relative: str, record: dict) -> None:
    if relative not in {'android/' + name for name in WRAPPERS}:
        raise ValueError('Not an admitted Gradle wrapper: ' + relative)
    data = _payload(root / relative, root)
    if len(data) != record['size'] or hashlib.sha256(data).hexdigest() != record['sha256']:
        raise ValueError('Generated wrapper differs from frozen Flutter cache: ' + relative)
    # Flutter's copy callback calls makeExecutable on each injected file.
    if os.name != 'nt' and not ((root / relative).stat().st_mode & 0o111):
        raise ValueError('Generated Gradle wrapper lost executable mode: ' + relative)
