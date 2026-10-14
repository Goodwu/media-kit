# media-kit HDR 路由与 PiliPlusX 对接：执行方案 v4

任务 ID：MK-ROUTING-20261011。更新日期：2026-10-13。
状态：设计稿；本次仅更新方案，不代表以下改动已实施或验证。本文件继续作为原任务唯一执行方案，替代 v3 的成熟度准入、实验开关、候选顺序和自动 SDR 兜底规定；历史版本由 Git 保留。中央实现台账中的既有 implemented/verified 记录不因本次设计变为 planned。

## 1. 已确定的约束

整个项目当前均为实验性。只有一套完整候选和默认执行路径，不划分生产/实验可行集，不以验证状态决定准入，不新增功能启用开关。待验证实现正常执行；适用路径未实现，在对应路径返回结构化错误。全部既定必需路径取得验收证据后才上线。

固定顺序：C1 原生直通 → C2 动态重建/映射 → C3 兼容基线直通 → C4 HLG→PQ；全部耗尽则阻断。HDR10+/Vivid 不得在 C1 以 PQ/HLG 基线提前命中。普通 SDR 不升 HDR；P8.2 的 SDR 基线不得成为 HDR 分支出口；不增加 SDR→HDR 或 PQ→HLG。

HDR 分支失败不得自动转 SDR。现有 off/require SDR 是用户明确要求 SDR 的独立请求，不是重试内部可写的降级开关；require HDR 与 off 冲突先报错。普通 SDR 若与 require HDR 不相容，报告约束不满足，而不是升 HDR。

保留真实的源/解码/元数据/输出前提、ABI 检查、设备适配条件和 owner/ACK/lease 安全约束。删除实验开关不等于删除 native_dv、元数据处理模式等执行路径必需参数；这些参数由选中的路由写入，不由用户额外开启。

继续复用 VideoRouteCapabilities.query(target:, sources:)、VideoSourceSpec、目标显示绑定、现有 planner/realizer/Session，以及 PiliPlusX 的 DASH 查询接入。不重建旧查询接口，不为跨平台统一命名重写全部播放器，不做 importer/renderer/decoder 任意笛卡尔积。

## 2. 本次核对的代码基线与交接保护

以下为阅读时的观察值，不是未来构建钉定值：

| 仓库/工作根 | 阅读基线 | 处理原则 |
|---|---|---|
| Goodwu/media-kit | main=d7619227；routing/MK-ROUTING-20261011=979e04eb | 以现有 routing 开发链增量修改；不从 main 重做 |
| Goodwu/PiliPlusX | routing/MK-ROUTING-20261011=71d568775 | 延续现有 App 开发链 |
| Goodwu/mpv | media-kit/android=c11426b67a | 保留已有 DV bridge、P5 修正及 importer/presenter |
| Goodwu/FFmpeg | lg-p84-d1-vui-fix-20261010=d4bb79394b | 定点补原生元数据/输入缺口，不默认重写解码层 |
| Goodwu/libplacebo 工作根 | optimize/dovi-linear-decode=ea700489 | 与实际 Android/Darwin 构建消费来源另行核对，不能把工作根 HEAD 当作已链接代码 |
| Goodwu/libmpv-android-video-build-dv-experiment | main 的 depinfo 仍含固定旧代际 | 作为已发现的历史构建入口核对，不能未经确认就当作当前权威测试构建器 |
| media-kit-build / ohos-native-build | 本地构建目录，不是 Git 仓库 | 配方和必要补丁必须进入可追踪仓库；产物保留清单 |

工作区观察：media-kit 有未提交 conversation 修改；PiliPlusX 有未提交 route_options.dart、route_options_test.dart、conversation 及新计划文件；FFmpeg 为 dirty。实施前逐项 diff 对账，不覆盖、不清理、不以 checkout/reset 获得假干净树。本次不修改这些文件。

现有权威文档位置：本文件；docs/plans/media-kit-routing-handoff-20261011.json；App 的 docs/plans/media-kit-routing-app-handoff-20261011.json。既有 PR 链延续，实施前回读其当前状态。每个工作包记录 implementation SHA、测试命令/退出码、实际构建输入、CI run/head、未完成项和下一步。已提交但 CI 未完成仍是已实现，不另开分支重复实现。

## 3. 已核实的差距，而非重新假设从零开发

1. hdr_route_planner.dart 仍以 allowExperimental 和 HdrStrategyMaturityTable 过滤；P8.1/P8.4/Vivid 的默认顺序仍基线优先，HDR10+ 无默认行，并有通用 SDR safety net。[R1]
2. hdr_video_session.dart 的 _planNextAttempt 在 hdrAttempts >= 2 时改用 off；_retry 按 strategy 截断列表。仅改 planner 无法保证 C3/C4 获得执行机会。[R2]
3. video_route_option_review.dart 对整个候选列表打分排序，会影响跨阶段顺序。v7.3 要求 C1-C4 优先级不可被 decode/import prefer 颠倒。[R3]
4. mpv 已读取 AV_FRAME_DATA_DYNAMIC_HDR_PLUS 并调用 pl_map_hdr_metadata；HDR Vivid 当前仅记录存在性，不映射元数据。不能沿用 Dart 注释中“HDR10+ 完全无法读取”的概括。[R4]
5. libplacebo 已有 HDR10+ 场景数据和 Bezier/OOTF 映射；所读实现只处理 application_version < 2，并使用 params[0]。这不是所有 HDR10+ 元数据形态完整支持的证明。[R5]
6. FFmpeg native DV 接受 BL+RPU、无 EL 的 P5/P8；Dart realizer 当前只放行 P5/P8.4。P8.1/P8.2 应先核对现有链路；P7 不得通过放宽单层检查假装获得双层支持。[R6]
7. PiliPlusX 已有按完整 DASH 规格批量查询、显示 revision 一致性检查和预测。保留这些实现，更新配置和结果消费，不重建接入。[R7]
8. tool/build-android-test.sh 仍描述并使用历史 JAR 底包替换；tool/routing_matrix.py 当前只覆盖 p5/p84/hdr10/hlg 四类的既有构建矩阵，不能作为 v7.3 全路径验收矩阵。[R8]

## 4. 核心数据和执行设计

### 4.1 候选与执行实例分开编号，不增加第二套路由模型

在现有 HdrCandidate 上增加 stage、candidateId 和稳定顺序。stage 只有 C1/C2/C3/C4；candidateId 同时标识源类、基线、具体执行契约。一个阶段可以包含已有的真实硬解/软件或导入实现，但不凭空组合不存在的路径。

保留 HdrStrategy 大部分现有命名及实现；C2 的现有 metadataReshape 入口改成按元数据制式分发，对外统一展示“动态重建/映射”。增加 nativeHdr10Plus/nativeHdrVivid 实现身份，不能复用 nativeDolbyVision 冒充其他原生制式。普通 HDR10/HLG 可复用 baseLayerDirect 执行器，但 stage=C1；动态源基线回退使用同类执行器时 stage=C3。

HdrRoutingPolicy 不再允许任意跨 C1-C4 重排/删除候选；删除 allowExperimental、experimentalWasSpecified。VideoRouteOptions/EffectiveVideoRouteOptions 删除 experimental；序列化、比较、配置迁移、Lab/App 及所有测试同步更新，不能只把默认值改成 true。已有持久配置只做一次迁移去掉旧字段，不保留长期真假两套行为。

require 仍是硬约束；decode/import prefer 只排序同一阶段的真实执行实例。所有实例需满足相同的目标输出及元数据语义。强制软解不能假借硬解路线满足，也不能导致 C3 抢先于 C2。

### 4.2 显式结果，不让单个 feasible 布尔承载全部语义

建议增加 HdrCandidateEvaluation/HdrRouteFailure（名称为拟议接口）：

- skipped：结构不适用/重复候选，例如普通 HLG 的 C2/C3。
- unavailable：真实环境或输入前提不满足；区分 displayUnknown、transferUnavailable、decoderUnsupported、metadataUnknown 等原因。
- error：routeNotImplemented、metadataFormUnsupported、metadataMalformed、metadataNotDelivered、metadataNotApplied、outputContractMismatch 等实现/执行错误。
- ready：计划可选，但不表示已完成真实播放或验收。

每条记录包含 candidateId、stage、source/profile、inputTransfer、outputTransfer、failureStage、reason、dependencyKey、snapshotId；保留 cause 链。源字段缺失/解码或显示查询未知不得伪装成“确定不支持”。缺少可用本地实现不得改写成设备不支持。

planner 仍是同步纯函数：从不可变快照运行候选的纯评估/描述入口，入口缺实现立即返回 routeNotImplemented。不得为了暴露错误在预测时创建 Player、decoder、Surface 或 EGL。执行阶段仅在 Session/Backend 中准备资源。两者复用同一候选定义和错误契约，不维护相互漂移的两张列表。

原生库报告的是当前二进制的真实 ABI/实现信息，不是启用开关。若映射入口缺失，仍保留该候选及其明确实现错误；不能将 capability=false 当作无痕删行依据。

### 4.3 候选表

| 源 | C1 原生直通 | C2 动态重建/映射→PQ | C3 兼容基线 | C4 |
|---|---|---|---|---|
| P5 | DV | DV reshape | 跳过：IPT 非兼容基线 | 跳过 |
| P8.1 | DV | DV reshape | PQ | 跳过 |
| P8.4 | DV | DV reshape | HLG | HLG→PQ |
| P8.2 | DV | DV reshape | HDR分支跳过：SDR基线 | 跳过 |
| P7 | DV原生对应输入路径 | 无EL残差重建依赖且输入可处理 | 可独立解码的PQ BL | 跳过 |
| HDR10 | PQ | 跳过 | 跳过：不重复C1 | 跳过 |
| HLG | HLG | 跳过 | 跳过：不重复C1 | HLG→PQ |
| HDR10+ | HDR10+原生 | HDR10+动态映射 | PQ | 跳过 |
| Vivid-PQ | Vivid原生 | Vivid动态映射 | PQ | 跳过 |
| Vivid-HLG | Vivid原生 | Vivid动态映射 | HLG | HLG→PQ |

表中适用路径未实现一律显式报错，不设置开关。普通 SDR 另走 sdrDirect；明确 SDR 显示下 P8.2 使用正确清理信令后的 SDR 基线，其余 HDR 走 toneMapSdr，P5 必须先正确重建。显示缺报不能归入 SDR。P10/AV1 保留当前路径的明确未实现/不支持错误，不使用“所有 AV1 不可解码”的全局判断。

C4 只接受可信 HLG 基线；不仅“面板不支持 HLG”时可用，HLG 输出实例失败后也可继续判断。PQ 是否可用由完整输出契约决定，不是恒真。

### 4.4 快照与 Session 重试

Snapshot 使用原始 source revision、target/display/mode revision、解码与运行库事实、effective options。原始信令不被重建后 video-params 覆盖。Vivid 的 PQ/HLG 使用基线 transfer 字段区分，无须复制两套 source 类型；增加动态元数据 present/absent/unknown 的可观测性。

替换 _retry、_planNextAttempt、HdrSessionAttemptPolicy 的“两次 HDR 后转 SDR”和按 strategy 截断行为。采用 snapshotId + 有序 execution candidateId + attempted 集合；失败后清理当前资源，继续剩余实例。预算等于该快照有限执行实例数，不用固定 2 或 5 截断合法候选。同一实例最多尝试一次。

只排除已确定失败的依赖：C2 映射器失败不禁用 C4；若确认共享 PQ presenter 失败，则使用该 presenter 的 C2/C4 均不可重试。未知错误不扩大成全部 GPU/全部 HDR 失败。

清理/owner 失败、无法安全归因的 timeout、过期 generation 沿用现有立即停止语义。不得绕过资源安全来“尽量继续”。新源、换屏、输出格式或候选资格改变生成新快照；正常逐帧动态参数变化由当前管线处理，不每帧重规划。失败续走始终从原始源或明确基线输入开始，不能消费前一条路径残留的半转换结果。

### 4.5 元数据所有权与输出报告

将 stripDvRpu 的单一布尔提升/映射为明确的元数据处理策略：preserveForNative、consumeForMapping、baselineOnly。C1 保留并交付动态元数据；C2 消费后输出普通 PQ，不能将原始动态元数据再交给显示端重复应用；C3/C4 明确剥离/禁用对应动态语义。P7 的 BL 提取还须正确排除 EL，不能只移除 RPU。

复用并扩展 HdrOutputContract/HdrOutputReport：保留 requested/effective/observed，新增 attemptedCandidates、metadataFormat、metadataDelivered、metadataConsumed、metadataForwarded、mappingBackend、outputTransfer、snapshot/PTS epoch 等证据。预期 appliesDynamicMetadata 不能充当实际消费证明。面板呈现不可观测时明确记录 unknown，不以 configure 成功或应用内标记替代。

## 5. 分仓库实施包

### A. media-kit：统一候选、错误、重试和测试契约

主要修改：
- media_kit_video/lib/src/hdr/hdr_route_planner.dart、hdr_strategy_realizer.dart、hdr_strategy.dart、hdr_route.dart。
- hdr_source_descriptor.dart、hdr_source_classifier.dart、hdr_source_facts.dart、hdr_open_plan.dart。
- hdr_video_session.dart、hdr_session_native_dv_policy.dart、hdr_player_backend.dart、hdr_open_coordinator.dart。
- hdr_output_contract.dart、hdr_output_report.dart、hdr_output_diagnostics.dart。
- lib/src/routing/video_route_options.dart、video_route_option_review.dart、video_route_capabilities.dart。

仅在必要位置增加候选结果/错误模型文件；成熟度表退出运行逻辑，可迁入验收数据，不能以改名后继续作准入条件。检查 HdrOutputPolicy 和其他旧入口，必须委托同一规划规则，避免旁路仍保留 SDR safety net。

在这一包直接建立 HDR10+/Vivid 适用入口；缺实现返回 routeNotImplemented，使默认构建能够测试完整错误与回退链。该阶段允许合同测试通过，但对应功能验收仍不通过。

### B1. FFmpeg：复用解析器，补硬解侧逐帧交付

复用已存在的 libavcodec/h2645_sei.c、dynamic_hdr_vivid.c、hevc/hevcdec.c 中 HDR10+/Vivid 解析及 side data；不重写 T.35 解析器。[R9]

重点审计 libavcodec/mediacodecdec.c、mediacodec_dovi.c/h、mediacodecdec_common.c：当前已有 DV 输入跟踪/输出附加机制。先验证软件、mediacodec、mediacodec-copy、surfacetexture 各真实载体的 metadata 交付；缺口处复用队列生命周期，增加类型化 HDR10+/Vivid 载荷，而非建立另一套解码框架。

输入按访问单元解析元数据，绑定 PTS、解码序列和 flush epoch；输出帧按同一关联交付对应 AVFrame side data。覆盖 B 帧重排、重复 PTS、无 PTS、seek/flush、丢帧、EOS、元数据更新及格式规定的有效期。不以“最近一次元数据”跨 seek 复用，不假定每帧必须重复携带相同 SEI。损坏或超出实现能力的元数据返回明确错误。

C1 native DV：保留 profile32/256、BL/RPU、codec/config 和实际 decoder 复核；P8.1/P8.2 先扩展 Dart 的真实输入准入与对应复核测试。P7 原生若需要双层输入，必须有正确解复用、BL/EL 时序与真实设备消费链，不能删除 el_present_flag 检查后宣称完成。P10 单独报告未实现输入路径。

复核原有 P8 MIME-only 多 decoder 选错问题；继续使用现有 native_selection_harness，只有尚未闭合的缺口才修改，不重复实现已完成修正。

### B2. mpv：源事实、动态处理分发和消费证据

修改重点：video/mp_image.c/h、player/command.c、video/filter/vf_format.c、video/out/vo_gpu_next.c 及对应 decoder/output 复核接线。

HDR10+：已有 AVFrame→pl_map_hdr_metadata 链保留；新增可查询的原始存在性/状态，并检查硬解导入、帧复制和过滤后的保存。C2 使用真实 HDR10+ 动态映射设置，不能仅写 target-trc=pq。libplacebo 的 st2094-40 可消费 OOTF/Bezier，但缺元数据会回退固定曲线，因此必须单独复核有效输入与实际消费。[R4][R5][R10]

Vivid：从仅 hdr_vivid 布尔升级为有引用生命周期的真实元数据载荷；传给共享映射器，复制/释放/flush 对称。仅保留存在性不算已实现。

C3/C4：显式禁用 DV/HDR10+/Vivid 动态语义并清理残留状态。复用现有 vf_format 的 dolbyvision/hdr10plus 处理能力，但核对它与解码入口的作用位置；不能把解码后的帧过滤冒充送入原生 decoder 前的码流清理。

P7 C2：报告残差依赖和映射支持性，替换 Dart 的 enhancementLayer==false 唯一判据。所读 mpv 仅在 disable_residual_flag 时映射 DV，而 libplacebo 工作根还有 trivial-NLQ 判断；先对齐实际构建版本的支持函数。仅在元数据证明不需要 EL 残差重建时使用 BL+RPU，不伪造完整 FEL 重建。

### B3. libplacebo：HDR10+ 复用；Vivid 为真正新增算法

HDR10+ 不另写现成算法。核对当前编译版本对 application_version、窗口、曲线及颜色控制的覆盖；所读 params[0] 路径不能冒充完整多窗口支持。未处理的必要形态返回 metadataFormUnsupported，并保留该功能工作项。全路径验收不能靠默默忽略字段完成。[R5]

Vivid 新增公共元数据模型、FFmpeg 结构映射、CPU 参考实现、共享 shader 实现与测试。建议文件：src/include/libplacebo/hdr_vivid.h、src/hdr_vivid.c、src/shaders/hdr_vivid.c、src/tests/hdr_vivid.c，具体组织遵循实际 libplacebo 构建树。

算法合同：按正式 Vivid 规范和合法测试向量处理源 PQ/HLG 解释、目标显示参数、基曲线/样条及颜色控制；将输出交给现有目标色域与 PQ 编码阶段。FFmpeg 元数据结构只证明语法存在，不是显示算法规范。不得把 Vivid 字段机械塞入 HDR10+ Bezier 并宣称等价，也不得以普通 HLG→PQ 冒充 Vivid C2。

目标峰值来自有效显示报告或明确的渲染策略值，并在报告注明来源；无测量证据不得标为实测 nits。CPU/GPU 对拍的阈值、量化模式和参考向量在实现前入库，不能看完结果再放宽。

共享实现让 Android/Darwin 等使用相同数学内核；不为每个平台复制 shader。HDR10+ 与 Vivid 的 C1 原生路径单独验证 decoder→Surface→display 的元数据交付；仅显示 HDR 类型或应用标记不算原生链完成。

### B4. Android 与其他平台边界

Android 的 HdrCapabilities.java、VideoRouteCapabilities.java、MediaKitVideoPlugin.java 按需扩展真实输出/动态制式事实。保留只读查询、实际 target、联合源规格匹配、unknown/error 区分，不创建预热 Player 或 decoder。继续使用现有 native pipeline probe，而非让 Dart define 声称某管线存在。

C1/C2/C3/C4 使用各自真实 presenter 与像素/信令契约。保留 LG 已接受的 YUV8 配方及所有 owner/ACK/lease 约束，不夹带 10-bit 或 lease 融合重构。HDR 的 Surface 路径和显示事实需逐平台核对，不能只凭 PQ 码值或泛化 HDR 标签认定端到端成功。[R11]

当前 VideoRouteCapabilities 主要为 Android adapter；其他平台缺实现时显式返回 adapterUnavailable/routeNotImplemented，不把 Android 枚举硬套过去。Darwin 已有共享 renderer、OHOS 已有播放器和构建链继续保留。共享映射与公共契约变化须跑其编译/生命周期回归；跨平台 HDR 端到端支持仍按平台单独验收，不将 Android 通过外推为全部平台通过。

### C1. PiliPlusX：迁移配置、消费同一结果、不再复制路由

修改 lib/plugin/pl_player/route_options.dart、hdr_output.dart、source_selection.dart、models/hdr.dart、controller.dart 及其测试。先与本地未提交修改对账。

删除 experimental 参数与配置项；保留现有按 codec/coded size/frame rate 构造规格、批量查询和显示 revision 保护。源选择、预测、Session 执行与报告使用同一规格/目标/有效选项。未知 DV 信令继续明确处理，不以质量编号或文件名猜 profile。

UI 至少区分“原生动态 HDR”“本地动态映射→PQ”“兼容基线回退”和“阻断”，并能查看被放弃候选的错误。C2 未实现而 C3 成功不得显示“动态映射成功”。App 不持有设备白名单、SDK/decoder 私有规则或另一张 C1-C4 表。

### C2. 构建与 CI：完整最新输入，不能只换主库

统一 tool/build-android-test.sh、tool/matrix-build.sh、tool/routing_matrix.py 与 App 原生输入验证脚本的来源契约。先确认权威构建入口；把必要的本地配方/补丁纳入追踪，不能让 CI 依赖工作站路径。

每次构建解析当前权威分支及全部适用修改，形成 build-inputs 清单：各仓库 commit/tree/patch、工具链、构建选项、依赖输入及产物哈希。随后对这一次解析结果一致构建，避免构建过程中混用移动分支。这里记录精确 SHA 是溯源，不是回退旧源。

重建全部适用的 FFmpeg/libplacebo/mpv/helper/JNI；未改且输入完全一致的中间产物可缓存，但不得沿用无法证明来源的旧 JAR 底包。核对最终 JAR/APK 内的 so 与加载库身份，而非只看 ninja 成功、目录时间或库名。

扩展已有 routing-source、routing-query、routing-darwin、handoff-source workflows，增加 native 元数据/映射合同测试、无实验开关检查和功能验收汇总。保留 App 全量 tests/analyze/真实 APK 构建，以及共享变更涉及的 Darwin/OHOS 回归。工作流必须读取本次候选的实际源码；不能以绿色的历史 run 证明新头。

## 6. 测试与验收矩阵

验收矩阵独立于实现注册表维护，建议 docs/validation/hdr-route-matrix-v7.3.json；不从当前支持的路径反推必测范围。每行有 caseId、目标候选/执行实例、源基线/元数据形态、显示链、解码条件、输入身份、expectedResult 和所需证据。该矩阵控制验收，不控制运行期路由准入。

### L0：纯规划与配置

覆盖所有源行、SDR/PQ/HLG/PQ+HLG/原生动态显示/缺报、硬解/软解/未知/不支持及 require 冲突。重点断言：
- HLG+仅PQ：C1不可行→C2/C3结构跳过→C4；不能提前阻断。
- P8.4、HDR10+、Vivid-PQ/HLG：C1原生不可行时，C2在C3前；任何prefer不能颠倒。
- C2适用但未实现：保留routeNotImplemented，C3回退成功不抹错。
- P8.2+HDR：C1/C2均失败后阻断；P8.2+SDR可走清理后的SDR基线。
- P5缺重建、DV信令未解析、显示缺报、P7残差依赖未知/需重建、P10未实现分别保留明确原因。
- 成熟度/验证标签变化不能改变候选或选择结果；代码和构建不需要启用experimental。
- HDR-only路径永不合成SDR候选；显式off和require冲突单独测试。

### L1：Session / Backend / App

复用并扩展 hdr_route_planner_test、hdr_fallback_failure_test、hdr_video_session_test、hdr_session_source_facts_test、hdr_session_route_options_test、hdr_output_contract_test、hdr_execution_catalog_test。新增 ordered-candidate、metadata-processing、acceptance-coverage 合同测试。

测试 C1→C2→C3→C4 逐项失败、第三/第四项最终成功、全部耗尽、同阶段替代执行、共享依赖排除、局部映射失败不误伤C4、清理失败立即停止、换屏重规划、旧generation迟到事实、并发open/seek/fullscreen/前后台/dispose。App 覆盖查询失败、目标revision变化、选源与实际执行一致、回退展示及旧配置迁移。

### L2：原生元数据和映射

软件与所有实际硬解载体检查同一PTS/epoch上的元数据内容；覆盖B帧、重复/缺失PTS、flush/EOS、格式有效期、畸形字段和容量上限，做ASan/UBSan及解析fuzz。C1保留、C2消费、C3/C4禁用各有阳性/阴性用例。

HDR10+ 用有效变化曲线测试，Vivid 用正式语义向量和独立CPU参考；比较CPU/GPU输出、黑白端点、连续性、单调性及颜色误差。选择确实应改变映射的向量证明元数据生效；不要求数学上应为恒等映射的所有场景都产生像素差异。PQ/HLG信号范围及二次映射错误另测。

### L3：设备端到端

设备按实际能力选取，覆盖原生DV、PQ-only、HLG、HDR10+原生及Vivid原生所需链路；缺少设备或样本明确标incomplete，不编造通过。现有设备/素材能覆盖哪些行由实测快照决定，不能把P5/P8.4回归外推到其他格式。

每个正向功能行要求目标候选实际进入并成功，元数据按预期交付/消费，输出契约成立，以及可用的呈现/颜色证据。软件模拟的显示能力不能替代真实面板证据；普通截图不能单独证明HDR亮度呈现。颜色与性能分开报告；4K60、丢帧、seek/切源/生命周期继续保留。

### L4：防止假全绿

“routeNotImplemented准确报错”的负向用例可以通过；该功能的正向行必须仍为未完成/失败。“C2失败、C3成功”只计回退机制通过，不计C2功能通过。未触达目标候选、skip/xfail、缺设备、缺样本、缺消费证据均不能计正向通过。

自动汇总核对 expected caseId 与实际结果，缺行/重复/覆盖不足/不同构建身份都不能通过上线验收。阶段性合同CI可以绿；总功能验收未完成时，汇总与上线检查必须清楚地不通过，不能展示“全部路径已验证”。不得删除用例、降低阈值或引入开关规避。

## 7. 三批实施顺序与完成定义

**现行排期修订**：以下三批表是历史实施设计，其第二批 B1—B4 已被 §13（2026-10-14 用户最新裁决）明确暂缓；不得按此历史表自动开工或将动态 C1/C2 纳入本期上线门槛。保留原文仅为审计与将来恢复时参考。

| 批次 | 工作包 | 输出与完成条件 |
|---|---|---|
| 第一批 | A + App配置最小同步 + 固定验收矩阵 | 去除门控；C1-C4及显式错误；Session无HDR→SDR暗退；默认构建合同测试；未实现功能仍如实未完成 |
| 第二批 | B1/B2/B3/B4，优先复用DV/HLG与HDR10+，再实现Vivid | 逐帧元数据交付、真实映射/基线处理、消费证据；按源/profile/元数据形态独立验证，未完成原生输入路径继续明确报错 |
| 第三批 | C1/C2 + 全量L0-L4 | App实际使用；完整最新源码构建；最终候选CI与设备矩阵闭合；全部既定必需行通过后才上线 |

第一批不是“上线子集”，第二批不是可选后续，第三批也不是仅补文档。每个小提交先有失败用例再改实现，保持可复核，沿原分支提交。第一批推进时保留原B1/B2/B3台账已完成项；未完成的decoder选择、LG接线、跨平台回归及App构建问题不得因新路由任务被遗忘。

本轮之后的唯一第一步：回读当前Git/台账并对账本地dirty修改，然后实施第一批的候选结果模型及无开关测试；不得先从旧main重新开发查询或App接入。

## 8. 证据入口与范围说明

以下引用用于设计依据；源码存在、单测通过、二进制编译、真实HDR呈现是不同证据层级。本轮没有运行项目测试、原生构建或设备验收，未独立宣布任何新功能完成。

[R1] media-kit@979e04eb，media_kit_video/lib/src/hdr/hdr_route_planner.dart，尤其默认表、_evaluate成熟度门和safety net。
[R2] 同提交 hdr_video_session.dart，_retry/_planNextAttempt（约779–907行）；hdr_session_native_dv_policy.dart。
[R3] 同提交 lib/src/routing/video_route_option_review.dart、video_route_options.dart、video_route_capabilities.dart。
[R4] https://github.com/Goodwu/mpv/blob/c11426b67a/video/mp_image.c （约1170–1212行）；video/filter/vf_format.c。
[R5] https://github.com/Goodwu/libplacebo/blob/ea700489/src/include/libplacebo/utils/libav_internal.h （约340–383及950–1028行）。该工作根版本不等于已链接Android版本。
[R6] https://github.com/Goodwu/FFmpeg/blob/d4bb79394b/libavcodec/mediacodecdec.c （约397–453行）；media-kit hdr_strategy_realizer.dart 的_nativeDolbyVision。
[R7] https://github.com/Goodwu/PiliPlusX/blob/71d568775/lib/plugin/pl_player/source_selection.dart 及hdr_output.dart/route_options.dart。
[R8] media-kit@979e04eb tool/build-android-test.sh、tool/routing_matrix.py；Android构建实验仓buildscripts/include/depinfo.sh。
[R9] FFmpeg@d4bb79394b libavcodec/h2645_sei.c、dynamic_hdr_vivid.c、hevc/hevcdec.c、mediacodec_dovi.c及mediacodecdec.c。
[R10] https://libplacebo.org/options/ （st2094-40使用OOTF/Bezier；缺元数据时会采用固定曲线）。
[R11] https://developer.android.com/media/grow/hdr-playback 及 https://developer.android.com/reference/android/view/Display.HdrCapabilities 。

## 9. 2026-10-13 远端实施检查点：供本地 agent 续接

**状态：第一批部分实施，尚未验收；以下不是完成声明。** 本轮只更新 Goodwu/media-kit 的既有 `routing/MK-ROUTING-20261011` 分支；其他关联仓库未改动。本地 Codex 工作根仍显示旧 commit `979e04eb`，并非最新远端提交。**先 fetch 后对账，勿从本地旧 HEAD 重新实现，也勿 reset/clean 覆盖用户未提交改动。**

### 已提交源码及测试（按提交顺序）

- `5b29be1cec866e2e95876cf432bdd74d38e9120e`：`hdr_session_native_dv_policy.dart` 移除两次 HDR/五次总数硬预算，保留逐条 route 去重、native DV 单次准入；`hdrAttempts` 仅用于统计。
- `7fc330706dedb45b77e0a955e937a0c39b460036`：`hdr_video_session.dart` 删除两次 HDR 后改 `preference.off` 重规划及固定五次停止条件。
- `5cc150340a29e21998bcc27747f1aa4c5c68e874`：更新 `hdr_session_native_dv_policy_test.dart` 的 admission 预算测试。
- `e186c5420051ce6c36133410573534c9ea987d45`：`hdr_route_planner.dart` 防止 HDR-capable/unknown display 自动落到 SDR 候选；仅显式 SDR 要求、普通 SDR 源或确定 SDR-only display 允许 SDR 输出。保留既有明确请求语义。
- `fe649e872307e279bbec15d839176958e45c529c`：新增 `hdr_v73_no_implicit_sdr_test.dart` 五个针对性 host 回归。
- `3063442f689bea9dc17507b22fabca3f5f1f4c99`：修正旧 Session 测试，从“第三次强制 SDR”改为“继续尝试 HDR 兼容基线”。

### 真实验证结果与限制

- GitHub Actions 对 `5cc1503` 的 `Routing source checks` / media_kit_video 运行 `38416157875`，测试编译、analyze 均已执行；该中间版本 **Flutter tests FAIL（1 项）**：`hdr_session_native_dv_policy_test.dart` 原用例把第三候选写死为 `toneMapSdr`，实际为 `baseLayerDirect`。已由 `3063442` 更新用例。该历史失败不得记为最终成功。
- 更新 `e186c54` 之后的最终候选 CI 仍需回读该实际 head 的 workflow runs 和 job conclusions，不能用历史 CI success 替代。
- 当前 ChatGPT 执行容器没有 Dart/Flutter/Android SDK、ADB，也无法 DNS 访问 github.com；Codex workspace 连接为 read-only，未实际执行本地构建/设备验证。本轮通过 GitHub 内容 API 写入上述源码，CI 是唯一可用的自动测试来源。
- 之前的 local dirty：media-kit conversation 文档；PiliPlusX conversation、`lib/plugin/pl_player/route_options.dart`、`test/route_options_test.dart` 和 MKSURF 计划；FFmpeg `configure` 与生成目录。未修改这些本地文件。

### 本地 agent 接手顺序（必须）

1. 检查远端 `Goodwu/media-kit:routing/MK-ROUTING-20261011` 最新 head。保存本地 dirty diff，`git fetch` 后决定如何安全合入以上提交；**不要 checkout 新分支重复开发，禁止 reset/force push**。
2. 对真实最新头运行 `flutter analyze`、`flutter test`（至少 media_kit_video 全量 + media_kit_hdr_lab 全量），核对 `hdr_v73_no_implicit_sdr_test.dart`、Session 的三次 HDR 回退和当前输出偏好测试。检查有无未复核的旧用例期望、未覆盖的空候选 `HdrCandidate` 以及 `nullable` 静态分析问题。记录命令、exit code、源码 SHA。
3. 继续执行第 4—7 节剩余事项：固定 C1—C4 顺序、移除全部实验开关和成熟度准入、HDR10+/Vivid 的 C1/C2 明确入口与 routeNotImplemented、完善逐候选错误/重试、修正 C4 仅 HLG→PQ、与 PiliPlusX 共用报告。**这些在本检查点均未实施，不能误记完成。**
4. 仅当 Dart/host tests 通过后，核对 mpv/FFmpeg/libplacebo 实际被构建的源版本与最新输入；按 v4 逐包实施 native 改动和元数据时序测试。遇到缺设备或无法完成真实 HDR 输出验证时停止并交回实机验收，勿伪造。
5. 全部改动均回到既有唯一方案、本仓台账及 App 台账；最终 CI 必须是最终源头的 success，设备真实性与功能验收分开记账。

本检查点不改变 v4 的完整目标表，不以临时局部修复代替其剩余任务，也不以“待实现已返回错误”当作 HDR10+/Vivid C2 的功能完成。

### 本地验证回执（2026-10-13，本地 agent）

- 合入：本地 `979e04eb` 严格落后，dirty 归档先行快照（`~/src/media-kit-build/local-dirty-snapshots/media-kit-routing-20261011-pre-e40cef8f.diff`）后 `git merge --ff-only` 至 `e40cef8f`；未 reset/未 force push/未开新分支，六个提交 SHA 全部核实在案。
- 首验证（`e40cef8f` 原样，Flutter 3.47.2）：两包 `flutter analyze` 零 finding；`hdr_v73_no_implicit_sdr_test` 5/5、`hdr_session_native_dv_policy_test` 58/58 通过；全量首跑 media_kit_video 748/39 失败、media_kit_hdr_lab 297/1 失败——40 项均为编码已废隐式 SDR 契约的未迁移旧用例（V1 复核与运行结果一致）。CI 回读该头：38417189657 两包 `Source analyze and tests` job failure 与本地一致；38417189624/89783/89602 success，38417189664 构建类 job 全绿。
- 处置：40 项旧用例全部按第 1 节不变量迁移（0 ESCALATED；无删用例、无断言弱化、无新开关；审查确认）；附带删除 `hdr_video_session.dart` review 路径 `hdrAttempts>=2→off` 死控制流（仓库级"hdrAttempts 仅统计"由此成立）与三处过时注释；新增空候选目录阻断占位专测 1 项。终态：media_kit_video 788/788、media_kit_hdr_lab 298/298，双 exit 0。
- 未实施（维持第 4—7 节原状）：4.1 stage/candidateId 与去 experimental 开关、4.2 显式错误模型、4.3 候选表、4.4 快照重试、4.5 元数据所有权、A 包 HDR10+/Vivid routeNotImplemented 入口、C4 仅 HLG→PQ 修正、PiliPlusX 配置/报告共用、验收矩阵 JSON、native B1—B4 与设备验收。已知设计遗留：planner 以 `displayLacksTransfer` 复用表达策略性禁 SDR、阻断路径 `report.degradeReason` 为 null（typed 错误由 `report.error` 携带），均归入 4.2 错误模型设计。
- 后续：本地提交待用户批准推送；推送后最终 CI 须在实际新头取得 success 方可记最终验收；再按第 4 步核对 mpv/FFmpeg/libplacebo 实际构建输入进 native 包。

## 10. 2026-10-14 主仓实施与源码验证阻断（本地 agent 接手）

**代码已提交，功能未验收。本节是本轮唯一续接事实，不重启旧工作或新开实现分支。**

### 10.1 代码身份与范围

原权威分支仍为 `Goodwu/media-kit:routing/MK-ROUTING-20261011`。本轮基点为本地 agent 已验证的 `e1993351dccc25149dc2543bf268a47dfec7b368`（本地对旧 40 项测试迁移后 788/788 video、298/298 lab；实机回归另有 LG P8.4 的实际 PQ 输出链失败）。本轮新代码最终变更头在下方；均 GitHub API 在相同原分支顺序写入并逐次成功回读，不是对本地旧副本重新开发。未写入 PiliPlusX/FFmpeg 的 dirty 文件或 mpv/libplacebo。不要将旧基点的 Flutter/设备成功标记继承给新头。

本轮按序提交：
1. `fa5cb8a2` + `c1885ecc`：C4 执行约束仅 HLG 基线→PQ，且 PQ 显示可用；新增六项纯执行器回归。
2. `79f8cc38`：旧 C4 HDR10 PQ 伪转换测试迁移，保留真实 HLG 路线、SurfaceTexture 故障和不得 SDR 接管的负向断言。
3. `6dd3c33b` + `3084e1d9`：HDR10+/Vivid 独立 C1 原生候选身份、C2 动态映射缺失时显式 `routeNotImplemented`，源不适用与显示缺报不冒充实现错误；普通 HDR10/HLG 的 C2 不可误标动态映射成功。加入 `HdrCandidateStatus` 与四项回归。
4. `f0472a4c`：修正旧 HDR10 C4 gate-open 误断言。
5. `c55ebb91` + `90a993f8`：`HdrRouteStage` C1—C4、候选 `candidateId`，prefer 同阶段排序，四项新阶段回归。
6. `9e41c0c1`：拒绝/过滤候选仍保持独立执行实例的稳定 ID（防止三个 SDR decoder 变体 ID 碰撞）。
7. `4e6b29ab`：DV P8.1/P8.4/P7 默认顺序以 C2 在 C3 前为准；Session 回退重新评估完整候选，保留 attempted/excluded，不能按旧策略索引裁掉 C3/C4。
8. `ede11fc0` + `a0975fbb`：移除 planner 对成熟度的真实执行准入门；新增无需 experimental 开关的测试。**过渡 API 仍包含旧 experimental 字段：仅记录/兼容，后续必须整体从库、Lab、App 删除。**
9. `cbd446d4` + `d5a270a7`：禁止旧 allowExperimental 与 effective options 的真假冲突阻断路由及回归测试。

### 10.2 实际 hosted CI 结果（不冒充功能通过）

- `c1885ecc` 的 routing source run `38436756113`：video tests **12 FAIL**（旧 C4 PQ→PQ/PQ→HLG 假契约），lab/tools SUCCESS；已在 `79f8cc38` 测试迁移。
- `79f8cc38` 的 routing source run `38437598785`：video **1 FAIL**（残留 gate-open 旧断言），lab/tools SUCCESS；由 `f0472a4c` 修订。
- `a0975fbb` 的 routing source run `38439230656`：`media_kit_video` **36 FAIL**（主要由于固定阶段顺序与成熟度开关废除，旧测试仍假设原准入/回退；包含新 stage 测试与旧 experimental policy 冲突），`media_kit_hdr_lab` SUCCESS、Python tools SUCCESS；video 的 `flutter analyze` 已执行且没有 compile/error finding（失败来自 Flutter tests）。原始 run/job `115441457858` 和日志留存，不能记为绿。末端两提交 `cbd446d4/d5a270a7` 已修复其中真实的旧开关冲突及添回归，**但未获末端全量绿**。
- 上述 hosted source 测试使用 GitHub runner 的 Flutter 3.47.7，不是本次模型在本地运行。此环境无 Dart/Flutter/Android SDK/ADB，不具备本地全量编译/设备检验条件。新 native 渲染端到端一概仍未验证。

### 10.3 必须先完成的本地验证/修正

1. 先查 `Goodwu/media-kit:routing/MK-ROUTING-20261011` 最新远端 HEAD，保留全部当前 dirty 工作，`fetch` 后安全快进/合并，**不要 checkout/reset 重来、不要产生重复开发分支**。运行前记录精确主仓/App/mpv/FFmpeg/libplacebo refs 与工作树补丁/二进制输入身份。
2. 对最新 HEAD 执行 `media_kit_video`、`media_kit_hdr_lab` 的全量 `flutter analyze` 与 `flutter test`。核对新 `hdr_v73_c4_hlg_to_pq_test.dart`、`hdr_v73_dynamic_candidate_errors_test.dart`、`hdr_v73_candidate_stage_test.dart`、`hdr_v73_no_maturity_gate_test.dart` 以及原 `hdr_v73_no_implicit_sdr_test.dart`。从 run `38439230656` 的 36 FAIL 开始逐项复核。
3. 旧测试应迁移到已裁决的不变量，而不是删测试、仅开某个 experimental 开关、把动态映射未实现当成功、或者把 P8.2 的真实 C2→PQ 判成不允许的 SDR→HDR。注重现实区别：P8.2 `p5PipelineAvailable=true` 的 C2 可正确输出 PQ；`false` 时才要求 C2 不可行和 HDR 分支阻断。
4. 特别查 `HdrRoutePlanner` 与 `HdrVideoSession` 的选中/恢复/重建时序：C2 错误后 C3/C4 能走完、同一执行 candidateId 不重复、未实现错误保留；不放宽 owner/ACK/lease、无信令 DV、数据空间和软件/硬解安全门。
5. 源码 full suite 通过且与最新远端一致后再继续删除旧 `allowExperimental/experimental` 配置/API 字段，并迁移 PiliPlusX dirty 的 `lib/plugin/pl_player/route_options.dart`、`test/route_options_test.dart` 与其他调用点。不能通过保留另一个实验性启用开关解决测试。
6. 核对未实施：metadata ownership 的 `preserve/consume/baseline` 合同、P7 残差与 EL、HDR10+/Vivid 的真实逐帧元数据交付+映射、C1 原生动态显示链、真实 native 最新源码构建与 LG/marble 设备输出。 `routeNotImplemented` 的合同测试通过不等于这些功能完成。

**当期阻断性质：本轮无本地 Dart/Flutter 运行器，hosted source 36 FAIL 尚需本地 agent 的全量用例迁移与独立审核。** 因此停在验证交接点，不继续修改 FFmpeg/mpv/libplacebo 或产品 App，避免在尚未通过源码门前扩大未验差异。已提交代码保持 implemented / unverified，而不是退回 planned。

### 本地验证回执（2026-10-14，本地 agent，d3a4ab23）

- 基线：fetch 快进至 `d3a4ab23`（含 §10.1 全部十提交），工作树净、无 dirty 冲突。
- 全量首验：双包 `flutter analyze` 零 finding；media_kit_hdr_lab 298/298 全绿（与 hosted 一致）；media_kit_video 失败 31 项（compact 报告器截断初计 18，expanded 复核实为 31；与 hosted a0975fbb 36 项之差为末两提交已修项及 Flutter 3.47.2/3.47.7 环境差，未逐项对账）。
- 迁移：四 Worker 两轮将失败项全部迁移至已裁决契约，**0 ESCALATED（未发现实现缺陷）**；无删用例、无断言弱化、无新开关（V1 复核逐条核对）；新增用例 2 个（hdr10Plus 固定目录 C1/C2 routeNotImplemented 错误在 C3 基线成功下保留；C2 dataspace 错误后 C3 续走至 verified）；规格级 `hdr_v73_no_implicit_sdr_test` P8.2 用例按 §10.3.3 双态语义迁移（p5=true C2→PQ 合法且入选、p5=false 阻断，两分支均断言无可行 SDR 候选，"SDR 基线不得冒充 HDR"保护保留）；一处 session 测试夹具按真实 planner API（`withRoutingIdentity`）补挂候选身份，经复核为复刻真实身份而非绕过。
- §10.3.4 时序核验：C2 错误后 C3/C4 走完、同 candidateId 不重复尝试、routeNotImplemented 在 C3 成功后保留、清理失败/不可归因 timeout 立即停止——四点均由具名测试覆盖（含新增用例钉住缺口 a）。
- 终态：**media_kit_video 808/808、media_kit_hdr_lab 298/298，双 exit 0**（Flutter 3.47.2）。V1 复核可提交；两条范围外低优先级跟进：planner lib 注释两处已顺手修正；两个既有测试文件的旧 gate 措辞留待 §10.3.5 批次清理。
- 本批本地提交：10 个测试文件迁移 + planner 注释修正 + 本回执与台账。
- 后续（§10.3.5）：删除旧 `allowExperimental/experimental` 配置/API 字段（库、Lab、App）与 PiliPlusX dirty 文件迁移，另批实施；§10.3.6 未实施项维持（metadata ownership 合同、P7 残差/EL、HDR10+/Vivid 逐帧元数据交付与映射、C1 原生动态显示链、native 最新源码构建与 LG/marble 设备输出）——routeNotImplemented 合同测试通过不等于这些功能完成。

### §10.3.5a 执行回执（2026-10-14，media_kit 侧）

- 删除完成：`HdrRoutingPolicy.allowExperimental/experimentalWasSpecified`（构造参数/字段/resolve policy 形参；off×require 冲突检查原样保留）；`VideoRouteOptions/EffectiveVideoRouteOptions.experimental`（字段/merge/==/hashCode/toMap/fromMap 全链）。序列化迁移契约：`fromMap` 允许集保留 legacy `experimental` key 并静默丢弃（含非 bool 脏值）=持久配置一次迁移，`toMap` 不再输出，新增契约测试钉住。
- 附带清理：session 写死不读的 `_legacyPolicy` 字段删除（setPolicy 改发未变 settings 保留 replan 触发语义）；Lab 三个实验 common/页面调用点去参（GATE_OPEN 分支返回 defaults）；`experimentalStrategySkipped` 枚举保留（降级原因词表，文档注明"已删门的 legacy 原因，不再产生"）。
- 测试同步 16 文件：[false,true] 参数化循环折叠为单趟 defaults（video 808→783，逐文件核对均为循环折叠，无断言本意删减）；"开关不影响评估"负向断言改为直接结果断言；`video_player_media_kit` 无代码引用（real.dart 的 'strict=experimental' 是 mpv flag 字符串，无关未动）。
- 验证：media_kit_video 783/783、media_kit_hdr_lab 298/298，双包 analyze 零 finding，exit 0。无 ESCALATED（未发现删除后改变评估结果的隐藏依赖）。
- 范围外事项：`video_player_media_kit/analysis_options.yaml` 出现一处非本批改动（新增 exclude build/**），按改动保护原则未入提交、保持工作树 dirty，待用户裁定。PiliPlusX 侧迁移另批（其依赖 override 钉旧 ref，App 提交与 pin 更新须待主库推送后）。

## 11. 2026-10-14 元数据所有权与独立验收矩阵（续接检查点）

状态：**源码已提交，未通过当前最新 SHA 的全部 CI，也未取得原生/设备证据**。继续唯一 `Goodwu/media-kit:routing/MK-ROUTING-20261011` 分支，没有创建新分支；用户本地 dirty 的 App 与 FFmpeg 未触碰。详细交接及下一步在 PR#4 [评论 6158407545](https://github.com/Goodwu/media-kit/pull/4#issuecomment-6158407545)。

- 上一验证基线为 `7ef40c4b`，对应父提交 `7a53bc78` 的 hosted workflows source/query/Darwin/OHOS/general 均 success（具体 run IDs 在 PR 评论）；本地 agent 之前 video 783/783、lab 298/298、analyze 零 finding。该事实仅绑定旧源码。
- `1407ce43`：`HdrRoute` 增加显式 `HdrMetadataHandling.none/preserveForNative/consumeForMapping/baselineOnly`，由 source×strategy realizer 计算并跨 `withExecution`、equality、hashCode 保留；`HdrOutputReport.requestedMetadataHandling` 为路由意图，`metadataHandlingObserved=null` 明确表示当前没有逐帧实际消费/转发证明。没有开关，也没有伪造元数据已被应用的结论。
- `c1cbf7d3`：新增 `hdr_metadata_ownership_contract_test.dart` 五项，覆盖 P5、P8.4、HDR10+、Vivid、SDR 及输出重建契约。
- `0608f891`：CI 中间版本仅一个旧 Session 用例失败，其原断言要求“从 HDR10 重新分类为 Vivid 后同一 vo/hwdec 不重建”。由于现在元数据处理模式从 `none` 变为 `baselineOnly`，路由身份变化必须重建以免采用旧执行契约。已改测试要求重建并断言前后模式；最终源码尚须重新跑全量确认。
- `a5cbcb49`、`e30857cf`、`8202e189`、`021bf1dc`：增加独立 `docs/validation/hdr-route-matrix-v7.3.json` 和 Python CI 校验 `tool/routing_ci/test_hdr_v73_matrix.py`。13 个源组×C1-C4 共 52 格、28 个适用路径、15 个额外边界/生命周期必测项目（29 为笔误，程序化清点 28，本地复核已更正）。普通 SDR 不进入 HDR 的 C1；只走独立 sdrDirect 预检。当前所有适用路径均为 pending，`releaseReady=false`；没有对应 path/case 源码 SHA、设备/参考目标、candidateId/stage 和证据产物时，不允许置 accepted。任何回退播放成功均不能替前序路径验收。
- 本轮最新实现提交 `021bf1dc60a8019342a0c678128d74641a5edf5e`。截至最后实际查询，该头 `Routing source checks` run `38492518746` 状态 queued；其它同 SHA workflow 仍有 pending/in_progress，不得把中间版本、取消运行或旧源码的成功沿用为此头通过。

本轮尚未完成：真实 FFmpeg/mpv 逐帧元数据交付与 C3/C4 的实际清理证明、HDR10+ 和 Vivid 完整 C1/C2 实现、P7 残差/增强层、LG P8.4 的 PQ 实际输出路径、PiliPlusX dirty 配置/版本迁移收口、全量最新源码原生构建与设备验收。**切勿把本轮的意图模型或待实现错误返回当成动态映射功能完成。**

本地接手下一步：`fetch` 远端真实 routing HEAD，先保留现有工作树 dirty 差异（主仓 `video_player_media_kit/analysis_options.yaml`、PiliPlusX 多文件、FFmpeg `configure`），禁止 `reset/force-push` 或另起分支重做。按该 SHA 跑 media_kit_video 与 media_kit_hdr_lab 的严格 analyze / 全量 flutter test，额外跑 Python matrix test；重点核对 HDR10→Vivid 来源重分类是否在 output owner 安全门下按需重建、失败注入后续路由及元数据状态报告的真实性。CI/本地验证未通过前不扩大到 FFmpeg/mpv/libplacebo。通过后续接 App 原有 dirty 集成及真正 native 路径实现，所有验收与源码身份分别入账。

### §11 本地验证回执（2026-10-14，本地 agent，ba97ab2c）

- 严格验证：双包 `flutter analyze` 零 finding；media_kit_video 788/788（含 5 项元数据所有权契约测试）、media_kit_hdr_lab 298/298；`tool/routing_ci/test_hdr_v73_matrix.py` 4/4 OK。hosted 该头 Routing source checks = success（Darwin viewport/query/OHOS 同绿）。
- V1 复核（0 blocking）：重分类重建由 HdrRoute equality 含 metadataHandling 驱动、经 _preferCurrent/attempted/admit 正常门，candidateId 因源类派生必然不同；`metadataHandlingObserved` 为恒 null getter、无任何赋值路径（"不伪造已被应用"结构性成立）；矩阵 52 格与 §4.3 逐格一致，accepted/releaseReady 门在 JSON 与 Python 两侧 fail-closed 强制。
- 记录在案的后续项：§4.4 "C2 映射器失败不禁用 C4"当前依赖层不可表达（C2/C4 共享 dataspacePq/topologyPlatformView 标签，无仅属 C2 的依赖可注入），矩阵以 `c2FailureThenC4` pending 必测项承认；`requestedMetadataHandling` 的 `?? requested` 回退分支无专测；矩阵 hdr10×C2-C4 notApplicable 与现行运行路由的分歧为已知分阶段状态（矩阵只控验收不控准入）。
- 下一步（§11 原文）：FFmpeg/mpv/libplacebo 真实逐帧元数据交付（B1/B2）前置条件盘点——需要 HDR10+/Vivid 合法测试样片（现素材仅 p5/p84/hdr10）、在线设备与 FFmpeg/mpv 工作树 dirty 对账；App 侧 dirty 集成收口待用户提交 PiliPlusX WIP。
## 12. 2026-10-14 B1/B2 元数据识别与映射故障归因（实现后验证交接）

**状态**：B1/B2 部分代码已实施并分仓库提交；Dart 源码宿主测试已 green，mpv 原生源码的编译、最终产品链接和真实设备观察仍未验证，故在此停于本地 native 验证门。继续使用唯一权威开发分支，不开新支路，不修改用户 dirty。

### 12.1 可核对的最新源身份

- `Goodwu/media-kit:routing/MK-ROUTING-20261011`：本轮基于本地 agent 已提交的 `d62fb72c0fbeb30e47ef7e1167e07d1be669d50a` 快进，按序 `497bf0b2`（mapper 独立依赖）、`36b3e304`（修正测试依赖集）、`c193b67d`（HDR10+ 源事实链）、`78d0f11e`（八项用例）、`36148f52ae6744d33fa3240f2108b0c9f0e1be19`（Session 回归）。文档之后的 SHA 仅为交接归档，不将上一代码 SHA 的 CI 篡改为新的构建验证。
- `Goodwu/mpv:media-kit/android`：`c11426b67a96747c74dfd2a1b0a0340af9696103` → `4f036f5cfa493e53dbe8fe2aa2cd5e356b2fc7b1`。修改 `video/mp_image.h`、`video/mp_image.c`、`player/command.c`，基于当前 `AV_FRAME_DATA_DYNAMIC_HDR_PLUS` 设置每帧 `hdr10_plus` presence，正确参与动态更新、复制与非静态比较，公开 `video-params/hdr10-plus` bool 子属性。映射是否真实执行及动态显示链是否转发不由 presence 位证明。
- `Goodwu/FFmpeg:lg-p84-d1-vui-fix-20261010` 当前远端 `d4bb79394b98d6247887e169998778474f43887e`；本轮未更改，原本本地 `configure` dirty 与生成目录保留。现有 HEVC/Vivid/HDR10+ SEI parser 不重写；是否走完整 MediaCodec 逐帧 side data 需要实测后才定点补缺口。
- `Goodwu/libplacebo` 当前工作根 `ea700489`（已知并不必然是最终链接版本）；未更改。现有 HDR10+ mapping 与其支持窗口/版本限制另行核对；Vivid 的规范映射尚未实施。
- PiliPlusX `routing/MK-ROUTING-20261011` 仍有原本 WIP：`hdr_output.dart`、`route_options.dart`、`pubspec.yaml`、测试与任务记录等；主仓本地 `TASKS.md` 与 LG P8.4 计划也 dirty。均未修改、重置、强推。继续原 App WIP 对接，不得将该分支误认为新代码已使用。

### 12.2 已实现的具体行为

- **C2 映射器特有失败**：增加 `HdrRouteDependency.mapperDolbyVision` 和 `HdrDegradeReason.metadataMappingFailed`，仅挂于可实现的 DV `metadataReshape` 执行实例。若实际执行器能精确抛出 `HdrExecutionDependencyFailure(mapperDolbyVision, metadataMappingFailed)`，Session 只排除这个 mapper；其它依赖同一 PQ dataspace 的 C4 HLG→PQ 不受误排除。新增真实 Session forTesting 故障注入确保 `P8.4 + PQ-only panel: C2 failure → C3 不可行 → C4 succeeds`，没有任何 SDR 出口。本次**仅接好了异常契约和测试注入，native 执行器具体错误上报与实机复核仍未实现，不能冒充 C2 映射器已可靠检测故障**。
- **HDR10+ 每帧源识别**：mpv 原有 `pl_map_hdr_metadata`/通用 `ff_side_data` 保留，新增不依赖 scene statistics 的原始帧事实；库内 `HdrReviewFacts`、locked double sample decoder review、player backend、`HdrSourceClassifier`、`HdrSourceFacts` 和 Session 统一消费三值 `hdr10Plus`。DV 优先于动态帧事实；profile-less 时 Vivid 优先于 HDR10+；同一逻辑 open 两种不同动态制式的肯定事实形成冲突并阻断，不以错误的猜测继续播放。缺失/false 不擦除先前肯定 HDR10+，但新媒体的 open 重新归零来源事实。旧二进制没有 `video-params/hdr10-plus` 时读到空值一律为 unknown，不伪装 false。
- **HDR10+ 分类/静态基线回退**：新增 8 项 `hdr10_plus_source_fact_test.dart`，另外新增 Session 实际 reclassification→rebuild 的 mock 回归（静态 C3 PQ 兼容基线，保留 C1/C2 `routeNotImplemented`，`metadataHandlingObserved=null`）。这些只证明 Dart 合同，不构成原生动态 HDR 成功证据。

### 12.3 实际验证和停止条件

- 代码 SHA `497bf0b2` 的 hosted Routing source run `38502992831`，Python tools / Lab 成功，video **1 FAIL**（旧依赖精确集合缺少 mapper token）；已于 `36b3e304` 迁移回归，没有放宽安全门。
- **最终源码候选** `36148f52ae6744d33fa3240f2108b0c9f0e1be19` 的 `Routing source checks` run **`38503650492` = success**：`media_kit_video` analyze 零 finding、795 项 pass、3 项平台跳过；`media_kit_hdr_lab` analyze 零 finding、298 项 pass；Python audit utility 通过。新增八项源事实及完整 Session 回归确实在日志执行。Darwin viewport run `38503650482` 已读 success；OHOS、query、general 工作流的最后状态要按各自 run 再核，不能提前全绿或把 app/native/device 接受混入 source。
- `Goodwu/mpv@4f036f5c` GitHub Actions 没有发现针对该 commit 的原生 build run，且当前模型环境无法运行目标编译器/NDK、链接 libmpv 并在 Android 上 ADB 实测。**原生验证条件尚不满足，按用户约定停止扩大 FFmpeg/mpv/libplacebo 改动**。源头和已有主库测试不回退；后续本地 agent 在同分支继续，不从 c11426 或 d62fb72c 重做代码。

### 12.4 本地 agent 必须执行的核验

1. 先 `git status` / `git fetch` 各仓库并备份 dirty WIP，分别确认 media-kit 代码 `36148f52`（及其随后归档文档 commit）、mpv `4f036f5c`、FFmpeg/renderer 实际源码输入；禁止 reset、force push 或从历史 pinned JAR/so 代替最新修订构建。
2. 按精确库源码运行 Flutter analyze/full test 与 `tool/routing_ci/test_hdr_v73_matrix.py`（合格输出绑定 code SHA）；在 native 侧重新从当前最新 mpv、FFmpeg、libplacebo、helper 及有效补丁构建和链接，审最终 JAR/APK 的 so 哈希、构建选项和来源；不能把已有旧产物当成验证结果。
3. 用 `TASKS.md` 2026-10-14 列出的 HDR10+ PA/PB、Vivid-PQ/Vivid-HLG 样片核每帧 `video-params/hdr10-plus`、`video-params/hdr-vivid` 的 yes/no/unknown 与 bitstream 真实 SEI、各 source revision、PTS/重排、seek/flush/切源。特别分开 MediaCodec direct/copy、SurfaceTexture 和软件：硬解没有交付时应报告缺口，**不得拿 PQ/HLG 色值或静态基线播放成功伪造动态元数据已交付**。
4. 如果硬解侧丢失：沿 FFmpeg `mediacodecdec.c` 的现有 DV 按输入 AU/PTS/flush epoch 附加机制定点审计 HDR10+/Vivid；补实现前冻结重复 PTS/无 PTS、乱序、seek/EOS 的阳性/阴性预期。HDR10+ 完整版本/窗口映射与 Vivid 标准色彩算法仍须真实实现及参考向量；P7 EL residual 与 LG PQ 输出门照原计划独立待验。
5. 所有源/样片/设备/编译元信息写回本文件及 `docs/validation/hdr-route-matrix-v7.3.json`；仅对应候选真实交付后方可设 acceptance=accepted。不把 `routeNotImplemented` 的合同测试 PASS 当作功能完成。

本阶段 PR#4 [具体交接评论 6159870759](https://github.com/Goodwu/media-kit/pull/4#issuecomment-6159870759) 为源码/CI 结果索引。保持单一 v4 计划与单一开发分支，下一轮从本节最新源码继续。

### HDR10+ reshape 前置条件（2026-10-14 用户裁决记录）

实现 HDR10+ 的 C2 metadataReshape 的**前置条件**为 hwdec 载体逐帧元数据交付工包（2026-10-14 已实证定型）：

- 范围：mediacodec_dovi 模板泛化——输入侧按 AU 解析 SEI 2094-40（及 CUVA 005，同机制同批可覆盖），pts_us/epoch 跟踪，输出侧现有 attach 点挂 `AV_FRAME_DATA_DYNAMIC_HDR_PLUS`/`AV_FRAME_DATA_DYNAMIC_HDR_VIVID`；configure 为 `hevc_mediacodec_decoder` 补 hevc_sei 机制 select。
- 依据（实证）：测试 mkv 的 HDR10+ 仅以码流内 SEI 存在（无 packet 级 side data、无 Block Addition Mapping），hwdec 路径码流直送 MediaCodec 无 SEI 解析 → 元数据全程不可达 → `video-params/hdr10-plus` 恒 false → Dart 三值分类恒 none → reshape 无元数据可消费。证据：`b1hpfix-r1` 轮 + ffprobe packet/stream 级双空 + mpv 本地修复 `9141961531`（packet 转发对 SEI 载体 inert，仅覆盖 Block Addition Mapping 文件）。
- 依赖链：**该工包 → `video-params/hdr10-plus` 设备端可读 true → Dart 三值分类 hdr10Plus → C2 reshape 有真实输入可映射**；缺该工包时 HDR10+ 源维持过渡态契约（静态分类日志 + C3 静态 PQ 兼容基线直通，动态 C1/C2 不合成，矩阵 pending）。Vivid C2 的逐帧载荷依赖同理（CUVA 005 同机制），随批实施。

### HDR10+/Vivid 过渡态契约（2026-10-14 用户裁决，接手双方共同约束）

用户裁决原文：**这两个格式（HDR10+、HDR Vivid）的缺失功能列为待办项；目前报日志、走兼容基线。**

- 过渡态行为即现行行为：源分类/候选/路由日志如实报告（含静态分类事实）；HDR10+ 源走静态 PQ 兼容基线、Vivid 源走静态 PQ/HLG 兼容基线；动态 C1/C2 不合成（无隐式 SDR、无伪实现）；`hdr-route-matrix-v7.3.json` 相关行维持 pending。
- 待办范围：FFmpeg hwdec 逐帧 SEI 交付（mediacodec_dovi 模板泛化，见上文前置条件段）、mpv Vivid 载荷读取/清理/映射、C1 原生 passthrough、C2 完整动态映射。实施基础=B1 缺口地图与三步实施顺序（主仓归档 2026-10-14 B1 审计段）。
- 约束：不得以过渡态基线播放冒充动态功能完成；识别链落地后过渡态行为不得单方面改变，须由用户另行裁决。
- LG 实证：HDR10+ PA 与 Vivid PQ 样片基线直通 EOS（vivid-pq 3/3）；vivid-hlg 阻断于 LG PQ 输出缺口（设备特有，同 p84 族）。

## 13. 2026-10-14 最新用户裁决：B1—B4 整体暂缓

> 本节为**覆盖 §5 B1/B2/B3/B4、§6 动态正向验收和 §7 第二批排期的最新用户裁决**。优先级高于前述历史实施表和 §12「HDR10+ reshape 前置条件」的实施顺序描述。保留先前事实、源码提交与实验记录，不撤销、不重写，也不据旧表继续分配开发。任务 ID 仍为 MK-ROUTING-20261011；不新增实现分支。

### 13.1 本阶段唯一产品目标：静态兼容基线

- **HDR10+ → 静态 PQ 兼容基线**；**HDR Vivid-PQ → 静态 PQ 兼容基线**；**HDR Vivid-HLG → 静态 HLG 兼容基线**。当实际目标无法呈现 HLG、而完整 PQ 输出契约可用时，沿已有 **C4 HLG→PQ** 静态兼容转换（这不是 Vivid C2）；C4 也不可用时，原样报错阻断。
- 源分类、候选、选中路径、退回原因、真实显示/解码事实必须如实记录。兼容基线成功只能报静态 HDR 成功，**不能报 HDR10+/Vivid 原生动态、动态映射或逐帧动态元数据消费成功**。
- 已存在的 C1/C2 候选定义、`routeNotImplemented`、`metadataHandlingObserved` 未证实状态和审计事实保持可见；本阶段既不实现也不启用 HDR10+/Vivid 的动态 C1/C2。没有隐式 HDR→SDR、SDR→HDR 或 PQ→HLG；不引入开关、设备白名单或靠虚假能力值绕过。
- **当前播放行为不得因识别元数据或构建新版本而自行切换**：即使日后已有逐帧元数据交付能力，本期仍走上述静态兼容路径。动态行为的研发恢复、默认执行或发布，均须用户另行明确批准。

### 13.2 B1—B4 全部移入延期队列

| 工作包 | 新状态 | 本阶段禁止新开展的范围 |
| --- | --- | --- |
| **B1 FFmpeg** | **DEFERRED_BY_USER** | HDR10+ ST 2094-40 / Vivid CUVA 005 的 MediaCodec 输入 AU/SEI 解析、PTS/epoch 关联及动态 AVFrame side-data 回注；为动态 passthrough/映射而改 decoder 或 SEI 构建接线 |
| **B2 mpv** | **DEFERRED_BY_USER** | 为动态 HDR10+/Vivid 增加元数据载荷消费、动态映射分发、C1 原生交付路径、动态处理证据以及伴随 native 实现 |
| **B3 libplacebo** | **DEFERRED_BY_USER** | HDR10+ C2 算法/版本窗口补齐、Vivid CPU 参考/公共元数据结构/GPU shader/映射算法、动态正向测试 |
| **B4 Android/其他平台动态适配** | **DEFERRED_BY_USER** | 为 HDR10+/Vivid C1/C2 增设 decoder/Surface/display 原生动态传输、平台特定 metadata 管线和动态 HDR 输出适配；不以动态设备认证作为本阶段阻断 |

**范围边界**：暂停整个 B1—B4 新增工作包，而非只暂缓“功能验收”。§12 的 B1 硬解 SEI 缺口地图与 mpv 本地 `9141961531` 等既有未合入工作，改为保存的延期背景，不再被视为「下一步必须实施」。现有生产源码、已经提交的局部元数据存在性接口和历史实测事实不强制回滚；本阶段不以它们为理由扩大开发，也不把本地未推送提交未经验证直接推入产品集成。

本决定只针对**本任务 B1—B4 工作包**；对静态兼容基线的必要漏洞修正、既有已验证 Dolby Vision 路径回归、完整输出链的来源溯源，不得误称为新开发 B1—B4 动态功能。若确需改动 B 包原生代码以修复静态播放，先单独登记该兼容性问题与范围并走既有验证门，不自动恢复已暂缓工作包。

### 13.3 当前仍继续的项目工作（不依赖动态 C1/C2）

1. **A：静态基线和失败语义**。保持现有 planner/Session 正确选择 PQ/HLG 兼容直通、需要时 C4 HLG→PQ、缺失路径返回原始错误，以及 HDR 失败绝不隐式转 SDR。只修真实的当前输出故障。
2. **LG P8.4 / Vivid-HLG 当前静态输出缺口**。按已落盘 `docs/plans/lg-p84-yuv-window-reopen-20261014.md` 的范围处理 LG C4 PQ dataspace / YUV config49 HWC 窗口问题；能力门和构建槽位 D1/D2 保留待决，不把 C2 动态映射作为先决条件，也不能放松 owner/ACK/lease 或已接受 YUV8 合同。
3. **C1 PiliPlusX**。审查并收口 App 既有未提交改动、依赖版本、旧实验配置迁移、预测与实际路由报告的一致性。UI/日志必须清楚区分「静态 PQ/HLG 兼容基线」和「动态 C1/C2 尚未实现」，不可显示动态成功。
4. **C2 构建/CI 和当前兼容路径 QA**。只构建本阶段真正适用的当前源码，不拿历史二进制验证新代码；记录最新 commit/dirty patch/JAR/APK/so 的身份。保留全量 Flutter/source CI、LG/LYA 等实际静态 PQ/HLG 输出、C4、重入/seek/生命周期/性能的验证，不为被延期的动态链额外开新 native 构建或设备开发批次。

### 13.4 原完整矩阵如何记账（禁止假验收、禁止误阻断）

`docs/validation/hdr-route-matrix-v7.3.json` 保留作为**原完整愿景的长期账本**。HDR10+/Vivid C1/C2 六个候选必须仍为 `pending`，新增 `scheduling=deferredByUser` 标注；**不得**改为 `notApplicable`、`accepted`、`skip=pass`，不得通过删行使原矩阵假全绿。`releaseReady=false` 仍表示原完整愿景未验收，**不等于本期静态兼容基线必须等待 B1—B4 完成才能开展上线决策**。本期只对静态兼容路径和现有安全边界独立收集可追溯验收证据；具体上线仍遵守既有产品/设备质量门，不能仅因 B 包延期就宣称可发布。

### 13.5 接手保护与恢复条件

截至本裁决读到的权威远端：`Goodwu/media-kit:routing/MK-ROUTING-20261011@3e2291bdda0efd3848c3530ca84329c0edc21131`、`Goodwu/mpv:media-kit/android@4f036f5cfa493e53dbe8fe2aa2cd5e356b2fc7b1`。本地 mpv `9141961531` 在其远端之前 **ahead 1**（未推送，保留）；FFmpeg `configure`、PiliPlusX 多文件、主仓 `TASKS.md` 及 LG 计划文件有既存 dirty/untracked。**不覆盖、不清理、不强推、不再建分支；本次只追加权威计划/延期标注**，避免踩坏本地 agent WIP。

只有用户重新明确要求开展 HDR10+/Vivid 动态 C1/C2 时，才重新审查和安排 B1—B4；届时先核最新代码、测试素材及现有已完成工作，再决定其启动顺序，绝不按旧 B1 计划自动复工。
