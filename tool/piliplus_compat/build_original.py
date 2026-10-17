#!/usr/bin/env python3
"""Build an unmodified PiliPlus checkout against this media-kit checkout.

All writes occur in a new isolated directory. T1 compilation evidence is NOT
native-source freshness, feature parity, routing verification, or device proof.
A failed prerequisite stays failed; no compiler-error baseline is accepted.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import stat
import subprocess
import sys
import time
from urllib.parse import urljoin, urlsplit
from urllib.request import url2pathname

import yaml

from dependency_plan import (AuditError, build_plan, git, identity,
                             managed, manifests_at_head, package_catalog,
                             parse_manifest)

# Reviewed upstream recipe; a changed recipe requires review, not executing an
# arbitrary PowerShell program with access to the runner's global SDK/cache.
PATCH_RECIPE_BLOB = '06efc7792edf6d37c9b9799ac78681fc86b50093'
FRAMEWORK_PATCHES = (
    'modal_barrier', 'text_selection', 'mouse_cursor', 'image_anim',
    'layout_builder', 'navigation_drawer', 'popup_menu', 'fab',
    'null_safety_for_selectable_region', 'selectable_region', 'editable_text',
    'text_field', 'scroll_position', 'scrollable', 'scrollable_gesture',
    'draggable_scrollable_sheet', 'scaffold', 'text', 'text_painter', 'sliver',
    'refresh_indicator', 'double_tap_gesture',
)
MATERIAL_PATCHES = ('modal_barrier_material', 'navigation_drawer', 'popup_menu',
                    'fab', 'text_field', 'scaffold', 'refresh_indicator', 'tabs')
PLATFORM_FRAMEWORK = {
    'android': ('bottom_sheet_android', 'scroll_view', 'navigator'),
    'ios': ('scroll_view', 'bottom_sheet_ios_flutter', 'navigator'),
}
PLATFORM_MATERIAL = {
    'android': ('bottom_sheet_android',),
    'ios': ('bottom_sheet_ios_flutter_material',),
}
# Only generated root lock/overlay may differ. Platform-generated sources are
# recorded separately, NOT broadly exempted by extension or directory name.
GENERATED_TRACKED = frozenset({
    'pubspec.lock', 'pubspec_overrides.yaml',
    'android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java',
    'linux/flutter/generated_plugin_registrant.cc',
    'linux/flutter/generated_plugin_registrant.h',
    'linux/flutter/generated_plugins.cmake',
    'windows/flutter/generated_plugin_registrant.cc',
    'windows/flutter/generated_plugin_registrant.h',
    'windows/flutter/generated_plugins.cmake',
    'macos/Flutter/GeneratedPluginRegistrant.swift',
    'ios/Runner/GeneratedPluginRegistrant.h',
    'ios/Runner/GeneratedPluginRegistrant.m',
    'ios/Podfile.lock', 'macos/Podfile.lock',
})


def write_json(path: Path, value: dict) -> None:
    temporary = path.with_suffix(path.suffix + '.tmp')
    temporary.write_text(json.dumps(value, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
    temporary.replace(path)


def blob_digest(data: bytes) -> str:
    return hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest()


def tracked_manifest(root: Path) -> dict:
    result = {}
    for record in git(root, 'ls-tree', '-rz', '--full-tree', 'HEAD').split(b'\0'):
        if not record:
            continue
        meta, raw_path = record.split(b'\t', 1)
        mode, kind, sha = meta.decode().split()
        path = raw_path.decode('utf-8')
        parts = PurePosixPath(path).parts
        if kind != 'blob' or mode not in ('100644', '100755', '120000'):
            raise AuditError(f'Unsupported Git tree entry: {path} ({mode})')
        if path.startswith('/') or any(p in ('..', '.git') for p in parts) or '\\' in path:
            raise AuditError(f'Unsafe tree path: {path}')
        result[path] = {'mode': mode, 'blob': sha}
    return result


def symlink_payload(target: str, *, windows: bool) -> bytes:
    # Windows exposes path separators using its OS spelling. This is a link
    # representation normalization, not a normalization of ordinary file data.
    # Absolute/UNC prefixes are retained and cannot match a relative Git blob.
    return os.fsencode(target.replace('\\', '/') if windows else target)


def checked_payload(root: Path, relative: str, mode: str) -> bytes:
    path = root / relative
    # No parent can redirect an original file outside the staged tree.
    if not path.parent.resolve(strict=True).is_relative_to(root.resolve()):
        raise AuditError(f'Source parent escaped staging: {relative}')
    info = path.lstat()
    if mode == '120000':
        if not stat.S_ISLNK(info.st_mode):
            raise AuditError(f'Expected source symlink: {relative}')
        if not path.resolve().is_relative_to(root.resolve()):
            raise AuditError(f'Source symlink escaped staging: {relative}')
        return symlink_payload(os.readlink(path), windows=os.name == 'nt')
    if not stat.S_ISREG(info.st_mode):
        raise AuditError(f'Expected regular source file: {relative}')
    if os.name != 'nt' and bool(info.st_mode & 0o111) != (mode == '100755'):
        raise AuditError(f'Source executable mode changed: {relative}')
    return path.read_bytes()


def verify_tracked(root: Path, manifest: dict, allowed=frozenset()) -> dict:
    generated, violations = {}, []
    for path, record in manifest.items():
        try:
            data = checked_payload(root, path, record['mode'])
            actual = blob_digest(data)
            if actual != record['blob']:
                if path not in allowed:
                    violations.append(f'{path} (expected {record["blob"]}, actual {actual})')
                else:
                    generated[path] = {'before': record['blob'], 'after': actual}
        except (OSError, AuditError) as error:
            violations.append(f'{path}: {error}')
    if violations:
        raise AuditError('Original source/type/mode changed: ' + ', '.join(violations[:20]))
    return {'trackedFiles': len(manifest), 'generatedChanges': generated,
            'originalSourceUnchanged': True}



def verify_added(root: Path, *, app=False, package_paths=()) -> dict:
    prefixes = ['.dart_tool/', 'build/'] if app else []
    files = set(GENERATED_TRACKED) | {
        '.flutter-plugins', '.flutter-plugins-dependencies',
        'android/local.properties', 'ios/Flutter/Generated.xcconfig',
        'ios/Flutter/flutter_export_environment.sh',
    } if app else set()
    if app:
        prefixes += ['android/.gradle/', 'android/.kotlin/', 'android/app/.cxx/',
                     'ios/Pods/', 'ios/.symlinks/', 'ios/Flutter/ephemeral/',
                     'macos/Pods/', 'macos/.symlinks/', 'macos/Flutter/ephemeral/',
                     'windows/flutter/ephemeral/', 'linux/flutter/ephemeral/']
    else:
        for package in package_paths:
            prefixes += [package + '/' + suffix for suffix in (
                '.dart_tool/', 'build/', 'android/.cxx/', 'android/.gradle/',
                'android/build/', 'linux/ephemeral/', 'windows/ephemeral/')]
    added = [p for p in git(root, 'ls-files', '--others', '-z').decode().split('\0') if p]
    rejected = [p for p in added if p not in files and not any(p.startswith(prefix) for prefix in prefixes)]
    if rejected:
        raise AuditError('Unexpected new source/input: ' + ', '.join(rejected[:20]))
    return {'generatedFileCount': len(added), 'unexpectedNewInputs': []}

def clone_exact(source: Path, destination: Path, commit: str) -> None:
    subprocess.run(['git', 'clone', '--no-hardlinks', '--no-checkout', '--',
                    str(source), str(destination)], check=True, capture_output=True)
    git(destination, 'config', 'core.autocrlf', 'false')
    git(destination, 'config', 'core.longpaths', 'true')
    git(destination, 'config', 'core.symlinks', 'true')
    git(destination, 'checkout', '--detach', commit)
    if git(destination, 'rev-parse', 'HEAD').decode().strip() != commit:
        raise AuditError('Staged checkout is not the requested commit')


def local_uri(base_file: Path, uri: str, *, must_exist: bool = True) -> Path:
    url = urlsplit(urljoin(base_file.resolve().as_uri(), uri))
    if url.scheme != 'file' or url.netloc not in ('', 'localhost') or url.query or url.fragment:
        raise AuditError('Expected a local file URI')
    return Path(url2pathname(url.path)).resolve(strict=must_exist)


def resolution_roots(config_file: Path) -> dict[str, Path]:
    value = json.loads(config_file.read_text(encoding='utf-8'))
    if value.get('configVersion') != 2 or not isinstance(value.get('packages'), list):
        raise AuditError('Unsupported package_config')
    roots = {}
    for row in value['packages']:
        name = row.get('name')
        if not isinstance(name, str) or name in roots or not isinstance(row.get('rootUri'), str):
            raise AuditError('Invalid/duplicate package_config entry')
        root = local_uri(config_file, row['rootUri'])
        lib_uri = row.get('packageUri', 'lib/')
        if not isinstance(lib_uri, str):
            raise AuditError('Invalid packageUri')
        # Native-only federated plugins can legitimately have no Dart lib/ directory.
        # Resolve existing symlinks but do not require the leaf to exist.
        lib = local_uri(root / '.package-root', lib_uri, must_exist=False)
        if lib != root / 'lib':
            raise AuditError(f'Package library escaped its lib/: {name}')
        roots[name] = root
    return roots


def verify_managed(plan: dict, config_file: Path, app_root: Path, sdk_root: Path) -> dict:
    roots = resolution_roots(config_file)
    required = set(plan['requiredPackages']) | {plan['applicationName']}
    if not required <= roots.keys():
        raise AuditError('Required packages are absent after pub get')
    for name, root in roots.items():
        if name == plan['applicationName']:
            expected = app_root
        elif managed(name):
            if name not in plan['packages']:
                raise AuditError(f'Unplanned/old managed package was resolved: {name}')
            expected = sdk_root / plan['packages'][name]['path']
        else:
            continue
        if root != expected.resolve(strict=True):
            raise AuditError(f'Package root does not match source checkout: {name}')
    omitted = [b['package'] for b in plan['blockers'] if b['kind'] == 'unresolved-override-only']
    if set(omitted) & roots.keys():
        raise AuditError('An omitted override-only package is reachable')
    overlay = parse_manifest((app_root / 'pubspec_overrides.yaml').read_text(encoding='utf-8'))
    if overlay != plan['overrideDocument']:
        raise AuditError('Root overrides changed during resolution')
    return {'status': 'verified', 'omittedOverrideOnlyProvenAbsent': omitted,
            'managedRoots': {n: str(p) for n, p in roots.items() if managed(n)},
            'packageConfigSha256': hashlib.sha256(config_file.read_bytes()).hexdigest()}


class Runner:
    def __init__(self, output: Path):
        self.output = output
        self.receipt = {'schemaVersion': 1, 'scope': 'T1-original-app-compilation',
                        'status': 'running', 'steps': [], 'patches': [],
                        'nativeSourceFreshness': 'not-verified',
                        'featureParity': 'not-run', 'automaticRouting': 'not-run',
                        'devicePlayback': 'not-run', 'hdrVerification': 'not-run'}
        self.env = os.environ.copy()
        self.env['PUB_CACHE'] = str(output / 'pub-cache')
        self.env['CI'] = 'true'
        self.save()

    def save(self):
        write_json(self.output / 'build-receipt.json', self.receipt)

    def run(self, name: str, argv: list[str], cwd: Path, *, required=True, timeout=2400) -> int:
        log = self.output / (name + '.log')
        row = {'name': name, 'command': [str(a) for a in argv], 'cwd': str(cwd),
               'log': log.name, 'status': 'running'}
        self.receipt['steps'].append(row)
        self.save()
        print(f'=== {name}: {argv} ===', flush=True)
        start = time.monotonic()
        with log.open('w', encoding='utf-8') as stream:
            try:
                result = subprocess.run(argv, cwd=cwd, env=self.env, stdout=stream,
                                        stderr=subprocess.STDOUT, timeout=timeout)
                code = result.returncode
            except subprocess.TimeoutExpired:
                stream.write('\nCOMMAND TIMEOUT\n')
                code = 124
            except OSError as error:
                stream.write(str(error) + '\n')
                code = 127
        row.update(exitCode=code, seconds=round(time.monotonic() - start, 3),
                   status='passed' if code == 0 else 'failed')
        self.save()
        text = log.read_text(encoding='utf-8', errors='replace')
        # Full logs are artifacts; bounded tail keeps Actions API reads useful.
        print(text[-24000:], flush=True)
        if required and code:
            raise AuditError(f'{name} failed with exit {code}; see {log.name}')
        return code

    def apply(self, target: Path, patch: Path, label: str):
        data = patch.read_bytes()
        self.receipt['patches'].append({'target': str(target), 'input': str(patch),
                                       'sha256': hashlib.sha256(data).hexdigest()})
        self.run('patch-' + label, ['git', 'apply', '--check', str(patch)], target)
        self.run('apply-' + label, ['git', 'apply', str(patch)], target)


def execute(args, runner: Runner) -> None:
    out = runner.output
    app_id, sdk_id = identity(args.app_root), identity(args.sdk_root)
    runner.receipt['inputs'] = {'app': app_id, 'sdk': sdk_id}
    runner.save()
    app, sdk = out / 'app', out / 'sdk'
    clone_exact(Path(app_id['root']), app, app_id['commit'])
    clone_exact(Path(sdk_id['root']), sdk, sdk_id['commit'])
    app_manifest, sdk_manifest = tracked_manifest(app), tracked_manifest(sdk)
    verify_tracked(app, app_manifest)
    verify_tracked(sdk, sdk_manifest)
    write_json(out / 'app-source-manifest.json', app_manifest)
    write_json(out / 'sdk-source-manifest.json', sdk_manifest)
    app_files = manifests_at_head(identity(app))
    catalog = package_catalog(manifests_at_head(identity(sdk)))
    app_spec = app_files['pubspec.yaml']['data']
    overlay = app_files.get('pubspec_overrides.yaml', {'data': {}})['data']
    plan = build_plan(app_spec, overlay, catalog, sdk)
    plan['applicationName'] = app_spec['name']
    write_json(out / 'dependency-plan.json', plan)
    if any(b['kind'] == 'missing-required-package' for b in plan['blockers']):
        raise AuditError('A required managed SDK package is missing')
    # This is a resolution experiment, not a declaration-level success. Keep
    # every blocker in the receipt until actual pub proves omission harmless.
    (app / 'pubspec_overrides.yaml').write_text(
        yaml.safe_dump(plan['overrideDocument'], sort_keys=True), encoding='utf-8')
    if git(app, 'rev-parse', 'HEAD:lib/scripts/patch.ps1').decode().strip() != PATCH_RECIPE_BLOB:
        raise AuditError('Upstream patch recipe changed; review it before building')
    runner.receipt['upstreamAppPatchesNotApplied'] = [
        'bottom_sheet_ios_piliplus.patch', 'geetest_ios.patch'] if args.platform == 'ios' else []
    original_flutter = args.flutter_root.resolve(strict=True)
    flutter_id = git(original_flutter, 'rev-parse', 'HEAD').decode().strip()
    flutter = out / 'flutter'
    clone_exact(original_flutter, flutter, flutter_id)
    # Copy, never link, mutable cache state into this per-run SDK.
    if (original_flutter / 'bin/cache').exists():
        shutil.copytree(original_flutter / 'bin/cache', flutter / 'bin/cache', symlinks=False)
    executable = str(flutter / 'bin' / ('flutter.bat' if os.name == 'nt' else 'flutter'))
    runner.env['FLUTTER_ROOT'] = str(flutter)
    runner.env['PATH'] = str(flutter / 'bin') + os.pathsep + runner.env.get('PATH', '')
    runner.receipt['flutter'] = {'commit': flutter_id, 'root': str(flutter),
                                 'requested': app_spec.get('environment', {}).get('flutter')}
    for name in FRAMEWORK_PATCHES + PLATFORM_FRAMEWORK.get(args.platform, ()):
        runner.apply(flutter, app / 'lib/scripts' / (name + '.patch'), 'flutter-' + name)
    runner.run('flutter-version', [executable, '--version', '--machine'], app)
    runner.run('pub-get', [executable, 'pub', 'get'], app)
    runner.receipt['resolution'] = verify_managed(plan, app / '.dart_tool/package_config.json', app, sdk)
    roots = resolution_roots(app / '.dart_tool/package_config.json')
    for name in MATERIAL_PATCHES + PLATFORM_MATERIAL.get(args.platform, ()):
        runner.apply(roots['material_ui'], app / 'lib/scripts/material' / (name + '.patch'), 'material-' + name)
    if args.platform == 'ios':
        runner.apply(roots['cupertino_ui'], app / 'lib/scripts/cupertino/bottom_sheet_ios_flutter.patch', 'cupertino-ios')
    verify_added(app, app=True)
    verify_added(sdk, package_paths=[p['path'] for p in plan['packages'].values()])
    runner.receipt['sourceGuardBeforeBuild'] = {
        'app': verify_tracked(app, app_manifest, GENERATED_TRACKED),
        'sdk': verify_tracked(sdk, sdk_manifest),
    }
    runner.save()
    analyze = runner.run('analyze', [executable, 'analyze', '--no-pub', '--no-fatal-infos', '--no-fatal-warnings'], app, required=False)
    commands = {
        'android': ['apk', '--debug', '--target-platform', 'android-arm64'],
        'ios': ['ios', '--debug', '--no-codesign'],
        'macos': ['macos', '--debug'],
        'windows': ['windows', '--debug'],
        'linux': ['linux', '--debug'],
    }
    build = runner.run('build-' + args.platform, [executable, 'build', *commands[args.platform], '--no-pub'], app, required=False)
    runner.receipt['addedInputsAfterBuild'] = {
        'app': verify_added(app, app=True),
        'sdk': verify_added(sdk, package_paths=[p['path'] for p in plan['packages'].values()]),
    }
    runner.receipt['sourceGuardAfterBuild'] = {
        'app': verify_tracked(app, app_manifest, GENERATED_TRACKED),
        'sdk': verify_tracked(sdk, sdk_manifest),
    }
    runner.receipt['resolutionAfterBuild'] = verify_managed(plan, app / '.dart_tool/package_config.json', app, sdk)
    # Input checkouts, unlike staged generated files, have no allowed changes.
    if identity(args.app_root) != app_id or identity(args.sdk_root) != sdk_id:
        raise AuditError('An input checkout changed while building')
    runner.receipt['applicationCompile'] = 'passed' if build == 0 else 'failed'
    runner.receipt['analysis'] = 'passed' if analyze == 0 else 'failed'
    if analyze or build:
        raise AuditError('Original application analysis/build failed; no error baseline is accepted')


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app-root', type=Path, required=True)
    parser.add_argument('--sdk-root', type=Path, required=True)
    parser.add_argument('--flutter-root', type=Path, required=True)
    parser.add_argument('--platform', choices=('android', 'ios', 'macos', 'windows', 'linux'), required=True)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args(argv)
    out = args.out.resolve()
    for root in (args.app_root, args.sdk_root, args.flutter_root):
        source = root.resolve()
        if out.is_relative_to(source) or source.is_relative_to(out):
            parser.error('Output and inputs must be disjoint')
    out.mkdir(parents=True, exist_ok=False)
    runner = Runner(out)
    runner.receipt['platform'] = args.platform
    try:
        execute(args, runner)
        runner.receipt['status'] = 'passed-T1-only'
        return 0
    except (AuditError, OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
        runner.receipt['status'] = 'failed'
        runner.receipt['error'] = str(error)
        print(str(error), file=sys.stderr, flush=True)
        return 2
    finally:
        runner.save()


if __name__ == '__main__':
    raise SystemExit(main())
