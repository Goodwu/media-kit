import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/src/utils/darwin_wakeup_callback_owner.dart';
Future<void> main() async {
  await initializeDarwinMpvOwnerBroker();
  final configuration = PlayerConfiguration();
  // ignore: avoid_print
  print(configuration);
}
