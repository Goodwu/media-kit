import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit/ffi/src/allocation.dart';
import 'package:media_kit/ffi/src/utf8.dart';
import 'package:media_kit/generated/libmpv/bindings.dart' as g;
import 'package:media_kit/src/player/native/core/initializer.dart';

void main() {
  test('real libmpv raw shutdown can dispose and destroy inside callback', () async {
    MediaKit.ensureInitialized(libmpv: 'libmpv.so.2');
    final api = NativePlayer.mpv;
    expect(NativePlayer.apiVersion, greaterThan(0));
    final done = Completer<void>();
    late Pointer<g.mpv_handle> handle;
    handle = await Initializer.create(api, (event) {
      if (event.ref.event_id == g.mpv_event_id.MPV_EVENT_SHUTDOWN) {
        Initializer.dispose(handle);
        api.mpv_terminate_destroy(handle);
        expect(event.ref.event_id, g.mpv_event_id.MPV_EVENT_SHUTDOWN);
        done.complete();
      }
      return null;
    }, options: {'idle': 'yes', 'vo': 'null', 'ao': 'null'});
    NativePlayer.setHeader(api, handle, userAgent: 'media-kit-test', referer: 'https://example.invalid');
    final quit = 'quit'.toNativeUtf8(allocator: calloc);
    final args = calloc<Pointer<Uint8>>(2)..[0] = quit;
    try {
      expect(api.mpv_command(handle, args), greaterThanOrEqualTo(0));
      await done.future.timeout(const Duration(seconds: 10));
      Initializer.dispose(handle);
      api.mpv_terminate_destroy(handle);
    } finally {
      calloc.free(args); calloc.free(quit);
      if (!done.isCompleted) {
        Initializer.dispose(handle);
        api.mpv_terminate_destroy(handle);
      }
    }
  }, skip: !Platform.isLinux, timeout: const Timeout(Duration(seconds: 20)));
}
