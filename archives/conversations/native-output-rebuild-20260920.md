# native output rebuild lifecycle

## Current State
- 背景: 当前分支包含 macOS native surface、OHOS HDR surface 和播放器释放路径的协同修改。
- 目标: 提交本轮代码及对应契约测试，保留未纳入范围的协作文档和本地产物。
- 当前状态: 跨平台生命周期修复与 macOS 首帧呈现 gating 已分别提交。
- 2026-09-27 进展: Darwin Player 新增 preTermination 屏障及创建/销毁仲裁；隔离 Goodwu mpv 0.41 的 W0 测试包完成 SDR 首次出图、旧 Surface 释放、重建出图和 Player dispose，无 render-context abort。应用 Quit 未提供第二个 Surface 释放 ACK；真实 PiliPlusX 的有序退出、快速重入、seek 与 HDR 长播仍待验收。证据见 `archives/experiments/macos-w0-modern-20260927.md`。
- 2026-09-27 PiliPlusX 尝试: 本地 path override 已指向当前 media-kit，macOS Debug 构建通过；隔离包加载 final16 Goodwu mpv 0.41 后进程启动并运行 Dart/网络初始化，但未创建可操作窗口，无法进入播放。测试用 PiliPlusX 版本引用已恢复，临时包已清理。见 `archives/experiments/piliplusx-macos-3a4fcaa-launch-20260927.md`。
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

## Archive Metadata
- date: 2026-09-20
- entry: native-output-rebuild
- agent: Codex
- project: media-kit
- submodule:
- language: zh-CN
- tags: [archive, native-output, hdr, ohos, macos]
