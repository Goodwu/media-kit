/// This file is a part of media_kit (https://github.com/media-kit/media-kit).
///
/// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
/// All rights reserved.
/// Use of this source code is governed by MIT license that can be found in the LICENSE file.
import 'dart:io';

class HdrDisposalReport {
  const HdrDisposalReport({
    required this.coordinatorError,
    required this.playerError,
    required this.directoryError,
    required this.retainedDirectory,
  });

  final Object? coordinatorError;
  final Object? playerError;
  final Object? directoryError;
  final String? retainedDirectory;

  bool get clean =>
      coordinatorError == null &&
      playerError == null &&
      directoryError == null &&
      retainedDirectory == null;
}

/// Closes a session's resources in dependency order: the open coordinator
/// first (stop + property restore, retrying transient backend failures),
/// then the player, then any session-owned directory. A directory whose
/// bytes may still be read by native code is retained when the player
/// termination failed.
///
/// Ported from hdr_lab's `disposeAndroidHdrResources`; [disposePlayer] and
/// [privateRoot] are optional because a library session does not own the
/// caller's player and stages no private copies.
Future<HdrDisposalReport> disposeHdrResources({
  Future<void> Function()? disposeCoordinator,
  Future<void> Function()? disposePlayer,
  Directory? Function()? privateRoot,
  int coordinatorAttempts = 3,
  Future<void> Function(Duration)? wait,
}) async {
  if (coordinatorAttempts < 1) {
    throw ArgumentError.value(coordinatorAttempts, 'coordinatorAttempts');
  }
  Object? coordinatorError;
  Object? playerError;
  Object? directoryError;
  String? retainedDirectory;

  if (disposeCoordinator != null) {
    for (var attempt = 0; attempt < coordinatorAttempts; attempt++) {
      try {
        await disposeCoordinator();
        coordinatorError = null;
        break;
      } catch (error) {
        coordinatorError = error;
        if (attempt + 1 < coordinatorAttempts) {
          await (wait ?? Future<void>.delayed)(
            const Duration(milliseconds: 100),
          );
        }
      }
    }
  }

  if (disposePlayer != null) {
    try {
      await disposePlayer();
    } catch (error) {
      playerError = error;
    }
  }

  final root = privateRoot?.call();
  if (root != null) {
    if (playerError == null) {
      try {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      } catch (error) {
        directoryError = error;
        retainedDirectory = root.path;
      }
    } else {
      retainedDirectory = root.path;
    }
  }

  return HdrDisposalReport(
    coordinatorError: coordinatorError,
    playerError: playerError,
    directoryError: directoryError,
    retainedDirectory: retainedDirectory,
  );
}
