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
  // attribution and the CURRENT round's endpoint snapshots. Pure observation
  // — no read order, retry or admission semantics depend on any of it — and
  // no source path value is ever recorded. Snapshots are round-scoped: a
  // round that fails midway cannot be mixed with the next round's halves.
  var phase = 'loaded';
  var iterations = 0;
  var identityState = 'unchecked';
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
    try {
      HdrOutputDiagnostics.review(
        playlistEntryId: playlistEntryId,
        openedAfterEpoch: openedAfterEpoch,
        outcome: outcome,
        iterations: iterations,
        elapsedMs: (now() - started).inMilliseconds,
        loadedMs: loadedMs < 0 ? -1 : (loadedMs),
        phase: phase,
        identityOk: identityState,
        detail: detail,
        changedKey: changedKey,
        changedA: changedA,
        changedB: changedB,
        aValues: aValues,
        bValues: bValues,
      );
    } catch (_) {
      // A diagnostics failure (broken sink, formatting) must never change
      // the review's outcome or replace its original exception.
    }
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
    loadedMs = (now() - started).inMilliseconds;
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
        identityState = 'failed';
        throw const HdrDecoderReviewFailure('Current source identity differs');
      }
      identityState = 'ok';
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

    /// The publication contract (V2 R1.3): the ONLY per-key transitions
    /// permitted between the two halves of one sampling round, each still
    /// bounded by the shared budget and subject to the observed-decoder
    /// guard below.
    ///
    /// * First publication — one half is still empty: the property had no
    ///   prior value that a retry could hide.
    /// * The hw-attach label publication — `X` → `X_mediacodec` while
    ///   both halves report the identical hwdec mode and the IDENTICAL
    ///   MediaCodec configuration (component, MIME, native-DV flag): the
    ///   device-evidenced relabeling of ONE decoder attachment. A swapped
    ///   configuration between the halves is not this shape and fails as a
    ///   decoder change. Component name equality is necessary, not an
    ///   instance proof — the residual same-name-instance risk is recorded
    ///   and accepted by explicit adjudication, with any later drift of the
    ///   registered settled identity still rejected by the guard.
    bool supportedPublication(
        String key, Map<String, String> a, Map<String, String> b) {
      if (a[key]!.isEmpty || b[key]!.isEmpty) return true;
      if (key == 'current-tracks/video/decoder' &&
          b[key] == '${a[key]}_mediacodec' &&
          a['hwdec-current'] == b['hwdec-current'] &&
          a['hwdec-current']!.startsWith('mediacodec') &&
          a['android-mediacodec-info'] == b['android-mediacodec-info']) {
        return true;
      }
      return false;
    }

    while (true) {
      iterations++;
      aValues = null;
      bValues = null; // Round-scoped snapshots: never mix rounds (V2 R3).
      final result = await bounded(() => lock.synchronized(() async {
            phase = 'admission';
            remaining(); // A late lock admission must perform no reads.
            await identity();
            final a = await endpoint();
            final b = await endpoint();
            // Post-sampling source identity BEFORE any publication
            // handling (V2 R1.1): a superseded or drifted source can never
            // be carried into a retry.
            phase = 'identityAfter';
            await identity();
            // Per-sample safety on BOTH halves before any publication
            // handling (V2 R1.2): a malformed configuration or an active
            // native-DV component can never be washed out by a retry.
            for (final half in [a, b]) {
              final raw = half['android-mediacodec-info']!;
              final config = AndroidMediaCodecConfiguration.parse(raw);
              if (raw.isNotEmpty && config == null) {
                throw const HdrDecoderReviewFailure(
                    'Malformed MediaCodec info');
              }
              if (config?.nativeDvActive == true) {
                throw const HdrDecoderReviewFailure(
                    'Native DV requires its owned review consumer');
              }
            }
            // Endpoint equality with the bounded publication contract
            // (V2 R1.3): any other mismatch fails.
            final publishedKeys = <String>{};
            for (final key in endpoints) {
              if (a[key] != b[key]) {
                if (!supportedPublication(key, a, b)) {
                  throw HdrDecoderReviewFailure(
                      'Decoder endpoint changed: $key');
                }
                publishedKeys.add(key);
              }
            }
            // Cross-attempt identity guard: registered from the SETTLED
            // side of a published key and from every other non-empty value,
            // on every round that reaches this point — including rounds
            // that are still incomplete (drift is never masked by
            // readiness).
            for (final key in decoderIdentityEndpoints) {
              final published = publishedKeys.contains(key);
              final value = published
                  ? (b[key]!.isNotEmpty ? b[key]! : a[key]!)
                  : a[key]!;
              final observed = observedDecoderEndpoints[key];
              if (observed != null && value != observed) {
                // A supported publication SUPERSEDES the pre-attach label:
                // the settled value becomes the registered identity. Any
                // change that is not a supported publication still fails.
                if (!published) {
                  throw HdrDecoderReviewFailure(
                      'Observed decoder changed: $key');
                }
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
    // Privacy (V2 R3): an unknown error's message may embed the source
    // URL — record only the runtime type, never the message.
    emitReview('failure', detail: error.runtimeType.toString());
    rethrow;
  }
}
