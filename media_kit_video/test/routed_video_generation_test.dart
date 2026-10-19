import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'routed_video_playback_test.dart' show TestPlayer, TestSession, turn;

void main() {
  test('old verified report cannot authorize successor while previous seek drains', () async {
    final player = TestPlayer(), session = TestSession();
    final binding = RoutedVideoPlayback.forTesting(player, session: session);
    final a = binding.open(Media('test://a'));
    await turn(); session.accept(0); await a;
    player.calls.clear();
    final held = Completer<void>();
    player.heldSeek = held;
    final seeking = binding.seek(const Duration(seconds: 4));
    await turn();
    final b = binding.open(Media('test://b'));
    // This is still A's session report: B has not entered session.open yet.
    session.report.value = const HdrOutputReport(generation: 2, verified: true);
    expect(binding.ready.value, isFalse);
    expect(session.requests.length, 1);
    held.complete(); await seeking; await turn();
    expect(session.requests.length, 2);
    expect(binding.ready.value, isFalse);
    expect(player.calls, ['seek:4']);
    session.accept(1); await b;
    expect(player.calls, ['seek:4', 'play']);
    await binding.dispose(); session.closeNotifiers();
  });
}
