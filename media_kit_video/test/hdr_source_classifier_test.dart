import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' show VideoParams;
import 'package:media_kit_video/src/hdr/hdr_output_policy.dart'
    show HdrMediaKind;
import 'package:media_kit_video/src/hdr/hdr_source_classifier.dart';
import 'package:media_kit_video/src/hdr/hdr_source_descriptor.dart';

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
      // HDR10+/HDR Vivid are not observable through mpv yet: none.
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
