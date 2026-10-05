/// This file is a part of media_kit (https://github.com/media-kit/media-kit).
///
/// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
/// All rights reserved.
/// Use of this source code is governed by MIT license that can be found in the LICENSE file.
import 'dart:async';

import 'hdr_open_plan.dart';

/// Resolves a request into a plan before the native side-effect queue. Runs
/// concurrently with newer requests so a slow preparation cannot open after
/// them (hdr_lab's sample-identity verifier position).
typedef HdrOpenPreparer<R, P> = Future<P> Function(
  R request,
  bool Function() cancelled,
);

/// Produces a follow-up plan after a queued phase failed, or null to fail
/// the open with the original error. Consulted inside the transaction so a
/// degradation stays within the same generation (plan 1.4 step 5).
typedef HdrOpenRetry<P> = Future<P?> Function(P plan, Object error);

/// Decides what the review phase concluded from the decoder facts: accept
/// (optionally with an updated plan for the report), or reopen the media in
/// place at a position with a new plan (plan 1.4 step 8).
typedef HdrOpenReview<P> = Future<HdrReviewDecision<P>> Function(
  P plan,
  HdrReviewFacts facts,
);

/// Native side effects are deliberately explicit so tests can hold any phase.
/// A returned result means opened, not that a frame reached the display.
abstract class HdrOpenBackend<P> {
  Future<void> validate(P plan);
  Future<void> stop();
  Future<void> resetOwnedConfiguration();
  Future<void> prepareOutput(P plan);
  Future<void> configure(P plan);
  Future<void> waitForOutput(P plan);
  Future<void> open(
    P plan, {
    Duration? start,
    required bool play,
  });

  /// Gathers the decoder facts for the review phase after the open's
  /// file-loaded boundary. The decision is made by the coordinator's review
  /// hook, not by the backend.
  Future<HdrReviewFacts> reviewFacts(P plan);

  /// Current dataspace/hwdec observation for report building (R4.2).
  HdrBackendObservation observe();
}

/// Coordinator invocation boundary, including the Session review decorator.
/// A failed waitForOutput is the *awaited operation* outcome after timeout;
/// it does not certify completion or cancellation of the underlying future.
enum HdrBackendDiagnosticMethod {
  validate,
  stop,
  resetOwnedConfiguration,
  prepareOutput,
  configure,
  waitForOutput,
  open,
  reviewFacts,
}

enum HdrBackendDiagnosticBoundary { entered, returned, failed }

enum HdrBackendDiagnosticPurpose { normal, rollback, disposal }

/// Diagnostic attribution only; never used for ownership or admission.
class HdrBackendDiagnosticAttempt<P> {
  const HdrBackendDiagnosticAttempt(
      this.coordinatorGeneration, this.ordinal, this.plan);
  final int coordinatorGeneration;
  final int ordinal;
  final P plan;
}

/// Immutable envelope; generic plan and raw error references are not deeply
/// immutable. Observers must synchronously snapshot scalar plan fields, retain
/// raw errors separately for identity assertions, and return without I/O,
/// Player calls, reentry, or widget/output mutation. A callback can still block
/// or deliberately reenter playback; this seam cannot prevent such misuse.
class HdrBackendCallDiagnostic<P> {
  const HdrBackendCallDiagnostic({
    required this.sequence,
    required this.elapsedMicros,
    required this.coordinatorGeneration,
    required this.invocation,
    required this.owningAttempt,
    required this.sessionGeneration,
    required this.owningSessionGeneration,
    required this.method,
    required this.boundary,
    required this.purpose,
    this.error,
    this.stack,
  });
  final int sequence;
  final int elapsedMicros;
  final int coordinatorGeneration;

  /// Null for disposal; request/attempt identity is separate from old ownership.
  final HdrBackendDiagnosticAttempt<P>? invocation;
  final HdrBackendDiagnosticAttempt<P>? owningAttempt;
  final int? sessionGeneration;
  final int? owningSessionGeneration;
  final HdrBackendDiagnosticMethod method;
  final HdrBackendDiagnosticBoundary boundary;
  final HdrBackendDiagnosticPurpose purpose;
  final Object? error;
  final StackTrace? stack;
  String get boundaryScope => 'coordinator-awaited-operation';
}

/// The review phase outcome (plan 1.4 step 8).
class HdrReviewDecision<P> {
  /// Accept the open as-is. [nextPlan], when given, only updates what the
  /// report describes (e.g. the decoder-derived description); no phase runs
  /// again.
  const HdrReviewDecision.accept({this.nextPlan})
      : reopen = false,
        position = null;

  /// Reopen the media in place at [position] with [nextPlan]. Honored at
  /// most once per open.
  const HdrReviewDecision.reopen(this.position, this.nextPlan)
      : reopen = true,
        assert(nextPlan != null);

  final bool reopen;
  final Duration? position;
  final P? nextPlan;
}

class OpenSuperseded implements Exception {
  const OpenSuperseded();
}

class HdrOpenResult<P> {
  const HdrOpenResult(this.plan, this._generation);
  final P plan;
  final int _generation;

  // The existing size/first-frame futures do not prove this session presented.
  bool get presentationVerified => false;
}

/// Serial open orchestration over a backend (ported from hdr_lab's
/// `AndroidHdrOpenCoordinator`): side effects run one at a time, a newer
/// request invalidates the previous generation, and an aborted transaction
/// rolls the backend back — including one superseded by a newer request
/// that itself failed during preparation.
///
/// Two extensions over hdr_lab, both inert for callers that do not use them:
///
/// * [review] — after the media's file-loaded boundary the session reviews
///   the decoder facts and may request one in-place reopen per open.
/// * [retry] with [maxRetries] — on a queued-phase failure the session may
///   supply a follow-up plan (candidate degradation, plan 1.4 step 5) that
///   re-runs the transaction within the same generation.
class HdrOpenCoordinator<R, P> {
  HdrOpenCoordinator(
    this.backend, {
    required this.preparer,
    this.review,
    this.retry,
    this.maxRetries = 0,
    this.onPhase,
    this.onBackendCallDiagnostic,
    this.diagnosticSessionGeneration,
    this.outputTimeout = const Duration(seconds: 10),
  });

  final HdrOpenBackend<P> backend;

  /// The pre-queue plan production (capability snapshot + planning for the
  /// session). A failure here fails the open before any native side effect.
  final HdrOpenPreparer<R, P> preparer;

  /// Post-open decoder review (plan 1.4 step 8). Null accepts always.
  final HdrOpenReview<P>? review;

  /// Failure-driven plan replacement (plan 1.4 step 5). Null fails directly,
  /// matching the hdr_lab behavior.
  final HdrOpenRetry<P>? retry;

  /// How many times [retry] may replace a plan within one open.
  final int maxRetries;

  final Duration outputTimeout;
  final void Function(int generation, String phase, int elapsedMicros)? onPhase;

  /// Internal/testing notification only. Null avoids event and clock allocation.
  final void Function(HdrBackendCallDiagnostic<P>)? onBackendCallDiagnostic;
  final int? Function(P)? diagnosticSessionGeneration;
  Stopwatch? _diagnosticClock;
  int _diagnosticSequence = 0;
  int _diagnosticAttemptOrdinal = 0;
  bool _emittingDiagnostic = false;
  HdrBackendDiagnosticAttempt<P>? _diagnosticOwner;

  HdrBackendDiagnosticAttempt<P>? _diagnosticAttempt(int generation, P plan) =>
      onBackendCallDiagnostic == null
          ? null
          : HdrBackendDiagnosticAttempt(
              generation, ++_diagnosticAttemptOrdinal, plan);

  void _emitBackendCall(
      HdrBackendDiagnosticMethod method,
      HdrBackendDiagnosticBoundary boundary,
      int generation,
      HdrBackendDiagnosticAttempt<P>? invocation,
      HdrBackendDiagnosticPurpose purpose,
      {Object? error,
      StackTrace? stack}) {
    final observer = onBackendCallDiagnostic;
    if (observer == null || _emittingDiagnostic) return;
    _emittingDiagnostic = true;
    try {
      final clock = _diagnosticClock ??= Stopwatch()..start();
      final owner = _diagnosticOwner;
      observer(HdrBackendCallDiagnostic<P>(
        sequence: ++_diagnosticSequence,
        elapsedMicros: clock.elapsedMicroseconds,
        coordinatorGeneration: generation,
        invocation: invocation,
        owningAttempt: owner,
        sessionGeneration: invocation == null
            ? null
            : diagnosticSessionGeneration?.call(invocation.plan),
        owningSessionGeneration: owner == null
            ? null
            : diagnosticSessionGeneration?.call(owner.plan),
        method: method,
        boundary: boundary,
        purpose: purpose,
        error: error,
        stack: stack,
      ));
    } catch (_) {
      // Entire projection/emission path is isolated, with no error reporter.
    } finally {
      _emittingDiagnostic = false;
    }
  }

  Future<void> _tail = Future<void>.value();
  final Set<Future<void>> _preparations = {};
  int _generation = 0;
  bool _disposed = false;
  Future<void>? _disposeFuture;
  // A superseded transaction may have changed native properties before it
  // could roll them back. The next queued request owns that cleanup, even if
  // its own policy validation fails.
  bool _pendingRollback = false;
  bool _activeMedia = false;

  bool _invalid(int generation) => _disposed || generation != _generation;

  void _check(int generation) {
    if (_invalid(generation)) throw const OpenSuperseded();
  }

  Future<HdrOpenResult<P>> openSource(
    R request, {
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
    late final P plan;
    try {
      plan = await preparer(request, () => _invalid(generation));
      _check(generation);
      mark('plan_ready');
    } catch (error, stack) {
      mark('plan_failed');
      Error.throwWithStackTrace(error, stack);
    } finally {
      _preparations.remove(preparationDone.future);
      preparationDone.complete();
    }

    final result = Completer<HdrOpenResult<P>>();
    final queued = _tail.then((_) async {
      var switching = false;
      var attemptPlan = plan;
      var diagnosticAttempt = _diagnosticAttempt(generation, attemptPlan);
      var currentStart = start;
      var retriesUsed = 0;
      var rebuilt = false;
      while (true) {
        try {
          _check(generation);
          mark('queue_entered');
          if (_pendingRollback) {
            _emitBackendCall(
                HdrBackendDiagnosticMethod.stop,
                HdrBackendDiagnosticBoundary.entered,
                generation,
                diagnosticAttempt,
                HdrBackendDiagnosticPurpose.rollback);
            try {
              await backend.stop();
            } catch (error, stack) {
              _emitBackendCall(
                  HdrBackendDiagnosticMethod.stop,
                  HdrBackendDiagnosticBoundary.failed,
                  generation,
                  diagnosticAttempt,
                  HdrBackendDiagnosticPurpose.rollback,
                  error: error,
                  stack: stack);
              rethrow;
            }
            _emitBackendCall(
                HdrBackendDiagnosticMethod.stop,
                HdrBackendDiagnosticBoundary.returned,
                generation,
                diagnosticAttempt,
                HdrBackendDiagnosticPurpose.rollback);
            _emitBackendCall(
                HdrBackendDiagnosticMethod.resetOwnedConfiguration,
                HdrBackendDiagnosticBoundary.entered,
                generation,
                diagnosticAttempt,
                HdrBackendDiagnosticPurpose.rollback);
            try {
              await backend.resetOwnedConfiguration();
            } catch (error, stack) {
              _emitBackendCall(
                  HdrBackendDiagnosticMethod.resetOwnedConfiguration,
                  HdrBackendDiagnosticBoundary.failed,
                  generation,
                  diagnosticAttempt,
                  HdrBackendDiagnosticPurpose.rollback,
                  error: error,
                  stack: stack);
              rethrow;
            }
            _emitBackendCall(
                HdrBackendDiagnosticMethod.resetOwnedConfiguration,
                HdrBackendDiagnosticBoundary.returned,
                generation,
                diagnosticAttempt,
                HdrBackendDiagnosticPurpose.rollback);
            _pendingRollback = false;
            _activeMedia = false;
            _diagnosticOwner = null;
            _check(generation);
            mark('rollback_complete');
          }
          _emitBackendCall(
              HdrBackendDiagnosticMethod.validate,
              HdrBackendDiagnosticBoundary.entered,
              generation,
              diagnosticAttempt,
              HdrBackendDiagnosticPurpose.normal);
          try {
            await backend.validate(attemptPlan);
          } catch (error, stack) {
            _emitBackendCall(
                HdrBackendDiagnosticMethod.validate,
                HdrBackendDiagnosticBoundary.failed,
                generation,
                diagnosticAttempt,
                HdrBackendDiagnosticPurpose.normal,
                error: error,
                stack: stack);
            rethrow;
          }
          _emitBackendCall(
              HdrBackendDiagnosticMethod.validate,
              HdrBackendDiagnosticBoundary.returned,
              generation,
              diagnosticAttempt,
              HdrBackendDiagnosticPurpose.normal);
          _check(generation);
          mark('validated');
          switching = true;
          _pendingRollback = true;
          _emitBackendCall(
              HdrBackendDiagnosticMethod.stop,
              HdrBackendDiagnosticBoundary.entered,
              generation,
              diagnosticAttempt,
              HdrBackendDiagnosticPurpose.normal);
          try {
            await backend.stop();
          } catch (error, stack) {
            _emitBackendCall(
                HdrBackendDiagnosticMethod.stop,
                HdrBackendDiagnosticBoundary.failed,
                generation,
                diagnosticAttempt,
                HdrBackendDiagnosticPurpose.normal,
                error: error,
                stack: stack);
            rethrow;
          }
          _emitBackendCall(
              HdrBackendDiagnosticMethod.stop,
              HdrBackendDiagnosticBoundary.returned,
              generation,
              diagnosticAttempt,
              HdrBackendDiagnosticPurpose.normal);
          _check(generation);
          mark('previous_output_stopped');
          _emitBackendCall(
              HdrBackendDiagnosticMethod.resetOwnedConfiguration,
              HdrBackendDiagnosticBoundary.entered,
              generation,
              diagnosticAttempt,
              HdrBackendDiagnosticPurpose.normal);
          try {
            await backend.resetOwnedConfiguration();
          } catch (error, stack) {
            _emitBackendCall(
                HdrBackendDiagnosticMethod.resetOwnedConfiguration,
                HdrBackendDiagnosticBoundary.failed,
                generation,
                diagnosticAttempt,
                HdrBackendDiagnosticPurpose.normal,
                error: error,
                stack: stack);
            rethrow;
          }
          _emitBackendCall(
              HdrBackendDiagnosticMethod.resetOwnedConfiguration,
              HdrBackendDiagnosticBoundary.returned,
              generation,
              diagnosticAttempt,
              HdrBackendDiagnosticPurpose.normal);
          _check(generation);
          _activeMedia = false;
          _diagnosticOwner = null;
          mark('configuration_reset');
          _diagnosticOwner = diagnosticAttempt;
          _emitBackendCall(
              HdrBackendDiagnosticMethod.prepareOutput,
              HdrBackendDiagnosticBoundary.entered,
              generation,
              diagnosticAttempt,
              HdrBackendDiagnosticPurpose.normal);
          try {
            await backend.prepareOutput(attemptPlan);
          } catch (error, stack) {
            _emitBackendCall(
                HdrBackendDiagnosticMethod.prepareOutput,
                HdrBackendDiagnosticBoundary.failed,
                generation,
                diagnosticAttempt,
                HdrBackendDiagnosticPurpose.normal,
                error: error,
                stack: stack);
            rethrow;
          }
          _emitBackendCall(
              HdrBackendDiagnosticMethod.prepareOutput,
              HdrBackendDiagnosticBoundary.returned,
              generation,
              diagnosticAttempt,
              HdrBackendDiagnosticPurpose.normal);
          _check(generation);
          mark('output_prepared');
          _emitBackendCall(
              HdrBackendDiagnosticMethod.configure,
              HdrBackendDiagnosticBoundary.entered,
              generation,
              diagnosticAttempt,
              HdrBackendDiagnosticPurpose.normal);
          try {
            await backend.configure(attemptPlan);
          } catch (error, stack) {
            _emitBackendCall(
                HdrBackendDiagnosticMethod.configure,
                HdrBackendDiagnosticBoundary.failed,
                generation,
                diagnosticAttempt,
                HdrBackendDiagnosticPurpose.normal,
                error: error,
                stack: stack);
            rethrow;
          }
          _emitBackendCall(
              HdrBackendDiagnosticMethod.configure,
              HdrBackendDiagnosticBoundary.returned,
              generation,
              diagnosticAttempt,
              HdrBackendDiagnosticPurpose.normal);
          _check(generation);
          mark('configured');
          _emitBackendCall(
              HdrBackendDiagnosticMethod.waitForOutput,
              HdrBackendDiagnosticBoundary.entered,
              generation,
              diagnosticAttempt,
              HdrBackendDiagnosticPurpose.normal);
          try {
            await backend.waitForOutput(attemptPlan).timeout(outputTimeout);
          } catch (error, stack) {
            _emitBackendCall(
                HdrBackendDiagnosticMethod.waitForOutput,
                HdrBackendDiagnosticBoundary.failed,
                generation,
                diagnosticAttempt,
                HdrBackendDiagnosticPurpose.normal,
                error: error,
                stack: stack);
            rethrow;
          }
          _emitBackendCall(
              HdrBackendDiagnosticMethod.waitForOutput,
              HdrBackendDiagnosticBoundary.returned,
              generation,
              diagnosticAttempt,
              HdrBackendDiagnosticPurpose.normal);
          _check(generation);
          mark('output_ready');
          _emitBackendCall(
              HdrBackendDiagnosticMethod.open,
              HdrBackendDiagnosticBoundary.entered,
              generation,
              diagnosticAttempt,
              HdrBackendDiagnosticPurpose.normal);
          try {
            await backend.open(attemptPlan, start: currentStart, play: play);
          } catch (error, stack) {
            _emitBackendCall(
                HdrBackendDiagnosticMethod.open,
                HdrBackendDiagnosticBoundary.failed,
                generation,
                diagnosticAttempt,
                HdrBackendDiagnosticPurpose.normal,
                error: error,
                stack: stack);
            rethrow;
          }
          _emitBackendCall(
              HdrBackendDiagnosticMethod.open,
              HdrBackendDiagnosticBoundary.returned,
              generation,
              diagnosticAttempt,
              HdrBackendDiagnosticPurpose.normal);
          _check(generation);
          mark('media_opened');
          late final HdrReviewFacts facts;
          _emitBackendCall(
              HdrBackendDiagnosticMethod.reviewFacts,
              HdrBackendDiagnosticBoundary.entered,
              generation,
              diagnosticAttempt,
              HdrBackendDiagnosticPurpose.normal);
          try {
            facts = await backend.reviewFacts(attemptPlan);
          } catch (error, stack) {
            _emitBackendCall(
                HdrBackendDiagnosticMethod.reviewFacts,
                HdrBackendDiagnosticBoundary.failed,
                generation,
                diagnosticAttempt,
                HdrBackendDiagnosticPurpose.normal,
                error: error,
                stack: stack);
            rethrow;
          }
          _emitBackendCall(
              HdrBackendDiagnosticMethod.reviewFacts,
              HdrBackendDiagnosticBoundary.returned,
              generation,
              diagnosticAttempt,
              HdrBackendDiagnosticPurpose.normal);
          _check(generation);
          mark('review_facts');
          final decide = review;
          final decision = decide == null
              ? HdrReviewDecision<P>.accept()
              : await decide(attemptPlan, facts);
          _check(generation);
          if (decision.reopen && !rebuilt) {
            // One review-driven in-place reopen per open (plan 1.4 step 8).
            rebuilt = true;
            attemptPlan = decision.nextPlan as P;
            diagnosticAttempt = _diagnosticAttempt(generation, attemptPlan);
            currentStart = decision.position;
            mark('review_reopen');
            continue;
          }
          mark('track_verified');
          _pendingRollback = false;
          _activeMedia = true;
          result.complete(
            HdrOpenResult<P>(
              decision.nextPlan ?? attemptPlan,
              generation,
            ),
          );
          return;
        } catch (error, stack) {
          mark('open_failed');
          // This callback still owns the side-effect queue even when a newer
          // request has invalidated it. A retry keeps the transaction inside
          // the same generation; anything else rolls back here so a successor
          // that fails during preparation cannot leave partial native
          // configuration behind. Like hdr_lab, a failure before the
          // transaction began switching (e.g. validate) leaves the currently
          // playing media untouched.
          if (!switching || error is OpenSuperseded || _invalid(generation)) {
            if (switching) {
              try {
                _emitBackendCall(
                    HdrBackendDiagnosticMethod.stop,
                    HdrBackendDiagnosticBoundary.entered,
                    generation,
                    diagnosticAttempt,
                    HdrBackendDiagnosticPurpose.rollback);
                try {
                  await backend.stop();
                } catch (error, stack) {
                  _emitBackendCall(
                      HdrBackendDiagnosticMethod.stop,
                      HdrBackendDiagnosticBoundary.failed,
                      generation,
                      diagnosticAttempt,
                      HdrBackendDiagnosticPurpose.rollback,
                      error: error,
                      stack: stack);
                  rethrow;
                }
                _emitBackendCall(
                    HdrBackendDiagnosticMethod.stop,
                    HdrBackendDiagnosticBoundary.returned,
                    generation,
                    diagnosticAttempt,
                    HdrBackendDiagnosticPurpose.rollback);
                _emitBackendCall(
                    HdrBackendDiagnosticMethod.resetOwnedConfiguration,
                    HdrBackendDiagnosticBoundary.entered,
                    generation,
                    diagnosticAttempt,
                    HdrBackendDiagnosticPurpose.rollback);
                try {
                  await backend.resetOwnedConfiguration();
                } catch (error, stack) {
                  _emitBackendCall(
                      HdrBackendDiagnosticMethod.resetOwnedConfiguration,
                      HdrBackendDiagnosticBoundary.failed,
                      generation,
                      diagnosticAttempt,
                      HdrBackendDiagnosticPurpose.rollback,
                      error: error,
                      stack: stack);
                  rethrow;
                }
                _emitBackendCall(
                    HdrBackendDiagnosticMethod.resetOwnedConfiguration,
                    HdrBackendDiagnosticBoundary.returned,
                    generation,
                    diagnosticAttempt,
                    HdrBackendDiagnosticPurpose.rollback);
                _pendingRollback = false;
                _activeMedia = false;
                _diagnosticOwner = null;
              } catch (_) {
                // Preserve the failure that caused this transaction to abort.
              }
            }
            result.completeError(error, stack);
            return;
          }
          P? next;
          final hook = retry;
          if (hook != null && retriesUsed < maxRetries) {
            try {
              next = await hook(attemptPlan, error);
            } catch (_) {
              try {
                _emitBackendCall(
                    HdrBackendDiagnosticMethod.stop,
                    HdrBackendDiagnosticBoundary.entered,
                    generation,
                    diagnosticAttempt,
                    HdrBackendDiagnosticPurpose.rollback);
                try {
                  await backend.stop();
                } catch (error, stack) {
                  _emitBackendCall(
                      HdrBackendDiagnosticMethod.stop,
                      HdrBackendDiagnosticBoundary.failed,
                      generation,
                      diagnosticAttempt,
                      HdrBackendDiagnosticPurpose.rollback,
                      error: error,
                      stack: stack);
                  rethrow;
                }
                _emitBackendCall(
                    HdrBackendDiagnosticMethod.stop,
                    HdrBackendDiagnosticBoundary.returned,
                    generation,
                    diagnosticAttempt,
                    HdrBackendDiagnosticPurpose.rollback);
                _emitBackendCall(
                    HdrBackendDiagnosticMethod.resetOwnedConfiguration,
                    HdrBackendDiagnosticBoundary.entered,
                    generation,
                    diagnosticAttempt,
                    HdrBackendDiagnosticPurpose.rollback);
                try {
                  await backend.resetOwnedConfiguration();
                } catch (error, stack) {
                  _emitBackendCall(
                      HdrBackendDiagnosticMethod.resetOwnedConfiguration,
                      HdrBackendDiagnosticBoundary.failed,
                      generation,
                      diagnosticAttempt,
                      HdrBackendDiagnosticPurpose.rollback,
                      error: error,
                      stack: stack);
                  rethrow;
                }
                _emitBackendCall(
                    HdrBackendDiagnosticMethod.resetOwnedConfiguration,
                    HdrBackendDiagnosticBoundary.returned,
                    generation,
                    diagnosticAttempt,
                    HdrBackendDiagnosticPurpose.rollback);
                _pendingRollback = false;
                _activeMedia = false;
                _diagnosticOwner = null;
              } catch (_) {
                // Preserve the failure that caused this transaction to abort.
              }
              result.completeError(error, stack);
              return;
            }
          }
          if (next != null && !_invalid(generation)) {
            retriesUsed++;
            attemptPlan = next;
            diagnosticAttempt = _diagnosticAttempt(generation, attemptPlan);
            currentStart = start;
            mark('retry_planned');
            // Re-enter the transaction: the loop-top rollback and the stop/
            // reset phases roll back the partial configuration of the failed
            // attempt (plan 1.4 step 5, "回到第 3 步").
            continue;
          }
          try {
            _emitBackendCall(
                HdrBackendDiagnosticMethod.stop,
                HdrBackendDiagnosticBoundary.entered,
                generation,
                diagnosticAttempt,
                HdrBackendDiagnosticPurpose.rollback);
            try {
              await backend.stop();
            } catch (error, stack) {
              _emitBackendCall(
                  HdrBackendDiagnosticMethod.stop,
                  HdrBackendDiagnosticBoundary.failed,
                  generation,
                  diagnosticAttempt,
                  HdrBackendDiagnosticPurpose.rollback,
                  error: error,
                  stack: stack);
              rethrow;
            }
            _emitBackendCall(
                HdrBackendDiagnosticMethod.stop,
                HdrBackendDiagnosticBoundary.returned,
                generation,
                diagnosticAttempt,
                HdrBackendDiagnosticPurpose.rollback);
            _emitBackendCall(
                HdrBackendDiagnosticMethod.resetOwnedConfiguration,
                HdrBackendDiagnosticBoundary.entered,
                generation,
                diagnosticAttempt,
                HdrBackendDiagnosticPurpose.rollback);
            try {
              await backend.resetOwnedConfiguration();
            } catch (error, stack) {
              _emitBackendCall(
                  HdrBackendDiagnosticMethod.resetOwnedConfiguration,
                  HdrBackendDiagnosticBoundary.failed,
                  generation,
                  diagnosticAttempt,
                  HdrBackendDiagnosticPurpose.rollback,
                  error: error,
                  stack: stack);
              rethrow;
            }
            _emitBackendCall(
                HdrBackendDiagnosticMethod.resetOwnedConfiguration,
                HdrBackendDiagnosticBoundary.returned,
                generation,
                diagnosticAttempt,
                HdrBackendDiagnosticPurpose.rollback);
            _pendingRollback = false;
            _activeMedia = false;
            _diagnosticOwner = null;
          } catch (_) {
            // Preserve the failure that caused this transaction to abort.
          }
          result.completeError(error, stack);
          return;
        }
      }
    });
    _tail = queued.catchError((Object _) {});
    return result.future;
  }

  /// Queues a session-scoped seek or diagnostic command behind native open.
  /// Callers must not put an unbounded wait or a sequence of unrelated
  /// commands inside [action]; split them so each checks the generation.
  Future<void> runForCurrent(
    HdrOpenResult<P> session,
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
    if (_activeMedia || _pendingRollback) {
      _emitBackendCall(
          HdrBackendDiagnosticMethod.stop,
          HdrBackendDiagnosticBoundary.entered,
          _generation,
          null,
          HdrBackendDiagnosticPurpose.disposal);
      try {
        await backend.stop();
      } catch (error, stack) {
        _emitBackendCall(
            HdrBackendDiagnosticMethod.stop,
            HdrBackendDiagnosticBoundary.failed,
            _generation,
            null,
            HdrBackendDiagnosticPurpose.disposal,
            error: error,
            stack: stack);
        rethrow;
      }
      _emitBackendCall(
          HdrBackendDiagnosticMethod.stop,
          HdrBackendDiagnosticBoundary.returned,
          _generation,
          null,
          HdrBackendDiagnosticPurpose.disposal);
      _emitBackendCall(
          HdrBackendDiagnosticMethod.resetOwnedConfiguration,
          HdrBackendDiagnosticBoundary.entered,
          _generation,
          null,
          HdrBackendDiagnosticPurpose.disposal);
      try {
        await backend.resetOwnedConfiguration();
      } catch (error, stack) {
        _emitBackendCall(
            HdrBackendDiagnosticMethod.resetOwnedConfiguration,
            HdrBackendDiagnosticBoundary.failed,
            _generation,
            null,
            HdrBackendDiagnosticPurpose.disposal,
            error: error,
            stack: stack);
        rethrow;
      }
      _emitBackendCall(
          HdrBackendDiagnosticMethod.resetOwnedConfiguration,
          HdrBackendDiagnosticBoundary.returned,
          _generation,
          null,
          HdrBackendDiagnosticPurpose.disposal);
      _pendingRollback = false;
      _activeMedia = false;
      _diagnosticOwner = null;
    }
  }
}
