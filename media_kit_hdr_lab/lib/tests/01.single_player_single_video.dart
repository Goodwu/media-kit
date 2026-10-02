import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../common/globals.dart';
import '../common/sources/sources.dart';
import '../common/widgets.dart';

class SinglePlayerSingleVideoScreen extends StatefulWidget {
  const SinglePlayerSingleVideoScreen({super.key});

  @override
  State<SinglePlayerSingleVideoScreen> createState() =>
      _SinglePlayerSingleVideoScreenState();
}

class _SinglePlayerSingleVideoScreenState
    extends State<SinglePlayerSingleVideoScreen> with WidgetsBindingObserver {
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
  void _createHdrSession() {
    if (_hdrSession != null) return;
    final policy = _hdrRoutingPolicy();
    // migrated to HdrVideoSession (S10): the lab coordinator/slot/backend are
    // replaced by the library session. The public constructor cannot inject a
    // capability provider, so the simulate-no-HLG switch uses the
    // @visibleForTesting constructor to wrap one (see the S10 report).
    final session = _androidHdrSimulateNoHlg
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
    // Follow controller replacements (Texture ↔ PlatformView topology
    // switches) the way the old output slot's publish callback did.
    session.controller.addListener(_onHdrControllerChanged);
    session.report.addListener(_onHdrReportChanged);
    session.events.listen((event) => debugPrint('HDR_SESSION_EVENT $event'));
    _hdrSession = session;
  }

  void _onHdrControllerChanged() {
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
    if (!_androidHdrPolicyExperimental) return HdrRoutingPolicy.defaults;
    final base =
        HdrRoutingPolicy.defaultPreferences[HdrSourceClass.dvP84] ??
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
    final Set<int>? filtered =
        types == null ? null : <int>{...types};
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
    final serial = ++_hdrOpenSerial;
    _hdrCurrentSource = source;
    try {
      await _applyAndroidVideoTimingOffset();
      await _applyAndroidScalers();
      final hint = _hintFor(source);
      debugPrint('ANDROID_HDR_OPEN_BEGIN path=$source hint=$hint serial=$serial '
          'simulateNoHlg=$_androidHdrSimulateNoHlg '
          'wrongHint=$_androidHdrWrongHint noHint=$_androidHdrNoHint '
          'policyExperimental=$_androidHdrPolicyExperimental '
          'namedLocalSource=$_androidNamedLocalSource '
          'p5RpuPipelineBuilt=$_androidP5RpuPipelineBuilt '
          'forceP84PqFallback=$_androidForceP84PqFallback '
          'textureCopyDiagnostic=$_androidTextureCopyDiagnostic '
          'gpuPlatformHdr=$_androidGpuPlatformHdr');
      await _requireHdrSession().open(Media(source), hint: hint, start: start);
      debugPrint('ANDROID_HDR_OPEN path=$source serial=$serial');
      if (serial == _hdrOpenSerial && mounted) {
        _logHdrSessionReport();
      }
      if (_androidOpenPhaseTrace) {
        unawaited(() async {
          final vo = await player.getProperty('vo');
          final hwdec = await player.getProperty('hwdec-current');
          final path = await player.getProperty('path');
          debugPrint('ANDROID_HDR_OUTPUT vo=$vo hwdecCurrent=$hwdec path=$path');
        }().catchError((Object error) {
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

  /// Prints the session report of the current generation with the full
  /// prediction (selected + every candidate) and the actual route — the A2
  /// prediction-consistency evidence and the A1 route/dataspace readback.
  void _logHdrSessionReport() {
    final session = _hdrSession;
    if (session == null) return;
    final report = session.report.value;
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

  Future<void> _openSelectedSource(String source) async {
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
          'target': configuration.value.android.usePlatformView ? 'platform' : 'flutter',
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
        if (Platform.isAndroid && !configuration.value.android.usePlatformView) {
          final prepared = await controller.prepareAndroidTextureOutput();
          debugPrint('ANDROID_SELECTED_TEXTURE_PREPARED layoutBound=$prepared');
        }
        await player.open(Media(source));
        if (Platform.isAndroid && _androidDirectOpenTrace) {
          debugPrint('ANDROID_DIRECT_OPEN media_returned');
        }
      }
    } catch (error) {
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
        debugPrint('ANDROID_DUAL_PLAYER second_open path=$_androidDualPlayerSource '
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
  static const _engineControlChannel = MethodChannel('media_kit_hdr_lab/engine_control');
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
      logLevel: (_androidVulkanProbe || _androidVerboseLog)
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

  @override
  void initState() {
    super.initState();
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
            debugPrint(
                'ANDROID_HDR_RECOVERY_OPEN path=$source');
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
            final report =
                await _videoChannel.invokeMapMethod<String, dynamic>(
              'PlatformVideoView.ApplyDataSpace',
              {'handle': handle.toString(), 'transfer': _androidSurfaceTransfer},
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
    if (Platform.isAndroid &&
        _androidHdrTransaction &&
        _androidHdrAutoResumeProbe) {
      if (_previousLifecycleState == AppLifecycleState.resumed &&
          state == AppLifecycleState.inactive) {
        _hdrResumeOpenSerial =
            player.state.playing ? _hdrOpenSerial : null;
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
        if (_androidHdrTransaction &&
            seekGuardSerial != _hdrOpenSerial) {
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
      final capabilities = await _capabilitiesChannel
          .invokeMapMethod<String, dynamic>('Get');
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
    if (Platform.isAndroid && _androidHdrTransaction) {
      await _disposeHdrPlayer();
    } else {
      await player.dispose();
    }
    debugPrint('AUTO_PLAYER_DISPOSE completed');
  }

  @override
  void dispose() {
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
    if (Platform.isAndroid && _androidFrameSchedulerProbe) {
      SchedulerBinding.instance.removeTimingsCallback(_frameTimingsCallback);
    }
    if (Platform.isAndroid &&
        (_androidPreDestroyVidStop ||
            _androidHdrLifecyclePositionProbe ||
            _androidHdrAutoResumeProbe)) {
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
    Object? playerDisposeError;
    try {
      await session?.dispose();
    } finally {
      try {
        await player.dispose();
      } catch (error) {
        playerDisposeError = error;
      }
    }
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

  @override
  Widget build(BuildContext context) {
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
      floatingActionButton: Row(
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
                                  ? HdrVideo(session: _hdrSession!)
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
                      ? HdrVideo(
                          session: _hdrSession!,
                          width: MediaQuery.of(context).size.width,
                          height:
                              MediaQuery.of(context).size.width * 9.0 / 16.0,
                        )
                      : displayController == null
                          ? AspectRatio(
                              aspectRatio: 16 / 9,
                              child: const ColoredBox(color: Colors.black),
                            )
                          : Video(
                              key: videoKey,
                              controller: displayController,
                              width: MediaQuery.of(context).size.width,
                              height:
                                  MediaQuery.of(context).size.width * 9.0 / 16.0,
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
