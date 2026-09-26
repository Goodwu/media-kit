import 'package:media_kit/media_kit.dart';
import 'package:test/test.dart';

class RecordingPlayer extends PlatformPlayer {
  RecordingPlayer() : super(configuration: const PlayerConfiguration());

  void started(int entryId) => recordFileStarted(entryId);
  void loaded() => recordFileLoaded();
}

void main() {
  test('waiter requires a later event for the requested playlist entry',
      () async {
    final player = RecordingPlayer();
    expect(player.fileLoadedEpoch, 0);
    player.started(10);
    final waiting = player.waitForFileLoadedEntryAfter(10, 0);
    player.loaded();
    expect((await waiting).epoch, 1);
    expect((await player.waitForFileLoadedEntryAfter(10, 0)).epoch, 1);
    final next = player.waitForFileLoadedEntryAfter(11, 1);
    player.started(11);
    player.loaded();
    expect((await next).epoch, 2);
    await player.dispose();
  });

  test('delayed A event cannot satisfy B waiter', () async {
    final player = RecordingPlayer();
    final b = player.waitForFileLoadedEntryAfter(22, 0);
    var completed = false;
    b.then((_) => completed = true);
    player.started(21);
    player.loaded();
    await Future<void>.delayed(Duration.zero);
    expect(completed, isFalse);
    player.started(22);
    player.loaded();
    expect((await b).playlistEntryId, 22);
    await player.dispose();
  });
}
