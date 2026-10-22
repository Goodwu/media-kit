import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

import '../hdr/hdr_source_descriptor.dart';
import '../video_controller/video_controller.dart';
import '../video_controller/platform_video_controller.dart';
import 'player_owner_slot.dart';
import 'routed_video_playback.dart';

/// Owns a replaceable Player together with exactly one routed or legacy output.
///
/// Exceptions from [onChanged] are reported through [onError]. They do not
/// reject owner creation; the owner remains available for later disposal.
class ManagedVideoPlayback {
  ManagedVideoPlayback({
    required PlayerOwnerSlot slot,
    required Future<Player> Function() createPlayer,
    this.configuration = const VideoControllerConfiguration(),
    this.preparePlayer,
    this.onChanged,
    this.onError,
    this.onFallback,
  })  : _slot = slot,
        _createPlayer = createPlayer,
        _createRouted = null,
        _createLegacyController = null;

  @visibleForTesting
  ManagedVideoPlayback.forTesting({
    required PlayerOwnerSlot slot,
    required Future<Player> Function() createPlayer,
    this.configuration = const VideoControllerConfiguration(),
    this.preparePlayer,
    this.onChanged,
    this.onError,
    this.onFallback,
    required Future<RoutedVideoPlayback> Function(
            Player player, VideoControllerConfiguration configuration)
        createRouted,
    required Future<VideoController> Function(
            Player player, VideoControllerConfiguration configuration)
        createLegacyController,
  })  : _slot = slot,
        _createPlayer = createPlayer,
        _createRouted = createRouted,
        _createLegacyController = createLegacyController;

  final PlayerOwnerSlot _slot;
  final Future<Player> Function() _createPlayer;
  final VideoControllerConfiguration configuration;
  final FutureOr<void> Function(Player)? preparePlayer;
  final void Function()? onChanged;
  final void Function(Object)? onError;
  final void Function(Object)? onFallback;
  final Future<RoutedVideoPlayback> Function(
      Player, VideoControllerConfiguration)? _createRouted;
  final Future<VideoController> Function(Player, VideoControllerConfiguration)?
      _createLegacyController;

  // This immutable tuple is only replaced while holding the slot transition.
  _ManagedOwner? _owner;
  bool _closed = false;
  double? _rate;
  double? _volume;
  int _rateRevision = 0;
  int _volumeRevision = 0;

  Player? get player => _owner?.player;
  RoutedVideoPlayback? get routed => _owner?.routed;

  /// Pass-through of the current verified source description for callers
  /// holding this managed wrapper; see
  /// [RoutedVideoPlayback.verifiedSourceHint].
  HdrSourceDescriptor? get verifiedSourceHint =>
      _owner?.routed?.verifiedSourceHint;
  VideoController? get controller =>
      _owner?.routed?.controller.value ?? _owner?.legacyController;
  bool get hasOutput => _owner != null;

  Future<Player?> ensure({
    required Object request,
    required bool Function() isCurrent,
  }) async {
    _checkOpen();
    if (!isCurrent()) return null;
    return _slot.transition<Player?>((transition) async {
      if (_closed || !isCurrent()) return null;
      final current = _owner;
      if (current != null &&
          !(current.fallbackRequest != null &&
              !identical(current.fallbackRequest, request))) {
        return current.player;
      }
      if (current != null) {
        _publish(null);
        await _retire(transition, current);
      }
      if (_closed || !isCurrent()) return null;
      _ManagedOwner created;
      try {
        created =
            await _createRoutedOwner(transition, () => !_closed && isCurrent());
      } on RoutedOpenSuperseded {
        return null;
      }
      if (_closed || !isCurrent()) {
        await _retire(transition, created);
        return null;
      }
      try {
        while (true) {
          final applied =
              await _applyProperties(created.player, isCurrent: isCurrent);
          if (_closed || !isCurrent()) throw const RoutedOpenSuperseded();
          // A setter can run after the helper returns but before this await
          // resumes. Validate synchronously before publishing the owner.
          if (applied == (_rateRevision, _volumeRevision)) break;
        }
      } catch (error, stack) {
        try {
          await _retire(transition, created);
        } catch (_) {}
        if (error is RoutedOpenSuperseded) return null;
        Error.throwWithStackTrace(error, stack);
      }
      if (_closed || !isCurrent()) {
        await _retire(transition, created);
        return null;
      }
      _publish(created);
      return created.player;
    });
  }

  Future<void> open(
    Media media, {
    required Object request,
    required bool Function() isCurrent,
    bool play = true,
    bool video = true,
    bool allowLegacyFallback = false,
    bool preservePlaybackSettings = false,
    HdrSourceDescriptor? sourceHint,
  }) async {
    final previous = _owner;
    final snapshot = previous == null
        ? null
        : _PlaybackSettings(previous.player.state.rate,
            previous.player.state.volume, _rateRevision, _volumeRevision);
    final resolved = await ensure(request: request, isCurrent: isCurrent);
    if (resolved == null || _closed || !isCurrent()) return;
    final captured = _owner;
    if (captured == null || !identical(captured.player, resolved)) return;

    if (preservePlaybackSettings &&
        previous != null &&
        !identical(previous, captured)) {
      try {
        await _applyProperties(captured.player,
            snapshot: snapshot,
            isCurrent: () => isCurrent() && identical(_owner, captured));
      } on RoutedOpenSuperseded {
        return;
      }
    }

    // The helper's last check precedes its async return. Validate again before
    // starting transport, including changes delivered at that return boundary.
    if (_closed || !isCurrent() || !identical(_owner, captured)) return;

    if (identical(captured.fallbackRequest, request) &&
        captured.legacyController != null) {
      await captured.player.open(media, play: play);
      return;
    }
    final route = captured.routed;
    if (route == null) return;
    try {
      await route.open(media, play: play, video: video,
          sourceHint: sourceHint);
      if (!isCurrent() || !identical(_owner, captured)) return;
      _notifyChanged();
    } catch (error) {
      if (error is RoutedOpenSuperseded ||
          !allowLegacyFallback ||
          !video ||
          !isCurrent() ||
          !identical(_owner, captured)) {
        rethrow;
      }
      try {
        final legacyOwner = await _fallback(
          request: request,
          isCurrent: isCurrent,
          captured: captured,
          snapshot: snapshot,
        );
        if (_closed ||
            !isCurrent() ||
            !identical(_owner, legacyOwner) ||
            !identical(legacyOwner.fallbackRequest, request)) {
          throw const RoutedOpenSuperseded();
        }
        await legacyOwner.player.open(media, play: play);
        if (!isCurrent() || !identical(_owner, legacyOwner)) {
          throw const RoutedOpenSuperseded();
        }
        try {
          onFallback?.call(error);
        } catch (observerError) {
          _reportError(observerError);
        }
      } catch (fallbackError) {
        if (fallbackError is! RoutedOpenSuperseded) {
          _reportError(fallbackError);
        }
        rethrow;
      }
    }
  }

  Future<void> setRate(double rate) async {
    _checkOpen();
    _rate = rate;
    _rateRevision++;
    final active = _owner?.player;
    if (active != null) await active.setRate(rate);
  }

  Future<void> setVolume(double volume) async {
    _checkOpen();
    _volume = volume;
    _volumeRevision++;
    final active = _owner?.player;
    if (active != null) await active.setVolume(volume);
  }

  Future<void> dispose() {
    if (_closed) return _slot.transition<void>((_) async {});
    _closed = true;
    final old = _owner;
    _owner = null;
    // Queue the owner itself before notifying observers. The slot retains this
    // debt even if earlier cleanup fails and this manager is never called again.
    final closing = old == null
        ? _slot.transition<void>((_) async {})
        : _slot.retire(old, () => _disposeOwner(old));
    _notifyChanged();
    return closing;
  }

  Future<_ManagedOwner> _createRoutedOwner(
      PlayerOwnerTransition transition, bool Function() isCurrent) async {
    final player = await _createPlayer();
    RoutedVideoPlayback? routed;
    StreamSubscription<Object>? errors;
    VoidCallback? changed;
    try {
      if (!isCurrent()) throw const RoutedOpenSuperseded();
      await preparePlayer?.call(player);
      if (!isCurrent()) throw const RoutedOpenSuperseded();
      routed = await (_createRouted?.call(player, configuration) ??
          RoutedVideoPlayback.create(player, configuration: configuration));
      late final _ManagedOwner owner;
      void listener() {
        if (!_closed && identical(_owner?.routed, routed)) _notifyChanged();
      }

      changed = listener;
      errors = routed.errors.listen((error) {
        if (!_closed && identical(_owner?.routed, routed)) _reportError(error);
      });
      routed.controller.addListener(listener);
      owner = _ManagedOwner(
        player: player,
        routed: routed,
        errorSubscription: errors,
        controllerListener: listener,
      );
      return owner;
    } catch (error, stack) {
      final partial = _ManagedOwner(
        player: player,
        routed: routed,
        errorSubscription: errors,
        controllerListener: changed,
      );
      try {
        await _retire(transition, partial);
      } catch (_) {}
      Error.throwWithStackTrace(error, stack);
    }
  }

  Future<_ManagedOwner> _fallback({
    required Object request,
    required bool Function() isCurrent,
    required _ManagedOwner captured,
    required _PlaybackSettings? snapshot,
  }) async {
    return _slot.transition<_ManagedOwner>((transition) async {
      if (_closed || !isCurrent() || !identical(_owner, captured)) {
        throw const RoutedOpenSuperseded();
      }
      _publish(null);
      await _retire(transition, captured);
      if (_closed || !isCurrent()) throw const RoutedOpenSuperseded();

      final player = await _createPlayer();
      VideoController? legacy;
      try {
        if (_closed || !isCurrent()) throw const RoutedOpenSuperseded();
        await preparePlayer?.call(player);
        if (_closed || !isCurrent()) throw const RoutedOpenSuperseded();
        legacy = await (_createLegacyController?.call(player, configuration) ??
            VideoController.create(player, configuration: configuration));
        if (_closed || !isCurrent()) throw const RoutedOpenSuperseded();
        while (true) {
          final applied = await _applyProperties(player,
              snapshot: snapshot, isCurrent: isCurrent);
          if (_closed || !isCurrent()) throw const RoutedOpenSuperseded();
          // Validate after the helper's async return, immediately before publish.
          if (applied == (_rateRevision, _volumeRevision)) break;
        }
        final owner = _ManagedOwner(
          player: player,
          legacyController: legacy,
          fallbackRequest: request,
        );
        _publish(owner);
        return owner;
      } catch (error, stack) {
        final partial = _ManagedOwner(player: player, legacyController: legacy);
        try {
          await _retire(transition, partial);
        } catch (_) {}
        Error.throwWithStackTrace(error, stack);
      }
    });
  }

  Future<(int, int)> _applyProperties(
    Player player, {
    required bool Function() isCurrent,
    _PlaybackSettings? snapshot,
  }) async {
    void checkCurrent() {
      if (_closed || !isCurrent()) throw const RoutedOpenSuperseded();
    }

    var appliedRateRevision = -1;
    var appliedVolumeRevision = -1;
    do {
      checkCurrent();
      final rateRevision = _rateRevision;
      final volumeRevision = _volumeRevision;
      final rate = snapshot != null && snapshot.rateRevision == rateRevision
          ? snapshot.rate
          : _rate;
      final volume =
          snapshot != null && snapshot.volumeRevision == volumeRevision
              ? snapshot.volume
              : _volume;
      if (appliedRateRevision != rateRevision) {
        if (rate != null) await player.setRate(rate);
        checkCurrent();
        appliedRateRevision = rateRevision;
      }
      if (appliedVolumeRevision != volumeRevision) {
        if (volume != null) await player.setVolume(volume);
        checkCurrent();
        appliedVolumeRevision = volumeRevision;
      }
    } while (appliedRateRevision != _rateRevision ||
        appliedVolumeRevision != _volumeRevision);
    return (appliedRateRevision, appliedVolumeRevision);
  }

  Future<void> _retire(
      PlayerOwnerTransition transition, _ManagedOwner owner) async {
    await transition.retire(owner, () => _disposeOwner(owner));
  }

  Future<void> _disposeOwner(_ManagedOwner owner) async {
    if (!owner.cleanup.listenersDetached) {
      owner.cleanup.listenersDetached = true;
      try {
        if (owner.controllerListener case final listener?) {
          owner.routed?.controller.removeListener(listener);
        }
      } catch (error) {
        _reportError(error);
      }
      try {
        await owner.errorSubscription?.cancel();
      } catch (error) {
        _reportError(error);
      }
    }
    if (owner.routed != null) {
      if (!owner.cleanup.routedDisposed) {
        await owner.routed!.dispose();
        owner.cleanup.routedDisposed = true;
        owner.cleanup.playerDisposed = true;
      }
      return;
    }
    if (owner.legacyController != null &&
        !owner.cleanup.legacyControllerDisposed) {
      await owner.legacyController!.disposeForRebuild();
      owner.cleanup.legacyControllerDisposed = true;
    }
    if (!owner.cleanup.playerDisposed) {
      await owner.player.dispose();
      owner.cleanup.playerDisposed = true;
    }
  }

  void _publish(_ManagedOwner? owner) {
    _owner = owner;
    _notifyChanged();
  }

  void _notifyChanged() {
    try {
      onChanged?.call();
    } catch (error) {
      _reportError(error);
    }
  }

  void _reportError(Object error) {
    try {
      onError?.call(error);
    } catch (_) {}
  }

  void _checkOpen() {
    if (_closed) throw StateError('ManagedVideoPlayback is closed');
  }
}

class _ManagedOwner {
  _ManagedOwner({
    required this.player,
    this.routed,
    this.legacyController,
    this.fallbackRequest,
    this.errorSubscription,
    this.controllerListener,
    _OwnerCleanup? cleanup,
  }) : cleanup = cleanup ?? _OwnerCleanup();

  final Player player;
  final RoutedVideoPlayback? routed;
  final VideoController? legacyController;
  final Object? fallbackRequest;
  final StreamSubscription<Object>? errorSubscription;
  final VoidCallback? controllerListener;
  final _OwnerCleanup cleanup;
}

class _PlaybackSettings {
  const _PlaybackSettings(
      this.rate, this.volume, this.rateRevision, this.volumeRevision);
  final double rate;
  final double volume;
  final int rateRevision;
  final int volumeRevision;
}

class _OwnerCleanup {
  bool listenersDetached = false;
  bool legacyControllerDisposed = false;
  bool routedDisposed = false;
  bool playerDisposed = false;
}
