import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit_video/media_kit_video.dart';

void main() {
  test(
      'GPU platform request keeps EGL, window and offscreen contracts distinct',
      () {
    final contract = HdrOutputContract.fromRoute(
        _route(
          hwdec: 'surfacetexture',
          surfaceTransfer: 'pq-itu',
          offscreenTransfer: 'pq-full',
        ),
        surfacePixelFormatOverride: 'rgba8888');
    expect(contract.vo, 'gpu-next');
    expect(contract.topology, HdrTopology.platformView);
    expect(contract.requestedHwdec, 'surfacetexture');
    expect(contract.gpuApi, 'opengl');
    expect(contract.eglOutputFormat, 'rgb10_a2');
    expect(contract.surfacePixelFormat, 'rgba8888');
    expect(contract.surfaceTransfer, 'pq-itu');
    expect(contract.offscreenTransfer, 'pq-full');
  });

  test('SurfaceTexture and PQ alone do not invent an offscreen/YUV request',
      () {
    final contract = HdrOutputContract.fromRoute(_route(
      hwdec: 'surfacetexture',
      surfaceTransfer: 'pq',
    ));
    expect(contract.offscreenTransfer, isNull);
    expect(contract.surfacePixelFormat, 'rgba1010102');
  });

  test('topology comes from route even without a Surface transfer', () {
    final contract = HdrOutputContract.fromRoute(_route());
    final config =
        contract.controllerConfiguration(const VideoControllerConfiguration());
    expect(config.android.usePlatformView, isTrue);
    expect(config.android.surfaceTransfer, '');
    expect(config.android.surfacePixelFormat, '');
    expect(contract.eglOutputFormat, 'rgb10_a2');
  });

  test(
      'Session projection clears unrelated prior GPU/Surface hints for embed output',
      () {
    final contract =
        HdrOutputContract.fromRoute(_route(vo: 'mediacodec_embed'));
    final config = contract.controllerConfiguration(_base);
    expect(config.vo, 'mediacodec_embed');
    expect(config.hwdec, contract.requestedHwdec);
    expect(config.android.usePlatformView, isTrue);
    expect(config.android.gpuApi, isNull);
    expect(config.android.surfaceTransfer, '');
    expect(config.android.surfacePixelFormat, '');
    _expectUnrelatedOptionsPreserved(config);
  });

  test(
      'Session projection clears all Surface hints for Texture and preserves caller options',
      () {
    final contract = HdrOutputContract.fromRoute(_route(
      topology: HdrTopology.texture,
      hwdec: 'mediacodec-copy',
    ));
    final config = contract.controllerConfiguration(_base);
    expect(config.vo, contract.vo);
    expect(config.hwdec, 'mediacodec-copy');
    expect(config.android.usePlatformView, isFalse);
    expect(config.android.gpuApi, 'opengl');
    expect(config.android.surfaceTransfer, isNull);
    expect(config.android.surfacePixelFormat, isNull);
    expect(contract.eglOutputFormat, isNull);
    _expectUnrelatedOptionsPreserved(config);
  });

  test(
      'target primaries, tone curve and metadata policy are configured in place',
      () {
    final first = HdrOutputContract.fromRoute(
        _route(targetPrim: 'bt.2020', targetTrc: 'pq'));
    final second = HdrOutputContract.fromRoute(
        _route(targetPrim: 'bt.709', targetTrc: 'bt.1886', stripDvRpu: true));
    expect(first, second);
    expect(first.hashCode, second.hashCode);
  });
}

const _base = VideoControllerConfiguration(
  scale: 0.75,
  width: 640,
  height: 360,
  enableHardwareAcceleration: false,
  android: AndroidVideoOptions(
    useHCPP: true,
    enableSurfaceProducer: false,
    matchTextureOutputToLayout: true,
    attachSurfaceAfterVideoParameters: false,
    gpuApi: 'vulkan',
    surfaceTransfer: 'hlg',
    surfacePixelFormat: 'rgba16f',
    lgExperimentOwnerToken: 'test-owner',
  ),
  darwin: DarwinVideoOptions(useNativeSurface: true),
);

void _expectUnrelatedOptionsPreserved(VideoControllerConfiguration config) {
  expect(config.scale, _base.scale);
  expect(config.width, _base.width);
  expect(config.height, _base.height);
  expect(config.enableHardwareAcceleration, _base.enableHardwareAcceleration);
  expect(config.darwin, same(_base.darwin));
  expect(config.android.useHCPP, isTrue);
  expect(config.android.enableSurfaceProducer, isFalse);
  expect(config.android.matchTextureOutputToLayout, isTrue);
  expect(config.android.attachSurfaceAfterVideoParameters, isFalse);
  expect(config.android.lgExperimentOwnerToken, 'test-owner');
}

HdrRoute _route({
  String vo = 'gpu-next',
  String hwdec = 'mediacodec',
  HdrTopology topology = HdrTopology.platformView,
  String? surfaceTransfer,
  String? offscreenTransfer,
  String? targetPrim,
  String? targetTrc,
  bool stripDvRpu = false,
}) =>
    HdrRoute(
      strategy: HdrStrategy.sdrDirect,
      presentation: HdrPresentation.sdr,
      outputTransfer: HdrOutputTransfer.sdr,
      appliesDynamicMetadata: false,
      topology: topology,
      vo: vo,
      hwdec: hwdec,
      targetPrim: targetPrim,
      targetTrc: targetTrc,
      surfaceTransfer: surfaceTransfer,
      offscreenTransfer: offscreenTransfer,
      stripDvRpu: stripDvRpu,
    );
