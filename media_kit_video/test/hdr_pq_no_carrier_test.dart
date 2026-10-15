import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit_video/media_kit_video.dart';

void main() {
  const sources = {
    'HLG': HdrSourceDescriptor(codec: 'hevc', transfer: 'hlg'),
    'P8.4': HdrSourceDescriptor(
        codec: 'hevc', transfer: 'hlg',
        dynamicMetadata: HdrDynamicMetadata.dolbyVision,
        dvProfile: 8, dvCompatibilityId: 4, enhancementLayer: false),
    'Vivid HLG': HdrSourceDescriptor(
        codec: 'hevc', transfer: 'hlg',
        dynamicMetadata: HdrDynamicMetadata.hdrVivid),
  };
  for (final source in sources.entries) {
    for (final rgb in [false, true]) {
      for (final yuv in [false, true]) {
        test('${source.key} C4 requires a declared carrier rgb=$rgb yuv=$yuv', () {
          final caps = HdrCapabilities(
              sdkInt: 28, displayHdrTypes: const {2},
              hevcDecoders: const [], dolbyVisionDecoders: const [],
              p5PipelineAvailable: true, dataSpaceBridgeLoaded: true,
              dataSpaceExt: HdrDataSpaceExtInfo(
                  id: 'fixture', applicable: true,
                  pqPresentation: HdrPqPresentation(rgbSurface: rgb, yuvWindow: yuv)));
          final result = HdrStrategyRealizer.realize(HdrStrategy.baseLayerConvert,
              source: source.value, sourceClass: HdrSourceClass.of(source.value),
              capabilities: caps);
          if (!rgb && !yuv) {
            expect(result.route, isNull);
            expect(result.infeasibleReason, HdrDegradeReason.pqRgbPresentationUnavailable);
            final prediction = caps.predict(source.value);
            expect(prediction.playable, isFalse);
            expect(prediction.candidates.any((candidate) => candidate.feasible), isFalse);
          } else {
            expect(result.infeasibleReason, isNull);
            expect(result.route!.hwdec, rgb ? 'mediacodec' : 'surfacetexture');
            expect(result.route!.outputTransfer, HdrOutputTransfer.pq);
            expect(result.route!.appliesDynamicMetadata, isFalse);
          }
        });
      }
    }
  }
}
