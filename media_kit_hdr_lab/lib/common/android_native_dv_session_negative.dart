// ignore_for_file: implementation_imports, depend_on_referenced_packages
import 'dart:async';
import 'dart:convert';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:media_kit_video/src/hdr/hdr_disposal.dart';
import 'package:media_kit_video/src/hdr/hdr_open_coordinator.dart';
import 'package:media_kit_video/src/hdr/hdr_native_dv_option_owner.dart';
import 'package:path_provider/path_provider.dart' as path_provider;

/// A denied identity is retained even after null retirement. A failed
/// dispose retaining that identity can never accidentally mount it later.
class AndroidNativeDvN1MountAdmission<T extends Object> {
  bool armed = false;
  T? denied;
  T? admitted;
  bool retired = false;
  bool invalid = false;

  void arm() {
    if (armed) throw StateError('N1 denial already armed');
    armed = true;
  }

  bool observe(T? controller, {required bool native}) {
    if (!armed) throw StateError('N1 denial must precede controller publish');
    if (controller == null) {
      if (denied != null) retired = true;
      admitted = null;
      return false;
    }
    if (denied == null) {
      if (!native) invalid = true;
      denied = controller;
      return false;
    }
    if (identical(denied, controller)) return false;
    if (!retired || native) {
      invalid = true;
      return false;
    }
    admitted = controller;
    return true;
  }

  bool mayMount(T? controller) =>
      controller != null &&
      !invalid &&
      retired &&
      identical(controller, admitted) &&
      !identical(controller, denied);
}

/// Notification callbacks only append synchronous scalar snapshots. No I/O,
/// Player calls, mount changes, rebind, open or disposal occurs in callbacks.
class AndroidNativeDvN1Run {
  AndroidNativeDvN1Run(
      {required this.externalIdentityLabel,
      this.maxRows = 4096,
      this.maxText = 16384,
      this.durationSeconds = 300,
      this.writeOverride,
      int Function()? elapsedMicros})
      : _elapsedMicros = elapsedMicros {
    if (maxRows < 1 ||
        maxText < 1 ||
        durationSeconds < 1 ||
        durationSeconds > 300) {
      throw RangeError('Invalid N1 bounds');
    }
    _clock.start();
  }

  final String externalIdentityLabel;
  final int maxRows;
  final int maxText;
  final int durationSeconds;
  final Future<void> Function(Map<String, Object?>)? writeOverride;
  final int Function()? _elapsedMicros;
  final Stopwatch _clock = Stopwatch();
  final String runId = '${DateTime.now().microsecondsSinceEpoch}-n1';
  final status = ValueNotifier<String>(
      'N1 prepared; native output deliberately unmounted');
  final mount = AndroidNativeDvN1MountAdmission<VideoController>();
  final List<Map<String, Object?>> _rows = [];
  final List<(Object, StackTrace?)> _rawErrors = [];
  final Set<String> _gaps = {};
  final Map<Object, int> _transactions = HashMap.identity();
  int openRequests = 0;
  int? generation;
  bool overflow = false;
  bool closed = false;
  bool debt = false;
  bool sessionClean = false;
  bool controllerRetired = false;
  bool playerTerminated = false;
  Map<String, String>? _baseline;
  Map<String, String>? _post;
  Map<String, Object?>? _disposeReport;
  File? _latest;
  File? _archive;
  Future<void> _writeTail = Future<void>.value();
  Future<void>? _closeFuture;
  Timer? _persistTimer;
  int? _finalElapsedMicros;
  int? _lastCoordinatorSequence;
  int? _lastCoordinatorMicros;

  List<Map<String, Object?>> get rows => List.unmodifiable(_rows);
  List<(Object, StackTrace?)> get rawErrors => List.unmodifiable(_rawErrors);
  bool get evidenceComplete => !overflow && _gaps.isEmpty;
  int get elapsedMicros =>
      _finalElapsedMicros ??
      _elapsedMicros?.call() ??
      _clock.elapsedMicroseconds;

  void gap(String reason) {
    _gaps.add(_text(reason));
  }

  String _text(Object? value) {
    String text;
    try {
      text = value?.toString() ?? '';
    } catch (_) {
      _gaps.add('text-projection-threw');
      return '<projection failed>';
    }
    if (text.length <= maxText) return text;
    _gaps.add('text-truncated');
    return text.substring(0, maxText);
  }

  Object? _snapshot(Object? value, int depth) {
    if (depth > 8) {
      gap('snapshot-depth');
      return null;
    }
    if (value == null || value is bool || value is num) return value;
    if (value is String) return _text(value);
    if (value is Map) {
      if (value.length > 128) {
        gap('snapshot-map-bound');
        return null;
      }
      return Map<String, Object?>.unmodifiable({
        for (final entry in value.entries)
          _text(entry.key): _snapshot(entry.value, depth + 1),
      });
    }
    if (value is Iterable) {
      final list = value.take(129).toList();
      if (list.length > 128) {
        gap('snapshot-list-bound');
        return null;
      }
      return List<Object?>.unmodifiable(
          list.map((v) => _snapshot(v, depth + 1)));
    }
    gap('non-scalar-envelope');
    return _text(value);
  }

  void record(String kind, Map<String, Object?> fields,
      {Object? error, StackTrace? stack}) {
    if (closed) {
      gap('late-event-after-final-report');
      return;
    }
    if (_rows.length >= maxRows) {
      overflow = true;
      return;
    }
    if (error != null) {
      if (_rawErrors.length >= 64) {
        overflow = true;
      } else {
        _rawErrors.add((error, stack));
      }
    }
    _rows.add(Map<String, Object?>.unmodifiable({
      'index': _rows.length,
      'elapsedMicros': elapsedMicros,
      'kind': kind,
      ...(_snapshot(fields, 0)! as Map<String, Object?>),
      if (error != null) 'errorType': _text(error.runtimeType),
      if (error != null) 'error': _text(error),
      if (stack != null) 'stack': _text(stack),
    }));
  }

  Map<String, Object?>? _attempt(
          HdrBackendDiagnosticAttempt<HdrOpenPlan>? value) =>
      value == null
          ? null
          : {
              'coordinatorGeneration': value.coordinatorGeneration,
              'ordinal': value.ordinal,
              'source': value.plan.media.uri,
              'route': routeFields(value.plan.route),
              'capabilities': {
                'sdkInt': value.plan.capabilities.sdkInt,
                'displayHdrTypes':
                    value.plan.capabilities.displayHdrTypes?.take(129).toList(),
                'nativeDvBridgeApi': value.plan.capabilities.nativeDvBridgeApi,
                'p5PipelineAvailable':
                    value.plan.capabilities.p5PipelineAvailable
              },
              'excluded': {
                for (final entry in value.plan.excluded.entries.take(129))
                  entry.key: entry.value.name
              },
            };

  void onBackendCall(HdrBackendCallDiagnostic<HdrOpenPlan> event) {
    try {
      if (_lastCoordinatorSequence != null &&
          event.sequence != _lastCoordinatorSequence! + 1) {
        gap('coordinator-sequence-gap');
      }
      if (_lastCoordinatorMicros != null &&
          event.elapsedMicros < _lastCoordinatorMicros!) {
        gap('coordinator-clock-regressed');
      }
      _lastCoordinatorSequence = event.sequence;
      _lastCoordinatorMicros = event.elapsedMicros;
      record(
          'backend-call',
          {
            'sequence': event.sequence,
            'coordinatorElapsedMicros': event.elapsedMicros,
            'coordinatorGeneration': event.coordinatorGeneration,
            'sessionGeneration': event.sessionGeneration,
            'owningSessionGeneration': event.owningSessionGeneration,
            'invocation': _attempt(event.invocation),
            'owningAttempt': _attempt(event.owningAttempt),
            'method': event.method.name,
            'boundary': event.boundary.name,
            'purpose': event.purpose.name,
            'boundaryScope': event.boundaryScope,
            'isTimeoutException': event.error is TimeoutException,
            'timeoutDurationMicros': event.error is TimeoutException
                ? (event.error as TimeoutException).duration?.inMicroseconds
                : null,
          },
          error: event.error,
          stack: event.stack);
    } catch (error, stack) {
      gap('backend-envelope-projection-failed');
      record('projection-failed', {}, error: error, stack: stack);
    }
  }

  void onNativeOption(HdrNativeDvOptionDiagnostic event) {
    try {
      if (!_transactions.containsKey(event.transaction)) {
        if (_transactions.length >= 32) {
          overflow = true;
          return;
        }
        _transactions[event.transaction] = _transactions.length + 1;
      }
      record(
          'native-option',
          {
            'transaction': _transactions[event.transaction],
            'sourcePath': event.sourcePath,
            'sourcePlaylistEntryId': event.sourcePlaylistEntryId,
            'sourceFileLoadedEpoch': event.sourceFileLoadedEpoch,
            'purpose': event.purpose.name,
            'name': event.name,
            'original': event.original,
            'requested': event.requested,
            'observed': event.observed
          },
          error: event.error,
          stack: event.stack);
    } catch (error, stack) {
      gap('owner-envelope-projection-failed');
      record('projection-failed', {}, error: error, stack: stack);
    }
  }

  /// Checks captured evidence, never changes playback or repairs an option.
  /// Surface ACK and visible output remain independent device acceptance.
  Map<String, Object?> audit() {
    final failures = <String>[];
    void require(bool condition, String reason) {
      if (!condition) failures.add(reason);
    }

    final calls = _rows.where((r) => r['kind'] == 'backend-call').toList();
    String? strategy(Map<String, Object?> row) {
      final attempt = row['invocation'];
      if (attempt is! Map) return null;
      final route = attempt['route'];
      return route is Map ? route['strategy'] as String? : null;
    }

    final native =
        calls.where((r) => strategy(r) == 'nativeDolbyVision').toList();
    final allFallback = calls
        .where((r) => strategy(r) != null && strategy(r) != 'nativeDolbyVision')
        .toList();
    int entries(List<Map<String, Object?>> list, String method) => list
        .where((r) => r['method'] == method && r['boundary'] == 'entered')
        .length;
    final failed = native
        .where(
            (r) => r['method'] == 'prepareOutput' && r['boundary'] == 'failed')
        .toList();
    require(openRequests == 1, 'single-open-request');
    require(evidenceComplete, 'bounded-complete-evidence');
    require(!mount.invalid && mount.denied != null && mount.retired,
        'denied-native-successfully-retired');
    require(
        entries(native, 'prepareOutput') == 1, 'native-prepare-entry-count');
    require(entries(native, 'configure') == 0 && entries(native, 'open') == 0,
        'native-configure-open-not-entered');
    require(
        failed.length == 1 &&
            failed.single['isTimeoutException'] == true &&
            failed.single['timeoutDurationMicros'] == 10000000,
        'actual-native-prepare-ten-second-timeout');
    final entered = native
        .where(
            (r) => r['method'] == 'prepareOutput' && r['boundary'] == 'entered')
        .toList();
    if (failed.length == 1 && entered.length == 1) {
      require(
          (failed.single['coordinatorElapsedMicros'] as int) -
                  (entered.single['coordinatorElapsedMicros'] as int) >=
              10000000,
          'native-prepare-awaited-operation-elapsed-at-least-ten-seconds');
    }
    final nativeGeneration =
        failed.length == 1 ? failed.single['sessionGeneration'] : null;
    final fallback = allFallback
        .where((r) =>
            r['sessionGeneration'] == nativeGeneration &&
            r['purpose'] != 'disposal')
        .toList();
    final degraded = _rows
        .where((r) =>
            r['kind'] == 'degraded' &&
            r['reason'] == 'nativeDvUnavailable' &&
            r['generation'] == nativeGeneration)
        .toList();
    final applied = _rows
        .where((r) =>
            r['kind'] == 'route-applied' && r['generation'] == nativeGeneration)
        .toList();
    require(
        nativeGeneration != null && degraded.length == 1 && applied.length == 1,
        'same-session-generation-typed-degradation-applied');
    require(
        entries(fallback, 'configure') >= 1 && entries(fallback, 'open') >= 1,
        'actual-fallback-configure-open-entries');
    final fallbackStart = fallback
        .where((r) =>
            r['boundary'] == 'entered' &&
            (r['method'] == 'prepareOutput' || r['method'] == 'configure'))
        .toList();
    final options = _rows.where((r) => r['kind'] == 'native-option').toList();
    final tokens = options
        .where((r) => r['purpose'] == 'apply')
        .map((r) => r['transaction'])
        .toSet();
    require(tokens.length == 1, 'one-native-option-transaction');
    if (tokens.length == 1 && fallbackStart.isNotEmpty && failed.length == 1) {
      final token = tokens.single;
      final transaction =
          options.where((r) => r['transaction'] == token).toList();
      final originals =
          transaction.where((r) => r['purpose'] == 'originals').toList();
      final applies =
          transaction.where((r) => r['purpose'] == 'apply').toList();
      const names = ['vd-lavc-o', 'mediacodec-embed-render-mode'];
      require(
          names.every(
              (name) => originals.where((r) => r['name'] == name).length == 1),
          'both-originals-captured');
      require(
          originals.length == 2 &&
              applies.length == 2 &&
              originals.every(
                  (r) => (r['index'] as int) < (applies.first['index'] as int)),
          'both-originals-before-first-write');
      require(names.every((name) {
        final captured = originals.where((r) => r['name'] == name).toList();
        final appliedOption = applies.where((r) => r['name'] == name).toList();
        return captured.length == 1 &&
            appliedOption.length == 1 &&
            appliedOption.single['original'] == captured.single['original'] &&
            appliedOption.single['observed'] ==
                appliedOption.single['requested'];
      }), 'applied-originals-match-captured-values');
      require(
          applies.any((r) =>
                  r['name'] == names[0] &&
                  r['observed'] == r['requested'] &&
                  '${r['observed']}'.contains('native_dv=1')) &&
              applies.any(
                  (r) => r['name'] == names[1] && r['observed'] == 'timed'),
          'actual-native-option-pair-applied');
      final restore = transaction
          .where((r) =>
              (r['purpose'] == 'restore' || r['purpose'] == 'restoreNoWrite') &&
              (r['index'] as int) > (failed.single['index'] as int) &&
              (r['index'] as int) < (fallbackStart.first['index'] as int))
          .toList();
      require(names.every((name) {
        final captured = originals.where((r) => r['name'] == name).toList();
        return captured.length == 1 &&
            restore.any((r) =>
                r['name'] == name &&
                r['original'] == captured.single['original'] &&
                r['observed'] == captured.single['original']);
      }), 'both-restored-values-before-fallback');
      bool ownsFailedNative(Map<String, Object?> r) {
        final owner = r['owningAttempt'];
        final original = failed.single['invocation'];
        return r['owningSessionGeneration'] == nativeGeneration &&
            owner is Map &&
            original is Map &&
            owner['coordinatorGeneration'] ==
                original['coordinatorGeneration'] &&
            owner['ordinal'] == original['ordinal'] &&
            jsonEncode(owner['route']) == jsonEncode(original['route']);
      }

      final reset = calls
          .where((r) =>
              r['method'] == 'resetOwnedConfiguration' &&
              r['boundary'] == 'returned' &&
              r['purpose'] == 'rollback' &&
              ownsFailedNative(r) &&
              restore.length >= 2 &&
              (r['index'] as int) > (restore.last['index'] as int) &&
              (r['index'] as int) < (fallbackStart.first['index'] as int))
          .toList();
      require(
          reset.any((end) => calls.any((begin) =>
              begin['method'] == 'resetOwnedConfiguration' &&
              begin['boundary'] == 'entered' &&
              begin['purpose'] == 'rollback' &&
              ownsFailedNative(begin) &&
              restore.length >= 2 &&
              (begin['index'] as int) > (failed.single['index'] as int) &&
              (begin['index'] as int) < (restore.first['index'] as int) &&
              (begin['index'] as int) < (end['index'] as int) &&
              jsonEncode(begin['invocation']) ==
                  jsonEncode(end['invocation']))),
          'owned-rollback-restoration-reset-returned-before-fallback');
      require(
          applies.length == 2 &&
              entered.length == 1 &&
              applies.every((r) =>
                  (r['index'] as int) > (entered.single['index'] as int) &&
                  (r['index'] as int) < (failed.single['index'] as int)),
          'native-transaction-applied-within-failed-prepare');
      final attempt = fallbackStart.first['invocation'];
      require(
          attempt is Map &&
              attempt['excluded'] is Map &&
              (attempt['excluded'] as Map)
                  .values
                  .contains('nativeDvUnavailable'),
          'fallback-plan-native-exclusion');
    } else {
      failures.add('rollback-order-evidence-missing');
    }
    if (applied.length == 1 && degraded.length == 1) {
      require(
          applied.single['route'] is Map &&
              (applied.single['route'] as Map)['strategy'] !=
                  'nativeDolbyVision',
          'real-distinct-fallback-route');
      require(
          degraded.single['from'] is Map &&
              (degraded.single['from'] as Map)['strategy'] ==
                  'nativeDolbyVision' &&
              failed.length == 1 &&
              failed.single['invocation'] is Map &&
              jsonEncode(degraded.single['from']) ==
                  jsonEncode((failed.single['invocation'] as Map)['route']),
          'typed-native-failure-origin');
      require(
          applied.single['verified'] == true, 'route-applied-report-verified');
      require(
          degraded.single['to'] != null &&
              jsonEncode(degraded.single['to']) ==
                  jsonEncode(applied.single['route']) &&
              jsonEncode(applied.single['route']) ==
                  jsonEncode(applied.single['reportedActual']),
          'typed-degradation-target-matches-actual-applied-route');
    }
    require(
        allFallback
            .where((r) => r['purpose'] != 'disposal')
            .every((r) => r['sessionGeneration'] == nativeGeneration),
        'fallback-retains-session-generation');
    Map<String, Object?>? successfulAttempt;
    if (applied.length == 1 && degraded.length == 1) {
      final target = jsonEncode(applied.single['route']);
      bool sameAttempt(Map<String, Object?> a, Map<String, Object?> b) =>
          a['sessionGeneration'] == b['sessionGeneration'] &&
          jsonEncode(a['invocation']) == jsonEncode(b['invocation']);
      final returnedOpens = fallback.where((r) =>
          r['method'] == 'open' &&
          r['boundary'] == 'returned' &&
          r['invocation'] is Map &&
          jsonEncode((r['invocation'] as Map)['route']) == target);
      for (final opened in returnedOpens) {
        final successful = <String, List<Map<String, Object?>>>{};
        for (final method in ['prepareOutput', 'configure', 'open']) {
          final methodRows = fallback
              .where((r) => r['method'] == method && sameAttempt(r, opened))
              .toList();
          final begins =
              methodRows.where((r) => r['boundary'] == 'entered').toList();
          final ends =
              methodRows.where((r) => r['boundary'] == 'returned').toList();
          if (begins.length == 1 &&
              ends.length == 1 &&
              (begins.single['index'] as int) < (ends.single['index'] as int) &&
              !methodRows.any((r) => r['boundary'] == 'failed')) {
            successful[method] = [begins.single, ends.single];
          }
        }
        if (successful.length == 3 &&
            (successful['prepareOutput']!.last['index'] as int) <
                (successful['configure']!.first['index'] as int) &&
            (successful['configure']!.last['index'] as int) <
                (successful['open']!.first['index'] as int) &&
            (opened['index'] as int) < (applied.single['index'] as int)) {
          successfulAttempt =
              Map<String, Object?>.from(opened['invocation'] as Map);
        }
      }
    }
    require(successfulAttempt != null,
        'actual-successful-fallback-attempt-matches-applied-target');
    for (final begin in fallback.where((r) =>
        ['prepareOutput', 'configure', 'open'].contains(r['method']) &&
        r['boundary'] == 'entered')) {
      require(
          fallback
                  .where((end) =>
                      end['method'] == begin['method'] &&
                      ['returned', 'failed'].contains(end['boundary']) &&
                      (end['index'] as int) > (begin['index'] as int) &&
                      jsonEncode(end['invocation']) ==
                          jsonEncode(begin['invocation']))
                  .length ==
              1,
          'fallback-invocation-has-exactly-one-outcome');
    }
    return {
      'configurationEvidenceComplete': failures.isEmpty,
      'successfulFallbackAttempt': successfulAttempt,
      'failures': failures,
      'nativeEntries': {
        for (final m in ['prepareOutput', 'configure', 'open'])
          m: entries(native, m)
      },
      'fallbackEntries': {
        for (final m in ['prepareOutput', 'configure', 'open'])
          m: entries(fallback, m)
      },
      'nativePrepareAwaitedOperationElapsedMicros':
          failed.length == 1 && entered.length == 1
              ? (failed.single['coordinatorElapsedMicros'] as int) -
                  (entered.single['coordinatorElapsedMicros'] as int)
              : null,
      'durationScope':
          'whole coordinator prepareOutput await; not an isolated bound-wait stopwatch',
      'presentationVerified': false
    };
  }

  void admitOpen() {
    if (closed || openRequests != 0 || !mount.armed) {
      throw StateError('N1 admits exactly one open after denial is armed');
    }
    openRequests++;
    record('open-request',
        {'source': '/data/local/tmp/media-kit-lg-dv-p5-2160p.mp4'});
  }

  bool observeController(VideoController? controller) {
    final prepares = _rows.where((r) =>
        r['kind'] == 'backend-call' &&
        r['method'] == 'prepareOutput' &&
        r['boundary'] == 'entered');
    final attempt = prepares.isEmpty ? null : prepares.last['invocation'];
    final route = attempt is Map ? attempt['route'] : null;
    final native = route is Map && route['strategy'] == 'nativeDolbyVision';
    if (controller != null && route == null) {
      gap('controller-without-prepare-attribution');
    }
    final admitted = mount.observe(controller, native: native);
    record('controller-notification', {
      'controller': controller == null ? null : identityHashCode(controller),
      'denied': mount.denied == null ? null : identityHashCode(mount.denied!),
      'nullRetirementObserved': mount.retired,
      'admitted': admitted,
      'prepareRoute': route,
      'nativeSurfaceActive': controller?.nativeSurfaceActive,
      'nativeSurfaceCandidate': controller?.nativeSurfaceCandidate,
    });
    if (mount.invalid) gap('replacement-before-null-retirement');
    return admitted;
  }

  void onEvent(HdrOutputEvent event) {
    if (event is HdrDegradedEvent) {
      generation ??= event.generation;
      record('degraded', {
        'generation': event.generation,
        'reason': event.reason.name,
        'from': routeFields(event.from),
        'to': routeFields(event.to),
        'diagnostic': event.diagnostic
      });
    } else if (event is HdrRouteAppliedEvent) {
      record('route-applied', {
        'generation': event.generation,
        'route': routeFields(event.route),
        'verified': event.report.verified,
        'reportedActual': routeFields(event.report.actual)
      });
      status.value =
          'N1 fallback route applied: ${event.route.strategy.name}; visual confirmation pending';
    } else if (event is HdrErrorEvent) {
      record(
          'session-error',
          {
            'generation': event.generation,
            'reason': event.reason?.name,
            'diagnostic': event.diagnostic
          },
          error: event.error);
    }
  }

  static Map<String, Object?>? routeFields(HdrRoute? route) => route == null
      ? null
      : {
          'strategy': route.strategy.name,
          'presentation': route.presentation.name,
          'topology': route.topology.name,
          'vo': route.vo,
          'hwdec': route.hwdec,
          'vdLavcOptions': route.vdLavcOptions,
          'renderMode': route.mediacodecEmbedRenderMode,
          'outputTransfer': route.outputTransfer.name,
          'appliesDynamicMetadata': route.appliesDynamicMetadata,
          'targetPrim': route.targetPrim,
          'targetTrc': route.targetTrc,
          'surfaceTransfer': route.surfaceTransfer,
          'stripDvRpu': route.stripDvRpu,
          'dependencies': route.dependencies.take(129).toList()..sort(),
        };

  Future<Map<String, String>> _properties(Player player) =>
      player.lock.synchronized(() async {
        final before = player.fileLoadedEpoch;
        final result = <String, String>{};
        for (final name in const [
          'path',
          'playlist/0/id',
          'vd-lavc-o',
          'mediacodec-embed-render-mode',
          'hwdec',
          'hwdec-current',
          'vo'
        ]) {
          result[name] =
              await player.getProperty(name, waitForInitialization: false);
        }
        result['fileLoadedEpoch'] = before.toString();
        if (before != player.fileLoadedEpoch) {
          throw StateError('Source changed during N1 cleanup snapshot');
        }
        return Map.unmodifiable(result);
      });

  Future<void> prepare(Player player) async {
    if (writeOverride == null) {
      final root = await path_provider.getExternalStorageDirectory();
      if (root == null) throw StateError('N1 external files unavailable');
      final directory = Directory('${root.path}/media-kit-hdr-diagnostic');
      await directory.create(recursive: true);
      _latest = File('${directory.path}/native-dv-session-negative.json');
      _archive =
          File('${directory.path}/native-dv-session-negative-$runId.json');
    }
    _baseline = await _properties(player);
    if (_baseline!['path'] != '' || player.state.playing) {
      throw StateError('N1 requires idle real Player');
    }
    record('idle-baseline', {'properties': _baseline});
    mount.arm();
    await persist();
    _persistTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (closed) return;
      if (elapsedMicros >= durationSeconds * 1000000) {
        gap('run-duration-expired');
        _persistTimer?.cancel();
      }
      unawaited(persist().catchError((Object error, StackTrace stack) {
        gap('periodic-persistence-failed');
        record('persistence-failed', {}, error: error, stack: stack);
      }));
    });
  }

  Future<void> captureCleanup(
      {required Player player,
      required HdrDisposalReport? report,
      required Object? error,
      required VideoController? controller}) async {
    _disposeReport = {
      'clean': report?.clean,
      'coordinatorError': _text(report?.coordinatorError),
      'playerError': _text(report?.playerError),
      'directoryError': _text(report?.directoryError),
      'retainedDirectory': report?.retainedDirectory
    };
    controllerRetired = controller == null;
    try {
      _post = await _properties(player);
    } catch (e, s) {
      record('cleanup-read-failed', {}, error: e, stack: s);
      debt = true;
    }
    final restored = _baseline != null &&
        _post != null &&
        _baseline!.entries
            .where((entry) => entry.key != 'fileLoadedEpoch')
            .every((entry) => _post![entry.key] == entry.value) &&
        int.parse(_post!['fileLoadedEpoch']!) >=
            int.parse(_baseline!['fileLoadedEpoch']!);
    sessionClean =
        report?.clean == true && error == null && controllerRetired && restored;
    debt = debt || !sessionClean;
    record(
        'session-cleanup',
        {
          'report': _disposeReport,
          'controllerRetired': controllerRetired,
          'properties': _post,
          'baselineMatched': restored,
          'surfaceReleaseAcknowledgement': 'not independently observed'
        },
        error: error);
    await persist();
  }

  Future<void> recordTermination(Object? error) async {
    playerTerminated = error == null;
    debt = debt || !playerTerminated;
    record('player-termination', {'success': playerTerminated}, error: error);
    await persist();
  }

  Map<String, Object?> toJson() => {
        'schema': 1,
        'diagnosticOnly': true,
        'mode': 'N1-real-unmounted-native-output',
        'runId': runId,
        'externalIdentityLabel': externalIdentityLabel,
        'elapsedMicros': elapsedMicros,
        'durationLimitSeconds': durationSeconds,
        'openRequests': openRequests,
        'generation': generation,
        'closed': closed,
        'debt': debt,
        'overflow': overflow,
        'evidenceGaps': _gaps.toList(),
        'status': status.value,
        'presentationVerified': false,
        'sessionClean': sessionClean,
        'controllerRetired': controllerRetired,
        'playerTerminated': playerTerminated,
        'cleanupVerified':
            sessionClean && controllerRetired && playerTerminated && !debt,
        'surfaceReleaseAcknowledgement': 'not independently observed',
        'audit': audit(),
        'rows': rows,
      };

  Future<void> persist() {
    final value = toJson();
    final next = _writeTail.then((_) async {
      if (writeOverride != null) {
        await writeOverride!(value);
        return;
      }
      final json = jsonEncode(value);
      for (final file in [_archive, _latest]) {
        if (file == null) throw StateError('N1 report storage not prepared');
        final temp = File('${file.path}.tmp');
        await temp.writeAsString(json, flush: true);
        await temp.rename(file.path);
      }
    });
    _writeTail = next.catchError((Object _) {});
    return next;
  }

  Future<void> close() => _closeFuture ??= () async {
        _persistTimer?.cancel();
        debt = debt || !sessionClean || !controllerRetired || !playerTerminated;
        record('final-report', {'cleanupDebt': debt});
        _finalElapsedMicros = elapsedMicros;
        _clock.stop();
        closed = true;
        await persist();
        await _writeTail;
      }();
}
