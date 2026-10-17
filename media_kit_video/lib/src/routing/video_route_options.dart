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
/// Null fields inherit; explicit auto/allowAlternatives reset lower layers.
class VideoRouteOptions {
  const VideoRouteOptions({
    this.decode,
    this.output,
    this.importPreference,
    this.failurePolicy,
    this.sdrEmbed,
  });

  final VideoRouteSelection<VideoDecodeTarget>? decode;
  final VideoRouteSelection<VideoOutputIntent>? output;
  final VideoImportPreference? importPreference;
  final VideoRouteFailurePolicy? failurePolicy;

  /// SDR session carrier selection on the copy-fallback device group.
  /// Default (unset, null): ENABLED within the capability scope — the
  /// planner generates the `sdrDirect`×`mediacodec_embed` execution
  /// candidate wherever the texture GPU import is unavailable (the
  /// `mediacodec-copy` fallback group). An explicit `false` is the preserved
  /// opt-out that keeps the Texture carrier; an explicit `true` is identical
  /// to the default. Product decision 2026-10-17: LG-class (SDK 16–25)
  /// devices play the SDR session on the embed candidate by default and
  /// accept that super-resolution — an mpv-side GL feature — does not run on
  /// that path; no user-visible switch is added. Contract rules:
  ///
  /// 1. The default embed path is the SDR session on SDK 16–25 devices
  ///    (`_requiresMediacodecCopy`): the embed VO renders through the
  ///    platform Surface WITHOUT the `gpu-next` GL pipeline. mpv-side GL
  ///    features — upscaling shaders, video filters, subtitles, OSD/OSC —
  ///    do not execute on that path, whether declared or not; this is an
  ///    accepted product trade-off, never an auto-detected decision. The
  ///    library does not inspect GL/shader/filter usage.
  /// 2. Flutter-layer features (danmaku, Flutter-rendered subtitles)
  ///    composite above the platform view and are a separate evaluation,
  ///    not covered by this option.
  /// 3. Mid-playback new requirements: keep every other effective option,
  ///    set `sdrEmbed: false`, reopen through the controlled `setOptions`
  ///    path (HdrVideoSession.setOptions — stop, replan, rebuild the output),
  ///    confirm the reopen succeeded, and only then enable the feature.
  ///    Callers that cannot drive that controlled reopen flow must explicitly
  ///    refuse the new feature request.
  /// 4. Writing filters/shaders directly to the Player is NOT an automatic
  ///    switch-back mechanism: the embed VO does not run them, and only the
  ///    controlled `sdrEmbed: false` reopen returns to the Texture carrier.
  /// 5. `screenshot-raw` compatibility on the embed carrier is unmeasured and
  ///    is not part of the verified promise.
  ///
  /// Admission stays capability-scoped — the SDK < 26 texture-GPU-import
  /// rule plus a precise source hardware-decode check: generation is
  /// suppressed only when the census declares the source's hardware decode
  /// `unsupported`; `unknown` rows or an absent census suppress nothing
  /// (the runtime review stays the decision point) — never a device-name
  /// judgment. An explicit `preferCopy` import preference suppresses
  /// generation entirely: the explicit copy intent wins over this option.
  ///
  /// Scope and evidence boundaries (registered 2026-10-17): the default
  /// applies to the whole SDK 16–25 population, not one device. Only LG
  /// H870DS/API24 is end-to-end verified, and only in the controlled
  /// explicit opt-in form — the default build resolves into the same embed
  /// execution path but has not been device-tested as such, and other
  /// devices are unverified. A failing embed observation is terminated by
  /// the unchanged review gate; a fallback to copy is never guaranteed
  /// (gate rejections stop the session). The mpv-side GL tradeoff above is
  /// an accepted product decision for this default path.
  final bool? sdrEmbed;

  VideoRouteOptions merge(VideoRouteOptions overrides) => VideoRouteOptions(
        decode: overrides.decode ?? decode,
        output: overrides.output ?? output,
        importPreference: overrides.importPreference ?? importPreference,
        failurePolicy: overrides.failurePolicy ?? failurePolicy,
        sdrEmbed: overrides.sdrEmbed ?? sdrEmbed,
      );

  /// Canonical field order and deeply immutable values, suitable for reports.
  /// The removed legacy `experimental` key is intentionally not emitted;
  /// persisted configurations carrying it migrate once through [fromMap].
  Map<String, Object?> toMap() => Map<String, Object?>.unmodifiable({
        'decode': decode?.toMap(),
        'output': output?.toMap(),
        'importPreference': importPreference?.name,
        'failurePolicy': failurePolicy?.name,
        'sdrEmbed': sdrEmbed,
      });

  String get key => jsonEncode(toMap());

  factory VideoRouteOptions.fromMap(Map<String, Object?> map) {
    // One-time persistence migration: a legacy `experimental` key is accepted
    // and silently dropped; it has no field to populate anymore.
    _checkKeys(map, const {
      'decode',
      'output',
      'importPreference',
      'failurePolicy',
      'sdrEmbed',
      'experimental'
    });
    return VideoRouteOptions(
      decode: _selection(map['decode'], VideoDecodeTarget.values),
      output: _selection(map['output'], VideoOutputIntent.values),
      importPreference:
          _enumValue(map['importPreference'], VideoImportPreference.values),
      failurePolicy:
          _enumValue(map['failurePolicy'], VideoRouteFailurePolicy.values),
      sdrEmbed: _flag(map['sdrEmbed']),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is VideoRouteOptions &&
      decode == other.decode &&
      output == other.output &&
      importPreference == other.importPreference &&
      failurePolicy == other.failurePolicy &&
      sdrEmbed == other.sdrEmbed;

  @override
  int get hashCode =>
      Object.hash(decode, output, importPreference, failurePolicy, sdrEmbed);
}

/// One effective configuration for selection, planning, execution and reporting.
/// Resolution applies library defaults, then application, then per-open values.
/// It never changes require or the SDR fallback.
class EffectiveVideoRouteOptions {
  EffectiveVideoRouteOptions._({
    required this.decode,
    required this.output,
    required this.importPreference,
    required this.failurePolicy,
    required this.sdrEmbed,
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
      // Unset (null at every layer) resolves to the default-enabled product
      // decision (see [VideoRouteOptions.sdrEmbed]); an explicit `false` is
      // the preserved opt-out and an explicit `true` is idempotent with the
      // default.
      sdrEmbed: result.sdrEmbed != false,
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

  /// Resolved SDR embed admission (see [VideoRouteOptions.sdrEmbed]): true
  /// unless a layer explicitly opted out with `false`.
  final bool sdrEmbed;
  final VideoRouteOptions libraryDefaults;
  final VideoRouteOptions application;
  final VideoRouteOptions openOverride;
  final Map<String, VideoRouteOptionOrigin> origins;

  Map<String, Object?> toMap() => Map<String, Object?>.unmodifiable({
        'decode': decode.toMap(),
        'output': output.toMap(),
        'importPreference': importPreference.name,
        'failurePolicy': failurePolicy.name,
        'sdrEmbed': sdrEmbed,
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

/// Absent stays undeclared (null); a stored flag must be a real boolean.
bool? _flag(Object? value) {
  if (value == null) return null;
  if (value is bool) return value;
  throw const FormatException('Route option flag must be a boolean');
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
