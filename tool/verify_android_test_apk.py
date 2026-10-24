#!/usr/bin/env python3
"""Bind the current native build receipt and JAR to a freshly built APK."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import zipfile


EXPECTED = {
    'lib/arm64-v8a/libmpv.so',
    'lib/arm64-v8a/libmediakitandroidhelper.so',
    'lib/arm64-v8a/libc++_shared.so',
}


def sha(data):
    return hashlib.sha256(data).hexdigest()


def ndk_stripped(data, strip_path):
    with tempfile.TemporaryDirectory(prefix='verify-apk-native-') as directory:
        target = Path(directory) / 'member.so'
        target.write_bytes(data)
        try:
            subprocess.run([str(strip_path), '--strip-unneeded', str(target)],
                           check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        except subprocess.CalledProcessError:
            return None
        return target.read_bytes()


def verify(apk_path, jar_path, candidate_path, output_path, required_marker=()):
    apk_path, jar_path = Path(apk_path), Path(jar_path)
    candidate_path, output_path = Path(candidate_path), Path(output_path)
    candidate = json.loads(candidate_path.read_text())
    packaging_path = jar_path.parent / 'packaging.json'
    packaging = json.loads(packaging_path.read_text())
    if candidate.get('status') != 'built-unreviewed' or candidate.get('sourceDrift'):
        raise ValueError('native source receipt is incomplete or reports source drift')
    if candidate.get('jarSha256') != sha(jar_path.read_bytes()):
        raise ValueError('JAR SHA-256 differs from the native source receipt')
    if packaging.get('status') not in ('packaged-unreviewed', 'verified'):
        raise ValueError('native packaging receipt is missing or failed')
    if packaging.get('jarSha256') != candidate['jarSha256']:
        raise ValueError('packaging receipt is not bound to this JAR')
    if set(packaging.get('members', {})) != EXPECTED:
        raise ValueError('native packaging receipt member set is unexpected')

    with zipfile.ZipFile(jar_path) as jar, zipfile.ZipFile(apk_path) as apk:
        jar_names = jar.namelist()
        apk_names = apk.namelist()
        for label, names in (('JAR', jar_names), ('APK', apk_names)):
            if len(names) != len(set(names)):
                raise ValueError(f'{label} has duplicate ZIP members')
        jar_native = {name for name in jar_names if name.startswith('lib/')}
        apk_native = {name for name in apk_names if name.startswith('lib/') and name.endswith('.so')}
        if jar_native != EXPECTED:
            raise ValueError(f'JAR native member set is unexpected: {sorted(jar_native)}')
        foreign_abi = sorted(name for name in apk_native
                             if len(name.split('/')) >= 3 and name.split('/')[1] != 'arm64-v8a')
        if foreign_abi:
            raise ValueError(f'APK contains native libraries for unexpected ABIs: {foreign_abi}')
        if not EXPECTED.issubset(apk_native):
            raise ValueError(f'APK is missing current JAR native members: {sorted(EXPECTED - apk_native)}')
        strip_tool = candidate.get('ndk', {}).get('tools', {}).get('llvm-strip', {})
        strip_path = Path(strip_tool.get('path', ''))
        if not strip_path.is_file() or sha(strip_path.read_bytes()) != strip_tool.get('sha256'):
            raise ValueError('selected NDK llvm-strip is missing or differs from native receipt')
        members = {}
        for name in sorted(EXPECTED):
            jar_bytes, apk_bytes = jar.read(name), apk.read(name)
            jar_hash = sha(jar_bytes)
            apk_hash = sha(apk_bytes)
            receipt_hash = packaging['members'][name].get('sha256')
            if jar_hash != receipt_hash:
                raise ValueError(f'JAR member differs from native packaging receipt: {name}')
            if apk_hash == jar_hash:
                packaging_mode = 'exact'
            elif apk_bytes == ndk_stripped(jar_bytes, strip_path):
                packaging_mode = 'ndk-strip-unneeded'
            else:
                raise ValueError(f'APK member differs from exact or canonical stripped JAR bytes: {name}')
            if name.endswith('/libmpv.so'):
                missing = [marker for marker in required_marker
                           if marker.encode() not in apk_bytes]
                if missing:
                    raise ValueError(f'final libmpv.so lacks required current-fork capabilities: {missing}')
            input_name = name.split('/')[-1]
            input_record = packaging.get('inputs', {}).get(input_name, {})
            if input_record.get('sha256') != jar_hash:
                raise ValueError(f'packaging input is not bound to final JAR member: {name}')
            input_path = input_record.get('path')
            if input_path and sha(Path(input_path).read_bytes()) != jar_hash:
                raise ValueError(f'packaging input file differs from JAR member: {name}')
            if name.endswith('/libmpv.so') and not input_path:
                raise ValueError('native receipt does not bind libmpv.so to the current build output')
            if name.endswith('/libc++_shared.so') and not input_path:
                raise ValueError('native receipt does not bind libc++_shared.so to the selected NDK')
            helper_apk = input_record.get('apk')
            helper_member = input_record.get('member')
            if helper_apk:
                with zipfile.ZipFile(helper_apk) as helper_zip:
                    if sha(helper_zip.read(helper_member)) != jar_hash:
                        raise ValueError('helper staging APK differs from final JAR member')
            if name.endswith('/libmediakitandroidhelper.so') and not helper_apk:
                raise ValueError('native receipt does not bind the freshly built helper')
            members[name] = {'sha256': apk_hash, 'bytes': len(apk_bytes),
                             'packagingMode': packaging_mode}

    result = {
        'schemaVersion': 1,
        'status': 'verified',
        'apk': str(apk_path.resolve()),
        'apkSha256': sha(apk_path.read_bytes()),
        'apkBytes': apk_path.stat().st_size,
        'nativeCandidate': str(candidate_path.resolve()),
        'jar': str(jar_path.resolve()),
        'jarSha256': candidate['jarSha256'],
        'members': members,
        'abiPolicy': 'arm64-v8a only',
        'requiredMarkers': list(required_marker),
        'stripTool': {'path': str(strip_path), 'sha256': strip_tool['sha256']},
        'sourceInputs': {
            name: {'head': source.get('head'), 'tree': source.get('tree'),
                   'sha256': source.get('sha256'), 'status': source.get('status')}
            for name, source in candidate.get('sourcesBefore', {}).items()
        },
    }
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(result, indent=2, sort_keys=True) + '\n')
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apk', required=True, type=Path)
    parser.add_argument('--jar', required=True, type=Path)
    parser.add_argument('--candidate', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--require-marker', action='append', default=[])
    args = parser.parse_args()
    try:
        result = verify(args.apk, args.jar, args.candidate, args.output,
                        required_marker=args.require_marker)
        print(json.dumps(result, sort_keys=True))
    except (OSError, ValueError, KeyError, zipfile.BadZipFile,
            json.JSONDecodeError, subprocess.SubprocessError) as error:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps({
            'schemaVersion': 1,
            'status': 'failed',
            'apk': str(args.apk),
            'jar': str(args.jar),
            'nativeCandidate': str(args.candidate),
            'requiredMarkers': args.require_marker,
            'error': str(error),
        }, indent=2, sort_keys=True) + '\n')
        parser.exit(1, f'APK native verification failed: {error}\n')


if __name__ == '__main__':
    main()
