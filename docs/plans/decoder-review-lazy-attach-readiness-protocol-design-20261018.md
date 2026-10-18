# 解码复核门「直连载体懒附着」readiness/实例身份协议扩展设计 v1

> 来源：Specialist-P1 设计（2026-10-18，只读审查，agent_55bf3bc3）。基线：库 `0a212785`、App `f6a9c1532`。状态：**「需先补证据」**——当前不建议直接实施「把目标两轮改为放行」的门语义补丁；可先进入原生实例身份取证、协议数据结构与负例夹具实施；发布白名单扩展须在同实例证据闭合后交 V2 复核。

## 结论：需先补证据

决定性原因两点：

1. **当前代码没有把空串登记为 decoder 基线**（`hdr_decoder_review.dart:465`（标准1基行号 466）仅 `value.isNotEmpty` 时写 observed）。目标日志中 `android-mediacodec-info 空→有` 被拒，按现有控制流说明**此前已登记过非空值**，不能称「合法首发布被空串基线误伤」。
2. **本次指定 marble、ugg 两轮均存在拒绝前再次创建组件的原始日志**：「本次问题就是同实例懒附着」尚不成立，至少混入实例更替。若继续要求拦截真实实例更替，就不能通过扩大首发布规则让这些记录直接转为成功。

应修订的问题描述：「未见过有效值」与「此前有值、当前暂缺」必须显式区分；不得把后者改判为首发布；现日志不打印历史基线导致两者易混淆。另：现有跨轮基线不覆盖全部 `video-params/*`，不能把「所有端点跨轮完全稳定」写成已有保证。

## 一、事实核对与证据边界

### marble（`/tmp/w5-verify-20261017-policy/marble-B2f-hdr-off-r1/logcat.log`）
- :3830 plan `selected=sdrDirect ... vo=gpu-next hwdec=mediacodec ... topology=texture`。
- :3939 `QC2CompStore: Created component(c2.qti.avc.decoder) id(997)`；:5440 同名 `id(998)`——同一打开窗口两个 vendor component id，随后 :5742 门拒（`changedKey=android-mediacodec-info changedA= changedB={"api":1,"mime":"video/avc","codec":"c2.qti.avc.decoder","native-dv-active":false}`）。
- 尚未证明：Dart 已登记配置精确对应 997、B 半对应 998（缺库内可关联实例 token）。**不能凭组件名相同判同实例懒附着。**

### ugg（`ugg-C2-BV1uZ4y1U7h8-r1/logcat.log`）
- :398 同 plan；:490/:496 首次 `makeComponentInstance(OMX.qcom.video.decoder.avc)`、`component_init`；:641/:643 `component_deinit() complete` / `Exit OMX vdec Destructor: fd=15`；:652/:665 二次 `makeComponentInstance`+`component_init: fd=15`（**fd 复用，fd/地址不能充当实例身份**）；:519/:675 surface generation `23405569→23405570`；:690 门拒（`iter=11`，`changedA= changedB={"codec":"OMX.qcom.video.decoder.avc",...}`）。
- 未验证：二次创建的触发原因及其与每轮 Dart 基线的精确关联。

### 原生事实（实际读取 FFmpeg `d4bb79394b`、mpv `9141961531`；未重核候选 JAR 与两源码树字节绑定）
- `~/src/FFmpeg/libavcodec/mediacodecdec.c`：:74-79 清 `native_dv_active`/MIME/组件名；:109-117 close 另行 `ff_mediacodec_dec_close`；:657-665 init 成功后发布 runtime facts（全文件仅 :663 一处 publish，**成功帧无自动重发布**）；:812-819 一般 receive 错误只 clear；:822-833 flush 错误也清 facts。
- `~/src/mpv/video/decode/vd_lavc.c` :1482-1522：缺 MIME 返回不可用；导出 API 1 只有 `api/mime/codec/native-dv-active`。
- 事实：「info 消失」≠释放实例；当前属性**无 incarnation/configuration generation**。未验证：目标两轮每次空值来自 receive 错误、close、重 init 还是其它时序；「同实例清空后成功帧自然恢复」不能据当前源码证明。

### 既有裁决核对
- Q1 保留门/不批预等待/App 零补丁：App 会话档 :12 核到（库档顶部为较旧 Current State，未虚报库档原文核证）。
- 46f21a0b→0c57dcd9 契约史：库 `TASKS.md:33-37`；当前实现 `hdr_decoder_review.dart:330-472` 相符；LG 修订已扩至 `surfacetexture`。
- 消失不得重授权、发布轮重采样：实现与 `TASKS.md:25-35` 支持。
- 同名组件不是实例证明：门 :310-325 附近注释明确承认；配置模型无实例字段。
- sdrEmbed 不解决 API≥26 texture direct：`hdr_strategy_realizer.dart:145-200,610-639,717-718`。
- 需修订的历史措辞：配置一致只支持「与附着解释相容」，不支持「非解码器变化已定案」。

## 二、机理模型：实例时间线，三类身份分开

1. **源身份 S**：Player 实例、playlist entry、file-loaded epoch、URI 一致性——`openedAfterEpoch/identityOk` 证明这一层，不证明 MediaCodec 实例。
2. **解码身份 D**：原生 decoder lineage、MediaCodec incarnation、configuration epoch——组件名/MIME/DV 标志只是配置描述，不是 D。
3. **输出身份 O**：session/attempt、输出 slot/generation、载体绑定 generation；YUV 另受 owner/lease。

同实例证明最低要求：原生生成、不可复用的 incarnation + configuration epoch + 从源打开起不丢失的 replacement/fallback 历史。不能用 Dart 生成的 UUID 为未知原生实例「贴身份」。

| 类别 | 时间线与充分判据 | 判定 |
|---|---|---|
| a. 同实例懒附着 | S/O 不变；D 自创建至附着同 incarnation/configuration；opening→attached；无释放/重配/软解输出；info 首发布、标签 `X→X_mediacodec`、hwdec 未就绪→计划直连值；最终格式与计划一致 | 精确发布规则内登记，**本轮不返回 facts**；后续一致样本才放行 |
| b. 实例更替 | incarnation 变化或 replacement 标志置位；同名同配置也算更替；同实例 stop→configure→start（configuration epoch 变化）不得伪装附着 | 拒，不换基线不重置预算 |
| c. 软解回退 | fallback/software-output 历史；已附着硬解退成 `no`、标签逆向；CPU 帧+config 缺失辅助 | direct review 拒（单独计划的软件路线不在禁令内） |
| d. 事实清空后恢复 | 登记 C→缺失→C；需独立于 facts 的 D 连续、无重配/回退历史；当前 API 1 无法证明 | 首期仍拒；完整协议可支持显式失效/恢复事件，不能裸空值重授权 |

限制：`pixelformat` 为空≠「未发生过软解/未出帧」；两半/跨轮配置相同及 `identityOk=ok` 均不能排除同名同配置更替或 ABA。

## 三、协议扩展设计

### 3.1 新增版本化内部属性 `android-decoder-readiness`（名称由原生工作包定稿；不给现有 API 1 偷加隐式身份语义）

字段组（必须保证）：`api`（严格 schema，未知版本不授新发布权限）、`sourceGeneration`（由 backend 与当前 S 绑定，不能只在首次非空 info 时建立）、`decoderLineage`、`incarnation`（每次真实 create 唯一，销毁不复用，不能是指针/fd/组件名）、`configurationEpoch`（同 incarnation 重配亦递增）、`state`（opening/configured/attached/invalidated/released/software）、`attachmentEpoch/targetMode`（不得由 Dart 从标签猜）、`replacementSeen/softwareFallbackSeen`（黏性，防首次采样前的 X→Y→Y）、`softwareOutputCount`、`factsValid/factsRevision`、`configuration`（与 info 同源）、`transition`（明确的首附着；完整档含失效/恢复原因与编号）。

原生约束：身份记录独立于 `mediacodec_clear_runtime_facts`（清 facts 不得清身份与历史）；真实销毁/重建/软解回退必须留可观察历史；原生同步快照发布（incarnation 与配置同一瞬间）；标量端点采样前后用 readiness 身份包围；producer 无法完整记录中间变化时报 `historyIncomplete` 并拒绝新增授权。

**范围缺口：身份必须在 FFmpeg/mpv 生产者实现，仅改两仓 Dart 不可能构造可靠原生实例证明。原生仓写入授权与工作包由 Lead 另行明确。**

### 3.2 显式历史状态替换「字符串 map 即状态机」
每端点维护 `neverPublished / registered(value, D, publicationKind) / attached(value, D) / failed`（完整档加 `invalidated(...)`）。不变量：空值不登记但历史非空值永不清除；`no` 是非空值不能归入 unknown；基线属同一 S/D/O/attempt；整轮先验证所有变化再原子提交；不因新轮 readiness/标签发布/输出事件重起预算。

### 3.3 精确发布形状
- **P1 `android-mediacodec-info` 合法首发布**：`A=""→B=C` 当且仅当历史 `neverPublished`、C 严格解析（MIME 兼容、普通消费者不接受 native-DV active）、S/D/O 绑定、readiness 表明该 D 首次配置事实发布、无 replacement/fallback/history-gap、其余端点差异独立过白名单。跨轮 `""/""→C/C` 同义。**不允许** `registered(C)→""→C` 称首发布、`→C2`、同名不同 incarnation、readiness 不支持却借新规则放行旧拒绝形状。
- **P2 `hwdec-current no→直连值`**：仅作为**原生声明的初始化占位完成**；计划目标精确为 `mediacodec`/`surfacetexture`（非前缀匹配）；readiness 绑定同一 D 且初次 attachment pending；`softwareOutputCount==0 && !softwareFallbackSeen`；本次 open 从未完成硬件附着；B 值=本 attempt 目标模式；双半配置非空必须相同；完成后重采样，最终 direct 要求 `pixelformat=mediacodec`。Worker 应由 backend 传入**冻结的 review contract**（含目标 hwdec/载体）——当前 gather 无 expected route 参数。
- **P3 跨 hwdec 表观变化的标签附着**：`X→X_mediacodec` 单向后缀（X 非已附着、不重复后缀）；D/configuration epoch 不变；双半+已登记配置一致（或变化仅是 P1）；hwdec 双半相同且=计划值；原生确认该 D 首次 attachment；无其它未解释差异。**不将 `mediacodec-copy→mediacodec`、`mediacodec→surfacetexture` 等已生效模式转换自动合法化**（载体/资源契约，另走受控事务）。
- **P4 消失后恢复：首期维持「裸消失即拒，不重授权」**（两目标轮有换实例证据；无同实例恢复证明）。完整档：native 在失效前/同时发布 `invalidated(D, invalidationId, reason)` → 不返回 facts/不重开/不改路线 → 同 D 成功解码后可核验 `recovered(invalidationId)` 且配置与旧基线一致、无 fallback/reconfigure → 结束 invalidated → 恢复轮不返回 facts、重新采样 → 预算内未恢复即失败。**首期不实施该扩权。**
- **与 0c57dcd9 合并**：统一 `classifyTransition(previous, A, B, readinessEvidence)`；轮内与跨轮同规则；合法附着只超替同 D 的标签/发布状态，不超替 D；所有协议迁移视作发布轮强制下一轮；任一键失败整轮失败；`attachSettling` 状态机替换时清理（当前只写未读）。

### 3.5 会话/owner/lease/超替/失败策略
readiness retry 是同一 attempt 内取证，不是失败后重新 open，不消耗 route candidate；`HdrDecoderReviewFailure` 继续使 `_retry` 返回 null；`failurePolicy.stop` 不削弱；不把实例更替错误包装为普通依赖失败触发 copy/software 候选；`setOptions` 新 generation 只建自己的状态、不继承旧 readiness proof；`_ordinaryReviewSerial` 与 session generation 在 await 后/提交基线前/返回 facts 后复核；owner token/Surface generation/lease 不可替代 incarnation；能力事件段 :1457-1509 不在本工作包。

## 四、两档方案与推荐
- **A 最小恢复分流**：补实例身份/历史观测；仅接 P1/P2/P3；保留裸消失即拒。覆盖：修真正首次懒附着，**不能保证修复目标两轮**（两轮有更替证据）。若无可靠身份生产者，仅改 Dart 不满足要求。
- **B 完整实例身份协议**：A + 显式 invalidated/recovered、配置/绑定生命周期、恢复证据、全采样窗口实例历史消费。覆盖广、native 面大；仍必须拒绝真更替。
- **推荐 A，先取证后扩权**：先分清哪些失败是同实例事实通道失效、哪些是正常初始化附着、哪些需修底层实例重建触发源。「只改空→有」虽代码最少，却不是安全的最小解法。

## 五、测试与验收矩阵
单测位置：`test/hdr_decoder_review_test.dart`、`hdr_decoder_review_diagnostics_test.dart`、`hdr_session_route_options_test.dart`、`hdr_player_backend_review_test.dart`（注意 :224-225 旧 `gatherReviewFacts` seam 与生产 :933 `gatherDecoderReviewFacts` 的区别，不能只让旧 seam 变绿）。每正例配负例（已登记 C 后空→C / 空→C2 / 同名不同 incarnation / schema 冲突；真软解后切硬 / 先硬后 no 再硬 / 超时；无 token / 异 token / 配置代际变 / 逆向标签；X→Y→Y / 首采样前更替且黏性标志存在；多项同轮发布中任一不合规；完整档 typed invalidation→recovery 的负例；预算/重采样/新 generation/`failurePolicy` 不可洗白）。原生单测：同名两次 create 得不同 token；指针/fd 复用；clear facts 不清身份；同对象重配递增代际；读取间隙发生 fallback/replacement 仍捕获；未知协议 fail-closed。

真机矩阵（建议最低轮数，非统计结论）：marble AVC 4K/1080p/720p 各 ≥3 冷开+3 重入（`gpu-next/mediacodec/texture`，禁止 copy 计通过）；ugg ≥10 次冷开记录全部试次；marble HDR/126 plain-hvc1 与 dvh1 native-DV 分开各 ≥3；LG copy 组用明确要求 copy 的库测试配置（sdrEmbed 默认另测，不把 embed 通过算 copy 回归）；LYA AVC direct 720p/1080p/4K（不在线记待验）；DV 轮（LG surfacetexture 同轮发布、LYA reshape、marble native-DV）；生命周期（setOptions、同 URI 重开、快速换源、后台返回/输出重建、dispose 迟到发布）。正例判据：同一 S/D/O 身份时间线、`outcome=success`、零 `HdrDecoderReviewFailure`、最终 route/hwdec 与目标一致、连续帧推进、HDR/DV 另有 SF/激活证据、零 ANR/FATAL。故障注入应期待拒绝/停止且无 applied。**原始目标日志先作为拒绝/分类夹具保留——若身份 trace 证实真实更替，正确门实现仍应拒绝；产品恢复须来自底层避免更替，不能改验收判据。**

## 六、日志设计与最低补证据顺序
现日志仅 gather 出口一次且截断（`hdr_output_diagnostics.dart:254-272,298-320`）。新增受限状态迁移记录：S 非敏感编号、session generation、attempt、incarnation/configuration epoch、output binding generation、`registeredInfoPresent` 与首次登记轮次、`transition=first-info/first-attach/invalidate/recover/replace/software-fallback`、前后配置摘要、原生事件序号、历史完整性、预算 elapsed/remaining、failure kind。不记 URL/CSD 原文/指针；诊断 sink 异常不得改变门结果。

补证据顺序：①原生 create/configure/start/clear/close/fallback 边界生成稳定身份与原因记录；②同轮关联 Dart baseline 登记，复跑 marble 1080p/4K、ugg 失败样本；③证明至少一个真实 a 类、一个 b 类（若要恢复支持，必须取得 d 类同实例成功恢复）；④在不变门的候选上完成分类，再定 P1/P2/P3 是否覆盖有效子集；⑤若失败主体仍是 b 类，停止扩门，另开「原生解码/载体重建触发原因」工作包。

## 七、V2 必查与明确不做
V2 必查：incarnation 来自真实 create 生命周期（非标签/地址代理）；configuration epoch 覆盖同对象重配；X→Y→Y/ABA/首采样前更替被黏性历史捕获；`no` 保持软件观察含义（仅强证据下标为初始化占位）；首发布/跨轮结算/恢复共用一个状态机且无换基线丢历史；普通门与 native-DV owned consumer 隔离；未知 API/缺 token/无恢复收据/超时/超替 fail-closed；`failurePolicy.stop`、owner/lease、源码构建来源保持；不把 review success 误当出帧/HDR/长期稳定性验收。

明确不做：无设备名判断；不改 App（业务代码/偏好/等待/重试/门绕过零补丁，新库候选构建接入≠App 修补）；不预等待不加预算；不把 AVC 改 preferCopy；不批准永久设备例外；不动能力事件段；不自动重建实例后清空基线重计首发布；不留旧 facts 伪装恢复。

## 实施顺序
**P0 身份取证与精确夹具 → P1 确认真实同实例子集 → P2 实施 A 档精确发布协议 → 独立 V2 → 最新源码构建与真机矩阵。**
