import 'dart:convert';

/// Preference strength; require is a constraint, not permission to try a route.
enum VideoRoutePreference { auto, prefer, require }

enum VideoDecodeTarget { hardware, software }

enum VideoOutputIntent { hdr, sdr }

enum VideoImportPreference { auto, preferCopy, preferDirect }

enum VideoRouteFailurePolicy { allowAlternatives, stop }

enum VideoRouteOptionOrigin { libraryDefault, application, openOverride }

/// A single target prevents contradictory requirements on the same axis.
/// Explicit auto clears a lower layer's selection; a null override is unset.
class VideoRouteSelection<T extends Enum> {
  const VideoRouteSelection.auto()
      : preference = VideoRoutePreference.auto,
        target = null;

  const VideoRouteSelection.prefer(T value)
      : preference = VideoRoutePreference.prefer,
        target = value;

  const VideoRouteSelection.require(T value)
      : preference = VideoRoutePreference.require,
        target = value;

  final VideoRoutePreference preference;
  final T? target;

  bool get isRequired => preference == VideoRoutePreference.require;

  Map<String, Object?> toMap() => Map<String, Object?>.unmodifiable({
        'preference': preference.name,
        'target': target?.name,
      });

  @override
  bool operator ==(Object other) =>
      other is VideoRouteSelection<T> &&
      preference == other.preference &&
      target == other.target;

  @override
  int get hashCode => Object.hash(preference, target);
}

/// Requested values only. This object does not query or authorize capabilities.
/// Null fields inherit; explicit auto/false/allowAlternatives reset lower layers.
class VideoRouteOptions {
  const VideoRouteOptions({
    this.decode,
    this.output,
    this.importPreference,
    this.failurePolicy,
    this.experimental,
  });

  final VideoRouteSelection<VideoDecodeTarget>? decode;
  final VideoRouteSelection<VideoOutputIntent>? output;
  final VideoImportPreference? importPreference;
  final VideoRouteFailurePolicy? failurePolicy;
  final bool? experimental;

  VideoRouteOptions merge(VideoRouteOptions overrides) => VideoRouteOptions(
        decode: overrides.decode ?? decode,
        output: overrides.output ?? output,
        importPreference: overrides.importPreference ?? importPreference,
        failurePolicy: overrides.failurePolicy ?? failurePolicy,
        experimental: overrides.experimental ?? experimental,
      );

  /// Canonical field order and deeply immutable values, suitable for reports.
  Map<String, Object?> toMap() => Map<String, Object?>.unmodifiable({
        'decode': decode?.toMap(),
        'output': output?.toMap(),
        'importPreference': importPreference?.name,
        'failurePolicy': failurePolicy?.name,
        'experimental': experimental,
      });

  String get key => jsonEncode(toMap());

  factory VideoRouteOptions.fromMap(Map<String, Object?> map) {
    _checkKeys(map, const {
      'decode',
      'output',
      'importPreference',
      'failurePolicy',
      'experimental'
    });
    final experimental = map['experimental'];
    if (experimental != null && experimental is! bool) {
      throw const FormatException('experimental must be a boolean or null');
    }
    return VideoRouteOptions(
      decode: _selection(map['decode'], VideoDecodeTarget.values),
      output: _selection(map['output'], VideoOutputIntent.values),
      importPreference:
          _enumValue(map['importPreference'], VideoImportPreference.values),
      failurePolicy:
          _enumValue(map['failurePolicy'], VideoRouteFailurePolicy.values),
      experimental: experimental as bool?,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is VideoRouteOptions &&
      decode == other.decode &&
      output == other.output &&
      importPreference == other.importPreference &&
      failurePolicy == other.failurePolicy &&
      experimental == other.experimental;

  @override
  int get hashCode => Object.hash(
      decode, output, importPreference, failurePolicy, experimental);
}

/// One effective configuration for selection, planning, execution and reporting.
/// Resolution applies library defaults, then application, then per-open values.
/// It never changes require because experimental is false or fallback is enabled.
class EffectiveVideoRouteOptions {
  EffectiveVideoRouteOptions._({
    required this.decode,
    required this.output,
    required this.importPreference,
    required this.failurePolicy,
    required this.experimental,
    required this.libraryDefaults,
    required this.application,
    required this.openOverride,
    required Map<String, VideoRouteOptionOrigin> origins,
  }) : origins = Map<String, VideoRouteOptionOrigin>.unmodifiable(origins);

  static const defaults = VideoRouteOptions(
    decode: VideoRouteSelection<VideoDecodeTarget>.auto(),
    output: VideoRouteSelection<VideoOutputIntent>.auto(),
    importPreference: VideoImportPreference.auto,
    failurePolicy: VideoRouteFailurePolicy.allowAlternatives,
    experimental: false,
  );

  factory EffectiveVideoRouteOptions.resolve({
    VideoRouteOptions libraryDefaults = defaults,
    VideoRouteOptions application = const VideoRouteOptions(),
    VideoRouteOptions openOverride = const VideoRouteOptions(),
  }) {
    final base = defaults.merge(libraryDefaults);
    final result = base.merge(application).merge(openOverride);
    final origins = <String, VideoRouteOptionOrigin>{};
    for (final field in defaults.toMap().keys) {
      origins[field] = openOverride.toMap()[field] != null
          ? VideoRouteOptionOrigin.openOverride
          : application.toMap()[field] != null
              ? VideoRouteOptionOrigin.application
              : VideoRouteOptionOrigin.libraryDefault;
    }
    return EffectiveVideoRouteOptions._(
      decode: result.decode!,
      output: result.output!,
      importPreference: result.importPreference!,
      failurePolicy: result.failurePolicy!,
      experimental: result.experimental!,
      libraryDefaults: libraryDefaults,
      application: application,
      openOverride: openOverride,
      origins: origins,
    );
  }

  final VideoRouteSelection<VideoDecodeTarget> decode;
  final VideoRouteSelection<VideoOutputIntent> output;
  final VideoImportPreference importPreference;
  final VideoRouteFailurePolicy failurePolicy;
  final bool experimental;
  final VideoRouteOptions libraryDefaults;
  final VideoRouteOptions application;
  final VideoRouteOptions openOverride;
  final Map<String, VideoRouteOptionOrigin> origins;

  Map<String, Object?> toMap() => Map<String, Object?>.unmodifiable({
        'decode': decode.toMap(),
        'output': output.toMap(),
        'importPreference': importPreference.name,
        'failurePolicy': failurePolicy.name,
        'experimental': experimental,
        'origins': Map<String, Object?>.unmodifiable({
          for (final entry in origins.entries) entry.key: entry.value.name,
        }),
        'requested': Map<String, Object?>.unmodifiable({
          'libraryDefaults': libraryDefaults.toMap(),
          'application': application.toMap(),
          'openOverride': openOverride.toMap(),
        }),
      });

  /// Includes request provenance as well as effective values.
  String get key => jsonEncode(toMap());

  @override
  bool operator ==(Object other) =>
      other is EffectiveVideoRouteOptions && key == other.key;

  @override
  int get hashCode => key.hashCode;
}

void _checkKeys(Map<String, Object?> map, Set<String> allowed) {
  if (map.keys.any((key) => !allowed.contains(key))) {
    throw const FormatException('Unknown route option field');
  }
}

T? _enumValue<T extends Enum>(Object? value, List<T> values) {
  if (value == null) return null;
  for (final candidate in values) {
    if (value == candidate.name) return candidate;
  }
  throw FormatException('Unknown route option value: $value');
}

VideoRouteSelection<T>? _selection<T extends Enum>(
    Object? value, List<T> targets) {
  if (value == null) return null;
  if (value is! Map<String, Object?>) {
    throw const FormatException('Selection must be an object or null');
  }
  _checkKeys(value, const {'preference', 'target'});
  final preference =
      _enumValue(value['preference'], VideoRoutePreference.values);
  final target = _enumValue(value['target'], targets);
  switch (preference) {
    case VideoRoutePreference.auto:
      if (target != null) {
        throw const FormatException('auto cannot specify a target');
      }
      return VideoRouteSelection<T>.auto();
    case VideoRoutePreference.prefer:
    case VideoRoutePreference.require:
      if (target == null) {
        throw const FormatException('prefer/require must specify one target');
      }
      return preference == VideoRoutePreference.prefer
          ? VideoRouteSelection<T>.prefer(target)
          : VideoRouteSelection<T>.require(target);
    case null:
      throw const FormatException('Selection preference is required');
  }
}
