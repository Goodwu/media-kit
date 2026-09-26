import 'package:media_kit_video/src/video_controller/android_video_controller/current_output_intent.dart';

void require(bool value, String message) {
  if (!value) throw StateError(message);
}

void main() {
  final destroyedDuringBind = CurrentOutputIntent<String>();
  final a = destroyedDuringBind.bind('A');
  require(destroyedDuringBind.destroy('A'), 'A destroy must be recognized');
  require(!destroyedDuringBind.isCurrent('A', a),
      'destroyed in-flight A must not publish availability');

  final replacedDuringBind = CurrentOutputIntent<String>();
  final old = replacedDuringBind.bind('A');
  final newest = replacedDuringBind.bind('B');
  require(!replacedDuringBind.isCurrent('A', old),
      'A must not release waiters after B is notified');
  require(
      !replacedDuringBind.destroy('A'), 'late A destroy must not invalidate B');
  require(replacedDuringBind.isCurrent('B', newest),
      'latest live B may publish availability');
  require(replacedDuringBind.destroy('B'), 'B destroy must be recognized');
  require(!replacedDuringBind.isCurrent('B', newest),
      'destroyed B must not publish availability');
}
