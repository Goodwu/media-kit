# HDR 能力查询、路由执行与报告（PiliPlusX 需求，2026-10-02 起）

## Current State

- **实施推进中（2026-10-02 第二轮开工）**：S0 基线冻结完成，S1/S2/S4/S7/S9 并行推进，然后 S3。每步完成即更新本节并提交。
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
