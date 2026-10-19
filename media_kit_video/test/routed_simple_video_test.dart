import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'routed_video_playback_test.dart' show TestSession;

class _Streams extends Fake implements PlayerStream {
  final widths = StreamController<int?>.broadcast(sync: true);
  final heights = StreamController<int?>.broadcast(sync: true);
  @override
  Stream<int?> get width => widths.stream;
  @override
  Stream<int?> get height => heights.stream;
}
class _Player extends Fake implements Player {
  @override
  final state = PlayerState(width: 640, height: 360);
  @override
  final stream = _Streams();
  @override
  Future<void> dispose({bool synchronized = true}) async {}
}
class _Controller extends Fake implements VideoController {
  @override
  final player = _Player();
  @override
  final id = ValueNotifier<int?>(null);
  @override
  final rect = ValueNotifier<Rect?>(null);
  @override
  final notifier = ValueNotifier<PlatformVideoController?>(null);
  @override
  void removeTextureLayoutOwner(Object owner) {}
  Future<void> close() async {
    id.dispose(); rect.dispose(); notifier.dispose();
    await player.stream.widths.close(); await player.stream.heights.close();
  }
}

void main() {
  testWidgets('explicit view mounts before review and follows controller replacement', (tester) async {
    final a = _Controller(), b = _Controller();
    final session = TestSession();
    final binding = RoutedVideoPlayback.forTesting(a.player, session: session);
    await tester.pumpWidget(MaterialApp(home: Center(child: SizedBox(
        width: 400, height: 300,
        child: FittedBox(child: RoutedSimpleVideo(playback: binding))))));
    expect(find.byType(Video), findsNothing);
    session.controller.value = a;
    await tester.pump();
    expect(binding.ready.value, isFalse);
    expect(find.byType(Video), findsOneWidget);
    expect(tester.widget<Video>(find.byType(Video)).controller, same(a));
    session.controller.value = b;
    await tester.pump();
    expect(tester.widget<Video>(find.byType(Video)).controller, same(b));
    expect(a.player.stream.widths.hasListener, isFalse);
    session.controller.value = null;
    await tester.pump();
    expect(find.byType(Video), findsNothing);
    expect(b.player.stream.widths.hasListener, isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await binding.dispose(); session.closeNotifiers();
    await a.close(); await b.close();
  });
}
