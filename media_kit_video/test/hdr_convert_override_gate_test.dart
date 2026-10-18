import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit_video/media_kit_video.dart';

void main() {
  const transfer = String.fromEnvironment(
      'MEDIA_KIT_ANDROID_CONVERT_SURFACE_TRANSFER', defaultValue: 'pq');
  const locked = bool.fromEnvironment('MEDIA_KIT_ANDROID_HDR_CONVERT_ROUTE_LOCK');
  test('convert override rejects invalid labels, unlocked limited and '
      'undeclared limited transfers', () {
    for (final sdk in [24, 29]) {
      for (final declared in [false, true]) {
        for (final applicable in [true, false]) {
          final result = HdrStrategyRealizer.realize(HdrStrategy.baseLayerConvert,
            source: const HdrSourceDescriptor(transfer: 'hlg'),
            sourceClass: HdrSourceClass.hlg,
            capabilities: HdrCapabilities(sdkInt: sdk, displayHdrTypes: const {2},
              hevcDecoders: const [], dolbyVisionDecoders: const [],
              p5PipelineAvailable: true, dataSpaceBridgeLoaded: true,
              dataSpaceExt: HdrDataSpaceExtInfo(
                // The id is inert data; the pq-itu gate consumes the
                // declared supported-surface-transfer capability.
                id: 'unknown-vendor',
                applicable: applicable,
                supportedSurfaceTransfers:
                    declared ? const {'pq-itu'} : const {})));
          // The pq-itu experiment gate: route lock + the extension's
          // supported-surface-transfer declaration + applicability. The
          // plain pq request stays outside this gate, but API 24 still
          // needs an applicable extension for the RGB carrier ground (the
          // pre-existing W1 pqPresentation gate).
          final allowed = transfer == 'pq'
              ? applicable || sdk >= 28
              : (transfer == 'pq-itu' &&
                  locked &&
                  sdk == 24 &&
                  declared &&
                  applicable);
          expect(result.route != null, allowed,
              reason: '$transfer/$locked/$sdk/$declared/$applicable');
          if (allowed) expect(result.route!.surfaceTransfer, transfer);
        }
      }
    }
  });
}
