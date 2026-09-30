import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit_hdr_lab/common/sources/android_hdr_open_coordinator.dart';
import 'package:media_kit_hdr_lab/common/sources/android_hdr_sample_identity.dart';

class FakeBackend implements AndroidHdrOpenBackend {
  final calls = <String>[];
  Completer<void>? heldOpen;
  Completer<void>? heldOutput;
  Completer<void>? heldConfigure;
  Completer<void>? heldPrepareOutput;
  bool failConfigure = false;
  bool removeStagedOnConfigureFailure = false;
  bool failStopOnce = false;
  bool failResetOnce = false;
  bool failValidate = false;

  @override
  Future<void> validate(AndroidHdrSampleIdentity identity) async {
    if (failValidate) throw StateError('unsupported output policy');
  }

  @override
  Future<void> stop() async {
    calls.add('stop');
    if (failStopOnce) {
      failStopOnce = false;
      throw StateError('stop failed');
    }
  }

  @override
  Future<void> resetOwnedConfiguration() async {
    calls.add('reset');
    if (failResetOnce) {
      failResetOnce = false;
      throw StateError('reset failed');
    }
  }

  @override
  Future<void> prepareOutput(AndroidHdrSampleIdentity identity) async {
    calls.add('prepare:${identity.path}');
    await heldPrepareOutput?.future;
  }

  @override
  Future<void> configure(AndroidHdrSampleIdentity identity) async {
    calls.add('configure:${identity.path}');
    await heldConfigure?.future;
    if (failConfigure) {
      if (removeStagedOnConfigureFailure) {
        await File(identity.path).parent.delete(recursive: true);
      }
      throw StateError('configuration failed');
    }
  }

  @override
  Future<void> waitForOutput(AndroidHdrSampleIdentity identity) async {
    calls.add('output:${identity.path}');
    await heldOutput?.future;
  }

  @override
  Future<void> open(
    AndroidHdrSampleIdentity identity, {
    Duration? start,
    required bool play,
  }) async {
    calls.add('open:${identity.path}');
    await heldOpen?.future;
  }

  @override
  Future<void> verifyTrack(AndroidHdrSampleIdentity identity) async {
    calls.add('track:${identity.path}');
  }
}

AndroidHdrSampleIdentity identity(String path) => AndroidHdrSampleIdentity(
    AndroidHdrSample.dolbyVisionP84, 'test-hash', path);

void main() {
  test('successful direct open is stopped and reset on coordinator dispose',
      () async {
    final backend = FakeBackend();
    final coordinator = AndroidHdrOpenCoordinator(backend,
        verifier: (source, _) async => identity(source));
    await coordinator.openSource('A');
    final before = backend.calls.length;
    await coordinator.dispose();
    expect(backend.calls.skip(before), ['stop', 'reset']);
  });

  test('dispose retries reset after a successful open', () async {
    final backend = FakeBackend();
    final coordinator = AndroidHdrOpenCoordinator(backend,
        verifier: (source, _) async => identity(source));
    await coordinator.openSource('A');
    backend.failResetOnce = true;
    await expectLater(coordinator.dispose(), throwsStateError);
    await coordinator.dispose();
    expect(backend.calls.where((call) => call == 'reset').length, 3);
  });

  test('slow verification cannot open after a newer request', () async {
    final aVerified = Completer<AndroidHdrSampleIdentity>();
    final backend = FakeBackend();
    final coordinator = AndroidHdrOpenCoordinator(backend,
        verifier: (source, _) =>
            source == 'A' ? aVerified.future : Future.value(identity(source)));
    final a = coordinator.openSource('A');
    final b = coordinator.openSource('B');
    final bResult = await b;
    expect(bResult.identity.path, 'B');
    expect(bResult.presentationVerified, isFalse);
    aVerified.complete(identity('A'));
    await expectLater(a, throwsA(isA<OpenSuperseded>()));
    expect(backend.calls.where((call) => call == 'open:A'), isEmpty);
    await coordinator.dispose();
  });

  test('old native open finishes before newer request starts side effects',
      () async {
    final backend = FakeBackend()..heldOpen = Completer<void>();
    final coordinator = AndroidHdrOpenCoordinator(backend,
        verifier: (source, _) async => identity(source));
    final a = coordinator.openSource('A');
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(backend.calls, contains('open:A'));
    final b = coordinator.openSource('B');
    backend.heldOpen!.complete();
    await expectLater(a, throwsA(isA<OpenSuperseded>()));
    expect((await b).identity.path, 'B');
    expect(backend.calls, contains('open:B'));
    expect(backend.calls, isNot(contains('track:A')));
    await coordinator.dispose();
  });

  test('configuration failure resets, and later request recovers', () async {
    final backend = FakeBackend()..failConfigure = true;
    final coordinator = AndroidHdrOpenCoordinator(backend,
        verifier: (source, _) async => identity(source));
    await expectLater(coordinator.openSource('A'), throwsStateError);
    expect(backend.calls.sublist(backend.calls.length - 2), ['stop', 'reset']);
    backend.failConfigure = false;
    expect((await coordinator.openSource('B')).identity.path, 'B');
    await coordinator.dispose();
  });

  test('unsupported policy leaves currently playing media untouched', () async {
    final backend = FakeBackend();
    final coordinator = AndroidHdrOpenCoordinator(backend,
        verifier: (source, _) async => identity(source));
    await coordinator.openSource('A');
    final stopCount = backend.calls.where((call) => call == 'stop').length;
    backend.failValidate = true;
    await expectLater(coordinator.openSource('B'), throwsStateError);
    expect(backend.calls.where((call) => call == 'stop').length, stopCount);
    expect(backend.calls, isNot(contains('open:B')));
    await coordinator.dispose();
  });

  test('invalid successor rolls back superseded partial configuration',
      () async {
    final backend = FakeBackend()..heldConfigure = Completer<void>();
    final coordinator = AndroidHdrOpenCoordinator(backend,
        verifier: (source, _) async => identity(source));
    final a = coordinator.openSource('A');
    while (!backend.calls.contains('configure:A')) {
      await Future<void>.delayed(Duration.zero);
    }
    backend.failValidate = true;
    final b = coordinator.openSource('B');
    backend.heldConfigure!.complete();
    await expectLater(a, throwsA(isA<OpenSuperseded>()));
    await expectLater(b, throwsStateError);
    expect(backend.calls, [
      'stop',
      'reset',
      'prepare:A',
      'configure:A',
      'stop',
      'reset',
    ]);
    expect(backend.calls, isNot(contains('open:A')));
    expect(backend.calls, isNot(contains('open:B')));
    await coordinator.dispose();
  });

  test('preparation failure of successor still rolls back partial config',
      () async {
    final backend = FakeBackend()..heldConfigure = Completer<void>();
    final coordinator =
        AndroidHdrOpenCoordinator(backend, verifier: (source, _) async {
      if (source == 'B') throw StateError('unknown sample');
      return identity(source);
    });
    final a = coordinator.openSource('A');
    while (!backend.calls.contains('configure:A')) {
      await Future<void>.delayed(Duration.zero);
    }
    final b = coordinator.openSource('B');
    await expectLater(b, throwsStateError);
    backend.heldConfigure!.complete();
    await expectLater(a, throwsA(isA<OpenSuperseded>()));
    expect(backend.calls, [
      'stop',
      'reset',
      'prepare:A',
      'configure:A',
      'stop',
      'reset',
    ]);
    await coordinator.dispose();
  });

  test('output preparation is serialized and superseded before configure',
      () async {
    final backend = FakeBackend()..heldPrepareOutput = Completer<void>();
    final coordinator = AndroidHdrOpenCoordinator(backend,
        verifier: (source, _) async => identity(source));
    final a = coordinator.openSource('A');
    while (!backend.calls.contains('prepare:A')) {
      await Future<void>.delayed(Duration.zero);
    }
    final b = coordinator.openSource('B');
    backend.heldPrepareOutput!.complete();
    await expectLater(a, throwsA(isA<OpenSuperseded>()));
    expect((await b).identity.path, 'B');
    expect(backend.calls.indexOf('prepare:A'),
        lessThan(backend.calls.indexOf('prepare:B')));
    expect(backend.calls, isNot(contains('configure:A')));
    await coordinator.dispose();
  });

  test('output timeout releases the queue for a later request', () async {
    final backend = FakeBackend()..heldOutput = Completer<void>();
    final coordinator = AndroidHdrOpenCoordinator(backend,
        outputTimeout: const Duration(milliseconds: 20),
        verifier: (source, _) async => identity(source));
    await expectLater(
        coordinator.openSource('A'), throwsA(isA<TimeoutException>()));
    expect(backend.calls, isNot(contains('open:A')));
    backend.heldOutput = null;
    expect((await coordinator.openSource('B')).identity.path, 'B');
    await coordinator.dispose();
  });

  test('dispose invalidates an in-flight request', () async {
    final backend = FakeBackend()..heldOpen = Completer<void>();
    final coordinator = AndroidHdrOpenCoordinator(backend,
        verifier: (source, _) async => identity(source));
    final open = coordinator.openSource('A');
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    final disposing = coordinator.dispose();
    backend.heldOpen!.complete();
    await expectLater(open, throwsA(isA<OpenSuperseded>()));
    await disposing;
    expect(backend.calls, isNot(contains('track:A')));
  });

  test('delayed command from an older session cannot affect new media',
      () async {
    final backend = FakeBackend();
    final coordinator = AndroidHdrOpenCoordinator(backend,
        verifier: (source, _) async => identity(source));
    final a = await coordinator.openSource('A');
    final b = coordinator.openSource('B');
    await expectLater(
      coordinator.runForCurrent(a, () async => backend.calls.add('seek:A')),
      throwsA(isA<OpenSuperseded>()),
    );
    await b;
    expect(backend.calls, isNot(contains('seek:A')));
    await coordinator.dispose();
  });

  test('staged sessions release old bytes after stop and failed bytes on error',
      () async {
    final directory = await Directory.systemTemp.createTemp('hdr-open-stage-');
    addTearDown(() => directory.delete(recursive: true));
    final aFile = File('${directory.path}/A.mp4');
    final bFile = File('${directory.path}/B.mp4');
    final cFile = File('${directory.path}/C.mp4');
    await aFile.writeAsString('movie A');
    await bFile.writeAsString('movie B');
    await cFile.writeAsString('movie C');
    final catalog = <String, AndroidHdrSample>{
      sha256.convert(await aFile.readAsBytes()).toString():
          AndroidHdrSample.hdr10,
      sha256.convert(await bFile.readAsBytes()).toString():
          AndroidHdrSample.dolbyVisionP84,
      sha256.convert(await cFile.readAsBytes()).toString():
          AndroidHdrSample.dolbyVisionP5,
    };
    final backend = FakeBackend();
    final coordinator = AndroidHdrOpenCoordinator.staged(
      backend,
      Directory('${directory.path}/private'),
      knownSha256: catalog,
    );
    final a = await coordinator.openSource(aFile.path);
    expect(await File(a.identity.path).exists(), isTrue);
    expect(a.identity.path, isNot(aFile.path));
    final b = await coordinator.openSource(bFile.path);
    expect(await File(a.identity.path).exists(), isFalse);
    expect(await File(b.identity.path).exists(), isTrue);
    backend.failConfigure = true;
    await expectLater(coordinator.openSource(cFile.path), throwsStateError);
    expect(await File(b.identity.path).exists(), isFalse);
    expect(await Directory('${directory.path}/private').list().isEmpty, isTrue);
    backend.failConfigure = false;
    final again = await coordinator.openSource(aFile.path);
    final firstDispose = coordinator.dispose();
    final secondDispose = coordinator.dispose();
    expect(identical(firstDispose, secondDispose), isTrue);
    await Future.wait([firstDispose, secondDispose]);
    expect(await File(again.identity.path).exists(), isFalse);
  });

  test('cleanup failure reports original open error without hanging', () async {
    final directory = await Directory.systemTemp.createTemp('hdr-cleanup-');
    addTearDown(() => directory.delete(recursive: true));
    final source = File('${directory.path}/source.mp4');
    await source.writeAsString('movie');
    final digest = sha256.convert(await source.readAsBytes()).toString();
    final backend = FakeBackend()
      ..failConfigure = true
      ..removeStagedOnConfigureFailure = true;
    final coordinator = AndroidHdrOpenCoordinator.staged(
      backend,
      Directory('${directory.path}/private'),
      knownSha256: {digest: AndroidHdrSample.hdr10},
    );
    await expectLater(
      coordinator.openSource(source.path),
      throwsA(isA<StateError>().having(
        (error) => error.message,
        'message',
        'configuration failed',
      )),
    );
    expect(coordinator.cleanupFailures, isNotEmpty);
    await coordinator.dispose();
  });

  test('dispose waits for a staging attempt to clean up', () async {
    final directory = await Directory.systemTemp.createTemp('hdr-dispose-');
    addTearDown(() => directory.delete(recursive: true));
    final source = File('${directory.path}/source.mp4');
    await source.writeAsBytes(List<int>.filled(1024 * 1024, 7));
    final privateRoot = Directory('${directory.path}/private');
    final backend = FakeBackend();
    final coordinator = AndroidHdrOpenCoordinator.staged(backend, privateRoot);
    final opening = coordinator.openSource(source.path);
    final openingCheck = expectLater(opening, throwsStateError);
    await Future<void>.delayed(Duration.zero);
    await coordinator.dispose();
    await openingCheck;
    expect(await privateRoot.list().isEmpty, isTrue);
    expect(backend.calls, isNot(contains('open:${source.path}')));
  });

  test('dispose retries a transient backend stop failure', () async {
    final directory = await Directory.systemTemp.createTemp('hdr-stop-retry-');
    addTearDown(() => directory.delete(recursive: true));
    final source = File('${directory.path}/source.mp4');
    await source.writeAsString('movie');
    final digest = sha256.convert(await source.readAsBytes()).toString();
    final backend = FakeBackend();
    final coordinator = AndroidHdrOpenCoordinator.staged(
      backend,
      Directory('${directory.path}/private'),
      knownSha256: {digest: AndroidHdrSample.hdr10},
    );
    final opened = await coordinator.openSource(source.path);
    backend.failStopOnce = true;
    await expectLater(coordinator.dispose(), throwsStateError);
    expect(await File(opened.identity.path).exists(), isTrue);
    await coordinator.dispose();
    expect(await File(opened.identity.path).exists(), isFalse);
  });
}
