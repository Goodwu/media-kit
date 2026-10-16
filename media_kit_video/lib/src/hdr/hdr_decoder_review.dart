import 'dart:async';

import 'package:media_kit/media_kit.dart' show FileLoadedRecord, VideoParams;
import 'package:synchronized/synchronized.dart';

import 'android_mediacodec_configuration.dart';
import 'hdr_open_plan.dart';
import 'hdr_output_diagnostics.dart';
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
  // Bounded diagnostics state (HDR review layer): the monotonic wait-phase
  // attribution and the last endpoint A/B snapshots. Pure observation — no
  // read order, retry or admission semantics depend on any of it, and no
  // source path value is ever recorded.
  var phase = 'loaded';
  var iterations = 0;
  var identityOk = true;
  var loadedMs = -1;
  Map<String, String>? aValues;
  Map<String, String>? bValues;
  void emitReview(
    String outcome, {
    String? detail,
  }) {
    String? changedKey;
    String? changedA;
    String? changedB;
    if (detail != null && detail.startsWith('Decoder endpoint changed: ')) {
      changedKey = detail.substring('Decoder endpoint changed: '.length);
      changedA = aValues?[changedKey];
      changedB = bValues?[changedKey];
    }
    HdrOutputDiagnostics.review(
      playlistEntryId: playlistEntryId,
      openedAfterEpoch: openedAfterEpoch,
      outcome: outcome,
      iterations: iterations,
      elapsedMs: now().inMilliseconds,
      loadedMs: loadedMs,
      phase: phase,
      identityOk: identityOk,
      detail: detail,
      changedKey: changedKey,
      changedA: changedA,
      changedB: changedB,
      aValues: aValues,
      bValues: bValues,
    );
  }

  try {
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

    Future<String> read(String property) =>
        bounded(() => readProperty(property));
    final loaded = await bounded(
        () => waitForFileLoadedEntry(playlistEntryId, openedAfterEpoch));
    loadedMs = now().inMilliseconds;
    phase = 'loadedEpochCheck';
    if (loaded.epoch != openedAfterEpoch + 1 ||
        loaded.playlistEntryId != playlistEntryId) {
      throw const HdrDecoderReviewFailure('File-loaded entry/epoch differs');
    }

    Future<void> identity() async {
      phase = 'identity';
      remaining();
      if (fileLoadedEpoch() != loaded.epoch ||
          await read('path') != mediaUri ||
          await read('playlist/0/id') != playlistEntryId.toString() ||
          await read('playlist/0/filename') != mediaUri ||
          fileLoadedEpoch() != loaded.epoch) {
        identityOk = false;
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
      'video-params/hdr10-plus',
    ];
    Future<Map<String, String>> endpoint() async {
      final target = phase == 'endpointA' ? 'endpointB' : 'endpointA';
      phase = target;
      final values = <String, String>{};
      for (final property in endpoints) {
        values[property] = await read(property);
      }
      if (target == 'endpointA') {
        aValues = values;
      } else {
        bValues = values;
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

    /// The pre-ready shape observed on device (HDR review diagnostics,
    /// marble 2026-10-16): while mpv attaches `mediacodec-copy`, the FIRST
    /// snapshot still carries the un-suffixed software track label with an
    /// empty pixel format, and the immediate second snapshot already reads
    /// `h264_mediacodec` — the SAME MediaCodec component in
    /// `android-mediacodec-info` on both sides. That half is the before of
    /// one settling transition, not a decoder change: retry it within the
    /// shared budget instead of comparing it against its settled other
    /// half. Deliberately narrow, baseline-aware: it applies only until the
    /// decoder label is first registered, only with a frame format still
    /// unreported, and it can never mask a contradicting registered
    /// baseline (the observed-decoder guard below still rejects drift), a
    /// complete-but-conflicting sample (plan validation still rejects it),
    /// or an A/B mismatch between two settled halves.
    bool decoderLabelPreReady(Map<String, String> a) {
      if (observedDecoderEndpoints['current-tracks/video/decoder'] != null) {
        return false;
      }
      return a['hwdec-current']!.startsWith('mediacodec') &&
          !a['current-tracks/video/decoder']!.endsWith('_mediacodec') &&
          a['video-params/pixelformat']!.isEmpty;
    }

    while (true) {
      iterations++;
      final result = await bounded(() => lock.synchronized(() async {
            phase = 'admission';
            remaining(); // A late lock admission must perform no reads.
            await identity();
            final a = await endpoint();
            final b = await endpoint();
            // Readiness before equality: the un-suffixed, frame-less label
            // half of a settling hwdec attachment is not decoder evidence.
            if (decoderLabelPreReady(a)) {
              return null;
            }
            await identity();
            for (final key in endpoints) {
              if (a[key] != b[key]) {
                throw HdrDecoderReviewFailure('Decoder endpoint changed: $key');
              }
            }
            for (final key in decoderIdentityEndpoints) {
              final value = a[key]!;
              final observed = observedDecoderEndpoints[key];
              if (observed != null && value != observed) {
                throw HdrDecoderReviewFailure('Observed decoder changed: $key');
              }
              if (value.isNotEmpty) observedDecoderEndpoints[key] = value;
            }
            final profile =
                int.tryParse(a['current-tracks/video/dolby-vision-profile']!);
            final compatibility = int.tryParse(
                a['current-tracks/video/dolby-vision-compatibility-id']!);
            final el = a['current-tracks/video/dolby-vision-el-present']!;
            final vivid = a['video-params/hdr-vivid']!;
            final hdr10Plus = a['video-params/hdr10-plus']!;
            final rawConfig = a['android-mediacodec-info']!;
            final config = AndroidMediaCodecConfiguration.parse(rawConfig);
            if (rawConfig.isNotEmpty && config == null) {
              throw const HdrDecoderReviewFailure('Malformed MediaCodec info');
            }
            if (config?.nativeDvActive == true) {
              throw const HdrDecoderReviewFailure(
                  'Native DV requires its owned review consumer');
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
              return null;
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
              hdr10Plus: hdr10Plus == 'yes'
                  ? true
                  : hdr10Plus == 'no'
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
      if (result != null) {
        phase = 'complete';
        emitReview('success');
        return result;
      }
      phase = 'settleDelay';
      final left = remaining();
      await bounded(() => delay(left < const Duration(milliseconds: 50)
          ? left
          : const Duration(milliseconds: 50)));
    }
  } on HdrDecoderReviewFailure catch (error) {
    emitReview(
      error.detail.startsWith('Decoder endpoint changed: ')
          ? 'endpoint-changed'
          : 'failure',
      detail: error.detail,
    );
    rethrow;
  } on TimeoutException catch (error) {
    emitReview('timeout', detail: error.message);
    rethrow;
  } catch (error) {
    emitReview('failure', detail: error.toString());
    rethrow;
  }
}
