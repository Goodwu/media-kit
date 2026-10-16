import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/src/hdr/hdr_capabilities.dart';
import 'package:media_kit_video/src/hdr/hdr_open_plan.dart';
import 'package:media_kit_video/src/hdr/hdr_output_slot.dart';
import 'package:media_kit_video/src/hdr/hdr_output_contract.dart';
import 'package:media_kit_video/src/hdr/hdr_player_backend.dart';
import 'package:media_kit_video/src/hdr/hdr_route.dart';
import 'package:media_kit_video/src/hdr/hdr_source_descriptor.dart';
import 'package:media_kit_video/src/hdr/hdr_strategy.dart';
import 'package:media_kit_video/src/video_controller/video_controller.dart';
import 'package:media_kit_video/src/video_controller/platform_video_controller.dart';
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
    final result = await _exercise(initial: 'no', softwareFallback: 'no');
    await result.backend.prepareOutput(_plan('no'));
    await result.backend.prepareOutput(_plan('auto'));
    await result.backend.resetOwnedConfiguration();
    expect(result.player.properties['hwdec'], 'no');
    expect(result.player.properties['hwdec-software-fallback'], 'no');
  });

  test(
      'backend writes exactly the contract handed to creation and preserves EGL baseline',
      () async {
    final result =
        await _exercise(initial: 'no', gpu: true, pixelFormat: 'rgba8888');
    expect(result.error, isNull);
    final contract = result.creationContract!;
    expect(result.creationSaw, contract.requestedHwdec);
    expect(result.creationEgl, contract.eglOutputFormat);
    expect(contract.surfacePixelFormat, 'rgba8888');
    expect(contract.surfaceTransfer, 'pq-itu');
    expect(contract.offscreenTransfer, 'pq-full');
    final projection =
        contract.controllerConfiguration(const VideoControllerConfiguration());
    expect(projection.vo, contract.vo);
    expect(projection.hwdec, contract.requestedHwdec);
    expect(projection.android.gpuApi, contract.gpuApi);
    expect(projection.android.surfacePixelFormat, contract.surfacePixelFormat);
    expect(projection.android.surfaceTransfer, contract.surfaceTransfer);
    await result.backend.resetOwnedConfiguration();
    expect(result.player.properties['egl-output-format'], 'rgba8');
    expect(result.player.properties['hwdec'], 'no');
  });

  test('first output preparation owns hwdec-software-fallback as 8', () async {
    final result = await _exercise(initial: 'no');
    expect(result.error, isNull);
    expect(result.player.properties['hwdec-software-fallback'], '8');
    // MapEntry has no structural equality; match on key/value instead.
    expect(
        result.player.setPropertyCalls
            .any((call) => call.key == 'hwdec-software-fallback'),
        isTrue);
    expect(
        result.player.setPropertyCalls
            .firstWhere((call) => call.key == 'hwdec-software-fallback')
            .value,
        '8');
    // Owned strictly before the controller is created, like `hwdec`.
    expect(result.creationSawSoftwareFallback, '8');
  });

  test('resetOwnedConfiguration restores the captured hwdec-software-fallback',
      () async {
    final result = await _exercise(initial: 'no');
    expect(result.player.properties['hwdec-software-fallback'], '8');
    await result.backend.resetOwnedConfiguration();
    expect(result.player.properties['hwdec-software-fallback'], '3');
  });

  test(
      'resetOwnedConfiguration restores a caller-set hwdec-software-fallback',
      () async {
    final result = await _exercise(initial: 'no', softwareFallback: 'no');
    expect(result.player.properties['hwdec-software-fallback'], '8');
    await result.backend.resetOwnedConfiguration();
    expect(result.player.properties['hwdec-software-fallback'], 'no');
  });

  test('hwdec-software-fallback rejection fails preparation before creation',
      () async {
    final result = await _exercise(
        initial: 'no',
        readbackOverrides: const {'hwdec-software-fallback': 'no'});
    expect(result.error, isA<StateError>());
    expect((result.error as StateError).message,
        contains('hwdec-software-fallback rejected: requested=8 actual=no'));
    expect(result.creationSaw, isNull);
    expect(result.creationSawSoftwareFallback, isNull);
  });

  test('empty hwdec-software-fallback baseline refuses controller creation',
      () async {
    final result = await _exercise(initial: 'no', softwareFallback: '');
    expect(result.error, isA<StateError>());
    expect(result.creationSaw, isNull);
    expect(result.creationSawSoftwareFallback, isNull);
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
  bool gpu = false,
  String pixelFormat = 'rgba1010102',
  String softwareFallback = '3',
  Map<String, String>? readbackOverrides,
}) async {
  final player = _FakePlayer(initial,
      readError: readError,
      softwareFallback: softwareFallback,
      readbackOverrides: readbackOverrides);
  String? creationSaw;
  String? creationEgl;
  String? creationSawSoftwareFallback;
  HdrOutputContract? creationContract;
  final slot = HdrOutputSlot<VideoController>(
    initial: null,
    voOf: (output) async => (output as _FakeController).contract.vo,
    disposeForRebuild: (_) async {},
    create: (contract) {
      creationSaw = player.properties['hwdec'];
      creationEgl = player.properties['egl-output-format'];
      creationSawSoftwareFallback =
          player.properties['hwdec-software-fallback'];
      creationContract = contract;
      return _FakeController(contract);
    },
    publish: (_) {},
    waitReady: (output) async {
      // AndroidController initialization applies its creation-time hwdec.
      player.properties['hwdec'] =
          (output as _FakeController).contract.requestedHwdec;
      if (readyError != null) throw readyError;
    },
  );
  final backend = AndroidHdrBackend(
      player: player,
      outputSlot: slot,
      surfacePixelFormatOverride: pixelFormat,
      applyDataSpace: (_, __) async => null);
  Object? error;
  try {
    await backend.prepareOutput(_plan('mediacodec', gpu: gpu));
  } catch (e) {
    error = e;
  }
  return _Exercise(player, backend, creationSaw, error, creationContract,
      creationEgl, creationSawSoftwareFallback);
}

HdrOpenPlan _plan(String hwdec, {bool gpu = false}) {
  const source = HdrSourceDescriptor(codec: 'h264');
  final route = HdrRoute(
    strategy: HdrStrategy.sdrDirect,
    presentation: HdrPresentation.sdr,
    outputTransfer: HdrOutputTransfer.sdr,
    appliesDynamicMetadata: false,
    topology: HdrTopology.platformView,
    vo: gpu ? 'gpu-next' : 'mediacodec_embed',
    hwdec: hwdec,
    targetPrim: null,
    targetTrc: null,
    surfaceTransfer: gpu ? 'pq-itu' : null,
    offscreenTransfer: gpu ? 'pq-full' : null,
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
  _FakePlayer(String hwdec,
      {this.readError,
      String softwareFallback = '3',
      Map<String, String>? readbackOverrides})
      : properties = {
          'hwdec': hwdec,
          'egl-output-format': 'rgba8',
          // mpv's actual default for --hwdec-software-fallback.
          'hwdec-software-fallback': softwareFallback,
        },
        _readbackOverrides = readbackOverrides;
  final Map<String, String> properties;
  final Object? readError;
  final Map<String, String>? _readbackOverrides;
  final List<MapEntry<String, String>> setPropertyCalls = [];
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
    final overridden = _readbackOverrides?[name];
    if (overridden != null) return overridden;
    return properties[name] ?? '';
  }

  @override
  Future<void> setPropertyStrict(String name, String value,
      {bool waitForInitialization = true}) async {
    setPropertyCalls.add(MapEntry(name, value));
    properties[name] = value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeController implements VideoController {
  _FakeController(this.contract);
  final HdrOutputContract contract;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Exercise {
  const _Exercise(this.player, this.backend, this.creationSaw, this.error,
      this.creationContract, this.creationEgl, this.creationSawSoftwareFallback);
  final _FakePlayer player;
  final AndroidHdrBackend backend;
  final String? creationSaw;
  final Object? error;
  final HdrOutputContract? creationContract;
  final String? creationEgl;
  final String? creationSawSoftwareFallback;
}
