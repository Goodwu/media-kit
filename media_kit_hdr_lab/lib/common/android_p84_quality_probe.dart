import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'android_p84_lifecycle_probe.dart' show P84LifecycleOwner;

/// A paused-position observation aid. Position/route evidence is not proof of
/// displayed pixels, panel luminance, or exact decoded-frame identity.
class AndroidP84QualityProbe {
  AndroidP84QualityProbe({
    required this.owner,
    required this.currentOwner,
    required this.readProperty,
    required this.readFusionMode,
    required this.readFaultModes,
    required this.expectedFusionMode,
    required this.readReport,
    required this.setPaused,
    required this.seek,
    required this.record,
    required this.changed,
    this.delay = Future<void>.delayed,
    this.maxPolls = 40,
    this.heartbeatDelay = Future<void>.delayed,
  });
  final P84LifecycleOwner owner;
  final P84LifecycleOwner? Function() currentOwner;
  final Future<String> Function(String) readProperty;
  final Future<String> Function() readFusionMode;
  final Future<Map<String, String>> Function() readFaultModes;
  final String expectedFusionMode;
  final Map<String, Object?> Function() readReport;
  final Future<void> Function(bool) setPaused;
  final Future<void> Function(Duration) seek;
  final Future<void> Function(Map<String, Object?>) record;
  final void Function() changed;
  final Future<void> Function(Duration) delay;
  final int maxPolls;
  final Future<void> Function(Duration) heartbeatDelay;
  Future<void>? _monitor;
  Completer<void>? _monitorStop;
  final runId = '$pid:${DateTime.now().microsecondsSinceEpoch}';
  static const points = [35.035, 600.032766667, 720.052666667];
  static const properties = [
    'time-pos',
    'pause',
    'seeking',
    'path',
    'duration',
    'hwdec-current',
    'vo',
    'target-trc',
    'target-prim',
    'target-peak',
    'gamma',
    'video-sync',
    'video-params/w',
    'video-params/h',
    'video-params/gamma',
    'video-params/primaries',
    'container-fps',
    'current-tracks/video/dolby-vision-profile',
    'current-tracks/video/dolby-vision-compatibility-id',
  ];
  Future<void>? _pending;
  bool _closed = false;
  int _ordinal = 0;
  String status = 'Choose a frame';
  bool get busy => _pending != null;
  bool get closed => _closed;

  void _check() {
    if (_closed || currentOwner() != owner) {
      throw StateError('P84 quality observation cancelled or owner changed');
    }
  }

  Future<T> _op<T>(Future<T> Function() action) async {
    _check();
    final result = await action();
    _check();
    return result;
  }

  static double? finite(Object? value) {
    final n = double.tryParse('$value');
    return n != null && n.isFinite ? n : null;
  }

  /// media-kit Player.seek currently truncates Duration to milliseconds.
  /// mpv may first report that pending seek target, then the decoded frame PTS.
  /// Accept only this representation difference, never a neighbouring frame.
  static double positionTolerance(double fps) =>
      (0.001002 < 0.25 / fps) ? 0.001002 : 0.25 / fps;

  static void validate(Map<String, String> values, Map<String, Object?> report,
      P84LifecycleOwner owner) {
    for (final e in {
      'path': owner.sourcePath,
      'pause': 'yes',
      'seeking': 'no',
      'hwdec-current': 'surfacetexture',
      'vo': 'gpu-next',
      'target-trc': 'pq',
      'target-prim': 'bt.2020',
      'current-tracks/video/dolby-vision-profile': '8',
      'current-tracks/video/dolby-vision-compatibility-id': '4',
      'video-params/gamma': 'hlg',
      'video-params/primaries': 'bt.2020',
    }.entries) {
      if (values[e.key] != e.value) {
        throw StateError('Invalid ${e.key}: ${values[e.key]}');
      }
    }
    if (finite(values['target-peak']) != 1000 || finite(values['gamma']) != 0) {
      throw StateError('PQ mapping changed');
    }
    final width = int.tryParse(values['video-params/w'] ?? '');
    final height = int.tryParse(values['video-params/h'] ?? '');
    if (width == null || width <= 0 || height == null || height <= 0) {
      throw StateError('Missing or invalid current video dimensions');
    }
    final source = report['source'];
    final actual = report['actual'];
    if (report['verified'] != true ||
        report['generation'] != owner.generation ||
        report['error'] != null ||
        source is! Map ||
        actual is! Map ||
        source['kind'] != 'dolbyVisionP84' ||
        source['dvProfile'] != 8 ||
        source['dvCompatibilityId'] != 4 ||
        actual['strategy'] != 'baseLayerConvert' ||
        actual['hwdec'] != 'surfacetexture') {
      throw StateError('Quality observation requires verified P8.4 convert');
    }
  }

  static const faultProperties = [
    'debug.mks.yuv_fail_commit',
    'debug.mks.yuv_fail_gl'
  ];

  static void validateFaultModes(String fusion, Map<String, String> faults) {
    if (fusion != '1') return;
    for (final key in faultProperties) {
      if (!faults.containsKey(key) ||
          (faults[key] != '' && faults[key] != '0')) {
        throw StateError(
            'Fusion quality observation rejects fault injection: $key');
      }
    }
  }

  Future<void> observe(double target) {
    if (_closed || busy) {
      return Future<void>.error(StateError('Quality probe unavailable'));
    }
    final future = _observe(target);
    _pending = future;
    changed();
    return future.whenComplete(() {
      _pending = null;
      changed();
    });
  }

  Future<void> _observe(double target) async {
    final ordinal = ++_ordinal;
    try {
      if (!target.isFinite || target < 0) {
        throw StateError('Invalid observation target');
      }
      await _stopMonitor();
      final fusion = (await _op(readFusionMode)).trim();
      if ((fusion != '0' && fusion != '1') || fusion != expectedFusionMode) {
        throw StateError('Explicit unchanged startup fusion mode 0/1 required');
      }
      final faults = await _op(readFaultModes);
      validateFaultModes(fusion, faults);
      await _op(() => setPaused(true));
      await _op(() => record({
            'runId': runId,
            'pid': pid,
            'ordinal': ordinal,
            'owner': owner.toJson(),
            'status': 'seek-started',
            'requestedPTS': target,
            'requestedFusionMode': fusion
          }));
      await _op(() => seek(Duration(microseconds: (target * 1000000).round())));
      double? previous;
      var stable = 0;
      Map<String, String>? accepted;
      for (var i = 0; i < maxPolls; i++) {
        await _op(() => delay(const Duration(milliseconds: 150)));
        final values = <String, String>{};
        for (final key in properties) {
          values[key] = await _op(() => readProperty(key));
        }
        if (values['seeking'] == 'yes') {
          stable = 0;
          previous = null;
          continue;
        }
        validate(values, readReport(), owner);
        final fps = finite(values['container-fps']);
        final pos = finite(values['time-pos']);
        final duration = finite(values['duration']);
        if (fps == null ||
            fps <= 0 ||
            duration == null ||
            duration <= target ||
            pos == null) {
          throw StateError('Missing position, duration, or frame rate');
        }
        // Pending seek time and decoded PTS can differ by <=1 millisecond.
        // Host still requires native source/current PTS at target +/-2 us.
        final tolerance = positionTolerance(fps);
        if ((pos - target).abs() <= tolerance &&
            previous != null &&
            (pos - previous).abs() <= 0.000001) {
          stable++;
        } else {
          stable = 0;
        }
        previous = pos;
        if (stable >= 3) {
          accepted = values;
          break;
        }
      }
      if (accepted == null) {
        throw StateError(
            'Paused position did not settle: target=$target lastPosition=$previous');
      }
      final modeAfter = (await _op(readFusionMode)).trim();
      if (modeAfter != fusion) {
        throw StateError('Fusion property changed: restart required');
      }
      final faultsAfter = await _op(readFaultModes);
      validateFaultModes(fusion, faultsAfter);
      final report = readReport();
      validate(accepted, report, owner);
      await _op(() => record({
            'runId': runId,
            'pid': pid,
            'ordinal': ordinal,
            'owner': owner.toJson(),
            'status': 'ready-for-observation',
            'requestedPTS': target,
            'actualPosition': finite(accepted!['time-pos']),
            'acceptedPosition': finite(accepted['time-pos']),
            'positionToleranceSeconds':
                positionTolerance(finite(accepted['container-fps'])!),
            'requestedFusionMode': fusion,
            'faultPropertiesBefore': faults,
            'faultPropertiesAfter': faultsAfter,
            'properties': accepted,
            'report': report,
            'evidenceScope': 'paused-property-position-and-route-only',
            'limits': [
              'Native committed counters must be checked independently.',
              'time-pos does not prove displayed-frame identity.',
              'Screenshots do not prove panel colour, brightness, or smoothness.'
            ],
          }));
      status =
          '${fusion == '1' ? 'Candidate' : 'Baseline'}: ${accepted['time-pos']} s — ready';
      final stop = Completer<void>();
      _monitorStop = stop;
      _monitor = _monitorObservation(
          ordinal, target, fusion, finite(accepted['time-pos'])!, stop);
    } catch (error) {
      status = 'Observation failed: $error';
      // Persist only while ownership still belongs to this run. Never report a
      // stale run as ready after exit or source replacement.
      if (_closed || currentOwner() != owner) {
        await record({
          'runId': runId,
          'pid': pid,
          'ordinal': ordinal,
          'owner': owner.toJson(),
          'status': 'cancelled',
          'error': '$error'
        });
      } else {
        await record({
          'runId': runId,
          'pid': pid,
          'ordinal': ordinal,
          'owner': owner.toJson(),
          'status': 'failed',
          'error': '$error'
        });
      }
      rethrow;
    }
  }

  Future<void> _stopMonitor() async {
    final stop = _monitorStop;
    if (stop != null && !stop.isCompleted) stop.complete();
    final monitor = _monitor;
    if (monitor != null) await monitor;
    _monitor = null;
    _monitorStop = null;
  }

  Future<void> _monitorObservation(int ordinal, double target, String fusion,
      double acceptedPosition, Completer<void> stop) async {
    var heartbeat = 0;
    try {
      while (!stop.isCompleted) {
        await Future.any(
            [heartbeatDelay(const Duration(milliseconds: 250)), stop.future]);
        if (stop.isCompleted) return;
        _check();
        final values = <String, String>{};
        for (final key in properties) {
          values[key] = await _op(() => readProperty(key));
        }
        if (stop.isCompleted) return;
        final report = readReport();
        validate(values, report, owner);
        final position = finite(values['time-pos']);
        final fps = finite(values['container-fps']);
        if (position == null ||
            fps == null ||
            fps <= 0 ||
            (position - target).abs() > positionTolerance(fps) ||
            (position - acceptedPosition).abs() > positionTolerance(fps)) {
          throw StateError(
              'Observed paused frame position changed: accepted=$acceptedPosition actual=$position target=$target seeking=${values['seeking']} tolerance=${fps == null || fps <= 0 ? 'unknown' : positionTolerance(fps)}');
        }
        if ((await _op(readFusionMode)).trim() != fusion) {
          throw StateError('Fusion mode changed during observation');
        }
        final faults = await _op(readFaultModes);
        validateFaultModes(fusion, faults);
        if (stop.isCompleted) return;
        await _op(() => record({
              'runId': runId,
              'pid': pid,
              'ordinal': ordinal,
              'owner': owner.toJson(),
              'status': 'observation-heartbeat',
              'heartbeat': ++heartbeat,
              'requestedPTS': target,
              'actualPosition': position,
              'acceptedPosition': acceptedPosition,
              'positionToleranceSeconds': positionTolerance(fps),
              'requestedFusionMode': fusion,
              'properties': values,
              'report': report,
              'faultPropertiesBefore': faults,
              'faultPropertiesAfter': faults,
              'evidenceScope': 'fresh-paused-property-position-and-route-only',
            }));
      }
    } catch (error) {
      await record({
        'runId': runId,
        'pid': pid,
        'ordinal': ordinal,
        'owner': owner.toJson(),
        'status': _closed ? 'cancelled' : 'invalidated',
        'error': '$error'
      });
      status = 'Observation invalidated: $error';
      changed();
    }
  }

  Future<void> cancelAndDrain() async {
    _closed = true;
    await _stopMonitor();
    final pending = _pending;
    if (pending != null) {
      try {
        await pending;
      } catch (_) {}
    }
  }
}

class AndroidP84QualityControls extends StatelessWidget {
  const AndroidP84QualityControls(
      {super.key, required this.probe, required this.run});
  final AndroidP84QualityProbe? probe;
  final void Function(double) run;
  @override
  Widget build(BuildContext context) => Material(
        color: Colors.black87,
        child: SafeArea(
            top: false,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(probe?.status ?? 'Waiting for verified video',
                  style: const TextStyle(color: Colors.white)),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                for (final t in AndroidP84QualityProbe.points)
                  TextButton(
                      onPressed: probe != null && !probe!.busy && !probe!.closed
                          ? () => run(t)
                          : null,
                      child: Text('${t.toStringAsFixed(3)} s')),
              ]),
            ])),
      );
}
