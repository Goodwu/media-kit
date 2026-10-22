import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:media_kit/media_kit.dart' show FileLoadedRecord, VideoParams;
import 'package:synchronized/synchronized.dart';

import 'android_mediacodec_configuration.dart';
import 'hdr_native_dv_option_owner.dart';
import 'hdr_native_dv_review_evidence.dart';
import 'hdr_open_plan.dart';

/// Define-gated per-round sampling trace for on-device review diagnosis.
const bool kHdrNativeDvReviewTrace =
    bool.fromEnvironment('MEDIA_KIT_ANDROID_HDR_REVIEW_TRACE');

String _configSummary(AndroidMediaCodecConfiguration? config) {
  if (config == null) return 'null';
  return '${config.mime}/${config.codec}/active=${config.nativeDvActive}';
}

/// Production native-DV review. All waits share one monotonic deadline.
/// Future timeouts cannot interrupt synchronous native FFI; they bound the
/// asynchronous admission/polling and prevent accepting a late sample.
/// Matching source/output/decoder endpoints cannot prove absence of an ABA
/// transition between reads, or establish a codec generation or presentation.
Future<HdrReviewFacts> gatherNativeDvReviewFacts({
  required Lock lock,
  required HdrOptionSourceIdentity expectedIdentity,
  required int openedAfterEpoch,
  required int expectedEntryId,
  required Future<void> Function() verifyOwned,
  required Future<HdrOptionSourceIdentity> Function() readIdentity,
  required Future<FileLoadedRecord> Function(int, int) waitForFileLoadedEntry,
  required HdrNativeDvOutputSnapshot? Function() readOutput,
  required Future<String> Function(String) readProperty,
  Future<List<String>> Function(List<String>)? readProperties,
  required VideoParams? Function() latestVideoParams,
  Duration budget = const Duration(seconds: 8),
  Duration Function()? monotonicNow,
  Future<void> Function(Duration) delay = Future<void>.delayed,
}) async {
  final stopwatch = Stopwatch()..start();
  final now = monotonicNow ?? (() => stopwatch.elapsed);
  final started = now();
  Duration remaining() {
    final result = budget - (now() - started);
    if (result <= Duration.zero) {
      throw const HdrNativeDvReviewFailure(
          HdrNativeDvReviewFailureKind.timeout);
    }
    return result;
  }

  HdrNativeDvReviewFailure timeoutFailure([Object? cause]) =>
      HdrNativeDvReviewFailure(HdrNativeDvReviewFailureKind.timeout,
          cause: cause);

  /// Native property/ownership reads cannot be cancelled. Keep the caller's
  /// lock until the exact in-flight operation has settled before reporting a
  /// deadline failure.
  Future<T> boundedNative<T>(Future<T> Function() operation) async {
    final left = remaining();
    final pending = operation();
    try {
      final result = await pending.timeout(left);
      remaining();
      return result;
    } on TimeoutException catch (error) {
      try {
        await pending;
      } catch (_) {
        // Preserve the budget failure; only draining is required here.
      }
      throw timeoutFailure(error);
    }
  }

  /// Event waits and delay do not issue a native read, so their timeout need
  /// not drain the future.
  Future<T> boundedPassive<T>(Future<T> Function() operation) async {
    final left = remaining();
    try {
      final result = await operation().timeout(left);
      remaining();
      return result;
    } on TimeoutException catch (error) {
      throw timeoutFailure(error);
    }
  }

  /// Bound lock admission without abandoning work after it starts. A queued
  /// callback checks the shared deadline on admission and therefore performs
  /// no reads if this caller has already timed out.
  Future<T> boundedLock<T>(
      Future<T> Function(void Function() markAdmitted) operation) async {
    final left = remaining();
    var admitted = false;
    final lockWork = operation(() => admitted = true);
    try {
      final result = await lockWork.timeout(left);
      remaining();
      return result;
    } on TimeoutException catch (error) {
      if (admitted) {
        try {
          await lockWork;
        } catch (_) {
          // The lock callback's native read has now drained.
        }
      } else {
        // Observe a late callback error. Its first remaining() rejects it
        // before any property read after eventual lock admission.
        lockWork.then<void>((_) {}, onError: (Object _, StackTrace __) {});
      }
      throw timeoutFailure(error);
    }
  }

  Future<List<String>> readGroup(List<String> properties) async {
    final batchReader = readProperties;
    if (batchReader != null) {
      final values = await boundedNative(() => batchReader(properties));
      if (values.length != properties.length) {
        throw const HdrNativeDvReviewFailure(
            HdrNativeDvReviewFailureKind.configuration);
      }
      return values;
    }
    final values = <String>[];
    for (final property in properties) {
      values.add(await boundedNative(() => readProperty(property)));
    }
    return values;
  }

  Future<void> verify() async {
    try {
      await boundedNative(verifyOwned);
    } on HdrNativeDvReviewFailure {
      rethrow;
    } catch (error) {
      throw HdrNativeDvReviewFailure(HdrNativeDvReviewFailureKind.ownership,
          cause: error);
    }
    if (await boundedNative(readIdentity) != expectedIdentity) {
      throw const HdrNativeDvReviewFailure(
          HdrNativeDvReviewFailureKind.sourceIdentity);
    }
  }

  if (expectedIdentity.path.isEmpty ||
      expectedIdentity.playlistEntryId != expectedEntryId.toString() ||
      expectedIdentity.fileLoadedEpoch != openedAfterEpoch + 1) {
    throw const HdrNativeDvReviewFailure(
        HdrNativeDvReviewFailureKind.sourceIdentity);
  }

  HdrNativeDvOutputSnapshot? pinned;
  HdrNativeDvOutputSnapshot? output() {
    remaining();
    final current = readOutput();
    if (pinned != null && (current == null || !pinned!.matches(current))) {
      throw const HdrNativeDvReviewFailure(
          HdrNativeDvReviewFailureKind.outputIdentity);
    }
    pinned ??= current;
    return current;
  }

  await boundedLock((markAdmitted) => lock.synchronized(() async {
        markAdmitted();
        remaining();
        await verify();
        output();
        await verify();
        output();
      }));
  final loaded = await boundedPassive(
      () => waitForFileLoadedEntry(expectedEntryId, openedAfterEpoch));
  if (loaded.playlistEntryId != expectedEntryId ||
      loaded.epoch != expectedIdentity.fileLoadedEpoch) {
    throw const HdrNativeDvReviewFailure(
        HdrNativeDvReviewFailureKind.fileLoaded);
  }

  AndroidMediaCodecConfiguration? observedConfiguration;
  var observedHwdec = false;
  bool sameConfiguration(AndroidMediaCodecConfiguration? a,
          AndroidMediaCodecConfiguration? b) =>
      a == null
          ? b == null
          : b != null &&
              a.mime == b.mime &&
              a.codec == b.codec &&
              a.nativeDvActive == b.nativeDvActive;
  bool invalidConfiguration(
          String raw, AndroidMediaCodecConfiguration? value) =>
      raw.isNotEmpty &&
      (value == null ||
          value.mime != 'video/dolby-vision' ||
          value.codec.isEmpty ||
          !value.nativeDvActive);
  while (true) {
    final facts =
        await boundedLock((markAdmitted) => lock.synchronized(() async {
              markAdmitted();
              remaining(); // A lock acquired after timeout cannot sample anything.
              await verify();
              final beforeOutput = output();
              const headProperties = <String>[
                'android-mediacodec-info',
                'hwdec-current',
                'video-format',
                'current-tracks/video/dolby-vision-profile',
                'current-tracks/video/codec',
                'current-tracks/video/dolby-vision-compatibility-id',
                'current-tracks/video/dolby-vision-el-present',
                'video-params/hdr-vivid',
              ];
              final head = await readGroup(headProperties);
              final raw = head[0];
              final config = AndroidMediaCodecConfiguration.parse(raw);
              final hwdec = head[1];
              final videoFormat = head[2];
              final profile = int.tryParse(head[3]);
              final codec = head[4];
              final compat = int.tryParse(head[5]);
              final el = head[6];
              final vivid = head[7];
              final params = latestVideoParams();
              // Source/output gates alone cannot detect decoder teardown on an
              // unchanged source and Surface. Re-read both decoder endpoints after
              // the track reads; never return the earlier configured value alone.
              const tailProperties = <String>[
                'android-mediacodec-info',
                'hwdec-current',
              ];
              final tail = await readGroup(tailProperties);
              final endRaw = tail[0];
              final endConfig = AndroidMediaCodecConfiguration.parse(endRaw);
              final endHwdec = tail[1];
              await verify();
              final afterOutput = output();
              if (kHdrNativeDvReviewTrace) {
                debugPrint('HDR_REVIEW_ROUND cfg=${_configSummary(config)} '
                    'end=${_configSummary(endConfig)} '
                    'hwdec="$hwdec" endHwdec="$endHwdec" vfmt="$videoFormat" '
                    'observed=${_configSummary(observedConfiguration)} '
                    'observedHwdec=$observedHwdec '
                    'out=${beforeOutput != null}:${afterOutput != null}');
              }
              if (invalidConfiguration(raw, config) ||
                  invalidConfiguration(endRaw, endConfig) ||
                  (config != null && !sameConfiguration(config, endConfig))) {
                throw const HdrNativeDvReviewFailure(
                    HdrNativeDvReviewFailureKind.configuration);
              }
              if (observedConfiguration != null &&
                  (!sameConfiguration(config, observedConfiguration) ||
                      !sameConfiguration(endConfig, observedConfiguration))) {
                throw const HdrNativeDvReviewFailure(
                    HdrNativeDvReviewFailureKind.configuration);
              }
              if ((hwdec.isNotEmpty && hwdec != 'mediacodec') ||
                  (endHwdec.isNotEmpty && endHwdec != 'mediacodec') ||
                  (hwdec.isNotEmpty && hwdec != endHwdec)) {
                throw const HdrNativeDvReviewFailure(
                    HdrNativeDvReviewFailureKind.hwdec);
              }
              if (observedHwdec && (hwdec.isEmpty || endHwdec.isEmpty)) {
                throw const HdrNativeDvReviewFailure(
                    HdrNativeDvReviewFailureKind.hwdec);
              }
              // A valid tail is already an observation even when this round must
              // be discarded for fresh sampling. Pin it before leaving the lock,
              // so the next round cannot adopt a different decoder or disappearance.
              observedConfiguration ??= config ?? endConfig;
              observedHwdec =
                  observedHwdec || hwdec.isNotEmpty || endHwdec.isNotEmpty;
              // Initial initialization during this snapshot requires a fresh full
              // sample next round. Neither a new tail value nor a stale head is
              // accepted as this round's configured evidence.
              if (!sameConfiguration(config, endConfig) || hwdec != endHwdec) {
                return null;
              }
              if (config == null ||
                  hwdec.isEmpty ||
                  videoFormat.isEmpty ||
                  afterOutput == null ||
                  beforeOutput == null) {
                return null;
              }
              return HdrReviewFacts(
                videoParams: params,
                dolbyVisionProfile: profile,
                codec: codec,
                hwdecCurrent: hwdec,
                path: expectedIdentity.path,
                dvCompatibilityId:
                    compat != null && compat >= 0 ? compat : null,
                dvElPresent: el == '1' ? true : (el == '0' ? false : null),
                hdrVivid:
                    vivid == 'yes' ? true : (vivid == 'no' ? false : null),
                nativeDvEvidence: HdrNativeDvReviewEvidence(
                  source: expectedIdentity,
                  loaded: loaded,
                  controller: afterOutput.controller,
                  output: afterOutput.identity,
                  configuration: config,
                  hwdecCurrent: hwdec,
                ),
              );
            }));
    if (facts != null) return facts;
    final left = remaining();
    await boundedPassive(() => delay(left < const Duration(milliseconds: 50)
        ? left
        : const Duration(milliseconds: 50)));
  }
}
