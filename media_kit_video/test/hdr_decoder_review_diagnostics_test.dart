import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' show FileLoadedRecord;
import 'package:media_kit_video/src/hdr/hdr_decoder_review.dart';
import 'package:media_kit_video/src/hdr/hdr_open_plan.dart' show HdrReviewFacts;
import 'package:media_kit_video/src/hdr/hdr_output_diagnostics.dart';
import 'package:synchronized/synchronized.dart';

/// HDR review diagnostics (V2 Q1 adjudication): the review gate records one
/// bounded, single-line observation per gather exit — wait-phase budget
/// attribution, iteration count and, on an endpoint mismatch, the full A/B
/// snapshots. Pure observation: the recorded evidence must never contain the
/// source path value, and the gate's admission, retry and A/B rejection
/// semantics are unchanged.
void main() {
  const mediaUri = 'signed-url-that-must-not-be-logged';
  final lines = <String>[];

  setUp(() {
    lines.clear();
    HdrOutputDiagnostics.enabled = false;
  });

  tearDown(() {
    HdrOutputDiagnostics.enabled = false;
    HdrOutputDiagnostics.printer = debugPrint;
  });

  void enable() {
    HdrOutputDiagnostics.printer = lines.add;
    HdrOutputDiagnostics.enabled = true;
  }

  /// Full endpoint snapshot with every known key present (empty = unreported)
  /// and the given per-key overrides applied.
  Map<String, String> values(Map<String, String> overrides) {
    final base = <String, String>{
      for (final key in const [
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
      ])
        key: ''
    };
    return base..addAll(overrides);
  }

  /// The 17 endpoints of the A snapshot (reads 0–16) see [aHwdec] for
  /// `hwdec-current`, the B snapshot (reads 17–33) sees [bHwdec].
  Future<HdrReviewFacts> gatherWithFlippedHwdec(String aHwdec, String bHwdec) {
    var read = 0;
    return gatherDecoderReviewFacts(
      lock: Lock(),
      mediaUri: 'signed-url-that-must-not-be-logged',
      readProperty: (name) async {
        // The identity endpoints first (no counter effect on the A/B split).
        if (name == 'path' || name == 'playlist/0/filename') return mediaUri;
        if (name == 'playlist/0/id') return '7';
        final snapshot = read++ < 17 ? aHwdec : bHwdec;
        return values({
          'hwdec-current': snapshot,
        })[name] ?? '';
      },
      waitForFileLoadedEntry: (_, __) async => const FileLoadedRecord(4, 7),
      playlistEntryId: 7,
      openedAfterEpoch: 3,
      fileLoadedEpoch: () => 4,
      isCurrent: () => true,
    );
  }

  test('endpoint mismatch records the changed key with both snapshots',
      () async {
    enable();
    await expectLater(
      gatherWithFlippedHwdec('no', 'mediacodec-copy'),
      throwsA(isA<HdrDecoderReviewFailure>()),
    );
    expect(lines, hasLength(1));
    final line = lines.single;
    expect(line, contains('HDR review: '));
    expect(line, contains('outcome=endpoint-changed'));
    expect(line, contains('changedKey=hwdec-current'));
    expect(line, contains('changedA=no'));
    expect(line, contains('changedB=mediacodec-copy'));
    final aSection =
        line.substring(line.indexOf(' a=') + 3, line.indexOf(' b='));
    final bSection = line.substring(line.indexOf(' b=') + 3);
    expect(aSection, contains('hwdec-current=no'));
    expect(bSection, contains('hwdec-current=mediacodec-copy'));
    expect(line, contains('entry=7 openedAfterEpoch=3'));
    // The privacy contract: the source path value never reaches the record.
    expect(line.contains('signed-url-that-must-not-be-logged'), isFalse);
  });

  test('budget timeout attributes the wait phase', () async {
    enable();
    await expectLater(
      gatherDecoderReviewFacts(
        lock: Lock(),
        mediaUri: mediaUri,
        readProperty: (_) async => '',
        waitForFileLoadedEntry: (_, __) => Completer<FileLoadedRecord>().future,
        playlistEntryId: 7,
        openedAfterEpoch: 3,
        fileLoadedEpoch: () => 4,
        isCurrent: () => true,
        budget: const Duration(milliseconds: 30),
      ),
      throwsA(isA<HdrDecoderReviewTimeout>()),
    );
    expect(lines, hasLength(1));
    final line = lines.single;
    expect(line, contains('outcome=timeout'));
    expect(line, contains('phase=loaded'));
    expect(line, contains('loadedMs=-1'));
  });

  test('identity drift is recorded as a failure with identityOk=false',
      () async {
    enable();
    var epoch = 4;
    await expectLater(
      gatherDecoderReviewFacts(
        lock: Lock(),
        mediaUri: mediaUri,
        readProperty: (name) async {
          if (name == 'path') epoch = 5;
          return 'drifted';
        },
        waitForFileLoadedEntry: (_, __) async => const FileLoadedRecord(4, 7),
        playlistEntryId: 7,
        openedAfterEpoch: 3,
        fileLoadedEpoch: () => epoch,
        isCurrent: () => true,
      ),
      throwsA(isA<HdrDecoderReviewFailure>()),
    );
    expect(lines, hasLength(1));
    final line = lines.single;
    expect(line, contains('outcome=failure'));
    expect(line, contains('identityOk=false'));
    expect(line, contains('phase=identity'));
    expect(line.contains('drifted'), isFalse,
        reason: 'the drifted path value must not be logged');
  });

  test('a stable complete sample records success with the final snapshot',
      () async {
    enable();
    final stableReads = values({
      'current-tracks/video/decoder': 'omx.qcom.decoder',
      'hwdec-current': 'mediacodec-copy',
      'video-params/pixelformat': 'yuv420p',
      'current-tracks/video/codec': 'h264',
      'video-format': 'avc',
      'video-params/gamma': 'bt.709',
      'video-params/primaries': 'bt.709',
      'path': mediaUri,
      'playlist/0/filename': mediaUri,
      'playlist/0/id': '7',
    });
    final facts = await gatherDecoderReviewFacts(
      lock: Lock(),
      mediaUri: 'signed-url-that-must-not-be-logged',
      readProperty: (name) async => stableReads[name]!,
      waitForFileLoadedEntry: (_, __) async => const FileLoadedRecord(4, 7),
      playlistEntryId: 7,
      openedAfterEpoch: 3,
      fileLoadedEpoch: () => 4,
      isCurrent: () => true,
    );
    expect(facts.hwdecCurrent, 'mediacodec-copy');
    expect(lines, hasLength(1));
    final line = lines.single;
    expect(line, contains('outcome=success'));
    expect(line, contains('phase=complete'));
    final aSection = line.substring(line.indexOf(' a=') + 3);
    expect(aSection, contains('hwdec-current=mediacodec-copy'));
    expect(aSection, contains('video-params/pixelformat=yuv420p'));
    expect(line.contains('signed-url-that-must-not-be-logged'), isFalse);
  });

  test('disabled diagnostics emit nothing and change no outcome', () async {
    await expectLater(
      gatherWithFlippedHwdec('no', 'surfacetexture'),
      throwsA(isA<HdrDecoderReviewFailure>()),
    );
    expect(lines, isEmpty);
  });
}
