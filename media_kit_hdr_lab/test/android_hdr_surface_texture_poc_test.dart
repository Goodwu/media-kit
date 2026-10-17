// ignore_for_file: implementation_imports
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:media_kit_hdr_lab/common/android_surface_texture_experiment.dart';

/// W1/W2 (plan lg-p84-yuv-window-reopen-20261014): the
/// MEDIA_KIT_ANDROID_SURFACETEXTURE_POC define and the production realizer's
/// hwdec override are gone. The `surfacetexture` carrier is derived from the
/// vendor-declared PQ presentation channels (a yuv-only declaration), and the
/// independent lab experiment validator admits exactly that carrier — the
/// legacy copy validator is never relaxed and no copy/SDR route can fall
/// back into the experiment. The sticky post-open version-evidence verdict
/// lives in the 01 page's open transaction (inlined from the deleted
/// AndroidSurfaceTexturePoc helpers, semantics unchanged).
void main() {
  const transfer = String.fromEnvironment(
      'MEDIA_KIT_ANDROID_CONVERT_SURFACE_TRANSFER',
      defaultValue: 'pq');
  const experiment = AndroidSurfaceTextureExperiment(
      transfer, transfer == 'pq' ? 'full' : 'limited');

  // W1 carrier declaration: the LG-class device reports the YUV window as
  // its only PQ presentation channel, so the baseLayerConvert carrier is
  // `surfacetexture` without any define.
  const yuvOnlyCaps = HdrCapabilities(
      sdkInt: 24,
      displayHdrTypes: {2},
      hevcDecoders: [],
      dolbyVisionDecoders: [],
      p5PipelineAvailable: false,
      dataSpaceBridgeLoaded: false,
      dataSpaceExt: HdrDataSpaceExtInfo(
          id: 'lg-pq',
          applicable: true,
          pqPresentation: HdrPqPresentation(rgbSurface: false, yuvWindow: true)));
  // Device-equivalent capability snapshot of the OES diagnostic round: the
  // LG reports both DOLBY_VISION(1) and HDR10(2), the lg-pq dataspace
  // extension is applicable and declares the same yuv-only channels.
  const deviceCaps = HdrCapabilities(
      sdkInt: 24,
      displayHdrTypes: {1, 2},
      hevcDecoders: [],
      dolbyVisionDecoders: [],
      p5PipelineAvailable: false,
      dataSpaceBridgeLoaded: false,
      dataSpaceExt: HdrDataSpaceExtInfo(
          id: 'lg-pq',
          applicable: true,
          pqPresentation: HdrPqPresentation(rgbSurface: false, yuvWindow: true)));
  // Migration default: an applicable extension without a pqPresentation
  // structure resolves to the RGB baseline, so the carrier stays the
  // platform copy route — and the validator fail-closes on it. No define
  // can reopen the carrier anymore.
  const legacyCaps = HdrCapabilities(
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
  HdrRoutePrediction plan({
    HdrSourceDescriptor input = source,
    Map<String, HdrDegradeReason> excluded = const {},
    HdrCapabilities capabilities = yuvOnlyCaps,
    HdrOutputPreference preference = HdrOutputPreference.auto,
  }) =>
      experiment.plan(
          source: input,
          capabilities: capabilities,
          policy: HdrRoutingPolicy.defaults,
          preference: preference,
          excluded: excluded);

  test('W1 carrier derivation: a yuv-only declaration routes surfacetexture, '
      'the migration default keeps the copy baseline', () {
    final HdrRoute yuvCarrier = HdrStrategyRealizer.realize(
      HdrStrategy.baseLayerConvert,
      source: source,
      sourceClass: HdrSourceClass.dvP84,
      capabilities: yuvOnlyCaps,
    ).route!;
    expect(yuvCarrier.hwdec, 'surfacetexture');
    expect(yuvCarrier.dependencies,
        contains(HdrRouteDependency.hwdecSurfaceTexture));
    expect(yuvCarrier.offscreenTransfer, 'pq-full',
        reason: 'the YUV carrier presents the actual YUV shape; the offscreen '
            'contract is required for the pq request too');
    // The migration-default RGB baseline is unchanged: the copy carrier
    // carries the copy dependency and no surfacetexture dependency.
    final HdrRoute copyCarrier = HdrStrategyRealizer.realize(
      HdrStrategy.baseLayerConvert,
      source: source,
      sourceClass: HdrSourceClass.dvP84,
      capabilities: legacyCaps,
    ).route!;
    expect(copyCarrier.hwdec, 'mediacodec-copy');
    expect(copyCarrier.dependencies,
        contains(HdrRouteDependency.hwdecMediacodecCopy));
    expect(copyCarrier.dependencies,
        isNot(contains(HdrRouteDependency.hwdecSurfaceTexture)));
    expect(copyCarrier.offscreenTransfer, isNull);
  });
  test('experiment admits exactly the derived surfacetexture route', () {
    // The realizer derived the carrier route; the independent validator
    // accepts exactly it (no copy/SDR relaxation).
    final prediction = plan();
    expect(prediction.playable, isTrue);
    final route = prediction.selected.route!;
    expect(route.strategy, HdrStrategy.baseLayerConvert);
    expect(route.hwdec, 'surfacetexture');
    expect(route.vo, 'gpu-next');
    expect(route.topology, HdrTopology.platformView);
    expect(route.outputTransfer, HdrOutputTransfer.pq);
    expect(route.targetTrc, 'pq');
    expect(route.surfaceTransfer, transfer);
    // The migration-default RGB baseline never opens under the validator.
    expect(() => plan(capabilities: legacyCaps),
        throwsA(isA<HdrPlaybackBlocked>()));
  });
  test(
      'hlg convert maturity: the experiment plans the experimental-labeled '
      'surfacetexture route in its own planner call', () {
    // Device OES-round contract: the named hlg patch fixture classifies as a
    // bare HLG source (codec null, transfer hlg); hlg x baseLayerConvert
    // carries the `experimental` maturity label, which is diagnostic only.
    // The experiment class is the explicit diagnostic opt-in: its own
    // planner call plans the convert route without any gate, without
    // touching the production table.
    final hlgSource = HdrSourceDescriptor.fromKind(HdrMediaKind.hlg);
    expect(hlgSource.codec, isEmpty);
    expect(hlgSource.transfer, 'hlg');
    final prediction = plan(input: hlgSource, capabilities: deviceCaps);
    expect(prediction.playable, isTrue);
    final route = prediction.selected.route!;
    expect(route.strategy, HdrStrategy.baseLayerConvert);
    expect(route.hwdec, 'surfacetexture');
    expect(route.vo, 'gpu-next');
    expect(route.topology, HdrTopology.platformView);
    expect(route.outputTransfer, HdrOutputTransfer.pq);
    expect(route.targetTrc, 'pq');
    expect(route.surfaceTransfer, transfer);
  });
  test('unknown hint, SDR and off preference never open a PoC route', () {
    expect(() => plan(input: const HdrSourceDescriptor()),
        throwsA(isA<HdrPlaybackBlocked>()));
    expect(() => plan(input: const HdrSourceDescriptor(transfer: 'bt.1886')),
        throwsA(isA<HdrPlaybackBlocked>()));
    expect(() => plan(preference: HdrOutputPreference.off),
        throwsA(isA<HdrPlaybackBlocked>()));
  });
  test('A4 by carrier: YUV execution failure blocks without a copy takeover, '
      'and a copy failure cannot exclude the YUV carrier', () {
    // The yuv-only device has no alternate HDR carrier: every failed
    // execution that kills the surfacetexture carrier must block the
    // prediction instead of falling back to a copy or SDR route.
    for (final dependency in [
      HdrRouteDependency.hwdecSurfaceTexture,
      HdrRouteDependency.dataspacePq,
      HdrRouteDependency.topologyPlatformView
    ]) {
      expect(() => plan(excluded: {dependency: HdrDegradeReason.hwdecMismatch}),
          throwsA(isA<HdrPlaybackBlocked>()));
    }
    // The YUV carrier execution is independent of the copy mode: a failed
    // copy execution neither excludes nor degrades it.
    final excludedCopy = plan(excluded: {
      HdrRouteDependency.hwdecMediacodecCopy: HdrDegradeReason.hwdecMismatch,
    });
    expect(excludedCopy.playable, isTrue);
    expect(excludedCopy.selected.route!.hwdec, 'surfacetexture');
  });
  test('output contract pairs are explicit; auto and mismatches fail', () {
    for (final pair in [
      const AndroidSurfaceTextureExperiment('pq', 'full'),
      const AndroidSurfaceTextureExperiment('pq-itu', 'limited')
    ]) {
      expect(pair.validate, returnsNormally);
    }
    for (final pair in [
      const AndroidSurfaceTextureExperiment('pq', 'limited'),
      const AndroidSurfaceTextureExperiment('pq-itu', 'full'),
      const AndroidSurfaceTextureExperiment('pq-itu', '')
    ]) {
      expect(pair.validate, throwsStateError);
    }
  });
  test('route lock rejects dataspace perform probe before preparation', () {
    expect(() => experiment.validateAdmission(dataSpacePerformProbe: true),
        throwsStateError);
    expect(() => experiment.validateAdmission(dataSpacePerformProbe: false),
        returnsNormally);
  });
}
