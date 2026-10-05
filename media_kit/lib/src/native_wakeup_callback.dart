import 'native_handle_lifecycle.dart';

/// Raised when a native event callback tries to dispose the same player.
///
/// Waiting for the event pump to drain from inside one of its own callbacks
/// would wait on that callback forever. The callback may finish and a later
/// external dispose attempt can then drain the pump normally.
class ReentrantEventPumpDisposeError extends StateError {
  ReentrantEventPumpDisposeError()
      : super('Cannot dispose a player from its native event callback');
}

/// Synchronous platform ownership of NativeCallable wakeup callbacks.
/// Installing and removing a callback must serialize with engine shutdown.
abstract class NativeWakeupCallbackOwner {
  bool install(int handle, int callback, int userdata);
  void remove(int handle);
}

abstract final class NativeWakeupCallbackOwnership {
  static NativeWakeupCallbackOwner? _owner;

  static NativeWakeupCallbackOwner? get owner => _owner;

  /// Wire before creating any Player. An owner cannot be replaced mid-lifetime.
  static void initialize(NativeWakeupCallbackOwner owner) {
    if (_owner != null && !identical(_owner, owner)) {
      throw StateError('Native wakeup callback owner already initialized');
    }
    if (_owner == null &&
        NativeHandleLifecycle.liveHandleAddresses.isNotEmpty) {
      throw StateError('Initialize wakeup ownership before the first Player');
    }
    _owner = owner;
  }
}
