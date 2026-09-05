/// This file is a part of media_kit (https://github.com/media-kit/media-kit).
///
/// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
/// All rights reserved.
/// Use of this source code is governed by MIT license that can be found in the LICENSE file.
import 'dart:io';
import 'dart:async';
import 'dart:collection';
import 'dart:ffi';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:synchronized/synchronized.dart';

import 'package:media_kit/media_kit.dart';

import 'package:media_kit_video/src/video_controller/platform_video_controller.dart';

/// {@template ohos_video_controller}
///
/// OhosVideoController
/// ----------------------
///
/// The [PlatformVideoController] implementation based on native C/C++ used on Ohos.
///
/// {@endtemplate}
class OhosVideoController extends PlatformVideoController {
  /// Whether [OhosVideoController] is supported on the current platform or not.
  static bool get supported => Platform.operatingSystem == 'ohos';

  /// Pointer address to the global object reference of `OHNativeWindow`.
  final ValueNotifier<int?> wid = ValueNotifier<int?>(null);

  static bool _nativeSurfaceHandlerInstalled = false;
  static const _nativeSurfaceEvents = MethodChannel(
    'com.alexmercerind/media_kit_video/native_surface_events',
  );

  static final DynamicLibrary _hdrLibrary =
      DynamicLibrary.open('libmediakit_ohos_hdr.so');
  static final int Function(int, int) _configureHdr = _hdrLibrary
      .lookup<NativeFunction<Int32 Function(Uint64, Int32)>>(
        'media_kit_ohos_hdr_configure',
      )
      .asFunction();
  static final int Function(int) _resetHdr = _hdrLibrary
      .lookup<NativeFunction<Int32 Function(Uint64)>>(
          'media_kit_ohos_hdr_reset')
      .asFunction();

  /// [Lock] used to synchronize [onLoadHooks], [onUnloadHooks] & [subscription].
  final lock = Lock();
  bool _disposed = false;
  int? _hdrTransfer;

  NativePlayer get platform => player.platform as NativePlayer;

  Future<void> setProperty(String key, String value) async {
    await platform.setProperty(key, value, waitForInitialization: false);
  }

  Future<void> setProperties(Map<String, String> properties) async {
    for (final entry in properties.entries) {
      await setProperty(entry.key, entry.value);
    }
  }

  @override
  Future<dynamic> createNativeOutput(
      {String? surfaceId, int? windowHandle}) async {
    // The XComponent PlatformView reports its surface asynchronously. Do
    // not claim native output until that surface has attached and mpv has
    // been switched to it by [_attachNativeSurface].
    final id = wid.value;
    if (!nativeSurfaceActive || id == null || id == 0) {
      return const <String, dynamic>{
        'capable': false,
        'active': false,
        'failureReason': 'ohos-native-surface-not-ready',
      };
    }
    return <String, dynamic>{
      'backend': 'ohos-xcomponent-native-window',
      'capable': true,
      'active': true,
      'surfaceId': id,
      'generation': nativeSurfaceGeneration,
    };
  }

  @override
  Future<dynamic> configureHdrOutput(dynamic configuration) async {
    final id = wid.value;
    if (!nativeSurfaceActive || id == null || id == 0) {
      return const <String, dynamic>{
        'capable': false,
        'active': false,
        'failureReason': 'ohos-native-surface-not-ready',
      };
    }
    final values =
        configuration is Map ? configuration : const <dynamic, dynamic>{};
    final transfer = values['transfer'] == 'hlg' ? 1 : 0;
    _hdrTransfer = transfer;
    // The NativeWindow is configured with the source HDR transfer below. Keep
    // mpv's target transfer identical; forcing linear here makes the display
    // treat linear samples as PQ/HLG code values and produces a gray, dim
    // image on real HDR panels.
    final targetTrc = values['transfer'] == 'hlg' ? 'hlg' : 'pq';
    await setProperties({
      'target-prim': 'bt.2020',
      'target-trc': targetTrc,
      // gpu-next otherwise leaves the swapchain color space at its default,
      // allowing the OHOS compositor to interpret PQ/HLG samples as SDR.
      'target-colorspace-hint': 'yes',
    });
    final result = _configureHdr(id, transfer);
    final active = result == 0;
    return <String, dynamic>{
      'backend': 'ohos-xcomponent-native-window',
      'capable': active,
      'active': active,
      'surfaceId': id,
      'generation': nativeSurfaceGeneration,
      'transfer': values['transfer'],
      'target-trc': targetTrc,
      'failureReason': active ? null : 'native-window-configure-$result',
    };
  }

  @override
  Future<Map<String, dynamic>> resetHdrOutput() async {
    final id = wid.value;
    if (id == null || id == 0) {
      return const <String, dynamic>{
        'capable': false,
        'active': false,
        'failureReason': 'ohos-surface-id-unavailable',
      };
    }
    final result = await lock.synchronized(() async {
      await setProperty('vo', 'null');
      final resetResult = _resetHdr(id);
      await setProperty('vo', 'gpu-next');
      return resetResult;
    });
    return <String, dynamic>{
      'backend': 'ohos-native-window',
      'capable': result == 0,
      'active': false,
      'surfaceId': id,
      'generation': nativeSurfaceGeneration,
      'failureReason': result == 0 ? null : 'native-window-reset-$result',
    };
  }

  /// [StreamSubscription] for listening to video [Rect].
  StreamSubscription<VideoParams>? videoParamsSubscription;
  int? _lastRequestedSurfaceWidth;
  int? _lastRequestedSurfaceHeight;
  int? _lastRefreshedSurfaceWidth;
  int? _lastRefreshedSurfaceHeight;
  double? _lastRefreshViewportWidth;
  double? _lastRefreshViewportHeight;
  bool _refreshingSurfaceSize = false;

  @override
  Future<void> refreshSurfaceSize({
    double? viewportWidth,
    double? viewportHeight,
  }) async {
    final width = _lastRequestedSurfaceWidth;
    final height = _lastRequestedSurfaceHeight;
    if (_disposed ||
        width == null ||
        height == null ||
        _refreshingSurfaceSize) {
      return;
    }
    if (viewportWidth != null &&
        viewportHeight != null &&
        viewportWidth == _lastRefreshViewportWidth &&
        viewportHeight == _lastRefreshViewportHeight) {
      return;
    }
    _refreshingSurfaceSize = true;
    try {
      final handle = await player.handle;
      final outputSize = await _channel.invokeMethod<dynamic>(
        'VideoOutputManager.SetSurfaceSize',
        {
          'handle': handle.toString(),
          'width': width.toString(),
          'height': height.toString(),
          'force': true,
        },
      );
      final effectiveWidth = outputSize is Map && outputSize['width'] is num
          ? (outputSize['width'] as num).toInt()
          : width;
      final effectiveHeight = outputSize is Map && outputSize['height'] is num
          ? (outputSize['height'] as num).toInt()
          : height;
      if (effectiveWidth <= 0 || effectiveHeight <= 0 || _disposed) return;
      if (effectiveWidth == _lastRefreshedSurfaceWidth &&
          effectiveHeight == _lastRefreshedSurfaceHeight) {
        return;
      }
      await lock.synchronized(() async {
        await setProperties({
          'ohos-surface-size': '${effectiveWidth}x$effectiveHeight',
        });
        // Resizing gpu-next can recreate the native swapchain. Reapply the
        // native window HDR contract after that recreation so fullscreen does
        // not silently fall back to an SDR interpretation.
        final transfer = _hdrTransfer;
        if (transfer != null) {
          final id = wid.value;
          if (id != null && id != 0) {
            final hdrResult = _configureHdr(id, transfer);
            debugPrint(
              '[OhosVideoController] reapplied HDR after surface resize: '
              'result=$hdrResult transfer=$transfer',
            );
          }
        }
        rect.value = Rect.fromLTWH(
          0,
          0,
          effectiveWidth.toDouble(),
          effectiveHeight.toDouble(),
        );
      });
      _lastRefreshedSurfaceWidth = effectiveWidth;
      _lastRefreshedSurfaceHeight = effectiveHeight;
      _lastRefreshViewportWidth = viewportWidth;
      _lastRefreshViewportHeight = viewportHeight;
      debugPrint(
        '[OhosVideoController] refreshed native surface size: '
        '${width}x$height -> ${effectiveWidth}x$effectiveHeight',
      );
    } finally {
      _refreshingSurfaceSize = false;
    }
  }

  /// {@macro ohos_video_controller}
  OhosVideoController._(
    super.player,
    super.configuration,
  ) {
    if (!_nativeSurfaceHandlerInstalled) {
      _nativeSurfaceHandlerInstalled = true;
      _nativeSurfaceEvents.setMethodCallHandler(_handleNativeSurfaceEvent);
    }
    videoParamsSubscription = player.stream.videoParams.listen(
      (event) => lock.synchronized(() async {
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

        final isZero = width == 0 || height == 0;
        final isSame = width == rect.value?.width.toInt() &&
            height == rect.value?.height.toInt();
        // videoParams may be emitted repeatedly while mpv settles the
        // decoder. Deduplicate at the request boundary as well as against
        // rect: the latter can briefly lag while the native surface changes.
        final isRepeatedRequest = width == _lastRequestedSurfaceWidth &&
            height == _lastRequestedSurfaceHeight;
        if (isZero || isSame || isRepeatedRequest) {
          return;
        }

        final handle = await player.handle;

        final outputSize = await _channel.invokeMethod<dynamic>(
          'VideoOutputManager.SetSurfaceSize',
          {
            'handle': handle.toString(),
            'width': width.toString(),
            'height': height.toString(),
          },
        );
        final effectiveWidth = outputSize is Map && outputSize['width'] is num
            ? (outputSize['width'] as num).toInt()
            : width;
        final effectiveHeight = outputSize is Map && outputSize['height'] is num
            ? (outputSize['height'] as num).toInt()
            : height;
        if (effectiveWidth <= 0 || effectiveHeight <= 0) {
          return;
        }
        _lastRequestedSurfaceWidth = width;
        _lastRequestedSurfaceHeight = height;
        await setProperties({
          'ohos-surface-size': [effectiveWidth, effectiveHeight].join('x'),
        });

        rect.value = Rect.fromLTWH(
          0.0,
          0.0,
          effectiveWidth.toDouble(),
          effectiveHeight.toDouble(),
        );

        if (!waitUntilFirstFrameRenderedCompleter.isCompleted) {
          waitUntilFirstFrameRenderedCompleter.complete();
        }
      }),
    );
  }

  static Future<dynamic> _handleNativeSurfaceEvent(MethodCall call) async {
    final args = call.arguments;
    debugPrint(
        '[OhosVideoController] native surface event ${call.method}: $args');
    if (args is! Map) return null;
    final rawHandle = args['handle'];
    final handle =
        rawHandle is num ? rawHandle.toInt() : int.tryParse('$rawHandle');
    if (handle == null) return null;
    var controller = _controllers[handle];
    if (controller == null) {
      for (final candidate in _controllers.values) {
        if (candidate.nativeHandle == handle) {
          controller = candidate;
          break;
        }
      }
    }
    if (controller == null) {
      debugPrint(
          '[OhosVideoController] no controller for native handle $handle');
      return null;
    }
    if (call.method == 'nativeSurfaceReady') {
      final rawSurfaceId = args['surfaceId'];
      final surfaceId = rawSurfaceId is num
          ? rawSurfaceId.toInt()
          : int.tryParse('$rawSurfaceId');
      debugPrint('[OhosVideoController] parsed native surface id: $surfaceId');
      if (surfaceId != null && surfaceId != 0) {
        // Stop Flutter's consumer before redirecting mpv away from the
        // texture-backed NativeWindow. Redirecting first leaves the old
        // external texture with an empty BufferQueue and causes repeated
        // OH_NativeImage_AcquireNativeWindowBuffer() 40601000 errors while
        // Flutter drains frames from the stale surface.
        await controller._suspendTextureOutput();
        await controller._attachNativeSurface(surfaceId);
      }
    } else if (call.method == 'nativeSurfaceDestroyed') {
      controller.nativeSurfaceActive = false;
      controller.nativeSurfaceCandidate = false;
      await controller._resumeTextureOutput();
    }
    return null;
  }

  Future<void> _attachNativeSurface(int surfaceId) async {
    debugPrint(
        '[OhosVideoController] attaching native XComponent surface $surfaceId');
    await lock.synchronized(() async {
      if (_disposed || wid.value == surfaceId) return;
      final previous = wid.value;
      await setProperty('vo', 'null');
      wid.value = surfaceId;
      await setProperties({
        'wid': surfaceId.toString(),
        if (rect.value != null)
          'ohos-surface-size':
              '${rect.value!.width.toInt()}x${rect.value!.height.toInt()}',
      });
      await setProperty('vo', configuration.vo ?? 'gpu-next');
      nativeSurfaceCandidate = true;
      nativeSurfaceActive = true;
      debugPrint(
        '[OhosVideoController] native XComponent surface attached: '
        'previous=$previous surface=$surfaceId',
      );
    });
  }

  Future<void> _suspendTextureOutput() async {
    final handle = await player.handle;
    await _channel.invokeMethod('VideoOutputManager.SuspendTexture', {
      'handle': handle.toString(),
    });
  }

  Future<void> _resumeTextureOutput() async {
    if (_disposed) return;
    final handle = await player.handle;
    final data = await _channel.invokeMethod<dynamic>(
      'VideoOutputManager.ResumeTexture',
      {'handle': handle.toString()},
    );
    if (data is! Map) return;
    final nextId = (data['id'] as num?)?.toInt();
    final nextWid = (data['wid'] as num?)?.toInt();
    final nextRect = data['rect'];
    if (nextId == null || nextWid == null || nextRect is! Map) return;
    id.value = nextId;
    wid.value = nextWid;
    rect.value = Rect.fromLTWH(
      ((nextRect['left'] as num?) ?? 0).toDouble(),
      ((nextRect['top'] as num?) ?? 0).toDouble(),
      ((nextRect['width'] as num?) ?? 1).toDouble(),
      ((nextRect['height'] as num?) ?? 1).toDouble(),
    );
    await lock.synchronized(() async {
      await setProperty('vo', 'null');
      await setProperties({
        'wid': nextWid.toString(),
        'ohos-surface-size':
            '${rect.value!.width.toInt()}x${rect.value!.height.toInt()}',
      });
      await setProperty('vo', configuration.vo ?? 'gpu-next');
    });
  }

  /// {@macro ohos_video_controller}
  static Future<PlatformVideoController> create(
    Player player,
    VideoControllerConfiguration configuration,
  ) async {
    final bool isEmulator = await _channel.invokeMethod('Utils.IsEmulator');
    if (isEmulator) {
      throw UnsupportedError(
        '[VideoController] does not support emulator.'
        ' '
        'Please use actual device.',
      );
    }

    Future<String> getDefaultHwdec() async {
      bool hw = configuration.enableHardwareAcceleration;
      return hw ? 'auto' : 'no';
    }

    // Update [configuration] to have default values.
    configuration = configuration.copyWith(
      vo: configuration.vo ?? 'gpu-next',
      hwdec: configuration.hwdec ?? await getDefaultHwdec(),
    );

    // Retrieve the native handle of the [Player].
    final handle = await player.handle;
    // Return the existing [VideoController] if it's already created.
    if (_controllers.containsKey(handle)) {
      return _controllers[handle]!;
    }

    // Creation:
    final controller = OhosVideoController._(
      player,
      configuration,
    );

    // Register [_dispose] for execution upon [Player.dispose].
    player.platform?.release.add(controller._dispose);

    // Store the [VideoController] in the [_controllers].
    _controllers[handle] = controller;

    final Map<dynamic, dynamic>? data = await _channel.invokeMethod(
      'VideoOutputManager.Create',
      {
        'handle': handle.toString(),
      },
    );

    if (data == null) {
      throw StateError('[OhosVideoController] failed to create video output.');
    }

    final id = (data['id'] as num).toInt();
    final wid = (data['wid'] as num).toInt();
    final rect = Rect.fromLTWH(
      (data['rect']['left'] as num).toDouble(),
      (data['rect']['top'] as num).toDouble(),
      (data['rect']['width'] as num).toDouble(),
      (data['rect']['height'] as num).toDouble(),
    );

    controller.id.value = id;
    controller.rect.value = rect;
    controller.wid.value = wid;
    controller.nativeHandle = handle;
    // Mount the XComponent once so its onLoad callback can provide the native
    // surface ID. After destruction the flag is cleared and the widget falls
    // back to the resumed Flutter Texture until a new candidate is mounted.
    controller.nativeSurfaceCandidate = configuration.useNativeSurface;
    controller.nativeSurfaceGeneration = (_surfaceGenerations[handle] ?? 0) + 1;
    _surfaceGenerations[handle] = controller.nativeSurfaceGeneration;

    await controller.lock.synchronized(() async {
      // MPV's HarmonyOS video output requires a valid surface ID before the
      // GPU video output is initialized.
      await controller.setProperty('vo', 'null');
      await controller.setProperties(
        {
          'ohos-surface-size': '${rect.width.toInt()}x${rect.height.toInt()}',
          'wid': wid.toString(),
          'hwdec': configuration.hwdec!,
          'vid': 'auto',
          'force-window': 'yes',
          'sub-use-margins': 'no',
          'sub-scale-with-window': 'no',
          'osd-font': 'HarmonyOS Sans SC',
        },
      );
      // When an OHOS native-surface candidate is enabled, keep mpv detached
      // until the XComponent reports its real surface. Starting gpu-next on
      // the Flutter Texture first creates frames for a producer that is
      // immediately replaced; after the handoff Flutter can keep consuming
      // that stale BufferQueue and report 40601000 indefinitely.
      if (!(Platform.operatingSystem == 'ohos' &&
          configuration.useNativeSurface)) {
        await controller.setProperty('vo', configuration.vo!);
      }
    });

    // Return the [PlatformVideoController].
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
  }) {
    throw UnsupportedError(
      '[OhosVideoController.setSize] is not available on Ohos',
    );
  }

  /// Disposes the instance. Releases allocated resources back to the system.
  @override
  Future<void> disposeForRebuild() => _dispose();

  /// Disposes the instance. Releases allocated resources back to the system.
  Future<void> _dispose() async {
    if (_disposed) return;
    _disposed = true;
    await videoParamsSubscription?.cancel();
    final handle = await player.handle;
    _controllers.remove(handle);
    await _channel.invokeMethod(
      'VideoOutputManager.Dispose',
      {
        'handle': handle.toString(),
      },
    );
    wid.dispose();
    super.dispose();
  }

  /// Currently created [OhosVideoController]s.
  static final _controllers = HashMap<int, OhosVideoController>();
  static final _surfaceGenerations = HashMap<int, int>();

  /// [MethodChannel] for invoking platform specific native implementation.
  static const _channel = MethodChannel('com.alexmercerind/media_kit_video');
}
