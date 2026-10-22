import 'package:flutter/foundation.dart' show debugPrint;
import 'package:media_kit/media_kit.dart' show FileLoadedRecord;
import 'package:synchronized/synchronized.dart';

import 'hdr_decoder_review.dart';
import 'hdr_native_dv_option_owner.dart'
    show
        HdrOptionSourceIdentity,
        HdrNativeDvPendingOpen,
        HdrNativeDvStoppedCapture;

const hdrContainerProbeSelectorProperties = <String>[
  'options/vid',
  'options/aid',
  'options/sid',
  'options/secondary-sid',
];

const _probeProperties = <String>[
  'options/track-auto-selection',
  'options/lavfi-complex',
  'options/demuxer-cache-wait',
  'options/rebase-start-time',
  'options/play-dir',
  ...hdrContainerProbeSelectorProperties,
  'vd-lavc-o',
  'mediacodec-embed-render-mode',
  'mediakit-container-probe-seek-ready',
];

class _HdrContainerProbeLease {
  _HdrContainerProbeLease({
    required this.plan,
    required this.uri,
    required this.stoppedIdentity,
    required this.trackAutoSelection,
    required this.selectors,
    required this.nativeBaseline,
    required this.promotionSeekSupported,
  });

  Object plan;
  final String uri;
  final HdrOptionSourceIdentity stoppedIdentity;
  final String trackAutoSelection;
  final List<String> selectors;
  final List<String> nativeBaseline;
  final bool promotionSeekSupported;
  Duration? start;
  _HdrContainerProbeLeaseState state =
      _HdrContainerProbeLeaseState.armedStopped;
  int? openedAfterEpoch;
  int? playlistEntryId;
  bool resumed = false;
  HdrNativeDvPendingOpen? openedEntry;
  bool ownStopIssued = false;
  HdrOptionSourceIdentity? ownedStoppedIdentity;
  HdrOptionSourceIdentity? promotionIdentity;
  bool promotionStartArmed = false;
}

enum _HdrContainerProbeLeaseState {
  armedStopped,
  pendingOwnEntry,
  confirmedEntryEpoch,
}

/// Owns the temporary no-track-selection window used for container probing.
/// It never adopts a loaded source and is keyed to one plan and FILE_LOADED.
class HdrContainerProbeOwner {
  _HdrContainerProbeLease? _lease;

  bool get active => _lease != null;
  bool owns(Object plan) => identical(_lease?.plan, plan);
  bool probing(Object plan) => owns(plan) && !_lease!.resumed;
  bool promotionTransferred(Object plan) =>
      owns(plan) && _lease!.promotionIdentity != null;
  bool canPromote(Object plan) {
    final lease = _lease;
    return lease != null &&
        identical(lease.plan, plan) &&
        lease.state == _HdrContainerProbeLeaseState.confirmedEntryEpoch &&
        !lease.resumed &&
        lease.promotionSeekSupported &&
        lease.promotionIdentity == null &&
        lease.nativeBaseline[0].isEmpty &&
        const ['boolean', 'timed'].contains(lease.nativeBaseline[1]);
  }

  bool automaticSubtitlesFor(Object plan) {
    final lease = _lease;
    if (lease == null || !identical(lease.plan, plan)) {
      throw const HdrDecoderReviewFailure(
          'Container probe lost its subtitle selection intent');
    }
    return lease.selectors[2] == 'auto';
  }

  void markPendingOwnEntry(Object plan) {
    final lease = _lease;
    if (lease == null || !identical(lease.plan, plan)) return;
    if (lease.state != _HdrContainerProbeLeaseState.armedStopped) {
      throw const HdrDecoderReviewFailure(
          'Container probe open was already admitted');
    }
    lease
      ..ownedStoppedIdentity = null
      ..ownStopIssued = false
      ..state = _HdrContainerProbeLeaseState.pendingOwnEntry;
  }

  /// Records a read-only intent. The native loadfile operation, not this
  /// method, owns the eventual per-entry option backups.
  Future<bool> prepare({
    required Lock lock,
    required Object plan,
    required String uri,
    required bool eligibleRoute,
    required bool Function() isCurrent,
    required HdrOptionSourceIdentity stoppedIdentity,
    required Future<HdrOptionSourceIdentity> Function() readIdentity,
    required Future<List<String>> Function(List<String>) readProperties,
  }) =>
      lock.synchronized(() async {
        if (!eligibleRoute || !isCurrent()) return false;
        if (_lease != null) {
          throw StateError('Container probe ownership is still active');
        }
        final identity = await readIdentity();
        if (identity != stoppedIdentity ||
            stoppedIdentity.path.isNotEmpty ||
            stoppedIdentity.playlistEntryId.isNotEmpty) {
          return false;
        }
        final properties = await readProperties(_probeProperties);
        if (properties.length != _probeProperties.length ||
            !isCurrent() ||
            await readIdentity() != stoppedIdentity) {
          return false;
        }
        if (!_eligibleOptions(properties)) {
          _traceIneligibleOptions('prepare', properties);
          return false;
        }
        _lease = _HdrContainerProbeLease(
          plan: plan,
          uri: uri,
          stoppedIdentity: stoppedIdentity,
          trackAutoSelection: properties[0],
          selectors: properties.sublist(5, 9),
          nativeBaseline: properties.sublist(9, 11),
          promotionSeekSupported: const ['yes', 'no'].contains(properties[11]),
        );
        return true;
      });

  static bool _eligibleOptions(List<String> properties) =>
      properties.length == _probeProperties.length &&
      properties[0] == 'yes' &&
      properties[1].isEmpty &&
      properties[2] == 'no' &&
      properties[3] == 'yes' &&
      properties[4] == 'forward' &&
      properties[5] == 'auto' &&
      properties[6] == 'auto' &&
      (properties[7] == 'auto' || properties[7] == 'no') &&
      properties[8] == 'no' &&
      const ['yes', 'no'].contains(properties[11]);

  static void _traceIneligibleOptions(String stage, List<String> properties) {
    if (!const bool.fromEnvironment('MEDIA_KIT_STARTUP_TRACE')) return;
    String value(int index, Set<String> choices) =>
        index < properties.length && choices.contains(properties[index])
            ? properties[index]
            : 'unavailable';
    String selector(int index) {
      if (index >= properties.length) return 'unavailable';
      final raw = properties[index];
      return raw == 'auto' || raw == 'no' || int.tryParse(raw) != null
          ? raw
          : 'unavailable';
    }

    debugPrint('MK_STARTUP containerProbeEligibility=$stage '
        'flag=${value(0, const {'yes', 'no'})} '
        'rebase=${value(3, const {'yes', 'no'})} '
        'dir=${value(4, const {'forward', 'backward'})} '
        'cacheWait=${value(2, const {'yes', 'no'})} '
        'lavfiEmpty=${properties.length > 1 && properties[1].isEmpty} '
        'selectors=${[for (var i = 5; i < 9; i++) selector(i)].join(',')}');
  }

  void bindOpenedEntry({
    required Object plan,
    required int openedAfterEpoch,
    required int playlistEntryId,
    required Duration? start,
  }) {
    final lease = _lease;
    if (lease == null || !identical(lease.plan, plan)) return;
    if (lease.state != _HdrContainerProbeLeaseState.pendingOwnEntry ||
        openedAfterEpoch != lease.stoppedIdentity.fileLoadedEpoch) {
      throw const HdrDecoderReviewFailure(
          'Container probe did not own the opened entry');
    }
    lease
      ..openedAfterEpoch = openedAfterEpoch
      ..playlistEntryId = playlistEntryId
      ..start = start
      ..openedEntry = HdrNativeDvPendingOpen(
          before: lease.stoppedIdentity,
          mediaUri: lease.uri,
          playlistEntryId: playlistEntryId)
      ..state = _HdrContainerProbeLeaseState.confirmedEntryEpoch;
  }

  /// Capture an admitted open's result before releasing the same lock used by
  /// public Player.open. Even cancellation/acknowledgement failures must not
  /// discard its entry proof and later adopt a same-URI external entry.
  Future<HdrDecoderOpenedEntry> captureOpenUnderLock({
    required Lock lock,
    required Object plan,
    required Duration? start,
    required bool Function() isCurrent,
    required Future<void> Function(bool probe) openWithoutLock,
    required Future<HdrOptionSourceIdentity> Function() readIdentity,
    required Future<List<String>> Function(List<String>) readProperties,
  }) =>
      lock.synchronized(() async {
        final lease = _lease;
        if (lease == null ||
            !identical(lease.plan, plan) ||
            !isCurrent() ||
            await readIdentity() != lease.stoppedIdentity) {
          throw const HdrDecoderReviewFailure(
              'Container probe lost its stopped admission boundary');
        }
        final properties = await readProperties(_probeProperties);
        if (!isCurrent() || await readIdentity() != lease.stoppedIdentity) {
          throw const HdrDecoderReviewFailure(
              'Container probe admission changed');
        }
        final optionsEligible = _eligibleOptions(properties) &&
            _sameSelectors(properties.sublist(5, 9), lease.selectors);
        if (!optionsEligible) _traceIneligibleOptions('admission', properties);
        final probe = start?.isNegative != true && optionsEligible;
        if (!probe) _lease = null; // Read-only intent; nothing needs restoring.
        if (probe) markPendingOwnEntry(plan);
        Object? operationError;
        StackTrace? operationStack;
        try {
          await openWithoutLock(probe);
        } catch (error, stack) {
          operationError = error;
          operationStack = stack;
        }
        if (!probe && operationError != null) {
          Error.throwWithStackTrace(operationError, operationStack!);
        }
        final current = await readIdentity();
        final entryValues = await readProperties(const [
          'playlist/0/filename',
          'playlist/0/id',
          'playlist/0/filename',
          'playlist/0/id',
        ]);
        if (await readIdentity() != current || entryValues.length != 4) {
          throw const HdrDecoderReviewFailure(
              'Container probe admitted open could not be captured');
        }
        if (probe &&
            current == lease.stoppedIdentity &&
            entryValues.every((value) => value.isEmpty)) {
          // A failed command did not change the original stopped boundary.
          // This proof is captured here, not reconstructed during cleanup.
          lease
            ..state = _HdrContainerProbeLeaseState.armedStopped
            ..ownedStoppedIdentity = current;
          if (operationError != null) {
            Error.throwWithStackTrace(operationError, operationStack!);
          }
          throw const HdrDecoderReviewFailure(
              'Container probe open did not submit an entry');
        }
        final id = int.tryParse(entryValues[1]);
        if (!identical(current.player, lease.stoppedIdentity.player) ||
            id == null ||
            id < 0 ||
            current.playlistEntryId != id.toString() ||
            (current.path.isNotEmpty && current.path != lease.uri) ||
            entryValues[0] != lease.uri ||
            entryValues[2] != entryValues[0] ||
            entryValues[3] != entryValues[1] ||
            current.fileLoadedEpoch < lease.stoppedIdentity.fileLoadedEpoch ||
            current.fileLoadedEpoch >
                lease.stoppedIdentity.fileLoadedEpoch + 1) {
          throw const HdrDecoderReviewFailure(
              'Container probe admitted entry differs from its open');
        }
        if (probe) {
          bindOpenedEntry(
            plan: plan,
            openedAfterEpoch: lease.stoppedIdentity.fileLoadedEpoch,
            playlistEntryId: id,
            start: start,
          );
        }
        if (operationError != null) {
          Error.throwWithStackTrace(operationError, operationStack!);
        }
        if (!isCurrent()) {
          throw const HdrDecoderReviewFailure(
              'Superseded container probe open');
        }
        return HdrDecoderOpenedEntry(lease.stoppedIdentity.fileLoadedEpoch, id);
      });

  /// Transfers this exact decoderless entry to the native option owner while
  /// retaining the probe's native file-backup debt until its owned stop.
  Future<HdrOptionSourceIdentity> beginPromotionUnderLock({
    required Lock lock,
    required Object oldPlan,
    required Object newPlan,
    required Duration? expectedStart,
    required bool Function() isCurrent,
    required int Function() fileLoadedEpoch,
    required Future<List<String>> Function(List<String>) readProperties,
    required Future<void> Function(String, String) writeProperty,
    required Future<HdrOptionSourceIdentity> Function() readIdentity,
    required bool Function(HdrOptionSourceIdentity identity)
        nativeOwnershipAcquired,
    required Future<void> Function(
      HdrOptionSourceIdentity identity,
      String originalVd,
      String originalRenderMode,
      Future<void> Function() verifyDecoderlessProbe,
    ) takeNativeOwnership,
  }) =>
      lock.synchronized(() async {
        final lease = _lease;
        if (lease == null ||
            !canPromote(oldPlan) ||
            lease.start != expectedStart ||
            lease.start?.isNegative == true) {
          throw const HdrDecoderReviewFailure(
              'Container probe cannot promote this plan');
        }
        final entryId = lease.playlistEntryId!;
        final after = lease.openedAfterEpoch!;
        Future<void> verifyDecoderlessProbe() async {
          if (!identical(_lease, lease)) {
            throw const HdrDecoderReviewFailure(
                'Probe promotion lost its lease');
          }
          await _assertEntryAndOptions(
              isCurrent: isCurrent,
              fileLoadedEpoch: fileLoadedEpoch,
              readProperties: readProperties,
              mediaUri: lease.uri,
              entryId: entryId,
              openedAfterEpoch: after,
              expectedFlag: 'no',
              expectedSelectors: lease.selectors);
          await _verifyDecoderlessTracks(readProperties);
          await _assertEntryAndOptions(
              isCurrent: isCurrent,
              fileLoadedEpoch: fileLoadedEpoch,
              readProperties: readProperties,
              mediaUri: lease.uri,
              entryId: entryId,
              openedAfterEpoch: after,
              expectedFlag: 'no',
              expectedSelectors: lease.selectors);
        }

        await verifyDecoderlessProbe();
        final pairAndCapability = await readProperties(const [
          'vd-lavc-o',
          'mediacodec-embed-render-mode',
          'mediakit-container-probe-seek-ready',
        ]);
        await verifyDecoderlessProbe();
        if (pairAndCapability.length != 3 ||
            !const ['yes', 'no'].contains(pairAndCapability[2]) ||
            !_sameSelectors(
                pairAndCapability.take(2).toList(), lease.nativeBaseline)) {
          throw const HdrDecoderReviewFailure(
              'Container probe native option baseline changed');
        }
        final identity = await readIdentity();
        if (!identical(identity.player, lease.stoppedIdentity.player) ||
            identity.path != lease.uri ||
            identity.playlistEntryId != entryId.toString() ||
            identity.fileLoadedEpoch != after + 1) {
          throw const HdrDecoderReviewFailure(
              'Container probe promotion source changed');
        }
        // An argument/busy rejection can happen before native ownership. Do
        // not strand the probe without a stop owner in that case. Once the
        // native owner acquires this identity it retains it on every failure.
        try {
          await takeNativeOwnership(identity, lease.nativeBaseline[0],
              lease.nativeBaseline[1], verifyDecoderlessProbe);
        } finally {
          if (nativeOwnershipAcquired(identity)) {
            lease
              ..plan = newPlan
              ..promotionIdentity = identity;
          }
        }
        if (lease.promotionIdentity != identity) {
          throw const HdrDecoderReviewFailure(
              'Native owner did not acquire the promoted probe entry');
        }
        await verifyDecoderlessProbe();
        Future<void> verifyPromotedDecoderless() async {
          await verifyDecoderlessProbe();
          if (lease.promotionIdentity != identity ||
              !nativeOwnershipAcquired(identity) ||
              await readIdentity() != identity) {
            throw const HdrDecoderReviewFailure(
                'Promoted probe lost native ownership before arming start');
          }
          await verifyDecoderlessProbe();
        }

        await _armRawStartBeforeDecoding(
          start: lease.start,
          readProperties: readProperties,
          writeProperty: writeProperty,
          verifyDecoderless: verifyPromotedDecoderless,
        );
        lease.promotionStartArmed = true;
        return identity;
      });

  /// The native owner is the sole stop owner after handoff. The backend calls
  /// this only after that stop, native backup restoration and pair restoration.
  Future<void> retireAfterTransferredStop({
    required Lock lock,
    required HdrNativeDvStoppedCapture capture,
    required Future<HdrOptionSourceIdentity> Function() readIdentity,
  }) =>
      lock.synchronized(() async {
        final lease = _lease;
        final stopped = capture.stopped;
        if (lease == null ||
            lease.promotionIdentity == null ||
            capture.before != lease.promotionIdentity ||
            !identical(stopped.player, capture.before.player) ||
            stopped.fileLoadedEpoch != capture.before.fileLoadedEpoch ||
            stopped.path.isNotEmpty ||
            stopped.playlistEntryId.isNotEmpty ||
            await readIdentity() != stopped ||
            await readIdentity() != stopped) {
          throw const HdrDecoderReviewFailure(
              'Transferred probe retirement lacks its owned stopped proof');
        }
        _lease = null;
      });

  /// Only this lease's captured entry may be stopped. The resulting private
  /// proof is required for retirement. An arbitrary empty source is not an
  /// acknowledgement that this entry's native backups have been released.
  Future<HdrOptionSourceIdentity> stopOwnedUnderLock({
    required Lock lock,
    required Future<void> Function() stopWithoutLock,
    required Future<HdrOptionSourceIdentity> Function() readIdentity,
    required Future<String> Function() readPlaylistFilename,
    required Future<FileLoadedRecord> Function(int, int) waitForFileLoadedEntry,
  }) =>
      lock.synchronized(() async {
        final lease = _lease;
        if (lease == null) {
          throw const HdrDecoderReviewFailure('Container probe lost its lease');
        }
        if (lease.promotionIdentity != null) {
          throw const HdrDecoderReviewFailure(
              'Transferred probe stop belongs to its native option owner');
        }
        final acknowledged = lease.ownedStoppedIdentity;
        if (acknowledged != null) {
          if (await readIdentity() == acknowledged &&
              await readIdentity() == acknowledged) {
            return acknowledged;
          }
          final entry = lease.openedEntry;
          if (entry == null || !lease.ownStopIssued) {
            throw const HdrDecoderReviewFailure(
                'Container probe stopped acknowledgement changed');
          }
          // A delayed event may advance the epoch after stop returned. Only
          // the recorded entry's matching single FILE_LOADED can renew this
          // empty-source proof; an unrelated empty epoch is never adopted.
          final refreshed = await entry.confirmForCleanup(
            readIdentity: readIdentity,
            readPlaylistFilename: readPlaylistFilename,
            waitForFileLoadedEntry: waitForFileLoadedEntry,
            afterOwnStop: true,
          );
          if (refreshed.path.isNotEmpty ||
              refreshed.playlistEntryId.isNotEmpty) {
            throw const HdrDecoderReviewFailure(
                'Container probe stopped acknowledgement became active');
          }
          lease.ownedStoppedIdentity = refreshed;
          return refreshed;
        }
        if (lease.state == _HdrContainerProbeLeaseState.armedStopped) {
          if (await readIdentity() != lease.stoppedIdentity ||
              await readIdentity() != lease.stoppedIdentity) {
            throw const HdrDecoderReviewFailure(
                'Container probe armed source changed before cleanup');
          }
          lease.ownedStoppedIdentity = lease.stoppedIdentity;
          return lease.stoppedIdentity;
        }
        final entry = lease.openedEntry;
        if (entry == null) {
          throw const HdrDecoderReviewFailure(
              'Container probe pending open has no admitted entry proof');
        }
        final before = await entry.confirmForCleanup(
          readIdentity: readIdentity,
          readPlaylistFilename: readPlaylistFilename,
          waitForFileLoadedEntry: waitForFileLoadedEntry,
          afterOwnStop: lease.ownStopIssued,
        );
        Object? operationError;
        StackTrace? operationStack;
        if (before.path.isNotEmpty || before.playlistEntryId.isNotEmpty) {
          lease.ownStopIssued = true;
          try {
            await stopWithoutLock();
          } catch (error, stack) {
            operationError = error;
            operationStack = stack;
          }
        }
        // stop clears the playlist before asynchronous decoder teardown has
        // necessarily cleared path. Never accept a new entry during this wait.
        for (var i = 0; i < 6; i++) {
          final current = await readIdentity();
          if (!identical(current.player, entry.before.player) ||
              current.playlistEntryId.isNotEmpty ||
              current.fileLoadedEpoch < entry.before.fileLoadedEpoch ||
              current.fileLoadedEpoch > entry.before.fileLoadedEpoch + 1 ||
              (current.path.isNotEmpty && current.path != entry.mediaUri)) {
            throw const HdrDecoderReviewFailure(
                'Container probe stop crossed an unowned source');
          }
          if (current.path.isEmpty) break;
          if (i == 5) {
            throw const HdrDecoderReviewFailure(
                'Container probe owned source did not finish stopping');
          }
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        final stopped = await entry.confirmForCleanup(
          readIdentity: readIdentity,
          readPlaylistFilename: readPlaylistFilename,
          waitForFileLoadedEntry: waitForFileLoadedEntry,
          afterOwnStop: true,
        );
        if (stopped.path.isNotEmpty || stopped.playlistEntryId.isNotEmpty) {
          throw const HdrDecoderReviewFailure(
              'Container probe owned stop has not been acknowledged');
        }
        lease.ownedStoppedIdentity = stopped;
        if (operationError != null) {
          Error.throwWithStackTrace(operationError, operationStack!);
        }
        return stopped;
      });

  /// Must be called from inside the already-held Player lock. The callback is
  /// a single property batch and does not acquire a second lock.
  Future<void> verifyInLock({
    required Object plan,
    required bool Function() isCurrent,
    required int Function() fileLoadedEpoch,
    required Future<List<String>> Function(List<String>) readProperties,
    required String mediaUri,
    required int playlistEntryId,
    required int openedAfterEpoch,
  }) async {
    final lease = _lease;
    if (lease == null || !identical(lease.plan, plan)) {
      throw const HdrDecoderReviewFailure('Container probe lost ownership');
    }
    if (lease.state != _HdrContainerProbeLeaseState.confirmedEntryEpoch ||
        lease.uri != mediaUri ||
        lease.openedAfterEpoch != openedAfterEpoch ||
        lease.playlistEntryId != playlistEntryId ||
        !isCurrent() ||
        fileLoadedEpoch() != openedAfterEpoch + 1) {
      throw const HdrDecoderReviewFailure(
          'Container probe entry or epoch changed');
    }
    await _assertEntryAndOptions(
      isCurrent: isCurrent,
      fileLoadedEpoch: fileLoadedEpoch,
      readProperties: readProperties,
      mediaUri: mediaUri,
      entryId: playlistEntryId,
      openedAfterEpoch: openedAfterEpoch,
      expectedFlag: 'no',
      expectedSelectors: lease.selectors,
    );
  }

  Future<void> resume({
    required Lock lock,
    required Object plan,
    required bool Function() isCurrent,
    required int Function() fileLoadedEpoch,
    required Future<List<String>> Function(List<String>) readProperties,
    required Future<void> Function(String, String) writeProperty,
    required int expectedEntryId,
    required int openedAfterEpoch,
    required String mediaUri,
  }) async {
    final lease = _lease;
    if (lease == null) return;
    await lock.synchronized(() async {
      if (lease.promotionIdentity != null || lease.start?.isNegative == true) {
        throw const HdrDecoderReviewFailure(
            'Probe cannot use ordinary decoderless resume');
      }
      await verifyInLock(
        plan: plan,
        isCurrent: isCurrent,
        fileLoadedEpoch: fileLoadedEpoch,
        readProperties: readProperties,
        mediaUri: mediaUri,
        playlistEntryId: expectedEntryId,
        openedAfterEpoch: openedAfterEpoch,
      );
      var expectedFlag = 'no';
      var expectedSelectors = List<String>.of(lease.selectors);
      Future<void> assertOptions() => _assertEntryAndOptions(
          isCurrent: isCurrent,
          fileLoadedEpoch: fileLoadedEpoch,
          readProperties: readProperties,
          mediaUri: mediaUri,
          entryId: expectedEntryId,
          openedAfterEpoch: openedAfterEpoch,
          expectedFlag: expectedFlag,
          expectedSelectors: expectedSelectors);
      Future<void> verifyDecoderless() async {
        await assertOptions();
        await _verifyDecoderlessTracks(readProperties,
            allowLargeTrackTable: true);
        await assertOptions();
      }

      await verifyDecoderless();
      // Keep automatic selection disabled while every selector is made inert.
      // A video's explicit auto selection can create its decoder even with
      // track-auto-selection=no, so it must follow the exact seek barrier.
      for (var i = 0; i < hdrContainerProbeSelectorProperties.length; i++) {
        if (expectedSelectors[i] == 'no') continue;
        await _writeOwnedEntryProperty(
          isCurrent: isCurrent,
          fileLoadedEpoch: fileLoadedEpoch,
          readProperties: readProperties,
          writeProperty: writeProperty,
          mediaUri: mediaUri,
          entryId: expectedEntryId,
          openedAfterEpoch: openedAfterEpoch,
          expectedFlag: expectedFlag,
          expectedSelectors: expectedSelectors,
          property: hdrContainerProbeSelectorProperties[i],
          value: 'no',
        );
        expectedSelectors[i] = 'no';
      }
      await _armRawStartBeforeDecoding(
        start: lease.start,
        readProperties: readProperties,
        writeProperty: writeProperty,
        verifyDecoderless: verifyDecoderless,
      );

      // Restore video first while the flag remains no, then audio/subtitles.
      // Auto still chooses the normal track: audio-only and multiple-video
      // sources do not acquire a new unique-video admission requirement.
      for (var i = 0; i < hdrContainerProbeSelectorProperties.length; i++) {
        if (lease.selectors[i] == 'no') continue;
        await _verifyOrdinaryActiveSlots(readProperties, expectedSelectors);
        final nextSelectors = List<String>.of(expectedSelectors);
        nextSelectors[i] = lease.selectors[i];
        await _writeOwnedEntryProperty(
          isCurrent: isCurrent,
          fileLoadedEpoch: fileLoadedEpoch,
          readProperties: readProperties,
          writeProperty: writeProperty,
          mediaUri: mediaUri,
          entryId: expectedEntryId,
          openedAfterEpoch: openedAfterEpoch,
          expectedFlag: expectedFlag,
          expectedSelectors: expectedSelectors,
          property: hdrContainerProbeSelectorProperties[i],
          value: lease.selectors[i],
          verifySelectedVideo: () =>
              _verifyOrdinaryActiveSlots(readProperties, nextSelectors),
        );
        expectedSelectors = nextSelectors;
      }
      await _verifyOrdinaryActiveSlots(readProperties, expectedSelectors);
      await _writeOwnedEntryProperty(
        isCurrent: isCurrent,
        fileLoadedEpoch: fileLoadedEpoch,
        readProperties: readProperties,
        writeProperty: writeProperty,
        mediaUri: mediaUri,
        entryId: expectedEntryId,
        openedAfterEpoch: openedAfterEpoch,
        expectedFlag: expectedFlag,
        expectedSelectors: expectedSelectors,
        property: 'options/track-auto-selection',
        value: lease.trackAutoSelection,
        verifySelectedVideo: () =>
            _verifyOrdinaryActiveSlots(readProperties, expectedSelectors),
      );
      expectedFlag = lease.trackAutoSelection;
      await assertOptions();
      await _verifyOrdinaryActiveSlots(readProperties, expectedSelectors);
      await assertOptions();
      lease.resumed = true;
    });
  }

  /// Completes track selection after the owned native output has selected the
  /// one video track. Video is never toggled: doing so could create a second
  /// decoder while promoting this entry.
  Future<void> resumePromotion({
    required Lock lock,
    required Object plan,
    required bool Function() isCurrent,
    required int Function() fileLoadedEpoch,
    required Future<List<String>> Function(List<String>) readProperties,
    required Future<void> Function(String, String) writeProperty,
    required int expectedEntryId,
    required int openedAfterEpoch,
    required String mediaUri,
    required Future<void> Function() verifyBoundVideo,
  }) =>
      lock.synchronized(() async {
        final lease = _lease;
        if (lease == null ||
            !promotionTransferred(plan) ||
            !lease.promotionStartArmed ||
            lease.resumed ||
            lease.uri != mediaUri ||
            lease.playlistEntryId != expectedEntryId ||
            lease.openedAfterEpoch != openedAfterEpoch) {
          throw const HdrDecoderReviewFailure(
              'Container probe promotion lost its entry');
        }
        var flag = 'no';
        final selectors = List<String>.of(lease.selectors);
        Future<void> verifyVideo() async {
          await verifyBoundVideo();
          await _verifyPromotedVideo(readProperties);
          await verifyBoundVideo();
        }

        Future<void> assertOptions() => _assertEntryAndOptions(
            isCurrent: isCurrent,
            fileLoadedEpoch: fileLoadedEpoch,
            readProperties: readProperties,
            mediaUri: mediaUri,
            entryId: expectedEntryId,
            openedAfterEpoch: openedAfterEpoch,
            expectedFlag: flag,
            expectedSelectors: selectors);
        Future<void> write(String property, String value) async {
          await _writeOwnedEntryProperty(
              isCurrent: isCurrent,
              fileLoadedEpoch: fileLoadedEpoch,
              readProperties: readProperties,
              writeProperty: writeProperty,
              mediaUri: mediaUri,
              entryId: expectedEntryId,
              openedAfterEpoch: openedAfterEpoch,
              expectedFlag: flag,
              expectedSelectors: selectors,
              property: property,
              value: value,
              verifySelectedVideo: verifyVideo);
          if (property == 'options/track-auto-selection') {
            flag = value;
          } else {
            selectors[hdrContainerProbeSelectorProperties.indexOf(property)] =
                value;
          }
        }

        await assertOptions();
        await verifyVideo();
        await assertOptions();
        // Prevent automatic audio/subtitle selection until each captured
        // selector is deliberately restored. Keep the bound video untouched.
        for (var i = 1; i < selectors.length; i++) {
          if (selectors[i] != 'no') {
            await write(hdrContainerProbeSelectorProperties[i], 'no');
          }
        }
        await write('options/track-auto-selection', lease.trackAutoSelection);
        for (var i = 1; i < selectors.length; i++) {
          if (lease.selectors[i] != 'no') {
            await write(
                hdrContainerProbeSelectorProperties[i], lease.selectors[i]);
          }
        }
        await assertOptions();
        await verifyVideo();
        await assertOptions();
        lease.resumed = true;
      });

  /// Native per-entry backups have already been restored by termination.
  /// Retire only after this lease's own stop was proved; never adopt an
  /// arbitrary empty source supplied by a caller.
  Future<void> retireAtStoppedBoundary({
    required Lock lock,
    required HdrOptionSourceIdentity stoppedIdentity,
    required Future<HdrOptionSourceIdentity> Function() readIdentity,
  }) async {
    final lease = _lease;
    if (lease == null) return;
    await lock.synchronized(() async {
      final authorized = lease.ownedStoppedIdentity ??
          (lease.state == _HdrContainerProbeLeaseState.armedStopped
              ? lease.stoppedIdentity
              : null);
      if (!identical(_lease, lease) ||
          authorized == null ||
          stoppedIdentity != authorized ||
          authorized.path.isNotEmpty ||
          authorized.playlistEntryId.isNotEmpty ||
          await readIdentity() != authorized ||
          await readIdentity() != authorized) {
        throw const HdrDecoderReviewFailure(
            'Container probe retirement lacks its owned stopped proof');
      }
      _lease = null;
    });
  }

  static Future<void> _armRawStartBeforeDecoding({
    required Duration? start,
    required Future<List<String>> Function(List<String>) readProperties,
    required Future<void> Function(String, String) writeProperty,
    required Future<void> Function() verifyDecoderless,
  }) async {
    if (start?.isNegative == true) {
      throw const HdrDecoderReviewFailure(
          'Decoderless probe start is negative');
    }
    await verifyDecoderless();
    final capability =
        await readProperties(const ['mediakit-container-probe-seek-ready']);
    await verifyDecoderless();
    if (capability.length != 1 ||
        !const ['yes', 'no'].contains(capability.single)) {
      throw const HdrDecoderReviewFailure(
          'Native decoderless seek capability is unavailable');
    }
    // A null caller start retains the native default; do not synthesize zero.
    if (start == null) return;
    final target = start.inMilliseconds / 1000.0;
    if (!target.isFinite) {
      throw const HdrDecoderReviewFailure(
          'Decoderless probe start is not finite');
    }
    // SET must execute the seek before a decoder can emit its first frame.
    // The native raw target, not a clamped playback position getter, proves
    // that exact target remains armed while no output chain exists.
    await writeProperty('time-pos', target.toString());
    await verifyDecoderless();
    final seek = await readProperties(const [
      'mediakit-container-probe-seek-ready',
      'mediakit-container-probe-seek-target',
    ]);
    await verifyDecoderless();
    final armedTarget = seek.length == 2 ? double.tryParse(seek[1]) : null;
    if (seek.length != 2 ||
        seek[0] != 'yes' ||
        armedTarget == null ||
        !armedTarget.isFinite ||
        (armedTarget - target).abs() > 1e-6) {
      throw const HdrDecoderReviewFailure(
          'Decoderless probe did not synchronously arm its raw seek target');
    }
  }

  /// Ordinary selection retains mpv's auto policy. The direct selector's
  /// positive no/id value and matching slot prove each enabled stream without
  /// imposing a unique-video table requirement or scanning unbounded tracks.
  static Future<void> _verifyOrdinaryActiveSlots(
    Future<List<String>> Function(List<String>) readProperties,
    List<String> selectors,
  ) async {
    const slots = ['video', 'audio', 'sub', 'sub2'];
    final values = await readProperties([
      'vid',
      'aid',
      'sid',
      'secondary-sid',
      for (final slot in slots) ...[
        'current-tracks/$slot/id',
        'current-tracks/$slot/selected',
        'current-tracks/$slot/main-selection',
        'current-tracks/$slot/decoder',
      ],
    ]);
    if (values.length != 20 || selectors.length != 4) {
      throw const HdrDecoderReviewFailure(
          'Ordinary probe track proof is incomplete');
    }
    for (var i = 0; i < 4; i++) {
      final actual = values[i];
      final offset = 4 + i * 4;
      if (actual == 'no') {
        if (values
            .sublist(offset, offset + 4)
            .any((value) => value.isNotEmpty)) {
          throw const HdrDecoderReviewFailure(
              'Inactive ordinary probe slot owns a decoder');
        }
        continue;
      }
      final id = int.tryParse(actual);
      if (selectors[i] == 'no' ||
          id == null ||
          id < 0 ||
          values[offset] != actual ||
          !_selected(values[offset + 1]) ||
          values[offset + 2] != (i == 3 ? '1' : '0')) {
        throw const HdrDecoderReviewFailure(
            'Ordinary probe selected an unowned playback slot');
      }
    }
  }

  static Future<void> _verifyDecoderlessTracks(
      Future<List<String>> Function(List<String>) readProperties,
      {bool allowLargeTrackTable = false}) async {
    await _verifyNoSelectedTracks(readProperties);
    final countRaw = await readProperties(const ['track-list/count']);
    final count = countRaw.length == 1 ? int.tryParse(countRaw.single) : null;
    if (count == null || count < 0 || (count > 64 && !allowLargeTrackTable)) {
      throw const HdrDecoderReviewFailure(
          'Probe promotion cannot bound decoder ownership');
    }
    if (count > 64) {
      // The typed probe's native no-selection window is still intact. Retain
      // the positive direct-no/empty-slot proof above for large tables and
      // check every current decoder slot without an unbounded property batch.
      final values = await readProperties([
        for (final slot in ['video', 'audio', 'sub', 'sub2']) ...[
          'current-tracks/$slot/decoder',
          'current-tracks/$slot/decoder-desc',
        ],
      ]);
      if (values.length != 8 || values.any((value) => value.isNotEmpty)) {
        throw const HdrDecoderReviewFailure(
            'Large probe table has an active decoder');
      }
      await _verifyNoSelectedTracks(readProperties);
      return;
    }
    final names = <String>[
      'vid',
      'aid',
      'sid',
      'secondary-sid',
      for (var i = 0; i < count; i++) ...[
        'track-list/$i/decoder',
        'track-list/$i/decoder-desc',
      ],
      for (final slot in ['video', 'audio', 'sub', 'sub2']) ...[
        'current-tracks/$slot/id',
        'current-tracks/$slot/selected',
        'current-tracks/$slot/main-selection',
        'current-tracks/$slot/decoder',
      ],
      'track-list/count',
    ];
    final values = await readProperties(names);
    if (values.length != names.length ||
        values.take(4).any((value) => value != 'no') ||
        values.sublist(4, values.length - 1).any((value) => value.isNotEmpty) ||
        values.last != countRaw.single) {
      throw const HdrDecoderReviewFailure(
          'Probe promotion found an existing decoder or playback slot');
    }
    await _verifyNoSelectedTracks(readProperties);
  }

  static Future<void> _verifyPromotedVideo(
      Future<List<String>> Function(List<String>) readProperties) async {
    final countRaw = await readProperties(const ['track-list/count']);
    final count = countRaw.length == 1 ? int.tryParse(countRaw.single) : null;
    if (count == null || count <= 0 || count > 64) {
      throw const HdrDecoderReviewFailure(
          'Promoted probe cannot bound its video selection');
    }
    final names = <String>[
      'vid',
      'current-tracks/video/id',
      'current-tracks/video/selected',
      'current-tracks/video/main-selection',
      'options/track-auto-selection',
      'options/aid',
      'options/sid',
      'options/secondary-sid',
      for (final slot in ['audio', 'sub', 'sub2']) ...[
        'current-tracks/$slot/id',
        'current-tracks/$slot/selected',
        'current-tracks/$slot/main-selection',
        'current-tracks/$slot/decoder',
      ],
      for (var i = 0; i < count; i++) ...[
        'track-list/$i/id',
        'track-list/$i/type',
        'track-list/$i/selected',
        'track-list/$i/main-selection',
        'track-list/$i/decoder',
        'track-list/$i/external',
        'track-list/$i/albumart',
        'track-list/$i/image',
      ],
      'track-list/count',
    ];
    final values = await readProperties(names);
    if (values.length != names.length ||
        values.last != countRaw.single ||
        int.tryParse(values[0]) == null ||
        values[0] != values[1] ||
        !_selected(values[2]) ||
        values[3] != '0') {
      throw const HdrDecoderReviewFailure(
          'Promoted probe has no uniquely bound video');
    }
    var selectedVideos = 0;
    for (var slot = 0; slot < 3; slot++) {
      final enabled = values[4] == 'yes' && values[5 + slot] != 'no';
      if (!enabled &&
          values
              .sublist(8 + slot * 4, 12 + slot * 4)
              .any((value) => value.isNotEmpty)) {
        throw const HdrDecoderReviewFailure(
            'Promoted probe selected an unenabled playback slot');
      }
    }
    for (var i = 0; i < count; i++) {
      final offset = 20 + i * 8;
      final selected = _selected(values[offset + 2]);
      if (!selected) {
        if (values[offset + 3].isNotEmpty || values[offset + 4].isNotEmpty) {
          throw const HdrDecoderReviewFailure(
              'Promoted probe has an unowned decoder');
        }
        continue;
      }
      final type = values[offset + 1];
      if (type == 'video') {
        selectedVideos++;
        if (values[offset] != values[0] ||
            values[offset + 3] != '0' ||
            values.sublist(offset + 5, offset + 8).any(_selected)) {
          throw const HdrDecoderReviewFailure(
              'Promoted probe selected an unexpected video');
        }
      } else if (values[4] != 'yes' ||
          (type == 'audio' && values[5] == 'no') ||
          (type == 'sub' && values[6] == 'no' && values[7] == 'no') ||
          (type != 'audio' && type != 'sub')) {
        throw const HdrDecoderReviewFailure(
            'Promoted probe selected an unexpected additional track');
      }
    }
    if (selectedVideos != 1) {
      throw const HdrDecoderReviewFailure(
          'Promoted probe has multiple or missing video selections');
    }
  }

  static bool _selected(String value) => value == 'yes' || value == 'true';

  static Future<void> _verifyNoSelectedTracks(
      Future<List<String>> Function(List<String>) readProperties) async {
    final countRaw = (await readProperties(const ['track-list/count'])).single;
    final count = int.tryParse(countRaw);
    if (count == null || count < 0) {
      throw const HdrDecoderReviewFailure(
          'Container probe track list is unavailable');
    }
    if (count > 64) {
      // A valid source may have many tracks. Bound metadata discovery, but do
      // not reject ordinary playback solely for its table size. Direct track
      // selectors provide positive "no current track" evidence; empty slot
      // getters alone could also mean an unsupported/failed property read.
      final names = <String>[
        'vid',
        'aid',
        'sid',
        'secondary-sid',
        'options/lavfi-complex',
        for (final slot in ['video', 'audio', 'sub', 'sub2']) ...[
          'current-tracks/$slot/id',
          'current-tracks/$slot/selected',
          'current-tracks/$slot/main-selection',
        ],
        'track-list/count',
      ];
      final values = await readProperties(names);
      if (values.length != names.length ||
          values.take(4).any((value) => value != 'no') ||
          values
              .sublist(4, values.length - 1)
              .any((value) => value.isNotEmpty) ||
          values.last != countRaw) {
        throw const HdrDecoderReviewFailure(
            'Container probe cannot prove all playback slots unselected');
      }
      return;
    }
    final names = <String>[
      for (var i = 0; i < count; i++) ...[
        'track-list/$i/selected',
        'track-list/$i/main-selection',
      ],
    ];
    final values =
        names.isEmpty ? const <String>[] : await readProperties(names);
    if (values.length != names.length) {
      throw const HdrDecoderReviewFailure(
          'A track is selected during container probe ownership');
    }
    for (var i = 0; i < values.length; i += 2) {
      if ((values[i].isNotEmpty && values[i] != 'no' && values[i] != 'false') ||
          values[i + 1].isNotEmpty) {
        throw const HdrDecoderReviewFailure(
            'A track is selected during container probe ownership');
      }
    }
  }

  static const _entryOwnershipProperties = <String>[
    'path',
    'playlist/0/id',
    'playlist/0/filename',
    'options/track-auto-selection',
    'pause',
    'options/rebase-start-time',
    'options/play-dir',
    'options/lavfi-complex',
    'options/demuxer-cache-wait',
    ...hdrContainerProbeSelectorProperties,
  ];

  Future<void> _writeOwnedEntryProperty({
    required bool Function() isCurrent,
    required int Function() fileLoadedEpoch,
    required Future<List<String>> Function(List<String>) readProperties,
    required Future<void> Function(String, String) writeProperty,
    required String mediaUri,
    required int entryId,
    required int openedAfterEpoch,
    required String expectedFlag,
    required List<String> expectedSelectors,
    required String property,
    required String value,
    Future<void> Function()? verifySelectedVideo,
  }) async {
    if (verifySelectedVideo != null) {
      await verifySelectedVideo();
    } else if (expectedFlag == 'no') {
      await _verifyNoSelectedTracks(readProperties);
    }
    await _assertEntryAndOptions(
      isCurrent: isCurrent,
      fileLoadedEpoch: fileLoadedEpoch,
      readProperties: readProperties,
      mediaUri: mediaUri,
      entryId: entryId,
      openedAfterEpoch: openedAfterEpoch,
      expectedFlag: expectedFlag,
      expectedSelectors: expectedSelectors,
    );
    await writeProperty(property, value);
    final updatedFlag =
        property == 'options/track-auto-selection' ? value : expectedFlag;
    final updatedSelectors = [
      for (var i = 0; i < expectedSelectors.length; i++)
        hdrContainerProbeSelectorProperties[i] == property
            ? value
            : expectedSelectors[i],
    ];
    await _assertEntryAndOptions(
      isCurrent: isCurrent,
      fileLoadedEpoch: fileLoadedEpoch,
      readProperties: readProperties,
      mediaUri: mediaUri,
      entryId: entryId,
      openedAfterEpoch: openedAfterEpoch,
      expectedFlag: updatedFlag,
      expectedSelectors: updatedSelectors,
    );
    if (verifySelectedVideo != null) {
      await verifySelectedVideo();
    } else if (updatedFlag == 'no') {
      await _verifyNoSelectedTracks(readProperties);
    }
  }

  Future<void> _assertEntryAndOptions({
    required bool Function() isCurrent,
    required int Function() fileLoadedEpoch,
    required Future<List<String>> Function(List<String>) readProperties,
    required String mediaUri,
    required int entryId,
    required int openedAfterEpoch,
    required String expectedFlag,
    required List<String> expectedSelectors,
  }) async {
    if (!isCurrent() || fileLoadedEpoch() != openedAfterEpoch + 1) {
      throw const HdrDecoderReviewFailure(
          'Container probe entry or epoch changed during resume');
    }
    final values = await readProperties(_entryOwnershipProperties);
    if (values.length != _entryOwnershipProperties.length ||
        !isCurrent() ||
        fileLoadedEpoch() != openedAfterEpoch + 1 ||
        values[0] != mediaUri ||
        values[1] != entryId.toString() ||
        values[2] != mediaUri ||
        values[3] != expectedFlag ||
        values[4] != 'yes' ||
        values[5] != 'yes' ||
        values[6] != 'forward' ||
        values[7].isNotEmpty ||
        values[8] != 'no' ||
        !_sameSelectors(values.sublist(9), expectedSelectors)) {
      throw const HdrDecoderReviewFailure(
          'Container probe source or option ownership changed during resume');
    }
  }

  static bool _sameSelectors(List<String> actual, List<String> expected) =>
      actual.length == expected.length &&
      List<int>.generate(actual.length, (i) => i)
          .every((i) => actual[i] == expected[i]);
}
