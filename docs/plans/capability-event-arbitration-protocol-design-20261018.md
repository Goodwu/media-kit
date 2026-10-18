# 面板能力事件「双事务」仲裁协议设计 v1（库钩子 vs 接受瞬态）

> 来源：Specialist-P2 设计（2026-10-18，只读审查，agent_7d051b41）。基线：库 `0a212785`、App `f6a9c1532`。状态：**待实施、待 V2 独立复核的设计建议**；App 侧用户此前裁决「D 路径暂时不动」，本设计不解释为撤销暂缓或新增实施授权。

## 一、裁决：推荐「显式启用的库侧仲裁钩子」，不推荐把瞬态重开作为正常产品行为接受

| 维度 | 接受瞬态 | 有界仲裁（推荐） |
|---|---|---|
| 产品公理 | 正常路径允许先重开被拒的 HDR 源，与「不使用 HDR→SDR tone-map、拒绝即落 SDR」直接冲突 | 正常响应路径先确定 SDR rendition，再开新源 |
| 实际执行 | 库会 `_open`：停止、重配、打开、复核旧 HDR 源 | 能力事件只产生一个有权提交的决策，旧源重开被抑制 |
| 可见性 | 多一次停止/输出重建可能增加黑屏/闪烁（**频率/持续/可见性未实测**） | 消除双事务额外重开；不保证换轨零黑屏 |
| 实现量 | 低 | 中高：凭据、成功回执、准备/提交分离、D/E1 共用调度 |
| 其它消费者 | 不变 | 无钩子严格原行为；hdr_lab 不必接入 |
| App 不响应 | 库自主处理 | **有界等待后库按现行为自主重规划** |
| DV004/owner | 不绕过 coordinator、复核门、owner/lease；一份决策至多消费一次 |

**关键取舍——正常保证 vs 故障保证**：「App 永不响应时库仍自主重规划」与「所有路径永远零 tone-map」不能同时无条件成立。本方案保证前者，并把后者限定为「App 在期限内正确接管的正常路径」。若产品要求故障路径也绝对禁止 tone-map，需另行批准「超时停播」或显式内容约束。

## 二、已核实事实
- 双事务成立（源码），但具体最终覆盖顺序未实测：库 `hdr_video_session.dart` :314-324 自行订阅原生能力通知；:378-379/:1634-1658 事件经 broadcast stream 发布，无等待 App 决策的确认通道；:1462-1488 通知后 pending open 用自身 source/options 重规划；:1490-1561 已应用源按新能力重规划、必要时 `_open` 当前 media；:1564-1586 原生通知作失效信号重查 target/source；:1379-1414 `setOptions` 也重开 pending/current。App：`pl_player/controller.dart` :686 `onHdrDisplayChanged` 仍 `void Function(bool)?`；:1890-1895 更新面板布尔后调用回调、不接收异步决策；:1771-1786 主动能力刷新也触发同一回调。页面 `controller.dart` :898-935 D 回调选 SDR、改状态、`await updatePlayer()`。
- **不能把现有 Future 完成当 `reopened` 成功证据**：页面 `updatePlayer()==true` 仅表示选源通过且初始化调用完成（:1351-1391）；L `setDataSource` 有早退/内部错误状态（:1092-1134, :1198-1255）；Session `open` 在 `OpenSuperseded`、`HdrPlaybackBlocked` 正常返回（:645-683）。可证明路由应用的内部位置是 Session :600-643（当前 generation、verified report、`phase=applied`、`HdrRouteAppliedEvent`）。
- 复核与预算不得旁路：Session :809-833（`failurePolicy.stop` 优先，身份/复核失败/非输出绑定超时禁止候选重试）、:1266-1286；`hdr_decoder_review.dart` :119-155/:157-173/:224-267/:331-473；`hdr_open_coordinator.dart` :343-376（准备在副作用队列外，generation 淘汰旧工作）、:989-1026（停止/恢复同队列；timeout≠底层取消）。
- 历史移交契约（App 会话档 :79、`docs/plans/android-mksurf-direct-import-enable-plan-20261013.md` :71-80）是设计约束，**当前 Session 无 `handoverFrom` API，不能当现成实现**。

## 三、推荐协议：有界决策 + 原子接管 + 可验证回执

### 3.1 API 选型：会话级显式 opt-in handler（不塞 `VideoRouteOptions`）
```dart
typedef CapabilityChangeHandler = Future<void> Function(CapabilityChangeRequest request);
// HdrVideoSession 构造参数
CapabilityChangeHandler? onCapabilitiesChanging;
Duration capabilityDecisionTimeout = const Duration(seconds: 1);
// request 由库签发，单次消费
Future<CapabilityResolution> replace(CapabilityReplacement replacement);
Future<CapabilityResolution> keepCurrent();
Future<CapabilityResolution> stop(CapabilityStopReason reason);
```
`CapabilityChangeRequest`：不可伪造请求身份、Session 实例身份、capability revision、当前逻辑 source intent、pending/applied generation、target 身份、options revision、冻结能力快照、单调 deadline、可观察失效状态与完成结果。`CapabilityReplacement` 必须是**完整可提交的开源请求**（Media、headers/extras、sourceSpec、新源 hint、target、有效 options、恢复意图），不接受占位。`CapabilityResolution` 终态：`reopened(receipt)`（已过库复核并应用）/`kept`/`stopped`/`superseded`/`failed`；receipt 由库生成、绑定 request/source/generation/options/capability 身份，App 不能伪造。

不新增路由选项字段的理由：`VideoRouteOptions` 是可合并、可持久化的声明性输入（`video_route_options.dart` :51-59/:67-117/:119-158/:192-228），不适合存会话回调与一次性凭据；handler 默认 `null` 走原分支不增加等待。

### 3.2 状态机与唯一提交点
```
offered ─ replace 完整请求 ─原子消费→ claimed ─库执行→ applied / failed
        ─ keepCurrent ─原子消费→ libraryCommit → kept / failed
        ─ stop ─原子消费→ stopping → stopped / failed
        ─ deadline/无有效响应 → fallback ─旧自主逻辑→ terminal
        ─ 新源/新代次/dispose → superseded
```
原子消费发生在库收到完整提交请求时（同一短同步临界区：仍当前/未到期/未消费 → 唯一赢家 → 其它提交能力失效 → 交既有 coordinator），不是页面开始异步工作时；不得「先 isCurrent，再 await，最后普通 open」。

### 3.3 时序
原生能力失效 → Session 查本 target/source 取新能力 → 创建/更新 arbitration request → **先关闭本轮旧源自主重规划入口** → 冻结/淘汰受旧能力影响的 pending 工作 → 发布能力事件 + 调用 opt-in handler → L 更新面板状态/失效路由缓存 → 页面在有界窗口内选轨复核 → `replace(SDR)`（原子 claim → 唯一 SDR open → decoder review → intent 应用屏障 → applied receipt → 页面返回 reopened/L 不再 setOptions）| `keepCurrent()`（库按新能力处理当前 rendition）| 无有效响应（deadline → 原子关闭 App 提交权 → 库按现行为自主重规划 → 迟到 App 请求被拒）。事件必须在仲裁窗口已建立后发布。

### 3.4 决策窗口与执行预算
默认决策窗口 **1 秒**（待测参数）：D 正常路径基于已有 DASH 数据选轨，不等整个网络开播；计时含调度等待、不因重复回调续期；窗口内新能力事件采用最新快照但同一未结算事件组继承最早 deadline。**窗口只等「完整提交」，不等完整 `updatePlayer()`**：未消费请求超时/异常/无效返回 → 库自主重规划；`replace` 已被接受 → 执行权归库（App 丢失后续 Future 也不能再开旧 HDR 源）；replacement 执行沿用输出等待、decoder review、候选预算；另设仲裁执行总 watchdog 初值 **30 秒**（实测调整），到期淘汰执行代次、停止清理，不回旧 HDR 源重试、不重置预算；timeout≠native 取消，清理不能确认完成时保留 debt、拒绝新 owner。

## 四、App 接线与 E1 互斥
- D 回传不能继续用 void 通知：拆「能力发布」（更新 `hdrDisplaySupportsHdr` 驱动 UI）与「能力决策」（L 的 hook 向页面传完整 request/context 等受控终态）。Android 已挂 Session 时，`HdrCapabilityChangedEvent` 消费分支只做发布/报告，**不再另起旧 `_onHdrDisplayChanged` 换源**。
- 页面决策：校验 page/data/options/target/source revision → 当前 HDR 档被面板或偏好拒绝时复用 `_pickFallbackSdrTrack`（准入+8K 门）→ 重新绑定本次能力下的路由判定（不复用旧 `_routeSelection`）→ 合格轨：准备完整 source 请求经 `request.replace` 提交 → 收到 applied receipt 后才返回 `reopened`/发布成功提示 → 无合格 SDR：显式 `stop` 并提示（不得返回 reopened/伪装 keep）→ 当前可保留：`keepCurrent`。**keep-current 只表示保留 rendition，不授权旧 decoder/output 继续有效。** `updatePlayer()` 应增受控调用路径或拆分准备/提交——不能为复用它在 claim 前执行 `setDataSource` 的 source-generation/暂停等副作用。
- 与 `RouteOptionsDecision`：保留 E1 三态外观但共享更强内部结果：`reopened` 只由受验证 applied receipt 映射；`keepCurrent` 表示后续库提交仍由当前事务负责；`superseded` 必须由真实代次淘汰支持；`stopped/failed` 独立内部终态。E1 当前 `fallback == null`、`await updatePlayer()` 后直接返回 reopened 的宽松回执（页面 :251-259）**不得被新 D 协议复制**。
- 共同调度不持长锁等回调：L 增统一 route-intent 调度器覆盖 D、E1 及写入同一 Session 的 source/target/refresh 提交；每次变化同步推进共同 intent revision；业务异步准备在锁外；提交以捕获的复合身份原子检查；D callback 内 replacement 带原 token 重入。并发规则：D 窗口内到 E1 → 旧 D 失效、最新决策同时消费新 options 与新能力；E1 决策中到 D → 旧 E1 不提交、重算最新合并意图；replacement 已 claim 后来 E1/D → 新代次淘汰旧执行、等真实清理屏障后提交；D 超时抢先提交 → 同一原子边界关闭 D token；stop/dispose → 同步淘汰所有未提交 token。库 opt-in 路径须将 `open/setOptions/setPreference/setPolicy` 纳入同一仲裁入口；无 hook 路径原行为。
- 主动刷新入口 `refreshHdrDisplayCapabilities()` 同步收口：Android 有 Session → 经 Session 能力刷新/仲裁入口；首开前无 Session → 仅发布能力供冷启动准入；非 Android 保持；不因 `displayHdr` 布尔未变而跳过 hook（HDR 类型或逐源硬解能力仍可能变化）。

## 五、身份、失败与预算规则
- 能力快照不跨 rendition 误用：`VideoRouteCapabilities.forHdrSource`（`video_route_capabilities.dart` :69-82）把 decoder census 绑定特定 source——旧 HEVC/DV source support 不能赋给新 AVC SDR；新源须取得匹配自身 `sourceSpec` 的 support；面板事实与逐源 decoder support 分开；display revision 必须与请求一致；App 不得回传「更强能力」覆盖库快照。
- 边界处置：页面 dispose 且 Session 释放 → 同步失效 token，晚到结果不 open/提示/发布；页面卸载但共享 Session 存活 → 撤销 handler、未接管请求走库兜底；换源 → 旧事件不得用 `_currentMedia` 恢复旧源；窗口内第二能力事件 → 旧 token 失效、最新胜出、deadline 不延长；裸 `reopened`/伪造 receipt/重复消费 → 不承认；返回能力超集 → API 不提供此授权面；App 抛异常/不响应 → 未 claim 且仍当前则库自主重规划；SDR replacement 被复核门拒 → failed/stopped，不回旧 HDR、不另建 Session 绕门；清理失败/lease 冲突 → 保留 debt、禁止继任 owner；显式 stop 与 timeout 同时 → stop 先失效请求；`failurePolicy.stop` 保持现义。
- DV004 与 v8 相容：同一能力决策的 App replacement 与库 fallback 互斥；逻辑决策 ID/source scope/候选消耗/终止失败随事务保留；126→SDR 是真换 rendition，**不得继承旧 HDR facts**；同源内部重建才可保留 `HdrSourceFacts` origins/conflicts；decoder/output/entry 接受证明重新取得；保存实际暂停/位置（不用 `_openPlay` 冒充）、等待中的暂停/seek 按 generation/seq 应用；「单开」指一次业务接管，不删现有合法复核重开机制。

## 六、最低测试与验收矩阵
宿主（扩展真实 Session/backend seam 与真实 L/页面链）：无 handler 原测试原样通过零新增等待；窗口建立（通知前已抑制、deadline 前旧 HDR open=0）；永不响应（到期恰一次库自主重规划）；超时后迟到 replace 被拒；App SDR wins（replacement 消费一次、旧 HDR 重开 0、应用回执正确）；仅 `updatePlayer()==true` 不产生 receipt；stop/blocked/superseded 正常返回均不误报 reopened；窗口内 D2（D1 不提交、D2 最新能力、deadline 不刷长）；D/E1 两序（最终源与最新 options 一致、无旧 HDR `setOptions` 重开）；pending 首开收到 D；dispose/换源/target 变化失效一切旧物；能力超集/跨源 census 拒绝或重查；stop 优先；暂停/seek 三边界注入；清理失败新 owner 不进；handler claim 后丢失返回库继续唯一执行。入口：库 `test/hdr_video_session_test.dart`（:1214-1262 已编码无钩子「能力丢失→tone-map，恢复→HDR」默认行为**必须保留**）、App `route_options_lifecycle_test`、`hdr_tier_menu_admission_test`、`player_controller_lifecycle_test`。

真机主场景：marble 播 126 中触发系统级能力变化或在同一 Session 能力入口注入 SDR 快照（等价注入只证控制协议）。正常接管验收：事件/request/source intent/options/最终 generation 可关联；原 126 源事件后实际重开 0；`toneMapSdr` **执行计数** 0（不以字符串出现次数冒充；`baseLayerConvert` 亦可能是合法 HDR→HDR 路线）；恰一次 SDR backend open；同一 SDR source/generation `phase=applied verified=true`；硬解、持续出帧、菜单、恢复位置/暂停符合预期；记录事件至首个 SDR 可见帧耗时与黑屏窗。故障场景：handler 不响应→超时默认重规划；决策中退出；D→E1、E1→D；快速 HDR→SDR→HDR；SDR open 被既有 decoder review 拒。**已知阻断分账**：marble/ugg SDR AVC 复核失败本仲裁不能修复——零 tone-map、单次 SDR open 成立但无 applied 应记「仲裁通过，端到端失败」。

## 七、风险与 V2 复核重点
假回执（Future 完成/UI 档位/`updatePlayer()==true` 不授权 reopened）；超时后迟到副作用（`.timeout`≠取消，最终开源入口验证一次性凭据）；D/E1 死锁或丢配置；pending 工作漏口（只阻 handler 自主 `_open` 不够）；跨源能力污染；预算洗白（hook 重入/重复事件/重建 Session 不清终止失败）；owner 混同（仲裁 token≠Surface lease≠复核证明）；默认行为回归（无 handler/hdr_lab/non-Android/options merge）；降级公理的故障例外须入 API 文档与验收说明；1 秒窗口/30 秒 watchdog/黑屏时间/事件频率均未实测。

**最低可行推进顺序**：真实 Session fake backend 做「超时旧行为、SDR claim wins、迟到被拒、D/E1 交错」四组可重复反例与正例 → 接页面强回执 → 构建同候选 marble 验证；涉及提交权、代次失效与终止失败不变量，实施前后分别交 V2 独立检查。
