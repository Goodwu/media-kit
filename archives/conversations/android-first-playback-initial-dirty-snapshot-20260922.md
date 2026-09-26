# 首播问题前已有 dirty 修改的回放快照（2026-09-22）

本文件保存任务开始时已存在的 dirty worktree 证据。它们不是本轮首次修改，但因本次回退一起恢复到了 HEAD；保留此快照以便后续 review。原始来源为本项目 session JSONL 的 ordinal 28/35 命令输出。

## ordinal 28 command output
--- routing ---
# 中立团队路由

本文件是顶层 agent 的 always-on 编排规则。目标是在核心功能、用户明确要求、安全、权限、数据完整性和不可逆操作约束不降低的前提下，最小化执行、交接、审核、返工和失败尝试的总成本。允许任务结果明确记录后延期非关键边界、重构和文档。顶层 agent 是 Lead，不另起 Lead 实例；子 agent 不得创建或重新路由子 agent。

## 能力预检与运行时核验

模型名称、角色配置或模型目录只是假设，不是能力证据。顶层 agent 在决定直接执行或分派前，先将任务写成最小能力契约：所需判断难度、读写与执行权限、工具或设备、上下文范围、可接受错误影响和验收方式。顶层 agent 直接执行时，确认当前会话和环境满足契约；不满足时分派给能满足契约的原生角色，或记录能力缺口并停止该工作包。不得通过降低验收、猜测模型能力或改变任务定义来绕过预检。

分派原生角色时必须依次核验：角色已由适配层声明且可创建；请求的能力、工具、权限和运行时参数与任务契约匹配；子会话的实际运行记录确认角色、模型、推理强度、工作目录和必要的 sandbox/权限，并完成一次可审计调用。配置解析、角色列表、创建请求成功或目录中的文件存在，均不能替代实际运行证据。任何关键字段缺失、未知或不匹配，都视为能力核验失败，停止该工作包；不得改用通用角色、另一个模型或直接启动器继续。

能力预检不是通用 benchmark，也不是要求顶层 agent 先创建一个 Lead 来证明自己；它是针对当前任务的边界和可验证运行时证据。任务完成后仍须按本文件的 V0/V1/V2 规则验收，能力核验通过不等于任务结果通过。

## 分派门槛

默认不分派。顶层 agent 已有足够上下文、下一步明显、只需少量工具操作、任务接近完成，或交接会让子 agent 重读同样材料而不改变结论时，直接执行。优先使用确定性工具和已有证据。

只有分派带来明确边际价值时才创建角色：低成本能力可完成大量独立工作；只读调查可隔离上下文；工作可真正并行；独立判断能降低确认偏差；需要独立环境或长时间执行；或当前推理/实施超过顶层 agent 的能力边界。默认零个子 agent，通常最多一个；只有互不依赖的工作才并行两个，硬上限四个。不得为同一搜索、同一写入或依赖前项结果的工作并行创建角色。

成本闸门只约束“可选且仅为节省成本”的分派：在可以合理估算时，比较“顶层直接完成”与“顶层交接加子 agent 加审核/返工”的完整费率等价成本；只有预期严格低于直接路线且有独立质量收益时才允许该类分派。无法估算或预期不低于直接路线时保持零分派，并把不确定性记录为停止条件。能力不足所需的升级、独立环境/设备证据，以及 V1/V2 审核不受成本闸门阻止：它们必须分派、记录全部成本，并按质量和能力证据验收。Luna 顶层直接执行仅限低风险、范围明确且有确定性验收的任务；不得为达成价格目标而降低能力、权限或审核。Cost Lab 的小型局部实现样本目前只是待纠正的历史材料；在取得完整新证据前，不得为小型局部任务仅以“Worker 更便宜”为理由创建子 agent。

开工记录目标、验收、错误影响、任务不确定性、唯一写入者和升级条件；简单任务不强制独立任务卡。交接仅含目标、范围、关键事实、产物版本、写入权、验收与升级条件。返回结论、证据位置、实际范围、未知项和验证状态。

## 能力路由

| 类别 | 准入条件 | 默认执行 | 质量保障 |
| --- | --- | --- | --- |
| 直接工具任务 | 下一步明确，现成命令或脚本可完成 | 顶层 agent | 检查实际结果 |
| 只读事实任务 | 文件、日志、调用/数据流、引用或材料事实追踪 | Scout | Lead 核查关键证据 |
| 困难判断 | 冲突约束、根因、架构、安全或关键领域推理 | Specialist | 独立关键审核（适用时） |
| 机械修改 | 规则确定、影响受限、结果可确定性验证 | Mechanical Worker | V0：既定检查 |
| 低风险常规实施 | 局部功能、修复或测试；接口、范围与核心验收明确 | Worker | V0 或 V1 |
| 复杂实施 | 跨模块状态、并发、生命周期或复杂调试；方案已经明确 | Escalated Worker | V1，风险高时 V2 |
| 独立运行证据 | 复现、集成、设备或长时验证不能由当前执行者可靠完成 | Verifier | 可复核证据包 |

Scout 可以跨文件机械追踪调用链、数据流、引用和材料事实。冲突证据判断、根因推断、设计取舍、验收标准或最终通过返回顶层 agent；必要时再路由 Specialist。Specialist 只解决“应如何做”，不承担实施。Worker 允许实施任务卡明确要求的行为改变；仅在必须重新决定业务语义、扩大分配边界、核心验收不足或发现跨模块/并发/生命周期问题时停止并返回 Lead。Escalated Worker 解决已知方案的困难实施，不替代 Specialist。

机械修改必须同时满足：不重新决定业务语义、规则无歧义、影响范围明确、验收方法开工前存在且覆盖预期变化。字面替换需提供精确 before/after 文本（含空白）或确定性命令。测试期望、权限配置、依赖升级、生命周期、关键运行参数、行为契约和跨模块状态不属于机械修改；规则未编码的行为改变应返回 Lead。

## 写入、验证与审核

一个任务阶段只有一个写入者。Scout、Specialist、Reviewer 保持只读。Verifier 可以写入测试产生物，但验证前后记录工作区基线，区分原有 dirty state、测试产生物与意外实现改动；不得修改、覆盖或清理被验证实现。多个 writer 只在隔离 worktree、范围不重叠且已定义整合方式时允许。

验证按成本由低到高使用：静态检查/schema/diff、build/lint、定向单测、更广自动化测试、集成测试、独立 Verifier、Reviewer、Critical Reviewer。低层证据足以回答的问题不得启动高层角色；构建成功、HTTP 200、进程或目录存在不自动代表业务验收通过。

审核按剩余不确定性与错误影响决定，不按“是否改过代码”决定。V0 是纯机械修改，或边界明确、回归有限、自动化验证充分的局部行为变更：无需独立模型审核。V1 在公共契约变化、验证覆盖不足、存在重要反例、影响范围难机械证明或 Lead 仍有实质不确定性时，调用 Reviewer 定向检查目标、diff、相关契约、证据和遗漏。V2 在权限/信任边界、认证授权、不可逆迁移、安全关键行为、跨模块并发或生命周期 invariant、冲突关键约束及难验证高影响修改时，直接调用 Critical Reviewer。Reviewer 不重复作者完整流程；同一产物版本与同一证据不重复审核。

## 停止与升级

当前环境无法创建指定原生角色、角色返回未知状态，或适配层要求的实际运行时身份无法核验时，记录能力缺口并停止该工作包；不得改用通用角色、另一个模型或直接启动器继续。新主会话可重新开始一次新的原生创建尝试。

升级只在当前角色达到能力边界、新证据提高风险、一次明确修正仍重复同类错误、关键证据冲突、验证推翻原假设或任务边界扩大时发生。未知根因按 Worker → Lead → Scout/Specialist → Worker 的路径处理；不要直接用更强 writer 继续猜测。轻量执行者基于明确反馈最多修正一次；两轮没有新证据或有效进展即停止当前路径并重新诊断。设备、权限、依赖、需求、工具或必要数据缺失是阻塞条件，不能以换模型、降低测试、改期望或删功能解决。
--- android sources ---
media_kit_video/lib/src/video_controller/ohos_video_controller/stub.dart
media_kit_video/lib/src/video_controller/ohos_video_controller/ohos_video_controller.dart
media_kit_video/lib/src/video_controller/ohos_video_controller/real.dart
media_kit_video/lib/src/video_controller/web_video_controller/stub.dart
media_kit_video/lib/src/video_controller/web_video_controller/web_video_controller.dart
media_kit_video/lib/src/video_controller/web_video_controller/real.dart
media_kit_video/lib/src/video_controller/platform_video_controller.dart
media_kit_video/lib/src/video_controller/native_video_controller/stub.dart
media_kit_video/lib/src/video_controller/native_video_controller/native_video_controller.dart
media_kit_video/lib/src/video_controller/native_video_controller/real.dart
media_kit_video/lib/src/video_controller/android_video_controller/stub.dart
media_kit_video/lib/src/video_controller/android_video_controller/real.dart
media_kit_video/lib/src/video_controller/android_video_controller/android_video_controller.dart
media_kit_video/lib/src/video_controller/video_controller.dart
--- diff controller ---
diff --git a/media_kit_video/android/src/main/java/com/alexmercerind/media_kit_video/platformview/PlatformVideoView.java b/media_kit_video/android/src/main/java/com/alexmercerind/media_kit_video/platformview/PlatformVideoView.java
index 49af763..49b4300 100644
--- a/media_kit_video/android/src/main/java/com/alexmercerind/media_kit_video/platformview/PlatformVideoView.java
+++ b/media_kit_video/android/src/main/java/com/alexmercerind/media_kit_video/platformview/PlatformVideoView.java
@@ -15,16 +15,11 @@ import android.os.Handler;
 import android.os.Looper;
 import android.util.Log;
 import android.view.SurfaceHolder;
+import android.view.Surface;
 import android.view.SurfaceView;
 import android.view.View;
-import android.view.SurfaceControl;
 import android.hardware.DataSpace;

-import java.util.concurrent.CountDownLatch;
-import java.util.concurrent.Executor;
-import java.util.concurrent.TimeUnit;
-import java.util.concurrent.atomic.AtomicBoolean;
-
 import androidx.annotation.NonNull;

 import io.flutter.plugin.platform.PlatformView;
@@ -36,14 +31,30 @@ import com.alexmercerind.media_kit_video.GlobalObjectRefManager;
  */
 public final class PlatformVideoView implements PlatformView {
     private static final String TAG = "PlatformVideoView";
+    private static final boolean HDR_NATIVE_BRIDGE_LOADED;
+
+    static {
+        boolean loaded = false;
+        try {
+            System.loadLibrary("media_kit_video_hdr");
+            loaded = true;
+        } catch (UnsatisfiedLinkError error) {
+            Log.e(TAG, "Unable to load HDR native bridge", error);
+        }
+        HDR_NATIVE_BRIDGE_LOADED = loaded;
+    }
+
+    private static native boolean nativeSetBuffersDataSpace(
+            @NonNull android.view.Surface surface, int dataSpace);
+
     private static final Handler handler = new Handler(Looper.getMainLooper());
-    private static final Executor transactionExecutor = Runnable::run;
     @NonNull
     private final SurfaceView surfaceView;
     private final long handle;
     private final int width;
     private final int height;
     private long wid = 0;
+    private String colorTransfer = null;
     private final Consumer<Long> onSurfaceAvailable;

     /**
@@ -91,7 +102,7 @@ public final class PlatformVideoView implements PlatformView {
                     // Get global reference to the Surface only once when it's first created
                     wid = GlobalObjectRefManager.newGlobalObjectRef(holder.getSurface());
                     Log.i(TAG, "surfaceCreated: created new wid=" + wid);
-                    holder.setFixedSize(width, height);
+                    applyNativeColorSpace(holder.getSurface());
                     // Notify Dart side about the PlatformView Surface availability
                     onSurfaceAvailable.accept(wid);
                 }
@@ -129,48 +140,33 @@ public final class PlatformVideoView implements PlatformView {

     /** Applies the display dataspace only after the decoder has identified HDR. */
     public boolean setColorSpace(@NonNull String transfer) {
-        // HCPP is gated at API 34 by the app. Keep this method equally strict:
-        // DataSpace/SurfaceControl dataspace support must never be resolved on
-        // older Android runtimes.
-        if (Build.VERSION.SDK_INT < 34 ||
-                !surfaceView.isAttachedToWindow()) {
+        colorTransfer = transfer;
+        if (Build.VERSION.SDK_INT < 28 || !HDR_NATIVE_BRIDGE_LOADED) {
+            return false;
+        }
+        return applyNativeColorSpace(surfaceView.getHolder().getSurface());
+    }
+
+    private boolean applyNativeColorSpace(@NonNull Surface surface) {
+        if (Build.VERSION.SDK_INT < 28 || !HDR_NATIVE_BRIDGE_LOADED ||
+                !surface.isValid() || colorTransfer == null) {
             return false;
         }
         final int dataSpace;
-        if ("pq".equals(transfer)) {
+        if ("pq".equals(colorTransfer)) {
             dataSpace = DataSpace.DATASPACE_BT2020_PQ;
-        } else if ("hlg".equals(transfer)) {
+        } else if ("hlg".equals(colorTransfer)) {
             dataSpace = DataSpace.DATASPACE_BT2020_HLG;
         } else {
             dataSpace = DataSpace.DATASPACE_SRGB;
         }
-        final SurfaceControl surfaceControl = surfaceView.getSurfaceControl();
-        if (!surfaceControl.isValid()) {
-            return false;
-        }
-        final CountDownLatch committed = new CountDownLatch(1);
-        final AtomicBoolean transactionCommitted = new AtomicBoolean(false);
-        try (SurfaceControl.Transaction transaction = new SurfaceControl.Transaction()) {
-            transaction
-                    .setDataSpace(surfaceControl, dataSpace)
-                    .addTransactionCommittedListener(transactionExecutor, () -> {
-                        transactionCommitted.set(true);
-                        committed.countDown();
-                    })
-                    .apply();
-            if (!committed.await(500, TimeUnit.MILLISECONDS)) {
-                Log.e(TAG, "setColorSpace: transaction commit timed out: handle=" + handle);
-                return false;
-            }
-            Log.i(TAG, "setColorSpace: handle=" + handle + ", transfer=" + transfer +
-                    ", transactionCommitted=" + transactionCommitted.get());
-            return transactionCommitted.get();
-        } catch (InterruptedException error) {
-            Thread.currentThread().interrupt();
-            Log.e(TAG, "setColorSpace: transaction wait interrupted: handle=" + handle, error);
-            return false;
+        try {
+            final boolean applied = nativeSetBuffersDataSpace(surface, dataSpace);
+            Log.i(TAG, "setColorSpace: handle=" + handle + ", transfer=" + colorTransfer +
+                    ", dataspace=" + dataSpace + ", nativeApplied=" + applied);
+            return applied;
         } catch (Throwable error) {
-            Log.e(TAG, "setColorSpace: handle=" + handle + ", transfer=" + transfer, error);
+            Log.e(TAG, "setColorSpace: handle=" + handle + ", transfer=" + colorTransfer, error);
             return false;
         }
     }
diff --git a/media_kit_video/lib/src/video/video_texture.dart b/media_kit_video/lib/src/video/video_texture.dart
index 6ebb155..846b215 100644
--- a/media_kit_video/lib/src/video/video_texture.dart
+++ b/media_kit_video/lib/src/video/video_texture.dart
@@ -490,8 +490,14 @@ class VideoState extends State<Video> with WidgetsBindingObserver {
                                                           .useNativeWindow
                                                       ? notifier
                                                           .nativeSurfaceCandidate
-                                                      : notifier
-                                                          .nativeSurfaceActive);
+                                                      : Platform.isAndroid &&
+                                                              notifier
+                                                                  .configuration
+                                                                  .usePlatformView
+                                                          ? notifier
+                                                              .nativeSurfaceCandidate
+                                                          : notifier
+                                                              .nativeSurfaceActive);
                                           final nativeOhosSurface =
                                               nativeSurface &&
                                                   Platform.operatingSystem ==
@@ -584,35 +590,52 @@ class VideoState extends State<Video> with WidgetsBindingObserver {
                                                 notifier.configuration
                                                     .useNativeWindow,
                                           );
+                                          final androidPlatformSurface =
+                                              Platform.isAndroid &&
+                                                  notifier.configuration
+                                                      .usePlatformView;
                                           return SizedBox(
                                             // Native OHOS surfaces must receive
                                             // the viewport size, not the decoder
                                             // rect. Platform views do not inherit
                                             // the scale produced by FittedBox.
-                                            width: nativeOhosSurface &&
+                                            width: androidPlatformSurface &&
                                                     viewportConstraints
                                                         .hasBoundedWidth
                                                 ? viewportConstraints.maxWidth
-                                                : nativeOhosSurface
-                                                    ? videoViewParameters.width
-                                                    : videoViewParameters
-                                                                .aspectRatio ==
-                                                            null
-                                                        ? rect.width
-                                                        : rect.height *
-                                                            videoViewParameters
-                                                                .aspectRatio!,
-                                            height: nativeOhosSurface &&
+                                                : nativeOhosSurface &&
+                                                        viewportConstraints
+                                                            .hasBoundedWidth
+                                                    ? viewportConstraints
+                                                        .maxWidth
+                                                    : nativeOhosSurface
+                                                        ? videoViewParameters
+                                                            .width
+                                                        : videoViewParameters
+                                                                    .aspectRatio ==
+                                                                null
+                                                            ? rect.width
+                                                            : rect.height *
+                                                                videoViewParameters
+                                                                    .aspectRatio!,
+                                            height: androidPlatformSurface &&
                                                     viewportConstraints
                                                         .hasBoundedHeight
                                                 ? viewportConstraints.maxHeight
-                                                : nativeOhosSurface
-                                                    ? videoViewParameters.height
-                                                    : rect.height,
+                                                : nativeOhosSurface &&
+                                                        viewportConstraints
+                                                            .hasBoundedHeight
+                                                    ? viewportConstraints
+                                                        .maxHeight
+                                                    : nativeOhosSurface
+                                                        ? videoViewParameters
+                                                            .height
+                                                        : rect.height,
                                             child: Stack(
                                               children: [
                                                 const SizedBox(),
-                                                if (nativeSurfaceCandidate)
+                                                if (nativeSurfaceCandidate &&
+                                                    !nativeSurface)
                                                   Positioned.fill(
                                                     // Keep the native candidate in
                                                     // one stable, painted element.
diff --git a/media_kit_video/lib/src/video_controller/android_video_controller/real.dart b/media_kit_video/lib/src/video_controller/android_video_controller/real.dart
index 8236ee6..58ad638 100644
--- a/media_kit_video/lib/src/video_controller/android_video_controller/real.dart
+++ b/media_kit_video/lib/src/video_controller/android_video_controller/real.dart
@@ -34,6 +34,8 @@ class AndroidVideoController extends PlatformVideoController {
   /// [Lock] used to synchronize [onLoadHooks], [onUnloadHooks] & [subscription].
   final lock = Lock();
   bool _disposed = false;
+  String? _targetTransfer;
+  bool _targetColorApplied = false;

   NativePlayer get platform => player.platform as NativePlayer;

@@ -47,6 +49,58 @@ class AndroidVideoController extends PlatformVideoController {
     }
   }

+  Future<void> _applyPlatformColorSpace() async {
+    if (!configuration.usePlatformView ||
+        wid.value == null ||
+        wid.value == 0 ||
+        !_targetColorApplied) {
+      return;
+    }
+    final handle = await player.handle;
+    final applied = await _channel.invokeMethod<bool>(
+      'PlatformVideoView.SetColorSpace',
+      {
+        'handle': handle.toString(),
+        'transfer': _targetTransfer ?? 'sdr',
+      },
+    );
+    debugPrint(
+      'AndroidVideoController: surface dataspace '
+      'transfer=${_targetTransfer ?? 'sdr'} applied=$applied',
+    );
+  }
+
+  Future<void> _updateTargetColor(VideoParams event) async {
+    // mpv emits empty video-params notifications while rebuilding the video
+    // output. They are not an SDR signal and must not reset an active HDR
+    // target in the middle of a surface/decoder transition.
+    if (event.gamma == null) return;
+    final String? transfer;
+    if (event.gamma == 'pq') {
+      transfer = 'pq';
+    } else if (event.gamma == 'hlg') {
+      transfer = 'hlg';
+    } else {
+      transfer = null;
+    }
+    if (!_targetColorApplied && transfer == null) return;
+    if (_targetColorApplied && _targetTransfer == transfer) return;
+    _targetTransfer = transfer;
+    _targetColorApplied = true;
+    await setProperties({
+      'target-prim': transfer == null ? 'bt.709' : 'bt.2020',
+      'target-trc': transfer ?? 'bt.1886',
+      'target-colorspace-hint': transfer == null ? 'auto' : 'yes',
+    });
+    await _applyPlatformColorSpace();
+    debugPrint(
+      'AndroidVideoController: target color '
+      'prim=${transfer == null ? 'bt.709' : 'bt.2020'} '
+      'trc=${transfer ?? 'bt.1886'} '
+      'hint=${transfer == null ? 'auto' : 'yes'}',
+    );
+  }
+
   /// Listener for updating the --wid property.
   Future<void> widListener() {
     return lock.synchronized(() async {
@@ -56,7 +110,10 @@ class AndroidVideoController extends PlatformVideoController {
       final widValue = wid.value?.toString() ?? '0';
       // When --wid is 0, vo=null is required to avoid SIGSEGV.
       final voValue = widValue == '0' ? 'null' : configuration.vo!;
-      final vidValue = widValue == '0' ? 'no' : 'auto';
+      // Keep the video track enabled while a PlatformView is being rebound.
+      // Setting vid=no for wid=0 prevents the next file from emitting
+      // video-params, so no new PlatformView can be mounted to provide wid.
+      final vidValue = 'auto';


## ordinal 35 command output
/// This file is a part of media_kit (https://github.com/media-kit/media-kit).
///
/// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
/// All rights reserved.
/// Use of this source code is governed by MIT license that can be found in the LICENSE file.
import 'dart:io';
import 'dart:async';
import 'dart:collection';

import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:synchronized/synchronized.dart';

import 'package:media_kit/media_kit.dart';

import 'package:media_kit_video/src/utils/query_decoders.dart';
import 'package:media_kit_video/src/video_controller/platform_video_controller.dart';

/// {@template android_video_controller}
///
/// AndroidVideoController
/// ----------------------
///
/// The [PlatformVideoController] implementation based on native JNI & C/C++ used on Android.
///
/// {@endtemplate}
class AndroidVideoController extends PlatformVideoController {
  /// Whether [AndroidVideoController] is supported on the current platform or not.
  static bool get supported => Platform.isAndroid;

  /// Pointer address to the global object reference of `android.view.Surface` i.e. `(intptr_t)(*android.view.Surface)`.
  final ValueNotifier<int?> wid = ValueNotifier<int?>(null);

  /// [Lock] used to synchronize [onLoadHooks], [onUnloadHooks] & [subscription].
  final lock = Lock();
  bool _disposed = false;
  String? _targetTransfer;
  bool _targetColorApplied = false;

  NativePlayer get platform => player.platform as NativePlayer;

  Future<void> setProperty(String key, String value) async {
    await platform.setProperty(key, value, waitForInitialization: false);
  }

  Future<void> setProperties(Map<String, String> properties) async {
    for (final entry in properties.entries) {
      await setProperty(entry.key, entry.value);
    }
  }

  Future<void> _applyPlatformColorSpace() async {
    if (!configuration.usePlatformView ||
        wid.value == null ||
        wid.value == 0 ||
        !_targetColorApplied) {
      return;
    }
    final handle = await player.handle;
    final applied = await _channel.invokeMethod<bool>(
      'PlatformVideoView.SetColorSpace',
      {
        'handle': handle.toString(),
        'transfer': _targetTransfer ?? 'sdr',
      },
    );
    debugPrint(
      'AndroidVideoController: surface dataspace '
      'transfer=${_targetTransfer ?? 'sdr'} applied=$applied',
    );
  }

  Future<void> _updateTargetColor(VideoParams event) async {
    // mpv emits empty video-params notifications while rebuilding the video
    // output. They are not an SDR signal and must not reset an active HDR
    // target in the middle of a surface/decoder transition.
    if (event.gamma == null) return;
    final String? transfer;
    if (event.gamma == 'pq') {
      transfer = 'pq';
    } else if (event.gamma == 'hlg') {
      transfer = 'hlg';
    } else {
      transfer = null;
    }
    if (!_targetColorApplied && transfer == null) return;
    if (_targetColorApplied && _targetTransfer == transfer) return;
    _targetTransfer = transfer;
    _targetColorApplied = true;
    await setProperties({
      'target-prim': transfer == null ? 'bt.709' : 'bt.2020',
      'target-trc': transfer ?? 'bt.1886',
      'target-colorspace-hint': transfer == null ? 'auto' : 'yes',
    });
    await _applyPlatformColorSpace();
    debugPrint(
      'AndroidVideoController: target color '
      'prim=${transfer == null ? 'bt.709' : 'bt.2020'} '
      'trc=${transfer ?? 'bt.1886'} '
      'hint=${transfer == null ? 'auto' : 'yes'}',
    );
  }

  /// Listener for updating the --wid property.
  Future<void> widListener() {
    return lock.synchronized(() async {
      final width = rect.value?.width.toInt() ?? 1;
      final height = rect.value?.height.toInt() ?? 1;
      final androidSurfaceSizeValue = [width, height].join('x');
      final widValue = wid.value?.toString() ?? '0';
      // When --wid is 0, vo=null is required to avoid SIGSEGV.
      final voValue = widValue == '0' ? 'null' : configuration.vo!;
      // Keep the video track enabled while a PlatformView is being rebound.
      // Setting vid=no for wid=0 prevents the next file from emitting
      // video-params, so no new PlatformView can be mounted to provide wid.
      final vidValue = 'auto';
      // It is important to re-initialize --vo after --android-surface-size.
      await setProperty('vo', 'null');
      await setProperties({
        // ORDER IS IMPORTANT.
        'android-surface-size': androidSurfaceSizeValue,
        'wid': widValue,
        'vo': voValue,
        // It is important to re-initialize --vid in-case of --vo=mediacodec_embed.
        // Not doing so causes error "Could not open codec." & video never gets rendered.
        // PlatformView must wait for its Surface before enabling the track;
        // otherwise MediaCodec starts with a null native window and repeatedly
        // tears down/recreates the decoder during startup.
        if (configuration.vo == 'mediacodec_embed') 'vid': vidValue,
      });
      await _applyPlatformColorSpace();
      // Do not seek here. A Surface rebind is also used for orientation
      // changes; seeking at this point flushes MediaCodec a second time and
      // turns a simple output rebind into a visible blank/loading interval.
    });
  }

  /// [StreamSubscription] for listening to video [Rect].
  StreamSubscription<VideoParams>? videoParamsSubscription;

  /// {@macro android_video_controller}
  AndroidVideoController._(super.player, super.configuration) {
    _channel; // Access _channel to trigger its initialization when the class is first accessed.
    wid.addListener(widListener);
    videoParamsSubscription = player.stream.videoParams.listen(
      (event) => lock.synchronized(() async {
        await _updateTargetColor(event);
        final int width;
        final int height;
        if (event.rotate == 0 || event.rotate == 180) {
          width = event.dw ?? 0;
          height = event.dh ?? 0;
        } else {
          // width & height are swapped for 90 or 270 degrees rotation.
          width = event.dh ?? 0;
          height = event.dw ?? 0;
        }

        final isZero = width == 0 || height == 0;
        final isSame = width == rect.value?.width.toInt() &&
            height == rect.value?.height.toInt();
        if (isZero || isSame) {
          return;
        }

        final handle = await player.handle;

        // For PlatformView, we don't need to call SetSurfaceSize
        // The Surface size is managed by the PlatformView itself
        // We only need to update the rect and trigger widListener if wid is already set
        if (!configuration.usePlatformView) {
          await _channel.invokeMethod('VideoOutputManager.SetSurfaceSize', {
            'handle': handle.toString(),
            'width': width.toString(),
            'height': height.toString(),
          });
        }

        rect.value = Rect.fromLTWH(
          0.0,
          0.0,
          width.toDouble(),
          height.toDouble(),
        );

        if (!waitUntilFirstFrameRenderedCompleter.isCompleted) {
          waitUntilFirstFrameRenderedCompleter.complete();
        }
      }),
    );
  }

  /// {@macro android_video_controller}
  static Future<PlatformVideoController> create(
    Player player,
    VideoControllerConfiguration configuration,
  ) async {
    Future<String> getDefaultHwdec() async {
      // Enforce software rendering in emulators.
      bool hw = configuration.enableHardwareAcceleration;
      final bool isEmulator = await _channel.invokeMethod('Utils.IsEmulator');
      if (isEmulator) {
        hw = false;
        debugPrint('media_kit: Emulator detected.');
        debugPrint('media_kit: Enforcing S/W rendering.');
      }
      return hw ? 'auto-safe' : 'no';
    }

    // Update [configuration] to have default values.
    configuration = configuration.copyWith(
      vo: configuration.vo ?? 'gpu',
      hwdec: configuration.hwdec ?? await getDefaultHwdec(),
    );

    // Retrieve the native handle of the [Player].
    final handle = await player.handle;
    // Return the existing [VideoController] if it's already created.
    if (_controllers.containsKey(handle)) {
      return _controllers[handle]!;
    }

    // In case no video-decoders are found, this means media_kit_libs_***_audio is being used.
    // Thus, --vid=no is required to prevent libmpv from trying to decode video (otherwise bad things may happen).
    //
    // Search for common H264 decoder to check if video support is available.
    final decoders = await queryDecoders(handle);
    if (!decoders.contains('h264')) {
      throw UnsupportedError(
        '[VideoController] is not available.'
        ' '
        'Please use media_kit_libs_***_video instead of media_kit_libs_***_audio.',
      );
    }

    // Creation:
    final controller = AndroidVideoController._(player, configuration);

    // Register [_dispose] for execution upon [Player.dispose].
    player.platform?.release.add(controller._dispose);

    // Store the [VideoController] in the [_controllers].
    _controllers[handle] = controller;

    // Serialize native output creation with initial mpv properties. Surface
    // callbacks can arrive synchronously/asynchronously from Create and would
    // otherwise enter widListener while vo/hwdec/vid are still being set.
    await controller.lock.synchronized(() async {
      // For PlatformView, we don't create VideoOutput (SurfaceProducer) here
      // The Surface will be provided by PlatformViewVideo widget
      // For TextureView, create VideoOutput normally
      if (!configuration.usePlatformView) {
        await _channel.invokeMethod('VideoOutputManager.Create', {
          'handle': handle.toString(),
          'enableSurfaceProducer': configuration.enableAndroidSurfaceProducer,
        });
      }

      if (configuration.usePlatformView) {
        controller.id.value = handle;
      }

      await controller.setProperties({
        // It is necessary to set vo=null here to avoid SIGSEGV, --wid must be assigned before vo=gpu is set.
        'vo': 'null',
        'hwdec': configuration.hwdec!,
        // Keep the video track enabled so mpv can publish video-params and
        // the PlatformView can be mounted. widListener rebinds --vid after
        // the real Surface arrives, avoiding the null-window decoder loop.
        'vid': 'auto',
        'force-window': 'yes',
        'gpu-api': configuration.vo == 'gpu-next' ? 'vulkan,opengl' : 'auto',
        'sub-use-margins': 'no',
        'sub-font-provider': 'none',
        'sub-scale-with-window': 'yes',
        'hwdec-codecs': 'h264,hevc,mpeg4,mpeg2video,vp8,vp9,av1',
      });
    });

    // Return the [PlatformVideoController].
    return controller;
  }

  /// Sets the required size of the video output.
  /// This may yield substantial performance improvements if a small [width] & [height] is specified.
  ///
  /// Remember:
  /// * “Premature optimization is the root of all evil”
  /// * “With great power comes great responsibility”
  @override
  Future<void> setSize({int? width, int? height}) {
    throw UnsupportedError(
      '[AndroidVideoController.setSize] is not available on Android',
    );
  }

  /// Disposes the instance. Releases allocated resources back to the system.
  @override
  Future<void> disposeForRebuild() => _dispose();

  /// Disposes the instance. Releases allocated resources back to the system.
  Future<void> _dispose() async {
    if (_disposed) return;
    _disposed = true;
    super.dispose();
    wid.dispose();
    wid.removeListener(widListener);
    await videoParamsSubscription?.cancel();
    final handle = await player.handle;
    _controllers.remove(handle);
    if (!configuration.usePlatformView) {
      await _channel.invokeMethod('VideoOutputManager.Dispose', {
        'handle': handle.toString(),
      });
    }
  }

  /// Currently created [AndroidVideoController]s.
  static final _controllers = HashMap<int, AndroidVideoController>();

  /// [MethodChannel] for invoking platform specific native implementation.
  static final _channel = const MethodChannel(
    'com.alexmercerind/media_kit_video',
  )..setMethodCallHandler((MethodCall call) async {
      try {
        debugPrint(call.method.toString());
        debugPrint(call.arguments.toString());
        switch (call.method) {
          case 'VideoOutput.Resize':
            {
              // Notify about updated texture ID & [Rect].
              final int handle = call.arguments['handle'];
              final Rect rect = Rect.fromLTWH(
                call.arguments['rect']['left'] * 1.0,
                call.arguments['rect']['top'] * 1.0,
                call.arguments['rect']['width'] * 1.0,
                call.arguments['rect']['height'] * 1.0,
              );
              final int id = call.arguments['id'];
              final int wid = call.arguments['wid'];
              _controllers[handle]?.rect.value = rect;
              _controllers[handle]?.id.value = id;
              _controllers[handle]?.wid.value = wid;
              break;
            }
          case 'VideoOutput.WaitUntilFirstFrameRenderedNotify':
            {
              // Notify about updated texture ID & [Rect].
              final int handle = call.arguments['handle'];
              debugPrint(handle.toString());
              // Notify about the first frame being rendered.
              final completer =
                  _controllers[handle]?.waitUntilFirstFrameRenderedCompleter;
              if (!(completer?.isCompleted ?? true)) {
                completer?.complete();
              }
              break;
            }
          case 'PlatformVideoView.SurfaceAvailable':
            {
--- remaining diff ---
diff --git a/media_kit_video/lib/src/video_controller/android_video_controller/real.dart b/media_kit_video/lib/src/video_controller/android_video_controller/real.dart
index 8236ee6..58ad638 100644
--- a/media_kit_video/lib/src/video_controller/android_video_controller/real.dart
+++ b/media_kit_video/lib/src/video_controller/android_video_controller/real.dart
@@ -34,6 +34,8 @@ class AndroidVideoController extends PlatformVideoController {
   /// [Lock] used to synchronize [onLoadHooks], [onUnloadHooks] & [subscription].
   final lock = Lock();
   bool _disposed = false;
+  String? _targetTransfer;
+  bool _targetColorApplied = false;

   NativePlayer get platform => player.platform as NativePlayer;

@@ -47,6 +49,58 @@ class AndroidVideoController extends PlatformVideoController {
     }
   }

+  Future<void> _applyPlatformColorSpace() async {
+    if (!configuration.usePlatformView ||
+        wid.value == null ||
+        wid.value == 0 ||
+        !_targetColorApplied) {
+      return;
+    }
+    final handle = await player.handle;
+    final applied = await _channel.invokeMethod<bool>(
+      'PlatformVideoView.SetColorSpace',
+      {
+        'handle': handle.toString(),
+        'transfer': _targetTransfer ?? 'sdr',
+      },
+    );
+    debugPrint(
+      'AndroidVideoController: surface dataspace '
+      'transfer=${_targetTransfer ?? 'sdr'} applied=$applied',
+    );
+  }
+
+  Future<void> _updateTargetColor(VideoParams event) async {
+    // mpv emits empty video-params notifications while rebuilding the video
+    // output. They are not an SDR signal and must not reset an active HDR
+    // target in the middle of a surface/decoder transition.
+    if (event.gamma == null) return;
+    final String? transfer;
+    if (event.gamma == 'pq') {
+      transfer = 'pq';
+    } else if (event.gamma == 'hlg') {
+      transfer = 'hlg';
+    } else {
+      transfer = null;
+    }
+    if (!_targetColorApplied && transfer == null) return;
+    if (_targetColorApplied && _targetTransfer == transfer) return;
+    _targetTransfer = transfer;
+    _targetColorApplied = true;
+    await setProperties({
+      'target-prim': transfer == null ? 'bt.709' : 'bt.2020',
+      'target-trc': transfer ?? 'bt.1886',
+      'target-colorspace-hint': transfer == null ? 'auto' : 'yes',
+    });
+    await _applyPlatformColorSpace();
+    debugPrint(
+      'AndroidVideoController: target color '
+      'prim=${transfer == null ? 'bt.709' : 'bt.2020'} '
+      'trc=${transfer ?? 'bt.1886'} '
+      'hint=${transfer == null ? 'auto' : 'yes'}',
+    );
+  }
+
   /// Listener for updating the --wid property.
   Future<void> widListener() {
     return lock.synchronized(() async {
@@ -56,7 +110,10 @@ class AndroidVideoController extends PlatformVideoController {
       final widValue = wid.value?.toString() ?? '0';
       // When --wid is 0, vo=null is required to avoid SIGSEGV.
       final voValue = widValue == '0' ? 'null' : configuration.vo!;
-      final vidValue = widValue == '0' ? 'no' : 'auto';
+      // Keep the video track enabled while a PlatformView is being rebound.
+      // Setting vid=no for wid=0 prevents the next file from emitting
+      // video-params, so no new PlatformView can be mounted to provide wid.
+      final vidValue = 'auto';
       // It is important to re-initialize --vo after --android-surface-size.
       await setProperty('vo', 'null');
       await setProperties({
@@ -66,16 +123,15 @@ class AndroidVideoController extends PlatformVideoController {
         'vo': voValue,
         // It is important to re-initialize --vid in-case of --vo=mediacodec_embed.
         // Not doing so causes error "Could not open codec." & video never gets rendered.
-        if (configuration.vo == 'mediacodec_embed' &&
-            !configuration.usePlatformView)
-          'vid': vidValue,
+        // PlatformView must wait for its Surface before enabling the track;
+        // otherwise MediaCodec starts with a null native window and repeatedly
+        // tears down/recreates the decoder during startup.
+        if (configuration.vo == 'mediacodec_embed') 'vid': vidValue,
       });
-      // Instead of seeking to the start (Duration.zero), seek to the current playback position
-      // without jumping the user to the start of the media.
-      if (widValue != '0') {
-        final currentPosition = player.state.position;
-        await player.seek(currentPosition);
-      }
+      await _applyPlatformColorSpace();
+      // Do not seek here. A Surface rebind is also used for orientation
+      // changes; seeking at this point flushes MediaCodec a second time and
+      // turns a simple output rebind into a visible blank/loading interval.
     });
   }

@@ -88,6 +144,7 @@ class AndroidVideoController extends PlatformVideoController {
     wid.addListener(widListener);
     videoParamsSubscription = player.stream.videoParams.listen(
       (event) => lock.synchronized(() async {
+        await _updateTargetColor(event);
         final int width;
         final int height;
         if (event.rotate == 0 || event.rotate == 180) {
@@ -100,8 +157,7 @@ class AndroidVideoController extends PlatformVideoController {
         }

         final isZero = width == 0 || height == 0;
-        final isSame =
-            width == rect.value?.width.toInt() &&
+        final isSame = width == rect.value?.width.toInt() &&
             height == rect.value?.height.toInt();
         if (isZero || isSame) {
           return;
@@ -186,31 +242,39 @@ class AndroidVideoController extends PlatformVideoController {
     // Store the [VideoController] in the [_controllers].
     _controllers[handle] = controller;

-    // For PlatformView, we don't create VideoOutput (SurfaceProducer) here
-    // The Surface will be provided by PlatformViewVideo widget
-    // For TextureView, create VideoOutput normally
-    if (!configuration.usePlatformView) {
-      await _channel.invokeMethod('VideoOutputManager.Create', {
-        'handle': handle.toString(),
-        'enableSurfaceProducer': configuration.enableAndroidSurfaceProducer,
-      });
-    }
+    // Serialize native output creation with initial mpv properties. Surface
+    // callbacks can arrive synchronously/asynchronously from Create and would
+    // otherwise enter widListener while vo/hwdec/vid are still being set.
+    await controller.lock.synchronized(() async {
+      // For PlatformView, we don't create VideoOutput (SurfaceProducer) here
+      // The Surface will be provided by PlatformViewVideo widget
+      // For TextureView, create VideoOutput normally
+      if (!configuration.usePlatformView) {
+        await _channel.invokeMethod('VideoOutputManager.Create', {
+          'handle': handle.toString(),
+          'enableSurfaceProducer': configuration.enableAndroidSurfaceProducer,
+        });
+      }

-    if (configuration.usePlatformView) {
-      controller.id.value = handle;
-    }
+      if (configuration.usePlatformView) {
+        controller.id.value = handle;
+      }

-    await controller.setProperties({
-      // It is necessary to set vo=null here to avoid SIGSEGV, --wid must be assigned before vo=gpu is set.
-      'vo': 'null',
-      'hwdec': configuration.hwdec!,
-      'vid': 'auto',
-      'force-window': 'yes',
-      'gpu-api': configuration.vo == 'gpu-next' ? 'vulkan,opengl' : 'auto',
-      'sub-use-margins': 'no',
-      'sub-font-provider': 'none',
-      'sub-scale-with-window': 'yes',
-      'hwdec-codecs': 'h264,hevc,mpeg4,mpeg2video,vp8,vp9,av1',
+      await controller.setProperties({
+        // It is necessary to set vo=null here to avoid SIGSEGV, --wid must be assigned before vo=gpu is set.
+        'vo': 'null',
+        'hwdec': configuration.hwdec!,
+        // Keep the video track enabled so mpv can publish video-params and
+        // the PlatformView can be mounted. widListener rebinds --vid after
+        // the real Surface arrives, avoiding the null-window decoder loop.
+        'vid': 'auto',
+        'force-window': 'yes',
+        'gpu-api': configuration.vo == 'gpu-next' ? 'vulkan,opengl' : 'auto',
+        'sub-use-margins': 'no',
+        'sub-font-provider': 'none',
+        'sub-scale-with-window': 'yes',
+        'hwdec-codecs': 'h264,hevc,mpeg4,mpeg2video,vp8,vp9,av1',
+      });
     });

     // Return the [PlatformVideoController].
@@ -255,60 +319,59 @@ class AndroidVideoController extends PlatformVideoController {
   static final _controllers = HashMap<int, AndroidVideoController>();

   /// [MethodChannel] for invoking platform specific native implementation.
-  static final _channel =
-      const MethodChannel(
-        'com.alexmercerind/media_kit_video',
-      )..setMethodCallHandler((MethodCall call) async {
-        try {
-          debugPrint(call.method.toString());
-          debugPrint(call.arguments.toString());
-          switch (call.method) {
-            case 'VideoOutput.Resize':
-              {
-                // Notify about updated texture ID & [Rect].
-                final int handle = call.arguments['handle'];
-                final Rect rect = Rect.fromLTWH(
-                  call.arguments['rect']['left'] * 1.0,
-                  call.arguments['rect']['top'] * 1.0,
-                  call.arguments['rect']['width'] * 1.0,
-                  call.arguments['rect']['height'] * 1.0,
-                );
-                final int id = call.arguments['id'];
-                final int wid = call.arguments['wid'];
-                _controllers[handle]?.rect.value = rect;
-                _controllers[handle]?.id.value = id;
-                _controllers[handle]?.wid.value = wid;
-                break;
+  static final _channel = const MethodChannel(
+    'com.alexmercerind/media_kit_video',
+  )..setMethodCallHandler((MethodCall call) async {
+      try {
+        debugPrint(call.method.toString());
+        debugPrint(call.arguments.toString());
+        switch (call.method) {
+          case 'VideoOutput.Resize':
+            {
+              // Notify about updated texture ID & [Rect].
+              final int handle = call.arguments['handle'];
+              final Rect rect = Rect.fromLTWH(
+                call.arguments['rect']['left'] * 1.0,
+                call.arguments['rect']['top'] * 1.0,
+                call.arguments['rect']['width'] * 1.0,
+                call.arguments['rect']['height'] * 1.0,
+              );
+              final int id = call.arguments['id'];
+              final int wid = call.arguments['wid'];
+              _controllers[handle]?.rect.value = rect;
+              _controllers[handle]?.id.value = id;
+              _controllers[handle]?.wid.value = wid;
+              break;
+            }
+          case 'VideoOutput.WaitUntilFirstFrameRenderedNotify':
+            {
+              // Notify about updated texture ID & [Rect].
+              final int handle = call.arguments['handle'];
+              debugPrint(handle.toString());
+              // Notify about the first frame being rendered.
+              final completer =
+                  _controllers[handle]?.waitUntilFirstFrameRenderedCompleter;
+              if (!(completer?.isCompleted ?? true)) {
+                completer?.complete();
               }
-            case 'VideoOutput.WaitUntilFirstFrameRenderedNotify':
-              {
-                // Notify about updated texture ID & [Rect].
-                final int handle = call.arguments['handle'];
-                debugPrint(handle.toString());
-                // Notify about the first frame being rendered.
-                final completer =
-                    _controllers[handle]?.waitUntilFirstFrameRenderedCompleter;
-                if (!(completer?.isCompleted ?? true)) {
-                  completer?.complete();
-                }
-                break;
-              }
-            case 'PlatformVideoView.SurfaceAvailable':
-              {
-                // Notify about PlatformView Surface availability
-                final int handle = call.arguments['handle'];
-                final int wid = call.arguments['wid'];
-                _controllers[handle]?.wid.value = wid;
-                break;
-              }
-            default:
-              {
-                break;
-              }
-          }
-        } catch (exception, stacktrace) {
-          debugPrint(exception.toString());
-          debugPrint(stacktrace.toString());
+              break;
+            }
+          case 'PlatformVideoView.SurfaceAvailable':
+            {
+              // Notify about PlatformView Surface availability
+              final int handle = call.arguments['handle'];
+              final int wid = call.arguments['wid'];
+              _controllers[handle]?.wid.value = wid;
+              break;
+            }
+          default:
+            {
+              break;
+            }
         }
-      });
+      } catch (exception, stacktrace) {
+        debugPrint(exception.toString());
+        debugPrint(stacktrace.toString());
+      }
+    });
 }
--- Android build/cpp ---
group 'com.alexmercerind.media_kit_video'
version '1.0'

buildscript {
    repositories {
        google()
        mavenCentral()
    }

    dependencies {
        classpath 'com.android.tools.build:gradle:8.13.0'
    }
}

rootProject.allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

apply plugin: 'com.android.library'

android {
    namespace 'com.alexmercerind.media_kit_video'

    compileSdkVersion 36
    ndkVersion '28.2.13676358'
    experimentalProperties['android.ndk.suppressMinSdkVersionError'] = 21

    compileOptions {
        sourceCompatibility JavaVersion.VERSION_1_8
        targetCompatibility JavaVersion.VERSION_1_8
    }

    defaultConfig {
        minSdkVersion 16
        consumerProguardFiles 'proguard-rules.pro'

        externalNativeBuild {
            cmake {
                cppFlags '-std=c++17'
            }
        }
    }

    externalNativeBuild {
        cmake {
            path 'src/main/cpp/CMakeLists.txt'
        }
    }
}
media_kit_video/android/src/main/cpp/CMakeLists.txt
cmake_minimum_required(VERSION 3.22.1)

project(media_kit_video_hdr)

add_library(media_kit_video_hdr SHARED hdr_surface.cpp)

find_library(log-lib log)

target_link_libraries(media_kit_video_hdr ${log-lib} android)
media_kit_video/android/src/main/cpp/hdr_surface.cpp
#include <jni.h>

#include <android/log.h>
#include <android/native_window.h>
#include <android/native_window_jni.h>
#include <dlfcn.h>

namespace {
constexpr char kTag[] = "MediaKitVideoHDR";
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_alexmercerind_media_1kit_1video_platformview_PlatformVideoView_nativeSetBuffersDataSpace(
    JNIEnv* env,
    jclass,
    jobject surface,
    jint data_space) {
  if (surface == nullptr) {
    return JNI_FALSE;
  }

  ANativeWindow* window = ANativeWindow_fromSurface(env, surface);
  if (window == nullptr) {
    return JNI_FALSE;
  }

  // The plugin still supports minSdk 16. Resolve this API 28 symbol at
  // runtime so the native library remains loadable on older Androids.
  using SetBuffersDataSpace = int32_t (*)(ANativeWindow*, int32_t);
  void* native_window_library =
      dlopen("libnativewindow.so", RTLD_NOW | RTLD_LOCAL);
  const auto set_buffers_data_space = reinterpret_cast<SetBuffersDataSpace>(
      native_window_library == nullptr
          ? nullptr
          : dlsym(native_window_library, "ANativeWindow_setBuffersDataSpace"));
  if (set_buffers_data_space == nullptr) {
    __android_log_print(ANDROID_LOG_ERROR, kTag,
                        "Could not resolve ANativeWindow_setBuffersDataSpace");
    ANativeWindow_release(window);
    return JNI_FALSE;
  }
  const int32_t result = set_buffers_data_space(window, data_space);
  ANativeWindow_release(window);
  if (result != 0) {
    __android_log_print(ANDROID_LOG_ERROR, kTag,
                        "ANativeWindow_setBuffersDataSpace failed: %d", result);
    return JNI_FALSE;
  }
  return JNI_TRUE;
}
