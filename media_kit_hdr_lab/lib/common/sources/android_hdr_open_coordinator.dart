// MIGRATED (S10/S13): the library implementation lives in media_kit_video/lib/src/hdr/;
// this file is kept only for hdr_lab tests that still reference it and is no longer
// wired into the 01 test page.
import 'dart:async';
import 'dart:io';

import 'android_hdr_sample_identity.dart';

typedef SampleVerifier = Future<AndroidHdrSampleIdentity> Function(
  String source,
  bool Function() cancelled,
);

/// Native side effects are deliberately explicit so tests can hold any phase.
/// A returned result means opened, not that a frame reached the display.
abstract class AndroidHdrOpenBackend {
  Future<void> validate(AndroidHdrSampleIdentity identity);
  Future<void> stop();
  Future<void> resetOwnedConfiguration();
  Future<void> prepareOutput(AndroidHdrSampleIdentity identity);
  Future<void> configure(AndroidHdrSampleIdentity identity);
  Future<void> waitForOutput(AndroidHdrSampleIdentity identity);
  Future<void> open(
    AndroidHdrSampleIdentity identity, {
    Duration? start,
    required bool play,
  });
  Future<void> verifyTrack(AndroidHdrSampleIdentity identity);
}

class OpenSuperseded implements Exception {
  const OpenSuperseded();
}

class AndroidHdrOpenResult {
  const AndroidHdrOpenResult(this.identity, this._generation);
  final AndroidHdrSampleIdentity identity;
  final int _generation;

  // The existing size/first-frame futures do not prove this session presented.
  bool get presentationVerified => false;
}

class AndroidHdrOpenCoordinator {
  AndroidHdrOpenCoordinator(this.backend,
      {SampleVerifier? verifier,
      this.onPhase,
      this.outputTimeout = const Duration(seconds: 10)})
      : privateRoot = null,
        knownSha256 = androidHdrSampleSha256,
        _verifier = verifier ??
            ((source, cancelled) =>
                identifyAndroidHdrSample(source, cancelled: cancelled));

  /// Opens only a private copy whose bytes were hashed while being copied.
  AndroidHdrOpenCoordinator.staged(
    this.backend,
    Directory this.privateRoot, {
    this.outputTimeout = const Duration(seconds: 10),
    this.knownSha256 = androidHdrSampleSha256,
    this.onPhase,
  }) : _verifier = null;

  final AndroidHdrOpenBackend backend;
  final SampleVerifier? _verifier;
  final Directory? privateRoot;
  final Map<String, AndroidHdrSample> knownSha256;
  final Duration outputTimeout;
  final void Function(int generation, String phase, int elapsedMicros)? onPhase;
  Future<void> _tail = Future<void>.value();
  StagedAndroidHdrSample? _attachedStaged;
  final Set<Future<void>> _preparations = {};
  final List<Object> _cleanupFailures = [];
  int _generation = 0;
  bool _disposed = false;
  Future<void>? _disposeFuture;
  // A superseded transaction may have changed native properties before it
  // could roll them back. The next queued request owns that cleanup, even if
  // its own policy validation fails.
  bool _pendingRollback = false;
  bool _activeMedia = false;

  List<Object> get cleanupFailures =>
      List<Object>.unmodifiable(_cleanupFailures);

  Future<void> _cleanupWithoutMasking(StagedAndroidHdrSample? staged) async {
    if (staged == null) return;
    try {
      await staged.dispose();
    } catch (error) {
      _cleanupFailures.add(error);
    }
  }

  bool _invalid(int generation) => _disposed || generation != _generation;

  void _check(int generation) {
    if (_invalid(generation)) throw const OpenSuperseded();
  }

  Future<AndroidHdrOpenResult> openSource(
    String source, {
    Duration? start,
    bool play = true,
  }) async {
    if (_disposed) throw StateError('Open coordinator is disposed');
    final generation = ++_generation;
    final elapsed = Stopwatch()..start();
    void mark(String phase) {
      try {
        onPhase?.call(generation, phase, elapsed.elapsedMicroseconds);
      } catch (_) {
        // Diagnostic timing must not affect playback or rollback.
      }
    }

    mark('requested');
    final preparationDone = Completer<void>();
    _preparations.add(preparationDone.future);
    StagedAndroidHdrSample? staged;
    late final AndroidHdrSampleIdentity identity;
    try {
      if (privateRoot != null) {
        staged = await stageAndroidHdrSample(
          source,
          privateRoot!,
          cancelled: () => _invalid(generation),
          knownSha256: knownSha256,
        );
        identity = staged.identity;
      } else {
        identity = await _verifier!(source, () => _invalid(generation));
      }
      _check(generation);
      mark('sample_ready');
    } catch (error, stack) {
      mark('sample_failed');
      await _cleanupWithoutMasking(staged);
      Error.throwWithStackTrace(error, stack);
    } finally {
      _preparations.remove(preparationDone.future);
      preparationDone.complete();
    }

    final result = Completer<AndroidHdrOpenResult>();
    final queued = _tail.then((_) async {
      var switching = false;
      try {
        _check(generation);
        mark('queue_entered');
        if (_pendingRollback) {
          await backend.stop();
          await _attachedStaged?.dispose();
          _attachedStaged = null;
          await backend.resetOwnedConfiguration();
          _pendingRollback = false;
          _activeMedia = false;
          _check(generation);
          mark('rollback_complete');
        }
        await backend.validate(identity);
        _check(generation);
        mark('validated');
        switching = true;
        _pendingRollback = true;
        await backend.stop();
        await _attachedStaged?.dispose();
        _attachedStaged = null;
        _check(generation);
        mark('previous_output_stopped');
        await backend.resetOwnedConfiguration();
        _check(generation);
        _activeMedia = false;
        mark('configuration_reset');
        await backend.prepareOutput(identity);
        _check(generation);
        mark('output_prepared');
        await backend.configure(identity);
        _check(generation);
        mark('configured');
        await backend.waitForOutput(identity).timeout(outputTimeout);
        _check(generation);
        mark('output_ready');
        _attachedStaged = staged;
        await backend.open(identity, start: start, play: play);
        _check(generation);
        mark('media_opened');
        await backend.verifyTrack(identity);
        _check(generation);
        mark('track_verified');
        _pendingRollback = false;
        _activeMedia = true;
        result.complete(AndroidHdrOpenResult(identity, generation));
      } catch (error, stack) {
        mark('open_failed');
        // This callback still owns the side-effect queue even when a newer
        // request has invalidated it. Roll back here so a successor that fails
        // during preparation cannot leave partial native configuration behind.
        if (switching) {
          try {
            await backend.stop();
            await _attachedStaged?.dispose();
            _attachedStaged = null;
            await backend.resetOwnedConfiguration();
            _pendingRollback = false;
            _activeMedia = false;
          } catch (_) {
            // Preserve the failure that caused this transaction to abort.
          }
        }
        if (_attachedStaged != staged) {
          await _cleanupWithoutMasking(staged);
        }
        result.completeError(error, stack);
      }
    });
    _tail = queued.catchError((Object _) {});
    return result.future;
  }

  /// Queues a session-scoped seek or diagnostic command behind native open.
  /// Callers must not put an unbounded wait or a sequence of unrelated
  /// commands inside [action]; split them so each checks the generation.
  Future<void> runForCurrent(
    AndroidHdrOpenResult session,
    Future<void> Function() action,
  ) async {
    _check(session._generation);
    final result = Completer<void>();
    final queued = _tail.then((_) async {
      try {
        _check(session._generation);
        await action();
        _check(session._generation);
        result.complete();
      } catch (error, stack) {
        result.completeError(error, stack);
      }
    });
    _tail = queued.catchError((Object _) {});
    return result.future;
  }

  /// Invalidates callbacks immediately; in-flight native calls finish before
  /// the owner disposes its Player. This does not dispose the Player itself.
  Future<void> dispose() {
    final existing = _disposeFuture;
    if (existing != null) return existing;
    final attempt = _disposeOnce();
    _disposeFuture = attempt;
    unawaited(attempt.then<void>((_) {}, onError: (Object _, StackTrace __) {
      if (identical(_disposeFuture, attempt)) _disposeFuture = null;
    }));
    return attempt;
  }

  Future<void> _disposeOnce() async {
    _disposed = true;
    ++_generation;
    await Future.wait(_preparations.toList());
    await _tail;
    if (_activeMedia || _attachedStaged != null || _pendingRollback) {
      await backend.stop();
      await _attachedStaged?.dispose();
      _attachedStaged = null;
      await backend.resetOwnedConfiguration();
      _pendingRollback = false;
      _activeMedia = false;
    }
  }
}
