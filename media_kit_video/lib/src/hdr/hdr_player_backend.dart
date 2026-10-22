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
import 'hdr_decoder_review.dart';
import 'hdr_container_source_discovery.dart';
import 'hdr_container_probe_owner.dart';
import 'hdr_native_dv_option_owner.dart';
import 'hdr_native_dv_review.dart';
import 'hdr_native_dv_review_evidence.dart';
import 'hdr_yuv_presentation_contract.dart';
import 'hdr_yuv_window_arm.dart';
import 'hdr_output_resources.dart';

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
abstract interface class HdrContainerSourceBackend {
  Future<void> prepareSourceDiscovery(HdrOpenPlan plan);

  Future<void> resumeSourceDiscovery(HdrOpenPlan plan);

  Future<HdrContainerSourceSnapshot?> discoverSource(HdrOpenPlan plan);
}

/// Optional same-entry transition from a paused decoderless source probe to
/// an owned native Dolby Vision route. A positive capability check is pure;
/// once promotion starts, failures must be surfaced for owned cleanup rather
/// than reopening or treating the entry as an ordinary retry.
abstract interface class HdrContainerSourcePromotionBackend {
  Future<bool> canPromoteDiscoveredSource(
      HdrOpenPlan previous, HdrOpenPlan next);

  Future<void> promoteDiscoveredSource(
    HdrOpenPlan previous,
    HdrOpenPlan next, {
    Duration? start,
  });
}

class AndroidHdrBackend
    implements
        HdrOpenBackend<HdrOpenPlan>,
        HdrContainerSourceBackend,
        HdrContainerSourcePromotionBackend {
  static const bool _startupTrace =
      bool.fromEnvironment('MEDIA_KIT_STARTUP_TRACE');

  AndroidHdrBackend({
    required this.player,
    required this.outputSlot,
    this.surfacePixelFormatOverride = 'rgba1010102',
    HdrYuvWindowArm? yuvWindowArm,
    VideoControllerConfiguration controllerConfiguration =
        const VideoControllerConfiguration(),
    void Function(HdrNativeDvOptionDiagnostic)? onNativeDvOptionDiagnostic,
    bool Function(HdrOpenPlan)? reviewIsCurrent,
    Future<Map<String, Object?>?> Function(int handle, String transfer)?
        applyDataSpace,
  }) : _applyDataSpace = applyDataSpace ??
            ((int handle, String transfer) =>
                AndroidVideoController.invokeApplyDataSpace(
                  handle: handle,
                  transfer: transfer,
                )) {
    this.reviewIsCurrent = reviewIsCurrent ?? ((_) => true);
    managedYuvCarrier = controllerConfiguration.android.managedYuvCarrier;
    this.yuvWindowArm = yuvWindowArm ??
        HdrYuvWindowArm(
          ownerToken: controllerConfiguration.android.lgExperimentOwnerToken,
          ownerGeneration: () async {
            final current = outputSlot.current;
            if (current == null || !current.platform.isCompleted) return null;
            final output = await current.platform.future;
            final generation = output.nativeSurfaceGeneration;
            return generation > 0 ? generation : null;
          },
        );
    _nativeDvOptions = HdrNativeDvOptionOwner(
      readProperty: player.getPropertyAsync,
      readProperties: player.getPropertiesAsync,
      currentFileLoadedEpoch: () => player.fileLoadedEpoch,
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
  final String surfacePixelFormatOverride;
  late final bool Function(HdrOpenPlan) reviewIsCurrent;

  /// W1 managed YUV-carrier mode: the platform view's Surface is registered
  /// and armed Java-side before the surface event; the Dart arm holds only
  /// the process write gate and the diag-dataspace atom.
  late final bool managedYuvCarrier;

  /// Route-scoped YUV window presentation arms (plan C). Null keeps the
  /// backend's behavior unchanged (no arm, no admission change).
  late final HdrYuvWindowArm? yuvWindowArm;

  HdrOutputResources<HdrOpenPlan>? get outputResources => yuvWindowArm;

  final Future<Map<String, Object?>?> Function(int handle, String transfer)
      _applyDataSpace;
  StreamSubscription<VideoParams>? _videoParamsSubscription;
  VideoParams? _latestVideoParams;

  late final HdrNativeDvOptionOwner _nativeDvOptions;
  final HdrContainerProbeOwner _containerProbeOwner = HdrContainerProbeOwner();
  HdrOpenPlan? _promotedProbePlan;
  HdrOptionSourceIdentity? _promotedProbeIdentity;
  HdrNativeDvStoppedCapture? _promotionStoppedCapture;
  // Restoring the native pair and retiring the probe do not acknowledge a
  // failed stop call to the coordinator. Keep its completed boundary until a
  // later managed open is admitted under Player.lock. Cleanup retries must
  // never fall through to an unowned stop after the owners have retired.
  HdrOptionSourceIdentity? _completedPromotionStop;
  HdrNativeDvPendingOpen? _nativeDvPendingOpen;
  bool _nativeDvPendingOwnStopIssued = false;
  HdrOptionSourceIdentity? _nativeDvStopAttemptBefore;

  bool _rpuFilterApplied = false;
  bool _observedStoppedPath = false;
  HdrOptionSourceIdentity? _stoppedBoundary;
  int? _openFileLoadedEpoch;
  int? _openPlaylistEntryId;
  int _ordinaryReviewSerial = 0;
  Stopwatch? _ordinaryReviewClock;
  String? _dataSpaceRequested;
  String? _dataSpacePath;
  String? _dataSpaceReadback;
  String? _lastHwdecCurrent;

  /// The RPU-stripping filter label; hdr_lab used the sample-specific name
  /// `@media-kit-p84-base`.
  static const String _dvRpuFilter = '@media-kit-dv-base';

  bool get _hasTransferredProbeDebt {
    final plan = _promotedProbePlan;
    return plan != null && _containerProbeOwner.promotionTransferred(plan);
  }

  static bool _promotionPlanPairIsEligible(
      HdrOpenPlan previous, HdrOpenPlan next) {
    final from = previous.route;
    final to = next.route;
    final facts = next.sourceFacts;
    final source = next.source;
    final sourceFactsMatch = facts != null &&
        !facts.hasConflict &&
        facts.source == source &&
        facts.origins[HdrSourceField.codec] == HdrSourceFactOrigin.track &&
        facts.origins[HdrSourceField.dvProfile] == HdrSourceFactOrigin.track &&
        facts.origins[HdrSourceField.dvCompatibilityId] ==
            HdrSourceFactOrigin.track &&
        facts.origins[HdrSourceField.enhancementLayer] ==
            HdrSourceFactOrigin.track;
    final sourceIsSupported = source.codec == 'hevc' &&
        source.dynamicMetadata == HdrDynamicMetadata.dolbyVision &&
        source.enhancementLayer == false &&
        ((source.dvProfile == 5 && source.dvCompatibilityId == 0) ||
            (source.dvProfile == 8 && source.dvCompatibilityId == 4));
    return identical(previous.media, next.media) &&
        previous.media.uri == next.media.uri &&
        previous.sourceOrigin == null &&
        previous.source == const HdrSourceDescriptor() &&
        from.strategy == HdrStrategy.sdrDirect &&
        from.presentation == HdrPresentation.sdr &&
        from.outputTransfer == HdrOutputTransfer.sdr &&
        !from.appliesDynamicMetadata &&
        from.topology == HdrTopology.texture &&
        from.vo == 'gpu-next' &&
        from.vdLavcOptions == null &&
        from.mediacodecEmbedRenderMode == null &&
        !from.stripDvRpu &&
        from.targetPrim == null &&
        from.targetTrc == null &&
        from.surfaceTransfer == null &&
        to.strategy == HdrStrategy.nativeDolbyVision &&
        to.presentation == HdrPresentation.nativeDolbyVision &&
        to.outputTransfer == HdrOutputTransfer.dolbyVision &&
        to.appliesDynamicMetadata &&
        to.topology == HdrTopology.platformView &&
        to.vo == 'mediacodec_embed' &&
        to.hwdec == 'mediacodec' &&
        to.vdLavcOptions == 'native_dv=1' &&
        (to.mediacodecEmbedRenderMode == 'timed' ||
            to.mediacodecEmbedRenderMode == 'boolean') &&
        to.surfaceTransfer == null &&
        !to.stripDvRpu &&
        to.targetPrim == null &&
        to.targetTrc == null &&
        sourceFactsMatch &&
        sourceIsSupported;
  }

  @override
  Future<bool> canPromoteDiscoveredSource(
          HdrOpenPlan previous, HdrOpenPlan next) async =>
      !_nativeDvOptions.active &&
      _promotedProbePlan == null &&
      _promotionStoppedCapture == null &&
      _containerProbeOwner.canPromote(previous) &&
      _promotionPlanPairIsEligible(previous, next);

  Future<void> _setOwned(String name, String value,
      {bool numericReadback = false}) async {
    if (!_originalProperties.containsKey(name)) {
      final original = await player.getPropertyAsync(name);
      if (original.isEmpty) {
        throw StateError('Cannot capture original value of $name');
      }
      _originalProperties[name] = original;
    }
    _ownedProperties.add(name);
    await player.setPropertyStrict(name, value);
    final actual = await player.getPropertyAsync(name);
    final bool matches = actual == value ||
        (numericReadback &&
            double.tryParse(actual) != null &&
            double.tryParse(value) != null &&
            double.parse(actual) == double.parse(value));
    if (!matches) {
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
    // Plan C production-gap surfacing: a YUV window route the arm manager
    // cannot admit (no valid owner, capability or vendor device gate) fails
    // here — the earliest open phase — instead of surfacing only as a late
    // soft-decode mismatch at the review. Non-YUV routes never fail here.
    yuvWindowArm?.assertRouteAdmission(plan);
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

  Future<HdrOptionSourceIdentity> _readOptionIdentity() =>
      readHdrOptionSourceIdentity(
        player: player,
        fileLoadedEpoch: () => player.fileLoadedEpoch,
        readProperties: player.getPropertiesAsync,
      );

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
      readPlaylistFilename: () =>
          player.getPropertyAsync('playlist/0/filename'),
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
    if (_hasTransferredProbeDebt) {
      _nativeDvStopAttemptBefore = null;
      _promotionStoppedCapture =
          HdrNativeDvStoppedCapture(before: before, stopped: stopped);
      return;
    }
    _nativeDvStopAttemptBefore = null;
  }

  Future<void> _completeTransferredProbeStop() async {
    final capture = _promotionStoppedCapture;
    final plan = _promotedProbePlan;
    if (capture == null || plan == null || !_hasTransferredProbeDebt) return;
    // The native owner has already re-bound this exact stop to its empty
    // boundary. Restore its per-player pair before retiring the probe's
    // entry-local backup debt; either failure leaves the debt retryable.
    await player.lock.synchronized(_nativeDvOptions.restore);
    await _containerProbeOwner.retireAfterTransferredStop(
      lock: player.lock,
      capture: capture,
      readIdentity: _readOptionIdentity,
    );
    _completedPromotionStop = capture.stopped;
    _promotionStoppedCapture = null;
    _promotedProbeIdentity = null;
    _promotedProbePlan = null;
    _nativeDvStopAttemptBefore = null;
    _nativeDvPendingOpen = null;
    _nativeDvPendingOwnStopIssued = false;
  }

  Future<bool> _finishCapturedPromotionStop() async {
    final capture = _promotionStoppedCapture;
    if (capture != null) await _completeTransferredProbeStop();
    final stopped = _completedPromotionStop;
    if (stopped == null) return false;
    await player.lock.synchronized(() async {
      await _assertCompletedPromotionStopped();
      _stoppedBoundary = stopped;
      _observedStoppedPath = true;
    });
    return true;
  }

  /// The caller holds Player.lock, including when consuming the proof for a
  /// new managed open. Same-URI replacements are different entries/epochs.
  Future<void> _assertCompletedPromotionStopped() async {
    final stopped = _completedPromotionStop;
    if (stopped == null) return;
    if (await _readOptionIdentity() != stopped ||
        await _readOptionIdentity() != stopped) {
      throw StateError('Completed promotion stop lost its stopped boundary');
    }
  }

  Future<void> _admitOpenAfterCompletedPromotionStop(
      Future<void> Function() openWithoutLock) async {
    await _assertCompletedPromotionStopped();
    // The source ownership capture enclosing this callback now owns any
    // partially accepted loadfile, including an acknowledgement failure.
    _completedPromotionStop = null;
    await openWithoutLock();
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
      readPlaylistFilename: () =>
          player.getPropertyAsync('playlist/0/filename'),
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
    ++_ordinaryReviewSerial;
    _observedStoppedPath = false;
    _stoppedBoundary = null;
    // All possible FILE_LOADED waits happen before/after the critical section.
    if (await _finishCapturedPromotionStop()) return;
    await _recoverNativeDvPendingOpen();
    await _recoverNativeDvStopAttempt();
    if (await _finishCapturedPromotionStop()) return;
    if (_containerProbeOwner.active && !_hasTransferredProbeDebt) {
      _stoppedBoundary = await _containerProbeOwner.stopOwnedUnderLock(
        lock: player.lock,
        stopWithoutLock: () => player.stop(synchronized: false),
        readIdentity: _readOptionIdentity,
        readPlaylistFilename: () =>
            player.getPropertyAsync('playlist/0/filename'),
        waitForFileLoadedEntry: player.waitForFileLoadedEntryAfter,
      );
      // A promotion can fail before native ownership is acquired. Its first
      // probe stop may unload successfully but lose the acknowledgement; on
      // this confirmed retry retain the boundary before reset retires the
      // probe and attempts any remaining configuration restores.
      _completedPromotionStop = _stoppedBoundary;
    } else if (!_nativeDvOptions.active) {
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
      HdrOptionSourceIdentity confirmed;
      try {
        confirmed = await _confirmNativeDvOwnStop(captured.before);
        if (confirmed != captured.stopped) {
          throw StateError(
              'Native DV stopped proof changed before acknowledgement');
        }
        await rebindNativeDvUnderLock(
            lock: player.lock,
            options: _nativeDvOptions,
            before: captured.before,
            confirmed: confirmed);
      } catch (identityError) {
        throw HdrNativeDvOptionFailure(
            captured.operationError, {'sourceIdentity': identityError});
      }
      _stoppedBoundary = confirmed;
      if (_hasTransferredProbeDebt) {
        _nativeDvStopAttemptBefore = null;
        _promotionStoppedCapture = HdrNativeDvStoppedCapture(
          before: captured.before,
          stopped: confirmed,
          operationError: captured.operationError,
          operationStack: captured.operationStack,
        );
        await _completeTransferredProbeStop();
      } else {
        _nativeDvPendingOpen = null;
        _nativeDvPendingOwnStopIssued = false;
        _nativeDvStopAttemptBefore = null;
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
    if (_promotionStoppedCapture != null) {
      await _completeTransferredProbeStop();
    }
    if (_hasTransferredProbeDebt) {
      throw StateError(
          'Promoted container probe requires its owned stop before reset');
    }
    await player.lock.synchronized(() async {
      await _assertCompletedPromotionStopped();
      await _nativeDvOptions.restore();
    });
    _nativeDvPendingOpen = null;
    _nativeDvPendingOwnStopIssued = false;
    _nativeDvStopAttemptBefore = null;
    if (_containerProbeOwner.active && !_hasTransferredProbeDebt) {
      final stopped = _stoppedBoundary;
      if (!_observedStoppedPath || stopped == null) {
        throw StateError(
            'Container probe cleanup has no verified stopped boundary');
      }
      await _containerProbeOwner.retireAtStoppedBoundary(
        lock: player.lock,
        stoppedIdentity: stopped,
        readIdentity: _readOptionIdentity,
      );
    }
    Future<void> restoreRemaining() async {
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

    if (_completedPromotionStop != null) {
      await player.lock.synchronized(() async {
        await _assertCompletedPromotionStopped();
        await restoreRemaining();
        await _assertCompletedPromotionStopped();
      });
    } else {
      await restoreRemaining();
    }
  }

  @override
  Future<void> prepareOutput(HdrOpenPlan plan) async {
    final route = plan.route;
    await validate(plan);
    if (route.vdLavcOptions != null) {
      if (_containerProbeOwner.promotionTransferred(plan)) {
        final expected = _promotedProbeIdentity;
        if (!_nativeDvOptions.active ||
            expected == null ||
            _nativeDvOptions.identity != expected) {
          throw const HdrDecoderReviewFailure(
              'Container promotion lost native DV option ownership');
        }
        await player.lock.synchronized(() async {
          await _nativeDvOptions.assertCurrent();
          await _nativeDvOptions.verify();
          if (_nativeDvOptions.identity != expected) {
            throw const HdrDecoderReviewFailure(
                'Container promotion source changed before output setup');
          }
        });
      } else {
        final stopped = _stoppedBoundary;
        if (!_observedStoppedPath || stopped == null) {
          throw StateError(
              'No stopped-media boundary before native DV options');
        }
        await beginNativeDvUnderLock(
            lock: player.lock,
            options: _nativeDvOptions,
            stoppedIdentity: stopped,
            vd: route.vdLavcOptions!,
            renderMode: route.mediacodecEmbedRenderMode!);
      }
    }
    final contract = HdrOutputContract.fromRoute(
      route,
      surfacePixelFormatOverride: surfacePixelFormatOverride,
    );
    final eglOutputFormat = contract.eglOutputFormat;
    if (eglOutputFormat != null) {
      await _setOwned('egl-output-format', eglOutputFormat);
    }
    // The Android video controller applies its creation-time hwdec setting
    // while it initializes. Capture and register ownership before ensure()
    // can construct that controller, or its initialization may overwrite the
    // value that resetOwnedConfiguration is meant to restore.
    await _setOwned('hwdec', contract.requestedHwdec);
    // Managed sessions keep mpv's bounded software fallback armed: after 8
    // consecutive failed hardware frames (a successful frame resets the
    // count) the next decoder init falls back to software.
    // Owned like `hwdec` (same placement: before output creation and before
    // the media open) so resetOwnedConfiguration restores the captured
    // original; a rejected write or readback fails preparation fail-closed.
    await _setOwned('hwdec-software-fallback', '8');
    // Plan C arm point + process admission (V2 B1 round 3): the guarded
    // initialization admits at process level BEFORE the slot's ensure —
    // hence before the previous output's retirement, so a rejected
    // initializer performs no teardown at all — and the arm runs as the
    // slot's internal preparation hook after that retirement and strictly
    // before the new output's creation triggers VO initialization. The
    // admission's protection spans the initialization's REAL tail: read
    // admissions to the texture layout rebuild's completion below (the
    // platformView topology's tail is the bind completion inside ensure —
    // output binding is what triggers its VO initialization); the YUV write
    // admission to the attempt's terminal cleanup.
    final arm = yuvWindowArm;
    Future<void> initialize() async {
      await outputSlot.ensure(
        contract,
        internalPrepare: arm == null
            ? null
            : (_) => managedYuvCarrier
                ? arm.prepareManagedAttempt(plan)
                : arm.armForAttempt(plan),
      );
      if (route.topology != HdrTopology.platformView &&
          route.vo == 'gpu-next') {
        // The TEXTURE topology's initialization tail: the layout-bound
        // rebuild (SetSurfaceSize + VO re-apply) runs INSIDE the admission's
        // protection interval — after the read release it would again race a
        // concurrent YUV arm.
        final prepared =
            await outputSlot.current!.prepareAndroidTextureOutput();
        debugPrint(prepared
            ? 'HDR_TEXTURE_PREPARED layoutBound=true'
            : 'HDR_TEXTURE_PREPARED fallback=surface_or_layout_unavailable');
      }
    }

    if (arm == null) {
      await initialize();
    } else {
      await arm.initializeOutput(plan, initialize);
    }
  }

  @override
  Future<void> configure(HdrOpenPlan plan) async {
    _dataSpaceRequested = null;
    _dataSpacePath = null;
    _dataSpaceReadback = null;
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
      await _setOwned('video-output-levels',
          HdrYuvPresentationContract.mpvOutputLevels(route.offscreenTransfer!));
      // The offscreen contract is PQ: without target-trc mpv renders the
      // source HLG values unconverted, which the PQ-tagged window (and the
      // panel) then interpret as absolute PQ luminance — bright areas
      // roughly double overexposed. Applying the HLG->PQ conversion here.
      await _setOwned('target-trc', 'pq');
      // Pin the destination peak used by HLG conversion instead of resolving
      // it from the PQ container's nominal peak. This is a rendering target;
      // it does not assert the source mastering peak or measured panel nits.
      await _setOwned('target-peak', HdrYuvPresentationContract.targetPeak);
      final ext = plan.capabilities.dataSpaceExt;
      final bool supportsLgYuvPq = ext != null &&
          ext.id == 'lg-pq' &&
          ext.applicable &&
          ext.pqPresentation?.yuvWindow == true &&
          ext.setterOnlyTransfers.contains(route.surfaceTransfer);
      if (plan.source.transfer == 'hlg' &&
          route.strategy == HdrStrategy.baseLayerConvert &&
          supportsLgYuvPq) {
        // A small midtone lift for the validated LG HLG-to-PQ route. The
        // neutral gamma is the only value this presentation adjustment owns;
        // a caller's non-neutral gamma remains intact.
        if (!_ownedProperties.contains('gamma')) {
          final String originalGamma = await player.getPropertyAsync('gamma');
          if (originalGamma.isEmpty) {
            throw StateError('Cannot capture original value of gamma');
          }
          // Gamma can be user-adjusted between HDR sessions. Unlike the
          // generic cache retained for other route properties, recapture it
          // whenever this presentation does not currently own the value.
          _originalProperties['gamma'] = originalGamma;
        }
        final String originalGamma = _originalProperties['gamma']!;
        if (double.tryParse(originalGamma) == 0) {
          await _setOwned('gamma', '3', numericReadback: true);
        }
      }
    }
    if (route.topology == HdrTopology.platformView) {
      final output = await outputSlot.current!.platform.future;
      await HdrOutputBindTimeout.waitFor(
        output.waitUntilCurrentOutputBound.timeout(const Duration(seconds: 10)),
      );
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
        // Only an extension that self-reports the setter-only exception for
        // this exact transfer may accept a setter without readback. This is
        // not verified presentation evidence.
        final bool acceptedWithoutReadback = acceptsUnverifiedExtSetter(
            plan.capabilities,
            transfer,
            result?['applied'] == true,
            _dataSpacePath,
            _dataSpaceReadback);
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
      final actual = await player.getPropertyAsync('vf');
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

  /// The limited acceptance of a setter that succeeded without a readback:
  /// every condition is a capability judgment, never a device-name
  /// judgment. ALL of these must hold —
  ///
  /// 1. a registered extension that is applicable;
  /// 2. the requested transfer explicitly declared in the extension's
  ///    `setterOnlyTransfers` (an undeclared transfer never qualifies);
  /// 3. the actual apply succeeded ([applied], already gated by the caller
  ///    before this check);
  /// 4. the actual apply path belongs to the currently registered extension
  ///    (`ext:<id>` — a same-provider identity association only, never a
  ///    device-behavior choice);
  /// 5. the readback is genuinely missing (null/empty/`none`), not present
  ///    with a wrong value — a present-but-wrong readback goes through the
  ///    mismatch gate instead.
  ///
  /// This is not verified presentation evidence.
  static bool acceptsUnverifiedExtSetter(HdrCapabilities capabilities,
      String transfer, bool applied, String? path, String? readback) {
    final HdrDataSpaceExtInfo? ext = capabilities.dataSpaceExt;
    if (ext == null || !ext.applicable || !applied) return false;
    if (!ext.setterOnlyTransfers.contains(transfer)) return false;
    if (path != 'ext:${ext.id}') return false;
    return readback == null || readback.isEmpty || readback == 'none';
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
    final media = plan.media;
    final playable = start == null && media.start == null
        ? media
        : Media(media.uri,
            start: start ?? media.start,
            end: media.end,
            extras: media.extras,
            httpHeaders: media.httpHeaders);
    _observedStoppedPath = false;
    _stoppedBoundary = null;
    final reviewSerial = ++_ordinaryReviewSerial;
    _ordinaryReviewClock = null;
    // Drop the previous media's cached video-params so the review waits for
    // this open's report instead of classifying from a stale source.
    _latestVideoParams = null;
    _openFileLoadedEpoch = player.fileLoadedEpoch;
    _openPlaylistEntryId = null;
    await _nativeDvOptions.assertCurrent();
    final optionIdentity = _nativeDvOptions.identity;
    var identityConfirmationAttempted = false;
    try {
      if (optionIdentity != null) {
        final captured = await captureNativeDvOpenUnderLock(
          lock: player.lock,
          options: _nativeDvOptions,
          mediaUri: media.uri,
          openWithoutLock: () => _admitOpenAfterCompletedPromotionStop(
              () => player.open(playable, play: play, synchronized: false)),
          readProperty: player.getPropertyAsync,
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
          readPlaylistFilename: () =>
              player.getPropertyAsync('playlist/0/filename'),
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
        bool current() =>
            _ordinaryReviewSerial == reviewSerial && reviewIsCurrent(plan);
        final entry = _containerProbeOwner.owns(plan)
            ? await _containerProbeOwner.captureOpenUnderLock(
                lock: player.lock,
                plan: plan,
                start: playable.start,
                isCurrent: current,
                openWithoutLock: (probe) =>
                    _admitOpenAfterCompletedPromotionStop(() async {
                  if (_startupTrace) {
                    debugPrint('MK_STARTUP containerProbe=$probe');
                  }
                  if (probe) {
                    await player.openContainerProbe(playable,
                        automaticSubtitles:
                            _containerProbeOwner.automaticSubtitlesFor(plan),
                        synchronized: false);
                  } else {
                    await player.open(playable,
                        play: play, synchronized: false);
                  }
                }),
                readIdentity: _readOptionIdentity,
                readProperties: player.getPropertiesAsync,
              )
            : await captureDecoderOpenUnderLock(
                lock: player.lock,
                mediaUri: media.uri,
                fileLoadedEpoch: () => player.fileLoadedEpoch,
                openWithoutLock: () => _admitOpenAfterCompletedPromotionStop(
                    () =>
                        player.open(playable, play: play, synchronized: false)),
                readProperty: player.getPropertyAsync,
                isCurrent: current,
              );
        if (_ordinaryReviewSerial != reviewSerial || !reviewIsCurrent(plan)) {
          throw const HdrDecoderReviewFailure('Superseded ordinary open');
        }
        _openFileLoadedEpoch = entry.openedAfterEpoch;
        _openPlaylistEntryId = entry.playlistEntryId;
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
  Future<void> prepareSourceDiscovery(HdrOpenPlan plan) async {
    void trace(bool prepared) {
      if (_startupTrace) {
        debugPrint('MK_STARTUP containerProbeIntent=$prepared');
      }
    }

    final currentOutput = outputSlot.current;
    if (currentOutput == null) {
      trace(false);
      return;
    }
    final route = plan.route;
    final eligiblePlan = plan.sourceOrigin == null &&
        plan.source == const HdrSourceDescriptor() &&
        plan.route.strategy == HdrStrategy.sdrDirect &&
        route.topology == HdrTopology.texture &&
        route.vo == 'gpu-next' &&
        plan.options?.failurePolicy != VideoRouteFailurePolicy.stop;
    if (!eligiblePlan || !reviewIsCurrent(plan)) {
      trace(false);
      return;
    }
    // LegacyMediaOptions permits lavfi-complex as a per-entry loadfile
    // override. A global-property check below cannot prove that such a
    // custom graph is absent, so keep the ordinary open path for it.
    if (plan.media.extras?.containsKey('lavfi-complex') ?? false) {
      trace(false);
      return;
    }
    final output = await currentOutput.platform.future;
    final configuration = output.configuration;
    final eligibleOutput = configuration.vo == 'gpu-next' &&
        !configuration.android.usePlatformView;
    if (!eligibleOutput || !reviewIsCurrent(plan)) {
      trace(false);
      return;
    }
    final stopped = _stoppedBoundary;
    if (!_observedStoppedPath || stopped == null) {
      trace(false);
      return;
    }
    final prepared = await _containerProbeOwner.prepare(
      lock: player.lock,
      plan: plan,
      uri: plan.media.uri,
      eligibleRoute: true,
      isCurrent: () => reviewIsCurrent(plan),
      stoppedIdentity: stopped,
      readIdentity: _readOptionIdentity,
      readProperties: player.getPropertiesAsync,
    );
    trace(prepared);
  }

  @override
  Future<void> resumeSourceDiscovery(HdrOpenPlan plan) async {
    if (!_containerProbeOwner.owns(plan)) return;
    final openedAfterEpoch = _openFileLoadedEpoch;
    final entryId = _openPlaylistEntryId;
    if (openedAfterEpoch == null || entryId == null) {
      throw const HdrDecoderReviewFailure(
          'Container probe has no opened playlist identity');
    }
    final serial = _ordinaryReviewSerial;
    await _containerProbeOwner.resume(
      lock: player.lock,
      plan: plan,
      isCurrent: () => _ordinaryReviewSerial == serial && reviewIsCurrent(plan),
      fileLoadedEpoch: () => player.fileLoadedEpoch,
      readProperties: player.getPropertiesAsync,
      writeProperty: player.setPropertyStrict,
      expectedEntryId: entryId,
      openedAfterEpoch: openedAfterEpoch,
      mediaUri: plan.media.uri,
    );
    if (_startupTrace) debugPrint('MK_STARTUP containerProbeResumed=true');
  }

  @override
  Future<void> promoteDiscoveredSource(
    HdrOpenPlan previous,
    HdrOpenPlan next, {
    Duration? start,
  }) =>
      player.runSourceTransition(() async {
        try {
          await _promoteDiscoveredSource(previous, next, start: start);
        } catch (error, stack) {
          // Source admission stays closed through every fallible output
          // operation and its owned cleanup. Surface callbacks can still use
          // Player.lock (not this gate), so binding does not deadlock.
          try {
            await stop();
            final stopped = _stoppedBoundary;
            if (stopped != null &&
                stopped.path.isEmpty &&
                stopped.playlistEntryId.isEmpty) {
              // This also covers rejection before the native owner acquired
              // the entry: the original probe's stop proof must survive its
              // retirement and the coordinator's later rollback retry.
              _completedPromotionStop ??= stopped;
            }
            await resetOwnedConfiguration();
          } catch (cleanupError) {
            throw HdrNativeDvOptionFailure(
                error, {'promotionCleanup': cleanupError});
          }
          Error.throwWithStackTrace(error, stack);
        }
      });

  Future<void> _promoteDiscoveredSource(
    HdrOpenPlan previous,
    HdrOpenPlan next, {
    Duration? start,
  }) async {
    if (!await canPromoteDiscoveredSource(previous, next)) {
      throw const HdrDecoderReviewFailure(
          'Container source is not eligible for same-entry promotion');
    }
    final serial = _ordinaryReviewSerial;
    bool isCurrent() =>
        _ordinaryReviewSerial == serial && reviewIsCurrent(next);

    final promoted = await _containerProbeOwner.beginPromotionUnderLock(
      lock: player.lock,
      oldPlan: previous,
      newPlan: next,
      expectedStart: start ?? previous.media.start,
      isCurrent: isCurrent,
      fileLoadedEpoch: () => player.fileLoadedEpoch,
      readProperties: player.getPropertiesAsync,
      writeProperty: player.setPropertyStrict,
      readIdentity: _readOptionIdentity,
      nativeOwnershipAcquired: (identity) =>
          _nativeDvOptions.identity == identity,
      takeNativeOwnership: (identity, originalVd, originalRenderMode,
          verifyDecoderlessProbe) async {
        // The probe owner records the transfer only after it observes that
        // the native option owner has acquired this exact source. If native
        // begin rejects before taking identity, the probe remains the sole
        // source-stop owner.
        _promotedProbePlan = next;
        _promotedProbeIdentity = identity;
        try {
          await _nativeDvOptions.beginFromDecoderlessProbe(
            entryIdentity: identity,
            originalVd: originalVd,
            originalRenderMode: originalRenderMode,
            verifyDecoderlessProbe: verifyDecoderlessProbe,
            vd: next.route.vdLavcOptions!,
            renderMode: next.route.mediacodecEmbedRenderMode!,
          );
        } catch (_) {
          if (_nativeDvOptions.identity != identity) {
            _promotedProbePlan = null;
            _promotedProbeIdentity = null;
          }
          rethrow;
        }
      },
    );
    if (promoted != _promotedProbeIdentity || !isCurrent()) {
      throw const HdrDecoderReviewFailure(
          'Promoted source ownership changed before output setup');
    }

    // No loadfile and no new epoch: the exact paused demuxer survives while
    // this route replaces the texture output with its native DV PlatformView.
    await prepareOutput(next);
    await configure(next);
    await waitForOutput(next);

    final output = outputSlot.current;
    final controller = output?.notifier.value;
    if (controller is! AndroidVideoController ||
        !identical(controller.player, player) ||
        controller.configuration.vo != next.route.vo ||
        !controller.configuration.android.usePlatformView) {
      throw const HdrDecoderReviewFailure(
          'Promoted native DV PlatformView is not owned and ready');
    }
    final boundIdentity = controller.currentBoundOutputIdentity;
    if (boundIdentity == null) {
      throw const HdrDecoderReviewFailure(
          'Promoted native DV PlatformView has no bound output');
    }

    Future<void> verifyBoundVideo() async {
      if (!isCurrent() ||
          !_containerProbeOwner.promotionTransferred(next) ||
          !identical(outputSlot.current, output) ||
          !identical(output?.notifier.value, controller) ||
          !identical(controller.player, player) ||
          controller.configuration.vo != next.route.vo ||
          !controller.configuration.android.usePlatformView ||
          controller.currentBoundOutputIdentity != boundIdentity ||
          _nativeDvOptions.identity != promoted) {
        throw const HdrDecoderReviewFailure(
            'Promoted native DV output or source ownership changed');
      }
      await _nativeDvOptions.assertCurrent();
      await _nativeDvOptions.verify();
      if (!isCurrent() ||
          !identical(outputSlot.current, output) ||
          !identical(output?.notifier.value, controller) ||
          controller.currentBoundOutputIdentity != boundIdentity ||
          _nativeDvOptions.identity != promoted) {
        throw const HdrDecoderReviewFailure(
            'Promoted native DV output changed during selector restore');
      }
    }

    final openedAfterEpoch = _openFileLoadedEpoch;
    final entryId = _openPlaylistEntryId;
    if (openedAfterEpoch == null || entryId == null) {
      throw const HdrDecoderReviewFailure(
          'Promoted probe lost its original file-loaded identity');
    }
    await _containerProbeOwner.resumePromotion(
      lock: player.lock,
      plan: next,
      isCurrent: isCurrent,
      fileLoadedEpoch: () => player.fileLoadedEpoch,
      readProperties: player.getPropertiesAsync,
      writeProperty: player.setPropertyStrict,
      expectedEntryId: entryId,
      openedAfterEpoch: openedAfterEpoch,
      mediaUri: next.media.uri,
      verifyBoundVideo: verifyBoundVideo,
    );
  }

  @override
  Future<HdrContainerSourceSnapshot?> discoverSource(HdrOpenPlan plan) async {
    final before = _openFileLoadedEpoch;
    final entry = _openPlaylistEntryId;
    if (before == null || entry == null) {
      throw StateError('No playlist-entry identity before discovery');
    }
    _ordinaryReviewClock ??= Stopwatch()..start();
    final probe = _containerProbeOwner.probing(plan);
    final serial = _ordinaryReviewSerial;
    return gatherContainerSourceSnapshot(
      lock: player.lock,
      mediaUri: plan.media.uri,
      playlistEntryId: entry,
      openedAfterEpoch: before,
      fileLoadedEpoch: () => player.fileLoadedEpoch,
      isCurrent: () => _ordinaryReviewSerial == serial && reviewIsCurrent(plan),
      readProperties: player.getPropertiesAsync,
      waitForFileLoadedEntry: player.waitForFileLoadedEntryAfter,
      budget: const Duration(seconds: 20) - _ordinaryReviewClock!.elapsed,
      unselectedProbe: probe,
      verifyUnselectedProbe: probe
          ? () => _containerProbeOwner.verifyInLock(
                plan: plan,
                isCurrent: () =>
                    _ordinaryReviewSerial == serial && reviewIsCurrent(plan),
                fileLoadedEpoch: () => player.fileLoadedEpoch,
                readProperties: player.getPropertiesAsync,
                mediaUri: plan.media.uri,
                playlistEntryId: entry,
                openedAfterEpoch: before,
              )
          : null,
    );
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
        readProperty: player.getPropertyAsync,
        readProperties: player.getPropertiesAsync,
        latestVideoParams: () => _latestVideoParams,
      );
      _lastHwdecCurrent = facts.hwdecCurrent;
      return facts;
    }
    final reviewSerial = _ordinaryReviewSerial;
    final facts = await gatherDecoderReviewFacts(
      lock: player.lock,
      mediaUri: plan.media.uri,
      readProperty: player.getPropertyAsync,
      readProperties: player.getPropertiesAsync,
      waitForFileLoadedEntry: player.waitForFileLoadedEntryAfter,
      playlistEntryId: entryId,
      openedAfterEpoch: before,
      fileLoadedEpoch: () => player.fileLoadedEpoch,
      isCurrent: () =>
          _ordinaryReviewSerial == reviewSerial && reviewIsCurrent(plan),
      budget: const Duration(seconds: 20) -
          (_ordinaryReviewClock?.elapsed ?? Duration.zero),
    );
    if (_ordinaryReviewSerial != reviewSerial || !reviewIsCurrent(plan)) {
      throw const HdrDecoderReviewFailure('Superseded decoder result');
    }
    _lastHwdecCurrent = facts.hwdecCurrent;
    return facts;
  }

  /// Gathers the decoder facts after the open's file-loaded boundary (plan
  /// 1.4 step 8). Static with injected readers so VM tests can drive the
  /// polling without a native Player. This legacy test seam is not the
  /// production [reviewFacts] path; ordinary production review uses
  /// [gatherDecoderReviewFacts] and current scalar source/frame evidence.
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
    final hdr10PlusRaw = await readProperty('video-params/hdr10-plus');
    final hdr10Plus = hdr10PlusRaw == 'yes'
        ? true
        : hdr10PlusRaw == 'no'
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
      hdr10Plus: hdr10Plus,
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
    ++_ordinaryReviewSerial;
    await _videoParamsSubscription?.cancel();
    _videoParamsSubscription = null;
  }
}
