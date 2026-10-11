import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit_video/src/video_controller/ohos_video_controller/sw_render_stub.dart';

void main() {
  test('unavailable software bridge never claims a bound output', () {
    expect(SwRender.attach(10, 20), isFalse);
    expect(SwRender.start(20), isFalse);
    expect(SwRender.setSurface(10), isFalse);
    expect(SwRender.setSurface(10, width: 1920, height: 1080), isFalse);
    expect(SwRender.setGeometry(1920, 1080), isFalse);
    expect(SwRender.detach, returnsNormally);
    expect(SwRender.detach, returnsNormally);
  });

  test('unavailable software bridge never fabricates frame evidence', () {
    expect(SwRender.frames(), 0);
    expect(SwRender.submitted(), 0);
    expect(SwRender.pixelSum(), 0);
    expect(SwRender.takeLogs(), isEmpty);
  });
}
