// Device-fact anchors for HdrSourceClassifier: the exact decoder-reported
// values captured on LYA-AL00 (3EP7N18C28016072, Android 10) with the
// v2026.10 libmpv (evidence: archives/conversations/
// android-hdr-auto-output-20261002.md, 2026-10-02 probe rounds). Each tuple
// replays what `current-tracks/video/dolby-vision-profile` and
// `video-params/gamma|primaries` actually reported for a sample, so a
// classification rule change that would break a verified device fact fails
// here.
import 'package:flutter_test/flutter_test.dart';

import 'package:media_kit/media_kit.dart' show VideoParams;
import 'package:media_kit_video/src/hdr/hdr_output_policy.dart';
import 'package:media_kit_video/src/hdr/hdr_source_classifier.dart';
import 'package:media_kit_video/src/hdr/hdr_source_descriptor.dart';

void main() {
  group('HdrSourceClassifier against LYA device-reported facts', () {
    // media-kit-hdr10-full.mp4 (HDR10): profile empty, gamma pq, primaries
    // bt.2020.
    test('HDR10 sample classifies as hdr10', () {
      final descriptor = const HdrSourceClassifier().classify(
        videoParams: const VideoParams(gamma: 'pq', primaries: 'bt.2020'),
      );
      expect(descriptor.dvProfile, isNull);
      expect(descriptor.dynamicMetadata, HdrDynamicMetadata.none);
      expect(descriptor.kind, HdrMediaKind.hdr10);
    });

    // media-kit-p84-full.mp4 (DV P8.4): profile=8 (integer), gamma hlg,
    // primaries bt.2020.
    test('P8.4 sample classifies via integer profile 8 + hlg gamma', () {
      final descriptor = const HdrSourceClassifier().classify(
        videoParams: const VideoParams(gamma: 'hlg', primaries: 'bt.2020'),
        dolbyVisionProfile: 8,
      );
      expect(descriptor.dvProfile, 8);
      expect(descriptor.dvCompatibilityId, 4);
      expect(descriptor.dynamicMetadata, HdrDynamicMetadata.dolbyVision);
      expect(descriptor.kind, HdrMediaKind.dolbyVisionP84);
    });

    // media-kit-p5-mystery-box.mp4 (DV P5): profile=5 (integer), gamma pq,
    // primaries bt.2020.
    test('P5 sample classifies as dolbyVisionP5', () {
      final descriptor = const HdrSourceClassifier().classify(
        videoParams: const VideoParams(gamma: 'pq', primaries: 'bt.2020'),
        dolbyVisionProfile: 5,
      );
      expect(descriptor.dvProfile, 5);
      expect(descriptor.dvCompatibilityId, 0);
      // Decoder facts alone cannot prove the layer structure: without a
      // container fact the P5 enhancement layer stays unknown.
      expect(descriptor.enhancementLayer, isNull);
      expect(descriptor.kind, HdrMediaKind.dolbyVisionP5);
      // The single-layer device fact reports through the container-fact
      // channel (el-present), not base-layer inference.
      final withContainerFact = const HdrSourceClassifier().classify(
        videoParams: const VideoParams(gamma: 'pq', primaries: 'bt.2020'),
        dolbyVisionProfile: 5,
        dvElPresent: false,
      );
      expect(withContainerFact.enhancementLayer, isFalse);
    });

    // media-kit-hlg-dvs-graypatch50.mp4 (pure HLG): profile empty, gamma
    // hlg, primaries bt.2020.
    test('pure HLG sample classifies as hlg', () {
      final descriptor = const HdrSourceClassifier().classify(
        videoParams: const VideoParams(gamma: 'hlg', primaries: 'bt.2020'),
      );
      expect(descriptor.dvProfile, isNull);
      expect(descriptor.kind, HdrMediaKind.hlg);
    });

    // "4K HDR (HDR Vivd_HLG).mp4": despite the file name, the decoder
    // reports PQ/BT.2020 with no DV profile (its HDR Vivid dynamic metadata
    // is not observable through mpv). The base layer classifies as HDR10 —
    // recorded here because the requirement's section-6 note expected this
    // file to serve as an HLG base layer, which the decoder facts contradict.
    test('HDR Vivid sample base layer (actually PQ) classifies as hdr10', () {
      final descriptor = const HdrSourceClassifier().classify(
        videoParams: const VideoParams(gamma: 'pq', primaries: 'bt.2020'),
      );
      expect(descriptor.kind, HdrMediaKind.hdr10);
      expect(descriptor.dynamicMetadata, HdrDynamicMetadata.none);
    });
  });

  group('classifyMedia end-to-end with the LYA decoder facts', () {
    test('integer profile 8 + hlg reaches dolbyVisionP84 (defect fix)', () {
      expect(
        HdrOutputPolicy.classifyMedia(
          videoParams: const VideoParams(gamma: 'hlg', primaries: 'bt.2020'),
          dolbyVisionProfile: '8',
        ),
        HdrMediaKind.dolbyVisionP84,
      );
    });
  });
}
