import 'dart:ffi';
import 'dart:collection';
import '../player/native/player/real.dart' as core;
import '../player/native/core/legacy_mpv.dart';
import '../player/platform_player.dart';
import '../../generated/libmpv/bindings.dart' as generated;
import 'screenshot_flutter.dart';

export '../player/native/player/real.dart' hide NativePlayer;

/// Flutter public type. All playback state, native handles and ownership stay
/// in the existing core implementation; only the screenshot type is specialized.
class NativePlayer extends core.NativePlayer with PlayerScreenshot {
  NativePlayer({PlayerConfiguration configuration = const PlayerConfiguration()})
      : super(configuration: configuration);

  static Future<NativePlayer> create({
    PlayerConfiguration configuration = const PlayerConfiguration(),
  }) async {
    final player = NativePlayer(configuration: configuration);
    await player.future;
    return player;
  }

  static LegacyMpv get mpv => core.NativePlayer.mpv;
  static int get apiVersion => core.NativePlayer.apiVersion;
  static void setHeader(LegacyMpv api, Pointer<generated.mpv_handle> handle,
          {String? userAgent, String? referer}) =>
      core.NativePlayer.setHeader(api, handle,
          userAgent: userAgent, referer: referer);
  static bool get test => core.NativePlayer.test;
  static set test(bool value) => core.NativePlayer.test = value;
  static HashMap<String, double> get audioBitrateCache =>
      core.NativePlayer.audioBitrateCache;
}
