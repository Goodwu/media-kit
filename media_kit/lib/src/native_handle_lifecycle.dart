/// This file is a part of media_kit (https://github.com/media-kit/media-kit).
///
/// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
/// All rights reserved.
/// Use of this source code is governed by MIT license that can be found in the LICENSE file.
import 'package:meta/meta.dart';

/// {@template native_handle_lifecycle}
///
/// NativeHandleLifecycle
/// ---------------------
/// Narrow observation hook for native mpv handle lifetimes.
///
/// Platform packages may set [observer] to mirror every live native handle
/// into engine-scoped native registries. media_kit itself never touches a
/// method channel: the platform package decides what registration means on
/// its side. On Android, media_kit_video registers each handle with the
/// native owner broker so an engine destroyed without Dart-side disposal
/// still clears its wakeup callbacks while the NativeCallable trampoline
/// backing them is mapped.
///
/// {@endtemplate}
abstract final class NativeHandleLifecycle {
  /// Invoked with the address of a native handle when it is created
  /// (`unregister: false`) and when it is disposed (`unregister: true`).
  ///
  /// Set this before the first [Player] is created. Exceptions thrown by the
  /// hook are ignored: observation must never break handle creation.
  static void Function(int ctxAddress, {required bool unregister})? observer;

  /// Addresses of handles whose wakeup callback is currently live.
  ///
  /// An observer installed after players already exist uses this to
  /// back-fill its registration.
  static List<int> get liveHandleAddresses =>
      _liveHandleAddresses.toList(growable: false);

  static final Set<int> _liveHandleAddresses = <int>{};

  /// Called by media_kit internals when a native handle is created.
  @internal
  static void handleCreated(int ctxAddress) {
    _liveHandleAddresses.add(ctxAddress);
    _notify(ctxAddress, unregister: false);
  }

  /// Called by media_kit internals when a native handle is disposed.
  @internal
  static void handleDisposed(int ctxAddress) {
    _liveHandleAddresses.remove(ctxAddress);
    _notify(ctxAddress, unregister: true);
  }

  static void _notify(int ctxAddress, {required bool unregister}) {
    try {
      observer?.call(ctxAddress, unregister: unregister);
    } catch (_) {}
  }
}
