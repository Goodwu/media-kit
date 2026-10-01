/// This file is a part of media_kit (https://github.com/media-kit/media-kit).
///
/// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
/// All rights reserved.
/// Use of this source code is governed by MIT license that can be found in the LICENSE file.
import 'package:media_kit/media_kit.dart' show VideoParams;

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
/// | = 7                                                     | dvProfile 7, compat 6; enhancement layer unknown (`null`) |
/// | = 10                                                    | dvProfile 10, codec `av1`, compat inferred from gamma |
/// | no profile, gamma `pq` + primaries `bt.2020`            | HDR10 |
/// | no profile, gamma `hlg`                                 | HLG |
/// | other                                                   | SDR |
///
/// HDR10+ and HDR Vivid dynamic metadata are not observable through mpv yet
/// (assessed separately) and classify as [HdrDynamicMetadata.none]. The
/// compatibility id is inferred from the base-layer transfer function
/// because mpv does not expose `dv_bl_signal_compatibility_id` either.
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
  /// property (`5`, `8`, `10`, ...). Passing hint-less facts produces a
  /// description with an empty codec; pass the track codec through a hint to
  /// keep it populated.
  HdrSourceDescriptor classify({
    VideoParams? videoParams,
    int? dolbyVisionProfile,
    HdrSourceDescriptor? hint,
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
      int? compatibilityId;
      bool? enhancementLayer;
      switch (profile) {
        case 5:
          compatibilityId = 0;
          enhancementLayer = false; // Single layer.
          break;
        case 7:
          compatibilityId = 6;
          // The profile-7 enhancement layer (MEL/FEL) is not observable
          // through mpv yet and stays unknown.
          enhancementLayer = null;
          break;
        case 8:
        case 10:
          compatibilityId = _compatibilityIdFromBaseLayer(gamma);
          enhancementLayer = false; // Single layer.
          break;
        default:
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
    return HdrSourceDescriptor(
      codec: hint?.codec ?? '',
      transfer: gamma,
      primaries: primaries,
      // Base-layer-only sources never carry an enhancement layer.
      enhancementLayer: false,
    );
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
