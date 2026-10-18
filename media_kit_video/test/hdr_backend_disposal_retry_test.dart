import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/src/hdr/hdr_output_slot.dart';
import 'package:media_kit_video/src/hdr/hdr_player_backend.dart';
import 'package:media_kit_video/src/video_controller/video_controller.dart';

class Subscription implements StreamSubscription<VideoParams> {
  int attempts = 0;
  @override
  Future<void> cancel() async {
    if (++attempts == 1) throw StateError('subscription still owned');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class VideoStream extends Stream<VideoParams> {
  final subscription = Subscription();
  @override
  StreamSubscription<VideoParams> listen(void Function(VideoParams)? onData,
          {Function? onError, void Function()? onDone, bool? cancelOnError}) =>
      subscription;
}

class Streams implements PlayerStream {
  Streams(this.videoParams);
  @override
  final VideoStream videoParams;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakePlayer implements Player {
  FakePlayer(this.stream);
  @override
  final Streams stream;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
      'actual Android backend retains failed subscription cancellation for retry',
      () async {
    final stream = VideoStream();
    final slot = HdrOutputSlot<VideoController>(
        initial: null,
        voOf: (_) async => 'gpu-next',
        disposeForRebuild: (_) async {},
        create: (_) => throw StateError('unused'),
        publish: (_) {},
        waitReady: (_) async {});
    final backend = AndroidHdrBackend(
        player: FakePlayer(Streams(stream)), outputSlot: slot);
    await expectLater(backend.dispose(), throwsStateError);
    expect(stream.subscription.attempts, 1);
    await backend.dispose();
    expect(stream.subscription.attempts, 2);
    await backend.dispose();
    expect(stream.subscription.attempts, 2);
  });
  test(
      'actual slot final disposal retains exact current on failure then clears on success',
      () async {
    final output = Object();
    var attempts = 0;
    final published = <Object?>[];
    final slot = HdrOutputSlot<Object>(
        initial: output,
        voOf: (_) async => 'gpu-next',
        disposeForRebuild: (_) async {
          if (++attempts == 1) throw StateError('output debt');
        },
        create: (_) => Object(),
        publish: published.add,
        waitReady: (_) async {});
    await expectLater(slot.dispose(), throwsStateError);
    expect(slot.current, same(output));
    expect(published, isEmpty);
    await slot.dispose();
    expect(slot.current, isNull);
    expect(published, [null]);
    await slot.dispose();
    expect(attempts, 2);
  });
}
