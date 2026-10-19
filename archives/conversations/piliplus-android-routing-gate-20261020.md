# PiliPlus Android 路由验收、复核门实测与三不变量设计输入

## Current State
- 背景: 用户要求参照 PiliPlusX 样片验收 PiliPlus（零改动 + 本仓 compat 分支），重点路由正确性；随后报告 LG/LYA 播 4K DV 样片明显丢帧并指示"先解决路由再解决丢帧、尽量少修改 App 侧"。
- 目标: 拿到路由/丢帧的实机判定与根因，产出修复设计（App 侧零改动）。
- 当前状态: 证据链闭合；设计稿已落盘待 specialist review；App 恢复零改动并重装可用基线（4K ~15fps）；实施未开始。
- 关键结论:
  - 零改动路径（现装基线）不走路由：legacy 默认 VideoController=texture，LYA 播 4K DV 实测 ~15.3fps（SF 层中位间隔 65.4ms），丢帧根因=mediacodec-copy+gpu-next DV→SDR 色调映射+4K 纹理上传链。
  - 显式 RoutedVideoPlayback 集成可跑通机制（会话/规划/诊断全部介入），但身份复核门在 LYA 对 SDR 与 DV、对 direct 与 copy 候选**确定性拒绝**（iter=7 endpoint-changed；E1/E2）——问题在"事后识别漂移"的白名单机器本身。
  - LG 侧另有 outputBindTimeout：会话输出绑定依赖 App 视图先行挂载，App 挂载门 videoController==null 与会话懒建控制器成环（E3）；App 侧 4 处接线 diff 已存档未合入。
  - EDL 双流源规划时事实全空（source=none class=sdr），DV 内容必被规划为 SDR（E4）——门重写必须与事实晚到同批裁决。
  - 用户裁决：方案尽量少改 App 侧 → 修复全部收敛到 SDK：复核门三不变量重写 + 普通入口自动路由（稳定控制器代理）+ EDL 静止采样点事实收集。
- 下一步:
  - 设计稿 `docs/plans/review-gate-invariants-auto-routing-20261020.md` 走 specialist review → V2 → 分批实施（①门+候选回退 ②自动路由 ③EDL 事实）。
- 接手入口:
  - 设计稿：`docs/plans/review-gate-invariants-auto-routing-20261020.md`
  - 实测证据：`/tmp/pili-verify-20261020/`（lya-dv-routed / lg-sdr-diag / lya-dv-fallback / lya-dv-copy，含 HdrDiag 全序列与 SF 帧率）
  - App 侧接线存档（不合入）：`/tmp/pili-verify-20261020/routed-wiring-app-side.patch`

## Session Log
- S1: 2026-10-20 晚 PiliPlus 三机验收与根因定位（HdrDiag 通道经 App 临时开关取得；SF --latency 用 EMUI 层名 "SurfaceView - pkg/act#0" 才有数据）。
- S2: 2026-10-20 深夜 App 侧接线试验（RoutedVideoPlayback/RoutedSimpleVideo + 挂载门 + auto-copy + legacy 回退）完整复现门失败后，按用户裁决回退 App 零改动，修复方案收敛 SDK 侧并落设计稿。

## Findings
- F1: `routeOptionsForLegacyConfiguration` 对 PiliPlus 安卓 release 默认 hwdec=`mediacodec,auto-safe`（混合 direct+auto）判为非 copy 意图 → 规划钉 direct；显式传 auto-copy 可得 copy 规划（实测 decision 行 hwdec=mediacodec-copy topology=texture），但 copy 候选同样过不了现有门（E2）。
- F2: `_retry` 的永不重试清单含 HdrDecoderReviewFailure；复核失败不产生候选级排除，7 次重建重选同候选（E1/E2 iter=7）。
- F3: RoutedSimpleVideo 空控制器占位为 1px 盒（aspectRatio==null 时），无 App 侧 16:9 兜底则布局永不可用（E3 的一部分）。
- F4: App 侧回退路径（会话失败后重建普通控制器）位置推进但画面不渲染——进程级输出所有权/vo 未干净交还（E5），双提交者代价实证。
- F5: LYA 能力 sdk=29 displayHdrTypes=2,3 dvDecoders=0 p5Pipeline=true；LG sdk=24 displayHdrTypes=1,2 dvDecoders=2（HdrDiag HDR capability 行）。

## Decisions
- D1: 修复方向=三不变量重写 + 普通入口自动路由 + EDL 事实收集，全部 SDK 侧。
  - 依据：E1–E5 实证 + 用户"尽量少改 App"裁决；顾问提案吸收为设计稿 §1–§3。
  - 备选方案：App 侧显式集成（已试验并回退，diff 存档）；单改 failurePolicy（不可行：永不重试清单独立于 policy）。
  - 影响：DV004 不变量与 hdr_lab 契约重写，P1/P2 设计降级为对照方案；丢帧最终解除依赖本设计落地。

## Action Items
- [ ] A1: 设计稿 specialist review（含"同配置重建容忍"单规则与静止判定参数定稿）。
- [ ] A2: 分批实施 ①门+候选回退 ②自动路由 ③EDL 事实；每批过全量契约测试与三机设备验收。
- [ ] A3: 自动路由落地后删除 App 侧接线存档的依赖（届时 App 仅需 pubspec_overrides）。

## Archive Metadata
- date: 2026-10-20
- entry: piliplus-android-routing-gate-20261020
- agent: ZCode (GLM-5.3)
- project: media-kit
- submodule: media_kit_video
