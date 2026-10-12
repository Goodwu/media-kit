import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:media_kit/media_kit.dart' show FileLoadedRecord, VideoParams;
import 'package:synchronized/synchronized.dart';

import 'android_mediacodec_configuration.dart';
import 'hdr_open_plan.dart';
import 'hdr_route.dart';

/// A current ordinary decode sample. This is neither a chosen decoder nor
/// presentation proof. Empty decoder names remain unknown, including on old
/// Android versions that cannot expose MediaCodec.getName().
class HdrDecoderObservation {
  const HdrDecoderObservation({
    required this.playlistEntryId,
    required this.fileLoadedEpoch,
    required this.decoder,
    required this.decoderDescription,
    required this.hwdec,
    required this.pixelFormat,
    required this.hwPixelFormat,
    this.mediaCodecConfiguration,
  });

  final int playlistEntryId;
  final int fileLoadedEpoch;
  final String decoder;
  final String decoderDescription;
  final String hwdec;
  final String pixelFormat;
  final String hwPixelFormat;
  final AndroidMediaCodecConfiguration? mediaCodecConfiguration;

  bool get decoderIdentityKnown =>
      decoder.isNotEmpty ||
      (mediaCodecConfiguration?.codec.isNotEmpty ?? false);

  /// `no` is mpv's positive software observation. Empty is unreported.
  bool get softwareDecoded => hwdec == 'no';

  /// Conservative known CPU format names from mpv/FFmpeg's scalar property.
  /// A hardware or unrecognized format is not CPU-upload evidence. This does
  /// not certify format support or successful rendering by libplacebo.
  bool get cpuFrame => RegExp(
        r'^(?:(?:yuv|yuvj|yuva)(?:420|422|444|440|411|410)p(?:9|10|12|14|16)?(?:le|be)?|'
        r'(?:gbrp|gbrap)(?:9|10|12|14|16|f32)?(?:le|be)?|'
        r'(?:gray|ya)(?:8|9|10|12|14|16|f32)?(?:le|be)?|'
        r'nv(?:12|21|16|20|24|42)(?:le|be)?|p(?:010|012|016|210|212|216|410|412|416)(?:le|be)?|'
        r'(?:rgb|bgr)(?:24|48|565|555|444|8|4)(?:le|be)?|'
        r'rgba|bgra|argb|abgr|rgb0|bgr0|0rgb|0bgr|rgba64(?:le|be)?|bgra64(?:le|be)?|'
        r'yuyv422|uyvy422|uyyvyy411|xyz12(?:le|be)?|monow|monob)$',
      ).hasMatch(pixelFormat);
}

/// Checks the actual resource accepted by the existing presenter. It does not
/// select a codec by name or grant new software/HDR paths.
void validateDecoderObservation(HdrRoute route, HdrReviewFacts facts) {
  final observation = facts.decoderObservation;
  if (observation == null) return; // Legacy injected backends, not production.
  if (facts.codec.isEmpty) {
    throw const HdrPlaybackBlocked(HdrDegradeReason.sourceMetadataUnknown);
  }
  final config = observation.mediaCodecConfiguration;
  if (observation.hwdec.isEmpty ||
      observation.pixelFormat.isEmpty ||
      observation.hwdec != facts.hwdecCurrent ||
      config?.nativeDvActive == true ||
      (route.vo == 'mediacodec_embed' &&
          (observation.hwdec != 'mediacodec' ||
              observation.pixelFormat != 'mediacodec'))) {
    throw const HdrPlaybackBlocked(HdrDegradeReason.routeReviewMismatch);
  }
  // Source codec describes the track, not the selected decoder identity.
  const mimeByCodec = <String, String>{
    'h264': 'video/avc',
    'avc': 'video/avc',
    'hevc': 'video/hevc',
    'h265': 'video/hevc',
    'vp9': 'video/x-vnd.on2.vp9',
    'av1': 'video/av01',
  };
  if (observation.softwareDecoded && config != null) {
    throw const HdrPlaybackBlocked(HdrDegradeReason.routeReviewMismatch);
  }
  final expectedMime = mimeByCodec[facts.codec];
  if (config != null && expectedMime != null && config.mime != expectedMime) {
    throw const HdrPlaybackBlocked(HdrDegradeReason.routeReviewMismatch);
  }
  if ((observation.softwareDecoded || observation.hwdec == 'mediacodec-copy') &&
      !observation.cpuFrame) {
    throw const HdrPlaybackBlocked(HdrDegradeReason.routeReviewMismatch);
  }
  if ((observation.hwdec == 'mediacodec' ||
          observation.hwdec == 'surfacetexture') &&
      observation.pixelFormat != 'mediacodec') {
    throw const HdrPlaybackBlocked(HdrDegradeReason.routeReviewMismatch);
  }
}

class HdrDecoderReviewFailure implements Exception {
  const HdrDecoderReviewFailure(this.detail);
  final String detail;
  @override
  String toString() => 'HdrDecoderReviewFailure($detail)';
}

class HdrDecoderReviewTimeout extends TimeoutException {
  HdrDecoderReviewTimeout() : super('Ordinary decoder review budget exhausted');
}

/// Immutable admission proof captured by the same Player lock as public open.
class HdrDecoderOpenedEntry {
  const HdrDecoderOpenedEntry(this.openedAfterEpoch, this.playlistEntryId);
  final int openedAfterEpoch;
  final int playlistEntryId;
}

Future<HdrDecoderOpenedEntry> captureDecoderOpenUnderLock({
  required Lock lock,
  required String mediaUri,
  required int Function() fileLoadedEpoch,
  required Future<void> Function() openWithoutLock,
  required Future<String> Function(String) readProperty,
  required bool Function() isCurrent,
}) =>
    lock.synchronized(() async {
      void check() {
        if (!isCurrent()) {
          throw const HdrDecoderReviewFailure('Superseded ordinary open');
        }
      }

      check();
      final before = fileLoadedEpoch();
      await openWithoutLock();
      check();
      final filename = await readProperty('playlist/0/filename');
      check();
      final rawEntry = await readProperty('playlist/0/id');
      check();
      final entry = int.tryParse(rawEntry);
      if (filename != mediaUri || entry == null || entry < 0) {
        throw const HdrDecoderReviewFailure('Opened playlist differs');
      }
      if (await readProperty('playlist/0/filename') != filename) {
        throw const HdrDecoderReviewFailure('Opened playlist changed');
      }
      check();
      if (await readProperty('playlist/0/id') != rawEntry) {
        throw const HdrDecoderReviewFailure('Opened entry changed');
      }
      check();
      return HdrDecoderOpenedEntry(before, entry);
    });

/// All asynchronous waits use one monotonic budget. Endpoint equality detects
/// observable changes; it cannot prove the absence of ABA between native reads.
/// The scalar frame properties are sampled directly, rather than promoting a
/// potentially delayed videoParams stream event into current-source evidence.
Future<HdrReviewFacts> gatherDecoderReviewFacts({
  required Lock lock,
  required String mediaUri,
  required Future<String> Function(String) readProperty,
  required Future<FileLoadedRecord> Function(int, int) waitForFileLoadedEntry,
  required int playlistEntryId,
  required int openedAfterEpoch,
  required int Function() fileLoadedEpoch,
  required bool Function() isCurrent,
  Duration budget = const Duration(seconds: 8),
  Duration Function()? monotonicNow,
  Future<void> Function(Duration) delay = Future<void>.delayed,
}) async {
  final stopwatch = Stopwatch()..start();
  final now = monotonicNow ?? (() => stopwatch.elapsed);
  final started = now();
  Duration remaining() {
    if (!isCurrent()) {
      throw const HdrDecoderReviewFailure('Superseded decoder sample');
    }
    final result = budget - (now() - started);
    if (result <= Duration.zero) throw HdrDecoderReviewTimeout();
    return result;
  }

  Future<T> bounded<T>(Future<T> Function() operation) async {
    final left = remaining();
    try {
      final result = await operation().timeout(left);
      remaining();
      return result;
    } on TimeoutException {
      throw HdrDecoderReviewTimeout();
    }
  }

  Future<String> read(String property) => bounded(() => readProperty(property));
  final loaded = await bounded(
      () => waitForFileLoadedEntry(playlistEntryId, openedAfterEpoch));
  if (loaded.epoch != openedAfterEpoch + 1 ||
      loaded.playlistEntryId != playlistEntryId) {
    throw const HdrDecoderReviewFailure('File-loaded entry/epoch differs');
  }

  Future<void> identity() async {
    remaining();
    if (fileLoadedEpoch() != loaded.epoch ||
        await read('path') != mediaUri ||
        await read('playlist/0/id') != playlistEntryId.toString() ||
        await read('playlist/0/filename') != mediaUri ||
        fileLoadedEpoch() != loaded.epoch) {
      throw const HdrDecoderReviewFailure('Current source identity differs');
    }
  }

  const endpoints = <String>[
    'current-tracks/video/decoder',
    'current-tracks/video/decoder-desc',
    'hwdec-current',
    'android-mediacodec-info',
    'video-params/pixelformat',
    'video-params/hw-pixelformat',
    'video-params/gamma',
    'video-params/primaries',
    'video-params/colormatrix',
    'video-params/colorlevels',
    'current-tracks/video/codec',
    'video-format',
    'current-tracks/video/dolby-vision-profile',
    'current-tracks/video/dolby-vision-compatibility-id',
    'current-tracks/video/dolby-vision-el-present',
    'video-params/hdr-vivid',
  ];
  Future<Map<String, String>> endpoint() async {
    final values = <String, String>{};
    for (final property in endpoints) {
      values[property] = await read(property);
    }
    return values;
  }

  final observedDecoderEndpoints = <String, String>{};
  const decoderIdentityEndpoints = <String>[
    'current-tracks/video/decoder',
    'current-tracks/video/decoder-desc',
    'hwdec-current',
    'android-mediacodec-info',
  ];
  // DV004-DIAG (temporary, behavior-preserving): logs observed values at the
  // existing throw sites and required-fact gaps per poll round. Remove with
  // the DV004 fix.
  var round = 0;
  void diag(String event, Map<String, Object?> fields) {
    debugPrint('DV004_DIAG event=$event round=$round '
        'elapsedMs=${now().inMilliseconds} entry=$playlistEntryId '
        'epoch=${loaded.epoch} $fields');
  }

  while (true) {
    round += 1;
    final result = await bounded(() => lock.synchronized(() async {
          remaining(); // A late lock admission must perform no reads.
          await identity();
          final a = await endpoint();
          final b = await endpoint();
          await identity();
          for (final key in endpoints) {
            if (a[key] != b[key]) {
              throw HdrDecoderReviewFailure('Decoder endpoint changed: $key');
            }
          }
          final hwdec = a['hwdec-current']!;
          final pixel = a['video-params/pixelformat']!;
          final gamma = a['video-params/gamma']!;
          final primaries = a['video-params/primaries']!;
          if (hwdec.isEmpty ||
              pixel.isEmpty ||
              gamma.isEmpty ||
              primaries.isEmpty ||
              a['video-format']!.isEmpty ||
              a['current-tracks/video/codec']!.isEmpty) {
            // DV004: pre-completeness rounds carry mpv's logical decoder
            // name, which the first decoded frame replaces with the actual
            // AVCodec name (f_decoder_wrapper.c:452-463 →
            // av_common.c:449-457). Sampling identity only from complete
            // samples keeps that name publication from failing the review;
            // real post-establishment switches remain guarded by the
            // session's final plan comparison.
            diag('requiredFactsMissing', {
              'hwdec': hwdec,
              'pixelFormat': pixel,
              'gamma': gamma,
              'primaries': primaries,
              'videoFormat': a['video-format'],
              'codec': a['current-tracks/video/codec'],
            });
            return null;
          }
          for (final key in decoderIdentityEndpoints) {
            final value = a[key]!;
            final observed = observedDecoderEndpoints[key];
            if (observed != null && value != observed) {
              diag('observedDecoderChanged', {
                'key': key,
                'old': observed,
                'new': value,
                'decoder': a['current-tracks/video/decoder'],
                'decoderDesc': a['current-tracks/video/decoder-desc'],
                'hwdecCurrent': a['hwdec-current'],
                'mediaCodecInfo': a['android-mediacodec-info'],
                'codec': a['current-tracks/video/codec'],
                'pixelFormat': a['video-params/pixelformat'],
                'gamma': a['video-params/gamma'],
              });
              throw HdrDecoderReviewFailure('Observed decoder changed: $key');
            }
            if (value.isNotEmpty) {
              if (observed == null) {
                diag('identityRecorded', {'key': key, 'value': value});
              }
              observedDecoderEndpoints[key] = value;
            }
          }
          final profile =
              int.tryParse(a['current-tracks/video/dolby-vision-profile']!);
          final compatibility = int.tryParse(
              a['current-tracks/video/dolby-vision-compatibility-id']!);
          final el = a['current-tracks/video/dolby-vision-el-present']!;
          final vivid = a['video-params/hdr-vivid']!;
          final rawConfig = a['android-mediacodec-info']!;
          final config = AndroidMediaCodecConfiguration.parse(rawConfig);
          if (rawConfig.isNotEmpty && config == null) {
            throw const HdrDecoderReviewFailure('Malformed MediaCodec info');
          }
          if (config?.nativeDvActive == true) {
            throw const HdrDecoderReviewFailure(
                'Native DV requires its owned review consumer');
          }
          String? optional(String key) => a[key]!.isEmpty ? null : a[key];
          return HdrReviewFacts(
            videoParams: VideoParams(
              pixelformat: pixel,
              hwPixelformat: optional('video-params/hw-pixelformat'),
              gamma: gamma,
              primaries: primaries,
              colormatrix: optional('video-params/colormatrix'),
              colorlevels: optional('video-params/colorlevels'),
            ),
            codec: a['current-tracks/video/codec']!,
            hwdecCurrent: hwdec,
            path: mediaUri,
            dolbyVisionProfile: profile,
            dvCompatibilityId: compatibility != null && compatibility >= 0
                ? compatibility
                : null,
            dvElPresent: el == '1'
                ? true
                : el == '0'
                    ? false
                    : null,
            hdrVivid: vivid == 'yes'
                ? true
                : vivid == 'no'
                    ? false
                    : null,
            decoderObservation: HdrDecoderObservation(
              playlistEntryId: playlistEntryId,
              fileLoadedEpoch: loaded.epoch,
              decoder: a['current-tracks/video/decoder']!,
              decoderDescription: a['current-tracks/video/decoder-desc']!,
              hwdec: hwdec,
              pixelFormat: pixel,
              hwPixelFormat: a['video-params/hw-pixelformat']!,
              mediaCodecConfiguration: config,
            ),
          );
        }));
    if (result != null) return result;
    final left = remaining();
    await bounded(() => delay(left < const Duration(milliseconds: 50)
        ? left
        : const Duration(milliseconds: 50)));
  }
}
