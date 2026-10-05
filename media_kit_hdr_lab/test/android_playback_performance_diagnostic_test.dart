// ignore_for_file: implementation_imports, depend_on_referenced_packages
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_hdr_lab/common/android_playback_performance_diagnostic.dart';
import 'package:synchronized/synchronized.dart';

void main() {
  const route = _Route(
    source: '/data/local/tmp/p5.mp4',
    epoch: 8,
    vo: 'gpu-next',
    hwdec: 'mediacodec-copy',
  );

  test('accepts consecutive explicitly requested samples with monotonic time',
      () async {
    final player = _FakePlayer(route);
    final sampler = AndroidPlaybackPerformanceDiagnostic(player: player);

    final first = await sampler.sample(
      expectedSource: route.source,
      expectedFileLoadedEpoch: route.epoch,
      expectedVo: route.vo,
      expectedHwdecCurrent: route.hwdec,
    );
    final second = await sampler.sample(
      expectedSource: route.source,
      expectedFileLoadedEpoch: route.epoch,
      expectedVo: route.vo,
      expectedHwdecCurrent: route.hwdec,
    );

    expect(first.accepted, isTrue);
    expect(second.accepted, isTrue);
    expect(sampler.rows, hasLength(2));
    expect(sampler.rows[0]['sampleOrdinal'], 1);
    expect(sampler.rows[1]['sampleOrdinal'], 2);
    expect(
      (sampler.rows[1]['hostElapsedMicros'] as int),
      greaterThanOrEqualTo(sampler.rows[0]['hostElapsedMicros'] as int),
    );
    expect(player.waitForInitializationValues, isNotEmpty);
    expect(player.waitForInitializationValues.every((value) => !value), isTrue);
    expect(player.lockedReads, player.reads.length);
  });

  test('identity drift rejects the sample and does not append it', () async {
    final player = _FakePlayer(route)
      ..onRead = (name, self) {
        if (name == 'time-pos') self.properties['path'] = '/other.mp4';
      };
    final sampler = AndroidPlaybackPerformanceDiagnostic(player: player);

    final result = await _sample(sampler, route);

    expect(result.accepted, isFalse);
    expect(result.reason, contains('identity-drift:path'));
    expect(result.identityBefore?['path'], route.source);
    expect(result.identityAfter?['path'], '/other.mp4');
    expect(sampler.rows, isEmpty);
  });

  test('file epoch and renderer identity are both part of the binding',
      () async {
    final changedRoute = route.copyWith(epoch: route.epoch + 1);
    final player = _FakePlayer(changedRoute);
    final sampler = AndroidPlaybackPerformanceDiagnostic(player: player);

    final epochResult = await _sample(sampler, route);
    expect(epochResult.accepted, isFalse);
    expect(epochResult.reason, contains('fileLoadedEpoch'));
    expect(sampler.rows, isEmpty);

    final wrongRenderer = _FakePlayer(route.copyWith(vo: 'other-vo'));
    final secondSampler = AndroidPlaybackPerformanceDiagnostic(
      player: wrongRenderer,
    );
    final rendererResult = await _sample(secondSampler, route);
    expect(rendererResult.accepted, isFalse);
    expect(rendererResult.reason, contains('vo'));
    expect(secondSampler.rows, isEmpty);
  });

  test('epoch changing during the final identity property read is rejected',
      () async {
    final player = _FakePlayer(route)
      ..onRead = (name, self) {
        if (name == 'hwdec-current') self.bumpEpoch();
      };
    final sampler = AndroidPlaybackPerformanceDiagnostic(player: player);

    final result = await _sample(sampler, route);

    expect(result.accepted, isFalse);
    expect(
        result.reason, contains('fileLoadedEpoch-drift-during-identity-read'));
    expect(sampler.rows, isEmpty);
  });

  test('unsupported metric property keeps its error instead of zero', () async {
    final error = UnsupportedError('property not available');
    final stack = StackTrace.current;
    final player = _FakePlayer(route)
      ..propertyErrors['vo-passes'] = (error, stack);
    final sampler = AndroidPlaybackPerformanceDiagnostic(player: player);

    final result = await _sample(sampler, route);

    expect(result.accepted, isTrue);
    final row = sampler.rows.single;
    expect((row['properties'] as Map).containsKey('vo-passes'), isFalse);
    final propertyError = (row['propertyErrors'] as Map)['vo-passes'] as Map;
    expect(propertyError['error'], contains('property not available'));
    expect(sampler.rawErrors, hasLength(1));
    expect(identical(sampler.rawErrors.single.error, error), isTrue);
    expect(identical(sampler.rawErrors.single.stackTrace, stack), isTrue);
    expect(identical(result.rawErrors.single.error, error), isTrue);
  });

  test('oversized property is bounded and explicitly marked truncated',
      () async {
    final player = _FakePlayer(route)..properties['vo-passes'] = 'x' * 3000;
    final sampler = AndroidPlaybackPerformanceDiagnostic(player: player);

    final result = await _sample(sampler, route);

    expect(result.accepted, isTrue);
    final row = sampler.rows.single;
    expect((row['properties'] as Map)['vo-passes'], hasLength(2048));
    expect((row['propertyTruncation'] as Map)['vo-passes'], {
      'truncated': true,
      'originalLength': 3000,
      'storedLength': 2048,
    });
  });

  test('overlapping invocation is rejected; drain waits for active read',
      () async {
    final player = _FakePlayer(route);
    final blockedRead = Completer<String>();
    player.blockProperty = 'time-pos';
    player.blockedPropertyResult = blockedRead;
    final sampler = AndroidPlaybackPerformanceDiagnostic(player: player);

    final firstFuture = _sample(sampler, route);
    final rejected = await _sample(sampler, route);
    expect(rejected.accepted, isFalse);
    expect(rejected.reason, 'sample-already-in-progress');
    expect(sampler.rows, isEmpty);

    var drained = false;
    final drainFuture = sampler.drain().then((rows) {
      drained = true;
      return rows;
    });
    await Future<void>.delayed(Duration.zero);
    expect(drained, isFalse);

    blockedRead.complete('1.0');
    final accepted = await firstFuture;
    final rows = await drainFuture;
    expect(accepted.accepted, isTrue);
    expect(drained, isTrue);
    expect(rows, hasLength(1));
  });

  test('row limit refuses further reads and preserves prior evidence',
      () async {
    final player = _FakePlayer(route);
    final sampler = AndroidPlaybackPerformanceDiagnostic(
      player: player,
      maxRows: 1,
    );
    expect((await _sample(sampler, route)).accepted, isTrue);
    final readsBefore = player.reads.length;

    final result = await _sample(sampler, route);

    expect(result.accepted, isFalse);
    expect(result.reason, 'row-capacity-reached');
    expect(player.reads.length, readsBefore);
    expect(sampler.rows, hasLength(1));
  });
}

Future<AndroidPlaybackPerformanceSampleResult> _sample(
  AndroidPlaybackPerformanceDiagnostic sampler,
  _Route route,
) =>
    sampler.sample(
      expectedSource: route.source,
      expectedFileLoadedEpoch: route.epoch,
      expectedVo: route.vo,
      expectedHwdecCurrent: route.hwdec,
    );

class _Route {
  const _Route({
    required this.source,
    required this.epoch,
    required this.vo,
    required this.hwdec,
  });

  final String source;
  final int epoch;
  final String vo;
  final String hwdec;

  _Route copyWith({int? epoch, String? vo}) => _Route(
        source: source,
        epoch: epoch ?? this.epoch,
        vo: vo ?? this.vo,
        hwdec: hwdec,
      );
}

class _FakePlayer implements Player {
  _FakePlayer(_Route route)
      : properties = {
          'path': route.source,
          'vo': route.vo,
          'hwdec-current': route.hwdec,
          'time-pos': '0.0',
          'duration': '30.0',
          'pause': 'no',
          'frame-drop-count': '0',
          'decoder-frame-drop-count': '0',
          'vo-delayed-frame-count': '0',
          'video-params': '1920x1080',
          'video-out-params': '1920x1080',
          'vo-passes': '1',
        },
        _epoch = route.epoch;

  final Map<String, String> properties;
  final Map<String, (Object, StackTrace?)> propertyErrors = {};
  final List<String> reads = [];
  final List<bool> waitForInitializationValues = [];
  @override
  final Lock lock = Lock();
  int _epoch;
  void Function(String name, _FakePlayer self)? onRead;
  String? blockProperty;
  Completer<String>? blockedPropertyResult;
  int lockedReads = 0;

  @override
  int get fileLoadedEpoch => _epoch;

  void bumpEpoch() => _epoch++;

  @override
  Future<String> getProperty(
    String name, {
    bool waitForInitialization = true,
  }) async {
    waitForInitializationValues.add(waitForInitialization);
    reads.add(name);
    lockedReads++;
    onRead?.call(name, this);
    final failure = propertyErrors[name];
    if (failure != null) Error.throwWithStackTrace(failure.$1, failure.$2!);
    if (name == blockProperty) return blockedPropertyResult!.future;
    return properties[name] ?? '';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
