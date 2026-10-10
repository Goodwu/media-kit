import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'package:media_kit_video/src/video_controller/android_video_controller/real.dart';

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

  Map<Object?, Object?> report(
    bool applied,
    String path,
    String readback, {
    String transfer = 'pq',
  }) =>
      <Object?, Object?>{
        'applied': applied,
        'path': path,
        'requested': transfer,
        'readback': readback,
      };

  test('LYA default convert still requests PQ full over the channel', () async {
    const capabilities = HdrCapabilities(
        sdkInt: 29,
        displayHdrTypes: {2},
        hevcDecoders: [],
        dolbyVisionDecoders: [],
        p5PipelineAvailable: true,
        dataSpaceBridgeLoaded: true,
        dataSpaceExt: HdrDataSpaceExtInfo(id: 'lya-pq', applicable: true));
    final route = HdrStrategyRealizer.realize(HdrStrategy.baseLayerConvert,
            source: const HdrSourceDescriptor(transfer: 'hlg'),
            sourceClass: HdrSourceClass.hlg,
            capabilities: capabilities)
        .route!;
    handler = (call) {
      expect(call.arguments['transfer'], 'pq');
      return report(true, 'ext:lya-pq', 'DATASPACE_BT2020_PQ');
    };
    final result = await AndroidVideoController.invokeApplyDataSpace(
        handle: 7, transfer: route.surfaceTransfer!);
    expect(calls, hasLength(1));
    expect(result!['requested'], 'pq');
  });
  group('AndroidVideoController.invokeApplyDataSpace', () {
    test('ndk path: outgoing arguments and parsed report', () async {
      handler = (MethodCall call) async {
        expect(call.method, 'PlatformVideoView.ApplyDataSpace');
        expect(call.arguments['handle'], '7');
        expect(call.arguments['transfer'], 'pq');
        return report(true, 'ndk', 'DATASPACE_BT2020_PQ');
      };

      final result = await AndroidVideoController.invokeApplyDataSpace(
        handle: 7,
        transfer: 'pq',
      );

      expect(calls.single.method, 'PlatformVideoView.ApplyDataSpace');
      expect(result, isNotNull);
      expect(result!['applied'], isTrue);
      expect(result['path'], 'ndk');
      expect(result['requested'], 'pq');
      expect(result['readback'], 'DATASPACE_BT2020_PQ');
    });

    test('ext path carries the extension id in the path', () async {
      handler = (MethodCall call) async =>
          report(true, 'ext:lya-pq', 'DATASPACE_BT2020_PQ', transfer: 'pq');

      final result = await AndroidVideoController.invokeApplyDataSpace(
        handle: 7,
        transfer: 'pq',
      );

      expect(result!['applied'], isTrue);
      expect(result['path'], 'ext:lya-pq');
      expect(result['readback'], 'DATASPACE_BT2020_PQ');
      expect(result['requested'], 'pq');
    });

    test('surfaceControl path with HLG readback', () async {
      handler = (MethodCall call) async => report(
            true,
            'surfaceControl',
            'DATASPACE_BT2020_HLG',
            transfer: 'hlg',
          );

      final result = await AndroidVideoController.invokeApplyDataSpace(
        handle: 7,
        transfer: 'hlg',
      );

      expect(result!['applied'], isTrue);
      expect(result['path'], 'surfaceControl');
      expect(result['requested'], 'hlg');
      expect(result['readback'], 'DATASPACE_BT2020_HLG');
    });

    test('none path when the application fails or no surface is live',
        () async {
      handler = (MethodCall call) async => report(
            false,
            'none',
            'none',
            transfer: 'pq',
          );

      final result = await AndroidVideoController.invokeApplyDataSpace(
        handle: 7,
        transfer: 'pq',
      );

      expect(result!['applied'], isFalse);
      expect(result['path'], 'none');
      expect(result['requested'], 'pq');
      expect(result['readback'], 'none');
    });

    test('every successful branch reports all four fields', () async {
      final branches = <Map<Object?, Object?>>[
        report(true, 'ndk', 'DATASPACE_BT2020_PQ'),
        report(true, 'ext:lya-pq', 'DATASPACE_BT2020_PQ'),
        report(true, 'surfaceControl', 'DATASPACE_BT2020_HLG', transfer: 'hlg'),
      ];
      for (final branch in branches) {
        handler = (MethodCall call) async => branch;
        final result = await AndroidVideoController.invokeApplyDataSpace(
          handle: 1,
          transfer: branch['requested'] as String,
        );
        expect(result, isNotNull);
        expect(
            result!.keys,
            containsAll(<String>[
              'applied',
              'path',
              'requested',
              'readback',
            ]));
        expect(result['applied'], isA<bool>());
        expect(result['path'], isA<String>());
        expect(result['requested'], isA<String>());
        expect(result['readback'], isA<String>());
        expect(result['path'], isNot(''));
      }
    });

    test('a null reply (channel error suppressed upstream) parses to null',
        () async {
      handler = (MethodCall call) async => null;

      final result = await AndroidVideoController.invokeApplyDataSpace(
        handle: 7,
        transfer: 'pq',
      );

      expect(result, isNull);
    });
  });
}
