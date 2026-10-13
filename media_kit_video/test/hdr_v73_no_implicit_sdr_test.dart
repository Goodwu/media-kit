import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit_video/src/hdr/hdr_capabilities.dart';
import 'package:media_kit_video/src/hdr/hdr_route.dart';
import 'package:media_kit_video/src/hdr/hdr_route_planner.dart';
import 'package:media_kit_video/src/hdr/hdr_source_descriptor.dart';
import 'package:media_kit_video/src/hdr/hdr_strategy.dart';

const _hdr10 = HdrSourceDescriptor(
  codec: 'hevc',
  transfer: 'pq',
  primaries: 'bt.2020',
  enhancementLayer: false,
);

HdrCapabilities _caps(Set<int>? display) => HdrCapabilities(
      sdkInt: 29,
      displayHdrTypes: display,
      hevcDecoders: const [],
      dolbyVisionDecoders: const [],
      p5PipelineAvailable: true,
      dataSpaceBridgeLoaded: true,
      dataSpaceExt: null,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('HDR output exhaustion cannot silently select SDR on an HDR panel', () {
    final result = HdrRoutePlanner.plan(
      source: _hdr10,
      capabilities: _caps({2}),
      excluded: const {
        HdrRouteDependency.decoderMediacodec:
            HdrDegradeReason.hwdecMismatch,
      },
    );
    expect(result.playable, isFalse);
    expect(result.candidates.where((candidate) =>
        candidate.feasible &&
        candidate.route?.outputTransfer == HdrOutputTransfer.sdr), isEmpty);
  });

  test('missing HDR capability report does not mean SDR-only display', () {
    final result = HdrRoutePlanner.plan(
      source: _hdr10,
      capabilities: _caps(null),
    );
    expect(result.playable, isFalse);
    expect(result.candidates.where((candidate) =>
        candidate.feasible &&
        candidate.route?.outputTransfer == HdrOutputTransfer.sdr), isEmpty);
  });

  test('confirmed SDR-only display retains correct tone mapping', () {
    final result = HdrRoutePlanner.plan(
      source: _hdr10,
      capabilities: _caps({}),
    );
    expect(result.playable, isTrue);
    expect(result.selected.strategy, HdrStrategy.toneMapSdr);
    expect(result.selected.route!.outputTransfer, HdrOutputTransfer.sdr);
  });

  test('explicit SDR request remains independent from HDR retry', () {
    final result = HdrRoutePlanner.plan(
      source: _hdr10,
      capabilities: _caps({2}),
      preference: HdrOutputPreference.off,
    );
    expect(result.playable, isTrue);
    expect(result.selected.strategy, HdrStrategy.toneMapSdr);
  });

  test('P8.2 SDR base cannot bypass the P5 reshape into a fake HDR output',
      () {
    const p82 = HdrSourceDescriptor(
      codec: 'hevc',
      transfer: 'bt.1886',
      dynamicMetadata: HdrDynamicMetadata.dolbyVision,
      dvProfile: 8,
      dvCompatibilityId: 2,
      enhancementLayer: false,
    );
    // P8.2 invariant: with the P5 rescale pipeline available, the C2
    // metadata reshape to PQ is the legal HDR output for the SDR baseline —
    // it applies the dynamic metadata, and no SDR-output route is offered on
    // the HDR display.
    final result = HdrRoutePlanner.plan(
      source: p82,
      capabilities: _caps({2}),
    );
    expect(result.playable, isTrue);
    expect(result.selected.strategy, HdrStrategy.metadataReshape);
    expect(result.selected.route!.outputTransfer, HdrOutputTransfer.pq);
    expect(result.selected.route!.appliesDynamicMetadata, isTrue);
    expect(
        result.candidates.where((candidate) =>
            candidate.feasible &&
            candidate.route?.outputTransfer == HdrOutputTransfer.sdr),
        isEmpty);
    // Without the pipeline the HDR branch is blocked: the SDR baseline is
    // never mistaken for an HDR output, and no implicit SDR route appears.
    final blocked = HdrRoutePlanner.plan(
      source: p82,
      capabilities: HdrCapabilities(
        sdkInt: 29,
        displayHdrTypes: const {2},
        hevcDecoders: const [],
        dolbyVisionDecoders: const [],
        p5PipelineAvailable: false,
        dataSpaceBridgeLoaded: true,
        dataSpaceExt: null,
      ),
    );
    expect(blocked.playable, isFalse);
    expect(
        blocked.candidates.where((candidate) =>
            candidate.feasible &&
            candidate.route?.outputTransfer == HdrOutputTransfer.sdr),
        isEmpty);
  });
}
