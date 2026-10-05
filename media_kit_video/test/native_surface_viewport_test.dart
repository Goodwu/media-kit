import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:media_kit_video/src/video/native_surface_viewport.dart';

class _PlayerStreams implements PlayerStream {
  @override
  Stream<int?> get width => const Stream.empty();
  @override
  Stream<int?> get height => const Stream.empty();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Player implements Player {
  @override
  PlayerState get state => const PlayerState(width: 3840, height: 1920);
  @override
  PlayerStream get stream => _PlayerStreams();
  @override
  PlatformPlayer? get platform => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Output extends PlatformVideoController {
  _Output(Player player, {bool nativeWindow = false})
      : super(
          player,
          VideoControllerConfiguration(
            darwin: DarwinVideoOptions(
              useNativeSurface: true,
              useNativeWindow: nativeWindow,
            ),
          ),
        ) {
    id.value = 9;
    rect.value = const Rect.fromLTWH(0, 0, 3840, 1920);
    nativeHandle = 42;
    nativeSurfaceGeneration = 7;
    nativeSurfaceCandidate = true;
  }
  void promote(bool value) => setNativeSurfaceActive(value);
  @override
  Future<void> setSize({int? width, int? height}) async {}
}

class _Controller implements VideoController {
  _Controller(this.player, PlatformVideoController output)
      : notifier = ValueNotifier(output);
  @override
  final Player player;
  @override
  final ValueNotifier<PlatformVideoController?> notifier;
  @override
  void removeTextureLayoutOwner(Object owner) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  Rect? fitRect(BoxFit fit,
          {Alignment alignment = Alignment.center,
          double? aspectRatio,
          Size source = const Size(400, 200),
          Size viewport = const Size(100, 100)}) =>
      fittedNativeSurfaceRect(
        sourceSize: source,
        viewportSize: viewport,
        fit: fit,
        alignment: alignment,
        aspectRatio: aspectRatio,
      );

  test('all BoxFit modes preserve the full image and its crop position', () {
    expect(fitRect(BoxFit.fill), const Rect.fromLTWH(0, 0, 100, 100));
    expect(fitRect(BoxFit.contain), const Rect.fromLTWH(0, 25, 100, 50));
    expect(fitRect(BoxFit.cover), const Rect.fromLTWH(-50, 0, 200, 100));
    expect(fitRect(BoxFit.fitWidth), const Rect.fromLTWH(0, 25, 100, 50));
    expect(fitRect(BoxFit.fitHeight), const Rect.fromLTWH(-50, 0, 200, 100));
    expect(fitRect(BoxFit.none), const Rect.fromLTWH(-150, -50, 400, 200));
    expect(fitRect(BoxFit.scaleDown), const Rect.fromLTWH(0, 25, 100, 50));
    expect(
      fitRect(BoxFit.scaleDown, source: const Size(40, 20)),
      const Rect.fromLTWH(30, 40, 40, 20),
    );
  });

  test('alignment positions letterboxing and cropped source pixels', () {
    expect(fitRect(BoxFit.contain, alignment: Alignment.topLeft),
        const Rect.fromLTWH(0, 0, 100, 50));
    expect(fitRect(BoxFit.contain, alignment: Alignment.bottomRight),
        const Rect.fromLTWH(0, 50, 100, 50));
    expect(fitRect(BoxFit.cover, alignment: Alignment.centerLeft),
        const Rect.fromLTWH(0, 0, 200, 100));
    expect(fitRect(BoxFit.cover, alignment: Alignment.centerRight),
        const Rect.fromLTWH(-100, 0, 200, 100));
    expect(fitRect(BoxFit.none, alignment: Alignment.topLeft),
        const Rect.fromLTWH(0, 0, 400, 200));
    expect(fitRect(BoxFit.none, alignment: Alignment.bottomRight),
        const Rect.fromLTWH(-300, -100, 400, 200));
    // Vertical crop follows the same source-to-destination mapping.
    expect(
        fitRect(BoxFit.cover,
            source: const Size(200, 400), alignment: Alignment.bottomRight),
        const Rect.fromLTWH(0, -100, 100, 200));
  });

  test('explicit aspect and viewport resize change layout, not decoder size',
      () {
    expect(fitRect(BoxFit.contain, aspectRatio: 1),
        const Rect.fromLTWH(0, 0, 100, 100));
    expect(
        fitRect(BoxFit.contain,
            source: const Size(3840, 1920), viewport: const Size(320, 240)),
        const Rect.fromLTWH(0, 40, 320, 160));
    expect(
        fitRect(BoxFit.contain,
            source: const Size(3840, 1920), viewport: const Size(1920, 1080)),
        const Rect.fromLTWH(0, 60, 1920, 960));
  });

  test('invalid and unbounded geometry does not reach platform layout', () {
    for (final source in [
      Size.zero,
      const Size(-1, 10),
      const Size(double.nan, 1)
    ]) {
      expect(fitRect(BoxFit.contain, source: source), isNull);
    }
    expect(fitRect(BoxFit.contain, viewport: const Size(double.infinity, 1)),
        isNull);
    expect(fitRect(BoxFit.contain, viewport: Size.zero), isNull);
    for (final aspect in [0.0, -1.0, double.nan, double.infinity]) {
      expect(fitRect(BoxFit.contain, aspectRatio: aspect), isNull);
    }
    expect(fitRect(BoxFit.contain, alignment: const Alignment(double.nan, 0)),
        isNull);
  });

  testWidgets('AppKit candidate survives promotion and resize with one create',
      (tester) async {
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform_views,
      (call) async {
        calls.add(call);
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform_views, null));

    Widget view(Size size, {required bool active}) => Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox.fromSize(
              size: size,
              child: NativeSurfaceViewport(
                sourceSize: const Size(3840, 1920),
                nativeSurface: const AppKitView(
                  key: ValueKey('native-42-7'),
                  viewType: 'test-native-surface',
                ),
                textureFallback: active
                    ? null
                    : const Texture(key: ValueKey('fallback'), textureId: 9),
              ),
            ),
          ),
        );

    await tester.pumpWidget(view(const Size(320, 240), active: false));
    await tester.pump();
    final nativeElement = tester.element(find.byType(AppKitView));
    final nativeState = tester.state(find.byType(AppKitView));
    expect(tester.getSize(find.byType(AppKitView)), const Size(320, 160));
    expect(tester.getRect(find.byType(Texture)),
        tester.getRect(find.byType(AppKitView)));
    expect(find.byType(FittedBox), findsNothing);
    expect(calls.where((c) => c.method == 'create'), hasLength(1));

    await tester.pumpWidget(view(const Size(320, 240), active: true));
    await tester.pump();
    expect(tester.element(find.byType(AppKitView)), same(nativeElement));
    expect(tester.state(find.byType(AppKitView)), same(nativeState));
    expect(find.byType(Texture), findsNothing);

    await tester.pumpWidget(view(const Size(600, 300), active: true));
    await tester.pump();
    expect(tester.getSize(find.byType(AppKitView)), const Size(600, 300));
    expect(tester.element(find.byType(AppKitView)), same(nativeElement));
    expect(tester.state(find.byType(AppKitView)), same(nativeState));
    expect(calls.where((c) => c.method == 'create'), hasLength(1));
    expect(calls.where((c) => c.method == 'dispose'), isEmpty);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(calls.where((c) => c.method == 'dispose'), hasLength(1));
  });

  testWidgets('unbounded viewport does not mount a native child',
      (tester) async {
    await tester.pumpWidget(const Directionality(
      textDirection: TextDirection.ltr,
      child: UnconstrainedBox(
        child: NativeSurfaceViewport(
          sourceSize: Size(3840, 1920),
          nativeSurface: SizedBox(key: ValueKey('native')),
        ),
      ),
    ));
    expect(find.byKey(const ValueKey('native')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('production Video keeps one native view on promotion and resize',
      (tester) async {
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform_views,
      (call) async {
        calls.add(call);
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform_views, null));
    final player = _Player();
    final output = _Output(player);
    final controller = _Controller(player, output);
    Widget view(Size size) => Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
              child: SizedBox.fromSize(
            size: size,
            child: Video(
                controller: controller,
                controls: null,
                wakelock: false,
                subtitleViewConfiguration:
                    const SubtitleViewConfiguration(visible: false)),
          )),
        );
    await tester.pumpWidget(view(const Size(320, 240)));
    await tester.pump();
    final state = tester.state(find.byType(AppKitView));
    expect(find.byType(FittedBox), findsNothing);
    expect(tester.getSize(find.byType(AppKitView)), const Size(320, 160));
    expect(tester.getRect(find.byType(Texture)),
        tester.getRect(find.byType(AppKitView)));
    output.promote(true);
    await tester.pump();
    expect(find.byType(Texture), findsNothing);
    expect(tester.state(find.byType(AppKitView)), same(state));
    await tester.pumpWidget(view(const Size(600, 300)));
    await tester.pump();
    expect(tester.getSize(find.byType(AppKitView)), const Size(600, 300));
    expect(tester.state(find.byType(AppKitView)), same(state));
    expect(calls.where((call) => call.method == 'create'), hasLength(1));
    expect(calls.where((call) => call.method == 'dispose'), isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }, skip: !Platform.isMacOS);

  testWidgets('production native-window path retains decoder-sized legacy fit',
      (tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform_views, (_) async => null);
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform_views, null));
    final player = _Player();
    final output = _Output(player, nativeWindow: true);
    final controller = _Controller(player, output);
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
          child: SizedBox(
        width: 320,
        height: 240,
        child: Video(
            controller: controller,
            controls: null,
            wakelock: false,
            subtitleViewConfiguration:
                const SubtitleViewConfiguration(visible: false)),
      )),
    ));
    await tester.pump();
    expect(find.byType(NativeSurfaceViewport), findsNothing);
    expect(find.byType(FittedBox), findsOneWidget);
    expect(tester.getSize(find.byType(AppKitView)), const Size(3840, 1920));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }, skip: !Platform.isMacOS);

  testWidgets('production native surface rejects nonfinite rect before toInt',
      (tester) async {
    final player = _Player();
    final output = _Output(player);
    final controller = _Controller(player, output);
    for (final width in [double.nan, double.infinity, 0.0, -1.0]) {
      output.rect.value = Rect.fromLTWH(0, 0, width, 1920);
      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: Video(
            controller: controller,
            controls: null,
            wakelock: false,
            subtitleViewConfiguration:
                const SubtitleViewConfiguration(visible: false)),
      ));
      await tester.pump();
      expect(find.byType(AppKitView), findsNothing);
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }, skip: !Platform.isMacOS);
}
