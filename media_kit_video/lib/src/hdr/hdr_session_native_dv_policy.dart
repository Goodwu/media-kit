import 'dart:async';

import 'package:synchronized/synchronized.dart';

import 'android_mediacodec_configuration.dart';
import 'hdr_native_dv_option_owner.dart';
import 'hdr_native_dv_review_evidence.dart';
import 'hdr_open_coordinator.dart';
import 'hdr_open_plan.dart';
import 'hdr_route.dart';
import 'hdr_strategy.dart';

/// State of actual candidate admissions in one Session open generation.
/// Display-only planning never spends a slot. Native DV may run only once;
/// the two HDR slots include both native HDR and native Dolby Vision.
class HdrSessionAttemptPolicy {
  int hdrAttempts = 0;
  bool nativeDvAttempted = false;
  final Map<String, HdrDegradeReason> _excluded = {};

  static bool isHdr(HdrRoute route) =>
      route.presentation == HdrPresentation.nativeHdr ||
      route.presentation == HdrPresentation.nativeDolbyVision;

  void admit(HdrRoute route) {
    if ((route.strategy == HdrStrategy.nativeDolbyVision &&
            nativeDvAttempted) ||
        (isHdr(route) && hdrAttempts >= 2)) {
      throw const HdrSessionRouteBudgetFailure();
    }
    if (isHdr(route)) hdrAttempts++;
    if (route.strategy == HdrStrategy.nativeDolbyVision) {
      nativeDvAttempted = true;
    }
  }

  void excludeNativeDv() {
    _excluded[HdrRouteDependency.nativeDolbyVision] =
        HdrDegradeReason.nativeDvUnavailable;
  }

  Map<String, HdrDegradeReason> exclusions(
    Map<String, HdrDegradeReason> previous, {
    bool nextAttempt = false,
  }) =>
      <String, HdrDegradeReason>{
        ...previous,
        ..._excluded,
        if (nextAttempt && nativeDvAttempted)
          HdrRouteDependency.nativeDolbyVision:
              HdrDegradeReason.nativeDvUnavailable,
      };
}

class HdrSessionRouteBudgetFailure implements Exception {
  const HdrSessionRouteBudgetFailure();
}

/// Identity / option debt failures must never be converted to a route retry.
/// Retain the typed cause chain instead of guessing from exception strings.
bool nativeDvFailureMustAbort(Object error) {
  final seen = <Object>{};
  Object? current = error;
  while (current != null && seen.add(current)) {
    if (current is HdrNativeDvOptionFailure) return true;
    if (current is! HdrNativeDvReviewFailure) return false;
    if (current.kind == HdrNativeDvReviewFailureKind.ownership ||
        current.kind == HdrNativeDvReviewFailureKind.sourceIdentity ||
        current.kind == HdrNativeDvReviewFailureKind.fileLoaded) {
      return true;
    }
    current = current.cause;
  }
  return false;
}

/// A conservative *acceptance* window spanning producer and consumer.
/// Starts before delegate.reviewFacts. A timeout does not cancel the producer
/// Future or native FFI. Their late results cannot pass this window, and the
/// producer retains its own deadline/ownership checks. No ABA or presentation
/// continuity is inferred from equal source/output/configuration endpoints.
class HdrSessionReviewWindow {
  HdrSessionReviewWindow({
    required this.generation,
    required this.plan,
    this.budget = const Duration(seconds: 8),
    Duration Function()? monotonicNow,
  }) {
    _stopwatch.start();
    _now = monotonicNow ?? (() => _stopwatch.elapsed);
    _started = _now();
  }

  final int generation;
  final HdrOpenPlan plan;
  final Duration budget;
  final Stopwatch _stopwatch = Stopwatch();
  late final Duration Function() _now;
  late final Duration _started;
  HdrReviewFacts? _facts;

  Duration remaining() {
    final left = budget - (_now() - _started);
    if (left <= Duration.zero) {
      throw const HdrNativeDvReviewFailure(
          HdrNativeDvReviewFailureKind.timeout);
    }
    return left;
  }

  Future<T> bounded<T>(Future<T> Function() operation) async {
    final left = remaining();
    try {
      final value = await operation().timeout(left);
      remaining();
      return value;
    } on TimeoutException catch (error) {
      throw HdrNativeDvReviewFailure(HdrNativeDvReviewFailureKind.timeout,
          cause: error);
    }
  }

  bool matches(int serial, HdrOpenPlan expectedPlan, HdrReviewFacts facts) =>
      generation == serial &&
      identical(plan, expectedPlan) &&
      identical(_facts, facts);
}

/// Session-only wrapper: no backend option/ownership implementation changes.
/// Windows remain tied to the captured generation/plan/facts. A late old
/// producer cannot overwrite a successor's window.
class HdrSessionReviewBackend implements HdrOpenBackend<HdrOpenPlan> {
  HdrSessionReviewBackend({
    required this.delegate,
    required this.generationOf,
    required this.isCurrent,
    required this.admit,
    required this.publishWindow,
    this.monotonicNow,
    this.budget = const Duration(seconds: 8),
  });

  final HdrOpenBackend<HdrOpenPlan> delegate;
  final int Function(HdrOpenPlan) generationOf;
  final bool Function(int) isCurrent;
  final void Function(HdrOpenPlan) admit;
  final void Function(HdrSessionReviewWindow) publishWindow;
  final Duration Function()? monotonicNow;
  final Duration budget;

  @override
  Future<void> validate(HdrOpenPlan plan) async {
    admit(plan);
    await delegate.validate(plan);
  }

  @override
  Future<HdrReviewFacts> reviewFacts(HdrOpenPlan plan) async {
    if (plan.route.strategy != HdrStrategy.nativeDolbyVision) {
      return delegate.reviewFacts(plan);
    }
    final generation = generationOf(plan);
    if (!isCurrent(generation)) throw const OpenSuperseded();
    final window = HdrSessionReviewWindow(
        generation: generation,
        plan: plan,
        budget: budget,
        monotonicNow: monotonicNow);
    publishWindow(window);
    final facts = await window.bounded(() => delegate.reviewFacts(plan));
    if (!isCurrent(generation)) throw const OpenSuperseded();
    window._facts = facts;
    return facts;
  }

  @override
  Future<void> stop() => delegate.stop();
  @override
  Future<void> resetOwnedConfiguration() => delegate.resetOwnedConfiguration();
  @override
  Future<void> prepareOutput(HdrOpenPlan plan) => delegate.prepareOutput(plan);
  @override
  Future<void> configure(HdrOpenPlan plan) => delegate.configure(plan);
  @override
  Future<void> waitForOutput(HdrOpenPlan plan) => delegate.waitForOutput(plan);
  @override
  Future<void> open(HdrOpenPlan plan, {Duration? start, required bool play}) =>
      delegate.open(plan, start: start, play: play);
  @override
  HdrBackendObservation observe() => delegate.observe();
}

/// Consume a producer sample on the actual Player shared nonreentrant lock.
/// Current identity is compared to the producer's proof, never adopted. The
/// same conservative deadline includes queue admission and every read. Once
/// an expired queued callback acquires the lock it performs no property reads.
Future<void> consumeNativeDvSessionEvidence({
  required HdrSessionReviewWindow window,
  required int generation,
  required HdrOpenPlan plan,
  required HdrReviewFacts facts,
  required Object expectedPlayer,
  required Lock lock,
  required Future<HdrOptionSourceIdentity> Function() readIdentity,
  required Future<String> Function(String) readProperty,
  required HdrNativeDvOutputSnapshot? Function() readOutput,
  required bool Function() isCurrent,
}) async {
  void check() {
    if (!isCurrent()) throw const OpenSuperseded();
    window.remaining();
  }

  check();
  if (!window.matches(generation, plan, facts)) {
    throw const HdrNativeDvReviewFailure(
        HdrNativeDvReviewFailureKind.sourceIdentity);
  }
  final evidence = facts.nativeDvEvidence;
  if (evidence == null) {
    throw const HdrNativeDvReviewFailure(
        HdrNativeDvReviewFailureKind.configuration);
  }
  final source = evidence.source;
  final entry = int.tryParse(source.playlistEntryId);
  if (!identical(source.player, expectedPlayer) ||
      source.path != plan.media.uri ||
      facts.path != source.path ||
      source.path.isEmpty ||
      entry == null ||
      entry < 0 ||
      source.playlistEntryId != entry.toString() ||
      source.fileLoadedEpoch <= 0 ||
      evidence.loaded.playlistEntryId != entry ||
      evidence.loaded.epoch != source.fileLoadedEpoch) {
    throw const HdrNativeDvReviewFailure(
        HdrNativeDvReviewFailureKind.sourceIdentity);
  }
  final configuration = evidence.configuration;
  // The route realizer admits single-layer P5 (profile 5, compatibility 0)
  // and P8.4 (profile 8, compatibility 4) sources; the decoder must report
  // one of those two identities. Everything else is a configuration drift.
  final isRealizedP5 = facts.dolbyVisionProfile == 5 &&
      facts.dvCompatibilityId == 0 &&
      facts.dvElPresent == false;
  final isRealizedP84 = facts.dolbyVisionProfile == 8 &&
      facts.dvCompatibilityId == 4 &&
      facts.dvElPresent == false;
  if (configuration.mime != 'video/dolby-vision' ||
      configuration.codec.isEmpty ||
      !configuration.nativeDvActive ||
      evidence.hwdecCurrent != 'mediacodec' ||
      facts.hwdecCurrent != evidence.hwdecCurrent ||
      facts.codec != 'hevc' ||
      !(isRealizedP5 || isRealizedP84)) {
    throw const HdrNativeDvReviewFailure(
        HdrNativeDvReviewFailureKind.configuration);
  }

  Future<void> verifyIdentity() async {
    check();
    HdrOptionSourceIdentity currentIdentity;
    try {
      currentIdentity = await window.bounded(readIdentity);
    } on HdrNativeDvReviewFailure {
      rethrow;
    } on OpenSuperseded {
      rethrow;
    } catch (error) {
      throw HdrNativeDvReviewFailure(
          HdrNativeDvReviewFailureKind.sourceIdentity,
          cause: error);
    }
    if (currentIdentity != source) {
      throw const HdrNativeDvReviewFailure(
          HdrNativeDvReviewFailureKind.sourceIdentity);
    }
    check();
  }

  void verifyOutput() {
    check();
    final output = readOutput();
    if (output == null ||
        !identical(output.controller, evidence.controller) ||
        output.identity != evidence.output) {
      throw const HdrNativeDvReviewFailure(
          HdrNativeDvReviewFailureKind.outputIdentity);
    }
  }

  Future<void> verifyConfiguration() async {
    check();
    final raw =
        await window.bounded(() => readProperty('android-mediacodec-info'));
    final current = AndroidMediaCodecConfiguration.parse(raw);
    if (current == null ||
        current.mime != configuration.mime ||
        current.codec != configuration.codec ||
        current.nativeDvActive != configuration.nativeDvActive) {
      throw const HdrNativeDvReviewFailure(
          HdrNativeDvReviewFailureKind.configuration);
    }
    check();
  }

  Future<void> verifyHwdec() async {
    check();
    if (await window.bounded(() => readProperty('hwdec-current')) !=
        evidence.hwdecCurrent) {
      throw const HdrNativeDvReviewFailure(HdrNativeDvReviewFailureKind.hwdec);
    }
    check();
  }

  await window.bounded(() => lock.synchronized(() async {
        check();
        await verifyIdentity();
        verifyOutput();
        await verifyConfiguration();
        await verifyHwdec();
        await verifyIdentity();
        await verifyConfiguration();
        await verifyHwdec();
        // Last asynchronous read is the configured decoder. Output/deadline
        // checks below are synchronous. Managed source changes remain blocked
        // by this Player lock; equal endpoints are not a global ABA proof.
        await verifyConfiguration();
        verifyOutput();
        check();
      }));
  // Lock completion itself yields: a successor can arrive after the final
  // synchronous output sample. A fast-completing Future chain may resume
  // inline, so explicitly drain an already queued supersession before the
  // acceptance check. This turn is charged to the same deadline.
  await Future<void>.microtask(() {});
  check();
}
