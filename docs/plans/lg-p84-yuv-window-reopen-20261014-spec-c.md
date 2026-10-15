# 方案 C 裁决书（YUV arm 生命周期归生产库所有）——Specialist 原文归档

> 归档说明：2026-10-15 由 Specialist（team-specialist）就"lab 预开 arm 在 LG 毒化 texture 路由（lgh7-sdr VO 死亡）"所作架构裁决原文，供 V2 审核逐条追溯。状态标注为"只读设计建议，不是实施或终审"。V2 审核以本文为设计基准；实施=工作树 hdr_yuv_window_arm* + output_slot 钩子 + coordinator attemptCleanup + vendor 插件通道 + lab 退役。

## 裁决

**选 C：由生产库的 session/backend 按"本次实际执行的 route"管理 arm，放进 coordinator 的串行副作用事务；A、B 不作为正确性方案，D 留作后续原生防御。**

建议拆成两个明确交付边界：

1. **本批必须完成**：路由级 arm 生命周期进入 `media_kit_video`，移除 lab 页每次 open 的预 arm；保留既有 owner-bound 优先、legacy FFI 回退模型；合入已另派的 lab token 接线修复。解决 LG SDR 硬回归及标准 lab 的 C4 执行。
2. **生产 owner 自动管理另包完成**：不是只差随机 token，而是涉及 single-open 限制、配置变化、自动重建及 bridge 再初始化。不要把本批"生产库具备 arm 执行能力"宣称为"普通生产调用已完整支持 C4×YUV"。

本批也需要 **V2 独立审核**。原因不是跨文件，而是实际改变了**进程级原子的授权存活范围、跨 attempt 清理和非 YUV 输出隔离**这些关键不变量。

## 一、源码核查后的三个重要修正

### 1. B 所依赖的 `HDR_SESSION_PREDICTION` 不是可等待的路由执行事件

实际链路为：

- `media_kit_video/lib/src/hdr/hdr_video_session.dart:707–772`：`_prepare()` 规划后调用 `_publish(report)`。
- 同文件 `:1584–1587`：`_publish()` 更新 `ValueNotifier`。
- `media_kit_hdr_lab/lib/tests/01.single_player_single_video.dart:3866–3888`：页面的 report listener 打印 `HDR_SESSION_PREDICTION`。

因此要区分：report listener 的调用是同步通知；listener 内启动的异步 `EnableYuvDiag` 不被 session 等待；真正的 `session.events` 是默认异步 broadcast（session `:342–343、1589–1614`），同样没有 arm ACK 屏障。即使日志顺序总显示 prediction 在 configure 前，也不能推出 vendor arm 完成先于 VO 初始化。

此外 `_prepare()` 在副作用队列外运行。新请求的 prediction 可以在旧请求仍执行时发布；在 listener 里 arm，会把新请求的副作用写入旧请求窗口。

### 2. 安全 arm 点不能只放在 `configure()` 开头

生产 backend 的 `hdr_player_backend.dart:513–547` 在 `prepareOutput()` 内已经调用 `outputSlot.ensure()`，并可能创建 controller、等待 Surface 绑定。controller 真正写入 `wid/vo` 的地方是 `video_controller/android_video_controller/real.dart:812–850`——这里先写 `vo=null`，再依序写 size、wid、目标 vo。输出绑定期间即可触发 VO 初始化，不应把"configure 开始"当作最早消费边界。

### 3. token 修复不止改生成条件，且不能直接泛化成生产 owner

页面 `:2872–2880` 生成 owner 并构造 `experimentConfiguration`；`:2988–2992` 普通 `HdrVideoSession` 仍传入 `configuration.value`，不是该配置——token 工包必须核验标准构造路径是否真正传 token 到创建参数。另 `hdr_video_session.dart:435–440`：配置含 `lgExperimentOwnerToken` 就启用一次 open 限制；`:1377–1382、1414–1417、1448–1451` 同时拒绝配置控制和自动 replanning；`media_kit_hdr_lab/lib/common/android_hdr_convert_experiment.dart:4–47` 的 `AndroidLgSingleOpenOwner` 自身也消费一次机会。能力门控下给所有 LG session 塞这种 owner，会额外改变 SDR/P5/HDR10 的 session 生命周期。（实施处置：single-open wrapper 已钉回 VISUAL278 define，标准构建持 token 走 plain open——见工包报告。）

## 二、A—D 逐项评估

| 方向 | 裁决 | 理由 |
| --- | --- | --- |
| A：hint 先验门 | 不选 | 只能绕过一部分 SDR 首开；wrongHint/noHint、review 后重开、候选切换均可能令 hint 与实际载体不一致；不满足"非 YUV attempt 不存活"。 |
| B：prediction 后置监听 | 不选 | 不是 awaited 执行钩子；规划在串行队列外。改成队列内 awaited hook 本质已是 C。 |
| C：session/backend 管理 | **主选** | plan 已确定，能与输出创建、重试、review-reopen、rollback 共用执行顺序；天然覆盖 wrongHint。需细化为"输出创建前 arm＋attempt 终结 disarm"。 |
| D：fork 收窄消费 | 后续防御 | fork 只拿到 ANativeWindow 不知道 Dart route（context_android.c:1329–1347 只读全局原子）；可靠实现需显式 carrier 标记，且不满足非 YUV open 原子为零。 |

## 三、本批实施级方案

1. **一个 route 判定，一个配对资源管理器**：`isYuvWindowRoute(route)` 后执行完整 `validate(route)`（hdr_yuv_presentation_contract.dart:92–136），不能仅检查 hwdec。新增可注入测试的 YUV arm 管理器（建议 hdr_yuv_window_arm.dart），管理**一对原子**：`mkvendor_set_diag_dataspace(0x11C60000)` + owner-bound YUV arm（拒绝/不可用按既有规则回退 legacy FFI）。缺库、缺符号、配对失败时明确拒绝 YUV attempt；非 YUV 路由不因缺 vendor 插件失败。
2. **arm 必须在旧输出退休之后、新输出初始化之前**：`hdr_output_slot.dart:39–78` 的 `HdrOutputSlot.ensure()` 增可等待内部准备钩子；替换输出=旧 controller disposeForRebuild 完成→钩子→create/publish/waitReady；复用=钩子→复用；钩子失败不得创建新输出。依据：旧 Surface owner termination 会清除 legacy unbound arm（LgPqDataSpaceExt.java:209–223）；输出绑定期间即触发 VO 初始化（real.dart:812–850）。
3. **清理单位必须是 execution attempt**：`hdr_open_coordinator.dart:339–652` 为每个执行 attempt 建 awaited 终结屏障（candidate retry/review-reopen/YUV→另一候选/supersede/失败回滚全覆盖）；执行顺序=旧输出停止/配置恢复→route 校验→旧输出退休→本 attempt arm→新输出创建/绑定→configure→media open→review→本 attempt disarm 完成→返回成功或开始下一 attempt。**不能在 backend.open() 返回即 disarm；不能在外层 finally 才 disarm；coordinator :646 直接 result.complete 必须改为清理成功后完成**；cleanup 失败保留 cleanup debt 阻止后继输出初始化；attempt 身份不能只用 session generation（同 generation 内多次执行；迟到旧 cleanup 不得清掉新 arm）。
4. **库侧不能依赖 lab MethodChannel 名称**：生产 vendor 插件（MediaKitAndroidDataspaceVendorPlugin.java:28–67）需补控制入口，转调既有 `LgPqDataSpaceExt.enableYuvDiag(token,generation)`，保留 legacy FFI 回退；并验证 takeOverSlot 后控制的是实际参与 owner 注册的同一 extension 实例。
5. **lab 退役范围**：移除生产必需的配对 arm/disarm 责任与设备预查询门；保留 OES 采样/readback 诊断、version marker 采集、明确的诊断配置冲突检查——诊断不得成为生产 YUV route 初始化前提。

## 四、owner 与 production 缺口的处置

本批保留：token→ASCII owner key 派生、platform-view generation、owner-bound 优先及拒绝后显式 legacy 回退、A2 termination 匹配语义、bridge 初始化只接受有效 owner。**token 存在、bridge 已初始化、vendor ledger 已授权、YUV arm 已绑定，是四件不同的事。**不得向普通 YUV 路由虚构 `routeLocked=true/acceptNonConformant=true`。

生产完整支持另包完成：普通 YUV output 自动分配 owner、bridge identity 与旧 Visual278 single-open 授权区分、token/generation 更换参与输出复用判定、重开/重试/Surface 重建后重新初始化 bridge（mediakit_surfacetexture_bridge.cpp:225–233：shutdown 清 initialized/owner 状态）。本批交付口径=**库拥有 route-scoped arm 执行；具备有效 owner 的路径可执行 C4；普通生产调用的 owner 自动生命周期仍是独立阻塞项**。未提供有效 owner 的生产 YUV 路径应提前明确失败。

## 五、测试与实机判据增量

Host 测试最低覆盖（hdr_open_coordinator_test / hdr_output_slot_test / hdr_yuv_presentation_contract_test / hdr_video_session_test / lab android_hdr_surface_texture_poc_test）：

- YUV capability=true 但 texture/embed route：零 arm；
- YUV route：arm ACK 完成前不得初始化输出；延迟 arm Future 不穿透屏障；
- 旧输出 unregister 清全局原子，证明新 arm 在其后；
- wrongHint/noHint 导致 review-reopen，逐 attempt 正确开关；
- YUV attempt 后接非 YUV attempt，两原子均已清零；
- 任一阶段失败、supersede、cleanup 失败、重复 dispose；
- stale attempt cleanup 不影响 successor；
- bound 成功、拒绝→legacy、通道缺失→legacy、符号缺失→明确失败；
- 非 YUV 设备无 vendor 插件仍保持原行为。

**进程级原子约束原文**："进程级原子仍意味着不能默认支持多个独立 session/engine 并发初始化输出。本批必须在既有限制下串行化或拒绝冲突；单个 coordinator 的队列本身不能证明进程级互斥。"

LG 实机最小新增矩阵：①SDR 冷开（无 config49 分支、VO 出帧）；②P8.4 冷开（owner 初始化→arm→config49→dataspace apply→复核样本 `hwdec-current=surfacetexture`→verified→open 末 disarm）；③同进程 P8.4↔SDR 互切（旧 owner teardown、两原子残留、token 机制未误引入 single-open）；④P8.4 配 SDR hint/无 hint（初始 texture 阶段不 arm，review 选到 C4 才 arm）；⑤P5、HDR10（embed 不 arm 的本轮证据）；⑥失败后恢复。每轮记录 session generation+attempt ordinal+route+platform generation+arm 方式+cleanup 结果（不记原始 token）。

## 确定与待确认边界

源码可确定：B 无 awaited 屏障；configure-only 太晚；旧 owner termination 清 legacy arm；生产 vendor 通道缺失；实验 token 触发 single-open/replan 限制。仍需实测：token 接线后首次真实 surfacetexture 复核表现；disarm 后持续渲染与窗口重建；embed 惰性；重复 open 的 bridge 重新初始化闭环。不建议在上述证据出现前修改解码复核预算或放宽 mismatch。
