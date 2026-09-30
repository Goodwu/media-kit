import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'android_hdr_open_coordinator.dart';
import 'android_hdr_output_slot.dart';
import 'android_hdr_playback_policy.dart';
import 'android_hdr_sample_identity.dart';

/// Adapter for the fixed Android HDR experiment. Output capability and actual
/// presentation must still be checked separately on the device.
class AndroidHdrPlayerBackend implements AndroidHdrOpenBackend {
  AndroidHdrPlayerBackend({
    required this.player,
    required this.outputSlot,
    required this.usePlatformView,
    required this.p5RpuPipelineBuilt,
    required this.readDisplayHdrTypes,
    required this.applySurfaceTransfer,
    this.forceP84PqFallback = false,
    this.gpuPlatformHdrExperiment = false,
    this.p5PlatformSdrDiagnostic = false,
    this.textureCopyDiagnostic = false,
  });

  final Player player;
  final AndroidHdrOutputSlot<VideoController> outputSlot;
  final bool usePlatformView;
  final bool p5RpuPipelineBuilt;
  final Future<Set<int>> Function() readDisplayHdrTypes;
  final Future<bool> Function(String transfer) applySurfaceTransfer;
  final bool forceP84PqFallback;
  final bool gpuPlatformHdrExperiment;
  final bool p5PlatformSdrDiagnostic;
  final bool textureCopyDiagnostic;
  AndroidHdrPlaybackPolicy? _validatedPolicy;

  final Map<String, String> _originalProperties = {};
  final Set<String> _ownedProperties = {};
  bool _p84FilterApplied = false;
  bool _observedStoppedPath = false;
  int? _openFileLoadedEpoch;
  int? _openPlaylistEntryId;

  Future<void> _setOwned(String name, String value) async {
    if (!_originalProperties.containsKey(name)) {
      final original = await player.getProperty(name);
      if (original.isEmpty) {
        throw StateError('Cannot capture original value of $name');
      }
      _originalProperties[name] = original;
    }
    _ownedProperties.add(name);
    await player.setPropertyStrict(name, value);
    final actual = await player.getProperty(name);
    if (actual != value) {
      throw StateError('$name rejected: requested=$value actual=$actual');
    }
  }

  @override
  Future<void> stop() async {
    await player.stop();
    final path = await player.getProperty('path');
    if (path.isNotEmpty) {
      throw StateError('Stop did not clear old media path: $path');
    }
    _observedStoppedPath = true;
  }

  @override
  Future<void> resetOwnedConfiguration() async {
    if (_p84FilterApplied) {
      await player.command(['vf', 'remove', '@media-kit-p84-base']);
      _p84FilterApplied = false;
    }
    for (final name in _ownedProperties.toList().reversed) {
      final original = _originalProperties[name];
      if (original == null || original.isEmpty) {
        throw StateError('No original value for $name');
      }
      await player.setPropertyStrict(name, original);
      _ownedProperties.remove(name);
    }
  }

  @override
  Future<void> validate(AndroidHdrSampleIdentity identity) async {
    final hdrTypes = usePlatformView ? await readDisplayHdrTypes() : null;
    _validatedPolicy = AndroidHdrPlaybackPolicy.forSample(
      identity.sample,
      usePlatformView: usePlatformView,
      p5RpuPipelineBuilt: p5RpuPipelineBuilt,
      displayHdrTypes: hdrTypes,
      forceP84PqFallback: forceP84PqFallback,
      gpuPlatformHdrExperiment: gpuPlatformHdrExperiment,
      p5PlatformSdrDiagnostic: p5PlatformSdrDiagnostic,
      textureCopyDiagnostic: textureCopyDiagnostic,
    );
  }

  @override
  Future<void> prepareOutput(AndroidHdrSampleIdentity identity) async {
    final policy = _validatedPolicy;
    if (policy == null) throw StateError('Output policy was not validated');
    final gpuPlatform = usePlatformView &&
        policy.vo == 'gpu-next' &&
        !(identity.sample == AndroidHdrSample.dolbyVisionP5 &&
            p5PlatformSdrDiagnostic);
    if (gpuPlatform) {
      await _setOwned('egl-output-format', 'rgb10_a2');
    }
    await outputSlot.ensure(
      policy.vo,
      policy.hwdec,
      outputFormat: gpuPlatform ? 'rgb10_a2' : null,
      surfaceTransfer: policy.surfaceTransfer,
    );
    if (!usePlatformView && policy.vo == 'gpu-next') {
      final prepared = await outputSlot.current!.prepareAndroidTextureOutput();
      debugPrint(prepared
          ? 'ANDROID_TEXTURE_PREPARED layoutBound=true'
          : 'ANDROID_TEXTURE_PREPARED fallback=surface_or_layout_unavailable');
    }
  }

  @override
  Future<void> configure(AndroidHdrSampleIdentity identity) async {
    final policy = _validatedPolicy;
    if (policy == null) throw StateError('Output policy was not validated');
    if (usePlatformView) {
      final output = await outputSlot.current!.platform.future;
      await output.waitUntilCurrentOutputBound
          .timeout(const Duration(seconds: 10));
      final transfer = policy.surfaceTransfer;
      if (transfer != null && !await applySurfaceTransfer(transfer)) {
        throw StateError('$transfer Surface dataspace was not applied');
      }
    }
    await _setOwned('cache-on-disk', 'no');
    await _setOwned('hwdec', policy.hwdec);
    if (identity.sample == AndroidHdrSample.dolbyVisionP5 &&
        policy.vo == 'gpu-next') {
      // Player initialization disables these globally. Restore gpu-next's
      // defaults only for this P5 transaction, then restore the captured values.
      await _setOwned('hdr-compute-peak', 'auto');
      await _setOwned('dither', 'fruit');
    }

    if (policy.stripP84Rpu) {
      await player
          .command(['vf', 'add', '@media-kit-p84-base:format=dolbyvision=no']);
      _p84FilterApplied = true;
      final actual = await player.getProperty('vf');
      if (!actual.contains('@media-kit-p84-base:format=dolbyvision=no')) {
        throw StateError('P8.4 base-layer filter was not accepted');
      }
    }

    if (!usePlatformView) {
      await _setOwned('target-prim', policy.targetPrim!);
      await _setOwned('target-trc', policy.targetTrc!);
      await _setOwned('target-colorspace-hint', 'auto');
      await _setOwned('tone-mapping', 'bt.2390');
    } else if (policy.vo == 'gpu-next') {
      await _setOwned('target-prim', policy.targetPrim!);
      await _setOwned('target-trc', policy.targetTrc!);
      await _setOwned('target-colorspace-hint', 'auto');
      if (identity.sample == AndroidHdrSample.dolbyVisionP5 &&
          p5PlatformSdrDiagnostic) {
        await _setOwned('tone-mapping', 'bt.2390');
      }
    }
  }

  @override
  Future<void> waitForOutput(AndroidHdrSampleIdentity identity) async {
    final output = await outputSlot.current!.platform.future;
    await output.waitUntilCurrentOutputBound;
  }

  @override
  Future<void> open(
    AndroidHdrSampleIdentity identity, {
    Duration? start,
    required bool play,
  }) async {
    if (!_observedStoppedPath) {
      throw StateError('No stopped-media path boundary before open');
    }
    _observedStoppedPath = false;
    _openFileLoadedEpoch = player.fileLoadedEpoch;
    _openPlaylistEntryId = null;
    await player.open(Media(identity.path, start: start), play: play);
    final playlistPath = await player.getProperty('playlist/0/filename');
    final entryId = int.tryParse(await player.getProperty('playlist/0/id'));
    if (playlistPath != identity.path || entryId == null) {
      throw StateError('Opened playlist entry differs from staged source: '
          'path=$playlistPath id=$entryId');
    }
    _openPlaylistEntryId = entryId;
  }

  @override
  Future<void> verifyTrack(AndroidHdrSampleIdentity identity) async {
    final before = _openFileLoadedEpoch;
    final entryId = _openPlaylistEntryId;
    if (before == null || entryId == null) {
      throw StateError('No playlist-entry identity before track verification');
    }
    final loaded = await player
        .waitForFileLoadedEntryAfter(entryId, before)
        .timeout(const Duration(seconds: 8));
    if (loaded.epoch <= before || loaded.playlistEntryId != entryId) {
      throw StateError('No matching native file-loaded event for this open');
    }
    final deadline = DateTime.now().add(const Duration(seconds: 8));
    var currentPath = '';
    var videoFormat = '';
    while (DateTime.now().isBefore(deadline)) {
      currentPath = await player.getProperty('path');
      videoFormat = await player.getProperty('video-format');
      if (currentPath == identity.path && videoFormat.isNotEmpty) break;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    if (currentPath != identity.path || videoFormat.isEmpty) {
      throw StateError(
          'New media track not observed: path=$currentPath format=$videoFormat');
    }
    final profile =
        await player.getProperty('current-tracks/video/dolby-vision-profile');
    final expectedProfile = switch (identity.sample) {
      AndroidHdrSample.hdr10 => '',
      AndroidHdrSample.hlgBaseControl => '',
      AndroidHdrSample.dolbyVisionP84 => '8',
      AndroidHdrSample.dolbyVisionP5 => '5',
    };
    if (profile != expectedProfile) {
      throw StateError(
          'Video profile mismatch: expected=$expectedProfile actual=$profile');
    }
    // FILE_LOADED and video-format can precede decoder initialization on a
    // newly bound gpu-next output. Keep the same media identity while waiting
    // for the decoder instead of treating the initial empty property as a
    // software-decoding verdict.
    var hwdec = '';
    final expectedHwdec = _validatedPolicy?.hwdec;
    if (expectedHwdec == null) {
      throw StateError('No validated decoder policy for track verification');
    }
    while (DateTime.now().isBefore(deadline)) {
      if (await player.getProperty('path') != identity.path) {
        throw StateError('Media changed before decoder verification');
      }
      hwdec = await player.getProperty('hwdec-current');
      if (hwdec == expectedHwdec) return;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    throw StateError('Expected $expectedHwdec output, got $hwdec');
  }
}
