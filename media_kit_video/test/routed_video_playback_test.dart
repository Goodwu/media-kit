import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

class TestPlayer extends Fake implements Player {
  final calls = <String>[];
  Completer<void>? heldSeek;
  @override
  Future<void> open(Playable media, {bool play = true, bool synchronized = true}) async {
    calls.add('open:$play');
  }
  @override
  Future<void> stop({bool open = false, bool notify = true, bool synchronized = true,
      bool waitForVideoControllerInitialization = true}) async { calls.add('stop'); }
  @override
  Future<void> play({bool synchronized = true}) async { calls.add('play'); }
  @override
  Future<void> pause({bool synchronized = true}) async { calls.add('pause'); }
  @override
  Future<void> seek(Duration position, {bool synchronized = true}) async {
    calls.add('seek:${position.inSeconds}');
    await heldSeek?.future;
  }
  @override
  Future<void> dispose({bool synchronized = true}) async { calls.add('dispose'); }
}

class TestSession extends Fake implements HdrVideoSession {
  @override
  final ValueNotifier<VideoController?> controller = ValueNotifier(null);
  @override
  final ValueNotifier<HdrOutputReport> report = ValueNotifier(const HdrOutputReport());
  final requests = <Completer<void>>[];
  final calls = <String>[];
  final hints = <HdrSourceDescriptor?>[];
  bool failDispose = false;
  @override
  Future<void> open(Media media, {HdrSourceDescriptor? hint,
    VideoSourceSpec? sourceSpec, VideoOutputTarget? target,
    EffectiveVideoRouteOptions? options, bool play = true, Duration? start}) {
    calls.add('open:$play:${start?.inSeconds}');
    hints.add(hint);
    final pending = Completer<void>();
    requests.add(pending);
    report.value = HdrOutputReport(generation: requests.length);
    return pending.future;
  }
  void accept(int index) {
    report.value = HdrOutputReport(generation: index + 1, verified: true);
    requests[index].complete();
  }
  @override
  Future<void> dispose() async {
    calls.add('dispose');
    if (failDispose) throw StateError('retained output owner');
    for (final request in requests) {
      if (!request.isCompleted) request.complete();
    }
  }
  void closeNotifiers() { controller.dispose(); report.dispose(); }
}

Future<void> turn() => Future<void>.delayed(Duration.zero);

void main() {
  test('legacy bridge inherits SDR embed default and preserves explicit copy intent', () {
    for (final hwdec in [null, 'auto-safe', 'mediacodec,auto-safe', 'mediacodec,auto-copy']) {
      final options = routeOptionsForLegacyConfiguration(
          VideoControllerConfiguration(hwdec: hwdec));
      expect(options.importPreference, VideoImportPreference.auto);
      expect(options.sdrEmbed, isTrue);
    }
    for (final hwdec in ['mediacodec-copy', 'auto-copy', 'mediacodec-copy,auto-copy']) {
      final options = routeOptionsForLegacyConfiguration(
          VideoControllerConfiguration(hwdec: hwdec));
      expect(options.importPreference, VideoImportPreference.preferCopy);
      expect(options.sdrEmbed, isTrue);
    }
    final options = routeOptionsForLegacyConfiguration(
        const VideoControllerConfiguration(enableHardwareAcceleration: false));
    expect(options.decode, const VideoRouteSelection.require(VideoDecodeTarget.software));
    expect(options.sdrEmbed, isTrue);
  });

  test('pending open mounts independently; only latest intent plays after review', () async {
    final player = TestPlayer(), session = TestSession();
    final binding = RoutedVideoPlayback.forTesting(player, session: session);
    final opening = binding.open(Media('test://a', start: const Duration(seconds: 3)));
    await turn();
    expect(session.calls, ['open:false:3']);
    await binding.pause();
    await binding.seek(const Duration(seconds: 9));
    expect(player.calls, isEmpty);
    expect(binding.ready.value, isFalse);
    session.accept(0);
    await opening;
    expect(binding.ready.value, isTrue);
    expect(player.calls, contains('seek:9'));
    expect(player.calls, isNot(contains('play')));
    await binding.play();
    expect(player.calls.last, 'play');
    await binding.dispose();
    expect(session.calls.last, 'dispose');
    expect(player.calls.last, 'dispose');
    session.closeNotifiers();
  });

  test('sourceHint reaches the session open unmodified', () async {
    final player = TestPlayer(), session = TestSession();
    final binding = RoutedVideoPlayback.forTesting(player, session: session);
    const hint = HdrSourceDescriptor(
        codec: 'hevc', transfer: 'hlg',
        dynamicMetadata: HdrDynamicMetadata.dolbyVision,
        dvProfile: 8, dvCompatibilityId: 4);
    final opening = binding.open(Media('test://a'), sourceHint: hint);
    await turn();
    expect(session.hints, const [hint]);
    session.accept(0);
    await opening;
    await binding.dispose();
    session.closeNotifiers();
  });

  test('verifiedSourceHint stays null until verified, then exposes facts', () async {
    final player = TestPlayer(), session = TestSession();
    final binding = RoutedVideoPlayback.forTesting(player, session: session);
    expect(binding.verifiedSourceHint, isNull);
    const hint = HdrSourceDescriptor(
        codec: 'hevc', transfer: 'hlg',
        dynamicMetadata: HdrDynamicMetadata.dolbyVision,
        dvProfile: 8, dvCompatibilityId: 4);
    final opening = binding.open(Media('test://a'), sourceHint: hint);
    await turn();
    // The session published a fresh unverified report for the new generation.
    expect(binding.verifiedSourceHint, isNull);
    session.accept(0);
    await opening;
    expect(binding.verifiedSourceHint, isNull); // no source in the report
    session.report.value = const HdrOutputReport(
        generation: 1, verified: true, source: hint);
    expect(binding.verifiedSourceHint, const HdrSourceDescriptor(
        codec: 'hevc', transfer: 'hlg',
        dynamicMetadata: HdrDynamicMetadata.dolbyVision,
        dvProfile: 8, dvCompatibilityId: 4));
    session.report.value = HdrOutputReport(
        generation: 1, verified: true, sourceFacts: HdrSourceFacts.fromHint(null));
    // An all-unknown description is no hint: the probe path stays eligible.
    expect(binding.verifiedSourceHint, isNull);
    await binding.dispose();
    session.closeNotifiers();
  });

  test('internal rebuild restores latest intent only after a new reviewed report', () async {
    final player = TestPlayer(), session = TestSession();
    final binding = RoutedVideoPlayback.forTesting(player, session: session);
    final opening = binding.open(Media('test://a'));
    await turn(); session.accept(0); await opening;
    player.calls.clear();
    session.report.value = const HdrOutputReport(generation: 2);
    await binding.pause();
    await binding.seek(const Duration(seconds: 7));
    expect(player.calls, isEmpty);
    session.report.value = const HdrOutputReport(generation: 2, verified: true);
    await turn();
    expect(player.calls, ['seek:7', 'pause']);
    await binding.dispose(); session.closeNotifiers();
  });

  test('new open supersedes old open without reviving old transport', () async {
    final player = TestPlayer(), session = TestSession();
    final binding = RoutedVideoPlayback.forTesting(player, session: session);
    final a = binding.open(Media('test://a'));
    final failure = expectLater(a, throwsA(isA<RoutedOpenSuperseded>()));
    await turn();
    final b = binding.open(Media('test://b'), play: false);
    await turn();
    session.requests[0].complete();
    await failure;
    expect(player.calls, isEmpty);
    session.accept(1); await b;
    expect(player.calls, isNot(contains('play')));
    await binding.dispose(); session.closeNotifiers();
  });

  test('blocked report is an error, not a successful open or readiness', () async {
    final player = TestPlayer(), session = TestSession();
    final binding = RoutedVideoPlayback.forTesting(player, session: session);
    final seen = <Object>[];
    final subscription = binding.errors.listen(seen.add);
    final opening = binding.open(Media('test://blocked'));
    final error = StateError('blocked route');
    final failed = expectLater(opening, throwsA(same(error)));
    await turn();
    session.report.value = HdrOutputReport(generation: 1, error: error);
    session.requests.single.complete();
    await failed; await turn();
    expect(binding.ready.value, isFalse);
    expect(player.calls, isEmpty);
    expect(seen, [error]);
    await subscription.cancel(); await binding.dispose(); session.closeNotifiers();
  });

  test('dispose cancels pending open and closes admission synchronously', () async {
    final player = TestPlayer(), session = TestSession();
    final binding = RoutedVideoPlayback.forTesting(player, session: session);
    final opening = binding.open(Media('test://a'));
    final cancelled = expectLater(opening, throwsA(isA<RoutedOpenSuperseded>()));
    await turn();
    final closing = binding.dispose();
    expect(() => binding.play(), throwsStateError);
    await closing; await cancelled;
    expect(player.calls, ['dispose']);
    session.closeNotifiers();
  });

  test('failed output disposal never destroys the raw player and is retryable', () async {
    final player = TestPlayer(), session = TestSession()..failDispose = true;
    final binding = RoutedVideoPlayback.forTesting(player, session: session);
    await expectLater(binding.dispose(), throwsStateError);
    expect(player.calls, isEmpty);
    expect(() => binding.open(Media('test://a')), throwsStateError);
    session.failDispose = false;
    await binding.dispose();
    expect(player.calls, ['dispose']);
    session.closeNotifiers();
  });

  test('non-Android compatibility does not pretend to verify an HDR session', () async {
    final player = TestPlayer();
    final binding = RoutedVideoPlayback.forTesting(player);
    await binding.open(Media('test://legacy'), play: false);
    expect(player.calls, ['open:false', 'pause']);
    await binding.play(); await binding.dispose();
    expect(player.calls.last, 'dispose');
  });
  test('audio-only source retires video owner; returning to video creates one owner', () async {
    final player = TestPlayer();
    final sessions = <TestSession>[];
    final binding = RoutedVideoPlayback.forTesting(player, sessionFactory: () {
      final session = TestSession(); sessions.add(session); return session;
    });
    final first = binding.open(Media('test://video'), play: false);
    await turn(); sessions.single.accept(0); await first;
    await binding.open(Media('test://audio'), video: false);
    expect(sessions.single.calls.last, 'dispose');
    expect(binding.controller.value, isNull);
    expect(player.calls, contains('open:false'));
    final next = binding.open(Media('test://video2'), play: false);
    await turn();
    expect(sessions.length, 2);
    sessions.last.accept(0); await next;
    await binding.dispose();
    for (final session in sessions) { session.closeNotifiers(); }
  });

  test('report view starts at the initial report and survives dispose', () async {
    final player = TestPlayer();
    final binding = RoutedVideoPlayback.forTesting(player);
    expect(binding.report.value, const HdrOutputReport());
    await binding.open(Media('test://legacy'), play: false);
    // No HDR session on this path: the view keeps the initial report.
    expect(binding.report.value, const HdrOutputReport());
    await binding.play(); await binding.dispose();
    // The view is never disposed itself and stays reset after closing.
    expect(binding.report.value, const HdrOutputReport());
    expect(player.calls.last, 'dispose');
  });

  test('report view forwards the mounted session report', () async {
    final player = TestPlayer(), session = TestSession();
    final binding = RoutedVideoPlayback.forTesting(player, session: session);
    final seen = <HdrOutputReport>[];
    void record() => seen.add(binding.report.value);
    binding.report.addListener(record);
    expect(binding.report.value.generation, 0);
    final opening = binding.open(Media('test://a'));
    await turn();
    // The session published an unverified report for the new generation.
    expect(binding.report.value.generation, 1);
    expect(binding.report.value.verified, isFalse);
    session.accept(0); await opening;
    expect(binding.report.value.generation, 1);
    expect(binding.report.value.verified, isTrue);
    expect(seen.last.generation, 1);
    expect(seen.last.verified, isTrue);
    await binding.dispose();
    expect(binding.report.value, const HdrOutputReport());
    expect(seen.last, const HdrOutputReport());
    binding.report.removeListener(record);
    session.closeNotifiers();
  });

  test('report view resets on session retirement and follows the successor', () async {
    final player = TestPlayer();
    final sessions = <TestSession>[];
    final binding = RoutedVideoPlayback.forTesting(player, sessionFactory: () {
      final session = TestSession(); sessions.add(session); return session;
    });
    expect(binding.report.value, const HdrOutputReport());
    final first = binding.open(Media('test://video'), play: false);
    await turn();
    expect(sessions.length, 1);
    expect(binding.report.value.generation, 1);
    expect(binding.report.value.verified, isFalse);
    sessions.single.accept(0); await first;
    expect(binding.report.value.verified, isTrue);
    await binding.open(Media('test://audio'), video: false);
    // Retirement resets the view: the old session's last report must not leak.
    expect(binding.report.value, const HdrOutputReport());
    final next = binding.open(Media('test://video2'), play: false);
    await turn();
    expect(sessions.length, 2);
    // The successor's own fresh report is forwarded after the remount.
    expect(binding.report.value.generation, 1);
    expect(binding.report.value.verified, isFalse);
    sessions.last.accept(0); await next;
    expect(binding.report.value.verified, isTrue);
    await binding.dispose();
    expect(binding.report.value, const HdrOutputReport());
    for (final session in sessions) { session.closeNotifiers(); }
  });

}
