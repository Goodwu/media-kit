/// This file is a part of media_kit (https://github.com/media-kit/media-kit).
///
/// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
/// All rights reserved.
/// Use of this source code is governed by MIT license that can be found in the LICENSE file.
import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart' show VideoParams;
import 'package:media_kit_video/media_kit_video_controls/media_kit_video_controls.dart';

import 'package:media_kit_video/src/subtitle/subtitle_view.dart';
import 'package:media_kit_video/media_kit_video_controls/media_kit_video_controls.dart'
    as media_kit_video_controls;
import 'package:media_kit_video/src/utils/dispose_safe_notifer.dart';

import 'package:media_kit_video/src/utils/wakelock.dart';
import 'package:media_kit_video/src/video_view_parameters.dart';
import 'package:media_kit_video/src/video_controller/video_controller.dart';
import 'package:media_kit_video/src/video_controller/platform_video_controller.dart';
import 'package:media_kit_video/src/video/platform_view_video.dart';

/// {@template video}
///
/// Video
/// -----
/// [Video] widget is used to display video output.
///
/// Use [VideoController] to initialize & handle the video rendering.
///
/// **Example:**
///
/// ```dart
/// class MyScreen extends StatefulWidget {
///   const MyScreen({Key? key}) : super(key: key);
///   @override
///   State<MyScreen> createState() => MyScreenState();
/// }
///
/// class MyScreenState extends State<MyScreen> {
///   late final player = Player();
///   late final controller = VideoController(player);
///
///   @override
///   void initState() {
///     super.initState();
///     player.open(Media('https://user-images.githubusercontent.com/28951144/229373695-22f88f13-d18f-4288-9bf1-c3e078d83722.mp4'));
///   }
///
///   @override
///   void dispose() {
///     player.dispose();
///     super.dispose();
///   }
///
///   @override
///   Widget build(BuildContext context) {
///     return Scaffold(
///       body: Video(
///         controller: controller,
///       ),
///     );
///   }
/// }
/// ```
///
/// {@endtemplate}
class Video extends StatefulWidget {
  /// The [VideoController] reference to control this [Video] output.
  final VideoController controller;

  /// Width of this viewport.
  final double? width;

  /// Height of this viewport.
  final double? height;

  /// Fit of the viewport.
  final BoxFit fit;

  /// Background color to fill the video background.
  final Color fill;

  /// Alignment of the viewport.
  final Alignment alignment;

  /// Preferred aspect ratio of the viewport.
  final double? aspectRatio;

  /// Filter quality of the [Texture] widget displaying the video output.
  final FilterQuality filterQuality;

  /// Video controls builder.
  final VideoControlsBuilder? controls;

  /// Whether to acquire wake lock while playing the video.
  final bool wakelock;

  /// Whether to pause the video when application enters background mode.
  final bool pauseUponEnteringBackgroundMode;

  /// Whether to resume the video when application enters foreground mode.
  ///
  /// This attribute is only applicable if [pauseUponEnteringBackgroundMode] is `true`.
  ///
  final bool resumeUponEnteringForegroundMode;

  /// The configuration for subtitles e.g. [TextStyle] & padding etc.
  final SubtitleViewConfiguration subtitleViewConfiguration;

  /// The callback invoked when the [Video] enters fullscreen.
  final Future<void> Function() onEnterFullscreen;

  /// The callback invoked when the [Video] exits fullscreen.
  final Future<void> Function() onExitFullscreen;

  /// FocusNode for keyboard input.
  final FocusNode? focusNode;

  /// {@macro video}
  const Video({
    Key? key,
    required this.controller,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.fill = const Color(0xFF000000),
    this.alignment = Alignment.center,
    this.aspectRatio,
    this.filterQuality = FilterQuality.low,
    this.controls = media_kit_video_controls.AdaptiveVideoControls,
    this.wakelock = true,
    this.pauseUponEnteringBackgroundMode = true,
    this.resumeUponEnteringForegroundMode = false,
    this.subtitleViewConfiguration = const SubtitleViewConfiguration(),
    this.onEnterFullscreen = defaultEnterNativeFullscreen,
    this.onExitFullscreen = defaultExitNativeFullscreen,
    this.focusNode,
  }) : super(key: key);

  @override
  State<Video> createState() => VideoState();
}

class VideoState extends State<Video> with WidgetsBindingObserver {
  late final _contextNotifier = DisposeSafeNotifier<BuildContext?>(null);
  late ValueNotifier<VideoViewParameters> videoViewParametersNotifier;
  late bool _disposeNotifiers;
  final _subtitleViewKey = GlobalKey<SubtitleViewState>();
  final _wakelock = Wakelock();
  final _subscriptions = <StreamSubscription>[];
  late int? _width = widget.controller.player.state.width;
  late int? _height = widget.controller.player.state.height;
  late bool _visible = (_width ?? 0) > 0 && (_height ?? 0) > 0;
  Size? _lastNativeSurfaceViewport;
  String? _lastOhosCompositionTrace;
  bool _ohosNativeSurfaceMounted = false;
  Size? _reportedTextureViewport;
  Size? _pendingTextureViewport;
  BoxFit? _reportedTextureFit;
  BoxFit? _pendingTextureFit;
  bool _textureLayoutCallbackScheduled = false;
  int _textureLayoutGeneration = 0;

  bool _pauseDueToPauseUponEnteringBackgroundMode = false;

  void _traceOhosComposition(String value) {
    if (!kDebugMode ||
        Platform.operatingSystem != 'ohos' ||
        _lastOhosCompositionTrace == value) {
      return;
    }
    _lastOhosCompositionTrace = value;
    debugPrint('[OhosPlatformViewTrace] composition $value');
  }

  // Public API:
  bool isFullscreen() {
    return media_kit_video_controls.isFullscreen(_contextNotifier.value!);
  }

  Future<void> enterFullscreen() {
    return media_kit_video_controls.enterFullscreen(_contextNotifier.value!);
  }

  Future<void> exitFullscreen() {
    return media_kit_video_controls.exitFullscreen(_contextNotifier.value!);
  }

  Future<void> toggleFullscreen() {
    return media_kit_video_controls.toggleFullscreen(_contextNotifier.value!);
  }

  void setSubtitleViewPadding(
    EdgeInsets padding, {
    Duration duration = const Duration(milliseconds: 100),
  }) {
    return _subtitleViewKey.currentState?.setPadding(
      padding,
      duration: duration,
    );
  }

  void update({
    double? width,
    double? height,
    BoxFit? fit,
    Color? fill,
    Alignment? alignment,
    double? aspectRatio,
    FilterQuality? filterQuality,
    VideoControlsBuilder? controls,
    SubtitleViewConfiguration? subtitleViewConfiguration,
    FocusNode? focusNode,
  }) {
    videoViewParametersNotifier.value =
        videoViewParametersNotifier.value.copyWith(
      width: width,
      height: height,
      fit: fit,
      fill: fill,
      alignment: alignment,
      aspectRatio: aspectRatio,
      filterQuality: filterQuality,
      controls: controls,
      subtitleViewConfiguration: subtitleViewConfiguration,
      focusNode: focusNode,
    );
  }

  @override
  void didChangeDependencies() {
    videoViewParametersNotifier =
        media_kit_video_controls.VideoStateInheritedWidget.maybeOf(
              context,
            )?.videoViewParametersNotifier ??
            ValueNotifier<VideoViewParameters>(
              VideoViewParameters(
                width: widget.width,
                height: widget.height,
                fit: widget.fit,
                fill: widget.fill,
                alignment: widget.alignment,
                aspectRatio: widget.aspectRatio,
                filterQuality: widget.filterQuality,
                controls: widget.controls,
                subtitleViewConfiguration: widget.subtitleViewConfiguration,
                focusNode: widget.focusNode,
              ),
            );
    _disposeNotifiers =
        media_kit_video_controls.VideoStateInheritedWidget.maybeOf(
              context,
            )?.disposeNotifiers ??
            true;
    super.didChangeDependencies();
  }

  @override
  void didUpdateWidget(Video oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (kDebugMode &&
        Platform.operatingSystem == 'ohos' &&
        !identical(oldWidget.controller, widget.controller)) {
      debugPrint(
        '[OhosPlatformViewTrace] Video controller changed '
        'old=${oldWidget.controller.hashCode} new=${widget.controller.hashCode}',
      );
    }
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeTextureLayoutOwner(this);
      _reportedTextureViewport = null;
      _pendingTextureViewport = null;
      _reportedTextureFit = null;
      _pendingTextureFit = null;
      _textureLayoutGeneration++;
      _textureLayoutCallbackScheduled = false;
      _ohosNativeSurfaceMounted = false;
      _lastNativeSurfaceViewport = null;
    }

    final currentParams = videoViewParametersNotifier.value;

    final newParams = currentParams.copyWith(
      width:
          widget.width != oldWidget.width ? widget.width : currentParams.width,
      height: widget.height != oldWidget.height
          ? widget.height
          : currentParams.height,
      fit: widget.fit != oldWidget.fit ? widget.fit : currentParams.fit,
      fill: widget.fill != oldWidget.fill ? widget.fill : currentParams.fill,
      alignment: widget.alignment != oldWidget.alignment
          ? widget.alignment
          : currentParams.alignment,
      aspectRatio: widget.aspectRatio != oldWidget.aspectRatio
          ? widget.aspectRatio
          : currentParams.aspectRatio,
      filterQuality: widget.filterQuality != oldWidget.filterQuality
          ? widget.filterQuality
          : currentParams.filterQuality,
      controls: widget.controls != oldWidget.controls
          ? widget.controls
          : currentParams.controls,
      subtitleViewConfiguration: widget.subtitleViewConfiguration !=
              oldWidget.subtitleViewConfiguration
          ? widget.subtitleViewConfiguration
          : currentParams.subtitleViewConfiguration,
      focusNode: widget.focusNode != oldWidget.focusNode
          ? widget.focusNode
          : currentParams.focusNode,
    );

    if (newParams != currentParams) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        videoViewParametersNotifier.value = newParams;
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (widget.pauseUponEnteringBackgroundMode) {
      if ([
        AppLifecycleState.paused,
        AppLifecycleState.detached,
      ].contains(state)) {
        if (widget.controller.player.state.playing) {
          _pauseDueToPauseUponEnteringBackgroundMode = true;
          widget.controller.player.pause();
        }
      } else {
        if (widget.resumeUponEnteringForegroundMode &&
            _pauseDueToPauseUponEnteringBackgroundMode) {
          _pauseDueToPauseUponEnteringBackgroundMode = false;
          widget.controller.player.play();
        }
      }
    }
    super.didChangeAppLifecycleState(state);
  }

  @override
  void initState() {
    super.initState();
    if (kDebugMode && Platform.operatingSystem == 'ohos') {
      debugPrint(
        '[OhosPlatformViewTrace] VideoState init '
        'controller=${widget.controller.hashCode}',
      );
    }
    WidgetsBinding.instance.addObserver(this);
    // --------------------------------------------------
    // Do not show the video frame until width & height are available.
    // Since [ValueNotifier<Rect?>] inside [VideoController] only gets updated by the render loop (i.e. it will not fire when video's width & height are not available etc.), it's important to handle this separately here.
    _subscriptions.addAll(
      [
        widget.controller.player.stream.width.listen(
          (value) {
            _width = value;
            final visible = (_width ?? 0) > 0 && (_height ?? 0) > 0;
            if (_visible != visible) {
              setState(() {
                _visible = visible;
              });
            }
          },
        ),
        widget.controller.player.stream.height.listen(
          (value) {
            _height = value;
            final visible = (_width ?? 0) > 0 && (_height ?? 0) > 0;
            if (_visible != visible) {
              setState(() {
                _visible = visible;
              });
            }
          },
        ),
      ],
    );
    // --------------------------------------------------
    if (widget.wakelock) {
      if (widget.controller.player.state.playing) {
        _wakelock.enable();
      }
      _subscriptions.add(
        widget.controller.player.stream.playing.listen(
          (value) {
            if (value) {
              _wakelock.enable();
            } else {
              _wakelock.disable();
            }
          },
        ),
      );
    }
  }

  @override
  void dispose() {
    widget.controller.removeTextureLayoutOwner(this);
    if (kDebugMode && Platform.operatingSystem == 'ohos') {
      debugPrint(
        '[OhosPlatformViewTrace] VideoState dispose '
        'controller=${widget.controller.hashCode}',
      );
    }
    WidgetsBinding.instance.removeObserver(this);
    _wakelock.disable();
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    if (_disposeNotifiers) {
      videoViewParametersNotifier.dispose();
      _contextNotifier.dispose();
      VideoStateInheritedWidgetContextNotifierState.fallback.remove(this);
    }

    super.dispose();
  }

  void refreshView() {}

  void _reportTextureLayout(
    BuildContext context,
    BoxConstraints constraints,
    BoxFit fit,
    PlatformVideoController notifier,
  ) {
    final hdrPlatformLayout = notifier.configuration.android.usePlatformView &&
        notifier.configuration.vo == 'gpu-next' &&
        (notifier.configuration.android.surfaceTransfer?.isNotEmpty ?? false);
    if (!Platform.isAndroid ||
        (!hdrPlatformLayout &&
            (notifier.configuration.android.usePlatformView ||
                (!notifier.configuration.android.matchTextureOutputToLayout &&
                    !notifier.configuration.android.enableSurfaceProducer))) ||
        !constraints.hasBoundedWidth ||
        !constraints.hasBoundedHeight) {
      return;
    }
    final viewport = Size(constraints.maxWidth, constraints.maxHeight) *
        MediaQuery.devicePixelRatioOf(context);
    if (!viewport.width.isFinite ||
        !viewport.height.isFinite ||
        viewport.width <= 0 ||
        viewport.height <= 0) {
      return;
    }
    if ((_pendingTextureViewport == viewport && _pendingTextureFit == fit) ||
        (_pendingTextureViewport == null &&
            _reportedTextureViewport == viewport &&
            _reportedTextureFit == fit)) {
      return;
    }
    _pendingTextureViewport = viewport;
    _pendingTextureFit = fit;
    if (_textureLayoutCallbackScheduled) return;
    _textureLayoutCallbackScheduled = true;
    final controller = widget.controller;
    final generation = _textureLayoutGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (generation != _textureLayoutGeneration) return;
      _textureLayoutCallbackScheduled = false;
      if (!mounted || !identical(widget.controller, controller)) return;
      final nextViewport = _pendingTextureViewport;
      final nextFit = _pendingTextureFit;
      _pendingTextureViewport = null;
      _pendingTextureFit = null;
      if (nextViewport == null || nextFit == null) return;
      _reportedTextureViewport = nextViewport;
      _reportedTextureFit = nextFit;
      controller.updateTextureLayoutOwner(this, nextViewport, nextFit);
    });
  }

  @override
  Widget build(BuildContext context) {
    return media_kit_video_controls.VideoStateInheritedWidget(
      state: this as dynamic,
      contextNotifier: _contextNotifier,
      videoViewParametersNotifier: videoViewParametersNotifier,
      child: ValueListenableBuilder<VideoViewParameters>(
        valueListenable: videoViewParametersNotifier,
        builder: (context, videoViewParameters, _) {
          return Container(
            clipBehavior: Clip.none,
            width: videoViewParameters.width,
            height: videoViewParameters.height,
            color: videoViewParameters.fill,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRect(
                  child: LayoutBuilder(
                    builder: (context, viewportConstraints) => FittedBox(
                      fit: videoViewParameters.fit,
                      alignment: videoViewParameters.alignment,
                      child: ValueListenableBuilder<PlatformVideoController?>(
                        valueListenable: widget.controller.notifier,
                        builder: (context, notifier, _) {
                          if (notifier == null) {
                            return (() {
                              _traceOhosComposition('notifier=null');
                              return const SizedBox.shrink();
                            })();
                          }
                          _reportTextureLayout(context, viewportConstraints,
                              videoViewParameters.fit, notifier);
                          // Android PlatformView owns its Surface and must be
                          // mounted before video-params/Texture readiness. It
                          // deliberately has no Texture sibling: rendering to
                          // both would create two native consumers.
                          if (Platform.isAndroid &&
                              notifier.configuration.android.usePlatformView &&
                              notifier.nativeHandle != null) {
                            final width = viewportConstraints.hasBoundedWidth
                                ? viewportConstraints.maxWidth
                                : videoViewParameters.width ?? 1.0;
                            final height = viewportConstraints.hasBoundedHeight
                                ? viewportConstraints.maxHeight
                                : videoViewParameters.height ?? 1.0;
                            final hdrPlatformView =
                                notifier.configuration.vo == 'gpu-next' &&
                                    (notifier
                                            .configuration
                                            .android.surfaceTransfer
                                            ?.isNotEmpty ??
                                        false);
                            return StreamBuilder<VideoParams>(
                              stream: hdrPlatformView
                                  ? widget.controller.player.stream.videoParams
                                  : null,
                              builder: (context, snapshot) {
                                final aspect = snapshot.data?.aspect ??
                                    widget.controller.player.state.videoParams
                                        .aspect;
                                final fittedHeight = hdrPlatformView &&
                                        aspect != null &&
                                        aspect.isFinite &&
                                        aspect > 0
                                    ? width / aspect
                                    : height;
                                return SizedBox(
                                  width: width,
                                  height: fittedHeight,
                                  child: PlatformViewVideo(
                                    key: ValueKey(
                                      'android-platform-view-${notifier.nativeHandle}-${notifier.nativeSurfaceGeneration}',
                                    ),
                                    handle: notifier.nativeHandle!,
                                    width: width.ceil(),
                                    height: fittedHeight.ceil(),
                                    useHCPP: notifier.configuration.android.useHCPP,
                                    generation:
                                        notifier.nativeSurfaceGeneration,
                                    androidSurfaceTransfer: notifier
                                        .configuration.android.surfaceTransfer,
                                    androidSurfacePixelFormat: notifier
                                        .configuration
                                        .android.surfacePixelFormat,
                                  ),
                                );
                              },
                            );
                          }
                          return ValueListenableBuilder<bool>(
                            valueListenable:
                                notifier.nativeSurfaceActiveNotifier,
                            builder: (context, _, __) =>
                                ValueListenableBuilder<int?>(
                              valueListenable: notifier.id,
                              builder: (context, id, _) {
                                return ValueListenableBuilder<Rect?>(
                                  valueListenable: notifier.rect,
                                  builder: (context, rect, _) {
                                    _traceOhosComposition(
                                      'visible=$_visible id=$id '
                                      'rect=$rect candidate=${notifier.nativeSurfaceCandidate} '
                                      'active=${notifier.nativeSurfaceActive} '
                                      'generation=${notifier.nativeSurfaceGeneration}',
                                    );
                                    final ohosNativeSurfaceCandidate =
                                        Platform.operatingSystem == 'ohos' &&
                                            notifier.configuration
                                                .darwin.useNativeSurface &&
                                            notifier.nativeSurfaceCandidate;
                                    final keepMountedNativeSurface =
                                        ohosNativeSurfaceCandidate &&
                                            _ohosNativeSurfaceMounted;
                                    if (id != null &&
                                        rect != null &&
                                        (_visible ||
                                            keepMountedNativeSurface)) {
                                      final nativeSurfaceCandidate = (Platform
                                                  .isAndroid &&
                                              notifier.configuration
                                                  .android.usePlatformView) ||
                                          ((Platform.isIOS || Platform.isMacOS) &&
                                              (notifier.configuration
                                                      .darwin.useNativeSurface ||
                                                  notifier.configuration
                                                      .darwin.useNativeWindow) &&
                                              (notifier.configuration
                                                      .darwin.useNativeWindow
                                                  ? notifier
                                                      .nativeSurfaceCandidate
                                                  : notifier
                                                      .nativeSurfaceCandidate) &&
                                              notifier.nativeHandle != null) ||
                                          (Platform.operatingSystem == 'ohos' &&
                                              notifier.configuration
                                                  .darwin.useNativeSurface &&
                                              notifier.nativeSurfaceCandidate);
                                      final nativeSurface =
                                          nativeSurfaceCandidate &&
                                              (notifier.configuration
                                                      .darwin.useNativeWindow
                                                  ? notifier
                                                      .nativeSurfaceCandidate
                                                  : notifier
                                                      .nativeSurfaceActive);
                                      final nativeOhosSurface = nativeSurface &&
                                          Platform.operatingSystem == 'ohos';
                                      final nativeOhosCandidate =
                                          nativeSurfaceCandidate &&
                                              Platform.operatingSystem ==
                                                  'ohos';
                                      final nativeMacosCandidate =
                                          nativeSurfaceCandidate &&
                                              Platform.isMacOS;
                                      if (nativeOhosCandidate && _visible) {
                                        _ohosNativeSurfaceMounted = true;
                                      }
                                      if (nativeOhosSurface &&
                                          viewportConstraints.hasBoundedWidth &&
                                          viewportConstraints
                                              .hasBoundedHeight) {
                                        final viewportSize = Size(
                                          viewportConstraints.maxWidth,
                                          viewportConstraints.maxHeight,
                                        );
                                        if (_lastNativeSurfaceViewport ==
                                            null) {
                                          // The initial surface size is set
                                          // by the video-params path. Avoid
                                          // rebuilding the HDR swapchain a
                                          // second time on first mount.
                                          _lastNativeSurfaceViewport =
                                              viewportSize;
                                        } else if (_lastNativeSurfaceViewport !=
                                            viewportSize) {
                                          _lastNativeSurfaceViewport =
                                              viewportSize;
                                          WidgetsBinding.instance
                                              .addPostFrameCallback((_) {
                                            if (mounted) {
                                              notifier.refreshSurfaceSize(
                                                viewportWidth:
                                                    viewportSize.width,
                                                viewportHeight:
                                                    viewportSize.height,
                                              );
                                            }
                                          });
                                        }
                                      }
                                      final viewportWidth =
                                          viewportConstraints.hasBoundedWidth
                                              ? viewportConstraints.maxWidth
                                              : (videoViewParameters.width ??
                                                  rect.width);
                                      final viewportHeight =
                                          viewportConstraints.hasBoundedHeight
                                              ? viewportConstraints.maxHeight
                                              : (videoViewParameters.height ??
                                                  rect.height);
                                      var surfaceWidth = viewportWidth;
                                      var surfaceHeight = viewportHeight;
                                      if (nativeOhosSurface &&
                                          rect.width > 0 &&
                                          rect.height > 0) {
                                        final aspect = rect.width / rect.height;
                                        final widthForHeight =
                                            viewportHeight * aspect;
                                        if (widthForHeight <= viewportWidth) {
                                          surfaceWidth = widthForHeight;
                                        } else {
                                          surfaceHeight =
                                              viewportWidth / aspect;
                                        }
                                      }
                                      final nativeVideo = PlatformViewVideo(
                                        handle: notifier.nativeHandle ?? id,
                                        width: rect.width.toInt(),
                                        height: rect.height.toInt(),
                                        useHCPP: notifier.configuration.android.useHCPP,
                                        generation:
                                            notifier.nativeSurfaceGeneration,
                                        mpvWindow: Platform.isMacOS &&
                                            notifier
                                                .configuration.darwin.useNativeWindow,
                                      );
                                      return SizedBox(
                                        // Native OHOS surfaces must receive
                                        // the viewport size, not the decoder
                                        // rect. Platform views do not inherit
                                        // the scale produced by FittedBox.
                                        width: nativeOhosSurface &&
                                                viewportConstraints
                                                    .hasBoundedWidth
                                            ? viewportConstraints.maxWidth
                                            : nativeOhosSurface
                                                ? videoViewParameters.width
                                                : videoViewParameters
                                                            .aspectRatio ==
                                                        null
                                                    ? rect.width
                                                    : rect.height *
                                                        videoViewParameters
                                                            .aspectRatio!,
                                        height: nativeOhosSurface &&
                                                viewportConstraints
                                                    .hasBoundedHeight
                                            ? viewportConstraints.maxHeight
                                            : nativeOhosSurface
                                                ? videoViewParameters.height
                                                : rect.height,
                                        child: Stack(
                                          children: [
                                            const SizedBox(),
                                            if (nativeSurfaceCandidate)
                                              Positioned.fill(
                                                // Keep the native candidate in
                                                // one stable, painted element.
                                                // When it is only a candidate,
                                                // the Texture below remains the
                                                // visual output until native
                                                // activation. Zero-opacity or
                                                // offstage wrappers would
                                                // suppress the platform-view
                                                // paint needed for renderer
                                                // readiness on Darwin too.
                                                // macOS already inherits the
                                                // fitted outer video box.
                                                child: nativeMacosCandidate
                                                    ? nativeVideo
                                                    : Center(
                                                        child: SizedBox(
                                                          width: nativeOhosSurface
                                                              ? surfaceWidth
                                                              : viewportWidth,
                                                          height: nativeOhosSurface
                                                              ? surfaceHeight
                                                              : viewportHeight,
                                                          child: nativeVideo,
                                                        ),
                                                      ),
                                              ),
                                            if (!nativeSurface)
                                              Positioned.fill(
                                                child: Texture(
                                                  textureId: id,
                                                  filterQuality:
                                                      videoViewParameters
                                                          .filterQuality,
                                                ),
                                              ),
                                            if (nativeSurface &&
                                                !nativeOhosCandidate &&
                                                !nativeMacosCandidate)
                                              Positioned.fill(
                                                child: nativeVideo,
                                              ),
                                            if (rect.width <= 1.0 &&
                                                rect.height <= 1.0)
                                              Positioned.fill(
                                                child: Container(
                                                  color:
                                                      videoViewParameters.fill,
                                                ),
                                              ),
                                          ],
                                        ),
                                      );
                                    }
                                    return const SizedBox.shrink();
                                  },
                                );
                              },
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
                if (videoViewParameters.subtitleViewConfiguration.visible &&
                    !(widget.controller.player.platform?.configuration.libass ??
                        false))
                  Positioned.fill(
                    child: SubtitleView(
                      controller: widget.controller,
                      key: _subtitleViewKey,
                      configuration:
                          videoViewParameters.subtitleViewConfiguration,
                    ),
                  ),
                if (videoViewParameters.controls != null)
                  Positioned.fill(
                    child: videoViewParameters.controls!.call(this),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

typedef VideoControlsBuilder = Widget Function(VideoState state);

// --------------------------------------------------

/// Makes the native window enter fullscreen.
Future<void> defaultEnterNativeFullscreen() async {
  try {
    if (Platform.isAndroid || Platform.isIOS) {
      await Future.wait(
        [
          SystemChrome.setEnabledSystemUIMode(
            SystemUiMode.immersiveSticky,
            overlays: [],
          ),
          SystemChrome.setPreferredOrientations(
            [
              DeviceOrientation.landscapeLeft,
              DeviceOrientation.landscapeRight,
            ],
          ),
        ],
      );
    } else if (Platform.isMacOS ||
        Platform.isWindows ||
        Platform.isLinux ||
        Platform.operatingSystem == 'ohos') {
      await const MethodChannel('com.alexmercerind/media_kit_video')
          .invokeMethod(
        'Utils.EnterNativeFullscreen',
      );
    }
  } catch (exception, stacktrace) {
    debugPrint(exception.toString());
    debugPrint(stacktrace.toString());
    if (Platform.operatingSystem == 'ohos') {
      rethrow;
    }
  }
}

/// Makes the native window exit fullscreen.
Future<void> defaultExitNativeFullscreen() async {
  try {
    if (Platform.isAndroid || Platform.isIOS) {
      await Future.wait(
        [
          SystemChrome.setEnabledSystemUIMode(
            SystemUiMode.manual,
            overlays: SystemUiOverlay.values,
          ),
          SystemChrome.setPreferredOrientations(
            [],
          ),
        ],
      );
    } else if (Platform.isMacOS ||
        Platform.isWindows ||
        Platform.isLinux ||
        Platform.operatingSystem == 'ohos') {
      await const MethodChannel('com.alexmercerind/media_kit_video')
          .invokeMethod(
        'Utils.ExitNativeFullscreen',
      );
    }
  } catch (exception, stacktrace) {
    debugPrint(exception.toString());
    debugPrint(stacktrace.toString());
    if (Platform.operatingSystem == 'ohos') {
      rethrow;
    }
  }
}
// --------------------------------------------------
