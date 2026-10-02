import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart'
    show FileLoadedRecord, Media, VideoParams;
import 'package:media_kit_video/src/hdr/hdr_capabilities.dart';
import 'package:media_kit_video/src/hdr/hdr_open_coordinator.dart';
import 'package:media_kit_video/src/hdr/hdr_player_backend.dart';
import 'package:media_kit_video/src/hdr/hdr_open_plan.dart';
import 'package:media_kit_video/src/hdr/hdr_output_event.dart';
import 'package:media_kit_video/src/hdr/hdr_route.dart';
import 'package:media_kit_video/src/hdr/hdr_source_descriptor.dart';
import 'package:media_kit_video/src/hdr/hdr_strategy.dart';
import 'package:media_kit_video/src/hdr/hdr_video_session.dart';

/// A1-P8.4 review-timing fix: `AndroidHdrBackend.gatherReviewFacts` waits,
/// within the review budget, for video-params to report the base-layer tags
/// before handing the facts to the session's review (plan 1.4 step 8 reads
/// BOTH `dolby-vision-profile` and video-params). Without the wait, a review
/// executed while video-params were still unreported classified an integer
/// profile 8 conservatively as an SDR-base-layer DV (8.2) and burned the
/// single rebuild on a tone-map route.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const p84 = HdrSourceDescriptor(
    codec: 'hevc',
    transfer: 'hlg',
    primaries: 'bt.2020',
    dynamicMetadata: HdrDynamicMetadata.dolbyVision,
    dvProfile: 8,
    dvCompatibilityId: 4,
    enhancementLayer: false,
  );

  HdrCapabilities caps() => const HdrCapabilities(
        sdkInt: 29,
        displayHdrTypes: {1, 2, 3},
        hevcDecoders: [],
        dolbyVisionDecoders: [],
        p5PipelineAvailable: true,
        dataSpaceBridgeLoaded: true,
        dataSpaceExt: HdrDataSpaceExtInfo(id: 'lya-pq', applicable: true),
      );

  /// The first read reports no video-params yet; from the second read on the
  /// decoder has reported the P8.4 base layer (gamma hlg, primaries bt.2020).
  VideoParams? Function() paramsAfterFirstQuery() {
    var queries = 0;
    return () {
      queries++;
      return queries >= 2
          ? const VideoParams(gamma: 'hlg', primaries: 'bt.2020')
          : null;
    };
  }

  VideoParams? Function() paramsNeverReported() => () => null;

  /// Property reader standing in for mpv: the media is loaded and the
  /// hardware decoder is active from the first query; the DV profile is the
  /// integer `8` and the container facts describe the hinted P8.4 (compat
  /// id 4, no enhancement layer, no HDR Vivid side data). [properties]
  /// overrides single property reads for the unavailable/sentinel scripts.
  HdrPropertyReader reader({Map<String, String> properties = const {}}) {
    return (property) async {
      if (properties.containsKey(property)) {
        return properties[property]!;
      }
      switch (property) {
        case 'path':
          return 'test://media';
        case 'video-format':
          return 'hevc';
        case 'hwdec-current':
          return 'mediacodec';
        case 'current-tracks/video/dolby-vision-profile':
          return '8';
        case 'current-tracks/video/codec':
          return 'hevc';
        case 'current-tracks/video/dolby-vision-compatibility-id':
          return '4';
        case 'current-tracks/video/dolby-vision-el-present':
          return '0';
        case 'video-params/hdr-vivid':
          return 'no';
        default:
          return '';
      }
    };
  }

  Future<FileLoadedRecord> fileLoadedNext(int entryId, int epoch) async =>
      FileLoadedRecord(epoch + 1, entryId);

  test('review waits for late video-params: first review yields 8.4, '
      'no rebuild, baseLayerDirect stays applied', () async {
    final backend = _GatheringBackend(
      readProperty: reader(),
      latestVideoParams: paramsAfterFirstQuery(),
      waitForFileLoadedEntry: fileLoadedNext,
    );
    final session = HdrVideoSession.forTesting(
      player: null,
      capabilitiesProvider: () async => caps(),
      positionProvider: () => Duration.zero,
      isAndroid: true,
      backend: backend,
    );
    final events = <HdrOutputEvent>[];
    session.events.listen(events.add);

    await session.open(Media('test://media'), hint: p84);
    await pumpEventQueue();

    // The one and only open ran on the HLG direct route; the review agreed
    // with the hint on its first execution.
    expect(backend.opened, hasLength(1));
    expect(backend.opened.single.route.strategy, HdrStrategy.baseLayerDirect);
    expect(backend.opened.single.route.outputTransfer, HdrOutputTransfer.hlg);
    expect(backend.reviewFactsCalls, 1);
    final report = session.report.value;
    expect(report.verified, isTrue);
    expect(report.source, p84);
    expect(report.actual!.strategy, HdrStrategy.baseLayerDirect);
    expect(report.diagnostic, isNull);
    expect(events.whereType<HdrDegradedEvent>(), isEmpty);
    expect(events.whereType<HdrReclassifiedEvent>(), isEmpty);
    expect(events.whereType<HdrRouteAppliedEvent>(), hasLength(1));
    await session.dispose();
  });

  test('params poll timeout returns the facts as observed (videoParams null)',
      () async {
    final facts = await AndroidHdrBackend.gatherReviewFacts(
      mediaUri: 'test://media',
      expectedHwdec: 'mediacodec',
      readProperty: reader(),
      latestVideoParams: paramsNeverReported(),
      waitForFileLoadedEntry: fileLoadedNext,
      playlistEntryId: 7,
      fileLoadedEpoch: 3,
      reviewBudget: const Duration(milliseconds: 120),
    );

    // Everything the decoder did report is honest; video-params stayed
    // unreported and are reported as absent, not guessed.
    expect(facts.videoParams, isNull);
    expect(facts.dolbyVisionProfile, 8);
    expect(facts.codec, 'hevc');
    expect(facts.hwdecCurrent, 'mediacodec');
    expect(facts.path, 'test://media');
    expect(facts.dvCompatibilityId, 4);
    expect(facts.dvElPresent, isFalse);
    expect(facts.hdrVivid, isFalse);
  });

  test('gathers the container DV facts and the HDR Vivid fact', () async {
    final facts = await AndroidHdrBackend.gatherReviewFacts(
      mediaUri: 'test://media',
      expectedHwdec: 'mediacodec',
      readProperty: reader(properties: const {
        'current-tracks/video/dolby-vision-compatibility-id': '1',
        'current-tracks/video/dolby-vision-el-present': '1',
        'video-params/hdr-vivid': 'yes',
      }),
      latestVideoParams: paramsAfterFirstQuery(),
      waitForFileLoadedEntry: fileLoadedNext,
      playlistEntryId: 7,
      fileLoadedEpoch: 3,
    );

    expect(facts.dvCompatibilityId, 1);
    expect(facts.dvElPresent, isTrue);
    expect(facts.hdrVivid, isTrue);
  });

  test('unavailable container/Vivid properties read as unknown nulls',
      () async {
    // mpv getProperty returns '' for an unavailable property: a stream
    // without a DOVI configuration record carries no container facts, and
    // upstream mpv has no `video-params/hdr-vivid` sub-property.
    final facts = await AndroidHdrBackend.gatherReviewFacts(
      mediaUri: 'test://media',
      expectedHwdec: 'mediacodec',
      readProperty: reader(properties: const {
        'current-tracks/video/dolby-vision-compatibility-id': '',
        'current-tracks/video/dolby-vision-el-present': '',
        'video-params/hdr-vivid': '',
      }),
      latestVideoParams: paramsAfterFirstQuery(),
      waitForFileLoadedEntry: fileLoadedNext,
      playlistEntryId: 7,
      fileLoadedEpoch: 3,
    );

    expect(facts.dvCompatibilityId, isNull);
    expect(facts.dvElPresent, isNull);
    expect(facts.hdrVivid, isNull);
  });

  test('the -1 unknown sentinels and non-bool readings read as nulls',
      () async {
    final facts = await AndroidHdrBackend.gatherReviewFacts(
      mediaUri: 'test://media',
      expectedHwdec: 'mediacodec',
      readProperty: reader(properties: const {
        'current-tracks/video/dolby-vision-compatibility-id': '-1',
        'current-tracks/video/dolby-vision-el-present': '-1',
        'video-params/hdr-vivid': 'unknown',
      }),
      latestVideoParams: paramsAfterFirstQuery(),
      waitForFileLoadedEntry: fileLoadedNext,
      playlistEntryId: 7,
      fileLoadedEpoch: 3,
    );

    expect(facts.dvCompatibilityId, isNull);
    expect(facts.dvElPresent, isNull);
    expect(facts.hdrVivid, isNull);
  });
}

/// Fake open backend whose review facts come from the REAL
/// `AndroidHdrBackend.gatherReviewFacts` driven by scripted mpv readers.
class _GatheringBackend implements HdrOpenBackend<HdrOpenPlan> {
  _GatheringBackend({
    required this.readProperty,
    required this.latestVideoParams,
    required this.waitForFileLoadedEntry,
  });

  final HdrPropertyReader readProperty;
  final VideoParams? Function() latestVideoParams;
  final Future<FileLoadedRecord> Function(int playlistEntryId, int epoch)
      waitForFileLoadedEntry;

  final opened = <_Opened>[];
  int reviewFactsCalls = 0;
  int _openSerial = 0;

  @override
  Future<void> validate(HdrOpenPlan plan) async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> resetOwnedConfiguration() async {}

  @override
  Future<void> prepareOutput(HdrOpenPlan plan) async {}

  @override
  Future<void> configure(HdrOpenPlan plan) async {}

  @override
  Future<void> waitForOutput(HdrOpenPlan plan) async {}

  @override
  Future<void> open(
    HdrOpenPlan plan, {
    Duration? start,
    required bool play,
  }) async {
    _openSerial++;
    opened.add(_Opened(plan.route, _openSerial));
  }

  @override
  Future<HdrReviewFacts> reviewFacts(HdrOpenPlan plan) async {
    reviewFactsCalls++;
    final epoch = _openSerial * 10;
    return AndroidHdrBackend.gatherReviewFacts(
      mediaUri: plan.media.uri,
      expectedHwdec: plan.route.hwdec,
      readProperty: readProperty,
      latestVideoParams: latestVideoParams,
      waitForFileLoadedEntry: waitForFileLoadedEntry,
      playlistEntryId: _openSerial,
      fileLoadedEpoch: epoch,
    );
  }

  @override
  HdrBackendObservation observe() => const HdrBackendObservation();
}

class _Opened {
  const _Opened(this.route, this.serial);
  final HdrRoute route;
  final int serial;
}
