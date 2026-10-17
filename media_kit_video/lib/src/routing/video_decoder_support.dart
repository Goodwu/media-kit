import 'video_source_spec.dart';

/// System declaration for the requested source, not configure, real-time
/// performance, power efficiency, GPU interoperability or HDR presentation.
enum VideoSupport { supported, unsupported, unknown }

enum VideoDecoderKind { hardware, software, unknown }

class VideoDecoderSupport {
  const VideoDecoderSupport({
    required this.name,
    required this.mime,
    required this.kind,
    required this.support,
    required this.reason,
    required this.path,
  });
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
  VideoSourceSupport({
    required this.source,
    required this.censusComplete,
    required Iterable<VideoDecoderSupport> decoders,
    required this.reason,
  }) : decoders = List<VideoDecoderSupport>.unmodifiable(decoders);
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
      if (decoder.support == VideoSupport.supported) {
        return VideoSupport.supported;
      }
      if (decoder.support == VideoSupport.unknown) unknown = true;
    }
    return unknown ? VideoSupport.unknown : VideoSupport.unsupported;
  }
}
