// ignore_for_file: implementation_imports
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:media_kit_video/media_kit_video.dart';

/// Lab-only contract for the WP-C SurfaceTexture PoC
/// (phase1-design-spec §5, plan §7: an independent experiment class; the
/// legacy copy validator is never relaxed). Same frozen output contract and
/// source-class whitelist as [AndroidHdrConvertExperiment], but the realized
/// baseLayerConvert route must carry the experimental `surfacetexture`
/// importer (the production realizer overrides the route hwdec when
/// MEDIA_KIT_ANDROID_SURFACETEXTURE_POC is non-empty). Rejects before
/// Session can prepare/open any other route, including the planner's SDR
/// safety net and dependency-failure retries: there is no fallback path.
class AndroidSurfaceTextureExperiment {
  const AndroidSurfaceTextureExperiment(this.surfaceTransfer, this.outputLevels);

  final String surfaceTransfer;
  final String outputLevels;

  void validateAdmission({required bool dataSpacePerformProbe}) {
    validate();
    if (dataSpacePerformProbe) {
      throw StateError(
          'SurfaceTexture route lock excludes DATASPACE_PERFORM_PROBE');
    }
  }

  void validate() {
    if (!((surfaceTransfer == 'pq' && outputLevels == 'full') ||
        (surfaceTransfer == 'pq-itu' && outputLevels == 'limited'))) {
      throw StateError(
          'SurfaceTexture experiment requires pq/full or pq-itu/limited');
    }
  }

  Future<void> prepareOutputLevels({
    required Future<void> Function(String) set,
    required Future<String> Function() read,
  }) async {
    validate();
    await set(outputLevels);
    final actual = await read();
    if (actual != outputLevels) {
      throw StateError('Output levels not accepted: $actual');
    }
  }

  HdrRoutePrediction plan({
    required HdrSourceDescriptor source,
    required HdrCapabilities capabilities,
    required HdrRoutingPolicy policy,
    required HdrOutputPreference preference,
    required Map<String, HdrDegradeReason> excluded,
  }) {
    validate();
    final cls = HdrSourceClass.of(source);
    debugPrint('MKSURF-POC: plan entry cls=$cls codec=${source.codec} '
        'transfer=${source.transfer} meta=${source.dynamicMetadata}');
    if (cls != HdrSourceClass.hlg &&
        cls != HdrSourceClass.dvP84 &&
        cls != HdrSourceClass.hdr10) {
      debugPrint('MKSURF-POC: plan whitelist rejected cls=$cls');
      throw const HdrPlaybackBlocked(HdrDegradeReason.unsupportedStrategy);
    }
    final prediction = HdrRoutePlanner.plan(
      source: source,
      capabilities: capabilities,
      policy: HdrRoutingPolicy(
        preferences: {
          HdrSourceClass.of(source): const [HdrStrategy.baseLayerConvert],
        },
        // This experiment class is a diagnostic tool explicitly opted in by
        // the double define pair (MEDIA_KIT_ANDROID_SURFACETEXTURE_DIAG +
        // _POC); hlg x baseLayerConvert is `experimental` in the production
        // maturity table and the diagnostic round deliberately exercises that
        // route. The production maturity table and the default (define-off)
        // behavior are unchanged: this gate only opens inside this lab
        // validator's own planner call, and the source-class whitelist above
        // still bounds what can reach it.
        allowExperimental: true,
      ),
      preference: preference,
      excluded: excluded,
    );
    final route = prediction.selected.route;
    if (!prediction.playable ||
        route == null ||
        route.strategy != HdrStrategy.baseLayerConvert ||
        route.outputTransfer != HdrOutputTransfer.pq ||
        route.targetTrc != 'pq' ||
        route.surfaceTransfer != surfaceTransfer ||
        route.topology != HdrTopology.platformView ||
        route.vo != 'gpu-next' ||
        // The one deliberate difference from the legacy copy validator: the
        // PoC route must carry the experimental importer, never a copy or
        // SDR route.
        route.hwdec != 'surfacetexture') {
      // Diagnostic visibility: the generic blocked reason hides the
      // planner's actual skip reason; log it before failing closed.
      debugPrint(
          'MKSURF-POC: plan rejected playable=${prediction.playable} '
          'skip=${prediction.selected.skipReason} '
          'route=${prediction.selected.route}');
      throw const HdrPlaybackBlocked(HdrDegradeReason.unsupportedStrategy);
    }
    return prediction;
  }
}
