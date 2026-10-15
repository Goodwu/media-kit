/// This file is a part of media_kit (https://github.com/media-kit/media-kit).
///
/// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
/// All rights reserved.
/// Use of this source code is governed by MIT license that can be found in the LICENSE file.
import 'dart:ffi';

import 'hdr_yuv_window_arm.dart';

/// Resolves the vendor native exports once per call. `DynamicLibrary.open`
/// returns the same handle for a library the process already loaded (the
/// vendor plugin's Java side loads it); the spec'd
/// `libmedia_kit_android_dataspace_vendor.so` name is tried first and the
/// plugin's actual soname (`libmedia_kit_dataspace_vendor.so`,
/// `System.loadLibrary("media_kit_dataspace_vendor")`) second. Any failure
/// resolves to null bindings — the YUV attempt then fails explicitly at arm
/// time instead of throwing from the resolver.
HdrYuvWindowFfiBindings? resolveHdrYuvWindowFfiBindings() {
  for (final name in const <String>[
    'libmedia_kit_android_dataspace_vendor.so',
    'libmedia_kit_dataspace_vendor.so',
  ]) {
    try {
      final library = DynamicLibrary.open(name);
      return HdrYuvWindowFfiBindings(
        setDiagDataSpace:
            library.lookupFunction<Void Function(Int32), void Function(int)>(
                'mkvendor_set_diag_dataspace'),
        setYuvDiagEnabled:
            library.lookupFunction<Void Function(Int32), void Function(int)>(
                'mkvendor_set_yuv_diag_enabled'),
        disarmYuvDiag: library.lookupFunction<Void Function(), void Function()>(
            'mkvendor_disarm_yuv_diag'),
      );
    } catch (_) {
      // Try the next soname; the caller fails closed on null bindings.
    }
  }
  return null;
}
