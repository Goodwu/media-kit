import 'dart:typed_data';
import '../player/platform_player.dart';

/// Pure-Dart callers keep a byte API without importing dart:ui.
extension PlayerBytesScreenshot on PlatformPlayer {
  Future<Uint8List?> screenshot({String? format = 'image/jpeg',
      bool synchronized = true, bool includeLibassSubtitles = false}) =>
      screenshotBytes(format: format, synchronized: synchronized,
          includeLibassSubtitles: includeLibassSubtitles);
}
