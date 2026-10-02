/// This file is a part of media_kit (https://github.com/media-kit/media-kit).
///
/// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
/// All rights reserved.
/// Use of this source code is governed by MIT license that can be found in the LICENSE file.
import 'package:media_kit/media_kit.dart' show Media, VideoParams;

import 'hdr_capabilities.dart';
import 'hdr_route.dart';
import 'hdr_source_descriptor.dart';

/// Where a plan's [HdrSourceDescriptor] came from.
///
/// * [hint]: the caller supplied the description at open time.
/// * [decoder]: the description was re-derived from decoder-reported facts.
/// * null: no hint was given and the decoder has not reported yet (the plan
///   assumed a plain SDR source).
enum HdrReportSource { hint, decoder }

/// One open request handed to `HdrOpenCoordinator.openSource`.
class HdrOpenRequest {
  const HdrOpenRequest(this.media, this.hint);

  final Media media;

  /// Optional caller-supplied source description used to pre-configure the
  /// route before the decoder reports (R2.3).
  final HdrSourceDescriptor? hint;
}

/// The immutable per-generation open plan: the media, the description the
/// route was planned against, the planner output, and the selected route.
/// Produced by the session's preparer and threaded through every backend
/// phase; a review-driven or degradation-driven rebuild replaces it with a
/// new instance via [copyWith].
class HdrOpenPlan {
  const HdrOpenPlan({
    required this.media,
    required this.source,
    required this.sourceOrigin,
    required this.capabilities,
    required this.prediction,
    required this.route,
    this.excluded = const <String, HdrDegradeReason>{},
  });

  final Media media;

  /// The description the [route] was planned against.
  final HdrSourceDescriptor source;

  /// Whether [source] came from the caller hint or from the decoder review.
  final HdrReportSource? sourceOrigin;

  /// The capability snapshot the route was planned against.
  final HdrCapabilities capabilities;

  /// The planner output [route] was selected from, including the full
  /// candidate list with skip reasons (R4.2).
  final HdrRoutePrediction prediction;

  /// The selected route to execute.
  final HdrRoute route;

  /// Pipeline stages excluded by runtime failures so far in this open.
  final Map<String, HdrDegradeReason> excluded;

  HdrOpenPlan copyWith({
    HdrSourceDescriptor? source,
    HdrReportSource? sourceOrigin,
    HdrCapabilities? capabilities,
    HdrRoutePrediction? prediction,
    HdrRoute? route,
    Map<String, HdrDegradeReason>? excluded,
  }) {
    return HdrOpenPlan(
      media: media,
      source: source ?? this.source,
      sourceOrigin: sourceOrigin ?? this.sourceOrigin,
      capabilities: capabilities ?? this.capabilities,
      prediction: prediction ?? this.prediction,
      route: route ?? this.route,
      excluded: excluded ?? this.excluded,
    );
  }

  @override
  String toString() => 'HdrOpenPlan(${media.uri}, source: $source, '
      'route: $route, excluded: $excluded)';
}

/// Decoder-reported facts gathered by the backend for the review phase
/// (plan 1.4 step 8). The decision itself is made by the session.
class HdrReviewFacts {
  const HdrReviewFacts({
    this.videoParams,
    this.dolbyVisionProfile,
    this.codec = '',
    this.hwdecCurrent = '',
    this.path = '',
    this.dvCompatibilityId,
    this.dvElPresent,
    this.hdrVivid,
  });

  /// Latest decoder-reported video parameters (`video-params`).
  final VideoParams? videoParams;

  /// `current-tracks/video/dolby-vision-profile` parsed as an integer
  /// (mpv reports it as an integer property: `5`, `8`, ...).
  final int? dolbyVisionProfile;

  /// `current-tracks/video/codec` (`VideoParams` does not carry it).
  final String codec;

  /// `hwdec-current`.
  final String hwdecCurrent;

  /// `path` observed after file-loaded.
  final String path;

  /// Container Dolby Vision compatibility id from the fork property
  /// `current-tracks/video/dolby-vision-compatibility-id` (fork
  /// 0f7e6bec32+). Unavailable for a stream without a DOVI configuration
  /// record; `0` is a valid value (the DV spec's "None"); `-1` is the
  /// in-record "unknown" sentinel. Every non-parsed value (unavailable,
  /// non-numeric) and every negative value reads as `null` = unknown/not
  /// observable; the classifier then falls back to base-layer inference.
  final int? dvCompatibilityId;

  /// Container Dolby Vision enhancement-layer presence from the fork
  /// property `current-tracks/video/dolby-vision-el-present` (fork
  /// 0f7e6bec32+): `1` → true, `0` → false, `-1` (unknown sentinel) and
  /// every non-parsed value (unavailable, non-numeric) → `null` = unknown.
  /// The configuration record does not distinguish FEL/MEL; it only states
  /// whether the enhancement layer exists.
  final bool? dvElPresent;

  /// Per-frame HDR Vivid side-data presence from the fork property
  /// `video-params/hdr-vivid` (fork 0f7e6bec32+): `yes` → true, `no` →
  /// false, every other/unavailable value → `null` = unknown (upstream mpv
  /// has no such sub-property). The review samples this once — it is a
  /// frame fact, not a watched property.
  final bool? hdrVivid;
}

/// Backend observation pulled by the session to build a report (R4.2):
/// the dataspace application outcome and the last observed `hwdec-current`.
class HdrBackendObservation {
  const HdrBackendObservation({
    this.dataSpaceRequested,
    this.dataSpacePath,
    this.dataSpaceReadback,
    this.hwdecCurrent,
  });

  /// The transfer requested for the GPU surface (`pq`/`hlg`), if any.
  final String? dataSpaceRequested;

  /// Actual applied path: `ndk`/`surfaceControl`/`ext:<id>`/`none`.
  final String? dataSpacePath;

  /// The dataspace read back from the surface, or `none`.
  final String? dataSpaceReadback;

  /// Last observed `hwdec-current`.
  final String? hwdecCurrent;
}

/// Playback must not start (R3.3): a P5 source whose dovi rescale pipeline
/// is missing would render wrongly colored output, so the library refuses
/// to open the media.
class HdrPlaybackBlocked implements Exception {
  const HdrPlaybackBlocked(this.reason);

  /// Why playback is blocked; [HdrDegradeReason.p5PipelineUnavailable] in
  /// Phase 1.
  final HdrDegradeReason reason;

  @override
  String toString() => 'HdrPlaybackBlocked(${reason.name})';
}

/// The surface dataspace application failed (R3.1). [reason] distinguishes a
/// straight apply failure from a readback mismatch on the paths where the
/// readback is expected to match the request.
class HdrDataSpaceApplyException implements Exception {
  const HdrDataSpaceApplyException(
    this.transfer, {
    this.path,
    this.readback,
    required this.reason,
  });

  /// The requested transfer (`pq`/`hlg`).
  final String transfer;

  /// Applied path reported by the native side, when known.
  final String? path;

  /// Readback reported by the native side, when known.
  final String? readback;

  /// [HdrDegradeReason.dataSpaceApplyFailed] or
  /// [HdrDegradeReason.dataSpaceReadbackMismatch].
  final HdrDegradeReason reason;

  @override
  String toString() => 'HdrDataSpaceApplyException($transfer, path: $path, '
      'readback: $readback, reason: ${reason.name})';
}
