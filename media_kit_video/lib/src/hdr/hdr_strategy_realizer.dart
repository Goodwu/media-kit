/// This file is a part of media_kit (https://github.com/media-kit/media-kit).
///
/// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
/// All rights reserved.
/// Use of this source code is governed by MIT license that can be found in the LICENSE file.
import 'hdr_capabilities.dart';
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
    // Guard the direct realizer API too: a caller-supplied coarse class must
    // not override the descriptor's unresolved DV semantics.
    if (source.hasUnresolvedDolbyVision ||
        sourceClass == HdrSourceClass.dvUnknown) {
      return const HdrStrategyRealization.infeasible(
        HdrDegradeReason.sourceMetadataUnknown,
      );
    }
    switch (strategy) {
      case HdrStrategy.nativeDolbyVision:
        return _nativeDolbyVision(source, sourceClass, capabilities);
      case HdrStrategy.nativeHdr10Plus:
        return HdrStrategyRealization.infeasible(
            sourceClass == HdrSourceClass.hdr10Plus &&
                    source.dynamicMetadata == HdrDynamicMetadata.hdr10Plus
                ? HdrDegradeReason.routeNotImplemented
                : HdrDegradeReason.unsupportedStrategy);
      case HdrStrategy.nativeHdrVivid:
        return HdrStrategyRealization.infeasible(
            sourceClass == HdrSourceClass.hdrVivid &&
                    source.dynamicMetadata == HdrDynamicMetadata.hdrVivid
                ? HdrDegradeReason.routeNotImplemented
                : HdrDegradeReason.unsupportedStrategy);
      case HdrStrategy.baseLayerDirect:
        return _withOrdinaryDecoderDependency(
            _baseLayerDirect(source, sourceClass, capabilities));
      case HdrStrategy.baseLayerConvert:
        return _withOrdinaryDecoderDependency(
            _baseLayerConvert(source, sourceClass, capabilities));
      case HdrStrategy.metadataReshape:
        return _withOrdinaryDecoderDependency(
            _metadataReshape(source, sourceClass, capabilities));
      case HdrStrategy.toneMapSdr:
        return _withOrdinaryDecoderDependency(
            _toneMapSdr(source, sourceClass, capabilities));
      case HdrStrategy.sdrDirect:
        return _withOrdinaryDecoderDependency(
            _sdrDirect(source, sourceClass, capabilities));
    }
  }

  /// Compute the immutable *request* before realizing the route. Neither this
  /// value nor appliesDynamicMetadata is a runtime observation.
  static HdrMetadataHandling metadataHandlingFor(
      HdrSourceDescriptor source, HdrStrategy strategy) {
    if (source.dynamicMetadata == HdrDynamicMetadata.none) {
      return HdrMetadataHandling.none;
    }
    switch (strategy) {
      case HdrStrategy.nativeDolbyVision:
      case HdrStrategy.nativeHdr10Plus:
      case HdrStrategy.nativeHdrVivid:
        return HdrMetadataHandling.preserveForNative;
      case HdrStrategy.metadataReshape:
        return HdrMetadataHandling.consumeForMapping;
      case HdrStrategy.toneMapSdr:
        return source.dvProfile == 5 &&
                source.dynamicMetadata == HdrDynamicMetadata.dolbyVision
            ? HdrMetadataHandling.consumeForMapping
            : HdrMetadataHandling.baselineOnly;
      case HdrStrategy.baseLayerDirect:
      case HdrStrategy.baseLayerConvert:
      case HdrStrategy.sdrDirect:
        return HdrMetadataHandling.baselineOnly;
    }
  }

  // These mpv requests all use the ordinary MediaCodec decode implementation.
  // Native DV owns a different configured decoder contract; hwdec=no is FFmpeg.
  static HdrStrategyRealization _withOrdinaryDecoderDependency(
      HdrStrategyRealization realization) {
    final route = realization.route;
    if (route == null ||
        !const {'mediacodec', 'mediacodec-copy', 'surfacetexture'}
            .contains(route.hwdec)) {
      return realization;
    }
    return HdrStrategyRealization.route(route.withExecution(
        hwdec: route.hwdec,
        dependencies: {
          ...route.dependencies,
          HdrRouteDependency.decoderMediacodec
        }));
  }

  /// Existing SDR Texture executions, in bounded preference order. CPU
  /// candidates preserve the same tone-map/P5 pipeline/P8.4 stripping gates;
  /// they never add an HDR presenter or feed CPU frames to mediacodec_embed.
  static List<HdrStrategyRealization> realizeCandidates(
    HdrStrategy strategy, {
    required HdrSourceDescriptor source,
    required HdrSourceClass sourceClass,
    required HdrCapabilities capabilities,
  }) {
    final primary = realize(strategy,
        source: source, sourceClass: sourceClass, capabilities: capabilities);
    final route = primary.route;
    if (route == null ||
        route.vo != 'gpu-next' ||
        route.topology != HdrTopology.texture ||
        route.outputTransfer != HdrOutputTransfer.sdr ||
        (strategy != HdrStrategy.sdrDirect &&
            strategy != HdrStrategy.toneMapSdr)) {
      return [primary];
    }
    final requests = <String>[
      route.hwdec,
      if (route.hwdec != 'mediacodec-copy') 'mediacodec-copy',
      'no',
    ];
    return List<HdrStrategyRealization>.unmodifiable([
      for (final hwdec in requests)
        HdrStrategyRealization.route(
            route.withExecution(hwdec: hwdec, dependencies: {
          ...route.dependencies.where((dependency) =>
              dependency != HdrRouteDependency.hwdecMediacodec &&
              dependency != HdrRouteDependency.hwdecMediacodecCopy &&
              dependency != HdrRouteDependency.decoderMediacodec),
          HdrRouteDependency.presenterGpuTexture,
          if (hwdec == 'no')
            HdrRouteDependency.decoderSoftware
          else
            HdrRouteDependency.decoderMediacodec,
          if (hwdec == 'mediacodec') ...{
            HdrRouteDependency.hwdecMediacodec,
            HdrRouteDependency.importMediacodec,
          } else
            HdrRouteDependency.importCpuUpload,
          if (hwdec == 'mediacodec-copy')
            HdrRouteDependency.hwdecMediacodecCopy,
        })),
    ]);
  }

  /// Native single-layer Dolby Vision decode through MediaCodec and the
  /// DV bridge. The RPU stays in the elementary stream for the native
  /// decoder; the GPU P5 rescale pipeline is not used by this route.
  static HdrStrategyRealization _nativeDolbyVision(
    HdrSourceDescriptor source,
    HdrSourceClass cls,
    HdrCapabilities capabilities,
  ) {
    // Match the fork's single-layer native_dv contract for both supported
    // source classes. Unknown EL presence is not proof of a single layer.
    // FFmpeg separately validates the BL/RPU flags and initialization data.
    final bool eligibleSource = source.enhancementLayer == false &&
        ((cls == HdrSourceClass.dvP5 &&
                source.dvProfile == 5 &&
                source.dvCompatibilityId == 0) ||
            (cls == HdrSourceClass.dvP84 &&
                source.dvProfile == 8 &&
                source.dvCompatibilityId == 4));
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
    // These are Android CodecProfileLevel keys, not DV profile numbers:
    // P5 uses DvheStn (0x20); P8 uses DvheSt (0x100). Keep admission aligned
    // with FFmpeg's native_dv_android_profile_key(). A P5-only decoder is
    // not a P8 candidate, and a P8 decoder need not also advertise P5.
    final int requiredAndroidProfile = cls == HdrSourceClass.dvP5 ? 32 : 256;
    final hasDolbyVisionDecoder = capabilities.dolbyVisionDecoders.any(
      (decoder) =>
          decoder.mimeType == 'video/dolby-vision' &&
          decoder.hardwareAcceleration &&
          decoder.profiles.contains(requiredAndroidProfile),
    );
    if (!hasDolbyVisionDecoder || capabilities.nativeDvBridgeApi != 1) {
      return const HdrStrategyRealization.infeasible(
          HdrDegradeReason.nativeDvUnavailable);
    }
    // Preserve the accepted release-mode behavior. Decoder-specific mode
    // policy is independent of this source/profile admission correction.
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
        metadataHandling: metadataHandlingFor(source, HdrStrategy.nativeDolbyVision),
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
        // Dolby Vision display support does not imply support for a bare
        // HLG base layer. In particular, the LG HLG-over-DV-panel experiment
        // did not establish correct HLG HDR presentation. Conversion and
        // SDR candidates must pass their own gates instead of bypassing
        // this display-transfer requirement.
        return HdrStrategyRealization.infeasible(reason);
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
        metadataHandling: metadataHandlingFor(source, HdrStrategy.baseLayerDirect),
        dependencies: const <String>{
          HdrRouteDependency.hwdecMediacodec,
          HdrRouteDependency.topologyPlatformView,
        },
      ),
    );
  }

  /// C4: `gpu-next` conversion of an HLG compatibility base layer to PQ on
  /// a `rgb10_a2` PlatformView. An existing PQ or SDR base layer is never
  /// transformed here. DV sources strip their RPU; profile 5 is excluded.
  static HdrStrategyRealization _baseLayerConvert(
    HdrSourceDescriptor source,
    HdrSourceClass cls,
    HdrCapabilities capabilities,
  ) {
    if (cls == HdrSourceClass.dvP5 ||
        cls == HdrSourceClass.dvP10 ||
        _baseLayerTransfer(source, cls) != HdrOutputTransfer.hlg) {
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
    if (!types.contains(HdrOutputPolicy.displayHdrTypeHdr10)) {
      return const HdrStrategyRealization.infeasible(
          HdrDegradeReason.displayLacksTransfer);
    }
    const HdrOutputTransfer output = HdrOutputTransfer.pq;
    // The pq-itu experiment keeps its existing lock semantics; the
    // admission criterion is the extension's own supported-surface-transfer
    // self-report, never a device-name-derived identifier. An extension
    // that does not declare the transfer — on any id — stays refused.
    if (_convertPqSurfaceTransfer != 'pq' &&
        (_convertPqSurfaceTransfer != 'pq-itu' ||
            !_convertRouteLock ||
            capabilities.sdkInt != 24 ||
            !(capabilities.dataSpaceExt?.supportedSurfaceTransfers
                    .contains(_convertPqSurfaceTransfer) ??
                false) ||
            capabilities.dataSpaceExt?.applicable != true)) {
      return const HdrStrategyRealization.infeasible(
          HdrDegradeReason.unsupportedStrategy);
    }
    final String trc = output == HdrOutputTransfer.pq ? 'pq' : 'hlg';
    // W1 carrier derivation: the vendor-declared YUV window is the only
    // alternative carrier, and only when the RGB window channel is absent
    // (a device declaring both channels keeps the RGB baseline). A YUV-less
    // device keeps the platform baseline: API < 26 has no non-copy
    // mediacodec GPU import, so the convert route then decodes through
    // mediacodec-copy like the SDR routes.
    final HdrPqPresentation pqPresentation = capabilities.pqPresentation;
    // An explicit negative declaration is not the legacy missing-field
    // migration. Without a YUV alternative, the RGB fallback must itself
    // be available; never manufacture a carrier for the C4 prediction.
    if (!pqPresentation.rgbSurface && !pqPresentation.yuvWindow) {
      return const HdrStrategyRealization.infeasible(
          HdrDegradeReason.pqRgbPresentationUnavailable);
    }
    final bool yuvWindowCarrier =
        pqPresentation.yuvWindow && !pqPresentation.rgbSurface;
    final String hwdec = yuvWindowCarrier
        ? 'surfacetexture'
        : _requiresMediacodecCopy(capabilities)
            ? 'mediacodec-copy'
            : 'mediacodec';
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
    final String hwdecDependency;
    if (hwdec == 'surfacetexture') {
      hwdecDependency = HdrRouteDependency.hwdecSurfaceTexture;
    } else if (hwdec == 'mediacodec-copy') {
      hwdecDependency = HdrRouteDependency.hwdecMediacodecCopy;
    } else {
      hwdecDependency = HdrRouteDependency.hwdecMediacodec;
    }
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
        metadataHandling: metadataHandlingFor(source, HdrStrategy.baseLayerConvert),
        dependencies: <String>{
          hwdecDependency,
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
    if (cls == HdrSourceClass.hdrVivid ||
        cls == HdrSourceClass.hdr10Plus) {
      // The format is a valid C2 target, but full metadata mapping is not
      // implemented. Do not silently emit PQ while ignoring the metadata.
      final reason = _displayTransferCheck(HdrOutputTransfer.pq, capabilities);
      if (reason != null) return HdrStrategyRealization.infeasible(reason);
      if (_gpuHdrDataSpaceUnavailable(capabilities)) {
        return const HdrStrategyRealization.infeasible(
            HdrDegradeReason.gpuHdrDataSpaceUnavailable);
      }
      return const HdrStrategyRealization.infeasible(
          HdrDegradeReason.routeNotImplemented);
    }
    if (cls == HdrSourceClass.dvP10) {
      return const HdrStrategyRealization.infeasible(
          HdrDegradeReason.unsupportedStrategy);
    }
    final bool isDv = source.dynamicMetadata == HdrDynamicMetadata.dolbyVision;
    if (!isDv) {
      // Ordinary PQ/HLG contains no dynamic metadata to rebuild.
      return const HdrStrategyRealization.infeasible(
          HdrDegradeReason.unsupportedStrategy);
    }
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
    // W1: the reshape is structurally hard-bound to the RGB `rgb10_a2`
    // window surface. A device whose declared PQ presentation channels
    // exclude the RGB surface cannot realize it at all — a declared YUV
    // window may still carry the conversion candidate instead.
    if (!capabilities.pqPresentation.rgbSurface) {
      return const HdrStrategyRealization.infeasible(
          HdrDegradeReason.pqRgbPresentationUnavailable);
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
        metadataHandling: metadataHandlingFor(source, HdrStrategy.metadataReshape),
        dependencies: const <String>{
          HdrRouteDependency.hwdecMediacodec,
          HdrRouteDependency.topologyPlatformView,
          HdrRouteDependency.dataspacePq,
          HdrRouteDependency.mapperDolbyVision,
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
        metadataHandling: metadataHandlingFor(source, HdrStrategy.toneMapSdr),
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
        metadataHandling: metadataHandlingFor(source, HdrStrategy.sdrDirect),
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
      case HdrSourceClass.dvUnknown: // unreachable after the source-fact guard
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

  static bool _requiresMediacodecCopy(HdrCapabilities capabilities) =>
      capabilities.sdkInt > 0 && capabilities.sdkInt < 26;

  static bool _gpuHdrDataSpaceUnavailable(HdrCapabilities capabilities) =>
      capabilities.sdkInt > 0 &&
      capabilities.sdkInt < 28 &&
      capabilities.dataSpaceExt?.applicable != true;
}
