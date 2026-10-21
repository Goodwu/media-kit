import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

class _Player extends Fake implements Player {
  PlayerState currentState = const PlayerState();
  final calls = <String>[];
  @override
  bool disposed = false;
  bool failRate = false;
  Future<void> Function(double)? rateAction;
  Future<void> Function(double)? volumeAction;
  @override
  PlayerState get state => currentState;
  @override
  Future<void> open(Playable media,
      {bool play = true, bool synchronized = true}) async {
    calls.add('open:$play');
  }

  @override
  Future<void> setRate(double rate, {bool synchronized = true}) async {
    calls.add('rate:$rate');
    await rateAction?.call(rate);
    if (failRate) throw StateError('rate update failed');
    currentState = currentState.copyWith(rate: rate);
  }

  @override
  Future<void> setVolume(double volume, {bool synchronized = true}) async {
    calls.add('volume:$volume');
    await volumeAction?.call(volume);
    currentState = currentState.copyWith(volume: volume);
  }

  @override
  Future<void> dispose({bool synchronized = true}) async {
    calls.add('dispose');
    disposed = true;
  }
}

class _Controller extends Fake implements VideoController {
  int disposals = 0;
  bool failDispose = false;
  @override
  Future<void> disposeForRebuild() async {
    disposals++;
    if (failDispose) throw StateError('controller release failed');
  }
}

class _Routed extends Fake implements RoutedVideoPlayback {
  _Routed(this.player);
  @override
  final Player player;
  final output = ValueNotifier<VideoController?>(null);
  final errorsController = StreamController<Object>.broadcast();
  final calls = <String>[];
  Future<void> Function(Media, {required bool play, required bool video})?
      openAction;
  int disposeAttempts = 0;
  bool failDispose = false;
  bool disposed = false;
  Future<void> Function()? disposeAction;
  @override
  ValueListenable<VideoController?> get controller => output;
  @override
  Stream<Object> get errors => errorsController.stream;
  @override
  Future<void> open(Media media, {bool play = true, bool video = true}) async {
    calls.add('open:$play:$video');
    await openAction?.call(media, play: play, video: video);
  }

  @override
  Future<void> dispose() async {
    disposeAttempts++;
    await disposeAction?.call();
    if (failDispose) throw StateError('routed release failed');
    if (disposed) return;
    disposed = true;
    await errorsController.close();
    output.dispose();
    await player.dispose();
  }
}

class _Harness {
  final players = <_Player>[];
  final routes = <_Routed>[];
  final controllers = <_Controller>[];
  Future<void> Function()? legacyFactoryAction;
  Future<void> Function()? routedFactoryAction;
  late final ManagedVideoPlayback playback = ManagedVideoPlayback.forTesting(
    slot: slot,
    createPlayer: () async {
      final player = _Player();
      players.add(player);
      return player;
    },
    createRouted: (player, _) async {
      await routedFactoryAction?.call();
      final route = _Routed(player);
      routes.add(route);
      return route;
    },
    createLegacyController: (_, __) async {
      await legacyFactoryAction?.call();
      final controller = _Controller();
      controllers.add(controller);
      return controller;
    },
    onChanged: () {
      events.add('changed:${playback.player != null}');
    },
    onFallback: (_) => events.add('fallback'),
  );
  final slot = PlayerOwnerSlot();
  final events = <String>[];
  bool current = true;
  bool Function()? currentAction;
  bool get isRequestCurrent => current && (currentAction?.call() ?? true);
  Object request = Object();
  Future<Player?> ensure([Object? forRequest]) => playback.ensure(
      request: forRequest ?? request, isCurrent: () => isRequestCurrent);
  Future<void> open({
    Object? forRequest,
    bool allowLegacyFallback = false,
    bool preservePlaybackSettings = false,
  }) =>
      playback.open(Media('test://video'),
          request: forRequest ?? request,
          isCurrent: () => isRequestCurrent,
          allowLegacyFallback: allowLegacyFallback,
          preservePlaybackSettings: preservePlaybackSettings);
}

void main() {
  test('same request reuses the complete player owner', () async {
    final h = _Harness();
    final first = await h.ensure();
    final second = await h.ensure();
    expect(identical(first, second), isTrue);
    expect(h.players, hasLength(1));
    expect(h.routes, hasLength(1));
    await h.playback.dispose();
  });

  test('fallback is explicit and a matching request reuses its legacy output',
      () async {
    final h = _Harness();
    await h.ensure();
    final failure = StateError('route failed');
    h.routes.single.openAction = (_, {required play, required video}) async {
      if (video) throw failure;
    };
    await expectLater(h.open(), throwsA(same(failure)));
    expect(h.controllers, isEmpty);
    await h.open(allowLegacyFallback: true);
    expect(h.controllers, hasLength(1));
    expect(h.playback.controller, same(h.controllers.single));
    expect(h.playback.routed, isNull);
    await h.open(allowLegacyFallback: true);
    expect(h.controllers, hasLength(1));
    expect(h.events, contains('fallback'));
    await h.playback.dispose();
    expect(h.controllers.single.disposals, 1);
  });

  test('the next request retires fallback and recreates a routed owner',
      () async {
    final h = _Harness();
    await h.ensure();
    h.routes.single.openAction = (_, {required play, required video}) async {
      if (video) throw StateError('route failed');
    };
    await h.open(allowLegacyFallback: true);
    final next = Object();
    h.routes.last.openAction = null;
    await h.open(forRequest: next);
    expect(h.players, hasLength(3));
    expect(h.routes, hasLength(2));
    expect(h.controllers.single.disposals, 1);
    expect(h.players.first.disposed, isTrue);
    await h.playback.dispose();
  });

  test('superseded old failure cannot start fallback', () async {
    final h = _Harness();
    await h.ensure();
    final entered = Completer<void>();
    final fail = Completer<void>();
    h.routes.single.openAction = (_, {required play, required video}) async {
      entered.complete();
      await fail.future;
      throw StateError('late route failure');
    };
    final opening = h.open(allowLegacyFallback: true);
    await entered.future;
    h.current = false;
    fail.complete();
    await expectLater(opening, throwsStateError);
    expect(h.controllers, isEmpty);
    await h.playback.dispose();
  });

  test('RoutedOpenSuperseded never starts legacy fallback', () async {
    final h = _Harness();
    await h.ensure();
    h.routes.single.openAction = (_, {required play, required video}) async {
      throw const RoutedOpenSuperseded();
    };
    await expectLater(h.open(allowLegacyFallback: true),
        throwsA(isA<RoutedOpenSuperseded>()));
    expect(h.players, hasLength(1));
    expect(h.controllers, isEmpty);
    await h.playback.dispose();
  });

  test('late player creation after close is cleaned without publication',
      () async {
    final slot = PlayerOwnerSlot();
    final entered = Completer<void>();
    final finish = Completer<void>();
    final player = _Player();
    var changes = 0;
    final playback = ManagedVideoPlayback.forTesting(
      slot: slot,
      createPlayer: () async {
        entered.complete();
        await finish.future;
        return player;
      },
      createRouted: (p, _) async => _Routed(p),
      createLegacyController: (_, __) async => _Controller(),
      onChanged: () => changes++,
    );
    var current = true;
    final ensure = playback.ensure(request: Object(), isCurrent: () => current);
    await entered.future;
    final closing = playback.dispose();
    current = false;
    finish.complete();
    expect(await ensure, isNull);
    await closing;
    expect(playback.player, isNull);
    expect(player.disposed, isTrue);
    expect(changes, 1);
  });

  test('cancel during routed retirement does not publish its successor',
      () async {
    final h = _Harness();
    await h.ensure();
    final entered = Completer<void>(), finish = Completer<void>();
    final old = h.routes.single;
    old.disposeAction = () async {
      entered.complete();
      await finish.future;
    };
    old.openAction = (_, {required play, required video}) async {
      throw StateError('route failed');
    };
    final successor = h.open(allowLegacyFallback: true);
    await entered.future;
    h.current = false;
    finish.complete();
    await expectLater(successor, throwsA(isA<RoutedOpenSuperseded>()));
    expect(h.routes, hasLength(1));
    expect(h.players.single.disposed, isTrue);
    await h.playback.dispose();
  });

  test('close during routed retirement prevents successor creation', () async {
    final h = _Harness();
    await h.ensure();
    final entered = Completer<void>(), finish = Completer<void>();
    h.routes.single.disposeAction = () async {
      entered.complete();
      await finish.future;
    };
    h.routes.single.openAction = (_, {required play, required video}) async {
      throw StateError('route failed');
    };
    final successor = h.open(allowLegacyFallback: true);
    await entered.future;
    final closing = h.playback.dispose();
    finish.complete();
    await expectLater(successor, throwsA(isA<RoutedOpenSuperseded>()));
    await closing;
    expect(h.players, hasLength(1));
    expect(h.routes, hasLength(1));
    expect(h.players.single.disposed, isTrue);
  });

  test('failed disposal blocks replacement and retries successful steps once',
      () async {
    final h = _Harness();
    await h.ensure();
    h.routes.single.failDispose = true;
    await expectLater(h.playback.dispose(), throwsStateError);
    expect(h.players.single.disposed, isFalse);
    h.routes.single.failDispose = false;
    await h.playback.dispose();
    expect(h.routes.single.disposeAttempts, 2);
    expect(h.players.single.calls.where((call) => call == 'dispose'),
        hasLength(1));
  });

  test('failed owner cleanup blocks another manager sharing the slot',
      () async {
    final h = _Harness();
    await h.ensure();
    h.routes.single.failDispose = true;
    await expectLater(h.playback.dispose(), throwsStateError);
    final blocked = ManagedVideoPlayback.forTesting(
      slot: h.slot,
      createPlayer: () async => _Player(),
      createRouted: (player, _) async => _Routed(player),
      createLegacyController: (_, __) async => _Controller(),
    );
    await expectLater(blocked.ensure(request: Object(), isCurrent: () => true),
        throwsStateError);
    expect(h.players, hasLength(1));
    h.routes.single.failDispose = false;
    await blocked.ensure(request: Object(), isCurrent: () => true);
    expect(h.players, hasLength(1));
    await blocked.dispose();
  });

  test('legacy cleanup retries only the unfinished wrapper/player steps',
      () async {
    final h = _Harness();
    await h.ensure();
    h.routes.single.openAction = (_, {required play, required video}) async {
      if (video) throw StateError('route failed');
    };
    await h.open(allowLegacyFallback: true);
    final legacyPlayer = h.players.last;
    final controller = h.controllers.single..failDispose = true;
    await expectLater(h.playback.dispose(), throwsStateError);
    expect(controller.disposals, 1);
    expect(legacyPlayer.calls.where((call) => call == 'dispose'), isEmpty);
    controller.failDispose = false;
    await h.playback.dispose();
    expect(controller.disposals, 2);
    expect(legacyPlayer.calls.where((call) => call == 'dispose'), hasLength(1));
  });

  test('different slots progress independently', () async {
    final first = PlayerOwnerSlot(), second = PlayerOwnerSlot();
    final entered = Completer<void>(), finish = Completer<void>();
    final a = first.transition((_) async {
      entered.complete();
      await finish.future;
    });
    await entered.future;
    var ran = false;
    await second.transition((_) async => ran = true);
    expect(ran, isTrue);
    finish.complete();
    await a;
  });

  test('open is outside the slot queue and listeners see owner before open',
      () async {
    final h = _Harness();
    await h.ensure();
    final entered = Completer<void>(), finish = Completer<void>();
    h.routes.single.openAction = (_, {required play, required video}) async {
      entered.complete();
      await finish.future;
    };
    final opening = h.open();
    await entered.future;
    expect(h.events, contains('changed:true'));
    var slotProgressed = false;
    final transition = h.slot.transition((_) async => slotProgressed = true);
    await transition;
    expect(slotProgressed, isTrue);
    finish.complete();
    await opening;
    await h.playback.dispose();
  });

  test('controller notifications rebind to the replacement routed owner',
      () async {
    final h = _Harness();
    await h.ensure();
    h.routes.single.openAction = (_, {required play, required video}) async {
      if (video) throw StateError('route failed');
    };
    await h.open(allowLegacyFallback: true);
    await h.open(forRequest: Object());
    final replacement = h.routes.last;
    final before = h.events.length;
    replacement.output.value = _Controller();
    expect(h.events.length, greaterThan(before));
    await h.playback.dispose();
  });

  test('new property intent during creation is applied to published player',
      () async {
    final entered = Completer<void>(), finish = Completer<void>();
    final slot = PlayerOwnerSlot();
    final player = _Player();
    final playback = ManagedVideoPlayback.forTesting(
      slot: slot,
      createPlayer: () async {
        entered.complete();
        await finish.future;
        return player;
      },
      createRouted: (p, _) async => _Routed(p),
      createLegacyController: (_, __) async => _Controller(),
    );
    final ensuring = playback.ensure(request: Object(), isCurrent: () => true);
    await entered.future;
    await playback.setRate(1.75);
    await playback.setVolume(42);
    finish.complete();
    await ensuring;
    expect(player.calls, containsAll(['rate:1.75', 'volume:42.0']));
    await playback.dispose();
  });

  test('property restore failure retires the unpublished owner', () async {
    final slot = PlayerOwnerSlot();
    final player = _Player()..failRate = true;
    late _Routed route;
    final playback = ManagedVideoPlayback.forTesting(
      slot: slot,
      createPlayer: () async => player,
      createRouted: (p, _) async => route = _Routed(p),
      createLegacyController: (_, __) async => _Controller(),
    );
    await playback.setRate(1.4);
    await expectLater(playback.ensure(request: Object(), isCurrent: () => true),
        throwsA(isA<StateError>()));
    expect(playback.player, isNull);
    expect(route.disposeAttempts, 1);
    expect(player.disposed, isTrue);
  });

  test('observer exceptions report errors while retaining a disposable owner',
      () async {
    final slot = PlayerOwnerSlot();
    final player = _Player();
    final errors = <Object>[];
    final playback = ManagedVideoPlayback.forTesting(
      slot: slot,
      createPlayer: () async => player,
      createRouted: (p, _) async => _Routed(p),
      createLegacyController: (_, __) async => _Controller(),
      onChanged: () => throw StateError('observer failed'),
      onError: errors.add,
    );
    expect(await playback.ensure(request: Object(), isCurrent: () => true),
        same(player));
    expect(playback.hasOutput, isTrue);
    expect(errors, hasLength(1));
    await playback.dispose();
    expect(player.disposed, isTrue);
  });

  test('refresh snapshot applies only when no newer setting intent exists',
      () async {
    final h = _Harness();
    await h.ensure();
    h.players.single.currentState = const PlayerState(rate: 1.6, volume: 61);
    h.routes.single.openAction = (_, {required play, required video}) async {
      if (video) throw StateError('route failed');
    };
    await h.open(allowLegacyFallback: true);
    await h.playback.setRate(1.9);
    await h.open(forRequest: Object(), preservePlaybackSettings: true);
    expect(h.players.last.calls, contains('rate:1.9'));
    expect(h.players.last.calls, contains('volume:61.0'));
    await h.playback.dispose();
  });

  test('ordinary new source does not copy an old player settings snapshot',
      () async {
    final h = _Harness();
    await h.ensure();
    h.players.single.currentState = const PlayerState(rate: 1.6, volume: 61);
    h.routes.single.openAction = (_, {required play, required video}) async {
      if (video) throw StateError('route failed');
    };
    await h.open(allowLegacyFallback: true);
    await h.open(forRequest: Object());
    expect(h.players.last.calls.where((call) => call.startsWith('rate:')),
        isEmpty);
    expect(h.players.last.calls.where((call) => call.startsWith('volume:')),
        isEmpty);
    await h.playback.dispose();
  });

  test('prepare and routed factory failures clean up the created player',
      () async {
    final slot = PlayerOwnerSlot();
    final player = _Player();
    final prepareFailure = ManagedVideoPlayback(
      slot: slot,
      createPlayer: () async => player,
      preparePlayer: (_) => throw StateError('prepare failed'),
    );
    await expectLater(
        prepareFailure.ensure(request: Object(), isCurrent: () => true),
        throwsStateError);
    expect(player.disposed, isTrue);

    final nextPlayer = _Player();
    final factoryFailure = ManagedVideoPlayback.forTesting(
      slot: PlayerOwnerSlot(),
      createPlayer: () async => nextPlayer,
      createRouted: (_, __) async => throw StateError('output factory failed'),
      createLegacyController: (_, __) async => _Controller(),
    );
    await expectLater(
        factoryFailure.ensure(request: Object(), isCurrent: () => true),
        throwsStateError);
    expect(nextPlayer.disposed, isTrue);
  });

  test('rate intent arriving during volume restore reaches published owner',
      () async {
    final entered = Completer<void>(), finish = Completer<void>();
    final player = _Player();
    player.volumeAction = (_) async {
      entered.complete();
      await finish.future;
    };
    final playback = ManagedVideoPlayback.forTesting(
      slot: PlayerOwnerSlot(),
      createPlayer: () async => player,
      createRouted: (p, _) async => _Routed(p),
      createLegacyController: (_, __) async => _Controller(),
    );
    await playback.setRate(1.25);
    await playback.setVolume(45);
    final ensuring = playback.ensure(request: Object(), isCurrent: () => true);
    await entered.future;
    await playback.setRate(1.75);
    finish.complete();
    await ensuring;
    expect(player.state.rate, 1.75);
    expect(player.state.volume, 45);
    await playback.dispose();
  });

  test('legacy factory await preserves newer property intents over snapshot',
      () async {
    final h = _Harness();
    await h.ensure();
    h.players.single.currentState = const PlayerState(rate: 1.6, volume: 61);
    h.routes.single.openAction = (_, {required play, required video}) async {
      throw StateError('route failed');
    };
    final entered = Completer<void>(), finish = Completer<void>();
    h.legacyFactoryAction = () async {
      entered.complete();
      await finish.future;
    };
    final opening =
        h.open(allowLegacyFallback: true, preservePlaybackSettings: true);
    await entered.future;
    await h.playback.setRate(1.9);
    await h.playback.setVolume(72);
    finish.complete();
    await opening;
    expect(h.players.last.state.rate, 1.9);
    expect(h.players.last.state.volume, 72);
    expect(h.players.first.disposed, isTrue);
    await h.playback.dispose();
  });

  test('refresh routed failure restores its settings on the legacy owner',
      () async {
    final h = _Harness();
    await h.ensure();
    h.players.single.currentState = const PlayerState(rate: 1.6, volume: 61);
    h.routes.single.openAction = (_, {required play, required video}) async {
      throw StateError('route failed');
    };
    await h.open(allowLegacyFallback: true, preservePlaybackSettings: true);
    expect(h.players.last.state.rate, 1.6);
    expect(h.players.last.state.volume, 61);
    expect(h.players.last.calls.last, 'open:true');
    await h.playback.dispose();
  });

  for (final close in [false, true]) {
    test(
        'snapshot stops after in-flight rate when ${close ? 'closed' : 'cancelled'}',
        () async {
      final h = _Harness();
      await h.ensure();
      h.players.single.currentState = const PlayerState(rate: 1.6, volume: 61);
      h.routes.single.openAction = (_, {required play, required video}) async {
        throw StateError('route failed');
      };
      await h.open(allowLegacyFallback: true);
      final entered = Completer<void>(), finish = Completer<void>();
      // The first routed creation already completed; the successor receives
      // this hook before its settings snapshot is applied outside the slot.
      h.routedFactoryAction = () async {
        h.players.last.rateAction = (_) async {
          entered.complete();
          await finish.future;
        };
      };
      final opening =
          h.open(forRequest: Object(), preservePlaybackSettings: true);
      await entered.future;
      final successor = h.players.last;
      final closing = close ? h.playback.dispose() : null;
      if (!close) h.current = false;
      finish.complete();
      await opening;
      await closing;
      expect(successor.calls.where((c) => c.startsWith('volume:')), isEmpty);
      expect(successor.calls.where((c) => c.startsWith('open:')), isEmpty);
      await h.playback.dispose();
    });
  }

  test('close during legacy factory retires both unpublished resources',
      () async {
    final h = _Harness();
    await h.ensure();
    h.routes.single.openAction = (_, {required play, required video}) async {
      throw StateError('route failed');
    };
    final entered = Completer<void>(), finish = Completer<void>();
    h.legacyFactoryAction = () async {
      entered.complete();
      await finish.future;
    };
    final opening = h.open(allowLegacyFallback: true);
    await entered.future;
    final closing = h.playback.dispose();
    finish.complete();
    await expectLater(opening, throwsA(isA<RoutedOpenSuperseded>()));
    await closing;
    expect(h.playback.player, isNull);
    expect(h.controllers.single.disposals, 1);
    expect(h.players.every((p) => p.disposed), isTrue);
  });

  test('close retains its detached owner when another cleanup blocks admission',
      () async {
    final a = _Harness();
    await a.ensure();
    final player = _Player();
    final route = _Routed(player);
    final b = ManagedVideoPlayback.forTesting(
      slot: a.slot,
      createPlayer: () async => player,
      createRouted: (_, __) async => route,
      createLegacyController: (_, __) async => _Controller(),
    );
    await b.ensure(request: Object(), isCurrent: () => true);
    a.routes.single.failDispose = true;
    await expectLater(a.playback.dispose(), throwsStateError);
    await expectLater(b.dispose(), throwsStateError);
    expect(b.player, isNull);
    expect(player.disposed, isFalse);
    a.routes.single.failDispose = false;
    await b.dispose();
    expect(player.disposed, isTrue);
    expect(route.disposeAttempts, 1);
  });

  test('fallback observer exceptions report errors without failing open',
      () async {
    final errors = <Object>[];
    late _Routed route;
    final playback = ManagedVideoPlayback.forTesting(
      slot: PlayerOwnerSlot(),
      createPlayer: () async => _Player(),
      createRouted: (p, _) async => route = _Routed(p),
      createLegacyController: (_, __) async => _Controller(),
      onError: errors.add,
      onFallback: (_) => throw StateError('observer failed'),
    );
    final request = Object();
    await playback.ensure(request: request, isCurrent: () => true);
    route.openAction = (_, {required play, required video}) async {
      throw StateError('route failed');
    };
    await playback.open(Media('test://video'),
        request: request, isCurrent: () => true, allowLegacyFallback: true);
    expect(errors, hasLength(1));
    expect(playback.controller, isA<_Controller>());
    await playback.dispose();
  });

  test('intent at every publication microtask boundary reaches the player',
      () async {
    for (var offset = 0; offset < 12; offset++) {
      final player = _Player();
      late ManagedVideoPlayback playback;
      Future<void>? setting;
      void updateAfter(int remaining) {
        scheduleMicrotask(() {
          if (remaining == 0) {
            setting = playback.setRate(1.75);
          } else {
            updateAfter(remaining - 1);
          }
        });
      }

      player.volumeAction = (_) async => updateAfter(offset);
      playback = ManagedVideoPlayback.forTesting(
        slot: PlayerOwnerSlot(),
        createPlayer: () async => player,
        createRouted: (p, _) async => _Routed(p),
        createLegacyController: (_, __) async => _Controller(),
      );
      await playback.setRate(1.25);
      await playback.setVolume(45);
      await playback.ensure(request: Object(), isCurrent: () => true);
      await Future<void>.delayed(Duration.zero);
      await setting;
      expect(player.state.rate, 1.75, reason: 'microtask offset $offset');
      await playback.dispose();
    }
  });

  test('fallback intents survive every legacy publication microtask boundary',
      () async {
    for (var offset = -1; offset < 12; offset++) {
      final h = _Harness();
      await h.ensure();
      h.players.single.currentState = const PlayerState(rate: 1.25, volume: 45);
      h.routes.single.openAction = (_, {required play, required video}) async {
        throw StateError('route failed');
      };
      var scheduled = false;
      Future<void>? setting;
      void updateAfter(int remaining) {
        if (remaining < 0) {
          setting = Future.wait([
            h.playback.setRate(1.75),
            h.playback.setVolume(63),
          ]).then((_) {});
        } else {
          scheduleMicrotask(() => updateAfter(remaining - 1));
        }
      }

      var restoreChecks = 0;
      h.currentAction = () {
        if (h.players.length == 2 &&
            h.players.last.state.volume == 45 &&
            h.playback.player == null) {
          restoreChecks++;
          // The second check occurs after the helper's final check returns.
          if (!scheduled && restoreChecks == 2) {
            scheduled = true;
            updateAfter(offset);
          }
        }
        return true;
      };
      await h.open(allowLegacyFallback: true);
      await Future<void>.delayed(Duration.zero);
      await setting;
      expect(h.players.last.state.rate, 1.75,
          reason: 'legacy microtask offset $offset');
      expect(h.players.last.state.volume, 63,
          reason: 'legacy microtask offset $offset');
      await h.playback.dispose();
    }
  });

  for (final close in [false, true]) {
    test('snapshot return microtask cancellation blocks open (close=$close)',
        () async {
      for (var offset = -1; offset < 12; offset++) {
        final h = _Harness();
        await h.ensure();
        h.players.single.currentState =
            const PlayerState(rate: 1.6, volume: 61);
        h.routes.single.openAction =
            (_, {required play, required video}) async {
          throw StateError('route failed');
        };
        await h.open(allowLegacyFallback: true);
        var cancelledBeforeOpen = false;
        Future<void>? closing;
        void cancelAfter(int remaining) {
          if (remaining < 0) {
            cancelledBeforeOpen = h.routes.last.calls.isEmpty;
            if (close) {
              closing = h.playback.dispose();
            } else {
              h.current = false;
            }
          } else {
            scheduleMicrotask(() => cancelAfter(remaining - 1));
          }
        }

        var scheduled = false;
        h.currentAction = () {
          if (!scheduled &&
              h.routes.length == 2 &&
              h.players.last.state.volume == 61) {
            scheduled = true;
            cancelAfter(offset);
          }
          return true;
        };
        await h.open(forRequest: Object(), preservePlaybackSettings: true);
        await Future<void>.delayed(Duration.zero);
        await closing;
        if (cancelledBeforeOpen) {
          expect(h.routes.last.calls, isEmpty,
              reason: 'snapshot return microtask offset $offset');
        }
        await h.playback.dispose();
      }
    });
  }

  test('successor drains discarded closed manager debt before creating',
      () async {
    final a = _Harness();
    await a.ensure();
    final playerB = _Player();
    final routeB = _Routed(playerB);
    final b = ManagedVideoPlayback.forTesting(
      slot: a.slot,
      createPlayer: () async => playerB,
      createRouted: (_, __) async => routeB,
      createLegacyController: (_, __) async => _Controller(),
    );
    await b.ensure(request: Object(), isCurrent: () => true);
    a.routes.single.failDispose = true;
    routeB.failDispose = true;
    await expectLater(a.playback.dispose(), throwsStateError);
    await expectLater(b.dispose(), throwsStateError);
    expect(b.player, isNull);
    var creations = 0;
    final c = ManagedVideoPlayback.forTesting(
      slot: a.slot,
      createPlayer: () async {
        creations++;
        return _Player();
      },
      createRouted: (p, _) async => _Routed(p),
      createLegacyController: (_, __) async => _Controller(),
    );
    a.routes.single.failDispose = false;
    await expectLater(
        c.ensure(request: Object(), isCurrent: () => true), throwsStateError);
    expect(creations, 0);
    expect(routeB.disposeAttempts, 1);
    routeB.failDispose = false;
    await c.ensure(request: Object(), isCurrent: () => true);
    expect(playerB.disposed, isTrue);
    expect(creations, 1);
    expect(routeB.disposeAttempts, 2);
    await c.dispose();
  });
}
