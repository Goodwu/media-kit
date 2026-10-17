import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// W1 PQ presentation-channel capability model (plan
/// lg-p84-yuv-window-reopen-20261014 §2 W1/W2): the three-source resolution
/// on [HdrCapabilities], the C2 RGB-window necessity gate, and the C4
/// carrier derivation — yuv-only declares the `surfacetexture` carrier, an
/// RGB channel (alone or alongside YUV) keeps the platform baseline
/// carrier. The SURFACETEXTURE PoC define and the mkst bridge probe were
/// removed with their build flag (W2): the carrier is a declared
/// capability, not a define or an FFI probe.
void main() {
  const HdrPqPresentation yuvOnlyChannels =
      HdrPqPresentation(rgbSurface: false, yuvWindow: true);
  const HdrPqPresentation rgbChannels =
      HdrPqPresentation(rgbSurface: true, yuvWindow: false);
  const HdrPqPresentation dualChannels =
      HdrPqPresentation(rgbSurface: true, yuvWindow: true);

  const HdrSourceDescriptor p84 = HdrSourceDescriptor(
    codec: 'hevc',
    transfer: 'hlg',
    dynamicMetadata: HdrDynamicMetadata.dolbyVision,
    dvProfile: 8,
    dvCompatibilityId: 4,
    enhancementLayer: false,
  );

  HdrCapabilities capsWithChannels(
    HdrPqPresentation? channels, {
    int sdkInt = 24,
    bool applicable = true,
    Set<int> types = const {2},
  }) =>
      HdrCapabilities(
        sdkInt: sdkInt,
        displayHdrTypes: types,
        hevcDecoders: const [],
        dolbyVisionDecoders: const [],
        p5PipelineAvailable: true,
        dataSpaceBridgeLoaded: true,
        dataSpaceExt: HdrDataSpaceExtInfo(
          id: 'lg-pq',
          applicable: applicable,
          pqPresentation: channels,
        ),
      );

  /// The LG-class snapshot: applicable lg-pq extension declaring the YUV
  /// window as the only PQ presentation channel.
  HdrCapabilities lgYuvCaps({Set<int> types = const {2}}) =>
      capsWithChannels(yuvOnlyChannels, types: types);

  /// An applicable extension that did not report the structure (legacy
  /// adapter): resolves to the migration default, i.e. today's behavior.
  HdrCapabilities legacyApplicableCaps({int sdkInt = 24}) => HdrCapabilities(
        sdkInt: sdkInt,
        displayHdrTypes: const {2},
        hevcDecoders: const [],
        dolbyVisionDecoders: const [],
        p5PipelineAvailable: true,
        dataSpaceBridgeLoaded: true,
        dataSpaceExt:
            const HdrDataSpaceExtInfo(id: 'lg-pq', applicable: true),
      );

  HdrRoute? realizeConvert(HdrCapabilities capabilities,
      {HdrSourceDescriptor source = const HdrSourceDescriptor(transfer: 'hlg')}) {
    return HdrStrategyRealizer.realize(
      HdrStrategy.baseLayerConvert,
      source: source,
      sourceClass: HdrSourceClass.hlg,
      capabilities: capabilities,
    ).route;
  }

  HdrStrategyRealization realizeReshape(HdrCapabilities capabilities) {
    return HdrStrategyRealizer.realize(
      HdrStrategy.metadataReshape,
      source: p84,
      sourceClass: HdrSourceClass.dvP84,
      capabilities: capabilities,
    );
  }

  group('capability resolution', () {
    test('a vendor report wins over every default', () {
      // API 29 with an adapter declaring rgbSurface=false is yuv-only all
      // the same: the self-report beats the platform default.
      final caps = capsWithChannels(yuvOnlyChannels, sdkInt: 29);
      expect(caps.pqPresentation.rgbSurface, isFalse);
      expect(caps.pqPresentation.yuvWindow, isTrue);
    });

    test('an applicable-but-silent extension takes the migration default',
        () {
      // Bit-identical to pre-W1 behavior: RGB window present, no YUV
      // window, independent of the API level.
      for (final sdkInt in [24, 29]) {
        final caps = legacyApplicableCaps(sdkInt: sdkInt);
        expect(caps.pqPresentation.rgbSurface, isTrue,
            reason: 'sdkInt $sdkInt');
        expect(caps.pqPresentation.yuvWindow, isFalse,
            reason: 'sdkInt $sdkInt');
      }
    });

    test('without a report the platform default applies by API level', () {
      HdrCapabilities noExt({int sdkInt = 29}) => HdrCapabilities(
            sdkInt: sdkInt,
            displayHdrTypes: const {2},
            hevcDecoders: const [],
            dolbyVisionDecoders: const [],
            p5PipelineAvailable: true,
            dataSpaceBridgeLoaded: true,
            dataSpaceExt: null,
          );
      // Public dataspace framework fact: RGB window from API 28.
      expect(noExt(sdkInt: 28).pqPresentation.rgbSurface, isTrue);
      expect(noExt(sdkInt: 28).pqPresentation.yuvWindow, isFalse);
      expect(noExt(sdkInt: 29).pqPresentation.rgbSurface, isTrue);
      // Below API 28 without an applicable extension: neither channel.
      expect(noExt(sdkInt: 27).pqPresentation.rgbSurface, isFalse);
      expect(noExt(sdkInt: 27).pqPresentation.yuvWindow, isFalse);
      // A registered but not-applicable extension is no report either.
      final notApplicable =
          capsWithChannels(null, sdkInt: 27, applicable: false);
      expect(notApplicable.pqPresentation.rgbSurface, isFalse);
      expect(notApplicable.pqPresentation.yuvWindow, isFalse);
    });

    test('a malformed structure report parses as absent', () {
      final HdrDataSpaceExtInfo? partial = HdrDataSpaceExtInfo.fromMap(
        const <String, Object?>{
          'id': 'lg-pq',
          'isApplicable': true,
          'pqPresentation': <String, Object?>{'rgbSurface': true},
        },
      );
      expect(partial!.pqPresentation, isNull);
      final HdrDataSpaceExtInfo? nonMap = HdrDataSpaceExtInfo.fromMap(
        const <String, Object?>{
          'id': 'lg-pq',
          'isApplicable': true,
          'pqPresentation': 'yes',
        },
      );
      expect(nonMap!.pqPresentation, isNull);
    });

    test('snapshot parsing is backward compatible', () {
      // Legacy report (no pqPresentation): applicable, structure absent,
      // resolution falls to the migration default.
      final legacy = HdrCapabilities.parseSnapshot(
        const <Object?, Object?>{
          'sdkInt': 24,
          'dataSpaceExt': <String, Object?>{
            'id': 'lg-pq',
            'isApplicable': true,
          },
        },
      );
      expect(legacy.dataSpaceExt!.pqPresentation, isNull);
      expect(legacy.pqPresentation.rgbSurface, isTrue);
      expect(legacy.pqPresentation.yuvWindow, isFalse);

      // New report: the declared channels parse through.
      final declared = HdrCapabilities.parseSnapshot(
        const <Object?, Object?>{
          'sdkInt': 24,
          'dataSpaceExt': <String, Object?>{
            'id': 'lg-pq',
            'isApplicable': true,
            'pqPresentation': <String, Object?>{
              'rgbSurface': false,
              'yuvWindow': true,
            },
          },
        },
      );
      expect(declared.dataSpaceExt!.pqPresentation!.rgbSurface, isFalse);
      expect(declared.dataSpaceExt!.pqPresentation!.yuvWindow, isTrue);
      expect(declared.pqPresentation.rgbSurface, isFalse);
      expect(declared.pqPresentation.yuvWindow, isTrue);
    });
  });

  group('C2 reshape admission', () {
    test('a device without the RGB window refuses the reshape with the '
        'presentation reason', () {
      final HdrStrategyRealization refused = realizeReshape(lgYuvCaps());
      expect(refused.route, isNull);
      expect(
          refused.infeasibleReason, HdrDegradeReason.pqRgbPresentationUnavailable);
    });

    test('a device with the RGB window keeps the reshape feasible', () {
      // Migration default (legacy applicable adapter) and an explicit RGB
      // report both keep today's C2 shape.
      for (final caps in [legacyApplicableCaps(), capsWithChannels(rgbChannels)]) {
        final HdrStrategyRealization realized = realizeReshape(caps);
        expect(realized.route, isNotNull);
        expect(realized.route!.hwdec, 'mediacodec');
        expect(realized.route!.vo, 'gpu-next');
        expect(realized.route!.outputTransfer, HdrOutputTransfer.pq);
      }
    });
  });

  group('C4 carrier derivation', () {
    test('a yuv-only declaration routes the surfacetexture carrier with '
        'the YUV contract', () {
      final route = realizeConvert(lgYuvCaps())!;
      expect(route.hwdec, 'surfacetexture');
      expect(route.surfaceTransfer, 'pq');
      expect(route.offscreenTransfer, 'pq-full',
          reason: 'the YUV carrier presents the actual YUV shape; the '
              'offscreen contract is required for the pq request too');
      expect(route.dependencies,
          contains(HdrRouteDependency.hwdecSurfaceTexture));
    });

    test('an RGB declaration keeps the platform baseline carrier', () {
      // API < 26 baseline: mediacodec-copy; the RGB window route keeps a
      // single surface contract.
      final copyRoute = realizeConvert(capsWithChannels(rgbChannels))!;
      expect(copyRoute.hwdec, 'mediacodec-copy');
      expect(copyRoute.surfaceTransfer, 'pq');
      expect(copyRoute.offscreenTransfer, isNull,
          reason: 'RGB window routes keep a single contract');
      expect(copyRoute.dependencies,
          contains(HdrRouteDependency.hwdecMediacodecCopy));
      expect(copyRoute.dependencies,
          isNot(contains(HdrRouteDependency.hwdecSurfaceTexture)));
      // API >= 26 baseline: mediacodec.
      expect(
          realizeConvert(capsWithChannels(rgbChannels, sdkInt: 29))!.hwdec,
          'mediacodec');
      // The migration-default shape (legacy applicable adapter) is the same
      // RGB baseline, bit-identical to pre-W1 behavior.
      expect(realizeConvert(legacyApplicableCaps())!.hwdec, 'mediacodec-copy');
      expect(realizeConvert(legacyApplicableCaps(sdkInt: 29))!.hwdec,
          'mediacodec');
    });

    test('a dual-channel declaration prefers the RGB baseline', () {
      expect(realizeConvert(capsWithChannels(dualChannels))!.hwdec,
          'mediacodec-copy');
      expect(
          realizeConvert(capsWithChannels(dualChannels, sdkInt: 29))!.hwdec,
          'mediacodec');
      final route = realizeConvert(capsWithChannels(dualChannels))!;
      expect(route.offscreenTransfer, isNull);
    });

    test('the carrier rides the existing admission gates', () {
      // A yuv-only declaration must not reopen a route the earlier gates
      // refuse: the extension is not applicable, so the convert route is
      // refused before any carrier decision.
      final HdrStrategyRealization refused = HdrStrategyRealizer.realize(
        HdrStrategy.baseLayerConvert,
        source: const HdrSourceDescriptor(transfer: 'hlg'),
        sourceClass: HdrSourceClass.hlg,
        capabilities:
            capsWithChannels(yuvOnlyChannels, applicable: false),
      );
      expect(refused.route, isNull);
    });

    test('other strategy routes never take the YUV carrier', () {
      // HLG-capable display so the direct route itself is admissible; the
      // carrier model must not leak beyond the conversion decision point.
      final direct = HdrStrategyRealizer.realize(
        HdrStrategy.baseLayerDirect,
        source: const HdrSourceDescriptor(transfer: 'hlg'),
        sourceClass: HdrSourceClass.hlg,
        capabilities: lgYuvCaps(types: const {2, 3}),
      );
      expect(direct.route!.hwdec, 'mediacodec');
      expect(direct.route!.vo, 'mediacodec_embed');
      expect(direct.route!.offscreenTransfer, isNull);
    });
  });

  group('A4 contract split by carrier', () {
    final policy = HdrRoutingPolicy(
      preferences: const {
        HdrSourceClass.hlg: [HdrStrategy.baseLayerConvert],
      },
    );
    const source = HdrSourceDescriptor(transfer: 'hlg');

    test('a failed copy execution cannot exclude the YUV carrier', () {
      final excludedCopy = HdrRoutePlanner.plan(
        source: source,
        capabilities: lgYuvCaps(),
        policy: policy,
        excluded: const {
          HdrRouteDependency.hwdecMediacodecCopy:
              HdrDegradeReason.hwdecMismatch,
        },
      );
      expect(excludedCopy.selected.strategy, HdrStrategy.baseLayerConvert,
          reason: 'the YUV carrier execution is independent of copy mode');
      expect(excludedCopy.selected.route!.hwdec, 'surfacetexture');
    });

    test('a failed YUV carrier execution blocks without a copy takeover',
        () {
      final excludedYuv = HdrRoutePlanner.plan(
        source: source,
        capabilities: lgYuvCaps(),
        policy: policy,
        excluded: const {
          HdrRouteDependency.hwdecSurfaceTexture:
              HdrDegradeReason.hwdecMismatch,
        },
      );
      // The yuv-only device has no alternate HDR carrier, and this
      // HDR-capable display does not authorize a synthesized SDR takeover
      // (MK-ROUTING-20261011): the failed execution is the recorded
      // blocking reason.
      expect(excludedYuv.playable, isFalse);
      expect(excludedYuv.selected.strategy, HdrStrategy.baseLayerConvert,
          reason: 'a failed YUV carrier execution must not be selected again');
      expect(excludedYuv.selected.route, isNull);
      expect(excludedYuv.selected.skipReason, HdrDegradeReason.hwdecMismatch);
      expect(
        excludedYuv.candidates
            .firstWhere((HdrCandidate c) =>
                c.strategy == HdrStrategy.baseLayerConvert)
            .skipReason,
        HdrDegradeReason.hwdecMismatch,
      );
    });

    test('the RGB baseline carrier keeps its own execution dependency', () {
      // Migration-default shape: the copy carrier carries the copy
      // dependency and no SurfaceTexture dependency.
      final route = realizeConvert(legacyApplicableCaps())!;
      expect(route.hwdec, 'mediacodec-copy');
      expect(route.dependencies,
          contains(HdrRouteDependency.hwdecMediacodecCopy));
      expect(route.dependencies,
          isNot(contains(HdrRouteDependency.hwdecSurfaceTexture)));
    });
  });
}
