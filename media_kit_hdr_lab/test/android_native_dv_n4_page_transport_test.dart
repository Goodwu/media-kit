// ignore_for_file: implementation_imports, depend_on_referenced_packages
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_hdr_lab/common/android_native_dv_session_foreign_ownership.dart';
import 'package:media_kit_hdr_lab/tests/01.single_player_single_video.dart';
import 'package:synchronized/synchronized.dart';

void main() {
  group('N4 page admission', () {
    test('requires fixed P5 HDR Session diagnostic and excludes other modes',
        () {
      String? check({
        bool android = true,
        bool transaction = true,
        bool diagnostic = true,
        bool n1 = false,
        bool performance = false,
        bool lifecycle = false,
        bool hdr10 = false,
      }) =>
          validateAndroidNativeDvN4PageAdmission(
            android: android,
            hdrTransaction: transaction,
            sessionDiagnostic: diagnostic,
            negativeN1: n1,
            performance: performance,
            lifecycle: lifecycle,
            hdr10: hdr10,
          );

      expect(check(), isNull);
      expect(check(android: false), contains('requires Android'));
      expect(check(transaction: false), contains('HDR_TRANSACTION'));
      expect(check(diagnostic: false), contains('Session diagnostic'));
      expect(check(n1: true), contains('excludes'));
      expect(check(performance: true), contains('excludes'));
      expect(check(lifecycle: true), contains('excludes'));
      expect(check(hdr10: true), contains('excludes'));
    });
  });

  group('N4 page transport', () {
    const source = 'https://fixture.invalid/fixed-p5.mp4';

    test('raw open dispatches exact P5 URI on the bound Player', () async {
      final player = _CapturePlayer();
      final run = AndroidNativeDvSessionForeignOwnershipRun(
        player: player,
        verifiedP5Source: source,
        transport: 'transportStub',
      );
      final transport = AndroidNativeDvN4PageTransport(
        player: player,
        source: source,
        currentSource: () => source,
        run: run,
      );

      await transport.openSamePlayerRaw(player, source);

      expect(player.openCalls, 1);
      expect(player.lastPlayable, isA<Media>());
      expect((player.lastPlayable! as Media).uri, source);
      expect(player.synchronizedOpen, isTrue);
    });

    test('raw open rejects a different Player or source before dispatch',
        () async {
      final player = _CapturePlayer();
      final other = _CapturePlayer();
      final run = AndroidNativeDvSessionForeignOwnershipRun(
        player: player,
        verifiedP5Source: source,
        transport: 'transportStub',
      );
      final transport = AndroidNativeDvN4PageTransport(
        player: player,
        source: source,
        currentSource: () => source,
        run: run,
      );

      expect(
        () => transport.openSamePlayerRaw(other, source),
        throwsA(isA<StateError>()),
      );
      expect(
        () => transport.openSamePlayerRaw(
            player, 'https://fixture.invalid/other.mp4'),
        throwsA(isA<StateError>()),
      );
      expect(player.openCalls, 0);
      expect(other.openCalls, 0);
    });

    test('transport cannot run until real session callback gate becomes ready',
        () async {
      final player = _CapturePlayer();
      final run = AndroidNativeDvSessionForeignOwnershipRun(
        player: player,
        verifiedP5Source: source,
        transport: 'transportStub',
      );
      final transport = AndroidNativeDvN4PageTransport(
        player: player,
        source: source,
        currentSource: () => source,
        run: run,
      );

      expect(transport.ready, isFalse);
      await expectLater(transport.execute(), throwsA(isA<StateError>()));
      expect(player.openCalls, 0);
    });

    test('close request synchronously closes page admission', () async {
      final player = _CapturePlayer();
      final run = AndroidNativeDvSessionForeignOwnershipRun(
        player: player,
        verifiedP5Source: source,
        transport: 'transportStub',
      );
      final transport = AndroidNativeDvN4PageTransport(
        player: player,
        source: source,
        currentSource: () => source,
        run: run,
      );

      transport.stopAdmission();

      expect(transport.ready, isFalse);
      await expectLater(transport.execute(), throwsA(isA<StateError>()));
      expect(player.openCalls, 0);
    });
  });

  group('N4 production page close/exit sequence', () {
    test(
        'explicit Run disposal failure persists then holds exit with original error',
        () async {
      final error = StateError('Player.dispose failed after N4 Run');
      final result = _result(
        playerTerminated: false,
        playerDisposeError: error,
      );
      final harness = _CloseHarness(result: result);

      await expectLater(harness.exit(), throwsA(same(error)));

      expect(harness.popCount, 0);
      expect(harness.snapshot!.playerTerminationSucceeded, isFalse);
      expect(harness.snapshot!.result, same(result));
      expect(harness.persistCount, 1);
    });

    test('never-Run disposal failure persists journal then holds exit',
        () async {
      final error = StateError('Player.dispose failed without Run');
      final harness = _CloseHarness(
        journal: [
          {'kind': 'player-dispose-threw', 'error': error.toString()},
          {'kind': 'player-termination', 'success': false},
        ],
        terminationError: error,
      );

      await expectLater(harness.exit(), throwsA(same(error)));

      expect(harness.popCount, 0);
      expect(harness.snapshot!.playerTerminationSucceeded, isFalse);
      expect(harness.snapshot!.journal.last['success'], isFalse);
      expect(harness.persistCount, 1);
    });

    test('owner debt does not block pop when Player termination succeeded',
        () async {
      final result = _result(
        playerTerminated: true,
        sessionDebtObserved: true,
      );
      final harness = _CloseHarness(result: result);

      await harness.exit();

      expect(harness.snapshot!.result!.sessionDebtObserved, isTrue);
      expect(harness.snapshot!.playerTerminationSucceeded, isTrue);
      expect(harness.popCount, 1);
    });

    test('diagnostic close and event cancellation errors are in final report',
        () async {
      final closeError = StateError('diagnostic close error');
      final cancelError = StateError('event cancel error');
      final harness = _CloseHarness(
        result: _result(playerTerminated: true),
        diagnosticError: closeError,
        cancelError: cancelError,
      );

      await harness.exit();

      expect(harness.order.indexOf('helper-close'),
          lessThan(harness.order.indexOf('event-cancel')));
      expect(harness.order.indexOf('event-cancel'),
          lessThan(harness.order.indexOf('drain')));
      expect(harness.order.indexOf('drain'),
          lessThan(harness.order.indexOf('persist')));
      expect(harness.order.indexOf('persist'),
          lessThan(harness.order.indexOf('pop')));
      expect(harness.snapshot!.errors.map((error) => error.error),
          containsAll([closeError, cancelError]));
      expect(harness.snapshot!.result!.playerTerminated, isTrue);
      expect(harness.popCount, 1);
    });

    test('final atomic report failure preserves error and holds exit',
        () async {
      final renameError = FileSystemException('rename failed');
      final harness = _CloseHarness(
        result: _result(playerTerminated: true),
        persistError: renameError,
      );

      await expectLater(harness.exit(), throwsA(same(renameError)));

      expect(harness.order, contains('persist'));
      expect(harness.popCount, 0);
    });

    test('permanently pending execution keeps exit pending and does not pop',
        () async {
      final pending = Completer<void>();
      final harness = _CloseHarness(
        journal: [
          {'kind': 'player-termination', 'success': true},
        ],
        waitExecution: () => pending.future,
      );

      final exit = harness.exit();
      await Future<void>.delayed(Duration.zero);

      expect(harness.sequence.admissionClosed, isTrue);
      expect(harness.popCount, 0);
      expect(harness.order, isNot(contains('helper-close')));

      pending.complete();
      await exit;
      expect(harness.popCount, 1);
    });

    test('normal never-Run termination evidence persists before pop', () async {
      final harness = _CloseHarness(
        journal: [
          {'kind': 'player-termination', 'success': true},
        ],
      );

      await harness.exit();

      expect(harness.snapshot!.result, isNull);
      expect(harness.snapshot!.playerTerminationSucceeded, isTrue);
      expect(harness.order.indexOf('persist'),
          lessThan(harness.order.indexOf('pop')));
      expect(harness.popCount, 1);
    });
  });
}

AndroidNativeDvForeignOwnershipResult _result({
  required bool playerTerminated,
  Object? playerDisposeError,
  bool sessionDebtObserved = false,
}) =>
    AndroidNativeDvForeignOwnershipResult(
      n4ExecutionAdmitted: true,
      foreignFileLoadedMatched: true,
      sameSessionGenerationAfterForeign: true,
      sameForeignIdentityAfterSessionDispose: true,
      optionsUnchangedAcrossSessionDispose: true,
      lastDisposeReportClean: false,
      coordinatorError: null,
      coordinatorErrorType: null,
      coordinatorErrorText: null,
      sessionDisposeThrown: null,
      sessionDisposeThrownStack: null,
      sessionDebtObserved: sessionDebtObserved,
      ownershipStopRefusalObserved: true,
      noSessionOpenOrConfigureAfterForeign: true,
      controllerRetiredObserved: true,
      controllerNativeSurfaceActiveBeforeDispose: true,
      controllerNativeSurfaceActiveAfterDispose: false,
      playerTerminated: playerTerminated,
      playerDisposeError: playerDisposeError,
      playerDisposeStack:
          playerDisposeError == null ? null : StackTrace.current,
      ownerRestoration: 'not-claimed',
      backendStopIssued: 'unknown',
      backendStopIssuedBasis: 'test stub',
      boundOutputWithdrawnObserved: null,
      boundOutputHandleBeforeDispose: null,
      boundOutputGenerationBeforeDispose: null,
      boundOutputViewIdBeforeDispose: null,
      boundOutputWidBeforeDispose: null,
      boundOutputHandleAfterDispose: null,
      boundOutputGenerationAfterDispose: null,
      boundOutputViewIdAfterDispose: null,
      boundOutputWidAfterDispose: null,
      n4DeviceAcceptance: false,
      transport: 'transportStub',
      executionError: null,
      executionStack: null,
      evidenceGaps: const [],
      journal: const [],
      rawErrors: const [],
      overflow: false,
      rawErrorOverflow: false,
    );

class _CloseHarness {
  _CloseHarness({
    this.result,
    this.journal = const [],
    this.terminationError,
    this.diagnosticError,
    this.cancelError,
    this.persistError,
    this.waitExecution,
  });

  final AndroidNativeDvForeignOwnershipResult? result;
  final List<Map<String, Object?>> journal;
  final Object? terminationError;
  final Object? diagnosticError;
  final Object? cancelError;
  final Object? persistError;
  final Future<void> Function()? waitExecution;
  final AndroidNativeDvN4PageCloseSequence sequence =
      AndroidNativeDvN4PageCloseSequence();
  final List<String> order = [];
  AndroidNativeDvN4PageCloseSnapshot? snapshot;
  int popCount = 0;
  int persistCount = 0;

  Future<void> exit() => sequence.exit(
        closeAndPersist: () => sequence.closeAndPersist(
          closeAdmission: () => order.add('close-admission'),
          waitStartup: () async => order.add('startup'),
          waitExecution: () async {
            order.add('execution');
            await waitExecution?.call();
          },
          result: () => result,
          closeDiagnostic: () async {
            order.add('diagnostic-close');
            if (diagnosticError != null) throw diagnosticError!;
          },
          closeHelper: () async => order.add('helper-close'),
          cancelEvents: () async {
            order.add('event-cancel');
            if (cancelError != null) throw cancelError!;
          },
          drain: () async {
            order.add('drain');
            return journal;
          },
          playerTerminationSucceeded:
              androidNativeDvN4PlayerTerminationSucceeded,
          terminationError: (_) => terminationError,
          terminationStack: (_) => StackTrace.current,
          persistFinalReport: (value) async {
            order.add('persist');
            persistCount++;
            snapshot = value;
            if (persistError != null) throw persistError!;
          },
        ),
        pop: () async {
          order.add('pop');
          popCount++;
        },
      );
}

class _CapturePlayer implements Player {
  @override
  final Lock lock = Lock();
  int openCalls = 0;
  Playable? lastPlayable;
  bool? synchronizedOpen;
  @override
  int fileLoadedEpoch = 1;

  @override
  Future<void> open(Playable playable,
      {bool play = true, bool synchronized = true}) async {
    openCalls++;
    lastPlayable = playable;
    synchronizedOpen = synchronized;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
