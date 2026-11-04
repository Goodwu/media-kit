#!/usr/bin/env python3
"""Build the standalone LG PQ-encode LUT probe from current C source only.

This is not an APK builder. Existing Android test APKs must continue to use
tool/build-android-test.sh. This command neither deploys nor executes on a
device. Its only native dependencies are NDK OS platform stubs/runtime and a
host C toolchain for the CPU self-test.
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--ndk', type=Path, default=Path.home() / 'Library/Android/sdk/ndk/27.2.12479018')
    p.add_argument('--output', type=Path, help='New build directory (must not exist)')
    args = p.parse_args()
    stamp = dt.datetime.now(dt.timezone.utc).strftime('%Y%m%dT%H%M%SZ')
    output = (args.output or root / 'build' / f'lg-pq-lut-probe-{stamp}-{os.getpid()}').resolve()
    output.mkdir(parents=True, exist_ok=False)
    source = root / 'tool/native/lg_pq_lut_probe.c'
    tool = Path(__file__).resolve()
    ndk = args.ndk.resolve(strict=True)
    ndk_info = (ndk / 'source.properties').read_text()
    if '27.2.12479018' not in ndk_info:
        raise SystemExit('Refusing an unverified NDK revision; expected 27.2.12479018')
    bins = ndk / 'toolchains/llvm/prebuilt/darwin-x86_64/bin'
    cc = bins / 'aarch64-linux-android24-clang'
    readelf = bins / 'llvm-readelf'
    host_cc = shutil.which('clang')
    if not host_cc:
        raise SystemExit('Host clang is required for CPU boundary self-tests')
    receipt: dict = {
        'schemaVersion': 1, 'createdAtUTC': stamp,
        'purpose': 'Standalone PQ-encode LUT cost/accuracy probe; not an APK or playback acceptance',
        'source': str(source), 'sourceSha256': sha(source),
        'builder': str(tool), 'builderSha256': sha(tool),
        'ndk': str(ndk), 'ndkSourceProperties': ndk_info,
        'compilerDriver': str(cc), 'compilerDriverSha256': sha(cc),
        'commands': [], 'status': 'building', 'deviceDeployed': False, 'deviceRun': False,
        'dependencyBoundary': 'Only current diagnostic C plus NDK platform EGL/GLESv3/libm/libc '
                              'stubs/runtime; no project prebuilt input',
    }

    def save() -> None:
        (output / 'build-receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')

    def run(argv: list[str], name: str) -> subprocess.CompletedProcess:
        result = subprocess.run(argv, capture_output=True, text=True)
        (output / f'{name}.stdout.txt').write_text(result.stdout)
        (output / f'{name}.stderr.txt').write_text(result.stderr)
        receipt['commands'].append({'argv': argv, 'returncode': result.returncode, 'evidence': name})
        save()
        if result.returncode:
            raise RuntimeError(f'{name} failed; see {output / (name + ".stderr.txt")}')
        return result

    save()
    try:
        compiler_version = run([str(cc), '--version'], 'android-compiler-version')
        receipt['compilerVersion'] = compiler_version.stdout.strip()
        common = ['-std=c11', '-O2', '-DNDEBUG', '-Wall', '-Wextra', '-Werror']
        host_bin = output / 'pq-cpu-selftest'
        run([host_cc, *common, '-DLG_PQ_HOST_TEST=1', str(source), '-lm', '-o', str(host_bin)],
            'host-build')
        run([str(host_bin)], 'host-selftest')
        binary = output / 'lg_pq_lut_probe'
        run([str(cc), *common, '-fPIE', '-pie', '-Wl,--build-id=sha1', str(source),
             '-lEGL', '-lGLESv3', '-lm', '-o', str(binary)], 'android-build')
        elf = run([str(readelf), '-h', '-d', str(binary)], 'android-elf')
        if 'AArch64' not in elf.stdout or 'ELF64' not in elf.stdout or 'DYN' not in elf.stdout:
            raise RuntimeError('Output is not an AArch64 ELF64 PIE')
        if sha(source) != receipt['sourceSha256'] or sha(tool) != receipt['builderSha256']:
            raise RuntimeError('Diagnostic source or build recipe drifted during build')
        receipt.update(status='built-and-host-selftested', binary=str(binary),
                       binarySha256=sha(binary), binaryBytes=binary.stat().st_size,
                       hostSelftestPassed=True,
                       limitations=['No Android GPU execution was performed.',
                                    'Successful build/CPU tests do not establish GPU extension '
                                    'support, timer behavior, or LUT accuracy on device.'])
        save()
        print(json.dumps({'status': receipt['status'], 'output': str(output),
                          'binarySha256': receipt['binarySha256'], 'deviceRun': False}))
        return 0
    except Exception as error:
        receipt.update(status='failed', error=str(error))
        save()
        print(str(error), file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
