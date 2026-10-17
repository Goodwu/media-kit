import contextlib
import hashlib
import io
import json
import subprocess
import tempfile
import unittest
from pathlib import Path

import yaml

import dependency_plan as d


def record(name, deps=None, **extra):
    return {'path': name, 'manifestSha256': 'test',
            'spec': {'name': name, 'dependencies': deps or {}, **extra}}


class PlanTests(unittest.TestCase):
    def setUp(self):
        self.app = {'name': 'PiliPlus', 'dependencies': {'media_kit': '1.1.11'}}
        self.catalog = {'media_kit': record('media_kit')}
        self.root = Path(tempfile.gettempdir()) / 'sdk'

    def plan(self, overlay=None):
        return d.build_plan(self.app, overlay or {}, self.catalog, self.root)

    def test_transitive_closure(self):
        self.catalog['media_kit']['spec']['dependencies']['media_kit_libs_video'] = 'any'
        self.catalog['media_kit_libs_video'] = record('media_kit_libs_video', {'media_kit_libs_android_video': 'any'})
        self.catalog['media_kit_libs_android_video'] = record('media_kit_libs_android_video')
        p = self.plan()
        self.assertEqual(set(p['requiredPackages']), set(self.catalog))
        self.assertFalse(p['blockers'])

    def test_federated_default_package(self):
        self.catalog['media_kit']['spec']['flutter'] = {'plugin': {'platforms': {'android': {'default_package': 'media_kit_android'}}}}
        self.catalog['media_kit_android'] = record('media_kit_android')
        self.assertIn('media_kit_android', self.plan()['requiredPackages'])

    def test_preserve_other_overrides_and_precedence(self):
        self.app['dependency_overrides'] = {'other': {'git': {'url': 'example', 'ref': 'old'}}, 'media_kit': {'git': 'old-player'}}
        p = self.plan({'dependency_overrides': {'other': {'path': '../local'}, 'another': '2.0.0'}})
        result = p['overrideDocument']['dependency_overrides']
        self.assertEqual(result['other'], {'path': '../local'})
        self.assertEqual(result['another'], '2.0.0')
        self.assertEqual(result['media_kit'], {'path': str(self.root / 'media_kit')})
        self.assertEqual(self.app['dependency_overrides']['other']['git']['ref'], 'old')

    def test_missing_required(self):
        self.catalog.clear()
        self.assertEqual(self.plan()['blockers'][0]['kind'], 'missing-required-package')

    def test_override_only_not_called_required(self):
        self.app['dependency_overrides'] = {'media_kit_native_event_loop': {'git': 'legacy'}}
        p = self.plan()
        self.assertEqual(p['blockers'][0]['kind'], 'unresolved-override-only')
        self.assertNotIn('media_kit_native_event_loop', p['requiredPackages'])
        self.assertEqual(p['status'], 'blocked')
        self.assertNotIn('media_kit_native_event_loop', p['overrideDocument']['dependency_overrides'])

    def test_dependency_dev_and_overrides_not_inherited(self):
        self.catalog['media_kit']['spec'].update({'dev_dependencies': {'media_kit_test': 'any'}, 'dependency_overrides': {'media_kit_old': 'any'}})
        self.assertEqual(self.plan()['requiredPackages'], ['media_kit'])

    def test_application_dev_dependency_is_required(self):
        self.app['dev_dependencies'] = {'media_kit_video': 'any'}
        self.assertEqual(self.plan()['blockers'][0]['kind'], 'missing-required-package')

    def test_cycle_is_bounded(self):
        self.catalog['media_kit']['spec']['dependencies']['media_kit'] = 'any'
        self.assertEqual(self.plan()['requiredPackages'], ['media_kit'])

    def test_unknown_is_not_a_build_pass(self):
        p = self.plan()
        self.assertEqual(p['status'], 'declarations-ready')
        self.assertTrue(all(value == 'not-run' for value in p['stages'].values()))

    def test_yaml_rejects_ambiguous_documents(self):
        for text in ('name: a\nname: b', 'dependencies: {a: x, a: y}', '[a, b]', 'x: &a hi\ny: *a', 'true: x'):
            with self.subTest(text=text), self.assertRaises((d.AuditError, yaml.YAMLError)):
                d.parse_manifest(text)

    def test_workspaces_fail_explicitly(self):
        self.app['resolution'] = 'workspace'
        with self.assertRaises(d.AuditError):
            self.plan()

    def test_catalog_excludes_app_and_example(self):
        records = {p: {'data': {'name': name}, 'sha256': 'abc'} for p, name in (
            ('media_kit/pubspec.yaml', 'media_kit'),
            ('media_kit/example/pubspec.yaml', 'media_kit'),
            ('media_kit_hdr_lab/pubspec.yaml', 'media_kit_hdr_lab'),
            ('libs/android/media_kit_libs_android_video/pubspec.yaml', 'media_kit_libs_android_video'))}
        self.assertEqual(set(d.package_catalog(records)), {'media_kit', 'media_kit_libs_android_video'})

    def test_duplicate_packages_rejected(self):
        rows = {p: {'data': {'name': 'media_kit'}, 'sha256': 'abc'} for p in ('media_kit/pubspec.yaml', 'media_kit_video/pubspec.yaml')}
        with self.assertRaises(d.AuditError):
            d.package_catalog(rows)


class GitTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)
        self.app = self.repo('app', {'pubspec.yaml': 'name: PiliPlus\ndependencies:\n  media_kit: 1.1.11\n',
            'pubspec.lock': 'old lock\n', '.gitignore': '.dart_tool/\n', 'lib/main.dart': '// unchanged\n'})
        self.sdk = self.repo('sdk', {'pubspec.yaml': 'name: workspace_root\n',
            'media_kit/pubspec.yaml': 'name: media_kit\nversion: 1.2.1\n', 'media_kit/lib/media_kit.dart': '// sdk\n'})

    def repo(self, name, files):
        root = self.base / name
        root.mkdir()
        subprocess.run(['git', 'init', '-q', str(root)], check=True)
        subprocess.run(['git', '-C', str(root), 'config', 'user.name', 'Fixture'], check=True)
        subprocess.run(['git', '-C', str(root), 'config', 'user.email', 'fixture@example.invalid'], check=True)
        for name, text in files.items():
            path = root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text)
        self.commit(root)
        return root

    def commit(self, root):
        subprocess.run(['git', '-C', str(root), 'add', '.'], check=True)
        subprocess.run(['git', '-C', str(root), 'commit', '-qm', 'fixture'], check=True)

    def invoke(self, out='out', *extra):
        with contextlib.redirect_stderr(io.StringIO()):
            return d.main(['--app-root', str(self.app), '--sdk-root', str(self.sdk), '--out', str(self.base / out), *extra])

    def prepare_config(self):
        self.assertEqual(self.invoke(), 0)
        plan = json.loads((self.base / 'out/plan.json').read_text())
        (self.app / 'pubspec_overrides.yaml').write_text(yaml.safe_dump(plan['overrideDocument']))
        (self.app / 'pubspec.lock').write_text('new generated lock\n')
        config = self.app / '.dart_tool/package_config.json'
        config.parent.mkdir()
        payload = {'configVersion': 2, 'packages': [
            {'name': 'PiliPlus', 'rootUri': '../', 'packageUri': 'lib/'},
            {'name': 'media_kit', 'rootUri': (self.sdk / 'media_kit').as_uri() + '/', 'packageUri': 'lib/'}]}
        config.write_text(json.dumps(payload))
        return plan, config, payload

    def test_generate_without_modifying_sources(self):
        before = d.identity(self.app), d.identity(self.sdk)
        self.assertEqual(self.invoke(), 0)
        self.assertEqual(before, (d.identity(self.app), d.identity(self.sdk)))
        plan = json.loads((self.base / 'out/plan.json').read_text())
        self.assertEqual(plan['appManifestSha256'], hashlib.sha256((self.app / 'pubspec.yaml').read_bytes()).hexdigest())
        self.assertTrue((self.base / 'out/pubspec_overrides.yaml').is_file())

    def test_output_in_app_is_rejected(self):
        self.assertEqual(self.invoke('app/generated'), 2)
        self.assertFalse((self.app / 'generated').exists())

    def test_existing_output_not_overwritten(self):
        self.assertEqual(self.invoke(), 0)
        prior = (self.base / 'out/plan.json').read_bytes()
        self.assertEqual(self.invoke(), 2)
        self.assertEqual((self.base / 'out/plan.json').read_bytes(), prior)

    def test_dirty_checkout_rejected_and_receipt_written(self):
        (self.app / 'lib/main.dart').write_text('// modified')
        self.assertEqual(self.invoke(), 2)
        self.assertTrue((self.base / 'out/failure.json').exists())

    def test_untracked_source_rejected(self):
        (self.sdk / 'media_kit/lib/extra.dart').write_text('// untracked')
        self.assertEqual(self.invoke(), 2)

    def test_missing_override_no_runnable_yaml(self):
        (self.app / 'pubspec.yaml').write_text('name: PiliPlus\ndependencies: {media_kit: any}\ndependency_overrides: {media_kit_native_event_loop: any}\n')
        self.commit(self.app)
        self.assertEqual(self.invoke(), 2)
        self.assertEqual(json.loads((self.base / 'out/plan.json').read_text())['status'], 'blocked')
        self.assertFalse((self.base / 'out/pubspec_overrides.yaml').exists())

    def test_matching_resolution_allows_generated_lock_and_overlay(self):
        plan, config, _ = self.prepare_config()
        self.assertEqual(d.verify_resolution(plan, config)['status'], 'resolved-managed-roots-verified')

    def test_resolution_rejects_old_fork(self):
        plan, config, payload = self.prepare_config()
        payload['packages'][1]['rootUri'] = self.app.as_uri()
        config.write_text(json.dumps(payload))
        with self.assertRaises(d.AuditError):
            d.verify_resolution(plan, config)

    def test_resolution_rejects_lib_escape(self):
        plan, config, payload = self.prepare_config()
        payload['packages'][1]['packageUri'] = '../other/lib/'
        config.write_text(json.dumps(payload))
        with self.assertRaises(d.AuditError):
            d.verify_resolution(plan, config)

    def test_resolution_rejects_missing_package(self):
        plan, config, payload = self.prepare_config()
        payload['packages'].pop()
        config.write_text(json.dumps(payload))
        with self.assertRaises(d.AuditError):
            d.verify_resolution(plan, config)

    def test_resolution_rejects_duplicate_package(self):
        plan, config, payload = self.prepare_config()
        payload['packages'].append(payload['packages'][1])
        config.write_text(json.dumps(payload))
        with self.assertRaises(d.AuditError):
            d.verify_resolution(plan, config)

    def test_resolution_rejects_changed_source(self):
        plan, config, _ = self.prepare_config()
        (self.sdk / 'media_kit/lib/media_kit.dart').write_text('// changed')
        with self.assertRaises(d.AuditError):
            d.verify_resolution(plan, config)

    def test_resolution_rejects_tampered_overrides(self):
        plan, config, _ = self.prepare_config()
        (self.app / 'pubspec_overrides.yaml').write_text('dependency_overrides: {}')
        with self.assertRaises(d.AuditError):
            d.verify_resolution(plan, config)


if __name__ == '__main__':
    unittest.main()
