// Legacy byte-pointer entry point. The player's typed FFI stays in utf8_core.
import 'dart:ffi';
import 'utf8_core.dart' as core;
import 'allocation.dart';
export 'utf8_core.dart' show Utf8;

extension StringUtf8Pointer on String {
  Pointer<Uint8> toNativeUtf8({Allocator allocator = malloc}) =>
      core.StringUtf8Pointer(this).toNativeUtf8(allocator: allocator).cast();
}

extension Utf8Pointer on Pointer<Uint8> {
  String toDartString({int? length}) =>
      core.Utf8Pointer(cast<core.Utf8>()).toDartString(length: length);
  int get length => core.Utf8Pointer(cast<core.Utf8>()).length;
}

extension SignedUtf8Pointer on Pointer<Int8> {
  String toDartString({int? length}) =>
      core.Utf8Pointer(cast<core.Utf8>()).toDartString(length: length);
  int get length => core.Utf8Pointer(cast<core.Utf8>()).length;
}
