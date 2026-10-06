/// This file is a part of media_kit (https://github.com/media-kit/media-kit).
///
/// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
/// All rights reserved.
/// Use of this source code is governed by MIT license that can be found in the LICENSE file.
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

// Test-only creation parameter used to verify that a PlatformView surface can
// receive its output dataspace before libmpv starts dequeuing buffers.
const _androidPlatformViewDataSpace =
    String.fromEnvironment('MEDIA_KIT_ANDROID_PLATFORM_VIEW_DATASPACE');
const _androidPlatformViewPixelFormat =
    String.fromEnvironment('MEDIA_KIT_ANDROID_PLATFORM_VIEW_PIXEL_FORMAT');

/// A widget that displays a video player using a native platform surface.
class PlatformViewVideo extends StatelessWidget {
  /// Creates a new instance of [PlatformViewVideo].
  const PlatformViewVideo({
    super.key,
    required this.handle,
    required this.width,
    required this.height,
    this.useHCPP = false,
    this.generation = 1,
    this.mpvWindow = false,
    this.androidSurfaceTransfer,
    this.androidSurfacePixelFormat,
  });

  /// The handle (player ID) of the video player.
  final int handle;
  final int width;
  final int height;
  final bool useHCPP;
  final int generation;

  /// Whether the Darwin native view should be bound as mpv's window.
  final bool mpvWindow;
  final String? androidSurfaceTransfer;
  final String? androidSurfacePixelFormat;

  @override
  Widget build(BuildContext context) {
    final String viewType = (Platform.isIOS || Platform.isMacOS)
        ? 'com.alexmercerind/media_kit_video/native_surface'
        : Platform.operatingSystem == 'ohos'
            ? 'com.alexmercerind/media_kit_video/ohos_native_surface'
            : 'com.alexmercerind/media_kit_video_platform_view';
    final Map<String, dynamic> creationParams = {
      'handle': handle,
      'width': width,
      'height': height,
      'generation': generation,
      'mpvWindow': mpvWindow,
      if (Platform.isAndroid && (androidSurfaceTransfer?.isNotEmpty ?? false))
        'dataspace': androidSurfaceTransfer,
      if (Platform.isAndroid &&
          androidSurfaceTransfer == null &&
          _androidPlatformViewDataSpace.isNotEmpty)
        'dataspace': _androidPlatformViewDataSpace,
      if (Platform.isAndroid &&
          (androidSurfacePixelFormat?.isNotEmpty ?? false))
        'pixelFormat': androidSurfacePixelFormat,
      if (Platform.isAndroid &&
          androidSurfacePixelFormat == null &&
          _androidPlatformViewPixelFormat.isNotEmpty)
        'pixelFormat': _androidPlatformViewPixelFormat,
    };

    if (Platform.isIOS) {
      return UiKitView(
        viewType: viewType,
        creationParams: creationParams,
        creationParamsCodec: const StandardMessageCodec(),
        hitTestBehavior: PlatformViewHitTestBehavior.transparent,
      );
    }
    if (Platform.isMacOS) {
      return AppKitView(
        viewType: viewType,
        creationParams: creationParams,
        creationParamsCodec: const StandardMessageCodec(),
        hitTestBehavior: PlatformViewHitTestBehavior.transparent,
      );
    }

    // IgnorePointer so that GestureDetector can be used above the platform view.
    final bool ohos = Platform.operatingSystem == 'ohos';
    return IgnorePointer(
      child: PlatformViewLink(
        viewType: viewType,
        surfaceFactory:
            (BuildContext context, PlatformViewController controller) {
          // OHOS rides the standard surface entry: the fork's channel maps
          // the texture-layer request to the engine's TLHC composition (the
          // September Luna e4 build proved this displays on the emulator via
          // external-texture composition). The hybrid/expensive entries hit
          // the engine's "HCPP unavailable → created but not composed"
          // fallback where XComponent onLoad never fires.
          return AndroidViewSurface(
            controller: controller as AndroidViewController,
            gestureRecognizers:
                const <Factory<OneSequenceGestureRecognizer>>{},
            hitTestBehavior: ohos
                ? PlatformViewHitTestBehavior.transparent
                : PlatformViewHitTestBehavior.opaque,
          );
        },
        onCreatePlatformView: (PlatformViewCreationParams params) {
          // TEMPORARY emulator trace (release-visible).
          debugPrint('[SwTrace] onCreatePlatformView id=${params.id} '
              'ohos=$ohos hcpp=$useHCPP');
          return useHCPP && !ohos
              ? PlatformViewsService.initHybridAndroidView(
                  id: params.id,
                  viewType: viewType,
                  layoutDirection:
                      Directionality.maybeOf(context) ?? TextDirection.ltr,
                  creationParams: creationParams,
                  creationParamsCodec: const StandardMessageCodec(),
                  onFocus: () => params.onFocusChanged(true),
                )
              // OHOS and API-29 Android share the surface (TLHC) entry; the
              // expensive entry is the documented ordinary Hybrid
              // Composition requirement on API 29 only.
              : (ohos || useHCPP)
                  ? PlatformViewsService.initSurfaceAndroidView(
                      id: params.id,
                      viewType: viewType,
                      layoutDirection:
                          Directionality.maybeOf(context) ?? TextDirection.ltr,
                      creationParams: creationParams,
                      creationParamsCodec: const StandardMessageCodec(),
                      onFocus: () => params.onFocusChanged(true),
                    )
                  : PlatformViewsService.initExpensiveAndroidView(
                      id: params.id,
                      viewType: viewType,
                      layoutDirection:
                          Directionality.maybeOf(context) ?? TextDirection.ltr,
                      creationParams: creationParams,
                      creationParamsCodec: const StandardMessageCodec(),
                      onFocus: () => params.onFocusChanged(true),
                    )
            ..addOnPlatformViewCreatedListener(params.onPlatformViewCreated)
            ..create();
        },
      ),
    );
  }
}
