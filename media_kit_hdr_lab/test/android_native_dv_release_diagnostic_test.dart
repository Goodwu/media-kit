import 'dart:convert';
import 'dart:io';
// ignore_for_file: depend_on_referenced_packages

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit_hdr_lab/common/android_native_dv_release_diagnostic.dart';
import 'package:media_kit_video/src/hdr/hdr_native_dv_option_owner.dart';
import 'package:media_kit_video/src/hdr/hdr_native_dv_review_evidence.dart';
import 'package:media_kit_video/src/video_controller/android_video_controller/platform_surface_release.dart';
import 'package:synchronized/synchronized.dart';

void main() {
  group('Release native DV diagnostic bounds', () {
    test('accepts only a 1 to 300 second window', () {
      expect(validateAndroidNativeDvReleaseDiagnosticSeconds(1), 1);
      expect(validateAndroidNativeDvReleaseDiagnosticSeconds(300), 300);
      expect(validateAndroidNativeDvReleaseDiagnosticIntervalSeconds(1), 1);
      expect(validateAndroidNativeDvReleaseDiagnosticIntervalSeconds(30), 30);
      expect(
        () => validateAndroidNativeDvReleaseDiagnosticSeconds(0),
        throwsRangeError,
      );
      expect(
        () => validateAndroidNativeDvReleaseDiagnosticSeconds(301),
        throwsRangeError,
      );
      expect(
        () => validateAndroidNativeDvReleaseDiagnosticIntervalSeconds(31),
        throwsRangeError,
      );
    });

    test('wall deadline is independent of sample count', () {
      expect(
        androidNativeDvDiagnosticDeadlineReached(
          elapsedMilliseconds: 299999,
          durationSeconds: 300,
        ),
        isFalse,
      );
      expect(
        androidNativeDvDiagnosticDeadlineReached(
          elapsedMilliseconds: 300000,
          durationSeconds: 300,
        ),
        isTrue,
      );
    });

    test('expired sampling budget does not start another native property read',
        () async {
      var starts = 0;
      expect(
        () => admitAndroidNativeDvDiagnosticRead<String>(
          remainingBudget: Duration.zero,
          startNativeRead: () async {
            starts++;
            return 'too late';
          },
        ),
        throwsA(isA<AndroidNativeDvDiagnosticSamplingDeadline>()),
      );
      expect(starts, 0);

      final pending = Completer<String>();
      final read = admitAndroidNativeDvDiagnosticRead<String>(
        remainingBudget: const Duration(milliseconds: 20),
        startNativeRead: () {
          starts++;
          return pending.future;
        },
      );
      await expectLater(read.bounded, throwsA(isA<TimeoutException>()));
      expect(starts, 1);
      pending.complete('late result remains observable to its owner');
      expect(
          await read.operation, 'late result remains observable to its owner');
      expect(starts, 1);
    });

    test('initial idle stop refuses same-URI foreign entry queued at admission',
        () async {
      final lock = Lock();
      final player = Object();
      var current = HdrOptionSourceIdentity(
        player: player,
        path: '',
        playlistEntryId: '',
        fileLoadedEpoch: 0,
      );
      final initial = current;
      final foreignEntered = Completer<void>();
      final releaseForeign = Completer<void>();
      final foreign = lock.synchronized(() async {
        current = HdrOptionSourceIdentity(
          player: player,
          path: androidNativeDvReleaseDiagnosticSource,
          playlistEntryId: '88',
          fileLoadedEpoch: 1,
        );
        foreignEntered.complete();
        await releaseForeign.future;
      });
      await foreignEntered.future;
      var stops = 0;
      final capture = captureAndroidNativeDvDiagnosticInitialBoundary(
        lock: lock,
        expectedIdle: initial,
        stop: () async {
          stops++;
          current = initial;
        },
        readIdentity: () async => current,
      );
      releaseForeign.complete();
      await foreign;
      await expectLater(capture, throwsStateError);
      expect(stops, 0);
      expect(current.playlistEntryId, '88');
    });

    test('option restore holds Player admission lock through final setter',
        () async {
      final lock = Lock();
      final player = Object();
      HdrOptionSourceIdentity identity(String path, String entry, int epoch) =>
          HdrOptionSourceIdentity(
            player: player,
            path: path,
            playlistEntryId: entry,
            fileLoadedEpoch: epoch,
          );
      var source = identity('', '', 0);
      final values = <String, String>{
        HdrNativeDvOptionOwner.vdOption: '',
        HdrNativeDvOptionOwner.renderOption: 'boolean',
      };
      final restoreReadEntered = Completer<void>();
      final releaseRestoreRead = Completer<void>();
      var restoring = false;
      var delayRestoreRead = true;
      final writes = <String>[];
      final owner = HdrNativeDvOptionOwner(
        readProperty: (name) async {
          if (restoring &&
              delayRestoreRead &&
              name == HdrNativeDvOptionOwner.renderOption) {
            delayRestoreRead = false;
            restoreReadEntered.complete();
            await releaseRestoreRead.future;
          }
          return values[name]!;
        },
        setPropertyStrict: (name, value) async {
          writes.add('$name=$value');
          values[name] = value;
        },
        readIdentity: () async => source,
      );
      final idle = source;
      await lock.synchronized(() => owner.begin(
            stoppedIdentity: idle,
            vd: 'native_dv=1',
            renderMode: 'timed',
          ));
      final loaded = identity('/fixed/p5.mp4', '7', 1);
      source = loaded;
      await lock.synchronized(() => owner.rebind(idle, loaded));
      restoring = true;

      final restore = restoreAndroidNativeDvDiagnosticOptionsUnderLock(
        lock: lock,
        options: owner,
      );
      await restoreReadEntered.future;
      var foreignOpenRan = false;
      final foreign = lock.synchronized(() async {
        foreignOpenRan = true;
        source = identity('/foreign.mp4', '8', 2);
      });
      await Future<void>.delayed(Duration.zero);
      expect(foreignOpenRan, isFalse);
      releaseRestoreRead.complete();
      await restore;
      await foreign;

      expect(
          writes, contains('${HdrNativeDvOptionOwner.renderOption}=boolean'));
      expect(writes, contains('${HdrNativeDvOptionOwner.vdOption}='));
      expect(owner.active, isFalse);
      expect(source.playlistEntryId, '8');
    });

    test('page disposal before output binding prevents late helper creation',
        () async {
      final admission = AndroidNativeDvDiagnosticPageAdmission<String>();
      final output = Completer<String>();
      var createCalls = 0;
      final started = admission.createAfterReady<int>(
        output: output.future,
        waitUntilReady: (_) async {},
        pageIsAlive: () => true,
        create: (_) => ++createCalls,
      );
      admission.close();
      output.complete('controller');
      expect(await started, isNull);
      expect(createCalls, 0);
    });

    test('page disposal during initial Surface binding prevents late creation',
        () async {
      final admission = AndroidNativeDvDiagnosticPageAdmission<String>();
      final binding = Completer<void>();
      final ready = Completer<void>();
      var createCalls = 0;
      final started = admission.createAfterReady<int>(
        output: Future<String>.value('controller'),
        waitUntilReady: (_) {
          binding.complete();
          return ready.future;
        },
        pageIsAlive: () => true,
        create: (_) => ++createCalls,
      );
      await binding.future;
      admission.close();
      ready.complete();
      expect(await started, isNull);
      expect(createCalls, 0);
    });

    test('delayed initial report cannot publish resources after shutdown',
        () async {
      final report = Completer<void>();
      var closing = false;
      var publishes = 0;
      final publishing = publishAndroidNativeDvDiagnosticResourcesAfterReport(
        initialReport: report.future,
        canPublish: () => !closing,
        publish: () => publishes++,
      );
      closing = true;
      report.complete();
      expect(await publishing, isFalse);
      expect(publishes, 0);
    });

    test('failed terminal sample is never hot-retried', () async {
      var propertyReads = 0;
      var reportWrites = 0;
      var sampleFailed = false;
      Future<void> sample() async {
        propertyReads++;
        try {
          throw StateError('owned terminal identity unavailable');
        } catch (_) {
          sampleFailed = true;
          reportWrites++;
        }
      }

      await sample();
      if (androidNativeDvDiagnosticShouldRetryTerminalSample(
        terminalObserved: true,
        terminalRowWritten: false,
        sampleFailed: sampleFailed,
        closed: false,
      )) {
        await sample();
      }
      expect(propertyReads, 1);
      expect(reportWrites, 1);
    });

    test('shutdown waits for startup side effects to settle', () async {
      final start = Completer<void>();
      var cleanupStarted = false;
      final shutdown = () async {
        await awaitAndroidNativeDvDiagnosticStartSettled(start.future);
        cleanupStarted = true;
      }();

      await Future<void>.delayed(Duration.zero);
      expect(cleanupStarted, isFalse);
      start.complete();
      await shutdown;
      expect(cleanupStarted, isTrue);
    });

    test('shutdown still cleans up after startup fails', () async {
      final start = Completer<void>();
      var cleanupStarted = false;
      final shutdown = () async {
        await awaitAndroidNativeDvDiagnosticStartSettled(start.future);
        cleanupStarted = true;
      }();

      start.completeError(StateError('startup failed after partial begin'));
      await shutdown;
      expect(cleanupStarted, isTrue);
    });

    test('row store never grows beyond its configured hard limit', () {
      final rows = AndroidNativeDvDiagnosticRows<int>(limit: 3);
      for (var value = 0; value < 8; value++) {
        rows.add(value);
      }
      expect(rows.length, 3);
      expect(rows.values, <int>[0, 1, 2]);
      expect(
        () => AndroidNativeDvDiagnosticRows<int>(limit: 301),
        throwsRangeError,
      );
    });

    test('atomic JSON writer emits serializable lists and replaces prior run',
        () async {
      final directory = await Directory.systemTemp.createTemp(
        'native-dv-release-report-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final output = File('${directory.path}/report.json');
      await writeAndroidNativeDvDiagnosticJsonAtomically(
          output, <String, Object?>{
        'rows': <Map<String, Object?>>[
          <String, Object?>{'eos': false},
        ],
        'runId': 'first',
      });
      await writeAndroidNativeDvDiagnosticJsonAtomically(
          output, <String, Object?>{
        'rows': <Map<String, Object?>>[
          <String, Object?>{'eos': true},
        ],
        'runId': 'second',
      });

      final report =
          jsonDecode(await output.readAsString()) as Map<String, dynamic>;
      expect(report['runId'], 'second');
      expect((report['rows'] as List).single['eos'], isTrue);
      expect(await File('${output.path}.tmp').exists(), isFalse);
    });

    test('Surface reuse with changed generation is a different owner', () {
      const first = AndroidSurfaceAccountId(
        handle: 4,
        generation: 11,
        viewId: 2,
        surfaceGeneration: 8,
        wid: 100,
      );
      const reusedAddress = AndroidSurfaceAccountId(
        handle: 4,
        generation: 12,
        viewId: 2,
        surfaceGeneration: 9,
        wid: 100,
      );
      final controller = Object();
      expect(
        HdrNativeDvOutputSnapshot(controller, first).matches(
          HdrNativeDvOutputSnapshot(controller, reusedAddress),
        ),
        isFalse,
      );
    });

    test('EOS path clearing remains bound to the same player, entry and epoch',
        () {
      final player = Object();
      final expected = HdrOptionSourceIdentity(
        player: player,
        path: '/fixed/p5.mp4',
        playlistEntryId: '7',
        fileLoadedEpoch: 4,
      );
      final clearedPath = HdrOptionSourceIdentity(
        player: player,
        path: '',
        playlistEntryId: '7',
        fileLoadedEpoch: 4,
      );
      expect(
        androidNativeDvDiagnosticOwnsTerminalIdentity(expected, clearedPath),
        isTrue,
      );
      expect(
        androidNativeDvDiagnosticOwnsTerminalIdentity(
          expected,
          HdrOptionSourceIdentity(
            player: player,
            path: '',
            playlistEntryId: '',
            fileLoadedEpoch: 4,
          ),
        ),
        isFalse,
      );
      expect(
        androidNativeDvDiagnosticOwnsTerminalIdentity(
          expected,
          HdrOptionSourceIdentity(
            player: player,
            path: '',
            playlistEntryId: '7',
            fileLoadedEpoch: 5,
          ),
        ),
        isFalse,
      );
    });
  });
}
