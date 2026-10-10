# media-kit 路由修正与 PiliPlusX 对接：执行方案 v2

任务 ID：MK-ROUTING-20261011。更新日期：2026-10-11（Asia/Seoul）。
状态：已获开发、提交、推送与环境允许范围内测试授权；实现和 CI 结果以任务台账与执行证据为准。
本文取代 RFC v1 的实施范围与兼容性决定；v1 只作历史设计，不能直接按其大范围重构执行。

## 1. 用户已确认的要求（不得丢失）

1. HdrCapabilities.query(player:) 是自有接口，可修改或删除，不承担向后兼容包袱；PiliPlusX 调用点与测试必须同步。
2. 使用最小正确闭环：先复用现有 native 能力，不同时铺开 Android/FFmpeg/mpv 的大改。
3. 完成三批工作及 PiliPlusX 对接；第三批逐项核实 native 缺口，确无缺口的项用已有实现与测试证据关闭，不能为了“完成批次”制造改动。
4. 普通自动模式以 allowExperimental=true 为主，同时测试 false；实验门只影响成熟度，不改变能力、颜色、安全或所有权门。
5. 全文尽早入库，维护唯一任务台账。禁止下一轮把已开发并提交的功能重新实现到另一分支。
6. 测试版本必须从最新已修改源码构建；不以旧钉定源码、旧 APK/JAR/so 替代候选。记录本次实际输入 SHA 是溯源，不是锁回历史实现。
7. 用户已推送 GitHub，可自主开发、提交并尽量测试；需实际跑通 GitHub CI。不能以工作流已添加或已触发声称成功。
8. 保留 LG 已批准 8-bit 路线、成熟度提升、既有输出/颜色配方和 owner/ACK/lease 协议。不重开已延后的 10-bit、lease 融合课题。

## 2. 范围与执行路径

### B1：现有路由与复核纠错
- 对齐 Dart 的 DV profile 准入与现有 FFmpeg P5=32/P8=256 配置；单层结构要求一致。
- 删除 DV 显示声明即可放行 HLG 的通用例外；保留真正 HLG 输出及 HLG→PQ/SDR 路径。
- 未知 P8/冲突源事实不得推成 SDR；原始源与处理后帧事实不互相擦除。
- 现有 route 增量表达真实 importer/presenter/依赖与输出重建要求，不先建立任意组件组合框架。
- 利用现有 android-mediacodec-info 复核实际 decoder/MIME/native-active；不能把配置成功当作呈现证明。
- 失败记录保留，按实际失败环节隔离；兜底不得重新授权已知错误颜色路径或违反硬约束。
- 原有成熟度产品决策不撤销；新增精确负向和生命周期回归测试。

### B2：最小 Android 查询与既有后端接线
- 删除或移除 query 的无效 player 参数，统一能力查询，调用方不因 Player 有无获得不同静态能力。
- 仅在需求和现有模型确有缺口时增量加入目标显示器与源规格匹配，未知项明确记录，不伪造支持。
- 普通 Session 的 LG 输出必须通过现有精确设备门、bridge owner、Surface tuple 以及完整 YUV 契约；不能仅删 direct 就宣称已自动接通 YUV。
- 资源 owner 与严格实验许可区分；不绕过 native 授权，不修改已验收像素/metadata 数值。
- 公开接口可以精简，不为自有 API 引入长期 V1/V2 兼容层。

### B3：按证据补齐 native 缺口
- 逐项核实 decoder 选择、原始源事实和元数据交付是否已由现有接口满足。
- 现有 FFmpeg P5/P8 profile 映射、dovi=auto/on/off、mpv decoder info 优先直接复用。
- 多 decoder 选择反例确实成立才定点修选择，不默认引入 Dart 点名 decoder 的跨层协议。
- on_preloaded、完整跨平台执行器、全新查询框架不作为默认前置；只有具体正确性要求无法达成时单独扩展并记录原因。
- 每项产出“修复+测试”或“现有能力满足/不在本次目标+依据”，不得无证据标全完成。

### APP：PiliPlusX 接入
- 同步 query/predict/report 改动，移除 player 空参数、过时说明和无条件静态快照回退。
- App 只处理源规格、策略偏好、预测与展示；不加入 SDK、型号、vo/hwdec 私有判断。
- 更新未知源与 native DV 展示边界；依据候选状态选择档位。
- 依赖本次最新 media-kit 源码构建并测试，不能仍引用旧发布包。

## 3. 唯一开发记录与防重复交接

权威方案：本文件。机器台账：docs/plans/media-kit-routing-handoff-20261011.json。
任务/PR/分支必须按仓库一一登记。本轮开始先读台账、远端 refs、提交和现存 PR，确认功能是否已经实施；若功能已提交只核对/修复，不重做。尚未建立权威开发分支时先登记再写功能。禁止第二轮为同一工作创建另一独立分支。

每项记录：taskId、状态(planned/in_progress/implemented/validated/blocked)、仓库、权威 ref、基线、实现提交、测试提交、CI run/head SHA、依赖、未完成项与禁止重做项。
实现已提交但 CI 未通过必须标 implemented，不能改回 planned。下一轮先 fetch/比对祖先；工作区与远端分歧时禁止 reset/force-push，先保存差异并核对。
每个语义提交尽量同时更新台账；无法自引用 SHA 时以下一记录提交或“含 taskId 的祖先提交”为解析锚点，禁止伪造 SHA。
结束前记录当前最后提交/CI 状态、下一步唯一操作、已存在但未验证的代码、环境限制。

## 4. 构建输入纪律（覆盖旧 RFC 的固定 native 产物策略）

- 开始构建前确认每个相关仓库的权威 ref 最新头；候选包括本轮全部源码修改。
- 不回退到历史 known-good 源或旧二进制作为验收对象。已声明未改动的 native 源也从当前允许的最新源构建；只能缓存与当前完整输入可验证一致的中间结果。
- 工作区 FFmpeg 存在既有 dirty：先查明内容和来源，不清理、不猜测 GitHub 已包含它。需要该配方而 CI 无法取得时，显式处理或报告构建阻塞。
- 记录源码提交/工作树差异摘要、实际依赖来源、工具链、命令和退出码、最终包 SHA；构建后重新核对输入，变化则本轮结果不能覆盖新头。
- 旧包仅能作明确标注的对照，不能证明新候选通过。
- 不从本地存在某个 so/JAR 推断它是实际链接/打包输入；必须核对真实输入与最终包。

## 5. 测试与验收

### L0 Dart 规则
profile 32/256/多 decoder；DV 无 HLG；P5 无 GPU 但 native 可用；P8 unknown/EL unknown；源规格组合；experimental 两态；实际 importer 依赖；LG 设备门；报告不超证据。

### L1 Session/Widget
可控异步阶段与时钟：并发 open、迟到事实、外来 FILE_LOADED、重建、超时未取消、stop/restore/ACK 失败、多 Session、全屏/seek/前后台；旧 owner 不可修改新 owner；所有降级有界且保留根因。

### L2 Android/native（有改动的层）
查询协议、显示目标、decoder 精确匹配、RPU 控制及与实际帧的对应；旧接口可复用时不制造新 ABI；涉及 native 才扩展链接/负例矩阵。

### L3 App/CI/构建
media_kit_video/lab/必要 media_kit 单测与 analyze；PiliPlusX 对接测试与可用平台编译；GitHub CI 对每一实施头真实执行。Flutter/OHOS 特有环境或签名不可用时用 blocked/skipped 明示，不以禁用关键测试得到绿灯。

### L4 实机
只有设备可操作接口真实可用时执行；LG/PQ-HLG/现代 DV/普通 SDR，颜色与持续性能分轮，设备动作不凭空宣称。本轮缺设备不伪造验收。
LG 的呈现级 FPS 已知不可观测，沿用提交侧指标与人工验收范围，不再次用 vfps 当 presented FPS。

完成条件：三批有逐项闭合记录、PiliPlusX 使用最新库、最新源码测试/编译成功、相关 GitHub CI 对最终候选头 success；无法覆盖项清晰列出。不把设计、补丁生成或 CI queued 当完成。

## 6. 当前观察与立即执行项

工作区观察：main main@0f0f1525 clean；mpv media-kit/android@c11426b67a clean；FFmpeg lg-p84-d1-vui-fix-20261010@d4bb79394b dirty；PiliPlusX fix/darwin-video-output-rebuild-barrier@73afb9b66 clean。
远端已核对：Goodwu/media-kit main=0f0f1525a2c1f3569052412775b8ba939963614b，当前无 open PR。
这些是观察基线，不是要求以后钉定的构建版本。

当前执行：先核查远端现有任务、分支、CI与可执行环境；将本文全文和台账入库；随后从唯一开发链开始 B1，继续 B2/B3/APP。环境/权限限制以实际工具返回为准。
