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

class _ReviewWorkResult<T> {
  const _ReviewWorkResult.value(this.value)
      : error = null,
        stackTrace = null;
  const _ReviewWorkResult.error(this.error, this.stackTrace) : value = null;
  final T? value;
  final Object? error;
  final StackTrace? stackTrace;
}

const _reviewPollTick = Object();

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
  // The budget spans the file-loaded wait AND the post-loaded settle. 4K
  // network streams on slow radios routinely need 5–10 s of loaded→first-
  // frame settle (measured LG H870DS: loaded 1.4–4.6 s + settle 5–8 s);
  // an 8 s total turned marginal networks into a hardware-decode exclusion
  // with a software-decode retry — effectively a black screen. 20 s keeps
  // the settle bounded while covering the slow tail.
  Duration budget = const Duration(seconds: 20),
  Duration Function()? monotonicNow,
  Future<void> Function(Duration) delay = Future<void>.delayed,
  Duration cancellationPollInterval = const Duration(milliseconds: 20),
}) async {
  final stopwatch = Stopwatch()..start();
  final wallClock = Stopwatch()..start();
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
    // Single-sample contract (2026-10-20): no endpoint-pair comparison
    // exists, so no changed-key extraction is performed. bValues stays null
    // by construction.
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
      final elapsed = now() - started;
      final wallElapsed = wallClock.elapsed;
      final result = budget - (elapsed > wallElapsed ? elapsed : wallElapsed);
      if (result <= Duration.zero) throw HdrDecoderReviewTimeout();
      return result;
    }

    Future<T> bounded<T>(Future<T> Function() operation) async {
      final left = remaining();
      final pending = operation();
      try {
        final result = await pending.timeout(left);
        remaining();
        return result;
      } on TimeoutException {
        // Future.timeout stops waiting; it cannot stop a native property read.
        // Keep the Player lock until that exact read has actually settled.
        try {
          await pending;
        } catch (_) {
          // Preserve cancellation/timeout as the review result.
        }
        if (!isCurrent()) {
          throw const HdrDecoderReviewFailure('Superseded decoder sample');
        }
        throw HdrDecoderReviewTimeout();
      }
    }

    Future<T> passiveWait<T>(Future<T> future) async {
      final result = Completer<_ReviewWorkResult<T>>();
      future.then<void>(
        (value) => result.complete(_ReviewWorkResult<T>.value(value)),
        onError: (Object error, StackTrace stack) =>
            result.complete(_ReviewWorkResult<T>.error(error, stack)),
      );
      while (true) {
        remaining();
        final tick = Completer<void>();
        final timer = Timer(cancellationPollInterval, tick.complete);
        await Future.any<Object>([
          result.future,
          tick.future.then<Object>((_) => _reviewPollTick),
        ]);
        timer.cancel();
        if (result.isCompleted) {
          final completed = await result.future;
          if (completed.error != null) {
            Error.throwWithStackTrace(completed.error!, completed.stackTrace!);
          }
          remaining();
          return completed.value as T;
        }
      }
    }

    Future<String> read(String property) =>
        bounded(() => readProperty(property));
    final loaded = await passiveWait(
        waitForFileLoadedEntry(playlistEntryId, openedAfterEpoch));
    loadedMs = (now() - started).inMilliseconds;
    phase = 'loadedEpochCheck';
    if (loaded.epoch != openedAfterEpoch + 1 ||
        loaded.playlistEntryId != playlistEntryId) {
      throw const HdrDecoderReviewFailure('File-loaded entry/epoch differs');
    }

    Future<void> identity() async {
      phase = 'identity';
      remaining();
      if (fileLoadedEpoch() != loaded.epoch) {
        identityState = 'failed';
        throw const HdrDecoderReviewFailure('Current source identity differs');
      }
      if (await read('path') != mediaUri ||
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
      phase = 'endpoint';
      final values = <String, String>{};
      for (final property in endpoints) {
        values[property] = await read(property);
      }
      aValues = values;
      return values;
    }

    // Quiescence-then-single-sample contract (2026-10-20 review-gate
    // invariants design): lazy attach, error-path rebuilds and hardware-mode
    // settlement legitimately churn the endpoint while the source settles,
    // so drift DURING settling is expected and is not diagnosed. The review
    // fact base is the first sample that is complete (required facts
    // non-empty) and identical to the PREVIOUS round's sample — the
    // [settleInterval] delay between rounds provides the quiet window, so
    // stability is structural and does not depend on the injected clock
    // advancing; the plan-vs-facts promise check lives with the consumers.
    // The publication whitelist, disappearance semantics and cross-attempt
    // registry are deleted by construction: no second post-settle sample
    // exists to compare against. A source that never settles fails through
    // the shared budget as [HdrDecoderReviewTimeout]; per-sample safety
    // (malformed MediaCodec configuration, active native-DV component)
    // still fails immediately.
    const settleInterval = Duration(milliseconds: 200);
    Map<String, String>? previousSample;
    bool sameEndpoint(Map<String, String> x, Map<String, String> y) {
      for (final key in endpoints) {
        if (x[key] != y[key]) return false;
      }
      return true;
    }

    while (true) {
      iterations++;
      bValues = null; // single-sample contract: no B half is ever taken.
      var admitted = false;
      final lockWork = lock.synchronized(() async {
        admitted = true;
        phase = 'admission';
        remaining(); // A late lock admission must perform no reads.
        await identity();
        final sample = await endpoint();
        // Post-sampling source identity (kept): a superseded or drifted
        // source can never be carried into facts.
        phase = 'identityAfter';
        await identity();
        // Per-sample safety on the settled sample before it can become
        // facts: a malformed configuration or an active native-DV
        // component must fail the review regardless of settling.
        final raw = sample['android-mediacodec-info']!;
        final config = AndroidMediaCodecConfiguration.parse(raw);
        if (raw.isNotEmpty && config == null) {
          throw const HdrDecoderReviewFailure('Malformed MediaCodec info');
        }
        if (config?.nativeDvActive == true) {
          throw const HdrDecoderReviewFailure(
              'Native DV requires its owned review consumer');
        }
        return sample;
      });
      final observedLockWork =
          lockWork.then<_ReviewWorkResult<Map<String, String>>>(
        _ReviewWorkResult<Map<String, String>>.value,
        onError: (Object error, StackTrace stack) =>
            _ReviewWorkResult<Map<String, String>>.error(error, stack),
      );
      _ReviewWorkResult<Map<String, String>>? lockResult;
      while (lockResult == null) {
        try {
          remaining();
        } on Object {
          if (admitted) await observedLockWork;
          rethrow;
        }
        final tick = Completer<void>();
        final timer = Timer(cancellationPollInterval, tick.complete);
        final outcome = await Future.any<Object>([
          observedLockWork,
          tick.future.then<Object>((_) => _reviewPollTick),
        ]);
        timer.cancel();
        if (outcome is _ReviewWorkResult<Map<String, String>>) {
          lockResult = outcome;
        }
      }
      if (lockResult.error != null) {
        Error.throwWithStackTrace(lockResult.error!, lockResult.stackTrace!);
      }
      remaining();
      final values = lockResult.value!;
      final complete = values['hwdec-current']!.isNotEmpty &&
          values['video-params/pixelformat']!.isNotEmpty &&
          values['video-params/gamma']!.isNotEmpty &&
          values['video-params/primaries']!.isNotEmpty &&
          values['video-format']!.isNotEmpty &&
          values['current-tracks/video/codec']!.isNotEmpty;
      if (complete &&
          previousSample != null &&
          sameEndpoint(previousSample, values)) {
        phase = 'complete';
        final profile =
            int.tryParse(values['current-tracks/video/dolby-vision-profile']!);
        final compatibility = int.tryParse(
            values['current-tracks/video/dolby-vision-compatibility-id']!);
        final el = values['current-tracks/video/dolby-vision-el-present']!;
        final vivid = values['video-params/hdr-vivid']!;
        final hdr10Plus = values['video-params/hdr10-plus']!;
        final rawConfig = values['android-mediacodec-info']!;
        final config = AndroidMediaCodecConfiguration.parse(rawConfig);
        final hwdec = values['hwdec-current']!;
        final pixel = values['video-params/pixelformat']!;
        final gamma = values['video-params/gamma']!;
        final primaries = values['video-params/primaries']!;
        String? optional(String key) =>
            values[key]!.isEmpty ? null : values[key];
        final facts = HdrReviewFacts(
          videoParams: VideoParams(
            pixelformat: pixel,
            hwPixelformat: optional('video-params/hw-pixelformat'),
            gamma: gamma,
            primaries: primaries,
            colormatrix: optional('video-params/colormatrix'),
            colorlevels: optional('video-params/colorlevels'),
          ),
          codec: values['current-tracks/video/codec']!,
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
            decoder: values['current-tracks/video/decoder']!,
            decoderDescription: values['current-tracks/video/decoder-desc']!,
            hwdec: hwdec,
            pixelFormat: pixel,
            hwPixelFormat: values['video-params/hw-pixelformat']!,
            mediaCodecConfiguration: config,
          ),
        );
        emitReview('success');
        return facts;
      }
      previousSample = values;
      phase = 'settleDelay';
      await passiveWait(delay(settleInterval));
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
