import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';

Future<File> pcmFixture(Directory directory, String name) async {
  const rate = 8000;
  const dataSize = rate * 2 * 2;
  final bytes = Uint8List(44 + dataSize);
  final header = ByteData.sublistView(bytes);
  void tag(int offset, String text) => bytes.setRange(offset, offset + 4, ascii.encode(text));
  tag(0, 'RIFF'); header.setUint32(4, bytes.length - 8, Endian.little);
  tag(8, 'WAVE'); tag(12, 'fmt ');
  header.setUint32(16, 16, Endian.little);
  header.setUint16(20, 1, Endian.little); header.setUint16(22, 1, Endian.little);
  header.setUint32(24, rate, Endian.little); header.setUint32(28, rate * 2, Endian.little);
  header.setUint16(32, 2, Endian.little); header.setUint16(34, 16, Endian.little);
  tag(36, 'data'); header.setUint32(40, dataSize, Endian.little);
  return File('${directory.path}/$name').writeAsBytes(bytes);
}

void main() {
  test('ordinary open/add preserve per-entry options and restore the baseline', () async {
    MediaKit.ensureInitialized(libmpv: 'libmpv.so.2');
    NativePlayer.test = true;
    final directory = await Directory.systemTemp.createTemp('mk-options-');
    final file = await pcmFixture(directory, 'sample.wav');
    final player = await Player.create();
    final observed = <Map<String, String>>[];
    var loaded = Completer<void>();
    player.onLoadHooks.add(() async {
      observed.add({
        'cache': await player.getPropertyAsync('cache'),
        'lavfi-complex': await player.getPropertyAsync('lavfi-complex'),
      });
      if (!loaded.isCompleted) loaded.complete();
    });
    try {
      await player.setPropertyStrict('cache', 'no');
      const graph = '[aid1] anull [ao]';
      await player.open(Media(file.path, extras: {
        'cache': 'yes', 'lavfi-complex': '"$graph"',
      }), play: false);
      await loaded.future.timeout(const Duration(seconds: 10));
      expect(observed.last['cache'], 'yes');
      expect(observed.last['lavfi-complex'], graph);
      loaded = Completer<void>();
      await player.add(Media(file.path, extras: const {}));
      await player.jump(1);
      await loaded.future.timeout(const Duration(seconds: 10));
      expect(observed.last['cache'], 'no');
      expect(observed.last['lavfi-complex'], '');
      await player.stop();
      expect(await player.getPropertyAsync('cache'), 'no');
      expect(await player.getPropertyAsync('lavfi-complex'), '');
    } finally {
      await player.dispose();
      NativePlayer.test = false;
      await directory.delete(recursive: true);
    }
  }, skip: !Platform.isLinux, timeout: const Timeout(Duration(seconds: 40)));

  test('opaque EDL survives ordinary open with media options', () async {
    MediaKit.ensureInitialized(libmpv: 'libmpv.so.2');
    NativePlayer.test = true;
    final directory = await Directory.systemTemp.createTemp('mk-edl-');
    final file = await pcmFixture(directory, '声音;,=%.wav');
    final uri = 'edl://!no_chapters;%${utf8.encode(file.path).length}%${file.path}';
    final player = await Player.create();
    final loaded = Completer<void>();
    String? path;
    player.onLoadHooks.add(() async {
      path = await player.getPropertyAsync('path');
      if (!loaded.isCompleted) loaded.complete();
    });
    try {
      await player.open(Media(uri, extras: const {'cache': 'no'}), play: false);
      await loaded.future.timeout(const Duration(seconds: 10));
      expect(path, uri);
      // file loading, not just command acceptance, must also succeed.
      if (player.state.duration <= Duration.zero) {
        await player.stream.duration.firstWhere((value) => value > Duration.zero)
            .timeout(const Duration(seconds: 10));
      }
      expect(player.current.single.uri, uri);
    } finally {
      await player.dispose();
      NativePlayer.test = false;
      await directory.delete(recursive: true);
    }
  }, skip: !Platform.isLinux, timeout: const Timeout(Duration(seconds: 40)));

  test('container probe accepts one media and always opens paused', () async {
    MediaKit.ensureInitialized(libmpv: 'libmpv.so.2');
    NativePlayer.test = true;
    final directory = await Directory.systemTemp.createTemp('mk-probe-');
    final file = await pcmFixture(directory, 'probe.wav');
    final player = await Player.create();
    try {
      expect(
        () => player.openContainerProbe(Playlist([Media(file.path)])),
        throwsArgumentError,
      );
      await player.openContainerProbe(Media(file.path));
      expect(player.state.playing, isFalse);
    } finally {
      await player.dispose();
      NativePlayer.test = false;
      await directory.delete(recursive: true);
    }
  }, skip: !Platform.isLinux, timeout: const Timeout(Duration(seconds: 40)));
}
