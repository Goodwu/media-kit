/// This file is a part of media_kit (https://github.com/media-kit/media-kit).
///
/// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
/// All rights reserved.
/// Use of this source code is governed by MIT license that can be found in the LICENSE file.
import 'hdr_capabilities.dart';
import 'hdr_output_diagnostics.dart';
import 'hdr_route.dart';
import 'hdr_source_descriptor.dart';
import 'hdr_strategy.dart';
import 'hdr_strategy_realizer.dart';

/// The playback-level output preference (requirement 3.3). `off` is the
/// caller asking for tone-mapped SDR regardless of capability (SDR sources
/// stay SDR); it does not stop playback.
enum HdrOutputPreference {
  auto,

  off,
}

/// {@template hdr_routing_policy}
///
/// HdrRoutingPolicy
/// ----------------
/// The caller-tunable part of routing: an ordered strategy list per source
/// class and the `allowExperimental` gate (requirement 3.3/3.5).
///
/// Preferences only contain cross-platform strategy names — no vo, hwdec,
/// SDK or device knowledge — so an application may ship them as plain
/// configuration. A class missing from a custom map falls back to
/// [defaultPreferences]; a class missing from both (profile 10 and HDR10+
/// have no default row in requirement 3.4) yields an empty list and the
/// planner's safety net picks the route.
///
/// {@endtemplate}
class HdrRoutingPolicy {
  /// {@macro hdr_routing_policy}
  const HdrRoutingPolicy({this.preferences, this.allowExperimental = false});

  /// Caller overrides keyed by source class. Treated as immutable; callers
  /// must not mutate a map after handing it to a policy.
  final Map<HdrSourceClass, List<HdrStrategy>>? preferences;

  /// Whether `experimental` strategies may be selected (requirement 3.5).
  /// `verified` and `inherited` are always allowed.
  final bool allowExperimental;

  /// The default preference order per source class: HDR output first with
  /// direct routes preferred, tone-map last (requirement 3.4).
  ///
  /// `dvP10` and `hdr10Plus` intentionally have no row (requirement 3.4
  /// does not list them; Phase 1 does not cover AV1 and mpv cannot read
  /// HDR10+ metadata yet) — those classes fall through to the safety net.
  static const Map<HdrSourceClass, List<HdrStrategy>> defaultPreferences =
      <HdrSourceClass, List<HdrStrategy>>{
    HdrSourceClass.dvP5: <HdrStrategy>[
      HdrStrategy.nativeDolbyVision,
      HdrStrategy.metadataReshape,
      HdrStrategy.toneMapSdr,
    ],
    HdrSourceClass.dvP81: <HdrStrategy>[
      HdrStrategy.nativeDolbyVision,
      HdrStrategy.baseLayerDirect,
      HdrStrategy.metadataReshape,
      HdrStrategy.toneMapSdr,
    ],
    HdrSourceClass.dvP84: <HdrStrategy>[
      HdrStrategy.nativeDolbyVision,
      HdrStrategy.baseLayerDirect,
      HdrStrategy.baseLayerConvert,
      HdrStrategy.metadataReshape,
      HdrStrategy.toneMapSdr,
    ],
    HdrSourceClass.dvP82: <HdrStrategy>[
      HdrStrategy.nativeDolbyVision,
      HdrStrategy.metadataReshape,
      HdrStrategy.sdrDirect,
    ],
    HdrSourceClass.dvP7: <HdrStrategy>[
      HdrStrategy.baseLayerDirect,
      HdrStrategy.metadataReshape,
      HdrStrategy.toneMapSdr,
    ],
    HdrSourceClass.hdr10: <HdrStrategy>[
      HdrStrategy.baseLayerDirect,
      HdrStrategy.baseLayerConvert,
      HdrStrategy.toneMapSdr,
    ],
    HdrSourceClass.hlg: <HdrStrategy>[
      HdrStrategy.baseLayerDirect,
      HdrStrategy.baseLayerConvert,
      HdrStrategy.toneMapSdr,
    ],
    HdrSourceClass.hdrVivid: <HdrStrategy>[
      HdrStrategy.baseLayerDirect,
      HdrStrategy.metadataReshape,
      HdrStrategy.toneMapSdr,
    ],
    HdrSourceClass.sdr: <HdrStrategy>[
      HdrStrategy.sdrDirect,
    ],
  };

  /// The library default policy: requirement 3.4 preferences, experimental
  /// strategies gated off.
  static const HdrRoutingPolicy defaults = HdrRoutingPolicy();

  /// The preference list for [cls]: the caller's row when present, otherwise
  /// the default row, otherwise an empty list (safety net only).
  List<HdrStrategy> preferencesFor(HdrSourceClass cls) {
    return preferences?[cls] ?? defaultPreferences[cls] ?? const <HdrStrategy>[];
  }
}

/// {@template hdr_route_planner}
///
/// HdrRoutePlanner
/// ---------------
/// The single planning function used by both the pre-playback prediction
/// (`HdrCapabilities.predict`) and the executor, so a prediction and the
/// route that actually gets applied cannot drift apart (R1.3).
///
/// Algorithm (plan 1.3): classify the source, take the preference list for
/// the class (`off` short-circuits to the safety-net strategy), and pick
/// the first entry that passes the maturity gate, realizes feasibly, and
/// does not depend on an excluded pipeline stage. Skipped entries stay in
/// the candidate list with their typed reason. When nothing survives, the
/// safety net (tone-mapped SDR, SDR direct for SDR sources) keeps playback
/// going — requirement section 2 forbids stopping playback — except a P5
/// source without the dovi rescale pipeline, which reports
/// [HdrDegradeReason.p5PipelineUnavailable] and `playable == false`
/// (R3.3: never output a wrongly colored picture).
///
/// {@endtemplate}
class HdrRoutePlanner {
  const HdrRoutePlanner._();

  /// Plans the route for [source] against [capabilities].
  ///
  /// [excluded] maps a pipeline-stage tag ([HdrRouteDependency]) to the
  /// reason it failed at runtime; candidates depending on an excluded stage
  /// are skipped with that reason carried over ("沿用失败原因").
  static HdrRoutePrediction plan({
    required HdrSourceDescriptor source,
    required HdrCapabilities capabilities,
    HdrRoutingPolicy policy = HdrRoutingPolicy.defaults,
    HdrOutputPreference preference = HdrOutputPreference.auto,
    Map<String, HdrDegradeReason> excluded = const <String, HdrDegradeReason>{},
  }) {
    final HdrSourceClass cls = HdrSourceClass.of(source);
    final HdrStrategy fallback = cls == HdrSourceClass.sdr
        ? HdrStrategy.sdrDirect
        : HdrStrategy.toneMapSdr;
    final List<HdrStrategy> list = preference == HdrOutputPreference.off
        ? <HdrStrategy>[fallback]
        : policy.preferencesFor(cls);

    final List<HdrCandidate> candidates = <HdrCandidate>[];
    HdrCandidate? selected;
    for (int i = 0; i < list.length; i++) {
      final HdrCandidate candidate = _evaluate(
        list[i],
        source: source,
        sourceClass: cls,
        capabilities: capabilities,
        policy: policy,
        excluded: excluded,
      );
      candidates.add(candidate);
      if (candidate.feasible) {
        selected = candidate;
        // Evaluate the remaining entries for display (feasibility and skip
        // reasons), without changing the selection.
        for (int j = i + 1; j < list.length; j++) {
          candidates.add(_evaluate(
            list[j],
            source: source,
            sourceClass: cls,
            capabilities: capabilities,
            policy: policy,
            excluded: excluded,
          ));
        }
        break;
      }
    }
    if (selected == null) {
      // Safety net: playback continues tone-mapped (SDR direct for SDR
      // sources). It bypasses the maturity gate and the excluded stages on
      // purpose — the requirement mandates continuing playback — so its
      // only possible failure is why playback will not start at all (a P5
      // source without the rescale pipeline, R3.3).
      final HdrCandidate candidate = _evaluate(
        fallback,
        source: source,
        sourceClass: cls,
        capabilities: capabilities,
        policy: policy,
        excluded: excluded,
        gateMaturity: false,
        honorExcluded: false,
      );
      selected = candidate;
      candidates.add(candidate);
    }

    final HdrRoute? route = selected.route;
    final bool dependsOnDataSpace =
        route != null && route.surfaceTransfer != null;
    final ext = capabilities.dataSpaceExt;
    final HdrPredictionConfidence confidence =
        !dependsOnDataSpace || (ext != null && ext.applicable)
            ? HdrPredictionConfidence.verified
            : HdrPredictionConfidence.unverified;

    final HdrRoutePrediction prediction = HdrRoutePrediction(
      source: source,
      selected: selected,
      candidates: List<HdrCandidate>.unmodifiable(candidates),
      presentation:
          route?.presentation ?? HdrPresentation.ofStrategy(selected.strategy),
      confidence: confidence,
      playable: selected.feasible,
    );
    // `HDR predict:` layer (R4.3), emitted at the single planning function
    // prediction and execution both share (R1.3). Static emit: the sink is
    // touched only when `HdrOutputDiagnostics.enabled` is set, so the pure
    // function stays I/O-free and the disabled cost is one boolean check.
    HdrOutputDiagnostics.predict(prediction);
    return prediction;
  }

  /// Evaluates one strategy against the gates and this device.
  ///
  /// Order (plan 1.3): maturity gate, then realization, then the excluded
  /// stages — a skipped candidate keeps the first matching reason.
  static HdrCandidate _evaluate(
    HdrStrategy strategy, {
    required HdrSourceDescriptor source,
    required HdrSourceClass sourceClass,
    required HdrCapabilities capabilities,
    required HdrRoutingPolicy policy,
    required Map<String, HdrDegradeReason> excluded,
    bool gateMaturity = true,
    bool honorExcluded = true,
  }) {
    final HdrStrategyMaturity maturity =
        HdrStrategyMaturityTable.of(sourceClass, strategy);
    if (gateMaturity) {
      if (maturity == HdrStrategyMaturity.unsupported) {
        return HdrCandidate(
          strategy: strategy,
          maturity: maturity,
          skipReason: HdrDegradeReason.unsupportedStrategy,
        );
      }
      if (maturity == HdrStrategyMaturity.experimental &&
          !policy.allowExperimental) {
        return HdrCandidate(
          strategy: strategy,
          maturity: maturity,
          skipReason: HdrDegradeReason.experimentalStrategySkipped,
        );
      }
    }
    final HdrStrategyRealization realization = HdrStrategyRealizer.realize(
      strategy,
      source: source,
      sourceClass: sourceClass,
      capabilities: capabilities,
    );
    final HdrRoute? route = realization.route;
    if (route == null) {
      return HdrCandidate(
        strategy: strategy,
        maturity: maturity,
        skipReason:
            realization.infeasibleReason ?? HdrDegradeReason.unsupportedStrategy,
      );
    }
    // The excluded check runs after realize because the dependency tags come
    // from the realized route. Edge case: a strategy whose realize fails AND
    // whose (would-be) dependencies are excluded reports the realize reason,
    // not the carried failure reason — the deeper cause. The selected
    // strategy is unaffected either way.
    for (final MapEntry<String, HdrDegradeReason> entry in excluded.entries) {
      if (honorExcluded && route.dependencies.contains(entry.key)) {
        return HdrCandidate(
          strategy: strategy,
          maturity: maturity,
          skipReason: entry.value,
        );
      }
    }
    return HdrCandidate(
      strategy: strategy,
      maturity: maturity,
      feasible: true,
      route: route,
    );
  }
}
