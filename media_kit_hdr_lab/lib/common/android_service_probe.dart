import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart'
    show HdrCapabilities, HdrDecoderInfo;

/// Opt-in VM-service diagnostics for Android devices without usable logcat.
/// The registered handler follows the current test-page player.
class AndroidServiceProbe {
  static const _enabled =
      bool.fromEnvironment('MEDIA_KIT_ANDROID_SERVICE_PROBE');
  static Player? _player;
  static Future<void> Function(String)? _open;
  static String? Function()? _report;
  static Future<Map<String, Object?>?> Function()? _surfaceSnapshot;
  static _NativeDvOptionTransaction? _nativeDvTransaction;
  static int _generation = 0;
  static bool _busy = false;
  static bool _registered = false;
  static StreamSubscription<PlayerLog>? _logsSubscription;
  static final _logs = <String>[];
  static final _codecLifecycleLogs = <String>[];
  static final _nativeDvInputLogs = <String>[];
  static int _nativeDvInputLogsDropped = 0;

  static void attach(Player player, Future<void> Function(String) open,
      {String? Function()? report,
      Future<Map<String, Object?>?> Function()? surfaceSnapshot}) {
    if (!kDebugMode || !Platform.isAndroid || !_enabled) return;
    _player = player;
    _open = open;
    _report = report;
    _surfaceSnapshot = surfaceSnapshot;
    _generation++;
    unawaited(_logsSubscription?.cancel());
    _logs.clear();
    _codecLifecycleLogs.clear();
    _nativeDvInputLogs.clear();
    _nativeDvInputLogsDropped = 0;
    _logsSubscription = player.stream.log.listen((log) {
      if (!identical(_player, player)) return;
      final entry =
          '${DateTime.now().toUtc().toIso8601String()} ${log.prefix} ${log.level} ${log.text}';
      _logs.add(entry);
      if (_logs.length > 300) _logs.removeAt(0);
      if (log.text.contains('native_dv_diag')) {
        _nativeDvInputLogs.add(entry);
        if (_nativeDvInputLogs.length > 4096) {
          _nativeDvInputLogs.removeAt(0);
          _nativeDvInputLogsDropped++;
        }
      }
      if (_isCodecLifecycleLog(log)) {
        _codecLifecycleLogs.add(entry);
        if (_codecLifecycleLogs.length > 100) {
          _codecLifecycleLogs.removeAt(0);
        }
      }
    });
    if (_registered) return;
    _registered = true;
    developer.registerExtension('ext.media_kit.hdr_lab.probe', (_, args) async {
      final current = _player;
      if (current == null) {
        return developer.ServiceExtensionResponse.error(
            developer.ServiceExtensionResponse.extensionError, 'No player');
      }
      if (_busy) {
        return developer.ServiceExtensionResponse.error(
            developer.ServiceExtensionResponse.extensionError, 'Probe busy');
      }
      _busy = true;
      final action = args['action'] ?? 'snapshot';
      if (action == 'open' ||
          action == 'native-dv-open' ||
          action == 'video-reinit') {
        _generation++;
        _logs.clear();
        _codecLifecycleLogs.clear();
      }
      final generation = _generation;
      final open = _open;
      try {
        String? actionResult;
        Map<String, Object?>? actionData;
        switch (action) {
          case 'open':
            final path = args['path'];
            if (path == null || path.isEmpty) {
              throw ArgumentError('path is required');
            }
            if (_nativeDvTransaction != null &&
                !identical(_nativeDvTransaction!.player, current)) {
              throw StateError(
                  'A native-DV option is pending restoration for another player');
            }
            final transaction = _nativeDvTransaction;
            if (transaction != null && identical(transaction.player, current)) {
              await _restoreNativeDvOptions(transaction);
            }
            _ensureProbeCurrent(current, generation);
            await open!(path);
            break;
          case 'native-dv-open':
            final path = args['path'];
            if (path == null || path.isEmpty) {
              throw ArgumentError('path is required');
            }
            if (_report?.call() != null) {
              throw StateError(
                  'native-dv-open requires a player without an HDR session');
            }
            final requestedRenderMode = args['renderMode'] ?? 'timed';
            final inputDiag = args['inputDiag'] ?? 'false';
            if (inputDiag != 'true' && inputDiag != 'false') {
              throw ArgumentError('inputDiag must be true or false');
            }
            final requestedNativeOption = inputDiag == 'true'
                ? 'native_dv=1,native_dv_diag=1'
                : 'native_dv=1';
            if (requestedRenderMode != 'boolean' &&
                requestedRenderMode != 'timed') {
              throw ArgumentError('renderMode must be boolean or timed');
            }
            final vo = await current.getProperty('vo');
            _ensureProbeCurrent(current, generation);
            if (vo != 'mediacodec_embed') {
              throw StateError(
                  'native-dv-open requires vo=mediacodec_embed (got $vo)');
            }
            final hwdecOption = await current.getProperty('hwdec');
            _ensureProbeCurrent(current, generation);
            if (hwdecOption != 'mediacodec') {
              throw StateError(
                  'native-dv-open requires hwdec=mediacodec (got $hwdecOption)');
            }
            final durationProperty = await current.getProperty('duration');
            _ensureProbeCurrent(current, generation);
            final parsedDuration = double.tryParse(durationProperty);
            final hasStableDuration = current.state.duration > Duration.zero ||
                (current.state.completed &&
                    parsedDuration != null &&
                    parsedDuration.isFinite &&
                    parsedDuration > 0);
            if (!hasStableDuration) {
              throw StateError('native-dv-open requires an initialized media '
                  'with a known duration');
            }
            final transaction = _nativeDvTransaction;
            if (transaction != null &&
                !identical(transaction.player, current)) {
              throw StateError(
                  'A native-DV option is pending restoration for another player');
            }
            final alreadyEnabled = transaction != null;
            final currentOption = await current.getProperty('vd-lavc-o');
            _ensureProbeCurrent(current, generation);
            final currentRenderMode =
                await current.getProperty('mediacodec-embed-render-mode');
            _ensureProbeCurrent(current, generation);
            if (alreadyEnabled) {
              if (transaction.nativeOption != requestedNativeOption) {
                throw StateError('Restore with ordinary open before changing '
                    'native input diagnostics');
              }
              if (transaction.renderMode != requestedRenderMode) {
                throw StateError('A native-DV transaction is already active '
                    'with render-mode=${transaction.renderMode}; restore it '
                    'with ordinary open before changing modes');
              }
              if (currentOption != transaction.nativeOption) {
                throw StateError('vd-lavc-o changed during native-DV probe: '
                    '$currentOption');
              }
              if (currentRenderMode != requestedRenderMode) {
                throw StateError('mediacodec-embed-render-mode changed during '
                    'native-DV probe: $currentRenderMode');
              }
            } else {
              if (currentOption.trim().isNotEmpty) {
                throw StateError('native-dv-open requires an empty vd-lavc-o '
                    '(got $currentOption)');
              }
              if (currentRenderMode != 'boolean') {
                throw StateError('native-dv-open requires the default '
                    'mediacodec-embed-render-mode=boolean (got '
                    '$currentRenderMode)');
              }
              final created = _NativeDvOptionTransaction(
                player: current,
                originalOption: currentOption,
                originalRenderMode: currentRenderMode,
                renderMode: requestedRenderMode,
                nativeOption: requestedNativeOption,
              );
              _nativeDvTransaction = created;
            }
            final activeTransaction = _nativeDvTransaction!;
            Object? nativeOpenError;
            StackTrace? nativeOpenStack;
            try {
              await current.stop();
              _ensureProbeCurrent(current, generation);
              if (!alreadyEnabled) {
                final nativePlayer = current.platform as NativePlayer;
                await nativePlayer.setPropertyStrictAsync(
                  'vd-lavc-o',
                  activeTransaction.nativeOption,
                  waitForInitialization: false,
                );
                _ensureProbeCurrent(current, generation);
                final appliedOption = await current.getProperty('vd-lavc-o');
                _ensureProbeCurrent(current, generation);
                if (appliedOption != activeTransaction.nativeOption) {
                  throw StateError('vd-lavc-o did not acknowledge '
                      '${activeTransaction.nativeOption} '
                      '(got $appliedOption)');
                }
                _ensureProbeCurrent(current, generation);
                await nativePlayer.setPropertyStrictAsync(
                  'mediacodec-embed-render-mode',
                  requestedRenderMode,
                  waitForInitialization: false,
                );
                _ensureProbeCurrent(current, generation);
                final appliedRenderMode =
                    await current.getProperty('mediacodec-embed-render-mode');
                _ensureProbeCurrent(current, generation);
                if (appliedRenderMode != requestedRenderMode) {
                  throw StateError('mediacodec-embed-render-mode did not '
                      'acknowledge $requestedRenderMode '
                      '(got $appliedRenderMode)');
                }
              }
              await open!(path);
            } catch (error, stack) {
              nativeOpenError = error;
              nativeOpenStack = stack;
            }
            if (nativeOpenError != null) {
              try {
                await _restoreNativeDvOptions(activeTransaction);
              } catch (restoreError) {
                // Preserve the native open failure as the reported error.
                developer.log('native-dv-open rollback failed: $restoreError');
              }
              Error.throwWithStackTrace(nativeOpenError, nativeOpenStack!);
            }
            if (!identical(_player, current) || generation != _generation) {
              throw StateError('Player changed during probe');
            }
            actionResult = 'native-dv-open requested; options remain active';
            break;
          case 'video-reinit':
            actionResult = await _reinitializeVideo(current, generation);
            break;
          case 'native-dv-facts':
            actionResult = 'native-dv-facts requested';
            actionData = await _readNativeDvFacts(current, generation);
            break;
          case 'native-dv-input-logs':
            _ensureProbeCurrent(current, generation);
            // Read only the received log buffer: no decoder lock or property
            // queries. Receipt timestamps cannot establish native event time.
            return developer.ServiceExtensionResponse.result(jsonEncode({
              'generation': generation,
              'receiptTimestampsOnly': true,
              'dropped': _nativeDvInputLogsDropped,
              'logs': List<String>.of(_nativeDvInputLogs),
            }));
          case 'capabilities':
            actionResult = 'capabilities requested';
            actionData = await _readCapabilities(current, generation);
            _ensureProbeCurrent(current, generation);
            return developer.ServiceExtensionResponse.result(jsonEncode({
              'generation': generation,
              'actionResult': actionResult,
              'actionData': actionData,
            }));
          case 'play':
            await current.play();
            break;
          case 'pause':
            await current.pause();
            break;
          case 'seek':
            final seconds = double.parse(args['seconds'] ?? '');
            if (!seconds.isFinite || seconds < 0) {
              throw ArgumentError('seconds must be finite and nonnegative');
            }
            await current.seek(Duration(
                microseconds:
                    (seconds * Duration.microsecondsPerSecond).round()));
            break;
          case 'snapshot':
            break;
          case 'p5-probe':
            await const MethodChannel('media_kit_hdr_lab/p5_codec_probe')
                .invokeMethod<Object?>('Run', {
              'path': args['path'],
              'maxFrames': 1,
            });
            break;
          default:
            throw ArgumentError('Unknown action');
        }
        final properties = <String, String>{};
        for (final name in const [
          'path',
          'vo',
          'wid',
          'vid',
          'idle-active',
          'hwdec',
          'hwdec-current',
          'vd-lavc-o',
          'mediacodec-embed-render-mode',
          'android-native-dv-bridge-api',
          'video-codec',
          'video-params',
          'video-out-params',
          'time-pos',
          'duration',
          'pause',
          'frame-drop-count',
          'decoder-frame-drop-count',
          'mistimed-frame-count',
          'vo-delayed-frame-count',
        ]) {
          try {
            properties[name] = await current.getProperty(name);
            _ensureProbeCurrent(current, generation);
          } catch (error) {
            _ensureProbeCurrent(current, generation);
            properties[name] = 'ERROR:$error';
          }
        }
        if (!identical(_player, current) || generation != _generation) {
          throw StateError('Player changed during probe');
        }
        Map<String, Object?>? surface;
        final surfaceSnapshot = _surfaceSnapshot;
        if (surfaceSnapshot != null) {
          surface = await surfaceSnapshot();
          _ensureProbeCurrent(current, generation);
        }
        return developer.ServiceExtensionResponse.result(jsonEncode({
          'generation': generation,
          if (actionResult != null) 'actionResult': actionResult,
          if (actionData != null) 'actionData': actionData,
          'hdrSessionReport': _report?.call(),
          'properties': properties,
          'surface': surface,
          'playing': current.state.playing,
          'completed': current.state.completed,
          'positionMs': current.state.position.inMilliseconds,
          'logs': List<String>.of(_logs),
          'codecLifecycleLogs': List<String>.of(_codecLifecycleLogs),
        }));
      } catch (error) {
        return developer.ServiceExtensionResponse.error(
            developer.ServiceExtensionResponse.extensionError, '$error');
      } finally {
        _busy = false;
      }
    });
  }

  static void detach(Player player) {
    if (!identical(_player, player)) return;
    final transaction = _nativeDvTransaction;
    if (transaction != null && identical(transaction.player, player)) {
      unawaited(_restoreNativeDvOptions(transaction).catchError((_) {}));
    }
    _player = null;
    _open = null;
    _report = null;
    _surfaceSnapshot = null;
    _generation++;
    unawaited(_logsSubscription?.cancel());
    _logsSubscription = null;
  }

  static Future<String> _reinitializeVideo(
      Player player, int generation) async {
    if (_report?.call() != null) {
      throw StateError('video-reinit requires a player without an HDR session');
    }
    final transaction = _nativeDvTransaction;
    if (transaction == null ||
        !identical(transaction.player, player) ||
        !transaction.nativeOptionPending ||
        !transaction.renderModePending) {
      throw StateError(
          'video-reinit requires an owned native-DV transaction for this player');
    }
    final vo = await player.getProperty('vo');
    _ensureProbeCurrent(player, generation);
    if (vo != 'mediacodec_embed') {
      throw StateError('video-reinit requires vo=mediacodec_embed (got $vo)');
    }
    final hwdec = await player.getProperty('hwdec');
    _ensureProbeCurrent(player, generation);
    if (hwdec != 'mediacodec') {
      throw StateError('video-reinit requires hwdec=mediacodec (got $hwdec)');
    }
    final option = await player.getProperty('vd-lavc-o');
    _ensureProbeCurrent(player, generation);
    if (option != transaction.nativeOption) {
      throw StateError('video-reinit requires owned vd-lavc-o=native_dv=1');
    }
    final renderMode = await player.getProperty('mediacodec-embed-render-mode');
    _ensureProbeCurrent(player, generation);
    if (renderMode != transaction.renderMode) {
      throw StateError('video-reinit requires owned render-mode='
          '${transaction.renderMode} (got $renderMode)');
    }

    final savedVid = await player.getProperty('vid');
    _ensureProbeCurrent(player, generation);
    final savedVideoTrack = int.tryParse(savedVid);
    if (savedVideoTrack == null || savedVideoTrack <= 0) {
      throw StateError('video-reinit requires a positive numeric vid track '
          '(got $savedVid)');
    }
    final savedPause = await player.getProperty('pause');
    _ensureProbeCurrent(player, generation);
    if (savedPause != 'yes' && savedPause != 'no') {
      throw StateError('video-reinit cannot preserve unknown pause value '
          '$savedPause');
    }
    final nativePlayer = player.platform as NativePlayer;
    Object? operationError;
    StackTrace? operationStack;
    final restoreErrors = <String>[];
    try {
      await _setAndVerifyProperty(
        player,
        nativePlayer,
        'pause',
        'yes',
        generation,
      );
      await _setAndVerifyProperty(
        player,
        nativePlayer,
        'vid',
        'no',
        generation,
      );
    } catch (error, stack) {
      operationError = error;
      operationStack = stack;
    } finally {
      try {
        await _setAndVerifyProperty(
          player,
          nativePlayer,
          'vid',
          savedVid,
          generation,
        );
      } catch (error) {
        restoreErrors.add('vid restore failed: $error');
      }
      try {
        await _setAndVerifyProperty(
          player,
          nativePlayer,
          'pause',
          savedPause,
          generation,
        );
      } catch (error) {
        restoreErrors.add('pause restore failed: $error');
      }
    }
    if (operationError != null) {
      if (restoreErrors.isNotEmpty) {
        throw StateError('video-reinit failed: $operationError; '
            '${restoreErrors.join('; ')}');
      }
      Error.throwWithStackTrace(operationError, operationStack!);
    }
    if (restoreErrors.isNotEmpty) {
      throw StateError(restoreErrors.join('; '));
    }
    _ensureProbeCurrent(player, generation);
    return 'video-reinit requested; vid and pause restore acknowledged';
  }

  static Future<void> _setAndVerifyProperty(
    Player player,
    NativePlayer nativePlayer,
    String property,
    String value,
    int generation,
  ) async {
    _ensureProbeCurrent(player, generation);
    await nativePlayer.setPropertyStrictAsync(
      property,
      value,
      waitForInitialization: false,
    );
    _ensureProbeCurrent(player, generation);
    final actual = await player.getProperty(property);
    _ensureProbeCurrent(player, generation);
    if (actual != value) {
      throw StateError('$property did not acknowledge $value (got $actual)');
    }
  }

  static Future<Map<String, Object?>> _readNativeDvFacts(
      Player player, int generation) async {
    final pathBefore = await player.getProperty('path');
    _ensureProbeCurrent(player, generation);
    final bridgeApiRaw = await _readProbeProperty(
      player,
      'android-native-dv-bridge-api',
      generation,
    );
    final mediaCodecInfoRaw = await _readProbeProperty(
      player,
      'android-mediacodec-info',
      generation,
    );
    final pathAfter = await player.getProperty('path');
    _ensureProbeCurrent(player, generation);
    if (pathBefore != pathAfter) {
      throw StateError('Media path changed during native-DV fact read: '
          '$pathBefore -> $pathAfter');
    }
    final bridgeApi = _parseBridgeApi(bridgeApiRaw);
    final mediaCodecInfo = _parseCodecConfiguration(mediaCodecInfoRaw);
    return {
      'path': pathAfter,
      'raw': {
        'android-native-dv-bridge-api': bridgeApiRaw,
        'android-mediacodec-info': mediaCodecInfoRaw,
      },
      'parsed': {
        'nativeDvBridgeApi': bridgeApi,
        'nativeDvBridgeSupported': bridgeApi == 1,
        'codecConfiguration': mediaCodecInfo,
        'codecConfigurationOnly': true,
        'nativeDvActive': null,
      },
    };
  }

  static Future<Map<String, Object?>> _readCapabilities(
      Player player, int generation) async {
    _ensureProbeCurrent(player, generation);
    final capabilities = await HdrCapabilities.query(player: null);
    _ensureProbeCurrent(player, generation);
    final displayHdrTypes = capabilities.displayHdrTypes?.toList();
    displayHdrTypes?.sort();
    return {
      'sdkInt': capabilities.sdkInt,
      'displayHdrTypes': displayHdrTypes,
      'p5PipelineAvailable': capabilities.p5PipelineAvailable,
      'nativeDvBridgeApi': capabilities.nativeDvBridgeApi,
      'hevcDecoders': capabilities.hevcDecoders
          .map(_decoderCapabilitySummary)
          .toList(growable: false),
      'dolbyVisionDecoders': capabilities.dolbyVisionDecoders
          .map(_decoderCapabilitySummary)
          .toList(growable: false),
    };
  }

  static Future<String> _readProbeProperty(
    Player player,
    String property,
    int generation,
  ) async {
    try {
      final value = await player.getProperty(property);
      _ensureProbeCurrent(player, generation);
      return value;
    } catch (error) {
      _ensureProbeCurrent(player, generation);
      return 'ERROR:$error';
    }
  }

  static int? _parseBridgeApi(String raw) {
    if (raw.isEmpty ||
        raw.startsWith('ERROR:') ||
        raw.toLowerCase() == 'unavailable') {
      return null;
    }
    final value = int.tryParse(raw.trim());
    return value == null || value < 0 ? null : value;
  }

  static Object? _parseCodecConfiguration(String raw) {
    if (raw.isEmpty ||
        raw.startsWith('ERROR:') ||
        raw.toLowerCase() == 'unavailable') {
      return null;
    }
    try {
      final parsed = jsonDecode(raw);
      if (parsed is Map || parsed is List) return parsed;
      return {'value': parsed};
    } catch (_) {
      return {'unparsed': raw};
    }
  }

  static Map<String, Object?> _decoderCapabilitySummary(
          HdrDecoderInfo decoder) =>
      {
        'name': decoder.name,
        'mimeType': decoder.mimeType,
        'hardwareAcceleration': decoder.hardwareAcceleration,
        'profiles': decoder.profiles,
        'main10': decoder.main10,
        'supports4K': decoder.supports4K,
        'max4KFps': decoder.max4KFps,
      };

  static bool _isCodecLifecycleLog(PlayerLog log) {
    final text = log.text.toLowerCase();
    const keywords = [
      'native_dv',
      'native dv',
      'configure',
      'decoder start',
      'flush',
      'stop',
      'delete',
      'decoder fallback',
      'fallback',
      'reinit',
      'invalid video timestamp',
    ];
    if (keywords.any(text.contains)) return true;
    final level = log.level.toLowerCase();
    return level == 'warn' ||
        level == 'warning' ||
        level == 'error' ||
        level == 'fatal';
  }

  static Future<void> _restoreNativeDvOptions(
      _NativeDvOptionTransaction transaction) async {
    final inProgress = transaction.restoreFuture;
    if (inProgress != null) {
      await inProgress;
      return;
    }
    late final Future<void> tracked;
    tracked = _performNativeDvRestore(transaction).whenComplete(() {
      if (identical(transaction.restoreFuture, tracked)) {
        transaction.restoreFuture = null;
      }
    });
    transaction.restoreFuture = tracked;
    await tracked;
  }

  static Future<void> _performNativeDvRestore(
      _NativeDvOptionTransaction transaction) async {
    if (!identical(_nativeDvTransaction, transaction)) return;
    final player = transaction.player;
    final nativePlayer = player.platform as NativePlayer;
    if (nativePlayer.disposed ||
        nativePlayer.isDisposing ||
        nativePlayer.isTerminated) {
      if (identical(_nativeDvTransaction, transaction)) {
        _nativeDvTransaction = null;
      }
      return;
    }
    final failures = <String>[];
    await _restoreOwnedOption(
      transaction,
      property: 'mediacodec-embed-render-mode',
      ownedValue: transaction.renderMode,
      originalValue: transaction.originalRenderMode,
      clearPending: () => transaction.renderModePending = false,
      nativePlayer: nativePlayer,
      failures: failures,
    );
    await _restoreOwnedOption(
      transaction,
      property: 'vd-lavc-o',
      ownedValue: transaction.nativeOption,
      originalValue: transaction.originalOption,
      clearPending: () => transaction.nativeOptionPending = false,
      nativePlayer: nativePlayer,
      failures: failures,
    );
    if (!identical(_nativeDvTransaction, transaction)) return;
    if (!transaction.renderModePending && !transaction.nativeOptionPending) {
      _nativeDvTransaction = null;
    }
    if (failures.isNotEmpty) {
      throw StateError(failures.join('; '));
    }
  }

  static Future<void> _restoreOwnedOption(
    _NativeDvOptionTransaction transaction, {
    required String property,
    required String ownedValue,
    required String originalValue,
    required void Function() clearPending,
    required NativePlayer nativePlayer,
    required List<String> failures,
  }) async {
    if (!transaction.pending(property)) return;
    final player = transaction.player;
    try {
      final currentValue = await player.getProperty(property);
      if (!identical(_nativeDvTransaction, transaction)) return;
      if (currentValue == originalValue) {
        clearPending();
        return;
      }
      if (currentValue != ownedValue) {
        clearPending();
        failures.add('$property ownership conflict; preserved current value: '
            '$currentValue');
        return;
      }
      await nativePlayer.setPropertyStrictAsync(
        property,
        originalValue,
        waitForInitialization: false,
      );
      if (!identical(_nativeDvTransaction, transaction)) return;
      final restoredValue = await player.getProperty(property);
      if (!identical(_nativeDvTransaction, transaction)) return;
      if (restoredValue != originalValue) {
        failures.add('$property restore was not acknowledged '
            '(got $restoredValue)');
        return;
      }
      clearPending();
    } catch (error) {
      if (identical(_nativeDvTransaction, transaction)) {
        failures.add('$property restore failed: $error');
      }
    }
  }

  static void _ensureProbeCurrent(Player player, int generation) {
    if (!identical(_player, player) || generation != _generation) {
      throw StateError('Player changed during probe');
    }
  }
}

class _NativeDvOptionTransaction {
  _NativeDvOptionTransaction({
    required this.player,
    required this.originalOption,
    required this.originalRenderMode,
    required this.renderMode,
    required this.nativeOption,
  });

  final Player player;
  final String originalOption;
  final String originalRenderMode;
  final String renderMode;
  final String nativeOption;
  bool nativeOptionPending = true;
  bool renderModePending = true;
  Future<void>? restoreFuture;

  bool pending(String property) =>
      property == 'vd-lavc-o' ? nativeOptionPending : renderModePending;
}
