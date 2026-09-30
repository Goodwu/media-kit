/// Bookkeeping for platform surface owners, extracted from
/// [AndroidVideoController] so the ownership invariants have one home.
///
/// Each owner moves through an explicit phase model:
///
/// ```text
///            announceQueuedBind            markInFlight
///  (untracked) ───────────────▶ queued ───────────────▶ inFlight ──▶ bound
///                                  │                        │
///                                  │ markBindFailed         │ markBindFailed
///                                  ▼                        ▼
///                                failed ◀──────────────────┘
///                                  │ clearBindFailed (retry)
///                                  └──▶ queued
///
///  any live phase ── beginRelease ──▶ releasing ── finishRelease/cancelRelease ──▶ (untracked)
///  any live phase ── destroy ─────────────────────────────────────────▶ (untracked)
/// ```
///
/// The queries mirror the exact set semantics the controller relied on:
/// an owner can be live while simultaneously release-pending or
/// bind-failed, `anyQueuedCandidate` is the conjunction the bind scheduler
/// uses, and `destroy` (a Surface destroyed event) keeps any pending
/// fallback intent serial so a late destroy can still authorize a
/// replacement bind.
///
/// The ledger holds no channels and starts no timers: the controller keeps
/// orchestrating MethodChannel calls and retries, and reports state changes
/// here. That keeps this class deterministic and unit-testable.

/// Lifecycle phase of a single surface owner, derived from its ledger state.
enum SurfaceOwnerPhase {
  /// Unknown to the ledger (never tracked, or fully reclaimed).
  untracked,

  /// Identity known, waiting for a bind attempt.
  queued,

  /// A bind attempt is running for this owner.
  inFlight,

  /// The active output.
  bound,

  /// The last bind attempt failed; the owner stays live for retries.
  failed,

  /// A release was requested and its acknowledgement is pending.
  releasing,
}

class SurfaceOwnerLedger<O> {
  final Map<O, _OwnerRecord> _records = {};
  O? _inFlightOwner;

  final Set<int> _authorizedFallbackSerials = {};
  final Map<O, int> _pendingFallbackSerials = {};

  /// Makes [owner] live and eligible for the next bind attempt. Re-announcing
  /// a destroyed owner refreshes its announcement order (the newest live
  /// owner wins fallback selection) while preserving any bind-failure or
  /// release-pending state.
  void announceQueuedBind(O owner) {
    final previous = _records.remove(owner);
    _records[owner] = _OwnerRecord(
      live: true,
      queued: true,
      failed: previous?.failed ?? false,
      releasing: previous?.releasing ?? false,
    );
  }

  /// Marks [owner] as waiting for a bind without making it live (a bind
  /// request that may yet be rejected as stale).
  void enqueueBind(O owner) {
    _records.putIfAbsent(owner, _OwnerRecord.new).queued = true;
  }

  /// The bind attempt for [owner] ended; it is no longer queued.
  void dequeueBind(O owner) {
    _prune(_records[owner]?..queued = false, owner);
  }

  /// The owner identity is live (announced and not yet destroyed).
  bool isLive(O owner) => _records[owner]?.live ?? false;

  /// Live and its last bind attempt did not fail.
  bool isLiveAndNotBindFailed(O owner) {
    final record = _records[owner];
    return record != null && record.live && !record.failed;
  }

  /// Queued for a bind, live, and its last bind attempt did not fail.
  bool isQueuedCandidate(O owner) {
    final record = _records[owner];
    return record != null && record.queued && record.live && !record.failed;
  }

  bool anyQueuedCandidate(bool Function(O owner) predicate) {
    for (final entry in _records.entries) {
      final record = entry.value;
      if (record.queued && record.live && !record.failed &&
          predicate(entry.key)) {
        return true;
      }
    }
    return false;
  }

  /// Live owners, in announcement order.
  Iterable<O> get liveOwners sync* {
    for (final entry in _records.entries) {
      if (entry.value.live) yield entry.key;
    }
  }

  /// Newest live owner by announcement order.
  O? get newestLiveOwner {
    O? newest;
    for (final entry in _records.entries) {
      if (entry.value.live) newest = entry.key;
    }
    return newest;
  }

  void markBindFailed(O owner) {
    _records.putIfAbsent(owner, _OwnerRecord.new).failed = true;
  }

  void clearBindFailed(O owner) {
    _prune(_records[owner]?..failed = false, owner);
  }

  bool isBindFailed(O owner) => _records[owner]?.failed ?? false;

  /// An owner whose Surface was destroyed. The identity stops being live,
  /// but a pending fallback intent serial is kept: the late destroy still
  /// authorizes the replacement bind it selected.
  void destroy(O owner) {
    final record = _records[owner];
    if (record == null) return;
    record.live = false;
    _prune(record, owner);
  }

  /// Drop every live owner identity (terminal dispose). Release-pending and
  /// bind-failed markers survive, exactly like the separate sets did.
  void clearLiveOwners() {
    for (final entry in _records.entries.toList()) {
      entry.value.live = false;
      _prune(entry.value, entry.key);
    }
  }

  void markInFlight(O owner) {
    _inFlightOwner = owner;
  }

  void clearInFlight() {
    _inFlightOwner = null;
  }

  void clearInFlightIf(O owner) {
    if (_inFlightOwner == owner) _inFlightOwner = null;
  }

  O? get inFlightOwner => _inFlightOwner;

  /// Requests release for [owner]; the owner may be unknown yet (a late
  /// destroy for a Surface this controller never tracked).
  void beginRelease(O owner) {
    _records.putIfAbsent(owner, _OwnerRecord.new).releasing = true;
  }

  /// Every live owner becomes release-pending (terminal dispose).
  void beginReleaseAllLive() {
    for (final record in _records.values) {
      if (record.live) record.releasing = true;
    }
  }

  /// Cancels a release request without reclaiming the owner.
  void cancelRelease(O owner) {
    _prune(_records[owner]?..releasing = false, owner);
  }

  /// The release completed: the owner is reclaimed and its pending fallback
  /// intent serial is dropped.
  void finishRelease(O owner) {
    _records.remove(owner);
    _pendingFallbackSerials.remove(owner);
  }

  /// Drop every release-pending marker (terminal dispose after the platform
  /// confirmed it released everything).
  void clearReleasing() {
    for (final entry in _records.entries.toList()) {
      entry.value.releasing = false;
      _prune(entry.value, entry.key);
    }
  }

  bool isReleasing(O owner) => _records[owner]?.releasing ?? false;

  /// Release-pending owners.
  Iterable<O> get releasingOwners sync* {
    for (final entry in _records.entries) {
      if (entry.value.releasing) yield entry.key;
    }
  }

  /// Fallback intent serials: a destroyed or releasing owner may authorize
  /// one replacement bind, keyed by complete owner identity. They are kept
  /// across [destroy] and dropped only by [finishRelease],
  /// [clearPendingFallbackSerial] and [clearPendingFallbackSerials].
  int? pendingFallbackSerial(O owner) => _pendingFallbackSerials[owner];

  void setPendingFallbackSerial(O owner, int serial) {
    _pendingFallbackSerials[owner] = serial;
  }

  void clearPendingFallbackSerial(O owner) {
    _pendingFallbackSerials.remove(owner);
  }

  void clearPendingFallbackSerials() {
    _pendingFallbackSerials.clear();
  }

  /// Serials allowed to publish even though their view is not the latest
  /// created one (explicit fallback authorizations).
  void authorizeFallbackSerial(int serial) {
    _authorizedFallbackSerials.add(serial);
  }

  bool isAuthorizedFallbackSerial(int serial) =>
      _authorizedFallbackSerials.contains(serial);

  void clearAuthorizedFallbackSerials() {
    _authorizedFallbackSerials.clear();
  }

  /// Derived phase for diagnostics and tests. Combined states are legal in
  /// this model (for example failed + releasing); the most progressed phase
  /// wins.
  SurfaceOwnerPhase phaseOf(O owner) {
    if (identical(_inFlightOwner, owner)) return SurfaceOwnerPhase.inFlight;
    final record = _records[owner];
    if (record == null) return SurfaceOwnerPhase.untracked;
    if (record.releasing) return SurfaceOwnerPhase.releasing;
    if (record.failed) return SurfaceOwnerPhase.failed;
    if (record.queued) return SurfaceOwnerPhase.queued;
    return SurfaceOwnerPhase.bound;
  }

  /// A record disappears only when no set would have contained the owner.
  void _prune(_OwnerRecord? record, O owner) {
    if (record == null) return;
    if (!record.live && !record.queued && !record.failed && !record.releasing) {
      _records.remove(owner);
    }
  }
}

class _OwnerRecord {
  bool live;
  bool queued;
  bool failed;
  bool releasing;

  _OwnerRecord({
    this.live = false,
    this.queued = false,
    this.failed = false,
    this.releasing = false,
  });
}
