import 'dart:ffi';
import 'dart:io';

import 'package:flutter/foundation.dart';

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

  /// Starts the software blit loop for [surfaceId] driven by the live mpv
  /// handle at [mpvHandle]. Returns false when the bridge is unavailable.
  static bool attach(int surfaceId, int mpvHandle) {
    final lib = _library ??= _open();
    if (lib == null) return false;
    try {
      final start = lib.lookupFunction<Int32 Function(Int64, Int64),
          int Function(int, int)>('mk_sw_start');
      final code = start(surfaceId, mpvHandle);
      debugPrint('[SwRender] start surface=$surfaceId code=$code');
      return code == 0;
    } catch (error) {
      debugPrint('[SwRender] start lookup/invoke failed: $error');
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
}
