import 'package:flutter/services.dart';

import '../hdr/hdr_capabilities.dart';
import 'video_output_target.dart';
import 'video_source_spec.dart';

/// System declaration for the requested source, not configure, real-time
/// performance, power efficiency, GPU interoperability or HDR presentation.
enum VideoSupport { supported, unsupported, unknown }

enum VideoDecoderKind { hardware, software, unknown }

class VideoDecoderSupport {
  const VideoDecoderSupport(
      {required this.name,
      required this.mime,
      required this.kind,
      required this.support,
      required this.reason,
      required this.path});
  final String name;
  final String mime;
  final VideoDecoderKind kind;
  final VideoSupport support;
  final String reason;

  /// codec: ordinary elementary-stream decode; nativeDv: native DV consumer.
  /// A DV HEVC base decode alone makes no claim about correct DV color output.
  final String path;
}

class VideoSourceSupport {
  VideoSourceSupport(
      {required this.source,
      required this.censusComplete,
      required Iterable<VideoDecoderSupport> decoders,
      required this.reason})
      : decoders = List<VideoDecoderSupport>.unmodifiable(decoders);
  final VideoSourceSpec source;
  final bool censusComplete;
  final List<VideoDecoderSupport> decoders;
  final String reason;

  /// Unknown decoder kind cannot prove hardware/software eligibility. A
  /// failed/partial census cannot prove that no other decoder exists.
  VideoSupport support({VideoDecoderKind? kind, String? path}) {
    var unknown = !censusComplete;
    for (final decoder in decoders) {
      if (path != null && decoder.path != path) continue;
      if (kind != null && decoder.kind != kind) {
        if (decoder.kind == VideoDecoderKind.unknown &&
            decoder.support != VideoSupport.unsupported) {
          unknown = true;
        }
        continue;
      }
      if (decoder.support == VideoSupport.supported)
        return VideoSupport.supported;
      if (decoder.support == VideoSupport.unknown) unknown = true;
    }
    return unknown ? VideoSupport.unknown : VideoSupport.unsupported;
  }
}

class VideoDisplayCapabilities {
  VideoDisplayCapabilities(
      {required this.status,
      this.platform,
      this.displayId,
      this.modeId,
      this.revision,
      Iterable<int>? hdrTypes})
      : hdrTypes = hdrTypes == null ? null : Set<int>.unmodifiable(hdrTypes);
  final String status;
  final String? platform;
  final int? displayId;
  final int? modeId;
  final String? revision;

  /// Android HDR type IDs in the Android adapter; null means not reported.
  /// Other adapters must provide normalized color support before exposing it.
  final Set<int>? hdrTypes;
  bool get resolved => status == 'resolved';
}

/// Player-independent, read-only environment and source-spec query.
///
/// target omitted: device/runtime/decoder facts only, display unresolved.
/// sources omitted: no format matching. No media is opened, no playback
/// decoder/Surface/EGL/owner is created. Android is the first adapter; other
/// platforms return explicit unknown source results, not simulated support.
class VideoRouteCapabilities {
  VideoRouteCapabilities._(
      {required this.platform,
      required this.display,
      required this.hdr,
      required Map<String, VideoSourceSupport> sources})
      : _sources = Map<String, VideoSourceSupport>.unmodifiable(sources);

  final String platform;
  final VideoDisplayCapabilities display;

  /// Existing Android HDR planner input. This is not a cross-platform claim
  /// or a proof of the runtime route. Kept as a value, not a second query API.
  final HdrCapabilities hdr;
  final Map<String, VideoSourceSupport> _sources;
  Iterable<VideoSourceSupport> get sources => _sources.values;

  VideoSourceSupport forSource(VideoSourceSpec source) =>
      _sources[source.key] ??
      VideoSourceSupport(
          source: source,
          censusComplete: false,
          decoders: const [],
          reason: 'sourceNotQueried');

  static const _channel = MethodChannel('com.alexmercerind/media_kit_video');

  static Future<VideoRouteCapabilities> query({
    VideoOutputTarget? target,
    Iterable<VideoSourceSpec> sources = const [],
  }) async {
    // Bound before deduplicating: callers cannot pass an unbounded iterable.
    final unique = <String, VideoSourceSpec>{};
    var count = 0;
    for (final source in sources) {
      if (++count > 128)
        throw ArgumentError('At most 128 source specifications per query');
      unique[source.key] = source;
    }
    Map<Object?, Object?>? raw;
    try {
      raw = await _channel.invokeMapMethod<Object?, Object?>(
          'VideoRouteCapabilities.Get', <String, Object?>{
        'schema': 1,
        'target': target?.toMap(),
        'sources': unique.values.map((s) => s.toMap()).toList(growable: false),
      });
    } on MissingPluginException {
      return VideoRouteCapabilities._(
        platform: 'unavailable',
        display: VideoDisplayCapabilities(status: 'adapterUnavailable'),
        hdr: HdrCapabilities.parseSnapshot(null),
        sources: {
          for (final source in unique.values)
            source.key: VideoSourceSupport(
                source: source,
                censusComplete: false,
                decoders: const [],
                reason: 'adapterUnavailable')
        },
      );
    }
    if (raw == null ||
        raw['schema'] != 1 ||
        raw['platform'] is! String ||
        raw['display'] is! Map ||
        raw['sources'] is! List ||
        raw['hdr'] is! Map) {
      throw const FormatException('Invalid VideoRouteCapabilities schema');
    }
    final display = raw['display'] as Map;
    if (display['status'] is! String)
      throw const FormatException('Invalid display status');
    final hdrTypes = display['hdrTypes'];
    if (hdrTypes != null &&
        (hdrTypes is! List || hdrTypes.any((v) => v is! int))) {
      throw const FormatException('Invalid HDR types');
    }
    final results = <String, VideoSourceSupport>{};
    for (final item in raw['sources'] as List) {
      if (item is! Map ||
          item['key'] is! String ||
          item['decoders'] is! List ||
          item['censusComplete'] is! bool ||
          item['reason'] is! String) {
        throw const FormatException('Invalid source support result');
      }
      final key = item['key'] as String;
      final source = unique[key];
      if (source == null || results.containsKey(key)) {
        throw const FormatException('Unexpected or duplicated source result');
      }
      final decoders = <VideoDecoderSupport>[];
      for (final decoder in item['decoders'] as List) {
        if (decoder is! Map ||
            decoder['name'] is! String ||
            decoder['mime'] is! String ||
            decoder['reason'] is! String ||
            !const ['codec', 'nativeDv'].contains(decoder['path'])) {
          throw const FormatException('Invalid decoder result');
        }
        decoders.add(VideoDecoderSupport(
            name: decoder['name'] as String,
            mime: decoder['mime'] as String,
            kind: _enumValue(VideoDecoderKind.values, decoder['kind']),
            support: _enumValue(VideoSupport.values, decoder['support']),
            reason: decoder['reason'] as String,
            path: decoder['path'] as String));
      }
      results[key] = VideoSourceSupport(
          source: source,
          censusComplete: item['censusComplete'] as bool,
          decoders: decoders,
          reason: item['reason'] as String);
    }
    if (results.length != unique.length)
      throw const FormatException('Missing source support result');
    final hdrMap = Map<Object?, Object?>.from(raw['hdr'] as Map);
    // Display truth is owned by the resolved target, never a legacy default.
    hdrMap['displayHdrTypes'] =
        display['status'] == 'resolved' ? hdrTypes : null;
    return VideoRouteCapabilities._(
      platform: raw['platform'] as String,
      display: VideoDisplayCapabilities(
          status: display['status'] as String,
          platform: display['platform'] as String?,
          displayId: display['displayId'] as int?,
          modeId: display['modeId'] as int?,
          revision: display['revision'] as String?,
          hdrTypes: (hdrTypes as List?)?.cast<int>()),
      hdr: HdrCapabilities.parseSnapshot(hdrMap),
      sources: results,
    );
  }

  static T _enumValue<T extends Enum>(List<T> values, Object? raw) {
    for (final value in values) {
      if (value.name == raw) return value;
    }
    throw FormatException('Unknown capability enum: $raw');
  }
}
