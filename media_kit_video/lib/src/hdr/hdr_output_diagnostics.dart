/// This file is a part of media_kit (https://github.com/media-kit/media-kit).
///
/// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
/// All rights reserved.
/// Use of this source code is governed by MIT license that can be found in the LICENSE file.
import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;

import 'hdr_capabilities.dart';
import 'hdr_open_plan.dart' show HdrReportSource;
import 'hdr_route.dart';
import 'hdr_source_descriptor.dart';
import 'hdr_strategy.dart';

/// {@template hdr_output_diagnostics}
///
/// HdrOutputDiagnostics
/// --------------------
/// Layered single-line `key=value` diagnostic logging for the HDR output
/// pipeline (requirement R4.3). Seven layers, one fixed line format each:
///
/// * `HDR capability:` — capability snapshot summary
///   (`HdrCapabilities.queryWith`).
/// * `HDR predict:` — planner output: selected strategy plus every candidate
///   and its skip reason (`HdrRoutePlanner.plan`).
/// * `HDR classify:` — decoder-fact classification result and its origin
///   (`HdrSourceClassifier.classify`).
/// * `HDR decision:` — the session's routing decision, once at plan time and
///   once at the verified report, both with candidates and generation.
/// * `HDR readback:` — surface dataspace request / applied path / readback
///   (`AndroidHdrBackend.configure`).
/// * `HDR degrade:` — every published `HdrDegradedEvent` (reason, from, to).
/// * `HDR recover:` — every published `HdrCapabilityChangedEvent` (snapshot
///   summary; recovery never upgrades automatically, R3.4).
///
/// Every line carries the fixed `HdrDiag` tag so logcat can filter on it:
/// `HdrDiag HDR decision: phase=plan gen=1 ...`.
///
/// Performance contract (plan S8): [enabled] defaults to false and the
/// switch is checked inside every emit method *before any string is built*.
/// Call sites pass existing object references only — never interpolated
/// strings — so a disabled pipeline costs one static-boolean read per emit
/// call and constructs zero strings. This includes the pure planner: the
/// static emit in `HdrRoutePlanner.plan` short-circuits on the same flag and
/// touches no sink, keeping the function free of I/O while diagnostics stay
/// available at the exact point the prediction is produced.
///
/// The sink is [printer], `debugPrint` (flutter/foundation) in production;
/// tests inject a capturing printer to assert the emitted lines.
///
/// {@endtemplate}
class HdrOutputDiagnostics {
  HdrOutputDiagnostics._();

  /// Filter tag prefixed to every emitted line.
  static const String tag = 'HdrDiag';

  /// Master switch (R4.3): diagnostics are off by default.
  static bool enabled = false;

  /// The log sink. `debugPrint` in production; tests replace it to capture
  /// and assert lines.
  @visibleForTesting
  static void Function(String line) printer = debugPrint;

  // ---------------------------------------------------------------------------
  // capability / recover
  // ---------------------------------------------------------------------------

  /// `HDR capability:` snapshot summary, emitted by
  /// `HdrCapabilities.queryWith` after a completed query.
  static void capability(HdrCapabilities capabilities) {
    if (!enabled) return;
    printer('$tag HDR capability: ${_capabilityFields(capabilities)}');
  }

  /// `HDR recover:` capability-change snapshot summary, emitted by the
  /// session when it publishes an `HdrCapabilityChangedEvent` (R3.4).
  static void recover({
    required int generation,
    required HdrCapabilities capabilities,
  }) {
    if (!enabled) return;
    printer(
        '$tag HDR recover: gen=$generation ${_capabilityFields(capabilities)}');
  }

  /// The shared capability snapshot fields of the `capability` and `recover`
  /// layers. Field set and order are fixed for golden-style assertions.
  static String _capabilityFields(HdrCapabilities c) {
    final String types;
    if (c.displayHdrTypes == null) {
      types = 'unreported'; // No capability report at all (distinct from empty).
    } else if (c.displayHdrTypes!.isEmpty) {
      types = 'none';
    } else {
      types = (c.displayHdrTypes!.toList()..sort()).join(',');
    }
    final String hevcMain10 = c.hevcDecoders.isEmpty
        ? 'none'
        : '${c.hevcDecoders.any((HdrDecoderInfo d) => d.main10 == true)}';
    final String hevc4k = c.hevcDecoders.isEmpty
        ? 'none'
        : '${c.hevcDecoders.any((HdrDecoderInfo d) => d.supports4K)}';
    return 'sdk=${c.sdkInt} '
        'displayHdrTypes=$types '
        'hevcDecoders=${c.hevcDecoders.length} '
        'hevcMain10=$hevcMain10 '
        'hevc4k=$hevc4k '
        'dvDecoders=${c.dolbyVisionDecoders.length} '
        'p5Pipeline=${c.p5PipelineAvailable} '
        'bridge=${c.dataSpaceBridgeLoaded} '
        'ext=${c.dataSpaceExt?.id ?? 'none'} '
        'extApplicable=${c.dataSpaceExt == null ? 'none' : c.dataSpaceExt!.applicable}';
  }

  // ---------------------------------------------------------------------------
  // predict / decision
  // ---------------------------------------------------------------------------

  /// `HDR predict:` planner output (R1.2): the selected strategy with its
  /// maturity, presentation, confidence and playability, plus every candidate
  /// in preference order as `strategy:ok` or `strategy:<skipReason>`.
  static void predict(HdrRoutePrediction prediction) {
    if (!enabled) return;
    printer('$tag HDR predict: ${_predictionFields(prediction)}');
  }

  /// `HDR decision:` the session's routing decision. `phase=plan` is emitted
  /// by the open preparer right after the plan is produced; `phase=applied`
  /// is emitted when the verified report is published for the same
  /// generation. Both carry the selected strategy and the full candidate
  /// list with skip reasons.
  static void decision({
    required int generation,
    required String phase,
    HdrReportSource? origin,
    required HdrSourceDescriptor source,
    required HdrRoutePrediction prediction,
    HdrRoute? actual,
    String? hwdecCurrent,
    String? dataSpaceRequested,
    String? dataSpacePath,
    String? dataSpaceReadback,
    bool? verified,
    HdrDegradeReason? degradeReason,
  }) {
    if (!enabled) return;
    final HdrRoute? route = actual ?? prediction.selected.route;
    printer('$tag HDR decision: '
        'phase=$phase '
        'gen=$generation '
        'origin=${origin?.name ?? 'none'} '
        'source=${_sourceValue(source)} '
        'class=${HdrSourceClass.of(source).name} '
        'selected=${prediction.selected.strategy.name} '
        'maturity=${prediction.selected.maturity.name} '
        'presentation=${prediction.presentation.name} '
        'confidence=${prediction.confidence.name} '
        'vo=${route?.vo ?? 'none'} '
        'hwdec=${route?.hwdec ?? 'none'} '
        'output=${route?.outputTransfer.name ?? 'none'} '
        'topology=${route?.topology.name ?? 'none'} '
        'surface=${route?.surfaceTransfer ?? 'none'} '
        'stripRpu=${route?.stripDvRpu ?? 'none'} '
        'hwdecCurrent=${_orNone(hwdecCurrent)} '
        'requested=${_orNone(dataSpaceRequested)} '
        'path=${_orNone(dataSpacePath)} '
        'readback=${_orNone(dataSpaceReadback)} '
        'verified=${verified ?? false} '
        'degrade=${degradeReason?.name ?? 'none'} '
        'candidates=${_candidatesValue(prediction)}');
  }

  static String _predictionFields(HdrRoutePrediction prediction) {
    return 'source=${_sourceValue(prediction.source)} '
        'class=${HdrSourceClass.of(prediction.source).name} '
        'selected=${prediction.selected.strategy.name} '
        'maturity=${prediction.selected.maturity.name} '
        'presentation=${prediction.presentation.name} '
        'confidence=${prediction.confidence.name} '
        'playable=${prediction.playable} '
        'candidates=${_candidatesValue(prediction)}';
  }

  /// Candidates in preference order: `strategy:ok` when feasible, else
  /// `strategy:<skipReason.name>`.
  static String _candidatesValue(HdrRoutePrediction prediction) {
    return prediction.candidates
        .map((HdrCandidate c) => c.feasible
            ? '${c.strategy.name}:ok'
            : '${c.strategy.name}:${c.skipReason?.name ?? 'infeasible'}')
        .join(',');
  }

  // ---------------------------------------------------------------------------
  // classify
  // ---------------------------------------------------------------------------

  /// `HDR classify:` the classified description and where it came from:
  /// `origin=facts` (decoder-reported), `origin=hint` (no facts yet, the
  /// caller hint stands) or `origin=default` (nothing known).
  static void classify({
    required HdrSourceDescriptor descriptor,
    required String origin,
  }) {
    if (!enabled) return;
    printer('$tag HDR classify: '
        'origin=$origin '
        'codec=${_orNone(descriptor.codec)} '
        'transfer=${_orNone(descriptor.transfer)} '
        'primaries=${_orNone(descriptor.primaries)} '
        'meta=${descriptor.dynamicMetadata.name} '
        'dv=${descriptor.dvProfile?.toString() ?? 'none'} '
        'compat=${descriptor.dvCompatibilityId?.toString() ?? 'none'} '
        'el=${descriptor.enhancementLayer?.toString() ?? 'unknown'}');
  }

  // ---------------------------------------------------------------------------
  // readback
  // ---------------------------------------------------------------------------

  /// `HDR readback:` the surface dataspace outcome: what was requested, the
  /// applied path (`ndk`/`surfaceControl`/`ext:<id>`/`none`), whether the
  /// application reported success, and what was read back. Emitted before
  /// the failure gates so a failing application is logged too.
  static void readback({
    required String requested,
    String? path,
    required bool applied,
    String? readback,
  }) {
    if (!enabled) return;
    printer('$tag HDR readback: '
        'requested=$requested '
        'path=${_orNone(path)} '
        'applied=$applied '
        'readback=${_orNone(readback)}');
  }

  // ---------------------------------------------------------------------------
  // degrade
  // ---------------------------------------------------------------------------

  /// `HDR degrade:` one line per published `HdrDegradedEvent`: the typed
  /// reason, the abandoned and the next route's strategy, and the diagnostic
  /// text (last field, free text).
  static void degrade({
    required int generation,
    required HdrDegradeReason reason,
    HdrRoute? from,
    HdrRoute? to,
    String diagnostic = '',
  }) {
    if (!enabled) return;
    printer('$tag HDR degrade: '
        'gen=$generation '
        'reason=${reason.name} '
        'from=${from?.strategy.name ?? 'none'} '
        'to=${to?.strategy.name ?? 'none'} '
        'diagnostic=$diagnostic');
  }

  // ---------------------------------------------------------------------------
  // Shared value encodings
  // ---------------------------------------------------------------------------

  /// Compact source description: `codec,transfer,primaries,meta,dv,compat,el`
  /// with `none` for unknown strings/numbers and `unknown` for a null
  /// enhancement-layer flag.
  static String _sourceValue(HdrSourceDescriptor s) {
    return <String>[
      _orNone(s.codec),
      _orNone(s.transfer),
      _orNone(s.primaries),
      s.dynamicMetadata.name,
      s.dvProfile?.toString() ?? 'none',
      s.dvCompatibilityId?.toString() ?? 'none',
      s.enhancementLayer?.toString() ?? 'unknown',
    ].join(',');
  }

  static String _orNone(String? value) {
    return (value == null || value.isEmpty) ? 'none' : value;
  }
}
