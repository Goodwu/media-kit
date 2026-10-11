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
  }

  @override
  Future<void> configure(FakePlan plan) async {
    calls.add('configure:${plan.path}');
    await heldConfigure?.future;
    if (failConfigure) {
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
  }

  @override
  Future<HdrReviewFacts> reviewFacts(FakePlan plan) async {
    calls.add('review:${plan.path}');
    return const HdrReviewFacts();
  }

  @override
  HdrBackendObservation observe() => const HdrBackendObservation();
}

FakePlan plan(String path) => FakePlan(path);

void main() {
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
    await expectLater(coordinator.openSource('A'),
        throwsA(isA<HdrOutputBindTimeout>().having((error) => error.cause, 'cause', same(raw))));
    expect(diagnostics.where((event) =>
        event.method == HdrBackendDiagnosticMethod.waitForOutput &&
        event.boundary == HdrBackendDiagnosticBoundary.failed).single.error,
        same(raw));
    expect(backend.calls, isNot(contains('open:A')));
    expect(backend.calls.skip(backend.calls.length - 2), ['stop', 'reset']);
    await coordinator.dispose();
  });

  test('exact readiness wrapper preserves cause, stack, and typed identity', () async {
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

  test('review reopen budget is finite and rejects invalid configuration', () async {
    for (final value in [-1, 5]) {
      expect(() => HdrOpenCoordinator<String, FakePlan>(FakeBackend(),
        preparer: (source, _) async => plan(source), maxReviewReopens: value),
        throwsArgumentError);
    }
    for (final limit in [0, 3]) {
      final backend = FakeBackend();
      var count = 0;
      final coordinator = HdrOpenCoordinator<String, FakePlan>(backend,
        preparer: (source, _) async => plan(source), maxReviewReopens: limit,
        review: (_, __) async => HdrReviewDecision<FakePlan>.reopen(
          Duration.zero, plan('rebuild-${++count}')));
      await expectLater(coordinator.openSource('A'), throwsA(isA<HdrReviewReopenLimit>()));
      expect(backend.calls.where((call) => call.startsWith('open:')), hasLength(limit + 1));
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
    test('second review disagreement retains failed $cleanup cleanup debt', () async {
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
          return HdrReviewDecision<FakePlan>.reopen(Duration.zero, plan('A-rebuilt'));
        },
      );
      await expectLater(coordinator.openSource('A'),
          throwsA(isA<HdrReviewReopenLimit>()));
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
}
