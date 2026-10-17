import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:media_kit_video/src/hdr/hdr_player_backend.dart';

HdrCapabilities caps(
        {int sdk = 24,
        String id = 'lg-pq',
        bool applicable = true,
        Set<String> setterOnly = const <String>{}}) =>
    HdrCapabilities(
        sdkInt: sdk,
        displayHdrTypes: const {2},
        hevcDecoders: const [],
        dolbyVisionDecoders: const [],
        p5PipelineAvailable: false,
        dataSpaceBridgeLoaded: false,
        dataSpaceExt: HdrDataSpaceExtInfo(
            id: id,
            applicable: applicable,
            setterOnlyTransfers: setterOnly));

/// The LG-shaped self-report: the extension declares the setter-only
/// exception for both PQ transfers (the readback is impossible on that
/// platform) — the capability the acceptance consumes instead of any
/// device-name-derived identifier.
const lgSetterOnly = <String>{'pq', 'pq-itu'};

void main() {
  test('LYA default convert route keeps production PQ request', () {
    final route = HdrStrategyRealizer.realize(HdrStrategy.baseLayerConvert,
            source: const HdrSourceDescriptor(transfer: 'hlg'),
            sourceClass: HdrSourceClass.hlg,
            capabilities: caps(sdk: 29, id: 'lya-pq'))
        .route!;
    expect(route.surfaceTransfer, 'pq');
    expect(route.targetTrc, 'pq');
    expect(route.hwdec, 'mediacodec');
  });
  test('PQ readback verifies transfer and range exactly', () {
    for (final value in ['DATASPACE_BT2020_PQ', '0x09c60000']) {
      expect(AndroidHdrBackend.dataSpaceReadbackMatches('pq', value), isTrue);
      expect(
          AndroidHdrBackend.dataSpaceReadbackMatches('pq-itu', value), isFalse);
    }
    for (final value in ['DATASPACE_BT2020_PQ_LIMITED', '0x11c60000']) {
      expect(
          AndroidHdrBackend.dataSpaceReadbackMatches('pq-itu', value), isTrue);
      expect(AndroidHdrBackend.dataSpaceReadbackMatches('pq', value), isFalse);
    }
    for (final value in [null, '', 'none', 'DATASPACE_SRGB', 'PQ']) {
      expect(
          AndroidHdrBackend.dataSpaceReadbackMatches('pq-itu', value), isFalse);
    }
    expect(
        AndroidHdrBackend.dataSpaceReadbackMatches('unknown', 'PQ'), isFalse);
  });
  test('setter-without-readback acceptance follows the declared capability',
      () {
    // The declared capability accepts both PQ transfers (applied must hold).
    expect(
        AndroidHdrBackend.acceptsUnverifiedExtSetter(
            caps(setterOnly: lgSetterOnly), 'pq-itu', true, 'ext:lg-pq',
            'none'),
        isTrue);
    expect(
        AndroidHdrBackend.acceptsUnverifiedExtSetter(
            caps(setterOnly: lgSetterOnly), 'pq', true, 'ext:lg-pq', null),
        isTrue);
    // A familiar id WITHOUT the declaration gets no exception: the id is
    // inert data, only the capability counts.
    expect(
        AndroidHdrBackend.acceptsUnverifiedExtSetter(
            caps(), 'pq', true, 'ext:lg-pq', null),
        isFalse);
    // An unknown id WITH the explicit declaration works (the path identity
    // follows the registered extension).
    expect(
        AndroidHdrBackend.acceptsUnverifiedExtSetter(
            caps(id: 'unknown-vendor', setterOnly: lgSetterOnly),
            'pq',
            true,
            'ext:unknown-vendor',
            null),
        isTrue);
    // The five rejections: not applicable, not applied, undeclared
    // transfer, foreign path, present-but-wrong readback.
    expect(
        AndroidHdrBackend.acceptsUnverifiedExtSetter(
            caps(setterOnly: lgSetterOnly, applicable: false),
            'pq',
            true,
            'ext:lg-pq',
            null),
        isFalse);
    expect(
        AndroidHdrBackend.acceptsUnverifiedExtSetter(
            caps(setterOnly: lgSetterOnly), 'pq', false, 'ext:lg-pq', null),
        isFalse);
    expect(
        AndroidHdrBackend.acceptsUnverifiedExtSetter(
            caps(setterOnly: lgSetterOnly), 'hlg', true, 'ext:lg-pq', null),
        isFalse);
    for (final path in [null, 'ext:any', 'ext:lya-pq', 'none']) {
      expect(
          AndroidHdrBackend.acceptsUnverifiedExtSetter(
              caps(setterOnly: lgSetterOnly), 'pq', true, path, null),
          isFalse);
    }
    expect(
        AndroidHdrBackend.acceptsUnverifiedExtSetter(
            caps(setterOnly: lgSetterOnly), 'pq', true, 'ext:lg-pq',
            'DATASPACE_SRGB'),
        isFalse);
  });
  test('LG setter evidence is not surface readback verification', () {
    const report = HdrOutputReport(
        dataSpaceRequested: 'pq-itu',
        dataSpacePath: 'ext:lg-pq',
        dataSpaceReadback: 'none',
        verified: true);
    expect(report.dataSpaceReadbackVerified, isFalse);
    expect(report.verified, isTrue); // decoder review only
  });
  test('API24 convert carries copy dependency, not noncopy identity', () {
    final route = HdrStrategyRealizer.realize(HdrStrategy.baseLayerConvert,
            source: const HdrSourceDescriptor(transfer: 'hlg'),
            sourceClass: HdrSourceClass.hlg,
            capabilities: caps())
        .route!;
    expect(route.hwdec, 'mediacodec-copy');
    expect(
        route.dependencies, contains(HdrRouteDependency.hwdecMediacodecCopy));
    expect(route.dependencies,
        isNot(contains(HdrRouteDependency.hwdecMediacodec)));
  });
}
