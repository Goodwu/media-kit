import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit_hdr_lab/common/sources/android_hdr_output_slot.dart';

class Output {
  Output(this.vo);
  final String vo;
}

void main() {
  test('first native output rebuilds even when its VO matches', () async {
    final old = Output('mediacodec_embed');
    final calls = <String>[];
    final slot = AndroidHdrOutputSlot<Output>(
      initial: old,
      rebuildInitial: true,
      voOf: (output) async => output.vo,
      disposeForRebuild: (output) async => calls.add('dispose'),
      create: (vo, _, __) {
        calls.add('create');
        return Output(vo);
      },
      publish: (_) {},
      waitReady: (_) async {},
    );
    await slot.ensure('mediacodec_embed', 'mediacodec');
    expect(calls, ['dispose', 'create']);
    expect(slot.current, isNot(same(old)));
    calls.clear();
    await slot.ensure('mediacodec_embed', 'mediacodec');
    expect(calls, isEmpty);
  });

  test('VO switch disposes old before creating and publishes before bind',
      () async {
    final calls = <String>[];
    final old = Output('mediacodec_embed');
    final slot = AndroidHdrOutputSlot<Output>(
      initial: old,
      voOf: (output) async => output.vo,
      disposeForRebuild: (output) async => calls.add('dispose:${output.vo}'),
      create: (vo, _, __) {
        calls.add('create:$vo');
        return Output(vo);
      },
      publish: (output) => calls.add('publish:${output?.vo}'),
      waitReady: (output) async => calls.add('ready:${output.vo}'),
    );
    await slot.ensure('gpu-next', 'mediacodec');
    expect(calls, [
      'dispose:mediacodec_embed',
      'publish:null',
      'create:gpu-next',
      'publish:gpu-next',
      'ready:gpu-next',
    ]);
    calls.clear();
    await slot.ensure('gpu-next', 'mediacodec');
    expect(calls, ['ready:gpu-next']);
    await slot.ensure('mediacodec_embed', 'mediacodec');
    expect(slot.current!.vo, 'mediacodec_embed');
  });

  test('failed old dispose prevents replacement and is retryable', () async {
    final old = Output('mediacodec_embed');
    var attempts = 0;
    var creates = 0;
    final slot = AndroidHdrOutputSlot<Output>(
      initial: old,
      voOf: (output) async => output.vo,
      disposeForRebuild: (_) async {
        if (++attempts == 1) throw StateError('old output still active');
      },
      create: (vo, _, __) {
        creates++;
        return Output(vo);
      },
      publish: (_) {},
      waitReady: (_) async {},
    );
    await expectLater(slot.ensure('gpu-next', 'mediacodec'), throwsStateError);
    expect(slot.current, same(old));
    expect(creates, 0);
    await slot.ensure('gpu-next', 'mediacodec');
    expect(creates, 1);
  });

  test('failed new bind retires new output before retry', () async {
    final old = Output('mediacodec_embed');
    final held = Completer<void>();
    final calls = <String>[];
    final slot = AndroidHdrOutputSlot<Output>(
      initial: old,
      voOf: (output) async => output.vo,
      disposeForRebuild: (output) async => calls.add('dispose:${output.vo}'),
      create: (vo, _, __) => Output(vo),
      publish: (output) => calls.add('publish:${output?.vo}'),
      waitReady: (output) => output == old ? Future<void>.value() : held.future,
    );
    final switching = slot.ensure('gpu-next', 'mediacodec');
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
    final slot = AndroidHdrOutputSlot<Output>(
      initial: old,
      voOf: (output) async => output.vo,
      disposeForRebuild: (output) async {
        if (identical(output, failed) && ++cleanupAttempts == 1) {
          throw StateError('native output still owned');
        }
      },
      create: (vo, _, __) {
        creations++;
        return failed = Output(vo);
      },
      publish: (_) {},
      waitReady: (output) async {
        if (!identical(output, old)) throw StateError('bind failed');
      },
    );

    await expectLater(slot.ensure('gpu-next', 'mediacodec'), throwsStateError);
    expect(slot.current, same(failed));
    expect(creations, 1);

    await slot.dispose();
    expect(cleanupAttempts, 2);
    expect(slot.current, isNull);
  });

  test('P5 output format change rebuilds even with unchanged VO', () async {
    var disposals = 0;
    var creations = 0;
    final slot = AndroidHdrOutputSlot<Output>(
      initial: Output('gpu-next'),
      voOf: (output) async => output.vo,
      disposeForRebuild: (_) async => disposals++,
      create: (vo, _, __) {
        creations++;
        return Output(vo);
      },
      publish: (_) {},
      waitReady: (_) async {},
    );
    await slot.ensure('gpu-next', 'mediacodec', outputFormat: 'rgb10_a2');
    expect(disposals, 1);
    expect(creations, 1);
    await slot.ensure('gpu-next', 'mediacodec', outputFormat: 'rgb10_a2');
    expect(disposals, 1);
    expect(creations, 1);
  });

  test('PQ to HLG rebuilds same VO and publishes transfer before bind',
      () async {
    final calls = <String>[];
    final slot = AndroidHdrOutputSlot<Output>(
      initial: Output('gpu-next'),
      voOf: (output) async => output.vo,
      disposeForRebuild: (output) async => calls.add('dispose:${output.vo}'),
      create: (vo, _, transfer) {
        calls.add('create:$vo:$transfer');
        return Output(vo);
      },
      publish: (output) => calls.add('publish:${output?.vo}'),
      waitReady: (output) async => calls.add('ready:${output.vo}'),
    );
    await slot.ensure('gpu-next', 'mediacodec',
        outputFormat: 'rgb10_a2', surfaceTransfer: 'pq');
    calls.clear();
    await slot.ensure('gpu-next', 'mediacodec',
        outputFormat: 'rgb10_a2', surfaceTransfer: 'hlg');
    expect(calls, [
      'dispose:gpu-next',
      'publish:null',
      'create:gpu-next:hlg',
      'publish:gpu-next',
      'ready:gpu-next',
    ]);
    calls.clear();
    await slot.ensure('gpu-next', 'mediacodec',
        outputFormat: 'rgb10_a2', surfaceTransfer: 'hlg');
    expect(calls, ['ready:gpu-next']);
  });

  test('PQ to HLG failure retains old output until it can be disposed',
      () async {
    final initial = Output('gpu-next');
    var disposals = 0;
    var creations = 0;
    final slot = AndroidHdrOutputSlot<Output>(
      initial: initial,
      voOf: (output) async => output.vo,
      disposeForRebuild: (_) async {
        if (++disposals == 2) throw StateError('old PQ Surface still owned');
      },
      create: (vo, _, __) {
        creations++;
        return Output(vo);
      },
      publish: (_) {},
      waitReady: (_) async {},
    );
    await slot.ensure('gpu-next', 'mediacodec',
        outputFormat: 'rgb10_a2', surfaceTransfer: 'pq');
    final pq = slot.current;
    await expectLater(
      slot.ensure('gpu-next', 'mediacodec',
          outputFormat: 'rgb10_a2', surfaceTransfer: 'hlg'),
      throwsStateError,
    );
    expect(slot.current, same(pq));
    expect(creations, 1);
    await slot.ensure('gpu-next', 'mediacodec',
        outputFormat: 'rgb10_a2', surfaceTransfer: 'hlg');
    expect(creations, 2);
    expect(slot.current, isNot(same(pq)));
  });

  test('new output creation failure leaves a retryable empty slot', () async {
    var creations = 0;
    final slot = AndroidHdrOutputSlot<Output>(
      initial: Output('mediacodec_embed'),
      voOf: (output) async => output.vo,
      disposeForRebuild: (_) async {},
      create: (vo, _, __) {
        if (++creations == 1) throw StateError('creation failed');
        return Output(vo);
      },
      publish: (_) {},
      waitReady: (_) async {},
    );
    await expectLater(slot.ensure('gpu-next', 'mediacodec'), throwsStateError);
    expect(slot.current, isNull);
    await slot.ensure('gpu-next', 'mediacodec');
    expect(slot.current!.vo, 'gpu-next');
  });
}
