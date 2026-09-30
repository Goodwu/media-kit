import 'package:media_kit_video/media_kit_video.dart';

import 'android_hdr_sample_identity.dart';

/// Test-app adapter over the library's [HdrOutputPolicy].
///
/// The routing matrix itself lives in media_kit_video and is unit-tested
/// there; this layer only maps a verified sample identity to its media kind
/// and applies the test-app-only experiment switches (diagnostic routes and
/// simulated display capabilities).
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

  static HdrMediaKind _kindFor(AndroidHdrSample sample) {
    switch (sample) {
      case AndroidHdrSample.hdr10:
        return HdrMediaKind.hdr10;
      case AndroidHdrSample.hlgBaseControl:
        return HdrMediaKind.hlg;
      case AndroidHdrSample.dolbyVisionP84:
        return HdrMediaKind.dolbyVisionP84;
      case AndroidHdrSample.dolbyVisionP5:
        return HdrMediaKind.dolbyVisionP5;
    }
  }

  static AndroidHdrPlaybackPolicy _from(HdrOutputPolicy policy) =>
      AndroidHdrPlaybackPolicy(
        vo: policy.vo,
        hwdec: policy.hwdec,
        targetPrim: policy.targetPrim,
        targetTrc: policy.targetTrc,
        surfaceTransfer: policy.surfaceTransfer,
        stripP84Rpu: policy.stripDvRpu,
      );

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
    final kind = _kindFor(sample);
    if (!usePlatformView) {
      final policy = _from(HdrOutputPolicy.decide(
        kind,
        usePlatformView: false,
        p5DoviRescaleAvailable: p5RpuPipelineBuilt,
      ));
      if (textureCopyDiagnostic && sample != AndroidHdrSample.dolbyVisionP5) {
        return AndroidHdrPlaybackPolicy(
          vo: policy.vo,
          hwdec: 'mediacodec-copy',
          targetPrim: policy.targetPrim,
          targetTrc: policy.targetTrc,
          surfaceTransfer: policy.surfaceTransfer,
          stripP84Rpu: policy.stripP84Rpu,
        );
      }
      return policy;
    }
    if (displayHdrTypes == null) {
      throw StateError('No display HDR capability report');
    }
    if (sample == AndroidHdrSample.dolbyVisionP5 && p5PlatformSdrDiagnostic) {
      // Diagnostic: route P5 through the platform view as SDR.
      return _from(HdrOutputPolicy.decide(
        kind,
        usePlatformView: false,
        p5DoviRescaleAvailable: p5RpuPipelineBuilt,
      ));
    }
    // forceP84PqFallback simulates a display without HLG support.
    final display = forceP84PqFallback
        ? displayHdrTypes
            .where((type) => type != HdrOutputPolicy.displayHdrTypeHlg)
            .toSet()
        : displayHdrTypes;
    return _from(HdrOutputPolicy.decide(
      kind,
      usePlatformView: true,
      p5DoviRescaleAvailable: p5RpuPipelineBuilt,
      displayHdrTypes: display,
      preferGpuOutput: gpuPlatformHdrExperiment,
    ));
  }
}
