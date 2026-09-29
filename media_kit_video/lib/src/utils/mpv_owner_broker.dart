/// This file is a part of media_kit (https://github.com/media-kit/media-kit).
///
/// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
/// All rights reserved.
/// Use of this source code is governed by MIT license that can be found in LICENSE file.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:media_kit/src/player/native/core/initializer_native_callable.dart';

/// Wires media_kit's owner-broker registration hook to the Android plugin's
/// `media_kit/native_broker` channel. The plugin registers every mpv handle
/// and, at engine detach, clears each wakeup callback while the
/// NativeCallable trampoline backing it is still mapped.
///
/// Call once before the first [Player] is created on Android; idempotent.
void wireMpvOwnerBroker() {
  if (!Platform.isAndroid) {
    return;
  }
  InitializerNativeCallable.ownerBrokerRegistration ??= (
    int ctxAddress, {
    required bool unregister,
  }) {
    const MethodChannel('media_kit/native_broker')
        .invokeMethod<void>(
          unregister ? 'Unregister' : 'Register',
          '$ctxAddress',
        )
        .catchError((Object _) {});
  };
  // Players created before this wiring still hold a live wakeup callback;
  // register them now.
  for (final address in InitializerNativeCallable.liveHandleAddresses) {
    const MethodChannel('media_kit/native_broker')
        .invokeMethod<void>('Register', '$address')
        .catchError((Object _) {});
  }
}
