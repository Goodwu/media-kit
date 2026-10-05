import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart' as path_provider;

const androidNativeDvSessionLifecycleMaxSeconds = 900;
const androidNativeDvSessionLifecycleMaxRows = 300;
const androidNativeDvSessionLifecycleMaxSegments = 24;
const androidNativeDvSessionLifecycleMaxActions = 128;
const androidNativeDvSessionLifecycleMaxRouteHistory = 48;
const androidNativeDvSessionLifecycleP5Path =
    '/data/local/tmp/media-kit-lg-dv-p5-2160p.mp4';
const androidNativeDvSessionLifecycleP5ExpectedSha256 =
    'dacfd04518accd6367530b650dfeea429227df2be171bd99b4bdad36d31bbf9f';
const androidNativeDvSessionLifecycleSdrPath =
    '/data/local/tmp/media-kit-sdr-control.mp4';
const androidNativeDvSessionLifecycleSdrExpectedSha256 =
    '664ad7d5f38db11266a4ee8b9ce650d989548901531d85193d01d1d09f101c44';

const androidNativeDvSessionLifecycleActions = <String>[
  'close-and-exit',
  'Pause10Resume',
  'ManualResume',
  'Seek90Then30',
  'Reopen40Then10',
  'P5SDRP5',
  'RestoreSurface',
  'FullscreenRoundTrip',
  'RecreateSession',
];

/// Canonical representation shared with the external collector. Hash the
/// returned UTF-8 bytes directly; collectors must not re-encode JSON.
String canonicalizeAndroidNativeDvPublicationPayload(Object? value) {
  Object? sorted(Object? item) {
    if (item == null || item is String || item is bool || item is int) {
      return item;
    }
    if (item is List) return item.map(sorted).toList(growable: false);
    if (item is Map) {
      final keys = item.keys.toList(growable: false);
      if (keys.any((key) => key is! String)) {
        throw ArgumentError('Canonical payload map keys must be strings');
      }
      keys.sort((a, b) => (a as String).compareTo(b as String));
      return <String, Object?>{
        for (final key in keys) key as String: sorted(item[key]),
      };
    }
    throw ArgumentError(
        'Unsupported canonical payload value: ${item.runtimeType}');
  }

  return jsonEncode(sorted(value));
}

String sha256AndroidNativeDvPublicationPayload(String canonicalJson) =>
    crypto.sha256.convert(utf8.encode(canonicalJson)).toString();

/// Drains asynchronous preparation, then rechecks the original run admission
/// immediately before a page-owned side effect such as a fullscreen toggle.
Future<void> runAndroidNativeDvAdmittedSideEffect({
  required AndroidNativeDvSessionLifecycleRun run,
  required String actionId,
  required String requestId,
  required String operation,
  required Future<void> Function() prepare,
  required Future<void> Function() sideEffect,
}) async {
  await prepare();
  run.ensureActionSideEffectAllowed(
    actionId: actionId,
    requestId: requestId,
    operation: operation,
  );
  await sideEffect();
}

/// The current page-owned playback state, read again after action publication.
/// This is admission evidence, not a claim about visible frames or smoothness.
class AndroidNativeDvManualResumeState {
  const AndroidNativeDvManualResumeState({
    required this.session,
    required this.sessionInstanceId,
    required this.startupAccepted,
    required this.playing,
    required this.completed,
    required this.buffering,
    required this.position,
  });

  final Object? session;
  final String sessionInstanceId;
  final bool startupAccepted;
  final bool playing;
  final bool completed;
  final bool buffering;
  final Duration position;

  bool get canResume =>
      startupAccepted &&
      session != null &&
      !playing &&
      !completed &&
      !buffering;

  bool sameSession(AndroidNativeDvManualResumeState other) =>
      session != null &&
      identical(session, other.session) &&
      sessionInstanceId == other.sessionInstanceId;
}

/// Uses the existing run and page action drain. There is one play call and no
/// seek, reopen, retry, or independent deadline. The observer uses the page's
/// existing delay; endpoint position advancement supports device observation.
Future<Map<String, Object?>> runAndroidNativeDvManualResume({
  required AndroidNativeDvSessionLifecycleRun run,
  required String requestId,
  required AndroidNativeDvManualResumeState expected,
  required AndroidNativeDvManualResumeState Function() readState,
  required Future<void> Function() play,
  required Future<void> Function(Duration duration) observePlayback,
}) async {
  const observationDuration = Duration(seconds: 10);
  run.ensureActionSideEffectAllowed(
    actionId: 'ManualResume',
    requestId: requestId,
    operation: 'manual-resume-play',
  );
  final before = readState();
  if (!before.canResume || !before.sameSession(expected)) {
    throw StateError('Manual resume requires the same accepted paused Session');
  }
  if (run.remaining < observationDuration) {
    throw TimeoutException(
        'No run budget remains for manual resume observation');
  }
  await play();
  await observePlayback(observationDuration);
  run.ensureActionSideEffectAllowed(
    actionId: 'ManualResume',
    requestId: requestId,
    operation: 'manual-resume-observed',
  );
  final after = readState();
  if (!after.sameSession(before) ||
      !after.startupAccepted ||
      !after.playing ||
      after.completed ||
      after.buffering ||
      after.position <= before.position) {
    throw StateError('Manual resume did not retain advancing Session playback');
  }
  return <String, Object?>{
    'sessionInstanceId': after.sessionInstanceId,
    'requestedObservationMs': observationDuration.inMilliseconds,
    'beforePositionMs': before.position.inMilliseconds,
    'afterPositionMs': after.position.inMilliseconds,
    'positionAdvanced': true,
    'observationScope': 'playback-state-endpoints; visible-frames-unverified',
  };
}

int validateAndroidNativeDvSessionLifecycleSeconds(int value) {
  if (value < 1 || value > androidNativeDvSessionLifecycleMaxSeconds) {
    throw RangeError.range(value, 1, androidNativeDvSessionLifecycleMaxSeconds);
  }
  return value;
}

class AndroidNativeDvSessionLifecycleRun {
  AndroidNativeDvSessionLifecycleRun({
    required int durationSeconds,
    required this.externalIdentityLabel,
    this.writeOverride,
  }) : durationSeconds =
            validateAndroidNativeDvSessionLifecycleSeconds(durationSeconds);

  final int durationSeconds;
  final String externalIdentityLabel;
  @visibleForTesting
  final Future<void> Function(Map<String, Object?> report)? writeOverride;
  final String runId = '${DateTime.now().toUtc().microsecondsSinceEpoch}-'
      '${identityHashCode(Object())}';
  final String startUtc = DateTime.now().toUtc().toIso8601String();
  final Stopwatch _clock = Stopwatch()..start();
  final ValueNotifier<String> status = ValueNotifier<String>('preparing');
  final List<Map<String, Object?>> segments = <Map<String, Object?>>[];
  final List<Map<String, Object?>> rows = <Map<String, Object?>>[];
  final List<Map<String, Object?>> actionEvents = <Map<String, Object?>>[];
  final List<Map<String, Object?>> routeAppliedHistory =
      <Map<String, Object?>>[];
  final List<Map<String, Object?>> consumerProofHistory =
      <Map<String, Object?>>[];
  final Map<String, Object?> enabledActions = <String, Object?>{};
  final AndroidNativeDvSessionLifecycleWriteQueue _writes =
      AndroidNativeDvSessionLifecycleWriteQueue();
  Directory? _directory;
  File? _latestFile;
  File? _archiveFile;
  bool _busy = false;
  bool _startupAttempted = false;
  bool _closing = false;
  bool _closed = false;
  bool _terminal = false;
  bool _debt = false;
  String _cleanupStatus = 'pending';
  String? _lastError;
  String? _currentActionId;
  String? _currentRequestId;
  Map<String, Object?>? _initialIdleBaseline;
  Completer<void>? _activeActionSettled;
  Future<void>? _closeFuture;
  Duration? _finalElapsed;
  Map<String, Object?>? _currentSegment;
  int _externalEventSequence = 0;

  Duration get elapsed => _finalElapsed ?? _clock.elapsed;
  Duration get remaining => Duration(seconds: durationSeconds) - elapsed;
  bool get busy => _busy;
  // Admission closes before the final snapshot write; await close() to prove
  // final report completion. This flag alone is not persistence evidence.
  bool get closed => _closed;
  bool get terminal => _terminal;
  bool get debt => _debt;
  String? get currentActionId => _currentActionId;
  String? get currentRequestId => _currentRequestId;

  Future<void> prepare() async {
    if (writeOverride != null) {
      status.value = 'ready · run=$runId';
      await writeNow();
      return;
    }
    final root = await path_provider.getExternalStorageDirectory();
    if (root == null) {
      throw StateError('App external files directory unavailable');
    }
    _directory = Directory('${root.path}/media-kit-hdr-diagnostic');
    await _directory!.create(recursive: true);
    _latestFile = File('${_directory!.path}/native-dv-session-diagnostic.json');
    final archive = Directory('${_directory!.path}/lifecycle');
    await archive.create(recursive: true);
    _archiveFile = File('${archive.path}/$runId.json');
    status.value = 'ready · run=$runId';
    await writeNow();
  }

  Map<String, Object?> get enabledActionsJson =>
      Map<String, Object?>.unmodifiable(enabledActions);

  void setActionEnabled(String actionId, bool enabled, {String? reason}) {
    if (_closing || _closed) return;
    if (!androidNativeDvSessionLifecycleActions.contains(actionId)) {
      throw ArgumentError.value(actionId, 'actionId');
    }
    enabledActions[actionId] = <String, Object?>{
      'available': enabled,
      'enabled': enabled && !_busy && !_closed && !_debt && !_terminal,
      'reason': reason,
    };
    scheduleWrite();
  }

  Future<void> runStartup({
    required String requestId,
    required Future<void> Function() action,
  }) async {
    if (_startupAttempted ||
        _busy ||
        _closing ||
        _closed ||
        _terminal ||
        _debt ||
        actionEvents.isNotEmpty ||
        requestId.isEmpty) {
      throw StateError('Initial startup admission is closed');
    }
    _startupAttempted = true;
    _busy = true;
    _currentActionId = 'startup';
    _currentRequestId = requestId;
    final settled = Completer<void>();
    _activeActionSettled = settled;
    _refreshEnabledActions();
    try {
      ensureActionSideEffectAllowed(
          actionId: 'startup',
          requestId: requestId,
          operation: 'initial-startup');
      await action();
      ensureActionSideEffectAllowed(
          actionId: 'startup',
          requestId: requestId,
          operation: 'accept-startup');
    } catch (error) {
      markDebt('Initial startup failed: $error');
      rethrow;
    } finally {
      _busy = false;
      _currentActionId = null;
      _currentRequestId = null;
      _activeActionSettled = null;
      _refreshEnabledActions();
      if (!settled.isCompleted) settled.complete();
    }
  }

  Future<void> runAction({
    required String actionId,
    required String requestId,
    required Future<void> Function(AndroidNativeDvSessionLifecycleRun run)
        action,
  }) async {
    if (_closing || _closed || _terminal) {
      throw StateError('Lifecycle run is closed');
    }
    if (_debt) throw StateError('Cleanup debt blocks lifecycle actions');
    if (_busy) throw StateError('Another lifecycle action is active');
    if (!androidNativeDvSessionLifecycleActions.contains(actionId)) {
      throw ArgumentError.value(actionId, 'actionId');
    }
    if (remaining <= Duration.zero) {
      _terminal = true;
      status.value = 'deadline · terminal';
      await writeNow();
      throw TimeoutException('Lifecycle run deadline reached');
    }
    final actionState = enabledActions[actionId];
    if (actionState is! Map || actionState['enabled'] != true) {
      throw StateError('Action is disabled: $actionId');
    }
    if (actionEvents.length >= androidNativeDvSessionLifecycleMaxActions) {
      _debt = true;
      _terminal = true;
      status.value = 'debt · action history limit reached';
      try {
        await writeNow();
      } catch (_) {}
      throw StateError('Lifecycle action history bound reached');
    }
    _busy = true;
    final actionSettled = Completer<void>();
    _activeActionSettled = actionSettled;
    _currentActionId = actionId;
    _currentRequestId = requestId;
    _refreshEnabledActions();
    final event = <String, Object?>{
      'index': actionEvents.length,
      'actionId': actionId,
      'requestId': requestId,
      'sessionInstanceId': null,
      'phase': 'begin',
      'elapsedMs': elapsed.inMilliseconds,
      'expectedSource': null,
      'requestedStartMs': null,
      'requestedPlay': null,
      'lifecycle': null,
      'error': null,
    };
    final rootEventIndex = actionEvents.length;
    _addBounded(actionEvents, event, androidNativeDvSessionLifecycleMaxActions);
    status.value = 'busy · $actionId · $requestId';
    try {
      await writeNow();
    } catch (ackError, ackStack) {
      final stored = Map<String, Object?>.from(actionEvents.last);
      stored['phase'] = 'ackError';
      stored['error'] = '$ackError';
      stored['elapsedEndMs'] = elapsed.inMilliseconds;
      actionEvents[actionEvents.length - 1] =
          Map<String, Object?>.unmodifiable(stored);
      _debt = true;
      _terminal = true;
      _busy = false;
      _currentActionId = null;
      _currentRequestId = null;
      _refreshEnabledActions();
      status.value = 'debt · action ACK write failed';
      try {
        await writeNow();
      } catch (_) {}
      _activeActionSettled = null;
      if (!actionSettled.isCompleted) actionSettled.complete();
      Error.throwWithStackTrace(ackError, ackStack);
    }
    if (_closing || _closed) {
      final rejected = Map<String, Object?>.from(actionEvents[rootEventIndex]);
      rejected['phase'] = 'closedBeforeAction';
      rejected['error'] = 'Close began while writing action ACK';
      actionEvents[rootEventIndex] =
          Map<String, Object?>.unmodifiable(rejected);
      _busy = false;
      _currentActionId = null;
      _currentRequestId = null;
      try {
        await writeNow();
      } catch (_) {}
      _activeActionSettled = null;
      if (!actionSettled.isCompleted) actionSettled.complete();
      throw StateError('Close began before action side effects were admitted');
    }
    if (remaining <= Duration.zero) {
      final rejected = Map<String, Object?>.from(actionEvents[rootEventIndex]);
      rejected['phase'] = 'deadlineRejected';
      rejected['error'] = 'Original deadline elapsed while writing ACK';
      actionEvents[rootEventIndex] =
          Map<String, Object?>.unmodifiable(rejected);
      _debt = true;
      _terminal = true;
      _busy = false;
      _currentActionId = null;
      _currentRequestId = null;
      status.value = 'debt · late action ACK';
      try {
        await writeNow();
      } catch (_) {}
      _activeActionSettled = null;
      if (!actionSettled.isCompleted) actionSettled.complete();
      throw TimeoutException('Lifecycle deadline expired after action ACK');
    }
    Object? error;
    StackTrace? errorStack;
    if (_closing || _closed) {
      error =
          StateError('Close began before action side effects were admitted');
      errorStack = StackTrace.current;
      final closedEvent =
          Map<String, Object?>.from(actionEvents[rootEventIndex]);
      closedEvent['phase'] = 'closedBeforeAction';
      closedEvent['error'] = '$error';
      actionEvents[rootEventIndex] =
          Map<String, Object?>.unmodifiable(closedEvent);
    } else if (remaining <= Duration.zero) {
      error = TimeoutException('Lifecycle deadline expired after action ACK');
      errorStack = StackTrace.current;
      _terminal = true;
      event['phase'] = 'deadlineRejected';
    } else {
      try {
        await action(this);
      } catch (value) {
        error = value;
        errorStack = StackTrace.current;
        _debt = true;
        _terminal = true;
      }
    }
    if (error == null && _debt) {
      error = StateError('Action completed with lifecycle debt');
      errorStack = StackTrace.current;
    } else if (error == null && _terminal && !_closing) {
      error = StateError('Run became terminal before action acceptance');
      errorStack = StackTrace.current;
    }
    if (error != null && event['phase'] != 'closedBeforeAction') {
      _debt = true;
      _terminal = true;
    }
    if (error == null && remaining <= Duration.zero) {
      error = TimeoutException('Lifecycle deadline expired before action end');
      errorStack = StackTrace.current;
      _debt = true;
      _terminal = true;
    }
    try {
      final stored = Map<String, Object?>.from(actionEvents[rootEventIndex]);
      stored['phase'] = error == null ? 'end-provisional' : 'error';
      stored['error'] = error == null ? null : '$error';
      stored['elapsedEndMs'] = elapsed.inMilliseconds;
      if (error == null && !_closed) {
        final publicationId =
            '$runId-${stored['index']}-${++_externalEventSequence}';
        final deadlineElapsedUs =
            durationSeconds * Duration.microsecondsPerSecond;
        final provisionalEvent = <String, Object?>{
          'index': stored['index'],
          'actionId': actionId,
          'requestId': requestId,
          'sessionInstanceId': stored['sessionInstanceId'],
          'phase': 'end-provisional',
          'elapsedMs': stored['elapsedMs'],
          'elapsedEndMs': stored['elapsedEndMs'],
          'expectedSource': stored['expectedSource'],
          'requestedStartMs': stored['requestedStartMs'],
          'requestedPlay': stored['requestedPlay'],
          'lifecycle': stored['lifecycle'],
          'error': null,
        };
        final provisionalPayload = <String, Object?>{
          'runId': runId,
          'externalIdentityLabel': externalIdentityLabel,
          'requestId': requestId,
          'actionId': actionId,
          'publicationId': publicationId,
          'phase': 'end-provisional',
          'deadlineElapsedUs': deadlineElapsedUs,
          'actionEvent': provisionalEvent,
        };
        final canonicalJson =
            canonicalizeAndroidNativeDvPublicationPayload(provisionalPayload);
        final payloadSha256 =
            sha256AndroidNativeDvPublicationPayload(canonicalJson);
        stored['publicationId'] = publicationId;
        stored['deadlineElapsedUs'] = deadlineElapsedUs;
        stored['provisionalPayload'] = provisionalPayload;
        stored['canonicalization'] = 'sorted-key-json-utf8-v1';
        stored['provisionalPayloadCanonicalJson'] = canonicalJson;
        stored['provisionalPayloadSha256'] = payloadSha256;
      }
      actionEvents[rootEventIndex] = Map<String, Object?>.unmodifiable(stored);
      if (error == null && !_closed) {
        // This write publishes the provisional payload to both archive and
        // latest. Its successful completion is the conservative upper bound
        // used by the receipt; the receipt write itself has no timely claim.
        await writeNow(requireArchive: true);
        final payloadPublishCompletedUpperBoundUs =
            _clock.elapsed.inMicroseconds;
        final deadlineElapsedUs =
            durationSeconds * Duration.microsecondsPerSecond;
        if (payloadPublishCompletedUpperBoundUs >= deadlineElapsedUs ||
            _closed) {
          error = TimeoutException(
              'Provisional action payload was published after its original deadline');
          errorStack = StackTrace.current;
          _debt = true;
          _terminal = true;
          final rejected =
              Map<String, Object?>.from(actionEvents[rootEventIndex]);
          rejected['phase'] = 'deadlineRejected';
          rejected['error'] = '$error';
          rejected.remove('publicationReceipt');
          actionEvents[rootEventIndex] =
              Map<String, Object?>.unmodifiable(rejected);
        } else {
          final accepted =
              Map<String, Object?>.from(actionEvents[rootEventIndex]);
          accepted['phase'] = 'end-certified';
          accepted['publicationReceipt'] = <String, Object?>{
            'publicationId': accepted['publicationId'],
            'payloadSha256': accepted['provisionalPayloadSha256'],
            'scope': 'action-and-provisional-payload',
            'payloadPublishCompletedUpperBoundElapsedUs':
                payloadPublishCompletedUpperBoundUs,
            'deadlineElapsedUs': deadlineElapsedUs,
            'receiptPublicationWithinDeadline': 'unverified',
          };
          actionEvents[rootEventIndex] =
              Map<String, Object?>.unmodifiable(accepted);
        }
      }
    } catch (writeError, writeStack) {
      _debt = true;
      _terminal = true;
      error ??= writeError;
      errorStack ??= writeStack;
    } finally {
      final stored = Map<String, Object?>.from(actionEvents[rootEventIndex]);
      if (error != null) {
        stored['phase'] = stored['phase'] == 'closedBeforeAction'
            ? 'closedBeforeAction'
            : stored['phase'] == 'deadlineRejected' ||
                    (error is TimeoutException && remaining <= Duration.zero)
                ? 'deadlineRejected'
                : 'error';
        stored['error'] = '$error';
      }
      _busy = false;
      _currentActionId = null;
      _currentRequestId = null;
      if (error != null) {
        stored['phase'] = stored['phase'] == 'closedBeforeAction'
            ? 'closedBeforeAction'
            : stored['phase'] == 'deadlineRejected' ||
                    (error is TimeoutException && remaining <= Duration.zero)
                ? 'deadlineRejected'
                : 'error';
        stored['error'] = '$error';
      }
      actionEvents[rootEventIndex] = Map<String, Object?>.unmodifiable(stored);
      status.value = error == null
          ? 'ready · ${rows.length} rows · ${segments.length} segments'
          : 'debt · $actionId · $error';
      try {
        if (error == null &&
            actionEvents[rootEventIndex]['phase'] == 'end-certified') {
          await _writes.enqueue(_writeLatestSnapshot);
        } else {
          await writeNow();
        }
      } catch (writeError, writeStack) {
        _debt = true;
        _terminal = true;
        status.value = 'debt · final action report write failed';
        final failedWrite =
            Map<String, Object?>.from(actionEvents[rootEventIndex]);
        failedWrite['phase'] = error == null ? 'reportError' : 'error';
        failedWrite['reportWriteError'] = '$writeError';
        failedWrite.remove('publicationReceipt');
        actionEvents[rootEventIndex] =
            Map<String, Object?>.unmodifiable(failedWrite);
        if (error == null) {
          error = writeError;
          errorStack = writeStack;
        }
        try {
          await writeNow();
        } catch (_) {}
      }
      _activeActionSettled = null;
      if (!actionSettled.isCompleted) actionSettled.complete();
    }
    if (error != null) {
      Error.throwWithStackTrace(error, errorStack ?? StackTrace.current);
    }
  }

  Future<void> recordStep({
    required String actionId,
    required String requestId,
    required String stepId,
    required String phase,
    String? sessionInstanceId,
    String? expectedSource,
    Duration? requestedStart,
    bool? requestedPlay,
    String? lifecycle,
    Object? error,
    Map<String, Object?>? facts,
  }) async {
    if (_closed || (!_busy && _closing) || remaining <= Duration.zero) {
      throw TimeoutException('Lifecycle run no longer accepts action steps');
    }
    try {
      _addBounded(
          actionEvents,
          <String, Object?>{
            'index': actionEvents.length,
            'actionId': actionId,
            'requestId': requestId,
            'stepId': stepId,
            'sessionInstanceId': sessionInstanceId,
            'phase': phase,
            'elapsedMs': elapsed.inMilliseconds,
            'expectedSource': expectedSource,
            'requestedStartMs': requestedStart?.inMilliseconds,
            'requestedPlay': requestedPlay,
            'lifecycle': lifecycle,
            'error': error == null ? null : '$error',
            if (facts != null) 'facts': facts,
          },
          androidNativeDvSessionLifecycleMaxActions);
    } on StateError catch (error) {
      markDebt('lifecycle action history overflow: $error');
      return;
    }
    await writeNow();
    if (remaining <= Duration.zero || _closed) {
      final index = actionEvents.lastIndexWhere((event) =>
          event['actionId'] == actionId &&
          event['requestId'] == requestId &&
          event['stepId'] == stepId);
      if (index >= 0) {
        final late = Map<String, Object?>.from(actionEvents[index]);
        late['phase'] = 'deadlineRejected';
        late['error'] = 'original run deadline elapsed during step write';
        actionEvents[index] = Map<String, Object?>.unmodifiable(late);
      }
      _terminal = true;
      _debt = true;
      status.value = 'debt · late lifecycle step $stepId';
      try {
        await writeNow();
      } catch (_) {}
      throw TimeoutException('Step $stepId was not accepted before deadline');
    }
  }

  void ensureActionSideEffectAllowed({
    required String actionId,
    required String requestId,
    required String operation,
  }) {
    if (!_busy ||
        _currentActionId != actionId ||
        _currentRequestId != requestId ||
        _closing ||
        _closed ||
        _debt ||
        _terminal) {
      throw StateError('Action admission closed before $operation');
    }
    if (remaining <= Duration.zero) {
      _debt = true;
      _terminal = true;
      status.value = 'debt · deadline before $operation';
      scheduleWrite();
      throw TimeoutException('Original run deadline reached before $operation');
    }
  }

  void recordExternalLifecycleState({
    required String state,
    required int positionMs,
    required bool playing,
    required bool completed,
    required bool buffering,
  }) {
    if (_closed || remaining <= Duration.zero) return;
    _addBounded(
        actionEvents,
        <String, Object?>{
          'index': actionEvents.length,
          'actionId': null,
          'requestId': 'lifecycle-${++_externalEventSequence}',
          'stepId': 'app-lifecycle',
          'sessionInstanceId': null,
          'phase': 'observed',
          'elapsedMs': elapsed.inMilliseconds,
          'lifecycle': state,
          'playerState': <String, Object?>{
            'positionMs': positionMs,
            'playing': playing,
            'completed': completed,
            'buffering': buffering,
          },
        },
        androidNativeDvSessionLifecycleMaxActions);
    scheduleWrite();
  }

  void recordInitialIdleBaseline({
    required Map<String, String> properties,
    required int fileLoadedEpoch,
  }) {
    if (_initialIdleBaseline != null || _closed || _closing) {
      throw StateError('Initial idle baseline is immutable');
    }
    _initialIdleBaseline = <String, Object?>{
      'properties': Map<String, String>.unmodifiable(properties),
      'fileLoadedEpoch': fileLoadedEpoch,
      'observedElapsedMs': elapsed.inMilliseconds,
      'proof': 'captured-under-Player.lock-before-Session',
    };
    scheduleWrite();
  }

  Map<String, Object?> beginSegment({
    required String segmentId,
    required String sessionInstanceId,
    required int generation,
    required String expectedSource,
    required String route,
    required String actionId,
    required String requestId,
    Map<String, Object?>? consumerValidated,
    required Map<String, Object?> routeApplied,
  }) {
    if (_closed || remaining <= Duration.zero) {
      throw TimeoutException('Lifecycle run no longer accepts segments');
    }
    if (segments.length >= androidNativeDvSessionLifecycleMaxSegments) {
      throw StateError('Lifecycle segment bound reached');
    }
    final segment = <String, Object?>{
      'segmentId': segmentId,
      'sessionInstanceId': sessionInstanceId,
      'generation': generation,
      'expectedSource': expectedSource,
      'route': route,
      'actionId': actionId,
      'requestId': requestId,
      'consumerValidated': consumerValidated,
      'routeApplied': routeApplied,
      'accepted': true,
      'phase': 'sampling',
      'startedElapsedMs': elapsed.inMilliseconds,
      'endedElapsedMs': null,
      'endReason': null,
      'initialIdentity': null,
      'surfaceTuple': null,
      'rowCount': 0,
      'error': null,
    };
    segments.add(segment);
    _currentSegment = segment;
    if (!_terminal && !_debt) _cleanupStatus = 'pending';
    return segment;
  }

  void closeSegment(String reason, {Object? error, bool abandoned = false}) {
    final segment = _currentSegment;
    if (segment == null || segment['endedElapsedMs'] != null) return;
    segment['endedElapsedMs'] = elapsed.inMilliseconds;
    segment['endReason'] = reason;
    segment['phase'] = abandoned ? 'abandoned' : 'ended';
    segment['accepted'] = !abandoned;
    segment['error'] = error == null ? null : '$error';
    _currentSegment = null;
    scheduleWrite();
  }

  void recordConsumerProof(Map<String, Object?> proof) {
    _addBounded(consumerProofHistory, proof,
        androidNativeDvSessionLifecycleMaxRouteHistory);
    scheduleWrite();
  }

  void updateConsumerProofStatus({
    required String sessionInstanceId,
    required int generation,
    required String status,
    String? reason,
  }) {
    final index = consumerProofHistory.lastIndexWhere(
      (proof) =>
          proof['sessionInstanceId'] == sessionInstanceId &&
          proof['generation'] == generation,
    );
    if (index < 0) return;
    final value = Map<String, Object?>.from(consumerProofHistory[index]);
    if (value['status'] != 'pending') return;
    value['status'] = status;
    value['statusReason'] = reason;
    consumerProofHistory[index] = Map<String, Object?>.unmodifiable(value);
    scheduleWrite();
  }

  void recordRouteApplied(Map<String, Object?> applied) {
    _addBounded(routeAppliedHistory, applied,
        androidNativeDvSessionLifecycleMaxRouteHistory);
    scheduleWrite();
  }

  bool appendRow(Map<String, Object?> row) {
    final segment = _currentSegment;
    if (segment == null || _closed || remaining <= Duration.zero) return false;
    if (rows.length >= androidNativeDvSessionLifecycleMaxRows) {
      _terminal = true;
      _refreshEnabledActions();
      closeSegment('row-limit');
      status.value = 'terminal · row limit reached';
      scheduleWrite();
      return false;
    }
    final value = <String, Object?>{
      ...row,
      'index': rows.length,
      'segmentId': segment['segmentId'],
    };
    rows.add(value);
    segment['rowCount'] = (segment['rowCount'] as int) + 1;
    if (!_busy) status.value = 'sampling · ${rows.length} rows';
    scheduleWrite();
    return true;
  }

  void markSegmentIdentity({
    required Map<String, Object?> identity,
    required Map<String, Object?> outputBinding,
  }) {
    final segment = _currentSegment;
    if (segment == null) return;
    segment['initialIdentity'] ??= identity;
    segment['outputBinding'] ??= outputBinding;
    if (outputBinding['kind'] == 'android-platform-view') {
      segment['surfaceTuple'] ??= outputBinding['surfaceTuple'];
    }
  }

  void markSegmentError(Object error) {
    closeSegment('identity-or-sampling-error', error: error);
    _debt = true;
    _terminal = true;
    status.value = 'debt · $error';
    scheduleWrite();
  }

  void markSessionDisposed({
    required String sessionInstanceId,
    required bool clean,
    required Object? report,
    required Map<String, Object?>? restoredProperties,
  }) {
    final segment = _currentSegment;
    if (segment != null && segment['sessionInstanceId'] == sessionInstanceId) {
      closeSegment('session-disposed');
    }
    _addBounded(
        actionEvents,
        <String, Object?>{
          'index': actionEvents.length,
          'actionId': _currentActionId,
          'requestId': _currentRequestId,
          'stepId': 'session-disposal-proof',
          'sessionInstanceId': sessionInstanceId,
          'phase': clean ? 'completed' : 'debt',
          'elapsedMs': elapsed.inMilliseconds,
          'disposeReport': report,
          'restoredProperties': restoredProperties,
          'surfaceReleaseAcknowledgement': 'not independently observable',
        },
        androidNativeDvSessionLifecycleMaxActions);
    if (!clean) {
      _debt = true;
      _terminal = true;
      _cleanupStatus = 'terminated-with-debt';
      _refreshEnabledActions();
    } else {
      _cleanupStatus =
          'session-restored; player-active; surface-release-unverified';
    }
    scheduleWrite();
  }

  void markPlayerTerminated({required bool success}) {
    if (!success) {
      _debt = true;
      _terminal = true;
      _cleanupStatus = 'terminated-with-debt';
      status.value = 'debt · player termination failed';
      _refreshEnabledActions();
    } else if (!_debt) {
      _cleanupStatus =
          'terminated; session-restore-reported; surface-release-unverified';
    }
    scheduleWrite();
  }

  void markTerminal({String reason = 'explicit-close'}) {
    _terminal = true;
    if (!_debt && _cleanupStatus == 'pending') {
      _cleanupStatus = 'terminal-with-cleanup-unverified';
    }
    closeSegment(reason);
    _refreshEnabledActions();
    scheduleWrite();
  }

  void markDebt(String reason) {
    _lastError = reason;
    _debt = true;
    _terminal = true;
    _cleanupStatus = 'terminated-with-debt';
    _refreshEnabledActions();
    closeSegment('debt', error: reason);
    scheduleWrite();
  }

  void _refreshEnabledActions() {
    enabledActions.updateAll((_, value) {
      final map =
          value is Map ? Map<String, Object?>.from(value) : <String, Object?>{};
      map['enabled'] = map['available'] == true &&
          !_busy &&
          !_closed &&
          !_debt &&
          !_terminal;
      return map;
    });
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'schema': 2,
        'diagnosticOnly': true,
        'diagnosticRoute': 'session',
        'diagnosticMode': 'lifecycle',
        'phase': _closed ? 'closed' : status.value,
        'error': _lastError,
        'closed': _closed,
        'exitAcknowledgement':
            'unverified; final snapshot precedes SystemNavigator.pop',
        'closeActionEndScope':
            'owned Player termination and final report only; Activity exit unverified',
        'runId': runId,
        'startUtc': startUtc,
        'externalIdentityLabel': externalIdentityLabel,
        'sourcePath': androidNativeDvSessionLifecycleP5Path,
        'expectedAssets': {
          androidNativeDvSessionLifecycleP5Path:
              androidNativeDvSessionLifecycleP5ExpectedSha256,
          androidNativeDvSessionLifecycleSdrPath:
              androidNativeDvSessionLifecycleSdrExpectedSha256,
        },
        'expectedAssetShaSemantics':
            'external identity labels; not app verification',
        'durationLimitSeconds': durationSeconds,
        'elapsedMs': elapsed.inMilliseconds,
        'remainingMs': remaining.inMilliseconds,
        'busy': busy,
        'currentAction': currentActionId == null
            ? null
            : <String, Object?>{
                'actionId': currentActionId,
                'requestId': currentRequestId,
              },
        'enabledActions': enabledActionsJson,
        'terminal': terminal,
        'debt': debt,
        'segments': List<Map<String, Object?>>.unmodifiable(segments),
        'routeAppliedHistory':
            List<Map<String, Object?>>.unmodifiable(routeAppliedHistory),
        'consumerProofHistory':
            List<Map<String, Object?>>.unmodifiable(consumerProofHistory),
        'actionEvents': List<Map<String, Object?>>.unmodifiable(actionEvents),
        'rowCount': rows.length,
        'rows': List<Map<String, Object?>>.unmodifiable(rows),
        'presentationVerified': false,
        'cleanup': _cleanupStatus,
        'initialIdleBaseline': _initialIdleBaseline,
      };

  Future<void> writeNow({bool requireArchive = false}) async {
    if (_closed) throw StateError('Lifecycle report is finalized');
    await _writes.enqueue(() => _writeSnapshot(requireArchive: requireArchive));
  }

  Future<void> _writeSnapshot({bool requireArchive = false}) async {
    final override = writeOverride;
    if (override != null) {
      await override(toJson());
      return;
    }
    final latest = _latestFile;
    final archive = _archiveFile;
    if (latest == null || archive == null) return;
    final json = jsonEncode(toJson());
    final hasCertifiedRootAction = actionEvents.any((event) =>
        !event.containsKey('stepId') && event['phase'] == 'end-certified');
    if (hasCertifiedRootAction && !requireArchive) {
      await _atomicWrite(latest, json);
      return;
    }
    await _atomicWrite(archive, json);
    await _atomicWrite(latest, json);
  }

  Future<void> _writeLatestSnapshot() async {
    final override = writeOverride;
    if (override != null) {
      await override(toJson());
      return;
    }
    final latest = _latestFile;
    if (latest == null) return;
    final json = jsonEncode(toJson());
    await _atomicWrite(latest, json);
  }

  void scheduleWrite() {
    if (_closing || _closed) return;
    _writes.schedule(_writeSnapshot);
  }

  Future<void> flush() => _writes.flush();

  Future<void> close() => _closeFuture ??= _closeOnce();

  Future<void> _closeOnce() async {
    if (_closed) return;
    _closing = true;
    _terminal = true;
    _refreshEnabledActions();
    final active = _activeActionSettled;
    if (active != null) await active.future;
    markTerminal(reason: 'lifecycle-run-closed');
    _finalElapsed = _clock.elapsed;
    _closed = true;
    _refreshEnabledActions();
    await _writes.enqueue(_writeSnapshot);
    await _writes.flush();
    _writes.closeAdmission();
  }

  static void _addBounded(
    List<Map<String, Object?>> target,
    Map<String, Object?> value,
    int max,
  ) {
    if (target.length >= max) {
      throw StateError('Lifecycle history bound reached');
    }
    target.add(Map<String, Object?>.unmodifiable(value));
  }

  static Future<void> _atomicWrite(File file, String contents) async {
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(contents, flush: true);
    await temp.rename(file.path);
  }
}

/// Admission shared by the recorder's routeApplied waiter and its sampler.
/// A route event alone is insufficient: only the recorder can accept this
/// gate after a bound identity/configuration row has been appended.
class AndroidNativeDvSessionAppliedAdmission {
  AndroidNativeDvSessionAppliedAdmission({
    required this.sessionInstanceId,
    required this.generation,
  });

  final String sessionInstanceId;
  final int generation;
  final Completer<Map<String, Object?>> _accepted =
      Completer<Map<String, Object?>>();

  bool get isAccepted => _accepted.isCompleted;

  void fail(Object error, StackTrace stack) {
    if (!_accepted.isCompleted) _accepted.completeError(error, stack);
  }

  void accept(Map<String, Object?> segment) {
    if (_accepted.isCompleted ||
        segment['sessionInstanceId'] != sessionInstanceId ||
        segment['generation'] != generation ||
        segment['accepted'] != true ||
        (segment['rowCount'] as int? ?? 0) < 1 ||
        segment['routeApplied'] is! Map) {
      return;
    }
    _accepted.complete(Map<String, Object?>.from(
        segment['routeApplied'] as Map<String, Object?>));
  }

  Future<Map<String, Object?>> wait({
    required Duration remaining,
    required bool Function() stillAdmissible,
  }) async {
    if (remaining <= Duration.zero || !stillAdmissible()) {
      throw TimeoutException('Lifecycle Applied admission is closed');
    }
    final value = await _accepted.future.timeout(remaining);
    if (!stillAdmissible()) {
      throw StateError('Lifecycle Applied admission expired or became debt');
    }
    return value;
  }
}

/// Production orchestration for close-and-exit. The admitted action performs
/// owned cleanup before its accepted end event. If its ACK fails, termination
/// still runs outside the action; close then drains/finalizes the run before UI
/// exit. Already failed/terminal runs use recovery termination without trying
/// action admission. Original failures remain distinct from cleanup failures.
Future<void> runAndroidNativeDvCloseAndExit({
  required AndroidNativeDvSessionLifecycleRun run,
  required String requestId,
  required Future<void> Function() terminateOwnedPlayer,
  required Future<void> Function() exit,
  required void Function(Object error) reportFailure,
}) async {
  final errors = <Object>[];
  final terminationErrors = <Object>[];
  final originalError = run.toJson()['error'];
  // A failed/terminal run cannot admit an action. Recovery is owned cleanup,
  // not a rejected action or a new successful close certificate.
  final recovering = run.debt || run.terminal;
  var terminationAttempted = false;
  Future<void> terminate() async {
    terminationAttempted = true;
    try {
      await terminateOwnedPlayer();
    } catch (error) {
      terminationErrors.add(error);
      rethrow;
    }
  }

  if (!recovering) {
    try {
      await run.runAction(
        actionId: 'close-and-exit',
        requestId: requestId,
        action: (_) => terminate(),
      );
    } catch (error) {
      errors.add(error);
    }
  }
  if (!terminationAttempted) {
    try {
      await terminate();
    } catch (error) {
      errors.add(error);
    }
  }
  if (errors.isNotEmpty && !run.closed) {
    final failure = StateError(errors.map((error) => '$error').join(' | '));
    final reason = terminationErrors.isNotEmpty
        ? 'Owned termination failed before final report: $failure'
        : 'Close action failed before final report: $failure';
    final currentError = run.toJson()['error'];
    final retainedErrors = <String>{
      if (originalError != null) '$originalError',
      if (currentError != null) '$currentError',
      reason,
    };
    run.markDebt(retainedErrors.join(' | '));
  }
  var finalReportCompleted = false;
  try {
    await run.close();
    finalReportCompleted = true;
  } catch (error) {
    errors.add(StateError('Final lifecycle report completion failed: $error'));
  }
  // closed is set before the final write starts. Only the fulfilled close
  // Future proves that enqueue/flush completed; a write failure retains UI.
  if (finalReportCompleted) {
    try {
      await exit();
    } catch (error) {
      // The immutable final report explicitly says Activity exit is unverified.
      // A pop error is returned to the page/outer observer, never written late.
      errors.add(error);
    }
  }
  if (errors.isNotEmpty) {
    final failure = StateError(errors.map((error) => '$error').join(' | '));
    try {
      reportFailure(failure);
    } catch (_) {}
  }
}

class AndroidNativeDvSessionTerminationResult {
  const AndroidNativeDvSessionTerminationResult({
    required this.recorderCloseError,
    required this.sessionDisposeError,
    required this.cleanupCaptureError,
    required this.playerDisposeError,
    required this.terminationRecordError,
  });

  final Object? recorderCloseError;
  final Object? sessionDisposeError;
  final Object? cleanupCaptureError;
  final Object? playerDisposeError;
  final Object? terminationRecordError;

  bool get clean =>
      recorderCloseError == null &&
      sessionDisposeError == null &&
      cleanupCaptureError == null &&
      playerDisposeError == null &&
      terminationRecordError == null;
}

class AndroidNativeDvSessionTermination {
  static Future<AndroidNativeDvSessionTerminationResult> run({
    required Future<void> Function() closeRecorder,
    required Future<void> Function() disposeSession,
    required Future<void> Function(Object? sessionDisposeError)
        capturePostSession,
    required Future<void> Function(Object error) recordCaptureError,
    required Future<void> Function() disposePlayer,
    required Future<void> Function(Object? playerDisposeError)
        recordPlayerTermination,
    required void Function(String reason) markDebt,
  }) async {
    Object? recorderCloseError;
    Object? sessionDisposeError;
    Object? cleanupCaptureError;
    Object? playerDisposeError;
    Object? terminationRecordError;
    try {
      await closeRecorder();
    } catch (error) {
      recorderCloseError = error;
      try {
        await recordCaptureError(error);
      } catch (recordError) {
        cleanupCaptureError = recordError;
      }
    }
    try {
      await disposeSession();
    } catch (error) {
      sessionDisposeError = error;
    }
    try {
      await capturePostSession(sessionDisposeError);
    } catch (error) {
      cleanupCaptureError ??= error;
      try {
        await recordCaptureError(error);
      } catch (recordError) {
        cleanupCaptureError = '$error; report=$recordError';
      }
    } finally {
      try {
        await disposePlayer();
      } catch (error) {
        playerDisposeError = error;
      }
      try {
        await recordPlayerTermination(playerDisposeError);
      } catch (error) {
        terminationRecordError = error;
      }
    }
    final result = AndroidNativeDvSessionTerminationResult(
      recorderCloseError: recorderCloseError,
      sessionDisposeError: sessionDisposeError,
      cleanupCaptureError: cleanupCaptureError,
      playerDisposeError: playerDisposeError,
      terminationRecordError: terminationRecordError,
    );
    if (!result.clean) {
      markDebt('Session termination has errors: '
          'recorder=$recorderCloseError session=$sessionDisposeError '
          'capture=$cleanupCaptureError player=$playerDisposeError '
          'terminationReport=$terminationRecordError');
    }
    return result;
  }
}

class AndroidNativeDvSessionLifecycleWriteQueue {
  Future<void> _tail = Future<void>.value();
  bool _closing = false;

  void schedule(Future<void> Function() write) {
    if (_closing) return;
    scheduleMicrotask(() {
      if (_closing) return;
      unawaited(enqueue(write).catchError((Object _) {}));
    });
  }

  Future<void> enqueue(Future<void> Function() write) {
    final next = _tail.then((_) => write());
    _tail = next.catchError((Object _) {});
    return next;
  }

  void closeAdmission() => _closing = true;

  Future<void> flush() => _tail;
}
