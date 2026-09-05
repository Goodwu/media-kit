/// OHOS platform surface implementation selected by the isolated OHOS build.
import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

class PlatformViewVideo extends StatelessWidget {
  const PlatformViewVideo({
    super.key,
    required this.handle,
    required this.width,
    required this.height,
    this.useHCPP = false,
    this.generation = 1,
  });

  final int handle;
  final int width;
  final int height;
  final bool useHCPP;
  final int generation;

  @override
  Widget build(BuildContext context) {
    final creationParams = <String, dynamic>{
      'handle': handle,
      'width': width,
      'height': height,
      'generation': generation,
    };
    // The parent video viewport owns the final size.  Keeping a fixed
    // decoder-sized box here makes the XComponent stay in the upper-left
    // corner after entering fullscreen (the decoder rect is often smaller
    // than the rotated display viewport).
    return IgnorePointer(
      child: PlatformViewLink(
        viewType: 'com.alexmercerind/media_kit_video/ohos_native_surface',
        surfaceFactory: (
          BuildContext context,
          PlatformViewController controller,
        ) {
          return OhosViewSurface(
            controller: controller as OhosViewController,
            gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
            // HCPP's ArkUI XComponent can retain a full-window hit region
            // even when the video surface itself is laid out to the video
            // viewport. Let the Flutter control overlay receive taps in
            // that surplus region (especially the bottom fullscreen button).
            hitTestBehavior: PlatformViewHitTestBehavior.transparent,
          );
        },
        onCreatePlatformView: (PlatformViewCreationParams params) {
          final controller = useHCPP
              ? PlatformViewsService.initExpensiveOhosView(
                  id: params.id,
                  viewType:
                      'com.alexmercerind/media_kit_video/ohos_native_surface',
                  layoutDirection:
                      Directionality.maybeOf(context) ?? TextDirection.ltr,
                  creationParams: creationParams,
                  creationParamsCodec: const StandardMessageCodec(),
                )
              : PlatformViewsService.initSurfaceOhosView(
                  id: params.id,
                  viewType:
                      'com.alexmercerind/media_kit_video/ohos_native_surface',
                  layoutDirection:
                      Directionality.maybeOf(context) ?? TextDirection.ltr,
                  creationParams: creationParams,
                  creationParamsCodec: const StandardMessageCodec(),
                );
          return controller
            ..addOnPlatformViewCreatedListener(params.onPlatformViewCreated)
            ..create();
        },
      ),
    );
  }
}
