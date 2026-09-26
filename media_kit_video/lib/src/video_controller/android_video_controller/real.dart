/// This file is a part of media_kit (https://github.com/media-kit/media-kit).
///
/// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
/// All rights reserved.
/// Use of this source code is governed by MIT license that can be found in the LICENSE file.
import 'dart:io';
import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:synchronized/synchronized.dart';

import 'package:media_kit/media_kit.dart';

import 'package:media_kit_video/src/utils/query_decoders.dart';
import 'package:media_kit_video/src/video_controller/platform_video_controller.dart';

import 'current_output_intent.dart';

// Diagnostic only: keep a 4K input while matching the Texture buffer to the
// known 16:9 display region. Production sizing must come from widget layout.
const _textureOutputMaxWidth = int.fromEnvironment(
  'MEDIA_KIT_ANDROID_TEXTURE_OUTPUT_MAX_WIDTH',
  defaultValue: 0,
);
// Diagnostic only: hold native Surface buffer resolution at the Texture
// experiment's width while preserving the same source and GPU renderer.
const _platformOutputMaxWidth = int.fromEnvironment(
  'MEDIA_KIT_ANDROID_PLATFORM_OUTPUT_MAX_WIDTH',
  defaultValue: 0,
);

@visibleForTesting
Size calculateAndroidTextureOutputSize(Size source, Size viewport, BoxFit fit) {
  if (source.width <= 0 ||
      source.height <= 0 ||
      viewport.width <= 0 ||
      viewport.height <= 0) {
    return source;
  }
  final fitted = applyBoxFit(fit, source, viewport);
  final destination = fitted.destination;
  if (fit == BoxFit.fill) {
    return Size(
      destination.width.ceil().clamp(1, source.width.toInt()).toDouble(),
      destination.height.ceil().clamp(1, source.height.toInt()).toDouble(),
    );
  }
  // For cover, applyBoxFit crops its source before reporting the viewport
  // destination. Render the *whole* source at that scale so FittedBox can
  // clip it without losing the requested content.
  final scale = (destination.width / fitted.source.width).clamp(0.0, 1.0);
  return Size(
    (source.width * scale).ceil().clamp(1, source.width.toInt()).toDouble(),
    (source.height * scale).ceil().clamp(1, source.height.toInt()).toDouble(),
  );
}

@visibleForTesting
Size calculateAndroidTextureOutputSizeForLayouts(
    Size source, List<TextureOutputLayout> layouts) {
  if (source.width <= 0 || source.height <= 0 || layouts.isEmpty) {
    return source;
  }
  if (layouts.length == 1) {
    final layout = layouts.single;
    return calculateAndroidTextureOutputSize(
        source, layout.viewport, layout.fit);
  }
  var maxScale = 0.0;
  for (final layout in layouts) {
    final target =
        calculateAndroidTextureOutputSize(source, layout.viewport, layout.fit);
    final requiredScale = math
        .max(
          target.width / source.width,
          target.height / source.height,
        )
        .clamp(0.0, 1.0);
    if (requiredScale > maxScale) maxScale = requiredScale;
  }
  // One shared Texture cannot have a different aspect for each Video widget.
  // Keep source aspect and enough pixels for the most demanding owner.
  return Size(
    (source.width * maxScale).ceil().clamp(1, source.width.toInt()).toDouble(),
    (source.height * maxScale)
        .ceil()
        .clamp(1, source.height.toInt())
        .toDouble(),
  );
}

class _AndroidPlatformSurfaceOwner {
  final int handle;
  final int generation;
  final int viewId;
  final int surfaceGeneration;
  final int wid;

  const _AndroidPlatformSurfaceOwner({
    required this.handle,
    required this.generation,
    required this.viewId,
    required this.surfaceGeneration,
    required this.wid,
  });

  @override
  bool operator ==(Object other) =>
      other is _AndroidPlatformSurfaceOwner &&
      handle == other.handle &&
      generation == other.generation &&
      viewId == other.viewId &&
      surfaceGeneration == other.surfaceGeneration &&
      wid == other.wid;

  @override
  int get hashCode =>
      Object.hash(handle, generation, viewId, surfaceGeneration, wid);
}

/// {@template android_video_controller}
///
/// AndroidVideoController
/// ----------------------
///
/// The [PlatformVideoController] implementation based on native JNI & C/C++ used on Android.
///
/// {@endtemplate}
class AndroidVideoController extends PlatformVideoController {
  /// Whether [AndroidVideoController] is supported on the current platform or not.
  static bool get supported => Platform.isAndroid;

  /// Pointer address to the global object reference of `android.view.Surface` i.e. `(intptr_t)(*android.view.Surface)`.
  final ValueNotifier<int?> wid = ValueNotifier<int?>(null);
  Future<void> Function()? _playerReleaseCallback;

  final _initialPlatformViewOutputBound = Completer<void>();
  Completer<void> _currentPlatformViewOutputBound = Completer<void>();
  bool _currentPlatformOutputUnavailable = true;
  final _outputIntent = CurrentOutputIntent<_AndroidPlatformSurfaceOwner>();

  @override
  Future<void> get waitUntilInitialOutputBound =>
      (configuration.usePlatformView ||
              !configuration.enableAndroidSurfaceProducer)
          ? _initialPlatformViewOutputBound.future
          : Future<void>.value();

  @override
  Future<void> get waitUntilCurrentOutputBound {
    if (!configuration.usePlatformView) return waitUntilInitialOutputBound;
    if (_disposed || _fullyDisposed) {
      return Future<void>.error(StateError('Android output is disposed'));
    }
    if (!_currentPlatformOutputUnavailable &&
        wid.value != null &&
        _platformViewId != null &&
        _inFlightSurfaceOwner == null) {
      return Future<void>.value();
    }
    return _currentPlatformViewOutputBound.future;
  }

  void _invalidateCurrentOutputBound() {
    _currentPlatformOutputUnavailable = true;
    if (_currentPlatformViewOutputBound.isCompleted) {
      _currentPlatformViewOutputBound = Completer<void>();
    }
  }

  void _failCurrentOutputBound(Object error, StackTrace stack) {
    if (!_currentPlatformViewOutputBound.isCompleted) {
      _currentPlatformViewOutputBound.completeError(error, stack);
      // A waiter may not have subscribed yet. Consume the error on this
      // branch while preserving it for any caller holding the same Future.
      unawaited(
          _currentPlatformViewOutputBound.future.catchError((Object _) {}));
    }
  }

  void _markSurfaceDestroyedBeforeDetach(
    int handle,
    int expectedWid,
    int generation,
    int viewId,
    int surfaceGeneration,
  ) {
    final owner = _surfaceOwner(
      handle: handle,
      generation: generation,
      viewId: viewId,
      surfaceGeneration: surfaceGeneration,
      wid: expectedWid,
    );
    if (_outputIntent.destroy(owner)) {
      _invalidateCurrentOutputBound();
    } else if (_outputIntent.expected == null &&
        wid.value == expectedWid &&
        nativeSurfaceGeneration == generation &&
        _platformViewId == viewId &&
        _platformSurfaceGeneration == surfaceGeneration) {
      _invalidateCurrentOutputBound();
    }
  }

  int _markSurfaceBindBeforeAwait(
    int handle,
    int generation,
    int viewId,
    int surfaceGeneration,
    int widValue,
  ) {
    final expected = _outputIntent.expected;
    if (expected != null &&
        expected.viewId == viewId &&
        surfaceGeneration < expected.surfaceGeneration) {
      return _outputIntent.serial;
    }
    if (nativeSurfaceGeneration == generation &&
        (_platformViewId != viewId ||
            surfaceGeneration >= _platformSurfaceGeneration)) {
      final owner = _surfaceOwner(
        handle: handle,
        generation: generation,
        viewId: viewId,
        surfaceGeneration: surfaceGeneration,
        wid: widValue,
      );
      _outputIntent.bind(owner);
      _invalidateCurrentOutputBound();
    }
    return _outputIntent.serial;
  }

  /// [Lock] used to synchronize [onLoadHooks], [onUnloadHooks] & [subscription].
  final lock = Lock();
  bool _disposed = false;
  bool _fullyDisposed = false;
  bool _published = false;
  bool _playerTerminated = false;
  bool _videoOutputCreated = false;
  Future<Map<String, dynamic>?>? _nativeTextureCreation;
  Future<void>? _disposeFuture;
  Future<void>? _terminalDisposeFuture;
  late final Future<void> Function() _postTerminationCallback;
  int? _platformViewId;
  int _platformSurfaceGeneration = 0;
  _AndroidPlatformSurfaceOwner? _inFlightSurfaceOwner;
  final Set<_AndroidPlatformSurfaceOwner> _pendingSurfaceReleases = {};
  Size? _sourceDisplaySize;
  final _textureLayoutRegistry = TextureOutputLayoutRegistry();
  Size? _appliedVideoSizeRequest;

  bool get _layoutSizedTexture =>
      configuration.matchAndroidTextureOutputToLayout &&
      !configuration.usePlatformView &&
      !configuration.enableAndroidSurfaceProducer;

  @override
  Future<void> updateTextureLayouts(
      Object owner, List<TextureOutputLayout> layouts) {
    if (!_layoutSizedTexture) return Future<void>.value();
    return lock.synchronized(() async {
      if (_disposed || _fullyDisposed) return;
      _textureLayoutRegistry.update(owner, layouts);
      await _applyVideoSizeLocked();
    });
  }

  Future<void> _applyVideoSizeLocked() async {
    final source = _sourceDisplaySize;
    if (source == null || source.width <= 0 || source.height <= 0) return;
    int width = source.width.toInt();
    int height = source.height.toInt();
    final textureLayouts = _textureLayoutRegistry.layouts;
    if (_layoutSizedTexture && textureLayouts.isNotEmpty) {
      final target =
          calculateAndroidTextureOutputSizeForLayouts(source, textureLayouts);
      width = target.width.toInt();
      height = target.height.toInt();
    }
    if (!configuration.usePlatformView &&
        _textureOutputMaxWidth > 0 &&
        width > _textureOutputMaxWidth) {
      height =
          (height * _textureOutputMaxWidth / width).round().clamp(1, height);
      width = _textureOutputMaxWidth;
      debugPrint('ANDROID_TEXTURE_OUTPUT_SIZE source='
          '${source.width.toInt()}x${source.height.toInt()} '
          'target=${width}x$height');
    }
    if (configuration.usePlatformView &&
        _platformOutputMaxWidth > 0 &&
        width > _platformOutputMaxWidth) {
      height =
          (height * _platformOutputMaxWidth / width).round().clamp(1, height);
      width = _platformOutputMaxWidth;
      debugPrint('ANDROID_PLATFORM_OUTPUT_SIZE source='
          '${source.width.toInt()}x${source.height.toInt()} '
          'target=${width}x$height');
    }
    final requestedSize = Size(width.toDouble(), height.toDouble());
    if (_appliedVideoSizeRequest == requestedSize) return;
    final handle = await player.handle;
    if (_disposed || _fullyDisposed) return;
    if (!configuration.usePlatformView) {
      final actual = await _channel.invokeMapMethod<String, dynamic>(
        'VideoOutputManager.SetSurfaceSize',
        {
          'handle': handle.toString(),
          'width': width.toString(),
          'height': height.toString(),
        },
      );
      if (_layoutSizedTexture) {
        final actualWidth = (actual?['width'] as num?)?.toInt();
        final actualHeight = (actual?['height'] as num?)?.toInt();
        if (actualWidth == null ||
            actualWidth <= 0 ||
            actualHeight == null ||
            actualHeight <= 0) {
          throw StateError('SurfaceTexture resize had no valid size ACK.');
        }
        width = actualWidth;
        height = actualHeight;
      }
    }
    if (_disposed || _fullyDisposed) return;
    if (wid.value != null &&
        (configuration.usePlatformView ||
            !configuration.enableAndroidSurfaceProducer)) {
      // The Surface identity is unchanged. A dynamic size property avoids a
      // VO rebind and the seek that belongs only to a new Surface.
      await _setOutputProperty('android-surface-size', '${width}x$height');
      _traceSurface(
          'size property complete android-surface-size=${width}x$height');
    }
    if (_disposed || _fullyDisposed) return;
    rect.value = Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
    _appliedVideoSizeRequest = requestedSize;
    if (!waitUntilFirstFrameRenderedCompleter.isCompleted) {
      waitUntilFirstFrameRenderedCompleter.complete();
    }
  }

  static const Duration _surfaceReleaseTimeout = Duration(seconds: 2);
  static const Duration _surfaceReleaseOwnerAckTimeout = Duration(seconds: 2);
  static const Duration _playerTerminatedTimeout = Duration(seconds: 2);
  static const bool _surfaceTimeline = bool.fromEnvironment(
    'MEDIA_KIT_ANDROID_SURFACE_TIMELINE',
  );

  void _traceSurface(String event) {
    if (_surfaceTimeline) {
      debugPrint('SURFACE_TIMELINE ${DateTime.now().toIso8601String()} $event');
    }
  }

  NativePlayer get platform => player.platform as NativePlayer;

  Future<void> setProperty(String key, String value) async {
    await platform.setProperty(key, value, waitForInitialization: false);
  }

  Future<void> setProperties(Map<String, String> properties) async {
    for (final entry in properties.entries) {
      await platform.setPropertyStrict(
        entry.key,
        entry.value,
        waitForInitialization: false,
      );
    }
  }

  Future<void> _setOutputProperty(String key, String value) {
    // Player.dispose marks the player disposed before invoking release
    // callbacks. Only the dedicated release setter is valid in that window.
    if (platform.isReleaseCallbacksActive) {
      return platform.setPropertyStrictForRelease(key, value);
    }
    return platform.setPropertyStrict(
      key,
      value,
      waitForInitialization: false,
    );
  }

  /// Listener for updating the --wid property.
  Future<void> widListener() {
    return lock.synchronized(
      () {
        if (_disposed) return Future<void>.value();
        return _applyWidLocked(seekAfterSurfaceBind: true);
      },
    );
  }

  Future<void> _applyWidLocked({
    bool seekAfterSurfaceBind = false,
    String? widValueOverride,
  }) async {
    final width = rect.value?.width.toInt() ?? 1;
    final height = rect.value?.height.toInt() ?? 1;
    final androidSurfaceSizeValue = [width, height].join('x');
    final widValue = widValueOverride ?? wid.value?.toString() ?? '0';
    // When --wid is 0, vo=null is required to avoid SIGSEGV.
    final voValue = widValue == '0' ? 'null' : configuration.vo!;
    final vidValue = widValue == '0' ? 'no' : 'auto';
    _traceSurface('apply begin wid=$widValue vo=$voValue vid=$vidValue');
    // It is important to re-initialize --vo after --android-surface-size.
    await _setOutputProperty('vo', 'null');
    _traceSurface('property complete vo=null');
    final properties = <String, String>{
      // ORDER IS IMPORTANT.
      'android-surface-size': androidSurfaceSizeValue,
      'wid': widValue,
      'vo': voValue,
      // It is important to re-initialize --vid in-case of --vo=mediacodec_embed.
      // Not doing so causes error "Could not open codec." & video never gets rendered.
      if (configuration.usePlatformView ||
          (configuration.vo == 'mediacodec_embed' &&
              !configuration.usePlatformView))
        'vid': vidValue,
    };
    for (final entry in properties.entries) {
      await _setOutputProperty(entry.key, entry.value);
      _traceSurface('property complete ${entry.key}=${entry.value}');
    }
    _traceSurface('apply complete wid=$widValue');
    // A new Surface needs a seek at the current position to resume its output.
    // A video-parameter size update reuses the same Surface and must not seek:
    // seeking at position zero while the HEVC reference queue is forming can
    // discard references before the first frame is rendered.
    if (widValue != '0' &&
        seekAfterSurfaceBind &&
        player.state.playlist.medias.isNotEmpty) {
      final currentPosition = player.state.position;
      await player.seek(currentPosition);
    }
  }

  Future<void> _detachPlatformSurface(
    int expectedWid,
    int generation,
    int viewId,
    int surfaceGeneration,
  ) async {
    _traceSurface(
        'detach requested wid=$expectedWid surfaceGeneration=$surfaceGeneration');
    await lock.synchronized(() async {
      final owner = _AndroidPlatformSurfaceOwner(
        handle: nativeHandle ?? await player.handle,
        generation: generation,
        viewId: viewId,
        surfaceGeneration: surfaceGeneration,
        wid: expectedWid,
      );
      _pendingSurfaceReleases.add(owner);
      if (_fullyDisposed) {
        await _releaseSurfaceOwnerLocked(owner);
        return;
      }
      if (_playerTerminated) {
        _clearSurfaceOwner(owner);
        await _releaseSurfaceOwnerLocked(owner);
        return;
      }
      if (_disposed && !platform.isReleaseCallbacksActive) {
        // Initializer may already have stopped the event pump. Retain the
        // owner for the post-mpv_terminate_destroy callback; never await an
        // asynchronous property reply in this interval.
        return;
      }
      final isCurrentOutput = _isBoundSurfaceOwner(owner);
      final isInFlightOutput = _inFlightSurfaceOwner == owner;
      if (isCurrentOutput || isInFlightOutput) {
        // Do not enqueue a second listener behind this lock: Java may release
        // the JNI reference only after mpv has observed wid=0 and vo=null.
        wid.removeListener(widListener);
        try {
          // Keep the Dart identity intact until every native property write
          // succeeds. A partial failure remains retryable and is never ACKed.
          await _applyWidLocked(widValueOverride: '0');
          _traceSurface('detach producer stopped wid=$expectedWid');
          _clearSurfaceOwner(owner);
        } finally {
          if (!_disposed) wid.addListener(widListener);
        }
      }
      // A late destroy for old A after B is bound must still reclaim A, but it
      // must not touch B's producer state. The complete identity selects the
      // exact Java owner even when a JNI pointer address is later reused.
      await _releaseSurfaceOwnerLocked(owner);
      _traceSurface('detach reference released wid=$expectedWid');
    });
  }

  bool _isBoundSurfaceOwner(_AndroidPlatformSurfaceOwner owner) {
    return nativeSurfaceGeneration == owner.generation &&
        _platformViewId == owner.viewId &&
        _platformSurfaceGeneration == owner.surfaceGeneration &&
        wid.value == owner.wid;
  }

  _AndroidPlatformSurfaceOwner? _boundSurfaceOwner(int handle) {
    final widValue = wid.value;
    final viewId = _platformViewId;
    if (widValue == null || viewId == null) return null;
    return _surfaceOwner(
      handle: handle,
      generation: nativeSurfaceGeneration,
      viewId: viewId,
      surfaceGeneration: _platformSurfaceGeneration,
      wid: widValue,
    );
  }

  void _clearSurfaceOwner(_AndroidPlatformSurfaceOwner owner) {
    if (_isBoundSurfaceOwner(owner)) {
      wid.value = null;
      _platformViewId = null;
      _platformSurfaceGeneration = 0;
      _invalidateCurrentOutputBound();
    }
    if (_inFlightSurfaceOwner == owner) {
      _inFlightSurfaceOwner = null;
    }
  }

  Future<void> _releaseSurfaceOwnerLocked(
    _AndroidPlatformSurfaceOwner owner,
  ) async {
    await _releasePlatformSurfaceReference(owner);
    _pendingSurfaceReleases.remove(owner);
  }

  Future<void> _drainPendingSurfaceReleasesLocked({
    _AndroidPlatformSurfaceOwner? except,
  }) async {
    for (final owner in _pendingSurfaceReleases.toList()) {
      if (owner == except) continue;
      await _releaseSurfaceOwnerLocked(owner);
    }
  }

  static Future<void> _releasePlatformSurfaceReference(
    _AndroidPlatformSurfaceOwner owner,
  ) async {
    final status = await _channel.invokeMethod<String>(
      'PlatformVideoView.ReleaseSurface',
      {
        'handle': owner.handle.toString(),
        'generation': owner.generation,
        'viewId': owner.viewId,
        'surfaceGeneration': owner.surfaceGeneration,
        'wid': owner.wid.toString(),
      },
    ).timeout(_surfaceReleaseTimeout);
    if (status != 'released' && status != 'alreadyReleased') {
      throw StateError(
        'PlatformVideoView.ReleaseSurface rejected '
        '${owner.generation}/${owner.viewId}/'
        '${owner.surfaceGeneration}/${owner.wid}: $status',
      );
    }
    // Keep ReleaseSurface idempotent until its result has reached Dart. The
    // second call is the explicit Dart ACK that may remove Java's tombstone.
    // If it fails, retain the Dart pending owner so retry observes
    // alreadyReleased and can repeat this exact acknowledgement.
    final acknowledged = await _channel.invokeMethod<bool>(
      'PlatformVideoView.ReleaseSurfaceOwner',
      {
        'handle': owner.handle.toString(),
        'generation': owner.generation,
        'viewId': owner.viewId,
        'surfaceGeneration': owner.surfaceGeneration,
        'wid': owner.wid.toString(),
      },
    ).timeout(_surfaceReleaseOwnerAckTimeout);
    if (acknowledged != true) {
      throw StateError(
        'PlatformVideoView.ReleaseSurfaceOwner did not acknowledge '
        '${owner.generation}/${owner.viewId}/'
        '${owner.surfaceGeneration}/${owner.wid}.',
      );
    }
  }

  static const int _maxOrphanReleaseAttempts = 3;
  static final Map<_AndroidPlatformSurfaceOwner, int>
      _orphanSurfaceReleaseAttempts = {};
  static final Map<_AndroidPlatformSurfaceOwner, Timer> _orphanReleaseTimers =
      {};

  static Future<void> _releaseOrphanPlatformSurface(
    _AndroidPlatformSurfaceOwner owner,
  ) async {
    _orphanSurfaceReleaseAttempts.putIfAbsent(owner, () => 0);
    try {
      await _releasePlatformSurfaceReference(owner);
      _orphanSurfaceReleaseAttempts.remove(owner);
      _orphanReleaseTimers.remove(owner)?.cancel();
    } catch (_) {
      _scheduleOrphanSurfaceRetry(owner);
      rethrow;
    }
  }

  static void _scheduleOrphanSurfaceRetry(
    _AndroidPlatformSurfaceOwner owner,
  ) {
    if (_orphanReleaseTimers.containsKey(owner)) return;
    final attempts = _orphanSurfaceReleaseAttempts[owner] ?? 0;
    if (attempts >= _maxOrphanReleaseAttempts) {
      debugPrint(
        'PlatformVideoView orphan release exhausted: '
        '${owner.handle}/${owner.generation}/${owner.viewId}/'
        '${owner.surfaceGeneration}/${owner.wid}',
      );
      return;
    }
    _orphanReleaseTimers[owner] = Timer(const Duration(seconds: 1), () async {
      _orphanReleaseTimers.remove(owner);
      _orphanSurfaceReleaseAttempts[owner] = attempts + 1;
      try {
        await _releasePlatformSurfaceReference(owner);
        _orphanSurfaceReleaseAttempts.remove(owner);
      } catch (exception, stacktrace) {
        debugPrint(exception.toString());
        debugPrint(stacktrace.toString());
        _scheduleOrphanSurfaceRetry(owner);
      }
    });
  }

  static _AndroidPlatformSurfaceOwner _surfaceOwner({
    required int handle,
    required int generation,
    required int viewId,
    required int surfaceGeneration,
    required int wid,
  }) {
    return _AndroidPlatformSurfaceOwner(
      handle: handle,
      generation: generation,
      viewId: viewId,
      surfaceGeneration: surfaceGeneration,
      wid: wid,
    );
  }

  Future<void> _bindPlatformViewSurface({
    required int widValue,
    required int generation,
    required int viewId,
    required int surfaceGeneration,
    required int outputIntentSerial,
  }) async {
    _traceSurface(
        'bind requested wid=$widValue surfaceGeneration=$surfaceGeneration');
    await lock.synchronized(() async {
      final incoming = _surfaceOwner(
        handle: nativeHandle ?? await player.handle,
        generation: generation,
        viewId: viewId,
        surfaceGeneration: surfaceGeneration,
        wid: widValue,
      );
      if (!_outputIntent.isCurrent(incoming, outputIntentSerial)) {
        _pendingSurfaceReleases.add(incoming);
        await _releaseSurfaceOwnerLocked(incoming);
        return;
      }
      if (_fullyDisposed) {
        _pendingSurfaceReleases.add(incoming);
        await _releaseSurfaceOwnerLocked(incoming);
        return;
      }
      if (_disposed) {
        _pendingSurfaceReleases.add(incoming);
        if (_playerTerminated) {
          await _releaseSurfaceOwnerLocked(incoming);
        }
        return;
      }
      if (nativeSurfaceGeneration != generation ||
          (_platformViewId == viewId &&
              surfaceGeneration < _platformSurfaceGeneration)) {
        _pendingSurfaceReleases.add(incoming);
        await _releaseSurfaceOwnerLocked(incoming);
        return;
      }
      final bound = _boundSurfaceOwner(incoming.handle);
      if (bound == incoming && _inFlightSurfaceOwner == null) {
        if (_outputIntent.isCurrent(incoming, outputIntentSerial)) {
          _currentPlatformOutputUnavailable = false;
          if (!_currentPlatformViewOutputBound.isCompleted) {
            _currentPlatformViewOutputBound.complete();
          }
        }
        return;
      }
      _invalidateCurrentOutputBound();
      // Retain B before attempting to stop A. If the strict stop fails, B has
      // not been promoted but still needs deterministic destroy/dispose cleanup.
      _pendingSurfaceReleases.add(incoming);

      // Apply the native window directly under the same lock before releasing
      // the initial-open barrier. A ValueNotifier listener is asynchronous and
      // would otherwise let player.open race vid=no/vo=null.
      wid.removeListener(widListener);
      try {
        final previousInFlight = _inFlightSurfaceOwner;
        if (bound != null || previousInFlight != null) {
          // Keep A as the confirmed owner until the strict stop reply succeeds.
          // A failed first vo=null therefore cannot make a late A destroy look
          // stale and release a Surface that mpv may still be using.
          await _applyWidLocked(widValueOverride: '0');
          if (bound != null && bound != incoming) {
            _pendingSurfaceReleases.add(bound);
            _clearSurfaceOwner(bound);
          }
          if (previousInFlight != null && previousInFlight != incoming) {
            _pendingSurfaceReleases.add(previousInFlight);
            _clearSurfaceOwner(previousInFlight);
          }
        }
        // From this point B may be visible to a partially completed mpv
        // property sequence. Keep it explicit until every strict write has
        // succeeded; failure paths must stop B before releasing it.
        _inFlightSurfaceOwner = incoming;
        await _drainPendingSurfaceReleasesLocked(except: incoming);
        // Rebinding vo/wid attaches the current decoder output to this new
        // Surface. Seeking again discards HEVC references during rebuild.
        await _applyWidLocked(widValueOverride: incoming.wid.toString());
        wid.value = incoming.wid == 0 ? null : incoming.wid;
        _platformViewId = incoming.viewId;
        _platformSurfaceGeneration = incoming.surfaceGeneration;
        _inFlightSurfaceOwner = null;
        _pendingSurfaceReleases.remove(incoming);
        final isExpectedOutput = widValue != 0 &&
            _outputIntent.isCurrent(incoming, outputIntentSerial);
        _currentPlatformOutputUnavailable = !isExpectedOutput;
        _traceSurface(
            'bind complete wid=$widValue surfaceGeneration=$surfaceGeneration');
        if (isExpectedOutput && !_currentPlatformViewOutputBound.isCompleted) {
          _currentPlatformViewOutputBound.complete();
        }
        if (isExpectedOutput && !_initialPlatformViewOutputBound.isCompleted) {
          _initialPlatformViewOutputBound.complete();
        }
      } catch (error, stackTrace) {
        if (_outputIntent.isCurrent(incoming, outputIntentSerial)) {
          _currentPlatformOutputUnavailable = true;
          _failCurrentOutputBound(error, stackTrace);
          _currentPlatformViewOutputBound = Completer<void>();
          if (!_initialPlatformViewOutputBound.isCompleted) {
            _initialPlatformViewOutputBound.completeError(error, stackTrace);
            unawaited(_initialPlatformViewOutputBound.future
                .catchError((Object _) {}));
          }
        }
        rethrow;
      } finally {
        if (!_disposed) wid.addListener(widListener);
      }
    });
  }

  /// [StreamSubscription] for listening to video [Rect].
  StreamSubscription<VideoParams>? videoParamsSubscription;

  /// {@macro android_video_controller}
  AndroidVideoController._(super.player, super.configuration) {
    _channel; // Access _channel to trigger its initialization when the class is first accessed.
    _postTerminationCallback = _onPlayerTerminated;
    platform.postTermination.add(_postTerminationCallback);
    wid.addListener(widListener);
    videoParamsSubscription = player.stream.videoParams.listen(
      (event) => lock.synchronized(() async {
        if (_disposed) return;
        int width;
        int height;
        if (event.rotate == 0 || event.rotate == 180) {
          width = event.dw ?? 0;
          height = event.dh ?? 0;
        } else {
          // width & height are swapped for 90 or 270 degrees rotation.
          width = event.dh ?? 0;
          height = event.dw ?? 0;
        }

        if (width <= 0 || height <= 0) return;
        _sourceDisplaySize = Size(width.toDouble(), height.toDouble());
        await _applyVideoSizeLocked();
      }),
    );
  }

  /// {@macro android_video_controller}
  static Future<PlatformVideoController> create(
    Player player,
    VideoControllerConfiguration configuration,
  ) async {
    final nativePlayer = player.platform as NativePlayer;
    void ensurePlayerActive() {
      if (nativePlayer.disposed ||
          nativePlayer.isDisposing ||
          nativePlayer.isTerminated) {
        throw StateError(
          'Cannot create an Android video controller for a disposed player.',
        );
      }
    }

    ensurePlayerActive();
    Future<String> getDefaultHwdec() async {
      // Enforce software rendering in emulators.
      bool hw = configuration.enableHardwareAcceleration;
      final bool isEmulator = await _channel.invokeMethod('Utils.IsEmulator');
      if (isEmulator) {
        hw = false;
        debugPrint('media_kit: Emulator detected.');
        debugPrint('media_kit: Enforcing S/W rendering.');
      }
      return hw ? 'auto-safe' : 'no';
    }

    // Update [configuration] to have default values.
    configuration = configuration.copyWith(
      vo: configuration.vo ?? 'gpu',
      hwdec: configuration.hwdec ?? await getDefaultHwdec(),
    );
    ensurePlayerActive();

    // Retrieve the native handle of the [Player].
    final handle = await player.handle;
    ensurePlayerActive();
    // Return only a live existing controller. A failed disposal deliberately
    // remains registered to retain its Surface owners; handing it to a new
    // widget would silently reuse a controller that rejects every bind.
    final existing = _controllers[handle];
    if (existing != null) {
      if (existing._fullyDisposed) {
        _controllers.remove(handle);
      } else if (existing._disposed) {
        throw StateError(
          'Android video controller disposal is incomplete; retry disposal '
          'before creating a replacement.',
        );
      } else {
        return existing;
      }
    }

    final failedController = _failedControllerDisposals[handle];
    if (failedController != null) {
      try {
        await failedController.disposeForRebuild();
        _failedControllerDisposals.remove(handle);
      } catch (error) {
        throw StateError(
          'A previous Android video controller initialization failed and its '
          'native cleanup is still incomplete: $error',
        );
      }
      ensurePlayerActive();
    }

    final pendingCreation = _controllerCreations[handle];
    if (pendingCreation != null) return pendingCreation;

    final creation = () async {
      // In case no video-decoders are found, this means
      // media_kit_libs_***_audio is being used. Thus, --vid=no is required to
      // prevent libmpv from trying to decode video.
      final decoders = await queryDecoders(handle);
      ensurePlayerActive();
      if (!decoders.contains('h264')) {
        throw UnsupportedError(
          '[VideoController] is not available.'
          ' '
          'Please use media_kit_libs_***_video instead of media_kit_libs_***_audio.',
        );
      }

      final controller = AndroidVideoController._(player, configuration);
      controller.nativeHandle = handle;
      controller.nativeSurfaceGeneration =
          (_surfaceGenerations[handle] ?? 0) + 1;
      _surfaceGenerations[handle] = controller.nativeSurfaceGeneration;

      try {
        // For PlatformView, Flutter provides the Surface asynchronously. A
        // Texture output must be recorded before the next await so failed
        // initialization can dispose the exact native resource.
        Map<String, dynamic>? initialTextureSurface;
        if (!configuration.usePlatformView) {
          controller._nativeTextureCreation = _channel
              .invokeMapMethod<String, dynamic>('VideoOutputManager.Create', {
            'handle': handle.toString(),
            'enableSurfaceProducer': configuration.enableAndroidSurfaceProducer,
            'generation': controller.nativeSurfaceGeneration,
          }).then((surface) {
            controller._videoOutputCreated = true;
            return surface;
          });
          initialTextureSurface = await controller._nativeTextureCreation;
          ensurePlayerActive();
        }

        if (configuration.usePlatformView) {
          controller.id.value = handle;
        }

        await controller.setProperties({
          // It is necessary to set vo=null here to avoid SIGSEGV, --wid must be assigned before vo=gpu is set.
          'vo': 'null',
          'hwdec': configuration.hwdec!,
          // A PlatformView's Surface is created asynchronously by Flutter. Do not
          // let MediaCodec configure before its wid exists; widListener restores
          // vid=auto after it has bound the current Surface generation.
          'vid': configuration.usePlatformView ? 'no' : 'auto',
          'force-window': 'yes',
          'gpu-api': configuration.androidGpuApi != null
              ? configuration.androidGpuApi!
              : const String.fromEnvironment('MEDIA_KIT_ANDROID_GPU_API')
                      .isNotEmpty
                  ? const String.fromEnvironment('MEDIA_KIT_ANDROID_GPU_API')
                  : configuration.vo == 'gpu-next'
                      ? 'vulkan,opengl'
                      : 'auto',
          // An explicit API choice owns its context choice too. A global
          // Vulkan-only probe context must not be paired with OpenGL HDR.
          if (configuration.androidGpuApi == null &&
              const String.fromEnvironment('MEDIA_KIT_ANDROID_GPU_CONTEXT')
                  .isNotEmpty)
            'gpu-context':
                const String.fromEnvironment('MEDIA_KIT_ANDROID_GPU_CONTEXT'),
          'sub-use-margins': 'no',
          'sub-font-provider': 'none',
          'sub-scale-with-window': 'yes',
          'hwdec-codecs': 'h264,hevc,mpeg4,mpeg2video,vp8,vp9,av1',
        });
        if (!configuration.usePlatformView &&
            !configuration.enableAndroidSurfaceProducer) {
          // SurfaceTextureEntry creates its Surface synchronously. Its first
          // MethodChannel callback can arrive before this controller is
          // published, so bind the returned identity before media is opened.
          final textureId = (initialTextureSurface?['id'] as num?)?.toInt();
          final textureWid = (initialTextureSurface?['wid'] as num?)?.toInt();
          if (textureId == null || textureWid == null || textureWid == 0) {
            throw StateError(
                'SurfaceTexture did not return an initial Surface.');
          }
          controller.wid.removeListener(controller.widListener);
          try {
            await controller._applyWidLocked(
                widValueOverride: textureWid.toString());
            controller.id.value = textureId;
            controller.wid.value = textureWid;
            controller._initialPlatformViewOutputBound.complete();
          } finally {
            controller.wid.addListener(controller.widListener);
          }
        }
        ensurePlayerActive();
      } catch (error, stackTrace) {
        try {
          await controller._dispose();
        } catch (cleanupError) {
          _failedControllerDisposals[handle] = controller;
          Error.throwWithStackTrace(
            StateError(
              'Android video controller initialization failed ($error), and '
              'its native cleanup is incomplete: $cleanupError',
            ),
            stackTrace,
          );
        }
        // Initialization never published a PlatformView, so no Java Surface
        // owner can exist for this generation after successful cleanup.
        controller.platform.postTermination.remove(
          controller._postTerminationCallback,
        );
        Error.throwWithStackTrace(error, stackTrace);
      }

      // Publish only a fully initialized controller. Concurrent callers share
      // this creation Future and cannot observe a partial controller.
      controller._published = true;
      _controllers[handle] = controller;
      controller._playerReleaseCallback = controller._dispose;
      player.platform?.release.add(controller._playerReleaseCallback!);
      return controller;
    }();
    _controllerCreations[handle] = creation;
    try {
      return await creation;
    } finally {
      if (identical(_controllerCreations[handle], creation)) {
        _controllerCreations.remove(handle);
      }
    }
  }

  /// Sets the required size of the video output.
  /// This may yield substantial performance improvements if a small [width] & [height] is specified.
  ///
  /// Remember:
  /// * “Premature optimization is the root of all evil”
  /// * “With great power comes great responsibility”
  @override
  Future<void> setSize({int? width, int? height}) {
    throw UnsupportedError(
      '[AndroidVideoController.setSize] is not available on Android',
    );
  }

  /// Disposes the instance. Releases allocated resources back to the system.
  @override
  Future<void> disposeForRebuild() async {
    // A successful normal dispose does not prove that Java received the
    // terminal epoch notification. Once mpv has terminated, retry the
    // post-termination callbacks instead of returning the older normal-dispose
    // Future. Failed callbacks remain registered in NativePlayer.
    if (platform.isTerminated) {
      await _disposeForRebuildAfterPlayerTermination();
    } else if (_playerTerminated) {
      await (_terminalDisposeFuture ??= _disposeAfterPlayerTermination());
    } else {
      await (_disposeFuture ??= _disposeOnce());
    }
    final callback = _playerReleaseCallback;
    if (callback != null) {
      player.platform?.release.remove(callback);
      _playerReleaseCallback = null;
    }
  }

  Future<void> _disposeForRebuildAfterPlayerTermination() async {
    await platform.retryPostTerminationCallbacks();
    if (_fullyDisposed) return;
    _playerTerminated = true;
    await (_terminalDisposeFuture ??= _disposeAfterPlayerTermination());
  }

  /// Disposes the instance. Releases allocated resources back to the system.
  Future<void> _dispose() => _playerTerminated
      ? _terminalDisposeFuture ??= _disposeAfterPlayerTermination()
      : _disposeFuture ??= _disposeOnce();

  Future<void> _disposeOnce() async {
    if (_playerTerminated) {
      return _terminalDisposeFuture ??= _disposeAfterPlayerTermination();
    }
    _disposed = true;
    _currentPlatformOutputUnavailable = true;
    _failCurrentOutputBound(
      StateError('Android output disposed before current bind.'),
      StackTrace.current,
    );
    if (_published && !_initialPlatformViewOutputBound.isCompleted) {
      _initialPlatformViewOutputBound.completeError(
        StateError(
            'Android PlatformView disposed before its initial output bound.'),
      );
      // The transaction may wait on the current output instead. Preserve the
      // error for initial-output callers without reporting an unhandled error
      // when no such caller exists.
      unawaited(
          _initialPlatformViewOutputBound.future.catchError((Object _) {}));
    }
    Object? cleanupError;
    StackTrace? cleanupStack;
    void recordFailure(Object error, StackTrace stack) {
      cleanupError ??= error;
      cleanupStack ??= stack;
    }

    final subscription = videoParamsSubscription;
    try {
      await subscription?.cancel();
      videoParamsSubscription = null;
    } catch (error, stack) {
      recordFailure(error, stack);
    }

    int? handle = nativeHandle;
    try {
      handle ??= await player.handle;
    } catch (error, stack) {
      recordFailure(error, stack);
    }
    try {
      if (handle == null) {
        throw StateError('Android video controller has no native handle.');
      }
      await lock.synchronized(() async {
        wid.removeListener(widListener);
        if (configuration.usePlatformView) {
          final bound = _boundSurfaceOwner(handle!);
          if (wid.value != null && bound == null) {
            throw StateError(
              'Active Android PlatformView Surface has no view identity.',
            );
          }
          if (bound != null) _pendingSurfaceReleases.add(bound);
          final inFlight = _inFlightSurfaceOwner;
          if (inFlight != null) _pendingSurfaceReleases.add(inFlight);
          // Stop mpv while the JNI Surface reference is still valid. The
          // release callback path must use NativePlayer's release-safe setter.
          // Do not mutate the Dart identity until the full stop sequence has
          // succeeded; failures remain retryable and are never ACKed.
          await _applyWidLocked(widValueOverride: '0');
          if (bound != null) _clearSurfaceOwner(bound);
          if (inFlight != null) _clearSurfaceOwner(inFlight);
          await _drainPendingSurfaceReleasesLocked();
        } else {
          // Texture output owns the same producer/consumer ordering contract.
          await _setOutputProperty('vo', 'null');
          if (_videoOutputCreated) {
            await _channel.invokeMethod('VideoOutputManager.Dispose', {
              'handle': handle!.toString(),
            });
            _videoOutputCreated = false;
          }
        }
      });
    } catch (error, stack) {
      recordFailure(error, stack);
    }
    if (cleanupError != null) {
      // Concurrent callers observed this same failed Future. A later explicit
      // call may retry using the retained controller, notifier, active
      // identity, and pending-owner set.
      _disposeFuture = null;
      Error.throwWithStackTrace(cleanupError!, cleanupStack!);
    }
    if (identical(_controllers[handle], this)) {
      _controllers.remove(handle);
    }
    _finalizeDispose();
  }

  Future<void> _onPlayerTerminated() {
    _playerTerminated = true;
    return _terminalDisposeFuture ??= _disposeAfterPlayerTermination();
  }

  Future<void> _disposeAfterPlayerTermination() async {
    _disposed = true;
    _currentPlatformOutputUnavailable = true;
    _failCurrentOutputBound(
      StateError('Android output terminated before current bind.'),
      StackTrace.current,
    );
    Object? cleanupError;
    StackTrace? cleanupStack;
    void recordFailure(Object error, StackTrace stack) {
      cleanupError ??= error;
      cleanupStack ??= stack;
    }

    // A rebuilt controller can start Create after the player's one-shot
    // initialization barrier has completed. Wait for its native ownership to
    // settle before deciding whether the terminal callback may finalize.
    // Dispose is idempotent on Java even when Create itself returned an error.
    if (!configuration.usePlatformView && _nativeTextureCreation != null) {
      try {
        await _nativeTextureCreation;
      } catch (_) {
        // The MethodChannel may fail after Java has inserted the output.
        // Reconcile by handle below instead of assuming nothing was created.
      }
    }

    final subscription = videoParamsSubscription;
    try {
      await subscription?.cancel();
      videoParamsSubscription = null;
    } catch (error, stack) {
      recordFailure(error, stack);
    }

    final handle = nativeHandle;
    if (handle == null) {
      recordFailure(
        StateError('Android video controller has no native handle.'),
        StackTrace.current,
      );
    } else {
      try {
        await lock.synchronized(() async {
          if (!_fullyDisposed) wid.removeListener(widListener);
          if (configuration.usePlatformView) {
            final bound = _fullyDisposed ? null : _boundSurfaceOwner(handle);
            final inFlight = _fullyDisposed ? null : _inFlightSurfaceOwner;
            if (!_fullyDisposed) {
              if (wid.value != null && bound == null) {
                throw StateError(
                  'Active Android PlatformView Surface has no view identity.',
                );
              }
              if (bound != null) _pendingSurfaceReleases.add(bound);
              if (inFlight != null) _pendingSurfaceReleases.add(inFlight);
            }
            // mpv_terminate_destroy has returned before this callback starts.
            // Java can now release every generation, including owners that a
            // channel failure prevented Dart from observing.
            final released = await _channel.invokeMethod<bool>(
              'PlatformVideoView.PlayerTerminated',
              {
                'handle': handle.toString(),
                'generation': nativeSurfaceGeneration,
              },
            ).timeout(_playerTerminatedTimeout);
            if (released != true) {
              throw StateError(
                'PlatformVideoView.PlayerTerminated did not release all '
                'Surface owners.',
              );
            }
            if (!_fullyDisposed) {
              if (bound != null) _clearSurfaceOwner(bound);
              if (inFlight != null) _clearSurfaceOwner(inFlight);
              _pendingSurfaceReleases.clear();
            }
          } else {
            if (_nativeTextureCreation != null) {
              await _channel.invokeMethod('VideoOutputManager.Dispose', {
                'handle': handle.toString(),
              });
              _videoOutputCreated = false;
            }
          }
        });
      } catch (error, stack) {
        recordFailure(error, stack);
      }
    }

    if (cleanupError != null) {
      _terminalDisposeFuture = null;
      Error.throwWithStackTrace(cleanupError!, cleanupStack!);
    }
    if (identical(_controllers[handle], this)) {
      _controllers.remove(handle);
    }
    platform.postTermination.remove(_postTerminationCallback);
    _finalizeDispose();
  }

  void _finalizeDispose() {
    if (_fullyDisposed) return;
    _fullyDisposed = true;
    final handle = nativeHandle;
    if (handle != null && identical(_failedControllerDisposals[handle], this)) {
      _failedControllerDisposals.remove(handle);
    }
    if (!configuration.usePlatformView) {
      platform.postTermination.remove(_postTerminationCallback);
    }
    wid.removeListener(widListener);
    wid.dispose();
    super.dispose();
  }

  /// Currently created [AndroidVideoController]s.
  static final _controllers = HashMap<int, AndroidVideoController>();

  /// Concurrent requests for the same native player share initialization and
  /// cannot observe or publish a half-configured controller.
  static final _controllerCreations =
      HashMap<int, Future<PlatformVideoController>>();

  /// Failed initialization is never published through [_controllers]. Keep a
  /// private retry handle if its native cleanup could not complete.
  static final _failedControllerDisposals =
      HashMap<int, AndroidVideoController>();

  /// Monotonic controller epoch per player handle. Platform-view callbacks use
  /// this to reject events from a controller that has already been rebuilt.
  static final _surfaceGenerations = HashMap<int, int>();

  /// [MethodChannel] for invoking platform specific native implementation.
  static final _channel = const MethodChannel(
    'com.alexmercerind/media_kit_video',
  )..setMethodCallHandler((MethodCall call) async {
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
              final int wid = call.arguments['wid'];
              final controller = _controllers[handle];
              if (controller == null || controller._disposed) break;
              final int generation = call.arguments['generation'] ?? 0;
              if (generation != 0 &&
                  generation != controller.nativeSurfaceGeneration) {
                break;
              }
              if (controller._layoutSizedTexture &&
                  controller.wid.value != null &&
                  (wid != controller.wid.value || id != controller.id.value)) {
                break;
              }
              // SurfaceTexture retains the same wid on resize. The locked
              // resize ACK, not this asynchronous callback, owns its rect.
              if (!controller._layoutSizedTexture) {
                controller.rect.value = rect;
              }
              controller.id.value = id;
              controller.wid.value = wid;
              break;
            }
          case 'VideoOutput.WaitUntilFirstFrameRenderedNotify':
            {
              // Notify about updated texture ID & [Rect].
              final int handle = call.arguments['handle'];
              debugPrint(handle.toString());
              // Notify about the first frame being rendered.
              final completer =
                  _controllers[handle]?.waitUntilFirstFrameRenderedCompleter;
              if (!(completer?.isCompleted ?? true)) {
                completer?.complete();
              }
              break;
            }
          case 'PlatformVideoView.SurfaceAvailable':
            {
              final int handle = call.arguments['handle'];
              final int wid = call.arguments['wid'];
              final int generation = call.arguments['generation'];
              final int viewId = call.arguments['viewId'];
              final int surfaceGeneration = call.arguments['surfaceGeneration'];
              final controller = _controllers[handle];
              if (controller == null) {
                await _releaseOrphanPlatformSurface(
                  _surfaceOwner(
                    handle: handle,
                    generation: generation,
                    viewId: viewId,
                    surfaceGeneration: surfaceGeneration,
                    wid: wid,
                  ),
                );
              } else {
                final outputIntentSerial =
                    controller._markSurfaceBindBeforeAwait(
                  handle,
                  generation,
                  viewId,
                  surfaceGeneration,
                  wid,
                );
                await controller._bindPlatformViewSurface(
                  widValue: wid,
                  generation: generation,
                  viewId: viewId,
                  surfaceGeneration: surfaceGeneration,
                  outputIntentSerial: outputIntentSerial,
                );
              }
              break;
            }
          case 'PlatformVideoView.SurfaceDestroyed':
            {
              final int handle = call.arguments['handle'];
              final int wid = call.arguments['wid'];
              final int generation = call.arguments['generation'];
              final int viewId = call.arguments['viewId'];
              final int surfaceGeneration = call.arguments['surfaceGeneration'];
              final controller = _controllers[handle];
              if (controller == null) {
                // The controller's dispose barrier already stopped its
                // producer before unregistering. A later Java view-dispose
                // notification only needs to reclaim that exact old owner.
                await _releaseOrphanPlatformSurface(
                  _surfaceOwner(
                    handle: handle,
                    generation: generation,
                    viewId: viewId,
                    surfaceGeneration: surfaceGeneration,
                    wid: wid,
                  ),
                );
              } else {
                controller._markSurfaceDestroyedBeforeDetach(
                  handle,
                  wid,
                  generation,
                  viewId,
                  surfaceGeneration,
                );
                await controller._detachPlatformSurface(
                  wid,
                  generation,
                  viewId,
                  surfaceGeneration,
                );
              }
              break;
            }
          default:
            {
              break;
            }
        }
      } catch (exception, stacktrace) {
        debugPrint(exception.toString());
        debugPrint(stacktrace.toString());
      }
    });
}
