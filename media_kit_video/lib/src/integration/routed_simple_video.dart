import 'package:flutter/widgets.dart';

import '../video/simple_video.dart';
import '../video_controller/video_controller.dart';
import 'routed_video_playback.dart';

/// Explicit listenable binding for an application-owned FittedBox/overlay.
/// The renderer mounts while routing is pending, rather than waiting for a
/// verified report or decoder dimensions. Its controller may be replaced.
class RoutedSimpleVideo extends StatelessWidget {
  const RoutedSimpleVideo({super.key, required this.playback,
    this.fill = const Color(0xFF000000), this.aspectRatio,
    this.filterQuality = FilterQuality.low});

  final RoutedVideoPlayback playback;
  final Color fill;
  final double? aspectRatio;
  final FilterQuality filterQuality;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<VideoController?>(
    valueListenable: playback.controller,
    builder: (context, controller, _) {
      if (controller == null) {
        return SizedBox(width: aspectRatio ?? 1, height: 1,
            child: ColoredBox(color: fill));
      }
      return Stack(fit: StackFit.passthrough, children: [
        SimpleVideo(key: ValueKey(controller), controller: controller,
            fill: fill, aspectRatio: aspectRatio, filterQuality: filterQuality),
        // Mounting is independent of readiness; pre-review pixels are covered.
        Positioned.fill(child: ValueListenableBuilder<bool>(
          valueListenable: playback.ready,
          builder: (context, ready, _) => ready
              ? const SizedBox.shrink() : ColoredBox(color: fill),
        )),
      ]);
    },
  );
}
