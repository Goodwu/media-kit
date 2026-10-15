/// This file is a part of media_kit (https://github.com/media-kit).
///
/// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
/// All rights reserved.
/// Use of this source code is governed by the MIT license that can be found
/// in the LICENSE file.
import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:flutter/services.dart'
    show MethodChannel, MissingPluginException;

import 'hdr_open_plan.dart';
import 'hdr_output_resources.dart';
import 'hdr_route.dart';
import 'hdr_output_failure.dart';
import 'hdr_yuv_presentation_contract.dart';
import 'hdr_yuv_window_arm_ffi_resolver.dart';

/// Vendor native exports driven by [HdrYuvWindowArm]. Every entry is a pure
/// atomic store inside the vendor library (safe from any thread); null marks
/// an export or library that could not be resolved in this process.
class HdrYuvWindowFfiBindings {
  const HdrYuvWindowFfiBindings({
    this.setDiagDataSpace,
    this.setYuvDiagEnabled,
    this.disarmYuvDiag,
  });

  /// `mkvendor_set_diag_dataspace` — the diag-dataspace atom (0 = off).
  final void Function(int dataSpace)? setDiagDataSpace;

  /// `mkvendor_set_yuv_diag_enabled` — the legacy unbound YUV diag atom.
  final void Function(int enabled)? setYuvDiagEnabled;

  /// `mkvendor_disarm_yuv_diag` — clears flag, format record and owner
  /// binding in one call; preferred over the legacy setter for disarm.
  final void Function()? disarmYuvDiag;
}

/// One control method call onto the vendor plugin's channel. Injectable so
/// tests can fake the platform round trip; never throws by contract callers
/// that catch (the manager treats every throw as unavailability).
typedef HdrYuvWindowArmChannel = Future<Object?> Function(
  String method,
  Map<String, Object?> arguments,
);

/// Compatibility names for the historical adapter and its regressions.
/// Generic orchestration depends on hdr_output_failure.dart instead.
typedef HdrYuvWindowArmFailure = HdrOutputPreparationFailure;
typedef HdrYuvWindowLeaseConflict = HdrOutputLeaseConflict;

/// The in-isolate record of who currently owns the YUV window presentation
/// attempt (B1). The underlying native atomics
/// (`mkvendor_set_diag_dataspace`, `mkvendor_set_yuv_diag_enabled`) are
/// process-global and identity-free — the vendor disarm clears whatever is
/// armed, with no caller attribution — so the Dart side supplies the
/// ownership layer: one lease per admitted attempt, registered by the
/// manager instance (one per session) at ADMISSION time, before the
/// previous output's retirement inside the output slot's ensure.
///
/// * [acquire] registers the pending attempt ownership (B2: a partial arm
///   is attributable to its attempt);
/// * [release] validates the owner — only the lease holder clears it;
/// * [markDebt]/[clearDebt] track the retained cleanup debt at process
///   scope: while any manager's debt is uncleared, no manager's output
///   initialization passes.
///
/// Process scope (V2 B1 rounds 3–4): the CROSS-ENGINE arbitration lives in
/// the vendor plugin's process-static reader/writer gate
/// (`ProcessOutputInitGate`, reached over the
/// `media_kit_android_dataspace_vendor/lg_yuv_diag` channel) — Java statics
/// are shared by every Flutter engine in this OS process, and its write
/// identity is a process-unique LEASE id (never a configured token), so the
/// same token can never be shared into a second writer on any engine. This
/// registry is the IN-ISOLATE identity layer: it keys ownership by manager
/// instance, catching the same-token cross-session aliasing inside this
/// isolate before the channel is even reached. Residual limitations,
/// honestly scoped:
///
/// * callers that bypass the Dart admission protocol (direct legacy
///   `enableYuvDiag()` or native `mkvendor_set_yuv_diag_enabled` calls) do
///   not pass the gate;
/// * a cross-engine Surface owner termination still clears a legacy native
///   arm (the existing fail-closed termination semantics — the gate
///   prevents concurrent ARMING, not foreign teardown);
/// * an `EndOutputInitWrite` that can no longer reach any attached engine
///   leaves the gate lease held until the last engine detaches (the plugin
///   resets the gate there) or the process restarts.
class HdrYuvWindowProcessRegistry {
  HdrYuvWindowProcessRegistry._();

  static HdrYuvWindowProcessLease? _activeLease;
  static Object? _debtOwner;

  /// The active attempt lease, or null when the atomics are unowned.
  static HdrYuvWindowProcessLease? get activeLease => _activeLease;

  /// The manager currently retaining cleanup debt, or null when clear.
  static Object? get debtOwner => _debtOwner;

  /// Registers [owner] as the pending owner of the atomics for [plan]'s
  /// attempt. Throws [HdrYuvWindowLeaseConflict] when any lease is already
  /// active — including the caller's own (a manager re-entering its arm
  /// sequence concurrently must fail closed, not overwrite its lease).
  static void acquire(Object owner, Object? plan) {
    final current = _activeLease;
    if (current != null) {
      throw HdrYuvWindowLeaseConflict(
          'the YUV window arm lease is already held '
          '(owner=${identical(current.owner, owner) ? 'self' : 'another session'}, '
          'plan=${current.plan})');
    }
    _activeLease = HdrYuvWindowProcessLease(owner: owner, plan: plan);
  }

  /// Whether [owner] holds the active lease.
  static bool holdsLease(Object owner) => identical(_activeLease?.owner, owner);

  /// Releases the active lease, validating that [owner] is its holder.
  /// Returns whether a lease owned by [owner] was actually released.
  static bool release(Object owner) {
    final current = _activeLease;
    if (current == null || !identical(current.owner, owner)) return false;
    _activeLease = null;
    return true;
  }

  /// Marks the cleanup debt as retained by [owner] (the lease holder whose
  /// disarm failed).
  static void markDebt(Object owner) {
    _debtOwner = owner;
  }

  /// Clears the cleanup debt, validating that [owner] is the debtor.
  static bool clearDebt(Object owner) {
    if (!identical(_debtOwner, owner)) return false;
    _debtOwner = null;
    return true;
  }

  /// Isolates the static state between tests. Never call in production: a
  /// process that leaks a lease or debt must keep failing closed.
  @visibleForTesting
  static void resetForTesting() {
    _activeLease = null;
    _debtOwner = null;
  }
}

/// One admitted attempt's ownership record in [HdrYuvWindowProcessRegistry].
class HdrYuvWindowProcessLease {
  const HdrYuvWindowProcessLease({required this.owner, this.plan});
  final Object owner;

  /// The attempt's plan instance — the identity a terminal cleanup must
  /// match (a stale attempt's late cleanup must not clear a successor).
  final Object? plan;
}

/// Route-scoped ownership of the vendor YUV window presentation arms (plan
/// C: the arm lifecycle belongs to the production library and is routed by
/// execution attempt).
///
/// The manager owns a PAIR of process-global vendor atomics that must always
/// migrate together:
///
/// * the diag-dataspace atom (`mkvendor_set_diag_dataspace(0x11C60000)`),
///   consumed by mpv once at its EGL window surface creation — the
///   PQ/LIMITED injection that labels the config49 NV12 window;
/// * the YUV diag atom (`mkvendor_set_yuv_diag_enabled` / the owner-bound
///   `enableYuvDiag(token, generation)` entry), which takes mpv's EGL
///   context creation down the NV12 branch and forces the window dataspace
///   label to BT2020 PQ / LIMITED while armed.
///
/// Arm admission is the YUV window route itself
/// ([HdrYuvPresentationContract.isYuvWindowRoute]) plus the full fail-closed
/// quad validation, the device's declared PQ presentation channel and the
/// vendor exact device gate. There is no build define: any other route takes
/// ZERO arms and is bit-identical to the pre-manager behavior.
///
/// Arm ordering (existing rule): owner-bound first through the vendor plugin
/// channel; a refusal or an unavailable channel falls back to the legacy
/// unbound FFI arm. A missing library, a missing symbol or a failed pairing
/// fails the YUV attempt explicitly; a non-YUV route never fails because the
/// vendor plugin is absent.
///
/// Process admission (V2 B1 round 3): [initializeOutput] wraps the output
/// slot's `ensure` with a two-point protocol —
///
/// 1. ADMISSION, at the wrapper's entry, BEFORE the previous output's
///    retirement inside `ensure` (a rejected initializer performs no
///    teardown at all): a YUV route takes the process WRITE admission
///    (the Java reader/writer gate plus this isolate's registry lease),
///    any other route takes the READ admission. Conflicts are rejected
///    with [HdrYuvWindowLeaseConflict]; an unreachable gate passes a
///    non-YUV initialization (it can never arm anything) and fails a YUV
///    route closed.
/// 2. The ARM itself stays where plan C put it — as the slot's internal
///    preparation hook, AFTER the previous output's disposal retired its
///    Surface (an owner termination clears a legacy arm) and strictly
///    BEFORE the new output's creation (output binding already triggers
///    VO initialization).
///
/// The protection interval spans the whole asynchronous initialization and
/// its real tail: a READ admission is released when the initialization
/// settles — the platformView topology's bind completion, or the texture
/// topology's layout rebuild (`prepareAndroidTextureOutput`), whichever
/// this route's real Surface/VO initialization ends with — and a WRITE
/// admission is held to the owning attempt's terminal cleanup
/// ([endAttempt]). Device limitation, precisely scoped: a concurrent
/// second output initialization is REJECTED while a P8.4 YUV OPEN
/// TRANSACTION is between its admission and its terminal cleanup — NOT
/// during the whole playback period (the attempt-scoped arm and this
/// admission end together before the open result completes, so steady
/// playback accepts new initializations). Under process-global atomics a
/// concurrent initializer inside that interval would be poisoned, and
/// rejection is the honest semantics.
///
/// Every hook invocation performs a real arm: the reuse-failure path runs
/// the hook a second time after the retired output's owner termination
/// already cleared the native pair, so a plan-identity cache here would
/// leave the rebuilt output unauthorized (B3). `endAttempt` is the awaited
/// terminal cleanup the open coordinator runs at every execution-attempt
/// end; a failed cleanup retains debt that blocks the next initialization
/// until it clears. Ordinary production callers without a configured owner
/// token fail admission explicitly — automatic owner lifecycle for them is
/// a separate, currently blocked deliverable.
class HdrYuvWindowArm implements HdrOutputResources<HdrOpenPlan> {
  HdrYuvWindowArm({
    this.ownerToken,
    required this.ownerGeneration,
    HdrYuvWindowFfiBindings? Function()? bindingsResolver,
    HdrYuvWindowArmChannel? channel,
  })  : _bindingsResolver = bindingsResolver ?? resolveHdrYuvWindowFfiBindings,
        _channel = channel ?? _defaultChannelInvoke;

  /// The vendor plugin control channel the library side calls. The plugin
  /// handlers forward to the extension instance that actually registered the
  /// Surface owner ledger — never a second instance — and expose the
  /// process-static output-initialization gate (`Begin/EndOutputInit*`).
  static const String channelName =
      'media_kit_android_dataspace_vendor/lg_yuv_diag';

  static Future<Object?> _defaultChannelInvoke(
    String method,
    Map<String, Object?> arguments,
  ) =>
      const MethodChannel(channelName).invokeMethod<Object?>(method, arguments);

  /// The configured surface owner token (`lgExperimentOwnerToken`). Null on
  /// ordinary production construction — such callers fail YUV admission
  /// explicitly instead of silently running an unauthorized global arm.
  final String? ownerToken;

  /// Non-constructive owner-generation observation for the bound arm: reads
  /// only the already-published output (never creates a wrapper) and yields
  /// null when nothing is published yet (the legacy fallback then applies).
  final Future<int?> Function() ownerGeneration;

  final HdrYuvWindowFfiBindings? Function() _bindingsResolver;
  final HdrYuvWindowArmChannel _channel;

  HdrYuvWindowFfiBindings? _bindings;
  bool _bindingsResolved = false;

  HdrYuvWindowFfiBindings? get _ffi {
    if (!_bindingsResolved) {
      _bindingsResolved = true;
      try {
        _bindings = _bindingsResolver();
      } catch (error) {
        debugPrint('YUV-DIAG: vendor FFI bindings unavailable ($error)');
        _bindings = null;
      }
    }
    return _bindings;
  }

  _ArmedScope? _armed;
  bool _cleanupDebt = false;
  Object? _lastDisarmError;
  bool _disposed = false;

  /// The plan of the attempt currently holding the guarded WRITE admission
  /// (set at admission, cleared at release). Null for unguarded direct
  /// [armForAttempt] calls, which register their pending ownership at arm
  /// time instead.
  HdrOpenPlan? _writeAdmission;

  /// The process gate's LEASE id for the current write admission (R3-4:
  /// the only release handle; a configured token is never shared into a
  /// second writer). Zero = no remotely-granted admission.
  int _gateLeaseId = 0;

  /// Whether a process read admission granted to this manager is still
  /// unreleased.
  bool _readGateHeld = false;

  /// An output initialization (or an arm sequence) of THIS manager is in
  /// flight. Re-entry while suspended at an await is a typed conflict —
  /// never a silent disarm of the in-flight companion (V2 B1 round 3,
  /// self-report ② correction).
  bool _initializing = false;
  bool _arming = false;

  @visibleForTesting
  bool get isArmed => _armed != null;

  @visibleForTesting
  bool get hasCleanupDebt => _cleanupDebt;

  @visibleForTesting
  Object? get armedPlan => _armed?.plan;

  /// Sync admission used at the earliest open phase (backend validate):
  /// returns the refusal reason for a YUV window route this manager cannot
  /// arm, or null when admissible. Non-YUV routes are always null — they
  /// neither arm nor fail here.
  static String? routeAdmissionRefusal(HdrOpenPlan plan, String? ownerToken) {
    final route = plan.route;
    if (!HdrYuvPresentationContract.isYuvWindowRoute(route)) return null;
    try {
      HdrYuvPresentationContract.validate(route);
    } on StateError catch (error) {
      return 'presentation contract rejected: ${error.message}';
    }
    final capabilities = plan.capabilities;
    if (!capabilities.pqPresentation.yuvWindow) {
      return 'device declares no YUV window PQ presentation channel';
    }
    final ext = capabilities.dataSpaceExt;
    if (capabilities.sdkInt != 24 ||
        ext?.id != 'lg-pq' ||
        ext?.applicable != true) {
      return 'vendor exact device gate refused '
          '(sdk=${capabilities.sdkInt}, ext=${ext?.id}, '
          'applicable=${ext?.applicable})';
    }
    if (ownerToken == null || ownerToken.isEmpty) {
      return 'no valid surface owner token: the YUV window route requires '
          'an owner-bound arm; automatic owner lifecycle for ordinary '
          'production callers is not available yet';
    }
    return null;
  }

  /// Throws [HdrYuvWindowArmFailure] when [plan]'s route is a YUV window
  /// route this manager cannot arm (early, explicit production-gap failure).
  void assertRouteAdmission(HdrOpenPlan plan) {
    final refusal = routeAdmissionRefusal(plan, ownerToken);
    if (refusal != null) {
      throw HdrYuvWindowArmFailure(HdrDegradeReason.yuvWindowArmUnavailable,
          cause: refusal);
    }
  }

  /// Process-level admission + guard for ONE output initialization (the
  /// output slot's `ensure`), covering the previous output's retirement,
  /// the internal preparation (the arm), the creation, the publication and
  /// the readiness wait:
  ///
  /// * ADMISSION runs at this wrapper's entry — BEFORE `ensure`, hence
  ///   before any retirement/teardown — so a rejected initializer has zero
  ///   side effects. A YUV route takes the WRITE admission (held to
  ///   [endAttempt]); any other route takes the READ admission (released
  ///   when [initialize] settles).
  /// * While this manager already has an initialization (or an arm
  ///   sequence) in flight, re-entry is a typed [HdrYuvWindowLeaseConflict]
  ///   — the suspended companion is never silently disarmed or replaced.
  ///
  /// The [initialize] callback must not itself call [initializeOutput].
  Future<T> initializeOutput<T>(
    HdrOpenPlan plan,
    Future<T> Function() initialize,
  ) async {
    if (_disposed) throw StateError('YUV window arm manager is disposed');
    if (_initializing || _arming) {
      throw const HdrYuvWindowLeaseConflict(
          'this manager already has an output initialization in flight');
    }
    _initializing = true;
    try {
      if (HdrYuvPresentationContract.isYuvWindowRoute(plan.route)) {
        await _admitWrite(plan);
        try {
          return await initialize();
        } catch (error, stack) {
          if (_armed == null && !_cleanupDebt) {
            // The attempt died before arming and left no debt: the dead
            // attempt must not hold the process write (the coordinator's
            // terminal cleanup still runs and releases idempotently).
            await _releaseWrite();
          }
          Error.throwWithStackTrace(error, stack);
        }
      }
      await _admitRead();
      try {
        return await initialize();
      } finally {
        await _releaseRead();
      }
    } finally {
      _initializing = false;
    }
  }

  /// WRITE admission for a YUV attempt: route admission first (an
  /// inadmissible YUV route never takes a process admission at all), then
  /// retire this manager's own residual state, register the pending attempt
  /// ownership in the in-isolate registry (B2 — before anything, including
  /// the old output's retirement), then take the process gate's write
  /// LEASE. The gate allocates a process-unique lease id for this
  /// admission; it is the only release handle (R3-4: while any lease is
  /// held every other acquire is rejected, the same token included — the
  /// same attempt's rebuilt-output re-arm goes through [armForAttempt] and
  /// never re-acquires). A foreign conflict rejects with
  /// [HdrYuvWindowLeaseConflict]; an unreachable gate fails the YUV route
  /// closed ([HdrYuvWindowArmFailure]).
  Future<void> _admitWrite(HdrOpenPlan plan) async {
    assertRouteAdmission(plan);
    await _retireOwnResidue();
    HdrYuvWindowProcessRegistry.acquire(this, plan);
    _writeAdmission = plan;
    final Object? reply;
    try {
      reply = await _channel('BeginOutputInitWrite', <String, Object?>{
        'ownerToken': ownerToken,
        'leaseId': _gateLeaseId,
      });
    } catch (error) {
      HdrYuvWindowProcessRegistry.release(this);
      _writeAdmission = null;
      throw HdrYuvWindowArmFailure(
          HdrDegradeReason.yuvWindowArmUnavailable,
          cause: 'process output-initialization gate unreachable: $error');
    }
    final leaseId = reply is int && reply > 0 ? reply : 0;
    if (leaseId == 0) {
      HdrYuvWindowProcessRegistry.release(this);
      _writeAdmission = null;
      throw const HdrYuvWindowLeaseConflict(
          'a concurrent output initialization or YUV arm is live in this '
          'process; the YUV attempt is rejected');
    }
    _gateLeaseId = leaseId;
  }

  /// READ admission for a non-YUV initialization: same in-isolate checks,
  /// then the process gate's read slot. A live YUV write lease rejects with
  /// [HdrYuvWindowLeaseConflict] BEFORE any teardown.
  ///
  /// Unreachable-gate rule (constrained, not broad): ONLY
  /// [MissingPluginException] — the typed signal that no handler is bound
  /// on this engine's channel — passes the initialization unguarded. In a
  /// build whose engines do not register the vendor plugin, no YUV arm can
  /// exist anywhere in the process: the owner-bound arm needs the channel
  /// and the legacy FFI arm needs the vendor library, which ships with the
  /// plugin module (an app registering the plugin on only SOME of its
  /// engines is a mixed configuration outside this contract). Every OTHER
  /// channel failure is NOT evidence that the process has no YUV
  /// participant — the initialization fails closed instead of guessing.
  Future<void> _admitRead() async {
    await _retireOwnResidue();
    final Object? reply;
    try {
      reply =
          await _channel('BeginOutputInitRead', const <String, Object?>{});
    } on MissingPluginException {
      debugPrint('YUV-DIAG: process init gate not registered on this '
          'engine; non-YUV initialization proceeds unguarded');
      return;
    } catch (error) {
      throw HdrYuvWindowLeaseConflict(
          'the process output-initialization gate failed ($error); a '
          'concurrent YUV arm cannot be excluded, so the non-YUV output '
          'initialization is rejected');
    }
    if (reply != true) {
      throw const HdrYuvWindowLeaseConflict(
          'a YUV arm is live in this process; the non-YUV output '
          'initialization is rejected');
    }
    _readGateHeld = true;
  }

  Future<void> _releaseRead() async {
    if (!_readGateHeld) return;
    _readGateHeld = false;
    try {
      await _channel('EndOutputInitRead', const <String, Object?>{});
    } catch (error) {
      debugPrint('YUV-DIAG: process read release unreachable ($error)');
    }
  }

  Future<void> _releaseWrite() async {
    _writeAdmission = null;
    HdrYuvWindowProcessRegistry.release(this);
    final leaseId = _gateLeaseId;
    _gateLeaseId = 0;
    if (leaseId == 0) return;
    try {
      final released = await _channel('EndOutputInitWrite', <String, Object?>{
        'ownerToken': ownerToken,
        'leaseId': leaseId,
      });
      if (released != true) {
        debugPrint('YUV-DIAG: process write lease $leaseId was not released '
            'by the gate (stale or superseded); the holder-side admission '
            'is still cleared locally');
      }
    } catch (error) {
      debugPrint('YUV-DIAG: process write release unreachable ($error); '
          'the gate write stays held until the last engine detaches');
    }
  }

  /// The in-isolate admission checks shared by every entry point:
  ///
  /// * another manager's retained cleanup debt → [HdrYuvWindowLeaseConflict]
  ///   (fail-closed: the atomics may still be poisoned, and only the debtor
  ///   may clear them);
  /// * another manager's active lease → [HdrYuvWindowLeaseConflict];
  /// * this manager's own residual state (a stale admission or retained
  ///   debt from an attempt that already ended) → retired first; a failing
  ///   retirement fails the attempt with [HdrYuvWindowArmFailure].
  Future<void> _retireOwnResidue() async {
    final debtOwner = HdrYuvWindowProcessRegistry.debtOwner;
    if (debtOwner != null && !identical(debtOwner, this)) {
      throw const HdrYuvWindowLeaseConflict(
          'another session retains YUV window cleanup debt; output '
          'initialization is blocked until it clears');
    }
    final lease = HdrYuvWindowProcessRegistry.activeLease;
    if (lease != null && !identical(lease.owner, this)) {
      throw const HdrYuvWindowLeaseConflict(
          'another session holds the YUV window arm lease');
    }
    if (debtOwner == null && lease == null) return;
    if (!await _disarmAll()) {
      throw HdrYuvWindowArmFailure(HdrDegradeReason.yuvWindowArmUnavailable,
          cause: 'previous arm cleanup still failing: $_lastDisarmError');
    }
    await _releaseWrite();
  }

  /// Arms the pair for [plan]'s execution attempt. No-op for every route
  /// that is not the YUV window carrier (zero arms, unchanged routing) —
  /// the in-isolate residue check still runs first, so a non-YUV direct
  /// call is also barrier-checked.
  ///
  /// Inside a guarded [initializeOutput] the admission already registered
  /// this exact attempt's ownership; an unguarded direct call registers its
  /// pending ownership at arm time instead (B2). A re-entry while an arm
  /// sequence is in flight is a typed conflict, and every continuation after
  /// an awaited step re-verifies it still owns the attempt before writing
  /// further atoms.
  Future<void> armForAttempt(HdrOpenPlan plan) async {
    if (_disposed) throw StateError('YUV window arm manager is disposed');
    if (_arming) {
      throw const HdrYuvWindowLeaseConflict(
          'this manager already has an arm sequence in flight');
    }
    _arming = true;
    try {
      if (!HdrYuvPresentationContract.isYuvWindowRoute(plan.route)) {
        await _retireOwnResidue();
        return;
      }
      assertRouteAdmission(plan);
      final admission = _writeAdmission;
      if (admission != null) {
        // Guarded: initializeOutput admitted exactly this attempt before the
        // old output's retirement — the ownership is already registered.
        if (!identical(admission, plan)) {
          throw const HdrYuvWindowLeaseConflict(
              'the armed plan does not match the admitted attempt');
        }
      } else {
        // Unguarded direct call: in-isolate barrier, then arm-time pending
        // ownership.
        await _retireOwnResidue();
        HdrYuvWindowProcessRegistry.acquire(this, plan);
      }
      final setDiagDataSpace = _ffi?.setDiagDataSpace;
      if (setDiagDataSpace == null) {
        throw const HdrYuvWindowArmFailure(
            HdrDegradeReason.yuvWindowArmUnavailable,
            cause: 'diag dataspace armer unavailable; the YUV route requires '
                'the PQ/LIMITED injection to arm');
      }
      try {
        // Atom 1: the diag-dataspace PQ/LIMITED injection. mpv consumes it
        // once at its EGL window surface creation during this attempt.
        try {
          setDiagDataSpace(HdrYuvPresentationContract.windowDataSpace);
        } catch (error) {
          throw HdrYuvWindowArmFailure(
              HdrDegradeReason.yuvWindowArmUnavailable,
              cause: 'diag dataspace arm failed: $error');
        }
        // Atom 2: the YUV diag switch. Owner-bound first (vendor channel),
        // with the ledger-checked (token, generation) tuple; refusal or an
        // unavailable channel falls back to the legacy global arm.
        var bound = false;
        int? generation;
        try {
          generation = await ownerGeneration();
        } catch (error) {
          // B5: the generation read is an awaited platform step INSIDE the
          // paired rollback protection — an unexpected failure is handled
          // explicitly (legacy fallback), never an unguarded residue.
          debugPrint('YUV-DIAG: owner generation read failed ($error); '
              'legacy global arm');
        }
        _assertArmOwnership(plan);
        if (generation != null && generation > 0) {
          try {
            final enabled =
                await _channel('EnableYuvDiag', <String, Object?>{
              'ownerToken': ownerToken,
              'generation': generation,
            });
            bound = enabled == true;
            if (!bound) {
              debugPrint(
                  'YUV-DIAG: owner-bound arm refused; legacy global arm');
            }
          } catch (error) {
            debugPrint('YUV-DIAG: owner-bound arm unavailable ($error); '
                'legacy global arm');
          }
        } else {
          debugPrint(
              'YUV-DIAG: owner generation unavailable; legacy global arm');
        }
        _assertArmOwnership(plan);
        if (!bound) {
          final setYuvDiagEnabled = _ffi?.setYuvDiagEnabled;
          if (setYuvDiagEnabled == null) {
            throw const HdrYuvWindowArmFailure(
                HdrDegradeReason.yuvWindowArmUnavailable,
                cause: 'YUV diag switch unavailable');
          }
          try {
            setYuvDiagEnabled(1);
          } catch (error) {
            throw HdrYuvWindowArmFailure(
                HdrDegradeReason.yuvWindowArmUnavailable,
                cause: 'YUV diag arm failed: $error');
          }
        }
        _armed = _ArmedScope(plan, bound);
      } catch (error, stack) {
        // B5: unified rollback — every step after the ownership
        // registration (the setters, the generation read, the channel round
        // trips) runs inside this protection, so a partial arm never
        // survives its attempt. A failed rollback retains the process-level
        // cleanup debt while the original arm failure stands; the attempt
        // ownership itself stays registered for the terminal cleanup.
        if (!await _disarmAll()) {
          debugPrint('YUV-DIAG: partial-arm rollback failed '
              '($_lastDisarmError); cleanup debt retained');
        }
        Error.throwWithStackTrace(error, stack);
      }
    } finally {
      _arming = false;
    }
  }

  /// A continuation resuming after an awaited step must still own this
  /// attempt — an ownership lost mid-flight (e.g. a dispose that released
  /// the admission) fails the arm instead of writing further atoms that no
  /// one would clean (self-report ② correction).
  void _assertArmOwnership(HdrOpenPlan plan) {
    final lease = HdrYuvWindowProcessRegistry.activeLease;
    if (lease == null ||
        !identical(lease.owner, this) ||
        !identical(lease.plan, plan)) {
      throw HdrYuvWindowArmFailure(
          HdrDegradeReason.yuvWindowArmUnavailable,
          cause: 'the arm continuation lost its attempt ownership');
    }
  }

  /// Awaited terminal cleanup of the execution attempt owning [plan]:
  /// disarms the pair and releases the process write admission. Both are
  /// keyed to the attempt — a stale attempt's late cleanup must not clear a
  /// successor's arm or release its admission. A partial arm (B2: the
  /// ownership registered at admission or arm time, but no complete scope
  /// published) or a retained cleanup debt is ALSO ended here. Throws
  /// [HdrYuvWindowArmFailure] when the disarm fails (debt is retained —
  /// process-wide — and blocks the next output initialization until it
  /// clears).
  @override
  Future<void> endAttempt(HdrOpenPlan plan) async {
    final scope = _armed;
    if (scope != null) {
      if (!identical(scope.plan, plan)) return;
      if (!await _disarmAll()) {
        throw HdrYuvWindowArmFailure(
            HdrDegradeReason.yuvWindowArmUnavailable,
            cause: 'attempt cleanup failed: $_lastDisarmError');
      }
      await _releaseWrite();
      return;
    }
    // B2: pending or indebted residue this manager still owns under [plan].
    final lease = HdrYuvWindowProcessRegistry.activeLease;
    if (lease == null || !identical(lease.owner, this)) return;
    if (!identical(lease.plan, plan)) return;
    if (!await _disarmAll()) {
      throw HdrYuvWindowArmFailure(
          HdrDegradeReason.yuvWindowArmUnavailable,
          cause: 'attempt cleanup failed: $_lastDisarmError');
    }
    await _releaseWrite();
  }

  /// Terminal best-effort clear for session disposal. Idempotent; never
  /// throws. The write admission is released ONLY when the final disarm
  /// succeeded: the debt and the lock live and die together, so a retained
  /// debt keeps the process write held (the documented "blocked until an
  /// explicit cleanup or a process restart" must actually hold — releasing
  /// the Java write over uncleared atoms would let a cross-isolate
  /// initializer run while the atomics may still be poisoned).
  /// NOTE: after this, [armForAttempt]/[initializeOutput] throw — there is
  /// no "next arm recovery" for a disposed manager; recovery from retained
  /// debt is an explicit successful cleanup here or a process restart.
  @override
  Future<void> dispose() async {
    _disposed = true;
    var clean = true;
    if (_armed != null ||
        _cleanupDebt ||
        HdrYuvWindowProcessRegistry.holdsLease(this)) {
      clean = await _disarmAll();
    }
    if (clean) {
      await _releaseWrite();
    } else {
      debugPrint('YUV-DIAG: dispose retained the write admission together '
          'with the cleanup debt; output initialization stays blocked');
    }
    await _releaseRead();
  }

  /// Disarms both atoms in reverse arm order. Only the current lease owner
  /// may clear the process atomics (B1) — a manager that already released
  /// (or never held) the lease clears nothing but its local bookkeeping.
  /// Does NOT release the attempt ownership: that is [_releaseWrite]'s duty,
  /// so an admission (or a pending arm) survives a mid-attempt rollback and
  /// is ended exactly once by the attempt's terminal cleanup. The FFI disarm
  /// is the authoritative barrier (B5): the vendor channel's ACK is
  /// advisory and never trusted as proof the native pair is clear. Returns
  /// false (retaining process-level cleanup debt) when any reachable path
  /// failed.
  Future<bool> _disarmAll() async {
    if (!HdrYuvWindowProcessRegistry.holdsLease(this)) {
      _armed = null;
      _cleanupDebt = false;
      return true;
    }
    var ok = true;
    Object? error;
    final scope = _armed;
    try {
      if (scope?.bound ?? false) {
        try {
          await _channel('DisableYuvDiag', const <String, Object?>{});
        } catch (channelError) {
          debugPrint(
              'YUV-DIAG: channel disarm unavailable ($channelError); '
              'FFI disarm is the authoritative barrier');
        }
      }
      final ffiDisarm = _ffi?.disarmYuvDiag;
      if (ffiDisarm != null) {
        ffiDisarm();
      } else {
        _ffi?.setYuvDiagEnabled?.call(0);
      }
    } catch (disarmError) {
      ok = false;
      error = disarmError;
    }
    try {
      _ffi?.setDiagDataSpace?.call(0);
    } catch (diagError) {
      ok = false;
      error ??= diagError;
    }
    if (ok) {
      _armed = null;
      _cleanupDebt = false;
      HdrYuvWindowProcessRegistry.clearDebt(this);
    } else {
      _cleanupDebt = true;
      _lastDisarmError = error;
      HdrYuvWindowProcessRegistry.markDebt(this);
      debugPrint('YUV-DIAG: disarm failed ($error); cleanup debt retained');
    }
    return ok;
  }
}

class _ArmedScope {
  _ArmedScope(this.plan, this.bound);
  final Object plan;
  final bool bound;
}
