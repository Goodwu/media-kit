import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit_video/src/hdr/hdr_capabilities.dart';
import 'package:media_kit_video/src/hdr/hdr_route.dart';
import 'package:media_kit_video/src/hdr/hdr_route_planner.dart';
import 'package:media_kit_video/src/hdr/hdr_source_descriptor.dart';
import 'package:media_kit_video/src/hdr/hdr_strategy.dart';
import 'package:media_kit_video/src/routing/video_route_options.dart';

const p84 = HdrSourceDescriptor(
  codec: 'hevc', transfer: 'hlg',
  dynamicMetadata: HdrDynamicMetadata.dolbyVision,
  dvProfile: 8, dvCompatibilityId: 4, enhancementLayer: false);
const hdr10Plus = HdrSourceDescriptor(
  codec: 'hevc', transfer: 'pq', primaries: 'bt.2020',
  dynamicMetadata: HdrDynamicMetadata.hdr10Plus);

HdrCapabilities caps(Set<int> types) => HdrCapabilities(
      sdkInt: 29, displayHdrTypes: types,
      hevcDecoders: const [], dolbyVisionDecoders: const [],
      p5PipelineAvailable: true,
      dataSpaceBridgeLoaded: true, dataSpaceExt: null);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('C2 is evaluated before C3/C4 even if old policy lists baseline first',
      () {
    final result = HdrRoutePlanner.plan(
      source: p84, capabilities: caps({2, 3}),
      policy: const HdrRoutingPolicy(
        preferences: {
          HdrSourceClass.dvP84: [
            HdrStrategy.baseLayerDirect,
            HdrStrategy.baseLayerConvert,
            HdrStrategy.metadataReshape,
          ],
        },
      ),
    );
    expect(result.selected.strategy, HdrStrategy.metadataReshape);
    expect(result.selected.stage, HdrRouteStage.c2);
    expect(result.candidates.map((c) => c.stage),
        [HdrRouteStage.c2, HdrRouteStage.c3, HdrRouteStage.c4]);
  });

  test('prefer decoder cannot move compatibility baseline before C2', () {
    final options = EffectiveVideoRouteOptions.resolve(
      application: const VideoRouteOptions(
        decode: VideoRouteSelection.prefer(VideoDecodeTarget.hardware)));
    final result = HdrRoutePlanner.plan(
      source: p84, capabilities: caps({2, 3}),
      options: options);
    expect(result.selected.stage, HdrRouteStage.c2);
    expect(result.selected.strategy, HdrStrategy.metadataReshape);
  });

  test('dynamic errors retain candidate IDs and stage before C3 baseline', () {
    final a = HdrRoutePlanner.plan(
      source: hdr10Plus, capabilities: caps({2}),
      );
    final b = HdrRoutePlanner.plan(
      source: hdr10Plus, capabilities: caps({2}),
      );
    expect(a.candidates[0].stage, HdrRouteStage.c1);
    expect(a.candidates[1].stage, HdrRouteStage.c2);
    expect(a.selected.stage, HdrRouteStage.c3);
    expect(a.candidates[0].candidateId, b.candidates[0].candidateId);
    expect(a.candidates.map((c) => c.candidateId).toSet().length,
        a.candidates.length);
  });

  test('ordinary HLG direct is C1, a later HLG-to-PQ conversion is C4', () {
    const source = HdrSourceDescriptor(codec: 'hevc', transfer: 'hlg');
    final result = HdrRoutePlanner.plan(
      source: source, capabilities: caps({2}),
      );
    expect(result.selected.stage, HdrRouteStage.c4);
    expect(result.selected.route!.outputTransfer, HdrOutputTransfer.pq);
    expect(result.candidates.first.stage, HdrRouteStage.c1);
  });
}
