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
import 'package:media_kit_video/src/hdr/hdr_session_native_dv_policy.dart';
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
const _hdr10 = HdrSourceDescriptor(
  codec: 'hevc',
  transfer: 'pq',
  primaries: 'bt.2020',
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

class _Environment {
  final player = Object();
  final controller = Object();
  final media = Media('test://p5');
  final lock = Lock();
  Duration now = Duration.zero;
  int reads = 0;
  String raw = _dvRaw;
  String hwdec = 'mediacodec';
  late HdrOptionSourceIdentity current = source();
  late HdrNativeDvOutputSnapshot? currentOutput = output();

  HdrOptionSourceIdentity source(
          {Object? owner, String? path, String entry = '7', int epoch = 4}) =>
      HdrOptionSourceIdentity(
          player: owner ?? player,
          path: path ?? media.uri,
          playlistEntryId: entry,
          fileLoadedEpoch: epoch);
  HdrNativeDvOutputSnapshot output(
          {Object? owner,
          int handle = 11,
          int generation = 2,
          int view = 3,
          int surface = 4,
          int wid = 5}) =>
      HdrNativeDvOutputSnapshot(
          owner ?? controller,
          AndroidSurfaceAccountId(
              handle: handle,
              generation: generation,
              viewId: view,
              surfaceGeneration: surface,
              wid: wid));
  HdrReviewFacts facts(
      {bool evidence = true,
      HdrOptionSourceIdentity? identity,
      FileLoadedRecord? loaded,
      HdrNativeDvOutputSnapshot? bound,
      String configuration = _dvRaw,
      String actualHwdec = 'mediacodec',
      String codec = 'hevc',
      int? profile = 5,
      int? compatibility = 0,
      bool? el = false,
      String? path}) {
    final selectedOutput = bound ?? output();
    return HdrReviewFacts(
        path: path ?? media.uri,
        codec: codec,
        dolbyVisionProfile: profile,
        dvCompatibilityId: compatibility,
        dvElPresent: el,
        hwdecCurrent: actualHwdec,
        nativeDvEvidence: evidence
            ? HdrNativeDvReviewEvidence(
                source: identity ?? source(),
                loaded: loaded ?? const FileLoadedRecord(4, 7),
                controller: selectedOutput.controller,
                output: selectedOutput.identity,
                configuration:
                    AndroidMediaCodecConfiguration.parse(configuration)!,
                hwdecCurrent: actualHwdec)
            : null);
  }

  HdrOpenPlan plan({HdrCapabilities? capabilities}) {
    final caps = capabilities ?? _caps();
    final prediction = _nativePlanner(
        source: _p5,
        capabilities: caps,
        policy: HdrRoutingPolicy.defaults,
        preference: HdrOutputPreference.auto,
        excluded: const {});
    return HdrOpenPlan(
        media: media,
        source: _p5,
        sourceOrigin: HdrReportSource.hint,
        capabilities: caps,
        prediction: prediction,
        route: prediction.selected.route!);
  }

  Future<HdrOptionSourceIdentity> readIdentity() async {
    reads++;
    return current;
  }

  Future<String> readProperty(String name) async {
    reads++;
    return name == 'android-mediacodec-info' ? raw : hwdec;
  }

  Future<HdrSessionReviewWindow> window(HdrOpenPlan plan, HdrReviewFacts facts,
      {Duration budget = const Duration(seconds: 8)}) async {
    HdrSessionReviewWindow? captured;
    final backend = _Backend()..review = ((_) async => facts);
    await HdrSessionReviewBackend(
            delegate: backend,
            generationOf: (_) => 1,
            isCurrent: (_) => true,
            admit: (_) {},
            publishWindow: (w) => captured = w,
            monotonicNow: () => now,
            budget: budget)
        .reviewFacts(plan);
    return captured!;
  }

  Future<void> consume(
          HdrSessionReviewWindow window, HdrOpenPlan plan, HdrReviewFacts facts,
          {bool Function()? live,
          Future<HdrOptionSourceIdentity> Function()? identityReader,
          HdrNativeDvOutputSnapshot? Function()? outputReader}) =>
      consumeNativeDvSessionEvidence(
          window: window,
          generation: 1,
          plan: plan,
          facts: facts,
          expectedPlayer: player,
          lock: lock,
          readIdentity: identityReader ?? readIdentity,
          readProperty: readProperty,
          readOutput: outputReader ?? (() => currentOutput),
          isCurrent: live ?? (() => true));
  HdrVideoSession session(_Backend backend,
          {HdrCapabilities? capabilities,
          bool customPlanner = true,
          Duration budget = const Duration(seconds: 8)}) =>
      HdrVideoSession.forTesting(
          backend: backend,
          isAndroid: true,
          capabilitiesProvider: () async => capabilities ?? _caps(),
          routePlanner: customPlanner ? _nativePlanner : null,
          nativePlayerIdentity: player,
          nativePlayerLock: lock,
          readNativeIdentity: readIdentity,
          readNativeProperty: readProperty,
          readNativeOutput: () => currentOutput,
          reviewMonotonicNow: () => now,
          reviewBudget: budget);
}

Matcher _kind(HdrNativeDvReviewFailureKind kind) =>
    isA<HdrNativeDvReviewFailure>().having((e) => e.kind, 'kind', kind);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('valid evidence is consumed under real shared Lock with fresh endpoints',
      () async {
    final env = _Environment();
    final plan = env.plan(), facts = env.facts();
    final window = await env.window(plan, facts);
    await env.consume(window, plan, facts);
    expect(env.reads, 7);
  });
  test('consumer microtask boundary after final output rejects supersession',
      () async {
    final env = _Environment();
    final plan = env.plan(), facts = env.facts();
    final window = await env.window(plan, facts);
    var live = true, outputReads = 0;
    await expectLater(
        env.consume(window, plan, facts,
            live: () => live,
            outputReader: () {
              if (++outputReads == 2) scheduleMicrotask(() => live = false);
              return env.currentOutput;
            }),
        throwsA(isA<OpenSuperseded>()));
  });
  test('consumer microtask boundary remains charged to the original deadline',
      () async {
    final env = _Environment();
    final plan = env.plan(), facts = env.facts();
    final window = await env.window(plan, facts);
    var outputReads = 0;
    await expectLater(
        env.consume(window, plan, facts, outputReader: () {
          if (++outputReads == 2) {
            scheduleMicrotask(() => env.now = const Duration(seconds: 8));
          }
          return env.currentOutput;
        }),
        throwsA(_kind(HdrNativeDvReviewFailureKind.timeout)));
  });

  final invalidFacts = <String, HdrReviewFacts Function(_Environment)>{
    'missing evidence': (e) => e.facts(evidence: false),
    'HEVC configured': (e) => e.facts(
        configuration:
            '{"api":1,"mime":"video/hevc","codec":"qcom.hevc","native-dv-active":false}'),
    'inactive DV configured': (e) => e.facts(
        configuration:
            '{"api":1,"mime":"video/dolby-vision","codec":"qcom.dv","native-dv-active":false}'),
    'wrong hardware mode': (e) => e.facts(actualHwdec: 'mediacodec-copy'),
    'actual track missing P5': (e) => e.facts(profile: null),
    'actual track wrong profile': (e) => e.facts(profile: 8),
    'actual track missing compatibility': (e) => e.facts(compatibility: null),
    'actual track wrong compatibility': (e) => e.facts(compatibility: 1),
    'actual track unknown EL': (e) => e.facts(el: null),
    'actual track has EL': (e) => e.facts(el: true),
    'actual track wrong codec': (e) => e.facts(codec: 'h264'),
  };
  for (final item in invalidFacts.entries) {
    test('${item.key} cannot pass native Session consumer', () async {
      final env = _Environment();
      final plan = env.plan(), facts = item.value(env);
      final window = await env.window(plan, facts);
      await expectLater(env.consume(window, plan, facts),
          throwsA(_kind(HdrNativeDvReviewFailureKind.configuration)));
      expect(env.reads, 0);
    });
  }
  final badSources = <String, HdrReviewFacts Function(_Environment)>{
    'other native Player': (e) => e.facts(identity: e.source(owner: Object())),
    'source path': (e) => e.facts(identity: e.source(path: 'test://other')),
    'facts path': (e) => e.facts(path: 'test://other'),
    'entry mismatch': (e) => e.facts(identity: e.source(entry: '8')),
    'noncanonical entry': (e) => e.facts(identity: e.source(entry: '07')),
    'epoch mismatch': (e) => e.facts(identity: e.source(epoch: 5)),
    'no loaded epoch': (e) => e.facts(
        identity: e.source(epoch: 0), loaded: const FileLoadedRecord(0, 7)),
  };
  for (final item in badSources.entries) {
    test('${item.key} is an aborting identity failure', () async {
      final env = _Environment();
      final plan = env.plan(), facts = item.value(env);
      final window = await env.window(plan, facts);
      await expectLater(env.consume(window, plan, facts),
          throwsA(_kind(HdrNativeDvReviewFailureKind.sourceIdentity)));
      expect(env.reads, 0);
    });
  }
  final wrongOutputs =
      <String, HdrNativeDvOutputSnapshot? Function(_Environment)>{
    'controller': (e) => e.output(owner: Object()),
    'handle': (e) => e.output(handle: 12),
    'topology generation': (e) => e.output(generation: 3),
    'view id': (e) => e.output(view: 4),
    'Surface generation': (e) => e.output(surface: 5),
    'wid': (e) => e.output(wid: 6),
    'missing output': (_) => null,
  };
  for (final item in wrongOutputs.entries) {
    test('consumer rejects current ${item.key} drift', () async {
      final env = _Environment();
      final plan = env.plan(), facts = env.facts();
      final window = await env.window(plan, facts);
      env.currentOutput = item.value(env);
      await expectLater(env.consume(window, plan, facts),
          throwsA(_kind(HdrNativeDvReviewFailureKind.outputIdentity)));
    });
  }
  test('same URI pending replacement entry without a new epoch aborts',
      () async {
    final env = _Environment();
    final plan = env.plan(), facts = env.facts();
    final window = await env.window(plan, facts);
    env.current = env.source(entry: '8');
    await expectLater(env.consume(window, plan, facts),
        throwsA(_kind(HdrNativeDvReviewFailureKind.sourceIdentity)));
  });
  test('consumer source or output change during awaited config reads fails',
      () async {
    for (final sourceChange in [true, false]) {
      final env = _Environment();
      final plan = env.plan(), facts = env.facts();
      final window = await env.window(plan, facts);
      var samples = 0;
      await expectLater(
          env.consume(window, plan, facts, identityReader: () async {
            if (++samples == 2) {
              if (sourceChange) {
                env.current = env.source(entry: '8');
              } else {
                env.currentOutput = env.output(surface: 5);
              }
            }
            return env.current;
          }),
          throwsA(_kind(sourceChange
              ? HdrNativeDvReviewFailureKind.sourceIdentity
              : HdrNativeDvReviewFailureKind.outputIdentity)));
    }
  });
  test('current decoder disappearance after producer returns fails', () async {
    final env = _Environment();
    final plan = env.plan(), facts = env.facts();
    final window = await env.window(plan, facts);
    env.raw = '';
    await expectLater(env.consume(window, plan, facts),
        throwsA(_kind(HdrNativeDvReviewFailureKind.configuration)));
  });
  test(
      'decoder disappearance while final source verification awaits is rejected',
      () async {
    final env = _Environment();
    final plan = env.plan(), facts = env.facts();
    final window = await env.window(plan, facts);
    var identities = 0;
    await expectLater(
        env.consume(window, plan, facts, identityReader: () async {
          if (++identities == 2) env.raw = '';
          return env.current;
        }),
        throwsA(_kind(HdrNativeDvReviewFailureKind.configuration)));
  });
  test('a queued consumer detects replacement that wins shared Lock admission',
      () async {
    final env = _Environment();
    final plan = env.plan(), facts = env.facts();
    final window = await env.window(plan, facts);
    final acquired = Completer<void>(), release = Completer<void>();
    final replace = env.lock.synchronized(() async {
      acquired.complete();
      await release.future;
      env.current = env.source(entry: '8');
    });
    await acquired.future;
    final consume = env.consume(window, plan, facts);
    final rejection = expectLater(
        consume, throwsA(_kind(HdrNativeDvReviewFailureKind.sourceIdentity)));
    release.complete();
    await replace;
    await rejection;
  });
  test('identity reader errors retain an aborting typed cause', () async {
    final env = _Environment();
    final plan = env.plan(), facts = env.facts();
    final window = await env.window(plan, facts);
    final cause = StateError('identity read changed');
    await expectLater(
        env.consume(window, plan, facts,
            identityReader: () async => throw cause),
        throwsA(isA<HdrNativeDvReviewFailure>()
            .having((e) => e.cause, 'cause', same(cause))));
  });
  test(
      'producer time is charged to consumer and expired queued callback does not read',
      () async {
    final env = _Environment();
    final plan = env.plan(), facts = env.facts();
    HdrSessionReviewWindow? window;
    final backend = _Backend()
      ..review = ((_) async {
        env.now = const Duration(milliseconds: 7990);
        return facts;
      });
    await HdrSessionReviewBackend(
        delegate: backend,
        generationOf: (_) => 1,
        isCurrent: (_) => true,
        admit: (_) {},
        publishWindow: (w) => window = w,
        monotonicNow: () => env.now).reviewFacts(plan);
    final held = Completer<void>(), acquired = Completer<void>();
    final blocker = env.lock.synchronized(() async {
      acquired.complete();
      await held.future;
    });
    await acquired.future;
    final consumption = env.consume(window!, plan, facts);
    await expectLater(
        consumption, throwsA(_kind(HdrNativeDvReviewFailureKind.timeout)));
    env.now = const Duration(seconds: 8);
    held.complete();
    await blocker;
    await pumpEventQueue();
    expect(env.reads, 0);
  });
  test('window is bound to exact generation plan and facts objects', () async {
    final env = _Environment();
    final plan = env.plan(), facts = env.facts();
    final window = await env.window(plan, facts);
    expect(window.matches(2, plan, facts), isFalse);
    await expectLater(env.consume(window, env.plan(), facts),
        throwsA(_kind(HdrNativeDvReviewFailureKind.sourceIdentity)));
    await expectLater(env.consume(window, plan, env.facts()),
        throwsA(_kind(HdrNativeDvReviewFailureKind.sourceIdentity)));
  });
  test('late old producer cannot replace or mark a new generation window',
      () async {
    final env = _Environment();
    final first = env.plan(), second = env.plan();
    final pending = Completer<HdrReviewFacts>();
    var serial = 1;
    HdrSessionReviewWindow? current;
    final backend = _Backend()
      ..review = ((plan) =>
          identical(plan, first) ? pending.future : Future.value(env.facts()));
    final wrapper = HdrSessionReviewBackend(
        delegate: backend,
        generationOf: (plan) => identical(plan, first) ? 1 : 2,
        isCurrent: (generation) => serial == generation,
        admit: (_) {},
        publishWindow: (w) {
          if (w.generation == serial) current = w;
        });
    final old = wrapper.reviewFacts(first);
    final oldFailure = expectLater(old, throwsA(isA<OpenSuperseded>()));
    serial = 2;
    final fresh = await wrapper.reviewFacts(second);
    final newWindow = current!;
    pending.complete(env.facts());
    await oldFailure;
    expect(current, same(newWindow));
    expect(newWindow.matches(2, second, fresh), isTrue);
  });
  test('producer timeout does not cancel its future or accept its late facts',
      () async {
    final env = _Environment();
    final plan = env.plan();
    final pending = Completer<HdrReviewFacts>();
    var completed = false;
    HdrSessionReviewWindow? window;
    final backend = _Backend()
      ..review = ((_) async {
        final facts = await pending.future;
        completed = true;
        return facts;
      });
    final wrapper = HdrSessionReviewBackend(
        delegate: backend,
        generationOf: (_) => 1,
        isCurrent: (_) => true,
        admit: (_) {},
        publishWindow: (w) => window = w,
        budget: const Duration(milliseconds: 10));
    await expectLater(wrapper.reviewFacts(plan),
        throwsA(_kind(HdrNativeDvReviewFailureKind.timeout)));
    expect(completed, isFalse);
    final facts = env.facts();
    pending.complete(facts);
    await pumpEventQueue();
    expect(completed, isTrue);
    expect(window!.matches(1, plan, facts), isFalse);
  });
  test('ownership and restoration debt dominate nested timeout/config failures',
      () {
    final debt = HdrNativeDvOptionFailure(
        StateError('apply'), {'vd-lavc-o': StateError('restore')});
    expect(nativeDvFailureMustAbort(debt), isTrue);
    for (final kind in [
      HdrNativeDvReviewFailureKind.ownership,
      HdrNativeDvReviewFailureKind.sourceIdentity,
      HdrNativeDvReviewFailureKind.fileLoaded
    ]) {
      expect(
          nativeDvFailureMustAbort(HdrNativeDvReviewFailure(
              HdrNativeDvReviewFailureKind.timeout,
              cause: HdrNativeDvReviewFailure(kind))),
          isTrue);
    }
    expect(
        nativeDvFailureMustAbort(HdrNativeDvReviewFailure(
            HdrNativeDvReviewFailureKind.configuration,
            cause: debt)),
        isTrue);
    expect(
        nativeDvFailureMustAbort(const HdrNativeDvReviewFailure(
            HdrNativeDvReviewFailureKind.configuration)),
        isFalse);
  });

  test('native once reservation does not exclude current successful review',
      () {
    final env = _Environment(), budget = HdrSessionAttemptPolicy();
    final native = env.plan().route;
    budget.admit(native);
    expect(budget.exclusions({}), isEmpty);
    expect(budget.exclusions({}, nextAttempt: true),
        contains(HdrRouteDependency.nativeDolbyVision));
    expect(() => budget.admit(native),
        throwsA(isA<HdrSessionRouteBudgetFailure>()));
    expect(HdrSessionAttemptPolicy().nativeDvAttempted, isFalse);
  });
  test('both native DV and ordinary native HDR consume the two-HDR budget', () {
    final env = _Environment(), budget = HdrSessionAttemptPolicy();
    final hdr = HdrRoutePlanner.plan(source: _hdr10, capabilities: _caps())
        .selected
        .route!;
    budget.admit(env.plan().route);
    budget.admit(hdr);
    expect(budget.hdrAttempts, 2);
    expect(
        () => budget.admit(hdr), throwsA(isA<HdrSessionRouteBudgetFailure>()));
    final sdr = HdrRoutePlanner.plan(
            source: _p5,
            capabilities: _caps(),
            preference: HdrOutputPreference.off)
        .selected
        .route!;
    budget.admit(sdr);
    expect(budget.hdrAttempts, 2);
  });

  group('actual Session/coordinator flow with synthetic evidence', () {
    test('superseded review cannot plan or spend successor generation state',
        () async {
      final env = _Environment();
      final backend = _Backend()..review = ((_) async => env.facts());
      final successorCaps = Completer<HdrCapabilities>();
      var capabilitiesReads = 0, plannerCalls = 0, outputReads = 0;
      Future<void>? successor;
      late HdrVideoSession session;
      session = HdrVideoSession.forTesting(
        backend: backend,
        isAndroid: true,
        capabilitiesProvider: () => ++capabilitiesReads == 1
            ? Future.value(_caps())
            : successorCaps.future,
        routePlanner: (
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
        },
        nativePlayerIdentity: env.player,
        nativePlayerLock: env.lock,
        readNativeIdentity: env.readIdentity,
        readNativeProperty: env.readProperty,
        readNativeOutput: () {
          if (++outputReads == 2) {
            scheduleMicrotask(() {
              successor = session.open(env.media, hint: _p5);
            });
          }
          return env.currentOutput;
        },
        reviewMonotonicNow: () => env.now,
      );
      await session.open(env.media, hint: _p5);
      final callsBeforeSuccessorPlan = plannerCalls;
      successorCaps.complete(_caps());
      await successor;
      expect(callsBeforeSuccessorPlan, 1,
          reason:
              'old review must stop before touching reset generation policy');
      expect(backend.configured.map((p) => p.route.strategy),
          [HdrStrategy.nativeDolbyVision, HdrStrategy.nativeDolbyVision]);
      expect(backend.configured.last.excluded, isEmpty);
      expect(session.report.value.generation, 2);
      expect(session.report.value.verified, isTrue);
      await session.dispose();
    });
    test('native DV and GPU HDR attempts exhaust budget before review upgrades',
        () async {
      final env = _Environment();
      final backend = _Backend()
        ..configureAction = ((plan) async {
          if (plan.route.strategy == HdrStrategy.nativeDolbyVision) {
            throw const HdrNativeDvReviewFailure(
                HdrNativeDvReviewFailureKind.configuration);
          }
        })
        ..review = ((plan) async => HdrReviewFacts(
            path: env.media.uri,
            videoParams: const VideoParams(gamma: 'pq', primaries: 'bt.2020'),
            codec: 'hevc',
            dolbyVisionProfile: 8,
            dvCompatibilityId: 1,
            dvElPresent: false,
            hwdecCurrent: plan.route.hwdec));
      final session = env.session(backend, capabilities: _caps(sdk: 29));
      await session.open(env.media, hint: _p5);
      expect(backend.configured.map((p) => p.route.strategy), [
        HdrStrategy.nativeDolbyVision,
        HdrStrategy.metadataReshape,
        HdrStrategy.toneMapSdr,
      ]);
      expect(
          backend.configured
              .where((p) => HdrSessionAttemptPolicy.isHdr(p.route)),
          hasLength(2));
      expect(session.report.value.actual!.strategy, HdrStrategy.toneMapSdr);
      expect(backend.opened.last.excluded,
          contains(HdrRouteDependency.nativeDolbyVision));
      await session.dispose();
    });
    test('valid native evidence is accepted once without a rebuild', () async {
      final env = _Environment();
      final backend = _Backend()..review = ((_) async => env.facts());
      final session = env.session(backend);
      await session.open(env.media, hint: _p5);
      expect(backend.opened.map((p) => p.route.strategy),
          [HdrStrategy.nativeDolbyVision]);
      expect(session.report.value.verified, isTrue);
      await session.dispose();
    });
    for (final name in [
      'missing evidence',
      'HEVC configured',
      'actual track missing P5'
    ]) {
      test('$name retries only to safe P5 fallback and preserves exclusion',
          () async {
        final env = _Environment();
        final backend = _Backend()
          ..review = ((plan) async =>
              plan.route.strategy == HdrStrategy.nativeDolbyVision
                  ? invalidFacts[name]!(env)
                  : HdrReviewFacts(
                      path: env.media.uri,
                      codec: 'hevc',
                      dolbyVisionProfile: 5,
                      dvCompatibilityId: 0,
                      dvElPresent: false,
                      hwdecCurrent: plan.route.hwdec));
        final session = env.session(backend);
        await session.open(env.media, hint: _p5);
        expect(backend.opened.map((p) => p.route.strategy),
            [HdrStrategy.nativeDolbyVision, HdrStrategy.toneMapSdr]);
        expect(backend.opened.last.excluded,
            contains(HdrRouteDependency.nativeDolbyVision));
        expect(session.report.value.actual!.strategy, HdrStrategy.toneMapSdr);
        expect(session.report.value.degradeReason,
            HdrDegradeReason.nativeDvUnavailable);
        await session.dispose();
      });
    }
    test(
        'reclassification to native after a prior review rebuild cannot accept missing evidence',
        () async {
      final env = _Environment();
      var review = 0;
      final backend = _Backend()
        ..review = ((plan) async {
          if (++review == 1) {
            return HdrReviewFacts(
                path: env.media.uri,
                codec: 'hevc',
                dolbyVisionProfile: 5,
                dvCompatibilityId: 0,
                dvElPresent: false,
                hwdecCurrent: plan.route.hwdec);
          }
          if (review == 2) return env.facts(evidence: false);
          return HdrReviewFacts(
              path: env.media.uri,
              codec: 'hevc',
              dolbyVisionProfile: 5,
              dvCompatibilityId: 0,
              dvElPresent: false,
              hwdecCurrent: plan.route.hwdec);
        });
      final session = env.session(backend);
      await session.open(env.media);
      expect(backend.opened.map((p) => p.route.strategy), [
        HdrStrategy.sdrDirect,
        HdrStrategy.nativeDolbyVision,
        HdrStrategy.toneMapSdr
      ]);
      expect(session.report.value.actual!.strategy, HdrStrategy.toneMapSdr);
      expect(session.report.value.verified, isTrue);
      await session.dispose();
    });
    test('native failure fallback cannot play P5 without its rescale pipeline',
        () async {
      final env = _Environment();
      final backend = _Backend()
        ..review = ((_) async => env.facts(evidence: false));
      final session =
          env.session(backend, capabilities: _caps(pipeline: false));
      await expectLater(session.open(env.media, hint: _p5),
          throwsA(_kind(HdrNativeDvReviewFailureKind.configuration)));
      expect(backend.opened, hasLength(1));
      expect(session.report.value.verified, isFalse);
      expect(
          backend.configured
              .where((p) => p.route.strategy == HdrStrategy.toneMapSdr),
          isEmpty);
      await session.dispose();
    });
    test(
        'nested ownership/debt aborts with original error and no next candidate',
        () async {
      for (final error in [
        HdrNativeDvOptionFailure(null, {'vd-lavc-o': StateError('debt')}),
        HdrNativeDvReviewFailure(HdrNativeDvReviewFailureKind.timeout,
            cause: const HdrNativeDvReviewFailure(
                HdrNativeDvReviewFailureKind.sourceIdentity)),
      ]) {
        final env = _Environment();
        final backend = _Backend()..review = ((_) async => throw error);
        final session = env.session(backend);
        await expectLater(
            session.open(env.media, hint: _p5), throwsA(same(error)));
        expect(backend.configured, hasLength(1));
        expect(session.report.value.verified, isFalse);
        await session.dispose();
      }
    });
    test('same URI foreign pending replacement aborts before another configure',
        () async {
      final env = _Environment();
      final backend = _Backend()
        ..review = ((_) async {
          final facts = env.facts();
          env.current = env.source(entry: '8');
          return facts;
        });
      final session = env.session(backend);
      await expectLater(session.open(env.media, hint: _p5),
          throwsA(_kind(HdrNativeDvReviewFailureKind.sourceIdentity)));
      expect(backend.configured, hasLength(1));
      await session.dispose();
    });
    test('a new open generation resets failed native exclusion and reservation',
        () async {
      final env = _Environment();
      var fail = true;
      final backend = _Backend()
        ..review = ((plan) async {
          if (plan.route.strategy == HdrStrategy.nativeDolbyVision) {
            return env.facts(evidence: !fail);
          }
          return HdrReviewFacts(
              path: env.media.uri,
              codec: 'hevc',
              dolbyVisionProfile: 5,
              dvCompatibilityId: 0,
              dvElPresent: false,
              hwdecCurrent: plan.route.hwdec);
        });
      final session = env.session(backend);
      await session.open(env.media, hint: _p5);
      fail = false;
      await session.open(env.media, hint: _p5);
      expect(backend.opened.map((p) => p.route.strategy), [
        HdrStrategy.nativeDolbyVision,
        HdrStrategy.toneMapSdr,
        HdrStrategy.nativeDolbyVision
      ]);
      expect(session.report.value.generation, 2);
      await session.dispose();
    });
    test('real planner stays unsupported even with allowExperimental',
        () async {
      final env = _Environment();
      final backend = _Backend()
        ..review = ((plan) async => HdrReviewFacts(
            path: env.media.uri,
            codec: 'hevc',
            dolbyVisionProfile: 5,
            dvCompatibilityId: 0,
            dvElPresent: false,
            hwdecCurrent: plan.route.hwdec));
      final session = HdrVideoSession.forTesting(
          backend: backend,
          isAndroid: true,
          policy: const HdrRoutingPolicy(allowExperimental: true),
          capabilitiesProvider: () async => _caps());
      await session.open(env.media, hint: _p5);
      expect(
          backend.opened
              .any((p) => p.route.strategy == HdrStrategy.nativeDolbyVision),
          isFalse);
      await session.dispose();
      final source =
          File('lib/src/hdr/hdr_video_session.dart').readAsStringSync();
      final ordinaryConstructor = source.substring(
          source.indexOf('  HdrVideoSession('),
          source.indexOf('  /// Test seam:'));
      expect(ordinaryConstructor, isNot(contains('routePlanner')));
      expect(ordinaryConstructor, isNot(contains('readNative')));
      expect(source,
          contains('_routePlanner = routePlanner ?? HdrRoutePlanner.plan'));
    });
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
