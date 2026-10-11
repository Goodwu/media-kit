import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit_video/src/routing/video_output_target.dart';
import 'package:media_kit_video/src/routing/video_route_capabilities.dart';
import 'package:media_kit_video/src/routing/video_source_spec.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.alexmercerind/media_kit_video');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final source = VideoSourceSpec(
      codec: 'hvc1.2.4.L153.B0',
      width: 3840,
      height: 2160,
      frameRate: 60,
      bitDepth: 10);

  Map<String, Object?> response(List<VideoSourceSpec> specs,
          {String displayStatus = 'resolved',
          String support = 'supported',
          bool complete = true}) =>
      <String, Object?>{
        'schema': 1,
        'platform': 'android',
        'display': <String, Object?>{
          'status': displayStatus,
          'platform': 'android',
          'displayId': 7,
          'modeId': 2,
          'revision': '7:2',
          'hdrTypes': <int>[2]
        },
        'hdr': <String, Object?>{
          'sdkInt': 34,
          'displayHdrTypes': <int>[1, 2, 3],
          'hevcDecoders': <Object?>[],
          'dolbyVisionDecoders': <Object?>[],
          'p5Pipeline': true
        },
        'sources': [
          for (final spec in specs)
            <String, Object?>{
              'key': spec.key,
              'censusComplete': complete,
              'reason': 'systemDeclarations',
              'decoders': <Object?>[
                <String, Object?>{
                  'name': 'vendor.hevc',
                  'mime': 'video/hevc',
                  'kind': 'hardware',
                  'support': support,
                  'reason': 'test',
                  'path': 'codec'
                }
              ],
            }
        ],
      };

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('no Player and no target: device query includes the exact source',
      () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return response([source], displayStatus: 'notRequested');
    });
    final caps = await VideoRouteCapabilities.query(sources: [source]);
    expect(calls.single.method, 'VideoRouteCapabilities.Get');
    final args = calls.single.arguments as Map;
    expect(args.containsKey('player'), isFalse);
    expect(args.containsKey('handle'), isFalse);
    expect(args['target'], isNull);
    expect((args['sources'] as List).single, source.toMap());
    expect(caps.display.resolved, isFalse);
    expect(caps.hdr.displayHdrTypes, isNull);
    expect(caps.hdr.p5PipelineAvailable, isTrue);
    expect(caps.forSource(source).support(), VideoSupport.supported);
  });

  test(
      'explicit OS display target is namespaced; legacy default cannot override it',
      () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect((call.arguments as Map)['target'],
          {'kind': 'nativeDisplay', 'platform': 'android', 'displayId': 7});
      return response([]);
    });
    final caps = await VideoRouteCapabilities.query(
        target:
            VideoOutputTarget.nativeDisplay(platform: 'android', displayId: 7));
    expect(caps.display.displayId, 7);
    expect(caps.hdr.displayHdrTypes, {2});
  });

  test('unresolved target never inherits default-display HDR', () async {
    messenger.setMockMethodCallHandler(
        channel, (_) async => response([], displayStatus: 'unresolved'));
    final caps = await VideoRouteCapabilities.query(
        target: const VideoOutputTarget.defaultDisplay());
    expect(caps.hdr.displayHdrTypes, isNull);
    expect(caps.display.resolved, isFalse);
  });

  test('changing size, fps, depth, profile, level or bitrate changes identity',
      () {
    final values = [
      VideoSourceSpec(codec: 'hevc', width: 1920, height: 1080, frameRate: 30),
      VideoSourceSpec(codec: 'hevc', width: 3840, height: 1080, frameRate: 30),
      VideoSourceSpec(codec: 'hevc', width: 1920, height: 2160, frameRate: 30),
      VideoSourceSpec(codec: 'hevc', width: 1920, height: 1080, frameRate: 60),
      VideoSourceSpec(
          codec: 'hevc',
          width: 1920,
          height: 1080,
          frameRate: 30,
          bitDepth: 10),
      VideoSourceSpec(
          codec: 'hevc', width: 1920, height: 1080, frameRate: 30, profile: 2),
      VideoSourceSpec(
          codec: 'hevc', width: 1920, height: 1080, frameRate: 30, level: 153),
      VideoSourceSpec(
          codec: 'hevc',
          width: 1920,
          height: 1080,
          frameRate: 30,
          highTier: true),
      VideoSourceSpec(
          codec: 'hevc',
          width: 1920,
          height: 1080,
          frameRate: 30,
          bitrate: 1000000),
    ];
    expect(values.toSet(), hasLength(values.length));
    expect(VideoSourceSpec(codec: ' HEVC '), VideoSourceSpec(codec: 'hevc'));
  });

  test('DASH rates preserve fractions and missing/invalid values', () {
    expect(VideoSourceSpec.parseFrameRate('30000/1001'),
        closeTo(29.97002997, .00000001));
    expect(VideoSourceSpec.parseFrameRate('59.94'), 59.94);
    for (final value in [
      null,
      '',
      '0',
      '-1',
      '60/0',
      'NaN',
      'Infinity',
      '1/2/3'
    ]) {
      expect(VideoSourceSpec.parseFrameRate(value), isNull, reason: '$value');
    }
  });

  test('invalid specifications fail before any channel call', () {
    expect(() => VideoSourceSpec(codec: 'https://video.test/a'),
        throwsArgumentError);
    expect(() => VideoSourceSpec(codec: ''), throwsArgumentError);
    expect(() => VideoSourceSpec(codec: 'hevc', width: 0), throwsArgumentError);
    expect(
        () => VideoSourceSpec(codec: 'hevc', height: -1), throwsArgumentError);
    expect(
        () => VideoSourceSpec(codec: 'hevc', profile: -1), throwsArgumentError);
    expect(() => VideoSourceSpec(codec: 'hevc', bitDepth: 64),
        throwsArgumentError);
    expect(() => VideoSourceSpec(codec: 'hevc', frameRate: double.nan),
        throwsArgumentError);
    expect(() => VideoSourceSpec(codec: 'hevc', frameRate: double.infinity),
        throwsArgumentError);
  });

  test('batch deduplicates equal specs; result order is not assumed', () async {
    final other = VideoSourceSpec(
        codec: 'avc1.640028', width: 1920, height: 1080, frameRate: 60);
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect((call.arguments as Map)['sources'], hasLength(2));
      return response([other, source]);
    });
    final caps =
        await VideoRouteCapabilities.query(sources: [source, other, source]);
    expect(caps.sources, hasLength(2));
    expect(caps.forSource(other).source, other);
    expect(caps.forSource(VideoSourceSpec(codec: 'hevc')).support(),
        VideoSupport.unknown);
  });

  test('oversized iterable is bounded before native access', () async {
    var called = false;
    messenger.setMockMethodCallHandler(channel, (_) async {
      called = true;
      return response([]);
    });
    await expectLater(
        VideoRouteCapabilities.query(sources: List.filled(129, source)),
        throwsArgumentError);
    expect(called, isFalse);
  });

  test('unsupported is different from incomplete census and absent adapter',
      () async {
    messenger.setMockMethodCallHandler(
        channel, (_) async => response([source], support: 'unsupported'));
    expect(
        (await VideoRouteCapabilities.query(sources: [source]))
            .forSource(source)
            .support(),
        VideoSupport.unsupported);
    messenger.setMockMethodCallHandler(
        channel,
        (_) async =>
            response([source], support: 'unsupported', complete: false));
    expect(
        (await VideoRouteCapabilities.query(sources: [source]))
            .forSource(source)
            .support(),
        VideoSupport.unknown);
    messenger.setMockMethodCallHandler(
        channel, (_) async => throw MissingPluginException());
    final caps = await VideoRouteCapabilities.query(sources: [source]);
    expect(caps.platform, 'unavailable');
    expect(caps.forSource(source).support(), VideoSupport.unknown);
  });

  test('query failures do not reuse a previously successful snapshot',
      () async {
    messenger.setMockMethodCallHandler(
        channel, (_) async => response([source]));
    await VideoRouteCapabilities.query(sources: [source]);
    messenger.setMockMethodCallHandler(
        channel, (_) async => throw PlatformException(code: 'unavailable'));
    await expectLater(VideoRouteCapabilities.query(sources: [source]),
        throwsA(isA<PlatformException>()));
  });

  for (final malformed in [
    'null',
    'schema',
    'missing',
    'duplicate',
    'foreign',
    'enum'
  ]) {
    test('reject $malformed response instead of authorizing a source',
        () async {
      messenger.setMockMethodCallHandler(channel, (_) async {
        final raw = response([source]);
        if (malformed == 'null') return null;
        if (malformed == 'schema') raw['schema'] = 99;
        if (malformed == 'missing') raw['sources'] = [];
        if (malformed == 'duplicate')
          (raw['sources'] as List).add((raw['sources'] as List).first);
        if (malformed == 'foreign')
          ((raw['sources'] as List).first as Map)['key'] = 'foreign';
        if (malformed == 'enum')
          (((raw['sources'] as List).first as Map)['decoders'] as List)
              .first['support'] = 'maybe';
        return raw;
      });
      await expectLater(VideoRouteCapabilities.query(sources: [source]),
          throwsFormatException);
    });
  }

  test('source and decoder collections cannot be mutated', () async {
    messenger.setMockMethodCallHandler(
        channel, (_) async => response([source]));
    final caps = await VideoRouteCapabilities.query(sources: [source]);
    expect(
        () => caps.forSource(source).decoders.clear(), throwsUnsupportedError);
    expect(() => caps.display.hdrTypes!.clear(), throwsUnsupportedError);
  });

  test('hardware/software requirements do not accept unknown decoder kind', () {
    VideoSourceSupport result(VideoDecoderKind kind) => VideoSourceSupport(
            source: source,
            censusComplete: true,
            reason: 'test',
            decoders: [
              VideoDecoderSupport(
                  name: 'x',
                  mime: 'video/hevc',
                  kind: kind,
                  support: VideoSupport.supported,
                  reason: 'test',
                  path: 'codec')
            ]);
    expect(
        result(VideoDecoderKind.software)
            .support(kind: VideoDecoderKind.hardware),
        VideoSupport.unsupported);
    expect(
        result(VideoDecoderKind.unknown)
            .support(kind: VideoDecoderKind.hardware),
        VideoSupport.unknown);
    expect(
        result(VideoDecoderKind.hardware)
            .support(kind: VideoDecoderKind.hardware),
        VideoSupport.supported);
    expect(result(VideoDecoderKind.hardware).support(path: 'nativeDv'),
        VideoSupport.unsupported);
  });
}
