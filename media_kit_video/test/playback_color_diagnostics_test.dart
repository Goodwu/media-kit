import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit_video/src/diagnostics/playback_color_diagnostics.dart';

Map<String, String> properties({String vo = 'mediacodec_embed'}) => {
      'path': 'https://example.test/video.mp4',
      'current-tracks/video/id': '1',
      'current-vo': vo,
      'hwdec-current': 'mediacodec',
      'video-params/pixelformat': 'mediacodec',
      'video-params/primaries': 'bt.709',
      'video-params/gamma': 'bt.1886',
      'current-tracks/video/demux-color-primaries': 'bt2020',
      'current-tracks/video/demux-color-transfer': 'arib-std-b67',
      'current-tracks/video/demux-color-matrix': 'bt2020nc',
      'current-tracks/video/demux-color-range': 'tv',
      'video-target-params/primaries': 'bt.2020',
      'video-target-params/gamma': 'pq',
      'video-target-params/colormatrix': 'rgb',
      'video-target-params/colorlevels': 'full',
    };

void main() {
  testWidgets('native passthrough keeps demux color and does not read target',
      (tester) async {
    final data = properties();
    final reads = <String>[];
    final samples = <PlaybackColorSnapshot>[];
    final sampler = PlaybackColorSampler(
      readProperty: (property) async {
        reads.add(property);
        return data[property] ?? '';
      },
      sourceIdentity: () => 1,
      onSample: samples.add,
    );
    sampler.start();
    await tester.pump();
    sampler.dispose();
    expect(samples, hasLength(1));
    final sample = samples.single;
    expect(sample.source.primaries, 'bt.2020');
    expect(sample.source.transfer, 'hlg');
    expect(sample.source.matrix, 'bt.2020-ncl');
    expect(sample.source.range, 'limited');
    expect(sample.decoderPassthrough, isTrue);
    expect(sample.outputTarget.hasValues, isFalse);
    expect(reads.any((p) => p.startsWith('video-target-params/')), isFalse);
    expect(reads, isNot(contains('video-params/gamma')));
  });

  testWidgets('GPU target is separate and source stays identical',
      (tester) async {
    final data = properties(vo: 'gpu-next');
    final samples = <PlaybackColorSnapshot>[];
    final sampler = PlaybackColorSampler(
      readProperty: (property) async => data[property] ?? '',
      sourceIdentity: () => 1,
      onSample: samples.add,
    );
    sampler.start();
    await tester.pump();
    sampler.dispose();
    final sample = samples.single;
    expect(sample.source.transfer, 'hlg');
    expect(sample.outputTarget.transfer, 'pq');
    expect(sample.outputTarget.matrix, 'rgb');
    expect(sample.outputTarget.range, 'full');
    expect(sample.decoderPassthrough, isFalse);
  });

  test('unknown and missing color fields stay absent without inference', () {
    final sample = PlaybackColorValues.fromProperties({
      'source/primaries': 'unspecified',
      'source/transfer': 'bt709',
      'source/matrix': 'auto',
      'source/range': 'unknown',
    }, prefix: 'source', source: true);
    expect(sample.primaries, isNull);
    expect(sample.transfer, 'bt709');
    expect(sample.matrix, isNull);
    expect(sample.range, isNull);
    expect(sample.hasValues, isTrue);
    for (final invalid in [
      '',
      '?',
      'none',
      'null',
      'unknown',
      '-1',
      'invalid key'
    ]) {
      final values = PlaybackColorValues.fromProperties({
        'target/primaries': invalid,
      }, prefix: 'target');
      expect(values.hasValues, isFalse, reason: invalid);
    }
  });

  testWidgets('missing source metadata still permits observed passthrough',
      (tester) async {
    final data = properties()
      ..removeWhere((key, _) => key.startsWith('current-tracks/video/demux-'));
    final samples = <PlaybackColorSnapshot>[];
    final sampler = PlaybackColorSampler(
      readProperty: (property) async {
        if (property.endsWith('demux-color-range')) throw StateError('old mpv');
        return data[property] ?? '';
      },
      sourceIdentity: () => 1,
      onSample: samples.add,
    );
    sampler.start();
    await tester.pump();
    sampler.dispose();
    expect(samples.single.source.hasValues, isFalse);
    expect(samples.single.decoderPassthrough, isTrue);
  });

  testWidgets('copy decoding is not decoder passthrough or a GPU target',
      (tester) async {
    final data = properties()..['hwdec-current'] = 'mediacodec-copy';
    final samples = <PlaybackColorSnapshot>[];
    final sampler = PlaybackColorSampler(
      readProperty: (property) async => data[property] ?? '',
      sourceIdentity: () => 1,
      onSample: samples.add,
    );
    sampler.start();
    await tester.pump();
    sampler.dispose();
    expect(samples.single.decoderPassthrough, isFalse);
    expect(samples.single.outputTarget.hasValues, isFalse);
  });

  testWidgets('reload of same URI invalidates an in-flight source sample',
      (tester) async {
    var epoch = 1;
    final data = properties();
    final pending = Completer<String>();
    final samples = <PlaybackColorSnapshot>[];
    final sampler = PlaybackColorSampler(
      readProperty: (property) async {
        if (property.endsWith('demux-color-transfer')) return pending.future;
        return data[property] ?? '';
      },
      sourceIdentity: () => epoch,
      onSample: samples.add,
    );
    sampler.start();
    await tester.pump();
    epoch++;
    pending.complete('arib-std-b67');
    await tester.pump();
    sampler.dispose();
    expect(samples, isEmpty);
  });

  testWidgets('active output change clears a mixed-stage snapshot',
      (tester) async {
    final data = properties();
    var voReads = 0;
    final samples = <PlaybackColorSnapshot>[];
    final sampler = PlaybackColorSampler(
      readProperty: (property) async {
        if (property == 'current-vo' && voReads++ > 0) return 'gpu-next';
        return data[property] ?? '';
      },
      sourceIdentity: () => 1,
      onSample: samples.add,
    );
    sampler.start();
    await tester.pump();
    sampler.dispose();
    expect(samples.single.hasValues, isFalse);
  });

  testWidgets(
      'timeout keeps serial guard across stop/start and ignores late data',
      (tester) async {
    final pending = Completer<String>();
    var reads = 0;
    final samples = <PlaybackColorSnapshot>[];
    final sampler = PlaybackColorSampler(
      readProperty: (_) {
        reads++;
        return pending.future;
      },
      sourceIdentity: () => 1,
      onSample: samples.add,
    );
    sampler.start();
    await tester.pump(const Duration(seconds: 1));
    expect(samples.single.hasValues, isFalse);
    sampler.stop();
    sampler.start();
    await tester.pump(const Duration(seconds: 3));
    expect(reads, 1);
    pending.complete('late');
    await tester.pump();
    sampler.dispose();
    expect(samples, hasLength(1));
  });

  testWidgets('dispose drops a pending result and does not restart',
      (tester) async {
    final pending = Completer<String>();
    var reads = 0;
    final samples = <PlaybackColorSnapshot>[];
    final sampler = PlaybackColorSampler(
      readProperty: (_) {
        reads++;
        return pending.future;
      },
      sourceIdentity: () => 1,
      onSample: samples.add,
    );
    sampler.start();
    sampler.dispose();
    pending.complete('late');
    await tester.pump();
    sampler.start();
    await tester.pump(const Duration(seconds: 2));
    expect(reads, 1);
    expect(samples, isEmpty);
  });
}
