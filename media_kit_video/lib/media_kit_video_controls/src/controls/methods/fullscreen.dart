/// This file is a part of media_kit (https://github.com/media-kit/media-kit).
///
/// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
/// All rights reserved.
/// Use of this source code is governed by MIT license that can be found in the LICENSE file.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:universal_platform/universal_platform.dart';
import 'package:media_kit_video/src/video/android_output_presentation.dart';
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
        final parameters = videoViewParametersNotifierValue.value;
        final pauseUponBackground =
            stateValue.widget.pauseUponEnteringBackgroundMode;
        final resumeUponForeground =
            stateValue.widget.resumeUponEnteringForegroundMode;
        final enterCallback = stateValue.widget.onEnterFullscreen;
        final exitCallback = stateValue.widget.onExitFullscreen;
        var nativeEnterAttempted = false;
        final enterSettled = Completer<void>();
        Future<void>? exitingNative;
        Future<void> exitNativeOnce() =>
            exitingNative ??= Future<void>.sync(() async {
              // A route may be removed while native enter is still pending.
              // Restore after it settles, so late enter cannot undo restoration.
              await enterSettled.future;
              if (!nativeEnterAttempted) return;
              try {
                await exitCallback();
              } catch (error, stack) {
                _reportFullscreenCleanupError(
                  error,
                  stack,
                  'restoring Android video fullscreen',
                );
              }
            });
        final navigator = Navigator.of(context, rootNavigator: true);
        final android = UniversalPlatform.isAndroid;
        final presentationOwner =
            AndroidOutputPresentationScope.maybeOf(context);
        // A second entry from a stale window context must not create another
        // fullscreen consumer while this precise presentation is leased.
        if (android && (presentationOwner?.suspended ?? false)) return;
        final injectThemes = android ? _captureVideoThemes(context) : null;
        final releaseNotifiers = android
            ? FullscreenNotifierLifetime.retain(contextNotifierValue)
            : () {};
        final releasePresentation =
            android ? presentationOwner?.acquire() ?? () {} : () {};
        var released = false;
        void release() {
          if (released) return;
          released = true;
          try {
            releasePresentation();
          } finally {
            releaseNotifiers();
          }
        }

        PageRouteBuilder<void>? pushedRoute;
        try {
          if (android) {
            // Commits removal of the old output subtree. This is a Flutter
            // frame boundary, not a native stop/release acknowledgement.
            await WidgetsBinding.instance.endOfFrame;
          }
          if (!context.mounted || !stateValue.mounted || !navigator.mounted) {
            release();
            return;
          }
          Widget buildFullscreenVideo(VideoController controller) => Video(
                controller: controller,
                width: null,
                height: null,
                fit: parameters.fit,
                fill: parameters.fill,
                alignment: parameters.alignment,
                aspectRatio: parameters.aspectRatio,
                filterQuality: parameters.filterQuality,
                controls: parameters.controls,
                wakelock: false,
                pauseUponEnteringBackgroundMode: pauseUponBackground,
                resumeUponEnteringForegroundMode: resumeUponForeground,
                subtitleViewConfiguration: parameters.subtitleViewConfiguration,
                focusNode: parameters.focusNode,
                onEnterFullscreen: enterCallback,
                onExitFullscreen: exitCallback,
              );
          final route = PageRouteBuilder<void>(
            pageBuilder: (_, __, ___) {
              final video = VideoStateInheritedWidget(
                state: stateValue,
                contextNotifier: contextNotifierValue,
                videoViewParametersNotifier: videoViewParametersNotifierValue,
                disposeNotifiers: false,
                child: FullscreenInheritedWidget(
                  parent: stateValue,
                  onExit: android ? exitNativeOnce : exitCallback,
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
                        color: parameters.fill,
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),
                ),
              );
              // An explicit independent host prevents inheritance of a
              // suspended window owner even with a nested root navigator.
              final independentVideo =
                  android ? AndroidOutputPresentationHost(child: video) : video;
              return Material(
                child: injectThemes != null
                    ? injectThemes(independentVideo)
                    : VideoControlsThemeDataInjector(
                        context: context,
                        child: independentVideo,
                      ),
              );
            },
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
          );
          pushedRoute = route;
          // Release after overlay removal, covering pop, Back and removeRoute.
          // Never await route lifetime while holding the fullscreen lock.
          unawaited(route.completed.then((_) async {
            try {
              if (android) await exitNativeOnce();
            } finally {
              release();
            }
          }).catchError((Object error, StackTrace stack) {
            _reportFullscreenCleanupError(
              error,
              stack,
              'releasing video fullscreen resources',
            );
          }));
          navigator.push(route);
          nativeEnterAttempted = true;
          try {
            await enterCallback();
          } finally {
            enterSettled.complete();
          }
        } catch (error, stack) {
          if (!enterSettled.isCompleted) enterSettled.complete();
          final route = pushedRoute;
          if (route?.navigator != null) {
            try {
              // Roll back this exact route, not an unrelated topmost route.
              navigator.removeRoute(route!);
            } catch (cleanupError, cleanupStack) {
              _reportFullscreenCleanupError(
                cleanupError,
                cleanupStack,
                'rolling back video fullscreen route',
              );
            }
          } else {
            release();
          }
          Error.throwWithStackTrace(error, stack);
        }
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
          final parent = FullscreenInheritedWidget.of(context).parent;
          if (parent.mounted) parent.refreshView();
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

/// Capture themes before the parent VideoState can disappear in a controller
/// null gap. Rebuilding the route never looks up an unmounted window context.
Widget Function(Widget) _captureVideoThemes(BuildContext context) {
  final cupertino = CupertinoVideoControlsTheme.maybeOf(context);
  final material = MaterialVideoControlsTheme.maybeOf(context);
  final desktop = MaterialDesktopVideoControlsTheme.maybeOf(context);
  final cupertinoNormal =
      cupertino?.normal ?? kDefaultCupertinoVideoControlsThemeData;
  final cupertinoFullscreen = cupertino?.fullscreen ??
      kDefaultCupertinoVideoControlsThemeDataFullscreen;
  final materialNormal =
      material?.normal ?? kDefaultMaterialVideoControlsThemeData;
  final materialFullscreen =
      material?.fullscreen ?? kDefaultMaterialVideoControlsThemeDataFullscreen;
  final desktopNormal =
      desktop?.normal ?? kDefaultMaterialDesktopVideoControlsThemeData;
  final desktopFullscreen = desktop?.fullscreen ??
      kDefaultMaterialDesktopVideoControlsThemeDataFullscreen;
  return (child) => CupertinoVideoControlsTheme(
        normal: cupertinoNormal,
        fullscreen: cupertinoFullscreen,
        child: MaterialVideoControlsTheme(
          normal: materialNormal,
          fullscreen: materialFullscreen,
          child: MaterialDesktopVideoControlsTheme(
            normal: desktopNormal,
            fullscreen: desktopFullscreen,
            child: child,
          ),
        ),
      );
}

/// A failing application's error reporter must not mask the original enter
/// failure or turn asynchronous route cleanup into an unhandled Future error.
void _reportFullscreenCleanupError(
    Object error, StackTrace stack, String action) {
  try {
    FlutterError.reportError(FlutterErrorDetails(
      exception: error,
      stack: stack,
      context: ErrorDescription(action),
    ));
  } catch (reporterError, reporterStack) {
    debugPrint('media_kit_video: $action failed: $error\n$stack\n'
        'FlutterError reporter failed: $reporterError\n$reporterStack');
  }
}
