import 'dart:convert';

/// The finite set of legacy per-media options consumed by original PiliPlus.
/// Other extras stay application data. In particular decoder, output, hooks and
/// scripts cannot acquire routing ownership through an extras map.
///
/// Values are frozen before an open/add is queued. mpv owns their per-file
/// lifetime through loadfile's options argument, not a Dart rollback cache.
class LegacyMediaOptions {
  LegacyMediaOptions._(Map<String, String> values)
      : values = Map<String, String>.unmodifiable(values);

  static const _names = <String>{
    'cache',
    'cache-secs',
    'demuxer-hysteresis-secs',
    'demuxer-max-bytes',
    'demuxer-max-back-bytes',
    'lavfi-complex',
  };

  factory LegacyMediaOptions.fromExtras(Map<String, dynamic>? extras) {
    final values = <String, String>{};
    for (final name in _names) {
      if (extras == null || !extras.containsKey(name)) continue;
      final value = extras[name];
      if (value is! String || value.contains('\u0000')) {
        throw ArgumentError('Legacy media option $name needs a NUL-free string');
      }
      var decoded = value;
      // The old loadfile key/value parser removed this quoting layer. The
      // application wraps its entire lavfi-complex graph in double quotes.
      // Do not treat embedded quotes or comma-separated text as new options.
      if (decoded.startsWith('"')) {
        if (decoded.length < 2 || !decoded.endsWith('"') ||
            decoded.substring(1, decoded.length - 1).contains('"')) {
          throw ArgumentError('Ambiguous quoting for legacy media option $name');
        }
        decoded = decoded.substring(1, decoded.length - 1);
      }
      values[name] = decoded;
    }
    return LegacyMediaOptions._(values);
  }

  final Map<String, String> values;
  bool get isEmpty => values.isEmpty;

  /// mpv's fixed-length suboption escaping uses UTF-8 bytes, not Dart length.
  /// This keeps commas, equals, brackets and percent signs inside one value.
  String get encoded => values.entries.map((entry) =>
      '${entry.key}=%${utf8.encode(entry.value).length}%${entry.value}').join(',');

  List<String> appendArguments(String uri, {required int apiVersion}) {
    if (uri.contains('\u0000')) throw ArgumentError('Media URI contains NUL');
    return List<String>.unmodifiable([
      'loadfile', uri, 'append',
      if (!isEmpty) ...[
        // The insertion-index argument was added with libmpv client API 2.3.
        if (apiVersion >= 0x20003) '-1',
        encoded,
      ],
    ]);
  }
}
