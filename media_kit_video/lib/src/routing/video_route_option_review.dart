import '../hdr/hdr_capabilities.dart';
import '../hdr/hdr_open_plan.dart';
import '../hdr/hdr_route.dart';
import '../hdr/hdr_strategy.dart';
import 'video_decoder_support.dart';
import 'video_route_options.dart';

enum VideoRouteOptionStatus { notRequested, fulfilled, unfulfilled, unknown }

/// Current configured-route evidence, never proof of visible pixels or HDR.
class VideoRouteOptionFulfillment {
  const VideoRouteOptionFulfillment(
      {required this.decode,
      required this.output,
      required this.importPreference});
  final VideoRouteOptionStatus decode;
  final VideoRouteOptionStatus output;
  final VideoRouteOptionStatus importPreference;
  Map<String, String> toMap() => Map.unmodifiable({
        'decode': decode.name,
        'output': output.name,
        'importPreference': importPreference.name,
      });
}

bool _hardwareRequest(HdrRoute route) => const {
      'mediacodec',
      'mediacodec-copy',
      'surfacetexture'
    }.contains(route.hwdec);

bool _hdr(HdrRoute route) => route.outputTransfer != HdrOutputTransfer.sdr;

/// Capability eligibility only. Unknown actual hardware must still be reviewed.
bool videoRouteMeetsRequirements(HdrRoute route, HdrCapabilities capabilities,
    EffectiveVideoRouteOptions options) {
  if (options.output.isRequired &&
      _hdr(route) != (options.output.target == VideoOutputIntent.hdr)) {
    return false;
  }
  if (options.decode.isRequired) {
    if (options.decode.target == VideoDecodeTarget.software) {
      return route.hwdec == 'no';
    }
    if (!_hardwareRequest(route)) {
      return false;
    }
    if (capabilities.sourceSupport?.support(
            kind: VideoDecoderKind.hardware,
            path: route.strategy == HdrStrategy.nativeDolbyVision
                ? 'nativeDv'
                : 'codec') ==
        VideoSupport.unsupported) {
      return false;
    }
  }
  return true;
}

/// Stable ordering of existing candidates; preferences never authorize one.
List<HdrCandidate> applyVideoRouteOptions(List<HdrCandidate> input,
    HdrCapabilities capabilities, EffectiveVideoRouteOptions options) {
  final candidates = [
    for (final candidate in input)
      if (candidate.feasible &&
          !videoRouteMeetsRequirements(candidate.route!, capabilities, options))
        HdrCandidate(
            strategy: candidate.strategy,
            maturity: candidate.maturity,
            isSafetyNet: candidate.isSafetyNet,
            sourceClass: candidate.sourceClass,
            stage: candidate.stage,
            executionId: candidate.executionId,
            skipReason: HdrDegradeReason.routeOptionsUnsatisfied)
      else
        candidate
  ];
  int score(HdrCandidate candidate) {
    final route = candidate.route;
    if (!candidate.feasible || route == null) return 100;
    final output = options.output.preference == VideoRoutePreference.prefer &&
            _hdr(route) != (options.output.target == VideoOutputIntent.hdr)
        ? 8
        : 0;
    final decode = options.decode.preference == VideoRoutePreference.prefer &&
            _hardwareRequest(route) !=
                (options.decode.target == VideoDecodeTarget.hardware)
        ? 4
        : 0;
    return output + decode;
  }

  int importer(HdrCandidate candidate) =>
      options.importPreference == VideoImportPreference.auto
          ? 0
          : options.importPreference == VideoImportPreference.preferCopy
              ? (candidate.route?.hwdec == 'mediacodec-copy' ? 0 : 1)
              : (candidate.route?.hwdec == 'mediacodec' ||
                      candidate.route?.hwdec == 'surfacetexture'
                  ? 0
                  : 1);
  final groups = <HdrRoute, int>{};
  int group(HdrCandidate candidate, int index) {
    final route = candidate.route;
    if (route == null) return index;
    return groups.putIfAbsent(
        route.withExecution(hwdec: '', dependencies: {}), () => index);
  }

  for (var index = 0; index < candidates.length; index++) {
    group(candidates[index], index);
  }
  final indexed = [
    for (var index = 0; index < candidates.length; index++)
      MapEntry(index, candidates[index])
  ];
  indexed.sort((a, b) {
    // A caller's prefer setting can only reorder implementations inside one
    // C1–C4 stage. Never let it promote a fallback baseline above mapping.
    final stageOrder = (a.value.stage?.index ?? 4)
        .compareTo(b.value.stage?.index ?? 4);
    if (stageOrder != 0) return stageOrder;
    final order = score(a.value).compareTo(score(b.value));
    if (order != 0) return order;
    final contractOrder =
        group(a.value, a.key).compareTo(group(b.value, b.key));
    if (contractOrder != 0) return contractOrder;
    final importOrder = importer(a.value).compareTo(importer(b.value));
    return importOrder == 0 ? a.key.compareTo(b.key) : importOrder;
  });
  // Even without a preference the stage order is canonical. Unstaged ad-hoc
  // callers retain their original order through the stable index tie-breaker.
  return [for (final entry in indexed) entry.value];
}

// Same codec families as the existing Android source adapter. This identifies
// the encoded family only, never profile support or color-processing safety.
String? _sourceMime(String codec) => const {
      'hevc': 'video/hevc',
      'h265': 'video/hevc',
      'hvc1': 'video/hevc',
      'hev1': 'video/hevc',
      'dvhe': 'video/hevc',
      'dvh1': 'video/hevc',
      'h264': 'video/avc',
      'avc': 'video/avc',
      'avc1': 'video/avc',
      'avc3': 'video/avc',
      'vp9': 'video/x-vnd.on2.vp9',
      'vp09': 'video/x-vnd.on2.vp9',
      'av1': 'video/av01',
      'av01': 'video/av01',
    }[codec.split('.').first];

/// Exact MediaCodec identity and eligible kind for this frozen source census.
/// Wrapper names (e.g. hevc_mediacodec) never stand in for getName().
bool _observedHardware(HdrOpenPlan plan, HdrReviewFacts facts) {
  final native = plan.route.strategy == HdrStrategy.nativeDolbyVision;
  final observation = facts.decoderObservation;
  final config = native
      ? facts.nativeDvEvidence?.configuration
      : observation?.mediaCodecConfiguration;
  final support = plan.capabilities.sourceSupport;
  if (config == null ||
      config.codec.isEmpty ||
      support == null ||
      plan.sourceSpec == null ||
      support.source != plan.sourceSpec ||
      facts.path != plan.media.uri ||
      facts.hwdecCurrent != plan.route.hwdec ||
      !_hardwareRequest(plan.route) ||
      _sourceMime(plan.sourceSpec!.codec) == null ||
      _sourceMime(plan.sourceSpec!.codec) != _sourceMime(facts.codec)) {
    return false;
  }
  if (native) {
    if (!config.nativeDvActive ||
        config.mime != 'video/dolby-vision' ||
        facts.nativeDvEvidence!.source.path != plan.media.uri) {
      return false;
    }
  } else {
    const mimes = {
      'hevc': 'video/hevc',
      'h265': 'video/hevc',
      'h264': 'video/avc',
      'avc': 'video/avc',
      'vp9': 'video/x-vnd.on2.vp9',
      'av1': 'video/av01'
    };
    if (config.nativeDvActive || mimes[facts.codec] != config.mime) {
      return false;
    }
  }
  final rows = support.decoders
      .where((row) =>
          row.name == config.codec &&
          row.mime == config.mime &&
          row.path == (native ? 'nativeDv' : 'codec'))
      .toList();
  return rows.isNotEmpty &&
      rows.every((row) =>
          row.kind == VideoDecoderKind.hardware &&
          row.support == VideoSupport.supported);
}

VideoRouteOptionFulfillment reviewVideoRouteOptions(HdrOpenPlan plan,
    HdrReviewFacts facts, EffectiveVideoRouteOptions options) {
  final hardware = _observedHardware(plan, facts);
  final software = plan.route.hwdec == 'no' &&
      facts.hwdecCurrent == 'no' &&
      facts.decoderObservation?.mediaCodecConfiguration == null &&
      facts.nativeDvEvidence == null &&
      facts.decoderObservation?.softwareDecoded == true &&
      facts.decoderObservation?.cpuFrame == true &&
      facts.path == plan.media.uri;
  VideoRouteOptionStatus decode;
  if (options.decode.target == null) {
    decode = VideoRouteOptionStatus.notRequested;
  } else if (options.decode.target == VideoDecodeTarget.hardware && hardware ||
      options.decode.target == VideoDecodeTarget.software && software) {
    decode = VideoRouteOptionStatus.fulfilled;
  } else {
    decode = hardware || software
        ? VideoRouteOptionStatus.unfulfilled
        : VideoRouteOptionStatus.unknown;
  }
  final output = options.output.target == null
      ? VideoRouteOptionStatus.notRequested
      : _hdr(plan.route) == (options.output.target == VideoOutputIntent.hdr)
          ? VideoRouteOptionStatus.fulfilled
          : VideoRouteOptionStatus.unfulfilled;
  final importer = options.importPreference == VideoImportPreference.auto
      ? VideoRouteOptionStatus.notRequested
      : (options.importPreference == VideoImportPreference.preferCopy
              ? facts.hwdecCurrent == 'mediacodec-copy' &&
                  facts.decoderObservation?.cpuFrame == true
              : facts.hwdecCurrent == 'mediacodec' ||
                  facts.hwdecCurrent == 'surfacetexture')
          ? VideoRouteOptionStatus.fulfilled
          : VideoRouteOptionStatus.unfulfilled;
  final result = VideoRouteOptionFulfillment(
      decode: decode, output: output, importPreference: importer);
  return result;
}

void validateVideoRouteOptionFulfillment(
    EffectiveVideoRouteOptions options, VideoRouteOptionFulfillment result) {
  if (options.decode.isRequired &&
          result.decode != VideoRouteOptionStatus.fulfilled ||
      options.output.isRequired &&
          result.output != VideoRouteOptionStatus.fulfilled) {
    throw const HdrPlaybackBlocked(HdrDegradeReason.routeOptionsUnsatisfied);
  }
}
