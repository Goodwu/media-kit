import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit_video/src/routing/video_route_options.dart';
import 'package:media_kit/media_kit.dart'
    show FileLoadedRecord, Media, VideoParams;
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
import 'package:media_kit_video/src/hdr/hdr_video_session.dart';
import 'package:media_kit_video/src/hdr/hdr_yuv_window_arm.dart';

/// S5 verification 2: session orchestration behaviors on a fake backend and
/// fake Player property stubs (plan section S5; requirement R2/R3/R4.2).
///
/// The session runs fully on the injected seams: capability snapshot,
/// position, platform flag and backend. No Player, controller or platform
/// channel is touched.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The process-level lease registry (B1) is static; isolate it per test.
  setUp(HdrYuvWindowProcessRegistry.resetForTesting);

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

  /// LG-class device whose extension declares the YUV window as the only PQ
  /// presentation channel (W1) plus the managed YUV arm protocol: the
  /// convert route's carrier is derived from the channel declaration
  /// (`surfacetexture`) and the arm admission consumes the declared
  /// protocol — replacing the removed probe seam and any device identity.
  HdrCapabilities lgYuvPqCaps() => HdrCapabilities(
        sdkInt: 24,
        displayHdrTypes: const {2},
        hevcDecoders: const [],
        dolbyVisionDecoders: const [],
        p5PipelineAvailable: true,
        dataSpaceBridgeLoaded: true,
        dataSpaceExt: const HdrDataSpaceExtInfo(
          id: 'lg-pq',
          applicable: true,
          pqPresentation: HdrPqPresentation(
            rgbSurface: false,
            yuvWindow: true,
          ),
          setterOnlyTransfers: <String>{'pq', 'pq-itu'},
          yuvWindowArmApi: 1,
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
        videoParams: gamma == null && primaries == null
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
    Future<HdrCapabilities> Function()? capabilitiesProvider,
    void Function(HdrBackendCallDiagnostic<HdrOpenPlan>)?
        onBackendCallDiagnostic,
    Duration position = Duration.zero,
    HdrOutputPreference preference = HdrOutputPreference.auto,
    HdrRoutingPolicy policy = HdrRoutingPolicy.defaults,
    HdrYuvWindowArm? yuvWindowArm,
  }) {
    if (yuvWindowArm != null) {
      backend.yuvWindowArm = yuvWindowArm;
    }
    return HdrVideoSession.forTesting(
      player: null,
      preference: preference,
      policy: policy,
      capabilitiesProvider: capabilitiesProvider ?? (() async => capabilities),
      positionProvider: () => position,
      isAndroid: true,
      backend: backend,
      outputResources: yuvWindowArm,
      onBackendCallDiagnostic: onBackendCallDiagnostic,
    );
  }

  test('hint agreeing with the decoder review causes zero rebuilds', () async {
    final backend = FakeBackend()..factsForOpen.add(gammaFacts(gamma: 'pq'));
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

  test(
      'a failed decoder on the second review is not verified or opened a third time',
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
    final backend = FakeBackend()
      ..factsForOpen.addAll([
        gammaFacts(gamma: 'pq', hwdec: 'mediacodec-copy'),
        gammaFacts(gamma: 'pq', hwdec: 'no'),
      ]);
    final session = makeSession(
      backend: backend,
      capabilities: lgPqCaps(),
    );
    final events = <HdrOutputEvent>[];
    session.events.listen(events.add);
    // The subject is the persistent-mismatch blocking protocol: the explicit
    // sdrEmbed opt-out keeps the unclassified source on the texture SDR head
    // (the unset option now plans the embed execution first at SDK 24).
    await session.open(media,
        options: EffectiveVideoRouteOptions.resolve(
            application: const VideoRouteOptions(sdrEmbed: false)));
    await pumpEventQueue();
    expect(backend.opened, hasLength(2));
    expect(backend.opened.first.route.strategy, HdrStrategy.sdrDirect);
    expect(backend.opened.last.route.strategy, HdrStrategy.baseLayerDirect);
    expect(session.report.value.verified, isFalse);
    expect(session.report.value.degradeReason, HdrDegradeReason.hwdecMismatch);
    expect(session.report.value.sourceFacts?.source, hdr10);
    expect(events.whereType<HdrRouteAppliedEvent>(), isEmpty);
    expect(events.whereType<HdrErrorEvent>().single.reason,
        HdrDegradeReason.hwdecMismatch);
    expect(backend.calls.skip(backend.calls.length - 2), ['stop', 'reset']);
    await session.dispose();
  });

  test('persistent route-only disagreement blocks with an accurate reason',
      () async {
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
    test(
        'actual output readiness timeout in $phase blocks when every '
        'remaining HDR candidate shares the failed topology', () async {
      // The bind timeout is attributed to its output topology, but on an
      // HDR-capable display the only further candidates are the other
      // PlatformView HDR route and the SDR-output tone-map (no implicit SDR
      // fallback). HDR exhausted means blocked, never a texture SDR retry.
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
      await expectLater(session.open(media, hint: hdr10), throwsA(same(typed)));
      await pumpEventQueue();
      expect(backend.opened, isEmpty);
      expect(backend.preparedPlans, hasLength(1));
      expect(events.whereType<HdrDegradedEvent>(), isEmpty);
      expect(events.whereType<HdrRouteAppliedEvent>(), isEmpty);
      final errors = events.whereType<HdrErrorEvent>().toList();
      expect(errors, hasLength(1));
      expect(errors.single.error, same(typed));
      final report = session.report.value;
      expect(report.verified, isFalse);
      expect(report.error, same(typed));
      // The failed attempt's partial configuration is rolled back.
      expect(backend.calls.skip(backend.calls.length - 2), ['stop', 'reset']);
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

  test('the already admitted second HDR attempt may still pass review',
      () async {
    // The C1-C4 stage order is canonical even when a legacy preference list
    // names the baseline first: the plan enters at the C2 reshape, and after
    // its dataspace failure the retry re-plans the complete stage-ordered
    // catalog. The second attempt (C3 direct) is admitted, opens, and must
    // pass review — an already admitted execution route is not re-litigated
    // against the original preference order.
    final backend = FakeBackend()
      ..attemptScripts.add(const AttemptScript(dataSpaceApplyFailed: true));
    final session = makeSession(
      backend: backend,
      capabilities: caps(),
      policy: const HdrRoutingPolicy(
        preferences: {
          HdrSourceClass.dvP84: [
            HdrStrategy.baseLayerDirect,
            HdrStrategy.baseLayerConvert,
            HdrStrategy.metadataReshape,
            HdrStrategy.toneMapSdr,
          ],
        },
      ),
    );
    await session.open(media, hint: p84);
    expect(backend.preparedPlans, hasLength(2));
    expect(backend.preparedPlans.first.route.strategy,
        HdrStrategy.metadataReshape);
    expect(backend.preparedPlans.first.prediction.selected.stage,
        HdrRouteStage.c2);
    expect(
        backend.preparedPlans.last.route.strategy, HdrStrategy.baseLayerDirect);
    expect(
        backend.preparedPlans.last.prediction.selected.stage, HdrRouteStage.c3);
    expect(backend.opened, hasLength(1));
    expect(session.report.value.verified, isTrue);
    expect(session.report.value.degradeReason,
        HdrDegradeReason.dataSpaceApplyFailed);
    expect(session.report.value.actual!.strategy, HdrStrategy.baseLayerDirect);
    await session.dispose();
  });

  test('a C2 mapper-only failure keeps independent C4 HLG-to-PQ', () async {
    // A PQ-only panel cannot take the P8.4 HLG base directly. C2 reshape
    // is first, followed by C3 (unavailable) and the C4 HLG-to-PQ route.
    // This is a synthetic typed failure, not proof of native mapping.
    final backend = FakeBackend()
      ..attemptScripts.add(const AttemptScript(
        configureError: HdrExecutionDependencyFailure(
          HdrRouteDependency.mapperDolbyVision,
          HdrDegradeReason.metadataMappingFailed,
        ),
      ));
    final session = makeSession(
      backend: backend,
      capabilities: caps(types: const {2}),
    );
    final events = <HdrOutputEvent>[];
    session.events.listen(events.add);
    await session.open(media, hint: p84);
    await pumpEventQueue();

    expect(backend.preparedPlans, hasLength(2));
    expect(
        backend.preparedPlans[0].route.strategy, HdrStrategy.metadataReshape);
    expect(
        backend.preparedPlans[0].prediction.selected.stage, HdrRouteStage.c2);
    expect(
        backend.preparedPlans[1].route.strategy, HdrStrategy.baseLayerConvert);
    expect(
        backend.preparedPlans[1].prediction.selected.stage, HdrRouteStage.c4);
    expect(backend.opened, hasLength(1));
    expect(backend.opened.single.route.outputTransfer, HdrOutputTransfer.pq);

    final excluded = backend.preparedPlans[1].excluded;
    expect(excluded[HdrRouteDependency.mapperDolbyVision],
        HdrDegradeReason.metadataMappingFailed);
    expect(excluded, isNot(contains(HdrRouteDependency.dataspacePq)));
    expect(excluded, isNot(contains(HdrRouteDependency.topologyPlatformView)));
    expect(
        backend.preparedPlans[1].prediction.candidates
            .firstWhere((c) => c.stage == HdrRouteStage.c2)
            .skipReason,
        HdrDegradeReason.metadataMappingFailed);
    expect(session.report.value.degradeReason,
        HdrDegradeReason.metadataMappingFailed);
    expect(session.report.value.actual!.strategy, HdrStrategy.baseLayerConvert);
    expect(events.whereType<HdrErrorEvent>(), isEmpty);
    expect(events.whereType<HdrDegradedEvent>().single.to!.strategy,
        HdrStrategy.baseLayerConvert);
    await session.dispose();
  });

  test(
      'dataspace failure degrades to the next HDR candidate; a following '
      'bind timeout blocks instead of an SDR fallback', () async {
    // C2 reshape(PQ) fails its dataspace application. The retry re-plans the
    // complete stage-ordered catalog — the dataspace-excluded C4 entry stays
    // listed instead of being sliced away — and the independent C3 HLG
    // direct candidate is tried next. Its output bind times out; the timeout
    // is attributed to the platform-view topology every remaining HDR
    // candidate shares, so HDR exhausted means blocked — playback stops with
    // the typed timeout instead of a silent SDR downgrade.
    final backend = FakeBackend()
      ..attemptScripts.addAll(const [
        AttemptScript(dataSpaceApplyFailed: true),
        AttemptScript(bindTimeout: true),
      ]);
    // No preference override: the default catalog evaluates C1-C4 in stage
    // order, so the dataspace-dependent C2 reshape is the first attempt.
    final session = makeSession(backend: backend, capabilities: caps());
    final events = <HdrOutputEvent>[];
    session.events.listen(events.add);

    await expectLater(
        session.open(media, hint: p84), throwsA(isA<HdrOutputBindTimeout>()));
    await pumpEventQueue();

    // Neither HDR attempt reached the media open: the reshape attempt failed
    // at its dataspace (before the media opens) and the direct attempt at
    // the output bind.
    expect(backend.opened, isEmpty);
    expect(backend.calls,
        contains('configure:metadataReshape:pq')); // First HDR attempt (C2).
    expect(backend.calls,
        contains('configure:baseLayerDirect:-')); // Next candidate (C3).
    final degraded = events.whereType<HdrDegradedEvent>().toList();
    expect(degraded, hasLength(1));
    expect(degraded[0].reason, HdrDegradeReason.dataSpaceApplyFailed);
    expect(degraded[0].to!.strategy, HdrStrategy.baseLayerDirect);
    final errors = events.whereType<HdrErrorEvent>().toList();
    expect(errors, hasLength(1));
    expect(errors.single.error, isA<HdrOutputBindTimeout>());
    // The retried plan excluded the failed dataspace dependency and still
    // carries the complete catalog: C4 remains listed with the carried
    // reason rather than being truncated at the failed strategy index.
    expect(backend.preparedPlans.last.excluded[HdrRouteDependency.dataspacePq],
        HdrDegradeReason.dataSpaceApplyFailed);
    final retried = backend.preparedPlans.last.prediction;
    expect(
        retried.candidates.map((candidate) => candidate.strategy),
        containsAll(
            [HdrStrategy.baseLayerDirect, HdrStrategy.baseLayerConvert]));
    expect(
        retried.candidates
            .firstWhere((c) => c.strategy == HdrStrategy.baseLayerConvert)
            .skipReason,
        HdrDegradeReason.dataSpaceApplyFailed);
    final report = session.report.value;
    expect(report.verified, isFalse);
    expect(report.actual, isNull);
    expect(events.whereType<HdrRouteAppliedEvent>(), isEmpty);
    expect(backend.calls.skip(backend.calls.length - 2), ['stop', 'reset']);
    await session.dispose();
  });

  test(
      'a C2 dataspace failure continues down the catalog to a verified C3 '
      'baseline', () async {
    // The full-catalog retry: after the C2 reshape loses its PQ dataspace,
    // the next stage-ordered candidate (C3 HLG direct, an independent
    // dataspace dependency) opens and passes review — the failure does not
    // strand the session on the first candidate nor fall through to SDR.
    final backend = FakeBackend()
      ..attemptScripts.add(const AttemptScript(dataSpaceApplyFailed: true));
    final session = makeSession(backend: backend, capabilities: caps());
    final events = <HdrOutputEvent>[];
    session.events.listen(events.add);

    await session.open(media, hint: p84);
    await pumpEventQueue();

    expect(backend.opened, hasLength(1));
    expect(backend.opened.single.route.strategy, HdrStrategy.baseLayerDirect);
    final degraded = events.whereType<HdrDegradedEvent>().single;
    expect(degraded.reason, HdrDegradeReason.dataSpaceApplyFailed);
    expect(degraded.from!.strategy, HdrStrategy.metadataReshape);
    expect(degraded.to!.strategy, HdrStrategy.baseLayerDirect);
    expect(events.whereType<HdrErrorEvent>(), isEmpty);
    final report = session.report.value;
    expect(report.verified, isTrue);
    expect(report.actual!.strategy, HdrStrategy.baseLayerDirect);
    expect(report.degradeReason, HdrDegradeReason.dataSpaceApplyFailed);
    expect(backend.preparedPlans.last.excluded[HdrRouteDependency.dataspacePq],
        HdrDegradeReason.dataSpaceApplyFailed);
    expect(events.whereType<HdrRouteAppliedEvent>(), hasLength(1));
    await session.dispose();
  });

  test(
      'a HDR Vivid side-data fact reclassifies an HDR10 hint and the '
      'applicable HDR baseline keeps playback with dynamic errors preserved',
      () async {
    final backend = FakeBackend()
      ..factsForOpen
          .add(facts(gamma: 'pq', primaries: 'bt.2020', hdrVivid: true));
    final session = makeSession(backend: backend, capabilities: caps());
    final events = <HdrOutputEvent>[];
    session.events.listen(events.add);

    await session.open(media, hint: hdr10);
    await pumpEventQueue();

    // Reclassification to the hdrVivid class plans C1 native Vivid and C2
    // metadata mapping as explicit routeNotImplemented errors — there is no
    // "gated off" state — while the C3 PQ baseline stays applicable. The
    // Although the same base-layer executor is selected, its metadata
    // ownership changes from none (HDR10) to baselineOnly (Vivid). Rebuild
    // the execution under the new source-fact contract rather than adopting
    // an open configured before the dynamic metadata was observed.
    // Unimplemented C1/C2 remain typed errors after baseline fallback.
    expect(backend.opened, hasLength(2));
    expect(backend.opened.first.route.strategy, HdrStrategy.baseLayerDirect);
    expect(
        backend.opened.first.route.metadataHandling, HdrMetadataHandling.none);
    expect(backend.opened.last.route.strategy, HdrStrategy.baseLayerDirect);
    expect(backend.opened.last.route.metadataHandling,
        HdrMetadataHandling.baselineOnly);
    final report = session.report.value;
    expect(report.verified, isTrue);
    expect(report.source!.dynamicMetadata, HdrDynamicMetadata.hdrVivid);
    expect(report.sourceOrigin, HdrReportSource.decoder);
    expect(report.actual!.strategy, HdrStrategy.baseLayerDirect);
    expect(report.degradeReason, isNull);
    final reclassified = events.whereType<HdrReclassifiedEvent>().toList();
    expect(reclassified, hasLength(1));
    expect(reclassified.single.rebuilt, isTrue);
    final candidates = report.prediction!.candidates;
    expect(candidates[0].strategy, HdrStrategy.nativeHdrVivid);
    expect(candidates[0].skipReason, HdrDegradeReason.routeNotImplemented);
    expect(candidates[0].status, HdrCandidateStatus.error);
    expect(candidates[1].strategy, HdrStrategy.metadataReshape);
    expect(candidates[1].skipReason, HdrDegradeReason.routeNotImplemented);
    expect(candidates[1].status, HdrCandidateStatus.error);
    expect(report.prediction!.selected.strategy, HdrStrategy.baseLayerDirect);
    expect(events.whereType<HdrErrorEvent>(), isEmpty);
    expect(events.whereType<HdrDegradedEvent>(), isEmpty);
    expect(events.whereType<HdrRouteAppliedEvent>(), hasLength(1));
    expect(backend.calls, contains('stop'));
    expect(backend.calls, contains('reset'));
    await session.dispose();
  });

  test(
      'HDR10+ affirmative frame fact rebuilds static PQ baseline without '
      'claiming dynamic rendering', () async {
    // Native mpv exposes metadata presence independently from the mapped
    // scene values. Synthetic review facts exercise Session reclassification,
    // not proof of actual native frame-side delivery.
    final backend = FakeBackend()
      ..factsForOpen.add(const HdrReviewFacts(
        codec: 'hevc',
        videoParams: VideoParams(gamma: 'pq', primaries: 'bt.2020'),
        hwdecCurrent: 'mediacodec',
        path: 'test://media',
        hdr10Plus: true,
      ));
    final session = makeSession(backend: backend, capabilities: caps());
    final events = <HdrOutputEvent>[];
    session.events.listen(events.add);
    await session.open(media, hint: hdr10);
    await pumpEventQueue();

    expect(backend.opened, hasLength(2));
    expect(
        backend.opened.first.route.metadataHandling, HdrMetadataHandling.none);
    expect(backend.opened.last.route.metadataHandling,
        HdrMetadataHandling.baselineOnly);
    final report = session.report.value;
    expect(report.verified, isTrue);
    expect(report.source!.dynamicMetadata, HdrDynamicMetadata.hdr10Plus);
    expect(report.sourceFacts!.hdr10PlusOnFrame, isTrue);
    expect(report.requestedMetadataHandling, HdrMetadataHandling.baselineOnly);
    expect(report.metadataHandlingObserved, isNull);
    expect(report.prediction!.selected.strategy, HdrStrategy.baseLayerDirect);
    expect(report.prediction!.selected.stage, HdrRouteStage.c3);
    expect(
        report.prediction!.candidates[0].strategy, HdrStrategy.nativeHdr10Plus);
    expect(report.prediction!.candidates[0].skipReason,
        HdrDegradeReason.routeNotImplemented);
    expect(report.prediction!.candidates[1].skipReason,
        HdrDegradeReason.routeNotImplemented);
    expect(events.whereType<HdrReclassifiedEvent>().single.rebuilt, isTrue);
    expect(events.whereType<HdrErrorEvent>(), isEmpty);
    await session.dispose();
  });

  test(
      'hwdec mismatch on an HDR-capable display blocks without an SDR '
      'software fallback', () async {
    // Every HDR candidate for hdr10 needs the failed mediacodec carrier;
    // the independent copy/software requests only serve SDR output, which
    // an HDR-capable display does not authorize. HDR exhausted = blocked.
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
    expect(backend.opened.map((o) => o.route.hwdec), ['mediacodec']);
    expect(backend.opened.single.route.strategy, HdrStrategy.baseLayerDirect);
    expect(session.report.value.verified, isFalse);
    expect(session.report.value.degradeReason, HdrDegradeReason.hwdecMismatch);
    expect(events.whereType<HdrRouteAppliedEvent>(), isEmpty);
    final errors = events.whereType<HdrErrorEvent>().toList();
    expect(errors, hasLength(1));
    expect(errors.single.reason, HdrDegradeReason.hwdecMismatch);
    expect(backend.calls, contains('stop'));
    expect(backend.calls, contains('reset'));
    await session.dispose();
  });

  test(
      'ordinary to native internal reopen clears predecessor decoder observation',
      () async {
    // Synthetic native endpoints exercise the real Session consumer and report
    // boundary. They do not claim any device codec or display acceptance.
    const nativeRaw = '{"api":1,"mime":"video/dolby-vision",'
        '"codec":"c2.native.dv","native-dv-active":true}';
    final playerIdentity = Object(), controllerIdentity = Object();
    final sourceIdentity = HdrOptionSourceIdentity(
      player: playerIdentity,
      path: media.uri,
      playlistEntryId: '7',
      fileLoadedEpoch: 4,
    );
    final output = HdrNativeDvOutputSnapshot(
        controllerIdentity,
        const AndroidSurfaceAccountId(
            handle: 11,
            generation: 2,
            viewId: 3,
            surfaceGeneration: 4,
            wid: 5));
    final backend = FakeBackend()
      ..factsForOpen.addAll([
        HdrReviewFacts(
            codec: 'hevc',
            hwdecCurrent: 'mediacodec',
            path: media.uri,
            dolbyVisionProfile: 5,
            dvCompatibilityId: 0,
            dvElPresent: false,
            decoderObservation: const HdrDecoderObservation(
                playlistEntryId: 1,
                fileLoadedEpoch: 1,
                decoder: 'hevc_mediacodec',
                decoderDescription: '',
                hwdec: 'mediacodec',
                pixelFormat: 'mediacodec',
                hwPixelFormat: 'nv12')),
        HdrReviewFacts(
            codec: 'hevc',
            hwdecCurrent: 'mediacodec',
            path: media.uri,
            dolbyVisionProfile: 5,
            dvCompatibilityId: 0,
            dvElPresent: false,
            nativeDvEvidence: HdrNativeDvReviewEvidence(
                source: sourceIdentity,
                loaded: const FileLoadedRecord(4, 7),
                controller: output.controller,
                output: output.identity,
                configuration: AndroidMediaCodecConfiguration.parse(nativeRaw)!,
                hwdecCurrent: 'mediacodec')),
      ]);
    final session = HdrVideoSession.forTesting(
      backend: backend,
      isAndroid: true,
      capabilitiesProvider: () async => caps(),
      nativePlayerIdentity: playerIdentity,
      nativePlayerLock: Lock(),
      readNativeIdentity: () async => sourceIdentity,
      readNativeProperty: (name) async =>
          name == 'android-mediacodec-info' ? nativeRaw : 'mediacodec',
      readNativeOutput: () => output,
      reviewMonotonicNow: () => Duration.zero,
      routePlanner: (
          {required source,
          required capabilities,
          required policy,
          required preference,
          required excluded}) {
        final ordinary = HdrRoutePlanner.plan(
            source: source,
            capabilities: capabilities,
            policy: policy,
            preference: preference,
            excluded: excluded);
        if (HdrSourceClass.of(source) != HdrSourceClass.dvP5) return ordinary;
        const nativeRoute = HdrRoute(
            strategy: HdrStrategy.nativeDolbyVision,
            presentation: HdrPresentation.nativeDolbyVision,
            outputTransfer: HdrOutputTransfer.dolbyVision,
            appliesDynamicMetadata: true,
            topology: HdrTopology.platformView,
            vo: 'mediacodec_embed',
            hwdec: 'mediacodec',
            targetPrim: null,
            targetTrc: null,
            surfaceTransfer: null,
            stripDvRpu: false);
        // Native DV is the dvP5 catalog's C1 candidate; the injected entry
        // must carry that routing identity so the canonical stage sort keeps
        // it ahead of the C2 reshape instead of demoting the unstaged entry.
        final candidate = const HdrCandidate(
                strategy: HdrStrategy.nativeDolbyVision,
                maturity: HdrStrategyMaturity.unsupported,
                route: nativeRoute,
                feasible: true)
            .withRoutingIdentity(HdrSourceClass.dvP5, HdrRouteStage.c1);
        return HdrRoutePrediction(
            source: source,
            selected: candidate,
            candidates: [candidate, ...ordinary.candidates],
            presentation: nativeRoute.presentation,
            confidence: HdrPredictionConfidence.unverified,
            playable: true);
      },
    );
    await session.open(media);
    expect(backend.opened.map((plan) => plan.route.strategy),
        [HdrStrategy.sdrDirect, HdrStrategy.nativeDolbyVision]);
    expect(session.report.value.verified, isTrue);
    expect(
        session.report.value.actual!.strategy, HdrStrategy.nativeDolbyVision);
    expect(session.report.value.decoderObservation, isNull);
    expect(session.report.value.decoderIdentityKnown, isFalse);
    await session.dispose();
  });

  test(
      'ordinary unnamed decoder keeps route and identity verification separate',
      () async {
    final backend = FakeBackend()
      ..factsForOpen.add(HdrReviewFacts(
        codec: 'hevc',
        hwdecCurrent: 'mediacodec',
        path: media.uri,
        videoParams: const VideoParams(gamma: 'pq', primaries: 'bt.2020'),
        decoderObservation: const HdrDecoderObservation(
          playlistEntryId: 1,
          fileLoadedEpoch: 1,
          decoder: '',
          decoderDescription: '',
          hwdec: 'mediacodec',
          pixelFormat: 'mediacodec',
          hwPixelFormat: 'nv12',
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

  test('ordinary observation blocks wrong MIME despite matching hwdec',
      () async {
    final backend = FakeBackend()
      ..factsForOpen.add(HdrReviewFacts(
        codec: 'hevc',
        hwdecCurrent: 'mediacodec',
        path: media.uri,
        videoParams: const VideoParams(gamma: 'pq', primaries: 'bt.2020'),
        decoderObservation: HdrDecoderObservation(
          playlistEntryId: 1,
          fileLoadedEpoch: 1,
          decoder: 'h264_mediacodec',
          decoderDescription: '',
          hwdec: 'mediacodec',
          pixelFormat: 'mediacodec',
          hwPixelFormat: 'nv12',
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
    expect(session.report.value.degradeReason,
        HdrDegradeReason.routeReviewMismatch);
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

    // The subject is the copy-carrier review contract: the explicit sdrEmbed
    // opt-out keeps the directory copy → software (the unset option now
    // plans the embed execution first on SDK 16–25).
    await session.open(media, hint: sdr,
        options: EffectiveVideoRouteOptions.resolve(
            application: const VideoRouteOptions(sdrEmbed: false)));
    await pumpEventQueue();

    expect(backend.opened, hasLength(1));
    expect(backend.opened.single.route.hwdec, 'mediacodec-copy');
    expect(session.report.value.hwdecCurrent, 'mediacodec-copy');
    expect(session.report.value.degradeReason, isNull);
    expect(events.whereType<HdrDegradedEvent>(), isEmpty);
    await session.dispose();
  });

  test('API 24 copy mismatch reaches software without repeating failed copy',
      () async {
    final backend = FakeBackend()
      ..factsForOpen.add(const HdrReviewFacts(
        hwdecCurrent: 'no',
        path: 'test://media',
      ));
    final session = makeSession(
      backend: backend,
      capabilities: caps(sdkInt: 24),
      position: const Duration(seconds: 3),
    );
    final events = <HdrOutputEvent>[];
    session.events.listen(events.add);
    // Same explicit opt-out as above: this verifies the copy review flow.
    await session.open(media, hint: sdr,
        options: EffectiveVideoRouteOptions.resolve(
            application: const VideoRouteOptions(sdrEmbed: false)));
    await pumpEventQueue();
    expect(backend.opened.map((o) => o.route.hwdec), ['mediacodec-copy', 'no']);
    expect(session.report.value.verified, isTrue);
    expect(session.report.value.actual!.hwdec, 'no');
    expect(events.whereType<HdrRouteAppliedEvent>(), hasLength(1));
    expect(events.whereType<HdrErrorEvent>(), isEmpty);
    expect(backend.calls, contains('stop'));
    expect(backend.calls, contains('reset'));
    await session.dispose();
  });

  test('SurfaceTexture mismatch blocks without an SDR takeover', () async {
    final backend = FakeBackend()
      ..factsForOpen.addAll([
        facts(gamma: 'hlg', profile: 8, hwdec: 'mediacodec'),
        facts(gamma: 'hlg', profile: 8, hwdec: 'no'),
      ]);
    final session = makeSession(
      backend: backend,
      capabilities: lgYuvPqCaps(),
      policy: HdrRoutingPolicy(
        preferences: const {
          HdrSourceClass.dvP84: [
            HdrStrategy.baseLayerConvert,
            HdrStrategy.toneMapSdr,
          ],
        },
      ),
      position: const Duration(seconds: 2),
    );
    final events = <HdrOutputEvent>[];
    session.events.listen(events.add);

    await session.open(media, hint: p84);
    await pumpEventQueue();

    // The mismatched surfacetexture carrier is excluded at the review, but
    // the remaining tone-map candidate is SDR output and the display
    // reports HDR10: no implicit SDR takeover, the open blocks instead.
    expect(backend.opened.map((o) => o.route.hwdec), ['surfacetexture']);
    expect(backend.opened.single.route.strategy, HdrStrategy.baseLayerConvert);
    expect(session.report.value.verified, isFalse);
    expect(session.report.value.degradeReason, HdrDegradeReason.hwdecMismatch);
    expect(events.whereType<HdrRouteAppliedEvent>(), isEmpty);
    final errors = events.whereType<HdrErrorEvent>().toList();
    expect(errors, hasLength(1));
    expect(errors.single.reason, HdrDegradeReason.hwdecMismatch);
    expect(backend.calls, contains('reset'));
    await session.dispose();
  });

  test(
      'SurfaceTexture mismatch cannot recover through the SDR copy route on '
      'an HDR-capable display', () async {
    final backend = FakeBackend()
      ..factsForOpen.addAll([
        facts(gamma: 'hlg', profile: 8, hwdec: 'mediacodec'),
        facts(gamma: 'hlg', profile: 8, hwdec: 'mediacodec-copy'),
      ]);
    final session = makeSession(
      backend: backend,
      capabilities: lgYuvPqCaps(),
      policy: HdrRoutingPolicy(
        preferences: const {
          HdrSourceClass.dvP84: [
            HdrStrategy.baseLayerConvert,
            HdrStrategy.toneMapSdr,
          ],
        },
      ),
      position: const Duration(seconds: 2),
    );
    final events = <HdrOutputEvent>[];
    session.events.listen(events.add);

    await session.open(media, hint: p84);
    await pumpEventQueue();

    // The mediacodec-copy carrier is independent of the failed
    // surfacetexture decoder, but it only carries the tone-map route —
    // SDR output that an HDR10-capable display does not authorize. The
    // copy route is therefore never prepared and the open blocks.
    expect(backend.opened.map((o) => o.route.hwdec), ['surfacetexture']);
    expect(backend.calls, isNot(contains('configure:toneMapSdr:-')));
    expect(session.report.value.verified, isFalse);
    expect(session.report.value.hwdecCurrent, isNull);
    expect(session.report.value.actual, isNull);
    expect(events.whereType<HdrRouteAppliedEvent>(), isEmpty);
    final errors = events.whereType<HdrErrorEvent>().toList();
    expect(errors, hasLength(1));
    expect(errors.single.reason, HdrDegradeReason.hwdecMismatch);
    await session.dispose();
  });

  test(
      'an unavailable native DV admission blocks a P5 hint and never opens '
      'the media', () async {
    // Native DV is the first (verified) dvP5 candidate since the 2026-10-10
    // promotion; without the bridge/decoder admission it fails before the
    // P5 rescale-pipeline dependency is ever consulted. The gated reshape/
    // tone-map rows are not an implicit fallback.
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
    expect(report.degradeReason, HdrDegradeReason.nativeDvUnavailable);
    final errors = events.whereType<HdrErrorEvent>().toList();
    expect(errors, hasLength(1));
    expect(errors.single.reason, HdrDegradeReason.nativeDvUnavailable);
    expect(events.whereType<HdrRouteAppliedEvent>(), isEmpty);
    await session.dispose();
  });

  test(
      'a newer open supersedes the old one: no stale report, backend '
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
    // Only the P8.4 open reached the backend, and it enters at the canonical
    // C2 stage: with the P5 pipeline available the metadata reshape to PQ is
    // the legal HDR output (P8.2 invariant). Native DV has no admission here
    // and the C3 baseline follows only behind the reshape.
    expect(backend.opened.single.route.strategy, HdrStrategy.metadataReshape);
    expect(backend.opened.single.route.outputTransfer,
        HdrOutputTransfer.pq); // The C2 reshape output, not an SDR downgrade.
    // The aborted transaction rolled back before the newer one ran.
    final firstConfigure = backend.calls
        .indexWhere((call) => call.startsWith('configure:baseLayerDirect:-'));
    expect(backend.calls[firstConfigure + 1], 'stop');
    expect(backend.calls[firstConfigure + 2], 'reset');
    final report = session.report.value;
    expect(report.generation, 2);
    expect(report.verified, isTrue);
    expect(report.actual!.strategy, HdrStrategy.metadataReshape);
    expect(report.actual!.outputTransfer, HdrOutputTransfer.pq);
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

  test('playback configuration changes review even an unchanged route',
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

    // The same route still receives a fresh configure/open/review for new settings.
    await session.setPolicy(const HdrRoutingPolicy(preferences: {
      HdrSourceClass.hdr10: [HdrStrategy.toneMapSdr],
    }));
    await pumpEventQueue();
    expect(backend.opened, hasLength(3));
    expect(backend.opened.last.route, backend.opened[1].route);
    expect(backend.opened.last.options, same(session.report.value.options));
    expect(
        backend.calls.where((c) => c.startsWith('configure:')), hasLength(3));
    expect(backend.calls.where((c) => c.startsWith('review:')), hasLength(3));
    expect(
      events.whereType<HdrRouteAppliedEvent>(),
      hasLength(3),
    );
    await session.dispose();
  });

  test(
      'capability loss degrades to tone-map; capability recovery rebuilds '
      'the HDR route', () async {
    final backend = FakeBackend()
      ..factsForOpen.add(facts(gamma: 'pq', primaries: 'bt.2020'))
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

    // Recovery: the confirmed HDR display invalidates the resting SDR-output
    // route (no implicit SDR resting state for an HDR source), so the same
    // capabilityLost path rebuilds onto the HDR route.
    final degradesBefore = events.whereType<HdrDegradedEvent>().length;
    await session.handleCapabilitiesChanged(caps());
    await pumpEventQueue();
    expect(backend.opened, hasLength(3));
    expect(backend.opened.last.route.strategy, HdrStrategy.baseLayerDirect);
    expect(backend.opened.last.start, const Duration(seconds: 6));
    final degrades = events.whereType<HdrDegradedEvent>().toList();
    expect(degrades, hasLength(degradesBefore + 1));
    expect(degrades.last.reason, HdrDegradeReason.capabilityLost);
    expect(degrades.last.from!.strategy, HdrStrategy.toneMapSdr);
    expect(degrades.last.to!.strategy, HdrStrategy.baseLayerDirect);
    expect(session.report.value.actual!.strategy, HdrStrategy.baseLayerDirect);
    expect(events.whereType<HdrRouteAppliedEvent>().last.route.strategy,
        HdrStrategy.baseLayerDirect);
    await session.dispose();
  });

  group('YUV window presentation arms (plan C)', () {
    const hlgSource = HdrSourceDescriptor(
      codec: 'hevc',
      transfer: 'hlg',
      primaries: 'bt.2020',
      enhancementLayer: false,
    );

    HdrReviewFacts yuvFacts() => HdrReviewFacts(
          videoParams: const VideoParams(gamma: 'hlg', primaries: 'bt.2020'),
          dolbyVisionProfile: 8,
          dvCompatibilityId: 4,
          codec: 'hevc',
          hwdecCurrent: 'surfacetexture',
          path: media.uri,
        );

    HdrYuvWindowArm sessionArm(_SessionArmAtoms atoms,
            {String? ownerToken = 'owner-token'}) =>
        HdrYuvWindowArm(
          ownerToken: ownerToken,
          ownerGeneration: () async => 4,
          bindingsResolver: () => atoms.bindings(),
          channel: atoms.channel,
        );

    test('zero arms for texture routes on a YUV-window device', () async {
      final atoms = _SessionArmAtoms();
      final backend = FakeBackend();
      final session = makeSession(
        backend: backend,
        capabilities: lgYuvPqCaps(),
        yuvWindowArm: sessionArm(atoms),
      );
      final events = <HdrOutputEvent>[];
      session.events.listen(events.add);

      // SDR source on the YUV-window device: the SDR-direct texture route,
      // not the YUV carrier — bit-identical to the arm-free behavior.
      await session.open(media, hint: sdr);
      await pumpEventQueue();

      expect(session.report.value.verified, isTrue);
      expect(session.report.value.actual!.hwdec, isNot('surfacetexture'));
      expect(atoms.calls, isEmpty);
      // Round 3: the non-YUV route takes a READ admission (Begin/End), but
      // performs no arm channel call and touches no atom.
      expect(
          atoms.channelCalls.where((m) => m.contains('YuvDiag')), isEmpty);
      expect(events.whereType<HdrErrorEvent>(), isEmpty);
      await session.dispose();
      expect(atoms.diagDataSpace, 0);
      expect(atoms.yuvDiagEnabled, 0);
    });

    test('zero arms for the mediacodec-embed direct route', () async {
      final atoms = _SessionArmAtoms();
      final backend = FakeBackend()..factsForOpen.add(gammaFacts(gamma: 'pq'));
      final session = makeSession(
        backend: backend,
        capabilities: caps(),
        yuvWindowArm: sessionArm(atoms),
      );
      await session.open(media, hint: hdr10);
      await pumpEventQueue();
      expect(session.report.value.verified, isTrue);
      expect(session.report.value.actual!.vo, 'mediacodec_embed');
      expect(atoms.calls, isEmpty);
      // Round 3: the non-YUV route takes a READ admission (Begin/End), but
      // performs no arm channel call and touches no atom.
      expect(
          atoms.channelCalls.where((m) => m.contains('YuvDiag')), isEmpty);
      await session.dispose();
    });

    test('a YUV review reopen retires its replaced attempt and retains live',
        () async {
      final atoms = _SessionArmAtoms();
      final backend = FakeBackend()
        ..factsForOpen.add(yuvFacts())
        ..factsForOpen.add(yuvFacts());
      final session = makeSession(
        backend: backend,
        capabilities: lgYuvPqCaps(),
        policy: HdrRoutingPolicy(
          preferences: const {
            HdrSourceClass.hlg: [HdrStrategy.baseLayerConvert],
            HdrSourceClass.dvP84: [HdrStrategy.baseLayerConvert],
          },
        ),
        yuvWindowArm: sessionArm(atoms),
      );
      final events = <HdrOutputEvent>[];
      session.events.listen(events.add);

      // The HLG hint plans C4 on the surfacetexture carrier; the decoder
      // review reclassifies the source to dvP84 (RPU stripping changes the
      // route) and reopens in place — still on the YUV-carrier convert
      // route: two execution attempts. The replaced attempt is disarmed;
      // the accepted live attempt retains its ownership until disposal.
      await session.open(media, hint: hlgSource);
      await pumpEventQueue();

      expect(backend.opened, hasLength(2));
      expect(backend.opened.map((o) => o.route.stripDvRpu), [false, true],
          reason: 'the review reopen is a distinct execution attempt');
      expect(backend.opened.every((o) => o.route.hwdec == 'surfacetexture'),
          isTrue);
      expect(session.report.value.verified, isTrue);
      expect(atoms.armCount, 2,
          reason: 'each execution attempt arms exactly once');
      expect(atoms.disarmCount, 1,
          reason: 'only the replaced attempt is disarmed immediately');
      expect(atoms.diagDataSpace, 0x11C60000);
      expect(atoms.yuvDiagEnabled, 1);
      await session.dispose();
      expect(atoms.diagDataSpace, 0);
      expect(atoms.yuvDiagEnabled, 0);
    });

    test('a YUV attempt stays armed until the same session reopens or disposes',
        () async {
      final atoms = _SessionArmAtoms();
      final backend = FakeBackend()
        ..factsForOpen.add(gammaFacts(gamma: 'hlg', hwdec: 'surfacetexture'));
      final session = makeSession(
        backend: backend,
        capabilities: lgYuvPqCaps(),
        policy: HdrRoutingPolicy(
          preferences: const {
            HdrSourceClass.hlg: [HdrStrategy.baseLayerConvert],
          },
        ),
        yuvWindowArm: sessionArm(atoms),
      );
      await session.open(media, hint: hlgSource);
      await pumpEventQueue();
      expect(session.report.value.verified, isTrue);
      expect(atoms.armCount, 1);
      // The ACCEPTED YUV window and its process ownership stay live past the
      // open; the disarm belongs to same-owner replacement and disposal.
      expect(atoms.disarmCount, 0);
      expect(atoms.diagDataSpace, 0x11C60000);
      expect(atoms.yuvDiagEnabled, 1);

      // A same-owner SDR open retires the retained YUV window before reading
      // the successor output's facts.
      backend.factsForOpen
          .add(gammaFacts(gamma: 'bt.1886', hwdec: 'mediacodec-copy'));
      await session.open(media, hint: sdr);
      await pumpEventQueue();
      expect(session.report.value.verified, isTrue);
      expect(atoms.armCount, 1);
      expect(atoms.diagDataSpace, 0);
      expect(atoms.yuvDiagEnabled, 0);
      await session.dispose();
    });

    test('a superseded accepted review disarms instead of retaining its lease',
        () async {
      final atoms = _SessionArmAtoms();
      final backend = FakeBackend()..factsForOpen.add(yuvFacts());
      final successorCapabilities = Completer<HdrCapabilities>();
      var capabilityCalls = 0;
      var successorStarted = false;
      late Future<void> successorOpen;
      late HdrVideoSession session;
      session = makeSession(
        backend: backend,
        capabilities: lgYuvPqCaps(),
        capabilitiesProvider: () {
          capabilityCalls++;
          return capabilityCalls == 1
              ? Future<HdrCapabilities>.value(lgYuvPqCaps())
              : successorCapabilities.future;
        },
        policy: HdrRoutingPolicy(
          preferences: const {
            HdrSourceClass.hlg: [HdrStrategy.baseLayerConvert],
          },
        ),
        yuvWindowArm: sessionArm(atoms),
        onBackendCallDiagnostic: (diagnostic) {
          if (diagnostic.method != HdrBackendDiagnosticMethod.reviewFacts ||
              diagnostic.boundary != HdrBackendDiagnosticBoundary.returned ||
              successorStarted) {
            return;
          }
          successorStarted = true;
          scheduleMicrotask(() {
            // The successor is held before preparation so the old attempt's
            // terminal cleanup is the only operation that can release A.
            backend.prepareErrorOnce = StateError('successor prepare failed');
            successorOpen = session.open(
                Media('test://superseding-request'),
                hint: hlgSource);
          });
        },
      );

      try {
        await session.open(media, hint: hlgSource);
      } catch (_) {
        // The diagnostic-triggered request supersedes the old generation.
      }
      await pumpUntil(() => successorStarted && capabilityCalls >= 2);
      expect(atoms.diagDataSpace, 0,
          reason: 'stale accepted review cleanup must disarm its atoms');
      expect(atoms.yuvDiagEnabled, 0);
      expect(atoms.gate.writer, isFalse,
          reason: 'stale accepted review cleanup must release its writer');

      successorCapabilities.complete(lgYuvPqCaps());
      await expectLater(successorOpen, throwsStateError);
      expect(atoms.diagDataSpace, 0);
      expect(atoms.yuvDiagEnabled, 0);
      expect(atoms.gate.writer, isFalse);
      await session.dispose();
    });

    test(
        'a same-generation review reopen YUV→non-YUV ends the YUV arm before '
        'the successor attempt', () async {
      final atoms = _SessionArmAtoms();
      final backend = FakeBackend()
        ..factsForOpen
            .add(gammaFacts(gamma: 'bt.1886', hwdec: 'mediacodec-copy'))
        ..factsForOpen
            .add(gammaFacts(gamma: 'bt.1886', hwdec: 'mediacodec-copy'));
      atoms.sink = backend.calls;
      final session = makeSession(
        backend: backend,
        capabilities: lgYuvPqCaps(),
        policy: HdrRoutingPolicy(
          preferences: const {
            HdrSourceClass.hlg: [HdrStrategy.baseLayerConvert],
          },
        ),
        yuvWindowArm: sessionArm(atoms),
      );
      // The subject is the same-generation reopen arm protocol: the explicit
      // sdrEmbed opt-out keeps the reclassified SDR reopen on the texture
      // copy carrier (the unset option now plans the embed execution first
      // at SDK 24).
      await session.open(media, hint: hlgSource,
          options: EffectiveVideoRouteOptions.resolve(
              application: const VideoRouteOptions(sdrEmbed: false)));
      await pumpEventQueue();

      // The decoder review reclassifies the hinted HLG source as SDR and
      // reopens within the SAME generation onto the non-YUV SDR-direct
      // route: exactly one arm, ended before the successor attempt prepared,
      // and both atoms zero at the end.
      expect(backend.opened, hasLength(2));
      expect(backend.opened.first.route.hwdec, 'surfacetexture');
      expect(backend.opened.last.route.hwdec, isNot('surfacetexture'));
      expect(session.report.value.verified, isTrue);
      expect(atoms.armCount, 1);
      expect(atoms.disarmCount, 1);
      final disarmAt = backend.calls.indexWhere((c) => c.startsWith('disarm:'));
      final secondPrepareAt = backend.calls
          .indexWhere((c) => c.startsWith('prepare:'), backend.calls.indexWhere((c) => c.startsWith('prepare:')) + 1);
      expect(disarmAt, greaterThan(backend.calls.indexWhere((c) => c.startsWith('review:'))),
          reason: 'the terminal disarm follows the review that ended the attempt');
      expect(disarmAt, lessThan(secondPrepareAt),
          reason: 'the successor attempt prepares only over cleared atoms');
      expect(atoms.diagDataSpace, 0);
      expect(atoms.yuvDiagEnabled, 0);
      await session.dispose();
    });

    test(
        'cleanup debt from a YUV attempt blocks a following SDR open until '
        'it clears (B2 barrier)', () async {
      final atoms = _SessionArmAtoms()..disarmFails = true;
      final backend = FakeBackend()..factsForOpen.add(yuvFacts());
      final session = makeSession(
        backend: backend,
        capabilities: lgYuvPqCaps(),
        policy: HdrRoutingPolicy(
          preferences: const {
            HdrSourceClass.hlg: [HdrStrategy.baseLayerConvert],
          },
        ),
        yuvWindowArm: sessionArm(atoms),
      );
      // The YUV attempt opens and reviews cleanly, but its terminal disarm
      // fails: the open fails with the cleanup failure and the debt stays.
      await expectLater(session.open(media, hint: hlgSource),
          throwsA(isA<HdrAttemptCleanupFailure>()));
      await pumpEventQueue();
      expect(atoms.armCount, 1);
      expect(atoms.yuvDiagEnabled, 1,
          reason: 'the armed YUV atom survived the failed disarm (debt)');
      // The diag-dataspace atom clears independently on the failed disarm
      // path (the pair is partially retired); the YUV switch — the one the
      // VO reads — is the residue that must block successors.
      expect(atoms.diagDataSpace, 0);
      final openedAfterFailure = backend.opened.length;

      // A following SDR open is REJECTED at the common barrier: initializing
      // an output over uncleared arms is exactly the poisoned-atoms path.
      backend.factsForOpen
          .add(gammaFacts(gamma: 'bt.1886', hwdec: 'mediacodec-copy'));
      await expectLater(session.open(media, hint: sdr),
          throwsA(isA<HdrYuvWindowArmFailure>().having(
              (error) => error.cause.toString(),
              'cause',
              contains('previous arm cleanup still failing'))));
      await pumpEventQueue();
      expect(backend.opened, hasLength(openedAfterFailure),
          reason: 'no SDR output was initialized behind the debt barrier');

      // Once the disarm path recovers, the barrier clears the debt and the
      // same SDR open proceeds with both atoms zero.
      atoms.disarmFails = false;
      await session.open(media, hint: sdr);
      await pumpEventQueue();
      expect(session.report.value.verified, isTrue);
      expect(atoms.diagDataSpace, 0);
      expect(atoms.yuvDiagEnabled, 0);
      await session.dispose();
    });

    test(
        'a YUV open is rejected while another session\'s SDR initialization '
        'is mid-flight (reverse concurrency, B1 round 3)', () async {
      final atoms = _SessionArmAtoms();
      final sdrBackend = FakeBackend()
        ..factsForOpen
            .add(gammaFacts(gamma: 'bt.1886', hwdec: 'mediacodec-copy'));
      final yuvBackend = FakeBackend()..factsForOpen.add(yuvFacts());
      final sdrSession = makeSession(
        backend: sdrBackend,
        capabilities: lgYuvPqCaps(),
        yuvWindowArm: sessionArm(atoms),
      );
      final yuvSession = makeSession(
        backend: yuvBackend,
        capabilities: lgYuvPqCaps(),
        policy: HdrRoutingPolicy(
          preferences: const {
            HdrSourceClass.hlg: [HdrStrategy.baseLayerConvert],
          },
        ),
        yuvWindowArm: sessionArm(atoms),
      );
      // Suspend the SDR session's output initialization AFTER its read
      // admission passed (the output binding is still in flight).
      sdrBackend.holdInitialize = Completer<void>();
      final sdrOpen = sdrSession.open(media, hint: sdr);
      await pumpUntil(
          () => sdrBackend.calls.any((c) => c.startsWith('prepare:')));
      expect(atoms.gate.readers, 1,
          reason: 'the SDR initialization holds an active read admission');

      // The YUV session's write admission is REJECTED by the process gate
      // (an active reader): no arm happens, no atom is touched, and the
      // SDR initialization is not queued-behind-but-poisoned.
      await expectLater(
          yuvSession.open(media, hint: hlgSource),
          throwsA(isA<HdrYuvWindowLeaseConflict>()
              .having((error) => error.description, 'description',
                  contains('concurrent output initialization'))));
      await pumpEventQueue();
      expect(yuvBackend.opened, isEmpty,
          reason: 'the rejected YUV attempt initialized no output');
      expect(atoms.diagDataSpace, 0,
          reason: 'the rejected YUV attempt armed nothing');
      expect(atoms.yuvDiagEnabled, 0);
      expect(atoms.armCount, 0);

      // The suspended SDR initialization completes cleanly afterwards.
      sdrBackend.holdInitialize!.complete();
      await sdrOpen;
      await pumpEventQueue();
      expect(sdrSession.report.value.verified, isTrue);
      expect(atoms.gate.readers, 0,
          reason: 'the read admission was released at the bind completion');
      expect(atoms.diagDataSpace, 0);
      expect(atoms.yuvDiagEnabled, 0);

      // With the process quiescent again, the same YUV open proceeds (the
      // decoder review's dvP84 reclassification reopens once in place — two
      // armed attempts, matching the single-session behavior).
      await yuvSession.open(media, hint: hlgSource);
      await pumpEventQueue();
      expect(yuvSession.report.value.verified, isTrue);
      expect(atoms.armCount, 2);
      // Only the replaced reopen attempt disarmed; the ACCEPTED attempt's
      // window stays armed while live, retiring at the session dispose.
      expect(atoms.disarmCount, 1);
      expect(atoms.diagDataSpace, 0x11C60000);
      expect(atoms.yuvDiagEnabled, 1);
      await sdrSession.dispose();
      await yuvSession.dispose();
      await pumpEventQueue();
      expect(atoms.diagDataSpace, 0);
      expect(atoms.yuvDiagEnabled, 0);
    });

    test(
        'another session\'s open is rejected while a YUV attempt is in '
        'flight (B1), and proceeds after the hand-off', () async {
      final atoms = _SessionArmAtoms();
      final firstBackend = FakeBackend()..factsForOpen.add(yuvFacts());
      final secondBackend = FakeBackend()
        ..factsForOpen.add(yuvFacts());
      atoms.sink = firstBackend.calls;
      final first = makeSession(
        backend: firstBackend,
        capabilities: lgYuvPqCaps(),
        policy: HdrRoutingPolicy(
          preferences: const {
            HdrSourceClass.hlg: [HdrStrategy.baseLayerConvert],
          },
        ),
        yuvWindowArm: sessionArm(atoms),
      );
      final second = makeSession(
        backend: secondBackend,
        capabilities: lgYuvPqCaps(),
        policy: HdrRoutingPolicy(
          preferences: const {
            HdrSourceClass.hlg: [HdrStrategy.baseLayerConvert],
          },
        ),
        yuvWindowArm: sessionArm(atoms),
      );
      // Hold the first session's YUV attempt between the arm and the open.
      firstBackend.holdConfigure = Completer<void>();
      final firstOpen = first.open(media, hint: hlgSource);
      await pumpUntil(() => firstBackend.calls.any((c) => c.startsWith('configure:')));
      expect(atoms.yuvDiagEnabled, 1,
          reason: 'the in-flight attempt holds the process atoms armed');
      expect(
          firstBackend.calls.indexWhere((c) => c.startsWith('arm:')),
          lessThan(firstBackend.calls
              .indexWhere((c) => c.startsWith('configure:'))),
          reason: 'the arm ACK precedes the configuration phase');

      // The second session's SDR (non-YUV) initialization is rejected with
      // the typed conflict — not silently reading the first session's
      // switches, and not degrading onto another route.
      final events = <HdrOutputEvent>[];
      second.events.listen(events.add);
      await expectLater(second.open(media, hint: sdr),
          throwsA(isA<HdrYuvWindowLeaseConflict>()));
      await pumpEventQueue();
      expect(secondBackend.opened, isEmpty,
          reason: 'the conflicting session initialized no output');
      expect(second.report.value.verified, isFalse);
      expect(events.whereType<HdrErrorEvent>().single.error,
          isA<HdrYuvWindowLeaseConflict>());

      // The accepted window remains owned after open completion. Other
      // sessions cannot initialize either SDR or YUV output while it lives.
      firstBackend.holdConfigure!.complete();
      await firstOpen;
      await pumpEventQueue();
      expect(first.report.value.verified, isTrue);
      await expectLater(second.open(media, hint: sdr),
          throwsA(isA<HdrYuvWindowLeaseConflict>()));
      await expectLater(second.open(media, hint: hlgSource),
          throwsA(isA<HdrYuvWindowLeaseConflict>()));
      expect(secondBackend.opened, isEmpty,
          reason: 'neither conflicting route initialized output');

      // A's dispose releases its retained ownership; B can then initialize
      // YUV. A repeated stale dispose must not clear B's new live window.
      await first.dispose();
      await second.open(media, hint: hlgSource);
      await pumpEventQueue();
      expect(second.report.value.verified, isTrue);
      expect(atoms.diagDataSpace, 0x11C60000);
      expect(atoms.yuvDiagEnabled, 1);
      await first.dispose();
      await pumpEventQueue();
      expect(atoms.diagDataSpace, 0x11C60000);
      expect(atoms.yuvDiagEnabled, 1,
          reason: 'stale A disposal must not clear B ownership');
      await second.dispose();
      await pumpEventQueue();
      expect(atoms.diagDataSpace, 0);
      expect(atoms.yuvDiagEnabled, 0);
    });

    test('a failed YUV attempt disarms before the error surfaces', () async {
      final atoms = _SessionArmAtoms();
      final backend = FakeBackend()..factsForOpen.add(yuvFacts());
      backend.prepareErrorOnce = StateError('output preparation failed');
      final session = makeSession(
        backend: backend,
        capabilities: lgYuvPqCaps(),
        policy: HdrRoutingPolicy(
          preferences: const {
            HdrSourceClass.hlg: [HdrStrategy.baseLayerConvert],
          },
        ),
        yuvWindowArm: sessionArm(atoms),
      );
      final events = <HdrOutputEvent>[];
      session.events.listen(events.add);

      await expectLater(session.open(media, hint: hlgSource), throwsStateError);
      await pumpEventQueue();

      expect(session.report.value.verified, isFalse);
      expect(atoms.armCount, 1);
      expect(atoms.disarmCount, 1,
          reason: 'the failed attempt ends with its terminal cleanup');
      expect(atoms.diagDataSpace, 0);
      expect(atoms.yuvDiagEnabled, 0);
      await session.dispose();
    });

    test('production gap: a YUV route without an owner fails explicitly',
        () async {
      final atoms = _SessionArmAtoms();
      final backend = FakeBackend()..factsForOpen.add(yuvFacts());
      final session = makeSession(
        backend: backend,
        capabilities: lgYuvPqCaps(),
        policy: HdrRoutingPolicy(
          preferences: const {
            HdrSourceClass.hlg: [HdrStrategy.baseLayerConvert],
          },
        ),
        yuvWindowArm: sessionArm(atoms, ownerToken: null),
      );
      final events = <HdrOutputEvent>[];
      session.events.listen(events.add);

      await expectLater(session.open(media, hint: hlgSource),
          throwsA(isA<HdrYuvWindowArmFailure>()));
      await pumpEventQueue();

      final report = session.report.value;
      expect(report.verified, isFalse);
      expect(report.attemptedRoutes.map((r) => r.hwdec),
          contains('surfacetexture'),
          reason: 'the YUV carrier was admitted and failed explicitly');
      expect(report.error, isA<HdrYuvWindowArmFailure>());
      expect(report.error.toString(), contains('no valid surface owner token'));
      expect(events.whereType<HdrErrorEvent>().single.error,
          isA<HdrYuvWindowArmFailure>());
      expect(atoms.calls, isEmpty);
      await session.dispose();
    });

    test('a non-YUV device without the vendor plugin behaves unchanged',
        () async {
      final atoms = _SessionArmAtoms();
      final backend = FakeBackend()..factsForOpen.add(gammaFacts(gamma: 'pq'));
      final session = makeSession(
        backend: backend,
        capabilities: caps(ext: false),
        yuvWindowArm: sessionArm(atoms),
      );
      await session.open(media, hint: hdr10);
      await pumpEventQueue();
      expect(session.report.value.verified, isTrue);
      expect(atoms.calls, isEmpty);
      // Round 3: the non-YUV route takes a READ admission (Begin/End), but
      // performs no arm channel call and touches no atom.
      expect(
          atoms.channelCalls.where((m) => m.contains('YuvDiag')), isEmpty);
      await session.dispose();
    });
  });
}

/// Recording fake for the session-level YUV window arm tests. Mirrors the
/// real native semantics: the bound arm (EnableYuvDiag -> mkvendor_arm_yuv_diag)
/// sets the YUV diag atom, so the "atoms end at zero" assertions verify from
/// a real armed state instead of a never-set one.
class _SessionArmAtoms {
  /// Optional shared event timeline (the fake backend's call list) so tests
  /// can assert cross-phase arm/disarm ordering.
  List<String>? sink;

  /// When set, both disarm paths throw (cleanup-debt scenarios).
  bool disarmFails = false;

  /// Host mirror of the vendor plugin's process-static admission gate,
  /// shared by every session wired to this atoms fake.
  final gate = _SessionInitGate();

  int diagDataSpace = 0;
  int yuvDiagEnabled = 0;
  int armCount = 0;
  int disarmCount = 0;
  final calls = <String>[];
  final channelCalls = <String>[];

  HdrYuvWindowFfiBindings bindings() => HdrYuvWindowFfiBindings(
        setDiagDataSpace: (value) {
          calls.add('diag:$value');
          sink?.add(value == 0 ? 'disarm:diag' : 'arm:diag');
          diagDataSpace = value;
        },
        setYuvDiagEnabled: (value) {
          calls.add('yuvDiag:$value');
          sink?.add(value == 0 ? 'disarm:legacy' : 'arm:legacy');
          yuvDiagEnabled = value;
        },
        disarmYuvDiag: () {
          calls.add('disarm');
          if (disarmFails) throw StateError('native disarm failed');
          yuvDiagEnabled = 0;
        },
      );

  Future<Object?> channel(String method, Map<String, Object?> arguments) async {
    channelCalls.add(method);
    switch (method) {
      case 'EnableYuvDiag':
        armCount++;
        yuvDiagEnabled = 1;
        sink?.add('arm:bound');
        return true;
      case 'DisableYuvDiag':
        disarmCount++;
        if (disarmFails) throw StateError('channel disarm failed');
        yuvDiagEnabled = 0;
        sink?.add('disarm:bound');
        return true;
      case 'BeginOutputInitRead':
        return gate.beginRead();
      case 'EndOutputInitRead':
        gate.endRead();
        return true;
      case 'BeginOutputInitWrite':
        sink?.add('admit:write');
        return gate.beginWrite(
            arguments['ownerToken'] as Object,
            (arguments['leaseId'] as int?) ?? 0);
      case 'EndOutputInitWrite':
        sink?.add('release:write');
        return gate.endWrite((arguments['leaseId'] as int?) ?? 0);
      default:
        return null;
    }
  }
}

/// Host mirror of the Java `ProcessOutputInitGate` statics.
class _SessionInitGate {
  int readers = 0;
  int _writerLease = 0;
  Object? writerKey;
  int _nextLease = 0;

  bool beginRead() {
    if (_writerLease != 0) return false;
    readers++;
    return true;
  }

  void endRead() {
    if (readers > 0) readers--;
  }

  /// Lease-id identity (R3-4 mirror): a held lease rejects every other
  /// acquire — the same token included; only the exact held lease retries.
  int beginWrite(Object key, int retryLease) {
    if (_writerLease != 0 || readers > 0) {
      return retryLease != 0 && retryLease == _writerLease ? _writerLease : 0;
    }
    _writerLease = ++_nextLease;
    writerKey = key;
    return _writerLease;
  }

  bool endWrite(int lease) {
    if (_writerLease == 0 || _writerLease != lease) return false;
    _writerLease = 0;
    writerKey = null;
    return true;
  }

  bool get writer => _writerLease != 0;
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
  const FakeOpened(this.route, this.start, this.options);
  final EffectiveVideoRouteOptions? options;
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

  /// When set, the guarded output initialization inside [prepareOutput]
  /// blocks until completed (suspends MID-initialization, after admission).
  Completer<void>? holdInitialize;
  Object? prepareErrorOnce;

  /// Plan C test wiring: mirrors the production backend's slot hook — the
  /// route-scoped YUV window arm manager prepared inside this attempt.
  HdrYuvWindowArm? yuvWindowArm;

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
    // Mirrors the production backend: the output initialization runs inside
    // the arm manager's process admission (before any retirement), and the
    // arm runs as the initialization's internal preparation.
    final arm = yuvWindowArm;
    if (arm == null) {
      _consumePrepareErrorOnce();
      return;
    }
    await arm.initializeOutput(plan, () async {
      await arm.armForAttempt(plan);
      await holdInitialize?.future;
      _consumePrepareErrorOnce();
    });
  }

  void _consumePrepareErrorOnce() {
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
    opened.add(FakeOpened(plan.route, start, plan.options));
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
      return HdrReviewFacts(
          hwdecCurrent: plan.route.hwdec, path: plan.media.uri);
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
