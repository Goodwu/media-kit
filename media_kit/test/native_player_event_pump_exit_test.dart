import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'package:path/path.dart' as path;

import 'package:media_kit/generated/libmpv/bindings.dart' as generated;
import 'package:media_kit/src/native_wakeup_callback.dart';
import 'package:media_kit/src/player/native/core/native_library.dart';
import 'package:media_kit/src/player/native/player/real.dart';
import 'package:media_kit/src/player/platform_player.dart';
import 'package:test/test.dart';

/// CPU-only bridge fixture. It installs the exact NativeCallable address into
/// mpv, while retaining a controllable removal failure for retry coverage.
class _MpvOwner implements NativeWakeupCallbackOwner {
  _MpvOwner(this.mpv);

  final generated.MPV mpv;
  int failedRemovals = 0;

  @override
  bool install(int handle, int callback, int userdata) {
    mpv.mpv_set_wakeup_callback(
      Pointer<generated.mpv_handle>.fromAddress(handle),
      Pointer<NativeFunction<Void Function(Pointer<Void>)>>.fromAddress(
        callback,
      ),
      Pointer<Void>.fromAddress(userdata),
    );
    return true;
  }

  @override
  void remove(int handle) {
    if (failedRemovals > 0) {
      failedRemovals--;
      throw StateError('controlled callback owner removal failure');
    }
    mpv.mpv_set_wakeup_callback(
      Pointer<generated.mpv_handle>.fromAddress(handle),
      nullptr,
      nullptr,
    );
  }
}

void main() {
  final libraryPath = Platform.environment['LIBMPV_LIBRARY_PATH'];
  if (libraryPath == null || libraryPath.isEmpty) {
    test('event pump exit integration requires LIBMPV_LIBRARY_PATH', () {},
        skip: 'Set LIBMPV_LIBRARY_PATH to the CPU-test libmpv candidate.');
    return;
  }

  late generated.MPV mpv;
  late _MpvOwner owner;

  setUpAll(() {
    final bundlePath = Platform.environment['MEDIA_KIT_TEST_FRAMEWORKS'];
    if (bundlePath != null) {
      final bundle = Directory(bundlePath);
      final pending = <String>[];
      for (final entity in bundle.listSync(followLinks: true)) {
        if (entity is Directory && entity.path.endsWith('.framework')) {
          final executable = File(
            path.join(entity.path, 'Versions', 'A',
                path.basenameWithoutExtension(entity.path)),
          );
          if (executable.existsSync()) pending.add(executable.path);
        } else if (entity is File && entity.path.endsWith('.dylib')) {
          pending.add(entity.path);
        }
      }
      while (pending.isNotEmpty) {
        var loaded = false;
        for (final candidate in pending.toList()) {
          try {
            DynamicLibrary.open(candidate);
            pending.remove(candidate);
            loaded = true;
          } catch (_) {}
        }
        if (!loaded) break;
      }
    }
    nativeEnsureInitialized(libmpv: libraryPath);
    mpv = generated.MPV(DynamicLibrary.open(NativeLibrary.path));
    owner = _MpvOwner(mpv);
    NativeWakeupCallbackOwnership.initialize(owner);
  });

  Future<NativePlayer> createPlayer() async {
    final player = await NativePlayer.create(
      configuration: const PlayerConfiguration(
        async: true,
        options: {'vo': 'null', 'ao': 'null'},
      ),
    ).timeout(const Duration(seconds: 20));
    return player;
  }

  test('async stop reply completes before successful native termination',
      () async {
    final player = await createPlayer();
    await player.dispose().timeout(const Duration(seconds: 20));
    expect(player.isTerminated, isTrue);
  });

  test('blocked observer outlives five seconds without native destruction',
      () async {
    final player = await createPlayer();
    final entered = Completer<void>();
    final attemptReentry = Completer<void>();
    final reentryRejected = Completer<void>();
    final release = Completer<void>();
    await player.observeProperty('volume', (_) async {
      if (!entered.isCompleted) entered.complete();
      if (!attemptReentry.isCompleted) {
        await attemptReentry.future;
        try {
          await player.dispose();
          fail('callback reentrant dispose unexpectedly succeeded');
        } on ReentrantEventPumpDisposeError {
          expect(player.isTerminated, isFalse);
          if (!reentryRejected.isCompleted) reentryRejected.complete();
        }
      }
      await release.future;
    });
    await entered.future.timeout(const Duration(seconds: 10));

    final dispose = player.dispose();
    var disposeCompleted = false;
    dispose.then((_) {
      disposeCompleted = true;
    }, onError: (Object _) {
      disposeCompleted = true;
    });
    attemptReentry.complete();
    await reentryRejected.future.timeout(const Duration(seconds: 5));
    await Future<void>.delayed(const Duration(milliseconds: 5200));
    expect(player.isTerminated, isFalse);
    expect(disposeCompleted, isFalse);

    release.complete();
    await dispose.timeout(const Duration(seconds: 20));
    expect(player.isTerminated, isTrue);
  });

  test('observer reentrant dispose has no close side effects and can retry',
      () async {
    final player = await createPlayer();
    final attempted = Completer<void>();
    await player.observeProperty('volume', (_) async {
      try {
        await player.dispose();
        fail('reentrant dispose unexpectedly succeeded');
      } on ReentrantEventPumpDisposeError {
        expect(player.isDisposing, isFalse);
        expect(player.isTerminated, isFalse);
      }
      if (!attempted.isCompleted) attempted.complete();
    });
    await attempted.future.timeout(const Duration(seconds: 10));
    await player.dispose().timeout(const Duration(seconds: 20));
    expect(player.isTerminated, isTrue);
  });

  test('callback removal failure keeps player retryable', () async {
    final player = await createPlayer();
    owner.failedRemovals = 1;
    await expectLater(player.dispose(), throwsStateError);
    expect(player.isTerminated, isFalse);
    await player.dispose().timeout(const Duration(seconds: 20));
    expect(player.isTerminated, isTrue);
  });

  test('concurrent dispose shares one native termination', () async {
    final player = await createPlayer();
    final first = player.dispose();
    final second = player.dispose();
    expect(identical(first, second), isTrue);
    await Future.wait([first, second]).timeout(const Duration(seconds: 20));
    expect(player.isTerminated, isTrue);
  });

  test('throwing observer releases its callback ticket for external retry',
      () async {
    final player = await createPlayer();
    final entered = Completer<void>();
    await player.observeProperty('volume', (_) async {
      if (!entered.isCompleted) entered.complete();
      throw StateError('controlled observer exception');
    });
    await entered.future.timeout(const Duration(seconds: 10));
    await Future<void>.delayed(Duration.zero);
    await player.dispose().timeout(const Duration(seconds: 20));
    expect(player.isTerminated, isTrue);
  });

  test('Zone-captured retry is allowed after its callback ticket ends',
      () async {
    final player = await createPlayer();
    final entered = Completer<void>();
    late Future<void> retry;
    await player.observeProperty('volume', (_) async {
      retry = Future<void>.delayed(
        const Duration(milliseconds: 20),
        player.dispose,
      );
      if (!entered.isCompleted) entered.complete();
    });
    await entered.future.timeout(const Duration(seconds: 10));
    await retry.timeout(const Duration(seconds: 20));
    expect(player.isTerminated, isTrue);
  });
}
