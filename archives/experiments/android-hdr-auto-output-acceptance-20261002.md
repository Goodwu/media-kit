# HDR 能力路由实机验收：A1–A6 + 升级轮 + 性能（2026-10-02）

- 对应需求：`docs/requirements/android-hdr-auto-output.md` v3（验收 A1–A8）；计划 `docs/requirements/android-hdr-auto-output-plan.md` S10
- 主题上下文：`archives/conversations/android-hdr-auto-output-20261002.md`
- 设备：`3EP7N18C28016072`（LYA-AL00，Android 10）；每轮结束恢复原 12492 包、自动亮度、熄屏（restore 输出逐轮核验）
- 库/迁移基线：media-kit `main` `9b18eb6e`（S10 代码迁移）+ `410df92b`（复核时序修复）；迁移 APK `a2e45ccaa05f4109`；库测试 185/185、hdr_lab 48/48
- 证据持久化：`~/src/media-kit-build/evidence/hdr-auto-output-acceptance-20261002/`（118 文件：26 轮设备日志 + 构建日志 + 截图 + SF 转储）
- 构建脚本：`tool/hdr-auto-probe-build.sh`（轮次纪律复用 `tool/matrix-round.sh`）

## 轮次与证据摘要（26 轮）

### A1 矩阵复跑（对照 playback-matrix-12703–12708）

| 轮 | 样片 | 实际路由 | 对照基线 | EOS/时长 | 渲染失败 |
|---|---|---|---|---|---|
| a1-p5 | Mystery Box（hint P5） | metadataReshape PQ：gpu-next/mediacodec、platformView、surface pq、stripRpu=false | 12704 同组合 | **全片 EOS** completed=true@99s | 0 |
| a1-hdr10 | hdr10-full（hint HDR10） | baseLayerDirect PQ：mediacodec_embed、platformView | 12706 同组合 | **全片 EOS** completed=true@304s | 0 |
| a1-p84-fix | p84-full（hint P8.4，修复后） | baseLayerDirect HLG：mediacodec_embed、platformView；SF 层 `BT2020_ITU_HLG (302383104)` | 12708 同组合 | 70s 观察窗 | 0 |
| a1-hlg | DVS graypatch（hint HLG，默认门禁） | toneMapSdr 兜底：gpu-next Texture；candidates 全 experimentalStrategySkipped | 新覆盖（12703 时代无纯 HLG 轮） | 45s | 0 |
| a1-sdr | Mystery Box（Texture SDR 流） | 会话 toneMapSdr Texture：gpu-next/mediacodec | 12703 行为不变 | 60s | 0 |

dataspace 读回（P5）：`requested=pq path=ext:lya-pq readback=DATASPACE_BT2020_PQ`，私有 ABI `perform=0 actual=163971072 expected=163971072`，与 12704 世代一致。

### A2 预测一致性

每轮 `HDR_SESSION_PREDICTION`/逐候选 `HDR_SESSION_CANDIDATE`（含跳过原因）与 `HDR_SESSION_ACTUAL` 逐项比对：P5/HDR10/P8.4/HLG/SDR 五轮预测选中==实际执行，候选列表与成熟度门禁行为符合预期（P5 预测 confidence=verified 有扩展；HLG 兜底路由 maturity 如实标 experimental）。报告 origin 如实区分 hint/decoder（样片 hint 与解码器事实合并后 origin=decoder，路由不变）。

### A3 降级不停播（注入）

1. **卸载扩展开播 P5**（`hdrLabUnregisterVendorExt=true` 构建 `c98f8854…`）：两级 `HdrDegradedEvent`（metadataReshape→toneMapSdr，diagnostic=initialDataSpaceRejected generation=1/3 viewId=0/1）；Texture 续播 **98.7s 近全片**；logcat **无私有 ABI 日志**；零渲染失败。注：degrade reason=unsupportedStrategy（V1 已接受的偏宽归属，diagnostic 精确）。
2. **模拟无 HLG 开播 P8.4**（`MEDIA_KIT_ANDROID_HDR_SIMULATE_NO_HLG=true` + 新增 `HDR_GATE_OPEN` 门禁开默认序，构建 `5ecf57da…`）：能力覆写 `before={2, 3} after={2}`；计划相 direct 因 displayLacksTransfer 跳过，落 **baseLayerConvert PQ**（gpu-next、stripRpu=true、SF 层 `BT2020_PQ (163971072)`、库读回 `requested=pq path=ext:lya-pq readback=DATASPACE_BT2020_PQ`）；续播 **97.9s**。该情形属计划相跳过，发布 RouteApplied（候选跳过原因进报告），无 Degraded——R3.1"发布对应事件"以报告候选原因兑现。
3. **Mi Note 3 开播 HDR10**：设备不在位，**缺口记录**（同 S2 验证 4）。

顺带实证（a7-p81 两轮）：FATE 10 帧 P8.1 样片在复核窗口内 hwdec-current 无法稳定（0.4s 循环边界抖动）→ **hwdecMismatch 降级链两次端到端实证**：排除 `hwdec:mediacodec` → 重规划 tone-map → 播放继续。

### A4 复核重建（错误 hint/无 hint ×3 轮）

| 场景 | 构建 | 轮 | 重建次数 | 终态路由 |
|---|---|---|---|---|
| SDR→HDR10（hdr10-full + WRONG_HINT=sdr） | `8c9f5659…` | ×3 | 均恰好 **1** | baseLayerDirect PQ ✓ |
| HDR10→P8.4（p84-full + WRONG_HINT=hdr10） | `319f2aab…` | ×3 | 均恰好 **1** | baseLayerDirect HLG ✓ |
| 无 hint（hdr10-full + HDR_NO_HINT） | `e1ab6732…` | ×3 | 均恰好 **1** | baseLayerDirect PQ ✓ |

位置保持：重建发生在复核时点（开播 ~1s 内），time-pos 与流逝时间连续、无重播；报告代次恒等于当前（无过期代次发布）；零渲染失败。终态路由 applied 时刻距开播 ~1.0–1.3s（日志推算）。

### A5 生命周期（脚本注入轮 /tmp/a5-round.sh，构建 `0a160eb1…`）

退出重入 ×5、Home→返回 ×3、seek ×10（KEYCODE_MEDIA_FAST_FORWARD）、全屏中 user_rotation 旋转、暂停 30s→恢复（中央 tap）、播放中偏好/策略切换 ×3（`HDR_PREFERENCE_SWAP off@0ms / auto@16816ms`、`HDR_POLICY_SWAP@6840ms`）：**FATAL/ANR=0**；会话报告 8 份仅 gen=1/gen=2（无过期代次）；Surface `release=released` 与 `acknowledgeSurfaceRelease=acknowledged` 1:1 闭合；零渲染失败。注：swap 计时锚点为页面级而非播放级（0ms 起跳），"路由变化才重建"行为已由三次交换验证；全屏中控制器替换的实机精确时序未单独隔离（S6 widget 测试覆盖跟随语义，记录为观察项）。

### A6 策略偏好（RPU 重建 PQ）

`MEDIA_KIT_ANDROID_HDR_POLICY_EXPERIMENTAL=true`（dvP84=[metadataReshape, nDV, direct, convert, toneMap]，构建 `d5da4d61…`）：custom policy 看效（HDR_POLICY_EXPERIMENTAL 日志）；**metadataReshape 选中**：PQ、dynamic=true（RPU 应用）、gpu-next/platformView、surface pq；SF 层 `BT2020_PQ (163971072)`；97.8s 续播、零渲染失败；电池 40.0°C / 81%（连续轮次后段）。默认配置复跑（a1-p84-fix）仍 HLG 直出 ✓。**人工观察画面正确：待用户确认**（本轮无真人观察，像素证据 + 读回齐备）。

### 成熟度升级轮

| 源×策略 | 现状 | 本轮证据 | 升级结论 |
|---|---|---|---|
| P8.4×baseLayerConvert | experimental | A3-2：PQ 转换、读回/SF 一致、97.9s | **证据完整，待人工观察后升级 verified** |
| HLG×baseLayerDirect | experimental | a1-hlg-gate-85：HLG 直出、time-pos 60.0s≥60s、SF HLG 层 2 处、零失败 | **证据完整，待人工观察后升级 verified** |
| P8.1×baseLayerDirect | inherited | a7-p81/a7-p81-loop：解码器识别 8.1（compat=1）✓、hwdec 不稳定触发降级 | **升级确认受样片阻塞**：公开仅有 10 帧 FATE 样片，复核窗口 hwdec 无法稳定；inherited 的"样片补确认"如实记缺口 |
| P7/HDR Vivid | experimental | 未跑（P7 无 MEL 长样片；Vivid 本地文件实测为 PQ 基层=HDR10 类，升级无意义） | 维持 |

**需求第 6 节状态表未改动**：升级以"待人工观察"提出，用户确认后由 Lead 同步第 6 节与代码常量表（S3 解析单测锁定两处同步）。

### 性能（第 7 节预算）

- **hint 命中首帧**（perf-p84-hit ×3，FirstFramePixelCopy 探针，`MEDIA_KIT_ANDROID_PREOPEN_FIRST_FRAME_PROBE=true`，构建 `28fdec86…`）：touchDownToContent **438.4 / 455.8 / 485.8ms**，中位 **455.8ms ≤ 800ms** ✓（历史基线 0.623–0.676s）。
- **重建/降级路径**（第 7 节 ≤2.0s）：A4 终态路由 applied ~1.0–1.3s（日志推算）；中间 SDR Texture 路由先出画面，无黑场间隔（重建期间持续有内容）。像素探针只测首个内容帧，"终态路由像素级首帧"未单独测量（记录测量口径）。
- 4K60 负载：A6 reshape 轮 time-pos 97.8s 处 frame-drop=0；设备连续轮次后段电池 40.0°C（热状态归因基线 41°C 附近，本轮无独立温控对照——按第 7 节要求记录，4K60 对比测试需同温条件另行安排）。

## A7/A8（PiliPlusX 接入）与缺口

- A7/A8 属 S12（PiliPlusX 仓），未在本轮范围。
- 缺口：Mi Note 3 不在位（A3-3）；P8.1 长样片不存在（升级确认阻塞）；A6/A1-HLG 升级的人工观察待用户；全屏中控制器替换的实机精确时序未单独隔离；终态路由像素级首帧未单独测量（口径记录）。

## 结论

A1–A6 全部执行：A1 五轮与 12703–12708 逐项一致、A2 五轮预测==实际、A3 两注入降级 ≥60s 不停播（第三情形 Mi Note 3 缺口）、A4 九轮均恰好一次重建、A5 无 ANR/FATAL 资源闭合、A6 自定义偏好看效且默认配置不变；升级轮证据完整（P8.4 convert、HLG direct）待人工观察；hint 命中首帧中位 455.8ms 达标。过程中发现并修复 S5 复核时序缺陷（video-params 有界轮询，185/185）。
