import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' show FileLoadedRecord, Media, VideoParams;
import 'package:media_kit_video/src/hdr/hdr_capabilities.dart';
import 'package:media_kit_video/src/hdr/hdr_decoder_review.dart';
import 'package:media_kit_video/src/hdr/android_mediacodec_configuration.dart';
import 'package:media_kit_video/src/hdr/hdr_native_dv_option_owner.dart';
import 'package:media_kit_video/src/hdr/hdr_native_dv_review_evidence.dart';
import 'package:media_kit_video/src/video_controller/android_video_controller/platform_surface_release.dart';
import 'package:synchronized/synchronized.dart';
import 'package:media_kit_video/src/hdr/hdr_open_coordinator.dart';
import 'package:media_kit_video/src/hdr/hdr_open_plan.dart';
import 'package:media_kit_video/src/hdr/hdr_output_event.dart';
import 'package:media_kit_video/src/hdr/hdr_route.dart';
import 'package:media_kit_video/src/hdr/hdr_route_planner.dart';
import 'package:media_kit_video/src/hdr/hdr_source_descriptor.dart';
import 'package:media_kit_video/src/hdr/hdr_strategy.dart';
import 'package:media_kit_video/src/hdr/hdr_strategy_realizer.dart';
import 'package:media_kit_video/src/hdr/hdr_video_session.dart';

/// S5 verification 2: session orchestration behaviors on a fake backend and
/// fake Player property stubs (plan section S5; requirement R2/R3/R4.2).
///
/// The session runs fully on the injected seams: capability snapshot,
/// position, platform flag and backend. No Player, controller or platform
/// channel is touched.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final media = Media('test://media');

  const hdr10 = HdrSourceDescriptor(
    codec: 'hevc',
    transfer: 'pq',
    primaries: 'bt.2020',
    enhancementLayer: false,
  );
  const p84 = HdrSourceDescriptor(
    codec: 'hevc',
    transfer: 'hlg',
    primaries: 'bt.2020',
    dynamicMetadata: HdrDynamicMetadata.dolbyVision,
    dvProfile: 8,
    dvCompatibilityId: 4,
    enhancementLayer: false,
  );
  const p5 = HdrSourceDescriptor(
    codec: 'hevc',
    dynamicMetadata: HdrDynamicMetadata.dolbyVision,
    dvProfile: 5,
    dvCompatibilityId: 0,
    enhancementLayer: false,
  );
  const undescribed = HdrSourceDescriptor();
  const sdr = HdrSourceDescriptor(
    transfer: 'bt.1886',
    primaries: 'bt.709',
    enhancementLayer: false,
  );

  HdrCapabilities caps({
    Set<int>? types = const {1, 2, 3},
    bool p5Pipeline = true,
    bool ext = true,
    int sdkInt = 29,
  }) =>
      HdrCapabilities(
        sdkInt: sdkInt,
        displayHdrTypes: types,
        hevcDecoders: const <HdrDecoderInfo>[],
        dolbyVisionDecoders: const <HdrDecoderInfo>[],
        p5PipelineAvailable: p5Pipeline,
        dataSpaceBridgeLoaded: true,
        dataSpaceExt: ext
            ? const HdrDataSpaceExtInfo(id: 'lya-pq', applicable: true)
            : null,
      );

  HdrCapabilities lgPqCaps() => HdrCapabilities(
        sdkInt: 24,
        displayHdrTypes: const {2},
        hevcDecoders: const [],
        dolbyVisionDecoders: const [],
        p5PipelineAvailable: true,
        dataSpaceBridgeLoaded: true,
        dataSpaceExt: const HdrDataSpaceExtInfo(
          id: 'lg-pq',
          applicable: true,
        ),
      );

  HdrReviewFacts facts({
    String? gamma,
    String? primaries,
    int? profile,
    String codec = 'hevc',
    String hwdec = 'mediacodec',
    bool? hdrVivid,
  }) =>
      HdrReviewFacts(
        videoParams:
            gamma == null && primaries == null
                ? null
                : const VideoParams(gamma: 'pq', primaries: 'bt.2020'),
        dolbyVisionProfile: profile,
        codec: codec,
        hwdecCurrent: hwdec,
        path: media.uri,
        hdrVivid: hdrVivid,
      );

  HdrReviewFacts gammaFacts({
    required String gamma,
    int? profile,
    String hwdec = 'mediacodec',
  }) =>
      HdrReviewFacts(
        videoParams: VideoParams(gamma: gamma, primaries: 'bt.2020'),
        dolbyVisionProfile: profile,
        codec: 'hevc',
        hwdecCurrent: hwdec,
        path: media.uri,
      );

  Future<void> pumpUntil(bool Function() condition) async {
    for (var i = 0; i < 5000; i++) {
      if (condition()) return;
      await Future<void>.delayed(Duration.zero);
    }
    fail('pumpUntil condition not met');
  }

  HdrVideoSession makeSession({
    required FakeBackend backend,
    required HdrCapabilities capabilities,
    Duration position = Duration.zero,
    HdrOutputPreference preference = HdrOutputPreference.auto,
    HdrRoutingPolicy policy = HdrRoutingPolicy.defaults,
  }) {
    return HdrVideoSession.forTesting(
      player: null,
      preference: preference,
      policy: policy,
      capabilitiesProvider: () async => capabilities,
      positionProvider: () => position,
      isAndroid: true,
      backend: backend,
    );
  }

  test('hint agreeing with the decoder review causes zero rebuilds', () async {
    final backend = FakeBackend()
      ..factsForOpen.add(gammaFacts(gamma: 'pq'));
    final session = makeSession(backend: backend, capabilities: caps());
    final events = <HdrOutputEvent>[];
    session.events.listen(events.add);

    await session.open(media, hint: hdr10);
    await pumpEventQueue();

    expect(backend.opened, hasLength(1));
    expect(backend.opened.single.route.strategy, HdrStrategy.baseLayerDirect);
    expect(backend.calls, isNot(contains('stop-after-open')));
    final report = session.report.value;
    expect(report.verified, isTrue);
    expect(report.source, hdr10);
    expect(report.sourceOrigin, HdrReportSource.hint);
    expect(report.actual!.strategy, HdrStrategy.baseLayerDirect);
    expect(
      events.whereType<HdrDegradedEvent>(),
      isEmpty,
    );
    expect(
      events.whereType<HdrReclassifiedEvent>(),
      isEmpty,
    );
    expect(events.whereType<HdrRouteAppliedEvent>(), hasLength(1));
    await session.dispose();
  });

  test('wrong hint rebuilds once, keeps the position, reports decoder origin',
      () async {
    final backend = FakeBackend()
      ..factsForOpen.add(gammaFacts(gamma: 'pq'))
      ..factsForOpen.add(gammaFacts(gamma: 'pq'));
    final session = makeSession(
      backend: backend,
      capabilities: caps(),
      position: const Duration(seconds: 5),
    );
    final events = <HdrOutputEvent>[];
    session.events.listen(events.add);

    await session.open(media, hint: undescribed);
    await pumpEventQueue();

    expect(backend.opened, hasLength(2));
    expect(backend.opened.first.route.strategy, HdrStrategy.sdrDirect);
    expect(backend.opened.last.route.strategy, HdrStrategy.baseLayerDirect);
    expect(backend.opened.last.start, const Duration(seconds: 5));
    final report = session.report.value;
    expect(report.source, hdr10);
    expect(report.sourceOrigin, HdrReportSource.decoder);
    expect(report.actual!.strategy, HdrStrategy.baseLayerDirect);
    final reclassified = events.whereType<HdrReclassifiedEvent>().toList();
    expect(reclassified, hasLength(1));
    expect(reclassified.single.rebuilt, isTrue);
    await session.dispose();
  });

  test('no hint opens SDR first and rebuilds once after the HDR review',
      () async {
    final backend = FakeBackend()
      ..factsForOpen.add(gammaFacts(gamma: 'pq'))
      ..factsForOpen.add(gammaFacts(gamma: 'pq'));
    final session = makeSession(
      backend: backend,
      capabilities: caps(),
      position: const Duration(seconds: 4),
    );
    final events = <HdrOutputEvent>[];
    session.events.listen(events.add);

    await session.open(media);
    await pumpEventQueue();

    expect(backend.opened, hasLength(2));
    expect(backend.opened.first.route.strategy, HdrStrategy.sdrDirect);
    expect(backend.opened.last.route.strategy, HdrStrategy.baseLayerDirect);
    expect(backend.opened.last.start, const Duration(seconds: 4));
    final report = session.report.value;
    expect(report.source, hdr10);
    expect(report.sourceOrigin, HdrReportSource.decoder);
    expect(
      events.whereType<HdrReclassifiedEvent>().single.rebuilt,
      isTrue,
    );
    await session.dispose();
  });

  test('a failed decoder on the second review is not verified or opened a third time',
    () async {
  // First open is SDR with a valid decoder. Actual HDR facts cause a
  // legitimate topology rebuild; only the second decoder fails.
  final backend = FakeBackend()
    ..factsForOpen.add(gammaFacts(gamma: 'pq'))
    ..factsForOpen.add(facts(gamma: 'pq', primaries: 'bt.2020', hwdec: 'no'));
  final session = makeSession(
    backend: backend,
    capabilities: caps(),
    position: const Duration(seconds: 2),
  );
  final events = <HdrOutputEvent>[];
  session.events.listen(events.add);
  await session.open(media);
  await pumpEventQueue();
  expect(backend.opened, hasLength(2));
  expect(backend.opened.first.route.strategy, HdrStrategy.sdrDirect);
  expect(backend.opened.last.route.strategy, HdrStrategy.baseLayerDirect);
  expect(session.report.value.verified, isFalse);
  expect(session.report.value.degradeReason, HdrDegradeReason.hwdecMismatch);
  expect(events.whereType<HdrRouteAppliedEvent>(), isEmpty);
  expect(events.whereType<HdrErrorEvent>().single.reason,
      HdrDegradeReason.hwdecMismatch);
  expect(events.whereType<HdrReclassifiedEvent>().single.rebuilt, isTrue);
  expect(backend.calls, contains('stop'));
  expect(backend.calls, contains('reset'));
  await session.dispose();
});

  test(
      'persistent second-review mismatch blocks even with another playable route',
      () async {
    addTearDown(() => HdrStrategyRealizer.mkstBridgeProbeOverride = null);
    HdrStrategyRealizer.mkstBridgeProbeOverride = () => false;
    for (final experimental in [true, false]) {
      final backend = FakeBackend()
        ..factsForOpen.addAll([
          gammaFacts(gamma: 'pq', hwdec: 'mediacodec-copy'),
          gammaFacts(gamma: 'pq', hwdec: 'no'),
        ]);
      final session = makeSession(
        backend: backend,
        capabilities: lgPqCaps(),
        policy: HdrRoutingPolicy(allowExperimental: experimental),
      );
      final events = <HdrOutputEvent>[];
      session.events.listen(events.add);
      await session.open(media);
      await pumpEventQueue();
      expect(backend.opened, hasLength(2));
      expect(backend.opened.first.route.strategy, HdrStrategy.sdrDirect);
      expect(backend.opened.last.route.strategy, HdrStrategy.baseLayerDirect);
      expect(session.report.value.verified, isFalse);
      expect(
          session.report.value.degradeReason, HdrDegradeReason.hwdecMismatch);
      expect(session.report.value.sourceFacts?.source, hdr10);
      expect(events.whereType<HdrRouteAppliedEvent>(), isEmpty);
      expect(events.whereType<HdrErrorEvent>().single.reason,
          HdrDegradeReason.hwdecMismatch);
      expect(backend.calls.skip(backend.calls.length - 2), ['stop', 'reset']);
      await session.dispose();
    }
  });

  test('persistent route-only disagreement blocks with an accurate reason', () async {
    final backend = FakeBackend()
      ..factsForOpen.addAll([
        gammaFacts(gamma: 'pq'),
        gammaFacts(gamma: 'hlg'),
      ]);
    final session = makeSession(backend: backend, capabilities: caps());
    final events = <HdrOutputEvent>[];
    session.events.listen(events.add);
    await session.open(media);
    await pumpEventQueue();
    expect(backend.opened, hasLength(2));
    expect(session.report.value.verified, isFalse);
    expect(session.report.value.degradeReason,
        HdrDegradeReason.routeReviewMismatch);
    expect(session.report.value.sourceFacts?.source.transfer, 'hlg');
    expect(session.report.value.diagnostic,
        contains('mismatch persisted after rebuild'));
    expect(events.whereType<HdrRouteAppliedEvent>(), isEmpty);
    expect(events.whereType<HdrErrorEvent>().single.reason,
        HdrDegradeReason.routeReviewMismatch);
    expect(backend.calls.skip(backend.calls.length - 2), ['stop', 'reset']);
    await session.dispose();
  });

  for (final phase in ['prepare', 'configure']) {
    test('actual output readiness timeout in $phase excludes its topology', () async {
      final raw = TimeoutException('actual output readiness');
      final typed = HdrOutputBindTimeout(raw);
      final backend = FakeBackend()
        ..prepareErrorOnce = phase == 'prepare' ? typed : null
        ..attemptScripts.add(AttemptScript(
          configureError: phase == 'configure' ? typed : null,
        ));
      final session = makeSession(backend: backend, capabilities: caps());
      final events = <HdrOutputEvent>[];
      session.events.listen(events.add);
      await session.open(media, hint: hdr10);
      await pumpEventQueue();
      expect(backend.opened, hasLength(1));
      expect(backend.opened.single.route.strategy, HdrStrategy.toneMapSdr);
      expect(backend.preparedPlans.last.excluded[HdrRouteDependency.topologyPlatformView],
          HdrDegradeReason.outputBindTimeout);
      expect(events.whereType<HdrDegradedEvent>().single.reason,
          HdrDegradeReason.outputBindTimeout);
      expect(session.report.value.verified, isTrue);
      await session.dispose();
    });
  }

  for (final phase in ['configure', 'open', 'review']) {
    test('$phase timeout aborts without excluding a working PlatformView',
        () async {
      final timeout = TimeoutException('$phase timed out');
      final backend = FakeBackend()
        ..attemptScripts.add(AttemptScript(
          configureError: phase == 'configure' ? timeout : null,
          openError: phase == 'open' ? timeout : null,
          reviewError: phase == 'review' ? timeout : null,
        ));
      final session = makeSession(backend: backend, capabilities: caps());
      final events = <HdrOutputEvent>[];
      session.events.listen(events.add);
      await expectLater(
          session.open(media, hint: hdr10), throwsA(same(timeout)));
      await pumpEventQueue();
      expect(backend.preparedPlans, hasLength(1));
      expect(backend.preparedPlans.single.excluded,
          isNot(contains(HdrRouteDependency.topologyPlatformView)));
      expect(events.whereType<HdrDegradedEvent>(), isEmpty);
      expect(events.whereType<HdrRouteAppliedEvent>(), isEmpty);
      expect(session.report.value.verified, isFalse);
      expect(session.report.value.degradeReason,
          isNot(HdrDegradeReason.outputBindTimeout));
      expect(session.report.value.error, same(timeout));
      expect(backend.calls.skip(backend.calls.length - 2), ['stop', 'reset']);
      await session.dispose();
    });
  }

  test('the already admitted second HDR attempt may still pass review', () async {
    final backend = FakeBackend()
      ..attemptScripts.add(const AttemptScript(dataSpaceApplyFailed: true));
    final session = makeSession(
      backend: backend,
      capabilities: caps(),
      policy: const HdrRoutingPolicy(
        preferences: {
          HdrSourceClass.hdr10: [
            HdrStrategy.baseLayerConvert,
            HdrStrategy.baseLayerDirect,
            HdrStrategy.toneMapSdr,
          ],
        },
        allowExperimental: true,
      ),
    );
    await session.open(media, hint: hdr10);
    expect(backend.preparedPlans, hasLength(2));
    expect(backend.preparedPlans.first.route.strategy, HdrStrategy.baseLayerConvert);
    expect(backend.preparedPlans.last.route.strategy, HdrStrategy.baseLayerDirect);
    expect(backend.opened, hasLength(1));
    expect(session.report.value.verified, isTrue);
    expect(session.report.value.actual!.strategy, HdrStrategy.baseLayerDirect);
    await session.dispose();
  });

  test(
      'dataspace failure degrades along the candidates, tone-map keeps '
      'playing, every step emits an event', () async {
    // Convert(PQ) fails its dataspace application; the next HDR candidate
    // (direct HLG) is tried and fails on the output bind; the fallback
    // tone-map route opens and playback continues.
    final backend = FakeBackend()
      ..attemptScripts.addAll(const [
        AttemptScript(dataSpaceApplyFailed: true),
        AttemptScript(bindTimeout: true),
      ])
      ..factsForOpen.add(gammaFacts(gamma: 'hlg', profile: 8))
      ..factsForOpen.add(gammaFacts(gamma: 'hlg', profile: 8))
      ..factsForOpen.add(gammaFacts(gamma: 'hlg', profile: 8));
    // `baseLayerConvert` for P8.4 is experimental; the gate must be open so
    // the dataspace-dependent candidate is actually selected first.
    final policy = const HdrRoutingPolicy(
      preferences: {
        HdrSourceClass.dvP84: [
          HdrStrategy.baseLayerConvert,
          HdrStrategy.baseLayerDirect,
          HdrStrategy.toneMapSdr,
        ],
      },
      allowExperimental: true,
    );
    final session = makeSession(
      backend: backend,
      capabilities: caps(),
      policy: policy,
    );
    final events = <HdrOutputEvent>[];
    session.events.listen(events.add);

    await session.open(media, hint: p84);
    await pumpEventQueue();

    // The convert attempt fails at its dataspace (before the media opens)
    // and the direct attempt fails at the output bind, so only the
    // tone-map fallback opens — playback continues on it.
    expect(backend.opened, hasLength(1));
    expect(backend.opened.single.route.strategy, HdrStrategy.toneMapSdr);
    expect(backend.calls,
        contains('configure:baseLayerConvert:pq')); // First HDR attempt.
    expect(backend.calls,
        contains('configure:baseLayerDirect:-')); // Next HDR candidate.
    expect(backend.calls, contains('configure:toneMapSdr:-'));
    final degraded = events.whereType<HdrDegradedEvent>().toList();
    expect(degraded, hasLength(2));
    expect(degraded[0].reason, HdrDegradeReason.dataSpaceApplyFailed);
    expect(degraded[0].to!.strategy, HdrStrategy.baseLayerDirect);
    expect(degraded[1].reason, HdrDegradeReason.outputBindTimeout);
    expect(degraded[1].to!.strategy, HdrStrategy.toneMapSdr);
    final report = session.report.value;
    expect(report.verified, isTrue);
    expect(report.actual!.strategy, HdrStrategy.toneMapSdr);
    expect(backend.preparedPlans.last.excluded[HdrRouteDependency.topologyPlatformView],
        HdrDegradeReason.outputBindTimeout);
    expect(events.whereType<HdrRouteAppliedEvent>(), hasLength(1));
    await session.dispose();
  });

  test('a HDR Vivid side-data fact reclassifies an HDR10 hint and rebuilds '
      'on the hdrVivid maturity row', () async {
    final backend = FakeBackend()
      ..factsForOpen
          .add(facts(gamma: 'pq', primaries: 'bt.2020', hdrVivid: true))
      ..factsForOpen
          .add(facts(gamma: 'pq', primaries: 'bt.2020', hdrVivid: true));
    final session = makeSession(backend: backend, capabilities: caps());
    final events = <HdrOutputEvent>[];
    session.events.listen(events.add);

    await session.open(media, hint: hdr10);
    await pumpEventQueue();

    // hdrVivid class maturity (hdr_strategy.dart, locked by the table test):
    // baseLayerDirect experimental, metadataReshape unsupported,
    // toneMapSdr experimental — every default candidate is gated off, so
    // the tone-map safety net is selected; the route changes and the
    // single per-open rebuild applies at the playback position.
    expect(backend.opened, hasLength(2));
    expect(backend.opened.first.route.strategy, HdrStrategy.baseLayerDirect);
    expect(backend.opened.last.route.strategy, HdrStrategy.toneMapSdr);
    final report = session.report.value;
    expect(report.verified, isTrue);
    expect(report.source!.dynamicMetadata, HdrDynamicMetadata.hdrVivid);
    expect(report.sourceOrigin, HdrReportSource.decoder);
    expect(report.actual!.strategy, HdrStrategy.toneMapSdr);
    expect(events.whereType<HdrReclassifiedEvent>().single.rebuilt, isTrue);
    await session.dispose();
  });

  test('hwdec mismatch cannot reuse the failed stage through SDR fallback', () async {
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

  test('ordinary to native internal reopen clears predecessor decoder observation', () async {
    // Synthetic native endpoints exercise the real Session consumer and report
    // boundary. They do not claim any device codec or display acceptance.
    const nativeRaw = '{"api":1,"mime":"video/dolby-vision",'
        '"codec":"c2.native.dv","native-dv-active":true}';
    final playerIdentity = Object(), controllerIdentity = Object();
    final sourceIdentity = HdrOptionSourceIdentity(
      player: playerIdentity, path: media.uri,
      playlistEntryId: '7', fileLoadedEpoch: 4,
    );
    final output = HdrNativeDvOutputSnapshot(controllerIdentity,
      const AndroidSurfaceAccountId(handle: 11, generation: 2,
        viewId: 3, surfaceGeneration: 4, wid: 5));
    final backend = FakeBackend()
      ..factsForOpen.addAll([
        HdrReviewFacts(codec: 'hevc', hwdecCurrent: 'mediacodec', path: media.uri,
          dolbyVisionProfile: 5, dvCompatibilityId: 0, dvElPresent: false,
          decoderObservation: const HdrDecoderObservation(
            playlistEntryId: 1, fileLoadedEpoch: 1, decoder: 'hevc_mediacodec',
            decoderDescription: '', hwdec: 'mediacodec',
            pixelFormat: 'mediacodec', hwPixelFormat: 'nv12')),
        HdrReviewFacts(codec: 'hevc', hwdecCurrent: 'mediacodec', path: media.uri,
          dolbyVisionProfile: 5, dvCompatibilityId: 0, dvElPresent: false,
          nativeDvEvidence: HdrNativeDvReviewEvidence(source: sourceIdentity,
            loaded: const FileLoadedRecord(4, 7), controller: output.controller,
            output: output.identity,
            configuration: AndroidMediaCodecConfiguration.parse(nativeRaw)!,
            hwdecCurrent: 'mediacodec')),
      ]);
    final session = HdrVideoSession.forTesting(
      backend: backend, isAndroid: true,
      capabilitiesProvider: () async => caps(),
      nativePlayerIdentity: playerIdentity, nativePlayerLock: Lock(),
      readNativeIdentity: () async => sourceIdentity,
      readNativeProperty: (name) async =>
          name == 'android-mediacodec-info' ? nativeRaw : 'mediacodec',
      readNativeOutput: () => output,
      reviewMonotonicNow: () => Duration.zero,
      routePlanner: ({required source, required capabilities, required policy,
          required preference, required excluded}) {
        final ordinary = HdrRoutePlanner.plan(source: source,
          capabilities: capabilities, policy: policy, preference: preference,
          excluded: excluded);
        if (HdrSourceClass.of(source) != HdrSourceClass.dvP5) return ordinary;
        const nativeRoute = HdrRoute(strategy: HdrStrategy.nativeDolbyVision,
          presentation: HdrPresentation.nativeDolbyVision,
          outputTransfer: HdrOutputTransfer.dolbyVision,
          appliesDynamicMetadata: true, topology: HdrTopology.platformView,
          vo: 'mediacodec_embed', hwdec: 'mediacodec',
          targetPrim: null, targetTrc: null, surfaceTransfer: null,
          stripDvRpu: false);
        const candidate = HdrCandidate(strategy: HdrStrategy.nativeDolbyVision,
          maturity: HdrStrategyMaturity.unsupported, route: nativeRoute, feasible: true);
        return HdrRoutePrediction(source: source, selected: candidate,
          candidates: [candidate, ...ordinary.candidates],
          presentation: nativeRoute.presentation,
          confidence: HdrPredictionConfidence.unverified, playable: true);
      },
    );
    await session.open(media);
    expect(backend.opened.map((plan) => plan.route.strategy),
        [HdrStrategy.sdrDirect, HdrStrategy.nativeDolbyVision]);
    expect(session.report.value.verified, isTrue);
    expect(session.report.value.actual!.strategy, HdrStrategy.nativeDolbyVision);
    expect(session.report.value.decoderObservation, isNull);
    expect(session.report.value.decoderIdentityKnown, isFalse);
    await session.dispose();
  });

  test('ordinary unnamed decoder keeps route and identity verification separate', () async {
    final backend = FakeBackend()
      ..factsForOpen.add(HdrReviewFacts(
        codec: 'hevc', hwdecCurrent: 'mediacodec', path: media.uri,
        videoParams: const VideoParams(gamma: 'pq', primaries: 'bt.2020'),
        decoderObservation: const HdrDecoderObservation(
          playlistEntryId: 1, fileLoadedEpoch: 1,
          decoder: '', decoderDescription: '', hwdec: 'mediacodec',
          pixelFormat: 'mediacodec', hwPixelFormat: 'nv12',
        ),
      ));
    final session = makeSession(backend: backend, capabilities: caps());
    await session.open(media, hint: hdr10);
    expect(session.report.value.verified, isTrue);
    expect(session.report.value.decoderIdentityKnown, isFalse);
    expect(session.report.value.decoderObservation!.pixelFormat, 'mediacodec');
    expect(backend.opened, hasLength(1));
    await session.dispose();
  });

  test('ordinary observation blocks wrong MIME despite matching hwdec', () async {
    final backend = FakeBackend()
      ..factsForOpen.add(HdrReviewFacts(
        codec: 'hevc', hwdecCurrent: 'mediacodec', path: media.uri,
        videoParams: const VideoParams(gamma: 'pq', primaries: 'bt.2020'),
        decoderObservation: HdrDecoderObservation(
          playlistEntryId: 1, fileLoadedEpoch: 1,
          decoder: 'h264_mediacodec', decoderDescription: '',
          hwdec: 'mediacodec', pixelFormat: 'mediacodec', hwPixelFormat: 'nv12',
          mediaCodecConfiguration: AndroidMediaCodecConfiguration.parse(
            '{"api":1,"mime":"video/avc","codec":"c2.avc","native-dv-active":false}'),
        ),
      ));
    final session = makeSession(backend: backend, capabilities: caps());
    final events = <HdrOutputEvent>[];
    session.events.listen(events.add);
    await session.open(media, hint: hdr10);
    await pumpEventQueue();
    expect(backend.opened, hasLength(1));
    expect(session.report.value.verified, isFalse);
    expect(session.report.value.degradeReason, HdrDegradeReason.routeReviewMismatch);
    expect(events.whereType<HdrRouteAppliedEvent>(), isEmpty);
    expect(backend.calls, contains('stop'));
    expect(backend.calls, contains('reset'));
    await session.dispose();
  });

  test('API 24 copy route accepts matching mediacodec-copy without reopen',
      () async {
    final backend = FakeBackend()
      ..factsForOpen.add(const HdrReviewFacts(
        hwdecCurrent: 'mediacodec-copy',
        path: 'test://media',
      ));
    final session = makeSession(
      backend: backend,
      capabilities: caps(sdkInt: 24),
    );
    final events = <HdrOutputEvent>[];
    session.events.listen(events.add);

    await session.open(media, hint: sdr);
    await pumpEventQueue();

    expect(backend.opened, hasLength(1));
    expect(backend.opened.single.route.hwdec, 'mediacodec-copy');
    expect(session.report.value.hwdecCurrent, 'mediacodec-copy');
    expect(session.report.value.degradeReason, isNull);
    expect(events.whereType<HdrDegradedEvent>(), isEmpty);
    await session.dispose();
  });

  test('API 24 copy mismatch blocks rather than retrying the same failed copy path',
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

  test('SurfaceTexture mismatch is excluded and rebuild remains bounded',
      () async {
    addTearDown(() {
      HdrStrategyRealizer.mkstBridgeProbeOverride = null;
    });
    for (final allowExperimental in [false, true]) {
      HdrStrategyRealizer.mkstBridgeProbeOverride = () => true;
      final backend = FakeBackend()
        ..factsForOpen.addAll([
          facts(gamma: 'pq', primaries: 'bt.2020', hwdec: 'mediacodec'),
          facts(gamma: 'pq', primaries: 'bt.2020', hwdec: 'no'),
        ]);
      final session = makeSession(
        backend: backend,
        capabilities: lgPqCaps(),
        policy: HdrRoutingPolicy(
          preferences: const {
            HdrSourceClass.hdr10: [
              HdrStrategy.baseLayerConvert,
              HdrStrategy.toneMapSdr,
            ],
          },
          allowExperimental: allowExperimental,
        ),
        position: const Duration(seconds: 2),
      );
      final events = <HdrOutputEvent>[];
      session.events.listen(events.add);

      await session.open(media, hint: hdr10);
      await pumpEventQueue();

      expect(backend.opened, hasLength(2),
          reason: 'one replan is the per-open bound; experimental='
              '$allowExperimental');
      expect(backend.opened.first.route.hwdec, 'surfacetexture');
      expect(backend.opened.last.route.hwdec, 'mediacodec-copy');
      expect(backend.opened.last.route.strategy, HdrStrategy.toneMapSdr);
      expect(session.report.value.verified, isFalse);
      expect(session.report.value.degradeReason, HdrDegradeReason.hwdecMismatch);
      expect(events.whereType<HdrRouteAppliedEvent>(), isEmpty);
      expect(events.whereType<HdrErrorEvent>(), hasLength(1));
      expect(backend.calls, contains('reset'));
      await session.dispose();
    }
  });

  test('SurfaceTexture mismatch can recover through independent copy mode',
      () async {
    addTearDown(() {
      HdrStrategyRealizer.mkstBridgeProbeOverride = null;
    });
    for (final allowExperimental in [false, true]) {
      HdrStrategyRealizer.mkstBridgeProbeOverride = () => true;
      final backend = FakeBackend()
        ..factsForOpen.addAll([
          facts(gamma: 'pq', primaries: 'bt.2020', hwdec: 'mediacodec'),
          facts(gamma: 'pq', primaries: 'bt.2020', hwdec: 'mediacodec-copy'),
        ]);
      final session = makeSession(
        backend: backend,
        capabilities: lgPqCaps(),
        policy: HdrRoutingPolicy(
          preferences: const {
            HdrSourceClass.hdr10: [
              HdrStrategy.baseLayerConvert,
              HdrStrategy.toneMapSdr,
            ],
          },
          allowExperimental: allowExperimental,
        ),
        position: const Duration(seconds: 2),
      );
      final events = <HdrOutputEvent>[];
      session.events.listen(events.add);

      await session.open(media, hint: hdr10);
      await pumpEventQueue();

      expect(backend.opened, hasLength(2),
          reason: 'one replan is the per-open bound; experimental='
              '$allowExperimental');
      expect(backend.opened.first.route.hwdec, 'surfacetexture');
      expect(backend.opened.last.route.hwdec, 'mediacodec-copy');
      expect(backend.opened.last.route.strategy, HdrStrategy.toneMapSdr);
      expect(session.report.value.hwdecCurrent, 'mediacodec-copy');
      expect(session.report.value.actual!.hwdec, 'mediacodec-copy');
      expect(session.report.value.verified, isTrue);
      expect(events.whereType<HdrRouteAppliedEvent>(), hasLength(1));
      expect(
        backend.preparedPlans.last.excluded,
        contains(HdrRouteDependency.hwdecSurfaceTexture),
      );
      expect(
        backend.preparedPlans.last.excluded,
        isNot(contains(HdrRouteDependency.hwdecMediacodecCopy)),
      );
      await session.dispose();
    }
  });

  test('missing P5 pipeline publishes Error and never opens the media',
      () async {
    final backend = FakeBackend();
    final session = makeSession(
      backend: backend,
      capabilities: caps(p5Pipeline: false),
    );
    final events = <HdrOutputEvent>[];
    session.events.listen(events.add);

    await session.open(media, hint: p5);
    await pumpEventQueue();

    expect(backend.opened, isEmpty);
    expect(backend.calls.where((call) => call.startsWith('open:')), isEmpty);
    final report = session.report.value;
    expect(report.verified, isFalse);
    expect(report.degradeReason, HdrDegradeReason.p5PipelineUnavailable);
    final errors = events.whereType<HdrErrorEvent>().toList();
    expect(errors, hasLength(1));
    expect(errors.single.reason, HdrDegradeReason.p5PipelineUnavailable);
    expect(events.whereType<HdrRouteAppliedEvent>(), isEmpty);
    await session.dispose();
  });

  test('a newer open supersedes the old one: no stale report, backend '
      'rolled back', () async {
    final backend = FakeBackend()..holdConfigure = Completer<void>();
    final session = makeSession(backend: backend, capabilities: caps());
    final events = <HdrOutputEvent>[];
    session.events.listen(events.add);

    final first = session.open(media, hint: hdr10);
    await pumpUntil(() => backend.calls
        .any((call) => call.startsWith('configure:baseLayerDirect:-')));
    final second = session.open(media, hint: p84);
    backend.holdConfigure!.complete();
    await first; // Superseded opens return normally.
    await second;
    await pumpEventQueue();

    expect(backend.opened, hasLength(1));
    expect(backend.opened.single.route.outputTransfer,
        HdrOutputTransfer.hlg); // Only the P8.4 open reached the backend.
    // The aborted transaction rolled back before the newer one ran.
    final firstConfigure = backend.calls
        .indexWhere((call) => call.startsWith('configure:baseLayerDirect:-'));
    expect(backend.calls[firstConfigure + 1], 'stop');
    expect(backend.calls[firstConfigure + 2], 'reset');
    final report = session.report.value;
    expect(report.generation, 2);
    expect(report.verified, isTrue);
    expect(report.actual!.outputTransfer, HdrOutputTransfer.hlg);
    expect(
      events.whereType<HdrRouteAppliedEvent>().single.generation,
      2,
    );
    expect(events.whereType<HdrDegradedEvent>(), isEmpty);
    await session.dispose();
  });

  test('dispose during an open closes the resources', () async {
    final backend = FakeBackend()..holdConfigure = Completer<void>();
    final session = makeSession(backend: backend, capabilities: caps());
    final events = <HdrOutputEvent>[];
    session.events.listen(events.add);

    final open = session.open(media, hint: hdr10);
    await pumpUntil(() => backend.calls
        .any((call) => call.startsWith('configure:baseLayerDirect:-')));
    final disposing = session.dispose();
    backend.holdConfigure!.complete();
    await open; // Returns normally, nothing published.
    await disposing;

    expect(backend.opened, isEmpty);
    expect(backend.calls.last, 'reset'); // Rollback closed the side effects.
    expect(session.lastDisposeReport!.clean, isTrue);
    expect(events.whereType<HdrRouteAppliedEvent>(), isEmpty);
    expect(events.whereType<HdrDegradedEvent>(), isEmpty);
  });

  test('playback preference and policy changes rebuild only on route change',
      () async {
    final backend = FakeBackend()
      ..factsForOpen.add(facts(gamma: 'pq', primaries: 'bt.2020'))
      ..factsForOpen.add(facts(gamma: 'pq', primaries: 'bt.2020'));
    final session = makeSession(
      backend: backend,
      capabilities: caps(),
      position: const Duration(seconds: 7),
    );
    final events = <HdrOutputEvent>[];
    session.events.listen(events.add);

    await session.open(media, hint: hdr10);
    await pumpEventQueue();
    expect(backend.opened, hasLength(1));

    // auto → off: the route changes to tone-map; rebuild at the position.
    await session.setPreference(HdrOutputPreference.off);
    await pumpEventQueue();
    expect(backend.opened, hasLength(2));
    expect(backend.opened.last.route.strategy, HdrStrategy.toneMapSdr);
    expect(backend.opened.last.start, const Duration(seconds: 7));
    expect(
      events.whereType<HdrDegradedEvent>().single.reason,
      HdrDegradeReason.preferenceOff,
    );
    // The rebuilt generation's report states why the route degraded (R4.2).
    expect(session.report.value.degradeReason, HdrDegradeReason.preferenceOff);

    // Policy change that does not alter the selected route: no rebuild.
    await session.setPolicy(const HdrRoutingPolicy(preferences: {
      HdrSourceClass.hdr10: [HdrStrategy.toneMapSdr],
    }));
    await pumpEventQueue();
    expect(backend.opened, hasLength(2));
    expect(
      events.whereType<HdrRouteAppliedEvent>(),
      hasLength(2),
    );
    await session.dispose();
  });

  test('capability loss degrades and rebuilds; recovery only emits the event',
      () async {
    final backend = FakeBackend()
      ..factsForOpen.add(facts(gamma: 'pq', primaries: 'bt.2020'))
      ..factsForOpen.add(facts(gamma: 'pq', primaries: 'bt.2020'));
    final session = makeSession(
      backend: backend,
      capabilities: caps(),
      position: const Duration(seconds: 6),
    );
    final events = <HdrOutputEvent>[];
    session.events.listen(events.add);

    await session.open(media, hint: hdr10);
    await pumpEventQueue();
    expect(backend.opened, hasLength(1));

    // The display loses its HDR types: degrade to tone-map in place.
    await session.handleCapabilitiesChanged(caps(types: const <int>{}));
    await pumpEventQueue();
    expect(backend.opened, hasLength(2));
    expect(backend.opened.last.route.strategy, HdrStrategy.toneMapSdr);
    expect(backend.opened.last.start, const Duration(seconds: 6));
    expect(
      events.whereType<HdrDegradedEvent>().single.reason,
      HdrDegradeReason.capabilityLost,
    );
    expect(session.report.value.degradeReason, HdrDegradeReason.capabilityLost);

    // Recovery: only a CapabilityChanged event, never an automatic upgrade.
    final eventsBefore = events.length;
    await session.handleCapabilitiesChanged(caps());
    await pumpEventQueue();
    expect(backend.opened, hasLength(2));
    expect(events.length, eventsBefore + 1);
    expect(events.last, isA<HdrCapabilityChangedEvent>());
    expect(session.report.value.actual!.strategy, HdrStrategy.toneMapSdr);
    await session.dispose();
  });
}

/// Per-attempt behavior of the fake backend's configure/waitForOutput phases.
class AttemptScript {
  const AttemptScript({
    this.dataSpaceApplyFailed = false,
    this.bindTimeout,
    this.configureError,
    this.openError,
    this.reviewError,
  });

  final Object? configureError;
  final Object? openError;
  final Object? reviewError;

  /// `configure` throws [HdrDataSpaceApplyException] for a route with a
  /// surface transfer.
  final bool dataSpaceApplyFailed;

  /// `waitForOutput` throws [TimeoutException]. Defaults to the dataspace
  /// failure so an attempt fails exactly once.
  final bool? bindTimeout;
}

/// The currently opened route, with the start the backend was asked for.
class FakeOpened {
  const FakeOpened(this.route, this.start);
  final HdrRoute route;
  final Duration? start;
}

/// Fake [HdrOpenBackend] over plans: records phase calls, applies scripted
/// per-attempt failures, and hands out decoder facts per open attempt.
class FakeBackend implements HdrOpenBackend<HdrOpenPlan> {
  final calls = <String>[];
  final opened = <FakeOpened>[];
  final preparedPlans = <HdrOpenPlan>[];

  /// Facts returned by [reviewFacts], one entry per attempt (last repeats).
  final factsForOpen = <HdrReviewFacts>[];

  /// Scripted failures, consumed one per [configure] call.
  final attemptScripts = <AttemptScript>[];

  /// When set, [configure] blocks until completed (holds the queue).
  Completer<void>? holdConfigure;
  Object? prepareErrorOnce;

  int _attempt = 0;
  String? _dataSpaceRequested;
  String? _dataSpacePath;
  String? _dataSpaceReadback;
  String _lastHwdec = '';

  AttemptScript get _script => _attempt > 0 && _attempt <= attemptScripts.length
      ? attemptScripts[_attempt - 1]
      : const AttemptScript();

  String _tag(HdrOpenPlan plan) =>
      '${plan.route.strategy.name}:${plan.route.surfaceTransfer ?? "-"}';

  @override
  Future<void> validate(HdrOpenPlan plan) async {}

  @override
  Future<void> stop() async {
    calls.add('stop');
  }

  @override
  Future<void> resetOwnedConfiguration() async {
    calls.add('reset');
  }

  @override
  Future<void> prepareOutput(HdrOpenPlan plan) async {
    calls.add('prepare:${_tag(plan)}');
    preparedPlans.add(plan);
    final error = prepareErrorOnce;
    prepareErrorOnce = null;
    if (error != null) throw error;
  }

  @override
  Future<void> configure(HdrOpenPlan plan) async {
    calls.add('configure:${_tag(plan)}');
    _attempt++;
    if (_script.configureError != null) throw _script.configureError!;
    final transfer = plan.route.surfaceTransfer;
    _dataSpaceRequested = transfer;
    _dataSpacePath = null;
    _dataSpaceReadback = null;
    if (transfer != null) {
      if (_script.dataSpaceApplyFailed) {
        _dataSpacePath = 'none';
        _dataSpaceReadback = 'none';
        throw HdrDataSpaceApplyException(
          transfer,
          path: 'none',
          readback: 'none',
          reason: HdrDegradeReason.dataSpaceApplyFailed,
        );
      }
      _dataSpacePath = 'ext:lya-pq';
      _dataSpaceReadback = 'DATASPACE_BT2020_PQ';
    }
    await holdConfigure?.future;
  }

  @override
  Future<void> waitForOutput(HdrOpenPlan plan) async {
    calls.add('output:${_tag(plan)}');
    final timeout = _script.bindTimeout ?? _script.dataSpaceApplyFailed;
    if (timeout) {
      throw TimeoutException('output bind timeout');
    }
  }

  @override
  Future<void> open(
    HdrOpenPlan plan, {
    Duration? start,
    required bool play,
  }) async {
    calls.add('open:${_tag(plan)}:$start');
    if (_script.openError != null) throw _script.openError!;
    opened.add(FakeOpened(plan.route, start));
  }

  @override
  Future<HdrReviewFacts> reviewFacts(HdrOpenPlan plan) async {
    calls.add('review:${_tag(plan)}');
    if (_script.reviewError != null) throw _script.reviewError!;
    _lastHwdec = factsForOpen.isEmpty
        ? plan.route.hwdec
        : factsForOpen[_attempt - 1 < factsForOpen.length
                ? _attempt - 1
                : factsForOpen.length - 1]
            .hwdecCurrent;
    if (factsForOpen.isEmpty) {
      return HdrReviewFacts(hwdecCurrent: plan.route.hwdec, path: plan.media.uri);
    }
    return factsForOpen[_attempt - 1 < factsForOpen.length
        ? _attempt - 1
        : factsForOpen.length - 1];
  }

  @override
  HdrBackendObservation observe() => HdrBackendObservation(
        dataSpaceRequested: _dataSpaceRequested,
        dataSpacePath: _dataSpacePath,
        dataSpaceReadback: _dataSpaceReadback,
        hwdecCurrent: _lastHwdec,
      );
}
