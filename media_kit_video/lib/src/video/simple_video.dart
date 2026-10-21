/// This file is a part of media_kit (https://github.com/media-kit/media-kit).
/// Use of this source code is governed by the repository's MIT license.
import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/widgets.dart';

import '../subtitle/subtitle_view.dart';
import '../video_controller/video_controller.dart';
import 'video_texture.dart' if (dart.library.js_interop) 'video_web.dart';

/// Intrinsically sized video for applications which own their FittedBox,
/// controls, subtitles and lifecycle handling outside the video widget.
///
/// The renderer is the ordinary [Video], including its native-surface path.
/// In particular, a surface must not wait for a texture id before mounting.
class SimpleVideo extends StatefulWidget {
  const SimpleVideo({
    super.key,
    this.fill = const Color(0xFF000000),
    required this.controller,
    this.aspectRatio,
    this.fit,
    this.filterQuality = FilterQuality.low,
    this.viewport,
  }) : assert(aspectRatio == null || aspectRatio > 0);

  final Color fill;
  final VideoController controller;
  final double? aspectRatio;
  /// Optional fit override for callers that manage a separate viewport.
  /// When omitted, preserve the legacy viewport/non-viewport defaults.
  final BoxFit? fit;
  final FilterQuality filterQuality;
  /// On-screen slot for native 1:1 layout; the renderer fits within this slot.
  final Size? viewport;

  @override
  State<SimpleVideo> createState() => SimpleVideoState();
}

class SimpleVideoState extends State<SimpleVideo> {
  final _subscriptions = <StreamSubscription<int?>>[];
  int _generation = 0;
  int? _width;
  int? _height;

  void _bind() {
    final generation = ++_generation;
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
    final player = widget.controller.player;
    _width = player.state.videoWidth;
    _height = player.state.videoHeight;
    _subscriptions.add(player.stream.width.listen((value) {
      if (!mounted || generation != _generation || value == _width) return;
      setState(() => _width = value);
    }));
    _subscriptions.add(player.stream.height.listen((value) {
      if (!mounted || generation != _generation || value == _height) return;
      setState(() => _height = value);
    }));
  }

  @override
  void initState() {
    super.initState();
    _bind();
  }

  @override
  void didUpdateWidget(SimpleVideo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.controller, oldWidget.controller)) _bind();
  }

  @override
  void dispose() {
    ++_generation;
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return ListenableBuilder(
      listenable: Listenable.merge([
        controller.id,
        controller.rect,
        controller.notifier,
      ]),
      builder: (context, _) {
        final viewport = widget.viewport;
        final useViewport =
            controller.notifier.value?.configuration.android.usePlatformView ==
                true &&
            viewport != null &&
            viewport.width.isFinite &&
            viewport.height.isFinite &&
            viewport.width > 0 &&
            viewport.height > 0;
        final size = useViewport
            ? viewport!
            : simpleVideoLogicalSize(
                rect: controller.rect.value,
                width: _width,
                height: _height,
                devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
                aspectRatio: widget.aspectRatio,
              );
        final fit = widget.fit ?? (useViewport ? BoxFit.contain : BoxFit.fill);
        final visible = (_width ?? 0) > 0 && (_height ?? 0) > 0;
        return SizedBox(
          width: size.width,
          height: size.height,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Video(
                // Video owns subscriptions; changing the actual Player must
                // not retain an old player's stream subscriptions.
                key: ValueKey(controller),
                controller: controller,
                width: size.width,
                height: size.height,
                fit: fit,
                fill: widget.fill,
                aspectRatio: widget.aspectRatio,
                filterQuality: widget.filterQuality,
                controls: null,
                wakelock: false,
                pauseUponEnteringBackgroundMode: false,
                resumeUponEnteringForegroundMode: false,
                subtitleViewConfiguration:
                    const SubtitleViewConfiguration(visible: false),
              ),
              if (!visible) Positioned.fill(child: ColoredBox(color: widget.fill)),
            ],
          ),
        );
      },
    );
  }
}

/// Source-pixel dimensions become logical dimensions before the caller's fit.
/// The non-zero preparation size lets native output mount before decoder facts.
@visibleForTesting
Size simpleVideoLogicalSize({
  Rect? rect,
  int? width,
  int? height,
  required double devicePixelRatio,
  double? aspectRatio,
}) {
  if (!devicePixelRatio.isFinite || devicePixelRatio <= 0) {
    throw ArgumentError.value(devicePixelRatio, 'devicePixelRatio');
  }
  if (aspectRatio != null && (!aspectRatio.isFinite || aspectRatio <= 0)) {
    throw ArgumentError.value(aspectRatio, 'aspectRatio');
  }
  final validRect = rect != null && rect.width.isFinite && rect.height.isFinite &&
      rect.width > 0 && rect.height > 0;
  final pixels = validRect
      ? rect!.size
      : (width ?? 0) > 0 && (height ?? 0) > 0
          ? Size(width!.toDouble(), height!.toDouble())
          : const Size(1, 1);
  final logicalHeight = pixels.height / devicePixelRatio;
  return Size(
    aspectRatio == null ? pixels.width / devicePixelRatio : logicalHeight * aspectRatio,
    logicalHeight,
  );
}
