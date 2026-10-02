/// This file is a part of media_kit (https://github.com/media-kit/media-kit).
///
/// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
/// All rights reserved.
/// Use of this source code is governed by MIT license that can be found in the LICENSE file.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:media_kit_video/src/video_controller/android_video_controller/android_video_controller.dart';

import 'hdr_open_coordinator.dart';

/// Android execution backend for `HdrVideoSession` (ported from hdr_lab's
/// `AndroidHdrPlayerBackend` with the sample identity removed): writes mpv
/// properties and confirms them by readback, restores the captured values on
/// session end or source switch, attaches the RPU-stripping filter per
/// route, applies the P5 transactional defaults, verifies `hwdec-current`,
/// and applies the GPU surface dataspace through
/// `AndroidVideoController.invokeApplyDataSpace`.
///
/// Output capability and actual presentation must still be checked
/// separately on the device.
class AndroidHdrBackend implements HdrOpenBackend<HdrOpenPlan> {
  AndroidHdrBackend({
    required this.player,
    required this.outputSlot,
    Future<Map<String, Object?>?> Function(int handle, String transfer)?
        applyDataSpace,
  }) : _applyDataSpace = applyDataSpace ??
            ((int handle, String transfer) =>
                AndroidVideoController.invokeApplyDataSpace(
                  handle: handle,
                  transfer: transfer,
                )) {
    _videoParamsSubscription = player.stream.videoParams.listen((params) {
      if (params.gamma != null || params.primaries != null) {
        _latestVideoParams = params;
      }
    });
  }

  final Player player;
  final HdrOutputSlot<VideoController> outputSlot;

  final Future<Map<String, Object?>?> Function(int handle, String transfer)
      _applyDataSpace;
  StreamSubscription<VideoParams>? _videoParamsSubscription;
  VideoParams? _latestVideoParams;

  bool _rpuFilterApplied = false;
  bool _observedStoppedPath = false;
  int? _openFileLoadedEpoch;
  int? _openPlaylistEntryId;
  String? _dataSpaceRequested;
  String? _dataSpacePath;
  String? _dataSpaceReadback;
  String? _lastHwdecCurrent;

  /// The RPU-stripping filter label; hdr_lab used the sample-specific name
  /// `@media-kit-p84-base`.
  static const String _dvRpuFilter = '@media-kit-dv-base';

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

  final Map<String, String> _originalProperties = {};
  final Set<String> _ownedProperties = {};

  @override
  Future<void> validate(HdrOpenPlan plan) async {
    // The planner already gated feasibility; the backend only executes.
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
    if (_rpuFilterApplied) {
      await player.command(['vf', 'remove', _dvRpuFilter]);
      _rpuFilterApplied = false;
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
  Future<void> prepareOutput(HdrOpenPlan plan) async {
    final route = plan.route;
    final gpuPlatform =
        route.topology == HdrTopology.platformView && route.vo == 'gpu-next';
    if (gpuPlatform) {
      await _setOwned('egl-output-format', 'rgb10_a2');
    }
    await outputSlot.ensure(
      route.vo,
      route.hwdec,
      outputFormat: gpuPlatform ? 'rgb10_a2' : null,
      surfaceTransfer: route.surfaceTransfer,
    );
    if (route.topology != HdrTopology.platformView && route.vo == 'gpu-next') {
      final prepared = await outputSlot.current!.prepareAndroidTextureOutput();
      debugPrint(prepared
          ? 'HDR_TEXTURE_PREPARED layoutBound=true'
          : 'HDR_TEXTURE_PREPARED fallback=surface_or_layout_unavailable');
    }
  }

  @override
  Future<void> configure(HdrOpenPlan plan) async {
    final route = plan.route;
    if (route.topology == HdrTopology.platformView) {
      final output = await outputSlot.current!.platform.future;
      await output.waitUntilCurrentOutputBound
          .timeout(const Duration(seconds: 10));
      final transfer = route.surfaceTransfer;
      if (transfer != null) {
        final handle = await player.handle;
        final result = await _applyDataSpace(handle, transfer);
        _dataSpaceRequested = transfer;
        _dataSpacePath = result?['path']?.toString();
        _dataSpaceReadback = result?['readback']?.toString();
        // `HDR readback:` layer (R4.3), emitted before the failure gates so
        // a failing application is logged too.
        HdrOutputDiagnostics.readback(
          requested: transfer,
          path: _dataSpacePath,
          applied: result?['applied'] == true,
          readback: _dataSpaceReadback,
        );
        // The applied flag is the gate (S4 reviewer note): on the
        // `surfaceControl` path applied and readback measure different
        // layers, so a readback mismatch there is diagnostic only.
        if (result?['applied'] != true) {
          throw HdrDataSpaceApplyException(
            transfer,
            path: _dataSpacePath,
            readback: _dataSpaceReadback,
            reason: HdrDegradeReason.dataSpaceApplyFailed,
          );
        }
        if (_dataSpacePath != 'surfaceControl' &&
            !_readbackMatches(transfer, _dataSpaceReadback)) {
          throw HdrDataSpaceApplyException(
            transfer,
            path: _dataSpacePath,
            readback: _dataSpaceReadback,
            reason: HdrDegradeReason.dataSpaceReadbackMismatch,
          );
        }
      }
    }
    await _setOwned('cache-on-disk', 'no');
    await _setOwned('hwdec', route.hwdec);
    if (plan.source.dvProfile == 5 && route.vo == 'gpu-next') {
      // Player initialization disables these globally. Restore gpu-next's
      // defaults only for this P5 transaction, then restore the captured
      // values.
      await _setOwned('hdr-compute-peak', 'auto');
      await _setOwned('dither', 'fruit');
    }

    if (route.stripDvRpu) {
      await player
          .command(['vf', 'add', '$_dvRpuFilter:format=dolbyvision=no']);
      _rpuFilterApplied = true;
      final actual = await player.getProperty('vf');
      if (!actual.contains('$_dvRpuFilter:format=dolbyvision=no')) {
        throw StateError('DV base-layer filter was not accepted');
      }
    }

    if (route.topology != HdrTopology.platformView) {
      if (route.targetPrim != null) {
        await _setOwned('target-prim', route.targetPrim!);
      }
      if (route.targetTrc != null) {
        await _setOwned('target-trc', route.targetTrc!);
      }
      await _setOwned('target-colorspace-hint', 'auto');
      await _setOwned('tone-mapping', 'bt.2390');
    } else if (route.vo == 'gpu-next') {
      if (route.targetPrim != null) {
        await _setOwned('target-prim', route.targetPrim!);
      }
      if (route.targetTrc != null) {
        await _setOwned('target-trc', route.targetTrc!);
      }
      await _setOwned('target-colorspace-hint', 'auto');
    }
  }

  /// The readback is expected to carry the requested transfer on the
  /// ANativeWindow paths (`ndk`/`ext:<id>`); constant names differ per
  /// platform, so match on the transfer keyword.
  static bool _readbackMatches(String transfer, String? readback) {
    if (readback == null || readback.isEmpty || readback == 'none') {
      return false;
    }
    final upper = readback.toUpperCase();
    return transfer == 'pq'
        ? upper.contains('PQ')
        : transfer == 'hlg'
            ? upper.contains('HLG')
            : true;
  }

  @override
  Future<void> waitForOutput(HdrOpenPlan plan) async {
    final output = await outputSlot.current!.platform.future;
    await output.waitUntilCurrentOutputBound;
  }

  @override
  Future<void> open(
    HdrOpenPlan plan, {
    Duration? start,
    required bool play,
  }) async {
    if (!_observedStoppedPath) {
      throw StateError('No stopped-media path boundary before open');
    }
    _observedStoppedPath = false;
    final media = plan.media;
    // Drop the previous media's cached video-params so the review waits for
    // this open's report instead of classifying from a stale source.
    _latestVideoParams = null;
    _openFileLoadedEpoch = player.fileLoadedEpoch;
    _openPlaylistEntryId = null;
    await player.open(
      start == null && media.start == null
          ? media
          : Media(
              media.uri,
              start: start ?? media.start,
              end: media.end,
              extras: media.extras,
              httpHeaders: media.httpHeaders,
            ),
      play: play,
    );
    final playlistPath = await player.getProperty('playlist/0/filename');
    final entryId = int.tryParse(await player.getProperty('playlist/0/id'));
    if (playlistPath != media.uri || entryId == null) {
      throw StateError(
          'Opened playlist entry differs from requested source: '
          'path=$playlistPath id=$entryId');
    }
    _openPlaylistEntryId = entryId;
  }

  @override
  Future<HdrReviewFacts> reviewFacts(HdrOpenPlan plan) async {
    final before = _openFileLoadedEpoch;
    final entryId = _openPlaylistEntryId;
    if (before == null || entryId == null) {
      throw StateError('No playlist-entry identity before review');
    }
    return gatherReviewFacts(
      mediaUri: plan.media.uri,
      expectedHwdec: plan.route.hwdec,
      readProperty: player.getProperty,
      latestVideoParams: () => _latestVideoParams,
      waitForFileLoadedEntry: player.waitForFileLoadedEntryAfter,
      playlistEntryId: entryId,
      fileLoadedEpoch: before,
    ).then((facts) {
      _lastHwdecCurrent = facts.hwdecCurrent;
      return facts;
    });
  }

  /// Gathers the decoder facts after the open's file-loaded boundary (plan
  /// 1.4 step 8). Static with injected readers so VM tests can drive the
  /// polling without a native Player; [reviewFacts] delegates to it.
  ///
  /// Both review inputs are awaited: `dolby-vision-profile` is read after
  /// the decoder reports, and video-params are polled until they carry the
  /// base-layer tags (gamma/primaries) — a review executed while
  /// video-params are still unreported would classify from the profile
  /// alone and mis-route (A1-P8.4 round, 2026-10-02). On timeout the facts
  /// are returned as observed (`videoParams == null`), and the session's
  /// conservative review applies.
  @visibleForTesting
  static Future<HdrReviewFacts> gatherReviewFacts({
    required String mediaUri,
    required String expectedHwdec,
    required HdrPropertyReader readProperty,
    required VideoParams? Function() latestVideoParams,
    required Future<FileLoadedRecord> Function(int playlistEntryId, int epoch)
        waitForFileLoadedEntry,
    required int playlistEntryId,
    required int fileLoadedEpoch,
    Duration reviewBudget = const Duration(seconds: 8),
    Future<void> Function(Duration duration) delay = Future<void>.delayed,
  }) async {
    final loaded = await waitForFileLoadedEntry(playlistEntryId,
            fileLoadedEpoch)
        .timeout(reviewBudget);
    if (loaded.epoch <= fileLoadedEpoch ||
        loaded.playlistEntryId != playlistEntryId) {
      throw StateError('No matching native file-loaded event for this open');
    }
    final deadline = DateTime.now().add(reviewBudget);
    var currentPath = '';
    var videoFormat = '';
    while (DateTime.now().isBefore(deadline)) {
      currentPath = await readProperty('path');
      videoFormat = await readProperty('video-format');
      if (currentPath == mediaUri && videoFormat.isNotEmpty) break;
      await delay(const Duration(milliseconds: 50));
    }
    if (currentPath != mediaUri || videoFormat.isEmpty) {
      throw StateError(
          'New media track not observed: path=$currentPath format=$videoFormat');
    }
    // video-params are the review's second input (plan 1.4 step 8): wait
    // for the base-layer tags the same bounded way as the decoder below,
    // keeping the media identity. FILE_LOADED and video-format can precede
    // the first parameter report, and classifying from the profile alone
    // mis-routes the open (an integer profile 8 without gamma is a
    // conservative SDR-base-layer DV, not the 8.1/8.4 the tags decide).
    while (latestVideoParams() == null && DateTime.now().isBefore(deadline)) {
      if (await readProperty('path') != mediaUri) {
        throw StateError('Media changed before video-params verification');
      }
      await delay(const Duration(milliseconds: 50));
    }
    // FILE_LOADED and video-format can precede decoder initialization on a
    // newly bound gpu-next output. Keep the same media identity while
    // waiting for the decoder instead of treating the initial empty
    // property as a software-decoding verdict. One observation happens even
    // when the params poll consumed the budget, so the review always sees
    // the decoder's actual state.
    var hwdec = '';
    while (true) {
      if (await readProperty('path') != mediaUri) {
        throw StateError('Media changed before decoder verification');
      }
      hwdec = await readProperty('hwdec-current');
      if (hwdec == expectedHwdec) break;
      if (hwdec.isNotEmpty) break;
      if (!DateTime.now().isBefore(deadline)) break;
      await delay(const Duration(milliseconds: 50));
    }
    final profile = int.tryParse(
      (await readProperty('current-tracks/video/dolby-vision-profile'))
          .trim(),
    );
    final codec = await readProperty('current-tracks/video/codec');
    return HdrReviewFacts(
      videoParams: latestVideoParams(),
      dolbyVisionProfile: profile,
      codec: codec,
      hwdecCurrent: hwdec,
      path: currentPath,
    );
  }

  @override
  HdrBackendObservation observe() {
    return HdrBackendObservation(
      dataSpaceRequested: _dataSpaceRequested,
      dataSpacePath: _dataSpacePath,
      dataSpaceReadback: _dataSpaceReadback,
      hwdecCurrent: _lastHwdecCurrent,
    );
  }

  Future<void> dispose() async {
    await _videoParamsSubscription?.cancel();
    _videoParamsSubscription = null;
  }
}
