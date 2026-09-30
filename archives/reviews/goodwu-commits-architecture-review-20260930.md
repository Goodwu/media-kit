# Goodwu 提交架构审查（2026-09-30）

> 性质：只读代码审查结论。未改动代码，未做实机复验；实机结论引用 `TASKS.md` 与 `archives/experiments/` 的既有记录，本文不重复背书。

## 1. 范围与方法

- **对象**：`git log --author=Goodwu`，共 213 个提交（2026-09-01 → 2026-09-30）。
- **分层**：
  - `38c4bdef chore: port media-kit integration from 08b baseline`（403 文件）把 PiliPlus 系 fork（`08b7b941`，含 Windows D3D11/mailbox、Linux GL 线程、控件改造、`bindings`/`utf8` 等）整体移植进来。**这部分视为继承基线**，本文只看它和上游的集成是否合理，不逐行审查。
  - `38c4bdef..96571a92`：你的实质工作。非归档部分 148 文件，+19.9k/−0.8k 行。
  - `a886f556`：合并上游 main（`d310049f`，236 提交），之后是合并补漏和清理。
- **对照基准**：上游 media-kit `d310049f`（合并入的上游 tip）。
- **执行的检查**：
  - `flutter analyze --no-pub lib`（media_kit_video）：**4 个 error**，其余为 info。
  - `flutter test --no-pub`：media_kit_video 12 通过、**1 个文件加载失败**；media_kit_test 48 个全部通过。
  - 读源码：Android、Darwin、OHOS 的 Dart 与原生层，`media_kit` 核心播放器，libs 的构建脚本，tool/，以及 CI。

## 2. 总体结论

**工程目标达成度高，可作为 PiliPlus 专用 fork 使用；但以"media-kit 库"的标准衡量，架构层面有明显偏离，现在还不具备回馈上游或长期低成本维护的条件。**

- **符合原框架的部分**：
  - 平台分派仍然是 `VideoController → PlatformVideoController → {Android, Native, Ohos}VideoController`。
  - 原生侧沿用 `VideoOutputManager/VideoOutput` 结构。
  - Darwin 代码放在 `common/darwin`，iOS/macOS 通过软链接共享，这是上游约定。
  - `media_kit` 保持不依赖 Flutter：broker 通过注入钩子接线，不直接用 MethodChannel。
- **主要偏离有三类**：
  1. **产品/实验逻辑下沉进库**：库代码里有单机型固件指纹、私有 ABI、调试探针；HDR 路由策略按样片 SHA 决定。
  2. **生命周期协议按平台各自演化**：Android、Darwin、OHOS 三套销毁/重建协议互不相同，控制器状态机膨胀到上游的约 7 倍。
  3. **交付链不闭合**：库默认拉取的 libmpv 不含你的 mpv/FFmpeg/libplacebo 修复，修复版只能靠本地 JAR 覆盖。

## 3. 做得好的地方（建议保留）

1. **所有权身份建模严谨**：Android PlatformView 用 `(handle, generation, viewId, surfaceGeneration, wid)` 五元组标识 Surface owner，配合 ReleaseSurface → ReleaseSurfaceOwner 双阶段 ACK 和 tombstone，正确处理了"旧 Surface 晚到销毁"和"JNI 地址复用"。这是上游一直没解决好的问题。
2. **销毁屏障分阶段**：`NativePlayer.dispose` 拆成 release → preTermination → `mpv_terminate_destroy` → postTermination。失败的回调保留在列表里可重试，不再像上游那样吞掉异常。
3. **owner broker 根因定位准确**：直接销毁 Engine 的崩溃，根因是 NativeCallable 蹦床随 isolate 失效。在引擎 detach 时先清掉 wakeup 回调，是方向正确的最小修复（上游 #1340 只修了 debug 构建）。
4. **切源间隙清空旧尺寸**：Player 在切源时发出空 `VideoParams`，这时清空尺寸缓存（`android_video_controller/real.dart:1326`），修复小且正确。
5. **按布局决定输出尺寸**：`calculateAndroidTextureOutputSizeForLayouts` 取所有挂载视图的最大需求，并且不超过源尺寸。数据显示 P5 PQ 全片 VO 掉帧从 2204 降到 11，收益明确，设计也通用。
6. **验收证据链完整**：区分事实、推断和未验证项，并且纠正了自己的错误结论（例如 8-bit 缓冲之谜、P4 的"100 倍偏差"其实是读回装置的缺陷）。方法论值得保留。

## 4. 问题清单（按严重度）

### P0：阻断"作为库发布或合入上游"

**P0-1 库代码包含单机型私有 ABI 和固件指纹**
- `media_kit_video/android/src/main/cpp/surface_dataspace.cpp:262-286`：比对 `ro.build.fingerprint == "HUAWEI/LYA-AL00/.../10.1.0.163C00"` 之后，从 `ANativeWindow` 偏移 `0x98` 读出 `perform` 函数指针，调用 op 19。
- `PlatformVideoView.java:44,118`：同一个指纹常量。
- **风险**：虽然指纹精确匹配，其他设备不会进入这个分支，但私有结构偏移属于未定义行为，这种代码不可能被上游接受。它把一台测试机的特例变成了库的永久负担。
- **建议**：把公开 setter 返回 -22 时的回退改成可注入的 `SurfaceDataspaceFallback` 扩展点，由 App（PiliPlus）或独立的 `media_kit_video_android_vendor_ext` 包注册。库默认只走公开 NDK 路径，失败就回退 SDR。

**P0-2 默认构建拿不到你的修复**
- `libs/android/media_kit_libs_android_video/android/build.gradle:61-64`：默认仍下载 `Predidit/libmpv-android-video-build v1.2.7`。
- 第 76 行的 `mediaKitLocalArm64Jar` 只是本地覆盖开关。
- P5 dovi 重标定、片尾相邻帧回退、OES `buffer_retire`、av_log 接管等关键修复都在 `Goodwu/mpv media-kit/android`（`5e26cf86`）以及 FFmpeg `fff3ee7`、libplacebo `c9fd879` 里。
- **后果**：任何人（包括 CI）按默认方式构建出来的包都不含这些修复，而 Dart/Java 侧的新逻辑可能依赖新的 mpv 行为，比如动态 `android-surface-size` 和 P5 路径。验收结论与可复现构建因此脱节。另外修复版只有 arm64。
- **建议**：
  - 在 Goodwu fork 发布带 SHA-256 的 release（全 ABI 或明确声明只支持 arm64），让 `build.gradle` 默认指向它。
  - 把 mpv、FFmpeg、libplacebo 三者的 commit 写进 `libs/*/CHANGELOG` 或 lock 文件。
  - 在 CI 里加一个 job，检查"JAR 里带有预期的版本标识"。

**P0-3 HDR 路由策略按样片 SHA 决定，并且放在测试 App 里**
- `media_kit_test/lib/common/sources/android_hdr_sample_identity.dart:29`：`androidHdrSampleSha256` 把文件哈希映射成 `AndroidHdrSample{hdr10, p84, p5, ...}`。
- `android_hdr_playback_policy.dart` 根据这个枚举选择 `vo/hwdec/target-trc/surfaceTransfer/stripP84Rpu`。
- 相关的 coordinator、backend、output slot 也都在 `media_kit_test`。
- **后果**：P0–P5 验收的"产品路径"实际上是**测试 App 的路径**。库本身没有"根据媒体元数据（`video-params` 的 gamma/primaries、`dolby-vision-profile`，加上显示能力）选择输出"的能力，PiliPlus 必须重新实现一遍，也就无法直接继承验收结论。
- **建议**：把策略提炼成库级别的 `HdrOutputPolicy`（纯函数，输入是 VideoParams、显示能力、平台能力，输出是 mpv 属性集合和输出拓扑），放进 `media_kit_video`，单测覆盖矩阵。样片 SHA 只作为测试夹具用于校验身份。

### P1：架构与可维护性

**P1-1 Android 控制器状态机过度膨胀**
- `android_video_controller/real.dart`：上游 299 行，现在 2057 行。
- 其中有 `_liveSurfaceOwners`、`_pendingSurfaceReleases`、`_queuedSurfaceBinds`、`_failedSurfaceBinds`、`_pendingFallbackIntentSerials`、`_authorizedFallbackIntentSerials`、两组重试 Timer 映射、静态 orphan 重试表、`_disposed/_fullyDisposed/_playerTerminated/_published` 四个布尔量，以及三个 Completer。
- 每个分支都有注释，逻辑本身能自洽，但状态之间的不变式没有集中表达，靠注释和实机回归维持。
- **建议**：把"Surface owner 生命周期"抽成独立的纯 Dart 类（例如 `SurfaceOwnerLedger`）。
  - 显式定义状态：`announced → queued → inFlight → bound → releasing → released | failed`，并定义合法迁移表。
  - MethodChannel 调用通过接口注入，这样可以在 VM 里做确定性单测，覆盖乱序、晚到和 ACK 失败，把目前靠实机注入的交错场景搬到单测里。
  - `AndroidVideoController` 只负责编排 mpv 属性。
  - 现有的 `CurrentOutputIntent` 已经是这个方向的雏形。

**P1-2 三个平台三套销毁协议**
- **Android**：`release` 回调，加上 `postTermination`、`isReleaseCallbacksActive` 和 `setPropertyStrictForRelease`。
- **Darwin**：`closePreTerminationOwnerAdmission`、`reservePreTerminationOwnerCreation`、`preTermination`，并且 `NativePlayer.dispose` 里有 `Platform.isMacOS || Platform.isIOS` 分支（`media_kit/lib/src/player/native/player/real.dart` 约 180-200 行）。
- **OHOS**：自己的 `_disposeOnce(playerReleasing:)`。
- **问题**：核心 Player 因此知道了具体平台的输出细节，破坏了 media_kit（播放器）和 media_kit_video（输出）的分层。
- **建议**：统一成一个 `NativeOutputOwner` 协议：`admit()` → `stopProducer()`（在 mpv 存活时调用）→ `releaseAfterTerminate()`。`NativePlayer` 只按阶段调度已登记的 owner，不再判断平台。三个平台的控制器都实现这个协议。

**P1-3 平台专用 API 泄漏到跨平台抽象**
- `PlatformVideoController` 基类新增了 `prepareAndroidTextureOutput`（117 行）、`createNativeOutput/configureHdrOutput` 返回 `dynamic`（122、130 行），以及 `nativeSurfaceCandidate/Active`。
- `VideoControllerConfiguration` 新增了 9 个平台/实验开关：`androidGpuApi`、`androidSurfaceTransfer`（注释写着"for HDR experiments"）、`androidSurfacePixelFormat`、`matchAndroidTextureOutputToLayout`、`useNativeSurface`、`useNativeWindow`（注释写着"W1 integration probe"）、`useHCPP` 等。
- `VideoController._publishTextureLayouts` 里又重复实现了一遍 Android 判断 `vo == 'gpu-next' && androidSurfaceTransfer`，和控制器内的 `_layoutSizedHdrPlatformView` 重复。
- **建议**：
  - 用类型化的 `HdrOutputConfiguration/HdrOutputReport` 替代 `dynamic` Map。
  - 平台配置收进 `AndroidVideoOptions`、`DarwinVideoOptions` 这样的子对象。
  - 实验开关不进公开 API，改为 `@visibleForTesting` 或 `--dart-define`。
  - "是否需要上报布局"由控制器自己声明，比如 `bool get wantsLayoutReports`，不要在包装层重复判断。

**P1-4 owner broker 是进程级静态的，存在多引擎误杀**
- `MpvOwnerBroker.onEngineDetach()`（`MpvOwnerBroker.java:54`）会终结**进程内所有已登记的** handle。在 add-to-app 或 FlutterEngineGroup、后台引擎等多引擎场景下，任何一个引擎 detach 都会调用 `mpv_terminate_destroy`，把其他仍在运行的引擎的播放器销毁掉，导致后者的 Dart 侧出现 use-after-free。
- 登记和注销走异步 MethodChannel，并用 `catchError` 吞掉错误（`mpv_owner_broker.dart`），登记失败时没有任何信号。
- broker 只在创建 AndroidVideoController 时接线，纯音频宿主覆盖不到（TASKS 已记录）。
- broker 通过 `import 'package:media_kit/src/...'` 跨包访问内部实现，analyzer 已报 `implementation_imports`。
- **建议**：
  - handle 按 `BinaryMessenger` 或引擎分组登记，detach 时只处理本引擎的 handle。
  - 从 `media_kit` 公开导出一个窄接口，例如 `NativeHandleLifecycle.addObserver`。
  - 长期看，把"清除 wakeup + terminate"的钩子放进 media_kit_libs_android 的原生层，让纯音频宿主也能覆盖。

**P1-5 诊断代码常驻生产路径**
- 库里有 `debug.media_kit.{late_pq,egl_hdr,vk_hdr}_probe` 系统属性探针，EGL/Vulkan 能力枚举（`probe_egl_pq_window`、`probe_vulkan_hdr_window`），以及 `Android.Capabilities`：它会列出所有 HEVC 解码器，还会 `eglInitialize/eglTerminate` 默认 display。
- `MetalSurfaceBlitter` 带帧采样统计。
- 多个 `bool.fromEnvironment('MEDIA_KIT_*')` 开关散落在控制器里。
- MethodChannel handler 无条件对每条消息调用 `debugPrint(call.method/arguments)`（这是上游原有写法，但你新增了大量高频事件，放大了问题）。
- **建议**：诊断能力移到 `media_kit_test` 或单独的 `*_diagnostics` 插件；库内只保留受 `kDebugMode` 或统一开关控制的轻量日志。其中 `Android.Capabilities` 里的 `eglTerminate(EGL_DEFAULT_DISPLAY)` 可能影响同进程的其他 EGL 用户，应优先移出库。

**P1-6 Darwin 原生 Surface 的帧驱动和同步方式**
- `NativeSurfaceView.swift:41` 用 `Timer(1/60)` 驱动绘制，没有和显示刷新同步：在 ProMotion 120Hz 屏上会限帧，暂停时也在空转。
- `MetalSurfaceBlitter.swift:144` 每帧在主线程执行 `command.waitUntilCompleted()`（注释承认这是保守做法）。
- 链路多了一次 GL → CVPixelBuffer → Metal 拷贝。
- **建议**：
  - 改用 `CADisplayLink`（iOS/macOS 14+）或 `CVDisplayLink` 驱动；只在有新帧时绘制，接入 `NativeFrameRegistry` 已有的 produced/presented epoch。
  - 用 `MTLSharedEvent` 或 `addCompletedHandler` 在帧完成后归还 buffer，替代主线程阻塞等待。
  - 长期评估 `useNativeWindow`（mpv 直接输出到 CAMetalLayer，通过 MoltenVK 或 libplacebo Metal），这样可以去掉整条中转链。

### P2：工程卫生

**P2-1 仓库体积和归档策略**
- `archives/` 占 **409 MB**（`.git` 461 MB），包含 1104 个文件、约 57 万行：logcat、png、ndjson、gz、patch、jar 探针源码。
- 这些大多是一次性实验证据，放在库仓库里会让每次 clone 都变重，而且和上游合并时噪声很大。
- **建议**：
  - 大文件证据移到 Git LFS，或独立的 `media-kit-evidence` 仓库或对象存储；本仓库只保留 Markdown 结论和索引。
  - 用 `git filter-repo` 瘦身需要单独授权，本次未执行。
  - `archives/README.md` 已经承认"221 篇未迁移、去重"，建议和瘦身一起处理。

**P2-2 硬编码本机路径和设备信息**
- `media_kit_test/lib/common/sources/sources_native.dart:20-21`：`/Users/wuweiwei1/Downloads/test-clips/...`。
- `tool/matrix-*.sh`、`merge-accept-*.sh`、`tool/README.md` 里有本机路径和设备序列号。
- `.vscode/launch.json` 被提交，共 329 行。
- **建议**：统一改用环境变量（例如 `MEDIA_KIT_TEST_CLIPS`、`ANDROID_SERIAL`），`.vscode/` 加入 `.gitignore`。

**P2-3 静态检查和测试已经红了**
- **analyze 的 4 个 error**：`lib/src/video/platform_view_video_ohos.dart:51-79` 使用 `OhosViewSurface`、`initSurfaceOhosView` 等只有 OHOS Flutter fork 才有的 API，在标准 Flutter 下无法解析。
  - 这个文件目前靠条件导入才没有进入标准平台的编译，但 analyzer、IDE 和 pub.dev 评分都会报错。
  - **建议**：拆成独立的 federated 插件包（例如 `media_kit_video_ohos`），或者把 analyzer 排除和 CI 分工写清楚。
- **`macos_video_texture_candidate_contract_test.dart` 加载失败**："candidate PlatformView ... must retain their composition order"。上游合并后 `video_texture.dart` 的文本变了，这类测试就断了，而 `b39a0f9d/d9be8fdf` 两个提交没有发现。
- **"契约测试"读源码文本**：9 个测试文件里有 7 个是 `File('lib/...').readAsStringSync()` 加上 `indexOf`/`RegExp`，逐字符匹配源码，其中 platform_view_entry 有 106 处、ohos_p1 有 64 处。这类测试验证的是文本，不是行为；格式化或重构一下就会失败，也无法发现真实的逻辑回归。
  - **建议**：改成 widget test 或 fake MethodChannel 的行为测试（配合 P1-1 的 Ledger 抽取）。纯文本契约只保留少数"禁止某个 API"的守卫。
- 上游 CI 的 package tests 被改成只在 PR 或手动触发时运行（`ci.yml:21` 等处）。push 到 main 不跑单测，这也是上面这个失败没被发现的原因之一。

**P2-4 测试 App 变成了诊断平台**
- `media_kit_test/lib/tests/01.single_player_single_video.dart`：上游 131 行，现在 2285 行，含 90 处 `fromEnvironment`。
- 加上 `P5CodecProbe.java` 和 3 个 native probe cpp，示例 App 的"示例"作用已经被淹没。
- **建议**：新建 `media_kit_hdr_lab` 这样的专用诊断 App；把 `01` 还原为上游示例，降低后续同步上游的冲突。

**P2-5 提交粒度**
- 213 个提交里有约 120 个是纯文档或证据（`docs:`、`记录…`、`补证…`），和代码提交交错。
- 这让 `git log`、`bisect` 和 cherry-pick 回上游都很困难，本次 63 处合并冲突的评估成本也因此增加。
- **建议**：代码和证据分开提交（最好分仓库）；代码提交保持"一个行为变更加对应测试"。

## 5. 优化路线建议（按投入产出排序）

| 顺序 | 事项 | 目的 |
| --- | --- | --- |
| 1 | 发布 Goodwu libmpv 全 ABI release 并设为默认下载源（P0-2） | 让验收结论可复现；CI 构建产物和实机验收版本一致 |
| 2 | 修复 analyze error 和失败的契约测试；恢复 push 触发 package tests（P2-3） | 止血，防止继续积累回归 |
| 3 | broker 按引擎分组，并改为公开接口（P1-4） | 消除多引擎误杀这一真实崩溃风险 |
| 4 | 厂商私有回退、诊断探针移出库（P0-1、P1-5） | 库只保留公开 API 路径 |
| 5 | 提炼 `HdrOutputPolicy` 进 media_kit_video（P0-3） | PiliPlus 能直接复用已验收的路由 |
| 6 | 抽取 `SurfaceOwnerLedger`，统一 `NativeOutputOwner` 生命周期（P1-1、P1-2） | 控制复杂度，把实机注入场景搬到单测 |
| 7 | 收敛公开配置 API（P1-3），Darwin 改用 DisplayLink 驱动加异步完成通知（P1-6） | API 稳定性和性能 |
| 8 | 仓库瘦身、证据外置、测试 App 拆分（P2-1、P2-2、P2-4） | 降低 clone 和合并上游的成本 |

如果目标是**向上游 media-kit 提 PR**，建议只拆出以下几个独立、通用的补丁：
- 切源时清空尺寸；
- 按布局计算 Texture 输出尺寸；
- release 回调的错误不再被吞；
- `NativeCallable` 的 wakeup 在 dispose 时先清除（对应 #1340 release 版）；
- Surface 五元组所有权（抽取 Ledger 之后）。

其余内容作为 PiliPlus fork 的私有补丁维护。

## 6. 本次未覆盖和局限

- port 基线 `38c4bdef` 带入的 Windows mailbox/D3D11、Linux GL 线程、控件改造只做了归属确认，没有逐行审查。
- mpv、FFmpeg、libplacebo fork 的 C 代码不在本仓库，未审查。
- 没有在设备上复验任何结论。多引擎误杀（P1-4）是基于代码路径的推断，未实测。
- `media_kit` 包的 `player_test.dart` 需要 libmpv 运行环境，本次没有运行。
