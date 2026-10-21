import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

class _Player extends Fake implements Player {
  @override
  PlatformPlayer? get platform => null;
}

void main() {
  testWidgets('constructing an idle VideoController schedules initialization',
      (tester) async {
    final binding = WidgetsBinding.instance;
    expect(SchedulerBinding.instance.schedulerPhase, SchedulerPhase.idle);
    expect(binding.hasScheduledFrame, isFalse);

    final controller = VideoController(_Player());

    // Assert before pumping: a pump here would hide a missing
    // ensureVisualUpdate() and leave the post-frame initialization stranded.
    expect(binding.hasScheduledFrame, isTrue);

    final initializationFailure = expectLater(
      controller.platform.future,
      throwsA(isA<TypeError>()),
    );
    await tester.pump();
    await initializationFailure;
    await controller.disposeForRebuild();
  });
}
