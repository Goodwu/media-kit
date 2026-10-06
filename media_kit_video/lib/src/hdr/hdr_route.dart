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
enum HdrTopology {
  texture,
  platformView,
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
  /// Output forced to SDR because the caller set `HdrOutputPreference.off`.
  preferenceOff,

  /// The display does not report the HDR transfer type the route outputs.
  displayLacksTransfer,

  /// The platform returned no display HDR capability report at all; HDR
  /// routes are never selected on a guess.
  noDisplayCapabilityReport,

  /// The strategy is `experimental` and the routing policy did not set
  /// `allowExperimental` (requirement 3.5).
  experimentalStrategySkipped,

  /// The strategy cannot be realized on the current pipeline at all: a
  /// `nativeDolbyVision` source outside the 2026-10-06 dvP5 experimental
  /// unlock, a strategy that would ignore a P5 RPU, HDR Vivid metadata
  /// rebuild (not implemented), or reshape on a P7 stream whose
  /// enhancement layer may be FEL.
  unsupportedStrategy,

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

  /// The native Dolby Vision decoder/bridge pipeline.
  static const String nativeDolbyVision = 'native:dolbyVision';

  /// The route renders through the platform view topology.
  static const String topologyPlatformView = 'topology:platformView';
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
  final String? surfaceTransfer;

  /// Whether the Dolby Vision RPU must be stripped from the bitstream.
  final bool stripDvRpu;

  /// The pipeline stages this route depends on (see [HdrRouteDependency]).
  final Set<String> dependencies;

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
        other.stripDvRpu == stripDvRpu &&
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
        stripDvRpu,
        Object.hashAllUnordered(dependencies),
      );

  @override
  String toString() => 'HdrRoute(${strategy.name}, ${presentation.name}, '
      'output: ${outputTransfer.name}, dynamic: $appliesDynamicMetadata, '
      'topology: ${topology.name}, vo: $vo, hwdec: $hwdec, '
      'vd-lavc-o: $vdLavcOptions, render-mode: $mediacodecEmbedRenderMode, '
      'prim: $targetPrim, trc: $targetTrc, surface: $surfaceTransfer, '
      'stripRpu: $stripDvRpu, deps: $dependencies)';
}

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
    this.skipReason,
    this.route,
  });

  final HdrStrategy strategy;

  final HdrStrategyMaturity maturity;

  /// Whether the strategy can be realized on this device right now.
  final bool feasible;

  /// Why the strategy was not (or cannot be) selected. Null when the
  /// candidate is feasible — including a feasible non-selected candidate
  /// kept for display, and the final safety-net candidate.
  final HdrDegradeReason? skipReason;

  /// The realized route when [feasible] is true.
  final HdrRoute? route;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is HdrCandidate &&
        other.strategy == strategy &&
        other.maturity == maturity &&
        other.feasible == feasible &&
        other.skipReason == skipReason &&
        other.route == route;
  }

  @override
  int get hashCode =>
      Object.hash(strategy, maturity, feasible, skipReason, route);

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

  /// False only when playback must not start: a P5 source whose dovi
  /// rescale pipeline is missing (R3.3).
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
  int get hashCode => Object.hash(source, selected, presentation, confidence,
      playable, Object.hashAll(candidates));

  @override
  String toString() => 'HdrRoutePrediction(selected: $selected, '
      'presentation: ${presentation.name}, confidence: ${confidence.name}, '
      'playable: $playable, candidates: $candidates)';
}
