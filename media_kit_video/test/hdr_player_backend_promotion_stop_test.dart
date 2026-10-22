import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit/src/player/native/utils/source_transition_gate.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:media_kit_video/src/hdr/hdr_player_backend.dart';
import 'package:media_kit_video/src/hdr/hdr_native_dv_option_owner.dart';
import 'package:media_kit_video/src/video_controller/android_video_controller/android_video_controller.dart';
import 'package:media_kit_video/src/video_controller/android_video_controller/platform_surface_release.dart';
import 'package:synchronized/synchronized.dart';

class _Streams implements PlayerStream {
  @override
  Stream<VideoParams> get videoParams => const Stream.empty();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Player implements Player {
  final properties = <String, String>{
    'path': '',
    'playlist/0/id': '',
    'playlist/0/filename': '',
    'options/track-auto-selection': 'yes',
    'options/lavfi-complex': '',
    'options/demuxer-cache-wait': 'no',
    'options/rebase-start-time': 'yes',
    'options/play-dir': 'forward',
    'options/vid': 'auto',
    'options/aid': 'auto',
    'options/sid': 'no',
    'options/secondary-sid': 'no',
    'pause': 'yes',
    'time-pos/full': '30.0',
    'vid': 'no',
    'aid': 'no',
    'sid': 'no',
    'secondary-sid': 'no',
    'track-list/count': '0',
    'vd-lavc-o': '',
    'mediacodec-embed-render-mode': 'boolean',
    'hwdec': 'no',
    'hwdec-software-fallback': '8',
    'cache-on-disk': 'yes',
    'target-colorspace-hint': 'auto',
    'tone-mapping': 'clip',
    'mediakit-container-probe-seek-ready': 'no',
    'mediakit-container-probe-seek-target': '',
  };
  @override
  final lock = Lock();
  late final sourceGate = NativeSourceTransitionGate(lock);
  @override
  Future<T> runSourceTransition<T>(Future<T> Function() body) =>
      sourceGate.run(body);
  @override
  final stream = _Streams();
  @override
  int fileLoadedEpoch = 4;
  int stopCalls = 0;
  int openCalls = 0;
  int nextEntry = 7;
  bool stopAckError = false;
  bool failRestoreAck = false;
  bool failRetirementRead = false;
  bool failRemainingRestoreAck = false;
  bool admissionClosed = false;
  @override
  bool disposed = false;
  bool pairWasRestoredAtDispose = false;
  void Function()? closeAdmission;
  int seekCalls = 0;
  final writes = <String>[];
  Map<String, String>? backups;

  @override
  Future<String> getPropertyAsync(String name,
          {bool waitForInitialization = true}) async =>
      properties[name] ?? '';

  @override
  Future<List<String>> getPropertiesAsync(List<String> names,
      {bool waitForInitialization = true}) async {
    if (failRetirementRead &&
        properties['path']!.isEmpty &&
        properties['vd-lavc-o']!.isEmpty &&
        properties['mediacodec-embed-render-mode'] == 'boolean' &&
        names.contains('path')) {
      failRetirementRead = false;
      throw StateError('retirement read acknowledgement lost');
    }
    return names.map((name) => properties[name] ?? '').toList();
  }

  @override
  Future<void> setPropertyStrict(String name, String value,
      {bool waitForInitialization = true}) async {
    writes.add('$name=$value');
    properties[name] = value;
    if (name == 'time-pos') {
      properties['mediakit-container-probe-seek-ready'] = 'yes';
      properties['mediakit-container-probe-seek-target'] = value;
    }
    if (failRemainingRestoreAck && name == 'cache-on-disk' && value == 'yes') {
      failRemainingRestoreAck = false;
      throw StateError('remaining restore acknowledgement lost');
    }
    if (failRestoreAck &&
        name == 'mediacodec-embed-render-mode' &&
        value == 'boolean') {
      failRestoreAck = false;
      throw StateError('restore acknowledgement lost');
    }
  }

  void _submit(Media media, {required bool probe}) {
    openCalls++;
    if (backups != null) properties.addAll(backups!);
    backups = {
      for (final key in [
        'options/track-auto-selection',
        'options/vid',
        'options/aid',
        'options/sid',
        'options/secondary-sid',
      ])
        key: properties[key]!,
    };
    properties.addAll({
      'path': media.uri,
      'playlist/0/filename': media.uri,
      'playlist/0/id': '${nextEntry++}',
      'track-list/count': '1',
      'track-list/0/id': '1',
      'track-list/0/type': 'video',
      'track-list/0/selected': 'no',
      'track-list/0/main-selection': '',
      'options/track-auto-selection': probe ? 'no' : 'yes',
    });
    fileLoadedEpoch++;
  }

  @override
  Future<void> openContainerProbe(Playable playable,
      {bool synchronized = true, bool automaticSubtitles = true}) async {
    Future<void> operation() async {
      _submit(playable as Media, probe: true);
      properties['options/sid'] = automaticSubtitles ? 'auto' : 'no';
    }

    await sourceGate.schedule(NativeSourceOperation.open, operation,
        synchronized: synchronized);
  }

  @override
  Future<void> open(Playable playable,
      {bool play = true, bool synchronized = true}) async {
    Future<void> operation() async => _submit(playable as Media, probe: false);
    await sourceGate.schedule(NativeSourceOperation.open, operation,
        synchronized: synchronized);
  }

  @override
  Future<void> stop(
      {bool open = false,
      bool notify = true,
      bool synchronized = true,
      bool waitForVideoControllerInitialization = true}) async {
    Future<void> operation() async {
      stopCalls++;
      properties.addAll({
        'path': '',
        'playlist/0/id': '',
        'playlist/0/filename': '',
        'track-list/count': '0',
      });
      if (backups != null) properties.addAll(backups!);
      if (stopAckError) {
        stopAckError = false;
        throw StateError('native stop acknowledgement lost');
      }
    }

    await sourceGate.schedule(NativeSourceOperation.stop, operation,
        synchronized: synchronized);
  }

  @override
  Future<FileLoadedRecord> waitForFileLoadedEntryAfter(int id, int epoch,
          {Duration? timeout}) async =>
      FileLoadedRecord(fileLoadedEpoch, id);

  @override
  Future<void> seek(Duration position, {bool synchronized = true}) =>
      sourceGate.schedule(NativeSourceOperation.seek, () async {
        seekCalls++;
        properties['time-pos/full'] =
            (position.inMicroseconds / Duration.microsecondsPerSecond)
                .toString();
      }, synchronized: synchronized);

  @override
  Future<void> dispose({bool synchronized = true}) {
    sourceGate.closeAdmission(() {
      admissionClosed = true;
      closeAdmission?.call();
    });
    return sourceGate.schedule(NativeSourceOperation.dispose, () async {
      pairWasRestoredAtDispose = properties['vd-lavc-o']!.isEmpty &&
          properties['mediacodec-embed-render-mode'] == 'boolean';
      disposed = true;
    }, synchronized: synchronized);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Platform implements PlatformVideoController {
  @override
  final configuration = const VideoControllerConfiguration(vo: 'gpu-next');
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Controller implements VideoController {
  _Controller([PlatformVideoController? output]) {
    final actual = output ?? _Platform();
    platform.complete(actual);
    notifier.value = actual;
  }
  @override
  final platform = Completer<PlatformVideoController>();
  @override
  final notifier = ValueNotifier<PlatformVideoController?>(null);
  @override
  Future<bool> prepareAndroidTextureOutput() async => true;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NativePlatform implements AndroidVideoController {
  _NativePlatform(this.player, this.configuration);
  @override
  final _Player player;
  @override
  final VideoControllerConfiguration configuration;
  @override
  final currentBoundOutputIdentity = const AndroidSurfaceAccountId(
      handle: 1, generation: 2, viewId: 3, surfaceGeneration: 4, wid: 5);
  @override
  Future<void> get waitUntilCurrentOutputBound async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// Surface callbacks are faked; the backend, slot, source gate, both owners and
// every capture/cleanup operation execute their production implementation.
class _Backend extends AndroidHdrBackend {
  _Backend(_Player player,
      {Future<void> Function(String stage)? atOutput, bool Function()? current})
      : super(
            player: player,
            outputSlot: _slot(player, atOutput),
            reviewIsCurrent: (_) => current?.call() ?? true);

  static HdrOutputSlot<VideoController> _slot(
          _Player player, Future<void> Function(String stage)? atOutput) =>
      HdrOutputSlot(
          initial: _Controller(),
          voOf: (controller) async {
            await atOutput?.call('old-inspect');
            return (await controller.platform.future).configuration.vo!;
          },
          disposeForRebuild: (_) async {
            await atOutput?.call('old-dispose');
            await player.setPropertyStrict('vo', 'null');
          },
          create: (contract) => _Controller(_NativePlatform(
              player,
              contract.controllerConfiguration(
                  const VideoControllerConfiguration()))),
          publish: (_) {},
          waitReady: (controller) async {
            await atOutput?.call('new-init');
            final output = await controller.platform.future;
            await player.setPropertyStrict('vo', output.configuration.vo!);
            await atOutput?.call('new-bind');
            if (player.properties['path']!.isEmpty) return;
            // Native binding can need an ordinary seek while source admission is
            // held. It must remain runnable without reentering that gate.
            await player.seek(const Duration(seconds: 30));
            player.properties.addAll({
              'vid': '1',
              'current-tracks/video/id': '1',
              'current-tracks/video/selected': 'yes',
              'current-tracks/video/main-selection': '0',
              'track-list/0/selected': 'yes',
              'track-list/0/main-selection': '0',
              'track-list/0/decoder': 'mediacodec',
            });
          });
}

HdrOpenPlan _plan(Media media, {bool native = false}) {
  final facts = HdrSourceFacts.fromHint(null).observe(
      codec: 'hevc',
      dolbyVisionProfile: 8,
      dvCompatibilityId: 4,
      dvElPresent: false,
      inferSourceColorFromDecoder: false);
  final source = native ? facts.source : const HdrSourceDescriptor();
  final route = HdrRoute(
    strategy: native ? HdrStrategy.nativeDolbyVision : HdrStrategy.sdrDirect,
    presentation:
        native ? HdrPresentation.nativeDolbyVision : HdrPresentation.sdr,
    outputTransfer:
        native ? HdrOutputTransfer.dolbyVision : HdrOutputTransfer.sdr,
    appliesDynamicMetadata: native,
    topology: native ? HdrTopology.platformView : HdrTopology.texture,
    vo: native ? 'mediacodec_embed' : 'gpu-next',
    hwdec: 'mediacodec',
    targetPrim: null,
    targetTrc: null,
    surfaceTransfer: null,
    stripDvRpu: false,
    vdLavcOptions: native ? 'native_dv=1' : null,
    mediacodecEmbedRenderMode: native ? 'timed' : null,
  );
  final candidate = HdrCandidate(
      strategy: route.strategy,
      maturity: HdrStrategyMaturity.verified,
      feasible: true,
      route: route);
  return HdrOpenPlan(
      media: media,
      source: source,
      sourceFacts: native ? facts : null,
      sourceOrigin: native ? HdrReportSource.decoder : null,
      capabilities: const HdrCapabilities(
          sdkInt: 35,
          displayHdrTypes: {1, 2, 3},
          hevcDecoders: [],
          dolbyVisionDecoders: [],
          p5PipelineAvailable: true,
          dataSpaceBridgeLoaded: true,
          dataSpaceExt: null),
      prediction: HdrRoutePrediction(
          source: source,
          selected: candidate,
          candidates: [candidate],
          presentation: route.presentation,
          confidence: HdrPredictionConfidence.verified,
          playable: true),
      route: route);
}

Future<(_Player, _Backend, HdrOpenPlan, HdrOpenPlan)> _prepared({
  Future<void> Function(String stage)? atOutput,
  bool Function()? current,
  bool configureInitial = false,
  Duration? rawStart = const Duration(seconds: 30),
  String seekCapability = 'no',
}) async {
  final player = _Player();
  player.properties['mediakit-container-probe-seek-ready'] = seekCapability;
  final backend = _Backend(player, atOutput: atOutput, current: current);
  final media = Media('file:///source.mkv', start: rawStart);
  final old = _plan(media);
  final next = _plan(media, native: true);
  await backend.stop();
  if (configureInitial) {
    await backend.prepareOutput(old);
    await backend.configure(old);
    await backend.waitForOutput(old);
  }
  await backend.prepareSourceDiscovery(old);
  await backend.open(old, play: false);
  expect(await backend.canPromoteDiscoveredSource(old, next),
      const ['yes', 'no'].contains(seekCapability));
  return (player, backend, old, next);
}

Future<(_Player, _Backend)> _promoted() async {
  final (player, backend, old, next) = await _prepared();
  await backend.promoteDiscoveredSource(old, next);
  expect(player.properties['vd-lavc-o'], 'native_dv=1');
  return (player, backend);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final start in <Duration?>[
    const Duration(seconds: 85),
    Duration.zero,
    null,
    const Duration(hours: 3),
  ]) {
    test(
        'actual backend arms $start before output setup and selector activation',
        () async {
      _Player? active;
      final snapshots = <Map<String, String>>[];
      final earlySeeks = <List<String>>[];
      final (player, backend, old, next) = await _prepared(
          rawStart: start,
          atOutput: (stage) async {
            if (stage != 'old-inspect') return;
            final player = active!;
            // voOf errors are intentionally swallowed by HdrOutputSlot.
            // Record here and assert outside that production catch boundary.
            snapshots.add(Map.of(player.properties));
            earlySeeks.add(player.writes
                .where((entry) => entry.startsWith('time-pos='))
                .toList());
          });
      active = player;
      await backend.promoteDiscoveredSource(old, next);
      expect(snapshots, hasLength(1));
      expect(snapshots.single['options/track-auto-selection'], 'no');
      expect(snapshots.single['vid'], 'no');
      expect(snapshots.single['track-list/0/selected'], 'no');
      expect(snapshots.single['vd-lavc-o'], 'native_dv=1');
      expect(
          earlySeeks.single,
          start == null
              ? <String>[]
              : ['time-pos=${start.inMilliseconds / 1000.0}']);
      expect(
          player.writes.where((entry) => entry.startsWith('time-pos=')),
          start == null
              ? <String>[]
              : ['time-pos=${start.inMilliseconds / 1000.0}']);
      await backend.stop();
      await backend.resetOwnedConfiguration();
      await backend.dispose();
    });
  }

  for (final capability in ['', 'unsupported', 'true']) {
    test(
        'actual backend preserves ordinary reopen without seek capability $capability',
        () async {
      final (player, backend, old, next) =
          await _prepared(seekCapability: capability);
      expect(await backend.canPromoteDiscoveredSource(old, next), isFalse);
      expect(player.writes, isEmpty);
      // This is the existing coordinator fallback transaction. The native
      // route reopens normally instead of applying a same-entry promotion.
      await backend.stop();
      await backend.resetOwnedConfiguration();
      await backend.prepareOutput(next);
      await backend.configure(next);
      await backend.waitForOutput(next);
      await backend.open(next, play: false);
      expect(player.openCalls, 2);
      expect(player.writes.where((entry) => entry.startsWith('time-pos=')),
          isEmpty);
      await backend.stop();
      await backend.resetOwnedConfiguration();
      await backend.dispose();
    });
  }

  test(
      'actual backend preserves a completed stop after an acknowledgement error',
      () async {
    final (player, backend) = await _promoted();
    player.stopAckError = true;
    await expectLater(backend.stop(), throwsStateError);
    expect(player.stopCalls, 2); // Initial empty stop, then this owned entry.
    expect(player.properties['path'], isEmpty);
    expect(player.properties['vd-lavc-o'], '');
    await backend.stop();
    await backend.resetOwnedConfiguration();
    final writes = List.of(player.writes);
    await backend.stop();
    expect(player.stopCalls, 2);
    expect(player.writes, writes);
    await backend.dispose();
  });

  for (final uri in ['file:///foreign.mkv', 'file:///source.mkv']) {
    test('actual backend never stops replacement $uri after ack-error cleanup',
        () async {
      final (player, backend) = await _promoted();
      player.stopAckError = true;
      await expectLater(backend.stop(), throwsStateError);
      final foreign = Media(uri);
      await player.open(foreign); // Default Player.lock serialization.
      final entry = player.properties['playlist/0/id'];
      final writes = List.of(player.writes);
      Object? stopError;
      try {
        await backend.stop();
      } catch (error) {
        stopError = error;
      }
      expect(player.stopCalls, 2,
          reason: 'must not issue a stop for replacement');
      expect(stopError, isA<StateError>());
      await expectLater(backend.resetOwnedConfiguration(), throwsStateError);
      expect(player.stopCalls, 2);
      expect(player.properties['path'], foreign.uri);
      expect(player.properties['playlist/0/id'], entry);
      expect(player.writes, writes);
      await backend.dispose();
    });
  }

  for (final failure in ['restore', 'retirement']) {
    test('actual backend retries $failure without issuing another native stop',
        () async {
      final (player, backend) = await _promoted();
      if (failure == 'restore') player.failRestoreAck = true;
      if (failure == 'retirement') player.failRetirementRead = true;
      await expectLater(backend.stop(), throwsA(isA<Exception>()));
      expect(player.stopCalls, 2);
      await backend.stop();
      await backend.resetOwnedConfiguration();
      expect(player.stopCalls, 2);
      expect(player.properties['vd-lavc-o'], '');
      expect(player.properties['mediacodec-embed-render-mode'], 'boolean');
      await backend.dispose();
    });
  }

  test('actual backend consumes completed proof only when new open is admitted',
      () async {
    final (player, backend) = await _promoted();
    await backend.stop();
    await backend.resetOwnedConfiguration();
    expect(player.stopCalls, 2);
    final next = _plan(Media('file:///managed-next.mkv'));
    await backend.open(next, play: false);
    expect(player.properties['path'], next.media.uri);
    await backend.stop();
    await backend.resetOwnedConfiguration();
    expect(player.stopCalls, 3);
    expect(player.properties['path'], isEmpty);
    await backend.dispose();
  });

  for (final stage in ['old-inspect', 'old-dispose', 'new-init', 'new-bind']) {
    for (final fail in stage == 'old-inspect' ? [false] : [false, true]) {
      test('actual backend gates foreign open during $stage (failure=$fail)',
          () async {
        final entered = Completer<void>();
        final released = Completer<void>();
        final (player, backend, old, next) =
            await _prepared(atOutput: (actual) async {
          if (actual != stage) return;
          if (!entered.isCompleted) entered.complete();
          await released.future;
          if (fail) throw StateError('output stage failed: $stage');
        });
        final promoting = backend.promoteDiscoveredSource(old, next);
        final outcome =
            expectLater(promoting, fail ? throwsStateError : completes);
        await entered.future;
        final foreign = Media('file:///foreign.mkv');
        final opening = player.open(foreign);
        await pumpEventQueue();
        expect(player.openCalls, 1);
        expect(player.properties['path'], old.media.uri);
        released.complete();
        await outcome.timeout(const Duration(seconds: 2));
        await opening;
        expect(player.properties['path'], foreign.uri);
        if (fail) {
          expect(player.properties['vd-lavc-o'], '');
          expect(player.properties['mediacodec-embed-render-mode'], 'boolean');
          expect(player.stopCalls, 2);
        } else {
          expect(player.seekCalls, 1, reason: 'bind seek must not deadlock');
        }
        final stops = player.stopCalls;
        final writes = List.of(player.writes);
        await expectLater(backend.stop(), throwsStateError);
        await expectLater(backend.resetOwnedConfiguration(),
            throwsA(anyOf(isA<StateError>(), isA<HdrNativeDvOptionFailure>())));
        expect(player.stopCalls, stops);
        expect(player.writes, writes);
        expect(player.properties['path'], foreign.uri);
        await backend.dispose();
      });
    }
  }

  test('promotion rejection before native acquisition retains probe stop proof',
      () async {
    final (player, backend, old, next) = await _prepared();
    player.properties['vd-lavc-o'] = 'external=1';
    await expectLater(
        backend.promoteDiscoveredSource(old, next), throwsA(isA<Exception>()));
    expect(player.stopCalls, 2);
    expect(player.properties['path'], isEmpty);
    expect(player.properties['vd-lavc-o'], 'external=1');
    expect(player.writes, isEmpty);
    final foreign = Media('file:///foreign.mkv');
    await player.open(foreign);
    await expectLater(backend.stop(), throwsStateError);
    await expectLater(backend.resetOwnedConfiguration(), throwsStateError);
    expect(player.stopCalls, 2);
    expect(player.properties['path'], foreign.uri);
    expect(player.writes, isEmpty);
    await backend.dispose();
  });

  for (final uri in ['file:///foreign.mkv', 'file:///source.mkv']) {
    test('pre-acquire stop ack and remaining restore failure protect $uri',
        () async {
      // The initial SDR attempt really owns properties. The subsequent
      // restore failure occurs after probe retirement, rather than testing
      // an empty restoration loop.
      final (player, backend, old, next) =
          await _prepared(configureInitial: true);
      expect(player.properties['cache-on-disk'], 'no');
      expect(player.properties['hwdec'], 'mediacodec');
      player.properties['vd-lavc-o'] = 'external=1';
      player.stopAckError = true;
      await expectLater(backend.promoteDiscoveredSource(old, next),
          throwsA(isA<HdrNativeDvOptionFailure>()));
      expect(player.stopCalls, 2);
      expect(player.properties['path'], isEmpty);

      // The old probe's private own-stop proof confirms this retry. Its
      // retirement then succeeds, but a later owned configuration setter
      // applies its baseline and loses the acknowledgement.
      player.failRemainingRestoreAck = true;
      await backend.stop();
      await expectLater(
          backend.resetOwnedConfiguration(),
          throwsA(isA<StateError>().having((e) => e.message, 'message',
              contains('remaining restore acknowledgement lost'))));
      expect(player.properties['cache-on-disk'], 'yes');
      expect(player.stopCalls, 2);

      final foreign = Media(uri);
      await player.open(foreign);
      final entry = player.properties['playlist/0/id'];
      final writes = List.of(player.writes);
      Object? stopError;
      try {
        await backend.stop();
      } catch (error) {
        stopError = error;
      }
      expect(player.stopCalls, 2,
          reason: 'retiring the probe must not erase its completed stop proof');
      expect(stopError, isA<StateError>());
      await expectLater(backend.resetOwnedConfiguration(), throwsStateError);
      expect(player.properties['path'], foreign.uri);
      expect(player.properties['playlist/0/id'], entry);
      expect(player.writes, writes,
          reason: 'foreign output must not be detached');
      await backend.dispose();
    });
  }

  test(
      'queued player disposal cancels admission before awaiting promotion cleanup',
      () async {
    final entered = Completer<void>();
    final released = Completer<void>();
    var current = true;
    final (player, backend, old, next) = await _prepared(
        current: () => current,
        atOutput: (stage) async {
          if (stage != 'new-bind') return;
          entered.complete();
          await released.future;
        });
    final promotion = backend.promoteDiscoveredSource(old, next);
    final outcome = expectLater(promotion, throwsA(isA<Exception>()));
    await entered.future;
    player.closeAdmission = () => current = false;
    final disposing = player.dispose();
    expect(player.admissionClosed, isTrue);
    expect(current, isFalse);
    expect(player.disposed, isFalse);
    released.complete();
    await outcome.timeout(const Duration(seconds: 2));
    await disposing;
    expect(player.disposed, isTrue);
    expect(player.pairWasRestoredAtDispose, isTrue);
    expect(player.stopCalls, 2);
    await backend.dispose();
  });
}
