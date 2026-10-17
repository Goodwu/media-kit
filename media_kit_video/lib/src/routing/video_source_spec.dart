import 'dart:convert';

/// Encoded source constraints, independent of a Player, viewport or display.
///
/// [codec] accepts an RFC 6381 codec string (for example hvc1.2.4.L153.B0)
/// or a codec family (h264, hevc, av1, vp9). A family without enough profile
/// information can produce an unknown result, not an assumed Main/8-bit one.
/// [profile] and [level] are bitstream values, NOT Android constant values:
/// AVC profile_idc/level_idc, HEVC general_profile_idc/general_level_idc,
/// AV1 seq_profile/seq_level_idx, VP9 profile/decimal level. DV codec strings
/// carry their own DV profile and level; do not put HEVC values in them.
class VideoSourceSpec {
  VideoSourceSpec({
    required String codec,
    this.width,
    this.height,
    this.frameRate,
    this.bitDepth,
    this.profile,
    this.level,
    this.highTier,
    this.bitrate,
  }) : codec = codec.trim().toLowerCase() {
    if (this.codec.isEmpty ||
        this.codec.length > 128 ||
        !RegExp(r'^[a-z0-9._-]+$').hasMatch(this.codec)) {
      throw ArgumentError.value(codec, 'codec', 'Expected a codec, not a URI');
    }
    for (final entry in <String, int?>{
      'width': width,
      'height': height,
      'bitDepth': bitDepth,
      'bitrate': bitrate,
    }.entries) {
      if (entry.value != null &&
          (entry.value! <= 0 || entry.value! > 0x7fffffff)) {
        throw ArgumentError.value(
            entry.value, entry.key, 'Must be a positive int32');
      }
    }
    if (bitDepth != null && bitDepth! > 32) {
      throw ArgumentError.value(bitDepth, 'bitDepth', 'Must not exceed 32');
    }
    for (final value in <int?>[profile, level]) {
      if (value != null && (value < 0 || value > 0x7fffffff)) {
        throw ArgumentError.value(
            value, 'profile/level', 'Must be a nonnegative int32');
      }
    }
    if (frameRate != null && (!frameRate!.isFinite || frameRate! <= 0)) {
      throw ArgumentError.value(
          frameRate, 'frameRate', 'Must be positive and finite');
    }
  }

  final String codec;

  /// Encoded dimensions. Never pass the widget's layout size here.
  final int? width;
  final int? height;
  final double? frameRate;
  final int? bitDepth;
  final int? profile;
  final int? level;
  final bool? highTier;

  /// Declared encoded bitrate in bits/second, when known.
  final int? bitrate;

  /// Parses DASH integer, decimal or rational rates. Invalid/missing rates
  /// stay unknown. They must not silently become 30 or 60 fps.
  static double? parseFrameRate(String? value) {
    if (value == null) return null;
    final parts = value.trim().split('/');
    if (parts.length > 2) return null;
    final numerator = double.tryParse(parts.first);
    final denominator = parts.length == 2 ? double.tryParse(parts.last) : 1.0;
    if (numerator == null ||
        denominator == null ||
        !numerator.isFinite ||
        !denominator.isFinite ||
        numerator <= 0 ||
        denominator <= 0) {
      return null;
    }
    final result = numerator / denominator;
    return result.isFinite && result > 0 ? result : null;
  }

  /// Stable identity includes every constraint; matching one resolution/rate
  /// can never authorize another source. It is not a media URL or cache token.
  String get key => jsonEncode(<Object?>[
        codec,
        width,
        height,
        frameRate,
        bitDepth,
        profile,
        level,
        highTier,
        bitrate,
      ]);

  Map<String, Object?> toMap() => <String, Object?>{
        'key': key,
        'codec': codec,
        'width': width,
        'height': height,
        'frameRate': frameRate,
        'bitDepth': bitDepth,
        'profile': profile,
        'level': level,
        'highTier': highTier,
        'bitrate': bitrate,
      };

  @override
  bool operator ==(Object other) =>
      other is VideoSourceSpec && key == other.key;
  @override
  int get hashCode => key.hashCode;
  @override
  String toString() => 'VideoSourceSpec($key)';
}
