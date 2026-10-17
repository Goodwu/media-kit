import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit_video/src/hdr/hdr_capabilities.dart';
import 'package:media_kit_video/src/hdr/hdr_route.dart';
import 'package:media_kit_video/src/hdr/hdr_route_planner.dart';
import 'package:media_kit_video/src/hdr/hdr_source_descriptor.dart';
import 'package:media_kit_video/src/hdr/hdr_strategy.dart';
import 'package:media_kit_video/src/hdr/hdr_strategy_realizer.dart';
import 'package:media_kit_video/src/routing/video_route_options.dart';

const sdr = HdrSourceDescriptor(
    codec: 'hevc',
    transfer: 'bt.1886',
    primaries: 'bt.709',
    enhancementLayer: false);

/// DV profile 8.2: SDR base layer whose RPU the sdrDirect route strips.
const p82 = HdrSourceDescriptor(
    codec: 'hevc',
    transfer: 'bt.1886',
    dynamicMetadata: HdrDynamicMetadata.dolbyVision,
    dvProfile: 8,
    dvCompatibilityId: 2,
    enhancementLayer: false);

const hdr10 = HdrSourceDescriptor(
    codec: 'hevc',
    transfer: 'pq',
    primaries: 'bt.2020',
    enhancementLayer: false);

HdrCapabilities caps(int sdkInt) => HdrCapabilities(
      sdkInt: sdkInt,
      displayHdrTypes: const {1, 2, 3},
      hevcDecoders: const [],
      dolbyVisionDecoders: const [],
      p5PipelineAvailable: true,
      dataSpaceBridgeLoaded: true,
      dataSpaceExt: null,
    );

EffectiveVideoRouteOptions optionsWith(bool sdrEmbed) =>
    EffectiveVideoRouteOptions.resolve(
        application: VideoRouteOptions(sdrEmbed: sdrEmbed));

List<HdrRoute> sdrDirectExecutions(HdrCapabilities capabilities,
        {bool sdrEmbed = false, HdrSourceDescriptor source = sdr}) =>
    HdrStrategyRealizer.realizeCandidates(
      HdrStrategy.sdrDirect,
      source: source,
      sourceClass: HdrSourceClass.of(source),
      capabilities: capabilities,
      sdrEmbedEnabled: sdrEmbed,
    ).map((realization) => realization.route!).toList();

/// A fully specified texture execution of the undeclared-option directory.
/// HdrRoute equality compares every field plus the dependency set, so an
/// `equals` against these values is a complete field-by-field comparison.
HdrRoute textureExecution(String hwdec, Set<String> dependencies) => HdrRoute(
      strategy: HdrStrategy.sdrDirect,
      presentation: HdrPresentation.sdr,
      outputTransfer: HdrOutputTransfer.sdr,
      appliesDynamicMetadata: false,
      topology: HdrTopology.texture,
      vo: 'gpu-next',
      hwdec: hwdec,
      targetPrim: null,
      targetTrc: null,
      surfaceTransfer: null,
      stripDvRpu: false,
      metadataHandling: HdrMetadataHandling.none,
      dependencies: dependencies,
    );

void main() {
  test('undeclared option keeps the candidate directory unchanged', () {
    // Red line: with the declaration absent, every platform's directory is
    // exactly today's — compared as complete route values (every HdrRoute
    // field plus the dependency set). API 16–25: copy → software (the texture
    // GPU import is unavailable). API ≥ 26: direct → copy → software.
    expect(sdrDirectExecutions(caps(24)), [
      textureExecution('mediacodec-copy', const {
        HdrRouteDependency.presenterGpuTexture,
        HdrRouteDependency.decoderMediacodec,
        HdrRouteDependency.importCpuUpload,
        HdrRouteDependency.hwdecMediacodecCopy,
      }),
      textureExecution('no', const {
        HdrRouteDependency.presenterGpuTexture,
        HdrRouteDependency.decoderSoftware,
        HdrRouteDependency.importCpuUpload,
      }),
    ]);
    expect(sdrDirectExecutions(caps(29)), [
      textureExecution('mediacodec', const {
        HdrRouteDependency.presenterGpuTexture,
        HdrRouteDependency.decoderMediacodec,
        HdrRouteDependency.hwdecMediacodec,
        HdrRouteDependency.importMediacodec,
      }),
      textureExecution('mediacodec-copy', const {
        HdrRouteDependency.presenterGpuTexture,
        HdrRouteDependency.decoderMediacodec,
        HdrRouteDependency.importCpuUpload,
        HdrRouteDependency.hwdecMediacodecCopy,
      }),
      textureExecution('no', const {
        HdrRouteDependency.presenterGpuTexture,
        HdrRouteDependency.decoderSoftware,
        HdrRouteDependency.importCpuUpload,
      }),
    ]);
    // Explicit false behaves like absent.
    expect(sdrDirectExecutions(caps(24), sdrEmbed: false),
        sdrDirectExecutions(caps(24)));
  });

  test('declared option adds the embed execution before copy on SDK 16–25',
      () {
    final routes = sdrDirectExecutions(caps(24), sdrEmbed: true);
    expect(routes.map((r) => [r.vo, r.hwdec]), [
      ['mediacodec_embed', 'mediacodec'],
      ['gpu-next', 'mediacodec-copy'],
      ['gpu-next', 'no'],
    ]);
    final embed = routes.first;
    // The embed route reuses the existing embed carrier shape (native-DV /
    // baseLayerDirect): platform view topology, decoder-rendered Surface, no
    // color requests, no render-mode pin (boolean default).
    expect(embed.strategy, HdrStrategy.sdrDirect);
    expect(embed.presentation, HdrPresentation.sdr);
    expect(embed.outputTransfer, HdrOutputTransfer.sdr);
    expect(embed.topology, HdrTopology.platformView);
    expect(embed.appliesDynamicMetadata, isFalse);
    expect(embed.targetPrim, isNull);
    expect(embed.targetTrc, isNull);
    expect(embed.surfaceTransfer, isNull);
    expect(embed.offscreenTransfer, isNull);
    expect(embed.mediacodecEmbedRenderMode, isNull);
    expect(embed.stripDvRpu, isFalse);
    // No presenter/import stage at all: the decoder renders into the wid.
    expect(embed.dependencies, <String>{
      HdrRouteDependency.hwdecMediacodec,
      HdrRouteDependency.topologyPlatformView,
      HdrRouteDependency.decoderMediacodec,
    });
  });

  test('declared option adds nothing on an API ≥ 26 device', () {
    // The verified texture direct route is the carrier there; the embed
    // candidate exists only where the texture GPU import is unavailable.
    expect(
        sdrDirectExecutions(caps(29), sdrEmbed: true)
            .map((r) => [r.vo, r.hwdec]),
        [
          ['gpu-next', 'mediacodec'],
          ['gpu-next', 'mediacodec-copy'],
          ['gpu-next', 'no'],
        ]);
  });

  test('unknown SDK level (0) never gains the embed candidate', () {
    // Admission is the capability rule sdkInt > 0 && sdkInt < 26; an unknown
    // level is not proof of a missing GPU import.
    expect(
        sdrDirectExecutions(caps(0), sdrEmbed: true).map((r) => r.vo),
        everyElement('gpu-next'));
    expect(sdrDirectExecutions(caps(0), sdrEmbed: true).length, 3);
  });

  test('P8.2 keeps its RPU strip and baseline contract on the embed carrier',
      () {
    final routes = sdrDirectExecutions(caps(24), sdrEmbed: true, source: p82);
    final embed = routes.first;
    expect(embed.vo, 'mediacodec_embed');
    expect(embed.stripDvRpu, isTrue);
    expect(embed.metadataHandling, HdrMetadataHandling.baselineOnly);
  });

  test('toneMapSdr never gains an embed variant', () {
    // Tone mapping IS the mpv-side GL pipeline the embed VO cannot provide.
    final routes = HdrStrategyRealizer.realizeCandidates(
      HdrStrategy.toneMapSdr,
      source: hdr10,
      sourceClass: HdrSourceClass.hdr10,
      capabilities: caps(24),
      sdrEmbedEnabled: true,
    ).map((realization) => realization.route!).toList();
    expect(routes.map((r) => [r.vo, r.hwdec]), [
      ['gpu-next', 'mediacodec-copy'],
      ['gpu-next', 'no'],
    ]);
  });

  test('HDR strategies are untouched by the declaration', () {
    final undeclared = HdrStrategyRealizer.realizeCandidates(
      HdrStrategy.baseLayerDirect,
      source: hdr10,
      sourceClass: HdrSourceClass.hdr10,
      capabilities: caps(24),
    ).single.route!;
    final declared = HdrStrategyRealizer.realizeCandidates(
      HdrStrategy.baseLayerDirect,
      source: hdr10,
      sourceClass: HdrSourceClass.hdr10,
      capabilities: caps(24),
      sdrEmbedEnabled: true,
    ).single.route!;
    expect(declared, undeclared);
  });

  test('planner selects the embed execution on the copy-fallback group', () {
    final prediction = HdrRoutePlanner.plan(
      source: sdr,
      capabilities: caps(24),
      options: optionsWith(true),
    );
    expect(prediction.playable, isTrue);
    expect(prediction.selected.route!.vo, 'mediacodec_embed');
    expect(prediction.selected.route!.hwdec, 'mediacodec');
    expect(prediction.selected.stage, isNull);
    expect(
        prediction.candidates.map((c) => [c.route?.vo, c.route?.hwdec]),
        [
          ['mediacodec_embed', 'mediacodec'],
          ['gpu-next', 'mediacodec-copy'],
          ['gpu-next', 'no'],
        ]);
  });

  test('planner directory is unchanged for undeclared option on any SDK', () {
    for (final sdk in [0, 24, 25, 26, 29]) {
      final prediction = HdrRoutePlanner.plan(
        source: sdr,
        capabilities: caps(sdk),
        options: optionsWith(false),
      );
      expect(prediction.candidates.map((c) => c.route?.vo),
          everyElement('gpu-next'),
          reason: 'sdk $sdk');
    }
  });

  test('shared decoder stage failure excludes embed and copy alike', () {
    final prediction = HdrRoutePlanner.plan(
      source: sdr,
      capabilities: caps(24),
      options: optionsWith(true),
      excluded: {
        HdrRouteDependency.decoderMediacodec:
            HdrDegradeReason.sourceDecodeUnsupported
      },
    );
    // All three executions were planned (embed first), and both MediaCodec
    // decode variants are skipped with the carried reason because they share
    // the decoder:mediacodec stage; software remains the playable remainder.
    expect(prediction.candidates.length, 3);
    expect(prediction.selected.route!.hwdec, 'no');
    expect(
        prediction.candidates
            .where((candidate) => !candidate.feasible)
            .map((candidate) => candidate.skipReason),
        everyElement(HdrDegradeReason.sourceDecodeUnsupported));
    expect(prediction.candidates.where((c) => !c.feasible).length, 2);
  });

  test('failed embed hwdec stage excludes only the embed variant', () {
    final prediction = HdrRoutePlanner.plan(
      source: sdr,
      capabilities: caps(24),
      options: optionsWith(true),
      excluded: {
        HdrRouteDependency.hwdecMediacodec: HdrDegradeReason.hwdecMismatch
      },
    );
    // Exactly one skipped candidate — the embed variant (its hwdec stage tag
    // is not shared with the copy carrier) — and the copy fallback is what
    // the planner selects instead.
    final skipped = prediction.candidates
        .where((candidate) => !candidate.feasible)
        .toList();
    expect(skipped.length, 1);
    expect(skipped.single.skipReason, HdrDegradeReason.hwdecMismatch);
    expect(prediction.selected.route!.vo, 'gpu-next');
    expect(prediction.selected.route!.hwdec, 'mediacodec-copy');
  });

  test('explicit preferCopy suppresses embed generation even when declared',
      () {
    // Lead ruling on P2 observation 2: the explicit copy intent is preserved
    // by design (LYA round contract — a persisted explicit mediacodec-copy
    // preference must be respected) and WINS over the sdrEmbed declaration.
    // Suppression is at generation: no embed candidate exists at all, and the
    // copy path is exactly the undeclared one.
    final options = EffectiveVideoRouteOptions.resolve(
        application: const VideoRouteOptions(
            sdrEmbed: true,
            importPreference: VideoImportPreference.preferCopy));
    final prediction = HdrRoutePlanner.plan(
      source: sdr,
      capabilities: caps(24),
      options: options,
    );
    expect(prediction.candidates.map((c) => c.route?.vo),
        everyElement('gpu-next'));
    expect(prediction.candidates.length, 2);
    expect(prediction.selected.route!.vo, 'gpu-next');
    expect(prediction.selected.route!.hwdec, 'mediacodec-copy');
  });

  test('declared embed still leads without a copy preference', () {
    final options = EffectiveVideoRouteOptions.resolve(
        application: const VideoRouteOptions(
            sdrEmbed: true, importPreference: VideoImportPreference.auto));
    final prediction = HdrRoutePlanner.plan(
      source: sdr,
      capabilities: caps(24),
      options: options,
    );
    expect(prediction.candidates.first.route!.vo, 'mediacodec_embed');
    expect(prediction.selected.route!.vo, 'mediacodec_embed');
  });

  test('preferDirect does not suppress the embed candidate', () {
    // Only the explicit copy intent suppresses generation; preferDirect is
    // the compatible direct preference and keeps the embed candidate first.
    final options = EffectiveVideoRouteOptions.resolve(
        application: const VideoRouteOptions(
            sdrEmbed: true,
            importPreference: VideoImportPreference.preferDirect));
    final prediction = HdrRoutePlanner.plan(
      source: sdr,
      capabilities: caps(24),
      options: options,
    );
    expect(prediction.candidates.first.route!.vo, 'mediacodec_embed');
  });

  test('serialization roundtrip preserves the copy-intent suppression', () {
    final requested = const VideoRouteOptions(
        sdrEmbed: true, importPreference: VideoImportPreference.preferCopy);
    final roundtripped = VideoRouteOptions.fromMap(
        jsonDecode(requested.key) as Map<String, Object?>);
    expect(roundtripped, requested);
    final prediction = HdrRoutePlanner.plan(
      source: sdr,
      capabilities: caps(24),
      options: EffectiveVideoRouteOptions.resolve(application: roundtripped),
    );
    expect(prediction.candidates.map((c) => c.route?.vo),
        everyElement('gpu-next'));
    expect(prediction.selected.route!.hwdec, 'mediacodec-copy');
  });
}
