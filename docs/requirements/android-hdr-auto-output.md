# 需求：HDR 能力查询、路由执行与报告（消费方：PiliPlusX）

- 提出方：PiliPlusX（2026-10-02）
- 版本：v3（2026-10-02；修订记录见第 9 节）
- 状态：需求已定稿，按 `android-hdr-auto-output-plan.md` 实施
- 关联：`archives/experiments/android-playback-matrix-12703-12708-20260930.md`（实机基线）、`archives/conversations/architecture-review-remediation-20260930.md`（P0-1/P0-3）、`archives/conversations/android-hdr-auto-output-20261002.md`（本主题上下文）、`media_kit_hdr_lab/`（参考实现）

## 1. 背景与问题

media-kit 已在 LYA-AL00（API 29）上跑通三条 Android HDR 路径（播放矩阵 12703–12708，六轮全过）：

| 源类型 | 路径 | 证据要点 |
|---|---|---|
| HDR10 | `mediacodec_embed` PQ 直出 | SF 合成、静态元数据 types=3、全片 EOS |
| DV P8.4 | HLG 直出（及剥 RPU 的 SDR 对照） | 视频层 BT.2020 HLG、首帧 0.6–0.7s |
| DV P5 | `gpu-next` + dovi rescale → PQ 10 位视频层 | direct=1+RESCALE、全片 EOS、片尾回退命中 |

库内已有的部分：路由纯函数 `HdrOutputPolicy`（`classifyMedia`/`decide`，11 项单测）；`PlatformVideoView` 的 dataspace 应用链路（公开 NDK 优先，失败后回退到已注册的 `SurfaceDataSpaceExt`）；bridge `.so`（公开 JNI；原 4 个，2026-10-02 方案 B 后含 P5 管线探针共 5 个，见 R5.2 注记）；mpv JAR `libmpv-android-v2026.10`（P5 dovi rescale 管线）。

**缺口**：

1. 从策略到生效之间的编排，目前由调用方自己完成。这份编排有两份不一致的实现：`media_kit_hdr_lab` 的版本完整，而且经过实机验证；PiliPlusX `lib/plugin/pl_player/models/hdr.dart` 是旧实现，Android 上只认 HCPP 且要求 API≥34，在 LYA 上把 DV 路由到 toneMappedSdr/Texture，完全没用到上面这些库能力。
2. PiliPlusX 需要在**请求片源之前**判断设备能否原生呈现某类 HDR，再决定请求 HDR 档还是 SDR 档。库目前没有开播前可用的能力查询和预测接口。
3. 同一类源往往有不止一种可行处理方式。例如 P8.4 可以 HLG 直出、转换到 PQ 输出，也可以用 libplacebo 应用 RPU 重建后输出。现有 `HdrOutputPolicy` 对每类源只给出一条路由，无法按配置选择，也无法报告备选路由。
4. 已核实的库缺陷：mpv 的 `current-tracks/video/dolby-vision-profile` 是整数属性，取值为 `5`、`8`（`player/command.c` `SUB_PROP_INT`）。`classifyMedia` 匹配的是字符串 `'8.4'`，所以用解码器上报的真实值时，P8.4 永远识别不出来，会按 gamma 落到 `hlg`。
5. 现有链路没有原生 DV 呈现路径：FFmpeg mediacodec 只用 `video/hevc` 打开解码器（`mediacodecdec.c`），库只识别 HDR10（2）和 HLG（3）两种显示类型。在支持 DV 的设备上，DV 源目前以 HDR10 或 HLG 呈现。

## 2. 职责边界（本需求的前提）

| 事项 | 负责方 |
|---|---|
| 设备对各类源有哪些可行路由、按偏好会选哪条（开播前预测） | media-kit 回答 |
| 根据预测请求 HDR 档还是 SDR 档（片源与显示能力是否一致） | **PiliPlusX** |
| 跨平台的策略偏好（可选，见 R2） | PiliPlusX 声明，或使用库默认值 |
| 按偏好和可行性选择路由，执行（拓扑、mpv 属性、dataspace），复核 | media-kit |
| 所有 HDR 策略都不可行时，以 tone-mapped SDR 继续播放 | media-kit（**不主动停止播放**） |
| 报告实际路由、备选路由、降级原因和能力变化 | media-kit |
| 收到降级事件后是否换源、何时换源 | **PiliPlusX** |
| 根据路由信息展示播放信息 | PiliPlusX |

media-kit 不负责保证片源和显示能力一致，只负责如实预测、正确执行、完整报告。

## 3. 源描述、策略与偏好

### 3.1 源描述

分类结果从单一的 `HdrMediaKind` 升级为源描述 `HdrSourceDescriptor`，包含：

- 编码格式；
- 基础层的传输函数和色域；
- 动态元数据格式：`none`/`dolbyVision`/`hdrVivid`/`hdr10Plus`；
- DV profile；
- DV 基础层兼容 ID；
- 是否有增强层。

原来的 `HdrMediaKind` 由描述推导得出，保留用于兼容。

- **兼容 ID**：mpv 目前不暴露，按基础层传输函数推断：`pq` 对应 8.1，`hlg` 对应 8.4，`bt.1886` 对应 8.2。
- **是否有增强层**：需要在 mpv fork 中补充属性，或者从 FFmpeg DOVI 配置记录中读取，实施时评估改动量。无法确定时按"未知"处理；涉及 P7 的策略在未知时只允许走基础层直出。

### 3.2 策略

| 策略 | 含义 |
|---|---|
| `nativeDolbyVision` | DV 解码器加 DV 显示，由系统和 Dolby 引擎完成映射（**预留**，现有链路不支持，见 R7） |
| `baseLayerDirect` | 解码器直出 Surface（`mediacodec_embed`），按基础层的传输函数输出，忽略动态元数据 |
| `baseLayerConvert` | gpu-next 把基础层转换到显示器支持的 HDR 传输函数（如 HLG 转 PQ），忽略动态元数据 |
| `metadataReshape` | gpu-next/libplacebo 应用动态元数据（DV RPU 等）重建后输出 HDR（PQ） |
| `toneMapSdr` | Texture 输出，tone-map 到 SDR，是否应用动态元数据由各 profile 的规则决定 |
| `sdrDirect` | SDR 基础层直接 SDR 输出 |

### 3.3 偏好配置

库提供 `HdrRoutingPolicy`：为每类源给出一个按顺序排列的策略列表，并附带 `allowExperimental` 开关。库按顺序取第一条**本机可行**且**成熟度允许**的策略。

- App 可以覆写偏好。偏好只包含跨平台的策略名，不涉及 vo、hwdec、SDK 或机型，所以不算平台决策代码。
- 偏好 `off` 等价于把所有源的列表设为 `[toneMapSdr]`（SDR 源为 `sdrDirect`）。

### 3.4 默认偏好（原则：先 HDR 输出，再 tone-map；HDR 输出中直出优先）

| 源 | 默认顺序 |
|---|---|
| DV P5 | `nativeDolbyVision` → `metadataReshape`（PQ）→ `toneMapSdr`（应用 RPU） |
| DV P8.1 | `nativeDolbyVision` → `baseLayerDirect`（HDR10）→ `metadataReshape`（PQ）→ `toneMapSdr` |
| DV P8.4 | `nativeDolbyVision` → `baseLayerDirect`（HLG）→ `baseLayerConvert`（PQ）→ `metadataReshape`（PQ）→ `toneMapSdr` |
| DV P8.2 | `nativeDolbyVision` → `metadataReshape`（PQ）→ `sdrDirect` |
| DV P7 | `baseLayerDirect`（HDR10，忽略增强层和 RPU）→ `metadataReshape`（PQ，仅 MEL）→ `toneMapSdr` |
| HDR10 | `baseLayerDirect` → `baseLayerConvert`（PQ，GPU 输出）→ `toneMapSdr` |
| HLG | `baseLayerDirect` → `baseLayerConvert`（PQ）→ `toneMapSdr` |
| HDR Vivid | `baseLayerDirect` → `metadataReshape`（预留，未实现）→ `toneMapSdr` |
| SDR | `sdrDirect` |

P5 的基础层是 IPT 色彩空间，忽略 RPU 会偏色，所以 P5 没有 `baseLayerDirect`、`baseLayerConvert` 或"不应用 RPU 的 tone-map"策略。

### 3.5 成熟度门禁

每个"源 × 策略"组合有一个成熟度，记录在第 6 节的状态表中：

- `verified`：在实机上直接验证过。
- `inherited`：所用机制（解码器输入、vo/hwdec、输出传输函数、dataspace 路径）与某个已验证的组合完全相同，并且已有证据表明差异部分没有影响。还需要用一个样片补确认。
- `experimental`：没有验证。
- `unsupported`：现有链路无法实现。

默认允许 `verified` 和 `inherited`，`experimental` 必须显式开启 `allowExperimental`。如果因为成熟度门禁跳过了 HDR 策略，最终落到 `toneMapSdr` 或 `sdrDirect`，报告里必须写明原因 `experimentalStrategySkipped` 和被跳过的策略，App 可以据此决定是否开启。

## 4. 需求

### R1 能力查询与路由预测（开播前，公开 API）

1. 库提供开播前可调用的能力查询，内容包括：
   - display HDR types（Android `Display.HdrCapabilities`，**包括 DV（1）**、HDR10（2）、HLG（3）、HDR10+（4））；
   - HEVC 解码器的 Main10/HDR 档位与 4K 尺寸帧率支持；
   - `video/dolby-vision` 解码器列表及其支持的 profile；
   - P5 管线可用性；
   - dataspace bridge 是否加载、已注册的设备扩展是否适用于本机。
   查询不得调用 `eglInitialize`/`eglTerminate` 这类会干扰进程内其他 EGL 用户的接口。
2. 库提供按源描述的预测，输出：
   - 选中的策略与路由；
   - 全部候选策略，每条包括本机是否可行、不可行的原因和成熟度；
   - 呈现类型；
   - 置信度。
   输入可以是 `HdrSourceDescriptor`，也可以是 `HdrMediaKind`，可附带分辨率和帧率。
3. **预测与执行同源**：预测必须调用执行时使用的同一个规划函数，单测要覆盖"同一输入下，预测选中的路由等于执行选中的路由"。
4. **P5 管线可用性必须在运行时、开播前可查**，不得依赖日志标识串或编译期 define。Phase 1 的判定方法是检查 mpv 是否存在 fork 选项 `dovi-p5-fast-path`（`option-info/dovi-p5-fast-path/name` 非空）。这个选项与 rescale 修复在同一提交 `5f9ddf1777` 引入，只会把较早的 fork 世代误判为不可用，不会把不可用的构建误判为可用。长期方案是在 mpv fork 中提供专门的只读能力属性。`metadataReshape` 用于 DV 时，都依赖这项能力。
   - **注记（2026-10-02，方案 B）**：长期方案已落地——mpv fork 新增只读能力属性 `dovi-p5-pipeline`（bool）。判定改由 bridge `.so`（`media_kit_video_hdr_bridge`）在插件 engine attach 时创建抛弃式 mpv 实例（create→initialize→读属性→terminate，无 vo、无媒体、不触碰 EGL）执行一次并缓存；`option-info/dovi-p5-fast-path/name` 代理路径退役。上游构建无此属性→读取失败→判为不可用，仍是合法结果而非错误。
5. **置信度**：
   - `verified`：路由不依赖运行时 dataspace 应用，或依赖的设备扩展已对本机门禁匹配。
   - `unverified`：路由依赖开播后才能确定成败的 dataspace 应用。
   置信度与第 3.5 节的成熟度是两回事：成熟度说明这类组合有没有被验证过，置信度说明本机这次开播的结果能否在开播前确定。
6. 能力变化（系统 HDR 开关、显示器切换等）通过事件发布，事件携带新的能力快照。

### R2 路由执行（库内编排）

1. **API 放置位置**：编排放在**高于单个 `VideoController` 的会话对象**中，不是 `VideoControllerConfiguration` 上的一个选项。原因是 `AndroidVideoOptions.usePlatformView` 在控制器创建时就已固定，Texture↔PlatformView 切换只能通过替换控制器实现（hdr_lab `AndroidHdrOutputSlot` 已验证这种做法）。会话对象持有 Player，对外发布当前控制器，库同时提供配套 widget，在控制器替换时自动重新挂载，**内置全屏页也必须跟随替换**。
2. 会话接受 `HdrRoutingPolicy`（缺省时使用第 3.4 节的默认值），以及 `HdrOutputPreference.auto/off`。不命名为 `HdrOutputMode`，避免与 PiliPlusX 现有枚举重名。两者都可以在播放中修改，修改后在当前位置重建。
3. **源分类**：调用方可以在开播时传入 hint（`HdrSourceDescriptor` 或 `HdrMediaKind`；PiliPlusX 可由清晰度档位或 DASH codec 字符串推出，例如 `dvh1.08.xx` 加 HLG）。路由先按 hint 预配置，避免多一次重建。首个视频参数到达后，必须用解码器上报的事实复核：
   - 复核结果与 hint 不一致，并且导致选中的路由变化时，在当前位置做一次单变量重建。每次开播最多重建一次。
   - 没有 hint 时，先按 SDR Texture 打开，再按复核结果决定是否重建。
   - 禁止旧源回写、禁止发布失效输出。
   - **注记（2026-10-02）**：复核事实新增容器 DV 兼容 ID（`current-tracks/video/dolby-vision-compatibility-id`）、增强层标志（`current-tracks/video/dolby-vision-el-present`）与 HDR Vivid side data 存在性（`video-params/hdr-vivid`；均为 mpv fork 0f7e6bec32+ 属性）。分类器口径：容器显式兼容 ID 优先、基础层 gamma 推断回退（容器记录就是 DV 信令本身）；增强层按事实驱动、profile 缺省回退；HDR Vivid 事实接通 `HdrDynamicMetadata.hdrVivid`（成熟度经 class 推导自动生效）。
4. 执行内容沿用 hdr_lab 已验证的语义：
   - 写入并读回确认 `vo`/`hwdec`/`target-prim`/`target-trc`/`egl-output-format` 等属性，在会话结束或换源时恢复原值；
   - 按策略决定是否剥离 RPU（vf）；
   - 设置 P5 的 `hdr-compute-peak`/`dither` 事务性默认值；
   - 校验 `hwdec-current` 与预期一致。
5. 非 Android 平台在 Phase 1 中，会话对象退化为单控制器透传，报告 `unsupportedPlatform`。调用方代码不需要按平台分支。

### R3 降级与事件

1. 选中的 HDR 策略在运行时失败时，库**沿候选列表往后找**：跳过与失败环节相同的候选（例如 PQ dataspace 应用失败，其他依赖 PQ dataspace 的候选也跳过），最多再尝试一条 HDR 候选。仍然失败就 tone-map 到 SDR，**继续播放，不主动停止**。每一次降级都要发布事件。触发情形包括：
   - 决策判定显示能力不足；
   - dataspace 应用失败，或读回值与请求不符；
   - `hwdec-current` 与预期不符；
   - 输出绑定超时；
   - 播放中能力丢失或 dataspace 被重置后重新应用失败。
   降级发生在开播前时，直接按下一条候选打开。发生在播放中时，在当前位置重建。
   （口径确认 2026-10-02：**"每一次降级都要发布事件"仅指开播后运行时降级**。开播前规划相的候选跳过（如能力不足、门禁跳过 experimental）不是降级事件——跳过原因经 R1.2 预测候选与 R4.2 报告候选列表完整披露，会话按选中的路由正常打开并发 `RouteApplied`。A3-2 实测：模拟无 HLG 开播 P8.4，direct 因 `displayLacksTransfer` 计划相跳过、落 convert 打开，全程无 Degraded、报告候选携带跳过原因。）
2. 降级原因是类型化枚举，附带诊断文本。至少区分以下原因：`preferenceOff`、`displayLacksTransfer`、`noDisplayCapabilityReport`、`experimentalStrategySkipped`、`dataSpaceApplyFailed`、`dataSpaceReadbackMismatch`、`hwdecMismatch`、`outputBindTimeout`、`capabilityLost`、`unsupportedPlatform`。
3. **边界例外**：P5 的任何策略（包括 tone-map）都依赖 dovi rescale 管线才能正确着色。管线不可用时，库**不输出错误着色的画面**，改为发布 `p5PipelineUnavailable` 错误，播放不开始。PiliPlusX 应当在 R1 预测阶段就避开这种情况。
4. 能力恢复时不自动升回 HDR，只发布 `CapabilityChanged` 事件。
5. 事件只用于报告。换源由调用方决定，库不重试、不切换片源。

### R4 路由与状态报告

1. 路由结构 `HdrRoute`：
   - 策略；
   - 呈现类型（`sdr`/`toneMappedSdr`/`nativeHdr`，预留 `nativeDolbyVision`）；
   - 输出传递函数（`pq`/`hlg`/`sdr`）；
   - 是否应用动态元数据；
   - 拓扑（Texture/PlatformView）；
   - `vo`、`hwdec`、`targetPrim`、`targetTrc`、`surfaceTransfer`、`stripDvRpu`。
2. 状态 `HdrOutputReport`（可监听）：
   - 当前源描述，并标明来源是 hint 还是解码器复核；
   - 预测路由、实际路由，以及被跳过的候选和跳过原因；
   - dataspace 信息：请求值、实际生效路径（`ndk`/`surfaceControl`/`ext:<id>`/`none`）、读回值；
   - `hwdec-current`；
   - 是否已完成校验；
   - 降级原因或错误；
   - 开播代次（generation）。
   报告只能对应当前代次。App 可以据此展示，例如"杜比视界 P8.4 · HLG 直出"或"杜比视界 P5 · RPU 重建 PQ"。
3. 诊断日志默认关闭，开启后按层输出单行 `key=value` 日志：`HDR capability:`、`HDR predict:`、`HDR classify:`、`HDR decision:`、`HDR readback:`、`HDR degrade:`、`HDR recover:`。字段与 PiliPlusX 现有 `HDR decision:` 日志的对照表随实施一次性给出。
4. PiliPlusX 的 `probeHdrCapabilities`（MainActivity）由 R1 查询替代。新 API 发布后，旧接口在一个版本内保留，期间标记为废弃。

### R5 设备私有回退封装

1. 目标：**调用方零设备特定代码**。LYA-AL00 的厂商 dataspace 私有 ABI 回退（`LyaPqDataSpaceExt`，现位于 `media_kit_hdr_lab`）回归 media-kit 仓，作为受控交付物。
2. 结构：做成**同仓独立子包**（Android 插件），App 依赖后自动注册到核心库已有的 `SurfaceDataSpaceExt` 扩展点。核心库不包含私有 ABI，bridge `.so` 符号面保持 4 个公开 JNI。
   - **注记（2026-10-02，方案 B 批准后）**：探针（`MpvPipelineProbe.nativeProbeP5Pipeline`）为第 5 个公开 JNI。它不是设备私有 ABI——是公开能力探测（读 fork 只读属性 `dovi-p5-pipeline`，经抛弃式 mpv 实例执行）。本条原文意图（私有 ABI 不进核心 bridge）不变。
3. 安全要求：
   - **默认关闭**。仅在 SDK、`ro.build.fingerprint` 和请求的 dataspace（BT2020_PQ）三者精确匹配已验证配置时才调用私有 ABI。
   - 是否适用通过**只读检查**判定，不得用试调私有 ABI 的方式探测。不适用时不加载原生库。
   - 扩展对外暴露 `id` 和"本机是否适用"，供 R1 预测和 R4 报告使用。
4. 范围限制：私有 ABI 只用于 dataspace 应用回退。late PQ、EGL HDR、Vulkan HDR 这些诊断探针留在 hdr_lab，不进入子包。启用条件、判定方法和失效表现都要文档化，并有单测。

### R6 跨平台（Phase 2 另立需求）

Phase 1 只做 Android。darwin（三事实交集门禁、final24 运行时禁止降档）和 OHOS（VO 动态色彩契约单层写入）各自另立需求。本需求只要求源描述、策略、偏好、报告的 API 形态与平台无关，不阻碍它们以后收敛。

### R7 原生 DV 呈现（预留，另立需求）

1. Phase 1 只预留：能力查询报告 DV 显示类型与 `video/dolby-vision` 解码器（R1.1）；策略枚举包含 `nativeDolbyVision`；呈现类型包含 `nativeDolbyVision`。`nativeDolbyVision` 的成熟度为 `unsupported`，规划时永远跳过。
2. 在支持 DV 的设备上，DV 源按默认偏好的下一条策略呈现，报告中要明确写出"以 HDR10/HLG 呈现、非原生 DV"。
3. 原生 DV 路由另立需求。它涉及 FFmpeg（用 `video/dolby-vision` 和对应 profile/level 打开解码器，RPU 保留在码流中）、mpv（路由选择）和 media-kit 三方。等 DV 设备到位，摸清它的解码器和合成链路后再设计。

## 5. Phase 1 验收

主设备为 `3EP7N18C28016072`（LYA-AL00），对照设备为 Mi Note 3（无 HDR 屏）。

- **A1 参考复跑**：`media_kit_hdr_lab` 改用新会话 API，以样片身份作为 hint，复跑三路径矩阵。输出路径、dataspace（生效路径和读回值）、资源闭合与 12703–12708 逐项一致，P5 和 HDR10 全片 EOS。
- **A2 预测一致性**：LYA 上每个有样片的源，预测选中的策略和路由与实际执行逐项一致，候选列表的可行性判断正确。Mi Note 3 上所有 HDR 源都预测为 tone-map，原因正确。
- **A3 降级不停播**：注入以下三种故障（测试钩子）：
  - 卸载设备扩展后开播 P5；
  - 模拟显示器无 HLG 后开播 P8.4，预期沿候选列表落到 `baseLayerConvert`（PQ）；
  - 在 Mi Note 3 上开播 HDR10。
  每种情况都要按候选列表走到预期策略，发布对应事件，持续播放 ≥60s 不停止，报告的实际路由正确。
- **A4 复核重建**：分别给出错误 hint（SDR→HDR10、HDR10→P8.4）和不给 hint，结果都只发生一次重建，重建后的位置偏差 ≤1s，最终路由正确，期间不发布过期代次的报告。
- **A5 生命周期**：退出重入、切档、前后台、全屏旋转（含全屏中发生控制器替换）、暂停/seek、播放中修改偏好或策略配置后，报告与输出正确。测试窗口内无 ANR/FATAL，资源闭合，`MpvOwnerBroker` 与 SurfaceReleaseProtocol 不回归。
- **A6 策略偏好**：P8.4 在开启 `allowExperimental` 并把 `metadataReshape` 排第一时，能走 RPU 重建 PQ 并且画面正确（人工观察加读回），报告中的策略相应变化。默认配置下仍然走 HLG 直出。
- **A7 PiliPlusX 接入**：arm64 release，同一台 LYA，覆盖以下样片：
  - `BV1vY4y1N7TY`（实测 P8.4/HLG）：预测可呈现，并走 HLG 直出出图；
  - HDR10 样片：走 `mediacodec_embed` PQ；
  - 本地 P5 样片：走 RPU 重建 PQ；
  - SDR 回归样片：行为不变。
  App 能展示路由信息，并在注入降级后按自身策略处理。
- **A8 diff 审查**：PiliPlusX 中没有设备特定代码，也没有 vo/hwdec/SDK/拓扑判断。允许出现的只有：调用 R1 查询选择档位、可选的跨平台策略偏好、展示路由、处理事件。

## 6. 源 × 策略状态表（成熟度事实源，随验证更新）

| 源 | 策略 | 成熟度 | 依据或缺口 |
|---|---|---|---|
| HDR10 | baseLayerDirect | verified | 12703–12708 |
| HDR10 | baseLayerConvert | experimental | 策略中有 `preferGpuOutput`，矩阵未单列 |
| HDR10 | toneMapSdr | verified | Texture→SDR 首帧受控轮 |
| HLG | baseLayerDirect | experimental | 只有 P8.4 剥 RPU 对照，缺纯 HLG 样片轮（本地 `HDR Vivid_HLG` 可用作基础层） |
| DV P5 | metadataReshape | verified | 12703–12708，全片 EOS |
| DV P5 | toneMapSdr | verified | P0 P5→Texture SDR 默认开启，真人确认 |
| DV P8.4 | baseLayerDirect | verified | 12703–12708 |
| DV P8.4 | baseLayerConvert | experimental | `forceP84PqFallback` 模拟路径存在，需要单列一轮实机验证后升级 |
| DV P8.4 | metadataReshape | experimental | 重建管线只在 P5 验证过 |
| DV P8.4 | toneMapSdr | verified | 12703–12708 SDR 对照 |
| DV P8.1 | baseLayerDirect | inherited | 机制同 HDR10 直出；P8.4 直出已证明 LYA 的 HEVC 解码器能容忍 RPU NAL；缺样片确认 |
| DV P8.1 | metadataReshape / toneMapSdr | experimental | 缺样片 |
| DV P8.2 | 全部 | experimental | 缺样片 |
| DV P7 | baseLayerDirect | experimental | 缺样片；增强层识别方式待定 |
| DV P7 | metadataReshape | experimental | 仅 MEL；FEL 为 unsupported |
| DV P10 | 全部 | unsupported | Phase 1 不涉及 AV1 |
| HDR Vivid | baseLayerDirect | experimental | 本地有样片，待单列验证 |
| HDR Vivid | metadataReshape | unsupported | 未实现 |
| 任意 DV | nativeDolbyVision | unsupported | R7 |

样片收集：P8.1、P7（MEL 与 FEL）、P8.2、纯 HLG 各至少一个，记录 SHA-256 后放入 `~/src/media-kit-build/sources/`。

## 7. 性能约束

- hint 命中时，首帧（触摸到内容）不劣于基线：P8.4/HDR10 ≤0.8s（基线 0.6–0.7s）。
- hint 错误、无 hint 或沿候选列表降级时，包含一次重建在内首帧 ≤2.0s，实测值单独列出。
- 4K60 负载不因编排层产生回归（归因结论是热状态主导，对比测试必须控制温度）。`metadataReshape` 和 `baseLayerConvert` 的功耗与发热高于直出，实验性组合的验证要记录负载数据，供决定默认顺序参考。

## 8. 其他约束与已知限制

- 不破坏既有公开 API（P1-3 的 `AndroidVideoOptions`/`DarwinVideoOptions` 迁移表）。会话 API 是增量入口。
- 暂停空转修复（churn_fix_20261001 边沿触发）与 SurfaceReleaseProtocol/NativeOutputLifecycle 协议在会话编排下继续生效。
- 测试面：`HdrOutputPolicy` 既有 11 项单测不回归（分类修复后对应用例同步修订）。hdr_lab 已有的 coordinator、slot、intent、disposal 单测迁入库内后继续通过。编排层新增行为要有 VM 单测。
- 当前只有一台 HDR 实机（LYA，API 29，依赖私有回退）。公开 NDK 直接成功的路径（API 30–33）和 SurfaceControl 路径（API≥34）缺少实机证据，相关预测置信度标为 `unverified`。新设备接入后，先跑现有矩阵，再补其他验证。
- P5 管线判定使用选项存在性作为代理（R1.4），较早的 fork 世代会被判为不可用。（注记 2026-10-02：该代理已退役，判定改为 fork 只读属性 `dovi-p5-pipeline` 经 bridge 探针，见 R1.4 注记——本条限制不再适用。）
- （2026-10-02 实机登记）**HDR Vivid 事实在 mediacodec 路径不可观测**：Android MediaCodec 解码不向输出帧传播 CUVA 005.1 逐帧 side data，会话路由全部强制 `hwdec=mediacodec`，因此 `video-params/hdr-vivid` 在硬解路径恒 false、Vivid 源按基础层分类（实测 `archives/experiments/android-hdr-planb-device-facts-20261002.md` R1/R1b：软解 `hwdec=no` 下同一属性读 true，归因为解码通道剥离而非属性缺陷）。路由结果不受影响（hdrVivid 与基础层 HLG 在缺省策略下同为 tone-map 安全网），仅报告的元数据格式在硬解路径按基础层显示。库不为此切换软解路由（4K 软解不可行）；Vivid 元数据的可靠检测需 demuxer/码流级 SEI 探测，归入 ② 完整目标（动态元数据重建扩展）。

## 9. 修订记录

- v1（2026-10-02）：PiliPlusX 初稿。
- v2（2026-10-02）：
  - 明确职责边界；
  - 新增开播前预测，预测与执行同源；
  - 降级改为 tone-map 后继续播放加事件；
  - API 改为会话对象加 widget；
  - P5 能力改为运行时探测；
  - 私有回退改为独立子包；
  - Phase 2 拆出；
  - 补充 `dolby-vision-profile` 整数取值缺陷和首帧预算。
- v3（2026-10-02）：
  - 新增源描述、策略、偏好配置、成熟度门禁（第 3 节）；
  - 默认偏好改为先 HDR 输出再 tone-map、HDR 输出中直出优先（用户决策）；
  - 降级改为沿候选列表查找；
  - 新增源 × 策略状态表与样片收集任务（第 6 节）；
  - 预留原生 DV（R7），能力查询增加 DV 显示类型与 DV 解码器；
  - 动态元数据格式覆盖 HDR Vivid 和 HDR10+；
  - 新增验收 A6（策略偏好），原 A6/A7 顺延为 A7/A8。
