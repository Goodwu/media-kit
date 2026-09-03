/// This file is a part of media_kit (https://github.com/media-kit/media-kit).
///
/// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
/// All rights reserved.
/// Use of this source code is governed by MIT license that can be found in the LICENSE file.
import 'dart:io';
import 'dart:async';
import 'dart:collection';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:synchronized/synchronized.dart';

import 'package:media_kit/media_kit.dart';

import 'package:media_kit_video/src/utils/query_decoders.dart';
import 'package:media_kit_video/src/video_controller/platform_video_controller.dart';

/// {@template native_video_controller}
///
/// NativeVideoController
/// ---------------------
///
/// The [PlatformVideoController] implementation based on native C/C++ used on:
/// * Windows
/// * GNU/Linux
/// * macOS
/// * iOS
///
/// {@endtemplate}
class NativeVideoController extends PlatformVideoController {
  /// Whether [NativeVideoController] is supported on the current platform or not.
  static bool get supported =>
      Platform.isWindows ||
      Platform.isLinux ||
      Platform.isMacOS ||
      Platform.isIOS;

  /// Fixed width of the video output.
  int? width;

  /// Fixed height of the video output.
  int? height;

  /// Width of the video (from [VideoParams]).
  int? videoParamsWidth;

  /// Height of the video (from [VideoParams]).
  int? videoParamsHeight;

  /// [Lock] used to synchronize [onLoadHooks], [onUnloadHooks] & [subscription].
  final lock = Lock();
  bool _disposed = false;
  Map<String, dynamic>? _lastNativeConfiguration;

  NativePlayer get platform => player.platform as NativePlayer;

  Future<void> setProperty(String key, String value) async {
    await platform.setProperty(key, value, waitForInitialization: false);
  }

  Future<void> setProperties(Map<String, String> properties) async {
    // ORDER IS IMPORTANT.
    for (final entry in properties.entries) {
      await setProperty(entry.key, entry.value);
    }
  }

  /// [StreamSubscription] for listening to video [Rect].
  StreamSubscription<VideoParams>? videoParamsSubscription;

  /// {@macro native_video_controller}
  NativeVideoController._(
    super.player,
    super.configuration,
  )   : width = configuration.width,
        height = configuration.height {
    videoParamsSubscription = player.stream.videoParams.listen(
      (event) => lock.synchronized(() async {
        if ([0, null].contains(event.dw) || [0, null].contains(event.dh)) {
          return;
        }

        final int handle = await player.handle;

        final int width;
        final int height;
        if (event.rotate == 0 || event.rotate == 180) {
          width = event.dw ?? 0;
          height = event.dh ?? 0;
        } else {
          // width & height are swapped for 90 or 270 degrees rotation.
          width = event.dh ?? 0;
          height = event.dw ?? 0;
        }

        if (videoParamsWidth == width && videoParamsHeight == height) {
          return;
        }

        videoParamsWidth = width;
        videoParamsHeight = height;

        await _channel.invokeMethod(
          'VideoOutputManager.SetSize',
          {
            'handle': handle.toString(),
            'width': width.toString(),
            'height': height.toString(),
          },
        );
      }),
    );
  }

  /// {@macro native_video_controller}
  static Future<PlatformVideoController> create(
    Player player,
    VideoControllerConfiguration configuration,
  ) async {
    // Update [configuration] to have default values.
    configuration = configuration.copyWith(
      vo: configuration.vo ?? 'libmpv',
      hwdec: configuration.hwdec ?? 'auto',
    );

    // Retrieve the native handle of the [Player].
    final handle = await player.handle;
    // Return the existing [VideoController] if it's already created.
    if (_controllers.containsKey(handle)) {
      return _controllers[handle]!;
    }

    // In case no video-decoders are found, this means media_kit_libs_***_audio is being used.
    // Thus, --vid=no is required to prevent libmpv from trying to decode video (otherwise bad things may happen).
    //
    // Search for common H264 decoder to check if video support is available.
    final decoders = await queryDecoders(handle);
    if (!decoders.contains('h264')) {
      throw UnsupportedError(
        '[VideoController] is not available.'
        ' '
        'Please use media_kit_libs_***_video instead of media_kit_libs_***_audio.',
      );
    }

    // Creation:
    final controller = NativeVideoController._(
      player,
      configuration,
    );
    controller.nativeHandle = handle;
    controller.nativeSurfaceGeneration = (_surfaceGenerations[handle] ?? 0) + 1;
    _surfaceGenerations[handle] = controller.nativeSurfaceGeneration;

    // Register [_dispose] for execution upon [Player.dispose].
    player.platform?.release.add(controller._dispose);

    // Store the [NativeVideoController] in the [_controllers].
    _controllers[handle] = controller;

    await controller.setProperties(
      {
        'vo': configuration.vo!,
        'hwdec': configuration.hwdec!,
        'vid': 'auto',
      },
    );

    if (configuration.useNativeSurface &&
        configuration.enableHardwareAcceleration &&
        (Platform.isIOS || Platform.isMacOS)) {
      // Keep the native candidate in a stable extended-linear BT.2020 target
      // across SDR/HDR source changes; promotion still requires native probes.
      await controller.setProperties({
        'target-colorspace': 'bt.2020',
        'target-trc': 'linear',
      });
    }

    if (configuration.useNativeSurface &&
        configuration.enableHardwareAcceleration &&
        (Platform.isIOS || Platform.isMacOS)) {
      try {
        final nativeResult = await controller.createNativeOutput();
        controller.nativeSurfaceCandidate =
            nativeResult is Map && nativeResult['capable'] == true;
        controller.nativeSurfaceActive =
            nativeResult is Map && nativeResult['active'] == true;
      } catch (_) {
        // Missing native plugin/renderer is a normal fail-closed fallback.
        controller.nativeSurfaceActive = false;
      }
    }

    // Wait until first texture ID is received.
    // We are not waiting on the native-side itself because it will block the UI thread.
    final completer = Completer<void>();
    void listener() {
      final value = controller.id.value;
      if (value != null) {
        debugPrint('NativeVideoController: Texture ID: $value');
        completer.complete();
      }
    }

    controller.id.addListener(listener);

    await _channel.invokeMethod(
      'VideoOutputManager.Create',
      {
        'handle': handle.toString(),
        'configuration': {
          'width': configuration.width.toString(),
          'height': configuration.height.toString(),
          'enableHardwareAcceleration':
              configuration.enableHardwareAcceleration,
          'useNativeSurface': configuration.useNativeSurface,
        },
      },
    );

    await completer.future;
    controller.id.removeListener(listener);

    // Return the [VideoController].
    return controller;
  }

  /// Sets the required size of the video output.
  /// This may yield substantial performance improvements if a small [width] & [height] is specified.
  ///
  /// Remember:
  /// * “Premature optimization is the root of all evil”
  /// * “With great power comes great responsibility”
  @override
  Future<void> setSize({
    int? width,
    int? height,
  }) async {
    final handle = await player.handle;
    if (this.width == width && this.height == height) {
      // No need to resize if the requested size is same as the current size.
      return;
    }
    if (width != null && height != null) {
      this.width = width;
      this.height = height;
      await _channel.invokeMethod(
        'VideoOutputManager.SetSize',
        {
          'handle': handle.toString(),
          'width': width.toString(),
          'height': height.toString(),
        },
      );
    } else {
      this.width = null;
      this.height = null;
      await _channel.invokeMethod(
        'VideoOutputManager.SetSize',
        {
          'handle': handle.toString(),
          'width': videoParamsWidth?.toString() ?? 'null',
          'height': videoParamsHeight?.toString() ?? 'null',
        },
      );
    }
  }

  @override
  Future<dynamic> createNativeOutput(
      {String? surfaceId, int? windowHandle}) async {
    final handle = nativeHandle ?? await player.handle;
    return (await _channel.invokeMethod<Map<dynamic, dynamic>>(
              'createNativeOutput',
              {
                'handle': handle.toString(),
                'generation': nativeSurfaceGeneration
              },
            ) ??
            const <dynamic, dynamic>{})
        .cast<String, dynamic>();
  }

  @override
  Future<dynamic> configureHdrOutput(dynamic configuration) async {
    final handle = nativeHandle ?? await player.handle;
    final payload = Map<String, dynamic>.from(
      configuration is Map<String, dynamic>
          ? configuration
          : (configuration as dynamic).toMap(),
    );
    if (this.configuration.useNativeSurface) {
      // Keep the native surface contract explicit: the mpv target must be
      // extended-linear BT.2020 before a layer can be promoted to HDR.
      payload['target-colorspace'] = 'bt.2020';
      payload['target-trc'] = 'linear';
      try {
        final colorspace = await player.getProperty(
          'target-colorspace',
          waitForInitialization: false,
        );
        final transfer = await player.getProperty(
          'target-trc',
          waitForInitialization: false,
        );
        payload['playerTargetVerified'] =
            colorspace == 'bt.2020' && transfer == 'linear';
      } catch (_) {
        payload['playerTargetVerified'] = false;
      }
    }
    _lastNativeConfiguration = payload.cast<String, dynamic>();
    return (await _channel.invokeMethod<Map<dynamic, dynamic>>(
              'configureHdrOutput',
              {
                'handle': handle.toString(),
                'generation': nativeSurfaceGeneration,
                'configuration': payload,
              },
            ) ??
            const <dynamic, dynamic>{})
        .cast<String, dynamic>();
  }

  @override
  Future<Map<String, dynamic>> resetHdrOutput() async {
    final handle = nativeHandle ?? await player.handle;
    return (await _channel.invokeMethod<Map<dynamic, dynamic>>(
              'resetHdrOutput',
              {
                'handle': handle.toString(),
                'generation': nativeSurfaceGeneration
              },
            ) ??
            const <dynamic, dynamic>{})
        .cast<String, dynamic>();
  }

  @override
  Future<void> disposeNativeOutput() async {
    final handle = nativeHandle ?? await player.handle;
    try {
      await _channel.invokeMethod('disposeNativeOutput', {
        'handle': handle.toString(),
        'generation': nativeSurfaceGeneration,
      });
    } catch (_) {}
  }

  /// Disposes the instance. Releases allocated resources back to the system.
  @override
  Future<void> disposeForRebuild() => _dispose();

  /// Disposes the instance. Releases allocated resources back to the system.
  Future<void> _dispose() async {
    if (_disposed) return;
    _disposed = true;
    super.dispose();
    await disposeNativeOutput();
    await videoParamsSubscription?.cancel();
    final handle = await player.handle;
    _controllers.remove(handle);
    await _channel.invokeMethod(
      'VideoOutputManager.Dispose',
      {
        'handle': handle.toString(),
      },
    );
  }

  /// Currently created [NativeVideoController]s.
  /// This is used to notify about updated texture IDs & [Rect]s through [_channel].
  static final _controllers = HashMap<int, NativeVideoController>();
  static final _surfaceGenerations = HashMap<int, int>();

  /// [MethodChannel] for invoking platform specific native implementation.
  static final _channel =
      const MethodChannel('com.alexmercerind/media_kit_video')
        ..setMethodCallHandler(
          (MethodCall call) async {
            try {
              debugPrint(call.method.toString());
              debugPrint(call.arguments.toString());
              switch (call.method) {
                case 'VideoOutput.Resize':
                  {
                    // Notify about updated texture ID & [Rect].
                    final int handle = call.arguments['handle'];
                    final Rect rect = Rect.fromLTWH(
                      call.arguments['rect']['left'] * 1.0,
                      call.arguments['rect']['top'] * 1.0,
                      call.arguments['rect']['width'] * 1.0,
                      call.arguments['rect']['height'] * 1.0,
                    );
                    final int id = call.arguments['id'];
                    _controllers[handle]?.rect.value = rect;
                    _controllers[handle]?.id.value = id;
                    // Notify about the first frame being rendered.
                    if (rect.width > 0 && rect.height > 0) {
                      final completer = _controllers[handle]
                          ?.waitUntilFirstFrameRenderedCompleter;
                      if (!(completer?.isCompleted ?? true)) {
                        completer?.complete();
                      }
                    }
                    break;
                  }
                case 'NativeSurface.Ready':
                  final handle = call.arguments['handle'] as int;
                  final controller = _controllers[handle];
                  final generation = call.arguments['generation'] as int?;
                  final hasRendererState =
                      call.arguments is Map &&
                      (call.arguments as Map).containsKey('rendererReady');
                  final rendererReady = call.arguments['rendererReady'] == true;
                  if (controller != null &&
                      generation == controller.nativeSurfaceGeneration) {
                    // A failed native renderer must immediately return to the
                    // Flutter texture path; do not leave a black platform view.
                    if (hasRendererState) {
                      controller.nativeSurfaceCandidate = rendererReady;
                    }
                    if (!hasRendererState && call.arguments['active'] is bool) {
                      controller.nativeSurfaceActive =
                          call.arguments['active'] == true;
                    }
                  }
                  final configuration = controller?._lastNativeConfiguration;
                  if (controller != null &&
                      rendererReady &&
                      generation == controller.nativeSurfaceGeneration &&
                      configuration != null) {
                    final result =
                        await controller.configureHdrOutput(configuration);
                    controller.nativeSurfaceActive =
                        result is Map && result['active'] == true;
                  }
                  break;
                default:
                  {
                    break;
                  }
              }
            } catch (exception, stacktrace) {
              debugPrint(exception.toString());
              debugPrint(stacktrace.toString());
            }
          },
        );
}
