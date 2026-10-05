import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:media_kit_video/src/video/android_output_presentation.dart';
import 'package:media_kit_video/src/utils/dispose_safe_notifer.dart';
import 'package:media_kit_video/media_kit_video_controls/src/controls/methods/video_state.dart'
    as video_context;
import 'package:media_kit_video/media_kit_video_controls/src/controls/methods/fullscreen.dart'
    as fullscreen;

class FakeController implements VideoController {
  @override
  final player = FakePlayer();
  @override
  final notifier = ValueNotifier<PlatformVideoController?>(null);
  @override
  final platform = Completer<PlatformVideoController>();
  @override
  final id = ValueNotifier<int?>(null);
  @override
  final rect = ValueNotifier<Rect?>(null);
  @override
  void removeTextureLayoutOwner(Object owner) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakePlayer implements Player {
  @override
  PlayerState state = const PlayerState();
  @override
  PlayerStream stream = FakeStreams();
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #platform) return null;
    return super.noSuchMethod(invocation);
  }
}

class FakeStreams implements PlayerStream {
  @override
  Stream<int?> get width => const Stream.empty();
  @override
  Stream<int?> get height => const Stream.empty();
  @override
  Stream<bool> get playing => const Stream.empty();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeSession implements HdrVideoSession {
  final published = ValueNotifier<VideoController?>(null);
  @override
  ValueListenable<VideoController?> get controller => published;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget app(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  test('tokens are isolated, idempotent and safe after owner disposal', () {
    final owner = AndroidOutputPresentationOwner();
    var notifications = 0;
    owner.addListener(() => notifications++);
    final old = owner.acquire();
    final current = owner.acquire();
    old();
    old();
    expect(owner.suspended, isTrue);
    current();
    expect(owner.suspended, isFalse);
    expect(notifications, 2);
    final late = owner.acquire();
    owner.dispose();
    late();
    late();
  });
  test('notifier disposal waits for last lease, entries are removed', () {
    final key = Object();
    final first = FullscreenNotifierLifetime.retain(key);
    final second = FullscreenNotifierLifetime.retain(key);
    var disposals = 0;
    FullscreenNotifierLifetime.disposeOwner(key, () => disposals++);
    first();
    first();
    expect(disposals, 0);
    second();
    second();
    expect(disposals, 1);
    final next = FullscreenNotifierLifetime.retain(key);
    FullscreenNotifierLifetime.disposeOwner(key, () => disposals++);
    next();
    expect(disposals, 2);
    FullscreenNotifierLifetime.disposeOwner(Object(), () => disposals++);
    expect(disposals, 3);
  });
  for (final enabled in [true, false]) {
    testWidgets(
        'production output body enabled=$enabled keeps viewport and controls',
        (tester) async {
      final owner = AndroidOutputPresentationOwner();
      var outputBuilds = 0;
      final controlKey = GlobalKey();
      await tester.pumpWidget(app(AndroidOutputPresentationScope(
        owner: owner,
        child: SizedBox(
          width: 300,
          height: 180,
          child: Stack(fit: StackFit.expand, children: [
            AndroidOutputPresentationBody(
                enabled: enabled,
                builder: (_) {
                  outputBuilds++;
                  return const Texture(textureId: 42, key: ValueKey('output'));
                }),
            Text('controls', key: controlKey),
            const Text('subtitles'),
          ]),
        ),
      )));
      final controls = controlKey.currentContext;
      final before = outputBuilds;
      final release = owner.acquire();
      await tester.pump();
      expect(find.byKey(const ValueKey('output')),
          enabled ? findsNothing : findsOneWidget);
      expect(outputBuilds, before);
      expect(controlKey.currentContext, same(controls));
      expect(find.text('subtitles'), findsOneWidget);
      expect(tester.getSize(find.byType(AndroidOutputPresentationBody)),
          const Size(300, 180));
      release();
      await tester.pump();
      expect(find.byKey(const ValueKey('output')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      owner.dispose();
    });
  }
  testWidgets(
      'Hdr body window owner survives A null B and fullscreen isolates output',
      (tester) async {
    final a = FakeController(), b = FakeController();
    final published = ValueNotifier<VideoController?>(a);
    AndroidOutputPresentationOwner? windowOwner;
    AndroidOutputPresentationOwner? fullscreenOwner;
    Widget body(bool window) => HdrVideoBody(
          controller: published,
          videoBuilder: (controller) => Builder(builder: (context) {
            final owner = AndroidOutputPresentationScope.maybeOf(context);
            if (window) {
              windowOwner = owner;
            } else {
              fullscreenOwner = owner;
            }
            return AndroidOutputPresentationBody(
                enabled: true,
                builder: (_) => Text(
                    '${window ? 'window' : 'fullscreen'}-${identical(controller, a) ? 'A' : 'B'}'));
          }),
        );
    await tester.pumpWidget(app(Column(children: [
      Expanded(child: body(true)),
      Expanded(child: body(false))
    ])));
    final original = windowOwner!;
    final release = original.acquire();
    await tester.pump();
    published.value = null;
    await tester.pump();
    published.value = b;
    await tester.pump();
    expect(windowOwner, same(original));
    expect(fullscreenOwner, isNot(same(original)));
    expect(find.text('window-B'), findsNothing);
    expect(find.text('fullscreen-B'), findsOneWidget);
    release();
    await tester.pump();
    expect(find.text('window-B'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    published.dispose();
  });
  testWidgets(
      'real default enter returns before route completion; exit unlocks',
      (tester) async {
    final controller = FakeController();
    BuildContext? window;
    await tester.pumpWidget(app(Video(
      controller: controller,
      wakelock: false,
      subtitleViewConfiguration:
          const SubtitleViewConfiguration(visible: false),
      onEnterFullscreen: () async {},
      onExitFullscreen: () async {},
      controls: (_) => Builder(builder: (context) {
        if (!fullscreen.isFullscreen(context)) window = context;
        return const Text('controls');
      }),
    )));
    var entered = false;
    final entering =
        fullscreen.enterFullscreen(window!).then((_) => entered = true);
    await tester.pumpAndSettle();
    await entering;
    expect(entered, isTrue);
    expect(find.byType(FullscreenInheritedWidget), findsOneWidget);
    final fullContext = tester.element(find.descendant(
      of: find.byType(FullscreenInheritedWidget),
      matching: find.text('controls'),
    ));
    final exiting = fullscreen.exitFullscreen(fullContext);
    await tester.pumpAndSettle();
    await exiting;
    expect(find.byType(FullscreenInheritedWidget), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'owned parameter notifier survives dependencies and didUpdateWidget',
      (tester) async {
    final key = GlobalKey<VideoState>();
    final controller = FakeController();
    BuildContext? controls;
    Widget video(double width) => Video(
          key: key,
          controller: controller,
          width: width,
          wakelock: false,
          subtitleViewConfiguration:
              const SubtitleViewConfiguration(visible: false),
          controls: (_) => Builder(builder: (context) {
            controls = context;
            return const Text('parameters');
          }),
        );
    await tester.pumpWidget(app(video(100)));
    final before = video_context.videoViewParametersNotifier(controls!);
    await tester.pumpWidget(app(video(300)));
    await tester.pump();
    final after = video_context.videoViewParametersNotifier(controls!);
    expect(after, same(before));
    expect(after.value.width, 300);
  });
  testWidgets(
      'borrowed parameter notifier is not disposed with borrowing Video',
      (tester) async {
    final ownerKey = GlobalKey<VideoState>();
    final borrowerKey = GlobalKey<VideoState>();
    final controller = FakeController();
    BuildContext? ownerContext;
    BuildContext? borrowerContext;
    Widget video(GlobalKey<VideoState> key, bool owner) => Video(
          key: key,
          controller: controller,
          wakelock: false,
          subtitleViewConfiguration:
              const SubtitleViewConfiguration(visible: false),
          controls: (_) => Builder(builder: (context) {
            if (owner) {
              ownerContext = context;
            } else {
              borrowerContext = context;
            }
            return Text(owner ? 'owner' : 'borrower');
          }),
        );
    final contexts = DisposeSafeNotifier<BuildContext?>(null);
    Widget home({bool borrowed = false, bool removed = false}) =>
        app(Column(children: [
          Expanded(child: video(ownerKey, true)),
          Expanded(
              child: removed
                  ? const SizedBox()
                  : borrowed
                      ? VideoStateInheritedWidget(
                          state: ownerKey.currentState!,
                          contextNotifier: contexts,
                          videoViewParametersNotifier: video_context
                              .videoViewParametersNotifier(ownerContext!),
                          disposeNotifiers: false,
                          child: video(borrowerKey, false),
                        )
                      : video(borrowerKey, false)),
        ]));
    await tester.pumpWidget(home());
    final previouslyOwned =
        video_context.videoViewParametersNotifier(borrowerContext!);
    final shared = video_context.videoViewParametersNotifier(ownerContext!);
    await tester.pumpWidget(home(borrowed: true));
    await tester.pump();
    expect(video_context.videoViewParametersNotifier(borrowerContext!),
        same(shared));
    await tester.pumpWidget(home(removed: true));
    // Test disposal through the notifier API: owned is gone, borrowed is live.
    expect(() => previouslyOwned.addListener(() {}), throwsFlutterError);
    shared.addListener(() {});
    await tester.pumpWidget(const SizedBox());
    contexts.dispose();
  });
}
