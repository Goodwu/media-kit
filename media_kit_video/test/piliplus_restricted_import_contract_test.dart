import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
// Mirrors the API boundary of a widget that only imports a controller getter.
// Deliberately do NOT import screenshot extensions.
import 'package:media_kit/media_kit.dart' show NativePlayer;

Future<ui.Image?> screenshotThroughRestrictedImport(NativePlayer player) =>
    player.screenshot();

void headersThroughRestrictedImport(NativePlayer player) {
  player.setMediaHeader(userAgent: 'PiliPlus', headers: {'Referer': 'test'});
  player.setMediaHeader(headers: {});
}

void main() {
  test('screenshot and headers are members visible through restricted imports', () {
    expect(screenshotThroughRestrictedImport, isA<Function>());
    expect(headersThroughRestrictedImport, isA<Function>());
  });
}
