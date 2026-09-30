import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit_video/src/video_controller/android_video_controller/platform_surface_release.dart';

/// Records every channel call so interleavings can be asserted, and lets a
/// test decide each reply — the same faults that previously needed
/// device-side injection.
class _FakeReleaseChannel implements PlatformSurfaceReleaseChannel {
  _FakeReleaseChannel({
    this.releaseReplies = const [],
    this.acknowledgeReplies = const [],
  });

  /// Replies for successive `ReleaseSurface` calls (values or Exceptions).
  final List<Object> releaseReplies;
  final List<Object> acknowledgeReplies;

  final calls = <String, AndroidSurfaceAccountId>{};
  int releaseCalls = 0;
  int acknowledgeCalls = 0;

  @override
  Future<String?> releaseSurface(AndroidSurfaceAccountId owner) async {
    calls['release:$releaseCalls'] = owner;
    final reply = releaseReplies[releaseCalls];
    releaseCalls++;
    if (reply is String) return reply;
    if (reply == null) return null;
    throw reply;
  }

  @override
  Future<bool?> acknowledgeReleaseSurfaceOwner(
    AndroidSurfaceAccountId owner,
  ) async {
    calls['ack:$acknowledgeCalls'] = owner;
    final reply = acknowledgeReplies[acknowledgeCalls];
    acknowledgeCalls++;
    if (reply is bool) return reply;
    if (reply == null) return null;
    throw reply;
  }
}

const _ownerA = AndroidSurfaceAccountId(
  handle: 11,
  generation: 3,
  viewId: 7,
  surfaceGeneration: 2,
  wid: 4242,
);

const _ownerB = AndroidSurfaceAccountId(
  handle: 11,
  generation: 3,
  viewId: 8,
  surfaceGeneration: 1,
  wid: 4242,
);

void main() {
  test('a clean release is release-then-acknowledge with full identity',
      () async {
    final channel = _FakeReleaseChannel(
      releaseReplies: ['released'],
      acknowledgeReplies: [true],
    );
    await SurfaceReleaseProtocol(channel).release(_ownerA);
    expect(channel.releaseCalls, 1);
    expect(channel.acknowledgeCalls, 1);
    expect(channel.calls['release:0'], _ownerA);
    expect(channel.calls['ack:0'], _ownerA);
  });

  test('alreadyReleased is accepted so a retry after a failed first phase '
      'can complete', () async {
    // First attempt: the platform release succeeded but the Dart-side call
    // failed; the owner stayed pending. The retry must accept
    // alreadyReleased and still deliver the explicit acknowledgement.
    final channel = _FakeReleaseChannel(
      releaseReplies: [
        StateError('simulated channel failure'),
        'alreadyReleased',
      ],
      acknowledgeReplies: [
        true,
      ],
    );
    final protocol = SurfaceReleaseProtocol(channel);
    await expectLater(protocol.release(_ownerA), throwsA(isA<StateError>()));
    expect(channel.acknowledgeCalls, 0);

    await protocol.release(_ownerA);
    expect(channel.releaseCalls, 2);
    expect(channel.acknowledgeCalls, 1);
  });

  test('a rejected release keeps the owner pending', () async {
    final channel = _FakeReleaseChannel(
      releaseReplies: ['rejected-not-current-owner'],
      acknowledgeReplies: [true],
    );
    await expectLater(
      SurfaceReleaseProtocol(channel).release(_ownerA),
      throwsStateError,
    );
    // The acknowledgement must never run after a rejected first phase.
    expect(channel.acknowledgeCalls, 0);
  });

  test('a failed acknowledgement keeps the owner pending for a full retry',
      () async {
    final channel = _FakeReleaseChannel(
      releaseReplies: ['released', 'alreadyReleased'],
      acknowledgeReplies: [false, true],
    );
    final protocol = SurfaceReleaseProtocol(channel);
    await expectLater(protocol.release(_ownerA), throwsStateError);
    expect(channel.releaseCalls, 1);
    expect(channel.acknowledgeCalls, 1);

    // The retry repeats the exact acknowledgement, not just the release.
    await protocol.release(_ownerA);
    expect(channel.releaseCalls, 2);
    expect(channel.acknowledgeCalls, 2);
  });

  test('channel exceptions propagate without acknowledging', () async {
    final channel = _FakeReleaseChannel(
      releaseReplies: [TimeoutException('simulated timeout')],
      acknowledgeReplies: [true],
    );
    await expectLater(
      SurfaceReleaseProtocol(channel).release(_ownerA),
      throwsA(isA<TimeoutException>()),
    );
    expect(channel.acknowledgeCalls, 0);
  });

  test('a late destroy for old A never confuses B: identities stay separate',
      () async {
    // Old A's destroy arrives after B is bound; both owners share the same
    // recycled JNI address (wid) but differ in the rest of the tuple.
    expect(_ownerA == _ownerB, isFalse);
    expect(_ownerA.hashCode, isNot(_ownerB.hashCode));

    final channel = _FakeReleaseChannel(
      releaseReplies: ['alreadyReleased', 'released'],
      acknowledgeReplies: [false, true],
    );
    final protocol = SurfaceReleaseProtocol(channel);
    // A's ACK fails; B's release then succeeds and is acknowledged.
    await expectLater(protocol.release(_ownerA), throwsStateError);
    await protocol.release(_ownerB);
    expect(channel.calls['release:0'], _ownerA);
    expect(channel.calls['release:1'], _ownerB);
    expect(channel.calls['ack:1'], _ownerB);
  });

  test('the channel payload carries the complete five-part identity',
      () async {
    final channel = _FakeReleaseChannel(
      releaseReplies: ['released'],
      acknowledgeReplies: [true],
    );
    await SurfaceReleaseProtocol(channel).release(_ownerA);
    final owner = channel.calls['release:0']!;
    expect(
      owner.asChannelArguments(),
      <String, Object>{
        'handle': '11',
        'generation': 3,
        'viewId': 7,
        'surfaceGeneration': 2,
        'wid': '4242',
      },
    );
  });
}
