import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' show Media, VideoParams;
import 'package:media_kit_video/src/hdr/hdr_capabilities.dart';
import 'package:media_kit_video/src/hdr/hdr_open_plan.dart';
import 'package:media_kit_video/src/hdr/hdr_output_event.dart';
import 'package:media_kit_video/src/hdr/hdr_route.dart';
import 'package:media_kit_video/src/hdr/hdr_route_planner.dart';
import 'package:media_kit_video/src/hdr/hdr_source_descriptor.dart';
import 'package:media_kit_video/src/hdr/hdr_source_facts.dart';
import 'package:media_kit_video/src/hdr/hdr_strategy.dart';
import 'package:media_kit_video/src/hdr/hdr_video_session.dart';

import 'hdr_video_session_test.dart' show FakeBackend;

const _p84 = HdrSourceDescriptor(
  codec: 'hevc', transfer: 'hlg', primaries: 'bt.2020',
  dynamicMetadata: HdrDynamicMetadata.dolbyVision,
  dvProfile: 8, dvCompatibilityId: 4, enhancementLayer: false,
);
const _hdr10 = HdrSourceDescriptor(
  codec: 'hevc', transfer: 'pq', primaries: 'bt.2020',
  enhancementLayer: false,
);

HdrVideoSession _session(FakeBackend backend, {bool experimental = true}) =>
    HdrVideoSession.forTesting(
      capabilitiesProvider: () async => const HdrCapabilities(
        sdkInt: 29, displayHdrTypes: {1, 2, 3},
        hevcDecoders: [], dolbyVisionDecoders: [],
        p5PipelineAvailable: true, dataSpaceBridgeLoaded: true,
        dataSpaceExt: HdrDataSpaceExtInfo(id: 'lya-pq', applicable: true),
      ),
      positionProvider: () => Duration.zero,
      isAndroid: true,
      backend: backend,
      policy: HdrRoutingPolicy(allowExperimental: experimental),
    );

HdrReviewFacts _facts({
  String gamma = 'hlg', int? profile, int? compatibility,
  bool? el, bool? vivid,
}) => HdrReviewFacts(
  videoParams: VideoParams(gamma: gamma, primaries: 'bt.2020'),
  dolbyVisionProfile: profile, dvCompatibilityId: compatibility,
  dvElPresent: el, hdrVivid: vivid,
  codec: 'hevc', hwdecCurrent: 'mediacodec', path: 'test://source',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final experimental in [false, true]) {
    test('partial review preserves hinted DV with experiment=$experimental', () async {
      final backend = FakeBackend()..factsForOpen.add(_facts());
      final session = _session(backend, experimental: experimental);
      addTearDown(session.dispose);
      await session.open(Media('test://source'), hint: _p84);
      expect(backend.opened, hasLength(1));
      final report = session.report.value;
      expect(report.source, _p84);
      expect(report.verified, isTrue);
      expect(report.sourceFacts!.reviewCount, 1);
      expect(report.sourceFacts!.initialHint, _p84);
      expect(report.sourceFacts!.origins[HdrSourceField.dvProfile],
          HdrSourceFactOrigin.hint);
      expect(report.sourceFacts!.videoParams!.gamma, 'hlg');
    });
  }

  test('first observed DV survives missing profile after a topology reopen', () async {
    final backend = FakeBackend()
      ..factsForOpen.addAll([
        _facts(profile: 8, compatibility: 4, el: false),
        _facts(),
      ]);
    final session = _session(backend);
    addTearDown(session.dispose);
    await session.open(Media('test://source'));
    expect(backend.opened, hasLength(2));
    expect(backend.opened.first.route.strategy, HdrStrategy.sdrDirect);
    // The retained DV evidence replans to the canonical catalog: the C2
    // reshape (P5 pipeline available, PQ-capable display) is evaluated
    // without a maturity gate and selected ahead of the C3 baseline.
    expect(backend.opened.last.route.strategy, HdrStrategy.metadataReshape);
    final report = session.report.value;
    expect(report.source, _p84);
    expect(report.sourceFacts!.initialHint, isNull);
    expect(report.sourceFacts!.reviewCount, 2);
    expect(report.sourceFacts!.origins[HdrSourceField.dvProfile],
        HdrSourceFactOrigin.track);
    expect(report.verified, isTrue);
    expect(report.diagnostic, isNull);
  });

  test('Vivid positive frame survives the next decoder missing side data', () async {
    final backend = FakeBackend()
      ..factsForOpen.addAll([
        _facts(gamma: 'pq', vivid: true),
        _facts(gamma: 'pq', vivid: false),
      ]);
    // The explicit experimental unlock makes the reclassified hdrVivid row
    // selectable; without it the reclassification blocks (no implicit SDR
    // fallback) and the retention scenario never reaches a second review.
    final session = _session(backend, experimental: true);
    addTearDown(session.dispose);
    await session.open(Media('test://source'));
    expect(backend.opened, hasLength(2));
    expect(backend.opened.first.route.strategy, HdrStrategy.sdrDirect);
    expect(backend.opened.last.route.strategy, HdrStrategy.baseLayerDirect);
    final report = session.report.value;
    expect(report.source!.dynamicMetadata, HdrDynamicMetadata.hdrVivid);
    expect(report.sourceFacts!.hdrVividOnFrame, isFalse);
    expect(report.sourceFacts!.reviewCount, 2);
    expect(report.verified, isTrue);
    expect(report.diagnostic, isNull);
  });

  test('a second affirmative track contradiction blocks and retains evidence', () async {
    final backend = FakeBackend()
      ..factsForOpen.addAll([
        _facts(profile: 8, compatibility: 4, el: false),
        _facts(gamma: 'pq', profile: 8, compatibility: 1, el: false),
      ]);
    final session = _session(backend);
    addTearDown(session.dispose);
    final events = <HdrOutputEvent>[];
    final subscription = session.events.listen(events.add);
    addTearDown(subscription.cancel);
    await session.open(Media('test://source'));
    await pumpEventQueue();
    final report = session.report.value;
    expect(backend.opened, hasLength(2));
    expect(report.verified, isFalse);
    expect(report.degradeReason, HdrDegradeReason.sourceMetadataUnknown);
    expect(report.sourceFacts!.hasConflict, isTrue);
    expect(report.sourceFacts!.conflicts.single.field,
        HdrSourceField.dvCompatibilityId);
    expect(report.sourceFacts!.videoParams!.gamma, 'pq');
    expect(events.whereType<HdrRouteAppliedEvent>(), isEmpty);
    expect(backend.calls, contains('reset'));
  });

  test('new open of identical URI resets original-source evidence', () async {
    final backend = FakeBackend()
      ..factsForOpen.addAll([
        _facts(profile: 8, compatibility: 4, el: false),
        _facts(gamma: 'bt.1886'),
      ]);
    final session = _session(backend);
    addTearDown(session.dispose);
    final media = Media('test://source');
    await session.open(media, hint: _p84);
    final first = session.report.value;
    await session.open(media);
    final second = session.report.value;
    expect(first.source!.dynamicMetadata, HdrDynamicMetadata.dolbyVision);
    expect(second.source!.dynamicMetadata, HdrDynamicMetadata.none);
    expect(second.sourceFacts!.initialHint, isNull);
    expect(second.sourceFacts!.reviewCount, 1);
    expect(second.sourceFacts!.origins.containsKey(HdrSourceField.dvProfile), isFalse);
    expect(second.generation, greaterThan(first.generation));
  });

  test('superseded delayed review cannot leak source evidence to the next open', () async {
    final backend = _HeldReviewBackend()
      ..factsForOpen.addAll([_facts(), _facts(gamma: 'pq')]);
    final session = _session(backend);
    addTearDown(session.dispose);
    final first = session.open(Media('test://source'), hint: _p84);
    await backend.entered.future;
    final second = session.open(Media('test://source'), hint: _hdr10);
    backend.release.complete(_facts(profile: 8, compatibility: 4, el: false));
    await Future.wait([first, second]);
    final report = session.report.value;
    expect(report.source, _hdr10);
    expect(report.sourceFacts!.initialHint, _hdr10);
    expect(report.sourceFacts!.reviewCount, 1);
    expect(report.sourceFacts!.origins.containsKey(HdrSourceField.dvProfile), isFalse);
    expect(report.verified, isTrue);
  });

  test('automatic preference rebuild retains original track evidence', () async {
    final backend = FakeBackend()
      ..factsForOpen.addAll([
        _facts(profile: 8, compatibility: 4, el: false),
        _facts(),
      ]);
    final session = _session(backend);
    addTearDown(session.dispose);
    await session.open(Media('test://source'), hint: _p84);
    final first = session.report.value;
    await session.setPreference(HdrOutputPreference.off);
    final second = session.report.value;
    expect(backend.opened, hasLength(2));
    expect(second.actual!.strategy, HdrStrategy.toneMapSdr);
    expect(second.source, _p84);
    expect(second.sourceFacts!.initialHint, same(first.sourceFacts!.initialHint));
    expect(second.sourceFacts!.reviewCount, 2);
    expect(second.sourceFacts!.origins[HdrSourceField.dvProfile],
        HdrSourceFactOrigin.track);
    expect(second.generation, greaterThan(first.generation));
    expect(first.sourceFacts!.reviewCount, 1);
  });

  test('report copies retain evidence without copying it into frame facts', () async {
    final backend = FakeBackend()..factsForOpen.add(_facts());
    final session = _session(backend);
    addTearDown(session.dispose);
    await session.open(Media('test://source'), hint: _p84);
    final report = session.report.value;
    expect(report.copyWith(diagnostic: 'test').sourceFacts, same(report.sourceFacts));
    final prepared = backend.preparedPlans.single;
    expect(prepared.copyWith(excluded: const {}).sourceFacts,
        same(prepared.sourceFacts));
    expect(prepared.sourceFacts!.reviewCount, 0);
    expect(report.sourceFacts!.reviewCount, 1);
  });
}

class _HeldReviewBackend extends FakeBackend {
  final entered = Completer<void>();
  final release = Completer<HdrReviewFacts>();
  var reads = 0;

  @override
  Future<HdrReviewFacts> reviewFacts(HdrOpenPlan plan) async {
    if (reads++ == 0) {
      entered.complete();
      return release.future;
    }
    return super.reviewFacts(plan);
  }
}
