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
  profiles: <int>[32],
  main10: null,
  widthRange: <int>[16, 4096],
  heightRange: <int>[16, 4096],
  frameRateRange: <int>[8, 120],
  supports4K: true,
  max4KFps: 60,
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

  // R7 baseline: native Dolby Vision stays unselected unless the class is
  // dvP5 or dvP84 on a DV-declaring display with the bridge loaded (both
  // verified since the 2026-10-10 A-group promotion; dvP5 via the genbump2
  // LG acceptance, dvP84 via the marble r30g acceptance).
  expect(
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
        expect(realize(source: invalid).infeasibleReason,
            HdrDegradeReason.unsupportedStrategy,
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
      expect(combos, 462);
    });

    test('API 24/25 use copy for texture routes and skip GPU HDR dataspace',
        () {
      const HdrRoutingPolicy convertFirst = HdrRoutingPolicy(
        preferences: <HdrSourceClass, List<HdrStrategy>>{
          HdrSourceClass.hdr10: <HdrStrategy>[
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
        expect(sdr.selected.route!.dependencies,
            <String>{HdrRouteDependency.hwdecMediacodecCopy});

        final HdrRoutePrediction hdr = caps(sdkInt: sdk).predict(
          sources[HdrSourceClass.hdr10]!,
          policy: convertFirst,
        );
        expect(hdr.candidates[0].skipReason,
            HdrDegradeReason.gpuHdrDataSpaceUnavailable);
        expect(hdr.candidates[1].skipReason,
            HdrDegradeReason.gpuHdrDataSpaceUnavailable);
        expect(hdr.selected.strategy, HdrStrategy.toneMapSdr);
        expect(hdr.selected.route!.hwdec, 'mediacodec-copy');

        // Decoder-composited output does not rely on the unavailable GPU
        // dataspace API and remains a candidate on these Android versions.
        final HdrRoutePrediction direct =
            caps(sdkInt: sdk).predict(sources[HdrSourceClass.hdr10]!);
        expect(direct.selected.strategy, HdrStrategy.baseLayerDirect);
        expect(direct.selected.route!.vo, 'mediacodec_embed');
      }
    });

    test('API 26/27 keep MediaCodec texture routes and skip GPU HDR dataspace',
        () {
      const HdrRoutingPolicy convertFirst = HdrRoutingPolicy(
        preferences: <HdrSourceClass, List<HdrStrategy>>{
          HdrSourceClass.hdr10: <HdrStrategy>[
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
        expect(sdr.selected.route!.dependencies,
            <String>{HdrRouteDependency.hwdecMediacodec});

        final HdrRoutePrediction hdr = caps(sdkInt: sdk).predict(
          sources[HdrSourceClass.hdr10]!,
          policy: convertFirst,
        );
        expect(hdr.candidates[0].skipReason,
            HdrDegradeReason.gpuHdrDataSpaceUnavailable);
        expect(hdr.candidates[1].skipReason,
            HdrDegradeReason.gpuHdrDataSpaceUnavailable);
        expect(hdr.selected.strategy, HdrStrategy.toneMapSdr);
      }
    });

    test('API 28+ enables GPU HDR routes; sdk 0 makes no legacy assumption',
        () {
      const HdrRoutingPolicy convertFirst = HdrRoutingPolicy(
        preferences: <HdrSourceClass, List<HdrStrategy>>{
          HdrSourceClass.hdr10: <HdrStrategy>[
            HdrStrategy.baseLayerConvert,
            HdrStrategy.metadataReshape,
            HdrStrategy.toneMapSdr,
          ],
        },
        allowExperimental: true,
      );
      for (final int sdk in <int>[28, 29, 34]) {
        final HdrRoutePrediction hdr = caps(sdkInt: sdk).predict(
          sources[HdrSourceClass.hdr10]!,
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
            .predict(sources[HdrSourceClass.hdr10]!, policy: convertFirst)
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
      expect(unavailable.selected.skipReason,
          HdrDegradeReason.p5PipelineUnavailable);

      final HdrRoutePrediction available =
          caps(sdkInt: 24, p5: true).predict(sources[HdrSourceClass.dvP5]!);
      expect(available.selected.strategy, HdrStrategy.toneMapSdr);
      expect(available.selected.route!.hwdec, 'mediacodec-copy');
      expect(available.selected.route!.appliesDynamicMetadata, isTrue);
      expect(available.selected.route!.stripDvRpu, isFalse);
      expect(
        available.candidates
            .firstWhere((candidate) =>
                candidate.strategy == HdrStrategy.metadataReshape)
            .skipReason,
        HdrDegradeReason.gpuHdrDataSpaceUnavailable,
      );
      expect(
        available.selected.route!.dependencies,
        <String>{HdrRouteDependency.hwdecMediacodecCopy},
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
      expect(prediction.candidates.first.strategy,
          HdrStrategy.nativeDolbyVision);
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
        'without DV signaling stays infeasible (LG N/A, 2026-10-10)', () {
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

      // LG declares no P8.4 DV signaling: the native route is unreachable
      // there (N/A, not a failure) and playback keeps the verified HLG
      // direct route.
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

    test('hdr10 baseLayerConvert is default-reachable (preferGpuOutput route)',
        () {
      // Default policy: the PQ conversion sits right behind the verified
      // direct route with no maturity skip (verified 2026-10-10, LG
      // genbump2 full-route round).
      final HdrRoutePrediction prediction =
          lyaCaps().predict(sources[HdrSourceClass.hdr10]!);
      final HdrCandidate convert = prediction.candidates.firstWhere(
          (HdrCandidate c) => c.strategy == HdrStrategy.baseLayerConvert);
      expect(convert.maturity, HdrStrategyMaturity.verified);
      expect(convert.skipReason, isNull);
      expect(convert.feasible, isTrue);
      // The preferGpuOutput scenario — an app preferring the gpu output
      // route — selects it with the default gate closed.
      const HdrRoutingPolicy convertFirst = HdrRoutingPolicy(
        preferences: <HdrSourceClass, List<HdrStrategy>>{
          HdrSourceClass.hdr10: <HdrStrategy>[
            HdrStrategy.baseLayerConvert,
            HdrStrategy.baseLayerDirect,
            HdrStrategy.toneMapSdr,
          ],
        },
      );
      final HdrRoutePrediction preferred = lyaCaps()
          .predict(sources[HdrSourceClass.hdr10]!, policy: convertFirst);
      expect(preferred.selected.strategy, HdrStrategy.baseLayerConvert);
      expect(preferred.selected.maturity, HdrStrategyMaturity.verified);
      expect(preferred.selected.skipReason, isNull);
      expect(preferred.selected.route!.surfaceTransfer, 'pq');
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

    test('nativeDolbyVision stays unselected on a non-DV display, even first '
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
      // reported as gated, not as excluded.
      expect(reshape.skipReason, HdrDegradeReason.experimentalStrategySkipped);
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
      // Default policy: direct, the PQ conversion (verified 2026-10-10,
      // the preferGpuOutput route) and tone-map are all verified — the
      // whole default candidate list is feasible with the gate closed.
      expect(prediction.candidates[1].skipReason, isNull);
      expect(prediction.candidates[1].feasible, isTrue);
      expect(prediction.candidates[2].feasible, isTrue);
      // Gate open changes nothing for this class any more: the same list.
      final HdrRoutePrediction gateOpen = lyaCaps().predict(
        sources[HdrSourceClass.hdr10]!,
        policy: const HdrRoutingPolicy(allowExperimental: true),
      );
      expect(gateOpen.candidates.every((HdrCandidate c) => c.feasible), isTrue);
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

    test('tone-map fallback matches the Texture branch of decide', () {
      final HdrRoutePrediction prediction =
          lyaCaps().predict(sources[HdrSourceClass.dvP84]!);
      final HdrCandidate toneMap = prediction.candidates.singleWhere(
          (HdrCandidate c) => c.strategy == HdrStrategy.toneMapSdr);
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

    test('P5 without the pipeline is never playable, safety net included', () {
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
        expect(prediction.playable, isTrue, reason: '$cls');
        checkInvariants(prediction,
            cls: cls, capabilities: lyaCaps(), allowExperimental: false);
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
