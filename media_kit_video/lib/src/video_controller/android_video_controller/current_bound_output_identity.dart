import 'platform_surface_release.dart';

/// Returns [candidate] only when every synchronous snapshot still describes
/// the same stable, current platform output.
///
/// Keeping this decision pure lets tests cover owner-address reuse and
/// lifecycle transitions without constructing a native Player or importing
/// `dart:io`.
AndroidSurfaceAccountId? currentBoundOutputIdentityForState({
  required AndroidSurfaceAccountId? candidate,
  required AndroidSurfaceAccountId? expected,
  required bool outputAvailable,
  required bool noInFlightOwner,
  required bool ownerLive,
  required bool ownerNotBindFailed,
  required bool ownerNotReleasing,
  required bool controllerActive,
  required bool matchesBoundOutput,
}) {
  if (candidate == null ||
      candidate != expected ||
      !outputAvailable ||
      !noInFlightOwner ||
      !ownerLive ||
      !ownerNotBindFailed ||
      !ownerNotReleasing ||
      !controllerActive ||
      !matchesBoundOutput) {
    return null;
  }
  return candidate;
}
