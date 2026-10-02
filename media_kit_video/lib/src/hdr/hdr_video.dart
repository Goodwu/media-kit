/// This file is a part of media_kit (https://github.com/media-kit/media-kit).
///
/// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
/// All rights reserved.
/// Use of this source code is governed by MIT license that can be found in the LICENSE file.
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'package:media_kit_video/media_kit_video_controls/media_kit_video_controls.dart'
    as media_kit_video_controls;

import 'package:media_kit_video/src/subtitle/subtitle_view.dart';
import 'package:media_kit_video/src/video/video.dart';
import 'package:media_kit_video/src/video_controller/video_controller.dart';

import 'hdr_video_session.dart';

/// {@template hdr_video}
///
/// HdrVideo
/// --------
/// The companion widget of [HdrVideoSession] (R2.1): it displays the
/// session's current [VideoController] output and follows the session when
/// the controller is replaced (a Texture ↔ PlatformView topology switch
/// rebuilds the controller instance).
///
/// The constructor parameters mirror [Video] one-to-one, except that the
/// `controller` argument is replaced by the required [session]; every other
/// argument is passed through to the mounted [Video] unchanged.
///
/// While the session has no controller (before the first controller is
/// created, or during a replacement), a plain [HdrVideoPlaceholder] is shown.
///
/// The [session] is also exposed below this widget through
/// [HdrVideoScope], which the built-in fullscreen page uses to follow
/// controller replacements as well (R2.1).
///
/// **Example:**
///
/// ```dart
/// final session = HdrVideoSession(player);
/// ...
/// HdrVideo(session: session)
/// ```
///
/// {@endtemplate}
class HdrVideo extends StatelessWidget {
  /// {@macro hdr_video}
  const HdrVideo({
    super.key,
    required this.session,
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
  });

  /// The [HdrVideoSession] whose current controller is displayed.
  final HdrVideoSession session;

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
  final bool resumeUponEnteringForegroundMode;

  /// The configuration for subtitles e.g. [TextStyle] & padding etc.
  final SubtitleViewConfiguration subtitleViewConfiguration;

  /// The callback invoked when the [Video] enters fullscreen.
  final Future<void> Function() onEnterFullscreen;

  /// The callback invoked when the [Video] exits fullscreen.
  final Future<void> Function() onExitFullscreen;

  /// FocusNode for keyboard input.
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    return HdrVideoScope(
      session: session,
      child: HdrVideoBody(
        controller: session.controller,
        placeholder: HdrVideoPlaceholder(color: fill),
        videoBuilder: (controller) => Video(
          controller: controller,
          width: width,
          height: height,
          fit: fit,
          fill: fill,
          alignment: alignment,
          aspectRatio: aspectRatio,
          filterQuality: filterQuality,
          controls: controls,
          wakelock: wakelock,
          pauseUponEnteringBackgroundMode: pauseUponEnteringBackgroundMode,
          resumeUponEnteringForegroundMode: resumeUponEnteringForegroundMode,
          subtitleViewConfiguration: subtitleViewConfiguration,
          onEnterFullscreen: onEnterFullscreen,
          onExitFullscreen: onExitFullscreen,
          focusNode: focusNode,
        ),
      ),
    );
  }
}

/// Exposes the owning [HdrVideoSession] to the widgets below the [HdrVideo].
///
/// The built-in fullscreen page (see
/// `media_kit_video_controls/src/controls/methods/fullscreen.dart`) looks
/// this scope up with [maybeOf]: when a session is present, the pushed
/// fullscreen page follows [HdrVideoSession.controller] instead of holding
/// the controller captured at push time (R2.1).
class HdrVideoScope extends InheritedWidget {
  /// Creates the scope.
  const HdrVideoScope({
    super.key,
    required this.session,
    required super.child,
  });

  /// The session exposed to the widgets below this scope.
  final HdrVideoSession session;

  /// Returns the [HdrVideoScope] of the nearest [HdrVideo] above [context],
  /// or null when the context is not below an [HdrVideo].
  static HdrVideoScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<HdrVideoScope>();
  }

  @override
  bool updateShouldNotify(HdrVideoScope oldWidget) {
    return session != oldWidget.session;
  }
}

/// Mounts a [Video] for whichever [VideoController] the session currently
/// publishes, and shows [placeholder] while it is null.
///
/// This is the shared mounting point of [HdrVideo] and the built-in
/// fullscreen page: both must follow [HdrVideoSession.controller] so that a
/// controller replacement is reflected everywhere the session is displayed
/// (R2.1).
class HdrVideoBody extends StatelessWidget {
  /// Creates the mounting body.
  const HdrVideoBody({
    super.key,
    required this.controller,
    required this.videoBuilder,
    this.placeholder = const SizedBox.expand(),
  });

  /// The listenable of the current session controller.
  final ValueListenable<VideoController?> controller;

  /// Builds the video surface for a non-null controller.
  final Widget Function(VideoController controller) videoBuilder;

  /// Shown while [controller] holds no [VideoController].
  final Widget placeholder;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<VideoController?>(
      valueListenable: controller,
      builder: (context, controller, _) {
        if (controller == null) {
          return placeholder;
        }
        return videoBuilder(controller);
      },
    );
  }
}

/// The empty surface shown while the session has no controller (before the
/// first controller is created, or during a replacement). No new assets or
/// colors: it is a plain filled box.
class HdrVideoPlaceholder extends StatelessWidget {
  /// Creates the placeholder.
  const HdrVideoPlaceholder({super.key, this.color = const Color(0xFF000000)});

  /// The background color of the placeholder.
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: color,
      child: const SizedBox.expand(),
    );
  }
}
