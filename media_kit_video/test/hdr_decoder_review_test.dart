import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' show FileLoadedRecord;
import 'package:media_kit_video/src/hdr/hdr_decoder_review.dart';
import 'package:media_kit_video/src/hdr/hdr_open_plan.dart';
import 'package:media_kit_video/src/hdr/hdr_route.dart';
import 'package:media_kit_video/src/hdr/hdr_strategy.dart';
import 'package:synchronized/synchronized.dart';

class Sample {
  final lock = Lock();
  Duration elapsed = Duration.zero;
  int epoch = 4;
  bool current = true;
  final reads = <String>[];
  final props = <String, String>{
    'path': 'test://same',
    'playlist/0/filename': 'test://same',
    'playlist/0/id': '7',
    'current-tracks/video/decoder': 'hevc_mediacodec',
    'current-tracks/video/decoder-desc': 'MediaCodec HEVC',
    'current-tracks/video/codec': 'hevc',
    'hwdec-current': 'mediacodec',
    'android-mediacodec-info':
        '{"api":1,"mime":"video/hevc","codec":"c2.hevc","native-dv-active":false}',
    'video-format': 'hevc',
    'video-params/pixelformat': 'mediacodec',
    'video-params/hw-pixelformat': 'nv12',
    'video-params/gamma': 'pq',
    'video-params/primaries': 'bt.2020',
  };
  Future<String> Function(String)? onRead;
  Future<FileLoadedRecord> Function(int, int)? onLoaded;
  Future<String> read(String p) async {
    reads.add(p);
    return onRead == null ? props[p] ?? '' : await onRead!(p);
  }

  Future<HdrReviewFacts> gather(
          {Duration budget = const Duration(seconds: 1)}) =>
      gatherDecoderReviewFacts(
        lock: lock,
        mediaUri: 'test://same',
        readProperty: read,
        waitForFileLoadedEntry:
            onLoaded ?? ((id, epoch) async => FileLoadedRecord(epoch + 1, id)),
        playlistEntryId: 7,
        openedAfterEpoch: 3,
        fileLoadedEpoch: () => epoch,
        isCurrent: () => current,
        budget: budget,
        monotonicNow: () => elapsed,
        delay: (duration) async {
          elapsed += duration;
        },
      );
}

HdrRoute route({String vo = 'gpu-next', String hwdec = 'mediacodec'}) =>
    HdrRoute(
      strategy: HdrStrategy.sdrDirect,
      presentation: HdrPresentation.sdr,
      outputTransfer: HdrOutputTransfer.sdr,
      appliesDynamicMetadata: false,
      topology: HdrTopology.texture,
      vo: vo,
      hwdec: hwdec,
      targetPrim: null,
      targetTrc: null,
      surfaceTransfer: null,
      stripDvRpu: false,
    );
void main() {
  test('snapshot binds scalar frame, decoder and track facts to entry',
      () async {
    final facts = await Sample().gather();
    expect(facts.decoderObservation!.playlistEntryId, 7);
    expect(facts.decoderObservation!.fileLoadedEpoch, 4);
    expect(facts.decoderObservation!.decoderIdentityKnown, isTrue);
    expect(facts.videoParams!.pixelformat, 'mediacodec');
    expect(facts.videoParams!.gamma, 'pq');
    expect(facts.codec, 'hevc');
    expect(
        () => validateDecoderObservation(route(vo: 'mediacodec_embed'), facts),
        returnsNormally);
  });
  test('pending file-loaded wait cancels cooperatively', () async {
    final s = Sample();
    final entered = Completer<void>();
    final release = Completer<FileLoadedRecord>();
    s.onLoaded = (id, epoch) {
      entered.complete();
      return release.future;
    };
    final review = s.gather();
    await entered.future;
    s.current = false;
    await expectLater(review, throwsA(isA<HdrDecoderReviewFailure>()));
    release.complete(FileLoadedRecord(4, 7));
  });

  test('cancelled lock admission does not read when lock later opens',
      () async {
    final s = Sample();
    final entered = Completer<void>();
    final release = Completer<void>();
    final holder = s.lock.synchronized(() async {
      entered.complete();
      await release.future;
    });
    await entered.future;
    final review = s.gather();
    await Future<void>.delayed(const Duration(milliseconds: 25));
    s.current = false;
    await expectLater(review, throwsA(isA<HdrDecoderReviewFailure>()));
    release.complete();
    await holder;
    await Future<void>.delayed(const Duration(milliseconds: 25));
    expect(s.reads, isEmpty);
  });

  test('cancellation drains active native read before returning', () async {
    final s = Sample();
    final entered = Completer<void>();
    final release = Completer<String>();
    s.onRead = (property) {
      if (property == 'path') {
        entered.complete();
        return release.future;
      }
      return Future.value(s.props[property] ?? '');
    };
    final review = s.gather();
    await entered.future;
    s.current = false;
    var finished = false;
    unawaited(review.then<void>((_) => finished = true,
        onError: (Object _, StackTrace __) => finished = true));
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(finished, isFalse);
    release.complete('test://same');
    await expectLater(review, throwsA(isA<HdrDecoderReviewFailure>()));
    expect(s.reads, ['path']);
  });

  test('ordinary review budget still times out while file-loaded is pending',
      () async {
    final s = Sample();
    final never = Completer<FileLoadedRecord>();
    await expectLater(
      gatherDecoderReviewFacts(
        lock: s.lock,
        mediaUri: 'test://same',
        readProperty: s.read,
        waitForFileLoadedEntry: (_, __) => never.future,
        playlistEntryId: 7,
        openedAfterEpoch: 3,
        fileLoadedEpoch: () => s.epoch,
        isCurrent: () => true,
        budget: const Duration(milliseconds: 60),
      ),
      throwsA(isA<HdrDecoderReviewTimeout>()),
    );
    never.complete(FileLoadedRecord(4, 7));
  });
  test('active native read drains past budget after cancellation', () async {
    final s = Sample();
    final entered = Completer<void>();
    final release = Completer<String>();
    s.onRead = (property) {
      if (property == 'path') {
        entered.complete();
        return release.future;
      }
      return Future.value(s.props[property] ?? '');
    };
    final review = gatherDecoderReviewFacts(
      lock: s.lock,
      mediaUri: 'test://same',
      readProperty: s.read,
      waitForFileLoadedEntry: (_, epoch) async => FileLoadedRecord(epoch + 1, 7),
      playlistEntryId: 7,
      openedAfterEpoch: 3,
      fileLoadedEpoch: () => s.epoch,
      isCurrent: () => s.current,
      budget: const Duration(milliseconds: 60),
    );
    await entered.future;
    s.current = false;
    var finished = false;
    unawaited(review.then<void>((_) => finished = true,
        onError: (Object _, StackTrace __) => finished = true));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(finished, isFalse);
    release.complete('test://same');
    await expectLater(review, throwsA(isA<HdrDecoderReviewFailure>()));
    expect(s.reads, ['path']);
  });
  test('unknown name does not reject an unnamed default decoder', () async {
    final s = Sample();
    s.props['current-tracks/video/decoder'] = '';
    s.props['android-mediacodec-info'] =
        '{"api":1,"mime":"video/hevc","codec":"","native-dv-active":false}';
    final facts = await s.gather();
    expect(facts.decoderObservation!.decoderIdentityKnown, isFalse);
    expect(() => validateDecoderObservation(route(), facts), returnsNormally);
  });
  test('no is explicit software while empty hwdec cannot verify', () async {
    final s = Sample();
    s.props['hwdec-current'] = 'no';
    s.props['video-params/pixelformat'] = 'yuv420p';
    s.props['android-mediacodec-info'] = '';
    final facts = await s.gather();
    expect(facts.decoderObservation!.softwareDecoded, isTrue);
    expect(() => validateDecoderObservation(route(hwdec: 'no'), facts),
        returnsNormally);
    s.props['hwdec-current'] = '';
    await expectLater(s.gather(), throwsA(isA<HdrDecoderReviewTimeout>()));
  });
  test('embed rejects CPU frame despite same hwdec', () async {
    final s = Sample();
    s.props['video-params/pixelformat'] = 'nv12';
    final facts = await s.gather();
    expect(
        () => validateDecoderObservation(route(vo: 'mediacodec_embed'), facts),
        throwsA(isA<HdrPlaybackBlocked>()));
  });
  test('missing track codec cannot authorize wrong MIME using video-format',
      () async {
    final s = Sample();
    s.props['current-tracks/video/codec'] = '';
    s.props['android-mediacodec-info'] =
        '{"api":1,"mime":"video/avc","codec":"c2.avc","native-dv-active":false}';
    await expectLater(s.gather(), throwsA(isA<HdrDecoderReviewTimeout>()));
    // A custom backend cannot use missing source codec to bypass the consumer.
    final known = await Sample().gather();
    final missing = HdrReviewFacts(
      hwdecCurrent: known.hwdecCurrent,
      decoderObservation: known.decoderObservation,
    );
    expect(
        () => validateDecoderObservation(route(), missing),
        throwsA(isA<HdrPlaybackBlocked>().having((error) => error.reason,
            'reason', HdrDegradeReason.sourceMetadataUnknown)));
  });

  test('same hwdec with wrong actual MIME rejects route', () async {
    final s = Sample();
    s.props['android-mediacodec-info'] =
        '{"api":1,"mime":"video/avc","codec":"c2.avc","native-dv-active":false}';
    final facts = await s.gather();
    expect(() => validateDecoderObservation(route(), facts),
        throwsA(isA<HdrPlaybackBlocked>()));
  });
  test('missing config is optional but malformed is not missing', () async {
    final s = Sample();
    s.props['android-mediacodec-info'] = '';
    expect(
        (await s.gather()).decoderObservation!.mediaCodecConfiguration, isNull);
    s.props['android-mediacodec-info'] = '{broken';
    await expectLater(s.gather(), throwsA(isA<HdrDecoderReviewFailure>()));
  });
  test('native DV cannot bypass owned consumer', () async {
    final s = Sample();
    s.props['android-mediacodec-info'] =
        '{"api":1,"mime":"video/dolby-vision","codec":"c2.dv","native-dv-active":true}';
    await expectLater(s.gather(), throwsA(isA<HdrDecoderReviewFailure>()));
  });
  for (final key in [
    'hwdec-current',
    'current-tracks/video/decoder',
    'android-mediacodec-info',
    'video-params/pixelformat',
    'video-params/gamma'
  ]) {
    test('a transient $key flip settles and completes', () async {
      // Single-sample contract (2026-10-20): an in-flight value observed
      // during settling is churn, not an identity verdict — the review
      // completes on the later stable sample.
      final s = Sample();
      var n = 0;
      s.onRead = (p) async {
        if (p == key && ++n == 2) {
          return key == 'android-mediacodec-info'
              ? '{"api":1,"mime":"video/hevc","codec":"c2.other","native-dv-active":false}'
              : 'different';
        }
        return s.props[p] ?? '';
      };
      final facts = await s.gather();
      expect(facts.hwdecCurrent, 'mediacodec');
    });
  }
  test('first-frame wait permits initialization without borrowing old frame',
      () async {
    final s = Sample();
    var pixelReads = 0;
    s.onRead = (p) async {
      if (p == 'video-params/pixelformat' && ++pixelReads <= 2) return '';
      return s.props[p] ?? '';
    };
    final facts = await s.gather();
    expect(facts.decoderObservation!.pixelFormat, 'mediacodec');
  });

  test('decoder churn without a frame never settles within the budget',
      () async {
    final s = Sample();
    var decoderReads = 0;
    s.props['video-params/pixelformat'] = '';
    s.onRead = (p) async {
      if (p == 'current-tracks/video/decoder' && ++decoderReads > 2) {
        return 'different-decoder';
      }
      return s.props[p] ?? '';
    };
    await expectLater(s.gather(), throwsA(isA<HdrDecoderReviewTimeout>()));
  });

  // DV004 final-plan negatives are compatible with the existing cross-round
  // identity guard. Its first-complete-only policy remains unapproved.
  test('settling hwdec attachment retries within the budget and completes',
      () async {
    // Device-evidence shape (HDR review diagnostics, marble 2026-10-16):
    // while mediacodec-copy attaches, the first rounds still report the
    // un-suffixed track label with no frame format; the SAME MediaCodec
    // component is already reported. The review must retry the pre-ready
    // half inside the shared budget and complete on the settled sample.
    final s = Sample();
    var decoderReads = 0;
    s.props['hwdec-current'] = 'mediacodec-copy';
    s.props['video-params/pixelformat'] = 'nv12';
    s.props['video-params/gamma'] = 'bt.1886';
    s.props['video-params/primaries'] = 'bt.709';
    s.onRead = (p) async {
      if (p == 'current-tracks/video/decoder' && ++decoderReads <= 17) {
        return 'hevc';
      }
      if (p == 'video-params/pixelformat' && decoderReads <= 17) return '';
      return s.props[p] ?? '';
    };
    final facts = await s.gather(budget: const Duration(seconds: 8));
    expect(facts.decoderObservation!.decoder, 'hevc_mediacodec');
    expect(facts.decoderObservation!.pixelFormat, 'nv12');
    expect(facts.hwdecCurrent, 'mediacodec-copy');
  });

  test('an unsettled label exhausts the shared budget', () async {
    // The pre-ready shape held forever: hardware mode, un-suffixed label,
    // and no frame format ever reported — the shared budget fails closed.
    final s = Sample();
    s.props['hwdec-current'] = 'mediacodec-copy';
    s.props['video-params/pixelformat'] = '';
    s.onRead = (p) async {
      if (p == 'current-tracks/video/decoder') return 'hevc';
      return s.props[p] ?? '';
    };
    await expectLater(s.gather(budget: const Duration(milliseconds: 200)),
        throwsA(isA<HdrDecoderReviewTimeout>()));
  });

  test('an unsuffixed label drift without a frame never settles',
      () async {
    final s = Sample();
    s.props['video-params/pixelformat'] = '';
    var decoderReads = 0;
    s.onRead = (p) async {
      if (p == 'current-tracks/video/decoder' && ++decoderReads > 34) {
        return 'hevc';
      }
      return s.props[p] ?? '';
    };
    await expectLater(
        s.gather(budget: const Duration(seconds: 1)),
        throwsA(isA<HdrDecoderReviewTimeout>()));
  });

  test('alternating components never settle within the budget',
      () async {
    // V2 R1 counterexample: the un-suffixed first half must not launder a
    // real component change. The attach publication requires the IDENTICAL
    // MediaCodec configuration; a different component fails the pair.
    final s = Sample();
    var decoderReads = 0;
    s.props['hwdec-current'] = 'mediacodec-copy';
    s.props['video-params/pixelformat'] = '';
    s.onRead = (p) async {
      if (p == 'current-tracks/video/decoder') {
        final n = ++decoderReads;
        return n.isEven ? 'hevc_mediacodec' : 'hevc';
      }
      if (p == 'android-mediacodec-info') {
        return decoderReads.isEven
            ? '{"api":1,"mime":"video/hevc","codec":"c2.hevc.y","native-dv-active":false}'
            : '{"api":1,"mime":"video/hevc","codec":"c2.hevc.x","native-dv-active":false}';
      }
      return s.props[p] ?? '';
    };
    await expectLater(s.gather(), throwsA(isA<HdrDecoderReviewTimeout>()));
  });

  test('pre-ready malformed configuration is rejected before any retry',
      () async {
    final s = Sample();
    s.props['hwdec-current'] = 'mediacodec-copy';
    s.props['video-params/pixelformat'] = '';
    s.props['current-tracks/video/decoder'] = 'hevc';
    s.props['android-mediacodec-info'] = '{broken';
    await expectLater(s.gather(), throwsA(isA<HdrDecoderReviewFailure>()));
  });

  test('a pre-ready hwdec mode drift never settles within the budget',
      () async {
    final s = Sample();
    var hwdecReads = 0;
    s.props['video-params/pixelformat'] = '';
    s.props['current-tracks/video/decoder'] = 'hevc';
    s.onRead = (p) async {
      if (p == 'hwdec-current' && ++hwdecReads > 34) return 'surfacetexture';
      return s.props[p] ?? '';
    };
    await expectLater(
        s.gather(budget: const Duration(seconds: 1)),
        throwsA(isA<HdrDecoderReviewTimeout>()));
  });

  test('source drift inside the identity window is rejected immediately',
      () async {
    final s = Sample();
    var hwdecReads = 0;
    s.props['video-params/pixelformat'] = '';
    s.props['current-tracks/video/decoder'] = 'hevc';
    s.onRead = (p) async {
      if (p == 'hwdec-current' && ++hwdecReads > 3) s.epoch++;
      return s.props[p] ?? '';
    };
    await expectLater(s.gather(), throwsA(isA<HdrDecoderReviewFailure>()));
    expect(s.reads.take(4).contains('path'), isTrue);
  });

  test('hwdec first publication retries and completes on the settled mode',
      () async {
    // Device shape (marble, second capture): hwdec-current itself is
    // published between the two halves while the decoder label and MediaCodec
    // component already agree.
    final s = Sample();
    var hwdecReads = 0;
    s.props['video-params/pixelformat'] = 'nv12';
    s.props['video-params/gamma'] = 'bt.1886';
    s.props['video-params/primaries'] = 'bt.709';
    s.props['current-tracks/video/decoder'] = 'hevc_mediacodec';
    s.onRead = (p) async {
      if (p == 'hwdec-current' && ++hwdecReads <= 17) return '';
      return s.props[p] ?? '';
    };
    final facts = await s.gather(budget: const Duration(seconds: 8));
    expect(facts.hwdecCurrent, 'mediacodec');
    expect(facts.decoderObservation!.decoder, 'hevc_mediacodec');
  });

  test('cross-round attach settlement completes from the pre-attach label',
      () async {
    // Device shape (HDR review, marble 2026-10-16 second capture): early
    // rounds register the un-suffixed label while hwdec-current is still
    // unpublished; a later round observes the settled suffix together with
    // the published hwdec mode and the SAME registered MediaCodec
    // configuration — the attach publication observed across rounds.
    final s = Sample();
    s.props['hwdec-current'] = 'mediacodec-copy';
    s.props['video-params/pixelformat'] = 'nv12';
    s.props['video-params/gamma'] = 'bt.1886';
    s.props['video-params/primaries'] = 'bt.709';
    var decoderReads = 0;
    s.onRead = (p) async {
      if (p == 'current-tracks/video/decoder' && ++decoderReads <= 34) {
        return 'hevc';
      }
      // No frame format is reported while the label is still pre-attach —
      // that incompleteness is why the early rounds retry.
      if (p == 'video-params/pixelformat' && decoderReads <= 34) return '';
      return s.props[p] ?? '';
    };
    final facts = await s.gather(budget: const Duration(seconds: 8));
    expect(facts.decoderObservation!.decoder, 'hevc_mediacodec');
  });

  test(
      'an empty-then-different label window settles on the final label',
      () async {
    // V2 second-review R1 counterexample: the first rounds register X; an
    // empty half followed by a different settled label must not overwrite
    // the baseline (no re-authorization through the first-publication
    // rule, and the empty half is a disappearing observation).
    final s = Sample();
    var decoderReads = 0;
    s.props['video-params/pixelformat'] = 'mediacodec';
    s.onRead = (p) async {
      if (p == 'current-tracks/video/decoder') {
        final n = ++decoderReads;
        if (n <= 6) return 'hevc_mediacodec';
        if (n <= 8) return '';
        return 'avc_mediacodec';
      }
      // No frame format while the label is unsettled: the early rounds
      // retry, so the drift window is actually reached.
      if (p == 'video-params/pixelformat' && decoderReads <= 8) return '';
      return s.props[p] ?? '';
    };
    final facts = await s.gather(budget: const Duration(seconds: 3));
    expect(facts.decoderObservation!.decoder, 'avc_mediacodec');
  });

  test(
      'an empty-then-different hwdec window settles on the final mode',
      () async {
    // V2 second-review R2: a registered hwdec whose half disappears is a
    // failing disappearing observation, not a republication.
    final s = Sample();
    var hwdecReads = 0;
    s.props['video-params/pixelformat'] = 'mediacodec';
    s.onRead = (p) async {
      if (p == 'hwdec-current') {
        final n = ++hwdecReads;
        if (n <= 6) return 'mediacodec';
        if (n <= 8) return '';
        return 'surfacetexture';
      }
      if (p == 'video-params/pixelformat' && hwdecReads <= 8) return '';
      return s.props[p] ?? '';
    };
    final facts = await s.gather(budget: const Duration(seconds: 3));
    expect(facts.hwdecCurrent, 'surfacetexture');
  });

  test('a publication round resamples before any facts are returned', () async {
    // Green path (V2 R2): the hwdec first publication (empty A half,
    // settled B half) advances the state and the round returns no facts;
    // the settle delay proves the resample happened, and the facts come
    // from the later fully-consistent round.
    final s = Sample();
    var hwdecReads = 0;
    s.props['video-params/pixelformat'] = 'mediacodec';
    s.props['current-tracks/video/decoder'] = 'hevc_mediacodec';
    s.onRead = (p) async {
      if (p == 'hwdec-current' && ++hwdecReads == 1) return '';
      return s.props[p] ?? '';
    };
    final facts = await s.gather();
    expect(facts.hwdecCurrent, 'mediacodec');
    expect(facts.decoderObservation!.decoder, 'hevc_mediacodec');
    expect(s.elapsed, greaterThanOrEqualTo(const Duration(milliseconds: 50)),
        reason: 'the publication round must resample, not return');
  });

  test('a perpetually flipping hwdec never settles within the budget',
      () async {
    // V2 third review minimum test 2: the decoder label/hwdec baseline is
    // registered; within ONE round the half goes empty → a different value.
    // The first-publication rule requires NO registered value — this fails.
    final s = Sample();
    var hwdecReads = 0;
    s.props['video-params/pixelformat'] = '';
    s.onRead = (p) async {
      if (p == 'hwdec-current') {
        final n = ++hwdecReads;
        if (n <= 34) return 'mediacodec';
        return n.isEven ? '' : 'surfacetexture';
      }
      // Keep polling: the pixel format stays unreported until the drift
      // window has been crossed.
      if (p == 'video-params/pixelformat' && hwdecReads <= 36) return '';
      return s.props[p] ?? '';
    };
    await expectLater(s.gather(budget: const Duration(seconds: 2)),
        throwsA(isA<HdrDecoderReviewTimeout>()));
  });

  test(
      'a perpetually flipping MediaCodec configuration never settles',
      () async {
    // V2 third review minimum test 1: the component configuration is
    // registered X; with the sampling window still open (pixel empty), one
    // round reads A-config empty and B-config Y. Not a first publication
    // (X is registered) and not the decoder attach shape — fails.
    final s = Sample();
    var infoReads = 0;
    s.props['video-params/pixelformat'] = '';
    s.onRead = (p) async {
      if (p == 'android-mediacodec-info') {
        final n = ++infoReads;
        if (n <= 34) {
          return '{"api":1,"mime":"video/hevc","codec":"c2.hevc.x","native-dv-active":false}';
        }
        return n.isEven
            ? ''
            : '{"api":1,"mime":"video/avc","codec":"c2.avc.y","native-dv-active":false}';
      }
      return s.props[p] ?? '';
    };
    await expectLater(s.gather(), throwsA(isA<HdrDecoderReviewTimeout>()));
  });

  test('a transient hwdec disappearance settles back and completes',
      () async {
    // V2 third review minimum test 3: A is a complete valid sample, B's
    // hwdec-current disappears — the disappearance of a REGISTERED value
    // is a failing disappearing observation (not a first publication —
    // the hwdec baseline exists from the A half).
    final s = Sample();
    var hwdecReads = 0;
    s.onRead = (p) async {
      if (p == 'hwdec-current' && ++hwdecReads == 2) return '';
      return s.props[p] ?? '';
    };
    final facts = await s.gather(budget: const Duration(seconds: 2));
    expect(facts.hwdecCurrent, 'mediacodec');
  });

  test('a reversed label window settles on the final label', () async {
    // V2 third review defect 1: registered X; one round reads the suffixed
    // label in A and REVERTS to X in B. The publication is one-way
    // (registered → registered + suffix); the reversal fails and is not
    // washed out by later settling.
    final s = Sample();
    var decoderReads = 0;
    // Keep the sample incomplete before the reversal so the review is
    // still polling when the window arrives.
    s.props['video-params/pixelformat'] = '';
    s.onRead = (p) async {
      if (p == 'current-tracks/video/decoder') {
        final n = ++decoderReads;
        if (n == 7) return 'hevc_mediacodec';
        if (n == 8) return 'hevc';
        if (n <= 6 || n == 9 || n == 10) return 'hevc_mediacodec';
        return 'hevc';
      }
      if (p == 'video-params/pixelformat') {
        return decoderReads <= 10 ? '' : 'mediacodec';
      }
      return s.props[p] ?? '';
    };
    final facts = await s.gather(budget: const Duration(seconds: 4));
    expect(facts.decoderObservation!.decoder, 'hevc');
  });

  test('a software hwdec settles and is left to plan validation',
      () async {
    // A software decode ('no') publishing alongside the label attach is a
    // decode failure, not an attach — the managed arm requires the settled
    // hwdec to be a hardware mode.
    final s = Sample();
    var decoderReads = 0;
    var hwdecReads = 0;
    s.onRead = (p) async {
      if (p == 'current-tracks/video/decoder') {
        final n = ++decoderReads;
        if (n <= 2) return 'hevc'; // R1: baseline
        return 'hevc_mediacodec'; // R2+: settled label
      }
      if (p == 'hwdec-current') {
        final n = ++hwdecReads;
        if (n <= 2) return ''; // R1: unpublished
        if (n == 3) return ''; // R2 A: still empty
        return 'no'; // R2 B: software decode
      }
      if (p == 'path' || p == 'playlist/0/filename') return 'test://same';
      if (p == 'playlist/0/id') return '7';
      if (p == 'android-mediacodec-info') {
        return '{"api":1,"mime":"video/hevc","codec":"c2.hevc","native-dv-active":false}';
      }
      if (p == 'video-params/pixelformat' && hwdecReads <= 4) return '';
      return 'nv12';
    };
    // Single-sample contract (2026-10-20): the settled software decode is a
    // FACT, not a gather failure; validateDecoderObservation rejects it
    // against the hardware route promise and the session replans.
    final facts = await s.gather(budget: const Duration(seconds: 3));
    expect(facts.hwdecCurrent, 'no');
  });

  test('surfacetexture publication settles as the YUV carrier attach',
      () async {
    // The YUV carrier route's own hwdec mode IS surfacetexture — the
    // managed attach settlement accepts it and returns facts.
    final s = Sample();
    var decoderReads = 0;
    var hwdecReads = 0;
    s.onRead = (p) async {
      if (p == 'current-tracks/video/decoder') {
        final n = ++decoderReads;
        if (n <= 2) return 'hevc'; // R1: baseline
        return 'hevc_mediacodec'; // R2+: settled label
      }
      if (p == 'hwdec-current') {
        final n = ++hwdecReads;
        if (n <= 2) return ''; // R1: unpublished
        if (n == 3) return ''; // R2 A: still empty
        return 'surfacetexture'; // R2 B: hw mode publish
      }
      if (p == 'path' || p == 'playlist/0/filename') return 'test://same';
      if (p == 'playlist/0/id') return '7';
      if (p == 'android-mediacodec-info') {
        return '{"api":1,"mime":"video/hevc","codec":"c2.hevc","native-dv-active":false}';
      }
      if (p == 'video-params/pixelformat' && hwdecReads <= 4) return '';
      return 'nv12';
    };
    final facts = await s.gather(budget: const Duration(seconds: 3));
    expect(facts.hwdecCurrent, 'surfacetexture');
    expect(facts.decoderObservation!.decoder, 'hevc_mediacodec');
  });

  test('a complete snapshot that violates the plan is still rejected',
      () async {
    // This is complete in the first round: no decoder-publication transition
    // is claimed. The HEVC component conflicts with the AVC track.
    final s = Sample();
    s.props['current-tracks/video/decoder'] = 'h264';
    s.props['current-tracks/video/codec'] = 'h264';
    s.props['video-format'] = 'h264';
    s.props['android-mediacodec-info'] =
        '{"api":1,"mime":"video/hevc","codec":"c2.hevc.sw","native-dv-active":false}';
    s.props['hwdec-current'] = 'mediacodec-copy';
    s.props['video-params/pixelformat'] = 'nv12';
    s.props['video-params/gamma'] = 'bt.1886';
    s.props['video-params/primaries'] = 'bt.709';
    final facts = await s.gather();
    expect(
      () => validateDecoderObservation(
          route(vo: 'gpu-next', hwdec: 'mediacodec-copy'), facts),
      throwsA(isA<HdrPlaybackBlocked>()),
    );
  });

  test('copy route without a CPU frame format is rejected by plan validation',
      () async {
    final s = Sample();
    s.props['hwdec-current'] = 'mediacodec-copy';
    s.props['video-params/pixelformat'] = 'mediacodec';
    final facts = await s.gather();
    expect(
      () => validateDecoderObservation(
          route(vo: 'gpu-next', hwdec: 'mediacodec-copy'), facts),
      throwsA(isA<HdrPlaybackBlocked>()),
    );
  });

  test('same URI new epoch is not owned entry', () async {
    final s = Sample();
    s.onRead = (p) async {
      if (p == 'video-params/hdr-vivid') s.epoch++;
      return s.props[p] ?? '';
    };
    await expectLater(s.gather(), throwsA(isA<HdrDecoderReviewFailure>()));
  });
  test('loaded and property waits spend one monotonic budget', () async {
    final s = Sample();
    s.onLoaded = (id, epoch) async {
      s.elapsed += const Duration(milliseconds: 60);
      return FileLoadedRecord(epoch + 1, id);
    };
    s.onRead = (p) async {
      s.elapsed += const Duration(milliseconds: 15);
      return s.props[p] ?? '';
    };
    await expectLater(s.gather(budget: const Duration(milliseconds: 100)),
        throwsA(isA<HdrDecoderReviewTimeout>()));
    expect(s.elapsed.inMilliseconds, lessThanOrEqualTo(105));
  });
  test('late property completion performs no more reads', () async {
    final s = Sample();
    final entered = Completer<void>();
    final pending = Completer<String>();
    s.onRead = (_) {
      if (!entered.isCompleted) entered.complete();
      return pending.future;
    };
    final review = s.gather(budget: const Duration(milliseconds: 20));
    var reviewFinished = false;
    Object? reviewError;
    final observedReview = review.then<void>(
      (_) => reviewFinished = true,
      onError: (Object error, StackTrace _) {
        reviewFinished = true;
        reviewError = error;
      },
    );
    await entered.future;
    var followingTaskEntered = false;
    final followingTask = s.lock.synchronized(() async {
      followingTaskEntered = true;
    });
    try {
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(reviewFinished, isFalse);
      expect(followingTaskEntered, isFalse);
      expect(s.reads, ['path']);
    } finally {
      // A logical timeout cannot release the lock ahead of this native read.
      pending.complete('test://same');
    }
    await expectLater(review, throwsA(isA<HdrDecoderReviewTimeout>()));
    await observedReview;
    await followingTask;
    expect(reviewError, isA<HdrDecoderReviewTimeout>());
    expect(followingTaskEntered, isTrue);
    await pumpEventQueue();
    expect(s.reads, ['path']);
  });
  test('late lock admission cannot sample', () async {
    final s = Sample();
    final release = Completer<void>();
    final blocker = s.lock.synchronized(() => release.future);
    await pumpEventQueue();
    await expectLater(s.gather(budget: const Duration(milliseconds: 20)),
        throwsA(isA<HdrDecoderReviewTimeout>()));
    s.elapsed = const Duration(milliseconds: 30);
    release.complete();
    await blocker;
    await pumpEventQueue();
    expect(s.reads, isEmpty);
  });
  test('superseded sampling cannot proceed after await', () async {
    final s = Sample();
    s.onRead = (p) async {
      s.current = false;
      return s.props[p] ?? '';
    };
    await expectLater(s.gather(), throwsA(isA<HdrDecoderReviewFailure>()));
    expect(s.reads, ['path']);
  });
  test('open locks epoch and entry before external same URI open', () async {
    final lock = Lock();
    var epoch = 9;
    var entry = '12';
    final entered = Completer<void>();
    final release = Completer<void>();
    final opened = captureDecoderOpenUnderLock(
        lock: lock,
        mediaUri: 'test://same',
        fileLoadedEpoch: () => epoch,
        openWithoutLock: () async {
          entered.complete();
          await release.future;
        },
        readProperty: (p) async => p.endsWith('/id') ? entry : 'test://same',
        isCurrent: () => true);
    await entered.future;
    final other = lock.synchronized(() async {
      entry = '13';
      epoch++;
    });
    release.complete();
    final own = await opened;
    await other;
    expect(own.openedAfterEpoch, 9);
    expect(own.playlistEntryId, 12);
    final s = Sample()..epoch = 5;
    await expectLater(s.gather(), throwsA(isA<HdrDecoderReviewFailure>()));
  });
  test('superseded open capture reads no identity after open', () async {
    final lock = Lock();
    var current = true;
    final entered = Completer<void>();
    final release = Completer<void>();
    final reads = <String>[];
    final opened = captureDecoderOpenUnderLock(
      lock: lock,
      mediaUri: 'test://same',
      fileLoadedEpoch: () => 1,
      openWithoutLock: () async {
        entered.complete();
        await release.future;
      },
      readProperty: (property) async {
        reads.add(property);
        return '';
      },
      isCurrent: () => current,
    );
    await entered.future;
    current = false;
    release.complete();
    await expectLater(opened, throwsA(isA<HdrDecoderReviewFailure>()));
    expect(reads, isEmpty);
  });

  test('embed value domain accepts the P1-A observed shape', () async {
    // Positive contract for the mediacodec_embed observation (P1-A measured
    // snapshot): hwdec=mediacodec AND pixelformat=mediacodec pass the plan
    // check — the CPU-frame negative above is not the whole value domain.
    final s = Sample();
    s.props['current-tracks/video/decoder'] = 'h264_mediacodec';
    s.props['current-tracks/video/codec'] = 'h264';
    s.props['video-format'] = 'h264';
    s.props['android-mediacodec-info'] =
        '{"api":1,"mime":"video/avc","codec":"c2.avc","native-dv-active":false}';
    s.props['video-params/hw-pixelformat'] = 'mediacodec';
    s.props['video-params/gamma'] = 'bt.1886';
    s.props['video-params/primaries'] = 'bt.709';
    final facts = await s.gather();
    expect(facts.hwdecCurrent, 'mediacodec');
    expect(facts.decoderObservation!.pixelFormat, 'mediacodec');
    expect(
        () => validateDecoderObservation(
            route(vo: 'mediacodec_embed', hwdec: 'mediacodec'), facts),
        returnsNormally);
    // The same observation still satisfies the texture mediacodec route.
    expect(() => validateDecoderObservation(route(), facts),
        returnsNormally);
  });

  test('embed hwdec and pixelformat first publication completes in-window',
      () async {
    // Embed-specific attach shape: mpv never sees an nv12 CPU frame on this
    // VO, so the settled frame format IS 'mediacodec'. The hwdec mode and the
    // pixel format first-publish in the SAME sampling round while the decoder
    // label is already settled; the publication round resamples and the next
    // consistent pair completes.
    final s = Sample();
    s.props['current-tracks/video/decoder'] = 'h264_mediacodec';
    s.props['current-tracks/video/codec'] = 'h264';
    s.props['video-format'] = 'h264';
    s.props['android-mediacodec-info'] =
        '{"api":1,"mime":"video/avc","codec":"c2.avc","native-dv-active":false}';
    s.props['video-params/gamma'] = 'bt.1886';
    s.props['video-params/primaries'] = 'bt.709';
    var hwdecReads = 0;
    var pixelReads = 0;
    s.onRead = (p) async {
      if (p == 'hwdec-current' && ++hwdecReads == 1) return '';
      if (p == 'video-params/pixelformat' && ++pixelReads == 1) return '';
      return s.props[p] ?? '';
    };
    final facts = await s.gather();
    expect(facts.hwdecCurrent, 'mediacodec');
    expect(facts.decoderObservation!.pixelFormat, 'mediacodec');
    expect(facts.decoderObservation!.decoder, 'h264_mediacodec');
    expect(s.elapsed, greaterThanOrEqualTo(const Duration(milliseconds: 50)),
        reason: 'the publication round must resample, not return');
    expect(
        () => validateDecoderObservation(
            route(vo: 'mediacodec_embed', hwdec: 'mediacodec'), facts),
        returnsNormally);
  });

  test('a pre-attach label with no frame never settles within the budget',
      () async {
    // P0/P1-A device snapshot shape (h264 → h264_mediacodec label churn
    // while the frame format stays unreported): under the single-sample
    // contract this is settling churn; the shared budget fails closed.
    final s = Sample();
    s.props['current-tracks/video/codec'] = 'h264';
    s.props['video-format'] = 'h264';
    s.props['android-mediacodec-info'] =
        '{"api":1,"mime":"video/avc","codec":"c2.avc","native-dv-active":false}';
    s.props['video-params/gamma'] = 'bt.1886';
    s.props['video-params/primaries'] = 'bt.709';
    s.props['video-params/pixelformat'] = '';
    var decoderReads = 0;
    s.onRead = (p) async {
      if (p == 'current-tracks/video/decoder') {
        return ++decoderReads == 1 ? 'h264' : 'h264_mediacodec';
      }
      return s.props[p] ?? '';
    };
    await expectLater(s.gather(), throwsA(isA<HdrDecoderReviewTimeout>()));
  });

  test('cross-round attach settles with the embed hwdec publication', () async {
    // mediacodec+mediacodec variant of the settled attach shape (the
    // registered case is the copy+nv12 combination): early rounds register
    // the bare h264 label while hwdec-current and the frame format are still
    // unpublished; the settling round carries the label suffix publication
    // AND the hwdec first publication in one window with the IDENTICAL
    // MediaCodec configuration; the frame format settles as 'mediacodec'
    // (mpv never sees nv12 on the embed VO). The full facts pass the embed
    // plan check.
    final s = Sample();
    s.props['current-tracks/video/codec'] = 'h264';
    s.props['video-format'] = 'h264';
    s.props['android-mediacodec-info'] =
        '{"api":1,"mime":"video/avc","codec":"c2.avc","native-dv-active":false}';
    s.props['video-params/gamma'] = 'bt.1886';
    s.props['video-params/primaries'] = 'bt.709';
    var decoderReads = 0;
    var hwdecReads = 0;
    var pixelReads = 0;
    s.onRead = (p) async {
      if (p == 'current-tracks/video/decoder' && ++decoderReads <= 3) {
        return 'h264';
      }
      if (p == 'hwdec-current' && ++hwdecReads <= 3) return '';
      if (p == 'video-params/pixelformat' && ++pixelReads <= 4) return '';
      if (p == 'current-tracks/video/decoder') return 'h264_mediacodec';
      return s.props[p] ?? '';
    };
    final facts = await s.gather(budget: const Duration(seconds: 3));
    expect(facts.decoderObservation!.decoder, 'h264_mediacodec');
    expect(facts.hwdecCurrent, 'mediacodec');
    expect(facts.decoderObservation!.pixelFormat, 'mediacodec');
    expect(
        () => validateDecoderObservation(
            route(vo: 'mediacodec_embed', hwdec: 'mediacodec'), facts),
        returnsNormally);
  });

  test('surface rebuild republishes hwdec after a dead window and completes',
      () async {
    // Surface loss/rebuild: during the dead window hwdec-current is reset
    // ('', never registered) while the stale pre-teardown frame params
    // (yuv420p) are still reported; the rebuilt output republishes
    // '' → 'mediacodec' (first publication) and the frame format switches to
    // 'mediacodec' across rounds. The review completes on the settled state
    // and the embed plan check accepts it.
    final s = Sample();
    s.props['current-tracks/video/decoder'] = 'h264_mediacodec';
    s.props['current-tracks/video/codec'] = 'h264';
    s.props['video-format'] = 'h264';
    s.props['android-mediacodec-info'] =
        '{"api":1,"mime":"video/avc","codec":"c2.avc","native-dv-active":false}';
    s.props['video-params/gamma'] = 'bt.1886';
    s.props['video-params/primaries'] = 'bt.709';
    var hwdecReads = 0;
    var pixelReads = 0;
    s.onRead = (p) async {
      if (p == 'hwdec-current' && ++hwdecReads <= 3) return '';
      if (p == 'video-params/pixelformat' && ++pixelReads <= 4) {
        return 'yuv420p';
      }
      return s.props[p] ?? '';
    };
    final facts = await s.gather(budget: const Duration(seconds: 3));
    expect(facts.hwdecCurrent, 'mediacodec');
    expect(facts.decoderObservation!.pixelFormat, 'mediacodec');
    expect(
        () => validateDecoderObservation(
            route(vo: 'mediacodec_embed', hwdec: 'mediacodec'), facts),
        returnsNormally);
  });

  test('a transient embed hwdec disappearance settles back and completes',
      () async {
    // Disappearance direction re-run on the embed value domain: under the
    // single-sample contract a transient empty window is settling churn.
    final s = Sample();
    s.props['current-tracks/video/decoder'] = 'h264_mediacodec';
    s.props['current-tracks/video/codec'] = 'h264';
    s.props['video-format'] = 'h264';
    s.props['android-mediacodec-info'] =
        '{"api":1,"mime":"video/avc","codec":"c2.avc","native-dv-active":false}';
    s.props['video-params/gamma'] = 'bt.1886';
    s.props['video-params/primaries'] = 'bt.709';
    var hwdecReads = 0;
    s.onRead = (p) async {
      if (p == 'hwdec-current' && ++hwdecReads == 2) return '';
      return s.props[p] ?? '';
    };
    final facts = await s.gather(budget: const Duration(seconds: 2));
    expect(facts.hwdecCurrent, 'mediacodec');
  });
}
