import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' show FileLoadedRecord;
import 'package:media_kit_video/src/hdr/hdr_container_probe_owner.dart';
import 'package:media_kit_video/src/hdr/hdr_decoder_review.dart';
import 'package:media_kit_video/src/hdr/hdr_native_dv_option_owner.dart';
import 'package:synchronized/synchronized.dart';

class _Fixture {
  final lock = Lock();
  final owner = HdrContainerProbeOwner();
  final player = Object();
  final plan = Object();
  final promotedPlan = Object();
  late final nativeOwner = HdrNativeDvOptionOwner(
      readProperty: (name) async => values[name] ?? '',
      readProperties: read,
      currentFileLoadedEpoch: () => epoch,
      setPropertyStrict: write,
      readIdentity: () async => identity);
  final values = <String, String>{
    'path': '',
    'playlist/0/id': '',
    'playlist/0/filename': '',
    'options/track-auto-selection': 'yes',
    'options/lavfi-complex': '',
    'options/demuxer-cache-wait': 'no',
    'options/rebase-start-time': 'yes',
    'options/play-dir': 'forward',
    'pause': 'yes',
    'time-pos/full': '0.000',
    'options/vid': 'auto',
    'options/aid': 'auto',
    'options/sid': 'auto',
    'options/secondary-sid': 'no',
    'track-list/count': '0',
    'vid': 'no',
    'aid': 'no',
    'sid': 'no',
    'secondary-sid': 'no',
    'vd-lavc-o': '',
    'mediacodec-embed-render-mode': 'boolean',
    'mediakit-container-probe-seek-ready': 'no',
    'mediakit-container-probe-seek-target': '',
  };
  final writes = <String>[];
  int epoch = 4;
  int stopCalls = 0;
  int failureAtWrite = -1;
  bool failStop = false;
  bool promotionCurrent = true;
  bool resumeCurrent = true;
  bool videoAvailable = true;
  bool audioAvailable = false;
  int automaticVideoIndex = 0;
  int automaticAudioIndex = 1;
  bool updateSeekPositionReadback = true;
  void Function()? onAuto;
  void Function(String, String)? afterWrite;
  Map<String, String>? nativeBackups;
  Duration? openedStart;
  HdrNativeDvStoppedCapture? lastPromotionStop;

  HdrOptionSourceIdentity get identity => HdrOptionSourceIdentity(
      player: player,
      path: values['path']!,
      playlistEntryId: values['playlist/0/id']!,
      fileLoadedEpoch: epoch);
  Future<List<String>> read(List<String> names) async =>
      names.map((name) => values[name] ?? '').toList();
  Future<void> write(String name, String value) async {
    writes.add('$name=$value');
    values[name] = value;
    if (name == 'time-pos' && updateSeekPositionReadback) {
      values['time-pos/full'] = value;
    }
    if (name == 'time-pos') {
      values['mediakit-container-probe-seek-ready'] = 'yes';
      values['mediakit-container-probe-seek-target'] = value;
    }
    if (name == 'options/vid' && value == 'auto' && videoAvailable) {
      selectTrack('vid', 'video', automaticVideoIndex);
      onAuto?.call();
    }
    if (name == 'options/aid' && value == 'auto' && audioAvailable) {
      selectTrack('aid', 'audio', automaticAudioIndex);
    }
    afterWrite?.call(name, value);
    if (writes.length == failureAtWrite) throw StateError('write ack lost');
  }

  void selectTrack(String direct, String slot, int index) {
    final id = values['track-list/$index/id'] ?? '${index + 1}';
    values.addAll({
      direct: id,
      'current-tracks/$slot/id': id,
      'current-tracks/$slot/selected': 'yes',
      'current-tracks/$slot/main-selection': '0',
      'current-tracks/$slot/decoder': slot == 'video' ? 'mediacodec' : 'lavc',
      'track-list/$index/selected': 'yes',
      'track-list/$index/main-selection': '0',
      'track-list/$index/decoder': slot == 'video' ? 'mediacodec' : 'lavc',
    });
  }

  Future<bool> prepare({bool Function()? current}) {
    nativeBackups = {
      for (final name in [
        'options/track-auto-selection',
        ...hdrContainerProbeSelectorProperties,
      ])
        name: values[name]!,
    };
    return owner.prepare(
        lock: lock,
        plan: plan,
        uri: 'file:///source.mkv',
        eligibleRoute: true,
        isCurrent: current ?? (() => true),
        stoppedIdentity: identity,
        readIdentity: () async => identity,
        readProperties: read);
  }

  void submitEntry({int id = 7, bool loaded = true, bool probe = true}) {
    values['path'] = 'file:///source.mkv';
    values['playlist/0/id'] = '$id';
    values['playlist/0/filename'] = 'file:///source.mkv';
    values['track-list/count'] = '1';
    values['track-list/0/selected'] = 'no';
    values['track-list/0/main-selection'] = '';
    values['track-list/0/id'] = '1';
    values['track-list/0/type'] = 'video';
    if (probe) {
      values['options/track-auto-selection'] = 'no';
      values['options/vid'] = 'auto';
      values['options/aid'] = 'auto';
      values['options/sid'] = owner.automaticSubtitlesFor(plan) ? 'auto' : 'no';
      values['options/secondary-sid'] = 'no';
    }
    if (loaded) epoch = 5;
  }

  void openEntry({Duration? start, bool loaded = true}) {
    openedStart = start;
    owner.markPendingOwnEntry(plan);
    submitEntry(loaded: loaded);
    owner.bindOpenedEntry(
        plan: plan, openedAfterEpoch: 4, playlistEntryId: 7, start: start);
  }

  Future<void> resume() => owner.resume(
      lock: lock,
      plan: plan,
      isCurrent: () => resumeCurrent,
      fileLoadedEpoch: () => epoch,
      readProperties: read,
      writeProperty: write,
      expectedEntryId: 7,
      openedAfterEpoch: 4,
      mediaUri: 'file:///source.mkv');
  void unload() {
    values['path'] = '';
    values['playlist/0/id'] = '';
    values['playlist/0/filename'] = '';
    values['track-list/count'] = '0';
    // Model mpv's native M_SETOPT_BACKUP restoration on entry termination.
    values.addAll(nativeBackups!);
  }

  Future<HdrOptionSourceIdentity> stopOwned() => owner.stopOwnedUnderLock(
      lock: lock,
      stopWithoutLock: () async {
        stopCalls++;
        if (failStop) throw StateError('stop failed');
        unload();
      },
      readIdentity: () async => identity,
      readPlaylistFilename: () async => values['playlist/0/filename']!,
      waitForFileLoadedEntry: (id, before) async =>
          FileLoadedRecord(before + 1, id));
  Future<void> retire(HdrOptionSourceIdentity stopped) =>
      owner.retireAtStoppedBoundary(
          lock: lock,
          stoppedIdentity: stopped,
          readIdentity: () async => identity);

  Future<HdrOptionSourceIdentity> promote() => owner.beginPromotionUnderLock(
      lock: lock,
      oldPlan: plan,
      newPlan: promotedPlan,
      expectedStart: openedStart,
      isCurrent: () => promotionCurrent,
      fileLoadedEpoch: () => epoch,
      readProperties: read,
      writeProperty: write,
      readIdentity: () async => identity,
      nativeOwnershipAcquired: (identity) => nativeOwner.identity == identity,
      takeNativeOwnership: (identity, originalVd, originalMode, verify) =>
          nativeOwner.beginFromDecoderlessProbe(
              entryIdentity: identity,
              originalVd: originalVd,
              originalRenderMode: originalMode,
              verifyDecoderlessProbe: verify,
              vd: 'native_dv=1',
              renderMode: 'timed'));

  void bindPromotedVideo() {
    values.addAll({
      'vid': '1',
      'current-tracks/video/id': '1',
      'current-tracks/video/selected': 'yes',
      'current-tracks/video/main-selection': '0',
      'track-list/0/selected': 'yes',
      'track-list/0/main-selection': '0',
      'track-list/0/decoder': 'mediacodec',
    });
  }

  Future<void> resumePromoted({Future<void> Function()? verifyBoundVideo}) =>
      owner.resumePromotion(
          lock: lock,
          plan: promotedPlan,
          isCurrent: () => true,
          fileLoadedEpoch: () => epoch,
          readProperties: read,
          writeProperty: write,
          expectedEntryId: 7,
          openedAfterEpoch: 4,
          mediaUri: 'file:///source.mkv',
          verifyBoundVideo: verifyBoundVideo ?? (() async {}));

  Future<void> stopPromotion() async {
    final capture = await lock.synchronized(() async {
      await nativeOwner.assertCurrent();
      if (lastPromotionStop != null) {
        await nativeOwner.restore();
        return lastPromotionStop!;
      }
      final before = nativeOwner.identity!;
      stopCalls++;
      if (failStop) throw StateError('stop failed');
      unload();
      final stopped = identity;
      lastPromotionStop =
          HdrNativeDvStoppedCapture(before: before, stopped: stopped);
      await nativeOwner.rebind(before, stopped);
      await nativeOwner.restore();
      return lastPromotionStop!;
    });
    await owner.retireAfterTransferredStop(
        lock: lock, capture: capture, readIdentity: () async => identity);
    lastPromotionStop = null;
  }
}

void main() {
  for (final start in <Duration?>[
    const Duration(seconds: 85),
    Duration.zero,
    null,
    const Duration(hours: 3),
  ]) {
    test('promotion arms raw start $start before any decoder and never reseeks',
        () async {
      final fixture = _Fixture()..updateSeekPositionReadback = false;
      expect(await fixture.prepare(), isTrue);
      fixture.openEntry(start: start);
      final positionReadback = start == const Duration(hours: 3) ? '10.0' : '';
      fixture.values['time-pos/full'] = positionReadback;
      fixture.values['duration'] = '10.0';
      fixture.afterWrite = (name, value) {
        if (name != 'time-pos') return;
        expect(fixture.values['options/track-auto-selection'], 'no');
        expect(fixture.values['vid'], 'no');
        expect(fixture.values['track-list/0/selected'], 'no');
        expect(fixture.values['track-list/0/decoder'], isNull);
        expect(fixture.nativeOwner.identity, fixture.identity);
      };
      await fixture.promote();
      final expected = start == null
          ? <String>[]
          : ['time-pos=${start.inMilliseconds / 1000.0}'];
      expect(fixture.writes.where((entry) => entry.startsWith('time-pos=')),
          expected);
      expect(fixture.values['time-pos/full'], positionReadback,
          reason:
              'clamped/unavailable position getter is not the raw seek target');
      fixture.bindPromotedVideo();
      await fixture.resumePromoted();
      expect(fixture.writes.where((entry) => entry.startsWith('time-pos=')),
          expected,
          reason: 'selector resume must not issue a second seek');
      expect(fixture.writes.where((entry) => entry.startsWith('options/vid=')),
          isEmpty);
    });
  }

  test(
      'missing or invalid native seek capability skips the entire probe read-only',
      () async {
    for (final capability in ['', 'unsupported', 'true']) {
      final fixture = _Fixture()
        ..values['mediakit-container-probe-seek-ready'] = capability;
      expect(await fixture.prepare(), isFalse);
      expect(fixture.owner.canPromote(fixture.plan), isFalse);
      await expectLater(
          fixture.promote(), throwsA(isA<HdrDecoderReviewFailure>()));
      expect(fixture.writes, isEmpty);
      expect(fixture.nativeOwner.active, isFalse);
      expect(fixture.owner.active, isFalse);
    }
  });

  test('early seek requires native ready and the exact unclamped armed target',
      () async {
    for (final bad in [
      'not-ready',
      'missing-ready',
      'missing-target',
      'old-target',
      'clamped-target',
      'nonfinite-target'
    ]) {
      final fixture = _Fixture();
      expect(await fixture.prepare(), isTrue);
      fixture.openEntry(start: const Duration(seconds: 85));
      fixture.afterWrite = (name, value) {
        if (name != 'time-pos') return;
        if (bad == 'not-ready') {
          fixture.values['mediakit-container-probe-seek-ready'] = 'no';
        } else if (bad == 'missing-ready') {
          fixture.values['mediakit-container-probe-seek-ready'] = '';
        } else {
          fixture.values['mediakit-container-probe-seek-target'] = {
            'missing-target': '',
            'old-target': '30.0',
            'clamped-target': '10.0',
            'nonfinite-target': 'NaN',
          }[bad]!;
        }
      };
      await expectLater(
          fixture.promote(), throwsA(isA<HdrDecoderReviewFailure>()),
          reason: bad);
      expect(fixture.writes.where((entry) => entry.startsWith('time-pos=')),
          ['time-pos=85.0']);
      fixture.bindPromotedVideo();
      final writes = List.of(fixture.writes);
      await expectLater(
          fixture.resumePromoted(), throwsA(isA<HdrDecoderReviewFailure>()));
      expect(fixture.writes, writes);
      await fixture.stopPromotion();
      expect(fixture.stopCalls, 1);
    }
  });

  test('failed early seek acknowledgement cannot commit the armed state',
      () async {
    final fixture = _Fixture()..failureAtWrite = 3;
    expect(await fixture.prepare(), isTrue);
    fixture.openEntry(start: const Duration(seconds: 85));
    await expectLater(fixture.promote(), throwsStateError);
    expect(fixture.writes.last, 'time-pos=85.0');
    expect(fixture.nativeOwner.active, isTrue);
    fixture.bindPromotedVideo();
    final writes = List.of(fixture.writes);
    await expectLater(
        fixture.resumePromoted(), throwsA(isA<HdrDecoderReviewFailure>()));
    expect(fixture.writes, writes);
    await fixture.stopPromotion();
    expect(fixture.stopCalls, 1);
  });

  test('cancellation and foreign identity before early seek issue no seek',
      () async {
    for (final drift in ['cancel', 'same-uri-entry', 'epoch']) {
      final fixture = _Fixture();
      expect(await fixture.prepare(), isTrue);
      fixture.openEntry(start: const Duration(seconds: 85));
      fixture.afterWrite = (name, value) {
        if (name != 'mediacodec-embed-render-mode' || value != 'timed') return;
        if (drift == 'cancel') fixture.promotionCurrent = false;
        if (drift == 'same-uri-entry') fixture.values['playlist/0/id'] = '8';
        if (drift == 'epoch') fixture.epoch++;
      };
      await expectLater(fixture.promote(),
          throwsA(anyOf(isA<StateError>(), isA<HdrDecoderReviewFailure>())));
      expect(fixture.writes.where((entry) => entry.startsWith('time-pos=')),
          isEmpty);
      if (drift != 'cancel') {
        final writes = List.of(fixture.writes);
        await expectLater(fixture.stopPromotion(), throwsStateError);
        expect(fixture.stopCalls, 0);
        expect(fixture.writes, writes);
      }
    }
  });

  test(
      'post-seek cancellation or source/decoder drift leaves start uncommitted',
      () async {
    for (final drift in ['cancel', 'same-uri-entry', 'epoch', 'decoder']) {
      final fixture = _Fixture();
      expect(await fixture.prepare(), isTrue);
      fixture.openEntry(start: const Duration(seconds: 85));
      fixture.afterWrite = (name, value) {
        if (name != 'time-pos') return;
        if (drift == 'cancel') fixture.promotionCurrent = false;
        if (drift == 'same-uri-entry') fixture.values['playlist/0/id'] = '8';
        if (drift == 'epoch') fixture.epoch++;
        if (drift == 'decoder') fixture.values['track-list/0/decoder'] = 'lavc';
      };
      await expectLater(
          fixture.promote(), throwsA(isA<HdrDecoderReviewFailure>()));
      expect(fixture.writes.where((entry) => entry.startsWith('time-pos=')),
          ['time-pos=85.0']);
      final writes = List.of(fixture.writes);
      fixture.bindPromotedVideo();
      await expectLater(
          fixture.resumePromoted(), throwsA(isA<HdrDecoderReviewFailure>()));
      expect(fixture.writes, writes);
      if (drift == 'same-uri-entry' || drift == 'epoch') {
        await expectLater(fixture.stopPromotion(), throwsStateError);
        expect(fixture.stopCalls, 0);
      }
    }
  });

  test('promotion preserves SID no, raw start and a single bound video',
      () async {
    final fixture = _Fixture()..values['options/sid'] = 'no';
    expect(await fixture.prepare(), isTrue);
    fixture.openEntry(start: const Duration(milliseconds: 12345));
    expect(fixture.owner.canPromote(fixture.plan), isTrue);
    final identity = await fixture.promote();
    expect(identity, fixture.identity);
    expect(fixture.owner.owns(fixture.plan), isFalse);
    expect(fixture.owner.promotionTransferred(fixture.promotedPlan), isTrue);
    expect(fixture.nativeOwner.identity, identity);
    fixture.bindPromotedVideo();
    var outputChecks = 0;
    await fixture.resumePromoted(verifyBoundVideo: () async => outputChecks++);
    expect(outputChecks, greaterThan(1));
    expect(fixture.values['options/sid'], 'no');
    expect(fixture.values['vid'], '1');
    expect(fixture.values['time-pos/full'], '12.345');
    expect(fixture.writes.where((write) => write.startsWith('options/vid=')),
        isEmpty);
    expect(fixture.writes.where((write) => write.startsWith('options/sid=')),
        isEmpty);
    await expectLater(
        fixture.stopOwned(), throwsA(isA<HdrDecoderReviewFailure>()));
    expect(fixture.stopCalls, 0);
    await fixture.stopPromotion();
    expect(fixture.stopCalls, 1);
    expect(fixture.values['options/sid'], 'no');
    expect(fixture.values['vd-lavc-o'], '');
    expect(fixture.values['mediacodec-embed-render-mode'], 'boolean');
    expect(fixture.owner.active, isFalse);
    expect(fixture.nativeOwner.active, isFalse);
  });

  test('promotion rejects source, epoch, option, pair and decoder drift',
      () async {
    for (final mutation in <void Function(_Fixture)>[
      (f) => f.values['path'] = 'file:///foreign.mkv',
      (f) => f.values['playlist/0/id'] = '8',
      (f) => f.epoch++,
      (f) => f.values['pause'] = 'no',
      (f) => f.values['options/aid'] = '2',
      (f) => f.values['options/sid'] = 'no',
      (f) => f.values['vd-lavc-o'] = 'external=1',
      (f) => f.values['mediacodec-embed-render-mode'] = 'timed',
      (f) => f.values['track-list/0/decoder'] = 'lavc:h264',
      (f) => f.values['track-list/0/selected'] = 'yes',
      (f) => f.values['current-tracks/audio/id'] = '2',
      (f) => f.openedStart = const Duration(seconds: 99),
    ]) {
      final fixture = _Fixture();
      expect(await fixture.prepare(), isTrue);
      fixture.openEntry();
      mutation(fixture);
      await expectLater(
          fixture.promote(), throwsA(isA<HdrDecoderReviewFailure>()));
      expect(fixture.writes, isEmpty);
      expect(fixture.owner.promotionTransferred(fixture.promotedPlan), isFalse);
      expect(fixture.nativeOwner.active, isFalse);
    }
  });

  test('promotion cannot reuse a resumed or non-default native pair intent',
      () async {
    final resumed = _Fixture();
    expect(await resumed.prepare(), isTrue);
    resumed.openEntry();
    await resumed.resume();
    expect(resumed.owner.canPromote(resumed.plan), isFalse);
    for (final entry in <String, String>{
      'vd-lavc-o': 'custom=1',
      'mediacodec-embed-render-mode': 'unknown',
    }.entries) {
      final fixture = _Fixture()..values[entry.key] = entry.value;
      expect(await fixture.prepare(), isTrue);
      fixture.openEntry();
      expect(fixture.owner.canPromote(fixture.plan), isFalse);
      await expectLater(
          fixture.promote(), throwsA(isA<HdrDecoderReviewFailure>()));
      expect(fixture.writes, isEmpty);
    }
  });

  test('each promotion write failure keeps debt until native owned stop',
      () async {
    // Two native pair writes, five selector/flag writes and the raw seek.
    for (var failure = 1; failure <= 8; failure++) {
      final fixture = _Fixture()..failureAtWrite = failure;
      expect(await fixture.prepare(), isTrue);
      fixture.openEntry(start: const Duration(seconds: 37));
      await expectLater(() async {
        await fixture.promote();
        fixture.bindPromotedVideo();
        await fixture.resumePromoted();
      }(), throwsStateError, reason: 'write $failure');
      expect(fixture.nativeOwner.active, isTrue);
      expect(fixture.owner.promotionTransferred(fixture.promotedPlan), isTrue);
      expect(fixture.stopCalls, 0);
      await fixture.stopPromotion();
      expect(fixture.stopCalls, 1);
      expect(fixture.owner.active, isFalse);
      expect(fixture.nativeOwner.active, isFalse);
      expect(fixture.values['vd-lavc-o'], '');
      expect(fixture.values['options/sid'], 'auto');
    }
  });

  test('native admission rejection keeps the original probe stop owner',
      () async {
    final fixture = _Fixture();
    expect(await fixture.prepare(), isTrue);
    fixture.openEntry();
    await expectLater(
        fixture.owner.beginPromotionUnderLock(
            lock: fixture.lock,
            oldPlan: fixture.plan,
            newPlan: fixture.promotedPlan,
            expectedStart: null,
            isCurrent: () => true,
            fileLoadedEpoch: () => fixture.epoch,
            readProperties: fixture.read,
            writeProperty: fixture.write,
            readIdentity: () async => fixture.identity,
            nativeOwnershipAcquired: (identity) =>
                fixture.nativeOwner.identity == identity,
            takeNativeOwnership: (_, __, ___, ____) async {
              throw StateError('native owner busy before acquisition');
            }),
        throwsStateError);
    expect(fixture.owner.owns(fixture.plan), isTrue);
    expect(fixture.owner.promotionTransferred(fixture.promotedPlan), isFalse);
    expect(fixture.nativeOwner.active, isFalse);
    expect(fixture.writes, isEmpty);
    await fixture.retire(await fixture.stopOwned());
    expect(fixture.stopCalls, 1);
    expect(fixture.owner.active, isFalse);
  });

  test('promotion stop failure retains ownership for a safe retry', () async {
    final fixture = _Fixture();
    expect(await fixture.prepare(), isTrue);
    fixture.openEntry();
    await fixture.promote();
    fixture.bindPromotedVideo();
    await fixture.resumePromoted();
    fixture.failStop = true;
    await expectLater(fixture.stopPromotion(), throwsStateError);
    expect(fixture.nativeOwner.identity, fixture.identity);
    expect(fixture.owner.active, isTrue);
    expect(fixture.values['vd-lavc-o'], 'native_dv=1');
    fixture.failStop = false;
    await fixture.stopPromotion();
    expect(fixture.stopCalls, 2);
    expect(fixture.owner.active, isFalse);
  });

  test('promotion restore failure keeps the stopped proof for retry', () async {
    final fixture = _Fixture();
    expect(await fixture.prepare(), isTrue);
    fixture.openEntry();
    await fixture.promote();
    fixture.bindPromotedVideo();
    await fixture.resumePromoted();
    fixture.failureAtWrite = fixture.writes.length + 1;
    await expectLater(
        fixture.stopPromotion(), throwsA(isA<HdrNativeDvOptionFailure>()));
    expect(fixture.stopCalls, 1);
    expect(fixture.identity.path, isEmpty);
    expect(fixture.owner.active, isTrue);
    expect(fixture.nativeOwner.active, isTrue);
    await fixture.stopPromotion();
    expect(fixture.stopCalls, 1);
    expect(fixture.owner.active, isFalse);
    expect(fixture.nativeOwner.active, isFalse);
    expect(fixture.values['vd-lavc-o'], '');
    expect(fixture.values['mediacodec-embed-render-mode'], 'boolean');
  });

  test('promoted output failure and foreign replacement cannot resume or stop',
      () async {
    final fixture = _Fixture();
    expect(await fixture.prepare(), isTrue);
    fixture.openEntry();
    await fixture.promote();
    fixture.bindPromotedVideo();
    final writes = List.of(fixture.writes);
    await expectLater(fixture.resumePromoted(verifyBoundVideo: () async {
      throw StateError('owned native output is not bound');
    }), throwsStateError);
    expect(fixture.writes, writes);
    fixture.values['playlist/0/id'] = '8';
    await expectLater(
        fixture.resumePromoted(), throwsA(isA<HdrDecoderReviewFailure>()));
    await expectLater(fixture.stopPromotion(), throwsStateError);
    expect(fixture.stopCalls, 0);
    expect(fixture.writes, writes);
    expect(fixture.owner.active, isTrue);
    expect(fixture.nativeOwner.active, isTrue);
  });

  test('promotion retirement rejects an unrelated stopped capture', () async {
    final fixture = _Fixture();
    expect(await fixture.prepare(), isTrue);
    fixture.openEntry();
    final before = await fixture.promote();
    fixture.unload();
    final foreignBefore = HdrOptionSourceIdentity(
        player: fixture.player,
        path: before.path,
        playlistEntryId: '8',
        fileLoadedEpoch: before.fileLoadedEpoch);
    await expectLater(
        fixture.owner.retireAfterTransferredStop(
            lock: fixture.lock,
            capture: HdrNativeDvStoppedCapture(
                before: foreignBefore, stopped: fixture.identity),
            readIdentity: () async => fixture.identity),
        throwsA(isA<HdrDecoderReviewFailure>()));
    expect(fixture.owner.active, isTrue);
    expect(fixture.nativeOwner.active, isTrue);
  });

  test('prepare is read-only and default eligibility failures are no-ops',
      () async {
    final fixture = _Fixture();
    expect(await fixture.prepare(), isTrue);
    expect(fixture.writes, isEmpty);
    expect(fixture.values['options/track-auto-selection'], 'yes');
    for (final entry in <String, String>{
      'options/vid': '3',
      'options/sid': '3',
      'options/track-auto-selection': 'no',
      'options/lavfi-complex': '[aid1]anull[ao]',
      'options/demuxer-cache-wait': 'yes',
      'options/rebase-start-time': 'no',
      'options/play-dir': 'backward',
    }.entries) {
      final altered = _Fixture()..values[entry.key] = entry.value;
      expect(await altered.prepare(), isFalse, reason: entry.key);
      expect(altered.owner.active, isFalse);
      expect(altered.writes, isEmpty);
    }
  });

  test('admission rechecks defaults and uses ordinary open after option drift',
      () async {
    final fixture = _Fixture();
    expect(await fixture.prepare(), isTrue);
    fixture.values['options/aid'] = '2';
    bool? probed;
    await fixture.owner.captureOpenUnderLock(
        lock: fixture.lock,
        plan: fixture.plan,
        start: null,
        isCurrent: () => true,
        openWithoutLock: (probe) async {
          probed = probe;
          fixture.submitEntry(probe: probe);
        },
        readIdentity: () async => fixture.identity,
        readProperties: fixture.read);
    expect(probed, isFalse);
    expect(fixture.owner.active, isFalse);
    expect(fixture.values['options/aid'], '2');
  });

  test('disabled subtitles stay disabled through probe, resume and native stop',
      () async {
    final fixture = _Fixture()..values['options/sid'] = 'no';
    expect(await fixture.prepare(), isTrue);
    expect(fixture.owner.automaticSubtitlesFor(fixture.plan), isFalse);
    bool? automaticSubtitles;
    await fixture.owner.captureOpenUnderLock(
      lock: fixture.lock,
      plan: fixture.plan,
      start: null,
      isCurrent: () => true,
      openWithoutLock: (probe) async {
        expect(probe, isTrue);
        automaticSubtitles = fixture.owner.automaticSubtitlesFor(fixture.plan);
        fixture.submitEntry(probe: probe);
      },
      readIdentity: () async => fixture.identity,
      readProperties: fixture.read,
    );
    expect(automaticSubtitles, isFalse);
    expect(fixture.values['options/sid'], 'no');
    await fixture.resume();
    expect(fixture.values['options/sid'], 'no');
    expect(fixture.writes.where((write) => write.startsWith('options/sid=')),
        isEmpty);
    expect(fixture.owner.probing(fixture.plan), isFalse);
    final writes = List.of(fixture.writes);
    final stopped = await fixture.stopOwned();
    await fixture.retire(stopped);
    expect(fixture.values['options/sid'], 'no');
    expect(fixture.writes, writes);
    expect(fixture.owner.active, isFalse);
  });

  test('subtitle changes before admission cannot reuse an auto subtitle intent',
      () async {
    final fixture = _Fixture();
    expect(await fixture.prepare(), isTrue);
    fixture.values['options/sid'] = 'no';
    bool? probed;
    await fixture.owner.captureOpenUnderLock(
      lock: fixture.lock,
      plan: fixture.plan,
      start: null,
      isCurrent: () => true,
      openWithoutLock: (probe) async {
        probed = probe;
        fixture.submitEntry(probe: probe);
      },
      readIdentity: () async => fixture.identity,
      readProperties: fixture.read,
    );
    expect(probed, isFalse);
    expect(fixture.values['options/sid'], 'no');
    expect(fixture.owner.active, isFalse);
    expect(fixture.writes, isEmpty);
  });

  test('disabled subtitle entry must read back disabled before resume',
      () async {
    final fixture = _Fixture()..values['options/sid'] = 'no';
    expect(await fixture.prepare(), isTrue);
    fixture.openEntry();
    fixture.values['options/sid'] = 'auto';
    await expectLater(
        fixture.resume(), throwsA(isA<HdrDecoderReviewFailure>()));
    expect(fixture.writes, isEmpty);
    await fixture.retire(await fixture.stopOwned());
    expect(fixture.values['options/sid'], 'no');
  });

  test(
      'cancellation before admission opens nothing and retires read-only intent',
      () async {
    final fixture = _Fixture();
    expect(await fixture.prepare(), isTrue);
    var opens = 0;
    await expectLater(
      fixture.owner.captureOpenUnderLock(
        lock: fixture.lock,
        plan: fixture.plan,
        start: null,
        isCurrent: () => false,
        openWithoutLock: (_) async => opens++,
        readIdentity: () async => fixture.identity,
        readProperties: fixture.read,
      ),
      throwsA(isA<HdrDecoderReviewFailure>()),
    );
    expect(opens, 0);
    await fixture.retire(await fixture.stopOwned());
    expect(fixture.stopCalls, 0);
    expect(fixture.writes, isEmpty);
  });

  test('negative actual start bypasses probe without changing global options',
      () async {
    final fixture = _Fixture();
    expect(await fixture.prepare(), isTrue);
    bool? probed;
    await fixture.owner.captureOpenUnderLock(
        lock: fixture.lock,
        plan: fixture.plan,
        start: const Duration(seconds: -2),
        isCurrent: () => true,
        openWithoutLock: (probe) async {
          probed = probe;
          fixture.submitEntry(probe: probe);
        },
        readIdentity: () async => fixture.identity,
        readProperties: fixture.read);
    expect(probed, isFalse);
    expect(fixture.values['options/track-auto-selection'], 'yes');
    expect(fixture.writes, isEmpty);
  });

  test(
      'resume uses entry options, allows real auto selection, retains source proof',
      () async {
    final fixture = _Fixture();
    expect(await fixture.prepare(), isTrue);
    fixture.openEntry();
    await fixture.resume();
    expect(fixture.writes, [
      'options/vid=no',
      'options/aid=no',
      'options/sid=no',
      'options/vid=auto',
      'options/aid=auto',
      'options/sid=auto',
      'options/track-auto-selection=yes',
    ]);
    expect(fixture.values['track-list/0/selected'], 'yes');
    expect(fixture.owner.active, isTrue);
    expect(fixture.owner.probing(fixture.plan), isFalse);
    final stopped = await fixture.stopOwned();
    await fixture.retire(stopped);
    expect(fixture.owner.active, isFalse);
  });

  for (final start in <Duration?>[
    const Duration(seconds: 85),
    Duration.zero,
    null,
    const Duration(hours: 3),
  ]) {
    test(
        'ordinary resume arms $start once before activation and restores flag last',
        () async {
      final fixture = _Fixture()..updateSeekPositionReadback = false;
      expect(await fixture.prepare(), isTrue);
      fixture.openEntry(start: start);
      fixture.values['time-pos/full'] = '10.0';
      fixture.values['duration'] = '10.0';
      fixture.afterWrite = (name, value) {
        if (name == 'time-pos') {
          expect(fixture.values['options/track-auto-selection'], 'no');
          expect(fixture.values['vid'], 'no');
          expect(fixture.values['aid'], 'no');
          expect(fixture.values['options/vid'], 'no');
          expect(fixture.values['options/aid'], 'no');
          expect(fixture.values['options/sid'], 'no');
        }
        if (name == 'options/vid' && value == 'auto') {
          expect(fixture.values['options/track-auto-selection'], 'no');
          expect(
              fixture.writes.where((write) => write.startsWith('time-pos=')),
              start == null
                  ? <String>[]
                  : ['time-pos=${start.inMilliseconds / 1000.0}']);
        }
      };
      await fixture.resume();
      expect(fixture.writes, [
        'options/vid=no',
        'options/aid=no',
        'options/sid=no',
        if (start != null) 'time-pos=${start.inMilliseconds / 1000.0}',
        'options/vid=auto',
        'options/aid=auto',
        'options/sid=auto',
        'options/track-auto-selection=yes',
      ]);
      expect(fixture.values['time-pos/full'], '10.0');
      expect(fixture.values['vid'], '1');
      expect(fixture.owner.probing(fixture.plan), isFalse);
    });
  }

  test(
      'ordinary resume supports audio-only without requiring a video selection',
      () async {
    final fixture = _Fixture()
      ..videoAvailable = false
      ..audioAvailable = true
      ..automaticAudioIndex = 0;
    expect(await fixture.prepare(), isTrue);
    fixture.openEntry(start: const Duration(seconds: 85));
    fixture.values['track-list/0/type'] = 'audio';
    await fixture.resume();
    expect(fixture.values['vid'], 'no');
    expect(fixture.values['aid'], '1');
    expect(fixture.writes.indexOf('time-pos=85.0'),
        lessThan(fixture.writes.indexOf('options/aid=auto')));
    expect(fixture.writes.last, 'options/track-auto-selection=yes');
    expect(fixture.owner.probing(fixture.plan), isFalse);
  });

  test('ordinary resume preserves automatic choice among multiple video tracks',
      () async {
    final fixture = _Fixture()..automaticVideoIndex = 1;
    expect(await fixture.prepare(), isTrue);
    fixture.openEntry(start: const Duration(seconds: 85));
    fixture.values.addAll({
      'track-list/count': '2',
      'track-list/1/id': '2',
      'track-list/1/type': 'video',
      'track-list/1/selected': 'no',
    });
    await fixture.resume();
    expect(fixture.values['vid'], '2');
    expect(fixture.values['track-list/0/selected'], 'no');
    expect(fixture.values['track-list/1/selected'], 'yes');
    expect(fixture.writes.where((write) => write.startsWith('options/vid=')),
        ['options/vid=no', 'options/vid=auto']);
  });

  test('ordinary seek failure or invalid ready/target never enables a decoder',
      () async {
    for (final failure in ['ack', 'ready', 'old-target']) {
      final fixture = _Fixture();
      expect(await fixture.prepare(), isTrue);
      fixture.openEntry(start: const Duration(seconds: 85));
      if (failure == 'ack') fixture.failureAtWrite = 4;
      fixture.afterWrite = (name, value) {
        if (name != 'time-pos') return;
        if (failure == 'ready') {
          fixture.values['mediakit-container-probe-seek-ready'] = 'no';
        }
        if (failure == 'old-target') {
          fixture.values['mediakit-container-probe-seek-target'] = '30.0';
        }
      };
      await expectLater(fixture.resume(),
          throwsA(anyOf(isA<StateError>(), isA<HdrDecoderReviewFailure>())));
      expect(fixture.writes.where((write) => write.endsWith('=auto')), isEmpty);
      expect(fixture.values['vid'], 'no');
      final writes = List.of(fixture.writes);
      await fixture.retire(await fixture.stopOwned());
      expect(fixture.stopCalls, 1);
      expect(fixture.writes, writes);
    }
  });

  test(
      'ordinary resume cancellation and foreign entry drift stop further activation',
      () async {
    for (final phase in ['before-seek', 'after-seek', 'after-video']) {
      for (final drift in ['cancel', 'same-uri-entry', 'epoch']) {
        final fixture = _Fixture();
        expect(await fixture.prepare(), isTrue);
        fixture.openEntry(start: const Duration(seconds: 85));
        fixture.afterWrite = (name, value) {
          final matches = (phase == 'before-seek' &&
                  name == 'options/sid' &&
                  value == 'no') ||
              (phase == 'after-seek' && name == 'time-pos') ||
              (phase == 'after-video' &&
                  name == 'options/vid' &&
                  value == 'auto');
          if (!matches) return;
          if (drift == 'cancel') fixture.resumeCurrent = false;
          if (drift == 'same-uri-entry') fixture.values['playlist/0/id'] = '8';
          if (drift == 'epoch') fixture.epoch++;
        };
        await expectLater(
            fixture.resume(), throwsA(isA<HdrDecoderReviewFailure>()));
        expect(fixture.writes.contains('options/track-auto-selection=yes'),
            isFalse);
        final writes = List.of(fixture.writes);
        if (drift == 'cancel') {
          await fixture.retire(await fixture.stopOwned());
          expect(fixture.stopCalls, 1);
        } else {
          await expectLater(
              fixture.stopOwned(),
              throwsA(
                  anyOf(isA<StateError>(), isA<HdrDecoderReviewFailure>())));
          expect(fixture.stopCalls, 0);
        }
        expect(fixture.writes, writes);
      }
    }
  });

  test('each ordinary resume write failure retains owned native backup cleanup',
      () async {
    for (var failure = 1; failure <= 8; failure++) {
      final fixture = _Fixture()..failureAtWrite = failure;
      expect(await fixture.prepare(), isTrue);
      fixture.openEntry(start: const Duration(seconds: 85));
      await expectLater(fixture.resume(), throwsStateError);
      final writes = List.of(fixture.writes);
      await fixture.retire(await fixture.stopOwned());
      expect(fixture.stopCalls, 1);
      expect(fixture.owner.active, isFalse);
      expect(fixture.writes, writes);
      expect(fixture.values['options/track-auto-selection'], 'yes');
    }
  });

  test('nonnegative raw start is rearmed, including values beyond duration',
      () async {
    for (final start in [
      const Duration(milliseconds: 12345),
      const Duration(seconds: 101)
    ]) {
      final fixture = _Fixture();
      expect(await fixture.prepare(), isTrue);
      fixture.openEntry(start: start);
      fixture.values['time-pos/full'] = '12.345678';
      fixture.onAuto = () => fixture.values['time-pos/full'] = '12.366700';
      await fixture.resume();
      final seek = 'time-pos=${start.inMilliseconds / 1000.0}';
      expect(fixture.writes.where((write) => write.startsWith('time-pos=')),
          [seek]);
      expect(fixture.writes.indexOf(seek),
          lessThan(fixture.writes.indexOf('options/vid=auto')));
    }
    final nullStart = _Fixture();
    expect(await nullStart.prepare(), isTrue);
    nullStart.openEntry();
    nullStart.values['time-pos/full'] = '';
    await nullStart.resume();
    expect(nullStart.writes.where((write) => write.startsWith('time-pos=')),
        isEmpty);
  });

  test('unavailable position getter is not mistaken for native raw seek proof',
      () async {
    final fixture = _Fixture();
    expect(await fixture.prepare(), isTrue);
    fixture.openEntry(start: const Duration(seconds: 3));
    fixture.values['time-pos/full'] = 'nan';
    fixture.updateSeekPositionReadback = false;
    await fixture.resume();
    expect(fixture.values['time-pos/full'], 'nan');
    expect(fixture.writes.where((write) => write.startsWith('time-pos=')),
        ['time-pos=3.0']);
    expect(fixture.owner.active, isTrue);
  });

  test('loaded option readback must prove all native per-entry options applied',
      () async {
    for (final entry in <String, String>{
      'options/track-auto-selection': 'yes',
      'options/aid': '3',
      'options/lavfi-complex': '[aid1]anull[ao]',
      'options/demuxer-cache-wait': 'yes',
      'options/rebase-start-time': 'no',
      'options/play-dir': 'backward',
      'pause': 'no',
    }.entries) {
      final fixture = _Fixture();
      expect(await fixture.prepare(), isTrue);
      fixture.openEntry();
      fixture.values[entry.key] = entry.value;
      await expectLater(
          fixture.resume(), throwsA(isA<HdrDecoderReviewFailure>()));
      expect(fixture.writes, isEmpty, reason: entry.key);
    }
  });

  test('65 or more tracks resume with bounded positive slot evidence',
      () async {
    final fixture = _Fixture();
    expect(await fixture.prepare(), isTrue);
    fixture.openEntry();
    fixture.values['track-list/count'] = '65';
    await fixture.resume();
    expect(fixture.owner.probing(fixture.plan), isFalse);
    for (final entry in <String, String>{
      'vid': '',
      'aid': '2',
      'sid': 'auto',
      'current-tracks/sub2/id': '4',
      'current-tracks/audio/decoder': 'lavc',
      'options/lavfi-complex': '[aid1]anull[ao]',
    }.entries) {
      final altered = _Fixture();
      expect(await altered.prepare(), isTrue);
      altered.openEntry();
      altered.values['track-list/count'] = '65';
      altered.values[entry.key] = entry.value;
      await expectLater(
          altered.resume(), throwsA(isA<HdrDecoderReviewFailure>()));
      expect(altered.writes, isEmpty, reason: entry.key);
    }
  });

  test('resume refuses source and selected track changes before writes',
      () async {
    for (final mutate in <void Function(_Fixture)>[
      (f) => f.values['path'] = 'file:///foreign.mkv',
      (f) => f.epoch++,
      (f) => f.values['track-list/0/selected'] = 'yes',
    ]) {
      final fixture = _Fixture();
      expect(await fixture.prepare(), isTrue);
      fixture.openEntry();
      mutate(fixture);
      await expectLater(
          fixture.resume(), throwsA(isA<HdrDecoderReviewFailure>()));
      expect(fixture.writes, isEmpty);
    }
  });

  test(
      'partial resume failure has no Dart global restore and stops only its entry',
      () async {
    final fixture = _Fixture()..failureAtWrite = 4;
    expect(await fixture.prepare(), isTrue);
    fixture.openEntry();
    await expectLater(fixture.resume(), throwsStateError);
    expect(fixture.owner.active, isTrue);
    final writes = List.of(fixture.writes);
    final stopped = await fixture.stopOwned();
    await fixture.retire(stopped);
    expect(fixture.writes, writes);
    expect(fixture.values['options/track-auto-selection'], 'yes');
    expect(fixture.values['options/aid'], 'auto');
  });

  test('armed cancellation retires without a native stop or setting write',
      () async {
    final fixture = _Fixture();
    expect(await fixture.prepare(), isTrue);
    final stopped = await fixture.stopOwned();
    await fixture.retire(stopped);
    expect(fixture.stopCalls, 0);
    expect(fixture.writes, isEmpty);
  });

  test('armed cleanup never stops a foreign entry', () async {
    final fixture = _Fixture();
    expect(await fixture.prepare(), isTrue);
    fixture.submitEntry(id: 8);
    await expectLater(
        fixture.stopOwned(), throwsA(isA<HdrDecoderReviewFailure>()));
    expect(fixture.stopCalls, 0);
    expect(fixture.owner.active, isTrue);
  });

  test(
      'confirmed cleanup refuses foreign URI, same URI new entry, and epoch drift',
      () async {
    for (final mutate in <void Function(_Fixture)>[
      (f) => f.values['path'] = 'file:///foreign.mkv',
      (f) => f.values['playlist/0/id'] = '8',
      (f) => f.epoch++,
    ]) {
      final fixture = _Fixture();
      expect(await fixture.prepare(), isTrue);
      fixture.openEntry();
      mutate(fixture);
      await expectLater(fixture.stopOwned(), throwsStateError);
      expect(fixture.stopCalls, 0);
      expect(fixture.owner.active, isTrue);
    }
  });

  test(
      'uncaptured pending open cannot adopt another same URI entry or empty source',
      () async {
    final fixture = _Fixture();
    expect(await fixture.prepare(), isTrue);
    fixture.owner.markPendingOwnEntry(fixture.plan);
    fixture.submitEntry(id: 8);
    await expectLater(
        fixture.stopOwned(), throwsA(isA<HdrDecoderReviewFailure>()));
    expect(fixture.stopCalls, 0);
    fixture.unload();
    await expectLater(fixture.retire(fixture.identity),
        throwsA(isA<HdrDecoderReviewFailure>()));
    expect(fixture.owner.active, isTrue);
  });

  test('failed stop retains captured entry for a fenced retry', () async {
    final fixture = _Fixture();
    expect(await fixture.prepare(), isTrue);
    fixture.openEntry();
    fixture.failStop = true;
    await expectLater(
        fixture.stopOwned(), throwsA(isA<HdrDecoderReviewFailure>()));
    fixture.failStop = false;
    final stopped = await fixture.stopOwned();
    expect(fixture.stopCalls, 2);
    await fixture.retire(stopped);
  });

  test('only matching delayed FILE_LOADED can renew an empty own-stop proof',
      () async {
    final fixture = _Fixture();
    expect(await fixture.prepare(), isTrue);
    fixture.openEntry(loaded: false);
    await fixture.stopOwned();
    fixture.epoch = 5;
    final stopped = await fixture.stopOwned();
    expect(fixture.stopCalls, 1);
    expect(stopped.fileLoadedEpoch, 5);
    await fixture.retire(stopped);
  });

  test('capture records accepted entry despite cancellation before returning',
      () async {
    final fixture = _Fixture();
    expect(await fixture.prepare(), isTrue);
    var current = true;
    await expectLater(
        fixture.owner.captureOpenUnderLock(
            lock: fixture.lock,
            plan: fixture.plan,
            start: null,
            isCurrent: () => current,
            openWithoutLock: (probe) async {
              fixture.submitEntry(probe: probe);
              current = false;
            },
            readIdentity: () async => fixture.identity,
            readProperties: fixture.read),
        throwsA(isA<HdrDecoderReviewFailure>()));
    final stopped = await fixture.stopOwned();
    expect(fixture.stopCalls, 1);
    await fixture.retire(stopped);
  });

  test('failed acknowledgement is captured before a later same URI open',
      () async {
    final fixture = _Fixture();
    expect(await fixture.prepare(), isTrue);
    await expectLater(
        fixture.owner.captureOpenUnderLock(
            lock: fixture.lock,
            plan: fixture.plan,
            start: null,
            isCurrent: () => true,
            openWithoutLock: (probe) async {
              fixture.submitEntry(probe: probe);
              throw StateError('ack lost');
            },
            readIdentity: () async => fixture.identity,
            readProperties: fixture.read),
        throwsStateError);
    fixture.values['playlist/0/id'] = '8';
    await expectLater(fixture.stopOwned(), throwsStateError);
    expect(fixture.stopCalls, 0);
  });

  test('failed non-admitted open can retire its unchanged original boundary',
      () async {
    final fixture = _Fixture();
    expect(await fixture.prepare(), isTrue);
    await expectLater(
        fixture.owner.captureOpenUnderLock(
            lock: fixture.lock,
            plan: fixture.plan,
            start: null,
            isCurrent: () => true,
            openWithoutLock: (_) async => throw StateError('not admitted'),
            readIdentity: () async => fixture.identity,
            readProperties: fixture.read),
        throwsStateError);
    final stopped = await fixture.stopOwned();
    expect(fixture.stopCalls, 0);
    await fixture.retire(stopped);
    expect(fixture.owner.active, isFalse);
  });
}
