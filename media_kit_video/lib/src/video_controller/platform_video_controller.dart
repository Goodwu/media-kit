/// This file is a part of media_kit (https://github.com/media-kit/media-kit).
///
/// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
/// All rights reserved.
/// Use of this source code is governed by MIT license that can be found in the LICENSE file.
import 'dart:async';

import 'package:flutter/widgets.dart';

import 'package:media_kit/media_kit.dart';

import 'package:media_kit_video/src/video_controller/video_controller.dart';

/// Rendering topology selected for a video output.
enum VideoOutputSurfaceKind { texture, nativeSurface }

/// {@template platform_video_controller}
///
/// PlatformVideoController
/// -----------------------
///
/// This class provides the interface for platform specific [VideoController] implementations.
/// The platform specific implementations are expected to implement the methods accordingly.
///
/// The subclasses are then used in composition with the [VideoController] class, based on the platform the application is running on.
///
/// {@endtemplate}
abstract class PlatformVideoController {
  /// The [Player] instance associated with this instance.
  final Player player;

  /// User defined configuration for [VideoController].
  final VideoControllerConfiguration configuration;

  /// Texture ID of the video output, registered with Flutter engine by the native implementation.
  final ValueNotifier<int?> id = ValueNotifier<int?>(null);

  /// [Rect] of the video output, received from the native implementation.
  final ValueNotifier<Rect?> rect = ValueNotifier<Rect?>(null);

  /// Stable player handle used by native platform surfaces.
  int? nativeHandle;

  /// Increments whenever a native output topology is rebuilt.
  int nativeSurfaceGeneration = 0;

  /// True only after the native surface and player output are both verified.
  bool nativeSurfaceActive = false;
  /// Candidate surface is mounted before HDR promotion so SDR and HDR keep topology.
  bool nativeSurfaceCandidate = false;

  /// {@macro platform_video_controller}
  PlatformVideoController(this.player, this.configuration);

  /// Sets the required size of the video output.
  /// This may yield substantial performance improvements if a small [width] & [height] is specified.
  ///
  /// Remember:
  /// * “Premature optimization is the root of all evil”
  /// * “With great power comes great responsibility”
  Future<void> setSize({int? width, int? height});

  /// Creates/configures the optional native output. Implementations must fail closed.
  Future<dynamic> createNativeOutput(
          {String? surfaceId, int? windowHandle}) async =>
      const <String, dynamic>{
        'capable': false,
        'active': false,
        'failureReason': 'unsupported platform',
      };

  Future<dynamic> configureHdrOutput(dynamic configuration) async =>
      const <String, dynamic>{
        'capable': false,
        'active': false,
        'failureReason': 'unsupported platform',
      };

  Future<Map<String, dynamic>> resetHdrOutput() async =>
      const <String, dynamic>{
        'capable': false,
        'active': false,
        'failureReason': 'unsupported platform',
      };

  Future<void> disposeNativeOutput() async {}

  /// A [Future] that completes when the first video frame has been rendered.
  Future<void> get waitUntilFirstFrameRendered =>
      waitUntilFirstFrameRenderedCompleter.future;

  /// [Completer] used to signal the decoding & rendering of the first video frame.
  /// Use [waitUntilFirstFrameRendered] to wait for the first frame to be rendered.
  @protected
  final waitUntilFirstFrameRenderedCompleter = Completer<void>();

  void dispose() {
    id.dispose();
    rect.dispose();
  }

  /// Releases this controller before creating another output for the same
  /// player. Platform implementations with per-player controller caches must
  /// remove the cached entry as part of this operation.
  Future<void> disposeForRebuild() async {
    dispose();
  }
}

/// {@template video_controller_configuration}
///
/// VideoControllerConfiguration
/// ----------------------------
/// Configurable options for customizing the [VideoController] behavior.
///
/// {@endtemplate}
class VideoControllerConfiguration {
  /// Selects the Darwin native surface when the platform can prove HDR output.
  /// Failed probes and unsupported platforms always fall back to Texture.
  final bool useNativeSurface;

  /// Sets the [`--vo`](https://mpv.io/manual/stable/#options-vo) property on native backend.
  ///
  /// Default: Platform specific.
  /// * Windows, GNU/Linux, macOS & iOS: `libmpv`
  /// * Android: `gpu`
  /// * Ohos: `gpu-next`
  final String? vo;

  /// Sets the [`--hwdec`](https://mpv.io/manual/stable/#options-hwdec) property on native backend.
  ///
  /// Default: Platform specific.
  /// * Windows, GNU/Linux, macOS & iOS, Ohos : `auto`
  /// * Android: `auto-safe`
  final String? hwdec;

  /// The scale for the video output.
  /// This may be used for performance reasons. Specifying this option will cause [width] & [height] to be ignored.
  ///
  /// Default: `1.0`
  final double scale;

  /// The fixed width for the video output.
  /// This may be used for performance reasons.
  ///
  /// Default: `null`
  final int? width;

  /// The fixed height for the video output.
  /// This may be used for performance reasons.
  ///
  /// Default: `null`
  final int? height;

  /// Whether to enable hardware acceleration.
  ///
  /// DO NOT DISABLE THIS OPTION MEANINGLESSLY.
  /// THE BATTERY WILL DRAIN, THE DEVICE MAY HEAT UP & CPU USAGE WILL BE HIGH.
  ///
  /// Default: `true`
  final bool enableHardwareAcceleration;

  /// Whether to use Flutter's `SurfaceProducer` API on Android.
  ///
  /// This option only has effect on Android. If disabled, the Android
  /// implementation uses the `SurfaceTexture` code path instead. The
  /// `SurfaceTexture` code path is only effective with Android's Skia backend.
  ///
  /// Default: `true`
  final bool enableAndroidSurfaceProducer;

  /// Whether to attach `android.view.Surface` after video parameters are known.
  ///
  /// Default:
  /// * [vo] == gpu : `true`
  /// * [vo] != gpu : `false`
  final bool? androidAttachSurfaceAfterVideoParameters;

  /// Whether to use PlatformView instead of Texture for video rendering on Android.
  ///
  /// PlatformView provides better performance and compatibility for some use cases,
  /// but may have limitations with certain Flutter features (e.g., transformations).
  ///
  /// Default: `false`
  final bool usePlatformView;

  /// Whether to use Hybrid Composition++ (HCPP) for better PlatformView rendering on Android.
  ///
  /// Default: `false`
  final bool useHCPP;

  /// {@macro video_controller_configuration}
  const VideoControllerConfiguration({
    this.vo,
    this.hwdec,
    this.width,
    this.height,
    this.scale = 1.0,
    this.enableHardwareAcceleration = true,
    this.enableAndroidSurfaceProducer = true,
    this.androidAttachSurfaceAfterVideoParameters,
    this.usePlatformView = false,
    this.useHCPP = false,
    this.useNativeSurface = false,
  });

  /// Returns a copy of this class with the given fields replaced by the new values.
  VideoControllerConfiguration copyWith({
    String? vo,
    String? hwdec,
    double? scale,
    int? width,
    int? height,
    bool? enableHardwareAcceleration,
    bool? enableAndroidSurfaceProducer,
    bool? androidAttachSurfaceAfterVideoParameters,
    bool? usePlatformView,
    bool? useHCPP,
    bool? useNativeSurface,
  }) =>
      VideoControllerConfiguration(
        vo: vo ?? this.vo,
        hwdec: hwdec ?? this.hwdec,
        scale: scale ?? this.scale,
        width: width ?? this.width,
        height: height ?? this.height,
        enableHardwareAcceleration:
            enableHardwareAcceleration ?? this.enableHardwareAcceleration,
        enableAndroidSurfaceProducer:
            enableAndroidSurfaceProducer ?? this.enableAndroidSurfaceProducer,
        androidAttachSurfaceAfterVideoParameters:
            androidAttachSurfaceAfterVideoParameters ??
                this.androidAttachSurfaceAfterVideoParameters,
        usePlatformView: usePlatformView ?? this.usePlatformView,
        useHCPP: useHCPP ?? this.useHCPP,
        useNativeSurface: useNativeSurface ?? this.useNativeSurface,
      );
}
