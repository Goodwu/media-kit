/// This file is a part of media_kit (https://github.com/media-kit/media-kit).
///
/// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
/// All rights reserved.
/// Use of this source code is governed by MIT license that can be found in the LICENSE file.
import 'package:meta/meta.dart';

import 'package:media_kit/src/player/platform_player.dart';

void webEnsureInitialized({String? libmpv}) {}

class WebPlayer extends PlatformPlayer {
  WebPlayer({PlayerConfiguration configuration = const PlayerConfiguration()})
      : super(configuration: configuration);

  /// Compatibility view for media_kit_video's platform-specific controllers.
  PlatformPlayer? get platform => this;

  /// Whether the [WebPlayer] is initialized for unit-testing.
  @visibleForTesting
  static bool test = false;

  /// Raw mpv property access parity with [NativePlayer]. The web player does
  /// not expose the mpv property surface.
  Future<void> setPropertyStrict(
    String property,
    String value, {
    bool waitForInitialization = true,
  }) async {
    throw UnsupportedError(
      '[WebPlayer.setPropertyStrict] is not supported on web: the web player does not expose the mpv property surface',
    );
  }

  /// Raw mpv property access parity with [NativePlayer]. The web player does
  /// not expose the mpv property surface.
  Future<String> getProperty(
    String property, {
    bool waitForInitialization = true,
  }) async {
    throw UnsupportedError(
      '[WebPlayer.getProperty] is not supported on web: the web player does not expose the mpv property surface',
    );
  }

  /// Raw mpv command invocation parity with [NativePlayer]. The web player
  /// does not expose the mpv command surface.
  Future<void> command(
    List<String> command, {
    bool waitForInitialization = true,
  }) async {
    throw UnsupportedError(
      '[WebPlayer.command] is not supported on web: the web player does not expose the mpv command surface',
    );
  }
}
