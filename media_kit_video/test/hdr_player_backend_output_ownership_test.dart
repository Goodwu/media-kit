import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/src/hdr/hdr_capabilities.dart';
import 'package:media_kit_video/src/hdr/hdr_open_plan.dart';
import 'package:media_kit_video/src/hdr/hdr_output_slot.dart';
import 'package:media_kit_video/src/hdr/hdr_player_backend.dart';
import 'package:media_kit_video/src/hdr/hdr_route.dart';
import 'package:media_kit_video/src/hdr/hdr_source_descriptor.dart';
import 'package:media_kit_video/src/hdr/hdr_strategy.dart';
import 'package:media_kit_video/src/video_controller/video_controller.dart';
import 'package:synchronized/synchronized.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('captures hwdec before controller creation and restores its baseline',
      () async {
    final result = await _exercise(initial: 'no');
    expect(result.player.properties['hwdec'], 'mediacodec');
    expect(result.creationSaw, 'mediacodec');
    await result.backend.resetOwnedConfiguration();
    expect(result.player.properties['hwdec'], 'no');
  });

  test('output readiness failure still leaves hwdec owned for restoration',
      () async {
    final result =
        await _exercise(initial: 'no', readyError: StateError('not ready'));
    expect(result.player.properties['hwdec'], 'mediacodec');
    await result.backend.resetOwnedConfiguration();
    expect(result.player.properties['hwdec'], 'no');
  });

  test('same route and later route do not replace the captured baseline',
      () async {
    final result = await _exercise(initial: 'no');
    await result.backend.prepareOutput(_plan('no'));
    await result.backend.prepareOutput(_plan('auto'));
    await result.backend.resetOwnedConfiguration();
    expect(result.player.properties['hwdec'], 'no');
  });

  test('empty baseline refuses controller creation', () async {
    final result = await _exercise(initial: '');
    expect(result.error, isA<StateError>());
    expect(result.creationSaw, isNull);
  });

  test('baseline read failure refuses controller creation', () async {
    final result =
        await _exercise(initial: 'no', readError: StateError('read failed'));
    expect(result.error, isA<StateError>());
    expect(result.creationSaw, isNull);
  });
}

Future<_Exercise> _exercise({
  required String initial,
  Object? readyError,
  Object? readError,
}) async {
  final player = _FakePlayer(initial, readError: readError);
  String? creationSaw;
  final slot = HdrOutputSlot<VideoController>(
    initial: null,
    voOf: (_) async => 'gpu-next',
    disposeForRebuild: (_) async {},
    create: (vo, hwdec, transfer) {
      creationSaw = player.properties['hwdec'];
      return _FakeController();
    },
    publish: (_) {},
    waitReady: (_) async {
      // AndroidController initialization applies its creation-time hwdec.
      player.properties['hwdec'] = 'mediacodec';
      if (readyError != null) throw readyError;
    },
  );
  final backend = AndroidHdrBackend(
      player: player, outputSlot: slot, applyDataSpace: (_, __) async => null);
  Object? error;
  try {
    await backend.prepareOutput(_plan('mediacodec'));
  } catch (e) {
    error = e;
  }
  return _Exercise(player, backend, creationSaw, error);
}

HdrOpenPlan _plan(String hwdec) {
  const source = HdrSourceDescriptor(codec: 'h264');
  final route = HdrRoute(
    strategy: HdrStrategy.sdrDirect,
    presentation: HdrPresentation.sdr,
    outputTransfer: HdrOutputTransfer.sdr,
    appliesDynamicMetadata: false,
    topology: HdrTopology.platformView,
    vo: 'mediacodec_embed',
    hwdec: hwdec,
    targetPrim: null,
    targetTrc: null,
    surfaceTransfer: null,
    stripDvRpu: false,
  );
  final candidate = HdrCandidate(
    strategy: HdrStrategy.sdrDirect,
    maturity: HdrStrategyMaturity.verified,
    feasible: true,
    route: route,
  );
  return HdrOpenPlan(
    media: Media('test://source'),
    source: source,
    sourceOrigin: null,
    capabilities: const HdrCapabilities(
      sdkInt: 24,
      displayHdrTypes: {},
      hevcDecoders: [],
      dolbyVisionDecoders: [],
      p5PipelineAvailable: false,
      dataSpaceBridgeLoaded: false,
      dataSpaceExt: null,
    ),
    prediction: HdrRoutePrediction(
      source: source,
      selected: candidate,
      candidates: [candidate],
      presentation: HdrPresentation.sdr,
      confidence: HdrPredictionConfidence.verified,
      playable: true,
    ),
    route: route,
  );
}

class _FakePlayer implements Player {
  _FakePlayer(String hwdec, {this.readError}) : properties = {'hwdec': hwdec};
  final Map<String, String> properties;
  final Object? readError;
  final Lock _lock = Lock();
  final PlayerStream _stream = PlayerStream(
      Stream.empty(),
      Stream.empty(),
      Stream.empty(),
      Stream.empty(),
      Stream.empty(),
      Stream.empty(),
      Stream.empty(),
      Stream.empty(),
      Stream.empty(),
      Stream.empty(),
      Stream.empty(),
      Stream.empty(),
      Stream.empty(),
      Stream.empty(),
      Stream.empty(),
      Stream.empty(),
      Stream.empty(),
      Stream.empty(),
      Stream.empty(),
      Stream.empty(),
      Stream.empty(),
      Stream.empty(),
      Stream.empty(),
      Stream.empty(),
      Stream.empty(),
      Stream.empty());
  @override
  PlayerStream get stream => _stream;
  @override
  Lock get lock => _lock;
  @override
  int get fileLoadedEpoch => 0;
  @override
  Future<String> getProperty(String name,
      {bool waitForInitialization = true}) async {
    if (readError != null) throw readError!;
    return properties[name] ?? '';
  }

  @override
  Future<void> setPropertyStrict(String name, String value,
      {bool waitForInitialization = true}) async {
    properties[name] = value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeController implements VideoController {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Exercise {
  const _Exercise(this.player, this.backend, this.creationSaw, this.error);
  final _FakePlayer player;
  final AndroidHdrBackend backend;
  final String? creationSaw;
  final Object? error;
}
