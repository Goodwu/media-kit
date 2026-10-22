import 'package:synchronized/synchronized.dart';

/// Operations that can change the active native entry or its playlist.
/// Seek deliberately uses only the Player lock: output binding can need it
/// while a source transition is waiting for the output to become ready.
enum NativeSourceOperation {
  open,
  stop,
  dispose,
  remove,
  next,
  previous,
  jump,
  play,
  playOrPause,
  add,
  move,
  setShuffle,
  setPlaylistMode,
  seek,
}

/// Per-player source admission. Always acquire this gate before Player.lock.
/// Neither lock is reentrant; code already holding Player.lock must explicitly
/// use the existing synchronized:false path for nested player operations.
class NativeSourceTransitionGate {
  NativeSourceTransitionGate(this.playerLock);

  final Lock playerLock;
  final Lock _gate = Lock();

  Future<T> run<T>(Future<T> Function() body) => _gate.synchronized(body);

  Future<T> schedule<T>(
    NativeSourceOperation operation,
    Future<T> Function() body, {
    bool synchronized = true,
  }) {
    if (!synchronized) return body();
    if (operation == NativeSourceOperation.seek) {
      return playerLock.synchronized(body);
    }
    return run(() => playerLock.synchronized(body));
  }

  /// Cancellation is synchronous even when the terminating operation queues
  /// behind a transition. The transition can observe it and clean up first.
  void closeAdmission(void Function()? notify) => notify?.call();
}
