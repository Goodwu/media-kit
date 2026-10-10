import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' show Media, VideoParams;
import 'package:media_kit_video/src/hdr/hdr_capabilities.dart';
import 'package:media_kit_video/src/hdr/hdr_open_plan.dart';
import 'package:media_kit_video/src/hdr/hdr_output_diagnostics.dart';
import 'package:media_kit_video/src/hdr/hdr_route.dart';
import 'package:media_kit_video/src/hdr/hdr_route_planner.dart';
import 'package:media_kit_video/src/hdr/hdr_source_classifier.dart';
import 'package:media_kit_video/src/hdr/hdr_source_descriptor.dart';
import 'package:media_kit_video/src/hdr/hdr_strategy.dart';
import 'package:media_kit_video/src/hdr/hdr_video_session.dart';

import 'hdr_video_session_test.dart' show AttemptScript, FakeBackend;

/// S8 verification: layered single-line `key=value` diagnostic logging
/// (requirement R4.3). Disabled by default with zero output and zero string
/// construction; when enabled, every layer emits one fixed-format line
/// prefixed with `HdrDiag`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final lines = <String>[];

  setUp(() {
    lines.clear();
    HdrOutputDiagnostics.enabled = false;
  });

  tearDown(() {
    HdrOutputDiagnostics.enabled = false;
    HdrOutputDiagnostics.printer = debugPrint;
  });

  void enable() {
    HdrOutputDiagnostics.printer = lines.add;
    HdrOutputDiagnostics.enabled = true;
  }

  /// `key=value` field names of a diagnostics line, in emission order.
  List<String> keysOf(String line) {
    // `<tag> HDR <layer>: k=v ...` — the layer token is the third word,
    // carrying the colon that separates it from the field list.
    final words = line.split(' ');
    final prefix = '${HdrOutputDiagnostics.tag} HDR '
        '${words[2].replaceAll(':', '')}';
    expect(line.startsWith('$prefix: '), isTrue, reason: line);
    expect(line.contains('\n'), isFalse, reason: 'single line required');
    return line
        .substring('$prefix: '.length)
        .split(' ')
        .map((field) => field.split('=')[0])
        .toList();
  }

  const hdr10 = HdrSourceDescriptor(
    codec: 'hevc',
    transfer: 'pq',
    primaries: 'bt.2020',
    enhancementLayer: false,
  );
  const p84 = HdrSourceDescriptor(
    codec: 'hevc',
    transfer: 'hlg',
    primaries: 'bt.2020',
    dynamicMetadata: HdrDynamicMetadata.dolbyVision,
    dvProfile: 8,
    dvCompatibilityId: 4,
    enhancementLayer: false,
  );
  const p5 = HdrSourceDescriptor(
    codec: 'hevc',
    dynamicMetadata: HdrDynamicMetadata.dolbyVision,
    dvProfile: 5,
    dvCompatibilityId: 0,
    enhancementLayer: false,
  );

  final media = Media('test://media');

  HdrCapabilities caps({
    Set<int>? types = const {1, 2, 3},
    bool p5Pipeline = true,
    bool ext = true,
    List<HdrDecoderInfo> hevc = const <HdrDecoderInfo>[],
  }) =>
      HdrCapabilities(
        sdkInt: 29,
        displayHdrTypes: types,
        hevcDecoders: hevc,
        dolbyVisionDecoders: const <HdrDecoderInfo>[],
        p5PipelineAvailable: p5Pipeline,
        dataSpaceBridgeLoaded: true,
        dataSpaceExt: ext
            ? const HdrDataSpaceExtInfo(id: 'lya-pq', applicable: true)
            : null,
      );

  const main10Decoder = HdrDecoderInfo(
    name: 'OMX.hisi.video.decoder.hevc',
    mimeType: 'video/hevc',
    hardwareAcceleration: true,
    profiles: <int>[2],
    main10: true,
    widthRange: <int>[16, 4096],
    heightRange: <int>[16, 4096],
    frameRateRange: <int>[8, 240],
    supports4K: true,
    max4KFps: 59.94,
  );

  HdrReviewFacts facts({
    required String gamma,
    int? profile,
    String hwdec = 'mediacodec',
  }) =>
      HdrReviewFacts(
        videoParams: VideoParams(gamma: gamma, primaries: 'bt.2020'),
        dolbyVisionProfile: profile,
        codec: 'hevc',
        hwdecCurrent: hwdec,
        path: media.uri,
      );

  HdrVideoSession makeSession({
    required FakeBackend backend,
    required HdrCapabilities capabilities,
    HdrRoutingPolicy policy = HdrRoutingPolicy.defaults,
  }) {
    return HdrVideoSession.forTesting(
      player: null,
      policy: policy,
      capabilitiesProvider: () async => capabilities,
      positionProvider: () => Duration.zero,
      isAndroid: true,
      backend: backend,
    );
  }

  group('disabled by default (R4.3 hard requirement)', () {
    test('every layer emits nothing, including through the real hooks', () {
      expect(HdrOutputDiagnostics.enabled, isFalse);
      HdrOutputDiagnostics.printer = lines.add;

      // Direct emit calls.
      HdrOutputDiagnostics.capability(caps());
      HdrOutputDiagnostics.recover(generation: 1, capabilities: caps());
      HdrOutputDiagnostics.predict(
          HdrRoutePlanner.plan(source: p84, capabilities: caps()));
      HdrOutputDiagnostics.classify(
          descriptor: p84, origin: 'facts');
      HdrOutputDiagnostics.decision(
        generation: 1,
        phase: 'plan',
        source: p84,
        prediction: HdrRoutePlanner.plan(source: p84, capabilities: caps()),
      );
      HdrOutputDiagnostics.readback(
        requested: 'pq',
        path: 'ext:lya-pq',
        applied: true,
        readback: 'DATASPACE_BT2020_PQ',
      );
      HdrOutputDiagnostics.degrade(
        generation: 1,
        reason: HdrDegradeReason.dataSpaceApplyFailed,
      );

      // Through the production hook points.
      HdrRoutePlanner.plan(source: hdr10, capabilities: caps());
      const HdrSourceClassifier().classify(videoParams: null, hint: p84);

      expect(lines, isEmpty);
    });
  });

  group('capability layer', () {
    test('fixed single line with the full field set and order', () {
      enable();
      HdrOutputDiagnostics.capability(
          caps(hevc: const <HdrDecoderInfo>[main10Decoder]));
      expect(
        lines.single,
        'HdrDiag HDR capability: sdk=29 displayHdrTypes=1,2,3 '
        'hevcDecoders=1 hevcMain10=true hevc4k=true dvDecoders=0 '
        'p5Pipeline=true bridge=true ext=lya-pq extApplicable=true',
      );
      expect(
        keysOf(lines.single),
        <String>[
          'sdk',
          'displayHdrTypes',
          'hevcDecoders',
          'hevcMain10',
          'hevc4k',
          'dvDecoders',
          'p5Pipeline',
          'bridge',
          'ext',
          'extApplicable',
        ],
      );
    });

    test('unknown values degrade to unreported/none, never guessed', () {
      enable();
      HdrOutputDiagnostics.capability(caps(types: null, ext: false));
      expect(
        lines.single,
        'HdrDiag HDR capability: sdk=29 displayHdrTypes=unreported '
        'hevcDecoders=0 hevcMain10=none hevc4k=none dvDecoders=0 '
        'p5Pipeline=true bridge=true ext=none extApplicable=none',
      );
    });

    test('empty display report is none, distinct from unreported', () {
      enable();
      HdrOutputDiagnostics.capability(caps(types: const <int>{}));
      expect(lines.single, contains('displayHdrTypes=none'));
    });
  });

  group('classify layer', () {
    test('decoder facts golden line', () {
      enable();
      const HdrSourceClassifier()
          .classify(videoParams: const VideoParams(gamma: 'pq', primaries: 'bt.2020'));
      expect(
        lines.single,
        'HdrDiag HDR classify: origin=facts codec=none transfer=pq '
        'primaries=bt.2020 meta=none dv=none compat=none el=false',
      );
      expect(
        keysOf(lines.single),
        <String>['origin', 'codec', 'transfer', 'primaries', 'meta', 'dv',
            'compat', 'el'],
      );
    });

    test('facts with DV profile carry dv/compat, hint fills nothing silently',
        () {
      enable();
      const HdrSourceClassifier().classify(
        videoParams: const VideoParams(gamma: 'hlg', primaries: 'bt.2020'),
        dolbyVisionProfile: 8,
        hint: p84,
      );
      expect(
        lines.single,
        'HdrDiag HDR classify: origin=facts codec=hevc transfer=hlg '
        'primaries=bt.2020 meta=dolbyVision dv=8 compat=4 el=false',
      );
    });

    test('hint without facts keeps the hint origin', () {
      enable();
      const HdrSourceClassifier().classify(hint: hdr10);
      expect(
        lines.single,
        'HdrDiag HDR classify: origin=hint codec=hevc transfer=pq '
        'primaries=bt.2020 meta=none dv=none compat=none el=false',
      );
    });

    test('nothing known is the default origin with unknown values', () {
      enable();
      const HdrSourceClassifier().classify();
      expect(
        lines.single,
        'HdrDiag HDR classify: origin=default codec=none transfer=none '
        'primaries=none meta=none dv=none compat=none el=unknown',
      );
    });
  });

  group('predict layer', () {
    test('full candidate list with unsupported and gate skips (golden)', () {
      enable();
      // P8.4 on the LYA-like snapshot with the default policy: the native DV
      // strategy is verified since 2026-10-10 but this snapshot has no DV
      // decoder, so the realizer refuses it (nativeDvUnavailable); the RPU
      // reshape is behind the experimental gate, direct, the PQ conversion
      // (verified since 2026-10-10) and tone-map are feasible.
      HdrRoutePlanner.plan(source: p84, capabilities: caps());
      expect(
        lines.single,
        'HdrDiag HDR predict: source=hevc,hlg,bt.2020,dolbyVision,8,4,false '
        'class=dvP84 selected=baseLayerDirect maturity=verified '
        'presentation=nativeHdr confidence=verified playable=true '
        'candidates=nativeDolbyVision:nativeDvUnavailable,'
        'baseLayerDirect:ok,'
        'baseLayerConvert:ok,'
        'metadataReshape:experimentalStrategySkipped,'
        'toneMapSdr:ok',
      );
      expect(
        keysOf(lines.single),
        <String>[
          'source',
          'class',
          'selected',
          'maturity',
          'presentation',
          'confidence',
          'playable',
          'candidates',
        ],
      );
    });

    test('every candidate and skip reason appears for the gated P8.4', () {
      enable();
      HdrRoutePlanner.plan(source: p84, capabilities: caps());
      final candidates =
          lines.single.split('candidates=')[1].split(',');
      expect(candidates, <String>[
        'nativeDolbyVision:nativeDvUnavailable',
        'baseLayerDirect:ok',
        'baseLayerConvert:ok',
        'metadataReshape:experimentalStrategySkipped',
        'toneMapSdr:ok',
      ]);
    });

    test('P5 without the pipeline logs playable=false with the block reason',
        () {
      enable();
      HdrRoutePlanner.plan(
          source: p5, capabilities: caps(p5Pipeline: false));
      expect(lines.single, contains('playable=false'));
      expect(lines.single, contains('metadataReshape:p5PipelineUnavailable'));
      expect(lines.single, contains('toneMapSdr:p5PipelineUnavailable'));
    });
  });

  group('decision layer (session hooks)', () {
    test('plan phase and applied phase both carry candidates and generation',
        () async {
      enable();
      final backend = FakeBackend()
        ..factsForOpen.add(facts(gamma: 'pq'))
        ..factsForOpen.add(facts(gamma: 'pq'));
      final session = makeSession(backend: backend, capabilities: caps());
      await session.open(media, hint: hdr10);
      await pumpEventQueueTimes(3);

      final decisions =
          lines.where((l) => l.startsWith('HdrDiag HDR decision:')).toList();
      expect(decisions, hasLength(2));

      const expectedKeys = <String>[
        'phase', 'gen', 'origin', 'source', 'class', 'selected', 'maturity',
        'presentation', 'confidence', 'vo', 'hwdec', 'output', 'topology',
        'surface', 'stripRpu', 'hwdecCurrent', 'requested', 'path',
        'readback', 'verified', 'degrade', 'candidates',
      ];
      expect(keysOf(decisions[0]), expectedKeys);
      expect(keysOf(decisions[1]), expectedKeys);

      // Plan phase: hint origin, no observation yet, unverified.
      expect(decisions[0], contains('phase=plan gen=1'));
      expect(decisions[0], contains('origin=hint'));
      expect(
        decisions[0],
        contains('source=hevc,pq,bt.2020,none,none,none,false class=hdr10'),
      );
      expect(decisions[0], contains('selected=baseLayerDirect'));
      expect(decisions[0], contains('vo=mediacodec_embed hwdec=mediacodec'));
      expect(decisions[0], contains('output=pq topology=platformView'));
      expect(decisions[0], contains('surface=none stripRpu=false'));
      expect(
        decisions[0],
        contains('hwdecCurrent=none requested=none path=none '
            'readback=none verified=false degrade=none'),
      );
      expect(
        decisions[0],
        contains('candidates=baseLayerDirect:ok,'
            'baseLayerConvert:ok,'
            'toneMapSdr:ok'),
      );

      // Applied phase: same generation, verified, with the observation.
      expect(decisions[1], contains('phase=applied gen=1'));
      expect(decisions[1], contains('selected=baseLayerDirect'));
      expect(decisions[1], contains('hwdecCurrent=mediacodec'));
      expect(decisions[1], contains('verified=true'));
      await session.dispose();
    });

    test('a dataspace route logs requested/path/readback in the applied '
        'decision', () async {
      enable();
      // Force a dataspace route: an HLG-only display has no PQ support, so
      // the conversion targets HLG (dataspace hlg) with the gate open.
      final backend = FakeBackend()
        ..factsForOpen.add(facts(gamma: 'pq'))
        ..factsForOpen.add(facts(gamma: 'pq'));
      final session = makeSession(
        backend: backend,
        capabilities: caps(types: const {3}),
        policy: const HdrRoutingPolicy(allowExperimental: true),
      );
      await session.open(media, hint: hdr10);
      await pumpEventQueueTimes(3);

      final applied = lines
          .where((l) => l.startsWith('HdrDiag HDR decision:'))
          .where((l) => l.contains('phase=applied'))
          .single;
      expect(applied, contains('surface=hlg'));
      expect(applied, contains('requested=hlg path=ext:lya-pq'));
      expect(applied, contains('readback=DATASPACE_BT2020_PQ'));
      await session.dispose();
    });
  });

  group('readback layer', () {
    test('success golden line', () {
      enable();
      HdrOutputDiagnostics.readback(
        requested: 'pq',
        path: 'ext:lya-pq',
        applied: true,
        readback: 'DATASPACE_BT2020_PQ',
      );
      expect(
        lines.single,
        'HdrDiag HDR readback: requested=pq path=ext:lya-pq applied=true '
        'readback=DATASPACE_BT2020_PQ',
      );
      expect(
        keysOf(lines.single),
        <String>['requested', 'path', 'applied', 'readback'],
      );
    });

    test('failure carries the none path and applied=false', () {
      enable();
      HdrOutputDiagnostics.readback(
        requested: 'pq',
        path: 'none',
        applied: false,
        readback: 'none',
      );
      expect(
        lines.single,
        'HdrDiag HDR readback: requested=pq path=none applied=false '
        'readback=none',
      );
    });
  });

  group('degrade layer (session hook)', () {
    test('every degradation step is logged with reason, from and to',
        () async {
      enable();
      final backend = FakeBackend()
        ..attemptScripts.addAll(const [
          AttemptScript(dataSpaceApplyFailed: true),
          AttemptScript(bindTimeout: true),
        ])
        ..factsForOpen.add(facts(gamma: 'hlg', profile: 8))
        ..factsForOpen.add(facts(gamma: 'hlg', profile: 8))
        ..factsForOpen.add(facts(gamma: 'hlg', profile: 8));
      final policy = const HdrRoutingPolicy(
        preferences: {
          HdrSourceClass.dvP84: [
            HdrStrategy.baseLayerConvert,
            HdrStrategy.baseLayerDirect,
            HdrStrategy.toneMapSdr,
          ],
        },
        allowExperimental: true,
      );
      final session = makeSession(
          backend: backend, capabilities: caps(), policy: policy);
      await session.open(media, hint: p84);
      await pumpEventQueueTimes(3);

      final degrades =
          lines.where((l) => l.startsWith('HdrDiag HDR degrade:')).toList();
      expect(degrades, hasLength(2));
      expect(degrades[0],
          startsWith('HdrDiag HDR degrade: gen=1 '
              'reason=dataSpaceApplyFailed from=baseLayerConvert '
              'to=baseLayerDirect diagnostic=HdrDataSpaceApplyException'));
      expect(degrades[1],
          startsWith('HdrDiag HDR degrade: gen=1 '
              'reason=outputBindTimeout from=baseLayerDirect '
              'to=toneMapSdr diagnostic=TimeoutException'));
      // The applied decision reports why the final route degraded.
      final applied = lines
          .where((l) => l.startsWith('HdrDiag HDR decision:'))
          .where((l) => l.contains('phase=applied'))
          .single;
      expect(applied, contains('degrade=outputBindTimeout'));
      expect(applied, contains('selected=toneMapSdr'));
      await session.dispose();
    });
  });

  group('recover layer (session hook)', () {
    test('capability changes log the snapshot summary; recovery never '
        'upgrades', () async {
      enable();
      final backend = FakeBackend()
        ..factsForOpen.add(facts(gamma: 'pq'))
        ..factsForOpen.add(facts(gamma: 'pq'))
        ..factsForOpen.add(facts(gamma: 'pq'));
      final session = makeSession(backend: backend, capabilities: caps());
      await session.open(media, hint: hdr10);
      await pumpEventQueueTimes(3);
      expect(lines.where((l) => l.startsWith('HdrDiag HDR recover:')),
          isEmpty);

      // Loss: degrade + rebuild; the capability snapshot is logged.
      await session.handleCapabilitiesChanged(caps(types: const <int>{}));
      await pumpEventQueueTimes(3);
      expect(
        lines.where((l) => l.startsWith('HdrDiag HDR degrade:')).single,
        startsWith('HdrDiag HDR degrade: gen=1 '
            'reason=capabilityLost from=baseLayerDirect to=toneMapSdr'),
      );

      // Recovery: only the event (and its log line), no route upgrade.
      await session.handleCapabilitiesChanged(caps());
      await pumpEventQueueTimes(3);
      final recovers =
          lines.where((l) => l.startsWith('HdrDiag HDR recover:')).toList();
      expect(recovers, hasLength(2));
      // The loss snapshot: the empty type set renders as none.
      expect(recovers[0], contains('gen=1'));
      expect(recovers[0], contains('displayHdrTypes=none'));
      expect(recovers[1], contains('gen=2'));
      expect(recovers[1], contains('displayHdrTypes=1,2,3'));
      expect(session.report.value.actual!.strategy, HdrStrategy.toneMapSdr);
      await session.dispose();
    });
  });
}

Future<void> pumpEventQueueTimes(int times) async {
  for (var i = 0; i < times; i++) {
    await pumpEventQueue();
  }
}
