import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit_video/src/video_controller/android_video_controller/current_bound_output_identity.dart';
import 'package:media_kit_video/src/video_controller/android_video_controller/platform_surface_release.dart';

const _owner = AndroidSurfaceAccountId(
  handle: 11,
  generation: 3,
  viewId: 7,
  surfaceGeneration: 2,
  wid: 4242,
);

AndroidSurfaceAccountId? _resolve({
  AndroidSurfaceAccountId? candidate = _owner,
  AndroidSurfaceAccountId? expected = _owner,
  bool outputAvailable = true,
  bool noInFlightOwner = true,
  bool ownerLive = true,
  bool ownerNotBindFailed = true,
  bool ownerNotReleasing = true,
  bool controllerActive = true,
  bool matchesBoundOutput = true,
}) =>
    currentBoundOutputIdentityForState(
      candidate: candidate,
      expected: expected,
      outputAvailable: outputAvailable,
      noInFlightOwner: noInFlightOwner,
      ownerLive: ownerLive,
      ownerNotBindFailed: ownerNotBindFailed,
      ownerNotReleasing: ownerNotReleasing,
      controllerActive: controllerActive,
      matchesBoundOutput: matchesBoundOutput,
    );

void main() {
  test('returns the complete identity only for the current stable owner', () {
    expect(_resolve(), _owner);
  });

  test('does not accept a recycled wid with an old owner tuple', () {
    const recycledAddressOldOwner = AndroidSurfaceAccountId(
      handle: 11,
      generation: 3,
      viewId: 6,
      surfaceGeneration: 1,
      wid: 4242,
    );
    expect(_resolve(candidate: recycledAddressOldOwner), isNull);
    expect(_resolve(expected: recycledAddressOldOwner), isNull);
  });

  test('does not accept changes to any identity component', () {
    final oldOwners = <AndroidSurfaceAccountId>[
      const AndroidSurfaceAccountId(
        handle: 12,
        generation: 3,
        viewId: 7,
        surfaceGeneration: 2,
        wid: 4242,
      ),
      const AndroidSurfaceAccountId(
        handle: 11,
        generation: 4,
        viewId: 7,
        surfaceGeneration: 2,
        wid: 4242,
      ),
      const AndroidSurfaceAccountId(
        handle: 11,
        generation: 3,
        viewId: 8,
        surfaceGeneration: 2,
        wid: 4242,
      ),
      const AndroidSurfaceAccountId(
        handle: 11,
        generation: 3,
        viewId: 7,
        surfaceGeneration: 1,
        wid: 4242,
      ),
      const AndroidSurfaceAccountId(
        handle: 11,
        generation: 3,
        viewId: 7,
        surfaceGeneration: 2,
        wid: 4243,
      ),
    ];

    for (final oldOwner in oldOwners) {
      expect(_resolve(candidate: oldOwner), isNull);
      expect(_resolve(expected: oldOwner), isNull);
    }
  });

  test('returns null whenever lifecycle or ledger state is unstable', () {
    final unstableStates = <AndroidSurfaceAccountId? Function()>[
      () => _resolve(candidate: null),
      () => _resolve(expected: null),
      () => _resolve(outputAvailable: false),
      () => _resolve(noInFlightOwner: false),
      () => _resolve(ownerLive: false),
      () => _resolve(ownerNotBindFailed: false),
      () => _resolve(ownerNotReleasing: false),
      () => _resolve(controllerActive: false),
      () => _resolve(matchesBoundOutput: false),
    ];

    for (final resolve in unstableStates) {
      expect(resolve(), isNull);
    }
  });
}
