import 'dart:ffi';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';

typedef _InstallNative = Int32 Function(
    Uint64, Pointer<Void>, Pointer<Void>, Pointer<Void>);
typedef _Install = int Function(
    int, Pointer<Void>, Pointer<Void>, Pointer<Void>);
typedef _RemoveNative = Int32 Function(Uint64, Pointer<Void>);
typedef _Remove = int Function(int, Pointer<Void>);

Future<void>? _initialization;

/// Call before the first Player on macOS. Hosts must also synchronously call
/// MediaKitVideoPlugin.prepareForEngineShutdown before destroying its engine.
/// Only the owner token and native function addresses cross the channel;
/// raw mpv handles never do.
Future<void> initializeDarwinMpvOwnerBroker() {
  if (!Platform.isMacOS) return Future.value();
  return _initialization ??= _initialize();
}

Future<void> _initialize() async {
  // Native function addresses are anchored by the plugin's Swift references.
  // SPM may statically link the plugin without exporting global symbols.
  final binding = await const MethodChannel('com.alexmercerind/media_kit_video')
      .invokeMapMethod<String, int>('WakeupCallback.Owner');
  final owner = binding?['owner'];
  final installAddress = binding?['install'];
  final removeAddress = binding?['remove'];
  if (owner == null ||
      owner <= 0 ||
      installAddress == null ||
      installAddress <= 0 ||
      removeAddress == null ||
      removeAddress <= 0) {
    throw StateError('Darwin wakeup callback owner unavailable');
  }
  final install =
      Pointer<NativeFunction<_InstallNative>>.fromAddress(installAddress)
          .asFunction<_Install>();
  final remove =
      Pointer<NativeFunction<_RemoveNative>>.fromAddress(removeAddress)
          .asFunction<_Remove>();
  NativeWakeupCallbackOwnership.initialize(
    _DarwinWakeupCallbackOwner(owner, install, remove),
  );
}

class _DarwinWakeupCallbackOwner implements NativeWakeupCallbackOwner {
  _DarwinWakeupCallbackOwner(this.owner, this._install, this._remove);
  final int owner;
  final _Install _install;
  final _Remove _remove;

  @override
  bool install(int handle, int callback, int userdata) =>
      _install(owner, Pointer.fromAddress(handle),
          Pointer.fromAddress(callback), Pointer.fromAddress(userdata)) ==
      1;

  @override
  void remove(int handle) {
    if (_remove(owner, Pointer.fromAddress(handle)) != 1) {
      throw StateError('Darwin wakeup callback owner mismatch');
    }
  }
}
