import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit_video/media_kit_video.dart';

class _StableChild extends StatefulWidget {
  final void Function() onInit;
  final void Function() onDispose;

  const _StableChild({
    super.key,
    required this.onInit,
    required this.onDispose,
  });

  @override
  State<_StableChild> createState() => _StableChildState();
}

class _StableChildState extends State<_StableChild> {
  @override
  void initState() {
    super.initState();
    widget.onInit();
  }

  @override
  void dispose() {
    widget.onDispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const ColoredBox(color: Colors.black);
}

void main() {
  testWidgets('scope changes fullscreen state without replacing its child',
      (tester) async {
    final scopeKey = GlobalKey<VideoFullscreenScopeState>();
    final childKey = GlobalKey();
    var initCount = 0;
    var disposeCount = 0;
    var enterCount = 0;
    var exitCount = 0;
    late BuildContext childContext;

    await tester.pumpWidget(MaterialApp(
      home: VideoFullscreenScope(
        key: scopeKey,
        builder: (context, fullscreen, child) => Scaffold(
          body: Stack(children: [Positioned.fill(child: child)]),
        ),
        child: Builder(
          builder: (context) {
            childContext = context;
            return _StableChild(
              key: childKey,
              onInit: () => initCount++,
              onDispose: () => disposeCount++,
            );
          },
        ),
      ),
    ));

    final originalElement = tester.element(find.byKey(childKey));
    expect(isFullscreen(childContext), isFalse);

    await scopeKey.currentState!.enter(
      onEnterFullscreen: () async {
        enterCount++;
      },
      onExitFullscreen: () async {
        exitCount++;
      },
    );
    await tester.pump();
    expect(isFullscreen(childContext), isTrue);
    expect(tester.element(find.byKey(childKey)), same(originalElement));

    await scopeKey.currentState!.exit();
    await tester.pump();
    expect(isFullscreen(childContext), isFalse);
    expect(tester.element(find.byKey(childKey)), same(originalElement));
    expect(initCount, 1);
    expect(disposeCount, 0);
    expect(enterCount, 1);
    expect(exitCount, 1);
  });

  testWidgets('back exits scope fullscreen before popping the page',
      (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    final scopeKey = GlobalKey<VideoFullscreenScopeState>();
    var exitCount = 0;

    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigatorKey,
      home: const Scaffold(body: Text('home')),
    ));
    navigatorKey.currentState!.push(MaterialPageRoute<void>(
      builder: (_) => VideoFullscreenScope(
        key: scopeKey,
        builder: (context, fullscreen, child) =>
            Scaffold(body: Stack(children: [Positioned.fill(child: child)])),
        child: const Text('video page'),
      ),
    ));
    await tester.pumpAndSettle();
    await scopeKey.currentState!.enter(
      onEnterFullscreen: () async {},
      onExitFullscreen: () async {
        exitCount++;
      },
    );
    await tester.pump();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(scopeKey.currentState!.isFullscreen, isFalse);
    expect(exitCount, 1);
    expect(find.text('video page'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('video page'), findsNothing);
    expect(exitCount, 1);
  });

  testWidgets('dispose during enter waits for callback then exits once',
      (tester) async {
    final scopeKey = GlobalKey<VideoFullscreenScopeState>();
    final enterCompleter = Completer<void>();
    var exitCount = 0;

    await tester.pumpWidget(MaterialApp(
      home: VideoFullscreenScope(
        key: scopeKey,
        builder: (context, fullscreen, child) =>
            Scaffold(body: Stack(children: [Positioned.fill(child: child)])),
        child: const SizedBox(),
      ),
    ));
    final entering = scopeKey.currentState!.enter(
      onEnterFullscreen: () => enterCompleter.future,
      onExitFullscreen: () async {
        exitCount++;
      },
    );
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    enterCompleter.complete();
    await entering;
    await tester.pump();
    expect(exitCount, 1);
  });

  testWidgets('exit queued during enter invokes callbacks in order',
      (tester) async {
    final scopeKey = GlobalKey<VideoFullscreenScopeState>();
    final enterCompleter = Completer<void>();
    final events = <String>[];

    await tester.pumpWidget(MaterialApp(
      home: VideoFullscreenScope(
        key: scopeKey,
        builder: (context, fullscreen, child) =>
            Scaffold(body: Stack(children: [Positioned.fill(child: child)])),
        child: const SizedBox(),
      ),
    ));
    final scope = scopeKey.currentState!;
    final entering = scope.enter(
      onEnterFullscreen: () async {
        events.add('enter-start');
        await enterCompleter.future;
        events.add('enter-end');
      },
      onExitFullscreen: () async {
        events.add('exit');
      },
    );
    final exiting = scope.exit();
    await tester.pump();
    expect(events, ['enter-start']);
    enterCompleter.complete();
    await Future.wait([entering, exiting]);
    await tester.pump();
    expect(events, ['enter-start', 'enter-end', 'exit']);
    expect(scope.isFullscreen, isFalse);
  });

  testWidgets('failed enter restores native state and remains windowed',
      (tester) async {
    final scopeKey = GlobalKey<VideoFullscreenScopeState>();
    var nativeFullscreen = false;
    var exitCount = 0;
    await tester.pumpWidget(MaterialApp(
      home: VideoFullscreenScope(
        key: scopeKey,
        builder: (context, fullscreen, child) => Scaffold(body: child),
        child: const SizedBox(),
      ),
    ));
    await expectLater(
      scopeKey.currentState!.enter(
        onEnterFullscreen: () async {
          nativeFullscreen = true;
          throw StateError('enter failed after native change');
        },
        onExitFullscreen: () async {
          nativeFullscreen = false;
          exitCount++;
        },
      ),
      throwsStateError,
    );
    await tester.pump();
    expect(nativeFullscreen, isFalse);
    expect(scopeKey.currentState!.isFullscreen, isFalse);
    expect(exitCount, 1);
  });

  testWidgets('failed exit keeps fullscreen and can be retried',
      (tester) async {
    final scopeKey = GlobalKey<VideoFullscreenScopeState>();
    var exitCount = 0;
    await tester.pumpWidget(MaterialApp(
      home: VideoFullscreenScope(
        key: scopeKey,
        builder: (context, fullscreen, child) => Scaffold(body: child),
        child: const SizedBox(),
      ),
    ));
    await scopeKey.currentState!.enter(
      onEnterFullscreen: () async {},
      onExitFullscreen: () async {
        exitCount++;
        if (exitCount == 1) throw StateError('temporary exit failure');
      },
    );
    await expectLater(scopeKey.currentState!.exit(), throwsStateError);
    expect(scopeKey.currentState!.isFullscreen, isTrue);
    await scopeKey.currentState!.exit();
    await tester.pump();
    expect(scopeKey.currentState!.isFullscreen, isFalse);
    expect(exitCount, 2);
  });

  testWidgets('page pop waits for producer shutdown and ignores repeated back',
      (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    final shutdown = Completer<void>();
    var shutdownCount = 0;
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigatorKey,
      home: const Scaffold(body: Text('home')),
    ));
    navigatorKey.currentState!.push(MaterialPageRoute<void>(
      builder: (_) => VideoFullscreenScope(
        onBeforePop: () {
          shutdownCount++;
          return shutdown.future;
        },
        builder: (context, fullscreen, child) => Scaffold(body: child),
        child: const Text('video page'),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text('video page'), findsOneWidget);
    expect(shutdownCount, 1);

    shutdown.complete();
    await tester.pumpAndSettle();
    expect(find.text('video page'), findsNothing);
  });

  testWidgets('pending page shutdown cannot reenter fullscreen',
      (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    final scopeKey = GlobalKey<VideoFullscreenScopeState>();
    final shutdown = Completer<void>();
    var enterCount = 0;
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigatorKey,
      home: const Scaffold(body: Text('home')),
    ));
    navigatorKey.currentState!.push(MaterialPageRoute<void>(
      builder: (_) => VideoFullscreenScope(
        key: scopeKey,
        onBeforePop: () => shutdown.future,
        builder: (context, fullscreen, child) => Scaffold(body: child),
        child: const Text('video page'),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pump();
    await scopeKey.currentState!.enter(
      onEnterFullscreen: () async {
        enterCount++;
      },
      onExitFullscreen: () async {},
    );
    expect(enterCount, 0);
    expect(scopeKey.currentState!.isFullscreen, isFalse);

    shutdown.complete();
    await tester.pumpAndSettle();
    expect(find.text('video page'), findsNothing);
  });

  testWidgets('failed shutdown keeps the page and permits another back',
      (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    var attempts = 0;
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigatorKey,
      home: const Scaffold(body: Text('home')),
    ));
    navigatorKey.currentState!.push(MaterialPageRoute<void>(
      builder: (_) => VideoFullscreenScope(
        onBeforePop: () async {
          attempts++;
          if (attempts == 1) throw StateError('producer still active');
        },
        builder: (context, fullscreen, child) => Scaffold(body: child),
        child: const Text('video page'),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(tester.takeException(), isA<StateError>());
    expect(find.text('video page'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(find.text('video page'), findsNothing);
  });
}
