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
    test('A/B mixed snapshot rejects $key', () async {
      final s = Sample();
      var n = 0;
      s.onRead = (p) async {
        if (p == key && ++n == 2) return 'different';
        return s.props[p] ?? '';
      };
      await expectLater(s.gather(), throwsA(isA<HdrDecoderReviewFailure>()));
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
    expect(s.elapsed, const Duration(milliseconds: 50));
    expect(facts.decoderObservation!.pixelFormat, 'mediacodec');
  });

  test('observed decoder cannot change between first-frame polling rounds',
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
    await expectLater(s.gather(), throwsA(isA<HdrDecoderReviewFailure>()));
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
    final facts = await s.gather(budget: const Duration(seconds: 3));
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
    await expectLater(
        s.gather(budget: const Duration(milliseconds: 200)),
        throwsA(isA<HdrDecoderReviewTimeout>()));
  });

  test('registered baseline rejects unsuffixed drift while frame-less',
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
    await expectLater(s.gather(budget: const Duration(seconds: 1)),
        throwsA(isA<HdrDecoderReviewFailure>().having(
            (error) => error.detail, 'detail', contains('Observed'))));
  });

  test('pre-ready halves with differing components are never retried clean',
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
    await expectLater(s.gather(), throwsA(isA<HdrDecoderReviewFailure>()));
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

  test('registered hwdec baseline rejects later mode drift while pre-ready',
      () async {
    final s = Sample();
    var hwdecReads = 0;
    s.props['video-params/pixelformat'] = '';
    s.props['current-tracks/video/decoder'] = 'hevc';
    s.onRead = (p) async {
      if (p == 'hwdec-current' && ++hwdecReads > 34) return 'surfacetexture';
      return s.props[p] ?? '';
    };
    await expectLater(s.gather(budget: const Duration(seconds: 1)),
        throwsA(isA<HdrDecoderReviewFailure>().having(
            (error) => error.detail, 'detail', contains('Observed'))));
  });

  test('source drift inside the publication window is rejected immediately',
      () async {
    final s = Sample();
    var hwdecReads = 0;
    s.props['video-params/pixelformat'] = '';
    s.props['current-tracks/video/decoder'] = 'hevc';
    s.onRead = (p) async {
      if (p == 'hwdec-current' && ++hwdecReads > 20) s.epoch++;
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
    final facts = await s.gather(budget: const Duration(seconds: 3));
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
    final facts = await s.gather(budget: const Duration(seconds: 3));
    expect(facts.decoderObservation!.decoder, 'hevc_mediacodec');
  });

  test('a complete snapshot that violates the plan is still rejected', () async {
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
    final pending = Completer<String>();
    s.onRead = (_) => pending.future;
    await expectLater(s.gather(budget: const Duration(milliseconds: 20)),
        throwsA(isA<HdrDecoderReviewTimeout>()));
    pending.complete('test://same');
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
}
