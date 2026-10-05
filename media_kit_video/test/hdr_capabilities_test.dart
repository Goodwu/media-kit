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
        'p5Pipeline': true,
        'nativeDvBridgeApi': 1,
        'dataSpaceBridgeLoaded': true,
        'dataSpaceExt': <Object?, Object?>{
          'id': 'lya-pq',
          'isApplicable': true,
        },
      };

  group('HdrCapabilities.query (channel parsing)', () {
    test('parses a complete snapshot with HEVC decoder and extension',
        () async {
      handler = (MethodCall call) async {
        expect(call.method, 'HdrCapabilities.Get');
        return fullSnapshot();
      };
      final HdrCapabilities caps = await HdrCapabilities.queryWith();

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
      expect(caps.nativeDvBridgeApi, 1);
      expect(caps.nativeDvBridgeSupported, isTrue);
      expect(caps.dataSpaceBridgeLoaded, isTrue);
      expect(caps.dataSpaceExt?.id, 'lya-pq');
      expect(caps.dataSpaceExt?.applicable, isTrue);
    });

    test('parses a Dolby Vision decoder with profiles, no main10 key',
        () async {
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

      final HdrCapabilities caps = await HdrCapabilities.queryWith();

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

      final HdrCapabilities caps = await HdrCapabilities.queryWith();

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

      final HdrCapabilities caps = await HdrCapabilities.queryWith();

      expect(caps.displayHdrTypes, isNull);
    });

    test('malformed displayHdrTypes yields displayHdrTypes == null', () async {
      // Non-int entries.
      handler = (MethodCall call) async => <Object?, Object?>{
            'displayHdrTypes': <Object?>[2, '3'],
          };
      HdrCapabilities caps = await HdrCapabilities.queryWith();
      expect(caps.displayHdrTypes, isNull);

      // Non-list value.
      handler = (MethodCall call) async => <Object?, Object?>{
            'displayHdrTypes': 2,
          };
      caps = await HdrCapabilities.queryWith();
      expect(caps.displayHdrTypes, isNull);
    });

    test('an empty list is a valid "no HDR types" report, not null', () async {
      handler = (MethodCall call) async => <Object?, Object?>{
            'displayHdrTypes': <Object?>[],
          };

      final HdrCapabilities caps = await HdrCapabilities.queryWith();

      expect(caps.displayHdrTypes, <int>{});
    });

    test('an unregistered extension parses to null', () async {
      handler = (MethodCall call) async => <Object?, Object?>{
            'dataSpaceExt': null,
          };

      final HdrCapabilities caps = await HdrCapabilities.queryWith();

      expect(caps.dataSpaceExt, isNull);
    });

    test('a missing channel reply is tolerated (null snapshot)', () async {
      handler = (MethodCall call) async => null;

      final HdrCapabilities caps = await HdrCapabilities.queryWith();

      expect(caps.displayHdrTypes, isNull);
      expect(caps.dataSpaceBridgeLoaded, isFalse);
    });
  });

  group('HdrCapabilities.parseSnapshot P5 pipeline field', () {
    test('snapshot p5Pipeline true means available', () async {
      handler = (MethodCall call) async => <Object?, Object?>{
            'sdkInt': 29,
            'p5Pipeline': true,
          };

      final HdrCapabilities caps = await HdrCapabilities.queryWith();

      expect(caps.p5PipelineAvailable, isTrue);
    });

    test('snapshot p5Pipeline false means unavailable', () async {
      handler = (MethodCall call) async => <Object?, Object?>{
            'sdkInt': 29,
            'p5Pipeline': false,
          };

      final HdrCapabilities caps = await HdrCapabilities.queryWith();

      expect(caps.p5PipelineAvailable, isFalse);
    });

    test('a missing p5Pipeline key falls back to the fallback argument', () {
      final HdrCapabilities caps = HdrCapabilities.parseSnapshot(
        <Object?, Object?>{'sdkInt': 29},
        p5PipelineAvailable: true,
      );
      expect(caps.p5PipelineAvailable, isTrue);

      final HdrCapabilities absentFalse = HdrCapabilities.parseSnapshot(
        <Object?, Object?>{'sdkInt': 29},
        p5PipelineAvailable: false,
      );
      expect(absentFalse.p5PipelineAvailable, isFalse);
    });

    test('a missing p5Pipeline key and no argument degrade to false', () {
      final HdrCapabilities caps =
          HdrCapabilities.parseSnapshot(<Object?, Object?>{'sdkInt': 29});
      expect(caps.p5PipelineAvailable, isFalse);
    });

    test('a non-bool p5Pipeline value degrades to false', () {
      final HdrCapabilities caps = HdrCapabilities.parseSnapshot(
        <Object?, Object?>{'p5Pipeline': 'true'},
      );
      expect(caps.p5PipelineAvailable, isFalse);
    });

    test('the snapshot field wins over the fallback argument', () {
      final HdrCapabilities snapshotTrue = HdrCapabilities.parseSnapshot(
        <Object?, Object?>{'p5Pipeline': true},
        p5PipelineAvailable: false,
      );
      expect(snapshotTrue.p5PipelineAvailable, isTrue);

      final HdrCapabilities snapshotFalse = HdrCapabilities.parseSnapshot(
        <Object?, Object?>{'p5Pipeline': false},
        p5PipelineAvailable: true,
      );
      expect(snapshotFalse.p5PipelineAvailable, isFalse);
    });

    test('a null snapshot degrades to false', () {
      final HdrCapabilities caps = HdrCapabilities.parseSnapshot(null);
      expect(caps.p5PipelineAvailable, isFalse);
    });
  });

  group('HdrCapabilities native DV bridge schema', () {
    test('older constructor callers default to no native bridge', () {
      const HdrCapabilities caps = HdrCapabilities(
        sdkInt: 24,
        displayHdrTypes: null,
        hevcDecoders: <HdrDecoderInfo>[],
        dolbyVisionDecoders: <HdrDecoderInfo>[],
        p5PipelineAvailable: true,
        dataSpaceBridgeLoaded: false,
        dataSpaceExt: null,
      );
      expect(caps.nativeDvBridgeApi, 0);
      expect(caps.nativeDvBridgeSupported, isFalse);
    });

    test('only an integer schema version 1 is supported', () {
      for (final Object? raw in <Object?>[
        null,
        true,
        false,
        1.0,
        '1',
        -1,
        0,
        2,
        100,
      ]) {
        final HdrCapabilities caps = HdrCapabilities.parseSnapshot(
          <Object?, Object?>{'nativeDvBridgeApi': raw},
        );
        expect(caps.nativeDvBridgeApi, 0, reason: 'raw=$raw');
        expect(caps.nativeDvBridgeSupported, isFalse, reason: 'raw=$raw');
      }
      expect(HdrCapabilities.parseSnapshot(null).nativeDvBridgeApi, 0);
      expect(
          HdrCapabilities.parseSnapshot(<Object?, Object?>{}).nativeDvBridgeApi,
          0);
    });

    for (final bool p5 in <bool>[false, true]) {
      for (final int api in <int>[0, 1]) {
        test('P5 rescale=$p5 and native DV API=$api remain independent', () {
          final HdrCapabilities caps = HdrCapabilities.parseSnapshot(
            <Object?, Object?>{'p5Pipeline': p5, 'nativeDvBridgeApi': api},
          );
          expect(caps.p5PipelineAvailable, p5);
          expect(caps.nativeDvBridgeApi, api);
          expect(caps.nativeDvBridgeSupported, api == 1);
        });
      }
    }
  });

  group('HdrCapabilities.query without a player', () {
    test(
        'query(player: null) is authoritative: the native probe verdict in '
        'the snapshot is used', () async {
      handler = (MethodCall call) async {
        expect(call.method, 'HdrCapabilities.Get');
        return fullSnapshot();
      };

      final HdrCapabilities caps = await HdrCapabilities.query(player: null);

      // The Android snapshot is still fetched through the plugin channel.
      expect(calls.single.method, 'HdrCapabilities.Get');
      expect(caps.sdkInt, 29);
      expect(caps.displayHdrTypes, <int>{2, 3});
      // Core new capability of plan B: no Player is required — the P5
      // verdict comes from the disposable mpv instance probe cached at
      // engine attach, so query() is authoritative without a player.
      expect(caps.p5PipelineAvailable, isTrue);
      expect(caps.dataSpaceBridgeLoaded, isTrue);
      expect(caps.dataSpaceExt?.id, 'lya-pq');
    });

    test(
        'query(player: null) reports p5PipelineAvailable false for a '
        'non-fork libmpv', () async {
      handler = (MethodCall call) async => <Object?, Object?>{
            'sdkInt': 29,
            'displayHdrTypes': <Object?>[2, 3],
            // Upstream (non-fork) libmpv has no such property: the native
            // probe answers 0 (unavailable, a verdict — not an error).
            'p5Pipeline': false,
          };

      final HdrCapabilities caps = await HdrCapabilities.query(player: null);

      expect(caps.p5PipelineAvailable, isFalse);
    });
  });
}
