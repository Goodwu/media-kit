/// This file is a part of media_kit (https://github.com/media-kit/media-kit).
///
/// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
/// All rights reserved.
/// Use of this source code is governed by MIT license that can be found in the LICENSE file.
import 'package:media_kit/media_kit.dart' show VideoParams;

import 'hdr_output_diagnostics.dart';
import 'hdr_source_descriptor.dart';

/// {@template hdr_source_classifier}
///
/// HdrSourceClassifier
/// -------------------
/// Maps decoder-reported facts to an [HdrSourceDescriptor].
///
/// Classification rules (decoder facts in, description out):
///
/// | Decoder facts                                          | Description |
/// |--------------------------------------------------------|-------------|
/// | `dolby-vision-profile` = 5                              | dvProfile 5, dynamicMetadata dolbyVision, compat 0 |
/// | = 8, gamma `pq`, primaries `bt.2020`                    | dvProfile 8, compat 1 (8.1) |
/// | = 8, gamma `hlg`                                        | dvProfile 8, compat 4 (8.4) |
/// | = 8, SDR gamma (`bt.1886`/`srgb`/...)                   | dvProfile 8, compat 2 (8.2) |
/// | = 7                                                     | dvProfile 7, compat 6; enhancement layer from `el-present` when reported, unknown (`null`) otherwise |
/// | = 10                                                    | dvProfile 10, codec `av1`, compat inferred from gamma |
/// | no profile, gamma `pq` + primaries `bt.2020`            | HDR10 |
/// | no profile, gamma `hlg`                                 | HLG |
/// | other                                                   | SDR |
///
/// The mpv fork (0f7e6bec32+) exposes the container DV compatibility id
/// (`current-tracks/video/dolby-vision-compatibility-id`) and the
/// enhancement-layer presence flag
/// (`current-tracks/video/dolby-vision-el-present`); when the review
/// reports them, they are authoritative — the container record is the DV
/// signaling itself — and the base-layer transfer inference is only the
/// fallback for a `null` compatibility fact. A missing enhancement-layer
/// fact stays unknown for every supported DV profile. HDR Vivid is
/// observable as a per-frame side-data fact (`video-params/hdr-vivid`): a
/// reported `true` classifies a profile-less source as
/// [HdrDynamicMetadata.hdrVivid]. HDR10+ remains not observable through mpv
/// and stays [HdrDynamicMetadata.none].
///
/// When no decoder facts are available at all ([VideoParams] and the profile
/// both absent), the optional [hint] descriptor is returned as-is so a hint
/// passed at open time survives until the decoder reports; otherwise the
/// hint only fills the [HdrSourceDescriptor.codec] gap, which `VideoParams`
/// does not carry. Facts always win over the hint.
///
/// {@endtemplate}
class HdrSourceClassifier {
  /// {@macro hdr_source_classifier}
  const HdrSourceClassifier();

  /// Classifies a source from decoder-reported facts and an optional hint.
  ///
  /// [dolbyVisionProfile] is the raw integer `dolby-vision-profile` mpv
  /// property (`5`, `8`, `10`, ...). [dvCompatibilityId] and [dvElPresent]
  /// are the container facts from the fork's compatibility-id/el-present
  /// properties; when reported they take priority over inference. A missing
  /// compatibility id may use the profile/gamma defaults; a missing EL
  /// fact remains unknown and must not authorize native single-layer DV.
  /// [hdrVivid] is the per-frame side-data fact from `video-params/hdr-vivid`;
  /// it applies only to profile-less sources (a DV profile and HDR Vivid
  /// side data never co-occur — when both appear, the DV branch wins).
  /// Passing hint-less facts produces a description with an empty codec;
  /// pass the track codec through a hint to keep it populated.
  HdrSourceDescriptor classify({
    VideoParams? videoParams,
    int? dolbyVisionProfile,
    HdrSourceDescriptor? hint,
    int? dvCompatibilityId,
    bool? dvElPresent,
    bool? hdrVivid,
  }) {
    final bool hasFacts = videoParams != null || dolbyVisionProfile != null;
    final HdrSourceDescriptor descriptor = _classify(
      videoParams: videoParams,
      dolbyVisionProfile: dolbyVisionProfile,
      hint: hint,
      dvCompatibilityId: dvCompatibilityId,
      dvElPresent: dvElPresent,
      hdrVivid: hdrVivid,
    );
    // `HDR classify:` layer (R4.3): the description plus where it came from.
    // Short-circuits inside while disabled; no strings are built here.
    HdrOutputDiagnostics.classify(
      descriptor: descriptor,
      origin: !hasFacts ? (hint == null ? 'default' : 'hint') : 'facts',
    );
    return descriptor;
  }

  HdrSourceDescriptor _classify({
    VideoParams? videoParams,
    int? dolbyVisionProfile,
    HdrSourceDescriptor? hint,
    int? dvCompatibilityId,
    bool? dvElPresent,
    bool? hdrVivid,
  }) {
    // No decoder facts yet: the hint (if any) is the only description
    // available. Without a hint the source stays undescribed/SDR until the
    // decoder reports.
    if (videoParams == null && dolbyVisionProfile == null) {
      return hint ?? const HdrSourceDescriptor();
    }
    final gamma = videoParams?.gamma;
    final primaries = videoParams?.primaries;
    final profile = dolbyVisionProfile;
    if (profile != null) {
      // Container fact first (authoritative when reported, any negative
      // value including the `-1` sentinel reads as unknown), base-layer
      // inference as the fallback.
      final int? compatibilityId = _containerCompatibilityId(
        dvCompatibilityId,
        profile: profile,
        gamma: gamma,
      );
      final bool? enhancementLayer;
      switch (profile) {
        case 5:
        case 7:
        case 8:
        case 10:
          // Preserve the actual container fact. In particular, P8's missing
          // EL field cannot become false before native-DV admission checks
          // it. Presence alone also does not distinguish P7 MEL from FEL.
          enhancementLayer = dvElPresent;
          break;
        default:
          enhancementLayer = null;
          break;
      }
      return HdrSourceDescriptor(
        codec: profile == 10 ? 'av1' : (hint?.codec ?? ''),
        transfer: gamma,
        primaries: primaries,
        dynamicMetadata: HdrDynamicMetadata.dolbyVision,
        dvProfile: profile,
        dvCompatibilityId: compatibilityId,
        enhancementLayer: enhancementLayer,
      );
    }
    // Profile-less sources: HDR Vivid side data observed on a frame is the
    // only detectable dynamic metadata; false/unknown stays none.
    return HdrSourceDescriptor(
      codec: hint?.codec ?? '',
      transfer: gamma,
      primaries: primaries,
      dynamicMetadata: hdrVivid == true
          ? HdrDynamicMetadata.hdrVivid
          : HdrDynamicMetadata.none,
      // Base-layer-only sources never carry an enhancement layer.
      enhancementLayer: false,
    );
  }

  /// The compatibility id for a DV profile: the container fact when
  /// reported (any negative value including the `-1` sentinel reads as
  /// unknown), otherwise the profile default or the base-layer inference.
  int? _containerCompatibilityId(
    int? dvCompatibilityId, {
    required int profile,
    required String? gamma,
  }) {
    if (dvCompatibilityId != null && dvCompatibilityId >= 0) {
      return dvCompatibilityId;
    }
    switch (profile) {
      case 5:
        return 0;
      case 7:
        return 6;
      case 8:
      case 10:
        return _compatibilityIdFromBaseLayer(gamma);
      default:
        return null;
    }
  }

  /// Base-layer compatibility-id inference for profiles 8 and 10, where the
  /// profile alone does not identify the cross-compatibility family:
  /// `pq` → 1 (8.1), `hlg` → 4 (8.4), SDR gammas (`bt.1886`/`srgb`/...) →
  /// 2 (8.2). `null` gamma stays unknown.
  int? _compatibilityIdFromBaseLayer(String? gamma) {
    if (gamma == null) return null;
    if (gamma == 'pq') return 1; // 8.1
    if (gamma == 'hlg') return 4; // 8.4
    return 2; // 8.2 (SDR base layer)
  }
}
