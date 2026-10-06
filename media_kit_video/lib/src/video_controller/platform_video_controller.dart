/// This file is a part of media_kit (https://github.com/media-kit/media-kit).
///
/// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
/// All rights reserved.
/// Use of this source code is governed by MIT license that can be found in the LICENSE file.
import 'dart:async';

import 'package:flutter/widgets.dart';

import 'package:media_kit/media_kit.dart';

import 'package:media_kit_video/src/video_controller/hdr_transaction_report.dart';
import 'package:media_kit_video/src/video_controller/video_controller.dart';

/// Rendering topology selected for a video output.
enum VideoOutputSurfaceKind { texture, nativeSurface }

/// The physical viewport requested by one mounted Video widget.
class TextureOutputLayout {
  final Size viewport;
  final BoxFit fit;

  const TextureOutputLayout(this.viewport, this.fit);
}

/// Combines layout requests from VideoController wrappers sharing one output.
class TextureOutputLayoutRegistry {
  final _byController = <Object, List<TextureOutputLayout>>{};

  void update(Object controller, List<TextureOutputLayout> layouts) {
    if (layouts.isEmpty) {
      _byController.remove(controller);
    } else {
      _byController[controller] = List<TextureOutputLayout>.of(layouts);
    }
  }

  List<TextureOutputLayout> get layouts =>
      _byController.values.expand((layouts) => layouts).toList(growable: false);
}

/// A listener for the native `HdrCapabilities.Changed` event. The arguments
/// carry the full `HdrCapabilities.Get` snapshot map.
typedef HdrCapabilitiesChangedListener = void Function(
  Map<Object?, Object?> snapshot,
);

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

  /// Notifies the video widget when native output promotion changes the
  /// visible output topology. The bool above is intentionally kept as the
  /// state owner; this notifier only makes the state transition observable.
  final ValueNotifier<bool> nativeSurfaceActiveNotifier =
      ValueNotifier<bool>(false);

  /// Candidate surface is mounted before HDR promotion so SDR and HDR keep topology.
  bool nativeSurfaceCandidate = false;

  /// OHOS emulator mode: the software render bridge owns the XComponent
  /// surface (libmpv render API SW blitted with the bridge's own EGL), while
  /// mpv runs with vo=libmpv. See [OhosVideoController].
  bool swRender = false;

  /// {@macro platform_video_controller}
  PlatformVideoController(this.player, this.configuration);

  @protected
  void setNativeSurfaceActive(bool value) {
    if (nativeSurfaceActive == value) return;
    nativeSurfaceActive = value;
    nativeSurfaceActiveNotifier.value = value;
  }

  /// Sets the required size of the video output.
  /// This may yield substantial performance improvements if a small [width] & [height] is specified.
  ///
  /// Remember:
  /// * “Premature optimization is the root of all evil”
  /// * “With great power comes great responsibility”
  Future<void> setSize({int? width, int? height});

  /// Recalculates a native output's display-scaled buffer after a window
  /// metrics/orientation change. Texture-backed implementations have nothing
  /// to refresh.
  Future<void> refreshSurfaceSize(
      {double? viewportWidth, double? viewportHeight}) async {}

  /// Whether this controller consumes [updateTextureLayouts] reports.
  ///
  /// The controller declares its own layout demand; the wrapper never
  /// re-derives platform conditions from the configuration.
  bool get wantsLayoutReports => false;

  /// Reports mounted Android Texture viewports. SurfaceTexture may use these
  /// for playback buffer sizing; SurfaceProducer may use them for pre-open
  /// Surface preparation while keeping source-sized playback buffers.
  /// [owner] identifies one VideoController wrapper. Multiple wrappers may
  /// share this platform controller for the same Player.
  Future<void> updateTextureLayouts(
      Object owner, List<TextureOutputLayout> layouts) async {}

  /// Binds a mounted Android SurfaceProducer Texture before media is opened.
  /// Returns false when no usable mounted layout is available.
  Future<bool> prepareAndroidTextureOutput(
          Object owner, List<TextureOutputLayout> layouts) async =>
      false;

  /// Creates/configures the optional native output. Implementations must fail closed.
  Future<HdrTransactionReport> createNativeOutput(
          {String? surfaceId, int? windowHandle}) async =>
      const HdrTransactionReport(
        failureReason: 'unsupported platform',
      );

  /// Configures the native HDR output from a configuration payload map
  /// (`transfer`, optional `masteringMetadata`, `opticalOutputScale`, ...).
  Future<HdrTransactionReport> configureHdrOutput(
          Map<String, dynamic> configuration) async =>
      const HdrTransactionReport(
        failureReason: 'unsupported platform',
      );

  Future<HdrTransactionReport> resetHdrOutput() async =>
      const HdrTransactionReport(
        failureReason: 'unsupported platform',
      );

  Future<void> disposeNativeOutput() async {}

  /// A [Future] that completes when the first video frame has been rendered.
  Future<void> get waitUntilFirstFrameRendered =>
      waitUntilFirstFrameRenderedCompleter.future;

  /// Completes once the initial output required to open media has bound.
  ///
  /// Texture-backed controllers do not require a separate mount barrier. An
  /// Android PlatformView overrides this so a caller that opens media during
  /// its first build can wait until the native Surface bind command chain has
  /// completed, rather than opening with `vid=no`. This is a one-time mount
  /// barrier; it does not assert a later rebuilt Surface remains available or
  /// that the display has presented a frame.
  Future<void> get waitUntilInitialOutputBound => Future<void>.value();

  /// Waits for the output that is bound now, or for a later bind after a
  /// detach. This is an output-availability barrier, not a frame-presentation
  /// acknowledgement. Platforms without a separate output use the initial
  /// barrier.
  Future<void> get waitUntilCurrentOutputBound => waitUntilInitialOutputBound;

  /// [Completer] used to signal the decoding & rendering of the first video frame.
  /// Use [waitUntilFirstFrameRendered] to wait for the first frame to be rendered.
  @protected
  final waitUntilFirstFrameRenderedCompleter = Completer<void>();

  void dispose() {
    id.dispose();
    rect.dispose();
    nativeSurfaceActiveNotifier.dispose();
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
/// Android-specific output options for [VideoControllerConfiguration].
///
/// These only have effect on Android (the HCPP flag is additionally read by
/// the isolated OHOS embedding, which shares the hybrid-composition
/// concept).
class AndroidVideoOptions {
  /// Whether to use PlatformView instead of Texture for video rendering.
  ///
  /// PlatformView provides better performance and compatibility for some use
  /// cases, but may have limitations with certain Flutter features (e.g.,
  /// transformations).
  ///
  /// Default: `false`
  final bool usePlatformView;

  /// Whether to use Hybrid Composition++ (HCPP) for better PlatformView
  /// rendering.
  ///
  /// Default: `false`
  final bool useHCPP;

  /// Whether to use Flutter's `SurfaceProducer` API. If disabled, the
  /// Android implementation uses the `SurfaceTexture` code path instead.
  /// The `SurfaceTexture` code path is only effective with Android's Skia
  /// backend.
  ///
  /// Default: `true`
  final bool enableSurfaceProducer;

  /// Size SurfaceTexture playback output from the active Video widget's
  /// physical viewport. This is opt-in; SurfaceProducer pre-open preparation
  /// uses mounted viewports separately and keeps source-sized playback
  /// output.
  ///
  /// Default: `false`
  final bool matchTextureOutputToLayout;

  /// Whether to attach `android.view.Surface` after video parameters are
  /// known.
  ///
  /// Default:
  /// * [VideoControllerConfiguration.vo] == gpu : `true`
  /// * [VideoControllerConfiguration.vo] != gpu : `false`
  final bool? attachSurfaceAfterVideoParameters;

  /// gpu-next API selection (`opengl` / `vulkan`). Null keeps the platform
  /// default.
  final String? gpuApi;

  /// PlatformView Surface creation hints for HDR experiments.
  final String? surfaceTransfer;
  final String? surfacePixelFormat;

  const AndroidVideoOptions({
    this.usePlatformView = false,
    this.useHCPP = false,
    this.enableSurfaceProducer = true,
    this.matchTextureOutputToLayout = false,
    this.attachSurfaceAfterVideoParameters,
    this.gpuApi,
    this.surfaceTransfer,
    this.surfacePixelFormat,
  });

  AndroidVideoOptions copyWith({
    bool? usePlatformView,
    bool? useHCPP,
    bool? enableSurfaceProducer,
    bool? matchTextureOutputToLayout,
    bool? attachSurfaceAfterVideoParameters,
    String? gpuApi,
    bool clearGpuApi = false,
    String? surfaceTransfer,
    String? surfacePixelFormat,
  }) =>
      AndroidVideoOptions(
        usePlatformView: usePlatformView ?? this.usePlatformView,
        useHCPP: useHCPP ?? this.useHCPP,
        enableSurfaceProducer:
            enableSurfaceProducer ?? this.enableSurfaceProducer,
        matchTextureOutputToLayout:
            matchTextureOutputToLayout ?? this.matchTextureOutputToLayout,
        attachSurfaceAfterVideoParameters: attachSurfaceAfterVideoParameters ??
            this.attachSurfaceAfterVideoParameters,
        gpuApi: clearGpuApi ? null : gpuApi ?? this.gpuApi,
        surfaceTransfer: surfaceTransfer ?? this.surfaceTransfer,
        surfacePixelFormat: surfacePixelFormat ?? this.surfacePixelFormat,
      );
}

/// Darwin-specific output options for [VideoControllerConfiguration].
class DarwinVideoOptions {
  /// Selects the Darwin native surface when the platform can prove HDR
  /// output. Failed probes and unsupported platforms always fall back to
  /// Texture.
  final bool useNativeSurface;

  /// Experimental macOS mpv-owned Cocoa window output.
  ///
  /// This is deliberately independent from [useNativeSurface] and defaults
  /// to `false`. It is only a W1 integration probe for `wid + vo=gpu-next`;
  /// it is not an HDR/DV capability switch.
  final bool useNativeWindow;

  const DarwinVideoOptions({
    this.useNativeSurface = false,
    this.useNativeWindow = false,
  });

  DarwinVideoOptions copyWith({
    bool? useNativeSurface,
    bool? useNativeWindow,
  }) =>
      DarwinVideoOptions(
        useNativeSurface: useNativeSurface ?? this.useNativeSurface,
        useNativeWindow: useNativeWindow ?? this.useNativeWindow,
      );
}

class VideoControllerConfiguration {
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

  /// Android-specific output options.
  final AndroidVideoOptions android;

  /// Darwin-specific output options.
  final DarwinVideoOptions darwin;

  /// {@macro video_controller_configuration}
  const VideoControllerConfiguration({
    this.vo,
    this.hwdec,
    this.width,
    this.height,
    this.scale = 1.0,
    this.enableHardwareAcceleration = true,
    this.android = const AndroidVideoOptions(),
    this.darwin = const DarwinVideoOptions(),
  });

  /// Returns a copy of this class with the given fields replaced by the new values.
  VideoControllerConfiguration copyWith({
    String? vo,
    String? hwdec,
    double? scale,
    int? width,
    int? height,
    bool? enableHardwareAcceleration,
    AndroidVideoOptions? android,
    DarwinVideoOptions? darwin,
  }) =>
      VideoControllerConfiguration(
        vo: vo ?? this.vo,
        hwdec: hwdec ?? this.hwdec,
        scale: scale ?? this.scale,
        width: width ?? this.width,
        height: height ?? this.height,
        enableHardwareAcceleration:
            enableHardwareAcceleration ?? this.enableHardwareAcceleration,
        android: android ?? this.android,
        darwin: darwin ?? this.darwin,
      );
}
