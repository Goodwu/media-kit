import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit_video/media_kit_video.dart';

// MK-ROUTING-20261011 B1a: independent capability counterexamples.
// These tests exercise production realization/planning, not copied gates.
HdrDecoderInfo decoder(List<int> profiles, {
  String name = 'test.decoder',
  String mime = 'video/dolby-vision',
  bool hardware = true,
}) => HdrDecoderInfo(
  name: name,
  mimeType: mime,
  hardwareAcceleration: hardware,
  profiles: profiles,
  main10: null,
  widthRange: null,
  heightRange: null,
  frameRateRange: null,
  supports4K: false,
  max4KFps: null,
);

HdrCapabilities capabilities({
  Set<int>? display = const {1, 2, 3},
  List<HdrDecoderInfo> decoders = const [],
  bool p5Pipeline = true,
  int bridge = 1,
  int sdk = 35,
  HdrDataSpaceExtInfo? ext,
}) => HdrCapabilities(
  sdkInt: sdk,
  displayHdrTypes: display,
  hevcDecoders: const [],
  dolbyVisionDecoders: decoders,
  p5PipelineAvailable: p5Pipeline,
  nativeDvBridgeApi: bridge,
  dataSpaceBridgeLoaded: true,
  dataSpaceExt: ext,
);

HdrSourceDescriptor dvSource(int profile, {bool? enhancementLayer = false}) =>
    HdrSourceDescriptor(
      codec: 'hevc',
      transfer: profile == 8 ? 'hlg' : null,
      primaries: 'bt.2020',
      dynamicMetadata: HdrDynamicMetadata.dolbyVision,
      dvProfile: profile,
      dvCompatibilityId: profile == 8 ? 4 : 0,
      enhancementLayer: enhancementLayer,
    );

HdrStrategyRealization native(HdrSourceDescriptor source, HdrCapabilities caps) =>
    HdrStrategyRealizer.realize(
      HdrStrategy.nativeDolbyVision,
      source: source,
      sourceClass: HdrSourceClass.of(source),
      capabilities: caps,
    );

void main() {
  for (final gateOpen in [false, true]) {
    final policy = HdrRoutingPolicy(allowExperimental: gateOpen);
    group('experimental=$gateOpen does not grant capabilities', () {
      test('P8.4 accepts profile256 without requiring profile32', () {
        final prediction = capabilities(decoders: [decoder([256])])
            .predict(dvSource(8), policy: policy);
        expect(prediction.selected.strategy, HdrStrategy.nativeDolbyVision);
        expect(prediction.selected.maturity, HdrStrategyMaturity.verified);
        expect(prediction.selected.route!.mediacodecEmbedRenderMode, 'boolean');
      });

      test('P5-only decoder is not a native P8.4 candidate', () {
        final prediction = capabilities(decoders: [decoder([32])])
            .predict(dvSource(8), policy: policy);
        expect(prediction.candidates.first.skipReason,
            HdrDegradeReason.nativeDvUnavailable);
        expect(prediction.selected.strategy, HdrStrategy.baseLayerDirect);
        expect(prediction.selected.route!.outputTransfer, HdrOutputTransfer.hlg);
      });

      test('P5 native does not depend on the GPU P5 pipeline', () {
        final prediction = capabilities(
          decoders: [decoder([32])], p5Pipeline: false,
        ).predict(dvSource(5), policy: policy);
        expect(prediction.playable, isTrue);
        expect(prediction.selected.strategy, HdrStrategy.nativeDolbyVision);
        expect(prediction.selected.route!.mediacodecEmbedRenderMode, 'timed');
      });

      test('profile256 cannot substitute for P5 profile32', () {
        final prediction = capabilities(
          decoders: [decoder([256])], p5Pipeline: false,
        ).predict(dvSource(5), policy: policy);
        expect(prediction.candidates.first.skipReason,
            HdrDegradeReason.nativeDvUnavailable);
        expect(prediction.playable, isFalse);
        expect(prediction.selected.skipReason,
            HdrDegradeReason.p5PipelineUnavailable);
      });

      test('DV plus PQ display does not grant HLG direct output', () {
        final prediction = capabilities(
          display: {1, 2}, decoders: [decoder([32])],
        ).predict(dvSource(8), policy: policy);
        final direct = prediction.candidates.singleWhere(
            (candidate) => candidate.strategy == HdrStrategy.baseLayerDirect);
        expect(direct.skipReason, HdrDegradeReason.displayLacksTransfer);
        expect(prediction.selected.strategy, HdrStrategy.baseLayerConvert);
        expect(prediction.selected.route!.outputTransfer, HdrOutputTransfer.pq);
      });

      test('DV-only display cannot receive a bare HLG source as HDR', () {
        final prediction = capabilities(display: {1}).predict(
          const HdrSourceDescriptor(
            codec: 'hevc', transfer: 'hlg', enhancementLayer: false,
          ),
          policy: policy,
        );
        final direct = prediction.candidates.singleWhere(
            (candidate) => candidate.strategy == HdrStrategy.baseLayerDirect);
        expect(direct.skipReason, HdrDegradeReason.displayLacksTransfer);
        expect(prediction.selected.strategy, HdrStrategy.toneMapSdr);
        expect(prediction.selected.route!.outputTransfer, HdrOutputTransfer.sdr);
      });

      test('an actual HLG declaration still permits HLG direct', () {
        final prediction = capabilities(display: {3}).predict(
          dvSource(8), policy: policy,
        );
        expect(prediction.selected.strategy, HdrStrategy.baseLayerDirect);
        expect(prediction.selected.route!.outputTransfer, HdrOutputTransfer.hlg);
      });
    });
  }

  test('native P5 and P8.4 reject unknown or present enhancement layers', () {
    final caps = capabilities(decoders: [decoder([32, 256])]);
    for (final profile in [5, 8]) {
      for (final el in <bool?>[null, true]) {
        final result = native(dvSource(profile, enhancementLayer: el), caps);
        expect(result.route, isNull, reason: 'profile=$profile el=$el');
        expect(result.infeasibleReason, HdrDegradeReason.unsupportedStrategy);
      }
    }
  });

  test('required profile must belong to a hardware DV MIME decoder', () {
    for (final invalid in [
      decoder([256], hardware: false),
      decoder([256], mime: 'video/hevc'),
    ]) {
      final result = native(dvSource(8), capabilities(decoders: [invalid]));
      expect(result.infeasibleReason, HdrDegradeReason.nativeDvUnavailable);
    }
    // A later eligible entry is not hidden by the first decoder's profiles.
    final result = native(dvSource(8), capabilities(decoders: [
      decoder([32], name: 'p5.only'),
      decoder([256], name: 'p8.only'),
    ]));
    expect(result.route, isNotNull);
    // Existence is admission evidence only; actual decoder identity remains
    // an execution-review concern, not a claim made by this test.
  });

  test('display and bridge gates remain independent from decoder profiles', () {
    final dv = [decoder([32, 256])];
    expect(native(dvSource(8), capabilities(display: null, decoders: dv))
        .infeasibleReason, HdrDegradeReason.noDisplayCapabilityReport);
    expect(native(dvSource(8), capabilities(display: {2, 3}, decoders: dv))
        .infeasibleReason, HdrDegradeReason.displayLacksTransfer);
    expect(native(dvSource(8), capabilities(decoders: dv, bridge: 0))
        .infeasibleReason, HdrDegradeReason.nativeDvUnavailable);
  });

  test('LG-like API24 without an extension cannot bypass conversion gates', () {
    final prediction = capabilities(
      sdk: 24, display: {1, 2}, decoders: [decoder([32])],
    ).predict(dvSource(8), policy: const HdrRoutingPolicy(allowExperimental: true));
    expect(prediction.candidates.first.skipReason,
        HdrDegradeReason.nativeDvUnavailable);
    final direct = prediction.candidates.singleWhere(
        (candidate) => candidate.strategy == HdrStrategy.baseLayerDirect);
    final convert = prediction.candidates.singleWhere(
        (candidate) => candidate.strategy == HdrStrategy.baseLayerConvert);
    expect(direct.skipReason, HdrDegradeReason.displayLacksTransfer);
    expect(convert.skipReason, HdrDegradeReason.gpuHdrDataSpaceUnavailable);
    expect(prediction.selected.strategy, HdrStrategy.toneMapSdr);
    expect(prediction.selected.route!.hwdec, 'mediacodec-copy');
    // This does not claim the separately authorized LG YUV route is ready.
  });
}
