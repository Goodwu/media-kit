import 'package:media_kit_video/src/video_controller/ohos_video_controller/sw_render.dart';

// Compile this entry with dart compile js and dart compile wasm. It imports
// the same facade used by the cross-platform application, not the stub alone.
void main() {
  if (SwRender.attach(1, 2) ||
      SwRender.start(2) ||
      SwRender.setSurface(1, width: 16, height: 16) ||
      SwRender.setGeometry(16, 16)) {
    throw StateError('OHOS software output must be unavailable on the web');
  }
  SwRender.detach();
  if (SwRender.frames() != 0 ||
      SwRender.submitted() != 0 ||
      SwRender.pixelSum() != 0 ||
      SwRender.takeLogs().isNotEmpty) {
    throw StateError('Unavailable bridge reported native frame evidence');
  }
  print('OHOS software bridge web facade: PASS');
}
