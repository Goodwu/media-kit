# HDR 能力查询、路由执行与报告（PiliPlusX 需求，2026-10-02 起）

## Current State

- **实施推进中（2026-10-02 第二轮开工）**：S0 基线冻结完成，S1/S2/S4/S7/S9 并行推进，然后 S3。每步完成即更新本节并提交。
- **并行批预备**：`SurfaceDataSpaceExt` 已先行加 default `id()`/`isApplicable()`（S2 与 S7 共同依赖，避免并行写冲突；S2 验证覆盖、S7 消费）。S2 与 S4 都改 `MediaKitVideoPlugin.java`/`PlatformVideoView.java`，按计划"同文件串行"合并为同一 worker 串行实施、分步提交；其余按计划并行。
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
