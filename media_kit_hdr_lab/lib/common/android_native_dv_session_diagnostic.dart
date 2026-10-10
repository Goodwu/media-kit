import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:media_kit_video/src/hdr/android_mediacodec_configuration.dart';
import 'package:media_kit_video/src/hdr/hdr_native_dv_review_evidence.dart';
import 'package:media_kit_video/src/hdr/hdr_native_dv_option_owner.dart'
    show HdrOptionSourceIdentity;
import 'package:media_kit_video/src/hdr/hdr_disposal.dart'
    show HdrDisposalReport;
import 'package:media_kit_video/src/video_controller/android_video_controller/platform_surface_release.dart';
import 'package:media_kit_video/src/video_controller/android_video_controller/android_video_controller.dart';
import 'package:path_provider/path_provider.dart' as path_provider;
import 'package:synchronized/synchronized.dart';

import 'android_native_dv_session_lifecycle.dart';

// Lab-only diagnostic. It observes the real Session and never owns/writes
// native options. The fixed-path descriptor is a caller hint, not extractor
// evidence; external collection must bind the media hash.
// ignore_for_file: depend_on_referenced_packages, implementation_imports, invalid_use_of_visible_for_testing_member

const androidNativeDvSessionDiagnosticSource =
    '/data/local/tmp/media-kit-lg-dv-p5-2160p.mp4';
const androidNativeDvSessionDiagnosticMaxRows = 300;

const _androidNativeDvRejectionTextLimit = 2048;
const _sdrRouteEvidenceTextLimit = 128;
const _sdrRouteEvidenceDependencyLimit = 8;

const _lgApi24SdrTextureRoute = HdrRoute(
  strategy: HdrStrategy.sdrDirect,
  presentation: HdrPresentation.sdr,
  outputTransfer: HdrOutputTransfer.sdr,
  appliesDynamicMetadata: false,
  topology: HdrTopology.texture,
  vo: 'gpu-next',
  hwdec: 'mediacodec-copy',
  targetPrim: null,
  targetTrc: null,
  surfaceTransfer: null,
  stripDvRpu: false,
  dependencies: <String>{HdrRouteDependency.hwdecMediacodecCopy},
);

Map<String, Object?> _sdrRouteEvidence(
  HdrRoute? route, {
  required List<String> truncatedFields,
  required String fieldPrefix,
}) {
  String? boundedNullableText(String? value, String field) => value == null
      ? null
      : _boundedRejectionText(
          value,
          limit: _sdrRouteEvidenceTextLimit,
          truncatedFields: truncatedFields,
          fieldName: '$fieldPrefix.$field',
        );

  final dependencies = route?.dependencies;
  if (dependencies != null &&
      dependencies.length > _sdrRouteEvidenceDependencyLimit) {
    final field = '$fieldPrefix.dependencies';
    if (!truncatedFields.contains(field)) truncatedFields.add(field);
  }
  return <String, Object?>{
    'strategy': route?.strategy.name,
    'presentation': route?.presentation.name,
    'outputTransfer': route?.outputTransfer.name,
    'appliesDynamicMetadata': route?.appliesDynamicMetadata,
    'topology': route?.topology.name,
    'vo': boundedNullableText(route?.vo, 'vo'),
    'hwdec': boundedNullableText(route?.hwdec, 'hwdec'),
    'hwdecCurrent': boundedNullableText(route?.hwdec, 'hwdecCurrent'),
    'vdLavcOptions': boundedNullableText(route?.vdLavcOptions, 'vdLavcOptions'),
    'mediacodecEmbedRenderMode':
        boundedNullableText(route?.mediacodecEmbedRenderMode, 'renderMode'),
    'targetPrim': boundedNullableText(route?.targetPrim, 'targetPrim'),
    'targetTrc': boundedNullableText(route?.targetTrc, 'targetTrc'),
    'surfaceTransfer':
        boundedNullableText(route?.surfaceTransfer, 'surfaceTransfer'),
    'stripDvRpu': route?.stripDvRpu,
    'dependencies': dependencies == null
        ? null
        : <String>[
            for (final dependency
                in dependencies.take(_sdrRouteEvidenceDependencyLimit))
              _boundedRejectionText(
                dependency,
                limit: _sdrRouteEvidenceTextLimit,
                truncatedFields: truncatedFields,
                fieldName: '$fieldPrefix.dependencies',
              ),
          ],
  };
}

String _boundedRejectionText(
  Object? value, {
  int limit = 256,
  List<String>? truncatedFields,
  String? fieldName,
}) {
  final text = value?.toString() ?? '';
  if (text.length > limit && fieldName != null) {
    truncatedFields?.add(fieldName);
  }
  return text.length <= limit ? text : text.substring(0, limit);
}

Map<String, Object?> _boundedLifecycleBinding(Map<String, Object?> binding) {
  const scalarKeys = <String>[
    'kind',
    'available',
    'bound',
    'videoControllerIdentity',
    'platformControllerIdentity',
    'textureId',
    'platformTextureId',
    'topologyGeneration',
  ];
  final result = <String, Object?>{
    for (final key in scalarKeys)
      if (binding.containsKey(key)) key: binding[key],
  };
  final tuple = binding['surfaceTuple'];
  if (tuple is Map) {
    result['surfaceTuple'] = <String, Object?>{
      for (final key in const <String>[
        'handle',
        'generation',
        'viewId',
        'surfaceGeneration',
        'wid',
      ])
        if (tuple.containsKey(key)) key: tuple[key],
    };
  }
  return result;
}

class _ExpectedLifecycleSurfaceDrift implements Exception {
  const _ExpectedLifecycleSurfaceDrift(this.before, this.after);

  final Map<String, Object?> before;
  final Map<String, Object?> after;

  @override
  String toString() => 'Bound Surface tuple changed during lifecycle';
}

Map<String, Object?> androidNativeDvTextureBindingSnapshotForTesting({
  required VideoController video,
  required AndroidVideoController output,
}) {
  if (!identical(video.player, output.player) ||
      !identical(video.notifier.value, output) ||
      output.configuration.android.usePlatformView) {
    throw StateError('Expected the published Android Texture output');
  }
  final videoId = video.id.value;
  final outputId = output.id.value;
  final videoRect = video.rect.value;
  final outputRect = output.rect.value;
  if (videoId == null ||
      outputId == null ||
      videoId != outputId ||
      videoRect == null ||
      outputRect == null ||
      videoRect != outputRect ||
      videoRect.width <= 0 ||
      videoRect.height <= 0 ||
      output.nativeSurfaceGeneration <= 0) {
    throw StateError('Android Texture binding facts are unavailable');
  }
  Map<String, Object?> rectJson(Rect rect) => <String, Object?>{
        'left': rect.left,
        'top': rect.top,
        'right': rect.right,
        'bottom': rect.bottom,
        'width': rect.width,
        'height': rect.height,
      };
  return <String, Object?>{
    'kind': 'android-texture',
    'videoControllerIdentity': identityHashCode(video),
    'platformControllerIdentity': identityHashCode(output),
    'textureId': videoId,
    'platformTextureId': outputId,
    'rect': rectJson(videoRect),
    'platformRect': rectJson(outputRect),
    'topologyGeneration': output.nativeSurfaceGeneration,
    'topologyGenerationSource':
        'AndroidVideoController.nativeSurfaceGeneration',
    'bindingMeaning': 'matching before/after endpoint snapshots',
    'abaAbsenceProven': false,
    'continuousBindingProven': false,
  };
}

bool androidNativeDvTextureBindingSnapshotsMatch(
  Map<String, Object?> first,
  Map<String, Object?> second,
) {
  const keys = <String>[
    'kind',
    'videoControllerIdentity',
    'platformControllerIdentity',
    'textureId',
    'platformTextureId',
    'topologyGeneration',
  ];
  if (!keys.every((key) => first[key] == second[key])) return false;
  final firstRect = first['rect'];
  final secondRect = second['rect'];
  final firstPlatformRect = first['platformRect'];
  final secondPlatformRect = second['platformRect'];
  return firstRect is Map &&
      secondRect is Map &&
      firstPlatformRect is Map &&
      secondPlatformRect is Map &&
      const <String>['left', 'top', 'right', 'bottom', 'width', 'height'].every(
          (key) =>
              firstRect[key] == secondRect[key] &&
              firstPlatformRect[key] == secondPlatformRect[key]);
}

class AndroidNativeDvFullscreenLifecycleObservations {
  Map<String, Object?>? beforeEntry;
  Map<String, Object?>? afterEntry;
  Map<String, Object?>? afterEntryRecovery;
  Map<String, Object?>? beforeExit;
  Map<String, Object?>? afterExit;

  bool get entryChanged =>
      !androidNativeDvSessionSurfaceTuplesMatch(beforeEntry, afterEntry);

  bool get exitChanged =>
      !androidNativeDvSessionSurfaceTuplesMatch(beforeExit, afterExit);

  void observeEntry({
    required Map<String, Object?>? before,
    required Map<String, Object?>? during,
  }) {
    beforeEntry = before;
    afterEntry = during;
    beforeExit = during;
  }

  void observeEntryRecovery(Map<String, Object?>? current) {
    afterEntryRecovery = current;
    beforeExit = current;
  }

  void observeExit(Map<String, Object?>? after) => afterExit = after;

  Map<String, Object?> toJson() => <String, Object?>{
        'beforeEntry': beforeEntry,
        'afterEntry': afterEntry,
        'afterEntryRecovery': afterEntryRecovery,
        'beforeExit': beforeExit,
        'afterExit': afterExit,
        'entryTupleChanged': entryChanged,
        'exitTupleChanged': exitChanged,
        'abaAbsenceProven': false,
      };
}

bool androidNativeDvSessionSurfaceTuplesMatch(
  Map<String, Object?>? first,
  Map<String, Object?>? second,
) =>
    first != null &&
    second != null &&
    const <String>[
      'handle',
      'generation',
      'viewId',
      'surfaceGeneration',
      'wid',
    ].every((key) => first[key] == second[key]);

/// Shared admission/lifecycle gate for the production sampling segment.
/// A terminal event is latched even when a periodic sample is already active;
/// its accepted row then closes the segment permanently.
class AndroidNativeDvSessionSamplingSegment {
  bool _sampling = false;
  bool _closing = false;
  bool _terminalObserved = false;
  bool _terminalRowAccepted = false;

  bool get terminalObserved => _terminalObserved;
  bool get terminalRowAccepted => _terminalRowAccepted;
  bool get closing => _closing;
  bool get sampling => _sampling;

  void observeTerminal() => _terminalObserved = true;

  Future<void> sample({
    required bool terminal,
    required Future<bool> Function(bool terminalObserved) operation,
  }) async {
    if (terminal) _terminalObserved = true;
    if (_closing || _terminalRowAccepted || _sampling) return;
    _sampling = true;
    try {
      if (await operation(_terminalObserved)) _terminalRowAccepted = true;
    } finally {
      _sampling = false;
    }
  }

  void beginClose() => _closing = true;
}

bool androidNativeDvSessionIdentityMatches({
  required String expectedPath,
  required String actualPath,
  required String expectedEntryId,
  required String actualEntryId,
  required int expectedEpoch,
  required int actualEpoch,
  required bool terminalObserved,
}) =>
    (actualPath == expectedPath || (terminalObserved && actualPath.isEmpty)) &&
    actualEntryId == expectedEntryId &&
    actualEpoch == expectedEpoch;

bool androidNativeDvSessionRouteBindingMatches({
  required int acceptedGeneration,
  required int appliedGeneration,
  required int currentSessionGeneration,
  required bool appliedNativeDv,
  required bool reportedNativeDv,
}) =>
    acceptedGeneration == appliedGeneration &&
    appliedGeneration == currentSessionGeneration &&
    appliedNativeDv &&
    reportedNativeDv;

class AndroidNativeDvSessionReportWriteQueue {
  Future<void> _tail = Future<void>.value();
  bool _closing = false;

  void schedule(Future<void> Function() write) {
    if (_closing) return;
    scheduleMicrotask(() {
      if (_closing) return;
      unawaited(enqueue(write).catchError((Object _) {}));
    });
  }

  Future<void> enqueue(Future<void> Function() write) {
    final next = _tail.then((_) => write());
    _tail = next.catchError((Object _) {});
    return next;
  }

  void closeAdmission() => _closing = true;

  Future<void> flush() => _tail;
}

String? validateAndroidNativeDvSessionDiagnosticAdmission({
  required bool android,
  required bool hdrTransaction,
  required bool rawReleaseDiagnostic,
  required List<String> sources,
  required String identityLabel,
}) {
  if (!android || !hdrTransaction || rawReleaseDiagnostic) {
    return 'Session diagnostic requires Android HDR_TRANSACTION and excludes raw Release diagnostic';
  }
  if (sources.length != 1 ||
      sources.single != androidNativeDvSessionDiagnosticSource ||
      identityLabel.trim().isEmpty) {
    return 'Requires one fixed LG P5 source and an external identity label';
  }
  return null;
}

HdrRoutePrediction planAndroidNativeDvSessionDiagnostic({
  required HdrSourceDescriptor source,
  required HdrCapabilities capabilities,
  required HdrRoutingPolicy policy,
  required HdrOutputPreference preference,
  required Map<String, HdrDegradeReason> excluded,
  void Function(HdrRoutePrediction ordinary)? onOrdinaryPrediction,
}) {
  final ordinary = HdrRoutePlanner.plan(
    source: source,
    capabilities: capabilities,
    policy: policy,
    preference: preference,
    excluded: excluded,
  );
  onOrdinaryPrediction?.call(ordinary);
  if (preference != HdrOutputPreference.auto ||
      source.kind != HdrMediaKind.dolbyVisionP5 ||
      source.codec != 'hevc' ||
      source.dvProfile != 5 ||
      source.dvCompatibilityId != 0 ||
      source.enhancementLayer != false ||
      !policy
          .preferencesFor(HdrSourceClass.dvP5)
          .contains(HdrStrategy.nativeDolbyVision) ||
      excluded.containsKey(HdrRouteDependency.nativeDolbyVision) ||
      excluded.containsKey(HdrRouteDependency.hwdecMediacodec) ||
      excluded.containsKey(HdrRouteDependency.topologyPlatformView)) {
    return ordinary;
  }
  final realized = HdrStrategyRealizer.realize(
    HdrStrategy.nativeDolbyVision,
    source: source,
    sourceClass: HdrSourceClass.dvP5,
    capabilities: capabilities,
  );
  final route = realized.route;
  if (route == null) return ordinary;

  final candidates = <HdrCandidate>[
    HdrCandidate(
      strategy: HdrStrategy.nativeDolbyVision,
      // Reflect the current maturity table: the diagnostic bypass forces the
      // reserved strategy through, but the reported maturity tracks the
      // table (unsupported → experimental since the 2026-10-06 LG DV
      // unlock → verified since the 2026-10-10 user-adjudicated direct-path
      // default promotion).
      maturity: HdrStrategyMaturityTable.of(
          HdrSourceClass.dvP5, HdrStrategy.nativeDolbyVision),
      feasible: true,
      route: route,
    ),
    ...ordinary.candidates.where(
      (candidate) => candidate.strategy != HdrStrategy.nativeDolbyVision,
    ),
  ];
  final selected = candidates.first;
  final confidence = route.surfaceTransfer == null ||
          (capabilities.dataSpaceExt?.applicable ?? false)
      ? HdrPredictionConfidence.verified
      : HdrPredictionConfidence.unverified;
  return HdrRoutePrediction(
    source: source,
    selected: selected,
    candidates: List<HdrCandidate>.unmodifiable(candidates),
    presentation: route.presentation,
    confidence: confidence,
    playable: true,
  );
}

int validateAndroidNativeDvSessionDiagnosticSeconds(int value) {
  if (value < 1 || value > androidNativeDvSessionDiagnosticMaxRows) {
    throw RangeError.range(value, 1, androidNativeDvSessionDiagnosticMaxRows);
  }
  return value;
}

int validateAndroidNativeDvSessionDiagnosticInterval(int value) {
  if (value < 1 || value > 30) throw RangeError.range(value, 1, 30);
  return value;
}

/// Same-Player Session replacement is admitted only after both the
/// framework report and the post-dispose observations match the captured
/// idle baseline without lifecycle debt.
bool androidNativeDvSessionReuseAdmitted({
  required bool disposeReportClean,
  required bool actualRestorationVerified,
  required bool lifecycleDebt,
}) =>
    disposeReportClean && actualRestorationVerified && !lifecycleDebt;

class AndroidNativeDvSessionDiagnostic {
  AndroidNativeDvSessionDiagnostic({
    required this.player,
    required int durationSeconds,
    required int intervalSeconds,
    required this.externalIdentityLabel,
    this.lifecycleRun,
  })  : durationSeconds = lifecycleRun == null
            ? validateAndroidNativeDvSessionDiagnosticSeconds(durationSeconds)
            : lifecycleRun.durationSeconds,
        intervalSeconds =
            validateAndroidNativeDvSessionDiagnosticInterval(intervalSeconds);

  final Player player;
  final int durationSeconds;
  final int intervalSeconds;
  final String externalIdentityLabel;
  final AndroidNativeDvSessionLifecycleRun? lifecycleRun;
  final String runId = '${DateTime.now().toUtc().microsecondsSinceEpoch}-'
      '${identityHashCode(Object())}';
  final String startUtc = DateTime.now().toUtc().toIso8601String();
  final ValueNotifier<String> status = ValueNotifier<String>('waiting');
  final List<Map<String, Object?>> _rows = <Map<String, Object?>>[];
  final Stopwatch _clock = Stopwatch();
  final Lock _sampleLock = Lock();
  Directory? _directory;
  File? _file;
  StreamSubscription<HdrOutputEvent>? _events;
  StreamSubscription<bool>? _completed;
  HdrVideoSession? _session;
  Timer? _timer;
  HdrNativeDvReviewEvidence? _accepted;
  Map<String, Object?>? _acceptedJson;
  Map<String, Object?>? _appliedJson;
  HdrRoutePrediction? _ordinaryPrediction;
  int? _appliedGeneration;
  String _phase = 'waiting';
  String? _error;
  String _cleanup = 'pending';
  Map<String, Object?>? _cleanupEvidence;
  bool _closed = false;
  bool _closing = false;
  bool _sampleFailed = false;
  Map<String, String>? _initialIdleProperties;
  int? _initialIdleEpoch;
  bool _lastCleanupVerified = false;
  Future<String>? _pendingPropertyRead;
  AndroidNativeDvSessionSamplingSegment _segment =
      AndroidNativeDvSessionSamplingSegment();
  String _sessionInstanceId = 'session-1';
  String _expectedSourcePath = androidNativeDvSessionDiagnosticSource;
  String? _expectedOpenActionId;
  String? _expectedOpenRequestId;
  final Map<String, Map<int, HdrNativeDvReviewEvidence>> _proofsBySession =
      <String, Map<int, HdrNativeDvReviewEvidence>>{};
  final Map<String, Map<int, Map<String, Object?>>> _proofJsonBySession =
      <String, Map<int, Map<String, Object?>>>{};
  final Map<String, AndroidNativeDvSessionAppliedAdmission> _appliedAdmissions =
      <String, AndroidNativeDvSessionAppliedAdmission>{};
  final Map<String, Completer<void>> _rowProgressWaiters =
      <String, Completer<void>>{};
  Map<String, Object?>? _activeLifecycleSegment;
  int _lifecycleSegmentSequence = 0;
  final AndroidNativeDvSessionReportWriteQueue _writes =
      AndroidNativeDvSessionReportWriteQueue();
  Future<void>? _sampleFuture;

  HdrRoutePrediction routePlanner({
    required HdrSourceDescriptor source,
    required HdrCapabilities capabilities,
    required HdrRoutingPolicy policy,
    required HdrOutputPreference preference,
    required Map<String, HdrDegradeReason> excluded,
  }) {
    return planAndroidNativeDvSessionDiagnostic(
      source: source,
      capabilities: capabilities,
      policy: policy,
      preference: preference,
      excluded: excluded,
      onOrdinaryPrediction: (prediction) => _ordinaryPrediction = prediction,
    );
  }

  Future<void> prepare() async {
    if (_closed) throw StateError('Session diagnostic was closed');
    final lifecycle = lifecycleRun;
    if (lifecycle != null) {
      await lifecycle.prepare();
      try {
        final baseline = await _captureIdleBaseline();
        _initialIdleProperties = baseline.properties;
        _initialIdleEpoch = baseline.epoch;
        lifecycle.recordInitialIdleBaseline(
          properties: baseline.properties,
          fileLoadedEpoch: baseline.epoch,
        );
      } catch (error) {
        lifecycle.markDebt('initial idle baseline failed: $error');
        rethrow;
      }
      _clock.start();
      _phase = 'prepared';
      await _write();
      return;
    }
    final root = await path_provider.getExternalStorageDirectory();
    if (root == null) {
      throw StateError('App external files directory unavailable');
    }
    _directory = Directory('${root.path}/media-kit-hdr-diagnostic');
    await _directory!.create(recursive: true);
    _file = File('${_directory!.path}/native-dv-session-diagnostic.json');
    _phase = 'prepared';
    await _write();
  }

  Future<({Map<String, String> properties, int epoch})>
      _captureIdleBaseline() async {
    return player.lock.synchronized(() async {
      final beforeEpoch = player.fileLoadedEpoch;
      final properties = await _captureLifecyclePropertiesLocked();
      final afterEpoch = player.fileLoadedEpoch;
      final codec = AndroidMediaCodecConfiguration.parse(
          properties['android-mediacodec-info']);
      if (properties['path']!.isNotEmpty ||
          player.state.playing ||
          beforeEpoch != afterEpoch ||
          (codec?.nativeDvActive ?? false) ||
          properties['vd-lavc-o']!.contains('native_dv=1')) {
        throw StateError(
            'The real Player is not idle before Session admission');
      }
      return (properties: properties, epoch: afterEpoch);
    });
  }

  Future<Map<String, String>> _captureLifecyclePropertiesLocked() async {
    final values = <String, String>{};
    for (final name in const <String>[
      'path',
      'playlist/0/id',
      'vd-lavc-o',
      'mediacodec-embed-render-mode',
      'android-mediacodec-info',
      'hwdec',
      'hwdec-current',
      'vo',
      'android-native-dv-bridge-api',
    ]) {
      values[name] =
          await player.getProperty(name, waitForInitialization: false);
    }
    return Map<String, String>.unmodifiable(values);
  }

  @visibleForTesting
  bool get cleanupVerifiedForTesting => _lastCleanupVerified;

  @visibleForTesting
  void setInitialIdleBaselineForTesting({
    required Map<String, String> properties,
    required int fileLoadedEpoch,
  }) {
    _initialIdleProperties = Map<String, String>.unmodifiable(properties);
    _initialIdleEpoch = fileLoadedEpoch;
  }

  @visibleForTesting
  void bindLifecycleSegmentForTesting({
    required HdrVideoSession session,
    required String sessionInstanceId,
    required Map<String, Object?> segment,
  }) {
    if (lifecycleRun == null) {
      throw StateError('A lifecycle run is required for this test seam');
    }
    _session = session;
    _sessionInstanceId = sessionInstanceId;
    _expectedSourcePath = segment['expectedSource']! as String;
    _activeLifecycleSegment = segment;
    if (!_clock.isRunning) _clock.start();
  }

  @visibleForTesting
  Future<bool> sampleLifecycleSegmentForTesting() {
    final segment = _activeLifecycleSegment;
    if (segment == null) return Future<bool>.value(false);
    return _sampleLifecycleLocked(segment);
  }

  Future<void> attach(
    HdrVideoSession session, {
    String sessionInstanceId = 'session-1',
  }) async {
    if (_closed || _closing) return;
    await _events?.cancel();
    await _completed?.cancel();
    _session = session;
    _sessionInstanceId = sessionInstanceId;
    _events = session.events.listen((event) {
      if (_closed || _closing) return;
      if (event is HdrRouteAppliedEvent) {
        if (lifecycleRun != null) {
          unawaited(_recordLifecycleRouteApplied(
            session: session,
            sessionInstanceId: sessionInstanceId,
            event: event,
          ).catchError((Object error, StackTrace stack) {
            lifecycleRun!
                .markDebt('routeApplied segment admission failed: $error');
            _appliedAdmissions
                .remove('$sessionInstanceId:${event.generation}')
                ?.fail(error, stack);
          }));
        } else if (_accepted != null &&
            androidNativeDvSessionRouteBindingMatches(
              acceptedGeneration: _acceptedGeneration!,
              appliedGeneration: event.generation,
              currentSessionGeneration: session.report.value.generation,
              appliedNativeDv:
                  event.route.strategy == HdrStrategy.nativeDolbyVision,
              reportedNativeDv: event.report.actual?.strategy ==
                  HdrStrategy.nativeDolbyVision,
            )) {
          _appliedGeneration = event.generation;
          _appliedJson = <String, Object?>{
            'generation': event.generation,
            'route': event.route.strategy.name,
            'report': event.report.toString(),
            'atElapsedMs': _clock.elapsedMilliseconds,
          };
          _phase = 'routeApplied';
          _clock.start();
          _timer ??= Timer.periodic(
            Duration(seconds: intervalSeconds),
            (_) => unawaited(_sample()),
          );
          _queueWrite();
        }
      }
    });
    _completed = player.stream.completed.listen((done) {
      if (done) unawaited(_sample(terminal: true));
    });
  }

  void expectLifecycleSource({
    required String sessionInstanceId,
    required String sourcePath,
    required String actionId,
    required String requestId,
  }) {
    if (lifecycleRun == null) {
      throw StateError('Lifecycle source switch requires lifecycle mode');
    }
    if (sessionInstanceId != _sessionInstanceId ||
        (sourcePath != androidNativeDvSessionLifecycleP5Path &&
            sourcePath != androidNativeDvSessionLifecycleSdrPath)) {
      throw StateError('Unapproved Session source or instance');
    }
    _expectedSourcePath = sourcePath;
    _expectedOpenActionId = actionId;
    _expectedOpenRequestId = requestId;
  }

  Future<void> quiesceLifecycleSegment(String reason) async {
    if (lifecycleRun == null) {
      throw StateError('Lifecycle segment quiesce requires lifecycle mode');
    }
    _timer?.cancel();
    _timer = null;
    lifecycleRun!.closeSegment(reason);
    _activeLifecycleSegment = null;
    _segment.beginClose();
    final sample = _sampleFuture;
    if (sample != null) {
      try {
        await sample;
      } catch (_) {}
    }
    // A timed-out property operation cannot be cancelled. Do not permit the
    // next source/segment to adopt its late completion.
    await _settlePropertyRead();
  }

  Future<Map<String, Object?>?> captureCurrentSurfaceTuple() async {
    final session = _session;
    if (session == null) return null;
    final video = session.controller.value;
    if (video == null || !video.platform.isCompleted) return null;
    final platform = await video.platform.future;
    if (platform is! AndroidVideoController) return null;
    final identity = platform.currentBoundOutputIdentity;
    if (identity == null) return null;
    return <String, Object?>{
      'handle': identity.handle,
      'generation': identity.generation,
      'viewId': identity.viewId,
      'surfaceGeneration': identity.surfaceGeneration,
      'wid': identity.wid,
    };
  }

  Future<Map<String, Object?>> waitForLifecycleApplied({
    required String sessionInstanceId,
    required int generation,
  }) async {
    final run = lifecycleRun;
    if (run == null) throw StateError('Lifecycle mode is not active');
    final key = '$sessionInstanceId:$generation';
    if (run.debt || run.terminal || run.closed) {
      throw StateError('Lifecycle run is terminal or has cleanup debt');
    }
    if (run.remaining <= Duration.zero) {
      throw TimeoutException('Lifecycle run deadline reached awaiting Applied');
    }
    final active = _activeLifecycleSegment;
    if (active != null &&
        active['sessionInstanceId'] == sessionInstanceId &&
        active['generation'] == generation) {
      final record = active['record'] as Map<String, Object?>;
      if ((record['rowCount'] as int? ?? 0) > 0 && record['accepted'] == true) {
        return Map<String, Object?>.from(record['routeApplied'] as Map);
      }
    }
    final admission = _appliedAdmissions.putIfAbsent(
      key,
      () => AndroidNativeDvSessionAppliedAdmission(
        sessionInstanceId: sessionInstanceId,
        generation: generation,
      ),
    );
    final applied = await admission.wait(
      remaining: run.remaining < const Duration(seconds: 60)
          ? run.remaining
          : const Duration(seconds: 60),
      stillAdmissible: () =>
          !run.debt &&
          !run.terminal &&
          !run.closed &&
          run.remaining > Duration.zero,
    );
    final accepted = _activeLifecycleSegment;
    if (accepted == null ||
        accepted['sessionInstanceId'] != sessionInstanceId ||
        accepted['generation'] != generation ||
        ((accepted['record'] as Map)['rowCount'] as int? ?? 0) == 0) {
      throw StateError('Applied has no accepted identity-bound sample row');
    }
    return applied;
  }

  Future<int> waitForLifecycleRows({
    required String sessionInstanceId,
    required int generation,
    required int minimumRows,
  }) async {
    if (minimumRows < 1 ||
        minimumRows > androidNativeDvSessionLifecycleMaxRows) {
      throw RangeError.range(
          minimumRows, 1, androidNativeDvSessionLifecycleMaxRows);
    }
    final run = lifecycleRun;
    if (run == null) throw StateError('Lifecycle mode is not active');
    final key = '$sessionInstanceId:$generation';
    while (true) {
      if (run.debt ||
          run.terminal ||
          run.closed ||
          run.remaining <= Duration.zero) {
        throw StateError('Lifecycle row admission expired or became debt');
      }
      final active = _activeLifecycleSegment;
      if (active == null ||
          active['sessionInstanceId'] != sessionInstanceId ||
          active['generation'] != generation ||
          sessionInstanceId != _sessionInstanceId ||
          _session?.report.value.generation != generation) {
        throw StateError('Lifecycle segment changed while waiting for rows');
      }
      final record = active['record'] as Map<String, Object?>;
      final count = record['rowCount'] as int? ?? 0;
      if (count >= minimumRows) return count;
      if (record['phase'] == 'terminal' || record['endedElapsedMs'] != null) {
        throw StateError('Segment ended with only $count rows');
      }
      final waiter = _rowProgressWaiters.putIfAbsent(
        key,
        Completer<void>.new,
      );
      await waiter.future.timeout(run.remaining);
    }
  }

  Future<void> _recordLifecycleRouteApplied({
    required HdrVideoSession session,
    required String sessionInstanceId,
    required HdrRouteAppliedEvent event,
  }) async {
    final run = lifecycleRun!;
    if (run.closed ||
        run.debt ||
        run.terminal ||
        run.remaining <= Duration.zero) {
      if (!run.closed) {
        run.markDebt('RouteApplied arrived outside run admission');
      }
      return;
    }
    if (!identical(session, _session) ||
        sessionInstanceId != _sessionInstanceId) {
      return;
    }
    final report = session.report.value;
    if (report.generation != event.generation ||
        event.report.actual?.strategy != event.route.strategy) {
      return;
    }
    final applied = <String, Object?>{
      'sessionInstanceId': sessionInstanceId,
      'generation': event.generation,
      'route': event.route.strategy.name,
      'reportSourceOrigin': event.report.sourceOrigin?.name,
      'report': event.report.toString(),
      'expectedSource': _expectedSourcePath,
      'actionId': _expectedOpenActionId ?? run.currentActionId,
      'requestId': _expectedOpenRequestId ?? run.currentRequestId,
      'elapsedMs': run.elapsed.inMilliseconds,
    };
    run.recordRouteApplied(applied);
    final proof = _proofsBySession[sessionInstanceId]?[event.generation];
    final proofJson = _proofJsonBySession[sessionInstanceId]?[event.generation];
    final native = event.route.strategy == HdrStrategy.nativeDolbyVision;
    final otherProofs = _proofsBySession[sessionInstanceId];
    if (otherProofs != null) {
      for (final pendingGeneration in otherProofs.keys) {
        if (pendingGeneration != event.generation) {
          run.updateConsumerProofStatus(
            sessionInstanceId: sessionInstanceId,
            generation: pendingGeneration,
            status: 'abandoned',
            reason: 'different generation routeApplied',
          );
        }
      }
    }
    if (proof != null) {
      run.updateConsumerProofStatus(
        sessionInstanceId: sessionInstanceId,
        generation: event.generation,
        status: 'applied',
      );
    }
    if (native && (proof == null || proofJson == null)) {
      run.closeSegment('native-applied-without-matching-consumer-proof',
          abandoned: true);
      _activeLifecycleSegment = null;
      _timer?.cancel();
      _phase = 'applied-proof-missing';
      run.markDebt('Native routeApplied has no same-instance/generation proof');
      return;
    }
    if (native &&
        (proof!.source.path != _expectedSourcePath ||
            proof.source.path != androidNativeDvSessionLifecycleP5Path)) {
      run.closeSegment('foreign-native-proof', abandoned: true);
      _activeLifecycleSegment = null;
      _timer?.cancel();
      run.markDebt('Native proof source differs from the expected fixed P5');
      return;
    }
    if (!native &&
        _expectedSourcePath != androidNativeDvSessionLifecycleSdrPath) {
      run.closeSegment('unexpected-nonnative-route', abandoned: true);
      _activeLifecycleSegment = null;
      _timer?.cancel();
      run.markDebt('Expected native P5 route did not apply');
      return;
    }
    run.closeSegment('next-route-applied');
    _activeLifecycleSegment = null;
    _segment.beginClose();
    _timer?.cancel();
    _timer = null;
    final oldSample = _sampleFuture;
    if (oldSample != null) {
      try {
        await oldSample;
      } catch (_) {}
    }
    await _settlePropertyRead();
    if (_closed ||
        _closing ||
        run.closed ||
        run.debt ||
        run.remaining <= Duration.zero ||
        !identical(session, _session) ||
        sessionInstanceId != _sessionInstanceId ||
        session.report.value.generation != event.generation) {
      return;
    }
    _segment = AndroidNativeDvSessionSamplingSegment();
    final actionId =
        _expectedOpenActionId ?? run.currentActionId ?? 'initial-open';
    final requestId =
        _expectedOpenRequestId ?? run.currentRequestId ?? 'startup';
    final segmentId =
        '$sessionInstanceId-g${event.generation}-s${++_lifecycleSegmentSequence}';
    final record = run.beginSegment(
      segmentId: segmentId,
      sessionInstanceId: sessionInstanceId,
      generation: event.generation,
      expectedSource: _expectedSourcePath,
      route: event.route.strategy.name,
      actionId: actionId,
      requestId: requestId,
      consumerValidated: proofJson,
      routeApplied: applied,
    );
    _activeLifecycleSegment = <String, Object?>{
      'record': record,
      'segmentId': segmentId,
      'sessionInstanceId': sessionInstanceId,
      'generation': event.generation,
      'expectedSource': _expectedSourcePath,
      'route': event.route.strategy,
      'appliedTypedRoute': event.route,
      'proof': proof,
      'proofJson': proofJson,
      'entryId': proof?.source.playlistEntryId,
      'epoch': proof?.source.fileLoadedEpoch,
      'surface': proof?.output,
      'identity': null,
    };
    _appliedGeneration = event.generation;
    _appliedJson = applied;
    _phase = 'routeApplied';
    _clock.start();
    _timer = Timer.periodic(
      Duration(seconds: intervalSeconds),
      (_) => unawaited(_sample()),
    );
    unawaited(_sample());
    _queueWrite();
  }

  int? get _acceptedGeneration => _acceptedJson?['generation'] is int
      ? _acceptedJson!['generation'] as int
      : null;

  void onNativeDvConsumerValidated(
    int generation,
    HdrOpenPlan plan,
    HdrReviewFacts facts, {
    String? sessionInstanceId,
  }) {
    final lifecycle = lifecycleRun;
    final instanceId = sessionInstanceId ?? _sessionInstanceId;
    if (lifecycle != null && instanceId != _sessionInstanceId) return;
    final evidence = facts.nativeDvEvidence;
    if (_closed || _closing || evidence == null) return;
    if (lifecycle != null &&
        (lifecycle.closed ||
            lifecycle.debt ||
            lifecycle.terminal ||
            lifecycle.remaining <= Duration.zero)) {
      lifecycle.markDebt('Consumer evidence arrived outside run admission');
      return;
    }
    final sourceEntry = int.tryParse(evidence.source.playlistEntryId);
    if (!identical(evidence.source.player, player) ||
        evidence.source.path != androidNativeDvSessionDiagnosticSource ||
        evidence.loaded.epoch != evidence.source.fileLoadedEpoch ||
        sourceEntry != evidence.loaded.playlistEntryId ||
        plan.route.strategy != HdrStrategy.nativeDolbyVision ||
        facts.path != androidNativeDvSessionDiagnosticSource ||
        facts.codec != 'hevc' ||
        facts.dolbyVisionProfile != 5 ||
        facts.dvCompatibilityId != 0 ||
        facts.dvElPresent != false) {
      _sampleFailed = true;
      _error = 'Consumer proof does not match the fixed native-DV P5 source';
      _phase = 'consumerProofRejected';
      lifecycle?.markDebt(_error!);
      _queueWrite();
      return;
    }
    _accepted = HdrNativeDvReviewEvidence(
      source: HdrOptionSourceIdentity(
        player: evidence.source.player,
        path: evidence.source.path,
        playlistEntryId: evidence.source.playlistEntryId,
        fileLoadedEpoch: evidence.source.fileLoadedEpoch,
      ),
      loaded: FileLoadedRecord(
        evidence.loaded.epoch,
        evidence.loaded.playlistEntryId,
      ),
      controller: evidence.controller,
      output: evidence.output,
      configuration: evidence.configuration,
      hwdecCurrent: evidence.hwdecCurrent,
    );
    final accepted = _accepted!;
    _acceptedJson = _evidenceJson(generation, plan, facts, accepted);
    if (lifecycle != null) {
      for (final previousGeneration
          in _proofsBySession[instanceId]?.keys ?? const <int>[]) {
        lifecycle.updateConsumerProofStatus(
          sessionInstanceId: instanceId,
          generation: previousGeneration,
          status: 'abandoned',
          reason: 'superseded by newer consumer proof',
        );
      }
      final evidenceJson = <String, Object?>{
        ..._acceptedJson!,
        'sessionInstanceId': instanceId,
        'status': 'pending',
        'actionId': _expectedOpenActionId ?? lifecycle.currentActionId,
        'requestId': _expectedOpenRequestId ?? lifecycle.currentRequestId,
        'elapsedMs': lifecycle.elapsed.inMilliseconds,
      };
      _acceptedJson = evidenceJson;
      (_proofsBySession[instanceId] ??=
          <int, HdrNativeDvReviewEvidence>{})[generation] = accepted;
      (_proofJsonBySession[instanceId] ??=
          <int, Map<String, Object?>>{})[generation] = evidenceJson;
      lifecycle.recordConsumerProof(evidenceJson);
    }
    _phase = 'consumerValidated';
    _queueWrite();
  }

  void onNativeDvConsumerCaptureError(
    Object error,
    StackTrace stack, {
    String? sessionInstanceId,
  }) {
    if (_closed || _closing) return;
    _error = 'consumer evidence capture: $error\n$stack';
    _phase = 'captureError';
    lifecycleRun?.markDebt(_error!);
    _queueWrite();
  }

  Map<String, Object?> _evidenceJson(int generation, HdrOpenPlan plan,
          HdrReviewFacts facts, HdrNativeDvReviewEvidence evidence) =>
      <String, Object?>{
        'generation': generation,
        'source': {
          'path': evidence.source.path,
          'playlistEntryId': evidence.source.playlistEntryId,
          'fileLoadedEpoch': evidence.source.fileLoadedEpoch,
          'playerIdentity': identityHashCode(evidence.source.player),
        },
        'fileLoaded': {
          'epoch': evidence.loaded.epoch,
          'playlistEntryId': evidence.loaded.playlistEntryId,
        },
        'controllerIdentity': identityHashCode(evidence.controller),
        'surface': evidence.output.asChannelArguments(),
        'surfaceTuple': {
          'handle': evidence.output.handle,
          'generation': evidence.output.generation,
          'viewId': evidence.output.viewId,
          'surfaceGeneration': evidence.output.surfaceGeneration,
          'wid': evidence.output.wid,
        },
        'codecConfiguration': {
          'mime': evidence.configuration.mime,
          'codec': evidence.configuration.codec,
          'nativeDvActive': evidence.configuration.nativeDvActive,
        },
        'hwdecCurrent': evidence.hwdecCurrent,
        'trackFacts': {
          'path': facts.path,
          'codec': facts.codec,
          'profile': facts.dolbyVisionProfile,
          'compatibilityId': facts.dvCompatibilityId,
          'enhancementLayerPresent': facts.dvElPresent,
        },
        'plannedRoute': plan.route.strategy.name,
        'presentationVerified': false,
      };

  Future<void> _sample({bool terminal = false}) async {
    if (terminal) _segment.observeTerminal();
    if (_segment.sampling) return;
    if (lifecycleRun != null) {
      await _sampleLifecycle(terminal: terminal);
      return;
    }
    final proof = _accepted;
    final generation = _appliedGeneration;
    if (_closed ||
        _closing ||
        _sampleFailed ||
        _segment.terminalRowAccepted ||
        proof == null ||
        generation == null ||
        generation != _acceptedGeneration ||
        _rows.length >= androidNativeDvSessionDiagnosticMaxRows ||
        _clock.elapsed >= Duration(seconds: durationSeconds)) {
      if (_clock.elapsed >= Duration(seconds: durationSeconds)) {
        _timer?.cancel();
        _phase = 'deadline';
        await _enqueueWrite();
      }
      return;
    }
    final future = _sampleFuture = _segment.sample(
      terminal: terminal,
      operation: (terminalObserved) =>
          _sampleLocked(proof, generation, terminalObserved),
    );
    try {
      await future;
    } finally {
      if (identical(_sampleFuture, future)) _sampleFuture = null;
    }
    if (!_closed &&
        !_sampleFailed &&
        player.state.completed &&
        !_segment.terminalRowAccepted) {
      scheduleMicrotask(() => unawaited(_sample(terminal: true)));
    }
  }

  Future<void> _sampleLifecycle({bool terminal = false}) async {
    final run = lifecycleRun!;
    final segment = _activeLifecycleSegment;
    if (_closed ||
        _closing ||
        _sampleFailed ||
        _segment.terminalRowAccepted ||
        segment == null ||
        run.closed ||
        run.terminal ||
        run.debt ||
        run.rows.length >= androidNativeDvSessionLifecycleMaxRows ||
        run.remaining <= Duration.zero) {
      if (run.remaining <= Duration.zero ||
          run.rows.length >= androidNativeDvSessionLifecycleMaxRows) {
        _timer?.cancel();
        _activeLifecycleSegment = null;
        _segment.beginClose();
        run.markTerminal(
          reason: run.remaining <= Duration.zero ? 'run-deadline' : 'row-limit',
        );
        run.scheduleWrite();
      }
      return;
    }
    final future = _sampleFuture = _segment.sample(
      terminal: terminal,
      operation: (_) => _sampleLifecycleLocked(segment),
    );
    try {
      await future;
    } finally {
      if (identical(_sampleFuture, future)) _sampleFuture = null;
    }
  }

  Future<bool> _sampleLifecycleLocked(Map<String, Object?> segment) async {
    final run = lifecycleRun!;
    final session = _session;
    try {
      final acceptedEos = await _sampleLock.synchronized(
        () => player.lock.synchronized(() async {
          if (_closed ||
              _closing ||
              run.closed ||
              run.debt ||
              run.remaining <= Duration.zero ||
              !identical(segment, _activeLifecycleSegment)) {
            return false;
          }
          if (session == null ||
              segment['sessionInstanceId'] != _sessionInstanceId ||
              !identical(session, _session)) {
            throw StateError('Session instance changed before sample read');
          }
          final generation = segment['generation'] as int;
          final expectedSource = segment['expectedSource'] as String;
          final route = segment['route'] as HdrStrategy;
          final proof = segment['proof'] as HdrNativeDvReviewEvidence?;
          final beforeEpoch = player.fileLoadedEpoch;
          final before = await _readTuple(segmentToken: segment);
          final currentBefore = session.report.value;
          if (currentBefore.generation != generation ||
              currentBefore.actual?.strategy != route ||
              beforeEpoch != player.fileLoadedEpoch ||
              !androidNativeDvSessionIdentityMatches(
                expectedPath: expectedSource,
                actualPath: before['path']!,
                expectedEntryId: proof?.source.playlistEntryId ??
                    (segment['entryId'] as String? ?? before['playlist/0/id']!),
                actualEntryId: before['playlist/0/id']!,
                expectedEpoch: proof?.source.fileLoadedEpoch ??
                    (segment['epoch'] as int? ?? beforeEpoch),
                actualEpoch: player.fileLoadedEpoch,
                terminalObserved:
                    _segment.terminalObserved || player.state.completed,
              )) {
            throw StateError(
                'Source/entry/epoch/route changed at sample start');
          }
          final bindingBefore = await _currentLifecycleOutputBinding(
            nativePlatformView: proof != null,
          );
          final outputBefore = bindingBefore['json'] as Map<String, Object?>;
          final boundBefore =
              bindingBefore['nativeOwner'] as AndroidSurfaceAccountId?;
          if (proof != null) {
            if (bindingBefore['available'] != true ||
                !identical(bindingBefore['platform'], proof.controller) ||
                boundBefore != proof.output) {
              throw _ExpectedLifecycleSurfaceDrift(
                  proof.output.asChannelArguments(), outputBefore);
            }
          } else if (expectedSource == androidNativeDvSessionLifecycleSdrPath) {
            final firstBinding =
                segment['outputBinding'] as Map<String, Object?>?;
            if (bindingBefore['available'] != true ||
                (firstBinding != null &&
                    !androidNativeDvTextureBindingSnapshotsMatch(
                        firstBinding, outputBefore))) {
              throw _ExpectedLifecycleSurfaceDrift(
                firstBinding ?? <String, Object?>{'kind': 'android-texture'},
                outputBefore,
              );
            }
          } else {
            throw StateError('Non-native P5 route has no accepted proof');
          }
          final config = <String, String>{};
          for (final property in const <String>[
            'android-mediacodec-info',
            'hwdec-current',
            'vo',
            'hwdec',
            'vd-lavc-o',
            'mediacodec-embed-render-mode',
            'time-pos',
            'duration',
            'pause',
            'frame-drop-count',
            'decoder-frame-drop-count',
            'mistimed-frame-count',
            'vo-delayed-frame-count',
          ]) {
            config[property] =
                await _readProperty(property, segmentToken: segment);
          }
          for (final property in const <String>[
            'android-mediacodec-info',
            'hwdec-current',
            'hwdec',
            'vo',
            'vd-lavc-o',
            'mediacodec-embed-render-mode',
          ]) {
            if (await _readProperty(property, segmentToken: segment) !=
                config[property]) {
              throw StateError(
                  'Configuration changed during segment: $property');
            }
          }
          final after = await _readTuple(segmentToken: segment);
          final afterEpoch = player.fileLoadedEpoch;
          final bindingAfter = await _currentLifecycleOutputBinding(
            nativePlatformView: proof != null,
          );
          final outputAfter = bindingAfter['json'] as Map<String, Object?>;
          final activeControllerAfter =
              bindingAfter['platform'] as AndroidVideoController?;
          final boundAfter =
              bindingAfter['nativeOwner'] as AndroidSurfaceAccountId?;
          final currentAfter = session.report.value;
          final terminalObserved = _segment.terminalObserved ||
              player.state.completed ||
              (double.tryParse(config['time-pos'] ?? '') != null &&
                  double.tryParse(config['duration'] ?? '') != null &&
                  double.parse(config['time-pos']!) >=
                      double.parse(config['duration']!));
          final afterEntry = proof?.source.playlistEntryId ??
              (segment['entryId'] as String? ?? before['playlist/0/id']!);
          final afterExpectedEpoch = proof?.source.fileLoadedEpoch ??
              (segment['epoch'] as int? ?? beforeEpoch);
          if (currentAfter.generation != generation ||
              currentAfter.actual?.strategy != route ||
              before['playlist/0/id'] != after['playlist/0/id'] ||
              !androidNativeDvSessionIdentityMatches(
                expectedPath: expectedSource,
                actualPath: after['path']!,
                expectedEntryId: afterEntry,
                actualEntryId: after['playlist/0/id']!,
                expectedEpoch: afterExpectedEpoch,
                actualEpoch: afterEpoch,
                terminalObserved: terminalObserved,
              ) ||
              afterEpoch != beforeEpoch) {
            throw StateError('Source/entry/epoch/route drift; segment ended');
          }
          if (proof != null) {
            if (bindingAfter['available'] != true ||
                !identical(activeControllerAfter, bindingBefore['platform']) ||
                boundAfter != boundBefore ||
                boundAfter != proof.output) {
              throw _ExpectedLifecycleSurfaceDrift(outputBefore, outputAfter);
            }
          } else if (bindingAfter['available'] != true ||
              !identical(bindingAfter['video'], bindingBefore['video']) ||
              !identical(bindingAfter['platform'], bindingBefore['platform']) ||
              !androidNativeDvTextureBindingSnapshotsMatch(
                  outputBefore, outputAfter) ||
              ((segment['outputBinding'] as Map<String, Object?>?) != null &&
                  !androidNativeDvTextureBindingSnapshotsMatch(
                    segment['outputBinding'] as Map<String, Object?>,
                    outputAfter,
                  ))) {
            throw _ExpectedLifecycleSurfaceDrift(outputBefore, outputAfter);
          }
          final codec = AndroidMediaCodecConfiguration.parse(
              config['android-mediacodec-info']);
          if (proof != null) {
            if (codec == null ||
                !codec.nativeDvActive ||
                codec.mime != proof.configuration.mime ||
                codec.codec != proof.configuration.codec ||
                config['hwdec-current'] != proof.hwdecCurrent ||
                config['hwdec'] != 'mediacodec' ||
                config['vo'] != 'mediacodec_embed' ||
                config['vd-lavc-o']?.contains('native_dv=1') != true ||
                config['mediacodec-embed-render-mode'] != 'timed') {
              throw StateError(
                  'Native segment configuration differs from accepted proof');
            }
          } else if (expectedSource == androidNativeDvSessionLifecycleSdrPath) {
            final baseline = _initialIdleProperties;
            final appliedTypedRoute = segment['appliedTypedRoute'] as HdrRoute?;
            final actualTypedRoute = currentAfter.actual;
            final failedConditions = <String, bool>{
              'appliedTypedRouteMissing': appliedTypedRoute == null,
              'appliedTypedRouteDiffersFromCurrent':
                  appliedTypedRoute == null ||
                      actualTypedRoute != appliedTypedRoute,
              'typedRouteDoesNotMatchFixedSdrTextureContract':
                  appliedTypedRoute != _lgApi24SdrTextureRoute ||
                      actualTypedRoute != _lgApi24SdrTextureRoute,
              'segmentRouteIsNotSdrDirect': route != HdrStrategy.sdrDirect,
              'codecConfigurationMissing': codec == null,
              'mimeIsNotAvc': codec?.mime != 'video/avc',
              'codecNameMissing': codec == null || codec.codec.trim().isEmpty,
              'nativeDvActive': codec?.nativeDvActive != false,
              'nativeDvOptionEnabled':
                  config['vd-lavc-o']?.contains('native_dv=1') == true,
              'idleBaselineMissing': baseline == null,
              'vdLavcOptionDiffersFromIdle': baseline != null &&
                  config['vd-lavc-o'] != baseline['vd-lavc-o'],
              'renderModeDiffersFromIdle': baseline != null &&
                  config['mediacodec-embed-render-mode'] !=
                      baseline['mediacodec-embed-render-mode'],
              'hwdecDiffersFromActiveExpected': actualTypedRoute == null ||
                  config['hwdec'] != actualTypedRoute.hwdec,
              'hwdecCurrentDiffersFromActiveExpected':
                  actualTypedRoute == null ||
                      config['hwdec-current'] != actualTypedRoute.hwdec,
              'voDiffersFromActiveExpected': actualTypedRoute == null ||
                  config['vo'] != actualTypedRoute.vo,
            };
            if (failedConditions.values.any((failed) => failed)) {
              final truncatedFields = <String>[];
              final rawCodec = config['android-mediacodec-info'] ?? '';
              final boundedCodec = _boundedRejectionText(
                rawCodec,
                limit: _androidNativeDvRejectionTextLimit,
                truncatedFields: truncatedFields,
                fieldName: 'codecRaw',
              );
              final applied =
                  (segment['record'] as Map<String, Object?>)['routeApplied'];
              final appliedMap =
                  applied is Map ? applied : const <Object?, Object?>{};
              final evidence = <String, Object?>{
                'kind': 'sdr-configuration-rejection-v1',
                'route': route.name,
                'routeApplied': <String, Object?>{
                  if (appliedMap['route'] != null)
                    'route': _boundedRejectionText(
                      appliedMap['route'],
                      truncatedFields: truncatedFields,
                      fieldName: 'routeApplied.route',
                    ),
                  if (appliedMap['generation'] != null)
                    'generation': appliedMap['generation'],
                },
                'activeExpected': _sdrRouteEvidence(
                  actualTypedRoute,
                  truncatedFields: truncatedFields,
                  fieldPrefix: 'activeExpected',
                ),
                'activeTypedRouteApplied': _sdrRouteEvidence(
                  appliedTypedRoute,
                  truncatedFields: truncatedFields,
                  fieldPrefix: 'activeTypedRouteApplied',
                ),
                'fixedSdrTextureContract': _sdrRouteEvidence(
                  _lgApi24SdrTextureRoute,
                  truncatedFields: truncatedFields,
                  fieldPrefix: 'fixedSdrTextureContract',
                ),
                'codecRaw': boundedCodec,
                'codecRawTruncated': boundedCodec.length != rawCodec.length,
                'codecParsed': <String, Object?>{
                  'mime': _boundedRejectionText(
                    codec?.mime,
                    truncatedFields: truncatedFields,
                    fieldName: 'codecParsed.mime',
                  ),
                  'codec': _boundedRejectionText(
                    codec?.codec,
                    truncatedFields: truncatedFields,
                    fieldName: 'codecParsed.codec',
                  ),
                  'nativeDvActive': codec?.nativeDvActive,
                },
                'actualProperties': <String, Object?>{
                  for (final key in const <String>[
                    'vd-lavc-o',
                    'mediacodec-embed-render-mode',
                    'hwdec',
                    'hwdec-current',
                    'vo',
                    'time-pos',
                    'duration',
                    'pause',
                  ])
                    key: _boundedRejectionText(
                      config[key],
                      truncatedFields: truncatedFields,
                      fieldName: 'actualProperties.$key',
                    ),
                },
                'idleExpected': baseline == null
                    ? null
                    : <String, Object?>{
                        for (final key in const <String>[
                          'vd-lavc-o',
                          'mediacodec-embed-render-mode',
                          'hwdec',
                          'hwdec-current',
                        ])
                          key: _boundedRejectionText(
                            baseline[key],
                            truncatedFields: truncatedFields,
                            fieldName: 'idleExpected.$key',
                          ),
                      },
                'cleanupIdleExpected': baseline == null
                    ? null
                    : <String, Object?>{
                        for (final key in const <String>[
                          'vd-lavc-o',
                          'mediacodec-embed-render-mode',
                          'hwdec',
                          'hwdec-current',
                          'vo',
                        ])
                          key: _boundedRejectionText(
                            baseline[key],
                            truncatedFields: truncatedFields,
                            fieldName: 'cleanupIdleExpected.$key',
                          ),
                      },
                'failedConditions': failedConditions,
                'failedConditionNames': failedConditions.entries
                    .where((entry) => entry.value)
                    .map((entry) => entry.key)
                    .toList(growable: false),
                'sourceBefore': <String, Object?>{
                  'path': _boundedRejectionText(
                    before['path'],
                    truncatedFields: truncatedFields,
                    fieldName: 'sourceBefore.path',
                  ),
                  'entryId': _boundedRejectionText(
                    before['playlist/0/id'],
                    truncatedFields: truncatedFields,
                    fieldName: 'sourceBefore.entryId',
                  ),
                  'epoch': beforeEpoch,
                },
                'sourceAfter': <String, Object?>{
                  'path': _boundedRejectionText(
                    after['path'],
                    truncatedFields: truncatedFields,
                    fieldName: 'sourceAfter.path',
                  ),
                  'entryId': _boundedRejectionText(
                    after['playlist/0/id'],
                    truncatedFields: truncatedFields,
                    fieldName: 'sourceAfter.entryId',
                  ),
                  'epoch': afterEpoch,
                },
                'outputBindingBefore': _boundedLifecycleBinding(outputBefore),
                'outputBindingAfter': _boundedLifecycleBinding(outputAfter),
                'sample': <String, Object?>{
                  'timePosSeconds': double.tryParse(config['time-pos'] ?? ''),
                  'durationSeconds': double.tryParse(config['duration'] ?? ''),
                  'pause': _boundedRejectionText(
                    config['pause'],
                    limit: 64,
                    truncatedFields: truncatedFields,
                    fieldName: 'sample.pause',
                  ),
                },
                'truncatedFields': truncatedFields,
              };
              final encoded = jsonEncode(evidence);
              throw StateError('SDR_CONFIGURATION_REJECTED:$encoded');
            }
          }
          if (_closed ||
              _closing ||
              run.closed ||
              run.remaining <= Duration.zero) {
            return false;
          }
          final entryId = after['playlist/0/id']!;
          final identity = <String, Object?>{
            'path': after['path'],
            'playlistEntryId': entryId,
            'fileLoadedEpoch': afterEpoch,
            'playerIdentity': identityHashCode(player),
          };
          final identityBefore = segment['identity'] as Map<String, Object?>?;
          if (identityBefore != null &&
              (identityBefore['path'] != identity['path'] ||
                  identityBefore['playlistEntryId'] != entryId ||
                  identityBefore['fileLoadedEpoch'] != afterEpoch)) {
            throw StateError(
                'Segment no longer matches its first observed identity');
          }
          segment['identity'] ??= identity;
          segment['epoch'] ??= afterEpoch;
          segment['entryId'] ??= entryId;
          segment['outputBinding'] ??= outputAfter;
          final record = segment['record'] as Map<String, Object?>;
          run.markSegmentIdentity(
            identity: identity,
            outputBinding: outputAfter,
          );
          final position = double.tryParse(config['time-pos'] ?? '');
          final duration = double.tryParse(config['duration'] ?? '');
          final eos = terminalObserved ||
              (position != null && duration != null && position >= duration);
          final row = <String, Object?>{
            'elapsedMs': run.elapsed.inMilliseconds,
            'sessionInstanceId': _sessionInstanceId,
            'generation': generation,
            'expectedSource': expectedSource,
            'sourceBefore': before,
            'sourceAfter': after,
            'fileLoadedEpochBefore': beforeEpoch,
            'fileLoadedEpochAfter': afterEpoch,
            'videoControllerIdentity': identityHashCode(bindingAfter['video']!),
            'platformControllerIdentity':
                identityHashCode(activeControllerAfter!),
            'outputBindingBefore': outputBefore,
            'outputBindingAfter': outputAfter,
            if (proof != null) 'surfaceTuple': boundAfter!.asChannelArguments(),
            'route': route.name,
            'configuration': <String, Object?>{
              'mime': codec?.mime,
              'codec': codec?.codec,
              'nativeDvActive': codec?.nativeDvActive,
              'hwdecCurrent': config['hwdec-current'],
              'hwdec': config['hwdec'],
              'vo': config['vo'],
              'vdLavcOptions': config['vd-lavc-o'],
              'renderMode': config['mediacodec-embed-render-mode'],
            },
            'properties': config,
            'timePosSeconds': position,
            'durationSeconds': duration,
            'playerState': <String, Object?>{
              'playing': player.state.playing,
              'completed': player.state.completed,
              'buffering': player.state.buffering,
              'pauseProperty': config['pause'],
            },
            'eos': eos,
            'eosEventObserved': terminalObserved,
            'presentationVerified': false,
          };
          if (!run.appendRow(row)) return false;
          final rowWaiter = _rowProgressWaiters
              .remove('${segment['sessionInstanceId']}:$generation');
          if (rowWaiter != null && !rowWaiter.isCompleted) {
            rowWaiter.complete();
          }
          _appliedAdmissions['${segment['sessionInstanceId']}:$generation']
              ?.accept(record);
          if (eos) {
            record['phase'] = 'terminal';
            run.closeSegment('eos');
          }
          return eos;
        }),
      );
      if (acceptedEos) {
        _timer?.cancel();
        _activeLifecycleSegment = null;
        _phase = 'eos';
        return true;
      }
      return false;
    } catch (error) {
      if (_closing || _closed) return false;
      if (error is _ExpectedLifecycleSurfaceDrift &&
          identical(segment, _activeLifecycleSegment)) {
        _timer?.cancel();
        _timer = null;
        run.closeSegment('surface-drift', error: error);
        final rowWaiter = _rowProgressWaiters
            .remove('${segment['sessionInstanceId']}:${segment['generation']}');
        if (rowWaiter != null && !rowWaiter.isCompleted) {
          rowWaiter.completeError(StateError('Surface drift ended segment'));
        }
        _activeLifecycleSegment = null;
        _segment.beginClose();
        await run.recordStep(
          actionId: run.currentActionId ?? 'external-lifecycle',
          requestId: run.currentRequestId ??
              'surface-drift-${run.elapsed.inMilliseconds}',
          stepId: 'surface-drift',
          phase: 'observed',
          sessionInstanceId: _sessionInstanceId,
          facts: <String, Object?>{
            'before': error.before,
            'after': error.after,
            'restoreActionRequired': true,
          },
        );
        _phase = 'surface-drift · RestoreSurface available';
        return false;
      }
      if (!identical(segment, _activeLifecycleSegment)) return false;
      _timer?.cancel();
      _sampleFailed = true;
      _phase = 'samplingError';
      _error = '$error';
      run.markSegmentError(error);
      final rowWaiter = _rowProgressWaiters
          .remove('${segment['sessionInstanceId']}:${segment['generation']}');
      if (rowWaiter != null && !rowWaiter.isCompleted) {
        rowWaiter.completeError(error);
      }
      _activeLifecycleSegment = null;
      return false;
    } finally {
      _queueWrite();
    }
  }

  Future<bool> _sampleLocked(
    HdrNativeDvReviewEvidence proof,
    int generation,
    bool terminal,
  ) async {
    try {
      await _sampleLock.synchronized(() => player.lock.synchronized(() async {
            if (_closed || _closing || _sampleFailed) return false;
            final epochBefore = player.fileLoadedEpoch;
            final controller = await _activeOutputController();
            if (!identical(controller, proof.controller)) {
              throw StateError('Session output controller changed');
            }
            final outputBefore = _outputIdentity(controller);
            final before = await _readTuple();
            final terminalAtStart =
                terminal || _segment.terminalObserved || player.state.completed;
            final currentBefore = _session?.report.value;
            if (epochBefore != proof.source.fileLoadedEpoch ||
                !androidNativeDvSessionIdentityMatches(
                  expectedPath: proof.source.path,
                  actualPath: before['path']!,
                  expectedEntryId: proof.source.playlistEntryId,
                  actualEntryId: before['playlist/0/id']!,
                  expectedEpoch: epochBefore,
                  actualEpoch: player.fileLoadedEpoch,
                  terminalObserved: terminalAtStart,
                ) ||
                outputBefore != proof.output ||
                !androidNativeDvSessionRouteBindingMatches(
                  acceptedGeneration: _acceptedGeneration!,
                  appliedGeneration: generation,
                  currentSessionGeneration: currentBefore?.generation ?? -1,
                  appliedNativeDv: generation == _appliedGeneration &&
                      currentBefore?.actual?.strategy ==
                          HdrStrategy.nativeDolbyVision,
                  reportedNativeDv: currentBefore?.actual?.strategy ==
                      HdrStrategy.nativeDolbyVision,
                )) {
              throw StateError(
                  'Accepted source/output/generation changed before property reads');
            }
            final config = <String, String>{};
            for (final key in const [
              'android-mediacodec-info',
              'hwdec-current',
              'vo',
              'hwdec',
              'vd-lavc-o',
              'mediacodec-embed-render-mode',
              'time-pos',
              'duration',
              'frame-drop-count',
              'decoder-frame-drop-count',
              'mistimed-frame-count',
              'vo-delayed-frame-count',
            ]) {
              config[key] = await _readProperty(key);
            }
            for (final key in const [
              'android-mediacodec-info',
              'hwdec-current',
              'hwdec',
              'vo',
              'vd-lavc-o',
              'mediacodec-embed-render-mode',
            ]) {
              final tail = await _readProperty(key);
              if (tail != config[key]) {
                throw StateError(
                    'Session codec property changed during sample: $key');
              }
            }
            final after = await _readTuple();
            final outputAfter = _outputIdentity(controller);
            final epochAfter = player.fileLoadedEpoch;
            final currentReport = _session?.report.value;
            final terminalObserved = terminalAtStart ||
                _segment.terminalObserved ||
                player.state.completed;
            final pathTransitionIsOwned = before['path'] == after['path'] ||
                (terminalObserved &&
                    (before['path'] == proof.source.path ||
                        before['path']!.isEmpty) &&
                    (after['path'] == proof.source.path ||
                        after['path']!.isEmpty));
            if (epochBefore != proof.source.fileLoadedEpoch ||
                epochAfter != epochBefore ||
                !pathTransitionIsOwned ||
                before['playlist/0/id'] != after['playlist/0/id'] ||
                !androidNativeDvSessionIdentityMatches(
                  expectedPath: proof.source.path,
                  actualPath: after['path']!,
                  expectedEntryId: proof.source.playlistEntryId,
                  actualEntryId: after['playlist/0/id']!,
                  expectedEpoch: proof.source.fileLoadedEpoch,
                  actualEpoch: epochAfter,
                  terminalObserved: terminalObserved,
                ) ||
                !androidNativeDvSessionRouteBindingMatches(
                  acceptedGeneration: _acceptedGeneration!,
                  appliedGeneration: generation,
                  currentSessionGeneration: currentReport?.generation ?? -1,
                  appliedNativeDv: generation == _appliedGeneration &&
                      currentReport?.actual?.strategy ==
                          HdrStrategy.nativeDolbyVision,
                  reportedNativeDv: currentReport?.actual?.strategy ==
                      HdrStrategy.nativeDolbyVision,
                ) ||
                outputBefore != proof.output ||
                outputAfter != outputBefore) {
              throw StateError(
                  'Accepted source/output identity drift; segment stopped');
            }
            if (terminalObserved &&
                ((after['path']!.isNotEmpty &&
                        after['path'] != proof.source.path) ||
                    after['playlist/0/id'] != proof.source.playlistEntryId ||
                    epochAfter != proof.source.fileLoadedEpoch)) {
              throw StateError(
                  'EOS identity did not retain the accepted entry and epoch');
            }
            final codec = AndroidMediaCodecConfiguration.parse(
                config['android-mediacodec-info']);
            if (codec == null ||
                !codec.nativeDvActive ||
                codec.mime != proof.configuration.mime ||
                codec.codec != proof.configuration.codec ||
                config['hwdec-current'] != proof.hwdecCurrent ||
                config['hwdec'] != 'mediacodec' ||
                config['vo'] != 'mediacodec_embed' ||
                config['vd-lavc-o']?.contains('native_dv=1') != true ||
                config['mediacodec-embed-render-mode'] != 'timed') {
              throw StateError(
                  'Current native DV configuration no longer matches accepted route');
            }
            if (_closed || _closing) return false;
            if (_remainingBudget() <= Duration.zero) {
              _timer?.cancel();
              _phase = 'deadline';
              return false;
            }
            final position = double.tryParse(config['time-pos'] ?? '');
            final eos = terminalObserved ||
                player.state.completed ||
                (position != null &&
                    double.tryParse(config['duration'] ?? '') != null &&
                    position >= double.parse(config['duration']!));
            _rows.add(<String, Object?>{
              'index': _rows.length,
              'elapsedMs': _clock.elapsedMilliseconds,
              'generation': generation,
              'source':
                  Map<String, Object?>.from(_acceptedJson!['source'] as Map),
              'codecConfiguration': {
                'mime': codec.mime,
                'codec': codec.codec,
                'nativeDvActive': codec.nativeDvActive,
              },
              'hwdecCurrent': config['hwdec-current'],
              'properties': config,
              'timePosSeconds': position,
              'eos': eos,
            });
            return eos;
          }));
      final eosAccepted = _rows.isNotEmpty && _rows.last['eos'] == true;
      if (eosAccepted ||
          _rows.length >= androidNativeDvSessionDiagnosticMaxRows ||
          _clock.elapsed >= Duration(seconds: durationSeconds) ||
          terminal) {
        _timer?.cancel();
        _phase = eosAccepted
            ? 'eos'
            : _clock.elapsed >= Duration(seconds: durationSeconds)
                ? 'deadline'
                : terminal
                    ? 'terminalNoRow'
                    : 'samplingComplete';
      }
      return eosAccepted;
    } catch (error, stack) {
      if (_closed || _closing) return false;
      _sampleFailed = true;
      _timer?.cancel();
      _error = '$error\n$stack';
      _phase = 'samplingError';
      return false;
    } finally {
      _queueWrite();
    }
  }

  Future<AndroidVideoController> _activeOutputController() async {
    final session = _session;
    if (session == null) throw StateError('Session is not attached');
    final video = session.controller.value;
    if (video == null || !video.platform.isCompleted) {
      throw StateError(
          'Current Session controller has no completed platform output');
    }
    final platform = await video.platform.future;
    if (platform is! AndroidVideoController) {
      throw StateError('Current Session output is not AndroidVideoController');
    }
    return platform;
  }

  Future<Map<String, Object?>> _currentLifecycleOutputBinding({
    required bool nativePlatformView,
  }) async {
    final session = _session;
    final video = session?.controller.value;
    if (video == null || !video.platform.isCompleted) {
      return <String, Object?>{
        'available': false,
        'video': video,
        'platform': null,
        'nativeOwner': null,
        'json': <String, Object?>{
          'kind':
              nativePlatformView ? 'android-platform-view' : 'android-texture',
          'available': false,
          'reason': 'Session VideoController/platform is not published',
        },
      };
    }
    if (!identical(video.player, player)) {
      throw StateError('Session VideoController belongs to a foreign Player');
    }
    final platform = await video.platform.future;
    if (platform is! AndroidVideoController ||
        !identical(video.notifier.value, platform)) {
      throw StateError(
          'Session Android output controller is foreign/unpublished');
    }
    if (nativePlatformView) {
      final owner = platform.currentBoundOutputIdentity;
      return <String, Object?>{
        'available': owner != null,
        'video': video,
        'platform': platform,
        'nativeOwner': owner,
        'json': <String, Object?>{
          'kind': 'android-platform-view',
          'videoControllerIdentity': identityHashCode(video),
          'platformControllerIdentity': identityHashCode(platform),
          'topologyGeneration': platform.nativeSurfaceGeneration,
          'bound': owner != null,
          'surfaceTuple': owner?.asChannelArguments(),
        },
      };
    }
    try {
      final snapshot = androidNativeDvTextureBindingSnapshotForTesting(
        video: video,
        output: platform,
      );
      return <String, Object?>{
        'available': true,
        'video': video,
        'platform': platform,
        'nativeOwner': null,
        'json': snapshot,
      };
    } catch (error) {
      Rect? rectJsonSource = video.rect.value;
      return <String, Object?>{
        'available': false,
        'video': video,
        'platform': platform,
        'nativeOwner': null,
        'json': <String, Object?>{
          'kind': 'android-texture',
          'videoControllerIdentity': identityHashCode(video),
          'platformControllerIdentity': identityHashCode(platform),
          'textureId': video.id.value,
          'platformTextureId': platform.id.value,
          'rect': rectJsonSource == null
              ? null
              : <String, Object?>{
                  'left': rectJsonSource.left,
                  'top': rectJsonSource.top,
                  'right': rectJsonSource.right,
                  'bottom': rectJsonSource.bottom,
                  'width': rectJsonSource.width,
                  'height': rectJsonSource.height,
                },
          'topologyGeneration': platform.nativeSurfaceGeneration,
          'topologyGenerationSource':
              'AndroidVideoController.nativeSurfaceGeneration',
          'bindingMeaning': 'matching before/after endpoint snapshots',
          'abaAbsenceProven': false,
          'continuousBindingProven': false,
          'available': false,
          'reason': '$error',
        },
      };
    }
  }

  AndroidSurfaceAccountId? _outputIdentity(AndroidVideoController controller) =>
      controller.currentBoundOutputIdentity;

  Future<Map<String, String>> _readTuple(
          {Map<String, Object?>? segmentToken}) async =>
      <String, String>{
        'path': await _readProperty('path', segmentToken: segmentToken),
        'playlist/0/id':
            await _readProperty('playlist/0/id', segmentToken: segmentToken),
      };

  Future<String> _readProperty(
    String name, {
    Map<String, Object?>? segmentToken,
  }) async {
    void checkSegment() {
      if (segmentToken != null &&
          !identical(segmentToken, _activeLifecycleSegment)) {
        throw StateError(
            'Sampling segment changed before property read: $name');
      }
    }

    if (_closed || _closing) {
      throw StateError('Sampling closed before property read: $name');
    }
    checkSegment();
    final unsettled = _pendingPropertyRead;
    if (unsettled != null) {
      await unsettled.timeout(_remainingBudget());
      if (_closed || _closing) {
        throw StateError(
            'Sampling closed while waiting for property read: $name');
      }
      checkSegment();
      if (_remainingBudget() <= Duration.zero) {
        throw TimeoutException(
            'Sampling deadline reached while waiting for property read');
      }
      if (identical(_pendingPropertyRead, unsettled)) {
        _pendingPropertyRead = null;
      }
    }
    if (_closed || _closing) {
      throw StateError('Sampling closed before property read: $name');
    }
    checkSegment();
    final remaining = _remainingBudget();
    if (remaining <= Duration.zero) {
      throw TimeoutException('Sampling deadline reached');
    }
    final operation = player.getProperty(name, waitForInitialization: false);
    _pendingPropertyRead = operation;
    unawaited(operation.then<void>((_) {
      if (identical(_pendingPropertyRead, operation)) {
        _pendingPropertyRead = null;
      }
    }, onError: (Object _, StackTrace __) {
      if (identical(_pendingPropertyRead, operation)) {
        _pendingPropertyRead = null;
      }
    }));
    final value = await operation.timeout(remaining < const Duration(seconds: 3)
        ? remaining
        : const Duration(seconds: 3));
    if (_closed || _closing) {
      throw StateError('Sampling closed while reading property: $name');
    }
    checkSegment();
    if (_remainingBudget() <= Duration.zero) {
      throw TimeoutException(
          'Sampling deadline reached after property read: $name');
    }
    return value;
  }

  @visibleForTesting
  Future<String> readPropertyForTesting(String name) => _readProperty(name);

  @visibleForTesting
  void startSamplingClockForTesting() => _clock.start();

  Duration _remainingBudget() {
    final local = Duration(seconds: durationSeconds) - _clock.elapsed;
    final lifecycle = lifecycleRun?.remaining;
    return lifecycle == null || local <= lifecycle ? local : lifecycle;
  }

  Future<void> close({String cleanup = 'session disposal pending'}) async {
    if (_closed) {
      await _sampleFuture;
      await _settlePropertyRead();
      await _writes.flush();
      await lifecycleRun?.flush();
      return;
    }
    _closing = true;
    _segment.beginClose();
    if (lifecycleRun == null) {
      _writes.closeAdmission();
    }
    _timer?.cancel();
    await _events?.cancel();
    await _completed?.cancel();
    try {
      await _sampleFuture;
    } catch (_) {}
    await _settlePropertyRead();
    lifecycleRun?.closeSegment(cleanup);
    _cleanup = cleanup;
    _phase = 'closed';
    _closed = true;
    _closing = false;
    await _enqueueWrite();
    await lifecycleRun?.flush();
  }

  Future<bool> capturePostSessionCleanup({
    required HdrDisposalReport? report,
    required Object? sessionDisposeError,
    String sessionInstanceId = 'session-1',
  }) async {
    Object? readError;
    Map<String, Object?> observed = <String, Object?>{};
    try {
      await player.lock.synchronized(() async {
        final epochBefore = player.fileLoadedEpoch;
        final names = await _captureLifecyclePropertiesLocked();
        final epochAfter = player.fileLoadedEpoch;
        observed = <String, Object?>{
          'properties': names,
          'fileLoadedEpochBefore': epochBefore,
          'fileLoadedEpochAfter': epochAfter,
          'configuredCodec': _codecJson(names['android-mediacodec-info']),
        };
      });
    } catch (error) {
      readError = error;
    }
    final baseline = _initialIdleProperties;
    final baselineEpoch = _initialIdleEpoch;
    final postProperties = observed['properties'];
    final post =
        postProperties is Map ? Map<String, String>.from(postProperties) : null;
    final epochBefore = observed['fileLoadedEpochBefore'];
    final epochAfter = observed['fileLoadedEpochAfter'];
    final codecRestored = baseline != null &&
        _sameCodecFacts(
          _codecJson(baseline['android-mediacodec-info']),
          _codecJson(post?['android-mediacodec-info']),
        );
    final sourceRestored = baseline != null &&
        post != null &&
        post['path'] == baseline['path'] &&
        post['playlist/0/id'] == baseline['playlist/0/id'];
    final epochStable = baselineEpoch != null &&
        epochBefore is int &&
        epochAfter is int &&
        epochBefore == epochAfter &&
        epochAfter >= baselineEpoch;
    final optionsRestored = baseline != null &&
        post != null &&
        const <String>[
          'vd-lavc-o',
          'mediacodec-embed-render-mode',
          'hwdec',
          'hwdec-current',
          'vo',
        ].every((name) => post[name] == baseline[name]) &&
        !(AndroidMediaCodecConfiguration.parse(post['android-mediacodec-info'])
                ?.nativeDvActive ??
            false) &&
        post['vd-lavc-o']?.contains('native_dv=1') != true;
    final restorationMatches = baseline != null &&
        sourceRestored &&
        epochStable &&
        optionsRestored &&
        codecRestored;
    _lastCleanupVerified = report?.clean == true &&
        sessionDisposeError == null &&
        readError == null &&
        (lifecycleRun == null || restorationMatches);
    _cleanupEvidence = <String, Object?>{
      'sessionDisposeClean': report?.clean,
      'sessionDisposeReport': report == null
          ? null
          : <String, Object?>{
              'coordinatorError': '${report.coordinatorError}',
              'playerError': '${report.playerError}',
              'directoryError': '${report.directoryError}',
              'retainedDirectory': report.retainedDirectory,
            },
      'surfaceAfterSessionDispose': _sessionSurfaceAfterDisposal(),
      'sessionDisposeError': '$sessionDisposeError',
      'postSessionObservedProperties': observed,
      'postSessionReadError': '$readError',
      'initialIdleBaseline': baseline == null
          ? null
          : <String, Object?>{
              'properties': baseline,
              'fileLoadedEpoch': baselineEpoch,
            },
      'restorationChecks': <String, Object?>{
        'sourceMatchesIdleBaseline': sourceRestored,
        'fileLoadedEpochStableAndMonotonic': epochStable,
        'optionsMatchBaseline': optionsRestored,
        'codecConfigurationMatchesBaseline': codecRestored,
        'verified': lifecycleRun == null ? null : restorationMatches,
      },
      'surfaceReleaseAcknowledgement': 'not independently observed',
      'playerTermination': 'pending',
    };
    _cleanup = _lastCleanupVerified
        ? 'session disposed; restoration properties recorded; surface release unverified'
        : lifecycleRun == null &&
                report?.clean == true &&
                sessionDisposeError == null &&
                readError == null
            ? 'session disposed; restoration properties recorded; surface release unverified'
            : 'cleanup debt recorded before player termination';
    final lifecycle = lifecycleRun;
    if (lifecycle != null) {
      if (!_lastCleanupVerified) {
        lifecycle.markDebt(
            'Post-Session actual source/options/config did not match the idle baseline');
      }
      lifecycle.markSessionDisposed(
        sessionInstanceId: sessionInstanceId,
        clean: _lastCleanupVerified,
        report: report == null
            ? <String, Object?>{'present': false}
            : <String, Object?>{
                'coordinatorError': '${report.coordinatorError}',
                'playerError': '${report.playerError}',
                'directoryError': '${report.directoryError}',
                'retainedDirectory': report.retainedDirectory,
              },
        restoredProperties: readError == null
            ? <String, Object?>{
                if (observed['properties'] is Map)
                  'properties': Map<String, Object?>.from(
                    observed['properties'] as Map,
                  ),
                'fileLoadedEpochBefore': observed['fileLoadedEpochBefore'],
                'fileLoadedEpochAfter': observed['fileLoadedEpochAfter'],
                'configuredCodec': observed['configuredCodec'],
                'surfaceAfterSessionDispose': _sessionSurfaceAfterDisposal(),
                'restorationChecks': _cleanupEvidence!['restorationChecks'],
              }
            : null,
      );
    }
    await _enqueueWrite();
    return _lastCleanupVerified;
  }

  bool _sameCodecFacts(
    Map<String, Object?>? first,
    Map<String, Object?>? second,
  ) {
    if (first == null || second == null) return first == null && second == null;
    return first['mime'] == second['mime'] &&
        first['codec'] == second['codec'] &&
        first['nativeDvActive'] == second['nativeDvActive'];
  }

  Future<void> recordPlayerTermination({required Object? error}) async {
    final evidence = _cleanupEvidence ?? <String, Object?>{};
    evidence['playerTermination'] =
        error == null ? 'completed' : 'error: $error';
    if (error != null ||
        evidence['sessionDisposeClean'] != true ||
        evidence['postSessionReadError'] != 'null' ||
        (evidence['restorationChecks'] is Map &&
            (evidence['restorationChecks'] as Map)['verified'] == false)) {
      _cleanup = 'terminated-with-debt';
    }
    final lifecycle = lifecycleRun;
    if (lifecycle != null) {
      lifecycle.markPlayerTerminated(success: error == null);
      final actionId = lifecycle.currentActionId ?? 'close-and-exit';
      final requestId = lifecycle.currentRequestId ?? 'termination';
      await lifecycle.recordStep(
        actionId: actionId,
        requestId: requestId,
        stepId: 'player-termination',
        phase: error == null ? 'completed' : 'debt',
        error: error,
      );
      if (error != null) {
        lifecycle.markDebt('Player termination failed: $error');
      }
    }
    await _enqueueWrite();
  }

  Future<void> recordCleanupCaptureError(Object error) async {
    final evidence = _cleanupEvidence ?? <String, Object?>{};
    evidence['cleanupCaptureError'] = '$error';
    _cleanupEvidence = evidence;
    _cleanup = 'cleanup-observation-debt-before-termination';
    lifecycleRun?.markDebt('Cleanup capture failed: $error');
    await _enqueueWrite();
  }

  Map<String, Object?>? _sessionSurfaceAfterDisposal() {
    final controller = _accepted?.controller;
    if (controller is! AndroidVideoController) {
      return <String, Object?>{
        'currentController': controller == null ? 'none' : 'unexpected-type',
        'releaseAcknowledgement': 'not independently observable',
      };
    }
    return <String, Object?>{
      'currentControllerIdentity': identityHashCode(controller),
      'boundOwner': controller.currentBoundOutputIdentity?.asChannelArguments(),
      'releaseAcknowledgement': 'not independently observable',
    };
  }

  Map<String, Object?>? _codecJson(String? raw) {
    final codec = AndroidMediaCodecConfiguration.parse(raw);
    if (codec == null) return null;
    return <String, Object?>{
      'mime': codec.mime,
      'codec': codec.codec,
      'nativeDvActive': codec.nativeDvActive,
    };
  }

  Future<void> _settlePropertyRead() async {
    final pending = _pendingPropertyRead;
    if (pending == null) return;
    try {
      await pending;
    } catch (_) {}
    if (identical(_pendingPropertyRead, pending)) _pendingPropertyRead = null;
  }

  void _queueWrite() {
    if (_closing || _closed) return;
    final lifecycle = lifecycleRun;
    if (lifecycle != null) {
      lifecycle.scheduleWrite();
      return;
    }
    _writes.schedule(_write);
  }

  Future<void> _enqueueWrite() {
    final lifecycle = lifecycleRun;
    return lifecycle == null ? _writes.enqueue(_write) : lifecycle.writeNow();
  }

  Future<void> _write() async {
    final lifecycle = lifecycleRun;
    if (lifecycle != null) {
      await lifecycle.writeNow();
      status.value = lifecycle.status.value;
      return;
    }
    final file = _file;
    if (file == null) return;
    final value = <String, Object?>{
      'schema': 1,
      'diagnosticOnly': true,
      'diagnosticRoute': 'session',
      'runId': runId,
      'startUtc': startUtc,
      'externalIdentityLabel': externalIdentityLabel,
      'sourcePath': androidNativeDvSessionDiagnosticSource,
      'sourceDescriptorOrigin': 'fixed-fixture caller hint; not extractor fact',
      'phase': _phase,
      'error': _error,
      'ordinaryPrediction': _ordinaryPrediction?.toString(),
      'ordinaryRefusal': _ordinaryNativeRefusal(),
      'consumerValidated': _acceptedJson,
      'routeApplied': _appliedJson,
      'rowCount': _rows.length,
      'rows': List<Map<String, Object?>>.unmodifiable(_rows),
      'presentationVerified': false,
      'cleanup': _cleanup,
      'cleanupEvidence': _cleanupEvidence,
    };
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(jsonEncode(value), flush: true);
    await temp.rename(file.path);
    status.value = '$_phase · ${_rows.length} samples · ${file.path}';
  }

  String? _ordinaryNativeRefusal() {
    final prediction = _ordinaryPrediction;
    if (prediction == null) return null;
    for (final candidate in prediction.candidates) {
      if (candidate.strategy == HdrStrategy.nativeDolbyVision) {
        return candidate.skipReason?.name ?? candidate.maturity.name;
      }
    }
    return null;
  }
}
