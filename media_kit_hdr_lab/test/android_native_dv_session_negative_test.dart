// ignore_for_file: implementation_imports, depend_on_referenced_packages
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:media_kit_video/src/hdr/hdr_disposal.dart';
import 'package:media_kit_video/src/hdr/hdr_open_coordinator.dart';
import 'package:media_kit_video/src/hdr/hdr_native_dv_option_owner.dart';
import 'package:media_kit_hdr_lab/common/android_native_dv_session_negative.dart';
import 'package:synchronized/synchronized.dart';

void main() {
  test('denial precedes publish and never readmits denied controller', () {
    final gate = AndroidNativeDvN1MountAdmission<Object>();
    final native = Object();
    final fallback = Object();
    expect(() => gate.observe(native, native: true), throwsStateError);
    gate.arm();
    expect(gate.observe(native, native: true), false);
    expect(gate.observe(native, native: true), false);
    expect(gate.observe(null, native: false), false);
    expect(gate.observe(fallback, native: false), true);
    expect(gate.mayMount(fallback), true);
    expect(gate.observe(native, native: true), false);
    expect(gate.mayMount(native), false);
  });
  test('failed retirement and replacement native are never admitted', () {
    for (final secondNative in [false, true]) {
      final gate = AndroidNativeDvN1MountAdmission<Object>()..arm();
      gate.observe(Object(), native: true);
      if (secondNative) gate.observe(null, native: false);
      expect(gate.observe(Object(), native: secondNative), false);
      expect(gate.invalid, true);
    }
  });
  test('first non-native controller is rejected as invalid trigger', () {
    final gate = AndroidNativeDvN1MountAdmission<Object>()..arm();
    expect(gate.observe(Object(), native: false), false);
    expect(gate.invalid, true);
  });
  test('N1 admits exactly one page open after denial is armed', () {
    final run = newRun();
    expect(run.admitOpen, throwsStateError);
    run.mount.arm();
    run.admitOpen();
    expect(run.openRequests, 1);
    expect(run.admitOpen, throwsStateError);
  });
  test('scalar ledger snapshots are immutable and overflow fails evidence', () {
    final run = AndroidNativeDvN1Run(externalIdentityLabel: 'unit', maxRows: 1);
    final exclusions = {'native': 'nativeDvUnavailable'};
    run.record('test', {'excluded': exclusions});
    exclusions.clear();
    expect(
        (run.rows.single['excluded'] as Map)['native'], 'nativeDvUnavailable');
    expect(() => (run.rows.single['excluded'] as Map)['x'] = 'y',
        throwsUnsupportedError);
    run.record('extra', {});
    expect(run.rows.length, 1);
    expect(run.overflow, true);
    expect(run.evidenceComplete, false);
  });
  test('raw error and stack identity retained separately from bounded text',
      () {
    final run = AndroidNativeDvN1Run(externalIdentityLabel: 'unit', maxText: 8);
    final error = StateError('a long original failure');
    final stack = StackTrace.current;
    run.record('failed', {}, error: error, stack: stack);
    expect(identical(run.rawErrors.single.$1, error), true);
    expect(identical(run.rawErrors.single.$2, stack), true);
    expect(run.evidenceComplete, false);
    expect((run.rows.single['error'] as String).length, 8);
  });
  test('unsafe error text cannot throw from scalar recorder', () {
    final run = newRun();
    run.record('failed', {}, error: _ThrowText());
    expect(run.evidenceComplete, false);
    expect(run.rawErrors.single.$1, isA<_ThrowText>());
  });
  test('coordinator order and its clock are independently checked', () {
    final run = newRun();
    call(run, sequence: 1, time: 10);
    call(run, sequence: 3, time: 9);
    expect(run.evidenceComplete, false);
    expect(run.toJson()['evidenceGaps'], contains('coordinator-sequence-gap'));
    expect(
        run.toJson()['evidenceGaps'], contains('coordinator-clock-regressed'));
  });
  test('transaction uses opaque identity rather than equality/hash code', () {
    final run = newRun();
    for (final token in [_SameToken(), _SameToken()]) {
      run.onNativeOption(HdrNativeDvOptionDiagnostic(
          transaction: token,
          sourcePath: '',
          sourcePlaylistEntryId: '',
          sourceFileLoadedEpoch: 0,
          purpose: HdrNativeDvOptionDiagnosticPurpose.originals,
          name: 'vd-lavc-o',
          original: ''));
    }
    expect(run.rows.map((r) => r['transaction']).toList(), [1, 2]);
  });
  test('complete synthetic trace verifies ledger contract without device claim',
      () {
    final run = completeTrace();
    expect(run.audit()['configurationEvidenceComplete'], true);
    expect(run.audit()['presentationVerified'], false);
  });
  test('restoration after fallback preparation cannot pass ordering', () {
    final run = completeTrace(restoreLate: true);
    expect(run.audit()['configurationEvidenceComplete'], false);
    expect(run.audit()['failures'],
        contains('both-restored-values-before-fallback'));
  });
  test('wrong typed event generation cannot pass correlation', () {
    final run = completeTrace(appliedGeneration: 2);
    expect(run.audit()['configurationEvidenceComplete'], false);
    expect(run.audit()['failures'],
        contains('same-session-generation-typed-degradation-applied'));
  });
  test('unverified or mismatched RouteApplied cannot pass target proof', () {
    for (final run in [
      completeTrace(verified: false),
      completeTrace(targetMismatch: true)
    ]) {
      expect(run.audit()['configurationEvidenceComplete'], false);
    }
  });
  test('missing awaited returns cannot be replaced by RouteApplied', () {
    final run = completeTrace(missingReturned: true);
    expect(run.audit()['configurationEvidenceComplete'], false);
    expect(run.audit()['failures'],
        contains('actual-successful-fallback-attempt-matches-applied-target'));
  });
  test('successful different backend route cannot satisfy typed target proof',
      () {
    final run = completeTrace(backendMismatch: true);
    expect(run.audit()['configurationEvidenceComplete'], false);
    expect(run.audit()['failures'],
        contains('actual-successful-fallback-attempt-matches-applied-target'));
  });
  test('unrelated reset owner cannot satisfy same-token rollback proof', () {
    final run = completeTrace(wrongResetOwner: true);
    expect(run.audit()['configurationEvidenceComplete'], false);
    expect(run.audit()['failures'],
        contains('owned-rollback-restoration-reset-returned-before-fallback'));
  });
  test('native configure/open entry cannot masquerade as prepare-only failure',
      () {
    final run = completeTrace();
    call(run, sequence: 11, method: HdrBackendDiagnosticMethod.configure);
    expect(run.audit()['configurationEvidenceComplete'], false);
    expect(
        run.audit()['failures'], contains('native-configure-open-not-entered'));
  });
  test(
      'cleanup proves actual baseline, retirement and Player termination separately',
      () async {
    final player = _Player();
    final writes = <Map<String, Object?>>[];
    final run = AndroidNativeDvN1Run(
        externalIdentityLabel: 'cleanup',
        writeOverride: (v) async {
          writes.add(v);
        });
    await run.prepare(player);
    player.epoch = 1;
    await run.captureCleanup(
        player: player, report: cleanReport, error: null, controller: null);
    expect(run.sessionClean, true);
    expect(run.playerTerminated, false);
    await run.recordTermination(null);
    await run.close();
    expect(run.closed, true);
    expect(run.debt, false);
    expect(writes.last['controllerRetired'], true);
    expect(writes.last['playerTerminated'], true);
    expect(writes.last['surfaceReleaseAcknowledgement'],
        'not independently observed');
  });
  test('retained output or mismatched restored option stays debt', () async {
    for (final retained in [false, true]) {
      final player = _Player();
      final run = newRun();
      await run.prepare(player);
      if (!retained) player.properties['vd-lavc-o'] = 'native_dv=1';
      await run.captureCleanup(
          player: player,
          report: cleanReport,
          error: null,
          controller: retained ? _Controller() : null);
      expect(run.sessionClean, false);
      expect(run.debt, true);
      await run.recordTermination(null);
      expect(run.debt, true);
      await run.close();
    }
  });
  test(
      'final snapshot write is awaited and failing write does not fulfill close',
      () async {
    final gate = Completer<void>();
    var writes = 0;
    final run = AndroidNativeDvN1Run(
        externalIdentityLabel: 'write',
        writeOverride: (_) {
          writes++;
          return gate.future;
        });
    var settled = false;
    final close = run.close().then((_) => settled = true);
    await Future<void>.delayed(Duration.zero);
    expect(settled, false);
    gate.complete();
    await close;
    expect(writes, 1);
    await run.close();
    expect(writes, 1);
    final error = StateError('disk');
    final failed = AndroidNativeDvN1Run(
        externalIdentityLabel: 'write',
        writeOverride: (_) async {
          throw error;
        });
    await expectLater(failed.close(), throwsA(same(error)));
    await expectLater(failed.close(), throwsA(same(error)));
  });
}

AndroidNativeDvN1Run newRun() => AndroidNativeDvN1Run(
    externalIdentityLabel: 'unit', writeOverride: (_) async {});
const cleanReport = HdrDisposalReport(
    coordinatorError: null,
    playerError: null,
    directoryError: null,
    retainedDirectory: null);

HdrRoute route(bool native, {bool mismatch = false}) => HdrRoute(
    strategy: native ? HdrStrategy.nativeDolbyVision : HdrStrategy.toneMapSdr,
    presentation: native
        ? HdrPresentation.nativeDolbyVision
        : HdrPresentation.toneMappedSdr,
    outputTransfer: HdrOutputTransfer.sdr,
    appliesDynamicMetadata: true,
    topology: native ? HdrTopology.platformView : HdrTopology.texture,
    vo: native ? 'mediacodec_embed' : 'gpu-next',
    hwdec: native
        ? 'mediacodec'
        : mismatch
            ? 'no'
            : 'mediacodec-copy',
    targetPrim: null,
    targetTrc: null,
    surfaceTransfer: null,
    stripDvRpu: false);
HdrOpenPlan plan(bool native, {bool mismatch = false}) {
  final r = route(native, mismatch: mismatch);
  final source = HdrSourceDescriptor.fromKind(HdrMediaKind.dolbyVisionP5);
  final candidate = HdrCandidate(
      strategy: r.strategy,
      maturity: HdrStrategyMaturity.experimental,
      feasible: true,
      route: r);
  return HdrOpenPlan(
      media: Media('/data/local/tmp/media-kit-lg-dv-p5-2160p.mp4'),
      source: source,
      sourceOrigin: HdrReportSource.hint,
      capabilities: const HdrCapabilities(
          sdkInt: 24,
          displayHdrTypes: {1, 2},
          hevcDecoders: [],
          dolbyVisionDecoders: [],
          p5PipelineAvailable: true,
          dataSpaceBridgeLoaded: false,
          dataSpaceExt: null),
      prediction: HdrRoutePrediction(
          source: source,
          selected: candidate,
          candidates: [candidate],
          presentation: r.presentation,
          confidence: HdrPredictionConfidence.verified,
          playable: true),
      route: r,
      excluded:
          native ? {} : {'native-dv': HdrDegradeReason.nativeDvUnavailable});
}

void call(AndroidNativeDvN1Run run,
    {required int sequence,
    int time = 0,
    bool native = true,
    HdrBackendDiagnosticMethod method =
        HdrBackendDiagnosticMethod.prepareOutput,
    HdrBackendDiagnosticBoundary boundary =
        HdrBackendDiagnosticBoundary.entered,
    Object? error,
    bool mismatch = false,
    int? ownerOrdinal,
    HdrBackendDiagnosticPurpose purpose = HdrBackendDiagnosticPurpose.normal}) {
  run.onBackendCall(HdrBackendCallDiagnostic(
      sequence: sequence,
      elapsedMicros: time,
      coordinatorGeneration: 1,
      invocation: HdrBackendDiagnosticAttempt(
          1, native ? 1 : 2, plan(native, mismatch: mismatch)),
      owningAttempt: ownerOrdinal == null
          ? null
          : HdrBackendDiagnosticAttempt(1, ownerOrdinal, plan(true)),
      sessionGeneration: 1,
      owningSessionGeneration: ownerOrdinal == null ? null : 1,
      method: method,
      boundary: boundary,
      purpose: purpose,
      error: error,
      stack: error == null ? null : StackTrace.current));
}

AndroidNativeDvN1Run completeTrace(
    {bool restoreLate = false,
    int appliedGeneration = 1,
    bool verified = true,
    bool targetMismatch = false,
    bool missingReturned = false,
    bool backendMismatch = false,
    bool wrongResetOwner = false}) {
  final run = newRun();
  run.mount.arm();
  run.admitOpen();
  call(run, sequence: 1);
  run.observeController(_Controller());
  final token = Object();
  void option(String name, HdrNativeDvOptionDiagnosticPurpose purpose,
      String original, String observed) {
    run.onNativeOption(HdrNativeDvOptionDiagnostic(
        transaction: token,
        sourcePath: '',
        sourcePlaylistEntryId: '',
        sourceFileLoadedEpoch: 0,
        purpose: purpose,
        name: name,
        original: original,
        observed: observed,
        requested: observed));
  }

  option('vd-lavc-o', HdrNativeDvOptionDiagnosticPurpose.originals, '', '');
  option('mediacodec-embed-render-mode',
      HdrNativeDvOptionDiagnosticPurpose.originals, 'boolean', 'boolean');
  option(
      'vd-lavc-o', HdrNativeDvOptionDiagnosticPurpose.apply, '', 'native_dv=1');
  option('mediacodec-embed-render-mode',
      HdrNativeDvOptionDiagnosticPurpose.apply, 'boolean', 'timed');
  run.observeController(null);
  call(run,
      sequence: 2,
      time: 10000001,
      boundary: HdrBackendDiagnosticBoundary.failed,
      error: TimeoutException(
          'real wait fixture trace', const Duration(seconds: 10)));
  run.onEvent(HdrDegradedEvent(1,
      reason: HdrDegradeReason.nativeDvUnavailable,
      from: route(true),
      to: targetMismatch ? route(true) : route(false)));
  int sequence = 3;
  void reset(HdrBackendDiagnosticBoundary boundary) {
    final next = sequence++;
    call(run,
        sequence: next,
        time: 10000000 + next,
        native: false,
        method: HdrBackendDiagnosticMethod.resetOwnedConfiguration,
        boundary: boundary,
        ownerOrdinal: wrongResetOwner ? 99 : 1,
        purpose: HdrBackendDiagnosticPurpose.rollback);
  }

  void restore() {
    option('mediacodec-embed-render-mode',
        HdrNativeDvOptionDiagnosticPurpose.restore, 'boolean', 'boolean');
    option(
        'vd-lavc-o', HdrNativeDvOptionDiagnosticPurpose.restoreNoWrite, '', '');
  }

  void fallback(HdrBackendDiagnosticMethod method,
      HdrBackendDiagnosticBoundary boundary) {
    final next = sequence++;
    call(run,
        sequence: next,
        time: 10000000 + next,
        native: false,
        method: method,
        boundary: boundary,
        mismatch: backendMismatch);
  }

  reset(HdrBackendDiagnosticBoundary.entered);
  if (!restoreLate) restore();
  reset(HdrBackendDiagnosticBoundary.returned);
  fallback(HdrBackendDiagnosticMethod.prepareOutput,
      HdrBackendDiagnosticBoundary.entered);
  if (restoreLate) restore();
  run.observeController(_Controller());
  fallback(HdrBackendDiagnosticMethod.prepareOutput,
      HdrBackendDiagnosticBoundary.returned);
  fallback(HdrBackendDiagnosticMethod.configure,
      HdrBackendDiagnosticBoundary.entered);
  if (!missingReturned) {
    fallback(HdrBackendDiagnosticMethod.configure,
        HdrBackendDiagnosticBoundary.returned);
  }
  fallback(
      HdrBackendDiagnosticMethod.open, HdrBackendDiagnosticBoundary.entered);
  if (!missingReturned) {
    fallback(
        HdrBackendDiagnosticMethod.open, HdrBackendDiagnosticBoundary.returned);
  }
  run.onEvent(HdrRouteAppliedEvent(appliedGeneration,
      route: route(false),
      report: HdrOutputReport(
          generation: appliedGeneration,
          actual: route(false),
          verified: verified)));
  return run;
}

class _Controller implements VideoController {
  @override
  bool get nativeSurfaceActive => false;
  @override
  bool get nativeSurfaceCandidate => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Player implements Player {
  final properties = <String, String>{
    'path': '',
    'playlist/0/id': '',
    'vd-lavc-o': '',
    'mediacodec-embed-render-mode': 'boolean',
    'hwdec': 'auto',
    'hwdec-current': 'no',
    'vo': 'null'
  };
  int epoch = 0;
  @override
  int get fileLoadedEpoch => epoch;
  @override
  final lock = Lock();
  @override
  PlayerState get state => const PlayerState();
  @override
  Future<String> getProperty(String name,
          {bool waitForInitialization = true}) async =>
      properties[name]!;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SameToken {
  @override
  bool operator ==(Object other) => other is _SameToken;
  @override
  int get hashCode => 1;
}

class _ThrowText {
  @override
  String toString() => throw StateError('text');
}
