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
    return IgnorePointer(
      child: PlatformViewLink(
        viewType: viewType,
        surfaceFactory:
            (BuildContext context, PlatformViewController controller) {
          return AndroidViewSurface(
            controller: controller as AndroidViewController,
            gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
            hitTestBehavior: PlatformViewHitTestBehavior.opaque,
          );
        },
        onCreatePlatformView: (PlatformViewCreationParams params) {
          return useHCPP
              ? PlatformViewsService.initHybridAndroidView(
                  id: params.id,
                  viewType: viewType,
                  layoutDirection:
                      Directionality.maybeOf(context) ?? TextDirection.ltr,
                  creationParams: creationParams,
                  creationParamsCodec: const StandardMessageCodec(),
                  onFocus: () => params.onFocusChanged(true),
                )
              // On API 29 the explicit, documented ordinary Hybrid
              // Composition entry is required. initSurfaceAndroidView first
              // attempts TLHC, which makes the composition contract depend on
              // a runtime fallback and obscures the HDR experiment topology.
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
