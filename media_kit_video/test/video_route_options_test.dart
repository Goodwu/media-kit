import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit_video/src/routing/video_route_options.dart';

void main() {
  const hardware =
      VideoRouteSelection<VideoDecodeTarget>.prefer(VideoDecodeTarget.hardware);
  const software = VideoRouteSelection<VideoDecodeTarget>.require(
      VideoDecodeTarget.software);
  const hdr =
      VideoRouteSelection<VideoOutputIntent>.require(VideoOutputIntent.hdr);
  const sdr =
      VideoRouteSelection<VideoOutputIntent>.require(VideoOutputIntent.sdr);

  test('default is automatic with experimental disabled', () {
    final options = EffectiveVideoRouteOptions.resolve();
    expect(options.decode.preference, VideoRoutePreference.auto);
    expect(options.output.preference, VideoRoutePreference.auto);
    expect(options.experimental, false);
    expect(options.failurePolicy, VideoRouteFailurePolicy.allowAlternatives);
    expect(options.origins.values.toSet(),
        {VideoRouteOptionOrigin.libraryDefault});
  });

  for (final preference in VideoImportPreference.values) {
    test('import $preference roundtrip, provenance and explicit auto reset',
        () {
      final requested = VideoRouteOptions(importPreference: preference);
      expect(VideoRouteOptions.fromMap(requested.toMap()), requested);
      final value = EffectiveVideoRouteOptions.resolve(application: requested);
      expect(value.importPreference, preference);
      expect(value.origins['importPreference'],
          VideoRouteOptionOrigin.application);
      final reset = EffectiveVideoRouteOptions.resolve(
          application: requested,
          openOverride: const VideoRouteOptions(
              importPreference: VideoImportPreference.auto));
      expect(reset.importPreference, VideoImportPreference.auto);
      expect(reset.origins['importPreference'],
          VideoRouteOptionOrigin.openOverride);
      expect(reset.application, requested);
      expect(requested.merge(const VideoRouteOptions()), requested);
      expect(const VideoRouteOptions().key, isNot(requested.key));
    });
  }

  test('unset inherits application and partial library defaults', () {
    final options = EffectiveVideoRouteOptions.resolve(
      libraryDefaults: const VideoRouteOptions(output: hdr, experimental: true),
      application: const VideoRouteOptions(decode: hardware),
    );
    expect(options.decode, hardware);
    expect(options.output, hdr);
    expect(options.experimental, true);
    expect(options.failurePolicy, VideoRouteFailurePolicy.allowAlternatives);
    expect(options.origins['decode'], VideoRouteOptionOrigin.application);
    expect(options.origins['output'], VideoRouteOptionOrigin.libraryDefault);
  });

  test('explicit auto resets application requirements', () {
    final options = EffectiveVideoRouteOptions.resolve(
      application: const VideoRouteOptions(decode: software, output: hdr),
      openOverride: const VideoRouteOptions(
        decode: VideoRouteSelection<VideoDecodeTarget>.auto(),
        output: VideoRouteSelection<VideoOutputIntent>.auto(),
      ),
    );
    expect(options.decode.target, null);
    expect(options.output.target, null);
    expect(options.origins['output'], VideoRouteOptionOrigin.openOverride);
    expect(options.application.output, hdr);
  });

  test('explicit false and allowAlternatives reset their lower values', () {
    final options = EffectiveVideoRouteOptions.resolve(
      application: const VideoRouteOptions(
        experimental: true,
        failurePolicy: VideoRouteFailurePolicy.stop,
      ),
      openOverride: const VideoRouteOptions(
        experimental: false,
        failurePolicy: VideoRouteFailurePolicy.allowAlternatives,
      ),
    );
    expect(options.experimental, false);
    expect(options.failurePolicy, VideoRouteFailurePolicy.allowAlternatives);
    expect(
        options.origins['experimental'], VideoRouteOptionOrigin.openOverride);
  });

  for (final experimental in [false, true]) {
    for (final policy in VideoRouteFailurePolicy.values) {
      test(
          'requirements survive experimental=$experimental failure=${policy.name}',
          () {
        final options = EffectiveVideoRouteOptions.resolve(
          application: const VideoRouteOptions(decode: software, output: hdr),
          openOverride: VideoRouteOptions(
              experimental: experimental, failurePolicy: policy),
        );
        expect(options.decode, software);
        expect(options.output, hdr);
        expect(options.decode.isRequired, true);
        expect(options.output.isRequired, true);
      });
    }
  }

  test('higher required target replaces lower required target', () {
    final options = EffectiveVideoRouteOptions.resolve(
      application: const VideoRouteOptions(output: hdr),
      openOverride: const VideoRouteOptions(output: sdr),
    );
    expect(options.output, sdr);
    expect(options.origins['output'], VideoRouteOptionOrigin.openOverride);
  });

  test('explicit higher preference replaces lower requirement', () {
    final options = EffectiveVideoRouteOptions.resolve(
      application: const VideoRouteOptions(decode: software, output: hdr),
      openOverride: const VideoRouteOptions(
        decode: hardware,
        output: VideoRouteSelection<VideoOutputIntent>.prefer(
            VideoOutputIntent.sdr),
      ),
    );
    expect(options.decode.preference, VideoRoutePreference.prefer);
    expect(options.output.preference, VideoRoutePreference.prefer);
    expect(options.application.decode, software);
    expect(options.application.output, hdr);
    expect(options.origins['decode'], VideoRouteOptionOrigin.openOverride);
  });

  for (final target in VideoDecodeTarget.values) {
    for (final preference in [
      VideoRoutePreference.prefer,
      VideoRoutePreference.require
    ]) {
      test('decode ${preference.name} ${target.name} roundtrip', () {
        final options = VideoRouteOptions.fromMap({
          'decode': {'preference': preference.name, 'target': target.name},
        });
        expect(options.decode?.target, target);
        expect(options.decode?.preference, preference);
        expect(
            VideoRouteOptions.fromMap(
                jsonDecode(options.key) as Map<String, Object?>),
            options);
      });
    }
  }

  for (final target in VideoOutputIntent.values) {
    for (final preference in [
      VideoRoutePreference.prefer,
      VideoRoutePreference.require
    ]) {
      test('output ${preference.name} ${target.name} roundtrip', () {
        final options = VideoRouteOptions.fromMap({
          'output': {'preference': preference.name, 'target': target.name},
        });
        expect(options.output?.target, target);
        expect(options.output?.preference, preference);
        expect(
            VideoRouteOptions.fromMap(
                jsonDecode(options.key) as Map<String, Object?>),
            options);
      });
    }
  }

  test('merge does not mutate either requested layer', () {
    const first = VideoRouteOptions(decode: hardware, output: hdr);
    const second = VideoRouteOptions(decode: software);
    expect(first.merge(second),
        const VideoRouteOptions(decode: software, output: hdr));
    expect(first.decode, hardware);
    expect(second.output, null);
  });

  test('requested values have equality and canonical JSON roundtrip', () {
    const options =
        VideoRouteOptions(decode: software, output: sdr, experimental: false);
    final fromJson = VideoRouteOptions.fromMap(
        jsonDecode(options.key) as Map<String, Object?>);
    expect(fromJson, options);
    expect(fromJson.hashCode, options.hashCode);
    expect(fromJson.key, options.key);
    expect(const VideoRouteOptions(),
        isNot(const VideoRouteOptions(experimental: false)));
  });

  test('explicit auto and unset are different requested values', () {
    expect(
        const VideoRouteOptions(),
        isNot(const VideoRouteOptions(
          decode: VideoRouteSelection<VideoDecodeTarget>.auto(),
        )));
  });

  test('effective equality includes immutable request provenance', () {
    final first = EffectiveVideoRouteOptions.resolve(
        application: const VideoRouteOptions(decode: hardware));
    final same = EffectiveVideoRouteOptions.resolve(
        application: const VideoRouteOptions(decode: hardware));
    final differentOrigin = EffectiveVideoRouteOptions.resolve(
        openOverride: const VideoRouteOptions(decode: hardware));
    expect(first, same);
    expect(first.hashCode, same.hashCode);
    expect(first, isNot(differentOrigin));
    expect(first.decode, differentOrigin.decode);
  });

  test('serialization is deeply immutable and inputs do not alias', () {
    final input = <String, Object?>{
      'decode': <String, Object?>{
        'preference': 'require',
        'target': 'software'
      },
    };
    final requested = VideoRouteOptions.fromMap(input);
    (input['decode'] as Map<String, Object?>)['target'] = 'hardware';
    expect(requested.decode, software);
    final effective =
        EffectiveVideoRouteOptions.resolve(application: requested);
    final map = effective.toMap();
    expect(() => map['experimental'] = true, throwsUnsupportedError);
    expect(() => (map['decode'] as Map<String, Object?>)['target'] = 'hardware',
        throwsUnsupportedError);
    expect(
        () =>
            effective.origins['decode'] = VideoRouteOptionOrigin.libraryDefault,
        throwsUnsupportedError);
    final layers = map['requested'] as Map<String, Object?>;
    final application = layers['application'] as Map<String, Object?>;
    expect(() => application['output'] = sdr.toMap(), throwsUnsupportedError);
    expect(
        () => (application['decode'] as Map<String, Object?>)['target'] =
            'hardware',
        throwsUnsupportedError);
  });

  final malformed = <String, Map<String, Object?>>{
    'auto plus target': {
      'decode': {'preference': 'auto', 'target': 'hardware'}
    },
    'require without target': {
      'output': {'preference': 'require'}
    },
    'prefer without target': {
      'decode': {'preference': 'prefer', 'target': null}
    },
    'two targets': {
      'decode': {
        'preference': 'require',
        'target': ['hardware', 'software']
      }
    },
    'wrong axis target': {
      'decode': {'preference': 'require', 'target': 'hdr'}
    },
    'missing strength': {
      'decode': {'target': 'hardware'}
    },
    'unknown strength': {
      'decode': {'preference': 'force', 'target': 'hardware'}
    },
    'unknown field': {'hardware': 'require', 'software': 'require'},
    'nested unknown field': {
      'output': {'preference': 'auto', 'hdr': 'require'}
    },
    'non boolean experiment': {'experimental': 'false'},
    'unknown fallback': {'failurePolicy': 'ignore'},
    'non object selection': {'decode': 'auto'},
  };
  for (final entry in malformed.entries) {
    test('reject malformed or contradictory ${entry.key}', () {
      expect(
          () => VideoRouteOptions.fromMap(entry.value), throwsFormatException);
    });
  }
}
