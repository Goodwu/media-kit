import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' show Media;
import 'package:media_kit_video/media_kit_video.dart';

import 'hdr_video_session_test.dart' show FakeBackend;
import 'hdr_execution_catalog_test.dart' show Backend;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.alexmercerind/media_kit_video');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final small = VideoSourceSpec(
    codec: 'hvc1.2.4.L153.B0',
    width: 3840,
    height: 2160,
    frameRate: 30,
  );
  final large = VideoSourceSpec(
    codec: 'hvc1.2.4.L153.B0',
    width: 3840,
    height: 2160,
    frameRate: 60,
  );
  const hdr10 = HdrSourceDescriptor(
    codec: 'hevc',
    transfer: 'pq',
    primaries: 'bt.2020',
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

  Map<String, Object?> response(
    List<VideoSourceSpec> specs, {
    String codecSupport = 'supported',
    String nativeSupport = 'unsupported',
    List<int> hdrTypes = const [1, 2, 3],
    bool incomplete = false,
  }) => {
    'schema': 1,
    'platform': 'android',
    'display': {
      'status': 'resolved',
      'platform': 'android',
      'displayId': 7,
      'modeId': 2,
      'revision': '7:2',
      'hdrTypes': hdrTypes,
    },
    'hdr': {
      'sdkInt': 34,
      'p5Pipeline': true,
      'dataSpaceBridgeLoaded': true,
      'nativeDvBridgeApi': 1,
      'hevcDecoders': [],
      'dolbyVisionDecoders': [
        {
          'name': 'vendor.dv',
          'mimeType': 'video/dolby-vision',
          'hardwareAcceleration': true,
          'profiles': [256],
        },
      ],
    },
    'sources': [
      for (final s in specs)
        {
          'key': s.key,
          'censusComplete': !incomplete,
          'reason': 'test',
          'decoders': [
            {
              'name': 'vendor.hevc',
              'mime': 'video/hevc',
              'kind': 'hardware',
              'support': codecSupport,
              'reason': 'test',
              'path': 'codec',
            },
            {
              'name': 'vendor.dv',
              'mime': 'video/dolby-vision',
              'kind': 'hardware',
              'support': nativeSupport,
              'reason': 'test',
              'path': 'nativeDv',
            },
          ],
        },
    ],
  };
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('exact MC negative blocks MC safety fallback but FFmpeg remains conditional', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => response([large], codecSupport: 'unsupported'),
    );
    final caps = await VideoRouteCapabilities.query(sources: [large]);
    for (final enabled in [false, true]) {
      final prediction = caps.predict(
        hdr10,
        specification: large,
        policy: HdrRoutingPolicy(allowExperimental: enabled),
      );
      // The exact MC negative excludes every MediaCodec carrier...
      expect(prediction.playable, isFalse);
      final decodeBlocked = prediction.candidates
          .where((c) => c.skipReason == HdrDegradeReason.sourceDecodeUnsupported)
          .toList();
      expect(decodeBlocked, isNotEmpty);
      expect(
          decodeBlocked.every((c) => c.route == null || c.route!.hwdec != 'no'),
          isTrue);
      // ...without poisoning the software (FFmpeg) request: on this
      // HDR-capable display its tone-map execution is gated by the display
      // transfer, not by the MC negative. FFmpeg stays conditional on its
      // own admission instead of being blanket-blocked or auto-selected.
      expect(
          prediction.candidates
              .where((c) => c.skipReason == HdrDegradeReason.displayLacksTransfer),
          isNotEmpty);
      expect(caps.forSource(large).support(), VideoSupport.unsupported);
    }
  });

  test('one source resolution/rate cannot authorize another', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => response([small]),
    );
    final caps = await VideoRouteCapabilities.query(sources: [small]);
    expect(caps.predict(hdr10, specification: small).playable, isTrue);
    final unknown = caps.predict(hdr10, specification: large);
    expect(unknown.confidence, HdrPredictionConfidence.unverified);
    expect(caps.forSource(large).support(), VideoSupport.unknown);
  });

  test(
    'supported decoding without HDR display retains correct SDR conversion',
    () async {
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => response([small], hdrTypes: []),
      );
      final caps = await VideoRouteCapabilities.query(sources: [small]);
      final prediction = caps.predict(hdr10, specification: small);
      expect(prediction.playable, isTrue);
      expect(prediction.presentation, HdrPresentation.toneMappedSdr);
    },
  );

  test(
    'native DV support cannot authorize the base decoder or vice versa',
    () async {
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => response(
          [small],
          codecSupport: 'unsupported',
          nativeSupport: 'supported',
        ),
      );
      var caps = await VideoRouteCapabilities.query(sources: [small]);
      expect(
        caps.predict(p84, specification: small).selected.strategy,
        HdrStrategy.nativeDolbyVision,
      );
      final off = caps.predict(p84, specification: small, preference: HdrOutputPreference.off);
      expect(off.playable, isTrue);
      expect(off.selected.route!.hwdec, 'no');
      expect(off.selected.route!.stripDvRpu, isTrue);
      expect(off.confidence, HdrPredictionConfidence.unverified);
      expect(off.candidates.where((c) => c.feasible).every((c) => c.route!.hwdec == 'no'), isTrue);
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => response([small]),
      );
      caps = await VideoRouteCapabilities.query(sources: [small]);
      expect(
        caps.predict(p84, specification: small).selected.strategy,
        HdrStrategy.baseLayerDirect,
      );
    },
  );

  test(
    'incomplete census stays conditional rather than a hardware rejection',
    () async {
      messenger.setMockMethodCallHandler(
        channel,
        (call) async =>
            response([small], codecSupport: 'unsupported', incomplete: true),
      );
      final caps = await VideoRouteCapabilities.query(sources: [small]);
      expect(
        caps.predict(hdr10, specification: small).confidence,
        HdrPredictionConfidence.unverified,
      );
    },
  );

  test(
    'production Session query carries target and source without Player',
    () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (call.method != 'VideoRouteCapabilities.Get') return null;
        return response([small]);
      });
      final backend = FakeBackend();
      final session = HdrVideoSession.forTesting(
        isAndroid: true,
        backend: backend,
        target: VideoOutputTarget.nativeDisplay(
          platform: 'android',
          displayId: 7,
        ),
      );
      addTearDown(session.dispose);
      await session.open(Media('test://small'), hint: hdr10, sourceSpec: small);
      final query = calls
          .where((c) => c.method == 'VideoRouteCapabilities.Get')
          .single;
      expect((query.arguments as Map)['target'], {
        'kind': 'nativeDisplay',
        'platform': 'android',
        'displayId': 7,
      });
      expect((query.arguments as Map)['sources'], [small.toMap()]);
      expect((query.arguments as Map).containsKey('player'), isFalse);
      expect(backend.opened, hasLength(1));
      expect(
        backend.preparedPlans.single.capabilities.sourceSupport!.source,
        small,
      );
    },
  );

  test('MC negative Session only admits FFmpeg on an SDR-only display and cannot verify before current review', () async {
    // SDR output for the HDR source is only authorized by a confirmed
    // SDR-only display; the exact MC negative then leaves FFmpeg ('no') as
    // the single admissible execution, unverified until the decoder review.
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => call.method == 'VideoRouteCapabilities.Get'
          ? response([large], codecSupport: 'unsupported', hdrTypes: const [])
          : null,
    );
    final release = Completer<void>();
    final backend = Backend(hdr10)..reviewHold = release.future;
    final session = HdrVideoSession.forTesting(isAndroid: true, backend: backend);
    addTearDown(session.dispose);
    final open = session.open(Media('test://large'), hint: hdr10, sourceSpec: large);
    await pumpEventQueue();
    expect(backend.opened.map((r) => r.hwdec), ['no']);
    expect(backend.configured.map((r) => r.hwdec), ['no']);
    expect(session.report.value.verified, isFalse);
    release.complete();
    await open;
    expect(session.report.value.verified, isTrue);
    expect(session.report.value.actual!.hwdec, 'no');
    expect(session.report.value.decoderObservation!.softwareDecoded, isTrue);
    expect(session.report.value.decoderObservation!.cpuFrame, isTrue);
    expect(session.report.value.prediction!.confidence, HdrPredictionConfidence.unverified);
  });

  test('MC negative cannot accept observed hardware or unknown CPU format as FFmpeg on an SDR-only display', () async {
    messenger.setMockMethodCallHandler(channel, (call) async =>
      call.method == 'VideoRouteCapabilities.Get' ? response([large], codecSupport: 'unsupported', hdrTypes: const []) : null);
    for (final hardware in [true, false]) {
      final backend = Backend(hdr10);
      if (hardware) { backend.hwdecOverrides['no'] = 'mediacodec'; }
      else { backend.pixelOverrides['no'] = 'unknown-format'; }
      final session = HdrVideoSession.forTesting(isAndroid: true, backend: backend);
      await session.open(Media('test://large'), hint: hdr10, sourceSpec: large);
      expect(backend.configured.map((r) => r.hwdec), ['no']);
      expect(session.report.value.verified, isFalse);
      expect(session.report.value.actual, isNull);
      await session.dispose();
    }
  });

  test('late source query cannot replace newer source support', () async {
    final started = Completer<void>();
    final release = Completer<Map<String, Object?>>();
    var queries = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method != 'VideoRouteCapabilities.Get') return null;
      if (++queries == 1) {
        started.complete();
        return release.future;
      }
      return response([small]);
    });
    final backend = FakeBackend();
    final session = HdrVideoSession.forTesting(
      isAndroid: true,
      backend: backend,
    );
    addTearDown(session.dispose);
    final old = session.open(
      Media('test://old'),
      hint: hdr10,
      sourceSpec: large,
    );
    await started.future;
    await session.open(Media('test://new'), hint: hdr10, sourceSpec: small);
    release.complete(response([large], codecSupport: 'unsupported'));
    await old;
    expect(backend.opened, hasLength(1));
    expect(
      backend.preparedPlans.single.capabilities.sourceSupport!.source,
      small,
    );
    expect(session.report.value.error, isNull);
  });

  test(
    'policy reopen and refresh query keep exact source specification',
    () async {
      final specs = <Object?>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method != 'VideoRouteCapabilities.Get') return null;
        specs.add((call.arguments as Map)['sources']);
        return response([small]);
      });
      final backend = FakeBackend();
      final session = HdrVideoSession.forTesting(
        isAndroid: true,
        backend: backend,
      );
      addTearDown(session.dispose);
      await session.open(Media('test://small'), hint: hdr10, sourceSpec: small);
      await session.setPreference(HdrOutputPreference.off);
      await session.refreshCapabilities();
      expect(specs.length, greaterThanOrEqualTo(2));
      for (final s in specs) {
        expect(s, [small.toMap()]);
      }
    },
  );
}
