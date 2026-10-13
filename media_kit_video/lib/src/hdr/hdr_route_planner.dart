/// This file is a part of media_kit (https://github.com/media-kit/media-kit).
///
/// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
/// All rights reserved.
/// Use of this source code is governed by MIT license that can be found in the LICENSE file.
import '../routing/video_decoder_support.dart';
import '../routing/video_route_options.dart';
import '../routing/video_route_option_review.dart';
import 'hdr_capabilities.dart';
import 'hdr_output_diagnostics.dart';
import 'hdr_route.dart';
import 'hdr_source_descriptor.dart';
import 'hdr_strategy.dart';
import 'hdr_strategy_realizer.dart';

/// The playback-level output preference (requirement 3.3). `off` is the
/// caller asking for tone-mapped SDR regardless of capability (SDR sources
/// stay SDR); it does not stop playback.
enum HdrOutputPreference { auto, off }

/// {@template hdr_routing_policy}
///
/// HdrRoutingPolicy
/// ----------------
/// Legacy source-specific lists are retained while applications migrate to
/// the fixed C1–C4 catalog. Maturity labels are diagnostic facts only;
/// they never authorize or suppress execution.
///
/// Preferences only contain cross-platform strategy names — no vo, hwdec,
/// SDK or device knowledge — so an application may ship them as plain
/// configuration. A class missing from a custom map falls back to
/// [defaultPreferences]; a class missing from both (profile 10 has no
/// default row) yields an empty list and the planner blocks with the
/// placeholder candidate.
///
/// {@endtemplate}
class HdrRoutingPolicy {
  /// {@macro hdr_routing_policy}
  const HdrRoutingPolicy({this.preferences, bool? allowExperimental})
      : allowExperimental = allowExperimental ?? false,
        experimentalWasSpecified = allowExperimental != null;

  /// Caller overrides keyed by source class. Treated as immutable; callers
  /// must not mutate a map after handing it to a policy.
  final Map<HdrSourceClass, List<HdrStrategy>>? preferences;

  /// Deprecated compatibility data; this value does not gate candidates.
  /// Remove with the application/config API migration.
  final bool allowExperimental;
  final bool experimentalWasSpecified;

  /// The default preference order per source class: HDR output first with
  /// direct routes preferred, tone-map last (requirement 3.4).
  ///
  /// `dvP10` intentionally has no row (requirement 3.4 does not list it;
  /// Phase 1 does not cover AV1) — that class plans to the blocking
  /// placeholder candidate instead of any SDR fallback. `hdr10Plus` plans
  /// through the fixed C1–C3 catalog with explicit not-implemented errors
  /// on its dynamic candidates.
  static const Map<HdrSourceClass, List<HdrStrategy>> defaultPreferences =
      <HdrSourceClass, List<HdrStrategy>>{
    HdrSourceClass.dvP5: <HdrStrategy>[
      HdrStrategy.nativeDolbyVision,
      HdrStrategy.metadataReshape,
      HdrStrategy.toneMapSdr,
    ],
    HdrSourceClass.dvP81: <HdrStrategy>[
      HdrStrategy.nativeDolbyVision,
      HdrStrategy.metadataReshape,
      HdrStrategy.baseLayerDirect,
      HdrStrategy.toneMapSdr,
    ],
    HdrSourceClass.dvP84: <HdrStrategy>[
      HdrStrategy.nativeDolbyVision,
      HdrStrategy.metadataReshape,
      HdrStrategy.baseLayerDirect,
      HdrStrategy.baseLayerConvert,
      HdrStrategy.toneMapSdr,
    ],
    HdrSourceClass.dvP82: <HdrStrategy>[
      HdrStrategy.nativeDolbyVision,
      HdrStrategy.metadataReshape,
      HdrStrategy.sdrDirect,
    ],
    HdrSourceClass.dvP7: <HdrStrategy>[
      HdrStrategy.nativeDolbyVision,
      HdrStrategy.metadataReshape,
      HdrStrategy.baseLayerDirect,
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
      HdrStrategy.nativeHdrVivid,
      HdrStrategy.metadataReshape,
      HdrStrategy.baseLayerDirect,
      HdrStrategy.baseLayerConvert,
      HdrStrategy.toneMapSdr,
    ],
    HdrSourceClass.hdr10Plus: <HdrStrategy>[
      HdrStrategy.nativeHdr10Plus,
      HdrStrategy.metadataReshape,
      HdrStrategy.baseLayerDirect,
      HdrStrategy.baseLayerConvert,
      HdrStrategy.toneMapSdr,
    ],
    HdrSourceClass.sdr: <HdrStrategy>[HdrStrategy.sdrDirect],
  };

  /// The library default policy: requirement 3.4 preferences, experimental
  /// strategies gated off.
  static const HdrRoutingPolicy defaults = HdrRoutingPolicy();

  /// The preference list for [cls]: the caller's row when present, otherwise
  /// the default row, otherwise an empty list (planning then blocks with the
  /// placeholder candidate).
  List<HdrStrategy> preferencesFor(HdrSourceClass cls) {
    return preferences?[cls] ??
        defaultPreferences[cls] ??
        const <HdrStrategy>[];
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
/// the class (`off` short-circuits to the explicit SDR strategy), and pick
/// the first entry that realizes feasibly, and
/// does not depend on an excluded pipeline stage. Skipped entries stay in
/// the candidate list with their typed reason. The SDR safety net (tone-map
/// for HDR sources, SDR direct for SDR sources) exists only when an SDR
/// output is allowed: a plain SDR source, an explicit off/require-SDR
/// request, or a display whose report is present and empty. On an
/// HDR-capable or unknown display (any non-empty report, or no report at
/// all), an exhausted HDR candidate list blocks playback instead of
/// synthesizing an implicit tone-map fallback; the first rejected
/// candidate's reason is preserved. A P5 source without the rescale
/// pipeline remains blocked (never output a wrongly colored picture).
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
    HdrRoutingPolicy? policy,
    HdrOutputPreference? preference,
    EffectiveVideoRouteOptions? options,
    Map<String, HdrDegradeReason> excluded = const <String, HdrDegradeReason>{},
  }) {
    options = resolveHdrRouteOptions(
        options: options, policy: policy, preference: preference);
    policy = HdrRoutingPolicy(
        preferences: policy?.preferences,
        allowExperimental: options.experimental);
    preference = options.output.isRequired &&
            options.output.target == VideoOutputIntent.sdr
        ? HdrOutputPreference.off
        : preference ?? HdrOutputPreference.auto;
    final HdrSourceClass cls = HdrSourceClass.of(source);
    // In automatic mode an HDR source may use SDR only when the display
    // explicitly reports SDR-only capabilities. A missing report is unknown,
    // not an SDR panel. The explicit off/require-SDR request is separate.
    final bool allowSdrOutput = cls == HdrSourceClass.sdr ||
        preference == HdrOutputPreference.off ||
        capabilities.displayHdrTypes?.isEmpty == true;
    final HdrStrategy fallback = cls == HdrSourceClass.sdr
        ? HdrStrategy.sdrDirect
        : HdrStrategy.toneMapSdr;
    final List<HdrStrategy> list = preference == HdrOutputPreference.off
        ? <HdrStrategy>[fallback]
        : policy.preferencesFor(cls);

    final List<HdrCandidate> candidates = <HdrCandidate>[];
    HdrCandidate? selected;
    for (final strategy in list) {
      for (final candidate in _evaluateCandidates(strategy,
          source: source,
          sourceClass: cls,
          capabilities: capabilities,
          policy: policy,
          excluded: excluded,
          options: options)) {
        final effective = !allowSdrOutput &&
                candidate.feasible &&
                candidate.route?.outputTransfer == HdrOutputTransfer.sdr
            ? HdrCandidate(
                strategy: candidate.strategy,
                maturity: candidate.maturity,
                skipReason: HdrDegradeReason.displayLacksTransfer,
            sourceClass: candidate.sourceClass,
            stage: candidate.stage,
            executionId: candidate.executionId)
            : candidate;
        candidates.add(effective);
        if (effective.feasible) selected ??= effective;
      }
    }
    if (selected == null && allowSdrOutput) {
      // SDR fallback is limited to an explicit SDR request or a confirmed
      // SDR-only display. It must not become a hidden HDR failure exit.
      final fallbackCandidates = _evaluateCandidates(fallback,
          source: source,
          sourceClass: cls,
          capabilities: capabilities,
          policy: policy,
          excluded: excluded,
          gateMaturity: false,
          options: options);
      candidates.addAll(fallbackCandidates);
      selected = fallbackCandidates.firstWhere(
          (candidate) => candidate.feasible,
          orElse: () => fallbackCandidates.first);
    }

    // No fallback candidate is synthesized for HDR-capable or unknown
    // displays. Preserve the first rejected candidate as the blocking reason.
    selected ??= candidates.isNotEmpty
        ? candidates.first
        : HdrCandidate(
            strategy: HdrStrategy.metadataReshape,
            maturity: HdrStrategyMaturity.unsupported,
            skipReason: cls == HdrSourceClass.dvUnknown
                ? HdrDegradeReason.sourceMetadataUnknown
                : HdrDegradeReason.unsupportedStrategy);
    if (candidates.isEmpty) candidates.add(selected);
    final ordered = applyVideoRouteOptions(candidates, capabilities, options);
    selected = ordered.firstWhere((candidate) => candidate.feasible,
        orElse: () => selected!);
    final HdrRoute? route = selected.route;
    final bool dependsOnDataSpace =
        route != null && route.surfaceTransfer != null;
    final ext = capabilities.dataSpaceExt;
    final HdrPredictionConfidence confidence = !dependsOnDataSpace ||
            (ext != null && ext.applicable && ext.id == 'lya-pq')
        ? HdrPredictionConfidence.verified
        : HdrPredictionConfidence.unverified;

    final HdrRoutePrediction prediction = HdrRoutePrediction(
      source: source,
      selected: selected,
      candidates: List<HdrCandidate>.unmodifiable(ordered),
      presentation:
          route?.presentation ?? HdrPresentation.ofStrategy(selected.strategy),
      confidence: cls == HdrSourceClass.dvUnknown ||
              route != null &&
                  (route.hwdec == 'no' || capabilities.sourceSupport != null) &&
                  capabilities.decoderSupportFor(route) == VideoSupport.unknown
          ? HdrPredictionConfidence.unverified
          : confidence,
      playable: selected.feasible,
    );
    // `HDR predict:` layer (R4.3), emitted at the single planning function
    // prediction and execution both share (R1.3). Static emit: the sink is
    // touched only when `HdrOutputDiagnostics.enabled` is set, so the pure
    // function stays I/O-free and the disabled cost is one boolean check.
    HdrOutputDiagnostics.predict(prediction);
    return prediction;
  }

  static HdrRouteStage? _stageFor(
      HdrStrategy strategy, HdrSourceClass cls) {
    switch (strategy) {
      case HdrStrategy.nativeDolbyVision:
      case HdrStrategy.nativeHdr10Plus:
      case HdrStrategy.nativeHdrVivid:
        return HdrRouteStage.c1;
      case HdrStrategy.metadataReshape:
        return HdrRouteStage.c2;
      case HdrStrategy.baseLayerDirect:
        return cls == HdrSourceClass.hdr10 || cls == HdrSourceClass.hlg
            ? HdrRouteStage.c1
            : HdrRouteStage.c3;
      case HdrStrategy.baseLayerConvert:
        return HdrRouteStage.c4;
      case HdrStrategy.toneMapSdr:
      case HdrStrategy.sdrDirect:
        return null;
    }
  }

  static List<HdrCandidate> _evaluateCandidates(
    HdrStrategy strategy, {
    required HdrSourceDescriptor source,
    required HdrSourceClass sourceClass,
    required HdrCapabilities capabilities,
    required HdrRoutingPolicy policy,
    required Map<String, HdrDegradeReason> excluded,
    bool gateMaturity = true,
    required EffectiveVideoRouteOptions options,
  }) {
    final candidates = [
      for (final realization in HdrStrategyRealizer.realizeCandidates(strategy,
          source: source, sourceClass: sourceClass, capabilities: capabilities))
        _evaluate(strategy,
            source: source,
            sourceClass: sourceClass,
            capabilities: capabilities,
            policy: policy,
            excluded: excluded,
            gateMaturity: gateMaturity,
            realization: realization)
          .withRoutingIdentity(sourceClass, _stageFor(strategy, sourceClass)),
    ];
    // Maturity is recorded but never used as a routing admission check.
    return applyVideoRouteOptions(candidates, capabilities, options);
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
    required HdrStrategyRealization realization,
  }) {
    final HdrStrategyMaturity maturity = HdrStrategyMaturityTable.of(
      sourceClass,
      strategy,
    );
    if (source.hasUnresolvedDolbyVision) {
      return HdrCandidate(
        strategy: strategy,
        maturity: maturity,
        isSafetyNet: !gateMaturity,
        skipReason: HdrDegradeReason.sourceMetadataUnknown,
      );
    }
    // Missing code is a genuine path error, not an experimental switch
    // rejection. The route stays visible even when a baseline can follow.
    if (realization.infeasibleReason == HdrDegradeReason.routeNotImplemented) {
      return HdrCandidate(
        strategy: strategy,
        maturity: maturity,
        skipReason: HdrDegradeReason.routeNotImplemented,
      );
    }
    // A route with experimental or unsupported *historical evidence* is
    // evaluated like every other route. Structural eligibility and the
    // actual implementation, not maturity, decide its outcome.
    final HdrRoute? route = realization.route;
    if (route == null) {
      return HdrCandidate(
        strategy: strategy,
        maturity: maturity,
        isSafetyNet: !gateMaturity,
        skipReason: realization.infeasibleReason ??
            HdrDegradeReason.unsupportedStrategy,
      );
    }
    // The excluded check runs after realize because the dependency tags come
    // from the realized route. Edge case: a strategy whose realize fails AND
    // whose (would-be) dependencies are excluded reports the realize reason,
    // not the carried failure reason — the deeper cause. The selected
    // strategy is unaffected either way.
    for (final MapEntry<String, HdrDegradeReason> entry in excluded.entries) {
      if (route.dependencies.contains(entry.key)) {
        return HdrCandidate(
          strategy: strategy,
          maturity: maturity,
          isSafetyNet: !gateMaturity,
          skipReason: entry.value,
        );
      }
    }
    if (capabilities.sourceSupport != null &&
        capabilities.decoderSupportFor(route) == VideoSupport.unsupported) {
      return HdrCandidate(
        strategy: strategy,
        maturity: maturity,
        isSafetyNet: !gateMaturity,
        skipReason: HdrDegradeReason.sourceDecodeUnsupported,
      );
    }
    return HdrCandidate(
      strategy: strategy,
      maturity: maturity,
      isSafetyNet: !gateMaturity,
      feasible: true,
      route: route,
    );
  }
}

/// Convert legacy callers once; explicit contradictory inputs cannot be ignored.
EffectiveVideoRouteOptions resolveHdrRouteOptions(
    {EffectiveVideoRouteOptions? options,
    HdrRoutingPolicy? policy,
    HdrOutputPreference? preference}) {
  if (options != null) {
    if (preference == HdrOutputPreference.off &&
        !(options.output.isRequired &&
            options.output.target == VideoOutputIntent.sdr)) {
      throw ArgumentError(
          'Legacy HDR off conflicts with effective output options');
    }
    // The legacy experimental field has no routing semantics. Do not reject
    // otherwise valid requests merely because old app/config layers disagree.
    return options;
  }
  return EffectiveVideoRouteOptions.resolve(
      application: VideoRouteOptions(
          output: preference == null
              ? null
              : preference == HdrOutputPreference.off
                  ? const VideoRouteSelection.require(VideoOutputIntent.sdr)
                  : const VideoRouteSelection<VideoOutputIntent>.auto(),
          experimental: policy?.experimentalWasSpecified == true
              ? policy!.allowExperimental
              : null));
}
