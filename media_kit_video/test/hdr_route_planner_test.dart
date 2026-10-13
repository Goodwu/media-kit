import 'package:flutter_test/flutter_test.dart';

import 'package:media_kit_video/src/hdr/hdr_capabilities.dart';
import 'package:media_kit_video/src/hdr/hdr_route.dart';
import 'package:media_kit_video/src/hdr/hdr_route_planner.dart';
import 'package:media_kit_video/src/hdr/hdr_source_descriptor.dart';
import 'package:media_kit_video/src/hdr/hdr_strategy.dart';
import 'package:media_kit_video/src/hdr/hdr_strategy_realizer.dart';

const HdrDataSpaceExtInfo extApplicable =
    HdrDataSpaceExtInfo(id: 'lya-pq', applicable: true);
const HdrDataSpaceExtInfo extNotApplicable =
    HdrDataSpaceExtInfo(id: 'lya-pq', applicable: false);

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
  required bool allowExperimental,
  bool explicitSdrRequest = false,
}) {
  final HdrStrategy fallback = cls == HdrSourceClass.sdr
      ? HdrStrategy.sdrDirect
      : HdrStrategy.toneMapSdr;

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
    // With the gate closed, an experimental strategy may only become the
    // selection through the explicit safety-net block; the same for
    // an unsupported maturity (e.g. profile 10's safety net).
    if (candidate.skipReason == null &&
        (candidate.maturity == HdrStrategyMaturity.experimental &&
                !allowExperimental ||
            candidate.maturity == HdrStrategyMaturity.unsupported)) {
      expect(
        candidate.isSafetyNet,
        isTrue,
        reason: 'gated candidate selected outside the safety net: $candidate',
      );
      expect(candidate.strategy, fallback, reason: '$candidate');
    }
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

  // Property (verification 2): when any maturity-allowed feasible candidate
  // presents native HDR, the selection must not be a tone-map/SDR route.
  bool maturityAllowed(HdrStrategyMaturity maturity) =>
      maturity == HdrStrategyMaturity.verified ||
      maturity == HdrStrategyMaturity.inherited ||
      (maturity == HdrStrategyMaturity.experimental && allowExperimental);
  final bool hasFeasibleHdr = prediction.candidates.any(
    (HdrCandidate c) =>
        c.feasible &&
        maturityAllowed(c.maturity) &&
        c.route!.presentation == HdrPresentation.nativeHdr,
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

    test('planner selects native DV for eligible P5.0 once maturity allows',
        () {
      // Gate explicitly open: still selects (the promotion did not change
      // the gate-open behavior; see the maturity-gate group for the
      // gate-closed default selection).
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
          allowExperimental: true,
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

              checkInvariants(at29Plan,
                  cls: cls, capabilities: at29, allowExperimental: false);
              checkInvariants(at34Plan,
                  cls: cls, capabilities: at34, allowExperimental: false);

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

    test('gate open (allowExperimental): same matrix holds without skips', () {
      const HdrRoutingPolicy policy = HdrRoutingPolicy(allowExperimental: true);
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
              checkInvariants(prediction,
                  cls: cls,
                  capabilities: capabilities,
                  allowExperimental: true);
              for (final HdrCandidate candidate in prediction.candidates) {
                // The gate is open: nothing is skipped for maturity. dvP5
                // and dvP84 nativeDolbyVision now proceed to the realizer
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
        allowExperimental: true,
      );
      for (final int sdk in <int>[24, 25]) {
        final HdrRoutePrediction sdr =
            caps(sdkInt: sdk).predict(sources[HdrSourceClass.sdr]!);
        expect(sdr.selected.route!.hwdec, 'mediacodec-copy');
        expect(sdr.selected.route!.dependencies, <String>{
          HdrRouteDependency.hwdecMediacodecCopy,
          HdrRouteDependency.decoderMediacodec,
          HdrRouteDependency.importCpuUpload,
          HdrRouteDependency.presenterGpuTexture
        });

        final HdrRoutePrediction hdr = caps(sdkInt: sdk).predict(
          sources[HdrSourceClass.hlg]!,
          policy: convertFirst,
        );
        expect(hdr.candidates[0].skipReason,
            HdrDegradeReason.gpuHdrDataSpaceUnavailable);
        expect(hdr.candidates[1].skipReason,
            HdrDegradeReason.gpuHdrDataSpaceUnavailable);
        // The display is HDR-capable: once the HDR candidates are refused on
        // the dataspace ground the plan blocks — no tone-map fallback is
        // synthesized (MK-ROUTING-20261011).
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
        allowExperimental: true,
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
        expect(hdr.candidates[0].skipReason,
            HdrDegradeReason.gpuHdrDataSpaceUnavailable);
        expect(hdr.candidates[1].skipReason,
            HdrDegradeReason.gpuHdrDataSpaceUnavailable);
        // The display is HDR-capable: the exhausted HDR list blocks instead
        // of falling through to a tone-map route (MK-ROUTING-20261011).
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
        allowExperimental: true,
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
      for (final bool allowExperimental in const <bool>[false, true]) {
        const HdrRoutingPolicy policy =
            HdrRoutingPolicy(allowExperimental: true);
        final HdrRoutingPolicy effectivePolicy =
            allowExperimental ? policy : HdrRoutingPolicy.defaults;
        for (final HdrSourceClass cls in HdrSourceClass.values) {
          final HdrSourceDescriptor source = sources[cls]!;
          for (final Set<int>? display in displays) {
            for (final bool p5 in const <bool>[true, false]) {
              final HdrCapabilities capabilities =
                  caps(displayHdrTypes: display, p5: p5);
              final HdrRoutePrediction prediction = HdrRoutePlanner.plan(
                source: source,
                capabilities: capabilities,
                policy: effectivePolicy,
              );
              checkInvariants(prediction,
                  cls: cls,
                  capabilities: capabilities,
                  allowExperimental: allowExperimental);
              checked++;
            }
          }
        }
      }
      // 2 gate states × 12 classes × 7 displays × 2 P5 pipelines. The
      // extension dimension is irrelevant to this property (it only moves
      // confidence) and is covered by the matrix tests.
      expect(checked, 336);
    });

    test('empty candidate directory synthesizes a blocking placeholder', () {
      // hdr10Plus has no default preference row (requirement 3.4 never
      // listed it), so with no caller override the candidate directory
      // starts empty. On an HDR-capable display no SDR fallback may be
      // synthesized either: the planner must still return a well-formed
      // blocked prediction with a typed reason and no route.
      final HdrCapabilities lya = lyaCaps();
      final HdrRoutePrediction prediction =
          lya.predict(sources[HdrSourceClass.hdr10Plus]!);
      expect(prediction.playable, isFalse);
      expect(prediction.selected.feasible, isFalse);
      expect(prediction.selected.route, isNull);
      expect(prediction.selected.maturity, HdrStrategyMaturity.unsupported);
      expect(prediction.selected.skipReason,
          HdrDegradeReason.unsupportedStrategy);
      expect(prediction.candidates, <HdrCandidate>[prediction.selected]);
      checkInvariants(prediction,
          cls: HdrSourceClass.hdr10Plus,
          capabilities: lya,
          allowExperimental: false);
      // The unresolved-DV flavor of the same empty-directory path reports
      // its own source-ground reason.
      expect(
        lya.predict(sources[HdrSourceClass.dvUnknown]!).selected.skipReason,
        HdrDegradeReason.sourceMetadataUnknown,
      );
    });
  });

  group('maturity gate (verification 3)', () {
    test('gate closed: experimental strategies are skipped with a reason', () {
      final HdrCapabilities lya = lyaCaps();
      // P7: direct/reshape/tone-map are all experimental for the dvP7 class
      // (no long P7 sample has validated them), so the gate-closed default
      // policy skips every entry — and on this HDR-capable display the
      // exhausted list blocks instead of tone-mapping via a safety net.
      final HdrRoutePrediction prediction =
          lya.predict(sources[HdrSourceClass.dvP7]!);
      expect(prediction.playable, isFalse);
      expect(prediction.selected.strategy, HdrStrategy.baseLayerDirect);
      expect(prediction.selected.skipReason,
          HdrDegradeReason.experimentalStrategySkipped);
      expect(prediction.candidates, hasLength(3));
      expect(prediction.candidates[0].strategy, HdrStrategy.baseLayerDirect);
      expect(prediction.candidates[0].skipReason,
          HdrDegradeReason.experimentalStrategySkipped);
      expect(prediction.candidates[1].strategy, HdrStrategy.metadataReshape);
      expect(prediction.candidates[1].skipReason,
          HdrDegradeReason.experimentalStrategySkipped);
      expect(prediction.candidates[2].strategy, HdrStrategy.toneMapSdr);
      expect(prediction.candidates[2].skipReason,
          HdrDegradeReason.experimentalStrategySkipped);
      expect(
        prediction.candidates.map((c) => c.feasible),
        everyElement(isFalse),
      );
      checkInvariants(prediction,
          cls: HdrSourceClass.dvP7,
          capabilities: lya,
          allowExperimental: false);
    });

    test('gate open: the same experimental strategy is selected', () {
      final HdrCapabilities lya = lyaCaps();
      final HdrRoutePrediction prediction = lya.predict(
        sources[HdrSourceClass.dvP7]!,
        policy: const HdrRoutingPolicy(allowExperimental: true),
      );
      expect(prediction.selected.strategy, HdrStrategy.baseLayerDirect);
      expect(prediction.selected.maturity, HdrStrategyMaturity.experimental);
      expect(prediction.selected.route!.vo, 'mediacodec_embed');
      expect(prediction.selected.route!.outputTransfer, HdrOutputTransfer.pq);
      checkInvariants(prediction,
          cls: HdrSourceClass.dvP7, capabilities: lya, allowExperimental: true);
    });

    test('inherited maturity is selected with the gate closed', () {
      final HdrCapabilities lya = lyaCaps();
      final HdrRoutePrediction prediction =
          lya.predict(sources[HdrSourceClass.dvP81]!);
      expect(prediction.selected.strategy, HdrStrategy.baseLayerDirect);
      expect(prediction.selected.maturity, HdrStrategyMaturity.inherited);
    });

    test(
        'dvP5 reaches nativeDolbyVision by default, without allowExperimental '
        '(2026-10-10 promotion)', () {
      // DV-capable device (declares DV, profile-32 hardware decoder, bridge
      // v1) with the default policy: the gate stays closed, yet the P5
      // source goes straight to the native route — the old behavior (skip
      // with experimentalStrategySkipped unless the gate was open) is gone.
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
          ),
          allowExperimental: false);

      // Contrast (scope red line): on the same device the R7-reserved
      // classes never route natively — dvP81's nativeDolbyVision stays
      // realizer-refused (unsupportedStrategy), gate state aside.
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
        'without DV declaration stays infeasible', () {
      // marble r30g acceptance promoted this cell: with the default policy
      // (gate closed) a DV-capable device takes the P8.4 native route —
      // immediate release (boolean render mode), unlike P5's timed one.
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
      // display requirements are independent.
      final HdrRoutePrediction noDvSignaling = caps(
        displayHdrTypes: const <int>{2, 3},
        dvDecoders: const <HdrDecoderInfo>[nativeDvDecoder],
        nativeDvBridgeApi: 1,
      ).predict(sources[HdrSourceClass.dvP84]!);
      final HdrCandidate native = noDvSignaling.candidates.firstWhere(
          (HdrCandidate c) => c.strategy == HdrStrategy.nativeDolbyVision);
      expect(native.maturity, HdrStrategyMaturity.verified);
      expect(native.skipReason, HdrDegradeReason.displayLacksTransfer);
      expect(noDvSignaling.selected.strategy, HdrStrategy.baseLayerDirect);
      expect(
          noDvSignaling.selected.route!.outputTransfer, HdrOutputTransfer.hlg);
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
      // A caller preference cannot make PQ->PQ masquerade as conversion.
      expect(preferred.selected.strategy, HdrStrategy.baseLayerDirect);
      expect(preferred.candidates.first.skipReason,
          HdrDegradeReason.unsupportedStrategy);
    });

    test('hdr10 metadataReshape is verified and selectable (2026-10-10)', () {
      // Indirect-evidence cell (pipeline verified at dvP5 + user
      // adjudication): the reshape is no longer behind the gate for HDR10.
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
      expect(prediction.selected.strategy, HdrStrategy.metadataReshape);
      expect(prediction.selected.maturity, HdrStrategyMaturity.verified);
      expect(prediction.selected.skipReason, isNull);
      // An HDR10 source carries no dynamic metadata to re-apply.
      expect(prediction.selected.route!.appliesDynamicMetadata, isFalse);
      expect(prediction.selected.route!.surfaceTransfer, 'pq');
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
        allowExperimental: true,
      );
      final HdrRoutePrediction hdr10 =
          lya.predict(sources[HdrSourceClass.hdr10]!, policy: policy);
      expect(hdr10.selected.strategy, HdrStrategy.baseLayerDirect);
      expect(hdr10.candidates.first.strategy, HdrStrategy.nativeDolbyVision);
      expect(hdr10.candidates.first.skipReason,
          HdrDegradeReason.unsupportedStrategy);

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
    test('P8.4 on an HDR10-only display converts to PQ (gate open)', () {
      final HdrRoutePrediction prediction = HdrRoutePlanner.plan(
        source: sources[HdrSourceClass.dvP84]!,
        capabilities: caps(displayHdrTypes: const <int>{2}),
        policy: const HdrRoutingPolicy(allowExperimental: true),
      );
      expect(prediction.selected.strategy, HdrStrategy.baseLayerConvert);
      expect(prediction.selected.route!.outputTransfer, HdrOutputTransfer.pq);
      expect(prediction.selected.route!.surfaceTransfer, 'pq');
      expect(prediction.selected.route!.stripDvRpu, isTrue);
      expect(prediction.selected.route!.dependencies,
          contains(HdrRouteDependency.dataspacePq));
    });

    test(
        'PQ dataspace excluded: P8.4 HDR candidates exhaust and the plan '
        'blocks', () {
      final HdrRoutePrediction prediction = HdrRoutePlanner.plan(
        source: sources[HdrSourceClass.dvP84]!,
        capabilities: caps(displayHdrTypes: const <int>{2}),
        policy: const HdrRoutingPolicy(allowExperimental: true),
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
          capabilities: caps(displayHdrTypes: const <int>{2}),
          allowExperimental: true);
    });

    test('gate order: a closed gate reasons before an excluded stage', () {
      final HdrRoutePrediction prediction = HdrRoutePlanner.plan(
        source: sources[HdrSourceClass.dvP84]!,
        capabilities: caps(displayHdrTypes: const <int>{2}),
        excluded: const <String, HdrDegradeReason>{
          HdrRouteDependency.dataspacePq: HdrDegradeReason.dataSpaceApplyFailed,
        },
      );
      final HdrCandidate reshape = prediction.candidates.firstWhere(
          (HdrCandidate c) => c.strategy == HdrStrategy.metadataReshape);
      // The maturity gate runs first, so the experimental reshape is
      // reported as gated, not as excluded. The HDR-capable display blocks
      // the exhausted list; the first rejected entry (native DV) is the
      // selection carrying its own reason.
      expect(reshape.skipReason, HdrDegradeReason.experimentalStrategySkipped);
      expect(prediction.playable, isFalse);
      expect(prediction.selected.strategy, HdrStrategy.nativeDolbyVision);
      expect(
          prediction.selected.skipReason, HdrDegradeReason.displayLacksTransfer);
    });

    test('dataspace exclusion does not touch the direct route', () {
      final HdrRoutePrediction prediction = HdrRoutePlanner.plan(
        source: sources[HdrSourceClass.dvP84]!,
        capabilities: caps(displayHdrTypes: const <int>{2, 3}),
        policy: const HdrRoutingPolicy(allowExperimental: true),
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
    test('predict() equals plan() for every combo and both gate states', () {
      var combos = 0;
      for (final bool allowExperimental in const <bool>[false, true]) {
        final HdrRoutingPolicy policy = allowExperimental
            ? const HdrRoutingPolicy(allowExperimental: true)
            : HdrRoutingPolicy.defaults;
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
      }
      expect(combos, 1008);
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
      // the preferGpuOutput route) are feasible with the gate closed. The
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
      // The C4 input constraint is independent of the legacy maturity gate:
      // PQ cannot become an HLG-to-PQ conversion even when it is open.
      final HdrRoutePrediction gateOpen = lyaCaps().predict(
        sources[HdrSourceClass.hdr10]!,
        policy: const HdrRoutingPolicy(allowExperimental: true),
      );
      expect(gateOpen.candidates[0].feasible, isTrue);
      expect(gateOpen.candidates[1].feasible, isFalse);
      expect(gateOpen.candidates[1].skipReason,
          HdrDegradeReason.unsupportedStrategy);
      expect(gateOpen.selected, prediction.selected);
    });

    test('P8.4 takes the verified HLG direct route', () {
      final HdrRoutePrediction prediction =
          lyaCaps().predict(sources[HdrSourceClass.dvP84]!);
      expect(prediction.selected.strategy, HdrStrategy.baseLayerDirect);
      expect(prediction.selected.maturity, HdrStrategyMaturity.verified);
      expect(prediction.selected.route!.outputTransfer, HdrOutputTransfer.hlg);
      expect(prediction.selected.route!.stripDvRpu, isFalse);
      expect(prediction.presentation, HdrPresentation.nativeHdr);
      expect(prediction.playable, isTrue);
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

    test('P8.1 takes the inherited direct route with the gate closed', () {
      final HdrRoutePrediction prediction =
          lyaCaps().predict(sources[HdrSourceClass.dvP81]!);
      expect(prediction.selected.strategy, HdrStrategy.baseLayerDirect);
      expect(prediction.selected.maturity, HdrStrategyMaturity.inherited);
      expect(prediction.selected.route!.outputTransfer, HdrOutputTransfer.pq);
      expect(prediction.playable, isTrue);
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
        allowExperimental: true,
      );
      final HdrRoutePrediction prediction =
          lyaCaps().predict(sources[HdrSourceClass.dvP84]!, policy: policy);
      expect(prediction.selected.strategy, HdrStrategy.metadataReshape);
      expect(prediction.selected.route!.surfaceTransfer, 'pq');
      expect(prediction.selected.route!.appliesDynamicMetadata, isTrue);
      // The default policy still picks the HLG direct route.
      expect(
          lyaCaps().predict(sources[HdrSourceClass.dvP84]!).selected.strategy,
          HdrStrategy.baseLayerDirect);
    });

    test('override without allowExperimental skips to the next entry', () {
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
      expect(prediction.selected.strategy, HdrStrategy.baseLayerDirect);
      expect(prediction.candidates.first.skipReason,
          HdrDegradeReason.experimentalStrategySkipped);
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
            allowExperimental: false,
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
      // this HDR-capable display blocks once the gated dvP7 strategies are
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
        policy: const HdrRoutingPolicy(allowExperimental: true),
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
}
