import 'package:flutter_test/flutter_test.dart';

import 'package:media_kit_video/src/hdr/hdr_capabilities.dart';

void main() {
  Map<Object?, Object?>? snapshot;
  setUp(() => snapshot = null);

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
    'dataSpaceExt': <Object?, Object?>{'id': 'lya-pq', 'isApplicable': true},
  };

  group('HdrCapabilities value parsing', () {
    test('parses a complete snapshot with HEVC decoder and extension', () {
      snapshot = fullSnapshot();
      final HdrCapabilities caps = HdrCapabilities.parseSnapshot(snapshot);

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

    test('parses a Dolby Vision decoder with profiles, no main10 key', () {
      snapshot = <Object?, Object?>{
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

      final HdrCapabilities caps = HdrCapabilities.parseSnapshot(snapshot);

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

    test('missing keys degrade to no-report defaults', () {
      snapshot = <Object?, Object?>{'sdkInt': 29};

      final HdrCapabilities caps = HdrCapabilities.parseSnapshot(snapshot);

      expect(caps.displayHdrTypes, isNull);
      expect(caps.hevcDecoders, isEmpty);
      expect(caps.dolbyVisionDecoders, isEmpty);
      expect(caps.dataSpaceBridgeLoaded, isFalse);
      expect(caps.dataSpaceExt, isNull);
    });

    test('a null capability report yields displayHdrTypes == null', () {
      snapshot = <Object?, Object?>{'sdkInt': 29, 'displayHdrTypes': null};

      final HdrCapabilities caps = HdrCapabilities.parseSnapshot(snapshot);

      expect(caps.displayHdrTypes, isNull);
    });

    test('malformed displayHdrTypes yields displayHdrTypes == null', () {
      // Non-int entries.
      snapshot = <Object?, Object?>{
        'displayHdrTypes': <Object?>[2, '3'],
      };
      HdrCapabilities caps = HdrCapabilities.parseSnapshot(snapshot);
      expect(caps.displayHdrTypes, isNull);

      // Non-list value.
      snapshot = <Object?, Object?>{'displayHdrTypes': 2};
      caps = HdrCapabilities.parseSnapshot(snapshot);
      expect(caps.displayHdrTypes, isNull);
    });

    test('an empty list is a valid "no HDR types" report, not null', () {
      snapshot = <Object?, Object?>{'displayHdrTypes': <Object?>[]};

      final HdrCapabilities caps = HdrCapabilities.parseSnapshot(snapshot);

      expect(caps.displayHdrTypes, <int>{});
    });

    test('an unregistered extension parses to null', () {
      snapshot = <Object?, Object?>{'dataSpaceExt': null};

      final HdrCapabilities caps = HdrCapabilities.parseSnapshot(snapshot);

      expect(caps.dataSpaceExt, isNull);
    });

    test('a missing channel reply is tolerated (null snapshot)', () {
      snapshot = null;

      final HdrCapabilities caps = HdrCapabilities.parseSnapshot(snapshot);

      expect(caps.displayHdrTypes, isNull);
      expect(caps.dataSpaceBridgeLoaded, isFalse);
    });
  });

  group('HdrCapabilities.parseSnapshot P5 pipeline field', () {
    test('snapshot p5Pipeline true means available', () {
      snapshot = <Object?, Object?>{'sdkInt': 29, 'p5Pipeline': true};

      final HdrCapabilities caps = HdrCapabilities.parseSnapshot(snapshot);

      expect(caps.p5PipelineAvailable, isTrue);
    });

    test('snapshot p5Pipeline false means unavailable', () {
      snapshot = <Object?, Object?>{'sdkInt': 29, 'p5Pipeline': false};

      final HdrCapabilities caps = HdrCapabilities.parseSnapshot(snapshot);

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
      final HdrCapabilities caps = HdrCapabilities.parseSnapshot(
        <Object?, Object?>{'sdkInt': 29},
      );
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
        0,
      );
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

  group('HdrCapabilities runtime probe value', () {
    test(
      'parsing without a Player is authoritative: the native probe verdict in '
      'the snapshot is used',
      () {
        snapshot = fullSnapshot();

        final HdrCapabilities caps = HdrCapabilities.parseSnapshot(snapshot);

        expect(caps.sdkInt, 29);
        expect(caps.displayHdrTypes, <int>{2, 3});
        // Core new capability of plan B: no Player is required — the P5
        // verdict comes from the disposable mpv instance probe cached at
        // engine attach, so query() is authoritative without a player.
        expect(caps.p5PipelineAvailable, isTrue);
        expect(caps.dataSpaceBridgeLoaded, isTrue);
        expect(caps.dataSpaceExt?.id, 'lya-pq');
      },
    );

    test('parsing without a Player reports p5PipelineAvailable false for a '
        'non-fork libmpv', () {
      snapshot = <Object?, Object?>{
        'sdkInt': 29,
        'displayHdrTypes': <Object?>[2, 3],
        // Upstream (non-fork) libmpv has no such property: the native
        // probe answers 0 (unavailable, a verdict — not an error).
        'p5Pipeline': false,
      };

      final HdrCapabilities caps = HdrCapabilities.parseSnapshot(snapshot);

      expect(caps.p5PipelineAvailable, isFalse);
    });
  });

  group('HdrDataSpaceExtInfo per-transfer capability fields', () {
    // The LYA vendor self-report shape (LyaPqDataSpaceExt): validated
    // prediction for pq, no setter-only exception, no YUV arm protocol.
    Map<Object?, Object?> lyaReport() => <Object?, Object?>{
          'id': 'lya-pq',
          'isApplicable': true,
          'validatedPredictionTransfers': <Object?>['pq'],
          'supportedSurfaceTransfers': <Object?>['pq'],
        };

    // The LG vendor self-report shape (LgPqDataSpaceExt): setter-only for
    // pq and pq-itu, the managed YUV arm protocol 1, no validated
    // prediction.
    Map<Object?, Object?> lgReport() => <Object?, Object?>{
          'id': 'lg-pq',
          'isApplicable': true,
          'setterOnlyTransfers': <Object?>['pq', 'pq-itu'],
          'supportedSurfaceTransfers': <Object?>['pq', 'pq-itu'],
          'yuvWindowArmApi': 1,
        };

    test('parses the LYA-shaped self-report', () {
      final HdrDataSpaceExtInfo? ext = HdrDataSpaceExtInfo.fromMap(lyaReport());
      expect(ext, isNotNull);
      expect(ext!.validatedPredictionTransfers, <String>{'pq'});
      expect(ext.setterOnlyTransfers, isEmpty);
      expect(ext.supportedSurfaceTransfers, <String>{'pq'});
      expect(ext.yuvWindowArmApi, 0);
    });

    test('parses the LG-shaped self-report', () {
      final HdrDataSpaceExtInfo? ext = HdrDataSpaceExtInfo.fromMap(lgReport());
      expect(ext, isNotNull);
      expect(ext!.validatedPredictionTransfers, isEmpty);
      expect(ext.setterOnlyTransfers, <String>{'pq', 'pq-itu'});
      expect(ext.supportedSurfaceTransfers, <String>{'pq', 'pq-itu'});
      expect(ext.yuvWindowArmApi, 1);
    });

    test('a legacy report without the fields resolves every field to the '
        'conservative default', () {
      final HdrDataSpaceExtInfo? ext = HdrDataSpaceExtInfo.fromMap(
          <Object?, Object?>{'id': 'legacy', 'isApplicable': true});
      expect(ext, isNotNull);
      expect(ext!.validatedPredictionTransfers, isEmpty);
      expect(ext.setterOnlyTransfers, isEmpty);
      expect(ext.supportedSurfaceTransfers, isEmpty);
      expect(ext.yuvWindowArmApi, 0);
    });

    test('malformed field types degrade to the conservative defaults, never '
        'to an admission', () {
      final HdrDataSpaceExtInfo? ext = HdrDataSpaceExtInfo.fromMap(
          <Object?, Object?>{
        'id': 'weird',
        'isApplicable': true,
        'validatedPredictionTransfers': 'pq',
        'setterOnlyTransfers': <Object?>['pq', 1],
        'supportedSurfaceTransfers': <Object?>[2],
        'yuvWindowArmApi': '1',
      });
      expect(ext, isNotNull);
      expect(ext!.validatedPredictionTransfers, isEmpty);
      expect(ext.setterOnlyTransfers, isEmpty);
      expect(ext.supportedSurfaceTransfers, isEmpty);
      expect(ext.yuvWindowArmApi, 0);
    });

    test('a non-positive yuvWindowArmApi is not a protocol declaration', () {
      final HdrDataSpaceExtInfo? ext = HdrDataSpaceExtInfo.fromMap(
          <Object?, Object?>{'id': 'x', 'yuvWindowArmApi': 0});
      expect(ext!.yuvWindowArmApi, 0);
      final negative = HdrDataSpaceExtInfo.fromMap(
          <Object?, Object?>{'id': 'x', 'yuvWindowArmApi': -1});
      expect(negative!.yuvWindowArmApi, 0);
    });

    test('the full snapshot carries the fields through parseSnapshot', () {
      snapshot = fullSnapshot()
        ..['dataSpaceExt'] = lgReport();
      final HdrCapabilities caps = HdrCapabilities.parseSnapshot(snapshot);
      expect(caps.dataSpaceExt!.setterOnlyTransfers, <String>{'pq', 'pq-itu'});
      expect(caps.dataSpaceExt!.yuvWindowArmApi, 1);
    });
  });
}
