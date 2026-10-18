import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit/src/compat/screenshot_flutter.dart';
import 'package:media_kit/ffi/src/allocation.dart';
import 'package:media_kit/ffi/src/utf8.dart';
import 'package:media_kit/generated/libmpv/bindings.dart' as g;
import 'package:media_kit/src/compat/legacy_dimensions.dart';
import 'package:media_kit/src/player/native/core/initializer.dart';
import 'package:media_kit/src/player/native/core/legacy_mpv.dart';
import 'package:media_kit_video/media_kit_video.dart';

// Compilation contracts are not proof that an unexecuted operation worked.
void oldApplicationTypes(NativePlayer player, Pointer<g.mpv_handle> encodingHandle) {
  final int width = player.state.width;
  final int height = player.state.height;
  final String volume = player.getProperty('volume');
  final Future<ui.Image?> screenshot = player.screenshot();
  final Stream<(int, int)> size = player.stream.size;
  final int apiVersion = NativePlayer.apiVersion;
  final api = NativePlayer.mpv;
  NativePlayer.setHeader(api, encodingHandle, userAgent: 'test', referer: 'test');
  player.setMediaHeader(userAgent: 'test', referer: 'test');
  final Future<Pointer<g.mpv_handle>> raw = Initializer.create(api, (_) => null);
  expect([width, height, volume, screenshot, size, apiVersion, raw], isNotEmpty);
}

class ImagePlayer extends PlatformPlayer with PlayerScreenshot {
  ImagePlayer() : super(configuration: const PlayerConfiguration());
  @override
  Future<Uint8List?> safeScreenshot({String? format = 'image/jpeg',
      bool synchronized = true, bool includeLibassSubtitles = false}) async {
    expect(format, 'image/png');
    return base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+ip1sAAAAASUVORK5CYII=');
  }
}

void main() {
  test('PiliPlus static API types compile', () {
    expect(oldApplicationTypes, isA<Function>());
  });
  test('legacy dimensions are zero while native facts stay unknown', () {
    const state = PlayerState();
    expect((state.width, state.height), (0, 0));
    expect(state.videoWidth, isNull);
    expect(state.videoHeight, isNull);
    final known = state.copyWith(width: 1920, height: 1080);
    expect((known.width, known.height), (1920, 1080));
    expect(known.copyWith().videoWidth, 1920);
    final cleared = known.copyWith(width: null, height: null);
    expect((cleared.width, cleared.height), (0, 0));
    expect(cleared.videoWidth, isNull);
  });
  test('paired size notifications coalesce and close', () async {
    final w = StreamController<int?>.broadcast(sync: true);
    final h = StreamController<int?>.broadcast(sync: true);
    final result = <(int, int)>[];
    final complete = Completer<void>();
    final sub = legacyDimensions(w.stream, h.stream).listen(result.add,
        onDone: complete.complete);
    w.add(1920); h.add(1080);
    await Future<void>.delayed(Duration.zero);
    w.add(1920); h.add(1080);
    await Future<void>.delayed(Duration.zero);
    w.add(null); h.add(null);
    await w.close(); await h.close(); await complete.future;
    expect(result, [(1920, 1080), (0, 0)]);
    await sub.cancel();
  });
  test('paired size cancellation releases both subscriptions', () async {
    var cancelled = 0;
    final w = StreamController<int?>(onCancel: () => cancelled++);
    final h = StreamController<int?>(onCancel: () => cancelled++);
    final sub = legacyDimensions(w.stream, h.stream).listen((_) {});
    await sub.cancel();
    expect(cancelled, 2);
    await w.close(); await h.close();
  });
  test('legacy Android alias retains other nested settings', () {
    const config = VideoControllerConfiguration(
      androidAttachSurfaceAfterVideoParameters: false,
      android: AndroidVideoOptions(usePlatformView: true, gpuApi: 'opengl'),
    );
    expect(config.android.attachSurfaceAfterVideoParameters, false);
    expect(config.android.usePlatformView, true);
    expect(config.copyWith(hwdec: 'mediacodec').android.gpuApi, 'opengl');
    const conflict = VideoControllerConfiguration(
      androidAttachSurfaceAfterVideoParameters: false,
      android: AndroidVideoOptions(attachSurfaceAfterVideoParameters: true),
    );
    expect(() => conflict.android, throwsArgumentError);
  });
  test('legacy pointers support unsigned, signed and non-ASCII strings', () {
    final Pointer<Uint8> p = '播放 🧪'.toNativeUtf8(allocator: calloc);
    try {
      expect(p.toDartString(), '播放 🧪');
      expect(p.cast<Int8>().toDartString(), '播放 🧪');
    } finally {
      calloc.free(p);
    }
  });
  test('event copy outlives native property storage', () {
    final source = calloc<g.mpv_event>();
    final property = calloc<g.mpv_event_property>();
    final name = 'time-pos'.toNativeUtf8(allocator: calloc);
    final data = calloc<Double>()..value = 12.5;
    source.ref.event_id = g.mpv_event_id.MPV_EVENT_PROPERTY_CHANGE;
    source.ref.data = property.cast();
    property.ref.name = name.cast();
    property.ref.format = g.mpv_format.MPV_FORMAT_DOUBLE;
    property.ref.data = data.cast();
    final copied = LegacyMpvEventCopy(source);
    calloc.free(name); calloc.free(data); calloc.free(property); calloc.free(source);
    final value = copied.pointer.ref.data.cast<g.mpv_event_property>().ref;
    expect(value.name.toDartString(), 'time-pos');
    expect(value.data.cast<Double>().value, 12.5);
    copied.dispose(); copied.dispose();
  });
  test('image screenshot returns a real caller-owned ui.Image', () async {
    final ui.Image? image = await ImagePlayer().screenshot();
    expect(image, isNotNull);
    expect((image!.width, image.height), (1, 1));
    expect(await image.toByteData(format: ui.ImageByteFormat.png), isNotNull);
    image.dispose();
  });
}
