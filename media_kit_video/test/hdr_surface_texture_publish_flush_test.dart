import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit_video/src/hdr/hdr_capabilities.dart';
import 'package:media_kit_video/src/hdr/hdr_output_policy.dart';
import 'package:media_kit_video/src/hdr/hdr_route.dart';
import 'package:media_kit_video/src/hdr/hdr_source_descriptor.dart';
import 'package:media_kit_video/src/hdr/hdr_strategy.dart';
import 'package:media_kit_video/src/hdr/hdr_strategy_realizer.dart';

HdrCapabilities _caps(
        {bool consent = true,
        bool applicable = true,
        bool rgb = false,
        String id = 'opaque-vendor'}) =>
    HdrCapabilities(
        sdkInt: 24,
        displayHdrTypes: const {2},
        hevcDecoders: const [],
        dolbyVisionDecoders: const [],
        p5PipelineAvailable: false,
        dataSpaceBridgeLoaded: true,
        dataSpaceExt: HdrDataSpaceExtInfo(
            id: id,
            applicable: applicable,
            pqPresentation: HdrPqPresentation(rgbSurface: rgb, yuvWindow: true),
            supportsDeferredSurfaceTexturePublish30fps: consent));

HdrRoute? _convert(HdrSourceDescriptor source, HdrCapabilities caps) =>
    HdrStrategyRealizer.realize(HdrStrategy.baseLayerConvert,
            source: source,
            sourceClass: HdrSourceClass.of(source),
            capabilities: caps)
        .route;

void main() {
  final p84 = HdrSourceDescriptor.fromKind(HdrMediaKind.dolbyVisionP84);
  test('capability is strict and absent/malformed values stay off', () {
    for (final raw in [null, false, 1, 'true', [], {}]) {
      final ext = HdrDataSpaceExtInfo.fromMap({
        'id': 'vendor',
        'isApplicable': true,
        'supportsDeferredSurfaceTexturePublish30fps': raw
      });
      expect(ext!.supportsDeferredSurfaceTexturePublish30fps, isFalse);
    }
    expect(
        HdrDataSpaceExtInfo.fromMap({
          'id': 'vendor',
          'supportsDeferredSurfaceTexturePublish30fps': true
        })!
            .supportsDeferredSurfaceTexturePublish30fps,
        isTrue);
    expect(
        const HdrDataSpaceExtInfo(id: 'vendor', applicable: true)
            .supportsDeferredSurfaceTexturePublish30fps,
        isFalse);
  });
  test(
      'exact P84 YUV contract and explicit applicable vendor consent request policy',
      () {
    final route = _convert(p84, _caps())!;
    expect(route.surfaceTexturePublishFlushPolicy,
        HdrSurfaceTexturePublishFlushPolicy.defer30fps);
    expect(route.supportsDeferredSurfaceTexturePublishShape, isTrue);
    expect(route.surfaceTexturePublishFlushPolicy.nativeValue, 'defer-30fps');
    // The opaque id proves this is capability-selected rather than a LG id check.
    expect(
        _convert(p84, _caps(id: 'another-vendor'))!
            .surfaceTexturePublishFlushPolicy,
        HdrSurfaceTexturePublishFlushPolicy.defer30fps);
  });
  test('legacy vendors, non-applicability and RGB execution never opt in', () {
    for (final caps in [_caps(consent: false), _caps(rgb: true)]) {
      expect(_convert(p84, caps)!.surfaceTexturePublishFlushPolicy,
          HdrSurfaceTexturePublishFlushPolicy.immediate);
    }
    expect(_convert(p84, _caps(applicable: false)), isNull);
  });
  test('ordinary HLG, P81 and P5 do not gain the P84 policy', () {
    final hlg = HdrSourceDescriptor.fromKind(HdrMediaKind.hlg);
    expect(_convert(hlg, _caps())!.surfaceTexturePublishFlushPolicy,
        HdrSurfaceTexturePublishFlushPolicy.immediate);
    for (final source in [
      const HdrSourceDescriptor(
          codec: 'hevc',
          transfer: 'pq',
          dynamicMetadata: HdrDynamicMetadata.dolbyVision,
          dvProfile: 8,
          dvCompatibilityId: 1),
      HdrSourceDescriptor.fromKind(HdrMediaKind.dolbyVisionP5)
    ]) {
      expect(_convert(source, _caps()), isNull);
    }
  });
  test('execution copy resets request on a non-SurfaceTexture import', () {
    final route = _convert(p84, _caps())!;
    expect(
        route.withExecution(
            hwdec: 'mediacodec-copy',
            dependencies: {}).surfaceTexturePublishFlushPolicy,
        HdrSurfaceTexturePublishFlushPolicy.immediate);
    expect(
        route.withExecution(
            hwdec: 'surfacetexture', dependencies: route.dependencies),
        route);
    final legacy = _convert(p84, _caps(consent: false))!;
    expect(route, isNot(legacy));
    expect(route.hashCode, isNot(legacy.hashCode));
    expect(route.toString(), contains('requestedPublishFlush: defer30fps'));
  });
}
