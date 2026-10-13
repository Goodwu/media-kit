import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit_video/src/hdr/hdr_capabilities.dart';
import 'package:media_kit_video/src/hdr/hdr_route.dart';
import 'package:media_kit_video/src/hdr/hdr_route_planner.dart';
import 'package:media_kit_video/src/hdr/hdr_source_descriptor.dart';
import 'package:media_kit_video/src/hdr/hdr_strategy.dart';
import 'package:media_kit_video/src/routing/video_route_options.dart';

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

  test('no enable switch exists: route and errors are fixed', () {
    final withDefaults = HdrRoutePlanner.plan(
      source: vividPq, capabilities: caps(),
      policy: HdrRoutingPolicy.defaults);
    final withoutPolicy = HdrRoutePlanner.plan(
      source: vividPq, capabilities: caps());
    expect(withDefaults.selected.strategy, withoutPolicy.selected.strategy);
    expect(withDefaults.candidates.map((c) => c.skipReason).toList(),
        withoutPolicy.candidates.map((c) => c.skipReason).toList());
    expect(withDefaults.candidates[0].status, HdrCandidateStatus.error);
    expect(withDefaults.candidates[1].status, HdrCandidateStatus.error);
  });

  test('valid options are accepted without any legacy hint', () {
    final options = EffectiveVideoRouteOptions.resolve();
    final result = HdrRoutePlanner.plan(
      source: vividPq, capabilities: caps(),
      options: options,
    );
    expect(result.playable, isTrue);
    expect(result.selected.strategy, HdrStrategy.baseLayerDirect);
  });

  test('HLG C4 may run by default with no maturity admission gate', () {
    const hlg = HdrSourceDescriptor(codec: 'hevc', transfer: 'hlg');
    final result = HdrRoutePlanner.plan(source: hlg, capabilities: caps());
    expect(result.playable, isTrue);
    expect(result.selected.strategy, HdrStrategy.baseLayerConvert);
    expect(result.selected.route!.outputTransfer, HdrOutputTransfer.pq);
  });
}
