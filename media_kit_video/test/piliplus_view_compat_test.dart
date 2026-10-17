import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:media_kit_video/src/video/simple_video.dart';

class _Streams extends Fake implements PlayerStream {
  final widths = StreamController<int?>.broadcast(sync: true);
  final heights = StreamController<int?>.broadcast(sync: true);
  final subtitles = StreamController<List<String>>.broadcast(sync: true);
  @override
  Stream<int?> get width => widths.stream;
  @override
  Stream<int?> get height => heights.stream;
  @override
  Stream<List<String>> get subtitle => subtitles.stream;
  Future<void> close() async {
    await widths.close();
    await heights.close();
    await subtitles.close();
  }
}

class _Player extends Fake implements Player {
  _Player({int? width, int? height, List<String> subtitle = const ['', '']})
      : state = PlayerState(width: width, height: height, subtitle: subtitle);
  @override
  final PlayerState state;
  @override
  final _Streams stream = _Streams();
}

class _Controller extends Fake implements VideoController {
  _Controller(this.player);
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
    notifier.dispose();
    await player.stream.close();
  }
}

Widget _host(Widget child, {double dpr = 1}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(devicePixelRatio: dpr),
        child: Center(child: SizedBox(width: 400, height: 300, child: child)),
      ),
    );

void main() {
  test('intrinsic dimensions retain source pixels, dpr and requested ratio', () {
    expect(simpleVideoLogicalSize(rect: const Rect.fromLTWH(0, 0, 1920, 1080),
        devicePixelRatio: 2), const Size(960, 540));
    expect(simpleVideoLogicalSize(width: 1920, height: 1080,
        devicePixelRatio: 2, aspectRatio: 4 / 3), const Size(720, 540));
    expect(simpleVideoLogicalSize(devicePixelRatio: 2), const Size(.5, .5));
    expect(() => simpleVideoLogicalSize(devicePixelRatio: 0), throwsArgumentError);
    expect(() => simpleVideoLogicalSize(devicePixelRatio: 1, aspectRatio: double.nan), throwsArgumentError);
  });

  testWidgets('unknown video dimensions do not prevent mounting the renderer', (tester) async {
    final controller = _Controller(_Player());
    await tester.pumpWidget(_host(FittedBox(child: SimpleVideo(controller: controller))));
    expect(find.byType(Video), findsOneWidget);
    final renderer = tester.widget<Video>(find.byType(Video));
    expect(renderer.controls, isNull);
    expect(renderer.wakelock, isFalse);
    expect(renderer.pauseUponEnteringBackgroundMode, isFalse);
    expect(renderer.subtitleViewConfiguration.visible, isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await controller.close();
  });

  testWidgets('intrinsic video follows rect changes and detaches old player subscriptions', (tester) async {
    final a = _Controller(_Player(width: 1920, height: 1080));
    final b = _Controller(_Player(width: 640, height: 360));
    a.rect.value = const Rect.fromLTWH(0, 0, 1920, 1080);
    await tester.pumpWidget(_host(FittedBox(child: SimpleVideo(controller: a)), dpr: 2));
    expect(tester.widget<Video>(find.byType(Video)).width, 960);
    a.rect.value = const Rect.fromLTWH(0, 0, 1280, 720);
    await tester.pump();
    await tester.pump();
    expect(tester.widget<Video>(find.byType(Video)).width, 640);
    await tester.pumpWidget(_host(FittedBox(child: SimpleVideo(controller: b)), dpr: 2));
    await tester.pump();
    expect(a.player.stream.widths.hasListener, isFalse);
    expect(b.player.stream.widths.hasListener, isTrue);
    await tester.pumpWidget(const SizedBox());
    expect(b.player.stream.widths.hasListener, isFalse);
    await a.close();
    await b.close();
  });

  testWidgets('stroke and explicit pre-scaled text are preserved', (tester) async {
    final controller = _Controller(_Player(subtitle: const ['hello', '']));
    await tester.pumpWidget(_host(SubtitleView(controller: controller,
      configuration: const SubtitleViewConfiguration(
        textScaleFactor: 1, strokeStyle: TextStyle(fontSize: 24),
      ))));
    final texts = tester.widgetList<Text>(find.text('hello')).toList();
    expect(texts, hasLength(2));
    expect(texts.every((text) => text.textScaler!.scale(20) == 20), isTrue);
    expect(find.ancestor(of: find.text('hello').first, matching: find.byType(ExcludeSemantics)), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await controller.close();
  });

  testWidgets('subtitle drag clamps and publishes final padding', (tester) async {
    final controller = _Controller(_Player(subtitle: const ['drag me', '']));
    EdgeInsets? reported;
    await tester.pumpWidget(_host(SubtitleView(
      controller: controller, enableDragSubtitle: true,
      onUpdatePadding: (value) => reported = value,
      configuration: const SubtitleViewConfiguration(textScaleFactor: 1),
    )));
    final gesture = tester.widget<GestureDetector>(find.descendant(
      of: find.byType(SubtitleView), matching: find.byType(GestureDetector)));
    gesture.onVerticalDragUpdate!(DragUpdateDetails(delta: const Offset(0, -500), globalPosition: Offset.zero));
    await tester.pump();
    gesture.onVerticalDragEnd!(DragEndDetails());
    expect(reported!.bottom, 200);
    await tester.pumpWidget(const SizedBox());
    await controller.close();
  });

  testWidgets('subtitle controller replacement and hidden state do not retain stale text', (tester) async {
    final a = _Controller(_Player(subtitle: const ['first', '']));
    final b = _Controller(_Player(subtitle: const ['second', '']));
    await tester.pumpWidget(_host(SubtitleView(controller: a,
      configuration: const SubtitleViewConfiguration(textScaleFactor: 1))));
    expect(find.text('first'), findsOneWidget);
    await tester.pumpWidget(_host(SubtitleView(controller: b,
      configuration: const SubtitleViewConfiguration(textScaleFactor: 1))));
    expect(a.player.stream.subtitles.hasListener, isFalse);
    expect(find.text('second'), findsOneWidget);
    a.player.stream.subtitles.add(['stale', '']);
    await tester.pump();
    expect(find.text('stale'), findsNothing);
    await tester.pumpWidget(_host(SubtitleView(controller: b,
      configuration: const SubtitleViewConfiguration(visible: false))));
    expect(find.text('second'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await a.close();
    await b.close();
  });

  test('configuration copying and equality include compatibility fields', () {
    const config = SubtitleViewConfiguration(textScaleFactor: 1,
        strokeStyle: TextStyle(fontSize: 20));
    expect(config.copyWith(), config);
    expect(config.copyWith().hashCode, config.hashCode);
    expect(config.copyWith(visible: false), isNot(config));
    final modern = config.copyWith(textScaler: const TextScaler.linear(2));
    expect(modern.textScaleFactor, isNull);
    expect(modern.textScaler!.scale(10), 20);
    final legacy = modern.copyWith(textScaleFactor: 1);
    expect(legacy.textScaler, isNull);
    expect(legacy.textScaleFactor, 1);
  });
}
