import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit_hdr_lab/common/sources/android_hdr_sample_identity.dart';

void main() {
  test(
      'stale HDR copies are removed without touching this process or other data',
      () async {
    final parent = await Directory.systemTemp.createTemp('hdr-sessions-');
    addTearDown(() => parent.delete(recursive: true));
    final stale = await parent.createTemp('session-456-');
    final legacy = await parent.createTemp('session-');
    final current = await parent.createTemp('session-123-');
    final unrelated = await parent.createTemp('other-');
    await File('${stale.path}/sample.mp4').writeAsString('stale');
    await File('${current.path}/sample.mp4').writeAsString('live');

    expect(await cleanupStaleAndroidHdrSessions(parent, currentPid: 123), 2);
    expect(await stale.exists(), isFalse);
    expect(await legacy.exists(), isFalse);
    expect(await current.exists(), isTrue);
    expect(await unrelated.exists(), isTrue);
  });

  test('identity follows bytes across names and rejects altered content',
      () async {
    final directory = await Directory.systemTemp.createTemp('hdr-identity-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/not-p5.mp4');
    await file.writeAsString('fixed sample bytes');
    final digest = sha256.convert(await file.readAsBytes()).toString();
    final catalog = {digest: AndroidHdrSample.dolbyVisionP5};

    final first =
        await identifyAndroidHdrSample(file.path, knownSha256: catalog);
    expect(first.sample, AndroidHdrSample.dolbyVisionP5);
    final renamed = await file.rename('${directory.path}/hdr10.mp4');
    final second = await identifyAndroidHdrSample(renamed.uri.toString(),
        knownSha256: catalog);
    expect(second.sha256, digest);

    await renamed.writeAsString('changed sample bytes');
    await expectLater(
      identifyAndroidHdrSample(renamed.path, knownSha256: catalog),
      throwsStateError,
    );
  });

  test('cancellation and non-local URLs fail closed', () async {
    final directory = await Directory.systemTemp.createTemp('hdr-cancel-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/sample.mp4');
    await file.writeAsString('sample');
    await expectLater(
      identifyAndroidHdrSample(file.path, cancelled: () => true),
      throwsStateError,
    );
    await expectLater(
      identifyAndroidHdrSample('https://example.invalid/video.mp4'),
      throwsUnsupportedError,
    );
  });

  test('staged playback path retains verified bytes after source replacement',
      () async {
    final directory = await Directory.systemTemp.createTemp('hdr-stage-');
    addTearDown(() => directory.delete(recursive: true));
    final source = File('${directory.path}/source.mp4');
    await source.writeAsString('verified movie');
    final digest = sha256.convert(await source.readAsBytes()).toString();
    final stagingRoot = Directory('${directory.path}/private');
    final staged = await stageAndroidHdrSample(
      source.path,
      stagingRoot,
      knownSha256: {digest: AndroidHdrSample.hdr10},
    );
    await source.writeAsString('replacement movie');
    expect(await File(staged.identity.path).readAsString(), 'verified movie');
    expect(staged.identity.sha256, digest);
    await staged.dispose();
    expect(await File(staged.identity.path).exists(), isFalse);
  });

  test('failed or cancelled staging removes its private partial copy',
      () async {
    final directory = await Directory.systemTemp.createTemp('hdr-reject-');
    addTearDown(() => directory.delete(recursive: true));
    final source = File('${directory.path}/source.mp4');
    await source.writeAsString('unknown movie');
    final stagingRoot = Directory('${directory.path}/private');
    await expectLater(
      stageAndroidHdrSample(source.path, stagingRoot),
      throwsStateError,
    );
    expect(await stagingRoot.list().isEmpty, isTrue);
    await expectLater(
      stageAndroidHdrSample(source.path, stagingRoot, cancelled: () => true),
      throwsStateError,
    );
    expect(await stagingRoot.list().isEmpty, isTrue);
  });

  test('staged cleanup can retry after a transient deletion failure', () async {
    final directory = await Directory.systemTemp.createTemp('hdr-retry-');
    addTearDown(() => directory.delete(recursive: true));
    final source = File('${directory.path}/source.mp4');
    await source.writeAsString('known movie');
    final digest = sha256.convert(await source.readAsBytes()).toString();
    final staged = await stageAndroidHdrSample(
      source.path,
      Directory('${directory.path}/private'),
      knownSha256: {digest: AndroidHdrSample.hdr10},
    );
    final stageDir = File(staged.identity.path).parent;
    await stageDir.delete(recursive: true);
    await expectLater(staged.dispose(), throwsA(isA<FileSystemException>()));
    await stageDir.create();
    await staged.dispose();
    expect(await stageDir.exists(), isFalse);
  });
}
