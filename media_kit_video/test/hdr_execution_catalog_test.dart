import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' show Media, VideoParams;
import 'package:media_kit_video/src/hdr/android_mediacodec_configuration.dart';
import 'package:media_kit_video/src/hdr/hdr_capabilities.dart';
import 'package:media_kit_video/src/hdr/hdr_decoder_review.dart';
import 'package:media_kit_video/src/hdr/hdr_native_dv_option_owner.dart';
import 'package:media_kit_video/src/hdr/hdr_open_coordinator.dart';
import 'package:media_kit_video/src/hdr/hdr_open_plan.dart';
import 'package:media_kit_video/src/hdr/hdr_output_contract.dart';
import 'package:media_kit_video/src/hdr/hdr_output_slot.dart';
import 'package:media_kit_video/src/hdr/hdr_route.dart';
import 'package:media_kit_video/src/hdr/hdr_route_planner.dart';
import 'package:media_kit_video/src/hdr/hdr_source_descriptor.dart';
import 'package:media_kit_video/src/hdr/hdr_strategy.dart';
import 'package:media_kit_video/src/hdr/hdr_strategy_realizer.dart';
import 'package:media_kit_video/src/hdr/hdr_video_session.dart';
import 'package:media_kit_video/src/routing/video_decoder_support.dart';
import 'package:media_kit_video/src/routing/video_source_spec.dart';

const sdr = HdrSourceDescriptor(
    codec: 'hevc',
    transfer: 'bt.1886',
    primaries: 'bt.709',
    enhancementLayer: false);
const hdr10 = HdrSourceDescriptor(
    codec: 'hevc',
    transfer: 'pq',
    primaries: 'bt.2020',
    enhancementLayer: false);
HdrCapabilities caps(
        {int sdk = 29, bool pipeline = true, VideoSourceSupport? support}) =>
    HdrCapabilities(
        sdkInt: sdk,
        displayHdrTypes: const {1, 2, 3},
        hevcDecoders: const [],
        dolbyVisionDecoders: const [],
        p5PipelineAvailable: pipeline,
        dataSpaceBridgeLoaded: true,
        dataSpaceExt: null,
        sourceSupport: support);

// Runs the real Session, planner, reviewer and OutputSlot contract replacement.
// Native property/Surface execution is synthetic and does not prove a device.
class Backend implements HdrOpenBackend<HdrOpenPlan> {
  Backend(this.source) {
    slot = HdrOutputSlot<HdrOutputContract>(
        initial: null,
        voOf: (value) async => value.vo,
        create: (contract) {
          resources.add('create:${contract.requestedHwdec}');
          return contract;
        },
        publish: (_) {},
        waitReady: (_) async {},
        disposeForRebuild: (value) async {
          resources.add('dispose:${value.requestedHwdec}');
        });
  }
  final HdrSourceDescriptor source;
  final configured = <HdrRoute>[],
      opened = <HdrRoute>[],
      reviewed = <HdrRoute>[];
  final resources = <String>[];
  final reviewErrors = <String, Object>{};
  final pixelOverrides = <String, String>{};
  final hwdecOverrides = <String, String>{};
  late HdrOutputSlot<HdrOutputContract> slot;
  bool failed = false, cleanupFails = false;
  String? observedHwdec;
  Future<void>? reviewHold;
  @override
  Future<void> validate(HdrOpenPlan plan) async {}
  @override
  Future<void> stop() async {
    if (failed && cleanupFails) throw StateError('cleanup debt');
  }

  @override
  Future<void> resetOwnedConfiguration() async {}
  @override
  Future<void> prepareOutput(HdrOpenPlan plan) =>
      slot.ensure(HdrOutputContract.fromRoute(plan.route));
  @override
  Future<void> configure(HdrOpenPlan plan) async {
    configured.add(plan.route);
  }

  @override
  Future<void> waitForOutput(HdrOpenPlan plan) async {}
  @override
  Future<void> open(HdrOpenPlan plan,
      {Duration? start, required bool play}) async {
    opened.add(plan.route);
  }

  @override
  Future<HdrReviewFacts> reviewFacts(HdrOpenPlan plan) async {
    reviewed.add(plan.route);
    await reviewHold;
    final error = reviewErrors[plan.route.hwdec];
    if (error != null) {
      failed = true;
      throw error;
    }
    final hwdec = hwdecOverrides[plan.route.hwdec] ?? plan.route.hwdec;
    observedHwdec = hwdec;
    final pixel = pixelOverrides[plan.route.hwdec] ??
        (hwdec == 'mediacodec' ? 'mediacodec' : 'yuv420p');
    final config = hwdec == 'no'
        ? null
        : AndroidMediaCodecConfiguration.parse(
            '{"api":1,"mime":"video/hevc","codec":"c2.hevc","native-dv-active":false}');
    return HdrReviewFacts(
        path: plan.media.uri,
        codec: 'hevc',
        hwdecCurrent: hwdec,
        videoParams: VideoParams(
            pixelformat: pixel,
            gamma: source.transfer ?? 'pq',
            primaries: source.primaries ?? 'bt.2020'),
        dolbyVisionProfile: source.dvProfile,
        dvCompatibilityId: source.dvCompatibilityId,
        dvElPresent: source.dynamicMetadata == HdrDynamicMetadata.dolbyVision
            ? source.enhancementLayer
            : null,
        decoderObservation: HdrDecoderObservation(
            playlistEntryId: reviewed.length,
            fileLoadedEpoch: reviewed.length,
            decoder: hwdec == 'no' ? 'hevc' : 'hevc_mediacodec',
            decoderDescription: '',
            hwdec: hwdec,
            pixelFormat: pixel,
            hwPixelFormat: '',
            mediaCodecConfiguration: config));
  }

  @override
  HdrBackendObservation observe() =>
      HdrBackendObservation(hwdecCurrent: observedHwdec);
}

HdrVideoSession session(Backend backend,
        {HdrOutputPreference preference = HdrOutputPreference.auto,
        HdrCapabilities? capabilities}) =>
    HdrVideoSession.forTesting(
        backend: backend,
        isAndroid: true,
        capabilitiesProvider: () async => capabilities ?? caps(),
        preference: preference);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final preference in HdrOutputPreference.values) {
    test('real Session direct to copy to software is finite with $preference',
        () async {
      final backend = Backend(sdr)
        ..reviewErrors.addAll({
          'mediacodec': StateError('direct request failed'),
          'mediacodec-copy': StateError('copy request failed')
        });
      final player = session(backend, preference: preference);
      await player.open(Media('test://sdr'), hint: sdr);
      expect(backend.configured.map((r) => r.hwdec),
          ['mediacodec', 'mediacodec-copy', 'no']);
      expect(backend.opened.map((r) => r.hwdec),
          ['mediacodec', 'mediacodec-copy', 'no']);
      expect(backend.reviewed.map((r) => r.hwdec),
          ['mediacodec', 'mediacodec-copy', 'no']);
      expect(backend.resources, [
        'create:mediacodec',
        'dispose:mediacodec',
        'create:mediacodec-copy',
        'dispose:mediacodec-copy',
        'create:no'
      ]);
      final report = player.report.value;
      expect(report.verified, isTrue);
      expect(report.requested!.hwdec, 'mediacodec');
      expect(report.actual!.hwdec, 'no');
      expect(report.decoderObservation!.softwareDecoded, isTrue);
      expect(report.prediction!.confidence, HdrPredictionConfidence.unverified);
      expect(report.attemptedRoutes.map((r) => r.hwdec),
          ['mediacodec', 'mediacodec-copy', 'no']);
      expect(() => report.attemptedRoutes.clear(), throwsUnsupportedError);
      await player.dispose();
    });
  }
  test('capability recovery retains reviewed copy/software full identity', () async {
    for (final software in [false, true]) {
      final backend = Backend(sdr)..reviewErrors['mediacodec'] = StateError('direct');
      if (software) backend.reviewErrors['mediacodec-copy'] = StateError('copy');
      final player = session(backend);
      await player.open(Media('test://sdr'), hint: sdr);
      final actual = player.report.value.actual, opens = backend.opened.length;
      await player.handleCapabilitiesChanged(caps());
      expect(backend.opened, hasLength(opens));
      expect(player.report.value.actual, actual);
      expect(player.report.value.verified, isTrue);
      await player.dispose();
    }
  });
  test('only distinct SDR requests can use the widened review reopen budget',
      () async {
    final backend = Backend(sdr)
      ..hwdecOverrides.addAll({
        'mediacodec': 'no',
        'mediacodec-copy': 'no',
      });
    final player = session(backend, preference: HdrOutputPreference.off);
    await player.open(Media('test://sdr'), hint: sdr);
    expect(backend.configured.map((r) => r.hwdec),
        ['mediacodec', 'mediacodec-copy', 'no']);
    expect(backend.opened.toSet(), hasLength(3));
    expect(player.report.value.verified, isTrue);
    expect(player.report.value.actual!.hwdec, 'no');
    expect(player.report.value.decoderObservation!.pixelFormat, 'yuv420p');
    await player.dispose();
  });
  test('unknown and hardware formats never serve as CPU upload evidence',
      () async {
    for (final format in [
      'unknown-format',
      'vulkan',
      'vaapi',
      'cuda',
      'mediacodec',
      'surfacetexture'
    ]) {
      final backend = Backend(sdr)
        ..reviewErrors['mediacodec'] = StateError('direct')
        ..reviewErrors['mediacodec-copy'] = StateError('copy')
        ..pixelOverrides['no'] = format;
      final player = session(backend);
      await player.open(Media('test://sdr'), hint: sdr);
      expect(backend.configured.map((r) => r.hwdec),
          ['mediacodec', 'mediacodec-copy', 'no']);
      expect(player.report.value.verified, isFalse, reason: format);
      expect(player.report.value.degradeReason,
          HdrDegradeReason.routeReviewMismatch);
      await player.dispose();
    }
  });
  test('current CPU formats are observations, not decoder census authorization',
      () async {
    for (final format in [
      'yuv420p',
      'yuv420p10le',
      'nv12',
      'p010',
      'gbrp',
      'rgba'
    ]) {
      final backend = Backend(sdr)
        ..reviewErrors['mediacodec'] = StateError('direct')
        ..reviewErrors['mediacodec-copy'] = StateError('copy')
        ..pixelOverrides['no'] = format;
      final player = session(backend);
      await player.open(Media('test://sdr'), hint: sdr);
      expect(player.report.value.verified, isTrue, reason: format);
      expect(player.report.value.prediction!.confidence,
          HdrPredictionConfidence.unverified);
      await player.dispose();
    }
  });
  test('real tone-map candidates preserve SDR processing for HDR input',
      () async {
    final backend = Backend(hdr10)
      ..reviewErrors.addAll({
        'mediacodec': StateError('direct failed'),
        'mediacodec-copy': StateError('copy failed')
      });
    final player = session(backend, preference: HdrOutputPreference.off);
    await player.open(Media('test://hdr'), hint: hdr10);
    expect(backend.configured.map((r) => r.hwdec),
        ['mediacodec', 'mediacodec-copy', 'no']);
    for (final route in backend.configured) {
      expect(route.strategy, HdrStrategy.toneMapSdr);
      expect(route.presentation, HdrPresentation.toneMappedSdr);
      expect(route.targetPrim, 'bt.709');
      expect(route.targetTrc, 'bt.1886');
    }
    expect(player.report.value.source, hdr10);
    expect(player.report.value.actual!.outputTransfer, HdrOutputTransfer.sdr);
    await player.dispose();
  });
  test(
      'import-only failure permits independent copy while decoder failure skips both MC requests',
      () async {
    for (final dependency in [
      HdrRouteDependency.importMediacodec,
      HdrRouteDependency.decoderMediacodec
    ]) {
      final backend = Backend(sdr)
        ..reviewErrors['mediacodec'] = HdrExecutionDependencyFailure(
            dependency, HdrDegradeReason.unsupportedStrategy);
      final player = session(backend);
      await player.open(Media('test://sdr'), hint: sdr);
      expect(
          backend.configured.map((r) => r.hwdec),
          dependency == HdrRouteDependency.importMediacodec
              ? ['mediacodec', 'mediacodec-copy']
              : ['mediacodec', 'no']);
      expect(player.report.value.verified, isTrue);
      await player.dispose();
    }
  });
  test(
      'ordinary HDR decoder failure excludes both SDR MC requests but retains FFmpeg',
      () async {
    final backend = Backend(hdr10)
      ..reviewErrors['mediacodec'] = const HdrExecutionDependencyFailure(
          HdrRouteDependency.decoderMediacodec,
          HdrDegradeReason.sourceDecodeUnsupported);
    final player = session(backend);
    await player.open(Media('test://hdr'), hint: hdr10);
    expect(backend.configured.map((r) => r.hwdec), ['mediacodec', 'no']);
    expect(backend.configured.first.strategy, HdrStrategy.baseLayerDirect);
    expect(backend.configured.last.strategy, HdrStrategy.toneMapSdr);
    expect(player.report.value.verified, isTrue);
    expect(player.report.value.degradeReason,
        HdrDegradeReason.sourceDecodeUnsupported);
    expect(
        player.report.value.prediction!.candidates.where(
            (c) => c.skipReason == HdrDegradeReason.sourceDecodeUnsupported),
        isNotEmpty);
    expect(player.report.value.actual!.dependencies,
        isNot(contains(HdrRouteDependency.decoderMediacodec)));
    await player.dispose();
  });
  test('shared presenter and CPU uploader failures cannot be forgotten',
      () async {
    final presenter = Backend(sdr)
      ..reviewErrors['mediacodec'] = const HdrExecutionDependencyFailure(
          HdrRouteDependency.presenterGpuTexture,
          HdrDegradeReason.unsupportedStrategy);
    final first = session(presenter);
    await expectLater(first.open(Media('test://sdr'), hint: sdr),
        throwsA(isA<HdrExecutionDependencyFailure>()));
    expect(presenter.configured, hasLength(1));
    expect(first.report.value.verified, isFalse);
    await first.dispose();
    final upload = Backend(sdr)
      ..reviewErrors.addAll({
        'mediacodec': StateError('direct failed'),
        'mediacodec-copy': const HdrExecutionDependencyFailure(
            HdrRouteDependency.importCpuUpload,
            HdrDegradeReason.unsupportedStrategy)
      });
    final second = session(upload);
    await expectLater(second.open(Media('test://sdr'), hint: sdr),
        throwsA(isA<HdrExecutionDependencyFailure>()));
    expect(upload.configured.map((r) => r.hwdec),
        ['mediacodec', 'mediacodec-copy']);
    expect(second.report.value.verified, isFalse);
    await second.dispose();
  });
  test('exhaustion visits each complete candidate once and does not loop',
      () async {
    final backend = Backend(sdr)
      ..reviewErrors.addAll({
        'mediacodec': StateError('direct'),
        'mediacodec-copy': StateError('copy'),
        'no': StateError('software')
      });
    final player = session(backend);
    await expectLater(
        player.open(Media('test://sdr'), hint: sdr), throwsStateError);
    expect(backend.configured.map((r) => r.hwdec),
        ['mediacodec', 'mediacodec-copy', 'no']);
    expect(player.report.value.verified, isFalse);
    expect(player.report.value.attemptedRoutes.map((r) => r.hwdec), ['mediacodec', 'mediacodec-copy', 'no']);
    expect(player.report.value.requested!.hwdec, 'mediacodec');
    await player.dispose();
  });
  test('cleanup debt prevents configure of an independent candidate', () async {
    final backend = Backend(sdr)
      ..cleanupFails = true
      ..reviewErrors['mediacodec'] = StateError('direct');
    final player = session(backend);
    await expectLater(
        player.open(Media('test://sdr'), hint: sdr), throwsStateError);
    expect(backend.configured, hasLength(1));
    expect(backend.resources, ['create:mediacodec']);
    backend.cleanupFails = false;
    await player.dispose();
  });
  test('unknown timeout, source identity and owner failures still abort',
      () async {
    final errors = <Object>[
      TimeoutException('unknown stage'),
      const HdrDecoderReviewFailure('source identity'),
      HdrNativeDvOptionFailure(null, {'owner': StateError('lost')}),
      HdrExecutionDependencyFailure(HdrRouteDependency.importMediacodec,
          HdrDegradeReason.unsupportedStrategy,
          cause: TimeoutException('unknown stage'))
    ];
    for (final error in errors) {
      final backend = Backend(sdr)..reviewErrors['mediacodec'] = error;
      final player = session(backend);
      await expectLater(
          player.open(Media('test://sdr'), hint: sdr), throwsA(same(error)));
      expect(backend.configured, hasLength(1));
      expect(player.report.value.verified, isFalse);
      await player.dispose();
    }
  });
  test(
      'copy still rejects hardware resource and never reports hypothetical software success',
      () async {
    final backend = Backend(sdr)
      ..reviewErrors['mediacodec'] = StateError('direct')
      ..pixelOverrides['mediacodec-copy'] = 'mediacodec';
    final player = session(backend);
    await player.open(Media('test://sdr'), hint: sdr);
    expect(backend.configured.map((r) => r.hwdec),
        ['mediacodec', 'mediacodec-copy']);
    expect(player.report.value.verified, isFalse);
    expect(player.report.value.degradeReason,
        HdrDegradeReason.routeReviewMismatch);
    await player.dispose();
  });
  test(
      'FFmpeg support stays unknown for supported and unsupported MC software census',
      () {
    for (final support in VideoSupport.values) {
      final declaration = VideoSourceSupport(
          source: VideoSourceSpec(codec: 'hevc'),
          censusComplete: true,
          decoders: [
            VideoDecoderSupport(
                name: 'android.software',
                mime: 'video/hevc',
                kind: VideoDecoderKind.software,
                support: support,
                reason: 'test',
                path: 'codec')
          ],
          reason: 'test');
      final capability = caps(support: declaration);
      final routes = HdrStrategyRealizer.realizeCandidates(
              HdrStrategy.sdrDirect,
              source: sdr,
              sourceClass: HdrSourceClass.sdr,
              capabilities: capability)
          .map((r) => r.route!)
          .toList();
      expect(capability.decoderSupportFor(routes.last), VideoSupport.unknown);
      final prediction = HdrRoutePlanner.plan(
          source: sdr,
          capabilities: capability,
          excluded: {
            HdrRouteDependency.decoderMediacodec:
                HdrDegradeReason.sourceDecodeUnsupported
          });
      expect(prediction.selected.route!.hwdec, 'no');
      expect(prediction.confidence, HdrPredictionConfidence.unverified);
    }
  });
  test('P5 processing and P8.4 stripping gates survive every SDR execution',
      () {
    const p5 = HdrSourceDescriptor(
        codec: 'hevc',
        dynamicMetadata: HdrDynamicMetadata.dolbyVision,
        dvProfile: 5,
        dvCompatibilityId: 0,
        enhancementLayer: false);
    const p84 = HdrSourceDescriptor(
        codec: 'hevc',
        transfer: 'hlg',
        primaries: 'bt.2020',
        dynamicMetadata: HdrDynamicMetadata.dolbyVision,
        dvProfile: 8,
        dvCompatibilityId: 4,
        enhancementLayer: false);
    final blocked = HdrStrategyRealizer.realizeCandidates(
        HdrStrategy.toneMapSdr,
        source: p5,
        sourceClass: HdrSourceClass.dvP5,
        capabilities: caps(pipeline: false));
    expect(blocked.every((r) => r.route == null), isTrue);
    for (final source in [p5, p84]) {
      final routes = HdrStrategyRealizer.realizeCandidates(
              HdrStrategy.toneMapSdr,
              source: source,
              sourceClass: HdrSourceClass.of(source),
              capabilities: caps())
          .map((r) => r.route!)
          .toList();
      expect(
          routes.map((r) => r.hwdec), ['mediacodec', 'mediacodec-copy', 'no']);
      expect(routes.every((r) => r.appliesDynamicMetadata == (source == p5)),
          isTrue);
      expect(routes.every((r) => r.stripDvRpu == (source == p84)), isTrue);
    }
  });
  test(
      'P5 and P8.4 actually execute all SDR variants with original source gates',
      () async {
    const p5 = HdrSourceDescriptor(
        codec: 'hevc',
        dynamicMetadata: HdrDynamicMetadata.dolbyVision,
        dvProfile: 5,
        dvCompatibilityId: 0,
        enhancementLayer: false);
    const p84 = HdrSourceDescriptor(
        codec: 'hevc',
        transfer: 'hlg',
        primaries: 'bt.2020',
        dynamicMetadata: HdrDynamicMetadata.dolbyVision,
        dvProfile: 8,
        dvCompatibilityId: 4,
        enhancementLayer: false);
    for (final source in [p5, p84]) {
      final backend = Backend(source)
        ..reviewErrors.addAll({
          'mediacodec': StateError('direct'),
          'mediacodec-copy': StateError('copy'),
        });
      final player = session(backend, preference: HdrOutputPreference.off);
      await player.open(Media('test://dv'), hint: source);
      expect(backend.configured.map((r) => r.hwdec),
          ['mediacodec', 'mediacodec-copy', 'no']);
      expect(player.report.value.verified, isTrue);
      expect(player.report.value.source!.dynamicMetadata,
          HdrDynamicMetadata.dolbyVision);
      expect(player.report.value.actual!.appliesDynamicMetadata, source == p5);
      expect(player.report.value.actual!.stripDvRpu, source == p84);
      await player.dispose();
    }
  });
  test('software catalog cannot bypass unresolved DV color/profile facts', () async {
    const unresolved = [
      HdrSourceDescriptor(codec: 'hevc', transfer: 'pq', primaries: 'bt.2020',
        dynamicMetadata: HdrDynamicMetadata.dolbyVision, enhancementLayer: false),
      HdrSourceDescriptor(codec: 'hevc', transfer: 'pq', primaries: 'bt.2020',
        dynamicMetadata: HdrDynamicMetadata.dolbyVision, dvProfile: 32, dvCompatibilityId: 0, enhancementLayer: false),
      HdrSourceDescriptor(codec: 'hevc', dynamicMetadata: HdrDynamicMetadata.dolbyVision,
        dvProfile: 8, enhancementLayer: false),
      HdrSourceDescriptor(codec: 'hevc', transfer: 'hlg', primaries: 'bt.2020',
        dynamicMetadata: HdrDynamicMetadata.dolbyVision, dvProfile: 8, dvCompatibilityId: 9, enhancementLayer: false),
    ];
    for (final source in unresolved) {
      final backend = Backend(source);
      final player = session(backend, preference: HdrOutputPreference.off);
      await player.open(Media('test://unknown-dv'), hint: source);
      expect(backend.configured, isEmpty);
      expect(backend.opened, isEmpty);
      expect(player.report.value.verified, isFalse);
      expect(player.report.value.degradeReason, HdrDegradeReason.sourceMetadataUnknown);
      await player.dispose();
    }
  });
  test(
      'API24 catalog preserves copy first and never inserts unsupported direct import',
      () {
    final prediction =
        HdrRoutePlanner.plan(source: sdr, capabilities: caps(sdk: 24));
    expect(prediction.candidates.map((c) => c.route!.hwdec),
        ['mediacodec-copy', 'no']);
  });
}
