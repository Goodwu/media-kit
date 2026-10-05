import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/src/hdr/android_mediacodec_configuration.dart';
import 'package:media_kit_video/src/hdr/hdr_native_dv_option_owner.dart';
import 'package:media_kit_video/src/hdr/hdr_native_dv_review_evidence.dart';
import 'package:media_kit_video/src/hdr/hdr_player_backend.dart';
import 'package:media_kit_video/src/video_controller/android_video_controller/android_video_controller.dart';
import 'package:path_provider/path_provider.dart' as path_provider;
import 'package:synchronized/synchronized.dart';

// This isolated lab-only route deliberately composes the same identity-bound
// static helpers used by AndroidHdrBackend; it does not create a second owner.
// ignore_for_file: depend_on_referenced_packages, implementation_imports, invalid_use_of_visible_for_testing_member

const androidNativeDvReleaseDiagnosticMaxRows = 300;
const androidNativeDvReleaseDiagnosticSource =
    '/data/local/tmp/media-kit-lg-dv-p5-2160p.mp4';

int validateAndroidNativeDvReleaseDiagnosticSeconds(int seconds) {
  if (seconds < 1 || seconds > androidNativeDvReleaseDiagnosticMaxRows) {
    throw RangeError.range(
      seconds,
      1,
      androidNativeDvReleaseDiagnosticMaxRows,
      'seconds',
    );
  }
  return seconds;
}

int validateAndroidNativeDvReleaseDiagnosticIntervalSeconds(int seconds) {
  if (seconds < 1 || seconds > 30) {
    throw RangeError.range(seconds, 1, 30, 'intervalSeconds');
  }
  return seconds;
}

bool androidNativeDvDiagnosticDeadlineReached({
  required int elapsedMilliseconds,
  required int durationSeconds,
}) =>
    elapsedMilliseconds >= durationSeconds * 1000;

bool androidNativeDvDiagnosticOwnsTerminalIdentity(
  HdrOptionSourceIdentity expected,
  HdrOptionSourceIdentity actual,
) {
  if (!identical(expected.player, actual.player) ||
      expected.fileLoadedEpoch != actual.fileLoadedEpoch ||
      actual.playlistEntryId != expected.playlistEntryId) {
    return false;
  }
  return actual.path == expected.path || actual.path.isEmpty;
}

Future<HdrOptionSourceIdentity>
    captureAndroidNativeDvDiagnosticInitialBoundary({
  required Lock lock,
  required HdrOptionSourceIdentity expectedIdle,
  required Future<void> Function() stop,
  required Future<HdrOptionSourceIdentity> Function() readIdentity,
}) =>
        AndroidHdrBackend.captureStoppedBoundaryUnderLock(
          lock: lock,
          stopWithoutLock: () async {
            final current = await readIdentity();
            if (current != expectedIdle ||
                current.path.isNotEmpty ||
                current.playlistEntryId.isNotEmpty) {
              throw StateError(
                  'Initial idle source changed before diagnostic stop admission');
            }
            await stop();
          },
          readIdentity: readIdentity,
        );

Future<void> restoreAndroidNativeDvDiagnosticOptionsUnderLock({
  required Lock lock,
  required HdrNativeDvOptionOwner options,
}) =>
    lock.synchronized(options.restore);

class AndroidNativeDvDiagnosticPageAdmission<T> {
  bool _closed = false;

  bool get isOpen => !_closed;

  void close() => _closed = true;

  Future<R?> createAfterReady<R>({
    required Future<T> output,
    required Future<void> Function(T) waitUntilReady,
    required bool Function() pageIsAlive,
    required R Function(T) create,
  }) async {
    if (_closed || !pageIsAlive()) return null;
    final value = await output;
    if (_closed || !pageIsAlive()) return null;
    await waitUntilReady(value);
    if (_closed || !pageIsAlive()) return null;
    return create(value);
  }
}

Future<bool> publishAndroidNativeDvDiagnosticResourcesAfterReport({
  required Future<void> initialReport,
  required bool Function() canPublish,
  required void Function() publish,
}) async {
  await initialReport;
  if (!canPublish()) return false;
  publish();
  return true;
}

Duration androidNativeDvDiagnosticPropertyReadTimeout({
  required Duration? remainingBudget,
  Duration maxWait = const Duration(seconds: 3),
}) {
  if (remainingBudget == null) return maxWait;
  if (remainingBudget <= Duration.zero) {
    throw const AndroidNativeDvDiagnosticSamplingDeadline();
  }
  return remainingBudget < maxWait ? remainingBudget : maxWait;
}

AndroidNativeDvDiagnosticSampleRead<T> admitAndroidNativeDvDiagnosticRead<T>({
  required Duration? remainingBudget,
  required Future<T> Function() startNativeRead,
}) {
  final timeout = androidNativeDvDiagnosticPropertyReadTimeout(
    remainingBudget: remainingBudget,
  );
  // Do not move this call above the deadline check: it starts the native op.
  final operation = startNativeRead();
  return AndroidNativeDvDiagnosticSampleRead<T>(
    operation: operation,
    bounded: operation.timeout(timeout),
  );
}

class AndroidNativeDvDiagnosticSampleRead<T> {
  const AndroidNativeDvDiagnosticSampleRead({
    required this.operation,
    required this.bounded,
  });

  final Future<T> operation;
  final Future<T> bounded;
}

class AndroidNativeDvDiagnosticSamplingDeadline implements Exception {
  const AndroidNativeDvDiagnosticSamplingDeadline();

  @override
  String toString() => 'Sampling wall-clock deadline reached';
}

bool androidNativeDvDiagnosticShouldRetryTerminalSample({
  required bool terminalObserved,
  required bool terminalRowWritten,
  required bool sampleFailed,
  required bool closed,
}) =>
    terminalObserved && !terminalRowWritten && !sampleFailed && !closed;

/// Serializes lab-page disposal behind an in-flight startup attempt. Startup
/// failures are preserved by the diagnostic state; shutdown still runs so an
/// already-begun owner or captured open can be recovered.
Future<void> awaitAndroidNativeDvDiagnosticStartSettled(
  Future<void>? startFuture,
) async {
  if (startFuture != null) {
    try {
      await startFuture;
    } catch (_) {
      // Startup reports the failure itself. Cleanup must still run afterward.
    }
  }
}

/// Small bounded row store used by the Release diagnostic and its tests.
class AndroidNativeDvDiagnosticRows<T> {
  AndroidNativeDvDiagnosticRows(
      {this.limit = androidNativeDvReleaseDiagnosticMaxRows}) {
    if (limit < 1 || limit > androidNativeDvReleaseDiagnosticMaxRows) {
      throw RangeError.range(limit, 1, androidNativeDvReleaseDiagnosticMaxRows);
    }
  }

  final int limit;
  final List<T> _rows = <T>[];

  int get length => _rows.length;
  List<T> get values => List<T>.unmodifiable(_rows);

  void add(T value) {
    if (_rows.length == limit) return;
    _rows.add(value);
  }
}

Future<void> writeAndroidNativeDvDiagnosticJsonAtomically(
  File output,
  Map<String, Object?> value,
) async {
  final temporary = File('${output.path}.tmp');
  await temporary.writeAsString(jsonEncode(value), flush: true);
  await temporary.rename(output.path);
}

/// Release-only, fixed-source native DV diagnostic for hdr_lab.
/// This owns configuration facts and a bounded report, not display acceptance.
class AndroidNativeDvReleaseDiagnostic {
  AndroidNativeDvReleaseDiagnostic({
    required this.player,
    required this.outputController,
    required int durationSeconds,
    required int sampleIntervalSeconds,
    required this.externalIdentityLabel,
  })  : durationSeconds =
            validateAndroidNativeDvReleaseDiagnosticSeconds(durationSeconds),
        sampleIntervalSeconds =
            validateAndroidNativeDvReleaseDiagnosticIntervalSeconds(
                sampleIntervalSeconds) {
    _options = HdrNativeDvOptionOwner(
      readProperty: _readProperty,
      setPropertyStrict: (name, value) => player.setPropertyStrict(
        name,
        value,
        waitForInitialization: false,
      ),
      readIdentity: _readIdentity,
    );
  }

  final Player player;
  final AndroidVideoController outputController;
  final int durationSeconds;
  final int sampleIntervalSeconds;

  /// A caller-supplied label only. APK and source hashes must be bound by the
  /// external evidence script; this class does not claim to verify them.
  final String externalIdentityLabel;

  late final HdrNativeDvOptionOwner _options;
  final String _runId = _createRunId();
  final String _startUtc = DateTime.now().toUtc().toIso8601String();
  final AndroidNativeDvDiagnosticRows<Map<String, Object?>> _rows =
      AndroidNativeDvDiagnosticRows<Map<String, Object?>>();
  final ValueNotifier<AndroidNativeDvReleaseDiagnosticState> state =
      ValueNotifier<AndroidNativeDvReleaseDiagnosticState>(
    const AndroidNativeDvReleaseDiagnosticState(phase: 'waiting'),
  );
  HdrNativeDvPendingOpen? _pendingOpen;
  HdrOptionSourceIdentity? _sourceIdentity;
  HdrNativeDvOutputSnapshot? _surfaceIdentity;
  Directory? _outputDirectory;
  File? _outputFile;
  Timer? _timer;
  Stopwatch? _clock;
  Future<void> _reportWriteTail = Future<void>.value();
  Completer<void>? _sampleFinished;
  bool _sampling = false;
  bool _closed = false;
  Future<void>? _startFuture;
  Future<void>? _shutdownFuture;
  Future<String>? _unsettledPropertyRead;
  StreamSubscription<bool>? _completedSubscription;
  AndroidMediaCodecConfiguration? _lastActiveCodec;
  bool _terminalEventObserved = false;
  bool _terminalRowWritten = false;
  bool _sampleFailed = false;
  bool _samplingDeadlineFinalized = false;

  Future<void> start() => _startFuture ??= _startOnce();

  void _ensureStarting() {
    if (_closed) throw StateError('Diagnostic startup was closed');
  }

  Future<void> _startOnce() async {
    try {
      _ensureStarting();
      _setState('waiting for bound Surface');
      final beforeSurface = _requireBoundSurface();
      final vo = await _readProperty('vo');
      final hwdec = await _readProperty('hwdec');
      final bridgeApi = await _readProperty('android-native-dv-bridge-api');
      _ensureStarting();
      if (vo != 'mediacodec_embed' || hwdec != 'mediacodec') {
        throw StateError('Requires vo=mediacodec_embed and hwdec=mediacodec');
      }
      if (bridgeApi != '1') {
        throw StateError('Native DV bridge API 1 is required (got $bridgeApi)');
      }
      await _prepareReportFile();
      _ensureStarting();
      final initial = await _readIdentity();
      _ensureStarting();
      if (initial.path.isNotEmpty || initial.playlistEntryId.isNotEmpty) {
        throw StateError('Release diagnostic requires an idle Player');
      }

      // A stop proof is captured through the same Player admission lock used
      // by public open. It must still describe the current empty source.
      final stopped = await captureAndroidNativeDvDiagnosticInitialBoundary(
        lock: player.lock,
        expectedIdle: initial,
        stop: () => player.stop(synchronized: false),
        readIdentity: _readIdentity,
      );
      _ensureStarting();
      if (!identical(stopped.player, player) ||
          stopped.path.isNotEmpty ||
          stopped.playlistEntryId.isNotEmpty) {
        throw StateError('Initial stopped proof is invalid');
      }
      final afterStopSurface = _requireBoundSurface();
      _requireSameSurface(beforeSurface, afterStopSurface);
      await AndroidHdrBackend.beginNativeDvUnderLock(
        lock: player.lock,
        options: _options,
        stoppedIdentity: stopped,
        vd: 'native_dv=1',
        renderMode: 'timed',
      );
      _ensureStarting();

      _setState('opening fixed official P5');
      final pending = await AndroidHdrBackend.captureNativeDvOpenUnderLock(
        lock: player.lock,
        options: _options,
        mediaUri: androidNativeDvReleaseDiagnosticSource,
        openWithoutLock: () => player.open(
          Media(androidNativeDvReleaseDiagnosticSource),
          play: true,
          synchronized: false,
        ),
        readProperty: _readProperty,
        onCaptured: (value) => _pendingOpen = value,
      );
      _pendingOpen = pending;
      _ensureStarting();
      final loaded = await AndroidHdrBackend.confirmNativeDvOpenIdentity(
        before: pending.before,
        mediaUri: pending.mediaUri,
        expectedPlaylistEntryId: pending.playlistEntryId,
        readIdentity: _readIdentity,
        readPlaylistFilename: () => _readProperty('playlist/0/filename'),
        waitForFileLoadedEntry: player.waitForFileLoadedEntryAfter,
        budget: const Duration(seconds: 20),
      );
      _ensureStarting();
      await AndroidHdrBackend.rebindNativeDvUnderLock(
        lock: player.lock,
        options: _options,
        before: pending.before,
        confirmed: loaded,
      );
      _pendingOpen = null;
      _sourceIdentity = loaded;
      _ensureStarting();
      await _options.verify();
      _ensureStarting();
      final afterOpenSurface = _requireBoundSurface();
      _requireSameSurface(beforeSurface, afterOpenSurface);
      _surfaceIdentity = afterOpenSurface;

      _clock = Stopwatch()..start();
      _setState('playing; visual acceptance requires human observation');
      final resourcesPublished =
          await publishAndroidNativeDvDiagnosticResourcesAfterReport(
        initialReport: _writeReport(),
        canPublish: () => !_closed,
        publish: () {
          _completedSubscription = player.stream.completed.listen((completed) {
            if (!completed || _closed) return;
            _terminalEventObserved = true;
            if (!_sampling) unawaited(_sampleOnce(forceTerminal: true));
          });
          _timer =
              Timer.periodic(Duration(seconds: sampleIntervalSeconds), (_) {
            if (_closed || _terminalRowWritten || _samplingDeadlineFinalized) {
              return;
            }
            if (!_sampling) {
              unawaited(_sampleOnce(forceTerminal: _terminalEventObserved));
            }
          });
          unawaited(_sampleOnce());
        },
      );
      if (!resourcesPublished) _ensureStarting();
    } catch (error) {
      _sampleFailed = true;
      _timer?.cancel();
      unawaited(_completedSubscription?.cancel());
      _completedSubscription = null;
      _setState('start failed; shutdown required', error: '$error');
      rethrow;
    }
  }

  Future<void> _sampleOnce({bool forceTerminal = false}) async {
    if (_sampling) {
      if (forceTerminal) _terminalEventObserved = true;
      return;
    }
    if (_closed ||
        _terminalRowWritten ||
        _samplingDeadlineFinalized ||
        _rows.length >= androidNativeDvReleaseDiagnosticMaxRows) {
      return;
    }
    if (androidNativeDvDiagnosticDeadlineReached(
      elapsedMilliseconds: _clock?.elapsedMilliseconds ?? 0,
      durationSeconds: durationSeconds,
    )) {
      _samplingDeadlineFinalized = true;
      _timer?.cancel();
      _setState('sampling time limit reached');
      await _writeReport();
      return;
    }
    _sampling = true;
    _sampleFinished = Completer<void>();
    try {
      final expected = _sourceIdentity;
      if (expected == null) throw StateError('No confirmed source identity');
      final before = await _readIdentity();
      var terminalAtStart =
          forceTerminal || _terminalEventObserved || player.state.completed;
      if (terminalAtStart) {
        if (!_isOwnedTerminalIdentity(expected, before)) {
          throw StateError('Terminal source identity crossed an unowned entry');
        }
      } else {
        try {
          await _options.verify();
        } catch (_) {
          // EOS can clear the current path while paired-option readback is in
          // flight. Reclassify only when the event and source identity prove
          // this is the same terminal source.
          if (!_terminalEventObserved && !player.state.completed) rethrow;
          terminalAtStart = true;
          if (!_isOwnedTerminalIdentity(expected, before)) rethrow;
        }
      }
      if (!terminalAtStart && before != expected) {
        throw StateError('Source/player/entry/epoch changed before sample');
      }
      final surfaceBefore = _requireBoundSurface();
      _requireSameSurface(_surfaceIdentity!, surfaceBefore);
      final configurationBefore = <String, String>{};
      for (final name in const <String>[
        'vo',
        'wid',
        'vid',
        'hwdec',
        'hwdec-current',
        'vd-lavc-o',
        'mediacodec-embed-render-mode',
        'android-native-dv-bridge-api',
        'android-mediacodec-info',
      ]) {
        configurationBefore[name] = await _readProperty(name);
      }
      final properties = <String, String>{};
      for (final name in const <String>[
        'path',
        'playlist/0/id',
        'playlist/0/filename',
        'time-pos',
        'duration',
        'pause',
        'frame-drop-count',
        'decoder-frame-drop-count',
        'mistimed-frame-count',
        'vo-delayed-frame-count',
      ]) {
        properties[name] = await _readProperty(name);
      }
      final configurationAfter = <String, String>{};
      for (final name in configurationBefore.keys) {
        configurationAfter[name] = await _readProperty(name);
      }
      final time = double.tryParse(properties['time-pos'] ?? '');
      final duration = double.tryParse(properties['duration'] ?? '');
      final eos = player.state.completed ||
          _terminalEventObserved ||
          (time != null && duration != null && time >= duration);
      if (!eos &&
          (configurationBefore['hwdec'] != configurationAfter['hwdec'] ||
              configurationBefore['hwdec-current'] !=
                  configurationAfter['hwdec-current'] ||
              configurationBefore['vo'] != configurationAfter['vo'] ||
              configurationBefore['wid'] != configurationAfter['wid'] ||
              configurationBefore['vid'] != configurationAfter['vid'] ||
              configurationBefore['vd-lavc-o'] !=
                  configurationAfter['vd-lavc-o'] ||
              configurationBefore['mediacodec-embed-render-mode'] !=
                  configurationAfter['mediacodec-embed-render-mode'])) {
        throw StateError('Codec/output configuration changed during sample');
      }
      final codecBefore = AndroidMediaCodecConfiguration.parse(
        configurationBefore['android-mediacodec-info'],
      );
      final codecAfter = AndroidMediaCodecConfiguration.parse(
        configurationAfter['android-mediacodec-info'],
      );
      if (!eos &&
          _lastActiveCodec != null &&
          (codecBefore == null ||
              !codecBefore.nativeDvActive ||
              codecAfter == null ||
              !codecAfter.nativeDvActive ||
              codecBefore.mime != codecAfter.mime ||
              codecBefore.codec != codecAfter.codec)) {
        throw StateError('Previously active native DV codec facts changed');
      }
      if (!eos &&
          codecBefore?.nativeDvActive == true &&
          codecAfter?.nativeDvActive != true) {
        throw StateError('Native DV configuration disappeared during sample');
      }
      final after = await _readIdentity();
      if (eos
          ? !_isOwnedTerminalIdentity(expected, after)
          : after != expected) {
        throw StateError('Source/player/entry/epoch changed during sample');
      }
      if (_closed) return;
      if (androidNativeDvDiagnosticDeadlineReached(
        elapsedMilliseconds: _clock?.elapsedMilliseconds ?? 0,
        durationSeconds: durationSeconds,
      )) {
        _timer?.cancel();
        _setState('sampling time limit reached');
        await _writeReport();
        return;
      }
      final surface = _requireBoundSurface();
      _requireSameSurface(_surfaceIdentity!, surface);
      final codec = codecAfter;
      final previousCodec = _lastActiveCodec;
      if (!eos &&
          previousCodec != null &&
          (codec == null ||
              !codec.nativeDvActive ||
              codec.mime != previousCodec.mime ||
              codec.codec != previousCodec.codec)) {
        throw StateError('Previously active native DV codec facts changed');
      }
      if (codec?.nativeDvActive == true) _lastActiveCodec = codec;
      if (properties['path'] != after.path ||
          properties['playlist/0/id'] != after.playlistEntryId) {
        throw StateError(
            'Sample property tuple differs from bound source tuple');
      }
      _rows.add(<String, Object?>{
        'elapsedMs': _clock?.elapsedMilliseconds,
        'sampleUtc': DateTime.now().toUtc().toIso8601String(),
        'openGeneration': 1,
        'playerIdentity': identityHashCode(expected.player),
        'source': after.path,
        'expectedSource': expected.path,
        'playlistEntryId': after.playlistEntryId,
        'fileLoadedEpoch': after.fileLoadedEpoch,
        'surfaceOwner': _serializeSurface(surface),
        'configurationBefore': configurationBefore,
        'configurationAfter': configurationAfter,
        'properties': properties,
        'codecConfiguration': codec == null
            ? {
                'state':
                    eos ? 'unavailable-at-terminal' : 'unknown-or-unavailable',
              }
            : {
                'state': 'configuration-only',
                'mime': codec.mime,
                'codec': codec.codec,
                'nativeDvActive': codec.nativeDvActive,
              },
        'timePosSeconds': time,
        'durationSeconds': duration,
        'eos': eos,
        'eosEventObserved': _terminalEventObserved,
        'ownedPathPreserved': after.path == expected.path,
        'codecConfigurationUnavailableAtTerminal': eos && codecAfter == null,
        'nativeDvConfigurationPreviouslyObserved': _lastActiveCodec != null,
        'playing': player.state.playing,
        'humanVisualAcceptance': 'pending',
      });
      _setState(eos
          ? 'EOS reached; visual acceptance remains human'
          : 'sampling ${_rows.length} rows');
      await _writeReport();
      if (eos || _rows.length >= androidNativeDvReleaseDiagnosticMaxRows) {
        _terminalRowWritten = true;
        _timer?.cancel();
      }
    } catch (error) {
      _sampleFailed = true;
      if (!_closed) {
        _timer?.cancel();
        final deadline = error is AndroidNativeDvDiagnosticSamplingDeadline ||
            androidNativeDvDiagnosticDeadlineReached(
              elapsedMilliseconds: _clock?.elapsedMilliseconds ?? 0,
              durationSeconds: durationSeconds,
            );
        if (deadline) _samplingDeadlineFinalized = true;
        _setState(
          deadline
              ? 'sampling time limit reached'
              : 'sampling stopped; shutdown required',
          error: deadline ? null : '$error',
        );
        try {
          await _writeReport();
        } catch (_) {
          // Keep the primary sampling failure visible to the page.
        }
      }
    } finally {
      _sampling = false;
      _sampleFinished?.complete();
      _sampleFinished = null;
      if (androidNativeDvDiagnosticShouldRetryTerminalSample(
        terminalObserved: _terminalEventObserved,
        terminalRowWritten: _terminalRowWritten,
        sampleFailed: _sampleFailed,
        closed: _closed,
      )) {
        unawaited(_sampleOnce(forceTerminal: true));
      }
    }
  }

  Future<void> _writeReport() {
    final output = _outputFile;
    if (output == null) return Future<void>.value();
    final payload = <String, Object?>{
      'schema': 1,
      'diagnosticOnly': true,
      'runId': _runId,
      'startUtc': _startUtc,
      'diagnosticIdentityLabel': externalIdentityLabel,
      'externalIdentityLabel': externalIdentityLabel,
      'sourcePath': androidNativeDvReleaseDiagnosticSource,
      'sourceSha256': 'external-script-bound',
      'apkSha256': 'external-script-bound',
      'durationLimitSeconds': durationSeconds,
      'wallClockDeadline': true,
      'sampleIntervalSeconds': sampleIntervalSeconds,
      'samplingOverhead': 'property reads plus atomic JSON file flush; nonzero',
      'nativeFfiCancellation':
          'Dart timeout does not cancel an in-flight native call',
      'rowCount': _rows.length,
      'maxRows': androidNativeDvReleaseDiagnosticMaxRows,
      'phase': state.value.phase,
      'error': state.value.error,
      'humanVisualAcceptance': 'pending',
      'rows': _rows.values.toList(growable: false),
    };
    final write = _reportWriteTail
        .catchError((Object _) {})
        .then((_) => writeAndroidNativeDvDiagnosticJsonAtomically(
              output,
              payload,
            ));
    _reportWriteTail = write;
    return write;
  }

  Future<void> _prepareReportFile() async {
    final external = await path_provider.getExternalStorageDirectory();
    if (external == null) {
      throw StateError('App-specific external files directory unavailable');
    }
    _outputDirectory = Directory(
      '${external.path}${Platform.pathSeparator}media-kit-hdr-diagnostic',
    );
    await _outputDirectory!.create(recursive: true);
    _outputFile = File(
      '${_outputDirectory!.path}${Platform.pathSeparator}'
      'native-dv-release-diagnostic.json',
    );
    await _writeReport();
  }

  Future<HdrOptionSourceIdentity> _readIdentity() async {
    final epoch = player.fileLoadedEpoch;
    final path = await _readProperty('path');
    final entry = await _readProperty('playlist/0/id');
    if (await _readProperty('path') != path ||
        await _readProperty('playlist/0/id') != entry ||
        player.fileLoadedEpoch != epoch) {
      throw StateError('Media identity changed during read');
    }
    return HdrOptionSourceIdentity(
      player: player,
      path: path,
      playlistEntryId: entry,
      fileLoadedEpoch: epoch,
    );
  }

  Future<String> _readProperty(String name) async {
    final unsettled = _unsettledPropertyRead;
    if (unsettled != null) {
      final timeout = androidNativeDvDiagnosticPropertyReadTimeout(
        remainingBudget: _samplingRemainingBudget(),
      );
      await unsettled.timeout(timeout);
      if (identical(_unsettledPropertyRead, unsettled)) {
        _unsettledPropertyRead = null;
      }
    }
    final read = admitAndroidNativeDvDiagnosticRead<String>(
      remainingBudget: _samplingRemainingBudget(),
      startNativeRead: () => player.getProperty(name),
    );
    final operation = read.operation;
    _unsettledPropertyRead = operation;
    unawaited(operation.then<void>(
      (_) {
        if (identical(_unsettledPropertyRead, operation)) {
          _unsettledPropertyRead = null;
        }
      },
      onError: (Object _, StackTrace __) {
        if (identical(_unsettledPropertyRead, operation)) {
          _unsettledPropertyRead = null;
        }
      },
    ));
    try {
      return await read.bounded;
    } on TimeoutException {
      throw TimeoutException(
        'Property read timed out; native call may remain pending: $name',
      );
    }
  }

  Duration? _samplingRemainingBudget() {
    if (!_sampling) return null;
    final remaining =
        Duration(seconds: durationSeconds) - (_clock?.elapsed ?? Duration.zero);
    if (remaining <= Duration.zero) {
      throw const AndroidNativeDvDiagnosticSamplingDeadline();
    }
    return remaining;
  }

  HdrNativeDvOutputSnapshot _requireBoundSurface() {
    if (!identical(outputController.player, player)) {
      throw StateError('Output controller belongs to another Player');
    }
    final identity = outputController.currentBoundOutputIdentity;
    if (identity == null) {
      throw StateError('A bound native PlatformView Surface is required');
    }
    return HdrNativeDvOutputSnapshot(outputController, identity);
  }

  void _requireSameSurface(
    HdrNativeDvOutputSnapshot expected,
    HdrNativeDvOutputSnapshot actual,
  ) {
    if (!expected.matches(actual)) {
      throw StateError('Bound Surface owner changed during diagnostic');
    }
  }

  bool _isOwnedTerminalIdentity(
    HdrOptionSourceIdentity expected,
    HdrOptionSourceIdentity actual,
  ) =>
      androidNativeDvDiagnosticOwnsTerminalIdentity(expected, actual);

  Map<String, Object?> _serializeSurface(HdrNativeDvOutputSnapshot snapshot) {
    final identity = snapshot.identity;
    return <String, Object?>{
      'controllerIdentity': identityHashCode(snapshot.controller),
      'handle': identity.handle,
      'generation': identity.generation,
      'viewId': identity.viewId,
      'surfaceGeneration': identity.surfaceGeneration,
      'wid': identity.wid,
    };
  }

  Future<void> shutdown() {
    final existing = _shutdownFuture;
    if (existing != null) return _boundedShutdownWait(existing);
    final attempt = _shutdownOnce();
    _shutdownFuture = attempt;
    unawaited(attempt.then<void>((_) {}, onError: (Object _, StackTrace __) {
      if (identical(_shutdownFuture, attempt)) _shutdownFuture = null;
    }));
    return _boundedShutdownWait(attempt);
  }

  Future<void> _boundedShutdownWait(Future<void> attempt) => attempt.timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          _setState(
            'shutdown still pending; owned option restore debt retained',
            error: 'Dart timeout cannot cancel a native Player operation',
          );
          unawaited(_writeReport());
          throw TimeoutException('Native DV diagnostic shutdown is pending');
        },
      );

  Future<void> _shutdownOnce() async {
    _closed = true;
    _timer?.cancel();
    await _completedSubscription?.cancel();
    _completedSubscription = null;
    try {
      await awaitAndroidNativeDvDiagnosticStartSettled(_startFuture);
      // Startup may have been inside its initial report write when shutdown
      // first cancelled resources. Close any resources published before its
      // closed-state check observed teardown.
      _timer?.cancel();
      await _completedSubscription?.cancel();
      _completedSubscription = null;
      final sample = _sampleFinished;
      if (sample != null) {
        await sample.future.timeout(const Duration(seconds: 15));
      }
      _setState('shutdown pending; preserving owned options');
      await _writeReport();
      final unsettledRead = _unsettledPropertyRead;
      if (unsettledRead != null) {
        await unsettledRead.timeout(const Duration(seconds: 3));
        if (identical(_unsettledPropertyRead, unsettledRead)) {
          _unsettledPropertyRead = null;
        }
      }
      final pending = _pendingOpen;
      if (pending != null) {
        final confirmed = await pending.confirmForCleanup(
          readIdentity: _readIdentity,
          readPlaylistFilename: () => _readProperty('playlist/0/filename'),
          waitForFileLoadedEntry: player.waitForFileLoadedEntryAfter,
          requireLoaded: true,
          budget: const Duration(seconds: 20),
        );
        await AndroidHdrBackend.rebindNativeDvUnderLock(
          lock: player.lock,
          options: _options,
          before: pending.before,
          confirmed: confirmed,
        );
        _sourceIdentity = confirmed;
        _pendingOpen = null;
      }
      if (_options.active) {
        final ownerIdentity = _options.identity;
        if (ownerIdentity == null) {
          throw StateError('Native DV owner lost its source identity');
        }
        final current = await _readIdentity();
        if (current == ownerIdentity) {
          final captured = await AndroidHdrBackend.captureNativeDvStopUnderLock(
            lock: player.lock,
            options: _options,
            onStopIssued: (_) {},
            stopWithoutLock: () => player.stop(synchronized: false),
            readIdentity: _readIdentity,
          );
          final confirmed =
              await AndroidHdrBackend.confirmNativeDvStoppedIdentity(
            before: captured.before,
            readIdentity: _readIdentity,
          );
          if (confirmed != captured.stopped) {
            throw StateError('Stopped identity changed before option restore');
          }
          await AndroidHdrBackend.rebindNativeDvUnderLock(
            lock: player.lock,
            options: _options,
            before: captured.before,
            confirmed: confirmed,
          );
          if (captured.operationError != null) {
            throw HdrNativeDvOptionFailure(
              captured.operationError,
              const <String, Object>{'stop': 'stop returned an error'},
            );
          }
        } else {
          if (!_terminalRowWritten ||
              !_isOwnedTerminalIdentity(ownerIdentity, current)) {
            throw StateError(
                'Cannot stop or restore after unowned native-DV identity drift');
          }
          final stopped =
              await AndroidHdrBackend.captureStoppedBoundaryUnderLock(
            lock: player.lock,
            stopWithoutLock: () async {
              final beforeStop = await _readIdentity();
              if (!_isOwnedTerminalIdentity(ownerIdentity, beforeStop)) {
                throw StateError('Terminal source changed before owned stop');
              }
              await player.stop(synchronized: false);
            },
            readIdentity: _readIdentity,
          );
          if (!identical(stopped.player, player) ||
              stopped.path.isNotEmpty ||
              stopped.playlistEntryId.isNotEmpty ||
              stopped.fileLoadedEpoch != ownerIdentity.fileLoadedEpoch) {
            throw StateError('Terminal owned stop did not retain its proof');
          }
          await AndroidHdrBackend.rebindNativeDvUnderLock(
            lock: player.lock,
            options: _options,
            before: ownerIdentity,
            confirmed: stopped,
          );
        }
        await restoreAndroidNativeDvDiagnosticOptionsUnderLock(
          lock: player.lock,
          options: _options,
        );
      }
      _sourceIdentity = null;
      _setState('shutdown restored owned option pair');
      await _writeReport();
    } catch (error) {
      // Do not clear the owner: its pending writes are the recovery debt.
      _setState('shutdown failed; option restore debt retained',
          error: '$error');
      try {
        await _writeReport();
      } catch (_) {}
      rethrow;
    }
  }

  void _setState(String phase, {String? error}) {
    state.value = AndroidNativeDvReleaseDiagnosticState(
      phase: phase,
      error: error,
      rowCount: _rows.length,
      outputPath: _outputFile?.path,
      ownerActive: _options.active,
    );
  }

  static String _createRunId() {
    final random = Random.secure();
    final suffix = List<int>.generate(16, (_) => random.nextInt(256))
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${DateTime.now().toUtc().microsecondsSinceEpoch}-$suffix';
  }
}

class AndroidNativeDvReleaseDiagnosticState {
  const AndroidNativeDvReleaseDiagnosticState({
    required this.phase,
    this.error,
    this.rowCount = 0,
    this.outputPath,
    this.ownerActive = false,
  });

  final String phase;
  final String? error;
  final int rowCount;
  final String? outputPath;
  final bool ownerActive;
}
