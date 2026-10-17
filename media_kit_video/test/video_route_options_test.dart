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

  test('default is automatic with alternatives allowed', () {
    final options = EffectiveVideoRouteOptions.resolve();
    expect(options.decode.preference, VideoRoutePreference.auto);
    expect(options.output.preference, VideoRoutePreference.auto);
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
      libraryDefaults: const VideoRouteOptions(output: hdr),
      application: const VideoRouteOptions(decode: hardware),
    );
    expect(options.decode, hardware);
    expect(options.output, hdr);
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

  test('explicit allowAlternatives resets the lower stop requirement', () {
    final options = EffectiveVideoRouteOptions.resolve(
      application: const VideoRouteOptions(
        failurePolicy: VideoRouteFailurePolicy.stop,
      ),
      openOverride: const VideoRouteOptions(
        failurePolicy: VideoRouteFailurePolicy.allowAlternatives,
      ),
    );
    expect(options.failurePolicy, VideoRouteFailurePolicy.allowAlternatives);
    expect(
        options.origins['failurePolicy'], VideoRouteOptionOrigin.openOverride);
  });

  for (final policy in VideoRouteFailurePolicy.values) {
    test('requirements survive failure=${policy.name}', () {
      final options = EffectiveVideoRouteOptions.resolve(
        application: const VideoRouteOptions(decode: software, output: hdr),
        openOverride: VideoRouteOptions(failurePolicy: policy),
      );
      expect(options.decode, software);
      expect(options.output, hdr);
      expect(options.decode.isRequired, true);
      expect(options.output.isRequired, true);
    });
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
    const options = VideoRouteOptions(decode: software, output: sdr);
    final fromJson = VideoRouteOptions.fromMap(
        jsonDecode(options.key) as Map<String, Object?>);
    expect(fromJson, options);
    expect(fromJson.hashCode, options.hashCode);
    expect(fromJson.key, options.key);
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
    expect(map.containsKey('experimental'), isFalse);
    expect(() => map['failurePolicy'] = 'stop', throwsUnsupportedError);
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
    'unknown fallback': {'failurePolicy': 'ignore'},
    'non object selection': {'decode': 'auto'},
  };
  for (final entry in malformed.entries) {
    test('reject malformed or contradictory ${entry.key}', () {
      expect(
          () => VideoRouteOptions.fromMap(entry.value), throwsFormatException);
    });
  }

  test('legacy persisted experimental key is dropped once on read', () {
    // Migration contract: old persisted configurations may still carry the
    // removed `experimental` key. It is accepted, silently dropped, and
    // never written back.
    expect(VideoRouteOptions.fromMap({'experimental': true}),
        const VideoRouteOptions());
    expect(VideoRouteOptions.fromMap({'experimental': false}),
        const VideoRouteOptions());
    expect(VideoRouteOptions.fromMap({'experimental': 'false'}),
        const VideoRouteOptions());
    final legacy = VideoRouteOptions.fromMap({
      'decode': {'preference': 'require', 'target': 'software'},
      'experimental': true,
    });
    expect(legacy, const VideoRouteOptions(decode: software));
    expect(legacy.toMap().containsKey('experimental'), isFalse);
    expect(EffectiveVideoRouteOptions.resolve(application: legacy).toMap()
        .containsKey('experimental'), isFalse);
  });

  test('sdrEmbed defaults to false at every layer and origin', () {
    const unset = VideoRouteOptions();
    expect(unset.sdrEmbed, isNull);
    final effective = EffectiveVideoRouteOptions.resolve();
    expect(effective.sdrEmbed, isFalse);
    expect(
        effective.origins['sdrEmbed'], VideoRouteOptionOrigin.libraryDefault);
    // A persisted configuration from before the field existed loads unchanged.
    final preField = VideoRouteOptions.fromMap({
      'importPreference': 'auto',
    });
    expect(preField.sdrEmbed, isNull);
    expect(EffectiveVideoRouteOptions.resolve(application: preField).sdrEmbed,
        isFalse);
  });

  test('sdrEmbed declaration roundtrips and resolves per layer', () {
    final requested = const VideoRouteOptions(sdrEmbed: true);
    expect(VideoRouteOptions.fromMap(requested.toMap()), requested);
    expect(
        VideoRouteOptions.fromMap(jsonDecode(requested.key)
                as Map<String, Object?>)
            .sdrEmbed,
        isTrue);
    final effective = EffectiveVideoRouteOptions.resolve(application: requested);
    expect(effective.sdrEmbed, isTrue);
    expect(
        effective.origins['sdrEmbed'], VideoRouteOptionOrigin.application);
    // An explicit open-level false overrides the application declaration;
    // an unset open layer inherits it.
    final overridden = EffectiveVideoRouteOptions.resolve(
        application: requested,
        openOverride: const VideoRouteOptions(sdrEmbed: false));
    expect(overridden.sdrEmbed, isFalse);
    expect(
        overridden.origins['sdrEmbed'], VideoRouteOptionOrigin.openOverride);
    final inherited = EffectiveVideoRouteOptions.resolve(
        application: requested, openOverride: const VideoRouteOptions());
    expect(inherited.sdrEmbed, isTrue);
    // The declaration participates in requested equality and the key.
    expect(requested, isNot(const VideoRouteOptions()));
    expect(const VideoRouteOptions(sdrEmbed: false).key,
        isNot(const VideoRouteOptions().key));
  });

  test('sdrEmbed fromMap accepts absent and boolean spellings only', () {
    expect(VideoRouteOptions.fromMap(const {}).sdrEmbed, isNull);
    expect(VideoRouteOptions.fromMap({'sdrEmbed': null}).sdrEmbed, isNull);
    expect(VideoRouteOptions.fromMap({'sdrEmbed': true}).sdrEmbed, isTrue);
    expect(VideoRouteOptions.fromMap({'sdrEmbed': false}).sdrEmbed, isFalse);
    expect(() => VideoRouteOptions.fromMap({'sdrEmbed': 'true'}),
        throwsFormatException);
    expect(() => VideoRouteOptions.fromMap({'sdrEmbed': 1}),
        throwsFormatException);
  });
}
