// ignore_for_file: implementation_imports

import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:media_kit_video/media_kit_video_controls/media_kit_video_controls.dart'
    as video_controls;
import 'package:path_provider/path_provider.dart' as path_provider;
import 'package:media_kit_video/src/hdr/hdr_open_coordinator.dart';
import 'package:media_kit_video/src/hdr/hdr_native_dv_option_owner.dart';
import 'package:media_kit_video/src/hdr/hdr_native_dv_review_evidence.dart';

import '../common/android_service_probe.dart';
import '../common/android_hdr_convert_experiment.dart';
import '../common/android_surface_texture_experiment.dart';
import '../common/sources/android_hdr_player_backend.dart'
    show AndroidSurfaceTextureDiag, AndroidSurfaceTexturePoc;
import '../common/android_native_dv_release_diagnostic.dart';
import '../common/android_native_dv_session_diagnostic.dart';
import '../common/android_native_dv_session_lifecycle.dart';
import '../common/android_native_dv_session_negative.dart';
import '../common/android_playback_performance_diagnostic.dart';
import '../common/android_native_dv_session_foreign_ownership.dart';
import '../common/android_hdr_session_diagnostic.dart';
import 'package:media_kit_video/src/video_controller/android_video_controller/android_video_controller.dart';
import '../common/globals.dart';
import '../common/sources/sources.dart';
import '../common/widgets.dart';

/// The experiment mounts only Session-owned output, never a default Texture.
class AndroidLgSingleOwnerVideo extends StatelessWidget {
  const AndroidLgSingleOwnerVideo({super.key, required this.session});

  final HdrVideoSession? session;

  @override
  Widget build(BuildContext context) {
    final currentSession = session;
    // POC define on only: mount the output at the frozen contract's 2:1
    // geometry from the first frame, so the platform view surface is created
    // directly at its final 1440x720 size and the mid-open resize (video
    // params resetting the decoder) never happens. Define off keeps the
    // existing adaptive placeholder/session layout untouched.
    if (AndroidSurfaceTexturePoc.enabled) {
      debugPrint('MKSURF-POC: fixed 2:1 single-owner output layout');
      return Center(
        child: AspectRatio(
          aspectRatio: 2.0,
          child: currentSession == null
              ? const HdrVideoPlaceholder()
              : HdrVideo(
                  key: const ValueKey('lg-single-owner-video'),
                  session: currentSession,
                  controls: null,
                ),
        ),
      );
    }
    return currentSession == null
        ? const HdrVideoPlaceholder()
        : HdrVideo(
            key: const ValueKey('lg-single-owner-video'),
            session: currentSession,
            controls: null,
          );
  }
}

String? validateAndroidNativeDvN4PageAdmission({
  required bool android,
  required bool hdrTransaction,
  required bool sessionDiagnostic,
  required bool negativeN1,
  required bool performance,
  required bool lifecycle,
  required bool hdr10,
}) {
  if (!android || !hdrTransaction || !sessionDiagnostic) {
    return 'N4 requires Android HDR_TRANSACTION and the fixed-P5 Session diagnostic';
  }
  if (negativeN1 || performance || lifecycle || hdr10) {
    return 'N4 excludes N1, performance, lifecycle, and HDR10 modes';
  }
  return null;
}

/// N4 keeps its actions reachable independently of diagnostic text length.
/// Callers retain all admission and exit behavior; this widget only lays out
/// the video, scrollable diagnostics, and fixed action area.
class AndroidNativeDvN4PageLayout extends StatelessWidget {
  const AndroidNativeDvN4PageLayout({
    super.key,
    required this.video,
    required this.diagnostics,
    required this.onRun,
    required this.onClose,
  });

  final Widget video;
  final Widget diagnostics;
  final VoidCallback? onRun;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Column(children: [
          Expanded(flex: 3, child: video),
          Expanded(
            flex: 2,
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: diagnostics,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Expanded(
                child: Semantics(
                  label: 'native-dv-n4:run-once',
                  button: true,
                  child: OutlinedButton(
                    onPressed: onRun,
                    child: const Text('Run N4 once'),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Semantics(
                  label: 'native-dv-n4:close-and-exit',
                  button: true,
                  child: OutlinedButton(
                    onPressed: onClose,
                    child: const Text('Close & exit'),
                  ),
                ),
              ),
            ]),
          ),
        ]),
      );
}

/// The page transport binds actual callbacks and invokes only same-Player raw
/// open. It delegates all identity admission and disposal evidence to the
/// frozen experiment helper.
class AndroidNativeDvN4PageTransport {
  AndroidNativeDvN4PageTransport({
    required this.player,
    required this.source,
    required this.currentSource,
    required this.run,
  });

  final Player player;
  final String source;
  final String Function() currentSource;
  final AndroidNativeDvSessionForeignOwnershipRun run;
  HdrVideoSession? _session;
  String? _sessionInstanceId;
  int? _consumerGeneration;
  HdrNativeDvReviewEvidence? _acceptedEvidence;
  VideoController? _acceptedWrapper;
  bool _routeApplied = false;
  bool _closing = false;
  Future<AndroidNativeDvForeignOwnershipResult>? _execution;

  bool get ready {
    final session = _session;
    final evidence = _acceptedEvidence;
    return !_closing &&
        session != null &&
        evidence != null &&
        _consumerGeneration != null &&
        _routeApplied &&
        currentSource() == source &&
        player.fileLoadedEpoch == evidence.source.fileLoadedEpoch &&
        session.report.value.generation == _consumerGeneration &&
        session.report.value.verified &&
        session.report.value.actual?.strategy ==
            HdrStrategy.nativeDolbyVision &&
        identical(evidence.source.player, player) &&
        evidence.source.path == source &&
        evidence.loaded.epoch == evidence.source.fileLoadedEpoch &&
        androidNativeDvN4ControllerMatches(
          player: player,
          currentWrapper: session.controller.value,
          acceptedWrapper: _acceptedWrapper,
          evidence: evidence,
        );
  }

  Future<AndroidNativeDvForeignOwnershipResult>? get execution => _execution;
  HdrVideoSession? get session => _session;
  String? get sessionInstanceId => _sessionInstanceId;

  void bindSession(HdrVideoSession session, String sessionInstanceId) {
    if (_closing || _session != null || sessionInstanceId.isEmpty) {
      throw StateError('N4 transport Session binding is repeated or closed');
    }
    _session = session;
    _sessionInstanceId = sessionInstanceId;
    run.bindSession(session, sessionInstanceId);
  }

  void onConsumerValidated({
    required HdrVideoSession callbackSession,
    required String sessionInstanceId,
    required int generation,
    required HdrOpenPlan plan,
    required HdrReviewFacts facts,
  }) {
    _consumerGeneration = null;
    _acceptedEvidence = null;
    _acceptedWrapper = null;
    _routeApplied = false;
    run.onConsumerValidated(
      callbackSession: callbackSession,
      sessionInstanceId: sessionInstanceId,
      generation: generation,
      plan: plan,
      facts: facts,
    );
    final evidence = facts.nativeDvEvidence;
    final wrapper = callbackSession.controller.value;
    if (!_closing &&
        identical(callbackSession, _session) &&
        sessionInstanceId == _sessionInstanceId &&
        evidence != null &&
        identical(evidence.source.player, player) &&
        evidence.source.path == source &&
        evidence.loaded.epoch == evidence.source.fileLoadedEpoch &&
        evidence.loaded.playlistEntryId.toString() ==
            evidence.source.playlistEntryId &&
        plan.route.strategy == HdrStrategy.nativeDolbyVision &&
        facts.path == source &&
        facts.codec == 'hevc' &&
        facts.dolbyVisionProfile == 5 &&
        facts.dvCompatibilityId == 0 &&
        facts.dvElPresent == false &&
        callbackSession.report.value.generation == generation &&
        androidNativeDvN4ControllerMatches(
          player: player,
          currentWrapper: wrapper,
          acceptedWrapper: wrapper,
          evidence: evidence,
        )) {
      _consumerGeneration = generation;
      _acceptedEvidence = evidence;
      _acceptedWrapper = wrapper;
      _routeApplied = false;
    }
  }

  void onBackendCall({
    required HdrVideoSession callbackSession,
    required String sessionInstanceId,
    required HdrBackendCallDiagnostic<HdrOpenPlan> diagnostic,
  }) =>
      run.onBackendCallDiagnostic(
        callbackSession: callbackSession,
        sessionInstanceId: sessionInstanceId,
        diagnostic: diagnostic,
      );

  void onNativeOption({
    required HdrVideoSession callbackSession,
    required String sessionInstanceId,
    required HdrNativeDvOptionDiagnostic diagnostic,
  }) =>
      run.onNativeOptionDiagnostic(
        callbackSession: callbackSession,
        sessionInstanceId: sessionInstanceId,
        diagnostic: diagnostic,
      );

  void onSessionEvent({
    required HdrVideoSession callbackSession,
    required String sessionInstanceId,
    required HdrOutputEvent event,
  }) {
    final currentGeneration = _session?.report.value.generation;
    if (_consumerGeneration != null &&
        currentGeneration != _consumerGeneration) {
      _consumerGeneration = null;
      _acceptedEvidence = null;
      _acceptedWrapper = null;
      _routeApplied = false;
    }
    run.onSessionEvent(
      callbackSession: callbackSession,
      sessionInstanceId: sessionInstanceId,
      event: event,
    );
    if (event is HdrReclassifiedEvent || event is HdrErrorEvent) {
      _consumerGeneration = null;
      _acceptedEvidence = null;
      _acceptedWrapper = null;
      _routeApplied = false;
    }
    final session = _session;
    if (event is HdrRouteAppliedEvent &&
        !_closing &&
        session != null &&
        identical(callbackSession, session) &&
        sessionInstanceId == _sessionInstanceId &&
        event.generation == _consumerGeneration &&
        session.report.value.generation == event.generation &&
        event.report.verified &&
        event.route.strategy == HdrStrategy.nativeDolbyVision &&
        event.report.actual?.strategy == HdrStrategy.nativeDolbyVision &&
        _acceptedEvidence != null &&
        androidNativeDvN4ControllerMatches(
          player: player,
          currentWrapper: session.controller.value,
          acceptedWrapper: _acceptedWrapper,
          evidence: _acceptedEvidence!,
        )) {
      _routeApplied = true;
    }
  }

  Future<AndroidNativeDvForeignOwnershipResult> execute() {
    if (!ready) {
      return Future.error(
          StateError('N4 requires actual same-session accepted P5 route'));
    }
    return _execution ??= run.execute(
      rawPlayerOpen: (actualPlayer, sameSource) =>
          openSamePlayerRaw(actualPlayer, sameSource),
    );
  }

  /// Synchronously rejects new page actions while startup/cleanup is draining.
  /// The helper's destructive close still waits until page startup settles.
  void stopAdmission() {
    _closing = true;
  }

  Future<void> close() {
    stopAdmission();
    return run.close();
  }

  Future<List<Map<String, Object?>>> drain() => run.drain();

  Future<void> openSamePlayerRaw(Player actualPlayer, String sameSource) {
    if (!identical(actualPlayer, player) || sameSource != source) {
      throw StateError('N4 raw open requires the bound same Player and P5 URI');
    }
    return actualPlayer.open(Media(sameSource));
  }
}

class AndroidNativeDvN4PageCloseError {
  const AndroidNativeDvN4PageCloseError({
    required this.phase,
    required this.error,
    required this.stackTrace,
  });

  final String phase;
  final Object error;
  final StackTrace stackTrace;

  Map<String, Object?> toJson() => <String, Object?>{
        'phase': phase,
        'errorType': error.runtimeType.toString(),
        'error': error.toString(),
        'stack': stackTrace.toString(),
      };
}

class AndroidNativeDvN4PageCloseSnapshot {
  const AndroidNativeDvN4PageCloseSnapshot({
    required this.result,
    required this.journal,
    required this.errors,
    required this.playerTerminationSucceeded,
  });

  final AndroidNativeDvForeignOwnershipResult? result;
  final List<Map<String, Object?>> journal;
  final List<AndroidNativeDvN4PageCloseError> errors;
  final bool playerTerminationSucceeded;
}

bool androidNativeDvN4PlayerTerminationSucceeded(
  AndroidNativeDvForeignOwnershipResult? result,
  List<Map<String, Object?>> journal,
) {
  if (result != null) return result.playerTerminated;
  Map<String, Object?>? terminal;
  for (final row in journal) {
    if (row['kind'] == 'player-termination') terminal = row;
  }
  return terminal?['success'] == true;
}

/// Production close/exit control flow, injectable only at actual page
/// operation boundaries so host tests exercise the same sequencing.
class AndroidNativeDvN4PageCloseSequence {
  Future<void>? _closeFuture;
  Future<void>? _exitFuture;
  bool _admissionClosed = false;

  bool get admissionClosed => _admissionClosed;

  Future<void> closeAndPersist({
    required Future<void> Function() waitStartup,
    required Future<void> Function() waitExecution,
    required AndroidNativeDvForeignOwnershipResult? Function() result,
    required Future<void> Function() closeDiagnostic,
    required Future<void> Function() closeHelper,
    required Future<void> Function() cancelEvents,
    required Future<List<Map<String, Object?>>> Function() drain,
    required bool Function(AndroidNativeDvForeignOwnershipResult? result,
            List<Map<String, Object?>> journal)
        playerTerminationSucceeded,
    required Object? Function(AndroidNativeDvForeignOwnershipResult? result)
        terminationError,
    required StackTrace? Function(AndroidNativeDvForeignOwnershipResult? result)
        terminationStack,
    required Future<void> Function(AndroidNativeDvN4PageCloseSnapshot snapshot)
        persistFinalReport,
    required void Function() closeAdmission,
  }) {
    _admissionClosed = true;
    closeAdmission();
    return _closeFuture ??= _closeAndPersist(
      waitStartup: waitStartup,
      waitExecution: waitExecution,
      result: result,
      closeDiagnostic: closeDiagnostic,
      closeHelper: closeHelper,
      cancelEvents: cancelEvents,
      drain: drain,
      playerTerminationSucceeded: playerTerminationSucceeded,
      terminationError: terminationError,
      terminationStack: terminationStack,
      persistFinalReport: persistFinalReport,
    );
  }

  Future<void> _closeAndPersist({
    required Future<void> Function() waitStartup,
    required Future<void> Function() waitExecution,
    required AndroidNativeDvForeignOwnershipResult? Function() result,
    required Future<void> Function() closeDiagnostic,
    required Future<void> Function() closeHelper,
    required Future<void> Function() cancelEvents,
    required Future<List<Map<String, Object?>>> Function() drain,
    required bool Function(AndroidNativeDvForeignOwnershipResult? result,
            List<Map<String, Object?>> journal)
        playerTerminationSucceeded,
    required Object? Function(AndroidNativeDvForeignOwnershipResult? result)
        terminationError,
    required StackTrace? Function(AndroidNativeDvForeignOwnershipResult? result)
        terminationStack,
    required Future<void> Function(AndroidNativeDvN4PageCloseSnapshot snapshot)
        persistFinalReport,
  }) async {
    final errors = <AndroidNativeDvN4PageCloseError>[];

    Future<void> observe(String phase, Future<void> Function() action) async {
      try {
        await action();
      } catch (error, stack) {
        errors.add(AndroidNativeDvN4PageCloseError(
          phase: phase,
          error: error,
          stackTrace: stack,
        ));
      }
    }

    await observe('startup', waitStartup);
    await observe('execution', waitExecution);
    await observe('diagnostic-close', closeDiagnostic);
    await observe('helper-close', closeHelper);
    await observe('event-cancel', cancelEvents);

    List<Map<String, Object?>> journal = const <Map<String, Object?>>[];
    try {
      journal = await drain();
    } catch (error, stack) {
      errors.add(AndroidNativeDvN4PageCloseError(
        phase: 'journal-drain',
        error: error,
        stackTrace: stack,
      ));
    }

    final executionResult = result();
    final terminationSucceeded =
        playerTerminationSucceeded(executionResult, journal);
    final snapshot = AndroidNativeDvN4PageCloseSnapshot(
      result: executionResult,
      journal: List.unmodifiable(journal),
      errors: List.unmodifiable(errors),
      playerTerminationSucceeded: terminationSucceeded,
    );

    // A final report is part of close. If atomic persistence fails, propagate
    // that original write/rename error and never claim exit.
    await persistFinalReport(snapshot);

    if (!terminationSucceeded) {
      final original = terminationError(executionResult) ??
          executionResult?.playerDisposeError;
      if (original != null) {
        Error.throwWithStackTrace(
          original,
          terminationStack(executionResult) ??
              executionResult?.playerDisposeStack ??
              StackTrace.current,
        );
      }
      throw StateError(
          'N4 Player termination has no explicit successful evidence');
    }
  }

  Future<void> exit({
    required Future<void> Function() closeAndPersist,
    required Future<void> Function() pop,
  }) =>
      _exitFuture ??= () async {
        await closeAndPersist();
        await pop();
      }();
}

Future<File> writeAndroidNativeDvN4ExternalReport({
  required Future<Directory?> Function() externalStorageDirectoryProvider,
  required String runId,
  required Map<String, Object?> payload,
}) async {
  final externalRoot = await externalStorageDirectoryProvider();
  if (externalRoot == null) {
    throw StateError('App external files directory unavailable');
  }
  final reportDirectory = Directory(
      '${externalRoot.path}${Platform.pathSeparator}media-kit-hdr-diagnostic');
  await reportDirectory.create(recursive: true);
  final finalPath = '${reportDirectory.path}${Platform.pathSeparator}'
      'android-native-dv-n4-$runId.json';
  final temporaryFile = File('$finalPath.tmp');
  await temporaryFile.writeAsString(jsonEncode(payload), flush: true);
  return temporaryFile.rename(finalPath);
}

/// Serializes the diagnostic page's action drain and owned close/exit.
/// The run helper's rejection fallback is safe only after page work settles.
class AndroidNativeDvSessionPageExitController {
  Future<void>? _actionFuture;
  Future<void>? _exitFuture;

  bool get actionPending => _actionFuture != null;
  bool get exitRequested => _exitFuture != null;

  bool actionEnabled(AndroidNativeDvSessionLifecycleRun run, String actionId,
      {required bool terminationAttempted}) {
    if (exitRequested ||
        actionPending ||
        run.busy ||
        run.closed ||
        terminationAttempted) {
      return false;
    }
    final state = run.enabledActions[actionId];
    final enabled = state is Map && state['enabled'] == true;
    if (actionId == 'close-and-exit') {
      return run.debt || run.terminal || enabled;
    }
    return enabled && !run.debt && !run.terminal;
  }

  Future<void> runAction(Future<void> Function() action) {
    if (exitRequested || actionPending) {
      return Future<void>.error(StateError('Page action admission is closed'));
    }
    // Establish ownership before the callback can synchronously change state.
    final attempt = Future<void>(action);
    _actionFuture = attempt;
    unawaited(attempt.then<void>((_) {
      if (identical(_actionFuture, attempt)) _actionFuture = null;
    }, onError: (Object _, StackTrace __) {
      if (identical(_actionFuture, attempt)) _actionFuture = null;
    }));
    return attempt;
  }

  Future<void> requestExit({
    required AndroidNativeDvSessionLifecycleRun? Function() getRun,
    required Future<void>? Function() getStartup,
    required bool Function() terminationAttempted,
    required String Function() nextRequestId,
    required Future<void> Function() terminateOwnedPlayer,
    required Future<void> Function() exit,
    required void Function(Object error) reportFailure,
  }) {
    final existing = _exitFuture;
    if (existing != null) return existing;
    void report(Object error) {
      try {
        reportFailure(error);
      } catch (_) {
        // A UI error must not prevent owned cleanup or final report draining.
      }
    }

    final attempt = Future<void>(() async {
      // Read startup after initState has assigned its Future. Never time out a
      // live continuation: termination follows its final report settlement.
      final pending = <Future<void>?>[getStartup(), _actionFuture];
      for (final future in pending) {
        if (future == null) continue;
        try {
          await future;
        } catch (error) {
          final run = getRun();
          if (run != null && !run.closed) {
            run.markDebt('Page work failed before exit: $error');
          }
          report(error);
        }
      }
      final run = getRun();
      if (run == null) {
        // Build validation can fail before a run exists. Dispose resources,
        // but retain the page because there is no final run report to drain.
        if (!terminationAttempted()) await terminateOwnedPlayer();
        throw StateError('Lifecycle run is unavailable for owned exit');
      }
      if (run.closed || terminationAttempted()) return;
      if (run.busy) {
        // Unknown work is not safe to terminate; tracked work was awaited.
        throw StateError('Untracked lifecycle work prevents owned exit');
      }
      // A queued Back disables page action admission while waiting. Restore
      // only this admitted cleanup action after the full drain; debt/terminal
      // still reject certification and use the helper's recovery fallback.
      if (!run.debt && !run.terminal) {
        run.setActionEnabled('close-and-exit', true);
      }
      await runAndroidNativeDvCloseAndExit(
        run: run,
        requestId: nextRequestId(),
        terminateOwnedPlayer: terminateOwnedPlayer,
        exit: exit,
        reportFailure: report,
      );
    });
    // A final-report failure is reported locally by the close helper and keeps
    // this attempt latched. The terminated page retains its error; repeated
    // Back never re-disposes the Player or treats run.closed as write success.
    _exitFuture = attempt;
    unawaited(attempt.then<void>((_) {}, onError: (Object _, StackTrace __) {
      // Only a pre-termination refusal can be retried after safe settlement.
      if (!terminationAttempted() &&
          getRun()?.closed != true &&
          identical(_exitFuture, attempt)) {
        _exitFuture = null;
      }
    }));
    return attempt;
  }
}

/// P8.4 C2: non-constructive owner-generation observation for the YUV diag
/// bound arm. Reads only [session]'s published controller — a null session or
/// a session that has not published an output yet yields null (the arm then
/// keeps its legacy-global-arm fallback) and no default Texture wrapper is
/// ever created as a side effect. Observing through the
/// `_hdrTransactionController` fallback getter here would eagerly construct
/// `_initialController` before the session's platform-view request, letting
/// the Android controller reuse a Texture-configured handle and hard-fail the
/// first open with HdrDataSpaceApplyException.
@visibleForTesting
Future<int?> resolveYuvDiagOwnerGeneration(HdrVideoSession? session) async {
  int? ownerGeneration;
  final VideoController? controller = session?.controller.value;
  if (controller != null && controller.platform.isCompleted) {
    final platform = await controller.platform.future;
    if (platform.nativeSurfaceGeneration > 0) {
      ownerGeneration = platform.nativeSurfaceGeneration;
    }
  }
  return ownerGeneration;
}

class SinglePlayerSingleVideoScreen extends StatefulWidget {
  const SinglePlayerSingleVideoScreen({super.key});

  @override
  State<SinglePlayerSingleVideoScreen> createState() =>
      _SinglePlayerSingleVideoScreenState();
}

class _SinglePlayerSingleVideoScreenState
    extends State<SinglePlayerSingleVideoScreen> with WidgetsBindingObserver {
  static const _androidNativeDvReleaseDiagnostic = bool.fromEnvironment(
    'MEDIA_KIT_ANDROID_NATIVE_DV_RELEASE_DIAGNOSTIC',
  );
  static const _androidNativeDvReleaseDiagnosticSeconds = int.fromEnvironment(
    'MEDIA_KIT_ANDROID_NATIVE_DV_DIAGNOSTIC_SECONDS',
    defaultValue: 300,
  );
  static const _androidNativeDvReleaseDiagnosticIntervalSeconds =
      int.fromEnvironment(
    'MEDIA_KIT_ANDROID_NATIVE_DV_DIAGNOSTIC_INTERVAL_SECONDS',
    defaultValue: 5,
  );
  static const _androidNativeDvReleaseDiagnosticIdentity =
      String.fromEnvironment(
    'MEDIA_KIT_ANDROID_NATIVE_DV_DIAGNOSTIC_IDENTITY',
  );
  static const _androidNativeDvSessionDiagnostic = bool.fromEnvironment(
    'MEDIA_KIT_ANDROID_NATIVE_DV_SESSION_DIAGNOSTIC',
  );
  static const _androidNativeDvSessionNegativeN1 = bool.fromEnvironment(
    'MEDIA_KIT_ANDROID_NATIVE_DV_SESSION_NEGATIVE_N1',
  );
  static const _androidNativeDvSessionForeignOwnershipN4 = bool.fromEnvironment(
    'MEDIA_KIT_ANDROID_NATIVE_DV_SESSION_FOREIGN_OWNERSHIP_N4',
    defaultValue: false,
  );
  static const _androidPlaybackPerformance = bool.fromEnvironment(
    'MEDIA_KIT_ANDROID_PLAYBACK_PERFORMANCE_DIAGNOSTIC',
  );
  static const _androidAvTrace = bool.fromEnvironment(
    'MEDIA_KIT_ANDROID_AV_TRACE',
  );
  // C-line telemetry probe (plan C2): sample the mpv `vo-passes` property to
  // determine whether per-pass timing telemetry is usable on this device at
  // all. String-format reads may fail on node-typed properties; a stable
  // failure is itself the C2 finding (fallback telemetry channels then apply).
  static const _androidVoPassesTrace = bool.fromEnvironment(
    'MEDIA_KIT_ANDROID_VO_PASSES_TRACE',
  );
  static const _androidDataSpacePerformProbe = bool.fromEnvironment(
    'MEDIA_KIT_ANDROID_DATASPACE_PERFORM_PROBE',
  );
  static const _androidHdrPreferConvert = bool.fromEnvironment(
    'MEDIA_KIT_ANDROID_HDR_PREFER_CONVERT',
  );
  static const _androidHdrConvertRouteLock = bool.fromEnvironment(
    'MEDIA_KIT_ANDROID_HDR_CONVERT_ROUTE_LOCK',
  );
  // WP-C SurfaceTexture PoC (phase1-design-spec §5): the production realizer
  // overrides the locked convert route hwdec when the define is non-empty;
  // this page only captures MKSURF log evidence and hard-fails the open
  // without it. The hwdec-current verdict itself stays in the production
  // backend (verified against the overridden route.hwdec).
  StreamSubscription<PlayerLog>? _surfaceTexturePocLogSubscription;
  // Sticky: set on the first matching entry so a later bounded-buffer
  // eviction can never lose the verdict.
  bool _surfaceTexturePocVersionObserved = false;
  // WP-C SurfaceTexture diagnostics copy leg (diag on, PoC off): the locked
  // convert route stays the baseline mediacodec-copy path; the page owns an
  // unlabeled `lavfi=[signalstats]` append to the vf chain for one open
  // transaction and polls its metadata every 500 ms while playback runs.
  // Backend `_setOwned` convention: capture the original value, write strict,
  // read back to verify, restore on the failure/transaction-end path.
  static const String _copyDiagVfFilter =
      'format=yuv420p,@mksdiag:lavfi=[signalstats]';
  Timer? _copyDiagTimer;
  int? _copyDiagSerial;
  String? _copyDiagOriginalVf;
  bool _copyDiagVfOwned = false;
  // Diagnostics vd-lavc-o ownership (both legs): the diag session declares
  // the patch material's source color to the MediaCodec decoder through
  // avctx options (color_trc=16 SMPTE2084, color_primaries=9 BT2020,
  // colorspace=9 BT2020nc); MediaCodec does not parse VUI and the FFmpeg
  // wrapper echoes avctx color back on hwdec frames.
  static const _diagVdLavcOValue =
      'color_trc=16,color_primaries=9,colorspace=9';
  bool _diagVdLavcOOwned = false;
  String? _diagOriginalVdLavcO;
  int? _diagVdLavcOSerial;
  bool _copyDiagSampleInFlight = false;
  // WP-C SurfaceTexture diagnostics OES leg (diag on, PoC on): the
  // small-area readback switch is the pure-C `mkst_set_diag_enabled` export
  // of the already-loaded media_kit_video_hdr_bridge.so, called directly via
  // dart:ffi (no Java bridge call, no platform channel). Resolved once and
  // latched; any resolution failure keeps the switch unreachable and the
  // driver-side getter naturally at 0.
  static bool _surfaceTextureDiagSwitchProbed = false;
  static void Function(int)? _surfaceTextureDiagSwitch;
  Timer? _surfaceTextureDiagTimer;
  int? _surfaceTextureDiagSerial;
  // E1 (MKSURF-E1, diag on + PoC on only): producer-commit-boundary
  // dataspace injection arm. The page arms the vendor's diag atomic with the
  // unchanged PQ/LIMITED value before the open (same point as
  // `_enableDiagVdLavcO`) and resets it to 0 on the open end/failure paths;
  // mpv consumes it once at its EGL window surface creation. FFI mirrors the
  // `mkst_set_diag_enabled` pattern: the vendor plugin .so is already loaded
  // in-process by its own Java side, resolution is latched, and any failure
  // keeps the switch a silent no-op. Off state (either define off) never
  // touches the atomic.
  static const int _diagDataspacePqLimited =
      0x11C60000; // 300000256 = BT2020 PQ / LIMITED (unchanged value).
  static bool _diagDataspaceArmerProbed = false;
  static void Function(int)? _diagDataspaceArmer;
  int? _diagDataspaceSerial;
  // YUV diag (define on + PoC on only): arms the vendor's independent YUV
  // diag atomic before the open, exactly like the E1 dataspace arm. mpv
  // reads it once via dlsym at its EGL context/surface creation; the native
  // gate re-verifies the config49 EGL capability before any perform.
  static bool _yuvDiagSwitchProbed = false;
  static void Function(int)? _yuvDiagSwitch;
  int? _yuvDiagSerial;
  // Disarm export of the same vendor library (clears the owner binding
  // together with the flag). Best-effort: resolution failure falls back to
  // the legacy enabled-setter and is logged.
  static bool _yuvDiagDisarmProbed = false;
  static void Function()? _yuvDiagDisarm;
  AndroidLgSingleOpenOwner? _lgExperimentOwner;
  String? get _lgExperimentToken => _lgExperimentOwner?.token;

  Future<void> _revokeLgExperiment(String token, int handle) async {
    await const MethodChannel('media_kit_hdr_lab/lg_visual278_experiment')
        .invokeMethod<bool>('Revoke', {'handle': handle, 'ownerToken': token});
  }

  static const _androidLgVisual278Experiment = bool.fromEnvironment(
    'MEDIA_KIT_ANDROID_LG_VISUAL278_EXPERIMENT',
  );
  static const _convertExperiment = AndroidHdrConvertExperiment(
    String.fromEnvironment('MEDIA_KIT_ANDROID_CONVERT_SURFACE_TRANSFER',
        defaultValue: 'pq'),
    _androidMpvOutputLevels,
  );
  // WP-C SurfaceTexture PoC (plan §7): independent experiment class with the
  // same frozen output contract; the realized route must carry the
  // experimental surfacetexture importer. Define off keeps every call site
  // on the legacy convert experiment unchanged.
  static const _surfaceTextureExperiment = AndroidSurfaceTextureExperiment(
    String.fromEnvironment('MEDIA_KIT_ANDROID_CONVERT_SURFACE_TRANSFER',
        defaultValue: 'pq'),
    _androidMpvOutputLevels,
  );
  static const _androidMpvVoDebug = bool.fromEnvironment(
    'MEDIA_KIT_ANDROID_MPV_VO_DEBUG',
  );
  // YUV diag (phase3-decision, lab-gated, default off): the config49 8-bit
  // NV12 output diagnostic branch. Define on requires PoC on (the diag arm
  // follows the same E1 producer-commit-boundary pattern); with the define
  // off nothing is armed and mpv stays on the existing RGB path.
  static const _androidMksYuvDiag = bool.fromEnvironment(
    'MEDIA_KIT_ANDROID_MKS_YUV_DIAG',
  );
  // YUV diag offscreen/window range contract (V2 P1-1): the diag define MUST
  // be built with CONVERT_SURFACE_TRANSFER=pq + MPV_OUTPUT_LEVELS=full. That
  // pairing makes gpu-next write FULL-range normalized PQ into the RGBA16F
  // offscreen RGB FBO, while the config49 NV12 window surface is LIMITED
  // (probed), and the mpv-side final pass performs the single 16+219p limited
  // packing. Any other pairing double-compresses: offscreen limited x shader
  // limited would put the black/white ends at 30/217 instead of 16/235. The
  // experiment classes' validate() accepts the pq/full combination; this page
  // additionally hard-verifies the pairing at arm time and fails the
  // diagnostic transaction otherwise (YUV-DIAG: pairing rejected).
  static const _yuvDiagConvertTransfer = String.fromEnvironment(
    'MEDIA_KIT_ANDROID_CONVERT_SURFACE_TRANSFER',
    defaultValue: 'pq',
  );
  // HLG OOTF experiment: libplacebo derives the HLG scene-to-display
  // transform from the target peak (nit). Empty keeps mpv's auto.
  static const _androidMpvTargetPeak =
      String.fromEnvironment('MEDIA_KIT_ANDROID_MPV_TARGET_PEAK');
  // GPU render resolution cap for the convert route: the API 24 LG renders
  // 4K PQ at the edge of its budget; capping the output width (still above
  // the 1440 panel) restores realtime with no visible loss.
  static const _androidOutputMaxWidth = int.fromEnvironment(
      'MEDIA_KIT_ANDROID_OUTPUT_MAX_WIDTH',
      defaultValue: 0);
  // Full-range experiment: force the frame range to full before the GPU
  // conversion so the full-range dataspace variant matches the content.
  static const _androidVfFullRange =
      bool.fromEnvironment('MEDIA_KIT_ANDROID_VF_FULL_RANGE');
  // Force the renderer's output encoding range (mpv video-output-levels).
  // Default auto adopts the swapchain value (limited for 10-bit HDR on this
  // Android EGL path); 'full' expands in the existing final pass at ~zero
  // GPU cost so a full-range dataspace tag can be used with matching content.
  static const _androidMpvOutputLevels =
      String.fromEnvironment('MEDIA_KIT_ANDROID_MPV_OUTPUT_LEVELS');
  static const _androidNativeDvSessionLifecycleActions = bool.fromEnvironment(
    'MEDIA_KIT_ANDROID_NATIVE_DV_SESSION_LIFECYCLE_ACTIONS',
  );
  static const _androidNativeDvSessionLifecycleSeconds = int.fromEnvironment(
    'MEDIA_KIT_ANDROID_NATIVE_DV_SESSION_LIFECYCLE_SECONDS',
    defaultValue: androidNativeDvSessionLifecycleMaxSeconds,
  );
  static const _androidHdr10SessionDiagnostic = bool.fromEnvironment(
      'MEDIA_KIT_ANDROID_HDR10_SESSION_DIAGNOSTIC',
      defaultValue: false);
  static const _androidHdr10DiagnosticIdentity = String.fromEnvironment(
      'MEDIA_KIT_ANDROID_HDR10_DIAGNOSTIC_IDENTITY',
      defaultValue: '');
  AndroidHdrSessionDiagnostic? _hdr10Journal;
  StreamSubscription<PlayerLog>? _hdr10CodecLogSubscription;
  String? _hdr10BuildError;
  Future<void>? _hdr10Startup;
  Future<void>? _hdr10CleanupFuture;
  Future<void>? _hdr10ExitFuture;
  Timer? _hdr10Timer;
  bool _hdr10Closing = false;

  static const _androidHdrTransaction = bool.fromEnvironment(
    'MEDIA_KIT_ANDROID_HDR_TRANSACTION',
  );
  static const _androidDualViewLifecycleProbe = bool.fromEnvironment(
    'MEDIA_KIT_ANDROID_DUAL_VIEW_LIFECYCLE_PROBE',
  );
  static const _autoSinglePlayer = bool.fromEnvironment(
    'MEDIA_KIT_AUTO_SINGLE_PLAYER',
  );
  static const _androidRecoverySources = String.fromEnvironment(
    'MEDIA_KIT_ANDROID_RECOVERY_SOURCES',
  );
  static const _androidOpenPhaseTrace = bool.fromEnvironment(
    'MEDIA_KIT_ANDROID_OPEN_PHASE_TRACE',
  );
  static const _androidDirectOpenTrace = bool.fromEnvironment(
    'MEDIA_KIT_ANDROID_DIRECT_OPEN_TRACE',
  );
  static const _androidOpenOnTap = bool.fromEnvironment(
    'MEDIA_KIT_ANDROID_OPEN_ON_TAP',
  );
  static const _androidTapFullscreenBeforeOpen = bool.fromEnvironment(
    'MEDIA_KIT_ANDROID_TAP_FULLSCREEN_BEFORE_OPEN',
  );
  static const _androidPreopenFullscreen = bool.fromEnvironment(
    'MEDIA_KIT_ANDROID_PREOPEN_FULLSCREEN',
  );
  static const _androidPreopenFirstFrameProbe = bool.fromEnvironment(
    'MEDIA_KIT_ANDROID_PREOPEN_FIRST_FRAME_PROBE',
  );
  // Diagnostic only: classify controlled local fixtures by their names.
  // Normal HDR opens keep their content-verified private copy.
  static const _androidNamedLocalSource = bool.fromEnvironment(
    'MEDIA_KIT_ANDROID_NAMED_LOCAL_SOURCE',
  );
  bool _preopenFullscreenStarted = false;
  int _dualViewPhase = 0;
  bool _dualViewProbeScheduled = false;
  Future<void>? _autoPlayerExitFuture;
  static const _androidP5RpuPipelineBuilt = bool.fromEnvironment(
    'MEDIA_KIT_ANDROID_P5_RPU_PIPELINE_BUILT',
  );
  static const _androidAutoSdrAfterP5Seconds = int.fromEnvironment(
    'MEDIA_KIT_ANDROID_AUTO_SDR_AFTER_P5_SECONDS',
    defaultValue: -1,
  );
  // Same-player second open for per-mapper state verification (P0-1 style
  // consecutive playback within one process); requires HDR transaction mode.
  static const _androidAutoSecondSource = String.fromEnvironment(
    'MEDIA_KIT_ANDROID_AUTO_SECOND_SOURCE',
  );
  static const _androidAutoSecondSourceAtSeconds = int.fromEnvironment(
    'MEDIA_KIT_ANDROID_AUTO_SECOND_SOURCE_AT_SECONDS',
    defaultValue: -1,
  );
  static const _androidP5PlatformSdrDiagnostic = bool.fromEnvironment(
    'MEDIA_KIT_ANDROID_P5_PLATFORM_SDR_DIAGNOSTIC',
  );
  static const _androidP5PrestopFullscreen = bool.fromEnvironment(
    'MEDIA_KIT_ANDROID_P5_PRESTOP_FULLSCREEN',
  );
  static const _androidP5PrestopVidFullscreen = bool.fromEnvironment(
    'MEDIA_KIT_ANDROID_P5_PRESTOP_VID_FULLSCREEN',
  );
  static const _androidP5PrestopWidFullscreen = bool.fromEnvironment(
    'MEDIA_KIT_ANDROID_P5_PRESTOP_WID_FULLSCREEN',
  );
  static const _androidP5InplaceFullscreen = bool.fromEnvironment(
    'MEDIA_KIT_ANDROID_P5_INPLACE_FULLSCREEN',
  );
  static const _androidP5ScopeFullscreen = bool.fromEnvironment(
    'MEDIA_KIT_ANDROID_P5_SCOPE_FULLSCREEN',
  );
  static const _androidP5AutoFullscreenAtSeconds = int.fromEnvironment(
    'MEDIA_KIT_ANDROID_P5_AUTO_FULLSCREEN_AT_SECONDS',
    defaultValue: -1,
  );
  static const _androidTextureCopyDiagnostic = bool.fromEnvironment(
    'MEDIA_KIT_ANDROID_TEXTURE_COPY_DIAGNOSTIC',
  );
  static const _androidP5CounterProbe = bool.fromEnvironment(
    'MEDIA_KIT_ANDROID_P5_COUNTER_PROBE',
  );
  static const _androidForceP84PqFallback = bool.fromEnvironment(
    'MEDIA_KIT_ANDROID_FORCE_P84_PQ_FALLBACK',
  );
  static const _androidGpuPlatformHdr = bool.fromEnvironment(
    'MEDIA_KIT_ANDROID_GPU_PLATFORM_HDR',
  );
  // S10 experiment switches for the HdrVideoSession path (acceptance A3/A4/A6):
  // - simulate-no-HLG: the session's capability provider drops HLG (type 3),
  //   so a P8.4 source must degrade along the candidate list.
  // - wrong-hint: forces a deliberately wrong hint descriptor at open
  //   (`sdr`, `hdr10` or `p84`) to trigger the single review rebuild.
  // - no-hint: opens without any hint; the session classifies from decoder
  //   facts and rebuilds if needed.
  // - policy-experimental: allowExperimental + metadataReshape first for the
  //   P8.4 source class (A6 RPU-reshape PQ route).
  // - preference/policy swap timers: mid-playback setPreference/setPolicy
  //   probes (A5).
  static const _androidHdrSimulateNoHlg = bool.fromEnvironment(
    'MEDIA_KIT_ANDROID_HDR_SIMULATE_NO_HLG',
  );
  static const _androidHdrWrongHint = String.fromEnvironment(
    'MEDIA_KIT_ANDROID_HDR_WRONG_HINT',
  );
  static const _androidHdrNoHint = bool.fromEnvironment(
    'MEDIA_KIT_ANDROID_HDR_NO_HINT',
  );
  static const _androidHdrPolicyExperimental = bool.fromEnvironment(
    'MEDIA_KIT_ANDROID_HDR_POLICY_EXPERIMENTAL',
  );
  // A3 candidate-degradation scenario: open the maturity gate while keeping
  // the default preference order, so the skipped direct candidate falls
  // through to the next HDR candidate instead of the A6 reshape-first order.
  static const _androidHdrGateOpen = bool.fromEnvironment(
    'MEDIA_KIT_ANDROID_HDR_GATE_OPEN',
  );
  static const _androidHdrPreferenceSwapAtSeconds = int.fromEnvironment(
    'MEDIA_KIT_ANDROID_HDR_PREFERENCE_SWAP_AT_SECONDS',
    defaultValue: -1,
  );
  static const _androidHdrPolicySwapAtSeconds = int.fromEnvironment(
    'MEDIA_KIT_ANDROID_HDR_POLICY_SWAP_AT_SECONDS',
    defaultValue: -1,
  );
  static const _androidHdrDiagnostics = bool.fromEnvironment(
    'MEDIA_KIT_ANDROID_HDR_DIAGNOSTICS',
  );

  // The controlled /data/local/tmp fixtures opened by this page. Their
  // identity mapping below is the page's existing sample enumeration (each
  // fixture's content was verified in earlier device rounds); this is not a
  // filename guess for arbitrary sources — anything else opens without a
  // hint and is classified from decoder facts by the session.
  static const _sdrControlSource = '/data/local/tmp/media-kit-sdr-control.mp4';
  static final RegExp _namedFixturePattern = RegExp(
      r'^/data/local/tmp/media-kit-(hdr10|hlg|p84|p5)-[a-z0-9][a-z0-9._-]*\.mp4$');

  /// The HDR session that owns the transaction path (migrated to
  /// HdrVideoSession in S10). Created in initState on Android.
  HdrVideoSession? _hdrSession;

  /// Monotonic open serial replacing the old source-intent gating: delayed
  /// probe callbacks capture the serial of the open that scheduled them and
  /// only act while no newer open (or disposal) happened.
  int _hdrOpenSerial = 0;

  /// The source of the current/last open, for reopen probes.
  String? _hdrCurrentSource;
  Future<void>? _hdrDisposeFuture;
  bool? _hdrDisposeReportClean;
  String? _hdrDisposeReportDetail;
  int? _hdrResumeOpenSerial;
  AndroidNativeDvReleaseDiagnostic? _nativeDvReleaseDiagnostic;
  final AndroidNativeDvDiagnosticPageAdmission<PlatformVideoController>
      _nativeDvPageAdmission =
      AndroidNativeDvDiagnosticPageAdmission<PlatformVideoController>();
  Future<void>? _nativeDvPageStartupFuture;
  String? _nativeDvReleaseDiagnosticBuildError;
  AndroidNativeDvN1Run? _nativeDvN1;
  AndroidNativeDvN4PageTransport? _nativeDvN4;
  StreamSubscription<HdrOutputEvent>? _nativeDvN4Events;
  Future<AndroidNativeDvForeignOwnershipResult>? _nativeDvN4Execution;
  Future<void>? _nativeDvN4ExecutionReport;
  Future<void>? _nativeDvN4Exit;
  final AndroidNativeDvN4PageCloseSequence _nativeDvN4CloseSequence =
      AndroidNativeDvN4PageCloseSequence();
  AndroidNativeDvForeignOwnershipResult? _nativeDvN4ExecutionResult;
  Object? _nativeDvN4ExecutionError;
  StackTrace? _nativeDvN4ExecutionStack;
  final String _nativeDvN4RunId =
      '${DateTime.now().toUtc().microsecondsSinceEpoch}-n4';
  String _nativeDvN4Status = 'N4 awaiting real accepted native P5 route';
  String? _nativeDvN4ReportPath;
  bool _nativeDvN4Closing = false;
  AndroidPlaybackPerformanceDiagnostic? _playbackPerformance;
  Timer? _playbackPerformanceTimer;
  Future<void>? _playbackPerformanceSample;
  int? _playbackPerformanceEpoch;
  StreamSubscription<HdrOutputEvent>? _nativeDvN1Events;
  Future<void>? _nativeDvN1Exit;
  AndroidNativeDvSessionDiagnostic? _nativeDvSessionDiagnostic;
  String? _nativeDvSessionDiagnosticError;
  Future<void>? _nativeDvSessionStartup;
  AndroidNativeDvSessionLifecycleRun? _nativeDvSessionLifecycleRun;
  int _nativeDvSessionInstanceSequence = 1;
  String _nativeDvSessionInstanceId = 'session-1';
  int _nativeDvSessionActionSequence = 0;
  String? _nativeDvSessionActionError;
  bool _nativeDvSessionVideoMounted = true;
  bool _nativeDvSessionStartupAccepted = false;
  bool _nativeDvPlayerTerminationAttempted = false;
  final _nativeDvSessionPageExit = AndroidNativeDvSessionPageExitController();
  final List<StreamSubscription<bool>> _nativeDvSessionStateSubscriptions =
      <StreamSubscription<bool>>[];
  BuildContext? _nativeDvSessionWindowedVideoContext;
  BuildContext? _nativeDvSessionFullscreenVideoContext;

  void _captureNativeDvSessionVideoContext(BuildContext context) {
    if (video_controls.isFullscreen(context)) {
      _nativeDvSessionFullscreenVideoContext = context;
    } else {
      _nativeDvSessionWindowedVideoContext = context;
    }
  }

  Map<String, Object?> _nativeDvSessionContextFact(BuildContext? context) =>
      <String, Object?>{
        'identity': context == null ? null : identityHashCode(context),
        'mounted': context?.mounted ?? false,
        'isFullscreen': context == null || !context.mounted
            ? null
            : video_controls.isFullscreen(context),
      };

  String? _validateHdr10DiagnosticBuild() => validateAndroidHdr10Diagnostic(
      android: Platform.isAndroid,
      transaction: _androidHdrTransaction,
      sources: sources,
      label: _androidHdr10DiagnosticIdentity,
      conflictingFlags: _androidNativeDvSessionDiagnostic ||
          _androidNativeDvSessionNegativeN1 ||
          _androidNativeDvSessionForeignOwnershipN4 ||
          _androidNativeDvSessionLifecycleActions ||
          _androidNativeDvReleaseDiagnostic ||
          _androidPlaybackPerformance ||
          _androidHdrSimulateNoHlg ||
          _androidHdrNoHint ||
          _androidHdrWrongHint.isNotEmpty ||
          _androidHdrPolicyExperimental ||
          _androidHdrGateOpen ||
          _androidHdrDiagnostics ||
          _androidAutoSecondSource.isNotEmpty ||
          _androidAutoSecondSourceAtSeconds > 0 ||
          _androidAutoSdrAfterP5Seconds > 0 ||
          _androidHdrPreferenceSwapAtSeconds > 0 ||
          _androidHdrPolicySwapAtSeconds > 0 ||
          _androidHdrAutoResumeProbe ||
          _androidHdrLifecyclePositionProbe ||
          _androidHdrPauseAtMediaSeconds >= 0 ||
          _androidHdrAutoPauseProbeSeconds > 0 ||
          _androidPostBindSeekProbe ||
          _androidPostBindReopenProbe ||
          _androidPreDestroyVidStop ||
          _androidAutoSeekAtSeconds >= 0 ||
          _androidAutoReopenAfterSeek ||
          _androidHotSwitchTarget.isNotEmpty ||
          _androidHotSwitchAtSeconds >= 0 ||
          _androidEngineDestroyAtSeconds >= 0 ||
          _androidOutputFailureAtSeconds >= 0 ||
          _androidDualPlayerView ||
          _androidDualViewLifecycleProbe ||
          _androidOpenPhaseTrace ||
          _androidDirectOpenTrace ||
          _androidVerboseLog ||
          _androidCodecTraceLog ||
          _androidVulkanProbe ||
          _androidPerfProbe ||
          _androidNoMediaProbe ||
          _androidSameSurfaceRebindProbe ||
          _androidTextureConsumerProbe ||
          _androidFlutterRepaintProbe ||
          _androidFrameSchedulerProbe ||
          _androidP5PlatformSdrDiagnostic ||
          _androidP5PrestopFullscreen ||
          _androidP5PrestopVidFullscreen ||
          _androidP5PrestopWidFullscreen ||
          _androidP5InplaceFullscreen ||
          _androidP5ScopeFullscreen ||
          _androidP5AutoFullscreenAtSeconds >= 0 ||
          _androidP5CounterProbe ||
          _androidTextureCopyDiagnostic ||
          _androidForceP84PqFallback ||
          _androidGpuPlatformHdr ||
          _androidP5CodecProbePath.isNotEmpty ||
          _androidP5CodecSurfaceProbe ||
          _androidP5CodecCpuReadProbe ||
          _androidP5CodecGpuImportProbe ||
          _androidP5CodecNativeReaderProbe ||
          _androidP5CodecDeferredAcquireProbe ||
          _androidP5CodecHoldPreviousImageProbe ||
          _androidP84BaseLayerProbe ||
          _androidRecoverySources.isNotEmpty ||
          _androidOpenOnTap ||
          _androidTapFullscreenBeforeOpen ||
          _androidPreopenFullscreen ||
          _androidPreopenFirstFrameProbe ||
          _androidPlayingStartSeconds.isNotEmpty ||
          _androidVideoTimingOffset.isNotEmpty ||
          _androidScale.isNotEmpty ||
          _androidDscale.isNotEmpty ||
          _androidCscale.isNotEmpty ||
          _androidLavcThreads.isNotEmpty ||
          _androidVoSummaryStopSeconds > 0 ||
          _androidLoopSource ||
          _autoToneMapping.isNotEmpty ||
          _autoTexture ||
          _autoSdr ||
          _autoStartSeconds.isNotEmpty);

  Future<Map<String, Object?>> _hdr10ReadIdentity() async {
    final session = _hdrSession;
    final video = session?.controller.value;
    final report = session?.report.value;
    Map<String, Object?>? output;
    if (video != null && video.platform.isCompleted) {
      final platform = await video.platform.future;
      if (platform is AndroidVideoController &&
          platform.configuration.android.usePlatformView) {
        final owner = platform.currentBoundOutputIdentity;
        output = {
          'bound': owner != null &&
              identical(video.notifier.value, platform) &&
              identical(session?.controller.value, video) &&
              identical(video.player, platform.player),
          'videoControllerIdentity': identityHashCode(video),
          'platformControllerIdentity': identityHashCode(platform),
          if (owner != null) ...{
            'handle': owner.handle,
            'generation': owner.generation,
            'viewId': owner.viewId,
            'surfaceGeneration': owner.surfaceGeneration,
            'wid': owner.wid,
          },
        };
      }
    }
    return {
      'sessionIdentity': session == null ? null : identityHashCode(session),
      'sessionInstanceId': 'hdr10-session-1',
      'sessionGeneration': report?.generation,
      'verified': report?.verified,
      'actual': androidHdr10RouteJson(report?.actual),
      'source':
          report == null ? null : androidHdr10ReportJson(report)['source'],
      'sourceOrigin': report?.sourceOrigin?.name,
      'boundOutput': output,
      'playing': player.state.playing,
      'completed': player.state.completed,
      'buffering': player.state.buffering,
    };
  }

  Future<void> _startHdr10Diagnostic() async {
    final journal = _hdr10Journal!;
    // Wait for native initialization before using waitForInitialization:false
    // under the existing Player lock. This is an idle readiness read only.
    await player.getProperty('path');
    journal.recordCapabilities(await HdrCapabilities.query());
    await journal.captureBaseline();
    _createHdrSession();
    journal.recordReport(_requireHdrSession().report.value);
    // The ordinary entry keeps the true hint/classification/review semantics.
    await _openInitialSource();
    await journal.sample();
    if (!_hdr10Closing) {
      _hdr10Timer = Timer.periodic(const Duration(seconds: 2), (timer) {
        if (!journal.samplingAllowed || _hdr10Closing) {
          timer.cancel();
          return;
        }
        unawaited(journal.sample().then<void>((_) {
          if (player.state.completed) timer.cancel();
          if (mounted) setState(() {});
        }, onError: (Object error, StackTrace stack) {
          journal.recordError(error, stack);
          timer.cancel();
          if (mounted) setState(() {});
        }));
      });
    }
    if (mounted) setState(() {});
  }

  Future<void> _closeHdr10Owned() => _hdr10CleanupFuture ??= () async {
        _hdr10Closing = true;
        _hdr10Timer?.cancel();
        final startup = _hdr10Startup;
        if (startup != null) {
          try {
            await startup;
          } catch (error, stack) {
            _hdr10Journal?.recordError(error, stack);
          }
        }
        final session = _hdrSession;
        final journal = _hdr10Journal;
        try {
          await _hdr10CodecLogSubscription?.cancel();
        } catch (error, stack) {
          journal?.recordError(error, stack);
        } finally {
          _hdr10CodecLogSubscription = null;
        }
        _autoPlayerDisposed = true;
        if (journal == null) {
          await player.dispose();
          return;
        }
        await journal.finish(
          disposeSession: () async {
            if (session != null) {
              session.report.removeListener(_onHdrReportChanged);
              session.controller.removeListener(_onHdrControllerChanged);
              await session.dispose();
            }
          },
          sessionCleanupFacts: () {
            final report = session?.lastDisposeReport;
            return {
              'sessionReportClean': report?.clean == true,
              'controllerRetired':
                  session != null && session.controller.value == null,
              'coordinatorError': report?.coordinatorError?.toString(),
              'playerError': report?.playerError?.toString(),
              'directoryError': report?.directoryError?.toString(),
              'retainedDirectory': report?.retainedDirectory,
            };
          },
          terminatePlayer: player.dispose,
        );
      }();

  Future<void> _exitHdr10DiagnosticPage() => _hdr10ExitFuture ??= () async {
        try {
          await _closeHdr10Owned();
          await SystemNavigator.pop();
        } catch (error, stack) {
          _hdr10Journal?.recordError(error, stack);
          _hdr10BuildError ??= '$error';
          if (mounted) setState(() {});
          rethrow;
        }
      }();

  String? _validateNativeDvSessionDiagnosticBuild() {
    if (_androidNativeDvSessionForeignOwnershipN4) {
      final n4Admission = validateAndroidNativeDvN4PageAdmission(
        android: Platform.isAndroid,
        hdrTransaction: _androidHdrTransaction,
        sessionDiagnostic: _androidNativeDvSessionDiagnostic,
        negativeN1: _androidNativeDvSessionNegativeN1,
        performance: _androidPlaybackPerformance,
        lifecycle: _androidNativeDvSessionLifecycleActions,
        hdr10: _androidHdr10SessionDiagnostic,
      );
      if (n4Admission != null) return n4Admission;
    }
    if (_androidPlaybackPerformance && !_androidNativeDvSessionNegativeN1) {
      return 'Performance sampling requires the fixed-source N1 diagnostic';
    }
    if (_androidNativeDvSessionNegativeN1 &&
        (!_androidNativeDvSessionDiagnostic ||
            _androidNativeDvSessionLifecycleActions)) {
      return 'N1 requires Session diagnostic and excludes lifecycle actions';
    }
    if (_androidNativeDvSessionLifecycleActions &&
        !_androidNativeDvSessionDiagnostic) {
      return 'Lifecycle actions require MEDIA_KIT_ANDROID_NATIVE_DV_SESSION_DIAGNOSTIC';
    }
    if (!_androidNativeDvSessionDiagnostic) return null;
    final admission = validateAndroidNativeDvSessionDiagnosticAdmission(
      android: Platform.isAndroid,
      hdrTransaction: _androidHdrTransaction,
      rawReleaseDiagnostic: _androidNativeDvReleaseDiagnostic,
      sources: sources,
      identityLabel: _androidNativeDvReleaseDiagnosticIdentity,
    );
    if (admission != null) return admission;
    if (_androidHdrSimulateNoHlg ||
        _androidHdrNoHint ||
        _androidHdrWrongHint.isNotEmpty ||
        _androidHdrPolicyExperimental ||
        _androidHdrGateOpen ||
        _androidHdrDiagnostics ||
        _androidAutoSecondSource.isNotEmpty ||
        _androidAutoSecondSourceAtSeconds > 0 ||
        _androidAutoSdrAfterP5Seconds > 0 ||
        _androidHdrPreferenceSwapAtSeconds > 0 ||
        _androidHdrPolicySwapAtSeconds > 0 ||
        _androidHdrAutoResumeProbe ||
        _androidHdrLifecyclePositionProbe ||
        _androidHdrPauseAtMediaSeconds >= 0 ||
        _androidHdrAutoPauseProbeSeconds > 0 ||
        _androidPostBindSeekProbe ||
        _androidPostBindReopenProbe ||
        _androidPreDestroyVidStop ||
        _androidAutoSeekAtSeconds >= 0 ||
        _androidAutoReopenAfterSeek ||
        _androidHotSwitchTarget.isNotEmpty ||
        _androidHotSwitchAtSeconds >= 0 ||
        _androidEngineDestroyAtSeconds >= 0 ||
        _androidOutputFailureAtSeconds >= 0 ||
        _androidDualPlayerView ||
        _androidDualViewLifecycleProbe ||
        _androidOpenPhaseTrace ||
        _androidDirectOpenTrace ||
        _androidVerboseLog ||
        _androidCodecTraceLog ||
        _androidVulkanProbe ||
        _androidPerfProbe ||
        _androidNoMediaProbe ||
        _androidSameSurfaceRebindProbe ||
        _androidTextureConsumerProbe ||
        _androidFlutterRepaintProbe ||
        _androidFrameSchedulerProbe ||
        _androidP5PlatformSdrDiagnostic ||
        _androidP5PrestopFullscreen ||
        _androidP5PrestopVidFullscreen ||
        _androidP5PrestopWidFullscreen ||
        _androidP5InplaceFullscreen ||
        _androidP5ScopeFullscreen ||
        _androidP5AutoFullscreenAtSeconds >= 0 ||
        _androidP5CounterProbe ||
        _androidTextureCopyDiagnostic ||
        _androidForceP84PqFallback ||
        _androidGpuPlatformHdr ||
        _androidP5CodecProbePath.isNotEmpty ||
        _androidP5CodecSurfaceProbe ||
        _androidP5CodecCpuReadProbe ||
        _androidP5CodecGpuImportProbe ||
        _androidP5CodecNativeReaderProbe ||
        _androidP5CodecDeferredAcquireProbe ||
        _androidP5CodecHoldPreviousImageProbe ||
        _androidP84BaseLayerProbe ||
        _androidRecoverySources.isNotEmpty ||
        _androidOpenOnTap ||
        _androidTapFullscreenBeforeOpen ||
        _androidPreopenFullscreen ||
        _androidPreopenFirstFrameProbe ||
        _androidPlayingStartSeconds.isNotEmpty ||
        _androidVideoTimingOffset.isNotEmpty ||
        _androidScale.isNotEmpty ||
        _androidDscale.isNotEmpty ||
        _androidCscale.isNotEmpty ||
        _androidLavcThreads.isNotEmpty ||
        _androidVoSummaryStopSeconds > 0 ||
        _androidLoopSource ||
        _autoToneMapping.isNotEmpty ||
        _autoTexture ||
        _autoSdr ||
        _autoStartSeconds.isNotEmpty) {
      return 'A source-changing, simulated, lifecycle, or high-volume diagnostic conflicts with Session mode';
    }
    try {
      validateAndroidNativeDvSessionDiagnosticSeconds(
        _androidNativeDvReleaseDiagnosticSeconds,
      );
      validateAndroidNativeDvSessionDiagnosticInterval(
        _androidNativeDvReleaseDiagnosticIntervalSeconds,
      );
      if (_androidNativeDvSessionLifecycleActions) {
        validateAndroidNativeDvSessionLifecycleSeconds(
          _androidNativeDvSessionLifecycleSeconds,
        );
      }
    } on RangeError catch (error) {
      return '$error';
    }
    return null;
  }

  Future<void> _startNativeDvSessionDiagnostic() async {
    final diagnostic = _nativeDvSessionDiagnostic;
    if (diagnostic == null) {
      throw StateError('Session diagnostic is unavailable');
    }
    final negative = _nativeDvN1;
    if (negative != null) {
      await negative.prepare(player);
      if (!mounted || _autoPlayerDisposed) return;
      _createHdrSession();
      final session = _requireHdrSession();
      _nativeDvN1Events = session.events.listen(negative.onEvent);
      negative.admitOpen();
      _hdrCurrentSource = androidNativeDvSessionDiagnosticSource;
      try {
        await session.open(Media(androidNativeDvSessionDiagnosticSource),
            hint: HdrSourceDescriptor.fromKind(HdrMediaKind.dolbyVisionP5));
        // Drain typed event delivery after the existing open has completed.
        await Future<void>.delayed(Duration.zero);
        negative.record('open-returned', {
          'generation': session.report.value.generation,
          'actual':
              AndroidNativeDvN1Run.routeFields(session.report.value.actual),
        });
        if (_androidPlaybackPerformance) {
          _playbackPerformance =
              AndroidPlaybackPerformanceDiagnostic(player: player);
          _playbackPerformanceEpoch = player.fileLoadedEpoch;
          await _samplePlaybackPerformance();
          _playbackPerformanceTimer =
              Timer.periodic(const Duration(seconds: 2), (_) {
            if (_playbackPerformanceSample != null ||
                _autoPlayerDisposed ||
                negative.closed ||
                negative.elapsedMicros >= negative.durationSeconds * 1000000) {
              return;
            }
            unawaited(_samplePlaybackPerformance());
          });
        }
        negative.status.value =
            negative.audit()['configurationEvidenceComplete'] == true
                ? 'N1 fallback configuration observed; visible output pending'
                : 'N1 evidence incomplete; inspect report';
      } catch (error, stack) {
        negative.record('open-failed', {}, error: error, stack: stack);
        negative.status.value = 'N1 open failed; inspect retained evidence';
        rethrow;
      } finally {
        await negative.persist();
      }
      return;
    }
    await diagnostic.prepare();
    if (!mounted || _autoPlayerDisposed) return;
    _createHdrSession();
    final session = _requireHdrSession();
    await diagnostic.attach(
      session,
      sessionInstanceId: _nativeDvSessionInstanceId,
    );
    if (_androidNativeDvSessionLifecycleActions) {
      final startupRequest = 'startup-$_nativeDvSessionInstanceId';
      await _nativeDvSessionLifecycleRun!.runStartup(
        requestId: startupRequest,
        action: () async {
          await _lifecycleOpenSource(
            sourcePath: androidNativeDvSessionLifecycleP5Path,
            start: Duration.zero,
            play: true,
            actionId: 'startup',
            requestId: startupRequest,
            stepId: 'initial-open',
          );
        },
      );
      _refreshNativeDvSessionLifecycleActions(startupAccepted: true);
    } else {
      await _openHdrSource(androidNativeDvSessionDiagnosticSource);
    }
  }

  void _refreshNativeDvSessionLifecycleActions({bool startupAccepted = false}) {
    final run = _nativeDvSessionLifecycleRun;
    if (run == null) return;
    if (startupAccepted) _nativeDvSessionStartupAccepted = true;
    if (_autoPlayerDisposed ||
        _nativeDvSessionPageExit.exitRequested ||
        run.closed ||
        run.debt ||
        run.terminal) {
      for (final id in androidNativeDvSessionLifecycleActions) {
        run.setActionEnabled(id, false,
            reason: run.debt ? 'cleanup debt' : 'run is closed');
      }
      return;
    }
    final ready = _nativeDvSessionStartupAccepted && _hdrSession != null;
    final state = player.state;
    final activePlayback =
        ready && state.playing && !state.completed && !state.buffering;
    final seekAvailable = ready &&
        !state.completed &&
        !state.buffering &&
        state.duration > const Duration(seconds: 93);
    run.setActionEnabled('close-and-exit', ready,
        reason: ready ? null : 'Session startup is not accepted');
    run.setActionEnabled('Pause10Resume', activePlayback,
        reason: activePlayback ? null : 'requires active non-EOS playback');
    final manualResumeAvailable = _nativeDvManualResumeState().canResume;
    run.setActionEnabled('ManualResume', manualResumeAvailable,
        reason: manualResumeAvailable
            ? null
            : 'requires accepted paused non-EOS nonbuffering Session');
    run.setActionEnabled('Seek90Then30', seekAvailable,
        reason:
            seekAvailable ? null : 'requires playable P5 beyond 93 seconds');
    for (final id in <String>[
      'Reopen40Then10',
      'P5SDRP5',
      'RestoreSurface',
      'RecreateSession',
    ]) {
      run.setActionEnabled(id, ready,
          reason: ready ? null : 'Session startup is not accepted');
    }
    final fullscreenAvailable = ready && !state.completed;
    run.setActionEnabled('FullscreenRoundTrip', fullscreenAvailable,
        reason: fullscreenAvailable ? null : 'requires non-EOS playback');
    if (!run.busy) {
      run.status.value = 'ready · rows=${run.rows.length} · '
          'player=${state.completed ? 'EOS' : state.playing ? 'playing' : 'paused'}';
    }
  }

  AndroidNativeDvManualResumeState _nativeDvManualResumeState() {
    final state = player.state;
    return AndroidNativeDvManualResumeState(
      session: _hdrSession,
      sessionInstanceId: _nativeDvSessionInstanceId,
      startupAccepted: _nativeDvSessionStartupAccepted &&
          !_autoPlayerDisposed &&
          !_nativeDvPlayerTerminationAttempted,
      playing: state.playing,
      completed: state.completed,
      buffering: state.buffering,
      position: state.position,
    );
  }

  Future<void> _lifecycleOpenSource({
    required String sourcePath,
    required Duration start,
    required bool play,
    required String actionId,
    required String requestId,
    required String stepId,
  }) async {
    final run = _nativeDvSessionLifecycleRun;
    final diagnostic = _nativeDvSessionDiagnostic;
    if (!_androidNativeDvSessionLifecycleActions ||
        run == null ||
        diagnostic == null ||
        !mounted ||
        _autoPlayerDisposed) {
      throw StateError('Lifecycle source admission is closed');
    }
    if (sourcePath != androidNativeDvSessionLifecycleP5Path &&
        sourcePath != androidNativeDvSessionLifecycleSdrPath) {
      throw StateError('Lifecycle mode rejects unapproved source path');
    }
    final session = _requireHdrSession();
    await run.recordStep(
      actionId: actionId,
      requestId: requestId,
      stepId: stepId,
      phase: 'begin',
      sessionInstanceId: _nativeDvSessionInstanceId,
      expectedSource: sourcePath,
      requestedStart: start,
      requestedPlay: play,
    );
    await diagnostic.quiesceLifecycleSegment('before-$stepId');
    run.ensureActionSideEffectAllowed(
      actionId: actionId,
      requestId: requestId,
      operation: 'session-open-$stepId',
    );
    diagnostic.expectLifecycleSource(
      sessionInstanceId: _nativeDvSessionInstanceId,
      sourcePath: sourcePath,
      actionId: actionId,
      requestId: requestId,
    );
    try {
      await session.open(
        Media(sourcePath),
        hint: _hintFor(sourcePath),
        start: start,
        play: play,
      );
      run.ensureActionSideEffectAllowed(
        actionId: actionId,
        requestId: requestId,
        operation: 'accept-session-open-$stepId',
      );
      final generation = session.report.value.generation;
      final applied = await diagnostic.waitForLifecycleApplied(
        sessionInstanceId: _nativeDvSessionInstanceId,
        generation: generation,
      );
      await diagnostic.waitForLifecycleRows(
        sessionInstanceId: _nativeDvSessionInstanceId,
        generation: generation,
        minimumRows: 2,
      );
      run.ensureActionSideEffectAllowed(
        actionId: actionId,
        requestId: requestId,
        operation: 'accept-sampled-session-open-$stepId',
      );
      await run.recordStep(
        actionId: actionId,
        requestId: requestId,
        stepId: stepId,
        phase: 'end',
        sessionInstanceId: _nativeDvSessionInstanceId,
        expectedSource: sourcePath,
        requestedStart: start,
        requestedPlay: play,
      );
      _hdrCurrentSource = sourcePath;
      if (mounted) setState(() {});
      debugPrint('NATIVE_DV_LIFECYCLE_OPEN_ACCEPTED '
          'action=$actionId request=$requestId source=$sourcePath '
          'generation=$generation route=${applied['route']}');
    } catch (error) {
      await run.recordStep(
        actionId: actionId,
        requestId: requestId,
        stepId: stepId,
        phase: 'error',
        sessionInstanceId: _nativeDvSessionInstanceId,
        expectedSource: sourcePath,
        requestedStart: start,
        requestedPlay: play,
        error: error,
      );
      rethrow;
    }
  }

  void _reportNativeDvSessionExitFailure(Object error) {
    final prior = _nativeDvSessionActionError;
    final detail = '$error';
    _nativeDvSessionActionError =
        prior == null || prior == detail ? detail : '$prior\nExit: $detail';
    if (mounted) setState(() {});
  }

  Future<void> _exitNativeDvSessionLifecyclePage() {
    final attempt = _nativeDvSessionPageExit.requestExit(
      getRun: () => _nativeDvSessionLifecycleRun,
      getStartup: () => _nativeDvSessionStartup,
      terminationAttempted: () => _nativeDvPlayerTerminationAttempted,
      nextRequestId: () => 'tap-${++_nativeDvSessionActionSequence}',
      terminateOwnedPlayer: _closeNativeDvSessionAndPlayer,
      exit: SystemNavigator.pop,
      reportFailure: _reportNativeDvSessionExitFailure,
    );
    if (mounted) setState(() {});
    return attempt;
  }

  Future<void> _runNativeDvSessionLifecycleAction(String actionId) async {
    if (actionId == 'close-and-exit') {
      await _exitNativeDvSessionLifecyclePage();
      return;
    }
    final attempt = _nativeDvSessionPageExit
        .runAction(() => _runNativeDvSessionLifecycleActionOnce(actionId));
    if (mounted) setState(() {});
    try {
      await attempt;
    } finally {
      if (mounted) setState(() {});
    }
  }

  Future<void> _runNativeDvSessionLifecycleActionOnce(String actionId) async {
    final run = _nativeDvSessionLifecycleRun;
    if (run == null) throw StateError('Lifecycle run is unavailable');
    // UI enablement can be stale. Reject before publishing an action, and the
    // admitted helper reads again after the ACK and step writes have settled.
    final manualResumeExpected =
        actionId == 'ManualResume' ? _nativeDvManualResumeState() : null;
    if (manualResumeExpected != null && !manualResumeExpected.canResume) {
      throw StateError('Manual resume requires accepted paused playback');
    }
    final requestId = 'tap-${++_nativeDvSessionActionSequence}';
    Future<void> step(String id, Future<void> Function() operation,
        {Map<String, Object?> Function()? facts}) async {
      await run.recordStep(
        actionId: actionId,
        requestId: requestId,
        stepId: id,
        phase: 'begin',
        sessionInstanceId: _nativeDvSessionInstanceId,
        expectedSource: _hdrCurrentSource,
      );
      try {
        run.ensureActionSideEffectAllowed(
          actionId: actionId,
          requestId: requestId,
          operation: id,
        );
        await operation();
        await run.recordStep(
          actionId: actionId,
          requestId: requestId,
          stepId: id,
          phase: 'end',
          sessionInstanceId: _nativeDvSessionInstanceId,
          expectedSource: _hdrCurrentSource,
          facts: facts?.call(),
        );
      } catch (error) {
        await run.recordStep(
          actionId: actionId,
          requestId: requestId,
          stepId: id,
          phase: 'error',
          sessionInstanceId: _nativeDvSessionInstanceId,
          expectedSource: _hdrCurrentSource,
          error: error,
        );
        rethrow;
      }
    }

    Future<void> delay(Duration duration) async {
      if (run.remaining < duration) {
        throw TimeoutException('Lifecycle action exceeds run deadline');
      }
      await Future<void>.delayed(duration);
      if (run.debt || run.remaining <= Duration.zero) {
        throw TimeoutException('Lifecycle action reached run deadline');
      }
    }

    Future<void> seekAndObserve(Duration target) async {
      final before = player.state.position;
      final observed = Completer<Duration>();
      Duration? candidate;
      late final StreamSubscription<Duration> subscription;
      subscription = player.stream.position.listen((position) {
        final seconds = position.inMilliseconds / 1000;
        final targetSeconds = target.inMilliseconds / 1000;
        if (position != before &&
            seconds >= targetSeconds - 1 &&
            seconds <= targetSeconds + 3 &&
            !player.state.buffering) {
          candidate = position;
          if (!observed.isCompleted) observed.complete(position);
        }
      });
      final remaining = run.remaining;
      if (remaining <= Duration.zero) {
        await subscription.cancel();
        throw TimeoutException('No run budget remains for seek');
      }
      try {
        run.ensureActionSideEffectAllowed(
          actionId: actionId,
          requestId: requestId,
          operation: 'seek-${target.inSeconds}s',
        );
        await player.seek(target);
        run.ensureActionSideEffectAllowed(
          actionId: actionId,
          requestId: requestId,
          operation: 'observe-seek-${target.inSeconds}s',
        );
        final value = candidate ??
            await observed.future.timeout(
              remaining < const Duration(seconds: 12)
                  ? remaining
                  : const Duration(seconds: 12),
            );
        if (player.state.buffering ||
            (value - target).inMilliseconds.abs() > 3000) {
          throw StateError('Seek did not settle near $target');
        }
      } finally {
        await subscription.cancel();
      }
    }

    try {
      await run.runAction(
        actionId: actionId,
        requestId: requestId,
        action: (_) async {
          switch (actionId) {
            case 'ManualResume':
              Map<String, Object?>? resumeFacts;
              await step('manual-resume-10s', () async {
                resumeFacts = await runAndroidNativeDvManualResume(
                  run: run,
                  requestId: requestId,
                  expected: manualResumeExpected!,
                  readState: _nativeDvManualResumeState,
                  play: player.play,
                  observePlayback: delay,
                );
              }, facts: () => resumeFacts!);
              break;
            case 'Pause10Resume':
              await step('pause-10s', () async {
                run.ensureActionSideEffectAllowed(
                  actionId: actionId,
                  requestId: requestId,
                  operation: 'pause',
                );
                await player.pause();
                await delay(const Duration(seconds: 10));
              });
              await step('resume-10s', () async {
                run.ensureActionSideEffectAllowed(
                  actionId: actionId,
                  requestId: requestId,
                  operation: 'play',
                );
                await player.play();
                await delay(const Duration(seconds: 10));
              });
              break;
            case 'Seek90Then30':
              await step('seek-90s', () async {
                run.ensureActionSideEffectAllowed(
                  actionId: actionId,
                  requestId: requestId,
                  operation: 'pause',
                );
                await player.pause();
                await seekAndObserve(const Duration(seconds: 90));
                run.ensureActionSideEffectAllowed(
                  actionId: actionId,
                  requestId: requestId,
                  operation: 'play',
                );
                await player.play();
                await delay(const Duration(seconds: 10));
              });
              await step('seek-30s', () async {
                run.ensureActionSideEffectAllowed(
                  actionId: actionId,
                  requestId: requestId,
                  operation: 'pause',
                );
                await player.pause();
                await seekAndObserve(const Duration(seconds: 30));
                run.ensureActionSideEffectAllowed(
                  actionId: actionId,
                  requestId: requestId,
                  operation: 'play',
                );
                await player.play();
                await delay(const Duration(seconds: 10));
              });
              break;
            case 'Reopen40Then10':
              await step(
                  'p5-at-40s',
                  () => _lifecycleOpenSource(
                        sourcePath: androidNativeDvSessionLifecycleP5Path,
                        start: const Duration(seconds: 40),
                        play: true,
                        actionId: actionId,
                        requestId: requestId,
                        stepId: 'p5-at-40s',
                      ));
              await delay(const Duration(seconds: 10));
              await step(
                  'p5-at-10s',
                  () => _lifecycleOpenSource(
                        sourcePath: androidNativeDvSessionLifecycleP5Path,
                        start: const Duration(seconds: 10),
                        play: true,
                        actionId: actionId,
                        requestId: requestId,
                        stepId: 'p5-at-10s',
                      ));
              await delay(const Duration(seconds: 10));
              break;
            case 'P5SDRP5':
              await step(
                  'sdr-control',
                  () => _lifecycleOpenSource(
                        sourcePath: androidNativeDvSessionLifecycleSdrPath,
                        start: Duration.zero,
                        play: true,
                        actionId: actionId,
                        requestId: requestId,
                        stepId: 'sdr-control',
                      ));
              await delay(const Duration(seconds: 10));
              await step(
                  'p5-return',
                  () => _lifecycleOpenSource(
                        sourcePath: androidNativeDvSessionLifecycleP5Path,
                        start: const Duration(seconds: 30),
                        play: true,
                        actionId: actionId,
                        requestId: requestId,
                        stepId: 'p5-return',
                      ));
              await delay(const Duration(seconds: 10));
              break;
            case 'RestoreSurface':
              await step(
                  'reopen-after-lifecycle',
                  () => _lifecycleOpenSource(
                        sourcePath: androidNativeDvSessionLifecycleP5Path,
                        start: _lifecycleSafeResumePosition(),
                        play: true,
                        actionId: actionId,
                        requestId: requestId,
                        stepId: 'reopen-after-lifecycle',
                      ));
              await delay(const Duration(seconds: 10));
              break;
            case 'FullscreenRoundTrip':
              await _fullscreenLifecycleRoundTrip(
                actionId: actionId,
                requestId: requestId,
                delay: delay,
              );
              break;
            case 'RecreateSession':
              await _recreateNativeDvSession(actionId, requestId);
              break;
            default:
              throw StateError('Unknown lifecycle action $actionId');
          }
        },
      );
    } catch (error) {
      _nativeDvSessionActionError = '$error';
      if (mounted) setState(() {});
      rethrow;
    } finally {
      _refreshNativeDvSessionLifecycleActions();
    }
  }

  Future<void> _recreateNativeDvSession(
      String actionId, String requestId) async {
    final diagnostic = _nativeDvSessionDiagnostic!;
    final oldSession = _requireHdrSession();
    final oldId = _nativeDvSessionInstanceId;
    final position = _lifecycleSafeResumePosition();
    await diagnostic.quiesceLifecycleSegment('before-session-recreate');
    _nativeDvSessionLifecycleRun!.ensureActionSideEffectAllowed(
      actionId: actionId,
      requestId: requestId,
      operation: 'unmount-old-session',
    );
    _nativeDvSessionVideoMounted = false;
    _nativeDvSessionWindowedVideoContext = null;
    _nativeDvSessionFullscreenVideoContext = null;
    if (mounted) setState(() {});
    await SchedulerBinding.instance.endOfFrame;
    _nativeDvSessionLifecycleRun!.ensureActionSideEffectAllowed(
      actionId: actionId,
      requestId: requestId,
      operation: 'dispose-old-session',
    );
    Object? disposeError;
    try {
      await oldSession.dispose();
    } catch (error) {
      disposeError = error;
    }
    final restored = await diagnostic.capturePostSessionCleanup(
      report: oldSession.lastDisposeReport,
      sessionDisposeError: disposeError,
      sessionInstanceId: oldId,
    );
    if (!androidNativeDvSessionReuseAdmitted(
      disposeReportClean:
          disposeError == null && oldSession.lastDisposeReport?.clean == true,
      actualRestorationVerified: restored,
      lifecycleDebt: _nativeDvSessionLifecycleRun?.debt ?? true,
    )) {
      throw StateError(
          'Old Session cleanup did not prove actual baseline restoration');
    }
    _nativeDvSessionLifecycleRun!.ensureActionSideEffectAllowed(
      actionId: actionId,
      requestId: requestId,
      operation: 'create-new-session',
    );
    _hdrSession = null;
    _hdrDisposeFuture = null;
    _nativeDvSessionInstanceId =
        'session-${++_nativeDvSessionInstanceSequence}';
    _createHdrSession(lifecycleSessionInstanceId: _nativeDvSessionInstanceId);
    final newSession = _requireHdrSession();
    await diagnostic.attach(newSession,
        sessionInstanceId: _nativeDvSessionInstanceId);
    _nativeDvSessionVideoMounted = true;
    if (mounted) setState(() {});
    await SchedulerBinding.instance.endOfFrame;
    await _lifecycleOpenSource(
      sourcePath: androidNativeDvSessionLifecycleP5Path,
      start: position,
      play: true,
      actionId: actionId,
      requestId: requestId,
      stepId: 'new-session-open',
    );
  }

  Future<void> _fullscreenLifecycleRoundTrip({
    required String actionId,
    required String requestId,
    required Future<void> Function(Duration) delay,
  }) async {
    final diagnostic = _nativeDvSessionDiagnostic!;
    final run = _nativeDvSessionLifecycleRun!;
    Map<String, Object?>? before;
    Duration savedPosition = Duration.zero;
    final observations = AndroidNativeDvFullscreenLifecycleObservations();
    BuildContext? windowedContext;
    BuildContext? fullscreenContext;
    Map<String, Object?>? during;
    Map<String, Object?>? postEntryRecovery;
    Map<String, Object?>? after;
    var entryChanged = false;
    bool? exitChanged;
    var contextStepRecorded = false;

    Future<void> recordContextStep({
      required String phase,
      Object? rejection,
    }) async {
      if (contextStepRecorded) return;
      contextStepRecorded = true;
      final rejectionText = rejection?.toString();
      await run.recordStep(
        actionId: actionId,
        requestId: requestId,
        stepId: 'fullscreen-surface-observation',
        phase: phase,
        sessionInstanceId: _nativeDvSessionInstanceId,
        facts: <String, Object?>{
          ...observations.toJson(),
          'windowedContext':
              _nativeDvSessionContextFact(_nativeDvSessionWindowedVideoContext),
          'fullscreenContext': _nativeDvSessionContextFact(
              _nativeDvSessionFullscreenVideoContext),
          'selectedWindowedContext':
              _nativeDvSessionContextFact(windowedContext),
          'selectedFullscreenContext':
              _nativeDvSessionContextFact(fullscreenContext),
          'beforeSurfaceTuple': before,
          'duringSurfaceTuple': during,
          'fullscreenBeforeRecovery': during,
          'afterEntryRecoverySurfaceTuple': postEntryRecovery,
          'afterEntryRecovery': postEntryRecovery,
          'afterSurfaceTuple': after,
          'observations': observations.toJson(),
          'entryChanged': entryChanged,
          'exitChanged': exitChanged,
          'tupleChanged': entryChanged || exitChanged == true,
          if (rejectionText != null)
            'rejection': rejectionText.length <= 512
                ? rejectionText
                : rejectionText.substring(0, 512),
        },
      );
    }

    try {
      await runAndroidNativeDvAdmittedSideEffect(
        run: run,
        actionId: actionId,
        requestId: requestId,
        operation: 'enter-fullscreen-toggle',
        prepare: () async {
          await diagnostic
              .quiesceLifecycleSegment('before-fullscreen-roundtrip');
          before = await diagnostic.captureCurrentSurfaceTuple();
          savedPosition = _lifecycleSafeResumePosition();
          windowedContext = _nativeDvSessionWindowedVideoContext;
          if (windowedContext == null ||
              !windowedContext!.mounted ||
              video_controls.isFullscreen(windowedContext!)) {
            throw StateError(
                'Mounted windowed Video controls context is unavailable');
          }
        },
        sideEffect: () => video_controls.toggleFullscreen(windowedContext!),
      );

      await runAndroidNativeDvAdmittedSideEffect(
        run: run,
        actionId: actionId,
        requestId: requestId,
        operation: 'exit-fullscreen-toggle',
        prepare: () async {
          await SchedulerBinding.instance.endOfFrame;
          await delay(const Duration(seconds: 5));
          fullscreenContext = _nativeDvSessionFullscreenVideoContext;
          if (fullscreenContext == null ||
              !fullscreenContext!.mounted ||
              !video_controls.isFullscreen(fullscreenContext!)) {
            throw StateError('Fullscreen UI did not enter the Video scope');
          }
          during = await diagnostic.captureCurrentSurfaceTuple();
          observations.observeEntry(before: before, during: during);
          entryChanged = observations.entryChanged;
          if (entryChanged) {
            await _lifecycleOpenSource(
              sourcePath: androidNativeDvSessionLifecycleP5Path,
              start: savedPosition,
              play: true,
              actionId: actionId,
              requestId: requestId,
              stepId: 'reopen-inside-fullscreen-after-surface-change',
            );
            await delay(const Duration(seconds: 5));
            final refreshedContext = _nativeDvSessionFullscreenVideoContext;
            if (refreshedContext == null ||
                !refreshedContext.mounted ||
                !video_controls.isFullscreen(refreshedContext)) {
              throw StateError(
                  'Fullscreen context did not survive the Surface reopen');
            }
            fullscreenContext = refreshedContext;
            postEntryRecovery = await diagnostic.captureCurrentSurfaceTuple();
            observations.observeEntryRecovery(postEntryRecovery);
          }
          if (!fullscreenContext!.mounted) {
            throw StateError('Fullscreen Video scope unmounted before exit');
          }
        },
        sideEffect: () => video_controls.toggleFullscreen(fullscreenContext!),
      );
      await SchedulerBinding.instance.endOfFrame;
      await delay(const Duration(seconds: 5));
      after = await diagnostic.captureCurrentSurfaceTuple();
      observations.observeExit(after);
      exitChanged = observations.exitChanged;
      if (exitChanged == true || !entryChanged) {
        await _lifecycleOpenSource(
          sourcePath: androidNativeDvSessionLifecycleP5Path,
          start: _lifecycleSafeResumePosition(),
          play: true,
          actionId: actionId,
          requestId: requestId,
          stepId: exitChanged == true
              ? 'reopen-after-fullscreen-exit-surface-change'
              : 'resume-after-fullscreen-ui-roundtrip',
        );
      }
      await recordContextStep(phase: 'observed');
    } catch (error) {
      if (!contextStepRecorded) {
        try {
          await recordContextStep(phase: 'rejected', rejection: error);
        } catch (_) {
          // Keep the original action rejection as the caller-visible error.
        }
      }
      rethrow;
    }
  }

  Duration _lifecycleSafeResumePosition() {
    final position = player.state.position;
    final duration = player.state.duration;
    if (duration <= Duration.zero || duration <= const Duration(seconds: 15)) {
      return position;
    }
    final safeEnd = duration - const Duration(seconds: 15);
    return position > safeEnd ? safeEnd : position;
  }

  Future<void> _exitNativeDvN1Page() => _nativeDvN1Exit ??= () async {
        final startup = _nativeDvSessionStartup;
        if (startup != null) {
          try {
            await startup;
          } catch (_) {}
        }
        await _closeNativeDvSessionAndPlayer();
        await SystemNavigator.pop();
      }();

  Future<void> _runNativeDvN4Experiment() async {
    final transport = _nativeDvN4;
    if (transport == null || !transport.ready || _nativeDvN4Closing) {
      throw StateError('N4 requires actual accepted native P5 callbacks');
    }
    setState(() => _nativeDvN4Status =
        'N4 raw Player.open pending; waiting for settled result');
    final execution = transport.execute();
    _nativeDvN4Execution = execution;
    AndroidNativeDvForeignOwnershipResult? result;
    Object? executionError;
    StackTrace? executionStack;
    try {
      result = await execution;
    } catch (error, stack) {
      executionError = error;
      executionStack = stack;
    }
    _nativeDvN4ExecutionResult = result;
    _nativeDvN4ExecutionError = executionError;
    _nativeDvN4ExecutionStack = executionStack;
    if (mounted) {
      setState(() => _nativeDvN4Status = result?.foreignFileLoadedMatched ==
              true
          ? 'N4 settled; close to persist final report; device acceptance pending'
          : 'N4 settled without matched foreign FILE_LOADED; close to persist report');
    }
  }

  void _startNativeDvN4Experiment() {
    if (_nativeDvN4ExecutionReport != null || _nativeDvN4Closing) return;
    final attempt = _runNativeDvN4Experiment();
    _nativeDvN4ExecutionReport = attempt;
    unawaited(attempt.catchError((Object error, StackTrace stack) {
      _nativeDvN4ExecutionError ??= error;
      _nativeDvN4ExecutionStack ??= stack;
      debugPrint('N4_EXECUTION_ERROR $error');
      if (mounted) {
        setState(() => _nativeDvN4Status =
            'N4 execution settled with error; close to persist final report');
      }
    }));
  }

  Future<void> _writeNativeDvN4Report({
    required String executionStatus,
    AndroidNativeDvForeignOwnershipResult? result,
    Object? executionError,
    StackTrace? executionStack,
    List<Map<String, Object?>>? drainedJournal,
    List<AndroidNativeDvN4PageCloseError> closeErrors =
        const <AndroidNativeDvN4PageCloseError>[],
    bool? playerTerminationSucceeded,
  }) async {
    final transport = _nativeDvN4;
    final session = transport?.session ?? _hdrSession;
    final disposeReport = session?.lastDisposeReport;
    final errors = transport?.run.rawErrors ??
        result?.rawErrors ??
        const <AndroidNativeDvForeignOwnershipRawError>[];
    final journal =
        drainedJournal == null || (drainedJournal.isEmpty && result != null)
            ? result?.journal ?? drainedJournal ?? const []
            : drainedJournal;
    final payload = <String, Object?>{
      'schema': 1,
      'experiment': 'android-native-dv-session-foreign-ownership-n4',
      'runId': _nativeDvN4RunId,
      'transport': result?.transport ?? 'real-player-callback',
      'status': executionStatus,
      'playerTerminationSucceeded': playerTerminationSucceeded,
      'sourceUri': androidNativeDvSessionDiagnosticSource,
      'sourceSha256ExternalClaim':
          androidNativeDvSessionLifecycleP5ExpectedSha256,
      'sourceSha256Scope':
          'external verified fixture claim; app did not recompute source bytes',
      'externalIdentityLabel': _androidNativeDvReleaseDiagnosticIdentity,
      'sessionInstanceId': transport?.sessionInstanceId,
      'playerIdentity': identityHashCode(player),
      'sessionIdentity': session == null ? null : identityHashCode(session),
      'sessionGeneration': session?.report.value.generation,
      'result': result == null
          ? null
          : <String, Object?>{
              'n4ExecutionAdmitted': result.n4ExecutionAdmitted,
              'foreignFileLoadedMatched': result.foreignFileLoadedMatched,
              'sameSessionGenerationAfterForeign':
                  result.sameSessionGenerationAfterForeign,
              'sameForeignIdentityAfterSessionDispose':
                  result.sameForeignIdentityAfterSessionDispose,
              'optionsUnchangedAcrossSessionDispose':
                  result.optionsUnchangedAcrossSessionDispose,
              'lastDisposeReportClean': result.lastDisposeReportClean,
              'coordinatorErrorType': result.coordinatorErrorType,
              'coordinatorErrorText': result.coordinatorErrorText,
              'sessionDisposeThrownType':
                  result.sessionDisposeThrown?.runtimeType.toString(),
              'sessionDisposeThrownText':
                  result.sessionDisposeThrown?.toString(),
              'sessionDebtObserved': result.sessionDebtObserved,
              'ownershipStopRefusalObserved':
                  result.ownershipStopRefusalObserved,
              'noSessionOpenOrConfigureAfterForeign':
                  result.noSessionOpenOrConfigureAfterForeign,
              'controllerRetiredObserved': result.controllerRetiredObserved,
              'playerTerminated': result.playerTerminated,
              'playerDisposeErrorType':
                  result.playerDisposeError?.runtimeType.toString(),
              'playerDisposeErrorText': result.playerDisposeError?.toString(),
              'ownerRestoration': result.ownerRestoration,
              'backendStopIssued': result.backendStopIssued,
              'backendStopIssuedBasis': result.backendStopIssuedBasis,
              'boundOutputWithdrawnObserved':
                  result.boundOutputWithdrawnObserved,
              'boundOutputHandleBeforeDispose':
                  result.boundOutputHandleBeforeDispose,
              'boundOutputGenerationBeforeDispose':
                  result.boundOutputGenerationBeforeDispose,
              'boundOutputViewIdBeforeDispose':
                  result.boundOutputViewIdBeforeDispose,
              'boundOutputWidBeforeDispose': result.boundOutputWidBeforeDispose,
              'boundOutputHandleAfterDispose':
                  result.boundOutputHandleAfterDispose,
              'boundOutputGenerationAfterDispose':
                  result.boundOutputGenerationAfterDispose,
              'boundOutputViewIdAfterDispose':
                  result.boundOutputViewIdAfterDispose,
              'boundOutputWidAfterDispose': result.boundOutputWidAfterDispose,
              'n4DeviceAcceptance': result.n4DeviceAcceptance,
              'acceptedByHostEvidence': result.acceptedByHostEvidence,
              'executionErrorType': (executionError ?? result.executionError)
                  ?.runtimeType
                  .toString(),
              'executionErrorText':
                  (executionError ?? result.executionError)?.toString(),
              'executionStack':
                  (executionStack ?? result.executionStack)?.toString(),
              'evidenceGaps': result.evidenceGaps,
              'rawErrors': [
                for (final error in errors)
                  {
                    'index': error.index,
                    'phase': error.phase,
                    'property': error.property,
                    'type': error.error.runtimeType.toString(),
                    'text': error.error.toString(),
                    'stack': error.stackTrace?.toString(),
                  }
              ],
              'journal': journal,
              'overflow': result.overflow,
              'rawErrorOverflow': result.rawErrorOverflow,
            },
      'sessionDisposeReport': disposeReport == null
          ? null
          : <String, Object?>{
              'clean': disposeReport.clean,
              'coordinatorErrorType':
                  disposeReport.coordinatorError?.runtimeType.toString(),
              'coordinatorErrorText':
                  disposeReport.coordinatorError?.toString(),
              'playerErrorType':
                  disposeReport.playerError?.runtimeType.toString(),
              'playerErrorText': disposeReport.playerError?.toString(),
              'directoryErrorType':
                  disposeReport.directoryError?.runtimeType.toString(),
              'directoryErrorText': disposeReport.directoryError?.toString(),
              'retainedDirectory': disposeReport.retainedDirectory,
            },
      if (result == null) 'journal': journal,
      'finalCloseErrors': [for (final error in closeErrors) error.toJson()],
      'executionErrorType':
          (executionError ?? result?.executionError)?.runtimeType.toString(),
      'executionErrorText':
          (executionError ?? result?.executionError)?.toString(),
      'executionStack': (executionStack ?? result?.executionStack)?.toString(),
    };
    final publishedReport = await writeAndroidNativeDvN4ExternalReport(
      externalStorageDirectoryProvider:
          path_provider.getExternalStorageDirectory,
      runId: _nativeDvN4RunId,
      payload: payload,
    );
    _nativeDvN4ReportPath = publishedReport.path;
  }

  Future<void> _closeNativeDvN4Owned() {
    _nativeDvN4Closing = true;
    _autoPlayerDisposed = true;
    _nativeDvN4?.stopAdmission();
    return _nativeDvN4CloseSequence.closeAndPersist(
      closeAdmission: () => _nativeDvN4?.stopAdmission(),
      waitStartup: () async {
        final startup = _nativeDvSessionStartup;
        if (startup != null) await startup;
      },
      waitExecution: () async {
        final executionReport = _nativeDvN4ExecutionReport;
        if (executionReport != null) await executionReport;
        final execution = _nativeDvN4Execution;
        if (execution != null) await execution;
      },
      result: () => _nativeDvN4ExecutionResult,
      closeDiagnostic: () async {
        await _nativeDvSessionDiagnostic?.close(
          cleanup: 'N4 explicit exit; raw Player.open must settle first',
        );
      },
      closeHelper: () async {
        final transport = _nativeDvN4;
        if (transport == null) {
          await _closeNativeDvSessionAndPlayer();
        } else {
          await transport.close();
        }
      },
      cancelEvents: () async {
        await _nativeDvN4Events?.cancel();
      },
      drain: () async {
        final transport = _nativeDvN4;
        if (transport == null) return const <Map<String, Object?>>[];
        return transport.drain();
      },
      playerTerminationSucceeded: androidNativeDvN4PlayerTerminationSucceeded,
      terminationError: (result) {
        if (result?.playerDisposeError != null) {
          return result!.playerDisposeError;
        }
        for (final raw in _nativeDvN4?.run.rawErrors.reversed ??
            const <AndroidNativeDvForeignOwnershipRawError>[]) {
          if (raw.phase == 'player-dispose-threw') return raw.error;
        }
        return null;
      },
      terminationStack: (result) {
        if (result?.playerDisposeStack != null) {
          return result!.playerDisposeStack;
        }
        for (final raw in _nativeDvN4?.run.rawErrors.reversed ??
            const <AndroidNativeDvForeignOwnershipRawError>[]) {
          if (raw.phase == 'player-dispose-threw') return raw.stackTrace;
        }
        return null;
      },
      persistFinalReport: (snapshot) async {
        final explicitRun = _nativeDvN4ExecutionReport != null;
        await _writeNativeDvN4Report(
          executionStatus: explicitRun
              ? snapshot.result == null
                  ? 'execution-error'
                  : 'settled'
              : 'closed-without-explicit-test',
          result: snapshot.result,
          executionError: _nativeDvN4ExecutionError,
          executionStack: _nativeDvN4ExecutionStack,
          drainedJournal: snapshot.journal,
          closeErrors: snapshot.errors,
          playerTerminationSucceeded: snapshot.playerTerminationSucceeded,
        );
        if (mounted) {
          setState(() {
            _nativeDvN4Status = snapshot.playerTerminationSucceeded
                ? 'N4 final report saved; Player termination confirmed'
                : 'N4 final report saved; Player termination failed, exit held';
          });
        }
      },
    );
  }

  Future<void> _exitNativeDvN4Page() {
    _nativeDvN4Closing = true;
    _autoPlayerDisposed = true;
    _nativeDvN4?.stopAdmission();
    return _nativeDvN4Exit ??= _nativeDvN4CloseSequence
        .exit(
      closeAndPersist: _closeNativeDvN4Owned,
      pop: SystemNavigator.pop,
    )
        .catchError((Object error, StackTrace stack) {
      if (mounted) {
        setState(() =>
            _nativeDvN4Status = 'N4 finalization failed; exit held: $error');
      }
      Error.throwWithStackTrace(error, stack);
    });
  }

  Future<void> _samplePlaybackPerformance() async {
    final sampler = _playbackPerformance;
    final negative = _nativeDvN1;
    final epoch = _playbackPerformanceEpoch;
    if (sampler == null ||
        negative == null ||
        epoch == null ||
        _autoPlayerDisposed) {
      return;
    }
    final attempt = () async {
      try {
        final result = await sampler.sample(
            expectedSource: androidNativeDvSessionDiagnosticSource,
            expectedFileLoadedEpoch: epoch,
            expectedVo: 'gpu-next',
            expectedHwdecCurrent: 'mediacodec-copy');
        if (result.accepted) {
          negative.record('performance-sample', {'sample': result.row});
        } else {
          negative.record('performance-sample-rejected', {
            'reason': result.reason,
            'identityBefore': result.identityBefore,
            'identityAfter': result.identityAfter,
          });
        }
        for (final raw in result.rawErrors) {
          negative.record(
              'performance-property-error',
              {
                'index': raw.index,
                'row': raw.row,
                'phase': raw.phase,
                'property': raw.property,
                'acceptedSample': result.accepted,
              },
              error: raw.error,
              stack: raw.stackTrace);
        }
        if (sampler.rawErrorOverflow) {
          negative.record('performance-error-overflow', {});
        }
      } catch (error, stack) {
        negative.record('performance-sample-failed', {},
            error: error, stack: stack);
      }
    }();
    _playbackPerformanceSample = attempt;
    try {
      await attempt;
    } finally {
      if (identical(_playbackPerformanceSample, attempt)) {
        _playbackPerformanceSample = null;
      }
    }
  }

  Future<void> _closeNativeDvSessionAndPlayer() async {
    if (_nativeDvPlayerTerminationAttempted) return;
    _nativeDvPlayerTerminationAttempted = true;
    _autoPlayerDisposed = true;
    _playbackPerformanceTimer?.cancel();
    await _playbackPerformanceSample;
    await _playbackPerformance?.drain();
    final diagnostic = _nativeDvSessionDiagnostic;
    final session = _hdrSession;
    final negative = _nativeDvN1;
    final outcome = await AndroidNativeDvSessionTermination.run(
      closeRecorder: () async {
        if (negative == null) {
          await diagnostic?.close(cleanup: 'explicit close-and-exit');
        }
      },
      disposeSession: () async {
        await session?.dispose();
      },
      capturePostSession: (sessionDisposeError) async {
        if (negative != null) {
          await negative.captureCleanup(
              player: player,
              report: session?.lastDisposeReport,
              error: sessionDisposeError,
              controller: session?.controller.value);
          if (!negative.sessionClean) {
            throw StateError('N1 Session cleanup has debt');
          }
          return;
        }
        final restored = await diagnostic?.capturePostSessionCleanup(
          report: session?.lastDisposeReport,
          sessionDisposeError: sessionDisposeError,
          sessionInstanceId: _nativeDvSessionInstanceId,
        );
        if (diagnostic != null && restored != true) {
          throw StateError('Actual Session restoration did not match baseline');
        }
      },
      recordCaptureError: (error) async {
        if (negative != null) {
          negative.record('cleanup-failed', {}, error: error);
          negative.debt = true;
          return;
        }
        await diagnostic?.recordCleanupCaptureError(error);
      },
      disposePlayer: player.dispose,
      recordPlayerTermination: (error) async {
        if (negative != null) {
          await negative.recordTermination(error);
          return;
        }
        await diagnostic?.recordPlayerTermination(error: error);
      },
      markDebt: (reason) {
        if (negative != null) {
          negative.debt = true;
          negative.record('cleanup-debt', {'reason': reason});
        } else {
          _nativeDvSessionLifecycleRun?.markDebt(reason);
        }
      },
    );
    if (negative != null) {
      await _nativeDvN1Events?.cancel();
      await negative.close();
    }
    if (!outcome.clean) {
      throw StateError(
          'Termination failed: recorder=${outcome.recorderCloseError} '
          'session=${outcome.sessionDisposeError} '
          'capture=${outcome.cleanupCaptureError} '
          'player=${outcome.playerDisposeError} '
          'terminationReport=${outcome.terminationRecordError}');
    }
  }

  Widget _buildNativeDvLifecycleControls() {
    final run = _nativeDvSessionLifecycleRun;
    if (run == null) return const SizedBox.shrink();
    return ValueListenableBuilder<String>(
      valueListenable: run.status,
      builder: (context, status, _) {
        final current = run.currentActionId == null
            ? ''
            : ' · ${run.currentActionId}/${run.currentRequestId}';
        final labels = <String, String>{
          'close-and-exit': 'Close & exit',
          'Pause10Resume': 'Pause 10s / resume',
          'ManualResume': 'Resume playback (10s)',
          'Seek90Then30': 'Seek 90s then 30s',
          'Reopen40Then10': 'Reopen 40s then 10s',
          'P5SDRP5': 'P5 → SDR → P5',
          'RestoreSurface': 'Restore Surface',
          'FullscreenRoundTrip': 'Fullscreen round trip',
          'RecreateSession': 'Recreate Session',
        };
        final controls = <Widget>[];
        for (final actionId in androidNativeDvSessionLifecycleActions) {
          final enabled = _nativeDvSessionPageExit.actionEnabled(run, actionId,
              terminationAttempted: _nativeDvPlayerTerminationAttempted);
          controls.add(Semantics(
            label: 'dv-session-action:$actionId',
            button: true,
            enabled: enabled,
            child: OutlinedButton(
              onPressed: enabled
                  ? () => unawaited(
                        _runNativeDvSessionLifecycleAction(actionId).catchError(
                          (Object error, StackTrace stack) {
                            debugPrint('NATIVE_DV_LIFECYCLE_ACTION_ERROR '
                                'action=$actionId error=$error');
                          },
                        ),
                      )
                  : null,
              child: Text(labels[actionId] ?? actionId),
            ),
          ));
        }
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(top: 6),
          padding: const EdgeInsets.all(8),
          color: Colors.black.withValues(alpha: 0.82),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'run=${run.runId} · ${run.elapsed.inSeconds}/${run.durationSeconds}s · '
                'rows=${run.rows.length}/$androidNativeDvSessionLifecycleMaxRows · '
                'segments=${run.segments.length}/$androidNativeDvSessionLifecycleMaxSegments',
                style: const TextStyle(color: Colors.white70, fontSize: 11),
              ),
              Text(
                'state=$status$current · terminal=${run.terminal} · debt=${run.debt}',
                style: TextStyle(
                  color: run.debt ? Colors.redAccent : Colors.white,
                  fontSize: 12,
                ),
              ),
              if (_nativeDvSessionActionError != null)
                Text(_nativeDvSessionActionError!,
                    style: const TextStyle(color: Colors.redAccent)),
              Wrap(spacing: 6, runSpacing: 2, children: controls),
            ],
          ),
        );
      },
    );
  }

  String? _validateNativeDvReleaseDiagnosticBuild() {
    if (!_androidNativeDvReleaseDiagnostic) return null;
    if (!Platform.isAndroid) {
      return 'Release native DV diagnostic is Android-only';
    }
    if (!_autoSinglePlayer ||
        _androidHdrTransaction ||
        configuration.value.android.usePlatformView != true ||
        configuration.value.vo != 'mediacodec_embed' ||
        player.configuration.async == false) {
      return 'Requires one-player direct PlatformView, no HDR Session, and asynchronous native Player';
    }
    if (_androidAutoSecondSource.isNotEmpty ||
        _androidAutoSecondSourceAtSeconds > 0 ||
        _androidRecoverySources.isNotEmpty ||
        _androidOpenOnTap ||
        _androidPreopenFullscreen ||
        _androidDualPlayerView ||
        _androidDualViewLifecycleProbe ||
        _androidVerboseLog ||
        _androidCodecTraceLog ||
        _androidVulkanProbe ||
        _androidOpenPhaseTrace ||
        _androidDirectOpenTrace) {
      return 'Conflicting source, lifecycle, or high-volume logging probe is enabled';
    }
    if (sources.length != 1 ||
        sources.single != androidNativeDvReleaseDiagnosticSource) {
      return 'MEDIA_KIT_ANDROID_LOCAL_SOURCE must be the fixed verified LG P5 path';
    }
    if (_androidNativeDvReleaseDiagnosticIdentity.trim().isEmpty) {
      return 'A candidate identity label is required for external artifact binding';
    }
    try {
      validateAndroidNativeDvReleaseDiagnosticSeconds(
        _androidNativeDvReleaseDiagnosticSeconds,
      );
      validateAndroidNativeDvReleaseDiagnosticIntervalSeconds(
        _androidNativeDvReleaseDiagnosticIntervalSeconds,
      );
    } on RangeError catch (error) {
      return '$error';
    }
    return null;
  }

  Future<void> _startNativeDvReleaseDiagnostic() async {
    final rejected = _nativeDvReleaseDiagnosticBuildError;
    if (rejected != null) throw StateError(rejected);
    if (_hdrSession != null) {
      throw StateError(
          'Release native DV diagnostic cannot use HdrVideoSession');
    }
    final diagnostic = await _nativeDvPageAdmission
        .createAfterReady<AndroidNativeDvReleaseDiagnostic>(
      output: controller.platform.future,
      waitUntilReady: (output) => output.waitUntilInitialOutputBound,
      pageIsAlive: () => mounted && !_autoPlayerDisposed,
      create: (output) {
        if (output is! AndroidVideoController ||
            !identical(output.player, player)) {
          throw StateError(
              'A bound AndroidVideoController for this Player is required');
        }
        final value = AndroidNativeDvReleaseDiagnostic(
          player: player,
          outputController: output,
          durationSeconds: _androidNativeDvReleaseDiagnosticSeconds,
          sampleIntervalSeconds:
              _androidNativeDvReleaseDiagnosticIntervalSeconds,
          externalIdentityLabel: _androidNativeDvReleaseDiagnosticIdentity,
        );
        _nativeDvReleaseDiagnostic = value;
        if (mounted && !_autoPlayerDisposed) setState(() {});
        return value;
      },
    );
    if (diagnostic == null) return;
    if (!_nativeDvPageAdmission.isOpen || !mounted || _autoPlayerDisposed) {
      await diagnostic.shutdown();
      return;
    }
    try {
      await diagnostic.start();
    } catch (error) {
      try {
        await diagnostic.shutdown();
      } catch (restoreError) {
        throw StateError('$error; shutdown restore debt: $restoreError');
      }
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // HdrVideoSession path (migrated to HdrVideoSession (S10))
  // ---------------------------------------------------------------------------

  HdrVideoSession _requireHdrSession() {
    final session = _hdrSession;
    if (session == null) {
      throw StateError('HDR session is not available');
    }
    return session;
  }

  /// Creates the session that owns the transaction path. Phase 1 constraint:
  /// one session per process (the HdrCapabilities.Changed enable is a shared
  /// switch), which the single-player page satisfies.
  void _createHdrSession({String? lifecycleSessionInstanceId}) {
    if (_hdrSession != null) return;
    final policy = _hdrRoutingPolicy();
    if (_androidLgVisual278Experiment) {
      final random = Random.secure();
      _lgExperimentOwner = AndroidLgSingleOpenOwner(List.generate(
              24, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'))
          .join());
    }
    final experimentConfiguration = configuration.value.copyWith(
        android: configuration.value.android
            .copyWith(lgExperimentOwnerToken: _lgExperimentToken));
    // migrated to HdrVideoSession (S10): the lab coordinator/slot/backend are
    // replaced by the library session. The public constructor cannot inject a
    // capability provider, so the simulate-no-HLG switch uses the
    // @visibleForTesting constructor to wrap one (see the S10 report).
    final lifecycleId =
        lifecycleSessionInstanceId ?? _nativeDvSessionInstanceId;
    final diagnostic = _nativeDvSessionDiagnostic;
    final n4 = _androidNativeDvSessionForeignOwnershipN4
        ? AndroidNativeDvN4PageTransport(
            player: player,
            source: androidNativeDvSessionDiagnosticSource,
            currentSource: () => _hdrCurrentSource ?? '',
            run: AndroidNativeDvSessionForeignOwnershipRun(
              player: player,
              verifiedP5Source: androidNativeDvSessionDiagnosticSource,
              transport: 'real-player-callback',
            ),
          )
        : null;
    late final HdrVideoSession session;
    void onBackendCall(HdrBackendCallDiagnostic<HdrOpenPlan> event) {
      _nativeDvN1?.onBackendCall(event);
      n4?.onBackendCall(
        callbackSession: session,
        sessionInstanceId: lifecycleId,
        diagnostic: event,
      );
    }

    void onNativeOption(HdrNativeDvOptionDiagnostic event) {
      _nativeDvN1?.onNativeOption(event);
      n4?.onNativeOption(
        callbackSession: session,
        sessionInstanceId: lifecycleId,
        diagnostic: event,
      );
    }

    if (_androidHdrConvertRouteLock) {
      if (AndroidSurfaceTexturePoc.enabled) {
        _surfaceTextureExperiment.validateAdmission(
            dataSpacePerformProbe: _androidDataSpacePerformProbe);
      } else {
        _convertExperiment.validateAdmission(
            dataSpacePerformProbe: _androidDataSpacePerformProbe);
      }
      if (!_androidHdrTransaction ||
          _androidNativeDvSessionDiagnostic ||
          _androidHdrSimulateNoHlg ||
          _androidVfFullRange ||
          _androidHdrGateOpen ||
          _androidHdrPolicyExperimental) {
        throw StateError(
            'Convert route lock rejects conflicting diagnostic modes');
      }
    }
    session = _androidHdrConvertRouteLock
        ? // Lab-only planner rejects initial SDR, retries and review replans.
        // ignore: invalid_use_of_visible_for_testing_member
        HdrVideoSession.forTesting(
            player: player,
            policy: policy,
            configuration: experimentConfiguration,
            // SurfaceTexture PoC: the planner must realize the overridden
            // route; the legacy copy validator would block it.
            routePlanner: AndroidSurfaceTexturePoc.enabled
                ? _surfaceTextureExperiment.plan
                : _convertExperiment.plan,
          )
        : _androidNativeDvSessionDiagnostic
            ? // The only diagnostic seam is a realizer-backed fixed-P5 planner
            // and a passive observer; backend/capabilities/identity stay real.
            // ignore: invalid_use_of_visible_for_testing_member
            HdrVideoSession.forTesting(
                player: player,
                policy: policy,
                configuration: configuration.value,
                routePlanner: diagnostic!.routePlanner,
                onBackendCallDiagnostic: onBackendCall,
                onNativeDvOptionDiagnostic: onNativeOption,
                onNativeDvConsumerValidated: (generation, plan, facts) {
                  diagnostic.onNativeDvConsumerValidated(
                    generation,
                    plan,
                    facts,
                    sessionInstanceId: lifecycleId,
                  );
                  n4?.onConsumerValidated(
                    callbackSession: session,
                    sessionInstanceId: lifecycleId,
                    generation: generation,
                    plan: plan,
                    facts: facts,
                  );
                },
                onNativeDvConsumerCaptureError: (error, stack) =>
                    diagnostic.onNativeDvConsumerCaptureError(
                  error,
                  stack,
                  sessionInstanceId: lifecycleId,
                ),
              )
            : _androidHdrSimulateNoHlg
                ? // The public constructor cannot inject a capability provider; the
                // S10 plan explicitly allows the @visibleForTesting constructor for
                // this experiment switch (A3 simulate-no-HLG).
                // ignore: invalid_use_of_visible_for_testing_member
                HdrVideoSession.forTesting(
                    player: player,
                    policy: policy,
                    configuration: configuration.value,
                    capabilitiesProvider: _capabilitiesWithoutHlg,
                  )
                : HdrVideoSession(
                    player,
                    policy: policy,
                    configuration: configuration.value,
                  );
    _hdrSession = session;
    if (n4 != null) {
      n4.bindSession(session, lifecycleId);
      _nativeDvN4 = n4;
      _nativeDvN4Events = session.events.listen((event) {
        n4.onSessionEvent(
          callbackSession: session,
          sessionInstanceId: lifecycleId,
          event: event,
        );
        if (event is HdrRouteAppliedEvent && mounted) setState(() {});
      });
    }
    // Follow controller replacements (Texture ↔ PlatformView topology
    // switches) the way the old output slot's publish callback did.
    session.controller.addListener(_onHdrControllerChanged);
    session.report.addListener(_onHdrReportChanged);
    final sessionExperimentOwner = _lgExperimentOwner;
    session.events.listen((event) {
      _hdr10Journal?.recordEvent(event);
      if (sessionExperimentOwner != null && event is HdrErrorEvent) {
        unawaited(sessionExperimentOwner
            .revoke(_revokeLgExperiment)
            .catchError((Object error) {
          debugPrint('LG_EXPERIMENT_REVOKE_ERROR $error');
        }));
      }
      debugPrint('HDR_SESSION_EVENT $event');
    });
  }

  void _onHdrControllerChanged() {
    final negative = _nativeDvN1;
    if (negative != null) {
      _nativeDvSessionVideoMounted =
          negative.observeController(_hdrSession?.controller.value);
    }
    if (mounted) setState(() {});
  }

  void _onHdrReportChanged() {
    _logHdrSessionReport();
  }

  /// The routing policy from the A6 experiment switch: defaults, or
  /// allowExperimental with `metadataReshape` first for the P8.4 class.
  HdrRoutingPolicy _hdrRoutingPolicy() {
    if (_androidHdrGateOpen) {
      debugPrint('HDR_GATE_OPEN default order, allowExperimental=true');
      return const HdrRoutingPolicy(allowExperimental: true);
    }
    if (_androidHdrPreferConvert) {
      // HLG→PQ color-accuracy experiment: prefer the GPU convert route over
      // the (systemically desaturated on HLG-incapable panels) direct one
      // for the P8.4 class. Verified-only; no experimental admission.
      final base = HdrRoutingPolicy.defaultPreferences[HdrSourceClass.dvP84] ??
          const <HdrStrategy>[];
      final reordered = <HdrStrategy>[
        HdrStrategy.baseLayerConvert,
        ...base.where((strategy) => strategy != HdrStrategy.baseLayerConvert),
      ];
      debugPrint('HDR_PREFER_CONVERT dvP84=$reordered');
      return HdrRoutingPolicy(
        preferences: <HdrSourceClass, List<HdrStrategy>>{
          HdrSourceClass.dvP84: reordered,
        },
      );
    }
    if (!_androidHdrPolicyExperimental) return HdrRoutingPolicy.defaults;
    final base = HdrRoutingPolicy.defaultPreferences[HdrSourceClass.dvP84] ??
        const <HdrStrategy>[];
    final reordered = <HdrStrategy>[
      HdrStrategy.metadataReshape,
      ...base.where((strategy) => strategy != HdrStrategy.metadataReshape),
    ];
    debugPrint('HDR_POLICY_EXPERIMENTAL dvP84=$reordered');
    return HdrRoutingPolicy(
      preferences: <HdrSourceClass, List<HdrStrategy>>{
        HdrSourceClass.dvP84: reordered,
      },
      allowExperimental: true,
    );
  }

  /// Capability provider wrapper for the simulate-no-HLG switch (A3): the
  /// real query with display type 3 (HLG) removed, so P8.4 cannot select an
  /// HLG-output route and must degrade along the candidate list.
  Future<HdrCapabilities> _capabilitiesWithoutHlg() async {
    final capabilities = await HdrCapabilities.query(player: player);
    final types = capabilities.displayHdrTypes;
    final Set<int>? filtered = types == null ? null : <int>{...types};
    if (filtered != null) {
      filtered.remove(HdrOutputPolicy.displayHdrTypeHlg);
    }
    debugPrint('HDR_CAP_SIMULATE_NO_HLG before=$types after=$filtered');
    return HdrCapabilities(
      sdkInt: capabilities.sdkInt,
      displayHdrTypes: filtered,
      hevcDecoders: capabilities.hevcDecoders,
      dolbyVisionDecoders: capabilities.dolbyVisionDecoders,
      p5PipelineAvailable: capabilities.p5PipelineAvailable,
      dataSpaceBridgeLoaded: capabilities.dataSpaceBridgeLoaded,
      dataSpaceExt: capabilities.dataSpaceExt,
    );
  }

  /// The open hint for [source], built from the page's sample enumeration:
  /// the controlled fixture regex and the SDR control literal map to source
  /// descriptors; the wrong-hint/no-hint switches override both (A4).
  HdrSourceDescriptor? _hintFor(String source) {
    if (_androidNativeDvSessionDiagnostic &&
        source == androidNativeDvSessionDiagnosticSource) {
      return HdrSourceDescriptor.fromKind(HdrMediaKind.dolbyVisionP5);
    }
    if (_androidHdrNoHint) return null;
    switch (_androidHdrWrongHint) {
      case '':
        break;
      case 'sdr':
        return HdrSourceDescriptor.fromKind(HdrMediaKind.sdr);
      case 'hdr10':
        return HdrSourceDescriptor.fromKind(HdrMediaKind.hdr10);
      case 'p84':
        return HdrSourceDescriptor.fromKind(HdrMediaKind.dolbyVisionP84);
      default:
        throw StateError(
            'MEDIA_KIT_ANDROID_HDR_WRONG_HINT must be sdr, hdr10 or p84');
    }
    final match = _namedFixturePattern.firstMatch(source);
    if (match != null) {
      switch (match.group(1)) {
        case 'hdr10':
          return HdrSourceDescriptor.fromKind(HdrMediaKind.hdr10);
        case 'hlg':
          return HdrSourceDescriptor.fromKind(HdrMediaKind.hlg);
        case 'p84':
          return HdrSourceDescriptor.fromKind(HdrMediaKind.dolbyVisionP84);
        case 'p5':
          return HdrSourceDescriptor.fromKind(HdrMediaKind.dolbyVisionP5);
      }
    }
    if (source == _sdrControlSource) {
      return HdrSourceDescriptor.fromKind(HdrMediaKind.sdr);
    }
    // Unknown source: no hint; the session classifies from decoder facts.
    return null;
  }

  /// One open generation through the session (migrated to HdrVideoSession
  /// (S10): the coordinator/backend open path is replaced by the session's
  /// orchestrated open — hint pre-routing, decoder review with at most one
  /// in-place rebuild, candidate degradation along the list).
  Future<void> _openHdrSource(
    String source, {
    Duration? start,
  }) async {
    if (_androidHdr10SessionDiagnostic &&
        source != androidHdr10DiagnosticSource) {
      throw StateError('HDR10 journal rejects sources other than fixed PQ');
    }
    if (_androidNativeDvSessionDiagnostic &&
        source != androidNativeDvSessionDiagnosticSource &&
        !(_androidNativeDvSessionLifecycleActions &&
            (source == androidNativeDvSessionLifecycleP5Path ||
                source == androidNativeDvSessionLifecycleSdrPath))) {
      throw StateError(
          'Session diagnostic rejects all sources except fixed P5');
    }
    final experimentOwner = _lgExperimentOwner;
    final session = _requireHdrSession();
    final serial = ++_hdrOpenSerial;
    _hdrCurrentSource = source;
    try {
      Future<void> prepare() async {
        await _applyAndroidVideoTimingOffset();
        await _applyAndroidScalers();
        if (_androidVfFullRange) {
          throw StateError(
              'VF_FULL_RANGE is not an output range conversion; use MPV_OUTPUT_LEVELS');
        }
        if (_androidMpvOutputLevels.isNotEmpty) {
          if (_androidHdrConvertRouteLock) {
            if (AndroidSurfaceTexturePoc.enabled) {
              await _surfaceTextureExperiment.prepareOutputLevels(
                set: (value) =>
                    player.setPropertyStrict('video-output-levels', value),
                read: () => player.getProperty('video-output-levels'),
              );
            } else {
              await _convertExperiment.prepareOutputLevels(
                set: (value) =>
                    player.setPropertyStrict('video-output-levels', value),
                read: () => player.getProperty('video-output-levels'),
              );
            }
          } else {
            await player.setPropertyStrict(
                'video-output-levels', _androidMpvOutputLevels);
            final levels = await player.getProperty('video-output-levels');
            if (levels != _androidMpvOutputLevels) {
              throw StateError('Output levels not accepted: $levels');
            }
          }
          debugPrint(
              'MPV_OUTPUT_LEVELS=$_androidMpvOutputLevels accepted=true beforeOpen=true');
        }
        if (_androidLgVisual278Experiment) {
          if (AndroidSurfaceTexturePoc.enabled) {
            _surfaceTextureExperiment.validateAdmission(
                dataSpacePerformProbe: _androidDataSpacePerformProbe);
          } else {
            _convertExperiment.validateAdmission(
                dataSpacePerformProbe: _androidDataSpacePerformProbe);
          }
          if (experimentOwner == null) {
            throw StateError('Missing experiment owner');
          }
          final openToken = experimentOwner.token;
          final openHandle = await player.handle;
          experimentOwner.bindHandle(openHandle);
          final enabled = await const MethodChannel(
                  'media_kit_hdr_lab/lg_visual278_experiment')
              .invokeMethod<bool>('Enable', {
            'routeLocked': _androidHdrConvertRouteLock,
            'acceptNonConformant': true,
            'handle': openHandle,
            'ownerToken': openToken,
          });
          if (enabled != true) {
            throw StateError('Visual278 experiment enable refused');
          }
        }
        if (AndroidSurfaceTextureDiag.enabled &&
            !AndroidSurfaceTexturePoc.enabled) {
          // Copy leg (对照): before the open, after the route decision for
          // this locked transaction is in place, append the signalstats probe
          // to the end of the current vf chain through the backend `_setOwned`
          // convention (owned restore on the open end). PoC on never reaches
          // this leg: the two legs are mutually exclusive.
          await _enableDiagVdLavcO(serial);
          await _enableCopyDiagVf(serial);
        }
      }

      final hint = _hintFor(source);
      if (AndroidSurfaceTexturePoc.enabled) {
        if (AndroidSurfaceTextureDiag.enabled) {
          // OES leg: enable the importer-side small-area readback for this
          // open transaction before the decoder init can emit its per-frame
          // `MKSURF: diag` entries.
          await _enableDiagVdLavcO(serial);
          _enableSurfaceTextureDiagSwitch(serial);
          // E1: arm the producer-commit-boundary dataspace before the open
          // so mpv's one-shot EGL-window injection reads the armed value.
          // YUV mode (define on) arms it fail-closed inside the pre-open
          // sequence below — an unresolvable armer or a failed arm throws
          // (a silently skipped arm would open the NV12 window without the
          // PQ/LIMITED injection = misleading playback); non-YUV mode keeps
          // the original non-blocking arm.
          // YUV diag (define on required): arm the independent config49
          // branch switch before the open so mpv's EGL context/surface
          // creation takes the NV12 path. Fail-closed: a pairing mismatch, a
          // dataspace arm failure or a YUV switch arm failure throws
          // (diagnostic transaction fails) after rolling back every arm
          // taken in this pre-open sequence.
          if (_androidMksYuvDiag) {
            try {
              _armDiagDataspace(serial);
              await _armYuvDiagSwitch(serial);
            } catch (_) {
              _disarmDiagDataspace(serial: null);
              _disarmYuvDiagSwitch(serial: null);
              _disableSurfaceTextureDiagSwitch(serial: null);
              await _disableDiagVdLavcO(serial: null);
              rethrow;
            }
          } else {
            // Diag on + PoC on, but the YUV define is off: only the
            // non-blocking E1 dataspace arm applies.
            _armDiagDataspace(serial);
            debugPrint('YUV-DIAG: define off; branch inert');
          }
        } else if (_androidMksYuvDiag) {
          // PoC on but the SurfaceTexture diag leg is off: the YUV diag arm
          // requires the diag+PoC combination, so the branch stays inert.
          debugPrint('YUV-DIAG: define on but diag leg off; branch inert');
        }
        // Capture the whole open window: the importer emits `MKSURF: version`
        // during decoder init, before the production backend's hwdec-current
        // verification completes inside session.open.
        unawaited(_surfaceTexturePocLogSubscription?.cancel());
        _surfaceTexturePocVersionObserved = false;
        _surfaceTexturePocLogSubscription = player.stream.log.listen((log) {
          if (AndroidSurfaceTexturePoc.isVersionEntry(log.text)) {
            _surfaceTexturePocVersionObserved = true;
          }
        });
      } else if (_androidMksYuvDiag) {
        // PoC off: the YUV diag arm requires the diag+PoC combination, so
        // the branch stays inert.
        debugPrint('YUV-DIAG: define on but PoC off; branch inert');
      }
      debugPrint(
          'ANDROID_HDR_OPEN_BEGIN path=$source hint=$hint serial=$serial '
          'simulateNoHlg=$_androidHdrSimulateNoHlg '
          'wrongHint=$_androidHdrWrongHint noHint=$_androidHdrNoHint '
          'policyExperimental=$_androidHdrPolicyExperimental '
          'namedLocalSource=$_androidNamedLocalSource '
          'p5RpuPipelineBuilt=$_androidP5RpuPipelineBuilt '
          'forceP84PqFallback=$_androidForceP84PqFallback '
          'textureCopyDiagnostic=$_androidTextureCopyDiagnostic '
          'gpuPlatformHdr=$_androidGpuPlatformHdr');
      // The open outcome never short-circuits the PoC verdict below: a
      // bridge init failure can make vd_lavc fall back to software decoding
      // while the session only DEGRADES and keeps playing.
      Object? openFailure;
      StackTrace? openFailureStack;
      try {
        if (experimentOwner != null) {
          await experimentOwner.open(
              session: session,
              media: Media(source),
              hint: hint,
              start: start,
              prepare: prepare,
              revokeOwner: _revokeLgExperiment);
        } else {
          await prepare();
          await session.open(Media(source), hint: hint, start: start);
        }
      } catch (error, stack) {
        openFailure = error;
        openFailureStack = stack;
      }
      if (AndroidSurfaceTexturePoc.enabled &&
          _requireHdrSession().report.value.actual?.strategy ==
              HdrStrategy.baseLayerConvert) {
        // V2 review fix: the override was applied to this open's route, so
        // the verdict applies regardless of the open outcome. The session
        // only DEGRADES on a decoder mismatch (e.g. bridge init failure
        // makes vd_lavc fall back to software decoding with
        // hwdec-current=no and keeps playing); this verdict must hard-fail
        // such opens instead of letting the fallback play. Both evidence
        // requirements are strict: hwdec-current must equal the overridden
        // importer AND `MKSURF: version` must have been observed.
        // V3 review fix: tracks whether the verdict block below completes
        // normally. The verdict-failure StateError (or any other exception
        // out of this block, e.g. the hwdec-current poll) throws past the
        // OES open-end block below, which is the only place the dataspace
        // arm, the readback switch and the vd-lavc-o owned write are reset
        // on the failure path — so every abnormal exit must reset all of
        // them here. The normal pass path deliberately does not: the open
        // keeps the readback switch and the owned vd-lavc-o live for the
        // bounded playback window (open-end block + teardown watch).
        var verdictBlockAborted = true;
        try {
          var hwdecCurrent = '';
          if (openFailure == null) {
            final deadline = DateTime.now().add(const Duration(seconds: 8));
            while (DateTime.now().isBefore(deadline)) {
              hwdecCurrent = await player.getProperty('hwdec-current');
              if (hwdecCurrent.isNotEmpty) break;
              await Future<void>.delayed(const Duration(milliseconds: 50));
            }
          } else {
            // The open failed and the coordinator rolled the backend back;
            // one read only, the original error stays the primary failure.
            hwdecCurrent = await player.getProperty('hwdec-current');
          }
          final failure = AndroidSurfaceTexturePoc.verdictFailure(
            hwdecCurrent: hwdecCurrent,
            versionObserved: _surfaceTexturePocVersionObserved,
          );
          if (failure != null) {
            debugPrint('${AndroidSurfaceTexturePoc.tag} '
                'active-importer-verify-fail $failure');
            if (openFailure == null) {
              // Hard stop: a degraded open keeps playing software-decoded
              // frames otherwise.
              try {
                await player.stop();
              } catch (stopError) {
                debugPrint('${AndroidSurfaceTexturePoc.tag} '
                    'player stop after verify-fail failed: $stopError');
              }
              throw StateError(
                  'SurfaceTexture PoC verification failed: $failure');
            }
          } else if (openFailure == null) {
            debugPrint('${AndroidSurfaceTexturePoc.tag} '
                'active-importer=surfacetexture verified');
          }
          verdictBlockAborted = false;
        } finally {
          unawaited(_surfaceTexturePocLogSubscription?.cancel());
          _surfaceTexturePocLogSubscription = null;
          // V2 P1-3: the verdict-failure StateError below throws past the
          // open-end block, so the YUV arm must be reset here too
          // (idempotent on the success path; the open-end disarm no-ops
          // after this).
          _disarmYuvDiagSwitch(serial: serial);
          if (verdictBlockAborted) {
            // V3 review fix: the remaining pre-open authorizations are
            // released here too (all idempotent, serial: null) so the
            // throw path resets the whole diagnostic arm set instead of
            // leaking the dataspace arm, the readback switch and the
            // vd-lavc-o owned write past the aborted transaction.
            _disarmDiagDataspace(serial: null);
            _disableSurfaceTextureDiagSwitch(serial: null);
            await _disableDiagVdLavcO(serial: null);
          }
        }
      }
      if (AndroidSurfaceTextureDiag.enabled &&
          !AndroidSurfaceTexturePoc.enabled) {
        // Copy leg open end: a failed open releases the owned vf probe before
        // the original error propagates; a successful open starts the bounded
        // 500 ms metadata poll for the transaction's playback window.
        if (openFailure != null) {
          await _disableDiagVdLavcO(serial: serial);
          await _disableCopyDiagVf(serial: serial);
        } else {
          _startCopyDiagPoll(serial);
        }
      }
      if (AndroidSurfaceTextureDiag.enabled &&
          AndroidSurfaceTexturePoc.enabled) {
        // OES leg open end: a failed open turns the readback switch back off
        // before the original error propagates; a successful open starts the
        // bounded teardown watch for the transaction's playback window.
        // E1: the dataspace arm is transaction-scoped — reset to 0 on both
        // the open end and the failure path, mirroring the disable mode; the
        // mpv injection has already consumed the armed value at its EGL
        // window surface creation during this open. YUV diag: same
        // transaction scope — mpv consumed the switch at its EGL context
        // creation during this open.
        if (openFailure != null) {
          unawaited(_disableDiagVdLavcO(serial: serial));
          _disableSurfaceTextureDiagSwitch(serial: serial);
          _disarmDiagDataspace(serial: serial);
          _disarmYuvDiagSwitch(serial: serial);
        } else {
          _startSurfaceTextureDiagWatch(serial);
          _disarmDiagDataspace(serial: serial);
          _disarmYuvDiagSwitch(serial: serial);
        }
      }
      if (openFailure != null) {
        Error.throwWithStackTrace(openFailure, openFailureStack!);
      }
      if (_androidHdrConvertRouteLock) {
        final report = _requireHdrSession().report.value;
        if (report.error != null || report.actual == null) {
          throw StateError(
              'Locked convert experiment did not open: ${report.error}');
        }
      }
      debugPrint('ANDROID_HDR_OPEN path=$source serial=$serial');
      if (serial == _hdrOpenSerial && mounted) {
        _logHdrSessionReport();
      }
      if (_androidOpenPhaseTrace) {
        unawaited(() async {
          final vo = await player.getProperty('vo');
          final hwdec = await player.getProperty('hwdec-current');
          final path = await player.getProperty('path');
          debugPrint(
              'ANDROID_HDR_OUTPUT vo=$vo hwdecCurrent=$hwdec path=$path');
        }()
            .catchError((Object error) {
          debugPrint('ANDROID_HDR_OUTPUT error=$error');
        }));
      }
      if (_androidDualViewLifecycleProbe && !_dualViewProbeScheduled) {
        _dualViewProbeScheduled = true;
        unawaited(_runDualViewLifecycleProbe());
      }
      if (Platform.isAndroid &&
          _androidOutputFailureAtSeconds >= 0 &&
          !_outputFailureScheduled) {
        _outputFailureScheduled = true;
        unawaited(_runOutputFailureRetryProbe());
      }
      if (_androidHdrPauseAtMediaSeconds >= 0) {
        unawaited(() async {
          try {
            final target = Duration(seconds: _androidHdrPauseAtMediaSeconds);
            await player.stream.position
                .firstWhere((position) => position >= target)
                .timeout(
                    Duration(seconds: _androidHdrPauseAtMediaSeconds + 30));
            if (!mounted || serial != _hdrOpenSerial) return;
            await player.pause();
            await player.seek(target);
            await Future<void>.delayed(const Duration(seconds: 1));
            debugPrint(
                'ANDROID_HDR_MEDIA_PAUSE target=${target.inMilliseconds} '
                'timePos=${await player.getProperty('time-pos')} '
                'pause=${await player.getProperty('pause')}');
          } catch (error) {
            debugPrint('ANDROID_HDR_MEDIA_PAUSE error=$error');
          }
        }());
      }
      if (_androidHdrAutoPauseProbeSeconds > 0) {
        unawaited(Future<void>.delayed(
            Duration(seconds: _androidHdrAutoPauseProbeSeconds), () async {
          if (!mounted || serial != _hdrOpenSerial) return;
          await player.pause();
          debugPrint('ANDROID_HDR_AUTO_PAUSE '
              'position=${player.state.position.inMilliseconds} '
              'pause=${await player.getProperty('pause')}');
        }));
      }
    } catch (_) {
      rethrow;
    }
  }

  /// Resolves the bridge .so exports once. `DynamicLibrary.open` returns the
  /// same handle for a library the process already loaded
  /// (PlatformVideoView's constructor hook loaded and initialized it); open
  /// or symbol-lookup failure latches the unavailable state with one
  /// `MKSURF-DIAG: switch unavailable` line and never throws.
  static void Function(int)? _resolveSurfaceTextureDiagSwitch() {
    if (_surfaceTextureDiagSwitchProbed) return _surfaceTextureDiagSwitch;
    _surfaceTextureDiagSwitchProbed = true;
    try {
      final bridge = ffi.DynamicLibrary.open('libmedia_kit_video_hdr_bridge.so');
      _surfaceTextureDiagSwitch = bridge
          .lookupFunction<ffi.Void Function(ffi.Int32), void Function(int)>(
              'mkst_set_diag_enabled');
    } catch (error) {
      _surfaceTextureDiagSwitch = null;
      debugPrint('MKSURF-DIAG: switch unavailable ($error)');
    }
    return _surfaceTextureDiagSwitch;
  }

  /// OES leg only (diag on, PoC on): enables the importer-side small-area
  /// readback for this open transaction. Deliberately does NOT call
  /// `mkst_ensure_init` from this (Dart/native, app-classloader-less)
  /// thread: under the explicit-init contract it is a verify-only probe and
  /// this path never touches it — native init is owner-scoped (the platform
  /// view's `setLgExperimentOwner` runs the explicit init during view
  /// creation, before any playback) and the setter below is a pure atomic
  /// store, safe from any thread and independent of the init state.
  void _enableSurfaceTextureDiagSwitch(int serial) {
    if (_surfaceTextureDiagSerial != null) {
      if (_surfaceTextureDiagSerial == serial) return;
      // A previous transaction still owns the switch; release it first so
      // ownership never doubles.
      unawaited(_disableDiagVdLavcO(serial: null));
      _disableSurfaceTextureDiagSwitch(serial: null);
    }
    final enable = _resolveSurfaceTextureDiagSwitch();
    if (enable == null) return;
    try {
      enable(1);
      _surfaceTextureDiagSerial = serial;
      debugPrint('MKSURF-DIAG: readback switch enabled (OES leg)');
    } catch (error) {
      debugPrint('MKSURF-DIAG: switch unavailable ($error)');
    }
  }

  /// Turns the OES-leg readback switch off. Idempotent; with a non-null
  /// [serial] it only acts while that open still owns the enabled switch.
  void _disableSurfaceTextureDiagSwitch({required int? serial}) {
    _surfaceTextureDiagTimer?.cancel();
    _surfaceTextureDiagTimer = null;
    if (serial != null && serial != _surfaceTextureDiagSerial) return;
    final disable = _surfaceTextureDiagSwitch;
    _surfaceTextureDiagSerial = null;
    if (disable == null) return;
    try {
      disable(0);
    } catch (error) {
      debugPrint('MKSURF-DIAG: disable failed: $error');
    }
  }

  /// E1: resolves the vendor plugin .so exports once. `DynamicLibrary.open`
  /// returns the same handle for a library the process already loaded (the
  /// vendor plugin's Java side loaded it); open or symbol-lookup failure
  /// latches the unavailable state and never throws. The plugin's CMake
  /// target actually produces `libmedia_kit_dataspace_vendor.so`
  /// (`System.loadLibrary("media_kit_dataspace_vendor")`), so the spec'd
  /// `libmedia_kit_android_dataspace_vendor.so` name is tried first and the
  /// real soname second before giving up.
  static void Function(int)? _resolveDiagDataspaceArmer() {
    if (_diagDataspaceArmerProbed) return _diagDataspaceArmer;
    _diagDataspaceArmerProbed = true;
    void lookup(ffi.DynamicLibrary library) =>
        _diagDataspaceArmer = library
            .lookupFunction<ffi.Void Function(ffi.Int32), void Function(int)>(
                'mkvendor_set_diag_dataspace');
    try {
      lookup(ffi.DynamicLibrary.open(
          'libmedia_kit_android_dataspace_vendor.so'));
    } catch (_) {
      try {
        lookup(ffi.DynamicLibrary.open('libmedia_kit_dataspace_vendor.so'));
      } catch (error) {
        _diagDataspaceArmer = null;
        debugPrint('MKSURF-E1: diag dataspace armer unavailable ($error)');
      }
    }
    return _diagDataspaceArmer;
  }

  /// E1, diag on + PoC on only: arms the vendor diag atomic with the
  /// unchanged PQ/LIMITED value before the open. The setter is a pure
  /// atomic store and safe from any thread; mpv consumes it once at its EGL
  /// window surface creation, before the first swap.
  ///
  /// Fail-closed in YUV mode (V3 review fix): the config49 NV12 branch
  /// REQUIRES the PQ/LIMITED dataspace injection, so an unresolvable armer
  /// or a failed arm throws a StateError — a silently skipped arm would
  /// open the YUV window without the armed dataspace (misleading playback),
  /// and the pre-open rollback in the caller releases the arms already
  /// taken. Non-YUV mode keeps the original non-blocking behavior.
  void _armDiagDataspace(int serial) {
    if (_diagDataspaceSerial != null) {
      if (_diagDataspaceSerial == serial) return;
      // A previous transaction still owns the arm; reset it first so
      // ownership never doubles.
      _disarmDiagDataspace(serial: null);
    }
    final armer = _resolveDiagDataspaceArmer();
    if (armer == null) {
      if (_androidMksYuvDiag) {
        throw StateError('MKSURF-E1: diag dataspace armer unavailable; '
            'YUV mode requires the PQ/LIMITED injection to arm');
      }
      return;
    }
    try {
      armer(_diagDataspacePqLimited);
      _diagDataspaceSerial = serial;
      debugPrint('MKSURF-E1: diag dataspace armed 0x11C60000');
    } catch (error) {
      if (_androidMksYuvDiag) {
        throw StateError('MKSURF-E1: diag dataspace arm failed ($error)');
      }
      debugPrint('MKSURF-E1: diag dataspace arm failed ($error)');
    }
  }

  /// E1: resets the vendor diag atomic to 0 (off). Idempotent; with a
  /// non-null [serial] it only acts while that open still owns the arm.
  void _disarmDiagDataspace({required int? serial}) {
    if (serial != null && serial != _diagDataspaceSerial) return;
    _diagDataspaceSerial = null;
    final armer = _diagDataspaceArmer;
    if (armer == null) return;
    try {
      armer(0);
    } catch (error) {
      debugPrint('MKSURF-E1: diag dataspace disarm failed: $error');
    }
  }

  /// YUV diag: resolves the vendor switch export once (same pattern as the
  /// E1 armer above). Fail-closed (V2 P1-3): a missing .so or symbol throws
  /// a StateError so the diagnostic transaction fails instead of silently
  /// playing with the branch inactive.
  static void Function(int)? _resolveYuvDiagSwitch() {
    if (_yuvDiagSwitchProbed) {
      if (_yuvDiagSwitch == null) {
        throw StateError('YUV-DIAG: switch unavailable (probe failed)');
      }
      return _yuvDiagSwitch;
    }
    _yuvDiagSwitchProbed = true;
    void lookup(ffi.DynamicLibrary library) =>
        _yuvDiagSwitch = library
            .lookupFunction<ffi.Void Function(ffi.Int32), void Function(int)>(
                'mkvendor_set_yuv_diag_enabled');
    try {
      lookup(ffi.DynamicLibrary.open(
          'libmedia_kit_android_dataspace_vendor.so'));
    } catch (_) {
      try {
        lookup(ffi.DynamicLibrary.open('libmedia_kit_dataspace_vendor.so'));
      } catch (error) {
        _yuvDiagSwitch = null;
        throw StateError('YUV-DIAG: switch unavailable ($error)');
      }
    }
    return _yuvDiagSwitch;
  }

  /// Resolves the vendor disarm export once (same dual-name lookup as the
  /// switch resolver). Best-effort: any failure latches null and never
  /// throws — the disarm path then falls back to the legacy setter.
  static void Function()? _resolveYuvDiagDisarm() {
    if (_yuvDiagDisarmProbed) return _yuvDiagDisarm;
    _yuvDiagDisarmProbed = true;
    void lookup(ffi.DynamicLibrary library) => _yuvDiagDisarm = library
        .lookupFunction<ffi.Void Function(), void Function()>(
            'mkvendor_disarm_yuv_diag');
    try {
      lookup(ffi.DynamicLibrary.open(
          'libmedia_kit_android_dataspace_vendor.so'));
    } catch (_) {
      try {
        lookup(ffi.DynamicLibrary.open('libmedia_kit_dataspace_vendor.so'));
      } catch (error) {
        _yuvDiagDisarm = null;
        debugPrint('YUV-DIAG: disarm export unavailable ($error)');
      }
    }
    return _yuvDiagDisarm;
  }

  /// YUV diag, define on + PoC on only: arms the independent YUV diag atomic
  /// before the open so mpv's EGL context/surface creation takes the NV12
  /// branch. Pure atomic store, safe from any thread; transaction-scoped.
  /// Fail-closed: a pairing mismatch (P1-1 contract) or an arm failure throws
  /// a StateError — a YUV-diag define that ends in a non-NV12 open is
  /// misleading and must hard-fail the diagnostic transaction.
  ///
  /// Owner-bound arm first (A2 authorization model): when the owner token
  /// and the platform-view generation are available, the arm routes through
  /// the vendor extension's bound overload so it consumes the owner ledger
  /// (pending + registered surface) and records the binding natively. When
  /// either input is unavailable — or the ledger refuses, which is the case
  /// before this owner's first platform-view mount — the legacy unbound
  /// global arm applies and the fallback is logged, never silent. The
  /// generation is observed non-constructively from the session's published
  /// output only; the fallback controller getter is never touched (P8.4 C2).
  Future<void> _armYuvDiagSwitch(int serial) async {
    if (_yuvDiagConvertTransfer != 'pq' || _androidMpvOutputLevels != 'full') {
      throw StateError('YUV-DIAG: pairing rejected '
          '(need CONVERT_SURFACE_TRANSFER=pq + MPV_OUTPUT_LEVELS=full; '
          'got transfer=$_yuvDiagConvertTransfer '
          'levels=$_androidMpvOutputLevels; offscreen full, window limited, '
          'single final-pass packing)');
    }
    if (_yuvDiagSerial != null) {
      if (_yuvDiagSerial == serial) return;
      _disarmYuvDiagSwitch(serial: null);
    }
    final String? ownerToken = _lgExperimentToken;
    final int? ownerGeneration =
        await resolveYuvDiagOwnerGeneration(_hdrSession);
    if (ownerToken != null && ownerGeneration != null) {
      try {
        final bound = await const MethodChannel(
                'media_kit_hdr_lab/lg_visual278_experiment')
            .invokeMethod<bool>('EnableYuvDiag', {
          'ownerToken': ownerToken,
          'generation': ownerGeneration,
        });
        if (bound == true) {
          _yuvDiagSerial = serial;
          debugPrint('YUV-DIAG: switch armed (owner-bound, '
              'generation=$ownerGeneration, config49 NV12 branch, pq/full)');
          return;
        }
        debugPrint('YUV-DIAG: owner-bound arm refused; legacy global arm');
      } catch (error) {
        debugPrint('YUV-DIAG: owner-bound arm unavailable ($error); '
            'legacy global arm');
      }
    } else {
      debugPrint('YUV-DIAG: owner token/generation unavailable; '
          'legacy global arm');
    }
    final arm = _resolveYuvDiagSwitch();
    // Unreachable: the resolver throws instead of returning null, but the
    // explicit check gives flow analysis the non-null promotion.
    if (arm == null) {
      throw StateError('YUV-DIAG: switch unavailable');
    }
    try {
      arm(1);
    } catch (error) {
      throw StateError('YUV-DIAG: arm failed ($error)');
    }
    _yuvDiagSerial = serial;
    debugPrint('YUV-DIAG: switch armed (config49 NV12 branch, pq/full)');
  }

  /// YUV diag: resets the YUV diag atomic to 0 (off). Idempotent; with a
  /// non-null [serial] it only acts while that open still owns the arm.
  void _disarmYuvDiagSwitch({required int? serial}) {
    if (serial != null && serial != _yuvDiagSerial) return;
    _yuvDiagSerial = null;
    // Prefer the disarm export: same flag + binding + format-record reset in
    // one call, with the bound-disarm log line.
    final disarm = _resolveYuvDiagDisarm();
    if (disarm != null) {
      try {
        disarm();
        debugPrint('YUV-DIAG: switch disarmed');
      } catch (error) {
        debugPrint('YUV-DIAG: disarm failed: $error');
      }
      return;
    }
    // Legacy fallback: the setter ALSO clears the owner binding (and the
    // format record) on the current vendor library — comment drift fixed
    // (A5 V2): the earlier note claiming the binding persists was written
    // before the legacy entry started resetting the tuple, and the binding
    // is 0/0 after this fallback too. Logged so the fallback path is
    // explicit.
    final legacy = _yuvDiagSwitch ?? _resolveYuvDiagSwitch();
    // Unreachable: the resolver throws instead of returning null.
    if (legacy == null) return;
    try {
      legacy(0);
      debugPrint('YUV-DIAG: switch disarmed (legacy setter; '
          'binding tuple reset to 0/0)');
    } catch (error) {
      debugPrint('YUV-DIAG: disarm failed: $error');
    }
  }

  /// OES-leg teardown watch: 500 ms cadence, no per-tick work beyond the
  /// transaction re-check; turns the readback switch off (bounded to one
  /// open transaction) on page disposal, a superseding open or end of
  /// playback.
  void _startSurfaceTextureDiagWatch(int serial) {
    _surfaceTextureDiagTimer?.cancel();
    _surfaceTextureDiagTimer =
        Timer.periodic(const Duration(milliseconds: 500), (timer) {
      final superseded = serial != _hdrOpenSerial;
      if (!mounted ||
          _autoPlayerDisposed ||
          superseded ||
          player.state.completed ||
          _surfaceTextureDiagSerial == null) {
        timer.cancel();
        _disableSurfaceTextureDiagSwitch(serial: superseded ? null : serial);
      }
    });
  }

  /// Copy leg only (diag on, PoC off): appends the unlabeled signalstats
  /// filter to the end of the current vf chain through an owned write
  /// following the backend `_setOwned` convention (capture, write strict,
  /// read back to verify). Unlike `_setOwned`, an empty captured `vf` is a
  /// valid original (a chain without filters) and is restored as an empty
  /// chain; a chain that already carries signalstats is left untouched so the
  /// probe is never duplicated.
  Future<void> _enableCopyDiagVf(int serial) async {
    if (_copyDiagVfOwned) {
      if (serial == _copyDiagSerial) return;
      // A previous transaction still owns the chain; release it before this
      // open appends its own probe so ownership never doubles.
      await _disableCopyDiagVf(serial: null);
    }
    final original = await player.getProperty('vf');
    if (original.contains('signalstats')) {
      debugPrint('MKSURF-COPY-DIAG: vf already carries signalstats; '
          'append skipped');
      return;
    }
    final updated =
        original.isEmpty ? _copyDiagVfFilter : '$original,$_copyDiagVfFilter';
    await player.setPropertyStrict('vf', updated);
    final actual = await player.getProperty('vf');
    // mpv normalizes the graph syntax (e.g. lavfi=[signalstats] becomes
    // lavfi=graph=signalstats); verify semantically, not by string equality.
    if (!actual.contains('signalstats')) {
      throw StateError('vf rejected: requested=$updated actual=$actual');
    }
    _copyDiagOriginalVf = original;
    _copyDiagSerial = serial;
    _copyDiagVfOwned = true;
  }

  /// Releases the copy-leg owned vf write and stops the metadata poll.
  /// Idempotent; with a non-null [serial] it only acts while that open still
  /// owns the write, so a superseding transaction's own probe stays intact.
  Future<void> _disableCopyDiagVf({required int? serial}) async {
    _copyDiagTimer?.cancel();
    _copyDiagTimer = null;
    if (!_copyDiagVfOwned) return;
    if (serial != null && serial != _copyDiagSerial) return;
    final original = _copyDiagOriginalVf ?? '';
    _copyDiagVfOwned = false;
    _copyDiagOriginalVf = null;
    _copyDiagSerial = null;
    try {
      await player.setPropertyStrict('vf', original);
      final actual = await player.getProperty('vf');
      if (actual != original) {
        debugPrint('MKSURF-COPY-DIAG: vf restore mismatch '
            'requested=$original actual=$actual');
      }
    } catch (error) {
      debugPrint('MKSURF-COPY-DIAG: vf restore failed: $error');
    }
  }

  /// Diagnostics vd-lavc-o ownership (both legs). Mirror of the copy-leg
  /// owned write: capture (empty is the valid original), strict write,
  /// read-back verify; an already-set original is never overridden (logged,
  /// skipped, non-blocking).
  Future<void> _enableDiagVdLavcO(int serial) async {
    if (_diagVdLavcOOwned) {
      if (serial == _diagVdLavcOSerial) return;
      await _disableDiagVdLavcO(serial: null);
    }
    final original = await player.getProperty('vd-lavc-o');
    if (original.isNotEmpty) {
      debugPrint('MKSURF-DIAG: vd-lavc-o already set ($original); '
          'write skipped');
      return;
    }
    await player.setPropertyStrict('vd-lavc-o', _diagVdLavcOValue);
    final actual = await player.getProperty('vd-lavc-o');
    if (actual != _diagVdLavcOValue) {
      throw StateError('vd-lavc-o rejected: requested=$_diagVdLavcOValue '
          'actual=$actual');
    }
    _diagOriginalVdLavcO = original;
    _diagVdLavcOSerial = serial;
    _diagVdLavcOOwned = true;
  }

  /// Releases the diagnostics vd-lavc-o owned write. Idempotent; with a
  /// non-null [serial] it only acts while that open still owns the write.
  Future<void> _disableDiagVdLavcO({required int? serial}) async {
    if (!_diagVdLavcOOwned) return;
    if (serial != null && serial != _diagVdLavcOSerial) return;
    final original = _diagOriginalVdLavcO ?? '';
    _diagVdLavcOOwned = false;
    _diagOriginalVdLavcO = null;
    _diagVdLavcOSerial = null;
    try {
      await player.setPropertyStrict('vd-lavc-o', original);
      final actual = await player.getProperty('vd-lavc-o');
      if (actual != original) {
        debugPrint('MKSURF-DIAG: vd-lavc-o restore mismatch '
            'requested=$original actual=$actual');
      }
    } catch (error) {
      debugPrint('MKSURF-DIAG: vd-lavc-o restore failed: $error');
    }
  }

  /// Copy-leg metadata poll: 500 ms cadence while this transaction plays.
  /// Every tick re-checks ownership and stops (restoring the owned vf chain)
  /// on page disposal, a superseding open or end of playback, so the poll is
  /// always bounded to one open transaction.
  void _startCopyDiagPoll(int serial) {
    _copyDiagTimer?.cancel();
    _copyDiagTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      final superseded = serial != _hdrOpenSerial;
      if (!mounted ||
          _autoPlayerDisposed ||
          superseded ||
          player.state.completed ||
          !_copyDiagVfOwned) {
        timer.cancel();
        unawaited(_disableCopyDiagVf(serial: superseded ? null : serial));
        return;
      }
      unawaited(_sampleCopyDiag(serial));
    });
  }

  /// One `MKSURF-COPY-DIAG:` sample. Every property is read through the
  /// string path; an unreadable property is logged as null.
  Future<void> _sampleCopyDiag(int serial) async {
    if (serial != _hdrOpenSerial || _copyDiagSampleInFlight) return;
    _copyDiagSampleInFlight = true;
    try {
      final pos = await player.getProperty('time-pos');
      final yavg =
          await player.getProperty('vf-metadata/mksdiag/lavfi.signalstats.YAVG');
      final ymin =
          await player.getProperty('vf-metadata/mksdiag/lavfi.signalstats.YMIN');
      final ymax =
          await player.getProperty('vf-metadata/mksdiag/lavfi.signalstats.YMAX');
      debugPrint('MKSURF-COPY-DIAG: t=${_copyDiagValue(pos)} '
          'yavg=${_copyDiagValue(yavg)} ymin=${_copyDiagValue(ymin)} '
          'ymax=${_copyDiagValue(ymax)}');
    } catch (error) {
      debugPrint('MKSURF-COPY-DIAG: sample failed: $error');
    } finally {
      _copyDiagSampleInFlight = false;
    }
  }

  static String _copyDiagValue(String value) => value.isEmpty ? 'null' : value;

  /// Prints the session report of the current generation with the full
  /// prediction (selected + every candidate) and the actual route — the A2
  /// prediction-consistency evidence and the A1 route/dataspace readback.
  void _logHdrSessionReport() {
    final session = _hdrSession;
    if (session == null) return;
    final report = session.report.value;
    _hdr10Journal?.recordReport(report);
    debugPrint('HDR_SESSION_REPORT gen=${report.generation} '
        'source=${report.source} origin=${report.sourceOrigin?.name} '
        'verified=${report.verified} hwdecCurrent=${report.hwdecCurrent} '
        'dataspace requested=${report.dataSpaceRequested} '
        'path=${report.dataSpacePath} readback=${report.dataSpaceReadback} '
        'degrade=${report.degradeReason?.name} '
        'diagnostic=${report.diagnostic} error=${report.error}');
    final prediction = report.prediction;
    if (prediction != null) {
      debugPrint('HDR_SESSION_PREDICTION gen=${report.generation} '
          'selected=${prediction.selected} '
          'presentation=${prediction.presentation.name} '
          'confidence=${prediction.confidence.name} '
          'playable=${prediction.playable}');
      for (final candidate in prediction.candidates) {
        debugPrint(
            'HDR_SESSION_CANDIDATE gen=${report.generation} candidate=$candidate');
      }
    }
    if (report.actual != null) {
      debugPrint(
          'HDR_SESSION_ACTUAL gen=${report.generation} actual=${report.actual}');
    }
  }

  Future<void> _openDirectSdrAfterHdr(String source) async {
    // migrated to HdrVideoSession (S10): the old coordinator disposal +
    // output-slot reset + direct player.open path is replaced by a session
    // open with the SDR descriptor; the session rebuilds the output topology
    // (Texture SDR) itself. The serial bump invalidates delayed HDR
    // pause/resume callbacks, as the old source-intent invalidation did.
    _hdrOpenSerial++;
    _hdrCurrentSource = source;
    await _requireHdrSession().open(Media(source), hint: _hintFor(source));
    debugPrint('ANDROID_HDR_SDR_RECOVERY_OPEN path=$source '
        'vo=${await player.getProperty('vo')} '
        'hwdec=${await player.getProperty('hwdec-current')}');
    if (mounted) _logHdrSessionReport();
  }

  Future<void> _runDualViewLifecycleProbe() async {
    for (final phase in const [1, 2, 3, 4]) {
      await Future<void>.delayed(const Duration(seconds: 5));
      if (!mounted || _autoPlayerDisposed) return;
      setState(() => _dualViewPhase = phase);
      debugPrint('ANDROID_DUAL_VIEW phase=$phase '
          'position=${player.state.position.inMilliseconds} '
          'playing=${player.state.playing}');
    }
  }

  Future<void> _exitAutoPlayerAfterDisposal() =>
      _autoPlayerExitFuture ??= _exitAutoPlayerAfterDisposalOnce();

  Future<void> _exitAutoPlayerAfterDisposalOnce() async {
    try {
      await _disposeTestPlayer();
      if (Platform.isAndroid &&
          _androidHdrTransaction &&
          _hdrDisposeReportClean != true) {
        throw StateError('Android HDR resource disposal is incomplete');
      }
      debugPrint('ANDROID_AUTO_PLAYER exit player disposed');
      await SystemNavigator.pop();
    } catch (error, stack) {
      debugPrint('ANDROID_AUTO_PLAYER exit blocked: $error');
      debugPrintStack(stackTrace: stack);
      _autoPlayerExitFuture = null;
    }
  }

  Future<void> _openSelectedSource(String source,
      {bool rethrowErrors = false}) async {
    if (_androidNativeDvSessionDiagnostic &&
        source != androidNativeDvSessionDiagnosticSource) {
      throw StateError(
        'Source changes are disabled in the fixed-source Session diagnostic',
      );
    }
    if (_androidNativeDvReleaseDiagnostic) {
      throw StateError(
        'Source changes are disabled in the fixed-source Release diagnostic',
      );
    }
    if (_autoPlayerDisposed) {
      debugPrint('OPEN_SELECTED_SOURCE ignored: player disposal started');
      return;
    }
    try {
      if (Platform.isAndroid &&
          _androidPreopenFirstFrameProbe &&
          !_androidPreopenFullscreen) {
        final started = await _flutterSurfaceProbeChannel
            .invokeMapMethod<String, dynamic>('StartFirstFrameProbe', {
          'target': configuration.value.android.usePlatformView
              ? 'platform'
              : 'flutter',
        });
        debugPrint('FIRST_FRAME_PIXEL_COPY started=$started');
      }
      if (Platform.isAndroid && _androidTapFullscreenBeforeOpen) {
        if (!_androidP5ScopeFullscreen) {
          throw StateError('Tap fullscreen requires VideoFullscreenScope');
        }
        await _toggleDiagnosticFullscreen(
          GlobalObjectKey<VideoState>(_initialController),
        );
        await SchedulerBinding.instance.endOfFrame;
        debugPrint('ANDROID_TAP_FULLSCREEN_LAYOUT_READY');
      }
      if (Platform.isAndroid && _androidHdrTransaction) {
        await _openHdrSource(source);
      } else {
        if (Platform.isAndroid && _androidDirectOpenTrace) {
          debugPrint('ANDROID_DIRECT_OPEN trigger path=$source');
          debugPrint('ANDROID_DIRECT_OPEN media_command');
        }
        if (Platform.isAndroid &&
            !configuration.value.android.usePlatformView) {
          final prepared = await controller.prepareAndroidTextureOutput();
          debugPrint('ANDROID_SELECTED_TEXTURE_PREPARED layoutBound=$prepared');
        }
        await player.open(Media(source));
        if (Platform.isAndroid && _androidDirectOpenTrace) {
          debugPrint('ANDROID_DIRECT_OPEN media_returned');
        }
      }
    } catch (error) {
      if (rethrowErrors) rethrow;
      debugPrint('OPEN_SELECTED_SOURCE error=$error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Cannot open selected video: $error')),
        );
      }
    }
  }

  static const _androidPreDestroyVidStop = bool.fromEnvironment(
    'MEDIA_KIT_ANDROID_PRE_DESTROY_VID_STOP',
  );
  static const _androidPostBindSeekProbe = bool.fromEnvironment(
    'MEDIA_KIT_ANDROID_POST_BIND_SEEK_PROBE',
  );
  static const _androidPostBindReopenProbe = bool.fromEnvironment(
    'MEDIA_KIT_ANDROID_POST_BIND_REOPEN_PROBE',
  );
  static const _androidHdrLifecyclePositionProbe = bool.fromEnvironment(
    'MEDIA_KIT_ANDROID_HDR_LIFECYCLE_POSITION_PROBE',
  );
  static const _androidHdrAutoResumeProbe = bool.fromEnvironment(
    'MEDIA_KIT_ANDROID_HDR_AUTO_RESUME_PROBE',
  );
  static const _androidHdrAutoPauseProbeSeconds = int.fromEnvironment(
    'MEDIA_KIT_ANDROID_HDR_AUTO_PAUSE_PROBE_SECONDS',
  );
  static const _androidHdrPauseAtMediaSeconds = int.fromEnvironment(
    'MEDIA_KIT_ANDROID_HDR_PAUSE_AT_MEDIA_SECONDS',
    defaultValue: -1,
  );
  bool _preDestroyStopped = false;
  AppLifecycleState _previousLifecycleState = AppLifecycleState.resumed;
  static const _windowChannel = MethodChannel('media_kit_hdr_lab/window');
  static const _videoChannel = MethodChannel(
    'com.alexmercerind/media_kit_video',
  );
  static const _capabilitiesChannel = MethodChannel(
    'media_kit_hdr_lab/capabilities',
  );
  static const _flutterSurfaceProbeChannel = MethodChannel(
    'media_kit_hdr_lab/flutter_surface_probe',
  );
  static const _p5RuntimeGateChannel = MethodChannel(
    'media_kit_hdr_lab/p5_runtime_gate',
  );
  static const _autoOpticalOutputScaleText = String.fromEnvironment(
    'MEDIA_KIT_AUTO_OPTICAL_OUTPUT_SCALE',
    defaultValue: '100',
  );
  static const _autoToneMapping = String.fromEnvironment(
    'MEDIA_KIT_AUTO_TONE_MAPPING',
  );
  static const _autoTexture = bool.fromEnvironment('MEDIA_KIT_AUTO_TEXTURE');
  static const _autoSdr = bool.fromEnvironment('MEDIA_KIT_AUTO_SDR');
  static const _androidAutoSeekAtSeconds = int.fromEnvironment(
    'MEDIA_KIT_ANDROID_AUTO_SEEK_AT_SECONDS',
    defaultValue: -1,
  );
  static const _androidAutoSeekTargetSeconds = int.fromEnvironment(
    'MEDIA_KIT_ANDROID_AUTO_SEEK_TARGET_SECONDS',
    defaultValue: -1,
  );
  static const _androidAutoReopenAfterSeek = bool.fromEnvironment(
    'MEDIA_KIT_ANDROID_AUTO_REOPEN_AFTER_SEEK',
  );
  static const _androidHotSwitchTarget = String.fromEnvironment(
    'MEDIA_KIT_ANDROID_HOT_SWITCH_TARGET',
  );
  static const _androidHotSwitchAtSeconds = int.fromEnvironment(
    'MEDIA_KIT_ANDROID_HOT_SWITCH_AT_SECONDS',
    defaultValue: -1,
  );
  static const _androidEngineDestroyAtSeconds = int.fromEnvironment(
    'MEDIA_KIT_ANDROID_ENGINE_DESTROY_AT_SECONDS',
    defaultValue: -1,
  );
  static const _androidOutputFailureAtSeconds = int.fromEnvironment(
    'MEDIA_KIT_ANDROID_OUTPUT_FAILURE_AT_SECONDS',
    defaultValue: -1,
  );
  static const _androidDualPlayerView = bool.fromEnvironment(
    'MEDIA_KIT_ANDROID_DUAL_PLAYER_VIEW',
  );
  static const _androidDualPlayerSource = String.fromEnvironment(
    'MEDIA_KIT_ANDROID_DUAL_PLAYER_SOURCE',
  );
  bool _autoSeekReopenScheduled = false;
  bool _hotSwitchScheduled = false;
  bool _hotSwitchPingActive = false;
  bool _hotSwitchPingOn = false;
  bool _engineDestroyScheduled = false;
  bool _outputFailureScheduled = false;
  Player? _secondPlayer;
  VideoController? _secondController;
  Future<void>? _secondPlayerSetup;

  /// Creates an independent second player for the dual-player dual-view
  /// probe. Both players must show live frames simultaneously; one shared
  /// player can only ever drive one active surface.
  Future<void> _ensureSecondPlayer() {
    return _secondPlayerSetup ??= () async {
      try {
        final second = Player();
        final secondController = VideoController(
          second,
          configuration: configuration.value,
        );
        await second.setAudioTrack(AudioTrack.no());
        await second.setPlaylistMode(PlaylistMode.loop);
        await second.open(Media(_androidDualPlayerSource));
        debugPrint(
            'ANDROID_DUAL_PLAYER second_open path=$_androidDualPlayerSource '
            'position=${second.state.position}');
        if (!mounted) {
          await second.dispose();
          return;
        }
        setState(() {
          _secondPlayer = second;
          _secondController = secondController;
        });
      } catch (error, stack) {
        debugPrint('ANDROID_DUAL_PLAYER setup error=$error');
        debugPrintStack(stackTrace: stack);
      }
    }();
  }

  static const _engineControlChannel =
      MethodChannel('media_kit_hdr_lab/engine_control');
  static const _autoStartSeconds = String.fromEnvironment(
    'MEDIA_KIT_AUTO_START_SECONDS',
  );
  static const _androidPlayingStartSeconds = String.fromEnvironment(
    'MEDIA_KIT_ANDROID_PLAYING_START_SECONDS',
  );
  static const _androidTargetPrim = String.fromEnvironment(
    'MEDIA_KIT_ANDROID_TARGET_PRIM',
  );
  static const _androidTargetTrc = String.fromEnvironment(
    'MEDIA_KIT_ANDROID_TARGET_TRC',
  );
  static const _androidTargetColorspaceHint = String.fromEnvironment(
    'MEDIA_KIT_ANDROID_TARGET_COLORSPACE_HINT',
  );
  static const _androidSurfaceTransfer = String.fromEnvironment(
    'MEDIA_KIT_ANDROID_SURFACE_TRANSFER',
  );
  static const _androidEglOutputFormat = String.fromEnvironment(
    'MEDIA_KIT_ANDROID_EGL_OUTPUT_FORMAT',
  );
  static const _androidVo = String.fromEnvironment('MEDIA_KIT_ANDROID_VO');
  static const _androidOpenGlSwapInterval = int.fromEnvironment(
    'MEDIA_KIT_ANDROID_OPENGL_SWAPINTERVAL',
    defaultValue: -1,
  );
  static const _androidScale = String.fromEnvironment(
    'MEDIA_KIT_ANDROID_SCALE',
  );
  static const _androidDscale = String.fromEnvironment(
    'MEDIA_KIT_ANDROID_DSCALE',
  );
  static const _androidCscale = String.fromEnvironment(
    'MEDIA_KIT_ANDROID_CSCALE',
  );
  static const _androidLavcThreads = String.fromEnvironment(
    'MEDIA_KIT_ANDROID_VD_LAVC_THREADS',
  );
  static const _androidVideoLatencyHacks = bool.fromEnvironment(
    'MEDIA_KIT_ANDROID_VIDEO_LATENCY_HACKS',
  );
  static const _androidDisableDiskCache = bool.fromEnvironment(
    'MEDIA_KIT_ANDROID_DISABLE_DISK_CACHE',
  );
  static const _androidNoMediaProbe = bool.fromEnvironment(
    'MEDIA_KIT_ANDROID_NO_MEDIA_PROBE',
  );
  static const _androidSameSurfaceRebindProbe = bool.fromEnvironment(
    'MEDIA_KIT_ANDROID_SAME_SURFACE_REBIND_PROBE',
  );
  static const _androidVulkanProbe = bool.fromEnvironment(
    'MEDIA_KIT_ANDROID_VULKAN_PROBE',
  );
  static const _androidVerboseLog = bool.fromEnvironment(
    'MEDIA_KIT_ANDROID_VERBOSE_LOG',
  );
  static const _androidCodecTraceLog = bool.fromEnvironment(
    'MEDIA_KIT_ANDROID_CODEC_TRACE_LOG',
  );
  static const _androidPerfProbe = bool.fromEnvironment(
    'MEDIA_KIT_ANDROID_PERF_PROBE',
  );
  static const _androidLoopSource = bool.fromEnvironment(
    'MEDIA_KIT_ANDROID_LOOP_SOURCE',
  );
  static const _androidTextureConsumerProbe = bool.fromEnvironment(
    'MEDIA_KIT_ANDROID_TEXTURE_CONSUMER_PROBE',
  );
  static const _androidVoSummaryStopSeconds = int.fromEnvironment(
    'MEDIA_KIT_ANDROID_VO_SUMMARY_STOP_SECONDS',
  );
  static const _androidVideoTimingOffset = String.fromEnvironment(
    'MEDIA_KIT_ANDROID_VIDEO_TIMING_OFFSET',
  );

  Future<void> _applyAndroidVideoTimingOffset() async {
    if (!Platform.isAndroid || _androidVideoTimingOffset.isEmpty) return;
    final offset = double.tryParse(_androidVideoTimingOffset);
    if (offset == null || offset < 0 || offset > 1) {
      throw StateError('Video timing offset must be 0..1 seconds');
    }
    await player.setProperty('video-timing-offset', _androidVideoTimingOffset);
    final actual = await player.getProperty('video-timing-offset');
    if ((double.tryParse(actual.toString()) ?? double.nan) != offset) {
      throw StateError('Video timing offset rejected: $actual');
    }
    debugPrint('ANDROID_VIDEO_TIMING_OFFSET=$actual');
  }

  Future<void> _applyAndroidScalers() async {
    if (!Platform.isAndroid) return;
    for (final entry in <String, String>{
      if (_androidScale.isNotEmpty) 'scale': _androidScale,
      if (_androidDscale.isNotEmpty) 'dscale': _androidDscale,
      if (_androidCscale.isNotEmpty) 'cscale': _androidCscale,
      if (_androidLavcThreads.isNotEmpty)
        'vd-lavc-threads': _androidLavcThreads,
    }.entries) {
      await player.setProperty(entry.key, entry.value);
      final actual = await player.getProperty(entry.key);
      if (actual.toString() != entry.value) {
        throw StateError(
            'Android scaler property ${entry.key} rejected: $actual');
      }
      debugPrint('ANDROID_SCALER ${entry.key}=$actual');
    }
  }

  static const _androidFlutterRepaintProbe = bool.fromEnvironment(
    'MEDIA_KIT_ANDROID_FLUTTER_REPAINT_PROBE',
  );
  static const _androidFrameSchedulerProbe = bool.fromEnvironment(
    'MEDIA_KIT_ANDROID_FRAME_SCHEDULER_PROBE',
  );
  static const _androidP5CodecProbePath = String.fromEnvironment(
    'MEDIA_KIT_ANDROID_P5_CODEC_PROBE_PATH',
  );
  static const _androidP5CodecProbeMaxFrames = int.fromEnvironment(
    'MEDIA_KIT_ANDROID_P5_CODEC_PROBE_MAX_FRAMES',
    defaultValue: 250,
  );
  static const _androidP5CodecSurfaceProbe = bool.fromEnvironment(
    'MEDIA_KIT_ANDROID_P5_CODEC_SURFACE_PROBE',
  );
  static const _androidP5CodecCpuReadProbe = bool.fromEnvironment(
    'MEDIA_KIT_ANDROID_P5_CODEC_CPU_READ_PROBE',
  );
  static const _androidP5CodecGpuImportProbe = bool.fromEnvironment(
    'MEDIA_KIT_ANDROID_P5_CODEC_GPU_IMPORT_PROBE',
  );
  static const _androidP5CodecReaderWidth = int.fromEnvironment(
    'MEDIA_KIT_ANDROID_P5_CODEC_READER_WIDTH',
  );
  static const _androidP5CodecReaderHeight = int.fromEnvironment(
    'MEDIA_KIT_ANDROID_P5_CODEC_READER_HEIGHT',
  );
  static const _androidP5CodecReaderMaxImages = int.fromEnvironment(
    'MEDIA_KIT_ANDROID_P5_CODEC_READER_MAX_IMAGES',
  );
  static const _androidP5CodecNativeReaderProbe = bool.fromEnvironment(
    'MEDIA_KIT_ANDROID_P5_CODEC_NATIVE_READER_PROBE',
  );
  static const _androidP5CodecDeferredAcquireProbe = bool.fromEnvironment(
    'MEDIA_KIT_ANDROID_P5_CODEC_DEFERRED_ACQUIRE_PROBE',
  );
  static const _androidP5CodecHoldPreviousImageProbe = bool.fromEnvironment(
    'MEDIA_KIT_ANDROID_P5_CODEC_HOLD_PREVIOUS_IMAGE_PROBE',
  );
  static const _androidP84BaseLayerProbe = bool.fromEnvironment(
    'MEDIA_KIT_ANDROID_P84_BASE_LAYER_PROBE',
  );
  static const _androidP84DoviFilter = String.fromEnvironment(
    'MEDIA_KIT_ANDROID_P84_DOVI_FILTER',
    defaultValue: 'no',
  );
  bool _compactWindow = false;
  bool _inplaceFullscreen = false;
  bool _autoPlayerDisposed = false;
  Future<void>? _autoPlayerDisposeFuture;
  Timer? _flutterRepaintTimer;
  Timer? _androidP5CounterTimer;
  bool _androidP5CounterInFlight = false;
  int _flutterRepaintTick = 0;
  int _flutterPostFrameCount = 0;
  int _flutterRasterTimingCount = 0;
  int _lastBuildLoggedTick = -1;
  final GlobalKey _tickReadbackKey = GlobalKey();
  bool _tickReadbackInFlight = false;

  Future<void> _sampleAndroidP5Counters() async {
    if (!mounted || _androidP5CounterInFlight) return;
    _androidP5CounterInFlight = true;
    try {
      final values = <String, String>{};
      for (final name in const [
        'time-pos',
        'frame-drop-count',
        'decoder-frame-drop-count',
        'mistimed-frame-count',
        'vo-delayed-frame-count',
        'avsync',
      ]) {
        try {
          values[name] = await player.getProperty(name);
        } catch (error) {
          values[name] = 'ERROR:$error';
        }
      }
      debugPrint('ANDROID_P5_COUNTERS $values');
    } finally {
      _androidP5CounterInFlight = false;
    }
  }

  Future<void> _readbackTick(int tick) async {
    if (_tickReadbackInFlight) return;
    _tickReadbackInFlight = true;
    try {
      final boundary = _tickReadbackKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 1.0);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      if (bytes == null) return;
      var hash = 2166136261;
      for (final byte in bytes.buffer.asUint8List()) {
        hash = ((hash ^ byte) * 16777619) & 0xffffffff;
      }
      debugPrint(
          'FLUTTER_TICK_READBACK tick=$tick hash=${hash.toRadixString(16)}');
      try {
        final pixelCopyHash = await _flutterSurfaceProbeChannel
            .invokeMethod<String>('CopyVideoPixels');
        debugPrint('FLUTTER_VIDEO_PIXEL_COPY tick=$tick hash=$pixelCopyHash');
      } catch (error) {
        debugPrint('FLUTTER_VIDEO_PIXEL_COPY tick=$tick error=$error');
      }
    } catch (error) {
      debugPrint('FLUTTER_TICK_READBACK tick=$tick error=$error');
    } finally {
      _tickReadbackInFlight = false;
    }
  }

  void _frameTimingsCallback(List<FrameTiming> timings) {
    _flutterRasterTimingCount += timings.length;
  }

  late final Player player = Player(
    configuration: PlayerConfiguration(
      logLevel: _androidCodecTraceLog
          ? MPVLogLevel.trace
          : (_androidVulkanProbe ||
                  _androidVerboseLog ||
                  _androidHdr10SessionDiagnostic)
              ? MPVLogLevel.v
              : MPVLogLevel.error,
    ),
  );
  late final VideoController _initialController = VideoController(
    player,
    configuration: configuration.value,
  );
  VideoController get controller => _hdrTransactionController;

  VideoController get _hdrTransactionController =>
      Platform.isAndroid && _androidHdrTransaction
          ? _hdrSession?.controller.value ?? _initialController
          : _initialController;

  Future<Map<String, Object?>?> _androidServiceProbeSurfaceSnapshot() async {
    final controller = _hdrTransactionController;
    if (!controller.platform.isCompleted) return null;
    final platform = await controller.platform.future;
    if (!mounted || !identical(controller, _hdrTransactionController)) {
      return null;
    }
    final rect = platform.rect.value;
    return {
      'id': platform.id.value,
      'rect': rect == null
          ? null
          : {
              'left': rect.left,
              'top': rect.top,
              'width': rect.width,
              'height': rect.height,
            },
      'nativeHandle': platform.nativeHandle,
      'topologyGeneration': platform.nativeSurfaceGeneration,
      'nativeSurfaceActive': platform.nativeSurfaceActive,
      'nativeSurfaceCandidate': platform.nativeSurfaceCandidate,
      'type': platform.runtimeType.toString(),
    };
  }

  @override
  void initState() {
    super.initState();
    AndroidHdrConvertExperiment.validateVisual278Admission(
        enabled: _androidLgVisual278Experiment,
        routeLocked: _androidHdrConvertRouteLock,
        android: Platform.isAndroid,
        hdrTransaction: _androidHdrTransaction);
    if (_androidLgVisual278Experiment &&
        (_androidDualPlayerView ||
            _androidDualViewLifecycleProbe ||
            _androidP5ScopeFullscreen ||
            _androidP5InplaceFullscreen ||
            _androidP5AutoFullscreenAtSeconds >= 0)) {
      throw StateError(
          'LG visual278 experiment excludes multi-output/fullscreen modes');
    }
    if (_androidHdrConvertRouteLock &&
        (!Platform.isAndroid ||
            !_androidHdrTransaction ||
            _androidOpenOnTap ||
            _androidPreopenFullscreen ||
            _androidNoMediaProbe)) {
      throw StateError(
          'Convert route lock requires the Android Session open path');
    }
    if ((_androidMpvOutputLevels.isNotEmpty || _androidVfFullRange) &&
        !_androidHdrTransaction) {
      throw StateError('Output range experiments require HDR_TRANSACTION');
    }
    if (_androidHdr10SessionDiagnostic) {
      _hdr10BuildError = _validateHdr10DiagnosticBuild();
      if (_hdr10BuildError != null) return;
      final journal = AndroidHdrSessionDiagnostic(
        label: _androidHdr10DiagnosticIdentity,
        readProperty: (name) =>
            player.getProperty(name, waitForInitialization: false),
        readEpoch: () => player.fileLoadedEpoch,
        readIdentity: _hdr10ReadIdentity,
        withPlayerLock: (work) => player.lock.synchronized(work),
      );
      _hdr10Journal = journal;
      _hdr10CodecLogSubscription = player.stream.log.listen(
        (log) {
          journal.recordCodecFormatLog(
              prefix: log.prefix, level: log.level, text: log.text);
        },
        onError: (Object error, StackTrace stack) =>
            journal.recordError(error, stack),
      );
      final startup = _startHdr10Diagnostic();
      _hdr10Startup = startup;
      unawaited(startup.then<void>((_) {},
          onError: (Object error, StackTrace stack) async {
        journal.recordError(error, stack);
        _hdr10BuildError ??= '$error';
        try {
          await journal.writeNow();
        } catch (_) {/* retained by journal */}
        if (mounted) setState(() {});
      }));
      return;
    }
    if (_androidNativeDvSessionDiagnostic ||
        _androidNativeDvSessionNegativeN1 ||
        _androidNativeDvSessionForeignOwnershipN4 ||
        _androidPlaybackPerformance) {
      _nativeDvSessionDiagnosticError =
          _validateNativeDvSessionDiagnosticBuild();
      if (_nativeDvSessionDiagnosticError != null) return;
      if (_androidNativeDvSessionNegativeN1) {
        _nativeDvN1 = AndroidNativeDvN1Run(
            externalIdentityLabel: _androidNativeDvReleaseDiagnosticIdentity,
            durationSeconds: _androidNativeDvReleaseDiagnosticSeconds);
        _nativeDvSessionVideoMounted = false;
      }
      if (_androidNativeDvSessionLifecycleActions) {
        final lifecycle = AndroidNativeDvSessionLifecycleRun(
          durationSeconds: _androidNativeDvSessionLifecycleSeconds,
          externalIdentityLabel: _androidNativeDvReleaseDiagnosticIdentity,
        );
        for (final actionId in androidNativeDvSessionLifecycleActions) {
          lifecycle.setActionEnabled(actionId, false,
              reason: 'startup segment not yet accepted');
        }
        _nativeDvSessionStateSubscriptions.addAll(<StreamSubscription<bool>>[
          player.stream.playing
              .listen((_) => _refreshNativeDvSessionLifecycleActions()),
          player.stream.completed
              .listen((_) => _refreshNativeDvSessionLifecycleActions()),
          player.stream.buffering
              .listen((_) => _refreshNativeDvSessionLifecycleActions()),
        ]);
        _nativeDvSessionLifecycleRun = lifecycle;
      }
      final diagnostic = AndroidNativeDvSessionDiagnostic(
        player: player,
        durationSeconds: _androidNativeDvSessionLifecycleActions
            ? _androidNativeDvSessionLifecycleSeconds
            : _androidNativeDvReleaseDiagnosticSeconds,
        intervalSeconds: _androidNativeDvReleaseDiagnosticIntervalSeconds,
        externalIdentityLabel: _androidNativeDvReleaseDiagnosticIdentity,
        lifecycleRun: _nativeDvSessionLifecycleRun,
      );
      _nativeDvSessionDiagnostic = diagnostic;
      final startup = _startNativeDvSessionDiagnostic();
      _nativeDvSessionStartup = startup;
      unawaited(startup.then<void>((_) {
        if (identical(_nativeDvSessionStartup, startup)) {
          _nativeDvSessionStartup = null;
        }
      }, onError: (Object error, StackTrace stack) {
        if (identical(_nativeDvSessionStartup, startup)) {
          _nativeDvSessionStartup = null;
        }
        _nativeDvSessionDiagnosticError = '$error';
        _nativeDvSessionLifecycleRun?.markDebt('startup failed: $error');
        debugPrint('NATIVE_DV_SESSION_DIAGNOSTIC_START_ERROR=$error');
        if (mounted) setState(() {});
      }));
      if (_androidNativeDvSessionLifecycleActions) {
        WidgetsBinding.instance.addObserver(this);
      }
      return;
    }
    if (_androidNativeDvReleaseDiagnostic) {
      _nativeDvReleaseDiagnosticBuildError =
          _validateNativeDvReleaseDiagnosticBuild();
      final startup = _openInitialSource();
      _nativeDvPageStartupFuture = startup;
      unawaited(startup.then<void>(
        (_) {
          if (identical(_nativeDvPageStartupFuture, startup)) {
            _nativeDvPageStartupFuture = null;
          }
        },
        onError: (Object error, StackTrace stack) {
          if (identical(_nativeDvPageStartupFuture, startup)) {
            _nativeDvPageStartupFuture = null;
          }
          _nativeDvReleaseDiagnosticBuildError ??= '$error';
          debugPrint('NATIVE_DV_RELEASE_DIAGNOSTIC_START_ERROR=$error');
          if (mounted) setState(() {});
        },
      ));
      return;
    }
    AndroidServiceProbe.attach(
        player, (source) => _openSelectedSource(source, rethrowErrors: true),
        report: () => _hdrSession?.report.value.toString(),
        surfaceSnapshot: _androidServiceProbeSurfaceSnapshot);
    if (Platform.isAndroid && _androidHdrTransaction) {
      // migrated to HdrVideoSession (S10): the session owns the HDR open
      // orchestration for the page's lifetime.
      _createHdrSession();
      if (_androidHdrDiagnostics) {
        // R4.3 seven-layer key=value logs (HDR capability/predict/classify/
        // decision/readback/degrade/recover) on top of the page's own
        // HDR_SESSION_* report printing.
        HdrOutputDiagnostics.enabled = true;
      }
      if (_androidHdrPreferenceSwapAtSeconds > 0) {
        // A5: mid-playback preference change (auto → off → auto).
        Future<void>.delayed(
          Duration(seconds: _androidHdrPreferenceSwapAtSeconds),
          () async {
            if (!mounted || _autoPlayerDisposed) return;
            await _requireHdrSession().setPreference(HdrOutputPreference.off);
            debugPrint('HDR_PREFERENCE_SWAP off at '
                '${player.state.position.inMilliseconds}ms');
          },
        );
        Future<void>.delayed(
          Duration(seconds: _androidHdrPreferenceSwapAtSeconds * 2),
          () async {
            if (!mounted || _autoPlayerDisposed) return;
            await _requireHdrSession().setPreference(HdrOutputPreference.auto);
            debugPrint('HDR_PREFERENCE_SWAP auto at '
                '${player.state.position.inMilliseconds}ms');
          },
        );
      }
      if (_androidHdrPolicySwapAtSeconds > 0) {
        // A5: mid-playback routing-policy change (defaults ↔ experimental).
        Future<void>.delayed(
          Duration(seconds: _androidHdrPolicySwapAtSeconds),
          () async {
            if (!mounted || _autoPlayerDisposed) return;
            await _requireHdrSession().setPolicy(_hdrRoutingPolicy());
            debugPrint('HDR_POLICY_SWAP at '
                '${player.state.position.inMilliseconds}ms');
          },
        );
      }
    }
    if (Platform.isAndroid &&
        _androidEngineDestroyAtSeconds >= 0 &&
        !_engineDestroyScheduled) {
      _engineDestroyScheduled = true;
      unawaited(_runEngineDestroyProbe());
    }
    if (Platform.isAndroid &&
        _androidDualPlayerView &&
        _androidDualPlayerSource.isNotEmpty) {
      unawaited(_ensureSecondPlayer());
    }
    if (Platform.isAndroid && _androidP5CounterProbe) {
      _androidP5CounterTimer = Timer.periodic(const Duration(seconds: 10), (_) {
        unawaited(_sampleAndroidP5Counters());
      });
    }
    if (Platform.isAndroid && _androidFrameSchedulerProbe) {
      SchedulerBinding.instance.addTimingsCallback(_frameTimingsCallback);
    }
    if (Platform.isAndroid && _androidFlutterRepaintProbe) {
      _flutterRepaintTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _flutterRepaintTick++);
        if (_androidFrameSchedulerProbe) {
          SchedulerBinding.instance.addPostFrameCallback((_) {
            _flutterPostFrameCount++;
            if (_flutterRepaintTick % 10 == 0) {
              unawaited(_readbackTick(_flutterRepaintTick));
            }
          });
        }
        if (_flutterRepaintTick % 5 == 0) {
          debugPrint('FLUTTER_TICK_TIMER $_flutterRepaintTick');
          if (_androidFrameSchedulerProbe) {
            final scheduler = SchedulerBinding.instance;
            debugPrint(
              'FLUTTER_FRAME_PROBE tick=$_flutterRepaintTick '
              'post=$_flutterPostFrameCount raster=$_flutterRasterTimingCount '
              'scheduled=${scheduler.hasScheduledFrame} '
              'enabled=${scheduler.framesEnabled} '
              'phase=${scheduler.schedulerPhase} '
              'lifecycle=${WidgetsBinding.instance.lifecycleState}',
            );
            final playback = player.state;
            debugPrint(
              'PLAYER_STATE_PROBE tick=$_flutterRepaintTick '
              'position=${playback.position.inMilliseconds} '
              'playing=${playback.playing} completed=${playback.completed} '
              'buffering=${playback.buffering} '
              'buffer=${playback.buffer.inMilliseconds}',
            );
          }
        }
      });
    }
    if (Platform.isAndroid &&
        (_androidPreDestroyVidStop ||
            _androidHdrLifecyclePositionProbe ||
            _androidHdrAutoResumeProbe)) {
      WidgetsBinding.instance.addObserver(this);
    }
    _logAndroidCapabilities();
    if (Platform.isAndroid && _androidP5CodecProbePath.isNotEmpty) {
      unawaited(
        const MethodChannel('media_kit_hdr_lab/p5_codec_probe')
            .invokeMapMethod<String, dynamic>('Run', {
          'path': _androidP5CodecProbePath,
          'maxFrames': _androidP5CodecProbeMaxFrames != 250
              ? _androidP5CodecProbeMaxFrames
              : _androidP5CodecSurfaceProbe &&
                      !_androidP5CodecCpuReadProbe &&
                      !_androidP5CodecGpuImportProbe &&
                      !_androidP5CodecNativeReaderProbe
                  ? 32
                  : 250,
          'surfaceMode': _androidP5CodecSurfaceProbe,
          'cpuRead': _androidP5CodecCpuReadProbe,
          'gpuImport': _androidP5CodecGpuImportProbe,
          'readerWidth': _androidP5CodecReaderWidth,
          'readerHeight': _androidP5CodecReaderHeight,
          'readerMaxImages': _androidP5CodecReaderMaxImages,
          'nativeReaderMode': _androidP5CodecNativeReaderProbe,
          'deferredAcquire': _androidP5CodecDeferredAcquireProbe,
          'holdPreviousImage': _androidP5CodecHoldPreviousImageProbe,
        }).then(
          (report) {
            report?.forEach((key, value) {
              if (key == 'surfaceImages' && value is List) {
                for (final image in value) {
                  final serialized = image.toString();
                  for (var offset = 0;
                      offset < serialized.length;
                      offset += 700) {
                    final end = offset + 700 < serialized.length
                        ? offset + 700
                        : serialized.length;
                    debugPrint('P5_CODEC_PROBE image_part=$offset '
                        '${serialized.substring(offset, end)}');
                  }
                }
              } else {
                debugPrint('P5_CODEC_PROBE $key=$value');
              }
            });
          },
          onError: (Object error) => debugPrint('P5_CODEC_PROBE ERROR=$error'),
        ),
      );
    }
    if (Platform.isAndroid &&
        (_androidOpenOnTap || _androidPreopenFullscreen)) {
      debugPrint('ANDROID_DIRECT_OPEN awaiting_tap');
    } else if (Platform.isAndroid && _androidNoMediaProbe) {
      debugPrint('ANDROID_NO_MEDIA_PROBE PlatformView mounted without open');
    } else {
      const autoPauseAtSeconds =
          int.fromEnvironment('MEDIA_KIT_AUTO_PAUSE_AT_SECONDS');
      if (autoPauseAtSeconds > 0) {
        Future<void>.delayed(
          Duration(seconds: autoPauseAtSeconds),
          () async {
            if (!mounted || _autoPlayerDisposed) return;
            await player.pause();
            debugPrint('AUTO_PAUSE_AT position=${player.state.position}');
          },
        );
      }
      if (_androidOutputMaxWidth > 0) {
        unawaited(
            Future<void>.delayed(const Duration(seconds: 6)).then((_) async {
          try {
            // 2:1 source aspect; the width cap keeps supersampling over the
            // 1440-wide panel while halving the GPU pixel load.
            final height = (_androidOutputMaxWidth * 1920 ~/ 3840);
            await player.setProperty('android-surface-size',
                '$_androidOutputMaxWidth' 'x' '$height');
            debugPrint('OUTPUT_MAX_WIDTH=$_androidOutputMaxWidth applied '
                '${_androidOutputMaxWidth}x$height');
          } catch (error) {
            debugPrint('OUTPUT_MAX_WIDTH error=$error');
          }
        }));
      }
      if (_androidMpvTargetPeak.isNotEmpty) {
        unawaited(() async {
          try {
            await player.setProperty('target-peak', _androidMpvTargetPeak);
            debugPrint('MPV_TARGET_PEAK=$_androidMpvTargetPeak');
          } catch (error) {
            debugPrint('MPV_TARGET_PEAK error=$error');
          }
        }());
      }
      if (_androidMpvVoDebug) {
        unawaited(() async {
          try {
            await player.setProperty('msg-level', 'vo=debug');
            debugPrint('MPV_VO_DEBUG enabled');
          } catch (error) {
            debugPrint('MPV_VO_DEBUG error=$error');
          }
        }());
      }
      if (_androidDataSpacePerformProbe) {
        unawaited(Future<void>.delayed(const Duration(seconds: 12)).then((_) {
          const channel =
              MethodChannel('media_kit_hdr_lab/dataspace_perform_probe');
          return channel.invokeMethod<Object>('Run', <String, Object>{
            'dataSpace': 0x09C60000,
            'observeSeconds': 8,
          });
        }).then((value) {
          debugPrint('DATASPACE_PROBE result=$value');
        }, onError: (Object error) {
          debugPrint('DATASPACE_PROBE error=$error');
        }));
      }
      if (_androidAvTrace) {
        Timer.periodic(const Duration(seconds: 2), (timer) {
          if (_autoPlayerDisposed || !mounted) {
            timer.cancel();
            return;
          }
          unawaited(() async {
            try {
              final tracePlayer = player;
              debugPrint(
                  'AVTRACE pos=${await tracePlayer.getProperty('time-pos', waitForInitialization: false)} '
                  'pause=${await tracePlayer.getProperty('pause', waitForInitialization: false)} '
                  'decDrop=${await tracePlayer.getProperty('decoder-frame-drop-count', waitForInitialization: false)} '
                  'voDelayed=${await tracePlayer.getProperty('vo-delayed-frame-count', waitForInitialization: false)} '
                  'frames=${await tracePlayer.getProperty('frame-count', waitForInitialization: false)} '
                  'vbitrate=${await tracePlayer.getProperty('video-bitrate', waitForInitialization: false)} '
                  'cacheDur=${await tracePlayer.getProperty('demuxer-cache-duration', waitForInitialization: false)} '
                  'vfps=${await tracePlayer.getProperty('estimated-vf-fps', waitForInitialization: false)} '
                  'completed=${tracePlayer.state.completed} '
                  'buffering=${tracePlayer.state.buffering}');
            } catch (error) {
              debugPrint('AVTRACE error=$error');
            }
          }());
        });
      }
      if (_androidVoPassesTrace) {
        var voPassesFailures = 0;
        Timer.periodic(const Duration(seconds: 5), (timer) {
          if (_autoPlayerDisposed || !mounted) {
            timer.cancel();
            return;
          }
          unawaited(() async {
            try {
              final passesPlayer = player;
              final passes = await passesPlayer.getProperty('vo-passes',
                  waitForInitialization: false);
              debugPrint('VOPASSES len=${passes.length} $passes');
            } catch (error) {
              voPassesFailures += 1;
              if (voPassesFailures <= 3 || voPassesFailures % 12 == 0) {
                debugPrint('VOPASSES error#$voPassesFailures=$error');
              }
            }
          }());
        });
      }
      unawaited(_openInitialSource()
          .catchError((Object error, StackTrace stack) async {
        debugPrint('AUTO_SOURCE ERROR=$error');
        debugPrintStack(stackTrace: stack);
        if (!Platform.isAndroid ||
            !_androidHdrTransaction ||
            _androidRecoverySources.isEmpty) {
          return;
        }
        for (final source in _androidRecoverySources.split(',')) {
          if (!mounted || source.isEmpty) {
            break;
          }
          try {
            if (source.startsWith('sdr:')) {
              await _openDirectSdrAfterHdr(source.substring(4));
              break;
            }
            await _openHdrSource(source);
            debugPrint('ANDROID_HDR_RECOVERY_OPEN path=$source');
            await Future<void>.delayed(const Duration(seconds: 5));
          } catch (recoveryError, recoveryStack) {
            debugPrint('ANDROID_HDR_RECOVERY_ERROR source=$source '
                'error=$recoveryError');
            debugPrintStack(stackTrace: recoveryStack);
            break;
          }
        }
      }));
    }
    if (const bool.fromEnvironment('MEDIA_KIT_AUTO_RESIZE')) {
      Future<void>.delayed(const Duration(seconds: 6), () {
        _resizeTestWindow(width: 640.0, height: 520.0);
      });
      Future<void>.delayed(const Duration(seconds: 10), () {
        _disposeTestPlayer();
      });
    }
    if (Platform.isAndroid && _androidVoSummaryStopSeconds > 0) {
      Future<void>.delayed(
        Duration(seconds: _androidVoSummaryStopSeconds),
        () async {
          if (!mounted || _autoPlayerDisposed) return;
          debugPrint('ANDROID_VO_SUMMARY_STOP begin');
          try {
            // Release gpu-next while the mpv log bridge is still alive so its
            // one-shot VO summary can be collected before Player disposal.
            await player.setProperty('vo', 'null');
            debugPrint('ANDROID_VO_SUMMARY_STOP vo=null');
          } catch (error) {
            debugPrint('ANDROID_VO_SUMMARY_STOP vo-change ERROR=$error');
          }
          try {
            await _disposeTestPlayer();
          } catch (error) {
            debugPrint('ANDROID_VO_SUMMARY_STOP dispose ERROR=$error');
          }
        },
      );
    }
    player.stream.error.listen((error) => debugPrint(error));
    if (Platform.isAndroid && _androidPerfProbe) {
      player.stream.completed.listen(
        (completed) {
          debugPrint('AUTO_COMPLETED completed=$completed');
          if (completed) unawaited(_sampleAndroidP5Counters());
        },
      );
    }
    player.stream.log.listen(
      (log) => debugPrint(
        'MPVLOG [${log.prefix}] ${log.level}: ${log.text}',
      ),
    );
    player.stream.videoParams.listen(
      (params) => debugPrint('VIDEOPARAMS $params'),
    );
    Future<void>.delayed(const Duration(seconds: 4), () async {
      for (final property in [
        'vo',
        'hwdec-current',
        'path',
        'video-format',
        'video-params',
        'video-out-params',
        'vf',
        'current-tracks/video/dolby-vision-profile',
        'current-tracks/video/dolby-vision-level',
        // Keep the output contract in the same stock-libmpv session as the
        // NativeSurface/Metal samples. These are diagnostic readbacks only;
        // do not infer visible HDR from any one property.
        'target-prim',
        'target-trc',
        'target-colorspace-hint',
        'target-colorspace-hint-strict',
        'gpu-api',
        'gpu-context',
        'target-peak',
        'egl-output-format',
        'android-surface-size',
        'sig-peak',
        'tone-mapping',
      ]) {
        try {
          final value = await player.getProperty(
            property,
            waitForInitialization: false,
          );
          debugPrint('MPVPROP $property=$value');
        } catch (error) {
          debugPrint('MPVPROP $property ERROR=$error');
        }
      }
    });
    if (Platform.isAndroid) {
      // S2 device-round probe: capture the lab's own capabilities channel,
      // the library HdrCapabilities.Get channel and the full library query
      // (including the P5 option probe) in the same session for comparison.
      Future<void>.delayed(const Duration(seconds: 5), () async {
        try {
          final own = await _capabilitiesChannel
              .invokeMapMethod<String, dynamic>('Get');
          debugPrint('HDR_CAP_LAB $own');
        } catch (error) {
          debugPrint('HDR_CAP_LAB ERROR=$error');
        }
        try {
          final lib = await _videoChannel
              .invokeMapMethod<String, dynamic>('HdrCapabilities.Get');
          debugPrint('HDR_CAP_LIB_CHANNEL $lib');
        } catch (error) {
          debugPrint('HDR_CAP_LIB_CHANNEL ERROR=$error');
        }
        try {
          final caps = await HdrCapabilities.query(player: player);
          debugPrint('HDR_CAP_QUERY $caps');
        } catch (error) {
          debugPrint('HDR_CAP_QUERY ERROR=$error');
        }
        if (_androidSurfaceTransfer.isNotEmpty) {
          // S4 device-round probe: the reporting contract alongside the
          // legacy boolean setter, same handle and transfer, ~5s after the
          // player is set up (the platform surface is live by then).
          try {
            final handle = await player.handle;
            final report = await _videoChannel.invokeMapMethod<String, dynamic>(
              'PlatformVideoView.ApplyDataSpace',
              {
                'handle': handle.toString(),
                'transfer': _androidSurfaceTransfer
              },
            );
            debugPrint(
              'ANDROID_APPLY_DATASPACE transfer=$_androidSurfaceTransfer report=$report',
            );
          } catch (error) {
            debugPrint('ANDROID_APPLY_DATASPACE ERROR=$error');
          }
        }
      });
    }
    if (Platform.isAndroid && _androidPerfProbe) {
      for (final second in [
        8,
        18,
        28,
        for (var t = 60; t <= 1200; t += 30) t,
      ]) {
        Future<void>.delayed(Duration(seconds: second), () async {
          if (!mounted || _autoPlayerDisposed) return;
          for (final property in [
            'time-pos',
            'frame-drop-count',
            'decoder-frame-drop-count',
            'avsync',
            'container-fps',
            'pause',
            'eof-reached',
            'idle-active',
          ]) {
            try {
              final value = await player
                  .getProperty(
                    property,
                    waitForInitialization: false,
                  )
                  .timeout(const Duration(seconds: 2));
              debugPrint('PERF t=$second $property=$value');
            } catch (error) {
              debugPrint('PERF t=$second $property ERROR=$error');
            }
          }
          try {
            final status = await _flutterSurfaceProbeChannel
                .invokeMethod<int>('GetThermalStatus')
                .timeout(const Duration(seconds: 2));
            debugPrint('PERF t=$second thermal-status=$status');
          } catch (error) {
            debugPrint('PERF t=$second thermal-status ERROR=$error');
          }
          if (_androidTextureConsumerProbe) {
            try {
              final stats =
                  await _videoChannel.invokeMapMethod<String, dynamic>(
                'VideoOutputManager.GetConsumerStats',
                {'handle': (await player.handle).toString()},
              ).timeout(const Duration(seconds: 2));
              debugPrint('PERF t=$second texture-consumer=$stats');
            } catch (error) {
              debugPrint('PERF t=$second texture-consumer ERROR=$error');
            }
          }
        });
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_androidNativeDvSessionLifecycleActions) {
      final run = _nativeDvSessionLifecycleRun;
      if (run != null) {
        run.recordExternalLifecycleState(
          state: state.name,
          positionMs: player.state.position.inMilliseconds,
          playing: player.state.playing,
          completed: player.state.completed,
          buffering: player.state.buffering,
        );
        _refreshNativeDvSessionLifecycleActions();
      }
    }
    if (Platform.isAndroid &&
        _androidHdrTransaction &&
        _androidHdrAutoResumeProbe) {
      if (_previousLifecycleState == AppLifecycleState.resumed &&
          state == AppLifecycleState.inactive) {
        _hdrResumeOpenSerial = player.state.playing ? _hdrOpenSerial : null;
        debugPrint('ANDROID_HDR_AUTO_RESUME capturedPlaying='
            '${_hdrResumeOpenSerial != null} '
            'position=${player.state.position.inMilliseconds}');
      } else if (state == AppLifecycleState.resumed) {
        final resumeSerial = _hdrResumeOpenSerial;
        _hdrResumeOpenSerial = null;
        if (resumeSerial != null) {
          unawaited(() async {
            if (resumeSerial != _hdrOpenSerial) return;
            // migrated to HdrVideoSession (S10): the old source-intent
            // gate + coordinator.runForCurrent pair is replaced by the open
            // serial guard; the output-bind wait uses the session's current
            // controller.
            final controller = _hdrSession?.controller.value;
            if (controller == null) return;
            final platform = await controller.platform.future;
            await platform.waitUntilCurrentOutputBound
                .timeout(const Duration(seconds: 10));
            if (!mounted || resumeSerial != _hdrOpenSerial) return;
            await player.play();
            debugPrint('ANDROID_HDR_AUTO_RESUME played '
                'position=${player.state.position.inMilliseconds}');
          }()
              .catchError((Object error) {
            debugPrint('ANDROID_HDR_AUTO_RESUME error=$error');
          }));
        }
      }
    }
    if (Platform.isAndroid &&
        _androidHdrTransaction &&
        _androidHdrLifecyclePositionProbe) {
      debugPrint('ANDROID_HDR_LIFECYCLE state=$state '
          'cachedPosition=${player.state.position.inMilliseconds} '
          'playing=${player.state.playing} '
          'time=${DateTime.now().toIso8601String()}');
      unawaited(player
          .getProperty('time-pos', waitForInitialization: false)
          .timeout(const Duration(seconds: 2))
          .then(
              (value) => debugPrint(
                  'ANDROID_HDR_LIFECYCLE_MPV state=$state timePos=$value '
                  'time=${DateTime.now().toIso8601String()}'),
              onError: (Object error) => debugPrint(
                  'ANDROID_HDR_LIFECYCLE_MPV state=$state error=$error')));
    }
    if (Platform.isAndroid && _androidPreDestroyVidStop) {
      debugPrint(
          'LIFECYCLE_STATE $_previousLifecycleState -> $state ${DateTime.now().toIso8601String()}');
    }
    if (Platform.isAndroid &&
        _androidPreDestroyVidStop &&
        _previousLifecycleState == AppLifecycleState.resumed &&
        state == AppLifecycleState.inactive) {
      _preDestroyStopped = true;
      if (_androidHdrTransaction) {
        _previousLifecycleState = state;
        return;
      }
      debugPrint(
          'PRE_DESTROY_VID_STOP begin ${DateTime.now().toIso8601String()}');
      unawaited(player.setProperty('vid', 'no').then((_) {
        debugPrint(
            'PRE_DESTROY_VID_STOP complete ${DateTime.now().toIso8601String()}');
      }, onError: (Object error) {
        debugPrint('PRE_DESTROY_VID_STOP error=$error');
      }));
    }
    if (Platform.isAndroid &&
        (_androidPostBindSeekProbe || _androidPostBindReopenProbe) &&
        state == AppLifecycleState.resumed &&
        _preDestroyStopped) {
      _preDestroyStopped = false;
      final openSerialBeforeResume = _hdrOpenSerial;
      unawaited(
          Future<void>.delayed(const Duration(milliseconds: 700), () async {
        if (!mounted) return;
        if (_androidHdrTransaction &&
            openSerialBeforeResume != _hdrOpenSerial) {
          return;
        }
        final position = player.state.position;
        // migrated to HdrVideoSession (S10): the reopen goes through the
        // session open and the seek is guarded by the open serial that is
        // current for the session the seek targets.
        var seekGuardSerial = openSerialBeforeResume;
        if (_androidPostBindReopenProbe) {
          debugPrint(
              'POST_BIND_REOPEN begin position=$position ${DateTime.now().toIso8601String()}');
          if (_androidHdrTransaction) {
            final source = _hdrCurrentSource;
            if (source == null) {
              throw StateError('No current HDR source to reopen');
            }
            await _openHdrSource(source);
            seekGuardSerial = _hdrOpenSerial;
          } else {
            await player.open(Media(sources[0]));
          }
          await Future<void>.delayed(const Duration(milliseconds: 700));
        }
        debugPrint(
            'POST_BIND_SEEK begin position=$position ${DateTime.now().toIso8601String()}');
        if (_androidHdrTransaction && seekGuardSerial != _hdrOpenSerial) {
          return;
        }
        await player.seek(position);
        debugPrint(
            'POST_BIND_SEEK complete ${DateTime.now().toIso8601String()}');
      }).catchError((Object error) {
        debugPrint('POST_BIND_SEEK error=$error');
      }));
    }
    _previousLifecycleState = state;
  }

  Future<void> _logAndroidCapabilities() async {
    if (!Platform.isAndroid) return;
    try {
      final capabilities =
          await _capabilitiesChannel.invokeMapMethod<String, dynamic>('Get');
      debugPrint('ANDROID_CAPABILITIES $capabilities');
    } catch (error) {
      debugPrint('ANDROID_CAPABILITIES ERROR=$error');
    }
  }

  Map<String, Object> _autoNativeHdrConfiguration() {
    final opticalOutputScale =
        double.tryParse(_autoOpticalOutputScaleText) ?? 100.0;
    final configuration = <String, Object>{
      'transfer': 'pq',
      'masteringMetadata': <String, Object>{
        'minLuminance': 0.005,
        'maxLuminance': 1000.0,
      },
    };
    if (opticalOutputScale != 100.0) {
      configuration['opticalOutputScale'] = opticalOutputScale;
    }
    return configuration;
  }

  Future<void> _openInitialSource() async {
    if (Platform.isAndroid && _androidNativeDvReleaseDiagnostic) {
      await _startNativeDvReleaseDiagnostic();
      return;
    }
    if (Platform.isAndroid && _androidDirectOpenTrace) {
      debugPrint('ANDROID_DIRECT_OPEN trigger path=${sources[0]}');
    }
    if (Platform.isAndroid && _androidHdrTransaction) {
      if (_androidLoopSource) {
        await player.setPlaylistMode(PlaylistMode.single);
        debugPrint('ANDROID_LOOP_SOURCE mode=single '
            'loop-file=${await player.getProperty('loop-file')}');
      }
      final seconds = _androidPlayingStartSeconds.isEmpty
          ? null
          : double.tryParse(_androidPlayingStartSeconds);
      if (_androidPlayingStartSeconds.isNotEmpty &&
          (seconds == null || !seconds.isFinite || seconds < 0)) {
        throw StateError('Android playing start time must be nonnegative');
      }
      if (_autoStartSeconds.isNotEmpty) {
        throw StateError(
            'Paused auto-start is incompatible with HDR transaction');
      }
      await _openHdrSource(
        sources[0],
        start: seconds == null
            ? null
            : Duration(
                microseconds:
                    (seconds * Duration.microsecondsPerSecond).round(),
              ),
      );
      if (_androidAutoSdrAfterP5Seconds > 0 &&
          sources[0].contains('/media-kit-p5-')) {
        await Future<void>.delayed(
          Duration(seconds: _androidAutoSdrAfterP5Seconds),
        );
        if (mounted && !_autoPlayerDisposed) {
          await _openDirectSdrAfterHdr(_sdrControlSource);
        }
      }
      if (_androidAutoSecondSourceAtSeconds > 0 &&
          _androidAutoSecondSource.isNotEmpty) {
        unawaited(Future<void>.delayed(
          Duration(seconds: _androidAutoSecondSourceAtSeconds),
        ).then((_) async {
          if (!mounted || _autoPlayerDisposed) return;
          // Same-player reopen through the session: rebuilds the hwdec
          // mapper as needed — exercises per-mapper state (e.g. P5 dovi
          // rescale) on the second file within the same process.
          await _openHdrSource(_androidAutoSecondSource);
          debugPrint('AUTO_SECOND_SOURCE '
              'path=$_androidAutoSecondSource');
        }));
      }
      if (_androidP5PlatformSdrDiagnostic &&
          _androidP5AutoFullscreenAtSeconds >= 0) {
        unawaited(_autoEnterDiagnosticFullscreen());
      }
      return;
    }
    // Android PlatformView configures libmpv with vid=no until its Surface
    // arrives. Ensure that guard exists before this diagnostic screen opens
    // media, otherwise a first launch can initialize vo before any Surface.
    final output = await controller.platform.future;
    await output.waitUntilInitialOutputBound;
    if (Platform.isAndroid && _androidDirectOpenTrace) {
      debugPrint('ANDROID_DIRECT_OPEN surface_bound');
    }
    debugPrint('AUTO_SOURCE path=${sources[0]}');
    if (Platform.isAndroid && _androidP84BaseLayerProbe) {
      if (!sources[0].contains('DV-P8.4') &&
          !sources[0].endsWith('/media-kit-p84-full.mp4')) {
        throw StateError(
            'P8.4 base-layer probe requires the fixed P8.4 source');
      }
      if (_androidP84DoviFilter != 'yes' && _androidP84DoviFilter != 'no') {
        throw StateError('P8.4 filter mode must be yes or no');
      }
      // Keep this diagnostic filter scoped to its own label. The format filter
      // with dolbyvision=no strips DV metadata and restores HLG base tags.
      await player.command([
        'vf',
        'add',
        '@media-kit-p84-base:format=dolbyvision=$_androidP84DoviFilter',
      ]);
      debugPrint('P84_BASE_FILTER vf=${await player.getProperty('vf')}');
    }
    if (Platform.isAndroid &&
        (_androidTargetPrim.isNotEmpty ||
            _androidTargetTrc.isNotEmpty ||
            _androidTargetColorspaceHint.isNotEmpty)) {
      for (final entry in <String, String>{
        if (_androidTargetPrim.isNotEmpty) 'target-prim': _androidTargetPrim,
        if (_androidTargetTrc.isNotEmpty) 'target-trc': _androidTargetTrc,
        if (_androidTargetColorspaceHint.isNotEmpty)
          'target-colorspace-hint': _androidTargetColorspaceHint,
      }.entries) {
        await player.setProperty(entry.key, entry.value);
        debugPrint('ANDROID_TARGET ${entry.key}=${entry.value}');
      }
    }
    if (Platform.isAndroid && _androidEglOutputFormat.isNotEmpty) {
      await player.setProperty('egl-output-format', _androidEglOutputFormat);
      debugPrint('ANDROID_EGL_OUTPUT_FORMAT=$_androidEglOutputFormat');
      // The PlatformView may have created gpu-next before this diagnostic
      // property is applied. Recreate it before any media is opened so the
      // requested EGL config is selected without interrupting a decoder.
      if (_androidVo == 'gpu-next') {
        await player.setProperty('vo', 'null');
        await player.setProperty('vo', _androidVo);
        debugPrint('ANDROID_EGL_OUTPUT_RECREATE vo=$_androidVo');
      }
    }
    if (Platform.isAndroid) {
      await _applyAndroidVideoTimingOffset();
      if (_androidOpenGlSwapInterval >= 0) {
        if (_androidOpenGlSwapInterval > 1 || _androidVo != 'gpu-next') {
          throw StateError(
              'OpenGL swap interval probe requires gpu-next and 0 or 1');
        }
        await player.setProperty(
          'opengl-swapinterval',
          '$_androidOpenGlSwapInterval',
        );
        final actual = await player.getProperty('opengl-swapinterval');
        if (actual.toString() != _androidOpenGlSwapInterval.toString()) {
          throw StateError('OpenGL swap interval rejected: $actual');
        }
        debugPrint('ANDROID_OPENGL_SWAPINTERVAL=$actual');
      }
      if (_androidVideoLatencyHacks) {
        await player.setProperty('video-latency-hacks', 'yes');
        debugPrint(
            'ANDROID_VIDEO_LATENCY_HACKS=${await player.getProperty('video-latency-hacks')}');
      }
      await _applyAndroidScalers();
    }
    if (Platform.isAndroid && _androidDisableDiskCache) {
      await player.setProperty('cache-on-disk', 'no');
      debugPrint('ANDROID_CACHE_ON_DISK=no');
    }
    if (_autoTexture) {
      // Isolated same-source SDR control: keep the normal Texture output and
      // make the target conversion explicit. This is diagnostic only and is
      // never part of PiliPlusX production configuration.
      for (final entry in const <String, String>{
        'target-prim': 'bt.709',
        'target-trc': 'bt.1886',
        'target-colorspace-hint': 'auto',
        'tone-mapping': 'bt.2390',
      }.entries) {
        try {
          await player.setProperty(entry.key, entry.value);
          debugPrint('AUTO_TEXTURE_SDR ${entry.key}=${entry.value}');
        } catch (error) {
          debugPrint('AUTO_TEXTURE_SDR ${entry.key} ERROR=$error');
        }
      }
    } else if (!const bool.fromEnvironment('MEDIA_KIT_AUTO_NATIVE_WINDOW',
        defaultValue: true)) {
      try {
        if (_autoSdr) {
          // Pure SDR control: do not configure NativeSurface/EDR or touch
          // tone-mapping. Keep mpv's normal BT.709 SDR target explicit.
          await player.setProperty('target-prim', 'bt.709');
          await player.setProperty('target-trc', 'bt.1886');
          debugPrint('AUTO_SDR_TARGET target-prim=bt.709 target-trc=bt.1886');
        } else {
          final output = await controller.platform.future;
          const targetPeak =
              String.fromEnvironment('MEDIA_KIT_AUTO_TARGET_PEAK');
          if (targetPeak.isNotEmpty) {
            await player.setProperty('target-peak', targetPeak);
            debugPrint('AUTO_NATIVE_TARGET_PEAK set=$targetPeak');
          }
          if (_autoToneMapping.isNotEmpty) {
            await player.setProperty('tone-mapping', _autoToneMapping);
            debugPrint('AUTO_NATIVE_TONE_MAPPING set=$_autoToneMapping');
          }
          final result = await output.configureHdrOutput(
            _autoNativeHdrConfiguration(),
          );
          debugPrint('AUTO_NATIVE_HDR_CONFIG result=$result');
        }
      } catch (error) {
        debugPrint('AUTO_NATIVE_HDR_CONFIG ERROR=$error');
      }
    }
    final autoStartSeconds = double.tryParse(_autoStartSeconds);
    final playingStartSeconds = Platform.isAndroid
        ? double.tryParse(_androidPlayingStartSeconds)
        : null;
    if (Platform.isAndroid &&
        _androidPlayingStartSeconds.isNotEmpty &&
        (playingStartSeconds == null ||
            !playingStartSeconds.isFinite ||
            playingStartSeconds < 0)) {
      throw StateError(
          'Android playing start time must be a nonnegative number');
    }
    if (autoStartSeconds != null && playingStartSeconds != null) {
      throw StateError('Only one Android start-time probe may be set');
    }
    final requestedStartSeconds = autoStartSeconds ?? playingStartSeconds;
    final firstVideoParams = autoStartSeconds != null && autoStartSeconds >= 0.0
        ? player.stream.videoParams.firstWhere((params) => params.w != null)
        : null;
    if (Platform.isAndroid && _androidLoopSource) {
      await player.setPlaylistMode(PlaylistMode.single);
      debugPrint('ANDROID_LOOP_SOURCE mode=single');
    }
    if (Platform.isAndroid &&
        _androidPreopenFullscreen &&
        !configuration.value.android.usePlatformView) {
      final properties = await _p5RuntimeGateChannel
          .invokeMapMethod<String, dynamic>('ReadProperties');
      final prebindEnabled =
          properties?['debug.media_kit.firstframe_prebind'] != '0';
      debugPrint('ANDROID_DIRECT_TEXTURE_PREBIND enabled=$prebindEnabled');
      if (prebindEnabled) {
        final prepared = await controller.prepareAndroidTextureOutput();
        debugPrint('ANDROID_DIRECT_TEXTURE_PREPARED layoutBound=$prepared');
      }
    }
    if (Platform.isAndroid && _androidDirectOpenTrace) {
      debugPrint('ANDROID_DIRECT_OPEN media_command');
    }
    await player.open(Media(
      sources[0],
      start: requestedStartSeconds != null && requestedStartSeconds >= 0.0
          ? Duration(
              microseconds:
                  (requestedStartSeconds * Duration.microsecondsPerSecond)
                      .round(),
            )
          : null,
    ));
    if (Platform.isAndroid &&
        _androidAutoSeekAtSeconds >= 0 &&
        !_autoSeekReopenScheduled) {
      _autoSeekReopenScheduled = true;
      unawaited(_runAutoSeekReopenProbe());
    }
    if (Platform.isAndroid &&
        _androidHotSwitchTarget.isNotEmpty &&
        _androidHotSwitchAtSeconds >= 0 &&
        !_hotSwitchScheduled) {
      _hotSwitchScheduled = true;
      unawaited(_runHotSwitchProbe());
    }
    if (Platform.isAndroid && _androidDirectOpenTrace) {
      debugPrint('ANDROID_DIRECT_OPEN media_returned');
    }
    if (Platform.isAndroid &&
        _androidDualViewLifecycleProbe &&
        !_dualViewProbeScheduled) {
      _dualViewProbeScheduled = true;
      unawaited(_runDualViewLifecycleProbe());
    }
    if (playingStartSeconds != null && playingStartSeconds >= 0.0) {
      debugPrint('ANDROID_PLAYING_START seconds=$playingStartSeconds');
    }
    if (Platform.isAndroid && _androidSameSurfaceRebindProbe) {
      Future<void>.delayed(const Duration(seconds: 6), () async {
        try {
          final before = await player.getProperty('wid');
          debugPrint('ANDROID_SAME_SURFACE_REBIND begin wid=$before');
          await player.setProperty('vo', 'null');
          await player.setProperty('wid', before);
          await player.setProperty('vo', _androidVo);
          final after = await player.getProperty('wid');
          debugPrint('ANDROID_SAME_SURFACE_REBIND end wid=$after');
        } catch (error) {
          debugPrint('ANDROID_SAME_SURFACE_REBIND error=$error');
        }
      });
    }
    if (Platform.isAndroid && _androidSurfaceTransfer.isNotEmpty) {
      Future<void>.delayed(const Duration(seconds: 6), () async {
        try {
          final handle = await player.handle;
          final applied = await _videoChannel.invokeMethod<bool>(
            'PlatformVideoView.SetColorSpace',
            {'handle': handle.toString(), 'transfer': _androidSurfaceTransfer},
          );
          debugPrint(
            'ANDROID_SURFACE_TRANSFER transfer=$_androidSurfaceTransfer applied=$applied',
          );
          // S4 device-round probe: the reporting contract alongside the
          // legacy boolean setter, same handle and transfer.
          final report = await _videoChannel.invokeMapMethod<String, dynamic>(
            'PlatformVideoView.ApplyDataSpace',
            {'handle': handle.toString(), 'transfer': _androidSurfaceTransfer},
          );
          debugPrint(
            'ANDROID_APPLY_DATASPACE transfer=$_androidSurfaceTransfer report=$report',
          );
        } catch (error) {
          debugPrint('ANDROID_SURFACE_TRANSFER ERROR=$error');
        }
      });
    }
    if (autoStartSeconds != null && autoStartSeconds >= 0.0) {
      await firstVideoParams;
      await player.pause();
      debugPrint('AUTO_FIXED_START seconds=$autoStartSeconds');
      debugPrint('AUTO_FIXED_START paused position=${player.state.position}');
    }
    if (const bool.fromEnvironment('MEDIA_KIT_AUTO_NATIVE_EDGE')) {
      Future<void>.delayed(const Duration(milliseconds: 350), () async {
        try {
          final output = await controller.platform.future;
          final reset = await output.resetHdrOutput();
          debugPrint('AUTO_NATIVE_EDGE reset=$reset');
          await Future<void>.delayed(const Duration(milliseconds: 350));
          final configure = await output.configureHdrOutput(
            _autoNativeHdrConfiguration(),
          );
          debugPrint('AUTO_NATIVE_EDGE configure=$configure');
        } catch (error) {
          debugPrint('AUTO_NATIVE_EDGE ERROR=$error');
        }
      });
    }
  }

  Future<void> _runAutoSeekReopenProbe() async {
    try {
      if (!_autoTexture || _androidAutoSeekTargetSeconds < 0) {
        throw StateError('Auto seek probe requires Texture and a target');
      }
      final start = Duration(seconds: _androidAutoSeekAtSeconds);
      final target = Duration(seconds: _androidAutoSeekTargetSeconds);
      await player.stream.position
          .firstWhere((position) => position >= start)
          .timeout(Duration(seconds: _androidAutoSeekAtSeconds + 30));
      if (!mounted || _autoPlayerDisposed) return;
      debugPrint(
          'AUTO_SEEK_REOPEN seek_begin position=${player.state.position} '
          'target=$target');
      await player.seek(target);
      await player.stream.position
          .firstWhere(
              (position) => position >= target + const Duration(seconds: 2))
          .timeout(const Duration(seconds: 20));
      if (!mounted || _autoPlayerDisposed) return;
      debugPrint(
          'AUTO_SEEK_REOPEN seek_playing position=${player.state.position}');
      if (!_androidAutoReopenAfterSeek) return;
      debugPrint(
          'AUTO_SEEK_REOPEN reopen_begin position=${player.state.position}');
      await player.open(Media(sources[0]));
      await player.stream.position
          .firstWhere((position) =>
              position >= const Duration(seconds: 2) &&
              position < const Duration(seconds: 10))
          .timeout(const Duration(seconds: 20));
      if (!mounted || _autoPlayerDisposed) return;
      debugPrint(
          'AUTO_SEEK_REOPEN reopen_playing position=${player.state.position}');
    } catch (error, stack) {
      debugPrint('AUTO_SEEK_REOPEN error=$error');
      debugPrintStack(stackTrace: stack);
    }
  }

  /// Hot-switches to another local source while pinging the video layout, so
  /// texture-layout updates land inside the empty-VideoParams gap between
  /// sources. The log then shows whether any interim output size request was
  /// computed from the previous source's dimensions.
  Future<void> _runHotSwitchProbe() async {
    try {
      final target = _androidHotSwitchTarget;
      final start = Duration(seconds: _androidHotSwitchAtSeconds);
      await player.stream.position
          .firstWhere((position) => position >= start)
          .timeout(Duration(seconds: _androidHotSwitchAtSeconds + 30));
      if (!mounted || _autoPlayerDisposed) return;
      debugPrint('ANDROID_HOT_SWITCH begin position=${player.state.position}');
      setState(() => _hotSwitchPingActive = true);
      unawaited(() async {
        while (_hotSwitchPingActive && mounted) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          if (!_hotSwitchPingActive || !mounted) return;
          setState(() => _hotSwitchPingOn = !_hotSwitchPingOn);
        }
      }());
      await player.open(Media(target));
      debugPrint(
          'ANDROID_HOT_SWITCH switched position=${player.state.position}');
      await Future<void>.delayed(const Duration(seconds: 3));
      if (mounted) {
        setState(() {
          _hotSwitchPingActive = false;
          _hotSwitchPingOn = false;
        });
      }
    } catch (error, stack) {
      debugPrint('ANDROID_HOT_SWITCH error=$error');
      debugPrintStack(stackTrace: stack);
    }
  }

  /// Destroys the FlutterEngine directly from the Android side, bypassing
  /// every Dart-side disposal path. The round script then checks that the
  /// process survives, native players are torn down, and no crash follows.
  /// Wall-clock based so a no-media Player can be exercised too.
  Future<void> _runEngineDestroyProbe() async {
    try {
      await Future<void>.delayed(
          Duration(seconds: _androidEngineDestroyAtSeconds));
      if (!mounted) return;
      debugPrint('ANDROID_ENGINE_DESTROY requested '
          'position=${player.state.position}');
      unawaited(_engineControlChannel
          .invokeMethod<void>('DestroyEngineNow')
          .then((_) => debugPrint('ANDROID_ENGINE_DESTROY returned'))
          .catchError((Object error) {
        debugPrint('ANDROID_ENGINE_DESTROY invoke error=$error');
      }));
    } catch (error, stack) {
      debugPrint('ANDROID_ENGINE_DESTROY error=$error');
      debugPrintStack(stackTrace: stack);
    }
  }

  /// Simulates a mid-play output failure by disposing the current texture
  /// output over the platform channel, then retries on the same path by
  /// reopening the same source. The output slot must rebuild through its
  /// dispose barrier and frames must resume.
  Future<void> _runOutputFailureRetryProbe() async {
    try {
      final start = Duration(seconds: _androidOutputFailureAtSeconds);
      await player.stream.position
          .firstWhere((position) => position >= start)
          .timeout(Duration(seconds: _androidOutputFailureAtSeconds + 30));
      if (!mounted || _autoPlayerDisposed) return;
      debugPrint(
          'ANDROID_OUTPUT_FAILURE begin position=${player.state.position}');
      final handle = await player.handle;
      await const MethodChannel('com.alexmercerind/media_kit_video')
          .invokeMethod<void>('VideoOutputManager.Dispose', {
        'handle': handle.toString(),
      });
      debugPrint('ANDROID_OUTPUT_FAILURE output_disposed');
      await _openHdrSource(sources[0]);
      debugPrint(
          'ANDROID_OUTPUT_FAILURE reopened position=${player.state.position}');
      await player.stream.position
          .firstWhere((position) =>
              position >= const Duration(seconds: 2) &&
              position < const Duration(seconds: 10))
          .timeout(const Duration(seconds: 20));
      debugPrint(
          'ANDROID_OUTPUT_FAILURE recovered position=${player.state.position}');
    } catch (error, stack) {
      debugPrint('ANDROID_OUTPUT_FAILURE error=$error');
      debugPrintStack(stackTrace: stack);
    }
  }

  Future<void> _resizeTestWindow(
      {required double width, required double height}) async {
    try {
      final result = await _windowChannel.invokeMethod<Map<Object?, Object?>>(
        'setFrame',
        {'width': width, 'height': height},
      );
      debugPrint(
          'AUTO_WINDOW_RESIZE requested=${width}x$height result=$result');
    } catch (error) {
      debugPrint('AUTO_WINDOW_RESIZE ERROR=$error');
    }
  }

  Future<void> _disposeTestPlayer() {
    final existing = _autoPlayerDisposeFuture;
    if (existing != null) return existing;
    final attempt = _disposeTestPlayerOnce();
    _autoPlayerDisposeFuture = attempt;
    unawaited(attempt.then<void>((_) {}, onError: (Object _, StackTrace __) {
      if (identical(_autoPlayerDisposeFuture, attempt)) {
        _autoPlayerDisposeFuture = null;
      }
    }));
    return attempt;
  }

  Future<void> _disposeTestPlayerOnce() async {
    _autoPlayerDisposed = true;
    if (_androidHdr10SessionDiagnostic) {
      await _closeHdr10Owned();
      return;
    }
    if (_androidNativeDvSessionForeignOwnershipN4) {
      await _closeNativeDvN4Owned();
      return;
    }
    if (_nativeDvN1 != null) {
      final startup = _nativeDvSessionStartup;
      if (startup != null) {
        try {
          await startup;
        } catch (_) {}
      }
      await _closeNativeDvSessionAndPlayer();
      return;
    }
    if (Platform.isAndroid && _androidNativeDvSessionDiagnostic) {
      final startup = _nativeDvSessionStartup;
      if (startup != null) {
        try {
          await startup;
        } catch (_) {}
      }
      try {
        await _nativeDvSessionDiagnostic?.close(
          cleanup: 'sampling quiesced; disposing real HdrVideoSession',
        );
      } catch (error) {
        try {
          await _nativeDvSessionDiagnostic?.recordCleanupCaptureError(error);
        } catch (_) {}
      }
    }
    if (Platform.isAndroid && _androidNativeDvReleaseDiagnostic) {
      _nativeDvPageAdmission.close();
    }
    if (Platform.isAndroid && _androidNativeDvReleaseDiagnostic) {
      await _nativeDvReleaseDiagnostic?.shutdown();
      await player.dispose();
    } else if (Platform.isAndroid && _androidHdrTransaction) {
      await _disposeHdrPlayer();
    } else {
      await player.dispose();
    }
    debugPrint('AUTO_PLAYER_DISPOSE completed');
  }

  @override
  void dispose() {
    AndroidServiceProbe.detach(player);
    for (final subscription in _nativeDvSessionStateSubscriptions) {
      unawaited(subscription.cancel());
    }
    if (_inplaceFullscreen) {
      unawaited(SystemChrome.setPreferredOrientations(
        const [DeviceOrientation.portraitUp],
      ));
      unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    }
    final second = _secondPlayer;
    if (second != null) {
      unawaited(second.dispose());
      _secondPlayer = null;
      _secondController = null;
    }
    _flutterRepaintTimer?.cancel();
    _androidP5CounterTimer?.cancel();
    _copyDiagTimer?.cancel();
    if (_copyDiagVfOwned) {
      unawaited(_disableCopyDiagVf(serial: null));
      unawaited(_disableDiagVdLavcO(serial: null));
    }
    _surfaceTextureDiagTimer?.cancel();
    if (_surfaceTextureDiagSerial != null) {
      _disableSurfaceTextureDiagSwitch(serial: null);
    }
    // E1: drop a lingering dataspace arm (defensive; the arm is normally
    // reset at each open's end).
    _disarmDiagDataspace(serial: null);
    // YUV diag: drop a lingering branch switch (defensive; normally reset at
    // each open's end).
    _disarmYuvDiagSwitch(serial: null);
    if (Platform.isAndroid && _androidFrameSchedulerProbe) {
      SchedulerBinding.instance.removeTimingsCallback(_frameTimingsCallback);
    }
    if (Platform.isAndroid &&
        (_androidPreDestroyVidStop ||
            _androidHdrLifecyclePositionProbe ||
            _androidHdrAutoResumeProbe ||
            _androidNativeDvSessionLifecycleActions)) {
      WidgetsBinding.instance.removeObserver(this);
    }
    if (!_autoPlayerDisposed) {
      unawaited(
          _disposeTestPlayer().catchError((Object error, StackTrace stack) {
        debugPrint('AUTO_PLAYER_DISPOSE error=$error');
        debugPrintStack(stackTrace: stack);
      }));
    }
    super.dispose();
  }

  Future<void> _disposeHdrPlayer() {
    final existing = _hdrDisposeFuture;
    if (existing != null) return existing;
    final attempt = _disposeHdrPlayerOnce();
    _hdrDisposeFuture = attempt;
    unawaited(attempt.then<void>((_) {}, onError: (Object _, StackTrace __) {
      if (identical(_hdrDisposeFuture, attempt)) _hdrDisposeFuture = null;
    }));
    return attempt;
  }

  Future<void> _disposeHdrPlayerOnce() async {
    // migrated to HdrVideoSession (S10): the old coordinator/slot/intent
    // disposal is replaced by the session's own dispose (mpv property
    // restore, controller slot and backend teardown); the caller's player is
    // still disposed here because the session does not own it.
    final session = _hdrSession;
    final experimentOwner = _lgExperimentOwner;
    Object? playerDisposeError;
    Object? sessionDisposeError;
    if (experimentOwner != null) {
      try {
        await experimentOwner.revoke(_revokeLgExperiment);
      } catch (error) {
        // Continue output disposal: core Surface lifecycle also withdraws the
        // exact tuple, even if the channel has already detached.
        sessionDisposeError = error;
      }
    }
    try {
      await session?.dispose();
    } catch (error) {
      sessionDisposeError = error;
    } finally {
      if (_androidNativeDvSessionDiagnostic) {
        try {
          await _nativeDvSessionDiagnostic?.capturePostSessionCleanup(
            report: session?.lastDisposeReport,
            sessionDisposeError: sessionDisposeError,
          );
        } catch (captureError) {
          try {
            await _nativeDvSessionDiagnostic
                ?.recordCleanupCaptureError(captureError);
          } catch (_) {}
        }
      }
      try {
        await player.dispose();
      } catch (error) {
        playerDisposeError = error;
      }
    }
    if (_androidNativeDvSessionDiagnostic) {
      await _nativeDvSessionDiagnostic?.recordPlayerTermination(
        error: playerDisposeError,
      );
    }
    if (sessionDisposeError != null) throw sessionDisposeError;
    final report = session?.lastDisposeReport;
    _hdrDisposeReportClean =
        (report?.clean ?? false) && playerDisposeError == null;
    _hdrDisposeReportDetail = report == null
        ? 'session=null playerError=$playerDisposeError'
        : 'coordinator=${report.coordinatorError} '
            'player=${report.playerError} '
            'directory=${report.directoryError} '
            'retained=${report.retainedDirectory}';
    if (_hdrDisposeReportClean != true) {
      debugPrint('ANDROID_HDR_DISPOSE $_hdrDisposeReportDetail');
      throw StateError('Android HDR resource disposal is incomplete');
    }
  }

  List<Widget> get items => [
        for (int i = 0; i < sources.length; i++)
          ListTile(
            title: Text(
              'Video $i',
              style: const TextStyle(
                fontSize: 14.0,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () {
              unawaited(_openSelectedSource(sources[i]));
            },
          ),
      ];

  Future<void> _toggleDiagnosticFullscreen(
      GlobalObjectKey<VideoState> videoKey) async {
    if (_androidLgVisual278Experiment) {
      throw StateError(
          'LG visual278 experiment is portrait single-output; fullscreen unsupported');
    }
    if (_androidP5ScopeFullscreen) {
      final videoState = videoKey.currentState;
      if (!mounted || videoState == null) {
        throw StateError('Diagnostic VideoState is unavailable at fullscreen');
      }
      debugPrint('DIAG_FULLSCREEN_SCOPE toggle begin '
          'media=${player.state.position.inMilliseconds}ms');
      await videoState.toggleFullscreen();
      debugPrint('DIAG_FULLSCREEN_SCOPE toggle complete '
          'media=${player.state.position.inMilliseconds}ms');
      return;
    }
    if (_androidP5InplaceFullscreen) {
      debugPrint('DIAG_FULLSCREEN_INPLACE begin '
          'media=${player.state.position.inMilliseconds}ms');
      await SystemChrome.setPreferredOrientations(
        const [DeviceOrientation.landscapeLeft],
      );
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      if (mounted) setState(() => _inplaceFullscreen = true);
      debugPrint('DIAG_FULLSCREEN_INPLACE complete '
          'media=${player.state.position.inMilliseconds}ms');
      return;
    }
    if (_androidP5PrestopFullscreen ||
        _androidP5PrestopVidFullscreen ||
        _androidP5PrestopWidFullscreen) {
      debugPrint('DIAG_FULLSCREEN_PRESTOP begin '
          'media=${player.state.position.inMilliseconds}ms');
      await player.setProperty('vo', 'null');
      if (_androidP5PrestopWidFullscreen) {
        await player.setProperty('wid', '0');
      }
      if (_androidP5PrestopVidFullscreen) {
        await player.setProperty('vid', 'no');
      }
      debugPrint('DIAG_FULLSCREEN_PRESTOP complete '
          'media=${player.state.position.inMilliseconds}ms');
    }
    final videoState = videoKey.currentState;
    if (!mounted || videoState == null) {
      throw StateError('Diagnostic VideoState is unavailable at fullscreen');
    }
    debugPrint('DIAG_FULLSCREEN_TOGGLE begin '
        'media=${player.state.position.inMilliseconds}ms');
    await videoState.toggleFullscreen();
  }

  Future<void> _autoEnterDiagnosticFullscreen() async {
    final target = Duration(seconds: _androidP5AutoFullscreenAtSeconds);
    if (player.state.position < target) {
      await player.stream.position.firstWhere((position) => position >= target);
    }
    if (!mounted) return;
    final displayController = _hdrTransactionController;
    await _toggleDiagnosticFullscreen(
      GlobalObjectKey<VideoState>(displayController),
    );
  }

  Future<void> _exitInplaceDiagnosticFullscreen() async {
    if (!_inplaceFullscreen) return;
    debugPrint('DIAG_FULLSCREEN_INPLACE exit begin '
        'media=${player.state.position.inMilliseconds}ms');
    await SystemChrome.setPreferredOrientations(
      const [DeviceOrientation.portraitUp],
    );
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    if (mounted) setState(() => _inplaceFullscreen = false);
    debugPrint('DIAG_FULLSCREEN_INPLACE exit complete '
        'media=${player.state.position.inMilliseconds}ms');
  }

  Future<void> _exitScopeDiagnosticPage() async {
    debugPrint('DIAG_SCOPE_PAGE_EXIT stop begin '
        'media=${player.state.position.inMilliseconds}ms');
    await _disposeTestPlayer();
    if (_androidHdrTransaction && _hdrDisposeReportClean != true) {
      debugPrint('DIAG_SCOPE_PAGE_EXIT dispose=$_hdrDisposeReportDetail');
      throw StateError('Player or output disposal did not complete safely');
    }
    debugPrint('DIAG_SCOPE_PAGE_EXIT stop complete');
  }

  /// POC define on only: the video output container is fixed at the frozen
  /// output contract's 2:1 geometry from the first build, so the platform
  /// view is created directly at its final 1440x720 surface size and the
  /// mid-open resize (video-params arrival resetting the decoder) never
  /// happens. Define off keeps the existing adaptive layout untouched.
  Widget _pocFixedOutputLayout(Widget child) {
    debugPrint('MKSURF-POC: fixed 2:1 output layout');
    return Center(
      child: AspectRatio(aspectRatio: 2.0, child: child),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_androidLgVisual278Experiment) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) unawaited(_exitAutoPlayerAfterDisposal());
        },
        child: Scaffold(
          appBar: AppBar(
              title: const Text('LG experimental - single output'),
              automaticallyImplyLeading: false),
          body: AndroidLgSingleOwnerVideo(session: _hdrSession),
        ),
      );
    }
    if (_androidHdr10SessionDiagnostic) {
      final journal = _hdr10Journal;
      final session = _hdrSession;
      final snapshot = journal?.snapshot();
      final page = Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
            title: const Text('HDR10 Session diagnostic'),
            automaticallyImplyLeading: false),
        body: Column(children: [
          Expanded(
              child: session == null
                  ? const SizedBox.expand()
                  : Center(
                      child: AspectRatio(
                          // This diagnostic admits only the byte-verified
                          // 3840 x 1920 sample; keep its native viewport 2:1.
                          aspectRatio: 2.0,
                          child: HdrVideo(
                              session: session,
                              aspectRatio: 2.0,
                              controls: (_) => const SizedBox.shrink())))),
          Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        'run: ${journal?.runId ?? "not admitted"}\n'
                        'route: ${session?.report.value.actual}\n'
                        'journal: ${snapshot?["closed"] == true ? "closed" : "observing"}; '
                        '10s position support: ${snapshot?["progressSupport"]}\n'
                        'Visible image, brightness, and smoothness require phone observation.',
                        style:
                            const TextStyle(color: Colors.white, fontSize: 11)),
                    if (_hdr10BuildError != null)
                      Text(_hdr10BuildError!,
                          style:
                              const TextStyle(color: Colors.red, fontSize: 11)),
                    Semantics(
                        label: 'hdr10-session-action:close-and-exit',
                        button: true,
                        child: OutlinedButton(
                            onPressed: _hdr10ExitFuture == null
                                ? () => unawaited(_exitHdr10DiagnosticPage()
                                        .catchError(
                                            (Object error, StackTrace stack) {
                                      debugPrint(
                                          'HDR10_SESSION_EXIT_ERROR $error');
                                    }))
                                : null,
                            child: const Text('Close & exit'))),
                  ])),
        ]),
      );
      return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop) {
              unawaited(_exitHdr10DiagnosticPage()
                  .catchError((Object error, StackTrace stack) {
                debugPrint('HDR10_SESSION_EXIT_ERROR $error');
              }));
            }
          },
          child: page);
    }

    if (Platform.isAndroid && _androidNativeDvSessionForeignOwnershipN4) {
      final session = _hdrSession;
      final transport = _nativeDvN4;
      final canRun = transport?.ready == true &&
          _nativeDvN4ExecutionReport == null &&
          !_nativeDvN4Closing;
      final page = Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: const Text('Native DV Session ownership N4'),
          automaticallyImplyLeading: false,
        ),
        body: AndroidNativeDvN4PageLayout(
          video: Center(
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: session == null
                  ? const ColoredBox(color: Colors.black)
                  : HdrVideo(
                      session: session,
                      width: MediaQuery.of(context).size.width,
                      height: MediaQuery.of(context).size.width * 9 / 16,
                      controls: (_) => const SizedBox.shrink(),
                    ),
            ),
          ),
          diagnostics: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'run: $_nativeDvN4RunId\n'
                'status: $_nativeDvN4Status\n'
                'session instance: ${transport?.sessionInstanceId ?? "not bound"}\n'
                'generation: ${session?.report.value.generation}\n'
                'route: ${session?.report.value.actual?.strategy.name}\n'
                'report: ${_nativeDvN4ReportPath ?? "pending"}\n'
                'source SHA is an external verified-fixture claim; '
                'this app does not hash source bytes. Device/display '
                'acceptance remains a separate observation.',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
              if (_nativeDvN4ExecutionReport != null &&
                  _nativeDvN4Execution == null)
                const Text(
                  'N4 open is pending; wait for the actual Player.open result before closing.',
                  style: TextStyle(color: Colors.orangeAccent),
                ),
              if (_nativeDvSessionDiagnosticError != null)
                Text(_nativeDvSessionDiagnosticError!,
                    style: const TextStyle(color: Colors.redAccent)),
            ],
          ),
          onRun: canRun ? _startNativeDvN4Experiment : null,
          onClose: _nativeDvN4Exit == null
              ? () => unawaited(_exitNativeDvN4Page()
                      .catchError((Object error, StackTrace stack) {
                    debugPrint('N4_EXIT_ERROR $error');
                  }))
              : null,
        ),
      );
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) {
            unawaited(_exitNativeDvN4Page()
                .catchError((Object error, StackTrace stack) {
              debugPrint('N4_BACK_EXIT_ERROR $error');
            }));
          }
        },
        child: page,
      );
    }

    if (Platform.isAndroid &&
        (_androidNativeDvSessionDiagnostic ||
            _androidNativeDvSessionNegativeN1)) {
      final diagnostic = _nativeDvSessionDiagnostic;
      final negative = _nativeDvN1;
      final page = Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                flex: 3,
                child: Center(
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: _hdrSession == null || !_nativeDvSessionVideoMounted
                        ? const ColoredBox(color: Colors.black)
                        : HdrVideo(
                            session: _hdrSession!,
                            width: MediaQuery.of(context).size.width,
                            height: MediaQuery.of(context).size.width * 9 / 16,
                            controls: (_) => Builder(
                              builder: (videoContext) {
                                _captureNativeDvSessionVideoContext(
                                    videoContext);
                                return const SizedBox.shrink();
                              },
                            ),
                          ),
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: SingleChildScrollView(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: SafeArea(
                      bottom: false,
                      child: Container(
                        width: double.infinity,
                        color: Colors.black.withValues(alpha: 0.78),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        child: negative != null
                            ? ValueListenableBuilder<String>(
                                valueListenable: negative.status,
                                builder: (context, value, _) => Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(value,
                                            style: const TextStyle(
                                                color: Colors.white)),
                                        const Text(
                                            'N1: one real open; first native Surface intentionally unmounted. Fallback uses the same Session. Visible output and Surface ACK require separate confirmation.',
                                            style: TextStyle(
                                                color: Colors.white70)),
                                        if (_nativeDvSessionDiagnosticError !=
                                            null)
                                          Text(_nativeDvSessionDiagnosticError!,
                                              style: const TextStyle(
                                                  color: Colors.redAccent)),
                                        if (_nativeDvSessionActionError != null)
                                          Text(_nativeDvSessionActionError!,
                                              style: const TextStyle(
                                                  color: Colors.redAccent)),
                                        TextButton(
                                            onPressed: _nativeDvN1Exit == null
                                                ? () => unawaited(
                                                        _exitNativeDvN1Page()
                                                            .catchError((Object
                                                                    error,
                                                                StackTrace _) {
                                                      _reportNativeDvSessionExitFailure(
                                                          error);
                                                    }))
                                                : null,
                                            child: const Text('Close N1')),
                                      ],
                                    ))
                            : diagnostic == null
                                ? Text(
                                    _nativeDvSessionDiagnosticError ??
                                        'Preparing fixed-source Session diagnostic',
                                    style: const TextStyle(color: Colors.white),
                                  )
                                : ValueListenableBuilder<String>(
                                    valueListenable: diagnostic.status,
                                    builder: (context, value, _) => Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                            'Native DV Session diagnostic: $value',
                                            style: const TextStyle(
                                                color: Colors.white)),
                                        const Text(
                                          'consumerValidated / routeApplied are configuration evidence only; visual HDR acceptance is pending.',
                                          style:
                                              TextStyle(color: Colors.white70),
                                        ),
                                        if (_nativeDvSessionDiagnosticError !=
                                            null)
                                          Text(_nativeDvSessionDiagnosticError!,
                                              style: const TextStyle(
                                                  color: Colors.redAccent)),
                                        if (_androidNativeDvSessionLifecycleActions)
                                          _buildNativeDvLifecycleControls(),
                                      ],
                                    ),
                                  ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      if (negative != null) {
        return PopScope(
            canPop: false,
            onPopInvokedWithResult: (didPop, result) {
              if (!didPop) {
                unawaited(_exitNativeDvN1Page()
                    .catchError((Object error, StackTrace _) {
                  _reportNativeDvSessionExitFailure(error);
                }));
              }
            },
            child: page);
      }
      if (!_androidNativeDvSessionLifecycleActions) return page;
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) {
            unawaited(_exitNativeDvSessionLifecyclePage()
                .catchError((Object error, StackTrace _) {
              _reportNativeDvSessionExitFailure(error);
            }));
          }
        },
        child: page,
      );
    }
    if (Platform.isAndroid && _androidNativeDvReleaseDiagnostic) {
      final diagnostic = _nativeDvReleaseDiagnostic;
      final page = Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              // This opt-in diagnostic has one SHA-bound 3840x2160,
              // square-pixel source. Fix its Surface viewport before open:
              // mediacodec_embed fills the native Surface directly.
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Video(
                  key: const ValueKey('native-dv-release-diagnostic-video'),
                  controller: _initialController,
                  fill: Colors.black,
                  controls: null,
                ),
              ),
            ),
            Align(
              alignment: Alignment.topCenter,
              child: SafeArea(
                bottom: false,
                child: Container(
                  width: double.infinity,
                  color: Colors.black.withValues(alpha: 0.78),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: diagnostic == null
                      ? Text(
                          _nativeDvReleaseDiagnosticBuildError ??
                              'Preparing fixed-source native DV diagnostic',
                          style: const TextStyle(color: Colors.white),
                        )
                      : ValueListenableBuilder<
                          AndroidNativeDvReleaseDiagnosticState>(
                          valueListenable: diagnostic.state,
                          builder: (context, value, _) => Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Native DV diagnostic: ${value.phase}',
                                style: const TextStyle(color: Colors.white),
                              ),
                              Text(
                                'Samples ${value.rowCount}/$_androidNativeDvReleaseDiagnosticSeconds · '
                                'visual acceptance: pending human observation',
                                style: const TextStyle(color: Colors.white70),
                              ),
                              if (value.outputPath != null)
                                Text(
                                  value.outputPath!,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 11,
                                  ),
                                ),
                              if (value.error != null)
                                Text(
                                  value.error!,
                                  style:
                                      const TextStyle(color: Colors.redAccent),
                                ),
                            ],
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      );
      if (!_autoSinglePlayer) return page;
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) unawaited(_exitAutoPlayerAfterDisposal());
        },
        child: page,
      );
    }
    // In the HDR session path the display follows the session's current
    // controller; it is null until the session creates the first controller
    // for an open (the placeholder branches below show black meanwhile).
    final VideoController? displayController =
        Platform.isAndroid && _androidHdrTransaction
            ? _hdrSession?.controller.value
            : _initialController;
    // migrated to HdrVideoSession (S10): the primary surface in the HDR
    // session path is HdrVideo, which follows session controller replacements
    // (Texture ↔ PlatformView) and lets the built-in fullscreen page follow
    // the session too (R2.1). The VideoState-key diagnostic branches keep the
    // plain Video so their global keys keep working.
    final useHdrVideo = Platform.isAndroid &&
        _androidHdrTransaction &&
        !_androidP5PlatformSdrDiagnostic &&
        !_androidP5ScopeFullscreen &&
        _hdrSession != null;
    final diagnosticVideoKey = displayController == null
        ? null
        : GlobalObjectKey<VideoState>(displayController);
    final videoKey =
        (_androidP5PlatformSdrDiagnostic || _androidP5ScopeFullscreen)
            ? diagnosticVideoKey
            : ObjectKey(displayController);
    if (Platform.isAndroid && _androidDualPlayerView) {
      final second = _secondController;
      final dualPlayerPage = Scaffold(
        body: Row(children: [
          Expanded(
            key: const ValueKey('android-dual-player-a'),
            child: displayController == null
                ? const ColoredBox(color: Colors.black)
                : Video(
                    key: const ValueKey('android-dual-player-view-a'),
                    controller: displayController,
                  ),
          ),
          Expanded(
            key: const ValueKey('android-dual-player-b'),
            child: second == null
                ? const ColoredBox(color: Colors.black)
                : Video(
                    key: const ValueKey('android-dual-player-view-b'),
                    controller: second,
                  ),
          ),
        ]),
      );
      if (!_autoSinglePlayer) return dualPlayerPage;
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) unawaited(_exitAutoPlayerAfterDisposal());
        },
        child: dualPlayerPage,
      );
    }
    if (Platform.isAndroid && _androidPreopenFullscreen) {
      final page = Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            if (displayController != null)
              Padding(
                padding: _hotSwitchPingOn
                    ? const EdgeInsets.only(bottom: 220)
                    : EdgeInsets.zero,
                child: Video(
                  key: videoKey,
                  controller: displayController,
                  fill: Colors.black,
                  controls: null,
                ),
              ),
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () {
                if (_preopenFullscreenStarted || _autoPlayerDisposed) return;
                _preopenFullscreenStarted = true;
                unawaited(() async {
                  try {
                    if (_androidPreopenFirstFrameProbe) {
                      final started = await _flutterSurfaceProbeChannel
                          .invokeMapMethod<String, dynamic>(
                              'StartFirstFrameProbe', {
                        'target': configuration.value.android.usePlatformView
                            ? 'platform'
                            : 'flutter',
                      });
                      debugPrint('FIRST_FRAME_PIXEL_COPY started=$started');
                    }
                    await _openInitialSource();
                  } catch (error, stack) {
                    _preopenFullscreenStarted = false;
                    debugPrint('PREOPEN_FULLSCREEN_OPEN error=$error');
                    debugPrintStack(stackTrace: stack);
                  }
                }());
              },
            ),
          ],
        ),
      );
      if (!_autoSinglePlayer) return page;
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) unawaited(_exitAutoPlayerAfterDisposal());
        },
        child: page,
      );
    }
    if (_androidDualViewLifecycleProbe) {
      final showA = _dualViewPhase != 2 && _dualViewPhase != 4;
      final showB = _dualViewPhase == 1 ||
          _dualViewPhase == 2 ||
          _dualViewPhase == 3 ||
          _dualViewPhase == 4;
      final dualViewPage = Scaffold(
        body: Row(children: [
          if (showA)
            Expanded(
              key: const ValueKey('android-dual-slot-a'),
              child: displayController == null
                  ? const ColoredBox(color: Colors.black)
                  : Video(
                      key: const ValueKey('android-dual-view-a'),
                      controller: displayController,
                    ),
            ),
          if (showB)
            Expanded(
              key: const ValueKey('android-dual-slot-b'),
              child: displayController == null
                  ? const ColoredBox(color: Colors.black)
                  : Video(
                      key: const ValueKey('android-dual-view-b'),
                      controller: displayController,
                    ),
            ),
        ]),
      );
      if (!_autoSinglePlayer) return dualViewPage;
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) unawaited(_exitAutoPlayerAfterDisposal());
        },
        child: dualViewPage,
      );
    }
    if (_androidP5ScopeFullscreen) {
      final viewHeight = MediaQuery.of(context).size.width * 9 / 16;
      return VideoFullscreenScope(
        onBeforePop: _exitScopeDiagnosticPage,
        builder: (context, fullscreen, child) => Scaffold(
          appBar: fullscreen
              ? null
              : AppBar(
                  title: const Text('package:media_kit'),
                  actions: [
                    IconButton(
                      tooltip: 'Toggle diagnostic video fullscreen',
                      icon: const Icon(Icons.fullscreen),
                      onPressed: diagnosticVideoKey == null
                          ? null
                          : () =>
                              _toggleDiagnosticFullscreen(diagnosticVideoKey),
                    ),
                  ],
                ),
          body: Stack(children: [
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              bottom: fullscreen ? 0 : null,
              height: fullscreen ? null : viewHeight,
              child: child,
            ),
            if (!fullscreen)
              Positioned(
                top: viewHeight,
                left: 0,
                right: 0,
                bottom: 0,
                child: ListView(children: items),
              ),
          ]),
        ),
        child: displayController == null
            ? const ColoredBox(color: Colors.black)
            : Video(
                key: videoKey,
                controller: displayController,
                onEnterFullscreen: () async {
                  await SystemChrome.setPreferredOrientations(
                    const [DeviceOrientation.landscapeLeft],
                  );
                  await SystemChrome.setEnabledSystemUIMode(
                    SystemUiMode.immersiveSticky,
                  );
                },
                onExitFullscreen: () async {
                  await SystemChrome.setPreferredOrientations(
                    const [DeviceOrientation.portraitUp],
                  );
                  await SystemChrome.setEnabledSystemUIMode(
                    SystemUiMode.edgeToEdge,
                  );
                },
              ),
      );
    }
    if (_androidP5InplaceFullscreen) {
      final viewHeight = MediaQuery.of(context).size.width * 9 / 16;
      return PopScope(
          canPop:
              !_inplaceFullscreen && !(Platform.isAndroid && _autoSinglePlayer),
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && _inplaceFullscreen) {
              unawaited(_exitInplaceDiagnosticFullscreen());
            } else if (!didPop && Platform.isAndroid && _autoSinglePlayer) {
              unawaited(_exitAutoPlayerAfterDisposal());
            }
          },
          child: Scaffold(
            appBar: _inplaceFullscreen
                ? null
                : AppBar(
                    title: const Text('package:media_kit'),
                    actions: [
                      IconButton(
                        tooltip: 'Toggle diagnostic video fullscreen',
                        icon: const Icon(Icons.fullscreen),
                        onPressed: diagnosticVideoKey == null
                            ? null
                            : () =>
                                _toggleDiagnosticFullscreen(diagnosticVideoKey),
                      ),
                    ],
                  ),
            body: Stack(
              children: [
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  bottom: _inplaceFullscreen ? 0 : null,
                  height: _inplaceFullscreen ? null : viewHeight,
                  child: displayController == null
                      ? const ColoredBox(color: Colors.black)
                      : Video(key: videoKey, controller: displayController),
                ),
                if (!_inplaceFullscreen)
                  Positioned(
                    top: viewHeight,
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: ListView(children: items),
                  ),
              ],
            ),
          ));
    }
    if (_androidFrameSchedulerProbe &&
        _flutterRepaintTick % 5 == 0 &&
        _lastBuildLoggedTick != _flutterRepaintTick) {
      _lastBuildLoggedTick = _flutterRepaintTick;
      debugPrint('FLUTTER_BUILD_TICK $_flutterRepaintTick');
    }
    final horizontal =
        MediaQuery.of(context).size.width > MediaQuery.of(context).size.height;
    final page = Scaffold(
      appBar: AppBar(
        title: const Text('package:media_kit'),
        actions: [
          if (_androidP5PlatformSdrDiagnostic && diagnosticVideoKey != null)
            IconButton(
              tooltip: 'Toggle diagnostic video fullscreen',
              icon: const Icon(Icons.fullscreen),
              onPressed: () => _toggleDiagnosticFullscreen(diagnosticVideoKey),
            ),
          IconButton(
            tooltip: 'Resize test window',
            icon: const Icon(Icons.open_in_full),
            onPressed: () async {
              final compact = !_compactWindow;
              await _windowChannel.invokeMethod('setFrame', {
                'width': compact ? 640.0 : 800.0,
                'height': compact ? 520.0 : 632.0,
              });
              if (mounted) {
                setState(() => _compactWindow = compact);
              }
            },
          ),
        ],
      ),
      floatingActionButton: _androidNativeDvReleaseDiagnostic
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                FloatingActionButton(
                  heroTag: 'file',
                  tooltip: 'Open [File]',
                  onPressed: () => showFilePicker(context, player,
                      openSource: Platform.isAndroid && _androidHdrTransaction
                          ? _openSelectedSource
                          : null),
                  child: const Icon(Icons.file_open),
                ),
                const SizedBox(width: 16.0),
                FloatingActionButton(
                  heroTag: 'uri',
                  tooltip: 'Open [Uri]',
                  onPressed: () => showURIPicker(context, player,
                      openSource: Platform.isAndroid && _androidHdrTransaction
                          ? _openSelectedSource
                          : null),
                  child: const Icon(Icons.link),
                ),
              ],
            ),
      body: SizedBox.expand(
        child: horizontal
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 3,
                    child: Container(
                      alignment: Alignment.center,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Expanded(
                            child: Card(
                              clipBehavior: Clip.antiAlias,
                              margin: const EdgeInsets.all(32.0),
                              child: useHdrVideo
                                  ? (AndroidSurfaceTexturePoc.enabled
                                      ? _pocFixedOutputLayout(
                                          HdrVideo(session: _hdrSession!))
                                      : HdrVideo(session: _hdrSession!))
                                  : displayController == null
                                      ? const ColoredBox(color: Colors.black)
                                      : Video(
                                          key: videoKey,
                                          controller: displayController,
                                        ),
                            ),
                          ),
                          const SizedBox(height: 32.0),
                        ],
                      ),
                    ),
                  ),
                  const VerticalDivider(width: 1.0, thickness: 1.0),
                  Expanded(
                    flex: 1,
                    child: ListView(
                      children: items,
                    ),
                  ),
                ],
              )
            : ListView(
                children: [
                  useHdrVideo
                      ? (AndroidSurfaceTexturePoc.enabled
                          ? _pocFixedOutputLayout(HdrVideo(
                              session: _hdrSession!,
                              controls: (_) => const SizedBox.shrink(),
                            ))
                          : HdrVideo(
                              session: _hdrSession!,
                              width: MediaQuery.of(context).size.width,
                              height:
                                  MediaQuery.of(context).size.width * 9.0 / 16.0,
                            ))
                      : displayController == null
                          ? AspectRatio(
                              aspectRatio: 16 / 9,
                              child: const ColoredBox(color: Colors.black),
                            )
                          : Video(
                              key: videoKey,
                              controller: displayController,
                              width: MediaQuery.of(context).size.width,
                              height: MediaQuery.of(context).size.width *
                                  9.0 /
                                  16.0,
                            ),
                  if (_androidFlutterRepaintProbe)
                    _androidFrameSchedulerProbe
                        ? RepaintBoundary(
                            key: _tickReadbackKey,
                            child: Text('FLUTTER_TICK $_flutterRepaintTick'),
                          )
                        : Text('FLUTTER_TICK $_flutterRepaintTick'),
                  ...items,
                ],
              ),
      ),
    );
    if (Platform.isAndroid && _autoSinglePlayer) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) unawaited(_exitAutoPlayerAfterDisposal());
        },
        child: page,
      );
    }
    return page;
  }
}
