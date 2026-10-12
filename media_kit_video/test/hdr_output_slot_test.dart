import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit_video/src/hdr/hdr_output_slot.dart';
import 'package:media_kit_video/src/hdr/hdr_output_contract.dart';
import 'package:media_kit_video/src/hdr/hdr_route.dart';

/// Existing lifecycle assertions plus complete request identity coverage.
class Output {
  Output(this.vo);
  final String vo;
}

void main() {
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
