import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit_video/src/video_controller/android_video_controller/real.dart';
import 'package:media_kit_video/src/video_controller/platform_video_controller.dart';

void _expectSize(Size actual, Size expected, String description) {
  if (actual != expected) {
    throw StateError('$description: expected $expected, got $actual');
  }
}

void main() {
  test('Android Texture layout sizing', () {
    const source = Size(3840, 2160);
    const configuration = VideoControllerConfiguration();
    if (configuration.matchAndroidTextureOutputToLayout ||
        !configuration
            .copyWith(matchAndroidTextureOutputToLayout: true)
            .matchAndroidTextureOutputToLayout) {
      throw StateError('Layout sizing must be opt-in and copyable.');
    }
    _expectSize(
      calculateAndroidTextureOutputSize(
          source, const Size(1440, 810), BoxFit.contain),
      const Size(1440, 810),
      'contain physical viewport',
    );
    _expectSize(
      calculateAndroidTextureOutputSize(
          source, const Size(1440, 1440), BoxFit.cover),
      const Size(2560, 1440),
      'cover retains cropped pixels',
    );
    _expectSize(
      calculateAndroidTextureOutputSize(
          source, const Size(7680, 4320), BoxFit.contain),
      source,
      'contain cannot upscale',
    );
    _expectSize(
      calculateAndroidTextureOutputSize(
          source, const Size(7680, 4320), BoxFit.fill),
      source,
      'fill cannot upscale',
    );
    _expectSize(
      calculateAndroidTextureOutputSize(
          source, const Size(1000, 1000), BoxFit.fill),
      const Size(1000, 1000),
      'fill changes aspect',
    );
    _expectSize(
      calculateAndroidTextureOutputSize(
          source, const Size(1000, 1000), BoxFit.none),
      source,
      'none retains source size',
    );
  });

  test('thumbnail updates cannot shrink a fullscreen owner', () {
    const source = Size(3840, 2160);
    const fullscreen = TextureOutputLayout(Size(1440, 810), BoxFit.contain);
    const thumbnail = TextureOutputLayout(Size(320, 180), BoxFit.contain);
    _expectSize(
      calculateAndroidTextureOutputSizeForLayouts(
          source, const [fullscreen, thumbnail]),
      const Size(1440, 810),
      'large owner first',
    );
    _expectSize(
      calculateAndroidTextureOutputSizeForLayouts(
          source, const [thumbnail, fullscreen]),
      const Size(1440, 810),
      'large owner last',
    );
    _expectSize(
      calculateAndroidTextureOutputSizeForLayouts(source, const [thumbnail]),
      const Size(320, 180),
      'large owner removed',
    );
    _expectSize(
      calculateAndroidTextureOutputSizeForLayouts(
        source,
        const [
          fullscreen,
          TextureOutputLayout(Size(1440, 1440), BoxFit.cover),
        ],
      ),
      const Size(2560, 1440),
      'cover demand exceeds contain demand',
    );
  });

  test('separate VideoController wrappers share layout demand', () {
    const source = Size(3840, 2160);
    final fullscreenController = Object();
    final thumbnailController = Object();
    final owners = TextureOutputLayoutRegistry();
    const fullscreen = TextureOutputLayout(Size(1440, 810), BoxFit.contain);
    const thumbnail = TextureOutputLayout(Size(320, 180), BoxFit.contain);
    owners.update(fullscreenController, [fullscreen]);
    owners.update(thumbnailController, [thumbnail]);
    _expectSize(
        calculateAndroidTextureOutputSizeForLayouts(source, owners.layouts),
        const Size(1440, 810),
        'thumbnail wrapper cannot shrink fullscreen');
    owners.update(fullscreenController, const []);
    _expectSize(
        calculateAndroidTextureOutputSizeForLayouts(source, owners.layouts),
        const Size(320, 180),
        'unmounted fullscreen wrapper is removed');
  });
}
