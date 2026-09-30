/// This file is a part of media_kit (https://github.com/media-kit/media-kit).
///
/// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
/// All rights reserved.
/// Use of this source code is governed by MIT license that can be found in LICENSE file.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart' show NativeHandleLifecycle;

/// Wires media_kit's [NativeHandleLifecycle] observer to the Android plugin's
/// `media_kit/native_broker` channel. The plugin registers every mpv handle
/// under the engine that owns it and, at that engine's detach, clears the
/// wakeup callback of its own handles only, while the NativeCallable
/// trampoline backing it is still mapped. Handles belonging to other
/// engines in the same process are left running.
///
/// Call once before the first [Player] is created on Android; idempotent.
void wireMpvOwnerBroker() {
  if (!Platform.isAndroid) {
    return;
  }
  NativeHandleLifecycle.observer ??= (
    int ctxAddress, {
    required bool unregister,
  }) {
    _invokeBroker(unregister ? 'Unregister' : 'Register', ctxAddress);
  };
  // Players created before this wiring still hold a live wakeup callback;
  // register them now.
  for (final address in NativeHandleLifecycle.liveHandleAddresses) {
    _invokeBroker('Register', address);
  }
}

void _invokeBroker(String method, int ctxAddress) {
  const MethodChannel('media_kit/native_broker')
      .invokeMethod<void>(method, '$ctxAddress')
      .then(
        (_) {},
        // Registration failures must stay visible: a handle the broker never
        // learned about would keep a dangling wakeup callback after engine
        // detach.
        onError: (Object e) => debugPrint(
          'media_kit: owner broker $method(0x${ctxAddress.toRadixString(16)}) failed: $e',
        ),
      );
}
