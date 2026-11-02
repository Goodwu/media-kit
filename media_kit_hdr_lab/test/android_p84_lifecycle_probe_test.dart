import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit_hdr_lab/common/android_p84_lifecycle_probe.dart';

class Fixture {
  P84LifecycleOwner owner =
      const P84LifecycleOwner(1, 2, 3, 4, '/local/p84.mp4');
  double position = 8;
  bool paused = false;
  bool completed = false;
  int eventEpoch = 0;
  int falseEpoch = 0;
  int trueEpoch = 0;
  bool pendingCompletion = false;
  bool suppressSeekCompletionEvents = false;
  bool noOpStop = false;
  bool stopped = false;
  bool wrongRouteAfterReopen = false;
  String targetPeak = '1000';
  List<Map<String, String>> nativeRows = [];
  int reopenCount = 0;
  final rows = <Map<String, dynamic>>[];
  final delays = <Duration>[];
  final mutations = <String>[];
  final reads = <String>[];
  Completer<String>? blockedRead;
  bool wrongReopenIdentity = false;
  late final probe = AndroidP84LifecycleProbe(
    owner: owner,
    currentOwner: () => owner,
    readProperty: (name) async {
      reads.add(name);
      if (name == 'hwdec-current' && blockedRead != null) {
        return blockedRead!.future;
      }
      if (name == 'time-pos') {
        if (stopped) return '';
        if (!paused) position += 0.2;
        return '$position';
      }
      return {
            'duration': '40',
            'path': stopped ? '' : owner.sourcePath,
            'idle-active': stopped ? 'yes' : 'no',
            'pause': paused ? 'yes' : 'no',
            'hwdec-current': 'surfacetexture',
            'vo': 'gpu-next',
            'target-trc': 'pq',
            'target-prim': 'bt.2020',
            'target-peak': targetPeak,
            'gamma': '0',
            'video-sync': 'audio',
          }[name] ??
          '0';
    },
    readReport: () => {
      'verified': true,
      'generation': owner.generation,
      'error': null,
      'source': {
        'kind': wrongRouteAfterReopen && reopenCount > 0
            ? 'hdr10'
            : 'dolbyVisionP84',
        'dvProfile': 8,
        'dvCompatibilityId': 4
      },
      'actual': {'strategy': 'baseLayerConvert', 'hwdec': 'surfacetexture'},
    },
    readNativeCounters: () => nativeRows,
    setPaused: (value) async {
      paused = value;
      mutations.add('pause=$value');
    },
    seek: (target) async {
      position = target.inMilliseconds / 1000;
      if (!suppressSeekCompletionEvents) {
        completed = false;
        falseEpoch = ++eventEpoch;
      }
      // EOF is a real state change and always fires, suppressed or not.
      pendingCompletion = position >= 38;
      mutations.add('seek=${target.inMilliseconds}');
    },
    stopPlayer: () async {
      mutations.add('stop');
      if (!noOpStop) stopped = true;
    },
    reopen: () async {
      reopenCount++;
      owner = P84LifecycleOwner(
          wrongReopenIdentity ? 99 : owner.session,
          owner.player,
          owner.serial + 1,
          owner.generation + 1,
          owner.sourcePath);
      position = 0;
      paused = false;
      completed = false;
      stopped = false;
      falseEpoch = ++eventEpoch;
      return owner;
    },
    readCompletion: () =>
        P84CompletionObservation(completed, eventEpoch, falseEpoch, trueEpoch),
    record: (row) async =>
        rows.add(jsonDecode(jsonEncode(row)) as Map<String, dynamic>),
    changed: () {},
    settleTimeout: const Duration(milliseconds: 20),
    delay: (duration) async {
      delays.add(duration);
      if (pendingCompletion) {
        completed = true;
        pendingCompletion = false;
        trueEpoch = ++eventEpoch;
      }
    },
  );
}

void main() {
  test(
      'pause holds three seconds and resumes; action name does not prove redraw',
      () async {
    final f = Fixture();
    await f.probe.run(P84LifecycleAction.pauseHoldResume);
    expect(f.delays, contains(const Duration(seconds: 3)));
    expect(f.mutations, ['pause=true', 'pause=false']);
    expect(f.rows.last['result'], 'functional_only');
    expect(f.rows.last['nativeEvidence']['status'], 'unverified');
    expect(f.rows.last['redrawCoverage'], 'unverified');
    expect(f.probe.busy, isFalse);
  });

  test('both forward/back seeks remain paused, then progress resumes',
      () async {
    final f = Fixture();
    await f.probe.run(P84LifecycleAction.seekForwardBack);
    final seeks = f.rows
        .where((row) => '${row['step']}'.startsWith('paused-seek'))
        .toList();
    expect(seeks, hasLength(2));
    expect(seeks.every((row) => row['properties']['pause'] == 'yes'), isTrue);
    expect(double.parse(seeks.first['properties']['time-pos']),
        greaterThan(double.parse(seeks.last['properties']['time-pos'])));
    expect(f.rows.last['redrawCoverage'], 'unverified');
  });

  test(
      'EOF replay requires actual completed and accepts only the owned rebuild',
      () async {
    final f = Fixture();
    await f.probe.run(P84LifecycleAction.nearEOFReplay);
    final eof =
        f.rows.singleWhere((row) => row['step'] == 'real-eof-completed');
    expect(eof['completion']['completed'], isTrue);
    expect(eof['completion']['lastTrueEpoch'],
        greaterThan(eof['completion']['lastFalseEpoch']));
    expect(f.reopenCount, 1);
    expect(f.probe.owner, f.owner);
    expect(f.probe.owner.serial, 4);
    expect(f.rows.last['result'], 'functional_only');
    final invalid = Fixture()..wrongReopenIdentity = true;
    await expectLater(
        invalid.probe.run(P84LifecycleAction.stopReopen), throwsStateError);
    expect(invalid.rows.last['result'], 'failed');
  });

  test('stop/reopen does not wait on its own action and advances identity',
      () async {
    final f = Fixture();
    await f.probe.run(P84LifecycleAction.stopReopen);
    expect(f.mutations, ['stop']);
    expect(f.reopenCount, 1);
    expect(
        f.rows.any((row) =>
            row['step'] == 'stopped-before-reopen' &&
            row['expectedRunning'] == false),
        isTrue);
    expect(f.rows.last['result'], 'functional_only');
  });

  test(
      'mid-playback EOF seek needs no completed=false change event (change-driven stream)',
      () async {
    // Regression for the on-device failure: seeking from mid-playback keeps
    // completed=false, so the change-driven stream never publishes a new
    // false event; the action must proceed on the settled state alone.
    final f = Fixture()..suppressSeekCompletionEvents = true;
    await f.probe.run(P84LifecycleAction.nearEOFReplay);
    final eof =
        f.rows.singleWhere((row) => row['step'] == 'real-eof-completed');
    expect(eof['completion']['completed'], isTrue);
    expect(f.reopenCount, 1);
    expect(f.rows.last['result'], 'functional_only');
  });

  test('an old completed=true without a new seek false event cannot replay',
      () async {
    final f = Fixture()
      ..completed = true
      ..eventEpoch = 5
      ..trueEpoch = 5
      ..suppressSeekCompletionEvents = true;
    await expectLater(
        f.probe.run(P84LifecycleAction.nearEOFReplay), throwsStateError);
    expect(f.reopenCount, 0);
    expect(f.rows.last['result'], 'failed');
  });

  test('a no-op stop is rejected before reopen', () async {
    final f = Fixture()..noOpStop = true;
    await expectLater(
        f.probe.run(P84LifecycleAction.stopReopen), throwsStateError);
    expect(f.reopenCount, 0);
    expect(f.rows.last['result'], 'failed');
  });

  test('reopen with a wrong source route fails despite verified=true',
      () async {
    final f = Fixture()..wrongRouteAfterReopen = true;
    await expectLater(
        f.probe.run(P84LifecycleAction.stopReopen), throwsStateError);
    expect(f.rows.last['result'], 'failed');
    expect(f.rows.last['error'], contains('clean P8.4 convert'));
  });

  test(
      'malformed native data remains unverified, never becomes zero-error pass',
      () async {
    final f = Fixture()..targetPeak = '1000.000000';
    f.nativeRows = [
      {
        'kind': 'import',
        'pid': '$pid',
        'instance': '0x1',
        'start_ns': '10',
        'mono_ns': '20',
        '_receivedAtMicros': '${DateTime.now().microsecondsSinceEpoch}',
        'lease_copy': '2',
        'latch': '2',
        'defer_publish_flush': '1',
        'fence_create_failed': '0',
        'reap_stuck': '0',
        'latch_timeout': '0',
        'stale_drop': 'unavailable',
      }
    ];
    await f.probe.run(P84LifecycleAction.pauseHoldResume);
    expect(f.rows.last['result'], 'functional_only');
    expect(f.rows.last['candidateAcceptance'], contains('requires_host'));
    expect(f.rows.last['nativeEvidence']['status'], 'unverified');
    expect(f.rows.last['nativeEvidence']['issues'],
        contains('missing/invalid stale_drop'));
  });

  test('native publish policy mismatch fails this run', () async {
    final f = Fixture();
    f.nativeRows = [
      {
        'kind': 'import',
        'pid': '$pid',
        'instance': '0x1',
        'start_ns': '10',
        'mono_ns': '20',
        '_receivedAtMicros': '${DateTime.now().microsecondsSinceEpoch}',
        'lease_copy': '2',
        'latch': '2',
        'defer_publish_flush': '0',
        'fence_create_failed': '0',
        'reap_stuck': '0',
        'latch_timeout': '0',
        'stale_drop': '0',
      }
    ];
    await expectLater(
        f.probe.run(P84LifecycleAction.pauseHoldResume), throwsStateError);
    expect(f.rows.last['result'], 'failed');
    expect(f.rows.last['error'], contains('publish policy mismatch'));
  });

  test(
      'ExitCancel drains real in-flight reads and never mutates a replacement owner',
      () async {
    final f = Fixture()..blockedRead = Completer<String>();
    final action = f.probe.run(P84LifecycleAction.pauseHoldResume);
    final expectedFailure = expectLater(action, throwsStateError);
    while (!f.reads.contains('hwdec-current')) {
      await Future<void>.delayed(Duration.zero);
    }
    await expectLater(
        f.probe.run(P84LifecycleAction.stopReopen), throwsStateError);
    var drained = false;
    final close = f.probe.cancelAndDrain().then((_) => drained = true);
    f.owner = const P84LifecycleOwner(9, 8, 7, 6, '/new/source.mp4');
    await Future<void>.delayed(Duration.zero);
    expect(drained, isFalse);
    f.blockedRead!.complete('surfacetexture');
    await expectedFailure;
    await close;
    expect(f.mutations, isEmpty);
    expect(f.reads.last, 'hwdec-current');
    expect(f.rows.last['result'], 'cancelled');
  });

  testWidgets(
      'controls expose named actions; busy disables all except ExitCancel',
      (tester) async {
    var exited = false;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: AndroidP84LifecycleControls(
      ready: true,
      busy: true,
      run: (_) {},
      exit: () => exited = true,
    ))));
    for (final action in P84LifecycleAction.values) {
      expect(find.byTooltip('P84 ${action.label}'), findsOneWidget);
      final button = tester
          .widget<TextButton>(find.widgetWithText(TextButton, action.label));
      expect(button.onPressed, isNull);
    }
    await tester.tap(find.text('ExitCancel'));
    expect(exited, isTrue);
  });
}
