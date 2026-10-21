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
  PlatformPlayer? get platform => null;
  _Player({int? width = 640, int? height = 360})
      : state = PlayerState(width: width, height: height);
  @override
  final PlayerState state;
  @override
  final _Streams stream = _Streams();
  @override
  Future<void> dispose({bool synchronized = true}) async {}
}

class _Output extends PlatformVideoController {
  _Output(Player player)
      : super(
          player,
          VideoControllerConfiguration(
            vo: 'mediacodec_embed',
            android: AndroidVideoOptions(usePlatformView: true),
          ),
        );

  @override
  Future<void> setSize({int? width, int? height}) async {}
}

class _Controller extends Fake implements VideoController {
  _Controller({int? width = 640, int? height = 360, bool platformView = false})
      : player = _Player(width: width, height: height) {
    if (platformView) notifier.value = _Output(player);
  }
  @override
  final _Player player;
  @override
  final id = ValueNotifier<int?>(null);
  @override
  final rect = ValueNotifier<Rect?>(null);
  @override
  final notifier = ValueNotifier<PlatformVideoController?>(null);
  @override
  void removeTextureLayoutOwner(Object owner) {}
  Future<void> close() async {
    id.dispose();
    rect.dispose();
    final output = notifier.value;
    if (output != null) {
      output.id.dispose();
      output.rect.dispose();
      output.nativeSurfaceActiveNotifier.dispose();
    }
    notifier.dispose();
    await player.stream.widths.close();
    await player.stream.heights.close();
  }
}

void main() {
  testWidgets(
      'explicit view mounts before review and follows controller replacement',
      (tester) async {
    final a = _Controller();
    final b = _Controller();
    final session = TestSession();
    final binding = RoutedVideoPlayback.forTesting(a.player, session: session);
    await tester.pumpWidget(MaterialApp(
        home: Center(
            child: SizedBox(
                width: 400,
                height: 300,
                child:
                    FittedBox(child: RoutedSimpleVideo(playback: binding))))));
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
    await binding.dispose();
    session.closeNotifiers();
    await a.close();
    await b.close();
  });

  testWidgets('unknown dimensions keep the viewport through controller changes',
      (tester) async {
    final a = _Controller(width: 0, height: 0, platformView: true);
    final b = _Controller(width: 0, height: 0, platformView: true);
    final session = TestSession();
    final binding = RoutedVideoPlayback.forTesting(a.player, session: session);
    const viewport = Size(400, 300);

    await tester.pumpWidget(MaterialApp(
      home: Center(
        child: SizedBox(
          width: viewport.width,
          height: viewport.height,
          child: FittedBox(
            child: RoutedSimpleVideo(playback: binding, viewport: viewport),
          ),
        ),
      ),
    ));
    expect(find.byType(Video), findsNothing);
    expect(tester.getSize(find.byType(RoutedSimpleVideo)), viewport);

    session.controller.value = a;
    await tester.pump();
    expect(binding.ready.value, isFalse);
    expect(find.byType(Video), findsOneWidget);
    expect(tester.widget<Video>(find.byType(Video)).controller, same(a));
    expect(tester.getSize(find.byType(RoutedSimpleVideo)), viewport);
    expect(tester.getSize(find.byType(SimpleVideo)), viewport);

    session.controller.value = null;
    await tester.pump();
    expect(find.byType(Video), findsNothing);
    expect(tester.getSize(find.byType(RoutedSimpleVideo)), viewport);

    session.controller.value = b;
    await tester.pump();
    expect(binding.ready.value, isFalse);
    expect(find.byType(Video), findsOneWidget);
    expect(tester.widget<Video>(find.byType(Video)).controller, same(b));
    expect(tester.getSize(find.byType(RoutedSimpleVideo)), viewport);
    expect(tester.getSize(find.byType(SimpleVideo)), viewport);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    await binding.dispose();
    session.closeNotifiers();
    await a.close();
    await b.close();
  });
}
