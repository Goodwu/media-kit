// Widget tests for the HDR companion widget (R2.1, plan S6):
//
// - `HdrVideoBody` is the shared mounting point of `HdrVideo` and the
//   built-in fullscreen page. Controller replacement (A -> B) and the
//   null-controller placeholder are verified on it, because mounting a real
//   `Video` requires a real `VideoController` (a `Player` plus platform
//   channels), which cannot be faked inside a widget test.
// - `FullscreenVideoSurface` carries the fullscreen-page branch: without a
//   session it builds the statically captured controller (regression for the
//   pre-existing behavior); with a session it follows
//   `HdrVideoSession.controller`. The session is faked with
//   `implements HdrVideoSession` since the real session has no test seam to
//   publish replacement controllers.
// - `HdrVideo` itself is exercised with a real `HdrVideoSession.forTesting`
//   on a non-Android host: its controller stays null, so the placeholder and
//   the `HdrVideoScope` injection are verified.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';

import 'package:media_kit_video/media_kit_video.dart';
import 'package:media_kit_video/src/hdr/hdr_disposal.dart';

/// A [VideoController] stub: enough for identity checks in the mounting
/// widgets, never used to build a real [Video] output.
class _FakeVideoController implements VideoController {
  @override
  Player get player => throw UnimplementedError();

  @override
  final platform = Completer<PlatformVideoController>();

  @override
  final notifier = ValueNotifier<PlatformVideoController?>(null);

  @override
  final id = ValueNotifier<int?>(null);

  @override
  final rect = ValueNotifier<Rect?>(null);

  @override
  bool get nativeSurfaceCandidate => false;

  @override
  bool get nativeSurfaceActive => false;

  @override
  void updateTextureLayoutOwner(Object owner, Size physicalViewport, BoxFit fit) {}

  @override
  void removeTextureLayoutOwner(Object owner) {}

  @override
  Future<bool> prepareAndroidTextureOutput() async => false;

  @override
  Future<void> setSize({int? width, int? height}) async {}

  @override
  Future<void> get waitUntilFirstFrameRendered async {}

  @override
  Future<void> disposeForRebuild() async {}
}

/// An [HdrVideoSession] stub whose controller can be published from tests,
/// simulating the topology-switch replacements driven by [HdrVideoSession].
class _FakeHdrVideoSession implements HdrVideoSession {
  final ValueNotifier<VideoController?> _controller =
      ValueNotifier<VideoController?>(null);

  void publish(VideoController? controller) => _controller.value = controller;

  @override
  ValueListenable<VideoController?> get controller => _controller;

  @override
  ValueListenable<HdrOutputReport> get report =>
      _report ??= ValueNotifier<HdrOutputReport>(const HdrOutputReport());
  ValueNotifier<HdrOutputReport>? _report;

  @override
  Stream<HdrOutputEvent> get events => const Stream.empty();

  @override
  HdrDisposalReport? get lastDisposeReport => null;

  @override
  Future<void> open(
    Media media, {
    HdrSourceDescriptor? hint,
    bool play = true,
    Duration? start,
  }) async {}

  @override
  Future<void> setPreference(HdrOutputPreference preference) async {}

  @override
  Future<void> setPolicy(HdrRoutingPolicy policy) async {}

  @override
  Future<void> handleCapabilitiesChanged(HdrCapabilities capabilities) async {}

  @override
  Future<void> dispose() async {}
}

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets(
      'HdrVideoBody mounts the new controller after a session replacement',
      (tester) async {
    final controllerA = _FakeVideoController();
    final controllerB = _FakeVideoController();
    final notifier = ValueNotifier<VideoController?>(controllerA);
    final mounted = <VideoController>[];

    await tester.pumpWidget(_wrap(HdrVideoBody(
      controller: notifier,
      videoBuilder: (controller) {
        mounted.add(controller);
        return Text(
          identical(controller, controllerA) ? 'video-A' : 'video-B',
          key: ValueKey<VideoController>(controller),
        );
      },
    )));

    expect(find.text('video-A'), findsOneWidget);
    expect(find.text('video-B'), findsNothing);
    expect(mounted, <VideoController>[controllerA]);

    // Simulate the controller replacement of a topology switch (R2.1).
    notifier.value = controllerB;
    await tester.pump();

    expect(find.byKey(ValueKey<VideoController>(controllerB)), findsOneWidget);
    expect(find.byKey(ValueKey<VideoController>(controllerA)), findsNothing);
    expect(mounted, <VideoController>[controllerA, controllerB]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('HdrVideoBody shows the placeholder while controller is null',
      (tester) async {
    final notifier = ValueNotifier<VideoController?>(null);
    var builtCount = 0;

    await tester.pumpWidget(_wrap(HdrVideoBody(
      controller: notifier,
      videoBuilder: (_) {
        builtCount++;
        return const Text('video');
      },
      placeholder: const Text('placeholder'),
    )));

    expect(find.text('placeholder'), findsOneWidget);
    expect(find.text('video'), findsNothing);
    expect(builtCount, 0);

    notifier.value = _FakeVideoController();
    await tester.pump();
    expect(find.text('video'), findsOneWidget);
    expect(find.text('placeholder'), findsNothing);

    notifier.value = null;
    await tester.pump();
    expect(find.text('placeholder'), findsOneWidget);
    expect(find.text('video'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('HdrVideo with a real session: placeholder and scope injection',
      (tester) async {
    final session = HdrVideoSession.forTesting(player: null, isAndroid: false);

    await tester.pumpWidget(_wrap(HdrVideo(session: session)));

    // A non-Android passthrough session without a Player never publishes a
    // controller: the placeholder is shown without any exception.
    expect(find.byType(HdrVideoPlaceholder), findsOneWidget);
    expect(find.byType(Video), findsNothing);
    expect(tester.takeException(), isNull);

    // The session is visible below the widget for fullscreen detection.
    final placeholderContext =
        tester.element(find.byType(HdrVideoPlaceholder));
    expect(HdrVideoScope.maybeOf(placeholderContext)?.session,
        same(session));

    // The scope is not visible above the widget.
    expect(HdrVideoScope.maybeOf(tester.element(find.byType(HdrVideo))),
        isNull);

    await session.dispose();
  });

  testWidgets(
      'fullscreen page follows a controller replacement while it is open',
      (tester) async {
    final session = _FakeHdrVideoSession();
    final controllerA = _FakeVideoController();
    final controllerB = _FakeVideoController();
    session.publish(controllerA);
    final built = <VideoController>[];

    await tester.pumpWidget(_wrap(FullscreenVideoSurface(
      session: session,
      controller: _FakeVideoController(), // static fallback, unused here
      buildVideo: (controller) {
        built.add(controller);
        return Text(
          identical(controller, controllerA) ? 'fullscreen-A' : 'fullscreen-B',
          key: ValueKey<VideoController>(controller),
        );
      },
      placeholder: const Text('placeholder'),
    )));

    expect(find.text('fullscreen-A'), findsOneWidget);
    expect(built, <VideoController>[controllerA]);

    // Controller replacement while the fullscreen page is open (R2.1):
    // the page must switch to the new controller.
    session.publish(controllerB);
    await tester.pump();
    expect(
        find.byKey(ValueKey<VideoController>(controllerB)), findsOneWidget);
    expect(
        find.byKey(ValueKey<VideoController>(controllerA)), findsNothing);
    expect(built, <VideoController>[controllerA, controllerB]);

    // While the next controller is being created, the placeholder shows.
    session.publish(null);
    await tester.pump();
    expect(find.text('placeholder'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'fullscreen page without a session keeps the static captured controller (regression)',
      (tester) async {
    final staticController = _FakeVideoController();
    VideoController? received;

    await tester.pumpWidget(_wrap(FullscreenVideoSurface(
      session: null,
      controller: staticController,
      buildVideo: (controller) {
        received = controller;
        return const Text('static-video');
      },
    )));

    expect(find.text('static-video'), findsOneWidget);
    expect(received, same(staticController));
    // The session path is not mounted at all.
    expect(find.byType(HdrVideoBody), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
