import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit_test/common/sources/android_hdr_playback_policy.dart';
import 'package:media_kit_test/common/sources/android_hdr_sample_identity.dart';

void main() {
  test('P5 runtime gate requires RPU attachment and raw YUV together', () {
    expect(
      () => requireAndroidP5RuntimePipeline({
        'debug.media_kit.p5_rpu_probe': '2',
        'debug.media_kit.p5_raw_yuv': '1',
      }),
      returnsNormally,
    );
    for (final values in <Map<String, String>>[
      {},
      {'debug.media_kit.p5_rpu_probe': '1', 'debug.media_kit.p5_raw_yuv': '1'},
      {'debug.media_kit.p5_rpu_probe': '2', 'debug.media_kit.p5_raw_yuv': '0'},
    ]) {
      expect(() => requireAndroidP5RuntimePipeline(values), throwsStateError);
    }
  });

  test('Texture maps all fixed sources to SDR and strips only P8.4 RPU', () {
    for (final sample in AndroidHdrSample.values) {
      final policy = AndroidHdrPlaybackPolicy.forSample(
        sample,
        usePlatformView: false,
        p5RpuPipelineBuilt: true,
      );
      expect(policy.vo, 'gpu-next');
      expect(policy.hwdec, 'mediacodec');
      expect(policy.targetPrim, 'bt.709');
      expect(policy.targetTrc, 'bt.1886');
      expect(policy.surfaceTransfer, isNull);
      expect(policy.stripP84Rpu, sample == AndroidHdrSample.dolbyVisionP84);
    }
  });

  test('8-bit MediaCodec copy is opt-in for non-P5 Texture diagnostics', () {
    for (final sample in AndroidHdrSample.values) {
      final policy = AndroidHdrPlaybackPolicy.forSample(
        sample,
        usePlatformView: false,
        p5RpuPipelineBuilt: true,
        textureCopyDiagnostic: true,
      );
      expect(
          policy.hwdec,
          sample == AndroidHdrSample.dolbyVisionP5
              ? 'mediacodec'
              : 'mediacodec-copy');
    }
  });

  test('PlatformView uses direct compatible output except P5 conversion', () {
    for (final sample in [
      AndroidHdrSample.hdr10,
      AndroidHdrSample.hlgBaseControl,
      AndroidHdrSample.dolbyVisionP84,
    ]) {
      final policy = AndroidHdrPlaybackPolicy.forSample(
        sample,
        usePlatformView: true,
        p5RpuPipelineBuilt: false,
        displayHdrTypes: {2, 3},
      );
      expect(policy.vo, 'mediacodec_embed');
      expect(policy.stripP84Rpu, isFalse);
      expect(policy.targetTrc, isNull);
      expect(policy.surfaceTransfer, isNull);
    }
    final p5 = AndroidHdrPlaybackPolicy.forSample(
      AndroidHdrSample.dolbyVisionP5,
      usePlatformView: true,
      p5RpuPipelineBuilt: true,
      displayHdrTypes: {2, 3},
    );
    expect(p5.vo, 'gpu-next');
    expect(p5.targetTrc, 'pq');
    expect(p5.surfaceTransfer, 'pq');
    expect(p5.stripP84Rpu, isFalse);
  });

  test('HLG base control never falls back to PQ or applies DV metadata', () {
    final policy = AndroidHdrPlaybackPolicy.forSample(
      AndroidHdrSample.hlgBaseControl,
      usePlatformView: true,
      p5RpuPipelineBuilt: false,
      displayHdrTypes: {2, 3},
      gpuPlatformHdrExperiment: true,
    );
    expect(policy.vo, 'mediacodec_embed');
    expect(policy.stripP84Rpu, isFalse);
    expect(policy.surfaceTransfer, isNull);
    expect(
      () => AndroidHdrPlaybackPolicy.forSample(
        AndroidHdrSample.hlgBaseControl,
        usePlatformView: true,
        p5RpuPipelineBuilt: false,
        displayHdrTypes: {2},
      ),
      throwsStateError,
    );
  });

  test('P5 PlatformView SDR diagnostic matches Texture conversion target', () {
    final policy = AndroidHdrPlaybackPolicy.forSample(
      AndroidHdrSample.dolbyVisionP5,
      usePlatformView: true,
      p5RpuPipelineBuilt: true,
      displayHdrTypes: {2, 3},
      p5PlatformSdrDiagnostic: true,
    );
    expect(policy.vo, 'gpu-next');
    expect(policy.hwdec, 'mediacodec');
    expect(policy.targetPrim, 'bt.709');
    expect(policy.targetTrc, 'bt.1886');
    expect(policy.surfaceTransfer, isNull);
    expect(policy.stripP84Rpu, isFalse);
  });

  test('P5 cannot be selected without a built RPU-preserving pipeline', () {
    expect(
      () => AndroidHdrPlaybackPolicy.forSample(
        AndroidHdrSample.dolbyVisionP5,
        usePlatformView: false,
        p5RpuPipelineBuilt: false,
      ),
      throwsStateError,
    );
  });

  test('P8.4 falls back from HLG to PQ only with HDR10 support', () {
    final fallback = AndroidHdrPlaybackPolicy.forSample(
      AndroidHdrSample.dolbyVisionP84,
      usePlatformView: true,
      p5RpuPipelineBuilt: false,
      displayHdrTypes: {2},
    );
    expect(fallback.vo, 'gpu-next');
    expect(fallback.targetTrc, 'pq');
    expect(fallback.surfaceTransfer, 'pq');
    expect(fallback.stripP84Rpu, isTrue);
    for (final types in <Set<int>?>[
      null,
      {},
      {1}
    ]) {
      expect(
        () => AndroidHdrPlaybackPolicy.forSample(
          AndroidHdrSample.dolbyVisionP84,
          usePlatformView: true,
          p5RpuPipelineBuilt: false,
          displayHdrTypes: types,
        ),
        throwsStateError,
      );
    }
  });

  test('forced P8.4 fallback keeps actual HDR10 capability mandatory', () {
    final policy = AndroidHdrPlaybackPolicy.forSample(
      AndroidHdrSample.dolbyVisionP84,
      usePlatformView: true,
      p5RpuPipelineBuilt: false,
      displayHdrTypes: {2, 3},
      forceP84PqFallback: true,
    );
    expect(policy.vo, 'gpu-next');
    expect(policy.targetTrc, 'pq');
    expect(policy.surfaceTransfer, 'pq');
    expect(
      () => AndroidHdrPlaybackPolicy.forSample(
        AndroidHdrSample.dolbyVisionP84,
        usePlatformView: true,
        p5RpuPipelineBuilt: false,
        displayHdrTypes: {3},
        forceP84PqFallback: true,
      ),
      throwsStateError,
    );
  });

  test('GPU Platform HDR is opt-in and keeps input-specific transfer', () {
    final hdr10 = AndroidHdrPlaybackPolicy.forSample(
      AndroidHdrSample.hdr10,
      usePlatformView: true,
      p5RpuPipelineBuilt: false,
      displayHdrTypes: {2, 3},
      gpuPlatformHdrExperiment: true,
    );
    expect(hdr10.vo, 'gpu-next');
    expect(hdr10.targetPrim, 'bt.2020');
    expect(hdr10.targetTrc, 'pq');
    expect(hdr10.surfaceTransfer, 'pq');
    expect(hdr10.stripP84Rpu, isFalse);

    final p84 = AndroidHdrPlaybackPolicy.forSample(
      AndroidHdrSample.dolbyVisionP84,
      usePlatformView: true,
      p5RpuPipelineBuilt: false,
      displayHdrTypes: {2, 3},
      gpuPlatformHdrExperiment: true,
    );
    expect(p84.vo, 'gpu-next');
    expect(p84.targetPrim, 'bt.2020');
    expect(p84.targetTrc, 'hlg');
    expect(p84.surfaceTransfer, 'hlg');
    expect(p84.stripP84Rpu, isTrue);

    final p5 = AndroidHdrPlaybackPolicy.forSample(
      AndroidHdrSample.dolbyVisionP5,
      usePlatformView: true,
      p5RpuPipelineBuilt: true,
      displayHdrTypes: {2, 3},
      gpuPlatformHdrExperiment: true,
    );
    expect(p5.vo, 'gpu-next');
    expect(p5.surfaceTransfer, 'pq');
    expect(p5.stripP84Rpu, isFalse);

    final texture = AndroidHdrPlaybackPolicy.forSample(
      AndroidHdrSample.dolbyVisionP84,
      usePlatformView: false,
      p5RpuPipelineBuilt: false,
      gpuPlatformHdrExperiment: true,
    );
    expect(texture.targetTrc, 'bt.1886');
    expect(texture.surfaceTransfer, isNull);
  });

  test('GPU Platform HDR still fails closed on absent capability', () {
    for (final types in <Set<int>?>[
      null,
      {},
      {1},
      {3}
    ]) {
      expect(
        () => AndroidHdrPlaybackPolicy.forSample(
          AndroidHdrSample.hdr10,
          usePlatformView: true,
          p5RpuPipelineBuilt: false,
          displayHdrTypes: types,
          gpuPlatformHdrExperiment: true,
        ),
        throwsStateError,
      );
    }
    for (final types in <Set<int>?>[
      null,
      {},
      {1}
    ]) {
      expect(
        () => AndroidHdrPlaybackPolicy.forSample(
          AndroidHdrSample.dolbyVisionP84,
          usePlatformView: true,
          p5RpuPipelineBuilt: false,
          displayHdrTypes: types,
          gpuPlatformHdrExperiment: true,
        ),
        throwsStateError,
      );
    }
    final pqFallback = AndroidHdrPlaybackPolicy.forSample(
      AndroidHdrSample.dolbyVisionP84,
      usePlatformView: true,
      p5RpuPipelineBuilt: false,
      displayHdrTypes: {2},
      gpuPlatformHdrExperiment: true,
    );
    expect(pqFallback.surfaceTransfer, 'pq');
    expect(pqFallback.stripP84Rpu, isTrue);
    expect(
      () => AndroidHdrPlaybackPolicy.forSample(
        AndroidHdrSample.dolbyVisionP84,
        usePlatformView: true,
        p5RpuPipelineBuilt: false,
        displayHdrTypes: {3},
        forceP84PqFallback: true,
        gpuPlatformHdrExperiment: true,
      ),
      throwsStateError,
    );
  });
}
