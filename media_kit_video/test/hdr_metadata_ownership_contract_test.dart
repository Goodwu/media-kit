import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit_video/src/hdr/hdr_capabilities.dart';
import 'package:media_kit_video/src/hdr/hdr_output_report.dart';
import 'package:media_kit_video/src/hdr/hdr_route.dart';
import 'package:media_kit_video/src/hdr/hdr_source_descriptor.dart';
import 'package:media_kit_video/src/hdr/hdr_strategy.dart';
import 'package:media_kit_video/src/hdr/hdr_strategy_realizer.dart';

const p5 = HdrSourceDescriptor(
  codec: 'hevc', dynamicMetadata: HdrDynamicMetadata.dolbyVision,
  dvProfile: 5, dvCompatibilityId: 0, enhancementLayer: false);
const p84 = HdrSourceDescriptor(
  codec: 'hevc', transfer: 'hlg', dynamicMetadata: HdrDynamicMetadata.dolbyVision,
  dvProfile: 8, dvCompatibilityId: 4, enhancementLayer: false);
const vividHlg = HdrSourceDescriptor(
  codec: 'hevc', transfer: 'hlg', dynamicMetadata: HdrDynamicMetadata.hdrVivid);
const hdr10Plus = HdrSourceDescriptor(
  codec: 'hevc', transfer: 'pq', dynamicMetadata: HdrDynamicMetadata.hdr10Plus);

HdrCapabilities caps() => HdrCapabilities(
  sdkInt: 29, displayHdrTypes: const {2, 3},
  hevcDecoders: const [], dolbyVisionDecoders: const [],
  p5PipelineAvailable: true,
  dataSpaceBridgeLoaded: true, dataSpaceExt: null,
);

HdrRoute route(HdrSourceDescriptor source, HdrStrategy strategy) {
  final result = HdrStrategyRealizer.realize(strategy,
    source: source,
    sourceClass: HdrSourceClass.of(source),
    capabilities: caps());
  expect(result.infeasibleReason, isNull);
  return result.route!;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('C2 P5 consumes RPU while native DV requests forwarding', () {
    final reshape = route(p5, HdrStrategy.metadataReshape);
    expect(reshape.metadataHandling, HdrMetadataHandling.consumeForMapping);
    expect(reshape.appliesDynamicMetadata, isTrue);
    expect(reshape.stripDvRpu, isFalse);
    expect(HdrStrategyRealizer.metadataHandlingFor(
      p5, HdrStrategy.nativeDolbyVision),
      HdrMetadataHandling.preserveForNative);
  });

  test('P8.4 C3 and C4 identify compatibility baseline, not dynamic HDR', () {
    final direct = route(p84, HdrStrategy.baseLayerDirect);
    final convert = route(p84, HdrStrategy.baseLayerConvert);
    expect(direct.metadataHandling, HdrMetadataHandling.baselineOnly);
    expect(convert.metadataHandling, HdrMetadataHandling.baselineOnly);
    expect(direct.appliesDynamicMetadata, isFalse);
    expect(convert.appliesDynamicMetadata, isFalse);
    expect(convert.outputTransfer, HdrOutputTransfer.pq);
    expect(convert.stripDvRpu, isTrue);
  });

  test('HDR10+/Vivid baselines do not masquerade as dynamic-mapped output', () {
    final pq = route(hdr10Plus, HdrStrategy.baseLayerDirect);
    final converted = route(vividHlg, HdrStrategy.baseLayerConvert);
    expect(pq.metadataHandling, HdrMetadataHandling.baselineOnly);
    expect(converted.metadataHandling, HdrMetadataHandling.baselineOnly);
    expect(pq.appliesDynamicMetadata, isFalse);
    expect(converted.appliesDynamicMetadata, isFalse);
    expect(HdrStrategyRealizer.metadataHandlingFor(
      hdr10Plus, HdrStrategy.metadataReshape),
      HdrMetadataHandling.consumeForMapping);
  });

  test('SDR source has no dynamic ownership, but P5 SDR mapping consumes it', () {
    const sdr = HdrSourceDescriptor(codec: 'hevc', transfer: 'bt.1886');
    expect(route(sdr, HdrStrategy.sdrDirect).metadataHandling,
      HdrMetadataHandling.none);
    expect(route(p5, HdrStrategy.toneMapSdr).metadataHandling,
      HdrMetadataHandling.consumeForMapping);
  });

  test('route execution copy preserves ownership identity and report stays unproven', () {
    final original = route(p84, HdrStrategy.baseLayerConvert);
    final copy = original.withExecution(
      hwdec: 'mediacodec-copy', dependencies: original.dependencies);
    expect(copy.metadataHandling, HdrMetadataHandling.baselineOnly);
    expect(copy, isNot(original));
    final report = HdrOutputReport(actual: copy);
    expect(report.requestedMetadataHandling, HdrMetadataHandling.baselineOnly);
    expect(report.metadataHandlingObserved, isNull,
      reason: 'configure/open cannot prove per-frame metadata handling');
  });
}
