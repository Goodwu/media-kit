import 'dart:io';

void _require(bool condition, String message) {
  if (!condition) {
    throw StateError(message);
  }
}

void main() {
  final source = File(
    'lib/src/video_controller/native_video_controller/real.dart',
  ).readAsStringSync();

  _require(
    source.contains(
      'Future<void> _dispose() => _disposeFuture ??= _disposeOnce();',
    ),
    'all native-controller disposal callers must await one shared future',
  );

  final dispose = source.indexOf('Future<void> _disposeOnce() async');
  final cancel = source.indexOf('await subscription?.cancel()', dispose);
  final drain = source.indexOf(
    'await lock.synchronized(() async {});',
    dispose,
  );
  final detach = source.indexOf('await detachNativeWindow()', dispose);
  final nativeOutput = source.indexOf('await disposeNativeOutput()', dispose);
  final videoOutput = source.indexOf(
    "await _channel.invokeMethod(\n          'VideoOutputManager.Dispose'",
    dispose,
  );
  final notifierDispose = source.indexOf('super.dispose()', dispose);
  _require(
    dispose >= 0 &&
        cancel > dispose &&
        drain > cancel &&
        detach > drain &&
        nativeOutput > detach &&
        videoOutput > nativeOutput &&
        notifierDispose > videoOutput,
    'disposal must quiesce callbacks and await native render-context release '
    'before disposing notifiers',
  );

  final disposeSection = source.substring(dispose, notifierDispose + 200);
  _require(
    disposeSection.contains('cleanupError ??= error;') &&
        disposeSection.contains('cleanupStack ??= stack;') &&
        disposeSection.contains(
          'Error.throwWithStackTrace(cleanupError!, cleanupStack!);',
        ) &&
        RegExp(r'} catch \(error, stack\) \{')
                .allMatches(disposeSection)
                .length >=
            5,
    'cleanup must continue after intermediate failures and report the first one',
  );

  final resize = source.indexOf("case 'VideoOutput.Resize':");
  final resizeGuard = source.indexOf(
    'if (_controllers[handle]?._disposed ?? true) break;',
    resize,
  );
  final resizeWrite = source.indexOf(
    '_controllers[handle]?.rect.value = rect;',
    resize,
  );
  final ready = source.indexOf("case 'NativeSurface.Ready':");
  final readyGuard = source.indexOf(
    'if (controller?._disposed ?? true) return;',
    ready,
  );
  _require(
    source.contains('if (_disposed) return;') &&
        source.contains('super.setNativeSurfaceActive(value);') &&
        resizeGuard > resize &&
        resizeWrite > resizeGuard &&
        readyGuard > ready,
    'late stream and method-channel callbacks must not write disposed notifiers',
  );

  _require(
    !source.contains('_disposeVideoOutputForTest'),
    'production code must not expose a test-only disposal helper',
  );
}
