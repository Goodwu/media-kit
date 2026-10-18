import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit_video/src/hdr/hdr_open_coordinator.dart';
import 'package:media_kit_video/src/hdr/hdr_open_plan.dart';

/// Migrated from hdr_lab's `android_hdr_open_coordinator_test.dart`. The
/// sample-identity verification is now the session's plan preparation, so
/// the fake verifier became a fake preparer and the four staged-private-copy
/// cases (which tested sample byte staging) were not migrated.
class FakePlan {
  FakePlan(this.path);
  final String path;
}

class FakeBackend implements HdrOpenBackend<FakePlan> {
  final calls = <String>[];
  Completer<void>? heldOpen;
  Completer<void>? heldOutput;
  Completer<void>? heldConfigure;
  Completer<void>? heldPrepareOutput;
  TimeoutException? outputError;
  bool failConfigure = false;
  bool failStopOnce = false;
  bool failResetOnce = false;
  bool failValidate = false;

  /// Plan paths whose next [configure] call fails once (candidate retry).
  final failuresPerConfigure = <String>{};

  /// One-shot phase failures.
  Object? prepareErrorOnce;
  Object? openErrorOnce;
  Object? reviewErrorOnce;

  @override
  Future<void> validate(FakePlan plan) async {
    if (failValidate) throw StateError('unsupported output policy');
  }

  @override
  Future<void> stop() async {
    calls.add('stop');
    if (failStopOnce) {
      failStopOnce = false;
      throw StateError('stop failed');
    }
  }

  @override
  Future<void> resetOwnedConfiguration() async {
    calls.add('reset');
    if (failResetOnce) {
      failResetOnce = false;
      throw StateError('reset failed');
    }
  }

  @override
  Future<void> prepareOutput(FakePlan plan) async {
    calls.add('prepare:${plan.path}');
    await heldPrepareOutput?.future;
    final error = prepareErrorOnce;
    if (error != null) {
      prepareErrorOnce = null;
      throw error;
    }
  }

  @override
  Future<void> configure(FakePlan plan) async {
    calls.add('configure:${plan.path}');
    await heldConfigure?.future;
    if (failConfigure) {
      throw StateError('configuration failed');
    }
    if (failuresPerConfigure.remove(plan.path)) {
      throw StateError('configuration failed');
    }
  }

  @override
  Future<void> waitForOutput(FakePlan plan) async {
    calls.add('output:${plan.path}');
    if (outputError != null) throw outputError!;
    await heldOutput?.future;
  }

  @override
  Future<void> open(
    FakePlan plan, {
    Duration? start,
    required bool play,
  }) async {
    calls.add('open:${plan.path}');
    await heldOpen?.future;
    final error = openErrorOnce;
    if (error != null) {
      openErrorOnce = null;
      throw error;
    }
  }

  @override
  Future<HdrReviewFacts> reviewFacts(FakePlan plan) async {
    calls.add('review:${plan.path}');
    final error = reviewErrorOnce;
    if (error != null) {
      reviewErrorOnce = null;
      throw error;
    }
    return const HdrReviewFacts();
  }

  @override
  HdrBackendObservation observe() => const HdrBackendObservation();
}

FakePlan plan(String path) => FakePlan(path);

void main() {
  test('queued stop invalidates slow preparation and allows a later legal open',
      () async {
    final held = Completer<FakePlan>();
    final backend = FakeBackend();
    final c = HdrOpenCoordinator<String, FakePlan>(backend,
        preparer: (source, _) =>
            source == 'stale' ? held.future : Future.value(plan(source)));
    await c.openSource('active');
    final stale = c.openSource('stale');
    await c.stopAndReset();
    held.complete(plan('stale'));
    await expectLater(stale, throwsA(isA<OpenSuperseded>()));
    expect(backend.calls, isNot(contains('configure:stale')));
    await c.openSource('new');
    expect(backend.calls, contains('open:new'));
    await c.dispose();
  });
  test('queued stop waits for old side effects and failed cleanup retains debt',
      () async {
    final backend = FakeBackend()..heldConfigure = Completer<void>();
    final c = HdrOpenCoordinator<String, FakePlan>(backend,
        preparer: (source, _) async => plan(source));
    final pending = c.openSource('old');
    while (!backend.calls.contains('configure:old')) {
      await Future<void>.delayed(Duration.zero);
    }
    final oldCalls = backend.calls.length;
    final stopped = c.stopAndReset();
    await Future<void>.delayed(Duration.zero);
    expect(backend.calls.length, oldCalls);
    backend.heldConfigure!.complete();
    await expectLater(pending, throwsA(isA<OpenSuperseded>()));
    await stopped;
    expect(backend.calls, isNot(contains('open:old')));
    await c.openSource('active');
    backend.failStopOnce = true;
    await expectLater(c.stopAndReset(), throwsStateError);
    final before = backend.calls.length;
    await c.openSource('new');
    expect(backend.calls.skip(before).take(2), ['stop', 'reset']);
    expect(backend.calls.skip(before), contains('configure:new'));
    await c.dispose();
  });

  test('successful direct open is stopped and reset on coordinator dispose',
      () async {
    final backend = FakeBackend();
    final coordinator = HdrOpenCoordinator<String, FakePlan>(
      backend,
      preparer: (source, _) async => plan(source),
    );
    await coordinator.openSource('A');
    final before = backend.calls.length;
    await coordinator.dispose();
    expect(backend.calls.skip(before), ['stop', 'reset']);
  });

  test('dispose retries reset after a successful open', () async {
    final backend = FakeBackend();
    final coordinator = HdrOpenCoordinator<String, FakePlan>(
      backend,
      preparer: (source, _) async => plan(source),
    );
    await coordinator.openSource('A');
    backend.failResetOnce = true;
    await expectLater(coordinator.dispose(), throwsStateError);
    await coordinator.dispose();
    expect(backend.calls.where((call) => call == 'reset').length, 3);
  });

  test('slow verification cannot open after a newer request', () async {
    final aVerified = Completer<FakePlan>();
    final backend = FakeBackend();
    final coordinator = HdrOpenCoordinator<String, FakePlan>(
      backend,
      preparer: (source, _) => source == 'A'
          ? aVerified.future
          : Future<FakePlan>.value(plan(source)),
    );
    final a = coordinator.openSource('A');
    final b = coordinator.openSource('B');
    final bResult = await b;
    expect(bResult.plan.path, 'B');
    expect(bResult.presentationVerified, isFalse);
    aVerified.complete(plan('A'));
    await expectLater(a, throwsA(isA<OpenSuperseded>()));
    expect(backend.calls.where((call) => call == 'open:A'), isEmpty);
    await coordinator.dispose();
  });

  test('old native open finishes before newer request starts side effects',
      () async {
    final backend = FakeBackend()..heldOpen = Completer<void>();
    final coordinator = HdrOpenCoordinator<String, FakePlan>(
      backend,
      preparer: (source, _) async => plan(source),
    );
    final a = coordinator.openSource('A');
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(backend.calls, contains('open:A'));
    final b = coordinator.openSource('B');
    backend.heldOpen!.complete();
    await expectLater(a, throwsA(isA<OpenSuperseded>()));
    expect((await b).plan.path, 'B');
    expect(backend.calls, contains('open:B'));
    expect(backend.calls, isNot(contains('review:A')));
    await coordinator.dispose();
  });

  test('configuration failure resets, and later request recovers', () async {
    final backend = FakeBackend()..failConfigure = true;
    final coordinator = HdrOpenCoordinator<String, FakePlan>(
      backend,
      preparer: (source, _) async => plan(source),
    );
    await expectLater(coordinator.openSource('A'), throwsStateError);
    expect(backend.calls.sublist(backend.calls.length - 2), ['stop', 'reset']);
    backend.failConfigure = false;
    expect((await coordinator.openSource('B')).plan.path, 'B');
    await coordinator.dispose();
  });

  test('unsupported policy leaves currently playing media untouched', () async {
    final backend = FakeBackend();
    final coordinator = HdrOpenCoordinator<String, FakePlan>(
      backend,
      preparer: (source, _) async => plan(source),
    );
    await coordinator.openSource('A');
    final stopCount = backend.calls.where((call) => call == 'stop').length;
    backend.failValidate = true;
    await expectLater(coordinator.openSource('B'), throwsStateError);
    expect(backend.calls.where((call) => call == 'stop').length, stopCount);
    expect(backend.calls, isNot(contains('open:B')));
    await coordinator.dispose();
  });

  test('invalid successor rolls back superseded partial configuration',
      () async {
    final backend = FakeBackend()..heldConfigure = Completer<void>();
    final coordinator = HdrOpenCoordinator<String, FakePlan>(
      backend,
      preparer: (source, _) async => plan(source),
    );
    final a = coordinator.openSource('A');
    while (!backend.calls.contains('configure:A')) {
      await Future<void>.delayed(Duration.zero);
    }
    backend.failValidate = true;
    final b = coordinator.openSource('B');
    backend.heldConfigure!.complete();
    await expectLater(a, throwsA(isA<OpenSuperseded>()));
    await expectLater(b, throwsStateError);
    expect(backend.calls, [
      'stop',
      'reset',
      'prepare:A',
      'configure:A',
      'stop',
      'reset',
    ]);
    expect(backend.calls, isNot(contains('open:A')));
    expect(backend.calls, isNot(contains('open:B')));
    await coordinator.dispose();
  });

  test('preparation failure of successor still rolls back partial config',
      () async {
    final backend = FakeBackend()..heldConfigure = Completer<void>();
    final coordinator = HdrOpenCoordinator<String, FakePlan>(
      backend,
      preparer: (source, _) async {
        if (source == 'B') throw StateError('unknown sample');
        return plan(source);
      },
    );
    final a = coordinator.openSource('A');
    while (!backend.calls.contains('configure:A')) {
      await Future<void>.delayed(Duration.zero);
    }
    final b = coordinator.openSource('B');
    await expectLater(b, throwsStateError);
    backend.heldConfigure!.complete();
    await expectLater(a, throwsA(isA<OpenSuperseded>()));
    expect(backend.calls, [
      'stop',
      'reset',
      'prepare:A',
      'configure:A',
      'stop',
      'reset',
    ]);
    await coordinator.dispose();
  });

  test('output preparation is serialized and superseded before configure',
      () async {
    final backend = FakeBackend()..heldPrepareOutput = Completer<void>();
    final coordinator = HdrOpenCoordinator<String, FakePlan>(
      backend,
      preparer: (source, _) async => plan(source),
    );
    final a = coordinator.openSource('A');
    while (!backend.calls.contains('prepare:A')) {
      await Future<void>.delayed(Duration.zero);
    }
    final b = coordinator.openSource('B');
    backend.heldPrepareOutput!.complete();
    await expectLater(a, throwsA(isA<OpenSuperseded>()));
    expect((await b).plan.path, 'B');
    expect(backend.calls.indexOf('prepare:A'),
        lessThan(backend.calls.indexOf('prepare:B')));
    expect(backend.calls, isNot(contains('configure:A')));
    await coordinator.dispose();
  });

  test('output timeout releases the queue for a later request', () async {
    final backend = FakeBackend()..heldOutput = Completer<void>();
    final coordinator = HdrOpenCoordinator<String, FakePlan>(
      backend,
      outputTimeout: const Duration(milliseconds: 20),
      preparer: (source, _) async => plan(source),
    );
    await expectLater(
        coordinator.openSource('A'), throwsA(isA<HdrOutputBindTimeout>()));
    expect(backend.calls, isNot(contains('open:A')));
    backend.heldOutput = null;
    expect((await coordinator.openSource('B')).plan.path, 'B');
    await coordinator.dispose();
  });

  test('dispose invalidates an in-flight request', () async {
    final backend = FakeBackend()..heldOpen = Completer<void>();
    final coordinator = HdrOpenCoordinator<String, FakePlan>(
      backend,
      preparer: (source, _) async => plan(source),
    );
    final open = coordinator.openSource('A');
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    final disposing = coordinator.dispose();
    backend.heldOpen!.complete();
    await expectLater(open, throwsA(isA<OpenSuperseded>()));
    await disposing;
    expect(backend.calls, isNot(contains('review:A')));
  });

  test('delayed command from an older session cannot affect new media',
      () async {
    final backend = FakeBackend();
    final coordinator = HdrOpenCoordinator<String, FakePlan>(
      backend,
      preparer: (source, _) async => plan(source),
    );
    final a = await coordinator.openSource('A');
    final b = coordinator.openSource('B');
    await expectLater(
      coordinator.runForCurrent(a, () async => backend.calls.add('seek:A')),
      throwsA(isA<OpenSuperseded>()),
    );
    await b;
    expect(backend.calls, isNot(contains('seek:A')));
    await coordinator.dispose();
  });

  test('retry hook re-runs the transaction within the same generation',
      () async {
    final backend = FakeBackend()..failConfigure = true;
    final coordinator = HdrOpenCoordinator<String, FakePlan>(
      backend,
      maxRetries: 1,
      retry: (plan, error) async {
        backend.failConfigure = false;
        return FakePlan('${plan.path}-retry');
      },
      preparer: (source, _) async => plan(source),
    );
    final result = await coordinator.openSource('A');
    expect(result.plan.path, 'A-retry');
    // The retry's loop-top rollback (stop/reset of the failed attempt) plus
    // the follow-up transaction's own stop/reset phases.
    expect(backend.calls, [
      'stop',
      'reset',
      'prepare:A',
      'configure:A',
      'stop',
      'reset',
      'stop',
      'reset',
      'prepare:A-retry',
      'configure:A-retry',
      'output:A-retry',
      'open:A-retry',
      'review:A-retry',
    ]);
    await coordinator.dispose();
  });

  test('output timeout preserves the raw diagnostic and cause', () async {
    final raw = TimeoutException('backend bind timeout');
    final backend = FakeBackend()..outputError = raw;
    final diagnostics = <HdrBackendCallDiagnostic<FakePlan>>[];
    final coordinator = HdrOpenCoordinator<String, FakePlan>(
      backend,
      preparer: (source, _) async => plan(source),
      onBackendCallDiagnostic: diagnostics.add,
    );
    await expectLater(
        coordinator.openSource('A'),
        throwsA(isA<HdrOutputBindTimeout>()
            .having((error) => error.cause, 'cause', same(raw))));
    expect(
        diagnostics
            .where((event) =>
                event.method == HdrBackendDiagnosticMethod.waitForOutput &&
                event.boundary == HdrBackendDiagnosticBoundary.failed)
            .single
            .error,
        same(raw));
    expect(backend.calls, isNot(contains('open:A')));
    expect(backend.calls.skip(backend.calls.length - 2), ['stop', 'reset']);
    await coordinator.dispose();
  });

  test('exact readiness wrapper preserves cause, stack, and typed identity',
      () async {
    final raw = TimeoutException('Surface binding timeout');
    final stack = StackTrace.fromString('original-readiness-stack');
    try {
      await HdrOutputBindTimeout.waitFor(Future<void>.error(raw, stack));
      fail('readiness timeout must fail');
    } on HdrOutputBindTimeout catch (error, caughtStack) {
      expect(error.cause, same(raw));
      expect(caughtStack.toString(), contains('original-readiness-stack'));
    }
    final typed = HdrOutputBindTimeout(raw);
    await expectLater(HdrOutputBindTimeout.waitFor(Future<void>.error(typed)),
        throwsA(same(typed)));
    final other = StateError('output owner lost');
    await expectLater(HdrOutputBindTimeout.waitFor(Future<void>.error(other)),
        throwsA(same(other)));
  });

  test('review reopen budget is finite and rejects invalid configuration',
      () async {
    for (final value in [-1, 5]) {
      expect(
          () => HdrOpenCoordinator<String, FakePlan>(FakeBackend(),
              preparer: (source, _) async => plan(source),
              maxReviewReopens: value),
          throwsArgumentError);
    }
    for (final limit in [0, 3]) {
      final backend = FakeBackend();
      var count = 0;
      final coordinator = HdrOpenCoordinator<String, FakePlan>(backend,
          preparer: (source, _) async => plan(source),
          maxReviewReopens: limit,
          review: (_, __) async => HdrReviewDecision<FakePlan>.reopen(
              Duration.zero, plan('rebuild-${++count}')));
      await expectLater(
          coordinator.openSource('A'), throwsA(isA<HdrReviewReopenLimit>()));
      expect(backend.calls.where((call) => call.startsWith('open:')),
          hasLength(limit + 1));
      expect(count, limit + 1);
      await coordinator.dispose();
    }
  });

  test('a second review reopen fails closed without retry or third open',
      () async {
    final backend = FakeBackend();
    var reviews = 0;
    var retries = 0;
    final coordinator = HdrOpenCoordinator<String, FakePlan>(
      backend,
      preparer: (source, _) async => plan(source),
      review: (current, _) async => HdrReviewDecision<FakePlan>.reopen(
        Duration.zero,
        plan('A-rebuild-${++reviews}'),
      ),
      retry: (current, error) async {
        retries++;
        return plan('A-retry');
      },
      maxRetries: 2,
    );
    await expectLater(
        coordinator.openSource('A'), throwsA(isA<HdrReviewReopenLimit>()));
    expect(reviews, 2);
    expect(retries, 0);
    expect(backend.calls.where((call) => call.startsWith('open:')),
        ['open:A', 'open:A-rebuild-1']);
    expect(backend.calls.skip(backend.calls.length - 2), ['stop', 'reset']);
    await coordinator.dispose();
  });

  for (final cleanup in ['stop', 'reset']) {
    test('second review disagreement retains failed $cleanup cleanup debt',
        () async {
      final backend = FakeBackend();
      var reviews = 0;
      final coordinator = HdrOpenCoordinator<String, FakePlan>(
        backend,
        preparer: (source, _) async => plan(source),
        review: (current, _) async {
          if (!current.path.startsWith('A')) {
            return const HdrReviewDecision<FakePlan>.accept();
          }
          if (++reviews == 2) {
            if (cleanup == 'stop') {
              backend.failStopOnce = true;
            } else {
              backend.failResetOnce = true;
            }
          }
          return HdrReviewDecision<FakePlan>.reopen(
              Duration.zero, plan('A-rebuilt'));
        },
      );
      await expectLater(
          coordinator.openSource('A'), throwsA(isA<HdrReviewReopenLimit>()));
      final beforeBlocked = backend.calls.length;
      if (cleanup == 'stop') {
        backend.failStopOnce = true;
      } else {
        backend.failResetOnce = true;
      }
      await expectLater(coordinator.openSource('B'), throwsStateError);
      expect(backend.calls.skip(beforeBlocked),
          cleanup == 'stop' ? ['stop'] : ['stop', 'reset']);
      expect(backend.calls, isNot(contains('prepare:B')));
      expect(backend.calls, isNot(contains('open:B')));
      final beforeRecovery = backend.calls.length;
      expect((await coordinator.openSource('C')).plan.path, 'C');
      expect(backend.calls.skip(beforeRecovery).take(2), ['stop', 'reset']);
      expect(backend.calls.where((call) => call.startsWith('open:')),
          ['open:A', 'open:A-rebuilt', 'open:C']);
      await coordinator.dispose();
    });
  }

  test('review reopen re-opens in place once within the generation', () async {
    final backend = FakeBackend();
    final reopened = FakePlan('A-rebuilt');
    var reviewed = false;
    final coordinator = HdrOpenCoordinator<String, FakePlan>(
      backend,
      review: (plan, facts) async {
        if (reviewed) return HdrReviewDecision<FakePlan>.accept();
        reviewed = true;
        return HdrReviewDecision<FakePlan>.reopen(
          const Duration(seconds: 3),
          reopened,
        );
      },
      preparer: (source, _) async => plan(source),
    );
    final result = await coordinator.openSource('A', start: Duration.zero);
    expect(result.plan.path, 'A-rebuilt');
    expect(backend.calls, contains('open:A'));
    expect(backend.calls, contains('open:A-rebuilt'));
    await coordinator.dispose();
  });

  group('attempt cleanup', () {
    test('a delayed cleanup future blocks the result completion', () async {
      final gate = Completer<void>();
      final cleaned = <String>[];
      final coordinator = HdrOpenCoordinator<String, FakePlan>(
        FakeBackend(),
        preparer: (source, _) async => plan(source),
        attemptCleanup: (attempt) {
          cleaned.add(attempt.path);
          return gate.future;
        },
      );
      var done = false;
      final opened = coordinator.openSource('A').then((_) => done = true);
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(done, isFalse,
          reason: 'the disarm barrier must complete before the result');
      gate.complete();
      await opened;
      expect(done, isTrue);
      expect(cleaned, ['A']);
      await coordinator.dispose();
    });

    test('cleanup runs per attempt across candidate retry and review reopen',
        () async {
      final backend = FakeBackend()..failuresPerConfigure.add('A');
      final cleaned = <String>[];
      var reviews = 0;
      final coordinator = HdrOpenCoordinator<String, FakePlan>(
        backend,
        preparer: (source, _) async => plan(source),
        retry: (failed, error) async => plan('${failed.path}-retry'),
        maxRetries: 1,
        review: (current, _) async {
          if (reviews++ == 0) {
            return HdrReviewDecision<FakePlan>.reopen(
                Duration.zero, plan('${current.path}-reopen'));
          }
          return const HdrReviewDecision<FakePlan>.accept();
        },
        attemptCleanup: (attempt) async => cleaned.add(attempt.path),
      );
      final result = await coordinator.openSource('A');
      expect(result.plan.path, 'A-retry-reopen');
      // Every execution attempt ends with its own cleanup, in execution
      // order, before its successor starts.
      expect(cleaned, ['A', 'A-retry', 'A-retry-reopen']);
      await coordinator.dispose();
    });

    test('cleanup failure on the success path fails the open without retry',
        () async {
      final backend = FakeBackend();
      var retries = 0;
      final coordinator = HdrOpenCoordinator<String, FakePlan>(
        backend,
        preparer: (source, _) async => plan(source),
        retry: (failed, error) async {
          retries++;
          return plan('retry');
        },
        maxRetries: 2,
        attemptCleanup: (attempt) async {
          if (attempt.path == 'A') throw StateError('disarm failed');
        },
      );
      await expectLater(coordinator.openSource('A'),
          throwsA(isA<HdrAttemptCleanupFailure>()));
      expect(retries, 0, reason: 'a cleanup failure never degrades the route');
      // The media that had opened is rolled back before the failure lands.
      expect(backend.calls.skip(backend.calls.length - 2), ['stop', 'reset']);
      await coordinator.dispose();
    });

    test('cleanup failure on the retry path keeps the original error',
        () async {
      final backend = FakeBackend()..failuresPerConfigure.add('A');
      final cleaned = <String>[];
      var retries = 0;
      final coordinator = HdrOpenCoordinator<String, FakePlan>(
        backend,
        preparer: (source, _) async => plan(source),
        retry: (failed, error) async {
          retries++;
          return plan('retry');
        },
        maxRetries: 2,
        attemptCleanup: (attempt) async {
          cleaned.add(attempt.path);
          if (attempt.path == 'A') throw StateError('disarm failed');
        },
      );
      await expectLater(coordinator.openSource('A'), throwsStateError);
      expect(retries, 1,
          reason: 'the retry was planned but not admitted over uncleared arms');
      // The failed cleanup is retried once more after the rollback — the
      // disarm gets a second chance before the open error lands.
      expect(cleaned, ['A', 'A']);
      expect(backend.calls, isNot(contains('prepare:retry')));
      expect(backend.calls, isNot(contains('open:retry')));
      await coordinator.dispose();
    });

    test('cleanup runs after rollback on every phase failure and supersede',
        () async {
      void Function(FakeBackend) scriptFor(String phase) {
        switch (phase) {
          case 'prepare':
            return (b) => b.prepareErrorOnce = StateError('p');
          case 'configure':
            return (b) => b.failConfigure = true;
          case 'open':
            return (b) => b.openErrorOnce = StateError('o');
          default:
            return (b) => b.reviewErrorOnce = StateError('r');
        }
      }

      for (final phase in ['prepare', 'configure', 'open', 'review']) {
        final backend = FakeBackend();
        scriptFor(phase)(backend);
        final cleaned = <String>[];
        final coordinator = HdrOpenCoordinator<String, FakePlan>(
          backend,
          preparer: (source, _) async => plan(source),
          attemptCleanup: (attempt) async => cleaned.add(attempt.path),
        );
        await expectLater(
            coordinator.openSource('A'), throwsA(isA<StateError>()));
        expect(cleaned, ['A'],
            reason: 'cleanup must run after the $phase failure');
        expect(backend.calls.skip(backend.calls.length - 2), ['stop', 'reset']);
        await coordinator.dispose();
      }

      // A superseded attempt is also cleaned: its queued catch runs before
      // the successor's side effects start.
      final backend = FakeBackend()..heldOpen = Completer<void>();
      final cleaned = <String>[];
      final coordinator = HdrOpenCoordinator<String, FakePlan>(
        backend,
        preparer: (source, _) async => plan(source),
        attemptCleanup: (attempt) async => cleaned.add(attempt.path),
      );
      final stale = coordinator.openSource('A');
      while (!backend.calls.contains('open:A')) {
        await Future<void>.delayed(Duration.zero);
      }
      final fresh = coordinator.openSource('B');
      backend.heldOpen!.complete();
      await expectLater(stale, throwsA(isA<OpenSuperseded>()));
      await fresh;
      expect(cleaned.first, 'A');
      expect(cleaned, contains('B'));
      await coordinator.dispose();
    });

    test('dispose re-runs the last attempt cleanup once (double dispose)',
        () async {
      final backend = FakeBackend();
      final cleaned = <String>[];
      final coordinator = HdrOpenCoordinator<String, FakePlan>(
        backend,
        preparer: (source, _) async => plan(source),
        attemptCleanup: (attempt) async => cleaned.add(attempt.path),
      );
      await coordinator.openSource('A');
      expect(cleaned, ['A']);
      await coordinator.dispose();
      await coordinator.dispose();
      // The success cleanup plus exactly one terminal re-run.
      expect(cleaned, ['A', 'A']);
      expect(coordinator.dispose(), completes);
    });

    test('a cleanup error at dispose stays best-effort', () async {
      var failures = 0;
      final coordinator = HdrOpenCoordinator<String, FakePlan>(
        FakeBackend(),
        preparer: (source, _) async => plan(source),
        attemptCleanup: (attempt) async {
          failures++;
          throw StateError('still armed');
        },
      );
      final failing = coordinator.openSource('A');
      // The attempt result fails with the cleanup failure...
      await expectLater(failing, throwsA(isA<HdrAttemptCleanupFailure>()));
      // ...and dispose still completes (the owner keeps its debt). Three
      // cleanup invocations: the success-path barrier, the post-rollback
      // retry, and the terminal dispose re-run.
      await expectLater(coordinator.dispose(), completes);
      expect(failures, 3);
    });

    test('a throwing retry hook still ends its attempt (B4)', () async {
      final backend = FakeBackend()..failuresPerConfigure.add('A');
      final coordinator = HdrOpenCoordinator<String, FakePlan>(
        backend,
        preparer: (source, _) async => plan(source),
        retry: (failed, error) async => throw StateError('hook exploded'),
        maxRetries: 1,
        attemptCleanup: (attempt) async =>
            backend.calls.add('cleanup:${attempt.path}'),
      );
      await expectLater(coordinator.openSource('A'), throwsStateError);
      // The exit edge that forgot the terminal cleanup: the rollback runs
      // first, then the attempt ends, then the original failure lands.
      expect(backend.calls, [
        'stop',
        'reset',
        'prepare:A',
        'configure:A',
        'stop',
        'reset',
        'cleanup:A',
      ]);
      await coordinator.dispose();
    });

    test('supersede during the pending terminal cleanup fails the attempt '
        '(B6)', () async {
      final backend = FakeBackend();
      final gate = Completer<void>();
      final coordinator = HdrOpenCoordinator<String, FakePlan>(
        backend,
        preparer: (source, _) async => plan(source),
        attemptCleanup: (attempt) => gate.future,
      );
      final stale = coordinator.openSource('A');
      while (!backend.calls.contains('review:A')) {
        await Future<void>.delayed(Duration.zero);
      }
      // A newer request supersedes the generation while the terminal
      // cleanup is still pending.
      final fresh = coordinator.openSource('B');
      gate.complete();
      await expectLater(stale, throwsA(isA<OpenSuperseded>()));
      await fresh;
      // The superseded attempt took the controlled rollback path AFTER its
      // cleanup completed: no active media was published for it, and the
      // successor's transaction ran to completion on a clean queue.
      expect(backend.calls.indexOf('review:A'),
          lessThan(backend.calls.indexOf('open:B')));
      expect(backend.calls.lastIndexOf('stop'),
          greaterThan(backend.calls.indexOf('review:A')));
      await coordinator.dispose();
    });

    test('dispose during the pending terminal cleanup fails the attempt '
        '(B6)', () async {
      final backend = FakeBackend();
      final gate = Completer<void>();
      var cleanups = 0;
      final coordinator = HdrOpenCoordinator<String, FakePlan>(
        backend,
        preparer: (source, _) async => plan(source),
        attemptCleanup: (attempt) async {
          cleanups++;
          await gate.future;
        },
      );
      final stale = coordinator.openSource('A');
      while (!backend.calls.contains('review:A')) {
        await Future<void>.delayed(Duration.zero);
      }
      final disposing = coordinator.dispose();
      gate.complete();
      await expectLater(stale, throwsA(isA<OpenSuperseded>()));
      await disposing;
      // The invalidated attempt never completed as a success: its queued
      // transaction rolled back (stop/reset after the review), and the
      // terminal dispose re-run only saw an already-ended attempt.
      expect(backend.calls.sublist(backend.calls.indexOf('review:A')),
          isNot(contains('review:A'.replaceFirst('review', 'open'))));
      expect(backend.calls.skipWhile((c) => c != 'review:A').length,
          greaterThanOrEqualTo(3),
          reason: 'review, then the post-cleanup rollback (stop/reset)');
      expect(cleanups, greaterThanOrEqualTo(1));
    });
  });
}
