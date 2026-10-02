/// This file is a part of media_kit (https://github.com/media-kit/media-kit).
///
/// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
/// All rights reserved.
/// Use of this source code is governed by MIT license that can be found in the LICENSE file.

/// Serial output replacement is called only from the open coordinator's
/// native side-effect queue. A replacement is published before waiting for
/// its Surface, so Flutter can mount the new PlatformView.
///
/// Ported from hdr_lab's `AndroidHdrOutputSlot` with identical semantics.
class HdrOutputSlot<T> {
  HdrOutputSlot({
    required T? initial,
    this.rebuildInitial = false,
    required this.voOf,
    required this.disposeForRebuild,
    required this.create,
    required this.publish,
    required this.waitReady,
  }) : _current = initial;

  final Future<String> Function(T output) voOf;
  final bool rebuildInitial;
  final Future<void> Function(T output) disposeForRebuild;
  final T Function(String vo, String hwdec, String? surfaceTransfer) create;
  final void Function(T? output) publish;
  final Future<void> Function(T output) waitReady;

  T? _current;
  String? _currentOutputFormat;
  String? _currentSurfaceTransfer;
  bool _initialPending = true;
  T? get current => _current;

  Future<void> ensure(
    String vo,
    String hwdec, {
    String? outputFormat,
    String? surfaceTransfer,
  }) async {
    final old = _current;
    if (old != null) {
      String? oldVo;
      try {
        oldVo = await voOf(old);
      } catch (_) {
        // A failed controller initialization has no usable VO. The wrapper
        // still needs to be retired before another one is created.
      }
      if ((!_initialPending || !rebuildInitial) &&
          oldVo == vo &&
          _currentOutputFormat == outputFormat &&
          _currentSurfaceTransfer == surfaceTransfer) {
        try {
          await waitReady(old);
          return;
        } catch (_) {
          // An explicit retry of the same route must replace a failed output.
          // Retire it through the normal producer stop and Surface ACK barrier
          // before publishing a new controller below.
        }
      }
      await disposeForRebuild(old);
      _initialPending = false;
      _current = null;
      _currentOutputFormat = null;
      _currentSurfaceTransfer = null;
      publish(null);
    }

    final next = create(vo, hwdec, surfaceTransfer);
    _initialPending = false;
    _current = next;
    _currentOutputFormat = outputFormat;
    _currentSurfaceTransfer = surfaceTransfer;
    publish(next);
    try {
      await waitReady(next);
    } catch (error, stack) {
      try {
        await disposeForRebuild(next);
        _current = null;
        _currentOutputFormat = null;
        _currentSurfaceTransfer = null;
        publish(null);
      } catch (_) {
        // Retain the failed output for a later explicit retry. Its platform
        // controller may still own a native Surface reference.
      }
      Error.throwWithStackTrace(error, stack);
    }
  }

  Future<void> dispose() async {
    final current = _current;
    if (current == null) return;
    await disposeForRebuild(current);
    _initialPending = false;
    _current = null;
    _currentOutputFormat = null;
    _currentSurfaceTransfer = null;
    publish(null);
  }
}
