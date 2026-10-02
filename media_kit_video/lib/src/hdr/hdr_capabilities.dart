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
/// extension) and probes the mpv fork for the P5 dovi rescale pipeline. The
/// snapshot never initializes EGL and never probes private ABIs.
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

  /// The mpv fork option whose existence identifies the generation carrying
  /// the P5 dovi rescale pipeline (both introduced in the same fork commit),
  /// so option presence is a conservative availability proxy (R1.4): an older
  /// fork generation may be misjudged as unavailable, but an incapable build
  /// is never misjudged as available.
  static const String p5FastPathOption = 'dovi-p5-fast-path';

  /// Property read to detect [p5FastPathOption]: the option's reported name
  /// is non-empty exactly when the option exists.
  static const String p5ProbeProperty = 'option-info/dovi-p5-fast-path/name';

  /// Injectable property reader used instead of `Player.getProperty` by
  /// [query]. Test seam; null in production.
  @visibleForTesting
  static HdrPropertyReader? propertyReader;

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

  /// Whether mpv carries the fork's P5 dovi rescale pipeline, detected from
  /// the presence of the `dovi-p5-fast-path` option.
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

  /// Queries the Android capability snapshot and probes the mpv fork for the
  /// P5 dovi rescale pipeline (R1.1, R1.4).
  ///
  /// [player] is optional. With a [Player], the P5 pipeline is probed through
  /// its mpv property access as before. Without one (e.g. a route decision
  /// made before the first player is created), no mpv option can be probed,
  /// so `p5PipelineAvailable` is conservatively false: the prediction treats
  /// every P5 source as not playable and falls back to SDR. This is not a
  /// safety gap — it is the "unavailable is never misjudged as available"
  /// direction. Callers must re-query once they hold a Player to get an
  /// authoritative P5 verdict; predictions for non-P5 sources (P8.4, HDR10,
  /// HLG, SDR) are unaffected.
  static Future<HdrCapabilities> query({Player? player}) {
    if (player == null) {
      // No player: no mpv property access, so the P5 probe cannot run and
      // the pipeline is treated as missing. [propertyReader] is deliberately
      // not consulted — the conservative verdict must not depend on a seam.
      return queryWith((property) async => '');
    }
    final HdrPropertyReader reader =
        propertyReader ?? (property) => player.getProperty(property);
    return queryWith(reader);
  }

  /// [query] with an injected libmpv property reader (test seam and for
  /// callers that already hold a property access abstraction).
  @visibleForTesting
  static Future<HdrCapabilities> queryWith(HdrPropertyReader readProperty) async {
    final List<Object?> results = await Future.wait(<Future<Object?>>[
      _channel.invokeMapMethod<String, dynamic>('HdrCapabilities.Get'),
      detectP5Pipeline(readProperty),
    ]);
    final HdrCapabilities capabilities = parseSnapshot(
      results[0] as Map<Object?, Object?>?,
      p5PipelineAvailable: results[1] as bool,
    );
    // `HDR capability:` layer (R4.3); short-circuits while disabled.
    HdrOutputDiagnostics.capability(capabilities);
    return capabilities;
  }

  /// True exactly when mpv reports a non-empty name for the
  /// [p5FastPathOption] option. Read failures and empty results mean the
  /// fork does not carry the P5 pipeline — false, never true by accident.
  @visibleForTesting
  static Future<bool> detectP5Pipeline(HdrPropertyReader readProperty) async {
    try {
      final String name = await readProperty(p5ProbeProperty);
      return name.trim().isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Parses the raw native snapshot. Malformed or missing fields degrade to
  /// the safe defaults: no capability report (null displayHdrTypes), no
  /// decoders, no bridge, no extension. Also used by the session to parse
  /// the `HdrCapabilities.Changed` event payload.
  static HdrCapabilities parseSnapshot(
    Map<Object?, Object?>? snapshot, {
    required bool p5PipelineAvailable,
  }) {
    final Map<String, Object?> map = snapshot == null
        ? const <String, Object?>{}
        : Map<String, Object?>.from(snapshot);
    return HdrCapabilities(
      sdkInt: map['sdkInt'] is int ? map['sdkInt'] as int : 0,
      displayHdrTypes: _parseDisplayHdrTypes(map['displayHdrTypes']),
      hevcDecoders: _parseDecoders(map['hevcDecoders']),
      dolbyVisionDecoders: _parseDecoders(map['dolbyVisionDecoders']),
      p5PipelineAvailable: p5PipelineAvailable,
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
