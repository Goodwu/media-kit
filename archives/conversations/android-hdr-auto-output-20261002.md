# HDR 能力查询、路由执行与报告（PiliPlusX 需求，2026-10-02 起）

## Current State

- **实施推进中（2026-10-02 第二轮开工）**：S0 基线冻结完成，S1/S2/S4/S7/S9 并行推进，然后 S3。每步完成即更新本节并提交。
- **并行批预备**：`SurfaceDataSpaceExt` 已先行加 default `id()`/`isApplicable()`（S2 与 S7 共同依赖，避免并行写冲突；S2 验证覆盖、S7 消费）。S2 与 S4 都改 `MediaKitVideoPlugin.java`/`PlatformVideoView.java`，按计划"同文件串行"合并为同一 worker 串行实施、分步提交；其余按计划并行。
- **S1 源描述与分类完成（2026-10-02 第二轮，V0）**：`HdrSourceDescriptor`/`HdrDynamicMetadata`（需求 3.1 七字段）、`HdrSourceClassifier`（计划 1.5 表；事实优先，hint 仅补 codec；兼容 ID 由基础层 gamma 推断 pq→1/hlg→4/SDR→2，P5→0，P7→6）；`classifyMedia` 委托分类器取 kind，`'5'`/`'8.4'` 字符串分支保留兼容旧 hint；kind 推导固定：P5→P5、P8.1/P7→hdr10、P8.4→P84、P8.2→sdr、P10 与 P8 未知 compat 按基础层 gamma。hdr_output_policy_test 11 项（P8.4 用例改整数输入）+ hdr_source_classifier_test 17 项；media_kit_video 全套 **79/79 通过**。整数缺陷修复已单测覆盖：`8`+hlg→dolbyVisionP84。S1 已提交 `d48fc08c`。
- **S3 路由规划完成（2026-10-02 第二轮，V1 PASS）**：`HdrStrategy`/`HdrStrategyMaturity`/`HdrSourceClass`（11 类，of(descriptor) 推导）+ 66 格成熟度常量表（33 文档格由解析单测逐格锁定，27 格保守 experimental、5 格 nDV=unsupported、sdr×sdrDirect=verified 为文档外白名单例外）；`HdrRoute`/`HdrCandidate`/`HdrRoutePrediction`/`HdrDegradeReason`（新增 `unsupportedStrategy`、`p5PipelineUnavailable` 两值，R3.2 为"至少"列表）；`HdrStrategyRealizer`（1.3 映射表，convert 优先 PQ；与 decide 已验证组合逐字段一致）；`HdrRoutePlanner.plan`（1.3 算法，兜底绕过门禁兑现 R3.1 不停播，P5 无管线 playable=false）；`HdrCapabilities.predict` 纯委托 plan（同源）。矩阵 462 组合/门禁双态、性质测试 308 组合、同源 924 组合、LYA 快照（HDR10→direct、P8.4→HLG direct、P5→reshape verified、P8.1→direct inherited）全部断言；全套 **118/118**。**V1 Reviewer PASS**（4 条建议已由 Lead 闭合：矩阵补含 DV 显示集 {1}/{1,2,3}、LYA 组补 toneMapSdr bt.709/bt.1886 断言、excluded-after-realize 边角注释、S3 与 hdr_lab 探针拆分提交；reviewer 做了 4 组变异验证确认测试可捕获回归）。
- **S5 会话编排完成（2026-10-02 第三轮，V1 PASS）**：hdr_lab 的 coordinator/slot/backend/intent/disposal 下沉进 `media_kit_video/lib/src/hdr/`（串行副作用队列/代次失效/回滚/属性写读回恢复/vf/P5 事务性默认值语义与原版逐行一致；样片身份整体移除）；新增 `HdrVideoSession`（1.4 九步流程、每代次最多一次复核重建+最多再试一条 HDR 候选、dataspace 只认 applied 判门禁、报告只对应当前代次）、五类事件流、R4.2 报告；`HdrCapabilities.Changed` 经共享通道转发进 session；非 Android 透传 unsupportedPlatform；旧 `HdrOutputReport` 改名 `HdrTransactionReport`（darwin/OHOS 内部，未导出过公开面）。迁移测试 32（coordinator 14/slot 10/intent 3/disposal 5）+ 会话新用例 11，全套 **161/161**。
  - **实施曲折**：第一个 worker 实施中因供应商流错误崩溃（移植层+类型层已完成）；第二个 worker 核对遗留代码后修复 session 的 24 个编译错误与 3 个语义问题（P5 阻断不走候选重试、能力变化重建用触发快照、绑定超时排除 topology:platformView）。
  - **V1 Reviewer PASS**（4 建议）：①`hdr_open_plan.dart` 补进 barrel（错误对象可命名，已修）；②`HdrCapabilities.Changed` enable 是共享开关，多 session 会互相关闭——Phase 1 单会话约束已注释声明（已修）；③重建代次报告保留触发降级原因（`_stagedDegradeReason`，已修+测试断言）；④不可映射后端异常统一标 `unsupportedStrategy` 语义偏宽——接受现状（diagnostic 携带 error.toString()），后续可补 `openFailed`。审核确认 1.4 九步全落点、代次纪律无窗口期、迁移用例数与 lab 原版逐名核对（lab 16/9/3/4 → 库 14/10/3/5，删 4 条纯 staging 用例、新增 4 条扩展/库场景用例）。
  - **计划内偏差（记录）**：coordinator 样片 staging 机制随样片身份整体移除，lab 的 4 条 staging 专用测试未迁入（staging release×2、cleanup failure、dispose 期间 staging 清理）；其 dispose 语义由迁移的 disposal 测试继续覆盖。
- **S10 代码迁移完成（2026-10-02 第四轮，实机验收待执行）**：hdr_lab 01 页 HDR 路径整段换 `HdrVideoSession`（旧 coordinator/slot/intent/私有样片拷贝调用全移除，旧源文件留待 S13 清理）；`HdrVideo` 挂载（全屏跟随自动获得）；hint 按受控样片枚举经 `fromKind` 构造（P5/P8.4/HDR10/HLG/SDR 对照）；实验开关：`MEDIA_KIT_ANDROID_HDR_SIMULATE_NO_HLG`（capabilitiesProvider 过滤 type 3，经 forTesting 注入——计划原文许可的 @visibleForTesting 覆写）、`HDR_WRONG_HINT=sdr|hdr10|p84`/`HDR_NO_HINT`（A4）、`HDR_POLICY_EXPERIMENTAL`（A6）、`HDR_PREFERENCE_SWAP_AT_SECONDS`/`HDR_POLICY_SWAP_AT_SECONDS`（A5）、`hdrLabUnregisterVendorExt` 保留；新增证据面 `HDR_SESSION_REPORT/PREDICTION/CANDIDATE/ACTUAL/EVENT`（A2 预测一致性逐项比对）+ 可选 `MEDIA_KIT_ANDROID_HDR_DIAGNOSTICS` 库七层日志；MPVPROP/HDR_CAP/ApplyDataSpace 直发探针保留。hdr_lab analyze 0、测试 48/48、库 183/183；release 构建 `a2e45ccaa05f4109`。**库 API 缺口记录**：`HdrOpenCoordinator.onPhase` 逐相耗时未从 session 暴露（ANDROID_HDR_OPEN_PHASE 无法等价迁移，A1–A6 证据由会话报告+事件覆盖）；`HdrDisposalReport` 未进 barrel（页面不命名类型，无阻塞）。
- **S10 实机验收进行中（2026-10-02 第四轮起，LYA 串行设备轮，全部按纪律恢复）**：
  - **A1 矩阵复跑**（对照 12703–12708）：P5=metadataReshape PQ（gpu-next+ext:lya-pq，全片 EOS completed=true@99s，零渲染失败，frame-drop 与基线相当）✓；HDR10=baseLayerDirect mediacodec_embed PQ（全片 EOS completed=true@304s）✓；**P8.4 首轮抓到 S5 复核时序缺陷**（见下）修复后复跑=baseLayerDirect HLG 直出 mediacodec_embed、零重建、SF 层 `BT2020_ITU_HLG (302383104)` ✓；HLG=DVS graypatch 默认门禁落 toneMapSdr 兜底（预测==实际，candidates 全 experimentalStrategySkipped，符合成熟度表，零重建）✓；SDR 回归=Texture gpu-next/mediacodec 行为同 12703 ✓。
  - **S5 复核时序缺陷（已修复）**：首次复核在 video-params 到达前执行（facts 仅 profile=8、gamma=null）→ 分类器保守落"P8 未知 compat"→ 重规划 toneMapSdr 烧掉唯一重建；真实 hlg 事实到达后预算已耗尽，最终停在 tone-map。修复：backend `gatherReviewFacts` 对 video-params 有界轮询（50ms 节奏共享 8s 预算、media 身份校验、换源清缓存），超时如实返回；新增迟到参数与超时两条 VM 用例（185/185）。
  - **A3 降级不停播**：①卸载扩展开播 P5——两级 DegradedEvent（metadataReshape→toneMapSdr，diagnostic=initialDataSpaceRejected），Texture 续播 98.7s 近全片、无私有 ABI 日志；degrade reason 为偏宽的 unsupportedStrategy（V1 已接受现状，diagnostic 精确）；②模拟无 HLG 开播 P8.4（能力覆写 before={2,3} after={2}）——计划相跳过 direct，落 baseLayerConvert(PQ)（gpu-next、stripRpu=true、SF 层 `BT2020_PQ (163971072)`、库读回一致），续播 97.9s；③Mi Note 3 不在位（缺口记录）。注：no-HLG 情形属计划相跳过（candidates 携带 displayLacksTransfer），发布的是 RouteApplied 而非 Degraded——R3.1"发布对应事件"以报告候选跳过原因兑现，已在证据中说明。
  - **新增验收开关**：`MEDIA_KIT_ANDROID_HDR_GATE_OPEN`（A3 专用：门禁开+默认序，与 A6 的 reshape 置顶区分）。
- **S10 实机验收完成（2026-10-02 第四轮，26 轮，证据 `archives/experiments/android-hdr-auto-output-acceptance-20261002.md` + `~/src/media-kit-build/evidence/hdr-auto-output-acceptance-20261002/`）**：A1 五轮与 12703–12708 逐项一致（P5/HDR10 全片 EOS）；A2 五轮预测==实际；A3 两注入 ≥60s 不停播（hwdecMismatch 降级链顺带两次实证；Mi Note 3 缺口）；A4 九轮均恰好一次重建、位置保持、终态路由正确；A5 无 ANR/FATAL、Surface release/ACK 1:1 闭合、播放中偏好/策略切换×3；A6 自定义偏好看效（RPU 重建 PQ + SF/读回一致）且默认配置不变；hint 命中首帧中位 **455.8ms ≤800ms**。升级轮：P8.4 convert 与 HLG direct 证据完整**待人工观察**后升级 verified（需求第 6 节未动）；P8.1 升级确认受样片阻塞（公开仅 10 帧 FATE 样片，复核窗口 hwdec 不稳定）；A6/A4 过程中修复 S5 复核时序缺陷（video-params 有界轮询）。库测试 185/185。
  - 下一步：S10 V1 审核 → 用户人工观察确认升级 → S11 发布 → S12 PiliPlusX 接入 → S13 收尾。
- **S8 诊断日志完成（2026-10-02 第三轮，V0）**：`HdrOutputDiagnostics`（默认关闭零输出，enabled 短路；printer 可注入便于测试，生产 debugPrint，tag `HdrDiag`）；七层挂接：capability（query 完成）/predict（planner.plan 返回处，纯函数内静态 emit，关闭时仅一次布尔判断）/classify/classify 后/readback（dataspace 应用后、失败门禁前，失败也留痕）/decision（session 计划相+applied 相，双相各带全候选+跳过原因+代次）/degrade（Degraded 事件）/recover（CapabilityChanged）。诊断测试 17 条（默认关闭硬要求、各层 golden 字段集与顺序、predict/decision 含 unsupported 与 experimentalStrategySkipped 全候选）。全套 **183/183**。
  - **与 PiliPlusX `HDR decision:` 字段对照表**（其源码 `lib/plugin/pl_player/controller.dart:2232` 实测；库 decision 层单行格式 `phase=plan|applied gen=N origin=hint|facts source=<描述符七段,逗号连接> class= selected= maturity= presentation= confidence= vo= hwdec= output= topology= surface= stripRpu= hwdecCurrent= requested= path= readback= verified= degrade= candidates=<策略:原因,…>`）：
    - `source`（kind.name）→ `source=`（描述符摘要）+`class=`（HdrSourceClass）
    - `primaries`/`transfer` → `source=` 摘要第 3/2 段
    - `dvProfile` → `source=` 第 5 段（5/8/7/10，无 DV 为 none）
    - `dynamicMetadata` → `source=` 第 4 段（dolbyVision/hdrVivid/hdr10Plus/none）
    - `el` → `source=` 第 7 段（false/true/none=未知）
    - `output` → `output=`；`surface` → `surface=`（dataspace 请求）+`requested=`/`path=`/`readback=`（S4 四元组，比原 surface 字段多了生效路径与读回）
    - `vo`/`hwdec` → `vo=`/`hwdec=`；实测 hwdec 另有 `hwdecCurrent=`
    - `reason` → `degrade=` + `candidates=` 各候选跳过原因（比原单一 reason 细化到每候选）
    - `matrix`/`rpu`/`dvEnhancement` → 库不产：matrix 未进描述符（mpv colormatrix 未接）；rpu 的决策面体现为 `stripRpu=`；dvEnhancement 无对应（FFmpeg DOVI 记录未暴露，S1 评估已列 fork 改造项）
    - 库新增无对应：`phase`/`gen`（代次）/`maturity`/`presentation`/`confidence`/`topology`/`verified`
    - PiliPlusX 的 `observed(...)` 三态（observed 值/none/unknown）在库 source 摘要里统一为值/none 两态
  - **实施曲折**：worker 因供应商网络错误中断一次，遗留实现+大部分测试由 Lead 收尾：修测试桩 `show` 子句缺 `AttemptScript`、`keysOf` 分词下标（layer 词带冒号）、decision 计划相期望串用错源类别（场景 hint 是 hdr10）、recover 首行是丢失快照（空集渲染 none）而期望写成恢复值、dataspace 语义用例期望 surface=pq 与 S3 realizer 矛盾（HLG-only 屏 convert 正确输出 HLG，实现无误、期望修正）。
- **S6 HdrVideo widget 与全屏跟随完成（2026-10-02 第三轮，V0）**：`HdrVideo`（参数与 Video 逐一对齐，controller 换 session）+ `HdrVideoScope` 注入 + `HdrVideoBody` 共享挂载点（ValueListenableBuilder 跟随 session.controller，null 占位）；内置全屏页检测 `HdrVideoScope.maybeOf`，有 session 时 `FullscreenVideoSurface` 跟随替换、无 session 时 `buildFullscreenVideo` 闭包逐参数保留历史静态行为（回归测试锁定 push 时捕获的同一控制器）；非 Android 上 HdrVideo 即透传显示层。widget 测试 5 条（替换换挂/全屏跟随/null 占位/非 session 回归/scope 可见性），全套 **166/166**，analyze 0 error。实机部分（全屏中重建）按计划并入 S10 的 A5。
- **实机轮准备（2026-10-02，提交 99601a48）**：hdr_lab 无扩展验证开关（`-P hdrLabUnregisterVendorExt=true`→BuildConfig→configureFlutterEngine 末尾注销扩展）；探针构建脚本 `tool/hdr-auto-probe-build.sh`；HLG fixture 推送 `/data/local/tmp/media-kit-hlg-vivid-4k.mp4` 与 DVS 纯 HLG fixture `media-kit-hlg-dvs-graypatch50.mp4`；上游非 fork JAR `~/src/media-kit-build/jars/upstream-predidit-v127-arm64.jar`（Predidit/libmpv-android-video-build v1.2.7，SHA-256 `13e882d9…`）。
- **实机探针轮完成（2026-10-02，LYA 3EP7N18C28016072，共 7 轮全部按纪律恢复 12492 包/自动亮度/熄屏）**。证据持久化 `~/src/media-kit-build/evidence/hdr-auto-output-probes-20261002/`（设备日志+构建日志；APK SHA 前 16：hdr10-facts `8ed236ed…`、p84-facts `fea9dfcd…`、hlg-facts `d57327cd…`、hlg-dvs-facts `da410b10…`、p5-combo2 `d17d7e61…`、p5-negjar `f4578f40…`、p5-noext `de62bf60…`；构建脚本 `tool/hdr-auto-probe-build.sh`）。
  - **S1 事实核对（Texture SDR 轮，MPVPROP 实测）**：HDR10 样片 profile 空+gamma pq+primaries bt.2020→hdr10；P8.4 样片 `dolby-vision-profile=8`（整数，缺陷在真机复证）+gamma hlg→P8.4；P5 样片 profile=5+gamma pq→P5；DVS 纯 HLG profile 空+gamma hlg→hlg。已固化为锚点测试 `hdr_source_classifier_device_facts_test.dart`（6 用例，全套 85/85）。
  - **事实冲突（不改需求，已汇报）**：需求第 6 节 HLG 行注"本地 `HDR Vivid_HLG` 可用作基础层"——实测该文件（`4K HDR (HDR Vivd_HLG).mp4`）解码上报 gamma=**pq**/primaries bt.2020（ffprobe 证 smpte2084/bt2020），基类是 HDR10 兼容层而非 HLG；纯 HLG 事实轮改用 S9 的 DVS 样片完成。HDR Vivid 动态元数据 mpv 不可观测（与 S1 评估一致），该样片分类为 hdr10。
  - **S2 能力查询（同刻三源对比）**：sdkInt=29、displayHdrTypes=[2,3]（HDR10+HLG、无 DV）lab 通道与库通道**逐项一致**；库通道 HEVC 解码器 4 项（OMX.hisi.video.decoder.hevc 主10 位 main10=true、supports4K=true、max4KFps≈34.2，另 hisi.secure/c2.android/OMX.google），与既有 OMX.hisi 事实吻合；`dolbyVisionDecoders=[]` 如实；`dataSpaceBridgeLoaded=true`、`dataSpaceExt={id: lya-pq, applicable: true}`（子包自动注册+诊断包装委托 id）。**P5 探测正向**：产品 JAR v2026.10 → `p5Pipeline: true`；**负向**：上游非 fork JAR（Predidit v1.2.7，SHA `13e882d9…`）→ `p5Pipeline: false`。Mi Note 3 不在位（displayHdrTypes 空集验证缺实机，记录缺口）；`HdrCapabilities.Changed` 无实机触发手段（计划已预期，单测注入为准）。
  - **S4 dataspace 回报**：有扩展（p5-combo2，12704 组合）→ `ANDROID_APPLY_DATASPACE transfer=pq report={path: ext:lya-pq, requested: pq, applied: true, readback: DATASPACE_BT2020_PQ}`，与 12704 世代私有 ABI 读回（perform=0，actual=163971072=BT2020_PQ）一致；无扩展（p5-noext，`-P hdrLabUnregisterVendorExt=true`）→ `{path: none, requested: pq, applied: false, readback: none}`、**无私有 ABI 调用日志**、能力查询 `dataSpaceExt: null`。S4 验证 1/2/3 全部闭合。
  - 其余读回：P5 综合轮 vo=gpu-next/hwdec=mediacodec（与 12704 一致）、零渲染失败、资源闭合。
- **S1 可得性评估结论（fork HEAD 5f9ddf1777 / FFmpeg fff3ee7a3e，n7.1.3 基底）**：
  - **能直接读取**：DV profile/level（`current-tracks/video/dolby-vision-profile|level`，已接入）；HDR10+ 经 fork 的 `pl_map_hdr_metadata` 映入 `video-params` 子属性 `scene-max-r/g/b`、`scene-avg`（首个解码帧后可读，逐帧性需保守处理——个别帧缺失会误报 none；适合 R2.3 复核时机，不适合开播前 hint）。
  - **需改 mpv fork（单列后续任务）**：DV 兼容 ID 与增强层标志——数据已在 fork 内解析（MKV `demux_mkv.c:782-830` 挂 AV_PKT_DATA_DOVI_CONF；MP4 `demux_lavf.c:764-770` 只取 profile/level），只差暴露：stheader.h 加字段 + demux_mkv/demux_lavf 复制 + command.c 轨道属性表加 `dolby-vision-compatibility-id`/`dolby-vision-el-present`；配置记录不区分 FEL/MEL。HDR Vivid：FFmpeg 7.1 已有 `AV_FRAME_DATA_DYNAMIC_HDR_VIVID`，fork 零引用，需 `mp_image_from_av_frame` 读取 + 属性暴露，需实机确认样片产出该 side data。
  - **取不到（按 null/none）**：FEL/MEL 区分；HDR10+/HDR Vivid 在 fork 改动前 `dynamicMetadata=none`；P7 增强层 `null`。
  - 实施注意事项（S3/S5）：pubspec SDK 下界 2.17，records/patterns/switch 表达式不可用；`VideoParams` 不携带 codec，S5 复核时应把 `current-tracks/video/codec` 经 hint 通道带入。
- **并行批 S2/S4/S7/S9 代码完成（2026-10-02 第二轮）**：
  - **S2 原生能力查询与 P5 探测**：`HdrCapabilities.Get/Changed`（MediaKitVideoPlugin + 新 HdrCapabilities.java，sdkInt/displayHdrTypes/HEVC 档位与 4K 帧率/DV 解码器如实查询/bridge/ext id+适用性；不触 EGL、不触私有 ABI）；Dart `HdrCapabilities.query`（P5 判定 `option-info/dovi-p5-fast-path/name` 非空，选项名在 mpv fork `vo_gpu_next.c:222` 核实，与 rescale 同提交 5f9ddf1777）；CI `libmpv-jar-identity` 增加 `dovi-p5-fast-path` 标识串。测试 hdr_capabilities_test 13 项。
  - **S4 dataspace 应用结果回报**：`PlatformVideoView.ApplyDataSpace` 返回 `{applied, path∈ndk/ext:<id>/surfaceControl/none, requested, readback}`；`SetColorSpace` 语义零改动；Dart 入口 `AndroidVideoController.invokeApplyDataSpace`。测试 platform_video_view_dataspace_report_test 6 项。**V1 Reviewer PASS**（4 建议）：①surfaceControl 路径 applied 走 SF 图层态、readback 走 buffer 侧，两者不同源——S5 判 `dataSpaceReadbackMismatch` 须对该路径豁免（已在 javadoc/dartdoc 写明）；②多 live view 的代表报告取迭代末项，S5 只应以 applied 作门禁、path/readback 作诊断；③私有 setColorSpace 的 path 传递改为返回值（已修复，删除 lastAppliedDataSpacePath 字段）；④`DATASPACE_BT2020_PQ_LIMITED`（0x11c60000，即 pq-itu）为库内自造名，对照 SF 证据时即 BT2020_ITU_PQ。readback 与 applied 相互独立，S5 以 applied 判门禁。
  - **S7 设备扩展子包**：`libs/android/media_kit_android_dataspace_vendor/`（LyaPqDataSpaceExt：只读门禁 SDK==29+精确 fingerprint+仅 PQ，幂等懒加载，不适用零加载；插件 onAttachedToEngine 先 isApplicable 再注册；native 侧二次防御门禁+perform 19+读回校验，单 JNI 导出）；hdr_lab 改依赖子包，探针留在 LyaDiagnosticsDataSpaceExt（apply 委托、id 委托保持 ext:lya-pq），MainActivity 经 takeOverSlot 交接槽位。JVM 测试 8 项；符号审计：子包 .so 仅 1 个 apply JNI、核心 bridge 仍 4 个 JNI、p5_probe 无 apply 符号（/tmp/symbol_audit/ 留档）。**V2 Critical Reviewer PASS**（3 建议）：①核心单静态槽无所有权查询，多 engine 同进程先 detach 方会误清后注册方的槽（受门禁 containment）——S5/S11 考虑槽所有权只读查询；②JVM 幂等断言补齐（已修复：重复 apply 断言 loadCalls==1）；③子包 JVM 单测接入 CI hdr-lab-analyze（已修复）。
  - **S9 样片收集**：6 样片入 `~/src/media-kit-build/sources/`，清单与 ffprobe DOVI 配置在 `SOURCES.md`：P8.1（FATE dovi-p81）、P7 FEL×2（FATE，其一为 Blu-ray 式分轨 dvcc 挂 EL 轨）、P7 MEL（FEL 派生合成）、P8.2（合成，真实 SDR BL+dvvC compat 2）、纯 HLG（DVS graypatch50 4K60）。**缺口：真实 P8.2 与 P7 MEL 公开样片不存在**（FATE/官方渠道均无），合成替代已标注局限；LaLaLand/Passengers 等商业片段按版权排除。
  - hdr_lab 实机探针已加（2026-10-02）：测试页新增 `HDR_CAP_LAB`/`HDR_CAP_LIB_CHANNEL`/`HDR_CAP_QUERY`（含 P5 选项探测）与 `ANDROID_APPLY_DATASPACE` 四元组日志；待办：S1（后台实施中）→ 提交 → LYA 三轮实机验证（S1 分类事实/S2 能力对比/S4 dataspace 回报）→ S3。
- **S0 基线冻结（2026-10-02，V0）**：
  - 基线提交：`f42d39ec`（需求 v3 定稿）；media-kit `main` 单线。
  - 产品 JAR：发布源 `libmpv-android-v2026.10` / `media-kit-5f9ddf17-arm64-v8a.jar`，SHA-256 `c0e5d7f0fbca11767b28f030d3d81bef01c5c2295adaf820b2f9d4d8441db9ea`（钉定于 `libs/android/media_kit_libs_android_video/android/build.gradle:68`；本地构建目录无副本，构建时按 SHA 校验下载）。
  - hdr_lab 构建参数：applicationId `com.example.media_kit_hdr_lab`；minSdk/targetSdk/compileSdk/ndk 随 Flutter 默认（`flutter.minSdkVersion` 等，仓库层 minSdk 21）；`abiFilters += "arm64-v8a"`；产品 JAR 经 `ORG_GRADLE_PROJECT_mediaKitLocalArm64Jar` 注入（`libs/android/media_kit_libs_android_video/android/build.gradle:83`），JDK17（`/opt/homebrew/opt/openjdk@17`）。
  - 测试基线（Flutter 3.47.2 stable）：`media_kit_video` `flutter test` **43 通过**（其中 `hdr_output_policy_test` 11 项）；`media_kit_hdr_lab` `flutter test` **48 通过**。两包零失败，作为后续回归基线。
- **2026-10-02 需求定稿 v3，实施计划同步修订（S0–S13）**。需求：`docs/requirements/android-hdr-auto-output.md`；计划：`docs/requirements/android-hdr-auto-output-plan.md`。
- **v3 新增（用户决策）**：
  - 同一类源有多种处理方式时，由"源描述 + 策略候选列表 + 偏好配置 + 成熟度门禁"决策。策略分为 nativeDolbyVision（预留）、baseLayerDirect、baseLayerConvert、metadataReshape、toneMapSdr、sdrDirect。
  - **默认偏好：硬件支持时先 HDR 输出，再 tone-map；HDR 输出中直出优先**。
  - 为避免成熟度门禁把可行的 HDR 降成 tone-map，引入 `inherited` 等级：P8.1 直出继承 HDR10 直出，依据是 P8.4 直出已证明 LYA 的 HEVC 解码器能容忍 RPU。
  - 运行时降级沿候选列表查找，最多再试一条 HDR 候选。
  - 原生 DV 只预留，另立需求：FFmpeg mediacodec 只用 `video/hevc` 打开解码器，整条链路没有原生 DV 路径。
  - 框架按"动态元数据格式 × 策略"设计，覆盖 HDR Vivid 和 HDR10+。
  - 样片缺口：P8.1、P7、P8.2、纯 HLG。
- **职责边界（用户决策）**：片源与显示能力是否一致由 PiliPlusX 负责。media-kit 只做三件事：开播前预测（可否原生呈现、预测路由）、执行路由、报告实际路由与事件。HDR 不可呈现时库以 tone-mapped SDR 继续播放，并发布降级事件，不主动停止；何时换源由 App 决定。路由信息返回给 App，供展示播放信息。
- **评审中确定的设计要点**：
  - auto 编排放在高于单控制器的会话对象（`HdrVideoSession` 加 `HdrVideo` widget）中，不放进 `VideoControllerConfiguration`，因为 `usePlatformView` 在创建期已固定，切换拓扑只能替换控制器；内置全屏在 push 时捕获控制器（`fullscreen.dart:37`），必须改为跟随替换。
  - 预测与执行同源，都走同一个 planner（包装 `HdrOutputPolicy.decide`）。
  - P5 管线运行时判定用 `option-info/dovi-p5-fast-path`。这个选项与 `dovi rescale k=` 标记都在 mpv `5f9ddf1777` 引入，只会把较早的 fork 世代误判为不可用，不会把不可用的构建误判为可用。
  - LYA 私有回退做成同仓独立子包：默认关闭，只读门禁（SDK29 + 精确 fingerprint + PQ），不适用时不加载 `.so`，诊断探针留在 hdr_lab。
  - Phase 2（darwin/OHOS）另立需求。
- **已核实的库缺陷（S1 修复）**：mpv `dolby-vision-profile` 是整数属性（`player/command.c:2102` `SUB_PROP_INT`），取值 `5`/`8`；`classifyMedia` 匹配 `'8.4'`，用真实解码器值时 P8.4 会误分类为 `hlg`。hdr_lab 依赖样片身份，所以没有暴露（`android_hdr_player_backend.dart` verifyTrack 期望值为 `'8'`）。
- **边界例外**：P5 管线缺失时，tone-map 也无法正确着色，库发布 `p5PipelineUnavailable` 错误、不开播，不输出错误着色画面。
- **证据缺口（已写入需求第 7 节）**：只有 LYA 一台 HDR 实机，API 30–33 公开 NDK 路径与 API≥34 SurfaceControl 路径没有实机证据，对应预测标为 `unverified`；LYA 无系统 HDR 开关，能力变化事件只能单测注入。

## 历史

### 2026-10-02 需求评审与修订

- PiliPlusX 提交 v1 需求。media-kit 侧核实了引用的事实（P0-1 批次C 私有 ABI 迁出、`HdrOutputPolicy` 11 项单测、PiliPlusX `hdr.dart:518-524` 只认 HCPP 且要求 API≥34），全部属实。
- 首轮评审意见：API 放置位置有误；以日志标识串作为运行时探测不可行（它只是 CI 构建期校验）；私有 ABI 缺少失败安全要求；只有一台设备做验收；Phase 2 应拆出；`HdrOutputMode` 重名；重建首帧没有预算。
- 用户补充一：PiliPlusX 需要按设备能力决定是否请求 HDR 源，请求了 HDR 却 tone-map 播放，对 App 是错误行为。由此确定库必须提供开播前预测，并且预测与执行同源。
- 用户补充三：询问其他设备直接渲染 DV 的可能。核实结论是现有链路没有原生 DV 路径，决定只预留、另立需求。用户补充四：DV 有多种 profile，同一 profile 有多种处理方式，需要按配置决策；默认偏好在倾向直出的同时，硬件支持时要优先 HDR 输出而不是 tone-map。据此修订为 v3。
- 用户补充二（职责边界决策）：路由信息返回给 App；HDR 不可呈现时 tone-map 继续播放并报告事件，不主动停止，由 App 决定何时换源；片源与能力一致是 App 的需求，media-kit 只报告。据此把需求修订为 v2，并编制实施计划。
