import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit_test/common/sources/android_hdr_disposal.dart';

void main() {
  test('transient stop failure retries before player and directory cleanup',
      () async {
    final parent = await Directory.systemTemp.createTemp('hdr-dispose-test-');
    addTearDown(() => parent.delete(recursive: true));
    final root = await Directory('${parent.path}/session').create();
    await File('${root.path}/sample.mp4').writeAsString('movie');
    final calls = <String>[];
    var stops = 0;
    final report = await disposeAndroidHdrResources(
      disposeCoordinator: () async {
        calls.add('stop');
        if (++stops == 1) throw StateError('transient stop failure');
      },
      disposePlayer: () async => calls.add('player'),
      privateRoot: () => root,
      wait: (_) async {},
    );
    expect(calls, ['stop', 'stop', 'player']);
    expect(report.clean, isTrue);
    expect(await root.exists(), isFalse);
  });

  test('failed player termination retains staged bytes', () async {
    final parent = await Directory.systemTemp.createTemp('hdr-retain-test-');
    addTearDown(() => parent.delete(recursive: true));
    final root = await Directory('${parent.path}/session').create();
    final staged = File('${root.path}/sample.mp4');
    await staged.writeAsString('movie');
    final report = await disposeAndroidHdrResources(
      disposeCoordinator: () async {},
      disposePlayer: () async => throw StateError('termination failed'),
      privateRoot: () => root,
    );
    expect(report.playerError, isA<StateError>());
    expect(report.retainedDirectory, root.path);
    expect(await staged.exists(), isTrue);
  });

  test('persistent stop failure still disposes player before deleting bytes',
      () async {
    final parent = await Directory.systemTemp.createTemp('hdr-stop-test-');
    addTearDown(() => parent.delete(recursive: true));
    final root = await Directory('${parent.path}/session').create();
    await File('${root.path}/sample.mp4').writeAsString('movie');
    var stops = 0;
    final report = await disposeAndroidHdrResources(
      disposeCoordinator: () async {
        stops++;
        throw StateError('stop failed');
      },
      disposePlayer: () async {},
      privateRoot: () => root,
      wait: (_) async {},
    );
    expect(stops, 3);
    expect(report.coordinatorError, isA<StateError>());
    expect(report.playerError, isNull);
    expect(await root.exists(), isFalse);
  });

  test('directory created during coordinator setup is cleaned on dispose',
      () async {
    final parent = await Directory.systemTemp.createTemp('hdr-setup-test-');
    addTearDown(() => parent.delete(recursive: true));
    final setup = Completer<void>();
    Directory? root;
    final disposing = disposeAndroidHdrResources(
      disposeCoordinator: () async {
        await setup.future;
        root = await Directory('${parent.path}/session').create();
        await File('${root!.path}/sample.mp4').writeAsString('movie');
      },
      disposePlayer: () async {},
      privateRoot: () => root,
    );
    setup.complete();
    final report = await disposing;
    expect(report.clean, isTrue);
    expect(root, isNotNull);
    expect(await root!.exists(), isFalse);
  });
}
