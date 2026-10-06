import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Rect;
import 'package:media_kit/media_kit.dart';

// ignore_for_file: depend_on_referenced_packages
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit_hdr_lab/common/android_native_dv_session_diagnostic.dart';
import 'package:media_kit_hdr_lab/common/android_native_dv_session_lifecycle.dart';
import 'package:media_kit_video/src/hdr/hdr_capabilities.dart';
import 'package:media_kit_video/src/hdr/android_mediacodec_configuration.dart';
import 'package:media_kit_video/src/hdr/hdr_native_dv_option_owner.dart'
    show HdrOptionSourceIdentity;
import 'package:media_kit_video/src/hdr/hdr_native_dv_review_evidence.dart';
import 'package:media_kit_video/src/hdr/hdr_disposal.dart'
    show HdrDisposalReport;
import 'package:media_kit_video/src/hdr/hdr_output_report.dart';
import 'package:media_kit_video/src/hdr/hdr_output_event.dart';
import 'package:media_kit_video/src/hdr/hdr_video_session.dart';
import 'package:media_kit_video/src/hdr/hdr_output_policy.dart'
    show HdrMediaKind;
import 'package:media_kit_video/src/hdr/hdr_route.dart';
import 'package:media_kit_video/src/hdr/hdr_route_planner.dart';
import 'package:media_kit_video/src/hdr/hdr_source_descriptor.dart';
import 'package:media_kit_video/src/hdr/hdr_strategy.dart';
import 'package:media_kit_video/src/video_controller/android_video_controller/android_video_controller.dart';
import 'package:media_kit_video/src/video_controller/android_video_controller/platform_surface_release.dart'
    show AndroidSurfaceAccountId;
import 'package:media_kit_video/src/video_controller/platform_video_controller.dart';
import 'package:media_kit_video/src/video_controller/video_controller.dart';
import 'package:synchronized/synchronized.dart';

void main() {
  group('Session native DV diagnostic admission', () {
    test('terminal during a periodic read accepts one EOS row and stops',
        () async {
      final segment = AndroidNativeDvSessionSamplingSegment();
      final read = Completer<void>();
      var propertyReads = 0;
      final rows = <bool>[];
      final periodic = segment.sample(
          terminal: false,
          operation: (_) async {
            propertyReads++;
            await read.future;
            final eos = segment.terminalObserved;
            rows.add(eos);
            return eos;
          });
      expect(propertyReads, 1);
      await segment.sample(
          terminal: true,
          operation: (_) async {
            propertyReads++;
            return true;
          });
      read.complete();
      await periodic;
      await segment.sample(
          terminal: false,
          operation: (_) async {
            propertyReads++;
            return false;
          });
      expect(rows, [true]);
      expect(propertyReads, 1);
      expect(segment.terminalRowAccepted, isTrue);
    });

    test('property completion past original deadline is rejected', () async {
      final player = _SlowPropertyPlayer();
      final recorder = AndroidNativeDvSessionDiagnostic(
        player: player,
        durationSeconds: 1,
        intervalSeconds: 1,
        externalIdentityLabel: 'test',
      )..startSamplingClockForTesting();
      await expectLater(
        recorder.readPropertyForTesting('path'),
        throwsA(isA<TimeoutException>()),
      );
      await recorder.close();
    });

    test('close drains current property and admits no subsequent read',
        () async {
      final player = _ControlledPropertyPlayer();
      final recorder = AndroidNativeDvSessionDiagnostic(
        player: player,
        durationSeconds: 10,
        intervalSeconds: 1,
        externalIdentityLabel: 'test',
      )..startSamplingClockForTesting();
      final batch = () async {
        await recorder.readPropertyForTesting('first');
        await recorder.readPropertyForTesting('second');
      }();
      expect(player.names, ['first']);
      final closing = recorder.close();
      player.first.complete('settled');
      await expectLater(batch, throwsA(isA<StateError>()));
      await closing;
      expect(player.names, ['first']);
    });

    test('requires the fixed single source, Session mode and external label',
        () {
      expect(
        validateAndroidNativeDvSessionDiagnosticAdmission(
          android: true,
          hdrTransaction: true,
          rawReleaseDiagnostic: false,
          sources: [androidNativeDvSessionDiagnosticSource],
          identityLabel: 'lg-session-candidate',
        ),
        isNull,
      );
      final invalid = [
        validateAndroidNativeDvSessionDiagnosticAdmission(
          android: false,
          hdrTransaction: true,
          rawReleaseDiagnostic: false,
          sources: [androidNativeDvSessionDiagnosticSource],
          identityLabel: 'x',
        ),
        validateAndroidNativeDvSessionDiagnosticAdmission(
          android: true,
          hdrTransaction: false,
          rawReleaseDiagnostic: false,
          sources: [androidNativeDvSessionDiagnosticSource],
          identityLabel: 'x',
        ),
        validateAndroidNativeDvSessionDiagnosticAdmission(
          android: true,
          hdrTransaction: true,
          rawReleaseDiagnostic: true,
          sources: [androidNativeDvSessionDiagnosticSource],
          identityLabel: 'x',
        ),
        validateAndroidNativeDvSessionDiagnosticAdmission(
          android: true,
          hdrTransaction: true,
          rawReleaseDiagnostic: false,
          sources: ['/tmp/other.mp4'],
          identityLabel: 'x',
        ),
        validateAndroidNativeDvSessionDiagnosticAdmission(
          android: true,
          hdrTransaction: true,
          rawReleaseDiagnostic: false,
          sources: [androidNativeDvSessionDiagnosticSource],
          identityLabel: ' ',
        ),
      ];
      expect(invalid, everyElement(isNotNull));
    });

    test('bounds duration to 1..300 seconds and interval to 1..30', () {
      expect(validateAndroidNativeDvSessionDiagnosticSeconds(1), 1);
      expect(validateAndroidNativeDvSessionDiagnosticSeconds(300), 300);
      expect(validateAndroidNativeDvSessionDiagnosticInterval(1), 1);
      expect(validateAndroidNativeDvSessionDiagnosticInterval(30), 30);
      expect(() => validateAndroidNativeDvSessionDiagnosticSeconds(0),
          throwsRangeError);
      expect(() => validateAndroidNativeDvSessionDiagnosticSeconds(301),
          throwsRangeError);
      expect(() => validateAndroidNativeDvSessionDiagnosticInterval(31),
          throwsRangeError);
    });

    test(
        'source identity rejects foreign entry and only allows terminal path clearing',
        () {
      expect(
          androidNativeDvSessionIdentityMatches(
            expectedPath: androidNativeDvSessionDiagnosticSource,
            actualPath: androidNativeDvSessionDiagnosticSource,
            expectedEntryId: '41',
            actualEntryId: '41',
            expectedEpoch: 7,
            actualEpoch: 7,
            terminalObserved: false,
          ),
          isTrue);
      expect(
          androidNativeDvSessionIdentityMatches(
            expectedPath: androidNativeDvSessionDiagnosticSource,
            actualPath: '',
            expectedEntryId: '41',
            actualEntryId: '41',
            expectedEpoch: 7,
            actualEpoch: 7,
            terminalObserved: true,
          ),
          isTrue);
      expect(
          androidNativeDvSessionIdentityMatches(
            expectedPath: androidNativeDvSessionDiagnosticSource,
            actualPath: '',
            expectedEntryId: '41',
            actualEntryId: '41',
            expectedEpoch: 7,
            actualEpoch: 7,
            terminalObserved: false,
          ),
          isFalse);
      expect(
          androidNativeDvSessionIdentityMatches(
            expectedPath: androidNativeDvSessionDiagnosticSource,
            actualPath: androidNativeDvSessionDiagnosticSource,
            expectedEntryId: '41',
            actualEntryId: '42',
            expectedEpoch: 7,
            actualEpoch: 7,
            terminalObserved: true,
          ),
          isFalse);
      expect(
          androidNativeDvSessionIdentityMatches(
            expectedPath: androidNativeDvSessionDiagnosticSource,
            actualPath: '',
            expectedEntryId: '41',
            actualEntryId: '41',
            expectedEpoch: 7,
            actualEpoch: 8,
            terminalObserved: true,
          ),
          isFalse);
    });

    test('post-dispose baseline mismatch or read failure blocks Session reuse',
        () async {
      final baseline = _idleProperties();
      final report = const HdrDisposalReport(
        coordinatorError: null,
        playerError: null,
        directoryError: null,
        retainedDirectory: null,
      );
      final run = AndroidNativeDvSessionLifecycleRun(
        durationSeconds: 900,
        externalIdentityLabel: 'test-candidate',
        writeOverride: (_) async {},
      );
      final changed = Map<String, String>.from(baseline)
        ..['hwdec'] = 'mediacodec-copy';
      final changedDiagnostic = AndroidNativeDvSessionDiagnostic(
        player: _PropertyDiagnosticPlayer(changed),
        durationSeconds: 300,
        intervalSeconds: 5,
        externalIdentityLabel: 'test-candidate',
        lifecycleRun: run,
      )..setInitialIdleBaselineForTesting(
          properties: baseline,
          fileLoadedEpoch: 5,
        );
      final changedResult = await changedDiagnostic.capturePostSessionCleanup(
        report: report,
        sessionDisposeError: null,
      );
      expect(changedResult, isFalse);
      expect(changedDiagnostic.cleanupVerifiedForTesting, isFalse);
      expect(run.debt, isTrue);
      expect(
        androidNativeDvSessionReuseAdmitted(
          disposeReportClean: report.clean,
          actualRestorationVerified: changedResult,
          lifecycleDebt: run.debt,
        ),
        isFalse,
      );
      await run.close();

      final readRun = AndroidNativeDvSessionLifecycleRun(
        durationSeconds: 900,
        externalIdentityLabel: 'test-candidate',
        writeOverride: (_) async {},
      );
      final readDiagnostic = AndroidNativeDvSessionDiagnostic(
        player: _PropertyDiagnosticPlayer(baseline, failProperty: 'vo'),
        durationSeconds: 300,
        intervalSeconds: 5,
        externalIdentityLabel: 'test-candidate',
        lifecycleRun: readRun,
      )..setInitialIdleBaselineForTesting(
          properties: baseline,
          fileLoadedEpoch: 5,
        );
      final readResult = await readDiagnostic.capturePostSessionCleanup(
        report: report,
        sessionDisposeError: null,
      );
      expect(readResult, isFalse);
      expect(readRun.debt, isTrue);
      expect(
        androidNativeDvSessionReuseAdmitted(
          disposeReportClean: report.clean,
          actualRestorationVerified: readResult,
          lifecycleDebt: readRun.debt,
        ),
        isFalse,
      );
      await readRun.close();
    });

    test('healthy restored idle baseline admits same-Player Session reuse',
        () async {
      final baseline = _idleProperties();
      final report = const HdrDisposalReport(
        coordinatorError: null,
        playerError: null,
        directoryError: null,
        retainedDirectory: null,
      );
      final run = AndroidNativeDvSessionLifecycleRun(
        durationSeconds: 900,
        externalIdentityLabel: 'test-candidate',
        writeOverride: (_) async {},
      );
      final diagnostic = AndroidNativeDvSessionDiagnostic(
        player: _PropertyDiagnosticPlayer(baseline),
        durationSeconds: 300,
        intervalSeconds: 5,
        externalIdentityLabel: 'test-candidate',
        lifecycleRun: run,
      )..setInitialIdleBaselineForTesting(
          properties: baseline,
          fileLoadedEpoch: 4,
        );
      final restored = await diagnostic.capturePostSessionCleanup(
        report: report,
        sessionDisposeError: null,
      );
      expect(restored, isTrue);
      expect(run.debt, isFalse);
      expect(
        androidNativeDvSessionReuseAdmitted(
          disposeReportClean: report.clean,
          actualRestorationVerified: restored,
          lifecycleDebt: run.debt,
        ),
        isTrue,
      );
      await run.close();
    });

    test('SDR configuration rejection persists active expected evidence',
        () async {
      final fixture = _sdrDiagnosticFixture(overrides: const {
        'hwdec': 'mediacodec',
      });
      await fixture.diagnostic.sampleLifecycleSegmentForTesting();

      expect(fixture.run.debt, isTrue);
      expect(fixture.run.rows, isEmpty);
      final segment = fixture.run.segments.single;
      expect(segment['endReason'], 'identity-or-sampling-error');
      expect(segment['rowCount'], 0);
      final error = segment['error'] as String;
      final prefix = 'SDR_CONFIGURATION_REJECTED:';
      final evidence =
          jsonDecode(error.substring(error.indexOf(prefix) + prefix.length))
              as Map<String, Object?>;
      expect(evidence['kind'], 'sdr-configuration-rejection-v1');
      expect(evidence['routeApplied'], {
        'route': 'sdrDirect',
        'generation': 1,
      });
      expect(evidence['codecRaw'], contains('video/avc'));
      expect(evidence['codecRawTruncated'], isFalse);
      expect(evidence['codecParsed'], {
        'mime': 'video/avc',
        'codec': 'OMX.test',
        'nativeDvActive': false,
      });
      expect((evidence['actualProperties'] as Map)['hwdec-current'],
          'mediacodec-copy');
      expect((evidence['activeExpected'] as Map)['hwdec'], 'mediacodec-copy');
      expect((evidence['activeExpected'] as Map)['hwdecCurrent'],
          'mediacodec-copy');
      expect((evidence['activeExpected'] as Map)['vo'], 'gpu-next');
      expect((evidence['cleanupIdleExpected'] as Map)['hwdec'], 'no');
      expect((evidence['cleanupIdleExpected'] as Map)['hwdec-current'], '');
      expect(
        (evidence['failedConditions'] as Map)['hwdecDiffersFromActiveExpected'],
        isTrue,
      );
      expect(
        evidence['failedConditionNames'],
        contains('hwdecDiffersFromActiveExpected'),
      );
      expect(evidence['sourceBefore'], {
        'path': androidNativeDvSessionLifecycleSdrPath,
        'entryId': '41',
        'epoch': 7,
      });
      expect(evidence['sourceAfter'], evidence['sourceBefore']);
      expect(evidence['outputBindingBefore'], evidence['outputBindingAfter']);
      expect(evidence['sample'], {
        'timePosSeconds': 1.0,
        'durationSeconds': 120.0,
        'pause': 'no',
      });
      expect(error.length, lessThan(8192));
      await fixture.diagnostic.close(cleanup: 'test complete');
      await fixture.run.close();
    });

    test('SDR rejection codec evidence is bounded and marks truncation',
        () async {
      final rawCodec = '{"api":1,"mime":"video/avc","codec":"OMX.test",'
          '"native-dv-active":false,"padding":"${'x' * 3000}"}';
      final fixture = _sdrDiagnosticFixture(
        overrides: <String, String>{
          'android-mediacodec-info': rawCodec,
          'vd-lavc-o': 'native_dv=1,timed',
        },
      );
      await fixture.diagnostic.sampleLifecycleSegmentForTesting();

      final error = fixture.run.segments.single['error'] as String;
      final prefix = 'SDR_CONFIGURATION_REJECTED:';
      final evidence =
          jsonDecode(error.substring(error.indexOf(prefix) + prefix.length))
              as Map<String, Object?>;
      expect(evidence['codecRaw'], hasLength(2048));
      expect(evidence['codecRawTruncated'], isTrue);
      expect(evidence['truncatedFields'], contains('codecRaw'));
      expect(evidence['codecParsed'], {
        'mime': 'video/avc',
        'codec': 'OMX.test',
        'nativeDvActive': false,
      });
      expect(fixture.run.debt, isTrue);
      expect(fixture.run.rows, isEmpty);
      await fixture.diagnostic.close(cleanup: 'test complete');
      await fixture.run.close();
    });

    test('R4 active SDR AVC route produces a sample row', () async {
      final fixture = _sdrDiagnosticFixture();
      await fixture.diagnostic.sampleLifecycleSegmentForTesting();

      expect(fixture.run.debt, isFalse);
      expect(fixture.run.rows, hasLength(1));
      expect(fixture.run.segments.single['rowCount'], 1);
      expect(fixture.run.segments.single['error'], isNull);
      await fixture.diagnostic.close(cleanup: 'test complete');
      await fixture.run.close();
    });

    test('SDR active hwdec, current hwdec, and vo must match typed route',
        () async {
      for (final property in const <String>[
        'hwdec',
        'hwdec-current',
        'vo',
      ]) {
        final fixture = _sdrDiagnosticFixture(overrides: <String, String>{
          property: property == 'vo' ? 'mediacodec_embed' : 'mediacodec',
        });
        await fixture.diagnostic.sampleLifecycleSegmentForTesting();
        expect(fixture.run.debt, isTrue, reason: property);
        expect(fixture.run.rows, isEmpty, reason: property);
        final error = fixture.run.segments.single['error'] as String;
        expect(error, contains('SDR_CONFIGURATION_REJECTED:'),
            reason: property);
        await fixture.diagnostic.close(cleanup: 'test complete');
        await fixture.run.close();
      }
    });

    test('SDR applied route must match the fixed typed Texture plan', () async {
      final wrongRoutes = <String, HdrRoute>{
        'strategy': _copySdrRoute(strategy: HdrStrategy.toneMapSdr),
        'route': _copySdrRoute(hwdec: 'mediacodec'),
        'topology': _copySdrRoute(topology: HdrTopology.platformView),
      };
      for (final entry in wrongRoutes.entries) {
        final fixture = _sdrDiagnosticFixture(
          typedRoute: entry.value,
          appliedTypedRoute: entry.value,
        );
        await fixture.diagnostic.sampleLifecycleSegmentForTesting();
        expect(fixture.run.debt, isTrue, reason: entry.key);
        expect(fixture.run.rows, isEmpty, reason: entry.key);
        expect(
          fixture.run.segments.single['error'],
          contains('SDR_CONFIGURATION_REJECTED:'),
          reason: entry.key,
        );
        await fixture.diagnostic.close(cleanup: 'test complete');
        await fixture.run.close();
      }
    });

    test('SDR applied and current typed routes must agree', () async {
      final fixture = _sdrDiagnosticFixture(
        typedRoute: _copySdrRoute(vo: 'wrong-output'),
        appliedTypedRoute: _copySdrRoute(),
      );
      await fixture.diagnostic.sampleLifecycleSegmentForTesting();
      expect(fixture.run.debt, isTrue);
      expect(fixture.run.rows, isEmpty);
      expect(fixture.run.segments.single['error'],
          contains('SDR_CONFIGURATION_REJECTED:'));
      await fixture.diagnostic.close(cleanup: 'test complete');
      await fixture.run.close();
    });

    test(
        'wrong typed SDR route evidence truncates long fields and dependencies',
        () async {
      final longValue = 'r' * 600;
      final longDependencies = <String>{
        for (var index = 0; index < 32; index++)
          'dependency-$index-${'d' * 400}',
      };
      final wrongRoute = _copySdrRoute(
        vo: longValue,
        hwdec: longValue,
        vdLavcOptions: longValue,
        targetTrc: longValue,
        dependencies: longDependencies,
      );
      final fixture = _sdrDiagnosticFixture(
        typedRoute: wrongRoute,
        appliedTypedRoute: wrongRoute,
      );
      await fixture.diagnostic.sampleLifecycleSegmentForTesting();

      expect(fixture.run.debt, isTrue);
      expect(fixture.run.rows, isEmpty);
      final error = fixture.run.segments.single['error'] as String;
      const prefix = 'SDR_CONFIGURATION_REJECTED:';
      final evidence = jsonDecode(
        error.substring(error.indexOf(prefix) + prefix.length),
      ) as Map<String, Object?>;
      final expected = evidence['activeExpected'] as Map;
      final dependencies = expected['dependencies'] as List;
      expect(expected['vo'], hasLength(128));
      expect(expected['hwdec'], hasLength(128));
      expect(expected['vdLavcOptions'], hasLength(128));
      expect(expected['targetTrc'], hasLength(128));
      expect(dependencies, hasLength(8));
      expect(
          dependencies.every((item) => (item as String).length <= 128), isTrue);
      expect(evidence['truncatedFields'], contains('activeExpected.vo'));
      expect(evidence['truncatedFields'], contains('activeExpected.hwdec'));
      expect(evidence['truncatedFields'],
          contains('activeExpected.vdLavcOptions'));
      expect(evidence['truncatedFields'], contains('activeExpected.targetTrc'));
      expect(
          evidence['truncatedFields'], contains('activeExpected.dependencies'));
      expect(evidence['truncatedFields'],
          contains('activeTypedRouteApplied.dependencies'));
      expect(error.length, lessThan(8192));

      await fixture.diagnostic.close(cleanup: 'test complete');
      await fixture.run.close();
    });

    test('SDR requires a named AVC codec with native DV inactive', () async {
      for (final override in const <Map<String, String>>[
        {'android-mediacodec-info': ''},
        {
          'android-mediacodec-info':
              '{"api":1,"mime":"video/hevc","codec":"OMX.test","native-dv-active":false}',
        },
        {
          'android-mediacodec-info':
              '{"api":1,"mime":"video/avc","codec":"","native-dv-active":false}',
        },
        {
          'android-mediacodec-info':
              '{"api":1,"mime":"video/avc","codec":"OMX.test","native-dv-active":true}',
        },
        {
          'android-mediacodec-info':
              '{"api":1,"mime":"video/avc","codec":"OMX.test"}',
        },
      ]) {
        final fixture = _sdrDiagnosticFixture(overrides: override);
        await fixture.diagnostic.sampleLifecycleSegmentForTesting();
        expect(fixture.run.debt, isTrue);
        expect(fixture.run.rows, isEmpty);
        await fixture.diagnostic.close(cleanup: 'test complete');
        await fixture.run.close();
      }
    });

    test(
        'SDR Texture sampling recovers from head Surface loss, then accepts row',
        () async {
      late _TextureAndroidOutput output;
      var bumpTextureGenerationOnDuration = false;
      final player = _PropertyDiagnosticPlayer(
        <String, String>{
          ..._idleProperties(),
          'path': androidNativeDvSessionLifecycleSdrPath,
          'playlist/0/id': '41',
          'android-mediacodec-info':
              '{"api":1,"mime":"video/avc","codec":"OMX.test","native-dv-active":false}',
          'hwdec': 'mediacodec-copy',
          'hwdec-current': 'mediacodec-copy',
          'vo': 'gpu-next',
          'mediacodec-embed-render-mode': 'boolean',
          'time-pos': '1.0',
          'duration': '120.0',
          'pause': 'no',
          'frame-drop-count': '0',
          'decoder-frame-drop-count': '0',
          'mistimed-frame-count': '0',
          'vo-delayed-frame-count': '0',
        },
        onRead: (name) {
          if (bumpTextureGenerationOnDuration && name == 'duration') {
            bumpTextureGenerationOnDuration = false;
            output.generation++;
          }
        },
      );
      player.fileLoadedEpoch = 7;
      final route = _copySdrRoute();
      output = _TextureAndroidOutput(
        player: player,
        textureId: 7,
        rect: const Rect.fromLTWH(0, 0, 1920, 1080),
        generation: 12,
      );
      final video = _TextureVideoController(player, output);
      video.id.value = null;
      video.rect.value = null;
      output.id.value = null;
      output.rect.value = null;
      final session = _DiagnosticSession(video, route);
      final run = AndroidNativeDvSessionLifecycleRun(
        durationSeconds: 900,
        externalIdentityLabel: 'test-candidate',
        writeOverride: (_) async {},
      );
      final diagnostic = AndroidNativeDvSessionDiagnostic(
        player: player,
        durationSeconds: 900,
        intervalSeconds: 5,
        externalIdentityLabel: 'test-candidate',
        lifecycleRun: run,
      )..setInitialIdleBaselineForTesting(
          properties: <String, String>{
            ..._idleProperties(),
            'mediacodec-embed-render-mode': 'boolean',
          },
          fileLoadedEpoch: 7,
        );

      Map<String, Object?> makeSegment(String id) {
        final record = run.beginSegment(
          segmentId: id,
          sessionInstanceId: 'session-1',
          generation: 1,
          expectedSource: androidNativeDvSessionLifecycleSdrPath,
          route: HdrStrategy.sdrDirect.name,
          actionId: 'P5SDRP5',
          requestId: id,
          routeApplied: const {'generation': 1, 'route': 'sdrDirect'},
        );
        return <String, Object?>{
          'record': record,
          'segmentId': id,
          'sessionInstanceId': 'session-1',
          'generation': 1,
          'expectedSource': androidNativeDvSessionLifecycleSdrPath,
          'route': HdrStrategy.sdrDirect,
          'appliedTypedRoute': route,
          'proof': null,
          'entryId': '41',
          'epoch': 7,
          'identity': null,
        };
      }

      final lostSurface = makeSegment('sdr-head-lost');
      diagnostic.bindLifecycleSegmentForTesting(
        session: session,
        sessionInstanceId: 'session-1',
        segment: lostSurface,
      );
      await diagnostic.sampleLifecycleSegmentForTesting();
      expect(run.debt, isFalse,
          reason: 'expected lifecycle Surface loss is recoverable');
      expect(run.segments.first['endReason'], 'surface-drift');
      expect(run.rows, isEmpty);

      video.id.value = 7;
      video.rect.value = const Rect.fromLTWH(0, 0, 1920, 1080);
      output.id.value = 7;
      output.rect.value = const Rect.fromLTWH(0, 0, 1920, 1080);
      final restored = makeSegment('sdr-restored');
      diagnostic.bindLifecycleSegmentForTesting(
        session: session,
        sessionInstanceId: 'session-1',
        segment: restored,
      );
      await diagnostic.sampleLifecycleSegmentForTesting();
      expect(run.debt, isFalse);
      expect(run.rows, hasLength(1));
      expect(run.rows.single['route'], HdrStrategy.sdrDirect.name);
      expect(run.rows.single['surfaceTuple'], isNull);
      expect(
        (run.rows.single['outputBindingAfter'] as Map)['topologyGeneration'],
        12,
      );
      expect(run.segments.last['rowCount'], 1);

      bumpTextureGenerationOnDuration = true;
      final changedTail = makeSegment('sdr-tail-generation-change');
      diagnostic.bindLifecycleSegmentForTesting(
        session: session,
        sessionInstanceId: 'session-1',
        segment: changedTail,
      );
      await diagnostic.sampleLifecycleSegmentForTesting();
      expect(run.debt, isFalse,
          reason: 'endpoint change after the read is a recoverable tail drift');
      expect(run.segments.last['endReason'], 'surface-drift');
      expect(run.rows, hasLength(1));
      await diagnostic.close(cleanup: 'test complete');
      await run.close();
    });

    test('foreign source remains hard debt during expected Surface recovery',
        () async {
      final player = _PropertyDiagnosticPlayer(<String, String>{
        ..._idleProperties(),
        'path': '/data/local/tmp/foreign.mp4',
        'playlist/0/id': '41',
      })
        ..fileLoadedEpoch = 7;
      final route = HdrRoute(
        strategy: HdrStrategy.sdrDirect,
        presentation: HdrPresentation.sdr,
        outputTransfer: HdrOutputTransfer.sdr,
        appliesDynamicMetadata: false,
        topology: HdrTopology.texture,
        vo: 'gpu-next',
        hwdec: 'mediacodec',
        targetPrim: null,
        targetTrc: null,
        surfaceTransfer: null,
        stripDvRpu: false,
      );
      final output = _TextureAndroidOutput(
        player: player,
        textureId: 7,
        rect: const Rect.fromLTWH(0, 0, 1920, 1080),
        generation: 12,
      );
      final video = _TextureVideoController(player, output);
      final session = _DiagnosticSession(video, route);
      final run = AndroidNativeDvSessionLifecycleRun(
        durationSeconds: 900,
        externalIdentityLabel: 'test-candidate',
        writeOverride: (_) async {},
      );
      final diagnostic = AndroidNativeDvSessionDiagnostic(
        player: player,
        durationSeconds: 900,
        intervalSeconds: 5,
        externalIdentityLabel: 'test-candidate',
        lifecycleRun: run,
      )..setInitialIdleBaselineForTesting(
          properties: _idleProperties(),
          fileLoadedEpoch: 7,
        );
      final record = run.beginSegment(
        segmentId: 'foreign-source',
        sessionInstanceId: 'session-1',
        generation: 1,
        expectedSource: androidNativeDvSessionLifecycleSdrPath,
        route: HdrStrategy.sdrDirect.name,
        actionId: 'P5SDRP5',
        requestId: 'foreign-source',
        routeApplied: const {'generation': 1},
      );
      final segment = <String, Object?>{
        'record': record,
        'segmentId': 'foreign-source',
        'sessionInstanceId': 'session-1',
        'generation': 1,
        'expectedSource': androidNativeDvSessionLifecycleSdrPath,
        'route': HdrStrategy.sdrDirect,
        'proof': null,
        'entryId': '41',
        'epoch': 7,
      };
      diagnostic.bindLifecycleSegmentForTesting(
        session: session,
        sessionInstanceId: 'session-1',
        segment: segment,
      );
      await diagnostic.sampleLifecycleSegmentForTesting();
      expect(run.debt, isTrue);
      expect(run.segments.single['endReason'], 'identity-or-sampling-error');
      expect(run.rows, isEmpty);
      await diagnostic.close(cleanup: 'test complete');
      await run.close();
    });

    test('native PlatformView head owner loss is recoverable but never adopted',
        () async {
      final fixedPath = androidNativeDvSessionLifecycleP5Path;
      const epoch = 7;
      const entryId = '41';
      final player = _PropertyDiagnosticPlayer(<String, String>{
        ..._idleProperties(),
        'path': fixedPath,
        'playlist/0/id': entryId,
        'vd-lavc-o': 'native_dv=1',
        'mediacodec-embed-render-mode': 'timed',
        'android-mediacodec-info':
            '{"api":1,"mime":"video/dolby-vision","codec":"OMX.DV","native-dv-active":true}',
        'hwdec': 'mediacodec',
        'hwdec-current': 'OMX.DV',
        'vo': 'mediacodec_embed',
        'time-pos': '40.0',
        'duration': '263.0',
        'pause': 'no',
        'frame-drop-count': '0',
        'decoder-frame-drop-count': '0',
        'mistimed-frame-count': '0',
        'vo-delayed-frame-count': '0',
      })
        ..fileLoadedEpoch = epoch;
      const owner = AndroidSurfaceAccountId(
        handle: 101,
        generation: 4,
        viewId: 8,
        surfaceGeneration: 9,
        wid: 202,
      );
      final output = _TextureAndroidOutput(
        player: player,
        textureId: 7,
        rect: const Rect.fromLTWH(0, 0, 1920, 1080),
        generation: 12,
        platformView: true,
      );
      output.owner = null;
      final video = _TextureVideoController(player, output);
      final route = HdrRoute(
        strategy: HdrStrategy.nativeDolbyVision,
        presentation: HdrPresentation.nativeDolbyVision,
        outputTransfer: HdrOutputTransfer.dolbyVision,
        appliesDynamicMetadata: true,
        topology: HdrTopology.platformView,
        vo: 'mediacodec_embed',
        hwdec: 'mediacodec',
        vdLavcOptions: 'native_dv=1',
        mediacodecEmbedRenderMode: 'timed',
        targetPrim: null,
        targetTrc: null,
        surfaceTransfer: null,
        stripDvRpu: false,
      );
      final session = _DiagnosticSession(video, route);
      final run = AndroidNativeDvSessionLifecycleRun(
        durationSeconds: 900,
        externalIdentityLabel: 'test-candidate',
        writeOverride: (_) async {},
      );
      final codec = AndroidMediaCodecConfiguration.parse(
        player.properties['android-mediacodec-info'],
      )!;
      final proof = HdrNativeDvReviewEvidence(
        source: HdrOptionSourceIdentity(
          player: player,
          path: fixedPath,
          playlistEntryId: entryId,
          fileLoadedEpoch: epoch,
        ),
        loaded: FileLoadedRecord(epoch, 41),
        controller: output,
        output: owner,
        configuration: codec,
        hwdecCurrent: 'OMX.DV',
      );
      final diagnostic = AndroidNativeDvSessionDiagnostic(
        player: player,
        durationSeconds: 900,
        intervalSeconds: 5,
        externalIdentityLabel: 'test-candidate',
        lifecycleRun: run,
      );
      Map<String, Object?> makeSegment(String id) {
        final record = run.beginSegment(
          segmentId: id,
          sessionInstanceId: 'session-1',
          generation: 1,
          expectedSource: fixedPath,
          route: HdrStrategy.nativeDolbyVision.name,
          actionId: 'RestoreSurface',
          requestId: id,
          consumerValidated: const {'generation': 1},
          routeApplied: const {'generation': 1, 'route': 'nativeDolbyVision'},
        );
        return <String, Object?>{
          'record': record,
          'segmentId': id,
          'sessionInstanceId': 'session-1',
          'generation': 1,
          'expectedSource': fixedPath,
          'route': HdrStrategy.nativeDolbyVision,
          'proof': proof,
          'entryId': entryId,
          'epoch': epoch,
        };
      }

      final missing = makeSegment('native-head-missing');
      diagnostic.bindLifecycleSegmentForTesting(
        session: session,
        sessionInstanceId: 'session-1',
        segment: missing,
      );
      await diagnostic.sampleLifecycleSegmentForTesting();
      expect(run.debt, isFalse);
      expect(run.segments.single['endReason'], 'surface-drift');
      expect(run.rows, isEmpty);

      output.owner = owner;
      final restored = makeSegment('native-owner-restored');
      diagnostic.bindLifecycleSegmentForTesting(
        session: session,
        sessionInstanceId: 'session-1',
        segment: restored,
      );
      await diagnostic.sampleLifecycleSegmentForTesting();
      expect(run.debt, isFalse);
      expect(run.rows, hasLength(1));
      expect(run.rows.single['surfaceTuple'], owner.asChannelArguments());

      output.owner = const AndroidSurfaceAccountId(
        handle: 101,
        generation: 4,
        viewId: 9,
        surfaceGeneration: 10,
        wid: 202,
      );
      final changed = makeSegment('native-owner-changed');
      diagnostic.bindLifecycleSegmentForTesting(
        session: session,
        sessionInstanceId: 'session-1',
        segment: changed,
      );
      await diagnostic.sampleLifecycleSegmentForTesting();
      expect(run.debt, isFalse);
      expect(run.segments.last['endReason'], 'surface-drift');
      expect(run.rows, hasLength(1),
          reason:
              'a different Java five-tuple is never adopted into this proof');
      await diagnostic.close(cleanup: 'test complete');
      await run.close();
    });

    test('Texture output uses its actual endpoint binding and no Java tuple',
        () {
      final player = _DiagnosticPlayer();
      final output = _TextureAndroidOutput(
        player: player,
        textureId: 7,
        rect: const Rect.fromLTWH(0, 0, 1920, 1080),
        generation: 12,
      );
      final video = _TextureVideoController(player, output);
      final snapshot = androidNativeDvTextureBindingSnapshotForTesting(
        video: video,
        output: output,
      );
      expect(snapshot['kind'], 'android-texture');
      expect(snapshot['textureId'], 7);
      expect(snapshot['platformTextureId'], 7);
      expect(snapshot['topologyGeneration'], 12);
      expect(snapshot['abaAbsenceProven'], isFalse);
      expect(snapshot['continuousBindingProven'], isFalse);
      expect(snapshot.containsKey('surfaceTuple'), isFalse);
      final changed = Map<String, Object?>.from(snapshot)
        ..['topologyGeneration'] = 13;
      expect(androidNativeDvTextureBindingSnapshotsMatch(snapshot, changed),
          isFalse);
    });

    test('fullscreen exit compares against the recovered entry tuple', () {
      final observations = AndroidNativeDvFullscreenLifecycleObservations();
      Map<String, Object?> tuple(String handle, int generation) =>
          <String, Object?>{
            'handle': handle,
            'generation': generation,
            'viewId': 1,
            'surfaceGeneration': generation,
            'wid': generation + 100,
          };
      final before = tuple('A', 1);
      final entry = tuple('B', 2);
      final recovered = tuple('C', 3);
      observations.observeEntry(before: before, during: entry);
      observations.observeEntryRecovery(recovered);
      observations.observeExit(tuple('C', 3));
      expect(observations.entryChanged, isTrue);
      expect(observations.exitChanged, isFalse,
          reason:
              'a stable recovered C tuple must not compare against stale B');
      expect(observations.toJson()['abaAbsenceProven'], isFalse);
      observations.observeExit(tuple('B', 2));
      expect(observations.exitChanged, isTrue,
          reason: 'returning from recovered C to B is a real exit change');
    });

    test('route binding rejects consumer evidence after generation changes',
        () {
      expect(
          androidNativeDvSessionRouteBindingMatches(
            acceptedGeneration: 4,
            appliedGeneration: 4,
            currentSessionGeneration: 4,
            appliedNativeDv: true,
            reportedNativeDv: true,
          ),
          isTrue);
      expect(
          androidNativeDvSessionRouteBindingMatches(
            acceptedGeneration: 4,
            appliedGeneration: 5,
            currentSessionGeneration: 5,
            appliedNativeDv: true,
            reportedNativeDv: true,
          ),
          isFalse);
      expect(
          androidNativeDvSessionRouteBindingMatches(
            acceptedGeneration: 4,
            appliedGeneration: 4,
            currentSessionGeneration: 4,
            appliedNativeDv: false,
            reportedNativeDv: true,
          ),
          isFalse);
    });

    test(
        'production write queue defers observer write and rejects late scheduled event',
        () async {
      final queue = AndroidNativeDvSessionReportWriteQueue();
      final writes = <String>[];
      final started = Completer<void>();
      final release = Completer<void>();
      queue.schedule(() async {
        writes.add('accepted');
        started.complete();
        await release.future;
      });
      expect(writes, isEmpty);
      await started.future;
      queue.closeAdmission();
      queue.schedule(() async => writes.add('late-event'));
      final finalWrite = queue.enqueue(() async => writes.add('final'));
      release.complete();
      await finalWrite;
      await queue.flush();
      await Future<void>.delayed(Duration.zero);
      expect(writes, ['accepted', 'final']);
    });

    test(
        'ordinary refusal is retained and realizer gates precede maturity bypass',
        () {
      final source = HdrSourceDescriptor.fromKind(HdrMediaKind.dolbyVisionP5);
      const caps = HdrCapabilities(
        sdkInt: 24,
        displayHdrTypes: {1},
        hevcDecoders: [],
        dolbyVisionDecoders: [
          HdrDecoderInfo(
            name: 'hardware-dv',
            mimeType: 'video/dolby-vision',
            hardwareAcceleration: true,
            profiles: [32],
            main10: null,
            widthRange: null,
            heightRange: null,
            frameRateRange: null,
            supports4K: true,
            max4KFps: 60,
          ),
        ],
        p5PipelineAvailable: false,
        nativeDvBridgeApi: 1,
        dataSpaceBridgeLoaded: false,
        dataSpaceExt: null,
      );
      final ordinary = HdrRoutePlanner.plan(source: source, capabilities: caps);
      final diagnostic = planAndroidNativeDvSessionDiagnostic(
        source: source,
        capabilities: caps,
        policy: HdrRoutingPolicy.defaults,
        preference: HdrOutputPreference.auto,
        excluded: const {},
      );
      final ordinaryNative = ordinary.candidates.firstWhere(
        (candidate) => candidate.strategy == HdrStrategy.nativeDolbyVision,
      );
      // 2026-10-06 dvP5 maturity unlock: the table now carries
      // experimental for dvP5 x nativeDolbyVision (realizer gates still
      // precede the maturity bypass below).
      expect(ordinaryNative.maturity, HdrStrategyMaturity.experimental);
      expect(ordinaryNative.skipReason,
          HdrDegradeReason.experimentalStrategySkipped);
      expect(ordinary.selected.strategy, isNot(HdrStrategy.nativeDolbyVision));
      expect(diagnostic.selected.maturity, HdrStrategyMaturity.experimental);
      expect(diagnostic.selected.strategy, HdrStrategy.nativeDolbyVision);
      expect(diagnostic.selected.feasible, isTrue);
      expect(diagnostic.playable, isTrue);
      expect(diagnostic.presentation, HdrPresentation.nativeDolbyVision);
      expect(diagnostic.confidence, HdrPredictionConfidence.verified);
      expect(
        planAndroidNativeDvSessionDiagnostic(
          source: source,
          capabilities: caps,
          policy: HdrRoutingPolicy.defaults,
          preference: HdrOutputPreference.off,
          excluded: const {},
        ).selected.strategy,
        isNot(HdrStrategy.nativeDolbyVision),
      );
      expect(
        planAndroidNativeDvSessionDiagnostic(
          source: source,
          capabilities: caps,
          policy: HdrRoutingPolicy.defaults,
          preference: HdrOutputPreference.auto,
          excluded: const {
            HdrRouteDependency.nativeDolbyVision:
                HdrDegradeReason.nativeDvUnavailable,
          },
        ).selected.strategy,
        isNot(HdrStrategy.nativeDolbyVision),
      );
    });
  });
}

class _SlowPropertyPlayer implements Player {
  @override
  Future<String> getProperty(String name,
      {bool waitForInitialization = true}) async {
    final delay = Stopwatch()..start();
    while (delay.elapsed < const Duration(milliseconds: 1100)) {}
    return 'late-value';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ControlledPropertyPlayer implements Player {
  final first = Completer<String>();
  final names = <String>[];

  @override
  Future<String> getProperty(String name, {bool waitForInitialization = true}) {
    names.add(name);
    return name == 'first' ? first.future : Future<String>.value('next');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _DiagnosticPlayer implements Player {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TextureVideoController implements VideoController {
  _TextureVideoController(this.player, _TextureAndroidOutput output) {
    platform.complete(output);
    notifier.value = output;
    id.value = output.id.value;
    rect.value = output.rect.value;
  }

  @override
  final Player player;
  @override
  final Completer<PlatformVideoController> platform =
      Completer<PlatformVideoController>();
  @override
  final ValueNotifier<PlatformVideoController?> notifier =
      ValueNotifier<PlatformVideoController?>(null);
  @override
  final ValueNotifier<int?> id = ValueNotifier<int?>(null);
  @override
  final ValueNotifier<Rect?> rect = ValueNotifier<Rect?>(null);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TextureAndroidOutput implements AndroidVideoController {
  _TextureAndroidOutput({
    required this.player,
    required int textureId,
    required Rect rect,
    required this.generation,
    this.platformView = false,
  })  : id = ValueNotifier<int?>(textureId),
        rect = ValueNotifier<Rect?>(rect);

  @override
  final Player player;
  @override
  late final VideoControllerConfiguration configuration =
      VideoControllerConfiguration(
    android: AndroidVideoOptions(usePlatformView: platformView),
  );
  @override
  final ValueNotifier<int?> id;
  @override
  final ValueNotifier<Rect?> rect;
  int generation;
  final bool platformView;
  AndroidSurfaceAccountId? owner;

  @override
  int get nativeSurfaceGeneration => generation;

  @override
  AndroidSurfaceAccountId? get currentBoundOutputIdentity => owner;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SdrDiagnosticFixture {
  const _SdrDiagnosticFixture(this.run, this.diagnostic);
  final AndroidNativeDvSessionLifecycleRun run;
  final AndroidNativeDvSessionDiagnostic diagnostic;
}

_SdrDiagnosticFixture _sdrDiagnosticFixture({
  HdrRoute? typedRoute,
  HdrRoute? appliedTypedRoute,
  Map<String, String> overrides = const {},
}) {
  final baseline = <String, String>{
    ..._idleProperties(),
    'hwdec': 'no',
    'hwdec-current': '',
    'vd-lavc-o': '',
    'mediacodec-embed-render-mode': 'boolean',
  };
  final properties = <String, String>{
    ...baseline,
    'path': androidNativeDvSessionLifecycleSdrPath,
    'playlist/0/id': '41',
    'android-mediacodec-info':
        '{"api":1,"mime":"video/avc","codec":"OMX.test","native-dv-active":false}',
    'hwdec': 'mediacodec-copy',
    'hwdec-current': 'mediacodec-copy',
    'vo': 'gpu-next',
    'mediacodec-embed-render-mode': 'boolean',
    'time-pos': '1.0',
    'duration': '120.0',
    'pause': 'no',
    'frame-drop-count': '0',
    'decoder-frame-drop-count': '0',
    'mistimed-frame-count': '0',
    'vo-delayed-frame-count': '0',
    ...overrides,
  };
  final player = _PropertyDiagnosticPlayer(properties)..fileLoadedEpoch = 7;
  final route = typedRoute ?? _copySdrRoute();
  final eventRoute = appliedTypedRoute ?? route;
  final output = _TextureAndroidOutput(
    player: player,
    textureId: 7,
    rect: const Rect.fromLTWH(0, 0, 1920, 1080),
    generation: 12,
  );
  final video = _TextureVideoController(player, output)
    ..id.value = 7
    ..rect.value = const Rect.fromLTWH(0, 0, 1920, 1080);
  output.id.value = 7;
  output.rect.value = const Rect.fromLTWH(0, 0, 1920, 1080);
  final session = _DiagnosticSession(video, route);
  final run = AndroidNativeDvSessionLifecycleRun(
    durationSeconds: 900,
    externalIdentityLabel: 'test-candidate',
    writeOverride: (_) async {},
  );
  final diagnostic = AndroidNativeDvSessionDiagnostic(
    player: player,
    durationSeconds: 900,
    intervalSeconds: 5,
    externalIdentityLabel: 'test-candidate',
    lifecycleRun: run,
  )..setInitialIdleBaselineForTesting(
      properties: baseline,
      fileLoadedEpoch: 7,
    );
  final record = run.beginSegment(
    segmentId: 'sdr-diagnostic',
    sessionInstanceId: 'session-1',
    generation: 1,
    expectedSource: androidNativeDvSessionLifecycleSdrPath,
    route: eventRoute.strategy.name,
    actionId: 'P5SDRP5',
    requestId: 'sdr-diagnostic',
    routeApplied: <String, Object?>{
      'generation': 1,
      'route': eventRoute.strategy.name,
    },
  );
  diagnostic.bindLifecycleSegmentForTesting(
    session: session,
    sessionInstanceId: 'session-1',
    segment: <String, Object?>{
      'record': record,
      'segmentId': 'sdr-diagnostic',
      'sessionInstanceId': 'session-1',
      'generation': 1,
      'expectedSource': androidNativeDvSessionLifecycleSdrPath,
      'route': eventRoute.strategy,
      'appliedTypedRoute': eventRoute,
      'proof': null,
      'entryId': '41',
      'epoch': 7,
    },
  );
  return _SdrDiagnosticFixture(run, diagnostic);
}

HdrRoute _copySdrRoute({
  HdrStrategy strategy = HdrStrategy.sdrDirect,
  HdrPresentation presentation = HdrPresentation.sdr,
  HdrOutputTransfer outputTransfer = HdrOutputTransfer.sdr,
  bool appliesDynamicMetadata = false,
  HdrTopology topology = HdrTopology.texture,
  String vo = 'gpu-next',
  String hwdec = 'mediacodec-copy',
  String? vdLavcOptions,
  String? mediacodecEmbedRenderMode,
  String? targetPrim,
  String? targetTrc,
  String? surfaceTransfer,
  bool stripDvRpu = false,
  Set<String> dependencies = const <String>{
    HdrRouteDependency.hwdecMediacodecCopy,
  },
}) =>
    HdrRoute(
      strategy: strategy,
      presentation: presentation,
      outputTransfer: outputTransfer,
      appliesDynamicMetadata: appliesDynamicMetadata,
      topology: topology,
      vo: vo,
      hwdec: hwdec,
      vdLavcOptions: vdLavcOptions,
      mediacodecEmbedRenderMode: mediacodecEmbedRenderMode,
      targetPrim: targetPrim,
      targetTrc: targetTrc,
      surfaceTransfer: surfaceTransfer,
      stripDvRpu: stripDvRpu,
      dependencies: dependencies,
    );

Map<String, String> _idleProperties() => <String, String>{
      'path': '',
      'playlist/0/id': '',
      'vd-lavc-o': 'baseline-options',
      'mediacodec-embed-render-mode': 'baseline-render',
      'android-mediacodec-info':
          '{"api":1,"mime":"video/avc","codec":"OMX.test","native-dv-active":false}',
      'hwdec': 'baseline-hwdec',
      'hwdec-current': 'baseline-hwdec-current',
      'vo': 'baseline-vo',
      'android-native-dv-bridge-api': '1',
    };

class _PropertyDiagnosticPlayer implements Player {
  _PropertyDiagnosticPlayer(
    this.properties, {
    this.failProperty,
    this.onRead,
  });

  final Map<String, String> properties;
  final String? failProperty;
  final void Function(String name)? onRead;
  @override
  final Lock lock = Lock();
  @override
  int fileLoadedEpoch = 5;
  @override
  PlayerState get state => const PlayerState();

  @override
  Future<String> getProperty(String name,
      {bool waitForInitialization = true}) async {
    if (name == failProperty) throw StateError('read failed: $name');
    final value = properties[name] ?? '';
    onRead?.call(name);
    return value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _DiagnosticSession implements HdrVideoSession {
  _DiagnosticSession(VideoController video, HdrRoute route)
      : controller = ValueNotifier<VideoController?>(video),
        report = ValueNotifier<HdrOutputReport>(HdrOutputReport(
          generation: 1,
          actual: route,
        ));

  @override
  final ValueNotifier<VideoController?> controller;
  @override
  final ValueNotifier<HdrOutputReport> report;
  @override
  Stream<HdrOutputEvent> get events => const Stream<HdrOutputEvent>.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
