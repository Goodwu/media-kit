import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' show Media, VideoParams;
import 'package:media_kit_video/src/hdr/hdr_capabilities.dart';
import 'package:media_kit_video/src/hdr/hdr_open_coordinator.dart';
import 'package:media_kit_video/src/hdr/hdr_open_plan.dart';
import 'package:media_kit_video/src/hdr/hdr_output_event.dart';
import 'package:media_kit_video/src/hdr/hdr_route.dart';
import 'package:media_kit_video/src/hdr/hdr_route_planner.dart';
import 'package:media_kit_video/src/hdr/hdr_source_descriptor.dart';
import 'package:media_kit_video/src/hdr/hdr_strategy.dart';
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

  HdrCapabilities caps({
    Set<int>? types = const {1, 2, 3},
    bool p5Pipeline = true,
    bool ext = true,
  }) =>
      HdrCapabilities(
        sdkInt: 29,
        displayHdrTypes: types,
        hevcDecoders: const <HdrDecoderInfo>[],
        dolbyVisionDecoders: const <HdrDecoderInfo>[],
        p5PipelineAvailable: p5Pipeline,
        dataSpaceBridgeLoaded: true,
        dataSpaceExt: ext
            ? const HdrDataSpaceExtInfo(id: 'lya-pq', applicable: true)
            : null,
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

  test('a second review disagreement is accepted and reported honestly',
      () async {
    // The decoder keeps failing hardware decoding; after the first rebuild
    // to tone-map the second review still disagrees on hwdec.
    final backend = FakeBackend()
      ..factsForOpen.add(facts(gamma: 'pq', primaries: 'bt.2020', hwdec: 'no'))
      ..factsForOpen.add(facts(gamma: 'pq', primaries: 'bt.2020', hwdec: 'no'));
    final session = makeSession(
      backend: backend,
      capabilities: caps(),
      position: const Duration(seconds: 2),
    );
    final events = <HdrOutputEvent>[];
    session.events.listen(events.add);

    await session.open(media, hint: hdr10);
    await pumpEventQueue();

    expect(backend.opened, hasLength(2)); // No third open.
    expect(backend.opened.last.route.strategy, HdrStrategy.toneMapSdr);
    final report = session.report.value;
    expect(report.verified, isTrue);
    expect(report.degradeReason, HdrDegradeReason.hwdecMismatch);
    expect(report.diagnostic, contains('mismatch persisted'));
    expect(
      events.whereType<HdrDegradedEvent>().single.reason,
      HdrDegradeReason.hwdecMismatch,
    );
    await session.dispose();
  });

  test('dataspace failure degrades along the candidates, tone-map keeps '
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

  test('hwdec mismatch excludes the stage and reopens in place', () async {
    final backend = FakeBackend()
      ..factsForOpen.add(facts(gamma: 'pq', primaries: 'bt.2020', hwdec: 'no'))
      ..factsForOpen
          .add(facts(gamma: 'pq', primaries: 'bt.2020', hwdec: 'mediacodec'));
    final session = makeSession(
      backend: backend,
      capabilities: caps(),
      position: const Duration(seconds: 3),
    );
    final events = <HdrOutputEvent>[];
    session.events.listen(events.add);

    await session.open(media, hint: hdr10);
    await pumpEventQueue();

    expect(backend.opened, hasLength(2));
    expect(backend.opened.first.route.strategy, HdrStrategy.baseLayerDirect);
    expect(backend.opened.last.route.strategy, HdrStrategy.toneMapSdr);
    expect(backend.opened.last.start, const Duration(seconds: 3));
    final report = session.report.value;
    expect(report.verified, isTrue);
    expect(report.degradeReason, HdrDegradeReason.hwdecMismatch);
    expect(report.hwdecCurrent, 'mediacodec');
    expect(
      events.whereType<HdrDegradedEvent>().single.reason,
      HdrDegradeReason.hwdecMismatch,
    );
    await session.dispose();
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
  const AttemptScript({this.dataSpaceApplyFailed = false, this.bindTimeout});

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

  /// Facts returned by [reviewFacts], one entry per attempt (last repeats).
  final factsForOpen = <HdrReviewFacts>[];

  /// Scripted failures, consumed one per [configure] call.
  final attemptScripts = <AttemptScript>[];

  /// When set, [configure] blocks until completed (holds the queue).
  Completer<void>? holdConfigure;

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
  }

  @override
  Future<void> configure(HdrOpenPlan plan) async {
    calls.add('configure:${_tag(plan)}');
    _attempt++;
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
    opened.add(FakeOpened(plan.route, start));
  }

  @override
  Future<HdrReviewFacts> reviewFacts(HdrOpenPlan plan) async {
    calls.add('review:${_tag(plan)}');
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
