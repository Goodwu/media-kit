# 受管 YUV 输出：分层解耦与生命周期设计约束

契约 ID：`MK-ROUTING-20261011/LAYERING-20261015-r1`。日期：2026-10-15。
状态：用户要求落盘的后续实现约束；文档已建立，不代表自动 owner、原生输出或设备验收已完成。
适用范围：media-kit 与 PiliPlusX 的普通调用路径，包括 YUV 输出的首次打开、重开、输出复用、Surface 重建和释放。

## 1. 权威范围、现状与接续入口

本文是本工作包的库侧规范。PiliPlusX 的 [App 对接契约](https://github.com/Goodwu/PiliPlusX/blob/routing/MK-ROUTING-20261011/docs/plans/media-kit-layering-integration-contract-20261015.md) 通过相同 ID 引用本文，不维护第二套 owner 协议或路由表。相同语义约束的后续变更须同步两仓文档、测试映射和 PR 交接。

继续 [中央执行方案](media-kit-routing-implementation-20261011.md)、media-kit PR #4 和 PiliPlusX PR #1 的原 `routing/MK-ROUTING-20261011` 分支。中央方案 §13 的现行范围不变：HDR10+/Vivid 本期仅静态 PQ/HLG 兼容，动态 C1/C2/B1—B4 仍延期。不得用本工作包恢复已延期的动态映射或增加 YUV10 配方。

[历史方案 C](lg-p84-yuv-window-reopen-20261014-spec-c.md) 保留为阶段性设计与审计证据。它的按实际 route 管理副作用、逐 attempt 清理及进程初始化互斥继续保留。其“普通 owner 另包”“legacy 回退”“创建前 arm”等阶段性接口，不是本次通用生命周期的最终 API：与本文不同处，仅在后续受管 owner 工作包的目标设计上以本文为准；不倒改历史实现或验收结论。

记录时观察到库 `c7247139ee2865ae43f8d0663fc77a1aa8baea91`、App `3bd3a07b1a214a6789791b266624c6ddc080932d`。这些 SHA 仅定位阅读基线，不钉定未来测试输入。该库中 Session 从 `lgExperimentOwnerToken` 取 owner，缺失时 YUV 路径返回 `yuvWindowArmUnavailable`；已有 Surface 身份、释放协议、输出槽和进程门不应重复开发。新约束的正向实现、自动化与真机验收均待后续完成。源码层历史通过不等于普通 YUV 入口已可用。

## 2. 分层职责与依赖方向（L01—L03）

### L01：应用只表达需求，不承担底层所有权

PiliPlusX 提交片源及来源证据、完整 VideoSourceSpec、显示目标和不可变有效播放选项，消费库的实际结果。不得创建、持久化、传递或恢复 YUV owner token/lease，不调用厂商控制通道、JNI/FFI arm，不依据 SDK/机型/指纹/config49 做路由判断，不在 report listener 中预 arm。正常 Flutter 挂载、更新、卸载视频视图仍是应用职责，但不需要额外的厂商初始化步骤。

### L02：查询/规划与有副作用的执行分离

沿用 VideoRouteCapabilities.query(target:, sources:) 和现有 planner/realizer/candidate 定义。查询只读取能力与输入事实；规划为纯计算，不创建 Player、decoder、Surface、EGL 或获取运行期许可，不为预测而触发 vendor arm/bridge 初始化。设备声明、实现可用性、输入支持、执行成功、呈现验证必须分开。缺实现保留候选和结构化错误，不假装设备不支持，不用成熟度、验证标签或启用开关删候选。

### L03：接口由通用层定义，具体实现单向依赖接口

| 层次 | 负责 | 禁止承担 |
|---|---|---|
| PiliPlusX | 业务片源、偏好、显示目标、视图挂载、结果展示 | 厂商规则、owner/arm、另一套 C1—C4 表 |
| 能力查询/规划 | 事实快照、候选及错误契约 | 分配资源、修改 native 状态 |
| Session/coordinator | open/复核/重试/终结清理的事务编排 | LG token、config49、私有 dataspace 数值、厂商类/通道 |
| Android backend/输出生命周期 | 实际输出身份、准备与激活屏障、重建、释放确认 | 根据 App 画质编号选策略或擅改 HDR/SDR 目标 |
| Vendor 呈现实现 | 精确适用性与私有 ABI 安全检查、具体呈现准备/撤销 | 选择片源、改变偏好、另行规划或静默换路由 |
| Native bridge/mpv | 解码导入、渲染、原生资源及必要消费校验 | 依赖 App 页面、报告监听或诊断预调用 |

通用 Android 输出模块定义范围有限的呈现生命周期接口，vendor 实现通过装配/注册接入。平台装配处可以引用具体实现；Session、planner 和通用执行逻辑不得按 `lg-pq` 等厂商 ID 分支。实现 ID 可用于诊断和匹配同一已注册实现，不能成为另一张设备策略表。通用协议允许表达真实的新能力，但新增同类设备不得迫使 App/Session 增加设备分支。

不是把 `registerLgExperimentSurface` 改名即可：普通接口不得继承 Visual278 授权、single-open 或 `routeLocked/acceptNonConformant` 实验语义。不得把全部控制逻辑迁往 Java 来代替分层；Dart/FFI 可以保留，跨 engine 的进程级事实放在能够真正共享和校验它们的原生层。不为形式分层新建庞大框架或重复调度器。

## 3. 数据与资源身份（L04—L05）

### L04：不可变输出要求不等于运行期授权

输出要求描述载体、传递函数、范围、导入方式及必要创建参数；规划、执行与报告消费同一份要求。owner、lease、Surface 句柄、初始化阶段和 cleanup debt 是临时资源状态，不写入用户播放配置、持久偏好或通用公开请求。App 诊断中不输出原始 token、裸指针或原始释放凭据。

保留 HdrOutputContract 的请求/观察分离，但普通路径不再通过它转交 `lgExperimentOwnerToken`。厂商具体实现参数只在 backend/适配器边界内解析；无需为了本工作包重写全部已有 mpv 路由字段。

### L05：复用现有身份，分清三种寿命

| 概念 | 唯一责任 | 结束条件 |
|---|---|---|
| Surface 资源身份 | 沿用 AndroidSurfaceAccountId 的 handle、controller generation、viewId、surfaceGeneration、wid；结合真实 engine/会话上下文校验 | Surface 失效后停止使用；资源引用按原释放协议回收 |
| 初始化 lease 与配对 arm | 授权本次执行 attempt 或受管重建事务触发初始化 | 对应事务的实际尾部及清理屏障完成；open attempt 保留现有 review 后终结语义 |
| 呈现/decoder 使用授权与释放记录 | 将实现的准备结果绑定到真实输出；保留原生引用/释放凭据的准确归属 | producer 停止及相应 ACK 完成后回收引用/记录，不把 attempt disarm 当成资源已释放 |

不得用一个 session token 同时代表三者，也不得另建一个独立决定 Surface 归属的 ledger。厂商的原生校验记录应关联现有权威身份，不得自行转移资源归属。跨 engine、跨 Player 地址复用、同 generation 内不同 attempt 都必须能区分；仅比较 token 或 wid 不够。失效 Surface 的引用尚被保留，只能表示等待安全回收，不能授权继续渲染。

## 4. 初始化、重建与清理协议（L06—L09）

### L06：建立依赖屏障，不把某个回调当作通用协议

概念阶段是“取得初始化许可 → 退休需替换的旧输出 → 发布可挂载但未激活的输出对象 → 登记真实 Surface → 完成该实现所需准备 → 激活 producer → 复核 → attempt 清理”。这不是确定的 API/方法名；dataspace、bridge 与 arm 的内部先后须按真实 native 消费依赖细化。

必须满足以下不变量：

- 进程初始化冲突在旧输出退休之前拒绝；不得先破坏当前输出再发现无授权。更早共享状态写入也必须核对其隔离边界，不能从一处 gate 推断整个事务零副作用。
- 创建/发布 controller 供 Flutter 挂载不等于激活输出；在依赖授权的消费者启动前保持未激活状态。保留 publish-before-waitReady，避免等 Surface 才发布与等挂载才有 Surface 的循环等待。
- 每步 dataspace、bridge、arm、EGL/VO 操作先满足其所需的真实身份与许可；实际消费者不得越过对应准备 ACK。bridge 初始化与 arm 的具体先后按依赖确定，不把整个准备过程要求的 ACK 反过来作为自身前提。不得先有副作用再补授权。
- 当前 Java 会在 SurfaceAvailable 前申请初始 dataspace。后续实现必须先确定其与 arm 的依赖；需要拆阶段则明确拆分，不能无条件将 arm 移到 SurfaceAvailable 之后，不能忽略初始 dataspace 失败。
- 旧输出退休可能清除旧 arm；新 arm 必须在相关旧输出退休完成后建立。每次 await 后重新核对 attempt、取消状态和完整输出身份，失败 ACK 或迟到回调不能激活输出。
- Session/coordinator 等待通用 backend 阶段和 cleanup；具体资源管理器归 backend/输出层，通用 Session 不直接驱动 LG arm。内部屏障不是 App 可任意注入的厂商回调。

平台回调只推进已登记操作，不重新选路、不重入 session.open，也不把完成动作排到正在等待该动作的同一串行队列后面。timeout 只说明等待超时，不证明底层操作已取消；必须有迟到处理、资源保留与可核验终结。

### L07：普通路径必须取得真实的绑定授权

预校验检查路由契约和建立受管输出的能力，不要求 App 先提供 owner。执行阶段由库预约/登记/绑定；真正失败仍保留 `yuvWindowArmUnavailable` 或兼容的结构化实现/阶段错误以及原始 cause。不能删除检查、构造假的实验授权或用随机 token 代替登记。

新的普通受管路径不得在 owner-bound 拒绝后退到无主的 legacy FFI arm 并报告成功。历史实验入口可保留独立验证，但不得成为普通入口的必要条件；迁移必须有正反例，不能以新启用开关隔离。FFI 本身不是问题，问题是缺少可归属授权。ACK 的语义必须由实际执行或读回证据支撑；channel true 不等于 native 已准备，更不等于面板呈现成功。

### L08：重开、复用与 Surface 重建使用同一资源协议

保留现有输出槽的复用机制。请求契约相同还必须证明当前 Surface/使用授权有效、bridge 状态可复用且上次事务无欠账；需要 reinitialize 不自动等于必须重建 Surface。不得把每次 open 强制重建设为最终规则。确需局部强制替换时说明触发条件并补性能与生命周期测试。

首次 open、候选重试、review-reopen、切源、HDR/SDR 切换、设置/显示变更、全屏/前后台导致的 Surface 重建以及 dispose，均覆盖自动 owner 生命周期，不继承实验 single-open 限制。open 已返回后的 Surface 重建仍要取得自己的受管初始化许可，不能复用已结束 attempt 的 lease/闭包；没有重建就不凭空触发全屏重开。

旧 attempt cleanup、旧 Surface destroy 和旧 ACK 只能处理其真实身份；不能撤销新 Surface 或另一 session 的 arm。bridge shutdown 后的重新初始化与使用授权转移须依据真实状态实现并测试，不把预分配 generation 当成真实 Surface 已存在。

### L09：清理完成与资源回收分别有证据

open attempt 的配对 arm/WRITE lease 沿用终结清理屏障：不得在 arm ACK、首次 bind 或 backend.open 返回时提前释放，应覆盖实际初始化尾部、open 和 review。其他受管重建事务也必须覆盖自己的实际尾部与失败清理。

解除配对 arm、处理 native 使用授权和释放进程 lease 都须有明确结果；无法证明安全结束时保留 cleanup debt 与对应阻塞，不只打印日志后宣称成功。cleanup 失败不得直接降到另一路由以绕开债务。使用现有 producer 停止和两阶段 Surface 释放确认，支持同身份幂等重试、丢失 ACK 和重复回调。安全释放确认前不回收仍被 producer 引用的 JNI 资源。

engine detach、会话销毁、进程恢复须按仍存活资源和执行者进行处理；仅移除 Dart 对象或通道不能当作 native producer 已终结的证据，不为解锁而盲清全局状态。

## 5. 全局状态、变更范围与报告（L10—L12）

### L10：分层解耦不等于任意并发隔离

当前 native arm 为进程级共享状态，现有 ProcessOutputInitGate 仍是必要保护；复用/扩展它，不再增加互相竞争的全局门。所有可能消费这些全局状态的输出初始化与重建都须纳入协议，包括与普通 VideoController 的并用边界；确实无法纳入的入口必须明确拒绝或标注不支持，不能默默旁路。

非 YUV 输出不 arm，移除 vendor 实现时与其无关的路径应保持可用；但进程内确有 YUV 参与者且 gate 不可达时，不能盲放行。跨 engine 的混合注册配置必须有明确覆盖或明确限制，不能用一个 engine 缺插件推断整个进程没有共享状态。

不把初始化 WRITE lease 误当作播放期 bridge 的并发许可；若 bridge 有活动 decoder window 限制，应独立校验和报告。未来若要求不同窗口/播放器任意并发初始化互不影响，需要按窗口或渲染上下文隔离 native 状态并重新验收，届时可能修改 mpv/native 接口；本工作包不预称已实现该隔离。

### L11：最小必要范围，不再全链路重写

主要修改范围：media_kit_video 的 Session/backend 内部边界、Android 输出生命周期、vendor 呈现实现及必要 bridge 状态接口。复用现有查询、planner/realizer、coordinator、输出槽、Surface 身份与释放协议。不默认修改通用 Player 核心、FFmpeg、mpv、libplacebo、Darwin/OHOS；只有实际依赖证据表明接口不足时，单列最小变更及受影响测试。App 只作必要接口消费/依赖更新和回归，不接管库侧缺口。

整个项目仍是同一套实验性候选和默认路径，不划分生产/实验可行集、不新增启用开关。“普通受管路径”是调用与资源协议的区别，不是成熟度许可；尚未实现在路径内明确报错。HDR 失败不隐式转 SDR，明确 HDR off/require SDR 是独立用户请求。

### L12：状态和验收不得互相替代

输出要求、声明能力、准备 ACK、绑定成功、decoder 复核、实际呈现与设备颜色/性能证据分别记录；不能把 opened/bound/route prediction 标成 presentationVerified。HDR10+/Vivid 静态兼容不显示动态映射成功。正常报告保留失败阶段/原因、候选和输入归属，敏感原始 owner/指针/凭据仅在必要受控诊断中处理，不能泄漏到 App 持久配置。

源码 CI、完整当前原生包、APK/ABI/签名/Android-Pink parity、设备 HDR/持续性能独立验收。负向“正确报错”通过不关闭普通冷开等正向用例；未进入目标路径、缺设备/样本、skip、缺证据不能记功能通过。

## 6. 架构与功能验收矩阵

以下是必需的验收要求，不是本次已经新增或执行的测试。后续实现必须把 case ID 映射到实际测试路径、运行命令、输入身份和结果；状态当前均为待实现/待执行。

| case ID | 约束 | 验收要求与反例 |
|---|---|---|
| L-A01 | L01/L03 | 普通 App/Session 不引用 vendor 类、通道、arm/token；禁用诊断、不提供 token 仍能走正向入口；不得只扫描文件名 |
| L-A02 | L02 | query/predict 的替身与调用计数证明零资源分配、零许可占用、零 arm；unsupported、unknown、notImplemented 分别验证 |
| L-A03 | L03/L10 | 移除 vendor 依赖后通用视频模块仍编译、无关路径仍运行；需要该实现的候选保留明确错误 |
| L-A04 | L03 | 用测试呈现实现替换 LG，无需改 Session/planner/App；新增同类设备只改实现与注册；真实新能力可扩展协议 |
| L-A05 | L04/L05 | 请求/配置序列化不含运行期 owner/lease；身份完整比较；跨 engine 同值/句柄复用不会错归属 |
| L-A06 | L06/L07 | 普通首次 YUV 冷开：真实登记、准备 ACK、激活严格有序；延迟 ACK 阻止依赖操作，拒绝 ACK 不落无主 FFI |
| L-A07 | L06 | 初始 dataspace、bridge、EGL/VO 每个失败点与顺序反例；保留挂载后等待，证明没有循环等待/队列重入 |
| L-A08 | L06/L09 | 任意 await 处 supersede/dispose/timeout；迟到动作不激活新源、不误释放他人、底层未结束不算取消完成 |
| L-A09 | L08 | 同 session 反复 HDR→SDR→HDR、切源、设置与显示变更、review-reopen；无实验 single-open 限制，未恢复隐式 SDR |
| L-A10 | L05/L08 | 兼容输出可安全复用；失效授权重建/重新初始化；Surface 重建取得新许可，旧 destroy/ACK/cleanup 不影响新身份 |
| L-A11 | L09 | 配对部分失败、native 撤销失败、lease 释放失败、ACK 丢失、重复 dispose；保留可重试欠账，禁止跨债务换路由 |
| L-A12 | L10 | 两 session/两 engine 的 READ/WRITE、重建及混合注册；冲突不退休旧输出；非 YUV 并行不被不必要串行化 |
| L-A13 | L10/L11 | SDR、P5、HDR10 直接输出、RGB 路径等非 YUV 不 arm；普通 controller 与受管路径混用的共享状态边界有覆盖 |
| L-A14 | L11/L12 | 新旧实际 package roots、源码 commit/tree/patch、native 链接与包成员一致；最新组合编译，受影响跨平台回归不遗漏 |
| L-A15 | L07—L12 | 实机普通入口冷开、切换、Surface 重建及失败恢复：实际 importer/presenter、PQ/range 与持续出帧/性能有证据；mock 不能代替 |
| L-A16 | L12 | 失败/静态回退/未验证标签准确；预期矩阵与实际结果逐行核对，负向通过不冒充正向功能完成 |

## 7. 实施与交接约束

先把上述 case ID 映射到现有测试并记录待补项，再完成接口与依赖顺序审查。然后在原分支分步实施库侧协议、生命周期及普通 App 联合回归；每步记录已实现 SHA、失败与通过证据、未完成项，不能因 CI 未结束再次开发同一功能。

实现测试版使用当时最新适用源码和可追溯原生输入。构建开始捕获一次精确输入供本次一致构建，结束核对新鲜度；SHA 是证据不是旧代码钉定。缺原生输入或设备即如实保留阻塞，不复制旧 JAR/SO 充当本次验证。

本次仅记录设计约束：不修改 runtime/依赖引用/构建流程/accepted ledger，不宣布上述正向能力或全 CI 通过，不合并或发布。下一接手先读两仓最新 refs、本文、App 契约及原 PR 最新回执，保护本地未提交工作；保留已完成 App 查询、选源、配置、Session/报告接入，禁止从旧 main 重做。

## 8. 源码与历史依据

以下是阅读基线 c7247139 的对应源码路径，不代表未来实现已存在。相对链接随当前分支移动，历史溯源使用 §1 的完整库 SHA：

- [Session 的 owner 与 attempt 清理接线](../../media_kit_video/lib/src/hdr/hdr_video_session.dart)、[当前 arm 管理器](../../media_kit_video/lib/src/hdr/hdr_yuv_window_arm.dart)。
- [输出槽](../../media_kit_video/lib/src/hdr/hdr_output_slot.dart)、[请求契约](../../media_kit_video/lib/src/hdr/hdr_output_contract.dart)、[coordinator/backend 协议](../../media_kit_video/lib/src/hdr/hdr_open_coordinator.dart)。
- [Surface 身份和释放协议](../../media_kit_video/lib/src/video_controller/android_video_controller/platform_surface_release.dart)、[Android 绑定实现](../../media_kit_video/lib/src/video_controller/android_video_controller/real.dart)。
- [PlatformVideoView 的扩展接口与初始 dataspace 顺序](../../media_kit_video/android/src/main/java/com/alexmercerind/media_kit_video/platformview/PlatformVideoView.java)。
- [实验 ledger](../../libs/android/media_kit_android_dataspace_vendor/android/src/main/java/com/alexmercerind/media_kit_android_dataspace_vendor/LgExperimentSurfaceOwners.java)、[进程初始化门](../../libs/android/media_kit_android_dataspace_vendor/android/src/main/java/com/alexmercerind/media_kit_android_dataspace_vendor/ProcessOutputInitGate.java)、[全局 native arm](../../libs/android/media_kit_android_dataspace_vendor/android/src/main/cpp/lg_fw_adapter.cpp)。
- [C4 无载体修复交接](app-pq-carrier-admission-20261015.md) 与 [方案 C 原文](lg-p84-yuv-window-reopen-20261014-spec-c.md) 保留，不用本文覆盖其历史结果。
