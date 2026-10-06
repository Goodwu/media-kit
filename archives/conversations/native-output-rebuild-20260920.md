# native output rebuild lifecycle

## Current State

2026-10-07 agent 接手轮：**OHOS 模拟器播放通道打通**（提交 67441db4）——sw 软件桥 + HCPP DISPLAY 直通组合在模拟器实机出画（清晰画面、帧推进、退出重入复播全通），"模拟器可视播放不可行"的旧定性就此推翻。详见下方 2026-10-07 HCPP 直通轮。

- 出画路径定性：TLHC（initSurfaceAndroidView）在模拟器不可修——其 XComponent 消费者是引擎外部纹理链，RS `bind external with nullptr gbuffer`（DGLES 缺陷）恒黑；HCPP（initHybridAndroidView + buildinfo `enable_ohos_hybrid_composition=true`）让系统合成器直通 XComponent surface（Luna E2 同款），绕开引擎纹理链。此前"模拟器 Impeller 门禁锁死 HCPP"系误判——真实原因仅是 buildinfo 未配 HCPP 开关。
- sw 桥三条硬修复：①生产者必须 SET_BUFFER_GEOMETRY（引擎消费侧恒 3×3 不 resize，不设几何则 RequestBuffer 恒 3×3，36 字节渲染缓冲、pixel_sum=0）；②几何随 videoParams 纠正（attach 时部件 rect 是布局前占位）；③绑定向 Dart 解析符号注入（mk_sw_start_ex；实测 same copy，双副本假设证伪但免疫化保留）。
- 遗留：XComponent 节点 3×3 需 Dart 传绝对物理像素（ohosSurfaceWidthPx/HeightPx → ets XComponent 绝对尺寸）绕开 embedding BuilderNode 不 resize 的缺陷；该改动对真机 TLHC 同样生效（节点从 '100%' 变绝对尺寸），真机回归待设备验证（blocked 不变）。
- 证据：`~/src/media-kit-build/ohos-emulator-evidence-20261007/`（mk11 出画首帧、mk12 动态帧、mk13 重入复播）。

2026-10-05 agent交接：macOS后续修复已在独立共享核心分支提交并推送252c5851，产品已提交推送68edf0ec9；本工作树补充保存历史实验记录。完整任务/已证/未证/下一步见 `/Users/wuweiwei1/src/PiliPlusX/archives/handoffs/macos-player-20261005.md`。当前核心源码身份以已审252c5851为准，不能把本记录工作树76440510当作最新候选核心。

- Release派生Info bootstrap的增量/target缺失/模板变化/未知模式/模式切换V2为PASS_RELEASE_BOOTSTRAP_MATRIX_WITH_LIMITS；derived缺失持久化前置记录与模板恢复SLF仍有限。
- Debug/Profile实际构建、当前shared consumer/最终包绑定、P5实际HDR/EDR及P8.4同PTS metadata、最终操作/长播/退出重入及受影响平台回归未完成；旧可见流畅通过仅对应旧候选，最新r4有卡顿FAIL。
- 用户授权保存交接、提交并推送；性能优化另专题，无Release/merge授权。证据目录仅报告/日志/源码快照/截图入Git，缓存及raw binary本地保留并索引；一条签名视频URL脱敏，原证据在本地handoff备份。
- 本次没有新增构建或播放。完整submission receipt：`/Users/wuweiwei1/src/media-kit-build/macos-agent-handoff-20261005/submission-receipt.json`；本记录分支推送receipt将追加其中。
- **分支归一注记（2026-10-05）**：codex/macos-shared-hdr-fix（252c5851）与 codex/macos-completion-handoff（0ecd4d9d）已按用户决策归一——前者代码同源并入 main 75743f5c（main 侧为超集），分支 ref 已删除，252c5851 作为已审 r4 快照身份引用仍有效；后者证据（macos-ppx-completion artifacts 596 文件 + 2 实验记录）已全量迁入 `~/src/media-kit-experiments`（提交 b4f9538），本文 `archives/experiments/` 前缀路径按 TASKS 路径映射规则指向该库根目录。

## Historical State (旧快照与实验过程，不替代当前交接)
- 2026-09-27 macOS 窗口复核：对现有 `/Users/wuweiwei1/src/PiliPlusX/build/macos/Build/Products/Debug/PiliPlusX.app` 执行 LaunchServices `open -n` 后，AppleScript 枚举到 1180×720 Aqua 窗口。此前“当前桌面环境无可操作窗口”已非持续阻断；尚未核对该包对应的 mpv 0.41 产品播放链、seek、重入、输出重建及 HDR 长播。
- 2026-09-27 OHOS 实机验收入口核验：当前主机 `hdc list targets` 返回 `[Empty]`，无可连接实体机；TASKS 将该项移至 Blocked，设备接入后重新核验身份、包与运行状态。
- 背景: 当前分支包含 macOS native surface、OHOS HDR surface 和播放器释放路径的协同修改。
- 目标: 提交本轮代码及对应契约测试，保留未纳入范围的协作文档和本地产物。
- 当前状态: 跨平台生命周期修复与 macOS 首帧呈现 gating 已分别提交。
- 2026-09-27 进展: Darwin Player 新增 preTermination 屏障及创建/销毁仲裁；隔离 Goodwu mpv 0.41 的 W0 测试包完成 SDR 首次出图、旧 Surface 释放、重建出图和 Player dispose，无 render-context abort。应用 Quit 未提供第二个 Surface 释放 ACK；真实 PiliPlusX 的有序退出、快速重入、seek 与 HDR 长播仍待验收。证据见 `archives/experiments/macos-w0-modern-20260927.md`。
- 2026-09-27 PiliPlusX 尝试: 本地 path override 已指向当前 media-kit，macOS Debug 构建通过；隔离包加载 final16 Goodwu mpv 0.41 后进程启动并运行 Dart/网络初始化，但未创建可操作窗口，无法进入播放。测试用 PiliPlusX 版本引用已恢复，临时包已清理。见 `archives/experiments/piliplusx-macos-3a4fcaa-launch-20260927.md`。
- 2026-09-27 第二输出释放: 增加默认关闭的测试页定时移除入口，W0/Goodwu mpv 0.41 实际播放两代 SDR 输出后移除第二代。两个 Surface 都有释放记录，两个 Player dispose 均完成，进程未 abort；见 `archives/experiments/macos-w0-remove-20260927.md`。未改动 final16 包也无可操作窗口，故产品链路验证仍开放。
- 关键结论:
  - native output 重建、释放和跨平台入口变更属于同一代码切片。
  - 新增 3 个契约测试覆盖 OHOS 生命周期、候选渲染分支和 platform-view 入口隔离。
  - 本地产生的 `libs/ohos/.../libs/` 未纳入提交。
  - 协作引导文件未纳入提交；TASKS 与本归档仅用于满足仓库提交上下文要求。
- 下一步:
  - 先修复 final11 运行时的 macOS modern-mpv render context 清理违约，再继续真实 macOS/OHOS 设备验证 native output 生命周期。
- final11-crash-20260920: PiliPlusX final11（Goodwu mpv 0.41.0）在运行态 SIGABRT。崩溃报告栈为 `mp_clients_destroy.cold.1 -> mp_clients_destroy -> mp_destroy -> mp_destroy_client`；实际二进制文本确认该分支为 `Broken API use: mpv_render_context_free() not called.`。`NativeVideoController._dispose` 当前先 `super.dispose()`，再 `detachNativeWindow()`，后者若 `active=true` 会写已释放的 notifier 并中断剩余清理；`NativePlayer.dispose` 即使 cleanup 失败仍延迟调用 `mpv_terminate_destroy`。本轮只修复这一 teardown 先后和完成屏障，不改 HDR 参数或 unrelated Android 已有 dirty changes。
- final11-teardown-fix-20260920: `NativeVideoController` 已改为共享 `_disposeFuture`，先禁止迟到回调、取消订阅并排空 lock，再无论中间单步是否失败都继续 detach、native output、Darwin `VideoOutputManager.Dispose`，最后才销毁 notifier并抛出首个错误。PiliPlusX 上层仅在 output barrier 成功后调用 `Player.dispose()`；barrier 失败时不终止 libmpv。新增 disposal contract script 和现有三份脚本均通过，目标 analyze 仅有本文件既有两条 info，diff-check 通过；未提交，等待独立 V1 审查与 final12 真机运行。
- final12-build-20260920: V1 独立审查已 PASS。若 cleanup 有任一错误，`NativeVideoController` 保留 notifier/controller registration 并清空 completed error Future，使上层能重试 render-context barrier；成功时才 unregister 并 `super.dispose()`。PiliPlusX 对每个 stale Player/output pair 保持 immutable ownership，且多 pair 的失败释放会被保留并自动重试。final12 已由 modern universal mpv 0.41.0 构建；media-kit 四份契约脚本、目标 analyze（两条既有 info）和 diff-check 通过。未提交；等待真实 macOS 播放、退出、快速重入、输出重建运行验收。
- final13-startup-flicker-fix-20260921: final12 真实 PID 的十分钟 unified log 有约 365 次 `CAMetalLayer` 零 drawable 警告。确认 `video_texture.dart` 在 macOS candidate→active 时重复挂载相同 `nativeVideo`，使第二个 `.zero` AppKitView 覆盖 factory owner 并清空已呈现状态。修复新增 `nativeMacosCandidate`，阻止 active legacy 分支再次挂载，保持 candidate 的单一平台视图和 inactive Texture fallback；Android/OHOS 不变。V1 审查 PASS，新增 macOS contract 和三份既有 contract、目标 analyze（三条既有 info）及 diff-check 通过。PiliPlusX final13 已构建，未提交；等待冷启动长播、seek、全屏、退出重入的真实验证。
- final14-fill-fix-20260921: final13 用户实测无闪烁、帧率初步正常，但唯一 macOS candidate 位于预留空间中央小区域。该 geometry regression 来自 candidate 保留了 `Center > SizedBox`，而被删除的重复 active view 曾填满区域。现仅改 candidate 的 macOS 子树直接填充 `Positioned.fill`，保留单一 view 和 `!nativeMacosCandidate` 去重；OHOS/Android 不变。V1 审查 PASS；四份契约脚本、目标 analyze（三条既有 info）与 diff-check 通过，PiliPlusX final14 已构建。未提交，等待实际填充/比例和生命周期验收。
- final16-frame-pacing-baseline-20260921: 用户确认 final14 前序视觉问题已好但平移仍有卡顿感；为避免在无运行时证据下裸删 GL/Metal 同步，新增仅 macOS、显式环境变量 `PILIPLUSX_FRAME_PACING_DIAGNOSTICS=1` 启用的汇总采样。首个实际视频 buffer 后统计最多 15 秒（900 tick 上界）的一条 summary：main tick、drawable、buffer reuse、Metal sequence gap、现有 `waitUntilCompleted()` CPU wait 和 command GPU duration。默认路径不创建 timing handler，不读取 pixel、不新建 command、不增加 completion handler/semaphore；`glFinish`、Metal wait/present 与 teardown 顺序不变。V1 PASS；focused contract、Swift parse/typecheck、Dart analyze、PiliPlusX macOS Debug build、48 项定向测试与两仓 diff-check 均通过。final16 等待固定平移段的真实汇总，未提交。
- final16-motion-runtime-20260921: final16 固定平移段用户实测无明显卡顿。diagnostic summary：duration-limit、877 tick、drawable 877/877、Metal completed 877/877、sequence gaps=0；tick p50/p95/max=16.670/23.956/220.958 ms，CPU wait=6.174/9.700/77.466 ms，GPU=5.405/9.080/16.876 ms。单次较长 tick/CPU wait 未见 sequence gap 或可见问题；连续 buffer reuse=437 缺 source PTS 不能推为掉帧。维持现有 GL/Metal 正确性同步，停止无证据的性能改动；仍待 HDR 亮度和长播/seek/退出重入验收，未提交。
- 接手入口:
  - 代码：`media_kit_video/lib/src/video_controller/`
  - 测试：`media_kit_video/test/`

## Session Log

- S1: 完成当前工作树检查、契约测试修正、静态检查和精确暂存。

## Findings

- F1: `git diff --check` 通过；Dart format 检查未产生格式改动。
- F2: 3 个契约测试通过；Dart 依赖解析仅有本地 `package:lints` 缺失提示。
- F3: macOS Metal blit 现在等待命令完成，并通过 output epoch 与首帧呈现状态决定 native output active。
- F4: 协作引导文件、空归档占位文件和 OHOS 本地 native 构建产物不属于代码提交，已加入仓库忽略规则。

## Decisions

- D1: 不使用 `--no-verify` 绕过提交钩子，补充最小任务与归档上下文。
  - 依据: 仓库钩子要求实质变更关联 TASKS 和 conversation archive。
  - 备选方案: 跳过钩子；影响是失去仓库约束检查。
  - 影响: 本归档与 TASKS 一并纳入本次提交。
- D2: 本轮只提交 macOS native output 相关的 7 个代码文件与 `.gitignore`，保留协作文档和 OHOS 本地产物。
  - 依据: 剩余 tracked 修改均集中于首帧呈现、输出 epoch 和控制器生命周期。
  - 备选方案: 纳入未跟踪二进制；影响是把本地构建产物混入代码提交。
  - 影响: 工作树仍保留未跟踪引导文件与 OHOS 二进制。
- D3: 将当前不需入库的本地引导文件、空归档占位文件和 OHOS native 构建目录加入 `.gitignore`。
  - 依据: 用户要求不需要提交的内容加入忽略规则，其余内容一并提交。
  - 备选方案: 提交这些本地文件；影响是把机器/工作树特定内容纳入项目历史。
  - 影响: 后续状态检查不再显示这些本地文件。

## Action Items

- [ ] A1: 在真实 macOS/OHOS 设备上完成 native output 生命周期验收。

## 2026-10-07 HCPP 直通轮：模拟器播放通道打通（sw 桥 + DISPLAY 合成，出画达成）

用户指令"继续打通OHOS模拟器播放通道"。接手 b2f9a89c 工作区（split-API + RTLD_DEFAULT 就位待验证），8 轮构建迭代后**模拟器实机出画**：视频清晰渲染、颜色正常、双截图动态帧推进、Back 退出→重入→复播闭环。

### 三层根因逐一定案（每层有实机证据）

1. **日志不可见（r23 遗留）**：原文件日志方案 `sw_log.txt` 本次实测已落盘（此前失败=装机 .so 陈旧）；但仍换装 **FFI 环形缓冲**（`mk_sw_log_take`/`mk_sw_log_buffer`，12KB tail + errno 记录），Dart 2s 轮询读回经 debugPrint 进 hilog——原生渲染线程状态全量可观测（`SwNative:` 前缀）。
2. **双副本假设证伪 + 绑定固化**：dart/dlopen 符号同址、dladdr 同路径 `/data/storage/el1/bundle/libs/arm64/libmpv.so`、`bind verdict: same copy`——"render() not being called"的另解：**vo 消费帧但渲染缓冲恒 3×3**。新增 `mk_sw_start_ex`（Dart 经 media_kit 同一 DynamicLibrary 解析三符号传入），绑定不再依赖桥自身 dlopen。
3. **真根因两层**：
   - **渲染 3×3**：引擎 TLHC 消费侧从不清 resize XComponent surface（`GET_BUFFER_GEOMETRY` 恒 3×3 → RequestBuffer 返回 36 字节缓冲）。external_window.h 明确要求生产者 RequestBuffer 前 SET_BUFFER_GEOMETRY——桥从未设。修复：`mk_sw_set_surface(id,w,h)` + `mk_sw_set_geometry(w,h)`（videoParams 到达时纠正，854×480）→ buffer 1639680 字节、pixel_sum 数百万级持续变化（**内容产出正常**）。
   - **显示恒黑（终审定案）**：节点同样 3×3（uitest dumpLayout 实证 [0,308][3,311]），Dart 传绝对物理像素（`ohosSurfaceWidthPx/HeightPx`，candidate 门在创建时固化、viewportWidth/Height 有无界 fallback）→ ets XComponent 绝对尺寸 → 节点 1260×709。**但画面仍黑**：hilog 抓到 `render_service bind external with nullptr gbuffer`——TLHC 的 XComponent BufferQueue 消费者是引擎外部纹理链，模拟器 DGLES 在 bind external 环节断（与 2026-10-06 "纹理显示链路不工作"终审同源）。**HCPP 直通**（`initHybridAndroidView` + 测试 app buildinfo.json5 `enable_ohos_hybrid_composition=true`，sw 模式 `notifier.swRender` 驱动）让系统合成器直接呈现 XComponent surface——**出画**。既往"Impeller 门禁锁死 HCPP"定性撤销：真实原因仅是 buildinfo 未配开关。

### 改动清单（本轮工作区）

- `libs/ohos/.../cpp/sw_render.cpp`：FFI 日志环 + errno 取证；`mk_sw_start_ex` 符号注入；`Forensics` 绑定取证（三路 dlsym 对比 + dladdr 路径 + verdict）；`mk_sw_set_surface(id,w,h)`/`mk_sw_set_geometry` 生产者几何；几何变化日志。
- `media_kit_video/.../sw_render.dart`：`_resolveMpvSymbols`（按 NativeLibrary 顺序 libmpv.so→.so.2）；`start_ex` 带 legacy 回退；`setSurface(w,h)`/`setGeometry`/`takeLogs`。
- `media_kit_video/.../ohos_video_controller/real.dart`：attach 传尺寸（rect×DPR，<8px 时用 lastRequested 兜底，全无效传 0）；videoParams 监听 `nativeSurfaceActive` 时 `SwRender.setGeometry`。
- `media_kit_video/lib/src/video/platform_view_video.dart`：`ohosSurfaceWidthPx/HeightPx`（进 creationParams）+ `ohosHcpp`（OHOS 走 `initHybridAndroidView`）；SwTrace 打印参数值。
- `media_kit_video/lib/src/video/video_texture.dart`：OHOS 分支传物理像素（`nativeOhosCandidate` 门——creationParams 在 create 时固化，active 门太晚；viewportWidth/Height 已含无界 fallback）+ `ohosHcpp: notifier.swRender`。
- `media_kit_video/ohos/.../OhosNativeSurface.ets`：XComponent 宽高绝对 px（>0 时）else '100%'。
- `media_kit_test`：测试页日志轮询换 `takeLogs()`；**buildinfo.json5 加 `enable_ohos_hybrid_composition=true`**（测试 app 本地，产品不经此路径）。

### 验证状态（模拟器 127.0.0.1:5555，release HAP）

- 出画 ✓（mk11/mk12：画面清晰颜色正常、双截图 MD5 不同动态推进）；帧推进 ✓（297+ 帧渲染提交、pixel_sum 2588 万级）；退出重入 ✓（Back→重开→复播正常，mk13）。
- analyze 全绿；media_kit_video 测试套回归见 TASKS 登记值；真机回归风险：OHOS TLHC 节点尺寸从 '100%' 变绝对像素（video_texture 传参改动全 OHOS 生效），无设备 blocked 不变，真机验收时必测。
- 遗留：SW 桥 25ms 轮询渲染的效率与 vsync 对齐、HCPP 路径的手势/覆盖层/全屏组合、`vo='sw'` 显式路径文档化。

## 2026-10-07 双目标轮：XComponent 挂载链全线打通，黑帧收窄为 render context 时序（b2f9a89c，本 HCPP 直通轮的前一轮）

用户指令"①尽可能实现 EGL 正常播放；②Luna E1 方案正常播放"。**挂载链月度堵点已全线打通**（viewType 修复→XComponent 创建→nativeSurfaceReady 首次到达→attach→提交→mpv 解码链可达），黑帧最终收窄为一个明确定位的 mpv render-context 生命周期问题。

### 三个连环根因与修复（本轮）

1. **S2 viewType 丢失（主根因）**：main 的 `platform_view_video.dart` 整改重写时丢了 OHOS 分支，OHOS 落入 Android viewType `media_kit_video_platform_view` → 引擎对未注册类型 throw（PlatformViewsController.ets:806-808）→ XComponent 从未创建（9 月 e4 至今全部黑屏的共同根因，真机同样存在）。修复：viewType 三元恢复 `ohos → com.alexmercerind/media_kit_video/ohos_native_surface`（9 月版一行式）。
2. **合成模式错误**：OHOS 落入 `initExpensiveAndroidView`（hybrid 入口）→ 引擎 `createForPlatformViewLayer: HCPP unavailable → created but not composed`（模拟器 Impeller 门禁锁死 HCPP）→ 视图不可见。修复：OHOS 分支改走 `initSurfaceAndroidView`（TLHC 纹理层，fork channel 协议等价、跨 SDK 可编译；`initSurfaceOhosView` 动态派发方案因 Dart 静态方法不能 dynamic 调用而不可行——`Class 'Type'` 实证）。用户问"为何借 Android 名"：编译约束+协议等价，正式形态=接线死代码 `platform_view_video_ohos.dart`（需 fork 上游条件导入机制，登记后续）。
3. **S1 `_visible` 门**：OHOS candidate 允许 pre-visible 挂载（`mountOhosNativeSurfaceCandidate`），镜像 Android 先例。

### 软件桥（Luna E1 方案）当前状态：生产链全通、内容黑

- sw_render.cpp 重写为 **NativeWindow 生产者路径**（RequestBuffer→MapPlanes→memcpy(rowStride 对齐)→FlushBuffer；弃自有 EGL——会饿死引擎消费者，实证"bind external with nullptr gbuffer" 1610 次）。`frames==submitted` 1600+/分钟（FFI 计数实证），pixel_sum 探针 + mk_sw_submitted/mk_sw_pixel_sum 导出。
- **mpv 侧修复**：早设 vo=libmpv 曾致 `vo/libmpv fatal: No render context set → Video: no video`（mpv 原话日志）——已改 attach 时"先建 ctx 再切 vo"，video-format=h264/width=854 恢复。
- **残余**：pixelSum 恒 0 + `vo/libmpv: mpv_render_context_render() not being called or stuck`（伴随 XComponent destroy/ready 循环引发的多次文件重开）。定性：render context 与 VO 在多次重建循环中未稳定绑定（E2 是 ctx 先于 open 的全新实例；media_kit 运行时 attach 顺序无法完全复刻）。rgb0 格式与 vid 循环两个变量已排除。

### 精确下一步（接手即做）

0. **恢复原生可见性（第一优先）**：r23 的文件日志方案（native 写 /data/storage/el2/base/files/sw_log.txt + Dart 轮询读回打印）Dart 侧未读到行——先查路径权限/写失败原因（Dart File 读自身 files 目录本应可行；native fopen 该路径在模拟器可能被 namespace 拦）；可见性恢复后即能量化 r22 的 RTLD_DEFAULT 绑定是否命中/是否 SECOND copy。
1. **render-context 黑帧主嫌**：linker namespace 双 libmpv 副本（我们的 .so dlopen 得到新副本，ctx 不在 player 的视频链上——mpv "render() not being called" 而我们每秒调 30+ 次的唯一自洽解释）。r22 已落 RTLD_DEFAULT 优先绑定 + dladdr 取证 + "SECOND copy" 检测代码，**待日志验证**。备选：mk_sw_start 改由 Dart 传入已解析符号地址（Dart FFI probes 拿到 mpv_render_context_create 地址传给 native，彻底绕开 dlopen namespace）。
2. 若非双副本：稳定单次 attach 序列（nativeSurfaceDestroyed 重开循环已实证多次 Playing 重开）；split-API（mk_sw_start 无窗启动 ctx + mk_sw_set_surface 换窗）已落地（r20-r21 实证 vo=libmpv/video-format 恢复正常时序）。
3. Goal 1（GL vo）未动：显式 vo 覆盖轮（⑥ 原计划）+ 补丁件 zip 在 libmpv-ohos-build 树。
4. rgb0/rgba 与 vid-cycle 两变量已排除（r18/r19 实证无效）。

### 现场与运维

- hvigor 插件 Node bug 已本地修复（DevEco hvigor-ohos-plugin `fs_extra rmdirSync→rmSync`，.bak 备份）——release 构建稳定；debug 变体还需签名配置（00304004 提示）。
- 增量构建陷阱实证：`flutter build hap` 对 path 依赖改动可能不重编（SwTrace 字符串核对法），清 `.dart_tool/flutter_build`+`build/ohos` 后恢复。
- 模拟器当日两次死亡（磁盘门槛/幽灵锁），恢复流程已固化（清空间>12G→-stop→-start→tconn）。
- 测试 app 诊断插桩（帧数/mpv 属性轮询/日志监听/SwTrace）在工作区，收口时按注释清理。

## 2026-10-06 Luna E1 方案打通轮（SW 桥落地，XComponent 挂载链未通）

用户指令"Luna E1 可以播放视频，使用这个方案进行打通"。实施 E1/E2 技术进 media_kit：**软件渲染桥已落地并 attach 成功，但 XComponent ready 事件未到达，画面未通**——工作区保存，未收口。

### 已落地的代码（本轮工作区状态）

1. **`libs/ohos/.../cpp/sw_render.cpp`（新，约 300 行）**：软件渲染桥。dlopen("libmpv.so") 绑定 render API（mpv_render_context_create/free/render），attach 到 Dart 传入的**活体 mpv handle**（非 E2 的自建实例），SW 渲染 RGBA → 自有 EGL/GLES blit（shader/texture/VBO 全套）→ eglSwapBuffers 到目标 surface；逐帧读窗口几何自适应尺寸。CMake 目标 `mediakit_ohos_sw`（EGL/GLESv3/native_window/hilog_ndk.z），随 HAP 打包已实证（HAP 内 59KB）。
2. **`media_kit_video/lib/src/video_controller/ohos_video_controller/sw_render.dart`（新）**：Dart FFI 封装（attach/detach/frames），带全路径回退（应用 libs 目录不在裸名搜索路径时）。
3. **`OhosVideoController` 接线**：模拟器自动检测（`Utils.IsEmulator` channel，异常回退 false）或 `vo='sw'` 显式 → sw 模式：`vo=libmpv` + `hwdec=no` + darwin.useNativeSurface=true（XComponent 面）。`_attachNativeSurfaceLocked` 增 sw 分支（detach→attach、不设 wid）。`_disposeOnce` 挂 detach。`PlatformVideoController.swRender` 字段。
4. libmpv-ohos-build 两项修复（前节）已提交。

### 验证状态

- **桥 attach 成功**（release 构建、模拟器实测 `start code=0`，surface id 与 mpv handle 均实值）。
- **画面未通**：XComponent 面与纹理面均黑。终审探针（vo=null + 红背景）与 SW 桥一致黑 → 指向 Flutter-OHOS 纹理/合成显示链路（模拟器限制），但 **XComponent 直通合成未获验证机会**——本轮最后卡点：`nativeSurfaceReady` 事件未到达（`useNativeSurface=true` 后 XComponent 未挂载或挂载未回报），挂载链门槛未查明。
- 原生侧 hilog（OH_LOG_Print LOG_APP）在 Flutter 宿主进程内**不落盘**（E2 独立应用同 API 可见）——渲染线程状态不可观测，是定位的主要障碍。
- debug HAP（可获 VM service 与 composition trace）构建被 hvigor debug 变体环境失败阻断（release 正常；直接 ninja 手动编译可过，hvigor 调用自身报 00308018——环境问题待查）。

### 精确下一步（接手即做）

1. 查 XComponent 挂载链：video_texture.dart 的 ohosNativeSurfaceCandidate 分支要求 `id/rect/visible` 与 candidate 齐备——插桩 `_traceOhosComposition`（kDebugMode 门）需 debug HAP；或先读 native_surface_viewport.dart 的挂载条件静态排查。
2. 解 hvigor debug 变体失败（00308018；release 同树正常）→ debug HAP → VM service 驱动 + composition trace。
3. 原生日标通道：OH_LOG 不落盘时，改写状态到应用 files 目录文件（Dart 轮询）或走 mpv log 前缀转发。
4. 若 XComponent ready 到达且 attach 成功仍黑：SW blit 的 EGL 在模拟器 guest-DGLES 上向 XComponent 窗口 swap 的行为需单独取证（E2 证明可行的是独立应用窗口；Flutter PlatformView 的 XComponent 合成路径未证）。
5. 真机优先级不变：真机 vo=gpu-next 正常路径未受本轮任何影响（sw 模式仅模拟器/显式触发）。

### 现场状态

- media_kit 工作区：sw 桥全套代码（未提交，工作区保存）；luna_flutter_e3 有 dumb-mode 实验残留（scratch 项目不提交）；模拟器在跑（media_kit_test 已装 sw 桥版）；宿主镜像服务 8000 在跑。
- libmpv-ohos-build：前节两项修复已提交；产物 71242b19 完整可用。

## 2026-10-06 选项 B 实施轮：构建修复达成、黑屏判决实验定案（显示链路）

用户指令"开工"。按"探针取证 → RGBA config 补丁 → 重建 → 验证"执行，结果**选项 B 的补丁机制工作但未能解决模拟器黑屏——终审探针证明黑屏根因是 Flutter-OHOS 纹理显示链路在模拟器上不工作**。

### 完成的实质修复（已入库 libmpv-ohos-build）

1. **macOS 构建修复（真 bug）**：ffmpeg.sh configure 补传 `--ar/--ranlib/--nm`（llvm 工具链）。此前 macOS 宿主 BSD ar+ranlib 把 ELF 目标归档写成 **96 字节空档案**（ffmpeg 六个 .a 全空），libmpv.so 留 149 个未定义 av_* 符号 → HAP 内 dlopen 重定位失败 → 应用白屏。该 bug 使 ffmpeg.sh 在 macOS 上从未产出过可用库（既往发布件应产自 Linux）。
2. **ohos-egl-rgba8-config-match.patch**：refine_config 回调读窗口 GET_FORMAT，=RGBA_8888 时优先选 8-bit RGBA config（auto），并打全量候选 config 取证日志；真机高深度选择路径不变。
3. 完整构建达成：libmpv.so 37.1MB（对齐发布件 35.5MB 量级）、av_* 零未定义、av_frame_alloc 自含导出、native_media ×4 ohcodec 链接恢复、补丁串在包内。

### 排查过程实证（模拟器，全部有日志/截图证据）

- 首个新构建（半成品 16.9MB）装机即白屏：hilog 抓到 `relocating failed: s=av_frame_alloc` + `libmpv.so.2 load failed`——空档案问题 first hand。
- 完整构建 + 补丁后（S/W）：日志证实 **渲染管线全链活跃**——`reconfig to 854x480 yuv420p`、窗口 `readback format=12`（RGBA8888，假设证实）、`Window size` 1x1→854x480 演进、libplacebo 建 r8 纹理+编译 `#version 300 es` shader、`first video frame after restart shown`——**但可见画面仍黑**。
- H/W：vo SIGSEGV 跨 libmpv 世代复现（vo 线程，同签名）——模拟器无硬解，官方文档吻合。
- **终审判决实验**：Dart `vo=null`（mpv 零渲染）+ ArkTS `setTextureBackGroundPixelMap` 纯红背景（854x480 RGBA）→ **仍纯黑**。纹理显示链路本身不通，与 mpv 无关；亦是选项 A（SW 纹理）在模拟器同样不可见的证明。

### 结论修订（对上节"修复设计"的修订）

- 上节"黑屏=libplacebo/GL 产出黑帧"的机制推断**被终审推翻**：mpv 侧渲染正常（帧 shown），断点在 Flutter-OHOS 引擎的纹理/合成层（模拟器限制，官方文档"视频显示受限"吻合）。
- 选项 A/B 均无法让模拟器显示画面；**模拟器可用面收敛为**：UI/状态机/demux/网络/FFmpeg 软解（音频+解码推进）/RPU 纯算法——可视画面验证只能真机（官方口径一致）。
- 选项 B 补丁保留价值：真机无回归风险 + 窗口格式自动匹配机制 upstream 质量；已在 libmpv-ohos-build 提交。media-kit 主仓 zip/CMakeLists 维持发布件 29b8bd4d 不变（黑屏根因不在 libmpv，本地构建不入产品链）。

### 现场与遗留

- libmpv-ohos-build：构建修复+补丁已提交（scripts/ffmpeg.sh、patches/mpv/ohos-egl-rgba8-config-match.patch）；完整产物 libmpv/arm64-build/{libmpv.so,libmpv_aarch64.zip}（zip SHA 71242b19…）在树，未经产品链审核不入主仓。
- 已知 build 链 bug（未修，登记）：bundle.sh 内嵌 patch.sh 在"已应用+已构建"树上幂等失败（color-contract 补丁 reverse-check 不过）；本轮以手动跳过绕过。
- media_kit_test 诊断代码全撤（VideoOutput 探针、test01 日志监听/vo=null 均还原）；模拟器在跑、样片缓存于应用内；宿主镜像服务 8000 仍在。
- 主仓无本论代码改动（探针全撤、zip 还原发布态）；本节即本轮入库记录。

## 2026-10-06 OHOS 模拟器黑帧根因定案与修复设计（接上节）

用户指令"以前解出来过图像，解决一下这个问题"。系统排查后**根因定案**：

### 排除矩阵（全部今日实机复现）

| 路径 | 今日结果 | 证据 |
| --- | --- | --- |
| E1/E2 原生探针（ArkTS XComponent + 自写 EGL + mpv render API **SW**） | **正常渲染**（SMPTE 彩条+动态元素+OSD） | /tmp/mk-e1.jpeg |
| e3 纹理路径（vo=gpu-next/gpu, hwdec=no, 新旧 libmpv 两世代） | 恒黑、播放推进、vo 零报错 | 多轮 snapshot_display |
| e4 原生面路径（useNativeSurface, 9月6日构建产物） | 恒黑 | /tmp/mk-e4.jpeg |
| 当前 main app（H/W） | vo 线程 SIGSEGV（两 libmpv 世代同崩） | faultlog ×2 |
| 当前 main app（S/W）+ 旧 libmpv（2f9d1f59）对换实验 | 恒黑（libmpv 世代排除） | /tmp/mk-old4.jpeg |
| gpu-dumb-mode=yes + vo=gpu（哑管线） | 恒黑（shader 复杂度假设排除） | /tmp/mk-dumb.jpeg |

### 结论

mpv 的 GL vo（gpu/gpu-next，含哑模式）在模拟器的 DGLES（软件模拟 GL）栈上渲染产出黑帧（无报错、swap"成功"），与 EGL 初始化方式无关（E2 用同样的 `EGL_DEFAULT_DISPLAY`+window surface+ES3 就正常——因为 E2 内容来自 **`MPV_RENDER_API_TYPE_SW` 纯软件渲染**，只做简单 blit）。libmpv 的 OHOS vo 无纯软件 vo 可用。当年"解出图像"= E1/E2 探针路径；Flutter 内的 vo 路径（e3 纹理、e4 原生面）在模拟器上从未出过帧。

### 修复设计（后续任务，接手即做）

**OHOS 软件纹理路径**（把 E2 技术并进 media_kit_video）：
1. 新增 native 模块 `media_kit_video/ohos/src/main/cpp/sw_render.cpp`（参照 `~/src/luna-ohos-e1/entry/src/main/cpp/luna_e2_native.cpp`）：持 mpv handle + surfaceId，`mpv_render_context_create(API_TYPE_SW)`，update 回调驱动 render→RGBA→GL blit→eglSwapBuffers 到既有纹理 surface（该 surfaceId 已经 Dart `VideoOutputManager.Create` 流转到 native，零 ArkTS 改动即可复用；CPU 直写 `OH_NativeWindow_RequestBuffer/FlushBuffer` 为备选）。
2. Dart：`OhosVideoController` 增软件模式分支（如 `configuration.vo=='sw'` 或模拟器检测自动）→ `vo=libmpv`+`hwdec=no`+调 native setup 传 wid。
3. 验收：模拟器可见画面 + 帧推进 + dispose 干净；真机回归不受影响（默认路径不变）。
预估：C ~250 行 + 桥接 + Dart ~60 行 + 3-4 轮模拟器验证。

### 本轮状态

- 仓库已还原到提交态（01b15a01：新 libmpv 钉定 29b8bd4d）；CMake 临时旧 zip 实验已撤。
- 模拟器现装：luna_flutter_e3（哑模式实验版，scratch 项目 ~/src/luna_flutter_e3 未提交改动）；宿主 HTTP 镜像服务仍在 8000 端口。
- e3 项目 main.dart 的 dumb-mode 实验改动留在 scratch 项目内（不影响主仓）。
- **SDK 位置更新（2026-10-06 后续）**：本地 OHOS Flutter SDK 定编为 `~/src/flutter-ohos`（原 flutter-ohos-e3 迁移；旧路径已不存在）。引擎 90 文件脏改动已由迁移方转为正式提交（HEAD `2ece1aae`，HCPP 契约文档+测试入库），版本缓存为规范化 `3.44.9+ohos-2`（不再需要本会话的 version 文件临时补丁），tag 3.44.9+ohos 与引擎缓存随迁完好。后续黑帧修复轮的构建命令一律用新路径；experiments 库 `ohos-flutter-e3-archive-20261006.md` 的恢复配方作为历史兜底仍有效。

## 2026-10-06 OHOS 模拟器轮（guard 移除验收）

用户决策移除 `OhosVideoController.create` 的 `Utils.IsEmulator` guard 并跑模拟器测试。环境：Mate 60 Pro+ 窗口模拟器（ARM64，API 26；磁盘清至 13G 过 12G 门槛）、hdc 127.0.0.1:5555、本地 flutter-ohos（补 tag 3.44.9+ohos + version 文件 + 清 flutter.version.json 缓存解决 0.0.0-unknown）、hvigorw/ohpm 入 PATH。

- **发现并修复 OHOS Flutter 首跑阻塞**：`GeneratedPluginRegistrant` 从未注册 path_provider（OHOS 无联邦默认实现）→ `getApplicationSupportDirectory()` MethodChannel 永久挂起 → app 恒停下载页（pubspec.ohos.lock 从 pub.dev 解析、无 ohos 变体；CI 只构建不运行故从未暴露）。修复：pubspec 显式依赖 `path_provider_ohos 2.2.1`（pub.dev）+ 锁更新（SDK 四件套未漂移）。
- **样片通路**：模拟器 NAT 无宿主代理到 GitHub 不通；新增 `MEDIA_KIT_TEST_SAMPLE_BASE` dart-define 样片基址覆盖（默认仍上游 URL），指向宿主 HTTP 服务（QEMU 网关 10.0.2.2:8000）后 5 样片全部 200 拉取成功。曾试 rawfile 打包提取（ArkTS/Dart 两版）未通、define 无 DNS 直连 IP 后即通——既往通路假设更正：先前"镜像 GET"实为本机自测 curl。
- **guard 移除验收（API 层通过）**：列表→single_player_single_video 页，VideoController 正常创建（无 `does not support emulator` UnsupportedError），`[OhosVideoController] videoParams surface request: 854x480` surface 生成、纹理路径 `updateTextureBuffer=true` 运行。
- **底层管线在模拟器两模式均不可用（guard 原始动机证实）**：H/W（hwdec auto）→ mpv **vo 线程 SIGSEGV**（libmpv.so 内 NULL 解引用，faultlog `cppcrash-...-20261006014024696.log` 已取回本机）；S/W → 无崩溃、解码管线活着但**视频区恒黑不出帧**（~60s 无渲染）。退出路径（BACK）dispose 干净、进程存活零新崩溃。
- 附带修正：仓库内 `libs/ohos/.../libmpv_aarch64.zip` 为过期副本（2f9d1f59），构建按 CMake 钉定（20260920 release，SHA 29b8bd4d）自动重下替换——本轮随提交刷新为钉定版。测试 libmpv 即钉定 20260920 世代，崩溃结论对该世代成立。
- **结论**：guard 移除本身达成（Dart 层不再拒绝模拟器、控制器生命周期可跑通退出）；模拟器上的可視播放仍不可行（vo 崩溃/黑帧），OHOS 播放验收仍以真机为准（既有 blocked 项不变）。e1/e2 探针证明的"libmpv 软解+自管 EGL"路线与 Flutter vo 管线不同层，差距定位在 libmpv OHOS vo/纹理路径对模拟器的适配。
- 设备端截图判定用 `snapshot_display`（模拟器自带 -instance screenshot 输出损坏）；UI 注入用 `uinput -T -m x y x y 200`（H/W 切换、列表点击、BACK=`uinput -K -d 2 -u 2` 均可用）。

## Archive Metadata
- date: 2026-09-20
- entry: native-output-rebuild
- agent: Codex
- project: media-kit
- submodule:
- language: zh-CN
- tags: [archive, native-output, hdr, ohos, macos]

## 2026-10-03 产品链纠正

旧交接默认 Debug modern 身份不成立（实为 mpv 0.36）。已加入 Xcode 全配置及 CI 最终包门禁，稳定源码构建、89 项测试与独立审核通过。产品五场景仍开放；本轮入口 `archives/experiments/macos-ppx-completion-20261003.md`。
