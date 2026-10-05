import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit_hdr_lab/common/android_native_dv_session_lifecycle.dart';

void main() {
  group('Manual resume admission and playback observation', () {
    final session = Object();
    AndroidNativeDvManualResumeState state({
      Object? owner,
      String sessionId = 'session-1',
      bool accepted = true,
      bool playing = false,
      bool completed = false,
      bool buffering = false,
      Duration position = const Duration(seconds: 30),
    }) =>
        AndroidNativeDvManualResumeState(
          session: owner ?? session,
          sessionInstanceId: sessionId,
          startupAccepted: accepted,
          playing: playing,
          completed: completed,
          buffering: buffering,
          position: position,
        );

    test('manual resume adds one action while preserving original action order',
        () {
      expect(androidNativeDvSessionLifecycleActions, <String>[
        'close-and-exit',
        'Pause10Resume',
        'ManualResume',
        'Seek90Then30',
        'Reopen40Then10',
        'P5SDRP5',
        'RestoreSurface',
        'FullscreenRoundTrip',
        'RecreateSession',
      ]);
      expect(state().canResume, true);
      for (final rejected in <AndroidNativeDvManualResumeState>[
        state(accepted: false),
        state(playing: true),
        state(completed: true),
        state(buffering: true),
        const AndroidNativeDvManualResumeState(
            session: null,
            sessionInstanceId: 'session-1',
            startupAccepted: true,
            playing: false,
            completed: false,
            buffering: false,
            position: Duration.zero),
      ]) {
        expect(rejected.canResume, false);
      }
    });

    test('accepted paused Session plays once and publishes endpoint evidence',
        () async {
      final run = AndroidNativeDvSessionLifecycleRun(
          durationSeconds: 900,
          externalIdentityLabel: 'manual-resume',
          writeOverride: (_) async {})
        ..setActionEnabled('ManualResume', true);
      final expected = state();
      var current = expected;
      final calls = <String>[];
      Map<String, Object?>? facts;
      await run.runAction(
          actionId: 'ManualResume',
          requestId: 'resume',
          action: (_) async {
            facts = await runAndroidNativeDvManualResume(
                run: run,
                requestId: 'resume',
                expected: expected,
                readState: () => current,
                play: () async {
                  calls.add('play');
                  current = state(playing: true);
                },
                observePlayback: (duration) async {
                  expect(duration, const Duration(seconds: 10));
                  calls.add('observe');
                  current = state(
                      playing: true, position: const Duration(seconds: 40));
                });
            await run.recordStep(
                actionId: 'ManualResume',
                requestId: 'resume',
                stepId: 'manual-resume-10s',
                phase: 'end',
                facts: facts);
          });
      expect(calls, ['play', 'observe']);
      expect(facts!['beforePositionMs'], 30000);
      expect(facts!['afterPositionMs'], 40000);
      expect(facts!['requestedObservationMs'], 10000);
      expect(facts!['observationScope'], contains('visible-frames-unverified'));
      expect(run.actionEvents.first['phase'], 'end-certified');
      expect(run.actionEvents.last['facts'], facts);
      expect(run.debt, false);
      await run.close();
    });

    for (final rejection in <String>[
      'playing',
      'EOS',
      'buffering',
      'startup',
      'session-object',
      'session-id',
    ]) {
      test('state changing during action ACK rejects $rejection before play',
          () async {
        final expected = state();
        var current = expected;
        var calls = 0;
        final run = AndroidNativeDvSessionLifecycleRun(
            durationSeconds: 900,
            externalIdentityLabel: 'manual-resume',
            writeOverride: (_) async {
              current = switch (rejection) {
                'playing' => state(playing: true),
                'EOS' => state(completed: true),
                'buffering' => state(buffering: true),
                'startup' => state(accepted: false),
                'session-object' => state(owner: Object()),
                _ => state(sessionId: 'session-2'),
              };
            })
          ..setActionEnabled('ManualResume', true);
        await expectLater(
            run.runAction(
                actionId: 'ManualResume',
                requestId: 'resume',
                action: (_) async {
                  await runAndroidNativeDvManualResume(
                      run: run,
                      requestId: 'resume',
                      expected: expected,
                      readState: () => current,
                      play: () async => calls++,
                      observePlayback: (_) async =>
                          fail('rejected before play'));
                }),
            throwsStateError);
        expect(calls, 0);
        expect(run.actionEvents.first['phase'], 'error');
        await run.close();
      });
    }

    for (final rejection in <String>['debt', 'terminal', 'closed']) {
      test('$rejection rejects ManualResume without play', () async {
        final run = AndroidNativeDvSessionLifecycleRun(
            durationSeconds: 900,
            externalIdentityLabel: 'manual-resume',
            writeOverride: (_) async {})
          ..setActionEnabled('ManualResume', true);
        switch (rejection) {
          case 'debt':
            run.markDebt('original cleanup failure');
          case 'terminal':
            run.markTerminal(reason: 'original terminal');
          case 'closed':
            await run.close();
        }
        var calls = 0;
        await expectLater(
            run.runAction(
                actionId: 'ManualResume',
                requestId: 'resume',
                action: (_) async {
                  await runAndroidNativeDvManualResume(
                      run: run,
                      requestId: 'resume',
                      expected: state(),
                      readState: state,
                      play: () async => calls++,
                      observePlayback: (_) async {});
                }),
            throwsStateError);
        expect(calls, 0);
        if (rejection == 'debt') {
          expect(run.toJson()['error'], 'original cleanup failure');
        }
        if (!run.closed) await run.close();
      });
    }

    test('original run budget must cover observation before the play call',
        () async {
      final run = AndroidNativeDvSessionLifecycleRun(
          durationSeconds: 1,
          externalIdentityLabel: 'manual-resume',
          writeOverride: (_) async {})
        ..setActionEnabled('ManualResume', true);
      var calls = 0;
      await expectLater(
          run.runAction(
              actionId: 'ManualResume',
              requestId: 'resume',
              action: (_) async {
                await runAndroidNativeDvManualResume(
                    run: run,
                    requestId: 'resume',
                    expected: state(),
                    readState: state,
                    play: () async => calls++,
                    observePlayback: (_) async => fail('budget cannot extend'));
              }),
          throwsA(isA<TimeoutException>()));
      expect(calls, 0);
      await run.close();
    });

    for (final rejection in <String>[
      'no-advance',
      'paused',
      'EOS',
      'buffering',
      'startup',
      'session',
    ]) {
      test('$rejection after observation cannot certify resumed playback',
          () async {
        final run = AndroidNativeDvSessionLifecycleRun(
            durationSeconds: 900,
            externalIdentityLabel: 'manual-resume',
            writeOverride: (_) async {})
          ..setActionEnabled('ManualResume', true);
        final expected = state();
        var current = expected;
        var calls = 0;
        await expectLater(
            run.runAction(
                actionId: 'ManualResume',
                requestId: 'resume',
                action: (_) async {
                  await runAndroidNativeDvManualResume(
                      run: run,
                      requestId: 'resume',
                      expected: expected,
                      readState: () => current,
                      play: () async {
                        calls++;
                        current = state(playing: true);
                      },
                      observePlayback: (_) async {
                        current = switch (rejection) {
                          'no-advance' => state(playing: true),
                          'paused' =>
                            state(position: const Duration(seconds: 40)),
                          'EOS' => state(
                              playing: true,
                              completed: true,
                              position: const Duration(seconds: 40)),
                          'buffering' => state(
                              playing: true,
                              buffering: true,
                              position: const Duration(seconds: 40)),
                          'startup' => state(
                              playing: true,
                              accepted: false,
                              position: const Duration(seconds: 40)),
                          _ => state(
                              owner: Object(),
                              playing: true,
                              position: const Duration(seconds: 40)),
                        };
                      });
                }),
            throwsStateError);
        expect(calls, 1);
        expect(run.actionEvents.first['phase'], 'error');
        expect(run.actionEvents.where((e) => e['phase'] == 'end-certified'),
            isEmpty);
        await run.close();
      });
    }
  });

  group('Initial lifecycle startup admission', () {
    test('startup owns fresh admission and is one-shot', () async {
      final run = AndroidNativeDvSessionLifecycleRun(
          durationSeconds: 10,
          externalIdentityLabel: 'startup',
          writeOverride: (_) async {});
      var opened = false;
      await run.runStartup(
          requestId: 'initial',
          action: () async {
            await run.recordStep(
                actionId: 'startup',
                requestId: 'initial',
                stepId: 'initial-open',
                phase: 'begin',
                sessionInstanceId: 's',
                expectedSource: androidNativeDvSessionLifecycleP5Path);
            run.ensureActionSideEffectAllowed(
                actionId: 'startup',
                requestId: 'initial',
                operation: 'session-open-initial-open');
            opened = true;
            await Future<void>.delayed(Duration.zero);
            run.ensureActionSideEffectAllowed(
                actionId: 'startup',
                requestId: 'initial',
                operation: 'accept-sampled-initial-open');
          });
      expect(opened, true);
      expect(run.busy, false);
      expect(run.debt, false);
      await expectLater(run.runStartup(requestId: 'again', action: () async {}),
          throwsStateError);
      expect(
          () => run.ensureActionSideEffectAllowed(
              actionId: 'startup',
              requestId: 'initial',
              operation: 'outside-startup'),
          throwsStateError);
      await run.close();
    });
    test('late startup continuation refuses next side effect', () async {
      final run = AndroidNativeDvSessionLifecycleRun(
          durationSeconds: 1,
          externalIdentityLabel: 'startup',
          writeOverride: (_) async {});
      var opened = false;
      await expectLater(
          run.runStartup(
              requestId: 'initial',
              action: () async {
                await Future<void>.delayed(const Duration(milliseconds: 1100));
                run.ensureActionSideEffectAllowed(
                    actionId: 'startup',
                    requestId: 'initial',
                    operation: 'late-open');
                opened = true;
              }),
          throwsA(isA<TimeoutException>()));
      expect(opened, false);
      expect(run.debt, true);
      expect(run.busy, false);
      await run.close();
    });
    test('close waits for startup drain and rejects continuation', () async {
      final run = AndroidNativeDvSessionLifecycleRun(
          durationSeconds: 10,
          externalIdentityLabel: 'startup',
          writeOverride: (_) async {});
      final entered = Completer<void>();
      final release = Completer<void>();
      var opened = false;
      final startup = run.runStartup(
          requestId: 'initial',
          action: () async {
            entered.complete();
            await release.future;
            run.ensureActionSideEffectAllowed(
                actionId: 'startup',
                requestId: 'initial',
                operation: 'open-after-close');
            opened = true;
          });
      final failed = expectLater(startup, throwsStateError);
      await entered.future;
      final closing = run.close();
      await Future<void>.delayed(Duration.zero);
      expect(run.closed, false);
      release.complete();
      await failed;
      await closing;
      expect(opened, false);
      expect(run.closed, true);
      expect(run.busy, false);
    });
  });

  group('Session lifecycle run bounds and admission', () {
    test('duration is limited to 1..900 seconds', () {
      expect(validateAndroidNativeDvSessionLifecycleSeconds(1), 1);
      expect(validateAndroidNativeDvSessionLifecycleSeconds(900), 900);
      expect(() => validateAndroidNativeDvSessionLifecycleSeconds(0),
          throwsRangeError);
      expect(() => validateAndroidNativeDvSessionLifecycleSeconds(901),
          throwsRangeError);
    });

    test('action requires enabled entry and writes begin ACK before body',
        () async {
      final writes = <Map<String, Object?>>[];
      final run = AndroidNativeDvSessionLifecycleRun(
        durationSeconds: 900,
        externalIdentityLabel: 'test-candidate',
        writeOverride: (report) async => writes.add(report),
      );
      await expectLater(
        run.runAction(
          actionId: 'Pause10Resume',
          requestId: 'req-disabled',
          action: (_) async => fail('disabled action must not run'),
        ),
        throwsStateError,
      );
      run.setActionEnabled('Pause10Resume', true);
      var bodySawBeginAck = false;
      await run.runAction(
        actionId: 'Pause10Resume',
        requestId: 'req-1',
        action: (current) async {
          final report = current.toJson();
          final action = report['currentAction']! as Map;
          expect(action['actionId'], 'Pause10Resume');
          expect(action['requestId'], 'req-1');
          bodySawBeginAck = writes.last['currentAction'] != null;
          await current.recordStep(
            actionId: 'Pause10Resume',
            requestId: 'req-1',
            stepId: 'pause',
            phase: 'begin',
          );
        },
      );
      expect(bodySawBeginAck, isTrue);
      expect(run.busy, isFalse);
      expect(run.actionEvents.first['phase'], 'end-certified');
      expect(run.actionEvents.last['stepId'], 'pause');
      expect(run.actionEvents.last['phase'], 'begin');
    });

    test('ACK write failure blocks the side effect and becomes terminal debt',
        () async {
      var actionCalls = 0;
      var writes = 0;
      final run = AndroidNativeDvSessionLifecycleRun(
        durationSeconds: 900,
        externalIdentityLabel: 'test-candidate',
        writeOverride: (_) async {
          writes++;
          if (writes == 1) throw StateError('ACK fsync failed');
        },
      );
      run.setActionEnabled('close-and-exit', true);
      await expectLater(
        run.runAction(
          actionId: 'close-and-exit',
          requestId: 'req-ack-fail',
          action: (_) async => actionCalls++,
        ),
        throwsStateError,
      );
      expect(actionCalls, 0);
      expect(run.busy, isFalse);
      expect(run.debt, isTrue);
      expect(run.terminal, isTrue);
      expect(run.actionEvents.single['phase'], 'ackError');
    });

    test('segments and rows retain explicit IDs and bounded flattened rows',
        () async {
      final run = AndroidNativeDvSessionLifecycleRun(
        durationSeconds: 900,
        externalIdentityLabel: 'test-candidate',
        writeOverride: (_) async {},
      );
      run.setActionEnabled('Reopen40Then10', true);
      await run.runAction(
        actionId: 'Reopen40Then10',
        requestId: 'req-open',
        action: (_) async {},
      );
      final segment = run.beginSegment(
        segmentId: 'session-1-g1-segment-1',
        sessionInstanceId: 'session-1',
        generation: 1,
        expectedSource: androidNativeDvSessionLifecycleP5Path,
        route: 'nativeDolbyVision',
        actionId: 'Reopen40Then10',
        requestId: 'req-open',
        consumerValidated: const {'generation': 1},
        routeApplied: const {'generation': 1},
      );
      expect(segment['phase'], 'sampling');
      expect(
          run.appendRow(const {
            'timePosSeconds': 40,
            'eos': false,
          }),
          isTrue);
      expect(run.rows.single['segmentId'], 'session-1-g1-segment-1');
      expect(segment['rowCount'], 1,
          reason: 'appendRow owns the single per-segment row increment');
      run.closeSegment('next-generation');
      expect(run.segments.single['endReason'], 'next-generation');
      expect(run.toJson()['diagnosticMode'], 'lifecycle');
      expect(run.toJson()['diagnosticRoute'], 'session');
      expect(run.toJson()['presentationVerified'], isFalse);
    });

    test('concurrent action admission rejects instead of interleaving',
        () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      final run = AndroidNativeDvSessionLifecycleRun(
        durationSeconds: 900,
        externalIdentityLabel: 'test-candidate',
        writeOverride: (_) async {},
      )..setActionEnabled('Pause10Resume', true);
      final active = run.runAction(
        actionId: 'Pause10Resume',
        requestId: 'req-1',
        action: (_) async {
          entered.complete();
          await release.future;
        },
      );
      await entered.future;
      await expectLater(
        run.runAction(
          actionId: 'Pause10Resume',
          requestId: 'req-2',
          action: (_) async => fail('concurrent action must not run'),
        ),
        throwsStateError,
      );
      release.complete();
      await active;
      expect(
          run.actionEvents.where((event) => event['phase'] == 'end-certified'),
          hasLength(1));
    });

    test('Applied admission waits for an accepted segment sample row',
        () async {
      final gate = AndroidNativeDvSessionAppliedAdmission(
        sessionInstanceId: 'session-2',
        generation: 4,
      );
      final record = <String, Object?>{
        'sessionInstanceId': 'session-2',
        'generation': 4,
        'accepted': true,
        'rowCount': 0,
        'routeApplied': const {'generation': 4, 'route': 'nativeDolbyVision'},
      };
      final pending = gate.wait(
        remaining: const Duration(seconds: 2),
        stillAdmissible: () => true,
      );
      gate.accept(record);
      expect(gate.isAccepted, isFalse,
          reason: 'routeApplied without a row cannot release the waiter');
      record['rowCount'] = 1;
      gate.accept(record);
      expect(await pending, const {
        'generation': 4,
        'route': 'nativeDolbyVision',
      });
    });

    test('ACK completed after the original deadline never invokes action',
        () async {
      var actionCalls = 0;
      final run = AndroidNativeDvSessionLifecycleRun(
        durationSeconds: 1,
        externalIdentityLabel: 'test-candidate',
        writeOverride: (report) async {
          if (report['currentAction'] is Map) {
            await Future<void>.delayed(const Duration(milliseconds: 1100));
          }
        },
      );
      run.setActionEnabled('Pause10Resume', true);
      await run.flush();
      await expectLater(
        run.runAction(
          actionId: 'Pause10Resume',
          requestId: 'req-late-ack',
          action: (_) async => actionCalls++,
        ),
        throwsA(isA<TimeoutException>()),
      );
      expect(actionCalls, 0);
      expect(run.actionEvents.single['phase'], 'deadlineRejected');
      await run.close();
    });

    test('late step publication is rejected under the same run deadline',
        () async {
      final run = AndroidNativeDvSessionLifecycleRun(
        durationSeconds: 1,
        externalIdentityLabel: 'test-candidate',
        writeOverride: (report) async {
          final events = report['actionEvents'] as List;
          if (events
              .any((event) => event is Map && event['stepId'] == 'late-step')) {
            await Future<void>.delayed(const Duration(milliseconds: 1100));
          }
        },
      )..setActionEnabled('Pause10Resume', true);
      await run.flush();
      await expectLater(
        run.runAction(
          actionId: 'Pause10Resume',
          requestId: 'req-late-step',
          action: (current) => current.recordStep(
            actionId: 'Pause10Resume',
            requestId: 'req-late-step',
            stepId: 'late-step',
            phase: 'begin',
          ),
        ),
        throwsA(isA<TimeoutException>()),
      );
      final step = run.actionEvents.singleWhere(
        (event) => event['stepId'] == 'late-step',
      );
      expect(step['phase'], 'deadlineRejected');
      expect(run.debt, isTrue);
      await run.close();
    });

    test('late action end publication cannot report successful completion',
        () async {
      final run = AndroidNativeDvSessionLifecycleRun(
        durationSeconds: 1,
        externalIdentityLabel: 'test-candidate',
        writeOverride: (report) async {
          final events = report['actionEvents'] as List;
          if (events.any(
              (event) => event is Map && event['phase'] == 'end-provisional')) {
            await Future<void>.delayed(const Duration(milliseconds: 1100));
          }
        },
      )..setActionEnabled('Pause10Resume', true);
      await run.flush();
      await expectLater(
        run.runAction(
          actionId: 'Pause10Resume',
          requestId: 'req-late-end',
          action: (_) async {},
        ),
        throwsA(isA<TimeoutException>()),
      );
      expect(run.actionEvents.single['phase'], 'deadlineRejected');
      expect(run.debt, isTrue);
      await run.close();
    });

    test('external sequence requires a receipt after both provisional writes',
        () async {
      final visible = <String>[];
      final run = AndroidNativeDvSessionLifecycleRun(
        durationSeconds: 1,
        externalIdentityLabel: 'test-candidate',
        writeOverride: (report) async {
          final events = (report['actionEvents'] as List).cast<Map>();
          final phase = events.isEmpty ? '' : events.first['phase'] as String;
          if (phase == 'end-provisional') {
            await Future<void>.delayed(const Duration(milliseconds: 1100));
          }
          visible.add(phase);
        },
      )..setActionEnabled('Pause10Resume', true);
      await run.flush();
      await expectLater(
        run.runAction(
          actionId: 'Pause10Resume',
          requestId: 'req-slow-payload',
          action: (_) async {},
        ),
        throwsA(isA<TimeoutException>()),
      );
      expect(visible, contains('end-provisional'));
      expect(visible, contains('deadlineRejected'));
      expect(visible, isNot(contains('end-certified')));
      expect(visible, isNot(contains('end')));
      expect(run.actionEvents.first['phase'], 'deadlineRejected');
      await run.close();
    });

    test('provisional writer error cannot expose a certified action', () async {
      final visible = <String>[];
      var failProvisional = true;
      final run = AndroidNativeDvSessionLifecycleRun(
        durationSeconds: 10,
        externalIdentityLabel: '测试候选',
        writeOverride: (report) async {
          final events = (report['actionEvents'] as List).cast<Map>();
          final phase = events.isEmpty ? '' : events.first['phase'] as String;
          if (phase == 'end-provisional' && failProvisional) {
            failProvisional = false;
            throw FileSystemException('provisional latest rename failed');
          }
          visible.add(phase);
        },
      )..setActionEnabled('Pause10Resume', true);
      await run.flush();
      await expectLater(
        run.runAction(
          actionId: 'Pause10Resume',
          requestId: 'req-provisional-error',
          action: (_) async {},
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(visible, isNot(contains('end-certified')));
      expect(visible, isNot(contains('end')));
      expect(run.actionEvents.single['phase'], 'error');
      expect(run.debt, isTrue);
      await run.close();
    });

    test('timely payload has verifiable certificate, receipt timing unverified',
        () async {
      final visible = <Map<String, Object?>>[];
      final run = AndroidNativeDvSessionLifecycleRun(
        durationSeconds: 10,
        externalIdentityLabel: '测试候选',
        writeOverride: (report) async {
          visible.add(Map<String, Object?>.from(report));
        },
      )..setActionEnabled('Pause10Resume', true);
      await run.flush();
      await run.runAction(
        actionId: 'Pause10Resume',
        requestId: 'req-certificate',
        action: (_) async {},
      );
      expect(
        visible.map((report) => (report['actionEvents'] as List).isEmpty
            ? null
            : ((report['actionEvents'] as List).first as Map)['phase']),
        containsAll(<Object?>['end-provisional', 'end-certified']),
      );
      final event = run.actionEvents.single;
      expect(event['phase'], 'end-certified');
      expect(
          visible.any((report) => (report['actionEvents'] as List)
              .any((entry) => entry is Map && entry['phase'] == 'end')),
          isFalse);
      final canonical = event['provisionalPayloadCanonicalJson'] as String;
      final payload = event['provisionalPayload'] as Map<String, Object?>;
      expect(jsonDecode(canonical), payload);
      expect(
        crypto.sha256.convert(utf8.encode(canonical)).toString(),
        event['provisionalPayloadSha256'],
      );
      expect(payload['runId'], run.runId);
      expect(payload['requestId'], 'req-certificate');
      expect(payload['actionId'], 'Pause10Resume');
      final receipt = event['publicationReceipt'] as Map;
      expect(receipt['publicationId'], event['publicationId']);
      expect(receipt['payloadSha256'], event['provisionalPayloadSha256']);
      expect(receipt['scope'], 'action-and-provisional-payload');
      expect(receipt['receiptPublicationWithinDeadline'], 'unverified');
      expect(
        receipt['payloadPublishCompletedUpperBoundElapsedUs'],
        lessThan(receipt['deadlineElapsedUs'] as int),
      );
      final fixturePath =
          Platform.environment['MEDIA_KIT_NATIVE_DV_PUBLICATION_FIXTURE_PATH'];
      if (fixturePath != null && fixturePath.isNotEmpty) {
        await File(fixturePath).writeAsString(jsonEncode(visible), flush: true);
      }
      await run.close();
    });

    test(
        'late receipt is explicitly unverified but retains timely payload proof',
        () async {
      var delayedReceipt = false;
      final published = <Map<String, Object?>>[];
      final run = AndroidNativeDvSessionLifecycleRun(
        durationSeconds: 1,
        externalIdentityLabel: 'test-candidate',
        writeOverride: (report) async {
          final event = (report['actionEvents'] as List).first as Map;
          if (event['phase'] == 'end-certified' && !delayedReceipt) {
            delayedReceipt = true;
            await Future<void>.delayed(const Duration(milliseconds: 1100));
          }
          published.add(Map<String, Object?>.from(report));
        },
      )..setActionEnabled('Pause10Resume', true);
      await run.flush();
      await run.runAction(
        actionId: 'Pause10Resume',
        requestId: 'req-late-receipt',
        action: (_) async {},
      );
      final certified = published
          .map((report) => (report['actionEvents'] as List).first as Map)
          .firstWhere((event) => event['phase'] == 'end-certified');
      final receipt = certified['publicationReceipt'] as Map;
      expect(
        receipt['payloadPublishCompletedUpperBoundElapsedUs'],
        lessThan(receipt['deadlineElapsedUs'] as int),
      );
      expect(receipt['receiptPublicationWithinDeadline'], 'unverified');
      expect(run.actionEvents.single['phase'], 'end-certified');
      await run.close();
    });

    test('fullscreen entry and exit toggles each recheck after preparation',
        () async {
      for (final operation in <String>[
        'enter-fullscreen-toggle',
        'exit-fullscreen-toggle',
      ]) {
        final run = AndroidNativeDvSessionLifecycleRun(
          durationSeconds: 1,
          externalIdentityLabel: 'test-candidate',
          writeOverride: (_) async {},
        )..setActionEnabled('FullscreenRoundTrip', true);
        var sideEffects = 0;
        await expectLater(
          run.runAction(
            actionId: 'FullscreenRoundTrip',
            requestId: operation,
            action: (active) => runAndroidNativeDvAdmittedSideEffect(
              run: active,
              actionId: 'FullscreenRoundTrip',
              requestId: operation,
              operation: operation,
              prepare: () =>
                  Future<void>.delayed(const Duration(milliseconds: 1100)),
              sideEffect: () async => sideEffects++,
            ),
          ),
          throwsA(isA<TimeoutException>()),
        );
        expect(sideEffects, 0,
            reason: '$operation was blocked after late prep');
        await run.close();
      }
    });

    test('page wires both fullscreen toggles through fresh admission helper',
        () async {
      final source = await File('lib/tests/01.single_player_single_video.dart')
          .readAsString();
      final begin =
          source.indexOf('Future<void> _fullscreenLifecycleRoundTrip');
      final end = source.indexOf(
        'Duration _lifecycleSafeResumePosition()',
        begin,
      );
      expect(begin, greaterThanOrEqualTo(0));
      expect(end, greaterThan(begin));
      final method = source.substring(begin, end);
      expect(
        RegExp(r'runAndroidNativeDvAdmittedSideEffect\(')
            .allMatches(method)
            .length,
        2,
      );
      expect(method, contains("quiesceLifecycleSegment('before-fullscreen"));
      expect(method, contains('exit-fullscreen-toggle'));
    });

    test('close drains an active action before final snapshot and stays final',
        () async {
      final writes = <Map<String, Object?>>[];
      final entered = Completer<void>();
      final release = Completer<void>();
      final run = AndroidNativeDvSessionLifecycleRun(
        durationSeconds: 900,
        externalIdentityLabel: 'test-candidate',
        writeOverride: (report) async {
          writes.add(Map<String, Object?>.from(report));
        },
      )..setActionEnabled('Pause10Resume', true);
      final action = run.runAction(
        actionId: 'Pause10Resume',
        requestId: 'req-held-action',
        action: (_) async {
          entered.complete();
          await release.future;
        },
      );
      await entered.future;
      // Necessary ordering adaptation: close is started while action is held,
      // then both are awaited after releasing the uncancellable action Future.
      var closeCompleted = false;
      final closing = run.close().then((_) => closeCompleted = true);
      await Future<void>.delayed(Duration.zero);
      expect(closeCompleted, isFalse,
          reason: 'close must drain the active action before finalizing');
      release.complete();
      await Future.wait<void>(<Future<void>>[action, closing]);
      final finalizedWriteCount = writes.length;
      run.scheduleWrite();
      await Future<void>.delayed(Duration.zero);
      await run.flush();
      expect(writes, hasLength(finalizedWriteCount),
          reason: 'no queued write may follow the immutable final snapshot');
      expect(run.closed, isTrue);
      expect(run.actionEvents.single['phase'], 'end-certified');
    });

    test(
        'close-and-exit production orchestration drains and exits after cleanup',
        () async {
      final order = <String>[];
      final writes = <Map<String, Object?>>[];
      final run = AndroidNativeDvSessionLifecycleRun(
        durationSeconds: 900,
        externalIdentityLabel: 'test-candidate',
        writeOverride: (report) async {
          writes.add(Map<String, Object?>.from(report));
        },
      )..setActionEnabled('close-and-exit', true);
      await run.flush();
      await runAndroidNativeDvCloseAndExit(
        run: run,
        requestId: 'req-exit',
        terminateOwnedPlayer: () async => order.add('terminate'),
        exit: () async => order.add('exit'),
        reportFailure: (_) => fail('clean action should not report failure'),
      );
      expect(order, ['terminate', 'exit']);
      expect(run.actionEvents.single['phase'], 'end-certified');
      expect(run.closed, isTrue);
      expect(writes.last['closed'], isTrue);
      expect(writes.last['exitAcknowledgement'],
          'unverified; final snapshot precedes SystemNavigator.pop');
    });

    for (final startupFailed in [false, true]) {
      test(
          'closed action admission recovers without mislabelled termination; '
          'startupFailed=$startupFailed', () async {
        final writes = <Map<String, Object?>>[];
        final run = AndroidNativeDvSessionLifecycleRun(
          durationSeconds: 900,
          externalIdentityLabel: 'closed-admission-recovery',
          writeOverride: (report) async => writes.add(report),
        );
        if (startupFailed) {
          await expectLater(
              run.runStartup(
                  requestId: 'startup-session-1',
                  action: () async {
                    throw TimeoutException(
                        'Future not completed', const Duration(seconds: 8));
                  }),
              throwsA(isA<TimeoutException>()));
        } else {
          run.markTerminal(reason: 'terminal-only');
        }
        final originalError = run.toJson()['error'];
        final originalDebt = run.debt;
        await expectLater(
            run.runAction(
                actionId: 'close-and-exit',
                requestId: 'known-rejected',
                action: (_) async => fail('closed admission cannot run')),
            throwsA(predicate(
                (error) => '$error'.contains('Lifecycle run is closed'))));
        var terminateCalls = 0;
        var exitCalls = 0;
        final errors = <Object>[];
        await runAndroidNativeDvCloseAndExit(
          run: run,
          requestId: 'recovery',
          terminateOwnedPlayer: () async => terminateCalls++,
          exit: () async {
            expect(writes.last['closed'], true);
            exitCalls++;
          },
          reportFailure: errors.add,
        );
        expect(terminateCalls, 1);
        expect(exitCalls, 1);
        expect(run.closed, true);
        expect(run.terminal, true);
        expect(run.debt, originalDebt);
        expect(run.toJson()['error'], originalError);
        expect(errors, isEmpty);
        expect(run.actionEvents, isEmpty,
            reason: 'no rejected or certified close action is synthesized');
      });
    }

    test('genuine recovery termination failure retains startup and new errors',
        () async {
      final run = AndroidNativeDvSessionLifecycleRun(
        durationSeconds: 900,
        externalIdentityLabel: 'recovery-termination-failure',
        writeOverride: (_) async {},
      );
      const original = 'startup failed: TimeoutException after 8s';
      run.markDebt(original);
      var terminateCalls = 0;
      var exitCalls = 0;
      final errors = <Object>[];
      await runAndroidNativeDvCloseAndExit(
        run: run,
        requestId: 'recovery-failed',
        terminateOwnedPlayer: () async {
          terminateCalls++;
          run.markDebt('Player disposal callback failed');
          throw StateError('actual Player dispose failed');
        },
        exit: () async => exitCalls++,
        reportFailure: errors.add,
      );
      expect(terminateCalls, 1);
      expect(exitCalls, 1);
      expect(run.debt, true);
      expect(run.toJson()['cleanup'], 'terminated-with-debt');
      expect(run.toJson()['error'].toString(), contains(original));
      expect(run.toJson()['error'].toString(),
          contains('Player disposal callback failed'));
      expect(run.toJson()['error'].toString(),
          contains('actual Player dispose failed'));
      expect(run.toJson()['error'].toString(),
          contains('Owned termination failed before final report'));
      expect(run.toJson()['error'].toString(),
          isNot(contains('Lifecycle run is closed')));
      expect(
          errors.single.toString(), contains('actual Player dispose failed'));
      expect(run.actionEvents, isEmpty);
    });

    test('recovery final write failure retains original debt and never exits',
        () async {
      final run = AndroidNativeDvSessionLifecycleRun(
        durationSeconds: 900,
        externalIdentityLabel: 'recovery-write-failure',
        writeOverride: (report) async {
          if (report['closed'] == true) {
            throw StateError('recovery final snapshot failed');
          }
        },
      );
      const original = 'startup failed: original source error';
      run.markDebt(original);
      await run.flush();
      var terminateCalls = 0;
      var exitCalls = 0;
      final errors = <Object>[];
      await runAndroidNativeDvCloseAndExit(
        run: run,
        requestId: 'recovery-final-failure',
        terminateOwnedPlayer: () async => terminateCalls++,
        exit: () async => exitCalls++,
        reportFailure: errors.add,
      );
      expect(terminateCalls, 1);
      expect(exitCalls, 0);
      expect(run.debt, true);
      expect(run.toJson()['error'], original);
      expect(errors.single.toString(),
          contains('Final lifecycle report completion failed'));
      expect(run.actionEvents, isEmpty);
    });

    test('close-and-exit waits for the actual final snapshot write', () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      final order = <String>[];
      final run = AndroidNativeDvSessionLifecycleRun(
        durationSeconds: 900,
        externalIdentityLabel: 'final-write-pending',
        writeOverride: (report) async {
          if (report['closed'] == true) {
            entered.complete();
            await release.future;
          }
        },
      )..setActionEnabled('close-and-exit', true);
      await run.flush();
      final closing = runAndroidNativeDvCloseAndExit(
        run: run,
        requestId: 'pending-final',
        terminateOwnedPlayer: () async => order.add('terminate'),
        exit: () async => order.add('exit'),
        reportFailure: (_) => fail('healthy final write should complete'),
      );
      await entered.future;
      expect(run.closed, true);
      expect(order, ['terminate'],
          reason: 'closed is already true while persistence remains pending');
      release.complete();
      await closing;
      expect(order, ['terminate', 'exit']);
    });

    for (final terminationFails in [false, true]) {
      test(
          'final snapshot failure retains UI; terminationFails=$terminationFails',
          () async {
        var terminateCalls = 0;
        var exitCalls = 0;
        var finalWriteCalls = 0;
        final reported = <Object>[];
        final run = AndroidNativeDvSessionLifecycleRun(
          durationSeconds: 900,
          externalIdentityLabel: 'final-write-failure',
          writeOverride: (report) async {
            if (report['closed'] == true) {
              finalWriteCalls++;
              throw StateError('actual final snapshot failed');
            }
          },
        )..setActionEnabled('close-and-exit', true);
        await run.flush();
        await runAndroidNativeDvCloseAndExit(
          run: run,
          requestId: 'failed-final',
          terminateOwnedPlayer: () async {
            terminateCalls++;
            if (terminationFails) {
              throw StateError('owned Player dispose failed');
            }
          },
          exit: () async => exitCalls++,
          reportFailure: reported.add,
        );
        expect(terminateCalls, 1);
        expect(exitCalls, 0);
        expect(finalWriteCalls, terminationFails ? 2 : 1,
            reason: 'termination error queues a debt write before final close; '
                'both deferred snapshots observe closed=true and fail');
        expect(run.closed, true,
            reason: 'admission is closed, final persistence has failed');
        expect(run.debt, terminationFails,
            reason: 'final-write error remains local after snapshot closure');
        expect(reported.single.toString(),
            contains('Final lifecycle report completion failed'));
        expect(reported.single.toString(),
            contains('actual final snapshot failed'));
        if (terminationFails) {
          expect(reported.single.toString(),
              contains('owned Player dispose failed'));
          expect(run.actionEvents.single['phase'], 'error');
        }
        final attemptsBeforeRepeatedClose = finalWriteCalls;
        await expectLater(run.close(), throwsStateError);
        expect(finalWriteCalls, attemptsBeforeRepeatedClose,
            reason:
                'failed close Future is cached; no unsafe late rewrite retry');
      });
    }

    test('SystemNavigator.pop failure stays local after immutable final report',
        () async {
      var terminateCalls = 0;
      Object? reported;
      String? reportAtExit;
      final writes = <Map<String, Object?>>[];
      final run = AndroidNativeDvSessionLifecycleRun(
        durationSeconds: 900,
        externalIdentityLabel: 'test-candidate',
        writeOverride: (report) async {
          writes.add(Map<String, Object?>.from(report));
        },
      )..setActionEnabled('close-and-exit', true);
      await run.flush();
      await runAndroidNativeDvCloseAndExit(
        run: run,
        requestId: 'req-pop-failure',
        terminateOwnedPlayer: () async => terminateCalls++,
        exit: () async {
          reportAtExit = jsonEncode(run.toJson());
          throw StateError('SystemNavigator.pop failed');
        },
        reportFailure: (error) => reported = error,
      );
      final finalReport = jsonEncode(run.toJson());
      final finalWriteCount = writes.length;
      await run.flush();
      expect(terminateCalls, 1);
      expect(run.closed, isTrue);
      expect(run.debt, isFalse,
          reason: 'post-final UI exit failure cannot mutate the frozen report');
      expect(reported.toString(), contains('SystemNavigator.pop failed'));
      expect(finalReport, reportAtExit);
      expect(jsonDecode(finalReport)['exitAcknowledgement'],
          'unverified; final snapshot precedes SystemNavigator.pop');
      expect(writes, hasLength(finalWriteCount),
          reason: 'a pop error cannot publish a late JSON rewrite');
    });

    test('close-and-exit still terminates after ACK failure without action',
        () async {
      var failNextActionAck = false;
      var terminateCalls = 0;
      var actionCalls = 0;
      var exitCalls = 0;
      Object? reported;
      final run = AndroidNativeDvSessionLifecycleRun(
        durationSeconds: 900,
        externalIdentityLabel: 'test-candidate',
        writeOverride: (report) async {
          final current = report['currentAction'];
          if (failNextActionAck && current is Map) {
            failNextActionAck = false;
            throw StateError('initial ACK write failed');
          }
        },
      )..setActionEnabled('close-and-exit', true);
      await run.flush();
      failNextActionAck = true;
      await runAndroidNativeDvCloseAndExit(
        run: run,
        requestId: 'req-ack-error-exit',
        terminateOwnedPlayer: () async => terminateCalls++,
        exit: () async => exitCalls++,
        reportFailure: (error) => reported = error,
      );
      expect(actionCalls, 0);
      expect(terminateCalls, 1);
      expect(exitCalls, 1);
      expect(reported, isNotNull);
      expect(run.toJson()['error'].toString(),
          contains('Close action failed before final report'));
      expect(run.toJson()['error'].toString(),
          isNot(contains('Owned termination failed')));
      expect(run.debt, isTrue);
      expect(run.actionEvents.single['phase'], 'ackError');
      expect(run.closed, isTrue);
    });

    test('termination attempts Player disposal after cleanup and report errors',
        () async {
      final order = <String>[];
      var debt = false;
      final result = await AndroidNativeDvSessionTermination.run(
        closeRecorder: () async {
          order.add('close-recorder');
        },
        disposeSession: () async {
          order.add('dispose-session');
        },
        capturePostSession: (_) async {
          order.add('capture-post-session');
          throw StateError('property read failed');
        },
        recordCaptureError: (_) async {
          order.add('record-capture-error');
          throw StateError('report write failed');
        },
        disposePlayer: () async {
          order.add('dispose-player');
        },
        recordPlayerTermination: (_) async {
          order.add('record-player-termination');
        },
        markDebt: (_) => debt = true,
      );
      expect(order, <String>[
        'close-recorder',
        'dispose-session',
        'capture-post-session',
        'record-capture-error',
        'dispose-player',
        'record-player-termination',
      ]);
      expect(result.clean, isFalse);
      expect(result.cleanupCaptureError, isNotNull);
      expect(debt, isTrue);
    });

    test(
        'ACK failure cannot run action but cleanup termination remains callable',
        () async {
      var writes = 0;
      var actionCalls = 0;
      var playerDisposals = 0;
      final run = AndroidNativeDvSessionLifecycleRun(
        durationSeconds: 900,
        externalIdentityLabel: 'test-candidate',
        writeOverride: (_) async {
          if (++writes == 1) throw StateError('ACK write failed');
        },
      )..setActionEnabled('close-and-exit', true);
      await run.flush();
      await expectLater(
        run.runAction(
          actionId: 'close-and-exit',
          requestId: 'req-close-ack-fail',
          action: (_) async => actionCalls++,
        ),
        throwsStateError,
      );
      final result = await AndroidNativeDvSessionTermination.run(
        closeRecorder: () async {},
        disposeSession: () async {},
        capturePostSession: (_) async {},
        recordCaptureError: (_) async {},
        disposePlayer: () async => playerDisposals++,
        recordPlayerTermination: (_) async {},
        markDebt: (_) {},
      );
      expect(actionCalls, 0);
      expect(playerDisposals, 1);
      expect(result.clean, isTrue);
      await run.close();
    });

    test('Applied waiter rejects debt or expired original deadline', () async {
      final gate = AndroidNativeDvSessionAppliedAdmission(
        sessionInstanceId: 'session-2',
        generation: 5,
      );
      final record = <String, Object?>{
        'sessionInstanceId': 'session-2',
        'generation': 5,
        'accepted': true,
        'rowCount': 1,
        'routeApplied': const {'generation': 5},
      };
      final pending = gate.wait(
        remaining: const Duration(seconds: 1),
        stillAdmissible: () => false,
      );
      gate.accept(record);
      await expectLater(pending, throwsA(isA<TimeoutException>()));
    });
  });
}
