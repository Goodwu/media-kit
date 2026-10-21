import 'dart:async';

import 'package:flutter/services.dart' show MissingPluginException;
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' show Media;
import 'package:media_kit_video/src/hdr/hdr_capabilities.dart';
import 'package:media_kit_video/src/hdr/hdr_open_plan.dart';
import 'package:media_kit_video/src/hdr/hdr_route.dart';
import 'package:media_kit_video/src/hdr/hdr_source_descriptor.dart';
import 'package:media_kit_video/src/hdr/hdr_strategy.dart';
import 'package:media_kit_video/src/hdr/hdr_yuv_presentation_contract.dart';
import 'package:media_kit_video/src/hdr/hdr_yuv_window_arm.dart';

/// Plan C: the YUV window presentation arm manager on injectable FFI/channel
/// seams — admission (route shape, capability channel, vendor YUV arm
/// capability gate, owner), the owner-bound-first/legacy-fallback arm order,
/// the paired disarm, cleanup debt and stale-attempt isolation. The
/// process-level lease registry (B1) is static, so it is reset between tests.
void main() {
  setUp(HdrYuvWindowProcessRegistry.resetForTesting);

  final media = Media('test://source');

  HdrCapabilities lgYuvCaps({bool yuvWindow = true}) => HdrCapabilities(
        sdkInt: 24,
        displayHdrTypes: const {2},
        hevcDecoders: const [],
        dolbyVisionDecoders: const [],
        p5PipelineAvailable: true,
        dataSpaceBridgeLoaded: true,
        dataSpaceExt: HdrDataSpaceExtInfo(
          id: 'lg-pq',
          applicable: true,
          pqPresentation: HdrPqPresentation(
            rgbSurface: false,
            yuvWindow: yuvWindow,
          ),
          // The managed YUV arm protocol declaration the admission consumes.
          yuvWindowArmApi: 1,
        ),
      );

  HdrOpenPlan planFor(HdrRoute route, {HdrCapabilities? capabilities}) {
    final source = HdrSourceDescriptor(
      codec: 'hevc',
      transfer: 'hlg',
      primaries: 'bt.2020',
      dynamicMetadata: HdrDynamicMetadata.dolbyVision,
      dvProfile: 8,
      dvCompatibilityId: 4,
      enhancementLayer: false,
    );
    final candidate = HdrCandidate(
      strategy: route.strategy,
      maturity: HdrStrategyMaturity.verified,
      feasible: true,
      route: route,
    );
    return HdrOpenPlan(
      media: media,
      source: source,
      sourceOrigin: null,
      capabilities: capabilities ?? lgYuvCaps(),
      prediction: HdrRoutePrediction(
        source: source,
        selected: candidate,
        candidates: [candidate],
        presentation: HdrPresentation.nativeHdr,
        confidence: HdrPredictionConfidence.verified,
        playable: true,
      ),
      route: route,
    );
  }

  test('non-YUV routes take zero arms and clean up as no-ops', () async {
    final atoms = FakeYuvAtoms();
    final arm = armManager(atoms, ownerToken: 'owner-token');
    final plan = planFor(yuvRoute().surrogate(hwdec: 'mediacodec-copy'));
    await arm.armForAttempt(plan);
    expect(atoms.calls, isEmpty);
    expect(arm.isArmed, isFalse);
    await arm.endAttempt(plan);
    expect(atoms.diagDataSpace, 0);
    expect(atoms.yuvDiagEnabled, 0);
  });

  test('owner-bound arm succeeds through the channel and disarms in pairs',
      () async {
    final atoms = FakeYuvAtoms();
    final arm = armManager(atoms, ownerToken: 'owner-token');
    final plan = planFor(yuvRoute());
    await arm.armForAttempt(plan);
    expect(atoms.diagDataSpace, HdrYuvPresentationContract.windowDataSpace);
    expect(
        atoms.channelCalls,
        contains(predicate<Map<String, Object?>>(
          (call) =>
              call['method'] == 'EnableYuvDiag' &&
              call['ownerToken'] == 'owner-token' &&
              call['generation'] == 7,
          'bound EnableYuvDiag with the observed generation',
        )));
    expect(atoms.yuvDiagEnabled, 1,
        reason: 'the bound arm sets the native atom (mkvendor_arm_yuv_diag)');
    expect(atoms.calls.where((c) => c.startsWith('yuvDiag:')), isEmpty,
        reason: 'the bound arm never runs through the legacy setter');
    expect(arm.isArmed, isTrue);
    await arm.endAttempt(plan);
    expect(atoms.channelCalls.last['method'], 'DisableYuvDiag');
    expect(atoms.diagDataSpace, 0);
    expect(atoms.yuvDiagEnabled, 0);
    expect(arm.isArmed, isFalse);
  });

  test('owner-bound refusal falls back to the legacy global arm', () async {
    final atoms = FakeYuvAtoms()..enableYuvDiagResult = false;
    final arm = armManager(atoms, ownerToken: 'owner-token');
    final plan = planFor(yuvRoute());
    await arm.armForAttempt(plan);
    expect(atoms.yuvDiagEnabled, 1);
    expect(atoms.diagDataSpace, HdrYuvPresentationContract.windowDataSpace);
    await arm.endAttempt(plan);
    expect(atoms.yuvDiagEnabled, 0);
    expect(atoms.diagDataSpace, 0);
  });

  test('unavailable channel (missing plugin) falls back to the legacy arm',
      () async {
    final atoms = FakeYuvAtoms()
      ..channelError = MissingPluginException('no channel');
    final arm = armManager(atoms, ownerToken: 'owner-token');
    await arm.armForAttempt(planFor(yuvRoute()));
    expect(atoms.yuvDiagEnabled, 1);
    expect(atoms.diagDataSpace, HdrYuvPresentationContract.windowDataSpace);
  });

  test('unavailable owner generation falls back to the legacy arm', () async {
    final atoms = FakeYuvAtoms();
    final arm = armManager(atoms,
        ownerToken: 'owner-token', generation: () async => null);
    await arm.armForAttempt(planFor(yuvRoute()));
    expect(atoms.yuvDiagEnabled, 1);
    expect(atoms.channelCalls.where((c) => c['method'] == 'EnableYuvDiag'),
        isEmpty);
  });

  test('missing yuvDiag symbol fails closed and rolls the diag atom back',
      () async {
    final atoms = FakeYuvAtoms()
      ..omitYuvDiagSetter = true
      ..channelError = MissingPluginException('no channel');
    final arm = armManager(atoms, ownerToken: 'owner-token');
    await expectLater(
        arm.armForAttempt(planFor(yuvRoute())),
        throwsA(isA<HdrYuvWindowArmFailure>().having((error) => error.reason,
            'reason', HdrDegradeReason.yuvWindowArmUnavailable)));
    expect(atoms.diagDataSpace, 0, reason: 'the partial arm was rolled back');
    expect(arm.isArmed, isFalse);
    expect(arm.hasCleanupDebt, isFalse);
  });

  test('missing diag-dataspace symbol fails before any arm', () async {
    final atoms = FakeYuvAtoms()..omitDiagSetter = true;
    final arm = armManager(atoms, ownerToken: 'owner-token');
    await expectLater(arm.armForAttempt(planFor(yuvRoute())),
        throwsA(isA<HdrYuvWindowArmFailure>()));
    expect(atoms.channelCalls, isEmpty);
    expect(atoms.yuvDiagEnabled, 0);
  });

  test('no owner token fails YUV admission explicitly (production gap)',
      () async {
    final atoms = FakeYuvAtoms();
    final arm = armManager(atoms, ownerToken: null);
    await expectLater(
      arm.armForAttempt(planFor(yuvRoute())),
      throwsA(isA<HdrYuvWindowArmFailure>().having((error) => error.cause,
          'cause', contains('no valid surface owner token'))),
    );
    expect(atoms.calls, isEmpty);
  });

  test(
      'capability channel, vendor arm capability gate and quad violations refuse admission',
      () async {
    final atoms = FakeYuvAtoms();
    final arm = armManager(atoms, ownerToken: 'owner-token');
    await expectLater(
      arm.armForAttempt(
          planFor(yuvRoute(), capabilities: lgYuvCaps(yuvWindow: false))),
      throwsA(isA<HdrYuvWindowArmFailure>()
          .having((error) => error.cause, 'cause', contains('no YUV window'))),
    );
    // A snapshot whose extension does NOT declare the managed YUV arm
    // protocol refuses even with a familiar id: the capability gate is
    // re-checked in Dart, not only natively.
    final undeclaredArm = HdrCapabilities(
      sdkInt: 24,
      displayHdrTypes: const {2},
      hevcDecoders: const [],
      dolbyVisionDecoders: const [],
      p5PipelineAvailable: true,
      dataSpaceBridgeLoaded: true,
      dataSpaceExt: HdrDataSpaceExtInfo(
        id: 'lg-pq',
        applicable: true,
        pqPresentation: lgYuvCaps().dataSpaceExt!.pqPresentation,
      ),
    );
    await expectLater(
      arm.armForAttempt(planFor(yuvRoute(), capabilities: undeclaredArm)),
      throwsA(isA<HdrYuvWindowArmFailure>().having((error) => error.cause,
          'cause', contains('vendor YUV arm capability gate'))),
    );
    await expectLater(
      arm.armForAttempt(planFor(yuvRoute().surrogate(offscreenTransfer: null))),
      throwsA(isA<HdrYuvWindowArmFailure>().having((error) => error.cause,
          'cause', contains('presentation contract rejected'))),
    );
    expect(atoms.calls, isEmpty);
  });

  test('YUV arm admission consumes the declared capability, never the id',
      () async {
    final atoms = FakeYuvAtoms();
    final arm = armManager(atoms, ownerToken: 'owner-token');
    // An unknown extension id with the explicit arm-protocol declaration is
    // admissible and arms the pair.
    final unknownIdCaps = HdrCapabilities(
      sdkInt: 29,
      displayHdrTypes: const {2},
      hevcDecoders: const [],
      dolbyVisionDecoders: const [],
      p5PipelineAvailable: true,
      dataSpaceBridgeLoaded: true,
      dataSpaceExt: HdrDataSpaceExtInfo(
        id: 'unknown-vendor',
        applicable: true,
        pqPresentation:
            lgYuvCaps().dataSpaceExt!.pqPresentation,
        yuvWindowArmApi: 1,
      ),
    );
    final plan = planFor(yuvRoute(), capabilities: unknownIdCaps);
    await arm.armForAttempt(plan);
    expect(atoms.diagDataSpace, HdrYuvPresentationContract.windowDataSpace);
    expect(arm.isArmed, isTrue);
    await arm.endAttempt(plan);
    expect(atoms.diagDataSpace, 0);
  });

  test('failed cleanup retains debt that blocks the next arm until it clears',
      () async {
    final atoms = FakeYuvAtoms()..disarmFails = true;
    final arm = armManager(atoms, ownerToken: 'owner-token');
    final first = planFor(yuvRoute());
    await arm.armForAttempt(first);
    await expectLater(
        arm.endAttempt(first), throwsA(isA<HdrYuvWindowArmFailure>()));
    expect(arm.hasCleanupDebt, isTrue);
    expect(arm.isArmed, isTrue);
    // The successor attempt cannot arm over uncleared state.
    await expectLater(arm.armForAttempt(planFor(yuvRoute())),
        throwsA(isA<HdrYuvWindowArmFailure>()));
    // Once the disarm path recovers, the next attempt clears and arms.
    atoms.disarmFails = false;
    await arm.armForAttempt(planFor(yuvRoute()));
    expect(arm.hasCleanupDebt, isFalse);
    expect(arm.isArmed, isTrue);
  });

  test('a stale attempt cleanup never clears a successor arm', () async {
    final atoms = FakeYuvAtoms();
    final arm = armManager(atoms, ownerToken: 'owner-token');
    final first = planFor(yuvRoute());
    final second = planFor(yuvRoute());
    await arm.armForAttempt(first);
    await arm.armForAttempt(second); // Retires the first arm, arms the second.
    expect(atoms.channelCalls.where((c) => c['method'] == 'EnableYuvDiag'),
        hasLength(2));
    await arm.endAttempt(first); // Stale: must be a no-op.
    expect(arm.isArmed, isTrue);
    expect(atoms.diagDataSpace, HdrYuvPresentationContract.windowDataSpace);
    await arm.endAttempt(second);
    expect(arm.isArmed, isFalse);
    expect(atoms.diagDataSpace, 0);
  });

  test(
      'a same-plan re-arm truly re-arms the pair (B3: retirement may have '
      'cleared the native state between the hooks)', () async {
    final atoms = FakeYuvAtoms();
    final arm = armManager(atoms, ownerToken: 'owner-token');
    final plan = planFor(yuvRoute());
    await arm.armForAttempt(plan);
    // Simulate the output retirement the slot performs between its two
    // preparation hooks: the native owner-termination path clears the YUV
    // diag atom (the diag-dataspace atom is NOT cleared by termination —
    // only the manager's own disarm clears it).
    atoms.yuvDiagEnabled = 0;
    await arm.armForAttempt(plan);
    expect(atoms.channelCalls.where((c) => c['method'] == 'EnableYuvDiag'),
        hasLength(2),
        reason: 'the second hook must penetrate any arm cache and re-arm');
    expect(atoms.diagDataSpace, HdrYuvPresentationContract.windowDataSpace);
    expect(arm.isArmed, isTrue);
    await arm.endAttempt(plan);
    expect(atoms.diagDataSpace, 0);
    expect(atoms.yuvDiagEnabled, 0);
  });

  test('a YUV attempt followed by a non-YUV attempt leaves both atoms zero',
      () async {
    final atoms = FakeYuvAtoms();
    final arm = armManager(atoms, ownerToken: 'owner-token');
    final yuv = planFor(yuvRoute());
    await arm.armForAttempt(yuv);
    await arm.endAttempt(yuv);
    await arm
        .armForAttempt(planFor(yuvRoute().surrogate(hwdec: 'mediacodec-copy')));
    await arm
        .endAttempt(planFor(yuvRoute().surrogate(hwdec: 'mediacodec-copy')));
    expect(atoms.diagDataSpace, 0);
    expect(atoms.yuvDiagEnabled, 0);
  });

  test('dispose clears an armed state best-effort and is idempotent', () async {
    final atoms = FakeYuvAtoms();
    final arm = armManager(atoms, ownerToken: 'owner-token');
    await arm.armForAttempt(planFor(yuvRoute()));
    await arm.dispose();
    expect(arm.isArmed, isFalse);
    expect(atoms.diagDataSpace, 0);
    await arm.dispose();
    expect(atoms.channelCalls.where((c) => c['method'] == 'DisableYuvDiag'),
        hasLength(1));
  });

  group('process-level lease registry (B1)', () {
    test('a second manager cannot arm over an active lease (typed conflict)',
        () async {
      final atoms = FakeYuvAtoms();
      final first = armManager(atoms, ownerToken: 'owner-a');
      final second = armManager(atoms, ownerToken: 'owner-b');
      await first.armForAttempt(planFor(yuvRoute()));
      // The conflict is typed and explicit — never a silent disarm of the
      // first manager's authorization, and never a second arm on top.
      await expectLater(
        second.armForAttempt(planFor(yuvRoute())),
        throwsA(isA<HdrYuvWindowLeaseConflict>()),
      );
      expect(atoms.diagDataSpace, HdrYuvPresentationContract.windowDataSpace,
          reason: 'the conflicting attempt touched nothing');
      expect(atoms.channelCalls.where((c) => c['method'] == 'EnableYuvDiag'),
          hasLength(1),
          reason: 'only the first manager armed');
      expect(HdrYuvWindowProcessRegistry.activeLease, isNotNull);
      expect(
          identical(HdrYuvWindowProcessRegistry.activeLease!.owner, first),
          isTrue);
    });

    test(
        'a second manager\'s non-YUV initialization is rejected during an '
        'active lease', () async {
      final atoms = FakeYuvAtoms();
      final first = armManager(atoms, ownerToken: 'owner-a');
      final second = armManager(atoms, ownerToken: 'owner-b');
      await first.armForAttempt(planFor(yuvRoute()));
      // A non-YUV (texture/SDR) output initialization is rejected with the
      // same typed conflict: it would otherwise initialize while reading
      // the first session's armed switches (the lgh7-sdr VO death).
      await expectLater(
        second.armForAttempt(
            planFor(yuvRoute().surrogate(hwdec: 'mediacodec-copy'))),
        throwsA(isA<HdrYuvWindowLeaseConflict>()),
      );
      expect(atoms.diagDataSpace, HdrYuvPresentationContract.windowDataSpace);
      expect(atoms.yuvDiagEnabled, 1);
      // The first manager's attempt still ends normally afterwards.
      final plan = (first.armedPlan as HdrOpenPlan);
      await first.endAttempt(plan);
      expect(atoms.diagDataSpace, 0);
      expect(atoms.yuvDiagEnabled, 0);
    });

    test(
        'foreign cleanup debt blocks every manager until the owner clears it',
        () async {
      final atoms = FakeYuvAtoms()..disarmFails = true;
      final debtor = armManager(atoms, ownerToken: 'owner-a');
      final other = armManager(atoms, ownerToken: 'owner-b');
      final plan = planFor(yuvRoute());
      await debtor.armForAttempt(plan);
      await expectLater(
          debtor.endAttempt(plan), throwsA(isA<HdrYuvWindowArmFailure>()));
      expect(identical(HdrYuvWindowProcessRegistry.debtOwner, debtor), isTrue);
      // Another session's YUV AND non-YUV initializations are both blocked.
      await expectLater(
        other.armForAttempt(planFor(yuvRoute())),
        throwsA(isA<HdrYuvWindowLeaseConflict>()),
      );
      await expectLater(
        other.armForAttempt(
            planFor(yuvRoute().surrogate(hwdec: 'mediacodec-copy'))),
        throwsA(isA<HdrYuvWindowLeaseConflict>()),
      );
      // Once the debtor's next attempt clears its own debt, the other
      // session may proceed.
      atoms.disarmFails = false;
      final recovered = planFor(yuvRoute());
      await debtor.armForAttempt(recovered);
      await debtor.endAttempt(recovered);
      expect(HdrYuvWindowProcessRegistry.debtOwner, isNull);
      await other.armForAttempt(planFor(yuvRoute()));
      expect(atoms.diagDataSpace, HdrYuvPresentationContract.windowDataSpace);
      await other.dispose();
      expect(atoms.diagDataSpace, 0);
    });

    test(
        'a stale cleanup from another manager never clears the successor arm',
        () async {
      final atoms = FakeYuvAtoms();
      final first = armManager(atoms, ownerToken: 'owner-a');
      final second = armManager(atoms, ownerToken: 'owner-b');
      final firstPlan = planFor(yuvRoute());
      await first.armForAttempt(firstPlan);
      await first.endAttempt(firstPlan);
      expect(atoms.diagDataSpace, 0);
      // The successor arms after the hand-off...
      final secondPlan = planFor(yuvRoute());
      await second.armForAttempt(secondPlan);
      expect(atoms.diagDataSpace, HdrYuvPresentationContract.windowDataSpace);
      // ...and the first manager's stale terminal cleanup clears nothing.
      await first.endAttempt(firstPlan);
      await first.dispose();
      expect(atoms.diagDataSpace, HdrYuvPresentationContract.windowDataSpace,
          reason: 'a stale cross-session cleanup must not disarm the holder');
      expect(second.isArmed, isTrue);
      await second.endAttempt(secondPlan);
      expect(atoms.diagDataSpace, 0);
      expect(atoms.yuvDiagEnabled, 0);
    });

    test('serialized A→B hand-off arms and clears in order', () async {
      final atoms = FakeYuvAtoms();
      final first = armManager(atoms, ownerToken: 'owner-a');
      final second = armManager(atoms, ownerToken: 'owner-b');
      final firstPlan = planFor(yuvRoute());
      await first.armForAttempt(firstPlan);
      await first.endAttempt(firstPlan);
      final secondPlan = planFor(yuvRoute());
      await second.armForAttempt(secondPlan);
      await second.endAttempt(secondPlan);
      expect(atoms.channelCalls.map((c) => c['method']).toList(), [
        'EnableYuvDiag',
        'DisableYuvDiag',
        'EnableYuvDiag',
        'DisableYuvDiag',
      ], reason: 'the serialized hand-off is a strict arm/disarm alternation');
      expect(atoms.diagDataSpace, 0);
      expect(atoms.yuvDiagEnabled, 0);
      expect(HdrYuvWindowProcessRegistry.activeLease, isNull);
      expect(HdrYuvWindowProcessRegistry.debtOwner, isNull);
    });
  });

  group('process admission (B1 round 3)', () {
    test(
        'a non-YUV read admission holds across the initialization: a '
        'concurrent YUV write is rejected (reverse concurrency)', () async {
      final atoms = FakeYuvAtoms();
      final reader = armManager(atoms, ownerToken: 'owner-a');
      final writer = armManager(atoms, ownerToken: 'owner-b');
      final events = <String>[];
      final held = Completer<void>();
      final release = Completer<void>();
      // B (non-YUV) passes admission and suspends MID-initialization (the
      // output binding is still in flight).
      final reading = reader.initializeOutput(
        planFor(yuvRoute().surrogate(hwdec: 'mediacodec-copy')),
        () async {
          events.add('read:init');
          await held.future;
          events.add('read:done');
          await release.future;
        },
      );
      await pumpUntil(() => events.contains('read:init'));
      // A (YUV) tries to arm while B's initialization is in flight: the
      // process gate has B as an active reader — A is REJECTED, not queued
      // into B's initialization window, and arms nothing.
      await expectLater(
        writer.initializeOutput(planFor(yuvRoute()), () async {
          events.add('write:init');
        }),
        throwsA(isA<HdrYuvWindowLeaseConflict>()),
      );
      expect(events, isNot(contains('write:init')),
          reason: 'the rejected initializer ran no body at all');
      expect(atoms.calls, isEmpty,
          reason: 'the rejected YUV attempt touched no atom');
      held.complete();
      await pumpUntil(() => events.contains('read:done'));
      release.complete();
      await reading;
      expect(atoms.diagDataSpace, 0);
      expect(atoms.yuvDiagEnabled, 0);
    });

    test(
        'a YUV write admission outlives the initialization until endAttempt',
        () async {
      final atoms = FakeYuvAtoms();
      final writer = armManager(atoms, ownerToken: 'owner-a');
      final reader = armManager(atoms, ownerToken: 'owner-b');
      final armed = Completer<void>();
      final release = Completer<void>();
      final plan = planFor(yuvRoute());
      final writing = writer.initializeOutput(plan, () async {
        await writer.armForAttempt(plan);
        armed.complete();
        await release.future; // The attempt is still open (pre-endAttempt).
      });
      await armed.future;
      expect(atoms.yuvDiagEnabled, 1);
      // During the YUV attempt (post-bind, pre-endAttempt) a concurrent
      // non-YUV initialization is rejected — the documented device
      // limitation of the P8.4 YUV window presentation.
      await expectLater(
        reader.initializeOutput(
            planFor(yuvRoute().surrogate(hwdec: 'mediacodec-copy')),
            () async {}),
        throwsA(isA<HdrYuvWindowLeaseConflict>()),
      );
      release.complete();
      await writing;
      await writer.endAttempt(plan);
      expect(atoms.diagDataSpace, 0);
      expect(atoms.yuvDiagEnabled, 0);
      // After the terminal disarm the read admission passes again and the
      // non-YUV initialization performs no atom operations of its own.
      atoms.calls.clear();
      await reader.initializeOutput(
          planFor(yuvRoute().surrogate(hwdec: 'mediacodec-copy')), () async {});
      expect(atoms.calls, isEmpty);
    });

    test(
        'same-manager re-entry while a guarded initialization is suspended '
        'is a typed conflict, never a disarm of the companion', () async {
      final atoms = FakeYuvAtoms();
      final arm = armManager(atoms, ownerToken: 'owner-token');
      final events = <String>[];
      final gate = Completer<void>();
      final release = Completer<void>();
      final plan = planFor(yuvRoute());
      final first = arm.initializeOutput(plan, () async {
        await arm.armForAttempt(plan);
        events.add('armed');
        await gate.future;
        await release.future;
      });
      await pumpUntil(() => events.contains('armed'));
      // The second initialization on the SAME manager (a bug or a re-entrant
      // caller) must not retire the in-flight attempt's state.
      await expectLater(
        arm.initializeOutput(
            planFor(yuvRoute().surrogate(hwdec: 'mediacodec-copy')),
            () async {
          events.add('second:init');
        }),
        throwsA(isA<HdrYuvWindowLeaseConflict>()),
      );
      expect(events, isNot(contains('second:init')));
      expect(atoms.yuvDiagEnabled, 1,
          reason: 'the in-flight arm was not disarmed by the re-entry');
      gate.complete();
      release.complete();
      await first;
      await arm.endAttempt(plan);
      expect(atoms.yuvDiagEnabled, 0);
    });

    test('managed accepted attempt retains only its admitted write owner',
        () async {
      final atoms = FakeYuvAtoms();
      final owner = armManager(atoms, ownerToken: 'owner-a');
      final successor = armManager(atoms, ownerToken: 'owner-b');
      final managedPlan = planFor(yuvRoute());
      final sdrPlan =
          planFor(yuvRoute().surrogate(hwdec: 'mediacodec-copy'));

      await owner.initializeOutput(
          managedPlan, () => owner.prepareManagedAttempt(managedPlan));
      await owner.endAttemptRetainingWindow(managedPlan);
      expect(atoms.gate.writer, isTrue,
          reason: 'managed accepted output retains its write gate lease');
      expect(atoms.diagDataSpace,
          HdrYuvPresentationContract.windowDataSpace);

      await expectLater(
          successor.initializeOutput(sdrPlan, () async {}),
          throwsA(isA<HdrYuvWindowLeaseConflict>()));
      final successorPlan = planFor(yuvRoute());
      await expectLater(
          successor.initializeOutput(successorPlan,
              () => successor.prepareManagedAttempt(successorPlan)),
          throwsA(isA<HdrYuvWindowLeaseConflict>()));
      expect(atoms.gate.writer, isTrue,
          reason: 'both successor routes leave the accepted owner intact');

      // A same-manager non-YUV open retires the previous managed window.
      await owner.initializeOutput(sdrPlan, () async {});
      expect(atoms.gate.writer, isFalse);
      expect(atoms.diagDataSpace, 0);

      // Re-establish accepted managed ownership, then dispose the owner.
      await owner.initializeOutput(
          managedPlan, () => owner.prepareManagedAttempt(managedPlan));
      await owner.endAttemptRetainingWindow(managedPlan);
      await owner.dispose();
      expect(atoms.gate.writer, isFalse);
      expect(atoms.diagDataSpace, 0);

      // The successor can now own a new managed output. A stale cleanup and
      // repeated disposal by the old manager cannot clear that ownership.
      await successor.initializeOutput(
          successorPlan, () => successor.prepareManagedAttempt(successorPlan));
      await successor.endAttemptRetainingWindow(successorPlan);
      await owner.endAttempt(managedPlan);
      await owner.dispose();
      expect(atoms.gate.writer, isTrue);
      expect(atoms.diagDataSpace,
          HdrYuvPresentationContract.windowDataSpace);
      await successor.dispose();
      expect(atoms.gate.writer, isFalse);
      expect(atoms.diagDataSpace, 0);
    });

    test('managed prepare failure keeps admission until terminal cleanup',
        () async {
      final atoms = FakeYuvAtoms();
      final owner = armManager(atoms, ownerToken: 'owner-a');
      final successor = armManager(atoms, ownerToken: 'owner-b');
      final failedPlan = planFor(yuvRoute());
      final sdrPlan =
          planFor(yuvRoute().surrogate(hwdec: 'mediacodec-copy'));

      await expectLater(
          owner.initializeOutput(failedPlan, () async {
            await owner.prepareManagedAttempt(failedPlan);
            throw StateError('output initialization failed');
          }),
          throwsStateError);
      expect(atoms.gate.writer, isTrue,
          reason: 'managed preparation established cleanup ownership');
      expect(atoms.diagDataSpace,
          HdrYuvPresentationContract.windowDataSpace);
      await expectLater(successor.initializeOutput(sdrPlan, () async {}),
          throwsA(isA<HdrYuvWindowLeaseConflict>()));

      await owner.endAttempt(failedPlan);
      expect(atoms.gate.writer, isFalse);
      expect(atoms.diagDataSpace, 0);
      expect(atoms.yuvDiagEnabled, 0);

      final successorPlan = planFor(yuvRoute());
      await successor.initializeOutput(successorPlan,
          () => successor.prepareManagedAttempt(successorPlan));
      expect(atoms.gate.writer, isTrue,
          reason: 'the successor initializes after terminal cleanup');
      await successor.endAttempt(successorPlan);
      expect(atoms.gate.writer, isFalse);
      expect(atoms.diagDataSpace, 0);
    });

    test(
        'same-manager re-entry while an unguarded arm is suspended at the '
        'generation read is a typed conflict; the pending arm completes',
        () async {
      final atoms = FakeYuvAtoms();
      final generationGate = Completer<int?>();
      final arm = armManager(atoms,
          ownerToken: 'owner-token', generation: () => generationGate.future);
      final plan = planFor(yuvRoute());
      final suspended = arm.armForAttempt(plan);
      await Future<void>.delayed(Duration.zero);
      // While the arm is suspended at the awaited generation read, the same
      // manager must not admit another initialization over it.
      await expectLater(
        arm.initializeOutput(
            planFor(yuvRoute().surrogate(hwdec: 'mediacodec-copy')),
            () async {}),
        throwsA(isA<HdrYuvWindowLeaseConflict>()),
      );
      expect(HdrYuvWindowProcessRegistry.activeLease, isNotNull,
          reason: 'the pending ownership was not silently released');
      // The suspended continuation resumes as the still-registered owner
      // and completes its arm.
      generationGate.complete(7);
      await suspended;
      expect(arm.isArmed, isTrue);
      expect(atoms.yuvDiagEnabled, 1);
      await arm.endAttempt(plan);
      expect(atoms.yuvDiagEnabled, 0);
    });

    test(
        'an admission rejection performs no initialization body at all '
        '(zero side effects for the rejecting side)', () async {
      final atoms = FakeYuvAtoms();
      final holder = armManager(atoms, ownerToken: 'owner-a');
      final other = armManager(atoms, ownerToken: 'owner-b');
      final held = holder.armForAttempt(planFor(yuvRoute()));
      await held;
      var bodyRan = false;
      await expectLater(
        other.initializeOutput(
            planFor(yuvRoute().surrogate(hwdec: 'mediacodec-copy')),
            () async {
          bodyRan = true;
        }),
        throwsA(isA<HdrYuvWindowLeaseConflict>()),
      );
      expect(bodyRan, isFalse);
      expect(atoms.diagDataSpace, HdrYuvPresentationContract.windowDataSpace,
          reason: 'the holder is unaffected by the rejection');
      expect(atoms.yuvDiagEnabled, 1);
      await holder.endAttempt((holder.armedPlan as HdrOpenPlan));
    });

    test(
        'the write lease is participant-unique: the SAME token on another '
        'manager is rejected (R3-4)', () async {
      final atoms = FakeYuvAtoms();
      // Two managers sharing ONE experiment token (the configuration the
      // token-keyed gate used to alias into one writer).
      final first = armManager(atoms, ownerToken: 'shared-token');
      final second = armManager(atoms, ownerToken: 'shared-token');
      final planA = planFor(yuvRoute());
      final armed = Completer<void>();
      final release = Completer<void>();
      final firstInit = first.initializeOutput(planA, () async {
        await first.armForAttempt(planA);
        armed.complete();
        await release.future;
      });
      await armed.future;
      // The same token, a different participant: REJECTED (the old
      // same-key idempotent admission would have let it through).
      await expectLater(
        second.initializeOutput(planFor(yuvRoute()), () async {}),
        throwsA(isA<HdrYuvWindowLeaseConflict>()),
      );
      release.complete();
      await firstInit;
      await first.endAttempt(planA);
      // After the lease truly ends, the same token on the other manager
      // proceeds.
      final planB = planFor(yuvRoute());
      await second.initializeOutput(planB, () => second.armForAttempt(planB));
      await second.endAttempt(planB);
      expect(atoms.diagDataSpace, 0);
      expect(atoms.yuvDiagEnabled, 0);
    });

    test(
        'a stale endWrite cannot release another holder\'s lease (R3-4)',
        () async {
      final atoms = FakeYuvAtoms();
      final holder = armManager(atoms, ownerToken: 'owner-a');
      final plan = planFor(yuvRoute());
      final armed = Completer<void>();
      final release = Completer<void>();
      final init = holder.initializeOutput(plan, () async {
        await holder.armForAttempt(plan);
        armed.complete();
        await release.future;
      });
      await armed.future;
      expect(atoms.gate.writer, isTrue);
      // A foreign, fabricated lease id must not end the holder's write.
      expect(atoms.gate.endWrite(999999), isFalse);
      expect(atoms.gate.writer, isTrue,
          reason: 'the stale release kept the lease');
      expect(atoms.yuvDiagEnabled, 1,
          reason: 'the holder is unaffected by the stale release');
      release.complete();
      await init;
      await holder.endAttempt(plan);
      expect(atoms.gate.writer, isFalse);
    });

    test(
        'dispose with a failed final disarm RETAINS the write admission and '
        'the lease together with the debt (R3-1)', () async {
      final atoms = FakeYuvAtoms()..disarmFails = true;
      final arm = armManager(atoms, ownerToken: 'owner-a');
      final plan = planFor(yuvRoute());
      final armed = Completer<void>();
      final release = Completer<void>();
      final init = arm.initializeOutput(plan, () async {
        await arm.armForAttempt(plan);
        armed.complete();
        await release.future;
      });
      await armed.future;
      release.complete();
      await init;
      // dispose never throws; the failed final disarm retains everything.
      await arm.dispose();
      // The debt AND the write admission survived the dispose together:
      // releasing the gate write over uncleared atoms would let another
      // participant initialize against possibly-poisoned atomics.
      expect(arm.hasCleanupDebt, isTrue);
      expect(HdrYuvWindowProcessRegistry.activeLease, isNotNull,
          reason: 'the local attempt ownership stays with the debt');
      expect(atoms.gate.writer, isTrue,
          reason: 'the process write lease was NOT released');
      final other = armManager(atoms, ownerToken: 'owner-b');
      await expectLater(
        other.initializeOutput(
            planFor(yuvRoute().surrogate(hwdec: 'mediacodec-copy')),
            () async {}),
        throwsA(isA<HdrYuvWindowLeaseConflict>()),
      );
      // A disposed manager has no self-recovery: the process release waits
      // for the last-engine reset (or, in the live variant below, the
      // debtor's own successful cleanup).
    });

    test(
        'a failed terminal cleanup keeps the process write until the debt '
        'clears, then releases it (R3-1 live variant)', () async {
      final atoms = FakeYuvAtoms()..disarmFails = true;
      final arm = armManager(atoms, ownerToken: 'owner-a');
      final other = armManager(atoms, ownerToken: 'owner-b');
      final plan = planFor(yuvRoute());
      final armed = Completer<void>();
      final release = Completer<void>();
      final init = arm.initializeOutput(plan, () async {
        await arm.armForAttempt(plan);
        armed.complete();
        await release.future;
      });
      await armed.future;
      release.complete();
      await init;
      await expectLater(
          arm.endAttempt(plan), throwsA(isA<HdrYuvWindowArmFailure>()));
      expect(atoms.gate.writer, isTrue,
          reason: 'the failed cleanup kept the process write');
      await expectLater(
        other.initializeOutput(
            planFor(yuvRoute().surrogate(hwdec: 'mediacodec-copy')),
            () async {}),
        throwsA(isA<HdrYuvWindowLeaseConflict>()),
      );
      // The debtor's own retry clears both together.
      atoms.disarmFails = false;
      await arm.endAttempt(plan);
      expect(arm.hasCleanupDebt, isFalse);
      expect(atoms.gate.writer, isFalse);
      atoms.calls.clear();
      await other.initializeOutput(
          planFor(yuvRoute().surrogate(hwdec: 'mediacodec-copy')), () async {});
      expect(atoms.calls, isEmpty,
          reason: 'the unblocked non-YUV initialization touched no atom');
    });
  });

  group('partial arms and pending ownership (B2/B5)', () {
    test(
        'a partial arm registers pending ownership and endAttempt clears the '
        'residue even without a complete armed scope', () async {
      final atoms = FakeYuvAtoms()
        ..channelError = MissingPluginException('no channel')
        ..omitYuvDiagSetter = true;
      final arm = armManager(atoms, ownerToken: 'owner-token');
      final plan = planFor(yuvRoute());
      await expectLater(arm.armForAttempt(plan),
          throwsA(isA<HdrYuvWindowArmFailure>()));
      expect(arm.isArmed, isFalse);
      expect(arm.hasCleanupDebt, isFalse,
          reason: 'the rollback succeeded, so no debt is retained');
      // Round 3: the ATOMS were rolled back, but the pending attempt
      // ownership survives the rollback — it belongs to the attempt and is
      // ended exactly once by its terminal cleanup.
      expect(HdrYuvWindowProcessRegistry.activeLease, isNotNull,
          reason: 'the pending ownership awaits the terminal cleanup');
      await arm.endAttempt(plan);
      expect(HdrYuvWindowProcessRegistry.activeLease, isNull);

      // The residue variant: the rollback itself fails, so the pending
      // ownership survives under the attempt's plan and endAttempt — not
      // only a complete arm — must clear it.
      final debtAtoms = FakeYuvAtoms()
        ..legacySetterFails = true
        ..disarmFails = true;
      final debtor = armManager(debtAtoms,
          ownerToken: 'owner-token', generation: () async => null);
      final debtPlan = planFor(yuvRoute());
      await expectLater(debtor.armForAttempt(debtPlan),
          throwsA(isA<HdrYuvWindowArmFailure>()));
      expect(debtor.isArmed, isFalse,
          reason: 'no complete armed scope was ever published');
      expect(debtor.hasCleanupDebt, isTrue);
      expect(HdrYuvWindowProcessRegistry.activeLease, isNotNull,
          reason: 'the partial arm is still owned by its attempt (B2)');
      // The retained pending debt blocks every other session...
      final other = armManager(debtAtoms, ownerToken: 'owner-b');
      await expectLater(other.armForAttempt(planFor(yuvRoute())),
          throwsA(isA<HdrYuvWindowLeaseConflict>()));
      // ...and endAttempt — with no complete _armed scope — still ends it.
      debtAtoms.disarmFails = false;
      await debtor.endAttempt(debtPlan);
      expect(debtAtoms.diagDataSpace, 0);
      expect(debtAtoms.yuvDiagEnabled, 0);
      expect(debtor.hasCleanupDebt, isFalse);
      expect(HdrYuvWindowProcessRegistry.activeLease, isNull);
      expect(HdrYuvWindowProcessRegistry.debtOwner, isNull);
      await other.armForAttempt(planFor(yuvRoute()));
      expect(debtAtoms.diagDataSpace,
          HdrYuvPresentationContract.windowDataSpace);
    });

    test(
        'endAttempt on a pending-debt attempt throws while the debt persists',
        () async {
      final atoms = FakeYuvAtoms()
        ..legacySetterFails = true
        ..disarmFails = true;
      final arm = armManager(atoms,
          ownerToken: 'owner-token', generation: () async => null);
      final plan = planFor(yuvRoute());
      await expectLater(
          arm.armForAttempt(plan), throwsA(isA<HdrYuvWindowArmFailure>()));
      await expectLater(
          arm.endAttempt(plan), throwsA(isA<HdrYuvWindowArmFailure>()));
      expect(arm.hasCleanupDebt, isTrue);
      expect(HdrYuvWindowProcessRegistry.debtOwner, isNotNull,
          reason: 'the debt persists until a cleanup succeeds');
      expect(HdrYuvWindowProcessRegistry.activeLease, isNotNull,
          reason: 'the residue stays owned while the debt persists');
    });

    test(
        'an owner-generation read failure falls back to the legacy arm '
        'inside the rollback protection (B5)', () async {
      final atoms = FakeYuvAtoms();
      final arm = armManager(atoms,
          ownerToken: 'owner-token',
          generation: () async => throw StateError('platform future failed'));
      final plan = planFor(yuvRoute());
      await arm.armForAttempt(plan);
      expect(atoms.yuvDiagEnabled, 1,
          reason: 'the failed generation read degrades to the legacy arm');
      expect(atoms.channelCalls, isEmpty);
      expect(atoms.diagDataSpace, HdrYuvPresentationContract.windowDataSpace);
      await arm.endAttempt(plan);
      expect(atoms.diagDataSpace, 0);
      expect(atoms.yuvDiagEnabled, 0);
    });

    test(
        'an unexpected arm-step failure rolls the pair back without debt '
        '(B5 unified rollback)', () async {
      final atoms = FakeYuvAtoms()..legacySetterFails = true;
      final arm = armManager(atoms,
          ownerToken: 'owner-token',
          generation: () async => null);
      final plan = planFor(yuvRoute());
      await expectLater(
          arm.armForAttempt(plan), throwsA(isA<HdrYuvWindowArmFailure>()));
      expect(atoms.diagDataSpace, 0,
          reason: 'the first atom was rolled back by the unified protection');
      expect(arm.isArmed, isFalse);
      expect(arm.hasCleanupDebt, isFalse);
      // Round 3: the ownership stays registered for the attempt's terminal
      // cleanup even after a clean rollback.
      expect(HdrYuvWindowProcessRegistry.activeLease, isNotNull);
      await arm.endAttempt(plan);
      expect(HdrYuvWindowProcessRegistry.activeLease, isNull);
    });
  });
}

HdrRoute yuvRoute() => const HdrRoute(
      strategy: HdrStrategy.baseLayerConvert,
      presentation: HdrPresentation.nativeHdr,
      outputTransfer: HdrOutputTransfer.pq,
      appliesDynamicMetadata: false,
      topology: HdrTopology.platformView,
      vo: 'gpu-next',
      hwdec: 'surfacetexture',
      targetPrim: 'bt.2020',
      targetTrc: 'pq',
      surfaceTransfer: 'pq-itu',
      offscreenTransfer: 'pq-full',
      stripDvRpu: false,
    );

extension _RouteSurrogate on HdrRoute {
  HdrRoute surrogate({String? hwdec, String? offscreenTransfer = 'pq-full'}) =>
      HdrRoute(
        strategy: strategy,
        presentation: presentation,
        outputTransfer: outputTransfer,
        appliesDynamicMetadata: appliesDynamicMetadata,
        topology: topology,
        vo: vo,
        hwdec: hwdec ?? this.hwdec,
        targetPrim: targetPrim,
        targetTrc: targetTrc,
        surfaceTransfer: surfaceTransfer,
        offscreenTransfer: offscreenTransfer,
        stripDvRpu: stripDvRpu,
        dependencies: dependencies,
      );
}

HdrYuvWindowArm armManager(
  FakeYuvAtoms atoms, {
  String? ownerToken,
  Future<int?> Function()? generation,
}) =>
    HdrYuvWindowArm(
      ownerToken: ownerToken,
      ownerGeneration: generation ?? (() async => 7),
      bindingsResolver: () => atoms.bindings(),
      channel: atoms.channel,
    );

Future<void> pumpUntil(bool Function() condition) async {
  for (var i = 0; i < 5000; i++) {
    if (condition()) return;
    await Future<void>.delayed(Duration.zero);
  }
  fail('pumpUntil condition not met');
}

/// Host mirror of the vendor plugin's process-static reader/writer gate
/// (`ProcessOutputInitGate`): same-key write re-acquisition, any-writer read
/// rejection, any-reader write rejection, key-validated release.
class FakeYuvInitGate {
  int readers = 0;
  int _writerLease = 0;
  Object? writerKey;
  int _nextLease = 0;

  bool beginRead() {
    if (_writerLease != 0) return false;
    readers++;
    return true;
  }

  void endRead() {
    if (readers > 0) readers--;
  }

  /// Lease-id identity (R3-4 mirror): a held lease rejects every other
  /// acquire — the same token included; only the exact held lease retries.
  int beginWrite(Object key, int retryLease) {
    if (_writerLease != 0 || readers > 0) {
      return retryLease != 0 && retryLease == _writerLease ? _writerLease : 0;
    }
    _writerLease = ++_nextLease;
    writerKey = key;
    return _writerLease;
  }

  bool endWrite(int lease) {
    if (_writerLease == 0 || _writerLease != lease) return false;
    _writerLease = 0;
    writerKey = null;
    return true;
  }

  bool get writer => _writerLease != 0;
}

/// Recording fake for the vendor atomics and control channel.
class FakeYuvAtoms {
  /// The process admission gate every manager sharing this fake goes
  /// through (the host mirror of the Java statics).
  final gate = FakeYuvInitGate();

  int diagDataSpace = 0;
  int yuvDiagEnabled = 0;
  final calls = <String>[];
  final channelCalls = <Map<String, Object?>>[];

  /// When set, every channel call throws (missing plugin).
  Object? channelError;

  /// Result of `EnableYuvDiag`; false = ledger refusal.
  bool enableYuvDiagResult = true;

  bool omitDiagSetter = false;
  bool omitYuvDiagSetter = false;
  bool disarmFails = false;

  /// When set, the legacy FFI setter throws (B5 unexpected-step rollback).
  bool legacySetterFails = false;

  HdrYuvWindowFfiBindings bindings() => HdrYuvWindowFfiBindings(
        setDiagDataSpace: omitDiagSetter
            ? null
            : (value) {
                calls.add('diag:$value');
                diagDataSpace = value;
              },
        setYuvDiagEnabled: omitYuvDiagSetter
            ? null
            : (value) {
                calls.add('yuvDiag:$value');
                if (legacySetterFails && value != 0) {
                  throw StateError('legacy setter failed');
                }
                yuvDiagEnabled = value;
              },
        disarmYuvDiag: () {
          calls.add('disarm');
          if (disarmFails) throw StateError('native disarm failed');
          yuvDiagEnabled = 0;
        },
      );

  Future<Object?> channel(String method, Map<String, Object?> arguments) async {
    if (channelError != null) throw channelError!;
    channelCalls.add({...arguments, 'method': method});
    switch (method) {
      case 'EnableYuvDiag':
        // The bound arm sets the native atom (mkvendor_arm_yuv_diag stores
        // flag+format+binding in one sequence).
        if (enableYuvDiagResult) yuvDiagEnabled = 1;
        return enableYuvDiagResult;
      case 'DisableYuvDiag':
        if (disarmFails) throw StateError('channel disarm failed');
        yuvDiagEnabled = 0;
        return true;
      case 'BeginOutputInitRead':
        return gate.beginRead();
      case 'EndOutputInitRead':
        gate.endRead();
        return true;
      case 'BeginOutputInitWrite':
        return gate.beginWrite(
            arguments['ownerToken'] as Object,
            (arguments['leaseId'] as int?) ?? 0);
      case 'EndOutputInitWrite':
        return gate.endWrite((arguments['leaseId'] as int?) ?? 0);
      default:
        throw MissingPluginException(method);
    }
  }
}
