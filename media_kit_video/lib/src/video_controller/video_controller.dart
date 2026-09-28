/// This file is a part of media_kit (https://github.com/media-kit/media-kit).
///
/// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
/// All rights reserved.
/// Use of this source code is governed by MIT license that can be found in the LICENSE file.
import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';

import 'package:media_kit_video/src/video_controller/platform_video_controller.dart';

import 'package:media_kit_video/src/video_controller/native_video_controller/native_video_controller.dart';
import 'package:media_kit_video/src/video_controller/android_video_controller/android_video_controller.dart';
import 'package:media_kit_video/src/video_controller/ohos_video_controller/ohos_video_controller.dart';
import 'package:media_kit_video/src/video_controller/web_video_controller/web_video_controller.dart';

/// {@template video_controller}
///
/// VideoController
/// ---------------
///
/// [VideoController] is used to initialize & display video output.
/// It takes reference to existing [Player] instance from `package:media_kit`.
///
/// Passing [VideoController] to [Video] widget will cause the video output to be displayed.
///
/// ```dart
/// late final player = Player();
/// late final controller = VideoController(player);
/// ```
///
/// **Configurable options:**
///
/// 1. You can limit size of the video output by specifying [VideoControllerConfiguration.width] & [VideoControllerConfiguration.height].
///    * A smaller width & height may yield substantial performance improvements.
///    * By default, both [VideoControllerConfiguration.height] & [VideoControllerConfiguration.width] are `null` i.e. output is based on video's resolution.
/// 2. You can reduce scale of the video output by specifying [VideoControllerConfiguration.scale].
///    * A smaller scale may yield substantial performance improvements. Specifying this value will cause [VideoControllerConfiguration.width] & [VideoControllerConfiguration.height] to be ignored.
///    * By default, [VideoControllerConfiguration.scale] is `1.0` i.e. output is based on video's resolution.
/// 3. You can switch between GPU & CPU rendering by specifying [VideoControllerConfiguration.enableHardwareAcceleration].
///    * Disabling the option may improve stability on certain devices.
///    * By default, [VideoControllerConfiguration.enableHardwareAcceleration] is `true` i.e. GPU (Direct3D/OpenGL/METAL) is utilized.
///
/// **Platform specific limitations & differences:**
///
/// **Android**
/// * [VideoControllerConfiguration.width] & [VideoControllerConfiguration.height] arguments have no effect.
///
/// **Web**
/// * [VideoControllerConfiguration.width] & [VideoControllerConfiguration.height] arguments have no effect.
/// * Only single [Video] output can be displayed for a [VideoController].
///   Displaying multiple [Video] widgets with same [VideoController] will cause only last mounted [Video] to be displayed.
/// * [VideoControllerConfiguration.enableHardwareAcceleration] is ignored i.e. GPU usage is dependent upon the web browser.
///
/// {@endtemplate}
class VideoController {
  Future<void> Function()? _forwarderReleaseCallback;
  Future<void>? _disposeForRebuildFuture;
  final _textureLayoutOwners = <Object, TextureOutputLayout>{};
  Completer<void>? _textureLayoutReady;

  /// The native output covers every mounted Video's physical pixel demand.
  /// A later thumbnail update cannot shrink an existing fullscreen output.
  void updateTextureLayoutOwner(
      Object owner, Size physicalViewport, BoxFit fit) {
    _textureLayoutOwners[owner] = TextureOutputLayout(physicalViewport, fit);
    final ready = _textureLayoutReady;
    if (ready != null && !ready.isCompleted) ready.complete();
    _publishTextureLayouts();
  }

  void removeTextureLayoutOwner(Object owner) {
    if (_textureLayoutOwners.remove(owner) != null) {
      if (_textureLayoutOwners.isEmpty) _textureLayoutReady = null;
      _publishTextureLayouts();
    }
  }

  void _publishTextureLayouts() {
    final output = notifier.value;
    if (output == null) return;
    final hdrPlatformLayout = output.configuration.usePlatformView &&
        output.configuration.vo == 'gpu-next' &&
        (output.configuration.androidSurfaceTransfer?.isNotEmpty ?? false);
    if (!hdrPlatformLayout &&
        (output.configuration.usePlatformView ||
            (!output.configuration.matchAndroidTextureOutputToLayout &&
                !output.configuration.enableAndroidSurfaceProducer))) {
      return;
    }
    unawaited(output
        .updateTextureLayouts(this,
            List<TextureOutputLayout>.unmodifiable(_textureLayoutOwners.values))
        .catchError((Object error, StackTrace stack) {
      debugPrint('Android Texture layout resize failed: $error\n$stack');
    }));
  }

  /// Prepares a mounted Android SurfaceProducer Texture before opening media.
  /// Returns false if no Video has reported a bounded layout yet.
  Future<bool> prepareAndroidTextureOutput() async {
    final output = await platform.future;
    if (output.configuration.usePlatformView ||
        !output.configuration.enableAndroidSurfaceProducer) {
      return false;
    }
    if (_textureLayoutOwners.isEmpty) {
      await (_textureLayoutReady ??= Completer<void>())
          .future
          .timeout(const Duration(milliseconds: 250), onTimeout: () {});
    }
    return output.prepareAndroidTextureOutput(this,
        List<TextureOutputLayout>.unmodifiable(_textureLayoutOwners.values));
  }

  static Future<VideoController> create(
    Player player, {
    VideoControllerConfiguration configuration =
        const VideoControllerConfiguration(),
  }) async {
    final controller = VideoController(player, configuration: configuration);
    await controller.platform.future;
    return controller;
  }

  /// The [Player] instance associated with this [VideoController].
  final Player player;

  /// Platform specific internal implementation initialized depending upon the current platform.
  final platform = Completer<PlatformVideoController>();

  /// Platform specific internal implementation initialized depending upon the current platform.
  final notifier = ValueNotifier<PlatformVideoController?>(null);

  /// Texture ID of the video output, registered with Flutter engine by the native implementation.
  final ValueNotifier<int?> id = ValueNotifier<int?>(null);

  /// [Rect] of the video output, received from the native implementation.
  final ValueNotifier<Rect?> rect = ValueNotifier<Rect?>(null);

  /// Whether the platform implementation has mounted a native-surface
  /// candidate. This is false on platforms which do not expose one.
  bool get nativeSurfaceCandidate =>
      notifier.value?.nativeSurfaceCandidate ?? false;

  /// Whether the platform implementation has an active native video surface.
  /// This remains false until the platform reports that the surface is ready.
  bool get nativeSurfaceActive => notifier.value?.nativeSurfaceActive ?? false;

  /// {@macro video_controller}
  VideoController(
    this.player, {
    VideoControllerConfiguration configuration =
        const VideoControllerConfiguration(),
  }) {
    player.platform?.isVideoControllerAttached = true;

    () async {
      final completer = Completer();
      WidgetsBinding.instance.addPostFrameCallback((_) => completer.complete());
      await completer.future;

      try {
        if (NativeVideoController.supported) {
          final result = await NativeVideoController.create(
            player,
            configuration,
          );
          platform.complete(result);
          notifier.value = result;
        } else if (AndroidVideoController.supported) {
          final result = await AndroidVideoController.create(
            player,
            configuration,
          );
          platform.complete(result);
          notifier.value = result;
        } else if (OhosVideoController.supported) {
          final result = await OhosVideoController.create(
            player,
            configuration,
          );
          platform.complete(result);
          notifier.value = result;
        } else if (WebVideoController.supported) {
          final result = await WebVideoController.create(
            player,
            configuration,
          );
          platform.complete(result);
          notifier.value = result;
        }

        if (platform.isCompleted) {
          // Populate [id] & [rect] [ValueNotifier]s with the values from [platform] implementation of [PlatformVideoController].
          final controller = await platform.future;
          _publishTextureLayouts();
          // Add listeners.
          void fn0() => id.value = controller.id.value;
          void fn1() => rect.value = controller.rect.value;
          fn0();
          fn1();
          controller.id.addListener(fn0);
          controller.rect.addListener(fn1);
          // Remove listeners upon [Player.dispose].
          Future<void> releaseForwarders() async {
            controller.id.removeListener(fn0);
            controller.rect.removeListener(fn1);
          }

          _forwarderReleaseCallback = releaseForwarders;
          player.platform?.release.add(releaseForwarders);
        } else {
          platform.completeError(
            UnimplementedError(
              '[VideoController] is unavailable for this platform.',
            ),
          );
        }
      } catch (exception, stacktrace) {
        platform.completeError(exception);
        debugPrint(exception.toString());
        debugPrint(stacktrace.toString());
      }

      if (!(player.platform?.videoControllerCompleter.isCompleted ?? true)) {
        player.platform?.videoControllerCompleter.complete();
      }
    }();
  }

  /// Sets the required size of the video output.
  /// This may yield substantial performance improvements if a small [width] & [height] is specified.
  ///
  /// Remember:
  /// * “Premature optimization is the root of all evil”
  /// * “With great power comes great responsibility”
  Future<void> setSize({
    int? width,
    int? height,
  }) async {
    final instance = await platform.future;
    return instance.setSize(
      width: width,
      height: height,
    );
  }

  /// A [Future] that completes when the first video frame has been rendered.
  Future<void> get waitUntilFirstFrameRendered async {
    final instance = await platform.future;
    return instance.waitUntilFirstFrameRendered;
  }

  /// Releases this wrapper and its platform output before another controller
  /// for the same Player is created. A failed platform release is retryable.
  Future<void> disposeForRebuild() =>
      _disposeForRebuildFuture ??= _disposeForRebuildOnce().catchError(
        (Object error, StackTrace stack) {
          _disposeForRebuildFuture = null;
          Error.throwWithStackTrace(error, stack);
        },
      );

  Future<void> _disposeForRebuildOnce() async {
    _textureLayoutOwners.clear();
    PlatformVideoController? output;
    try {
      output = await platform.future;
    } catch (_) {
      // Platform creation already reconciles its native resources (or keeps
      // a failed controller registered for retry). This wrapper was never
      // published and has no platform listeners to detach.
    }
    if (output != null) {
      await output.updateTextureLayouts(this, const []);
      await output.disposeForRebuild();
    }
    final releaseForwarders = _forwarderReleaseCallback;
    if (releaseForwarders != null) {
      await releaseForwarders();
      player.platform?.release.remove(releaseForwarders);
      _forwarderReleaseCallback = null;
    }
    id.dispose();
    rect.dispose();
    notifier.dispose();
  }
}
