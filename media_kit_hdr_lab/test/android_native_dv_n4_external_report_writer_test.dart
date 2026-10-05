import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit_hdr_lab/tests/01.single_player_single_video.dart';

void main() {
  group('N4 external report writer', () {
    late Directory sandbox;

    setUp(() async {
      sandbox = await Directory.systemTemp.createTemp('n4-report-writer-');
    });

    tearDown(() async {
      if (await sandbox.exists()) await sandbox.delete(recursive: true);
    });

    test('writes JSON below external diagnostics directory and renames tmp',
        () async {
      final payload = <String, Object?>{
        'runId': 'run-a',
        'finalCloseErrors': [
          {'phase': 'cancel', 'error': 'retained'}
        ],
      };
      final report = await writeAndroidNativeDvN4ExternalReport(
        externalStorageDirectoryProvider: () async => sandbox,
        runId: 'run-a',
        payload: payload,
      );

      expect(
          report.path,
          '${sandbox.path}${Platform.pathSeparator}media-kit-hdr-diagnostic'
          '${Platform.pathSeparator}android-native-dv-n4-run-a.json');
      expect(jsonDecode(await report.readAsString()), payload);
      expect(await File('${report.path}.tmp').exists(), isFalse);
    });

    test('unique run paths preserve the normal Session diagnostic', () async {
      final directory = Directory(
          '${sandbox.path}${Platform.pathSeparator}media-kit-hdr-diagnostic');
      await directory.create();
      final existing = File(
          '${directory.path}${Platform.pathSeparator}native-dv-session-diagnostic.json');
      await existing.writeAsString('existing-session-report');

      final first = await writeAndroidNativeDvN4ExternalReport(
        externalStorageDirectoryProvider: () async => sandbox,
        runId: 'one',
        payload: const {'runId': 'one'},
      );
      final second = await writeAndroidNativeDvN4ExternalReport(
        externalStorageDirectoryProvider: () async => sandbox,
        runId: 'two',
        payload: const {'runId': 'two'},
      );

      expect(first.path, isNot(second.path));
      expect(await existing.readAsString(), 'existing-session-report');
      expect(jsonDecode(await first.readAsString()), {'runId': 'one'});
      expect(jsonDecode(await second.readAsString()), {'runId': 'two'});
    });

    test('null external root preserves explicit unavailable error', () async {
      await expectLater(
        writeAndroidNativeDvN4ExternalReport(
          externalStorageDirectoryProvider: () async => null,
          runId: 'null-root',
          payload: const {},
        ),
        throwsA(isA<StateError>().having(
          (error) => error.message,
          'message',
          'App external files directory unavailable',
        )),
      );
      expect(
        await Directory(
                '${sandbox.path}${Platform.pathSeparator}media-kit-hdr-diagnostic')
            .exists(),
        isFalse,
      );
    });

    test('provider failure propagates the original object and stack', () async {
      final error = StateError('provider failed');
      final providerStack = StackTrace.current;
      Object? caught;
      StackTrace? caughtStack;
      try {
        await writeAndroidNativeDvN4ExternalReport(
          externalStorageDirectoryProvider: () async {
            Error.throwWithStackTrace(error, providerStack);
          },
          runId: 'provider-error',
          payload: const {},
        );
      } catch (failure, stack) {
        caught = failure;
        caughtStack = stack;
      }

      expect(caught, same(error));
      expect(caughtStack.toString(), providerStack.toString());
    });

    test('directory creation conflict propagates and publishes no report',
        () async {
      final conflict = File(
          '${sandbox.path}${Platform.pathSeparator}media-kit-hdr-diagnostic');
      await conflict.writeAsString('not a directory');

      await expectLater(
        writeAndroidNativeDvN4ExternalReport(
          externalStorageDirectoryProvider: () async => sandbox,
          runId: 'mkdir-conflict',
          payload: const {},
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(await conflict.readAsString(), 'not a directory');
    });

    test('tmp path write conflict propagates without publishing final path',
        () async {
      final directory = Directory(
          '${sandbox.path}${Platform.pathSeparator}media-kit-hdr-diagnostic');
      await directory.create();
      final temporary = Directory(
          '${directory.path}${Platform.pathSeparator}android-native-dv-n4-tmp-conflict.json.tmp');
      await temporary.create();

      await expectLater(
        writeAndroidNativeDvN4ExternalReport(
          externalStorageDirectoryProvider: () async => sandbox,
          runId: 'tmp-conflict',
          payload: const {'runId': 'tmp-conflict'},
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(
        await File(
                '${directory.path}${Platform.pathSeparator}android-native-dv-n4-tmp-conflict.json')
            .exists(),
        isFalse,
      );
    });

    test('rename conflict preserves original target and leaves tmp evidence',
        () async {
      final directory = Directory(
          '${sandbox.path}${Platform.pathSeparator}media-kit-hdr-diagnostic');
      await directory.create();
      final finalTarget = Directory(
          '${directory.path}${Platform.pathSeparator}android-native-dv-n4-rename-conflict.json');
      await finalTarget.create();
      final sentinel =
          File('${finalTarget.path}${Platform.pathSeparator}sentinel.txt');
      await sentinel.writeAsString('original target');

      await expectLater(
        writeAndroidNativeDvN4ExternalReport(
          externalStorageDirectoryProvider: () async => sandbox,
          runId: 'rename-conflict',
          payload: const {'runId': 'rename-conflict'},
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(await sentinel.readAsString(), 'original target');
      expect(
        await File('${finalTarget.path}.tmp').exists(),
        isTrue,
      );
    });

    test('failed final report prevents production close sequence from popping',
        () async {
      final sequence = AndroidNativeDvN4PageCloseSequence();
      var popCount = 0;
      final exit = sequence.exit(
        closeAndPersist: () => sequence.closeAndPersist(
          closeAdmission: () {},
          waitStartup: () async {},
          waitExecution: () async {},
          result: () => null,
          closeDiagnostic: () async {},
          closeHelper: () async {},
          cancelEvents: () async {},
          drain: () async => [
            {'kind': 'player-termination', 'success': true}
          ],
          playerTerminationSucceeded:
              androidNativeDvN4PlayerTerminationSucceeded,
          terminationError: (_) => null,
          terminationStack: (_) => null,
          persistFinalReport: (_) async {
            await writeAndroidNativeDvN4ExternalReport(
              externalStorageDirectoryProvider: () async => null,
              runId: 'close-no-root',
              payload: const {},
            );
          },
        ),
        pop: () async => popCount++,
      );

      await expectLater(
        exit,
        throwsA(isA<StateError>().having(
          (error) => error.message,
          'message',
          'App external files directory unavailable',
        )),
      );
      expect(popCount, 0);
    });
  });
}
