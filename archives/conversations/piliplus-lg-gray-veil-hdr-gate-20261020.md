# PiliPlus LG 灰蒙修复与 HDR 会话门控（2026-10-20 白天轮）

> **后续更正（2026-10-21）**：以下为保留的历史实验记录，灰屏归因与部分实验代码已撤回。真正灰层是 PiliPlus 字幕 Obx 异常产生的 Release ErrorWidget，修复后用户已确认画面和控件正常。最新状态及清理审计统一见 `/Users/wuweiwei1/src/PiliPlus/archives/conversations/video-gray-getx-20261021.md`。

## 目标（用户提出）
1. 视频蒙了一层灰色 —— 修复。
2. 所有具备 HDR 能力（DV/HLG/PQ）的面板必须解码并激活 HDR 显示；符合条件的设备采用 tone-map 不可接受。

测试设备（在线 adb）：LG H870DS（lucye，Android 7.0/API 24，Adreno 530，Dolby Vision+HDR10 面板）。
样片：BV1T7t96BECu（SDR h264 720p）、BV1vY4y1N7TY（4K DV P8.4）、BV1uZ4y1U7h8 / BV1WPNh6zEcx（DV P8.4 1080p）。
注意：普通 `adb shell logcat` 在该机不返回数据，必须 `adb exec-out logcat`。

## 结论

### 1. 灰蒙（已修复，实机四样片全彩验证）
- 症状定量化：会话（HdrVideoSession/RoutedVideoPlayback）的纹理输出在屏幕上呈现
  luma 181–196、饱和度≤15 的近均匀灰场；增强后可见清晰全分辨率画面结构 —— 即
  画面 ≈ 0.06×帧 + 0.94×灰(≈191)。同 app、同 media-kit、同 mpv JAR 下 legacy
  VideoController 路径输出 luma 3..240、饱和度 197（完全正常）。
- 逐层排除（每项均有实机 A/B 证据，/tmp/pili-gray-20261020/）：
  vo（gpu/gpu-next 均灰）、全部会话 owned mpv 属性运行时翻转（hwdec/软解、vo 重建、
  resurface、tone-mapping、output-levels）、surface 载体（SurfaceProducer 与
  SurfaceTextureEntry 均灰）、wid 绑定时序（1x1 先绑 vs 视频参数后绑均灰）、控制器
  创建时机（急建+预热=legacy 时机仍灰）、player.stop() 剥离、YUV arm 包装剥离、
  target-colorspace-hint 剥离 —— 全部无效。mpv 侧日志（vo/gpu "Video display
  1280x720 -> 1280x720"）与 legacy 完全一致。
- 遗留判定：会话纹理输出链路内部存在一个 legacy 不经过的破坏点（疑似 Java/GL
  纹理消费层），本轮未定位到；以架构规避：
- **修复**：PiliPlus 双路 —— SDR 流一律走 legacy VideoController（实机验证全彩）；
  仅当"流为 HDR 且面板会话就绪"才进会话（见 2）。
- 顺带修复：legacy 分支无自动播放接线（回退后黑屏）→ 回退/legacy 路径补
  play；会话 open 看门狗（45s）+ abandon 式回退（不等待已死会话的 dispose）。

### 2. HDR 激活（路由层达成并实机验证；LG 执行层被 YUV 载体未完成阻塞）
- 本轮打通的路由层（实机 HdrDiag 证据）：
  - PiliPlus 依赖 media_kit_android_dataspace_vendor（此前仅 override 无依赖，
    插件未入包，ext=none）→ LG 上 ext=lg-pq、extApplicable=true。
  - routeOptionsForLegacyConfiguration 解除 output=require(sdr) 钉死（自动模式）。
  - 规划结果（BV1vY4y1N7TY，dvP84）：`selected=baseLayerConvert
    presentation=nativeHdr`（HLG→PQ、gpu-next、YUV 载体）；nativeDolbyVision 因
    LG DV 解码器无 P8 profile(0x100) 被拒（nativeDvUnavailable，与文档一致）；
    toneMapSdr 被 displayLacksTransfer 排除 —— 符合"有能力面板禁止 tone-map"。
  - review 预算 8s→20s（4K 网络流 loaded 1.4–4.6s + settle 5–8s，8s 必超时；
    超时链曾导致 hwdec 排除→软解 4K→停滞黑屏）。修复后 4K review 7.8–9.6s 成功。
- 执行层阻塞点（新证据）：进入 baseLayerConvert（YUV 载体）后，
  `YUV-DIAG: owner generation unavailable; legacy global arm` 之后整个 open 永久
  悬挂（无 applied/无降级/无报错）；且悬挂会连坐：平台线程被占死后，看门狗回退的
  dispose/新 Player 创建全部排队 → 全程黑屏。该路径为 lg-p84-yuv-window 生产
  集成未完成部分（lab-only 验证过），本轮不再深入。
- **门控（本轮最终形态）**：PiliPlus 仅当 `displayHdrTypes 非空 && (sdkInt>=28 ||
  ext.applicable && ext.validatedPredictionTransfers 非空)` 才允许进会话。LG
  （sdk24 + lg-pq 声明 setter-only、无 validated transfers）→ HDR 流走 legacy
  tone-map 播放（颜色正确、可播，优于黑屏）；API≥28 或 vendor 已验证设备 → 会话
  HDR 输出照常启用。lg-pq 若补齐 validated 声明（YUV 载体验证落地后），LG 自动
  重新进入会话路径，无需改 App。

### 3. 其他媒体库（media-kit）本轮变更
- hdr_strategy_realizer：纹理拓扑（sdrDirect/toneMapSdr）vo gpu-next→gpu（同拓扑
  legacy 验证形态；realizeCandidates 候选展开守卫同步接受 'gpu'）。
- hdr_decoder_review / hdr_video_session：review 预算默认 8s→20s。
- routed_video_playback：Android 急建会话 + warmUpOptions 预热（legacy 时机）；
  首视频跳过 player.stop()；sdrEmbed 保持 false。
- hdr_player_backend：非 YUV 契约跳过 YUV arm 包装；纹理路由不再写
  target-colorspace-hint（Flutter 纹理消费无色彩空间协商通道）。
- 测试债：media_kit_video 999/1020 过、21 失败均为钉旧契约的用例（vo 字面量、
  预算、sdrEmbed 桥默认、tone-map texture 分支等），需按新契约更新：
  hdr_execution_catalog_test（2）、hdr_native_dv_session_observer_test（1）、
  hdr_route_planner_test（1）等 21 项。

## PiliPlus 侧最终变更
- pubspec.yaml：新增 media_kit_android_dataspace_vendor: 1.0.0（插件入包注册）。
- pl_player/controller.dart：_hdrStream/panelHdrCapable（含 sessionReady 判据与
  证据日志 panelHdr/HdrRouteDecision）、_initPlayer(routed:) 双路、legacy 回退补
  play、看门狗+abandon 回退。
- pages/video/controller.dart：isHdrRendition（qn 125/126/129、dvh*/dva*、
  hev1.2/hvc1.2）→ hdrStream 传入。
- 验证（verify2-*，2026-10-20）：四样片 sat p95 = 172/77/127/125，全彩可播，
  零 ANR/FATAL；panelHdr status=resolved types={2,1} sdk=24 sessionReady=false。

## 下一步（接手入口）
1. YUV 载体生产化：hdr_yuv_window_arm 的 owner/legacy global arm 悬挂点
   （"owner generation unavailable" → initializeOutput gate 配对）——打通后 LG 的
   baseLayerConvert 即可实激活 HDR；随后 lg-pq 补 validatedPredictionTransfers，
   PiliPlus 门控自动放行。
2. 会话纹理灰蒙的真正根因（Java/GL 消费层；本轮已把搜索空间压缩到会话 open 流程
   内部的非 mpv 部分）。
3. 更新 21 项媒体库契约测试。

## Archive Metadata
- date: 2026-10-20
- entry: piliplus-lg-gray-veil-hdr-gate-20261020
- agent: ZCode (GLM-5.3)
- project: media-kit / PiliPlus
- submodule: media_kit_video
