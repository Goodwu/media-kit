import 'dart:convert';

import 'legacy_media_headers.dart';

/// Frozen per-entry input for ordinary open/add. Unknown extras stay data;
/// decoder/output/script ownership cannot be acquired through an extras map.
/// mpv applies/restores these values with the native playlist entry, not by URI
/// lookup or by a Dart on_unload callback which may belong to an older source.
class LegacyMediaOptions {
  LegacyMediaOptions._(Map<String, String> values, this.httpHeaders)
      : values = Map<String, String>.unmodifiable(values);

  static const _names = <String>{
    'cache',
    'cache-secs',
    'demuxer-hysteresis-secs',
    'demuxer-max-bytes',
    'demuxer-max-back-bytes',
    'lavfi-complex',
  };

  factory LegacyMediaOptions.fromExtras(Map<String, dynamic>? extras, {
    Map<String, String>? httpHeaders,
    Duration? start,
    Duration? end,
  }) {
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
      if (decoded.startsWith('"')) {
        if (decoded.length < 2 || !decoded.endsWith('"') ||
            decoded.substring(1, decoded.length - 1).contains('"')) {
          throw ArgumentError('Ambiguous quoting for legacy media option $name');
        }
        decoded = decoded.substring(1, decoded.length - 1);
      }
      values[name] = decoded;
    }
    // Preserve the existing millisecond precision and negative-time semantics.
    // These named fields are trusted API input, not an expanded extras allowlist.
    if (start != null) values['start'] =
        (start.inMilliseconds / 1000).toStringAsFixed(3);
    if (end != null) values['end'] =
        (end.inMilliseconds / 1000).toStringAsFixed(3);
    final headers = LegacyMediaHeaders().resolve(httpHeaders);
    return LegacyMediaOptions._(values, headers);
  }

  final Map<String, String> values;
  final Map<String, String> httpHeaders;
  bool get isEmpty => values.isEmpty && httpHeaders.isEmpty;

  /// The key/value parser consumes UTF-8 byte lengths. Header list operations
  /// deliberately use clr + repeated append, NOT a comma-joined string list:
  /// append keeps commas and trailing backslashes literally inside ONE field.
  /// The native per-file backup belongs to http-header-fields for every action.
  String get encoded => <String>[
    for (final entry in values.entries) _pair(entry.key, entry.value),
    if (httpHeaders.isNotEmpty) ...[
      _pair('http-header-fields-clr', ''),
      for (final entry in httpHeaders.entries)
        _pair('http-header-fields-append', '${entry.key}: ${entry.value}'),
    ],
  ].join(',');

  static String _pair(String name, String value) =>
      '$name=%${utf8.encode(value).length}%$value';

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
