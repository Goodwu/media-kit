# mpv fork 分支归一与发布基线（2026-09-30）

## 背景

Goodwu/mpv fork 上自定义修改散落在 4 个分支（另 44 个为 fork 继承的上游分支），无法输出包含全部修复的单一版本。本次归一回单一维护分支并建立发布基线。

## 归一前的分支拓扑（全部基于上游 mpv master `32a164cc01`，落后当时上游 982 提交）

| 分支 | tip | 独有内容 | 处置 |
|---|---|---|---|
| `feature/android-p5-sdr-direct-yuv` | `398d0c3` | 7 提交：直接采样候选 6758565、同帧复用 aa8bd10、OES 回退 91554aa、清理 33a212e/8e7c23e、片尾相邻帧回退 c025cbf、颜色重标定 398d0c3。全部产品修复在此线 | 作为新分支基底 |
| `feature/android-dv-native` | `a81978b` | 0（元数据传递 1 提交） | 已包含，删除 |
| `experiment/android-dv-p5-renderer` | `63a0aa9` | 2 提交（a322dd2 归档实验路线 ~3229 行 + 63a0aa9 线性解码候选开关）；有效成果 `optimize_dovi_linear_decode` 已产品化进主线 | tag 归档后删除 |
| `fix/ffmpeg-log-owner-handoff` | `9acfeff` | 1 提交：`common/av_log.c` 多实例日志接管修复（10445 实机短轮验证） | cherry-pick 后删除 |

## 执行结果

- **新维护分支 `media-kit/android`**（Goodwu/mpv，tip `6719532703`）= `398d0c3` + 2 提交：
  - `5379756208` docs: 更正 P5 缓冲位深注释——0x325 为 Main10 10-bit 布局、Y2Y 采样按 code/1020 归一化（P5 遗留措辞项，行为不变）；
  - `6719532703` 修复多实例销毁后的 FFmpeg 日志接管（cherry-pick 自 `9acfeff`，`git cherry` 判定补丁级等价）。
- **发布 tag `media-kit-v2026.09`** → `398d0c3`（已验收产品状态，刻意不含未回归的 cherry-pick）。
- **归档 tag `archive/android-dv-p5-renderer-202609`** → `63a0aa9`。
- 删除远端 4 个旧分支；本地 `/tmp/mkmpvsrc` 切至 `media-kit/android` 并删除本地旧分支。
- 验证：三个旧分支 tip 对新分支做 `merge-base --is-ancestor` 判定（experiment 为预期非祖先，由 tag 覆盖）；NDK 27.2 arm64 全量重链 `libmpv.so` 通过（含改动的 `common/av_log.c` 与 `video/out/hwdec/hwdec_aimagereader.c`）。仅编译验证，未实机回归；av_log 修复合入后产品 JAR 尚未重建，属下一发布周期事项。

## 发布链（一个版本必须同时固定三件套）

| 组件 | 仓库/分支 | 固定 commit |
|---|---|---|
| mpv | Goodwu/mpv `media-kit/android`，发布基线 tag `media-kit-v2026.09` | `398d0c30e5576f2d9c41531bb8c2b2fa12e4923a` |
| FFmpeg | Goodwu/FFmpeg `feature/android-mediacodec-p5-rpu` | `fff3ee7a3e520c22e3b9d43e62afb1a3ffb2e793` |
| libplacebo | Goodwu/libplacebo `optimize/dovi-linear-decode` | `c9fd87984d2495778133f6b733635f871505a432` |

对应已验收正式 JAR：`/tmp/media-kit-p5-colorfix-398d0c3-arm64.jar`，SHA-256 `dad30ae23cd75e85c43663959ce9e1c5940ae632adda404fbfe71d4202c2a9f7`（APK 12680/12681/12682 三轮实机验收 + 真人确认，见 `android-p5-mediacodec-color-fix-20260930.md`）。教训不变：产品链接必须用 fff3ee7 世代 libavcodec。

FFmpeg 与 libplacebo fork 各只有一条自定义分支，无需归一。

## 附带事项

- `/tmp/mkmpvsrc` 工作区原有 670 行未提交诊断探针（P5_GAMUT_SOURCE/P5_YUV_DUMP/GPU timer 等，`debug.media_kit.*` 属性门控）已存为 `archives/experiments/android-mpv-diagnostic-probes-20260930.patch` 后清理；诊断构建需要时可重新应用。
- 环境教训：本机 `git-credential-osxkeychain` 查询 github.com 挂死（疑钥匙串 ACL 弹窗），git push 因此无输出挂起；绕过方式 `git -c credential.helper= -c credential.helper='!gh auth git-credential' push …`（gh CLI 已登录 Goodwu）。
- media-kit 主仓侧：`feature/android-p5-pq-product`（139 提交，全包含于 `fix/darwin-video-output-rebuild-barrier`）及其工作树 `/private/tmp/media-kit-p5-pq-product` 已删除；当前分支已推送远端。
- **media-kit main 合并推迟**：浅克隆曾误导 main 仅领先 1 提交，unshallow 后实为上游 236 提交（含 `a7cec615` AndroidVideoController 重构等），与当前分支 60+ 文件冲突（核心文件双侧大改）。按「版本发布前不追上游」原则中止合并，登记为独立任务，需专门冲突解决 + 实机回归后再合。
- 遗留临时工作树（未动，HEAD 均已包含于当前分支，但有未提交实验改动）：`/private/tmp/media-kit-firstframe-mix-20260927`、`/private/tmp/media-kit-firstframe-sdr-20260927`；`/private/tmp/media-kit-p5-app` 已 prunable（目录不存在）。

## 追加：Goodwu/media-kit 分支清理（2026-09-30 同日）

远端原有 12 个分支（均为 fork 自建，无上游继承分支），清理后仅剩 `main`（d9be8fdf）：

- **直接删除（内容完整包含于 main）**：`feature/android-p5-pq-product`（139 提交，P1/P2 正式 PQ 产品线）、`integration/piliplusx-hdr-08`、`validation/ohos-dart310-6393db1a`、`version_1.2.5`。
- **归档 tag 后删除（SHA 独有历史，内容已由 main 等价承载）**：
  - `archive/integration-piliplusx-hdr-202609`（原始 144 提交集成线，经 squash port 进主线，SHA 不可追溯）
  - `archive/integration-piliplusx-hdr-public-api-202609`（public-api 变体，含 08b 的 OHOS HAP CI 为祖先；lifecycle 契约 `disposeForRebuild` 与 OHOS CI 已在 main 验证存在）
  - `archive/source-predidit-main-202609`、`archive/source-predidit-feat-hcpp-202609`（Predidit fork 源快照，供后续上游同步 diff 基准）
  - `archive/version-1.3.0-predidit-202609`（Predidit v1.3.0 版本快照）
  - `archive/dev-darwin-xcframeworks-exp-202609`（dev 分支 Darwin xcframeworks 源切换临时实验，melodink v0.6.0 pin，未采纳）
- 本地 `remote.origin.fetch` 恢复为全分支通配并 prune 过期 tracking refs。

至此三个自有仓库均为单分支：Goodwu/mpv `media-kit/android`、Goodwu/media-kit `main`；FFmpeg/libplacebo 各自单分支不变。

## 追加：mpv fork 上游跟踪策略（2026-09-30 定）

**结论：跟发布版，不跟 master。**

事实依据（当日核实）：
- 我方基点 `32a164cc01` 是 v0.41.0 发布后不久的 master 快照，与 v0.41.0 仅差 vo_gpu_next 15 行——当前实质就在 v0.41 世代，无迁移动作待做。
- 上游 master 领先 982 提交，其中 vo_gpu_next 46 提交/1029 行为 libplacebo v7 API 迁移与新特性（min libplacebo v7.360.1、scRGB、reference white、Wayland set_color 等），与我方 1100+ 行改动正面冲突；aimagereader 仅 2 提交/44 行错误处理改进。
- **master 未包含我们任何一项修复**：dovi 元数据重标定、外部 YUV 直接采样、片尾相邻帧回退、av_log 多实例接管均无上游对应物；上游 dovi 提交全在 demux 侧（EL+BL 拆分）。maxImages 5→3 双方独立改过（同步时自动消解）。

执行策略：
- 同步节奏：等 v0.42 发布 → `git merge-tree` 只读试评估（重点 hwdec API 与 vo_gpu_next dovi 路径受 libplacebo v7 迁移冲击面）→ 可接受则整体迁移 + P5 五项实机回归 → 打新发布 tag。
- 期间个别修复按需 cherry-pick（候选：上游 `14f2d48cbc` aimagereader 错误处理，含 buffer 已释放 ENOENT 假成功 HACK，与我方片尾回退互补不重复）。
- FFmpeg 安全修复与 mpv 跟踪策略解耦，走 CVE 按需 cherry-pick。
- 已知欠账：`media-kit/android` tip（`6719532`）的 av_log 修复尚未进产品 JAR（dad30ae2 基于 398d0c3 构建），下个发布周期重建 JAR 时纳入。
