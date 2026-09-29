# 直接 FlutterEngine.destroy 的 P5 播放崩溃复现（12646，2026-09-29）

## 结论

播放中直接 `FlutterEngine.destroy()`（绕过全部 Dart 清理路径）**确定性触发原生 SIGSEGV**，两轮 2/2 复现：

- 时序：`ANDROID_ENGINE_DESTROY requested`（媒体12秒）→ `EngineControl destroy_begin` → **10–13ms 后** `Fatal signal 11 (SEGV_MAPERR)` 于 `Thread-7` → 进程死亡（轮后 `pidof` 为空）。
- 崩溃栈（tombstone）：`#01 mpv_set_property_async+136 (libmpv.so)`，其上为 libmpv 内部两帧（无符号）。即引擎销毁触发 Java 插件拆卸时，某工作线程对正在并发释放的 mpv 句柄调用 `mpv_set_property_async`。
- 与既有记录同族：12486 时代 P5 长播后重入曾在 Flutter SurfaceTexture finalizer release 栈出现一次 SIGSEGV「归因未明」；本次拿到确定性复现与明确栈，归因到销毁竞态。
- 对照：正常 Back 退出（Dart dispose 先行）从未出现该崩溃（12627–12640 全批次零崩溃）。

## 探针实现（已随代码提交）

- `MainActivity.kt`：新增 `media_kit_test/engine_control` 通道，`DestroyEngineNow` 先回执再 `flutterEngine.destroy()`（引擎拥有回执通道的 messenger）。
- 测试页：`MEDIA_KIT_ANDROID_ENGINE_DESTROY_AT_SECONDS`（默认 -1 关闭）定时触发，播放中销毁。

## 复现包与证据

- 12646 APK SHA-256 `32bd1617fc40119367140faf8353d4114864a19b1f02385c612b8febcca3d076`（e0102cf + 12627 JAR + transaction define 集 + 销毁探针）。
- 两轮日志与 tombstone 栈：`/private/tmp/media-kit-p5-engine-destroy-12646-device.log`（第二轮覆盖第一轮，两者结论一致）、截图 `*-predestroy.png`（销毁前正常画面）/`*-postdestroy.png`。

## 修复方向与边界

TASKS「Android native output / 双视图生命周期回归」既有规划适用：任意宿主直接 `FlutterEngine.destroy` 需要独立于 Dart 的 Android 原生播放器 owner broker，统一 mpv 调用、事件/hook、终止和视频输出引用；修复前该崩溃会持续复现。本轮只复现并归因，不做架构修复。每轮结束 force-stop 恢复原 12492、自动亮度、熄屏（进程已死，无需 Back）。
