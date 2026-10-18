import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' show VideoParams;
import 'package:media_kit_video/src/hdr/hdr_source_descriptor.dart';
import 'package:media_kit_video/src/hdr/hdr_source_facts.dart';
import 'package:media_kit_video/src/hdr/hdr_strategy.dart';

void main() {
  const p84 = HdrSourceDescriptor(
    codec: 'hevc', transfer: 'hlg', primaries: 'bt.2020',
    dynamicMetadata: HdrDynamicMetadata.dolbyVision,
    dvProfile: 8, dvCompatibilityId: 4, enhancementLayer: false,
  );
  const hdr10 = HdrSourceDescriptor(
    codec: 'hevc', transfer: 'pq', primaries: 'bt.2020',
    enhancementLayer: false,
  );
  const p5 = HdrSourceDescriptor(
    codec: 'hevc', dynamicMetadata: HdrDynamicMetadata.dolbyVision,
    dvProfile: 5, dvCompatibilityId: 0, enhancementLayer: false,
  );

  test('initial hint is immutable, provisional, and has no decoded sample', () {
    final facts = HdrSourceFacts.fromHint(p84);
    expect(facts.initialHint, same(p84));
    expect(facts.source, p84);
    expect(facts.videoParams, isNull);
    expect(facts.reviewCount, 0);
    expect(facts.retainsHint, isTrue);
    expect(facts.origins.values.toSet(), {HdrSourceFactOrigin.hint});
    expect(() => facts.origins.clear(), throwsUnsupportedError);
    expect(() => facts.conflicts.clear(), throwsUnsupportedError);
  });

  test('partial frame does not erase hinted DV or populate track evidence', () {
    final before = HdrSourceFacts.fromHint(p84);
    final after = before.observe(
      videoParams: const VideoParams(gamma: 'hlg'), codec: 'hevc',
      inferSourceColorFromDecoder: true,
    );
    expect(after.source, p84);
    expect(after.origins[HdrSourceField.dvProfile], HdrSourceFactOrigin.hint);
    expect(after.origins[HdrSourceField.enhancementLayer], HdrSourceFactOrigin.hint);
    expect(after.origins[HdrSourceField.codec], HdrSourceFactOrigin.track);
    expect(before.reviewCount, 0);
    expect(after.reviewCount, 1);
  });

  test('native DV output PQ does not turn original HLG base layer into PQ', () {
    const decoded = VideoParams(gamma: 'pq', primaries: 'bt.709');
    final facts = HdrSourceFacts.fromHint(p84).observe(
      videoParams: decoded, dolbyVisionProfile: 8,
      dvCompatibilityId: 4, dvElPresent: false, codec: 'hevc',
      inferSourceColorFromDecoder: false,
    );
    expect(facts.source, p84);
    expect(facts.videoParams, same(decoded));
    expect(facts.origins[HdrSourceField.transfer], HdrSourceFactOrigin.track);
    expect(facts.origins[HdrSourceField.primaries], HdrSourceFactOrigin.hint);
  });

  test('native frame cannot infer a missing DV compatibility', () {
    final facts = HdrSourceFacts.fromHint(null).observe(
      videoParams: const VideoParams(gamma: 'pq', primaries: 'bt.2020'),
      dolbyVisionProfile: 8, inferSourceColorFromDecoder: false,
    );
    expect(facts.source.dvCompatibilityId, isNull);
    expect(facts.source.transfer, isNull);
    expect(HdrSourceClass.of(facts.source), HdrSourceClass.dvUnknown);
  });

  test('ordinary decoder may infer missing compatibility with explicit origin', () {
    final facts = HdrSourceFacts.fromHint(null).observe(
      videoParams: const VideoParams(gamma: 'hlg', primaries: 'bt.2020'),
      dolbyVisionProfile: 8, codec: 'hevc',
      inferSourceColorFromDecoder: true,
    );
    expect(facts.source.dvCompatibilityId, 4);
    expect(facts.source.enhancementLayer, isNull);
    expect(facts.origins[HdrSourceField.dvCompatibilityId], HdrSourceFactOrigin.decoder);
    expect(facts.origins[HdrSourceField.dvProfile], HdrSourceFactOrigin.track);
  });

  test('explicit unsupported compatibility is not overwritten by decoder gamma', () {
    final facts = HdrSourceFacts.fromHint(const HdrSourceDescriptor(
      dynamicMetadata: HdrDynamicMetadata.dolbyVision,
      dvProfile: 8, dvCompatibilityId: 99,
    )).observe(
      videoParams: const VideoParams(gamma: 'hlg'),
      inferSourceColorFromDecoder: true,
    );
    expect(facts.source.dvCompatibilityId, 99);
    expect(facts.source.hasUnresolvedDolbyVision, isTrue);
  });

  test('missing observations across a reopen do not delete positive track facts', () {
    final first = HdrSourceFacts.fromHint(p84).observe(
      dolbyVisionProfile: 8, dvCompatibilityId: 4, dvElPresent: false,
      codec: 'hevc', inferSourceColorFromDecoder: false,
    );
    final second = first.observe(
      videoParams: const VideoParams(gamma: 'pq'), hdrVivid: false,
      inferSourceColorFromDecoder: true,
    );
    expect(second.source, p84);
    expect(second.origins[HdrSourceField.dvProfile], HdrSourceFactOrigin.track);
    expect(second.origins[HdrSourceField.enhancementLayer], HdrSourceFactOrigin.track);
    expect(second.videoParams!.gamma, 'pq');
    expect(second.reviewCount, 2);
  });

  test('affirmative track profile corrects a hint without borrowing its EL', () {
    final facts = HdrSourceFacts.fromHint(p5).observe(
      dolbyVisionProfile: 8, videoParams: const VideoParams(gamma: 'hlg'),
      inferSourceColorFromDecoder: true,
    );
    expect(facts.source.dvProfile, 8);
    expect(facts.source.dvCompatibilityId, 4);
    expect(facts.source.enhancementLayer, isNull);
    expect(facts.hasConflict, isFalse);
    expect(facts.initialHint, p5);
  });

  test('changed hint profile with no source tags remains unresolved', () {
    final facts = HdrSourceFacts.fromHint(p5).observe(
      dolbyVisionProfile: 8, inferSourceColorFromDecoder: false,
    );
    expect(facts.source.dvCompatibilityId, isNull);
    expect(facts.source.enhancementLayer, isNull);
    expect(HdrSourceClass.of(facts.source), HdrSourceClass.dvUnknown);
  });

  test('explicit compatibility corrects a hint and original transfer together', () {
    final facts = HdrSourceFacts.fromHint(p84).observe(
      dolbyVisionProfile: 8, dvCompatibilityId: 1,
      videoParams: const VideoParams(gamma: 'hlg'),
      inferSourceColorFromDecoder: false,
    );
    expect(facts.source.dvCompatibilityId, 1);
    expect(facts.source.transfer, 'pq');
    expect(facts.videoParams!.gamma, 'hlg');
    expect(facts.hasConflict, isFalse);
  });

  test('contradicting observed track compatibility is not a valid correction', () {
    final first = HdrSourceFacts.fromHint(p84).observe(
      dolbyVisionProfile: 8, dvCompatibilityId: 4,
      inferSourceColorFromDecoder: false,
    );
    final second = first.observe(
      dolbyVisionProfile: 8, dvCompatibilityId: 1,
      inferSourceColorFromDecoder: false,
    );
    expect(first.hasConflict, isFalse);
    expect(second.hasConflict, isTrue);
    expect(second.conflicts.single.field, HdrSourceField.dvCompatibilityId);
    expect(second.conflicts.single.previous, 4);
    expect(second.conflicts.single.observed, 1);
    expect(second.observe(inferSourceColorFromDecoder: true).hasConflict, isTrue);
  });

  for (final field in ['profile', 'el', 'codec']) {
    test('affirmative $field conflict is retained for fail-closed review', () {
      final first = HdrSourceFacts.fromHint(p84).observe(
        dolbyVisionProfile: 8, dvCompatibilityId: 4, dvElPresent: false,
        codec: 'hevc', inferSourceColorFromDecoder: false,
      );
      final second = first.observe(
        dolbyVisionProfile: field == 'profile' ? 5 : null,
        dvElPresent: field == 'el' ? true : null,
        codec: field == 'codec' ? 'av1' : '',
        inferSourceColorFromDecoder: false,
      );
      expect(second.hasConflict, isTrue);
      expect(first.source, p84);
    });
  }

  test('negative sentinels do not erase valid observed values', () {
    final first = HdrSourceFacts.fromHint(p84).observe(
      dolbyVisionProfile: 8, dvCompatibilityId: 4, dvElPresent: false,
      inferSourceColorFromDecoder: false,
    );
    final second = first.observe(
      dolbyVisionProfile: -1, dvCompatibilityId: -1,
      inferSourceColorFromDecoder: false,
    );
    expect(second.source, first.source);
    expect(second.hasConflict, isFalse);
  });

  test('HDR Vivid presence survives a frame without dynamic side data', () {
    final first = HdrSourceFacts.fromHint(hdr10).observe(
      videoParams: const VideoParams(gamma: 'pq', primaries: 'bt.2020'),
      hdrVivid: true, inferSourceColorFromDecoder: true,
    );
    final second = first.observe(hdrVivid: false, inferSourceColorFromDecoder: true);
    expect(second.source.dynamicMetadata, HdrDynamicMetadata.hdrVivid);
    expect(second.hdrVividOnFrame, isFalse);
    expect(second.videoParams, isNull);
    expect(first.hdrVividOnFrame, isTrue);
  });

  test('HDR10+ hint is not disproved by absent HDR Vivid on a frame', () {
    const source = HdrSourceDescriptor(
      transfer: 'pq', primaries: 'bt.2020',
      dynamicMetadata: HdrDynamicMetadata.hdr10Plus,
    );
    final facts = HdrSourceFacts.fromHint(source).observe(
      hdrVivid: false, inferSourceColorFromDecoder: true,
    );
    expect(facts.source, source);
    expect(facts.origins[HdrSourceField.dynamicMetadata], HdrSourceFactOrigin.hint);
  });

  test('an empty later frame does not erase known source color tags', () {
    final first = HdrSourceFacts.fromHint(null).observe(
      codec: 'hevc', videoParams: const VideoParams(gamma: 'pq', primaries: 'bt.2020'),
      inferSourceColorFromDecoder: true,
    );
    final second = first.observe(
      videoParams: const VideoParams(), inferSourceColorFromDecoder: true,
    );
    expect(second.source, hdr10);
    expect(second.videoParams!.gamma, isNull);
    expect(second.origins[HdrSourceField.transfer], HdrSourceFactOrigin.decoder);
  });

  test('placeholder frame tags do not erase known HDR source tags', () {
    final facts = HdrSourceFacts.fromHint(hdr10).observe(
      videoParams: const VideoParams(gamma: 'unknown', primaries: 'unknown'),
      inferSourceColorFromDecoder: true,
    );
    expect(facts.source, hdr10);
    expect(facts.videoParams!.gamma, 'unknown');
  });

  test('independent opens do not inherit metadata even with the same URI', () {
    final previous = HdrSourceFacts.fromHint(p84).observe(
      dolbyVisionProfile: 8, dvCompatibilityId: 4,
      inferSourceColorFromDecoder: false,
    );
    final next = HdrSourceFacts.fromHint(null).observe(
      videoParams: const VideoParams(gamma: 'bt.1886', primaries: 'bt.709'),
      inferSourceColorFromDecoder: true,
    );
    expect(next.source.dynamicMetadata, HdrDynamicMetadata.none);
    expect(next.source.dvProfile, isNull);
    expect(next.reviewCount, 1);
    expect(previous.source.dvProfile, 8);
  });

  test('no hint or observations still represents ordinary undescribed input', () {
    final facts = HdrSourceFacts.fromHint(null).observe(
      inferSourceColorFromDecoder: false,
    );
    expect(facts.source, const HdrSourceDescriptor());
    expect(facts.origins, isEmpty);
  });
}
