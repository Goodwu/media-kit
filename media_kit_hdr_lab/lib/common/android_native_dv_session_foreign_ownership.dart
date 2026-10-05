import 'dart:async';
import 'dart:convert';

import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:media_kit_video/src/hdr/hdr_native_dv_option_owner.dart';
import 'package:media_kit_video/src/hdr/hdr_native_dv_review_evidence.dart';
import 'package:media_kit_video/src/hdr/hdr_disposal.dart';
import 'package:media_kit_video/src/hdr/hdr_open_coordinator.dart';
import 'package:media_kit_video/src/video_controller/android_video_controller/android_video_controller.dart';
import 'package:media_kit_video/src/video_controller/android_video_controller/platform_surface_release.dart';

// ignore_for_file: depend_on_referenced_packages, implementation_imports

const androidNativeDvForeignOwnershipMaxRows = 256;
const androidNativeDvForeignOwnershipMaxRawErrors = 32;
const androidNativeDvForeignOwnershipMaxText = 2048;

/// N4 compares the accepted wrapper and its actual current Android output.
/// Evidence names the platform controller, while Session publishes a wrapper.
/// Neither a reused output tuple nor another wrapper authorizes this binding.
bool androidNativeDvN4ControllerMatches({
  required Player player,
  required VideoController? currentWrapper,
  required VideoController? acceptedWrapper,
  required HdrNativeDvReviewEvidence evidence,
}) {
  if (currentWrapper == null ||
      acceptedWrapper == null ||
      !identical(currentWrapper, acceptedWrapper) ||
      !identical(currentWrapper.player, player)) {
    return false;
  }
  final platform = currentWrapper.notifier.value;
  return platform is AndroidVideoController &&
      identical(platform.player, player) &&
      identical(platform, evidence.controller) &&
      platform.currentBoundOutputIdentity == evidence.output;
}

/// Passive bounded evidence journal and one-shot same-Player ownership test.
/// This helper never selects a route, changes options, or uses Session.open.
class AndroidNativeDvSessionForeignOwnershipRun {
  AndroidNativeDvSessionForeignOwnershipRun({
    required this.player,
    required this.verifiedP5Source,
    this.maxRows = 128,
    this.transport = 'real-player-callback',
  }) {
    if (maxRows < 1 || maxRows > androidNativeDvForeignOwnershipMaxRows) {
      throw RangeError.range(
          maxRows, 1, androidNativeDvForeignOwnershipMaxRows, 'maxRows');
    }
    if (transport != 'real-player-callback' && transport != 'transportStub') {
      throw ArgumentError.value(transport, 'transport');
    }
    _clock.start();
  }

  final Player player;
  final String verifiedP5Source;
  final int maxRows;

  /// Host tests must explicitly use `transportStub`; device integration uses
  /// `real-player-callback`. The label is copied into the run and result.
  final String transport;

  final Stopwatch _clock = Stopwatch();
  final List<Map<String, Object?>> _journal = [];
  final List<AndroidNativeDvForeignOwnershipRawError> _rawErrors = [];
  HdrVideoSession? _session;
  String? _sessionInstanceId;
  _AcceptedNativeRoute? _accepted;
  _AppliedNativeRoute? _applied;
  Future<AndroidNativeDvForeignOwnershipResult>? _execution;
  Future<void>? _finalizeFuture;
  Future<void>? _closeFuture;
  bool _sessionDisposeIssued = false;
  bool _playerDisposeIssued = false;
  bool _closed = false;
  bool _closingRequested = false;
  bool _overflow = false;
  bool _rawErrorOverflow = false;
  int _rawErrorCount = 0;
  int? _foreignLoadedJournalIndex;
  bool _disposalStopEvidenceOverflow = false;
  final List<_StopAttemptEvidence> _disposalStopAttempts = [];
  bool _disposalStopReturned = false;
  bool _disposalResetObserved = false;
  bool _disposalStopIdentityMismatch = false;
  bool _ownershipOptionRestoreObserved = false;
  bool _postForeignSessionMutationObserved = false;
  Object? _sessionDisposeThrown;
  StackTrace? _sessionDisposeStack;
  HdrDisposalReport? _lastDisposeReport;
  Object? _playerDisposeThrown;
  StackTrace? _playerDisposeStack;
  _BoundarySnapshot? _foreignBoundary;
  _BoundarySnapshot? _afterSessionBoundary;
  VideoController? _acceptedController;
  bool? _controllerNativeSurfaceActiveBeforeDispose;
  bool? _controllerNativeSurfaceActiveAfterDispose;
  bool? _controllerRetiredObserved;
  AndroidSurfaceAccountId? _boundOutputIdentityBeforeDispose;
  AndroidSurfaceAccountId? _boundOutputIdentityAfterDispose;
  bool? _boundOutputWithdrawnObserved;
  final Set<String> _gaps = <String>{
    'backend-stop-issued-state-unobservable',
    'surface-release-acknowledgement-unobservable',
  };

  List<Map<String, Object?>> get journal =>
      List.unmodifiable(_journal.map(_freezeMap));
  List<AndroidNativeDvForeignOwnershipRawError> get rawErrors =>
      List.unmodifiable(_rawErrors);
  bool get overflow => _overflow;
  bool get rawErrorOverflow => _rawErrorOverflow;
  bool get closed => _closed;
  int get elapsedMicros => _clock.elapsedMicroseconds;

  /// Binds this run to the one actual Session before any callback is forwarded.
  void bindSession(HdrVideoSession session, String sessionInstanceId) {
    if (_closed ||
        _closingRequested ||
        _session != null ||
        sessionInstanceId.isEmpty) {
      throw StateError('N4 Session binding is closed, repeated, or empty');
    }
    _session = session;
    _sessionInstanceId = sessionInstanceId;
    _record('session-bound', {
      'sessionIdentity': identityHashCode(session),
      'sessionInstanceId': sessionInstanceId,
      'playerIdentity': identityHashCode(player),
    });
  }

  /// Called only by the actual Session consumer-validation callback.
  /// Callback work stays synchronous and only snapshots bounded scalar facts.
  void onConsumerValidated({
    required HdrVideoSession callbackSession,
    required String sessionInstanceId,
    required int generation,
    required HdrOpenPlan plan,
    required HdrReviewFacts facts,
  }) {
    final session = _session;
    final evidence = facts.nativeDvEvidence;
    final callbackBound = session != null &&
        identical(callbackSession, session) &&
        sessionInstanceId == _sessionInstanceId;
    final route = plan.route;
    final wrapper = session?.controller.value;
    final valid = callbackBound &&
        !_closed &&
        _execution == null &&
        evidence != null &&
        identical(evidence.source.player, player) &&
        evidence.source.path == verifiedP5Source &&
        evidence.loaded.epoch == evidence.source.fileLoadedEpoch &&
        evidence.loaded.playlistEntryId.toString() ==
            evidence.source.playlistEntryId &&
        route.strategy == HdrStrategy.nativeDolbyVision &&
        facts.path == verifiedP5Source &&
        facts.codec == 'hevc' &&
        facts.dolbyVisionProfile == 5 &&
        facts.dvCompatibilityId == 0 &&
        facts.dvElPresent == false &&
        session.report.value.generation == generation &&
        androidNativeDvN4ControllerMatches(
          player: player,
          currentWrapper: wrapper,
          acceptedWrapper: wrapper,
          evidence: evidence,
        );
    _record('consumer-validated', {
      'accepted': valid,
      'generation': generation,
      'callbackSessionIdentity': identityHashCode(callbackSession),
      'sessionIdentity': session == null ? null : identityHashCode(session),
      'sessionInstanceId': sessionInstanceId,
      'boundSessionInstanceId': _sessionInstanceId,
      'playerIdentity':
          evidence == null ? null : identityHashCode(evidence.source.player),
      'sourcePath': evidence?.source.path,
      'playlistEntryId': evidence?.source.playlistEntryId,
      'fileLoadedEpoch': evidence?.source.fileLoadedEpoch,
      'loadedEntryId': evidence?.loaded.playlistEntryId,
      'loadedEpoch': evidence?.loaded.epoch,
      'strategy': route.strategy.name,
      'profile': facts.dolbyVisionProfile,
      'codec': facts.codec,
      'controllerIdentity':
          evidence == null ? null : identityHashCode(evidence.controller),
      'wrapperIdentity': wrapper == null ? null : identityHashCode(wrapper),
      'platformControllerIdentity': wrapper?.notifier.value == null
          ? null
          : identityHashCode(wrapper!.notifier.value!),
      'output': evidence?.output.asChannelArguments(),
      'hwdecCurrent': evidence?.hwdecCurrent,
    });
    if (!valid) {
      _gaps.add('consumer-validation-not-bound-to-required-real-identity');
      return;
    }
    if (_accepted != null) {
      _gaps.add('multiple-native-consumer-validations-observed');
      return;
    }
    _accepted = _AcceptedNativeRoute(
      generation: generation,
      session: callbackSession,
      sessionInstanceId: sessionInstanceId,
      evidence: evidence,
      route: route,
      wrapper: wrapper!,
    );
    _acceptedController = wrapper;
  }

  /// Receives the actual Session broadcast event. A paired RouteApplied must
  /// describe the same accepted generation, Session instance, Player, entry,
  /// epoch, controller, and accepted output identity.
  void onSessionEvent({
    required HdrVideoSession callbackSession,
    required String sessionInstanceId,
    required HdrOutputEvent event,
  }) {
    final session = _session;
    final callbackBound = session != null &&
        identical(callbackSession, session) &&
        sessionInstanceId == _sessionInstanceId;
    final accepted = _accepted;
    if (event is HdrRouteAppliedEvent) {
      if (_foreignLoadedJournalIndex != null) {
        _gaps.add('session-route-or-rebuild-event-after-foreign-file-loaded');
      }
      final evidence = accepted?.evidence;
      final actual = event.report.actual;
      final valid = callbackBound &&
          !_closed &&
          accepted != null &&
          evidence != null &&
          identical(accepted.session, callbackSession) &&
          accepted.sessionInstanceId == sessionInstanceId &&
          accepted.generation == event.generation &&
          session.report.value.generation == event.generation &&
          event.report.generation == event.generation &&
          event.report.verified &&
          event.route.strategy == HdrStrategy.nativeDolbyVision &&
          actual?.strategy == HdrStrategy.nativeDolbyVision &&
          jsonEncode(_routeFields(event.route)) ==
              jsonEncode(_routeFields(accepted.route)) &&
          jsonEncode(_routeFields(actual)) ==
              jsonEncode(_routeFields(event.route)) &&
          event.report.hwdecCurrent == evidence.hwdecCurrent &&
          androidNativeDvN4ControllerMatches(
            player: player,
            currentWrapper: session.controller.value,
            acceptedWrapper: accepted.wrapper,
            evidence: evidence,
          );
      _record('route-applied', {
        'accepted': valid,
        'generation': event.generation,
        'callbackSessionIdentity': identityHashCode(callbackSession),
        'sessionInstanceId': sessionInstanceId,
        'route': _routeFields(event.route),
        'reportedActual': _routeFields(actual),
        'verified': event.report.verified,
        'reportedHwdecCurrent': event.report.hwdecCurrent,
        'acceptedOutput': evidence?.output.asChannelArguments(),
        'currentControllerMatchesAccepted': session != null &&
            evidence != null &&
            androidNativeDvN4ControllerMatches(
              player: player,
              currentWrapper: session.controller.value,
              acceptedWrapper: accepted?.wrapper,
              evidence: evidence,
            ),
      });
      if (valid) {
        _applied = _AppliedNativeRoute(
          generation: event.generation,
          session: callbackSession,
          sessionInstanceId: sessionInstanceId,
          route: event.route,
        );
      } else {
        _gaps.add('route-applied-not-paired-to-consumer-validation');
      }
    } else {
      _record('session-event', {
        'type': event.runtimeType.toString(),
        'generation': event.generation,
        'callbackBound': callbackBound,
        'sessionInstanceId': sessionInstanceId,
      });
      if (_foreignLoadedJournalIndex != null &&
          (event is HdrReclassifiedEvent ||
              (event is HdrRouteAppliedEvent &&
                  event.generation != accepted?.generation))) {
        _gaps.add('session-route-or-rebuild-event-after-foreign-file-loaded');
      }
    }
  }

  /// Captures the existing coordinator's real awaited boundaries. There is no
  /// core stop-issued callback, so this journal never infers that player.stop
  /// was or was not issued from an entered/failed boundary.
  void onBackendCallDiagnostic({
    required HdrVideoSession callbackSession,
    required String sessionInstanceId,
    required HdrBackendCallDiagnostic<HdrOpenPlan> diagnostic,
  }) {
    final callbackBound = identical(callbackSession, _session) &&
        sessionInstanceId == _sessionInstanceId;
    final route = diagnostic.invocation?.plan.route;
    final acceptedGeneration = _accepted?.generation;
    if (callbackBound &&
        diagnostic.purpose == HdrBackendDiagnosticPurpose.disposal) {
      if (diagnostic.method == HdrBackendDiagnosticMethod.stop) {
        if (diagnostic.boundary == HdrBackendDiagnosticBoundary.returned) {
          _disposalStopReturned = true;
        }
        if (diagnostic.owningSessionGeneration == acceptedGeneration &&
            (diagnostic.boundary == HdrBackendDiagnosticBoundary.entered ||
                diagnostic.boundary == HdrBackendDiagnosticBoundary.failed ||
                diagnostic.boundary == HdrBackendDiagnosticBoundary.returned)) {
          if (_disposalStopAttempts.length < maxRows) {
            _disposalStopAttempts.add(_StopAttemptEvidence(
              sequence: diagnostic.sequence,
              boundary: diagnostic.boundary,
              error: diagnostic.error,
            ));
          } else {
            _disposalStopEvidenceOverflow = true;
            _gaps.add('disposal-stop-evidence-capacity-exceeded');
          }
        } else if (acceptedGeneration != null) {
          _disposalStopIdentityMismatch = true;
        }
      } else if (diagnostic.method ==
          HdrBackendDiagnosticMethod.resetOwnedConfiguration) {
        _disposalResetObserved = true;
      }
    }
    final rowIndex = _record(
        'backend-call',
        {
          'callbackBound': callbackBound,
          'callbackSessionIdentity': identityHashCode(callbackSession),
          'sessionInstanceId': sessionInstanceId,
          'sequence': diagnostic.sequence,
          'elapsedMicros': diagnostic.elapsedMicros,
          'coordinatorGeneration': diagnostic.coordinatorGeneration,
          'sessionGeneration': diagnostic.sessionGeneration,
          'owningSessionGeneration': diagnostic.owningSessionGeneration,
          'method': diagnostic.method.name,
          'boundary': diagnostic.boundary.name,
          'purpose': diagnostic.purpose.name,
          'route': route == null ? null : _routeFields(route),
          'boundaryScope': diagnostic.boundaryScope,
          'errorType': diagnostic.error?.runtimeType.toString(),
          'error':
              diagnostic.error == null ? null : _boundedText(diagnostic.error!),
        },
        error: diagnostic.error,
        stackTrace: diagnostic.stack);
    if (callbackBound &&
        _foreignLoadedJournalIndex != null &&
        rowIndex > _foreignLoadedJournalIndex! &&
        (diagnostic.method == HdrBackendDiagnosticMethod.stop &&
                diagnostic.purpose != HdrBackendDiagnosticPurpose.disposal ||
            const {
              HdrBackendDiagnosticMethod.prepareOutput,
              HdrBackendDiagnosticMethod.configure,
              HdrBackendDiagnosticMethod.open,
              HdrBackendDiagnosticMethod.resetOwnedConfiguration,
            }.contains(diagnostic.method))) {
      _postForeignSessionMutationObserved = true;
      _gaps.add('session-backend-open-or-configure-after-foreign-file-loaded');
    }
  }

  /// Records the existing public option-owner notifications; it does not use
  /// them to authorize ownership or issue option writes.
  void onNativeOptionDiagnostic({
    required HdrVideoSession callbackSession,
    required String sessionInstanceId,
    required HdrNativeDvOptionDiagnostic diagnostic,
  }) {
    final callbackBound = identical(callbackSession, _session) &&
        sessionInstanceId == _sessionInstanceId;
    if (callbackBound &&
        _foreignLoadedJournalIndex != null &&
        (diagnostic.purpose == HdrNativeDvOptionDiagnosticPurpose.restore ||
            diagnostic.purpose ==
                HdrNativeDvOptionDiagnosticPurpose.restoreNoWrite ||
            diagnostic.purpose ==
                HdrNativeDvOptionDiagnosticPurpose.restoreFailure)) {
      _ownershipOptionRestoreObserved = true;
      _gaps.add('native-option-restore-observed');
    }
    _record(
        'native-option-diagnostic',
        {
          'callbackBound': identical(callbackSession, _session) &&
              sessionInstanceId == _sessionInstanceId,
          'sessionInstanceId': sessionInstanceId,
          'transactionIdentity': identityHashCode(diagnostic.transaction),
          'sourcePath': diagnostic.sourcePath,
          'sourcePlaylistEntryId': diagnostic.sourcePlaylistEntryId,
          'sourceFileLoadedEpoch': diagnostic.sourceFileLoadedEpoch,
          'purpose': diagnostic.purpose.name,
          'name': diagnostic.name,
          'original': diagnostic.original,
          'requested': diagnostic.requested,
          'observed': diagnostic.observed,
          'errorType': diagnostic.error?.runtimeType.toString(),
          'error':
              diagnostic.error == null ? null : _boundedText(diagnostic.error!),
        },
        error: diagnostic.error,
        stackTrace: diagnostic.stack);
  }

  /// Runs at most once. [rawPlayerOpen] must call the supplied same Player's
  /// ordinary serialized `open(Media(source))`; it must not call Session.open.
  /// The FILE_LOADED listener is installed before invoking that callback and
  /// waits outside Player.lock.
  Future<AndroidNativeDvForeignOwnershipResult> execute({
    required Future<void> Function(Player player, String sameP5Source)
        rawPlayerOpen,
    Duration fileLoadedTimeout = const Duration(seconds: 8),
  }) {
    if (_closingRequested || _closed) {
      return Future.error(StateError('N4 run is closing or already closed'));
    }
    return _execution ??= _execute(
      rawPlayerOpen: rawPlayerOpen,
      fileLoadedTimeout: fileLoadedTimeout,
    );
  }

  Future<AndroidNativeDvForeignOwnershipResult> _execute({
    required Future<void> Function(Player player, String sameP5Source)
        rawPlayerOpen,
    required Duration fileLoadedTimeout,
  }) async {
    var admissionPassed = false;
    var foreignLoaded = false;
    var sameSessionGenerationAfterForeign = false;
    Object? executionError;
    StackTrace? executionStack;
    StreamSubscription<FileLoadedRecord>? fileLoadedSubscription;
    try {
      final accepted = _accepted;
      final applied = _applied;
      final session = _session;
      if (_closed || accepted == null || applied == null || session == null) {
        throw StateError(
            'N4 requires paired actual consumerValidated and RouteApplied callbacks');
      }
      if (!identical(accepted.session, session) ||
          !identical(applied.session, session) ||
          accepted.sessionInstanceId != _sessionInstanceId ||
          applied.sessionInstanceId != _sessionInstanceId ||
          accepted.generation != applied.generation ||
          accepted.generation != session.report.value.generation ||
          !identical(accepted.evidence.source.player, player) ||
          accepted.evidence.source.path != verifiedP5Source ||
          accepted.evidence.loaded.epoch !=
              accepted.evidence.source.fileLoadedEpoch ||
          !androidNativeDvN4ControllerMatches(
            player: player,
            currentWrapper: session.controller.value,
            acceptedWrapper: accepted.wrapper,
            evidence: accepted.evidence,
          )) {
        throw StateError(
            'N4 acceptance identity changed before raw foreign open');
      }
      final before = await _captureBoundary('before-foreign-open');
      final beforeProblems = _validateAcceptedBoundary(before, accepted);
      if (beforeProblems.isNotEmpty) {
        throw StateError(
            'N4 pre-open source/options mismatch: ${beforeProblems.join(',')}');
      }
      // The property snapshot above awaits under Player.lock. Its final read
      // may retire or replace the accepted output, request Close, or advance
      // Session ownership. Recheck the live binding after that final await;
      // no further await occurs before dispatching the raw Player.open call.
      if (_closed ||
          _closingRequested ||
          player.disposed ||
          !identical(_session, session) ||
          !identical(_accepted, accepted) ||
          !identical(_applied, applied) ||
          !identical(accepted.session, session) ||
          !identical(applied.session, session) ||
          accepted.sessionInstanceId != _sessionInstanceId ||
          applied.sessionInstanceId != _sessionInstanceId ||
          accepted.generation != applied.generation ||
          accepted.generation != session.report.value.generation ||
          !identical(accepted.evidence.source.player, player) ||
          accepted.evidence.source.path != verifiedP5Source ||
          accepted.evidence.loaded.epoch !=
              accepted.evidence.source.fileLoadedEpoch ||
          player.fileLoadedEpoch != accepted.evidence.source.fileLoadedEpoch ||
          !androidNativeDvN4ControllerMatches(
            player: player,
            currentWrapper: session.controller.value,
            acceptedWrapper: accepted.wrapper,
            evidence: accepted.evidence,
          )) {
        throw StateError(
            'N4 acceptance identity changed after pre-open capture');
      }
      admissionPassed = true;
      _record('raw-player-open-request', {
        'transport': transport,
        'apiBoundary':
            'injected direct Player.open callback; Session.open excluded',
        'playerIdentity': identityHashCode(player),
        'sessionIdentity': identityHashCode(session),
        'sessionInstanceId': _sessionInstanceId,
        'sessionGenerationBefore': accepted.generation,
        'path': verifiedP5Source,
        'entryBefore': accepted.evidence.source.playlistEntryId,
        'epochBefore': accepted.evidence.source.fileLoadedEpoch,
      });

      final loadedCompleter = Completer<_FileLoadedOutcome>();
      final beforeEpoch = accepted.evidence.source.fileLoadedEpoch;
      fileLoadedSubscription = player.fileLoadedEpochController.stream.listen(
        (loaded) {
          if (!loadedCompleter.isCompleted && loaded.epoch > beforeEpoch) {
            if (loaded.playlistEntryId.toString() !=
                accepted.evidence.source.playlistEntryId) {
              _foreignLoadedJournalIndex = _record(
                'foreign-file-loaded-callback',
                {
                  'transport': transport,
                  'fileLoadedEpoch': loaded.epoch,
                  'playlistEntryId': loaded.playlistEntryId,
                  'playerIdentity': identityHashCode(player),
                  'sessionIdentity': identityHashCode(session),
                  'sessionInstanceId': _sessionInstanceId,
                  'sameSessionGenerationAtCallback':
                      session.report.value.generation == accepted.generation,
                },
              );
            }
            loadedCompleter.complete(_FileLoadedOutcome(record: loaded));
          }
        },
        onError: (Object error, StackTrace stack) {
          if (!loadedCompleter.isCompleted) {
            loadedCompleter
                .complete(_FileLoadedOutcome(error: error, stackTrace: stack));
          }
        },
      );
      // Always complete with a value. An early stream error must not become
      // unhandled while the injected Player.open callback is still settling.
      final loadedOutcomeFuture = loadedCompleter.future.timeout(
        fileLoadedTimeout,
        onTimeout: () => _FileLoadedOutcome(
          error: TimeoutException(
              'N4 matching FILE_LOADED timed out', fileLoadedTimeout),
        ),
      );
      // Player.open has no cancellation/abort acknowledgement in this API.
      // Do not time it out and race Session/Player disposal against the same
      // serialized native operation. The FILE_LOADED deadline records an
      // event timeout, but cleanup waits until rawPlayerOpen actually settles.
      await rawPlayerOpen(player, verifiedP5Source);
      _record('raw-player-open-returned', {
        'playerIdentity': identityHashCode(player),
        'sessionGeneration': session.report.value.generation,
      });
      final loadedOutcome = await loadedOutcomeFuture;
      if (loadedOutcome.error != null) {
        Error.throwWithStackTrace(
          loadedOutcome.error!,
          loadedOutcome.stackTrace ?? StackTrace.current,
        );
      }
      final loaded = loadedOutcome.record!;
      await fileLoadedSubscription.cancel();
      fileLoadedSubscription = null;
      final foreign = await _captureBoundary('foreign-file-loaded');
      _foreignBoundary = foreign;
      _record('foreign-file-loaded', {
        'transport': transport,
        'fileLoadedEpoch': loaded.epoch,
        'playlistEntryId': loaded.playlistEntryId,
        'identity': foreign.toJson(),
        'entryChanged': loaded.playlistEntryId.toString() !=
            accepted.evidence.source.playlistEntryId,
        'epochAdvanced':
            loaded.epoch > accepted.evidence.source.fileLoadedEpoch,
        'pathMatchesSameP5Uri': foreign.properties['path'] == verifiedP5Source,
      });
      foreignLoaded = loaded.epoch > accepted.evidence.source.fileLoadedEpoch &&
          loaded.playlistEntryId.toString() !=
              accepted.evidence.source.playlistEntryId &&
          loaded.epoch == foreign.epochAfter &&
          loaded.playlistEntryId.toString() ==
              foreign.properties['playlist/0/id'] &&
          foreign.properties['path'] == verifiedP5Source &&
          foreign.epochStable;
      if (!foreignLoaded) {
        throw StateError(
            'N4 FILE_LOADED did not bind the same-URI new entry and epoch');
      }
      sameSessionGenerationAfterForeign = identical(session, _session) &&
          _sessionInstanceId == accepted.sessionInstanceId &&
          session.report.value.generation == accepted.generation;
      _record('post-foreign-generation-check', {
        'sameSession': identical(session, _session),
        'sessionInstanceId': _sessionInstanceId,
        'expectedGeneration': accepted.generation,
        'actualGeneration': session.report.value.generation,
        'sameSessionGeneration': sameSessionGenerationAfterForeign,
      });
      if (!sameSessionGenerationAfterForeign) {
        _gaps.add('foreign-open-changed-session-generation-or-instance');
        throw StateError('N4 foreign open changed Session generation/instance');
      }
      _controllerNativeSurfaceActiveBeforeDispose =
          _acceptedController?.nativeSurfaceActive;
      _boundOutputIdentityBeforeDispose = await _readBoundOutputIdentity();
    } catch (error, stack) {
      executionError = error;
      executionStack = stack;
      _record(
          'n4-execution-error',
          {
            'errorType': error.runtimeType.toString(),
            'error': _boundedText(error),
            'admissionPassed': admissionPassed,
            'foreignFileLoaded': foreignLoaded,
          },
          error: error,
          stackTrace: stack);
    } finally {
      try {
        await fileLoadedSubscription?.cancel();
      } catch (error, stack) {
        _gaps.add('file-loaded-subscription-cancel-failed');
        _record(
          'file-loaded-subscription-cancel-error',
          {
            'errorType': error.runtimeType.toString(),
            'error': _boundedText(error),
          },
          error: error,
          stackTrace: stack,
        );
      }
      await _finalize();
    }
    return _buildResult(
      admissionPassed: admissionPassed,
      foreignLoaded: foreignLoaded,
      sameSessionGenerationAfterForeign: sameSessionGenerationAfterForeign,
      executionError: executionError,
      executionStack: executionStack,
    );
  }

  /// Drains an active execution. Calling it before execute closes this
  /// experiment-only Session and Player, without claiming an N4 run occurred.
  Future<void> close({Object? error, StackTrace? stackTrace}) =>
      _requestClose(error: error, stackTrace: stackTrace);

  Future<void> _requestClose({Object? error, StackTrace? stackTrace}) {
    _closingRequested = true;
    return _closeFuture ??= _close(error: error, stackTrace: stackTrace);
  }

  /// Waits for the one cached execution (when started) and returns the
  /// immutable journal snapshot. It does not claim device acceptance.
  Future<List<Map<String, Object?>>> drain() async {
    final execution = _execution;
    if (execution != null) {
      try {
        await execution;
      } catch (_) {
        // The original error remains in the execution result/raw error list.
      }
    }
    return journal;
  }

  Future<void> _close({Object? error, StackTrace? stackTrace}) async {
    if (error != null) {
      _record(
          'external-close-error',
          {
            'errorType': error.runtimeType.toString(),
            'error': _boundedText(error),
          },
          error: error,
          stackTrace: stackTrace);
    }
    final execution = _execution;
    if (execution != null) {
      try {
        await execution;
      } catch (caught, stack) {
        _record(
            'execution-drain-error',
            {
              'errorType': caught.runtimeType.toString(),
              'error': _boundedText(caught),
            },
            error: caught,
            stackTrace: stack);
      }
    }
    await _finalize();
    _closed = true;
    _record('closed', {'ownerRestoration': 'not-claimed'});
  }

  Future<void> _finalize() => _finalizeFuture ??= _finalizeOnce();

  Future<void> _finalizeOnce() async {
    final session = _session;
    if (session != null && !_sessionDisposeIssued) {
      _sessionDisposeIssued = true;
      _record('session-dispose-entered', {
        'sessionIdentity': identityHashCode(session),
        'sessionInstanceId': _sessionInstanceId,
        'generationBeforeDispose': _accepted?.generation,
        'foreignFileLoaded': _foreignBoundary != null,
      });
      try {
        await session.dispose();
      } catch (error, stack) {
        _sessionDisposeThrown = error;
        _sessionDisposeStack = stack;
        _record(
            'session-dispose-threw',
            {
              'errorType': error.runtimeType.toString(),
              'error': _boundedText(error),
            },
            error: error,
            stackTrace: stack);
      }
      _lastDisposeReport = session.lastDisposeReport;
      final report = _lastDisposeReport;
      if (report?.coordinatorError != null) {
        _record(
            'session-coordinator-error',
            {
              'errorType': report!.coordinatorError.runtimeType.toString(),
              'error': _boundedText(report.coordinatorError!),
              'clean': report.clean,
            },
            error: report.coordinatorError);
      }
      try {
        _afterSessionBoundary = await _captureBoundary('after-session-dispose');
      } catch (error, stack) {
        _gaps.add('post-session-dispose-source-or-options-read-failed');
        _record(
            'post-session-dispose-read-error',
            {
              'errorType': error.runtimeType.toString(),
              'error': _boundedText(error),
            },
            error: error,
            stackTrace: stack);
      }
      final activeAfter = _acceptedController?.nativeSurfaceActive;
      _controllerNativeSurfaceActiveAfterDispose = activeAfter;
      final activeBefore = _controllerNativeSurfaceActiveBeforeDispose;
      _controllerRetiredObserved = activeBefore == true && activeAfter == false;
      if (_controllerRetiredObserved != true) {
        _gaps.add('controller-retirement-not-observed-as-active-to-inactive');
      }
      _boundOutputIdentityAfterDispose = await _readBoundOutputIdentity();
      final boundBefore = _boundOutputIdentityBeforeDispose;
      final boundAfter = _boundOutputIdentityAfterDispose;
      _boundOutputWithdrawnObserved = boundBefore == null
          ? null
          : boundAfter == null;
      if (boundBefore == null) {
        _gaps.add('bound-output-identity-not-observed-before-dispose');
      } else if (boundAfter != null) {
        _gaps.add('bound-output-identity-not-withdrawn-after-dispose');
      }
      if (report != null && report.coordinatorError == null) {
        _gaps.remove('backend-stop-issued-state-unobservable');
      }
      _record(
          'session-dispose-completed',
          {
            'lastDisposeReportClean': report?.clean,
            'coordinatorErrorType':
                report?.coordinatorError?.runtimeType.toString(),
            'coordinatorError': report?.coordinatorError == null
                ? null
                : _boundedText(report!.coordinatorError!),
            'sessionDisposeThrownType':
                _sessionDisposeThrown?.runtimeType.toString(),
            'sessionDisposeThrown': _sessionDisposeThrown == null
                ? null
                : _boundedText(_sessionDisposeThrown!),
            'controllerNativeSurfaceActiveBefore': activeBefore,
            'controllerNativeSurfaceActiveAfter': activeAfter,
            'controllerRetiredObserved': _controllerRetiredObserved,
            'boundOutputHandleBefore': boundBefore?.handle,
            'boundOutputGenerationBefore': boundBefore?.generation,
            'boundOutputViewIdBefore': boundBefore?.viewId,
            'boundOutputWidBefore': boundBefore?.wid,
            'boundOutputHandleAfter': boundAfter?.handle,
            'boundOutputGenerationAfter': boundAfter?.generation,
            'boundOutputViewIdAfter': boundAfter?.viewId,
            'boundOutputWidAfter': boundAfter?.wid,
            'boundOutputWithdrawnObserved': _boundOutputWithdrawnObserved,
            'boundOutputWithdrawnBasis':
                'public currentBoundOutputIdentity snapshot before/after '
                'Session.dispose; withdrawal is not a Surface release '
                'acknowledgement or resource-recovery proof',
            'ownerRestoration': 'not-claimed',
            'surfaceReleaseAcknowledgement': 'not independently observed',
          },
          error: report?.coordinatorError ?? _sessionDisposeThrown,
          stackTrace: _sessionDisposeStack);
    }
    if (!_playerDisposeIssued) {
      _playerDisposeIssued = true;
      _record('player-dispose-entered', {
        'playerIdentity': identityHashCode(player),
        'afterSessionDispose': _sessionDisposeIssued,
      });
      try {
        await player.dispose();
      } catch (error, stack) {
        _playerDisposeThrown = error;
        _playerDisposeStack = stack;
        _record(
            'player-dispose-threw',
            {
              'errorType': error.runtimeType.toString(),
              'error': _boundedText(error),
            },
            error: error,
            stackTrace: stack);
      }
      _record(
          'player-termination',
          {
            'success': _playerDisposeThrown == null,
            'errorType': _playerDisposeThrown?.runtimeType.toString(),
            'error': _playerDisposeThrown == null
                ? null
                : _boundedText(_playerDisposeThrown!),
            'distinctFromSessionOwnership': true,
          },
          error: _playerDisposeThrown,
          stackTrace: _playerDisposeStack);
    }
    _closed = true;
  }

  /// Reads the public bound-output identity off the accepted controller's
  /// Android platform controller. Null when no controller was accepted, the
  /// platform future fails, or no output is currently bound. A withdrawal
  /// observed through this getter is a binding-state fact only; it is not a
  /// Surface release acknowledgement nor a resource-recovery proof.
  Future<AndroidSurfaceAccountId?> _readBoundOutputIdentity() async {
    final controller = _acceptedController;
    if (controller == null) return null;
    try {
      final platform = await controller.platform.future;
      if (platform is AndroidVideoController) {
        return platform.currentBoundOutputIdentity;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<_BoundarySnapshot> _captureBoundary(String phase) =>
      player.lock.synchronized(() async {
        final beforeEpoch = player.fileLoadedEpoch;
        final properties = <String, String>{};
        final propertyErrors = <String, String>{};
        for (final name in const [
          'path',
          'playlist/0/id',
          'vd-lavc-o',
          'mediacodec-embed-render-mode',
          'vo',
          'hwdec-current',
          'pause',
          'time-pos',
        ]) {
          try {
            properties[name] = await player.getProperty(
              name,
              waitForInitialization: false,
            );
          } catch (error, stack) {
            final raw = _recordRawError(
              phase: phase,
              property: name,
              error: error,
              stackTrace: stack,
            );
            propertyErrors[name] =
                'rawError#${raw.index}:${_boundedText(error)}';
          }
        }
        final afterEpoch = player.fileLoadedEpoch;
        final stable = beforeEpoch == afterEpoch;
        _record('source-option-boundary', {
          'phase': phase,
          'playerIdentity': identityHashCode(player),
          'fileLoadedEpochBeforeProperties': beforeEpoch,
          'fileLoadedEpochAfterProperties': afterEpoch,
          'epochStable': stable,
          'properties': properties,
          'propertyErrors': propertyErrors,
        });
        return _BoundarySnapshot(
          phase: phase,
          epochBefore: beforeEpoch,
          epochAfter: afterEpoch,
          properties: Map.unmodifiable(properties),
          propertyErrors: Map.unmodifiable(propertyErrors),
        );
      });

  List<String> _validateAcceptedBoundary(
      _BoundarySnapshot boundary, _AcceptedNativeRoute accepted) {
    final failures = <String>[];
    final evidence = accepted.evidence;
    if (!boundary.epochStable) failures.add('epoch-unstable');
    if (boundary.properties['path'] != verifiedP5Source ||
        boundary.properties['path'] != evidence.source.path) {
      failures.add('path');
    }
    if (boundary.properties['playlist/0/id'] !=
        evidence.source.playlistEntryId) {
      failures.add('playlist-entry-id');
    }
    if (boundary.epochAfter != evidence.source.fileLoadedEpoch) {
      failures.add('fileLoadedEpoch');
    }
    if (boundary.properties['hwdec-current'] != evidence.hwdecCurrent) {
      failures.add('hwdec-current');
    }
    if (boundary.properties['vd-lavc-o'] != 'native_dv=1') {
      failures.add('vd-lavc-o');
    }
    if (boundary.properties['mediacodec-embed-render-mode'] != 'timed') {
      failures.add('mediacodec-embed-render-mode');
    }
    if (boundary.propertyErrors.isNotEmpty) {
      failures.add('identity-or-option-property-read-error');
    }
    return failures;
  }

  AndroidNativeDvForeignOwnershipResult _buildResult({
    required bool admissionPassed,
    required bool foreignLoaded,
    required bool sameSessionGenerationAfterForeign,
    Object? executionError,
    StackTrace? executionStack,
  }) {
    final foreign = _foreignBoundary;
    final after = _afterSessionBoundary;
    final report = _lastDisposeReport;
    final sameForeignIdentityAfterDispose = foreign != null &&
        after != null &&
        foreign.properties['path'] == after.properties['path'] &&
        foreign.properties['playlist/0/id'] ==
            after.properties['playlist/0/id'] &&
        foreign.epochAfter == after.epochAfter;
    final optionsAfterSame = foreign != null &&
        after != null &&
        foreign.properties['vd-lavc-o'] == after.properties['vd-lavc-o'] &&
        foreign.properties['mediacodec-embed-render-mode'] ==
            after.properties['mediacodec-embed-render-mode'];
    final journalAfterForeign = _foreignLoadedJournalIndex == null
        ? const <Map<String, Object?>>[]
        : _journal
            .skip(_foreignLoadedJournalIndex! + 1)
            .where((row) => row['kind'] == 'backend-call')
            .toList();
    final noSessionOpenOrConfigureAfterForeign = journalAfterForeign.every(
          (row) =>
              !const {
                'resetOwnedConfiguration',
                'prepareOutput',
                'configure',
                'open',
              }.contains(row['method']) &&
              !(row['method'] == 'stop' && row['purpose'] != 'disposal'),
        ) &&
        !_postForeignSessionMutationObserved &&
        !_gaps.contains(
            'session-route-or-rebuild-event-after-foreign-file-loaded');
    final ownershipStopRefusalObserved =
        _hasBoundDisposalStopRefusal(report?.coordinatorError);
    return AndroidNativeDvForeignOwnershipResult(
      n4ExecutionAdmitted: admissionPassed,
      foreignFileLoadedMatched: foreignLoaded,
      sameSessionGenerationAfterForeign: sameSessionGenerationAfterForeign,
      sameForeignIdentityAfterSessionDispose: sameForeignIdentityAfterDispose,
      optionsUnchangedAcrossSessionDispose: optionsAfterSame,
      lastDisposeReportClean: report?.clean,
      coordinatorError: report?.coordinatorError,
      coordinatorErrorType: report?.coordinatorError?.runtimeType.toString(),
      coordinatorErrorText: report?.coordinatorError == null
          ? null
          : _boundedText(report!.coordinatorError!),
      sessionDisposeThrown: _sessionDisposeThrown,
      sessionDisposeThrownStack: _sessionDisposeStack,
      sessionDebtObserved:
          report?.coordinatorError != null || report?.clean == false,
      ownershipStopRefusalObserved: ownershipStopRefusalObserved,
      noSessionOpenOrConfigureAfterForeign:
          noSessionOpenOrConfigureAfterForeign,
      controllerRetiredObserved: _controllerRetiredObserved,
      controllerNativeSurfaceActiveBeforeDispose:
          _controllerNativeSurfaceActiveBeforeDispose,
      controllerNativeSurfaceActiveAfterDispose:
          _controllerNativeSurfaceActiveAfterDispose,
      playerTerminated: _playerDisposeIssued && _playerDisposeThrown == null,
      playerDisposeError: _playerDisposeThrown,
      playerDisposeStack: _playerDisposeStack,
      ownerRestoration: 'not-claimed',
      backendStopIssued: report == null
          ? 'not-observed-no-dispose-report'
          : (report.coordinatorError == null
              ? 'issued-inferred-from-clean-dispose-report'
              : 'issued-verify-failed-coordinator-error'),
      backendStopIssuedBasis:
          'derived from Session.dispose report coordinator-error absence; '
          'not core telemetry',
      boundOutputWithdrawnObserved: _boundOutputWithdrawnObserved,
      boundOutputHandleBeforeDispose:
          _boundOutputIdentityBeforeDispose?.handle,
      boundOutputGenerationBeforeDispose:
          _boundOutputIdentityBeforeDispose?.generation,
      boundOutputViewIdBeforeDispose:
          _boundOutputIdentityBeforeDispose?.viewId,
      boundOutputWidBeforeDispose: _boundOutputIdentityBeforeDispose?.wid,
      boundOutputHandleAfterDispose: _boundOutputIdentityAfterDispose?.handle,
      boundOutputGenerationAfterDispose:
          _boundOutputIdentityAfterDispose?.generation,
      boundOutputViewIdAfterDispose:
          _boundOutputIdentityAfterDispose?.viewId,
      boundOutputWidAfterDispose: _boundOutputIdentityAfterDispose?.wid,
      n4DeviceAcceptance: false,
      transport: transport,
      executionError: executionError,
      executionStack: executionStack,
      evidenceGaps: List.unmodifiable(_gaps),
      journal: journal,
      rawErrors: rawErrors,
      overflow: _overflow,
      rawErrorOverflow: _rawErrorOverflow,
    );
  }

  bool _hasBoundDisposalStopRefusal(Object? reportError) {
    final expectedGeneration = _accepted?.generation;
    if (reportError == null ||
        expectedGeneration == null ||
        _disposalStopReturned ||
        _disposalResetObserved ||
        _disposalStopIdentityMismatch ||
        _disposalStopEvidenceOverflow ||
        _ownershipOptionRestoreObserved) {
      return false;
    }
    final unmatchedEnters = <int>[];
    var matchingFailureObserved = false;
    var malformed = false;
    for (final attempt in _disposalStopAttempts) {
      switch (attempt.boundary) {
        case HdrBackendDiagnosticBoundary.entered:
          unmatchedEnters.add(attempt.sequence);
          break;
        case HdrBackendDiagnosticBoundary.failed:
          final enteredIndex = unmatchedEnters.indexWhere(
            (sequence) => sequence < attempt.sequence,
          );
          if (enteredIndex < 0 || attempt.error == null) {
            malformed = true;
            break;
          }
          unmatchedEnters.removeAt(enteredIndex);
          if (identical(attempt.error, reportError)) {
            matchingFailureObserved = true;
          }
          break;
        case HdrBackendDiagnosticBoundary.returned:
          malformed = true;
          break;
      }
    }
    return !malformed && unmatchedEnters.isEmpty && matchingFailureObserved;
  }

  int _record(
    String kind,
    Map<String, Object?> fields, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (_journal.length >= maxRows) {
      _overflow = true;
      _gaps.add('journal-row-capacity-exceeded');
      return _journal.length;
    }
    final row = <String, Object?>{
      'index': _journal.length,
      'elapsedMicros': _clock.elapsedMicroseconds,
      'kind': kind,
      ...fields,
    };
    if (error != null) {
      final raw = _recordRawError(
        phase: kind,
        error: error,
        stackTrace: stackTrace,
      );
      row['rawErrorIndex'] = raw.index;
      row['errorType'] = error.runtimeType.toString();
      row['error'] = _boundedText(error);
      row['stack'] = stackTrace == null ? null : _boundedText(stackTrace);
    }
    _journal.add(_freezeMap(row));
    return _journal.length - 1;
  }

  AndroidNativeDvForeignOwnershipRawError _recordRawError({
    required String phase,
    required Object error,
    required StackTrace? stackTrace,
    String? property,
  }) {
    final raw = AndroidNativeDvForeignOwnershipRawError(
      index: _rawErrorCount++,
      phase: phase,
      property: property,
      error: error,
      stackTrace: stackTrace,
    );
    if (_rawErrors.length < androidNativeDvForeignOwnershipMaxRawErrors) {
      _rawErrors.add(raw);
    } else {
      _rawErrorOverflow = true;
      _gaps.add('raw-error-capacity-exceeded');
    }
    return raw;
  }

  static Map<String, Object?> _routeFields(HdrRoute? route) => route == null
      ? const <String, Object?>{}
      : {
          'strategy': route.strategy.name,
          'presentation': route.presentation.name,
          'outputTransfer': route.outputTransfer.name,
          'topology': route.topology.name,
          'vo': route.vo,
          'hwdec': route.hwdec,
          'vdLavcOptions': route.vdLavcOptions,
          'renderMode': route.mediacodecEmbedRenderMode,
          'targetPrim': route.targetPrim,
          'targetTrc': route.targetTrc,
          'surfaceTransfer': route.surfaceTransfer,
          'stripDvRpu': route.stripDvRpu,
        };
}

class AndroidNativeDvForeignOwnershipResult {
  const AndroidNativeDvForeignOwnershipResult({
    required this.n4ExecutionAdmitted,
    required this.foreignFileLoadedMatched,
    required this.sameSessionGenerationAfterForeign,
    required this.sameForeignIdentityAfterSessionDispose,
    required this.optionsUnchangedAcrossSessionDispose,
    required this.lastDisposeReportClean,
    required this.coordinatorError,
    required this.coordinatorErrorType,
    required this.coordinatorErrorText,
    required this.sessionDisposeThrown,
    required this.sessionDisposeThrownStack,
    required this.sessionDebtObserved,
    required this.ownershipStopRefusalObserved,
    required this.noSessionOpenOrConfigureAfterForeign,
    required this.controllerRetiredObserved,
    required this.controllerNativeSurfaceActiveBeforeDispose,
    required this.controllerNativeSurfaceActiveAfterDispose,
    required this.playerTerminated,
    required this.playerDisposeError,
    required this.playerDisposeStack,
    required this.ownerRestoration,
    required this.backendStopIssued,
    required this.backendStopIssuedBasis,
    required this.boundOutputWithdrawnObserved,
    required this.boundOutputHandleBeforeDispose,
    required this.boundOutputGenerationBeforeDispose,
    required this.boundOutputViewIdBeforeDispose,
    required this.boundOutputWidBeforeDispose,
    required this.boundOutputHandleAfterDispose,
    required this.boundOutputGenerationAfterDispose,
    required this.boundOutputViewIdAfterDispose,
    required this.boundOutputWidAfterDispose,
    required this.n4DeviceAcceptance,
    required this.transport,
    required this.executionError,
    required this.executionStack,
    required this.evidenceGaps,
    required this.journal,
    required this.rawErrors,
    required this.overflow,
    required this.rawErrorOverflow,
  });

  final bool n4ExecutionAdmitted;
  final bool foreignFileLoadedMatched;
  final bool sameSessionGenerationAfterForeign;
  final bool sameForeignIdentityAfterSessionDispose;
  final bool optionsUnchangedAcrossSessionDispose;
  final bool? lastDisposeReportClean;
  final Object? coordinatorError;
  final String? coordinatorErrorType;
  final String? coordinatorErrorText;
  final Object? sessionDisposeThrown;
  final StackTrace? sessionDisposeThrownStack;
  final bool sessionDebtObserved;
  final bool ownershipStopRefusalObserved;
  final bool noSessionOpenOrConfigureAfterForeign;
  final bool? controllerRetiredObserved;
  final bool? controllerNativeSurfaceActiveBeforeDispose;
  final bool? controllerNativeSurfaceActiveAfterDispose;
  final bool playerTerminated;
  final Object? playerDisposeError;
  final StackTrace? playerDisposeStack;
  final String ownerRestoration;
  final String backendStopIssued;
  final String backendStopIssuedBasis;
  final bool? boundOutputWithdrawnObserved;
  final int? boundOutputHandleBeforeDispose;
  final int? boundOutputGenerationBeforeDispose;
  final int? boundOutputViewIdBeforeDispose;
  final int? boundOutputWidBeforeDispose;
  final int? boundOutputHandleAfterDispose;
  final int? boundOutputGenerationAfterDispose;
  final int? boundOutputViewIdAfterDispose;
  final int? boundOutputWidAfterDispose;
  final bool n4DeviceAcceptance;
  final String transport;
  final Object? executionError;
  final StackTrace? executionStack;
  final List<String> evidenceGaps;
  final List<Map<String, Object?>> journal;
  final List<AndroidNativeDvForeignOwnershipRawError> rawErrors;
  final bool overflow;
  final bool rawErrorOverflow;

  bool get acceptedByHostEvidence =>
      n4ExecutionAdmitted &&
      foreignFileLoadedMatched &&
      sameSessionGenerationAfterForeign &&
      sameForeignIdentityAfterSessionDispose &&
      optionsUnchangedAcrossSessionDispose &&
      lastDisposeReportClean == false &&
      sessionDebtObserved &&
      ownershipStopRefusalObserved &&
      noSessionOpenOrConfigureAfterForeign &&
      playerTerminated &&
      !overflow &&
      !rawErrorOverflow;
}

class AndroidNativeDvForeignOwnershipRawError {
  const AndroidNativeDvForeignOwnershipRawError({
    required this.index,
    required this.phase,
    required this.error,
    required this.stackTrace,
    this.property,
  });

  final int index;
  final String phase;
  final String? property;
  final Object error;
  final StackTrace? stackTrace;
}

class _AcceptedNativeRoute {
  const _AcceptedNativeRoute({
    required this.generation,
    required this.session,
    required this.sessionInstanceId,
    required this.evidence,
    required this.route,
    required this.wrapper,
  });

  final int generation;
  final HdrVideoSession session;
  final String sessionInstanceId;
  final HdrNativeDvReviewEvidence evidence;
  final HdrRoute route;
  final VideoController wrapper;
}

class _AppliedNativeRoute {
  const _AppliedNativeRoute({
    required this.generation,
    required this.session,
    required this.sessionInstanceId,
    required this.route,
  });

  final int generation;
  final HdrVideoSession session;
  final String sessionInstanceId;
  final HdrRoute route;
}

class _StopAttemptEvidence {
  const _StopAttemptEvidence({
    required this.sequence,
    required this.boundary,
    required this.error,
  });

  final int sequence;
  final HdrBackendDiagnosticBoundary boundary;
  final Object? error;
}

class _BoundarySnapshot {
  const _BoundarySnapshot({
    required this.phase,
    required this.epochBefore,
    required this.epochAfter,
    required this.properties,
    required this.propertyErrors,
  });

  final String phase;
  final int epochBefore;
  final int epochAfter;
  final Map<String, String> properties;
  final Map<String, String> propertyErrors;
  bool get epochStable => epochBefore == epochAfter;

  Map<String, Object?> toJson() => {
        'phase': phase,
        'epochBefore': epochBefore,
        'epochAfter': epochAfter,
        'epochStable': epochStable,
        'properties': properties,
        'propertyErrors': propertyErrors,
      };
}

class _FileLoadedOutcome {
  const _FileLoadedOutcome({this.record, this.error, this.stackTrace});
  final FileLoadedRecord? record;
  final Object? error;
  final StackTrace? stackTrace;
}

String _boundedText(Object value) {
  final text = value.toString();
  return text.length <= androidNativeDvForeignOwnershipMaxText
      ? text
      : text.substring(0, androidNativeDvForeignOwnershipMaxText);
}

Map<String, Object?> _freezeMap(Map<String, Object?> value) {
  Object? freeze(Object? child) {
    if (child is Map) {
      return Map.unmodifiable(
          child.map((key, value) => MapEntry(key, freeze(value))));
    }
    if (child is List) return List.unmodifiable(child.map(freeze));
    return child;
  }

  return Map.unmodifiable(
      value.map((key, child) => MapEntry(key, freeze(child))));
}
