# HDR 路由②+方案 B 设备事实轮（LYA-AL00，2026-10-02）

- 被验证代码：media-kit `main` `e90ada4d`（"HDR 路由 ②+方案 B 合并实施：P5 管线探针去 Player 依赖 + 分类器容器事实消费（V1 PASS）"，本轮为运行时证据，未改任何源码）
- 正向 JAR：`media-kit-d24c59905-arm64-v8a.jar`（SHA-256 `cafef3a44f7ab6379faf59e352e65dd69fa0b0fce45e80f86bc3026520bfdf21`，每轮构建日志含 "Using local arm64 libmpv jar SHA-256" 逐轮核验）
- 负向 JAR：`upstream-predidit-v127-arm64.jar`（SHA-256 `13e882d96b8cd235425172b022e4a94dfcae5f07985dff85c8d648e7369fa2d1`）
- 设备：LYA-AL00 `3EP7N18C28016072`（Android 10，sdk 29，1440x3120）；每轮结束恢复原包 12492（versionCode 2086）、自动亮度（mode=1）、熄屏（mWakefulness=Asleep），restore 输出逐轮核验（见各 `planb-rX-round-stdout.log` 尾部）
- 构建脚本：`tool/hdr-auto-probe-build.sh`（JAR 经 `ORG_GRADLE_PROJECT_mediaKitLocalArm64Jar` 注入）；轮次脚本 `/tmp/planb-round.sh`（复用 `tool/matrix-round.sh` 纪律：唤醒解锁→logcat `-v time`→tap 1560,720（横屏 PREOPEN 全屏页中心）→定时截图→BACK 退出→trap 恢复；未改屏幕亮度，自动亮度全程保持）
- 证据目录：`~/src/media-kit-build/evidence/hdr-planb-facts-20261002/`（环境记录 env.txt；8 份构建日志、8 份全程设备 logcat、轮次 stdout、27 张截图）
- 证据面：logcat tag `media_kit_pipeline_probe`/`MediaKitVideoPlugin probeOnce`（探针）、`HdrDiag HDR capability/classify/predict/decision`（`MEDIA_KIT_ANDROID_HDR_DIAGNOSTICS=true`）、`HDR_CAP_QUERY`、`HDR_SESSION_REPORT/PREDICTION/EVENT`、`MPVPROP`（注意：MPVPROP 探针的属性列表不含三个 ② 属性名，但 `MPVPROP video-params` 读回的原始 JSON 末尾携带 `"hdr-vivid":<bool>` 子字段——hdr-vivid 的原始值证据走该面；compat-id/el-present 无直接 MPVPROP 面，以会话报告/分类行反推并在下文说明）

## 轮次清单

| 轮 | 样片（设备路径） | JAR | hint | 循环 | APK SHA-256（前 8） | 核心结果 |
|---|---|---|---|---|---|---|
| R1 | media-kit-hdrvivid-user-18c7c05a.mp4（真实 HDR Vivid，HLG 基层） | d24c59905 | 无（NO_HINT） | single | `1ea6c568` | hdr-vivid 实机 **no/false**（mediacodec）→ class=hlg → toneMapSdr 安全网；**hdrVivid 未识别**（见问题 1） |
| R1b（归因追加） | 同上 | d24c59905 | — | single | `6ab161b8` | 直接路径 + `hwdec=no` 软解：`MPVPROP video-params` 原始 JSON **`"hdr-vivid":true`** ✓ |
| R2 | media-kit-p81-fate-3313278f.mp4（P8.1，10 帧/0.417s） | d24c59905 | 无 | single | `c7932482` | 容器事实 compat=1、class=dvP81、首个重规划 baseLayerDirect(inherited)；随后 hwdecMismatch 降级 toneMapSdr（已知短样片窗口，与 a7-p81 基线一致） |
| R3 | media-kit-p7fel-fate-67baddaf.mp4（P7 FEL，1 帧） | d24c59905 | 无 | single | `b9953de0` | **el=true（容器事实）**、compat=6、class=dvP7；默认门禁下 toneMapSdr 安全网 |
| R3b（变体） | media-kit-p7fel-dual-7e4b69c9.mp4（双轨） | d24c59905 | 无 | single | `7a708b4c` | 选中轨道无 DOVI 记录（profile 空）→ 无 DV 事实（样片轨道结构所致，如实记录） |
| R4 | media-kit-p84-rpu-12s-control.mp4（mkchk 对照） | d24c59905 | p84（fixture 名匹配） | 无 | `f15c87f8` | 样片容器**无 dvcC/dvvC 记录**（host ffprobe 证实）→ profile 空 → class=hlg → toneMapSdr；断言的 dvP84/compat=4 不成立，归因样片而非代码 |
| R4b（零回归追加） | media-kit-p84-full.mp4（A1 基线同款） | d24c59905 | p84 | 无 | `dbc911be` | class=dvP84、compat=4、el=false、HLG 直出、56s+ 零丢帧正常画面，**零回归 ✓** |
| R5（负向） | media-kit-p84-full.mp4 | upstream v127 | p84 | 无 | `3ae503f1` | 探针 result=0（property=-8）→ **p5Pipeline=false** ✓；② 属性 unavailable → gamma 推断 compat=4 ✓ 不崩、HLG 直出正常播放 |

## P5 管线探针（方案 B）汇总

| 轮 | logcat `media_kit_pipeline_probe` | `MediaKitVideoPlugin probeOnce` | `HdrDiag HDR capability` / `HDR_CAP_QUERY` |
|---|---|---|---|
| R1 | `probe: result=1 config=0 initialize=0 property=0 elapsedMs=8` | `probeOnce: result=1 elapsedMs=8` | `p5Pipeline=true` ×2 |
| R1b* | result=1 elapsedMs=4 | result=1 | （直接路径无 HdrDiag，探针照常 result=1） |
| R2 | result=1 … elapsedMs=4 | result=1 elapsedMs=5 | `p5Pipeline: true` |
| R3 | result=1 … elapsedMs=4 | result=1 | `p5Pipeline: true` |
| R3b | result=1 | result=1 | `p5Pipeline: true` |
| R4 | result=1 … elapsedMs=4 | result=1 | `p5Pipeline: true` |
| R4b | result=1 … elapsedMs=4 | result=1 | `p5Pipeline: true` |
| R5 | **`probe: result=0 config=0 initialize=0 property=-8 elapsedMs=4`** | `probeOnce: result=0` | **`p5Pipeline=false`** |

探针 elapsedMs 实测 4–8ms（配置/初始化均 0 错误）；上游 JAR 的 property=-8（属性不存在）走 result=0 合法不可用路径，未出现 -1 机械失败。`HdrCapabilities.query` 快照（无 Player 亦权威）与探针逐轮一致。

## R1 user-hdr-vivid（正向 JAR，核心轮）——断言逐条

1. **复核事实 `video-params/hdr-vivid` 原始值为 yes → ✗（实机 no）**。证据路径：MPVPROP 面 `MPVPROP video-params={…,"gamma":"hlg",…,"hdr-vivid":false}`（21:52:02.700，开播后帧流中）；复核分类行 `HdrDiag HDR classify: origin=facts codec=hevc transfer=hlg primaries=bt.2020 meta=none`（21:52:02.323/02.714 两次均 none）。归因见问题 1：会话路径所有路由 `hwdec=mediacodec`（`_setOwned('hwdec', route.hwdec)`），MediaCodec 解码不向 AVFrame 传播 CUVA 005.1 side data → fork 属性读 false。**R1b 软解对照证实属性本身工作正常**：`MEDIA_KIT_ANDROID_HDR_TRANSACTION=false` + `MEDIA_KIT_ANDROID_HWDEC=no` 直接路径下 `MPVPROP hwdec-current=no`、`MPVPROP video-params={…,"hdr-vivid":true}`（22:06:27.489）。
2. **会话报告 dynamicMetadata=hdrVivid、class=hdrVivid → ✗**。实际：`HDR_SESSION_REPORT … source=HdrSourceDescriptor(codec: hevc, transfer: hlg, primaries: bt.2020, dynamicMetadata: HdrDynamicMetadata.none, dvProfile: null, …) origin=decoder verified=true`；`HdrDiag HDR decision … class=hlg`。分类器按设计回退到 gamma 推断（hlg），无崩溃。
3. **路由 toneMapSdr 安全网、候选全 experimental 带原因 → ✓（经 hlg 类达成，非 hdrVivid 类）**。`HdrDiag HDR decision: phase=applied gen=1 origin=decoder source=hevc,hlg,bt.2020,none,none,none,false class=hlg selected=toneMapSdr … candidates=baseLayerDirect:experimentalStrategySkipped,baseLayerConvert:experimentalStrategySkipped,toneMapSdr:experimentalStrategySkipped,toneMapSdr:ok`。
4. **无 hint 开播（SDR 起）→ 复核重分类 → 至多一次重建 → ✓**。时序：`ANDROID_HDR_OPEN_BEGIN … hint=null … noHint=true` → 初始 predict `class=sdr selected=sdrDirect`（21:52:01.822）→ `HdrReclassifiedEvent(…, rebuilt: true)`（21:52:02.323，全程唯一一次）→ `HdrRouteAppliedEvent(toneMapSdr…)`（21:52:02.715），代次恒 gen=1。循环单循环模式（`ANDROID_LOOP_SOURCE mode=single loop-file=inf`）续播，t12/t20 截图像素判定"正常画面"，`fatal_count=0`、`render_failures=0`、退出闭合 `ANDROID_AUTO_PLAYER exit player disposed`。
5. **快照 p5Pipeline=true → ✓**。`HDR_CAP_QUERY HdrCapabilities(… p5Pipeline: true, bridge: true, ext: HdrDataSpaceExtInfo(id: lya-pq, applicable: true))` + `HdrDiag HDR capability: … p5Pipeline=true`。

## R2 fate p81——断言逐条

1. **compat-id=1（容器事实）→ ✓**。`HdrDiag HDR classify: origin=facts codec=none transfer=none primaries=none meta=dolbyVision dv=8 compat=1 el=false`；predict `source=hevc,none,none,dolbyVision,8,1,false`；`HdrReclassifiedEvent … dvCompatibilityId: 1`。**容器事实通道的直接证明**：该样片复核时 gamma=none（transfer=none），gamma 推断不可能给出 1，compat=1 只能来自 `current-tracks/video/dolby-vision-compatibility-id` 容器读数（原始值面：MPVPROP 属性列表不含该名，以会话报告反推——此为任务卡预先允许的证据路径）。
2. **class dvP81→HDR10 呈现（P8.1 inherited）→ △**。分类与首个重规划均正确：`HdrDiag HDR predict: source=hevc,none,none,dolbyVision,8,1,false class=dvP81 selected=baseLayerDirect maturity=inherited presentation=nativeHdr … baseLayerDirect:ok`（21:54:38.284）。但随后 `HdrDegradedEvent(reason: hwdecMismatch, from: sdrDirect, to: toneMapSdr, diagnostic: hwdec-current= expected=mediacodec)` → 终态 `class=dvP81 selected=toneMapSdr … baseLayerDirect:hwdecMismatch`。该 10 帧样片在本设备 mediacodec 下无解码输出（`MPVPROP hwdec-current=`（空）、time-pos 恒 0.000000、截图黑屏）——**与既有 a7-p81/a7-p81-loop 基线逐项一致**（基线日志同为 time-pos 0/黑屏/hwdecMismatch 降级），属任务卡预知的"复核窗口赶不上"情形。已用循环模式（loop-file=inf）多次采样，方法如实记录。
3. p5Pipeline=true ✓（`HDR_CAP_QUERY … p5Pipeline: true`；probe result=1）；无崩溃、退出闭合 ✓。

## R3 P7 FEL——断言逐条

1. **el-present=1 → 报告 enhancementLayer=true → ✓（本轮关键可区分事实）**。`HdrDiag HDR classify: origin=facts … dv=7 compat=6 el=true`（21:56:36.377 与 44.557 两次）；predict `source=hevc,none,none,dolbyVision,7,6,true`；`HdrReclassifiedEvent … enhancementLayer: true`。旧版该值为 null（不可观测），true 只能来自 `current-tracks/video/dolby-vision-el-present` 容器读数（profile 7 的 el 无默认值推断路径——`dvElPresent` 为 null 时保持 unknown，分类行会显示 el=unknown）。
2. **compat=6 ✓**（同上 classify 行）。
3. **class dvP7 → ✓；"→hdr10 呈现" → ✗（默认策略下不兑现）**。`HdrDiag HDR predict: class=dvP7 selected=toneMapSdr … candidates=baseLayerDirect:experimentalStrategySkipped,metadataReshape:experimentalStrategySkipped,toneMapSdr:experimentalStrategySkipped,toneMapSdr:ok`——dvP7 成熟度行全 experimental（hdr_strategy.dart P7 行），缺省门禁下全部跳过落 toneMapSdr 安全网；且同 R2 存在 hwdecMismatch（`HdrDegradedEvent … hwdec-current= expected=mediacodec`）。样片 1 帧无输出（time-pos 恒 0），与短样片已知行为一致。
4. R3b 双轨变体：选中轨道无 DOVI 记录（`MPVPROP current-tracks/video/dolby-vision-profile=`（空））→ 复核无 DV 事实，分类保持非 DV（`classify … meta=none dv=none`），hint=null 下会话合成 codec 提示（classify origin=hint、descriptor codec: hevc），一次重建（rebuilt: true）后 sdrDirect 续跑，无崩溃。双轨样片的 BL 轨不带逐轨 DV 信令，容器事实按设计读 unavailable——如实记录，不作为 R3 断言的反例。
5. p5Pipeline=true ✓；无崩溃、退出闭合 ✓。

## R4 mkchk p84 对照回归——断言逐条

1. **class dolbyVisionP84、compat=4、el=false → ✗（样片问题，非代码回归）**。实机 `HdrDiag HDR classify: origin=facts codec=hevc transfer=hlg primaries=bt.2020 meta=none dv=none compat=none el=false`、`class=hlg selected=toneMapSdr`。归因：host `ffprobe -v trace` 证实 `mkchk-media-kit-p84-rpu-12s-control.mp4` 容器**无 dvcC/dvvC box**（对照 `media-kit-DV-P5.mp4` 可见 `type:'dvcC' … profile: 5 … compatibility id: 0`）→ `dolby-vision-profile` 实机读空（`MPVPROP current-tracks/video/dolby-vision-profile=`，复核与 t=4s 两次均空）→ 分类器按设计走 profile-less HLG 回退。hint（fixture 名匹配注入 p84）与事实 hlg 不一致触发一次重建（`HdrReclassifiedEvent … rebuilt: true`）→ toneMapSdr，播放正常（t28 time-pos=11.64，AUTO_COMPLETED completed=true），无崩溃——回退与重建行为本身符合 ② 设计。
2. **R4b（p84-full，A1 基线同款样片）零回归 → ✓**。`HdrDiag HDR classify: origin=facts codec=hevc transfer=hlg primaries=bt.2020 meta=dolbyVision dv=8 compat=4 el=false`；`HdrDiag HDR decision: phase=applied gen=1 origin=decoder source=hevc,hlg,bt.2020,dolbyVision,8,4,false class=dvP84 selected=baseLayerDirect maturity=verified presentation=nativeHdr vo=mediacodec_embed hwdec=mediacodec output=hlg topology=platformView … verified=true degrade=none candidates=nativeDolbyVision:unsupportedStrategy,baseLayerDirect:ok,…`；`HdrReclassifiedEvent(…, rebuilt: false)`（事实与 hint 一致，无重建）；time-pos 55.99s@t60、frame-drop-count=0、t45 截图"正常画面"、`MPVPROP current-tracks/video/dolby-vision-profile=8`。与 S10 A1-p84-fix 基线（baseLayerDirect HLG、SF BT2020_ITU_HLG）一致。
3. p5Pipeline=true ✓（两轮均 probe result=1 / `HDR_CAP_QUERY p5Pipeline: true`）。
4. 注：R4b 的 compat=4 无法区分容器事实与 gamma 推断（hlg→4 两者同值）；容器事实通道的正确性由 R2（compat=1，gamma=none）单独证明。

## R5 负向（上游 JAR upstream-predidit-v127 + p84-full）——断言逐条

1. **p5Pipeline=false（探针 property 读取失败→0 合法路径）→ ✓**。`media_kit_pipeline_probe: probe: result=0 config=0 initialize=0 property=-8 elapsedMs=4`、`MediaKitVideoPlugin: probeOnce: result=0`、`HdrDiag HDR capability: … p5Pipeline=false`、`HDR_CAP_QUERY HdrCapabilities(… p5Pipeline: false, bridge: true …)`。
2. **三个 ② 属性 unavailable → 分类器回退推断不崩、p84 经 gamma 推断仍 4 → ✓**。上游 mpv 无 `hdr-vivid` 子属性（R5 全程 logcat `hdr-vivid` 出现 0 次；R4b 同面为 `"hdr-vivid":false`）、compat-id/el-present 不可用读空；`HdrDiag HDR classify: origin=facts codec=hevc transfer=hlg primaries=bt.2020 meta=dolbyVision dv=8 compat=4 el=false`——compat=4 此处只能来自 profile 8 + gamma hlg 的基基层推断（容器事实通道缺席）；`class=dvP84 selected=baseLayerDirect … output=hlg topology=platformView verified=true degrade=none`，`HdrReclassifiedEvent(…, rebuilt: false)` 无重建。
3. **App 正常运行 → ✓**。time-pos 14.01s@t18 推进、t45 截图"正常画面"、`fatal_count=0`、`render_failures=0`、退出闭合 `exit player disposed`、恢复原包核验通过。

## 发现的问题（按重要性）

1. **HDR Vivid 在会话路径实机不可观测（R1 核心断言不达）**：会话全部路由 `deps {hwdec:mediacodec}` 并由 realizer `_setOwned('hwdec', route.hwdec)` 强制，MediaCodec 解码不传播 CUVA 005.1 逐帧 side data → fork `video-params/hdr-vivid` 读 false → `dynamicMetadata=none` → class=hlg。R1b 软解对照（`hwdec-current=no` 下原始 JSON `"hdr-vivid":true`）证实归因是解码通道剥离 side data，而非 fork 属性缺陷或复核时序问题（R1 复核读与 MPVPROP 帧流中读均为 false）。**路由结果不受影响**（hlg 类缺省门禁下同样落 toneMapSdr 安全网），但 ② 的 hdrVivid→HdrSourceClass.hdrVivid 分支在 LYA 的 mediacodec 路径上无实机正例；需软解路由或带 CUVA 透传的解码通道才能覆盖（库侧当前无软解路由）。建议 Lead 决策：登记为设备/路由限制或调整 dvP* 路由 hwdec 策略。
2. **R4 任务卡指定样片与断言不匹配**：mkchk 对照样片容器无 DOVI 记录（ffprobe 证实），断言的 dvP84/compat=4 对该文件原理上不可达；零回归结论改由 R4b（p84-full）兑现。后续轮次指定样片前应 ffprobe 核对 dvcC/dvvC。
3. **R2/R3 超短样片（10 帧/1 帧）在本设备 mediacodec 下无解码输出**：time-pos 恒 0、黑屏、hwdec-current 空 → 复核后 hwdecMismatch 降级 toneMapSdr。与 a7-p81 既有基线一致；"HDR10 直出终态"断言在该样片上不可终验（首个重规划的 baseLayerDirect/inherited 选择本身已留痕）。公开样片库无长 P7/P8.1 样片，缺口维持。
4. R3b 双轨样片选中轨道无 DOVI 逐轨信令（profile 空）——该样片不适合作为 P7 容器事实轮的主样片。

## 缺口与限制

- R1 的 `video-params/hdr-vivid=yes`→hdrVivid 分类、R2/R3 的 HDR10 直出终态、R3 的 dvP7→hdr10 呈现：因上述问题 1/3 未取得端到端正例；已采集的替代证据（软解原始值 true、首个重规划行、容器事实行）见各轮详录。
- MPVPROP 探针属性列表不含 compat-id/el-present 属性名（App 侧固定列表，本轮不可修改仓库源码），该两项原始值以会话报告/分类行反推（任务卡允许路径），且 R2/R3 的反推均有"推断不可能给出该值"的排除性佐证。
- 本轮未采集 SurfaceFlinger 层转储（断言集不含 SF 面证据）；R4b 的 HLG 直出以 decision 行 + 正常画面截图 + 与 A1 基线行比对为准。
- 屏幕亮度全程自动（未按 matrix-round 惯例调最高），截图仅作画面正常性参考，未做像素级 HDR 判定。
- 设备最终状态：原包 12492（versionCode=2086）已恢复、自动亮度 mode=1、mWakefulness=Asleep（本轮末次核验 2026-10-02 22:08 前后）；仓库工作树 clean（仅本记录文件新增，未 commit）。

## 结论

方案 B P5 探针（8 轮全量）：正向 result=1（elapsedMs 4–8ms）、负向 result=0（property=-8），`HdrCapabilities.query` 快照逐轮一致，无 -1 机械失败，无崩溃——**探针断言全部成立**。② 容器事实：compat-id（R2 compat=1，排除推断的容器直证）、el-present（R3 el=true，旧版 null 的关键区分）通道实机验证成立；上游 JAR 下三属性 unavailable、gamma 推断回退 compat=4 不崩（R5）成立。HDR Vivid 分支（R1）在 LYA mediacodec 路径不可观测（问题 1，归因已实证）；p84 零回归由 R4b 兑现（R4 指定样片本身无 DV 容器记录）。所有轮次零崩溃、零渲染失败、退出资源闭合、设备恢复核验通过。
