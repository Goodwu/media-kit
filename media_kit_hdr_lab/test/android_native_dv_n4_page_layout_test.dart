import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit_hdr_lab/tests/01.single_player_single_video.dart';

void main() {
  for (final viewport in [
    (size: const Size(360, 592), scale: 1.0),
    (size: const Size(640, 360), scale: 1.0),
    (size: const Size(320, 360), scale: 2.0),
  ]) {
    testWidgets('N4 actions stay reachable with long diagnostics $viewport',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = viewport.size;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final semantics = tester.ensureSemantics();
      var runs = 0;
      var closes = 0;
      try {
        await tester.pumpWidget(MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: viewport.size,
              textScaler: TextScaler.linear(viewport.scale),
              padding: const EdgeInsets.only(bottom: 24),
            ),
            child: Scaffold(
              appBar:
                  AppBar(title: const Text('Native DV Session ownership N4')),
              body: AndroidNativeDvN4PageLayout(
                video: const Center(
                    child: AspectRatio(
                        aspectRatio: 16 / 9,
                        child: ColoredBox(color: Colors.black))),
                diagnostics: Column(children: [
                  Text('run: 1791140414516796-n4\nstatus: '
                      '${List.filled(100, "long pending status / error / report").join("\n")}'),
                  const Text(
                      'N4 open is pending; wait for the actual Player.open result before closing.'),
                ]),
                onRun: () => runs++,
                onClose: () => closes++,
              ),
            ),
          ),
        ));
        expect(tester.takeException(), isNull);
        final run = find.widgetWithText(OutlinedButton, 'Run N4 once');
        final close = find.widgetWithText(OutlinedButton, 'Close & exit');
        expect(run.hitTestable(), findsOneWidget);
        expect(close.hitTestable(), findsOneWidget);
        expect(find.bySemanticsLabel(RegExp('native-dv-n4:run-once')),
            findsOneWidget);
        expect(find.bySemanticsLabel(RegExp('native-dv-n4:close-and-exit')),
            findsOneWidget);
        expect(
            find.ancestor(
                of: run, matching: find.byType(SingleChildScrollView)),
            findsNothing);
        expect(
            find.ancestor(
                of: close, matching: find.byType(SingleChildScrollView)),
            findsNothing);
        final beforeRun = tester.getRect(run);
        final beforeClose = tester.getRect(close);
        expect(
            beforeClose.bottom, lessThanOrEqualTo(viewport.size.height - 24));
        await tester.drag(
            find.byType(SingleChildScrollView), const Offset(0, -500));
        await tester.pumpAndSettle();
        expect(tester.getRect(run), beforeRun);
        expect(tester.getRect(close), beforeClose);
        expect(run.hitTestable(), findsOneWidget);
        expect(close.hitTestable(), findsOneWidget);
        await tester.tap(run);
        await tester.tap(close);
        expect(runs, 1);
        expect(closes, 1);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    });
  }

  testWidgets('N4 layout preserves null action admission and pending hint',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: AndroidNativeDvN4PageLayout(
          video: SizedBox.shrink(),
          diagnostics: Text(
              'N4 open is pending; wait for the actual Player.open result before closing.'),
          onRun: null,
          onClose: null,
        ),
      ),
    ));
    expect(
        tester
            .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, 'Run N4 once'))
            .onPressed,
        isNull);
    expect(
        tester
            .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, 'Close & exit'))
            .onPressed,
        isNull);
    expect(
        find.text(
            'N4 open is pending; wait for the actual Player.open result before closing.'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
