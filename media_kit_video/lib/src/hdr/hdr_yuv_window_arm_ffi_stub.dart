/// This file is a part of media_kit (https://github.com/media-kit/media-kit).
///
/// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
/// All rights reserved.
/// Use of this source code is governed by MIT license that can be found in the LICENSE file.
import 'hdr_yuv_window_arm.dart';

/// Non-IO platforms have no vendor FFI: no bindings, and YUV window routes
/// are never planned there (they are Android-only carrier shapes).
HdrYuvWindowFfiBindings? resolveHdrYuvWindowFfiBindings() => null;
