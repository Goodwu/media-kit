import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:media_kit_video/src/hdr/hdr_capabilities.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel channel = MethodChannel(
    'com.alexmercerind/media_kit_video',
  );

  final List<MethodCall> calls = <MethodCall>[];
  Object? Function(MethodCall call)? handler;

  setUp(() {
    calls.clear();
    handler = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      calls.add(call);
      return handler?.call(call);
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    HdrCapabilities.propertyReader = null;
  });

  Map<Object?, Object?> fullSnapshot() => <Object?, Object?>{
        'sdkInt': 29,
        'displayHdrTypes': <Object?>[2, 3],
        'hevcDecoders': <Object?>[
          <Object?, Object?>{
            'name': 'OMX.hisi.video.decoder.hevc',
            'mimeType': 'video/hevc',
            'hardwareAcceleration': true,
            'main10': true,
            'profiles': <Object?>[2, 65536],
            'widthRange': <Object?>[16, 4096],
            'heightRange': <Object?>[16, 4096],
            'frameRateRange': <Object?>[8, 240],
            'supports4K': true,
            'max4KFps': 59.94,
          },
        ],
        'dolbyVisionDecoders': <Object?>[],
        'dataSpaceBridgeLoaded': true,
        'dataSpaceExt': <Object?, Object?>{
          'id': 'lya-pq',
          'isApplicable': true,
        },
      };

  group('HdrCapabilities.query (channel parsing)', () {
    test('parses a complete snapshot with HEVC decoder and extension', () async {
      handler = (MethodCall call) async {
        expect(call.method, 'HdrCapabilities.Get');
        return fullSnapshot();
      };
      // Positive P5 probe: the option name comes back non-empty.
      final HdrCapabilities caps =
          await HdrCapabilities.queryWith((String property) async {
        expect(property, HdrCapabilities.p5ProbeProperty);
        return 'dovi-p5-fast-path';
      });

      expect(calls.single.method, 'HdrCapabilities.Get');
      expect(caps.sdkInt, 29);
      expect(caps.displayHdrTypes, <int>{2, 3});
      expect(caps.hevcDecoders, hasLength(1));
      final HdrDecoderInfo hevc = caps.hevcDecoders.single;
      expect(hevc.name, 'OMX.hisi.video.decoder.hevc');
      expect(hevc.mimeType, 'video/hevc');
      expect(hevc.hardwareAcceleration, isTrue);
      expect(hevc.main10, isTrue);
      expect(hevc.profiles, <int>[2, 65536]);
      expect(hevc.widthRange, <int>[16, 4096]);
      expect(hevc.heightRange, <int>[16, 4096]);
      expect(hevc.frameRateRange, <int>[8, 240]);
      expect(hevc.supports4K, isTrue);
      expect(hevc.max4KFps, 59.94);
      expect(caps.dolbyVisionDecoders, isEmpty);
      expect(caps.p5PipelineAvailable, isTrue);
      expect(caps.dataSpaceBridgeLoaded, isTrue);
      expect(caps.dataSpaceExt?.id, 'lya-pq');
      expect(caps.dataSpaceExt?.applicable, isTrue);
    });

    test('parses a Dolby Vision decoder with profiles, no main10 key', () async {
      handler = (MethodCall call) async => <Object?, Object?>{
            'sdkInt': 34,
            'displayHdrTypes': <Object?>[1, 2, 3],
            'hevcDecoders': <Object?>[],
            'dolbyVisionDecoders': <Object?>[
              <Object?, Object?>{
                'name': 'c2.dolby.decoder',
                'mimeType': 'video/dolby-vision',
                'hardwareAcceleration': true,
                'profiles': <Object?>[4, 8],
                'supports4K': true,
                'max4KFps': 60,
              },
            ],
          };

      final HdrCapabilities caps = await HdrCapabilities.queryWith(
          (String property) async => '');

      expect(caps.displayHdrTypes, <int>{1, 2, 3});
      expect(caps.dolbyVisionDecoders, hasLength(1));
      final HdrDecoderInfo dv = caps.dolbyVisionDecoders.single;
      expect(dv.name, 'c2.dolby.decoder');
      expect(dv.mimeType, 'video/dolby-vision');
      expect(dv.profiles, <int>[4, 8]);
      expect(dv.main10, isNull);
      expect(dv.supports4K, isTrue);
      expect(dv.max4KFps, 60.0);
    });

    test('missing keys degrade to no-report defaults', () async {
      handler = (MethodCall call) async => <Object?, Object?>{'sdkInt': 29};

      final HdrCapabilities caps = await HdrCapabilities.queryWith(
          (String property) async => '');

      expect(caps.displayHdrTypes, isNull);
      expect(caps.hevcDecoders, isEmpty);
      expect(caps.dolbyVisionDecoders, isEmpty);
      expect(caps.dataSpaceBridgeLoaded, isFalse);
      expect(caps.dataSpaceExt, isNull);
    });

    test('a null capability report yields displayHdrTypes == null', () async {
      handler = (MethodCall call) async => <Object?, Object?>{
            'sdkInt': 29,
            'displayHdrTypes': null,
          };

      final HdrCapabilities caps = await HdrCapabilities.queryWith(
          (String property) async => '');

      expect(caps.displayHdrTypes, isNull);
    });

    test('malformed displayHdrTypes yields displayHdrTypes == null', () async {
      // Non-int entries.
      handler = (MethodCall call) async => <Object?, Object?>{
            'displayHdrTypes': <Object?>[2, '3'],
          };
      HdrCapabilities caps = await HdrCapabilities.queryWith(
          (String property) async => '');
      expect(caps.displayHdrTypes, isNull);

      // Non-list value.
      handler = (MethodCall call) async => <Object?, Object?>{
            'displayHdrTypes': 2,
          };
      caps = await HdrCapabilities.queryWith((String property) async => '');
      expect(caps.displayHdrTypes, isNull);
    });

    test('an empty list is a valid "no HDR types" report, not null', () async {
      handler = (MethodCall call) async => <Object?, Object?>{
            'displayHdrTypes': <Object?>[],
          };

      final HdrCapabilities caps = await HdrCapabilities.queryWith(
          (String property) async => '');

      expect(caps.displayHdrTypes, <int>{});
    });

    test('an unregistered extension parses to null', () async {
      handler = (MethodCall call) async => <Object?, Object?>{
            'dataSpaceExt': null,
          };

      final HdrCapabilities caps = await HdrCapabilities.queryWith(
          (String property) async => '');

      expect(caps.dataSpaceExt, isNull);
    });

    test('a missing channel reply is tolerated (null snapshot)', () async {
      handler = (MethodCall call) async => null;

      final HdrCapabilities caps = await HdrCapabilities.queryWith(
          (String property) async => '');

      expect(caps.displayHdrTypes, isNull);
      expect(caps.dataSpaceBridgeLoaded, isFalse);
    });
  });

  group('HdrCapabilities P5 pipeline probe (injected property reader)', () {
    test('non-empty option name means available', () async {
      expect(
        await HdrCapabilities.detectP5Pipeline(
            (String property) async => 'dovi-p5-fast-path'),
        isTrue,
      );
    });

    test('empty property result means unavailable', () async {
      expect(
        await HdrCapabilities.detectP5Pipeline((String property) async => ''),
        isFalse,
      );
    });

    test('a property read failure means unavailable', () async {
      Future<String> fail(String property) async {
        throw StateError('property unavailable');
      }

      expect(await HdrCapabilities.detectP5Pipeline(fail), isFalse);
    });

    test('whitespace-only option name means unavailable', () async {
      expect(
        await HdrCapabilities.detectP5Pipeline(
            (String property) async => '  '),
        isFalse,
      );
    });

    test('query reports p5PipelineAvailable false for a non-fork libmpv',
        () async {
      handler = (MethodCall call) async => fullSnapshot();

      // Upstream (non-fork) libmpv has no such option: the property read
      // comes back empty.
      final HdrCapabilities caps = await HdrCapabilities.queryWith(
          (String property) async => '');

      expect(caps.p5PipelineAvailable, isFalse);
    });
  });

  group('HdrCapabilities.query without a player', () {
    test('query(player: null) reads the channel and conservatively reports '
        'p5PipelineAvailable false', () async {
      handler = (MethodCall call) async {
        expect(call.method, 'HdrCapabilities.Get');
        return fullSnapshot();
      };

      final HdrCapabilities caps = await HdrCapabilities.query(player: null);

      // The Android snapshot is still fetched through the plugin channel.
      expect(calls.single.method, 'HdrCapabilities.Get');
      expect(caps.sdkInt, 29);
      expect(caps.displayHdrTypes, <int>{2, 3});
      // No player means no mpv option probe: the P5 pipeline is treated as
      // missing (the safe direction), regardless of what the fork carries.
      expect(caps.p5PipelineAvailable, isFalse);
      expect(caps.dataSpaceBridgeLoaded, isTrue);
      expect(caps.dataSpaceExt?.id, 'lya-pq');
    });
  });
}
