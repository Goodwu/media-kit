import 'dart:io';

class AndroidHdrDisposalReport {
  const AndroidHdrDisposalReport({
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

/// The staging directory belongs to one screen session. Its bytes may still
/// be read by native code until Player disposal has completed successfully.
Future<AndroidHdrDisposalReport> disposeAndroidHdrResources({
  required Future<void> Function() disposePlayer,
  Future<void> Function()? disposeCoordinator,
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

  try {
    await disposePlayer();
  } catch (error) {
    playerError = error;
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

  return AndroidHdrDisposalReport(
    coordinatorError: coordinatorError,
    playerError: playerError,
    directoryError: directoryError,
    retainedDirectory: retainedDirectory,
  );
}
