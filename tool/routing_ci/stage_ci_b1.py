#!/usr/bin/env python3
"""Guarded CI/B1c transformation. Retired from the tree after staging.

All edits are reviewed task-owned changes. No arbitrary issue commands and no
branch writes; the connector separately commits the reviewed immutable tree.
"""
from pathlib import Path
import json


def replace_once(text, old, new):
    if text.count(old) != 1:
        raise ValueError(f'Expected one exact source anchor: {old[:100]!r}')
    return text.replace(old, new, 1)


def apply(root):
    pending = {}
    path = 'media_kit_video/lib/src/hdr/hdr_route_planner.dart'
    s = (root / path).read_text()
    s = replace_once(s, '        honorExcluded: false,\n', '')
    s = replace_once(s, '    bool honorExcluded = true,\n', '')
    s = replace_once(s, 'if (honorExcluded && route.dependencies.contains(entry.key))', 'if (route.dependencies.contains(entry.key))')
    old = '''      // Safety net: playback continues tone-mapped (SDR direct for SDR
      // sources). It bypasses the maturity gate and the excluded stages on
      // purpose — the requirement mandates continuing playback — so its
      // only possible failure is why playback will not start at all (a P5
      // source without the rescale pipeline, R3.3).
'''
    s = replace_once(s, old, '''      // The SDR fallback may relax maturity, never a known execution failure.
      // No usable remaining implementation means blocked playback, not a
      // retry of the same failed decoder/import path under a different name.
''')
    s = replace_once(s, '''/// going — requirement section 2 forbids stopping playback — except a P5
/// source without the dovi rescale pipeline, which reports
/// [HdrDegradeReason.p5PipelineUnavailable] and `playable == false`
/// (R3.3: never output a wrongly colored picture).''', '''/// going only when it satisfies the source and execution constraints too.
/// Known failures retain their original reason. A P5 source without the
/// rescale pipeline remains blocked (never output a wrongly colored picture).''')
    pending[path] = s

    path = 'media_kit_video/test/hdr_video_session_test.dart'
    s = (root / path).read_text()
    start = s.index("  test('hwdec mismatch excludes the stage and reopens in place'")
    end = s.index("  test('API 24 copy route accepts", start)
    s = s[:start] + '''  test('hwdec mismatch cannot reuse the failed stage through SDR fallback', () async {
    final backend = FakeBackend()
      ..factsForOpen.add(facts(gamma: 'pq', primaries: 'bt.2020', hwdec: 'no'));
    final session = makeSession(
      backend: backend,
      capabilities: caps(),
      position: const Duration(seconds: 3),
    );
    final events = <HdrOutputEvent>[];
    session.events.listen(events.add);
    await session.open(media, hint: hdr10);
    await pumpEventQueue();
    expect(backend.opened, hasLength(1));
    expect(backend.opened.single.route.strategy, HdrStrategy.baseLayerDirect);
    expect(session.report.value.verified, isFalse);
    expect(session.report.value.degradeReason, HdrDegradeReason.hwdecMismatch);
    expect(events.whereType<HdrRouteAppliedEvent>(), isEmpty);
    expect(events.whereType<HdrErrorEvent>().single.reason,
        HdrDegradeReason.hwdecMismatch);
    expect(backend.calls, contains('stop'));
    expect(backend.calls, contains('reset'));
    await session.dispose();
  });

''' + s[end:]
    start = s.index("  test('API 24 copy mismatch")
    end = s.index("  test('missing P5 pipeline", start)
    s = s[:start] + '''  test('API 24 copy mismatch blocks rather than retrying the same failed copy path',
      () async {
    final backend = FakeBackend()
      ..factsForOpen.add(const HdrReviewFacts(
        hwdecCurrent: 'no', path: 'test://media',
      ));
    final session = makeSession(
      backend: backend,
      capabilities: caps(sdkInt: 24),
      position: const Duration(seconds: 3),
    );
    final events = <HdrOutputEvent>[];
    session.events.listen(events.add);
    await session.open(media, hint: sdr);
    await pumpEventQueue();
    expect(backend.opened, hasLength(1));
    expect(backend.opened.single.route.hwdec, 'mediacodec-copy');
    expect(session.report.value.verified, isFalse);
    expect(session.report.value.degradeReason, HdrDegradeReason.hwdecMismatch);
    expect(events.whereType<HdrRouteAppliedEvent>(), isEmpty);
    expect(events.whereType<HdrErrorEvent>().single.reason,
        HdrDegradeReason.hwdecMismatch);
    expect(backend.calls, contains('stop'));
    expect(backend.calls, contains('reset'));
    await session.dispose();
  });

''' + s[end:]
    pending[path] = s

    path = '.github/workflows/ci.yml'
    s = (root / path).read_text()
    start = s.index('      - name: Download pinned arm64 jar and verify identity\n')
    end = s.index('\n  hdr-lab-analyze:', start)
    s = s[:start] + '''      - name: Test release identity parser and negative cases
        run: python3 -m unittest tool.routing_ci.test_android_jar_identity -v
      - name: Verify configured release JAR (not a native source build)
        run: python3 tool/routing_ci/android_jar_identity.py
''' + s[end:]
    pending[path] = s

    path = 'docs/plans/media-kit-routing-handoff-20261011.json'
    d = json.loads((root / path).read_text())
    d['nextAction'] = 'Validate phaseCiB1 on existing PR4; B2b is already implemented and host-validated (comments6107283427/6107287306). Finish App CI, importer/source facts, B3 selection and latest-source native build; do not repeat integrations.'
    d['phaseCiB1'] = {
        'status': 'implemented_validation_pending',
        'mediaIntegration': '8b80f4523f58a635b380bee1e12c1654afe706f5',
        'appIntegration': 'd0926b315af63b43bf5452119b4e4a067f58f88c',
        'localIdentityTestsPassed': 8, 'newFallbackTests': 10,
        'sessionTestsUpdated': 2, 'doNotReimplement': True,
        'fullNativeAcceptance': False,
        'open': ['App85infos', 'AppBuildRequiredRef', 'UnknownP8', 'ImporterAndOutputIdentity', 'LGManaged', 'B3NativeSelection', 'LatestNativeAPK']
    }
    for task in d['tasks']:
        if task['id'] == 'B2':
            for sub in task['subtasks']:
                if sub['id'] == 'B2b-query-migration-App-source-filter':
                    sub['status'] = 'implemented_host_validated'
                    sub['validationComment'] = 6107283427
        if task['id'] == 'B1':
            for sub in task['subtasks']:
                if sub['id'] == 'B1c-dependencies-review-fallback':
                    sub['status'] = 'in_progress'
                    sub['note'] = 'Fallback now honors failures; independent tests pending. Importer/output identity and software alternatives remain open.'
    pending[path] = json.dumps(d, ensure_ascii=False, indent=2) + '\n'
    for path, content in pending.items():
        (root / path).write_text(content)
    return list(pending)


if __name__ == '__main__':
    print('\n'.join(apply(Path.cwd())))
