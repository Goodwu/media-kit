import 'dart:io';

void _require(bool condition, String message) {
  if (!condition) {
    throw StateError(message);
  }
}

String _read(String path) => File(path).readAsStringSync();

class _HdrLifecycleProbe {
  String? appliedMode;
  bool voRunning = true;
  final operations = <String>[];

  void sdrSuccess() {
    operations.add('stop');
    operations.add('sdr-reset');
    operations.add('start');
    appliedMode = 'sdr';
    voRunning = true;
  }

  void hdrConfigurationFails() {
    appliedMode = null;
    operations.add('stop');
    operations.add('hdr-configure-failed');
    // The controller performs a best-effort immediate SDR recovery, but does
    // not cache it as an idempotent result. A later reset must still rebuild.
    appliedMode = null;
    operations.add('sdr-recovery');
    operations.add('start');
    voRunning = true;
  }

  void resetSdr() {
    if (appliedMode == 'sdr') {
      operations.add('stale-cache-hit');
      return;
    }
    operations.add('stop');
    operations.add('sdr-reset');
    operations.add('start');
    appliedMode = 'sdr';
    voRunning = true;
  }
}

void main() {
  final controller =
      _read('lib/src/video_controller/ohos_video_controller/real.dart');
  final player = _read('../media_kit/lib/src/player/native/player/real.dart');
  final platformPlayer =
      _read('../media_kit/lib/src/player/platform_player.dart');
  final hdrOutput =
      _read('../libs/ohos/media_kit_libs_ohos/ohos/src/main/cpp/hdr_output.cc');
  final surface = _read(
      'ohos/src/main/ets/com/alexmercerind/media_kit_video/OhosNativeSurface.ets');
  final output = _read(
      'ohos/src/main/ets/com/alexmercerind/media_kit_video/VideoOutput.ets');
  final videoTexture = _read('lib/src/video/video_texture.dart');
  final platformView = _read('lib/src/video/platform_view_video_ohos.dart');

  _require(surface.contains('readonly generation: number;'),
      'surface creation must retain a fixed generation');
  _require(
      surface.contains('generation: this.generation') &&
          surface.contains('surfaceId: this.surfaceId'),
      'ready/destroy events must carry the complete surface identity');

  _require(
      videoTexture.contains('bool _ohosNativeSurfaceMounted = false;') &&
          videoTexture.contains('keepMountedNativeSurface') &&
          platformView.contains('key: ValueKey<int>(generation)'),
      'OHOS native candidate must survive transient decoder visibility loss and '
      'recreate only on an explicit surface generation change');

  final ready = controller.indexOf("call.method == 'nativeSurfaceReady'");
  final readyValidation =
      controller.indexOf('generation != target.nativeSurfaceGeneration', ready);
  final readySuspend =
      controller.indexOf('_suspendTextureOutputLocked()', ready);
  final readyAttach =
      controller.indexOf('_attachNativeSurfaceLocked(surfaceId)', ready);
  _require(
      ready >= 0 &&
          readyValidation > ready &&
          readyValidation < readySuspend &&
          readySuspend < readyAttach,
      'ready must validate identity before suspend and attach');

  final destroyed =
      controller.indexOf("call.method == 'nativeSurfaceDestroyed'");
  final destroyStop =
      controller.indexOf('_stopVideoOutputForReconfigure()', destroyed);
  final destroyReset = controller.indexOf('_resetHdr(surfaceId)', destroyed);
  final destroyRevision = controller.indexOf('_hdrConfigRevision++', destroyed);
  final destroyResume = controller.indexOf('_resumeTextureOutput()', destroyed);
  _require(
      destroyed >= 0 &&
          destroyStop > destroyed &&
          destroyReset > destroyStop &&
          destroyRevision > destroyReset &&
          destroyResume == -1,
      'native surface destroy must not switch to a Texture/SDR fallback before the replacement surface is ready');

  final reset =
      controller.indexOf('Future<HdrOutputReport> resetHdrOutput()');
  final noSurface = controller.indexOf(
      'id == null || id == 0 || !nativeSurfaceActive', reset);
  final sdrWrite = controller.indexOf('_applySdrMpvProperties()', noSurface);
  final sdrIdempotence = controller.indexOf(
      '_hasAppliedHdrMode(id, generation, _OhosHdrOutputMode.sdr)', reset);
  final resetStop =
      controller.indexOf('_stopVideoOutputForReconfigure()', reset);
  _require(
      reset >= 0 &&
          noSurface > reset &&
          sdrWrite > noSurface &&
          sdrIdempotence > reset &&
          resetStop > sdrIdempotence,
      'reset must apply SDR without a surface and stop before a fresh restart');

  final configure = controller.indexOf('_configureHdrOutputLocked(');
  final staticInit =
      controller.indexOf('_configureHdr(id, transfer)', configure);
  final restartVo =
      controller.indexOf("setProperty('vo', 'gpu-next')", staticInit);
  final configureStop =
      controller.indexOf('_stopVideoOutputForReconfigure();', configure);
  _require(
      configure >= 0 &&
          configureStop > configure &&
          staticInit > configureStop &&
          restartVo > staticInit,
      'HDR static format/gamut init must be bracketed by VO stop and restart');

  final stopHelper =
      controller.indexOf('Future<void> _stopVideoOutputForReconfigure()');
  final invalidateBeforeVo =
      controller.indexOf('_clearAppliedHdrMode();', stopHelper);
  final helperVoNull =
      controller.indexOf("setProperty('vo', 'null')", stopHelper);
  _require(
      stopHelper >= 0 &&
          invalidateBeforeVo > stopHelper &&
          helperVoNull > invalidateBeforeVo,
      'applied output cache must be invalidated before destroying the VO');

  final configureFailure =
      controller.indexOf("'failureReason': 'native-window-configure-");
  final recovery =
      controller.indexOf('_recoverSdrAfterHdrFailure(id)', configure);
  _require(
      configureFailure > configure &&
          recovery > configure &&
          controller.indexOf('_pendingHdrConfiguration = null;', recovery) >
              recovery &&
          controller.indexOf("setProperty('vo', 'gpu-next')", recovery) >
              recovery,
      'HDR configure failure must clear pending state and explicitly recover SDR');

  final pendingClass = controller.indexOf('class _PendingHdrConfiguration');
  final revisionField = controller.indexOf('final int revision;', pendingClass);
  final readyReplay =
      controller.indexOf('_replayPendingHdrConfiguration(pending!)');
  final resetRevision = controller.indexOf('_hdrConfigRevision++', reset);
  _require(
      pendingClass >= 0 &&
          revisionField > pendingClass &&
          readyReplay > revisionField &&
          resetRevision > reset &&
          controller.contains("'failureReason': 'stale-hdr-config-revision'"),
      'pending HDR replay must be revision-bound and reset-invalidated');

  final dispose = controller
      .indexOf('Future<void> _disposeOnce({required bool playerReleasing})');
  final stopProducer =
      controller.indexOf('_setPropertyForRelease(\'vo\', \'null\')', dispose);
  final releaseConsumer =
      controller.indexOf('VideoOutputManager.Dispose', dispose);
  _require(dispose >= 0 && stopProducer >= 0 && stopProducer < releaseConsumer,
      'dispose must stop mpv before releasing the Flutter texture');

  final playerDispose = player.indexOf('Future<void> dispose');
  final disposedBeforeRelease =
      player.indexOf('disposed = true', playerDispose);
  final superDispose = player.indexOf('await super.dispose()', playerDispose);
  _require(
      player.contains('Future<void> setPropertyForRelease') &&
          player.contains('!disposed || !releaseCallbacksActive') &&
          disposedBeforeRelease > playerDispose &&
          superDispose > disposedBeforeRelease &&
          player.indexOf('_throwIfMpvError(result',
                  player.indexOf('Future<void> _setPropertyStringDirect')) >=
              0,
      'disposed player must retain a checked release setter');

  _require(
      hdrOutput.contains('SET_SOURCE_TYPE') &&
          hdrOutput.contains('SET_FORMAT') &&
          hdrOutput.contains('SET_COLOR_GAMUT') &&
          !hdrOutput.contains('SET_HDR_WHITE_POINT_BRIGHTNESS') &&
          !hdrOutput.contains('SET_SDR_WHITE_POINT_BRIGHTNESS') &&
          !hdrOutput.contains('hdr_white_point') &&
          !hdrOutput.contains('sdr_white_point'),
      'FFI must configure only static source, format, and gamut state');

  _require(
      platformPlayer.contains('_releaseCallbacksActive = true;') &&
          platformPlayer.contains('_releaseCallbacksActive = false;') &&
          platformPlayer.contains('Object? releaseError;') &&
          platformPlayer.contains('releaseError ??= exception;') &&
          platformPlayer.contains('Error.throwWithStackTrace(releaseError,') &&
          controller.contains(
              'if (playerReleasing || platform.isReleaseCallbacksActive)') &&
          controller.contains('await setProperty(\'vo\', \'null\');'),
      'release failures must remain observable and concurrent disposal must use '
      'the release-safe property path');

  final lifecycle = _HdrLifecycleProbe()..sdrSuccess();
  lifecycle.hdrConfigurationFails();
  lifecycle.resetSdr();
  _require(
      lifecycle.operations.join(',') ==
              'stop,sdr-reset,start,stop,hdr-configure-failed,sdr-recovery,start,stop,sdr-reset,start' &&
          !lifecycle.operations.contains('stale-cache-hit') &&
          lifecycle.appliedMode == 'sdr' &&
          lifecycle.voRunning,
      'SDR success -> HDR failure -> SDR recovery must rebuild the VO');

  final outputDispose = output.indexOf('dispose(): void');
  final outputSuspend = output.indexOf('suspendTexture(): void', outputDispose);
  final disposeBody = output.substring(outputDispose, outputSuspend);
  _require(!disposeBody.contains('catch'),
      'texture disposal errors must reach the native bridge caller');
}
