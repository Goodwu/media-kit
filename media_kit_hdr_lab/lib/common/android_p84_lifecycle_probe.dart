import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

enum P84LifecycleAction {
  pauseHoldResume,
  seekForwardBack,
  nearEOFReplay,
  stopReopen,
}

extension P84LifecycleActionLabel on P84LifecycleAction {
  String get label => switch (this) {
        P84LifecycleAction.pauseHoldResume => 'PauseHoldResume',
        P84LifecycleAction.seekForwardBack => 'SeekForwardBack',
        P84LifecycleAction.nearEOFReplay => 'NearEOFReplay',
        P84LifecycleAction.stopReopen => 'StopReopen',
      };
}

class P84LifecycleOwner {
  const P84LifecycleOwner(
      this.session, this.player, this.serial, this.generation, this.sourcePath);
  final int session;
  final int player;
  final int serial;
  final int generation;
  final String sourcePath;

  Map<String, Object?> toJson() => {
        'session': session,
        'player': player,
        'serial': serial,
        'generation': generation,
        'sourcePath': sourcePath,
      };

  @override
  bool operator ==(Object other) =>
      other is P84LifecycleOwner &&
      other.session == session &&
      other.player == player &&
      other.serial == serial &&
      other.generation == generation &&
      other.sourcePath == sourcePath;
  @override
  int get hashCode =>
      Object.hash(session, player, serial, generation, sourcePath);
}

class P84CompletionObservation {
  const P84CompletionObservation(
      this.completed, this.epoch, this.lastFalseEpoch, this.lastTrueEpoch);
  final bool completed;
  final int epoch;
  final int lastFalseEpoch;
  final int lastTrueEpoch;
  Map<String, Object?> toJson() => {
        'completed': completed,
        'epoch': epoch,
        'lastFalseEpoch': lastFalseEpoch,
        'lastTrueEpoch': lastTrueEpoch,
      };
}

/// Independent of thermal measurement. Every operation uses the real page
/// Player/Session; injected functions only make ownership/cancellation testable.
class AndroidP84LifecycleProbe {
  AndroidP84LifecycleProbe({
    required this.owner,
    required this.currentOwner,
    required this.readProperty,
    required this.readReport,
    required this.readNativeCounters,
    required this.setPaused,
    required this.seek,
    required this.stopPlayer,
    required this.reopen,
    required this.readCompletion,
    required this.record,
    required this.changed,
    this.videoSync = 'audio',
    this.deferPublishFlush = 1,
    this.settleTimeout = const Duration(seconds: 8),
    this.delay = Future<void>.delayed,
  });

  P84LifecycleOwner owner;
  final P84LifecycleOwner? Function() currentOwner;
  final Future<String> Function(String) readProperty;
  final Map<String, Object?> Function() readReport;
  final List<Map<String, String>> Function() readNativeCounters;
  final Future<void> Function(bool) setPaused;
  final Future<void> Function(Duration) seek;
  final Future<void> Function() stopPlayer;
  final Future<P84LifecycleOwner> Function() reopen;
  final P84CompletionObservation Function() readCompletion;
  final Future<void> Function(Map<String, Object?>) record;
  final void Function() changed;
  final Future<void> Function(Duration) delay;
  final String videoSync;
  final int deferPublishFlush;
  final Duration settleTimeout;
  final String runId = '$pid:${DateTime.now().microsecondsSinceEpoch}';
  final _cancel = Completer<void>();
  Future<void>? _pending;
  bool _closed = false;
  int _actionOrdinal = 0;
  bool get busy => _pending != null;
  bool get closed => _closed;

  static const properties = [
    'time-pos',
    'duration',
    'path',
    'pause',
    'hwdec-current',
    'vo',
    'target-trc',
    'target-prim',
    'target-peak',
    'gamma',
    'video-sync',
    'decoder-frame-drop-count',
    'frame-drop-count',
    'avsync',
    'eof-reached',
    'idle-active',
    'video-params/w',
    'video-params/h',
    'container-fps',
    'current-tracks/video/dolby-vision-profile',
    'current-tracks/video/dolby-vision-compatibility-id',
  ];

  void _check() {
    if (_closed || currentOwner() != owner) {
      throw StateError('P84 lifecycle owner changed or action cancelled');
    }
  }

  Future<T> _operation<T>(Future<T> Function() operation) async {
    _check();
    final value = await operation();
    _check();
    return value;
  }

  Future<void> _wait(Duration duration) async {
    _check();
    // Only a non-native delay is interruptible. Real native operations are
    // always awaited to completion before ExitCancel can dispose the player.
    await Future.any([delay(duration), _cancel.future]);
    _check();
  }

  Future<Map<String, Object?>> _capture(String step,
      {bool? paused, bool running = true}) async {
    final values = <String, String>{};
    for (final property in properties) {
      values[property] = await _operation(() => readProperty(property));
    }
    _check();
    final report = readReport();
    final native = readNativeCounters();
    final failures = <String>[];
    if (running) {
      for (final entry in {
        'path': owner.sourcePath,
        'hwdec-current': 'surfacetexture',
        'vo': 'gpu-next',
        'target-trc': 'pq',
        'target-prim': 'bt.2020',
        'video-sync': videoSync,
      }.entries) {
        if (values[entry.key] != entry.value) {
          failures.add('${entry.key}=${values[entry.key]}');
        }
      }
      if (double.tryParse(values['gamma'] ?? '') != 0) {
        failures.add('gamma=${values['gamma']}');
      }
      if (report['verified'] != true) failures.add('report unverified');
      final peak = double.tryParse(values['target-peak'] ?? '');
      if (peak == null || !peak.isFinite || peak != 1000) {
        failures.add('target-peak=${values['target-peak']}');
      }
      final source = report['source'] as Map?;
      final route = report['actual'] as Map?;
      if (report['error'] != null ||
          source?['kind'] != 'dolbyVisionP84' ||
          source?['dvProfile'] != 8 ||
          source?['dvCompatibilityId'] != 4 ||
          route?['strategy'] != 'baseLayerConvert' ||
          route?['hwdec'] != 'surfacetexture') {
        failures.add('report is not a clean P8.4 convert route');
      }
    }
    if (paused != null && values['pause'] != (paused ? 'yes' : 'no')) {
      failures.add('pause=${values['pause']}');
    }
    for (final counters in native) {
      for (final name in [
        'fence_create_failed',
        'reap_stuck',
        'latch_timeout',
        'stale_drop'
      ]) {
        final count = int.tryParse(counters[name] ?? '');
        if (count != null && count > 0) {
          failures.add('native $name=${counters[name]}');
        }
      }
    }
    final nativeEvidence = _nativeEvidence(native);
    if (nativeEvidence['policyMismatch'] == true) {
      failures.add('native publish policy mismatch');
    }
    final row = <String, Object?>{
      'runId': runId,
      'pid': pid,
      'actionOrdinal': _actionOrdinal,
      'step': step,
      'owner': owner.toJson(),
      'properties': values,
      'report': report,
      'nativeCounters': native,
      'nativeCountersPresent': native.isNotEmpty,
      'nativeEvidence': nativeEvidence,
      'completion': readCompletion().toJson(),
      'expectedRunning': running,
      'failures': failures,
      'wallTime': DateTime.now().toUtc().toIso8601String(),
    };
    await _operation(() => record(row));
    if (failures.isNotEmpty) {
      throw StateError('P84 lifecycle contract: ${failures.join(', ')}');
    }
    return row;
  }

  double _number(Map<String, Object?> row, String name) {
    final value =
        double.tryParse((row['properties'] as Map)[name] as String? ?? '');
    if (value == null || !value.isFinite) throw StateError('Missing $name');
    return value;
  }

  Future<void> _reopen() async {
    _check();
    final previous = owner;
    final next = await reopen();
    if (_closed ||
        currentOwner() != next ||
        next.session != previous.session ||
        next.player != previous.player ||
        next.sourcePath != previous.sourcePath ||
        next.serial != previous.serial + 1 ||
        next.generation <= previous.generation) {
      throw StateError('Unexpected identity after owned P84 reopen');
    }
    owner = next;
  }

  Future<void> _waitProgress(double previous) async {
    final budget = Stopwatch()..start();
    while (budget.elapsed < const Duration(seconds: 8)) {
      final value =
          double.tryParse(await _operation(() => readProperty('time-pos')));
      if (value != null && value > previous + 0.25) return;
      await _wait(const Duration(milliseconds: 200));
    }
    throw StateError('P84 playback did not progress');
  }

  Future<void> run(P84LifecycleAction action) async {
    if (busy) throw StateError('A P84 lifecycle action is already in flight');
    _check();
    _actionOrdinal++;
    final attempt = _run(action);
    _pending = attempt;
    changed();
    try {
      await attempt;
    } finally {
      if (identical(_pending, attempt)) _pending = null;
      changed();
    }
  }

  Future<void> _waitPosition(double target) async {
    final budget = Stopwatch()..start();
    while (budget.elapsed < const Duration(seconds: 8)) {
      final value =
          double.tryParse(await _operation(() => readProperty('time-pos')));
      if (value != null && (value - target).abs() <= 0.5) return;
      await _wait(const Duration(milliseconds: 100));
    }
    throw StateError('Paused seek did not settle at $target');
  }

  Future<void> _waitStopped() async {
    final budget = Stopwatch()..start();
    while (budget.elapsed < settleTimeout) {
      final idle = await _operation(() => readProperty('idle-active'));
      final path = await _operation(() => readProperty('path'));
      final position = await _operation(() => readProperty('time-pos'));
      if (idle == 'yes' && path.isEmpty && position.isEmpty) return;
      await _wait(const Duration(milliseconds: 100));
    }
    throw StateError('Stop did not reach idle with no loaded source');
  }

  Future<P84CompletionObservation> _waitNewFalse(int seekEpoch) async {
    final budget = Stopwatch()..start();
    while (budget.elapsed < settleTimeout) {
      _check();
      final event = readCompletion();
      if (!event.completed && event.lastFalseEpoch > seekEpoch) return event;
      await _wait(const Duration(milliseconds: 50));
    }
    throw StateError('Seek did not publish a new completed=false event');
  }

  Future<void> _waitNewCompleted(int falseEpoch) async {
    final budget = Stopwatch()..start();
    while (budget.elapsed < const Duration(seconds: 15)) {
      _check();
      final event = readCompletion();
      if (event.completed &&
          event.lastTrueEpoch > falseEpoch &&
          event.epoch >= event.lastTrueEpoch) {
        return;
      }
      await _wait(const Duration(milliseconds: 100));
    }
    throw StateError('No new completed=true event after this EOF seek');
  }

  Future<void> _run(P84LifecycleAction action) async {
    try {
      final before = await _capture('${action.label}:before');
      final position = _number(before, 'time-pos');
      switch (action) {
        case P84LifecycleAction.pauseHoldResume:
          await _operation(() => setPaused(true));
          final held = await _capture('pause-held', paused: true);
          await _wait(const Duration(seconds: 3));
          final heldAfter = await _capture('pause-held-3s', paused: true);
          if ((_number(heldAfter, 'time-pos') - _number(held, 'time-pos'))
                  .abs() >
              0.1) {
            throw StateError('Position advanced while paused');
          }
          await _operation(() => setPaused(false));
          await _waitProgress(position);
          break;
        case P84LifecycleAction.seekForwardBack:
          final duration = _number(before, 'duration');
          if (duration < 15) throw StateError('Seek test requires >15s source');
          await _operation(() => setPaused(true));
          final forward = (position + 5).clamp(1.0, duration - 3);
          await _operation(
              () => seek(Duration(milliseconds: (forward * 1000).round())));
          await _waitPosition(forward.toDouble());
          await _capture('paused-seek-forward', paused: true);
          await _wait(const Duration(milliseconds: 500));
          await _operation(
              () => seek(Duration(milliseconds: (position * 1000).round())));
          await _waitPosition(position);
          await _capture('paused-seek-back', paused: true);
          await _operation(() => setPaused(false));
          await _waitProgress(position);
          break;
        case P84LifecycleAction.nearEOFReplay:
          final duration = _number(before, 'duration');
          if (duration < 5) throw StateError('EOF test requires >5s source');
          await _operation(() => setPaused(false));
          final seekEpoch = readCompletion().epoch;
          await _operation(() =>
              seek(Duration(milliseconds: ((duration - 2) * 1000).round())));
          await _waitPosition(duration - 2);
          final notCompleted = await _waitNewFalse(seekEpoch);
          await _capture('near-eof-seek-settled');
          await _waitNewCompleted(notCompleted.lastFalseEpoch);
          await _capture('real-eof-completed', running: false);
          await _reopen();
          await _waitProgress(0);
          break;
        case P84LifecycleAction.stopReopen:
          await _operation(stopPlayer);
          await _waitStopped();
          await _capture('stopped-before-reopen', running: false);
          await _reopen();
          await _waitProgress(0);
          break;
      }
      final after = await _capture('${action.label}:after', paused: false);
      final redraw = _redrawDelta(before, after);
      await _operation(() => record({
            'runId': runId,
            'pid': pid,
            'actionOrdinal': _actionOrdinal,
            'action': action.label,
            'owner': owner.toJson(),
            'result': 'functional_only',
            'functionalChecks': 'passed',
            'candidateAcceptance':
                'requires_host_native_and_presentation_review',
            'redrawCoverage': redraw,
            'nativeEvidence': after['nativeEvidence'],
          }));
    } catch (error) {
      // Persist only already-known identities; never query a new owner on a
      // failed/cancelled action. No teardown or automatic recovery is hidden.
      await record({
        'runId': runId,
        'pid': pid,
        'actionOrdinal': _actionOrdinal,
        'action': action.label,
        'owner': owner.toJson(),
        'result': _closed ? 'cancelled' : 'failed',
        'error': '$error',
      });
      rethrow;
    }
  }

  String _redrawDelta(Map<String, Object?> before, Map<String, Object?> after) {
    final first =
        (before['nativeCounters'] as List).cast<Map<String, String>>();
    final last = (after['nativeCounters'] as List).cast<Map<String, String>>();
    for (final a in first) {
      for (final b in last) {
        if (a['kind'] != b['kind'] ||
            a['instance'] != b['instance'] ||
            a['start_ns'] != b['start_ns']) {
          continue;
        }
        if ((int.tryParse(b['mono_ns'] ?? '') ?? 0) <=
            (int.tryParse(a['mono_ns'] ?? '') ?? 0)) {
          continue;
        }
        for (final field in ['lease_reuse', 'redraw']) {
          if ((int.tryParse(b[field] ?? '') ?? 0) >
              (int.tryParse(a[field] ?? '') ?? 0)) {
            return 'native_counter_delta';
          }
        }
      }
    }
    return 'unverified';
  }

  Map<String, Object?> _nativeEvidence(List<Map<String, String>> counters) {
    final imports = counters.where((row) => row['kind'] == 'import').toList()
      ..sort((a, b) => (int.tryParse(b['mono_ns'] ?? '') ?? -1)
          .compareTo(int.tryParse(a['mono_ns'] ?? '') ?? -1));
    final issues = <String>[];
    final current = imports.isEmpty ? null : imports.first;
    var policyMismatch = false;
    if (current == null) {
      issues.add('no import counter snapshot');
    } else {
      final received = int.tryParse(current['_receivedAtMicros'] ?? '');
      final age = received == null
          ? null
          : DateTime.now().microsecondsSinceEpoch - received;
      if (age == null || age < 0 || age > 15000000) {
        issues.add('import snapshot is not fresh');
      }
      final start = int.tryParse(current['start_ns'] ?? '');
      final mono = int.tryParse(current['mono_ns'] ?? '');
      if (current['pid'] != '$pid' ||
          current['instance'] == null ||
          start == null ||
          start <= 0 ||
          mono == null ||
          mono < start) {
        issues.add('import identity is incomplete');
      }
      for (final field in [
        'fence_create_failed',
        'reap_stuck',
        'latch_timeout',
        'stale_drop'
      ]) {
        final value = int.tryParse(current[field] ?? '');
        if (value == null || value < 0) issues.add('missing/invalid $field');
      }
      for (final field in ['lease_copy', 'latch']) {
        final value = int.tryParse(current[field] ?? '');
        if (value == null || value <= 0) {
          issues.add('no active $field evidence');
        }
      }
      final policy = int.tryParse(current['defer_publish_flush'] ?? '');
      if (policy == null || (policy != 0 && policy != 1)) {
        issues.add('native publish policy unavailable');
      } else if (policy != deferPublishFlush) {
        policyMismatch = true;
        issues.add('native publish policy differs from this run');
      }
    }
    return {
      'status': issues.isEmpty ? 'verified_checkpoint' : 'unverified',
      'expectedDeferPublishFlush': deferPublishFlush,
      'policyMismatch': policyMismatch,
      'issues': issues,
      'kind': current?['kind'],
      'instance': current?['instance'],
      'mono_ns': current?['mono_ns'],
      'start_ns': current?['start_ns'],
      'scope':
          'internal importer checkpoint; host completion and display evidence still required',
    };
  }

  Future<void> cancelAndDrain() async {
    _closed = true;
    changed();
    if (!_cancel.isCompleted) _cancel.complete();
    final pending = _pending;
    if (pending != null) {
      try {
        await pending;
      } catch (_) {/* failure is already persisted */}
    }
  }
}

class AndroidP84LifecycleControls extends StatelessWidget {
  const AndroidP84LifecycleControls(
      {super.key,
      required this.ready,
      required this.busy,
      required this.run,
      required this.exit});
  final bool ready;
  final bool busy;
  final void Function(P84LifecycleAction) run;
  final VoidCallback exit;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.black87,
        child: SafeArea(
            top: false,
            child: Wrap(
              alignment: WrapAlignment.center,
              children: [
                for (final action in P84LifecycleAction.values)
                  Tooltip(
                      message: 'P84 ${action.label}',
                      child: TextButton(
                          onPressed: ready && !busy ? () => run(action) : null,
                          child: Text(action.label))),
                Tooltip(
                    message: 'P84 ExitCancel',
                    child: TextButton(
                        onPressed: exit, child: const Text('ExitCancel'))),
              ],
            )),
      );
}
