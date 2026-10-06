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

  Future<T> bounded<T>(Future<T> Function() operation) async {
    final left = remaining();
    try {
      final result = await operation().timeout(left);
      remaining();
      return result;
    } on TimeoutException catch (error) {
      throw HdrNativeDvReviewFailure(HdrNativeDvReviewFailureKind.timeout,
          cause: error);
    }
  }

  Future<void> verify() async {
    try {
      await bounded(verifyOwned);
    } on HdrNativeDvReviewFailure {
      rethrow;
    } catch (error) {
      throw HdrNativeDvReviewFailure(HdrNativeDvReviewFailureKind.ownership,
          cause: error);
    }
    if (await bounded(readIdentity) != expectedIdentity) {
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

  await bounded(() => lock.synchronized(() async {
        remaining();
        await verify();
        output();
        await verify();
        output();
      }));
  final loaded = await bounded(
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
    final facts = await bounded(() => lock.synchronized(() async {
          remaining(); // A lock acquired after timeout cannot sample anything.
          await verify();
          final beforeOutput = output();
          final raw =
              await bounded(() => readProperty('android-mediacodec-info'));
          final config = AndroidMediaCodecConfiguration.parse(raw);
          final hwdec = await bounded(() => readProperty('hwdec-current'));
          final videoFormat = await bounded(() => readProperty('video-format'));
          final profile = int.tryParse(await bounded(
              () => readProperty('current-tracks/video/dolby-vision-profile')));
          final codec =
              await bounded(() => readProperty('current-tracks/video/codec'));
          final compat = int.tryParse(await bounded(() => readProperty(
              'current-tracks/video/dolby-vision-compatibility-id')));
          final el = await bounded(() =>
              readProperty('current-tracks/video/dolby-vision-el-present'));
          final vivid =
              await bounded(() => readProperty('video-params/hdr-vivid'));
          final params = latestVideoParams();
          // Source/output gates alone cannot detect decoder teardown on an
          // unchanged source and Surface. Re-read both decoder endpoints after
          // the track reads; never return the earlier configured value alone.
          final endRaw =
              await bounded(() => readProperty('android-mediacodec-info'));
          final endConfig = AndroidMediaCodecConfiguration.parse(endRaw);
          final endHwdec = await bounded(() => readProperty('hwdec-current'));
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
            dvCompatibilityId: compat != null && compat >= 0 ? compat : null,
            dvElPresent: el == '1' ? true : (el == '0' ? false : null),
            hdrVivid: vivid == 'yes' ? true : (vivid == 'no' ? false : null),
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
    await bounded(() => delay(left < const Duration(milliseconds: 50)
        ? left
        : const Duration(milliseconds: 50)));
  }
}
