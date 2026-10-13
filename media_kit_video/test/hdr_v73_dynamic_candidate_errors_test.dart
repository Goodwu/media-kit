import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit_video/src/hdr/hdr_capabilities.dart';
import 'package:media_kit_video/src/hdr/hdr_route.dart';
import 'package:media_kit_video/src/hdr/hdr_route_planner.dart';
import 'package:media_kit_video/src/hdr/hdr_source_descriptor.dart';
import 'package:media_kit_video/src/hdr/hdr_strategy.dart';

const hdr10Plus = HdrSourceDescriptor(
  codec: 'hevc', transfer: 'pq', primaries: 'bt.2020',
  dynamicMetadata: HdrDynamicMetadata.hdr10Plus,
);
const vividPq = HdrSourceDescriptor(
  codec: 'hevc', transfer: 'pq',
  dynamicMetadata: HdrDynamicMetadata.hdrVivid,
);
const vividHlg = HdrSourceDescriptor(
  codec: 'hevc', transfer: 'hlg',
  dynamicMetadata: HdrDynamicMetadata.hdrVivid,
);

HdrCapabilities _caps(Set<int>? display) => HdrCapabilities(
      sdkInt: 29, displayHdrTypes: display,
      hevcDecoders: const [], dolbyVisionDecoders: const [],
      p5PipelineAvailable: true,
      dataSpaceBridgeLoaded: true, dataSpaceExt: null,
    );

void _expectMissingDynamic(HdrRoutePrediction p,
    HdrStrategy expectedNative) {
  expect(p.candidates[0].strategy, expectedNative);
  expect(p.candidates[0].skipReason,
      HdrDegradeReason.routeNotImplemented);
  expect(p.candidates[0].status, HdrCandidateStatus.error);
  expect(p.candidates[1].strategy, HdrStrategy.metadataReshape);
  expect(p.candidates[1].skipReason,
      HdrDegradeReason.routeNotImplemented);
  expect(p.candidates[1].status, HdrCandidateStatus.error);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('HDR10+ cannot masquerade as dynamic native or mapped PQ', () {
    final p = HdrRoutePlanner.plan(
        source: hdr10Plus, capabilities: _caps({2}),
        );
    _expectMissingDynamic(p, HdrStrategy.nativeHdr10Plus);
    expect(p.playable, isTrue);
    expect(p.selected.strategy, HdrStrategy.baseLayerDirect);
    expect(p.selected.route!.appliesDynamicMetadata, isFalse);
  });

  test('Vivid PQ maps to explicit C1/C2 errors before PQ baseline', () {
    final p = HdrRoutePlanner.plan(
        source: vividPq, capabilities: _caps({2}),
        );
    _expectMissingDynamic(p, HdrStrategy.nativeHdrVivid);
    expect(p.playable, isTrue);
    expect(p.selected.strategy, HdrStrategy.baseLayerDirect);
  });

  test('Vivid HLG with PQ-only panel can still reach C4', () {
    final p = HdrRoutePlanner.plan(
        source: vividHlg, capabilities: _caps({2}),
        );
    _expectMissingDynamic(p, HdrStrategy.nativeHdrVivid);
    expect(p.candidates.firstWhere((c) =>
        c.strategy == HdrStrategy.baseLayerDirect).feasible, isFalse);
    expect(p.playable, isTrue);
    expect(p.selected.strategy, HdrStrategy.baseLayerConvert);
    expect(p.selected.route!.outputTransfer, HdrOutputTransfer.pq);
  });

  test('missing PQ capability is unavailable, not C2 implementation error', () {
    final p = HdrRoutePlanner.plan(
        source: hdr10Plus, capabilities: _caps({3}),
        );
    expect(p.candidates[0].skipReason,
        HdrDegradeReason.routeNotImplemented);
    expect(p.candidates[1].skipReason,
        HdrDegradeReason.displayLacksTransfer);
    expect(p.candidates[1].status, HdrCandidateStatus.unavailable);
  });
}
