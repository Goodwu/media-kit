# `/private/tmp` 中 media-kit 工作的接手索引（2026-09-28）

## Current State

- **2026-09-29 清理更新**：本页下面的21树/14脏树为2026-09-28历史快照。已确认冗余并逐目录删除 `media-kit-p5-libplacebo`、`media-kit-p5-mpv`、`media-kit-p5-app`、`media-kit-p5-jar-rebuild-20260927`、`media-kit-ffmpeg-p5-stream-2215`、`media-kit-p5-jar-ffmpeg-20260927`；现存该快照中的15树，8树在快照时有未提交状态。六树源码补丁仍在本目录，原临时路径已不存在。以根目录`TASKS.md`的2026-09-29状态为准。

- 本目录的 `TASKS.md` 和 `archives/conversations/android-hdr-dv-display-plan-20260922.md` 是任务与结论入口。本索引补齐临时目录定位；接手时先核对当前 Git 状态，再看本页。
- 本次快照清点 `/private/tmp` 顶层名称为 `media-kit*` 的 **1566 个文件或目录**，其中 **21 个可读 Git 工作树、14 个有未提交状态**。完整顶层清单见 [产物清单](android-private-tmp-media-kit-artifacts-20260928.json)，工作树的 HEAD、分支、remote 与逐文件状态见 [工作树清单](android-private-tmp-worktrees-20260928.json)。这两份是时间点快照；它们不证明其他名称的临时目录或后来新增的文件均已收录。
- 13 个工作树的已跟踪修改已保存为 [补丁目录](android-private-tmp-patches-20260928/)。另单独保存 `media-kit-firstframe-mix-20260927` 的已修改文件补丁，以及 DoViBaker 两个未跟踪 C++ 源文件。**补丁是实验快照，不代表应直接合入。** FFmpeg `_build-*` 生成文件、DoViBaker 二进制和 firstframe-mix 中 868 个删除项只有索引、没有复制；完整回放仍依赖原临时目录和相应 Git HEAD。

## 已进入产品分支的主线

| 工作树 | 状态与去向 |
| --- | --- |
| `/private/tmp/media-kit-p5-pq-product` | `e0102cf`，干净；同一提交已在当前目录，P1/P2 产品代码已回归。 |
| `/private/tmp/media-kit-p5-mpv-product` | **已删除（2026-09-29）**：`c025cbf` 已核验在 Goodwu/mpv 远端 `feature/android-p5-sdr-direct-yuv`；12627/12632 实机回归全部完成（见 `android-p5-tail-c025cbf-regression-12627-12640-20260929.md`），JAR 留存 `/private/tmp/media-kit-p5-tail-clean-12627-arm64.jar`。其原挂接主仓库 `media-kit-p5-mpv` 删除后本树的 git 链接已断。 |
| `/private/tmp/media-kit-p5-ffmpeg-product` | `fff3ee7`，干净；P5 RPU 产品分支，既有记录称已推送 Goodwu/FFmpeg。 |
| `/private/tmp/media-kit-libplacebo-p5-gamut-fallback` | `c9fd879`，干净；默认线性解码优化已在产品链路使用，既有记录称已推送。 |

## 仍只在临时工作树中的改动

| 工作树 | 未提交内容；接手判断 |
| --- | --- |
| `media-kit-p5-app` | 5 个 app/policy/test 文件；旧 P5 app 实验，尚未逐项与 `e0102cf` 比对，不能视为已回归。 |
| `media-kit-p5-libplacebo` | `src/renderer.c`；旧 renderer 实验，尚未确认是否优于已提交 `c9fd879`。 |
| `media-kit-p5-mpv` | AImageReader 与 `vo_gpu_next.c` 两文件；旧片尾候选，不能替代已提交 `c025cbf` 的产品版本。 |
| `media-kit-firstframe-sdr-20260927` | 5 个 app/plugin 文件；首帧 SDR 实验，需比对当前目录后才决定是否使用。 |
| `media-kit-firstframe-mix-20260927` | 877 个状态项：868 个删除、9 个修改；只保存 9 个修改的补丁。大量删除疑似工作树快照状态，**不得直接应用或清理**。 |
| `media-kit-p5-jar-rebuild-20260927` | 12 个 mpv 文件；旧 JAR 重建实验。 |
| `media-kit-p5-jar-ffmpeg-20260927`、`media-kit-ffmpeg-p5-stream-2215`、`media-kit-ffmpeg-n713-clean`、`media-kit-ffmpeg-dvtest-host-20260925` | FFmpeg 实验；已跟踪源码差异有补丁，`_build-*` 未跟踪项为构建目录内容，仅在清单列名。 |
| `media-kit-mpv-p5-replay-2214`、`media-kit-mpv-p84-rebuild-2213`、`media-kit-mpv-upstream-reader3` | mpv 旧重播/双视图实验，均有未提交源码差异与补丁。 |
| `media-kit-dovibaker-reference` | DoViBaker 参考实验；未跟踪的两个 C++ 源文件已复制，二进制仍只在临时目录。 |

上述每个工作树的**确切文件名、状态和 HEAD**在 JSON 工作树清单中，补丁按同名工作树命名。另有 `media-kit-libplacebo-d4624` 的 `.git` 入口不可用，未列为可读工作树；目录本身仍在临时盘，接手时需单独判定。干净的旧工作树也列于 JSON，不要仅凭目录名推断它们是产品版本。

## 当前目录尚未提交的工作

- `media_kit_video/lib/src/video_controller/android_video_controller/real.dart`：切源收到空 `VideoParams` 时清除旧尺寸缓存的候选；只过 `git diff --check`，未实机验证。对应 `archives/experiments/android-p5-source-switch-aspect-20260928.md`。
- `TASKS.md`、当前 conversation 与 `archives/experiments/android-p5-glass-tail-12617-12627-20260928.md`、`archives/experiments/android-p5-source-switch-aspect-20260928.md` 含 P3 最新进展；尚未提交，换 agent 时先运行 `git status --short`，不要误丢。

## 关键证据与限制

- P0 Texture SDR：`archives/experiments/android-p5-product-raw-prune-12574-12576-20260928.md` 与 `android-p5-glass-default-12581-12585-20260928.md`。
- P1 PQ 显示/首帧：`archives/experiments/android-p5-pq-product-candidate-12582-20260928.md`；最终当前 Surface PixelCopy 约 1.168 秒，用户画质验收通过。
- P2 PQ 性能：`archives/experiments/android-p5-pq-performance-12603-20260928.md`；2560×1440 严格 EOS VO11、decoder0，用户观感通过。
- P3 片尾紫屏：`archives/experiments/android-p5-glass-tail-12617-12627-20260928.md`；12625 短轮与 12626 全片命中回退且画面正常，12627 精简版尚未实机验收。设备和构建 socket 受限的事实见 `TASKS.md`，不要把签名/对齐当作播放通过。
- 临时 APK、JAR、日志、截图的逐个路径可从产物清单按实验编号查找；它只记录顶层项，未对大目录做递归哈希。换 agent 继续前，应重新核对文件存在、Git HEAD、设备、依赖与磁盘空间。
