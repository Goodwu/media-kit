/// This file is a part of media_kit (https://github.com/media-kit/media-kit).
///
/// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
/// All rights reserved.
/// Use of this source code is governed by MIT license that can be found in the LICENSE file.
import 'dart:collection';
import 'dart:ffi';

import 'package:media_kit/ffi/ffi.dart';
import 'package:media_kit/generated/libmpv/bindings.dart' as generated;
import 'package:synchronized/synchronized.dart';

/// {@template initializer_native_callable}
///
/// InitializerNativeCallable
/// -------------------------
/// Initializes [Pointer<mpv_handle>] & notifies about events through the supplied callback.
///
/// {@endtemplate}
class InitializerNativeCallable {
  /// Singleton instance.
  static InitializerNativeCallable? _instance;

  /// {@macro initializer}
  InitializerNativeCallable._(this.mpv);

  /// {@macro initializer}
  factory InitializerNativeCallable(generated.MPV mpv) {
    _instance ??= InitializerNativeCallable._(mpv);
    return _instance!;
  }

  /// Generated libmpv C API bindings.
  final generated.MPV mpv;

  /// Creates [Pointer<mpv_handle>].
  Future<Pointer<generated.mpv_handle>> create(
    Future<void> Function(Pointer<generated.mpv_event>) callback, {
    Map<String, String> options = const {},
  }) async {
    final ctx = mpv.mpv_create();
    for (final entry in options.entries) {
      final name = entry.key.toNativeUtf8();
      final value = entry.value.toNativeUtf8();
      mpv.mpv_set_option_string(ctx, name.cast(), value.cast());
      calloc.free(name);
      calloc.free(value);
    }
    mpv.mpv_initialize(ctx);
    final nativeCallable = WakeUpNativeCallable.listener(_callback);
    final nativeFunction = nativeCallable.nativeFunction;
    _locks[ctx.address] = Lock();
    _eventCallbacks[ctx.address] = callback;
    _wakeUpNativeCallables[ctx.address] = nativeCallable;
    mpv.mpv_set_wakeup_callback(ctx, nativeFunction.cast(), ctx.cast());
    _liveHandleAddresses.add(ctx.address);
    try {
      ownerBrokerRegistration?.call(ctx.address, unregister: false);
    } catch (_) {}
    return ctx;
  }

  /// Wired by media_kit_video on Android so this Flutter-free package never
  /// touches a method channel. The registration lets the Android-side owner
  /// broker clear the wakeup callback at engine detach, while the
  /// NativeCallable trampoline backing it is still mapped. Without that, a
  /// host destroying the FlutterEngine without Dart disposal leaves the next
  /// mpv wakeup calling trampoline memory that died with the isolate.
  static void Function(int ctxAddress, {required bool unregister})?
      ownerBrokerRegistration;

  /// Addresses of handles whose wakeup callback is currently registered.
  /// Owner-broker wiring uses this to back-fill players that were created
  /// before the hook was installed.
  static final Set<int> _liveHandleAddresses = <int>{};

  static List<int> get liveHandleAddresses =>
      _liveHandleAddresses.toList(growable: false);

  /// Disposes [Pointer<mpv_handle>].
  void dispose(Pointer<generated.mpv_handle> ctx) {
    _locks.remove(ctx.address);
    _eventCallbacks.remove(ctx.address);

    // Clear the wakeup callback in libmpv before closing NativeCallable
    // to prevent libmpv from invoking a deleted callback
    mpv.mpv_set_wakeup_callback(ctx, nullptr, nullptr);

    _registerUnregister(ctx);
    _liveHandleAddresses.remove(ctx.address);
    _wakeUpNativeCallables.remove(ctx.address)?.close();
  }

  void _registerUnregister(Pointer<generated.mpv_handle> ctx) {
    try {
      ownerBrokerRegistration?.call(ctx.address, unregister: true);
    } catch (_) {}
  }

  void _callback(Pointer<generated.mpv_handle> ctx) {
    _locks[ctx.address]?.synchronized(() async {
      while (true) {
        final event = mpv.mpv_wait_event(ctx, 0);
        if (event == nullptr) return;
        if (event.ref.event_id == generated.mpv_event_id.MPV_EVENT_NONE) return;
        await _eventCallbacks[ctx.address]?.call(event);
      }
    });
  }

  final _locks = HashMap<int, Lock>();
  final _eventCallbacks = EventCallbackMap();
  final _wakeUpNativeCallables = WakeUpNativeCallableMap();
}

typedef WakeUpCallback = Void Function(Pointer<generated.mpv_handle>);
typedef WakeUpNativeCallable = NativeCallable<WakeUpCallback>;
typedef WakeUpNativeCallableMap = HashMap<int, WakeUpNativeCallable>;

typedef EventCallback = Future<void> Function(Pointer<generated.mpv_event>);
typedef EventCallbackMap = HashMap<int, EventCallback>;
