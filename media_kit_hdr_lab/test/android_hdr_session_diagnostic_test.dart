import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:media_kit_hdr_lab/common/android_hdr_session_diagnostic.dart';

class _Fixture {
  _Fixture() {
    journal = AndroidHdrSessionDiagnostic(
        label: 'hdr10-fixture',
        readProperty: (name) async {
          expect(inLock, true);
          if (heldProperty == name) {
            propertyEntered?.complete();
            await propertyRelease!.future;
            heldProperty = null;
          }
          if (missing.contains(name)) throw StateError('missing:$name');
          return properties[name] ?? 'unknown';
        },
        readEpoch: () => epoch,
        readIdentity: () async {
          expect(inLock, true);
          identityReads++;
          return identityOverride?.call(identityReads) ?? identity;
        },
        withPlayerLock: (work) => serialize(() async {
              inLock = true;
              try {
                await work();
              } finally {
                inLock = false;
              }
            }),
        writeOverride: (payload) async {
          writes.add(payload);
          await onWrite?.call(payload);
        });
  }
  late final AndroidHdrSessionDiagnostic journal;
  Future<void> _lockTail = Future<void>.value();
  // Test-only queue stands in for the real Player lock injected by the page.
  Future<void> serialize(Future<void> Function() work) {
    final attempt = _lockTail.then((_) => work());
    _lockTail =
        attempt.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return attempt;
  }

  bool inLock = false;
  int epoch = 0;
  int identityReads = 0;
  String? heldProperty;
  Completer<void>? propertyEntered;
  Completer<void>? propertyRelease;
  final Set<String> missing = {};
  final Map<String, String> properties = {
    'path': '',
    'playlist/0/id': '',
    for (final name in androidHdr10RestoredProperties) name: 'original:$name',
    'vo': 'mediacodec_embed',
    'hwdec-current': 'mediacodec',
    'time-pos': '0',
    'duration': '30.097',
    'pause': 'no',
    'video-params': '{"gamma":"pq","primaries":"bt.2020"}',
    'video-out-params': '{"w":3840,"h":1920}',
    'android-mediacodec-info': '{"codec":"OMX.qcom.video.decoder.hevc"}',
  };
  final Map<String, Object?> identity = {
    'sessionIdentity': 5,
    'sessionInstanceId': 'session-1',
    'sessionGeneration': 1,
    'verified': true,
    'sourceOrigin': 'decoder',
    'source': {
      'transfer': 'pq',
      'primaries': 'bt.2020',
      'dvProfile': null,
      'dynamicMetadata': 'none'
    },
    'actual': {
      'strategy': 'baseLayerDirect',
      'presentation': 'nativeHdr',
      'transfer': 'pq',
      'topology': 'platformView',
      'vo': 'mediacodec_embed',
      'hwdec': 'mediacodec'
    },
    'boundOutput': {
      'bound': true,
      'videoControllerIdentity': 6,
      'platformControllerIdentity': 7,
      'handle': 8,
      'generation': 1,
      'viewId': 0,
      'surfaceGeneration': 1,
      'wid': 9
    },
    'playing': true,
    'completed': false,
    'buffering': false,
  };
  Map<String, Object?> Function(int reads)? identityOverride;
  final List<Map<String, Object?>> writes = [];
  Future<void> Function(Map<String, Object?>)? onWrite;
  final List<String> order = [];
  Future<void> prepare() async {
    await journal.captureBaseline();
    properties['path'] = androidHdr10DiagnosticSource;
    properties['playlist/0/id'] = '77';
    properties['hwdec'] = 'mediacodec';
    epoch = 2;
  }

  List<Map> get samples => (journal.snapshot()['rows'] as List)
      .cast<Map>()
      .where((r) => r['kind'] == 'sample')
      .toList();
  Future<void> finish(
          {bool clean = true, bool retired = true, bool restore = true}) =>
      journal.finish(
          disposeSession: () async {
            order.add('session-dispose');
            if (restore) {
              for (final name in androidHdr10RestoredProperties) {
                properties[name] = 'original:$name';
              }
            }
            properties['path'] = '';
          },
          sessionCleanupFacts: () =>
              {'sessionReportClean': clean, 'controllerRetired': retired},
          terminatePlayer: () async => order.add('player-terminate'));
}

void main() {
  test('fixed HDR10 admission rejects wrong platform/source/flags/label', () {
    String? admission(
            {bool android = true,
            bool transaction = true,
            List<String> sources = const [androidHdr10DiagnosticSource],
            String label = 'r',
            bool conflict = false}) =>
        validateAndroidHdr10Diagnostic(
            android: android,
            transaction: transaction,
            sources: sources,
            label: label,
            conflictingFlags: conflict);
    expect(admission(), null);
    expect(admission(android: false), isNotNull);
    expect(admission(transaction: false), isNotNull);
    expect(admission(sources: ['P5']), isNotNull);
    expect(admission(sources: [androidHdr10DiagnosticSource, 'second']),
        isNotNull);
    expect(admission(label: ''), isNotNull);
    expect(admission(conflict: true), isNotNull);
  });

  test('codec output text remains raw and does not claim input or HDR', () {
    final f = _Fixture();
    f.journal.recordCodecFormatLog(
        prefix: 'ffmpeg/video', level: 'v', text: 'unrelated frame output');
    f.journal.recordCodecFormatLog(
        prefix: 'ffmpeg/video',
        level: 'v',
        text: 'Output MediaFormat changed to {color-transfer=3}');
    final rows = (f.journal.snapshot()['rows'] as List).cast<Map>();
    expect(rows, hasLength(1));
    expect(rows.single['text'],
        'Output MediaFormat changed to {color-transfer=3}');
    expect(rows.single['scope'], contains('input configure format'));
    expect(f.journal.snapshot()['error'], isNull);
  });

  test('configure input log remains raw and separate from output', () {
    final f = _Fixture();
    const raw =
        'hdr10_config_input event=configure codec=OMX.qcom.video.decoder.hevc mime=video/hevc surface_present=1 status=0 input_available=1 input_truncated=0 input={width=3840}';
    f.journal
        .recordCodecFormatLog(prefix: 'ffmpeg/video', level: 'info', text: raw);
    f.journal.recordCodecFormatLog(
        prefix: 'ffmpeg/video',
        level: 'info',
        text: 'hdr10_config_input unrelated');
    final rows = (f.journal.snapshot()['rows'] as List).cast<Map>();
    expect(rows, hasLength(1));
    expect(rows.single['kind'], 'codec-input-format-log');
    expect(rows.single['text'], raw);
    expect(rows.single['scope'], contains('CSD/SEI'));
    expect(f.journal.snapshot()['error'], isNull);
  });

  test('original degradation survives later report replacement', () {
    final f = _Fixture();
    f.journal.recordEvent(const HdrDegradedEvent(1,
        reason: HdrDegradeReason.unsupportedStrategy,
        diagnostic: 'original native prepare failure'));
    f.journal.recordReport(const HdrOutputReport(
        generation: 1, diagnostic: 'later decoder mismatch'));
    final rows = (f.journal.snapshot()['rows'] as List).cast<Map>();
    expect(rows[0]['kind'], 'session-degradation');
    expect(rows[0]['generation'], 1);
    expect(rows[0]['reason'], 'unsupportedStrategy');
    expect(rows[0]['diagnostic'], 'original native prepare failure');
    expect(rows[1]['diagnostic'], 'later decoder mismatch');
    expect(f.journal.snapshot()['error'], isNull);
  });

  test('planning report and real decoder review remain distinct', () {
    final f = _Fixture();
    f.journal.recordReport(const HdrOutputReport(generation: 1));
    f.journal.recordReport(const HdrOutputReport(
        generation: 1,
        source: HdrSourceDescriptor(
            codec: 'hevc', transfer: 'pq', primaries: 'bt.2020'),
        sourceOrigin: HdrReportSource.decoder,
        verified: true,
        hwdecCurrent: 'mediacodec'));
    final rows = (f.journal.snapshot()['rows'] as List).cast<Map>();
    expect(rows[0]['reportPhase'], 'planning-or-unverified');
    expect(rows[0]['verified'], false);
    expect(rows[1]['reportPhase'], 'decoder-reviewed');
    expect(rows[1]['sourceOrigin'], 'decoder');
    expect(rows[1]['verificationScope'],
        contains('panel-and-visible-output-unverified'));
  });

  test(
      'stable locked sample binds source generation epoch output and native config',
      () async {
    final f = _Fixture();
    await f.prepare();
    await f.journal.sample();
    expect(f.samples.single['accepted'], true);
    expect(f.samples.single['nativeHdr10Configuration'], true);
    expect((f.samples.single['properties'] as Map)['video-params'],
        f.properties['video-params']);
    expect(f.inLock, false);
    await f.finish();
    expect(f.journal.closed, true);
    expect(f.journal.debt, false);
    expect(f.writes.last['closed'], true);
    expect(f.journal.snapshot()['sessionRestorationVerified'], true);
    expect(
        (f.journal.snapshot()['cleanup']
            as Map)['surfaceReleaseAcknowledgement'],
        'unverified');
  });

  for (final invalid in [
    'false-bound',
    'empty-output',
    'missing-tuple',
    'missing-controller',
    'missing-session'
  ]) {
    test('$invalid cannot become an accepted bound output', () async {
      final f = _Fixture();
      await f.prepare();
      switch (invalid) {
        case 'false-bound':
          (f.identity['boundOutput'] as Map)['bound'] = false;
        case 'empty-output':
          f.identity['boundOutput'] = <String, Object?>{};
        case 'missing-tuple':
          (f.identity['boundOutput'] as Map).remove('surfaceGeneration');
        case 'missing-controller':
          (f.identity['boundOutput'] as Map).remove('videoControllerIdentity');
        case 'missing-session':
          f.identity.remove('sessionIdentity');
      }
      await f.journal.sample();
      expect(f.samples.single['accepted'], false);
    });
  }

  for (final drift in [
    'generation',
    'session',
    'output',
    'epoch',
    'entry',
    'source'
  ]) {
    test('$drift drift rejects mixed observation and preserves endpoints',
        () async {
      final f = _Fixture();
      await f.prepare();
      f.identityOverride = (n) {
        if (n == 2) {
          switch (drift) {
            case 'generation':
              f.identity['sessionGeneration'] = 2;
            case 'session':
              f.identity['sessionIdentity'] = 44;
            case 'output':
              (f.identity['boundOutput'] as Map)['wid'] = 44;
            case 'epoch':
              f.epoch++;
            case 'entry':
              f.properties['playlist/0/id'] = '99';
            case 'source':
              f.properties['path'] = 'foreign';
          }
        }
        return f.identity;
      };
      // Identity-after must follow native properties; entry/source mutate on
      // the second property-read endpoint instead via the held read completion.
      if (drift == 'entry' || drift == 'source') {
        f.heldProperty = 'time-pos';
        f.propertyEntered = Completer<void>();
        f.propertyRelease = Completer<void>();
        final sample = f.journal.sample();
        await f.propertyEntered!.future;
        f.properties[drift == 'entry' ? 'playlist/0/id' : 'path'] =
            drift == 'entry' ? '99' : 'foreign';
        f.propertyRelease!.complete();
        await sample;
      } else {
        await f.journal.sample();
      }
      expect(f.samples.single['accepted'], false);
      expect(
          (f.samples.single['identityBefore'] as Map)['sessionGeneration'], 1);
    });
  }

  test('missing decoder property preserves its error without fabricating data',
      () async {
    final f = _Fixture();
    await f.prepare();
    f.missing.add('android-mediacodec-info');
    await f.journal.sample();
    final row = f.samples.single;
    expect((row['properties'] as Map).containsKey('android-mediacodec-info'),
        false);
    expect(
        (row['propertyErrors'] as Map)['android-mediacodec-info'], isA<Map>());
    expect(row['accepted'], true);
  });

  for (final invalid in [
    'Infinity',
    'NaN',
    '-1',
    'paused',
    'EOS',
    'buffering'
  ]) {
    test('$invalid cannot supply ten-second playback progress support',
        () async {
      final f = _Fixture();
      await f.prepare();
      f.properties['time-pos'] = '0';
      await f.journal.sample();
      if (invalid == 'paused') {
        f.properties['pause'] = 'yes';
        f.identity['playing'] = false;
      } else if (invalid == 'EOS') {
        f.identity['completed'] = true;
      } else if (invalid == 'buffering') {
        f.identity['buffering'] = true;
      } else {
        f.properties['time-pos'] = invalid;
      }
      if (['paused', 'EOS', 'buffering'].contains(invalid)) {
        f.properties['time-pos'] = '12';
      }
      await f.journal.sample();
      expect(
          (f.journal.snapshot()['progressSupport']
              as Map)['tenSecondsPositionAdvance'],
          false);
    });
  }

  test('ten-second same-segment position support is explicit and finite',
      () async {
    final f = _Fixture();
    await f.prepare();
    await f.journal.sample();
    f.properties['time-pos'] = '12';
    await f.journal.sample();
    final support = f.journal.snapshot()['progressSupport'] as Map;
    expect(support['tenSecondsPositionAdvance'], true);
    expect(
        support['scope'], contains('visible output and smoothness unverified'));
    f.epoch++;
    await f.journal.sample();
    expect(f.samples.last['accepted'], false);
  });

  for (final replacement in ['session', 'surface']) {
    test(
        'stable $replacement replacement at same generation cannot merge progress',
        () async {
      final f = _Fixture();
      await f.prepare();
      await f.journal.sample();
      f.properties['time-pos'] = '12';
      if (replacement == 'session') {
        f.identity['sessionIdentity'] = 44;
      } else {
        (f.identity['boundOutput'] as Map)['surfaceGeneration'] = 2;
      }
      await f.journal.sample();
      expect(f.samples.first['accepted'], true);
      expect(f.samples.last['accepted'], false);
      expect(
          (f.journal.snapshot()['progressSupport']
              as Map)['tenSecondsPositionAdvance'],
          false);
      expect(f.samples.last['epochBefore'], f.samples.first['epochBefore']);
      expect((f.samples.last['identityBefore'] as Map)['sessionGeneration'], 1);
    });
  }

  test('Close drains a live property read and final write before completing',
      () async {
    final f = _Fixture();
    await f.prepare();
    f.heldProperty = 'time-pos';
    f.propertyEntered = Completer<void>();
    f.propertyRelease = Completer<void>();
    final sampling = f.journal.sample();
    await f.propertyEntered!.future;
    final writeEntered = Completer<void>();
    final writeRelease = Completer<void>();
    f.onWrite = (payload) async {
      if (payload['closed'] == true) {
        writeEntered.complete();
        await writeRelease.future;
      }
    };
    final closing = f.finish();
    await Future<void>.delayed(Duration.zero);
    expect(f.order, isEmpty);
    expect(f.journal.samplingAllowed, false);
    f.propertyRelease!.complete();
    await sampling;
    await writeEntered.future;
    expect(f.order, ['session-dispose', 'player-terminate']);
    expect(f.journal.closed, false);
    writeRelease.complete();
    await closing;
    expect(f.journal.closed, true);
  });

  for (final failure in ['restore', 'report', 'retained-controller']) {
    test('$failure refuses clean exit after actual Player termination',
        () async {
      final f = _Fixture();
      await f.prepare();
      await expectLater(
          f.finish(
              restore: failure != 'restore',
              clean: failure != 'report',
              retired: failure != 'retained-controller'),
          throwsStateError);
      expect(f.order.last, 'player-terminate');
      expect(f.journal.debt, true);
      expect(f.writes.last['sessionRestorationVerified'], false);
    });
  }

  test(
      'first persistence error remains debt even when final publication succeeds',
      () async {
    final f = _Fixture();
    await f.prepare();
    var fail = true;
    f.onWrite = (_) async {
      if (fail) {
        fail = false;
        throw StateError('original-write');
      }
    };
    await expectLater(f.journal.sample(), throwsStateError);
    await expectLater(f.finish(), throwsStateError);
    expect(f.journal.snapshot()['error'], contains('original-write'));
    expect(f.writes.last['debt'], true);
  });

  test(
      'failed final publication never marks in-process closure verified or retries cleanup',
      () async {
    final f = _Fixture();
    await f.prepare();
    f.onWrite = (payload) async {
      if (payload['closed'] == true) throw StateError('final-write');
    };
    await expectLater(f.finish(), throwsStateError);
    expect(f.journal.closed, false);
    expect(f.journal.debt, true);
    expect(f.journal.snapshot()['finalWriteSucceededInProcess'], false);
    await expectLater(f.finish(), throwsStateError);
    expect(f.order, ['session-dispose', 'player-terminate']);
  });

  test('truncated identity rejects the same sample and reports gap overflow',
      () async {
    final f = _Fixture();
    await f.prepare();
    for (var i = 0; i < 70; i++) {
      f.identity['oversized-$i'] = 'x' * 5000;
    }
    await f.journal.sample();
    final snapshot = f.journal.snapshot();
    expect(f.samples.single['accepted'], false);
    expect(f.samples.single['nativeHdr10Configuration'], false);
    expect((snapshot['evidenceGaps'] as List).length, 64);
    expect(snapshot['evidenceGapsOverflow'], true);
  });

  test('bounded reports retain explicit row and gap overflow', () {
    final f = _Fixture();
    for (var i = 0; i < 300; i++) {
      f.journal
          .recordReport(HdrOutputReport(generation: i, diagnostic: 'x' * 5000));
    }
    final snapshot = f.journal.snapshot();
    expect((snapshot['rows'] as List).length, androidHdr10DiagnosticMaxRows);
    expect(snapshot['evidenceGaps'], contains('rows-overflow'));
    expect(f.journal.samplingAllowed, false);
  });
}
