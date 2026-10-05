// ignore_for_file: implementation_imports, depend_on_referenced_packages
import 'dart:async';
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:media_kit_video/src/hdr/android_mediacodec_configuration.dart';
import 'package:media_kit_video/src/hdr/hdr_disposal.dart';
import 'package:media_kit_video/src/hdr/hdr_native_dv_option_owner.dart';
import 'package:media_kit_video/src/hdr/hdr_native_dv_review_evidence.dart';
import 'package:media_kit_video/src/hdr/hdr_open_coordinator.dart';
import 'package:media_kit_video/src/video_controller/android_video_controller/platform_surface_release.dart';
import 'package:media_kit_video/src/video_controller/android_video_controller/android_video_controller.dart';
import 'package:media_kit_hdr_lab/tests/01.single_player_single_video.dart';
import 'package:media_kit_hdr_lab/common/android_native_dv_session_foreign_ownership.dart';
import 'package:synchronized/synchronized.dart';

const _source = '/same/verified/p5.mp4';
const _instanceId = 'host-transport-stub-session';
const _generation = 7;

void main() {
  test('N4 binding distinguishes wrapper, real platform and current tuple', () {
    final fixture = _Fixture();
    bool matches(VideoController current, VideoController accepted,
            HdrNativeDvReviewEvidence evidence) =>
        androidNativeDvN4ControllerMatches(
          player: fixture.player,
          currentWrapper: current,
          acceptedWrapper: accepted,
          evidence: evidence,
        );
    expect(identical(fixture.controller, fixture.platformOutput), isFalse);
    expect(matches(fixture.controller, fixture.controller, fixture.evidence),
        isTrue);
    expect(
        matches(fixture.controller, fixture.controller,
            fixture.evidence.copyWithController(fixture.controller)),
        isFalse);
    final replacement =
        _FakeVideoController(fixture.player, fixture.platformOutput);
    expect(matches(replacement, fixture.controller, fixture.evidence), isFalse);
    fixture.platformOutput.currentBoundOutputIdentity = null;
    expect(matches(fixture.controller, fixture.controller, fixture.evidence),
        isFalse);
    fixture.platformOutput.currentBoundOutputIdentity =
        const AndroidSurfaceAccountId(
            handle: 10, generation: 2, viewId: 3, surfaceGeneration: 5, wid: 5);
    expect(matches(fixture.controller, fixture.controller, fixture.evidence),
        isFalse);
  });

  test('old evidence naming wrapper is refused by consumer and never raw-opens',
      () async {
    final fixture = _Fixture();
    fixture.run.bindSession(fixture.session, _instanceId);
    fixture.run.onConsumerValidated(
        callbackSession: fixture.session,
        sessionInstanceId: _instanceId,
        generation: _generation,
        plan: fixture.plan,
        facts: fixture.facts.copyWithEvidence(
            fixture.evidence.copyWithController(fixture.controller)));
    fixture.run.onSessionEvent(
        callbackSession: fixture.session,
        sessionInstanceId: _instanceId,
        event: fixture.routeAppliedEvent);
    final result = await _executeFixture(fixture);
    expect(result.n4ExecutionAdmitted, isFalse);
    expect(fixture.player.openCalls, 0);
    expect(
        fixture.run.journal
            .firstWhere((r) => r['kind'] == 'consumer-validated')['accepted'],
        isFalse);
  });

  test('replaced wrapper sharing platform is refused before RouteApplied',
      () async {
    final fixture = _Fixture();
    fixture.run.bindSession(fixture.session, _instanceId);
    fixture.run.onConsumerValidated(
        callbackSession: fixture.session,
        sessionInstanceId: _instanceId,
        generation: _generation,
        plan: fixture.plan,
        facts: fixture.facts);
    fixture.session._controller.value =
        _FakeVideoController(fixture.player, fixture.platformOutput);
    fixture.run.onSessionEvent(
        callbackSession: fixture.session,
        sessionInstanceId: _instanceId,
        event: fixture.routeAppliedEvent);
    expect(fixture.run.journal.last['accepted'], isFalse);
    final result = await _executeFixture(fixture);
    expect(result.n4ExecutionAdmitted, isFalse);
    expect(fixture.player.openCalls, 0);
  });

  test(
      'execution rechecks wrapper, platform, tuple, generation, source and epoch',
      () async {
    for (final drift in [
      'wrapper',
      'platform',
      'tuple',
      'generation',
      'source',
      'epoch'
    ]) {
      final fixture = _Fixture();
      fixture.bindAndAccept();
      switch (drift) {
        case 'wrapper':
          fixture.session._controller.value =
              _FakeVideoController(fixture.player, fixture.platformOutput);
          break;
        case 'platform':
          fixture.controller.notifier.value =
              _FakePlatformOutput(fixture.player);
          break;
        case 'tuple':
          fixture.platformOutput.currentBoundOutputIdentity = null;
          break;
        case 'generation':
          fixture.session.setReport(fixture.session.report.value
              .copyWith(generation: _generation + 1));
          break;
        case 'source':
          fixture.player.properties['path'] = '/foreign/p5.mp4';
          break;
        case 'epoch':
          fixture.player.fileLoadedEpoch++;
          break;
      }
      final result = await _executeFixture(fixture);
      expect(result.n4ExecutionAdmitted, isFalse, reason: drift);
      expect(fixture.player.openCalls, 0, reason: drift);
    }
  });

  for (final drift in [
    'tuple',
    'platform',
    'wrapper',
    'generation',
    'epoch',
    'close'
  ]) {
    test('pre-open capture refuses async $drift drift without raw open',
        () async {
      final fixture = _Fixture();
      fixture.bindAndAccept();
      var changedDuringCapture = false;
      Future<void>? closeFuture;
      fixture.player.onGetProperty = (name) {
        if (name != 'time-pos' || changedDuringCapture) return;
        changedDuringCapture = true;
        expect(fixture.player.fileLoadedEpoch, 9);
        expect(fixture.player.openCalls, 0);
        switch (drift) {
          case 'tuple':
            fixture.platformOutput.currentBoundOutputIdentity = null;
            break;
          case 'platform':
            fixture.controller.notifier.value =
                _FakePlatformOutput(fixture.player);
            break;
          case 'wrapper':
            fixture.session._controller.value =
                _FakeVideoController(fixture.player, fixture.platformOutput);
            break;
          case 'generation':
            fixture.session.setReport(fixture.session.report.value
                .copyWith(generation: _generation + 1));
            break;
          case 'epoch':
            fixture.player.fileLoadedEpoch++;
            break;
          case 'close':
            closeFuture = fixture.run.close();
            break;
        }
      };
      final result = await _executeFixture(fixture);
      await closeFuture;
      expect(changedDuringCapture, isTrue);
      expect(result.n4ExecutionAdmitted, isFalse);
      expect(fixture.player.openCalls, 0);
      expect(result.executionError, isA<StateError>());
      expect(runErrorPreserved(fixture.run, result.executionError!), isTrue);
    });
  }

  test(
      'actual page consumer and RouteApplied chain admits the two-layer binding',
      () async {
    final fixture = _Fixture();
    final transport = AndroidNativeDvN4PageTransport(
        player: fixture.player,
        source: _source,
        currentSource: () => _source,
        run: fixture.run);
    transport.bindSession(fixture.session, _instanceId);
    transport.onConsumerValidated(
        callbackSession: fixture.session,
        sessionInstanceId: _instanceId,
        generation: _generation,
        plan: fixture.plan,
        facts: fixture.facts);
    expect(transport.ready, isFalse);
    transport.onSessionEvent(
        callbackSession: fixture.session,
        sessionInstanceId: _instanceId,
        event: fixture.routeAppliedEvent);
    expect(transport.ready, isTrue);
    final result = await transport.execute();
    expect(result.n4ExecutionAdmitted, isTrue);
    expect(result.foreignFileLoadedMatched, isTrue);
    expect(fixture.player.openCalls, 1);
    expect(result.controllerRetiredObserved, isTrue);
    expect(result.n4DeviceAcceptance, isFalse);
  });

  test(
      'clean dispose derives backendStopIssued and observes bound-output withdrawal',
      () async {
    final fixture = _Fixture();
    fixture.session.onDispose = () {
      fixture.platformOutput.currentBoundOutputIdentity = null;
    };
    final transport = AndroidNativeDvN4PageTransport(
        player: fixture.player,
        source: _source,
        currentSource: () => _source,
        run: fixture.run);
    transport.bindSession(fixture.session, _instanceId);
    transport.onConsumerValidated(
        callbackSession: fixture.session,
        sessionInstanceId: _instanceId,
        generation: _generation,
        plan: fixture.plan,
        facts: fixture.facts);
    transport.onSessionEvent(
        callbackSession: fixture.session,
        sessionInstanceId: _instanceId,
        event: fixture.routeAppliedEvent);
    final result = await transport.execute();
    expect(result.backendStopIssued, 'issued-inferred-from-clean-dispose-report');
    expect(
        result.evidenceGaps,
        isNot(
            contains('backend-stop-issued-state-unobservable')));
    expect(result.boundOutputWithdrawnObserved, isTrue);
    expect(result.boundOutputHandleBeforeDispose, 10);
    expect(result.boundOutputGenerationBeforeDispose, 2);
    expect(result.boundOutputViewIdBeforeDispose, 3);
    expect(result.boundOutputWidBeforeDispose, 5);
    expect(result.boundOutputHandleAfterDispose, isNull);
    expect(result.boundOutputWidAfterDispose, isNull);
    expect(
        result.evidenceGaps,
        isNot(contains(
            'bound-output-identity-not-withdrawn-after-dispose')));
    expect(
        result.evidenceGaps,
        isNot(contains('bound-output-identity-not-observed-before-dispose')));
  });

  test('retained bound output after dispose records not-withdrawn gap',
      () async {
    final fixture = _Fixture();
    final transport = AndroidNativeDvN4PageTransport(
        player: fixture.player,
        source: _source,
        currentSource: () => _source,
        run: fixture.run);
    transport.bindSession(fixture.session, _instanceId);
    transport.onConsumerValidated(
        callbackSession: fixture.session,
        sessionInstanceId: _instanceId,
        generation: _generation,
        plan: fixture.plan,
        facts: fixture.facts);
    transport.onSessionEvent(
        callbackSession: fixture.session,
        sessionInstanceId: _instanceId,
        event: fixture.routeAppliedEvent);
    final result = await transport.execute();
    expect(result.boundOutputWithdrawnObserved, isFalse);
    expect(result.boundOutputHandleBeforeDispose, 10);
    expect(result.boundOutputHandleAfterDispose, 10);
    expect(
        result.evidenceGaps,
        contains('bound-output-identity-not-withdrawn-after-dispose'));
  });

  test(
      'page readiness and execution refuse successor wrapper/platform and identity drift',
      () async {
    for (final drift in [
      'wrapper',
      'platform',
      'tuple',
      'generation',
      'source',
      'epoch',
      'foreign-session',
      'close'
    ]) {
      final fixture = _Fixture();
      var currentSource = _source;
      final transport = AndroidNativeDvN4PageTransport(
          player: fixture.player,
          source: _source,
          currentSource: () => currentSource,
          run: fixture.run);
      transport.bindSession(fixture.session, _instanceId);
      transport.onConsumerValidated(
          callbackSession: fixture.session,
          sessionInstanceId: _instanceId,
          generation: _generation,
          plan: fixture.plan,
          facts: fixture.facts);
      transport.onSessionEvent(
          callbackSession: fixture.session,
          sessionInstanceId: _instanceId,
          event: fixture.routeAppliedEvent);
      expect(transport.ready, isTrue, reason: drift);
      switch (drift) {
        case 'wrapper':
          fixture.session._controller.value =
              _FakeVideoController(fixture.player, fixture.platformOutput);
          break;
        case 'platform':
          fixture.controller.notifier.value =
              _FakePlatformOutput(fixture.player);
          break;
        case 'tuple':
          fixture.platformOutput.currentBoundOutputIdentity = null;
          break;
        case 'generation':
          fixture.session.setReport(fixture.session.report.value
              .copyWith(generation: _generation + 1));
          break;
        case 'source':
          currentSource = '/foreign/p5.mp4';
          break;
        case 'epoch':
          fixture.player.fileLoadedEpoch++;
          break;
        case 'foreign-session':
          transport.onConsumerValidated(
              callbackSession: _FakeSession(
                  _generation, fixture.controller, fixture.platformOutput),
              sessionInstanceId: _instanceId,
              generation: _generation,
              plan: fixture.plan,
              facts: fixture.facts);
          break;
        case 'close':
          transport.stopAdmission();
          break;
      }
      expect(transport.ready, isFalse, reason: drift);
      await expectLater(transport.execute(), throwsStateError, reason: drift);
      expect(fixture.player.openCalls, 0, reason: drift);
      await transport.close();
    }
  });

  test(
      'paired acceptance drives raw same-Player open and records dirty dispose',
      () async {
    final fixture = _Fixture();
    final run = fixture.run;
    fixture.bindAndAccept();
    final coordinatorError = StateError('foreign owner blocks owned stop');
    fixture.session.coordinatorError = coordinatorError;

    final result = await run.execute(
      rawPlayerOpen: (player, uri) async {
        expect(identical(player, fixture.player), isTrue);
        expect(uri, _source);
        await fixture.player.open(Media(uri));
      },
      fileLoadedTimeout: const Duration(milliseconds: 100),
    );

    expect(result.transport, 'transportStub');
    expect(result.n4ExecutionAdmitted, isTrue);
    expect(result.foreignFileLoadedMatched, isTrue);
    expect(result.sameSessionGenerationAfterForeign, isTrue);
    expect(result.sameForeignIdentityAfterSessionDispose, isTrue);
    expect(result.optionsUnchangedAcrossSessionDispose, isTrue);
    expect(result.lastDisposeReportClean, isFalse);
    expect(identical(result.coordinatorError, coordinatorError), isTrue);
    expect(result.coordinatorErrorType, 'StateError');
    expect(result.sessionDebtObserved, isTrue);
    expect(result.noSessionOpenOrConfigureAfterForeign, isTrue);
    expect(result.controllerRetiredObserved, isTrue);
    expect(result.playerTerminated, isTrue);
    expect(result.ownerRestoration, 'not-claimed');
    expect(result.backendStopIssued,
        'issued-verify-failed-coordinator-error');
    expect(result.n4DeviceAcceptance, isFalse);
    expect(result.ownershipStopRefusalObserved, isTrue);
    expect(result.acceptedByHostEvidence, isTrue);
    expect(result.evidenceGaps,
        contains('backend-stop-issued-state-unobservable'));
    expect(fixture.player.openCalls, 1);
    expect(fixture.player.lastOpenSynchronized, isTrue);
    expect(fixture.session.sessionOpenCalls, 0);
    expect(fixture.session.disposeCalls, 1);
    expect(fixture.player.disposeCalls, 1);
    expect(
        run.rawErrors.any((e) => identical(e.error, coordinatorError)), isTrue);
  });

  test('unrelated disposal error without bound stop refusal is not accepted',
      () async {
    final fixture = _Fixture();
    fixture.bindAndAccept();
    fixture.session.coordinatorError = FormatException('unrelated debt');
    fixture.session.onDispose = null;

    final result = await _executeFixture(fixture);

    expect(result.sessionDebtObserved, isTrue);
    expect(result.ownershipStopRefusalObserved, isFalse);
    expect(result.acceptedByHostEvidence, isFalse);
  });

  test('wrong-session or wrong-generation stop failure cannot prove refusal',
      () async {
    for (final wrongSession in [true, false]) {
      final fixture = _Fixture();
      fixture.bindAndAccept();
      final error = StateError('same reported refusal');
      fixture.session.coordinatorError = error;
      final callbackSession = wrongSession
          ? _FakeSession(
              _generation, fixture.controller, fixture.platformOutput)
          : fixture.session;
      fixture.session.onDispose = () {
        fixture.emitStopBoundary(
          callbackSession: callbackSession,
          owningGeneration: wrongSession ? _generation : _generation + 1,
          boundary: HdrBackendDiagnosticBoundary.entered,
          sequence: 10,
        );
        fixture.emitStopBoundary(
          callbackSession: callbackSession,
          owningGeneration: wrongSession ? _generation : _generation + 1,
          boundary: HdrBackendDiagnosticBoundary.failed,
          error: error,
          sequence: 11,
        );
      };

      final result = await _executeFixture(fixture);

      expect(result.ownershipStopRefusalObserved, isFalse);
      expect(result.acceptedByHostEvidence, isFalse);
    }
  });

  test('returned stop and ownership restore both reject N4 evidence', () async {
    final fixture = _Fixture();
    fixture.bindAndAccept();
    fixture.session.coordinatorError = StateError('unrelated report debt');
    fixture.session.onDispose = () {
      fixture.emitStopBoundary(
        callbackSession: fixture.session,
        owningGeneration: _generation,
        boundary: HdrBackendDiagnosticBoundary.entered,
        sequence: 20,
      );
      fixture.emitStopBoundary(
        callbackSession: fixture.session,
        owningGeneration: _generation,
        boundary: HdrBackendDiagnosticBoundary.returned,
        sequence: 21,
      );
    };

    final result = await _executeFixture(
      fixture,
      beforeRawOpenReturns: () => fixture.run.onNativeOptionDiagnostic(
        callbackSession: fixture.session,
        sessionInstanceId: _instanceId,
        diagnostic: HdrNativeDvOptionDiagnostic(
          transaction: Object(),
          sourcePath: _source,
          sourcePlaylistEntryId: '5',
          sourceFileLoadedEpoch: 10,
          purpose: HdrNativeDvOptionDiagnosticPurpose.restore,
          name: 'vd-lavc-o',
        ),
      ),
    );

    expect(result.ownershipStopRefusalObserved, isFalse);
    expect(result.evidenceGaps, contains('native-option-restore-observed'));
    expect(result.acceptedByHostEvidence, isFalse);
  });

  test('owned reset after disposal stop is not accepted as refusal', () async {
    final fixture = _Fixture();
    fixture.bindAndAccept();
    final stopError = StateError('same stop refusal');
    fixture.session.coordinatorError = stopError;
    fixture.session.onDispose = () {
      fixture.emitStopBoundary(
        callbackSession: fixture.session,
        owningGeneration: _generation,
        boundary: HdrBackendDiagnosticBoundary.entered,
        sequence: 40,
      );
      fixture.emitStopBoundary(
        callbackSession: fixture.session,
        owningGeneration: _generation,
        boundary: HdrBackendDiagnosticBoundary.failed,
        error: stopError,
        sequence: 41,
      );
      fixture.emitBackendMethod(
        HdrBackendDiagnosticMethod.resetOwnedConfiguration,
        HdrBackendDiagnosticBoundary.entered,
        purpose: HdrBackendDiagnosticPurpose.disposal,
      );
    };

    final result = await _executeFixture(fixture);

    expect(result.ownershipStopRefusalObserved, isFalse);
    expect(result.acceptedByHostEvidence, isFalse);
  });

  test('RouteApplied before consumer evidence is not admitted', () async {
    final fixture = _Fixture();
    fixture.run.bindSession(fixture.session, _instanceId);
    fixture.run.onSessionEvent(
      callbackSession: fixture.session,
      sessionInstanceId: _instanceId,
      event: fixture.routeAppliedEvent,
    );
    fixture.run.onConsumerValidated(
      callbackSession: fixture.session,
      sessionInstanceId: _instanceId,
      generation: _generation,
      plan: fixture.plan,
      facts: fixture.facts,
    );
    var rawOpenCalls = 0;

    final result = await fixture.run.execute(
      rawPlayerOpen: (player, uri) async => rawOpenCalls++,
      fileLoadedTimeout: const Duration(milliseconds: 10),
    );

    expect(result.n4ExecutionAdmitted, isFalse);
    expect(result.foreignFileLoadedMatched, isFalse);
    expect(rawOpenCalls, 0);
    expect(result.executionError, isA<StateError>());
    expect(fixture.session.disposeCalls, 1);
    expect(fixture.player.disposeCalls, 1);
  });

  test('foreign Session callback and repeated binding cannot authorize N4',
      () async {
    final fixture = _Fixture();
    final foreign = _FakeSession(
      _generation,
      fixture.controller,
      fixture.platformOutput,
    );
    fixture.run.bindSession(fixture.session, _instanceId);
    expect(() => fixture.run.bindSession(foreign, 'second-instance'),
        throwsStateError);

    fixture.run.onConsumerValidated(
      callbackSession: foreign,
      sessionInstanceId: _instanceId,
      generation: _generation,
      plan: fixture.plan,
      facts: fixture.facts,
    );
    fixture.run.onSessionEvent(
      callbackSession: foreign,
      sessionInstanceId: _instanceId,
      event: fixture.routeAppliedEvent,
    );
    var opened = false;

    final result = await fixture.run.execute(
      rawPlayerOpen: (player, uri) async => opened = true,
      fileLoadedTimeout: const Duration(milliseconds: 10),
    );

    expect(result.n4ExecutionAdmitted, isFalse);
    expect(opened, isFalse);
    expect(result.evidenceGaps,
        contains('consumer-validation-not-bound-to-required-real-identity'));
    expect(fixture.player.disposeCalls, 1);
  });

  test('foreign Player evidence and wrong Session instance are rejected',
      () async {
    final fixture = _Fixture();
    fixture.run.bindSession(fixture.session, _instanceId);
    final foreignPlayer = _FakePlayer();
    final foreignEvidence = fixture.evidence.copyWithPlayer(foreignPlayer);
    final foreignFacts = fixture.facts.copyWithEvidence(foreignEvidence);
    fixture.run.onConsumerValidated(
      callbackSession: fixture.session,
      sessionInstanceId: 'wrong-instance',
      generation: _generation,
      plan: fixture.plan,
      facts: fixture.facts,
    );
    fixture.run.onConsumerValidated(
      callbackSession: fixture.session,
      sessionInstanceId: _instanceId,
      generation: _generation,
      plan: fixture.plan,
      facts: foreignFacts,
    );
    fixture.run.onSessionEvent(
      callbackSession: fixture.session,
      sessionInstanceId: _instanceId,
      event: fixture.routeAppliedEvent,
    );

    final result = await fixture.run.execute(
      rawPlayerOpen: (player, uri) async {},
      fileLoadedTimeout: const Duration(milliseconds: 10),
    );

    expect(result.n4ExecutionAdmitted, isFalse);
    expect(result.foreignFileLoadedMatched, isFalse);
    expect(result.evidenceGaps,
        contains('consumer-validation-not-bound-to-required-real-identity'));
  });

  test('single cached execution invokes the raw callback and disposes once',
      () async {
    final fixture = _Fixture();
    fixture.bindAndAccept();
    final openStarted = Completer<void>();
    final openRelease = Completer<void>();
    var callbackCount = 0;
    Future<void> rawOpen(Player player, String uri) async {
      callbackCount++;
      openStarted.complete();
      await openRelease.future;
      await fixture.player.open(Media(uri));
    }

    final first = fixture.run.execute(
      rawPlayerOpen: rawOpen,
      fileLoadedTimeout: const Duration(milliseconds: 100),
    );
    final second = fixture.run.execute(
      rawPlayerOpen: (player, uri) async => callbackCount += 100,
      fileLoadedTimeout: const Duration(milliseconds: 100),
    );
    expect(identical(first, second), isTrue);
    await openStarted.future;
    openRelease.complete();
    final result = await first;

    expect(result.foreignFileLoadedMatched, isTrue);
    expect(callbackCount, 1);
    expect(fixture.session.disposeCalls, 1);
    expect(fixture.player.disposeCalls, 1);
  });

  test('early file-loaded stream error is retained while raw open settles',
      () async {
    final fixture = _Fixture();
    fixture.bindAndAccept();
    final openStarted = Completer<void>();
    final openRelease = Completer<void>();
    final streamError = FormatException('synthetic transportStub event error');
    final streamStack = StackTrace.current;
    final execution = fixture.run.execute(
      rawPlayerOpen: (player, uri) async {
        openStarted.complete();
        await openRelease.future;
      },
      fileLoadedTimeout: const Duration(milliseconds: 100),
    );
    await openStarted.future;
    fixture.player.emitFileLoadedError(streamError, streamStack);
    await Future<void>.delayed(Duration.zero);
    openRelease.complete();

    final result = await execution;

    expect(identical(result.executionError, streamError), isTrue);
    expect(identical(result.executionStack, streamStack), isTrue);
    expect(runErrorPreserved(fixture.run, streamError), isTrue);
    expect(fixture.session.disposeCalls, 1);
    expect(fixture.player.disposeCalls, 1);
  });

  test(
      'configure after real FILE_LOADED before delayed raw-open return is seen',
      () async {
    final fixture = _Fixture();
    fixture.bindAndAccept();
    final openStarted = Completer<void>();
    final releaseOpen = Completer<void>();
    final execution = fixture.run.execute(
      rawPlayerOpen: (player, uri) async {
        openStarted.complete();
        await fixture.player.open(Media(uri));
        await releaseOpen.future;
      },
      fileLoadedTimeout: const Duration(milliseconds: 100),
    );
    await openStarted.future;
    await Future<void>.delayed(Duration.zero);
    expect(
        fixture.run.journal
            .any((row) => row['kind'] == 'foreign-file-loaded-callback'),
        isTrue);
    fixture.emitBackendMethod(
      HdrBackendDiagnosticMethod.configure,
      HdrBackendDiagnosticBoundary.entered,
    );
    releaseOpen.complete();

    final result = await execution;

    expect(result.noSessionOpenOrConfigureAfterForeign, isFalse);
    expect(result.acceptedByHostEvidence, isFalse);
  });

  test('configure during locked snapshot is in the foreign cutoff interval',
      () async {
    final fixture = _Fixture();
    fixture.bindAndAccept();
    fixture.player.onGetProperty = (name) {
      if (name == 'path' && fixture.player.fileLoadedEpoch > 9) {
        fixture.emitBackendMethod(
          HdrBackendDiagnosticMethod.configure,
          HdrBackendDiagnosticBoundary.entered,
        );
      }
    };

    final result = await _executeFixture(fixture);

    expect(result.foreignFileLoadedMatched, isTrue);
    expect(result.noSessionOpenOrConfigureAfterForeign, isFalse);
    expect(result.acceptedByHostEvidence, isFalse);
  });

  test('FILE_LOADED timeout does not race disposal against unsettled raw open',
      () async {
    final fixture = _Fixture();
    fixture.bindAndAccept();
    final openStarted = Completer<void>();
    final releaseOpen = Completer<void>();
    final execution = fixture.run.execute(
      rawPlayerOpen: (player, uri) async {
        openStarted.complete();
        await releaseOpen.future;
      },
      fileLoadedTimeout: const Duration(milliseconds: 5),
    );
    await openStarted.future;
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(fixture.player.disposeCalls, 0);
    expect(fixture.session.disposeCalls, 0);
    releaseOpen.complete();
    final result = await execution;

    expect(result.executionError, isA<TimeoutException>());
    expect(fixture.session.disposeCalls, 1);
    expect(fixture.player.disposeCalls, 1);
  });

  test('subscription cancellation error cannot skip final Player disposal',
      () async {
    final fixture = _Fixture();
    fixture.bindAndAccept();
    final cancelError = StateError('synthetic cancel failure');
    fixture.player.cancelError = cancelError;

    final result = await _executeFixture(fixture);

    expect(result.executionError, same(cancelError));
    expect(fixture.session.disposeCalls, 1);
    expect(fixture.player.disposeCalls, 1);
  });

  test('close closes admission immediately and drains active execution',
      () async {
    final fixture = _Fixture();
    fixture.bindAndAccept();
    final openStarted = Completer<void>();
    final openRelease = Completer<void>();
    final execution = fixture.run.execute(
      rawPlayerOpen: (player, uri) async {
        openStarted.complete();
        await openRelease.future;
        await fixture.player.open(Media(uri));
      },
      fileLoadedTimeout: const Duration(milliseconds: 100),
    );
    await openStarted.future;
    final close = fixture.run.close();
    await expectLater(
      fixture.run.execute(rawPlayerOpen: (player, uri) async {}),
      throwsStateError,
    );
    openRelease.complete();
    final result = await execution;
    await close;
    final drained = await fixture.run.drain();

    expect(result.foreignFileLoadedMatched, isTrue);
    expect(drained, isNotEmpty);
    expect(fixture.session.disposeCalls, 1);
    expect(fixture.player.disposeCalls, 1);
    expect(fixture.run.closed, isTrue);
  });

  test('journal and raw error reference bounds fail closed', () async {
    final fixture = _Fixture(maxRows: 5);
    fixture.bindAndAccept();
    fixture.run.onNativeOptionDiagnostic(
      callbackSession: fixture.session,
      sessionInstanceId: _instanceId,
      diagnostic: HdrNativeDvOptionDiagnostic(
        transaction: Object(),
        sourcePath: _source,
        sourcePlaylistEntryId: '4',
        sourceFileLoadedEpoch: 9,
        purpose: HdrNativeDvOptionDiagnosticPurpose.originals,
        name: 'vd-lavc-o',
        original: '',
        requested: 'native_dv=1',
        observed: '',
      ),
    );
    fixture.run.onNativeOptionDiagnostic(
      callbackSession: fixture.session,
      sessionInstanceId: _instanceId,
      diagnostic: HdrNativeDvOptionDiagnostic(
        transaction: Object(),
        sourcePath: _source,
        sourcePlaylistEntryId: '4',
        sourceFileLoadedEpoch: 9,
        purpose: HdrNativeDvOptionDiagnosticPurpose.apply,
        name: 'vd-lavc-o',
        error: StateError('bounded diagnostic error'),
      ),
    );
    fixture.run.onNativeOptionDiagnostic(
      callbackSession: fixture.session,
      sessionInstanceId: _instanceId,
      diagnostic: HdrNativeDvOptionDiagnostic(
        transaction: Object(),
        sourcePath: _source,
        sourcePlaylistEntryId: '4',
        sourceFileLoadedEpoch: 9,
        purpose: HdrNativeDvOptionDiagnosticPurpose.restore,
        name: 'vd-lavc-o',
      ),
    );
    fixture.run.onNativeOptionDiagnostic(
      callbackSession: fixture.session,
      sessionInstanceId: _instanceId,
      diagnostic: HdrNativeDvOptionDiagnostic(
        transaction: Object(),
        sourcePath: _source,
        sourcePlaylistEntryId: '4',
        sourceFileLoadedEpoch: 9,
        purpose: HdrNativeDvOptionDiagnosticPurpose.restore,
        name: 'vd-lavc-o',
      ),
    );

    expect(fixture.run.overflow, isTrue);
    expect(fixture.run.journal.length, 5);
    expect(fixture.run.rawErrors, hasLength(1));
  });
}

bool runErrorPreserved(
  AndroidNativeDvSessionForeignOwnershipRun run,
  Object error,
) =>
    run.rawErrors.any((record) => identical(record.error, error));

Future<AndroidNativeDvForeignOwnershipResult> _executeFixture(
  _Fixture fixture, {
  void Function()? beforeRawOpenReturns,
}) =>
    fixture.run.execute(
      rawPlayerOpen: (player, uri) async {
        await fixture.player.open(Media(uri));
        beforeRawOpenReturns?.call();
      },
      fileLoadedTimeout: const Duration(milliseconds: 100),
    );

class _Fixture {
  _Fixture({int maxRows = 128}) : player = _FakePlayer() {
    platformOutput = _FakePlatformOutput(player)..nativeSurfaceActive = true;
    controller = _FakeVideoController(player, platformOutput);
    session = _FakeSession(_generation, controller, platformOutput);
    session.onDispose = _emitFailedStop;
    run = AndroidNativeDvSessionForeignOwnershipRun(
      player: player,
      verifiedP5Source: _source,
      maxRows: maxRows,
      transport: 'transportStub',
    );
    evidence = HdrNativeDvReviewEvidence(
      source: HdrOptionSourceIdentity(
        player: player,
        path: _source,
        playlistEntryId: '4',
        fileLoadedEpoch: 9,
      ),
      loaded: const FileLoadedRecord(9, 4),
      controller: platformOutput,
      output: const AndroidSurfaceAccountId(
        handle: 10,
        generation: 2,
        viewId: 3,
        surfaceGeneration: 4,
        wid: 5,
      ),
      configuration: AndroidMediaCodecConfiguration.parse(
        '{"api":1,"mime":"video/dolby-vision","codec":"test","native-dv-active":true}',
      )!,
      hwdecCurrent: 'mediacodec-copy',
    );
    route = const HdrRoute(
      strategy: HdrStrategy.nativeDolbyVision,
      presentation: HdrPresentation.nativeDolbyVision,
      outputTransfer: HdrOutputTransfer.dolbyVision,
      appliesDynamicMetadata: true,
      topology: HdrTopology.platformView,
      vo: 'mediacodec_embed',
      hwdec: 'mediacodec-copy',
      vdLavcOptions: 'native_dv=1',
      mediacodecEmbedRenderMode: 'timed',
      targetPrim: 'bt.2020',
      targetTrc: 'dolbyvision',
      surfaceTransfer: 'dolbyvision',
      stripDvRpu: false,
    );
    source = const HdrSourceDescriptor(
      codec: 'hevc',
      transfer: 'bt.2020-pq',
      primaries: 'bt.2020',
      dynamicMetadata: HdrDynamicMetadata.dolbyVision,
      dvProfile: 5,
      dvCompatibilityId: 0,
      enhancementLayer: false,
    );
    capabilities = const HdrCapabilities(
      sdkInt: 24,
      displayHdrTypes: {1},
      hevcDecoders: [],
      dolbyVisionDecoders: [],
      p5PipelineAvailable: true,
      dataSpaceBridgeLoaded: true,
      dataSpaceExt: null,
    );
    prediction = HdrRoutePrediction(
      source: source,
      selected: HdrCandidate(
        strategy: HdrStrategy.nativeDolbyVision,
        maturity: HdrStrategyMaturity.unsupported,
        feasible: true,
        route: route,
      ),
      candidates: [
        HdrCandidate(
          strategy: HdrStrategy.nativeDolbyVision,
          maturity: HdrStrategyMaturity.unsupported,
          feasible: true,
          route: route,
        ),
      ],
      presentation: HdrPresentation.nativeDolbyVision,
      confidence: HdrPredictionConfidence.verified,
      playable: true,
    );
    plan = HdrOpenPlan(
      media: Media(_source),
      source: source,
      sourceOrigin: HdrReportSource.decoder,
      capabilities: capabilities,
      prediction: prediction,
      route: route,
    );
    facts = HdrReviewFacts(
      codec: 'hevc',
      hwdecCurrent: evidence.hwdecCurrent,
      path: _source,
      dolbyVisionProfile: 5,
      dvCompatibilityId: 0,
      dvElPresent: false,
      nativeDvEvidence: evidence,
    );
    session.setReport(HdrOutputReport(
      generation: _generation,
      actual: route,
      hwdecCurrent: evidence.hwdecCurrent,
      verified: true,
    ));
    routeAppliedEvent = HdrRouteAppliedEvent(
      _generation,
      route: route,
      report: session.report.value,
    );
  }

  final _FakePlayer player;
  late final _FakePlatformOutput platformOutput;
  late final _FakeVideoController controller;
  late final _FakeSession session;
  late final AndroidNativeDvSessionForeignOwnershipRun run;
  late final HdrNativeDvReviewEvidence evidence;
  late final HdrRoute route;
  late final HdrSourceDescriptor source;
  late final HdrCapabilities capabilities;
  late final HdrRoutePrediction prediction;
  late final HdrOpenPlan plan;
  late final HdrReviewFacts facts;
  late final HdrRouteAppliedEvent routeAppliedEvent;

  void bindAndAccept() {
    run.bindSession(session, _instanceId);
    run.onConsumerValidated(
      callbackSession: session,
      sessionInstanceId: _instanceId,
      generation: _generation,
      plan: plan,
      facts: facts,
    );
    run.onSessionEvent(
      callbackSession: session,
      sessionInstanceId: _instanceId,
      event: routeAppliedEvent,
    );
  }

  void _emitFailedStop() {
    final error = session.coordinatorError ?? StateError('stop refused');
    emitStopBoundary(
      callbackSession: session,
      owningGeneration: _generation,
      boundary: HdrBackendDiagnosticBoundary.entered,
      sequence: 1,
    );
    emitStopBoundary(
      callbackSession: session,
      owningGeneration: _generation,
      boundary: HdrBackendDiagnosticBoundary.failed,
      error: error,
      sequence: 2,
    );
    platformOutput.nativeSurfaceActive = false;
  }

  void emitStopBoundary({
    required HdrVideoSession callbackSession,
    required int owningGeneration,
    required HdrBackendDiagnosticBoundary boundary,
    required int sequence,
    Object? error,
  }) {
    run.onBackendCallDiagnostic(
      callbackSession: callbackSession,
      sessionInstanceId: _instanceId,
      diagnostic: HdrBackendCallDiagnostic<HdrOpenPlan>(
        sequence: sequence,
        elapsedMicros: 20 + sequence,
        coordinatorGeneration: 8,
        invocation: null,
        owningAttempt: null,
        sessionGeneration: null,
        owningSessionGeneration: owningGeneration,
        method: HdrBackendDiagnosticMethod.stop,
        boundary: boundary,
        purpose: HdrBackendDiagnosticPurpose.disposal,
        error: error,
        stack: error == null ? null : StackTrace.current,
      ),
    );
  }

  void emitBackendMethod(
      HdrBackendDiagnosticMethod method, HdrBackendDiagnosticBoundary boundary,
      {HdrBackendDiagnosticPurpose purpose =
          HdrBackendDiagnosticPurpose.normal}) {
    run.onBackendCallDiagnostic(
      callbackSession: session,
      sessionInstanceId: _instanceId,
      diagnostic: HdrBackendCallDiagnostic<HdrOpenPlan>(
        sequence: 30,
        elapsedMicros: 50,
        coordinatorGeneration: 8,
        invocation: method == HdrBackendDiagnosticMethod.configure ||
                method == HdrBackendDiagnosticMethod.open ||
                method == HdrBackendDiagnosticMethod.prepareOutput
            ? HdrBackendDiagnosticAttempt(8, 1, plan)
            : null,
        owningAttempt: null,
        sessionGeneration: _generation,
        owningSessionGeneration: _generation,
        method: method,
        boundary: boundary,
        purpose: purpose,
      ),
    );
  }
}

class _FakeSession implements HdrVideoSession {
  _FakeSession(this.generation, this.videoController, this.platformOutput)
      : _report = ValueNotifier(HdrOutputReport(generation: generation)),
        _controller = ValueNotifier(videoController);

  final int generation;
  final _FakeVideoController videoController;
  final _FakePlatformOutput platformOutput;
  final ValueNotifier<HdrOutputReport> _report;
  final ValueNotifier<VideoController?> _controller;
  final StreamController<HdrOutputEvent> _events =
      StreamController<HdrOutputEvent>.broadcast(sync: true);
  HdrDisposalReport? _disposeReport;
  Object? coordinatorError;
  void Function()? onDispose;
  int disposeCalls = 0;
  int sessionOpenCalls = 0;

  void setReport(HdrOutputReport value) => _report.value = value;

  @override
  ValueListenable<VideoController?> get controller => _controller;
  @override
  ValueListenable<HdrOutputReport> get report => _report;
  @override
  Stream<HdrOutputEvent> get events => _events.stream;
  @override
  HdrDisposalReport? get lastDisposeReport => _disposeReport;

  @override
  Future<void> dispose() async {
    disposeCalls++;
    onDispose?.call();
    platformOutput.nativeSurfaceActive = false;
    _disposeReport = HdrDisposalReport(
      coordinatorError: coordinatorError,
      playerError: null,
      directoryError: null,
      retainedDirectory: null,
    );
  }

  @override
  Future<void> open(Media media,
      {HdrSourceDescriptor? hint, bool play = true, Duration? start}) async {
    sessionOpenCalls++;
    _report.value = _report.value.copyWith(generation: generation + 1);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeVideoController implements VideoController {
  _FakeVideoController(this.player, _FakePlatformOutput output)
      : platform = Completer<PlatformVideoController>() {
    platform.complete(output);
    notifier = ValueNotifier<PlatformVideoController?>(output);
    id = ValueNotifier<int?>(1);
    rect = ValueNotifier<Rect?>(null);
  }

  @override
  final Player player;
  @override
  final Completer<PlatformVideoController> platform;
  @override
  late final ValueNotifier<PlatformVideoController?> notifier;
  @override
  late final ValueNotifier<int?> id;
  @override
  late final ValueNotifier<Rect?> rect;
  @override
  bool get nativeSurfaceCandidate =>
      notifier.value?.nativeSurfaceCandidate ?? false;
  @override
  bool get nativeSurfaceActive => notifier.value?.nativeSurfaceActive ?? false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePlatformOutput extends PlatformVideoController
    implements AndroidVideoController {
  _FakePlatformOutput(Player player)
      : super(player, const VideoControllerConfiguration());

  @override
  AndroidSurfaceAccountId? currentBoundOutputIdentity =
      const AndroidSurfaceAccountId(
          handle: 10, generation: 2, viewId: 3, surfaceGeneration: 4, wid: 5);

  @override
  Future<void> setSize({int? width, int? height}) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePlayer implements Player {
  _FakePlayer()
      : properties = {
          'path': _source,
          'playlist/0/id': '4',
          'vd-lavc-o': 'native_dv=1',
          'mediacodec-embed-render-mode': 'timed',
          'vo': 'mediacodec_embed',
          'hwdec-current': 'mediacodec-copy',
          'pause': 'no',
          'time-pos': '10',
        };

  final Map<String, String> properties;
  Object? cancelError;
  void Function(String property)? onGetProperty;
  @override
  final Lock lock = Lock();
  @override
  late final StreamController<FileLoadedRecord> fileLoadedEpochController =
      _CancelFailingController(() => cancelError);
  @override
  int fileLoadedEpoch = 9;
  int openCalls = 0;
  int disposeCalls = 0;
  @override
  bool disposed = false;
  bool? lastOpenSynchronized;

  @override
  Future<String> getProperty(String property,
      {bool waitForInitialization = true}) async {
    if (disposed) throw StateError('Player is disposed');
    onGetProperty?.call(property);
    return properties[property] ?? '';
  }

  @override
  Future<void> open(Playable playable,
      {bool play = true, bool synchronized = true}) async {
    if (disposed) throw StateError('Player is disposed');
    if (playable is! Media || playable.uri != _source) {
      throw StateError('transportStub only allows the fixed same P5 URI');
    }
    openCalls++;
    lastOpenSynchronized = synchronized;
    properties['path'] = playable.uri;
    properties['playlist/0/id'] = '5';
    fileLoadedEpoch++;
    fileLoadedEpochController.add(FileLoadedRecord(fileLoadedEpoch, 5));
  }

  void emitFileLoadedError(Object error, StackTrace stack) {
    fileLoadedEpochController.addError(error, stack);
  }

  @override
  Future<void> dispose({bool synchronized = true}) async {
    disposeCalls++;
    disposed = true;
    await fileLoadedEpochController.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CancelFailingController implements StreamController<FileLoadedRecord> {
  _CancelFailingController(this.cancelError)
      : _inner = StreamController<FileLoadedRecord>.broadcast(sync: true);

  final StreamController<FileLoadedRecord> _inner;
  final Object? Function() cancelError;

  @override
  Stream<FileLoadedRecord> get stream =>
      _CancelFailingStream(_inner.stream, cancelError);
  @override
  bool get isClosed => _inner.isClosed;
  @override
  bool get isPaused => _inner.isPaused;
  @override
  bool get hasListener => _inner.hasListener;
  @override
  Future<void> get done => _inner.done;
  @override
  void add(FileLoadedRecord event) => _inner.add(event);
  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      _inner.addError(error, stackTrace);
  @override
  Future<void> close() => _inner.close();
  @override
  void Function()? get onListen => _inner.onListen;
  @override
  set onListen(void Function()? value) => _inner.onListen = value;
  @override
  void Function()? get onPause => _inner.onPause;
  @override
  set onPause(void Function()? value) => _inner.onPause = value;
  @override
  void Function()? get onResume => _inner.onResume;
  @override
  set onResume(void Function()? value) => _inner.onResume = value;
  @override
  FutureOr<void> Function()? get onCancel => _inner.onCancel;
  @override
  set onCancel(FutureOr<void> Function()? value) => _inner.onCancel = value;
  @override
  Future<dynamic> addStream(Stream<FileLoadedRecord> stream,
          {bool? cancelOnError}) =>
      _inner.addStream(stream, cancelOnError: cancelOnError ?? true);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CancelFailingStream extends Stream<FileLoadedRecord> {
  const _CancelFailingStream(this._inner, this.cancelError);

  final Stream<FileLoadedRecord> _inner;
  final Object? Function() cancelError;

  @override
  StreamSubscription<FileLoadedRecord> listen(
    void Function(FileLoadedRecord)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) =>
      _CancelFailingSubscription(
        _inner.listen(
          onData,
          onError: onError,
          onDone: onDone,
          cancelOnError: cancelOnError,
        ),
        cancelError,
      );
}

class _CancelFailingSubscription
    implements StreamSubscription<FileLoadedRecord> {
  _CancelFailingSubscription(this._inner, this.cancelError);

  final StreamSubscription<FileLoadedRecord> _inner;
  final Object? Function() cancelError;

  @override
  Future<void> cancel() async {
    await _inner.cancel();
    final error = cancelError();
    if (error != null) throw error;
  }

  @override
  void onData(void Function(FileLoadedRecord)? handleData) =>
      _inner.onData(handleData);
  @override
  void onError(Function? handleError) => _inner.onError(handleError);
  @override
  void onDone(void Function()? handleDone) => _inner.onDone(handleDone);
  @override
  void pause([Future<void>? resumeSignal]) => _inner.pause(resumeSignal);
  @override
  void resume() => _inner.resume();
  @override
  bool get isPaused => _inner.isPaused;
  @override
  Future<E> asFuture<E>([E? futureValue]) => _inner.asFuture<E>(futureValue);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

extension on HdrNativeDvReviewEvidence {
  HdrNativeDvReviewEvidence copyWithController(Object platform) =>
      HdrNativeDvReviewEvidence(
          source: source,
          loaded: loaded,
          controller: platform,
          output: output,
          configuration: configuration,
          hwdecCurrent: hwdecCurrent);

  HdrNativeDvReviewEvidence copyWithPlayer(Object otherPlayer) =>
      HdrNativeDvReviewEvidence(
        source: HdrOptionSourceIdentity(
          player: otherPlayer,
          path: source.path,
          playlistEntryId: source.playlistEntryId,
          fileLoadedEpoch: source.fileLoadedEpoch,
        ),
        loaded: loaded,
        controller: controller,
        output: output,
        configuration: configuration,
        hwdecCurrent: hwdecCurrent,
      );
}

extension on HdrReviewFacts {
  HdrReviewFacts copyWithEvidence(HdrNativeDvReviewEvidence evidence) =>
      HdrReviewFacts(
        codec: codec,
        hwdecCurrent: hwdecCurrent,
        path: path,
        dolbyVisionProfile: dolbyVisionProfile,
        dvCompatibilityId: dvCompatibilityId,
        dvElPresent: dvElPresent,
        nativeDvEvidence: evidence,
      );
}
