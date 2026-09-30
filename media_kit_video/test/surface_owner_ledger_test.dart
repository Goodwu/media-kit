import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit_video/src/video_controller/android_video_controller/surface_owner_ledger.dart';

void main() {
  group('SurfaceOwnerLedger', () {
    test('announce → queued → inFlight → bound promotion', () {
      final ledger = SurfaceOwnerLedger<String>();
      ledger.announceQueuedBind('A');
      expect(ledger.isLive('A'), isTrue);
      expect(ledger.isQueuedCandidate('A'), isTrue);
      expect(ledger.phaseOf('A'), SurfaceOwnerPhase.queued);

      ledger.markInFlight('A');
      expect(ledger.phaseOf('A'), SurfaceOwnerPhase.inFlight);
      expect(ledger.inFlightOwner, 'A');

      ledger.dequeueBind('A');
      ledger.clearInFlight();
      expect(ledger.phaseOf('A'), SurfaceOwnerPhase.bound);
    });

    test('bind failure keeps the owner live and retryable', () {
      final ledger = SurfaceOwnerLedger<String>();
      ledger.announceQueuedBind('A');
      ledger.markInFlight('A');
      ledger.markBindFailed('A');
      expect(ledger.isLive('A'), isTrue);
      expect(ledger.isQueuedCandidate('A'), isFalse);
      // The controller keeps a failed bind owner in flight until its retry
      // resolves it: the retained marker blocks fallback promotion.
      expect(ledger.phaseOf('A'), SurfaceOwnerPhase.inFlight);
      ledger.clearInFlight();
      expect(ledger.phaseOf('A'), SurfaceOwnerPhase.failed);

      // Retry: the same owner is announced and queued again. The failure
      // marker survives re-announcement exactly like the separate failed set
      // did; only the bind flow clears it once the retry succeeds.
      ledger.announceQueuedBind('A');
      expect(ledger.isQueuedCandidate('A'), isFalse);
      ledger.clearBindFailed('A');
      expect(ledger.isQueuedCandidate('A'), isTrue);
      expect(ledger.phaseOf('A'), SurfaceOwnerPhase.queued);
    });

    test('late destroy of an untracked owner still gets a release record', () {
      final ledger = SurfaceOwnerLedger<String>();
      // A destroy for a Surface this controller never tracked (JNI address
      // reuse or a pre-wiring event) must still be release-trackable.
      ledger.beginRelease('late');
      expect(ledger.isReleasing('late'), isTrue);
      expect(ledger.isLive('late'), isFalse);
      expect(ledger.phaseOf('late'), SurfaceOwnerPhase.releasing);

      ledger.finishRelease('late');
      expect(ledger.isReleasing('late'), isFalse);
      expect(ledger.phaseOf('late'), SurfaceOwnerPhase.untracked);
    });

    test('destroy keeps the pending fallback serial for the replacement bind',
        () {
      final ledger = SurfaceOwnerLedger<String>();
      ledger.announceQueuedBind('A');
      ledger.setPendingFallbackSerial('A', 7);
      ledger.authorizeFallbackSerial(7);

      ledger.destroy('A');
      expect(ledger.isLive('A'), isFalse);
      // The late destroy still authorizes the replacement bind it selected.
      expect(ledger.pendingFallbackSerial('A'), 7);
      expect(ledger.isAuthorizedFallbackSerial(7), isTrue);

      ledger.finishRelease('A');
      expect(ledger.pendingFallbackSerial('A'), isNull);
    });

    test('finishRelease is the only release path dropping the fallback serial',
        () {
      final ledger = SurfaceOwnerLedger<String>();
      ledger.announceQueuedBind('A');
      ledger.beginRelease('A');
      ledger.setPendingFallbackSerial('A', 3);

      // A cancelled release keeps the serial.
      ledger.cancelRelease('A');
      expect(ledger.pendingFallbackSerial('A'), 3);
      expect(ledger.isLive('A'), isTrue);

      ledger.beginRelease('A');
      ledger.finishRelease('A');
      expect(ledger.pendingFallbackSerial('A'), isNull);
      expect(ledger.isLive('A'), isFalse);
    });

    test('re-announce refreshes announcement order for fallback selection',
        () {
      final ledger = SurfaceOwnerLedger<String>();
      ledger.announceQueuedBind('A');
      ledger.announceQueuedBind('B');
      expect(ledger.newestLiveOwner, 'B');

      ledger.destroy('A');
      ledger.announceQueuedBind('A');
      // A is the newest live owner again.
      expect(ledger.newestLiveOwner, 'A');
      expect(ledger.liveOwners.toList(), ['B', 'A']);
    });

    test('re-announce preserves failure and release-pending state', () {
      final ledger = SurfaceOwnerLedger<String>();
      ledger.announceQueuedBind('A');
      ledger.markBindFailed('A');
      ledger.beginRelease('A');

      ledger.destroy('A');
      ledger.announceQueuedBind('A');
      expect(ledger.isBindFailed('A'), isTrue);
      expect(ledger.isReleasing('A'), isTrue);
      expect(ledger.isLive('A'), isTrue);
      expect(ledger.isQueuedCandidate('A'), isFalse); // still failed
    });

    test('anyQueuedCandidate requires queued, live and not failed', () {
      final ledger = SurfaceOwnerLedger<String>();
      ledger.announceQueuedBind('A'); // queued candidate
      ledger.announceQueuedBind('B');
      ledger.markBindFailed('B'); // failed → not a candidate
      ledger.announceQueuedBind('C');
      ledger.destroy('C'); // not live → not a candidate
      ledger.enqueueBind('D'); // queued but never announced → not live

      expect(ledger.anyQueuedCandidate((owner) => true), isTrue);
      expect(ledger.anyQueuedCandidate((owner) => owner == 'A'), isTrue);
      expect(ledger.anyQueuedCandidate((owner) => owner == 'B'), isFalse);
      expect(ledger.anyQueuedCandidate((owner) => owner == 'C'), isFalse);
      expect(ledger.anyQueuedCandidate((owner) => owner == 'D'), isFalse);
    });

    test('out-of-order bind then destroy keeps the release drainable', () {
      final ledger = SurfaceOwnerLedger<String>();
      // B is announced and queued while old A is still bound.
      ledger.announceQueuedBind('A');
      ledger.announceQueuedBind('B');

      // Old A's destroy arrives after B started binding.
      ledger.markInFlight('B');
      ledger.beginRelease('A');
      ledger.destroy('A');

      expect(ledger.isLive('A'), isFalse);
      expect(ledger.isReleasing('A'), isTrue);
      expect(ledger.releasingOwners.toList(), contains('A'));
      expect(ledger.phaseOf('A'), SurfaceOwnerPhase.releasing);

      // The drain releases A without touching B.
      for (final owner in ledger.releasingOwners.toList()) {
        if (ledger.isLive(owner)) continue;
        ledger.finishRelease(owner);
      }
      expect(ledger.isReleasing('A'), isFalse);
      expect(ledger.isLive('B'), isTrue);
    });

    test('terminal dispose marks every live owner release-pending and clears',
        () {
      final ledger = SurfaceOwnerLedger<String>();
      ledger.announceQueuedBind('A');
      ledger.announceQueuedBind('B');
      ledger.markBindFailed('B');
      ledger.setPendingFallbackSerial('A', 11);
      ledger.authorizeFallbackSerial(11);

      ledger.beginReleaseAllLive();
      expect(ledger.isReleasing('A'), isTrue);
      expect(ledger.isReleasing('B'), isTrue);

      // clearLiveOwners drops the identities but release-pending markers
      // survive so the drain can still release them.
      ledger.clearLiveOwners();
      expect(ledger.isLive('A'), isFalse);
      expect(ledger.isReleasing('A'), isTrue);
      expect(ledger.releasingOwners.toSet(), {'A', 'B'});

      ledger.clearPendingFallbackSerials();
      expect(ledger.pendingFallbackSerial('A'), isNull);

      ledger.clearReleasing();
      expect(ledger.releasingOwners, isEmpty);
      // Queued markers survive terminal cleanup exactly like the separate
      // queued set did: each bind attempt dequeues its own owner.
      expect(ledger.phaseOf('A'), SurfaceOwnerPhase.queued);
      ledger.dequeueBind('A');
      ledger.dequeueBind('B');
      expect(ledger.phaseOf('A'), SurfaceOwnerPhase.untracked);
      // B's failure marker outlives terminal cleanup, exactly like the
      // separate failed set did on a discarded controller.
      expect(ledger.phaseOf('B'), SurfaceOwnerPhase.failed);
    });

    test('authorized serials are cleared wholesale on a new bind attempt',
        () {
      final ledger = SurfaceOwnerLedger<String>();
      ledger.authorizeFallbackSerial(1);
      ledger.authorizeFallbackSerial(2);
      expect(ledger.isAuthorizedFallbackSerial(1), isTrue);

      ledger.clearAuthorizedFallbackSerials();
      expect(ledger.isAuthorizedFallbackSerial(1), isFalse);
      expect(ledger.isAuthorizedFallbackSerial(2), isFalse);
    });

    test('in-flight owner is exclusive and clearable by identity', () {
      final ledger = SurfaceOwnerLedger<String>();
      ledger.markInFlight('A');
      ledger.clearInFlightIf('B'); // different identity: no effect
      expect(ledger.inFlightOwner, 'A');
      ledger.clearInFlightIf('A');
      expect(ledger.inFlightOwner, isNull);
    });

    test('enqueue without announce stays non-live and prunes on dequeue', () {
      final ledger = SurfaceOwnerLedger<String>();
      ledger.enqueueBind('A');
      expect(ledger.isLive('A'), isFalse);
      expect(ledger.isQueuedCandidate('A'), isFalse);
      expect(ledger.phaseOf('A'), SurfaceOwnerPhase.queued);

      ledger.dequeueBind('A');
      expect(ledger.phaseOf('A'), SurfaceOwnerPhase.untracked);
    });
  });
}
