import '../routing/video_route_options.dart';
/// This file is a part of media_kit (https://github.com/media-kit/media-kit).
///
/// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
/// All rights reserved.
/// Use of this source code is governed by MIT license that can be found in the LICENSE file.
import '../routing/video_decoder_support.dart';
import 'hdr_strategy.dart';
import 'hdr_route.dart';
import 'hdr_route_planner.dart';
import 'hdr_source_descriptor.dart';

/// Asynchronous libmpv property lookup, e.g. through `Player.getProperty`.
typedef HdrPropertyReader = Future<String> Function(String property);

/// Declarative PQ presentation-channel report of a vendor dataspace
/// extension (plan W1): whether this device can present PQ through the RGB
/// `rgb10_a2` window surface ([rgbSurface], hard-bound to the C2 reshape and
/// the C4 baseline carrier) and/or through the vendor YUV window
/// ([yuvWindow], the alternative C4 carrier). This is a self-report, not a
/// probe result; a device list never lives in routing code.
class HdrPqPresentation {
  const HdrPqPresentation({
    required this.rgbSurface,
    required this.yuvWindow,
  });

  /// PQ through the RGB `rgb10_a2` window surface.
  final bool rgbSurface;

  /// PQ through the vendor YUV window carrier.
  final bool yuvWindow;

  /// Parses the extension report map. Null when the adapter did not report
  /// the structure (legacy adapters) or reported it malformed — never a
  /// default; resolution then falls to the migration/platform defaults.
  static HdrPqPresentation? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final Object? rgbSurface = raw['rgbSurface'];
    final Object? yuvWindow = raw['yuvWindow'];
    if (rgbSurface is! bool || yuvWindow is! bool) return null;
    return HdrPqPresentation(
      rgbSurface: rgbSurface,
      yuvWindow: yuvWindow,
    );
  }

  @override
  String toString() =>
      'HdrPqPresentation(rgbSurface: $rgbSurface, yuvWindow: $yuvWindow)';
}

/// Identifier and device applicability of the natively registered dataspace
/// extension (see `PlatformVideoView.SurfaceDataSpaceExt`). Null on the
/// capability snapshot means no extension is registered in this process.
class HdrDataSpaceExtInfo {
  const HdrDataSpaceExtInfo({
    required this.id,
    required this.applicable,
    this.pqPresentation,
  });

  final String id;

  /// Whether the extension applies to this device, judged by its read-only
  /// check (never by probing a private ABI).
  final bool applicable;

  /// The extension's declared PQ presentation channels, or null when a
  /// legacy adapter reports applicability without the structure (the
  /// snapshot resolution then applies the migration default).
  final HdrPqPresentation? pqPresentation;

  static HdrDataSpaceExtInfo? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final Object? id = raw['id'];
    final Object? applicable = raw['isApplicable'];
    if (id is! String || id.isEmpty) return null;
    return HdrDataSpaceExtInfo(
      id: id,
      applicable: applicable == true,
      pqPresentation: HdrPqPresentation.fromMap(raw['pqPresentation']),
    );
  }

  @override
  String toString() =>
      'HdrDataSpaceExtInfo(id: $id, applicable: $applicable, '
      'pqPresentation: $pqPresentation)';
}

/// One platform decoder entry (HEVC or Dolby Vision) from `MediaCodecList`.
class HdrDecoderInfo {
  const HdrDecoderInfo({
    required this.name,
    required this.mimeType,
    required this.hardwareAcceleration,
    required this.profiles,
    required this.main10,
    required this.widthRange,
    required this.heightRange,
    required this.frameRateRange,
    required this.supports4K,
    required this.max4KFps,
  });

  final String name;
  final String mimeType;
  final bool hardwareAcceleration;

  /// Raw `CodecProfileLevel.profile` values supported by this decoder.
  final List<int> profiles;

  /// HEVC only: whether a Main10 (10-bit, incl. HDR10 variants) profile is
  /// supported. Null for other mime types.
  final bool? main10;

  /// Supported width/height/frame-rate ranges as `[min, max]`; null when the
  /// platform did not report them.
  final List<int>? widthRange;
  final List<int>? heightRange;
  final List<int>? frameRateRange;

  /// Whether 3840x2160 is a supported size.
  final bool supports4K;

  /// Highest frame rate supported at 3840x2160; null when 4K is unsupported.
  final double? max4KFps;

  static HdrDecoderInfo? fromMap(Map<String, Object?> map) {
    final Object? name = map['name'];
    final Object? mimeType = map['mimeType'];
    if (name is! String || name.isEmpty || mimeType is! String) return null;
    return HdrDecoderInfo(
      name: name,
      mimeType: mimeType,
      hardwareAcceleration: map['hardwareAcceleration'] == true,
      profiles: _intList(map['profiles']) ?? const <int>[],
      main10: map['main10'] is bool ? map['main10'] as bool : null,
      widthRange: _intRange(map['widthRange']),
      heightRange: _intRange(map['heightRange']),
      frameRateRange: _intRange(map['frameRateRange']),
      supports4K: map['supports4K'] == true,
      max4KFps:
          map['max4KFps'] is num ? (map['max4KFps'] as num).toDouble() : null,
    );
  }

  static List<int>? _intList(Object? raw) {
    if (raw is! List) return null;
    for (final Object? value in raw) {
      if (value is! int) return null;
    }
    return List<int>.from(raw);
  }

  static List<int>? _intRange(Object? raw) {
    final List<int>? values = _intList(raw);
    if (values == null || values.length != 2) return null;
    return values;
  }

  @override
  String toString() => 'HdrDecoderInfo($name, $mimeType, '
      'hardware: $hardwareAcceleration, main10: $main10, 4K: $supports4K)';
}

/// {@template hdr_capabilities}
///
/// HdrCapabilities
/// ---------------
/// Pre-playback device capability snapshot for HDR output planning (R1).
///
/// VideoRouteCapabilities.query reads the Android side (display HDR types including Dolby Vision,
/// HEVC/Dolby Vision decoder census, dataspace bridge state, registered
/// extension) and takes the P5 dovi rescale pipeline verdict from the native
/// probe: a disposable mpv instance (no vo — never EGL) created once inside
/// the currently loaded libmpv at engine attach, reading the fork's read-only
/// `dovi-p5-pipeline` and `android-native-dv-bridge-api` properties. The
/// snapshot never initializes EGL and never
/// probes private ABIs.
///
/// {@endtemplate}
class HdrCapabilities {
  const HdrCapabilities({
    required this.sdkInt,
    required this.displayHdrTypes,
    required this.hevcDecoders,
    required this.dolbyVisionDecoders,
    required this.p5PipelineAvailable,
    this.nativeDvBridgeApi = 0,
    required this.dataSpaceBridgeLoaded,
    required this.dataSpaceExt,
    this.sourceSupport,
  });

  /// Android SDK version.
  final int sdkInt;

  /// HDR types supported by the queried display target: Dolby Vision (1), HDR10 (2),
  /// HLG (3), HDR10+ (4). Null means the platform reported no capability
  /// report at all — distinct from an empty set (a display that reports
  /// support for none).
  final Set<int>? displayHdrTypes;

  /// HEVC decoders with Main10 support and the 4K size/frame-rate tier.
  final List<HdrDecoderInfo> hevcDecoders;

  /// `video/dolby-vision` decoders, reported as-is (usually empty).
  final List<HdrDecoderInfo> dolbyVisionDecoders;

  /// Whether mpv carries the fork's P5 dovi rescale pipeline, answered by
  /// the native disposable mpv instance probe (the fork's read-only
  /// `dovi-p5-pipeline` property, read once at engine attach and cached).
  final bool p5PipelineAvailable;

  /// Independent native Dolby Vision bridge schema capability. Only version
  /// 1 is understood; 0 means missing, malformed, unavailable or unknown.
  /// This static fact does not prove native codec use or visible HDR output.
  final int nativeDvBridgeApi;

  bool get nativeDvBridgeSupported => nativeDvBridgeApi == 1;

  /// Whether the native Surface dataspace bridge loaded in this process.
  final bool dataSpaceBridgeLoaded;

  /// The registered dataspace extension, or null when none is registered.
  final HdrDataSpaceExtInfo? dataSpaceExt;

  /// Resolved PQ presentation channels (plan W1), in priority order:
  ///
  /// 1. The extension's self-report — a vendor report wins over every
  ///    default (an API>=28 device whose adapter reports `rgbSurface=false`
  ///    is yuv-only all the same).
  /// 2. Migration default: an applicable extension that did not report the
  ///    structure resolves to `{rgbSurface: true, yuvWindow: false}` —
  ///    bit-identical to every pre-W1 behavior.
  /// 3. Platform default: no (or not-applicable) extension resolves by the
  ///    public Android dataspace framework fact — `rgbSurface` from API 28,
  ///    neither channel below it.
  HdrPqPresentation get pqPresentation {
    final HdrDataSpaceExtInfo? ext = dataSpaceExt;
    if (ext != null) {
      final HdrPqPresentation? reported = ext.pqPresentation;
      if (reported != null) return reported;
      if (ext.applicable) {
        return const HdrPqPresentation(rgbSurface: true, yuvWindow: false);
      }
    }
    return sdkInt >= 28
        ? const HdrPqPresentation(rgbSurface: true, yuvWindow: false)
        : const HdrPqPresentation(rgbSurface: false, yuvWindow: false);
  }

  /// Predicts how [source] would play on this device, before any media is
  /// opened (R1.2): the selected candidate, the full candidate list with
  /// skip reasons, the presentation type, and the confidence.
  ///
  /// This is a thin delegation to `HdrRoutePlanner.plan` with this snapshot
  /// — the same function used by the executor. Use
  /// VideoRouteCapabilities.predict with a VideoSourceSpec for source-aware
  /// decoder filtering; this value alone describes HDR routing facts.
  HdrRoutePrediction predict(
    HdrSourceDescriptor source, {
    HdrRoutingPolicy? policy,
    HdrOutputPreference? preference,
    EffectiveVideoRouteOptions? options,
  }) {
    return HdrRoutePlanner.plan(
      source: source,
      capabilities: this,
      policy: policy,
      preference: preference,
      options: options,
    );
  }

  /// Optional exact source declaration attached by the target-aware query.
  /// Null means the caller has not supplied source specifications.
  final VideoSourceSupport? sourceSupport;

  HdrCapabilities withSourceSupport(VideoSourceSupport support) =>
      HdrCapabilities(
        sdkInt: sdkInt,
        displayHdrTypes: displayHdrTypes,
        hevcDecoders: hevcDecoders,
        dolbyVisionDecoders: dolbyVisionDecoders,
        p5PipelineAvailable: p5PipelineAvailable,
        nativeDvBridgeApi: nativeDvBridgeApi,
        dataSpaceBridgeLoaded: dataSpaceBridgeLoaded,
        dataSpaceExt: dataSpaceExt,
        sourceSupport: support,
      );

  /// The source must match the consumer actually used by the route. Native
  /// DV support cannot authorize a HEVC base-layer fallback, or vice versa.
  VideoSupport decoderSupportFor(HdrRoute route) =>
      // MediaCodecList's software rows are not FFmpeg decoder availability.
      route.hwdec == 'no'
          ? VideoSupport.unknown
          : sourceSupport?.support(
                path: route.strategy == HdrStrategy.nativeDolbyVision
                    ? 'nativeDv'
                    : 'codec',
                kind: route.strategy == HdrStrategy.nativeDolbyVision
                    ? VideoDecoderKind.hardware
                    : null,
              ) ??
              VideoSupport.unknown;

  /// Parses the raw native snapshot. Malformed or missing fields degrade to
  /// the safe defaults: no capability report (null displayHdrTypes), no
  /// decoders, no bridge, no extension. Also used by the session to parse
  /// the `HdrCapabilities.Changed` event payload.
  ///
  /// The P5 pipeline verdict is the snapshot's `p5Pipeline` field when
  /// present (the native probe's answer, plan B 2026-10-02); when absent it
  /// falls back to [p5PipelineAvailable] — the Phase 1 parameter kept so the
  /// session's `HdrCapabilities.Changed` payload parsing compiles unchanged —
  /// and both missing degrade to false, never true by accident.
  static HdrCapabilities parseSnapshot(
    Map<Object?, Object?>? snapshot, {
    bool? p5PipelineAvailable,
  }) {
    final Map<String, Object?> map = snapshot == null
        ? const <String, Object?>{}
        : Map<String, Object?>.from(snapshot);
    final Object? p5Raw = map['p5Pipeline'];
    final Object? nativeDvRaw = map['nativeDvBridgeApi'];
    return HdrCapabilities(
      sdkInt: map['sdkInt'] is int ? map['sdkInt'] as int : 0,
      displayHdrTypes: _parseDisplayHdrTypes(map['displayHdrTypes']),
      hevcDecoders: _parseDecoders(map['hevcDecoders']),
      dolbyVisionDecoders: _parseDecoders(map['dolbyVisionDecoders']),
      p5PipelineAvailable:
          p5Raw is bool ? p5Raw : (p5PipelineAvailable ?? false),
      nativeDvBridgeApi: nativeDvRaw is int && nativeDvRaw == 1 ? 1 : 0,
      dataSpaceBridgeLoaded: map['dataSpaceBridgeLoaded'] == true,
      dataSpaceExt: HdrDataSpaceExtInfo.fromMap(map['dataSpaceExt']),
    );
  }

  /// Null unless the platform reported a valid list. A missing, non-list or
  /// malformed report is "no capability report", not "no HDR".
  static Set<int>? _parseDisplayHdrTypes(Object? raw) {
    if (raw is! List) return null;
    final Set<int> types = <int>{};
    for (final Object? value in raw) {
      if (value is! int) return null;
      types.add(value);
    }
    return types;
  }

  static List<HdrDecoderInfo> _parseDecoders(Object? raw) {
    if (raw is! List) return const <HdrDecoderInfo>[];
    final List<HdrDecoderInfo> decoders = <HdrDecoderInfo>[];
    for (final Object? entry in raw) {
      if (entry is! Map) continue;
      final HdrDecoderInfo? decoder = HdrDecoderInfo.fromMap(
        Map<String, Object?>.from(entry),
      );
      if (decoder != null) decoders.add(decoder);
    }
    return decoders;
  }

  @override
  String toString() => 'HdrCapabilities(sdk: $sdkInt, '
      'displayHdrTypes: $displayHdrTypes, hevc: ${hevcDecoders.length}, '
      'dv: ${dolbyVisionDecoders.length}, p5Pipeline: $p5PipelineAvailable, '
      'nativeDvBridgeApi: $nativeDvBridgeApi, '
      'bridge: $dataSpaceBridgeLoaded, ext: $dataSpaceExt)';
}
