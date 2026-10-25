import 'dart:async';

/// Reported color fields from one stage of playback. Missing fields remain
/// absent; this type never infers color from a codec, profile, or HDR route.
class PlaybackColorValues {
  const PlaybackColorValues({
    this.primaries,
    this.transfer,
    this.matrix,
    this.range,
  });

  final String? primaries;
  final String? transfer;
  final String? matrix;
  final String? range;

  bool get hasValues =>
      primaries != null || transfer != null || matrix != null || range != null;

  static String? _reported(String? value) {
    final text = value?.trim();
    if (text == null || text.isEmpty) return null;
    if (const {
      '?',
      'auto',
      'unknown',
      'unspecified',
      'reserved',
      'none',
      'null',
      'no',
      '(unavailable)',
    }.contains(text.toLowerCase())) {
      return null;
    }
    // mpv color enumerations are single tokens. Do not expose getter errors,
    // formatted node dumps, or numeric sentinel values as color information.
    if (!RegExp(r'^[a-zA-Z][a-zA-Z0-9._-]*$').hasMatch(text)) return null;
    return text;
  }

  factory PlaybackColorValues.fromProperties(
    Map<String, String?> properties, {
    required String prefix,
    bool source = false,
  }) {
    String? field(String name, Map<String, String> sourceAliases) {
      final value = _reported(properties['$prefix/$name']);
      if (source && value != null) return sourceAliases[value] ?? value;
      return value;
    }

    return PlaybackColorValues(
      primaries: field('primaries', const {'bt2020': 'bt.2020'}),
      // These are exact naming aliases only. In particular, a source bt709
      // OETF is not replaced with a bt1886 display EOTF.
      transfer: field(source ? 'transfer' : 'gamma', const {
        'smpte2084': 'pq',
        'arib-std-b67': 'hlg',
      }),
      matrix: field(source ? 'matrix' : 'colormatrix', const {
        'bt2020nc': 'bt.2020-ncl',
        'bt2020c': 'bt.2020-cl',
      }),
      range: field(source ? 'range' : 'colorlevels', const {
        'tv': 'limited',
        'pc': 'full',
      }),
    );
  }
}

/// Independent source metadata and output-stage observations. [outputTarget]
/// describes a GPU render target, not measured panel color. A native decoder
/// surface can be identified as [decoderPassthrough] without inventing its
/// final display primaries, transfer, or range.
class PlaybackColorSnapshot {
  const PlaybackColorSnapshot({
    this.source = const PlaybackColorValues(),
    this.outputTarget = const PlaybackColorValues(),
    this.decoderPassthrough = false,
  });

  final PlaybackColorValues source;
  final PlaybackColorValues outputTarget;
  final bool decoderPassthrough;

  bool get hasValues =>
      source.hasValues || outputTarget.hasValues || decoderPassthrough;
}

/// Serial read-only diagnostic sampling. The caller starts/stops sampling with
/// diagnostic visibility and supplies a source identity containing its player
/// file-loaded epoch (including reloads of the same URI).
///
/// Source fields use mpv's demux metadata, never decoder-frame `video-params`.
/// GPU output comes only from `video-target-params`. Native decoder passthrough
/// requires an observed `mediacodec_embed` VO, `mediacodec` hwdec and hardware
/// frame format. Planning decisions and display capabilities are not inputs.
class PlaybackColorSampler {
  PlaybackColorSampler({
    required this.readProperty,
    required this.sourceIdentity,
    required this.onSample,
    this.interval = const Duration(seconds: 1),
    this.propertyTimeout = const Duration(seconds: 1),
  });

  final Future<String> Function(String property) readProperty;
  final Object? Function() sourceIdentity;
  final void Function(PlaybackColorSnapshot sample) onSample;
  final Duration interval;
  final Duration propertyTimeout;

  Timer? _timer;
  bool _inFlight = false;
  bool _disposed = false;
  int _generation = 0;

  bool get isRunning => _timer != null;

  void start() {
    if (_disposed || _timer != null) return;
    final generation = ++_generation;
    _timer = Timer.periodic(interval, (_) => unawaited(_sample(generation)));
    unawaited(_sample(generation));
  }

  Future<void> _sample(int generation) async {
    if (!_current(generation) || _inFlight) return;
    _inFlight = true;
    final identity = sourceIdentity();
    bool valid() => _current(generation) && sourceIdentity() == identity;
    try {
      Future<String?> read(String property) async {
        if (!valid()) throw const _ColorSampleCancelled();
        final pending = Future<String>.sync(() => readProperty(property));
        try {
          final value = await pending.timeout(propertyTimeout);
          if (!valid()) throw const _ColorSampleCancelled();
          return value;
        } on TimeoutException {
          if (valid()) onSample(const PlaybackColorSnapshot());
          // Do not free the serial guard while the actual property call is
          // unresolved: repeated timeouts must not accumulate native reads.
          await pending.then<void>((_) {}, onError: (Object _) {});
          throw const _ColorSampleCancelled();
        } on _ColorSampleCancelled {
          rethrow;
        } catch (_) {
          if (!valid()) throw const _ColorSampleCancelled();
          return null;
        }
      }

      const identityProperties = [
        'path',
        'current-tracks/video/id',
        'current-vo',
        'hwdec-current',
        'video-params/pixelformat',
      ];
      final before = <String, String?>{};
      for (final property in identityProperties) {
        before[property] = await read(property);
      }
      // No selected loaded video means no current source to attach a result
      // to. Clear the last sample instead of retaining a previous file's data.
      if ((before['path']?.isEmpty ?? true) ||
          (before['current-tracks/video/id']?.isEmpty ?? true)) {
        if (valid()) onSample(const PlaybackColorSnapshot());
        return;
      }

      const sourcePrefix = 'current-tracks/video/demux-color';
      final sourceProperties = <String, String?>{};
      for (final name in ['primaries', 'transfer', 'matrix', 'range']) {
        // Public mpv property keys use demux-color-<field>; the normalized
        // map keeps parsing independent of that transport spelling.
        sourceProperties['$sourcePrefix/$name'] =
            await read('$sourcePrefix-$name');
      }
      final source = PlaybackColorValues.fromProperties(
        sourceProperties,
        prefix: sourcePrefix,
        source: true,
      );

      final vo = before['current-vo'];
      final passthrough = vo == 'mediacodec_embed' &&
          before['hwdec-current'] == 'mediacodec' &&
          before['video-params/pixelformat'] == 'mediacodec';
      var target = const PlaybackColorValues();
      if (vo == 'gpu' || vo == 'gpu-next') {
        final values = <String, String?>{};
        for (final field in [
          'primaries',
          'gamma',
          'colormatrix',
          'colorlevels'
        ]) {
          final property = 'video-target-params/$field';
          values[property] = await read(property);
        }
        target = PlaybackColorValues.fromProperties(
          values,
          prefix: 'video-target-params',
        );
      }

      // Both source selection and the active presenter can change while
      // individual async getters run. Never publish a mixed-stage snapshot.
      for (final property in identityProperties) {
        if (await read(property) != before[property]) {
          if (valid()) onSample(const PlaybackColorSnapshot());
          return;
        }
      }
      if (valid()) {
        onSample(PlaybackColorSnapshot(
          source: source,
          outputTarget: target,
          decoderPassthrough: passthrough,
        ));
      }
    } on _ColorSampleCancelled {
      // stop/dispose/source replacement invalidates this sample.
    } finally {
      _inFlight = false;
    }
  }

  bool _current(int generation) =>
      !_disposed && _timer != null && generation == _generation;

  void stop() {
    _timer?.cancel();
    _timer = null;
    _generation++;
  }

  void dispose() {
    stop();
    _disposed = true;
  }
}

class _ColorSampleCancelled implements Exception {
  const _ColorSampleCancelled();
}
