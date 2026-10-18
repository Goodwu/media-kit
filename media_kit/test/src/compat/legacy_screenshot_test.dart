import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:media_kit/media_kit_dart.dart';

class BytesPlayer extends PlatformPlayer {
  BytesPlayer() : super(configuration: const PlayerConfiguration());
  String? requestedFormat;
  bool? requestedSynchronized;
  bool? requestedSubtitles;

  @override
  Future<Uint8List?> screenshotBytes({String? format = 'image/jpeg',
      bool synchronized = true, bool includeLibassSubtitles = false}) async {
    requestedFormat = format;
    requestedSynchronized = synchronized;
    requestedSubtitles = includeLibassSubtitles;
    return Uint8List.fromList([1, 2, 3]);
  }
}

void main() {
  test('pure Dart keeps a byte alias through its explicit entry point', () async {
    final player = BytesPlayer();
    final Future<Uint8List?> pending = player.screenshot(
        format: null, synchronized: false, includeLibassSubtitles: true);
    expect(await pending, [1, 2, 3]);
    expect(player.requestedFormat, isNull);
    expect(player.requestedSynchronized, false);
    expect(player.requestedSubtitles, true);
  });
}
