import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/src/hdr/hdr_capabilities.dart';
import 'package:media_kit_video/src/hdr/hdr_open_plan.dart';
import 'package:media_kit_video/src/hdr/hdr_output_slot.dart';
import 'package:media_kit_video/src/hdr/hdr_player_backend.dart';
import 'package:media_kit_video/src/hdr/hdr_route.dart';
import 'package:media_kit_video/src/hdr/hdr_source_descriptor.dart';
import 'package:media_kit_video/src/hdr/hdr_strategy.dart';
import 'package:media_kit_video/src/hdr/hdr_yuv_presentation_contract.dart';
import 'package:media_kit_video/src/video_controller/platform_video_controller.dart';
import 'package:media_kit_video/src/video_controller/video_controller.dart';
import 'package:synchronized/synchronized.dart';

/// A4 contract split, tightened by the P8.4 A5 V2 review fix: the YUV
/// window route's presentation quad (offscreen full-PQ / NV12 limited window
/// content / vendor-forced 0x11C60000 window label / (9,1,16) metadata
/// triplet) is fail-closed in the main library path, the YUV shape is judged
/// by the `surfacetexture` carrier (both `pq` and `pq-itu` requests enter
/// the contract — the vendor forces the same window label for either in
/// yuvDiag mode), the offscreen contract is issued as the owned mpv
/// output-levels write, and routes off the carrier keep their default
/// routing.
void main() {
  group('contract validation', () {
    test('accepted quad passes validation', () {
      // Must not throw.
      HdrYuvPresentationContract.validate(_yuvRoute());
      // The euv17 actual shape (the review counterexample carrier): plain
      // `pq` request on the surfacetexture carrier with the offscreen
      // contract the realizer now generates for it.
      HdrYuvPresentationContract.validate(
          _yuvRoute().surrogate(surfaceTransfer: 'pq'));
    });

    test('shapes outside the YUV carrier are out of scope', () {
      // Limited PQ label on the RGB mediacodec-copy carrier: no
      // SurfaceTexture intermediary, no separate offscreen contract.
      HdrYuvPresentationContract.validate(
          _yuvRoute().surrogate(hwdec: 'mediacodec-copy'));
      // Texture routes never carry the YUV shape.
      HdrYuvPresentationContract.validate(_yuvRoute()
          .surrogate(hwdec: 'mediacodec', vo: 'gpu-next', surfaceTransfer: 'x'));
      // Non-PQ window request on the carrier is not the YUV pairing.
      HdrYuvPresentationContract.validate(
          _yuvRoute().surrogate(surfaceTransfer: 'hlg', offscreenTransfer: null));
    });

    test('every quad member is fail-closed', () {
      final mutations = <String, HdrRoute Function()>{
        'offscreen-null': () => _yuvRoute().surrogate(offscreenTransfer: null),
        'offscreen-wrong': () =>
            _yuvRoute().surrogate(offscreenTransfer: 'pq-limited'),
        'vo': () => _yuvRoute().surrogate(vo: 'mediacodec_embed'),
        'topology': () => _yuvRoute().surrogate(topology: HdrTopology.texture),
        'prim': () => _yuvRoute().surrogate(targetPrim: 'bt.709'),
        'trc': () => _yuvRoute().surrogate(targetTrc: 'hlg'),
      };
      mutations.forEach((member, build) {
        expect(
          () => HdrYuvPresentationContract.validate(build()),
          throwsA(isA<StateError>().having(
              (error) => error.message,
              'message',
              contains('YUV presentation contract rejected'))),
          reason: 'quad member "$member" must be fail-closed',
        );
      });
    });

    test('pre-fix counterexample shape is now covered by the gate', () {
      // P8.4 A5 V2 review counterexample (euv17-contract): surfacetexture
      // carrier + requested `pq` + offscreen null — the actual YUV shape
      // presented through the vendor-forced 0x11C60000 window, which the
      // request-keyed gate used to let through without the quad.
      final counterexample =
          _yuvRoute().surrogate(surfaceTransfer: 'pq', offscreenTransfer: null);
      expect(HdrYuvPresentationContract.isYuvWindowRoute(counterexample), isTrue,
          reason: 'the carrier, not the requested label, decides the shape');
      expect(
        () => HdrYuvPresentationContract.validate(counterexample),
        throwsA(isA<StateError>().having((error) => error.message, 'message',
            contains('offscreen=null (need pq-full)'))),
      );
    });

    test('declared constants equal the accepted euv13/euv17 values', () {
      expect(HdrYuvPresentationContract.windowDataSpace, 0x11C60000);
      expect(HdrYuvPresentationContract.metadataPrimaries, 9);
      expect(HdrYuvPresentationContract.metadataRange, 1);
      expect(HdrYuvPresentationContract.metadataTransfer, 16);
      expect(HdrYuvPresentationContract.offscreenTransfer, 'pq-full');
      expect(HdrYuvPresentationContract.windowTransfer, 'pq-itu');
      expect(HdrYuvPresentationContract.windowRequests, ['pq', 'pq-itu']);
    });

    test('offscreen contract maps to the mpv output-levels value', () {
      expect(HdrYuvPresentationContract.mpvOutputLevels('pq-full'), 'full');
      expect(
        () => HdrYuvPresentationContract.mpvOutputLevels('pq-limited'),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('backend issuance', () {
    test('YUV route issues owned output levels and the window dataspace',
        () async {
      final result = await _exercise(_yuvRoute());
      expect(result.player.properties['video-output-levels'], 'full');
      expect(result.dataSpaceRequested, 'pq-itu');
      await result.backend.resetOwnedConfiguration();
      expect(result.player.properties['video-output-levels'], 'auto');
    });

    test('euv17 pq-request route issues the owned quad write', () async {
      // The review counterexample's actual euv17 pairing: surfacetexture
      // carrier + requested `pq`. With the realizer generating the offscreen
      // contract for this shape, validate passes and the owned
      // video-output-levels=full write is issued (it was skipped before the
      // fix).
      final result = await _exercise(
          _yuvRoute().surrogate(surfaceTransfer: 'pq'));
      expect(result.player.properties['video-output-levels'], 'full');
      expect(result.dataSpaceRequested, 'pq');
      await result.backend.resetOwnedConfiguration();
      expect(result.player.properties['video-output-levels'], 'auto');
    });

    test('YUV route without the offscreen contract is refused before writes',
        () async {
      final result = _harness();
      await expectLater(
        result.backend
            .prepareOutput(_plan(_yuvRoute().surrogate(offscreenTransfer: null))),
        throwsA(isA<StateError>()),
      );
      // Fail-closed happened before any owned write or controller creation.
      expect(result.player.properties['hwdec'], 'no');
      expect(result.player.properties.containsKey('video-output-levels'),
          isFalse);
    });

    test('routes off the YUV carrier issue no output levels',
        () async {
      final result = await _exercise(
          _yuvRoute().surrogate(hwdec: 'mediacodec-copy', surfaceTransfer: 'pq'));
      expect(result.player.properties.containsKey('video-output-levels'),
          isFalse);
      expect(result.dataSpaceRequested, 'pq');
    });
  });
}

HdrRoute _yuvRoute() => const HdrRoute(
      strategy: HdrStrategy.baseLayerConvert,
      presentation: HdrPresentation.nativeHdr,
      outputTransfer: HdrOutputTransfer.pq,
      appliesDynamicMetadata: false,
      topology: HdrTopology.platformView,
      vo: 'gpu-next',
      hwdec: 'surfacetexture',
      targetPrim: 'bt.2020',
      targetTrc: 'pq',
      surfaceTransfer: 'pq-itu',
      offscreenTransfer: 'pq-full',
      stripDvRpu: false,
    );

extension _RouteSurrogate on HdrRoute {
  /// Hand-rolled surrogate: keeps the fail-closed cases readable without a
  /// full copyWith on the immutable route value. [offscreenTransfer] has no
  /// fallback so a null argument explicitly resets the field.
  HdrRoute surrogate({
    String? hwdec,
    String? vo,
    HdrTopology? topology,
    String? surfaceTransfer,
    String? offscreenTransfer = 'pq-full',
    String? targetPrim,
    String? targetTrc,
  }) =>
      HdrRoute(
        strategy: strategy,
        presentation: presentation,
        outputTransfer: outputTransfer,
        appliesDynamicMetadata: appliesDynamicMetadata,
        topology: topology ?? this.topology,
        vo: vo ?? this.vo,
        hwdec: hwdec ?? this.hwdec,
        targetPrim: targetPrim ?? this.targetPrim,
        targetTrc: targetTrc ?? this.targetTrc,
        surfaceTransfer: surfaceTransfer ?? this.surfaceTransfer,
        offscreenTransfer: offscreenTransfer,
        stripDvRpu: stripDvRpu,
        dependencies: dependencies,
      );
}

HdrOpenPlan _plan(HdrRoute route) {
  const source = HdrSourceDescriptor(codec: 'hevc', transfer: 'hlg');
  final candidate = HdrCandidate(
    strategy: HdrStrategy.baseLayerConvert,
    maturity: HdrStrategyMaturity.verified,
    feasible: true,
    route: route,
  );
  return HdrOpenPlan(
    media: Media('test://source'),
    source: source,
    sourceOrigin: null,
    capabilities: const HdrCapabilities(
      sdkInt: 24,
      displayHdrTypes: {2, 3},
      hevcDecoders: [],
      dolbyVisionDecoders: [],
      p5PipelineAvailable: true,
      dataSpaceBridgeLoaded: true,
      dataSpaceExt: HdrDataSpaceExtInfo(id: 'lg-pq', applicable: true),
    ),
    prediction: HdrRoutePrediction(
      source: source,
      selected: candidate,
      candidates: [candidate],
      presentation: HdrPresentation.nativeHdr,
      confidence: HdrPredictionConfidence.verified,
      playable: true,
    ),
    route: route,
  );
}

class _Harness {
  _Harness(this.player);
  final _FakePlayer player;
  late final AndroidHdrBackend backend;
  String? dataSpaceRequested;
}

_Harness _harness() {
  final player = _FakePlayer();
  final harness = _Harness(player);
  harness.backend = AndroidHdrBackend(
    player: player,
    outputSlot: HdrOutputSlot<VideoController>(
      initial: null,
      voOf: (_) async => 'gpu-next',
      disposeForRebuild: (_) async {},
      create: (vo, hwdec, transfer) => _FakeOutput(),
      publish: (_) {},
      waitReady: (_) async {},
    ),
    applyDataSpace: (_, transfer) async {
      harness.dataSpaceRequested = transfer;
      // LG setter path: accepted without readback (the evidence-pinned
      // API24 extension), matching the device behavior this contract pins.
      return {'applied': true, 'path': 'ext:lg-pq', 'readback': null};
    },
  );
  return harness;
}

Future<_Harness> _exercise(HdrRoute route) async {
  final result = _harness();
  await result.backend.prepareOutput(_plan(route));
  await result.backend.configure(_plan(route));
  return result;
}

class _FakeOutput implements VideoController {
  @override
  final Completer<PlatformVideoController> platform =
      Completer<PlatformVideoController>()..complete(_FakePlatformOutput());
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePlatformOutput implements PlatformVideoController {
  @override
  Future<void> get waitUntilCurrentOutputBound async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePlayer implements Player {
  _FakePlayer() : properties = {'hwdec': 'no'};

  final Map<String, String> properties;
  final Lock _lock = Lock();
  final PlayerStream _stream = PlayerStream(
      Stream.empty(),
      Stream.empty(),
      Stream.empty(),
      Stream.empty(),
      Stream.empty(),
      Stream.empty(),
      Stream.empty(),
      Stream.empty(),
      Stream.empty(),
      Stream.empty(),
      Stream.empty(),
      Stream.empty(),
      Stream.empty(),
      Stream.empty(),
      Stream.empty(),
      Stream.empty(),
      Stream.empty(),
      Stream.empty(),
      Stream.empty(),
      Stream.empty(),
      Stream.empty(),
      Stream.empty(),
      Stream.empty(),
      Stream.empty(),
      Stream.empty(),
      Stream.empty());
  @override
  PlayerStream get stream => _stream;
  @override
  Lock get lock => _lock;
  @override
  int get fileLoadedEpoch => 0;
  @override
  Future<int> get handle async => 1;
  @override
  Future<String> getProperty(String name,
      {bool waitForInitialization = true}) async {
    // Non-empty baselines so the owned writes can capture and restore.
    return properties[name] ??
        (name == 'video-output-levels'
            ? 'auto'
            : name == 'cache-on-disk'
                ? 'yes'
                : name == 'egl-output-format'
                    ? 'rgb8'
                    : name == 'target-prim'
                        ? 'bt.709'
                        : name == 'target-trc'
                            ? 'sdr'
                            : name == 'target-colorspace-hint' ? 'no' : '');
  }

  @override
  Future<void> setPropertyStrict(String name, String value,
      {bool waitForInitialization = true}) async {
    properties[name] = value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
