/// This file is a part of media_kit (https://github.com/media-kit/media-kit).
///
/// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
/// All rights reserved.
/// Use of this source code is governed by MIT license that can be found in the LICENSE file.
import 'dart:async';

/// The PlatformView output-availability waiter state machine (production
/// object used by [AndroidVideoController]).
///
/// It owns exactly the state the controller previously held in loose fields:
/// whether the current output is available, the current-output waiter, and
/// the one-shot initial-output waiter with its failed flag. Every waiter
/// transition of the controller — bind success, already-bound republish,
/// invalidation on rebind/destroy, failure publication, disposal, and the
/// wid-listener activation's suspend/restore — goes through this object, so
/// the transitions are exercised as one real machine instead of scattered
/// field writes.
class PlatformOutputAvailability {
  PlatformOutputAvailability();

  bool _currentUnavailable = true;
  bool _initialFailed = false;
  Completer<void> _currentWaiter = Completer<void>();
  Completer<void> _initialWaiter = Completer<void>();

  /// Whether the current output must (re)fail instead of completing now.
  bool get currentOutputUnavailable => _currentUnavailable;

  Future<void> get currentFuture => _currentWaiter.future;
  Future<void> get initialFuture => _initialWaiter.future;
  bool get currentWaiterCompleted => _currentWaiter.isCompleted;
  bool get initialWaiterCompleted => _initialWaiter.isCompleted;

  /// The current output went away or is being re-activated: the waiter is
  /// unavailable and a completed waiter (failed or not) is replaced so later
  /// `waitUntilCurrentOutputBound` callers wait for the next outcome instead
  /// of observing the old one.
  void invalidateCurrent() {
    _currentUnavailable = true;
    if (_currentWaiter.isCompleted) {
      _currentWaiter = Completer<void>();
    }
  }

  /// Marks the current output unavailable without touching any waiter
  /// (disposal paths pair this with an explicit failure).
  void markCurrentUnavailable() {
    _currentUnavailable = true;
  }

  /// A new view creation or a new Surface attempt: a previously failed
  /// initial waiter becomes fresh again, and a completed current waiter is
  /// replaced while the output is unavailable.
  void beginNewOutputAttempt() {
    if (_initialFailed) {
      _initialWaiter = Completer<void>();
      _initialFailed = false;
    }
    if (_currentUnavailable && _currentWaiter.isCompleted) {
      _currentWaiter = Completer<void>();
    }
  }

  /// Fails the current waiter. The error stays observable for callers
  /// holding the same future; the swallow branch prevents an unhandled
  /// async error when no caller ever awaits it.
  void failCurrent(Object error, StackTrace stack) {
    if (!_currentWaiter.isCompleted) {
      _currentWaiter.completeError(error, stack);
      unawaited(_currentWaiter.future.catchError((Object _) {}));
    }
  }

  /// The generic property-failure path: fail the current waiter and install
  /// a fresh one. The failure itself is preserved for later waiters through
  /// the controller's pending-failure bookkeeping.
  void failCurrentAndRenew(Object error, StackTrace stack) {
    failCurrent(error, stack);
    _currentWaiter = Completer<void>();
  }

  /// Fails the initial-output waiter. [rememberFailure] records that the
  /// initial barrier failed so a later new-attempt recreates it.
  void failInitial(
    Object error,
    StackTrace stack, {
    bool rememberFailure = false,
  }) {
    if (!_initialWaiter.isCompleted) {
      _initialFailed = rememberFailure;
      _initialWaiter.completeError(error, stack);
      unawaited(_initialWaiter.future.catchError((Object _) {}));
    }
  }

  /// The output is (again) the expected one: the current waiter completes
  /// and — unless this is only an already-bound republish — the initial
  /// barrier completes too.
  void publishCurrentAvailable({bool completeInitial = true}) {
    _currentUnavailable = false;
    if (!_currentWaiter.isCompleted) {
      _currentWaiter.complete();
    }
    if (completeInitial && !_initialWaiter.isCompleted) {
      _initialWaiter.complete();
    }
  }

  /// Completes only the initial barrier (the texture first-bind path, whose
  /// current-output waiter is managed separately).
  void completeInitial() {
    if (!_initialWaiter.isCompleted) {
      _initialWaiter.complete();
    }
  }
}
