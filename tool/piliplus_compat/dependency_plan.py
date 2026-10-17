#!/usr/bin/env python3
"""P0a: read committed pubspecs and audit a zero-source-change override plan.

This tool does NOT stage an app, resolve pub dependencies, compile, or certify
native binaries. Output belongs outside both input checkouts. Exit 2 denotes an
audit failure; an override-only missing package is not called a compiler error.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import sys
from pathlib import Path, PurePosixPath
from urllib.parse import unquote, urljoin, urlsplit

import yaml


class AuditError(ValueError):
    pass


class StrictLoader(yaml.SafeLoader):
    def construct_mapping(self, node, deep=False):
        self.flatten_mapping(node)
        result = {}
        for key_node, value_node in node.value:
            key = self.construct_object(key_node, deep=deep)
            if not isinstance(key, str) or key in result:
                raise AuditError('Duplicate or non-string YAML mapping key')
            result[key] = self.construct_object(value_node, deep=deep)
        return result


def mapping(value, label):
    if value is None:
        return {}
    if not isinstance(value, dict) or any(not isinstance(k, str) for k in value):
        raise AuditError(f'{label} must be a string-keyed map')
    return value


def parse_manifest(text: str) -> dict:
    # Anchors are deliberately unsupported until parity with pub is tested.
    if any(isinstance(t, (yaml.tokens.AnchorToken, yaml.tokens.AliasToken))
           for t in yaml.scan(text)):
        raise AuditError('YAML anchors/aliases require a separately reviewed parser')
    return mapping(yaml.load(text, Loader=StrictLoader), 'manifest')


def managed(name: str) -> bool:
    return name == 'media_kit' or name.startswith('media_kit_') or name == 'video_player_media_kit'


def git(root: Path, *args: str) -> bytes:
    result = subprocess.run(['git', '-C', str(root), *args], capture_output=True)
    if result.returncode:
        raise AuditError(f'git {args[0]} failed (exit {result.returncode})')
    return result.stdout


def identity(root: Path, allowed_changes=frozenset()) -> dict:
    root = root.resolve(strict=True)
    top = Path(git(root, 'rev-parse', '--show-toplevel').decode().strip()).resolve()
    if top != root:
        raise AuditError('Input must be the Git checkout root')
    changed = set(git(root, 'diff', '--no-ext-diff', '--no-renames', '--name-only', '-z', 'HEAD', '--').decode().split('\0'))
    changed.update(git(root, 'ls-files', '--others', '--exclude-standard', '-z').decode().split('\0'))
    if changed - {''} - set(allowed_changes):
        raise AuditError('Input has tracked changes or untracked files; use a clean checkout')
    return {'root': str(root), 'commit': git(root, 'rev-parse', 'HEAD').decode().strip(),
            'tree': git(root, 'rev-parse', 'HEAD^{tree}').decode().strip()}


def manifests_at_head(source: dict) -> dict:
    root = Path(source['root'])
    entries = git(root, 'ls-tree', '-rz', '--full-tree', source['commit'])
    result = {}
    for record in entries.split(b'\0'):
        if not record:
            continue
        meta, raw_path = record.split(b'\t', 1)
        mode, kind, _ = meta.decode().split()
        path = raw_path.decode('utf-8')
        if PurePosixPath(path).name not in ('pubspec.yaml', 'pubspec_overrides.yaml'):
            continue
        if kind != 'blob' or mode not in ('100644', '100755'):
            raise AuditError(f'Unsupported manifest file type: {path}')
        payload = git(root, 'show', f"{source['commit']}:{path}")
        result[path] = {'data': parse_manifest(payload.decode('utf-8')),
                        'sha256': hashlib.sha256(payload).hexdigest()}
    if 'pubspec.yaml' not in result:
        raise AuditError('Root pubspec.yaml is missing')
    return result


def dependencies(spec: dict, *, root=False) -> set[str]:
    names = set(mapping(spec.get('dependencies'), 'dependencies'))
    if root:
        names.update(mapping(spec.get('dev_dependencies'), 'dev_dependencies'))
    return {name for name in names if managed(name)}


def package_catalog(manifests: dict) -> dict:
    catalog = {}
    for path, record in sorted(manifests.items()):
        parts = PurePosixPath(path).parts
        # SDK library roots only, not applications, examples, or test fixtures.
        library = (len(parts) == 2 and parts[0] in
                   ('media_kit', 'media_kit_video', 'media_kit_native_event_loop',
                    'video_player_media_kit')) or (len(parts) == 4 and parts[0] == 'libs')
        if not library or parts[-1] != 'pubspec.yaml':
            continue
        spec = record['data']
        name = spec.get('name')
        if not isinstance(name, str) or not managed(name):
            raise AuditError(f'Unexpected SDK package name in {path}')
        if name in catalog:
            raise AuditError(f'Duplicate SDK package: {name}')
        catalog[name] = {'path': str(PurePosixPath(path).parent),
                         'manifestSha256': record['sha256'], 'spec': spec}
    return catalog


def build_plan(app: dict, overlay: dict, catalog: dict, sdk_root: Path) -> dict:
    if app.get('workspace') is not None or app.get('resolution') == 'workspace' or overlay.get('workspace') is not None or overlay.get('resolution') == 'workspace':
        raise AuditError('Pub workspaces are not yet supported by this auditor')
    # Root override file takes precedence. Preserve unrelated values exactly.
    original = dict(mapping(app.get('dependency_overrides'), 'dependency_overrides'))
    original.update(mapping(overlay.get('dependency_overrides'), 'dependency_overrides'))
    roots = dependencies(app, root=True)
    override_roots = {name for name in original if managed(name)}
    if not roots:
        raise AuditError('Application declares no managed player dependencies')

    def closure(seeds):
        reached, todo = set(), list(seeds)
        while todo:
            name = todo.pop()
            if name in reached:
                continue
            reached.add(name)
            if name not in catalog:
                continue
            spec = catalog[name]['spec']
            todo.extend(dependencies(spec) - reached)
            flutter = mapping(spec.get('flutter'), 'flutter')
            plugin = mapping(flutter.get('plugin'), 'plugin')
            for row in mapping(plugin.get('platforms'), 'platforms').values():
                default = mapping(row, 'platform').get('default_package')
                if default is not None and not isinstance(default, str):
                    raise AuditError('default_package must be a string')
                if default and managed(default):
                    todo.append(default)
        return reached

    required = closure(roots)
    selected = closure(roots | override_roots)
    missing = sorted(selected - catalog.keys())
    blockers = [{'package': name, 'kind': 'missing-required-package' if name in required
                 else 'unresolved-override-only',
                 'note': 'No matching SDK package; do not mix the old fork. '
                         'Override-only reachability needs pub resolution evidence.'}
                for name in missing]
    output = dict(overlay)
    overrides = {name: value for name, value in original.items() if not managed(name)}
    packages = {}
    for name in sorted(selected & catalog.keys()):
        record = catalog[name]
        target = (sdk_root / record['path']).resolve()
        if not target.is_relative_to(sdk_root.resolve()):
            raise AuditError('SDK package path escapes checkout')
        overrides[name] = {'path': str(target)}
        packages[name] = {k: record[k] for k in ('path', 'manifestSha256')}
    output['dependency_overrides'] = overrides
    return {'schemaVersion': 1, 'stage': 'P0a-dependency-audit',
            'status': 'blocked' if blockers else 'declarations-ready',
            'requiredPackages': sorted(required), 'packages': packages,
            'blockers': blockers, 'overrideDocument': output,
            'stages': {name: 'not-run' for name in
                       ('isolatedStaging', 'pubResolution', 'applicationCompile',
                        'nativeBuild', 'devicePlayback', 'hdrVerification')}}


def verify_resolution(plan: dict, config_file: Path) -> dict:
    if plan['blockers']:
        raise AuditError('Dependency declarations still have unresolved blockers')
    for role, source in plan['sources'].items():
        allowed = {'pubspec.lock', 'pubspec_overrides.yaml'} if role == 'app' else set()
        if identity(Path(source['root']), allowed) != source:
            raise AuditError('Source checkout changed since plan generation')
    config = json.loads(config_file.read_text(encoding='utf-8'))
    if config.get('configVersion') != 2 or not isinstance(config.get('packages'), list):
        raise AuditError('Unsupported package_config shape')
    seen, matched = set(), set()
    sdk_root = Path(plan['sources']['sdk']['root']).resolve()
    app_root = Path(plan['sources']['app']['root']).resolve()
    actual_overlay = parse_manifest((app_root / 'pubspec_overrides.yaml').read_text(encoding='utf-8'))
    if actual_overlay != plan['overrideDocument']:
        raise AuditError('Generated root overrides differ from the audited plan')
    for row in config['packages']:
        if not isinstance(row, dict) or not isinstance(row.get('name'), str):
            raise AuditError('Invalid package_config row')
        name = row['name']
        if name in seen:
            raise AuditError('Duplicate package_config package')
        seen.add(name)
        if name != plan['applicationName'] and not managed(name):
            continue
        if name != plan['applicationName'] and name not in plan['packages']:
            raise AuditError(f'Unplanned managed package resolved: {name}')
        root_uri = row.get('rootUri')
        package_uri = row.get('packageUri', 'lib/')
        if not isinstance(root_uri, str) or not isinstance(package_uri, str):
            raise AuditError('Invalid package URI')
        url = urlsplit(urljoin(config_file.resolve().as_uri(), root_uri))
        if url.scheme != 'file' or url.netloc not in ('', 'localhost') or url.query or url.fragment:
            raise AuditError('Expected a local file package root')
        actual = Path(unquote(url.path)).resolve(strict=True)
        expected = app_root if name == plan['applicationName'] else sdk_root / plan['packages'][name]['path']
        if actual != expected.resolve(strict=True):
            raise AuditError(f'Package resolved outside its planned root: {name}')
        lib_url = urlsplit(urljoin(actual.as_uri() + '/', package_uri))
        if lib_url.scheme != 'file' or lib_url.netloc not in ('', 'localhost') or lib_url.query or lib_url.fragment or Path(unquote(lib_url.path)).resolve() != actual / 'lib':
            raise AuditError(f'Package library URI escaped its planned lib/: {name}')
        matched.add(name)
    if not (set(plan['requiredPackages']) | {plan['applicationName']}) <= matched:
        raise AuditError('Required packages are absent from package_config')
    return {'status': 'resolved-managed-roots-verified', 'matched': sorted(matched),
            'note': 'Path verification only; no compile, native binary or HDR certification.'}


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app-root', type=Path)
    parser.add_argument('--sdk-root', type=Path)
    parser.add_argument('--out', type=Path, required=True, help='New output directory outside the input roots')
    parser.add_argument('--verify-plan', type=Path)
    parser.add_argument('--package-config', type=Path)
    args = parser.parse_args(argv)
    out = args.out.resolve()
    created = False
    try:
        if args.verify_plan:
            if args.app_root or args.sdk_root or not args.package_config:
                raise AuditError('Verification requires only --verify-plan and --package-config')
            plan = json.loads(args.verify_plan.read_text(encoding='utf-8'))
            roots = [Path(s['root']).resolve() for s in plan['sources'].values()]
        else:
            if not args.app_root or not args.sdk_root or args.package_config:
                raise AuditError('Generation requires --app-root and --sdk-root')
            roots = [args.app_root.resolve(), args.sdk_root.resolve()]
        if any(out.is_relative_to(root) for root in roots):
            raise AuditError('Output may not modify an input checkout')
        out.mkdir(parents=True, exist_ok=False)
        created = True
        if args.verify_plan:
            result = verify_resolution(plan, args.package_config)
            (out / 'resolution.json').write_text(json.dumps(result, indent=2) + '\n')
            return 0
        app_id, sdk_id = (identity(root) for root in roots)
        app_files, sdk_files = manifests_at_head(app_id), manifests_at_head(sdk_id)
        app = app_files['pubspec.yaml']['data']
        overlay = app_files.get('pubspec_overrides.yaml', {'data': {}})['data']
        result = build_plan(app, overlay, package_catalog(sdk_files), roots[1])
        result['sources'] = {'app': app_id, 'sdk': sdk_id}
        result['applicationName'] = app.get('name')
        if not isinstance(result['applicationName'], str):
            raise AuditError('Application name is missing')
        result['appManifestSha256'] = app_files['pubspec.yaml']['sha256']
        if identity(roots[0]) != app_id or identity(roots[1]) != sdk_id:
            raise AuditError('Input changed during audit')
        (out / 'plan.json').write_text(json.dumps(result, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
        if result['blockers']:
            print('Dependency audit blocked; see plan.json', file=sys.stderr)
            return 2
        (out / 'pubspec_overrides.yaml').write_text(yaml.safe_dump(result['overrideDocument'], sort_keys=True, allow_unicode=True), encoding='utf-8')
        return 0
    except (AuditError, OSError, ValueError, KeyError, TypeError, yaml.YAMLError) as error:
        if created:
            (out / 'failure.json').write_text(json.dumps({'stage': 'P0a-dependency-audit',
                'status': 'failed', 'error': str(error), 'applicationCompile': 'not-run'}) + '\n')
        print(f'Dependency audit failed: {error}', file=sys.stderr)
        return 2


if __name__ == '__main__':
    raise SystemExit(main())
