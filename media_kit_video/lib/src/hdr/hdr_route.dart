/// This file is a part of media_kit (https://github.com/media-kit/media-kit).
///
/// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
/// All rights reserved.
/// Use of this source code is governed by MIT license that can be found in the LICENSE file.
import 'package:flutter/foundation.dart' show setEquals;

import 'hdr_strategy.dart';
import 'hdr_source_descriptor.dart';

/// How the picture reaches the viewer (requirement R4.1). The value is
/// derived from the selected strategy; `nativeDolbyVision` was reserved
/// (R7) and is produced only for `dvP5` sources since the 2026-10-06
/// experimental unlock on DV-declaring devices.
enum HdrPresentation {
  sdr,
  toneMappedSdr,
  nativeHdr,
  nativeDolbyVision;

  /// The presentation a strategy realizes into. Used when a prediction has
  /// no concrete route (the P5 pipeline is missing and playback will not
  /// start) so the field stays populated.
  static HdrPresentation ofStrategy(HdrStrategy strategy) {
    switch (strategy) {
      case HdrStrategy.nativeDolbyVision:
        return HdrPresentation.nativeDolbyVision;
      case HdrStrategy.nativeHdr10Plus:
      case HdrStrategy.nativeHdrVivid:
        return HdrPresentation.nativeHdr;
      case HdrStrategy.baseLayerDirect:
      case HdrStrategy.baseLayerConvert:
      case HdrStrategy.metadataReshape:
        return HdrPresentation.nativeHdr;
      case HdrStrategy.toneMapSdr:
        return HdrPresentation.toneMappedSdr;
      case HdrStrategy.sdrDirect:
        return HdrPresentation.sdr;
    }
  }
}

/// The output transfer function of a realized route (requirement R4.1).
enum HdrOutputTransfer {
  pq,

  hlg,

  /// Dolby Vision output is not SDR, even when the base-layer transfer is
  /// unavailable or represented by an unknown raw value.
  dolbyVision,

  sdr,
}

/// The output topology of a realized route: a `gpu-next` GL texture
/// (Texture widget) or a native surface hosted by the platform view
/// (decoder-composited `mediacodec_embed` or the GPU HDR dataspace surface).
enum HdrTopology { texture, platformView }

/// Intended ownership of *source* dynamic metadata. This is a requested
/// route contract, never proof that a decoder/renderer consumed or forwarded
/// a frame's metadata. Actual delivery/consumption needs runtime evidence.
enum HdrMetadataHandling {
  /// Ordinary SDR/HDR without an applicable dynamic payload.
  none,

  /// Keep original dynamic signaling for an actual native HDR decoder.
  preserveForNative,

  /// Consume per-frame metadata in the local GPU mapping/tone-map pipeline.
  consumeForMapping,

  /// Use only the independently decodable compatible base layer.
  /// The execution adapter must not claim dynamic HDR was rendered.
  baselineOnly,
}

/// Confidence that the predicted route will actually come up on this device
/// (requirement R1.5). Orthogonal to [HdrStrategyMaturity]: maturity says
/// whether this kind of route has ever been verified, confidence says
/// whether *this* playback's outcome is decidable before opening the media.
enum HdrPredictionConfidence {
  /// The route does not depend on runtime dataspace application, or the
  /// dataspace it depends on is covered by a registered extension whose
  /// read-only applicability check matches this device.
  verified,

  /// The route depends on a dataspace application that can only succeed or
  /// fail after playback starts.
  unverified,
}

/// Typed reasons for a skipped candidate or a runtime degradation
/// (requirement R3.2, which sets the floor "至少区分以下原因").
enum HdrDegradeReason {
  /// No available system decoder for this exact source and route consumer.
  /// Does not prove that an unenumerated FFmpeg software path is impossible.
  sourceDecodeUnsupported,

  /// Every execution of this complete request was already admitted once.
  candidateExhausted,

  /// The requested configuration cannot be met by an eligible/current route.
  routeOptionsUnsatisfied,

  /// DV is present but its profile/base-layer interpretation is not known.
  /// More source facts are required; requesting SDR cannot remove this need.
  sourceMetadataUnknown,

  /// Output forced to SDR because the caller set `HdrOutputPreference.off`.
  preferenceOff,

  /// The display does not report the HDR transfer type the route outputs.
  displayLacksTransfer,

  /// The platform returned no display HDR capability report at all; HDR
  /// routes are never selected on a guess.
  noDisplayCapabilityReport,

  /// Legacy reason of the removed maturity admission gate. The planner no
  /// longer produces it — maturity never gates admission — and it is kept
  /// only as part of the typed reason vocabulary.
  experimentalStrategySkipped,

  /// The strategy cannot be realized on the current pipeline at all: a
  /// `nativeDolbyVision` source outside the 2026-10-06 dvP5 experimental
  /// unlock, a strategy that would ignore a P5 RPU, HDR Vivid metadata
  /// rebuild (not implemented), or reshape on a P7 stream whose
  /// enhancement layer may be FEL.
  unsupportedStrategy,

  /// The selected, structurally applicable route has no implementation in
  /// this build. This is not display/decoder unavailability and is reported
  /// even if a later baseline HDR candidate plays successfully.
  routeNotImplemented,

  /// A Dolby Vision source needs the fork's P5 dovi rescale pipeline and it
  /// is not available; the library refuses to output a wrongly colored
  /// picture (R3.3).
  p5PipelineUnavailable,

  /// The dataspace application failed at runtime.
  dataSpaceApplyFailed,

  /// The dataspace readback did not match the requested value.
  dataSpaceReadbackMismatch,

  /// `hwdec-current` did not match the route's expectation.
  hwdecMismatch,

  /// The reviewed source requires a different route after the single rebuild.
  routeReviewMismatch,

  /// The GPU output surface did not bind within the budget.
  outputBindTimeout,

  /// Native Dolby Vision decoder or bridge capability is unavailable.
  nativeDvUnavailable,

  /// A capability the selected route relied on disappeared during playback.
  capabilityLost,

  /// Android versions before API 28 cannot apply the public GPU HDR dataspace
  /// needed by HDR PlatformView routes.
  gpuHdrDataSpaceUnavailable,

  /// The platform has no HDR output pipeline (non-Android in Phase 1).
  unsupportedPlatform,
}

/// The pipeline stages a route depends on (plan 1.3). When one of them fails
/// at runtime the executor adds the tag to the planner's `excluded` set and
/// every candidate depending on the same stage is skipped with the failure
/// reason attached.
abstract class HdrRouteDependency {
  /// The route requests a BT.2020 PQ dataspace on the GPU surface.
  static const String dataspacePq = 'dataspace:pq';

  /// The route requests a BT.2020 HLG dataspace on the GPU surface.
  static const String dataspaceHlg = 'dataspace:hlg';

  /// The route plays through the MediaCodec hardware decoder.
  static const String hwdecMediacodec = 'hwdec:mediacodec';

  /// The route decodes through MediaCodec and copies frames to the GPU.
  static const String hwdecMediacodecCopy = 'hwdec:mediacodec-copy';

  /// The route imports SurfaceTexture decoder frames. This records the
  /// execution dependency only; it does not imply a YUV presenter or identify
  /// a decoder failure cause.
  static const String hwdecSurfaceTexture = 'hwdec:surfacetexture';

  /// The native Dolby Vision decoder/bridge pipeline.
  static const String nativeDolbyVision = 'native:dolbyVision';

  /// The route renders through the platform view topology.
  static const String topologyPlatformView = 'topology:platformView';

  /// Shared ordinary MediaCodec decode, independent of frame import mode.
  static const String decoderMediacodec = 'decoder:mediacodec';
  static const String decoderSoftware = 'decoder:ffmpeg-software';
  static const String importMediacodec = 'import:mediacodec-hardware';
  static const String importCpuUpload = 'import:cpu-upload';
  static const String presenterGpuTexture = 'presenter:gpu-next-opengl-texture';
}

/// {@template hdr_route}
///
/// HdrRoute
/// --------
/// One concrete way of presenting the current source: the mpv property set,
/// the output topology, and the surface dataspace request (requirement
/// R4.1). Produced by the strategy realizer from a [HdrStrategy]; consumed
/// identically by the pre-playback prediction and the executor so the two
/// cannot drift apart (R1.3).
///
/// PlatformView GPU HDR routes (`baseLayerConvert`, `metadataReshape`) use
/// the `rgb10_a2` EGL output format; that is an execution detail applied by
/// the session backend and intentionally not part of the route value.
///
/// {@endtemplate}
class HdrRoute {
  /// {@macro hdr_route}
  const HdrRoute({
    required this.strategy,
    required this.presentation,
    required this.outputTransfer,
    required this.appliesDynamicMetadata,
    required this.topology,
    required this.vo,
    required this.hwdec,
    this.vdLavcOptions,
    this.mediacodecEmbedRenderMode,
    required this.targetPrim,
    required this.targetTrc,
    required this.surfaceTransfer,
    required this.stripDvRpu,
    this.metadataHandling = HdrMetadataHandling.none,
    this.offscreenTransfer,
    this.dependencies = const <String>{},
  });

  final HdrStrategy strategy;

  final HdrPresentation presentation;

  /// The transfer function the output emits: `pq`, `hlg`, or `sdr`.
  final HdrOutputTransfer outputTransfer;

  /// Whether the route applies the source's dynamic metadata (DV RPU via
  /// the rescale/reshape pipeline) instead of ignoring it.
  final bool appliesDynamicMetadata;

  final HdrTopology topology;

  /// `vo` mpv property: `gpu-next` or `mediacodec_embed`.
  final String vo;

  /// `hwdec` mpv property.
  final String hwdec;

  /// Explicit `vd-lavc-o` value required by this route, when any.
  final String? vdLavcOptions;

  /// Explicit `mediacodec-embed-render-mode` required by this route, when any.
  final String? mediacodecEmbedRenderMode;

  /// `target-prim` mpv property; null leaves the default.
  final String? targetPrim;

  /// `target-trc` mpv property; null leaves the default.
  final String? targetTrc;

  /// Dataspace requested for the GPU PlatformView surface (`pq`/`hlg`), or
  /// null when the route has no GPU HDR transfer to apply.
  ///
  /// Window contract only (A4 contract split): this labels the presenting
  /// window, not the offscreen intermediary (`pq-itu` = BT2020 PQ / LIMITED
  /// 0x11C60000, the YUV window's forced label). The offscreen encoding of a
  /// route with a separate offscreen contract is [offscreenTransfer]; the
  /// two fields are independent and must never be read interchangeably.
  final String? surfaceTransfer;

  /// Content encoding of the route's offscreen intermediary FBO, when that
  /// offscreen is a contract distinct from the presenting window. Only the
  /// YUV route (SurfaceTexture offscreen → NV12 window) declares one today:
  /// `pq-full` = full-range normalized PQ, the euv13/euv17 accepted offscreen
  /// contract. Routes whose offscreen and window share one RGB contract keep
  /// null — the single window [surfaceTransfer] plus mpv's default output
  /// levels carry the current semantics and nothing is issued offscreen.
  final String? offscreenTransfer;

  /// Whether the Dolby Vision RPU must be stripped from the bitstream.
  final bool stripDvRpu;

  /// Intent only. For C3/C4 the output must be reported as a static
  /// compatibility baseline, not as native or mapped dynamic HDR.
  final HdrMetadataHandling metadataHandling;

  /// The pipeline stages this route depends on (see [HdrRouteDependency]).
  final Set<String> dependencies;

  /// Preserves source processing and all output/color requests while changing
  /// the decode/import execution path. OutputContract derives from this value.
  HdrRoute withExecution(
          {required String hwdec, required Set<String> dependencies}) =>
      HdrRoute(
        strategy: strategy,
        presentation: presentation,
        outputTransfer: outputTransfer,
        appliesDynamicMetadata: appliesDynamicMetadata,
        topology: topology,
        vo: vo,
        hwdec: hwdec,
        vdLavcOptions: vdLavcOptions,
        mediacodecEmbedRenderMode: mediacodecEmbedRenderMode,
        targetPrim: targetPrim,
        targetTrc: targetTrc,
        surfaceTransfer: surfaceTransfer,
        offscreenTransfer: offscreenTransfer,
        stripDvRpu: stripDvRpu,
        metadataHandling: metadataHandling,
        dependencies: Set<String>.unmodifiable(dependencies),
      );

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is HdrRoute &&
        other.strategy == strategy &&
        other.presentation == presentation &&
        other.outputTransfer == outputTransfer &&
        other.appliesDynamicMetadata == appliesDynamicMetadata &&
        other.topology == topology &&
        other.vo == vo &&
        other.hwdec == hwdec &&
        other.vdLavcOptions == vdLavcOptions &&
        other.mediacodecEmbedRenderMode == mediacodecEmbedRenderMode &&
        other.targetPrim == targetPrim &&
        other.targetTrc == targetTrc &&
        other.surfaceTransfer == surfaceTransfer &&
        other.offscreenTransfer == offscreenTransfer &&
        other.stripDvRpu == stripDvRpu &&
        other.metadataHandling == metadataHandling &&
        setEquals(other.dependencies, dependencies);
  }

  @override
  int get hashCode => Object.hash(
        strategy,
        presentation,
        outputTransfer,
        appliesDynamicMetadata,
        topology,
        vo,
        hwdec,
        vdLavcOptions,
        mediacodecEmbedRenderMode,
        targetPrim,
        targetTrc,
        surfaceTransfer,
        offscreenTransfer,
        stripDvRpu,
        metadataHandling,
        Object.hashAllUnordered(dependencies),
      );

  @override
  String toString() => 'HdrRoute(${strategy.name}, ${presentation.name}, '
      'output: ${outputTransfer.name}, dynamic: $appliesDynamicMetadata, '
      'topology: ${topology.name}, vo: $vo, hwdec: $hwdec, '
      'vd-lavc-o: $vdLavcOptions, render-mode: $mediacodecEmbedRenderMode, '
      'prim: $targetPrim, trc: $targetTrc, surface: $surfaceTransfer, '
      'offscreen: ${offscreenTransfer ?? 'none'}, '
      'stripRpu: $stripDvRpu, metadata: ${metadataHandling.name}, '
      'deps: $dependencies)';
}

enum HdrRouteStage { c1, c2, c3, c4 }

enum HdrCandidateStatus { ready, skipped, unavailable, error }

/// {@template hdr_candidate}
///
/// One entry of a prediction's candidate list: a strategy from the
/// preference list (or the final safety net) with its maturity, whether it
/// is feasible on this device, and — when it is not — the typed reason.
///
/// {@endtemplate}
class HdrCandidate {
  /// {@macro hdr_candidate}
  const HdrCandidate({
    required this.strategy,
    required this.maturity,
    this.feasible = false,
    this.isSafetyNet = false,
    this.skipReason,
    this.route,
    this.sourceClass,
    this.stage,
    this.executionId,
  });

  final HdrStrategy strategy;

  /// The source classification and immutable C1–C4 order of this candidate.
  final HdrSourceClass? sourceClass;
  final HdrRouteStage? stage;

  /// Preserved across later rejection/wrapping when a realizable execution
  /// is converted to an infeasible candidate (e.g. HDR cannot fall to SDR).
  final String? executionId;

  /// Stable within a planning snapshot; the snapshot identity itself is owned
  /// by the caller and must be checked again before execution.
  String get candidateId => executionId ?? [
        sourceClass?.name ?? 'unknown',
        stage?.name ?? 'sdr',
        strategy.name,
        route?.vo ?? 'none',
        route?.hwdec ?? 'none',
        route?.outputTransfer.name ?? 'none',
        route?.surfaceTransfer ?? 'none',
        route?.offscreenTransfer ?? 'none',
        route?.vdLavcOptions ?? 'none',
      ].join('/');

  HdrCandidate withRoutingIdentity(HdrSourceClass cls, HdrRouteStage? phase) =>
      HdrCandidate(
        strategy: strategy,
        maturity: maturity,
        feasible: feasible,
        isSafetyNet: isSafetyNet,
        skipReason: skipReason,
        route: route,
        sourceClass: cls,
        stage: phase,
        executionId: [
          cls.name,
          phase?.name ?? 'sdr',
          strategy.name,
          route?.vo ?? 'none',
          route?.hwdec ?? 'none',
          route?.outputTransfer.name ?? 'none',
          route?.surfaceTransfer ?? 'none',
          route?.offscreenTransfer ?? 'none',
          route?.vdLavcOptions ?? 'none',
        ].join('/'),
      );

  final HdrStrategyMaturity maturity;

  /// Whether the strategy can be realized on this device right now.
  final bool feasible;

  /// Explicit source-safe SDR fallback, whose maturity gate was relaxed.
  final bool isSafetyNet;

  /// Why the strategy was not (or cannot be) selected. Null when the
  /// candidate is feasible — including a feasible non-selected candidate
  /// kept for display, and the final safety-net candidate.
  final HdrDegradeReason? skipReason;

  /// An explicit planning state. Runtime playback success is a separate
  /// observation; a later fallback must not erase this candidate's error.
  HdrCandidateStatus get status {
    if (feasible) return HdrCandidateStatus.ready;
    if (skipReason == HdrDegradeReason.routeNotImplemented) {
      return HdrCandidateStatus.error;
    }
    if (skipReason == HdrDegradeReason.unsupportedStrategy ||
        skipReason == HdrDegradeReason.experimentalStrategySkipped) {
      return HdrCandidateStatus.skipped;
    }
    return HdrCandidateStatus.unavailable;
  }

  /// The realized route when [feasible] is true.
  final HdrRoute? route;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is HdrCandidate &&
        other.strategy == strategy &&
        other.maturity == maturity &&
        other.feasible == feasible &&
        other.isSafetyNet == isSafetyNet &&
        other.sourceClass == sourceClass &&
        other.stage == stage &&
        other.executionId == executionId &&
        other.skipReason == skipReason &&
        other.route == route;
  }

  @override
  int get hashCode =>
      Object.hash(strategy, maturity, feasible, isSafetyNet, skipReason, route,
          sourceClass, stage, executionId);

  @override
  String toString() => 'HdrCandidate(${strategy.name}, ${maturity.name}, '
      'feasible: $feasible, skip: ${skipReason?.name}, route: $route)';
}

/// {@template hdr_route_prediction}
///
/// HdrRoutePrediction
/// ------------------
/// The pre-playback answer to "how would this source play here?" (R1.2):
/// the selected candidate, the full ordered candidate list with skip
/// reasons, the presentation type, the confidence, and whether playback can
/// start at all.
///
/// {@endtemplate}
class HdrRoutePrediction {
  /// {@macro hdr_route_prediction}
  const HdrRoutePrediction({
    required this.source,
    required this.selected,
    required this.candidates,
    required this.presentation,
    required this.confidence,
    required this.playable,
  });

  final HdrSourceDescriptor source;

  /// The candidate the planner selected. When nothing in the preference list
  /// survived the gates this is the safety-net candidate (tone-mapped SDR,
  /// or SDR direct for SDR sources); for a P5 source without the rescale
  /// pipeline it is infeasible with [HdrDegradeReason.p5PipelineUnavailable]
  /// and [playable] is false (R3.3).
  final HdrCandidate selected;

  /// Every evaluated candidate in preference order, including skipped ones.
  /// The selected candidate is always a member; the safety-net candidate,
  /// when used, is appended last.
  final List<HdrCandidate> candidates;

  final HdrPresentation presentation;

  final HdrPredictionConfidence confidence;

  /// False when no candidate satisfies source and execution constraints.
  /// Includes missing P5 processing, unresolved DV and failed dependencies.
  final bool playable;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! HdrRoutePrediction) return false;
    if (other.candidates.length != candidates.length) return false;
    for (int i = 0; i < candidates.length; i++) {
      if (other.candidates[i] != candidates[i]) return false;
    }
    return other.source == source &&
        other.selected == selected &&
        other.presentation == presentation &&
        other.confidence == confidence &&
        other.playable == playable;
  }

  @override
  int get hashCode => Object.hash(
        source,
        selected,
        presentation,
        confidence,
        playable,
        Object.hashAll(candidates),
      );

  @override
  String toString() => 'HdrRoutePrediction(selected: $selected, '
      'presentation: ${presentation.name}, confidence: ${confidence.name}, '
      'playable: $playable, candidates: $candidates)';
}

/// A caller/native adapter has identified the failing execution component.
/// Generic errors do not establish this cause. Session verifies the dependency
/// belongs to the failed route before excluding other candidates that share it.
class HdrExecutionDependencyFailure implements Exception {
  const HdrExecutionDependencyFailure(this.dependency, this.reason,
      {this.cause});
  final String dependency;
  final HdrDegradeReason reason;
  final Object? cause;
  @override
  String toString() =>
      'HdrExecutionDependencyFailure($dependency, ${reason.name}, $cause)';
}
