# Android 首播失败方向：controller 修改补丁回放（2026-09-22）

本文件与 android-first-playback-replay-20260922.md 配套，保存 AndroidVideoController 的逐次 FileChange hunks。按 ordinal 顺序回放；这些修改基于任务开始时已有的 dirty worktree，最终已全部回退。

原始 session：/Users/wuweiwei1/.codex/sessions/2026/09/22/rollout-2026-09-22T10-16-46-01a0c6e6-c053-77a2-bebf-3882ae2475e8.jsonl

### ordinal 103 — media_kit_video/lib/src/video_controller/android_video_controller/real.dart

```diff
@@ -112,6 +112,7 @@
       final voValue = widValue == '0' ? 'null' : configuration.vo!;
-      // Keep the video track enabled while a PlatformView is being rebound.
-      // Setting vid=no for wid=0 prevents the next file from emitting
-      // video-params, so no new PlatformView can be mounted to provide wid.
-      final vidValue = 'auto';
+      // mediacodec_embed must not be started before the PlatformView Surface
+      // exists. The widget can mount the initial PlatformView without
+      // video-params; enabling the track here would make the decoder churn on
+      // a null native window during the first open.
+      final vidValue = widValue == '0' ? 'no' : 'auto';
       // It is important to re-initialize --vo after --android-surface-size.
@@ -266,6 +267,6 @@
         'hwdec': configuration.hwdec!,
-        // Keep the video track enabled so mpv can publish video-params and
-        // the PlatformView can be mounted. widListener rebinds --vid after
-        // the real Surface arrives, avoiding the null-window decoder loop.
-        'vid': 'auto',
+        // The PlatformView is mounted before video-params are available. Its
+        // SurfaceAvailable callback then supplies widListener with a valid
+        // native window and enables the video track.
+        'vid': configuration.usePlatformView ? 'no' : 'auto',
         'force-window': 'yes',

```

### ordinal 378 — media_kit_video/lib/src/video_controller/android_video_controller/real.dart

```diff
@@ -112,7 +112,3 @@
       final voValue = widValue == '0' ? 'null' : configuration.vo!;
-      // mediacodec_embed must not be started before the PlatformView Surface
-      // exists. The widget can mount the initial PlatformView without
-      // video-params; enabling the track here would make the decoder churn on
-      // a null native window during the first open.
-      final vidValue = widValue == '0' ? 'no' : 'auto';
+      final vidValue = 'auto';
       // It is important to re-initialize --vo after --android-surface-size.
@@ -126,5 +122,2 @@
         // Not doing so causes error "Could not open codec." & video never gets rendered.
-        // PlatformView must wait for its Surface before enabling the track;
-        // otherwise MediaCodec starts with a null native window and repeatedly
-        // tears down/recreates the decoder during startup.
         if (configuration.vo == 'mediacodec_embed') 'vid': vidValue,

```

### ordinal 390 — media_kit_video/lib/src/video_controller/android_video_controller/real.dart

```diff
@@ -260,6 +260,3 @@
         'hwdec': configuration.hwdec!,
-        // The PlatformView is mounted before video-params are available. Its
-        // SurfaceAvailable callback then supplies widListener with a valid
-        // native window and enables the video track.
-        'vid': configuration.usePlatformView ? 'no' : 'auto',
+        'vid': 'auto',
         'force-window': 'yes',

```

### ordinal 461 — media_kit_video/lib/src/video_controller/android_video_controller/real.dart

```diff
@@ -73,2 +73,3 @@
   Future<void> _updateTargetColor(VideoParams event) async {
+    if (!configuration.usePlatformView) return;
     // mpv emits empty video-params notifications while rebuilding the video
@@ -122,3 +123,5 @@
         // Not doing so causes error "Could not open codec." & video never gets rendered.
-        if (configuration.vo == 'mediacodec_embed') 'vid': vidValue,
+        if (configuration.usePlatformView ||
+            configuration.vo == 'mediacodec_embed')
+          'vid': vidValue,
       });
@@ -260,3 +263,3 @@
         'hwdec': configuration.hwdec!,
-        'vid': 'auto',
+        'vid': configuration.usePlatformView ? 'no' : 'auto',
         'force-window': 'yes',

```

### ordinal 634 — media_kit_video/lib/src/video_controller/android_video_controller/real.dart

```diff
@@ -113,3 +113,3 @@
       final voValue = widValue == '0' ? 'null' : configuration.vo!;
-      final vidValue = 'auto';
+      final vidValue = widValue == '0' ? 'no' : 'auto';
       // It is important to re-initialize --vo after --android-surface-size.

```
