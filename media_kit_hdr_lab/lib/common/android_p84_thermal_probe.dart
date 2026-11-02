import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Lab-only scheduling A/B probe. It never changes the pixel processing chain.
/// The page creates this only behind MEDIA_KIT_ANDROID_P84_THERMAL_PROBE.
class AndroidP84ThermalProbe {
  AndroidP84ThermalProbe({
    required this.serial,
    required this.isCurrent,
    required this.readProperty,
    required this.writeProperty,
    required this.readReport,
    required this.emit,
    this.readMode = readAndroidMode,
    this.interval = const Duration(seconds: 10),
  });

  final int serial;
  final bool Function() isCurrent;
  final Future<String> Function(String) readProperty;
  final Future<void> Function(String, String) writeProperty;
  final Map<String, Object?> Function() readReport;
  final void Function(String) emit;
  final Future<String> Function() readMode;
  final Duration interval;

  static Future<String> readAndroidMode() async {
    final result = await Process.run(
      '/system/bin/getprop',
      const ['debug.mks.thermal_sync'],
    );
    if (result.exitCode != 0) {
      throw StateError('Thermal mode read failed: ${result.exitCode}');
    }
    return '${result.stdout}'.trim();
  }

  static const properties = <String>[
    'time-pos',
    'path',
    'pause',
    'hwdec-current',
    'hwdec-software-fallback',
    'video-codec',
    'current-tracks/video/dolby-vision-profile',
    'current-tracks/video/dolby-vision-compatibility-id',
    'video-sync',
    'display-sync-active',
    'vsync-ratio',
    'audio-speed-correction',
    'video-speed-correction',
    'avsync',
    'decoder-frame-drop-count',
    'frame-drop-count',
    'vo-delayed-frame-count',
    'mistimed-frame-count',
    'estimated-vf-fps',
    'estimated-display-fps',
    'container-fps',
    'video-params/w',
    'video-params/h',
    'video-params/gamma',
    'video-params/primaries',
    'video-params/pixelformat',
    'video-params/hw-pixelformat',
    'video-out-params/w',
    'video-out-params/h',
    'video-out-params/gamma',
    'video-out-params/primaries',
    'target-peak',
    'target-trc',
    'target-prim',
    'android-surface-size',
    'gamma',
    'interpolation',
    'vo',
  ];

  final _clock = Stopwatch();
  final String runId = '$pid:${DateTime.now().microsecondsSinceEpoch}';
  Timer? _timer;
  Future<void>? _inFlight;
  Future<void>? _stopFuture;
  String? _mode;
  bool _stopped = false;
  bool _generationCaptured = false;
  Object? _generation;
  int _sampleOrdinal = 0;

  bool get _ownsCurrent =>
      !_stopped &&
      isCurrent() &&
      (!_generationCaptured || readReport()['generation'] == _generation);

  void _checkCurrent() {
    if (!_ownsCurrent) {
      throw StateError('Thermal probe open was superseded');
    }
  }

  /// Sequential strict write/readback before this generation's session.open.
  Future<void> prepare() async {
    _checkCurrent();
    final mode = await readMode();
    _checkCurrent();
    if (mode != 'display-resample' && mode != 'audio') {
      throw StateError('Invalid thermal sync mode: $mode');
    }
    await writeProperty('video-sync', mode);
    _checkCurrent();
    final accepted = await readProperty('video-sync');
    _checkCurrent();
    if (accepted != mode) {
      throw StateError(
          'Thermal sync rejected: requested=$mode actual=$accepted');
    }
    _mode = mode;
    _emit('prepared', const {}, const {}, 0);
  }

  Future<void> start() async {
    _checkCurrent();
    if (_mode == null) throw StateError('Thermal probe was not prepared');
    _generation = readReport()['generation'];
    _generationCaptured = true;
    _clock.start();
    await sample(phase: 'start');
    _checkCurrent();
    _timer = Timer.periodic(interval, (_) => unawaited(sample()));
  }

  /// One real async native query at a time; a late sample never touches the
  /// next source owner or presents the report's cached hwdec as a live fact.
  Future<void> sample({String phase = 'sample'}) {
    if (!_ownsCurrent) return Future<void>.value();
    final pending = _inFlight;
    if (pending != null) return pending;
    final result = _sample(phase);
    _inFlight = result;
    return result.whenComplete(() {
      if (identical(_inFlight, result)) _inFlight = null;
    });
  }

  Future<void> _sample(String phase) async {
    final started = _clock.elapsedMilliseconds;
    final values = <String, String>{};
    final errors = <String, String>{};
    for (final property in properties) {
      if (!_ownsCurrent) return;
      try {
        final value = await readProperty(property);
        if (!_ownsCurrent) return;
        values[property] = value;
      } catch (error) {
        if (!_ownsCurrent) return;
        final text = '$error';
        errors[property] = text.length > 160 ? text.substring(0, 160) : text;
      }
    }
    _emit(phase, values, errors, _clock.elapsedMilliseconds - started);
  }

  void _emit(String phase, Map<String, String> values,
      Map<String, String> errors, int duration) {
    final row = <String, Object?>{
      'schemaVersion': 1,
      'runId': runId,
      'pid': pid,
      'serial': serial,
      'phase': phase,
      'mode': _mode,
      'elapsedMs': _clock.elapsedMilliseconds,
      'wallTime': DateTime.now().toUtc().toIso8601String(),
      'sampleDurationMs': duration,
      'sampleOrdinal': ++_sampleOrdinal,
      'properties': values,
      'propertyErrors': errors,
      'report': readReport(),
    };
    final encoded = jsonEncode(row);
    // The LG/Flutter logging path truncates near 1KB on this device, below
    // Android's nominal limit. Each emitted ASCII payload stays below 800B.
    if (utf8.encode('THERMAL_JSON $encoded').length <= 750) {
      emit('THERMAL_JSON $encoded');
      return;
    }
    final data = base64Encode(utf8.encode(encoded));
    final count = (data.length + 599) ~/ 600;
    for (var index = 0; index < count; index++) {
      final start = index * 600;
      final end = start + 600 < data.length ? start + 600 : data.length;
      emit('THERMAL_JSON_PART ${jsonEncode({
            'r': runId,
            'n': _sampleOrdinal,
            'i': index,
            'c': count,
            'd': data.substring(start, end),
          })}');
    }
  }

  /// Keep the first failure observable even when open rolls all properties
  /// back before teardown. The host treats this as invalid, never as data.
  void reportError(Object error) {
    final text = '$error';
    final report = readReport();
    emit('THERMAL_ERROR ${jsonEncode({
          'pid': pid,
          'runId': runId,
          'serial': serial,
          'generation': report['generation'],
          'phase': 'open-error',
          'error': text.length > 180 ? text.substring(0, 180) : text,
          'verified': report['verified'],
          'strategy': (report['actual'] as Map?)?['strategy'],
        })}');
  }

  /// Call before native stop/dispose; drains any real in-flight query first.
  Future<void> stop() => _stopFuture ??= _stop();

  Future<void> _stop() async {
    _timer?.cancel();
    _timer = null;
    final pending = _inFlight;
    if (pending != null) await pending;
    if (_ownsCurrent && _mode != null) {
      await sample(phase: 'end');
    }
    _stopped = true;
    _clock.stop();
  }
}
