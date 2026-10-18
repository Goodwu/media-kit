import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' show VideoParams;
import 'package:media_kit_video/media_kit_video.dart';

void main() {
  const classifier = HdrSourceClassifier();
  const caps = HdrCapabilities(
    sdkInt: 35,
    displayHdrTypes: {1, 2, 3},
    hevcDecoders: [],
    dolbyVisionDecoders: [
      HdrDecoderInfo(
        name: 'test.dv.p5.p8',
        mimeType: 'video/dolby-vision',
        hardwareAcceleration: true,
        profiles: [32, 256],
        main10: null,
        widthRange: null,
        heightRange: null,
        frameRateRange: null,
        supports4K: false,
        max4KFps: null,
      ),
    ],
    p5PipelineAvailable: true,
    nativeDvBridgeApi: 1,
    dataSpaceBridgeLoaded: true,
    dataSpaceExt: null,
  );

  for (final profile in [5, 8]) {
    final hint = HdrSourceDescriptor(
      codec: 'hevc',
      transfer: profile == 8 ? 'hlg' : null,
      dynamicMetadata: HdrDynamicMetadata.dolbyVision,
      dvProfile: profile,
      dvCompatibilityId: profile == 8 ? 4 : 0,
      enhancementLayer: false,
    );
    final params = VideoParams(
      gamma: profile == 8 ? 'hlg' : 'pq', primaries: 'bt.2020',
    );

    test('P$profile review cannot manufacture single-layer evidence', () {
      // A provisional hint is not allowed to fill a missing container EL
      // fact after review has received source facts.
      final source = classifier.classify(
        hint: hint,
        videoParams: params,
        dolbyVisionProfile: profile,
        dvCompatibilityId: hint.dvCompatibilityId,
      );
      expect(source.enhancementLayer, isNull);
      final native = HdrStrategyRealizer.realize(
        HdrStrategy.nativeDolbyVision,
        source: source,
        sourceClass: HdrSourceClass.of(source),
        capabilities: caps,
      );
      expect(native.route, isNull);
      expect(native.infeasibleReason, HdrDegradeReason.unsupportedStrategy);
    });

    test('P$profile explicit single-layer fact reaches native admission', () {
      final source = classifier.classify(
        hint: hint,
        videoParams: params,
        dolbyVisionProfile: profile,
        dvCompatibilityId: hint.dvCompatibilityId,
        dvElPresent: false,
      );
      expect(source.enhancementLayer, isFalse);
      final prediction = caps.predict(source);
      expect(prediction.selected.strategy, HdrStrategy.nativeDolbyVision);
      expect(prediction.selected.route!.stripDvRpu, isFalse);
    });
  }

  test('P10 missing EL remains unknown without claiming native support', () {
    final source = classifier.classify(
      videoParams: const VideoParams(gamma: 'hlg', primaries: 'bt.2020'),
      dolbyVisionProfile: 10,
    );
    expect(source.codec, 'av1');
    expect(source.enhancementLayer, isNull);
  });
}
