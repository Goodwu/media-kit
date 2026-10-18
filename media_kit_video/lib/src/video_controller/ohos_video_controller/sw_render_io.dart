import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter/foundation.dart';

// mpv render API signatures (render.h), used to resolve the symbols through
// the exact DynamicLibrary instance media_kit opened for playback.
typedef _MpvCreateC = Int32 Function(
    Pointer<Pointer<Void>>, Pointer<Void>, Pointer<Void>);
typedef _MpvFreeC = Void Function(Pointer<Void>);
typedef _MpvRenderC = Int32 Function(Pointer<Void>, Pointer<Void>);

class _MpvSymbols {
  final Pointer<Void>? create;
  final Pointer<Void>? freeFn;
  final Pointer<Void>? render;
  _MpvSymbols(this.create, this.freeFn, this.render);
}

/// FFI binding for libmediakit_sw.so: the software render bridge that blits
/// libmpv render-API-SW frames onto the Flutter texture surface. Used on the
/// OHOS emulator where the GL video outputs render black; real devices are
/// unaffected (the bridge is only attached when the caller opts in).
class SwRender {
  static DynamicLibrary? _library;

  static DynamicLibrary? _open() {
    if (Platform.operatingSystem != 'ohos') return null;
    // The CMake target name is mediakit_ohos_sw; the app-libs directory is
    // not always in the bare-name search path, so try the absolute location
    // as well.
    for (final name in [
      'libmediakit_ohos_sw.so',
      '/data/storage/el1/bundle/libs/arm64/libmediakit_ohos_sw.so',
    ]) {
      try {
        return DynamicLibrary.open(name);
      } catch (_) {}
    }
    debugPrint('[SwRender] libmediakit_ohos_sw.so could not be loaded');
    return null;
  }

  /// Resolves the mpv render API symbols through the same DynamicLibrary
  /// instance media_kit's NativeLibrary opened (`libmpv.so`, then
  /// `libmpv.so.2`). Passing them to the bridge removes any dependency on
  /// the bridge's own dlopen resolving a possibly different copy.
  static _MpvSymbols _resolveMpvSymbols() {
    for (final name in ['libmpv.so', 'libmpv.so.2']) {
      DynamicLibrary mpv;
      try {
        mpv = DynamicLibrary.open(name);
      } catch (_) {
        continue;
      }
      try {
        final create = mpv
            .lookup<NativeFunction<_MpvCreateC>>('mpv_render_context_create')
            .cast<Void>();
        final freeFn = mpv
            .lookup<NativeFunction<_MpvFreeC>>('mpv_render_context_free')
            .cast<Void>();
        final render = mpv
            .lookup<NativeFunction<_MpvRenderC>>('mpv_render_context_render')
            .cast<Void>();
        return _MpvSymbols(create, freeFn, render);
      } catch (_) {}
    }
    return _MpvSymbols(null, null, null);
  }

  /// Starts the software render loop for [surfaceId] driven by the live mpv
  /// handle at [mpvHandle]. Returns false when the bridge is unavailable.
  static bool attach(int surfaceId, int mpvHandle) {
    final lib = _library ??= _open();
    if (lib == null) return false;
    final syms = _resolveMpvSymbols();
    try {
      final startEx = lib.lookupFunction<
          Int32 Function(Int64, Int64, Pointer<Void>, Pointer<Void>,
              Pointer<Void>),
          int Function(int, int, Pointer<Void>, Pointer<Void>,
              Pointer<Void>)>('mk_sw_start_ex');
      final code = startEx(
        surfaceId,
        mpvHandle,
        syms.create ?? nullptr,
        syms.freeFn ?? nullptr,
        syms.render ?? nullptr,
      );
      debugPrint('[SwRender] start surface=$surfaceId code=$code '
          'dartSymbols=${syms.create != null}');
      return code == 0;
    } catch (error) {
      debugPrint('[SwRender] start_ex lookup/invoke failed: $error');
    }
    // Older native build without mk_sw_start_ex.
    try {
      final start = lib.lookupFunction<Int32 Function(Int64, Int64),
          int Function(int, int)>('mk_sw_start');
      final code = start(surfaceId, mpvHandle);
      debugPrint('[SwRender] legacy start surface=$surfaceId code=$code');
      return code == 0;
    } catch (error) {
      debugPrint('[SwRender] start lookup/invoke failed: $error');
      return false;
    }
  }

  /// Starts the render context without a window: the loop drains mpv frames
  /// into an internal buffer (E2 ordering — the context exists before the
  /// video chain initializes). Call [setSurface] when the XComponent reports
  /// its surface to begin submitting.
  static bool start(int mpvHandle) => attach(0, mpvHandle);

  /// Attaches or swaps the submission window; the render context survives.
  /// [width]/[height] set the producer-side buffer geometry: the engine's
  /// consumer leaves the XComponent surface at its default 3x3 and never
  /// resizes it, and external_window.h requires the producer to set the
  /// geometry before requesting buffers.
  static bool setSurface(int surfaceId, {int width = 0, int height = 0}) {
    final lib = _library;
    if (lib == null) return false;
    try {
      final set = lib.lookupFunction<
          Int32 Function(Int64, Int32, Int32),
          int Function(int, int, int)>('mk_sw_set_surface');
      return set(surfaceId, width, height) == 0;
    } catch (_) {
      return false;
    }
  }

  /// Re-applies the producer-side buffer geometry on the attached window.
  /// Called when mpv reports the real video dimensions (the attach-time
  /// widget rect is a pre-layout placeholder on this platform).
  static bool setGeometry(int width, int height) {
    final lib = _library;
    if (lib == null) return false;
    try {
      final set = lib.lookupFunction<Int32 Function(Int32, Int32),
          int Function(int, int)>('mk_sw_set_geometry');
      return set(width, height) == 0;
    } catch (_) {
      return false;
    }
  }

  static void detach() {
    final lib = _library;
    if (lib == null) return;
    try {
      lib.lookupFunction<Void Function(), void Function()>('mk_sw_stop')();
    } catch (error) {
      debugPrint('[SwRender] detach failed: $error');
    }
  }

  static int frames() {
    final lib = _library;
    if (lib == null) return 0;
    return lib.lookupFunction<Int64 Function(), int Function()>(
      'mk_sw_frames',
    )();
  }

  static int submitted() {
    final lib = _library;
    if (lib == null) return 0;
    return lib.lookupFunction<Int64 Function(), int Function()>(
      'mk_sw_submitted',
    )();
  }

  static int pixelSum() {
    final lib = _library;
    if (lib == null) return 0;
    return lib.lookupFunction<Int64 Function(), int Function()>(
      'mk_sw_pixel_sum',
    )();
  }

  /// Drains the native bridge's in-memory log tail. Empty string when
  /// nothing new was logged. This bypasses both hilog (which drops LOG_APP
  /// from this module on the emulator) and the app-files mirror (which
  /// failed silently in earlier rounds).
  static String takeLogs() {
    final lib = _library;
    if (lib == null) return '';
    try {
      final take = lib.lookupFunction<Int32 Function(), int Function()>(
        'mk_sw_log_take',
      );
      final n = take();
      if (n <= 0) return '';
      final buffer =
          lib.lookupFunction<Pointer<Uint8> Function(), Pointer<Uint8> Function()>(
        'mk_sw_log_buffer',
      )();
      return utf8.decode(buffer.asTypedList(n), allowMalformed: true);
    } catch (_) {
      return '';
    }
  }
}
