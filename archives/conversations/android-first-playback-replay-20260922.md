# Android 首播失败方向：修改补丁回放记录（2026-09-22）

## 用途

本文件保存本轮会话实际产生的逐次代码修改补丁，供后续逐 ordinal 回放和 review。它不是成功方案，也不应直接重新应用到干净基线；早期 hunks 基于当时已有的 dirty worktree。最终真机结果是 HDR10 约 6 秒转圈、DV 约 11 秒转圈并出现下半屏黑屏，因此该方向已回退。

- 会话原始记录：/Users/wuweiwei1/.codex/sessions/2026/09/22/rollout-2026-09-22T10-16-46-01a0c6e6-c053-77a2-bebf-3882ae2475e8.jsonl
- 记录范围：FileChange ordinal < 1500
- 覆盖文件：media_kit_video/lib/src/video/video_texture.dart、media_kit_video/lib/src/video_controller/android_video_controller/real.dart、media_kit_test/lib/common/globals.dart
- 回放顺序：按 ordinal 从小到大；同一 ordinal 内按文件顺序。

## 逐次补丁

### ordinal 103 — media_kit_video/lib/src/video/video_texture.dart

```diff
@@ -456,4 +456,9 @@
                                                 _ohosNativeSurfaceMounted;
+                                        final androidPlatformSurface =
+                                            Platform.isAndroid &&
+                                                notifier.configuration
+                                                    .usePlatformView;
                                         if (id != null &&
-                                            rect != null &&
+                                            (rect != null ||
+                                                androidPlatformSurface) &&
                                             (_visible ||
@@ -511,2 +516,23 @@
                                                   Platform.isMacOS;
+                                          final effectiveRect = rect ??
+                                              Rect.fromLTWH(
+                                                0.0,
+                                                0.0,
+                                                (notifier.configuration.width
+                                                            ?.toDouble() ??
+                                                        (viewportConstraints
+                                                                .hasBoundedWidth
+                                                            ? viewportConstraints
+                                                                .maxWidth
+                                                            : 1.0))
+                                                    .clamp(1.0, double.infinity),
+                                                (notifier.configuration.height
+                                                            ?.toDouble() ??
+                                                        (viewportConstraints
+                                                                .hasBoundedHeight
+                                                            ? viewportConstraints
+                                                                .maxHeight
+                                                            : 1.0))
+                                                    .clamp(1.0, double.infinity),
+                                              );
                                           if (nativeOhosCandidate && _visible) {
@@ -566,6 +592,7 @@
                                           if (nativeOhosSurface &&
-                                              rect.width > 0 &&
-                                              rect.height > 0) {
+                                              effectiveRect.width > 0 &&
+                                              effectiveRect.height > 0) {
                                             final aspect =
-                                                rect.width / rect.height;
+                                                effectiveRect.width /
+                                                    effectiveRect.height;
                                             final widthForHeight =
@@ -582,4 +609,5 @@
                                             handle: notifier.nativeHandle ?? id,
-                                            width: rect.width.toInt(),
-                                            height: rect.height.toInt(),
+                                            width: effectiveRect.width.toInt(),
+                                            height:
+                                                effectiveRect.height.toInt(),
                                             useHCPP:
@@ -592,6 +620,2 @@
                                           );
-                                          final androidPlatformSurface =
-                                              Platform.isAndroid &&
-                                                  notifier.configuration
-                                                      .usePlatformView;
                                           return SizedBox(
@@ -616,3 +640,3 @@
                                                                 null
-                                                            ? rect.width
+                                                          ? effectiveRect.width
                                                             : rect.height *
@@ -632,3 +656,3 @@
                                                             .height
-                                                        : rect.height,
+                                                        : effectiveRect.height,
                                             child: Stack(
@@ -681,4 +705,4 @@
                                                   ),
-                                                if (rect.width <= 1.0 &&
-                                                    rect.height <= 1.0)
+                                                if (effectiveRect.width <= 1.0 &&
+                                                    effectiveRect.height <= 1.0)
                                                   Positioned.fill(

```

### ordinal 117 — media_kit_video/lib/src/video/video_texture.dart

```diff
@@ -582,3 +582,3 @@
                                                           .width ??
-                                                      rect.width);
+                                                      effectiveRect.width);
                                           final viewportHeight =
@@ -590,3 +590,3 @@
                                                           .height ??
-                                                      rect.height);
+                                                      effectiveRect.height);
                                           var surfaceWidth = viewportWidth;
@@ -643,3 +643,3 @@
                                                                 .width
-                                                            : rect.height *
+                                                            : effectiveRect.height *
                                                                 videoViewParameters

```

### ordinal 140 — media_kit_video/lib/src/video/video_texture.dart

```diff
@@ -528,3 +528,4 @@
                                                     .clamp(
-                                                        1.0, double.infinity),
+                                                        1.0, double.infinity)
+                                                    .toDouble(),
                                                 (notifier.configuration.height
@@ -537,3 +538,4 @@
                                                     .clamp(
-                                                        1.0, double.infinity),
+                                                        1.0, double.infinity)
+                                                    .toDouble(),
                                               );

```

### ordinal 417 — media_kit_video/lib/src/video/video_texture.dart

```diff
@@ -456,9 +456,4 @@
                                                 _ohosNativeSurfaceMounted;
-                                        final androidPlatformSurface =
-                                            Platform.isAndroid &&
-                                                notifier.configuration
-                                                    .usePlatformView;
                                         if (id != null &&
-                                            (rect != null ||
-                                                androidPlatformSurface) &&
+                                            rect != null &&
                                             (_visible ||
@@ -516,25 +511,2 @@
                                                   Platform.isMacOS;
-                                          final effectiveRect = rect ??
-                                              Rect.fromLTWH(
-                                                0.0,
-                                                0.0,
-                                                (notifier.configuration.width
-                                                            ?.toDouble() ??
-                                                        (viewportConstraints
-                                                                .hasBoundedWidth
-                                                            ? viewportConstraints
-                                                                .maxWidth
-                                                            : 1.0))
-                                                    .clamp(1.0, double.infinity)
-                                                    .toDouble(),
-                                                (notifier.configuration.height
-                                                            ?.toDouble() ??
-                                                        (viewportConstraints
-                                                                .hasBoundedHeight
-                                                            ? viewportConstraints
-                                                                .maxHeight
-                                                            : 1.0))
-                                                    .clamp(1.0, double.infinity)
-                                                    .toDouble(),
-                                              );
                                           if (nativeOhosCandidate && _visible) {

```

### ordinal 424 — media_kit_video/lib/src/video/video_texture.dart

```diff
@@ -554,3 +554,3 @@
                                                           .width ??
-                                                      effectiveRect.width);
+                                                      rect.width);
                                           final viewportHeight =
@@ -562,3 +562,3 @@
                                                           .height ??
-                                                      effectiveRect.height);
+                                                      rect.height);
                                           var surfaceWidth = viewportWidth;
@@ -566,6 +566,5 @@
                                           if (nativeOhosSurface &&
-                                              effectiveRect.width > 0 &&
-                                              effectiveRect.height > 0) {
-                                            final aspect = effectiveRect.width /
-                                                effectiveRect.height;
+                                              rect.width > 0 &&
+                                              rect.height > 0) {
+                                            final aspect = rect.width / rect.height;
                                             final widthForHeight =
@@ -582,5 +581,4 @@
                                             handle: notifier.nativeHandle ?? id,
-                                            width: effectiveRect.width.toInt(),
-                                            height:
-                                                effectiveRect.height.toInt(),
+                                            width: rect.width.toInt(),
+                                            height: rect.height.toInt(),
                                             useHCPP:
@@ -593,2 +591,6 @@
                                           );
+                                          final androidPlatformSurface =
+                                              Platform.isAndroid &&
+                                                  notifier.configuration
+                                                      .usePlatformView;
                                           return SizedBox(
@@ -613,6 +615,4 @@
                                                                 null
-                                                            ? effectiveRect
-                                                                .width
-                                                            : effectiveRect
-                                                                    .height *
+                                                            ? rect.width
+                                                            : rect.height *
                                                                 videoViewParameters
@@ -631,3 +631,3 @@
                                                             .height
-                                                        : effectiveRect.height,
+                                                        : rect.height,
                                             child: Stack(
@@ -680,5 +680,4 @@
                                                   ),
-                                                if (effectiveRect.width <=
-                                                        1.0 &&
-                                                    effectiveRect.height <= 1.0)
+                                                if (rect.width <= 1.0 &&
+                                                    rect.height <= 1.0)
                                                   Positioned.fill(

```

### ordinal 461 — media_kit_test/lib/common/globals.dart

```diff
@@ -1 +1,3 @@
+import 'dart:io';
+
 import 'package:flutter/foundation.dart';
@@ -14,3 +16,3 @@
     enableHardwareAcceleration: true,
-    usePlatformView: true,
+    usePlatformView: Platform.isAndroid,
     // W1 macOS-only experiment. Keep this enabled only in the isolated host.

```

### ordinal 461 — media_kit_video/lib/src/video/video_texture.dart

```diff
@@ -496,4 +496,3 @@
                                                                   .usePlatformView
-                                                          ? notifier
-                                                              .nativeSurfaceCandidate
+                                                          ? true
                                                           : notifier
@@ -637,3 +636,5 @@
                                                 if (nativeSurfaceCandidate &&
-                                                    !nativeSurface)
+                                                    (!nativeSurface ||
+                                                        nativeOhosCandidate ||
+                                                        nativeMacosCandidate))
                                                   Positioned.fill(

```

### ordinal 474 — media_kit_video/lib/src/video/video_texture.dart

```diff
@@ -456,4 +456,9 @@
                                                 _ohosNativeSurfaceMounted;
+                                        final androidPlatformSurface =
+                                            Platform.isAndroid &&
+                                                notifier.configuration
+                                                    .usePlatformView;
                                         if (id != null &&
-                                            rect != null &&
+                                            (rect != null ||
+                                                androidPlatformSurface) &&
                                             (_visible ||

```

### ordinal 481 — media_kit_video/lib/src/video/video_texture.dart

```diff
@@ -515,2 +515,25 @@
                                                   Platform.isMacOS;
+                                          final effectiveRect = rect ??
+                                              Rect.fromLTWH(
+                                                0.0,
+                                                0.0,
+                                                (notifier.configuration.width
+                                                            ?.toDouble() ??
+                                                        (viewportConstraints
+                                                                .hasBoundedWidth
+                                                            ? viewportConstraints
+                                                                .maxWidth
+                                                            : 1.0))
+                                                    .clamp(1.0, double.infinity)
+                                                    .toDouble(),
+                                                (notifier.configuration.height
+                                                            ?.toDouble() ??
+                                                        (viewportConstraints
+                                                                .hasBoundedHeight
+                                                            ? viewportConstraints
+                                                                .maxHeight
+                                                            : 1.0))
+                                                    .clamp(1.0, double.infinity)
+                                                    .toDouble(),
+                                              );
                                           if (nativeOhosCandidate && _visible) {

```

### ordinal 488 — media_kit_video/lib/src/video/video_texture.dart

```diff
@@ -581,3 +581,3 @@
                                                           .width ??
-                                                      rect.width);
+                                                      effectiveRect.width);
                                           final viewportHeight =
@@ -589,3 +589,3 @@
                                                           .height ??
-                                                      rect.height);
+                                                      effectiveRect.height);
                                           var surfaceWidth = viewportWidth;
@@ -593,6 +593,6 @@
                                           if (nativeOhosSurface &&
-                                              rect.width > 0 &&
-                                              rect.height > 0) {
-                                            final aspect =
-                                                rect.width / rect.height;
+                                              effectiveRect.width > 0 &&
+                                              effectiveRect.height > 0) {
+                                            final aspect = effectiveRect.width /
+                                                effectiveRect.height;
                                             final widthForHeight =
@@ -609,4 +609,5 @@
                                             handle: notifier.nativeHandle ?? id,
-                                            width: rect.width.toInt(),
-                                            height: rect.height.toInt(),
+                                            width: effectiveRect.width.toInt(),
+                                            height:
+                                                effectiveRect.height.toInt(),
                                             useHCPP:
@@ -643,4 +644,4 @@
                                                                 null
-                                                            ? rect.width
-                                                            : rect.height *
+                                                            ? effectiveRect.width
+                                                            : effectiveRect.height *
                                                                 videoViewParameters
@@ -659,3 +660,3 @@
                                                             .height
-                                                        : rect.height,
+                                                        : effectiveRect.height,
                                             child: Stack(
@@ -710,4 +711,4 @@
                                                   ),
-                                                if (rect.width <= 1.0 &&
-                                                    rect.height <= 1.0)
+                                                if (effectiveRect.width <= 1.0 &&
+                                                    effectiveRect.height <= 1.0)
                                                   Positioned.fill(

```

### ordinal 509 — media_kit_test/lib/common/globals.dart

```diff
@@ -11,3 +11,3 @@
 final configuration = ValueNotifier<VideoControllerConfiguration>(
-  const VideoControllerConfiguration(
+  VideoControllerConfiguration(
     // PLEASE USE auto-safe IN PRODUCTION.

```

### ordinal 634 — media_kit_video/lib/src/video/video_texture.dart

```diff
@@ -493,11 +493,10 @@
                                               nativeSurfaceCandidate &&
-                                                  (notifier.configuration
-                                                          .useNativeWindow
-                                                      ? notifier
-                                                          .nativeSurfaceCandidate
-                                                      : Platform.isAndroid &&
-                                                              notifier
-                                                                  .configuration
-                                                                  .usePlatformView
-                                                          ? true
+                                                  (Platform.isAndroid &&
+                                                          notifier.configuration
+                                                              .usePlatformView
+                                                      ? true
+                                                      : notifier.configuration
+                                                              .useNativeWindow
+                                                          ? notifier
+                                                              .nativeSurfaceCandidate
                                                           : notifier

```

### ordinal 634 — media_kit_test/lib/common/globals.dart

```diff
@@ -9,2 +9,3 @@
     bool.fromEnvironment('MEDIA_KIT_AUTO_TEXTURE', defaultValue: false);
+final _android = Platform.isAndroid;

@@ -13,9 +14,9 @@
     // PLEASE USE auto-safe IN PRODUCTION.
-    vo: 'mediacodec_embed',
-    hwdec: 'mediacodec',
+    vo: _android ? 'mediacodec_embed' : null,
+    hwdec: _android ? 'mediacodec' : null,
     enableHardwareAcceleration: true,
-    usePlatformView: Platform.isAndroid,
+    usePlatformView: _android,
     // W1 macOS-only experiment. Keep this enabled only in the isolated host.
-    useNativeWindow: !_autoTexture && _autoNativeWindow,
-    useNativeSurface: !_autoTexture && !_autoNativeWindow,
+    useNativeWindow: !_android && !_autoTexture && _autoNativeWindow,
+    useNativeSurface: !_android && !_autoTexture && !_autoNativeWindow,
   ),

```

### ordinal 1295 — media_kit_video/lib/src/video/video_texture.dart

```diff
@@ -464,3 +464,4 @@
                                             (_visible ||
-                                                keepMountedNativeSurface)) {
+                                                keepMountedNativeSurface ||
+                                                androidPlatformSurface)) {
                                           final nativeSurfaceCandidate = (Platform

```

### ordinal 1342 — media_kit_video/lib/src/video/video_texture.dart

```diff
@@ -629,7 +629,3 @@
                                             // the scale produced by FittedBox.
-                                            width: androidPlatformSurface &&
-                                                    viewportConstraints
-                                                        .hasBoundedWidth
-                                                ? viewportConstraints.maxWidth
-                                                : nativeOhosSurface &&
+                                            width: nativeOhosSurface &&
                                                         viewportConstraints
@@ -650,7 +646,3 @@
                                                                     .aspectRatio!,
-                                            height: androidPlatformSurface &&
-                                                    viewportConstraints
-                                                        .hasBoundedHeight
-                                                ? viewportConstraints.maxHeight
-                                                : nativeOhosSurface &&
+                                            height: nativeOhosSurface &&
                                                         viewportConstraints

```

### ordinal 1379 — media_kit_video/lib/src/video/video_texture.dart

```diff
@@ -620,6 +620,2 @@
                                           );
-                                          final androidPlatformSurface =
-                                              Platform.isAndroid &&
-                                                  notifier.configuration
-                                                      .usePlatformView;
                                           return SizedBox(

```


## 未纳入逐次 Dart hunks 的初始 dirty 状态

本轮开始时工作区已有以下修改，来自更早工作而非本轮首次编辑：

- media_kit_test/lib/common/sources/sources_native.dart
- media_kit_test/lib/common/widgets.dart
- media_kit_test/pubspec.lock
- media_kit_test/pubspec.yaml
- media_kit_video/android/build.gradle
- media_kit_video/android/src/main/java/com/alexmercerind/media_kit_video/platformview/PlatformVideoView.java
- media_kit_video/android/src/main/cpp/CMakeLists.txt
- media_kit_video/android/src/main/cpp/hdr_surface.cpp

这些文件的初始 diff 与完整内容摘录仍保存在上述 session JSONL 的 ordinal 28/35 命令输出中；本文件不把它们伪装成本轮新增修改。
