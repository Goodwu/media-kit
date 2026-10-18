"""Verify exact Flutter-generated Apple build configuration, not app patches.

Only the reviewed deployment-target migration and local engine podspec are
admitted. Neither arbitrary Xcode diffs nor arbitrary Ruby are accepted.
"""
from pathlib import Path
import hashlib
import re
import textwrap

GENERATORS = {
    'packages/flutter_tools/lib/src/ios/migrations/ios_deployment_target_migration.dart':
        '386ef482873fed86bec5f7b674bb098f756761b1',
    'packages/flutter_tools/lib/src/base/project_migrator.dart':
        '21550a04c005d2570f926c6ab8acceeb4f2f5f64',
    'packages/flutter_tools/bin/podhelper.rb':
        'f7308a6f86cbde214fd02c36b10c7b96cf378ee2',
}
IOS_CONFIG = ('ios/Runner.xcodeproj/project.pbxproj',
              'ios/Flutter/AppFrameworkInfo.plist', 'ios/Podfile')


def blob(data: bytes) -> str:
    return hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest()


def checked_bytes(path: Path, root: Path) -> bytes:
    if path.is_symlink() or not path.resolve(strict=True).is_relative_to(root.resolve(strict=True)) or not path.is_file():
        raise ValueError('Untrusted generated-file source: ' + str(path))
    return path.read_bytes()


def verify_generators(flutter: Path) -> None:
    for relative, expected in GENERATORS.items():
        if blob(checked_bytes(flutter / relative, flutter)) != expected:
            raise ValueError('Flutter generator changed; review required: ' + relative)


def migrate_ios_config(original: bytes) -> bytes:
    # Mirrors IOSDeploymentTargetMigration and ProjectMigrator. No filesystem
    # writes: compute the expected bytes from the original Git source instead.
    text = original.decode('utf-8')
    lines = text.splitlines()
    transformed = []
    for line in lines:
        for version in ('8.0', '9.0', '11.0', '12.0', '13.0', '14.0'):
            line = line.replace('IPHONEOS_DEPLOYMENT_TARGET = ' + version + ';',
                                'IPHONEOS_DEPLOYMENT_TARGET = 15.0;')
        for version in ('9.0', '11.0', '12.0', '13.0', '14.0'):
            line = line.replace("platform :ios, '" + version + "'", "platform :ios, '15.0'")
        transformed.append(line)
    migrated = ''.join(line + '\n' for line in transformed)
    for version in ('8.0', '9.0', '11.0', '12.0', '13.0', '14.0', '15.0'):
        migrated = migrated.replace('  <key>MinimumOSVersion</key>\n  <string>' + version + '</string>\n', '')
    return migrated.encode('utf-8')


def engine_podspec(helper: str) -> bytes:
    section = helper.split('def flutter_install_ios_engine_pod(', 1)[1]
    section = section.split('def flutter_install_macos_engine_pod(', 1)[0]
    blocks = re.findall(r'podspec\.write <<~EOF\n(.*?)^    EOF$', section, re.M | re.S)
    if len(blocks) != 1 or '#{' in blocks[0]:
        raise ValueError('Unexpected Flutter engine podspec template')
    return textwrap.dedent(blocks[0]).encode('utf-8')


def capture_apple_inputs(flutter: Path, originals: dict[str, bytes]) -> dict:
    verify_generators(flutter)
    configs = {}
    for relative in IOS_CONFIG:
        if relative not in originals:
            continue
        before = originals[relative]
        after = migrate_ios_config(before)
        configs[relative] = {'before': blob(before), 'after': blob(after),
                            'generator': 'Flutter IOSDeploymentTargetMigration'}
    podspec = engine_podspec((flutter / 'packages/flutter_tools/bin/podhelper.rb').read_text())
    return {'generators': GENERATORS, 'configurations': configs, 'newFiles': {
        'ios/Flutter/Flutter.podspec': {'sha256': hashlib.sha256(podspec).hexdigest(), 'size': len(podspec),
                                      'generator': 'Flutter flutter_install_ios_engine_pod'},
    }}


def is_generated_configuration(path: str, original_blob: str, actual: bytes, records: dict) -> bool:
    record = records.get(path)
    return record is not None and record['before'] == original_blob and record['after'] == blob(actual)


def verify_generated_apple(root: Path, path: str, record: dict) -> None:
    if path != 'ios/Flutter/Flutter.podspec':
        raise ValueError('Not an admitted generated Apple file: ' + path)
    data = checked_bytes(root / path, root)
    if len(data) != record['size'] or hashlib.sha256(data).hexdigest() != record['sha256']:
        raise ValueError('Flutter engine podspec does not match frozen generator: ' + path)
