import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit_hdr_lab/common/android_native_dv_session_lifecycle.dart';
import 'package:media_kit_hdr_lab/tests/01.single_player_single_video.dart';

class _Fixture {
  _Fixture({Future<void> Function(Map<String, Object?> report)? onWrite}) {
    run = AndroidNativeDvSessionLifecycleRun(
      durationSeconds: 900,
      externalIdentityLabel: 'page-exit-test',
      writeOverride: (report) async {
        writes.add(Map<String, Object?>.from(report));
        await onWrite?.call(report);
      },
    );
    run.setActionEnabled('close-and-exit', true);
    run.setActionEnabled('Pause10Resume', true);
    run.setActionEnabled('ManualResume', true);
  }
  final control = AndroidNativeDvSessionPageExitController();
  late final AndroidNativeDvSessionLifecycleRun run;
  final writes = <Map<String, Object?>>[];
  final order = <String>[];
  final errors = <Object>[];
  Future<void>? startup;
  bool attempted = false;
  bool failTermination = false;
  int requests = 0;

  bool enabled(String id) =>
      control.actionEnabled(run, id, terminationAttempted: attempted);

  Future<void> back() => control.requestExit(
        getRun: () => run,
        getStartup: () => startup,
        terminationAttempted: () => attempted,
        nextRequestId: () => 'exit-${++requests}',
        terminateOwnedPlayer: () async {
          expect(run.busy && run.currentActionId != 'close-and-exit', false);
          attempted = true;
          order.add('terminate');
          if (failTermination) throw StateError('owned termination failed');
        },
        exit: () async {
          expect(run.closed, true);
          expect(writes.last['closed'], true);
          order.add('exit');
        },
        reportFailure: errors.add,
      );
}

void main() {
  test('healthy Close awaits cleanup and final report before exit', () async {
    final f = _Fixture();
    expect(f.enabled('close-and-exit'), true);
    await f.back();
    expect(f.order, ['terminate', 'exit']);
    expect(f.run.debt, false);
    expect(f.run.actionEvents.single['phase'], 'end-certified');
    expect(f.errors, isEmpty);
  });

  for (final state in ['debt', 'terminal']) {
    test('$state enables recovery Close without a spurious admission error',
        () async {
      final f = _Fixture();
      if (state == 'debt') {
        f.run.markDebt('original failure');
      } else {
        f.run.markTerminal(reason: 'original terminal');
      }
      expect(f.enabled('close-and-exit'), true);
      expect(f.enabled('Pause10Resume'), false);
      await f.back();
      expect(f.order, ['terminate', 'exit']);
      expect(f.run.debt, state == 'debt');
      expect(
          f.run.toJson()['error'], state == 'debt' ? 'original failure' : null);
      expect(f.run.actionEvents, isEmpty,
          reason: 'recovery is cleanup, never a successful action certificate');
      expect(f.errors, isEmpty);
    });
  }

  test('Back waits for real busy action and its report write to settle',
      () async {
    final finalWriteEntered = Completer<void>();
    final finalWriteRelease = Completer<void>();
    var holdFinalWrite = true;
    final f = _Fixture(onWrite: (report) async {
      final events = report['actionEvents'] as List;
      if (holdFinalWrite &&
          report['currentAction'] == null &&
          events.any((event) =>
              event['actionId'] == 'Pause10Resume' &&
              event['phase'] == 'end-certified')) {
        holdFinalWrite = false;
        finalWriteEntered.complete();
        await finalWriteRelease.future;
      }
    });
    final entered = Completer<void>();
    final release = Completer<void>();
    final action = f.control.runAction(() async {
      await f.run.runAction(
        actionId: 'Pause10Resume',
        requestId: 'busy-action',
        action: (_) async {
          entered.complete();
          await release.future;
          f.order.add('action-settled');
        },
      );
      f.run.setActionEnabled('close-and-exit', false,
          reason: 'page disables admission while Back waits');
      f.order.add('report-settled');
    });
    await entered.future;
    expect(f.enabled('close-and-exit'), false);
    final exit = f.back();
    expect(f.control.exitRequested, true);
    expect(f.enabled('Pause10Resume'), false);
    await expectLater(
        f.control.runAction(() async => fail('new action')), throwsStateError);
    await Future<void>.delayed(Duration.zero);
    expect(f.order, isEmpty);
    expect(f.attempted, false);
    release.complete();
    await finalWriteEntered.future;
    expect(f.attempted, false,
        reason: 'busy=false is insufficient while the final write is pending');
    finalWriteRelease.complete();
    await action;
    await exit;
    expect(f.run.debt, false);
    expect(f.order, ['action-settled', 'report-settled', 'terminate', 'exit']);
  });

  test(
      'Close drains ManualResume observation and certificate before termination',
      () async {
    final f = _Fixture();
    final owner = Object();
    AndroidNativeDvManualResumeState state(bool playing, int position) =>
        AndroidNativeDvManualResumeState(
            session: owner,
            sessionInstanceId: 's',
            startupAccepted: true,
            playing: playing,
            completed: false,
            buffering: false,
            position: Duration(seconds: position));
    final expected = state(false, 30);
    var current = expected;
    final observationEntered = Completer<void>();
    final observationRelease = Completer<void>();
    var playCalls = 0;
    expect(f.enabled('ManualResume'), true);
    final action = f.control.runAction(() => f.run.runAction(
        actionId: 'ManualResume',
        requestId: 'resume',
        action: (_) async {
          await runAndroidNativeDvManualResume(
              run: f.run,
              requestId: 'resume',
              expected: expected,
              readState: () => current,
              play: () async {
                playCalls++;
                current = state(true, 30);
                f.order.add('play');
              },
              observePlayback: (duration) async {
                expect(duration, const Duration(seconds: 10));
                observationEntered.complete();
                await observationRelease.future;
                current = state(true, 40);
                f.order.add('observed');
              });
        }));
    await observationEntered.future;
    expect(f.enabled('ManualResume'), false);
    await expectLater(
        f.run.runAction(
            actionId: 'ManualResume',
            requestId: 'second',
            action: (_) async => fail('concurrent action')),
        throwsStateError);
    final closing = f.back();
    await expectLater(
        f.control.runAction(() async => fail('queued after exit')),
        throwsStateError);
    await Future<void>.delayed(Duration.zero);
    expect(f.attempted, false);
    expect(f.run.closed, false);
    expect(f.order, ['play']);
    observationRelease.complete();
    await action;
    await closing;
    expect(playCalls, 1);
    expect(f.order, ['play', 'observed', 'terminate', 'exit']);
    expect(f.run.actionEvents.first['actionId'], 'ManualResume');
    expect(f.run.actionEvents.first['phase'], 'end-certified');
    expect(f.errors, isEmpty);
    expect(f.run.debt, false);
  });

  test('failed pending action still drains and preserves debt', () async {
    final f = _Fixture();
    final entered = Completer<void>();
    final release = Completer<void>();
    final action = f.control.runAction(() async {
      await f.run.runAction(
        actionId: 'Pause10Resume',
        requestId: 'failed-action',
        action: (_) async {
          entered.complete();
          await release.future;
          throw StateError('original action failed');
        },
      );
    });
    final actionFailure = expectLater(action, throwsStateError);
    await entered.future;
    final exit = f.back();
    await Future<void>.delayed(Duration.zero);
    expect(f.attempted, false);
    release.complete();
    await actionFailure;
    await exit;
    expect(f.order, ['terminate', 'exit']);
    expect(f.run.debt, true);
    expect(f.run.actionEvents.single['phase'], 'error');
    expect(f.errors.map((e) => '$e').join(' '),
        contains('original action failed'));
  });

  test('Back reads startup after assignment and waits through startup failure',
      () async {
    final f = _Fixture();
    final release = Completer<void>();
    final first = f.back();
    // Mirrors the initState Future assignment before its first continuation.
    f.startup = release.future;
    await Future<void>.delayed(Duration.zero);
    expect(f.attempted, false);
    release.completeError(StateError('startup failed'));
    await first;
    expect(f.order, ['terminate', 'exit']);
    expect(f.run.debt, true);
    expect(f.errors.map((e) => '$e').join(' '), contains('startup failed'));
    expect(f.run.actionEvents, isEmpty);
  });

  test('repeated Back and Close share one pending and completed attempt',
      () async {
    final f = _Fixture();
    final release = Completer<void>();
    f.startup = release.future;
    final a = f.back();
    final b = f.back();
    expect(identical(a, b), true);
    release.complete();
    await Future.wait([a, b]);
    await f.back();
    expect(f.order, ['terminate', 'exit']);
    expect(f.requests, 1);
    expect(f.enabled('close-and-exit'), false);
  });

  test('termination failure finalizes debt before exit without retry',
      () async {
    final f = _Fixture()..failTermination = true;
    await f.back();
    await f.back();
    expect(f.order, ['terminate', 'exit']);
    expect(f.run.debt, true);
    expect(f.run.actionEvents.single['phase'], 'error');
    expect(f.errors.map((e) => '$e').join(' '),
        contains('owned termination failed'));
  });

  test('failed final report keeps page error and repeated Back never exits',
      () async {
    var finalWrites = 0;
    final f = _Fixture(onWrite: (report) async {
      if (report['closed'] == true) {
        finalWrites++;
        throw StateError('page final snapshot write failed');
      }
    });
    await f.back();
    expect(f.order, ['terminate']);
    expect(f.run.closed, true);
    expect(f.control.exitRequested, true);
    expect(f.enabled('close-and-exit'), false);
    expect(f.errors.single.toString(),
        contains('Final lifecycle report completion failed'));
    expect(f.errors.single.toString(),
        contains('page final snapshot write failed'));
    final retainedError = f.errors.single;
    await f.back();
    expect(f.order, ['terminate']);
    expect(finalWrites, 1);
    expect(f.errors.single, same(retainedError));
  });

  test('already closed or termination attempted does not repeat termination',
      () async {
    for (final alreadyClosed in [false, true]) {
      final f = _Fixture();
      if (alreadyClosed) {
        await f.run.close();
      } else {
        f.attempted = true;
      }
      expect(f.enabled('close-and-exit'), false);
      await f.back();
      expect(f.order, isEmpty);
      expect(f.requests, 0);
      if (!f.run.closed) await f.run.close();
    }
  });

  test('untracked busy work fails closed instead of concurrent termination',
      () async {
    final f = _Fixture();
    final entered = Completer<void>();
    final release = Completer<void>();
    final work = f.run.runAction(
      actionId: 'Pause10Resume',
      requestId: 'untracked',
      action: (_) async {
        entered.complete();
        await release.future;
      },
    );
    await entered.future;
    await expectLater(f.back(), throwsStateError);
    expect(f.attempted, false);
    release.complete();
    await work;
    expect(f.control.exitRequested, false);
    await f.back();
    expect(f.order, ['terminate', 'exit']);
  });

  test('UI failure reporting cannot bypass cleanup after pending failure',
      () async {
    final f = _Fixture();
    final release = Completer<void>();
    f.startup = release.future;
    var reportCalls = 0;
    final exit = f.control.requestExit(
      getRun: () => f.run,
      getStartup: () => f.startup,
      terminationAttempted: () => f.attempted,
      nextRequestId: () => 'report-failure',
      terminateOwnedPlayer: () async {
        f.attempted = true;
        f.order.add('terminate');
      },
      exit: () async {
        expect(f.run.closed, true);
        f.order.add('exit');
      },
      reportFailure: (_) {
        reportCalls++;
        throw StateError('UI report failed');
      },
    );
    await Future<void>.delayed(Duration.zero);
    release.completeError(StateError('startup failed'));
    await exit;
    expect(reportCalls, greaterThan(0));
    expect(f.order, ['terminate', 'exit']);
    expect(f.run.debt, true);
  });

  test('missing run disposes owned resources once and retains page error',
      () async {
    final control = AndroidNativeDvSessionPageExitController();
    var terminated = false;
    var disposeCount = 0;
    var exitCount = 0;
    Future<void> back() => control.requestExit(
          getRun: () => null,
          getStartup: () => null,
          terminationAttempted: () => terminated,
          nextRequestId: () => 'unused',
          terminateOwnedPlayer: () async {
            terminated = true;
            disposeCount++;
          },
          exit: () async => exitCount++,
          reportFailure: (_) {},
        );
    await expectLater(back(), throwsStateError);
    await expectLater(back(), throwsStateError);
    expect(disposeCount, 1);
    expect(exitCount, 0);
  });
}
