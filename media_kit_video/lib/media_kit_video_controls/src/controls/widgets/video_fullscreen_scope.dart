// This file is a part of media_kit (https://github.com/media-kit/media-kit).
//
// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
// All rights reserved.
// Use of this source code is governed by MIT license that can be found in the LICENSE file.
import 'dart:async';

import 'package:flutter/widgets.dart';

/// Builds a layout around one [child] while its fullscreen state changes.
///
/// Place this widget above [Video] from the first frame to opt into in-place
/// fullscreen. The [builder] must keep [child] at the same element location in
/// both states, for example in one `Scaffold > Stack > Positioned.fill` tree.
/// Moving it between branches, routes, overlays, or differently keyed parents
/// will still recreate the video output.
/// Use one scope per video.
///
/// Without this scope, the video controls retain their route-based fullscreen
/// behavior.
class VideoFullscreenScope extends StatefulWidget {
  final Widget child;
  final Widget Function(BuildContext context, bool isFullscreen, Widget child)
      builder;

  /// Optional barrier before this route is popped with the system back action.
  ///
  /// A page that owns a native video Surface can stop and dispose its producer
  /// here, before Flutter removes the video widget and destroys that Surface.
  /// Throw on failure to keep the page mounted. Explicit route removal by an
  /// ancestor still needs its own lifecycle coordination.
  final Future<void> Function()? onBeforePop;

  const VideoFullscreenScope({
    super.key,
    required this.child,
    required this.builder,
    this.onBeforePop,
  });

  static VideoFullscreenScopeState? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_VideoFullscreenScopeInherited>()
      ?.scope;

  @override
  State<VideoFullscreenScope> createState() => VideoFullscreenScopeState();
}

class VideoFullscreenScopeState extends State<VideoFullscreenScope> {
  bool _isFullscreen = false;
  bool _disposed = false;
  Future<void> _pending = Future<void>.value();
  Future<void> Function()? _onExitFullscreen;
  bool _pageExitInProgress = false;
  bool _pageExitReady = false;

  bool get isFullscreen => _isFullscreen;

  Future<void> _serialize(Future<void> Function() operation) {
    final result = _pending.then((_) => operation());
    // A failed callback must not prevent a later exit or disposal cleanup.
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  /// Enters fullscreen without moving or rebuilding [Video] in another route.
  ///
  /// Calls made while another transition is in progress are serialized.
  Future<void> enter({
    required Future<void> Function() onEnterFullscreen,
    required Future<void> Function() onExitFullscreen,
  }) =>
      _serialize(() async {
        if (_disposed ||
            _isFullscreen ||
            _pageExitInProgress ||
            _pageExitReady) {
          return;
        }
        setState(() => _isFullscreen = true);
        _onExitFullscreen = onExitFullscreen;
        try {
          await onEnterFullscreen();
        } catch (error, stack) {
          // Enter may have changed the native orientation or system UI before
          // failing. Keep the exit callback until restoration succeeds.
          try {
            await onExitFullscreen();
            _onExitFullscreen = null;
            if (!_disposed) setState(() => _isFullscreen = false);
          } catch (restoreError, restoreStack) {
            _reportAsyncError(restoreError, restoreStack,
                'while restoring a failed fullscreen enter');
          }
          Error.throwWithStackTrace(error, stack);
        }
      });

  /// Exits fullscreen while retaining the same video element.
  Future<void> exit() => _serialize(() async {
        if (_disposed || !_isFullscreen) return;
        final callback = _onExitFullscreen;
        await callback?.call();
        _onExitFullscreen = null;
        if (!_disposed) setState(() => _isFullscreen = false);
      });

  void _reportAsyncError(Object error, StackTrace stack, String action) {
    FlutterError.reportError(FlutterErrorDetails(
      exception: error,
      stack: stack,
      library: 'media_kit_video_controls',
      context: ErrorDescription(action),
    ));
  }

  Future<void> _runBeforePop() async {
    if (_disposed || _pageExitInProgress || _pageExitReady) return;
    final callback = widget.onBeforePop;
    if (callback == null) return;
    _pageExitInProgress = true;
    try {
      await callback();
      if (_disposed) return;
      setState(() => _pageExitReady = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
    } catch (error, stack) {
      _reportAsyncError(error, stack, 'while preparing to leave video page');
    } finally {
      _pageExitInProgress = false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    // A route can be removed while enter() is still awaiting native fullscreen.
    // Finish that callback first, then restore native UI exactly once.
    unawaited(_serialize(() async {
      final callback = _onExitFullscreen;
      await callback?.call();
      _onExitFullscreen = null;
    }).catchError((Object error, StackTrace stack) {
      _reportAsyncError(error, stack, 'while disposing VideoFullscreenScope');
    }));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop:
            !_isFullscreen && (widget.onBeforePop == null || _pageExitReady),
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && _isFullscreen) {
            unawaited(exit().catchError((Object error, StackTrace stack) {
              _reportAsyncError(error, stack, 'while handling fullscreen back');
            }));
          } else if (!didPop) {
            unawaited(_runBeforePop());
          }
        },
        child: _VideoFullscreenScopeInherited(
          scope: this,
          isFullscreen: _isFullscreen,
          child: Builder(
            builder: (context) =>
                widget.builder(context, _isFullscreen, widget.child),
          ),
        ),
      );
}

class _VideoFullscreenScopeInherited extends InheritedWidget {
  final VideoFullscreenScopeState scope;
  final bool isFullscreen;

  const _VideoFullscreenScopeInherited({
    required this.scope,
    required this.isFullscreen,
    required super.child,
  });

  @override
  bool updateShouldNotify(_VideoFullscreenScopeInherited oldWidget) =>
      !identical(scope, oldWidget.scope) ||
      isFullscreen != oldWidget.isFullscreen;
}
