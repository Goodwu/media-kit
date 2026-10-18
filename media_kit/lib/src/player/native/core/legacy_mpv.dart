// ignore_for_file: non_constant_identifier_names
import 'dart:async';
import 'dart:ffi';

import 'package:media_kit/ffi/ffi.dart';
import 'package:media_kit/generated/libmpv/bindings.dart' as g;
import 'package:media_kit/src/player/native/core/native_library.dart';

/// An owned event. Unlike mpv_wait_event's borrowed buffer, this remains valid
/// if a callback stops/destroys its native handle. The callback must not retain
/// the pointer after its returned Future completes.
class LegacyMpvEventCopy {
  final List<Pointer<Void>> _allocations = [];
  late final Pointer<g.mpv_event> pointer;
  bool _disposed = false;

  LegacyMpvEventCopy(Pointer<g.mpv_event> source) {
    try {
      pointer = _copy(source, sizeOf<g.mpv_event>());
      final data = source.ref.data;
      if (data == nullptr) return;
      switch (source.ref.event_id) {
        case g.mpv_event_id.MPV_EVENT_LOG_MESSAGE:
          final from = data.cast<g.mpv_event_log_message>();
          final to = _copy(from, sizeOf<g.mpv_event_log_message>());
          to.ref.prefix = _string(from.ref.prefix);
          to.ref.level = _string(from.ref.level);
          to.ref.text = _string(from.ref.text);
          pointer.ref.data = to.cast();
          break;
        case g.mpv_event_id.MPV_EVENT_PROPERTY_CHANGE:
        case g.mpv_event_id.MPV_EVENT_GET_PROPERTY_REPLY:
          final from = data.cast<g.mpv_event_property>();
          final to = _copy(from, sizeOf<g.mpv_event_property>());
          to.ref.name = _string(from.ref.name);
          to.ref.data = _value(from.ref.format, from.ref.data);
          pointer.ref.data = to.cast();
          break;
        case g.mpv_event_id.MPV_EVENT_START_FILE:
          pointer.ref.data = _copy(data, sizeOf<g.mpv_event_start_file>());
          break;
        case g.mpv_event_id.MPV_EVENT_END_FILE:
          pointer.ref.data = _copy(data, sizeOf<g.mpv_event_end_file>());
          break;
        case g.mpv_event_id.MPV_EVENT_CLIENT_MESSAGE:
          final from = data.cast<g.mpv_event_client_message>();
          final to = _copy(from, sizeOf<g.mpv_event_client_message>());
          final count = from.ref.num_args;
          _checkCount(count);
          final argv = _bytes(sizeOf<Pointer<Int8>>() * count).cast<Pointer<Int8>>();
          for (var i = 0; i < count; i++) {
            argv[i] = _string(from.ref.args[i]);
          }
          to.ref.args = argv;
          pointer.ref.data = to.cast();
          break;
        case g.mpv_event_id.MPV_EVENT_HOOK:
          final from = data.cast<g.mpv_event_hook>();
          final to = _copy(from, sizeOf<g.mpv_event_hook>());
          to.ref.name = _string(from.ref.name);
          pointer.ref.data = to.cast();
          break;
        default:
          throw UnsupportedError('Unowned legacy event payload: ${source.ref.event_id}');
      }
    } catch (_) {
      dispose();
      rethrow;
    }
  }

  Pointer<Uint8> _bytes(int size) {
    final result = calloc<Uint8>(size == 0 ? 1 : size);
    _allocations.add(result.cast());
    return result;
  }

  Pointer<T> _copy<T extends NativeType>(Pointer<T> from, int size) {
    final to = _bytes(size);
    to.asTypedList(size).setAll(0, from.cast<Uint8>().asTypedList(size));
    return to.cast();
  }

  Pointer<Int8> _string(Pointer<Int8> from) {
    if (from == nullptr) return nullptr;
    var length = 0;
    while (from[length] != 0) {
      if (++length > 1024 * 1024) throw StateError('Oversized mpv event string');
    }
    return _copy(from, length + 1);
  }

  void _checkCount(int count) {
    if (count < 0 || count > 65536) throw StateError('Invalid mpv event element count');
  }

  Pointer<Void> _value(int format, Pointer<Void> data) {
    if (data == nullptr || format == g.mpv_format.MPV_FORMAT_NONE) return nullptr;
    switch (format) {
      case g.mpv_format.MPV_FORMAT_FLAG:
        return _copy(data, sizeOf<Int32>());
      case g.mpv_format.MPV_FORMAT_INT64:
        return _copy(data, sizeOf<Int64>());
      case g.mpv_format.MPV_FORMAT_DOUBLE:
        return _copy(data, sizeOf<Double>());
      case g.mpv_format.MPV_FORMAT_STRING:
      case g.mpv_format.MPV_FORMAT_OSD_STRING:
        final to = _bytes(sizeOf<Pointer<Int8>>()).cast<Pointer<Int8>>();
        to.value = _string(data.cast<Pointer<Int8>>().value);
        return to.cast();
      case g.mpv_format.MPV_FORMAT_NODE:
        return _node(data.cast<g.mpv_node>(), 0).cast();
      default:
        throw UnsupportedError('Unowned legacy property format: $format');
    }
  }

  Pointer<g.mpv_node> _node(Pointer<g.mpv_node> from, int depth) {
    if (depth > 32) throw StateError('Excessively nested mpv event node');
    final to = _copy(from, sizeOf<g.mpv_node>());
    switch (from.ref.format) {
      case g.mpv_format.MPV_FORMAT_STRING:
        to.ref.u.string = _string(from.ref.u.string);
        break;
      case g.mpv_format.MPV_FORMAT_NODE_ARRAY:
      case g.mpv_format.MPV_FORMAT_NODE_MAP:
        final list = from.ref.u.list;
        final count = list.ref.num;
        _checkCount(count);
        final copy = _copy(list, sizeOf<g.mpv_node_list>());
        copy.ref.values = _bytes(sizeOf<g.mpv_node>() * count).cast();
        final isMap = from.ref.format == g.mpv_format.MPV_FORMAT_NODE_MAP;
        if (isMap) copy.ref.keys = _bytes(sizeOf<Pointer<Int8>>() * count).cast();
        for (var i = 0; i < count; i++) {
          final value = _node(list.ref.values + i, depth + 1);
          (copy.ref.values + i).cast<Uint8>().asTypedList(sizeOf<g.mpv_node>())
              .setAll(0, value.cast<Uint8>().asTypedList(sizeOf<g.mpv_node>()));
          if (isMap) copy.ref.keys[i] = _string(list.ref.keys[i]);
        }
        to.ref.u.list = copy;
        break;
      case g.mpv_format.MPV_FORMAT_NONE:
      case g.mpv_format.MPV_FORMAT_FLAG:
      case g.mpv_format.MPV_FORMAT_INT64:
      case g.mpv_format.MPV_FORMAT_DOUBLE:
        break;
      default:
        throw UnsupportedError('Unowned legacy node format: ${from.ref.format}');
    }
    return to;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final allocation in _allocations.reversed) {
      calloc.free(allocation);
    }
    _allocations.clear();
  }
}

/// Legacy byte-pointer ABI facade for independently owned encoding handles.
/// Playback handles continue to use the existing asynchronous PlayerInitializer.
/// No client event thread or NativeCallable accesses these encoding handles:
/// each nonblocking wait and its callback run on the owning Dart isolate.
class LegacyMpv {
  LegacyMpv._() : _api = g.MPV(DynamicLibrary.open(NativeLibrary.path));
  static final LegacyMpv instance = LegacyMpv._();
  final g.MPV _api;
  final Map<int, _LegacyPump> _owners = {};
  final Set<int> _destroyed = {};

  int get apiVersion => _api.mpv_client_api_version();

  _LegacyPump _owner(Pointer<g.mpv_handle> ctx) {
    final owner = _owners[ctx.address];
    if (owner == null || owner.stopped) throw StateError('Legacy mpv handle is closed');
    return owner;
  }

  void _checked(int code) {
    if (code < 0) {
      throw StateError(_api.mpv_error_string(code).cast<Utf8>().toDartString());
    }
  }

  int mpv_request_event(Pointer<g.mpv_handle> ctx, int event, int enable) {
    _owner(ctx);
    return _api.mpv_request_event(ctx, event, enable);
  }

  int mpv_request_log_messages(Pointer<g.mpv_handle> ctx, Pointer<Uint8> level) {
    _owner(ctx);
    return _api.mpv_request_log_messages(ctx, level.cast());
  }

  int mpv_observe_property(Pointer<g.mpv_handle> ctx, int reply,
      Pointer<Uint8> name, int format) {
    _owner(ctx);
    return _api.mpv_observe_property(ctx, reply, name.cast(), format);
  }

  int mpv_command(Pointer<g.mpv_handle> ctx, Pointer<Pointer<Uint8>> args) {
    _owner(ctx);
    return _api.mpv_command(ctx, args.cast());
  }

  void setHeader(Pointer<g.mpv_handle> ctx, {String? userAgent, String? referer}) {
    _owner(ctx);
    for (final entry in {'user-agent': userAgent, 'referrer': referer}.entries) {
      final value = entry.value;
      if (value == null) continue;
      if (value.contains(RegExp(r'[\r\n\x00]'))) throw ArgumentError('Invalid HTTP header');
      final key = entry.key.toNativeUtf8();
      final text = value.toNativeUtf8();
      try {
        _checked(_api.mpv_set_property_string(ctx, key.cast(), text.cast()));
      } finally {
        calloc.free(key);
        calloc.free(text);
      }
    }
  }

  /// Idempotent only for handles created by this facade. The event pump is
  /// stopped synchronously before libmpv frees the handle. In-flight callbacks
  /// read owned event memory and cannot issue new operations on a closed handle.
  void mpv_terminate_destroy(Pointer<g.mpv_handle> ctx) {
    final owner = _owners.remove(ctx.address);
    if (owner == null) {
      if (_destroyed.contains(ctx.address)) return;
      throw StateError('Cannot destroy a foreign mpv handle');
    }
    owner.stop();
    _destroyed.add(ctx.address);
    _api.mpv_terminate_destroy(ctx);
  }
}

/// Static legacy entry points, deliberately separate from PlayerInitializer.
class Initializer {
  static Future<Pointer<g.mpv_handle>> create(
    LegacyMpv mpv,
    Future<void>? Function(Pointer<g.mpv_event>) callback, {
    Map<String, String> options = const {},
  }) async {
    final ctx = mpv._api.mpv_create();
    if (ctx == nullptr) throw StateError('mpv_create failed');
    try {
      for (final entry in {'config': 'no', 'terminal': 'no', ...options}.entries) {
        if (entry.key.contains('\x00') || entry.value.contains('\x00')) {
          throw ArgumentError('NUL in mpv option');
        }
        final name = entry.key.toNativeUtf8();
        final value = entry.value.toNativeUtf8();
        try {
          mpv._checked(mpv._api.mpv_set_option_string(ctx, name.cast(), value.cast()));
        } finally {
          calloc.free(name);
          calloc.free(value);
        }
      }
      mpv._checked(mpv._api.mpv_initialize(ctx));
      mpv._destroyed.remove(ctx.address);
      final pump = _LegacyPump(mpv, ctx, callback);
      mpv._owners[ctx.address] = pump;
      pump.start();
      return ctx;
    } catch (_) {
      mpv._api.mpv_terminate_destroy(ctx);
      rethrow;
    }
  }

  static void dispose(Pointer<g.mpv_handle> ctx) {
    final mpv = LegacyMpv.instance;
    final owner = mpv._owners[ctx.address];
    if (owner != null) {
      owner.stop();
    } else if (!mpv._destroyed.contains(ctx.address)) {
      throw StateError('Cannot dispose a foreign mpv handle');
    }
  }
}

class _LegacyPump {
  _LegacyPump(this.mpv, this.ctx, this.callback);
  final LegacyMpv mpv;
  final Pointer<g.mpv_handle> ctx;
  final Future<void>? Function(Pointer<g.mpv_event>) callback;
  Timer? _timer;
  bool stopped = false;
  bool _draining = false;

  void start() {
    _timer = Timer.periodic(const Duration(milliseconds: 8), (_) {
      if (!stopped && !_draining) unawaited(_drain());
    });
  }

  void stop() {
    stopped = true;
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _drain() async {
    _draining = true;
    try {
      for (var count = 0; count < 32 && !stopped; count++) {
        final borrowed = mpv._api.mpv_wait_event(ctx, 0);
        if (borrowed.ref.event_id == g.mpv_event_id.MPV_EVENT_NONE) break;
        final event = LegacyMpvEventCopy(borrowed);
        try {
          await callback(event.pointer);
        } finally {
          event.dispose();
        }
        // Do not read borrowed or ctx here: the callback may have destroyed it.
      }
    } catch (error, stack) {
      if (!stopped) {
        await _fail(error, stack);
      } else {
        Zone.current.handleUncaughtError(error, stack);
      }
    } finally {
      _draining = false;
    }
  }

  Future<void> _fail(Object error, StackTrace stack) async {
    stop();
    // The old export callback owns its completion Future. Deliver an explicit
    // error and terminal event so a pump failure cannot leave conversion hung.
    final event = calloc<g.mpv_event>();
    final log = calloc<g.mpv_event_log_message>();
    final prefix = 'media_kit'.toNativeUtf8();
    final level = 'error'.toNativeUtf8();
    final message = 'Legacy event pump failed: $error'.toNativeUtf8();
    try {
      log.ref.prefix = prefix.cast();
      log.ref.level = level.cast();
      log.ref.text = message.cast();
      event.ref.event_id = g.mpv_event_id.MPV_EVENT_LOG_MESSAGE;
      event.ref.error = -1;
      event.ref.data = log.cast();
      await callback(event);
      if (mpv._owners.containsKey(ctx.address)) {
        event.ref.event_id = g.mpv_event_id.MPV_EVENT_SHUTDOWN;
        event.ref.data = nullptr;
        await callback(event);
      }
    } catch (callbackError, callbackStack) {
      Zone.current.handleUncaughtError(callbackError, callbackStack);
    } finally {
      calloc.free(prefix);
      calloc.free(level);
      calloc.free(message);
      calloc.free(log);
      calloc.free(event);
      if (mpv._owners.containsKey(ctx.address)) mpv.mpv_terminate_destroy(ctx);
    }
  }
}
