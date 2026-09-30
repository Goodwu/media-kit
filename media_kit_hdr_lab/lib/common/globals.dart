import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:media_kit_video/media_kit_video.dart';

const _autoNativeWindow =
    bool.fromEnvironment('MEDIA_KIT_AUTO_NATIVE_WINDOW', defaultValue: true);
const _autoTexture =
    bool.fromEnvironment('MEDIA_KIT_AUTO_TEXTURE', defaultValue: false);
const _androidPlatformView = bool.fromEnvironment(
  'MEDIA_KIT_ANDROID_PLATFORM_VIEW',
  defaultValue: false,
);
const _androidVo = String.fromEnvironment('MEDIA_KIT_ANDROID_VO');
const _androidHdrTransaction = bool.fromEnvironment(
  'MEDIA_KIT_ANDROID_HDR_TRANSACTION',
);
const _androidHwdec = String.fromEnvironment('MEDIA_KIT_ANDROID_HWDEC');
const _androidSurfaceProducer = bool.fromEnvironment(
  'MEDIA_KIT_ANDROID_SURFACE_PRODUCER',
  defaultValue: true,
);
const _androidTextureLayoutSize = bool.fromEnvironment(
  'MEDIA_KIT_ANDROID_TEXTURE_LAYOUT_SIZE',
);
const _androidGpuSdrTenBitProbe = bool.fromEnvironment(
  'MEDIA_KIT_ANDROID_GPU_SDR_10BIT_PROBE',
);

final configuration = ValueNotifier<VideoControllerConfiguration>(
  VideoControllerConfiguration(
    // PLEASE USE auto-safe IN PRODUCTION.
    hwdec: Platform.isAndroid && _androidHwdec.isNotEmpty
        ? _androidHwdec
        : 'auto',
    enableHardwareAcceleration: true,
    // W1 macOS-only experiment. Keep this enabled only in the isolated host.
    vo: Platform.isAndroid && _androidVo.isNotEmpty ? _androidVo : null,
    darwin: DarwinVideoOptions(
      useNativeWindow: !_autoTexture && _autoNativeWindow,
      useNativeSurface: !_autoTexture && !_autoNativeWindow,
    ),
    // Explicit comparison input for Android test builds; it is not a library
    // HDR-capability declaration.
    android: AndroidVideoOptions(
      usePlatformView: Platform.isAndroid && _androidPlatformView,
      enableSurfaceProducer: _androidSurfaceProducer,
      matchTextureOutputToLayout:
          Platform.isAndroid && _androidTextureLayoutSize,
      gpuApi: Platform.isAndroid &&
              _androidHdrTransaction &&
              _androidVo == 'gpu-next'
          ? 'opengl'
          : null,
      surfacePixelFormat: Platform.isAndroid &&
              _androidPlatformView &&
              _androidGpuSdrTenBitProbe
          ? 'rgba1010102'
          : null,
    ),
  ),
);
