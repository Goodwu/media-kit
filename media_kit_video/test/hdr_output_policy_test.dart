import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' show VideoParams;
import 'package:media_kit_video/media_kit_video.dart';

void main() {
  group('classifyMedia', () {
    test('dolby-vision-profile wins over gamma tags', () {
      expect(
        HdrOutputPolicy.classifyMedia(
          videoParams: const VideoParams(gamma: 'pq', primaries: 'bt.2020'),
          dolbyVisionProfile: '5',
        ),
        HdrMediaKind.dolbyVisionP5,
      );
      // The real mpv property is an integer: profile 8 over an HLG base
      // layer is 8.4, not plain HLG. Regression guard for the defect where
      // only the legacy '8.4' hint string was recognized.
      expect(
        HdrOutputPolicy.classifyMedia(
          videoParams: const VideoParams(gamma: 'hlg', primaries: 'bt.2020'),
          dolbyVisionProfile: '8',
        ),
        HdrMediaKind.dolbyVisionP84,
      );
      expect(
        HdrOutputPolicy.classifyMedia(
          videoParams: const VideoParams(gamma: 'pq', primaries: 'bt.2020'),
          dolbyVisionProfile: '8',
        ),
        HdrMediaKind.hdr10,
      );
      // Legacy '8.4' hint string keeps its meaning for old callers.
      expect(
        HdrOutputPolicy.classifyMedia(
          videoParams: const VideoParams(gamma: 'hlg', primaries: 'bt.2020'),
          dolbyVisionProfile: '8.4',
        ),
        HdrMediaKind.dolbyVisionP84,
      );
    });

    test('HLG and HDR10 come from gamma/primaries', () {
      expect(
        HdrOutputPolicy.classifyMedia(
          videoParams: const VideoParams(gamma: 'hlg', primaries: 'bt.2020'),
        ),
        HdrMediaKind.hlg,
      );
      expect(
        HdrOutputPolicy.classifyMedia(
          videoParams: const VideoParams(gamma: 'pq', primaries: 'bt.2020'),
        ),
        HdrMediaKind.hdr10,
      );
    });

    test('PQ with non-BT.2020 primaries and SDR gamma stay SDR', () {
      expect(
        HdrOutputPolicy.classifyMedia(
          videoParams: const VideoParams(gamma: 'pq', primaries: 'bt.709'),
        ),
        HdrMediaKind.sdr,
      );
      expect(
        HdrOutputPolicy.classifyMedia(
          videoParams: const VideoParams(gamma: 'bt.1886', primaries: 'bt.709'),
        ),
        HdrMediaKind.sdr,
      );
      expect(HdrOutputPolicy.classifyMedia(), HdrMediaKind.sdr);
    });
  });

  group('decide: Texture output (no PlatformView)', () {
    test('every HDR kind tone-maps to BT.709/BT.1886 with mediacodec', () {
      for (final kind in HdrMediaKind.values) {
        if (kind == HdrMediaKind.dolbyVisionP5 ||
            kind == HdrMediaKind.sdr) {
          continue;
        }
        final policy = HdrOutputPolicy.decide(
          kind,
          usePlatformView: false,
          p5DoviRescaleAvailable: true,
          displayHdrTypes: null,
        );
        expect(policy.vo, 'gpu-next', reason: '$kind');
        expect(policy.hwdec, 'mediacodec', reason: '$kind');
        expect(policy.targetPrim, 'bt.709', reason: '$kind');
        expect(policy.targetTrc, 'bt.1886', reason: '$kind');
        expect(policy.surfaceTransfer, isNull, reason: '$kind');
        expect(
          policy.stripDvRpu,
          kind == HdrMediaKind.dolbyVisionP84,
          reason: '$kind',
        );
      }
    });

    test('SDR keeps decoder tags instead of tone-map targets', () {
      final policy = HdrOutputPolicy.decide(
        HdrMediaKind.sdr,
        usePlatformView: false,
        p5DoviRescaleAvailable: false,
        displayHdrTypes: null,
      );
      expect(policy.targetPrim, isNull);
      expect(policy.targetTrc, isNull);
      expect(policy.stripDvRpu, isFalse);
    });

    test('P5 requires the dovi rescale pipeline even for Texture SDR', () {
      expect(
        () => HdrOutputPolicy.decide(
          HdrMediaKind.dolbyVisionP5,
          usePlatformView: false,
          p5DoviRescaleAvailable: false,
        ),
        throwsStateError,
      );
    });
  });

  group('decide: PlatformView output', () {
    test('P5 needs a display HDR10 report and takes the PQ surface route', () {
      expect(
        () => HdrOutputPolicy.decide(
          HdrMediaKind.dolbyVisionP5,
          usePlatformView: true,
          p5DoviRescaleAvailable: true,
          displayHdrTypes: null,
        ),
        throwsStateError,
      );
      expect(
        () => HdrOutputPolicy.decide(
          HdrMediaKind.dolbyVisionP5,
          usePlatformView: true,
          p5DoviRescaleAvailable: true,
          displayHdrTypes: const {HdrOutputPolicy.displayHdrTypeHlg},
        ),
        throwsStateError,
      );
      final policy = HdrOutputPolicy.decide(
        HdrMediaKind.dolbyVisionP5,
        usePlatformView: true,
        p5DoviRescaleAvailable: true,
        displayHdrTypes: const {HdrOutputPolicy.displayHdrTypeHdr10},
      );
      expect(policy.vo, 'gpu-next');
      expect(policy.hwdec, 'mediacodec');
      expect(policy.targetPrim, 'bt.2020');
      expect(policy.targetTrc, 'pq');
      expect(policy.surfaceTransfer, 'pq');
      expect(policy.stripDvRpu, isFalse);
    });

    test('HDR10 defaults to mediacodec_embed, gpu route is opt-in', () {
      final embedded = HdrOutputPolicy.decide(
        HdrMediaKind.hdr10,
        usePlatformView: true,
        p5DoviRescaleAvailable: true,
        displayHdrTypes: const {HdrOutputPolicy.displayHdrTypeHdr10},
      );
      expect(embedded.vo, 'mediacodec_embed');
      expect(embedded.targetTrc, isNull);
      expect(embedded.surfaceTransfer, isNull);
      expect(embedded.stripDvRpu, isFalse);

      final gpu = HdrOutputPolicy.decide(
        HdrMediaKind.hdr10,
        usePlatformView: true,
        p5DoviRescaleAvailable: true,
        displayHdrTypes: const {HdrOutputPolicy.displayHdrTypeHdr10},
        preferGpuOutput: true,
      );
      expect(gpu.vo, 'gpu-next');
      expect(gpu.targetTrc, 'pq');
      expect(gpu.surfaceTransfer, 'pq');

      expect(
        () => HdrOutputPolicy.decide(
          HdrMediaKind.hdr10,
          usePlatformView: true,
          p5DoviRescaleAvailable: true,
          displayHdrTypes: const {HdrOutputPolicy.displayHdrTypeHlg},
        ),
        throwsStateError,
      );
    });

    test('HLG needs display HLG and takes mediacodec_embed', () {
      final policy = HdrOutputPolicy.decide(
        HdrMediaKind.hlg,
        usePlatformView: true,
        p5DoviRescaleAvailable: true,
        displayHdrTypes: const {HdrOutputPolicy.displayHdrTypeHlg},
      );
      expect(policy.vo, 'mediacodec_embed');
      expect(policy.surfaceTransfer, isNull);
      expect(
        () => HdrOutputPolicy.decide(
          HdrMediaKind.hlg,
          usePlatformView: true,
          p5DoviRescaleAvailable: true,
          displayHdrTypes: const {HdrOutputPolicy.displayHdrTypeHdr10},
        ),
        throwsStateError,
      );
    });

    test('P8.4 prefers HLG, falls back to HDR10, and never guesses', () {
      // HLG display: direct embed, RPU kept for the dolby-compatible path.
      final hlg = HdrOutputPolicy.decide(
        HdrMediaKind.dolbyVisionP84,
        usePlatformView: true,
        p5DoviRescaleAvailable: true,
        displayHdrTypes: const {HdrOutputPolicy.displayHdrTypeHlg},
      );
      expect(hlg.vo, 'mediacodec_embed');
      expect(hlg.stripDvRpu, isFalse);

      // HLG display with the gpu route opted in: strip the RPU and render
      // the HLG base layer through a PQ/HLG-capable GPU surface.
      final hlgGpu = HdrOutputPolicy.decide(
        HdrMediaKind.dolbyVisionP84,
        usePlatformView: true,
        p5DoviRescaleAvailable: true,
        displayHdrTypes: const {HdrOutputPolicy.displayHdrTypeHlg},
        preferGpuOutput: true,
      );
      expect(hlgGpu.vo, 'gpu-next');
      expect(hlgGpu.targetTrc, 'hlg');
      expect(hlgGpu.surfaceTransfer, 'hlg');
      expect(hlgGpu.stripDvRpu, isTrue);

      // HDR10-only display: strip the RPU and tone-map through PQ.
      final hdr10 = HdrOutputPolicy.decide(
        HdrMediaKind.dolbyVisionP84,
        usePlatformView: true,
        p5DoviRescaleAvailable: true,
        displayHdrTypes: const {HdrOutputPolicy.displayHdrTypeHdr10},
      );
      expect(hdr10.vo, 'gpu-next');
      expect(hdr10.targetTrc, 'pq');
      expect(hdr10.surfaceTransfer, 'pq');
      expect(hdr10.stripDvRpu, isTrue);

      expect(
        () => HdrOutputPolicy.decide(
          HdrMediaKind.dolbyVisionP84,
          usePlatformView: true,
          p5DoviRescaleAvailable: true,
          displayHdrTypes: const <int>{},
        ),
        throwsStateError,
      );
    });

    test('SDR needs no display report', () {
      final policy = HdrOutputPolicy.decide(
        HdrMediaKind.sdr,
        usePlatformView: true,
        p5DoviRescaleAvailable: false,
        displayHdrTypes: null,
      );
      expect(policy.vo, 'gpu-next');
      expect(policy.targetPrim, isNull);
      expect(policy.surfaceTransfer, isNull);
      expect(policy.stripDvRpu, isFalse);
    });
  });
}
