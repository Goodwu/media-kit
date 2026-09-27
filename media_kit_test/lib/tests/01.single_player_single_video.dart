import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path_provider/path_provider.dart' as path_provider;

import '../common/globals.dart';
import '../common/sources/android_hdr_disposal.dart';
import '../common/sources/android_hdr_open_coordinator.dart';
import '../common/sources/android_hdr_output_slot.dart';
import '../common/sources/android_hdr_player_backend.dart';
import '../common/sources/android_hdr_sample_identity.dart';
import '../common/sources/android_hdr_source_intent.dart';
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
  static const _androidGpuPqItuProbe = bool.fromEnvironment(
    'MEDIA_KIT_ANDROID_GPU_PQ_ITU_DATASPACE_PROBE',
  );
  static const _androidGpuHdrRgba8888SurfaceProbe = bool.fromEnvironment(
    'MEDIA_KIT_ANDROID_GPU_HDR_RGBA8888_SURFACE_PROBE',
  );
  static const _androidGpuHdrLateDataspaceProbe = bool.fromEnvironment(
    'MEDIA_KIT_ANDROID_GPU_HDR_LATE_DATASPACE_PROBE',
  );

  static String _surfaceTransferForProbe(String transfer) =>
      _androidGpuPlatformHdr && _androidGpuPqItuProbe && transfer == 'pq'
          ? 'pq-itu'
          : transfer;

  Future<AndroidHdrOpenCoordinator>? _hdrCoordinatorFuture;
  Future<void>? _hdrDisposeFuture;
  AndroidHdrDisposalReport? _hdrLastDisposeReport;
  Directory? _hdrPrivateRoot;
  final _hdrIntent = AndroidHdrSourceIntent<AndroidHdrOpenResult>();
  late final AndroidHdrOutputSlot<VideoController> _hdrOutputSlot =
      AndroidHdrOutputSlot<VideoController>(
    initial: _initialController,
    rebuildInitial: configuration.value.usePlatformView,
    voOf: (current) async =>
        (await current.platform.future).configuration.vo ?? '',
    disposeForRebuild: (current) => current.disposeForRebuild(),
    create: (vo, hwdec, surfaceTransfer) => VideoController(
      player,
      configuration: configuration.value.copyWith(
        vo: vo,
        hwdec: hwdec,
        androidGpuApi: vo == 'gpu-next' ? 'opengl' : null,
        clearAndroidGpuApi: vo != 'gpu-next',
        androidSurfaceTransfer: configuration.value.usePlatformView
            ? (surfaceTransfer == null ||
                    (vo == 'gpu-next' && _androidGpuHdrLateDataspaceProbe)
                ? ''
                : _surfaceTransferForProbe(surfaceTransfer))
            : null,
        androidSurfacePixelFormat: configuration.value.usePlatformView
            ? (vo == 'gpu-next' &&
                    !_androidGpuHdrRgba8888SurfaceProbe &&
                    !_androidP5PlatformSdrDiagnostic
                ? 'rgba1010102'
                : '')
            : null,
      ),
    ),
    publish: (_) {
      if (mounted) setState(() {});
    },
    waitReady: (current) async {
      final output = await current.platform.future;
      await output.waitUntilCurrentOutputBound
          .timeout(const Duration(seconds: 10));
    },
  );

  Future<AndroidHdrOpenCoordinator> _hdrCoordinator() =>
      _hdrCoordinatorFuture ??= _createHdrCoordinator();

  Future<AndroidHdrOpenCoordinator> _createHdrCoordinator() async {
    final backend = AndroidHdrPlayerBackend(
      player: player,
      outputSlot: _hdrOutputSlot,
      usePlatformView: configuration.value.usePlatformView,
      p5RpuPipelineBuilt: _androidP5RpuPipelineBuilt,
      p5PlatformSdrDiagnostic: _androidP5PlatformSdrDiagnostic,
      textureCopyDiagnostic: _androidTextureCopyDiagnostic,
      forceP84PqFallback: _androidForceP84PqFallback,
      gpuPlatformHdrExperiment: _androidHdrTransaction &&
          configuration.value.usePlatformView &&
          _androidGpuPlatformHdr,
      readDisplayHdrTypes: () async {
        final capabilities = await _videoChannel
            .invokeMapMethod<String, dynamic>('Android.Capabilities');
        final raw = capabilities?['displayHdrTypes'];
        if (raw is! List || raw.any((value) => value is! int)) {
          throw StateError('Invalid display HDR capability report: $raw');
        }
        final reported = raw.cast<int>().toSet();
        debugPrint('ANDROID_HDR_CAPABILITY reported=$reported '
            'simulateNoHlgForP84=$_androidForceP84PqFallback');
        return reported;
      },
      applySurfaceTransfer: (transfer) async {
        final handle = await player.handle;
        return await _videoChannel.invokeMethod<bool>(
              'PlatformVideoView.SetColorSpace',
              {
                'handle': handle.toString(),
                'transfer': _surfaceTransferForProbe(transfer),
              },
            ) ??
            false;
      },
      readP5RuntimeProperties: () async {
        final values = await _p5RuntimeGateChannel
            .invokeMapMethod<String, String>('ReadProperties');
        if (values == null) {
          throw StateError('P5 runtime property report is unavailable');
        }
        return values;
      },
    );
    if (_androidNamedLocalSource) {
      if (sources.isEmpty) throw StateError('No named Android sample selected');
      return AndroidHdrOpenCoordinator(
        backend,
        verifier: (source, cancelled) async {
          if (cancelled() || source != sources.first) {
            throw StateError('Named source is no longer selected');
          }
          final name = RegExp(
                  r'^/data/local/tmp/media-kit-(hdr10|hlg|p84|p5)-[a-z0-9][a-z0-9._-]*\.mp4$')
              .firstMatch(source);
          if (name == null ||
              await FileSystemEntity.type(source, followLinks: false) !=
                  FileSystemEntityType.file) {
            throw StateError('Named source does not match a regular fixture');
          }
          final sample = switch (name.group(1)) {
            'hdr10' => AndroidHdrSample.hdr10,
            'hlg' => AndroidHdrSample.hlgBaseControl,
            'p84' => AndroidHdrSample.dolbyVisionP84,
            'p5' => AndroidHdrSample.dolbyVisionP5,
            _ => throw StateError('Unknown named Android sample'),
          };
          debugPrint('ANDROID_NAMED_LOCAL_SAMPLE sample=$sample path=$source');
          return AndroidHdrSampleIdentity(sample, '', source);
        },
        onPhase: _androidOpenPhaseTrace
            ? (generation, phase, elapsedMicros) => debugPrint(
                'ANDROID_HDR_OPEN_PHASE generation=$generation phase=$phase '
                'elapsed_us=$elapsedMicros')
            : null,
      );
    }
    final support = await path_provider.getApplicationSupportDirectory();
    final parent = Directory('${support.path}/android-hdr-staged');
    await parent.create(recursive: true);
    final removed =
        await cleanupStaleAndroidHdrSessions(parent, currentPid: pid);
    if (removed > 0) debugPrint('ANDROID_HDR_STALE_SESSIONS removed=$removed');
    final privateRoot = await parent.createTemp('session-$pid-');
    _hdrPrivateRoot = privateRoot;
    return AndroidHdrOpenCoordinator.staged(
      backend,
      privateRoot,
      onPhase: _androidOpenPhaseTrace
          ? (generation, phase, elapsedMicros) => debugPrint(
              'ANDROID_HDR_OPEN_PHASE generation=$generation phase=$phase '
              'elapsed_us=$elapsedMicros')
          : null,
    );
  }

  Future<AndroidHdrOpenResult> _openHdrSource(
    String source, {
    Duration? start,
  }) async {
    final request = _hdrIntent.begin();
    try {
      await _applyAndroidVideoTimingOffset();
      await _applyAndroidScalers();
      final result = await (await _hdrCoordinator()).openSource(
        source,
        start: start,
      );
      _hdrIntent.succeed(request, source, result);
      debugPrint('ANDROID_HDR_OPEN sample=${result.identity.sample} '
          'presentationVerified=${result.presentationVerified} '
          'gpuPlatformHdr=$_androidGpuPlatformHdr '
          'simulateNoHlgForP84=$_androidForceP84PqFallback');
      if (_androidDualViewLifecycleProbe && !_dualViewProbeScheduled) {
        _dualViewProbeScheduled = true;
        unawaited(_runDualViewLifecycleProbe());
      }
      if (_androidHdrPauseAtMediaSeconds >= 0) {
        final snapshot = _hdrIntent.snapshot();
        unawaited(() async {
          try {
            final target = Duration(seconds: _androidHdrPauseAtMediaSeconds);
            await player.stream.position
                .firstWhere((position) => position >= target)
                .timeout(
                    Duration(seconds: _androidHdrPauseAtMediaSeconds + 30));
            if (!mounted || !_hdrIntent.mayResume(snapshot)) return;
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
        final snapshot = _hdrIntent.snapshot();
        unawaited(Future<void>.delayed(
            Duration(seconds: _androidHdrAutoPauseProbeSeconds), () async {
          if (!mounted || !_hdrIntent.mayResume(snapshot)) return;
          await player.pause();
          debugPrint('ANDROID_HDR_AUTO_PAUSE '
              'position=${player.state.position.inMilliseconds} '
              'pause=${await player.getProperty('pause')}');
        }));
      }
      return result;
    } catch (_) {
      _hdrIntent.fail(request);
      rethrow;
    }
  }

  Future<void> _openDirectSdrAfterHdr(String source) async {
    final coordinator = _hdrCoordinatorFuture;
    if (coordinator == null) {
      throw StateError('No HDR coordinator for SDR recovery');
    }
    // Invalidate delayed HDR pause/seek/resume callbacks before yielding to
    // coordinator disposal or opening the SDR source.
    final supersedingRequest = _hdrIntent.begin();
    _hdrIntent.fail(supersedingRequest);
    await (await coordinator).dispose();
    await player.open(Media(source));
    debugPrint('ANDROID_HDR_SDR_RECOVERY_OPEN path=$source '
        'vo=${await player.getProperty('vo')} '
        'hwdec=${await player.getProperty('hwdec-current')}');
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
          _hdrLastDisposeReport?.clean != true) {
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
          !_androidPreopenFullscreen &&
          !configuration.value.usePlatformView) {
        final started = await _flutterSurfaceProbeChannel
            .invokeMapMethod<String, dynamic>('StartFirstFrameProbe');
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
        if (Platform.isAndroid && !configuration.value.usePlatformView) {
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
  AndroidHdrSourceSnapshot<AndroidHdrOpenResult>? _hdrResumeSnapshot;
  bool _preDestroyStopped = false;
  AppLifecycleState _previousLifecycleState = AppLifecycleState.resumed;
  static const _windowChannel = MethodChannel('media_kit_test/window');
  static const _videoChannel = MethodChannel(
    'com.alexmercerind/media_kit_video',
  );
  static const _flutterSurfaceProbeChannel = MethodChannel(
    'media_kit_test/flutter_surface_probe',
  );
  static const _p5RuntimeGateChannel = MethodChannel(
    'media_kit_test/p5_runtime_gate',
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
          ? _hdrOutputSlot.current ?? _initialController
          : _initialController;

  @override
  void initState() {
    super.initState();
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
        const MethodChannel('media_kit_test/p5_codec_probe')
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
            final result = await _openHdrSource(source);
            debugPrint(
                'ANDROID_HDR_RECOVERY_OPEN sample=${result.identity.sample} '
                'path=$source');
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
        (completed) => debugPrint('AUTO_COMPLETED completed=$completed'),
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
        _hdrResumeSnapshot =
            player.state.playing ? _hdrIntent.snapshot() : null;
        debugPrint('ANDROID_HDR_AUTO_RESUME capturedPlaying='
            '${_hdrResumeSnapshot != null} '
            'position=${player.state.position.inMilliseconds}');
      } else if (state == AppLifecycleState.resumed) {
        final snapshot = _hdrResumeSnapshot;
        _hdrResumeSnapshot = null;
        if (snapshot != null) {
          unawaited(() async {
            if (!_hdrIntent.mayResume(snapshot)) return;
            final output = _hdrOutputSlot.current;
            final session = snapshot.session;
            if (output == null || session == null) return;
            final platform = await output.platform.future;
            await platform.waitUntilCurrentOutputBound
                .timeout(const Duration(seconds: 10));
            if (!mounted || !_hdrIntent.mayResume(snapshot)) return;
            final coordinator = await _hdrCoordinator();
            await coordinator.runForCurrent(session, () => player.play());
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
      final snapshot = _hdrIntent.snapshot();
      final sessionBeforeResume = snapshot.session;
      unawaited(
          Future<void>.delayed(const Duration(milliseconds: 700), () async {
        if (!mounted) return;
        if (_androidHdrTransaction && !_hdrIntent.mayResume(snapshot)) {
          return;
        }
        final position = player.state.position;
        var sessionForSeek = sessionBeforeResume;
        if (_androidPostBindReopenProbe) {
          debugPrint(
              'POST_BIND_REOPEN begin position=$position ${DateTime.now().toIso8601String()}');
          if (_androidHdrTransaction) {
            final source = _hdrIntent.source;
            if (source == null) {
              throw StateError('No current HDR source to reopen');
            }
            sessionForSeek = await _openHdrSource(source);
          } else {
            await player.open(Media(sources[0]));
          }
          await Future<void>.delayed(const Duration(milliseconds: 700));
        }
        debugPrint(
            'POST_BIND_SEEK begin position=$position ${DateTime.now().toIso8601String()}');
        if (_androidHdrTransaction) {
          final coordinator = await _hdrCoordinator();
          final session = sessionForSeek;
          if (session == null) {
            throw StateError('No current HDR session to seek');
          }
          await coordinator.runForCurrent(session, () => player.seek(position));
        } else {
          await player.seek(position);
        }
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
      final capabilities = await _videoChannel.invokeMapMethod<String, dynamic>(
        'Android.Capabilities',
      );
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
        !configuration.value.usePlatformView) {
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
    final coordinator = _hdrCoordinatorFuture;
    final report = await disposeAndroidHdrResources(
      disposeCoordinator: coordinator == null
          ? null
          : () async => (await coordinator).dispose(),
      disposePlayer: player.dispose,
      privateRoot: () => _hdrPrivateRoot,
    );
    _hdrLastDisposeReport = report;
    if (!report.clean) {
      debugPrint('ANDROID_HDR_DISPOSE coordinator=${report.coordinatorError} '
          'player=${report.playerError} directory=${report.directoryError} '
          'retained=${report.retainedDirectory}');
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
    final displayController = _hdrOutputSlot.current ?? _initialController;
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
    final disposeReport = _hdrLastDisposeReport;
    if (disposeReport == null ||
        disposeReport.playerError != null ||
        disposeReport.coordinatorError != null) {
      throw StateError('Player or output disposal did not complete safely');
    }
    debugPrint('DIAG_SCOPE_PAGE_EXIT stop complete');
  }

  @override
  Widget build(BuildContext context) {
    final displayController = Platform.isAndroid && _androidHdrTransaction
        ? _hdrOutputSlot.current
        : _initialController;
    final diagnosticVideoKey = displayController == null
        ? null
        : GlobalObjectKey<VideoState>(displayController);
    final videoKey =
        (_androidP5PlatformSdrDiagnostic || _androidP5ScopeFullscreen)
            ? diagnosticVideoKey
            : ObjectKey(displayController);
    if (Platform.isAndroid && _androidPreopenFullscreen) {
      final page = Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            if (displayController != null)
              Video(
                key: videoKey,
                controller: displayController,
                fill: Colors.black,
                controls: null,
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
                              'StartFirstFrameProbe');
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
                              child: displayController == null
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
                  displayController == null
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
