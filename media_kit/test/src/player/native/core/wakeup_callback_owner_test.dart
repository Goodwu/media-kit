import 'dart:ffi';
import 'dart:io';
import 'package:media_kit/generated/libmpv/bindings.dart' as generated;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit/src/player/native/core/initializer_native_callable.dart';
import 'package:test/test.dart';

class _Owner implements NativeWakeupCallbackOwner {
  _Owner(this.mpv);
  final generated.MPV mpv;
  bool reject = false, throwInstall = false, failRemove = false;
  final Set<int> live = {};
  final List<String> calls = [];
  @override
  bool install(int handle, int callback, int userdata) {
    calls.add('install');
    if (reject) return false;
    live.add(handle);
    mpv.mpv_set_wakeup_callback(Pointer.fromAddress(handle),
        Pointer.fromAddress(callback), Pointer.fromAddress(userdata));
    if (throwInstall) throw StateError('failure after native publication');
    return true;
  }

  @override
  void remove(int handle) {
    calls.add('remove');
    if (failRemove) throw StateError('removal failure');
    if (live.remove(handle)) {
      mpv.mpv_set_wakeup_callback(
          Pointer.fromAddress(handle), nullptr, nullptr);
      calls.add('cleared');
    }
  }
}

void _preloadFrameworkDependencies() {
  final bundlePath = Platform.environment['MEDIA_KIT_TEST_FRAMEWORKS'];
  if (bundlePath == null) return;
  final pending = <String>[];
  for (final entity in Directory(bundlePath).listSync(followLinks: true)) {
    if (entity is Directory && entity.path.endsWith('.framework')) {
      final executable = File(
        '${entity.path}/Versions/A/${entity.path.split('/').last.replaceAll('.framework', '')}',
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

void main() {
  final path = Platform.environment['MEDIA_KIT_TEST_MPV'];
  if (path == null) {
    throw StateError('Set MEDIA_KIT_TEST_MPV to exact candidate mpv');
  }
  _preloadFrameworkDependencies();
  final mpv = generated.MPV(DynamicLibrary.open(path));
  final initializer = InitializerNativeCallable(mpv);
  final owner = _Owner(mpv);
  NativeWakeupCallbackOwnership.initialize(owner);
  tearDown(() async {
    owner.reject = owner.throwInstall = owner.failRemove = false;
    for (final address in owner.live.toList()) {
      final handle = Pointer<generated.mpv_handle>.fromAddress(address);
      await initializer.dispose(handle);
      mpv.mpv_terminate_destroy(handle);
    }
    owner.calls.clear();
  });
  test(
      'real NativePlayer dispose retries failed owner barrier before terminal cleanup',
      () async {
    MediaKit.ensureInitialized(libmpv: path);
    final player = await NativePlayer.create();
    final address = await player.handle;
    player.preTermination.add(() async {
      owner.calls.add('render-freed');
    });
    owner.failRemove = true;
    await expectLater(player.dispose(), throwsStateError);
    expect(owner.live, contains(address));
    expect(owner.calls.sublist(owner.calls.indexOf('render-freed')),
        ['render-freed', 'remove']);
    expect(player.isDisposing, isFalse);
    // No terminal destruction occurred despite the caller having attempted
    // dispose. The still-mapped callable safely receives a real mpv wakeup.
    mpv.mpv_wakeup(Pointer.fromAddress(address));
    await Future<void>.delayed(Duration.zero);
    owner.failRemove = false;
    await player.dispose();
    expect(owner.live, isEmpty);
    expect(owner.calls.where((event) => event == 'render-freed'), hasLength(1));
    expect(owner.calls.last, 'cleared');
  });
  test('owner cannot be replaced', () {
    expect(() => NativeWakeupCallbackOwnership.initialize(_Owner(mpv)),
        throwsStateError);
  });
  test(
      'actual create and dispose clear callback before destroy; duplicate safe',
      () async {
    final handle =
        await initializer.create((_) async {}, options: {'terminal': 'no'});
    expect(owner.live, contains(handle.address));
    await initializer.dispose(handle);
    expect(owner.calls, ['install', 'remove', 'cleared']);
    mpv.mpv_wakeup(handle);
    await initializer.dispose(handle);
    expect(owner.calls, ['install', 'remove', 'cleared']);
    mpv.mpv_terminate_destroy(handle);
  });
  test('closed owner rejects without publishing native handle', () async {
    owner.reject = true;
    await expectLater(initializer.create((_) async {}), throwsStateError);
    expect(owner.live, isEmpty);
    expect(owner.calls, ['install']);
  });
  test('exception after install clears synchronously before closing callable',
      () async {
    owner.throwInstall = true;
    await expectLater(initializer.create((_) async {}), throwsStateError);
    expect(owner.live, isEmpty);
    expect(owner.calls, ['install', 'remove', 'cleared']);
  });
  test('failed remove retains live callable until retry', () async {
    final handle = await initializer.create((_) async {});
    owner.failRemove = true;
    await expectLater(initializer.dispose(handle), throwsStateError);
    expect(owner.live, contains(handle.address));
    mpv.mpv_wakeup(handle);
    await Future<void>.delayed(Duration.zero);
    owner.failRemove = false;
    await initializer.dispose(handle);
    expect(owner.live, isEmpty);
    mpv.mpv_terminate_destroy(handle);
  });
  test('failed exceptional-install rollback retains native resources for retry',
      () async {
    owner.throwInstall = owner.failRemove = true;
    await expectLater(initializer.create((_) async {}), throwsStateError);
    expect(owner.live, hasLength(1));
    final handle = Pointer<generated.mpv_handle>.fromAddress(owner.live.single);
    mpv.mpv_wakeup(handle);
    await Future<void>.delayed(Duration.zero);
    owner.failRemove = false;
    await initializer.dispose(handle);
    expect(owner.live, isEmpty);
    mpv.mpv_terminate_destroy(handle);
  });
}
