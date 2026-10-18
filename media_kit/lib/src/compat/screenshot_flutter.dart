import 'dart:ui' as ui;
import '../player/platform_player.dart';

/// Compatibility image API. Pixel ownership is independent of libmpv, and the
/// caller owns/disposes the returned ui.Image. Use screenshotBytes for bytes.
extension PlayerImageScreenshot on PlatformPlayer {
  Future<ui.Image?> screenshot({bool synchronized = true,
      bool includeLibassSubtitles = false}) async {
    final bytes = await safeScreenshot(format: 'image/png',
        synchronized: synchronized, includeLibassSubtitles: includeLibassSubtitles);
    if (bytes == null) return null;
    final codec = await ui.instantiateImageCodec(bytes);
    try {
      return (await codec.getNextFrame()).image;
    } finally {
      codec.dispose();
    }
  }
}
