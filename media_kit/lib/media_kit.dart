// Copyright © 2021 & onwards, Hitesh Kumar Saini. MIT license.
/// Flutter-facing media-kit API. Player screenshots have a stable ui.Image type.
/// Non-Flutter Dart clients use media_kit_dart.dart and screenshotBytes.
export 'media_kit_core.dart'
    hide Player, NativePlayer, WebPlayer, libmpvPlayer, webPlayer;
export 'src/player/player.dart';
export 'src/compat/flutter_native_player.dart';
export 'src/compat/flutter_web_player.dart';
export 'src/compat/flutter_legacy.dart';
