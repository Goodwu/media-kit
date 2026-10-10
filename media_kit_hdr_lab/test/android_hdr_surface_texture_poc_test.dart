// ignore_for_file: implementation_imports
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:media_kit_hdr_lab/common/android_surface_texture_experiment.dart';
import 'package:media_kit_hdr_lab/common/sources/android_hdr_player_backend.dart'
    show AndroidSurfaceTexturePoc;

/// WP-C SurfaceTexture PoC (phase1-design-spec §5, plan §7): the opt-in
/// define, the production realizer's baseLayerConvert hwdec override, the
/// independent experiment class (the legacy copy validator is never
/// relaxed), and the sticky post-open version-evidence verdict.
void main() {
  test('define wiring: empty define is off and never touches routed hwdec',
      () {
    if (AndroidSurfaceTexturePoc.define.isEmpty) {
      expect(AndroidSurfaceTexturePoc.enabled, isFalse);
      expect(AndroidSurfaceTexturePoc.hwdecToWrite('mediacodec-copy'),
          'mediacodec-copy');
      expect(
          AndroidSurfaceTexturePoc.hwdecToWrite('mediacodec'), 'mediacodec');
    } else {
      expect(AndroidSurfaceTexturePoc.enabled, isTrue);
    }
  });
  test('enabled override replaces only the hwdec write value', () {
    expect(
        AndroidSurfaceTexturePoc.hwdecToWrite('mediacodec-copy',
            enabled: true),
        'surfacetexture');
    expect(AndroidSurfaceTexturePoc.hwdecToWrite('mediacodec', enabled: true),
        'surfacetexture');
    expect(AndroidSurfaceTexturePoc.hwdecToWrite('no', enabled: true),
        'surfacetexture');
    expect(
        AndroidSurfaceTexturePoc.hwdecToWrite('mediacodec-copy',
            enabled: false),
        'mediacodec-copy');
  });
  test('realizer baseLayerConvert override: only the hwdec field changes',
      () {
    // The routed hwdec at the baseLayerConvert decision point for API 24 is
    // mediacodec-copy; the PoC define replaces it with surfacetexture.
    expect(HdrStrategyRealizer.surfaceTexturePocHwdec('mediacodec-copy',
        define: 'on'), 'surfacetexture');
    expect(HdrStrategyRealizer.surfaceTexturePocHwdec('mediacodec',
        define: 'on'), 'surfacetexture');
    // Empty define (default): identity for every routed hwdec.
    expect(HdrStrategyRealizer.surfaceTexturePocHwdec('mediacodec-copy',
        define: ''), 'mediacodec-copy');
    expect(HdrStrategyRealizer.surfaceTexturePocHwdec('mediacodec',
        define: ''), 'mediacodec');
    // Production define state consistency with the lab helper.
    expect(
        HdrStrategyRealizer.surfaceTexturePocHwdec('mediacodec-copy'),
        AndroidSurfaceTexturePoc.hwdecToWrite('mediacodec-copy'));
  });
  const transfer = String.fromEnvironment(
      'MEDIA_KIT_ANDROID_CONVERT_SURFACE_TRANSFER',
      defaultValue: 'pq');
  const experiment = AndroidSurfaceTextureExperiment(
      transfer, transfer == 'pq' ? 'full' : 'limited');
  const caps = HdrCapabilities(
      sdkInt: 24,
      displayHdrTypes: {2},
      hevcDecoders: [],
      dolbyVisionDecoders: [],
      p5PipelineAvailable: false,
      dataSpaceBridgeLoaded: false,
      dataSpaceExt: HdrDataSpaceExtInfo(id: 'lg-pq', applicable: true));
  // Device-equivalent capability snapshot of the OES diagnostic round: the
  // LG reports both DOLBY_VISION(1) and HDR10(2), the lg-pq dataspace
  // extension is applicable.
  const deviceCaps = HdrCapabilities(
      sdkInt: 24,
      displayHdrTypes: {1, 2},
      hevcDecoders: [],
      dolbyVisionDecoders: [],
      p5PipelineAvailable: false,
      dataSpaceBridgeLoaded: false,
      dataSpaceExt: HdrDataSpaceExtInfo(id: 'lg-pq', applicable: true));
  const source = HdrSourceDescriptor(
      codec: 'hevc',
      transfer: 'hlg',
      dynamicMetadata: HdrDynamicMetadata.dolbyVision,
      dvProfile: 8,
      dvCompatibilityId: 4,
      enhancementLayer: false);
  HdrRoutePrediction plan({
    HdrSourceDescriptor input = source,
    Map<String, HdrDegradeReason> excluded = const {},
    HdrCapabilities capabilities = caps,
    HdrOutputPreference preference = HdrOutputPreference.auto,
  }) =>
      experiment.plan(
          source: input,
          capabilities: capabilities,
          policy: HdrRoutingPolicy.defaults,
          preference: preference,
          excluded: excluded);
  test('experiment admits only the overridden surfacetexture route', () {
    if (AndroidSurfaceTexturePoc.enabled) {
      // The realizer realized the overridden route; the independent
      // validator accepts exactly it (no copy/SDR relaxation).
      final prediction = plan();
      expect(prediction.playable, isTrue);
      final route = prediction.selected.route!;
      expect(route.strategy, HdrStrategy.baseLayerConvert);
      expect(route.hwdec, 'surfacetexture');
      expect(route.vo, 'gpu-next');
      expect(route.topology, HdrTopology.platformView);
      expect(route.outputTransfer, HdrOutputTransfer.pq);
      expect(route.targetTrc, 'pq');
      expect(route.surfaceTransfer, transfer);
    } else {
      // Define off: the realizer still routes mediacodec-copy and the
      // independent validator rejects it (fail-closed; the legacy copy
      // validator stays untouched and continues to admit copy routes).
      expect(plan, throwsA(isA<HdrPlaybackBlocked>()));
    }
  });
  test(
      'hlg convert maturity: the double-define diag opt-in overrides an '
      'outer allowExperimental=false policy', () {
    // Device OES-round contract: the named hlg patch fixture classifies as a
    // bare HLG source (codec null, transfer hlg); hlg x baseLayerConvert is
    // `experimental` in the production maturity table, and the device open
    // ran with the outer Session policy at allowExperimental=false (the
    // defaults below), which made the planner skip the convert route and the
    // validator throw the generic unsupportedStrategy. The experiment class
    // is the explicit diagnostic opt-in: its own planner call opens the
    // maturity gate deliberately, without touching the production table or
    // the default define-off behavior.
    expect(HdrRoutingPolicy.defaults.allowExperimental, isFalse);
    final hlgSource = HdrSourceDescriptor.fromKind(HdrMediaKind.hlg);
    expect(hlgSource.codec, isEmpty);
    expect(hlgSource.transfer, 'hlg');
    if (AndroidSurfaceTexturePoc.enabled) {
      final prediction = plan(input: hlgSource, capabilities: deviceCaps);
      expect(prediction.playable, isTrue);
      final route = prediction.selected.route!;
      expect(route.strategy, HdrStrategy.baseLayerConvert);
      expect(route.hwdec, 'surfacetexture');
      expect(route.vo, 'gpu-next');
      expect(route.topology, HdrTopology.platformView);
      expect(route.outputTransfer, HdrOutputTransfer.pq);
      expect(route.targetTrc, 'pq');
      expect(route.surfaceTransfer, transfer);
    } else {
      // Define off: the planner now realizes the hlg convert route (the
      // maturity override), but the validator still fail-closes on the
      // non-overridden copy hwdec — the legacy default behavior is intact.
      expect(() => plan(input: hlgSource, capabilities: deviceCaps),
          throwsA(isA<HdrPlaybackBlocked>()));
    }
  });
  test('unknown hint, SDR and off preference never open a PoC route', () {
    expect(() => plan(input: const HdrSourceDescriptor()),
        throwsA(isA<HdrPlaybackBlocked>()));
    expect(() => plan(input: const HdrSourceDescriptor(transfer: 'bt.1886')),
        throwsA(isA<HdrPlaybackBlocked>()));
    expect(() => plan(preference: HdrOutputPreference.off),
        throwsA(isA<HdrPlaybackBlocked>()));
  });
  test('dependency failures and SDR cannot fall back into the experiment',
      () {
    for (final dependency in [
      HdrRouteDependency.hwdecMediacodecCopy,
      HdrRouteDependency.dataspacePq,
      HdrRouteDependency.topologyPlatformView
    ]) {
      expect(() => plan(excluded: {dependency: HdrDegradeReason.hwdecMismatch}),
          throwsA(isA<HdrPlaybackBlocked>()));
    }
  });
  test('output contract pairs are explicit; auto and mismatches fail', () {
    for (final pair in [
      const AndroidSurfaceTextureExperiment('pq', 'full'),
      const AndroidSurfaceTextureExperiment('pq-itu', 'limited')
    ]) {
      expect(pair.validate, returnsNormally);
    }
    for (final pair in [
      const AndroidSurfaceTextureExperiment('pq', 'limited'),
      const AndroidSurfaceTextureExperiment('pq-itu', 'full'),
      const AndroidSurfaceTextureExperiment('pq-itu', '')
    ]) {
      expect(pair.validate, throwsStateError);
    }
  });
  test('route lock rejects dataspace perform probe before preparation', () {
    expect(() => experiment.validateAdmission(dataSpacePerformProbe: true),
        throwsStateError);
    expect(() => experiment.validateAdmission(dataSpacePerformProbe: false),
        returnsNormally);
  });
  test(
      'missing MKSURF version evidence hard-fails only when logs are '
      'available', () {
    expect(
        AndroidSurfaceTexturePoc.versionLogFailure(
            logsAvailable: true, versionObserved: true),
        isNull);
    expect(
        AndroidSurfaceTexturePoc.versionLogFailure(
            logsAvailable: true, versionObserved: false),
        contains(AndroidSurfaceTexturePoc.versionMarker));
    expect(
        AndroidSurfaceTexturePoc.versionLogFailure(
            logsAvailable: false, versionObserved: false),
        isNull);
  });
  test('PoC verdict: software fallback and missing version both hard-fail',
      () {
    // run2 scenario: bridge init failure lets vd_lavc fall back to software
    // decoding (hwdec-current=no) while the session only degrades; the
    // verdict must report the mismatch (V2 review, no software fallback).
    final mismatch = AndroidSurfaceTexturePoc.verdictFailure(
        hwdecCurrent: 'no', versionObserved: false);
    expect(mismatch, isNotNull);
    expect(mismatch, contains('hwdec-current=no'));
    expect(mismatch, contains('expected=surfacetexture'));
    // A copy route observed instead of the importer fails the same way.
    final copy = AndroidSurfaceTexturePoc.verdictFailure(
        hwdecCurrent: 'mediacodec-copy', versionObserved: true);
    expect(copy, isNotNull);
    expect(copy, contains('hwdec-current=mediacodec-copy'));
    expect(copy, contains('expected=surfacetexture'));
    // Importer active but version evidence missing fails too.
    expect(
        AndroidSurfaceTexturePoc.verdictFailure(
            hwdecCurrent: 'surfacetexture', versionObserved: false),
        contains(AndroidSurfaceTexturePoc.versionMarker));
    // Complete evidence passes.
    expect(
        AndroidSurfaceTexturePoc.verdictFailure(
            hwdecCurrent: 'surfacetexture', versionObserved: true),
        isNull);
  });
  test('version marker matches captured MKSURF entries only', () {
    expect(
        AndroidSurfaceTexturePoc.isVersionEntry(
            'cplayer v MKSURF: version candidate-20261008'),
        isTrue);
    expect(AndroidSurfaceTexturePoc.isVersionEntry('MKSURF: latch ts=1'),
        isFalse);
  });
}
