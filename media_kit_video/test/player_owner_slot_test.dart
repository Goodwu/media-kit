import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit_video/media_kit_video.dart';

void main() {
  test('transitions serialize and a failed callback does not poison the queue',
      () async {
    final slot = PlayerOwnerSlot();
    final entered = Completer<void>();
    final release = Completer<void>();
    final order = <int>[];
    final first = slot.transition((tx) async {
      entered.complete();
      await release.future;
      order.add(1);
    });
    await entered.future;
    final second = slot.transition((tx) async => order.add(2));
    expect(order, isEmpty);
    release.complete();
    await Future.wait([first, second]);
    await expectLater(
        slot.transition<void>((tx) async => throw StateError('expected')),
        throwsStateError);
    await slot.transition((tx) async => order.add(3));
    expect(order, [1, 2, 3]);
  });

  test('independent slots do not block each other', () async {
    final firstSlot = PlayerOwnerSlot();
    final secondSlot = PlayerOwnerSlot();
    final entered = Completer<void>();
    final release = Completer<void>();
    final first = firstSlot.transition((tx) async {
      entered.complete();
      await release.future;
    });
    await entered.future;
    var independentRan = false;
    await secondSlot.transition((tx) async => independentRan = true);
    expect(independentRan, isTrue);
    release.complete();
    await first;
  });

  test(
      'failed disposal blocks creation and retains its original disposer for retry',
      () async {
    final slot = PlayerOwnerSlot();
    final owner = Object();
    var attempts = 0;
    var allowRelease = false;
    Future<void> dispose() async {
      attempts++;
      if (!allowRelease) throw StateError('temporary release failure');
    }

    await expectLater(slot.retire(owner, dispose), throwsStateError);
    var created = false;
    await expectLater(
        slot.transition((tx) async => created = true), throwsStateError);
    expect(created, isFalse);
    allowRelease = true;
    await slot.transition((tx) async => created = true);
    expect(created, isTrue);
    expect(attempts, 3);
  });

  test('queued same-owner retirement retries once without double disposal',
      () async {
    final slot = PlayerOwnerSlot();
    final owner = Object();
    var attempts = 0;
    var alternateDisposerCalls = 0;
    Future<void> dispose() async {
      attempts++;
      if (attempts == 1) throw StateError('retry once');
    }

    final first = slot.retire(owner, dispose);
    final retry = slot.retire(owner, () async => alternateDisposerCalls++);
    await expectLater(first, throwsStateError);
    await retry;
    expect(attempts, 2);
    expect(alternateDisposerCalls, 0);
  });

  test('close retirement queues behind creation and before its successor',
      () async {
    final slot = PlayerOwnerSlot();
    final owner = Object();
    final entered = Completer<void>();
    final release = Completer<void>();
    final order = <String>[];
    final create = slot.transition((tx) async {
      entered.complete();
      await release.future;
      order.add('created');
    });
    await entered.future;
    final close = slot.retire(owner, () async => order.add('disposed'));
    final next = slot.transition((tx) async => order.add('successor'));
    release.complete();
    await Future.wait([create, close, next]);
    expect(order, ['created', 'disposed', 'successor']);
  });

  test('completed transition cannot admit more retirements', () async {
    final slot = PlayerOwnerSlot();
    late PlayerOwnerTransition saved;
    await slot.transition((tx) async => saved = tx);
    var disposed = false;
    expect(() => saved.retire(Object(), () async => disposed = true),
        throwsStateError);
    expect(disposed, isFalse);
  });

  test('unawaited admitted retirement drains before the next transition',
      () async {
    final slot = PlayerOwnerSlot();
    final release = Completer<void>();
    final entered = Completer<void>();
    late PlayerOwnerTransition saved;
    var nextRan = false;
    final first = slot.transition((tx) async {
      saved = tx;
      unawaited(tx.retire(Object(), () async {
        entered.complete();
        await release.future;
      }));
    });
    await entered.future;
    final next = slot.transition((tx) async => nextRan = true);
    await Future<void>.delayed(Duration.zero);
    expect(nextRan, isFalse);
    expect(() => saved.retire(Object(), () async {}), throwsStateError);
    release.complete();
    await Future.wait([first, next]);
    expect(nextRan, isTrue);
  });

  test(
      'callback error is preserved while failed admitted cleanup remains pending',
      () async {
    final slot = PlayerOwnerSlot();
    final owner = Object();
    final callbackError = StateError('callback');
    final release = Completer<void>();
    final entered = Completer<void>();
    var attempts = 0;
    var allowRelease = false;
    final first = slot.transition<void>((tx) async {
      unawaited(tx.retire(owner, () async {
        attempts++;
        if (!entered.isCompleted) entered.complete();
        await release.future;
        if (!allowRelease) throw StateError('release');
      }));
      throw callbackError;
    });
    final failure = expectLater(first, throwsA(same(callbackError)));
    await entered.future;
    release.complete();
    await failure;
    allowRelease = true;
    var successorRan = false;
    await slot.transition((tx) async => successorRan = true);
    expect(attempts, 2);
    expect(successorRan, isTrue);
  });
  test(
      'pre-drain before a queued duplicate cannot dispose the same owner twice',
      () async {
    final slot = PlayerOwnerSlot();
    final owner = Object();
    var attempts = 0;
    Future<void> dispose() async {
      attempts++;
      if (attempts == 1) throw StateError('retry');
    }

    final first = slot.retire(owner, dispose);
    final successor = slot.transition((tx) async {});
    final duplicate = slot.retire(owner, dispose);
    await expectLater(first, throwsStateError);
    await successor;
    await duplicate;
    await slot.retire(owner, dispose);
    expect(attempts, 2);
  });

  test('a conflicting retirement cannot replace outstanding cleanup debt',
      () async {
    final slot = PlayerOwnerSlot();
    final owner = Object();
    var attempts = 0;
    var wrongOwnerDisposed = false;
    await expectLater(slot.transition((tx) async {
      try {
        await tx.retire(owner, () async {
          attempts++;
          if (attempts == 1) throw StateError('retry');
        });
      } catch (_) {}
      await tx.retire(Object(), () async => wrongOwnerDisposed = true);
    }), throwsStateError);
    expect(wrongOwnerDisposed, isFalse);
    await slot.transition((tx) async {});
    expect(attempts, 2);
    expect(wrongOwnerDisposed, isFalse);
  });
}
