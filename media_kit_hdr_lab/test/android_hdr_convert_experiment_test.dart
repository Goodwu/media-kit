// ignore_for_file: implementation_imports
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit_video/src/video/platform_view_video.dart';
import 'package:media_kit_hdr_lab/tests/01.single_player_single_video.dart'
    show AndroidLgSingleOwnerVideo;
import '../../media_kit_video/test/android_output_presentation_test.dart'
    show FakeController, FakeSession, FakePlayer, FakeStreams;
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:media_kit/media_kit.dart' show Media;
import 'package:media_kit_hdr_lab/common/android_hdr_convert_experiment.dart';
import '../../media_kit_video/test/hdr_video_session_test.dart'
    show FakeBackend, AttemptScript;

const caps = HdrCapabilities(
    sdkInt: 24,
    displayHdrTypes: {2},
    hevcDecoders: [],
    dolbyVisionDecoders: [],
    p5PipelineAvailable: false,
    dataSpaceBridgeLoaded: false,
    dataSpaceExt: HdrDataSpaceExtInfo(id: 'lg-pq', applicable: true));
const source = HdrSourceDescriptor(
    codec: 'hevc',
    transfer: 'hlg',
    dynamicMetadata: HdrDynamicMetadata.dolbyVision,
    dvProfile: 8,
    dvCompatibilityId: 4,
    enhancementLayer: false);
class _WidgetStreams extends FakeStreams {
  @override
  Stream<List<String>> get subtitle => const Stream.empty();
}

class _WidgetPlayer extends FakePlayer {
  _WidgetPlayer() {
    stream = _WidgetStreams();
  }
}

class _WidgetController extends FakeController {
  final _player = _WidgetPlayer();
  @override
  FakePlayer get player => _player;
}

class _PublishedPlatformOutput extends PlatformVideoController {
  _PublishedPlatformOutput(super.player, super.configuration) {
    nativeHandle = 278;
    nativeSurfaceGeneration = 1;
  }

  @override
  Future<void> setSize({int? width, int? height}) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('experimental page uses Session-only mounting, not fallback getter', () {
    final page = File('lib/tests/01.single_player_single_video.dart')
        .readAsStringSync();
    final build = page.lastIndexOf('Widget build(BuildContext context) {');
    final start = page.indexOf('if (_androidLgVisual278Experiment) {', build);
    final end = page.indexOf('if (_androidHdr10SessionDiagnostic) {', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final branch = page.substring(start, end);
    expect(branch, contains('AndroidLgSingleOwnerVideo(session: _hdrSession)'));
    expect(branch, isNot(contains('_hdrTransactionController')));
    expect(branch, isNot(contains('_initialController')));
    expect(branch, isNot(contains('body: Video(')));
  });
  test('plan C retirement: the page owns no YUV arm path; token, verdict and '
      'diagnostics remain', () {
    final page = File('lib/tests/01.single_player_single_video.dart')
        .readAsStringSync();
    // Plan C: the YUV window arm lifecycle is the library's
    // (HdrYuvWindowArm, routed by execution attempt). The page must not read
    // or write the vendor YUV atoms through any path — a pre-open arm here
    // would pollute the process-global atomics before a non-YUV routed open
    // (observed as a dead VO on lgh7-sdr).
    for (final retired in [
      '_armYuvDiagSwitch',
      '_disarmYuvDiagSwitch',
      '_armDiagDataspace',
      '_disarmDiagDataspace',
      '_resolveYuvDiagSwitch',
      '_resolveDiagDataspaceArmer',
      'resolveYuvDiagOwnerGeneration',
      'mkvendor_',
      'EnableYuvDiag',
      'DisableYuvDiag',
    ]) {
      expect(page.contains(retired), isFalse,
          reason: 'retired page-side YUV arm symbol still present: $retired');
    }
    // The owner token capability gate stays: the bridge initializes only
    // through the creationParams' lgExperimentOwnerToken, so the token is a
    // platform-view-owner duty, not an arm duty.
    expect(
        page.contains('if (await _yuvWindowChannelDeclared()) {'), isTrue);
    expect(page, contains('Future<bool> _yuvWindowChannelDeclared()'));
    // The importer verdict and the version-marker capture stay (diagnostics,
    // not production preconditions).
    expect(page, contains("_mkSurfaceVersionMarker = 'MKSURF: version'"));
    expect(page, contains('SurfaceTexture PoC verification failed'));
    expect(page, contains('.report.value.actual?.hwdec =='));
  });
  testWidgets('experiment waits for Session output without default Texture',
      (tester) async {
    final calls = <MethodCall>[];
    const channel = MethodChannel('com.alexmercerind/media_kit_video');
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    final session = FakeSession();
    Widget output(HdrVideoSession? current) => MaterialApp(
        home: Scaffold(body: AndroidLgSingleOwnerVideo(session: current)));

    await tester.pumpWidget(output(null));
    await tester.pump(); // Include the frame which would initialize a controller.
    expect(find.byType(HdrVideoPlaceholder), findsOneWidget);
    expect(find.byType(HdrVideo), findsNothing);
    expect(find.byType(Video), findsNothing);
    expect(find.byType(Texture), findsNothing);
    expect(calls, isEmpty);

    await tester.pumpWidget(output(session));
    await tester.pump();
    expect(find.byType(HdrVideo), findsOneWidget);
    expect(find.byType(HdrVideoPlaceholder), findsOneWidget);
    expect(find.byType(Video), findsNothing);
    expect(find.byType(Texture), findsNothing);
    expect(calls, isEmpty);

    final controller = _WidgetController();
    final platform = _PublishedPlatformOutput(
        controller.player,
        const VideoControllerConfiguration(
            vo: 'gpu-next',
            hwdec: 'mediacodec-copy',
            android: AndroidVideoOptions(
                usePlatformView: true,
                surfaceTransfer: 'pq-itu',
                lgExperimentOwnerToken: 'owner278-widget')));
    controller.notifier.value = platform;
    controller.platform.complete(platform);
    session.published.value = controller;
    await tester.pump();
    expect(find.byType(HdrVideo), findsOneWidget);
    expect(find.byType(Video), findsOneWidget);
    final hdrVideo = tester.widget<HdrVideo>(find.byType(HdrVideo));
    final video = tester.widget<Video>(find.byType(Video));
    expect(hdrVideo.session, same(session));
    expect(hdrVideo.controls, isNull);
    expect(video.controller, same(controller));
    expect(video.controls, isNull);
    expect(video.controller.notifier.value, same(platform));
    expect(platform.configuration.android.usePlatformView, isTrue);
    expect(platform.configuration.android.surfaceTransfer, 'pq-itu');
    expect(platform.configuration.android.lgExperimentOwnerToken,
        'owner278-widget');
    expect(find.byType(Texture), findsNothing);
    expect(calls.where((call) => call.method == 'VideoOutputManager.Create'),
        isEmpty);
    // Host coverage stops at the published output. dart:io's Android branch
    // cannot be enabled with debugDefaultTargetPlatformOverride on macOS.
    if (Platform.isAndroid) {
      expect(find.byType(PlatformViewVideo), findsOneWidget);
      final view =
          tester.widget<PlatformViewVideo>(find.byType(PlatformViewVideo));
      expect(view.handle, 278);
      expect(view.androidSurfaceTransfer, 'pq-itu');
      expect(view.lgExperimentOwnerToken, 'owner278-widget');
    }
    await tester.pumpWidget(const SizedBox.shrink());
    session.published.dispose();
    expect(tester.takeException(), isNull);
  });
  const transfer = String.fromEnvironment(
      'MEDIA_KIT_ANDROID_CONVERT_SURFACE_TRANSFER',
      defaultValue: 'pq');
  const lock = AndroidHdrConvertExperiment(
      transfer, transfer == 'pq' ? 'full' : 'limited');
  test('real lab single-open wrapper failure permanently consumes claim',
      () async {
    final backend = FakeBackend()
      ..attemptScripts.add(const AttemptScript(dataSpaceApplyFailed: true));
    // ignore: invalid_use_of_visible_for_testing_member
    final session = HdrVideoSession.forTesting(
        backend: backend,
        isAndroid: true,
        configuration: const VideoControllerConfiguration(
            android: AndroidVideoOptions(lgExperimentOwnerToken: 'owner-a')),
        capabilitiesProvider: () async => caps,
        routePlanner: lock.plan);
    final owner = AndroidLgSingleOpenOwner('owner-a');
    final revoked = <String>[];
    var prepared = 0;
    Future<void> run() => owner.open(
        session: session,
        media: Media('test://p84'),
        hint: source,
        prepare: () async {
          prepared++;
          owner.bindHandle(7);
        },
        revokeOwner: (token, handle) async {
          revoked.add('$token/$handle');
        });
    await expectLater(run(), throwsA(isA<HdrDataSpaceApplyException>()));
    expect(revoked, ['owner-a/7']);
    await expectLater(run(), throwsStateError);
    expect(prepared, 1);
    await expectLater(
        session.open(Media('test://retry'), hint: source), throwsStateError);
    final backendCalls = List<String>.of(backend.calls);
    final failedReport = session.report.value;
    await expectLater(
        session.setOptions(EffectiveVideoRouteOptions.resolve(
            application: const VideoRouteOptions(
                decode: VideoRouteSelection.require(VideoDecodeTarget.software),
                output: VideoRouteSelection.require(VideoOutputIntent.sdr)))),
        throwsStateError);
    await expectLater(
        session.setPreference(HdrOutputPreference.off), throwsStateError);
    await expectLater(
        session.setPolicy(HdrRoutingPolicy.defaults), throwsStateError);
    expect(backend.calls, backendCalls);
    expect(session.report.value, same(failedReport));
    expect(revoked, ['owner-a/7']);
    expect(prepared, 1);
    await session.dispose();
  });
  test(
      'real lab wrapper consumes failed preparation and stale owner revoke is fixed',
      () async {
    final owner = AndroidLgSingleOpenOwner('old');
    final successor = AndroidLgSingleOpenOwner('new')..bindHandle(8);
    final revoked = <String>[];
    final backend = FakeBackend();
    // ignore: invalid_use_of_visible_for_testing_member
    final session = HdrVideoSession.forTesting(
        backend: backend,
        isAndroid: true,
        capabilitiesProvider: () async => caps,
        routePlanner: lock.plan);
    Future<void> run() => owner.open(
        session: session,
        media: Media('test://p84'),
        prepare: () async {
          owner.bindHandle(7);
          throw StateError('prepare');
        },
        revokeOwner: (token, handle) async {
          revoked.add('$token/$handle');
        });
    await expectLater(run(), throwsStateError);
    await expectLater(run(), throwsStateError);
    await owner.revoke((token, handle) async {
      revoked.add('$token/$handle');
    });
    expect(revoked, ['old/7', 'old/7']);
    expect(successor.token, 'new');
    expect(backend.preparedPlans, isEmpty);
    await session.dispose();
  });
  test('visual278 requires strict Android Session lock, disabled default inert',
      () {
    for (var mask = 0; mask < 8; mask++) {
      void enable() => AndroidHdrConvertExperiment.validateVisual278Admission(
          enabled: true,
          routeLocked: (mask & 1) != 0,
          android: (mask & 2) != 0,
          hdrTransaction: (mask & 4) != 0);
      expect(enable, mask == 7 ? returnsNormally : throwsStateError);
    }
    expect(
        () => AndroidHdrConvertExperiment.validateVisual278Admission(
            enabled: false,
            routeLocked: false,
            android: false,
            hdrTransaction: false),
        returnsNormally);
  });
  test('route lock rejects dataspace perform probe before preparation', () {
    expect(() => lock.validateAdmission(dataSpacePerformProbe: true),
        throwsStateError);
    expect(() => lock.validateAdmission(dataSpacePerformProbe: false),
        returnsNormally);
  });
  HdrRoutePrediction plan(
          {HdrSourceDescriptor input = source,
          Map<String, HdrDegradeReason> excluded = const {},
          HdrCapabilities capabilities = caps,
          HdrOutputPreference preference = HdrOutputPreference.auto}) =>
      lock.plan(
          source: input,
          capabilities: capabilities,
          policy: HdrRoutingPolicy.defaults,
          preference: preference,
          excluded: excluded);
  test('output levels await setter then readback before open', () async {
    final setter = Completer<void>();
    final readback = Completer<String>();
    final calls = <String>[];
    final operation = () async {
      await lock.prepareOutputLevels(
        set: (value) {
          calls.add('set:$value');
          return setter.future;
        },
        read: () {
          calls.add('read');
          return readback.future;
        },
      );
      calls.add('open');
    }();
    await Future<void>.delayed(Duration.zero);
    expect(calls, ['set:${lock.outputLevels}']);
    setter.complete();
    await Future<void>.delayed(Duration.zero);
    expect(calls, ['set:${lock.outputLevels}', 'read']);
    readback.complete(lock.outputLevels);
    await operation;
    expect(calls, ['set:${lock.outputLevels}', 'read', 'open']);
  });
  test('output levels mismatch and setter error prevent open', () async {
    var opened = false;
    Future<void> run(bool failSetter) async {
      await lock.prepareOutputLevels(
          set: (_) async {
            if (failSetter) throw StateError('setter failed');
          },
          read: () async => lock.outputLevels == 'full' ? 'limited' : 'full');
      opened = true;
    }

    await expectLater(run(false), throwsStateError);
    await expectLater(run(true), throwsStateError);
    expect(opened, isFalse);
  });
  test('Session blocks unknown hint before prepare or open', () async {
    final backend = FakeBackend();
    // ignore: invalid_use_of_visible_for_testing_member
    final session = HdrVideoSession.forTesting(
        backend: backend,
        isAndroid: true,
        capabilitiesProvider: () async => caps,
        routePlanner: lock.plan);
    await session.open(Media('test://unknown'));
    expect(session.report.value.error, isA<HdrPlaybackBlocked>());
    expect(backend.preparedPlans, isEmpty);
    expect(backend.opened, isEmpty);
    await session.dispose();
  });
  test('Session setter failure does not prepare/open an SDR fallback',
      () async {
    final backend = FakeBackend()
      ..attemptScripts.add(const AttemptScript(dataSpaceApplyFailed: true));
    // ignore: invalid_use_of_visible_for_testing_member
    final session = HdrVideoSession.forTesting(
        backend: backend,
        isAndroid: true,
        capabilitiesProvider: () async => caps,
        routePlanner: lock.plan);
    await expectLater(session.open(Media('test://p84'), hint: source),
        throwsA(isA<HdrDataSpaceApplyException>()));
    expect(backend.preparedPlans, hasLength(1));
    expect(backend.preparedPlans.single.route.strategy,
        HdrStrategy.baseLayerConvert);
    expect(backend.opened, isEmpty);
    await session.dispose();
  });
  test('Session decoder copy mismatch aborts rather than accepts or falls back',
      () async {
    final backend = FakeBackend()
      ..factsForOpen.add(const HdrReviewFacts(hwdecCurrent: 'no'));
    // ignore: invalid_use_of_visible_for_testing_member
    final session = HdrVideoSession.forTesting(
        backend: backend,
        isAndroid: true,
        capabilitiesProvider: () async => caps,
        routePlanner: lock.plan);
    await session.open(Media('test://p84'), hint: source);
    expect(session.report.value.error, isA<HdrPlaybackBlocked>());
    expect(session.report.value.actual, isNull);
    expect(backend.preparedPlans, hasLength(1));
    expect(backend.opened, hasLength(1));
    expect(backend.opened.single.route.strategy, HdrStrategy.baseLayerConvert);
    await session.dispose();
  });
  test('range pairs are explicit; auto and mismatches fail', () {
    for (final pair in [
      const AndroidHdrConvertExperiment('pq', 'full'),
      const AndroidHdrConvertExperiment('pq-itu', 'limited')
    ]) {
      expect(pair.validate, returnsNormally);
    }
    for (final pair in [
      const AndroidHdrConvertExperiment('pq', 'limited'),
      const AndroidHdrConvertExperiment('pq-itu', 'full'),
      const AndroidHdrConvertExperiment('pq-itu', '')
    ]) {
      expect(pair.validate, throwsStateError);
    }
  });
  test('initial matching route is exclusively GPU PQ copy', () {
    final prediction = plan();
    expect(prediction.confidence, HdrPredictionConfidence.unverified);
    final route = prediction.selected.route!;
    expect(route.strategy, HdrStrategy.baseLayerConvert);
    expect(route.hwdec, 'mediacodec-copy');
    expect(route.surfaceTransfer, transfer);
  });
  test('unknown hint and SDR do not start SDR safety-net output', () {
    expect(() => plan(input: const HdrSourceDescriptor()),
        throwsA(isA<HdrPlaybackBlocked>()));
    expect(() => plan(input: const HdrSourceDescriptor(transfer: 'bt.1886')),
        throwsA(isA<HdrPlaybackBlocked>()));
    expect(() => plan(preference: HdrOutputPreference.off),
        throwsA(isA<HdrPlaybackBlocked>()));
  });
  test('copy/dataspace/topology failures cannot fall back to SDR', () {
    for (final dependency in [
      HdrRouteDependency.hwdecMediacodecCopy,
      HdrRouteDependency.dataspacePq,
      HdrRouteDependency.topologyPlatformView
    ]) {
      expect(() => plan(excluded: {dependency: HdrDegradeReason.hwdecMismatch}),
          throwsA(isA<HdrPlaybackBlocked>()));
    }
  });
  test('modern noncopy route is outside experiment contract', () {
    const modern = HdrCapabilities(
        sdkInt: 29,
        displayHdrTypes: {2},
        hevcDecoders: [],
        dolbyVisionDecoders: [],
        p5PipelineAvailable: false,
        dataSpaceBridgeLoaded: true,
        dataSpaceExt: null);
    expect(
        () => plan(capabilities: modern), throwsA(isA<HdrPlaybackBlocked>()));
  });
}
