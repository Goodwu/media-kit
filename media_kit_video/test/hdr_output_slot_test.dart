import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' show Media;
import 'package:media_kit_video/src/hdr/hdr_capabilities.dart';
import 'package:media_kit_video/src/hdr/hdr_open_plan.dart';
import 'package:media_kit_video/src/hdr/hdr_output_slot.dart';
import 'package:media_kit_video/src/hdr/hdr_output_contract.dart';
import 'package:media_kit_video/src/hdr/hdr_route.dart';
import 'package:media_kit_video/src/hdr/hdr_source_descriptor.dart';
import 'package:media_kit_video/src/hdr/hdr_strategy.dart';
import 'package:media_kit_video/src/hdr/hdr_yuv_presentation_contract.dart';
import 'package:media_kit_video/src/hdr/hdr_yuv_window_arm.dart';

/// Existing lifecycle assertions plus complete request identity coverage.
class Output {
  Output(this.vo);
  final String vo;
}

void main() {
  // The process-level lease registry (B1) is static; isolate it per test.
  setUp(HdrYuvWindowProcessRegistry.resetForTesting);

  test('first native output rebuilds even when its VO matches', () async {
    final old = Output('mediacodec_embed');
    final calls = <String>[];
    final slot = HdrOutputSlot<Output>(
      initial: old,
      rebuildInitial: true,
      voOf: (output) async => output.vo,
      disposeForRebuild: (output) async => calls.add('dispose'),
      create: (contract) {
        final vo = contract.vo;
        calls.add('create');
        return Output(vo);
      },
      publish: (_) {},
      waitReady: (_) async {},
    );
    await slot.ensure(_contract('mediacodec_embed', 'mediacodec'));
    expect(calls, ['dispose', 'create']);
    expect(slot.current, isNot(same(old)));
    calls.clear();
    await slot.ensure(_contract('mediacodec_embed', 'mediacodec'));
    expect(calls, isEmpty);
  });

  test('VO switch disposes old before creating and publishes before bind',
      () async {
    final calls = <String>[];
    final old = Output('mediacodec_embed');
    final slot = HdrOutputSlot<Output>(
      initial: old,
      voOf: (output) async => output.vo,
      disposeForRebuild: (output) async => calls.add('dispose:${output.vo}'),
      create: (contract) {
        final vo = contract.vo;
        calls.add('create:$vo');
        return Output(vo);
      },
      publish: (output) => calls.add('publish:${output?.vo}'),
      waitReady: (output) async => calls.add('ready:${output.vo}'),
    );
    await slot.ensure(_contract('gpu-next', 'mediacodec'));
    expect(calls, [
      'dispose:mediacodec_embed',
      'publish:null',
      'create:gpu-next',
      'publish:gpu-next',
      'ready:gpu-next',
    ]);
    calls.clear();
    await slot.ensure(_contract('gpu-next', 'mediacodec'));
    expect(calls, ['ready:gpu-next']);
    await slot.ensure(_contract('mediacodec_embed', 'mediacodec'));
    expect(slot.current!.vo, 'mediacodec_embed');
  });

  test('failed old dispose prevents replacement and is retryable', () async {
    final old = Output('mediacodec_embed');
    var attempts = 0;
    var creates = 0;
    final slot = HdrOutputSlot<Output>(
      initial: old,
      voOf: (output) async => output.vo,
      disposeForRebuild: (_) async {
        if (++attempts == 1) throw StateError('old output still active');
      },
      create: (contract) {
        final vo = contract.vo;
        creates++;
        return Output(vo);
      },
      publish: (_) {},
      waitReady: (_) async {},
    );
    await expectLater(
        slot.ensure(_contract('gpu-next', 'mediacodec')), throwsStateError);
    expect(slot.current, same(old));
    expect(creates, 0);
    await slot.ensure(_contract('gpu-next', 'mediacodec'));
    expect(creates, 1);
  });

  test('failed new bind retires new output before retry', () async {
    final old = Output('mediacodec_embed');
    final held = Completer<void>();
    final calls = <String>[];
    final slot = HdrOutputSlot<Output>(
      initial: old,
      voOf: (output) async => output.vo,
      disposeForRebuild: (output) async => calls.add('dispose:${output.vo}'),
      create: (contract) => Output(contract.vo),
      publish: (output) => calls.add('publish:${output?.vo}'),
      waitReady: (output) => output == old ? Future<void>.value() : held.future,
    );
    final switching = slot.ensure(_contract('gpu-next', 'mediacodec'));
    while (!calls.contains('publish:gpu-next')) {
      await Future<void>.delayed(Duration.zero);
    }
    held.completeError(StateError('bind failed'));
    await expectLater(switching, throwsStateError);
    expect(slot.current, isNull);
    expect(calls.last, 'publish:null');
  });

  test('failed bind and failed cleanup retain output ownership for retry',
      () async {
    final old = Output('mediacodec_embed');
    Output? failed;
    var cleanupAttempts = 0;
    var creations = 0;
    final slot = HdrOutputSlot<Output>(
      initial: old,
      voOf: (output) async => output.vo,
      disposeForRebuild: (output) async {
        if (identical(output, failed) && ++cleanupAttempts == 1) {
          throw StateError('native output still owned');
        }
      },
      create: (contract) {
        final vo = contract.vo;
        creations++;
        return failed = Output(vo);
      },
      publish: (_) {},
      waitReady: (output) async {
        if (!identical(output, old)) throw StateError('bind failed');
      },
    );

    await expectLater(
        slot.ensure(_contract('gpu-next', 'mediacodec')), throwsStateError);
    expect(slot.current, same(failed));
    expect(creations, 1);

    await slot.dispose();
    expect(cleanupAttempts, 2);
    expect(slot.current, isNull);
  });

  test('P5 output format change rebuilds even with unchanged VO', () async {
    var disposals = 0;
    var creations = 0;
    final slot = HdrOutputSlot<Output>(
      initial: Output('gpu-next'),
      voOf: (output) async => output.vo,
      disposeForRebuild: (_) async => disposals++,
      create: (contract) {
        final vo = contract.vo;
        creations++;
        return Output(vo);
      },
      publish: (_) {},
      waitReady: (_) async {},
    );
    await slot
        .ensure(_contract('gpu-next', 'mediacodec', outputFormat: 'rgb10_a2'));
    expect(disposals, 1);
    expect(creations, 1);
    await slot
        .ensure(_contract('gpu-next', 'mediacodec', outputFormat: 'rgb10_a2'));
    expect(disposals, 1);
    expect(creations, 1);
  });

  test('PQ to HLG rebuilds same VO and publishes transfer before bind',
      () async {
    final calls = <String>[];
    final slot = HdrOutputSlot<Output>(
      initial: Output('gpu-next'),
      voOf: (output) async => output.vo,
      disposeForRebuild: (output) async => calls.add('dispose:${output.vo}'),
      create: (contract) {
        final vo = contract.vo;
        final transfer = contract.surfaceTransfer;
        calls.add('create:$vo:$transfer');
        return Output(vo);
      },
      publish: (output) => calls.add('publish:${output?.vo}'),
      waitReady: (output) async => calls.add('ready:${output.vo}'),
    );
    await slot.ensure(_contract('gpu-next', 'mediacodec',
        outputFormat: 'rgb10_a2', surfaceTransfer: 'pq'));
    calls.clear();
    await slot.ensure(_contract('gpu-next', 'mediacodec',
        outputFormat: 'rgb10_a2', surfaceTransfer: 'hlg'));
    expect(calls, [
      'dispose:gpu-next',
      'publish:null',
      'create:gpu-next:hlg',
      'publish:gpu-next',
      'ready:gpu-next',
    ]);
    calls.clear();
    await slot.ensure(_contract('gpu-next', 'mediacodec',
        outputFormat: 'rgb10_a2', surfaceTransfer: 'hlg'));
    expect(calls, ['ready:gpu-next']);
  });

  test('PQ to HLG failure retains old output until it can be disposed',
      () async {
    final initial = Output('gpu-next');
    var disposals = 0;
    var creations = 0;
    final slot = HdrOutputSlot<Output>(
      initial: initial,
      voOf: (output) async => output.vo,
      disposeForRebuild: (_) async {
        if (++disposals == 2) throw StateError('old PQ Surface still owned');
      },
      create: (contract) {
        final vo = contract.vo;
        creations++;
        return Output(vo);
      },
      publish: (_) {},
      waitReady: (_) async {},
    );
    await slot.ensure(_contract('gpu-next', 'mediacodec',
        outputFormat: 'rgb10_a2', surfaceTransfer: 'pq'));
    final pq = slot.current;
    await expectLater(
      slot.ensure(_contract('gpu-next', 'mediacodec',
          outputFormat: 'rgb10_a2', surfaceTransfer: 'hlg')),
      throwsStateError,
    );
    expect(slot.current, same(pq));
    expect(creations, 1);
    await slot.ensure(_contract('gpu-next', 'mediacodec',
        outputFormat: 'rgb10_a2', surfaceTransfer: 'hlg'));
    expect(creations, 2);
    expect(slot.current, isNot(same(pq)));
  });

  test('new output creation failure leaves a retryable empty slot', () async {
    var creations = 0;
    final slot = HdrOutputSlot<Output>(
      initial: Output('mediacodec_embed'),
      voOf: (output) async => output.vo,
      disposeForRebuild: (_) async {},
      create: (contract) {
        final vo = contract.vo;
        if (++creations == 1) throw StateError('creation failed');
        return Output(vo);
      },
      publish: (_) {},
      waitReady: (_) async {},
    );
    await expectLater(
        slot.ensure(_contract('gpu-next', 'mediacodec')), throwsStateError);
    expect(slot.current, isNull);
    await slot.ensure(_contract('gpu-next', 'mediacodec'));
    expect(slot.current!.vo, 'gpu-next');
  });

  test('an initial null slot creates without disposing', () async {
    final calls = <String>[];
    final slot = HdrOutputSlot<Output>(
      initial: null,
      voOf: (output) async => output.vo,
      disposeForRebuild: (_) async => calls.add('dispose'),
      create: (contract) {
        final vo = contract.vo;
        calls.add('create:$vo');
        return Output(vo);
      },
      publish: (output) => calls.add('publish:${output?.vo}'),
      waitReady: (_) async {},
    );
    expect(slot.current, isNull);
    await slot.ensure(_contract('gpu-next', 'mediacodec'));
    expect(calls, ['create:gpu-next', 'publish:gpu-next']);
    expect(slot.current!.vo, 'gpu-next');
  });
  test('unknown initial contract rebuilds despite matching VO and ready output',
      () async {
    final initial = Output('gpu-next');
    var disposals = 0;
    final request = _contract('gpu-next', 'mediacodec');
    final slot = HdrOutputSlot<Output>(
      initial: initial,
      voOf: (output) async => output.vo,
      disposeForRebuild: (_) async => disposals++,
      create: (contract) => Output(contract.vo),
      publish: (_) {},
      waitReady: (_) async {},
    );
    await slot.ensure(request);
    expect(disposals, 1);
    expect(slot.current, isNot(same(initial)));
  });

  const base = HdrOutputContract(
    vo: 'gpu-next',
    topology: HdrTopology.platformView,
    requestedHwdec: 'mediacodec',
    gpuApi: 'opengl',
    eglOutputFormat: 'rgb10_a2',
    surfacePixelFormat: 'rgba8888',
    surfaceTransfer: 'pq-itu',
    offscreenTransfer: 'pq-full',
  );
  final changes = <String, HdrOutputContract>{
    'hwdec': _changed(base, hwdec: 'mediacodec-copy'),
    'topology': _changed(base, topology: HdrTopology.texture),
    'gpu API': _changed(base, gpuApi: 'vulkan'),
    'EGL format': _changed(base, eglFormat: 'rgba8'),
    'Surface pixel format': _changed(base, pixelFormat: 'rgba1010102'),
    'Surface transfer': _changed(base, transfer: 'hlg'),
    'offscreen transfer': _changed(base, offscreen: 'hlg-full'),
  };
  for (final entry in changes.entries) {
    test('same VO rebuilds for changed ${entry.key} and reuses equal contract',
        () async {
      final calls = <String>[];
      HdrOutputContract? createdRequest;
      final slot = HdrOutputSlot<Output>(
        initial: Output('gpu-next'),
        initialContract: base,
        voOf: (output) async => output.vo,
        disposeForRebuild: (_) async => calls.add('dispose'),
        create: (contract) {
          createdRequest = contract;
          calls.add('create');
          return Output(contract.vo);
        },
        publish: (output) => calls.add('publish:${output?.vo}'),
        waitReady: (_) async => calls.add('ready'),
      );
      await slot.ensure(entry.value);
      expect(createdRequest, same(entry.value));
      expect(calls,
          ['dispose', 'publish:null', 'create', 'publish:gpu-next', 'ready']);
      calls.clear();
      await slot.ensure(_changed(entry.value));
      expect(calls, ['ready']);
    });
  }

  test(
      'failed bind plus failed cleanup cannot reuse an accidentally ready output',
      () async {
    var creations = 0;
    var disposals = 0;
    var readyCalls = 0;
    final calls = <String>[];
    final contract = _contract('gpu-next', 'mediacodec');
    final slot = HdrOutputSlot<Output>(
      initial: null,
      voOf: (output) async => output.vo,
      disposeForRebuild: (_) async {
        calls.add('dispose');
        if (++disposals <= 2) throw StateError('still owned');
      },
      create: (contract) {
        creations++;
        calls.add('create');
        return Output(contract.vo);
      },
      publish: (output) => calls.add('publish:${output?.vo}'),
      waitReady: (_) async {
        readyCalls++;
        if (readyCalls == 1) throw StateError('bind failed');
      },
    );
    await expectLater(slot.ensure(contract), throwsStateError);
    final failed = slot.current;
    await expectLater(slot.ensure(contract), throwsStateError);
    expect(slot.current, same(failed));
    expect(creations, 1);
    expect(readyCalls, 1);
    calls.clear();
    await slot.ensure(contract);
    expect(calls, ['dispose', 'publish:null', 'create', 'publish:gpu-next']);
    expect(slot.current, isNot(same(failed)));
    expect(readyCalls, 2);
  });

  test('publication failure retires the created output and preserves its error',
      () async {
    final failure = StateError('publication failed');
    final calls = <String>[];
    var publications = 0;
    final request = _contract('gpu-next', 'mediacodec');
    final slot = HdrOutputSlot<Output>(
      initial: null,
      voOf: (output) async => output.vo,
      disposeForRebuild: (_) async => calls.add('dispose'),
      create: (contract) {
        calls.add('create');
        return Output(contract.vo);
      },
      publish: (output) {
        calls.add('publish:${output?.vo}');
        if (output != null && ++publications == 1) throw failure;
      },
      waitReady: (_) async => calls.add('ready'),
    );
    await expectLater(slot.ensure(request), throwsA(same(failure)));
    expect(calls, ['create', 'publish:gpu-next', 'dispose', 'publish:null']);
    expect(slot.current, isNull);
    calls.clear();
    await slot.ensure(request);
    expect(calls, ['create', 'publish:gpu-next', 'ready']);
  });

  test('publication and cleanup failures retain ownership without ready reuse',
      () async {
    final failure = StateError('publication failed');
    final cleanupFailure = StateError('still owned');
    var creations = 0;
    var disposals = 0;
    var publications = 0;
    var readyCalls = 0;
    final calls = <String>[];
    final request = _contract('gpu-next', 'mediacodec');
    final slot = HdrOutputSlot<Output>(
      initial: null,
      voOf: (output) async => output.vo,
      disposeForRebuild: (_) async {
        calls.add('dispose');
        if (++disposals <= 2) throw cleanupFailure;
      },
      create: (contract) {
        creations++;
        calls.add('create');
        return Output(contract.vo);
      },
      publish: (output) {
        calls.add('publish:${output?.vo}');
        if (output != null && ++publications == 1) throw failure;
      },
      waitReady: (_) async => readyCalls++,
    );
    await expectLater(slot.ensure(request), throwsA(same(failure)));
    final failed = slot.current;
    expect(failed, isNotNull);
    expect(calls, ['create', 'publish:gpu-next', 'dispose']);
    await expectLater(slot.ensure(request), throwsA(same(cleanupFailure)));
    expect(slot.current, same(failed));
    expect(creations, 1);
    expect(publications, 1);
    expect(readyCalls, 0);
    calls.clear();
    await slot.ensure(request);
    expect(calls, ['dispose', 'publish:null', 'create', 'publish:gpu-next']);
    expect(slot.current, isNot(same(failed)));
    expect(creations, 2);
    expect(readyCalls, 1);
  });

  group('internal preparation hook', () {
    test('replacement arms after the old disposal, strictly before create',
        () async {
      final calls = <String>[];
      final slot = HdrOutputSlot<Output>(
        initial: Output('mediacodec_embed'),
        voOf: (output) async => output.vo,
        disposeForRebuild: (_) async => calls.add('dispose'),
        create: (contract) {
          calls.add('create');
          return Output(contract.vo);
        },
        publish: (output) => calls.add('publish:${output?.vo}'),
        waitReady: (_) async => calls.add('ready'),
      );
      await slot.ensure(_contract('gpu-next', 'mediacodec'),
          internalPrepare: (_) async => calls.add('prepare'));
      expect(calls, [
        'dispose',
        'publish:null',
        'prepare',
        'create',
        'publish:gpu-next',
        'ready',
      ]);
    });

    test('a delayed hook future blocks the new output initialization',
        () async {
      final gate = Completer<void>();
      var created = false;
      final slot = HdrOutputSlot<Output>(
        initial: null,
        voOf: (output) async => output.vo,
        disposeForRebuild: (_) async {},
        create: (contract) {
          created = true;
          return Output(contract.vo);
        },
        publish: (_) {},
        waitReady: (_) async {},
      );
      final pending = slot.ensure(_contract('gpu-next', 'mediacodec'),
          internalPrepare: (_) => gate.future);
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(created, isFalse,
          reason: 'the arm ACK barrier must not leak through to creation');
      gate.complete();
      await pending;
      expect(created, isTrue);
    });

    test('hook failure creates no new output and keeps the attempt failed',
        () async {
      final old = Output('mediacodec_embed');
      var created = false;
      final slot = HdrOutputSlot<Output>(
        initial: old,
        voOf: (output) async => output.vo,
        disposeForRebuild: (_) async {},
        create: (contract) {
          created = true;
          return Output(contract.vo);
        },
        publish: (_) {},
        waitReady: (_) async {},
      );
      await expectLater(
        slot.ensure(_contract('gpu-next', 'mediacodec'),
            internalPrepare: (_) async => throw StateError('arm refused')),
        throwsStateError,
      );
      expect(created, isFalse);
      expect(slot.current, isNull);
    });

    test('reuse runs the hook before accepting the existing output', () async {
      final calls = <String>[];
      final contract = _contract('gpu-next', 'mediacodec',
          outputFormat: 'rgb10_a2', surfaceTransfer: 'pq');
      final slot = HdrOutputSlot<Output>(
        initial: null,
        initialContract: contract,
        voOf: (output) async => output.vo,
        disposeForRebuild: (_) async => calls.add('dispose'),
        create: (contract) {
          calls.add('create');
          return Output(contract.vo);
        },
        publish: (output) => calls.add('publish:${output?.vo}'),
        waitReady: (_) async => calls.add('ready'),
      );
      // Establish the output, then reuse it: the hook runs, then the reuse.
      await slot.ensure(contract);
      calls.clear();
      await slot.ensure(contract,
          internalPrepare: (_) async => calls.add('prepare'));
      expect(calls, ['prepare', 'ready']);
    });

    test('reuse hook failure is not silently downgraded to a replacement',
        () async {
      var creations = 0;
      final contract = _contract('gpu-next', 'mediacodec',
          outputFormat: 'rgb10_a2', surfaceTransfer: 'pq');
      final slot = HdrOutputSlot<Output>(
        initial: null,
        initialContract: contract,
        voOf: (output) async => output.vo,
        disposeForRebuild: (_) async {},
        create: (contract) {
          creations++;
          return Output(contract.vo);
        },
        publish: (_) {},
        waitReady: (_) async {},
      );
      await slot.ensure(contract);
      creations = 0;
      await expectLater(
        slot.ensure(contract,
            internalPrepare: (_) async => throw StateError('arm refused')),
        throwsStateError,
      );
      expect(creations, 0, reason: 'a failed arm must not create a new output');
    });

    test('failed bind re-runs the hook once before the replacement create',
        () async {
      // The reuse segment's waitReady failure falls through to a
      // replacement: the hook barrier runs again (same attempt contract,
      // idempotent for its owner) before the create.
      final calls = <String>[];
      final contract = _contract('gpu-next', 'mediacodec',
          outputFormat: 'rgb10_a2', surfaceTransfer: 'pq');
      var failNextReady = false;
      final slot = HdrOutputSlot<Output>(
        initial: null,
        initialContract: contract,
        voOf: (output) async => output.vo,
        disposeForRebuild: (_) async => calls.add('dispose'),
        create: (contract) {
          calls.add('create');
          return Output(contract.vo);
        },
        publish: (output) => calls.add('publish:${output?.vo}'),
        waitReady: (_) async {
          if (failNextReady) {
            failNextReady = false;
            throw StateError('bind failed');
          }
        },
      );
      await slot.ensure(contract);
      calls.clear();
      failNextReady = true;
      await slot.ensure(contract,
          internalPrepare: (_) async => calls.add('prepare'));
      expect(calls, [
        'prepare',
        'dispose',
        'publish:null',
        'prepare',
        'create',
        'publish:gpu-next',
      ]);
    });

    test(
        'a reuse failure retires the native pair and the replacement truly '
        're-arms through the real manager (B3)', () async {
      // Real HdrYuvWindowArm (not a hook stub): the second hook after the
      // retirement must penetrate any arm cache and re-arm, because the
      // retired output's owner termination already cleared the native YUV
      // diag atom on the Java side.
      final calls = <String>[];
      final atoms = _SlotArmAtoms(calls);
      final arm = HdrYuvWindowArm(
        ownerToken: 'owner-token',
        ownerGeneration: () async => null,
        bindingsResolver: () => atoms.bindings(),
        channel: atoms.channel,
      );
      final plan = _slotYuvPlan();
      final contract = _contract('gpu-next', 'surfacetexture',
          outputFormat: 'rgb10_a2', surfaceTransfer: 'pq-itu');
      var failNextReady = false;
      final slot = HdrOutputSlot<Output>(
        initial: null,
        initialContract: contract,
        voOf: (output) async => output.vo,
        // Simulates the Java owner-termination disarm the retirement runs.
        disposeForRebuild: (_) async {
          calls.add('dispose');
          atoms.yuvDiagEnabled = 0;
        },
        create: (contract) {
          calls.add('create');
          return Output(contract.vo);
        },
        publish: (output) => calls.add('publish:${output?.vo}'),
        waitReady: (_) async {
          if (failNextReady) {
            failNextReady = false;
            throw StateError('bind failed');
          }
        },
      );
      // Establish the armed output.
      await slot.ensure(contract,
          internalPrepare: (_) => arm.armForAttempt(plan));
      expect(atoms.yuvDiagEnabled, 1);
      expect(atoms.diagDataSpace,
          HdrYuvPresentationContract.windowDataSpace);
      calls.clear();
      // The reuse's readiness fails; the retirement clears the YUV atom
      // (termination); the replacement's hook must re-arm it for real.
      failNextReady = true;
      await slot.ensure(contract,
          internalPrepare: (_) => arm.armForAttempt(plan));
      // Round 3: each hook first retires the previous arm's diag atom (the
      // retire/re-arm cycle), then re-arms the pair. The retirement still
      // happens strictly between the second hook's retire and its re-arm.
      expect(calls, [
        'disarm:diag',
        'arm:diag',
        'arm',
        'dispose',
        'publish:null',
        'disarm:diag',
        'arm:diag',
        'arm',
        'create',
        'publish:gpu-next',
      ]);
      // The rebuilt output is authorized: the atoms describe a live arm for
      // its attempt, not a retired one.
      expect(atoms.yuvDiagEnabled, 1,
          reason: 'the replacement create ran under a re-armed pair');
      expect(atoms.diagDataSpace,
          HdrYuvPresentationContract.windowDataSpace);
      await arm.endAttempt(plan);
      expect(atoms.yuvDiagEnabled, 0);
      expect(atoms.diagDataSpace, 0);
    });

    test(
        'a guarded replacement admits BEFORE the retirement and arms after '
        'it (B1 round 3 ordering)', () async {
      final calls = <String>[];
      final atoms = _SlotArmAtoms(calls);
      final arm = HdrYuvWindowArm(
        ownerToken: 'owner-token',
        ownerGeneration: () async => null,
        bindingsResolver: () => atoms.bindings(),
        channel: atoms.channel,
      );
      final plan = _slotYuvPlan();
      final contract = _contract('gpu-next', 'surfacetexture',
          outputFormat: 'rgb10_a2', surfaceTransfer: 'pq-itu');
      final slot = HdrOutputSlot<Output>(
        initial: Output('mediacodec_embed'),
        voOf: (output) async => output.vo,
        disposeForRebuild: (_) async => calls.add('dispose'),
        create: (contract) {
          calls.add('create');
          return Output(contract.vo);
        },
        publish: (output) => calls.add('publish:${output?.vo}'),
        waitReady: (_) async => calls.add('ready'),
      );
      await arm.initializeOutput(plan, () => slot.ensure(contract,
              internalPrepare: (_) => arm.armForAttempt(plan)));
      // The five time points in order: process admission, old-output
      // retirement, the arm, the creation, the bind completion.
      expect(calls, [
        'admit:write',
        'dispose',
        'publish:null',
        'arm:diag',
        'arm',
        'create',
        'publish:gpu-next',
        'ready',
      ]);
      // The write admission outlives the initialization (no EndOutputInitWrite
      // yet) and is released by the terminal cleanup.
      expect(calls, isNot(contains('release:write')));
      expect(atoms.gate.writer, isTrue);
      await arm.endAttempt(plan);
      expect(atoms.gate.writer, isFalse);
      expect(atoms.diagDataSpace, 0);
    });

    test(
        'a foreign live legacy arm rejects the guarded initialization '
        'before ANY teardown (zero side effects)', () async {
      final calls = <String>[];
      final holderAtoms = _SlotArmAtoms(calls);
      final holder = HdrYuvWindowArm(
        ownerToken: 'owner-a',
        ownerGeneration: () async => null,
        bindingsResolver: () => holderAtoms.bindings(),
        channel: holderAtoms.channel,
      );
      final other = HdrYuvWindowArm(
        ownerToken: 'owner-b',
        ownerGeneration: () async => null,
        bindingsResolver: () => holderAtoms.bindings(),
        channel: holderAtoms.channel,
      );
      // The holder's live legacy arm (unbound, generation unavailable).
      final heldPlan = _slotYuvPlan();
      await holder.armForAttempt(heldPlan);
      expect(holderAtoms.yuvDiagEnabled, 1);
      final before = List.of(calls);
      // Another session's guarded replacement: rejected at admission —
      // BEFORE the retirement — so its old output is never disposed.
      final contract = _contract('gpu-next', 'mediacodec',
          outputFormat: 'rgb10_a2', surfaceTransfer: 'pq');
      final slot = HdrOutputSlot<Output>(
        initial: Output('mediacodec_embed'),
        voOf: (output) async => output.vo,
        disposeForRebuild: (_) async => calls.add('dispose'),
        create: (contract) {
          calls.add('create');
          return Output(contract.vo);
        },
        publish: (output) => calls.add('publish:${output?.vo}'),
        waitReady: (_) async => calls.add('ready'),
      );
      await expectLater(
        other.initializeOutput(_slotYuvPlan(),
            () => slot.ensure(contract, internalPrepare: (_) => other.armForAttempt(_slotYuvPlan()))),
        throwsA(isA<HdrYuvWindowLeaseConflict>()),
      );
      expect(calls.skip(before.length), isEmpty,
          reason: 'the rejected initializer performed no teardown at all');
      expect(slot.current!.vo, 'mediacodec_embed',
          reason: 'the old output is untouched');
      expect(holderAtoms.yuvDiagEnabled, 1,
          reason: 'the holder is unaffected');
      expect(holderAtoms.diagDataSpace,
          HdrYuvPresentationContract.windowDataSpace);
      await holder.endAttempt(heldPlan);
      expect(holderAtoms.yuvDiagEnabled, 0);
    });
  });
}

HdrOpenPlan _slotYuvPlan() {
  const route = HdrRoute(
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
  const source = HdrSourceDescriptor(
    codec: 'hevc',
    transfer: 'hlg',
    primaries: 'bt.2020',
    dynamicMetadata: HdrDynamicMetadata.dolbyVision,
    dvProfile: 8,
    dvCompatibilityId: 4,
    enhancementLayer: false,
  );
  const candidate = HdrCandidate(
    strategy: HdrStrategy.baseLayerConvert,
    maturity: HdrStrategyMaturity.verified,
    feasible: true,
    route: route,
  );
  return HdrOpenPlan(
    media: Media('test://source'),
    source: source,
    sourceOrigin: null,
    capabilities: HdrCapabilities(
      sdkInt: 24,
      displayHdrTypes: {2},
      hevcDecoders: [],
      dolbyVisionDecoders: [],
      p5PipelineAvailable: true,
      dataSpaceBridgeLoaded: true,
      dataSpaceExt: HdrDataSpaceExtInfo(
        id: 'lg-pq',
        applicable: true,
        pqPresentation: HdrPqPresentation(rgbSurface: false, yuvWindow: true),
        yuvWindowArmApi: 1,
      ),
    ),
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

/// Atoms fake for the real-manager slot test: records arm/disarm events into
/// the shared timeline and simulates the native atomics plus the process
/// admission gate (the host mirror of the Java statics).
class _SlotArmAtoms {
  _SlotArmAtoms(this.timeline);
  final List<String> timeline;
  int diagDataSpace = 0;
  int yuvDiagEnabled = 0;

  /// Host mirror of `ProcessOutputInitGate`.
  final gate = _SlotInitGate();

  HdrYuvWindowFfiBindings bindings() => HdrYuvWindowFfiBindings(
        setDiagDataSpace: (value) {
          diagDataSpace = value;
          timeline.add(value == 0 ? 'disarm:diag' : 'arm:diag');
        },
        setYuvDiagEnabled: (value) {
          yuvDiagEnabled = value;
          if (value != 0) timeline.add('arm');
        },
        disarmYuvDiag: () => yuvDiagEnabled = 0,
      );

  Future<Object?> channel(String method, Map<String, Object?> arguments) async {
    switch (method) {
      case 'EnableYuvDiag':
        yuvDiagEnabled = 1;
        timeline.add('arm');
        return true;
      case 'DisableYuvDiag':
        yuvDiagEnabled = 0;
        return true;
      case 'BeginOutputInitRead':
        return gate.beginRead();
      case 'EndOutputInitRead':
        gate.endRead();
        return true;
      case 'BeginOutputInitWrite':
        timeline.add('admit:write');
        return gate.beginWrite(
            arguments['ownerToken'] as Object,
            (arguments['leaseId'] as int?) ?? 0);
      case 'EndOutputInitWrite':
        return gate.endWrite((arguments['leaseId'] as int?) ?? 0);
      default:
        return null;
    }
  }
}

class _SlotInitGate {
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

HdrOutputContract _contract(String vo, String hwdec,
        {String? outputFormat, String? surfaceTransfer}) =>
    HdrOutputContract(
      vo: vo,
      topology: surfaceTransfer != null || vo == 'mediacodec_embed'
          ? HdrTopology.platformView
          : HdrTopology.texture,
      requestedHwdec: hwdec,
      eglOutputFormat: outputFormat,
      surfaceTransfer: surfaceTransfer,
    );

HdrOutputContract _changed(
  HdrOutputContract base, {
  String? hwdec,
  HdrTopology? topology,
  String? gpuApi,
  String? eglFormat,
  String? pixelFormat,
  String? transfer,
  String? offscreen,
}) =>
    HdrOutputContract(
      vo: base.vo,
      topology: topology ?? base.topology,
      requestedHwdec: hwdec ?? base.requestedHwdec,
      gpuApi: gpuApi ?? base.gpuApi,
      eglOutputFormat: eglFormat ?? base.eglOutputFormat,
      surfacePixelFormat: pixelFormat ?? base.surfacePixelFormat,
      surfaceTransfer: transfer ?? base.surfaceTransfer,
      offscreenTransfer: offscreen ?? base.offscreenTransfer,
    );
