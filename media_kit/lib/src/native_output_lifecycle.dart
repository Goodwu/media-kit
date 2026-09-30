/// This file is a part of media_kit (https://github.com/media-kit/media-kit).
///
/// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
/// All rights reserved.
/// Use of this source code is governed by MIT license that can be found in the LICENSE file.

/// {@template native_output_lifecycle}
///
/// NativeOutputLifecycle
/// ---------------------
/// Phase scheduler for native output owners during [Player] disposal.
///
/// media_kit schedules disposal by phase only and never branches on the host
/// platform:
///
/// 1. [onCloseOwnerAdmission] — synchronous, before dispose's first await:
///    stop admitting new native outputs.
/// 2. [waitForSettledOwners] — while mpv is still alive, wait until in-flight
///    output creations have settled.
/// 3. [stopWaitsForVideoControllerInitialization] — whether the player stop
///    also waits for an attached video controller's initialization.
///
/// The attached video output installs an instance on the player (see
/// `PlatformPlayer.outputLifecycle`) when its controller is created, before
/// any asynchronous work. Without one, disposal uses the defaults: no
/// admission closing, waiting for an attached controller's initialization,
/// and stop waiting for it — the conservative baseline for hosts that never
/// reserve native-output admissions.
///
/// {@endtemplate}
class NativeOutputLifecycle {
  const NativeOutputLifecycle({
    this.onCloseOwnerAdmission,
    this.waitForSettledOwners,
    this.stopWaitsForVideoControllerInitialization = true,
  });

  /// Phase 1 hook; `null` keeps the player default (no admission closing).
  final void Function()? onCloseOwnerAdmission;

  /// Phase 2 hook; `null` keeps the player default (wait for an attached
  /// video controller's initialization).
  final Future<void> Function()? waitForSettledOwners;

  /// Phase 3 flag for the player's stop call.
  final bool stopWaitsForVideoControllerInitialization;
}
