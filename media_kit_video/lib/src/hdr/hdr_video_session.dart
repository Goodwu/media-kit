/// This file is a part of media_kit (https://github.com/media-kit/media-kit).
///
/// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
/// All rights reserved.
/// Use of this source code is governed by MIT license that can be found in the LICENSE file.
import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:synchronized/synchronized.dart';

import 'package:media_kit_video/src/video_controller/android_video_controller/android_video_controller.dart';
import 'package:media_kit_video/src/video_controller/platform_video_controller.dart';
import 'package:media_kit_video/src/video_controller/video_controller.dart';

import '../routing/video_output_target.dart';
import '../routing/video_route_capabilities.dart';
import '../routing/video_source_spec.dart';
import 'hdr_capabilities.dart';
import 'hdr_disposal.dart';
import 'hdr_open_coordinator.dart';
import 'hdr_open_plan.dart';
import 'hdr_native_dv_option_owner.dart';
import 'hdr_native_dv_review_evidence.dart';
import 'hdr_decoder_review.dart';
import 'hdr_output_diagnostics.dart';
import 'hdr_output_event.dart';
import 'hdr_output_report.dart';
import 'hdr_output_slot.dart';
import 'hdr_output_contract.dart';
import 'hdr_player_backend.dart';
import 'hdr_route.dart';
import 'hdr_route_planner.dart';
import 'hdr_source_facts.dart';
import 'hdr_source_descriptor.dart';
import 'hdr_source_intent.dart';
import 'hdr_session_native_dv_policy.dart';
import 'hdr_strategy.dart';

typedef HdrSessionRoutePlanner = HdrRoutePrediction Function({
  required HdrSourceDescriptor source,
  required HdrCapabilities capabilities,
  required HdrRoutingPolicy policy,
  required HdrOutputPreference preference,
  required Map<String, HdrDegradeReason> excluded,
});

/// {@template hdr_video_session}
///
/// HdrVideoSession
/// ---------------
/// The HDR output orchestration above a single [VideoController] (R2): it
/// owns a [Player], plans routes with the same planner the pre-playback
/// prediction uses, drives the ported open coordinator / output slot /
/// Android backend, reviews the decoder facts after every open, degrades
/// along the candidate list when a selected route fails at runtime, and
/// publishes the report ([report]) plus the event stream ([events]).
///
/// The current controller is exposed through [controller]; a topology switch
/// replaces the controller instance (the old one is disposed first), so
/// consumers must follow the [controller] listenable (the `HdrVideo` widget
/// does this).
///
/// On non-Android platforms the session degrades to a single-controller
/// passthrough and reports [HdrDegradeReason.unsupportedPlatform] (R2.5);
/// caller code needs no platform branching.
///
/// {@endtemplate}
class HdrVideoSession {
  /// Build-time pixel-format override for the GPU HDR platform view.
  /// Default rgba1010102 (10-bit); 'rgba8888' trades bit depth for a
  /// potentially cheaper compositor path on old devices.
  static const String _surfaceFormatOverride = String.fromEnvironment(
    'MEDIA_KIT_ANDROID_HDR_SURFACE_FORMAT',
    defaultValue: 'rgba1010102',
  );

  /// {@macro hdr_video_session}
  HdrVideoSession(
    Player player, {
    HdrOutputPreference preference = HdrOutputPreference.auto,
    HdrRoutingPolicy policy = HdrRoutingPolicy.defaults,
    VideoOutputTarget target = const VideoOutputTarget.applicationView(),
    VideoControllerConfiguration configuration =
        const VideoControllerConfiguration(),
  }) : this._(
         player: player,
         preference: preference,
         policy: policy,
         target: target,
         configuration: configuration,
       );

  /// Test seam: same session with injectable capability querying, position
  /// reading, platform detection and backend. Not for application use.
  /// Diagnostics are notification-only; normal public construction leaves
  /// them null. Option diagnostics require the default-created Android
  /// backend and its private output slot (no backend override). Non-Android
  /// construction remains inert. Callbacks must only copy bounded scalar
  /// facts synchronously; no I/O, Player calls, reentry or mount changes.
  @visibleForTesting
  HdrVideoSession.forTesting({
    Player? player,
    HdrOutputPreference preference = HdrOutputPreference.auto,
    HdrRoutingPolicy policy = HdrRoutingPolicy.defaults,
    VideoOutputTarget target = const VideoOutputTarget.applicationView(),
    VideoControllerConfiguration configuration =
        const VideoControllerConfiguration(),
    Future<HdrCapabilities> Function()? capabilitiesProvider,
    Duration Function()? positionProvider,
    bool? isAndroid,
    HdrOpenBackend<HdrOpenPlan>? backend,
    HdrSessionRoutePlanner? routePlanner,
    Object? nativePlayerIdentity,
    Lock? nativePlayerLock,
    Future<HdrOptionSourceIdentity> Function()? readNativeIdentity,
    Future<String> Function(String)? readNativeProperty,
    HdrNativeDvOutputSnapshot? Function()? readNativeOutput,
    Duration Function()? reviewMonotonicNow,
    Duration reviewBudget = const Duration(seconds: 8),
    void Function(int generation, HdrOpenPlan plan, HdrReviewFacts facts)?
    onNativeDvConsumerValidated,
    void Function(Object, StackTrace)? onNativeDvConsumerCaptureError,
    void Function(HdrBackendCallDiagnostic<HdrOpenPlan>)?
    onBackendCallDiagnostic,
    void Function(HdrNativeDvOptionDiagnostic)? onNativeDvOptionDiagnostic,
  }) : this._(
         player: player,
         preference: preference,
         policy: policy,
         target: target,
         configuration: configuration,
         capabilitiesProvider: capabilitiesProvider,
         positionProvider: positionProvider,
         isAndroid: isAndroid,
         backend: backend,
         routePlanner: routePlanner,
         nativePlayerIdentity: nativePlayerIdentity,
         nativePlayerLock: nativePlayerLock,
         readNativeIdentity: readNativeIdentity,
         readNativeProperty: readNativeProperty,
         readNativeOutput: readNativeOutput,
         reviewMonotonicNow: reviewMonotonicNow,
         reviewBudget: reviewBudget,
         onNativeDvConsumerValidated: onNativeDvConsumerValidated,
         onNativeDvConsumerCaptureError: onNativeDvConsumerCaptureError,
         onBackendCallDiagnostic: onBackendCallDiagnostic,
         onNativeDvOptionDiagnostic: onNativeDvOptionDiagnostic,
       );

  HdrVideoSession._({
    Player? player,
    required HdrOutputPreference preference,
    required HdrRoutingPolicy policy,
    required VideoOutputTarget target,
    required VideoControllerConfiguration configuration,
    Future<HdrCapabilities> Function()? capabilitiesProvider,
    Duration Function()? positionProvider,
    bool? isAndroid,
    HdrOpenBackend<HdrOpenPlan>? backend,
    HdrSessionRoutePlanner? routePlanner,
    Object? nativePlayerIdentity,
    Lock? nativePlayerLock,
    Future<HdrOptionSourceIdentity> Function()? readNativeIdentity,
    Future<String> Function(String)? readNativeProperty,
    HdrNativeDvOutputSnapshot? Function()? readNativeOutput,
    Duration Function()? reviewMonotonicNow,
    Duration reviewBudget = const Duration(seconds: 8),
    void Function(int generation, HdrOpenPlan plan, HdrReviewFacts facts)?
    onNativeDvConsumerValidated,
    void Function(Object, StackTrace)? onNativeDvConsumerCaptureError,
    void Function(HdrBackendCallDiagnostic<HdrOpenPlan>)?
    onBackendCallDiagnostic,
    void Function(HdrNativeDvOptionDiagnostic)? onNativeDvOptionDiagnostic,
  }) {
    _player = player;
    _preference = preference;
    _policy = policy;
    _target = target;
    _configuration = configuration;
    _routePlanner = routePlanner ?? HdrRoutePlanner.plan;
    _onNativeDvConsumerValidated = onNativeDvConsumerValidated;
    _onNativeDvConsumerCaptureError = onNativeDvConsumerCaptureError;
    _testNativePlayerIdentity = nativePlayerIdentity;
    _testNativePlayerLock = nativePlayerLock;
    _testReadNativeIdentity = readNativeIdentity;
    _testReadNativeProperty = readNativeProperty;
    _testReadNativeOutput = readNativeOutput;
    _positionProvider =
        positionProvider ??
        (player == null ? () => Duration.zero : () => player.state.position);
    _isAndroid = isAndroid ?? Platform.isAndroid;
    _capabilitiesProvider = capabilitiesProvider;

    if (!_isAndroid) {
      // Phase 1 non-Android: single-controller passthrough (R2.5).
      if (player != null) {
        _controller.value = VideoController(
          player,
          configuration: configuration,
        );
      }
      _report.value = const HdrOutputReport(
        degradeReason: HdrDegradeReason.unsupportedPlatform,
      );
      return;
    }
    // A supplied backend does not expose its actual option owner. Reject that
    // combination rather than silently claiming real-owner coverage.
    if (backend != null && onNativeDvOptionDiagnostic != null) {
      throw ArgumentError(
        'Option diagnostics require the Session-created backend',
      );
    }
    if (backend == null && player == null) {
      throw ArgumentError('HdrVideoSession requires a Player');
    }
    _slot = HdrOutputSlot<VideoController>(
      initial: null,
      voOf: (controller) async =>
          (await controller.platform.future).configuration.vo ?? '',
      disposeForRebuild: (controller) => controller.disposeForRebuild(),
      create: _createController,
      publish: (controller) => _controller.value = controller,
      waitReady: (controller) async {
        final output = await controller.platform.future;
        await HdrOutputBindTimeout.waitFor(
          output.waitUntilCurrentOutputBound
              .timeout(const Duration(seconds: 10)),
        );
      },
    );
    _backend =
        backend ??
        AndroidHdrBackend(
          player: player!,
          outputSlot: _slot!,
          surfacePixelFormatOverride: _surfaceFormatOverride,
          onNativeDvOptionDiagnostic: onNativeDvOptionDiagnostic,
        );
    _coordinator = HdrOpenCoordinator<HdrOpenRequest, HdrOpenPlan>(
      HdrSessionReviewBackend(
        delegate: _backend!,
        generationOf: _generationOf,
        isCurrent: (serial) => serial == _serial && !_disposed,
        admit: (plan) {
          if (_generationOf(plan) != _serial || _disposed) {
            throw const OpenSuperseded();
          }
          _attemptPolicy.admit(plan.route);
        },
        publishWindow: (window) {
          if (window.generation == _serial && !_disposed) {
            _nativeReviewWindow = window;
          }
        },
        monotonicNow: reviewMonotonicNow,
        budget: reviewBudget,
      ),
      preparer: _prepare,
      review: _review,
      retry: _retry,
      maxRetries: 2,
      onBackendCallDiagnostic: onBackendCallDiagnostic,
      diagnosticSessionGeneration: onBackendCallDiagnostic == null
          ? null
          : _generationOf,
    );
    AndroidVideoController.registerHdrCapabilitiesChangedListener(
      _onNativeCapabilitiesChanged,
    );
    // The enable is a shared channel switch (see
    // [AndroidVideoController.setHdrCapabilitiesChangedEnabled]): Phase 1
    // assumes a single session per process, so turning it on here and off
    // in dispose is the whole lifecycle.
    unawaited(
      AndroidVideoController.setHdrCapabilitiesChangedEnabled(true)
          .catchError((Object _) {}),
    );
  }

  static const String _tag = 'HdrVideoSession';

  Player? _player;
  late HdrOutputPreference _preference;
  late HdrRoutingPolicy _policy;
  late VideoControllerConfiguration _configuration;
  late HdrSessionRoutePlanner _routePlanner;
  void Function(int generation, HdrOpenPlan plan, HdrReviewFacts facts)?
  _onNativeDvConsumerValidated;
  void Function(Object, StackTrace)? _onNativeDvConsumerCaptureError;
  Object? _testNativePlayerIdentity;
  Lock? _testNativePlayerLock;
  Future<HdrOptionSourceIdentity> Function()? _testReadNativeIdentity;
  Future<String> Function(String)? _testReadNativeProperty;
  HdrNativeDvOutputSnapshot? Function()? _testReadNativeOutput;
  final Expando<int> _planGenerations = Expando<int>();
  HdrSessionAttemptPolicy _attemptPolicy = HdrSessionAttemptPolicy();
  HdrSessionReviewWindow? _nativeReviewWindow;
  late bool _isAndroid;
  late Duration Function() _positionProvider;
  Future<HdrCapabilities> Function()? _capabilitiesProvider;
  late VideoOutputTarget _target;
  VideoSourceSpec? _currentSourceSpec;
  int _capabilityQuerySerial = 0;

  Future<HdrCapabilities> _queryCapabilities(
    VideoOutputTarget target,
    VideoSourceSpec? source,
  ) async {
    final injected = _capabilitiesProvider;
    if (injected != null) return injected();
    final result = await VideoRouteCapabilities.query(
      target: target,
      sources: source == null ? const [] : [source],
    );
    return source == null ? result.hdr : result.forHdrSource(source);
  }

  /// Capability snapshot a rebuild must plan against when the trigger already
  /// carries a fresh snapshot (a capability change). Null re-queries through
  /// [_capabilitiesProvider].
  HdrCapabilities? _capabilitiesOverride;

  final ValueNotifier<VideoController?> _controller =
      ValueNotifier<VideoController?>(null);
  final ValueNotifier<HdrOutputReport> _report = ValueNotifier<HdrOutputReport>(
    const HdrOutputReport(),
  );
  final StreamController<HdrOutputEvent> _events =
      StreamController<HdrOutputEvent>.broadcast();
  final HdrSourceIntent<HdrOpenResult<HdrOpenPlan>> _intent =
      HdrSourceIntent<HdrOpenResult<HdrOpenPlan>>();

  HdrOutputSlot<VideoController>? _slot;
  HdrOpenBackend<HdrOpenPlan>? _backend;
  HdrOpenCoordinator<HdrOpenRequest, HdrOpenPlan>? _coordinator;

  int _serial = 0;
  int _transactionSerial = 0;
  bool _disposed = false;
  Media? _currentMedia;
  Duration? _openStart;
  bool _openPlay = true;
  bool _rebuildUsed = false;
  HdrDegradeReason? _degradeReason;

  /// Degrade reason staged by the rebuild trigger that led to this open;
  /// only used when this open itself does not set one.
  HdrDegradeReason? _stagedDegradeReason;
  String? _reviewDiagnostic;
  HdrDecoderObservation? _decoderObservation;
  HdrCapabilities? _lastCapabilities;
  HdrDisposalReport? _lastDisposeReport;

  /// The current video controller, replaced when the route's topology
  /// changes. Null until the first controller is created.
  ValueListenable<VideoController?> get controller => _controller;

  /// The routing report of the current open generation (R4.2). Never
  /// published for a superseded generation.
  ValueListenable<HdrOutputReport> get report => _report;

  /// The session event stream (R3): `RouteApplied`, `Degraded`,
  /// `Reclassified`, `CapabilityChanged` and `Error`.
  Stream<HdrOutputEvent> get events => _events.stream;

  /// The last disposal report, for diagnostics after [dispose].
  HdrDisposalReport? get lastDisposeReport => _lastDisposeReport;

  // ---------------------------------------------------------------------------
  // Open flow (plan 1.4)
  // ---------------------------------------------------------------------------

  /// Opens [media] with HDR orchestration (plan 1.4). One call is one open
  /// generation: candidate degradations and the single review-driven rebuild
  /// stay inside it.
  ///
  /// [hint] pre-configures the route from a caller-known description
  /// (R2.3); the decoder review after the open may correct it with at most
  /// one in-place rebuild at the preserved position.
  ///
  /// Returns normally when a newer [open] superseded this one. Other
  /// failures are published as an [HdrErrorEvent] and rethrown.
  bool _lgExperimentOpenUsed = false;

  Future<void> open(
    Media media, {
    HdrSourceDescriptor? hint,
    VideoSourceSpec? sourceSpec,
    VideoOutputTarget? target,
    bool play = true,
    Duration? start,
  }) => _open(
    media,
    hint: hint,
    sourceSpec: sourceSpec,
    target: target,
    play: play,
    start: start,
  );

  // Only an internal same-source configuration/capability rebuild carries
  // evidence forward. Every explicit public open starts a new source scope.
  Future<void> _open(
    Media media, {
    HdrSourceDescriptor? hint,
    VideoSourceSpec? sourceSpec,
    VideoOutputTarget? target,
    HdrSourceFacts? sourceFacts,
    bool play = true,
    Duration? start,
  }) async {
    if (_configuration.android.lgExperimentOwnerToken != null) {
      if (_lgExperimentOpenUsed) {
        throw StateError('LG experiment Session permits one open attempt only');
      }
      _lgExperimentOpenUsed =
          true; // Atomic before the first await; failure consumes it.
    }
    if (!_isAndroid) {
      final player = _player;
      if (player == null) throw StateError('HdrVideoSession has no Player');
      await player.open(_withStart(media, start), play: play);
      return;
    }
    if (_disposed) throw StateError('HdrVideoSession is disposed');
    final serial = ++_serial;
    _transactionSerial = serial;
    _openStart = start;
    _openPlay = play;
    _rebuildUsed = false;
    _attemptPolicy = HdrSessionAttemptPolicy();
    _nativeReviewWindow = null;
    // A rebuild trigger (configuration change, capability loss) stages its
    // reason before calling open(); carry it through so the rebuilt
    // generation's report states why the route degraded (R4.2). A reason
    // set during this open itself takes precedence below.
    _stagedDegradeReason = _degradeReason;
    _degradeReason = null;
    _reviewDiagnostic = null;
    _decoderObservation = null;
    final intentSerial = _intent.begin();
    // Consume the override before yielding; another open must not inherit it.
    final capabilitiesOverride = _capabilitiesOverride;
    _capabilitiesOverride = null;
    _target = target ?? _target;
    final request = HdrOpenRequest(
      media,
      hint,
      target: _target,
      sourceSpec: sourceSpec,
      capabilitiesOverride: capabilitiesOverride,
      sourceFacts: sourceFacts,
    );
    try {
      final result = await _coordinator!.openSource(
        request,
        start: start,
        play: play,
      );
      _intent.succeed(intentSerial, media.uri, result);
      if (serial == _serial && !_disposed) {
        _currentMedia = media;
        _currentSourceSpec = sourceSpec;
        final observation = _backend!.observe();
        final plan = result.plan;
        final report = HdrOutputReport(
          generation: serial,
          source: plan.source,
          sourceOrigin: plan.sourceOrigin,
          sourceFacts: plan.sourceFacts,
          prediction: plan.prediction,
          actual: plan.route,
          dataSpaceRequested: observation.dataSpaceRequested,
          dataSpacePath: observation.dataSpacePath,
          dataSpaceReadback: observation.dataSpaceReadback,
          hwdecCurrent: observation.hwdecCurrent,
          decoderObservation: _decoderObservation,
          verified: true,
          degradeReason: _degradeReason ?? _stagedDegradeReason,
          diagnostic: _reviewDiagnostic,
        );
        _report.value = report;
        // `HDR decision:` layer, applied phase (R4.3): the same decision
        // after verification, with the dataspace outcome and hwdec observed.
        HdrOutputDiagnostics.decision(
          generation: serial,
          phase: 'applied',
          origin: plan.sourceOrigin,
          source: plan.source,
          prediction: plan.prediction,
          actual: plan.route,
          hwdecCurrent: report.hwdecCurrent,
          dataSpaceRequested: report.dataSpaceRequested,
          dataSpacePath: report.dataSpacePath,
          dataSpaceReadback: report.dataSpaceReadback,
          verified: report.verified,
          degradeReason: report.degradeReason,
        );
        _emit(HdrRouteAppliedEvent(serial, route: plan.route, report: report));
      }
    } on OpenSuperseded {
      _intent.fail(intentSerial);
      // A newer open owns the session now; nothing is published for this
      // generation and the transaction has already rolled the backend back.
      return;
    } on HdrPlaybackBlocked catch (error) {
      _intent.fail(intentSerial);
      if (serial == _serial && !_disposed) {
        _report.value = HdrOutputReport(
          generation: serial,
          source: error.sourceFacts?.source ?? hint,
          sourceOrigin: error.sourceFacts != null
              ? HdrReportSource.decoder
              : hint == null ? null : HdrReportSource.hint,
          sourceFacts: error.sourceFacts,
          verified: false,
          degradeReason: error.reason,
          error: error,
          diagnostic: _reviewDiagnostic,
        );
        _emit(
          HdrErrorEvent(
            serial,
            reason: error.reason,
            error: error,
            diagnostic: 'playback blocked: ${error.reason.name}',
          ),
        );
      }
      return;
    } catch (error, stack) {
      _intent.fail(intentSerial);
      if (serial == _serial && !_disposed) {
        _report.value = HdrOutputReport(
          generation: serial,
          verified: false,
          degradeReason: _degradeReason ?? _stagedDegradeReason,
          error: error,
          diagnostic: error.toString(),
        );
        _emit(
          HdrErrorEvent(serial, error: error, diagnostic: error.toString()),
        );
      }
      Error.throwWithStackTrace(error, stack);
    }
  }

  /// Pre-queue plan production: capability snapshot + plan (plan 1.4
  /// step 2). Runs outside the side-effect queue so a slow query cannot
  /// delay or open after a newer request.
  Future<HdrOpenPlan> _prepare(
    HdrOpenRequest request,
    bool Function() cancelled,
  ) async {
    final capabilities =
        request.capabilitiesOverride ??
        await _queryCapabilities(request.target, request.sourceSpec);
    if (cancelled()) throw const OpenSuperseded();
    final hint = request.hint;
    final sourceFacts = request.sourceFacts ?? HdrSourceFacts.fromHint(hint);
    final source = sourceFacts.source;
    final prediction = _routePlanner(
      source: source,
      capabilities: capabilities,
      policy: _policy,
      preference: _preference,
      excluded: _attemptPolicy.exclusions(const {}),
    );
    if (!prediction.playable) {
      // P5 without the dovi rescale pipeline: never output a wrongly
      // colored picture (R3.3).
      throw HdrPlaybackBlocked(
        prediction.selected.skipReason ??
            HdrDegradeReason.p5PipelineUnavailable,
      );
    }
    _lastCapabilities = capabilities;
    final plan = HdrOpenPlan(
      media: request.media,
      source: source,
      sourceOrigin: hint == null ? null : HdrReportSource.hint,
      sourceFacts: sourceFacts,
      capabilities: capabilities,
      prediction: prediction,
      route: prediction.selected.route!,
    );
    _planGenerations[plan] = _serial;
    _publish(
      HdrOutputReport(
        generation: _transactionSerial,
        source: source,
        sourceOrigin: plan.sourceOrigin,
        sourceFacts: plan.sourceFacts,
        prediction: prediction,
        verified: false,
      ),
    );
    // `HDR decision:` layer, plan phase (R4.3): selected strategy, full
    // candidate list with skip reasons, and the open generation.
    HdrOutputDiagnostics.decision(
      generation: _transactionSerial,
      phase: 'plan',
      origin: plan.sourceOrigin,
      source: plan.source,
      prediction: prediction,
    );
    return plan;
  }

  /// Failure-driven plan replacement inside the open generation (plan 1.4
  /// step 5): map the failure to a dependency stage, re-plan past the failed
  /// candidate, and allow at most one further HDR candidate before the
  /// tone-map/SDR fallback.
  Future<HdrOpenPlan?> _retry(HdrOpenPlan failed, Object error) async {
    final generation = _generationOf(failed);
    if (generation != _serial || _disposed) return null;
    if (error is HdrPlaybackBlocked ||
        error is HdrDecoderReviewFailure ||
        nativeDvFailureMustAbort(error)) {
      // Ownership/source/debt failures retain their original typed cause.
      // Coordinator cleanup is still protected by the backend's owner gates.
      return null;
    }
    // A timeout in open/review/configuration does not identify a failed
    // decoder or presenter. Stop and clean up rather than guessing a route.
    if (error is TimeoutException && error is! HdrOutputBindTimeout) {
      return null;
    }
    if (_preference == HdrOutputPreference.off) return null;
    final nativeFailure =
        failed.route.strategy == HdrStrategy.nativeDolbyVision;
    if (nativeFailure) _attemptPolicy.excludeNativeDv();
    final excluded = _attemptPolicy.exclusions(
      failed.excluded,
      nextAttempt: true,
    );
    HdrDegradeReason reason;
    final diagnostic = error.toString();
    if (nativeFailure || error is HdrSessionRouteBudgetFailure) {
      reason = HdrDegradeReason.nativeDvUnavailable;
    } else if (error is HdrDataSpaceApplyException) {
      reason = error.reason;
      excluded[failed.route.surfaceTransfer == 'hlg'
              ? HdrRouteDependency.dataspaceHlg
              : HdrRouteDependency.dataspacePq] =
          reason;
    } else if (error is HdrOutputBindTimeout) {
      reason = HdrDegradeReason.outputBindTimeout;
      if (failed.route.topology == HdrTopology.platformView) {
        excluded[HdrRouteDependency.topologyPlatformView] = reason;
      }
    } else {
      reason = HdrDegradeReason.unsupportedStrategy;
    }
    final cls = HdrSourceClass.of(failed.source);
    final full = _policy.preferencesFor(cls);
    final index = full.indexOf(failed.route.strategy);
    final remaining = index >= 0 ? full.sublist(index + 1) : full;
    final slicedPolicy = HdrRoutingPolicy(
      preferences: <HdrSourceClass, List<HdrStrategy>>{cls: remaining},
      allowExperimental: _policy.allowExperimental,
    );
    final prediction = _planNextAttempt(
      source: failed.source,
      capabilities: failed.capabilities,
      policy: slicedPolicy,
      excluded: excluded,
    );
    if (!prediction.playable) return null;
    final nextRoute = prediction.selected.route!;
    if (nextRoute == failed.route) return null;
    _degradeReason = reason;
    _emit(
      HdrDegradedEvent(
        generation,
        reason: reason,
        diagnostic: diagnostic,
        from: failed.route,
        to: nextRoute,
      ),
    );
    final next = failed.copyWith(
      prediction: prediction,
      route: nextRoute,
      excluded: excluded,
    );
    _planGenerations[next] = generation;
    return next;
  }

  int _generationOf(HdrOpenPlan plan) =>
      _planGenerations[plan] ?? (throw const OpenSuperseded());

  HdrRoutePrediction _planNextAttempt({
    required HdrSourceDescriptor source,
    required HdrCapabilities capabilities,
    required HdrRoutingPolicy policy,
    required Map<String, HdrDegradeReason> excluded,
  }) {
    final nextExcluded = _attemptPolicy.exclusions(excluded, nextAttempt: true);
    var prediction = _routePlanner(
      source: source,
      capabilities: capabilities,
      policy: policy,
      preference: _preference,
      excluded: nextExcluded,
    );
    if (prediction.playable &&
        HdrSessionAttemptPolicy.isHdr(prediction.selected.route!) &&
        _attemptPolicy.hdrAttempts >= 2) {
      prediction = _routePlanner(
        source: source,
        capabilities: capabilities,
        policy: policy,
        preference: HdrOutputPreference.off,
        excluded: nextExcluded,
      );
    }
    return prediction;
  }

  Future<void> _consumeNativeDvEvidence(
    HdrOpenPlan plan,
    HdrReviewFacts facts,
  ) async {
    final generation = _generationOf(plan);
    final native = _player?.platform;
    final identity = _testNativePlayerIdentity ?? native;
    final lock =
        _testNativePlayerLock ?? (native is NativePlayer ? native.lock : null);
    final window = _nativeReviewWindow;
    if (window == null || identity == null || lock == null) {
      throw const HdrNativeDvReviewFailure(
        HdrNativeDvReviewFailureKind.configuration,
      );
    }
    Future<HdrOptionSourceIdentity> readIdentity() async {
      if (_testReadNativeIdentity != null) return _testReadNativeIdentity!();
      if (native is! NativePlayer) {
        throw const HdrNativeDvReviewFailure(
          HdrNativeDvReviewFailureKind.sourceIdentity,
        );
      }
      final epoch = native.fileLoadedEpoch;
      final path = await window.bounded(() => native.getProperty('path'));
      final entry = await window.bounded(
        () => native.getProperty('playlist/0/id'),
      );
      if (await window.bounded(() => native.getProperty('path')) != path ||
          await window.bounded(() => native.getProperty('playlist/0/id')) !=
              entry ||
          native.fileLoadedEpoch != epoch) {
        throw const HdrNativeDvReviewFailure(
          HdrNativeDvReviewFailureKind.sourceIdentity,
        );
      }
      return HdrOptionSourceIdentity(
        player: native,
        path: path,
        playlistEntryId: entry,
        fileLoadedEpoch: epoch,
      );
    }

    HdrNativeDvOutputSnapshot? readOutput() {
      if (_testReadNativeOutput != null) return _testReadNativeOutput!();
      final controller = _controller.value?.notifier.value;
      if (controller is! AndroidVideoController ||
          !identical(controller.player.platform, identity)) {
        return null;
      }
      final output = controller.currentBoundOutputIdentity;
      return output == null
          ? null
          : HdrNativeDvOutputSnapshot(controller, output);
    }

    await consumeNativeDvSessionEvidence(
      window: window,
      generation: generation,
      plan: plan,
      facts: facts,
      expectedPlayer: identity,
      lock: lock,
      readIdentity: readIdentity,
      readProperty:
          _testReadNativeProperty ??
          ((name) => (native as NativePlayer).getProperty(name)),
      readOutput: readOutput,
      isCurrent: () => generation == _serial && !_disposed,
    );
  }

  /// The review decision (plan 1.4 step 8): classify the decoder facts,
  /// re-plan, and reopen in place at most once when the route changed or
  /// `hwdec-current` mismatches. A second disagreement blocks playback;
  /// a playable prediction cannot verify the output that actually opened.
  Future<HdrReviewDecision<HdrOpenPlan>> _review(
    HdrOpenPlan plan,
    HdrReviewFacts facts,
  ) async {
    final generation = _generationOf(plan);
    if (generation != _serial || _disposed) {
      return const HdrReviewDecision<HdrOpenPlan>.accept();
    }
    if (plan.route.strategy == HdrStrategy.nativeDolbyVision) {
      // Missing/contradictory native evidence throws before either ordinary
      // mismatch branch, including the second-disagreement blocking path.
      // Keep this transaction's window even if a diagnostic callback starts
      // another open. Observation never grants a new acceptance deadline.
      final reviewWindow = _nativeReviewWindow;
      await _consumeNativeDvEvidence(plan, facts);
      // The consumer and its caller each cross a Future completion boundary.
      // Never classify or mutate policy belonging to a successor generation.
      if (generation != _serial || _disposed) {
        throw const OpenSuperseded();
      }
      final observer = _onNativeDvConsumerValidated;
      if (observer != null) {
        // Passive forTesting capture of the exact consumed immutable proof.
        // This is consumer validation, before classification / routeApplied;
        // callbacks must only copy evidence and schedule external I/O later.
        try {
          observer(generation, plan, facts);
        } catch (error, stack) {
          try {
            _onNativeDvConsumerCaptureError?.call(error, stack);
          } catch (_) {
            // Recorder failures must not select a different native route.
          }
        }
        // A callback may synchronously open/dispose or spend the original
        // budget. Reject before touching a successor's policy or planning.
        if (generation != _serial || _disposed) {
          throw const OpenSuperseded();
        }
        reviewWindow!.remaining();
      }
    }
    if (plan.route.strategy != HdrStrategy.nativeDolbyVision) {
      validateDecoderObservation(plan.route, facts);
      _decoderObservation = facts.decoderObservation;
    } else {
      // A native review describes another accepted attempt. Do not attach an
      // ordinary predecessor's entry/decoder/frame sample to this report.
      _decoderObservation = null;
    }
    // Source evidence survives this logical open's retries. Decoder output
    // is stored separately and cannot erase original DV/HDR metadata merely
    // because the new decoder omitted it. Native DV may transform frame colors;
    // its output tags are never used to infer the source compatibility family.
    final sourceFacts =
        (plan.sourceFacts ?? HdrSourceFacts.fromHint(plan.source)).observe(
          videoParams: facts.videoParams,
          dolbyVisionProfile: facts.dolbyVisionProfile,
          codec: facts.codec,
          dvCompatibilityId: facts.dvCompatibilityId,
          dvElPresent: facts.dvElPresent,
          hdrVivid: facts.hdrVivid,
          inferSourceColorFromDecoder:
              plan.route.strategy != HdrStrategy.nativeDolbyVision,
        );
    final descriptor = sourceFacts.source;
    HdrOutputDiagnostics.classify(
      descriptor: descriptor,
      origin: sourceFacts.retainsHint ? 'mixed' : 'facts',
    );
    if (sourceFacts.hasConflict) {
      throw HdrPlaybackBlocked(
        HdrDegradeReason.sourceMetadataUnknown,
        sourceFacts: sourceFacts,
      );
    }
    final reclassified = descriptor != plan.source;
    // A previously admitted HDR route may still be reviewed at the limit.
    // A non-HDR route selected after exhausting the two HDR attempts must
    // keep that effective SDR constraint instead of predicting a new upgrade.
    final reviewPreference = !HdrSessionAttemptPolicy.isHdr(plan.route) &&
            _attemptPolicy.hdrAttempts >= 2
        ? HdrOutputPreference.off
        : _preference;
    final prediction = _routePlanner(
      source: descriptor,
      capabilities: plan.capabilities,
      policy: _policy,
      preference: reviewPreference,
      excluded: _attemptPolicy.exclusions(plan.excluded),
    );
    if (!prediction.playable) {
      // The decoder reported a source whose routes all need the P5
      // pipeline (e.g. a mislabeled hint): stop before wrong colors (R3.3).
      throw HdrPlaybackBlocked(
        prediction.selected.skipReason ??
            HdrDegradeReason.p5PipelineUnavailable,
        sourceFacts: sourceFacts,
      );
    }
    final routeChanged = prediction.selected.route != plan.route;
    final hwdecMismatch = facts.hwdecCurrent != plan.route.hwdec;

    var excludedForRebuild = _attemptPolicy.exclusions(plan.excluded);
    var replanned = prediction;
    if (hwdecMismatch) {
      final String? dependency = _hwdecDependency(plan.route.hwdec);
      if (dependency != null) {
        excludedForRebuild = <String, HdrDegradeReason>{
          ...excludedForRebuild,
          dependency: HdrDegradeReason.hwdecMismatch,
        };
      }
      replanned = _routePlanner(
        source: descriptor,
        capabilities: plan.capabilities,
        policy: _policy,
        preference: reviewPreference,
        excluded: excludedForRebuild,
      );
      if (!replanned.playable) {
        throw HdrPlaybackBlocked(
          replanned.selected.skipReason ??
              HdrDegradeReason.p5PipelineUnavailable,
          sourceFacts: sourceFacts,
        );
      }
    }

    if (!routeChanged && !hwdecMismatch) {
      if (reclassified) {
        _emit(
          HdrReclassifiedEvent(
            _transactionSerial,
            previous: plan.source,
            current: descriptor,
            rebuilt: false,
          ),
        );
      }
      return HdrReviewDecision<HdrOpenPlan>.accept(
        nextPlan: plan.copyWith(
          source: descriptor,
          sourceOrigin: reclassified ? HdrReportSource.decoder : null,
          sourceFacts: sourceFacts,
          prediction: prediction,
        ),
      );
    }

    if (_rebuildUsed) {
      // The current output still disagrees with its required route or decoder.
      // Stop within the existing budget; do not report a hypothetical candidate
      // as an accepted output, nor open an unbounded third attempt.
      _reviewDiagnostic = 'decoder review mismatch persisted after rebuild: '
          'route=${plan.route.strategy.name}, hwdec=${facts.hwdecCurrent}, '
          'profile=${facts.dolbyVisionProfile}, '
          'gamma=${facts.videoParams?.gamma}';
      throw HdrPlaybackBlocked(
        hwdecMismatch
            ? HdrDegradeReason.hwdecMismatch
            : HdrDegradeReason.routeReviewMismatch,
        sourceFacts: sourceFacts,
      );
    }

    _rebuildUsed = true;
    // A review reopen is an actual new attempt too. Persist native-once
    // exclusions and enforce the same two-HDR budget as failure retries.
    excludedForRebuild = _attemptPolicy.exclusions(
      excludedForRebuild,
      nextAttempt: true,
    );
    replanned = _planNextAttempt(
      source: descriptor,
      capabilities: plan.capabilities,
      policy: _policy,
      excluded: excludedForRebuild,
    );
    if (!replanned.playable) {
      throw HdrPlaybackBlocked(
        replanned.selected.skipReason ?? HdrDegradeReason.p5PipelineUnavailable,
        sourceFacts: sourceFacts,
      );
    }
    if (hwdecMismatch) {
      _degradeReason = HdrDegradeReason.hwdecMismatch;
      _emit(
        HdrDegradedEvent(
          _transactionSerial,
          reason: HdrDegradeReason.hwdecMismatch,
          diagnostic:
              'hwdec-current=${facts.hwdecCurrent} '
              'expected=${plan.route.hwdec}',
          from: plan.route,
          to: replanned.selected.route,
        ),
      );
    }
    if (reclassified) {
      _emit(
        HdrReclassifiedEvent(
          _transactionSerial,
          previous: plan.source,
          current: descriptor,
          rebuilt: true,
        ),
      );
    }
    final rebuildPlan = plan.copyWith(
      source: descriptor,
      sourceOrigin: reclassified ? HdrReportSource.decoder : plan.sourceOrigin,
      sourceFacts: sourceFacts,
      prediction: replanned,
      route: replanned.selected.route!,
      excluded: excludedForRebuild,
    );
    _planGenerations[rebuildPlan] = generation;
    return HdrReviewDecision<HdrOpenPlan>.reopen(
      _rebuildPosition(),
      rebuildPlan,
    );
  }

  /// Maps the selected route's actual decoder mode to the planner dependency
  /// that failed. Copy-mode routes are independent from zero-copy MediaCodec
  /// routes and must be excluded separately.
  static String? _hwdecDependency(String hwdec) {
    switch (hwdec) {
      case 'mediacodec':
        return HdrRouteDependency.hwdecMediacodec;
      case 'mediacodec-copy':
        return HdrRouteDependency.hwdecMediacodecCopy;
      case 'surfacetexture':
        return HdrRouteDependency.hwdecSurfaceTexture;
      default:
        return null;
    }
  }

  /// The position an in-place rebuild reopens at: the playback position,
  /// or the requested start when nothing has played yet.
  Duration _rebuildPosition() {
    final position = _positionProvider();
    final start = _openStart;
    if (position <= Duration.zero && start != null) return start;
    return position;
  }

  // ---------------------------------------------------------------------------
  // Playback-time configuration and capability changes
  // ---------------------------------------------------------------------------

  /// Changes the output preference during playback (R2.2): re-plans with
  /// the current description and rebuilds at the current position only
  /// when the selected route changed.
  Future<void> setPreference(HdrOutputPreference preference) async {
    if (_configuration.android.lgExperimentOwnerToken != null) {
      throw StateError('LG single-open experiment rejects preference controls');
    }
    if (_preference == preference) return;
    _preference = preference;
    await _replanAfterConfigurationChange(
      reason: preference == HdrOutputPreference.off
          ? HdrDegradeReason.preferenceOff
          : null,
    );
  }

  /// Changes the routing policy during playback (R2.2), same rebuild rule
  /// as [setPreference].
  Future<void> setPolicy(HdrRoutingPolicy policy) async {
    if (_configuration.android.lgExperimentOwnerToken != null) {
      throw StateError('LG single-open experiment rejects policy controls');
    }
    _policy = policy;
    await _replanAfterConfigurationChange();
  }

  Future<void> _replanAfterConfigurationChange({
    HdrDegradeReason? reason,
  }) async {
    if (!_isAndroid || _disposed) return;
    final current = _report.value;
    final descriptor = current.source;
    final actual = current.actual;
    final media = _currentMedia;
    final capabilities = _lastCapabilities;
    if (descriptor == null || actual == null || media == null) return;
    if (capabilities == null) return;
    if (_configuration.android.lgExperimentOwnerToken != null) {
      throw StateError(
        'LG single-open experiment rejects automatic replanning',
      );
    }
    final prediction = HdrRoutePlanner.plan(
      source: descriptor,
      capabilities: capabilities,
      policy: _policy,
      preference: _preference,
    );
    if (!prediction.playable) {
      _emit(
        HdrErrorEvent(
          _serial,
          reason: HdrDegradeReason.p5PipelineUnavailable,
          diagnostic: 're-planned route is not playable',
        ),
      );
      return;
    }
    final next = prediction.selected.route!;
    if (next == actual) return; // Route unchanged: no rebuild.
    if (reason != null) {
      _degradeReason = reason;
      _emit(
        HdrDegradedEvent(
          _serial,
          reason: reason,
          diagnostic: 'configuration changed; rebuilding at current position',
          from: actual,
          to: next,
        ),
      );
    }
    await _open(
      media,
      hint: descriptor,
      sourceFacts: current.sourceFacts,
      sourceSpec: _currentSourceSpec,
      play: _openPlay,
      start: _positionProvider(),
    );
  }

  /// Consumes a capability snapshot change (R1.6/R3.4): always publishes
  /// [HdrCapabilityChangedEvent]; rebuilds at the current position only
  /// when the currently applied route became infeasible. Recovery never
  /// upgrades automatically.
  @visibleForTesting
  Future<void> handleCapabilitiesChanged(HdrCapabilities capabilities) async {
    if (_disposed || !_isAndroid) return;
    _emit(HdrCapabilityChangedEvent(_serial, capabilities));
    final current = _report.value;
    final descriptor = current.source;
    final actual = current.actual;
    final media = _currentMedia;
    if (descriptor == null || actual == null || media == null) {
      _lastCapabilities = capabilities;
      return;
    }
    if (_configuration.android.lgExperimentOwnerToken != null) {
      throw StateError(
        'LG single-open experiment rejects automatic replanning',
      );
    }
    final prediction = HdrRoutePlanner.plan(
      source: descriptor,
      capabilities: capabilities,
      policy: _policy,
      preference: _preference,
    );
    _lastCapabilities = capabilities;
    if (!prediction.playable) {
      _emit(
        HdrErrorEvent(
          _serial,
          reason: HdrDegradeReason.p5PipelineUnavailable,
          diagnostic: 'capability change made the source unplayable',
        ),
      );
      return;
    }
    HdrCandidate? currentCandidate;
    for (final candidate in prediction.candidates) {
      if (candidate.strategy == actual.strategy) {
        currentCandidate = candidate;
        break;
      }
    }
    final stillFeasible =
        currentCandidate != null &&
        currentCandidate.feasible &&
        currentCandidate.route == actual;
    if (stillFeasible) return; // E.g. capability recovery: event only (R3.4).
    _degradeReason = HdrDegradeReason.capabilityLost;
    _emit(
      HdrDegradedEvent(
        _serial,
        reason: HdrDegradeReason.capabilityLost,
        diagnostic: 'the applied route is no longer feasible',
        from: actual,
        to: prediction.selected.route,
      ),
    );
    // The rebuild must plan against the snapshot that triggered it, not
    // against a fresh query that may still return the stale state.
    _capabilitiesOverride = capabilities;
    try {
      await _open(
        media,
        hint: descriptor,
        sourceFacts: current.sourceFacts,
        sourceSpec: _currentSourceSpec,
        play: _openPlay,
        start: _positionProvider(),
      );
    } finally {
      if (identical(_capabilitiesOverride, capabilities)) {
        _capabilitiesOverride = null;
      }
    }
  }

  void _onNativeCapabilitiesChanged(Map<Object?, Object?> snapshot) {
    // Legacy notifications carry default-display data. Use them only as
    // invalidation; query THIS Session's target and source instead.
    unawaited(refreshCapabilities());
  }

  /// Re-query the attached output target without a Player-based lookup.
  Future<void> refreshCapabilities() async {
    if (_disposed || !_isAndroid) return;
    final querySerial = ++_capabilityQuerySerial;
    final generation = _serial;
    final source = _currentSourceSpec;
    try {
      final capabilities = await _queryCapabilities(_target, source);
      if (_disposed ||
          generation != _serial ||
          querySerial != _capabilityQuerySerial) {
        return;
      }
      await handleCapabilitiesChanged(capabilities);
    } catch (error) {
      if (_disposed ||
          generation != _serial ||
          querySerial != _capabilityQuerySerial) {
        return;
      }
      _emit(
        HdrErrorEvent(
          generation,
          reason: HdrDegradeReason.noDisplayCapabilityReport,
          error: error,
          diagnostic: 'target capability refresh failed',
        ),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Controller creation and lifecycle
  // ---------------------------------------------------------------------------

  /// Uses the same immutable request that the backend handed to the slot.
  VideoController _createController(HdrOutputContract contract) {
    final player = _player;
    if (player == null) throw StateError('HdrVideoSession has no Player');
    return VideoController(
      player,
      configuration: contract.controllerConfiguration(_configuration),
    );
  }

  Media _withStart(Media media, Duration? start) {
    if (start == null) return media;
    return Media(
      media.uri,
      start: start,
      end: media.end,
      extras: media.extras,
      httpHeaders: media.httpHeaders,
    );
  }

  void _publish(HdrOutputReport report) {
    if (_disposed || report.generation != _serial) return;
    _report.value = report;
  }

  void _emit(HdrOutputEvent event) {
    if (_disposed) return;
    // Open-flow events carry their transaction's generation; a stale
    // transaction must not publish anything (plan 1.4 step 1).
    if (event.generation != _serial) return;
    // `HDR degrade:` / `HDR recover:` layers (R4.3): hooked on the single
    // event funnel so every degradation site and the capability-change
    // recovery log identically, and only for live generations.
    if (HdrOutputDiagnostics.enabled) {
      if (event is HdrDegradedEvent) {
        HdrOutputDiagnostics.degrade(
          generation: event.generation,
          reason: event.reason,
          from: event.from,
          to: event.to,
          diagnostic: event.diagnostic,
        );
      } else if (event is HdrCapabilityChangedEvent) {
        HdrOutputDiagnostics.recover(
          generation: event.generation,
          capabilities: event.capabilities,
        );
      }
    }
    _events.add(event);
  }

  /// Closes the session: invalidates the current generation, stops media,
  /// restores owned mpv properties, disposes controllers and closes the
  /// event stream. The caller's [Player] is not disposed.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _serial++;
    if (_isAndroid) {
      AndroidVideoController.unregisterHdrCapabilitiesChangedListener(
        _onNativeCapabilitiesChanged,
      );
      unawaited(
        AndroidVideoController.setHdrCapabilitiesChangedEnabled(false)
            .catchError((Object _) {}),
      );
    }
    _lastDisposeReport = await disposeHdrResources(
      disposeCoordinator: _coordinator == null
          ? null
          : () => _coordinator!.dispose(),
    );
    try {
      await _slot?.dispose();
    } catch (error) {
      debugPrint('$_tag: slot dispose failed: $error');
    }
    final backend = _backend;
    if (backend is AndroidHdrBackend) {
      try {
        await backend.dispose();
      } catch (error) {
        debugPrint('$_tag: backend dispose failed: $error');
      }
    }
    await _events.close();
    _controller.dispose();
    _report.dispose();
  }
}
