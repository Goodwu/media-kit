import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// A2 official backend admission at the baseLayerConvert decision point:
/// the POC define stays authoritative (bit-identical define path), the
/// owner-bound bridge probe adds the override only while it reports an
/// explicit init, and no other strategy route changes.
void main() {
  final lgCapabilities = HdrCapabilities(
    sdkInt: 24,
    displayHdrTypes: const {2, 3},
    hevcDecoders: const [],
    dolbyVisionDecoders: const [],
    p5PipelineAvailable: true,
    dataSpaceBridgeLoaded: true,
    dataSpaceExt: const HdrDataSpaceExtInfo(id: 'lg-pq', applicable: true),
  );

  HdrRoute? realizeBaseLayerConvert(HdrCapabilities capabilities) {
    final result = HdrStrategyRealizer.realize(
      HdrStrategy.baseLayerConvert,
      source: const HdrSourceDescriptor(transfer: 'hlg'),
      sourceClass: HdrSourceClass.hlg,
      capabilities: capabilities,
    );
    return result.route;
  }

  HdrRoute? realizeBaseLayerDirect(HdrCapabilities capabilities) {
    final result = HdrStrategyRealizer.realize(
      HdrStrategy.baseLayerDirect,
      source: const HdrSourceDescriptor(transfer: 'hlg'),
      sourceClass: HdrSourceClass.hlg,
      capabilities: capabilities,
    );
    return result.route;
  }

  tearDown(() {
    HdrStrategyRealizer.mkstBridgeProbeOverride = null;
  });

  test('poc define forces the override regardless of the probe', () {
    for (final official in [false, true]) {
      expect(
        HdrStrategyRealizer.surfaceTexturePocHwdec('mediacodec',
            define: 'poc', officialBackendReady: official),
        'surfacetexture',
      );
      expect(
        HdrStrategyRealizer.surfaceTexturePocHwdec('mediacodec-copy',
            define: 'poc', officialBackendReady: official),
        'surfacetexture',
      );
    }
  });

  test('empty define keeps the routed value unless the probe is ready', () {
    expect(HdrStrategyRealizer.surfaceTexturePocHwdec('mediacodec'), 'mediacodec');
    expect(
      HdrStrategyRealizer.surfaceTexturePocHwdec('mediacodec',
          officialBackendReady: false),
      'mediacodec',
    );
    expect(
      HdrStrategyRealizer.surfaceTexturePocHwdec('mediacodec-copy',
          officialBackendReady: true),
      'surfacetexture',
    );
  });

  test('official probe rides the existing admission gates', () {
    // Existing gates pass (LG-applicable): the probe decides.
    HdrStrategyRealizer.mkstBridgeProbeOverride = () => true;
    expect(realizeBaseLayerConvert(lgCapabilities)!.hwdec, 'surfacetexture');
    HdrStrategyRealizer.mkstBridgeProbeOverride = () => false;
    expect(realizeBaseLayerConvert(lgCapabilities)!.hwdec, 'mediacodec-copy');
    // Probe unavailable (host default): routed value unchanged.
    HdrStrategyRealizer.mkstBridgeProbeOverride = null;
    expect(realizeBaseLayerConvert(lgCapabilities)!.hwdec, 'mediacodec-copy');

    // Existing gates refuse (no applicable dataspace extension): the probe
    // must not reopen the route.
    HdrStrategyRealizer.mkstBridgeProbeOverride = () => true;
    final refused = HdrStrategyRealizer.realize(
      HdrStrategy.baseLayerConvert,
      source: const HdrSourceDescriptor(transfer: 'hlg'),
      sourceClass: HdrSourceClass.hlg,
      capabilities: const HdrCapabilities(
        sdkInt: 24,
        displayHdrTypes: {2},
        hevcDecoders: [],
        dolbyVisionDecoders: [],
        p5PipelineAvailable: true,
        dataSpaceBridgeLoaded: true,
        dataSpaceExt: HdrDataSpaceExtInfo(id: 'lg-pq', applicable: false),
      ),
    );
    expect(refused.route, isNull);
  });

  test('other strategy routes never consult the bridge probe', () {
    HdrStrategyRealizer.mkstBridgeProbeOverride = () => true;
    expect(realizeBaseLayerDirect(lgCapabilities)!.hwdec, 'mediacodec');
    expect(realizeBaseLayerDirect(lgCapabilities)!.vo, 'mediacodec_embed');
  });

  test('A4 contract split: default routes keep their surface contract', () {
    // Regression pin for the A4 field split, updated by the P8.4 A5 V2
    // review fix: in the default build (window label 'pq', no lock define)
    // the plain mediacodec routes keep the single surface contract with no
    // separate offscreen value, while the surfacetexture carrier — the one
    // carrier of the actual YUV presentation shape — now carries the
    // offscreen contract (`pq-full`) for the `pq` request too. The earlier
    // revision expected offscreen null for the surfacetexture route, which
    // was exactly the euv17 contract bypass (actual YUV shape, no quad).
    final pqCapabilities = HdrCapabilities(
      sdkInt: 24,
      displayHdrTypes: const {2},
      hevcDecoders: const [],
      dolbyVisionDecoders: const [],
      p5PipelineAvailable: true,
      dataSpaceBridgeLoaded: true,
      dataSpaceExt: const HdrDataSpaceExtInfo(id: 'lg-pq', applicable: true),
    );
    // Plain mediacodec-copy carrier: RGB single-contract route unchanged.
    HdrStrategyRealizer.mkstBridgeProbeOverride = () => false;
    final rgbRoute = realizeBaseLayerConvert(pqCapabilities)!;
    expect(rgbRoute.surfaceTransfer, 'pq',
        reason: 'window contract value unchanged by the split');
    expect(rgbRoute.hwdec, 'mediacodec-copy');
    expect(rgbRoute.offscreenTransfer, isNull,
        reason: 'RGB window routes keep a single contract');
    // Official surfacetexture carrier: actual YUV shape -> offscreen
    // contract declared for the `pq` request as well.
    HdrStrategyRealizer.mkstBridgeProbeOverride = () => true;
    final yuvRoute = realizeBaseLayerConvert(pqCapabilities)!;
    expect(yuvRoute.surfaceTransfer, 'pq');
    expect(yuvRoute.hwdec, 'surfacetexture');
    expect(yuvRoute.offscreenTransfer, 'pq-full',
        reason: 'the surfacetexture carrier presents the actual YUV shape; '
            'the offscreen contract is required regardless of the pq/pq-itu '
            'request (P8.4 A5 V2 review fix)');
    HdrStrategyRealizer.mkstBridgeProbeOverride = () => true;
    expect(realizeBaseLayerDirect(lgCapabilities)!.offscreenTransfer, isNull);
    HdrStrategyRealizer.mkstBridgeProbeOverride = null;
  });
}
