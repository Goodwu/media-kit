/// This file is a part of media_kit (https://github.com/media-kit/media-kit).
///
/// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
/// All rights reserved.
/// Use of this source code is governed by MIT license that can be found in the LICENSE file.
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:media_kit/media_kit.dart' show Player;

import 'hdr_output_diagnostics.dart';
import 'hdr_route.dart';
import 'hdr_route_planner.dart';
import 'hdr_source_descriptor.dart';

/// Asynchronous libmpv property lookup, e.g. through `Player.getProperty`.
typedef HdrPropertyReader = Future<String> Function(String property);

/// Identifier and device applicability of the natively registered dataspace
/// extension (see `PlatformVideoView.SurfaceDataSpaceExt`). Null on the
/// capability snapshot means no extension is registered in this process.
class HdrDataSpaceExtInfo {
  const HdrDataSpaceExtInfo({required this.id, required this.applicable});

  final String id;

  /// Whether the extension applies to this device, judged by its read-only
  /// check (never by probing a private ABI).
  final bool applicable;

  static HdrDataSpaceExtInfo? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final Object? id = raw['id'];
    final Object? applicable = raw['isApplicable'];
    if (id is! String || id.isEmpty) return null;
    return HdrDataSpaceExtInfo(id: id, applicable: applicable == true);
  }

  @override
  String toString() => 'HdrDataSpaceExtInfo(id: $id, applicable: $applicable)';
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
      max4KFps: map['max4KFps'] is num ? (map['max4KFps'] as num).toDouble() : null,
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
/// [query] reads the Android side (display HDR types including Dolby Vision,
/// HEVC/Dolby Vision decoder census, dataspace bridge state, registered
/// extension) and takes the P5 dovi rescale pipeline verdict from the native
/// probe: a disposable mpv instance (no vo — never EGL) created once inside
/// the already-pinned libmpv at engine attach, reading the fork's read-only
/// `dovi-p5-pipeline` property. The snapshot never initializes EGL and never
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
    required this.dataSpaceBridgeLoaded,
    required this.dataSpaceExt,
  });

  static const MethodChannel _channel = MethodChannel(
    'com.alexmercerind/media_kit_video',
  );

  /// Android SDK version.
  final int sdkInt;

  /// HDR types supported by the default display: Dolby Vision (1), HDR10 (2),
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

  /// Whether the native Surface dataspace bridge loaded in this process.
  final bool dataSpaceBridgeLoaded;

  /// The registered dataspace extension, or null when none is registered.
  final HdrDataSpaceExtInfo? dataSpaceExt;

  /// Predicts how [source] would play on this device, before any media is
  /// opened (R1.2): the selected candidate, the full candidate list with
  /// skip reasons, the presentation type, and the confidence.
  ///
  /// This is a thin delegation to `HdrRoutePlanner.plan` with this snapshot
  /// — the exact function the executor uses — so a predicted route and the
  /// applied route cannot drift apart (R1.3). [width], [height] and [fps]
  /// are accepted per R1.2 and reserved for decoder size/frame-rate tier
  /// matching; the Phase 1 planner does not consume them yet.
  HdrRoutePrediction predict(
    HdrSourceDescriptor source, {
    HdrRoutingPolicy policy = HdrRoutingPolicy.defaults,
    HdrOutputPreference preference = HdrOutputPreference.auto,
    int? width,
    int? height,
    double? fps,
  }) {
    return HdrRoutePlanner.plan(
      source: source,
      capabilities: this,
      policy: policy,
      preference: preference,
    );
  }

  /// Queries the Android capability snapshot (R1.1, R1.4).
  ///
  /// The P5 pipeline verdict comes from the snapshot: the native side answers
  /// it once per process through a disposable mpv instance (created with no
  /// vo and no media, so it never touches EGL) that reads the fork's
  /// read-only `dovi-p5-pipeline` property. The probe runs at engine attach
  /// and is cached; every query is therefore authoritative with or without a
  /// [Player].
  ///
  /// [player] is kept only for source compatibility with the Phase 1
  /// signature and is not consulted — no mpv property is read through it.
  static Future<HdrCapabilities> query({Player? player}) {
    return queryWith();
  }

  /// [query] implementation: fetches the snapshot through the plugin channel
  /// and parses it. The P5 verdict is whatever the native probe wrote into
  /// the snapshot (missing key degrades to false, the safe direction).
  @visibleForTesting
  static Future<HdrCapabilities> queryWith() async {
    final Map<Object?, Object?>? snapshot =
        await _channel.invokeMapMethod<String, dynamic>('HdrCapabilities.Get');
    final HdrCapabilities capabilities = parseSnapshot(snapshot);
    // `HDR capability:` layer (R4.3); short-circuits while disabled.
    HdrOutputDiagnostics.capability(capabilities);
    return capabilities;
  }

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
    return HdrCapabilities(
      sdkInt: map['sdkInt'] is int ? map['sdkInt'] as int : 0,
      displayHdrTypes: _parseDisplayHdrTypes(map['displayHdrTypes']),
      hevcDecoders: _parseDecoders(map['hevcDecoders']),
      dolbyVisionDecoders: _parseDecoders(map['dolbyVisionDecoders']),
      p5PipelineAvailable:
          p5Raw is bool ? p5Raw : (p5PipelineAvailable ?? false),
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
      final HdrDecoderInfo? decoder =
          HdrDecoderInfo.fromMap(Map<String, Object?>.from(entry));
      if (decoder != null) decoders.add(decoder);
    }
    return decoders;
  }

  @override
  String toString() => 'HdrCapabilities(sdk: $sdkInt, '
      'displayHdrTypes: $displayHdrTypes, hevc: ${hevcDecoders.length}, '
      'dv: ${dolbyVisionDecoders.length}, p5Pipeline: $p5PipelineAvailable, '
      'bridge: $dataSpaceBridgeLoaded, ext: $dataSpaceExt)';
}
