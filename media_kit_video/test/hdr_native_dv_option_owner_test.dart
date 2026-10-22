import 'dart:async';
import 'package:synchronized/synchronized.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' show FileLoadedRecord;
import 'package:media_kit_video/src/hdr/hdr_native_dv_option_owner.dart';
import 'package:media_kit_video/src/hdr/hdr_player_backend.dart';

class Fixture {
  final player = Object();
  late HdrOptionSourceIdentity source = identity();
  final values = <String, String>{
    'vd-lavc-o': '',
    'mediacodec-embed-render-mode': 'boolean'
  };
  final writes = <String>[];
  Future<void> Function(String, String)? beforeWrite;
  Future<void> Function(String)? afterRead;
  late final owner = HdrNativeDvOptionOwner(
    readProperty: (name) async {
      final result = values[name]!;
      await afterRead?.call(name);
      return result;
    },
    setPropertyStrict: (name, value) async {
      writes.add('$name=$value');
      await beforeWrite?.call(name, value);
      values[name] = value;
    },
    readIdentity: () async => source,
  );
  HdrOptionSourceIdentity identity(
          {String path = '',
          String entry = '',
          int epoch = 0,
          Object? otherPlayer}) =>
      HdrOptionSourceIdentity(
          player: otherPlayer ?? player,
          path: path,
          playlistEntryId: entry,
          fileLoadedEpoch: epoch);
  Future<void> begin() => owner.begin(
      stoppedIdentity: identity(epoch: source.fileLoadedEpoch),
      vd: 'native_dv=1',
      renderMode: 'timed');
  Future<void> beginProbe({Future<void> Function()? verify}) =>
      owner.beginFromDecoderlessProbe(
          entryIdentity: source,
          originalVd: '',
          originalRenderMode: 'boolean',
          verifyDecoderlessProbe: verify ?? (() async {}),
          vd: 'native_dv=1',
          renderMode: 'timed');
}

void main() {
  test('decoderless entry admission is separate from stopped-source begin',
      () async {
    final fixture = Fixture();
    fixture.source =
        fixture.identity(path: 'file:///probe.mkv', entry: '7', epoch: 3);
    await expectLater(fixture.begin(), throwsStateError);
    expect(fixture.writes, isEmpty);
    var proofs = 0;
    await fixture.beginProbe(verify: () async => proofs++);
    expect(proofs, greaterThan(2));
    expect(fixture.owner.identity, fixture.source);
    expect(fixture.writes,
        ['vd-lavc-o=native_dv=1', 'mediacodec-embed-render-mode=timed']);
    final writes = List.of(fixture.writes);
    await expectLater(
        fixture.owner.restore(), throwsA(isA<HdrNativeDvOptionFailure>()));
    expect(fixture.writes, writes);
    final before = fixture.source;
    fixture.source = fixture.identity(epoch: 3);
    await fixture.owner.rebind(before, fixture.source);
    await fixture.owner.restore();
    expect(fixture.values['vd-lavc-o'], '');
    expect(fixture.values['mediacodec-embed-render-mode'], 'boolean');
    expect(fixture.owner.active, isFalse);
  });

  test(
      'decoderless baseline or proof failure never writes or adopts another entry',
      () async {
    for (final failure in ['vd', 'render', 'proof', 'foreign']) {
      final fixture = Fixture();
      fixture.source =
          fixture.identity(path: 'file:///probe.mkv', entry: '7', epoch: 3);
      final admitted = fixture.source;
      if (failure == 'vd') {
        fixture.values['vd-lavc-o'] = 'external=1';
      }
      if (failure == 'render') {
        fixture.values['mediacodec-embed-render-mode'] = 'timed';
      }
      await expectLater(fixture.beginProbe(verify: () async {
        if (failure == 'proof') throw StateError('decoder already exists');
        if (failure == 'foreign') {
          fixture.source =
              fixture.identity(path: admitted.path, entry: '8', epoch: 4);
        }
      }), throwsStateError, reason: failure);
      expect(fixture.writes, isEmpty);
      expect(fixture.owner.identity, admitted);
      expect(fixture.owner.active, isTrue);
      await expectLater(
          fixture.owner.restore(), throwsA(isA<HdrNativeDvOptionFailure>()));
      expect(fixture.writes, isEmpty);
    }
  });

  test('decoderless native write failures keep pair debt until owned stop',
      () async {
    for (final failedName in [
      HdrNativeDvOptionOwner.vdOption,
      HdrNativeDvOptionOwner.renderOption,
    ]) {
      final fixture = Fixture();
      fixture.source =
          fixture.identity(path: 'file:///probe.mkv', entry: '7', epoch: 3);
      var failOnce = true;
      fixture.beforeWrite = (name, value) async {
        if (name == failedName && failOnce) {
          failOnce = false;
          fixture.values[name] = value;
          throw StateError('setter failed after mutation');
        }
      };
      await expectLater(fixture.beginProbe(), throwsStateError);
      expect(fixture.owner.active, isTrue);
      final attempted = List.of(fixture.writes);
      await expectLater(
          fixture.owner.restore(), throwsA(isA<HdrNativeDvOptionFailure>()));
      expect(fixture.writes, attempted);
      final before = fixture.source;
      fixture.source = fixture.identity(epoch: 3);
      await fixture.owner.rebind(before, fixture.source);
      await fixture.owner.restore();
      expect(fixture.values['vd-lavc-o'], '');
      expect(fixture.values['mediacodec-embed-render-mode'], 'boolean');
      expect(fixture.owner.active, isFalse);
    }
  });

  test('decoderless promotion proof is checked after each pair mutation',
      () async {
    final fixture = Fixture();
    fixture.source =
        fixture.identity(path: 'file:///probe.mkv', entry: '7', epoch: 3);
    await expectLater(fixture.beginProbe(verify: () async {
      if (fixture.writes.isNotEmpty) {
        throw StateError('track selected during pair apply');
      }
    }), throwsStateError);
    expect(fixture.writes, ['vd-lavc-o=native_dv=1']);
    expect(fixture.owner.active, isTrue);
  });

  test('decoderless pair drift between writes rejects the second mutation',
      () async {
    final fixture = Fixture();
    fixture.source =
        fixture.identity(path: 'file:///probe.mkv', entry: '7', epoch: 3);
    fixture.beforeWrite = (name, _) async {
      if (name == HdrNativeDvOptionOwner.vdOption) {
        fixture.values[HdrNativeDvOptionOwner.renderOption] = 'timed';
      }
    };
    await expectLater(fixture.beginProbe(), throwsStateError);
    expect(fixture.writes, ['vd-lavc-o=native_dv=1']);
    expect(fixture.owner.active, isTrue);
  });

  test('option reads use one ordered nine-field batch with active identity',
      () async {
    final player = Object();
    var epoch = 9;
    final values = <String, String>{
      HdrNativeDvOptionOwner.vdOption: '',
      HdrNativeDvOptionOwner.renderOption: 'boolean',
    };
    final batches = <List<String>>[];
    final owner = HdrNativeDvOptionOwner(
      readProperty: (_) async => fail('scalar fallback should not run'),
      setPropertyStrict: (name, value) async => values[name] = value,
      readIdentity: () async => HdrOptionSourceIdentity(
          player: player,
          path: '',
          playlistEntryId: '',
          fileLoadedEpoch: epoch),
      currentFileLoadedEpoch: () => epoch,
      readProperties: (names) async {
        batches.add(List.of(names));
        return names
            .map((name) => switch (name) {
                  'path' => '',
                  'playlist/0/id' => '',
                  _ => values[name] ?? '',
                })
            .toList();
      },
    );

    await owner.begin(
      stoppedIdentity: HdrOptionSourceIdentity(
          player: player,
          path: '',
          playlistEntryId: '',
          fileLoadedEpoch: epoch),
      vd: 'native_dv=1',
      renderMode: 'timed',
    );
    const expectedPrefix = <String>[
      'path',
      'playlist/0/id',
      'path',
      'playlist/0/id',
    ];
    const expectedSuffix = <String>[
      'path',
      'playlist/0/id',
      'path',
      'playlist/0/id',
    ];
    expect(batches, hasLength(4));
    for (var i = 0; i < batches.length; i++) {
      expect(
        batches[i],
        [
          ...expectedPrefix,
          i.isEven
              ? HdrNativeDvOptionOwner.vdOption
              : HdrNativeDvOptionOwner.renderOption,
          ...expectedSuffix
        ],
      );
    }
  });

  test('batch option reads reject source endpoint, epoch and length drift',
      () async {
    for (final failureCase in ['path', 'id', 'epoch', 'length']) {
      final player = Object();
      var epoch = 9;
      var path = '';
      var entry = '';
      final owner = HdrNativeDvOptionOwner(
        readProperty: (_) async => fail('scalar fallback should not run'),
        setPropertyStrict: (_, __) async {},
        readIdentity: () async => HdrOptionSourceIdentity(
            player: player,
            path: path,
            playlistEntryId: entry,
            fileLoadedEpoch: epoch),
        currentFileLoadedEpoch: () => epoch,
        readProperties: (names) async {
          if (failureCase == 'path') {
            return ['', '', 'other', '', '', '', '', '', ''];
          }
          if (failureCase == 'id') {
            return ['', '', '', '1', '', '', '', '', ''];
          }
          if (failureCase == 'epoch') {
            epoch++;
            return List<String>.filled(9, '');
          }
          return List<String>.filled(8, '');
        },
      );
      final stopped = HdrOptionSourceIdentity(
          player: player,
          path: '',
          playlistEntryId: '',
          fileLoadedEpoch: epoch);
      await expectLater(
        owner.begin(
          stoppedIdentity: stopped,
          vd: 'native_dv=1',
          renderMode: 'timed',
        ),
        throwsStateError,
        reason: failureCase,
      );
    }
  });

  test('pending batch rejects ownership epoch change before accepting option',
      () async {
    final player = Object();
    var epoch = 9;
    final entered = Completer<void>();
    final release = Completer<List<String>>();
    final owner = HdrNativeDvOptionOwner(
      readProperty: (_) async => fail('scalar fallback should not run'),
      setPropertyStrict: (_, __) async {},
      readIdentity: () async => HdrOptionSourceIdentity(
          player: player,
          path: '',
          playlistEntryId: '',
          fileLoadedEpoch: epoch),
      currentFileLoadedEpoch: () => epoch,
      readProperties: (_) {
        entered.complete();
        return release.future;
      },
    );
    final review = owner.begin(
      stoppedIdentity: HdrOptionSourceIdentity(
          player: player,
          path: '',
          playlistEntryId: '',
          fileLoadedEpoch: epoch),
      vd: 'native_dv=1',
      renderMode: 'timed',
    );
    await entered.future;
    epoch++;
    release.complete(List<String>.filled(9, ''));
    await expectLater(review, throwsStateError);
    expect(owner.active, isFalse);
  });

  test('active verify reads both options in one ordered 18-field batch',
      () async {
    final player = Object();
    var path = '';
    var entry = '';
    var epoch = 9;
    final values = <String, String>{
      HdrNativeDvOptionOwner.vdOption: '',
      HdrNativeDvOptionOwner.renderOption: 'boolean',
    };
    final batches = <List<String>>[];
    final owner = HdrNativeDvOptionOwner(
      readProperty: (_) async => fail('scalar fallback should not run'),
      setPropertyStrict: (name, value) async => values[name] = value,
      readIdentity: () async => HdrOptionSourceIdentity(
          player: player,
          path: path,
          playlistEntryId: entry,
          fileLoadedEpoch: epoch),
      currentFileLoadedEpoch: () => epoch,
      readProperties: (names) async {
        batches.add(List.of(names));
        return names.map((name) {
          final value = switch (name) {
            'path' => path,
            'playlist/0/id' => entry,
            _ => values[name] ?? '',
          };
          return value;
        }).toList();
      },
    );
    await owner.begin(
      stoppedIdentity: HdrOptionSourceIdentity(
          player: player,
          path: '',
          playlistEntryId: '',
          fileLoadedEpoch: epoch),
      vd: 'native_dv=1',
      renderMode: 'timed',
    );
    batches.clear();

    await owner.verify();

    const groupVd = <String>[
      'path',
      'playlist/0/id',
      'path',
      'playlist/0/id',
      HdrNativeDvOptionOwner.vdOption,
      'path',
      'playlist/0/id',
      'path',
      'playlist/0/id',
    ];
    const groupRender = <String>[
      'path',
      'playlist/0/id',
      'path',
      'playlist/0/id',
      HdrNativeDvOptionOwner.renderOption,
      'path',
      'playlist/0/id',
      'path',
      'playlist/0/id',
    ];
    expect(batches, [
      <String>[...groupVd, ...groupRender]
    ]);
  });

  test('verify rejects second-group identity drift and first option mismatch',
      () async {
    for (final failureCase in ['secondIdentity', 'firstOption']) {
      final player = Object();
      var epoch = 9;
      final values = <String, String>{
        HdrNativeDvOptionOwner.vdOption: '',
        HdrNativeDvOptionOwner.renderOption: 'boolean',
      };
      final batches = <List<String>>[];
      final writes = <String>[];
      final owner = HdrNativeDvOptionOwner(
        readProperty: (_) async => fail('scalar fallback should not run'),
        setPropertyStrict: (name, value) async {
          writes.add('$name=$value');
          values[name] = value;
        },
        readIdentity: () async => HdrOptionSourceIdentity(
            player: player,
            path: '',
            playlistEntryId: '',
            fileLoadedEpoch: epoch),
        currentFileLoadedEpoch: () => epoch,
        readProperties: (names) async {
          batches.add(List.of(names));
          return names.indexed.map((indexed) {
            final (index, name) = indexed;
            if (failureCase == 'secondIdentity' && index == 11) {
              return 'foreign-path';
            }
            if (failureCase == 'firstOption' &&
                names.length == 18 &&
                index == 4) {
              return 'externally-changed';
            }
            return switch (name) {
              'path' => '',
              'playlist/0/id' => '',
              _ => values[name] ?? '',
            };
          }).toList();
        },
      );
      await owner.begin(
        stoppedIdentity: HdrOptionSourceIdentity(
            player: player,
            path: '',
            playlistEntryId: '',
            fileLoadedEpoch: epoch),
        vd: 'native_dv=1',
        renderMode: 'timed',
      );
      batches.clear();
      final writesBeforeVerify = writes.length;

      await expectLater(owner.verify(), throwsStateError);

      expect(batches, hasLength(1), reason: failureCase);
      expect(batches.single, hasLength(18), reason: failureCase);
      expect(writes, hasLength(writesBeforeVerify), reason: failureCase);
      expect(owner.active, isTrue, reason: failureCase);
    }
  });

  test('batch identity preserves source and stopped source endpoints',
      () async {
    final player = Object();
    for (final pair in [
      <String>['test://source', '7'],
      <String>['', '']
    ]) {
      final result = await readHdrOptionSourceIdentity(
        player: player,
        fileLoadedEpoch: () => 3,
        readProperties: (names) async {
          expect(names, ['path', 'playlist/0/id', 'path', 'playlist/0/id']);
          return [...pair, ...pair];
        },
      );
      expect(result.player, same(player));
      expect(result.path, pair[0]);
      expect(result.playlistEntryId, pair[1]);
      expect(result.fileLoadedEpoch, 3);
    }
  });
  test('batch identity rejects endpoint, epoch and length drift', () async {
    for (final values in [
      ['test://a', '1', 'test://b', '1'],
      ['test://a', '1', 'test://a', '2'],
      ['test://a'],
      ['test://a', '1', 'test://a', '1'],
    ]) {
      var epoch = 3;
      await expectLater(
        readHdrOptionSourceIdentity(
          player: Object(),
          fileLoadedEpoch: () => epoch,
          readProperties: (_) async {
            if (values.length == 4 &&
                values[0] == values[2] &&
                values[1] == values[3]) {
              epoch++;
            }
            return values;
          },
        ),
        throwsStateError,
      );
    }
  });
  TestWidgetsFlutterBinding.ensureInitialized();
  group('captureStoppedBoundaryUnderLock diagnostics', () {
    Future<StateError> captureFailure({
      required HdrOptionSourceIdentity first,
      HdrOptionSourceIdentity? second,
      required int expectedReadCount,
      required String reason,
      required Lock lock,
    }) async {
      var reads = 0;
      final error = await captureFailureObject(
        lock: lock,
        first: first,
        second: second,
        onRead: () => reads++,
      );
      expect(reads, expectedReadCount);
      expect(error.toString(),
          contains('Stop did not establish a stable empty source'));
      expect(error.toString(), contains('reason=$reason'));
      return error;
    }

    test('path-not-empty short-circuits second identity read', () async {
      final lock = Lock();
      final player = Object();
      final error = await captureFailure(
        first: HdrOptionSourceIdentity(
          player: player,
          path: 'https://user:secret@example.invalid/path-secret.mp4',
          playlistEntryId: 'entry-secret',
          fileLoadedEpoch: 41,
        ),
        expectedReadCount: 1,
        reason: 'path-not-empty',
        lock: lock,
      );

      expect(error.message, contains('pathEmpty=false'));
      expect(error.message, contains('entryEmpty=false'));
      expect(error.message, contains('firstEpoch=41'));
      expect(error.message, isNot(contains('secret')));
    });

    test('entry-not-empty short-circuits second identity read', () async {
      final error = await captureFailure(
        first: HdrOptionSourceIdentity(
          player: Object(),
          path: '',
          playlistEntryId: 'entry-secret',
          fileLoadedEpoch: 42,
        ),
        expectedReadCount: 1,
        reason: 'entry-not-empty',
        lock: Lock(),
      );

      expect(error.message, contains('pathEmpty=true'));
      expect(error.message, contains('entryEmpty=false'));
      expect(error.message, contains('firstEpoch=42'));
      expect(error.message, isNot(contains('entry-secret')));
    });

    test('stale path with empty entry is re-read until cleared', () async {
      final player = Object();
      final identities = <HdrOptionSourceIdentity>[
        HdrOptionSourceIdentity(
            player: player,
            path: '/stale-path.mp4',
            playlistEntryId: '',
            fileLoadedEpoch: 45),
        HdrOptionSourceIdentity(
            player: player, path: '', playlistEntryId: '', fileLoadedEpoch: 45),
        HdrOptionSourceIdentity(
            player: player, path: '', playlistEntryId: '', fileLoadedEpoch: 45),
      ];
      var reads = 0;
      final stopped = await AndroidHdrBackend.captureStoppedBoundaryUnderLock(
        lock: Lock(),
        stopWithoutLock: () async {},
        readIdentity: () async {
          reads++;
          return identities[reads - 1];
        },
      );
      expect(reads, 3);
      expect(stopped.path, isEmpty);
      expect(stopped.playlistEntryId, isEmpty);
    });

    test('stale path never clearing fails with rereads counter', () async {
      final player = Object();
      var reads = 0;
      StateError? error;
      try {
        await AndroidHdrBackend.captureStoppedBoundaryUnderLock(
          lock: Lock(),
          stopWithoutLock: () async {},
          readIdentity: () async {
            reads++;
            return HdrOptionSourceIdentity(
                player: player,
                path: '/stale-path.mp4',
                playlistEntryId: '',
                fileLoadedEpoch: 46);
          },
        );
      } on StateError catch (stateError) {
        error = stateError;
      }
      expect(error, isNotNull);
      expect(reads, 6);
      expect(error!.message, contains('reason=path-not-empty'));
      expect(error.message, contains('rereads=5'));
      expect(error.message, contains('pathEmpty=false'));
      expect(error.message, contains('entryEmpty=true'));
    });

    test('entry refilled during reread fails as identity-changed', () async {
      final player = Object();
      final identities = <HdrOptionSourceIdentity>[
        HdrOptionSourceIdentity(
            player: player,
            path: '/stale-path.mp4',
            playlistEntryId: '',
            fileLoadedEpoch: 47),
        HdrOptionSourceIdentity(
            player: player,
            path: '',
            playlistEntryId: '9',
            fileLoadedEpoch: 47),
      ];
      var reads = 0;
      StateError? error;
      try {
        await AndroidHdrBackend.captureStoppedBoundaryUnderLock(
          lock: Lock(),
          stopWithoutLock: () async {},
          readIdentity: () async {
            reads++;
            return identities[reads - 1];
          },
        );
      } on StateError catch (stateError) {
        error = stateError;
      }
      expect(error, isNotNull);
      expect(error!.message, contains('reason=identity-changed'));
      expect(error.message, contains('secondEntryEmpty=false'));
      expect(error.message, contains('rereads=1'));
      expect(error.message, isNot(contains('secret')));
    });

    test('epoch change during reread fails as identity-changed', () async {
      final player = Object();
      final identities = <HdrOptionSourceIdentity>[
        HdrOptionSourceIdentity(
            player: player,
            path: '/stale-path.mp4',
            playlistEntryId: '',
            fileLoadedEpoch: 48),
        HdrOptionSourceIdentity(
            player: player, path: '', playlistEntryId: '', fileLoadedEpoch: 49),
      ];
      var reads = 0;
      StateError? error;
      try {
        await AndroidHdrBackend.captureStoppedBoundaryUnderLock(
          lock: Lock(),
          stopWithoutLock: () async {},
          readIdentity: () async {
            reads++;
            return identities[reads - 1];
          },
        );
      } on StateError catch (stateError) {
        error = stateError;
      }
      expect(error, isNotNull);
      expect(error!.message, contains('reason=identity-changed'));
      expect(error.message, contains('secondEpoch=49'));
      expect(error.message, contains('firstEpoch=48'));
    });

    test('identity-changed records only safe second-read scalars', () async {
      final player = Object();
      final error = await captureFailure(
        first: HdrOptionSourceIdentity(
          player: player,
          path: '',
          playlistEntryId: '',
          fileLoadedEpoch: 43,
        ),
        second: HdrOptionSourceIdentity(
          player: player,
          path: '/private/source-secret.mp4',
          playlistEntryId: 'entry-secret',
          fileLoadedEpoch: 44,
        ),
        expectedReadCount: 2,
        reason: 'identity-changed',
        lock: Lock(),
      );

      expect(error.message, contains('pathEmpty=true'));
      expect(error.message, contains('entryEmpty=true'));
      expect(error.message, contains('firstEpoch=43'));
      expect(error.message, contains('secondEpoch=44'));
      expect(error.message, contains('samePlayer=true'));
      expect(error.message, contains('secondPathEmpty=false'));
      expect(error.message, contains('secondEntryEmpty=false'));
      expect(error.message, contains('entryIdMatches=false'));
      expect(error.message, isNot(contains('private/source-secret')));
      expect(error.message, isNot(contains('entry-secret')));
    });

    test('successful empty stable identity keeps two reads and stop order',
        () async {
      final lock = Lock();
      final player = Object();
      final identity = HdrOptionSourceIdentity(
        player: player,
        path: '',
        playlistEntryId: '',
        fileLoadedEpoch: 45,
      );
      var stops = 0;
      var reads = 0;
      final stopped = await AndroidHdrBackend.captureStoppedBoundaryUnderLock(
        lock: lock,
        stopWithoutLock: () async {
          stops++;
          expect(reads, 0);
        },
        readIdentity: () async {
          reads++;
          expect(stops, 1);
          return identity;
        },
      );

      expect(identical(stopped, identity), isTrue);
      expect(stops, 1);
      expect(reads, 2);
    });

    test('stop and identity-read exceptions propagate unchanged', () async {
      final stopError = StateError('stop-original-error');
      var stopReads = 0;
      await expectLater(
        AndroidHdrBackend.captureStoppedBoundaryUnderLock(
          lock: Lock(),
          stopWithoutLock: () async => throw stopError,
          readIdentity: () async {
            stopReads++;
            return HdrOptionSourceIdentity(
              player: Object(),
              path: '',
              playlistEntryId: '',
              fileLoadedEpoch: 0,
            );
          },
        ),
        throwsA(same(stopError)),
      );
      expect(stopReads, 0);

      final readError = FormatException('identity-original-error');
      var reads = 0;
      await expectLater(
        AndroidHdrBackend.captureStoppedBoundaryUnderLock(
          lock: Lock(),
          stopWithoutLock: () async {},
          readIdentity: () async {
            reads++;
            throw readError;
          },
        ),
        throwsA(same(readError)),
      );
      expect(reads, 1);

      final secondReadError = StateError('second-identity-read-error');
      reads = 0;
      final stableFirst = HdrOptionSourceIdentity(
        player: Object(),
        path: '',
        playlistEntryId: '',
        fileLoadedEpoch: 1,
      );
      await expectLater(
        AndroidHdrBackend.captureStoppedBoundaryUnderLock(
          lock: Lock(),
          stopWithoutLock: () async {},
          readIdentity: () async {
            reads++;
            if (reads == 1) return stableFirst;
            throw secondReadError;
          },
        ),
        throwsA(same(secondReadError)),
      );
      expect(reads, 2);
    });
  });

  for (final replacement in [
    'loaded',
    'pending',
    'cancelled',
    'other-player'
  ]) {
    test('stop proof rejects external $replacement before option writes',
        () async {
      final f = Fixture();
      final lock = Lock();
      f.source = f.identity(path: 'test://old', entry: '1', epoch: 1);
      final stopped = await AndroidHdrBackend.captureStoppedBoundaryUnderLock(
        lock: lock,
        stopWithoutLock: () async {
          f.source = f.identity(epoch: 1);
        },
        readIdentity: () async => f.source,
      );
      // This default serialized source mutation finishes after stop and
      // before prepare. A historical stopped boolean cannot authorize it.
      await lock.synchronized(() async {
        if (replacement == 'loaded') {
          f.source = f.identity(path: 'test://external', entry: '9', epoch: 2);
        } else if (replacement == 'pending') {
          f.source = f.identity(entry: '9', epoch: 1);
        } else if (replacement == 'cancelled') {
          f.source = f.identity(epoch: 2);
        } else {
          f.source = f.identity(epoch: 1, otherPlayer: Object());
        }
      });
      await expectLater(
          AndroidHdrBackend.beginNativeDvUnderLock(
              lock: lock,
              options: f.owner,
              stoppedIdentity: stopped,
              vd: 'native_dv=1',
              renderMode: 'timed'),
          throwsStateError);
      expect(f.writes, isEmpty);
      expect(f.owner.active, isFalse);
      expect(f.values['vd-lavc-o'], '');
      expect(f.values['mediacodec-embed-render-mode'], 'boolean');
    });
  }
  test('nonempty expected proof cannot authorize begin even if current matches',
      () async {
    final f = Fixture();
    f.source = f.identity(path: 'test://external', entry: '9', epoch: 1);
    await expectLater(
        f.owner.begin(
            stoppedIdentity: f.source, vd: 'native_dv=1', renderMode: 'timed'),
        throwsStateError);
    expect(f.writes, isEmpty);
    expect(f.owner.active, isFalse);
  });
  test('captures both before writing and restores legal empty vd', () async {
    final f = Fixture();
    var reads = 0;
    f.afterRead = (_) async {
      reads++;
    };
    f.beforeWrite = (_, __) async {
      expect(reads, greaterThanOrEqualTo(2));
    };
    await f.begin();
    await f.owner.verify();
    await f.owner.restore();
    expect(
        f.values, {'vd-lavc-o': '', 'mediacodec-embed-render-mode': 'boolean'});
    expect(f.owner.active, isFalse);
  });
  test('original timed mode is preserved', () async {
    final f = Fixture();
    f.values['mediacodec-embed-render-mode'] = 'timed';
    await f.begin();
    await f.owner.restore();
    expect(f.values['mediacodec-embed-render-mode'], 'timed');
    expect(f.owner.active, isFalse);
  });
  test('second set fails: first restored, untouched second is not written',
      () async {
    final f = Fixture();
    f.beforeWrite = (name, value) async {
      if (name == 'mediacodec-embed-render-mode' && value == 'timed') {
        throw StateError('second set failed');
      }
    };
    await expectLater(f.begin(), throwsStateError);
    expect(f.writes, [
      'vd-lavc-o=native_dv=1',
      'mediacodec-embed-render-mode=timed',
      'vd-lavc-o='
    ]);
    expect(f.owner.active, isFalse);
  });
  test('mutating setter that fails is rolled back', () async {
    final f = Fixture();
    f.beforeWrite = (name, value) async {
      if (name == 'mediacodec-embed-render-mode' && value == 'timed') {
        f.values[name] = value;
        throw StateError('late failure');
      }
    };
    await expectLater(f.begin(), throwsStateError);
    expect(f.values['mediacodec-embed-render-mode'], 'boolean');
    expect(f.owner.active, isFalse);
  });
  test('both restores attempted independently and pending owner retries',
      () async {
    final f = Fixture();
    await f.begin();
    f.writes.clear();
    f.beforeWrite = (_, __) async {
      throw StateError('restore failure');
    };
    await expectLater(
        f.owner.restore(),
        throwsA(isA<HdrNativeDvOptionFailure>()
            .having((e) => e.restoreErrors.length, 'both errors', 2)));
    expect(f.writes, ['mediacodec-embed-render-mode=boolean', 'vd-lavc-o=']);
    expect(f.owner.active, isTrue);
    f.beforeWrite = null;
    await f.owner.restore();
    expect(f.owner.active, isFalse);
  });
  test('application failure retained together with rollback failure', () async {
    final f = Fixture();
    f.beforeWrite = (name, value) async {
      if (name == 'mediacodec-embed-render-mode' || value.isEmpty) {
        throw StateError('injected failure');
      }
    };
    await expectLater(
        f.begin(),
        throwsA(isA<HdrNativeDvOptionFailure>()
            .having(
                (e) => e.operationError, 'application error', isA<StateError>())
            .having((e) => e.restoreErrors.keys, 'pending vd',
                contains('vd-lavc-o'))));
    expect(f.owner.active, isTrue);
    f.beforeWrite = null;
    await f.owner.restore();
    expect(f.values['vd-lavc-o'], '');
  });
  test('external conflict preserved while other option restored', () async {
    final f = Fixture();
    await f.begin();
    f.values['mediacodec-embed-render-mode'] = 'external';
    f.writes.clear();
    await expectLater(
        f.owner.restore(), throwsA(isA<HdrNativeDvOptionFailure>()));
    expect(f.writes, ['vd-lavc-o=']);
    expect(f.values['mediacodec-embed-render-mode'], 'external');
    expect(f.owner.active, isTrue);
    f.values['mediacodec-embed-render-mode'] = 'timed';
    await f.owner.restore();
    expect(f.values['mediacodec-embed-render-mode'], 'boolean');
  });
  test('changed source or player refuses both restore writes', () async {
    for (final replacePlayer in [false, true]) {
      final f = Fixture();
      await f.begin();
      final original = f.source;
      f.source = f.identity(
          path: 'external',
          entry: '8',
          epoch: 1,
          otherPlayer: replacePlayer ? Object() : null);
      f.writes.clear();
      await expectLater(
          f.owner.restore(), throwsA(isA<HdrNativeDvOptionFailure>()));
      expect(f.writes, isEmpty);
      expect(f.owner.active, isTrue);
      f.source = original;
      await f.owner.restore();
    }
  });
  test('identity change during setter prevents second write', () async {
    final f = Fixture();
    f.beforeWrite = (_, __) async {
      f.source = f.identity(epoch: 1);
    };
    await expectLater(f.begin(), throwsA(isA<HdrNativeDvOptionFailure>()));
    expect(f.writes, ['vd-lavc-o=native_dv=1']);
    expect(f.owner.active, isTrue);
  });
  test('nonempty vd or unknown mode rejected before writing', () async {
    for (final name in ['vd-lavc-o', 'mediacodec-embed-render-mode']) {
      final f = Fixture();
      f.values[name] = 'external';
      await expectLater(f.begin(), throwsStateError);
      expect(f.writes, isEmpty);
      expect(f.owner.active, isFalse);
    }
  });
  test(
      'late own FILE_LOADED accepted once; same-entry external reload rejected',
      () async {
    final f = Fixture();
    await f.begin();
    final before = f.source;
    f.source = f.identity(entry: '7');
    final event = Completer<FileLoadedRecord>();
    final confirming = AndroidHdrBackend.confirmNativeDvOpenIdentity(
        expectedPlaylistEntryId: 7,
        before: before,
        mediaUri: 'test://p5',
        readIdentity: () async => f.source,
        readPlaylistFilename: () async => 'test://p5',
        waitForFileLoadedEntry: (entry, epoch) {
          expect(entry, 7);
          expect(epoch, 0);
          return event.future;
        });
    await pumpEventQueue();
    f.source = f.identity(path: 'test://p5', entry: '7', epoch: 1);
    event.complete(FileLoadedRecord(1, 7));
    await f.owner.rebind(before, await confirming);
    await f.owner.verify();
    f.source = f.identity(path: 'test://p5', entry: '7', epoch: 2);
    f.writes.clear();
    await expectLater(
        f.owner.restore(), throwsA(isA<HdrNativeDvOptionFailure>()));
    expect(f.writes, isEmpty);
  });
  test('failed open with loaded own entry can migrate, stop and restore',
      () async {
    final f = Fixture();
    await f.begin();
    final before = f.source;
    f.source = f.identity(path: 'test://p5', entry: '7', epoch: 1);
    final confirmed = await AndroidHdrBackend.confirmNativeDvOpenIdentity(
        expectedPlaylistEntryId: 7,
        before: before,
        mediaUri: 'test://p5',
        readIdentity: () async => f.source,
        readPlaylistFilename: () async => 'test://p5',
        allowUnchanged: true,
        waitForFileLoadedEntry: (_, __) async => FileLoadedRecord(1, 7));
    await f.owner.rebind(before, confirmed);
    f.source = f.identity(epoch: 1);
    await f.owner.rebind(confirmed, f.source);
    await f.owner.restore();
    expect(f.owner.active, isFalse);
  });
  test('failed open that never loaded keeps recoverable stopped token',
      () async {
    final f = Fixture();
    await f.begin();
    final before = f.source;
    final confirmed = await AndroidHdrBackend.confirmNativeDvOpenIdentity(
        expectedPlaylistEntryId: 7,
        before: before,
        mediaUri: 'test://p5',
        readIdentity: () async => f.source,
        readPlaylistFilename: () async => throw StateError('must not read'),
        waitForFileLoadedEntry: (_, __) async =>
            throw StateError('must not wait'),
        allowUnchanged: true);
    await f.owner.rebind(before, confirmed);
    await f.owner.restore();
    expect(f.owner.active, isFalse);
  });
  test('foreign playlist/wrong event/new epoch never migrate ownership',
      () async {
    for (final failure in ['filename', 'entry', 'epoch']) {
      final f = Fixture();
      await f.begin();
      final before = f.source;
      f.source = f.identity(path: 'test://p5', entry: '7', epoch: 2);
      await expectLater(
          AndroidHdrBackend.confirmNativeDvOpenIdentity(
              expectedPlaylistEntryId: 7,
              before: before,
              mediaUri: 'test://p5',
              readIdentity: () async => f.source,
              readPlaylistFilename: () async =>
                  failure == 'filename' ? 'foreign' : 'test://p5',
              waitForFileLoadedEntry: (_, __) async =>
                  FileLoadedRecord(1, failure == 'entry' ? 8 : 7),
              allowUnchanged: true),
          throwsStateError);
      expect(f.owner.identity, before);
    }
  });
  test(
      'controlled stop keeps epoch and can restore even after public stop error',
      () async {
    final f = Fixture();
    await f.begin();
    final before = f.source;
    f.source = f.identity(path: 'test://p5', entry: '7', epoch: 1);
    await f.owner.rebind(before, f.source);
    final loaded = f.source;
    f.source = f.identity(epoch: 1);
    final stopped = await AndroidHdrBackend.confirmNativeDvStoppedIdentity(
        before: loaded, readIdentity: () async => f.source);
    await f.owner.rebind(loaded, stopped);
    await f.owner.restore();
    expect(f.owner.active, isFalse);
  });
  test('stop that crossed FILE_LOADED cannot transfer option ownership',
      () async {
    final f = Fixture();
    final before = f.identity(path: 'test://p5', entry: '7', epoch: 1);
    f.source = f.identity(epoch: 2);
    await expectLater(
        AndroidHdrBackend.confirmNativeDvStoppedIdentity(
            before: before, readIdentity: () async => f.source),
        throwsStateError);
  });
  test('open identity confirmation has a bounded wait and preserves owner',
      () async {
    final f = Fixture();
    await f.begin();
    final before = f.source;
    f.source = f.identity(entry: '7');
    await expectLater(
        AndroidHdrBackend.confirmNativeDvOpenIdentity(
            expectedPlaylistEntryId: 7,
            before: before,
            mediaUri: 'test://p5',
            readIdentity: () async => f.source,
            readPlaylistFilename: () async => 'test://p5',
            waitForFileLoadedEntry: (_, __) =>
                Completer<FileLoadedRecord>().future,
            budget: const Duration(milliseconds: 1)),
        throwsA(isA<TimeoutException>()));
    expect(f.owner.identity, before);
    expect(f.owner.active, isTrue);
  });
  test('strict setter success without requested readback is rejected',
      () async {
    final player = Object();
    final source = HdrOptionSourceIdentity(
        player: player, path: '', playlistEntryId: '', fileLoadedEpoch: 0);
    final values = {'vd-lavc-o': '', 'mediacodec-embed-render-mode': 'boolean'};
    final owner = HdrNativeDvOptionOwner(
        readProperty: (name) async => values[name]!,
        setPropertyStrict: (_, __) async {},
        readIdentity: () async => source);
    await expectLater(
        owner.begin(
            stoppedIdentity: source, vd: 'native_dv=1', renderMode: 'timed'),
        throwsStateError);
    expect(owner.active, isFalse);
  });
  test('timeout then own late load permits stop/reset and a new open',
      () async {
    final f = Fixture();
    await f.begin();
    final before = f.source;
    final pending = HdrNativeDvPendingOpen(
        before: before, mediaUri: 'test://p5', playlistEntryId: 7);
    f.source = f.identity(entry: '7');
    await expectLater(
        pending.confirmForCleanup(
            readIdentity: () async => f.source,
            readPlaylistFilename: () async => 'test://p5',
            waitForFileLoadedEntry: (_, __) =>
                Completer<FileLoadedRecord>().future,
            requireLoaded: true,
            budget: const Duration(milliseconds: 1)),
        throwsA(isA<TimeoutException>()));
    expect(f.owner.identity, before);
    f.source = f.identity(path: 'test://p5', entry: '7', epoch: 1);
    final late = await pending.confirmForCleanup(
        readIdentity: () async => f.source,
        readPlaylistFilename: () async => 'test://p5',
        waitForFileLoadedEntry: (_, __) async => FileLoadedRecord(1, 7));
    await f.owner.rebind(before, late);
    await f.owner.assertCurrent();
    f.source = f.identity(epoch: 1);
    final stopped = await pending.confirmForCleanup(
        readIdentity: () async => f.source,
        readPlaylistFilename: () async =>
            throw StateError('stopped: no filename'),
        waitForFileLoadedEntry: (_, __) async => FileLoadedRecord(1, 7),
        afterOwnStop: true);
    await f.owner.rebind(late, stopped);
    await f.owner.restore();
    expect(
        f.values, {'vd-lavc-o': '', 'mediacodec-embed-render-mode': 'boolean'});
    await f.begin();
    final nextBefore = f.source;
    f.source = f.identity(path: 'test://next', entry: '8', epoch: 2);
    final next = await HdrNativeDvPendingOpen(
            before: nextBefore, mediaUri: 'test://next', playlistEntryId: 8)
        .confirmForCleanup(
            readIdentity: () async => f.source,
            readPlaylistFilename: () async => 'test://next',
            waitForFileLoadedEntry: (_, __) async => FileLoadedRecord(2, 8),
            requireLoaded: true);
    await f.owner.rebind(nextBefore, next);
    await f.owner.verify();
    expect(f.owner.active, isTrue);
  });
  test('timed-out own entry can be stopped before FILE_LOADED arrives',
      () async {
    final f = Fixture();
    await f.begin();
    final before = f.source;
    final pending = HdrNativeDvPendingOpen(
        before: before, mediaUri: 'test://p5', playlistEntryId: 7);
    f.source = f.identity(entry: '7');
    final loading = await pending.confirmForCleanup(
        readIdentity: () async => f.source,
        readPlaylistFilename: () async => 'test://p5',
        waitForFileLoadedEntry: (_, __) async =>
            throw StateError('must not wait'));
    await f.owner.rebind(before, loading);
    // Its own first event races with the native stop, after the pre-stop check.
    f.source = f.identity(epoch: 1);
    final stopped = await pending.confirmForCleanup(
        readIdentity: () async => f.source,
        readPlaylistFilename: () async => '',
        waitForFileLoadedEntry: (_, __) async => FileLoadedRecord(1, 7),
        afterOwnStop: true);
    await f.owner.rebind(loading, stopped);
    await f.owner.restore();
    expect(f.owner.active, isFalse);
  });
  test('pending cleanup rejects external same URI entry, path and epoch drift',
      () async {
    for (final failure in [
      'entry',
      'path',
      'filename',
      'epoch',
      'record',
      'recordEpoch',
      'player',
      'stopped'
    ]) {
      final f = Fixture();
      await f.begin();
      final before = f.source;
      final pending = HdrNativeDvPendingOpen(
          before: before, mediaUri: 'test://p5', playlistEntryId: 7);
      f.source = f.identity(
          path: failure == 'stopped'
              ? ''
              : failure == 'path'
                  ? 'external'
                  : 'test://p5',
          entry: failure == 'stopped'
              ? ''
              : failure == 'entry'
                  ? '8'
                  : '7',
          epoch: failure == 'epoch' ? 2 : 1,
          otherPlayer: failure == 'player' ? Object() : null);
      await expectLater(
          pending.confirmForCleanup(
              readIdentity: () async => f.source,
              readPlaylistFilename: () async =>
                  failure == 'filename' ? 'external' : 'test://p5',
              waitForFileLoadedEntry: (_, __) async => FileLoadedRecord(
                  failure == 'recordEpoch' ? 2 : 1,
                  failure == 'record' ? 8 : 7)),
          throwsStateError);
      expect(f.owner.identity, before);
      f.writes.clear();
      await expectLater(
          f.owner.restore(), throwsA(isA<HdrNativeDvOptionFailure>()));
      expect(f.writes, isEmpty);
    }
  });
  test('production open capture holds shared lock against same-URI public open',
      () async {
    final f = Fixture();
    await f.begin();
    final lock = Lock();
    final reading = Completer<void>();
    final release = Completer<void>();
    var firstRead = true;
    var externalRan = false;
    HdrNativeDvPendingOpen? saved;
    final capture = AndroidHdrBackend.captureNativeDvOpenUnderLock(
        lock: lock,
        options: f.owner,
        mediaUri: 'test://p5',
        openWithoutLock: () async {
          f.source = f.identity(entry: '7');
        },
        readProperty: (name) async {
          if (name == 'playlist/0/filename' && firstRead) {
            firstRead = false;
            reading.complete();
            await release.future;
          }
          return name == 'playlist/0/id'
              ? f.source.playlistEntryId
              : 'test://p5';
        },
        onCaptured: (entry) {
          saved = entry;
        });
    await reading.future;
    // This uses exactly the lock protocol of public open(synchronized:true).
    final external = lock.synchronized(() async {
      externalRan = true;
      // The only loaded event belongs to the external same-URI entry.
      f.source = f.identity(path: 'test://p5', entry: '8', epoch: 1);
    });
    await pumpEventQueue();
    expect(externalRan, isFalse);
    release.complete();
    final own = await capture;
    await external;
    expect(saved, same(own));
    expect(own.playlistEntryId, 7);
    expect(externalRan, isTrue);
    await expectLater(
        AndroidHdrBackend.confirmNativeDvOpenIdentity(
            before: own.before,
            mediaUri: own.mediaUri,
            expectedPlaylistEntryId: own.playlistEntryId,
            readIdentity: () async => f.source,
            readPlaylistFilename: () async => 'test://p5',
            waitForFileLoadedEntry: (_, __) async => FileLoadedRecord(1, 8)),
        throwsStateError);
    f.writes.clear();
    await expectLater(
        f.owner.restore(), throwsA(isA<HdrNativeDvOptionFailure>()));
    expect(f.writes, isEmpty);
  });
  test('production entry capture releases lock before FILE_LOADED waiting',
      () async {
    final f = Fixture();
    await f.begin();
    final lock = Lock();
    final own = await AndroidHdrBackend.captureNativeDvOpenUnderLock(
        lock: lock,
        options: f.owner,
        mediaUri: 'test://p5',
        openWithoutLock: () async {
          f.source = f.identity(entry: '7');
        },
        readProperty: (name) async =>
            name == 'playlist/0/id' ? f.source.playlistEntryId : 'test://p5',
        onCaptured: (_) {});
    final waiting = Completer<void>();
    final event = Completer<FileLoadedRecord>();
    final confirming = AndroidHdrBackend.confirmNativeDvOpenIdentity(
        before: own.before,
        mediaUri: own.mediaUri,
        expectedPlaylistEntryId: own.playlistEntryId,
        readIdentity: () async => f.source,
        readPlaylistFilename: () async => 'test://p5',
        waitForFileLoadedEntry: (_, __) {
          waiting.complete();
          return event.future;
        });
    final rejected = expectLater(confirming, throwsStateError);
    await waiting.future;
    await lock.synchronized(() async {
      f.source = f.identity(path: 'test://p5', entry: '8', epoch: 1);
    });
    event.complete(FileLoadedRecord(1, 7));
    await rejected;
  });

  test('production stop captures proof before admitting another open',
      () async {
    final f = Fixture();
    await f.begin();
    final before = f.source;
    f.source = f.identity(path: 'test://p5', entry: '7', epoch: 1);
    await f.owner.rebind(before, f.source);
    final lock = Lock();
    final reading = Completer<void>();
    final release = Completer<void>();
    var externalRan = false;
    var stopCalls = 0;
    final stopping = AndroidHdrBackend.captureNativeDvStopUnderLock(
        lock: lock,
        options: f.owner,
        onStopIssued: (_) {},
        stopWithoutLock: () async {
          stopCalls++;
          f.source = f.identity(epoch: 1);
        },
        readIdentity: () async {
          reading.complete();
          await release.future;
          return f.source;
        });
    await reading.future;
    final external = lock.synchronized(() async {
      externalRan = true;
      f.source = f.identity(path: 'test://p5', entry: '8', epoch: 2);
    });
    await pumpEventQueue();
    expect(externalRan, isFalse);
    release.complete();
    final proof = await stopping;
    await external;
    expect(proof.before.playlistEntryId, '7');
    expect(proof.stopped.playlistEntryId, '');
    expect(proof.stopped.fileLoadedEpoch, 1);
    // Reacquiring the same lock must reject the stale proof. The external
    // source is neither adopted nor stopped by our old transaction.
    await expectLater(
        AndroidHdrBackend.rebindNativeDvUnderLock(
            lock: lock,
            options: f.owner,
            before: proof.before,
            confirmed: proof.stopped),
        throwsStateError);
    expect(stopCalls, 1);
    expect(f.source.playlistEntryId, '8');
    f.writes.clear();
    await expectLater(
        f.owner.restore(), throwsA(isA<HdrNativeDvOptionFailure>()));
    expect(f.writes, isEmpty);
  });
  test(
      'production capture/stop recover timed-out own entry and permit new open',
      () async {
    final f = Fixture();
    await f.begin();
    final lock = Lock();
    HdrNativeDvPendingOpen? pending;
    var stopIssued = false;
    Future<HdrNativeDvPendingOpen> capture(int id) =>
        AndroidHdrBackend.captureNativeDvOpenUnderLock(
            lock: lock,
            options: f.owner,
            mediaUri: 'test://p5',
            openWithoutLock: () async {
              f.source =
                  f.identity(entry: '$id', epoch: f.source.fileLoadedEpoch);
            },
            readProperty: (name) async => name == 'playlist/0/id'
                ? f.source.playlistEntryId
                : 'test://p5',
            onCaptured: (entry) {
              pending = entry;
            });
    final own = await capture(7);
    await expectLater(
        AndroidHdrBackend.confirmNativeDvOpenIdentity(
            before: own.before,
            mediaUri: own.mediaUri,
            expectedPlaylistEntryId: 7,
            readIdentity: () async => f.source,
            readPlaylistFilename: () async => 'test://p5',
            waitForFileLoadedEntry: (_, __) =>
                Completer<FileLoadedRecord>().future,
            budget: const Duration(milliseconds: 1)),
        throwsA(isA<TimeoutException>()));
    f.source = f.identity(path: 'test://p5', entry: '7', epoch: 1);
    Future<HdrOptionSourceIdentity> confirm({bool stopped = false}) =>
        pending!.confirmForCleanup(
            readIdentity: () async => f.source,
            readPlaylistFilename: () async => 'test://p5',
            waitForFileLoadedEntry: (_, __) async {
              // Matching records are awaited with the Player lock released.
              expect(lock.locked, isFalse);
              return FileLoadedRecord(1, 7);
            },
            afterOwnStop: stopped);
    final loaded = await confirm();
    await AndroidHdrBackend.rebindNativeDvUnderLock(
        lock: lock,
        options: f.owner,
        before: f.owner.identity!,
        confirmed: loaded);
    final proof = await AndroidHdrBackend.captureNativeDvStopUnderLock(
        lock: lock,
        options: f.owner,
        onStopIssued: (_) {
          stopIssued = true;
        },
        stopWithoutLock: () async {
          expect(stopIssued, isTrue);
          f.source = f.identity(epoch: 1);
        },
        readIdentity: () async => f.source);
    final closed = await confirm(stopped: true);
    expect(closed, proof.stopped);
    await AndroidHdrBackend.rebindNativeDvUnderLock(
        lock: lock, options: f.owner, before: proof.before, confirmed: closed);
    pending = null;
    await lock.synchronized(f.owner.restore);
    expect(f.owner.active, isFalse);
    await lock.synchronized(f.begin);
    final next = await capture(8);
    expect(next.before.fileLoadedEpoch, 1);
    expect(next.playlistEntryId, 8);
  });
}

Future<StateError> captureFailureObject({
  required Lock lock,
  required HdrOptionSourceIdentity first,
  HdrOptionSourceIdentity? second,
  required void Function() onRead,
}) async {
  final identities = <HdrOptionSourceIdentity>[
    first,
    if (second != null) second,
  ];
  var index = 0;
  try {
    await AndroidHdrBackend.captureStoppedBoundaryUnderLock(
      lock: lock,
      stopWithoutLock: () async {},
      readIdentity: () async {
        onRead();
        return identities[index++];
      },
    );
  } on StateError catch (error) {
    return error;
  }
  throw StateError('Expected the actual backend method to reject identity');
}
