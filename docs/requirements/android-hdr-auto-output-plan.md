# 实施计划：HDR 能力查询、路由执行与报告（Phase 1 Android）

- 对应需求：`docs/requirements/android-hdr-auto-output.md` v3
- 主题上下文：`archives/conversations/android-hdr-auto-output-20261002.md`
- 编制：2026-10-02（随需求 v3 修订）

## 1. 设计

### 1.1 总体结构

```
PiliPlusX
  │ ① HdrCapabilities.query(player) → 能力快照
  │ ② caps.predict(descriptor, policy) → 选中策略 + 候选列表；据此选清晰度档（App 职责）
  │ ③ session.open(media, hint: descriptor)
  │ ④ 监听 session.report / session.events，用 HdrVideo(session) 显示
  ▼
media_kit_video（Dart）
  HdrVideoSession ──持有── Player
    ├─ HdrOpenCoordinator   串行副作用队列、代次失效、回滚（移植 hdr_lab coordinator）
    ├─ HdrOutputSlot        控制器替换：先 disposeForRebuild 旧的，再建新的并发布（移植 hdr_lab slot）
    ├─ AndroidHdrBackend    属性写入、读回、恢复，dataspace 应用，轨道与 hwdec 校验（移植 hdr_lab backend，去掉样片身份）
    ├─ HdrRoutePlanner      描述 + 能力 + 偏好 + 成熟度表 → 候选列表 → 选中路由；预测和执行都只走这里
    │    └─ HdrStrategyRealizer  单条策略 → HdrRoute（内部调用 HdrOutputPolicy.decide 及新增的策略分支）
    ├─ HdrSourceClassifier  hint / 解码器事实 → HdrSourceDescriptor
    └─ HdrCapabilities      原生能力查询 + P5 选项探测 + 能力变化事件
  HdrVideo(widget)          监听 session.controller，替换时重挂 Video；向下注入 session 供全屏使用
media_kit_video（Android 原生）
  MediaKitVideoPlugin: HdrCapabilities.Get / HdrCapabilities.Changed / PlatformVideoView.ApplyDataSpace
  PlatformVideoView.SurfaceDataSpaceExt: 新增 default id() / isApplicable()
media_kit_android_dataspace_vendor（新子包，Android 插件）
  LyaPqDataSpaceExt（仅 apply 路径）+ 原生 perform 回退；适用时自动注册
```

### 1.2 公开 API（草案）

```dart
enum HdrDynamicMetadata { none, dolbyVision, hdrVivid, hdr10Plus }
enum HdrStrategy {
  nativeDolbyVision,   // 预留，成熟度 unsupported
  baseLayerDirect, baseLayerConvert, metadataReshape, toneMapSdr, sdrDirect,
}
enum HdrStrategyMaturity { verified, inherited, experimental, unsupported }
enum HdrPresentation { sdr, toneMappedSdr, nativeHdr, nativeDolbyVision }
enum HdrPredictionConfidence { verified, unverified }
enum HdrDegradeReason {
  preferenceOff, displayLacksTransfer, noDisplayCapabilityReport,
  experimentalStrategySkipped, dataSpaceApplyFailed, dataSpaceReadbackMismatch,
  hwdecMismatch, outputBindTimeout, capabilityLost, unsupportedPlatform,
}

class HdrSourceDescriptor {
  final String codec;                  // 'hevc' | 'av1' | 'h264' ...
  final String? transfer, primaries;   // 基础层
  final HdrDynamicMetadata dynamicMetadata;
  final int? dvProfile;                // 5 / 7 / 8 / 10 ...
  final int? dvCompatibilityId;        // 由基础层传输函数推断，或来自 hint
  final bool? enhancementLayer;        // null = 未知
  HdrMediaKind get kind;               // 兼容旧枚举
  factory HdrSourceDescriptor.fromKind(HdrMediaKind kind);
}

class HdrRoutingPolicy {
  const HdrRoutingPolicy({Map<HdrSourceClass, List<HdrStrategy>>? preferences,
                          bool allowExperimental = false});
  static const HdrRoutingPolicy defaults;   // 需求 3.4
}

class HdrCandidate {
  final HdrStrategy strategy;
  final HdrStrategyMaturity maturity;
  final bool feasible;
  final HdrDegradeReason? skipReason;  // 不可行或被成熟度门禁跳过
  final HdrRoute? route;               // 可行时
}

class HdrRoutePrediction {
  final HdrSourceDescriptor source;
  final HdrCandidate selected;
  final List<HdrCandidate> candidates; // 按偏好顺序，含被跳过的
  final HdrPresentation presentation;
  final HdrPredictionConfidence confidence;
  final bool playable;                 // P5 管线缺失时为 false
}

class HdrCapabilities {
  static Future<HdrCapabilities> query({required Player player});
  final int sdkInt;
  final Set<int>? displayHdrTypes;     // 含 DV(1)/HDR10(2)/HLG(3)/HDR10+(4)；null = 无能力报告
  final List<HdrDecoderInfo> hevcDecoders;
  final List<HdrDecoderInfo> dolbyVisionDecoders;
  final bool p5PipelineAvailable;
  final bool dataSpaceBridgeLoaded;
  final HdrDataSpaceExtInfo? dataSpaceExt;
  HdrRoutePrediction predict(HdrSourceDescriptor source,
      {HdrRoutingPolicy policy = HdrRoutingPolicy.defaults,
       HdrOutputPreference preference = HdrOutputPreference.auto,
       int? width, int? height, double? fps});
}

class HdrVideoSession {
  HdrVideoSession(Player player, {
    HdrOutputPreference preference = HdrOutputPreference.auto,
    HdrRoutingPolicy policy = HdrRoutingPolicy.defaults,
    VideoControllerConfiguration configuration = const VideoControllerConfiguration(),
  });
  ValueListenable<VideoController?> get controller;
  ValueListenable<HdrOutputReport> get report;
  Stream<HdrOutputEvent> get events;   // RouteApplied / Degraded / Reclassified / CapabilityChanged / Error
  Future<void> open(Media media, {HdrSourceDescriptor? hint, bool play = true, Duration? start});
  Future<void> setPreference(HdrOutputPreference preference);
  Future<void> setPolicy(HdrRoutingPolicy policy);
  Future<void> dispose();
}

class HdrVideo extends StatelessWidget {  // 参数与 Video 对齐
  const HdrVideo({required HdrVideoSession session, ...});
}
```

`HdrSourceClass` 是偏好表的键：`dvP5`/`dvP81`/`dvP84`/`dvP82`/`dvP7`/`dvP10`/`hdr10`/`hlg`/`hdrVivid`/`hdr10Plus`/`sdr`，由描述推导。命名在 S5 最终确定。

### 1.3 规划算法（预测与执行共用）

```
plan(source, caps, policy, preference, excluded = {}):
  cls = classOf(source)
  list = preference == off ? [toneMapSdr 或 sdrDirect] : policy.preferences[cls] ?? defaults[cls]
  for s in list:
    maturity = maturityTable[cls][s]                     // 需求第 6 节，代码内常量表
    if maturity == unsupported            → 记录跳过（unsupported），继续
    if maturity == experimental && !policy.allowExperimental
                                          → 记录跳过（experimentalStrategySkipped），继续
    if s 依赖的环节 ∈ excluded             → 记录跳过（沿用失败原因），继续
    route = realize(s, source, caps)                      // 不可行时给出原因
    if route == null                      → 记录跳过（displayLacksTransfer 等），继续
    return selected = s，并把剩余项也评估可行性放入 candidates（供展示）
  P5 且 !caps.p5PipelineAvailable → playable = false（p5PipelineUnavailable）
  兜底：toneMapSdr（SDR 源为 sdrDirect）
```

`realize` 中各策略的路由映射，复用现有 `HdrOutputPolicy.decide` 的分支，并补齐缺失的组合：

| 策略 | vo / hwdec | 输出 | dataspace | RPU |
|---|---|---|---|---|
| baseLayerDirect | mediacodec_embed / mediacodec | 基础层的传输函数（需要显示器支持） | 无 | 不剥（解码器忽略） |
| baseLayerConvert | gpu-next / mediacodec，PlatformView，rgb10_a2 | 显示器支持的 HDR 传输函数（优先 PQ） | pq/hlg | DV 源剥离 |
| metadataReshape | gpu-next / mediacodec，PlatformView，rgb10_a2 | PQ | pq | 保留（需要 P5 管线能力） |
| toneMapSdr | gpu-next / mediacodec，Texture | bt.709/bt.1886 | 无 | P5 保留；其他 DV 源按现有规则剥离 |
| sdrDirect | gpu-next / mediacodec，Texture | 源标签 | 无 | 剥离 |

"依赖环节"用于降级时跳过同类候选：`dataspace:pq`、`dataspace:hlg`、`hwdec:mediacodec`、`topology:platformView`。

### 1.4 开播流程（单次 open，一个代次）

1. `generation++`，使上一代失效，后续每步之后都检查代次。
2. 取能力快照，`plan(hint ?? sdr, caps, policy, preference)`。`playable == false` 时发布 `Error(p5PipelineUnavailable)` 并结束。
3. 停止旧媒体（确认 `path` 已清空），恢复本会话改动过的属性。
4. `slot.ensure(route)`：拓扑或 vo 不变就复用当前控制器，否则替换控制器并发布。
5. PlatformView GPU 路由：等待输出绑定后调用 `ApplyDataSpace`，得到 `{applied, path, readback}`。失败时把对应环节加入 `excluded` 后重新 plan（每代次最多再试一条 HDR 候选，之后直接兜底），然后回到第 3 步。这一步发生在打开媒体之前。
6. 写入并读回确认属性，按路由挂或不挂 RPU 剥离 vf，设置 P5 事务性默认值。
7. 打开媒体，确认 file-loaded 事件对应本次的 playlist entry。
8. 复核：读 video-params 与 `dolby-vision-profile`，生成描述。
   - 重新 plan 后选中的路由变化，且本代次还没重建过：记录位置，回到第 3 步，在原位置重新打开。
   - `hwdec-current` 不符：把 `hwdec:mediacodec` 加入 `excluded`，重新 plan，在原位置重开。
9. 发布 `HdrOutputReport`（标明 verified，附候选列表和跳过原因）与 `RouteApplied` 事件。

播放中的情形：
- 能力变化导致当前路由失效，或 dataspace 被重置后重新应用失败：按第 5 步规则沿候选列表降级，在当前位置重建。
- 偏好或策略配置变化：重新 plan，路由变化时在当前位置重建。
- 能力恢复时只发布 `CapabilityChanged`，不自动升回 HDR。

### 1.5 分类规则（`HdrSourceClassifier`）

| 解码器事实 | 描述 |
|---|---|
| `dolby-vision-profile` = 5 | dvProfile 5，dynamicMetadata dolbyVision，compat 0 |
| = 8，gamma pq，primaries bt.2020 | dvProfile 8，compat 1（8.1） |
| = 8，gamma hlg | dvProfile 8，compat 4（8.4） |
| = 8，gamma bt.1886/srgb 等 SDR | dvProfile 8，compat 2（8.2） |
| = 7 | dvProfile 7，compat 6；增强层按 mpv/FFmpeg 可得信息判断，取不到为 null |
| = 10 | dvProfile 10，codec av1，compat 按 gamma 推断 |
| 空，gamma pq + bt.2020 | HDR10（HDR10+、HDR Vivid 的动态元数据识别在 S1 评估可得性，取不到时为 none） |
| 空，gamma hlg | HLG（HDR Vivid 同上） |
| 其他 | SDR |

`classifyMedia` 保留，内部改为调用分类器后取 `kind`；`'8.4'` 字符串分支保留，兼容旧的 hint。

### 1.6 设备扩展子包

- 包名暂定 `media_kit_android_dataspace_vendor`（`libs/android/` 下）。
- 只包含 `applyDataSpace` 路径及其原生实现（fingerprint 门禁 + `perform(window, 19, BT2020_PQ)`，并读回校验）。探针留在 hdr_lab。
- 插件的 `onAttachedToEngine` 中先执行 `isApplicable()` 只读检查（SDK==29 且 `Build.FINGERPRINT` 精确匹配），适用时才注册。不适用时既不注册，也不加载原生库。
- 核心库 `SurfaceDataSpaceExt` 接口新增 `default String id()` 与 `default boolean isApplicable()`。

## 2. 分步计划

每步都写明内容、验证方法与通过判据、审核等级（按 agent-team 路由规则：V0 由 Lead 审，V1 交 Reviewer，V2 交 Critical Reviewer）。多个步骤修改同一文件时串行执行。实机步骤共用第 3 节的设备纪律。

### S0 基线冻结

- 内容：记录 media-kit `main` 提交、产品 JAR SHA-256（`c0e5d7f0…`）、hdr_lab 构建参数，跑现有测试。
- 验证：
  - `media_kit_video` 下 `flutter test` 全部通过，其中 `hdr_output_policy_test` 11 项通过；
  - `media_kit_hdr_lab` 下 `flutter test` 全部通过；
  - 记录通过数，作为后续的回归基线。
- 审核：V0。

### S1 源描述与分类

- 内容：
  - 新增 `HdrSourceDescriptor`、`HdrSourceClassifier`，规则见 1.5；
  - `classifyMedia` 改为委托分类器；
  - 评估增强层与 HDR10+/HDR Vivid 动态元数据的可得性（mpv 属性、FFmpeg side data），给出结论：能直接读取的就接入，需要改 mpv fork 的单列为后续任务。
- 验证：
  1. 单测：1.5 表格的每一行至少一个用例；原 11 项用例不回归（P8.4 用例改为整数输入后仍然通过）。
  2. 实机事实核对：在 LYA 上用 hdr_lab 分别开播 HDR10、P8.4、P5、HDR Vivid(HLG) 样片，记录 `current-tracks/video/dolby-vision-profile` 与 `video-params/gamma|primaries` 的实际值，代入分类器，结果必须符合预期。
  3. 可得性评估结论写入主题 conversation。
- 审核：V0。

### S2 原生能力查询与 P5 探测

- 内容：
  - `MediaKitVideoPlugin` 新增 `HdrCapabilities.Get`，返回 sdkInt、displayHdrTypes（含 1/2/3/4）、HEVC 解码器档位与 4K 尺寸帧率、`video/dolby-vision` 解码器及 profile、bridge 是否加载、扩展 id/适用性。不做 EGL 初始化。
  - 新增 `HdrCapabilities.Changed`：DisplayManager 监听默认显示器。
  - `SurfaceDataSpaceExt` 增加 default 方法 `id()`/`isApplicable()`。
  - Dart 侧 `HdrCapabilities.query`，P5 判定读取 `option-info/dovi-p5-fast-path/name`。
  - CI 的 `libmpv-jar-identity` job 增加 `dovi-p5-fast-path` 标识串校验。
- 验证：
  1. 单测：解析通道返回值，非法输入时得到 `displayHdrTypes == null`。
  2. LYA：库查询结果中的 displayHdrTypes 与 HEVC 解码器列表，与 hdr_lab `CapabilitiesChannel` 同时刻的输出逐项一致；DV 解码器列表如实记录（预期为空，记录实际值）。
  3. P5 探测正向：v2026.10 产品 JAR 返回 true。负向：上游 media-kit 原版 libmpv JAR（非 fork，需要下载并记录 SHA）返回 false。
  4. Mi Note 3（如在位）：displayHdrTypes 为空集。
  5. `HdrCapabilities.Changed`：LYA 无法实机触发，只做单测注入，证据缺口记录在案。
- 审核：V0。

### S3 路由规划（候选列表、偏好、成熟度门禁）

- 内容：
  - `HdrStrategy`、`HdrRoutingPolicy`（含 `defaults` = 需求 3.4）；
  - 成熟度常量表（与需求第 6 节一致，并用单测锁定两者同步）；
  - `HdrStrategyRealizer`（1.3 的映射表）；
  - `HdrRoutePlanner.plan`（1.3 的算法）；
  - `HdrCapabilities.predict` 只调用 planner。
- 验证（单测）：
  1. 默认偏好矩阵：每个源类别 × {无报告、空集、仅 HDR10、仅 HLG、HDR10+HLG、含 DV} × {P5 管线有/无} × {扩展适用/不适用} × {SDK 29/34}，断言选中策略、候选列表、跳过原因、置信度。
  2. **"先 HDR 后 tone-map"性质测试**：对所有输入组合，只要候选列表中存在可行、成熟度允许且呈现为 HDR 的策略，选中的就不能是 `toneMapSdr` 或 `sdrDirect`。
  3. 成熟度门禁：`allowExperimental=false` 时，实验性策略不会被选中，且出现 `experimentalStrategySkipped`；为 true 时可以被选中。`nativeDolbyVision` 在任何配置下都不会被选中。
     - **注记（2026-10-10）**：上句为 Phase 1 规划时的口径，已被两次成熟度更新取代——2026-10-06 DV P5/P8.4 类解锁为 `experimental`（开启 `allowExperimental` 可选中），2026-10-10 DV P5 × nativeDolbyVision 经用户裁决提升为 `verified` 并默认直通（无需 `allowExperimental`，见 `android-hdr-auto-output.md` 第 6 节状态表）。门禁机制本身（experimental 需显式开启）不变，单测按状态表现值断言。
  4. `excluded` 降级：PQ dataspace 被排除后，P8.4 从 `baseLayerConvert(PQ)` 跳到 `toneMapSdr`；HLG 不支持时，P8.4 从 `baseLayerDirect` 落到 `baseLayerConvert(PQ)`。
  5. 同源性：对同一组输入，`predict().selected.route` 必须等于 session 执行时 `plan()` 选中的路由，用表驱动遍历全部组合。
  6. LYA 的实际能力快照（S2 采集）代入后：HDR10→直出；P8.4→HLG 直出；P5→RPU 重建 PQ（有扩展时置信度 verified）；P8.1→直出（inherited）。
  7. 自定义偏好：App 覆写 P8.4 顺序、偏好设为 off，结果符合预期。
- 审核：V1（规划规则直接决定产品行为，并且是预测与执行的共同依据）。

### S4 dataspace 应用结果回报

- 内容：新增 `PlatformVideoView.ApplyDataSpace`，返回 `{applied, path, requested, readback}`，其中 path 取值 `ndk`/`surfaceControl`/`ext:<id>`/`none`。保留原 `SetColorSpace` 不变。
- 验证：
  1. 通道单测：覆盖各路径分支的返回结构。
  2. LYA + hdr_lab 注册扩展，开播 P5：`applied=true`、`path=ext:lya-pq`、`readback=DATASPACE_BT2020_PQ`，与 12703–12708 中 P5 轮的读回一致。
  3. LYA 不注册扩展，开播 P5：`applied=false`、`path=none`，并且没有私有 ABI 调用日志。
- 审核：V1。

### S5 会话编排（`HdrVideoSession` 与 coordinator、slot、backend 下沉）

- 内容：按 1.1/1.4 把 hdr_lab 的 coordinator、slot、backend、intent、disposal 移植进 `media_kit_video/lib/src/hdr/`。样片身份校验替换为 hint 加解码器复核，并加入候选降级、复核重建、播放中重建、偏好与策略切换、报告与事件。非 Android 平台透传。
- 验证（VM 单测，使用假 backend 和假 Player 属性）：
  1. 迁移用例：hdr_lab 的 `android_hdr_open_coordinator_test`、`output_slot_test`、`source_intent_test`、`disposal_test` 原样迁入并通过。
  2. 新增用例：
     - hint 与复核一致时零重建；
     - hint 错误时重建一次，位置被保留，报告的描述来源为 decoder；
     - 无 hint 时先 SDR，复核为 HDR 后重建一次；
     - 第二次复核仍不一致时不再重建，并报告实际情况；
     - dataspace 失败时沿候选列表降级到下一条 HDR 候选，再失败则落到 tone-map，播放继续，每一步都有事件；
     - hwdec 不符时把该环节排除后降级，并在原位置重开；
     - P5 管线缺失时发布 Error、不打开媒体；
     - 新 open 打断旧 open 时，旧代次报告不发布，属性被回滚；
     - open 过程中 dispose 时资源闭合；
     - 播放中切换偏好或策略配置，路由变化时在原位置重建，不变时不重建；
     - 能力丢失事件触发降级重建；能力恢复只发布事件。
  3. 原有 `media_kit_video` 测试全部通过。
- 审核：V1。

### S6 `HdrVideo` widget 与全屏跟随

- 内容：`HdrVideo` 用 `ValueListenableBuilder` 跟随 `session.controller` 变化，并通过 InheritedWidget 注入 session。内置全屏（`media_kit_video_controls/.../fullscreen.dart`）检测到 session 时，全屏页同样跟随替换。
- 验证：
  1. widget 测试：替换控制器后挂载的是新的 `Video`；全屏打开状态下替换，全屏页也换成新控制器；controller 为 null 期间显示占位。
  2. 实机部分并入 S10 的 A5 场景。
- 审核：V0。

### S7 设备扩展子包

- 内容：按 1.6 新建子包，从 hdr_lab 迁出 apply 路径（Java + C++），去掉探针。核心库不引用该子包。hdr_lab 改为依赖子包，并保留自己的探针扩展（诊断构建时链式包装子包扩展）。
- 验证：
  1. JVM 单测：注入 fingerprint/SDK 提供者，断言不匹配时 `isApplicable=false`、`applyDataSpace` 不调用原生方法；dataspace 不是 PQ 时直接返回 false。
  2. 符号审计：子包 `.so` 导出符号只有 apply 对应的 JNI（`nm -D` 留档）。核心 `media_kit_video_hdr_bridge.so` 仍然只有 4 个公开 JNI。
  3. LYA：依赖子包后自动注册，P5 播放时 `path=ext:lya-pq`，读回为 PQ。
  4. 非目标设备：不注册，logcat 中没有子包原生库加载记录。
- 审核：**V2**（私有 ABI 的安全门禁属于高影响不变量）。

### S8 诊断日志

- 内容：`HdrOutputDiagnostics.enabled`（默认 false），按 R4.3 分层输出单行日志。`HDR predict:` 和 `HDR decision:` 包含选中策略和全部候选及跳过原因。给出与 PiliPlusX `HDR decision:` 字段的对照表（写入主题 conversation）。
- 验证：单测断言默认关闭时不输出，开启后各层格式固定；实机日志见 S10 的 logcat。
- 审核：V0。

### S9 样片收集（可与 S1–S8 并行）

- 内容：收集 P8.1、P7（MEL 与 FEL 各一）、P8.2、纯 HLG 样片各至少一个，优先使用官方或可公开获取的测试片。记录来源、SHA-256，以及 `ffprobe` 得到的 DOVI 配置（profile、compat id、增强层标志），放入 `~/src/media-kit-build/sources/`。
- 验证：每个样片的 `ffprobe` DOVI 配置与预期 profile 一致，清单写入需求第 6 节的依据列。
- 审核：V0。缺样片不阻塞 Phase 1 主线，相应组合保持现有成熟度。

### S10 hdr_lab 迁移与实机验收（A1–A6）

- 内容：hdr_lab 的 01 页 HDR 路径改用 `HdrVideoSession`，以样片身份作为 hint。实验开关（模拟无 HLG、卸载扩展、错误 hint、自定义策略偏好）通过 `@visibleForTesting` 的能力覆写，以及公开的 policy/hint 参数注入。
- 验证（LYA，使用 `tool/` 下的轮次脚本，产物放 `~/src/media-kit-build/evidence/`）：
  1. **A1 矩阵复跑**：P5/P8.4/HDR10 × 默认策略，加 SDR 回归。对照 12703–12708 逐项核对 vo、hwdec-current、dataspace（路径与读回）、SF 图层格式、资源闭合计数；P5 和 HDR10 跑全片 EOS。
  2. **A2 预测一致性**：每轮开播前记录 `predict()`（选中策略和候选），开播后记录 report.actual，逐项比对。
  3. **A3 降级不停播**：三个注入场景（卸载扩展开播 P5；模拟无 HLG 开播 P8.4，预期落到 `baseLayerConvert(PQ)`；Mi Note 3 开播 HDR10），各自持续 ≥60s，确认 `time-pos` 持续前进、事件序列与候选降级路径相符。
  4. **A4 复核重建**：错误 hint（SDR→HDR10、HDR10→P8.4）和无 hint 各 3 轮。确认重建只有一次、位置偏差 ≤1s，并记录首帧时间。
  5. **A5 生命周期**：退出重入 ×5、Home→返回 ×3、全屏旋转（含全屏中切换偏好导致重建）、暂停 30s 后恢复、seek ×10、播放中 auto↔off 与策略切换。确认无 ANR/FATAL，Surface 释放 ACK 计数闭合，broker 无残留。
  6. **A6 策略偏好**：P8.4 开启 `allowExperimental`，把 `metadataReshape` 排第一，确认走 gpu-next RPU 重建 PQ、读回为 PQ、人工观察画面正确，并记录 GPU 负载和电池温度。默认配置复跑仍然是 HLG 直出。
  7. **成熟度升级轮**：对状态表中有样片的 experimental 或 inherited 组合（P8.4 baseLayerConvert、HLG/HDR Vivid baseLayerDirect、S9 收集到的 P8.1 等）各跑一轮：首帧、≥60s 持续播放、读回、人工观察。通过的组合在需求第 6 节和代码常量表中同步升级。
  8. **性能**：hint 命中时首帧三轮取中位数 ≤0.8s；重建与降级场景 ≤2.0s。4K60 对比在相同温度条件下进行（记录电池温度）。
- 审核：V1。证据整理成 `archives/experiments/android-hdr-auto-output-acceptance-<日期>.md`。

### S11 发布

- 内容：更新 `media_kit_video` 与新子包的 CHANGELOG/README（API 说明、默认偏好与成熟度表、迁移指南、扩展启用条件与失效表现），版本号递增，旧接口废弃说明。
- 验证：`flutter analyze` 0 error，`flutter test` 全部通过，发布 dry-run（或仓内引用方式）无报错。
- 审核：V0。

### S12 PiliPlusX 接入（PiliPlusX 仓，验收 A7–A8）

- 内容：
  - 删除 `hdr.dart` 中 Android 的拓扑与路由决策；
  - 选档前根据 DASH codec 和档位构造描述，调用 `predict`；
  - 用 `HdrVideoSession` 和 `HdrVideo` 替换现有 Android 视频挂载；
  - 展示 `report.actual`（策略和呈现类型）；
  - 按 App 自身策略处理 `Degraded`；
  - 删除 MainActivity 的 `probeHdrCapabilities`；
  - 增加每次播放 DV profile 的统计日志，为后续默认顺序和样片优先级提供依据。
- 验证：
  1. arm64 release 安装到 LYA，覆盖 A7 的四类样片，记录预测、路由报告、logcat 和截图。
  2. 注入降级后，确认 App 收到事件并按自身策略处理。
  3. **A8 diff 审查**：`git diff` 中 PiliPlusX 没有 fingerprint、SDK 判断、vo/hwdec 字面量或 Texture/PlatformView 选择代码；只允许出现策略偏好。
- 审核：V1。

### S13 收尾

- 内容：更新 `TASKS.md`（任务状态、证据入口），更新主题 conversation 的 Current State，需求第 6 节状态表同步到最终结论；hdr_lab 中冗余的旧适配层标记为已迁移或删除。另外登记两个后续任务：原生 DV（R7）和动态元数据重建（HDR Vivid/HDR10+）。
- 验证：所有引用路径可以打开，`TASKS.md` 验收项逐条对应证据文件，状态表与代码常量表一致（S3 单测守护）。
- 审核：V0。

### 依赖与并行

```
S0 → S1 → S3 ─┐
S0 → S2 ──────┼→ S5 → S6 → S8 → S10 → S11 → S12 → S13
S0 → S4 ──────┤
S0 → S7 ──────┘（S7 的实机项 3/4 放到 S10 一并执行）
S9 与 S1–S8 并行，结果在 S10 第 7 项使用
```

S1/S2/S4/S7/S9 涉及的文件互不重叠，可以并行。S5 起串行执行。

## 3. 实机纪律（每个实机步骤都适用）

- 设备 `3EP7N18C28016072`。先按 AGENTS.local 的方法唤醒，并用 `dumpsys power`/`dumpsys window` 核验已唤醒。
- 构建使用 JDK17（`JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home`），产品 JAR 通过 `ORG_GRADLE_PROJECT_mediaKitLocalArm64Jar` 注入。
- 只在人工观察画面时短时调到最高亮度。每轮结束后恢复原 12492 包、自动亮度并熄屏。
- 证据分三类记录：设备读回、日志、人工观察。构建或安装成功不能当作端到端验收。

## 4. 风险与对策

| 风险 | 对策 |
|---|---|
| 成熟度门禁过严，导致可行的 HDR 被降成 tone-map | 引入 `inherited` 等级（同机制继承）；S3 性质测试守护"先 HDR 后 tone-map"；跳过时报告 `experimentalStrategySkipped` |
| 成熟度表与文档不同步 | 代码常量表为准，S3 单测比对需求第 6 节；S10 升级时两处同步修改 |
| 复核重建或候选降级造成首帧回退 | hint 优先，要求 PiliPlusX 始终传入描述；每代次最多一次重建、最多再试一条 HDR 候选；S10 单独度量 |
| 全屏页持有旧控制器 | S6 让全屏跟随替换，S10 验证全屏中重建 |
| 私有 ABI 在非目标设备被调用 | 默认关闭、精确匹配、只读门禁，不适用时不加载 `.so`；S7 走 V2 审核 |
| 只有一台 HDR 设备 | 预测置信度标 `unverified`；新设备接入先跑现有矩阵 |
| RPU 重建或 GPU 转换增加发热 | 实验性组合验证时记录负载与温度；默认顺序中直出优先 |
| 增强层或动态元数据无法从 mpv 取得 | S1 评估；取不到时按 null/none 处理，P7 只允许基础层直出，需要改 fork 的单列后续任务 |
| P5 选项代理在 fork 同步时改名 | CI 标识串校验加入该选项名；长期在 fork 中提供专门属性 |
