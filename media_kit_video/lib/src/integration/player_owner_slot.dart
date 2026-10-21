/// Serializes creation/replacement and retirement of one logical player owner.
///
/// Share a slot explicitly between callers which replace the same player. Slots
/// are independent; no process-wide state or application lifecycle is inferred.
/// Callbacks must not await another transition on the same slot. Owners must be
/// identity-bearing objects (not primitive values) and cannot be reused after
/// release. Repeated retirement of a released owner is a no-op.
class PlayerOwnerSlot {
  Future<void> _tail = Future<void>.value();
  final _released = Expando<bool>();
  Object? _retiredOwner;
  Future<void> Function()? _disposeRetiredOwner;

  /// Retries outstanding cleanup before admitting a new owner transition.
  /// A failed release keeps its owner and blocks the callback until a later
  /// retry succeeds. A failed callback does not poison the transition queue.
  Future<T> transition<T>(
      Future<T> Function(PlayerOwnerTransition transition) operation) {
    return _enqueue(() async {
      await _drainRetiredOwner();
      final transition = PlayerOwnerTransition._(this);
      try {
        final result = await operation(transition);
        await transition._finish();
        return result;
      } catch (error, stack) {
        // Drain any admitted release even when the callback failed. Preserve
        // the callback's error; a cleanup failure remains pending in the slot.
        try {
          await transition._finish();
        } catch (_) {}
        Error.throwWithStackTrace(error, stack);
      }
    });
  }

  /// Queues retirement from outside a transition (for example on view close).
  /// Repeating a failed retirement retries that same pending owner once, rather
  /// than first draining it and then disposing it a second time.
  Future<void> retire(Object owner, Future<void> Function() dispose) {
    return _enqueue(() async {
      await _drainRetiredOwner();
      await _retire(owner, dispose);
    });
  }

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final result = _tail.then((_) => operation());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<void> _retire(Object owner, Future<void> Function() dispose) async {
    if (_released[owner] == true) return;
    if (_retiredOwner != null && !identical(_retiredOwner, owner)) {
      throw StateError('A previous player owner is still awaiting disposal');
    }
    if (_retiredOwner == null) {
      _retiredOwner = owner;
      _disposeRetiredOwner = dispose;
    }
    await _drainRetiredOwner();
  }

  Future<void> _drainRetiredOwner() async {
    final owner = _retiredOwner;
    final dispose = _disposeRetiredOwner;
    if (owner == null || dispose == null) return;
    await dispose();
    _released[owner] = true;
    _retiredOwner = null;
    _disposeRetiredOwner = null;
  }
}

/// Scoped access to retirement while a [PlayerOwnerSlot] transition is active.
/// Await [retire] before creating/publishing its successor. If release fails,
/// do not create a successor unless a retry of that retirement succeeds. Do not
/// retain this object after the transition callback completes.
class PlayerOwnerTransition {
  PlayerOwnerTransition._(this._slot);

  final PlayerOwnerSlot _slot;
  Future<void> _retirements = Future<void>.value();
  bool _active = true;

  Future<void> retire(Object owner, Future<void> Function() dispose) {
    if (!_active) throw StateError('Player owner transition has ended');
    final result = _retirements.then(
      (_) => _slot._retire(owner, dispose),
      onError: (Object _, StackTrace __) => _slot._retire(owner, dispose),
    );
    _retirements = result;
    // Keep even an unawaited admitted release observed until _finish drains it.
    result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<void> _finish() {
    _active = false;
    return _retirements;
  }
}
