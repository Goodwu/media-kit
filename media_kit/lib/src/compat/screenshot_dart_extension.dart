import 'dart:typed_data';
import '../player/platform_player.dart';

extension PlayerBytesScreenshot on PlatformPlayer {
  Future<Uint8List?> screenshot({String? format = 'image/jpeg',
      bool synchronized = true, bool includeLibassSubtitles = false}) =>
      screenshotBytes(format: format, synchronized: synchronized,
          includeLibassSubtitles: includeLibassSubtitles);
}
