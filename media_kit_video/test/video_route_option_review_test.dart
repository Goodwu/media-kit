import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' show Media, FileLoadedRecord;
import 'package:media_kit_video/src/hdr/android_mediacodec_configuration.dart';
import 'package:media_kit_video/src/hdr/hdr_decoder_review.dart';
import 'package:media_kit_video/src/hdr/hdr_native_dv_option_owner.dart';
import 'package:media_kit_video/src/hdr/hdr_native_dv_review_evidence.dart';
import 'package:media_kit_video/src/hdr/hdr_open_plan.dart';
import 'package:media_kit_video/src/hdr/hdr_route.dart';
import 'package:media_kit_video/src/hdr/hdr_route_planner.dart';
import 'package:media_kit_video/src/hdr/hdr_strategy.dart';
import 'package:media_kit_video/src/routing/video_decoder_support.dart';
import 'package:media_kit_video/src/routing/video_route_options.dart';
import 'package:media_kit_video/src/routing/video_route_option_review.dart';
import 'package:media_kit_video/src/routing/video_source_spec.dart';
import 'package:media_kit_video/src/video_controller/android_video_controller/platform_surface_release.dart';
import 'hdr_execution_catalog_test.dart' as catalog;

final source = VideoSourceSpec(codec: 'hevc', width: 1920, height: 1080);
final media = Media('test://require');
final hardware = EffectiveVideoRouteOptions.resolve(
    application: const VideoRouteOptions(
        experimental: true,
        decode: VideoRouteSelection.require(VideoDecodeTarget.hardware)));
HdrRoute route(String mode, {HdrStrategy strategy = HdrStrategy.sdrDirect}) {
  final prediction = HdrRoutePlanner.plan(
      source: catalog.sdr,
      capabilities: catalog.caps(),
      policy: const HdrRoutingPolicy(allowExperimental: true));
  return changed(
      prediction.candidates
          .firstWhere((c) => c.feasible && c.route!.hwdec == mode)
          .route!,
      strategy: strategy);
}

HdrRoute changed(HdrRoute r,
        {HdrStrategy? strategy, HdrOutputTransfer? outputTransfer}) =>
    HdrRoute(
        strategy: strategy ?? r.strategy,
        presentation: r.presentation,
        outputTransfer: outputTransfer ?? r.outputTransfer,
        appliesDynamicMetadata: r.appliesDynamicMetadata,
        topology: r.topology,
        vo: r.vo,
        hwdec: r.hwdec,
        targetPrim: r.targetPrim,
        targetTrc: r.targetTrc,
        surfaceTransfer: r.surfaceTransfer,
        stripDvRpu: r.stripDvRpu,
        dependencies: r.dependencies);
VideoDecoderSupport row(
        {String name = 'c2.hevc',
        String mime = 'video/hevc',
        String path = 'codec',
        VideoDecoderKind kind = VideoDecoderKind.hardware,
        VideoSupport support = VideoSupport.supported}) =>
    VideoDecoderSupport(
        name: name,
        mime: mime,
        path: path,
        kind: kind,
        support: support,
        reason: 'synthetic');
HdrOpenPlan plan(
    {String mode = 'mediacodec',
    bool native = false,
    List<VideoDecoderSupport>? rows,
    VideoSourceSpec? declared,
    bool missingSource = false,
    VideoSourceSpec? bound}) {
  final caps = catalog.caps(
      support: VideoSourceSupport(
          source: declared ?? source,
          censusComplete: true,
          decoders: rows ??
              [
                row(
                    mime: native ? 'video/dolby-vision' : 'video/hevc',
                    path: native ? 'nativeDv' : 'codec')
              ],
          reason: 'test'));
  final prediction = HdrRoutePlanner.plan(
      source: catalog.sdr,
      capabilities: caps,
      policy: const HdrRoutingPolicy(allowExperimental: true));
  return HdrOpenPlan(
      media: media,
      source: catalog.sdr,
      sourceOrigin: HdrReportSource.hint,
      capabilities: caps,
      prediction: prediction,
      route: route(mode,
          strategy:
              native ? HdrStrategy.nativeDolbyVision : HdrStrategy.sdrDirect),
      sourceSpec: missingSource ? null : bound ?? source,
      options: hardware);
}

HdrReviewFacts facts(
    {String mode = 'mediacodec',
    String codec = 'hevc',
    String path = 'test://require',
    String name = 'c2.hevc',
    String mime = 'video/hevc',
    bool active = false,
    bool native = false,
    bool evidence = true,
    bool missingConfig = false,
    String? pixel}) {
  final config = missingConfig
      ? null
      : AndroidMediaCodecConfiguration.parse(
          '{"api":1,"mime":"$mime","codec":"$name","native-dv-active":$active}');
  return HdrReviewFacts(
      path: path,
      codec: codec,
      hwdecCurrent: mode,
      decoderObservation: native
          ? null
          : HdrDecoderObservation(
              playlistEntryId: 1,
              fileLoadedEpoch: 1,
              decoder: 'hevc_mediacodec',
              decoderDescription: '',
              hwdec: mode,
              pixelFormat:
                  pixel ?? (mode == 'mediacodec' ? 'mediacodec' : 'yuv420p'),
              hwPixelFormat: '',
              mediaCodecConfiguration: config),
      nativeDvEvidence: native && evidence && config != null
          ? HdrNativeDvReviewEvidence(
              source: HdrOptionSourceIdentity(
                  player: Object(),
                  path: path,
                  playlistEntryId: '1',
                  fileLoadedEpoch: 1),
              loaded: const FileLoadedRecord(1, 1),
              controller: Object(),
              output: AndroidSurfaceAccountId(
                  handle: 1,
                  generation: 1,
                  viewId: 1,
                  surfaceGeneration: 1,
                  wid: 1),
              configuration: config,
              hwdecCurrent: mode)
          : null);
}

VideoRouteOptionFulfillment review(HdrOpenPlan p, HdrReviewFacts f,
        [EffectiveVideoRouteOptions? o]) =>
    reviewVideoRouteOptions(p, f, o ?? hardware);
void reject(HdrOpenPlan p, HdrReviewFacts f) {
  final result = review(p, f);
  expect(result.decode, isNot(VideoRouteOptionStatus.fulfilled));
  expect(() => validateVideoRouteOptionFulfillment(hardware, result),
      throwsA(isA<HdrPlaybackBlocked>()));
}

void main() {
  test(
      'ordinary direct and MC-copy can prove hardware from exact eligible source row',
      () {
    for (final mode in ['mediacodec', 'mediacodec-copy']) {
      final result = review(plan(mode: mode), facts(mode: mode));
      expect(result.decode, VideoRouteOptionStatus.fulfilled);
      expect(() => validateVideoRouteOptionFulfillment(hardware, result),
          returnsNormally);
    }
  });
  for (final kind in [VideoDecoderKind.software, VideoDecoderKind.unknown]) {
    test('actual configured name with $kind kind cannot fulfill hardware', () {
      reject(plan(rows: [row(kind: kind)]), facts());
    });
  }
  for (final support in [VideoSupport.unknown, VideoSupport.unsupported]) {
    test('actual codec row $support cannot fulfill hardware', () {
      reject(plan(rows: [row(support: support)]), facts());
    });
  }
  test('duplicate eligible and conflicting kind rows fail closed', () {
    reject(plan(rows: [row(), row(kind: VideoDecoderKind.unknown)]), facts());
  });
  test('codec wrapper name cannot stand in for configured codec', () {
    reject(plan(), facts(name: 'hevc_mediacodec'));
  });
  test('missing configured codec remains unknown', () {
    reject(plan(), facts(name: ''));
  });
  test('missing config remains unknown', () {
    reject(plan(), facts(missingConfig: true));
  });
  test('wrong track MIME rejects hardware', () {
    reject(plan(), facts(mime: 'video/avc'));
  });
  test('unknown source codec cannot infer MIME from decoder name', () {
    reject(plan(), facts(codec: ''));
  });
  test(
      'wrong source dimensions and missing source census binding reject hardware',
      () {
    reject(
        plan(
            declared:
                VideoSourceSpec(codec: 'hevc', width: 3840, height: 2160)),
        facts());
    reject(plan(missingSource: true), facts());
  });
  test(
      'census bound to conflicting declared codec cannot prove actual HEVC hardware',
      () {
    final other =
        VideoSourceSpec(codec: 'avc1.640028', width: 1920, height: 1080);
    reject(plan(declared: other, bound: other), facts());
    reject(plan(declared: other, bound: other, native: true),
        facts(native: true, mime: 'video/dolby-vision', active: true));
  });
  test('wrong media path and census path reject hardware', () {
    reject(plan(), facts(path: 'test://other'));
    reject(plan(rows: [row(path: 'nativeDv')]), facts());
  });
  test('software no+known CPU fulfills, copy and unknown resource cannot', () {
    final o = EffectiveVideoRouteOptions.resolve(
        application: const VideoRouteOptions(
            decode: VideoRouteSelection.require(VideoDecodeTarget.software)));
    expect(
        review(plan(mode: 'no'), facts(mode: 'no', missingConfig: true), o)
            .decode,
        VideoRouteOptionStatus.fulfilled);
    for (final f in [
      facts(mode: 'mediacodec-copy'),
      facts(mode: 'no', pixel: 'unknown', missingConfig: true)
    ]) {
      final result = review(plan(mode: 'no'), f, o);
      expect(() => validateVideoRouteOptionFulfillment(o, result),
          throwsA(isA<HdrPlaybackBlocked>()));
    }
  });
  test('native DV uses exact hardware native path and active DV config', () {
    final p = plan(native: true);
    final f = facts(native: true, mime: 'video/dolby-vision', active: true);
    expect(review(p, f).decode, VideoRouteOptionStatus.fulfilled);
    reject(p, facts(native: true, mime: 'video/hevc', active: true));
    reject(p, facts(native: true, mime: 'video/dolby-vision', active: false));
    reject(
        p,
        facts(
            native: true,
            mime: 'video/dolby-vision',
            active: true,
            evidence: false));
    reject(
        plan(
            native: true,
            rows: [row(mime: 'video/dolby-vision', path: 'codec')]),
        f);
    reject(
        plan(native: true, rows: [
          row(
              mime: 'video/dolby-vision',
              path: 'nativeDv',
              kind: VideoDecoderKind.unknown)
        ]),
        f);
  });
  test('preferCopy stays inside SDR contract and does not overtake HDR direct',
      () {
    final direct = route('mediacodec'), copy = route('mediacodec-copy');
    final hdr = changed(direct,
        strategy: HdrStrategy.baseLayerDirect,
        outputTransfer: HdrOutputTransfer.pq);
    HdrCandidate c(HdrRoute r) => HdrCandidate(
        strategy: r.strategy,
        maturity: HdrStrategyMaturity.verified,
        feasible: true,
        route: r);
    final o = EffectiveVideoRouteOptions.resolve(
        application: const VideoRouteOptions(
            importPreference: VideoImportPreference.preferCopy));
    final ordered =
        applyVideoRouteOptions([c(hdr), c(direct), c(copy)], catalog.caps(), o);
    expect(ordered.map((c) => c.route), [hdr, copy, direct]);
    expect(
        applyVideoRouteOptions([c(direct), c(copy)], catalog.caps(), o)
            .first
            .route,
        copy);
    final other = EffectiveVideoRouteOptions.resolve(
        application: const VideoRouteOptions(
            importPreference: VideoImportPreference.preferDirect));
    expect(
        applyVideoRouteOptions([c(copy), c(direct)], catalog.caps(), other)
            .first
            .route,
        direct);
  });
  test(
      'require output filters safety nets and prefer does not authorize failed route',
      () {
    final direct = route('mediacodec');
    final hdr = changed(direct,
        strategy: HdrStrategy.baseLayerDirect,
        outputTransfer: HdrOutputTransfer.pq);
    final candidate = HdrCandidate(
        strategy: direct.strategy,
        maturity: HdrStrategyMaturity.verified,
        feasible: true,
        route: direct);
    final o = EffectiveVideoRouteOptions.resolve(
        application: const VideoRouteOptions(
            output: VideoRouteSelection.require(VideoOutputIntent.hdr)));
    final result =
        applyVideoRouteOptions([candidate], catalog.caps(), o).single;
    expect(result.feasible, isFalse);
    expect(result.skipReason, HdrDegradeReason.routeOptionsUnsatisfied);
    expect(videoRouteMeetsRequirements(hdr, catalog.caps(), o), isTrue);
  });
}
