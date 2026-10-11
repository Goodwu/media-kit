/// This file is a part of media_kit (https://github.com/media-kit/media-kit).
///
/// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
/// All rights reserved.
/// Use of this source code is governed by MIT license that can be found in the LICENSE file.

import '../video_controller/platform_video_controller.dart';
import 'hdr_route.dart';

/// Creation-time output requests, not observations of native presentation.
/// Importing SurfaceTexture frames does not prove a YUV presenter is armed.
/// Parameters configured in place (such as target-prim/trc) are not identity.
class HdrOutputContract {
  const HdrOutputContract({
    required this.vo,
    required this.topology,
    required this.requestedHwdec,
    this.gpuApi,
    this.eglOutputFormat,
    this.surfacePixelFormat,
    this.surfaceTransfer,
    this.offscreenTransfer,
  });

  factory HdrOutputContract.fromRoute(
    HdrRoute route, {
    String surfacePixelFormatOverride = 'rgba1010102',
  }) {
    final platform = route.topology == HdrTopology.platformView;
    final gpu = route.vo == 'gpu-next';
    return HdrOutputContract(
      vo: route.vo,
      topology: route.topology,
      requestedHwdec: route.hwdec,
      gpuApi: gpu ? 'opengl' : null,
      eglOutputFormat: platform && gpu ? 'rgb10_a2' : null,
      surfacePixelFormat: platform
          ? (gpu && route.surfaceTransfer != null
              ? surfacePixelFormatOverride
              : '')
          : null,
      surfaceTransfer: platform ? (route.surfaceTransfer ?? '') : null,
      offscreenTransfer: route.offscreenTransfer,
    );
  }

  final String vo;
  final HdrTopology topology;
  final String requestedHwdec;
  final String? gpuApi;
  final String? eglOutputFormat;
  final String? surfacePixelFormat;
  final String? surfaceTransfer;
  final String? offscreenTransfer;

  /// The Session uses this exact projection when constructing its controller.
  /// Android copyWith cannot clear nullable hints, so construct the options
  /// explicitly while preserving every unrelated caller option.
  VideoControllerConfiguration controllerConfiguration(
      VideoControllerConfiguration base) {
    final options = base.android;
    return base.copyWith(
      vo: vo,
      hwdec: requestedHwdec,
      android: AndroidVideoOptions(
        usePlatformView: topology == HdrTopology.platformView,
        useHCPP: options.useHCPP,
        enableSurfaceProducer: options.enableSurfaceProducer,
        matchTextureOutputToLayout: options.matchTextureOutputToLayout,
        attachSurfaceAfterVideoParameters:
            options.attachSurfaceAfterVideoParameters,
        gpuApi: gpuApi,
        surfaceTransfer: surfaceTransfer,
        surfacePixelFormat: surfacePixelFormat,
        lgExperimentOwnerToken: options.lgExperimentOwnerToken,
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HdrOutputContract &&
          vo == other.vo &&
          topology == other.topology &&
          requestedHwdec == other.requestedHwdec &&
          gpuApi == other.gpuApi &&
          eglOutputFormat == other.eglOutputFormat &&
          surfacePixelFormat == other.surfacePixelFormat &&
          surfaceTransfer == other.surfaceTransfer &&
          offscreenTransfer == other.offscreenTransfer;

  @override
  int get hashCode => Object.hash(vo, topology, requestedHwdec, gpuApi,
      eglOutputFormat, surfacePixelFormat, surfaceTransfer, offscreenTransfer);
}
