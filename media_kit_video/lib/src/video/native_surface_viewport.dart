import 'package:flutter/widgets.dart';

/// The whole source image's layout rect, including pixels clipped by [fit].
///
/// Unlike a FittedBox transform, these are real logical layout dimensions for
/// a platform view. Its native drawable can therefore follow the viewport.
Rect? fittedNativeSurfaceRect({
  required Size sourceSize,
  required Size viewportSize,
  required BoxFit fit,
  required Alignment alignment,
  double? aspectRatio,
}) {
  bool validSize(Size size) =>
      size.width.isFinite &&
      size.height.isFinite &&
      size.width > 0 &&
      size.height > 0;
  if (!validSize(sourceSize) ||
      !validSize(viewportSize) ||
      !alignment.x.isFinite ||
      !alignment.y.isFinite ||
      (aspectRatio != null && (!aspectRatio.isFinite || aspectRatio <= 0))) {
    return null;
  }
  final source = aspectRatio == null
      ? sourceSize
      : Size(sourceSize.height * aspectRatio, sourceSize.height);
  if (!validSize(source)) return null;
  final fitted = applyBoxFit(fit, source, viewportSize);
  if (!validSize(fitted.source) || !validSize(fitted.destination)) return null;
  final sourceRect = alignment.inscribe(fitted.source, Offset.zero & source);
  final destinationRect =
      alignment.inscribe(fitted.destination, Offset.zero & viewportSize);
  final sx = destinationRect.width / sourceRect.width;
  final sy = destinationRect.height / sourceRect.height;
  final result = Rect.fromLTWH(
    destinationRect.left - sourceRect.left * sx,
    destinationRect.top - sourceRect.top * sy,
    source.width * sx,
    source.height * sy,
  );
  return result.left.isFinite && result.top.isFinite && validSize(result.size)
      ? result
      : null;
}

/// Paints one stable native candidate and its optional Texture overlay in the
/// same fitted rectangle. Removing the overlay or resizing never changes the
/// native child's element position or identity.
class NativeSurfaceViewport extends StatelessWidget {
  const NativeSurfaceViewport({
    super.key,
    required this.sourceSize,
    required this.nativeSurface,
    this.textureFallback,
    this.fit = BoxFit.contain,
    this.alignment = Alignment.center,
    this.aspectRatio,
  });

  final Size sourceSize;
  final Widget nativeSurface;
  final Widget? textureFallback;
  final BoxFit fit;
  final Alignment alignment;
  final double? aspectRatio;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final rect = fittedNativeSurfaceRect(
            sourceSize: sourceSize,
            viewportSize: constraints.biggest,
            fit: fit,
            alignment: alignment,
            aspectRatio: aspectRatio,
          );
          if (rect == null) return const SizedBox.shrink();
          return ClipRect(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Positioned.fromRect(rect: rect, child: nativeSurface),
                if (textureFallback != null)
                  Positioned.fromRect(rect: rect, child: textureFallback!),
              ],
            ),
          );
        },
      );
}
