# 归档导航

先读仓库根目录的 [`TASKS.md`](../TASKS.md) 接手快照与任务状态；本页只负责定位归档。当前没有批量迁移旧文件，原链接仍有效。

| 主题 | 当前上下文 | 关键入口 |
| --- | --- | --- |
| 仓库分支归一、发布链与 mpv 上游策略 | [`android-mpv-fork-branch-consolidation-20260930.md`](experiments/android-mpv-fork-branch-consolidation-20260930.md)（含 media-kit 分支清理追加节） | [main 合并冲突评估](experiments/android-media-kit-main-merge-assessment-20260930.md)、[合并后 P5 五项验收 12700–12702](experiments/android-media-kit-main-merge-acceptance-12700-20260930.md) |
| Android HDR10、P8.4、P5、首帧与生命周期 | [`android-hdr-dv-display-plan-20260922.md`](conversations/android-hdr-dv-display-plan-20260922.md) 顶部 `Current State` | [P5临时工作树交接](experiments/android-private-tmp-handoff-20260928.md)、[P5片尾12617–12627](experiments/android-p5-glass-tail-12617-12627-20260928.md)、[c025cbf回归12627–12640](experiments/android-p5-tail-c025cbf-regression-12627-12640-20260929.md)、[P5切源尺寸](experiments/android-p5-source-switch-aspect-20260928.md)、[Engine销毁12646–12657](experiments/android-p5-engine-destroy-12646-20260929.md)、[失败重试与双播放器12658–12661](experiments/android-p5-failure-retry-dual-player-12658-12659-20260930.md)、[P4数值色准与颜色回归发现](experiments/android-p5-numeric-color-20260930.md) |
| Android 首播历史、回退及审查 | [`android-first-playback-replay-20260922.md`](conversations/android-first-playback-replay-20260922.md)、[`android-first-playback-controller-replay-20260922.md`](conversations/android-first-playback-controller-replay-20260922.md)、[`android-hdr-first-playback-revert-20260922.md`](conversations/android-hdr-first-playback-revert-20260922.md)、[`android-hdr-release-vs-debug-review-20260922.md`](conversations/android-hdr-release-vs-debug-review-20260922.md) | [首播原始脏状态快照](conversations/android-first-playback-initial-dirty-snapshot-20260922.md) |
| macOS native output | [`native-output-rebuild-20260920.md`](conversations/native-output-rebuild-20260920.md) | [W0移除实验](experiments/macos-w0-remove-20260927.md) |
| OHOS libmpv | [`ohos-libmpv-release-20260920.md`](conversations/ohos-libmpv-release-20260920.md) | 对应任务见 `TASKS.md` |

`experiments/` 当前还有221篇顶层Markdown，尚未完成主题迁移或去重；其内容不能仅按文件名前缀判断为已验收。整理计划和验收门槛在 `TASKS.md` 的“整理 archives 的主题结构与引用”任务中。不要在迁移前删除原文件。
