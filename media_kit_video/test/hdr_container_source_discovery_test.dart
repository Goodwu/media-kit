import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' show FileLoadedRecord;
import 'package:media_kit_video/src/hdr/hdr_container_source_discovery.dart';
import 'package:media_kit_video/src/hdr/hdr_decoder_review.dart';
import 'package:synchronized/synchronized.dart';

const _identity = <String>['path', 'playlist/0/id', 'playlist/0/filename'];
const _metadata = <String>[
  'current-tracks/video/codec',
  'current-tracks/video/dolby-vision-profile',
  'current-tracks/video/dolby-vision-compatibility-id',
  'current-tracks/video/dolby-vision-el-present',
];
const _trackListFields = <String>[
  'id',
  'type',
  'external',
  'albumart',
  'image',
  'selected',
  'main-selection',
  'codec',
  'dolby-vision-profile',
  'dolby-vision-compatibility-id',
  'dolby-vision-el-present',
];

class _Fixture {
  final lock = Lock();
  final values = <String, String>{
    'path': 'file:///video.mkv',
    'playlist/0/id': '7',
    'playlist/0/filename': 'file:///video.mkv',
    'current-tracks/video/id': '2',
    'current-tracks/video/main-selection': '0',
    'current-tracks/video/selected': 'yes',
    _metadata[0]: 'hevc',
    _metadata[1]: '5',
    _metadata[2]: '0',
    _metadata[3]: '0',
    'track-list/count': '1',
    'track-list/0/id': '2',
    'track-list/0/type': 'video',
    'track-list/0/external': 'no',
    'track-list/0/albumart': 'no',
    'track-list/0/image': 'no',
    'track-list/0/selected': 'no',
    'track-list/0/main-selection': '',
    'track-list/0/codec': 'hevc',
    'track-list/0/dolby-vision-profile': '5',
    'track-list/0/dolby-vision-compatibility-id': '0',
    'track-list/0/dolby-vision-el-present': '0',
  };
  int epoch = 5;
  bool current = true;
  int metadataReads = 0;
  final batches = <List<String>>[];
  Future<List<String>> Function(List<String>)? onRead;
  Future<FileLoadedRecord> Function()? onLoaded;
  Future<void> Function()? onVerifyProbe;

  Future<HdrContainerSourceSnapshot?> gather({
    Duration budget = const Duration(seconds: 1),
    Duration Function()? monotonicNow,
    bool unselectedProbe = false,
  }) =>
      gatherContainerSourceSnapshot(
        lock: lock,
        mediaUri: 'file:///video.mkv',
        readProperties: (names) async {
          batches.add(List.of(names));
          if (names == _metadata) metadataReads++;
          final hook = onRead;
          if (hook != null) return hook(names);
          return names.map((name) => values[name] ?? '').toList();
        },
        waitForFileLoadedEntry: (_, __) async =>
            onLoaded?.call() ?? Future.value(const FileLoadedRecord(5, 7)),
        playlistEntryId: 7,
        openedAfterEpoch: 4,
        fileLoadedEpoch: () => epoch,
        isCurrent: () => current,
        budget: budget,
        monotonicNow: monotonicNow,
        unselectedProbe: unselectedProbe,
        verifyUnselectedProbe: unselectedProbe
            ? () => onVerifyProbe?.call() ?? Future<void>.value()
            : null,
      );
}

void main() {
  test('expiry before outer wait still drains a synchronously admitted read',
      () async {
    final fixture = _Fixture();
    var elapsed = Duration.zero;
    final entered = Completer<void>();
    final release = Completer<List<String>>();
    fixture.onRead = (_) {
      elapsed = const Duration(seconds: 2);
      entered.complete();
      return release.future;
    };
    final discovery = fixture.gather(monotonicNow: () => elapsed);
    await entered.future;
    var finished = false;
    discovery.then((_) => finished = true, onError: (_) => finished = true);
    await Future<void>.delayed(Duration.zero);
    expect(finished, isFalse);
    release.complete(['file:///video.mkv', '7', 'file:///video.mkv']);
    await expectLater(discovery, throwsA(isA<TimeoutException>()));
  });
  test('supersede interrupts pending loaded without waiting for its event',
      () async {
    final fixture = _Fixture();
    final pending = Completer<FileLoadedRecord>();
    fixture.onLoaded = () => pending.future;
    final discovery = fixture.gather();
    await Future<void>.delayed(Duration.zero);
    fixture.current = false;
    await expectLater(discovery.timeout(const Duration(milliseconds: 200)),
        throwsA(isA<HdrDecoderReviewFailure>()));
    expect(fixture.batches, isEmpty);
    pending.complete(const FileLoadedRecord(5, 7));
  });

  test('supersede interrupts queued admission and late work reads nothing',
      () async {
    final fixture = _Fixture();
    final held = Completer<void>();
    final release = Completer<void>();
    final holder = fixture.lock.synchronized(() async {
      held.complete();
      await release.future;
    });
    await held.future;
    final discovery = fixture.gather();
    await Future<void>.delayed(Duration.zero);
    fixture.current = false;
    await expectLater(discovery.timeout(const Duration(milliseconds: 200)),
        throwsA(isA<HdrDecoderReviewFailure>()));
    release.complete();
    await holder;
    await Future<void>.delayed(Duration.zero);
    expect(fixture.batches, isEmpty);
  });

  test('empty track, nonprimary selection and selection drift fall back',
      () async {
    for (final key in [
      'current-tracks/video/id',
      'current-tracks/video/main-selection',
      'current-tracks/video/selected'
    ]) {
      final fixture = _Fixture()..values[key] = '';
      expect(await fixture.gather(), isNull);
    }
    final fixture = _Fixture();
    var selectionReads = 0;
    fixture.onRead = (names) async {
      if (names.contains('current-tracks/video/main-selection') &&
          ++selectionReads == 2) {
        return ['1', 'yes'];
      }
      return names.map((name) => fixture.values[name] ?? '').toList();
    };
    expect(await fixture.gather(), isNull);
  });

  test('returns matching Profile 5 and Profile 8.4 snapshots', () async {
    final p5 = _Fixture();
    final result5 = await p5.gather();
    expect(result5?.dvProfile, 5);
    expect(result5?.dvCompatibilityId, 0);
    expect(result5?.codec, 'hevc');
    expect(result5?.elPresent, isFalse);
    expect(p5.metadataReads, 2);

    final p84 = _Fixture()..values[_metadata[1]] = '8';
    p84.values[_metadata[2]] = '4';
    final result84 = await p84.gather();
    expect(result84?.dvProfile, 8);
    expect(result84?.dvCompatibilityId, 4);
  });

  test('missing, malformed, unsupported and A/B metadata fall back null',
      () async {
    for (final pair in <List<String>>[
      ['', '5', '0', '0'],
      ['hevc', 'five', '0', '0'],
      ['av1', '5', '0', '0'],
      ['hevc', '5', '0', '1'],
    ]) {
      final fixture = _Fixture();
      for (var i = 0; i < _metadata.length; i++) {
        fixture.values[_metadata[i]] = pair[i];
      }
      expect(await fixture.gather(), isNull);
    }

    final drift = _Fixture();
    drift.onRead = (names) async {
      if (names.length == _metadata.length && drift.metadataReads == 2) {
        return ['hevc', '8', '4', '0'];
      }
      return names.map((name) => drift.values[name] ?? '').toList();
    };
    expect(await drift.gather(), isNull);
  });

  test('entry and epoch drift fail closed', () async {
    final entry = _Fixture()
      ..onLoaded = () async => const FileLoadedRecord(5, 8);
    await expectLater(entry.gather(), throwsA(isA<HdrDecoderReviewFailure>()));

    final epoch = _Fixture()..epoch = 6;
    await expectLater(epoch.gather(), throwsA(isA<HdrDecoderReviewFailure>()));
  });

  test('source path and video track drift fail closed', () async {
    final path = _Fixture();
    var identityReads = 0;
    path.onRead = (names) async {
      if (names.length == _identity.length && ++identityReads == 2) {
        return ['file:///other.mkv', '7', 'file:///video.mkv'];
      }
      return names.map((name) => path.values[name] ?? '').toList();
    };
    await expectLater(path.gather(), throwsA(isA<HdrDecoderReviewFailure>()));

    final track = _Fixture();
    var trackReads = 0;
    track.onRead = (names) async {
      if (names.length == 1 && names.single == 'current-tracks/video/id') {
        trackReads++;
        return [trackReads == 1 ? '2' : '3'];
      }
      return names.map((name) => track.values[name] ?? '').toList();
    };
    await expectLater(track.gather(), throwsA(isA<HdrDecoderReviewFailure>()));
  });

  test('cancel and timeout drain an active native property read', () async {
    for (final cancel in [false, true]) {
      final fixture = _Fixture();
      final entered = Completer<void>();
      final release = Completer<List<String>>();
      fixture.onRead = (names) {
        if (names == _metadata && !entered.isCompleted) {
          entered.complete();
          return release.future;
        }
        return Future.value(
            names.map((name) => fixture.values[name] ?? '').toList());
      };
      final review = fixture.gather(
          budget: cancel
              ? const Duration(seconds: 5)
              : const Duration(milliseconds: 30));
      await entered.future;
      if (cancel) {
        fixture.current = false;
      } else {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      var completed = false;
      review.then((_) => completed = true, onError: (_) => completed = true);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(completed, isFalse);
      release.complete(fixture.values.entries
          .where((entry) => _metadata.contains(entry.key))
          .map((entry) => entry.value)
          .toList());
      await expectLater(
        review,
        throwsA(
            cancel ? isA<HdrDecoderReviewFailure>() : isA<TimeoutException>()),
      );
    }
  });

  test('late lock admission after deadline performs no reads', () async {
    final fixture = _Fixture();
    final held = Completer<void>();
    final release = Completer<void>();
    final holder = fixture.lock.synchronized(() async {
      held.complete();
      await release.future;
    });
    await held.future;
    final review = fixture.gather(budget: const Duration(milliseconds: 25));
    await expectLater(review, throwsA(isA<TimeoutException>()));
    release.complete();
    await holder;
    expect(fixture.batches, isEmpty);
  });

  test(
      'unselected probe reads the unique container video without current-track',
      () async {
    final fixture = _Fixture();
    final result = await fixture.gather(unselectedProbe: true);
    expect(result?.videoTrackId, '2');
    expect(result?.dvProfile, 5);
    expect(result?.dvCompatibilityId, 0);
    expect(result?.elPresent, isFalse);
    expect(
        fixture.batches.where((batch) =>
            batch.any((name) => name.startsWith('current-tracks/video/'))),
        isEmpty);
    final trackBatches = fixture.batches.where(
        (batch) => batch.any((name) => name.startsWith('track-list/0/')));
    expect(trackBatches.length, 2);
    expect(trackBatches.first,
        containsAll(_trackListFields.map((field) => 'track-list/0/$field')));
  });

  test('unselected probe rejects ambiguous, malformed and active tracks',
      () async {
    final ambiguous = _Fixture();
    ambiguous.values['track-list/count'] = '2';
    for (final field in _trackListFields) {
      ambiguous.values['track-list/1/$field'] =
          ambiguous.values['track-list/0/$field'] ?? '';
    }
    ambiguous.values['track-list/1/id'] = '3';
    expect(await ambiguous.gather(unselectedProbe: true), isNull);

    final malformed = _Fixture()
      ..values['track-list/0/dolby-vision-profile'] = 'bad';
    expect(await malformed.gather(unselectedProbe: true), isNull);

    final active = _Fixture()..values['track-list/0/selected'] = 'yes';
    await expectLater(
      active.gather(unselectedProbe: true),
      throwsA(isA<HdrDecoderReviewFailure>()),
    );
  });

  test('unselected probe falls back on missing fields and A/B drift', () async {
    final missing = _Fixture()..values['track-list/0/codec'] = '';
    expect(await missing.gather(unselectedProbe: true), isNull);

    final drift = _Fixture();
    var trackBatches = 0;
    drift.onRead = (names) async {
      if (names.any((name) => name.startsWith('track-list/0/'))) {
        trackBatches++;
        if (trackBatches == 2) {
          return names
              .map((name) => name == 'track-list/0/codec'
                  ? 'av1'
                  : drift.values[name] ?? '')
              .toList();
        }
      }
      return names.map((name) => drift.values[name] ?? '').toList();
    };
    expect(await drift.gather(unselectedProbe: true), isNull);
  });

  test('unselected probe verifies ownership before and after both samples',
      () async {
    final fixture = _Fixture();
    var verifies = 0;
    fixture.onVerifyProbe = () async {
      if (++verifies == 2) {
        throw const HdrDecoderReviewFailure('probe option changed');
      }
    };
    await expectLater(
      fixture.gather(unselectedProbe: true),
      throwsA(isA<HdrDecoderReviewFailure>()),
    );
  });
}
