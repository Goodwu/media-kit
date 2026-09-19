import 'dart:io';

void _require(bool condition, String message) {
  if (!condition) {
    throw StateError(message);
  }
}

String _read(String path) => File(path).readAsStringSync();

void main() {
  final shared = _read('lib/src/video/platform_view_video.dart');
  final ohos = _read('lib/src/video/platform_view_video_ohos.dart');

  _require(
    shared.contains('PlatformViewsService.initSurfaceAndroidView') &&
        shared.contains('PlatformViewsService.initHybridAndroidView') &&
        shared.contains('AndroidViewSurface'),
    'the shared entry must remain analyzable with standard Flutter platform-view APIs',
  );
  _require(
    !shared.contains('OhosViewController') &&
        !shared.contains('OhosViewSurface') &&
        !shared.contains('initSurfaceOhosView') &&
        !shared.contains('initExpensiveOhosView'),
    'OHOS-only controller and factories must not leak into the shared entry',
  );
  _require(
    ohos.contains('OhosViewController') &&
        ohos.contains('OhosViewSurface') &&
        ohos.contains('initSurfaceOhosView') &&
        ohos.contains('initExpensiveOhosView'),
    'the isolated OHOS entry must retain the OHOS platform-view implementation',
  );
  _require(
    shared.contains('final bool mpvWindow;') &&
        ohos.contains('final bool mpvWindow;'),
    'both platform entries must keep the shared constructor contract',
  );
}
