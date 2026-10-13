import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit_video/media_kit_video.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final sdk in [24, 29]) {
    for (final hdr in [false, true]) {
      test('fallback retains failed request while permitting independent execution: SDK=$sdk HDR=$hdr', () {
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
          excluded: failures,
        );
        expect(result.playable, isTrue);
        expect(result.selected.route!.hwdec, sdk < 26 ? 'no' : 'mediacodec-copy');
        expect(result.selected.route!.dependencies, isNot(contains(dependency)));
        expect(result.candidates.where((c) => c.skipReason == HdrDegradeReason.hwdecMismatch), isNotEmpty);
        expect(failures, {dependency: HdrDegradeReason.hwdecMismatch});
        // A shared presenter failure still blocks every independent decoder.
        final sharedFailures = {...failures,
          HdrRouteDependency.presenterGpuTexture: HdrDegradeReason.hwdecMismatch};
        final blocked = HdrRoutePlanner.plan(source: source, capabilities: caps,
          excluded: sharedFailures);
        expect(blocked.playable, isFalse);
        expect(blocked.selected.route, isNull);
        expect(blocked.selected.skipReason, HdrDegradeReason.hwdecMismatch);
        expect(sharedFailures, {...failures,
          HdrRouteDependency.presenterGpuTexture: HdrDegradeReason.hwdecMismatch});
      });
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
      excluded: const {HdrRouteDependency.dataspacePq: HdrDegradeReason.dataSpaceApplyFailed},
    );
    expect(result.playable, isTrue);
    expect(result.selected.strategy, HdrStrategy.baseLayerDirect);
  });

  test('platform-view failure exhausts the HDR list on an HDR-capable display', () {
    const caps = HdrCapabilities(
      sdkInt: 29, displayHdrTypes: {2}, hevcDecoders: [],
      dolbyVisionDecoders: [], p5PipelineAvailable: true,
      dataSpaceBridgeLoaded: true, dataSpaceExt: null,
    );
    final result = HdrRoutePlanner.plan(
      source: const HdrSourceDescriptor(codec: 'hevc', transfer: 'pq', primaries: 'bt.2020'),
      capabilities: caps,
      excluded: const {HdrRouteDependency.topologyPlatformView: HdrDegradeReason.outputBindTimeout},
    );
    // Every HDR candidate renders through the platform-view stage; on this
    // HDR-capable display the exhausted list blocks — no independent SDR
    // output is synthesized (MK-ROUTING-20261011).
    expect(result.playable, isFalse);
    expect(result.selected.strategy, HdrStrategy.baseLayerDirect);
    expect(result.selected.skipReason, HdrDegradeReason.outputBindTimeout);
    expect(result.selected.route, isNull);
    for (final candidate in result.candidates) {
      if (candidate.strategy == HdrStrategy.toneMapSdr) {
        // The tone-map entries carry the SDR-block marker, not a fallback
        // admission.
        expect(candidate.feasible, isFalse, reason: '$candidate');
        expect(candidate.skipReason, HdrDegradeReason.displayLacksTransfer,
            reason: '$candidate');
      } else if (candidate.strategy == HdrStrategy.baseLayerConvert) {
        // PQ input has no C4 HLG-to-PQ conversion candidate.
        expect(candidate.skipReason, HdrDegradeReason.unsupportedStrategy,
            reason: '$candidate');
      } else {
        expect(candidate.skipReason, HdrDegradeReason.outputBindTimeout,
            reason: '$candidate');
      }
    }
  });
}
