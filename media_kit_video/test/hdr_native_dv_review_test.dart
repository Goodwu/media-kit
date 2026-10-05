import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' show FileLoadedRecord;
import 'package:media_kit_video/src/hdr/hdr_native_dv_option_owner.dart';
import 'package:media_kit_video/src/hdr/hdr_native_dv_review.dart';
import 'package:media_kit_video/src/hdr/hdr_native_dv_review_evidence.dart';
import 'package:media_kit_video/src/hdr/hdr_open_plan.dart';
import 'package:media_kit_video/src/video_controller/android_video_controller/platform_surface_release.dart';
import 'package:synchronized/synchronized.dart';

const dvConfiguration =
    '{"api":1,"mime":"video/dolby-vision","codec":"OMX.qcom.video.decoder.dolby-vision","native-dv-active":true}';

class Fixture {
  final lock = Lock();
  final player = Object();
  final controller = Object();
  late HdrOptionSourceIdentity source = identity(path: '', entry: '', epoch: 0);
  late HdrOptionSourceIdentity expected;
  late HdrNativeDvOutputSnapshot? output = surface();
  final values = <String, String>{
    'vd-lavc-o': '',
    'mediacodec-embed-render-mode': 'boolean',
    'android-mediacodec-info': dvConfiguration,
    'hwdec-current': 'mediacodec',
    'video-format': 'hevc',
    'current-tracks/video/codec': 'hevc',
    'current-tracks/video/dolby-vision-profile': '5',
    'current-tracks/video/dolby-vision-compatibility-id': '0',
    'current-tracks/video/dolby-vision-el-present': '0',
    'video-params/hdr-vivid': 'no',
  };
  int writes = 0;
  int propertyReads = 0;
  Duration clock = Duration.zero;
  Duration budget = const Duration(seconds: 1);
  void Function(String)? onRead;
  void Function()? onDelay;
  Future<FileLoadedRecord> Function()? loaded;
  Object? verificationError;
  late final owner = HdrNativeDvOptionOwner(
    readProperty: (name) async => values[name] ?? '',
    setPropertyStrict: (name, value) async {
      writes++;
      values[name] = value;
    },
    readIdentity: () async => source,
  );

  HdrOptionSourceIdentity identity({
    String path = 'test://p5',
    String entry = '7',
    int epoch = 1,
    Object? otherPlayer,
  }) =>
      HdrOptionSourceIdentity(
        player: otherPlayer ?? player,
        path: path,
        playlistEntryId: entry,
        fileLoadedEpoch: epoch,
      );

  HdrNativeDvOutputSnapshot surface({
    Object? otherController,
    int handle = 10,
    int generation = 2,
    int view = 3,
    int javaGeneration = 4,
    int wid = 5,
  }) =>
      HdrNativeDvOutputSnapshot(
        otherController ?? controller,
        AndroidSurfaceAccountId(
          handle: handle,
          generation: generation,
          viewId: view,
          surfaceGeneration: javaGeneration,
          wid: wid,
        ),
      );

  Future<void> initialize() async {
    final stopped = source;
    await owner.begin(
        stoppedIdentity: stopped, vd: 'native_dv=1', renderMode: 'timed');
    source = identity();
    await owner.rebind(stopped, source);
    expected = source;
    writes = 0;
  }

  Future<HdrReviewFacts> review() => gatherNativeDvReviewFacts(
        lock: lock,
        expectedIdentity: expected,
        openedAfterEpoch: 0,
        expectedEntryId: 7,
        verifyOwned: () async {
          if (verificationError != null) throw verificationError!;
          if (owner.identity != expected) throw StateError('owner changed');
          await owner.verify();
        },
        readIdentity: () async => source,
        waitForFileLoadedEntry: (_, __) =>
            loaded?.call() ?? Future.value(const FileLoadedRecord(1, 7)),
        readOutput: () => output,
        readProperty: (name) async {
          propertyReads++;
          final result = values[name] ?? '';
          onRead?.call(name);
          return result;
        },
        latestVideoParams: () => null,
        budget: budget,
        monotonicNow: () => clock,
        delay: (duration) async {
          clock += duration;
          onDelay?.call();
        },
      );
}

TypeMatcher<HdrNativeDvReviewFailure> failure(
        HdrNativeDvReviewFailureKind kind) =>
    isA<HdrNativeDvReviewFailure>().having((e) => e.kind, 'kind', kind);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('production review binds actual config to owned source/full output',
      () async {
    final f = Fixture();
    await f.initialize();
    final facts = await f.review();
    final evidence = facts.nativeDvEvidence!;
    expect(evidence.source, f.expected);
    expect(evidence.loaded.epoch, 1);
    expect(evidence.loaded.playlistEntryId, 7);
    expect(evidence.controller, same(f.controller));
    expect(evidence.output, f.output!.identity);
    expect(evidence.configuration.mime, 'video/dolby-vision');
    expect(evidence.configuration.nativeDvActive, isTrue);
    expect(evidence.hwdecCurrent, 'mediacodec');
    expect(
        facts.dolbyVisionProfile, 5); // Track fact, not actual codec profile.
    expect(facts.dvCompatibilityId, 0);
    expect(facts.dvElPresent, isFalse);
    expect(f.writes, 0);
  });

  for (final change in ['entry', 'epoch', 'player', 'path']) {
    test('rejects same URI or source $change drift inside config snapshot',
        () async {
      final f = Fixture();
      await f.initialize();
      f.onRead = (name) {
        if (name != 'android-mediacodec-info') return;
        f.source = f.identity(
          entry: change == 'entry' ? '8' : '7',
          epoch: change == 'epoch' ? 2 : 1,
          otherPlayer: change == 'player' ? Object() : null,
          path: change == 'path' ? 'test://other' : 'test://p5',
        );
      };
      await expectLater(
          f.review(), throwsA(failure(HdrNativeDvReviewFailureKind.ownership)));
      expect(f.writes, 0);
    });
  }

  for (final change in [
    'handle',
    'generation',
    'view',
    'javaGeneration',
    'wid',
    'controller',
    'null'
  ]) {
    test('rejects output $change drift including recycled Surface address',
        () async {
      final f = Fixture();
      await f.initialize();
      f.onRead = (name) {
        if (name != 'android-mediacodec-info') return;
        f.output = change == 'null'
            ? null
            : f.surface(
                handle: change == 'handle' ? 11 : 10,
                generation: change == 'generation' ? 3 : 2,
                view: change == 'view' ? 4 : 3,
                javaGeneration: change == 'javaGeneration' ? 5 : 4,
                wid: change == 'wid' ? 6 : 5,
                otherController: change == 'controller' ? Object() : null,
              );
      };
      await expectLater(f.review(),
          throwsA(failure(HdrNativeDvReviewFailureKind.outputIdentity)));
    });
  }

  for (final record in [
    const FileLoadedRecord(2, 7),
    const FileLoadedRecord(1, 8),
    const FileLoadedRecord(0, 7),
  ]) {
    test(
        'rejects stale/replacement FILE_LOADED ${record.epoch}/${record.playlistEntryId}',
        () async {
      final f = Fixture();
      await f.initialize();
      f.loaded = () async => record;
      await expectLater(f.review(),
          throwsA(failure(HdrNativeDvReviewFailureKind.fileLoaded)));
      expect(f.propertyReads, 0);
    });
  }

  test('FILE_LOADED waiting does not hold nonreentrant Player lock', () async {
    final f = Fixture();
    await f.initialize();
    f.loaded =
        () => f.lock.synchronized(() async => const FileLoadedRecord(1, 7));
    expect((await f.review()).nativeDvEvidence, isNotNull);
  });

  test('source replacement during FILE_LOADED rejects old config', () async {
    final f = Fixture();
    await f.initialize();
    f.loaded = () async {
      f.source = f.identity(entry: '8', epoch: 2);
      return const FileLoadedRecord(1, 7);
    };
    await expectLater(
        f.review(), throwsA(failure(HdrNativeDvReviewFailureKind.ownership)));
    expect(f.propertyReads, 0);
  });

  test('output replacement during FILE_LOADED rejects existing config',
      () async {
    final f = Fixture();
    await f.initialize();
    f.loaded = () async {
      f.output = f.surface(javaGeneration: 5);
      return const FileLoadedRecord(1, 7);
    };
    await expectLater(f.review(),
        throwsA(failure(HdrNativeDvReviewFailureKind.outputIdentity)));
    expect(f.propertyReads, 0);
  });

  test('delayed output/config initializes under same deadline', () async {
    final f = Fixture();
    await f.initialize();
    f.output = null;
    f.values['android-mediacodec-info'] = '';
    f.values['hwdec-current'] = '';
    f.onDelay = () {
      f.output = f.surface();
      f.values['android-mediacodec-info'] = dvConfiguration;
      f.values['hwdec-current'] = 'mediacodec';
    };
    expect((await f.review()).nativeDvEvidence, isNotNull);
    expect(f.clock, const Duration(milliseconds: 50));
  });

  for (final raw in [
    '{}',
    '{"api":1.0,"mime":"video/dolby-vision","codec":"dv","native-dv-active":true}',
    '{"api":2,"mime":"video/dolby-vision","codec":"dv","native-dv-active":true}',
    '{"api":1,"mime":"video/hevc","codec":"hevc","native-dv-active":false}',
    '{"api":1,"mime":"video/dolby-vision","codec":"dv","native-dv-active":false}',
    '{"api":1,"mime":"video/dolby-vision","codec":"","native-dv-active":true}',
    '{"api":1,"mime":"video/dolby-vision","codec":"dv","native-dv-active":1}',
  ]) {
    test(
        'nonempty contradictory/unsupported configuration fails immediately: $raw',
        () async {
      final f = Fixture();
      await f.initialize();
      f.values['android-mediacodec-info'] = raw;
      await expectLater(f.review(),
          throwsA(failure(HdrNativeDvReviewFailureKind.configuration)));
      expect(f.clock, Duration.zero);
    });
  }

  test('configured software/copy hwdec rejected', () async {
    final f = Fixture();
    await f.initialize();
    f.values['hwdec-current'] = 'mediacodec-copy';
    await expectLater(
        f.review(), throwsA(failure(HdrNativeDvReviewFailureKind.hwdec)));
  });

  for (final change in [
    'unavailable-config',
    'new-codec',
    'unavailable-hwdec'
  ]) {
    test('first snapshot rejects decoder $change during track reads', () async {
      final f = Fixture();
      await f.initialize();
      f.onRead = (name) {
        if (name != 'video-format') return;
        if (change == 'unavailable-config') {
          f.values['android-mediacodec-info'] = '';
        } else if (change == 'new-codec') {
          f.values['android-mediacodec-info'] =
              dvConfiguration.replaceFirst('OMX.qcom', 'other');
        } else {
          f.values['hwdec-current'] = '';
        }
      };
      await expectLater(
          f.review(),
          throwsA(failure(change == 'unavailable-hwdec'
              ? HdrNativeDvReviewFailureKind.hwdec
              : HdrNativeDvReviewFailureKind.configuration)));
      expect(f.clock, Duration.zero);
      expect(f.writes, 0);
    });
  }

  for (final next in ['different-codec', 'unavailable']) {
    test('tail first configured codec stays pinned when next sample is $next',
        () async {
      final f = Fixture();
      await f.initialize();
      f.values['android-mediacodec-info'] = '';
      f.onRead = (name) {
        if (name == 'video-format' && f.clock == Duration.zero) {
          f.values['android-mediacodec-info'] = dvConfiguration;
        }
      };
      f.onDelay = () {
        f.values['android-mediacodec-info'] = next == 'different-codec'
            ? dvConfiguration.replaceFirst('OMX.qcom', 'other')
            : '';
      };
      await expectLater(f.review(),
          throwsA(failure(HdrNativeDvReviewFailureKind.configuration)));
      expect(f.clock, const Duration(milliseconds: 50));
      expect(f.writes, 0);
    });
  }

  test('tail first configured hwdec stays pinned when next sample disappears',
      () async {
    final f = Fixture();
    await f.initialize();
    f.values['hwdec-current'] = '';
    f.onRead = (name) {
      if (name == 'video-format' && f.clock == Duration.zero) {
        f.values['hwdec-current'] = 'mediacodec';
      }
    };
    f.onDelay = () => f.values['hwdec-current'] = '';
    await expectLater(
        f.review(), throwsA(failure(HdrNativeDvReviewFailureKind.hwdec)));
    expect(f.clock, const Duration(milliseconds: 50));
    expect(f.writes, 0);
  });

  test('initial empty head and configured tail needs a new full snapshot',
      () async {
    final f = Fixture();
    await f.initialize();
    f.values['android-mediacodec-info'] = '';
    f.values['hwdec-current'] = '';
    f.onRead = (name) {
      if (name != 'video-format') return;
      f.values['android-mediacodec-info'] = dvConfiguration;
      f.values['hwdec-current'] = 'mediacodec';
    };
    expect((await f.review()).nativeDvEvidence, isNotNull);
    expect(f.clock, const Duration(milliseconds: 50));
    expect(f.propertyReads, 20);
  });

  for (final change in [
    'unavailable-config',
    'new-codec',
    'unavailable-hwdec'
  ]) {
    test('initialized decoder $change is not treated as initial pending',
        () async {
      final f = Fixture();
      await f.initialize();
      f.output = null;
      f.onDelay = () {
        f.output = f.surface();
        if (change == 'unavailable-config') {
          f.values['android-mediacodec-info'] = '';
        } else if (change == 'new-codec') {
          f.values['android-mediacodec-info'] =
              dvConfiguration.replaceFirst('OMX.qcom', 'other');
        } else {
          f.values['hwdec-current'] = '';
        }
      };
      await expectLater(
          f.review(),
          throwsA(failure(change == 'unavailable-hwdec'
              ? HdrNativeDvReviewFailureKind.hwdec
              : HdrNativeDvReviewFailureKind.configuration)));
      expect(f.clock, const Duration(milliseconds: 50));
    });
  }

  test('ownership failure retains exact debt cause and performs no cleanup',
      () async {
    final f = Fixture();
    await f.initialize();
    final original =
        HdrNativeDvOptionFailure(null, {'restore': StateError('debt')});
    f.verificationError = original;
    await expectLater(
        f.review(),
        throwsA(failure(HdrNativeDvReviewFailureKind.ownership)
            .having((dynamic e) => e.cause, 'cause', same(original))));
    expect(f.writes, 0);
    expect(f.owner.active, isTrue);
  });

  test('FILE_LOADED and config polling share total monotonic deadline',
      () async {
    final f = Fixture();
    await f.initialize();
    f.budget = const Duration(milliseconds: 100);
    f.loaded = () async {
      f.clock += const Duration(milliseconds: 75);
      return const FileLoadedRecord(1, 7);
    };
    f.values['android-mediacodec-info'] = '';
    await expectLater(
        f.review(), throwsA(failure(HdrNativeDvReviewFailureKind.timeout)));
    expect(f.clock, const Duration(milliseconds: 100));
    expect(f.propertyReads, 10);
  });

  test('deadline includes property reads; late valid config cannot succeed',
      () async {
    final f = Fixture();
    await f.initialize();
    f.onRead = (_) => f.clock += f.budget;
    await expectLater(
        f.review(), throwsA(failure(HdrNativeDvReviewFailureKind.timeout)));
    expect(f.propertyReads, 1);
  });

  test('deadline includes Player lock admission and prevents late reads',
      () async {
    final f = Fixture();
    await f.initialize();
    final release = Completer<void>();
    final entered = Completer<void>();
    final holding = f.lock.synchronized(() {
      entered.complete();
      return release.future;
    });
    await entered.future;
    final reviewing = f.review();
    final assertion = expectLater(
        reviewing, throwsA(failure(HdrNativeDvReviewFailureKind.timeout)));
    f.clock = f.budget;
    release.complete();
    await holding;
    await assertion;
    expect(f.propertyReads, 0);
  });

  test('never completing FILE_LOADED is asynchronously bounded', () async {
    final f = Fixture();
    await f.initialize();
    f.budget = const Duration(milliseconds: 10);
    f.loaded = () => Completer<FileLoadedRecord>().future;
    await expectLater(
        f.review(), throwsA(failure(HdrNativeDvReviewFailureKind.timeout)));
  });
}
