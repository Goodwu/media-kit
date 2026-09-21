# TASKS.md

## Now（当前推进，最多 3 条）
- [ ] 修复 macOS modern mpv 销毁时未释放 render context 的崩溃
  - status: in_progress
  - context: archives/conversations/native-output-rebuild-20260920.md
  - acceptance: `NativeVideoController` 的所有并发 dispose 共享同一完成屏障；在 Player 销毁前完成 native output / render context 释放，且 active notifier 不会在 dispose 后被写入。使用 modern mpv 候选完成实际播放后退出、快速重入与输出重建复验，无 `mpv_render_context_free() not called` abort。
  - latest: 已实现共享 `_disposeFuture`、callback quiesce、detach/native-output/`VideoOutputManager.Dispose` 的持续清理与首错传播，且 notifier 仅在该 barrier 后销毁；新增 disposal contract script、既有 3 个契约脚本、目标 analyze 和 diff-check 通过。等待独立 V1 审查及 PiliPlusX final12 实际运行验收，未提交。
  - latest: V1 独立审查 PASS；若任一释放步骤失败，控制器不再销毁 notifier，而是清空 completed error future 允许上层重试 render-context barrier。PiliPlusX final12 已用 modern mpv 0.41.0 构建；四份契约脚本、目标 analyze（仅两条既有 info）和 diff-check 复验通过。等待真实 macOS runtime，未提交。
  - latest: 另已修复 macOS 起播闪烁/低帧率：candidate 和 active 分支曾对同一 handle/generation 重复挂载 `PlatformViewVideo`，导致零尺寸 AppKitView 覆盖 native owner 并重置 presented state。macOS 现只保留 candidate 的稳定唯一挂载，Texture 仅在 inactive 覆盖，Android/OHOS 原语义不变。V1 审查 PASS；新增 macOS contract、既有 OHOS candidate/P1/platform-entry 脚本及目标 analyze（3 条既有 info）和 diff-check 通过；final13 已构建，等待真实 runtime，未提交。
  - latest: final13 已确认无闪烁但出现中央小画面；修复为 macOS 唯一 candidate view 直接填满 outer fitted video box，仍不恢复 active 的第二挂载；OHOS/Android 继续原 Center sizing。V1 审查 PASS；四份契约脚本、目标 analyze（3 条既有 info）和 diff-check 通过，PiliPlusX final14 已构建，等待真实 runtime，未提交。
  - latest: final14 用户确认前序视觉问题已好，但平移镜头仍感觉卡顿。没有 source PTS 或运行耗时证据，故未删除 GL/Metal 同步；仅新增 macOS opt-in 帧节奏汇总，环境变量 `PILIPLUSX_FRAME_PACING_DIAGNOSTICS=1` 下从首个实际视频 buffer 开始最多采样 15 秒（900 tick 上界），报告 timer tick、drawable、buffer reuse、Metal sequence gap、既有 CPU wait 与 GPU duration。默认不启用，未加 readback/额外 command/completion handler/semaphore，也未改变 `glFinish`、`waitUntilCompleted()`、present 或 teardown。V1 PASS；新 contract、macOS Debug build、PiliPlusX 48 项定向测试、codesign 和两仓 diff-check 通过；final16 已构建，等待固定平移段真实汇总，未提交。
  - latest: final16 真实平移播放用户报告无明显卡顿；同进程 15 秒 summary 为 877 tick、drawable 877/877、Metal completed 877/877、sequence gaps=0，tick p50/p95/max=16.670/23.956/220.958 ms，CPU wait=6.174/9.700/77.466 ms，GPU=5.405/9.080/16.876 ms。单次 tick/CPU wait 尖峰不伴随 sequence gap，也未见可见问题；buffer reuse 未结合 source PTS 不判作掉帧。因此保留 GL/Metal 同步，不实施 speculative lease/fence 优化；HDR 亮度和长播/seek/退出重入验收仍待完成，未提交。
- [x] 切换 OHOS libmpv 二进制发布来源至 Goodwu 20260920
  - status: done
  - context: archives/conversations/ohos-libmpv-release-20260920.md
  - acceptance: CMake 下载地址与 SHA-256 均匹配指定 GitHub release；归档记录可复核的 release/资产校验；静态配置检查通过
- [x] 修复跨平台 native video output 重建与释放生命周期
  - status: done
  - context: archives/conversations/native-output-rebuild-20260920.md
  - acceptance: 代码、契约测试和 staged diff 检查通过；完成一次 Git 提交
- [x] 修复 macOS native output 首帧呈现与输出 epoch gating
  - status: done
  - context: archives/conversations/native-output-rebuild-20260920.md
  - acceptance: 代码变更通过 diff 检查并完成 Git 提交

## Next（近期候选，最多 10 条）
- [ ] 在真实 macOS/OHOS 设备上继续验证 native output 生命周期
  - status: todo
  - context: archives/conversations/native-output-rebuild-20260920.md

## Blocked（等待输入或外部条件）
- （暂无）

## Recently Done（最近完成，最多 5-10 条）
- （暂无）

## 规则
- 新任务必须写入本文件
- 完成任务必须打勾
- 建议任务状态：todo / in_progress / blocked / done
- 活跃任务建议填写 `context: archives/conversations/<topic>.md`
- 按需从本文件定位任务、读取有效 context，并在需要时检索 active memory
- 旧完成项超过上限时，压缩进对应 conversation 后从本文件移除
- 每次推进使用 Git 提交信息记录变更
