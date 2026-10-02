import 'dart:ffi';
import 'dart:io';

import 'package:media_kit/ffi/ffi.dart';

/// Keep COM's MTA alive while libmpv joins its core thread and releases the
/// WASAPI device enumerator. The core thread may be the last explicit MTA
/// thread; without this lease its exit can invalidate the enumerator before
/// hotplug_uninit runs on the caller's thread.
///
/// A usage cookie does not change an existing STA and does not require Dart
/// to keep an OS thread across asynchronous work. Every successful acquire
/// is balanced before this synchronous function returns.
void withWindowsMta(void Function() action) {
  if (!Platform.isWindows) {
    action();
    return;
  }

  final ole32 = DynamicLibrary.open('ole32.dll');
  final increment = ole32.lookupFunction<Int32 Function(Pointer<Pointer<Void>>),
      int Function(Pointer<Pointer<Void>>)>(
    'CoIncrementMTAUsage',
  );
  final decrement = ole32.lookupFunction<Int32 Function(Pointer<Void>),
      int Function(Pointer<Void>)>('CoDecrementMTAUsage');
  final cookie = calloc<Pointer<Void>>();
  try {
    final result = increment(cookie);
    if (result < 0) {
      throw StateError('CoIncrementMTAUsage failed: $result');
    }
    try {
      action();
    } finally {
      decrement(cookie.value);
    }
  } finally {
    calloc.free(cookie);
  }
}
