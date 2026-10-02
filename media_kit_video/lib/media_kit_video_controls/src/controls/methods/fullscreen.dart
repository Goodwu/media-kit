/// This file is a part of media_kit (https://github.com/media-kit/media-kit).
///
/// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
/// All rights reserved.
/// Use of this source code is governed by MIT license that can be found in the LICENSE file.
import 'package:flutter/material.dart';
import 'package:synchronized/synchronized.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'package:media_kit_video/media_kit_video_controls/src/controls/methods/video_state.dart';

import 'package:media_kit_video/media_kit_video_controls/src/controls/widgets/video_controls_theme_data_injector.dart';

/// Whether a [Video] present in the current [BuildContext] is in fullscreen or not.
bool isFullscreen(BuildContext context) =>
    VideoFullscreenScope.maybeOf(context)?.isFullscreen ??
    (FullscreenInheritedWidget.maybeOf(context) != null);

/// Makes the [Video] present in the current [BuildContext] enter fullscreen.
Future<void> enterFullscreen(BuildContext context) {
  return lock.synchronized(() async {
    if (!context.mounted) return;
    final scope = VideoFullscreenScope.maybeOf(context);
    if (scope != null) {
      await scope.enter(
        onEnterFullscreen: state(context).widget.onEnterFullscreen,
        onExitFullscreen: state(context).widget.onExitFullscreen,
      );
      return;
    }
    if (!isFullscreen(context)) {
      if (context.mounted) {
        final stateValue = state(context);
        final contextNotifierValue = contextNotifier(context);
        final videoViewParametersNotifierValue =
            videoViewParametersNotifier(context);
        final controllerValue = controller(context);
        // R2.1: when the [Video] is mounted by an [HdrVideo], the pushed
        // fullscreen page must follow [HdrVideoSession.controller] instead
        // of holding this statically captured controller — a topology switch
        // replaces the controller instance while the page is open.
        final hdrSessionValue = HdrVideoScope.maybeOf(context)?.session;
        Widget buildFullscreenVideo(VideoController controller) => Video(
              controller: controller,
              // Do not restrict the video's width & height in fullscreen mode:
              width: null,
              height: null,
              fit: videoViewParametersNotifierValue.value.fit,
              fill: videoViewParametersNotifierValue.value.fill,
              alignment:
                  videoViewParametersNotifierValue.value.alignment,
              aspectRatio:
                  videoViewParametersNotifierValue.value.aspectRatio,
              filterQuality: videoViewParametersNotifierValue
                  .value.filterQuality,
              controls:
                  videoViewParametersNotifierValue.value.controls,
              // Do not acquire or modify existing wakelock in fullscreen mode:
              wakelock: false,
              pauseUponEnteringBackgroundMode:
                  stateValue.widget.pauseUponEnteringBackgroundMode,
              resumeUponEnteringForegroundMode:
                  stateValue.widget.resumeUponEnteringForegroundMode,
              subtitleViewConfiguration:
                  videoViewParametersNotifierValue
                      .value.subtitleViewConfiguration,
              focusNode:
                  videoViewParametersNotifierValue.value.focusNode,
              onEnterFullscreen: stateValue.widget.onEnterFullscreen,
              onExitFullscreen: stateValue.widget.onExitFullscreen,
            );
        Navigator.of(context, rootNavigator: true).push(
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => Material(
              child: VideoControlsThemeDataInjector(
                // NOTE: Make various *VideoControlsThemeData from the parent context available in the fullscreen context.
                context: context,
                child: VideoStateInheritedWidget(
                  state: stateValue,
                  contextNotifier: contextNotifierValue,
                  videoViewParametersNotifier: videoViewParametersNotifierValue,
                  disposeNotifiers: false,
                  child: FullscreenInheritedWidget(
                    parent: stateValue,
                    // Another [VideoStateInheritedWidget] inside [FullscreenInheritedWidget] is important to notify about the fullscreen [BuildContext].
                    child: VideoStateInheritedWidget(
                      state: stateValue,
                      contextNotifier: contextNotifierValue,
                      videoViewParametersNotifier:
                          videoViewParametersNotifierValue,
                      disposeNotifiers: false,
                      child: FullscreenVideoSurface(
                        session: hdrSessionValue,
                        controller: controllerValue,
                        buildVideo: buildFullscreenVideo,
                        placeholder: ColoredBox(
                          color: videoViewParametersNotifierValue.value.fill,
                          child: const SizedBox.expand(),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
          ),
        );
        await onEnterFullscreen(context)?.call();
      }
    }
  });
}

/// Makes the [Video] present in the current [BuildContext] exit fullscreen.
Future<void> exitFullscreen(BuildContext context) {
  return lock.synchronized(() async {
    if (!context.mounted) return;
    final scope = VideoFullscreenScope.maybeOf(context);
    if (scope != null) {
      await scope.exit();
      return;
    }
    if (isFullscreen(context)) {
      if (context.mounted) {
        await Navigator.of(context).maybePop();
        // It is known that this [context] will have a [FullscreenInheritedWidget] above it.
        if (context.mounted) {
          FullscreenInheritedWidget.of(context).parent.refreshView();
        }
      }
      // [exitNativeFullscreen] is moved to [WillPopScope] in [FullscreenInheritedWidget].
      // This is because [exitNativeFullscreen] needs to be called when the user presses the back button.
    }
  });
}

/// Toggles fullscreen for the [Video] present in the current [BuildContext].
Future<void> toggleFullscreen(BuildContext context) {
  if (isFullscreen(context)) {
    return exitFullscreen(context);
  } else {
    return enterFullscreen(context);
  }
}

/// The video surface of the built-in fullscreen page (R2.1).
///
/// Without an [HdrVideoSession] (i.e. the windowed [Video] was not mounted
/// by an [HdrVideo]) this builds the statically captured [VideoController] —
/// the historical behavior, byte-for-byte. With a session, the surface
/// follows [HdrVideoSession.controller] instead, so a controller replacement
/// (Texture ↔ PlatformView topology switch) while the fullscreen page is
/// open is reflected in it; [placeholder] is shown while the next controller
/// is being created.
class FullscreenVideoSurface extends StatelessWidget {
  const FullscreenVideoSurface({
    super.key,
    required this.session,
    required this.controller,
    required this.buildVideo,
    this.placeholder = const SizedBox.expand(),
  });

  /// The session detected above the windowed [Video], if any.
  final HdrVideoSession? session;

  /// The controller captured at push time. Only used when [session] is null.
  final VideoController controller;

  /// Builds the fullscreen [Video] for a controller.
  final Widget Function(VideoController controller) buildVideo;

  /// Shown while the session has no controller (replacement in progress).
  final Widget placeholder;

  @override
  Widget build(BuildContext context) {
    final session = this.session;
    if (session == null) {
      // No HDR session: keep the static behavior unchanged.
      return buildVideo(controller);
    }
    return HdrVideoBody(
      controller: session.controller,
      placeholder: placeholder,
      videoBuilder: buildVideo,
    );
  }
}

/// For synchronizing [enterFullscreen] & [exitFullscreen] operations.
final Lock lock = Lock();
