import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' show VideoParams;
import 'package:media_kit_video/src/hdr/hdr_output_policy.dart'
    show HdrMediaKind;
import 'package:media_kit_video/src/hdr/hdr_source_classifier.dart';
import 'package:media_kit_video/src/hdr/hdr_source_descriptor.dart';
import 'package:media_kit_video/src/hdr/hdr_strategy.dart';

void main() {
  const classifier = HdrSourceClassifier();

  group('classify: decoder facts → description (plan 1.5 table)', () {
    test('dolby-vision-profile 5 → dvProfile 5, compat 0, metadata DV', () {
      final descriptor = classifier.classify(
        videoParams: const VideoParams(gamma: 'pq', primaries: 'bt.2020'),
        dolbyVisionProfile: 5,
      );
      expect(descriptor.dvProfile, 5);
      expect(descriptor.dvCompatibilityId, 0);
      expect(descriptor.dynamicMetadata, HdrDynamicMetadata.dolbyVision);
      expect(descriptor.enhancementLayer, isFalse);
      expect(descriptor.transfer, 'pq');
      expect(descriptor.primaries, 'bt.2020');
      expect(descriptor.kind, HdrMediaKind.dolbyVisionP5);
    });

    test('profile 8 with PQ/BT.2020 base layer → 8.1, compat 1', () {
      final descriptor = classifier.classify(
        videoParams: const VideoParams(gamma: 'pq', primaries: 'bt.2020'),
        dolbyVisionProfile: 8,
      );
      expect(descriptor.dvProfile, 8);
      expect(descriptor.dvCompatibilityId, 1);
      expect(descriptor.dynamicMetadata, HdrDynamicMetadata.dolbyVision);
      expect(descriptor.kind, HdrMediaKind.hdr10);
    });

    test('profile 8 with HLG base layer → 8.4, compat 4', () {
      final descriptor = classifier.classify(
        videoParams: const VideoParams(gamma: 'hlg', primaries: 'bt.2020'),
        dolbyVisionProfile: 8,
      );
      expect(descriptor.dvProfile, 8);
      expect(descriptor.dvCompatibilityId, 4);
      expect(descriptor.kind, HdrMediaKind.dolbyVisionP84);
    });

    test('profile 8 with SDR base layer gamma → 8.2, compat 2', () {
      for (final gamma in const ['bt.1886', 'srgb']) {
        final descriptor = classifier.classify(
          videoParams: VideoParams(gamma: gamma, primaries: 'bt.709'),
          dolbyVisionProfile: 8,
        );
        expect(descriptor.dvProfile, 8, reason: gamma);
        expect(descriptor.dvCompatibilityId, 2, reason: gamma);
        expect(descriptor.kind, HdrMediaKind.sdr, reason: gamma);
      }
    });

    test('profile 7 → compat 6, enhancement layer unknown', () {
      final descriptor = classifier.classify(
        videoParams: const VideoParams(gamma: 'pq', primaries: 'bt.2020'),
        dolbyVisionProfile: 7,
      );
      expect(descriptor.dvProfile, 7);
      expect(descriptor.dvCompatibilityId, 6);
      // mpv does not expose the enhancement-layer flag yet: unknown.
      expect(descriptor.enhancementLayer, isNull);
      // The profile-7 base layer keeps the HDR10 routing behavior.
      expect(descriptor.kind, HdrMediaKind.hdr10);
    });

    test('profile 10 → codec av1, compat inferred from gamma', () {
      final pq = classifier.classify(
        videoParams: const VideoParams(gamma: 'pq', primaries: 'bt.2020'),
        dolbyVisionProfile: 10,
      );
      expect(pq.dvProfile, 10);
      expect(pq.codec, 'av1');
      expect(pq.dvCompatibilityId, 1);
      expect(pq.kind, HdrMediaKind.hdr10);

      final hlg = classifier.classify(
        videoParams: const VideoParams(gamma: 'hlg', primaries: 'bt.2020'),
        dolbyVisionProfile: 10,
      );
      expect(hlg.codec, 'av1');
      expect(hlg.dvCompatibilityId, 4);
      expect(hlg.kind, HdrMediaKind.hlg);
    });

    test('no DV profile, PQ + BT.2020 → HDR10 without dynamic metadata', () {
      final descriptor = classifier.classify(
        videoParams: const VideoParams(gamma: 'pq', primaries: 'bt.2020'),
      );
      expect(descriptor.dvProfile, isNull);
      // No HDR Vivid side-data fact reported: none (HDR10+ remains not
      // observable through mpv).
      expect(descriptor.dynamicMetadata, HdrDynamicMetadata.none);
      expect(descriptor.transfer, 'pq');
      expect(descriptor.primaries, 'bt.2020');
      expect(descriptor.kind, HdrMediaKind.hdr10);
    });

    test('no DV profile, HLG → HLG', () {
      final descriptor = classifier.classify(
        videoParams: const VideoParams(gamma: 'hlg', primaries: 'bt.2020'),
      );
      expect(descriptor.transfer, 'hlg');
      expect(descriptor.kind, HdrMediaKind.hlg);
    });

    test('everything else stays SDR', () {
      void expectSdr(VideoParams params, String reason) {
        final descriptor = classifier.classify(videoParams: params);
        expect(descriptor.kind, HdrMediaKind.sdr, reason: reason);
        expect(descriptor.dvProfile, isNull, reason: reason);
      }

      expectSdr(
        const VideoParams(gamma: 'bt.1886', primaries: 'bt.709'),
        'bt.1886',
      );
      expectSdr(
        const VideoParams(gamma: 'srgb', primaries: 'bt.709'),
        'srgb',
      );
      expectSdr(
        const VideoParams(gamma: 'pq', primaries: 'bt.709'),
        'PQ without BT.2020',
      );
      expectSdr(
        const VideoParams(primaries: 'bt.2020'),
        'missing gamma',
      );
    });

    test('profile 8 with unknown gamma leaves the compatibility id unknown',
        () {
      final descriptor = classifier.classify(
        videoParams: const VideoParams(primaries: 'bt.2020'),
        dolbyVisionProfile: 8,
      );
      expect(descriptor.dvProfile, 8);
      expect(descriptor.dvCompatibilityId, isNull);
      expect(descriptor.kind, HdrMediaKind.sdr);
    });
  });

  group('classify: hint channel', () {
    const hint = HdrSourceDescriptor(
      codec: 'hevc',
      transfer: 'hlg',
      primaries: 'bt.2020',
      dynamicMetadata: HdrDynamicMetadata.dolbyVision,
      dvProfile: 8,
      dvCompatibilityId: 4,
      enhancementLayer: false,
    );

    test('no decoder facts yet → the hint is returned as-is', () {
      expect(classifier.classify(), const HdrSourceDescriptor());
      expect(classifier.classify(hint: hint), same(hint));
    });

    test('facts fill the codec gap from the hint', () {
      final descriptor = classifier.classify(
        videoParams: const VideoParams(gamma: 'hlg', primaries: 'bt.2020'),
        dolbyVisionProfile: 8,
        hint: hint,
      );
      expect(descriptor.codec, 'hevc');
      expect(descriptor.kind, HdrMediaKind.dolbyVisionP84);
    });

    test('decoder facts win over a wrong hint', () {
      final descriptor = classifier.classify(
        videoParams: const VideoParams(gamma: 'pq', primaries: 'bt.2020'),
        dolbyVisionProfile: 5,
        hint: hint,
      );
      expect(descriptor.dvProfile, 5);
      expect(descriptor.dvCompatibilityId, 0);
      expect(descriptor.kind, HdrMediaKind.dolbyVisionP5);
    });
  });

  group('classify: container DV facts and HDR Vivid fact (fork 0f7e6bec32+)',
      () {
    test('explicit container compatibility id overrides the gamma inference',
        () {
      // Container fact 1 on an HLG base layer: the record is the DV
      // signaling itself, so it wins over the hlg→4 inference.
      final descriptor = classifier.classify(
        videoParams: const VideoParams(gamma: 'hlg', primaries: 'bt.2020'),
        dolbyVisionProfile: 8,
        dvCompatibilityId: 1,
      );
      expect(descriptor.dvProfile, 8);
      expect(descriptor.dvCompatibilityId, 1);
      expect(descriptor.kind, HdrMediaKind.hdr10);
    });

    test('container fact 0 is valid and overrides a non-zero inference', () {
      final descriptor = classifier.classify(
        videoParams: const VideoParams(gamma: 'hlg', primaries: 'bt.2020'),
        dolbyVisionProfile: 8,
        dvCompatibilityId: 0,
      );
      expect(descriptor.dvCompatibilityId, 0);
    });

    test('a null container fact keeps the base-layer inference', () {
      final descriptor = classifier.classify(
        videoParams: const VideoParams(gamma: 'hlg', primaries: 'bt.2020'),
        dolbyVisionProfile: 8,
        dvCompatibilityId: null,
      );
      expect(descriptor.dvCompatibilityId, 4);
    });

    test('the -1 unknown sentinel falls back to the inference', () {
      final descriptor = classifier.classify(
        videoParams: const VideoParams(gamma: 'pq', primaries: 'bt.2020'),
        dolbyVisionProfile: 8,
        dvCompatibilityId: -1,
      );
      expect(descriptor.dvCompatibilityId, 1);

      final p7 = classifier.classify(
        videoParams: const VideoParams(gamma: 'pq', primaries: 'bt.2020'),
        dolbyVisionProfile: 7,
        dvCompatibilityId: -1,
      );
      expect(p7.dvCompatibilityId, 6);
    });

    test('container fact overrides the profile-5 default', () {
      final descriptor = classifier.classify(
        videoParams: const VideoParams(gamma: 'pq', primaries: 'bt.2020'),
        dolbyVisionProfile: 5,
        dvCompatibilityId: 2,
      );
      expect(descriptor.dvProfile, 5);
      expect(descriptor.dvCompatibilityId, 2);
    });

    test('profile 7 enhancement layer follows the el-present fact', () {
      final fel = classifier.classify(
        videoParams: const VideoParams(gamma: 'pq', primaries: 'bt.2020'),
        dolbyVisionProfile: 7,
        dvElPresent: true,
      );
      expect(fel.enhancementLayer, isTrue);

      final baseOnly = classifier.classify(
        videoParams: const VideoParams(gamma: 'pq', primaries: 'bt.2020'),
        dolbyVisionProfile: 7,
        dvElPresent: false,
      );
      expect(baseOnly.enhancementLayer, isFalse);

      // Unavailable fact stays unknown (the original mpv behavior).
      final unknown = classifier.classify(
        videoParams: const VideoParams(gamma: 'pq', primaries: 'bt.2020'),
        dolbyVisionProfile: 7,
      );
      expect(unknown.enhancementLayer, isNull);
    });

    test('profile 5 and 8 enhancement-layer facts override the defaults', () {
      final p5 = classifier.classify(
        videoParams: const VideoParams(gamma: 'pq', primaries: 'bt.2020'),
        dolbyVisionProfile: 5,
        dvElPresent: true,
      );
      expect(p5.enhancementLayer, isTrue);

      final p8 = classifier.classify(
        videoParams: const VideoParams(gamma: 'hlg', primaries: 'bt.2020'),
        dolbyVisionProfile: 8,
        dvElPresent: false,
      );
      expect(p8.enhancementLayer, isFalse);
    });

    test('profile 8 container compatibility id and el fact combine', () {
      final descriptor = classifier.classify(
        videoParams: const VideoParams(gamma: 'hlg', primaries: 'bt.2020'),
        dolbyVisionProfile: 8,
        dvCompatibilityId: 1,
        dvElPresent: true,
      );
      expect(descriptor.dvCompatibilityId, 1);
      expect(descriptor.enhancementLayer, isTrue);
    });

    test('no profile + HDR Vivid fact true → hdrVivid metadata and class',
        () {
      final descriptor = classifier.classify(
        videoParams: const VideoParams(gamma: 'pq', primaries: 'bt.2020'),
        hdrVivid: true,
      );
      expect(descriptor.dvProfile, isNull);
      expect(descriptor.dynamicMetadata, HdrDynamicMetadata.hdrVivid);
      expect(descriptor.enhancementLayer, isFalse);
      // The class derivation reads the metadata format (hdr_strategy.dart
      // HdrSourceClass.of), so the fact feeds the maturity table directly.
      expect(HdrSourceClass.of(descriptor), HdrSourceClass.hdrVivid);
    });

    test('no profile + HDR Vivid fact false or unknown → none', () {
      final explicitNo = classifier.classify(
        videoParams: const VideoParams(gamma: 'pq', primaries: 'bt.2020'),
        hdrVivid: false,
      );
      expect(explicitNo.dynamicMetadata, HdrDynamicMetadata.none);
      expect(HdrSourceClass.of(explicitNo), HdrSourceClass.hdr10);

      final unavailable = classifier.classify(
        videoParams: const VideoParams(gamma: 'pq', primaries: 'bt.2020'),
      );
      expect(unavailable.dynamicMetadata, HdrDynamicMetadata.none);
    });

    test('a DV profile wins over HDR Vivid metadata priority', () {
      // DV metadata and HDR Vivid side data never co-occur; the existing
      // switch structure prioritizes the DV branch without special-casing.
      final descriptor = classifier.classify(
        videoParams: const VideoParams(gamma: 'hlg', primaries: 'bt.2020'),
        dolbyVisionProfile: 8,
        dvCompatibilityId: 4,
        hdrVivid: true,
      );
      expect(descriptor.dynamicMetadata, HdrDynamicMetadata.dolbyVision);
      expect(HdrSourceClass.of(descriptor), HdrSourceClass.dvP84);
    });
  });

  group('HdrSourceDescriptor.kind derivation', () {
    test('fixed mapping over the source classes', () {
      HdrMediaKind kindOf(HdrSourceDescriptor descriptor) => descriptor.kind;

      expect(
        kindOf(const HdrSourceDescriptor(
          dynamicMetadata: HdrDynamicMetadata.dolbyVision,
          dvProfile: 5,
        )),
        HdrMediaKind.dolbyVisionP5,
      );
      expect(
        kindOf(const HdrSourceDescriptor(
          dynamicMetadata: HdrDynamicMetadata.dolbyVision,
          dvProfile: 8,
          dvCompatibilityId: 1,
        )),
        HdrMediaKind.hdr10,
      );
      expect(
        kindOf(const HdrSourceDescriptor(
          dynamicMetadata: HdrDynamicMetadata.dolbyVision,
          dvProfile: 7,
          dvCompatibilityId: 6,
        )),
        HdrMediaKind.hdr10,
      );
      expect(
        kindOf(const HdrSourceDescriptor(
          dynamicMetadata: HdrDynamicMetadata.dolbyVision,
          dvProfile: 8,
          dvCompatibilityId: 4,
        )),
        HdrMediaKind.dolbyVisionP84,
      );
      expect(
        kindOf(const HdrSourceDescriptor(
          dynamicMetadata: HdrDynamicMetadata.dolbyVision,
          dvProfile: 8,
          dvCompatibilityId: 2,
        )),
        HdrMediaKind.sdr,
      );
      // P10 follows the base-layer transfer function.
      expect(
        kindOf(const HdrSourceDescriptor(
          codec: 'av1',
          transfer: 'pq',
          primaries: 'bt.2020',
          dynamicMetadata: HdrDynamicMetadata.dolbyVision,
          dvProfile: 10,
        )),
        HdrMediaKind.hdr10,
      );
      expect(
        kindOf(const HdrSourceDescriptor(
          codec: 'av1',
          transfer: 'hlg',
          dynamicMetadata: HdrDynamicMetadata.dolbyVision,
          dvProfile: 10,
        )),
        HdrMediaKind.hlg,
      );
      // Base-layer kinds.
      expect(
        kindOf(const HdrSourceDescriptor(transfer: 'pq', primaries: 'bt.2020')),
        HdrMediaKind.hdr10,
      );
      expect(kindOf(const HdrSourceDescriptor(transfer: 'hlg')),
          HdrMediaKind.hlg);
      expect(kindOf(const HdrSourceDescriptor()), HdrMediaKind.sdr);
    });

    test('profile 8 with unknown compatibility id falls back to the base '
        'layer transfer', () {
      expect(
        const HdrSourceDescriptor(
          transfer: 'hlg',
          dynamicMetadata: HdrDynamicMetadata.dolbyVision,
          dvProfile: 8,
        ).kind,
        HdrMediaKind.dolbyVisionP84,
      );
      expect(
        const HdrSourceDescriptor(
          transfer: 'pq',
          primaries: 'bt.2020',
          dynamicMetadata: HdrDynamicMetadata.dolbyVision,
          dvProfile: 8,
        ).kind,
        HdrMediaKind.hdr10,
      );
    });
  });

  group('HdrSourceDescriptor.fromKind', () {
    test('every kind produces a fully determined description', () {
      const p5 = HdrSourceDescriptor(
        codec: 'hevc',
        dynamicMetadata: HdrDynamicMetadata.dolbyVision,
        dvProfile: 5,
        dvCompatibilityId: 0,
        enhancementLayer: false,
      );
      const p84 = HdrSourceDescriptor(
        codec: 'hevc',
        transfer: 'hlg',
        dynamicMetadata: HdrDynamicMetadata.dolbyVision,
        dvProfile: 8,
        dvCompatibilityId: 4,
        enhancementLayer: false,
      );
      const hdr10 = HdrSourceDescriptor(
        transfer: 'pq',
        primaries: 'bt.2020',
        enhancementLayer: false,
      );
      const hlg = HdrSourceDescriptor(
        transfer: 'hlg',
        enhancementLayer: false,
      );
      const sdr = HdrSourceDescriptor(enhancementLayer: false);

      expect(HdrSourceDescriptor.fromKind(HdrMediaKind.dolbyVisionP5), p5);
      expect(HdrSourceDescriptor.fromKind(HdrMediaKind.dolbyVisionP84), p84);
      expect(HdrSourceDescriptor.fromKind(HdrMediaKind.hdr10), hdr10);
      expect(HdrSourceDescriptor.fromKind(HdrMediaKind.hlg), hlg);
      expect(HdrSourceDescriptor.fromKind(HdrMediaKind.sdr), sdr);
    });

    test('fromKind round-trips through the kind getter', () {
      for (final kind in HdrMediaKind.values) {
        expect(HdrSourceDescriptor.fromKind(kind).kind, kind, reason: '$kind');
      }
    });
  });
}
