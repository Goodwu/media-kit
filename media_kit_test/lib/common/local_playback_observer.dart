import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

// Do not create the lazy video controller here or release initialization
// barriers. Native property snapshots run once, after playback is established;
// their synchronous FFI may perturb timing, so exclude that interval.
class LocalPlaybackObserver {
  static bool get enabled => !kIsWeb && Platform.isMacOS &&
      Platform.environment['PILIPLUSX_FRAME_PACING_DIAGNOSTICS'] == '1';

  final Player player;
  final Stopwatch _clock = Stopwatch()..start();
  late final File _file = File(
    '${Directory.systemTemp.path}/media-kit-demo-initialization-$pid.jsonl',
  );
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  VideoController? _controller;
  Timer? _timer;
  bool _stopped = false;
  int _samples = 0;
  int _request = 0;
  int _records = 0;
  int _lastErrorSecond = -1;
  bool _propertiesRequested = false;

  LocalPlaybackObserver(this.player) {
    _subscriptions.add(player.stream.error.listen(
      (error) {
        final second = _clock.elapsed.inSeconds;
        if (second == _lastErrorSecond) return;
        _lastErrorSecond = second;
        _record({'event': 'error', 'value': error});
      },
    ));
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _snapshot();
      if (++_samples >= 180) stop();
    });
    _record({'event': 'observer.started'});
  }

  VideoController observe(VideoController controller) {
    _controller = controller;
    return controller;
  }

  void observeOpen(Future<void> result, String source) {
    final request = ++_request;
    final began = _clock.elapsedMicroseconds;
    _record({'event': 'open.requested', 'request': request, 'source': source});
    result.then((_) {
      _record({
        'event': 'open.completed',
        'request': request,
        'elapsedUs': _clock.elapsedMicroseconds - began,
      });
    }, onError: (Object error, StackTrace stack) {
      _record({
        'event': 'open.failed',
        'request': request,
        'error': '$error',
      });
    });
  }

  void observeOperation(Future<void> result, String event,
      Map<String, Object?> fields) {
    _record({'event': '$event.requested', ...fields});
    result.then((_) {
      _record({'event': '$event.completed', ...fields});
    }, onError: (Object error, StackTrace stack) {
      _record({'event': '$event.failed', 'error': '$error', ...fields});
    });
  }

  void _snapshot() {
    final state = player.state;
    final controller = _controller;
    final native = controller?.notifier.value;
    _record({
      'event': 'state',
      'playerInitialized': player.platform?.completer.isCompleted,
      'videoAttached': player.platform?.isVideoControllerAttached,
      'videoInitialized': player.platform?.videoControllerCompleter.isCompleted,
      'controllerObserved': controller != null,
      'controllerInitialized': controller?.platform.isCompleted,
      'controllerType': native?.runtimeType.toString(),
      'id': controller?.id.value,
      'rect': _rect(controller?.rect.value),
      'nativeId': native?.id.value,
      'nativeRect': _rect(native?.rect.value),
      'playlistCount': state.playlist.medias.length,
      'playing': state.playing,
      'buffering': state.buffering,
      'positionMs': state.position.inMilliseconds,
      'durationMs': state.duration.inMilliseconds,
      'width': state.width,
      'height': state.height,
    });
    if (!_propertiesRequested &&
        !_stopped &&
        (state.width ?? 0) > 0 &&
        state.position > Duration.zero &&
        !state.buffering &&
        controller?.platform.isCompleted == true) {
      _propertiesRequested = true;
      unawaited(_properties());
    }
  }

  Map<String, double>? _rect(Rect? value) => value == null ? null : {
    'width': value.width,
    'height': value.height,
  };

  Future<void> _properties() async {
    // One serial batch, no retries, no timer per native read. Dart timeouts
    // cannot interrupt synchronous FFI; do not claim a hard native deadline.
    const names = [
      'hwdec-current', 'video-params', 'video-out-params',
      'target-prim', 'target-trc', 'target-peak', 'tone-mapping',
      'video-sync', 'container-fps', 'display-fps',
      'decoder-frame-drop-count', 'frame-drop-count',
    ];
    final generation = _request;
    for (final name in names) {
      if (_stopped || generation != _request) return;
      final began = _clock.elapsedMicroseconds;
      try {
        final value = await player.getProperty(
          name, waitForInitialization: false,
        );
        if (_stopped || generation != _request) return;
        _record({'event': 'property', 'name': name,
          'requestGeneration': generation,
          'status': value.isEmpty ? 'unavailable' : 'available',
          'value': value, 'beginUs': began, 'endUs': _clock.elapsedMicroseconds});
      } catch (error) {
        if (_stopped || generation != _request) return;
        _record({'event': 'property', 'name': name, 'status': 'unavailable',
          'requestGeneration': generation,
          'error': '$error', 'beginUs': began, 'endUs': _clock.elapsedMicroseconds});
      }
    }
  }

  void _record(Map<String, Object?> values) {
    if (_stopped || _records >= 512) return;
    _records++;
    final line = jsonEncode({
      'utc': DateTime.now().toUtc().toIso8601String(),
      'elapsedUs': _clock.elapsedMicroseconds,
      ...values,
    }).replaceAll(RegExp(r'https?://[^"\s]+'), '<remote-uri>');
    // Initialization diagnostics only: synchronous file IO may perturb timing.
    // Errors are limited to one per second; all events share a 512-line cap.
    // Logging errors must not affect playback or lifecycle.
    try {
      _file.writeAsStringSync('$line\n', mode: FileMode.append);
    } catch (_) {}
  }

  void stop() {
    if (_stopped) return;
    _stopped = true;
    _timer?.cancel();
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
    _controller = null;
  }
}
