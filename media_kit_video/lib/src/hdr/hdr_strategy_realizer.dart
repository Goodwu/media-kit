/// This file is a part of media_kit (https://github.com/media-kit/media-kit).
///
/// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
/// All rights reserved.
/// Use of this source code is governed by MIT license that can be found in the LICENSE file.
import 'package:flutter/foundation.dart'
    show debugPrint, visibleForTesting;
import 'hdr_capabilities.dart';
import 'hdr_mkst_bridge_probe.dart';
import 'hdr_output_policy.dart' show HdrOutputPolicy;
import 'hdr_route.dart';
import 'hdr_source_descriptor.dart';
import 'hdr_strategy.dart';
import 'hdr_yuv_presentation_contract.dart';

/// The outcome of realizing one strategy: either a concrete route, or the
/// typed reason the strategy is infeasible for this source on this device.
class HdrStrategyRealization {
  const HdrStrategyRealization.route(this.route) : infeasibleReason = null;

  const HdrStrategyRealization.infeasible(this.infeasibleReason) : route = null;

  final HdrRoute? route;

  final HdrDegradeReason? infeasibleReason;
}

/// {@template hdr_strategy_realizer}
///
/// HdrStrategyRealizer
/// -------------------
/// Realizes a single [HdrStrategy] into an [HdrRoute] following the mapping
/// table in plan section 1.3, or reports why it is infeasible.
///
/// The vo/hwdec/target-prim/target-trc/surface values reuse the semantics of
/// the existing `HdrOutputPolicy.decide` branches (same literals) and add
/// the combinations `decide` does not have (conversion, reshape, per-profile
/// SDR routes). Display-feasibility failures are reported as
/// [HdrDegradeReason.noDisplayCapabilityReport] (no report at all) or
/// [HdrDegradeReason.displayLacksTransfer] (report present, type missing).
///
/// {@endtemplate}
class HdrStrategyRealizer {
  const HdrStrategyRealizer._();

  /// Realizes [strategy] for [source] (of class [sourceClass]) against the
  /// device [capabilities].
  static HdrStrategyRealization realize(
    HdrStrategy strategy, {
    required HdrSourceDescriptor source,
    required HdrSourceClass sourceClass,
    required HdrCapabilities capabilities,
  }) {
    switch (strategy) {
      case HdrStrategy.nativeDolbyVision:
        return _nativeDolbyVision(source, sourceClass, capabilities);
      case HdrStrategy.baseLayerDirect:
        return _baseLayerDirect(source, sourceClass, capabilities);
      case HdrStrategy.baseLayerConvert:
        return _baseLayerConvert(source, sourceClass, capabilities);
      case HdrStrategy.metadataReshape:
        return _metadataReshape(source, sourceClass, capabilities);
      case HdrStrategy.toneMapSdr:
        return _toneMapSdr(source, sourceClass, capabilities);
      case HdrStrategy.sdrDirect:
        return _sdrDirect(source, sourceClass, capabilities);
    }
  }

  /// Native Dolby Vision P5 decode through MediaCodec and the DV bridge.
  /// This bypasses libplacebo's P5 rescale pipeline while keeping the RPU in
  /// the elementary stream for the native Dolby Vision decoder.
  static HdrStrategyRealization _nativeDolbyVision(
    HdrSourceDescriptor source,
    HdrSourceClass cls,
    HdrCapabilities capabilities,
  ) {
    // 2026-10-06: dvP84 unlocked alongside dvP5 (user-directed direct-path
    // verification on the LG DV device). P8.4 = profile 8, compatibility id 4
    // (HLG base layer + enhancement/RPU); the Dolby engine handles the
    // enhancement the same way the P5.0 single-layer case hands everything to
    // it. Other classes/profiles remain unsupported.
    final bool eligibleSource = (cls == HdrSourceClass.dvP5 &&
            source.dvProfile == 5 &&
            source.dvCompatibilityId == 0 &&
            source.enhancementLayer == false) ||
        (cls == HdrSourceClass.dvP84 &&
            source.dvProfile == 8 &&
            source.dvCompatibilityId == 4);
    if (!eligibleSource ||
        source.codec != 'hevc' ||
        source.dynamicMetadata != HdrDynamicMetadata.dolbyVision) {
      return const HdrStrategyRealization.infeasible(
          HdrDegradeReason.unsupportedStrategy);
    }
    final types = capabilities.displayHdrTypes;
    if (types == null) {
      return const HdrStrategyRealization.infeasible(
          HdrDegradeReason.noDisplayCapabilityReport);
    }
    if (!types.contains(1)) {
      return const HdrStrategyRealization.infeasible(
          HdrDegradeReason.displayLacksTransfer);
    }
    const int dolbyVisionProfile32 = 32;
    final hasDolbyVisionDecoder = capabilities.dolbyVisionDecoders.any(
      (decoder) =>
          decoder.mimeType == 'video/dolby-vision' &&
          decoder.hardwareAcceleration &&
          decoder.profiles.contains(dolbyVisionProfile32),
    );
    if (!hasDolbyVisionDecoder || capabilities.nativeDvBridgeApi != 1) {
      return const HdrStrategyRealization.infeasible(
          HdrDegradeReason.nativeDvUnavailable);
    }
    // P5 keeps the verified timed release. The API 24 vendor DV decoder
    // holds at-time released buffers (on-device r28 chain: frames decoded,
    // playback advancing, screen frozen 48s), so P8.4 releases immediately.
    final renderMode = cls == HdrSourceClass.dvP84 ? 'boolean' : 'timed';
    return HdrStrategyRealization.route(
      HdrRoute(
        strategy: HdrStrategy.nativeDolbyVision,
        presentation: HdrPresentation.nativeDolbyVision,
        outputTransfer: HdrOutputTransfer.dolbyVision,
        appliesDynamicMetadata: true,
        topology: HdrTopology.platformView,
        vo: 'mediacodec_embed',
        hwdec: 'mediacodec',
        vdLavcOptions: 'native_dv=1',
        mediacodecEmbedRenderMode: renderMode,
        targetPrim: null,
        targetTrc: null,
        surfaceTransfer: null,
        stripDvRpu: false,
        dependencies: const <String>{
          HdrRouteDependency.nativeDolbyVision,
          HdrRouteDependency.hwdecMediacodec,
          HdrRouteDependency.topologyPlatformView,
        },
      ),
    );
  }

  /// `mediacodec_embed` direct output at the base-layer transfer function.
  ///
  /// PQ output requires display HDR10 (2), HLG output requires display HLG
  /// (3). The decoder ignores the RPU on this route, so profile 5 (whose
  /// IPT base layer shifts color without it) must not take it — the same
  /// reason P8.2's SDR base layer is the only DV family allowed to emit SDR
  /// directly here. Profile 10 (AV1) is out of Phase 1 scope.
  static HdrStrategyRealization _baseLayerDirect(
    HdrSourceDescriptor source,
    HdrSourceClass cls,
    HdrCapabilities capabilities,
  ) {
    if (cls == HdrSourceClass.dvP5 || cls == HdrSourceClass.dvP10) {
      return const HdrStrategyRealization.infeasible(
          HdrDegradeReason.unsupportedStrategy);
    }
    final HdrOutputTransfer transfer = _baseLayerTransfer(source, cls);
    if (transfer != HdrOutputTransfer.sdr) {
      final HdrDegradeReason? reason =
          _displayTransferCheck(transfer, capabilities);
      if (reason != null) {
        // An HLG base layer stays presentable on a panel that declares
        // Dolby Vision without HLG: the system composer interprets the HLG
        // buffer itself (the platform player plays P8.4 this way on the
        // API 24 LG device — smooth, desaturated, no dynamic metadata).
        // Every other missing transfer stays infeasible.
        final bool hlgOverDvPanel =
            reason == HdrDegradeReason.displayLacksTransfer &&
                transfer == HdrOutputTransfer.hlg &&
                capabilities.displayHdrTypes?.contains(1) == true;
        if (!hlgOverDvPanel) {
          return HdrStrategyRealization.infeasible(reason);
        }
      }
    }
    return HdrStrategyRealization.route(
      HdrRoute(
        strategy: HdrStrategy.baseLayerDirect,
        presentation: transfer == HdrOutputTransfer.sdr
            ? HdrPresentation.sdr
            : HdrPresentation.nativeHdr,
        outputTransfer: transfer,
        appliesDynamicMetadata: false,
        topology: HdrTopology.platformView,
        vo: 'mediacodec_embed',
        hwdec: 'mediacodec',
        targetPrim: null,
        targetTrc: null,
        surfaceTransfer: null,
        // The decoder ignores the RPU on the compat path; nothing to strip.
        stripDvRpu: false,
        dependencies: const <String>{
          HdrRouteDependency.hwdecMediacodec,
          HdrRouteDependency.topologyPlatformView,
        },
      ),
    );
  }

  /// `gpu-next` conversion of the base layer to a display-supported HDR
  /// transfer function on a `rgb10_a2` PlatformView surface, PQ preferred.
  /// DV sources strip the RPU on this route; profile 5 never applies.
  static HdrStrategyRealization _baseLayerConvert(
    HdrSourceDescriptor source,
    HdrSourceClass cls,
    HdrCapabilities capabilities,
  ) {
    if (cls == HdrSourceClass.dvP5 || cls == HdrSourceClass.dvP10) {
      return const HdrStrategyRealization.infeasible(
          HdrDegradeReason.unsupportedStrategy);
    }
    if (_gpuHdrDataSpaceUnavailable(capabilities)) {
      return const HdrStrategyRealization.infeasible(
          HdrDegradeReason.gpuHdrDataSpaceUnavailable);
    }
    final Set<int>? types = capabilities.displayHdrTypes;
    if (types == null) {
      return const HdrStrategyRealization.infeasible(
          HdrDegradeReason.noDisplayCapabilityReport);
    }
    final HdrOutputTransfer output;
    if (types.contains(HdrOutputPolicy.displayHdrTypeHdr10)) {
      output = HdrOutputTransfer.pq;
    } else if (types.contains(HdrOutputPolicy.displayHdrTypeHlg)) {
      output = HdrOutputTransfer.hlg;
    } else {
      return const HdrStrategyRealization.infeasible(
          HdrDegradeReason.displayLacksTransfer);
    }
    if (output == HdrOutputTransfer.pq &&
        (_convertPqSurfaceTransfer != 'pq' &&
            (_convertPqSurfaceTransfer != 'pq-itu' ||
                !_convertRouteLock ||
                capabilities.sdkInt != 24 ||
                capabilities.dataSpaceExt?.id != 'lg-pq' ||
                capabilities.dataSpaceExt?.applicable != true))) {
      return const HdrStrategyRealization.infeasible(
          HdrDegradeReason.unsupportedStrategy);
    }
    final String trc = output == HdrOutputTransfer.pq ? 'pq' : 'hlg';
    // API < 26 has no non-copy mediacodec GPU import; the convert route
    // then decodes through mediacodec-copy like the SDR routes.
    final bool useMediacodecCopy = _requiresMediacodecCopy(capabilities);
    final String routedHwdec =
        useMediacodecCopy ? 'mediacodec-copy' : 'mediacodec';
    // The official backend applies at this decision point only when the
    // bridge reports an owner-bound explicit init; every gate above
    // (applicability, display capability, transfer whitelist) has already
    // passed, so the override rides the same admission as the routed value.
    // Other strategies never consult the bridge.
    final String hwdec = surfaceTexturePocHwdec(
      routedHwdec,
      officialBackendReady:
          mkstBridgeProbeOverride?.call() ?? mkstBridgeInitialized(),
    );
    if (hwdec != routedHwdec) {
      debugPrint('MKSURF-POC: route hwdec override $routedHwdec -> $hwdec');
    }
    // A4 contract split, P8.4 A5 V2 review fix: the separate offscreen
    // contract is keyed on the CARRIER, not on the requested window label.
    // The `surfacetexture` hwdec is the LG yuv-diag path's only carrier and
    // presents the actual YUV shape (the vendor forces the 0x11C60000 window
    // label for either PQ request in yuvDiag mode), so the offscreen
    // contract (full-range normalized PQ in the offscreen FBO, realized
    // mpv-side by the owned video-output-levels=full write) must be declared
    // for the product-default `pq` request too, not only for the locked
    // `pq-itu` experiment. RGB window routes (plain mediacodec /
    // mediacodec-copy carriers) share a single output contract and keep
    // offscreenTransfer null.
    final bool yuvWindowContract = hwdec == 'surfacetexture' &&
        output == HdrOutputTransfer.pq &&
        (_convertPqSurfaceTransfer == 'pq' ||
            _convertPqSurfaceTransfer ==
                HdrYuvPresentationContract.windowTransfer);
    return HdrStrategyRealization.route(
      HdrRoute(
        strategy: HdrStrategy.baseLayerConvert,
        presentation: HdrPresentation.nativeHdr,
        outputTransfer: output,
        appliesDynamicMetadata: false,
        topology: HdrTopology.platformView,
        vo: 'gpu-next',
        hwdec: hwdec,
        targetPrim: 'bt.2020',
        targetTrc: trc,
        // Keep the production PQ label unchanged. A limited-range override
        // is admitted only for the explicitly locked LG lab experiment.
        surfaceTransfer:
            output == HdrOutputTransfer.pq ? _convertPqSurfaceTransfer : trc,
        offscreenTransfer: yuvWindowContract
            ? HdrYuvPresentationContract.offscreenTransfer
            : null,
        stripDvRpu: source.dynamicMetadata == HdrDynamicMetadata.dolbyVision,
        dependencies: <String>{
          useMediacodecCopy
              ? HdrRouteDependency.hwdecMediacodecCopy
              : HdrRouteDependency.hwdecMediacodec,
          HdrRouteDependency.topologyPlatformView,
          output == HdrOutputTransfer.pq
              ? HdrRouteDependency.dataspacePq
              : HdrRouteDependency.dataspaceHlg,
        },
      ),
    );
  }

  /// `gpu-next`/libplacebo RPU reshape to a PQ `rgb10_a2` PlatformView
  /// surface. Every Dolby Vision reshape depends on the fork's P5 dovi
  /// rescale pipeline; HDR Vivid rebuild is not implemented; a profile 7
  /// stream whose enhancement layer is unknown (or present, i.e. possibly
  /// FEL) may only take the base-layer direct route (requirement 3.1).
  static HdrStrategyRealization _metadataReshape(
    HdrSourceDescriptor source,
    HdrSourceClass cls,
    HdrCapabilities capabilities,
  ) {
    if (cls == HdrSourceClass.hdrVivid || cls == HdrSourceClass.dvP10) {
      return const HdrStrategyRealization.infeasible(
          HdrDegradeReason.unsupportedStrategy);
    }
    final bool isDv = source.dynamicMetadata == HdrDynamicMetadata.dolbyVision;
    if (isDv) {
      if (!capabilities.p5PipelineAvailable) {
        return const HdrStrategyRealization.infeasible(
            HdrDegradeReason.p5PipelineUnavailable);
      }
      if (cls == HdrSourceClass.dvP7 && source.enhancementLayer != false) {
        return const HdrStrategyRealization.infeasible(
            HdrDegradeReason.unsupportedStrategy);
      }
    }
    if (_gpuHdrDataSpaceUnavailable(capabilities)) {
      return const HdrStrategyRealization.infeasible(
          HdrDegradeReason.gpuHdrDataSpaceUnavailable);
    }
    final HdrDegradeReason? reason =
        _displayTransferCheck(HdrOutputTransfer.pq, capabilities);
    if (reason != null) {
      return HdrStrategyRealization.infeasible(reason);
    }
    return HdrStrategyRealization.route(
      HdrRoute(
        strategy: HdrStrategy.metadataReshape,
        presentation: HdrPresentation.nativeHdr,
        outputTransfer: HdrOutputTransfer.pq,
        appliesDynamicMetadata: isDv,
        topology: HdrTopology.platformView,
        vo: 'gpu-next',
        hwdec: 'mediacodec',
        targetPrim: 'bt.2020',
        targetTrc: 'pq',
        surfaceTransfer: 'pq',
        // The RPU is the input of the rebuild; it must survive.
        stripDvRpu: false,
        dependencies: const <String>{
          HdrRouteDependency.hwdecMediacodec,
          HdrRouteDependency.topologyPlatformView,
          HdrRouteDependency.dataspacePq,
        },
      ),
    );
  }

  /// `gpu-next` Texture output tone-mapped to BT.709/BT.1886. Profile 5
  /// keeps its RPU (the rescale pipeline applies it) and therefore requires
  /// the pipeline; the other profiles follow the existing stripping rules
  /// (only 8.4 was ever stripped on a non-dovi route).
  static HdrStrategyRealization _toneMapSdr(
    HdrSourceDescriptor source,
    HdrSourceClass cls,
    HdrCapabilities capabilities,
  ) {
    if (cls == HdrSourceClass.dvP5 && !capabilities.p5PipelineAvailable) {
      return const HdrStrategyRealization.infeasible(
          HdrDegradeReason.p5PipelineUnavailable);
    }
    final bool useMediacodecCopy = _requiresMediacodecCopy(capabilities);
    return HdrStrategyRealization.route(
      HdrRoute(
        strategy: HdrStrategy.toneMapSdr,
        presentation: HdrPresentation.toneMappedSdr,
        outputTransfer: HdrOutputTransfer.sdr,
        appliesDynamicMetadata: cls == HdrSourceClass.dvP5,
        topology: HdrTopology.texture,
        vo: 'gpu-next',
        hwdec: useMediacodecCopy ? 'mediacodec-copy' : 'mediacodec',
        targetPrim: 'bt.709',
        targetTrc: 'bt.1886',
        surfaceTransfer: null,
        stripDvRpu: cls == HdrSourceClass.dvP84,
        dependencies: <String>{
          useMediacodecCopy
              ? HdrRouteDependency.hwdecMediacodecCopy
              : HdrRouteDependency.hwdecMediacodec,
        },
      ),
    );
  }

  /// `gpu-next` Texture output of a SDR base layer at its decoder-reported
  /// tags. Only sources whose base layer actually is SDR may take it
  /// (plain SDR, and profile 8.2 with its RPU stripped); an HDR base layer
  /// presented as "SDR direct" is not a realizable route.
  static HdrStrategyRealization _sdrDirect(
    HdrSourceDescriptor source,
    HdrSourceClass cls,
    HdrCapabilities capabilities,
  ) {
    if (cls != HdrSourceClass.sdr && cls != HdrSourceClass.dvP82) {
      return const HdrStrategyRealization.infeasible(
          HdrDegradeReason.unsupportedStrategy);
    }
    final bool useMediacodecCopy = _requiresMediacodecCopy(capabilities);
    return HdrStrategyRealization.route(
      HdrRoute(
        strategy: HdrStrategy.sdrDirect,
        presentation: HdrPresentation.sdr,
        outputTransfer: HdrOutputTransfer.sdr,
        appliesDynamicMetadata: false,
        topology: HdrTopology.texture,
        vo: 'gpu-next',
        hwdec: useMediacodecCopy ? 'mediacodec-copy' : 'mediacodec',
        targetPrim: null,
        targetTrc: null,
        surfaceTransfer: null,
        // P8.2 strips its RPU; plain SDR carries none.
        stripDvRpu: source.dynamicMetadata == HdrDynamicMetadata.dolbyVision,
        dependencies: <String>{
          useMediacodecCopy
              ? HdrRouteDependency.hwdecMediacodecCopy
              : HdrRouteDependency.hwdecMediacodec,
        },
      ),
    );
  }

  /// Base-layer transfer function per source class; classes that do not pin
  /// one (HDR Vivid, HDR10+, SDR families) follow the reported gamma.
  static HdrOutputTransfer _baseLayerTransfer(
    HdrSourceDescriptor source,
    HdrSourceClass cls,
  ) {
    switch (cls) {
      case HdrSourceClass.hdr10:
      case HdrSourceClass.dvP81:
      case HdrSourceClass.dvP7:
        return HdrOutputTransfer.pq;
      case HdrSourceClass.hlg:
      case HdrSourceClass.dvP84:
        return HdrOutputTransfer.hlg;
      case HdrSourceClass.dvP82:
        return HdrOutputTransfer.sdr;
      case HdrSourceClass.hdrVivid:
      case HdrSourceClass.hdr10Plus:
      case HdrSourceClass.sdr:
      case HdrSourceClass.dvP5: // Unreachable: refused above.
      case HdrSourceClass.dvP10:
        if (source.transfer == 'hlg') return HdrOutputTransfer.hlg;
        if (source.transfer == 'pq') return HdrOutputTransfer.pq;
        return HdrOutputTransfer.sdr;
    }
  }

  /// HDR output feasibility on the default display. Returns null when the
  /// display supports the requested transfer type.
  static HdrDegradeReason? _displayTransferCheck(
    HdrOutputTransfer transfer,
    HdrCapabilities capabilities,
  ) {
    final Set<int>? types = capabilities.displayHdrTypes;
    if (types == null) {
      return HdrDegradeReason.noDisplayCapabilityReport;
    }
    final int? required;
    switch (transfer) {
      case HdrOutputTransfer.pq:
        required = HdrOutputPolicy.displayHdrTypeHdr10;
        break;
      case HdrOutputTransfer.hlg:
        required = HdrOutputPolicy.displayHdrTypeHlg;
        break;
      case HdrOutputTransfer.dolbyVision:
        required = 1;
        break;
      case HdrOutputTransfer.sdr:
        required = null;
        break;
    }
    if (required == null) return null;
    if (!types.contains(required)) {
      return HdrDegradeReason.displayLacksTransfer;
    }
    return null;
  }

  /// API 24/25 cannot import decoder buffers through the public GPU path used
  /// by the Texture strategies. API 26/27 can import buffers, while public
  /// HDR dataspace application is available from API 28, or earlier on a
  /// device whose registered vendor dataspace extension passed its
  /// read-only applicability gate (e.g. the API 24 LG private-slot path).
  /// Production defaults to PQ full-range. Limited is a locked LG-only
  /// experiment, not a claim about verified color or panel presentation.
  static const String _convertPqSurfaceTransfer = String.fromEnvironment(
      'MEDIA_KIT_ANDROID_CONVERT_SURFACE_TRANSFER',
      defaultValue: 'pq');
  static const bool _convertRouteLock =
      bool.fromEnvironment('MEDIA_KIT_ANDROID_HDR_CONVERT_ROUTE_LOCK');

  /// WP-C SurfaceTexture PoC (phase1-design-spec §5): a non-empty
  /// MEDIA_KIT_ANDROID_SURFACETEXTURE_POC define overrides only the
  /// baseLayerConvert route hwdec with the experimental `surfacetexture`
  /// importer. Empty (default) keeps every routed value unchanged.
  static const String _surfaceTexturePoc =
      String.fromEnvironment('MEDIA_KIT_ANDROID_SURFACETEXTURE_POC');

  /// Test seam for the official backend probe: null (default) runs the real
  /// FFI probe. Only the baseLayerConvert decision point consumes it.
  ///
  /// Visibility constraint (frozen): this seam exists for host tests only —
  /// it stays `@visibleForTesting` (compile-time enforced, no runtime gate,
  /// no build flag around it) and must never grow a production caller or a
  /// runtime toggle that could silently re-route the admission decision.
  @visibleForTesting
  static bool Function()? mkstBridgeProbeOverride;

  /// hwdec written at the baseLayerConvert decision point. Pure helper with
  /// injectable inputs for tests; production passes the official backend
  /// probe ([mkstBridgeInitialized]) and uses [_surfaceTexturePoc].
  /// All other realizer decision points never call this. The define stays
  /// authoritative: a non-empty define forces the override even when the
  /// probe is absent; the official path applies only while the bridge
  /// reports an owner-bound explicit init.
  static String surfaceTexturePocHwdec(String routedHwdec,
          {String? define, bool officialBackendReady = false}) =>
      (define ?? _surfaceTexturePoc).isNotEmpty || officialBackendReady
          ? 'surfacetexture'
          : routedHwdec;

  static bool _requiresMediacodecCopy(HdrCapabilities capabilities) =>
      capabilities.sdkInt > 0 && capabilities.sdkInt < 26;

  static bool _gpuHdrDataSpaceUnavailable(HdrCapabilities capabilities) =>
      capabilities.sdkInt > 0 &&
      capabilities.sdkInt < 28 &&
      capabilities.dataSpaceExt?.applicable != true;
}
