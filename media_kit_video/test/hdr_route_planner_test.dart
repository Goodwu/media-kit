import 'package:flutter_test/flutter_test.dart';

import 'package:media_kit_video/src/hdr/hdr_capabilities.dart';
import 'package:media_kit_video/src/hdr/hdr_route.dart';
import 'package:media_kit_video/src/hdr/hdr_route_planner.dart';
import 'package:media_kit_video/src/hdr/hdr_source_descriptor.dart';
import 'package:media_kit_video/src/hdr/hdr_strategy.dart';
import 'package:media_kit_video/src/hdr/hdr_strategy_realizer.dart';
import 'package:media_kit_video/src/routing/video_route_options.dart';

/// The LYA-shaped self-report: applicable, with the vendor's validated
/// prediction evidence for the pq surface transfer (the confidence rule
/// consumes the declared capability, never the extension id).
const HdrDataSpaceExtInfo extApplicable = HdrDataSpaceExtInfo(
    id: 'lya-pq',
    applicable: true,
    validatedPredictionTransfers: <String>{'pq'});
const HdrDataSpaceExtInfo extNotApplicable = HdrDataSpaceExtInfo(
    id: 'lya-pq',
    applicable: false,
    validatedPredictionTransfers: <String>{'pq'});

const HdrDecoderInfo lyHevcDecoder = HdrDecoderInfo(
  name: 'OMX.hisi.video.decoder.hevc',
  mimeType: 'video/hevc',
  hardwareAcceleration: true,
  profiles: <int>[2],
  main10: true,
  widthRange: <int>[16, 4096],
  heightRange: <int>[16, 4096],
  frameRateRange: <int>[8, 240],
  supports4K: true,
  max4KFps: 59.94,
);

const HdrDecoderInfo nativeDvDecoder = HdrDecoderInfo(
  name: 'OMX.vendor.video.decoder.dolby-vision',
  mimeType: 'video/dolby-vision',
  hardwareAcceleration: true,
  // Generic P5 + P8 device. Profile-only counterexamples live in
  // hdr_route_admission_test.dart; P5 support cannot stand in for P8.
  profiles: <int>[32, 256],
  main10: null,
  widthRange: <int>[16, 4096],
  heightRange: <int>[16, 4096],
  frameRateRange: <int>[8, 120],
  supports4K: true,
  max4KFps: 60,
);

/// One descriptor per source class. Each entry derives back to its key
/// (asserted below), so the matrix includes unresolved Dolby Vision too.
const Map<HdrSourceClass, HdrSourceDescriptor> sources =
    <HdrSourceClass, HdrSourceDescriptor>{
  HdrSourceClass.hdr10: HdrSourceDescriptor(
      transfer: 'pq', primaries: 'bt.2020', enhancementLayer: false),
  HdrSourceClass.hlg:
      HdrSourceDescriptor(transfer: 'hlg', enhancementLayer: false),
  HdrSourceClass.dvP5: HdrSourceDescriptor(
      codec: 'hevc',
      dynamicMetadata: HdrDynamicMetadata.dolbyVision,
      dvProfile: 5,
      dvCompatibilityId: 0,
      enhancementLayer: false),
  HdrSourceClass.dvP81: HdrSourceDescriptor(
      codec: 'hevc',
      transfer: 'pq',
      primaries: 'bt.2020',
      dynamicMetadata: HdrDynamicMetadata.dolbyVision,
      dvProfile: 8,
      dvCompatibilityId: 1,
      enhancementLayer: false),
  HdrSourceClass.dvP82: HdrSourceDescriptor(
      codec: 'hevc',
      transfer: 'bt.1886',
      dynamicMetadata: HdrDynamicMetadata.dolbyVision,
      dvProfile: 8,
      dvCompatibilityId: 2,
      enhancementLayer: false),
  HdrSourceClass.dvP84: HdrSourceDescriptor(
      codec: 'hevc',
      transfer: 'hlg',
      dynamicMetadata: HdrDynamicMetadata.dolbyVision,
      dvProfile: 8,
      dvCompatibilityId: 4,
      enhancementLayer: false),
  HdrSourceClass.dvP7: HdrSourceDescriptor(
      codec: 'hevc',
      transfer: 'pq',
      primaries: 'bt.2020',
      dynamicMetadata: HdrDynamicMetadata.dolbyVision,
      dvProfile: 7,
      dvCompatibilityId: 6),
  HdrSourceClass.dvP10: HdrSourceDescriptor(
      codec: 'av1',
      transfer: 'pq',
      primaries: 'bt.2020',
      dynamicMetadata: HdrDynamicMetadata.dolbyVision,
      dvProfile: 10),
  HdrSourceClass.hdrVivid: HdrSourceDescriptor(
      transfer: 'hlg',
      dynamicMetadata: HdrDynamicMetadata.hdrVivid,
      enhancementLayer: false),
  HdrSourceClass.hdr10Plus: HdrSourceDescriptor(
      transfer: 'pq',
      primaries: 'bt.2020',
      dynamicMetadata: HdrDynamicMetadata.hdr10Plus,
      enhancementLayer: false),
  HdrSourceClass.dvUnknown: HdrSourceDescriptor(
      codec: 'hevc',
      dynamicMetadata: HdrDynamicMetadata.dolbyVision,
      dvProfile: 8),
  HdrSourceClass.sdr: HdrSourceDescriptor(
      transfer: 'bt.1886', primaries: 'bt.709', enhancementLayer: false),
};

HdrCapabilities caps({
  int sdkInt = 29,
  Set<int>? displayHdrTypes = const <int>{2, 3},
  bool p5 = true,
  HdrDataSpaceExtInfo? ext,
  List<HdrDecoderInfo> dvDecoders = const <HdrDecoderInfo>[],
  int nativeDvBridgeApi = 0,
}) {
  return HdrCapabilities(
    sdkInt: sdkInt,
    displayHdrTypes: displayHdrTypes,
    hevcDecoders: const <HdrDecoderInfo>[lyHevcDecoder],
    dolbyVisionDecoders: dvDecoders,
    p5PipelineAvailable: p5,
    nativeDvBridgeApi: nativeDvBridgeApi,
    dataSpaceBridgeLoaded: true,
    dataSpaceExt: ext,
  );
}

/// The S2-measured LYA-AL00 snapshot: SDK 29, HDR10+HLG display, HEVC
/// Main10 with 4K, no Dolby Vision decoder, P5 pipeline present, bridge
/// loaded, and the lya-pq vendor extension registered and applicable.
HdrCapabilities lyaCaps() {
  return caps(ext: extApplicable);
}

/// Cross-cutting invariants every prediction must satisfy, independent of
/// the specific expectation of a test cell.
void checkInvariants(
  HdrRoutePrediction prediction, {
  required HdrSourceClass cls,
  required HdrCapabilities capabilities,
  bool explicitSdrRequest = false,
}) {
  // Unknown DV must remain blocked independently of the decoder/display/P5
  // pipeline.
  if (cls == HdrSourceClass.dvUnknown) {
    expect(prediction.playable, isFalse,
        reason: 'unknown DV never becomes playable');
  }

  // MK-ROUTING-20261011: an SDR output is reachable only for a plain SDR
  // source, an explicit off/require-SDR request, or a confirmed SDR-only
  // display (report present and empty). On an HDR-capable or unknown display
  // the exhausted HDR list blocks; playable is no longer unconditionally
  // true and no tone-map fallback is synthesized.
  final bool sdrOutputAllowed = cls == HdrSourceClass.sdr ||
      explicitSdrRequest ||
      capabilities.displayHdrTypes?.isEmpty == true;
  final bool hasFeasibleHdrCandidate = prediction.candidates.any(
      (HdrCandidate c) =>
          c.feasible && c.route!.outputTransfer != HdrOutputTransfer.sdr);
  final bool hasFeasibleSdrCandidate = prediction.candidates.any(
      (HdrCandidate c) =>
          c.feasible && c.route!.outputTransfer == HdrOutputTransfer.sdr);
  expect(
    hasFeasibleSdrCandidate && !sdrOutputAllowed,
    isFalse,
    reason: 'an SDR output is only allowed for SDR sources, explicit SDR '
        'requests or confirmed SDR-only displays '
        '($cls, display: ${capabilities.displayHdrTypes})',
  );
  expect(
    prediction.playable,
    hasFeasibleHdrCandidate || hasFeasibleSdrCandidate,
    reason: 'playable for $cls with p5=${capabilities.p5PipelineAvailable} '
        '(display: ${capabilities.displayHdrTypes})',
  );
  expect(prediction.selected.feasible, prediction.playable);

  // R7 baseline: native Dolby Vision is never the playable selection unless
  // the class is dvP5 or dvP84 on a DV-declaring display with the bridge
  // loaded (both verified since the 2026-10-10 A-group promotion; dvP5 via
  // the genbump2 LG acceptance, dvP84 via the marble r30g acceptance). When
  // the plan blocks, the selection may be a rejected nativeDolbyVision
  // candidate recorded as the first blocking reason — that is not a routing
  // decision.
  expect(
    !prediction.playable ||
        prediction.selected.strategy != HdrStrategy.nativeDolbyVision ||
        ((cls == HdrSourceClass.dvP5 || cls == HdrSourceClass.dvP84) &&
            capabilities.displayHdrTypes?.contains(1) == true &&
            capabilities.nativeDvBridgeApi == 1),
    isTrue,
    reason: 'nativeDolbyVision selected for $cls',
  );

  // Candidate list shape: the selection is a member, skipped candidates
  // carry a reason and no route, feasible candidates carry a route.
  expect(prediction.candidates, contains(prediction.selected));
  for (final HdrCandidate candidate in prediction.candidates) {
    if (candidate.skipReason != null) {
      expect(candidate.feasible, isFalse, reason: '$candidate');
      expect(candidate.route, isNull, reason: '$candidate');
    } else {
      expect(candidate.feasible, isTrue, reason: '$candidate');
      expect(candidate.route, isNotNull, reason: '$candidate');
    }
    // Maturity is a diagnostic label in v7.3: it never admits or rejects a
    // route, so no maturity value constrains which candidate is selected.
  }

  // Presentation follows the selected route (or the strategy when the
  // safety net could not produce a route at all).
  expect(
    prediction.presentation,
    prediction.selected.route?.presentation ??
        HdrPresentation.ofStrategy(prediction.selected.strategy),
  );

  // Confidence rule (R1.5): dataspace-dependent routes need a registered
  // extension whose applicability check matched this device.
  final HdrRoute? route = prediction.selected.route;
  final bool dependsOnDataSpace =
      route != null && route.surfaceTransfer != null;
  final HdrDataSpaceExtInfo? ext = capabilities.dataSpaceExt;
  expect(
    prediction.confidence,
    cls != HdrSourceClass.dvUnknown &&
            (!dependsOnDataSpace || (ext != null && ext.applicable))
        ? HdrPredictionConfidence.verified
        : HdrPredictionConfidence.unverified,
    reason: 'confidence for $cls (ext: $ext)',
  );

  // Property (verification 2): when any feasible candidate presents native
  // HDR, the selection must not be a tone-map/SDR route. Maturity labels do
  // not participate: every applicable path is always evaluated (v7.3).
  final bool hasFeasibleHdr = prediction.candidates.any(
    (HdrCandidate c) =>
        c.feasible && c.route!.presentation == HdrPresentation.nativeHdr,
  );
  if (hasFeasibleHdr) {
    expect(
      prediction.selected.strategy,
      isNot(anyOf(HdrStrategy.toneMapSdr, HdrStrategy.sdrDirect)),
      reason: 'HDR-first violated for $cls: ${prediction.candidates}',
    );
  }
}

void main() {
  const List<Set<int>?> displays = <Set<int>?>[
    null,
    <int>{},
    <int>{2},
    <int>{3},
    <int>{2, 3},
    // A display reporting Dolby Vision (type 1). Only the native DV route
    // consumes the type (realizer display ground for dvP5/dvP84); without a
    // DV decoder + bridge in `caps()` those candidates are refused and the
    // rest of the plan ignores the type.
    <int>{1},
    <int>{1, 2, 3},
  ];
  const List<HdrDataSpaceExtInfo?> extensions = <HdrDataSpaceExtInfo?>[
    null,
    extApplicable,
    extNotApplicable,
  ];

  group('native Dolby Vision P5 realizer', () {
    const HdrSourceDescriptor eligibleP5 = HdrSourceDescriptor(
      codec: 'hevc',
      // Unknown transfer is intentional: output must remain explicitly DV,
      // never be inferred as SDR from an unavailable base-layer transfer.
      transfer: 'transfer3',
      dynamicMetadata: HdrDynamicMetadata.dolbyVision,
      dvProfile: 5,
      dvCompatibilityId: 0,
      enhancementLayer: false,
    );

    HdrStrategyRealization realize({
      HdrSourceDescriptor source = eligibleP5,
      HdrSourceClass sourceClass = HdrSourceClass.dvP5,
      HdrCapabilities? capabilities,
    }) =>
        HdrStrategyRealizer.realize(
          HdrStrategy.nativeDolbyVision,
          source: source,
          sourceClass: sourceClass,
          capabilities: capabilities ??
              caps(
                displayHdrTypes: const <int>{1},
                p5: false,
                dvDecoders: const <HdrDecoderInfo>[nativeDvDecoder],
                nativeDvBridgeApi: 1,
              ),
        );

    HdrSourceDescriptor source({
      String codec = 'hevc',
      HdrDynamicMetadata metadata = HdrDynamicMetadata.dolbyVision,
      int? profile = 5,
      int? compatibilityId = 0,
      bool? enhancementLayer = false,
    }) =>
        HdrSourceDescriptor(
          codec: codec,
          transfer: 'transfer3',
          dynamicMetadata: metadata,
          dvProfile: profile,
          dvCompatibilityId: compatibilityId,
          enhancementLayer: enhancementLayer,
        );

    test('realizes only native route and does not need GPU P5 pipeline', () {
      final HdrRoute route = realize().route!;
      expect(route.strategy, HdrStrategy.nativeDolbyVision);
      expect(route.presentation, HdrPresentation.nativeDolbyVision);
      expect(route.outputTransfer, HdrOutputTransfer.dolbyVision);
      expect(route.topology, HdrTopology.platformView);
      expect(route.vo, 'mediacodec_embed');
      expect(route.hwdec, 'mediacodec');
      expect(route.vdLavcOptions, 'native_dv=1');
      expect(route.mediacodecEmbedRenderMode, 'timed');
      expect(route.stripDvRpu, isFalse);
      expect(route.appliesDynamicMetadata, isTrue);
      expect(route.dependencies, <String>{
        HdrRouteDependency.nativeDolbyVision,
        HdrRouteDependency.hwdecMediacodec,
        HdrRouteDependency.topologyPlatformView,
      });
    });

    test('rejects unknown or non-single-layer source facts', () {
      final List<HdrSourceDescriptor> invalidSources = <HdrSourceDescriptor>[
        source(codec: 'h264'),
        source(metadata: HdrDynamicMetadata.none),
        source(profile: 8),
        source(compatibilityId: null),
        source(compatibilityId: 1),
        source(enhancementLayer: null),
        source(enhancementLayer: true),
      ];
      for (final HdrSourceDescriptor invalid in invalidSources) {
        expect(
            realize(source: invalid).infeasibleReason,
            invalid.hasUnresolvedDolbyVision
                ? HdrDegradeReason.sourceMetadataUnknown
                : HdrDegradeReason.unsupportedStrategy,
            reason: '$invalid');
      }
      expect(
        realize(sourceClass: HdrSourceClass.dvP84).infeasibleReason,
        HdrDegradeReason.unsupportedStrategy,
      );
    });

    test('requires DV display, hardware profile 32 decoder and bridge v1', () {
      expect(
        realize(capabilities: caps(displayHdrTypes: null)).infeasibleReason,
        HdrDegradeReason.noDisplayCapabilityReport,
      );
      expect(
        realize(capabilities: caps(displayHdrTypes: const <int>{2, 3}))
            .infeasibleReason,
        HdrDegradeReason.displayLacksTransfer,
      );
      const HdrDecoderInfo softOrWrong = HdrDecoderInfo(
        name: 'wrong',
        mimeType: 'video/hevc',
        hardwareAcceleration: false,
        profiles: <int>[31],
        main10: null,
        widthRange: null,
        heightRange: null,
        frameRateRange: null,
        supports4K: false,
        max4KFps: null,
      );
      for (final List<HdrDecoderInfo> decoders in <List<HdrDecoderInfo>>[
        const <HdrDecoderInfo>[],
        const <HdrDecoderInfo>[softOrWrong],
      ]) {
        expect(
          realize(
            capabilities: caps(
              displayHdrTypes: const <int>{1},
              dvDecoders: decoders,
              nativeDvBridgeApi: 1,
            ),
          ).infeasibleReason,
          HdrDegradeReason.nativeDvUnavailable,
        );
      }
      expect(
        realize(
          capabilities: caps(
            displayHdrTypes: const <int>{1},
            dvDecoders: const <HdrDecoderInfo>[nativeDvDecoder],
          ),
        ).infeasibleReason,
        HdrDegradeReason.nativeDvUnavailable,
      );
    });

    test('planner selects native DV for eligible P5.0 with the realizer '
        'grounds met', () {
      // The selection comes from the realizer grounds (DV display,
      // profile-32 decoder, bridge v1); the policy only carries preferences.
      final HdrRoutePrediction prediction = caps(
        displayHdrTypes: const <int>{1},
        dvDecoders: const <HdrDecoderInfo>[nativeDvDecoder],
        nativeDvBridgeApi: 1,
      ).predict(
        eligibleP5,
        policy: const HdrRoutingPolicy(
          preferences: <HdrSourceClass, List<HdrStrategy>>{
            HdrSourceClass.dvP5: <HdrStrategy>[
              HdrStrategy.nativeDolbyVision,
              HdrStrategy.toneMapSdr,
            ],
          },
        ),
      );
      expect(
          prediction.candidates.first.strategy, HdrStrategy.nativeDolbyVision);
      expect(prediction.candidates.first.skipReason, isNull);
      expect(prediction.selected.strategy, HdrStrategy.nativeDolbyVision);
      expect(prediction.selected.route!.vdLavcOptions, 'native_dv=1');
      expect(prediction.selected.route!.mediacodecEmbedRenderMode, 'timed');
    });
  });

  group('HdrSourceClass derivation', () {
    test('every matrix descriptor maps back to its intended class', () {
      sources.forEach((HdrSourceClass cls, HdrSourceDescriptor source) {
        expect(HdrSourceClass.of(source), cls, reason: '$source');
      });
    });

    test('HDR10+/HDR Vivid come from dynamic metadata, HDR from the base layer',
        () {
      expect(
        HdrSourceClass.of(const HdrSourceDescriptor(
            transfer: 'pq',
            primaries: 'bt.2020',
            dynamicMetadata: HdrDynamicMetadata.hdr10Plus)),
        HdrSourceClass.hdr10Plus,
      );
      expect(
        HdrSourceClass.of(const HdrSourceDescriptor(
            transfer: 'hlg', dynamicMetadata: HdrDynamicMetadata.hdrVivid)),
        HdrSourceClass.hdrVivid,
      );
      expect(
        HdrSourceClass.of(
            const HdrSourceDescriptor(transfer: 'pq', primaries: 'bt.2020')),
        HdrSourceClass.hdr10,
      );
      expect(
        HdrSourceClass.of(const HdrSourceDescriptor(transfer: 'hlg')),
        HdrSourceClass.hlg,
      );
      // PQ without BT.2020 primaries and SDR gammas stay SDR.
      expect(
        HdrSourceClass.of(
            const HdrSourceDescriptor(transfer: 'pq', primaries: 'bt.709')),
        HdrSourceClass.sdr,
      );
      expect(
        HdrSourceClass.of(const HdrSourceDescriptor(transfer: 'bt.1886')),
        HdrSourceClass.sdr,
      );
    });

    test('profile 8 with an unknown compatibility id follows the base layer',
        () {
      HdrSourceDescriptor p8(String? transfer) => HdrSourceDescriptor(
          transfer: transfer,
          dynamicMetadata: HdrDynamicMetadata.dolbyVision,
          dvProfile: 8);
      expect(HdrSourceClass.of(p8('hlg')), HdrSourceClass.dvP84);
      expect(HdrSourceClass.of(p8('pq')), HdrSourceClass.dvP81);
      expect(HdrSourceClass.of(p8('bt.1886')), HdrSourceClass.dvP82);
      expect(HdrSourceClass.of(p8(null)), HdrSourceClass.dvUnknown);
    });

    test('DV metadata without a profile remains unresolved', () {
      // Neither P5 processing nor RPU stripping is justified by an unknown
      // profile, even when an ordinary base-layer transfer is present.
      expect(
        HdrSourceClass.of(const HdrSourceDescriptor(
            transfer: 'pq', dynamicMetadata: HdrDynamicMetadata.dolbyVision)),
        HdrSourceClass.dvUnknown,
      );
    });
  });

  group('default preference matrix (verification 1)', () {
    test('12 classes × 7 displays × 2 P5 pipelines × 3 ext × 2 SDK', () {
      var combos = 0;
      for (final HdrSourceClass cls in HdrSourceClass.values) {
        final HdrSourceDescriptor source = sources[cls]!;
        for (final Set<int>? display in displays) {
          for (final bool p5 in const <bool>[true, false]) {
            for (final HdrDataSpaceExtInfo? ext in extensions) {
              final HdrCapabilities at29 =
                  caps(displayHdrTypes: display, p5: p5, ext: ext, sdkInt: 29);
              final HdrCapabilities at34 =
                  caps(displayHdrTypes: display, p5: p5, ext: ext, sdkInt: 34);
              final HdrRoutePrediction at29Plan =
                  HdrRoutePlanner.plan(source: source, capabilities: at29);
              final HdrRoutePrediction at34Plan =
                  HdrRoutePlanner.plan(source: source, capabilities: at34);

              checkInvariants(at29Plan, cls: cls, capabilities: at29);
              checkInvariants(at34Plan, cls: cls, capabilities: at34);

              // The Phase 1 planner does not read sdkInt (the rgb10_a2
              // output format and the dataspace application path are
              // execution-phase concerns handled in S4/S5), so the whole
              // prediction must be identical across SDK levels.
              expect(at34Plan, at29Plan,
                  reason: 'sdk must not affect planning for $cls '
                      '(display: $display, p5: $p5, ext: $ext)');
              combos++;
            }
          }
        }
      }
      expect(combos, 504);
    });

    test('explicit default policy: same matrix holds without skips', () {
      const HdrRoutingPolicy policy = HdrRoutingPolicy.defaults;
      var combos = 0;
      for (final HdrSourceClass cls in HdrSourceClass.values) {
        final HdrSourceDescriptor source = sources[cls]!;
        for (final Set<int>? display in displays) {
          for (final bool p5 in const <bool>[true, false]) {
            for (final HdrDataSpaceExtInfo? ext in extensions) {
              final HdrCapabilities capabilities =
                  caps(displayHdrTypes: display, p5: p5, ext: ext);
              final HdrRoutePrediction prediction = HdrRoutePlanner.plan(
                  source: source, capabilities: capabilities, policy: policy);
              checkInvariants(prediction, cls: cls, capabilities: capabilities);
              // An explicit default policy is identical to omitting the
              // policy: admission has no switch (v7.3), so every route and
              // error equals the implicit prediction.
              final HdrRoutePrediction defaults = HdrRoutePlanner.plan(
                  source: source, capabilities: capabilities);
              expect(prediction.selected, defaults.selected,
                  reason: '$cls display: $display p5: $p5 ext: $ext');
              expect(prediction.playable, defaults.playable);
              for (final HdrCandidate candidate in prediction.candidates) {
                // Nothing is refused by the removed maturity gate: dvP5 and
                // dvP84 nativeDolbyVision proceed to the realizer
                // (display/decoder/bridge grounds); other classes keep the
                // R7 refusal, locked by the maturity table test.
                expect(candidate.skipReason,
                    isNot(HdrDegradeReason.experimentalStrategySkipped),
                    reason: '$candidate');
              }
              combos++;
            }
          }
        }
      }
      expect(combos, 504);
    });

    test(
        'API 24/25 use copy for texture routes; without the GPU HDR dataspace '
        'the HDR list blocks', () {
      const HdrRoutingPolicy convertFirst = HdrRoutingPolicy(
        preferences: <HdrSourceClass, List<HdrStrategy>>{
          HdrSourceClass.hlg: <HdrStrategy>[
            HdrStrategy.baseLayerConvert,
            HdrStrategy.metadataReshape,
            HdrStrategy.toneMapSdr,
          ],
        },
      );
      for (final int sdk in <int>[24, 25]) {
        // Default-enabled sdrEmbed (2026-10-17 product decision): the plain
        // SDR prediction selects the decoder-composited embed execution;
        // the texture carrier head stays copy and the explicit false opt-out
        // restores exactly the pre-default texture prediction.
        final HdrRoutePrediction sdr =
            caps(sdkInt: sdk).predict(sources[HdrSourceClass.sdr]!);
        expect(sdr.selected.route!.vo, 'mediacodec_embed');
        expect(sdr.selected.route!.hwdec, 'mediacodec');
        final HdrRoutePrediction texture = caps(sdkInt: sdk).predict(
          sources[HdrSourceClass.sdr]!,
          options: EffectiveVideoRouteOptions.resolve(
              application: const VideoRouteOptions(sdrEmbed: false)),
        );
        expect(texture.selected.route!.hwdec, 'mediacodec-copy');
        expect(texture.selected.route!.dependencies, <String>{
          HdrRouteDependency.hwdecMediacodecCopy,
          HdrRouteDependency.decoderMediacodec,
          HdrRouteDependency.importCpuUpload,
          HdrRouteDependency.presenterGpuTexture
        });

        final HdrRoutePrediction hdr = caps(sdkInt: sdk).predict(
          sources[HdrSourceClass.hlg]!,
          policy: convertFirst,
        );
        // Canonical stage order: the C2 reshape (an ordinary HLG stream has
        // no dynamic metadata to rebuild) is evaluated first and refuses as
        // unsupported; the C4 conversion then reports the missing GPU HDR
        // dataspace.
        expect(hdr.candidates[0].strategy, HdrStrategy.metadataReshape);
        expect(hdr.candidates[0].skipReason,
            HdrDegradeReason.unsupportedStrategy);
        expect(hdr.candidates[1].strategy, HdrStrategy.baseLayerConvert);
        expect(hdr.candidates[1].skipReason,
            HdrDegradeReason.gpuHdrDataSpaceUnavailable);
        // The display is HDR-capable: once the HDR candidates are refused on
        // the dataspace ground the plan blocks — no tone-map fallback is
        // synthesized (MK-ROUTING-20261011). The blocking selection is the
        // first rejected entry of the caller's preference order (the C4
        // conversion here), while the candidate list is displayed in
        // canonical stage order.
        expect(hdr.playable, isFalse);
        expect(hdr.selected.strategy, HdrStrategy.baseLayerConvert);
        expect(hdr.selected.skipReason,
            HdrDegradeReason.gpuHdrDataSpaceUnavailable);
        expect(hdr.selected.route, isNull);

        // Decoder-composited output does not rely on the unavailable GPU
        // dataspace API and remains a candidate on these Android versions.
        final HdrRoutePrediction direct =
            caps(sdkInt: sdk).predict(sources[HdrSourceClass.hdr10]!);
        expect(direct.selected.strategy, HdrStrategy.baseLayerDirect);
        expect(direct.selected.route!.vo, 'mediacodec_embed');
      }
    });

    test(
        'API 26/27 keep MediaCodec texture routes; without the GPU HDR '
        'dataspace the HDR list blocks', () {
      const HdrRoutingPolicy convertFirst = HdrRoutingPolicy(
        preferences: <HdrSourceClass, List<HdrStrategy>>{
          HdrSourceClass.hlg: <HdrStrategy>[
            HdrStrategy.baseLayerConvert,
            HdrStrategy.metadataReshape,
            HdrStrategy.toneMapSdr,
          ],
        },
      );
      for (final int sdk in <int>[26, 27]) {
        final HdrRoutePrediction sdr =
            caps(sdkInt: sdk).predict(sources[HdrSourceClass.sdr]!);
        expect(sdr.selected.route!.hwdec, 'mediacodec');
        expect(sdr.selected.route!.dependencies, <String>{
          HdrRouteDependency.hwdecMediacodec,
          HdrRouteDependency.decoderMediacodec,
          HdrRouteDependency.importMediacodec,
          HdrRouteDependency.presenterGpuTexture
        });

        final HdrRoutePrediction hdr = caps(sdkInt: sdk).predict(
          sources[HdrSourceClass.hlg]!,
          policy: convertFirst,
        );
        // Canonical stage order: the C2 reshape refuses as unsupported for a
        // dynamic-metadata-free HLG stream; the C4 conversion reports the
        // missing GPU HDR dataspace.
        expect(hdr.candidates[0].strategy, HdrStrategy.metadataReshape);
        expect(hdr.candidates[0].skipReason,
            HdrDegradeReason.unsupportedStrategy);
        expect(hdr.candidates[1].strategy, HdrStrategy.baseLayerConvert);
        expect(hdr.candidates[1].skipReason,
            HdrDegradeReason.gpuHdrDataSpaceUnavailable);
        // The display is HDR-capable: the exhausted HDR list blocks instead
        // of falling through to a tone-map route (MK-ROUTING-20261011). The
        // blocking selection is the first rejected entry of the caller's
        // preference order; the candidate list is in canonical stage order.
        expect(hdr.playable, isFalse);
        expect(hdr.selected.strategy, HdrStrategy.baseLayerConvert);
        expect(hdr.selected.skipReason,
            HdrDegradeReason.gpuHdrDataSpaceUnavailable);
        expect(hdr.selected.route, isNull);
      }
    });

    test('API 28+ enables GPU HDR routes; sdk 0 makes no legacy assumption',
        () {
      const HdrRoutingPolicy convertFirst = HdrRoutingPolicy(
        preferences: <HdrSourceClass, List<HdrStrategy>>{
          HdrSourceClass.hlg: <HdrStrategy>[
            HdrStrategy.baseLayerConvert,
            HdrStrategy.metadataReshape,
            HdrStrategy.toneMapSdr,
          ],
        },
      );
      for (final int sdk in <int>[28, 29, 34]) {
        final HdrRoutePrediction hdr = caps(sdkInt: sdk).predict(
          sources[HdrSourceClass.hlg]!,
          policy: convertFirst,
        );
        expect(hdr.selected.strategy, HdrStrategy.baseLayerConvert);
      }
      final HdrRoutePrediction p5At28 = caps(sdkInt: 28).predict(
        sources[HdrSourceClass.dvP5]!,
        policy: const HdrRoutingPolicy(
          preferences: <HdrSourceClass, List<HdrStrategy>>{
            HdrSourceClass.dvP5: <HdrStrategy>[
              HdrStrategy.metadataReshape,
              HdrStrategy.toneMapSdr,
            ],
          },
        ),
      );
      expect(p5At28.selected.strategy, HdrStrategy.metadataReshape);

      final HdrCapabilities unknownSdk = caps(sdkInt: 0);
      expect(
          unknownSdk
              .predict(sources[HdrSourceClass.sdr]!)
              .selected
              .route!
              .hwdec,
          'mediacodec');
      expect(
        unknownSdk
            .predict(sources[HdrSourceClass.hlg]!, policy: convertFirst)
            .selected
            .strategy,
        HdrStrategy.baseLayerConvert,
      );
    });

    test('SDK compatibility never bypasses the P5 pipeline gate or strips RPU',
        () {
      final HdrRoutePrediction unavailable =
          caps(sdkInt: 24, p5: false).predict(sources[HdrSourceClass.dvP5]!);
      expect(unavailable.playable, isFalse);
      // The first preference entry (native DV) reports its own display
      // ground; the pipeline gate refuses every P5-processing strategy
      // independently of the SDK level.
      expect(unavailable.selected.skipReason,
          HdrDegradeReason.displayLacksTransfer);
      expect(
        unavailable.candidates
            .where((candidate) =>
                candidate.strategy != HdrStrategy.nativeDolbyVision)
            .map((candidate) => candidate.skipReason),
        everyElement(HdrDegradeReason.p5PipelineUnavailable),
      );

      final HdrRoutePrediction available =
          caps(sdkInt: 24, p5: true).predict(sources[HdrSourceClass.dvP5]!);
      // SDK compatibility does not unlock the reshape on this device, and
      // the HDR-capable display blocks the SDR-only remainder instead of
      // tone-mapping (MK-ROUTING-20261011).
      expect(available.playable, isFalse);
      expect(available.selected.strategy, HdrStrategy.nativeDolbyVision);
      expect(
          available.selected.skipReason, HdrDegradeReason.displayLacksTransfer);
      expect(
        available.candidates
            .firstWhere((candidate) =>
                candidate.strategy == HdrStrategy.metadataReshape)
            .skipReason,
        HdrDegradeReason.gpuHdrDataSpaceUnavailable,
      );
      // Realizer-level pin: the P5 tone-map execution keeps its RPU (the
      // rescale pipeline applies it) and copies frames at SDK 24 — SDK
      // compatibility never strips the RPU.
      final List<HdrStrategyRealization> toneMapExecutions =
          HdrStrategyRealizer.realizeCandidates(
        HdrStrategy.toneMapSdr,
        source: sources[HdrSourceClass.dvP5]!,
        sourceClass: HdrSourceClass.dvP5,
        capabilities: caps(sdkInt: 24, p5: true),
      );
      final HdrRoute copyRoute = toneMapExecutions.first.route!;
      expect(copyRoute.hwdec, 'mediacodec-copy');
      expect(copyRoute.appliesDynamicMetadata, isTrue);
      expect(copyRoute.stripDvRpu, isFalse);
      expect(
        copyRoute.dependencies,
        <String>{
          HdrRouteDependency.hwdecMediacodecCopy,
          HdrRouteDependency.decoderMediacodec,
          HdrRouteDependency.importCpuUpload,
          HdrRouteDependency.presenterGpuTexture
        },
      );
    });

    test('"HDR first, tone-map last" holds for every combo (verification 2)',
        () {
      var checked = 0;
      const HdrRoutingPolicy policy = HdrRoutingPolicy.defaults;
      for (final HdrSourceClass cls in HdrSourceClass.values) {
        final HdrSourceDescriptor source = sources[cls]!;
        for (final Set<int>? display in displays) {
          for (final bool p5 in const <bool>[true, false]) {
            final HdrCapabilities capabilities =
                caps(displayHdrTypes: display, p5: p5);
            final HdrRoutePrediction prediction = HdrRoutePlanner.plan(
              source: source,
              capabilities: capabilities,
              policy: policy,
            );
            checkInvariants(prediction, cls: cls, capabilities: capabilities);
            checked++;
          }
        }
      }
      // 12 classes × 7 displays × 2 P5 pipelines. The extension dimension
      // is irrelevant to this property (it only moves confidence) and is
      // covered by the matrix tests.
      expect(checked, 168);
    });

    test('classes without a preference row synthesize a blocking placeholder',
        () {
      // dvP10 (AV1) is out of Phase 1 scope and has no default preference
      // row, so with no caller override the candidate directory starts
      // empty. On an HDR-capable display no SDR fallback may be synthesized
      // either: the planner must still return a well-formed blocked
      // prediction with a typed reason and no route.
      final HdrCapabilities lya = lyaCaps();
      final HdrRoutePrediction prediction =
          lya.predict(sources[HdrSourceClass.dvP10]!);
      expect(prediction.playable, isFalse);
      expect(prediction.selected.feasible, isFalse);
      expect(prediction.selected.route, isNull);
      expect(prediction.selected.maturity, HdrStrategyMaturity.unsupported);
      expect(prediction.selected.skipReason,
          HdrDegradeReason.unsupportedStrategy);
      expect(prediction.candidates, <HdrCandidate>[prediction.selected]);
      checkInvariants(prediction, cls: HdrSourceClass.dvP10, capabilities: lya);
      // The unresolved-DV flavor of the same empty-directory path reports
      // its own source-ground reason.
      expect(
        lya.predict(sources[HdrSourceClass.dvUnknown]!).selected.skipReason,
        HdrDegradeReason.sourceMetadataUnknown,
      );
    });

    test('hdr10Plus plans through the fixed catalog; C1/C2 errors stay '
        'visible while the baseline plays', () {
      // v7.3 gives hdr10Plus a default row (native C1 + reshape C2 +
      // baseline). The missing implementations are explicit typed errors,
      // not silent deletions, and the C3 PQ baseline still plays.
      final HdrCapabilities lya = lyaCaps();
      final HdrRoutePrediction prediction =
          lya.predict(sources[HdrSourceClass.hdr10Plus]!);
      expect(prediction.playable, isTrue);
      expect(prediction.candidates[0].strategy, HdrStrategy.nativeHdr10Plus);
      expect(prediction.candidates[0].stage, HdrRouteStage.c1);
      expect(prediction.candidates[0].status, HdrCandidateStatus.error);
      expect(prediction.candidates[0].skipReason,
          HdrDegradeReason.routeNotImplemented);
      expect(prediction.candidates[1].strategy, HdrStrategy.metadataReshape);
      expect(prediction.candidates[1].stage, HdrRouteStage.c2);
      expect(prediction.candidates[1].status, HdrCandidateStatus.error);
      expect(prediction.candidates[1].skipReason,
          HdrDegradeReason.routeNotImplemented);
      expect(prediction.selected.strategy, HdrStrategy.baseLayerDirect);
      expect(prediction.selected.stage, HdrRouteStage.c3);
      expect(prediction.selected.route!.outputTransfer, HdrOutputTransfer.pq);
      checkInvariants(prediction,
          cls: HdrSourceClass.hdr10Plus, capabilities: lya);
    });
  });

  group('maturity labels are diagnostic (verification 3)', () {
    test('P7 plans to the C3 baseline direct by default, without any switch',
        () {
      final HdrCapabilities lya = lyaCaps();
      // P7: native DV keeps the R7 refusal and the reshape refuses on the
      // unknown enhancement layer; the C3 baseline direct is evaluated like
      // every applicable path (v7.3 removed the maturity admission gate).
      // The tone-map entries are refused by the HDR-capable display.
      final HdrRoutePrediction prediction =
          lya.predict(sources[HdrSourceClass.dvP7]!);
      expect(prediction.playable, isTrue);
      expect(prediction.selected.strategy, HdrStrategy.baseLayerDirect);
      expect(prediction.selected.maturity, HdrStrategyMaturity.experimental);
      expect(prediction.candidates[0].strategy, HdrStrategy.nativeDolbyVision);
      expect(prediction.candidates[0].skipReason,
          HdrDegradeReason.unsupportedStrategy);
      expect(prediction.candidates[1].strategy, HdrStrategy.metadataReshape);
      expect(prediction.candidates[1].skipReason,
          HdrDegradeReason.unsupportedStrategy);
      expect(prediction.candidates[2].strategy, HdrStrategy.baseLayerDirect);
      expect(prediction.candidates[2].skipReason, isNull);
      for (final int blocked in const <int>[3, 4, 5]) {
        expect(prediction.candidates[blocked].strategy, HdrStrategy.toneMapSdr,
            reason: 'candidate $blocked');
        expect(prediction.candidates[blocked].feasible, isFalse,
            reason: 'candidate $blocked');
      }
      checkInvariants(prediction, cls: HdrSourceClass.dvP7, capabilities: lya);
    });

    test('an explicit default policy selects the identical P7 route', () {
      final HdrCapabilities lya = lyaCaps();
      final HdrRoutePrediction prediction = lya.predict(
        sources[HdrSourceClass.dvP7]!,
        policy: HdrRoutingPolicy.defaults,
      );
      expect(prediction.selected.strategy, HdrStrategy.baseLayerDirect);
      expect(prediction.selected.maturity, HdrStrategyMaturity.experimental);
      expect(prediction.selected.route!.vo, 'mediacodec_embed');
      expect(prediction.selected.route!.outputTransfer, HdrOutputTransfer.pq);
      // Passing the default policy cannot change the plan.
      expect(prediction, lya.predict(sources[HdrSourceClass.dvP7]!));
      checkInvariants(prediction, cls: HdrSourceClass.dvP7, capabilities: lya);
    });

    test('P8.1 takes the C2 reshape ahead of the inherited C3 direct', () {
      final HdrCapabilities lya = lyaCaps();
      final HdrRoutePrediction prediction =
          lya.predict(sources[HdrSourceClass.dvP81]!);
      // Canonical DV order (4e6b29ab): the C2 reshape is evaluated before
      // the C3 baseline and is feasible on this PQ-capable display.
      expect(prediction.selected.strategy, HdrStrategy.metadataReshape);
      expect(prediction.selected.stage, HdrRouteStage.c2);
      expect(prediction.selected.route!.outputTransfer, HdrOutputTransfer.pq);
      expect(prediction.playable, isTrue);
      // The inherited direct route stays a feasible C3 fallback; its
      // maturity label remains diagnostic.
      final HdrCandidate direct = prediction.candidates.firstWhere(
          (HdrCandidate c) => c.strategy == HdrStrategy.baseLayerDirect);
      expect(direct.feasible, isTrue);
      expect(direct.maturity, HdrStrategyMaturity.inherited);
      expect(direct.stage, HdrRouteStage.c3);
    });

    test('dvP5 reaches nativeDolbyVision by default (2026-10-10 promotion)',
        () {
      // DV-capable device (declares DV, profile-32 hardware decoder, bridge
      // v1) with the default policy: the P5 source goes straight to the
      // native route — the old behavior (skip with
      // experimentalStrategySkipped unless a switch was set) is gone.
      final HdrRoutePrediction prediction = caps(
        displayHdrTypes: const <int>{1},
        dvDecoders: const <HdrDecoderInfo>[nativeDvDecoder],
        nativeDvBridgeApi: 1,
      ).predict(sources[HdrSourceClass.dvP5]!);
      expect(prediction.selected.strategy, HdrStrategy.nativeDolbyVision);
      expect(prediction.selected.maturity, HdrStrategyMaturity.verified);
      expect(prediction.selected.skipReason, isNull);
      expect(
          prediction.candidates.first.strategy, HdrStrategy.nativeDolbyVision);
      expect(prediction.candidates.first.skipReason, isNull);
      expect(prediction.selected.route!.vdLavcOptions, 'native_dv=1');
      expect(prediction.playable, isTrue);
      checkInvariants(prediction,
          cls: HdrSourceClass.dvP5,
          capabilities: caps(
            displayHdrTypes: const <int>{1},
            dvDecoders: const <HdrDecoderInfo>[nativeDvDecoder],
            nativeDvBridgeApi: 1,
          ));

      // Contrast (scope red line): on the same device the R7-reserved
      // classes never route natively — dvP81's nativeDolbyVision stays
      // realizer-refused (unsupportedStrategy), legacy switch state aside.
      final HdrRoutePrediction p81 = caps(
        displayHdrTypes: const <int>{1, 2},
        dvDecoders: const <HdrDecoderInfo>[nativeDvDecoder],
        nativeDvBridgeApi: 1,
      ).predict(sources[HdrSourceClass.dvP81]!);
      final HdrCandidate p81Native = p81.candidates.firstWhere(
          (HdrCandidate c) => c.strategy == HdrStrategy.nativeDolbyVision);
      expect(p81Native.maturity, HdrStrategyMaturity.unsupported);
      expect(p81Native.skipReason, HdrDegradeReason.unsupportedStrategy);
      expect(p81.selected.strategy, isNot(HdrStrategy.nativeDolbyVision));
    });

    test(
        'dvP84 reaches nativeDolbyVision by default on capable caps; a panel '
        'without DV declaration takes the C2 reshape', () {
      // marble r30g acceptance promoted this cell: with the default policy a
      // DV-capable device takes the P8.4 native route — immediate release
      // (boolean render mode), unlike P5's timed one.
      final HdrRoutePrediction prediction = caps(
        displayHdrTypes: const <int>{1, 2},
        dvDecoders: const <HdrDecoderInfo>[nativeDvDecoder],
        nativeDvBridgeApi: 1,
      ).predict(sources[HdrSourceClass.dvP84]!);
      expect(prediction.selected.strategy, HdrStrategy.nativeDolbyVision);
      expect(prediction.selected.maturity, HdrStrategyMaturity.verified);
      expect(prediction.selected.skipReason, isNull);
      expect(prediction.selected.route!.mediacodecEmbedRenderMode, 'boolean');
      expect(prediction.selected.route!.vdLavcOptions, 'native_dv=1');
      expect(prediction.playable, isTrue);

      // This fixture is an HLG-capable display without DV, not the LG
      // display (which declares DV and PQ, but not HLG). Decoder and
      // display requirements are independent: the native entry is refused
      // on the display ground, and the canonical order then selects the
      // C2 reshape (which precedes the C3 baseline).
      final HdrRoutePrediction noDvSignaling = caps(
        displayHdrTypes: const <int>{2, 3},
        dvDecoders: const <HdrDecoderInfo>[nativeDvDecoder],
        nativeDvBridgeApi: 1,
      ).predict(sources[HdrSourceClass.dvP84]!);
      final HdrCandidate native = noDvSignaling.candidates.firstWhere(
          (HdrCandidate c) => c.strategy == HdrStrategy.nativeDolbyVision);
      expect(native.maturity, HdrStrategyMaturity.verified);
      expect(native.skipReason, HdrDegradeReason.displayLacksTransfer);
      expect(noDvSignaling.selected.strategy, HdrStrategy.metadataReshape);
      expect(noDvSignaling.selected.stage, HdrRouteStage.c2);
      expect(
          noDvSignaling.selected.route!.outputTransfer, HdrOutputTransfer.pq);
      // The HLG direct remains a feasible C3 fallback.
      final HdrCandidate direct = noDvSignaling.candidates.firstWhere(
          (HdrCandidate c) => c.strategy == HdrStrategy.baseLayerDirect);
      expect(direct.feasible, isTrue);
      expect(direct.route!.outputTransfer, HdrOutputTransfer.hlg);
    });

    test('HDR10 PQ base cannot enter C4 even when requested first', () {
      final prediction = lyaCaps().predict(sources[HdrSourceClass.hdr10]!);
      final convert = prediction.candidates.firstWhere(
          (HdrCandidate c) => c.strategy == HdrStrategy.baseLayerConvert);
      expect(convert.maturity, HdrStrategyMaturity.verified);
      expect(convert.feasible, isFalse);
      expect(convert.skipReason, HdrDegradeReason.unsupportedStrategy);

      const convertFirst = HdrRoutingPolicy(
        preferences: <HdrSourceClass, List<HdrStrategy>>{
          HdrSourceClass.hdr10: <HdrStrategy>[
            HdrStrategy.baseLayerConvert,
            HdrStrategy.baseLayerDirect,
            HdrStrategy.toneMapSdr,
          ],
        },
      );
      final preferred = lyaCaps().predict(
          sources[HdrSourceClass.hdr10]!, policy: convertFirst);
      // A caller preference cannot make PQ->PQ masquerade as conversion, and
      // the fixed stage order keeps the C4 entry behind the same-stage C1
      // direct even when it is listed first.
      expect(preferred.candidates.first.strategy, HdrStrategy.baseLayerDirect);
      expect(preferred.candidates.first.stage, HdrRouteStage.c1);
      expect(preferred.candidates.first.feasible, isTrue);
      expect(preferred.selected.strategy, HdrStrategy.baseLayerDirect);
      final HdrCandidate preferredConvert = preferred.candidates.firstWhere(
          (HdrCandidate c) => c.strategy == HdrStrategy.baseLayerConvert);
      expect(preferredConvert.skipReason, HdrDegradeReason.unsupportedStrategy);
    });

    test('hdr10 carries no dynamic metadata, so a C2-first row cannot '
        'select the reshape', () {
      // The maturity label of hdr10 × metadataReshape says verified, but
      // labels are diagnostic (v7.3): an ordinary HDR10 stream has no
      // dynamic metadata to rebuild and the realizer refuses the C2 entry
      // structurally. On this HDR-capable display the exhausted list then
      // blocks — the rejected C2 entry records the reason.
      const HdrRoutingPolicy reshapeFirst = HdrRoutingPolicy(
        preferences: <HdrSourceClass, List<HdrStrategy>>{
          HdrSourceClass.hdr10: <HdrStrategy>[
            HdrStrategy.metadataReshape,
            HdrStrategy.toneMapSdr,
          ],
        },
      );
      final HdrRoutePrediction prediction = lyaCaps()
          .predict(sources[HdrSourceClass.hdr10]!, policy: reshapeFirst);
      expect(prediction.playable, isFalse);
      expect(prediction.selected.strategy, HdrStrategy.metadataReshape);
      expect(prediction.selected.stage, HdrRouteStage.c2);
      expect(prediction.selected.maturity, HdrStrategyMaturity.verified);
      expect(prediction.selected.skipReason,
          HdrDegradeReason.unsupportedStrategy);
      expect(prediction.selected.route, isNull);
      for (final HdrCandidate candidate in prediction.candidates) {
        expect(candidate.feasible, isFalse, reason: '$candidate');
      }
    });

    test(
        'nativeDolbyVision stays unselected on a non-DV display, even first '
        'in preferences', () {
      final HdrCapabilities lya = lyaCaps();
      const HdrRoutingPolicy policy = HdrRoutingPolicy(
        preferences: <HdrSourceClass, List<HdrStrategy>>{
          HdrSourceClass.hdr10: <HdrStrategy>[
            HdrStrategy.nativeDolbyVision,
            HdrStrategy.baseLayerDirect,
            HdrStrategy.toneMapSdr,
          ],
          HdrSourceClass.dvP5: <HdrStrategy>[
            HdrStrategy.nativeDolbyVision,
            HdrStrategy.metadataReshape,
            HdrStrategy.toneMapSdr,
          ],
        },
      );
      final HdrRoutePrediction hdr10 =
          lya.predict(sources[HdrSourceClass.hdr10]!, policy: policy);
      expect(hdr10.selected.strategy, HdrStrategy.baseLayerDirect);
      // Both entries are C1 for an HDR10 source; within one stage the
      // feasible direct ranks ahead of the refused native entry, which
      // stays visible with its reason.
      final HdrCandidate hdr10Native = hdr10.candidates.firstWhere(
          (HdrCandidate c) => c.strategy == HdrStrategy.nativeDolbyVision);
      expect(hdr10Native.stage, HdrRouteStage.c1);
      expect(hdr10Native.skipReason, HdrDegradeReason.unsupportedStrategy);

      final HdrRoutePrediction p5 =
          lya.predict(sources[HdrSourceClass.dvP5]!, policy: policy);
      expect(p5.selected.strategy, HdrStrategy.metadataReshape);
      // LYA declares no Dolby Vision display: after the dvP5 unlock the
      // reserved strategy participates but the realizer refuses it on the
      // display-transfer ground.
      expect(p5.candidates.first.skipReason,
          HdrDegradeReason.displayLacksTransfer);
    });
  });

  group('excluded stages and degradation (verification 4)', () {
    test('P8.4 on an HDR10-only display: C2 reshape first, C4 HLG-to-PQ '
        'conversion feasible', () {
      // The HDR10-only report is a real PQ display: the HLG compatibility
      // base layer of P8.4 may convert to PQ (C4), and the canonical DV
      // order selects the C2 reshape before the C3 baseline.
      final HdrRoutePrediction prediction = HdrRoutePlanner.plan(
        source: sources[HdrSourceClass.dvP84]!,
        capabilities: caps(displayHdrTypes: const <int>{2}),
      );
      expect(prediction.selected.strategy, HdrStrategy.metadataReshape);
      expect(prediction.selected.stage, HdrRouteStage.c2);
      expect(prediction.selected.route!.outputTransfer, HdrOutputTransfer.pq);
      expect(prediction.selected.route!.surfaceTransfer, 'pq');
      expect(prediction.selected.route!.stripDvRpu, isFalse);
      expect(prediction.selected.route!.dependencies,
          contains(HdrRouteDependency.dataspacePq));
      // The C4 conversion stays feasible: same PQ output, but the ignored
      // RPU must be stripped from the bitstream.
      final HdrCandidate convert = prediction.candidates.firstWhere(
          (HdrCandidate c) => c.strategy == HdrStrategy.baseLayerConvert);
      expect(convert.stage, HdrRouteStage.c4);
      expect(convert.feasible, isTrue);
      expect(convert.route!.outputTransfer, HdrOutputTransfer.pq);
      expect(convert.route!.stripDvRpu, isTrue);
      expect(convert.route!.dependencies,
          contains(HdrRouteDependency.dataspacePq));
    });

    test(
        'PQ dataspace excluded: P8.4 HDR candidates exhaust and the plan '
        'blocks', () {
      final HdrRoutePrediction prediction = HdrRoutePlanner.plan(
        source: sources[HdrSourceClass.dvP84]!,
        capabilities: caps(displayHdrTypes: const <int>{2}),
        excluded: const <String, HdrDegradeReason>{
          HdrRouteDependency.dataspacePq: HdrDegradeReason.dataSpaceApplyFailed,
        },
      );
      // The HDR10-only display is HDR-capable: with every HDR candidate
      // refused there is no tone-map exit — the plan blocks and the first
      // rejected candidate keeps its reason.
      expect(prediction.playable, isFalse);
      expect(prediction.selected.strategy, HdrStrategy.nativeDolbyVision);
      expect(
          prediction.selected.skipReason, HdrDegradeReason.displayLacksTransfer);
      final HdrCandidate direct = prediction.candidates.firstWhere(
          (HdrCandidate c) => c.strategy == HdrStrategy.baseLayerDirect);
      expect(direct.skipReason, HdrDegradeReason.displayLacksTransfer);
      final HdrCandidate convert = prediction.candidates.firstWhere(
          (HdrCandidate c) => c.strategy == HdrStrategy.baseLayerConvert);
      expect(convert.skipReason, HdrDegradeReason.dataSpaceApplyFailed);
      final HdrCandidate reshape = prediction.candidates.firstWhere(
          (HdrCandidate c) => c.strategy == HdrStrategy.metadataReshape);
      expect(reshape.skipReason, HdrDegradeReason.dataSpaceApplyFailed);
      checkInvariants(prediction,
          cls: HdrSourceClass.dvP84,
          capabilities: caps(displayHdrTypes: const <int>{2}));
    });

    test('excluded stage: the reshape reports the carried failure, and the '
        'default policy needs no switch', () {
      final HdrRoutePrediction prediction = HdrRoutePlanner.plan(
        source: sources[HdrSourceClass.dvP84]!,
        capabilities: caps(displayHdrTypes: const <int>{2}),
        excluded: const <String, HdrDegradeReason>{
          HdrRouteDependency.dataspacePq: HdrDegradeReason.dataSpaceApplyFailed,
        },
      );
      final HdrCandidate reshape = prediction.candidates.firstWhere(
          (HdrCandidate c) => c.strategy == HdrStrategy.metadataReshape);
      // Without the maturity gate there is no earlier refusal: the excluded
      // dataspace stage is the reshape's reported reason. The HDR-capable
      // display blocks the exhausted list; the first rejected entry (native
      // DV) is the selection carrying its own reason.
      expect(reshape.skipReason, HdrDegradeReason.dataSpaceApplyFailed);
      expect(prediction.playable, isFalse);
      expect(prediction.selected.strategy, HdrStrategy.nativeDolbyVision);
      expect(
          prediction.selected.skipReason, HdrDegradeReason.displayLacksTransfer);
    });

    test('dataspace exclusion does not touch the direct route', () {
      final HdrRoutePrediction prediction = HdrRoutePlanner.plan(
        source: sources[HdrSourceClass.dvP84]!,
        capabilities: caps(displayHdrTypes: const <int>{2, 3}),
        excluded: const <String, HdrDegradeReason>{
          HdrRouteDependency.dataspacePq: HdrDegradeReason.dataSpaceApplyFailed,
          HdrRouteDependency.dataspaceHlg:
              HdrDegradeReason.dataSpaceApplyFailed,
        },
      );
      // baseLayerDirect has no dataspace dependency; it is still selected.
      expect(prediction.selected.strategy, HdrStrategy.baseLayerDirect);
      expect(prediction.selected.route!.surfaceTransfer, isNull);
    });

    test('dependency tags carry the plan 1.3 literals', () {
      expect(HdrRouteDependency.dataspaceHlg, 'dataspace:hlg');
      expect(HdrRouteDependency.dataspacePq, 'dataspace:pq');
      expect(HdrRouteDependency.hwdecMediacodec, 'hwdec:mediacodec');
      expect(HdrRouteDependency.topologyPlatformView, 'topology:platformView');
    });
  });

  group('prediction/execution homogeneity (verification 5)', () {
    test('predict() equals plan() for every combo with the default policy',
        () {
      var combos = 0;
      const HdrRoutingPolicy policy = HdrRoutingPolicy.defaults;
      for (final HdrSourceClass cls in HdrSourceClass.values) {
        final HdrSourceDescriptor source = sources[cls]!;
        for (final Set<int>? display in displays) {
          for (final bool p5 in const <bool>[true, false]) {
            for (final HdrDataSpaceExtInfo? ext in extensions) {
              final HdrCapabilities capabilities =
                  caps(displayHdrTypes: display, p5: p5, ext: ext);
              final HdrRoutePrediction predicted = capabilities.predict(
                source,
                policy: policy,
              );
              final HdrRoutePrediction planned = HdrRoutePlanner.plan(
                source: source,
                capabilities: capabilities,
                policy: policy,
              );
              expect(predicted, planned,
                  reason: '$cls display: $display p5: $p5 ext: $ext');
              combos++;
            }
          }
        }
      }
      expect(combos, 504);
    });

    test('predict() default arguments use the default policy and auto', () {
      final HdrCapabilities capabilities = lyaCaps();
      expect(
        capabilities.predict(sources[HdrSourceClass.hdr10]!),
        HdrRoutePlanner.plan(
          source: sources[HdrSourceClass.hdr10]!,
          capabilities: capabilities,
        ),
      );
    });
  });

  group('LYA-AL00 snapshot (verification 6, S2 measured values)', () {
    test(
        'HDR10 takes mediacodec_embed PQ direct; tone-map entries are blocked '
        'on this HDR-capable display', () {
      final HdrRoutePrediction prediction =
          lyaCaps().predict(sources[HdrSourceClass.hdr10]!);
      expect(prediction.selected.strategy, HdrStrategy.baseLayerDirect);
      expect(prediction.selected.maturity, HdrStrategyMaturity.verified);
      expect(prediction.selected.route!.vo, 'mediacodec_embed');
      expect(prediction.selected.route!.hwdec, 'mediacodec');
      expect(prediction.selected.route!.outputTransfer, HdrOutputTransfer.pq);
      expect(prediction.selected.route!.surfaceTransfer, isNull);
      expect(prediction.selected.route!.stripDvRpu, isFalse);
      expect(prediction.presentation, HdrPresentation.nativeHdr);
      expect(prediction.confidence, HdrPredictionConfidence.verified);
      expect(prediction.playable, isTrue);
      expect(
        prediction.candidates.map((HdrCandidate c) => c.strategy).toList(),
        <HdrStrategy>[
          HdrStrategy.baseLayerDirect,
          HdrStrategy.baseLayerConvert,
          HdrStrategy.toneMapSdr,
          HdrStrategy.toneMapSdr,
          HdrStrategy.toneMapSdr
        ],
      );
      // Default policy: direct and the PQ conversion (verified 2026-10-10,
      // the preferGpuOutput route) are both feasible by default. The
      // tone-map entries are refused: this HDR-capable display never
      // receives an implicit SDR output (MK-ROUTING-20261011).
      expect(prediction.candidates[1].skipReason,
          HdrDegradeReason.unsupportedStrategy);
      expect(prediction.candidates[1].feasible, isFalse);
      for (final int blocked in const <int>[2, 3, 4]) {
        expect(prediction.candidates[blocked].feasible, isFalse,
            reason: 'candidate $blocked');
        expect(prediction.candidates[blocked].skipReason,
            HdrDegradeReason.displayLacksTransfer,
            reason: 'candidate $blocked');
        expect(prediction.candidates[blocked].route, isNull,
            reason: 'candidate $blocked');
      }
      // The C4 input constraint holds under an explicit default policy too:
      // PQ cannot become an HLG-to-PQ conversion.
      final HdrRoutePrediction switchOn = lyaCaps().predict(
        sources[HdrSourceClass.hdr10]!,
        policy: HdrRoutingPolicy.defaults,
      );
      expect(switchOn.candidates[0].feasible, isTrue);
      expect(switchOn.candidates[1].feasible, isFalse);
      expect(switchOn.candidates[1].skipReason,
          HdrDegradeReason.unsupportedStrategy);
      expect(switchOn.selected, prediction.selected);
    });

    test('P8.4 takes the C2 RPU reshape; the HLG direct stays a C3 fallback',
        () {
      final HdrRoutePrediction prediction =
          lyaCaps().predict(sources[HdrSourceClass.dvP84]!);
      // Canonical DV order: the reshape (C2) is evaluated before the
      // baseline direct (C3) and is feasible on this PQ+HLG display.
      expect(prediction.selected.strategy, HdrStrategy.metadataReshape);
      expect(prediction.selected.stage, HdrRouteStage.c2);
      expect(prediction.selected.route!.outputTransfer, HdrOutputTransfer.pq);
      expect(prediction.selected.route!.appliesDynamicMetadata, isTrue);
      expect(prediction.selected.route!.stripDvRpu, isFalse);
      expect(prediction.presentation, HdrPresentation.nativeHdr);
      expect(prediction.playable, isTrue);
      // The verified HLG direct route remains a feasible C3 fallback.
      final HdrCandidate direct = prediction.candidates.firstWhere(
          (HdrCandidate c) => c.strategy == HdrStrategy.baseLayerDirect);
      expect(direct.feasible, isTrue);
      expect(direct.maturity, HdrStrategyMaturity.verified);
      expect(direct.stage, HdrRouteStage.c3);
      expect(direct.route!.outputTransfer, HdrOutputTransfer.hlg);
      expect(direct.route!.stripDvRpu, isFalse);
    });

    test('tone-map texture execution matches the Texture branch of decide', () {
      // The planner no longer emits the tone-map route on an HDR-capable
      // display (MK-ROUTING-20261011): the execution contract is pinned at
      // the realizer, which is where it is produced.
      final HdrStrategyRealization toneMap = HdrStrategyRealizer.realize(
        HdrStrategy.toneMapSdr,
        source: sources[HdrSourceClass.dvP84]!,
        sourceClass: HdrSourceClass.dvP84,
        capabilities: lyaCaps(),
      );
      expect(toneMap.route, isNotNull);
      expect(toneMap.route!.vo, 'gpu-next');
      expect(toneMap.route!.hwdec, 'mediacodec');
      expect(toneMap.route!.topology, HdrTopology.texture);
      expect(toneMap.route!.targetPrim, 'bt.709');
      expect(toneMap.route!.targetTrc, 'bt.1886');
      expect(toneMap.route!.surfaceTransfer, isNull);
      expect(toneMap.route!.stripDvRpu, isTrue);
      // In the plan the strategy stays listed but is refused: this
      // HDR-capable display never receives the tone-mapped output.
      final HdrRoutePrediction prediction =
          lyaCaps().predict(sources[HdrSourceClass.dvP84]!);
      for (final HdrCandidate candidate in prediction.candidates) {
        if (candidate.strategy != HdrStrategy.toneMapSdr) continue;
        expect(candidate.feasible, isFalse, reason: '$candidate');
        expect(candidate.route, isNull, reason: '$candidate');
        expect(candidate.skipReason, HdrDegradeReason.displayLacksTransfer,
            reason: '$candidate');
      }
    });

    test('P5 takes the verified RPU reshape with verified confidence', () {
      final HdrRoutePrediction prediction =
          lyaCaps().predict(sources[HdrSourceClass.dvP5]!);
      expect(prediction.selected.strategy, HdrStrategy.metadataReshape);
      expect(prediction.selected.maturity, HdrStrategyMaturity.verified);
      expect(prediction.selected.route!.vo, 'gpu-next');
      expect(prediction.selected.route!.topology, HdrTopology.platformView);
      expect(prediction.selected.route!.surfaceTransfer, 'pq');
      expect(prediction.selected.route!.targetTrc, 'pq');
      expect(prediction.selected.route!.appliesDynamicMetadata, isTrue);
      expect(prediction.selected.route!.stripDvRpu, isFalse);
      expect(prediction.confidence, HdrPredictionConfidence.verified);
      expect(prediction.playable, isTrue);
    });

    test('P8.1 snapshot: the C2 reshape wins over the inherited direct', () {
      final HdrRoutePrediction prediction =
          lyaCaps().predict(sources[HdrSourceClass.dvP81]!);
      expect(prediction.selected.strategy, HdrStrategy.metadataReshape);
      expect(prediction.selected.stage, HdrRouteStage.c2);
      expect(prediction.selected.route!.outputTransfer, HdrOutputTransfer.pq);
      expect(prediction.playable, isTrue);
      // The inherited C3 direct stays available as the next baseline.
      final HdrCandidate direct = prediction.candidates.firstWhere(
          (HdrCandidate c) => c.strategy == HdrStrategy.baseLayerDirect);
      expect(direct.feasible, isTrue);
      expect(direct.maturity, HdrStrategyMaturity.inherited);
      expect(direct.route!.outputTransfer, HdrOutputTransfer.pq);
    });

    test('P5 without the pipeline is never playable, tone-map included', () {
      final HdrCapabilities capabilities = caps(p5: false, ext: extApplicable);
      final HdrRoutePrediction prediction =
          capabilities.predict(sources[HdrSourceClass.dvP5]!);
      expect(prediction.playable, isFalse);
      expect(prediction.selected.feasible, isFalse);
      expect(prediction.selected.route, isNull);
      // The first preference entry (native DV) reports its own display
      // ground; the pipeline gate refuses reshape and tone-map alike, and on
      // this HDR-capable display no safety net is synthesized.
      expect(prediction.selected.skipReason,
          HdrDegradeReason.displayLacksTransfer);
      expect(prediction.candidates.first, prediction.selected);
      expect(
        prediction.candidates
            .where((candidate) =>
                candidate.strategy != HdrStrategy.nativeDolbyVision)
            .map((candidate) => candidate.skipReason),
        everyElement(HdrDegradeReason.p5PipelineUnavailable),
      );
    });

    test('confidence follows the extension for dataspace routes (R1.5)', () {
      final HdrSourceDescriptor p5 = sources[HdrSourceClass.dvP5]!;
      final HdrSourceDescriptor hdr10 = sources[HdrSourceClass.hdr10]!;
      // PQ dataspace route without an applicable extension: unverified.
      expect(
        caps(displayHdrTypes: const <int>{2}).predict(p5).confidence,
        HdrPredictionConfidence.unverified,
      );
      expect(
        caps(displayHdrTypes: const <int>{2}, ext: extNotApplicable)
            .predict(p5)
            .confidence,
        HdrPredictionConfidence.unverified,
      );
      // A registered and applicable extension covers the dataspace.
      expect(
        caps(displayHdrTypes: const <int>{2}, ext: extApplicable)
            .predict(p5)
            .confidence,
        HdrPredictionConfidence.verified,
      );
      // No dataspace dependency: verified regardless of any extension.
      expect(
        caps(displayHdrTypes: const <int>{2}).predict(hdr10).confidence,
        HdrPredictionConfidence.verified,
      );
    });

    test('confidence consumes the declared capability, never the id (R1.5)',
        () {
      final HdrSourceDescriptor p5 = sources[HdrSourceClass.dvP5]!;
      // An unknown extension id with the explicit validated-prediction
      // declaration verifies the pq dataspace route.
      expect(
        caps(
          displayHdrTypes: const <int>{2},
          ext: const HdrDataSpaceExtInfo(
              id: 'unknown-vendor',
              applicable: true,
              validatedPredictionTransfers: <String>{'pq'}),
        ).predict(p5).confidence,
        HdrPredictionConfidence.verified,
      );
      // A familiar id without the declaration stays unverified: the id is
      // inert data, only the capability counts.
      expect(
        caps(
          displayHdrTypes: const <int>{2},
          ext: const HdrDataSpaceExtInfo(id: 'lya-pq', applicable: true),
        ).predict(p5).confidence,
        HdrPredictionConfidence.unverified,
      );
      // A declared transfer that does not match the route's requested
      // surface transfer stays unverified.
      expect(
        caps(
          displayHdrTypes: const <int>{2},
          ext: const HdrDataSpaceExtInfo(
              id: 'lya-pq',
              applicable: true,
              validatedPredictionTransfers: <String>{'hlg'}),
        ).predict(p5).confidence,
        HdrPredictionConfidence.unverified,
      );
    });
  });

  group('custom preferences and off (verification 7)', () {
    test('P8.4 with metadataReshape first follows the override (A6)', () {
      const HdrRoutingPolicy policy = HdrRoutingPolicy(
        preferences: <HdrSourceClass, List<HdrStrategy>>{
          HdrSourceClass.dvP84: <HdrStrategy>[
            HdrStrategy.metadataReshape,
            HdrStrategy.baseLayerDirect,
            HdrStrategy.toneMapSdr,
          ],
        },
      );
      final HdrRoutePrediction prediction =
          lyaCaps().predict(sources[HdrSourceClass.dvP84]!, policy: policy);
      expect(prediction.selected.strategy, HdrStrategy.metadataReshape);
      expect(prediction.selected.route!.surfaceTransfer, 'pq');
      expect(prediction.selected.route!.appliesDynamicMetadata, isTrue);
      // The override row replaces the class catalog: the C4 conversion entry
      // the default row carries is gone from the plan.
      expect(
        prediction.candidates
            .where((HdrCandidate c) =>
                c.strategy == HdrStrategy.baseLayerConvert)
            .toList(),
        isEmpty,
      );
      // Since 4e6b29ab the canonical default order already evaluates C2
      // before C3, so the default policy selects the same reshaping route.
      expect(
          lyaCaps().predict(sources[HdrSourceClass.dvP84]!).selected.strategy,
          HdrStrategy.metadataReshape);
    });

    test('an override row selects the reshape without any legacy switch', () {
      const HdrRoutingPolicy policy = HdrRoutingPolicy(
        preferences: <HdrSourceClass, List<HdrStrategy>>{
          HdrSourceClass.dvP84: <HdrStrategy>[
            HdrStrategy.metadataReshape,
            HdrStrategy.baseLayerDirect,
            HdrStrategy.toneMapSdr,
          ],
        },
      );
      final HdrRoutePrediction prediction =
          lyaCaps().predict(sources[HdrSourceClass.dvP84]!, policy: policy);
      // The refusal the removed maturity gate used to produce no longer
      // exists anywhere in the plan; the C2 reshape is selected directly.
      expect(prediction.selected.strategy, HdrStrategy.metadataReshape);
      expect(prediction.selected.stage, HdrRouteStage.c2);
      expect(prediction.selected.skipReason, isNull);
      expect(prediction.playable, isTrue);
      expect(
        prediction.candidates
            .map((HdrCandidate c) => c.skipReason)
            .whereType<HdrDegradeReason>()
            .toList(),
        isNot(contains(HdrDegradeReason.experimentalStrategySkipped)),
      );
    });

    test('preference off: HDR sources tone-map, SDR stays direct', () {
      for (final HdrSourceClass cls in HdrSourceClass.values) {
        final HdrRoutePrediction prediction = lyaCaps()
            .predict(sources[cls]!, preference: HdrOutputPreference.off);
        if (cls == HdrSourceClass.sdr) {
          expect(prediction.selected.strategy, HdrStrategy.sdrDirect,
              reason: '$cls');
        } else {
          expect(prediction.selected.strategy, HdrStrategy.toneMapSdr,
              reason: '$cls');
        }
        expect(prediction.playable, cls != HdrSourceClass.dvUnknown,
            reason: '$cls');
        checkInvariants(prediction,
            cls: cls,
            capabilities: lyaCaps(),
            explicitSdrRequest: true);
      }
    });

    test('preference off keeps a pipeline-less P5 unplayable (R3.3)', () {
      final HdrRoutePrediction prediction = caps(p5: false).predict(
          sources[HdrSourceClass.dvP5]!,
          preference: HdrOutputPreference.off);
      expect(prediction.playable, isFalse);
      expect(prediction.selected.skipReason,
          HdrDegradeReason.p5PipelineUnavailable);
    });
  });

  group('route dependency tags (plan 1.3)', () {
    test('each strategy carries its pipeline-stage dependencies', () {
      final HdrCapabilities lya = lyaCaps();
      // Direct (embedded) and reshape (platform view GPU) render on the
      // platform view topology; tone-map/SDR direct render on a texture.
      expect(
        lya
            .predict(sources[HdrSourceClass.hdr10]!)
            .selected
            .route!
            .dependencies,
        <String>{
          HdrRouteDependency.hwdecMediacodec,
          HdrRouteDependency.topologyPlatformView,
          HdrRouteDependency.decoderMediacodec,
        },
      );
      expect(
        lya.predict(sources[HdrSourceClass.dvP5]!).selected.route!.dependencies,
        <String>{
          HdrRouteDependency.hwdecMediacodec,
          HdrRouteDependency.topologyPlatformView,
          HdrRouteDependency.dataspacePq,
          // DV dynamic mapping and PQ presentation are independent failure
          // dependencies; a mapper error must not eliminate C4 HLG→PQ.
          HdrRouteDependency.mapperDolbyVision,
          HdrRouteDependency.decoderMediacodec,
        },
      );
      expect(
        lya.predict(sources[HdrSourceClass.sdr]!).selected.route!.dependencies,
        <String>{
          HdrRouteDependency.hwdecMediacodec,
          HdrRouteDependency.decoderMediacodec,
          HdrRouteDependency.importMediacodec,
          HdrRouteDependency.presenterGpuTexture
        },
      );
      // The tone-map route has no dataspace/platformView dependency. It is
      // obtained through an explicit off request here: the default path on
      // this HDR-capable display blocks once the HDR candidates are
      // exhausted (MK-ROUTING-20261011).
      expect(
        lya
            .predict(sources[HdrSourceClass.dvP7]!,
                preference: HdrOutputPreference.off)
            .selected
            .route!
            .dependencies,
        <String>{
          HdrRouteDependency.hwdecMediacodec,
          HdrRouteDependency.decoderMediacodec,
          HdrRouteDependency.importMediacodec,
          HdrRouteDependency.presenterGpuTexture
        },
      );
      // C4 converts HLG base on a PQ-only display and carries dataspace:pq.
      final HdrRoutePrediction converted = HdrRoutePlanner.plan(
        source: sources[HdrSourceClass.hlg]!,
        capabilities: caps(displayHdrTypes: const <int>{2}),
      );
      expect(converted.selected.strategy, HdrStrategy.baseLayerConvert);
      expect(converted.selected.route!.dependencies, <String>{
        HdrRouteDependency.hwdecMediacodec,
        HdrRouteDependency.topologyPlatformView,
        HdrRouteDependency.dataspacePq,
        HdrRouteDependency.decoderMediacodec,
      });
    });
  });

  group('W1 PQ presentation channels (lg-p84 yuv window reopen)', () {
    // LG-class snapshot: API 24, DV+HDR10 panel (no HLG), applicable lg-pq
    // extension declaring the YUV window as the only PQ presentation
    // channel. The extension id itself is inert data; routing consumes the
    // declared channel structure only.
    HdrCapabilities lgYuvCaps() => caps(
          sdkInt: 24,
          displayHdrTypes: const <int>{1, 2},
          ext: const HdrDataSpaceExtInfo(
            id: 'lg-pq',
            applicable: true,
            pqPresentation:
                HdrPqPresentation(rgbSurface: false, yuvWindow: true),
          ),
        );

    test(
        'dvP84 on the LG-class device: C2 refused on the presentation ground, '
        'C4 feasible through the YUV carrier, playable predicted true', () {
      final HdrRoutePrediction prediction =
          lgYuvCaps().predict(sources[HdrSourceClass.dvP84]!);

      // C1 native: the census has no video/dolby-vision decoder.
      final HdrCandidate native = prediction.candidates.firstWhere(
          (HdrCandidate c) => c.strategy == HdrStrategy.nativeDolbyVision);
      expect(native.skipReason, HdrDegradeReason.nativeDvUnavailable);

      // C2 reshape: structurally hard-bound to the RGB window surface this
      // device does not declare.
      final HdrCandidate reshape = prediction.candidates.firstWhere(
          (HdrCandidate c) => c.strategy == HdrStrategy.metadataReshape);
      expect(reshape.feasible, isFalse);
      expect(reshape.skipReason, HdrDegradeReason.pqRgbPresentationUnavailable);

      // C1 baseline direct: the panel declares no HLG transfer.
      final HdrCandidate direct = prediction.candidates.firstWhere(
          (HdrCandidate c) => c.strategy == HdrStrategy.baseLayerDirect);
      expect(direct.skipReason, HdrDegradeReason.displayLacksTransfer);

      // C4 conversion: feasible through the declared YUV carrier, carrying
      // the fail-closed window contract.
      final HdrCandidate convert = prediction.candidates.firstWhere(
          (HdrCandidate c) => c.strategy == HdrStrategy.baseLayerConvert);
      expect(convert.feasible, isTrue);
      expect(convert.route!.hwdec, 'surfacetexture');
      expect(convert.route!.surfaceTransfer, 'pq');
      expect(convert.route!.offscreenTransfer, 'pq-full');
      expect(convert.route!.dependencies,
          contains(HdrRouteDependency.hwdecSurfaceTexture));

      expect(prediction.selected.strategy, HdrStrategy.baseLayerConvert);
      expect(prediction.selected.stage, HdrRouteStage.c4);
      expect(prediction.playable, isTrue);
    });

    test(
        'dvP84 on the migration-default shape plans exactly as before '
        '(applicable extension without the structure report)', () {
      // The legacy adapter report resolves to {rgbSurface: true,
      // yuvWindow: false}: C2 stays feasible with the mediacodec carrier and
      // C4 keeps the platform baseline carrier — bit-identical to the
      // pre-W1 LYA-shaped plans.
      final HdrRoutePrediction prediction = caps(
        sdkInt: 29,
        displayHdrTypes: const <int>{2, 3},
        ext: extApplicable,
      ).predict(sources[HdrSourceClass.dvP84]!);
      expect(prediction.selected.strategy, HdrStrategy.metadataReshape);
      expect(prediction.selected.stage, HdrRouteStage.c2);
      expect(prediction.selected.route!.hwdec, 'mediacodec');
      expect(prediction.playable, isTrue);
      final HdrCandidate convert = prediction.candidates.firstWhere(
          (HdrCandidate c) => c.strategy == HdrStrategy.baseLayerConvert);
      expect(convert.feasible, isTrue);
      expect(convert.route!.hwdec, 'mediacodec');
      expect(convert.route!.offscreenTransfer, isNull);
    });

    test('hdr10 and P5 planning do not regress on the LG-class device', () {
      // hdr10: the C1 mediacodec_embed direct output declares no window
      // channel and stays the selected playable route.
      final HdrRoutePrediction hdr10 =
          lgYuvCaps().predict(sources[HdrSourceClass.hdr10]!);
      expect(hdr10.selected.strategy, HdrStrategy.baseLayerDirect);
      expect(hdr10.selected.feasible, isTrue);
      expect(hdr10.selected.route!.hwdec, 'mediacodec');
      expect(hdr10.playable, isTrue);

      // P5: no native DV decoder, C2 needs the RGB window this device does
      // not declare, and the tone-map row stays gated by the HDR-display
      // rule (MK-ROUTING-20261011) — the plan records the reasons and
      // blocks instead of a hidden SDR exit.
      final HdrRoutePrediction p5 =
          lgYuvCaps().predict(sources[HdrSourceClass.dvP5]!);
      final HdrCandidate reshape = p5.candidates.firstWhere(
          (HdrCandidate c) => c.strategy == HdrStrategy.metadataReshape);
      expect(reshape.skipReason, HdrDegradeReason.pqRgbPresentationUnavailable);
      final HdrCandidate toneMap = p5.candidates.firstWhere(
          (HdrCandidate c) => c.strategy == HdrStrategy.toneMapSdr);
      expect(toneMap.skipReason, HdrDegradeReason.displayLacksTransfer);
      expect(p5.playable, isFalse);
    });
  });
}
