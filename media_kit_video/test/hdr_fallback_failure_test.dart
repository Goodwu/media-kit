import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit_video/media_kit_video.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final experimental in [false, true]) {
    for (final sdk in [24, 29]) {
      for (final hdr in [false, true]) {
        test('fallback retains failure: experimental=$experimental SDK=$sdk HDR=$hdr', () {
          final caps = HdrCapabilities(
            sdkInt: sdk,
            displayHdrTypes: const {},
            hevcDecoders: const [],
            dolbyVisionDecoders: const [],
            p5PipelineAvailable: true,
            dataSpaceBridgeLoaded: false,
            dataSpaceExt: null,
          );
          final source = hdr
              ? const HdrSourceDescriptor(codec: 'hevc', transfer: 'hlg')
              : const HdrSourceDescriptor(codec: 'h264', transfer: 'bt.1886');
          final dependency = sdk < 26
              ? HdrRouteDependency.hwdecMediacodecCopy
              : HdrRouteDependency.hwdecMediacodec;
          final failures = {dependency: HdrDegradeReason.hwdecMismatch};
          final result = HdrRoutePlanner.plan(
            source: source,
            capabilities: caps,
            policy: HdrRoutingPolicy(allowExperimental: experimental),
            excluded: failures,
          );
          expect(result.playable, isFalse);
          expect(result.selected.route, isNull);
          expect(result.selected.skipReason, HdrDegradeReason.hwdecMismatch);
          expect(failures, {dependency: HdrDegradeReason.hwdecMismatch});
        });
      }
    }
  }

  test('an unavailable GPU dataspace does not exclude independent direct HDR', () {
    const caps = HdrCapabilities(
      sdkInt: 29, displayHdrTypes: {2}, hevcDecoders: [],
      dolbyVisionDecoders: [], p5PipelineAvailable: true,
      dataSpaceBridgeLoaded: true, dataSpaceExt: null,
    );
    final result = HdrRoutePlanner.plan(
      source: const HdrSourceDescriptor(codec: 'hevc', transfer: 'pq', primaries: 'bt.2020'),
      capabilities: caps,
      policy: const HdrRoutingPolicy(allowExperimental: true),
      excluded: const {HdrRouteDependency.dataspacePq: HdrDegradeReason.dataSpaceApplyFailed},
    );
    expect(result.playable, isTrue);
    expect(result.selected.strategy, HdrStrategy.baseLayerDirect);
  });

  test('platform-view failure still permits an independent SDR output', () {
    const caps = HdrCapabilities(
      sdkInt: 29, displayHdrTypes: {2}, hevcDecoders: [],
      dolbyVisionDecoders: [], p5PipelineAvailable: true,
      dataSpaceBridgeLoaded: true, dataSpaceExt: null,
    );
    final result = HdrRoutePlanner.plan(
      source: const HdrSourceDescriptor(codec: 'hevc', transfer: 'pq', primaries: 'bt.2020'),
      capabilities: caps,
      policy: const HdrRoutingPolicy(allowExperimental: true),
      excluded: const {HdrRouteDependency.topologyPlatformView: HdrDegradeReason.outputBindTimeout},
    );
    expect(result.playable, isTrue);
    expect(result.selected.strategy, HdrStrategy.toneMapSdr);
  });
}
