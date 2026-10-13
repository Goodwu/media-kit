import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit_video/src/hdr/hdr_capabilities.dart';
import 'package:media_kit_video/src/hdr/hdr_route.dart';
import 'package:media_kit_video/src/hdr/hdr_source_descriptor.dart';
import 'package:media_kit_video/src/hdr/hdr_strategy.dart';
import 'package:media_kit_video/src/hdr/hdr_strategy_realizer.dart';

HdrCapabilities caps(Set<int>? display) => HdrCapabilities(
      sdkInt: 29,
      displayHdrTypes: display,
      hevcDecoders: const [],
      dolbyVisionDecoders: const [],
      p5PipelineAvailable: true,
      dataSpaceBridgeLoaded: true,
      dataSpaceExt: null,
    );

HdrStrategyRealization convert(HdrSourceDescriptor source, Set<int>? display) =>
    HdrStrategyRealizer.realize(
      HdrStrategy.baseLayerConvert,
      source: source,
      sourceClass: HdrSourceClass.of(source),
      capabilities: caps(display),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('HLG with PQ panel is converted to PQ', () {
    const source = HdrSourceDescriptor(codec: 'hevc', transfer: 'hlg');
    final result = convert(source, {2});
    expect(result.infeasibleReason, isNull);
    expect(result.route!.outputTransfer, HdrOutputTransfer.pq);
    expect(result.route!.targetTrc, 'pq');
  });

  test('HLG-only panel is not a valid HLG-to-PQ conversion target', () {
    const source = HdrSourceDescriptor(codec: 'hevc', transfer: 'hlg');
    expect(convert(source, {3}).infeasibleReason,
        HdrDegradeReason.displayLacksTransfer);
  });

  test('PQ base layers cannot enter C4 even with PQ display', () {
    const pq = HdrSourceDescriptor(codec: 'hevc',
        transfer: 'pq', primaries: 'bt.2020');
    const hdr10Plus = HdrSourceDescriptor(codec: 'hevc',
        transfer: 'pq', primaries: 'bt.2020',
        dynamicMetadata: HdrDynamicMetadata.hdr10Plus);
    const vividPq = HdrSourceDescriptor(codec: 'hevc',
        transfer: 'pq', dynamicMetadata: HdrDynamicMetadata.hdrVivid);
    for (final source in [pq, hdr10Plus, vividPq]) {
      expect(convert(source, {2, 3}).infeasibleReason,
          HdrDegradeReason.unsupportedStrategy);
    }
  });

  test('Vivid HLG compatibility base may use C4', () {
    const vividHlg = HdrSourceDescriptor(codec: 'hevc', transfer: 'hlg',
        dynamicMetadata: HdrDynamicMetadata.hdrVivid);
    expect(convert(vividHlg, {2}).route?.outputTransfer, HdrOutputTransfer.pq);
  });

  test('DV P8.2 SDR baseline cannot be converted to HDR', () {
    const p82 = HdrSourceDescriptor(codec: 'hevc', transfer: 'bt.1886',
        dynamicMetadata: HdrDynamicMetadata.dolbyVision,
        dvProfile: 8, dvCompatibilityId: 2, enhancementLayer: false);
    expect(convert(p82, {2, 3}).infeasibleReason,
        HdrDegradeReason.unsupportedStrategy);
  });

  test('HLG without display report cannot assume PQ', () {
    const source = HdrSourceDescriptor(codec: 'hevc', transfer: 'hlg');
    expect(convert(source, null).infeasibleReason,
        HdrDegradeReason.noDisplayCapabilityReport);
  });
}
