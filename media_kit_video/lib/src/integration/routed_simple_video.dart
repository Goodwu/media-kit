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
    this.fit, this.filterQuality = FilterQuality.low, this.viewport});

  final RoutedVideoPlayback playback;
  final Color fill;
  final double? aspectRatio;
  /// Optional caller-owned fit for native surfaces that cannot inherit a
  /// Flutter transform. Omitted callers retain the legacy default.
  final BoxFit? fit;
  final FilterQuality filterQuality;
  /// On-screen slot used to align native output geometry.
  final Size? viewport;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<VideoController?>(
    valueListenable: playback.controller,
    builder: (context, controller, _) {
      if (controller == null) {
        return SizedBox(width: viewport?.width ?? aspectRatio ?? 1,
            height: viewport?.height ?? 1,
            child: ColoredBox(color: fill));
      }
      return Stack(fit: StackFit.passthrough, children: [
        SimpleVideo(key: ValueKey(controller), controller: controller,
            fill: fill, aspectRatio: aspectRatio, fit: fit,
            filterQuality: filterQuality,
            viewport: viewport),
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
