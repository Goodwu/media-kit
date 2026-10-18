import 'dart:typed_data';

/// Pure-Dart builds retain a byte-returning screenshot member, without dart:ui.
mixin PlayerScreenshot {
  Future<Uint8List?> screenshotBytes({
    String? format = 'image/jpeg',
    bool synchronized = true,
    bool includeLibassSubtitles = false,
  });

  Future<Uint8List?> screenshot({
    String? format = 'image/jpeg',
    bool synchronized = true,
    bool includeLibassSubtitles = false,
  }) => screenshotBytes(
    format: format,
    synchronized: synchronized,
    includeLibassSubtitles: includeLibassSubtitles,
  );
}
