import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

import '../hdr/hdr_video_session.dart';
import '../routing/video_route_options.dart';
import '../video_controller/platform_video_controller.dart';
import '../video_controller/video_controller.dart';

/// Explicit application integration, not interception of ordinary Player APIs.
///
/// Mount [controller] before awaiting [open]. Android uses the existing HDR
/// session; other platforms keep their ordinary output (including Darwin's
/// texture/PiP contract) and make no HDR verification claim. All transport
/// requests from this integration must use this object, not the raw Player.
/// Property setters and event subscriptions may continue using [player].
class RoutedVideoPlayback {
  RoutedVideoPlayback._(this.player, this._session, this.options,
      [this._sessionFactory]) {
    final session = _session;
    if (session != null) {
      session.controller.addListener(_outputChanged);
      session.report.addListener(_reportChanged);
      _outputChanged();
    }
  }

  static Future<RoutedVideoPlayback> create(Player player, {
    VideoControllerConfiguration configuration =
        const VideoControllerConfiguration(),
  }) async {
    if (Platform.isAndroid) {
      final options = routeOptionsForLegacyConfiguration(configuration);
      return RoutedVideoPlayback._(player, null, options,
          () => HdrVideoSession(player, configuration: configuration));
    }
    final binding = RoutedVideoPlayback._(player, null,
        EffectiveVideoRouteOptions.resolve());
    binding._controller.value = await VideoController.create(player,
        configuration: configuration);
    return binding;
  }

  @visibleForTesting
  factory RoutedVideoPlayback.forTesting(Player player, {
    HdrVideoSession? session,
    VideoController? legacyController,
    HdrVideoSession Function()? sessionFactory,
  }) {
    final binding = RoutedVideoPlayback._(player, session,
        EffectiveVideoRouteOptions.resolve(), sessionFactory);
    if (session == null) binding._controller.value = legacyController;
    return binding;
  }

  final Player player;
  HdrVideoSession? _session;
  final HdrVideoSession Function()? _sessionFactory;
  Future<void> _mode = Future<void>.value();
  bool _retiringSession = false;
  final EffectiveVideoRouteOptions options;
  final _controller = ValueNotifier<VideoController?>(null);
  final _ready = ValueNotifier<bool>(false);
  final _errors = StreamController<Object>.broadcast();
  ValueListenable<VideoController?> get controller => _controller;
  ValueListenable<bool> get ready => _ready;
  Stream<Object> get errors => _errors.stream;

  bool _closed = false;
  bool _desiredPlaying = false;
  int _generation = 0;
  int _intent = 0;
  int _readinessEpoch = 0;
  (int, int, int)? _applied;
  Duration? _pendingSeek;
  Object? _reportedError;
  Future<void> _transport = Future<void>.value();
  Future<void>? _disposeFuture;

  void _ensureOpen() {
    if (_closed) throw StateError('RoutedVideoPlayback is closed');
  }

  void _outputChanged() {
    if (!_closed) _controller.value = _session!.controller.value;
  }

  void _reportChanged() {
    if (_closed) return;
    final report = _session!.report.value;
    _ready.value = report.verified && report.error == null;
    if (!_ready.value) _readinessEpoch++;
    if (report.error case final error?) _reportError(error);
    // Configuration/capability rebuilds are deliberately opened paused. The
    // newest play/pause/seek intent is applied only after the session's review.
    if (_ready.value) _applyIntent().catchError(_reportError);
  }

  void _reportError(Object error) {
    if (_closed || error is RoutedOpenSuperseded ||
        identical(error, _reportedError)) return;
    _reportedError = error;
    _errors.add(error);
  }

  /// Completes after the explicit session's open/review and transport intent.
  /// The view must already follow [controller]; readiness is NOT a mount gate.
  Future<void> open(Media media, {bool play = true, bool video = true}) {
    _ensureOpen();
    final generation = ++_generation;
    _intent++;
    _desiredPlaying = play;
    _pendingSeek = null;
    _reportedError = null;
    _ready.value = false;
    final previousTransport = _transport;
    return () async {
      try {
        await previousTransport;
        if (_closed || generation != _generation) throw const RoutedOpenSuperseded();
        await _prepareMode(video, generation);
        if (_closed || generation != _generation) throw const RoutedOpenSuperseded();
        final session = _session;
        if (session == null) {
          await player.open(media, play: false);
        } else {
          // Always false: an internal rebuild must never restore a stale play
          // flag captured by an earlier open. Report notification reapplies the
          // latest intent only after verification. Preserve Media.start.
          await session.open(media, options: options,
              start: media.start, play: false);
        }
        if (_closed || generation != _generation) throw const RoutedOpenSuperseded();
        if (session != null) {
          final report = session.report.value;
          if (report.error case final error?) throw error;
          if (!report.verified) throw StateError('Routed open has no verified output');
        }
        _ready.value = true;
        await _applyIntent();
        if (_closed || generation != _generation) throw const RoutedOpenSuperseded();
      } catch (error) {
        if (!_closed && generation == _generation) {
          _ready.value = false;
          _reportError(error);
        }
        rethrow;
      }
    }();
  }

  // Only explicit audio/video mode switches are serialized here. Video-to-video
  // opens still enter the existing session immediately and supersede its old
  // transaction; they are never queued behind a blocked open awaiting a view.
  Future<void> _prepareMode(bool video, int generation) {
    final task = _mode.then((_) async {
      void check() {
        if (_closed || generation != _generation) throw const RoutedOpenSuperseded();
      }
      check();
      if (_sessionFactory == null) return; // ordinary non-Android output
      if ((_retiringSession || !video) && _session != null) {
        final old = _session!;
        if (!_retiringSession) {
          old.controller.removeListener(_outputChanged);
          old.report.removeListener(_reportChanged);
          _controller.value = null;
          _retiringSession = true;
        }
        await old.dispose();
        _session = null;
        _retiringSession = false;
      }
      check();
      if (video && _session == null) {
        await player.stop();
        check();
        final next = _sessionFactory!();
        _session = next;
        next.controller.addListener(_outputChanged);
        next.report.addListener(_reportChanged);
        _outputChanged();
      }
    });
    _mode = task.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return task;
  }

  /// While opening these acknowledge intent, not physical playback. A newer
  /// intent supersedes queued work; it cannot resurrect a closed/older source.
  Future<void> play() {
    _ensureOpen();
    _desiredPlaying = true;
    _intent++;
    return _applyIntent();
  }

  Future<void> pause() {
    _ensureOpen();
    _desiredPlaying = false;
    _intent++;
    return _applyIntent();
  }

  Future<void> seek(Duration position) {
    _ensureOpen();
    _pendingSeek = position;
    _intent++;
    return _applyIntent();
  }

  Future<void> playOrPause() => _desiredPlaying ? pause() : play();

  Future<void> _applyIntent() {
    final generation = _generation, intent = _intent, readiness = _readinessEpoch;
    final key = (generation, intent, readiness);
    final task = _transport.then((_) async {
      bool current() => !_closed && generation == _generation &&
          intent == _intent && readiness == _readinessEpoch && _ready.value;
      if (!current() || _applied == key) return;
      final seek = _pendingSeek;
      if (seek != null) {
        await player.seek(seek);
        if (!current()) return;
        _pendingSeek = null;
      }
      if (_desiredPlaying) {
        await player.play();
      } else {
        await player.pause();
      }
      if (current()) _applied = key;
    });
    // Keep the queue usable, but return the original failure to the caller.
    _transport = task.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return task;
  }

  /// Stop/restore output ownership before destroying the raw player. Failed
  /// cleanup keeps admission closed but may be retried by calling dispose again.
  Future<void> dispose() {
    if (_disposeFuture case final pending?) return pending;
    if (!_closed) {
      _closed = true;
      _generation++;
      _intent++;
      _ready.value = false;
      _controller.value = null;
      _session?.controller.removeListener(_outputChanged);
      _session?.report.removeListener(_reportChanged);
    }
    final task = () async {
      // Invalidate a pending session open immediately; do not await its open
      // Future or widget initialization before asking the owner to close.
      await _mode;
      await Future.wait<void>([
        _transport,
        if (_session != null) _session!.dispose(),
      ]);
      await player.dispose();
      await _errors.close();
      _controller.dispose();
      _ready.dispose();
    }();
    _disposeFuture = task;
    unawaited(task.then<void>((_) {}, onError: (Object _, StackTrace __) {
      if (identical(_disposeFuture, task)) _disposeFuture = null;
    }));
    return task;
  }
}

class RoutedOpenSuperseded implements Exception {
  const RoutedOpenSuperseded();
  @override
  String toString() => 'Routed open superseded or closed';
}

/// Decode intent, not a past hwdec-current observation. The application uses
/// null plus disabled acceleration for its software choice. Mixed direct/copy
/// fallback lists must not be classified as copy-only by substring matching.
EffectiveVideoRouteOptions routeOptionsForLegacyConfiguration(
    VideoControllerConfiguration configuration) {
  final tokens = (configuration.hwdec ?? '').split(',')
      .map((value) => value.trim()).where((value) => value.isNotEmpty).toList();
  final software = !configuration.enableHardwareAcceleration ||
      (tokens.length == 1 && tokens.single == 'no');
  final copyOnly = tokens.isNotEmpty && tokens.every((value) =>
      value == 'auto-copy' || value.endsWith('-copy'));
  return EffectiveVideoRouteOptions.resolve(application: VideoRouteOptions(
    decode: software
        ? const VideoRouteSelection.require(VideoDecodeTarget.software) : null,
    importPreference: !software && copyOnly ? VideoImportPreference.preferCopy : null,
  ));
}
