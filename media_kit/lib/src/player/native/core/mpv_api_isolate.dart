/// This file is a part of media_kit (https://github.com/media-kit/media-kit).
///
/// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
/// All rights reserved. Use of this source code is governed by MIT license
/// that can be found in the LICENSE file.
import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';

import 'package:media_kit/ffi/ffi.dart';
import 'package:media_kit/generated/libmpv/bindings.dart' as generated;
import 'package:media_kit/src/player/native/core/native_library.dart';

/// Operation identifiers served by the mpv event-pump isolate.
abstract final class MpvApiOp {
  static const getPropertyString = 0;
  static const getPropertyInt64 = 1;
  static const setPropertyString = 2;
  static const setPropertyNodeNone = 3;
  static const hookContinue = 4;
  static const setPropertyStringListNode = 5;
  static const getPropertyStringList = 6;
}

/// Reply field indices of an API reply message.
abstract final class MpvApiReply {
  static const requestId = 0;
  static const errorCode = 1;
  static const value = 2;
}

typedef MpvMediakitGetPropertyStringsNative = Int32 Function(
  Pointer<generated.mpv_handle>,
  Pointer<Pointer<Int8>>,
  Int32,
  Pointer<generated.mpv_node>,
);
typedef MpvMediakitGetPropertyStringsDart = int Function(
  Pointer<generated.mpv_handle>,
  Pointer<Pointer<Int8>>,
  int,
  Pointer<generated.mpv_node>,
);

const bool _nativePropertyBatch = bool.fromEnvironment(
  'MEDIA_KIT_NATIVE_PROPERTY_BATCH',
  defaultValue: true,
);

/// Performs one [MpvApiOp] against [ctx] with decoded [args].
///
/// Runs on the dedicated API isolate. Native reads may wait on the playback
/// core and decoder/VO locks; keep the event pump free to drain events and
/// the root isolate free to service platform surface work.
(int, Object?) performMpvApiOp(
  generated.MPV mpvBindings,
  int op,
  Pointer<generated.mpv_handle> ctx,
  List<Object?> args, {
  MpvMediakitGetPropertyStringsDart? readPropertyStrings,
}) {
  var error = -1;
  Object? value;
  switch (op) {
    case MpvApiOp.getPropertyString:
      final name = (args[0]! as String).toNativeUtf8();
      final result = mpvBindings.mpv_get_property_string(ctx, name.cast());
      if (result != nullptr) {
        value = result.cast<Utf8>().toDartString();
        mpvBindings.mpv_free(result.cast());
      }
      calloc.free(name);
      break;
    case MpvApiOp.getPropertyStringList:
      final names = args[0]! as List<Object?>;
      final batchReader = readPropertyStrings;
      if (names.isEmpty) {
        value = <String?>[];
      } else if (batchReader != null && names.length <= 4096) {
        final allocatedNames = <Pointer<Utf8>>[];
        final nativeNames = calloc<Pointer<Int8>>(names.length);
        try {
          final result = calloc<generated.mpv_node>();
          try {
            for (var i = 0; i < names.length; i++) {
              final name = (names[i]! as String).toNativeUtf8();
              allocatedNames.add(name);
              nativeNames[i] = name.cast<Int8>();
            }
            error = batchReader(ctx, nativeNames, names.length, result);
            if (error < 0) {
              value = List<String?>.filled(names.length, null);
            } else {
              Never malformed(String message) {
                error = -1;
                throw StateError(message);
              }

              if (result.ref.format !=
                  generated.mpv_format.MPV_FORMAT_NODE_ARRAY) {
                malformed('Native property batch returned a non-array');
              }
              final list = result.ref.u.list;
              if (list == nullptr || list.ref.num != names.length) {
                malformed('Native property batch returned wrong length');
              }
              final values = <String?>[];
              for (var i = 0; i < names.length; i++) {
                final item = list.ref.values[i];
                if (item.format == generated.mpv_format.MPV_FORMAT_NONE) {
                  values.add(null);
                } else if (item.format ==
                    generated.mpv_format.MPV_FORMAT_STRING) {
                  final string = item.u.string;
                  if (string == nullptr) {
                    malformed('Native property batch returned a null string');
                  }
                  values.add(string.cast<Utf8>().toDartString());
                } else {
                  malformed(
                      'Native property batch returned an invalid node type');
                }
              }
              value = values;
            }
          } finally {
            mpvBindings.mpv_free_node_contents(result);
            calloc.free(result);
          }
        } finally {
          for (final name in allocatedNames) {
            calloc.free(name);
          }
          calloc.free(nativeNames);
        }
      } else {
        final values = <String?>[];
        for (final rawName in names) {
          final name = (rawName! as String).toNativeUtf8();
          try {
            final result =
                mpvBindings.mpv_get_property_string(ctx, name.cast());
            if (result == nullptr) {
              values.add(null);
            } else {
              try {
                values.add(result.cast<Utf8>().toDartString());
              } finally {
                mpvBindings.mpv_free(result.cast());
              }
            }
          } finally {
            calloc.free(name);
          }
        }
        value = values;
      }
      break;
    case MpvApiOp.getPropertyInt64:
      final name = (args[0]! as String).toNativeUtf8();
      final pointer = calloc<Int64>(1);
      error = mpvBindings.mpv_get_property(
        ctx,
        name.cast(),
        generated.mpv_format.MPV_FORMAT_INT64,
        pointer.cast(),
      );
      if (error >= 0) {
        value = pointer.value;
      }
      calloc.free(pointer);
      calloc.free(name);
      break;
    case MpvApiOp.setPropertyString:
      final name = (args[0]! as String).toNativeUtf8();
      final data = (args[1]! as String).toNativeUtf8();
      final pointer = calloc<Pointer<Void>>(1);
      pointer.value = Pointer.fromAddress(data.address);
      error = mpvBindings.mpv_set_property(
        ctx,
        name.cast(),
        generated.mpv_format.MPV_FORMAT_STRING,
        pointer.cast(),
      );
      calloc.free(pointer);
      calloc.free(name);
      calloc.free(data);
      break;
    case MpvApiOp.setPropertyNodeNone:
      final name = (args[0]! as String).toNativeUtf8();
      final pointer = calloc<generated.mpv_node>();
      pointer.ref.format = generated.mpv_format.MPV_FORMAT_NONE;
      error = mpvBindings.mpv_set_property(
        ctx,
        name.cast(),
        generated.mpv_format.MPV_FORMAT_NODE,
        pointer.cast(),
      );
      calloc.free(pointer);
      calloc.free(name);
      break;
    case MpvApiOp.hookContinue:
      error = mpvBindings.mpv_hook_continue(ctx, args[0]! as int);
      break;
    case MpvApiOp.setPropertyStringListNode:
      final name = (args[0]! as String).toNativeUtf8();
      final entries = args[1]! as List<Object?>;
      final value_ = calloc<generated.mpv_node>();
      value_.ref.format = generated.mpv_format.MPV_FORMAT_NODE_ARRAY;
      value_.ref.u.list = calloc<generated.mpv_node_list>();
      value_.ref.u.list.ref.num = entries.length;
      value_.ref.u.list.ref.values = calloc<generated.mpv_node>(
        entries.length,
      );
      for (int i = 0; i < entries.length; i++) {
        final entry = (entries[i]! as String).toNativeUtf8();
        value_.ref.u.list.ref.values[i].format =
            generated.mpv_format.MPV_FORMAT_STRING;
        value_.ref.u.list.ref.values[i].u.string = entry.cast();
      }
      error = mpvBindings.mpv_set_property(
        ctx,
        name.cast(),
        generated.mpv_format.MPV_FORMAT_NODE,
        value_.cast(),
      );
      for (int i = 0; i < entries.length; i++) {
        calloc.free(value_.ref.u.list.ref.values[i].u.string);
      }
      calloc.free(value_.ref.u.list.ref.values);
      calloc.free(value_.ref.u.list);
      calloc.free(value_);
      calloc.free(name);
      break;
  }
  return (error, value);
}

/// Client for issuing synchronous libmpv property & hook access from the
/// Dart root isolate without executing it there.
///
/// The Dart root isolate runs on the Android platform thread whenever the
/// engine merges threads (platform view topologies). A synchronous libmpv
/// call made there takes `mp_dispatch_lock`, which during playback startup,
/// review or output rebuild can be held while the VO pipeline waits for
/// main-thread surface work: the platform thread waits on mpv, mpv waits on
/// the platform thread, and the application deadlocks into an ANR. The
/// calls are therefore forwarded to this dedicated API isolate.
///
/// The isolate is deliberately separate from the event pump: a property
/// read blocked on `mp_dispatch_lock` (core busy) must never prevent the
/// pump from draining the event queue — a saturated client event queue
/// makes the core block on event delivery and deadlocks the whole handle.
/// libmpv's client API is documented thread-safe; exactly one thread
/// (`mpv_initializer`) owns `mpv_wait_event()`.
abstract final class MpvApiIsolate {
  static SendPort? _sendPort;
  static Future<SendPort>? _spawning;
  static final Map<int, Completer<List<Object?>>> _pending = {};

  /// Kept assigned so the port is not garbage-collected while replies may
  /// still arrive.
  // ignore: unused_field
  static RawReceivePort? _replyPort;
  static int _requestId = 0;

  static Future<SendPort> _ensure() {
    final existing = _sendPort;
    if (existing != null) {
      return Future.value(existing);
    }
    return _spawning ??= _spawn();
  }

  static Future<SendPort> _spawn() async {
    // The init port carries only the runner's SendPort; `await init.first`
    // cancels its subscription, so replies must arrive on a dedicated port
    // that stays subscribed for the lifetime of the isolate.
    final init = ReceivePort();
    final response = RawReceivePort((Object? message) {
      final data = message! as List<Object?>;
      final requestId = data[MpvApiReply.requestId]! as int;
      final pending = _pending.remove(requestId);
      if (pending != null && !pending.isCompleted) {
        pending.complete(data);
      }
    });
    final libraryPath = NativeLibrary.path;
    await Isolate.spawn(
      _mpvApiIsolateEntry,
      _MpvApiInit(libraryPath, init.sendPort, response.sendPort),
    );
    final port = await init.first as SendPort;
    _replyPort = response;
    _sendPort = port;
    _spawning = null;
    return port;
  }

  static Future<(int, Object?)> _request(
    int op,
    int ctx,
    List<Object?> args,
  ) async {
    final port = await _ensure();
    final requestId = _requestId++;
    final completer = _pending[requestId] = Completer<List<Object?>>();
    port.send([requestId, op, ctx, ...args]);
    final reply = await completer.future;
    return (
      reply[MpvApiReply.errorCode]! as int,
      reply[MpvApiReply.value],
    );
  }

  /// Reads a string property. Returns `null` when the property is
  /// unavailable (mpv returned no value).
  static Future<String?> getPropertyString(int ctx, String name) async {
    final (_, value) = await _request(MpvApiOp.getPropertyString, ctx, [name]);
    return value as String?;
  }

  /// Reads string properties sequentially in one API-isolate request. Returns
  /// `null` for each property unavailable from mpv, preserving input order.
  static Future<List<String?>> getPropertyStrings(
    int ctx,
    List<String> names,
  ) async {
    final (_, value) = await _request(
      MpvApiOp.getPropertyStringList,
      ctx,
      [names],
    );
    return (value! as List<Object?>).cast<String?>();
  }

  /// Reads an int64 property. Returns `null` when the property is
  /// unavailable.
  static Future<int?> getPropertyInt64(int ctx, String name) async {
    final (_, value) = await _request(MpvApiOp.getPropertyInt64, ctx, [name]);
    return value as int?;
  }

  /// Sets a string property. Returns the raw libmpv error code.
  static Future<int> setPropertyString(
    int ctx,
    String name,
    String value,
  ) async {
    final (error, _) = await _request(MpvApiOp.setPropertyString, ctx, [
      name,
      value,
    ]);
    return error;
  }

  /// Sets an `MPV_FORMAT_NODE` property with an `MPV_FORMAT_NONE` value.
  /// Returns the raw libmpv error code.
  static Future<int> setPropertyNodeNone(int ctx, String name) async {
    final (error, _) = await _request(MpvApiOp.setPropertyNodeNone, ctx, [
      name,
    ]);
    return error;
  }

  /// Continues an mpv hook. Throws when libmpv rejects the continuation.
  static Future<void> hookContinue(int ctx, int id) async {
    final (error, _) = await _request(MpvApiOp.hookContinue, ctx, [id]);
    if (error < 0) {
      throw StateError('mpv_hook_continue($id) failed ($error)');
    }
  }

  /// Sets an `MPV_FORMAT_NODE` property whose value is an array of
  /// `MPV_FORMAT_STRING` entries (e.g. `http-header-fields`).
  /// Returns the raw libmpv error code.
  static Future<int> setPropertyStringListNode(
    int ctx,
    String name,
    List<String> entries,
  ) async {
    final (error, _) = await _request(MpvApiOp.setPropertyStringListNode, ctx, [
      name,
      entries,
    ]);
    return error;
  }
}

class _MpvApiInit {
  final String libraryPath;

  /// Receives the runner's request SendPort during handshake.
  final SendPort reply;

  /// The runner sends every operation reply here.
  final SendPort response;

  const _MpvApiInit(this.libraryPath, this.reply, this.response);
}

void _mpvApiIsolateEntry(_MpvApiInit init) {
  final library = DynamicLibrary.open(init.libraryPath);
  final mpvBindings = generated.MPV(library);
  MpvMediakitGetPropertyStringsDart? readPropertyStrings;
  try {
    if (_nativePropertyBatch) {
      readPropertyStrings = library.lookupFunction<
          MpvMediakitGetPropertyStringsNative, MpvMediakitGetPropertyStringsDart>(
        'mpv_mediakit_get_property_strings',
      );
    }
  } on ArgumentError {
    // Upstream/system libmpv builds do not carry the media-kit fork extension.
  }
  final requests = ReceivePort();
  init.reply.send(requests.sendPort);
  final reply = init.response;
  requests.listen((Object? message) {
    final data = message! as List<Object?>;
    final requestId = data[0]! as int;
    final op = data[1]! as int;
    final ctx = Pointer<generated.mpv_handle>.fromAddress(data[2]! as int);
    final args = data.sublist(3);

    int error = -1;
    Object? value;
    try {
      (error, value) = performMpvApiOp(
        mpvBindings,
        op,
        ctx,
        args,
        readPropertyStrings: readPropertyStrings,
      );
    } catch (exception, stacktrace) {
      // A failed operation must still terminate its caller's await.
      print(exception);
      print(stacktrace);
    }
    reply.send([requestId, error, value]);
  });
}
