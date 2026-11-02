import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit_hdr_lab/common/android_p84_lifecycle_probe.dart';
import 'package:media_kit_hdr_lab/common/android_p84_quality_probe.dart';

class Fixture {
  P84LifecycleOwner? owner =
      const P84LifecycleOwner(1, 2, 3, 4, '/local/p84.mp4');
  final initial = const P84LifecycleOwner(1, 2, 3, 4, '/local/p84.mp4');
  String mode = '1';
  bool changeModeAfterRead = false;
  int modeReads = 0;
  double position = 0;
  double seekOffset = 0;
  bool truncateSeekToMillis = false;
  bool paused = false;
  bool moving = false;
  bool wrongRoute = false;
  int pendingSeekingReads = 0;
  final propertyOverrides = <String, String>{};
  final faults = {
    'debug.mks.yuv_fail_commit': '0',
    'debug.mks.yuv_fail_gl': '0'
  };
  Completer<void>? blockedSeek;
  Completer<void>? blockedRecord;
  final heartbeatTicks = <Completer<void>>[];
  final rows = <Map<String, Object?>>[];
  late final probe = AndroidP84QualityProbe(
    owner: initial,
    currentOwner: () => owner,
    readProperty: (name) async {
      if (name == 'seeking' && pendingSeekingReads > 0) {
        pendingSeekingReads--;
        return 'yes';
      }
      if (name == 'time-pos') {
        if (moving) position += 0.001;
        return '$position';
      }
      if (propertyOverrides.containsKey(name)) return propertyOverrides[name]!;
      return {
            'pause': paused ? 'yes' : 'no',
            'seeking': 'no',
            'path': initial.sourcePath,
            'hwdec-current': 'surfacetexture',
            'vo': 'gpu-next',
            'target-trc': 'pq',
            'target-prim': 'bt.2020',
            'target-peak': '1000',
            'gamma': '0',
            'duration': '1170',
            'container-fps': '29.970029970',
            'video-sync': 'display-resample',
            'video-params/w': '3840',
            'video-params/h': '1920',
            'video-params/gamma': 'hlg',
            'video-params/primaries': 'bt.2020',
            'current-tracks/video/dolby-vision-profile': '8',
            'current-tracks/video/dolby-vision-compatibility-id': '4',
          }[name] ??
          '';
    },
    readFusionMode: () async {
      modeReads++;
      return changeModeAfterRead && modeReads > 1 ? '0' : mode;
    },
    expectedFusionMode: '1',
    readFaultModes: () async => Map<String, String>.of(faults),
    readReport: () => {
      'generation': 4,
      'verified': !wrongRoute,
      'error': null,
      'source': {
        'kind': 'dolbyVisionP84',
        'dvProfile': 8,
        'dvCompatibilityId': 4
      },
      'actual': {'strategy': 'baseLayerConvert', 'hwdec': 'surfacetexture'},
    },
    setPaused: (value) async {
      paused = value;
    },
    seek: (target) async {
      if (blockedSeek != null) await blockedSeek!.future;
      position = (truncateSeekToMillis
              ? target.inMilliseconds / 1000
              : target.inMicroseconds / 1000000) +
          seekOffset;
    },
    record: (row) async {
      rows.add(row);
      if (row['status'] == 'ready-for-observation' && blockedRecord != null) {
        await blockedRecord!.future;
      }
    },
    changed: () {},
    delay: (_) async {},
    heartbeatDelay: (_) {
      final tick = Completer<void>();
      heartbeatTicks.add(tick);
      return tick.future;
    },
    maxPolls: 5,
  );
}

void main() {
  test('ready persists exact requested and stable actual position with mode',
      () async {
    final f = Fixture();
    await f.probe.observe(35.035);
    final row = f.rows.last;
    expect(row['status'], 'ready-for-observation');
    expect(row['actualPosition'], 35.035);
    expect(row['requestedFusionMode'], '1');
    expect(f.paused, true);
    expect(f.probe.busy, false);
  });
  test('submillisecond representation difference accepted and recorded',
      () async {
    final f = Fixture()..seekOffset = 0.0005;
    await f.probe.observe(35.035);
    expect(f.rows.last['actualPosition'], closeTo(35.0355, 1e-8));
  });
  test('inaccurate seek fails rather than marking ready', () async {
    final f = Fixture()..seekOffset = 0.04;
    await expectLater(f.probe.observe(35.035), throwsStateError);
    expect(f.rows.last['status'], 'failed');
  });
  test('moving position never marks ready even when paused is reported',
      () async {
    final f = Fixture()..moving = true;
    await expectLater(f.probe.observe(35.035), throwsStateError);
    expect(f.rows.last['status'], 'failed');
  });
  test('unverified route rejects observation', () async {
    final f = Fixture()..wrongRoute = true;
    await expectLater(f.probe.observe(35.035), throwsStateError);
    expect(f.rows.last['status'], 'failed');
  });
  test('fusion mode must be explicitly set for process restart', () async {
    final f = Fixture()..mode = '';
    await expectLater(f.probe.observe(35.035), throwsStateError);
    expect(f.paused, false);
  });
  test('source replacement while seek pending cannot emit stale ready',
      () async {
    final f = Fixture()..blockedSeek = Completer<void>();
    final work = f.probe.observe(35.035);
    await Future<void>.delayed(Duration.zero);
    f.owner = const P84LifecycleOwner(1, 2, 5, 6, '/local/other.mp4');
    f.blockedSeek!.complete();
    await expectLater(work, throwsStateError);
    expect(f.rows.last['status'], 'cancelled');
  });
  test('cancel drains pending native operation and suppresses ready', () async {
    final f = Fixture()..blockedSeek = Completer<void>();
    final work = f.probe.observe(35.035);
    await Future<void>.delayed(Duration.zero);
    final stop = f.probe.cancelAndDrain();
    f.blockedSeek!.complete();
    await expectLater(work, throwsStateError);
    await stop;
    expect(f.rows.last['status'], 'cancelled');
    expect(f.probe.closed, true);
  });
  for (final item in <String, List<String>>{
    'current-tracks/video/dolby-vision-profile': ['', '5', 'unknown'],
    'current-tracks/video/dolby-vision-compatibility-id': ['', '1', 'unknown'],
    'video-params/w': ['', '0', '-1', '3840.5'],
    'video-params/h': ['', '0', '-1'],
    'video-params/gamma': ['', 'pq', 'bt.1886'],
    'video-params/primaries': ['', 'bt.709'],
  }.entries) {
    for (final value in item.value) {
      test('current property ${item.key}=$value rejects cached verified route',
          () async {
        final f = Fixture()..propertyOverrides[item.key] = value;
        await expectLater(f.probe.observe(35.035), throwsStateError);
        expect(f.rows.last['status'], 'failed');
      });
    }
  }
  for (final key in AndroidP84QualityProbe.faultProperties) {
    test('fault residue $key rejects before pause/seek', () async {
      final f = Fixture()..faults[key] = '1';
      await expectLater(f.probe.observe(35.035), throwsStateError);
      expect(f.paused, false);
      expect(f.rows.last['status'], 'failed');
    });
    test('missing fault read $key rejects', () async {
      final f = Fixture()..faults.remove(key);
      await expectLater(f.probe.observe(35.035), throwsStateError);
      expect(f.paused, false);
    });
  }
  test('mode change during seek is recorded as failure', () async {
    final f = Fixture()..changeModeAfterRead = true;
    await expectLater(f.probe.observe(35.035), throwsStateError);
    expect(f.rows.last['status'], 'failed');
  });
  test('cancel during persistent write invalidates prior ready row', () async {
    final f = Fixture()..blockedRecord = Completer<void>();
    final work = f.probe.observe(35.035);
    while (!f.rows.any((r) => r['status'] == 'ready-for-observation')) {
      await Future<void>.delayed(Duration.zero);
    }
    final stop = f.probe.cancelAndDrain();
    f.blockedRecord!.complete();
    await expectLater(work, throwsStateError);
    await stop;
    expect(f.rows.map((r) => r['status']),
        ['seek-started', 'ready-for-observation', 'cancelled']);
  });
  test('heartbeat reads fresh paused state and invalidates resume', () async {
    final f = Fixture();
    await f.probe.observe(35.035);
    f.heartbeatTicks.last.complete();
    while (!f.rows.any((r) => r['status'] == 'observation-heartbeat')) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(f.rows.last['heartbeat'], 1);
    f.paused = false;
    f.heartbeatTicks.last.complete();
    while (f.rows.last['status'] != 'invalidated') {
      await Future<void>.delayed(Duration.zero);
    }
    expect(f.rows.last['status'], 'invalidated');
    await f.probe.cancelAndDrain();
  });
  test(
      'second observation drains old monitor and cancellation leaves no late rows',
      () async {
    final f = Fixture();
    await f.probe.observe(35.035);
    final oldTick = f.heartbeatTicks.last;
    await f.probe.observe(600.032766667);
    final newTick = f.heartbeatTicks.last;
    expect(identical(oldTick, newTick), false);
    expect(f.rows.map((r) => r['ordinal']), [1, 1, 2, 2]);
    final count = f.rows.length;
    oldTick.complete();
    await Future<void>.delayed(Duration.zero);
    expect(f.rows.length, count);
    await f.probe.cancelAndDrain();
    newTick.complete();
    await Future<void>.delayed(Duration.zero);
    expect(f.rows.length, count);
  });
  test('real millisecond pending target may settle to same decoded PTS',
      () async {
    final f = Fixture()..truncateSeekToMillis = true;
    await f.probe.observe(600.032766667);
    expect(f.rows.last['actualPosition'], closeTo(600.032, 1e-9));
    f.position = 600.032766667;
    f.heartbeatTicks.last.complete();
    while (!f.rows.any((r) => r['status'] == 'observation-heartbeat')) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(f.rows.last['actualPosition'], 600.032766667);
    expect(f.rows.last['acceptedPosition'], closeTo(600.032, 1e-9));
    expect(f.rows.last['positionToleranceSeconds'], 0.001002);
    expect(f.rows.last['status'], 'observation-heartbeat');
    await f.probe.cancelAndDrain();
  });
  test('neighbouring frame and larger than millisecond drift invalidate',
      () async {
    for (final drift in [0.00101, 1001 / 30000]) {
      final f = Fixture();
      await f.probe.observe(600.032766667);
      f.position += drift;
      f.heartbeatTicks.last.complete();
      while (f.rows.last['status'] != 'invalidated') {
        await Future<void>.delayed(Duration.zero);
      }
      expect(f.rows.last['status'], 'invalidated');
      expect(f.rows.last['error'], contains('accepted='));
      expect(f.rows.last['error'], contains('target='));
      await f.probe.cancelAndDrain();
    }
  });
  test('pending seek resets stability and cannot become ready', () async {
    final f = Fixture()..pendingSeekingReads = 5;
    await expectLater(f.probe.observe(600.032766667), throwsStateError);
    expect(f.rows.last['status'], 'failed');
    expect(
        f.rows.where((r) => r['status'] == 'ready-for-observation'), isEmpty);
  });
  test('seek completion requires four newly stable polls', () async {
    final f = Fixture()..pendingSeekingReads = 1;
    await f.probe.observe(600.032766667);
    expect(f.rows.last['status'], 'ready-for-observation');
    expect((f.rows.last['properties'] as Map)['seeking'], 'no');
    await f.probe.cancelAndDrain();
  });
  test('new seek during heartbeat invalidates observation', () async {
    final f = Fixture();
    await f.probe.observe(600.032766667);
    f.pendingSeekingReads = 1;
    f.heartbeatTicks.last.complete();
    while (f.rows.last['status'] != 'invalidated') {
      await Future<void>.delayed(Duration.zero);
    }
    expect(f.rows.last['status'], 'invalidated');
    await f.probe.cancelAndDrain();
  });
  test('cancel drains heartbeat without waiting for sleeping timer', () async {
    final f = Fixture();
    await f.probe.observe(35.035);
    await f.probe.cancelAndDrain();
    expect(f.probe.closed, true);
    expect(
        f.rows.where((r) => r['status'] == 'observation-heartbeat'), isEmpty);
  });
  test('concurrent action rejected without a second seek', () async {
    final f = Fixture()..blockedSeek = Completer<void>();
    final work = f.probe.observe(35.035);
    await Future<void>.delayed(Duration.zero);
    await expectLater(f.probe.observe(600), throwsStateError);
    f.blockedSeek!.complete();
    await work;
    expect(f.rows.length, 2);
  });
}
