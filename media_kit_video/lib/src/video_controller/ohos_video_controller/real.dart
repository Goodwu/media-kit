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
import 'package:media_kit_video/src/video_controller/ohos_video_controller/sw_render.dart';
import 'package:media_kit_video/src/video_controller/hdr_transaction_report.dart';

enum _OhosHdrOutputMode { sdr, pq, hlg }

class _PendingHdrConfiguration {
  const _PendingHdrConfiguration({
    required this.configuration,
    required this.revision,
  });

  final Map<String, dynamic> configuration;
  final int revision;
}

/// {@template ohos_video_controller}
///
/// OhosVideoController
/// ----------------------
///
/// The [PlatformVideoController] implementation based on native C/C++ used on Ohos.
///
/// {@endtemplate}
HdrTransactionReport _hdrReport(Map<String, dynamic> map) =>
    HdrTransactionReport.fromMap(map);

class OhosVideoController extends PlatformVideoController {
  /// Whether [OhosVideoController] is supported on the current platform or not.
  static bool get supported => Platform.operatingSystem == 'ohos';

  // Diagnostic-only experiment. It keeps Flutter/XComponent geometry and the
  // HDR/VO lifecycle unchanged, while holding the extent submitted to mpv
  // constant across orientation changes. Production builds leave this off.
  static const bool _fixedProducerExtent = bool.fromEnvironment(
    'OHOS_DIAGNOSTIC_FIXED_PRODUCER_EXTENT',
    defaultValue: false,
  );
  static const int _fixedProducerWidth = int.fromEnvironment(
    'OHOS_DIAGNOSTIC_FIXED_PRODUCER_WIDTH',
    defaultValue: 2520,
  );
  static const int _fixedProducerHeight = int.fromEnvironment(
    'OHOS_DIAGNOSTIC_FIXED_PRODUCER_HEIGHT',
    defaultValue: 1260,
  );
  static const bool _diagnosticSkipMpvSurfaceSizeProperty =
      bool.fromEnvironment(
    'OHOS_DIAGNOSTIC_SKIP_MPV_SURFACE_SIZE_PROPERTY',
    defaultValue: false,
  );

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
  Future<void>? _disposeFuture;
  int? _hdrTransfer;
  int _hdrConfigRevision = 0;
  int? _nativeViewId;
  _PendingHdrConfiguration? _pendingHdrConfiguration;
  _OhosHdrOutputMode? _appliedHdrOutputMode;
  int? _appliedHdrSurfaceId;
  int? _appliedHdrGeneration;
  bool _sdrTargetAppliedWithoutSurface = false;

  NativePlayer get platform => player.platform as NativePlayer;

  Future<void> setProperty(String key, String value) async {
    await platform.setProperty(key, value, waitForInitialization: false);
  }

  Future<void> _setPropertyForRelease(String key, String value) async {
    await platform.setPropertyForRelease(key, value);
  }

  Future<void> setProperties(Map<String, String> properties) async {
    for (final entry in properties.entries) {
      await setProperty(entry.key, entry.value);
    }
  }

  @override
  Future<HdrTransactionReport> createNativeOutput(
      {String? surfaceId, int? windowHandle}) async {
    // The XComponent PlatformView reports its surface asynchronously. Do
    // not claim native output until that surface has attached and mpv has
    // been switched to it by [_attachNativeSurfaceLocked].
    final id = wid.value;
    if (!nativeSurfaceActive || id == null || id == 0) {
      if (nativeSurfaceCandidate) {
        return const HdrTransactionReport(
          capable: true,
          failureReason: 'ohos-native-surface-awaiting-ready',
        );
      }
      return const HdrTransactionReport(
        failureReason: 'ohos-native-surface-not-ready',
      );
    }
    return _hdrReport(<String, dynamic>{
      'backend': 'ohos-xcomponent-native-window',
      'capable': true,
      'active': true,
      'surfaceId': id,
      'generation': nativeSurfaceGeneration,
    });
  }

  @override
  Future<HdrTransactionReport> configureHdrOutput(
      Map<String, dynamic> configuration) async {
    return lock.synchronized(() async {
      if (_disposed) {
        return const HdrTransactionReport(
          failureReason: 'ohos-video-controller-disposed',
        );
      }
      final revision = ++_hdrConfigRevision;
      return _hdrReport(
          await _configureHdrOutputLocked(configuration, revision: revision));
    });
  }

  Future<Map<String, dynamic>> _configureHdrOutputLocked(
    Map<String, dynamic> configuration, {
    required int revision,
  }) async {
    if (_disposed || revision != _hdrConfigRevision) {
      return const <String, dynamic>{
        'capable': false,
        'active': false,
        'failureReason': 'stale-hdr-config-revision',
      };
    }
    final values = configuration;
    final transfer = values['transfer'] == 'hlg' ? 1 : 0;
    final mode = _hdrModeForTransfer(transfer);
    final pending = _PendingHdrConfiguration(
      configuration: Map<String, dynamic>.from(configuration),
      revision: revision,
    );
    // The pending value and its revision form one transaction. Reset clears
    // both and increments the revision, so an old ready callback cannot
    // re-submit the superseded HDR target.
    _hdrTransfer = transfer;
    _pendingHdrConfiguration = pending;
    _sdrTargetAppliedWithoutSurface = false;

    final id = wid.value;
    if (!nativeSurfaceActive || id == null || id == 0) {
      if (nativeSurfaceCandidate) {
        return const <String, dynamic>{
          'capable': true,
          'active': false,
          'failureReason': 'ohos-native-surface-awaiting-ready',
        };
      }
      return const <String, dynamic>{
        'capable': false,
        'active': false,
        'failureReason': 'ohos-native-surface-not-ready',
      };
    }
    final generation = nativeSurfaceGeneration;
    if (_hasAppliedHdrMode(id, generation, mode)) {
      _pendingHdrConfiguration = null;
      return <String, dynamic>{
        'backend': 'ohos-xcomponent-native-window',
        'capable': true,
        'active': true,
        'surfaceId': id,
        'generation': generation,
        'transfer': values['transfer'],
        'target-trc': transfer == 1 ? 'hlg' : 'pq',
      };
    }

    // FFI owns static format/gamut/source setup and the valid SDR reference
    // while the VO is stopped. The VO is then initialized with the target
    // properties and becomes the sole writer of dynamic color space and
    // metadata state.
    await _stopVideoOutputForReconfigure();
    if (!_isCurrentHdrConfiguration(id, generation, revision)) {
      return const <String, dynamic>{
        'capable': false,
        'active': false,
        'failureReason': 'stale-hdr-config-revision',
      };
    }
    final result = _configureHdr(id, transfer);
    if (result != 0) {
      final recoveryFailure = await _recoverSdrAfterHdrFailure(id);
      return <String, dynamic>{
        'backend': 'ohos-xcomponent-native-window',
        'capable': false,
        'active': false,
        'surfaceId': id,
        'generation': generation,
        'transfer': values['transfer'],
        'target-trc': transfer == 1 ? 'hlg' : 'pq',
        'failureReason': 'native-window-configure-$result',
        if (recoveryFailure != null) 'recoveryFailureReason': recoveryFailure,
      };
    }
    try {
      await _applyHdrMpvProperties(transfer);
      if (!_isCurrentHdrConfiguration(id, generation, revision)) {
        return const <String, dynamic>{
          'capable': false,
          'active': false,
          'failureReason': 'stale-hdr-config-revision',
        };
      }
      await setProperty('vo', 'gpu-next');
    } catch (error) {
      final recoveryFailure = await _recoverSdrAfterHdrFailure(id);
      return <String, dynamic>{
        'backend': 'ohos-xcomponent-native-window',
        'capable': false,
        'active': false,
        'surfaceId': id,
        'generation': generation,
        'transfer': values['transfer'],
        'target-trc': transfer == 1 ? 'hlg' : 'pq',
        'failureReason': 'hdr-output-property-$error',
        if (recoveryFailure != null) 'recoveryFailureReason': recoveryFailure,
      };
    }
    if (!_isCurrentHdrConfiguration(id, generation, revision)) {
      return const <String, dynamic>{
        'capable': false,
        'active': false,
        'failureReason': 'stale-hdr-config-revision',
      };
    }
    _recordAppliedHdrMode(id, generation, mode);
    _pendingHdrConfiguration = null;
    return <String, dynamic>{
      'backend': 'ohos-xcomponent-native-window',
      'capable': true,
      'active': true,
      'surfaceId': id,
      'generation': generation,
      'transfer': values['transfer'],
      'target-trc': transfer == 1 ? 'hlg' : 'pq',
      'failureReason': null,
    };
  }

  bool _isCurrentHdrConfiguration(
    int surfaceId,
    int generation,
    int revision,
  ) {
    return !_disposed &&
        revision == _hdrConfigRevision &&
        _pendingHdrConfiguration?.revision == revision &&
        wid.value == surfaceId &&
        nativeSurfaceGeneration == generation &&
        nativeSurfaceActive;
  }

  Future<Map<String, dynamic>> _replayPendingHdrConfiguration(
    _PendingHdrConfiguration pending,
  ) {
    return lock.synchronized(() async {
      if (_disposed ||
          !identical(_pendingHdrConfiguration, pending) ||
          pending.revision != _hdrConfigRevision) {
        return const <String, dynamic>{
          'capable': false,
          'active': false,
          'failureReason': 'stale-hdr-config-revision',
        };
      }
      return _configureHdrOutputLocked(
        pending.configuration,
        revision: pending.revision,
      );
    });
  }

  Future<Map<String, dynamic>> _replayLatestHdrConfiguration() {
    return lock.synchronized(() async {
      if (_disposed || _hdrTransfer == null) {
        return const <String, dynamic>{
          'capable': false,
          'active': false,
          'failureReason': 'no-pending-hdr-configuration',
        };
      }
      final revision = ++_hdrConfigRevision;
      return _configureHdrOutputLocked(<String, dynamic>{
        'transfer': _hdrTransfer == 1 ? 'hlg' : 'pq',
      }, revision: revision);
    });
  }

  Future<void> _applyHdrMpvProperties(int transfer) async {
    final targetTrc = transfer == 1 ? 'hlg' : 'pq';
    await setProperties({
      'target-prim': 'bt.2020',
      'target-trc': targetTrc,
      // gpu-next otherwise leaves the swapchain color space at its default,
      // allowing the OHOS compositor to interpret PQ/HLG samples as SDR.
      'target-colorspace-hint': 'yes',
      'tone-mapping': 'auto',
      'target-peak': 'auto',
    });
  }

  Future<void> _applySdrMpvProperties() async {
    await setProperties({
      'target-prim': 'bt.709',
      'target-trc': 'bt.1886',
      'target-colorspace-hint': 'auto',
      'tone-mapping': 'bt.2390',
      'target-peak': 'auto',
    });
  }

  List<int> _producerExtent({
    required int geometryWidth,
    required int geometryHeight,
    required bool nativeActive,
  }) {
    if (_fixedProducerExtent &&
        nativeActive &&
        _fixedProducerWidth > 0 &&
        _fixedProducerHeight > 0) {
      return <int>[_fixedProducerWidth, _fixedProducerHeight];
    }
    return <int>[geometryWidth, geometryHeight];
  }

  _OhosHdrOutputMode _hdrModeForTransfer(int transfer) {
    return transfer == 1 ? _OhosHdrOutputMode.hlg : _OhosHdrOutputMode.pq;
  }

  bool _hasAppliedHdrMode(
    int surfaceId,
    int generation,
    _OhosHdrOutputMode mode,
  ) {
    return _appliedHdrSurfaceId == surfaceId &&
        _appliedHdrGeneration == generation &&
        _appliedHdrOutputMode == mode;
  }

  void _recordAppliedHdrMode(
    int surfaceId,
    int generation,
    _OhosHdrOutputMode mode,
  ) {
    _appliedHdrSurfaceId = surfaceId;
    _appliedHdrGeneration = generation;
    _appliedHdrOutputMode = mode;
    _sdrTargetAppliedWithoutSurface = false;
  }

  void _clearAppliedHdrMode() {
    _appliedHdrSurfaceId = null;
    _appliedHdrGeneration = null;
    _appliedHdrOutputMode = null;
    _sdrTargetAppliedWithoutSurface = false;
  }

  /// Invalidates the mode cache before the old VO is destroyed.
  ///
  /// A successful SDR/HDR transaction is only valid for the VO instance that
  /// was restarted by that transaction. Keeping the record while setting
  /// `vo=null` lets a later reset incorrectly treat a stopped VO as already
  /// configured.
  Future<void> _stopVideoOutputForReconfigure() async {
    _clearAppliedHdrMode();
    await setProperty('vo', 'null');
  }

  Future<String?> _recoverSdrAfterHdrFailure(int surfaceId) async {
    _pendingHdrConfiguration = null;
    _hdrTransfer = null;
    _clearAppliedHdrMode();
    try {
      final resetResult = _resetHdr(surfaceId);
      await _applySdrMpvProperties();
      await setProperty('vo', 'gpu-next');
      if (resetResult != 0) {
        return 'native-window-sdr-recovery-$resetResult';
      }
    } catch (error) {
      return 'sdr-recovery-$error';
    }
    // Do not record this as an idempotent applied mode. The caller may still
    // issue resetHdrOutput() after the failed HDR attempt; it must perform a
    // real SDR VO restart rather than trust the pre-failure cache.
    return null;
  }

  @override
  Future<HdrTransactionReport> resetHdrOutput() async {
    final result = await lock.synchronized(() async {
      if (_disposed) return null;
      _hdrConfigRevision++;
      _pendingHdrConfiguration = null;
      _hdrTransfer = null;
      final id = wid.value;
      final generation = nativeSurfaceGeneration;
      if (id == null || id == 0 || !nativeSurfaceActive) {
        // A reset must still restore mpv's SDR target when the native surface
        // is temporarily absent. Returning before this write leaves the old
        // HDR target armed for the next output.
        if (!_sdrTargetAppliedWithoutSurface) {
          await _applySdrMpvProperties();
          _clearAppliedHdrMode();
          _sdrTargetAppliedWithoutSurface = true;
        }
        return null;
      }
      if (_hasAppliedHdrMode(id, generation, _OhosHdrOutputMode.sdr)) {
        return <String, int>{'id': id, 'generation': generation, 'result': 0};
      }
      await _stopVideoOutputForReconfigure();
      final resetResult = _resetHdr(id);
      await _applySdrMpvProperties();
      await setProperty('vo', 'gpu-next');
      if (resetResult == 0) {
        _recordAppliedHdrMode(id, generation, _OhosHdrOutputMode.sdr);
      }
      return <String, int>{
        'id': id,
        'generation': generation,
        'result': resetResult,
      };
    });
    if (result == null) {
      return const HdrTransactionReport(
        failureReason: 'ohos-surface-id-unavailable',
      );
    }
    return _hdrReport(<String, dynamic>{
      'backend': 'ohos-native-window',
      'capable': result['result'] == 0,
      'active': false,
      'surfaceId': result['id'],
      'generation': result['generation'],
      'failureReason': result['result'] == 0
          ? null
          : 'native-window-reset-${result['result']}',
    });
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
  int _surfaceResizeSerial = 0;
  int? _queuedSurfaceWidth;
  int? _queuedSurfaceHeight;
  double? _queuedViewportWidth;
  double? _queuedViewportHeight;

  @override
  Future<void> refreshSurfaceSize({
    double? viewportWidth,
    double? viewportHeight,
  }) async {
    final width = _lastRequestedSurfaceWidth;
    final height = _lastRequestedSurfaceHeight;
    if (_disposed || width == null || height == null) {
      return;
    }
    if (_refreshingSurfaceSize) {
      _queuedSurfaceWidth = width;
      _queuedSurfaceHeight = height;
      _queuedViewportWidth = viewportWidth;
      _queuedViewportHeight = viewportHeight;
      return;
    }
    if (viewportWidth != null &&
        viewportHeight != null &&
        viewportWidth == _lastRefreshViewportWidth &&
        viewportHeight == _lastRefreshViewportHeight) {
      return;
    }
    _refreshingSurfaceSize = true;
    final resizeSerial = ++_surfaceResizeSerial;
    final requestViewId = _nativeViewId;
    final requestSurfaceId = wid.value;
    final requestGeneration = nativeSurfaceGeneration;
    final requestConfigRevision = _hdrConfigRevision;
    debugPrint(
      '[OhosPlaybackTrace] refreshSurfaceSize begin serial=$resizeSerial '
      'viewport=${viewportWidth}x$viewportHeight requested=${width}x$height '
      'active=$nativeSurfaceActive generation=$requestGeneration '
      'surface=$requestSurfaceId',
    );
    bool isCurrentOutput() =>
        !_disposed &&
        requestViewId == _nativeViewId &&
        requestSurfaceId == wid.value &&
        requestGeneration == nativeSurfaceGeneration &&
        requestConfigRevision == _hdrConfigRevision;
    try {
      final handle = await player.handle;
      final nativeActive = nativeSurfaceActive;
      final outputSize = await lock.synchronized(() async {
        if (!isCurrentOutput()) return null;
        return _channel.invokeMethod<dynamic>(
          'VideoOutputManager.SetSurfaceSize',
          {
            'handle': handle.toString(),
            'width': width.toString(),
            'height': height.toString(),
            'force': true,
            // Once the XComponent is active, mpv submits directly to that
            // surface. Resizing the unused Flutter Texture in parallel creates
            // a second BufferQueue allocation during rotation on OHOS.
            'updateTextureBuffer': !nativeActive,
          },
        );
      });
      if (outputSize == null || !isCurrentOutput()) {
        return;
      }
      final effectiveWidth = outputSize is Map && outputSize['width'] is num
          ? (outputSize['width'] as num).toInt()
          : width;
      final effectiveHeight = outputSize is Map && outputSize['height'] is num
          ? (outputSize['height'] as num).toInt()
          : height;
      if (effectiveWidth <= 0 || effectiveHeight <= 0 || !isCurrentOutput()) {
        debugPrint(
          '[OhosVideoController] discarded stale surface resize: '
          'serial=$resizeSerial requestView=$requestViewId currentView=$_nativeViewId '
          'requestSurface=$requestSurfaceId currentSurface=${wid.value} '
          'requestGeneration=$requestGeneration currentGeneration=$nativeSurfaceGeneration',
        );
        return;
      }
      if (effectiveWidth == _lastRefreshedSurfaceWidth &&
          effectiveHeight == _lastRefreshedSurfaceHeight) {
        return;
      }
      var applied = false;
      await lock.synchronized(() async {
        if (!isCurrentOutput()) return;
        final producerExtent = _producerExtent(
          geometryWidth: effectiveWidth,
          geometryHeight: effectiveHeight,
          nativeActive: nativeActive,
        );
        final currentSurfaceId = wid.value;
        if (_diagnosticSkipMpvSurfaceSizeProperty) {
          debugPrint(
            '[OhosVideoController] diagnostic skipped mpv surface-size '
            'property serial=$resizeSerial producerExtent='
            '${producerExtent[0]}x${producerExtent[1]}',
          );
        } else {
          debugPrint(
            '[OhosPlaybackTrace] set ohos-surface-size serial=$resizeSerial '
            'extent=${producerExtent[0]}x${producerExtent[1]} '
            'active=$nativeActive surface=$currentSurfaceId',
          );
          await setProperties({
            'ohos-surface-size': '${producerExtent[0]}x${producerExtent[1]}',
          });
        }
        // A swapchain resize can discard VO-owned dynamic color state before
        // mpv's next frame reaches its color callback. Restore only the VO
        // target properties here; static format/gamut is initialized by FFI
        // while the VO is stopped and is never written during resize.
        final transfer = _hdrTransfer;
        if (transfer != null &&
            currentSurfaceId != null &&
            currentSurfaceId != 0 &&
            isCurrentOutput()) {
          // ohos-surface-size invalidates mpv's swapchain/color cache. Do not
          // call the HDR FFI here: it writes static producer state and is
          // reserved for the explicit stopped-VO init boundary.
          await _applyHdrMpvProperties(transfer);
          debugPrint(
            '[OhosVideoController] reapplied VO HDR target after surface resize: '
            'transfer=$transfer targetTrc='
            '${transfer == 1 ? 'hlg' : 'pq'} serial=$resizeSerial '
            'surface=$currentSurfaceId producerExtent='
            '${producerExtent[0]}x${producerExtent[1]}',
          );
        }
        debugPrint(
          '[OhosVideoController] resized native surface geometry; '
          'HDR color contract reapplied for producer extent '
          '${producerExtent[0]}x${producerExtent[1]}; '
          'serial=$resizeSerial view=$_nativeViewId surface=${wid.value} '
          'nativeActive=$nativeActive updateTextureBuffer=${!nativeActive}',
        );
        rect.value = Rect.fromLTWH(
          0,
          0,
          effectiveWidth.toDouble(),
          effectiveHeight.toDouble(),
        );
        applied = true;
      });
      if (!applied) {
        debugPrint(
          '[OhosVideoController] skipped resize after output changed: '
          'serial=$resizeSerial requestView=$requestViewId currentView=$_nativeViewId '
          'requestSurface=$requestSurfaceId currentSurface=${wid.value}',
        );
        return;
      }
      _lastRefreshedSurfaceWidth = effectiveWidth;
      _lastRefreshedSurfaceHeight = effectiveHeight;
      _lastRefreshViewportWidth = viewportWidth;
      _lastRefreshViewportHeight = viewportHeight;
      debugPrint(
        '[OhosVideoController] refreshed native surface size: '
        '${width}x$height -> ${effectiveWidth}x$effectiveHeight '
        'serial=$resizeSerial view=$_nativeViewId surface=${wid.value}',
      );
    } finally {
      _refreshingSurfaceSize = false;
      final queuedWidth = _queuedSurfaceWidth;
      final queuedHeight = _queuedSurfaceHeight;
      final queuedViewportWidth = _queuedViewportWidth;
      final queuedViewportHeight = _queuedViewportHeight;
      _queuedSurfaceWidth = null;
      _queuedSurfaceHeight = null;
      _queuedViewportWidth = null;
      _queuedViewportHeight = null;
      if (!_disposed && queuedWidth != null && queuedHeight != null) {
        _lastRequestedSurfaceWidth = queuedWidth;
        _lastRequestedSurfaceHeight = queuedHeight;
        scheduleMicrotask(() {
          refreshSurfaceSize(
            viewportWidth: queuedViewportWidth,
            viewportHeight: queuedViewportHeight,
          );
        });
      }
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

        final requestViewId = _nativeViewId;
        final requestSurfaceId = wid.value;
        final requestGeneration = nativeSurfaceGeneration;
        final handle = await player.handle;
        if (_disposed) return;

        final outputSize = await _channel.invokeMethod<dynamic>(
          'VideoOutputManager.SetSurfaceSize',
          {
            'handle': handle.toString(),
            'width': width.toString(),
            'height': height.toString(),
            'updateTextureBuffer': !nativeSurfaceActive,
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
        if (_disposed ||
            requestViewId != _nativeViewId ||
            requestSurfaceId != wid.value ||
            requestGeneration != nativeSurfaceGeneration) {
          debugPrint(
            '[OhosVideoController] discarded stale video params resize: '
            'requestView=$requestViewId currentView=$_nativeViewId '
            'requestSurface=$requestSurfaceId currentSurface=${wid.value}',
          );
          return;
        }
        if (_disposed) return;
        _lastRequestedSurfaceWidth = width;
        _lastRequestedSurfaceHeight = height;
        debugPrint(
          '[OhosVideoController] videoParams surface request: '
          '${width}x$height view=$_nativeViewId surface=${wid.value} '
          'nativeActive=$nativeSurfaceActive '
          'updateTextureBuffer=${!nativeSurfaceActive}',
        );
        await setProperties({
          'ohos-surface-size': _producerExtent(
            geometryWidth: effectiveWidth,
            geometryHeight: effectiveHeight,
            nativeActive: nativeSurfaceActive,
          ).join('x'),
        });
        if (_disposed ||
            requestViewId != _nativeViewId ||
            requestSurfaceId != wid.value ||
            requestGeneration != nativeSurfaceGeneration) {
          return;
        }
        final transfer = _hdrTransfer;
        final currentSurfaceId = wid.value;
        if (nativeSurfaceActive &&
            transfer != null &&
            currentSurfaceId != null &&
            currentSurfaceId != 0) {
          await _applyHdrMpvProperties(transfer);
          debugPrint(
            '[OhosVideoController] reapplied VO HDR target after video params resize: '
            'transfer=$transfer targetTrc='
            '${transfer == 1 ? 'hlg' : 'pq'} surface=$currentSurfaceId '
            'view=$_nativeViewId generation=$nativeSurfaceGeneration',
          );
        }

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

  void _advanceNativeSurfaceGeneration() {
    nativeSurfaceGeneration++;
    final handle = nativeHandle;
    if (handle != null &&
        (_surfaceGenerations[handle] ?? 0) < nativeSurfaceGeneration) {
      _surfaceGenerations[handle] = nativeSurfaceGeneration;
    }
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
    final target = controller;
    if (target == null) {
      debugPrint(
          '[OhosVideoController] no controller for native handle $handle');
      return null;
    }
    if (call.method == 'nativeSurfaceReady') {
      final rawViewId = args['viewId'];
      final viewId =
          rawViewId is num ? rawViewId.toInt() : int.tryParse('$rawViewId');
      final rawSurfaceId = args['surfaceId'];
      final surfaceId = rawSurfaceId is num
          ? rawSurfaceId.toInt()
          : int.tryParse('$rawSurfaceId');
      final rawGeneration = args['generation'];
      final generation = rawGeneration is num
          ? rawGeneration.toInt()
          : int.tryParse('$rawGeneration');
      debugPrint('[OhosVideoController] parsed native surface id: $surfaceId');
      if (viewId == null ||
          surfaceId == null ||
          surfaceId == 0 ||
          generation == null) {
        debugPrint(
            '[OhosVideoController] ignoring incomplete native surface ready');
        return null;
      }
      _PendingHdrConfiguration? pending;
      await target.lock.synchronized(() async {
        if (target._disposed ||
            generation != target.nativeSurfaceGeneration ||
            (target._nativeViewId != null && target._nativeViewId != viewId)) {
          debugPrint(
            '[OhosVideoController] ignoring stale native surface ready: '
            'view=$viewId currentView=${target._nativeViewId} '
            'surface=$surfaceId currentSurface=${target.wid.value} '
            'generation=$generation currentGeneration=${target.nativeSurfaceGeneration}',
          );
          return;
        }
        if (target._nativeViewId == viewId &&
            target.wid.value == surfaceId &&
            target.nativeSurfaceActive) {
          return;
        }
        // Validate the complete creation identity before either native side
        // effect. The lock covers suspend and attach as one handoff: a stale
        // ready event cannot update identity and then redirect mpv.
        await target._suspendTextureOutputLocked();
        await target._attachNativeSurfaceLocked(surfaceId);
        target._nativeViewId = viewId;
        pending = target._pendingHdrConfiguration;
      });
      if (pending != null && !target._disposed) {
        final result = await target._replayPendingHdrConfiguration(pending!);
        debugPrint(
            '[OhosVideoController] applied pending HDR configuration: $result');
      } else if (target._hdrTransfer != null && !target._disposed) {
        final result = await target._replayLatestHdrConfiguration();
        debugPrint(
            '[OhosVideoController] reapplied HDR after native surface attach: $result');
      }
    } else if (call.method == 'nativeSurfaceDestroyed') {
      final rawViewId = args['viewId'];
      final viewId =
          rawViewId is num ? rawViewId.toInt() : int.tryParse('$rawViewId');
      final rawSurfaceId = args['surfaceId'];
      final surfaceId = rawSurfaceId is num
          ? rawSurfaceId.toInt()
          : int.tryParse('$rawSurfaceId');
      final rawGeneration = args['generation'];
      final generation = rawGeneration is num
          ? rawGeneration.toInt()
          : int.tryParse('$rawGeneration');
      var current = false;
      await target.lock.synchronized(() async {
        if (target._disposed) return;
        if (viewId == null ||
            surfaceId == null ||
            generation == null ||
            target._nativeViewId != viewId ||
            target.wid.value != surfaceId ||
            target.nativeSurfaceGeneration != generation) {
          debugPrint(
              '[OhosVideoController] ignoring stale native surface destroy: '
              'view=$viewId currentView=${target._nativeViewId} '
              'surface=$surfaceId currentSurface=${target.wid.value} '
              'generation=$generation currentGeneration=${target.nativeSurfaceGeneration}');
          return;
        }
        // The native window is gone, but the mpv VO may still carry the last
        // PQ/HLG target. Stop that VO and clear the dynamic HDR target before
        // exposing the Flutter Texture again; otherwise the consumer topology
        // becomes Texture/SDR while the producer remains configured as HDR.
        await target._stopVideoOutputForReconfigure();
        try {
          final resetResult = _resetHdr(surfaceId);
          if (resetResult != 0) {
            debugPrint(
                '[OhosVideoController] native surface destroy HDR reset failed: '
                '$resetResult surface=$surfaceId');
          }
        } catch (error) {
          debugPrint(
              '[OhosVideoController] native surface destroy HDR reset error: '
              '$error');
        }
        target._hdrConfigRevision++;
        target._hdrTransfer = null;
        target._advanceNativeSurfaceGeneration();
        target._nativeViewId = null;
        target.wid.value = null;
        target._pendingHdrConfiguration = null;
        target._clearAppliedHdrMode();
        target.setNativeSurfaceActive(false);
        // Keep the native-surface candidate alive for a controller that is
        // still mounted. The XComponent will be rebuilt with the advanced
        // generation and can report a new ready event; clearing this flag
        // permanently would make a surface-loss recovery fall back to Texture
        // forever and could never restore the native HDR path.
        target.nativeSurfaceCandidate = target.configuration.darwin.useNativeSurface;
        current = true;
      });
      if (!current || target._disposed) return null;
      // A native XComponent can be destroyed as part of the same layout or
      // orientation transaction that creates its replacement.  Do not switch
      // the player to the Flutter Texture in this gap: that requires a second
      // VO restart, changes the producer to SDR, and can make mpv report a
      // pause/buffering transition (or reset the current position) even while
      // the player is still meant to be playing.  The next nativeSurfaceReady
      // event owns the handoff and reattaches the native VO directly.
      // Keeping the texture suspended also prevents two BufferQueues from
      // competing during the native-surface replacement.
    }
    return null;
  }

  Future<void> _attachNativeSurfaceLocked(int surfaceId) async {
    debugPrint(
        '[OhosVideoController] attaching native XComponent surface $surfaceId');
    if (_disposed) return;
    final previous = wid.value;
    await _stopVideoOutputForReconfigure();
    wid.value = surfaceId;
    if (swRender) {
      // Software render mode: the bridge owns the surface (its own EGL on
      // the XComponent window, mpv render API SW frames blitted onto it);
      // mpv keeps vo=libmpv and must not bind the surface as a window.
      await setProperties({
        if (rect.value != null)
          'ohos-surface-size':
              '${rect.value!.width.toInt()}x${rect.value!.height.toInt()}',
      });
      await setProperty('vo', 'libmpv');
      nativeSurfaceCandidate = true;
      setNativeSurfaceActive(true);
      SwRender.detach();
      final attached = SwRender.attach(surfaceId, nativeHandle ?? 0);
      debugPrint(
        '[OhosVideoController] software render attach: surface=$surfaceId '
        'attached=$attached',
      );
      return;
    }
    await setProperties({
      'wid': surfaceId.toString(),
      if (rect.value != null)
        'ohos-surface-size':
            '${rect.value!.width.toInt()}x${rect.value!.height.toInt()}',
    });
    await setProperty('vo', configuration.vo ?? 'gpu-next');
    nativeSurfaceCandidate = true;
    setNativeSurfaceActive(true);
    debugPrint(
      '[OhosVideoController] native XComponent surface attached: '
      'previous=$previous surface=$surfaceId view=$_nativeViewId '
      'generation=$nativeSurfaceGeneration',
    );
  }

  Future<void> _suspendTextureOutputLocked() async {
    if (_disposed) return;
    final handle = nativeHandle ?? await player.handle;
    if (_disposed) return;
    await _channel.invokeMethod('VideoOutputManager.SuspendTexture', {
      'handle': handle.toString(),
    });
  }

  /// {@macro ohos_video_controller}
  static Future<PlatformVideoController> create(
    Player player,
    VideoControllerConfiguration configuration,
  ) async {
    Future<String> getDefaultHwdec() async {
      bool hw = configuration.enableHardwareAcceleration;
      return hw ? 'auto' : 'no';
    }

    // Update [configuration] to have default values.
    configuration = configuration.copyWith(
      vo: configuration.vo ?? 'gpu-next',
      hwdec: configuration.hwdec ?? await getDefaultHwdec(),
    );

    // OHOS emulator: the GL video outputs (gpu/gpu-next) render black with no
    // error and the hardware decoder path crashes in libmpv's vo thread, so
    // attach the software render bridge (libmpv render API SW blitted onto
    // the Flutter texture surface). Real devices are unaffected.
    bool swRender = configuration.vo == 'sw';
    if (!swRender) {
      try {
        swRender = await _channel.invokeMethod('Utils.IsEmulator') == true;
      } catch (_) {
        swRender = false;
      }
    }
    if (swRender) {
      configuration = configuration.copyWith(
        vo: 'libmpv',
        hwdec: 'no',
        // The bridge blits onto the XComponent's native window (direct
        // composition, proven by the Luna E2 probe); the Flutter texture
        // surface does not display on the emulator.
        darwin: configuration.darwin.copyWith(useNativeSurface: true),
      );
    }

    // Retrieve the native handle of the [Player].
    final handle = await player.handle;
    // Return the existing [VideoController] if it's already created. A
    // controller that is disposing remains cached until the native dispose
    // call completes, so a concurrent create must wait for that barrier.
    final existing = _controllers[handle];
    if (existing != null) {
      final disposal = existing._disposeFuture;
      if (disposal != null) {
        await disposal;
        final current = _controllers[handle];
        if (current != null) return current;
      } else {
        return existing;
      }
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
    controller.swRender = swRender;
    // Mount the XComponent so its onLoad callback can provide the native
    // surface ID. After destruction a live controller keeps the candidate
    // enabled and the widget can mount a new generation; dispose clears it.
    controller.nativeSurfaceCandidate = configuration.darwin.useNativeSurface;
    controller.nativeSurfaceGeneration = (_surfaceGenerations[handle] ?? 0) + 1;
    _surfaceGenerations[handle] = controller.nativeSurfaceGeneration;

    await controller.lock.synchronized(() async {
      // MPV's HarmonyOS video output requires a valid surface ID before the
      // GPU video output is initialized.
      await controller.setProperty('vo', 'null');
      await controller.setProperties(
        {
          'ohos-surface-size': '${rect.width.toInt()}x${rect.height.toInt()}',
          // Software render mode blits onto the texture surface through the
          // native bridge: mpv must not bind the surface as its own window.
          if (!swRender) 'wid': wid.toString(),
          'hwdec': configuration.hwdec!,
          'vid': 'auto',
          if (!swRender) 'force-window': 'yes',
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
          configuration.darwin.useNativeSurface)) {
        await controller.setProperty('vo', configuration.vo!);
      }
    });

    if (swRender) {
      // The software bridge attaches when the XComponent reports its surface
      // (nativeSurfaceReady → _attachNativeSurfaceLocked); the texture
      // surface is not used at all in this mode.
      debugPrint(
        '[OhosVideoController] software render mode: waiting for the '
        'XComponent surface (native surface candidate enabled)',
      );
    }

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
  Future<void> disposeForRebuild() =>
      _disposeFuture ??= _disposeOnce(playerReleasing: false);

  /// Disposes the instance. Releases allocated resources back to the system.
  Future<void> _dispose() =>
      _disposeFuture ??= _disposeOnce(playerReleasing: true);

  Future<void> _disposeOnce({required bool playerReleasing}) async {
    _disposed = true;
    _hdrConfigRevision++;
    _advanceNativeSurfaceGeneration();
    _surfaceResizeSerial++;
    _queuedSurfaceWidth = null;
    _queuedSurfaceHeight = null;
    _queuedViewportWidth = null;
    _queuedViewportHeight = null;
    SwRender.detach();

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

    int? handle = nativeHandle;
    try {
      await lock.synchronized(() async {
        handle ??= await player.handle;
        if (handle == null) return;
        // Stop mpv's producer before releasing the Flutter texture consumer.
        // If this fails, the native dispose call is intentionally not issued;
        // the error is reported to the caller instead of hiding the ordering
        // failure behind an unregister operation.
        // A rebuild and Player.dispose can overlap. The cached dispose future
        // must use the release-safe setter when the callback is active, even
        // if the rebuild call created the future first.
        if (playerReleasing || platform.isReleaseCallbacksActive) {
          await _setPropertyForRelease('vo', 'null');
        } else {
          await setProperty('vo', 'null');
        }
        await _channel.invokeMethod(
          'VideoOutputManager.Dispose',
          {
            'handle': handle.toString(),
          },
        );
      });
    } catch (error, stack) {
      recordFailure(error, stack);
    } finally {
      if (handle != null && identical(_controllers[handle], this)) {
        _controllers.remove(handle);
      }
      _pendingHdrConfiguration = null;
      _nativeViewId = null;
      nativeSurfaceCandidate = false;
      setNativeSurfaceActive(false);
      wid.value = null;
      try {
        wid.dispose();
      } catch (error, stack) {
        recordFailure(error, stack);
      }
      try {
        super.dispose();
      } catch (error, stack) {
        recordFailure(error, stack);
      }
    }
    if (cleanupError != null) {
      Error.throwWithStackTrace(cleanupError!, cleanupStack!);
    }
  }

  /// Currently created [OhosVideoController]s.
  static final _controllers = HashMap<int, OhosVideoController>();
  static final _surfaceGenerations = HashMap<int, int>();

  /// [MethodChannel] for invoking platform specific native implementation.
  static const _channel = MethodChannel('com.alexmercerind/media_kit_video');
}
