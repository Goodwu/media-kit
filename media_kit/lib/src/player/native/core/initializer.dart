export 'legacy_mpv.dart' show Initializer;
/// This file is a part of media_kit (https://github.com/media-kit/media-kit).
///
/// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
/// All rights reserved.
/// Use of this source code is governed by MIT license that can be found in the LICENSE file.
import 'dart:ffi';
import 'dart:isolate';

import 'package:media_kit/generated/libmpv/bindings.dart' as generated;
import 'package:media_kit/src/player/native/core/execmem_restriction.dart';
import 'package:media_kit/src/player/native/core/initializer_isolate.dart';
import 'package:media_kit/src/player/native/core/initializer_native_callable.dart';

/// {@template initializer}
///
/// Initializer
/// -----------
/// Initializes [Pointer<mpv_handle>] & notifies about events through the supplied callback.
///
/// {@endtemplate}
class PlayerInitializer {
  /// Singleton instance.
  static PlayerInitializer? _instance;

  /// {@macro initializer}
  PlayerInitializer._(this.mpvBindings);

  /// {@macro initializer}
  factory PlayerInitializer(generated.MPV mpvBindings) {
    _instance ??= PlayerInitializer._(mpvBindings);
    return _instance!;
  }

  /// Generated libmpv C API bindings.
  final generated.MPV mpvBindings;

  /// Creates [Pointer<mpv_handle>].
  Future<Pointer<generated.mpv_handle>> create(
    Future<void> Function(Pointer<generated.mpv_event>) callback, {
    Map<String, String> options = const {},
  }) async {
    // Hot-restart tears down the Dart isolate, which invalidates any previously
    // registered `NativeCallable` trampolines. In debug mode, prefer the isolate
    // based implementation to avoid native -> Dart callbacks that can outlive
    // the isolate and crash with "Callback invoked after it has been deleted".
    // See: https://github.com/media-kit/media-kit/issues/1340
    //
    // The root isolate also runs on the platform thread whenever the engine
    // merges threads (platform view topologies). The NativeCallable pump
    // drains `mpv_wait_event()` on that thread, and concurrent libmpv access
    // from property/command helper isolates then contends with the core lock
    // held across the pump's event handlers — deadlocking into an ANR. The
    // isolate pump keeps `mpv_wait_event()` on its own thread, so every
    // main-isolate player uses it regardless of build mode.
    if (isMainIsolate()) {
      return InitializerIsolate().create(callback, options: options);
    }
    if (!isExecmemRestricted) {
      return InitializerNativeCallable(mpvBindings).create(callback, options: options);
    } else {
      return InitializerIsolate().create(callback, options: options);
    }
  }

  /// Owned NativeCallable callbacks need a retryable pre-terminal barrier.
  /// Other initializers preserve their existing terminal dispose ordering.
  Future<bool> disposeOwnedWakeupCallback(
    Pointer<generated.mpv_handle> ctx,
  ) =>
      InitializerNativeCallable(mpvBindings).disposeOwned(ctx);

  /// Disposes [Pointer<mpv_handle>].
  Future<void> dispose(Pointer<generated.mpv_handle> ctx) async {
    // Must mirror [create]: the backend that owns the handle also owns its
    // teardown, otherwise the isolate pump keeps draining a freed handle
    // while the NativeCallable path disposes nothing.
    if (isMainIsolate()) {
      InitializerIsolate().dispose(mpvBindings, ctx);
      return;
    }
    if (!isExecmemRestricted) {
      await InitializerNativeCallable(mpvBindings).dispose(ctx);
    } else {
      // Isolate shutdown remains its existing asynchronous request protocol;
      // this path is not a close-and-drain completion barrier.
      InitializerIsolate().dispose(mpvBindings, ctx);
    }
  }

  bool isMainIsolate() {
    final name = Isolate.current.debugName;
    return name == 'main';
  }
}
