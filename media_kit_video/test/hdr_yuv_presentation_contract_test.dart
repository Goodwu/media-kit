import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/src/hdr/hdr_capabilities.dart';
import 'package:media_kit_video/src/hdr/hdr_open_plan.dart';
import 'package:media_kit_video/src/hdr/hdr_output_slot.dart';
import 'package:media_kit_video/src/hdr/hdr_player_backend.dart';
import 'package:media_kit_video/src/hdr/hdr_route.dart';
import 'package:media_kit_video/src/hdr/hdr_source_descriptor.dart';
import 'package:media_kit_video/src/hdr/hdr_strategy.dart';
import 'package:media_kit_video/src/hdr/hdr_yuv_presentation_contract.dart';
import 'package:media_kit_video/src/hdr/hdr_yuv_window_arm.dart';
import 'package:media_kit_video/src/video_controller/platform_video_controller.dart';
import 'package:media_kit_video/src/video_controller/video_controller.dart';
import 'package:synchronized/synchronized.dart';

/// A4 contract split, tightened by the P8.4 A5 V2 review fix: the YUV
/// window route's presentation quad (offscreen full-PQ / NV12 limited window
/// content / vendor-forced 0x11C60000 window label / (9,1,16) metadata
/// triplet) is fail-closed in the main library path, the YUV shape is judged
/// by the `surfacetexture` carrier (both `pq` and `pq-itu` requests enter
/// the contract — the vendor forces the same window label for either in
/// yuvDiag mode), the offscreen contract is issued as the owned mpv
/// output-levels write, and routes off the carrier keep their default
/// routing.
void main() {
  // The process-level lease registry (B1) is static; isolate it per test.
  setUp(HdrYuvWindowProcessRegistry.resetForTesting);

  group('contract validation', () {
    test('accepted quad passes validation', () {
      // Must not throw.
      HdrYuvPresentationContract.validate(_yuvRoute());
      // The euv17 actual shape (the review counterexample carrier): plain
      // `pq` request on the surfacetexture carrier with the offscreen
      // contract the realizer now generates for it.
      HdrYuvPresentationContract.validate(
          _yuvRoute().surrogate(surfaceTransfer: 'pq'));
    });

    test('shapes outside the YUV carrier are out of scope', () {
      // Limited PQ label on the RGB mediacodec-copy carrier: no
      // SurfaceTexture intermediary, no separate offscreen contract.
      HdrYuvPresentationContract.validate(
          _yuvRoute().surrogate(hwdec: 'mediacodec-copy'));
      // Texture routes never carry the YUV shape.
      HdrYuvPresentationContract.validate(_yuvRoute().surrogate(
          hwdec: 'mediacodec', vo: 'gpu-next', surfaceTransfer: 'x'));
      // Non-PQ window request on the carrier is not the YUV pairing.
      HdrYuvPresentationContract.validate(_yuvRoute()
          .surrogate(surfaceTransfer: 'hlg', offscreenTransfer: null));
    });

    test('every quad member is fail-closed', () {
      final mutations = <String, HdrRoute Function()>{
        'offscreen-null': () => _yuvRoute().surrogate(offscreenTransfer: null),
        'offscreen-wrong': () =>
            _yuvRoute().surrogate(offscreenTransfer: 'pq-limited'),
        'vo': () => _yuvRoute().surrogate(vo: 'mediacodec_embed'),
        'topology': () => _yuvRoute().surrogate(topology: HdrTopology.texture),
        'prim': () => _yuvRoute().surrogate(targetPrim: 'bt.709'),
        'trc': () => _yuvRoute().surrogate(targetTrc: 'hlg'),
      };
      mutations.forEach((member, build) {
        expect(
          () => HdrYuvPresentationContract.validate(build()),
          throwsA(isA<StateError>().having((error) => error.message, 'message',
              contains('YUV presentation contract rejected'))),
          reason: 'quad member "$member" must be fail-closed',
        );
      });
    });

    test('pre-fix counterexample shape is now covered by the gate', () {
      // P8.4 A5 V2 review counterexample (euv17-contract): surfacetexture
      // carrier + requested `pq` + offscreen null — the actual YUV shape
      // presented through the vendor-forced 0x11C60000 window, which the
      // request-keyed gate used to let through without the quad.
      final counterexample =
          _yuvRoute().surrogate(surfaceTransfer: 'pq', offscreenTransfer: null);
      expect(
          HdrYuvPresentationContract.isYuvWindowRoute(counterexample), isTrue,
          reason: 'the carrier, not the requested label, decides the shape');
      expect(
        () => HdrYuvPresentationContract.validate(counterexample),
        throwsA(isA<StateError>().having((error) => error.message, 'message',
            contains('offscreen=null (need pq-full)'))),
      );
    });

    test('declared constants equal the accepted euv13/euv17 values', () {
      expect(HdrYuvPresentationContract.windowDataSpace, 0x11C60000);
      expect(HdrYuvPresentationContract.metadataPrimaries, 9);
      expect(HdrYuvPresentationContract.metadataRange, 1);
      expect(HdrYuvPresentationContract.metadataTransfer, 16);
      expect(HdrYuvPresentationContract.offscreenTransfer, 'pq-full');
      expect(HdrYuvPresentationContract.windowTransfer, 'pq-itu');
      expect(HdrYuvPresentationContract.windowRequests, ['pq', 'pq-itu']);
      expect(HdrYuvPresentationContract.targetPeak, '1000');
    });

    test('offscreen contract maps to the mpv output-levels value', () {
      expect(HdrYuvPresentationContract.mpvOutputLevels('pq-full'), 'full');
      expect(
        () => HdrYuvPresentationContract.mpvOutputLevels('pq-limited'),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('backend issuance', () {
    test('YUV route issues owned output levels and the window dataspace',
        () async {
      final result = await _exercise(_yuvRoute());
      expect(result.player.properties['video-output-levels'], 'full');
      expect(result.player.properties['target-trc'], 'pq');
      expect(result.player.properties['target-peak'], '1000');
      expect(await result.player.getPropertyAsync('gamma'), '0.000000');
      expect(result.player.writtenProperties, isNot(contains('gamma')));
      expect(result.dataSpaceRequested, 'pq-itu');
      await result.backend.configure(_issuedPlan(_yuvRoute()));
      expect(await result.player.getPropertyAsync('gamma'), '0.000000');
      expect(result.player.writtenProperties, isNot(contains('gamma')));
      await result.backend.resetOwnedConfiguration();
      expect(result.player.properties['video-output-levels'], 'auto');
      expect(result.player.properties['target-trc'], 'sdr');
      expect(result.player.properties['target-peak'], 'auto');
      expect(await result.player.getPropertyAsync('gamma'), '0.000000');
      expect(result.player.writtenProperties, isNot(contains('gamma')));
    });

    test('dataspace observation resets across PQ to SDR and a later PQ',
        () async {
      final result = _harness();
      final pq = _issuedPlan(_yuvRoute());
      await result.backend.prepareOutput(pq);
      await result.backend.configure(pq);
      expect(result.backend.observe().dataSpaceRequested, 'pq-itu');
      expect(result.backend.observe().dataSpacePath, 'ext:lg-pq');
      expect(result.backend.observe().dataSpaceReadback, isNull);
      expect(result.dataSpaceApplyCount, 1);

      final sdrRoute = HdrRoute(
        strategy: HdrStrategy.sdrDirect,
        presentation: HdrPresentation.sdr,
        outputTransfer: HdrOutputTransfer.sdr,
        appliesDynamicMetadata: false,
        topology: HdrTopology.platformView,
        vo: 'mediacodec_embed',
        hwdec: 'mediacodec',
        targetPrim: null,
        targetTrc: 'sdr',
        surfaceTransfer: null,
        stripDvRpu: false,
      );
      await result.backend.configure(pq.copyWith(route: sdrRoute));
      expect(result.backend.observe().dataSpaceRequested, isNull);
      expect(result.backend.observe().dataSpacePath, isNull);
      expect(result.backend.observe().dataSpaceReadback, isNull);
      expect(result.dataSpaceApplyCount, 1,
          reason: 'SDR with no dataspace must not call the injected setter');

      result.dataSpacePath = 'new-pq-path';
      result.dataSpaceReadback = 'DATASPACE_BT2020_PQ_LIMITED';
      await result.backend.configure(pq);
      expect(result.backend.observe().dataSpaceRequested, 'pq-itu');
      expect(result.backend.observe().dataSpacePath, 'new-pq-path');
      expect(result.backend.observe().dataSpaceReadback,
          'DATASPACE_BT2020_PQ_LIMITED');
      expect(result.dataSpaceApplyCount, 2);
    });

    test('non-neutral user gamma is preserved', () async {
      final result = _harness();
      result.player.properties['gamma'] = '1.25';
      final plan = _issuedPlan(_yuvRoute());
      await result.backend.prepareOutput(plan);
      await result.backend.configure(plan);
      expect(result.player.properties['gamma'], '1.25');
      await result.backend.resetOwnedConfiguration();
      expect(result.player.properties['gamma'], '1.25');
    });

    test('PQ input does not change gamma',
        () async {
      final nonHlg = _issuedPlan(_yuvRoute()).copyWith(
        source: const HdrSourceDescriptor(codec: 'hevc', transfer: 'pq'),
      );
      await _expectNoGamma(nonHlg);
    });

    test('other YUV PQ extensions do not change gamma', () async {
      final plan = _issuedPlan(_yuvRoute()).copyWith(
        capabilities: HdrCapabilities(
          sdkInt: 24,
          displayHdrTypes: const {2, 3},
          hevcDecoders: const [],
          dolbyVisionDecoders: const [],
          p5PipelineAvailable: true,
          dataSpaceBridgeLoaded: true,
          dataSpaceExt: const HdrDataSpaceExtInfo(
            id: 'other-pq',
            applicable: true,
            pqPresentation:
                HdrPqPresentation(rgbSurface: false, yuvWindow: true),
            setterOnlyTransfers: <String>{'pq-itu'},
            yuvWindowArmApi: 1,
          ),
        ),
      );
      await _expectNoGamma(plan);
    });

    test('other strategies do not change gamma', () async {
      final plan = _issuedPlan(
        _yuvRoute().surrogate(strategy: HdrStrategy.toneMapSdr),
      );
      await _expectNoGamma(plan);
    });

    test('gamma setter rejection is irrelevant to YUV configuration', () async {
      final result = _harness();
      result.player.rejectedProperties.add('gamma');
      final plan = _issuedPlan(_yuvRoute());
      await result.backend.prepareOutput(plan);
      await result.backend.configure(plan);
      await result.backend.resetOwnedConfiguration();
      expect(await result.player.getPropertyAsync('gamma'), '0.000000');
      expect(result.player.writtenProperties, isNot(contains('gamma')));
    });

    test('configuration failure restores owned output but preserves gamma',
        () async {
      final result = _harness(dataSpaceSucceeds: false);
      result.player.properties['gamma'] = '0.000000';
      final plan = _issuedPlan(_yuvRoute());
      await result.backend.prepareOutput(plan);
      await expectLater(result.backend.configure(plan),
          throwsA(isA<HdrDataSpaceApplyException>()));
      expect(result.player.properties['gamma'], '0.000000');
      // A user adjustment after failure is not a backend-owned value.
      result.player.properties['gamma'] = '1.25';
      await result.backend.resetOwnedConfiguration();
      expect(result.player.properties['gamma'], '1.25');
      expect(result.player.properties['target-peak'], 'auto');
      expect(result.player.properties['target-trc'], 'sdr');
      expect(result.player.properties['video-output-levels'], 'auto');
      expect(result.player.writtenProperties, isNot(contains('gamma')));
    });

    test('user gamma changed during playback survives owned reset', () async {
      final result = _harness();
      final plan = _issuedPlan(_yuvRoute());
      await result.backend.prepareOutput(plan);
      await result.backend.configure(plan);
      expect(await result.player.getPropertyAsync('gamma'), '0.000000');
      result.player.properties['gamma'] = '1.25';
      await result.backend.resetOwnedConfiguration();
      expect(result.player.properties['gamma'], '1.25');
      expect(result.player.writtenProperties, isNot(contains('gamma')));
    });

    test('new user gamma between YUV sessions remains untouched', () async {
      final result = _harness();
      final plan = _issuedPlan(_yuvRoute());
      await result.backend.prepareOutput(plan);
      await result.backend.configure(plan);
      await result.backend.resetOwnedConfiguration();
      result.player.properties['gamma'] = '1.25';
      await result.backend.configure(plan);
      expect(result.player.properties['gamma'], '1.25');
      await result.backend.resetOwnedConfiguration();
      expect(result.player.properties['gamma'], '1.25');
      expect(result.player.writtenProperties, isNot(contains('gamma')));
    });

    test('euv17 pq-request route issues the owned quad write', () async {
      // The review counterexample's actual euv17 pairing: surfacetexture
      // carrier + requested `pq`. With the realizer generating the offscreen
      // contract for this shape, validate passes and the owned
      // video-output-levels=full write is issued (it was skipped before the
      // fix).
      final result =
          await _exercise(_yuvRoute().surrogate(surfaceTransfer: 'pq'));
      expect(result.player.properties['video-output-levels'], 'full');
      expect(result.player.properties['target-trc'], 'pq');
      expect(result.player.properties['target-peak'], '1000');
      expect(result.dataSpaceRequested, 'pq');
      await result.backend.resetOwnedConfiguration();
      expect(result.player.properties['video-output-levels'], 'auto');
      expect(result.player.properties['target-trc'], 'sdr');
      expect(result.player.properties['target-peak'], 'auto');
    });

    test('YUV block reads the route peak before the contract constant',
        () async {
      // The backend applies a route target verbatim; it does not replace
      // an explicit diagnostic target with the production HLG reference.
      final result = await _exercise(_yuvRoute().surrogate(targetPeak: '620'));
      expect(result.player.properties['target-trc'], 'pq');
      expect(result.player.properties['target-peak'], '620');
      await result.backend.resetOwnedConfiguration();
      expect(result.player.properties['target-peak'], 'auto');
    });

    test('YUV route without the offscreen contract is refused before writes',
        () async {
      final result = _harness();
      await expectLater(
        result.backend.prepareOutput(
            _plan(_yuvRoute().surrogate(offscreenTransfer: null))),
        throwsA(isA<StateError>()),
      );
      // Fail-closed happened before any owned write or controller creation.
      expect(result.player.properties['hwdec'], 'no');
      expect(
          result.player.properties.containsKey('video-output-levels'), isFalse);
    });

    test('routes off the YUV carrier issue no output levels', () async {
      final result = await _exercise(_yuvRoute()
          .surrogate(hwdec: 'mediacodec-copy', surfaceTransfer: 'pq'));
      expect(
          result.player.properties.containsKey('video-output-levels'), isFalse);
      expect(result.player.properties.containsKey('gamma'), isFalse);
      expect(result.dataSpaceRequested, 'pq');
    });
  });

  group('backend arm integration (plan C)', () {
    // The shared [_plan] carries the migration-default capability snapshot
    // (no yuvWindow declaration); the arm admission tests need the declared
    // YUV-window channel the realizer's route implies.
    HdrOpenPlan yuvPlan(HdrRoute route) => _plan(route).copyWith(
          capabilities: HdrCapabilities(
            sdkInt: 24,
            displayHdrTypes: const {2, 3},
            hevcDecoders: const [],
            dolbyVisionDecoders: const [],
            p5PipelineAvailable: true,
            dataSpaceBridgeLoaded: true,
            // The LG-shaped self-report: the YUV window channel, the
            // setter-only exception the readback-less apply path relies on,
            // and the managed YUV arm protocol declaration.
            dataSpaceExt: const HdrDataSpaceExtInfo(
              id: 'lg-pq',
              applicable: true,
              pqPresentation:
                  HdrPqPresentation(rgbSurface: false, yuvWindow: true),
              setterOnlyTransfers: <String>{'pq', 'pq-itu'},
              yuvWindowArmApi: 1,
            ),
          ),
        );

    _ArmHarness armHarness({String? ownerToken = 'owner-token'}) {
      final calls = <String>[];
      final atoms = FakeArmAtoms(calls);
      final player = _FakePlayer();
      final arm = HdrYuvWindowArm(
        ownerToken: ownerToken,
        ownerGeneration: () async => 5,
        bindingsResolver: () => atoms.bindings(),
        channel: atoms.channel,
      );
      final backend = AndroidHdrBackend(
        player: player,
        outputSlot: HdrOutputSlot<VideoController>(
          initial: null,
          voOf: (_) async => 'gpu-next',
          disposeForRebuild: (_) async => calls.add('dispose'),
          create: (contract) {
            calls.add('create');
            return _FakeOutput();
          },
          publish: (output) =>
              calls.add('publish:${output == null ? 'null' : 'out'}'),
          waitReady: (_) async => calls.add('ready'),
        ),
        yuvWindowArm: arm,
        applyDataSpace: (_, transfer) async =>
            {'applied': true, 'path': 'ext:lg-pq', 'readback': null},
      );
      return _ArmHarness(backend, atoms, calls, player);
    }

    test('YUV route arms inside the slot barrier, before the create', () async {
      final harness = armHarness();
      await harness.backend.prepareOutput(yuvPlan(_yuvRoute()));
      expect(harness.atoms.diagDataSpace,
          HdrYuvPresentationContract.windowDataSpace);
      // The unified event timeline proves the process admission precedes
      // everything and the arm ACK strictly precedes the output creation
      // (and publication): moving the arm after the create flips this red
      // instead of silently keeping a final-value check. The write
      // admission intentionally OUTLIVES prepareOutput (it is held to the
      // attempt's terminal cleanup), so no release appears here.
      expect(harness.calls, [
        'admit:write',
        'arm:diag:${HdrYuvPresentationContract.windowDataSpace}',
        'arm:bound',
        'create',
        'publish:out',
        'ready',
      ]);
      expect(harness.atoms.gate.writer, isTrue,
          reason: 'the write admission is still held after prepareOutput');
    });

    test('routes off the YUV carrier arm nothing through the backend',
        () async {
      final harness = armHarness();
      await harness.backend.prepareOutput(
          yuvPlan(_yuvRoute().surrogate(hwdec: 'mediacodec-copy')));
      expect(harness.atoms.calls, isEmpty);
      // Round 3: the non-YUV route takes a READ admission (Begin/End) but
      // performs no arm/disarm channel call and touches no atom.
      expect(
          harness.atoms.channelCalls
              .where((method) => method.contains('YuvDiag')),
          isEmpty);
      expect(harness.atoms.gate.writer, isFalse);
      expect(harness.atoms.gate.readers, 0,
          reason: 'the read admission was released when ensure settled');
    });

    test(
        'the read admission covers the texture topology\'s real '
        'initialization tail (R3-3)', () async {
      // Real backend fixture: a texture-topology route whose ACTUAL VO
      // rebuild (prepareAndroidTextureOutput: SetSurfaceSize + the locked
      // wid/vo re-apply in real.dart) suspends mid-call — the read
      // admission must still be held there, so a concurrent YUV write is
      // rejected until the real tail completes.
      final calls = <String>[];
      final atoms = FakeArmAtoms(calls);
      final player = _FakePlayer();
      final textureGate = Completer<void>();
      final arm = HdrYuvWindowArm(
        ownerToken: 'owner-a',
        ownerGeneration: () async => 5,
        bindingsResolver: () => atoms.bindings(),
        channel: atoms.channel,
      );
      final backend = AndroidHdrBackend(
        player: player,
        outputSlot: HdrOutputSlot<VideoController>(
          initial: null,
          voOf: (_) async => 'gpu-next',
          disposeForRebuild: (_) async => calls.add('dispose'),
          create: (contract) {
            calls.add('create');
            return _TextureGateOutput(textureGate);
          },
          publish: (output) =>
              calls.add('publish:${output == null ? 'null' : 'out'}'),
          waitReady: (_) async => calls.add('ready'),
        ),
        yuvWindowArm: arm,
        applyDataSpace: (_, transfer) async =>
            {'applied': true, 'path': 'ext:lg-pq', 'readback': null},
      );
      final other = HdrYuvWindowArm(
        ownerToken: 'owner-b',
        ownerGeneration: () async => 5,
        bindingsResolver: () => atoms.bindings(),
        channel: atoms.channel,
      );
      final texturePlan = yuvPlan(_yuvRoute().surrogate(
          hwdec: 'mediacodec-copy', topology: HdrTopology.texture));
      final preparing = backend.prepareOutput(texturePlan);
      for (var i = 0;
          !calls.contains('create') || !calls.contains('ready');
          i++) {
        if (i > 5000) fail('texture preparation did not reach its tail');
        await Future<void>.delayed(Duration.zero);
      }
      // Suspended INSIDE prepareAndroidTextureOutput — past ensure, at the
      // real initialization tail.
      expect(atoms.gate.readers, 1,
          reason: 'the read admission still covers the texture tail');
      await expectLater(
        other.initializeOutput(yuvPlan(_yuvRoute()), () async {
          await other.armForAttempt(yuvPlan(_yuvRoute()));
        }),
        throwsA(isA<HdrYuvWindowLeaseConflict>()),
      );
      expect(atoms.calls.where((c) => c.startsWith('diag:')), isEmpty,
          reason: 'the rejected YUV attempt armed nothing');
      textureGate.complete();
      await preparing;
      expect(atoms.gate.readers, 0,
          reason: 'the read released only after the real tail completed');
      // With the process quiescent, the same YUV attempt proceeds.
      final plan = yuvPlan(_yuvRoute());
      await other.initializeOutput(plan, () => other.armForAttempt(plan));
      await other.endAttempt(plan);
      expect(atoms.diagDataSpace, 0);
      expect(atoms.yuvDiagEnabled, 0);
    });

    test('production gap: no owner token fails validation before any write',
        () async {
      final harness = armHarness(ownerToken: null);
      await expectLater(
        harness.backend.validate(yuvPlan(_yuvRoute())),
        throwsA(isA<HdrYuvWindowArmFailure>().having((error) => error.cause,
            'cause', contains('no valid surface owner token'))),
      );
      expect(harness.atoms.calls, isEmpty);
      expect(harness.properties['hwdec'], 'no',
          reason: 'fail-closed before any owned write');
    });

    test('arm failure inside the barrier creates no output', () async {
      final harness = armHarness();
      harness.atoms.omitYuvDiagSetter = true;
      harness.atoms.channelError = StateError('no plugin');
      await expectLater(
        harness.backend.prepareOutput(yuvPlan(_yuvRoute())),
        throwsA(isA<HdrYuvWindowArmFailure>()),
      );
      expect(harness.calls, isNot(contains('create')));
      expect(harness.atoms.diagDataSpace, 0,
          reason: 'the partial arm was rolled back');
    });
  });
}

class _ArmHarness {
  _ArmHarness(this.backend, this.atoms, this.calls, this._player);
  final AndroidHdrBackend backend;
  final FakeArmAtoms atoms;
  final List<String> calls;
  final _FakePlayer _player;

  /// Owned mpv property state of the fake player.
  Map<String, String> get properties => _player.properties;
}

class FakeArmAtoms {
  FakeArmAtoms([this.timeline]);
  final List<String>? timeline;
  int diagDataSpace = 0;
  int yuvDiagEnabled = 0;
  final calls = <String>[];
  final channelCalls = <String>[];
  Object? channelError;
  bool omitYuvDiagSetter = false;

  /// Host mirror of the vendor plugin's process-static admission gate.
  final gate = _ArmInitGate();

  HdrYuvWindowFfiBindings bindings() => HdrYuvWindowFfiBindings(
        setDiagDataSpace: (value) {
          calls.add('diag:$value');
          timeline?.add(value == 0 ? 'disarm:diag' : 'arm:diag:$value');
          diagDataSpace = value;
        },
        setYuvDiagEnabled: omitYuvDiagSetter
            ? null
            : (value) {
                calls.add('yuvDiag:$value');
                timeline?.add('legacy:$value');
                yuvDiagEnabled = value;
              },
        disarmYuvDiag: () {
          calls.add('disarm');
          timeline?.add('disarm:yuv');
          yuvDiagEnabled = 0;
        },
      );

  Future<Object?> channel(String method, Map<String, Object?> arguments) async {
    if (channelError != null) throw channelError!;
    channelCalls.add(method);
    switch (method) {
      case 'EnableYuvDiag':
        yuvDiagEnabled = 1;
        timeline?.add('arm:bound');
        return true;
      case 'DisableYuvDiag':
        yuvDiagEnabled = 0;
        timeline?.add('disarm:bound');
        return true;
      case 'BeginOutputInitRead':
        return gate.beginRead();
      case 'EndOutputInitRead':
        gate.endRead();
        return true;
      case 'BeginOutputInitWrite':
        timeline?.add('admit:write');
        return gate.beginWrite(
            arguments['ownerToken'] as Object,
            (arguments['leaseId'] as int?) ?? 0);
      case 'EndOutputInitWrite':
        timeline?.add('release:write');
        return gate.endWrite((arguments['leaseId'] as int?) ?? 0);
      default:
        return null;
    }
  }
}

class _ArmInitGate {
  int readers = 0;
  int _writerLease = 0;
  Object? writerKey;
  int _nextLease = 0;

  bool beginRead() {
    if (_writerLease != 0) return false;
    readers++;
    return true;
  }

  void endRead() {
    if (readers > 0) readers--;
  }

  /// Lease-id identity (R3-4 mirror): a held lease rejects every other
  /// acquire — the same token included; only the exact held lease retries.
  int beginWrite(Object key, int retryLease) {
    if (_writerLease != 0 || readers > 0) {
      return retryLease != 0 && retryLease == _writerLease ? _writerLease : 0;
    }
    _writerLease = ++_nextLease;
    writerKey = key;
    return _writerLease;
  }

  bool endWrite(int lease) {
    if (_writerLease == 0 || _writerLease != lease) return false;
    _writerLease = 0;
    writerKey = null;
    return true;
  }

  bool get writer => _writerLease != 0;
}

HdrRoute _yuvRoute() => const HdrRoute(
      strategy: HdrStrategy.baseLayerConvert,
      presentation: HdrPresentation.nativeHdr,
      outputTransfer: HdrOutputTransfer.pq,
      appliesDynamicMetadata: false,
      topology: HdrTopology.platformView,
      vo: 'gpu-next',
      hwdec: 'surfacetexture',
      targetPrim: 'bt.2020',
      targetTrc: 'pq',
      surfaceTransfer: 'pq-itu',
      offscreenTransfer: 'pq-full',
      stripDvRpu: false,
    );

extension _RouteSurrogate on HdrRoute {
  /// Hand-rolled surrogate: keeps the fail-closed cases readable without a
  /// full copyWith on the immutable route value. [offscreenTransfer] has no
  /// fallback so a null argument explicitly resets the field.
  HdrRoute surrogate({
    HdrStrategy? strategy,
    String? hwdec,
    String? vo,
    HdrTopology? topology,
    String? surfaceTransfer,
    String? offscreenTransfer = 'pq-full',
    String? targetPrim,
    String? targetTrc,
    String? targetPeak,
  }) =>
      HdrRoute(
        strategy: strategy ?? this.strategy,
        presentation: presentation,
        outputTransfer: outputTransfer,
        appliesDynamicMetadata: appliesDynamicMetadata,
        topology: topology ?? this.topology,
        vo: vo ?? this.vo,
        hwdec: hwdec ?? this.hwdec,
        targetPrim: targetPrim ?? this.targetPrim,
        targetTrc: targetTrc ?? this.targetTrc,
        targetPeak: targetPeak ?? this.targetPeak,
        surfaceTransfer: surfaceTransfer ?? this.surfaceTransfer,
        offscreenTransfer: offscreenTransfer,
        stripDvRpu: stripDvRpu,
        dependencies: dependencies,
      );
}

HdrOpenPlan _plan(HdrRoute route) {
  const source = HdrSourceDescriptor(codec: 'hevc', transfer: 'hlg');
  final candidate = HdrCandidate(
    strategy: HdrStrategy.baseLayerConvert,
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
      displayHdrTypes: {2, 3},
      hevcDecoders: [],
      dolbyVisionDecoders: [],
      p5PipelineAvailable: true,
      dataSpaceBridgeLoaded: true,
      dataSpaceExt: HdrDataSpaceExtInfo(id: 'lg-pq', applicable: true),
    ),
    prediction: HdrRoutePrediction(
      source: source,
      selected: candidate,
      candidates: [candidate],
      presentation: HdrPresentation.nativeHdr,
      confidence: HdrPredictionConfidence.verified,
      playable: true,
    ),
    route: route,
  );
}

class _Harness {
  _Harness(this.player);
  final _FakePlayer player;
  late final AndroidHdrBackend backend;
  late final FakeArmAtoms atoms;
  String? dataSpaceRequested;
  String? dataSpacePath;
  String? dataSpaceReadback;
  int dataSpaceApplyCount = 0;
}

Future<void> _expectNoGamma(HdrOpenPlan plan) async {
  final result =
      _harness(dataSpaceExtId: plan.capabilities.dataSpaceExt?.id ?? 'lg-pq');
  await result.backend.prepareOutput(plan);
  await result.backend.configure(plan);
  expect(result.player.properties.containsKey('gamma'), isFalse);
  await result.backend.resetOwnedConfiguration();
  expect(result.player.writtenProperties, isNot(contains('gamma')));
}

_Harness _harness({
  String dataSpaceExtId = 'lg-pq',
  bool dataSpaceSucceeds = true,
}) {
  final player = _FakePlayer();
  final harness = _Harness(player);
  // The backend constructor owns a real arm manager by default now. This
  // contract pins the backend's owned writes, so the harness injects the
  // same real manager through the constructor seam with the fake platform
  // round trips (vendor channel + FFI atoms) the arm-integration group
  // uses: admission, ownership and lease checks all stay live; only the
  // platform boundary is a test double.
  final atoms = FakeArmAtoms();
  harness.atoms = atoms;
  harness.backend = AndroidHdrBackend(
    player: player,
    outputSlot: HdrOutputSlot<VideoController>(
      initial: null,
      voOf: (_) async => 'gpu-next',
      disposeForRebuild: (_) async {},
      create: (contract) => _FakeOutput(),
      publish: (_) {},
      waitReady: (_) async {},
    ),
    yuvWindowArm: HdrYuvWindowArm(
      ownerToken: 'owner-token',
      ownerGeneration: () async => 5,
      bindingsResolver: () => atoms.bindings(),
      channel: atoms.channel,
    ),
    applyDataSpace: (_, transfer) async {
      harness.dataSpaceRequested = transfer;
      harness.dataSpaceApplyCount++;
      // LG setter path: accepted without readback (the evidence-pinned
      // API24 extension), matching the device behavior this contract pins.
      return {
        'applied': dataSpaceSucceeds,
        'path': harness.dataSpacePath ?? 'ext:$dataSpaceExtId',
        'readback': harness.dataSpaceReadback,
      };
    },
  );
  return harness;
}

/// The issuance group's plan declares the YUV-window PQ presentation
/// channel the accepted quad implies (the arm-integration group's
/// `yuvPlan` shape): an admissible route is the precondition for the owned
/// writes pinned here, while the route WITHOUT the declaration still fails
/// admission in the arm group's production-gap test.
HdrOpenPlan _issuedPlan(HdrRoute route) => _plan(route).copyWith(
      capabilities: HdrCapabilities(
        sdkInt: 24,
        displayHdrTypes: const {2, 3},
        hevcDecoders: const [],
        dolbyVisionDecoders: const [],
        p5PipelineAvailable: true,
        dataSpaceBridgeLoaded: true,
        // The LG-shaped self-report: the YUV window channel, the
        // setter-only exception the harness's readback-less apply path
        // relies on, and the managed YUV arm protocol declaration.
        dataSpaceExt: const HdrDataSpaceExtInfo(
          id: 'lg-pq',
          applicable: true,
          pqPresentation:
              HdrPqPresentation(rgbSurface: false, yuvWindow: true),
          setterOnlyTransfers: <String>{'pq', 'pq-itu'},
          yuvWindowArmApi: 1,
        ),
      ),
    );

Future<_Harness> _exercise(HdrRoute route) async {
  final result = _harness();
  await result.backend.prepareOutput(_issuedPlan(route));
  await result.backend.configure(_issuedPlan(route));
  return result;
}

class _FakeOutput implements VideoController {
  @override
  final Completer<PlatformVideoController> platform =
      Completer<PlatformVideoController>()..complete(_FakePlatformOutput());
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A fake output whose REAL initialization tail
/// ([VideoController.prepareAndroidTextureOutput]) suspends until a test
/// gate completes — the R3-3 fixture.
class _TextureGateOutput extends _FakeOutput {
  _TextureGateOutput(this.gate);
  final Completer<void> gate;

  @override
  Future<bool> prepareAndroidTextureOutput() async {
    await gate.future;
    return true;
  }
}

class _FakePlatformOutput implements PlatformVideoController {
  @override
  Future<void> get waitUntilCurrentOutputBound async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePlayer implements Player {
  _FakePlayer() : properties = {'hwdec': 'no', 'hwdec-software-fallback': '3'};

  final Map<String, String> properties;
  final Set<String> rejectedProperties = <String>{};
  final List<String> writtenProperties = <String>[];
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
  Future<int> get handle async => 1;
  @override
  Future<String> getPropertyAsync(String name,
      {bool waitForInitialization = true}) async {
    // Non-empty baselines so the owned writes can capture and restore.
    return properties[name] ??
        (name == 'video-output-levels'
            ? 'auto'
            : name == 'cache-on-disk'
                ? 'yes'
                : name == 'egl-output-format'
                    ? 'rgb8'
                    : name == 'target-prim'
                        ? 'bt.709'
                        : name == 'target-trc'
                            ? 'sdr'
                            : name == 'target-peak'
                                ? 'auto'
                                : name == 'target-colorspace-hint'
                                    ? 'no'
                                    : name == 'gamma'
                                        ? '0.000000'
                                        : '');
  }

  @override
  Future<void> setPropertyStrict(String name, String value,
      {bool waitForInitialization = true}) async {
    writtenProperties.add(name);
    if (rejectedProperties.contains(name)) return;
    properties[name] = name == 'gamma' && double.tryParse(value) != null
        ? double.parse(value).toStringAsFixed(6)
        : value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
