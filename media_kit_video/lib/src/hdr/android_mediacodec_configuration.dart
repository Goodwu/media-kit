import 'dart:convert';

/// The configured decoder reported by `android-mediacodec-info`.
/// This is not evidence of visible frames or an HDR display mode.
class AndroidMediaCodecConfiguration {
  const AndroidMediaCodecConfiguration._(
      this.mime, this.codec, this.nativeDvActive);

  final String mime;

  /// Empty when the platform cannot report the actual decoder name.
  final String codec;
  final bool nativeDvActive;

  /// Rejects unknown schemas, malformed values and contradictory DV facts.
  /// Callers must additionally bind this sample to their media identity.
  static AndroidMediaCodecConfiguration? parse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    Object? value;
    try {
      value = jsonDecode(raw);
    } on FormatException {
      return null;
    }
    if (value is! Map<String, dynamic>) return null;
    final api = value['api'];
    final mime = value['mime'];
    final codec = value['codec'];
    final active = value['native-dv-active'];
    if (api is! int ||
        api != 1 ||
        mime is! String ||
        !mime.startsWith('video/') ||
        mime.length <= 6 ||
        mime.trim() != mime ||
        codec is! String ||
        codec.trim() != codec ||
        active is! bool) {
      return null;
    }
    if (active && (mime != 'video/dolby-vision' || codec.isEmpty)) {
      return null;
    }
    return AndroidMediaCodecConfiguration._(mime, codec, active);
  }
}
