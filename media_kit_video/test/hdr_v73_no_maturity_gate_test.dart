import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit_video/src/hdr/hdr_capabilities.dart';
import 'package:media_kit_video/src/hdr/hdr_route.dart';
import 'package:media_kit_video/src/hdr/hdr_route_planner.dart';
import 'package:media_kit_video/src/hdr/hdr_source_descriptor.dart';
import 'package:media_kit_video/src/hdr/hdr_strategy.dart';

const vividPq = HdrSourceDescriptor(
  codec: 'hevc', transfer: 'pq',
  dynamicMetadata: HdrDynamicMetadata.hdrVivid);

HdrCapabilities caps() => HdrCapabilities(
  sdkInt: 29, displayHdrTypes: const {2},
  hevcDecoders: const [], dolbyVisionDecoders: const [],
  p5PipelineAvailable: true,
  dataSpaceBridgeLoaded: true, dataSpaceExt: null);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('C1/C2 unimplemented entries remain visible without an enable switch', () {
    final defaultPlan = HdrRoutePlanner.plan(
        source: vividPq, capabilities: caps());
    expect(defaultPlan.candidates[0].status, HdrCandidateStatus.error);
    expect(defaultPlan.candidates[1].status, HdrCandidateStatus.error);
    expect(defaultPlan.selected.strategy, HdrStrategy.baseLayerDirect);
    expect(defaultPlan.selected.stage, HdrRouteStage.c3);
  });

  test('legacy experimental toggles cannot change the route or errors', () {
    final no = HdrRoutePlanner.plan(
      source: vividPq, capabilities: caps(),
      policy: const HdrRoutingPolicy(allowExperimental: false));
    final yes = HdrRoutePlanner.plan(
      source: vividPq, capabilities: caps(),
      policy: const HdrRoutingPolicy(allowExperimental: true));
    expect(no.selected.strategy, yes.selected.strategy);
    expect(no.candidates.map((c) => c.skipReason).toList(),
        yes.candidates.map((c) => c.skipReason).toList());
  });

  test('HLG C4 may run by default with no maturity admission gate', () {
    const hlg = HdrSourceDescriptor(codec: 'hevc', transfer: 'hlg');
    final result = HdrRoutePlanner.plan(source: hlg, capabilities: caps());
    expect(result.playable, isTrue);
    expect(result.selected.strategy, HdrStrategy.baseLayerConvert);
    expect(result.selected.route!.outputTransfer, HdrOutputTransfer.pq);
  });
}
