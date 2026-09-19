import 'package:flutter/foundation.dart';
import 'package:media_kit_video/media_kit_video.dart';

const _autoNativeWindow =
    bool.fromEnvironment('MEDIA_KIT_AUTO_NATIVE_WINDOW', defaultValue: true);
const _autoTexture =
    bool.fromEnvironment('MEDIA_KIT_AUTO_TEXTURE', defaultValue: false);

final configuration = ValueNotifier<VideoControllerConfiguration>(
  const VideoControllerConfiguration(
    // PLEASE USE auto-safe IN PRODUCTION.
    hwdec: 'auto',
    enableHardwareAcceleration: true,
    // W1 macOS-only experiment. Keep this enabled only in the isolated host.
    useNativeWindow: !_autoTexture && _autoNativeWindow,
    useNativeSurface: !_autoTexture && !_autoNativeWindow,
  ),
);
