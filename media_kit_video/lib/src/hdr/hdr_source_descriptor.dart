/// This file is a part of media_kit (https://github.com/media-kit/media-kit).
///
/// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
/// All rights reserved.
/// Use of this source code is governed by MIT license that can be found in the LICENSE file.
import 'hdr_output_policy.dart' show HdrMediaKind;

/// {@template hdr_dynamic_metadata}
///
/// The dynamic metadata format carried on top of the base layer, as far as
/// it is knowable on this platform. Dolby Vision is detected from the
/// decoder-reported `dolby-vision-profile`; HDR Vivid from the fork's
/// per-frame `video-params/hdr-vivid` side-data fact (0f7e6bec32+); HDR10+
/// is not exposed by mpv yet and stays [HdrDynamicMetadata.none] until a
/// source for it exists.
///
/// {@endtemplate}
enum HdrDynamicMetadata {
  /// No dynamic metadata, or a format this build cannot detect yet.
  none,

  /// Dolby Vision RPU metadata.
  dolbyVision,

  /// HDR Vivid (CUVA 005) dynamic metadata.
  hdrVivid,

  /// HDR10+ (SMPTE ST 2094-40) dynamic metadata.
  hdr10Plus,
}

/// {@template hdr_source_descriptor}
///
/// HdrSourceDescriptor
/// -------------------
/// Decoder-fact description of an HDR source. Every field is a fact reported
/// by the decoder or an explicit caller hint — never derived from the file
/// name. Fields the current pipeline cannot observe carry the documented
/// unknown value instead of a guess.
///
/// The legacy [HdrMediaKind] classification is derived from this description
/// through [kind], which keeps the existing routing behavior intact while
/// letting callers describe sources with more precision.
///
/// {@endtemplate}
class HdrSourceDescriptor {
  /// Lowercase codec/container name as reported by the decoder: `hevc`,
  /// `av1`, `h264`, ... Empty string when unknown.
  ///
  /// mpv reports it as `current-tracks/video/codec`; `VideoParams` does not
  /// carry it, so the source classifier fills it from a hint or from the
  /// profile itself (profile 10 is AV1).
  final String codec;

  /// Base-layer transfer function (mpv `video-params/gamma`): `pq`, `hlg`,
  /// `bt.1886`, `srgb`, ... `null` when unknown.
  final String? transfer;

  /// Base-layer color primaries (mpv `video-params/primaries`): `bt.2020`,
  /// `bt.709`, ... `null` when unknown.
  final String? primaries;

  /// Dynamic metadata format carried on top of the base layer.
  final HdrDynamicMetadata dynamicMetadata;

  /// Dolby Vision profile: `5`, `7`, `8`, `10`, ... `null` for non-Dolby
  /// Vision sources and when the decoder did not report a profile.
  final int? dvProfile;

  /// Dolby Vision base-layer signal compatibility id (e.g. `1` for 8.1,
  /// `4` for 8.4, `2` for 8.2, `6` for profile 7, `0` for profile 5).
  ///
  /// Authoritative from the container when the decoder review reports the
  /// fork property `current-tracks/video/dolby-vision-compatibility-id`
  /// (0f7e6bec32+) — the DOVI configuration record is the DV signaling
  /// itself; otherwise it is inferred from the base-layer transfer function
  /// (`pq`→1, `hlg`→4, SDR gamma→2, profile 7→6, profile 5→0) or carried
  /// over from a hint. `null` when unknown.
  final int? dvCompatibilityId;

  /// Whether the stream carries a Dolby Vision enhancement layer (profile 7
  /// FEL/MEL). Authoritative from the container when the decoder review
  /// reports the fork property `current-tracks/video/dolby-vision-el-present`
  /// (0f7e6bec32+; the configuration record does not distinguish FEL/MEL).
  /// `null` = unknown: the property is unavailable (no DOVI configuration
  /// record, upstream mpv), and profile-7-dependent strategies must treat
  /// unknown as base-layer-only.
  final bool? enhancementLayer;

  /// {@macro hdr_source_descriptor}
  const HdrSourceDescriptor({
    this.codec = '',
    this.transfer,
    this.primaries,
    this.dynamicMetadata = HdrDynamicMetadata.none,
    this.dvProfile,
    this.dvCompatibilityId,
    this.enhancementLayer,
  });

  /// Builds a descriptor from the legacy [HdrMediaKind] classification, for
  /// callers that only know the kind (hint channels, old code paths).
  ///
  /// Every kind maps to a fully determined source class, so enhancement
  /// layer absence is stated as fact (`false`) rather than unknown.
  factory HdrSourceDescriptor.fromKind(HdrMediaKind kind) {
    switch (kind) {
      case HdrMediaKind.dolbyVisionP5:
        return const HdrSourceDescriptor(
          codec: 'hevc',
          dynamicMetadata: HdrDynamicMetadata.dolbyVision,
          dvProfile: 5,
          dvCompatibilityId: 0,
          enhancementLayer: false,
        );
      case HdrMediaKind.dolbyVisionP84:
        return const HdrSourceDescriptor(
          codec: 'hevc',
          transfer: 'hlg',
          dynamicMetadata: HdrDynamicMetadata.dolbyVision,
          dvProfile: 8,
          dvCompatibilityId: 4,
          enhancementLayer: false,
        );
      case HdrMediaKind.hdr10:
        return const HdrSourceDescriptor(
          transfer: 'pq',
          primaries: 'bt.2020',
          enhancementLayer: false,
        );
      case HdrMediaKind.hlg:
        return const HdrSourceDescriptor(
          transfer: 'hlg',
          enhancementLayer: false,
        );
      case HdrMediaKind.sdr:
        return const HdrSourceDescriptor(enhancementLayer: false);
    }
  }

  /// The legacy [HdrMediaKind] classification derived from this description.
  ///
  /// Dolby Vision profile 5 → [HdrMediaKind.dolbyVisionP5]; profile 7 and
  /// profile 8.1 (compatibility id 1) → [HdrMediaKind.hdr10] (the profile-7
  /// base layer is HDR10-compatible and this preserves the existing routing
  /// behavior); profile 8.4 (compatibility id 4) →
  /// [HdrMediaKind.dolbyVisionP84]; profile 8.2 (compatibility id 2) →
  /// [HdrMediaKind.sdr]; profile 10 and profile 8 with an unknown
  /// compatibility id follow the base-layer transfer function (profile 8
  /// additionally maps `hlg` to 8.4's kind), as do non-Dolby Vision
  /// sources: `hlg` → [HdrMediaKind.hlg], `pq` with `bt.2020` primaries →
  /// [HdrMediaKind.hdr10], everything else → [HdrMediaKind.sdr].
  HdrMediaKind get kind {
    if (dynamicMetadata == HdrDynamicMetadata.dolbyVision) {
      switch (dvProfile) {
        case 5:
          return HdrMediaKind.dolbyVisionP5;
        case 7:
          // The profile-7 base layer is HDR10-compatible; enhancement-layer
          // handling is a routing concern, not part of the legacy kind.
          return HdrMediaKind.hdr10;
        case 8:
          switch (dvCompatibilityId) {
            case 1:
              return HdrMediaKind.hdr10; // 8.1
            case 4:
              return HdrMediaKind.dolbyVisionP84; // 8.4
            case 2:
              return HdrMediaKind.sdr; // 8.2
          }
          // Unknown compatibility id: an HLG base layer identifies 8.4,
          // everything else follows the base layer (PQ+BT.2020 → 8.1's
          // HDR10 kind, SDR gamma → 8.2's SDR kind).
          if (transfer == 'hlg') return HdrMediaKind.dolbyVisionP84;
          return _kindFromBaseLayer();
        case 10:
          return _kindFromBaseLayer();
      }
    }
    return _kindFromBaseLayer();
  }

  /// Base-layer fallback for the legacy kind: HLG, HDR10, then SDR.
  HdrMediaKind _kindFromBaseLayer() {
    if (transfer == 'hlg') return HdrMediaKind.hlg;
    if (transfer == 'pq' && primaries == 'bt.2020') {
      return HdrMediaKind.hdr10;
    }
    return HdrMediaKind.sdr;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is HdrSourceDescriptor &&
        other.codec == codec &&
        other.transfer == transfer &&
        other.primaries == primaries &&
        other.dynamicMetadata == dynamicMetadata &&
        other.dvProfile == dvProfile &&
        other.dvCompatibilityId == dvCompatibilityId &&
        other.enhancementLayer == enhancementLayer;
  }

  @override
  int get hashCode => Object.hash(codec, transfer, primaries, dynamicMetadata,
      dvProfile, dvCompatibilityId, enhancementLayer);

  @override
  String toString() => 'HdrSourceDescriptor('
      'codec: $codec, '
      'transfer: $transfer, '
      'primaries: $primaries, '
      'dynamicMetadata: $dynamicMetadata, '
      'dvProfile: $dvProfile, '
      'dvCompatibilityId: $dvCompatibilityId, '
      'enhancementLayer: $enhancementLayer'
      ')';
}
