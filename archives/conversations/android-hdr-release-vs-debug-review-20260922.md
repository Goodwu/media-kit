# Android HDR10/DV：回退后 Release 未见卡顿的审查（2026-09-22）

## Current State

- 当前仓库 HEAD：`193c746`，分支 `fix/darwin-video-output-rebuild-barrier`。
- 当前实现代码没有本轮修改；工作树仅有 `TASKS.md` 与 Android 首播相关归档未提交。
- 归档中的历史用户报告是：HDR10 首播约 6 秒转圈、DV 约 11 秒转圈，开始播放后下半屏全黑；该报告不是本次受控测量。
- 用户后续报告恢复修改前代码、编译安装 Release 后未看到卡顿；缺少该次安装包身份、播放内容、输出路径、时间轴和日志条件的闭环证据。

## Evidence collected

- ADB 当前可见设备：`3EP7N18C28016072`，型号 `LYA_AL00`；设备在历史安装过程中曾断连，当前运行中的包仍未核验。
- 本地 Release 候选：`media_kit_test/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`，40,722,123 bytes，SHA-256 `79e015bdcf10b3f68e238c846ce679fd729be49f9cba0050010879110cc9da54`，仅 `arm64-v8a`，包名 `com.example.media_kit_test`，versionCode `2001`，无 debuggable 标记。
- 本地 Debug 与 Release 产物存在，但没有“源码快照 → 完整构建命令 → APK hash → 安装时间/PID → 播放结果”的逐次映射；产物存在不能证明设备正在运行该包。
- 当前基线 Android controller：默认 `vo=gpu`，初始化 `hwdec` 来自配置；`wid` 重绑先写 `vo=null`，再写尺寸、`wid`、`vo`，有效 wid 后 seek 到当前位置；方法通道仍无条件 `debugPrint` 方法与参数。
- 回退前归档补丁不只是日志：多次改变 `vid=auto/no`、PlatformView 提前挂载、Surface 尺寸/固定尺寸、Texture/PlatformView 布局、`vo`/seek 时序、HDR dataspace JNI/SurfaceControl 路径及 HDR target 属性。

## Architect review

### 结论分级

- 已证实：当前没有 Android 实现代码 diff；历史 HDR10/DV 症状来自归档用户报告。
- 支持：回退并重新做受控实验是合理方向。
- 未证实：原代码无问题、Debug 必然卡而 Release 必然不卡、日志是主因、回退后的播放仍实际走 HDR/DV 输出。
- 反证：不能把本轮归纳为“仅增加调试信息”；补丁改变了解码、Surface、布局、颜色和初始化时序。

### 日志判断

日志可能造成额外开销，但当前没有日志吞吐、格式化耗时、Dart/平台线程调度、GC 或 ADB/IDE/debugger 状态证据。`debugPrint` 不能简单等同于 Release 自动关闭；日志洪泛也可能是反复重绑/解码失败的结果。必须在同一构建和输出路径下先关闭日志生成，再比较开启日志，而不是只关闭终端或过滤 logcat。

### 最高优先级风险点

1. 输出路径可能改变：baseline 测试配置与回退补丁涉及 `hwdec`、`vo`、`mediacodec_embed`、PlatformView 和 Texture 的不同组合。
2. `vid/vo` 与 Surface 时序可能改变：`vid=no/auto`、`vo=null`、Surface 提前挂载、seek 删除都会改变 MediaCodec 初始化和重绑窗口。
3. Surface 尺寸/合成拓扑可能改变：`setFixedSize`、viewport/rect、Texture 覆盖条件直接关联裁剪、buffer 尺寸和下半屏黑。
4. HDR 色彩路径可能改变：API 适用范围、SurfaceControl transaction 与 JNI `ANativeWindow_setBuffersDataSpace` 不同；属性成功或 `gamma=pq/hlg` 不等于真实 HDR 输出。

## Required next experiment

固定同一设备 `3EP7N18C28016072`、同一 HDR10 文件和同一 DV 文件（记录文件 SHA、轨道、profile、分辨率、帧率、码率），先本地离线播放，固定输出配置、`vo`、`hwdec`、Surface 路径、方向、电源/刷新率/温度和缓存状态。每组分别测进程冷启动与同进程重开，至少 5 次，记录真实可见首帧、60 秒内帧间隔/丢帧、黑屏比例及 `hwdec-current`/`vo`/Surface 状态。

| 组 | 代码/配置 | 构建 | 诊断日志 | ADB/调试器 |
|---|---|---|---|---|
| A | 同一 baseline、显式固定输出路径 | Release arm64 | L0：关闭日志生成 | 仅连接，不持续采集、不附着 |
| B | 与 A 完全相同 | Debug arm64 | L0 | 与 A 相同 |
| C | 与 B 完全相同 | Debug arm64 | L1：开启指定 Dart/Java/mpv 诊断 | 与 A 相同 |

只有 A↔B 可讨论构建模式影响，B↔C 才可讨论应用日志影响。之后再用相同条件加入持续 logcat 对照，最后才把可准确重建的失败补丁作为代码对照；网络/DASH/EDL 另做受控变量，不与本地单文件结果混算。

## Review outcome

本轮不修改 Android 实现、不声称修复、不提交。当前最稳妥结论是：Release 未见卡顿是有价值但未闭环的正向观察，不能排除代码/输出路径问题，也不能确认日志是主因。

## Controlled comparison progress

- 为测试应用增加 `MEDIA_KIT_DIAGNOSTICS` 编译时开关；L0 在 `main()` 初始化阶段关闭 Dart/Flutter `debugPrint`，不改变播放配置或 native 播放逻辑。
- A 组已构建并安装启动：Release arm64、L0、versionCode `2002`，APK SHA-256 `cffa529c6a6e1d33550a4d03591e1a2c7cfbf62f977953fb5ab6056176ea4fa3`。等待用户人工确认 HDR10/DV。
- B 组已构建未安装：Debug arm64、L0、versionCode `2003`，等待 A 组人工确认后安装。
- 安装过程曾遇到手机端权限拒绝和旧 versionCode 冲突；未卸载设备已有应用，改用更高临时 versionCode 解决。

## Manual comparison results

同一设备、同一测试应用、同一播放路径，由用户人工确认同一个 HDR10 样本和同一个 DV 样本：

| 组 | 条件 | HDR10 | DV |
|---|---|---|---|
| A | Release + L0，versionCode 2002 | 不卡，约 7 秒出视频 | 不卡，约 7 秒出视频 |
| B | Debug + L0，versionCode 2003 | 不卡，约 6 秒出视频 | 不卡，约 11 秒出视频 |
| C | Debug + L1，versionCode 2004 | 卡顿，约 6 秒出视频 | 卡顿，约 11 秒出视频 |

C 组进程日志回读为 141 行、16,307 bytes；A/B 进程分别为 11 行、1,080 bytes 和 13 行、1,278 bytes。该日志量是事后从 logcat buffer 按进程读取的辅助证据，不是播放期间的实时吞吐测量。

## Updated interpretation

- A/B 均不卡、C 两种内容均卡，且唯一实验变量是 L1 诊断日志开关，强烈支持诊断日志生成开销会诱发或放大当前卡顿。
- 这仍不能证明原始 HDR/Surface/MediaCodec 代码完全没有问题，也不能确定具体是 Dart debugPrint、平台日志、mpv log stream 还是日志汇聚/调度共同造成。
- 首帧等待约 6/11 秒在 B/C 基本相同，说明本轮 L1 主要与“播放中卡顿”相关，不能解释为首帧等待根因。
- 当前结论基于用户观感和事后日志量，未声称完成丢帧、PTS、CPU 调度或真实 HDR 输出的自动化验收。

## C rerun log classification

- C versionCode `2004` 重测由用户确认本次 HDR10/DV 均不卡；因此日志量与卡顿不是确定的一一对应关系。
- 实时抓取期间，按进程 `6365` 读取到的保留 logcat 缓冲为 156 条：`MediaKitBufferTrace` 62 条、MediaCodec/ACodec/OMX 37 条、Flutter/系统渲染与生命周期 27 条、音频 11 条、其他 12 条；应用侧还观察到 MPVLOG、VIDEOPARAMS、MPVPROP、VideoOutput resize 和 Java Surface 生命周期日志。
- `MediaKitBufferTrace` 62 条中，按当前保留缓冲统计：`demuxer-cache-time` 54、`core-idle` 4、`pause` 2、`paused-for-cache` 1、`cache-buffering-state` 1。它们展示的是时间戳、缓存秒数/百分比和 buffering 状态，不是错误。
- 实时内容示例：`MPVLOG [lavf] error: Failed to create file cache.`；属性为 `vo=gpu`、`hwdec-current=mediacodec-copy`；视频参数观察到 SDR `854x480/bt.601/bt.1886`、PQ `3840x1920/bt.2020/pq` 和 HLG `3840x1920/bt.2020/hlg`。
- MediaCodec/ACodec 日志展示 `OMX.hisi.video.decoder.avc/hevc` 的创建、色彩 aspects、output port change 和 flush/stop；这些是平台解码链路日志，不是 Dart 测试页主动生成的诊断文本。
- 该次 logcat 不是持久化完整日志文件；环形缓冲在停止后会继续被系统日志覆盖，因此以上数量明确标注为“抓取期间可回读的保留缓冲”，不冒充完整实时吞吐。

## 2026-09-26 审查收束

独立 architect 审查及 A/B/C 人工矩阵已记录，满足本项“复核回退后 Release 卡顿观察”的验收。C 组同版重跑曾由用户确认不卡，因此诊断日志开销可诱发或放大卡顿的判断仍是可能解释，不能当作确定根因；首帧等待、HDR 激活和后续播放稳定性仍由 Android HDR/DV 显示闭环任务继续验证。
