import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/src/hdr/hdr_capabilities.dart';
import 'package:media_kit_video/src/hdr/hdr_native_dv_option_owner.dart';
import 'package:media_kit_video/src/hdr/hdr_open_coordinator.dart';
import 'package:media_kit_video/src/hdr/hdr_open_plan.dart';
import 'package:media_kit_video/src/hdr/hdr_route.dart';
import 'package:media_kit_video/src/hdr/hdr_route_planner.dart';
import 'package:media_kit_video/src/hdr/hdr_source_descriptor.dart';
import 'package:media_kit_video/src/hdr/hdr_strategy.dart';
import 'package:media_kit_video/src/hdr/hdr_session_native_dv_policy.dart';
import 'package:media_kit_video/src/hdr/hdr_video_session.dart';
import 'package:synchronized/synchronized.dart';

import 'hdr_open_coordinator_test.dart' as old;
import 'hdr_video_session_test.dart' as session_fixture;

typedef Call = HdrBackendCallDiagnostic<old.FakePlan>;

class ScriptBackend extends old.FakeBackend {
  Object? prepareError;
  Object? configureError;
  Object? cleanupError;
  final errorStack = StackTrace.fromString('original native stack');
  int resetCount = 0;
  bool syncPrepare = false;

  @override
  Future<void> prepareOutput(old.FakePlan plan) {
    if (prepareError != null && plan.path == 'native') {
      calls.add('prepare:${plan.path}');
      if (syncPrepare) Error.throwWithStackTrace(prepareError!, errorStack);
      return Future.error(prepareError!, errorStack);
    }
    return super.prepareOutput(plan);
  }

  @override
  Future<void> configure(old.FakePlan plan) {
    if (configureError != null) {
      calls.add('configure:${plan.path}');
      return Future.error(configureError!, errorStack);
    }
    return super.configure(plan);
  }

  @override
  Future<void> resetOwnedConfiguration() {
    resetCount++;
    if (resetCount >= 2 && cleanupError != null) {
      calls.add('reset');
      return Future.error(cleanupError!, errorStack);
    }
    return super.resetOwnedConfiguration();
  }
}

HdrOpenCoordinator<String, old.FakePlan> coordinator(ScriptBackend backend,
        {void Function(Call)? observer,
        HdrOpenRetry<old.FakePlan>? retry,
        HdrOpenReview<old.FakePlan>? review,
        Duration timeout = const Duration(seconds: 10),
        HdrOpenPreparer<String, old.FakePlan>? preparer}) =>
    HdrOpenCoordinator(backend,
        preparer: preparer ?? (source, _) async => old.FakePlan(source),
        onBackendCallDiagnostic: observer,
        diagnosticSessionGeneration: (_) => 91,
        retry: retry,
        maxRetries: 1,
        review: review,
        outputTimeout: timeout);

List<Call> entries(List<Call> rows, HdrBackendDiagnosticMethod method) => rows
    .where((r) =>
        r.method == method &&
        r.boundary == HdrBackendDiagnosticBoundary.entered)
    .toList();

class OptionFixture {
  OptionFixture({this.observer, String mode = 'boolean'}) {
    values[HdrNativeDvOptionOwner.renderOption] = mode;
    owner = HdrNativeDvOptionOwner(
      onDiagnostic: observer,
      readProperty: (name) async {
        reads.add('property:$name');
        return values[name]!;
      },
      readIdentity: () async {
        reads.add('identity');
        return source;
      },
      setPropertyStrict: (name, value) async {
        writes.add('$name=$value');
        await onWrite?.call(name, value);
        values[name] = mismatchOption == name ? 'mismatched' : value;
      },
    );
  }
  final void Function(HdrNativeDvOptionDiagnostic)? observer;
  final player = Object();
  late HdrOptionSourceIdentity source = identity();
  final reads = <String>[];
  final writes = <String>[];
  final values = <String, String>{
    HdrNativeDvOptionOwner.vdOption: '',
    HdrNativeDvOptionOwner.renderOption: 'boolean',
  };
  Future<void> Function(String, String)? onWrite;
  String? mismatchOption;
  late final HdrNativeDvOptionOwner owner;
  HdrOptionSourceIdentity identity({String path = '', int epoch = 0}) =>
      HdrOptionSourceIdentity(
          player: player,
          path: path,
          playlistEntryId: path.isEmpty ? '' : '7',
          fileLoadedEpoch: epoch);
  Future<void> begin() => owner.begin(
      stoppedIdentity: source, vd: 'native_dv=1', renderMode: 'timed');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final scenario in ['success', 'prepare', 'configure', 'cleanup']) {
    test('observer null/enabled/throwing preserves $scenario trace and error',
        () async {
      final primary = StateError('primary');
      final cleanup = StateError('cleanup');
      final traces = <List<String>>[];
      for (var mode = 0; mode < 3; mode++) {
        final backend = ScriptBackend()
          ..prepareError = scenario == 'prepare' ? primary : null
          ..configureError =
              scenario == 'configure' || scenario == 'cleanup' ? primary : null
          ..cleanupError = scenario == 'cleanup' ? cleanup : null;
        final rows = <Call>[];
        final c = coordinator(backend,
            observer: mode == 0
                ? null
                : (row) {
                    rows.add(row);
                    if (mode == 2) throw StateError('observer only');
                  });
        if (scenario == 'success') {
          expect((await c.openSource('native')).plan.path, 'native');
        } else {
          try {
            await c.openSource('native');
            fail('expected original failure');
          } catch (error, stack) {
            expect(identical(error, primary), isTrue);
            expect(stack.toString(), backend.errorStack.toString());
          }
          if (mode != 0) {
            expect(
                rows.where((r) => identical(r.error, primary)), hasLength(1));
            if (scenario == 'cleanup') {
              expect(
                  rows.where((r) => identical(r.error, cleanup)), hasLength(1));
            }
          }
        }
        backend.cleanupError = null;
        await c.dispose();
        traces.add(List.of(backend.calls));
        if (mode != 0) {
          expect(rows.map((r) => r.sequence),
              List.generate(rows.length, (index) => index + 1));
          final times = rows.map((r) => r.elapsedMicros).toList();
          expect(times, orderedEquals(List<int>.of(times)..sort()));
        }
      }
      expect(traces[1], traces[0]);
      expect(traces[2], traces[0]);
    });
  }

  for (final syncThrow in [true, false]) {
    test('prepare raw timeout counted once; syncThrow=$syncThrow', () async {
      final failure = TimeoutException('real backend await failed');
      final backend = ScriptBackend()
        ..prepareError = failure
        ..syncPrepare = syncThrow;
      final rows = <Call>[];
      final c = coordinator(backend, observer: rows.add);
      await expectLater(c.openSource('native'), throwsA(same(failure)));
      expect(entries(rows, HdrBackendDiagnosticMethod.prepareOutput),
          hasLength(1));
      expect(entries(rows, HdrBackendDiagnosticMethod.configure), isEmpty);
      expect(entries(rows, HdrBackendDiagnosticMethod.open), isEmpty);
      final failed = rows.singleWhere((r) => identical(r.error, failure));
      expect(failed.boundary, HdrBackendDiagnosticBoundary.failed);
      expect(failed.stack.toString(), backend.errorStack.toString());
      expect(failed.owningAttempt!.plan.path, 'native');
      await c.dispose();
    });
  }

  test('retry reset keeps old owner distinct from fallback invocation',
      () async {
    final backend = ScriptBackend()..prepareError = TimeoutException('bind');
    final rows = <Call>[];
    final c = coordinator(backend,
        observer: rows.add, retry: (_, __) async => old.FakePlan('fallback'));
    expect((await c.openSource('native')).plan.path, 'fallback');
    final reset = rows.firstWhere((r) =>
        r.purpose == HdrBackendDiagnosticPurpose.rollback &&
        r.method == HdrBackendDiagnosticMethod.resetOwnedConfiguration &&
        r.boundary == HdrBackendDiagnosticBoundary.returned);
    expect(reset.invocation!.plan.path, 'fallback');
    expect(reset.invocation!.ordinal, 2);
    expect(reset.owningAttempt!.plan.path, 'native');
    expect(reset.owningAttempt!.ordinal, 1);
    expect(reset.sessionGeneration, 91);
    expect(reset.owningSessionGeneration, 91);
    final fallback =
        entries(rows, HdrBackendDiagnosticMethod.prepareOutput).last;
    expect(fallback.sequence, greaterThan(reset.sequence));
    expect(fallback.owningAttempt, same(fallback.invocation));
    expect(entries(rows, HdrBackendDiagnosticMethod.configure), hasLength(1));
    expect(entries(rows, HdrBackendDiagnosticMethod.open), hasLength(1));
    await c.dispose();
  });

  test('review reopen increments ordinal; report replacement is not owner',
      () async {
    final backend = ScriptBackend();
    final rows = <Call>[];
    var reviews = 0;
    final c = coordinator(backend, observer: rows.add, review: (_, __) async {
      reviews++;
      return reviews == 1
          ? HdrReviewDecision.reopen(Duration.zero, old.FakePlan('reopened'))
          : HdrReviewDecision.accept(nextPlan: old.FakePlan('report-only'));
    });
    expect((await c.openSource('native')).plan.path, 'report-only');
    expect(
        entries(rows, HdrBackendDiagnosticMethod.open)
            .map((r) => r.invocation!.ordinal),
        [1, 2]);
    await c.dispose();
    final disposed = rows.last;
    expect(disposed.purpose, HdrBackendDiagnosticPurpose.disposal);
    expect(disposed.coordinatorGeneration, 2);
    expect(disposed.invocation, isNull);
    expect(disposed.sessionGeneration, isNull);
    expect(disposed.owningSessionGeneration, 91);
    expect(disposed.owningAttempt!.plan.path, 'reopened');
  });

  test('failed disposal retry retains old owning attempt across generations',
      () async {
    final backend = ScriptBackend();
    final rows = <Call>[];
    final c = coordinator(backend, observer: rows.add);
    await c.openSource('native');
    final failure = StateError('restore failed');
    backend.cleanupError = failure;
    await expectLater(c.dispose(), throwsA(same(failure)));
    backend.cleanupError = null;
    await c.dispose();
    final disposals =
        entries(rows, HdrBackendDiagnosticMethod.resetOwnedConfiguration)
            .where((r) => r.purpose == HdrBackendDiagnosticPurpose.disposal)
            .toList();
    expect(disposals.map((r) => r.coordinatorGeneration), [2, 3]);
    expect(disposals.map((r) => r.owningAttempt!.ordinal), [1, 1]);
    expect(
        disposals.map((r) => r.owningAttempt!.coordinatorGeneration), [1, 1]);
  });

  test('newer preparation failure does not relabel superseded owner cleanup',
      () async {
    final backend = ScriptBackend()..heldConfigure = Completer<void>();
    final rows = <Call>[];
    final c =
        coordinator(backend, observer: rows.add, preparer: (source, _) async {
      if (source == 'new') throw StateError('new preparation failed');
      return old.FakePlan(source);
    });
    final previous = c.openSource('native');
    while (!backend.calls.contains('configure:native')) {
      await Future<void>.delayed(Duration.zero);
    }
    await expectLater(c.openSource('new'), throwsStateError);
    backend.heldConfigure!.complete();
    await expectLater(previous, throwsA(isA<OpenSuperseded>()));
    final rollback =
        rows.where((r) => r.purpose == HdrBackendDiagnosticPurpose.rollback);
    expect(rollback, isNotEmpty);
    expect(
        rollback.every((r) =>
            r.coordinatorGeneration == 1 &&
            r.owningAttempt!.coordinatorGeneration == 1 &&
            r.owningAttempt!.plan.path == 'native'),
        isTrue);
    expect(entries(rows, HdrBackendDiagnosticMethod.configure), hasLength(1));
    await c.dispose();
  });

  test('outer output timeout is not underlying future completion/cancellation',
      () async {
    final backend = ScriptBackend()..heldOutput = Completer<void>();
    final rows = <Call>[];
    final c = coordinator(backend,
        observer: rows.add, timeout: const Duration(milliseconds: 1));
    await expectLater(c.openSource('native'), throwsA(isA<TimeoutException>()));
    final failed = rows.singleWhere((r) => r.error is TimeoutException);
    expect(failed.method, HdrBackendDiagnosticMethod.waitForOutput);
    expect(failed.boundaryScope, 'coordinator-awaited-operation');
    expect(backend.heldOutput!.isCompleted, isFalse);
    backend.heldOutput!.complete();
    await pumpEventQueue();
    expect(
        rows.where((r) =>
            r.method == HdrBackendDiagnosticMethod.waitForOutput &&
            r.boundary == HdrBackendDiagnosticBoundary.returned),
        isEmpty);
    await c.dispose();
  });

  test('throwing Session correlation projection cannot change backend outcome',
      () async {
    final backend = ScriptBackend();
    final c = HdrOpenCoordinator<String, old.FakePlan>(backend,
        preparer: (source, _) async => old.FakePlan(source),
        onBackendCallDiagnostic: (_) => fail('projection must fail first'),
        diagnosticSessionGeneration: (_) => throw StateError('projection'));
    expect((await c.openSource('native')).plan.path, 'native');
    await c.dispose();
  });

  for (final mode in ['boolean', 'timed']) {
    test('owner $mode originals/apply/restore read-write trace parity',
        () async {
      final traces = <List<String>>[];
      for (var observerMode = 0; observerMode < 3; observerMode++) {
        final rows = <HdrNativeDvOptionDiagnostic>[];
        final f = OptionFixture(
            mode: mode,
            observer: observerMode == 0
                ? null
                : (r) {
                    rows.add(r);
                    if (observerMode == 2) throw StateError('callback');
                  });
        f.onWrite = (_, __) async {
          // Both actual originals have already been emitted before first write.
          if (observerMode != 0 && f.writes.length == 1) {
            expect(rows.map((r) => r.purpose), [
              HdrNativeDvOptionDiagnosticPurpose.originals,
              HdrNativeDvOptionDiagnosticPurpose.originals,
            ]);
          }
        };
        await f.begin();
        await f.owner.verify();
        await f.owner.restore();
        expect(f.values[HdrNativeDvOptionOwner.vdOption], '');
        expect(f.values[HdrNativeDvOptionOwner.renderOption], mode);
        expect(f.owner.active, isFalse);
        traces.add([...f.reads, 'WRITES', ...f.writes]);
        if (observerMode != 0) {
          expect(rows.map((r) => r.transaction).toSet(), hasLength(1));
          final restored = rows
              .where((r) =>
                  r.purpose == HdrNativeDvOptionDiagnosticPurpose.restore ||
                  r.purpose ==
                      HdrNativeDvOptionDiagnosticPurpose.restoreNoWrite)
              .toList();
          expect(restored.map((r) => r.name), [
            HdrNativeDvOptionOwner.renderOption,
            HdrNativeDvOptionOwner.vdOption,
          ]);
          expect(restored.map((r) => r.observed), [mode, '']);
          if (mode == 'timed') {
            expect(restored.first.purpose,
                HdrNativeDvOptionDiagnosticPurpose.restoreNoWrite);
          }
        }
      }
      expect(traces[1], traces[0]);
      expect(traces[2], traces[0]);
    });
  }

  test(
      'partial setter failure preserves original object/stack and no-write row',
      () async {
    final rows = <HdrNativeDvOptionDiagnostic>[];
    final f = OptionFixture(observer: (r) {
      rows.add(r);
      throw StateError('observer');
    });
    final original = StateError('setter failed');
    final stack = StackTrace.fromString('strict setter original stack');
    f.onWrite = (name, value) async {
      if (name == HdrNativeDvOptionOwner.renderOption && value == 'timed') {
        Error.throwWithStackTrace(original, stack);
      }
    };
    try {
      await f.begin();
      fail('expected setter failure');
    } catch (error, caughtStack) {
      expect(error, same(original));
      expect(caughtStack.toString(), stack.toString());
    }
    final failure = rows.singleWhere(
        (r) => r.purpose == HdrNativeDvOptionDiagnosticPurpose.beginFailure);
    expect(failure.error, same(original));
    expect(failure.stack.toString(), stack.toString());
    expect(
        rows
            .where((r) =>
                r.purpose == HdrNativeDvOptionDiagnosticPurpose.restoreNoWrite)
            .single
            .observed,
        'boolean');
    expect(f.owner.active, isFalse);
  });

  test(
      'external value/change restore failure retains token through retry/rebind',
      () async {
    final rows = <HdrNativeDvOptionDiagnostic>[];
    final f = OptionFixture(observer: rows.add);
    await f.begin();
    final token = rows.first.transaction;
    final before = f.source;
    f.source = f.identity(path: 'test://owned', epoch: 1);
    await f.owner.rebind(before, f.source);
    f.values[HdrNativeDvOptionOwner.renderOption] = 'external';
    await expectLater(
        f.owner.restore(), throwsA(isA<HdrNativeDvOptionFailure>()));
    final failure = rows.singleWhere(
        (r) => r.purpose == HdrNativeDvOptionDiagnosticPurpose.restoreFailure);
    expect(failure.transaction, same(token));
    expect(failure.sourcePath, 'test://owned');
    expect(failure.sourcePlaylistEntryId, '7');
    expect(failure.sourceFileLoadedEpoch, 1);
    expect(f.owner.active, isTrue);
    f.values[HdrNativeDvOptionOwner.renderOption] = 'timed';
    await f.owner.restore();
    expect(rows.every((r) => identical(r.transaction, token)), isTrue);
    expect(f.owner.active, isFalse);
    f.source = f.identity(epoch: 1);
    await f.begin();
    expect(rows.last.transaction, isNot(same(token)));
    await f.owner.restore();
  });

  test(
      'external identity restore failure records old source and retries same token',
      () async {
    final rows = <HdrNativeDvOptionDiagnostic>[];
    final f = OptionFixture(observer: rows.add);
    await f.begin();
    final oldSource = f.source;
    final token = rows.first.transaction;
    f.source = f.identity(path: 'test://foreign', epoch: 1);
    await expectLater(
        f.owner.restore(), throwsA(isA<HdrNativeDvOptionFailure>()));
    expect(
        rows.where((r) =>
            r.purpose == HdrNativeDvOptionDiagnosticPurpose.restoreFailure),
        hasLength(2));
    expect(rows.last.sourcePath, '');
    expect(rows.last.transaction, same(token));
    f.source = oldSource;
    await f.owner.restore();
    expect(f.owner.active, isFalse);
  });

  test('Session forwards calls/correlation through real review decorator',
      () async {
    final backend = session_fixture.FakeBackend();
    final rows = <HdrBackendCallDiagnostic<HdrOpenPlan>>[];
    final session = HdrVideoSession.forTesting(
      backend: backend,
      isAndroid: true,
      capabilitiesProvider: () async => testCaps,
      onBackendCallDiagnostic: rows.add,
    );
    await session.open(Media('test://sdr'),
        hint: const HdrSourceDescriptor(
            transfer: 'bt.1886', primaries: 'bt.709', enhancementLayer: false));
    expect(
        rows
            .where((r) => r.invocation != null)
            .every((r) => r.sessionGeneration == 1),
        isTrue);
    expect(
        rows.where((r) =>
            r.method == HdrBackendDiagnosticMethod.open &&
            r.boundary == HdrBackendDiagnosticBoundary.entered),
        hasLength(1));
    await session.dispose();
    final disposal = rows.last;
    expect(disposal.invocation, isNull);
    expect(disposal.owningSessionGeneration, 1);
    expect(disposal.coordinatorGeneration, 2);
  });

  test('successful method entries match returns exactly, including disposal',
      () async {
    final rows = <Call>[];
    final backend = ScriptBackend();
    final c = coordinator(backend, observer: rows.add);
    await c.openSource('native');
    await c.dispose();
    final expected = [
      HdrBackendDiagnosticMethod.validate,
      HdrBackendDiagnosticMethod.stop,
      HdrBackendDiagnosticMethod.resetOwnedConfiguration,
      HdrBackendDiagnosticMethod.prepareOutput,
      HdrBackendDiagnosticMethod.configure,
      HdrBackendDiagnosticMethod.waitForOutput,
      HdrBackendDiagnosticMethod.open,
      HdrBackendDiagnosticMethod.reviewFacts,
      HdrBackendDiagnosticMethod.stop,
      HdrBackendDiagnosticMethod.resetOwnedConfiguration,
    ];
    expect(
        rows
            .where((r) => r.boundary == HdrBackendDiagnosticBoundary.entered)
            .map((r) => r.method),
        expected);
    expect(
        rows
            .where((r) => r.boundary == HdrBackendDiagnosticBoundary.returned)
            .map((r) => r.method),
        expected);
    expect(rows.where((r) => r.boundary == HdrBackendDiagnosticBoundary.failed),
        isEmpty);
  });

  test('pending old rollback is attributed separately from new request',
      () async {
    final backend = ScriptBackend()
      ..prepareError = StateError('first')
      ..cleanupError = StateError('cleanup retained');
    final rows = <Call>[];
    final c = coordinator(backend, observer: rows.add);
    await expectLater(
        c.openSource('native'), throwsA(same(backend.prepareError)));
    await expectLater(
        c.openSource('fallback'), throwsA(same(backend.cleanupError)));
    final second = rows.where((r) => r.coordinatorGeneration == 2);
    expect(second, isNotEmpty);
    expect(
        second.every((r) =>
            r.invocation!.plan.path == 'fallback' &&
            r.invocation!.coordinatorGeneration == 2 &&
            r.owningAttempt!.plan.path == 'native' &&
            r.owningAttempt!.coordinatorGeneration == 1),
        isTrue);
    backend.cleanupError = null;
    await c.openSource('fallback');
    await c.dispose();
  });

  test('Session decorator admission failure is not a concrete delegate entry',
      () async {
    final delegate = CountingSessionBackend();
    final error = StateError('Session admission rejected');
    final rows = <HdrBackendCallDiagnostic<HdrOpenPlan>>[];
    final plan = HdrOpenPlan(
        media: Media('test://sdr'),
        source: const HdrSourceDescriptor(),
        sourceOrigin: null,
        capabilities: testCaps,
        prediction: onlyNativePlanner(
            source: const HdrSourceDescriptor(),
            capabilities: testCaps,
            policy: HdrRoutingPolicy.defaults,
            preference: HdrOutputPreference.auto,
            excluded: const {}),
        route: nativeRoute);
    final decorated = HdrSessionReviewBackend(
        delegate: delegate,
        generationOf: (_) => 14,
        isCurrent: (_) => true,
        admit: (_) => throw error,
        publishWindow: (_) {});
    final c = HdrOpenCoordinator<String, HdrOpenPlan>(decorated,
        preparer: (_, __) async => plan, onBackendCallDiagnostic: rows.add);
    await expectLater(c.openSource('x'), throwsA(same(error)));
    expect(delegate.validations, 0);
    expect(delegate.calls, isEmpty);
    expect(rows.map((r) => r.method), [
      HdrBackendDiagnosticMethod.validate,
      HdrBackendDiagnosticMethod.validate
    ]);
    expect(rows.last.boundary, HdrBackendDiagnosticBoundary.failed);
    expect(rows.last.boundaryScope, 'coordinator-awaited-operation');
    await c.dispose();
  });

  test(
      'Session review decorator failure before delegate is attributed at boundary',
      () async {
    final delegate = CountingSessionBackend();
    final rows = <HdrBackendCallDiagnostic<HdrOpenPlan>>[];
    final plan = HdrOpenPlan(
        media: Media('test://p5'),
        source: const HdrSourceDescriptor(),
        sourceOrigin: null,
        capabilities: testCaps,
        prediction: onlyNativePlanner(
            source: const HdrSourceDescriptor(),
            capabilities: testCaps,
            policy: HdrRoutingPolicy.defaults,
            preference: HdrOutputPreference.auto,
            excluded: const {}),
        route: nativeRoute);
    var current = true;
    final decorated = HdrSessionReviewBackend(
        delegate: delegate,
        generationOf: (_) => 14,
        isCurrent: (_) => current,
        admit: (_) {},
        publishWindow: (_) {});
    delegate.onOpened = () => current = false;
    final c = HdrOpenCoordinator<String, HdrOpenPlan>(decorated,
        preparer: (_, __) async => plan, onBackendCallDiagnostic: rows.add);
    await expectLater(c.openSource('x'), throwsA(isA<OpenSuperseded>()));
    expect(delegate.reviews, 0);
    final failure = rows.singleWhere((r) =>
        r.method == HdrBackendDiagnosticMethod.reviewFacts &&
        r.boundary == HdrBackendDiagnosticBoundary.failed);
    expect(failure.error, isA<OpenSuperseded>());
    expect(failure.boundaryScope, 'coordinator-awaited-operation');
    await c.dispose();
  });

  test(
      'partial restore failure retries one pending option under the same token',
      () async {
    final traces = <List<String>>[];
    final failure = StateError('restore setter');
    for (var observerMode = 0; observerMode < 3; observerMode++) {
      final rows = <HdrNativeDvOptionDiagnostic>[];
      final f = OptionFixture(
          observer: observerMode == 0
              ? null
              : (r) {
                  rows.add(r);
                  if (observerMode == 2) throw StateError('callback');
                });
      await f.begin();
      f.onWrite = (name, value) async {
        if (name == HdrNativeDvOptionOwner.renderOption && value == 'boolean') {
          throw failure;
        }
      };
      try {
        await f.owner.restore();
        fail('expected restore failure');
      } on HdrNativeDvOptionFailure catch (error) {
        expect(error.restoreErrors[HdrNativeDvOptionOwner.renderOption],
            same(failure));
      }
      expect(f.owner.active, isTrue);
      expect(f.values[HdrNativeDvOptionOwner.vdOption], '');
      f.onWrite = null;
      await f.owner.restore();
      expect(f.owner.active, isFalse);
      traces.add([...f.reads, 'WRITES', ...f.writes]);
      if (observerMode != 0) {
        expect(rows.map((r) => r.transaction).toSet(), hasLength(1));
        expect(rows.where((r) => r.error != null).single.error, same(failure));
        expect(
            rows.where((r) =>
                r.name == HdrNativeDvOptionOwner.vdOption &&
                r.purpose == HdrNativeDvOptionDiagnosticPurpose.restore),
            hasLength(1));
        expect(
            rows.where((r) =>
                r.name == HdrNativeDvOptionOwner.renderOption &&
                r.purpose == HdrNativeDvOptionDiagnosticPurpose.restore),
            hasLength(1));
      }
    }
    expect(traces[1], traces[0]);
    expect(traces[2], traces[0]);
  });

  test('readback mismatch emits no successful apply and retains actual failure',
      () async {
    final traces = <List<String>>[];
    for (var observerMode = 0; observerMode < 3; observerMode++) {
      final rows = <HdrNativeDvOptionDiagnostic>[];
      final f = OptionFixture(
          observer: observerMode == 0
              ? null
              : (r) {
                  rows.add(r);
                  if (observerMode == 2) throw StateError('callback');
                })
        ..mismatchOption = HdrNativeDvOptionOwner.vdOption;
      try {
        await f.begin();
        fail('expected mismatch');
      } on HdrNativeDvOptionFailure catch (error) {
        expect(error.operationError, isA<StateError>());
        if (observerMode != 0) {
          final failure = rows.singleWhere((r) =>
              r.purpose == HdrNativeDvOptionDiagnosticPurpose.beginFailure);
          expect(failure.error, same(error.operationError));
          expect(
              rows.where(
                  (r) => r.purpose == HdrNativeDvOptionDiagnosticPurpose.apply),
              isEmpty);
          expect(
              rows.where((r) =>
                  r.purpose ==
                  HdrNativeDvOptionDiagnosticPurpose.restoreFailure),
              hasLength(1));
        }
      }
      f.mismatchOption = null;
      f.values[HdrNativeDvOptionOwner.vdOption] = 'native_dv=1';
      await f.owner.restore();
      traces.add([...f.reads, 'WRITES', ...f.writes]);
    }
    expect(traces[1], traces[0]);
    expect(traces[2], traces[0]);
  });

  test(
      'owner observer rejects injected backend instead of false owner coverage',
      () {
    expect(
        () => HdrVideoSession.forTesting(
            backend: session_fixture.FakeBackend(),
            isAndroid: true,
            onNativeDvOptionDiagnostic: (_) {}),
        throwsArgumentError);
  });

  test('non-Android diagnostics remain inert with no backend or Player',
      () async {
    final session = HdrVideoSession.forTesting(
        isAndroid: false,
        onBackendCallDiagnostic: (_) => fail('Android call'),
        onNativeDvOptionDiagnostic: (_) => fail('Android owner'));
    await session.dispose();
  });

  test(
      'default Session backend forwards actual option owner; no backend override',
      () async {
    final player = DiagnosticPlayer();
    final rows = <HdrNativeDvOptionDiagnostic>[];
    final calls = <HdrBackendCallDiagnostic<HdrOpenPlan>>[];
    final session = HdrVideoSession.forTesting(
        player: player,
        isAndroid: true,
        positionProvider: () => Duration.zero,
        capabilitiesProvider: () async => testCaps,
        routePlanner: onlyNativePlanner,
        onBackendCallDiagnostic: calls.add,
        onNativeDvOptionDiagnostic: rows.add);
    await expectLater(
        session.open(Media('test://p5'),
            hint: const HdrSourceDescriptor(
                codec: 'hevc',
                dynamicMetadata: HdrDynamicMetadata.dolbyVision,
                dvProfile: 5,
                dvCompatibilityId: 0,
                enhancementLayer: false)),
        throwsA(same(player.hwdecError)));
    expect(
        rows.where(
            (r) => r.purpose == HdrNativeDvOptionDiagnosticPurpose.apply),
        hasLength(2));
    expect(
        rows.where(
            (r) => r.purpose == HdrNativeDvOptionDiagnosticPurpose.restore),
        hasLength(2));
    expect(
        calls
            .where((r) =>
                r.method == HdrBackendDiagnosticMethod.prepareOutput &&
                r.boundary == HdrBackendDiagnosticBoundary.failed)
            .single
            .error,
        same(player.hwdecError));
    expect(
        session.controller.value, isNull); // Failure before real slot creation.
    expect(player.properties['vd-lavc-o'], '');
    expect(player.properties['mediacodec-embed-render-mode'], 'boolean');
    await session.dispose();
  });
}

const testCaps = HdrCapabilities(
    sdkInt: 24,
    displayHdrTypes: {1, 2},
    hevcDecoders: [],
    dolbyVisionDecoders: [],
    p5PipelineAvailable: true,
    dataSpaceBridgeLoaded: false,
    dataSpaceExt: null);
const nativeRoute = HdrRoute(
    strategy: HdrStrategy.nativeDolbyVision,
    presentation: HdrPresentation.nativeDolbyVision,
    outputTransfer: HdrOutputTransfer.dolbyVision,
    appliesDynamicMetadata: true,
    topology: HdrTopology.platformView,
    vo: 'mediacodec_embed',
    hwdec: 'mediacodec',
    vdLavcOptions: 'native_dv=1',
    mediacodecEmbedRenderMode: 'timed',
    targetPrim: null,
    targetTrc: null,
    surfaceTransfer: null,
    stripDvRpu: false);

HdrRoutePrediction onlyNativePlanner(
    {required HdrSourceDescriptor source,
    required HdrCapabilities capabilities,
    required HdrRoutingPolicy policy,
    required HdrOutputPreference preference,
    required Map<String, HdrDegradeReason> excluded}) {
  final playable = !excluded.containsKey(HdrRouteDependency.nativeDolbyVision);
  final candidate = HdrCandidate(
      strategy: HdrStrategy.nativeDolbyVision,
      maturity: HdrStrategyMaturity.unsupported,
      feasible: playable,
      route: playable ? nativeRoute : null);
  return HdrRoutePrediction(
      source: source,
      selected: candidate,
      candidates: [candidate],
      presentation: HdrPresentation.nativeDolbyVision,
      confidence: HdrPredictionConfidence.unverified,
      playable: playable);
}

/// Real Session/backend/owner, with a fake Player that fails before controller
/// creation. Proves callback plumbing, not native Surface or device behavior.
class DiagnosticPlayer implements Player {
  final properties = <String, String>{
    'path': '',
    'playlist-entry-id': '',
    'vd-lavc-o': '',
    'mediacodec-embed-render-mode': 'boolean'
  };
  final hwdecError = StateError('stop before controller creation');
  @override
  final lock = Lock();
  @override
  int get fileLoadedEpoch => 0;
  @override
  final stream = PlayerStream(
      Stream.empty(),
      Stream.empty(),
      Stream.empty(),
      Stream.empty(),
      Stream.empty(),
      Stream.empty(),
      Stream.empty(),
      Stream.empty(),
      Stream.empty(),
      Stream.empty(),
      Stream.empty(),
      Stream.empty(),
      Stream.empty(),
      Stream.empty(),
      Stream.empty(),
      Stream.empty(),
      Stream.empty(),
      Stream.empty(),
      Stream.empty(),
      Stream.empty(),
      Stream.empty(),
      Stream.empty(),
      Stream.empty(),
      Stream.empty(),
      Stream.empty(),
      Stream.empty());
  @override
  Future<void> stop(
      {bool open = false,
      bool notify = true,
      bool synchronized = true,
      bool waitForVideoControllerInitialization = true}) async {}
  @override
  Future<String> getProperty(String name,
      {bool waitForInitialization = true}) async {
    if (name == 'hwdec') throw hwdecError;
    return properties[name] ?? '';
  }

  @override
  Future<void> setPropertyStrict(String name, String value,
      {bool waitForInitialization = true}) async {
    properties[name] = value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class CountingSessionBackend extends session_fixture.FakeBackend {
  void Function()? onOpened;
  @override
  Future<void> open(HdrOpenPlan plan,
      {Duration? start, required bool play}) async {
    await super.open(plan, start: start, play: play);
    onOpened?.call();
  }

  int validations = 0;
  int reviews = 0;
  @override
  Future<void> validate(HdrOpenPlan plan) async {
    validations++;
  }

  @override
  Future<HdrReviewFacts> reviewFacts(HdrOpenPlan plan) {
    reviews++;
    return super.reviewFacts(plan);
  }
}
