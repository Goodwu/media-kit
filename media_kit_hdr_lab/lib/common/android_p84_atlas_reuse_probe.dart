import 'dart:async';

import 'android_p84_quality_probe.dart';

/// Explicit default-off, same-player diagnostic only. Native identities and
/// archived data require independent host validation before ACK is written.
class P84AtlasReuseConfig {
  P84AtlasReuseConfig(this.nonce, this.firstPTS, this.secondPTS);
  final String nonce;
  final double firstPTS;
  final double secondPTS;
  static const property = 'debug.mks.atlas_reuse';
  static const nextPTS = 'debug.mks.atlas_pts2';
  static const nonceProperty = 'debug.mks.atlas_nonce';
  static const ackProperty = 'debug.mks.atlas_ack';
  static const offProperties = [
    'debug.mks.yuv_compare_repeat', 'debug.mks.yuv_tap', 'debug.mks.yuv_inv',
    'debug.mks.yuv_oracle', 'debug.mks.yuv_oracle_a', 'debug.mks.yuv_probe',
    'debug.mks.yuv_single', 'debug.mks.yuv_quad', 'debug.mks.yuv_rev',
    'debug.mks.yuv_fail_commit', 'debug.mks.yuv_fail_gl', 'debug.mks.gpu_timing',
    'debug.mks.st_fbo',
  ];
  static const properties = [property, nextPTS, nonceProperty, ackProperty,
    'debug.mks.yuv_compare', 'debug.mks.yuv_atlas', 'debug.mks.yuv_fusion',
    'debug.mks.yuv_compare_pts', 'debug.mks.quality_pts', ...offProperties];

  static P84AtlasReuseConfig? parse(Map<String, String> values) {
    final mode = values[property];
    if (mode == '' || mode == '0') return null;
    if (mode != '1' ||
        !RegExp(r'^[0-9a-f]{32}$').hasMatch(values[nonceProperty] ?? '') ||
        values[ackProperty] != '' ||
        ['debug.mks.yuv_compare', 'debug.mks.yuv_atlas', 'debug.mks.yuv_fusion']
            .any((key) => values[key] != '1') ||
        offProperties.any((key) => values[key] != '0')) {
      throw StateError('Explicit clean atlas reuse startup controls required');
    }
    final first = AndroidP84QualityProbe.finite(values['debug.mks.quality_pts']);
    final seed = AndroidP84QualityProbe.finite(values['debug.mks.yuv_compare_pts']);
    final second = AndroidP84QualityProbe.finite(values[nextPTS]);
    if (first == null || seed == null || second == null || first < 0 ||
        second < 0 || (first - seed).abs() > 0.000002 ||
        (first - second).abs() <= 0.000002 ||
        !AndroidP84QualityProbe.points.contains(first) ||
        !AndroidP84QualityProbe.points.contains(second)) {
      throw StateError('Two distinct preset atlas PTS required');
    }
    return P84AtlasReuseConfig(values[nonceProperty]!, first, second);
  }
}

class AndroidP84AtlasReuseProbe {
  AndroidP84AtlasReuseProbe({
    required this.config, required this.quality, required this.nativeLogs,
    required this.readAck, required this.currentOwnerValid, required this.record,
    this.stageTimeout = const Duration(seconds: 300),
    this.totalTimeout = const Duration(seconds: 650),
    this.delay = Future<void>.delayed,
    this.now = DateTime.now,
  });
  final P84AtlasReuseConfig config;
  final AndroidP84QualityProbe quality;
  final Stream<String> nativeLogs;
  final Future<String> Function() readAck;
  final bool Function() currentOwnerValid;
  final Future<void> Function(Map<String, Object?>) record;
  final Duration stageTimeout;
  final Duration totalTimeout;
  final Future<void> Function(Duration) delay;
  final DateTime Function() now;
  StreamSubscription<String>? _subscription;
  Future<void>? _pending;
  final _stop = Completer<void>();
  bool _closed = false;
  Object? _failure;
  Map<String, String>? _promoted, _accepted;
  late DateTime _totalDeadline, _stageDeadline;
  String status = 'not-started';
  static const identityKeys = ['nonce', 'cache_id', 'cache_generation',
    'renderer_id', 'renderer_generation', 'signature', 'seed_capture_id',
    'seed_pts', 't2_pts', 'stage', 'ordinal'];
  static const nativeEvents = ['seed-promoted', 'armed', 'capture-complete',
    'capture-diagnostic-invalid', 'promoted-ready', 'ack-accepted',
    'capture-failed', 'config-invalid', 'cleanup-deferred'];

  static bool _positiveU64(String? value) => value != null &&
      RegExp(r'^[1-9][0-9]*$').hasMatch(value) &&
      (value.length < 20 || value.length == 20 &&
          value.compareTo('18446744073709551615') <= 0);

  void _check() {
    if (_closed || !currentOwnerValid()) throw StateError('Atlas reuse cancelled or owner changed');
    if (_failure != null) throw StateError('Native atlas reuse failed: $_failure');
    if (!now().isBefore(_totalDeadline) || !now().isBefore(_stageDeadline)) {
      throw StateError('Atlas reuse stage/total deadline expired');
    }
  }

  Duration _remaining() {
    _check();
    final end = _stageDeadline.isBefore(_totalDeadline) ? _stageDeadline : _totalDeadline;
    return end.difference(now());
  }

  Future<T> _op<T>(Future<T> Function() action) async {
    final remaining = _remaining();
    final result = await Future.any<T>([action(), _stop.future.then<T>((_) =>
      throw StateError('Atlas reuse cancelled'))]).timeout(remaining);
    _check();
    return result;
  }

  Future<void> _row(String step, [Map<String, Object?> extra = const {}]) async {
    status = step;
    await record({'runId': quality.runId, 'owner': quality.owner.toJson(),
      'nonce': config.nonce, 'firstPTS': config.firstPTS, 'secondPTS': config.secondPTS,
      'status': step, ...extra});
  }

  Map<String, String> _receipt(Map<String, String> row) {
    if (row['nonce'] != config.nonce || row['stage'] != '1' || row['ordinal'] != '1' ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(row['signature'] ?? '') ||
        ['cache_id', 'cache_generation', 'renderer_id', 'renderer_generation', 'seed_capture_id']
            .any((key) => !_positiveU64(row[key]))) {
      throw StateError('Atlas promotion identity is missing or changed');
    }
    for (final pair in [('seed_pts', config.firstPTS), ('t2_pts', config.secondPTS)]) {
      final value = AndroidP84QualityProbe.finite(row[pair.$1]);
      if (value == null || (value - pair.$2).abs() > 0.000002) {
        throw StateError('Atlas promotion PTS mismatch');
      }
    }
    return {for (final key in identityKeys) key: row[key]!};
  }

  void _native(String text) {
    if (_closed) return;
    try {
      if (!currentOwnerValid()) throw StateError('Atlas native event owner changed');
      final marker = RegExp(r'(?<![\w-])(MKS-UV-ATLAS-READ|MKS-YUV-ATLAS(?:-LIB)?|MKS-YUV-COMPARE(?:-LIB)?)\s+')
          .firstMatch(text);
      if (marker == null) return;
      final pairs = RegExp(r'([A-Za-z_][\w-]*)=([^\s]+)').allMatches(text.substring(marker.end)).toList();
      final row = {for (final pair in pairs) pair.group(1)!: pair.group(2)!};
      if (row.length != pairs.length || row['event'] == null) throw StateError('Malformed atlas event');
      final event = row['event'];
      if (['capture-failed', 'capture-diagnostic-invalid', 'config-invalid',
        'cleanup-deferred', 'fatal-cleanup-deferred', 'rejected', 'caps-rejected',
        'arm-rejected', 'ssbo-binding-rejected'].contains(event)) {
        throw StateError('Terminal ${marker.group(1)} $row');
      }
      if (marker.group(1) != 'MKS-UV-ATLAS-READ') return;
      if (!nativeEvents.contains(event)) throw StateError('Unknown atlas read event');
      if (event == 'promoted-ready') {
        if (_promoted != null || _accepted != null) throw StateError('Duplicate/out-of-order promotion');
        _promoted = _receipt(row);
      } else if (event == 'ack-accepted') {
        final accepted = _receipt(row);
        if (_promoted == null || _accepted != null ||
            identityKeys.any((key) => accepted[key] != _promoted![key])) {
          throw StateError('ACK without matching promotion');
        }
        _accepted = accepted;
      }
    } catch (error) {
      _failure ??= error;
    }
  }

  Future<void> run() {
    if (_closed || _pending != null || status != 'not-started') {
      return Future.error(StateError('Atlas reuse runner cannot restart'));
    }
    final future = _run();
    _pending = future;
    return future.whenComplete(() => _pending = null);
  }

  Future<void> _run() async {
    _totalDeadline = now().add(totalTimeout);
    _stageDeadline = now().add(stageTimeout);
    _subscription = nativeLogs.listen(_native, onError: (Object e) => _failure ??= e,
      onDone: () { if (!_closed && status != 'second-observation-ready') _failure ??= StateError('Native log stream closed'); });
    try {
      await _op(() => _row('first-observation-started'));
      await _op(() => quality.observe(config.firstPTS));
      while (_promoted == null) {
        await _op(() => delay(const Duration(milliseconds: 250)));
      }
      await _op(() => _row('awaiting-host-ack', {'promotion': _promoted}));
      final expected = '${config.nonce}:${_promoted!['cache_id']}';
      while (true) {
        final ack = (await _op(readAck)).trim();
        if (ack == expected) break;
        if (ack.isNotEmpty) throw StateError('Stale/malformed atlas ACK rejected');
        if (_accepted != null) throw StateError('Native ACK accepted before current host ACK');
        await _op(() => delay(const Duration(milliseconds: 250)));
      }
      await _op(() => _row('awaiting-native-ack', {'promotion': _promoted}));
      while (_accepted == null) {
        if ((await _op(readAck)).trim() != expected) throw StateError('Host ACK changed');
        await _op(() => delay(const Duration(milliseconds: 250)));
      }
      if ((await _op(readAck)).trim() != expected) throw StateError('Host ACK changed');
      _stageDeadline = now().add(stageTimeout);
      await _op(() => _row('second-observation-started', {'promotion': _accepted}));
      // observe() drains the first monitor before recording seek-started #2.
      await _op(() => quality.observe(config.secondPTS));
      await _op(() => _row('second-observation-ready', {'promotion': _accepted}));
    } catch (error) {
      await quality.cancelAndDrain();
      await _row(_closed ? 'cancelled' : 'failed', {'error': '$error'});
      rethrow;
    }
  }

  Future<void> cancelAndDrain() async {
    _closed = true;
    if (!_stop.isCompleted) _stop.complete();
    await quality.cancelAndDrain();
    try { await _pending; } catch (_) { /* recorded by the runner */ }
    await _subscription?.cancel();
    _subscription = null;
  }
}
