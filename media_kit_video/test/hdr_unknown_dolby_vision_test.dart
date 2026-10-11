import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/src/hdr/hdr_capabilities.dart';
import 'package:media_kit_video/src/hdr/hdr_output_policy.dart';
import 'package:media_kit_video/src/hdr/hdr_route.dart';
import 'package:media_kit_video/src/hdr/hdr_route_planner.dart';
import 'package:media_kit_video/src/hdr/hdr_source_classifier.dart';
import 'package:media_kit_video/src/hdr/hdr_source_descriptor.dart';
import 'package:media_kit_video/src/hdr/hdr_strategy.dart';
import 'package:media_kit_video/src/hdr/hdr_strategy_realizer.dart';

const _capabilities = HdrCapabilities(
  sdkInt: 35,
  displayHdrTypes: <int>{1, 2, 3, 4},
  hevcDecoders: <HdrDecoderInfo>[],
  dolbyVisionDecoders: <HdrDecoderInfo>[],
  p5PipelineAvailable: true,
  dataSpaceBridgeLoaded: true,
  dataSpaceExt: null,
);

HdrSourceDescriptor _dv({int? profile = 8, int? compatibility, String? gamma}) =>
    HdrSourceDescriptor(
      codec: profile == 10 ? 'av1' : 'hevc',
      dynamicMetadata: HdrDynamicMetadata.dolbyVision,
      dvProfile: profile,
      dvCompatibilityId: compatibility,
      transfer: gamma,
    );

void main() {
  for (final profile in <int?>[8, 10, null, 99]) {
    for (final gamma in <String?>[null, '', 'auto', 'unknown', 'linear']) {
      test('unresolved DV profile=$profile gamma=$gamma is not SDR or P5', () {
        final source = _dv(profile: profile, gamma: gamma);
        expect(source.hasUnresolvedDolbyVision, isTrue);
        expect(source.kind, HdrMediaKind.dolbyVisionUnknown);
        expect(HdrSourceClass.of(source), HdrSourceClass.dvUnknown);
        for (final experimental in <bool>[false, true]) {
          final policy = HdrRoutingPolicy(
            allowExperimental: experimental,
            preferences: <HdrSourceClass, List<HdrStrategy>>{
              HdrSourceClass.dvUnknown: HdrStrategy.values,
            },
          );
          for (final preference in HdrOutputPreference.values) {
            final prediction = HdrRoutePlanner.plan(
              source: source,
              capabilities: _capabilities,
              policy: policy,
              preference: preference,
            );
            expect(prediction.playable, isFalse);
            expect(prediction.confidence, HdrPredictionConfidence.unverified);
            for (final candidate in prediction.candidates) {
              expect(candidate.route, isNull);
              expect(candidate.feasible, isFalse);
              expect(candidate.skipReason, HdrDegradeReason.sourceMetadataUnknown);
            }
          }
        }
      });
    }
  }

  test('direct realizer cannot override unresolved facts with a chosen class', () {
    final source = _dv();
    for (final strategy in HdrStrategy.values) {
      for (final coarseClass in HdrSourceClass.values) {
        final result = HdrStrategyRealizer.realize(
          strategy,
          source: source,
          sourceClass: coarseClass,
          capabilities: _capabilities,
        );
        expect(result.route, isNull);
        expect(result.infeasibleReason, HdrDegradeReason.sourceMetadataUnknown);
      }
    }
  });

  for (final profile in <int>[8, 10]) {
    test('profile $profile infers compatibility only from known gamma', () {
      for (final gamma in <String?>[null, '', 'auto', 'future-transfer', 'linear']) {
        final source = const HdrSourceClassifier().classify(
          dolbyVisionProfile: profile,
          videoParams: VideoParams(gamma: gamma),
        );
        expect(source.dvCompatibilityId, isNull);
        expect(source.kind, HdrMediaKind.dolbyVisionUnknown);
      }
      for (final entry in <String, int>{'pq': 1, 'hlg': 4, 'bt.1886': 2, 'srgb': 2, 'gamma2.2': 2}.entries) {
        final source = const HdrSourceClassifier().classify(
          dolbyVisionProfile: profile,
          videoParams: VideoParams(gamma: entry.key),
        );
        expect(source.dvCompatibilityId, entry.value);
        expect(source.hasUnresolvedDolbyVision, isFalse);
      }
    });
  }

  test('explicit unsupported compatibility cannot be overwritten by gamma', () {
    for (final id in <int>[0, 3, 5, 99]) {
      for (final gamma in <String>['pq', 'hlg', 'srgb']) {
        final source = _dv(compatibility: id, gamma: gamma);
        expect(source.dvCompatibilityId, id);
        expect(HdrSourceClass.of(source), HdrSourceClass.dvUnknown);
      }
    }
  });

  test('known compatibility wins over processed or unavailable gamma', () {
    for (final entry in <int, HdrSourceClass>{
      1: HdrSourceClass.dvP81,
      2: HdrSourceClass.dvP82,
      4: HdrSourceClass.dvP84,
    }.entries) {
      for (final gamma in <String?>[null, 'pq', 'hlg', 'bt.1886']) {
        final source = _dv(compatibility: entry.key, gamma: gamma);
        expect(HdrSourceClass.of(source), entry.value);
        expect(source.hasUnresolvedDolbyVision, isFalse);
      }
    }
  });

  test('known P5 need not have an ordinary base-layer gamma', () {
    expect(HdrSourceClass.of(_dv(profile: 5)), HdrSourceClass.dvP5);
    expect(_dv(profile: 5).kind, HdrMediaKind.dolbyVisionP5);
  });

  test('ordinary unlabeled media retains the existing SDR baseline', () {
    const source = HdrSourceDescriptor();
    expect(source.hasUnresolvedDolbyVision, isFalse);
    expect(source.kind, HdrMediaKind.sdr);
    expect(_capabilities.predict(source).playable, isTrue);
  });

  test('legacy policy rejects unknown DV for both output topologies', () {
    for (final platformView in <bool>[false, true]) {
      expect(
        () => HdrOutputPolicy.decide(
          HdrMediaKind.dolbyVisionUnknown,
          usePlatformView: platformView,
          p5DoviRescaleAvailable: true,
          displayHdrTypes: <int>{1, 2, 3},
        ),
        throwsStateError,
      );
    }
  });

  test('additional source facts can resolve a previously blocked source', () {
    final unresolved = _dv();
    final resolved = const HdrSourceClassifier().classify(
      dolbyVisionProfile: 8,
      dvCompatibilityId: 4,
      dvElPresent: false,
      hint: unresolved,
    );
    expect(_capabilities.predict(unresolved).playable, isFalse);
    expect(HdrSourceClass.of(resolved), HdrSourceClass.dvP84);
    expect(_capabilities.predict(resolved).playable, isTrue);
    expect(unresolved.dvCompatibilityId, isNull);
  });
}
