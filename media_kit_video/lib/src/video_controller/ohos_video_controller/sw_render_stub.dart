/// Unavailable OHOS software renderer on targets without dart:io/FFI.
///
/// Match the native bridge's unavailable behavior: never claim an attached
/// output, render progress, or logs. No native resources are created.
class SwRender {
  static bool attach(int surfaceId, int mpvHandle) => false;
  static bool start(int mpvHandle) => false;
  static bool setSurface(int surfaceId, {int width = 0, int height = 0}) => false;
  static bool setGeometry(int width, int height) => false;
  static void detach() {}
  static int frames() => 0;
  static int submitted() => 0;
  static int pixelSum() => 0;
  static String takeLogs() => '';
}
