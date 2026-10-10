/// This file is a part of media_kit (https://github.com/media-kit/media-kit).
///
/// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
/// All rights reserved.
/// Use of this source code is governed by MIT license that can be found in the LICENSE file.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:synchronized/synchronized.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:media_kit_video/src/video_controller/android_video_controller/android_video_controller.dart';

import 'hdr_open_coordinator.dart';
import 'hdr_native_dv_option_owner.dart';
import 'hdr_native_dv_review.dart';
import 'hdr_native_dv_review_evidence.dart';
import 'hdr_yuv_presentation_contract.dart';

/// Android execution backend for `HdrVideoSession` (ported from hdr_lab's
/// `AndroidHdrPlayerBackend` with the sample identity removed): writes mpv
/// properties and confirms them by readback, restores the captured values on
/// session end or source switch, attaches the RPU-stripping filter per
/// route, applies the P5 transactional defaults, verifies `hwdec-current`,
/// and applies the GPU surface dataspace through
/// `AndroidVideoController.invokeApplyDataSpace`.
///
/// Native DV source ownership requires source changes to use the Player's
/// default serialized playback APIs. Raw `command`, source-changing property
/// writes, and `synchronized: false` calls bypass that lock. Identity checks
/// detect observable drift, but cannot attribute a same-URI raw replacement
/// before its first event. Such concurrent mutations are outside this managed
/// session contract; the native DV route remains unsupported by default.
///
/// Output capability and actual presentation must still be checked
/// separately on the device.
class AndroidHdrBackend implements HdrOpenBackend<HdrOpenPlan> {
  AndroidHdrBackend({
    required this.player,
    required this.outputSlot,
    void Function(HdrNativeDvOptionDiagnostic)? onNativeDvOptionDiagnostic,
    Future<Map<String, Object?>?> Function(int handle, String transfer)?
        applyDataSpace,
  }) : _applyDataSpace = applyDataSpace ??
            ((int handle, String transfer) =>
                AndroidVideoController.invokeApplyDataSpace(
                  handle: handle,
                  transfer: transfer,
                )) {
    _nativeDvOptions = HdrNativeDvOptionOwner(
      readProperty: player.getProperty,
      setPropertyStrict: player.setPropertyStrict,
      readIdentity: _readOptionIdentity,
      onDiagnostic: onNativeDvOptionDiagnostic,
    );
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

  late final HdrNativeDvOptionOwner _nativeDvOptions;
  HdrNativeDvPendingOpen? _nativeDvPendingOpen;
  bool _nativeDvPendingOwnStopIssued = false;
  HdrOptionSourceIdentity? _nativeDvStopAttemptBefore;

  bool _rpuFilterApplied = false;
  bool _observedStoppedPath = false;
  HdrOptionSourceIdentity? _stoppedBoundary;
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
    final route = plan.route;
    // A4 contract split: a route declaring the YUV window shape must carry
    // the whole accepted presentation quad, before any owned property write
    // or output creation runs (fail-closed).
    HdrYuvPresentationContract.validate(route);
    final hasPair = route.strategy == HdrStrategy.nativeDolbyVision ||
        route.vdLavcOptions != null ||
        route.mediacodecEmbedRenderMode != null;
    if (hasPair &&
        (route.strategy != HdrStrategy.nativeDolbyVision ||
            route.vdLavcOptions != 'native_dv=1' ||
            (route.mediacodecEmbedRenderMode != 'timed' &&
                route.mediacodecEmbedRenderMode != 'boolean') ||
            route.vo != 'mediacodec_embed' ||
            route.hwdec != 'mediacodec' ||
            route.topology != HdrTopology.platformView ||
            route.stripDvRpu)) {
      throw StateError('Invalid native DV execution option pair');
    }
  }

  /// Uses the SAME non-reentrant lock as default public Player.open. The
  /// supplied open must explicitly bypass nested locking. Capture and publish
  /// the immutable entry proof before releasing admission to another open.
  /// FILE_LOADED waiting belongs outside this short critical section.
  @visibleForTesting
  static Future<HdrNativeDvPendingOpen> captureNativeDvOpenUnderLock({
    required Lock lock,
    required HdrNativeDvOptionOwner options,
    required String mediaUri,
    required Future<void> Function() openWithoutLock,
    required Future<String> Function(String) readProperty,
    required void Function(HdrNativeDvPendingOpen) onCaptured,
  }) =>
      lock.synchronized(() async {
        await options.assertCurrent();
        final before = options.identity;
        if (before == null ||
            before.path.isNotEmpty ||
            before.playlistEntryId.isNotEmpty) {
          throw StateError('No owned stopped boundary before native DV open');
        }
        await openWithoutLock();
        final filename = await readProperty('playlist/0/filename');
        final rawId = await readProperty('playlist/0/id');
        final entryId = int.tryParse(rawId);
        if (filename != mediaUri ||
            entryId == null ||
            entryId < 0 ||
            await readProperty('playlist/0/filename') != filename ||
            await readProperty('playlist/0/id') != rawId ||
            options.identity != before) {
          throw StateError(
              'Opened native DV playlist differs from owned operation');
        }
        final captured = HdrNativeDvPendingOpen(
            before: before, mediaUri: mediaUri, playlistEntryId: entryId);
        onCaptured(captured);
        return captured;
      });

  /// Capture only: neither FILE_LOADED waiting nor owner rebind happens
  /// while this shared lock is held. The returned proof must be acknowledged
  /// outside the lock, then checked again under it before updating ownership.
  @visibleForTesting
  static Future<HdrNativeDvStoppedCapture> captureNativeDvStopUnderLock({
    required Lock lock,
    required HdrNativeDvOptionOwner options,
    required void Function(HdrOptionSourceIdentity) onStopIssued,
    required Future<void> Function() stopWithoutLock,
    required Future<HdrOptionSourceIdentity> Function() readIdentity,
  }) =>
      lock.synchronized(() async {
        await options.assertCurrent();
        final before = options.identity;
        if (before == null) {
          throw StateError('No owned native DV stop boundary');
        }
        onStopIssued(before);
        Object? operationError;
        StackTrace? operationStack;
        try {
          await stopWithoutLock();
        } catch (error, stack) {
          operationError = error;
          operationStack = stack;
        }
        try {
          final stopped = await readIdentity();
          if (!identical(stopped.player, before.player) ||
              stopped.path.isNotEmpty ||
              stopped.playlistEntryId.isNotEmpty ||
              options.identity != before) {
            throw StateError('Stop did not clear owned native DV source');
          }
          return HdrNativeDvStoppedCapture(
              before: before,
              stopped: stopped,
              operationError: operationError,
              operationStack: operationStack);
        } catch (identityError) {
          throw HdrNativeDvOptionFailure(
              operationError, {'sourceIdentity': identityError});
        }
      });

  /// Shared by production and tests: a cross-lock proof is never reused as
  /// current state without this fresh check inside the same Player lock.
  @visibleForTesting
  static Future<void> rebindNativeDvUnderLock({
    required Lock lock,
    required HdrNativeDvOptionOwner options,
    required HdrOptionSourceIdentity before,
    required HdrOptionSourceIdentity confirmed,
  }) =>
      lock.synchronized(() => options.rebind(before, confirmed));

  @visibleForTesting
  static Future<HdrOptionSourceIdentity> captureStoppedBoundaryUnderLock({
    required Lock lock,
    required Future<void> Function() stopWithoutLock,
    required Future<HdrOptionSourceIdentity> Function() readIdentity,
  }) =>
      lock.synchronized(() async {
        await stopWithoutLock();
        var stopped = await readIdentity();
        var pathEmpty = stopped.path.isEmpty;
        var entryEmpty = stopped.playlistEntryId.isEmpty;
        final prefix = 'Stop did not establish a stable empty source';
        // mpv clears the playlist synchronously before `stop` returns, but the
        // path property only resets once file teardown finishes; a read that
        // lands in between observes an empty entry with a stale path. Bounded
        // re-reads absorb that window; any other identity dimension changing
        // across them keeps the original failure.
        var rereads = 0;
        while (!pathEmpty && entryEmpty && rereads < 5) {
          rereads++;
          await Future<void>.delayed(const Duration(milliseconds: 100));
          final candidate = await readIdentity();
          if (!identical(candidate.player, stopped.player) ||
              candidate.playlistEntryId.isNotEmpty ||
              candidate.fileLoadedEpoch != stopped.fileLoadedEpoch) {
            throw StateError('$prefix; reason=identity-changed; '
                'pathEmpty=$pathEmpty; entryEmpty=$entryEmpty; '
                'firstEpoch=${stopped.fileLoadedEpoch}; '
                'secondEpoch=${candidate.fileLoadedEpoch}; '
                'samePlayer=${identical(candidate.player, stopped.player)}; '
                'secondPathEmpty=${candidate.path.isEmpty}; '
                'secondEntryEmpty=${candidate.playlistEntryId.isEmpty}; '
                'entryIdMatches=${candidate.playlistEntryId == stopped.playlistEntryId}; '
                'rereads=$rereads');
          }
          stopped = candidate;
          pathEmpty = stopped.path.isEmpty;
          entryEmpty = stopped.playlistEntryId.isEmpty;
        }
        if (!pathEmpty || !entryEmpty) {
          final reason = !pathEmpty ? 'path-not-empty' : 'entry-not-empty';
          throw StateError('$prefix; reason=$reason; pathEmpty=$pathEmpty; '
              'entryEmpty=$entryEmpty; firstEpoch=${stopped.fileLoadedEpoch}'
              '${rereads > 0 ? '; rereads=$rereads' : ''}');
        }
        final second = await readIdentity();
        if (second != stopped) {
          throw StateError('$prefix; reason=identity-changed; '
              'pathEmpty=$pathEmpty; entryEmpty=$entryEmpty; '
              'firstEpoch=${stopped.fileLoadedEpoch}; '
              'secondEpoch=${second.fileLoadedEpoch}; '
              'samePlayer=${identical(second.player, stopped.player)}; '
              'secondPathEmpty=${second.path.isEmpty}; '
              'secondEntryEmpty=${second.playlistEntryId.isEmpty}; '
              'entryIdMatches=${second.playlistEntryId == stopped.playlistEntryId}');
        }
        return stopped;
      });

  @visibleForTesting
  static Future<void> beginNativeDvUnderLock({
    required Lock lock,
    required HdrNativeDvOptionOwner options,
    required HdrOptionSourceIdentity stoppedIdentity,
    required String vd,
    required String renderMode,
  }) =>
      lock.synchronized(() => options.begin(
          stoppedIdentity: stoppedIdentity, vd: vd, renderMode: renderMode));

  Future<HdrOptionSourceIdentity> _readOptionIdentity() async {
    final epoch = player.fileLoadedEpoch;
    final path = await player.getProperty('path');
    final entry = await player.getProperty('playlist/0/id');
    if (await player.getProperty('path') != path ||
        await player.getProperty('playlist/0/id') != entry ||
        player.fileLoadedEpoch != epoch) {
      throw StateError('Media changed while reading native DV option identity');
    }
    return HdrOptionSourceIdentity(
      player: player,
      path: path,
      playlistEntryId: entry,
      fileLoadedEpoch: epoch,
    );
  }

  /// Only a matching native FILE_LOADED record permits the backend to move
  /// option ownership from its stopped boundary onto the entry it opened.
  /// Kept injectable so late loading and failed-open rollback are tested
  /// without creating a native Player.
  @visibleForTesting
  static Future<HdrOptionSourceIdentity> confirmNativeDvOpenIdentity({
    required HdrOptionSourceIdentity before,
    required String mediaUri,
    required Future<HdrOptionSourceIdentity> Function() readIdentity,
    required Future<String> Function() readPlaylistFilename,
    required Future<FileLoadedRecord> Function(int, int) waitForFileLoadedEntry,
    required int expectedPlaylistEntryId,
    bool allowUnchanged = false,
    Duration budget = const Duration(seconds: 8),
  }) async {
    final current = await readIdentity();
    if (allowUnchanged && current == before) return before;
    final entryId = expectedPlaylistEntryId;
    return HdrNativeDvPendingOpen(
      before: before,
      mediaUri: mediaUri,
      playlistEntryId: entryId,
    ).confirmForCleanup(
      readIdentity: readIdentity,
      readPlaylistFilename: readPlaylistFilename,
      waitForFileLoadedEntry: waitForFileLoadedEntry,
      requireLoaded: true,
      budget: budget,
    );
  }

  Future<void> _recoverNativeDvPendingOpen() async {
    final pending = _nativeDvPendingOpen;
    if (pending == null) return;
    final previous = _nativeDvOptions.identity;
    if (previous == null) {
      throw StateError('Native DV pending open lost option ownership');
    }
    final current = await pending.confirmForCleanup(
      readIdentity: _readOptionIdentity,
      readPlaylistFilename: () => player.getProperty('playlist/0/filename'),
      waitForFileLoadedEntry: player.waitForFileLoadedEntryAfter,
      afterOwnStop: _nativeDvPendingOwnStopIssued,
    );
    await rebindNativeDvUnderLock(
        lock: player.lock,
        options: _nativeDvOptions,
        before: previous,
        confirmed: current);
    if (_nativeDvPendingOwnStopIssued &&
        current.path.isEmpty &&
        current.playlistEntryId.isEmpty) {
      _nativeDvPendingOpen = null;
      _nativeDvPendingOwnStopIssued = false;
      _nativeDvStopAttemptBefore = null;
    }
    // Retain the verified entry through stop: its first FILE_LOADED can
    // race with our own unload after the pre-stop confirmation.
  }

  Future<void> _recoverNativeDvStopAttempt() async {
    final before = _nativeDvStopAttemptBefore;
    if (before == null || _nativeDvPendingOpen != null) return;
    final actual = await _readOptionIdentity();
    if (actual == before) {
      // The failed public stop never unloaded its owned source. It can be
      // retried, but only after checking that source again under admission.
      await player.lock.synchronized(() async {
        await _nativeDvOptions.assertCurrent();
        _nativeDvStopAttemptBefore = null;
      });
      return;
    }
    final stopped = await confirmNativeDvStoppedIdentity(
        before: before, readIdentity: _readOptionIdentity);
    await rebindNativeDvUnderLock(
        lock: player.lock,
        options: _nativeDvOptions,
        before: before,
        confirmed: stopped);
    _nativeDvStopAttemptBefore = null;
  }

  Future<HdrOptionSourceIdentity> _confirmNativeDvOwnStop(
      HdrOptionSourceIdentity before) async {
    final pending = _nativeDvPendingOpen;
    if (pending == null) {
      return confirmNativeDvStoppedIdentity(
          before: before, readIdentity: _readOptionIdentity);
    }
    final stopped = await pending.confirmForCleanup(
      readIdentity: _readOptionIdentity,
      readPlaylistFilename: () => player.getProperty('playlist/0/filename'),
      waitForFileLoadedEntry: player.waitForFileLoadedEntryAfter,
      afterOwnStop: true,
    );
    if (stopped.path.isNotEmpty || stopped.playlistEntryId.isNotEmpty) {
      throw StateError('Native DV stop did not unload its pending entry');
    }
    return stopped;
  }

  @visibleForTesting
  static Future<HdrOptionSourceIdentity> confirmNativeDvStoppedIdentity({
    required HdrOptionSourceIdentity before,
    required Future<HdrOptionSourceIdentity> Function() readIdentity,
  }) async {
    final stopped = await readIdentity();
    if (!identical(stopped.player, before.player) ||
        stopped.path.isNotEmpty ||
        stopped.playlistEntryId.isNotEmpty ||
        stopped.fileLoadedEpoch != before.fileLoadedEpoch ||
        await readIdentity() != stopped) {
      throw StateError('Native DV stop crossed an unowned media boundary');
    }
    return stopped;
  }

  @override
  Future<void> stop() async {
    _observedStoppedPath = false;
    _stoppedBoundary = null;
    // All possible FILE_LOADED waits happen before/after the critical section.
    await _recoverNativeDvPendingOpen();
    await _recoverNativeDvStopAttempt();
    if (!_nativeDvOptions.active) {
      _stoppedBoundary = await captureStoppedBoundaryUnderLock(
          lock: player.lock,
          stopWithoutLock: () => player.stop(synchronized: false),
          readIdentity: _readOptionIdentity);
    } else {
      final captured = await captureNativeDvStopUnderLock(
        lock: player.lock,
        options: _nativeDvOptions,
        onStopIssued: (before) {
          _nativeDvStopAttemptBefore = before;
          if (_nativeDvPendingOpen != null) {
            _nativeDvPendingOwnStopIssued = true;
          }
        },
        stopWithoutLock: () => player.stop(synchronized: false),
        readIdentity: _readOptionIdentity,
      );
      try {
        final confirmed = await _confirmNativeDvOwnStop(captured.before);
        if (confirmed != captured.stopped) {
          throw StateError(
              'Native DV stopped proof changed before acknowledgement');
        }
        await rebindNativeDvUnderLock(
            lock: player.lock,
            options: _nativeDvOptions,
            before: captured.before,
            confirmed: confirmed);
        _stoppedBoundary = confirmed;
        _nativeDvPendingOpen = null;
        _nativeDvPendingOwnStopIssued = false;
        _nativeDvStopAttemptBefore = null;
      } catch (identityError) {
        throw HdrNativeDvOptionFailure(
            captured.operationError, {'sourceIdentity': identityError});
      }
      if (captured.operationError != null) {
        Error.throwWithStackTrace(
            captured.operationError!, captured.operationStack!);
      }
    }
    _observedStoppedPath = true;
  }

  @override
  Future<void> resetOwnedConfiguration() async {
    await _recoverNativeDvPendingOpen();
    await _recoverNativeDvStopAttempt();
    await player.lock.synchronized(_nativeDvOptions.restore);
    _nativeDvPendingOpen = null;
    _nativeDvPendingOwnStopIssued = false;
    _nativeDvStopAttemptBefore = null;
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
    await validate(plan);
    if (route.vdLavcOptions != null) {
      final stopped = _stoppedBoundary;
      if (!_observedStoppedPath || stopped == null) {
        throw StateError('No stopped-media boundary before native DV options');
      }
      await beginNativeDvUnderLock(
          lock: player.lock,
          options: _nativeDvOptions,
          stoppedIdentity: stopped,
          vd: route.vdLavcOptions!,
          renderMode: route.mediacodecEmbedRenderMode!);
    }
    final gpuPlatform =
        route.topology == HdrTopology.platformView && route.vo == 'gpu-next';
    if (gpuPlatform) {
      await _setOwned('egl-output-format', 'rgb10_a2');
    }
    // The Android video controller applies its creation-time hwdec setting
    // while it initializes. Capture and register ownership before ensure()
    // can construct that controller, or its initialization may overwrite the
    // value that resetOwnedConfiguration is meant to restore.
    await _setOwned('hwdec', route.hwdec);
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
    if (route.vdLavcOptions != null) {
      await player.lock.synchronized(_nativeDvOptions.verify);
    }
    // A4 contract split: on the YUV window route both contracts are issued
    // here — the offscreen contract as the mpv output-levels option (the
    // lab define's MPV_OUTPUT_LEVELS=full application, promoted into the
    // backend) and the window contract through the dataspace apply below.
    // The quad is re-validated fail-closed first, and the write is owned so
    // the session end restores the captured value. Routes without an
    // offscreen contract issue nothing (default routing unchanged).
    if (HdrYuvPresentationContract.isYuvWindowRoute(route)) {
      HdrYuvPresentationContract.validate(route);
      await _setOwned(
          'video-output-levels',
          HdrYuvPresentationContract.mpvOutputLevels(
              route.offscreenTransfer!));
    }
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
        // Only the evidence-pinned API24 LG extension may accept a setter
        // without readback. This is not verified presentation evidence.
        final bool acceptedWithoutReadback = acceptsUnverifiedLgSetter(
            plan.capabilities, transfer, _dataSpacePath, _dataSpaceReadback);
        if (_dataSpacePath != 'surfaceControl' &&
            !acceptedWithoutReadback &&
            !dataSpaceReadbackMatches(transfer, _dataSpaceReadback)) {
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
    if (route.vdLavcOptions != null) {
      await player.lock.synchronized(_nativeDvOptions.verify);
    }
  }

  /// The readback is expected to carry the requested transfer on the
  /// ANativeWindow paths (`ndk`/`ext:<id>`); constant names differ per
  /// platform, so match on the transfer keyword.
  static bool dataSpaceReadbackMatches(String transfer, String? readback) {
    final value = readback?.toUpperCase();
    switch (transfer) {
      case 'pq':
        return value == 'DATASPACE_BT2020_PQ' || value == '0X09C60000';
      case 'pq-itu':
        return value == 'DATASPACE_BT2020_PQ_LIMITED' || value == '0X11C60000';
      case 'hlg':
        return value == 'DATASPACE_BT2020_HLG' || value == '0X09C70000';
      default:
        return false;
    }
  }

  static bool acceptsUnverifiedLgSetter(HdrCapabilities capabilities,
      String transfer, String? path, String? readback) {
    return capabilities.sdkInt == 24 &&
        capabilities.dataSpaceExt?.id == 'lg-pq' &&
        capabilities.dataSpaceExt?.applicable == true &&
        path == 'ext:lg-pq' &&
        (transfer == 'pq' || transfer == 'pq-itu') &&
        (readback == null || readback.isEmpty || readback == 'none');
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
    _stoppedBoundary = null;
    final media = plan.media;
    // Drop the previous media's cached video-params so the review waits for
    // this open's report instead of classifying from a stale source.
    _latestVideoParams = null;
    _openFileLoadedEpoch = player.fileLoadedEpoch;
    _openPlaylistEntryId = null;
    await _nativeDvOptions.assertCurrent();
    final optionIdentity = _nativeDvOptions.identity;
    var identityConfirmationAttempted = false;
    try {
      final playable = start == null && media.start == null
          ? media
          : Media(media.uri,
              start: start ?? media.start,
              end: media.end,
              extras: media.extras,
              httpHeaders: media.httpHeaders);
      if (optionIdentity != null) {
        final captured = await captureNativeDvOpenUnderLock(
          lock: player.lock,
          options: _nativeDvOptions,
          mediaUri: media.uri,
          openWithoutLock: () =>
              player.open(playable, play: play, synchronized: false),
          readProperty: player.getProperty,
          onCaptured: (entry) {
            _openFileLoadedEpoch = entry.before.fileLoadedEpoch;
            _openPlaylistEntryId = entry.playlistEntryId;
            _nativeDvPendingOpen = entry;
            _nativeDvPendingOwnStopIssued = false;
          },
        );
        identityConfirmationAttempted = true;
        // The immutable proof was captured under Player.lock. An external
        // default open admitted now cannot be mistaken for this entry.
        final opened = await confirmNativeDvOpenIdentity(
          before: captured.before,
          mediaUri: captured.mediaUri,
          expectedPlaylistEntryId: captured.playlistEntryId,
          readIdentity: _readOptionIdentity,
          readPlaylistFilename: () => player.getProperty('playlist/0/filename'),
          waitForFileLoadedEntry: player.waitForFileLoadedEntryAfter,
        );
        await rebindNativeDvUnderLock(
            lock: player.lock,
            options: _nativeDvOptions,
            before: captured.before,
            confirmed: opened);
        _nativeDvPendingOpen = null;
        _nativeDvPendingOwnStopIssued = false;
      } else {
        await player.open(playable, play: play);
        final playlistPath = await player.getProperty('playlist/0/filename');
        final entryId = int.tryParse(await player.getProperty('playlist/0/id'));
        if (playlistPath != media.uri || entryId == null) {
          throw StateError(
              'Opened playlist entry differs from requested source: '
              'path=$playlistPath id=$entryId');
        }
        _openPlaylistEntryId = entryId;
      }
    } catch (error, stack) {
      if (!identityConfirmationAttempted &&
          optionIdentity != null &&
          _nativeDvOptions.identity == optionIdentity) {
        try {
          // Without a verified returned entry, a same-URI current playlist
          // could belong to an external open. Only the unchanged stopped
          // boundary is safe to recover here.
          if (await _readOptionIdentity() != optionIdentity) {
            throw StateError(
                'Failed native DV open has no verified owned entry');
          }
          await _nativeDvOptions.assertCurrent();
        } catch (identityError) {
          throw HdrNativeDvOptionFailure(
              error, {'sourceIdentity': identityError});
        }
      }
      Error.throwWithStackTrace(error, stack);
    }
  }

  @override
  Future<HdrReviewFacts> reviewFacts(HdrOpenPlan plan) async {
    final before = _openFileLoadedEpoch;
    final entryId = _openPlaylistEntryId;
    if (before == null || entryId == null) {
      throw StateError('No playlist-entry identity before review');
    }
    if (plan.route.strategy == HdrStrategy.nativeDolbyVision) {
      final expected = _nativeDvOptions.identity;
      if (expected == null || expected.path != plan.media.uri) {
        throw const HdrNativeDvReviewFailure(
            HdrNativeDvReviewFailureKind.ownership);
      }
      final facts = await gatherNativeDvReviewFacts(
        lock: player.lock,
        expectedIdentity: expected,
        openedAfterEpoch: before,
        expectedEntryId: entryId,
        verifyOwned: () async {
          if (_nativeDvOptions.identity != expected) {
            throw StateError('Native DV review lost its owned open');
          }
          await _nativeDvOptions.verify();
          if (_nativeDvOptions.identity != expected) {
            throw StateError('Native DV review ownership changed');
          }
        },
        readIdentity: _readOptionIdentity,
        waitForFileLoadedEntry: player.waitForFileLoadedEntryAfter,
        readOutput: () {
          final controller = outputSlot.current?.notifier.value;
          if (controller is! AndroidVideoController) return null;
          if (!identical(controller.player, player)) {
            throw const HdrNativeDvReviewFailure(
                HdrNativeDvReviewFailureKind.outputIdentity);
          }
          final identity = controller.currentBoundOutputIdentity;
          return identity == null
              ? null
              : HdrNativeDvOutputSnapshot(controller, identity);
        },
        readProperty: player.getProperty,
        latestVideoParams: () => _latestVideoParams,
      );
      _lastHwdecCurrent = facts.hwdecCurrent;
      return facts;
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
    final loaded =
        await waitForFileLoadedEntry(playlistEntryId, fileLoadedEpoch)
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
      (await readProperty('current-tracks/video/dolby-vision-profile')).trim(),
    );
    final codec = await readProperty('current-tracks/video/codec');
    // The fork's container/track facts (fork 0f7e6bec32+) are read once,
    // right after the profile/codec reads — the same single-observation
    // pattern, no extra polling round. These are side-data/track facts, not
    // watched properties: a review executed mid-play samples the state at
    // its execution point and does not observe later frame changes. An
    // unavailable property reads as an empty string (getProperty never
    // throws for unavailable), so a failed parse is already the unknown
    // value the classifier falls back from.
    final compatibilityIdRaw = int.tryParse(
      (await readProperty('current-tracks/video/dolby-vision-compatibility-id'))
          .trim(),
    );
    // No DOVI configuration record → the whole property is unavailable;
    // with a record, `0` is a valid value (DV spec "None") and `-1` is the
    // in-record "unknown" sentinel — every negative reads as unknown.
    final dvCompatibilityId =
        compatibilityIdRaw != null && compatibilityIdRaw >= 0
            ? compatibilityIdRaw
            : null;
    final elPresentRaw = int.tryParse(
      (await readProperty('current-tracks/video/dolby-vision-el-present'))
          .trim(),
    );
    final dvElPresent = elPresentRaw == 1
        ? true
        : elPresentRaw == 0
            ? false
            : null; // -1 (unknown sentinel), unavailable, non-numeric.
    // `video-params/hdr-vivid` is readable once video-params carry the
    // base-layer tags (the poll above guarantees the read happens after the
    // first frame); on the timeout path it is still sampled once and read
    // defensively ('yes'/'no' are the only mpv bool spellings).
    final hdrVividRaw = await readProperty('video-params/hdr-vivid');
    final hdrVivid = hdrVividRaw == 'yes'
        ? true
        : hdrVividRaw == 'no'
            ? false
            : null;
    return HdrReviewFacts(
      videoParams: latestVideoParams(),
      dolbyVisionProfile: profile,
      codec: codec,
      hwdecCurrent: hwdec,
      path: currentPath,
      dvCompatibilityId: dvCompatibilityId,
      dvElPresent: dvElPresent,
      hdrVivid: hdrVivid,
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
