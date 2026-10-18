"""Byte-exact macOS configuration migrations performed by the current Flutter SDK."""
from pathlib import Path
import re
from generated_apple import blob, checked_bytes

GENERATORS = {
    'packages/flutter_tools/lib/src/macos/migrations/macos_deployment_target_migration.dart':
        '9333ed69c2fe2901aa9fbdd8d8e436f361c69298',
    'packages/flutter_tools/lib/src/migrations/xcode_project_object_version_migration.dart':
        '75300a5ecc7cf8a97cd31993ee438dbd34d6e1fc',
    'packages/flutter_tools/lib/src/base/project_migrator.dart':
        '21550a04c005d2570f926c6ab8acceeb4f2f5f64',
}
MACOS_CONFIG = ('macos/Podfile', 'macos/Runner.xcodeproj/project.pbxproj',
               'macos/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme')


def verify_macos_generators(flutter: Path) -> None:
    for relative, expected in GENERATORS.items():
        if blob(checked_bytes(flutter / relative, flutter)) != expected:
            raise ValueError('Flutter macOS generator changed; review required: ' + relative)


def migrate_macos_config(path: str, original: bytes) -> bytes:
    if path not in MACOS_CONFIG:
        raise ValueError('Not a reviewed macOS configuration path')
    result = []
    for line in original.decode('utf-8').splitlines():
        if path.endswith(('Podfile', 'project.pbxproj')):
            for version in ('10.11', '10.13', '10.14', '10.15', '11.0'):
                line = line.replace('MACOSX_DEPLOYMENT_TARGET = ' + version + ';',
                                    'MACOSX_DEPLOYMENT_TARGET = 12.0;')
                line = line.replace("platform :osx, '" + version + "'", "platform :osx, '12.0'")
        if path.endswith(('project.pbxproj', 'Runner.xcscheme')):
            for pattern, replacement, threshold in (
                (r'objectVersion = (\d+);', 'objectVersion = 54;', 54),
                (r'LastUpgradeCheck = (\d+);', 'LastUpgradeCheck = 1510;', 1510),
                (r'LastUpgradeVersion = "(\d+)"', 'LastUpgradeVersion = "1510"', 1510),
            ):
                match = re.search(pattern, line)
                if match and int(match.group(1)) < threshold:
                    line = re.sub(pattern, replacement, line, count=1)
        result.append(line + '\n')
    return ''.join(result).encode('utf-8')


def capture_macos_inputs(flutter: Path, originals: dict[str, bytes]) -> dict:
    verify_macos_generators(flutter)
    return {'generators': GENERATORS, 'configurations': {
        path: {'before': blob(data), 'after': blob(migrate_macos_config(path, data)),
               'generator': 'Flutter MacOSDeploymentTargetMigration + XcodeProjectObjectVersionMigration'}
        for path, data in originals.items() if path in MACOS_CONFIG
    }, 'newFiles': {}}
