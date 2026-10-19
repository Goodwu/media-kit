#!/usr/bin/env python3
"""Build direction B in isolated application copies; never call this zero-patch T1."""
from __future__ import annotations
import argparse
import json
from pathlib import Path
import subprocess
import sys

from build_original import clone_exact, tracked_manifest, verify_tracked, write_json
from dependency_plan import AuditError, identity
from direction_b_inputs import apply_direction_b


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app-root', type=Path, required=True)
    parser.add_argument('--sdk-root', type=Path, required=True)
    parser.add_argument('--flutter-root', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--platform', choices=('android', 'ios', 'macos', 'windows', 'linux'), required=True)
    args = parser.parse_args(argv)
    out = args.output.resolve()
    if out.exists():
        raise AuditError('Direction B requires a new output directory')
    app_id, sdk_id = identity(args.app_root), identity(args.sdk_root)
    for root in (Path(app_id['root']), Path(sdk_id['root']), args.flutter_root.resolve()):
        if out == root or out.is_relative_to(root) or root.is_relative_to(out):
            raise AuditError('Direction B output overlaps an input checkout')
    out.mkdir(parents=True)
    receipt = {'scope': 'T1B player-integration build', 'zeroPatch': False,
               'inputs': {'application': app_id, 'sdk': sdk_id},
               'status': 'running', 'platform': args.platform,
               'nativeSourceFreshness': 'not-verified', 'deviceAcceptance': 'not-run'}
    def save(): write_json(out / 'direction-b-receipt.json', receipt)
    save()
    code = 1
    try:
        app = out / 'integration-app'
        clone_exact(Path(app_id['root']), app, app_id['commit'])
        baseline = tracked_manifest(app)
        verify_tracked(app, baseline)
        write_json(out / 'original-app-source-manifest.json', baseline)
        receipt['integration'] = apply_direction_b(app, Path(sdk_id['root']), out)
        save()
        # Reuse the existing strict builder, but clearly identify this derivative
        # as its input. Its default zero-patch lane is unchanged and separate.
        command = [sys.executable, str(Path(__file__).with_name('build_original.py')),
                   '--app-root', str(app), '--sdk-root', sdk_id['root'],
                   '--flutter-root', str(args.flutter_root.resolve()),
                   '--out', str(out / 'validation'), '--platform', args.platform]
        code = subprocess.run(command, check=False).returncode
        receipt['buildExitCode'] = code
        receipt['status'] = 'passed' if code == 0 else 'failed'
        if identity(args.app_root) != app_id or identity(args.sdk_root) != sdk_id:
            raise AuditError('An original input checkout changed')
        receipt['originalInputCheckoutsUnchanged'] = True
        return code
    except Exception as error:
        receipt['status'] = 'failed'
        receipt['error'] = str(error)
        raise
    finally:
        save()


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except (AuditError, OSError, ValueError) as error:
        print(f'Direction B build failed: {error}', file=sys.stderr)
        raise SystemExit(1)
