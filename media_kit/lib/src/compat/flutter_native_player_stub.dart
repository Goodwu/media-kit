import '../player/native/player/stub.dart' as core;
import '../player/platform_player.dart';
import 'screenshot_flutter.dart';
export '../player/native/player/stub.dart' hide NativePlayer;

/// Web compile face only; the inherited native operations still reject use.
class NativePlayer extends core.NativePlayer with PlayerScreenshot {
  NativePlayer({PlayerConfiguration configuration = const PlayerConfiguration()})
      : super(configuration: configuration);
  static bool get test => core.NativePlayer.test;
  static set test(bool value) => core.NativePlayer.test = value;
}
