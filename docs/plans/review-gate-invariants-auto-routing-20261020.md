# 复核门三条不变量重写 + 普通入口自动路由：设计稿（待 specialist review）

日期：2026-10-20。分支：`compat/piliplus-zero-change-20261018`。
状态：设计稿草案，未实施；按治理需 specialist review 后排期。
上游输入：用户裁决「修改方案尽量少修改 App 侧」+ 架构顾问三不变量提案（2026-10-20 会话）。

## 0. 本设计要解决的问题（全部有 2026-10-20 实机证据）

证据目录 `/tmp/pili-verify-20261020/`（lya-dv-routed / lg-sdr-diag / lya-dv-fallback / lya-dv-copy），设备 LYA-AL00（API 29，hisi）、LGH870DS（API 24，qcom）、marble（API 35）。App = PiliPlus 零改动 + 本仓 path overrides，样片 BV1vY4y1N7TY（4K DV，B 站 DASH 双流 EDL 打开）与 BV1T7t96BECu（SDR）。

| # | 现象 | 证据 |
| --- | --- | --- |
| E1 | 显式 RoutedVideoPlayback 集成下，SDR 与 DV 样片在 LYA 均被身份复核门拒绝：`HdrDecoderReviewFailure(Decoder endpoint changed: …)`，iter=7 后放弃，open 失败 | lya-dv-routed/lya-dv-fallback logcat |
| E2 | 拷贝路线同样被拒：显式 `hwdec=auto-copy` 使规划 `hwdec=mediacodec-copy topology=texture`（与实验室 LG PASS 配置同形），复核仍 `endpoint-changed: current-tracks/video/decoder` | lya-dv-copy logcat decision/review 行 |
| E3 | LG 直连规划下 `outputBindTimeout`（10s）后 degrade 同候选；会话输出绑定依赖 App 视图先行挂载，App 挂载门 `videoController == null` 与会话懒建控制器形成环 | lg-sdr-diag HdrDiag degrade 行 |
| E4 | EDL 双流源规划时事实全空：`predict source=none,…,unknown class=sdr`——DV 内容被规划为 sdrDirect，native HDR 不可达 | 全部 LYA 轮 predict 行 |
| E5 | App 侧回退（会话失败后 App 重建普通控制器重开）后位置推进但画面不渲染：进程级输出所有权/vo 状态未干净交还 | lya-dv-fallback（pixel 0% + 进度推进） |

E1/E2 的机理：hisi/OMX 在 EDL 懒附着期间端点（current-tracks/video/decoder、hwdec-current、android-mediacodec-info）天然翻覆；现有发布白名单（首发布/附着重标/消失语义）覆盖不了全部形状。E2 证明**问题在"事后识别漂移"这台机器本身**，与候选选择无关。

## 1. 三条不变量（吸收顾问提案，替代 P1/P2 垫片）

### 不变量 1：计划即承诺；静止后一次采样
- 打开时携带精确承诺（vo/hwdec/载体；`hwdec-software-fallback` 禁止——App 侧已有该属性语义）。
- 复核退化为：**静止判定 + 单次端点采样 + 匹配即通过**；此后只信错误事件。任何端点变化 = 失败，无形状白名单。
- 静止判定（本设计新增定义，需评审定稿）：`video-params` 非空且连续两次属性读一致（间隔 ≥200ms），或首帧呈现；上限 3s 超时进入失败路径。hisi 实测收敛 ~1.7–2.0s。
- 删除：发布白名单、首发布/附着/消失语义、P1 的原生 readiness/实例身份通道与状态机。

### 不变量 2：失败 = 显式换候选重规划事务
- 复核失败（含静止超时）→ 规划器取**下一个候选**（mediacodec → mediacodec-copy → 软解，候选序已存在）重新走「承诺-打开-验证」。
- 删除 `_retry` 中 `HdrDecoderReviewFailure` 永不重试清单条目；复核失败改为候选级排除（与现有 preparation 失败同一机制）。
- E2 证明 copy 候选在同类设备可用（legacy 路径正在以 copy 播放），该回退可落地。

### 不变量 3：唯一重开权威
- 能力变化/失败重开只有会话一个提交者；App 策略回调（P2 的 `replace/keepCurrent/stop` 精简版）只做决策不下发 open。
- 删除 P2 的 claim token/回执防伪/超时仲裁。
- E5 即双提交者代价的实证；单一权威下该中途拆除不存在。

### 保留的单条容忍规则（需裁决）
- 「播放中同 mime+codec+同 hwdec 模式且帧流不中断的实例重建」容忍（marble `Render:150` 家族），否则一律干净失败重规划。

## 2. 普通入口自动路由（App 零改动的必要条件）

用户裁决：方案必须尽量少修改 App 侧。显式 `RoutedVideoPlayback` 集成需要 App 改 4 处（controller/view/挂载门/诊断开关，diff 已存档 `/tmp/pili-verify-20261020/routed-wiring-app-side.patch`），不符合。落地形态：

- `VideoController.create`（默认配置，Android）内部创建**路由输出槽**而非固定 texture 输出；控制器 id/rect/platform 代理身份**稳定**（主计划 §8），内部后端随会话拓扑替换。App 现有 `SimpleVideo`/挂载门零改动，E3 的挂载环按构造消失（控制器自创建即非空且身份不变）。
- compat `Player.open`（legacy 路径）提交至共享 VideoRoutingSession（rawOpen/rawStop 与公开入口分离已在 P2 交付）；`open(play:false)` 维持"提交即返回"语义，不等待 verified（主计划 §5），play 意图在输出就绪后放行。
- 诊断通道：`HdrOutputDiagnostics.enabled` 默认随 `kDebugMode`，另提供 dart-define 常开开关——零改动 App 的 dev 构建可直接取证。

## 3. EDL 事实晚到（与门重写同批裁决）

E4：双流 EDL 的 DV/HDR10 事实在解码启动后才存在。方案：不变量 1 的「静止采样点」同时作为事实收集点；首次采样若类升级（sdr→hdr/dv），允许**一次**有边界的同源重规划（沿用既有 sourceGeneration 事务模型，禁止无限循环）。预打开 ffprobe/第二 Player 探测明确不做（主计划 §6 已排除）。

## 4. 验收矩阵（增量于既有矩阵）

| 层 | 用例 |
| --- | --- |
| 门单测 | 静止采样通过/超时失败、无白名单残留断言、候选排除推进（direct→copy→软解）、同配置重建容忍单规则 |
| 自动路由 | 零改动 App：VideoController 默认创建即路由输出槽、控制器身份跨拓扑稳定、open(play:false) 即返、play 意图挂起至输出就绪 |
| EDL 事实 | 双流 EDL：首采样类升级触发一次重规划、无循环、音频/听视频不建视频会话 |
| 设备 | LYA：E1/E2 场景 direct 干净失败→copy 验证播放；LG：outputBindTimeout 消除；marble：DV 样片 native 路线或明确降级报告；三机零 FATAL/ANR |
| 回归 | media_kit_video 全量 + hdr_lab 298 项迁移至新契约；DV004 既有不变量逐条对账 |

## 5. 迁移与治理

- 触及 DV004 不变量与 hdr_lab，按仓规约走 specialist review → V2 → 实施；P1/P2 两份设计降级为对照方案（原生仓工作包取消）。
- 分批：①门重写+候选回退（不变量 1/2）→ ②自动路由（§2）→ ③EDL 事实（§3）。①②可并行开发、分批合入。
- 风险如实：vendor 瞬态从静默自愈变为可见失败+1–2s 重规划（优于现状卡死）；失去"软解悄悄降级"区分（按构造不可能发生）。

## 6. 2026-10-20 实测数据附录

- LYA 4K DV、legacy 零改动路径（现装基线）：hisi 硬解 HEVC 3840×1920、SF 层有效帧率 ~15.3fps（中位间隔 65.4ms、64/126 间隔 >2 vsync）——丢帧根因=copy+gpu-next 色调映射+4K 纹理上传链。
- LYA 能力：sdk=29 displayHdrTypes=2,3 hevcMain10/4K=true dvDecoders=0 p5Pipeline=true。
- LG 能力：sdk=24 displayHdrTypes=1,2 hevcMain10/4K=true dvDecoders=2。
- 修复依赖关系：丢帧最终解除依赖本设计（embed/native 路线可达），单靠 copy 路线上限即 15fps 基线。
