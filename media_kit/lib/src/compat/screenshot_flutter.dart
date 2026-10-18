import 'dart:typed_data';
import 'dart:ui' as ui;

/// A real player member, also visible through restricted imports or a getter
/// declared in another library. The caller owns/disposes the returned image.
mixin PlayerScreenshot {
  Future<Uint8List?> safeScreenshot({
    String? format = 'image/jpeg',
    bool synchronized = true,
    bool includeLibassSubtitles = false,
  });

  Future<ui.Image?> screenshot({
    bool synchronized = true,
    bool includeLibassSubtitles = false,
  }) async {
    final bytes = await safeScreenshot(
      format: 'image/png',
      synchronized: synchronized,
      includeLibassSubtitles: includeLibassSubtitles,
    );
    if (bytes == null) return null;
    final codec = await ui.instantiateImageCodec(bytes);
    try {
      return (await codec.getNextFrame()).image;
    } finally {
      codec.dispose();
    }
  }
}
