import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:synchronized/synchronized.dart';

import 'package:media_kit_video/src/hdr/android_mediacodec_configuration.dart';
import 'package:media_kit_video/src/hdr/hdr_capabilities.dart';
import 'package:media_kit_video/src/hdr/hdr_native_dv_option_owner.dart';
import 'package:media_kit_video/src/hdr/hdr_native_dv_review_evidence.dart';
import 'package:media_kit_video/src/hdr/hdr_open_coordinator.dart';
import 'package:media_kit_video/src/hdr/hdr_open_plan.dart';
import 'package:media_kit_video/src/hdr/hdr_route.dart';
import 'package:media_kit_video/src/hdr/hdr_route_planner.dart';
import 'package:media_kit_video/src/hdr/hdr_source_descriptor.dart';
import 'package:media_kit_video/src/hdr/hdr_strategy.dart';
import 'package:media_kit_video/src/hdr/hdr_strategy_realizer.dart';
import 'package:media_kit_video/src/hdr/hdr_video_session.dart';
import 'package:media_kit_video/src/video_controller/android_video_controller/platform_surface_release.dart';

// Synthetic facts exercise production policy/consumer and Session wiring.
// They are not evidence that any decoder or display actually works.
const _p5 = HdrSourceDescriptor(
  codec: 'hevc',
  dynamicMetadata: HdrDynamicMetadata.dolbyVision,
  dvProfile: 5,
  dvCompatibilityId: 0,
  enhancementLayer: false,
);
const _dvRaw = '{"api":1,"mime":"video/dolby-vision",'
    '"codec":"OMX.qcom.video.decoder.dolby-vision","native-dv-active":true}';

HdrCapabilities _caps({bool pipeline = true, int sdk = 24}) => HdrCapabilities(
      sdkInt: sdk,
      displayHdrTypes: const {1, 2, 3},
      hevcDecoders: const [],
      dolbyVisionDecoders: const [
        HdrDecoderInfo(
          name: 'OMX.qcom.video.decoder.dolby-vision',
          mimeType: 'video/dolby-vision',
          hardwareAcceleration: true,
          profiles: [32],
          main10: null,
          widthRange: null,
          heightRange: null,
          frameRateRange: null,
          supports4K: true,
          max4KFps: 60,
        )
      ],
      p5PipelineAvailable: pipeline,
      nativeDvBridgeApi: 1,
      dataSpaceBridgeLoaded: true,
      dataSpaceExt: const HdrDataSpaceExtInfo(id: 'test', applicable: true),
    );

// Only supplied to forTesting. The realizer is real; maturity is bypassed
// here so unreachable-by-default native Session branches can be exercised.
HdrRoutePrediction _nativePlanner({
  required HdrSourceDescriptor source,
  required HdrCapabilities capabilities,
  required HdrRoutingPolicy policy,
  required HdrOutputPreference preference,
  required Map<String, HdrDegradeReason> excluded,
}) {
  final ordinary = HdrRoutePlanner.plan(
      source: source,
      capabilities: capabilities,
      policy: policy,
      preference: preference,
      excluded: excluded);
  if (HdrSourceClass.of(source) != HdrSourceClass.dvP5 ||
      preference == HdrOutputPreference.off ||
      excluded.containsKey(HdrRouteDependency.nativeDolbyVision)) {
    return ordinary;
  }
  final route = HdrStrategyRealizer.realize(HdrStrategy.nativeDolbyVision,
          source: source,
          sourceClass: HdrSourceClass.dvP5,
          capabilities: capabilities)
      .route;
  if (route == null) return ordinary;
  final candidate = HdrCandidate(
      strategy: HdrStrategy.nativeDolbyVision,
      maturity: HdrStrategyMaturity.unsupported,
      route: route,
      feasible: true);
  return HdrRoutePrediction(
      source: source,
      selected: candidate,
      candidates: [candidate, ...ordinary.candidates],
      presentation: route.presentation,
      confidence: HdrPredictionConfidence.unverified,
      playable: true);
}

typedef _Observer = void Function(int, HdrOpenPlan, HdrReviewFacts);

class _Environment {
  final player = Object();
  final controller = Object();
  final media = Media('test://p5');
  final lock = Lock();
  Duration now = Duration.zero;
  late HdrOptionSourceIdentity current = source();
  int plannerCalls = 0;

  HdrOptionSourceIdentity source({String entry = '7'}) =>
      HdrOptionSourceIdentity(
          player: player,
          path: media.uri,
          playlistEntryId: entry,
          fileLoadedEpoch: 4);
  HdrNativeDvOutputSnapshot output() => HdrNativeDvOutputSnapshot(
      controller,
      const AndroidSurfaceAccountId(
          handle: 11, generation: 2, viewId: 3, surfaceGeneration: 4, wid: 5));
  HdrReviewFacts facts(
      {bool evidence = true, HdrOptionSourceIdentity? identity}) {
    final bound = output();
    return HdrReviewFacts(
        path: media.uri,
        codec: 'hevc',
        dolbyVisionProfile: 5,
        dvCompatibilityId: 0,
        dvElPresent: false,
        hwdecCurrent: 'mediacodec',
        nativeDvEvidence: evidence
            ? HdrNativeDvReviewEvidence(
                source: identity ?? source(),
                loaded: const FileLoadedRecord(4, 7),
                controller: bound.controller,
                output: bound.identity,
                configuration: AndroidMediaCodecConfiguration.parse(_dvRaw)!,
                hwdecCurrent: 'mediacodec')
            : null);
  }

  Future<HdrReviewFacts> review(HdrOpenPlan plan) async =>
      plan.route.strategy == HdrStrategy.nativeDolbyVision
          ? facts()
          : HdrReviewFacts(
              path: media.uri,
              codec: 'hevc',
              dolbyVisionProfile: 5,
              dvCompatibilityId: 0,
              dvElPresent: false,
              hwdecCurrent: plan.route.hwdec);

  HdrVideoSession session(
    _Backend backend, {
    _Observer? observer,
    void Function(Object, StackTrace)? captureError,
    Future<HdrCapabilities> Function()? capabilitiesProvider,
    bool diagnosticPlanner = true,
  }) =>
      HdrVideoSession.forTesting(
          backend: backend,
          isAndroid: true,
          capabilitiesProvider: capabilitiesProvider ?? (() async => _caps()),
          routePlanner: diagnosticPlanner
              ? (
                  {required source,
                  required capabilities,
                  required policy,
                  required preference,
                  required excluded}) {
                  plannerCalls++;
                  return _nativePlanner(
                      source: source,
                      capabilities: capabilities,
                      policy: policy,
                      preference: preference,
                      excluded: excluded);
                }
              : null,
          nativePlayerIdentity: player,
          nativePlayerLock: lock,
          readNativeIdentity: () async => current,
          readNativeProperty: (name) async =>
              name == 'android-mediacodec-info' ? _dvRaw : 'mediacodec',
          readNativeOutput: output,
          reviewMonotonicNow: () => now,
          onNativeDvConsumerValidated: observer,
          onNativeDvConsumerCaptureError: captureError);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('actual Session publishes exact generation plan and facts once',
      () async {
    final env = _Environment();
    final backend = _Backend();
    late HdrOpenPlan reviewedPlan;
    late HdrReviewFacts reviewedFacts;
    backend.review = (plan) async {
      reviewedPlan = plan;
      return reviewedFacts = env.facts();
    };
    final observations = <List<Object>>[];
    final session = env.session(backend, observer: (generation, plan, facts) {
      // This is before classification/routeApplied, not displayed-frame proof.
      expect(env.plannerCalls, 1);
      observations.add([generation, plan, facts]);
    });
    await session.open(env.media, hint: _p5);
    expect(observations, hasLength(1));
    expect(observations.single[0], 1);
    expect(observations.single[1], same(reviewedPlan));
    expect(observations.single[2], same(reviewedFacts));
    expect(env.plannerCalls, 2);
    expect(
        session.report.value.actual?.strategy, HdrStrategy.nativeDolbyVision);
    expect(session.report.value.verified, isTrue);
    await session.dispose();
  });

  test('observer absent adds no recorder behavior', () async {
    final env = _Environment();
    final backend = _Backend()..review = env.review;
    var errors = 0;
    final session = env.session(backend, captureError: (_, __) => errors++);
    await session.open(env.media, hint: _p5);
    expect(errors, 0);
    expect(backend.opened, hasLength(1));
    expect(
        session.report.value.actual?.strategy, HdrStrategy.nativeDolbyVision);
    await session.dispose();
  });

  test('no successful consumer means no publication even after safe fallback',
      () async {
    final env = _Environment();
    final backend = _Backend()
      ..review = (plan) async =>
          plan.route.strategy == HdrStrategy.nativeDolbyVision
              ? env.facts(evidence: false)
              : await env.review(plan);
    var captures = 0;
    final session = env.session(backend, observer: (_, __, ___) => captures++);
    await session.open(env.media, hint: _p5);
    expect(captures, 0);
    expect(backend.opened.map((p) => p.route.strategy),
        [HdrStrategy.nativeDolbyVision, HdrStrategy.toneMapSdr]);
    await session.dispose();
  });

  test('consumer source identity failure never publishes or retries', () async {
    final env = _Environment();
    final backend = _Backend()
      ..review = ((_) async => env.facts(identity: env.source(entry: '8')));
    var captures = 0;
    final session = env.session(backend, observer: (_, __, ___) => captures++);
    await expectLater(
        session.open(env.media, hint: _p5),
        throwsA(isA<HdrNativeDvReviewFailure>().having((e) => e.kind, 'kind',
            HdrNativeDvReviewFailureKind.sourceIdentity)));
    expect(captures, 0);
    expect(backend.opened, hasLength(1));
    await session.dispose();
  });

  test('producer typed ownership failure never publishes or retries', () async {
    final env = _Environment();
    final error =
        HdrNativeDvOptionFailure(null, {'vd-lavc-o': StateError('debt')});
    final backend = _Backend()..review = ((_) async => throw error);
    var captures = 0;
    final session = env.session(backend, observer: (_, __, ___) => captures++);
    await expectLater(session.open(env.media, hint: _p5), throwsA(same(error)));
    expect(captures, 0);
    expect(backend.opened, hasLength(1));
    await session.dispose();
  });

  test('observer exception reports exact error and keeps native route',
      () async {
    final env = _Environment();
    final backend = _Backend()..review = env.review;
    final error = StateError('recorder');
    Object? capturedError;
    StackTrace? capturedStack;
    final session = env.session(backend,
        observer: (_, __, ___) => throw error,
        captureError: (e, s) {
          capturedError = e;
          capturedStack = s;
        });
    await session.open(env.media, hint: _p5);
    expect(capturedError, same(error));
    expect(capturedStack, isNotNull);
    expect(backend.opened, hasLength(1));
    expect(
        session.report.value.actual?.strategy, HdrStrategy.nativeDolbyVision);
    await session.dispose();
  });

  test('observer and error sink exceptions are both contained', () async {
    final env = _Environment();
    final backend = _Backend()..review = env.review;
    var errors = 0;
    final session = env.session(backend,
        observer: (_, __, ___) => throw StateError('recorder'),
        captureError: (_, __) {
          errors++;
          throw StateError('sink');
        });
    await session.open(env.media, hint: _p5);
    expect(errors, 1);
    expect(backend.opened, hasLength(1));
    expect(
        session.report.value.actual?.strategy, HdrStrategy.nativeDolbyVision);
    await session.dispose();
  });

  test('observer reentrant open prevents old review from planning successor',
      () async {
    final env = _Environment();
    final backend = _Backend()..review = env.review;
    final successorCaps = Completer<HdrCapabilities>();
    var queries = 0;
    Future<void>? successor;
    final captured = <int>[];
    late HdrVideoSession session;
    session = env.session(backend,
        capabilitiesProvider: () async =>
            ++queries == 1 ? _caps() : await successorCaps.future,
        observer: (generation, _, __) {
          captured.add(generation);
          if (generation == 1) successor = session.open(env.media, hint: _p5);
        });
    await session.open(env.media, hint: _p5);
    expect(env.plannerCalls, 1);
    expect(session.report.value.verified, isFalse);
    expect(captured, [1]);
    successorCaps.complete(_caps());
    await successor;
    expect(captured, [1, 2]);
    expect(session.report.value.generation, 2);
    expect(
        session.report.value.actual?.strategy, HdrStrategy.nativeDolbyVision);
    await session.dispose();
  });

  test('observer reentrant dispose prevents old review planning or publication',
      () async {
    final env = _Environment();
    final backend = _Backend()..review = env.review;
    Future<void>? disposing;
    late HdrVideoSession session;
    session = env.session(backend, observer: (_, __, ___) {
      disposing = session.dispose();
    });
    await session.open(env.media, hint: _p5);
    await disposing;
    expect(env.plannerCalls, 1);
    expect(session.report.value.verified, isFalse);
    expect(backend.opened, hasLength(1));
  });

  test('error sink reentrant dispose is checked even when sink throws',
      () async {
    final env = _Environment();
    final backend = _Backend()..review = env.review;
    Future<void>? disposing;
    late HdrVideoSession session;
    session = env.session(backend,
        observer: (_, __, ___) => throw StateError('recorder'),
        captureError: (_, __) {
          disposing = session.dispose();
          throw StateError('sink');
        });
    await session.open(env.media, hint: _p5);
    await disposing;
    expect(env.plannerCalls, 1);
    expect(session.report.value.verified, isFalse);
  });

  test('observer is charged to original producer deadline and rejects result',
      () async {
    final env = _Environment();
    final backend = _Backend()
      ..review = (plan) async {
        if (plan.route.strategy == HdrStrategy.nativeDolbyVision) {
          env.now = const Duration(seconds: 6);
        }
        return env.review(plan);
      };
    var captures = 0;
    final session = env.session(backend, observer: (_, __, ___) {
      captures++;
      env.now += const Duration(seconds: 2);
    });
    await session.open(env.media, hint: _p5);
    expect(captures, 1); // captured validation is not route application.
    expect(backend.opened.map((p) => p.route.strategy),
        [HdrStrategy.nativeDolbyVision, HdrStrategy.toneMapSdr]);
    expect(session.report.value.actual?.strategy, HdrStrategy.toneMapSdr);
    await session.dispose();
  });

  test('default planner never enables native observer and public API has none',
      () async {
    final env = _Environment();
    final backend = _Backend()..review = env.review;
    var captures = 0;
    final session = env.session(backend,
        diagnosticPlanner: false, observer: (_, __, ___) => captures++);
    await session.open(env.media, hint: _p5);
    expect(captures, 0);
    expect(
        backend.opened.map((p) => p.route.strategy), [HdrStrategy.toneMapSdr]);
    await session.dispose();
    final source =
        File('lib/src/hdr/hdr_video_session.dart').readAsStringSync();
    final publicConstructor = source.substring(
        source.indexOf('  HdrVideoSession('),
        source.indexOf('  /// Test seam:'));
    expect(publicConstructor, isNot(contains('onNativeDvConsumer')));
  });
}

class _Backend implements HdrOpenBackend<HdrOpenPlan> {
  final opened = <HdrOpenPlan>[];
  final configured = <HdrOpenPlan>[];
  final prepared = <HdrOpenPlan>[];
  Future<HdrReviewFacts> Function(HdrOpenPlan)? review;
  Future<void> Function(HdrOpenPlan)? configureAction;
  @override
  Future<void> validate(HdrOpenPlan plan) async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> resetOwnedConfiguration() async {}
  @override
  Future<void> prepareOutput(HdrOpenPlan plan) async {
    prepared.add(plan);
  }

  @override
  Future<void> configure(HdrOpenPlan plan) async {
    configured.add(plan);
    await configureAction?.call(plan);
  }

  @override
  Future<void> waitForOutput(HdrOpenPlan plan) async {}
  @override
  Future<void> open(HdrOpenPlan plan,
      {Duration? start, required bool play}) async {
    opened.add(plan);
  }

  @override
  Future<HdrReviewFacts> reviewFacts(HdrOpenPlan plan) => review!(plan);
  @override
  HdrBackendObservation observe() =>
      const HdrBackendObservation(hwdecCurrent: 'mediacodec');
}
