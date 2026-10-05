# native output rebuild lifecycle

## Current State

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
