import 'android_hdr_sample_identity.dart';

class AndroidHdrPlaybackPolicy {
  const AndroidHdrPlaybackPolicy({
    required this.vo,
    required this.hwdec,
    required this.targetPrim,
    required this.targetTrc,
    required this.surfaceTransfer,
    required this.stripP84Rpu,
  });

  final String vo;
  final String hwdec;
  final String? targetPrim;
  final String? targetTrc;

  /// Requested PlatformView dataspace for GPU output; direct/Texture output
  /// has no GPU HDR transfer to apply.
  final String? surfaceTransfer;
  final bool stripP84Rpu;

  static AndroidHdrPlaybackPolicy forSample(
    AndroidHdrSample sample, {
    required bool usePlatformView,
    required bool p5RpuPipelineBuilt,
    Set<int>? displayHdrTypes,
    bool forceP84PqFallback = false,
    bool gpuPlatformHdrExperiment = false,
    bool p5PlatformSdrDiagnostic = false,
    bool textureCopyDiagnostic = false,
  }) {
    if (sample == AndroidHdrSample.dolbyVisionP5 && !p5RpuPipelineBuilt) {
      throw StateError('P5 RPU-preserving native pipeline is not built');
    }
    if (!usePlatformView) {
      return AndroidHdrPlaybackPolicy(
        vo: 'gpu-next',
        hwdec: textureCopyDiagnostic && sample != AndroidHdrSample.dolbyVisionP5
            ? 'mediacodec-copy'
            : 'mediacodec',
        targetPrim: 'bt.709',
        targetTrc: 'bt.1886',
        surfaceTransfer: null,
        stripP84Rpu: sample == AndroidHdrSample.dolbyVisionP84,
      );
    }
    // Android Display.HdrCapabilities: HDR10=2, HLG=3. An absent capability
    // report must not silently select an HDR output route.
    if (displayHdrTypes == null) {
      throw StateError('No display HDR capability report');
    }
    if (sample == AndroidHdrSample.dolbyVisionP5 && p5PlatformSdrDiagnostic) {
      return const AndroidHdrPlaybackPolicy(
        vo: 'gpu-next',
        hwdec: 'mediacodec',
        targetPrim: 'bt.709',
        targetTrc: 'bt.1886',
        surfaceTransfer: null,
        stripP84Rpu: false,
      );
    }
    if (sample == AndroidHdrSample.hlgBaseControl) {
      if (!displayHdrTypes.contains(3)) {
        throw StateError('HLG base control requires display HLG support');
      }
      return const AndroidHdrPlaybackPolicy(
        vo: 'mediacodec_embed',
        hwdec: 'mediacodec',
        targetPrim: null,
        targetTrc: null,
        surfaceTransfer: null,
        stripP84Rpu: false,
      );
    }
    if (sample == AndroidHdrSample.dolbyVisionP84) {
      if (displayHdrTypes.contains(3) && !forceP84PqFallback) {
        if (gpuPlatformHdrExperiment) {
          return const AndroidHdrPlaybackPolicy(
            vo: 'gpu-next',
            hwdec: 'mediacodec',
            targetPrim: 'bt.2020',
            targetTrc: 'hlg',
            surfaceTransfer: 'hlg',
            stripP84Rpu: true,
          );
        }
        return const AndroidHdrPlaybackPolicy(
          vo: 'mediacodec_embed',
          hwdec: 'mediacodec',
          targetPrim: null,
          targetTrc: null,
          surfaceTransfer: null,
          stripP84Rpu: false,
        );
      }
      if (displayHdrTypes.contains(2)) {
        return const AndroidHdrPlaybackPolicy(
          vo: 'gpu-next',
          hwdec: 'mediacodec',
          targetPrim: 'bt.2020',
          targetTrc: 'pq',
          surfaceTransfer: 'pq',
          stripP84Rpu: true,
        );
      }
      throw StateError('P8.4 requires display HLG or HDR10 support');
    }
    if (!displayHdrTypes.contains(2)) {
      throw StateError('PQ output requires display HDR10 support');
    }
    if (sample == AndroidHdrSample.dolbyVisionP5) {
      return const AndroidHdrPlaybackPolicy(
        vo: 'gpu-next',
        hwdec: 'mediacodec',
        targetPrim: 'bt.2020',
        targetTrc: 'pq',
        surfaceTransfer: 'pq',
        stripP84Rpu: false,
      );
    }
    return gpuPlatformHdrExperiment
        ? const AndroidHdrPlaybackPolicy(
            vo: 'gpu-next',
            hwdec: 'mediacodec',
            targetPrim: 'bt.2020',
            targetTrc: 'pq',
            surfaceTransfer: 'pq',
            stripP84Rpu: false,
          )
        : const AndroidHdrPlaybackPolicy(
            vo: 'mediacodec_embed',
            hwdec: 'mediacodec',
            targetPrim: null,
            targetTrc: null,
            surfaceTransfer: null,
            stripP84Rpu: false,
          );
  }
}
