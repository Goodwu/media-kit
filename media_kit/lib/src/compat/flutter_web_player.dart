import '../player/web/player/player.dart' as core;
import '../player/platform_player.dart';
import 'screenshot_flutter.dart';
export '../player/web/player/player.dart' hide WebPlayer;

class WebPlayer extends core.WebPlayer with PlayerScreenshot {
  WebPlayer({PlayerConfiguration configuration = const PlayerConfiguration()})
      : super(configuration: configuration);
  static bool get test => core.WebPlayer.test;
  static set test(bool value) => core.WebPlayer.test = value;
}
