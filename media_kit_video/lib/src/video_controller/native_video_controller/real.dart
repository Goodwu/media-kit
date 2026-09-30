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
import 'package:media_kit_video/src/video_controller/hdr_output_report.dart';

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
  Future<void>? _disposeFuture;
  Map<String, dynamic>? _lastNativeConfiguration;
  Map<String, dynamic>? _nativeWindowAttachment;
  int _nativeOutputTransaction = 0;
  int? _lastNativeOutputEpoch;
  int? _invalidatedNativeOutputEpoch;
  int? _nativeOutputEpochGeneration;
  bool _nativeOutputResetInFlight = false;
  Future<HdrOutputReport>? _nativeOutputResetFuture;

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
    // Native-window mode can skip createNativeOutput, so force installation
    // of the platform-channel handler before the PlatformView emits Ready.
    _channel;
    videoParamsSubscription = player.stream.videoParams.listen(
      (event) => lock.synchronized(() async {
        if (_disposed) return;
        if ([0, null].contains(event.dw) || [0, null].contains(event.dh)) {
          return;
        }

        final int handle = await player.handle;
        if (_disposed) return;

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

        if (configuration.useNativeWindow && Platform.isMacOS) {
          // The mpv-owned window has no Flutter texture ID. Use the stable
          // player handle only as a PlatformView mount signal; it is never a
          // native window handle and is never written to mpv's --wid.
          id.value ??= handle;
          rect.value = Rect.fromLTWH(
            0,
            0,
            width.toDouble(),
            height.toDouble(),
          );
          if (!waitUntilFirstFrameRenderedCompleter.isCompleted) {
            waitUntilFirstFrameRenderedCompleter.complete();
          }
          return;
        }

        await _channel.invokeMethod('VideoOutputManager.SetSize', {
          'handle': handle.toString(),
          'width': width.toString(),
          'height': height.toString(),
        });
      }),
    );
  }

  /// {@macro native_video_controller}
  static Future<PlatformVideoController> create(
    Player player,
    VideoControllerConfiguration configuration,
  ) {
    final darwin = Platform.isMacOS || Platform.isIOS;
    final admission = darwin
        ? (player.platform as NativePlayer).reservePreTerminationOwnerCreation()
        : null;
    if (darwin && admission == null) {
      throw StateError(
          'Cannot create native output while player is disposing.');
    }
    return _createAdmitted(player, configuration, admission)
        .whenComplete(() => admission?.release());
  }

  static Future<PlatformVideoController> _createAdmitted(
    Player player,
    VideoControllerConfiguration configuration,
    PreTerminationOwnerReservation? admission,
  ) async {
    void ensureAdmissionOpen() {
      if (admission != null &&
          (player.platform as NativePlayer)
              .isPreTerminationOwnerAdmissionClosed) {
        throw StateError('Native-output creation was canceled by disposal.');
      }
    }

    final nativeWindowMode = configuration.useNativeWindow && Platform.isMacOS;

    // Update [configuration] to have default values.
    configuration = configuration.copyWith(
      // W1 is specifically the gpu-next window experiment. Do not let the
      // normal Darwin `libmpv` default silently change the experiment into A.
      vo: nativeWindowMode ? 'gpu-next' : (configuration.vo ?? 'libmpv'),
      hwdec: configuration.hwdec ?? 'auto',
    );

    // Retrieve the native handle of the [Player].
    final handle = await player.handle;
    ensureAdmissionOpen();
    // Return the existing [VideoController] if it's already created.
    if (_controllers.containsKey(handle)) {
      return _controllers[handle]!;
    }

    // In case no video-decoders are found, this means media_kit_libs_***_audio is being used.
    // Thus, --vid=no is required to prevent libmpv from trying to decode video (otherwise bad things may happen).
    //
    // Search for common H264 decoder to check if video support is available.
    final decoders = await queryDecoders(handle);
    ensureAdmissionOpen();
    if (!decoders.contains('h264')) {
      throw UnsupportedError(
        '[VideoController] is not available.'
        ' '
        'Please use media_kit_libs_***_video instead of media_kit_libs_***_audio.',
      );
    }

    // A concurrent caller may have published the controller while decoder
    // discovery was in flight. Reuse that owner rather than registering two.
    if (_controllers.containsKey(handle)) {
      return _controllers[handle]!;
    }

    // Creation:
    final controller = NativeVideoController._(
      player,
      configuration,
    );
    controller.nativeHandle = handle;
    controller.nativeSurfaceGeneration = (_surfaceGenerations[handle] ?? 0) + 1;
    _surfaceGenerations[handle] = controller.nativeSurfaceGeneration;

    // Darwin's native output can own an mpv render context. Its disposal must
    // complete before the player's event pump and mpv handle are destroyed.
    // Other platforms retain their existing release-callback ordering.
    if (Platform.isMacOS || Platform.isIOS) {
      admission!.register(controller._dispose);
    } else {
      player.platform?.release.add(controller._dispose);
    }

    // Store the [NativeVideoController] in the [_controllers].
    _controllers[handle] = controller;

    await controller.setProperties({
      // The window backend must be detached before its NSView exists.
      'vo': nativeWindowMode ? 'null' : configuration.vo!,
      'hwdec': configuration.hwdec!,
      'vid': 'auto',
    });
    ensureAdmissionOpen();

    if (nativeWindowMode) {
      // W1 is intentionally opt-in and does not create VideoOutput/Texture.
      // The external gpu-next experiment must select an HDR target explicitly;
      // the source transfer alone does not make mpv's output target HDR.
      await controller.setProperties({
        'target-prim': 'bt.2020',
        'target-trc': 'linear',
      });
      ensureAdmissionOpen();
      // The PlatformView mount is driven by the first video-params event.
      controller.nativeSurfaceCandidate = true;
      controller.setNativeSurfaceActive(false);
      return controller;
    }

    if (configuration.useNativeSurface &&
        configuration.enableHardwareAcceleration &&
        (Platform.isIOS || Platform.isMacOS)) {
      try {
        final nativeResult = await controller.createNativeOutput();
        controller.nativeSurfaceCandidate = nativeResult.capable;
        controller.setNativeSurfaceActive(nativeResult.active);
      } catch (_) {
        // Missing native plugin/renderer is a normal fail-closed fallback.
        controller.setNativeSurfaceActive(false);
      }
      ensureAdmissionOpen();
    }

    // Wait until first texture ID is received.
    // We are not waiting on the native-side itself because it will block the UI thread.
    final completer = Completer<void>();
    void listener() {
      final value = controller.id.value;
      if (value != null && !completer.isCompleted) {
        debugPrint('NativeVideoController: Texture ID: $value');
        completer.complete();
      }
    }

    controller.id.addListener(listener);

    try {
      ensureAdmissionOpen();
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
      ensureAdmissionOpen();
      if (admission == null) {
        await completer.future;
      } else {
        await Future.any<void>([
          completer.future,
          (player.platform as NativePlayer).preTerminationOwnerAdmissionClosed,
        ]);
      }
      ensureAdmissionOpen();
    } finally {
      controller.id.removeListener(listener);
    }

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
  Future<HdrOutputReport> createNativeOutput(
      {String? surfaceId, int? windowHandle}) async {
    // Only a genuinely new surface generation starts a new epoch namespace.
    // Repeated create calls during HDR reconfiguration are idempotent on the
    // native side and must retain the old-event rejection boundary.
    if (_nativeOutputEpochGeneration != nativeSurfaceGeneration) {
      _lastNativeOutputEpoch = null;
      _invalidatedNativeOutputEpoch = null;
      _nativeOutputEpochGeneration = nativeSurfaceGeneration;
    }
    final handle = nativeHandle ?? await player.handle;
    final result = (await _channel.invokeMethod<Map<dynamic, dynamic>>(
              'createNativeOutput',
              {
                'handle': handle.toString(),
                'generation': nativeSurfaceGeneration
              },
            ) ??
            const <dynamic, dynamic>{})
        .cast<String, dynamic>();
    return HdrOutputReport.fromMap(result);
  }

  @override
  Future<HdrOutputReport> configureHdrOutput(
      Map<String, dynamic> configuration) async {
    final transaction = _nativeOutputTransaction;
    final handle = nativeHandle ?? await player.handle;
    if (transaction != _nativeOutputTransaction || _nativeOutputResetInFlight) {
      return const HdrOutputReport(active: false, stale: true);
    }
    final payload = Map<String, dynamic>.from(configuration);
    if (this.configuration.useNativeSurface) {
      // Darwin's native surface consumes extended-linear BT.2020 samples.
      // Keep the source transfer in the payload for EDR metadata, but do not
      // ask mpv to emit PQ/HLG code values into that linear surface.
      final darwinNative = Platform.isMacOS || Platform.isIOS;
      final transfer = payload['transfer'] as String?;
      final hdrInput = transfer == 'pq' || transfer == 'hlg';
      payload['target-prim'] = hdrInput ? 'bt.2020' : 'bt.709';
      payload['target-colorspace'] = payload['target-prim'];
      payload['target-trc'] = hdrInput && darwinNative
          ? 'linear'
          : (hdrInput ? (transfer == 'hlg' ? 'hlg' : 'pq') : 'bt.1886');
      try {
        // The app may have applied its conservative SDR parameters after the
        // controller was created. Re-assert the native target immediately
        // before reading it back, so verification observes the actual mpv
        // state rather than only the configuration payload.
        await setProperties({
          'target-prim': payload['target-prim'] as String,
          'target-trc': payload['target-trc'] as String,
        });
        final colorspace = await player.getProperty(
          'target-prim',
          waitForInitialization: false,
        );
        final transfer = await player.getProperty(
          'target-trc',
          waitForInitialization: false,
        );
        payload['playerTargetVerified'] =
            colorspace == payload['target-prim'] &&
                transfer == payload['target-trc'];
      } catch (_) {
        payload['playerTargetVerified'] = false;
      }
    }
    if (transaction != _nativeOutputTransaction) {
      return const HdrOutputReport(active: false, stale: true);
    }
    _lastNativeConfiguration = payload.cast<String, dynamic>();
    final result = (await _channel.invokeMethod<Map<dynamic, dynamic>>(
              'configureHdrOutput',
              {
                'handle': handle.toString(),
                'generation': nativeSurfaceGeneration,
                'configuration': payload,
              },
            ) ??
            const <dynamic, dynamic>{})
        .cast<String, dynamic>();
    if (transaction != _nativeOutputTransaction) {
      return const HdrOutputReport(active: false, stale: true);
    }
    final epoch = result['outputEpoch'];
    if (epoch is int) _lastNativeOutputEpoch = epoch;
    return HdrOutputReport.fromMap(result);
  }

  @override
  Future<HdrOutputReport> resetHdrOutput() async {
    final existing = _nativeOutputResetFuture;
    if (existing != null) return existing;
    // Invalidate the Dart-side replay payload before crossing the channel.
    // A late renderer-ready callback must not reconfigure a reset generation.
    _lastNativeConfiguration = null;
    _invalidatedNativeOutputEpoch = _lastNativeOutputEpoch;
    _nativeOutputTransaction++;
    _nativeOutputResetInFlight = true;
    setNativeSurfaceActive(false);
    late Future<HdrOutputReport> resetFuture;
    var resetSucceeded = false;
    resetFuture = () async {
      try {
        final handle = nativeHandle ?? await player.handle;
        final result = (await _channel.invokeMethod<Map<dynamic, dynamic>>(
                  'resetHdrOutput',
                  {
                    'handle': handle.toString(),
                    'generation': nativeSurfaceGeneration
                  },
                ) ??
                const <dynamic, dynamic>{})
            .cast<String, dynamic>();
        final resetEpoch = result['outputEpoch'];
        if (resetEpoch is int) {
          _invalidatedNativeOutputEpoch = resetEpoch;
          _lastNativeOutputEpoch = resetEpoch;
          resetSucceeded = true;
        }
        return HdrOutputReport.fromMap(result);
      } finally {
        if (identical(_nativeOutputResetFuture, resetFuture)) {
          _nativeOutputResetFuture = null;
          if (resetSucceeded) _nativeOutputResetInFlight = false;
        }
      }
    }();
    _nativeOutputResetFuture = resetFuture;
    return resetFuture;
  }

  @override
  Future<void> disposeNativeOutput() async {
    final handle = nativeHandle ?? await player.handle;
    await _channel.invokeMethod('disposeNativeOutput', {
      'handle': handle.toString(),
      'generation': nativeSurfaceGeneration,
    });
  }

  /// Attaches the generation-scoped Cocoa view after the Flutter PlatformView
  /// exists. W0 only observes the view; W1's opt-in native-window mode uses
  /// the returned handle for one immediate `wid` binding.
  Future<Map<String, dynamic>> attachNativeWindow() async {
    if (_disposed ||
        !Platform.isMacOS ||
        (!configuration.useNativeSurface && !configuration.useNativeWindow)) {
      return const <String, dynamic>{
        'capable': false,
        'attached': false,
        'failureReason': 'not a macOS native-surface output',
      };
    }
    return lock.synchronized(() async {
      if (_disposed) {
        return const <String, dynamic>{
          'capable': false,
          'attached': false,
          'failureReason': 'controller disposed',
        };
      }
      final handle = nativeHandle ?? await player.handle;
      final result = (await _channel.invokeMethod<Map<dynamic, dynamic>>(
                'NativeWindow.Attach',
                {
                  'handle': handle.toString(),
                  'generation': nativeSurfaceGeneration,
                },
              ) ??
              const <dynamic, dynamic>{})
          .cast<String, dynamic>();
      if (_disposed) {
        if (result['attached'] == true) {
          await _channel.invokeMethod(
            'NativeWindow.Detach',
            {
              'handle': handle.toString(),
              'generation': nativeSurfaceGeneration,
            },
          );
        }
        return const <String, dynamic>{
          'capable': false,
          'attached': false,
          'failureReason': 'controller disposed',
        };
      }
      if (result['capable'] == true && result['attached'] == true) {
        // Keep lifecycle state only. Never retain the native view address in
        // the controller after the immediate W1 bind call has consumed it.
        _nativeWindowAttachment = {
          'attached': true,
          'handle': result['handle'],
          'generation': result['generation'],
        };
      }
      return result;
    });
  }

  /// Invalidates the W0 Cocoa view token before the controller is disposed.
  Future<void> detachNativeWindow() async {
    if (_nativeWindowAttachment == null) return;
    // A failed mpv stop or channel detachment must leave the attachment
    // available for a later disposal attempt.
    setNativeSurfaceActive(false);

    if (configuration.useNativeWindow && Platform.isMacOS) {
      Future<void> setOutputProperty(String property, String value) =>
          platform.isPreTerminationCallbacksActive
              ? platform.setPropertyStrictAsyncForPreTermination(
                  property,
                  value,
                )
              : platform.setPropertyStrictAsync(
                  property,
                  value,
                  waitForInitialization: false,
                );
      // These mpv-owned window transitions must receive successful async
      // replies before Cocoa is allowed to release the NSView.
      await setOutputProperty('vo', 'null');
      await setOutputProperty('wid', '0');
    }
    final handle = nativeHandle ?? await player.handle;
    await _channel.invokeMethod(
      'NativeWindow.Detach',
      {
        'handle': handle.toString(),
        'generation': nativeSurfaceGeneration,
      },
    );
    _nativeWindowAttachment = null;
  }

  /// Reads the native Cocoa view frame without treating the video resolution
  /// as the PlatformView layout size.
  Future<Map<String, dynamic>> nativeWindowState() async {
    if (!Platform.isMacOS ||
        (!configuration.useNativeSurface && !configuration.useNativeWindow)) {
      return const <String, dynamic>{
        'capable': false,
        'attached': false,
        'failureReason': 'not a macOS native-surface output',
      };
    }
    final handle = nativeHandle ?? await player.handle;
    final result = (await _channel.invokeMethod<Map<dynamic, dynamic>>(
              'NativeWindow.State',
              {
                'handle': handle.toString(),
                'generation': nativeSurfaceGeneration,
              },
            ) ??
            const <dynamic, dynamic>{})
        .cast<String, dynamic>();
    return result;
  }

  /// W1-only bridge: consume the native view address immediately and do not
  /// retain it after the `wid` property has been sent to mpv.
  ///
  /// A successful return means that the attachment was accepted and the
  /// asynchronous mpv transition was issued. It does not mean that gpu-next
  /// has initialized, rendered a frame, or produced visible pixels. Those
  /// facts must be established by native/player/output evidence separately.
  Future<bool> bindExperimentalNativeWindow(
    Map<String, dynamic> attachment,
  ) async {
    if (_disposed || !Platform.isMacOS || !configuration.useNativeWindow) {
      return false;
    }
    final nativeViewHandle = attachment['nativeViewHandle'];
    if (nativeViewHandle is! num || nativeViewHandle == 0) return false;
    var bound = false;
    await lock.synchronized(() async {
      if (_disposed) return;
      // A synchronous mpv_set_property can wait in vo_create while Cocoa
      // needs the Flutter main thread. Use mpv_command_async for the
      // mpv-owned window transition so the main thread remains pumpable.
      await platform.command(
        ['set', 'vo', 'null'],
        waitForInitialization: false,
      );
      await platform.command(
        ['set', 'wid', nativeViewHandle.toInt().toString()],
        waitForInitialization: false,
      );
      await platform.command(
        ['set', 'gpu-api', 'vulkan'],
        waitForInitialization: false,
      );
      await platform.command(
        ['set', 'vo', configuration.vo ?? 'gpu-next'],
        waitForInitialization: false,
      );
      bound = !_disposed;
    });
    if (!bound) return false;
    // Do not promote `nativeSurfaceActive` here. Sending `vo`, `wid`, and
    // `gpu-api` is only a setup request; mpv's async command completion does
    // not prove renderer initialization or a visible frame.
    setNativeSurfaceActive(false);
    return true;
  }

  /// Disposes the instance. Releases allocated resources back to the system.
  @override
  Future<void> disposeForRebuild() => _dispose();

  /// Disposes the instance. Releases allocated resources back to the system.
  Future<void> _dispose() => _disposeFuture ??= _disposeOnce();

  Future<void> _disposeOnce() async {
    _disposed = true;
    _nativeOutputTransaction++;
    _lastNativeConfiguration = null;
    nativeSurfaceCandidate = false;
    // Publish the inactive edge while the notifier is still alive. All later
    // callbacks observe [_disposed] and must not write to disposed notifiers.
    super.setNativeSurfaceActive(false);

    Object? cleanupError;
    StackTrace? cleanupStack;
    void recordFailure(Object error, StackTrace stack) {
      cleanupError ??= error;
      cleanupStack ??= stack;
    }

    final subscription = videoParamsSubscription;
    videoParamsSubscription = null;
    try {
      await subscription?.cancel();
    } catch (error, stack) {
      recordFailure(error, stack);
    }

    // Stream callbacks and native-window binds use this lock. Drain any work
    // that started before [_disposed] was published before releasing native
    // objects referenced by that work.
    try {
      await lock.synchronized(() async {});
    } catch (error, stack) {
      recordFailure(error, stack);
    }

    try {
      await detachNativeWindow();
    } catch (error, stack) {
      recordFailure(error, stack);
    }
    try {
      await disposeNativeOutput();
    } catch (error, stack) {
      recordFailure(error, stack);
    }

    final handle = nativeHandle;
    if (!(configuration.useNativeWindow && Platform.isMacOS) &&
        handle != null) {
      try {
        // Darwin completes this method only after VideoOutput disposal has
        // released its mpv render context. Awaiting it is the barrier that
        // keeps Player teardown from terminating libmpv too early.
        await _channel.invokeMethod(
          'VideoOutputManager.Dispose',
          {
            'handle': handle.toString(),
          },
        );
      } catch (error, stack) {
        recordFailure(error, stack);
      }
    }

    if (cleanupError != null) {
      // Keep the notifier and controller registration alive for a later
      // caller to retry the render-context barrier. Destroying either here
      // would make a failed output release unrecoverable while libmpv is
      // still required to stay alive.
      _disposeFuture = null;
      Error.throwWithStackTrace(cleanupError!, cleanupStack!);
    }
    _controllers.removeWhere((_, controller) => identical(controller, this));
    _nativeWindowAttachment = null;
    _nativeOutputResetFuture = null;
    _nativeOutputResetInFlight = false;
    super.dispose();
  }

  @override
  void setNativeSurfaceActive(bool value) {
    if (_disposed) return;
    super.setNativeSurfaceActive(value);
  }

  /// Currently created [NativeVideoController]s.
  /// This is used to notify about updated texture IDs & [Rect]s through [_channel].
  static final _controllers = HashMap<int, NativeVideoController>();
  static final _surfaceGenerations = HashMap<int, int>();

  /// [MethodChannel] for invoking platform specific native implementation.
  static final _channel = const MethodChannel(
      'com.alexmercerind/media_kit_video')
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
                if (_controllers[handle]?._disposed ?? true) break;
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
              if (controller?._disposed ?? true) return;
              final generation = call.arguments['generation'] as int?;
              final transaction = controller?._nativeOutputTransaction;
              final hasRendererState = call.arguments is Map &&
                  (call.arguments as Map).containsKey('rendererReady');
              final rendererReady = call.arguments['rendererReady'] == true;
              final eventEpoch = call.arguments['outputEpoch'];
              if (controller?._nativeOutputResetInFlight == true) {
                return;
              }
              if (eventEpoch is int &&
                  controller?._invalidatedNativeOutputEpoch is int &&
                  eventEpoch <= controller!._invalidatedNativeOutputEpoch!) {
                return;
              }
              if (controller != null &&
                  generation == controller.nativeSurfaceGeneration) {
                // A failed native renderer must immediately return to the
                // Flutter texture path; do not leave a black platform view.
                if (hasRendererState) {
                  controller.nativeSurfaceCandidate = rendererReady;
                  if (!rendererReady) {
                    controller.setNativeSurfaceActive(false);
                  }
                }
                if (!hasRendererState && call.arguments['active'] is bool) {
                  controller
                      .setNativeSurfaceActive(call.arguments['active'] == true);
                }
              }
              final configuration = controller?._lastNativeConfiguration;
              if (controller != null &&
                  rendererReady &&
                  generation == controller.nativeSurfaceGeneration &&
                  Platform.isMacOS) {
                final attachment = await controller.attachNativeWindow();
                if (controller._disposed ||
                    transaction != controller._nativeOutputTransaction) {
                  return;
                }
                if (attachment['attached'] == true) {
                  final state = await controller.nativeWindowState();
                  debugPrint('NativeWindow.State: $state');
                  if (controller.configuration.useNativeWindow) {
                    final bound = await controller
                        .bindExperimentalNativeWindow(attachment);
                    debugPrint('NativeWindow.Bind: bound=$bound');
                  }
                }
              }
              if (controller != null &&
                  rendererReady &&
                  generation == controller.nativeSurfaceGeneration &&
                  transaction == controller._nativeOutputTransaction &&
                  configuration != null) {
                final result =
                    await controller.configureHdrOutput(configuration);
                if (controller._disposed ||
                    transaction != controller._nativeOutputTransaction ||
                    result.stale) {
                  // A reset or newer output transaction superseded this
                  // Ready callback. Never publish its false result over a
                  // newer active native surface.
                  return;
                }
                if (controller.configuration.useNativeWindow) {
                  // W1's mpv-owned window has no verified visible-frame
                  // callback yet. NativeSurfaceOutput readiness alone
                  // must not promote the separate child-window path.
                  controller.setNativeSurfaceActive(false);
                } else {
                  controller.setNativeSurfaceActive(result.active);
                }
              }
              break;
            case 'NativeWindow.Frame':
              if (call.arguments is Map) {
                debugPrint(
                  'NativeWindow.Frame: ${call.arguments}',
                );
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
