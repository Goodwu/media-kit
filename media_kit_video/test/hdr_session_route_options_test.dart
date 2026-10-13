import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' show Media;
import 'package:media_kit_video/src/hdr/hdr_capabilities.dart';
import 'package:media_kit_video/src/hdr/hdr_open_plan.dart';
import 'package:media_kit_video/src/hdr/hdr_route.dart';
import 'package:media_kit_video/src/hdr/hdr_route_planner.dart';
import 'package:media_kit_video/src/hdr/hdr_video_session.dart';
import 'package:media_kit_video/src/routing/video_decoder_support.dart';
import 'package:media_kit_video/src/routing/video_route_options.dart';
import 'package:media_kit_video/src/routing/video_route_option_review.dart';
import 'package:media_kit_video/src/routing/video_source_spec.dart';
import 'package:media_kit_video/src/video_controller/platform_video_controller.dart';

import 'hdr_execution_catalog_test.dart' as catalog;

final spec = VideoSourceSpec(codec: 'hevc', width: 1920, height: 1080);
EffectiveVideoRouteOptions options(
        {VideoRouteSelection<VideoDecodeTarget>? decode,
        VideoRouteSelection<VideoOutputIntent>? output,
        VideoImportPreference? importer,
        VideoRouteFailurePolicy? failure}) =>
    EffectiveVideoRouteOptions.resolve(
        application: VideoRouteOptions(
            decode: decode,
            output: output,
            importPreference: importer,
            failurePolicy: failure));
HdrCapabilities capabilities(
        {VideoDecoderKind kind = VideoDecoderKind.hardware,
        VideoSupport support = VideoSupport.supported,
        String name = 'c2.hevc',
        bool hdr = true}) =>
    HdrCapabilities(
        sdkInt: 29,
        displayHdrTypes: hdr ? const {1, 2, 3} : const {},
        hevcDecoders: const [],
        dolbyVisionDecoders: const [],
        p5PipelineAvailable: true,
        dataSpaceBridgeLoaded: true,
        dataSpaceExt: null,
        sourceSupport: VideoSourceSupport(
            source: spec,
            censusComplete: true,
            decoders: [
              VideoDecoderSupport(
                  name: name,
                  mime: 'video/hevc',
                  kind: kind,
                  support: support,
                  reason: 'synthetic source census',
                  path: 'codec')
            ],
            reason: 'test'));

class Backend extends catalog.Backend {
  Backend([super.source = catalog.sdr]);
  final plans = <HdrOpenPlan>[];
  final starts = <Duration?>[];
  final plays = <bool>[];
  int stops = 0, resets = 0;
  bool stopFails = false;
  Completer<void>? stopHold;
  @override
  Future<void> configure(HdrOpenPlan plan) async {
    plans.add(plan);
    await super.configure(plan);
  }

  @override
  Future<void> open(HdrOpenPlan plan,
      {Duration? start, required bool play}) async {
    starts.add(start);
    plays.add(play);
    await super.open(plan, start: start, play: play);
  }

  @override
  Future<void> stop() async {
    stops++;
    await stopHold?.future;
    if (stopFails) throw StateError('stop debt');
    await super.stop();
  }

  @override
  Future<void> resetOwnedConfiguration() async {
    resets++;
  }
}

HdrVideoSession session(Backend b,
        {HdrCapabilities? caps,
        Future<HdrCapabilities> Function()? query,
        Future<void> Function()? outputDispose,
        Future<void> Function()? backendDispose}) =>
    HdrVideoSession.forTesting(
        backend: b,
        isAndroid: true,
        capabilitiesProvider: query ?? () async => caps ?? capabilities(),
        disposeOutputForTesting: outputDispose,
        disposeBackendForTesting: backendDispose);
final media = Media('test://config');
Future<void> open(HdrVideoSession s, Backend b, EffectiveVideoRouteOptions o) =>
    s.open(media, hint: b.source, sourceSpec: spec, options: o);

Future<void> blocked(Future<void> operation, HdrVideoSession session) async {
  // Existing Session contract publishes typed playback blocking in the report.
  await operation;
  expect(session.report.value.error, isA<HdrPlaybackBlocked>());
  expect(session.report.value.actual, isNull);
  expect(session.report.value.verified, isFalse);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final phase in ['fresh', 'pending', 'failed', 'accepted']) {
    for (final setter in ['options', 'preference', 'policy']) {
      test('LG single-open $phase rejects $setter before any mutation',
          () async {
        final b = Backend();
        final query = Completer<HdrCapabilities>();
        const initialPolicy = HdrRoutingPolicy();
        HdrRoutingPolicy? plannedPolicy;
        final s = HdrVideoSession.forTesting(
            backend: b,
            isAndroid: true,
            configuration: const VideoControllerConfiguration(
                android: AndroidVideoOptions(lgExperimentOwnerToken: 'guard')),
            policy: initialPolicy,
            capabilitiesProvider: () => query.future,
            routePlanner: (
                {required source,
                required capabilities,
                required policy,
                required preference,
                required excluded}) {
              plannedPolicy = policy;
              return HdrRoutePlanner.plan(
                  source: source,
                  capabilities: capabilities,
                  policy: policy,
                  preference: preference,
                  excluded: excluded);
            });
        Future<void>? pending;
        if (phase != 'fresh') {
          if (phase == 'failed') {
            for (final hwdec in ['mediacodec', 'mediacodec-copy', 'no']) {
              b.reviewErrors[hwdec] = StateError('first attempt failed');
            }
          }
          pending = s.open(media, hint: b.source, sourceSpec: spec);
          if (phase != 'pending') {
            query.complete(capabilities());
            if (phase == 'failed') {
              await expectLater(pending, throwsStateError);
              expect(s.report.value.error, isA<StateError>());
            } else {
              await pending;
            }
            expect(s.report.value.verified, phase == 'accepted');
          }
        }
        final priorReport = s.report.value;
        final stops = b.stops, resets = b.resets;
        final plans = List<HdrOpenPlan>.of(b.plans);
        final resources = List<String>.of(b.resources);
        final configured = List<HdrRoute>.of(b.configured);
        final opened = List<HdrRoute>.of(b.opened);
        final operation = setter == 'options'
            ? s.setOptions(options(
                decode: const VideoRouteSelection.require(
                    VideoDecodeTarget.software),
                output:
                    const VideoRouteSelection.require(VideoOutputIntent.sdr),
                importer: VideoImportPreference.preferCopy))
            : setter == 'preference'
                ? s.setPreference(HdrOutputPreference.off)
: s.setPolicy(const HdrRoutingPolicy(preferences: {}));
        await expectLater(operation, throwsStateError);
        expect(s.report.value, same(priorReport));
        expect(b.stops, stops);
        expect(b.resets, resets);
        expect(b.plans, plans);
        expect(b.resources, resources);
        expect(b.configured, configured);
        expect(b.opened, opened);
        if (phase == 'fresh' || phase == 'pending') {
          pending ??= s.open(media, hint: b.source, sourceSpec: spec);
          query.complete(capabilities());
          await pending;
          expect(s.report.value.verified, isTrue);
          expect(plannedPolicy!.preferences, initialPolicy.preferences);
          expect(b.plans.single.options!.decode.preference,
              VideoRoutePreference.auto);
          expect(b.plans.single.options!.output.preference,
              VideoRoutePreference.auto);
          expect(b.plans.single.options!.importPreference,
              VideoImportPreference.auto);
        }
        await expectLater(
            s.open(media, hint: b.source, sourceSpec: spec), throwsStateError);
        await s.dispose();
      });
    }
  }
  test('LG contradictory first options consume attempt before resolving',
      () async {
    final b = Backend();
    var queries = 0;
    final s = HdrVideoSession.forTesting(
        backend: b,
        isAndroid: true,
        preference: HdrOutputPreference.off,
        configuration: const VideoControllerConfiguration(
            android: AndroidVideoOptions(lgExperimentOwnerToken: 'conflict')),
        capabilitiesProvider: () async {
          queries++;
          return capabilities();
        });
    await expectLater(open(s, b, options()), throwsArgumentError);
    await expectLater(
        s.open(media, hint: b.source, sourceSpec: spec), throwsStateError);
    expect(queries, 0);
    expect(b.plans, isEmpty);
    expect(b.opened, isEmpty);
    expect(b.stops, 0);
    expect(s.report.value.generation, 0);
    await s.dispose();
  });
  test('same snapshot before query, retry, plan copy and report', () async {
    final query = Completer<HdrCapabilities>();
    final b = Backend()
      ..reviewErrors['mediacodec'] = StateError('import failed');
    final s = session(b, query: () => query.future);
    final o = options(importer: VideoImportPreference.preferDirect);
    final pending = open(s, b, o);
    query.complete(capabilities());
    await pending;
    expect(b.opened.map((r) => r.hwdec), ['mediacodec', 'mediacodec-copy']);
    expect(b.plans.every((p) => identical(p.options, o)), isTrue);
    expect(b.plans.first.copyWith().options, same(o));
    expect(s.report.value.options, same(o));
    expect(s.report.value.verified, isTrue);
    await s.dispose();
  });
  test('new public open and changed settings do not inherit old SDR reason',
      () async {
    final b = Backend(catalog.hdr10);
    final s = session(b);
    await open(
        s,
        b,
        options(
            output: const VideoRouteSelection.require(VideoOutputIntent.sdr)));
    expect(s.report.value.degradeReason, HdrDegradeReason.preferenceOff);
    await open(s, b, options());
    expect(s.report.value.actual!.outputTransfer, isNot(HdrOutputTransfer.sdr));
    expect(s.report.value.degradeReason, isNull);
    await s.setOptions(options(
        output: const VideoRouteSelection.require(VideoOutputIntent.sdr)));
    await s.setOptions(options());
    expect(s.report.value.degradeReason, isNull);
    await s.dispose();
  });

  test('public open does not inherit previous per-open import override',
      () async {
    final b = Backend();
    final s = session(b);
    await open(s, b, options(importer: VideoImportPreference.preferCopy));
    expect(b.opened.last.hwdec, 'mediacodec-copy');
    await s.open(media, hint: b.source, sourceSpec: spec);
    expect(b.opened.last.hwdec, 'mediacodec');
    expect(
        s.report.value.options!.importPreference, VideoImportPreference.auto);
    await s.dispose();
  });
  test(
      'require hardware actual source census positive',
      () async {
    final b = Backend();
    final s = session(b);
    final o = options(
        decode: const VideoRouteSelection.require(VideoDecodeTarget.hardware));
    await open(s, b, o);
    expect(s.report.value.optionFulfillment!.decode,
        VideoRouteOptionStatus.fulfilled);
    expect(s.report.value.options, same(o));
    await s.dispose();
  });
  for (final bad in [VideoDecoderKind.unknown, VideoDecoderKind.software]) {
    test('require hardware refuses actual codec census kind $bad', () async {
      final b = Backend();
      final s = session(b, caps: capabilities(kind: bad));
      final o = options(
          decode:
              const VideoRouteSelection.require(VideoDecodeTarget.hardware));
      await blocked(open(s, b, o), s);
      expect(s.report.value.options, same(o));
      expect(s.report.value.actual, isNull);
      expect(s.report.value.verified, isFalse);
      await s.dispose();
    });
  }
  test('require hardware different named codec is rejected at actual review',
      () async {
    final b = Backend();
    final s = session(b, caps: capabilities(name: 'other.codec'));
    await blocked(
        open(
            s,
            b,
            options(
                decode: const VideoRouteSelection.require(
                    VideoDecodeTarget.hardware))),
        s);
    expect(b.opened, hasLength(1));
    expect(s.report.value.actual, isNull);
    expect(s.report.value.optionFulfillment!.decode,
        VideoRouteOptionStatus.unknown);
    await s.dispose();
  });
  test(
      'require software configures no and verifies CPU without MC census grant',
      () async {
    final b = Backend();
    final s = session(b, caps: capabilities(support: VideoSupport.unsupported));
    await open(
        s,
        b,
        options(
            decode:
                const VideoRouteSelection.require(VideoDecodeTarget.software)));
    expect(b.opened.single.hwdec, 'no');
    expect(s.report.value.optionFulfillment!.decode,
        VideoRouteOptionStatus.fulfilled);
    await s.dispose();
  });
  for (final pixel in ['mediacodec', 'unknown']) {
    test('require software rejects resource $pixel', () async {
      final b = Backend()..pixelOverrides['no'] = pixel;
      final s = session(b);
      await blocked(
          open(
              s,
              b,
              options(
                  decode: const VideoRouteSelection.require(
                      VideoDecodeTarget.software))),
          s);
      expect(b.opened.single.hwdec, 'no');
      expect(s.report.value.actual, isNull);
      await s.dispose();
    });
  }
  test('prefer hardware can fulfill safe software after two MC attempts fail',
      () async {
    final b = Backend()
      ..reviewErrors['mediacodec'] = StateError('direct fail')
      ..reviewErrors['mediacodec-copy'] = StateError('copy fail');
    final s = session(b);
    await open(
        s,
        b,
        options(
            decode:
                const VideoRouteSelection.prefer(VideoDecodeTarget.hardware)));
    expect(
        b.opened.map((r) => r.hwdec), ['mediacodec', 'mediacodec-copy', 'no']);
    expect(s.report.value.actual!.hwdec, 'no');
    expect(s.report.value.optionFulfillment!.decode,
        VideoRouteOptionStatus.unfulfilled);
    await s.dispose();
  });
  test('stop fails first candidate with exact failed config report', () async {
    final b = Backend()
      ..reviewErrors['mediacodec'] = StateError('direct failed');
    final s = session(b);
    final o = options(failure: VideoRouteFailurePolicy.stop);
    await expectLater(open(s, b, o), throwsStateError);
    expect(b.opened, hasLength(1));
    expect(b.configured, hasLength(1));
    expect(s.report.value.options, same(o));
    expect(s.report.value.actual, isNull);
    await s.dispose();
  });
  test('require HDR unavailable blocks without SDR configure', () async {
    final b = Backend(catalog.hdr10);
    final s = session(b, caps: capabilities(hdr: false));
    await blocked(
        open(
            s,
            b,
            options(
                output:
                    const VideoRouteSelection.require(VideoOutputIntent.hdr))),
        s);
    expect(b.configured, isEmpty);
    expect(s.report.value.actual, isNull);
    await s.dispose();
  });
  test('require SDR tone maps HDR source and persists configured options',
      () async {
    final b = Backend(catalog.hdr10);
    final s = session(b);
    final o = options(
        output: const VideoRouteSelection.require(VideoOutputIntent.sdr));
    await s.setOptions(o);
    await s.open(media, hint: b.source, sourceSpec: spec);
    expect(b.opened.single.outputTransfer, HdrOutputTransfer.sdr);
    expect(s.report.value.options, same(o));
    expect(s.report.value.optionFulfillment!.output,
        VideoRouteOptionStatus.fulfilled);
    await s.dispose();
  });
  test(
      'hardware playback settings switch actually configures and verifies software',
      () async {
    final b = Backend();
    final s = session(b);
    await open(s, b, options());
    final o = options(
        decode: const VideoRouteSelection.require(VideoDecodeTarget.software));
    await s.setOptions(o);
    expect(b.opened.map((r) => r.hwdec), ['mediacodec', 'no']);
    expect(s.report.value.error, isNull);
    expect(s.report.value.verified, isTrue);
    expect(s.report.value.optionFulfillment!.decode,
        VideoRouteOptionStatus.fulfilled);
    expect(s.report.value.options, same(o));
    await s.dispose();
  });
  test(
      'same route stronger require triggers real fresh review and fails unknown kind',
      () async {
    final b = Backend();
    final s = session(b, caps: capabilities(kind: VideoDecoderKind.unknown));
    await open(s, b, options());
    final old = b.opened.single;
    final o = options(
        decode: const VideoRouteSelection.require(VideoDecodeTarget.hardware));
    await blocked(s.setOptions(o), s);
    expect(b.opened, hasLength(2));
    expect(b.opened.last, old);
    expect(b.reviewed, hasLength(2));
    expect(s.report.value.options, same(o));
    expect(s.report.value.actual, isNull);
    await s.dispose();
  });
  test(
      'unfulfillable setOptions stops old output and emits new failed generation',
      () async {
    final b = Backend();
    final s = session(b);
    await open(s, b, options());
    final generation = s.report.value.generation, stops = b.stops;
    final o = options(
        output: const VideoRouteSelection.require(VideoOutputIntent.hdr));
    await blocked(s.setOptions(o), s);
    expect(b.stops, greaterThan(stops));
    expect(b.resets, greaterThan(0));
    expect(b.opened, hasLength(1));
    expect(s.report.value.generation, greaterThan(generation));
    expect(s.report.value.options, same(o));
    expect(s.report.value.actual, isNull);
    await s.dispose();
  });
  test('capability loss keeps exact required snapshot and cleans old output',
      () async {
    final b = Backend();
    final s = session(b);
    final o = options(
        decode: const VideoRouteSelection.require(VideoDecodeTarget.hardware));
    await open(s, b, o);
    final stops = b.stops;
    await blocked(
        s.handleCapabilitiesChanged(
            capabilities(kind: VideoDecoderKind.software)),
        s);
    expect(b.stops, greaterThan(stops));
    expect(s.report.value.actual, isNull);
    expect(s.report.value.options, same(o));
    await s.dispose();
  });
  for (final phase in ['slot', 'backend']) {
    test(
        'dispose $phase debt retains report and shared future then retry succeeds',
        () async {
      final b = Backend();
      var outputCalls = 0, backendCalls = 0;
      final gate = Completer<void>();
      var fails = true;
      final s = session(b, outputDispose: () async {
        outputCalls++;
        await gate.future;
        if (phase == 'slot' && fails) throw StateError('slot debt');
      }, backendDispose: () async {
        backendCalls++;
        if (phase == 'backend' && fails) throw StateError('backend debt');
      });
      await open(s, b, options());
      final a = s.dispose(), other = s.dispose();
      expect(other, same(a));
      gate.complete();
      await expectLater(a, throwsA(isA<HdrSessionDisposalFailure>()));
      expect(s.lastDisposeReport!.clean, isFalse);
      expect(outputCalls, 1);
      expect(backendCalls, phase == 'slot' ? 0 : 1);
      expect(s.lastDisposeReport!.slotError,
          phase == 'slot' ? isA<StateError>() : isNull);
      expect(s.lastDisposeReport!.backendError,
          phase == 'backend' ? isA<StateError>() : isNull);
      await expectLater(open(s, b, options()), throwsStateError);
      fails = false;
      await s.dispose();
      expect(s.lastDisposeReport!.clean, isTrue);
      expect(outputCalls, 2);
      expect(backendCalls, phase == 'slot' ? 1 : 2);
      await s.dispose();
      expect(outputCalls, 2);
    });
  }
  test(
      'rejected settings cleanup cannot overwrite successor report',
      () async {
    final b = Backend();
    final s = session(b);
    await open(s, b, options());
    final oldStops = b.stops;
    b.stopHold = Completer<void>();
    final rejected = options(
        output: const VideoRouteSelection.require(VideoOutputIntent.hdr));
    final failed = s.setOptions(rejected);
    while (b.stops == oldStops) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(s.report.value.options, same(rejected));
    expect(s.report.value.actual, isNull);
    final successor = options(
        importer: VideoImportPreference.preferCopy);
    final newest = open(s, b, successor);
    b.stopHold!.complete();
    await failed;
    await newest;
    expect(s.report.value.options, same(successor));
    expect(s.report.value.verified, isTrue);
    expect(s.report.value.error, isNull);
    expect(s.report.value.actual!.hwdec, 'mediacodec-copy');
    await s.dispose();
  });
  test(
      'failed required-config cleanup debt prevents any new open until actual clean retry',
      () async {
    final b = Backend();
    final s = session(b);
    await open(s, b, options());
    b.stopFails = true;
    await expectLater(
        s.setOptions(options(
            output: const VideoRouteSelection.require(VideoOutputIntent.hdr))),
        throwsStateError);
    expect(s.report.value.actual, isNull);
    expect(s.report.value.diagnostic, contains('cleanup failed'));
    final before = b.configured.length;
    await expectLater(open(s, b, options()), throwsStateError);
    expect(b.configured, hasLength(before));
    b.stopFails = false;
    await open(s, b, options());
    expect(s.report.value.verified, isTrue);
    expect(b.opened, hasLength(2));
    await s.dispose();
  });

  test('coordinator dispose debt prevents slot/backend until a real retry',
      () async {
    final b = Backend();
    var outputCalls = 0, backendCalls = 0;
    final s = session(b, outputDispose: () async {
      outputCalls++;
    }, backendDispose: () async {
      backendCalls++;
    });
    await open(s, b, options());
    b.stopFails = true;
    await expectLater(s.dispose(), throwsA(isA<HdrSessionDisposalFailure>()));
    expect(outputCalls, 0);
    expect(backendCalls, 0);
    expect(s.lastDisposeReport!.clean, isFalse);
    b.stopFails = false;
    await s.dispose();
    expect(outputCalls, 1);
    expect(backendCalls, 1);
    expect(s.lastDisposeReport!.clean, isTrue);
  });
  test(
      'settings supersede the first pending query and await new transaction',
      () async {
    final q = Completer<HdrCapabilities>();
    final b = Backend();
    final s = session(b, query: () => q.future);
    final initial = open(s, b, options());
    final required = options(
        decode: const VideoRouteSelection.require(VideoDecodeTarget.software));
    var settingDone = false;
    final setting = s.setOptions(required)
      ..then((_) {
        settingDone = true;
      });
    await Future<void>.delayed(Duration.zero);
    final returnedEarly = settingDone;
    q.complete(capabilities());
    await initial;
    await setting;
    expect(returnedEarly, isFalse);
    expect(s.report.value.options, same(required));
    expect(b.opened.map((r) => r.hwdec), ['no']);
    expect(s.report.value.verified, isTrue);
    await s.dispose();
  });
  test(
      'settings during source B query use atomic B intent after source A',
      () async {
    final q = Completer<HdrCapabilities>();
    var reads = 0;
    final b = Backend();
    final s = session(b,
        query: () => ++reads == 1 ? Future.value(capabilities()) : q.future);
    await open(s, b, options());
    final second = Media('test://source-B');
    final secondSpec =
        VideoSourceSpec(codec: 'hevc', width: 3840, height: 2160);
    final pending = s.open(second,
        hint: b.source,
        sourceSpec: secondSpec,
        options: options(),
        start: const Duration(seconds: 37),
        play: false);
    final required = options(
        decode: const VideoRouteSelection.require(VideoDecodeTarget.software));
    final setting = s.setOptions(required);
    q.complete(capabilities());
    await pending;
    await setting;
    expect(b.plans.last.media.uri, second.uri);
    expect(b.plans.last.sourceSpec, same(secondSpec));
    expect(b.starts.last, const Duration(seconds: 37));
    expect(b.plays.last, isFalse);
    expect(b.opened.map((r) => r.hwdec), ['mediacodec', 'no']);
    expect(s.report.value.options, same(required));
    expect(s.report.value.verified, isTrue);
    await s.dispose();
  });
  test(
      'settings during B review cannot pair A media with B source',
      () async {
    final b = Backend();
    final s = session(b);
    await open(s, b, options());
    final hold = Completer<void>();
    b.reviewHold = hold.future;
    final second = Media('test://source-B-review');
    final secondSpec =
        VideoSourceSpec(codec: 'hevc', width: 3840, height: 2160);
    final pending = s.open(second,
        hint: b.source,
        sourceSpec: secondSpec,
        options: options());
    while (b.reviewed.length < 2) {
      await Future<void>.delayed(Duration.zero);
    }
    final required = options(
        decode: const VideoRouteSelection.require(VideoDecodeTarget.software));
    final setting = s.setOptions(required);
    hold.complete();
    await pending;
    await setting;
    expect(b.plans.last.media.uri, second.uri);
    expect(b.plans.last.sourceSpec, same(secondSpec));
    expect(b.opened.last.hwdec, 'no');
    expect(s.report.value.options, same(required));
    await s.dispose();
  });
  test(
      'same route fresh census removes actual HW decoder and stops verified output',
      () async {
    final b = Backend();
    final s = session(b);
    final required = options(
        decode: const VideoRouteSelection.require(VideoDecodeTarget.hardware));
    await open(s, b, required);
    final reviews = b.reviewed.length;
    await s.handleCapabilitiesChanged(
        capabilities(name: 'another.hardware.decoder'));
    expect(b.reviewed.length, greaterThan(reviews));
    expect(s.report.value.verified, isFalse);
    expect(s.report.value.actual, isNull);
    expect(s.report.value.options, same(required));
    expect(s.report.value.error, isA<HdrPlaybackBlocked>());
    await s.dispose();
  });

  test(
      'fresh same decoder census actually re-reviews HW without inventing degradation',
      () async {
    final b = Backend();
    final s = session(b);
    final required = options(
        decode: const VideoRouteSelection.require(VideoDecodeTarget.hardware));
    await open(s, b, required);
    final reviews = b.reviewed.length;
    await s.handleCapabilitiesChanged(capabilities());
    expect(b.reviewed.length, reviews + 1);
    expect(s.report.value.verified, isTrue);
    expect(s.report.value.options, same(required));
    expect(s.report.value.degradeReason, isNull);
    await s.dispose();
  });
  test(
      'rapid settings preserve only latest pending snapshot without MC side effects',
      () async {
    final q = Completer<HdrCapabilities>();
    final b = Backend();
    final s = session(b, query: () => q.future);
    final initial = open(s, b, options());
    final changed =
        s.setOptions(options(importer: VideoImportPreference.preferCopy));
    final latest = options(
        decode: const VideoRouteSelection.require(VideoDecodeTarget.software));
    final finalChange = s.setOptions(latest);
    q.complete(capabilities());
    await initial;
    await changed;
    await finalChange;
    expect(b.opened.map((r) => r.hwdec), ['no']);
    expect(s.report.value.options, same(latest));
    await s.dispose();
  });
  test(
      'unfulfillable settings during first query invalidate old playable request',
      () async {
    final q = Completer<HdrCapabilities>();
    final b = Backend();
    final s = session(b, query: () => q.future);
    final initial = open(s, b, options());
    final required = options(
        output: const VideoRouteSelection.require(VideoOutputIntent.hdr));
    final changed = s.setOptions(required);
    q.complete(capabilities());
    await initial;
    await changed;
    expect(b.configured, isEmpty);
    expect(s.report.value.options, same(required));
    expect(s.report.value.verified, isFalse);
    expect(s.report.value.actual, isNull);
    expect(s.report.value.error, isA<HdrPlaybackBlocked>());
    await s.dispose();
  });

  test(
      'public refresh keeps pending software settings authoritative',
      () async {
    var reads = 0;
    final query = Completer<HdrCapabilities>();
    final b = Backend();
    final s = session(b,
        query: () =>
            ++reads == 2 ? query.future : Future.value(capabilities()));
    final hardware = options(
        decode: const VideoRouteSelection.require(VideoDecodeTarget.hardware));
    final software = options(
        decode: const VideoRouteSelection.require(VideoDecodeTarget.software));
    await open(s, b, hardware);
    final changing = s.setOptions(software);
    await s.refreshCapabilities();
    query.complete(capabilities());
    await changing;
    expect(b.opened.map((route) => route.hwdec), ['mediacodec', 'no']);
    expect(s.report.value.options, same(software));
    expect(s.report.value.actual!.hwdec, 'no');
    expect(s.report.value.optionFulfillment!.decode,
        VideoRouteOptionStatus.fulfilled);
    expect(s.report.value.verified, isTrue);
    await s.dispose();
  });
  test(
      'public refresh uses pending source B settings start and play',
      () async {
    final query = Completer<HdrCapabilities>();
    var reads = 0;
    final b = Backend();
    final s = session(b,
        query: () => ++reads == 2 || reads == 3
            ? query.future
            : Future.value(capabilities()));
    await open(s, b, options());
    final second = Media('test://source-B-refresh');
    final secondSpec =
        VideoSourceSpec(codec: 'hevc', width: 3840, height: 2160);
    final pending = s.open(second,
        hint: b.source,
        sourceSpec: secondSpec,
        options: options(),
        start: const Duration(seconds: 41),
        play: false);
    final software = options(
        decode: const VideoRouteSelection.require(VideoDecodeTarget.software));
    final changing = s.setOptions(software);
    await s.refreshCapabilities();
    query.complete(capabilities());
    await Future.wait([pending, changing]);
    expect(b.opened.map((route) => route.hwdec), ['mediacodec', 'no']);
    expect(b.plans.last.media.uri, second.uri);
    expect(b.plans.last.sourceSpec, same(secondSpec));
    expect(b.plans.last.options, same(software));
    expect(b.starts.last, const Duration(seconds: 41));
    expect(b.plays.last, isFalse);
    expect(s.report.value.options, same(software));
    expect(s.report.value.verified, isTrue);
    await s.dispose();
  });
  test(
      'public refresh during source B review applies fresh census to B',
      () async {
    var reads = 0;
    final b = Backend();
    final s = session(b,
        query: () async => ++reads == 3
            ? capabilities(name: 'another.hardware.decoder')
            : capabilities());
    final hardware = options(
        decode: const VideoRouteSelection.require(VideoDecodeTarget.hardware));
    await open(s, b, hardware);
    final hold = Completer<void>();
    b.reviewHold = hold.future;
    final second = Media('test://source-B-refresh-review');
    final pending =
        s.open(second, hint: b.source, sourceSpec: spec, options: hardware);
    while (b.reviewed.length < 2) {
      await Future<void>.delayed(Duration.zero);
    }
    final refreshing = s.refreshCapabilities();
    await Future<void>.delayed(Duration.zero);
    hold.complete();
    await Future.wait([pending, refreshing]);
    expect(b.plans.last.media.uri, second.uri);
    expect(b.plans.last.sourceSpec, same(spec));
    expect(b.reviewed, hasLength(3));
    expect(s.report.value.options, same(hardware));
    expect(s.report.value.verified, isFalse);
    expect(s.report.value.actual, isNull);
    expect(s.report.value.error, isA<HdrPlaybackBlocked>());
    await s.dispose();
  });
  test(
      'older public refresh cannot replace newly completed source settings',
      () async {
    var reads = 0;
    final query = Completer<HdrCapabilities>();
    final b = Backend();
    final s = session(b,
        query: () =>
            ++reads == 2 ? query.future : Future.value(capabilities()));
    final hardware = options(
        decode: const VideoRouteSelection.require(VideoDecodeTarget.hardware));
    await open(s, b, hardware);
    final refreshing = s.refreshCapabilities();
    final second = Media('test://source-B-refresh-stale');
    final software = options(
        decode: const VideoRouteSelection.require(VideoDecodeTarget.software));
    await s.open(second, hint: b.source, sourceSpec: spec, options: software);
    query.complete(capabilities(name: 'another.hardware.decoder'));
    await refreshing;
    expect(b.opened.map((route) => route.hwdec), ['mediacodec', 'no']);
    expect(b.plans.last.media.uri, second.uri);
    expect(s.report.value.options, same(software));
    expect(s.report.value.verified, isTrue);
    await s.dispose();
  });

  test('nonAndroid unavailable reviewer fails explicit require without opening',
      () async {
    final s = HdrVideoSession.forTesting(isAndroid: false);
    final o = options(
        decode: const VideoRouteSelection.require(VideoDecodeTarget.hardware));
    await s.open(media, hint: catalog.sdr, options: o);
    expect(s.report.value.options, same(o));
    expect(s.report.value.actual, isNull);
    expect(s.report.value.error, isA<HdrPlaybackBlocked>());
    expect(s.report.value.degradeReason, HdrDegradeReason.unsupportedPlatform);
    await s.dispose();
    await expectLater(s.open(media), throwsStateError);
  });

  test('effective options pass through unchanged, off conflict still rejected',
      () {
    final o = options();
    // Without any legacy field left, effective options are returned as-is.
    expect(() => resolveHdrRouteOptions(options: o), returnsNormally);
    expect(resolveHdrRouteOptions(options: o), same(o));
    // A legacy HDR-off request contradicting the effective output options is
    // an explicit contradiction that cannot be ignored.
    expect(
        () => resolveHdrRouteOptions(
            options: o, preference: HdrOutputPreference.off),
        throwsArgumentError);
  });
}
