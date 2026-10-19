import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'legacy_media_options_native_test.dart' show pcmFixture;

class RequestCapture {
  RequestCapture(this.path, this.headers);
  final String path;
  final Map<String, String> headers;
}

class LocalMediaServer {
  LocalMediaServer._(this.server, this.bytes, this.assets) {
    subscription = server.listen((request) async {
      final headers = <String, String>{};
      request.headers.forEach((name, values) => headers[name] = values.join(','));
      final capture = RequestCapture(request.uri.path, headers);
      requests.add(capture);
      events.add(capture);
      final data = assets[request.uri.path] ?? bytes;
      request.response.headers.contentType = request.uri.path.endsWith('.y4m')
          ? ContentType('application', 'octet-stream') : ContentType('audio', 'wav');
      request.response.headers.set('Accept-Ranges', 'bytes');
      var start = 0;
      var end = data.length - 1;
      final range = request.headers.value('range');
      if (range != null) {
        final match = RegExp(r'^bytes=(\d+)-(\d*)$').firstMatch(range);
        if (match == null || int.parse(match.group(1)!) >= data.length) {
          request.response.statusCode = 416;
          request.response.headers.set('Content-Range', 'bytes */${data.length}');
          await request.response.close();
          return;
        }
        start = int.parse(match.group(1)!);
        if (match.group(2)!.isNotEmpty) {
          end = int.parse(match.group(2)!).clamp(start, end).toInt();
        }
        request.response.statusCode = 206;
        request.response.headers.set('Content-Range', 'bytes $start-$end/${data.length}');
      }
      request.response.contentLength = end - start + 1;
      request.response.add(data.sublist(start, end + 1));
      await request.response.close();
    });
  }
  final HttpServer server;
  final Uint8List bytes;
  final Map<String, Uint8List> assets;
  final requests = <RequestCapture>[];
  final events = StreamController<RequestCapture>.broadcast();
  late final StreamSubscription<HttpRequest> subscription;
  static Future<LocalMediaServer> start(Uint8List bytes,
      {Map<String, Uint8List> assets = const {}}) async =>
      LocalMediaServer._(await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
          bytes, assets);
  String uri(String path) => 'http://127.0.0.1:${server.port}/$path';
  Future<RequestCapture> waitFor(String value, {int after = 0}) {
    for (final entry in requests.skip(after)) {
      if (entry.headers['x-entry'] == value) return Future.value(entry);
    }
    return events.stream.firstWhere((entry) => entry.headers['x-entry'] == value)
        .timeout(const Duration(seconds: 10));
  }
  Future<void> close() async {
    await server.close(force: true);
    await subscription.cancel();
    await events.close();
  }
}

Future<void> waitLoaded(Player player) async {
  if (player.state.duration > Duration.zero) return;
  await player.stream.duration.firstWhere((value) => value > Duration.zero)
      .timeout(const Duration(seconds: 10));
}

void main() {
  test('same-URI playlist entries retain frozen HTTP headers on the wire', () async {
    MediaKit.ensureInitialized(libmpv: 'libmpv.so.2');
    NativePlayer.test = true;
    final directory = await Directory.systemTemp.createTemp('mk-header-scope-');
    final file = await pcmFixture(directory, 'sample.wav');
    final server = await LocalMediaServer.start(await file.readAsBytes());
    final player = await Player.create(configuration: const PlayerConfiguration(
        options: {'ao': 'null', 'vo': 'null'}));
    try {
      await player.setPropertyStrict('http-header-fields', 'x-baseline: keep');
      player.setMediaHeader(userAgent: 'mk-snapshot', headers: {'X-Default': 'before'});
      final headersA = {'X-Entry': 'A', 'X-Literal': 'a,b=3,vo=null', 'X-Tail': 'end\\'};
      final headersB = {'X-Entry': 'B'};
      final a = Media(server.uri('same.wav'), httpHeaders: headersA,
          extras: const {'cache': 'no'});
      // Creating the second Media updates the old URI cache. Entry A must
      // still have A's headers, not B's; this fails with the old on_load code.
      final b = Media(server.uri('same.wav'), httpHeaders: headersB,
          extras: const {'cache': 'no'});
      final opening = player.open(Playlist([a, b]), play: false);
      headersA['X-Entry'] = 'mutated-A';
      headersB['X-Entry'] = 'mutated-B';
      player.setMediaHeader(headers: {'X-Default': 'after'});
      await opening;
      final first = await server.waitFor('A');
      await waitLoaded(player);
      expect(first.headers['x-default'], 'before');
      expect(first.headers['user-agent'], 'mk-snapshot');
      expect(first.headers['x-literal'], 'a,b=3,vo=null');
      expect(first.headers['x-tail'], 'end\\');
      expect(first.headers.containsKey('x-baseline'), isFalse);
      final beforeB = server.requests.length;
      await player.jump(1);
      final second = await server.waitFor('B', after: beforeB);
      expect(second.headers['x-default'], 'before');
      expect(second.headers.containsKey('x-literal'), isFalse);
      final beforeA = server.requests.length;
      await player.jump(0);
      expect((await server.waitFor('A', after: beforeA)).headers['x-default'], 'before');
      await player.stop();
      expect(await player.getPropertyAsync('http-header-fields'), 'x-baseline: keep');
    } finally {
      await player.dispose();
      NativePlayer.test = false;
      await server.close();
      await directory.delete(recursive: true);
    }
  }, skip: !Platform.isLinux, timeout: const Timeout(Duration(seconds: 50)));

  test('add captures headers independently and invalid headers preserve playback', () async {
    MediaKit.ensureInitialized(libmpv: 'libmpv.so.2');
    NativePlayer.test = true;
    final directory = await Directory.systemTemp.createTemp('mk-header-add-');
    final file = await pcmFixture(directory, 'sample.wav');
    final server = await LocalMediaServer.start(await file.readAsBytes());
    final player = await Player.create(configuration: const PlayerConfiguration(
        options: {'ao': 'null', 'vo': 'null'}));
    try {
      await player.open(Media(file.path), play: false);
      await waitLoaded(player);
      final oldPath = await player.getPropertyAsync('path');
      expect(() => player.open(Media(server.uri('bad.wav'),
          httpHeaders: {'X-Test': 'one\r\ntwo'})), throwsArgumentError);
      expect(await player.getPropertyAsync('path'), oldPath);
      expect(server.requests, isEmpty);
      player.setMediaHeader(headers: {'X-Entry': 'added'});
      final adding = player.add(Media(server.uri('added.wav'), httpHeaders: const {}));
      player.setMediaHeader(headers: {'X-Entry': 'later'});
      await adding;
      await player.jump(1);
      expect((await server.waitFor('added')).path, '/added.wav');
      await player.stop();
    } finally {
      await player.dispose();
      NativePlayer.test = false;
      await server.close();
      await directory.delete(recursive: true);
    }
  }, skip: !Platform.isLinux, timeout: const Timeout(Duration(seconds: 40)));

  test('same-URI start/end fields are scoped and restore native baseline', () async {
    MediaKit.ensureInitialized(libmpv: 'libmpv.so.2');
    NativePlayer.test = true;
    final directory = await Directory.systemTemp.createTemp('mk-interval-scope-');
    final file = await pcmFixture(directory, 'sample.wav');
    final player = await Player.create(configuration: const PlayerConfiguration(
        options: {'ao': 'null', 'vo': 'null'}));
    var loaded = Completer<(String, String)>();
    player.onLoadHooks.add(() async {
      final start = await player.getPropertyAsync('start');
      final end = await player.getPropertyAsync('end');
      if (!loaded.isCompleted) loaded.complete((start, end));
    });
    try {
      await player.setPropertyStrict('start', '0.100');
      await player.setPropertyStrict('end', '1.900');
      final baseline = (await player.getPropertyAsync('start'),
          await player.getPropertyAsync('end'));
      await player.open(Playlist([
        Media(file.path, start: const Duration(milliseconds: 500),
            end: const Duration(milliseconds: 1500)),
        Media(file.path, start: const Duration(milliseconds: 750),
            end: const Duration(milliseconds: 1750)),
      ]), play: false);
      var observation = await loaded.future.timeout(const Duration(seconds: 10));
      expect(double.parse(observation.$1), closeTo(0.5, 0.001));
      expect(double.parse(observation.$2), closeTo(1.5, 0.001));
      loaded = Completer<(String, String)>();
      await player.jump(1);
      observation = await loaded.future.timeout(const Duration(seconds: 10));
      expect(double.parse(observation.$1), closeTo(0.75, 0.001));
      expect(double.parse(observation.$2), closeTo(1.75, 0.001));
      await player.stop();
      expect((await player.getPropertyAsync('start'),
          await player.getPropertyAsync('end')), baseline);
    } finally {
      await player.dispose();
      NativePlayer.test = false;
      await directory.delete(recursive: true);
    }
  }, skip: !Platform.isLinux, timeout: const Timeout(Duration(seconds: 40)));

  test('opaque EDL forwards the frozen headers to both video and audio', () async {
    MediaKit.ensureInitialized(libmpv: 'libmpv.so.2');
    NativePlayer.test = true;
    final directory = await Directory.systemTemp.createTemp('mk-edl-http-');
    final audio = await pcmFixture(directory, 'audio.wav');
    final video = BytesBuilder()..add(ascii.encode(
        'YUV4MPEG2 W16 H16 F2:1 Ip A1:1 C420jpeg\n'));
    for (var frame = 0; frame < 4; frame++) {
      video..add(ascii.encode('FRAME\n'))..add(Uint8List(384)..fillRange(0, 384, 128));
    }
    final server = await LocalMediaServer.start(await audio.readAsBytes(),
        assets: {'/video.y4m': video.takeBytes()});
    final player = await Player.create(configuration: const PlayerConfiguration(
        options: {'ao': 'null', 'vo': 'null'}));
    try {
      final videoUri = server.uri('video.y4m');
      final audioUri = server.uri('audio.wav');
      final edl = 'edl://!no_chapters;%${utf8.encode(videoUri).length}%$videoUri;'
          '!new_stream;!no_chapters;%${utf8.encode(audioUri).length}%$audioUri';
      await player.open(Media(edl, httpHeaders: const {'X-Entry': 'edl'},
          extras: const {'cache': 'no'}), play: false);
      await waitLoaded(player);
      expect(server.requests.map((r) => r.path), containsAll(['/video.y4m', '/audio.wav']));
      expect(server.requests.every((r) => r.headers['x-entry'] == 'edl'), isTrue);
      final count = int.parse(await player.getPropertyAsync('track-list/count'));
      final types = <String>[];
      for (var index = 0; index < count; index++) {
        types.add(await player.getPropertyAsync('track-list/$index/type'));
      }
      expect(types, containsAll(['video', 'audio']));
      expect(await player.getPropertyAsync('path'), edl);
    } finally {
      await player.dispose();
      NativePlayer.test = false;
      await server.close();
      await directory.delete(recursive: true);
    }
  }, skip: !Platform.isLinux, timeout: const Timeout(Duration(seconds: 40)));
}
