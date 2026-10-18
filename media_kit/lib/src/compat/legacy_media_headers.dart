/// Application-level header defaults used by the old native player API.
/// No libmpv access occurs here: an unawaited setter is visible synchronously.
class LegacyMediaHeaders {
  Map<String, String> _named = {};
  Map<String, String> _custom = {};

  /// A provided [headers] map REPLACES the previous custom map. In particular,
  /// headers: {} clears a previous custom Referer (PiliPlus audio contract).
  /// Omitted named userAgent/referer keep their previous defaults. Custom
  /// fields override named defaults; per-media fields override both.
  void update({String? userAgent, String? referer,
      Map<String, String>? headers}) {
    final named = Map<String, String>.of(_named);
    for (final entry in {'user-agent': userAgent, 'referer': referer}.entries) {
      if (entry.value != null) named[entry.key] = entry.value!;
    }
    final nextNamed = _normalize(named);
    final nextCustom = headers == null ? _custom : _normalize(headers);
    // Validate the entire update before changing either map.
    _named = nextNamed;
    _custom = nextCustom;
  }

  Map<String, String> resolve([Map<String, String>? media]) =>
      Map<String, String>.unmodifiable({
        ..._named, ..._custom, ..._normalize(media ?? const {}),
      });

  static Map<String, String> _normalize(Map<String, String> values) {
    final result = <String, String>{};
    final namePattern = RegExp(r"^[!#$%&'*+.^_`|~0-9A-Za-z-]+$");
    for (final entry in values.entries) {
      if (!namePattern.hasMatch(entry.key) ||
          entry.value.contains(RegExp(r'[\r\n\x00]'))) {
        throw ArgumentError('Invalid HTTP header');
      }
      result[entry.key.toLowerCase()] = entry.value;
    }
    return result;
  }
}
