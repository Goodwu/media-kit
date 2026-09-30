/// This file is a part of media_kit (https://github.com/media-kit/media-kit).
///
/// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
/// All rights reserved.
/// Use of this source code is governed by MIT license that can be found in the LICENSE file.
import 'package:media_kit/media_kit.dart' show VideoParams;

/// {@template hdr_media_kind}
///
/// The HDR classification of the media itself, derived from decoder-reported
/// metadata — never from the file name or a caller's guess.
///
/// {@endtemplate}
enum HdrMediaKind {
  /// SDR, or HDR metadata this policy does not route specially.
  sdr,

  /// HDR10: PQ transfer with BT.2020 primaries.
  hdr10,

  /// HLG transfer.
  hlg,

  /// Dolby Vision profile 5 (IPTPQc2, requires the dovi rescale pipeline).
  dolbyVisionP5,

  /// Dolby Vision profile 8.4 (HLG-compatible cross-compatibility profile).
  dolbyVisionP84,
}

/// {@template hdr_output_policy}
///
/// HdrOutputPolicy
/// ---------------
/// Pure routing policy from media metadata, display capabilities and platform
/// capabilities to the mpv properties and output topology for Android video
/// output.
///
/// Inputs are facts only: [VideoParams] (gamma/primaries), the raw
/// `dolby-vision-profile` value, the Android `Display.HdrCapabilities` set,
/// and which output topologies the current build can use. The result is the
/// `vo`/`hwdec`/`target-prim`/`target-trc` mpv property set, the PlatformView
/// dataspace request, and whether a Dolby Vision RPU must be stripped for the
/// chosen route.
///
/// The policy throws [StateError] instead of silently degrading whenever an
/// HDR route is requested that the display or the build cannot actually
/// present — callers decide how to surface the failure.
///
/// {@endtemplate}
class HdrOutputPolicy {
  const HdrOutputPolicy({
    required this.vo,
    required this.hwdec,
    required this.targetPrim,
    required this.targetTrc,
    required this.surfaceTransfer,
    required this.stripDvRpu,
  });

  /// `vo` mpv property: `gpu-next` (GL/GPU output) or `mediacodec_embed`
  /// (decoder output composited by SurfaceFlinger).
  final String vo;

  /// `hwdec` mpv property.
  final String hwdec;

  /// `target-prim` mpv property, `null` leaves the default.
  final String? targetPrim;

  /// `target-trc` mpv property, `null` leaves the default.
  final String? targetTrc;

  /// Dataspace requested for the GPU PlatformView surface. `null` when the
  /// route has no GPU HDR transfer to apply (direct/Texture output or
  /// `mediacodec_embed`).
  final String? surfaceTransfer;

  /// Whether the Dolby Vision RPU must be stripped from the bitstream for
  /// this route (profile 8.4 rendered through a non-dovi path).
  final bool stripDvRpu;

  /// Android `Display.HdrCapabilities` type constants.
  static const int displayHdrTypeHdr10 = 2;
  static const int displayHdrTypeHlg = 3;

  /// Classifies media from decoder-reported metadata.
  static HdrMediaKind classifyMedia({
    VideoParams? videoParams,
    String? dolbyVisionProfile,
  }) {
    switch (dolbyVisionProfile) {
      case '5':
        return HdrMediaKind.dolbyVisionP5;
      case '8.4':
        return HdrMediaKind.dolbyVisionP84;
    }
    final gamma = videoParams?.gamma;
    if (gamma == 'hlg') return HdrMediaKind.hlg;
    if (gamma == 'pq' && videoParams?.primaries == 'bt.2020') {
      return HdrMediaKind.hdr10;
    }
    return HdrMediaKind.sdr;
  }

  /// Routes [kind] to mpv properties and output topology.
  ///
  /// [displayHdrTypes] carries the Android `Display.HdrCapabilities` set.
  /// It must be provided for PlatformView HDR routes; an absent capability
  /// report must not silently select an HDR route.
  ///
  /// [p5DoviRescaleAvailable] reports whether the libmpv build carries the
  /// P5 dovi metadata rescale pipeline; profile 5 must not be opened without
  /// it. [preferGpuOutput] opts into the `gpu-next` + HDR dataspace surface
  /// route where `mediacodec_embed` would otherwise be selected.
  static HdrOutputPolicy decide(
    HdrMediaKind kind, {
    required bool usePlatformView,
    required bool p5DoviRescaleAvailable,
    Set<int>? displayHdrTypes,
    bool preferGpuOutput = false,
  }) {
    if (kind == HdrMediaKind.dolbyVisionP5 && !p5DoviRescaleAvailable) {
      throw StateError('P5 RPU-preserving native pipeline is not built');
    }
    if (!usePlatformView) {
      // Texture SDR: tone-map every HDR kind to BT.709/BT.1886. SDR media
      // keeps the decoder-reported tags instead of forcing tone-map targets.
      final sdr = kind == HdrMediaKind.sdr;
      return HdrOutputPolicy(
        vo: 'gpu-next',
        hwdec: 'mediacodec',
        targetPrim: sdr ? null : 'bt.709',
        targetTrc: sdr ? null : 'bt.1886',
        surfaceTransfer: null,
        stripDvRpu: kind == HdrMediaKind.dolbyVisionP84,
      );
    }
    if (kind == HdrMediaKind.sdr) {
      return HdrOutputPolicy(
        vo: 'gpu-next',
        hwdec: 'mediacodec',
        targetPrim: null,
        targetTrc: null,
        surfaceTransfer: null,
        stripDvRpu: false,
      );
    }
    // Android Display.HdrCapabilities: HDR10=2, HLG=3. An absent capability
    // report must not silently select an HDR output route.
    if (displayHdrTypes == null) {
      throw StateError('No display HDR capability report');
    }
    final supportsHdr10 = displayHdrTypes.contains(displayHdrTypeHdr10);
    final supportsHlg = displayHdrTypes.contains(displayHdrTypeHlg);
    switch (kind) {
      case HdrMediaKind.hlg:
        if (!supportsHlg) {
          throw StateError('HLG output requires display HLG support');
        }
        return const HdrOutputPolicy(
          vo: 'mediacodec_embed',
          hwdec: 'mediacodec',
          targetPrim: null,
          targetTrc: null,
          surfaceTransfer: null,
          stripDvRpu: false,
        );
      case HdrMediaKind.dolbyVisionP84:
        if (supportsHlg) {
          if (preferGpuOutput) {
            return const HdrOutputPolicy(
              vo: 'gpu-next',
              hwdec: 'mediacodec',
              targetPrim: 'bt.2020',
              targetTrc: 'hlg',
              surfaceTransfer: 'hlg',
              stripDvRpu: true,
            );
          }
          return const HdrOutputPolicy(
            vo: 'mediacodec_embed',
            hwdec: 'mediacodec',
            targetPrim: null,
            targetTrc: null,
            surfaceTransfer: null,
            stripDvRpu: false,
          );
        }
        if (supportsHdr10) {
          return const HdrOutputPolicy(
            vo: 'gpu-next',
            hwdec: 'mediacodec',
            targetPrim: 'bt.2020',
            targetTrc: 'pq',
            surfaceTransfer: 'pq',
            stripDvRpu: true,
          );
        }
        throw StateError('P8.4 requires display HLG or HDR10 support');
      case HdrMediaKind.dolbyVisionP5:
      case HdrMediaKind.hdr10:
        if (!supportsHdr10) {
          throw StateError('PQ output requires display HDR10 support');
        }
        if (kind == HdrMediaKind.dolbyVisionP5 || preferGpuOutput) {
          return const HdrOutputPolicy(
            vo: 'gpu-next',
            hwdec: 'mediacodec',
            targetPrim: 'bt.2020',
            targetTrc: 'pq',
            surfaceTransfer: 'pq',
            stripDvRpu: false,
          );
        }
        return const HdrOutputPolicy(
          vo: 'mediacodec_embed',
          hwdec: 'mediacodec',
          targetPrim: null,
          targetTrc: null,
          surfaceTransfer: null,
          stripDvRpu: false,
        );
      case HdrMediaKind.sdr:
        break; // handled above; unreachable for HDR-flagged input.
    }
    throw StateError('unreachable');
  }
}
