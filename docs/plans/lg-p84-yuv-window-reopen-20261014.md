# LG P8.4→PQ 显示重开方案（v4，2026-10-15）

状态：**已实施并实机验证通过**（lgh8，2026-10-15）。W1a/W2/方案 C 演进全部落地；LG H870DS（API24）DV P8.4 经 C4 baseLayerConvert（HLG→PQ）× YUV config49 HWC 载体 verified 274s。剩余边界见 §0 末尾。
代码基线：routing/MK-ROUTING-20261011（v3 基线 d07b46b3 之上含方案 C 演进实施，未推送）。
范围：LG H870DS（API24）Dolby Vision P8.4 解码并转换 PQ 显示恢复可达；RGB/YUV 判定已通用化为"声明式 PQ 呈现通道能力模型"。

## 0. v4 实施与验证回执（2026-10-15）

**裁决演进**（v3 之后设备实机 lgh7 暴露两处方案外缺陷，经 Specialist 裁决方案 C + V2 五轮审核收敛）：

1. **W1a 能力模型**（按 v3 §W1 落地）：`HdrPqPresentation{rgbSurface,yuvWindow}` 三来源解析（vendor 自报 > 平台默认 > 迁移默认）；C2 要求 rgbSurface 否则计划期不可行（`pqRgbPresentationUnavailable`）；C4 载体按通道推导（yuvWindow 且非 rgb → surfacetexture，否则平台基线）。vendor Java 自报：LG `{false,true}`、LYA `{true,false}`，装配全有或全无与 Dart 解析对齐；迁移默认保证现网设备行为逐位不变。
2. **W2 两 define 删除 + 方案 C 演进**：`MEDIA_KIT_ANDROID_SURFACETEXTURE_POC`/`MEDIA_KIT_ANDROID_MKS_YUV_DIAG` 删除，另撤销残留的 `LG_VISUAL278_EXPERIMENT` token 门（桥初始化 owner 改能力门控并补齐标准构造路径接线——lgh7 根因）。arm 生命周期归生产库所有、按执行 attempt 路由条件化（`HdrYuvWindowArm` + `ProcessOutputInitGate` Java 进程静态读写门跨 engine 仲裁：准入先于旧输出 retirement、arm 在 retirement 后 create 前、attempt 终结 awaited 清理、cleanup debt 与写锁同生共死、lease 身份绑定实际参与者；V2 五轮审核每轮阻断以源码级失败路径+真实探针/联合夹具负例关闭）。lab 预开 arm 仪式退役。
3. **V2 审核记录**：五轮终判演进 B1–B6 → R3-1~4 → leaseId codec，最终 **PASS 放行设备**。

**lgh8 实机验证回执**（证据 `~/src/media-kit-build/evidence/lg-p84-reopen-20261014/`，报告含逐条原始日志行）：

- 主判据 lgh8-p84 **PASS 8/8**：能力自报 ✓；C2 skip=pqRgbPresentationUnavailable / C4×surfacetexture 选中 ✓；桥初始化成功（`MKSURF: init: bound owner`、`active-importer=surfacetexture device_registered=1`，对照 lgh7 bridge-not-initialized）✓；**复核样本 hwdecCurrent=surfacetexture**（lgh7 为 null）✓；config49 分支+lgPqApply 全链 accepted 零 refused ✓；arm 生命周期（输出创建后才有原子、open 末 disarm）✓；verified=true 274s 连续（decoder-frame-drop=0）✓；SF 实锤 config49 HWC 层持续驱动+hal_hdr 驻留+COLOR_METADATA(9,1,16) ✓；SDR 复位干净 ✓。
- 回归全过：lgh8-sdr **零 YUV-DIAG/config49 行**（对照 lgh7-sdr 被 arm 毒死——方案 C 直接验证点）；p5 nativeDV、hdr10 baseLayerDirect 零 arm；同进程 p84→dispose→p84 重验（bridge 重初始化、无原子残留、无 single-open 误触发）。
- **剩余边界（如实）**：①production owner 自动生命周期另包（无 owner 的生产 YUV 路径 open 早期显性失败 `yuvWindowArmUnavailable`，不冒称完整支持）；②wrongHint 设备场景待专建（四槽每槽烤定一源无法构造；host 已有 review-reopen YUV→非 YUV 负例）；③同进程跨源互切（p84→sdr→p84）待多源场景构建；④人工色彩/亮度/流畅三样待用户目视；⑤多 engine 残余限制与"arm 至 terminal cleanup 区间拒绝并发第二输出初始化"的设备限制已写入门类文档；⑥W1b（dataspace 依赖键通道化）仍未实施（本批无行为需求）。

**裁决与演进记录（2026-10-14 用户）**：
1. `MEDIA_KIT_ANDROID_SURFACETEXTURE_POC`/`MEDIA_KIT_ANDROID_MKS_YUV_DIAG` 两 define **删除，功能直接开启**（演进：默认打开 → 删 define 直开）。v1 的 D2（槽位策略）与子裁决 (a)(b) 随之消解。
2. RGB/YUV 走线**自动按能力确定**（v3 新增裁决）：判定升级为"声明式 PQ 呈现通道能力模型"（§2 W1），取代 v1-D1 的 lg-pq id 特判与 v2-W2 的无条件载体翻转。

## 1. 诊断结论

### 1.1 现象与定性

LG P8.4 样片三轮同点失败（10-13 lgh4、10-14 lgh5/lgh6）：

1. 候选执行 PQ dataspace 应用，实际输出窗口 format=278 被 vendor 窗口门拒绝：`lgPqApply stage=refused reason=window-format-not-43-experiment-disabled-or-unsupported`（lgh6-p84-device.log:999，lgh4/lgh5 同构）。注意同轮 setter 链路对 format-43 窗口 query/perform 全部 accepted（:985-988）——失败在窗口格式门与合成层，setter 层探测必然假阳性。
2. `HdrDataSpaceApplyException(pq, reason: dataSpaceApplyFailed)`（hdr_player_backend.dart:594-599）→ session 重规划写共享依赖 `excluded[dataspacePq]`（hdr_video_session.dart:811-815），C4 与 C2 共享 `dataspacePq` 被级联排除（hdr_route_planner.dart:372-379；契约测试 hdr_video_session_test.dart:499-586 钉住该语义）。
3. 其余候选各自不可行：C1（LG 无 P8.4 DV 信令）、C3（面板不报 HLG）、toneMapSdr（HDR 显示拦截，SDR 兜底废除不变量）→ `playable=false` 硬失败（OPEN_MISSING）。
4. 10-13 轮"通过"是已废除的隐式 SDR 兜底在降级播放（lgh4 日志 ACTUAL=output:sdr 实锤）。失败非 v7.3 引入；v7.3 只改变失败候选（C4→C2，DV 序 C2 在前）并使失败显形。

### 1.2 曾经打通的构型（2026-10-09 人工验收，"色彩好、亮度好、流畅度好"）

euv13-stable-long（f1384c61）：P8.4（HLG BT.2020 10bit）→ MediaCodec surface 解码 → **SurfaceTexture** → libplacebo HLG→PQ（target-peak=1000）→ RGBA16F 离屏（pq-full）→ BT.2020 NCL YUV 打包 → **NV12 config49（VENUS）window → HWC 视频层**（SF 实锤 0x7FA30C04）→ 逐 buffer COLOR_METADATA（9/1/16）→ SDM hal_hdr → 面板 PQ。
设备级根因事实（10-09 定性）：**LG RGB GLES 链无 HDR 呈现路径（面板 PQ 能力在），RGB 窗口上 dataspace 通道不可修复**；PQ 呈现唯一可行构型即上述 YUV config49 HWC 视频层。（依据：archives/conversations/lg-h870ds-hdr-demo-20261004.md:15）

### 1.3 断点（按 d07b46b3 现状）

1. **载体与授权未接通（W2 解决）**：C4 hwdec 走 API<26 基线 `mediacodec-copy`（realizer:683-684，:351-369），define 未开则不覆写；yuvDiag 无人 arm（lab define 门未开，拒绝串字面 experiment-disabled）→ 窗口为通用 format 278，必被 vendor 窗口门拒绝（lg_fw_adapter.cpp:274-311）。
2. **YUV 窗口契约不成立**：`yuvWindowContract` 要求 hwdec==surfacetexture（realizer:384-388）；载体不切则离屏 pq-full + NV12 契约 + `video-output-levels=full`（hdr_player_backend.dart:563-568）均不声明。
3. **C2 先行失败并毒化 C4（W1 解决）**：dvP84 默认序 C2 在前（hdr_route_planner.dart:66-72）；C2 硬编码 RGB 构型（`hwdec:'mediacodec'`、platformView、surfaceTransfer:'pq'，realizer:487-491）——按 1.2 设备级根因在 LG 结构性不可行。497bf0b2 已隔离 DV mapper 失败依赖（`mapperDolbyVision`，hdr_route.dart:204-208），但 dataspace 类失败仍写共享 `dataspacePq` 键（session:811-815；hdr_route.dart:206-208 注释明确 dataspace/owner 失败不使用 mapper 标签）→ C4 被级联排除。C2 在 lg-pq 类设备计划期 feasible（p5PipelineAvailable + dataspaceExt applicable 即过，realizer:462-479），失败只能运行期暴露。

### 1.4 对照组与能力核验

- hdr10 baseLayerDirect：mediacodec_embed 直通，日志无 lgPqApply 行——不经过渲染窗口 dataspace 通道；p5 nativeDV 同理。P8.4 在 LG 唯一 HDR 出路是渲染转换（HLG→PQ），只能走 YUV 窗口配方。
- LYA P8.4 经 C2 reshape→PQ 通过（`path=ext:lya-pq`，readback BT2020_PQ）：RGB PQ 通道可用，与 LG 相反——设备能力差异，非候选模型故障。
- "底层能力都在"属实：lib 槽 5f8fc04c 字节一致（10-10 基线）、surfacetexture 对象在构建物（build-p84.log:4）、vendor config49 与 arm 通路代码全在。

### 1.5 v1 诊断以来 tip 的相关变化（d07b46b3）

- `mapperDolbyVision` 依赖隔离落地（497bf0b2/36b3e304）："C2 mapper 失败不禁用 C4"在依赖层可表达并有注入测试（hdr_video_session_test.dart:443-493）；native 执行器错误上报未接线（implementation 文档 §12.2:383 自认），且与本案 dataspace 失败类无关。
- implementation 文档 §11:367 的"C2→C4 续走依赖层不可表达"pending 已部分解决（mapper 类可表达；dataspace 类由本方案 W1b 通道化）。
- 本方案引用行号已按 d07b46b3 刷新（见 §5）。

## 2. 打通方案

目标构型：**LG dvP84 → C4 baseLayerConvert（HLG→PQ）× YUV config49 HWC 窗口载体**，经现行契约（yuvWindowContract fail-closed 四元组 + vendor 窗口门）接入。候选序全局裁决（C2 在 C3 前）不动；SDR 兜底不恢复。

### W1 PQ 呈现通道能力模型（RGB/YUV 自动判定，通用设计）

**原则**：声明式能力，不是探测式，也不是设备名单。LG 实证 setter 探测假阳性（1.1 第 1 条）；读回探测仅限有读回通道的设备且属于验证而非发现；探测在开播路径上加首帧延迟。设备特异性只存在于 vendor adapter 的能力自报（数据），路由代码消费通用模型（逻辑）——新设备接入=adapter 报能力，路由零代码变更。

**能力来源（优先级）**：

1. **vendor 自报**：dataspace 扩展内省在现有 `{isApplicable, id}` 上增报 `pqPresentation: {rgbSurface: bool, yuvWindow: bool}`。LG adapter 报 `{rgbSurface:false, yuvWindow:true}`（其窗口门策略的声明化）；LYA adapter 报 `{rgbSurface:true}` 或不报（走迁移默认）。
2. **平台默认**：API≥28 → `rgbSurface=true`（Android dataspace 框架通用事实）；API<28 且无 applicable 扩展 → 两者皆无（仅直通类候选可行）。
3. **迁移默认**：applicable 但未报结构的旧 adapter → `{rgbSurface:true, yuvWindow:false}`——LYA 与全部现网行为逐位不变。

**消费规则（库内零设备名单）**：

- **C2（构造硬绑 RGB）**：`rgbSurface` 为可行性必要条件；false → 计划期 inapplicable，结构化 skipReason（建议 `pqRgbPresentationUnavailable`）。
- **C4（构造可选载体）**：载体由通道推导——`yuvWindow=true` → YUV 载体（surfacetexture + yuvWindowContract）；否则平台基线（API<26 mediacodec-copy / 其余 mediacodec）；双通道皆真 → RGB 优先（当前无双通道设备；未来需要时 vendor 增偏好字段，不在本批）。
- **W1b 失败语义通道化（唯一待裁决）**：C2 依赖 `dataspacePq@rgb`、C4 依赖其实际载体通道键；session 排除按失败路由的通道写（hdr_route.dart:204-208 mapper 隔离的同构扩展）。效果：RGB 通道运行期失败不再毒化 YUV 通道候选。契约变更：hdr_video_session_test.dart:499-586 三条"共享 dataspacePq 级联"钉住测试迁移为通道化语义（plan-blocks 不变量在无备选通道时保持）。
- 落点：能力结构进 `HdrCapabilities`/ext 描述类型（现有 `dataSpaceExt?.applicable` 消费点 realizer:686-689 旁）；realizer `_metadataReshape`（:433）与 `_baseLayerConvert`（:320）消费；planner 无新逻辑（可行性经 realizer inapplicability 流入）。

**测试**：能力模型单测（三来源优先级 + 迁移默认）；LG-class dvP84 计划形态（C1/C2/C3 skip、C4×YUV 载体 feasible、playable 预测 true）；hdr10/P5 在 LG-class 计划不回归；mapper 隔离既有用例全绿；W1b 若同批，级联三测迁移。

### W2 define 删除与功能无条件开启（已裁决）

**变更清单（代码）**：

- `MEDIA_KIT_ANDROID_SURFACETEXTURE_POC` 删除：
  - realizer：`_surfaceTexturePoc` 常量（:657-658）与注释（:653-656）删除；`surfaceTexturePocHwdec`（:677-681）删除，C4 载体改由 W1 通道推导（取代 v2 的无条件翻转）；`officialBackendReady`/`mkstBridgeProbeOverride` 参数与字段（:667-668，:365-369 调用点）删除。
  - probe 死代码：`hdr_mkst_bridge_probe_stub.dart`、`hdr_mkst_bridge_probe_io.dart`（唯一生产消费即载体判定；fork 侧 mkst bridge 与 native 不动）。
  - lab 侧同 define 读点：`media_kit_hdr_lab/lib/common/sources/android_hdr_player_backend.dart:26`、`android_surface_texture_experiment.dart`（`AndroidSurfaceTexturePoc.enabled/hwdecToWrite` 收敛删除）。
- `MEDIA_KIT_ANDROID_MKS_YUV_DIAG` 删除：
  - lab `01.single_player_single_video.dart`：`_androidMksYuvDiag` 常量（:864-866）删除；arm 门控三分支 inert 判定（:3294-3329）与 :3660/:3671 两处门控塌缩——arm 无条件进入运行时守卫链（pairing 硬校验 :3761-3812、owner-bound arm 失败回退 legacy、disarm :3816-3847，形态不变）；非 LG 设备被 `isApplicable()` 自然 no-op。
- **爆炸半径（较 v2 收窄）**：W1 通道推导使非 yuv 通道设备行为与今天逐位一致；YUV 载体仅在声明 `yuvWindow=true` 的设备激活（当前=LG）。所有构建无开关差异（build identity 统一）。与"去开关"方向一致（先例：v7.3 成熟度门删除、§10.3.5a experimental 字段删除）。

**测试迁移清单（契约纪律：0 ESCALATED、无断言本意删减）**：

- `hdr_surface_texture_official_backend_test.dart`：迁移为钉住"C4 载体由通道能力推导"新不变量；define/probe 分支用例随主体删除（先例 §10.3.5a）。
- lab `android_hdr_surface_texture_poc_test.dart`（:27-55）：迁移为载体推导断言 + `AndroidSurfaceTexturePoc` 删除后收口。

### W3 host 验证

analyze 零 finding；media_kit_video + media_kit_hdr_lab 全量绿；W1/W2 新增与迁移用例绿。

### W4 实机验收（LG 当前在线：LGH870DS42e27764）

- LG p84 样片：route 声明 surfacetexture 载体（通道推导所得）、yuvWindowContract validate 通过、lgPqApply 无 refused（窗口 format 43/config49 accepted）、SF 实锤 config49 HWC 视频层 + hal_hdr 驻留、COLOR_METADATA(9,1,16)；全片 EOS、零 render_failures、dispose 闭合、SDR 复位；人工三样（色彩/亮度/流畅）对照 10-09 验收。
- 回归不破：LYA p84 仍 C2→PQ（C4 不触达）；LG p5 nativeDV、hdr10 baseLayerDirect 不回归；jason SDR、marble 可达轮不回归。
- 风险与回退：契约层与 10-09 演示构建的等价性未经实机复核，是主要验证风险。若仍失败，用 lab 页 arm 通路逐段复演 10-09 流程定位；失败证据回填候选表，不回退 SDR 兜底。

### W5 记录收口

需求文档 §6 候选表补 LG dvP84×baseLayerConvert（YUV 载体）行与依据 + 呈现通道能力模型入 R6/能力章节；followup 计划（v4.1）触发式候选重开记录；implementation 文档 §4.4/§12.2 补 dataspace 通道化注记（若 W1b 同批）；TASKS.md 与 conversation 同步；push 逐次请示。

## 3. 裁决状态

- **W1b（唯一待裁决）**：依赖键通道化（dataspacePq@rgb/@yuvWindow）同批实施 vs 先落计划期门+载体推导、通道化后续批。同批=模型一次完整（RGB 失败运行期也能续走 YUV）；分批=每批契约面更小（先例：v7.3 分批迁移）。无双通道设备存在，两案当前实机行为等价。
- 已裁决消解：v1-D2（槽位策略）、v1-D1（lg-pq id 特判 vs vendor 单字段——被通用模型取代）、v2 的无条件载体翻转（被 W1 通道推导取代）。

## 4. 非目标

- 不改 DV 默认候选序全局裁决；不恢复 SDR 兜底；不为 C2 改造 YUV 载体。
- 不接 native 层 mapper 失败上报（§12.2 已有归属）；fork/mpv 与 vendor .so 不动（W1 的 adapter 能力自报是 Java 层 report map 增列 + 既有能力管线透传）。
- 双通道设备的 YUV 偏好字段、HLG 呈现通道建模（C3 走 displayHdrTypes 已能力驱动）：留后续。

## 5. 证据索引（行号=d07b46b3）

- 日志：`~/src/media-kit-build/evidence/regression-v73-20261014/`（lgh6-p84:967/:985-988/:999/:1004-1011、lgh6-hdr10、lgh6-p5）、`regression-latest-20261014/`（lgh5-p84）、`regression-two-device-20261013/`（lgh4-p84:296/:339/:341/:344/:664-672）。
- 库代码：hdr_route_planner.dart:66-72/:372-379、hdr_route.dart:140/:204-208、hdr_strategy_realizer.dart:80-136/:320/:351-369/:384-388/:433/:462-479/:487-500/:647-658/:667-689、hdr_video_session.dart:796-834、hdr_player_backend.dart:46/:70/:563-568/:594-613、hdr_yuv_presentation_contract.dart、hdr_mkst_bridge_probe_{stub,io}.dart。
- lab：01.single_player_single_video.dart:864-866/:3294-3329/:3660/:3671/:3761-3847、common/sources/android_hdr_player_backend.dart:26、android_surface_texture_experiment.dart；MainActivity.kt:243-268（channel，不变）。
- 测试：hdr_video_session_test.dart:443-493/:499-586、hdr_surface_texture_official_backend_test.dart、android_hdr_surface_texture_poc_test.dart、hdr_fallback_failure_test.dart:64-107。
- native：lg_fw_adapter.cpp:85-101/:106-137/:151/:164-167/:216-220/:274-311、LgPqDataSpaceExt.java:123-232。
- 文档：lg-h870ds-hdr-demo-20261004.md:15（10-09 验收原文）、regression-latest-20261014.md（三轮失败链）、lg-p84-hdr-followup-plan-20261009.md、media-kit-routing-implementation-20261011.md:367/:383。
