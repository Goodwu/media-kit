import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit_video/media_kit_video.dart';

void main() {
  const transfer = String.fromEnvironment(
      'MEDIA_KIT_ANDROID_CONVERT_SURFACE_TRANSFER', defaultValue: 'pq');
  const locked = bool.fromEnvironment('MEDIA_KIT_ANDROID_HDR_CONVERT_ROUTE_LOCK');
  test('convert override rejects invalid labels, unlocked limited and non-LG limited', () {
    for (final sdk in [24, 29]) {
      for (final id in ['lg-pq', 'lya-pq']) {
        final result = HdrStrategyRealizer.realize(HdrStrategy.baseLayerConvert,
          source: const HdrSourceDescriptor(transfer: 'hlg'),
          sourceClass: HdrSourceClass.hlg,
          capabilities: HdrCapabilities(sdkInt: sdk, displayHdrTypes: const {2},
            hevcDecoders: const [], dolbyVisionDecoders: const [],
            p5PipelineAvailable: true, dataSpaceBridgeLoaded: true,
            dataSpaceExt: HdrDataSpaceExtInfo(id: id, applicable: true)));
        final allowed = transfer == 'pq' ||
            (transfer == 'pq-itu' && locked && sdk == 24 && id == 'lg-pq');
        expect(result.route != null, allowed, reason: '$transfer/$locked/$sdk/$id');
        if (allowed) expect(result.route!.surfaceTransfer, transfer);
      }
    }
  });
}
