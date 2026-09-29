# 直接 FlutterEngine.destroy 的崩溃复现、根因与 owner broker 修复（12646–12654，2026-09-29）

## 结论

播放中直接 `flutterEngine.destroy()` 的确定性 SIGSEGV **已根因定位并修复**：`media_kit_video` 新增 Dart 无关的 owner broker，在引擎拆卸第一步（`onDetachedFromEngine`）经 JNI 清空全部 mpv wakeup 回调。修复后播放中直接销毁 **4/4 零崩溃**（对照基线 12/14 崩溃），正常 Back 退出路径回归不受影响。

## 根因

release 模式下 `InitializerNativeCallable.create`（`media_kit/lib/src/player/native/core/initializer_native_callable.dart`）把 `NativeCallable.listener` 蹦床注册为 mpv 的 wakeup 回调（`mpv_set_wakeup_callback`）。Dart isolate 拆卸使蹦床的**可执行内存失效**；直接销毁引擎时 Dart 清理路径完全不运行，而 mpv 仍在播放——下一次 wakeup（帧/属性事件，播放中每帧都可能）由 mpv 原生线程调用已失效蹦床 → 跳入已释放执行内存 → SIGSEGV（`pc == fault addr`，寄存器带 0xaaaa… 毒化模式；栈帧经 `blr x8` 函数指针，符号归属 `mpv_set_property_async+…` 为最近符号噪声）。

与 media-kit 上游 issue #1340 同类（该 issue 只在 debug 模式改用 isolate 实现规避，release 仍用 NativeCallable 以保性能）。12486 时代「P5 长播后重入 finalizer release 栈 SIGSEGV 归因未明」同族，本次拿到确定性复现与完整机制。

## 二分与排除实验（均实机，每轮恢复原 12492/自动亮度/熄屏）

| 轮次 | 配置 | 结果 | 推论 |
| --- | --- | --- | --- |
| 12646 | 无修复，播放中销毁 | 2/2 SIGSEGV（`Thread-7`，销毁后 10–13ms） | 确定性复现 |
| 12647 | 无媒体裸 Player 销毁 | 0/1 崩溃，进程存活 | 崩溃需要播放路径；裸 Player 终态干净（计划步骤①） |
| 12648 | 播放中暂停后销毁 | 0/1 崩溃 | 需要活跃渲染/事件，非 mpv 线程存在本身 |
| 12649 | +引擎拆卸时 disposeAll 视频输出 | 3/4 崩溃 | 表面释放不是根因 |
| 12650 | +销毁前 18ms 主线程 census | 0/4 崩溃 | 时序敏感（当时误导性地指向时序） |
| 12651 | +posted 50ms 延迟销毁 | 4/4 崩溃 | 延迟无效，排除「回调内重入销毁」假设 |
| 12652 | +Java `System.loadLibrary` 钉库 | 3/4 崩溃（含一次 scudo 风格 SIGABRT） | 排除「FFI dlclose 解除库映射」假设 |
| **12653** | **+owner broker 清空 wakeup 回调** | **4/4 零崩溃**，每轮 `clearWakeup: ctx=0x…` 确认 | **根因证实** |
| 12654 | 修复版正常 Back 退出 | 0 错误、资源闭合 2257/2257、dispose 完成 | 正常路径无回归 |

崩溃线程身份：播放期间新增的未命名 `Thread-N`（mpv 内部线程）+ census 显示的线程集合变化与「仅播放崩溃」一致；wakeup 回调恰由 mpv 线程调用。

## 修复实现（均已提交）

- `media_kit_video/android/src/main/cpp/surface_dataspace.cpp`：新增 JNI `MpvOwnerBroker_nativeClearWakeupCallback`，`dlopen(RTLD_NOLOAD)` + `dlsym` 取 `mpv_set_wakeup_callback`，对句柄清空回调。
- `MpvOwnerBroker.java`：静态句柄注册表 + `onEngineDetach()`（逐一清空，容错）。
- `MediaKitVideoPlugin.java`：新增 `media_kit/native_broker` 通道（Register/Unregister）；`onDetachedFromEngine` 顺序为 broker 清空 → `disposeAll` 视频输出 → 其余拆卸；另在附加时 `System.loadLibrary` 钉住 libmpv/libmediakitandroidhelper（纵深防御）。
- `media_kit` core：`InitializerNativeCallable` 暴露 `ownerBrokerRegistration` 注入钩子与 `liveHandleAddresses` 静态镜像（保持包不依赖 Flutter）；create/dispose 时注册/注销。
- `media_kit_video` Dart：`wireMpvOwnerBroker()` 在 `AndroidVideoController` 构造时接线并回填既有句柄（Player 先于控制器创建的场景）。

## 验证包

- 修复包 12653 SHA `fb9db20ec35cb4506c750e02480cfec9e9fa594c58319471f522b1265634d766`（e0102cf+12627 JAR+transaction define 集+销毁探针+broker）；正常路径回归 12654。
- 证据：`/private/tmp/media-kit-p5-engine-destroy-{12646,12647,12648,12649*,12650*,12651*,12652*,12653*}-device.log` 与 `/private/tmp/media-kit-p5-normal-back-12654-*`。
- 探针（已随代码提交）：MainActivity `engine_control` 通道 `DestroyEngineNow`（回执后 post 到主线程销毁，避免在 channel 分发内重入销毁）；测试页 `MEDIA_KIT_ANDROID_ENGINE_DESTROY_AT_SECONDS`（墙钟，无媒体也可用）。

## 终止增量（12655–12657，2026-09-30）

P3「直接 Engine 销毁后资源正确释放」闭环完成：

- 实现：C 侧新增 `MpvOwnerBroker_nativeTerminateDestroy`（dlsym `mpv_terminate_destroy`）；Java `onEngineDetach` 改为——主线程同步清空全部 wakeup 回调（必须先于 isolate 拆卸），随后在专用 broker 线程逐一 `mpv_terminate_destroy`（避免阻塞平台线程，销毁本身 30ms 完成）；注册/注销加日志。
- **销毁场景 12655 ×3 全过**：`clearWakeup`（主线程）→ broker 线程 `terminate begin` → `destroy_complete`（30ms，平台线程未阻塞）→ **`P5_RETIRE_FINAL`/`P5_IMAGE_FINAL`（949/949、held_after=0、retired=0）由 broker 终止触发** → `terminate complete`（75ms）；销毁后 `ps -T` 确认 mpv 线程（demux/MediaCodec_loop/ImageReader/AudioTrack/Thread-N）全部退出、进程存活（+10s 复核）、零崩溃。
- **正常 Back 路径 12657**：`register`（初始+回填，幂等）→ Dart dispose 完整执行 → `unregister` 到达 → 引擎拆卸时注册表为空、broker 零活动、`AUTO_PLAYER_DISPOSE completed`、资源闭合 2263/2263。
- 12656 为脚本失误轮（误装销毁探针包当正常 Back），其时序实际是销毁场景的正确行为，不构成异常证据。
- 双重释放分析：Dart 的 Unregister 在其 `mpv_terminate_destroy` 前 5 秒发出；若引擎在 dispose 完成前拆卸（messenger 存活、Dart 被杀），broker 终止的是存活句柄（安全）；dispose 完整完成的路径下 messenger 全程存活，Unregister 必然先于拆卸送达。构造上无双重终止窗口。

## 边界与后续

- 音频-only 宿主（无 media_kit_video 插件）不接线，保持原行为——记录在案。
- 每轮结束恢复原 12492、自动亮度、熄屏。