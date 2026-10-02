import 'package:flutter_test/flutter_test.dart';

import 'package:media_kit_video/src/hdr/hdr_capabilities.dart';
import 'package:media_kit_video/src/hdr/hdr_route.dart';
import 'package:media_kit_video/src/hdr/hdr_route_planner.dart';
import 'package:media_kit_video/src/hdr/hdr_source_descriptor.dart';
import 'package:media_kit_video/src/hdr/hdr_strategy.dart';

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

/// One descriptor per source class. Each entry derives back to its key
/// (asserted below), so the matrix really walks the eleven classes.
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
  HdrSourceClass.sdr: HdrSourceDescriptor(
      transfer: 'bt.1886', primaries: 'bt.709', enhancementLayer: false),
};

HdrCapabilities caps({
  int sdkInt = 29,
  Set<int>? displayHdrTypes = const <int>{2, 3},
  bool p5 = true,
  HdrDataSpaceExtInfo? ext,
}) {
  return HdrCapabilities(
    sdkInt: sdkInt,
    displayHdrTypes: displayHdrTypes,
    hevcDecoders: const <HdrDecoderInfo>[lyHevcDecoder],
    dolbyVisionDecoders: const <HdrDecoderInfo>[],
    p5PipelineAvailable: p5,
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
}) {
  final HdrStrategy fallback = cls == HdrSourceClass.sdr
      ? HdrStrategy.sdrDirect
      : HdrStrategy.toneMapSdr;

  // R3.3: playable is false only for a P5 source without the rescale
  // pipeline; otherwise playback always continues.
  expect(
    prediction.playable,
    cls != HdrSourceClass.dvP5 || capabilities.p5PipelineAvailable,
    reason: 'playable for $cls with p5=${capabilities.p5PipelineAvailable}',
  );
  expect(prediction.selected.feasible, prediction.playable);

  // R7: native Dolby Vision is never selected, whatever the policy says.
  expect(
    prediction.selected.strategy,
    isNot(HdrStrategy.nativeDolbyVision),
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
    // selection through the safety net (the last candidate); the same for
    // an unsupported maturity (e.g. profile 10's safety net).
    if (candidate.skipReason == null &&
        (candidate.maturity == HdrStrategyMaturity.experimental &&
                !allowExperimental ||
            candidate.maturity == HdrStrategyMaturity.unsupported)) {
      expect(
        identical(candidate, prediction.candidates.last),
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
    !dependsOnDataSpace || (ext != null && ext.applicable)
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
    // A display reporting Dolby Vision (type 1). The planner consumes no
    // route from it yet (nativeDolbyVision is unsupported, R7), so plans
    // must be identical to the {2, 3} display.
    <int>{1},
    <int>{1, 2, 3},
  ];
  const List<HdrDataSpaceExtInfo?> extensions = <HdrDataSpaceExtInfo?>[
    null,
    extApplicable,
    extNotApplicable,
  ];

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
            transfer: 'hlg',
            dynamicMetadata: HdrDynamicMetadata.hdrVivid)),
        HdrSourceClass.hdrVivid,
      );
      expect(
        HdrSourceClass.of(const HdrSourceDescriptor(
            transfer: 'pq', primaries: 'bt.2020')),
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
        HdrSourceClass.of(
            const HdrSourceDescriptor(transfer: 'bt.1886')),
        HdrSourceClass.sdr,
      );
    });

    test('profile 8 with an unknown compatibility id follows the base layer',
        () {
      HdrSourceDescriptor p8(String? transfer) => HdrSourceDescriptor(
          transfer: transfer, dynamicMetadata: HdrDynamicMetadata.dolbyVision, dvProfile: 8);
      expect(HdrSourceClass.of(p8('hlg')), HdrSourceClass.dvP84);
      expect(HdrSourceClass.of(p8('pq')), HdrSourceClass.dvP81);
      expect(HdrSourceClass.of(p8('bt.1886')), HdrSourceClass.dvP82);
      expect(HdrSourceClass.of(p8(null)), HdrSourceClass.dvP82);
    });

    test('DV metadata without a profile is treated as profile 5 (conservative)',
        () {
      // The only family whose routes never ignore the RPU, so a malformed
      // hint cannot select a mis-coloring route (R3.3).
      expect(
        HdrSourceClass.of(const HdrSourceDescriptor(
            transfer: 'pq', dynamicMetadata: HdrDynamicMetadata.dolbyVision)),
        HdrSourceClass.dvP5,
      );
    });
  });

  group('default preference matrix (verification 1)', () {
    test('11 classes × 7 displays × 2 P5 pipelines × 3 ext × 2 SDK', () {
      var combos = 0;
      for (final HdrSourceClass cls in HdrSourceClass.values) {
        final HdrSourceDescriptor source = sources[cls]!;
        for (final Set<int>? display in displays) {
          for (final bool p5 in const <bool>[true, false]) {
            for (final HdrDataSpaceExtInfo? ext in extensions) {
              final HdrCapabilities at29 = caps(
                  displayHdrTypes: display, p5: p5, ext: ext, sdkInt: 29);
              final HdrCapabilities at34 = caps(
                  displayHdrTypes: display, p5: p5, ext: ext, sdkInt: 34);
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
      expect(combos, 462);
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
                  cls: cls, capabilities: capabilities, allowExperimental: true);
              for (final HdrCandidate candidate in prediction.candidates) {
                // The gate is open: nothing is skipped for maturity, and
                // the reserved strategy is still refused.
                expect(candidate.skipReason,
                    isNot(HdrDegradeReason.experimentalStrategySkipped),
                    reason: '$candidate');
                if (candidate.strategy == HdrStrategy.nativeDolbyVision) {
                  expect(candidate.skipReason,
                      HdrDegradeReason.unsupportedStrategy, reason: '$candidate');
                }
              }
              combos++;
            }
          }
        }
      }
      expect(combos, 462);
    });

    test('"HDR first, tone-map last" holds for every combo (verification 2)',
        () {
      var checked = 0;
      for (final bool allowExperimental in const <bool>[false, true]) {
        const HdrRoutingPolicy policy = HdrRoutingPolicy(
            allowExperimental: true);
        final HdrRoutingPolicy effectivePolicy = allowExperimental
            ? policy
            : HdrRoutingPolicy.defaults;
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
      // 2 gate states × 11 classes × 7 displays × 2 P5 pipelines. The
      // extension dimension is irrelevant to this property (it only moves
      // confidence) and is covered by the matrix tests.
      expect(checked, 308);
    });
  });

  group('maturity gate (verification 3)', () {
    test('gate closed: experimental strategies are skipped with a reason', () {
      final HdrCapabilities lya = lyaCaps();
      // P7: direct/reshape/tone-map are all experimental for the dvP7 class
      // (no long P7 sample has validated them), so the default policy
      // tone-maps via the safety net.
      final HdrRoutePrediction prediction =
          lya.predict(sources[HdrSourceClass.dvP7]!);
      expect(prediction.selected.strategy, HdrStrategy.toneMapSdr);
      expect(prediction.candidates, hasLength(4));
      expect(prediction.candidates[0].strategy, HdrStrategy.baseLayerDirect);
      expect(prediction.candidates[0].skipReason,
          HdrDegradeReason.experimentalStrategySkipped);
      expect(prediction.candidates[1].strategy, HdrStrategy.metadataReshape);
      expect(prediction.candidates[1].skipReason,
          HdrDegradeReason.experimentalStrategySkipped);
      expect(prediction.candidates[2].strategy, HdrStrategy.toneMapSdr);
      expect(prediction.candidates[2].skipReason,
          HdrDegradeReason.experimentalStrategySkipped);
      expect(prediction.candidates.last.feasible, isTrue);
      expect(prediction.candidates.last.skipReason, isNull);
      expect(prediction.playable, isTrue);
      checkInvariants(prediction,
          cls: HdrSourceClass.dvP7, capabilities: lya, allowExperimental: false);
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

    test('nativeDolbyVision is never selected, even first in preferences', () {
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
      expect(p5.candidates.first.skipReason,
          HdrDegradeReason.unsupportedStrategy);
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

    test('PQ dataspace excluded: P8.4 falls from convert(PQ) to tone-map', () {
      final HdrRoutePrediction prediction = HdrRoutePlanner.plan(
        source: sources[HdrSourceClass.dvP84]!,
        capabilities: caps(displayHdrTypes: const <int>{2}),
        policy: const HdrRoutingPolicy(allowExperimental: true),
        excluded: const <String, HdrDegradeReason>{
          HdrRouteDependency.dataspacePq: HdrDegradeReason.dataSpaceApplyFailed,
        },
      );
      expect(prediction.selected.strategy, HdrStrategy.toneMapSdr);
      final HdrCandidate direct = prediction.candidates
          .firstWhere((HdrCandidate c) => c.strategy == HdrStrategy.baseLayerDirect);
      expect(direct.skipReason, HdrDegradeReason.displayLacksTransfer);
      final HdrCandidate convert = prediction.candidates
          .firstWhere((HdrCandidate c) => c.strategy == HdrStrategy.baseLayerConvert);
      expect(convert.skipReason, HdrDegradeReason.dataSpaceApplyFailed);
      final HdrCandidate reshape = prediction.candidates
          .firstWhere((HdrCandidate c) => c.strategy == HdrStrategy.metadataReshape);
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
      final HdrCandidate reshape = prediction.candidates
          .firstWhere((HdrCandidate c) => c.strategy == HdrStrategy.metadataReshape);
      // The maturity gate runs first, so the experimental reshape is
      // reported as gated, not as excluded.
      expect(reshape.skipReason,
          HdrDegradeReason.experimentalStrategySkipped);
      expect(prediction.selected.strategy, HdrStrategy.toneMapSdr);
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
      expect(combos, 924);
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
    test('HDR10 takes mediacodec_embed PQ direct with all candidates feasible',
        () {
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
          HdrStrategy.toneMapSdr
        ],
      );
      // Default policy: the conversion is experimental (section 6) and
      // stays behind the maturity gate; direct and tone-map are verified.
      expect(prediction.candidates[1].skipReason,
          HdrDegradeReason.experimentalStrategySkipped);
      expect(prediction.candidates[1].feasible, isFalse);
      expect(prediction.candidates[2].feasible, isTrue);
      // Gate open: every default candidate is feasible on this display.
      final HdrRoutePrediction gateOpen = lyaCaps().predict(
        sources[HdrSourceClass.hdr10]!,
        policy: const HdrRoutingPolicy(allowExperimental: true),
      );
      expect(gateOpen.candidates.every((HdrCandidate c) => c.feasible),
          isTrue);
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

    test('tone-map fallback matches the Texture branch of decide', () {
      final HdrRoutePrediction prediction =
          lyaCaps().predict(sources[HdrSourceClass.dvP84]!);
      final HdrCandidate toneMap = prediction.candidates
          .singleWhere((HdrCandidate c) => c.strategy == HdrStrategy.toneMapSdr);
      expect(toneMap.route!.vo, 'gpu-next');
      expect(toneMap.route!.hwdec, 'mediacodec');
      expect(toneMap.route!.topology, HdrTopology.texture);
      expect(toneMap.route!.targetPrim, 'bt.709');
      expect(toneMap.route!.targetTrc, 'bt.1886');
      expect(toneMap.route!.surfaceTransfer, isNull);
      expect(toneMap.route!.stripDvRpu, isTrue);
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

    test('P5 without the pipeline is never playable, safety net included',
        () {
      final HdrCapabilities capabilities = caps(p5: false, ext: extApplicable);
      final HdrRoutePrediction prediction =
          capabilities.predict(sources[HdrSourceClass.dvP5]!);
      expect(prediction.playable, isFalse);
      expect(prediction.selected.feasible, isFalse);
      expect(prediction.selected.route, isNull);
      expect(prediction.selected.skipReason,
          HdrDegradeReason.p5PipelineUnavailable);
      expect(prediction.candidates.last, prediction.selected);
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
      expect(lyaCaps().predict(sources[HdrSourceClass.dvP84]!).selected.strategy,
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
        final HdrRoutePrediction prediction =
            lyaCaps().predict(sources[cls]!, preference: HdrOutputPreference.off);
        if (cls == HdrSourceClass.sdr) {
          expect(prediction.selected.strategy, HdrStrategy.sdrDirect,
              reason: '$cls');
        } else {
          expect(prediction.selected.strategy, HdrStrategy.toneMapSdr,
              reason: '$cls');
        }
        expect(prediction.playable, isTrue, reason: '$cls');
        checkInvariants(prediction,
            cls: cls, capabilities: lyaCaps(), allowExperimental: false);
      }
    });

    test('preference off keeps a pipeline-less P5 unplayable (R3.3)', () {
      final HdrRoutePrediction prediction = caps(p5: false)
          .predict(sources[HdrSourceClass.dvP5]!,
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
        lya.predict(sources[HdrSourceClass.hdr10]!).selected.route!.dependencies,
        <String>{
          HdrRouteDependency.hwdecMediacodec,
          HdrRouteDependency.topologyPlatformView
        },
      );
      expect(
        lya.predict(sources[HdrSourceClass.dvP5]!).selected.route!.dependencies,
        <String>{
          HdrRouteDependency.hwdecMediacodec,
          HdrRouteDependency.topologyPlatformView,
          HdrRouteDependency.dataspacePq,
        },
      );
      expect(
        lya.predict(sources[HdrSourceClass.sdr]!).selected.route!.dependencies,
        <String>{HdrRouteDependency.hwdecMediacodec},
      );
      // The tone-map safety net has no dataspace/platformView dependency.
      expect(
        lya.predict(sources[HdrSourceClass.dvP7]!).selected.route!.dependencies,
        <String>{HdrRouteDependency.hwdecMediacodec},
      );
      // Conversion to HLG (HDR10 base on an HLG-only display, gate open —
      // the direct route is infeasible without display HDR10) carries
      // dataspace:hlg.
      final HdrRoutePrediction converted = HdrRoutePlanner.plan(
        source: sources[HdrSourceClass.hdr10]!,
        capabilities: caps(displayHdrTypes: const <int>{3}),
        policy: const HdrRoutingPolicy(allowExperimental: true),
      );
      expect(converted.selected.strategy, HdrStrategy.baseLayerConvert);
      expect(converted.selected.route!.dependencies, <String>{
        HdrRouteDependency.hwdecMediacodec,
        HdrRouteDependency.topologyPlatformView,
        HdrRouteDependency.dataspaceHlg,
      });
    });
  });
}
