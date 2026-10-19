#!/usr/bin/env python3
"""Check current direction-B application against real OHOS Flutter, without porting it.

A successful pub get is not a HAP build. Missing OHOS host or resolution failure
makes this gate fail. Never rewrite SDK constraints or substitute PiliPlusX.
"""
from __future__ import annotations
import argparse
import json
from pathlib import Path
import subprocess
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'piliplus_compat'))
from build_original import clone_exact, write_json, verify_managed
from dependency_plan import identity, manifests_at_head, package_catalog, build_plan
from direction_b_inputs import apply_direction_b
import yaml


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app-root', type=Path, required=True)
    parser.add_argument('--sdk-root', type=Path, required=True)
    parser.add_argument('--flutter', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    app_id, sdk_id = identity(args.app_root), identity(args.sdk_root)
    out = args.output.resolve()
    for root in (args.app_root.resolve(), args.sdk_root.resolve()):
        if out == root or out.is_relative_to(root) or root.is_relative_to(out):
            raise ValueError('Preflight output overlaps a source checkout')
    out.mkdir(parents=True, exist_ok=False)
    receipt = {'schema': 1, 'scope': 'current-PiliPlus-direction-B-OHOS-prerequisites',
               'inputs': {'app': app_id, 'sdk': sdk_id}, 'status': 'failed',
               'applicationCompile': 'not-run', 'devicePlayback': 'not-run',
               'requirementsRelaxed': False}
    try:
        version = subprocess.run([str(args.flutter), '--version', '--machine'],
                                 text=True, capture_output=True, timeout=300)
        (out / 'flutter-version.log').write_text(version.stdout + version.stderr)
        version.check_returncode()
        receipt['flutter'] = json.loads(version.stdout)
        app = out / 'application'
        clone_exact(Path(app_id['root']), app, app_id['commit'])
        receipt['integration'] = apply_direction_b(app, Path(sdk_id['root']), out)
        app_files = manifests_at_head(identity(app))
        sdk_files = manifests_at_head(sdk_id)
        app_spec = app_files['pubspec.yaml']['data']
        receipt['applicationEnvironment'] = app_spec.get('environment', {})
        receipt['ohosHostPresent'] = (app / 'ohos/entry/src/main/module.json5').is_file()
        plan = build_plan(app_spec,
                         app_files.get('pubspec_overrides.yaml', {'data': {}})['data'],
                         package_catalog(sdk_files), Path(sdk_id['root']))
        write_json(out / 'dependency-plan.json', plan)
        if any(b['kind'] != 'unresolved-override-only' for b in plan['blockers']):
            raise ValueError('Missing required SDK package in dependency plan')
        (app / 'pubspec_overrides.yaml').write_text(yaml.safe_dump(plan['overrideDocument']))
        with (out / 'pub-get.log').open('w') as log:
            result = subprocess.run([str(args.flutter), 'pub', 'get'], cwd=app,
                                    stdout=log, stderr=subprocess.STDOUT, timeout=600)
        receipt['pubGetExitCode'] = result.returncode
        if result.returncode:
            raise ValueError('OHOS Flutter rejected the unchanged application dependency constraints; see pub-get.log')
        receipt['resolution'] = verify_managed(plan, app / '.dart_tool/package_config.json',
                                               app, Path(sdk_id['root']))
        if not receipt['ohosHostPresent']:
            raise ValueError('Current application has no OHOS host; broader host/plugin port needs review')
        # This script is deliberately NOT a compiler; don't manufacture a green
        # application-build status even when both prerequisites are available.
        receipt['status'] = 'prerequisites-passed'
        return 0
    except Exception as error:
        receipt['error'] = str(error)
        print(f'OHOS application prerequisite gate failed: {error}', file=sys.stderr)
        return 1
    finally:
        receipt['originalInputCheckoutsUnchanged'] = (
            identity(args.app_root) == app_id and identity(args.sdk_root) == sdk_id)
        write_json(out / 'application-preflight.json', receipt)
        print(json.dumps(receipt, indent=2))

if __name__ == '__main__':
    raise SystemExit(main())
