/// This file is a part of media_kit (https://github.com/media-kit/media-kit).
///
/// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
/// All rights reserved.
/// Use of this source code is governed by MIT license that can be found in the LICENSE file.
import 'dart:async';
import 'dart:collection';
import 'dart:ffi';

import 'package:media_kit/ffi/ffi.dart';
import 'package:media_kit/generated/libmpv/bindings.dart' as generated;
import 'package:media_kit/src/native_handle_lifecycle.dart';
import 'package:media_kit/src/native_wakeup_callback.dart';
import 'package:synchronized/synchronized.dart';

/// {@template initializer_native_callable}
/// Initializes [Pointer<generated.mpv_handle>] and forwards its events.
/// {@endtemplate}
class InitializerNativeCallable {
  static InitializerNativeCallable? _instance;

  InitializerNativeCallable._(this.mpv);

  factory InitializerNativeCallable(generated.MPV mpv) {
    _instance ??= InitializerNativeCallable._(mpv);
    return _instance!;
  }

  final generated.MPV mpv;

  Future<Pointer<generated.mpv_handle>> create(
    Future<void> Function(Pointer<generated.mpv_event>) callback, {
    Map<String, String> options = const {},
  }) async {
    final ctx = mpv.mpv_create();
    for (final entry in options.entries) {
      final name = entry.key.toNativeUtf8();
      final value = entry.value.toNativeUtf8();
      try {
        mpv.mpv_set_option_string(ctx, name.cast(), value.cast());
      } finally {
        calloc.free(name);
        calloc.free(value);
      }
    }
    mpv.mpv_initialize(ctx);

    final owner = NativeWakeupCallbackOwnership.owner;
    final session = _EventPumpSession(ctx, callback, owner);
    session.callable = WakeUpNativeCallable.listener(
      (Pointer<generated.mpv_handle> handle) => _callback(session, handle),
    );
    _sessions[ctx.address] = session;
    NativeHandleLifecycle.handleCreated(ctx.address);
    session.lifecycleRegistered = true;
    final nativeFunction = session.callable.nativeFunction;
    if (owner != null) {
      bool installed;
      try {
        installed = owner.install(
          ctx.address,
          nativeFunction.address,
          ctx.address,
        );
      } catch (error, stack) {
        // An exceptional bridge may already have installed the callback.
        // Keep the session and callable alive if removal cannot be confirmed.
        try {
          owner.remove(ctx.address);
        } catch (_) {
          Error.throwWithStackTrace(error, stack);
        }
        session.phase = _EventPumpPhase.closing;
        await _drainAndClose(session);
        mpv.mpv_terminate_destroy(ctx);
        Error.throwWithStackTrace(error, stack);
      }
      if (!installed) {
        session.phase = _EventPumpPhase.closing;
        await _drainAndClose(session);
        mpv.mpv_terminate_destroy(ctx);
        throw StateError('Native wakeup callback owner is shutting down');
      }
    } else {
      mpv.mpv_set_wakeup_callback(ctx, nativeFunction.cast(), ctx.cast());
    }
    return ctx;
  }

  /// Requests a retryable close-and-drain for an owned callback.
  Future<bool> disposeOwned(Pointer<generated.mpv_handle> ctx) async {
    final session = _sessions[ctx.address];
    if (session == null) return false;
    final owned = session.owner != null;
    if (owned) {
      await _closeSession(session);
    } else {
      await dispose(ctx);
    }
    return owned;
  }

  /// Closes an unowned callback. Owned handles must use [disposeOwned] so
  /// their native owner is cleared before admission is closed.
  Future<void> dispose(Pointer<generated.mpv_handle> ctx) async {
    final session = _sessions[ctx.address];
    if (session == null) return;
    if (session.owner != null) {
      await _closeSession(session);
      return;
    }
    mpv.mpv_set_wakeup_callback(ctx, nullptr, nullptr);
    session.phase = _EventPumpPhase.closing;
    await _drainAndClose(session);
  }

  Future<void> _closeSession(_EventPumpSession session) async {
    if (session.phase == _EventPumpPhase.closed) return;
    final existing = session.closeFuture;
    if (existing != null) return existing;
    final completion = Completer<void>();
    final future = completion.future;
    session.closeFuture = future;
    unawaited(() async {
      try {
        // A failed remove leaves admission, callable and session intact so
        // the caller can retry without destroying the handle.
        session.owner!.remove(session.handle.address);
        session.phase = _EventPumpPhase.closing;
        await _drainAndClose(session);
        completion.complete();
      } catch (error, stack) {
        completion.completeError(error, stack);
      }
    }());
    try {
      await future;
    } catch (_) {
      if (!identical(session.closeFuture, future)) rethrow;
      session.closeFuture = null;
      rethrow;
    }
  }

  Future<void> _drainAndClose(_EventPumpSession session) async {
    if (session.phase == _EventPumpPhase.closed) return;
    // Lock.synchronized queues this real barrier behind the active handler
    // and all callback invocations already admitted to this session.
    await session.serial.synchronized(() async {});
    if (!identical(_sessions[session.handle.address], session)) return;
    session.callable.close();
    _sessions.remove(session.handle.address);
    if (session.lifecycleRegistered) {
      NativeHandleLifecycle.handleDisposed(session.handle.address);
      session.lifecycleRegistered = false;
    }
    session.phase = _EventPumpPhase.closed;
  }

  void _callback(
    _EventPumpSession session,
    Pointer<generated.mpv_handle> ctx,
  ) {
    if (!_isOpen(session, ctx)) return;
    unawaited(session.serial.synchronized(() async {
      if (!_isOpen(session, ctx)) return;
      while (_isOpen(session, ctx)) {
        final event = mpv.mpv_wait_event(ctx, 0);
        if (!_isOpen(session, ctx)) return;
        if (event == nullptr ||
            event.ref.event_id == generated.mpv_event_id.MPV_EVENT_NONE) {
          return;
        }
        final ticket = _ActiveCallbackTicket(session);
        session.activeTickets++;
        try {
          await runZoned(
            () => session.callback(event),
            zoneValues: {_activeCallbackTicketKey: ticket},
          );
        } catch (error, stack) {
          print(error);
          print(stack);
        } finally {
          ticket.active = false;
          session.activeTickets--;
        }
        if (!_isOpen(session, ctx)) return;
      }
    }));
  }

  static bool isInActiveCallback(Pointer<generated.mpv_handle> ctx) {
    final ticket = Zone.current[_activeCallbackTicketKey];
    return ticket is _ActiveCallbackTicket &&
        ticket.active &&
        ticket.session.handle.address == ctx.address &&
        identical(_sessions[ctx.address], ticket.session);
  }

  bool _isOpen(_EventPumpSession session, Pointer<generated.mpv_handle> ctx) =>
      session.phase == _EventPumpPhase.open &&
      session.handle.address == ctx.address &&
      identical(_sessions[ctx.address], session);

  static final _sessions = HashMap<int, _EventPumpSession>();
}

enum _EventPumpPhase { open, closing, closed }

class _EventPumpSession {
  _EventPumpSession(this.handle, this.callback, this.owner);

  final Pointer<generated.mpv_handle> handle;
  final Future<void> Function(Pointer<generated.mpv_event>) callback;
  final NativeWakeupCallbackOwner? owner;
  final Lock serial = Lock();
  late final WakeUpNativeCallable callable;
  _EventPumpPhase phase = _EventPumpPhase.open;
  Future<void>? closeFuture;
  int activeTickets = 0;
  bool lifecycleRegistered = false;
}

class _ActiveCallbackTicket {
  _ActiveCallbackTicket(this.session);
  final _EventPumpSession session;
  bool active = true;
}

final Object _activeCallbackTicketKey = Object();

typedef WakeUpCallback = Void Function(Pointer<generated.mpv_handle>);
typedef WakeUpNativeCallable = NativeCallable<WakeUpCallback>;
