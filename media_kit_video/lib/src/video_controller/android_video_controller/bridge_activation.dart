/// This file is a part of media_kit (https://github.com/media-kit/media-kit).
///
/// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
/// All rights reserved.
/// Use of this source code is governed by MIT license that can be found in the LICENSE file.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'platform_output_availability.dart';
import 'platform_surface_release.dart';
import 'surface_owner_ledger.dart';

/// Outcome codes of the `PlatformVideoView.AuthorizeBridgeActivation`
/// channel contract, plus the Dart-side synthesized codes for conditions a
/// platform reply cannot express (a channel exception or a timeout).
///
/// Java-side alignment notes:
/// * `staleIdentity` arrives with `applicable=true` (the owner route was
///   located but its identity expired) — Dart discards it silently by code.
/// * a `wid=0` request is answered `staleIdentity` platform-side; the Dart
///   helper additionally hard-refuses to authorize a `wid=0` transaction
///   locally, so the two sides are double-insured.
/// * `ok=true` is returned for `code=ok` and for `code=notApplicable` (a
///   token-less view); only the all-three combination
///   (`applicable && ok && code==ok`) is a success, and `notApplicable` on
///   the token-gated path is a contract-mismatch failure.
/// * an unexpected platform-side `Throwable` maps to `invalidArguments` with
///   an `unexpected authorization failure: <type>` message — a typed
///   fail-closed (A) failure like any other non-stale code.
enum BridgeActivationCode {
  ok,
  notApplicable,
  staleIdentity,
  invalidArguments,
  tokenMismatch,
  invalidOwner,
  initFailed,

  /// Dart-side: the channel call itself failed, or another authorization is
  /// still pending for this controller.
  channelError,

  /// Dart-side: no reply arrived within the authorization budget. A late
  /// reply must never activate the transaction that timed out.
  timeout,
}

/// Only [BridgeActivationCode.staleIdentity] is a stale transaction: silently
/// discarded, no error published, no bind retry scheduled. Every other code
/// (including [BridgeActivationCode.notApplicable] on an expected-token
/// route — a contract mismatch, not a success) fails closed.
bool isBridgeActivationStaleCode(BridgeActivationCode code) =>
    code == BridgeActivationCode.staleIdentity;

/// The controller-side authorization gate (production unit).
///
/// The bridge is the LG yuv-diag presentation path's only carrier:
/// `hwdec == 'surfacetexture'` (`hdr_yuv_presentation_contract.dart`: "the
/// one and only carrier"). The strategy realizer derives every other route's
/// hwdec as `mediacodec-copy`/`mediacodec` (`hdr_strategy_realizer.dart`,
/// YUV-carrier ternary), including the `mediacodec_embed` native-DV routes
/// and the RGB-window/SDR policies (`hdr_output_policy.dart`); texture routes
/// are not PlatformView at all (`HdrOutputContract.controllerConfiguration`
/// sets `usePlatformView: topology == platformView`). Because the HDR session
/// injects an owner token for *every* Android session, the token alone must
/// not activate the barrier: non-bridge routes keep zero additional channel
/// calls and zero behavior change.
bool bridgeActivationGateEnabled({
  required bool usePlatformView,
  required String? ownerToken,
  required String? hwdec,
}) =>
    usePlatformView && ownerToken != null && hwdec == 'surfacetexture';

/// Shared inert [ValueListenable] used by controllers that never report a
/// bridge activation issue (every non-Android implementation).
class BridgeActivationIssues {
  const BridgeActivationIssues._();

  /// A const listenable whose value is always `null` and whose listener
  /// registrations are no-ops.
  static const ValueListenable<BridgeActivationIssue?> none =
      _NoBridgeActivationIssueListenable();
}

class _NoBridgeActivationIssueListenable
    implements ValueListenable<BridgeActivationIssue?> {
  const _NoBridgeActivationIssueListenable();

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}

  @override
  BridgeActivationIssue? get value => null;
}

/// One authorization request over the shared media_kit_video channel.
///
/// `handle`/`wid` use the same decimal-string encoding as the existing
/// `PlatformVideoView.Release*` calls. `generation` is the controller /
/// topology generation (never the per-view surface generation); the platform
/// uses it only for identity matching.
class BridgeAuthorizationRequest {
  const BridgeAuthorizationRequest({
    required this.handle,
    required this.generation,
    required this.viewId,
    required this.surfaceGeneration,
    required this.wid,
    required this.ownerToken,
  });

  final int handle;
  final int generation;
  final int viewId;
  final int surfaceGeneration;
  final int wid;
  final String? ownerToken;

  Map<String, Object> asChannelArguments() => <String, Object>{
        'handle': handle.toString(),
        'generation': generation,
        'viewId': viewId,
        'surfaceGeneration': surfaceGeneration,
        'wid': wid.toString(),
        if (ownerToken != null) 'ownerToken': ownerToken!,
      };

  @override
  String toString() =>
      '$generation/$viewId/$surfaceGeneration/$wid (handle=$handle)';
}

class _MalformedInt {
  const _MalformedInt();
}

/// Parsed reply of `PlatformVideoView.AuthorizeBridgeActivation`.
///
/// Strict six-key parsing: `applicable`, `ok`, `code`, `ownerGeneration`,
/// `surfaceGeneration` and `message` must all be PRESENT (`ownerGeneration`/
/// `surfaceGeneration`/`message` may carry null values, but the keys must
/// exist). A malformed reply — non-map, any missing key, wrong types, an
/// unknown code, or a `double` generation (even an integral one; the
/// standard codec only widens Java `double`, never `int`) — parses to an
/// [invalidArguments] failure, never to success.
class BridgeActivationResult {
  const BridgeActivationResult({
    required this.applicable,
    required this.ok,
    required this.code,
    this.ownerGeneration,
    this.surfaceGeneration,
    this.message,
  });

  final bool applicable;
  final bool ok;
  final BridgeActivationCode code;
  final int? ownerGeneration;
  final int? surfaceGeneration;
  final String? message;

  /// The platform explicitly confirmed an applicable, successful init: all
  /// three fields must agree. (`notApplicable` replies carry `ok=true` with
  /// `applicable=false` and are NOT a success.)
  bool get isOk =>
      applicable && ok && code == BridgeActivationCode.ok;

  /// A stale identity reply: the transaction must be discarded silently,
  /// regardless of the accompanying `applicable` value.
  bool get isStale => isBridgeActivationStaleCode(code);

  static BridgeActivationResult fromMap(Object? raw) {
    if (raw is! Map) {
      return _invalid('reply is not a map: ${raw.runtimeType}');
    }
    for (final key in const [
      'applicable',
      'ok',
      'code',
      'ownerGeneration',
      'surfaceGeneration',
      'message',
    ]) {
      if (!raw.containsKey(key)) {
        return _invalid('missing key: $key');
      }
    }
    final applicable = raw['applicable'];
    final ok = raw['ok'];
    final codeName = raw['code'];
    if (applicable is! bool || ok is! bool || codeName is! String) {
      return _invalid('mistyped applicable/ok/code');
    }
    BridgeActivationCode code;
    switch (codeName) {
      case 'ok':
        code = BridgeActivationCode.ok;
        break;
      case 'notApplicable':
        code = BridgeActivationCode.notApplicable;
        break;
      case 'staleIdentity':
        code = BridgeActivationCode.staleIdentity;
        break;
      case 'invalidArguments':
        code = BridgeActivationCode.invalidArguments;
        break;
      case 'tokenMismatch':
        code = BridgeActivationCode.tokenMismatch;
        break;
      case 'invalidOwner':
        code = BridgeActivationCode.invalidOwner;
        break;
      case 'initFailed':
        code = BridgeActivationCode.initFailed;
        break;
      default:
        return _invalid('unknown code: $codeName');
    }
    final messageValue = raw['message'];
    if (messageValue != null && messageValue is! String) {
      return _invalid('mistyped message');
    }
    // Combination consistency: a success must agree on all three fields, a
    // notApplicable must be `applicable=false, ok=true`, and `ok=true` never
    // accompanies a failure code. Anything else is a contract violation.
    if (code == BridgeActivationCode.ok && !(applicable && ok)) {
      return _invalid('inconsistent success: code=ok with '
          'applicable=$applicable ok=$ok');
    }
    if (code == BridgeActivationCode.notApplicable && (applicable || !ok)) {
      return _invalid('inconsistent notApplicable: applicable=$applicable '
          'ok=$ok');
    }
    if (code != BridgeActivationCode.ok &&
        code != BridgeActivationCode.notApplicable &&
        ok) {
      return _invalid('ok=true with failure code $codeName');
    }
    final ownerGeneration = _optionalInt(raw['ownerGeneration']);
    final surfaceGeneration = _optionalInt(raw['surfaceGeneration']);
    if (ownerGeneration is _MalformedInt ||
        surfaceGeneration is _MalformedInt) {
      return _invalid('ownerGeneration/surfaceGeneration not integers');
    }
    return BridgeActivationResult(
      applicable: applicable,
      ok: ok,
      code: code,
      ownerGeneration: ownerGeneration is int ? ownerGeneration : null,
      surfaceGeneration:
          surfaceGeneration is int ? surfaceGeneration : null,
      message: messageValue is String ? messageValue : null,
    );
  }

  static const _MalformedInt _malformedInt = _MalformedInt();

  /// Accepts a present null, or an `int`. Doubles are rejected even when
  /// integral, and any other type is malformed: a changed identity must
  /// never be accepted silently.
  static Object? _optionalInt(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    return _malformedInt;
  }

  static BridgeActivationResult _invalid(String detail) =>
      BridgeActivationResult(
        applicable: true,
        ok: false,
        code: BridgeActivationCode.invalidArguments,
        message: 'malformed AuthorizeBridgeActivation reply: $detail',
      );
}

/// Typed failure of one bridge authorization attempt. Carries the transaction
/// phase at which the attempt ended so the caller can pick the right cleanup
/// (before/after the new `wid` write began).
class BridgeActivationException implements Exception {
  const BridgeActivationException(
    this.code, {
    this.message,
    this.error,
    this.stackTrace,
    this.phase = BridgeActivationPhase.stopped,
  }) : assert(code != BridgeActivationCode.ok);

  final BridgeActivationCode code;
  final String? message;
  final Object? error;
  final StackTrace? stackTrace;
  final BridgeActivationPhase phase;

  /// A stale transaction: discard silently (no publish, no error, no retry).
  bool get stale => isBridgeActivationStaleCode(code);

  /// The new `wid` write had already started when the attempt ended.
  bool get widWriteStarted =>
      phase == BridgeActivationPhase.mayHaveWrittenWid ||
      phase == BridgeActivationPhase.applied;

  @override
  String toString() {
    final buffer = StringBuffer('BridgeActivationException($code');
    if (message != null) buffer.write(': $message');
    if (error != null) buffer.write(', error: $error');
    buffer.write(', phase: ${phase.name}');
    buffer.write(')');
    return buffer.toString();
  }
}

/// Kind of the scoped issue payload handed to the session. Decision A
/// (fail-closed) only ever publishes [failed]; a degraded-continue kind is
/// deliberately absent so the payload cannot masquerade as a recovery.
enum BridgeActivationIssueKind { failed }

/// A scoped surfacetexture bridge activation failure, published by the
/// controller and consumed by the HDR session.
///
/// The scope key is the controller instance + the complete owner identity +
/// the activation epoch: a newer real activation attempt supersedes the issue
/// (it stops blocking new outputs) but never restores a `verified` report —
/// only a fresh review of the current output can do that.
class BridgeActivationIssue {
  const BridgeActivationIssue({
    required this.controller,
    required this.owner,
    required this.activationEpoch,
    required this.outputIntentSerial,
    required this.code,
    this.error,
    this.message,
  }) : kind = BridgeActivationIssueKind.failed;

  /// Instance identity of the [AndroidVideoController] that failed.
  final Object controller;

  /// The complete owner identity whose activation failed.
  final AndroidSurfaceAccountId owner;

  /// The controller's monotonic activation attempt counter value at the
  /// failed authorization.
  final int activationEpoch;

  /// The output intent serial captured by the failed transaction.
  final int outputIntentSerial;

  final BridgeActivationIssueKind kind;
  final BridgeActivationCode code;
  final Object? error;
  final String? message;

  @override
  String toString() =>
      'BridgeActivationIssue($kind, $code, owner=$owner, '
      'epoch=$activationEpoch, intent=$outputIntentSerial)';
}

/// Phases of one stop → authorize → apply transaction.
enum BridgeActivationPhase {
  /// The first strict `vo=null` ACK completed: the previous VO (and any
  /// bridge window it owned) has been torn down.
  stopped,

  /// The Java-side authorization completed and the identity re-checked.
  authorized,

  /// The new `wid` property write has started (it may not be ACKed yet).
  mayHaveWrittenWid,

  /// The complete activation property sequence finished.
  applied,
}

/// Progress tracker of one activation transaction. The protocol advances the
/// phase; callers read it to pick the correct cancellation cleanup.
class BridgeActivationTransaction {
  BridgeActivationTransaction(this.widValue)
      : phase = BridgeActivationPhase.stopped;

  /// The `wid` value this transaction applies.
  final String widValue;

  BridgeActivationPhase phase;
}

/// The injectable stop → authorize → apply protocol actually driven by
/// `AndroidVideoController._applyWidLocked`.
///
/// Production supplies the strict property setter and the method-channel
/// invocation; tests supply fakes and Completer-controlled acknowledgements,
/// so ordering, cancellation and failure classification are exercised on this
/// exact choreography rather than a parallel model.
class BridgeActivationProtocol {
  BridgeActivationProtocol({
    required Future<void> Function(String key, String value) strictSetter,
    required Future<Object?> Function(BridgeAuthorizationRequest request)
        invokeAuthorization,
    this.authorizationTimeout = defaultAuthorizationTimeout,
    void Function(String event)? trace,
  })  : _strictSetter = strictSetter,
        _invokeAuthorization = invokeAuthorization,
        _trace = trace ?? _ignoreTrace;

  /// Budget for one channel authorization, independent of the 30 s strict
  /// property ACK and the 10 s output bind wait.
  static const Duration defaultAuthorizationTimeout = Duration(seconds: 5);

  final Future<void> Function(String key, String value) _strictSetter;
  final Future<Object?> Function(BridgeAuthorizationRequest request)
      _invokeAuthorization;
  final Duration authorizationTimeout;
  final void Function(String event) _trace;

  /// One outstanding authorization per protocol instance (= per controller):
  /// while a request is pending — from dispatch until it settles by reply,
  /// failure or timeout — no second request is sent.
  bool _authorizationPending = false;

  /// Monotonic count of authorizations actually DISPATCHED to the channel.
  /// Incremented exactly at dispatch (not at identity pre-checks), so an
  /// issue published for dispatch N is superseded only by a later real
  /// dispatch N+1 — a stale pre-check discard never bumps it.
  int _dispatchEpoch = 0;
  int get dispatchEpoch => _dispatchEpoch;

  static void _ignoreTrace(String event) {}

  /// Runs one complete `vo=null → authorize → android-surface-size / wid /
  /// vo / vid` transaction and returns its final [BridgeActivationTransaction].
  ///
  /// * [authorizeActivation] runs strictly after the first successful
  ///   `vo=null` ACK and before any activation property write. A `wid=0`
  ///   transaction never authorizes, no matter what the caller passes.
  /// * [activationStillCurrent] is re-checked after every activation
  ///   property ACK; a failed check throws a stale
  ///   [BridgeActivationException] carrying the phase reached.
  Future<BridgeActivationTransaction> apply({
    required String widValue,
    required String voValue,
    required String vidValue,
    required String androidSurfaceSizeValue,
    required bool writeVid,
    bool stopVideoFirst = false,
    Future<void> Function()? authorizeActivation,
    bool Function()? activationStillCurrent,
  }) async {
    final transaction = BridgeActivationTransaction(widValue);
    _trace('apply begin wid=$widValue vo=$voValue vid=$vidValue');
    // Hard prohibition: a stop transaction (wid=0) must never authorize the
    // bridge, regardless of the caller-supplied callback.
    final authorization = widValue == '0' ? null : authorizeActivation;
    if (widValue == '0' && authorizeActivation != null) {
      _trace('authorize skipped wid=0');
    }
    if (stopVideoFirst) {
      _trace('property begin vid=no before vo=null');
      await _strictSetter('vid', 'no');
      _trace('property complete vid=no before vo=null');
    }
    // It is important to re-initialize --vo after --android-surface-size.
    _trace('property begin vo=null');
    await _strictSetter('vo', 'null');
    _trace('property complete vo=null');
    transaction.phase = BridgeActivationPhase.stopped;
    if (authorization != null) {
      await authorization();
      transaction.phase = BridgeActivationPhase.authorized;
    }
    final entries = <MapEntry<String, String>>[
      // ORDER IS IMPORTANT.
      MapEntry('android-surface-size', androidSurfaceSizeValue),
      MapEntry('wid', widValue),
      MapEntry('vo', voValue),
      if (writeVid) MapEntry('vid', vidValue),
    ];
    for (final entry in entries) {
      if (entry.key == 'wid') {
        transaction.phase = BridgeActivationPhase.mayHaveWrittenWid;
      }
      _trace('property begin ${entry.key}=${entry.value}');
      await _strictSetter(entry.key, entry.value);
      _trace('property complete ${entry.key}=${entry.value}');
      final stillCurrent = activationStillCurrent;
      if (stillCurrent != null && !stillCurrent()) {
        throw BridgeActivationException(
          BridgeActivationCode.staleIdentity,
          message: 'activation identity changed after ${entry.key} write',
          phase: transaction.phase,
        );
      }
    }
    transaction.phase = BridgeActivationPhase.applied;
    _trace('apply complete wid=$widValue');
    return transaction;
  }

  /// Guards, sends and classifies one authorization. Throws a stale
  /// [BridgeActivationException] when [stillCurrent] fails before or after
  /// the channel call, when the reply is `staleIdentity`, or when a
  /// successful reply carries an owner/surface generation that does not
  /// match the request; and a hard one for every other non-success reply
  /// (including `notApplicable`, which on an expected-token route is a
  /// contract mismatch), channel failure, malformed reply or timeout.
  Future<void> authorize({
    required BridgeAuthorizationRequest request,
    required bool Function() stillCurrent,
    void Function(BridgeActivationResult result)? onResult,
  }) async {
    if (!stillCurrent()) {
      throw const BridgeActivationException(
        BridgeActivationCode.staleIdentity,
        message: 'activation identity changed before authorize',
      );
    }
    final result = await _invokeOnChannel(request);
    onResult?.call(result);
    if (!stillCurrent()) {
      throw const BridgeActivationException(
        BridgeActivationCode.staleIdentity,
        message: 'activation identity changed after authorize',
      );
    }
    if (result.isOk) {
      // A successful reply must confirm the exact identity that was asked
      // about; a mismatching generation pair describes another output.
      if (result.ownerGeneration != request.generation ||
          result.surfaceGeneration != request.surfaceGeneration) {
        throw BridgeActivationException(
          BridgeActivationCode.staleIdentity,
          message: 'reply generations (${result.ownerGeneration}/'
              '${result.surfaceGeneration}) do not match the request '
              '(${request.generation}/${request.surfaceGeneration})',
        );
      }
      return;
    }
    throw BridgeActivationException(
      result.code,
      message: result.message,
    );
  }

  Future<BridgeActivationResult> _invokeOnChannel(
    BridgeAuthorizationRequest request,
  ) async {
    if (_authorizationPending) {
      throw const BridgeActivationException(
        BridgeActivationCode.channelError,
        message: 'another bridge authorization is still pending',
      );
    }
    _authorizationPending = true;
    // The epoch counts real dispatches only: this is the single point where
    // an authorization actually reaches the platform.
    _dispatchEpoch++;
    try {
      final raw = _invokeAuthorization(request);
      // A timeout abandons this await while the platform may still reply
      // later. Consume that late completion quietly: it must never activate
      // anything and must not surface as an unhandled async error.
      unawaited(raw.then<void>((_) {}, onError: (Object _, StackTrace __) {}));
      try {
        return BridgeActivationResult.fromMap(
          await raw.timeout(authorizationTimeout),
        );
      } on TimeoutException {
        throw BridgeActivationException(
          BridgeActivationCode.timeout,
          message: 'no authorization reply within '
              '$authorizationTimeout (request $request)',
        );
      }
    } on BridgeActivationException {
      rethrow;
    } catch (error, stackTrace) {
      throw BridgeActivationException(
        BridgeActivationCode.channelError,
        error: error,
        stackTrace: stackTrace,
        message: 'authorization channel call failed (request $request)',
      );
    } finally {
      // The gate opens on success, failure or timeout alike; it never stays
      // permanently closed.
      _authorizationPending = false;
    }
  }
}

/// Review-scope anchor (C2): the complete owner identity, output intent
/// serial, activation epoch AND latest-view serial of the output a decoder
/// review describes. The session captures it before the review facts are
/// sampled and compares it before writing a `verified` report, so a review
/// of an older activation can never verify a newer output — including a
/// newer *successful* attempt with no issue at all, and a newer ViewCreated
/// that arrived while no new Surface (and thus no new intent/epoch) exists
/// yet: in that window the owner, intent and epoch are all unchanged, and
/// only [latestViewCreationSerial] distinguishes the scopes.
class BridgeActivationScopeAnchor {
  const BridgeActivationScopeAnchor({
    this.controller,
    this.owner,
    required this.activationEpoch,
    required this.outputIntentSerial,
    this.latestViewCreationSerial = 0,
  });

  /// Instance identity of the platform controller this anchor was read from.
  final Object? controller;

  /// The complete bound owner identity at capture time (null when unbound).
  final AndroidSurfaceAccountId? owner;

  final int activationEpoch;
  final int outputIntentSerial;

  /// The controller's latest created-view serial at capture time.
  final int latestViewCreationSerial;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is BridgeActivationScopeAnchor &&
      identical(other.controller, controller) &&
      other.owner == owner &&
      other.activationEpoch == activationEpoch &&
      other.outputIntentSerial == outputIntentSerial &&
      other.latestViewCreationSerial == latestViewCreationSerial;
  }

  @override
  int get hashCode =>
      Object.hash(identityHashCode(controller), owner, activationEpoch,
          outputIntentSerial, latestViewCreationSerial);

  @override
  String toString() =>
      'BridgeActivationScopeAnchor($owner, epoch=$activationEpoch, '
      'intent=$outputIntentSerial, view=$latestViewCreationSerial)';
}

/// Full scope currency for a published issue (production unit used by
/// [AndroidVideoController.isCurrentBridgeActivationIssue]): controller
/// instance identity, aliveness, the activation epoch (dispatches only), the
/// complete owner AND output intent serial, and the latest-view gate. The
/// extra owner/intent/view checks close the window where a new ViewCreated
/// arrived (or an owner was replaced) while no new channel dispatch has
/// happened yet — the epoch alone cannot detect that.
bool isBridgeActivationIssueCurrent({
  required BridgeActivationIssue issue,
  required Object? controller,
  required bool controllerActive,
  required int activationEpoch,
  required AndroidSurfaceAccountId? expectedOwner,
  required int outputIntentSerial,
  required bool ownerAllowedByLatestView,
}) {
  return identical(issue.controller, controller) &&
      controllerActive &&
      issue.activationEpoch == activationEpoch &&
      issue.owner == expectedOwner &&
      issue.outputIntentSerial == outputIntentSerial &&
      ownerAllowedByLatestView;
}

/// The latest-view publish gate (production unit used by
/// [AndroidVideoController._mayPublishPlatformSurface]): an owner may
/// publish while its view is the latest created one, or under an explicitly
/// authorized fallback serial. A ViewCreated that arrived for a newer view
/// whose Surface has not been announced yet closes this gate for the older
/// view even though the output intent has not changed.
bool mayPublishPlatformSurface({
  required int? ownerViewCreationSerial,
  required int latestViewCreationSerial,
  required bool authorizedFallbackSerial,
}) =>
    ownerViewCreationSerial == latestViewCreationSerial ||
    authorizedFallbackSerial;

/// C1 no-promotion rule as one production unit (used by
/// [AndroidVideoController._promoteCompatibleBoundFallback]): a retained
/// in-flight debt blocks promotion outright; only a still-confirmed bound,
/// compatible owner without a competing queued candidate may complete the
/// waiter. A stopped owner whose Dart identity was cleared (an activation
/// failure or a same-Surface stale discard) can never match
/// [isBoundSurfaceOwner] and is therefore never promoted.
O? decideCompatibleBoundFallback<O>({
  required bool hasInFlightOwner,
  required Iterable<O> liveOwnersInArrivalOrder,
  required bool Function(O owner) isBoundSurfaceOwner,
  required bool Function(O owner) isCompatibleWithLatestView,
  required bool Function(O owner) hasOtherQueuedCandidate,
}) {
  if (hasInFlightOwner) return null;
  for (final owner in liveOwnersInArrivalOrder) {
    if (!isBoundSurfaceOwner(owner) || !isCompatibleWithLatestView(owner)) {
      continue;
    }
    if (hasOtherQueuedCandidate(owner)) continue;
    return owner;
  }
  return null;
}

/// Whether a repeated already-bound Surface event may (re)publish the bound
/// waiter (production unit used by the bind already-bound branch): the owner
/// must still be confirmed bound with no in-flight debt — a stop-then-
/// authorize failure keeps the in-flight marker precisely so this gate stays
/// closed — with a current intent and an open latest-view gate.
bool mayRepublishAlreadyBoundOutput({
  required bool confirmedBound,
  required bool hasInFlightOwner,
  required bool intentCurrent,
  required bool mayPublishLatestView,
}) =>
    confirmedBound &&
    !hasInFlightOwner &&
    intentCurrent &&
    mayPublishLatestView;

/// Whether `waitUntilCurrentOutputBound` may resolve immediately (production
/// unit): a suspended authorization holds the in-flight debt, so the waiter
/// must not succeed midway through a hanging listener re-activation.
bool isCurrentPlatformOutputImmediatelyAvailable({
  required bool outputAvailable,
  required bool widBound,
  required bool viewIdBound,
  required bool hasInFlightOwner,
}) =>
    outputAvailable && widBound && viewIdBound && !hasInFlightOwner;

/// Whether a detach must run the strict stop before releasing the JNI
/// reference (production unit used by
/// [AndroidVideoController._detachPlatformSurface]): only the confirmed
/// bound owner or a retained in-flight debt proves mpv may still reference
/// the Surface. An abandoned listener activation whose strict stop failed
/// keeps both exactly so this returns true and detach stops first.
bool releaseRequiresStrictStop({
  required bool isBoundOutput,
  required bool isInFlightOutput,
}) =>
    isBoundOutput || isInFlightOutput;

/// What the wid listener must do for one activation tick (production unit).
enum WidListenerActivationPlan {
  /// No barrier: the plain re-apply keeps the previous semantics and makes
  /// zero channel calls. This is only ever chosen for NON-bridge routes —
  /// a bridge-route owner is never re-applied without authorization.
  plainReapply,

  /// A bridge-route owner whose activation cannot be authorized right now
  /// (it is no longer the current output intent, or another owner holds the
  /// in-flight debt): write nothing, stop nothing, change no state. A
  /// non-zero wid write without authorization would bypass the fail-closed
  /// barrier, and overwriting or bypassing the other owner's debt is
  /// forbidden.
  skip,

  /// Capture the complete owner and run the guarded stop → authorize →
  /// apply transaction, invalidating the confirmed output and taking the
  /// in-flight debt for its duration.
  guardedActivation,
}

/// Decides [WidListenerActivationPlan].
///
/// * Non-bridge routes (and identity-less / zero-wid ticks) keep the plain
///   re-apply: the barrier does not apply to them at all.
/// * A bridge route with a complete bound identity never falls back to a
///   plain re-apply: without a current-intent authorization (and with no
///   foreign in-flight debt) it is [WidListenerActivationPlan.skip].
WidListenerActivationPlan planWidListenerActivation({
  required bool bridgeActivationEnabled,
  required bool hasCompleteBoundIdentity,
  required int boundWid,
  required bool boundOwnerIsCurrentIntent,
  required bool hasForeignInFlightOwner,
}) {
  if (!bridgeActivationEnabled || !hasCompleteBoundIdentity || boundWid == 0) {
    return WidListenerActivationPlan.plainReapply;
  }
  if (!boundOwnerIsCurrentIntent || hasForeignInFlightOwner) {
    return WidListenerActivationPlan.skip;
  }
  return WidListenerActivationPlan.guardedActivation;
}

/// Cleanup decision after an abandoned wid-listener activation (production
/// unit): only a successful strict stop may drop the Dart identity and the
/// in-flight debt. A failed stop keeps both — the owner's detach must stop
/// mpv strictly before releasing the JNI reference, and it only takes that
/// stop branch while the in-flight debt is still recorded
/// ([releaseRequiresStrictStop]).
class AbandonedActivationCleanup {
  const AbandonedActivationCleanup({required this.mayDropOwnerState});

  /// Whether the confirmed bound identity and the in-flight debt may be
  /// cleared now (the strict stop succeeded).
  final bool mayDropOwnerState;
}

AbandonedActivationCleanup abandonedActivationCleanupAfterStrictStop({
  required bool strictStopSucceeded,
}) =>
    AbandonedActivationCleanup(mayDropOwnerState: strictStopSucceeded);

/// One guarded wid-listener activation (production object: the controller's
/// widListener path delegates here). It owns the real state transitions of
/// the listener transaction — availability invalidation, the ledger in-flight
/// debt, the stop → authorize → apply protocol call, the success publication
/// (B2-1) and the stale/failure debt semantics — over the same
/// [PlatformOutputAvailability] and [SurfaceOwnerLedger] objects the
/// controller uses everywhere else.
class WidListenerActivation {
  WidListenerActivation({
    required this.availability,
    required this.ledger,
    required this.isIdentityCurrent,
    required this.isIntentCurrent,
    required this.mayPublishOutput,
    required this.plainReapply,
    required this.guardedApply,
    required this.strictStop,
    required this.clearSuspendedOwner,
    required this.recordFailure,
    required this.onNotExpectedOutput,
    required this.trace,
  });

  final PlatformOutputAvailability availability;
  final SurfaceOwnerLedger<AndroidSurfaceAccountId> ledger;
  final bool Function(AndroidSurfaceAccountId owner, int outputIntentSerial)
      isIdentityCurrent;
  final bool Function(AndroidSurfaceAccountId owner, int outputIntentSerial)
      isIntentCurrent;
  final bool Function(AndroidSurfaceAccountId owner, int outputIntentSerial)
      mayPublishOutput;
  final Future<void> Function() plainReapply;
  final Future<void> Function(AndroidSurfaceAccountId owner, int outputIntentSerial)
      guardedApply;
  final Future<bool> Function() strictStop;
  final void Function(AndroidSurfaceAccountId owner) clearSuspendedOwner;
  final void Function(
    AndroidSurfaceAccountId owner,
    int outputIntentSerial,
    BridgeActivationException error,
    StackTrace stack, {
    required bool boundIdentityClearable,
  }) recordFailure;
  final void Function() onNotExpectedOutput;
  final void Function(String event) trace;

  Future<void> run({
    required WidListenerActivationPlan plan,
    required AndroidSurfaceAccountId? owner,
    required int outputIntentSerial,
  }) async {
    switch (plan) {
      case WidListenerActivationPlan.plainReapply:
        return plainReapply();
      case WidListenerActivationPlan.skip:
        // B2-2: a bridge-route owner without a current-intent authorization
        // is never written: no wid, no stop, no state change, and any other
        // owner's in-flight debt stays untouched.
        trace('listener skip wid=${owner?.wid} '
            '(bridge route without current-intent authorization)');
        return;
      case WidListenerActivationPlan.guardedActivation:
        break;
    }
    final boundOwner = owner!;
    // The re-activation suspends the confirmed output exactly like a bind:
    // invalidate the waiter and take the in-flight debt first, so a hanging
    // or failed authorization can never let `waitUntilCurrentOutputBound`
    // succeed midway, and the promotion gate stays closed for its duration.
    availability.invalidateCurrent();
    ledger.markInFlight(boundOwner);
    var applied = false;
    try {
      await guardedApply(boundOwner, outputIntentSerial);
      applied = true;
    } on BridgeActivationException catch (error, stackTrace) {
      final cleanup = await _abandon(boundOwner, error);
      if (!error.stale) {
        recordFailure(
          boundOwner,
          outputIntentSerial,
          error,
          stackTrace,
          boundIdentityClearable: cleanup.mayDropOwnerState,
        );
      }
      return;
    }
    assert(applied);
    // The seek inside the transaction is its last await: re-check the
    // identity afterwards — an owner that went stale mid-seek keeps the
    // late-stale debt semantics instead of being left as confirmed.
    if (!isIdentityCurrent(boundOwner, outputIntentSerial)) {
      await _abandon(
        boundOwner,
        const BridgeActivationException(
          BridgeActivationCode.staleIdentity,
          message: 'activation identity changed after listener seek',
          phase: BridgeActivationPhase.applied,
        ),
      );
      return;
    }
    ledger.clearInFlight();
    ledger.clearBindFailed(boundOwner);
    ledger.cancelRelease(boundOwner);
    // B2-1: mirror the bind success publication — the re-activation
    // re-confirmed the same complete identity, so availability is restored
    // and the (fresh) waiter completes under the same intent/latest-view
    // publish gate the bind path uses.
    if (isIntentCurrent(boundOwner, outputIntentSerial) &&
        mayPublishOutput(boundOwner, outputIntentSerial)) {
      availability.publishCurrentAvailable();
    } else {
      availability.markCurrentUnavailable();
      onNotExpectedOutput();
    }
  }

  /// Completes a stop interrupted after its `vo=null` ACK and clears the
  /// suspended owner state when — and only when — that stop succeeded. A
  /// failed stop keeps the confirmed identity and the in-flight debt: the
  /// owner's own detach must then stop mpv strictly before it releases the
  /// JNI reference (it takes that stop branch exactly because the in-flight
  /// debt is still recorded).
  Future<AbandonedActivationCleanup> _abandon(
    AndroidSurfaceAccountId owner,
    BridgeActivationException error,
  ) async {
    trace('authorize stale discard listener wid=${owner.wid} '
        'phase=${error.phase.name} code=${error.code.name}');
    final stopped = await strictStop();
    final cleanup = abandonedActivationCleanupAfterStrictStop(
        strictStopSucceeded: stopped);
    if (cleanup.mayDropOwnerState) {
      // mpv is fully stopped: the stopped owner must not survive as a
      // promotable confirmed identity (C1).
      ledger.clearInFlightIf(owner);
      clearSuspendedOwner(owner);
    }
    return cleanup;
  }
}

/// Method-channel invocation of `PlatformVideoView.AuthorizeBridgeActivation`
/// for production controllers.
const MethodChannel bridgeAuthorizationChannel = MethodChannel(
  'com.alexmercerind/media_kit_video',
);

Future<Object?> invokeBridgeAuthorization(BridgeAuthorizationRequest request) {
  return bridgeAuthorizationChannel.invokeMethod<Object?>(
    'PlatformVideoView.AuthorizeBridgeActivation',
    request.asChannelArguments(),
  );
}
