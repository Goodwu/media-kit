import 'dart:async';

import 'package:media_kit/src/player/native/utils/source_transition_gate.dart';
import 'package:synchronized/synchronized.dart';
import 'package:test/test.dart';

Future<void> _turn() => Future<void>.delayed(Duration.zero);

void main() {
  test('default entry and playlist operations queue behind the transition',
      () async {
    final gate = NativeSourceTransitionGate(Lock());
    final entered = Completer<void>();
    final release = Completer<void>();
    final events = <NativeSourceOperation>[];
    final transition = gate.run(() async {
      entered.complete();
      await release.future;
    });
    await entered.future;
    final operations = NativeSourceOperation.values
        .where((operation) => operation != NativeSourceOperation.seek)
        .toList();
    final pending = [
      for (final operation in operations)
        gate.schedule(operation, () async => events.add(operation)),
    ];
    await _turn();
    expect(events, isEmpty);
    release.complete();
    await transition;
    await Future.wait(pending);
    expect(events, operations);
  });

  test('default seek can complete while output transition holds the gate',
      () async {
    final playerLock = Lock();
    final gate = NativeSourceTransitionGate(playerLock);
    final entered = Completer<void>();
    final release = Completer<void>();
    final transition = gate.run(() async {
      entered.complete();
      await release.future;
    });
    await entered.future;
    var sought = false;
    await gate.schedule(NativeSourceOperation.seek, () async {
      expect(playerLock.locked, isTrue);
      sought = true;
    }).timeout(const Duration(seconds: 1));
    expect(sought, isTrue);
    release.complete();
    await transition;
  });

  test('nested synchronized false bypasses both locks for every operation',
      () async {
    final playerLock = Lock();
    final gate = NativeSourceTransitionGate(playerLock);
    final events = <NativeSourceOperation>[];
    await gate
        .run(() => playerLock.synchronized(() async {
              for (final operation in NativeSourceOperation.values) {
                await gate.schedule(operation, () async {
                  events.add(operation);
                }, synchronized: false);
              }
            }))
        .timeout(const Duration(seconds: 1));
    expect(events, NativeSourceOperation.values);
  });

  test('dispose closes admission immediately before its queued cleanup',
      () async {
    final gate = NativeSourceTransitionGate(Lock());
    final entered = Completer<void>();
    final cancelled = Completer<void>();
    final events = <String>[];
    final transition = gate.run(() async {
      entered.complete();
      await cancelled.future;
      events.add('owned transition cleanup');
    });
    await entered.future;
    gate.closeAdmission(() {
      events.add('close admission');
      cancelled.complete();
    });
    expect(events, ['close admission']);
    final disposal = gate.schedule(NativeSourceOperation.dispose, () async {
      events.add('native disposal');
    });
    await Future.wait([transition, disposal]);
    expect(events, [
      'close admission',
      'owned transition cleanup',
      'native disposal',
    ]);
  });

  test('source scheduling acquires the gate before the Player lock', () async {
    final playerLock = Lock();
    final gate = NativeSourceTransitionGate(playerLock);
    final locked = Completer<void>();
    final releasePlayer = Completer<void>();
    final holder = playerLock.synchronized(() async {
      locked.complete();
      await releasePlayer.future;
    });
    await locked.future;
    final events = <String>[];
    final open = gate.schedule(NativeSourceOperation.open, () async {
      events.add('open');
    });
    final followingTransition = gate.run(() async {
      events.add('following transition');
    });
    await _turn();
    expect(events, isEmpty);
    releasePlayer.complete();
    await Future.wait([holder, open, followingTransition]);
    expect(events, ['open', 'following transition']);
  });

  test('a failed transition releases the gate without swallowing its error',
      () async {
    final gate = NativeSourceTransitionGate(Lock());
    final failure = StateError('transition failed');
    await expectLater(
        gate.run<void>(() async => throw failure), throwsA(same(failure)));
    expect(await gate.run<int>(() async => 37), 37);
    var stopped = false;
    await gate.schedule(NativeSourceOperation.stop, () async => stopped = true);
    expect(stopped, isTrue);
  });

  test('independent players do not share source admission', () async {
    final first = NativeSourceTransitionGate(Lock());
    final second = NativeSourceTransitionGate(Lock());
    final entered = Completer<void>();
    final release = Completer<void>();
    final busy = first.run(() async {
      entered.complete();
      await release.future;
    });
    await entered.future;
    var opened = false;
    await second.schedule(
        NativeSourceOperation.open, () async => opened = true);
    expect(opened, isTrue);
    release.complete();
    await busy;
  });
}
