import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' show VideoParams;
import 'package:media_kit_video/src/hdr/hdr_source_classifier.dart';
import 'package:media_kit_video/src/hdr/hdr_source_descriptor.dart';
import 'package:media_kit_video/src/hdr/hdr_source_facts.dart';
import 'package:media_kit_video/src/hdr/hdr_strategy.dart';

const pq = VideoParams(gamma: 'pq', primaries: 'bt.2020');
const hint = HdrSourceDescriptor(codec: 'hevc', transfer: 'pq',
    primaries: 'bt.2020', enhancementLayer: false);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('HDR10+ per-frame presence is independent of scene statistics', () {
    const classifier = HdrSourceClassifier();
    final positive = classifier.classify(
        videoParams: pq, hint: hint, hdr10Plus: true);
    expect(positive.dynamicMetadata, HdrDynamicMetadata.hdr10Plus);
    expect(HdrSourceClass.of(positive), HdrSourceClass.hdr10Plus);
    final missing = classifier.classify(videoParams: pq, hint: hint);
    expect(missing.dynamicMetadata, HdrDynamicMetadata.none);
    final negative = classifier.classify(
        videoParams: pq, hint: hint, hdr10Plus: false);
    expect(negative.dynamicMetadata, HdrDynamicMetadata.none);
  });

  test('DV profile outranks contradictory HDR10+ frame side data', () {
    const classifier = HdrSourceClassifier();
    final source = classifier.classify(
      videoParams: pq,
      dolbyVisionProfile: 8,
      dvElPresent: false,
      hdr10Plus: true,
    );
    expect(source.dynamicMetadata, HdrDynamicMetadata.dolbyVision);
    expect(HdrSourceClass.of(source), HdrSourceClass.dvP81);
  });

  test('Vivid takes precedence in a simultaneous profile-less sample', () {
    const classifier = HdrSourceClassifier();
    final source = classifier.classify(
        videoParams: pq, hdrVivid: true, hdr10Plus: true);
    expect(source.dynamicMetadata, HdrDynamicMetadata.hdrVivid);
    // Classification alone has no history; source facts must reject
    // ambiguous simultaneous affirmative formats.
    final facts = HdrSourceFacts.fromHint(hint).observe(
      videoParams: pq, hdrVivid: true, hdr10Plus: true,
      inferSourceColorFromDecoder: true,
    );
    expect(facts.hasConflict, isTrue);
    expect(facts.conflicts.single.field, HdrSourceField.dynamicMetadata);
  });

  test('HDR10+ positive cannot be erased by missing or negative later frame', () {
    final positive = HdrSourceFacts.fromHint(hint).observe(
      videoParams: pq, hdr10Plus: true,
      inferSourceColorFromDecoder: true,
    );
    expect(positive.source.dynamicMetadata, HdrDynamicMetadata.hdr10Plus);
    final missing = positive.observe(
        videoParams: pq, inferSourceColorFromDecoder: true);
    expect(missing.source.dynamicMetadata, HdrDynamicMetadata.hdr10Plus);
    expect(missing.hdr10PlusOnFrame, isNull);
    final negative = missing.observe(
      videoParams: pq, hdr10Plus: false,
      inferSourceColorFromDecoder: true,
    );
    expect(negative.source.dynamicMetadata, HdrDynamicMetadata.hdr10Plus);
    expect(negative.hdr10PlusOnFrame, isFalse);
    expect(negative.hasConflict, isFalse);
  });

  test('different affirmative formats across one logical open block', () {
    final first = HdrSourceFacts.fromHint(hint).observe(
      videoParams: pq, hdr10Plus: true,
      inferSourceColorFromDecoder: true,
    );
    final contradicted = first.observe(
      videoParams: pq, hdrVivid: true,
      inferSourceColorFromDecoder: true,
    );
    expect(contradicted.hasConflict, isTrue);
    expect(contradicted.conflicts.first.previous,
        HdrDynamicMetadata.hdr10Plus);
    expect(contradicted.conflicts.first.observed,
        HdrDynamicMetadata.hdrVivid);
  });

  test('decoder affirmative evidence corrects a weaker explicit hint', () {
    const oldHint = HdrSourceDescriptor(codec: 'hevc', transfer: 'pq',
      primaries: 'bt.2020',
      dynamicMetadata: HdrDynamicMetadata.hdrVivid);
    final observed = HdrSourceFacts.fromHint(oldHint).observe(
      videoParams: pq, hdr10Plus: true,
      inferSourceColorFromDecoder: true,
    );
    expect(observed.hasConflict, isFalse);
    expect(observed.source.dynamicMetadata, HdrDynamicMetadata.hdr10Plus);
    expect(observed.origins[HdrSourceField.dynamicMetadata],
        HdrSourceFactOrigin.decoder);
  });

  test('older mpv without hdr10-plus field remains unknown, never false', () {
    final facts = HdrSourceFacts.fromHint(const HdrSourceDescriptor(
      codec: 'hevc', transfer: 'pq', primaries: 'bt.2020',
      dynamicMetadata: HdrDynamicMetadata.hdr10Plus,
    )).observe(videoParams: pq, hdr10Plus: null,
        inferSourceColorFromDecoder: true);
    expect(facts.source.dynamicMetadata, HdrDynamicMetadata.hdr10Plus);
    expect(facts.hdr10PlusOnFrame, isNull);
  });

  test('source-fact reset happens on each new logical open', () {
    final first = HdrSourceFacts.fromHint(hint).observe(
      videoParams: pq, hdr10Plus: true,
      inferSourceColorFromDecoder: true,
    );
    final next = HdrSourceFacts.fromHint(hint).observe(
      videoParams: pq, hdr10Plus: false,
      inferSourceColorFromDecoder: true,
    );
    expect(first.source.dynamicMetadata, HdrDynamicMetadata.hdr10Plus);
    expect(next.source.dynamicMetadata, HdrDynamicMetadata.none);
  });
}
