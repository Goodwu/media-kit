# DV003 架构评审（team-specialist，2026-10-12）

只读评审。App HEAD=8bed4a4f；media-kit HEAD=5b279611（相对 a3cdbda2 仅 DV-BUILD-01 文档/脚本差异，HDR 源码无变化）；mpv/FFmpeg/libplacebo 同 DV-BUILD-01 向量。

## 1. 分层判断

用户方向（PiliPlusX 标准化站点信息、media-kit 消费标准化 descriptor）正确；但**不应落实为"把 126 档改写成 P5/dvh1 codec"**。三层语义：

1. 站点声明：quality=126 = B 站声明的杜比视界档（App 层知识）
2. 源格式事实：HEVC 参数、DV profile/compat/BL-RPU-EL 标志及来源完整性
3. 执行与呈现能力：media-kit 按源事实+解码器+目标+复核选路

修正表述：`hvc1.2.4.L150.90` 是有效 HEVC 声明，**保留原串用于 VideoSourceSpec 解码查询**；在旁补充标准化 HdrSourceDescriptor（codec='hevc'、dynamicMetadata=dolbyVision），无证据字段留空。App 不维护设备/解码器规则；media-kit 不识别 B 站 126。

关键架构事实：现有 hint 是**执行授权**而非纯排序——Session `_prepare` 在 open 前按 hint 规划，unknown DV 直接 blocked（hdr_route_planner.dart:249-258）；open coordinator 先输出配置/open(play:true) 后 review（hdr_open_coordinator.dart:455-605）；classifier 无 facts 保留 hint、二次 mismatch accept 旧 route（hdr_source_classifier.dart:101-155、hdr_video_session.dart:890-917）。**因此不能依赖"Session 必兜底错 hint"。**

## 2. profile 信息来源逐项结论

| 来源 | 结论 | 要点 |
| --- | --- | --- |
| a. open 后容器/解码器事实 | 可行但**不可作为唯一来源** | backend 收 dolby-vision-profile/compat/EL 并重分类（hdr_player_backend.dart:845-948；hdr_video_session.dart:803-973；真机已证）。但 unknown DV 在 `_prepare` 就被拦，到不了 open；错 hint 可能解码器初始化即失败 |
| b. Range GET 轻量嗅探 DOVI 配置记录 | **推荐优先验证** | FFmpeg 已有解析（ffmpeg/libavformat/dovi_isom.c:32-84；mov.c:9193-9195）；实测匿名 CDN Range 0-2047 → HTTP 206/Content-Range 准确（普通 1080P HEVC 轨：ftyp@4 moov@118 hvcC@701）。126 轨容器未验证；须按 segment_base.initialization 有界解析 box，缺记录/截断返回"未解析"而非 P5 |
| c. B 站 API 其它字段 | **无 profile** | 匿名 web+wbi playurl：126 仅在 support_formats（new_description=杜比视界、codecs=hvc1.2.4.L150.90），DASH 无 126 轨；codecid=12 只证 HEVC（普通 HEVC 轨同 12）；gRPC 枚举仅 264/265/AV1（v1.pbenum.dart:54-67、playershared.pbenum.dart:133-146）且 gRPC playurl 无生产调用链 |
| d. codec 串+平台常识 | **不成立** | Main10 是编码 profile 非 transfer 更非 P5；**B 站存在 P8.4 反例（北海道 BV，compat 4 HLG 基层）**，"126 恒 P5"被事实否定 |

## 3. 统一处理设计推荐

流程：**站点声明 → 可解析候选 → 获取源事实 → 按事实规划 → 执行 → Session 复核**。

- descriptor：codec='hevc' + dynamicMetadata=dolbyVision，profile/compat/transfer 留空；嗅探/resolver 得到事实后填 resolved descriptor（缓存绑定 rendition 身份）。"平台倾向 P5"如要保留只能做独立弱排序提示，首版不需要。
- **三态准入拆分**（替换 allows 一肩双挑）：
  - `ready`：可选，正常规划
  - `needsSourceResolution`：可选，说明"播放前确认 HDR 格式"，只授权有界探测，不授权未知颜色输出
  - `unsupported`：灰禁+具体原因
  - 126+合法 HEVC+解码 supported+可用 resolver → 第二态。**不能只删 hasUnresolvedDolbyVision 判断**（Session `_prepare` 仍拒）。isHdrPresentable 严格含义保留。decodeSupport 不复用（依赖 selected.route）。SDR 屏策略（video_quality_eligibility.dart:89-94 的 displayHdrUnsupported）需产品显式决策，不得伪设 hdrDisplaySupportsHdr。
- **嗅探失败兜底**：media-kit 新增站点无关、无呈现的 source-resolution 阶段（只 demux 初始化信息；不提交帧、不剥 RPU、不做未知颜色 SDR fallback；到期返回结构化 sourceMetadataUnknown，不重置失败记录）。这是新能力，不是现有 Session 行为；借完整 Player 探测须另证无呈现与生命周期隔离。
- 拿不到 profile 的源在 B1b 下只有两选：维持执行未授权，或取得其它足够源事实进入已定义安全路径。**不能靠选最常见 profile 消除未知。**

## 4. 错标风险矩阵（为何不统一伪造 P5）

| 场景 | 后果 | Session 能否纠正 |
| --- | --- | --- |
| LG：实际 P8.4 误标 P5 → nativeDV | FFmpeg 按真实 DOVI record 选 P8 Android 0x100，非 App hint 强行 P5；无对应 decoder 则 review 前失败 | 不能保证到达重分类 |
| HLG 面板：实际 P8.4 误标 P5 | 失去 baseLayerDirect，转 reshape/tone-map 或 open 前拒绝 | 条件可纠正（须先有可启动路径取得 facts） |
| HLG 面板：实际 P5 误标 HLG | 普通 baseLayerDirect 忽略 RPU → P5 IPT 基层错色 | 取得 facts 后可重建/阻断，但不保证复核前无错色帧 |
| SDR 屏：实际 P5 误标 P8.4 | 错误 tone-map 可能剥 RPU，失去 P5 必需颜色信息 | 不能作可靠兜底 |

FFmpeg 证据：mediacodecdec.c:399-453,529-549 按真实配置转 P8→Android 0x100；common.c:1052-1094 精确查 decoder 缺失即失败（二进制绑定未核验）。

## 5. 回归面

- 既有 10 项 App（hdr_unknown_source_test.dart:25-114）与 29 项库（hdr_unknown_dolby_vision_test.dart:31-164）断言**全部保持成立**，不翻转；cb14f853/8de0de00 矩阵不回退。
- 新增回归：真实形态（126+hvc1 → DV 意图+HEVC codec+profile 未知；普通档同 codec 不变 DV；codecid=12 不触发 DV）；容器解析（P5/P8.1/P8.4、EL/RPU/BL、缺记录/截断/64 位长度/多 track/初始化段>2KB、与 ffprobe 一致性、200 忽略 Range/206/416/过期/超时）；准入与 UI（三态、菜单-点击-初始选档-最终 codec 同一 rendition 结果、不伪设显示能力、换源/换目标/迟到结果不交叉污染、SDR 屏策略若开放则加 tone-map 策略测试）；Session 安全门（未解析前无可见帧/剥 RPU/颜色转换、resolved 后正常规划、事实优先于 hint、弱 hint 不当 confirmed、失败预算不重置、supersede/dispose 清理）；App 事件反馈（现 HdrReclassifiedEvent 被忽略、Degraded 一律显示"已降级 tone-map"——controller.dart:1591-1627，需补真实失败/结果反馈）。

## 6. 推荐（一句话）

App 保留真实 HEVC codec、标准化 126 的 DV 意图，优先用有界初始化段 DOVI 嗅探取得 profile；拿不到时进入库级无呈现 source-resolution 流程，而不是统一伪造 P5；颜色执行严格等待源事实授权。

## 未验证项

本例 126 实际 profile；两个真实 B 站 DV rendition 的配置记录完整性/CDN 行为；B 站 DV profile 分布统计；新 resolver 后端实现/延迟/资源成本；既有 Session 在全部错误 hint 场景避免错色首帧；新候选设备二进制绑定与颜色/生命周期验收。若实现触及"未知源何时可呈现"边界，交独立 Critical Reviewer 终审。
