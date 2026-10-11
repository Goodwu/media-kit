# media-kit 路由修正与 PiliPlusX 对接：执行方案 v3

任务 ID：MK-ROUTING-20261011。更新日期：2026-10-11。
状态：已获开发、提交、推送和环境允许范围内测试授权；实现、编译和 CI 结论以精确提交及实际结果为准。
本文件是唯一执行方案。v3 纳入用户确认的显示目标查询、源规格解码过滤、跨平台公共语义和高级配置方向；不是重新启动 RFC v1 的大范围重写。

## 1. 用户已确认的要求（不得丢失）

1. HdrCapabilities.query(player:) 是自有接口，无兼容包袱。能力查询不依赖已创建 Player；新入口为 VideoRouteCapabilities.query(target:, sources:)。迁移调用点后删除无效 player 参数，不建立长期 V1/V2 兼容框架。
2. 源规格是必需的产品能力：选源前按实际 codec/profile/level、位深、coded size、帧率等组合查询解码支持，不能只判断显示器 HDR 或各维度独立最大值。sources 列表允许为空以仅查询环境；有源时必须使用其规格。
3. 使用最小正确闭环，优先复用现有 native 能力，不同时铺开 Android/FFmpeg/mpv 大改。完成原三批及 PiliPlusX 接入；第三批逐项核实 native 缺口，无缺口用证据关闭，不为完成批次制造改动。
4. 普通自动模式以 allowExperimental=true 为主要验证场景，同时测试 false。实验门只改变成熟度，不授予能力、不绕过颜色正确性和 owner 安全门。
5. 及时全文落盘、提交和推送，维护唯一台账。严禁下一轮把已提交实现重做在另一个分支。已实现和已验证分开记载。
6. 测试候选使用相关仓库最新源码及全部适用修改，不用旧钉定源码、APK/JAR/so 替代。记录解析到的 SHA 是溯源而非选择过时输入；编译器按当前 App 声明的契约使用。
7. GitHub CI 必须实际运行并核对最终候选，不能以已添加/触发/排队代替 success；PiliPlusX 构建与测试不是可选后续。
8. 保留 LG 已批准 YUV8、成熟度提升、像素与颜色配方及 owner/ACK/lease 协议。不重开已延后 10-bit、lease 融合课题。

## 2. 范围与执行路径

### B1：现有路由与复核纠错
- 已完成的 profile32/256、native 显式 EL=false、删除 HLG-over-DV 放行和分类器保留未知 EL 均继续保留，不重做。
- 未知 P8/冲突信息不得推成 SDR；原始源与处理后帧事实不得互相擦除。
- 增量表达真实 importer/presenter、依赖和输出重建要求，不建立任意组件笛卡尔积。
- 使用现有 android-mediacodec-info 复核实际 decoder/MIME/native-active，不把 configure 成功当作呈现证明。
- 按失败环节保留 exclusions；兜底不重用已知错误链、不违反用户硬约束。重试有界且保留根因。
- 保留成熟度产品决策，补负向、生命周期和常规 SDR 回归。

### B2：统一查询接口、源规格匹配、最小 Android 接线

#### B2a 数据契约
- VideoSourceSpec：codec 或明确的 codec 标识、profile/level、位深、coded width/height、frame rate；未知字段保留未知。验证非法/非有限/非正数、过大批量和重复输入。规格不包含媒体 URI，查询不下载或打开媒体。
- VideoOutputTarget：明确区分无目标、FlutterView、显式 OS display、显式默认显示器。Flutter view ID、OS display ID、window/Surface/Player handle 不能混用。
- 不传 target 只查询设备/运行库/解码能力，显示部分为 unresolved。显式无效目标不得默默回落 DEFAULT_DISPLAY。
- 快照分为 runtime/device、display target、逐源逐 decoder 支持与执行期待验证条件。状态至少为 supported / unsupported / unknown；查询故障不伪装成空能力成功。
- 区分“系统声明可解码”“符合当前路线要求”“可实时播放”“实际已经输出 HDR”。源过滤不以可解码冒充 HDR 可呈现，也不以显示不支持 HDR否定 HDR 源可被正确 tone-map。

#### B2b 平台采集和纯预测
- 新公开入口 VideoRouteCapabilities.query(target:, sources:)；无 Player 参数、无应用 Player 创建、无 decoder configure、无 Surface/EGL/lease 或私有 ABI 试调。
- Android 批量复用 MediaCodecList，按一个完整源规格在同一个 decoder 上匹配。尺寸和帧率联合查询；profile/level 使用平台定义的对应规则，不对所有编码直接比较任意整数大小。
- 显示查询绑定实际目标；FlutterView 必须通过可验证的原生关联解析，不把 Flutter display.id 数字直接当 Android Display ID。不能解析则 unknown/unresolved。
- 普通 HDR/SDR 及 native DV 的 decoder 约束分别表达；存在系统 decoder 不证明 mpv 已选中它，严格 native 路线仍复核现有事实。
- predict 保持同步纯函数，缺少指定源匹配时返回未确定/条件结果，不能偷偷查询或沿用其他源规格的支持。
- 默认无持久跨目标缓存；后续缓存按 runtime/target/mode/source revision 键控。能力变化时重新查询/规划，旧快照不能作为新 Surface 的授权。
- 删除旧查询中无效 Player 参数，迁移库内、lab 与 App 调用和测试；单个实施检查点可暂存迁移未完项，但最终不能只加新 API 而 App 仍走旧逻辑。

#### B2c LG 及其他平台
- 普通 Session 的 LG 输出必须经过精确设备门、bridge owner、Surface tuple、完整 YUV 契约；选中 baseLayerConvert 不等于自动接通验收过的 YUV 链。
- 资源 owner 与严格实验许可分离，不绕过 native 授权，不修改验收像素/metadata 数值。
- 统一源规格、约束、候选、原因和报告；平台 adapter 保留可靠执行器。未接入的平台显式 unknown/unsupportedControls，不把 Android 枚举硬套到其他系统。
- 逐平台接入公共 planner/Session，先有实际实现再暴露支持。VideoRouteSession 是后续统一命名方向，不以重命名替代能力。

### B3：按证据补齐 native 缺口
- 已有 ac4f7889 的提取工具与实际 P8 MIME-only 选错 decoder 反例继续使用；定点修复需要覆盖空 profile 列表与多 decoder，不重建同一 harness。
- 优先复用现有 P5/P8 Android profile 映射、dovi=auto/on/off、mpv decoder-info v1 与容器事实。逐项验证原始源/元数据交付，而非只证明选项存在。
- 不默认引入 Dart 点名 decoder 协议。on_preloaded、全新跨平台执行器不是源规格查询的前置。
- 每项输出修复+测试或已有能力/明确范围+依据；未实测不标全完成。

### APP：PiliPlusX 源过滤与实际使用
- 继续既有 PR#1 分支及已实现 portable overrides、源码绑定检查器和 CI，禁止从旧观察重建 App 分支。
- 从 DASH 读取每个候选的 codec、coded size、frame rate 等构造 VideoSourceSpec，一次批量查询并按对应源结果过滤，不以 viewport 尺寸替代 coded size。
- 确定不支持的源排除；unknown 与支持分别呈现，由显式选择策略决定是否受控尝试，不静默假报支持。无法获得规格的候选不凭质量编号断言 decoder 能力。
- 当前 View/display target 在创建 Player 前即可传入。App 不维护 SDK、型号、decoder 私有适配规则。
- query/predict/report 使用同一目标和规格；HDR 选档同时考虑解码支持与 HDR 路线，不将任一等同于另一。
- 删除查询失败后无条件 lastCapabilities 回退和“无 Player 则无 P5”旧说明。能力改变刷新；最终执行用实际事实复核。
- 保持最新 media-kit 源码依赖，运行全部 App 测试、严格 analyze 和可用编译；bundle 明确不等于完整 native APK。

## 3. 高级配置方向（纳入计划，按能力逐项交付）

采用一个 VideoRouteOptions/约束模型，避免并行私有 mpv 开关。维度分别是解码、帧导入、渲染、GPU API、HDR/动态元数据、输出精度、性能和失败策略。

每项区分 auto / prefer / require：prefer 只排序，require 过滤并在不可满足时解释失败，不静默覆盖。实验门独立。全局默认、应用偏好、用户覆盖先合并成一份不可变有效选项，同一 planner 消费；实际能力和正确性/所有权规则不能被覆盖。

先开放有真实执行路径的硬解/软解偏好及约束、HDR/SDR目标和失败策略；后续增加 decoder/backend、导入、画质和功耗设置。系统未提供可靠性能/功耗数据时标未知，不制造分数。GPU API、renderer、importer 不是任意互换组合。

提供候选列表与拒绝/待验证原因，区分 requested/effective/observed。影响 Surface/decoder 的选项按现有事务重建，支持原位更新的参数另行标识；旧 generation 不得写新 owner。严格诊断 route lock 独立于普通高级偏好。

## 4. 唯一开发记录与防重复交接

方案：本文件。中央机器台账：docs/plans/media-kit-routing-handoff-20261011.json。
media-kit 权威链：Goodwu/media-kit:routing/MK-ROUTING-20261011 / PR#4。
App 权威链：Goodwu/PiliPlusX:routing/MK-ROUTING-20261011 / PR#1，基于 fix/darwin-video-output-rebuild-barrier 的最新已合并工作。App 台账为 docs/plans/media-kit-routing-app-handoff-20261011.json。

每轮先读台账、refs、PR 与最新结果评论。已实现但 CI 失败仍是 implemented，不退回 planned，不重新开发、不 force-push/reset 远端或用户 dirty tree。每个可恢复阶段提交并推送、回读确认；长构建前和交接前不能仅留临时文件。

记录 taskId、状态、仓库/分支、基线、实现 SHA 或可解析 commitAnchor、测试范围/命令/退出码、CI run/head、依赖、未完成项和下一步唯一动作。源码正在验证时可以 PR 评论保存结果，后续代码提交同步台账，不以文档更新反复取消构建。

## 5. 构建输入纪律

- 开始构建前确认相关权威 ref 最新头，包含全部适用修改；构建后重新确认。变化后的结果只能证明记录的输入，不能覆盖新头。
- 不回退历史 known-good 源或旧二进制作为候选。只允许与当前完整输入可证明一致的中间缓存；源码 SHA/工作树摘要和产物哈希用于溯源。
- FFmpeg 原有 configure dirty 将 FFMPEG_CONFIGURATION 置空，保留并查明实际构建意义，不擅自清理。
- 现有外部 relink/r22 helper JAR 配方未证明为完整最新构建，需审计并构建所有适用输入，不能因 ninja 成功就宣称整包最新。
- 不从本地存在 so/JAR 推断实际链接来源；核对最终包。旧包仅用于明确标注的对照。
- 不提交凭据、私有媒体或未经清理的环境日志。

## 6. 测试和验收

L0：原准入与成熟度反例；新增源规格验证、完整相等键、profile/level、Main10、4K60 vs 4K30/1080p60、缺帧率/尺寸、多个 decoder、软件与硬件分别支持、unknown/unsupported/query error、不可变快照、源结果与请求一一对应；require 不可被回退绕过。

L1：目标无 Player、未挂载/销毁、多 engine/View、换屏/mode、查询返回乱序与失效；纯 predict 不跨 channel；源/query/Session 一致。保留并发 open、迟到事实、旧 owner、重建/超时/清理失败/多 Session/fullscreen/seek/前后台测试。

L2：Android 查询只读无 configure、无 EGL/Surface 创建；目标 Display 解析、源规格组合 API、畸形输入/空 census/查询异常、软件识别来源。平台真实能力验证与宿主模拟证据分开。

L3：media_kit_video/lab analyze 和全量单测、相关 Android JVM/编译、App 全量 Python/Flutter tests、严格 analyze、Dart/assets 编译以及最新 native 产品构建。实际相关 CI 对候选头完成 success 才验收，不能禁用失败用例或降低检查代替修复。

L4：设备接口真实可用才测 LG/PQ-HLG/现代 DV/普通 SDR；颜色与性能分轮。无设备不伪造。LG presented-FPS 已知不可观测，不把 vfps/提交帧率当面板呈现率。

完成条件：原三批逐项闭合、App 确实使用新接口按源规格过滤、最新源码测试与编译完成、相关 CI 成功；不覆盖项明确记录，不能把新查询实现等同于全部跨平台执行器或完整 native 验收。

## 7. 本次续接检查点与立即实施顺序

续接观察：media-kit PR#4=ef3951eb239d48747f4cbb2c3c2749fde40ff274；App PR#1=8fc8f2c618b96b60b29d576e4242d0e153fd00bd。这些是观察值，不是未来构建钉定值。

已有源码/viewport/OHOS CI success 与 App 231 Python/156 Flutter tests、bundle success 见两 PR 最新结果记录；App analyze85 info、旧Build startup_failure 和完整 native 构建仍开放。旧台账中的 App branch=null 已过期，本轮同步修正。

当前优先级：先推送本 v3 计划，再实施 B2a/B2b 的可测试完整小阶段（源规格、目标查询、支持状态），及时保存；随后迁移 Session/lab/App 调用并把 DASH 候选实际纳入过滤，独立 CI 验证。高级配置分阶段开放有实现的项，不伪造未接入平台能力。继续保留 B1余项、LG 接线及 B3定点修复，不因新增 API 忘记它们。
