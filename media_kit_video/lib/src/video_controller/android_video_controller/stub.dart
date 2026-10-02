/// This file is a part of media_kit (https://github.com/media-kit/media-kit).
///
/// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
/// All rights reserved.
/// Use of this source code is governed by MIT license that can be found in the LICENSE file.
import 'package:media_kit/media_kit.dart';

import 'package:media_kit_video/src/video_controller/platform_video_controller.dart';

// Stub declaration for avoiding compilation errors on Dart JS using conditional imports.

class AndroidVideoController extends PlatformVideoController {
  static const bool supported = false;

  // Web compile-face stubs for the HDR capability-change members used by
  // HdrVideoSession (Phase 1 R2.5 passthrough semantics). All call sites are
  // behind the session's Android gate, so none of these is reachable on web.

  static void registerHdrCapabilitiesChangedListener(
    HdrCapabilitiesChangedListener listener,
  ) =>
      throw UnimplementedError();

  static bool unregisterHdrCapabilitiesChangedListener(
    HdrCapabilitiesChangedListener listener,
  ) =>
      throw UnimplementedError();

  static Future<void> setHdrCapabilitiesChangedEnabled(bool enabled) =>
      throw UnimplementedError();

  static Future<Map<String, Object?>?> invokeApplyDataSpace({
    required int handle,
    required String transfer,
  }) =>
      throw UnimplementedError();

  AndroidVideoController._(
    super.player,
    super.configuration,
  );

  static Future<PlatformVideoController> create(
    Player player,
    VideoControllerConfiguration configuration,
  ) =>
      throw UnimplementedError();

  @override
  Future<void> setSize({int? width, int? height}) => throw UnimplementedError();
}
