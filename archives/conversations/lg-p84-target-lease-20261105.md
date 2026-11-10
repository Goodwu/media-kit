# LG P8.4 目标尺寸 lease（perf round 3）

## Current State

- **派生项目（2026-11-10）**：P5-on-LYA 性能定位与优化（0.38fps 异常）拆分至新项目 P5-NODV-RESHAPE-PERF-20261110，context `p5-nodv-reshape-perf-20261110.md`；本文件此后不再承载该项目进展。
## Current State

- **最终状态（2026-11-10 收敛，此前逐条过程记录已并入下方历史区与本仓 Git log）**：
  **G-9 Lead 终裁通过**（S6 同 sync 8 轮 4 对：P1 +10.21%、P3 +11.02% 过线，P4
  +9.40% 差 0.6pp，P2 频率混杂剔除；判据字面 2/3 留档在案）。收尾 critical
  复审 BLOCK（2P0+6P1+2P2）→ 全部 P0/P1 修复（环满解耦记账、copies_ok=真实
  发布数、HOL quarantine tracker 填充、LP 禁用互斥握手 fail-closed、HAVE_ANDROID
  门、分析器 fail-closed+频率窗口对齐、md5 回执归档），修复后重建 lgp84-s5k
  （LG/LYA 双机 md5 门过）。M4 热态（5 轮，r 观察 +8.62%，LG 升温有限 26-27°C
  如实登记）、M3c 字幕共存演练（账本全净；渲染观感归 M3b）、M5 LYA 回归
  （lease 路由结构性不适用 + Mali 计时 OOM 观察项）均完成并登记 TASKS.md。
  剩余需用户参与：M3b 观感验收；截图/非等比演练（需 lab 触发通道，Open）。
  三仓已提交并推送（perf2/lg-p84：mk f18ef2df+修复提交、mpv 5278651a+修复提交、
  lp ebefbc18）。定向重审 verdict 见 TASKS.md 收尾条目。

- **M2′ 计时口径设计（2026-11-08，修订中）**：specialist 设计稿（ra_ctx owner、
  ticket 分段、frame/frame-span 属性值、覆盖账本、S1-S4 切分）归档于
  `docs/plans/lg-p84-frame-gpu-timing-design-20261108.md`（35ce831f…）。独立
  critical 审查：4×P0（LP timer 非自动关闭、ticket 出口表不穷尽、copy 闭合方程
  边界错误、R2 状态机缺失）+4×P1+行号校正；已派回 specialist 修订（LP 显式禁用
  或 capability 门、逐出口状态转移表、分离计数+接收端对账、R1/R2 状态机、验收
  参数冻结）。修订版 r2 已归档并定向复审：P0-1 关闭、P0-4 核心成立；剩 P0-A（compare_fail_transaction 的 submit/abort 路径使 3517 单点 hook 不成立、draw 表误并分支、无 swap 收口）与 P0-B（方程⑦重复计数、HOL 归属）+P1（旁路入口直接记账、G-4 禁止换算法等），r3 增量修订已归档（P0-A 选定 compare/atlas 配置下 owner 不 armed + 提交点不变式探测、P0-B HOL 冻结行为隔离占槽/迟到结果不入账、P1 协议全部冻结含 G-2 种子与 G-11 原值登记），r4 增量修订已归档（HOL 双账分离+X1–X6 恒等式、seg_ref 七情形编码、G-3 三组对照、G-7/G-8 冻结），r5 增量修订已归档（ctx_lost 单向停机策略、双账+X7/X8、E1 五场景、seg_ref 优先级、G-3 六轮块、G-8 收紧；新发现 ra_gl timer 不经 L3 双防登记），r6 增量修订已归档（kind/tstate 拆分、调用边源码契约全名单、R-10 收窄），r7 增量修订已归档（issued 只写一次标志、DCE 集合更名、EV-1 间接可达性核查正式化），第七轮复审通过：设计定稿。**S1 owner 核心已实施**：mks_frame_gpu_timer.h ~460 行（四轴状态机/三模式/双账/停机/HOL/seg_ref 编码/MKS-FGPU-* 日志），E1 12 场景通过，既定回归 17 文件 110 项通过，NDK 语法检查干净。own-bug （FAKE_Q 差一、t_next 未初始化、HOL 差一、R2 span 语义、initialized 守卫）迭代修复如实记录。EV-1 间接可达性核查仍为 S2 前置。S2 完成（LP 22 行 + EV-1 闭合）。S4 接线尝试→V2 复审 BLOCK（3×P0 + 7×P1）→P0/P1 修复完成（extern 链接、懒 init、恢复旧 timer end、acquire 失败 resume、release hooks、draw_exit/flip_close/submit_result）→v24 回归 110 项通过。剩余：EV-1 证据补审、emit 日志接线、S3 分析器、V2 复审确认、S5 设备轮。
- **M3c 真机交互演练（2026-11-08）**：lease ON 播放中 `wm size` 两轮真实 resize：
  2160x1080→重建 `1952x976`、reset→重建回 `2672x1336`，瞬态几何逐映射正确，
  **零几何/acquire 错误**；resize 重绘触发 `lease_reuse≥2` 零错误。原系统状态
  还原（rotation/wm size/灭屏）。字幕/截图/crop 回退无外部触发通道，仍未演练。
  证据 `M3c-interactive-20261108/`（7 日志+SHA256SUMS）。
- **F′ 功能轮（2026-11-08，首次真机消费者验证）**：设备空闲时完成。装机
  `lgp84-iso2-release.apk`（消费者接入 + round2 定义集）md5 门过。F′-off 默认关
  正确（无 target-size 日志、源尺寸 lease、23 稳定样本）；F′-on 首个 fresh map
  即发布 `2672x1336 (src 3840x1920)`，几何校验/acquire/rescale 零错误，VO
  2672x1336，24 稳定样本，busy/频率与 off 轮相当。排查路径记录：两次 invalid
  （缺 `--tap 1440 720`；缺 `MEDIA_KIT_ANDROID_P84_THERMAL_PROBE=true` 导致
  THERMAL_JSON 永不发出——期间用 HEAD-stash 对照排除了我们的 mpv 改动，HEAD 版
  播放正常）；reference-start 冷却过冲超时一次，功能轮改不带热锚。三次 invalid
  现场保留，大流外置 f2-functional-rounds 归档（SHA256SUMS `012187c3…`）。
  **未做**：字幕/截图/resize/retired 真机演练（M3c）、同包 A/B（M2′）、观感
  （M3b）、热态（M4）、LYA+收尾复审（M5）。
- **隔离构建解阻（2026-11-08）**：共享脏 prefix 缺口已按方案闭合，JAR 与测试 APK
  从隔离链产出。要点：clonefile 快照（CoW，共享仓零消耗、写隔离/inode 验证）、
  副本内裁剪、wiped 全量依赖重建（第一轮误复用旧对象，清除后重建——记录在案）、
  ffmpeg 配方机械 diff（修 `mp3*`）、shaderc usr 布局与 .pc 复刻、新 mpv 树
  `_build-arm64-mks-iso`（49 依赖全指向隔离 prefix）。产物：JAR
  `acecfeca672bcd129531cd762f639da6bdb23e9b7570db866eb3bc325e45257c`；APK
  `lgp84-iso-release.apk` `a136df1d3fd467cc764b43cd3bc5a820520e008b3c74df254f68fdf2782c67dc`
  （verify_android_test_apk status=verified，含 mpv/libplacebo/ffmpeg 当前脏态
  receipt）。共享仓前后基线逐行一致（git status+11 依赖仓+3 金丝雀）。磁盘
  11Gi→9.5Gi。方案与执行偏差见
  `docs/validation/lg-p84-target-lease-20261105/isolated-build-bootstrap-20261108.md`
  与隔离根 `bootstrap.log`。未装机、未设备轮；receipt 为构建级自验。
- **gpu-next 消费者接入复审通过（2026-11-08，冻结快照 64e320ef）**：定向 critical
  复审（同一 reviewer 四轮迭代）最终裁决"接入复审通过，以冻结快照
  `64e320ef` 为准"。关闭路径：首版 draw/截图时换算物理 crop（2×P0：fresh 帧先算
  crop 后 acquire、REJECT(34) 读空队列纹理）→ 重构为 acquire 内局部副本换算 →
  DST_CROP 误缩放 P0 与 talloc abort 语义、parts 塌缩修正 → SRC_CROP parts 改按
  修正后 crop 有效比例（renderer 以修正后范围分母，端点 q 输出偏移保持 qD/O
  比例，窄 crop 反例闭合）。v18 回归 16 文件 109 项通过，证据包 19 条目核验
  一致。**边界**：静态与替身验证；不替代行为性缓存证据、消费前预约反例、共享
  OSD 隔离及 GPU/设备/画质/性能验收；再改坐标契约/acquire 生命周期/缓存身份须
  重新定向复审。仍 OPEN：隔离构建 blocked、legacy `vo=gpu` 未 opt-in。
- **gpu-next 消费者第四轮修正（2026-11-08，复审已通过）**：第三轮复审确认
  DST_CROP P0 关闭、OOM 语义一致、生命周期无新问题；残余 P1 为 SRC_CROP parts
  与舍入后 crop 的比例错配（renderer.c:833-840,867-876 以修正后 crop 范围为分母）。
  修复：parts 按修正后 crop 的有效比例（new_extent/old_extent）换算，零/全跨度
  端点精确吸附（`hwdec_scale_overlay_endpoint`），内部端点保持浮点；除零轴回退
  原始比例。复审的两项测试缺口（未断言 part 宽度、循环未重置 crop）已补：契约
  测试改 crop-relative 语义并断言窄 crop 全跨度 part 保持 100%，acquire 循环
  每轮按队列帧重置 crop 且断言 crop 不被重复缩放。v18 回归 109 项通过，日志
  `…-v18-consumer-partscale-20261108/`（SHA256SUMS
  `6646bb3a7624be6ee4575844ab28143cb5f3c89bcf1629bc3008227db96d3974`），
  `vo_gpu_next.c` SHA256
  `64e320efca197e4c8a6429f85e9ae191ffafe16763864994d2fc6f6c06c1c47a`。
  OPEN 项与第四条中的边界声明不变。
- **gpu-next 消费者第三轮修正（2026-11-08，已被第四轮覆盖）**：定向复审
  最终报告（快照 f82d9179）确认前两项 P0 根因关闭、rescale_ctx 生命周期正常、
  请求/清零/悬空指针修复确认；裁决仍不通过的残余项已全部处理：DST_CROP 误缩放
  改为仅 SRC_CROP parts 换算（renderer.c:865-883 语义）；talloc 失败恢复死路径
  删除（ta_talloc.h 映射 ta_x* abort-on-OOM）；parts 改纯浮点等比缩放、不再整数化
  （消除合法窄 part 塌缩与舍入漂移），crop 保留吸附/防塌缩。测试补坐标语义、
  副本数值、窄 part、多次 acquire/release 账本闭合及 talloc 子分配替身；v17 回归
  109 项通过，日志 `…-v17-consumer-fixes-20261108/`（SHA256SUMS
  `9a848d2c337f3499c96b7b1c98daafbddc0606438f127517e5f9c06eba3fbf59`），
  `vo_gpu_next.c` SHA256 `ab55dd632725f0c0f80cea3398f89cdf1bfb26e7c5bcdf9914f9f441477bb0fa`。
  复审确认的行为性缓存裁决：队列帧几何恒源空间后原特定失败路径消除，不必一律加
  尺寸签名；行为性缓存测试、消费前预约反例、共享 OSD 隔离、GPU/设备/画质/性能、
  legacy vo=gpu 均 OPEN。负坐标与反向窄 crop 按经典语义保留，不声称钳制。
- **gpu-next 消费者接入重做（2026-11-08，critical 复审 2×P0 后重构，已被第三轮修正覆盖）**：
  首版（下条）把物理 crop 放在 draw/截图时计算；独立 critical 复审核实两项
  P0：`pl_queue_update` 只 map 不 acquire，libplacebo renderer 在**局部
  pl_frame 副本**上惰性 acquire（`renderer.c` `pass_init`/混合路径），
  fresh 帧首绘先按源空间算好 crop/字幕、之后才拿到 small 纹理（越界采样）；
  队列帧 texture 恒为空使 REJECT(34) 物理分支不可达，第二次 draw 起合法
  small lease 反被拒。重构架构：**队列帧恒为经典源空间几何**——draw 循环、
  截图、REJECT(34) 全部回退经典形式；`hwdec_acquire`（renderer 局部副本、
  纹理绑定后）对已验证缩放 lease 调 `hwdec_lease_rescale_frame`，把该副本的
  crop 与视频字幕 overlay parts 换算到物理空间：double 精度、全帧边吸附、
  非空防塌缩（合法窄 crop 舍入为空时钳到 1px，P1-2）、旋转/vflip 不缩放；
  overlay 每次换新副本（`talloc` 子上下文挂 `frame_priv.rescale_ctx`，
  `hwdec_release` 释放），共享字幕状态不改，分配失败丢弃当次字幕并报错；
  acquire 开头清 lease 标记（P2-1）；几何校验新增尺寸为正、仅缩不放大
  （P2-2 部分）。渲染时序与经典路径一致（acquire 仍只发生在 renderer 采样
  时），不改变帧消费时刻；多帧混合按各自 acquire 独立换算；测试替身悬空
  指针改为调用内复制（P1-3）。P1-1（preserve_mixing_cache 按签名复用旧渲染）
  在队列帧几何不再中途变化后按构造缓解，但未做行为性缓存测试，保持 OPEN。
  测试：`test_lg_p84_hwdec_acquire` 提取三个真实函数扩至 17 场景（含 rescale
  crop、overlay 副本、共享不动、失败路径不残留、释放闭合）；契约测试改为
  断言 opt-in/顺序/经典回退并新增 rescale 提取 8 项；`screenshot_osd` 回退
  factor-1 场景。既定 16 文件回归 **109 项通过**（runner `python3 -E -s -B`），
  三仓 tracked diff-check 通过，日志外置
  `lg-p84-target-lease-20261105-host-regression-v16-consumer-rework-20261108/`，
  `SHA256SUMS` 自身 SHA256
  `37bfd058142521398d90b0a17feab31e6a46fcb6a6596ed0c5d6d3b7c0b339b8`；
  三文件 NDK 27.2 `-fsyntax-only` 干净。**仍属静态与替身验证：无 GPU、无
  APK、无设备、无画质或性能验收；构建保持 blocked；消费前预约反例未修；
  定向 critical 复审进行中**。首版 v15 回归（105 项）与复审结论保留于
  v15 归档。
- **gpu-next 消费者首版（2026-11-08，已被同日重构取代）**：draw/截图路径直接
  换算物理 crop、REJECT(34) 查物理纹理的方案；critical 复审（agent
  `48108d3b`，只读）裁定 P0-1/P0-2 接入阻断、P1-1/P1-2/P1-3 与 P2-1/P2-2，
  均已在重构中处理或明确记录为 OPEN。v15 回归 105 项通过，日志
  `lg-p84-target-lease-20261105-host-regression-v15-consumer-20261108/`
  （`SHA256SUMS` SHA256
  `423ab3141cd303a61729be9da4350e247a475ff3b9b2696a0b96d9e7e24c2f73`）。
  另：`perf2-mpv` 的 `player/screenshot.c`（窗口截图先取 window_res）与
  `video/sws_utils.c`（sws_scale 负值传播）经核对为 11-05/06 会话已记录工作
  （截图 OSD 所有权、底层缩放错误传播），非未知来源；本轮改动与其共存，同一
  工作树，未触碰其内容。
- **消费前预约修前反例（2026-11-06，真实 mapper 控制流＋host 替身）**：事先
  为空闲 slot 放一张可复用 full 纹理，注入 target 创建失败。期望直接回 full 的
  临时测试在 `map_frame` 断言失败；观察版使用相同真实控制流确认旧纹理被释放、
  release/latch 各一次、无 draw、加入 consumed 后同帧再请求 full 被拒绝。相同
  全局创建故障下直接走 full 可复用原纹理并正常消费。替身只证明限定控制流，不是
  实际设备 OOM，也不能证明目标 draw 失败后回源。10 件编译/运行/源码身份材料校验
  外置到 `lg-p84-target-lease-20261105-reserve-before-counterexample-20261106/`，
  清单 SHA256 `848b5778e94d7816b896839c99f05dead25fa3f19a157579e343bfe9612f22a6`。
  候选预约状态机独立设计复核进行中，生产 mapper 本轮尚未修改。
- **M2 计时接线只读核查（2026-11-06）**：MKS mapper/final 与 libplacebo 在不同
  创建时点读取属性，并非真正 context owner；属性在 LP 创建后、mapper 首次计时前
  改变时双读取者是条件式风险，未设备复现。所核播放器与依赖源码中 MKS 2 处、LP
  3 处 disjoint 读取；legacy RA timer 另争用 elapsed target。LP 的 NULL timer
  回落内部 timer、结果是滚动历史，不能按当前 callback 帧认领。建议先对现有真实
  timer 函数及共享 GL/EGL 替身建只读观察切片，再研究由 context 持有的 ticket/
  generation owner 与 LP client adapter；未接入。统一 owner 仍不自动覆盖 clear、
  blit、upload、fallback、source/cache/output 身份或设备扰动，M2 仍未验收。

- **PQ 上传身份与内容 witness 咨询（2026-11-06，只读）**：现有 canary 不访问
  source/LUT；source 实际是灰阶 RGBA16F，LUT 是 R16F，host 上传替身不保存 payload。
  可分开研究 API 对象/unit/uniform/FBO 身份、逐 texel 内容运输以及真实 PQ/LINEAR
  数学，前两项不能推出第三项。候选保留实际上传 half payload，使用独立整数
  half→binary32 展开，并探索 `texelFetch`→整数输出/读回全表逐分量对比；输入附着
  不得同时被 clear/draw，必须排除采样反馈，source 需条带全覆盖、四 LUT 全覆盖和
  反陈旧两相位/彩色通道校准。独立 witness shader 不证明计时 shader 内部执行。
  本轮未找到可核验的 GLES/ESSL 规范正文，整数附件/读回格式、half subnormal、±0、
  特殊值和完整传输语义均待核实；逐位相等只可作为本探针强准入候选，失败不自动
  说明驱动违反规范。校准/上传/读回须在 query 外且状态恢复后重新 warmup，仍会
  扰动热态；无 GPU pow/LINEAR 误差预算，未实施/设备验证，`unverified`/失败不变。

- **legacy 消费者与消费前资源预约咨询（2026-11-06，只读）**：`vo=gpu` 相同
  frame ID 直接沿用当前 mapping，resize/选项重建会清 renderer 缓存或中间资源但不
  清当前映射；暂停 small 后切换尺寸敏感 shader/scaler 仍可能读取 small。renderer
  的 output_tex/插值 surface 是自有缓存而非 lease；预取后的 cache 失效可能触及
  consumed 无 lease，此条件式风险也可能出现在 full 基线。可研究将逐映射 geometry
  绑定 video_image，并使用现有 prescale offset 组合局部 crop；视频空间字幕、共享
  OSD/截图、实际处理次序和失败语义仍未闭合。`take_slot` 目前在 codec release/latch
  后且替换尺寸时先销毁旧纹理再申请；如可复用 full 被毁而 small 申请失败，不能保证
  当前帧回源。消费前对候选 small 单独申请、失败保留原 slot 再走 full 是候选，不
  保证 full 一定成功，commit 时点、GL 状态/显存峰值、release/latch/draw/fence
  失败及旧退休契约正在独立设计复核，尚未实施。源码位置与边界见 M0 阻断说明
  §2.5.1；两 VO 继续不 opt-in。

- **复审落档与 OOM 测试补强（2026-11-06）**：固定 probe `f9091b9a…`、测试
  `97c3c33e…` 的独立 critical 最终未见样本 OOM 分支生产阻断；正常和六次失败的
  CPU/事件账本通过。33 版本 198 运行，25 个故障变异 21 检出/4 存活：zero ID、
  detach 后删除 query、terminate 后 detach、错误 display 均 6/6 HIT 后被旧测试
  放行；7 个合法对照仅 RING=8 被硬编码 16 误拒。另发现固定 allocation 序号可能
  被额外合法分配偏移；没有声称 CPU free 顺序或 free(NULL) 必须固定。
  207 件证据逐项校验外置到 `~/Documents/media-kit-validation-archive/artifacts/`
  `lg-p84-target-lease-20261105-pq-timing-oom-review-20261106/`，清单 SHA256
  `29ae57c4787c84c1c96df85f91de76078f9d5629bd8826530f50a5a49f5da850`；
  原 reviewer 嵌套引号 SyntaxError 在编译前，已留证并排除。计数与 EGL 调用顺序是
  本分支的限定约定，不能泛化为 EGL 所有合法资源释放实现或真实设备已清理。
  现测试在临时 probe 副本的样本分配 site 按 `v` 注入，并检查每个 sample HIT，
  host doubles 跟踪真实 query 集合、current context 和 display；不要求单次 delete、
  固定 query 总数或 samples free 顺序。本地 4 故障版本均 6/6 实际 HIT 且提交
  unittest 运行断言拒绝；baseline、RING=8、逆序 free、prefix、跳过 NULL、CPU free
  位于 EGL 后、分批逆序 query delete、额外 malloc/free、集中检查共九类对照通过。
  261 件本地材料校验外置到 `lg-p84-target-lease-20261105-pq-timing-oom-ledger-local-20261106/`，
  清单 SHA256 `1c0a90a3bef93e7220f6d4c602e46dba465af2f64dd9e0f4038d2d46df9ed3b3`。
  新测试 SHA256 `2ed355a02fc5d3c9dee58ab7c4504ebf3a03ef701af64ec3b6c459c9d5e4c401`，
  host C `c0931829070059777ca8467c91cb644446da62fa1ff6a83f584955e5f7e5c00a`，
  header `00dcb0304f2bdbce5994ae5c0af2f58aa32eae2cfe6f79d05604a77fba5e15c8`；
  生产 probe 未变。4 项受影响定向测试通过；完整 host 回归 **16 文件 101 项**
  通过，三实验仓 tracked diff-check 通过（不覆盖 untracked），四个 PQ 输入运行
  前后 SHA 匹配。20 件日志逐项校验外置到
  `lg-p84-target-lease-20261105-host-regression-v15-20261106/`，清单 SHA256
  `1fc696e6bd682c86dc13c6870dcda1ef91412c0c03f466a745d3c9b16364af58`；
  新快照独立复审最终确认四项旧漏检均 6/6 HIT 后被实际测试拒绝，指定合法对照
  通过；倒序分配的 index 3/4/5 被样本次数断言误拒，后续断言未执行，资源正常来自
  独立 trace，不是这些后续断言已通过。无 current 生成 query 再重绑删除、以及错误
  display 创建 context 两类变异均 6/6 HIT 后仍存活；它们是测试保障限制，不是已证
  生产缺陷。26 次成功编译、139 次运行、0 超时，33 件证据逐项校验外置到
  `lg-p84-target-lease-20261105-pq-timing-oom-ledger-review-20261106/`，清单
  SHA256 `ed35f39518ceb82c728b7adc3b5ea1f2c2788a83c232286652828d901b0fe355`。
  现修正倒序断言并补充 context 创建/display 关联和 query 生成时 current 状态，
  4 项受影响定向测试通过。定向重放 19 版本：baseline/倒序 samples/RING=8 等
  合法对照通过；前述故障拒绝，缺 current query 的六个 OOM 位置均 HIT；错误
  display 创建 context 在 OOM 前已被拒绝，操作命中但不是样本 OOM 命中。401 件
  材料逐项校验外置到 `lg-p84-target-lease-20261105-pq-timing-oom-ledger-v2-local-20261106/`，
  清单 SHA256 `faf18f63f28b7a425d1f52a35dc273c9bf1426f265acc97d4bb6b36df6620e6c`。
  最新测试 SHA `cb5481e445f4e07fd01d317810eeda250a9c6126f5a30ccba503983941fe3cc1`，
  host C `b8351fc542df83233c7be74a344ffec12ca131b315df3e34cce5c294fe49163d`，
  probe/header 未变；完整 host 回归 **16 文件 101 项**和三仓 tracked diff-check
  通过，四输入前后 SHA 匹配。20 件日志外置到
  `lg-p84-target-lease-20261105-host-regression-v16-20261106/`，清单 SHA256
  `eed7d1d8d6ba7eb3f5b019bd1b95dc93e9bf2a2469d37134e88a29308b2908c7`。
  新快照独立复审进行中，不证明真实 EGL/GPU 清理。
- **256 点独立数学审计最终结果（2026-11-06）**：固定 fixture 的 90/150 位每种
  分别 7682 次 neg、7169 次 sub 经 Fraction 逐次检查未失包围；256 个 source half
  经精确分数验证，8 个 PQ 点经独立整数幂/根验证匹配；未发现固定结果位值错误。
  通用 Decimal neg 可收缩区间，half 近溢出及 `power(0,0)` 也有域外反例；
  `observed_pow` 的 `ulp_error_upper` 除法向内舍入，90 位 63 条、150 位 87 条，
  不构成实际 pow 超界的证明，却阻断将这些数字称为严格上界。非零正规真值的
  ULP/binade 定义、`pow(0,正数)=0`、binary64 RN 及每次 pow≤1 ULP 等仍为条件，
  不是 Android/GPU 平台保证。全部 256 PQ/传播区间未独立证明，fixture 尚未接入
  测试；灰阶不覆盖彩色/上传。21 件证据逐项校验外置到
  `lg-p84-target-lease-20261105-pq-cpu256-oracle-review-20261106/`，清单 SHA256
  `4d3f5d1d5bc74ef647bdb41bbf9579565e74f581396a70f9758060546806b50e`。
- **shaderc 来源只读复核（2026-11-06）**：实际输入是 NDK 内 shaderc、glslang、
  SPIRV-Tools、SPIRV-Headers 源码树，四者无已核实 Git 身份；产物目录不是独立源码
  checkout。正确双层 local 仍含旧对象，不能由修正路径或 archive hash 推出全量
  重编译。SPIRV-Tools 两处生成规则的变量大小写及 grammar prerequisite 缺项只支持
  条件式增量风险推断，尚未执行构建反例或证明旧文件过期。详细路径、行号与边界见
  M0 阻断说明 §5.2.1；debug 源码、工具及目标运行库、空 prefix、写入隔离/空间均
  OPEN，无构建或设备操作。最近查询剩余空间约 2.9 GiB，不是构建峰值预算。

- **256 点灰阶独立 CPU oracle 数学咨询（2026-11-06，只读）**：独立 Decimal
  ln/exp 有向区间，以固定 LCG、每像素先抽样再覆盖前四锚点、源 double→float→half、
  正规 RNE/小值 RTZ、ST.2084 与 tail 建模；90/150 位生成相同 256 行 fixture。
  在 binary64 基本运算 RN、每次 `pow` 误差≤1 binary64 ULP、无 fast-math 等
  **条件**下，脚本报告计算区间逐点落在唯一 half；独立审计中途发现通用区间
  `__neg__` 可能受 Decimal 上下文舍入而收缩；固定数据的最终审计见本节首条之下，
  该结果目前不是严格区间证明。`pow` 限制也不是已证的本机 C 或 Android 平台
  保证，不是 GPU 容差。数学模型预测略去源 half 时 13 个 Y 差异、
  LCG 错位时 252 个非锚点变化，尚未对真实 C main 执行这些变异；略去中间 PQ half
  在此灰阶样本未见最终位型变化。Cb/Cr 都是 0.5，不能证明非灰色 CSC/RGB、
  中间量化必要性、真实上传、GPU 或画质。研究时 probe 从旧 `90ab…` 改到
  `f909…`，specialist 以逆除新增 sample OOM 段的内存比较确认数学相关代码未变，
  未写项目。12 件冻结材料逐项校验外置到
  `~/Documents/media-kit-validation-archive/artifacts/`
  `lg-p84-target-lease-20261105-pq-cpu256-oracle-research-20261106/`，清单
  SHA256 `67ca5f52ebf16a77cac495d2d3ce4b463b4127345c76964f7d1f55253336a8e5`；
  生成器的后续限定独立审计见本节顶部，fixture 尚未接入回归，平台误差边界仍 OPEN。
- **PQ 计时样本 OOM 试修（2026-11-06，独立复审中）**：真实 main 搭配 fake GL
  与查询替身，分别令六个 `samples[v]` 分配返回 NULL；原代码未立即检查而继续
  timing，六例各自命中后分别产生 31/181/331/481/631/781 个 timing draw、
  1/121/241/361/481/601 次 query begin，最终误报 `reason=timer_begin`、退出 2；
  13 次成功分配仅释放 8 次，query 未删除、EGL 未 detach/terminate。此为 host
  控制流观察，不证明真实 GPU OOM。现将样本数组清零初始化并逐次检查，失败立刻
  报 OOM，释放已分配样本、删除 query、detach/terminate 并返回 2。新增真实 main
  定向测试六个子场景修前均因释放账本不符而失败，修后通过；其余 GLQ 早退及真实
  EGL 完整清理仍未证。修前 21 件材料逐项校验外置到
  `~/Documents/media-kit-validation-archive/artifacts/`
  `lg-p84-target-lease-20261105-pq-timing-oom-before-20261106/`，清单 SHA256
  `4446bf8247d06bab44a5fff2d90560415d140daae077544b1ad32dc7c82ed227`。
  新 probe SHA256 `f9091b9a90edb5d18476958a826ca53c4bef6f555f37952b630f71ded4be5a0a`，
  新测试 `97c3c33e87b7dd69184b0a5631d63ba361a8111e8730f6f94f7b934dfdb053b2`；
  固定快照最终独立 critical 复审见本节顶部。完整回归首轮错误地对项目测试使用 Python
  `-I`，屏蔽脚本目录，mix-cache、screenshot-overlay、sws-error 三文件在 import
  本地 helper 时 `ModuleNotFoundError`，其余 13 文件（含 PQ20 项）通过；这不是
  产品测试失败也不是完整回归通过。20 件日志外置到
  `lg-p84-target-lease-20261105-host-regression-v14-runner-error-20261106/`，
  清单 SHA256 `a3f60537592bed5c64f2bec5b9aabdceb586eabcf18c7b8c9f9c209bd7b36d44`。
  改用 `python3 -E -s -B` 保留可信项目脚本目录后重跑，**16 文件 101 项通过**，
  三实验仓 tracked diff-check 通过（不覆盖 untracked），四个 PQ 输入运行前后
  hash 匹配。20 件日志逐项校验外置到
  `lg-p84-target-lease-20261105-host-regression-v14-20261106/`，清单 SHA256
  `8f60effb2613ded979eea099ef1c93c178c854a86e3feaa4de320ba8eb9a80b7`。
  独立 critical 中途报告：固定源码未见生产阻断，但 query 删除只计数不校验 ID，
  EGL 只计次数不验证顺序/handle；错误 ID、detach 后删 query、terminate 后 detach、
  错误 display 四类变异各 6/6 实际 HIT 仍被测试放行。RING=8 的合法 query 数量
  变化被固定 16 误拒；其他合法 cleanup 位置/NULL free 对照通过。以上是中途测试
  保障结果，最终独立报告和后续补测尚未完成。不放宽对下载或解压的不可信材料
  使用 `-I` 的环境要求。最终 `unverified` 强制失败不变，未运行 GPU/APK/设备轮。
- **截图共享 OSD/字幕再调查（2026-11-06，只读）**：`osd_render` 修改共享几何、
  版本并可能广播 resize，`sub_get_bitmaps` 更新 PTS 且可切换/销毁 decoder；
  局部 atlas 与软件窗口快照不隔离这些状态。本地 libass 的独立 renderer 仍写
  共享 track/event 碰撞状态，锁不能回滚；`sub_bitmaps_copy` 的真实 refcount
  不代表长期 pin 没有后续 COW 失败域，已裁剪 ASS 结果也不能普遍跨尺寸等价。
  可分别研究非字幕独立 view、现存 `sd_lavc` 事件的布局前快照和真实 libass
  track；每项仍有限定、额外资源/失败域，非完整解法。真实/替身函数边界、
  D→S→D 与 segment 事件脚本、合法/故障对照及只读源身份记录在
  `docs/validation/lg-p84-target-lease-20261105/m0-osd-subtitle-observation-20261106.md`；
  观察包均未构建或运行，源 hash 不证明依赖准入/设备链接。原 specialist 对记录
  的限定及 15 个 hash 只读核对无必须更正项；已补充固定时间 D→S→D 不覆盖自然
  播放推进，segment 命中须按 direction/delay/speed 换算到字幕时间域。两 VO 保持
  不 opt-in，真实截图/字幕和 M0 仍 OPEN。
- **真实 CPU 四锚点 host 参考补测（2026-11-06，独立复审中）**：独立只读数学校验
  使用 Decimal 100/160 位和 Fraction 数值网格，得到依序 Y half 位型
  `0x000c/0x38a5/0x3a04/0x3c00`，Cb/Cr 均 `0x3800`；与旧证据相符但未用旧输出
  生成独立预计。CPU 先量化源，再 double PQ 与中间 half、double 色转及 tail half；
  量化后的亮锚为 4.92578125/49.25 而非名义 1000/10000 nit。当前四锚点碰巧不足以
  检出删除源量化、中间量化或 small-RTZ→RNE；灰阶也不能证明 RGB 互换/完整矩阵。
  新测试 `test_cpu_reference_anchors_use_analytic_readback` 不改真实 CPU reference，
  只替换 fake GL 读回；四锚点 × 三通道 × exact/±1/±2 共 60 场景，独立 half 编码
  用 Python `struct` 解码，固定一个背景 −1 哨兵校验 max_abs=1.5，其他四次 LUT
  读回与 analytic 不同；定向通过。测试 SHA256
  `40e5d5c7a33f7c2b9216e4d82bcf65c840bc3c0188becc8741def809c75178e1`，生产与双
  替身文件未变。完整 host 回归 **16 文件 100 项通过**，三个实验仓 tracked
  `git diff --check` 通过（不覆盖 untracked）；生产 probe、测试及 host GL C/header
  四个输入 SHA 与运行前一致。20 件日志逐项复制并以 SHA256 校验外置到
  `~/Documents/media-kit-validation-archive/artifacts/`
  `lg-p84-target-lease-20261105-host-regression-v13-20261106/`，清单 SHA256
  `e6d57b0b119566117736e11ef2e567f7c275fe443e4c6639e4d911a129354fd3`。固定
  快照独立 critical 复审完成：限定范围未确认新增 P2；原整体/bit/ULP 错读
  `acc`、`max_abs` 错源和恒零五项均实际 HIT 后由运行断言检出。14 个源码故障
  与 3 个夹具故障变异均命中检出；不同 LUT、alpha 和 sentinel 的合法对照通过。
  审查核对生成的 anchor probe 除 include 与 16×16 尺寸外保留真实 CPU 整段，
  60 个独立进程在 analytic 注入锚点/sentinel、后四次 LUT 为不同于 analytic
  的值；独立 Decimal/ST.2084 与 half oracle 匹配四锚点。有效 287 编译、14135
  次原生和 31 次辅助运行、0 超时；reviewer 脚本曾有一次转义编译失败及一次
  错换目标，证据保留、排除有效统计，不作产品误拒或变异检出。2494 件材料及
  清单逐项校验外置到 `~/Documents/media-kit-validation-archive/artifacts/`
  `lg-p84-target-lease-20261105-pq-half-anchors-review-20261106/`，清单 SHA256
  `eb667c8eaf49c6f3d232f44b47fe9826bb32fc34e6005c882bae70e9fd844492`。
  anchor 报告仍用 substring 断言，sentinel 会掩盖更小的局部 max 差异；这是
  有限 CPU 真实路径与合成读回，不是 GPU 四锚点、过滤、彩色或画质验收。
- **ac3ca 全位置独立复审完成（2026-11-06）**：旧首像素/通道漏计两项变异分别有
  765/512 个运行子场景检出，限定关闭；778 个独立进程覆盖 768 位置加十种边界，
  但不是 768×所有边界的笛卡尔积。新增 analytic/LUT 身份和 max_abs 未断言两项
  测试 P2：整体/bit/距离错用 acc、max_abs 错源及恒零五变异均 HIT 后整套 PQ18
  存活；25 变异 20 检出/5 存活，585 编译、26325 原生运行、0 超时，16 文件 99 项
  通过。合法等价 helper/谓词及污染环境对照通过。56160 件材料逐项校验外置到
  `~/Documents/media-kit-validation-archive/artifacts/`
  `lg-p84-target-lease-20261105-pq-half-grid-review-20261106/`，清单 SHA256
  `9c56621927c52d6d545482a27ff3f827149b71fb3f264e100af209cd93beccaf`。后续
  17da 的本地补测见下条，新版 40e5 的独立复审不能使用旧快照结论代替。
- **PQ CPU 读回来源补测（2026-11-06，历史中间快照）**：`ac3ca511…` 的独立复审
  已核实 778 个独立进程及 768 个位置各自选中，其余参考值精确，负零位型正确；但
  五次 fake GL 读回相同，真实 CPU 统计区块将 analytic `base` 全换为最后 LUT `acc`
  的变异 783 次 HIT 后整套 PQ 18 项仍通过，为新测试 P2 候选，非已证生产缺陷。
  reviewer 在临时对照中区分首个 analytic 与后续 LUT 的选中分量，正确报告 1/1，
  整体错读 `acc` 报 1/0；正进一步核验单独比较、距离和 max_abs 的错读。现仅修改
  夹具：analytic 保持原合成参考/读回，其余四次 LUT 读回改为不同值；中间测试
  `00b5f6ad5cb4eae502b53813290f19739d4666a34896426c9d301190bf03f883` 的 778 场景
  定向基线通过，整体错源、bit 比较错源、距离错源各由运行断言检出，但单独的
  `max_abs` 错源仍存活。独立复审亦确认这四项在 ac3ca 固定快照均 HIT 后整套存活。
  因而继续在测试里解析 CPU 报告并独立以输入 hex 数值差核对 `max_abs`，容差
  `5.1e-10` 仅覆盖打印到九位小数的四舍五入；最新测试 SHA256
  `17da921cab8784b675c219cc5e50dd993ddcb6c55d8dcb5dcbd253dd1f4e7402`。定向基线
  通过；整体、bit 比较、距离、max_abs 错源四项在本地临时副本分别有 778/778/3/778
  个子断言失败（这些是失败子场景数，不是不同变异数），证据暂存
  `/var/folders/96/wxgz1n_d70g8rfl09q80jych0000gp/T/pq-half-readback-v2-mutation-x23j0yxz/`。
  先前 ac3ca 固定快照的独立复审还确认 max_abs 恒零变异命中后存活；其最终结果见
  顶部，不能扩展到新版。当时完整 host 回归 **16 文件 99 项**及三个实验仓
  tracked diff-check 通过，20 件日志逐项校验外置到
  `~/Documents/media-kit-validation-archive/artifacts/`
  `lg-p84-target-lease-20261105-host-regression-v12-20261106/`，清单 SHA256
  `cb9bbb061e24f897cf58eeabd91f638ab130574d01b7c2ab6a7ba603edf71221`；上述 9 件
  定向证据也已外置至 `lg-p84-target-lease-20261105-pq-half-readback-targeted-20261106/`，
  清单 SHA256 `60eff6608ffc4c92232b72ec7968f956ff9448b1098a9b9ff7c3cff9dc0095eb`。
  本地另对 `cpu_max` 恒零变异做定向对照：基线通过，变异在 775 个运行子场景失败，
  6 件材料外置到 `lg-p84-target-lease-20261105-pq-half-maxzero-targeted-20261106/`，
  清单 SHA256 `7d0b8ef663ae7a6162f2b2564006876c7e37115546f4f3dc5eecc5b79b3c909c`。
  新版独立复审尚待进行；仍为 host 合成统计，不是 GPU 或数值精度容差。
- **PQ CPU 统计空间覆盖补测（2026-11-06，历史中间快照）**：测试 `e50f5a0b…` 的
  16 文件 99 项 host 回归和三实验仓 tracked diff-check 已通过，20 件日志逐项校验
  外置到 `~/Documents/media-kit-validation-archive/artifacts/`
  `lg-p84-target-lease-20261105-host-regression-v10-20261106/`，清单 SHA256
  `070c73c983a3b5ae697ca6b97fc438204b4dccd618826670314c82758ac886d6`。
  e50f 的独立复审中间报告确认原 `1≤ulp≤2` 抵消变异被五个场景检出，但发现所有
  正计数都集中在 `(p=0,c=0)`：将真实 `within1ulp` 门另限 `c==0` 或 `p==0`
  的两项变异均 HIT 后 PQ 18 项存活；合法地把单个差异搬到 `(0,1)/(0,2)/(1,0)/
  (255,2)` 时，正确实现为 1/1、错误门在其排除位置为 1/0。整段 mismatch
  限首像素会被既有测试检出，不能泛称整个 CPU 统计均无空间覆盖。
  e50f 独立复审最终 18 项变异 16 检出/2 存活、453 次编译、3072 次原生运行、
  0 超时；9099 件材料及清单经逐项复制校验后外置到
  `~/Documents/media-kit-validation-archive/artifacts/`
  `lg-p84-target-lease-20261105-pq-half-split-review-20261106/`，清单 SHA256
  `5fb81a40a743b2a9f922e7383fe09a3b5eeb8ad310e9fc444c6f0e33c705aa87`。
  现只修改合成测试，允许指定像素/分量，对每个单独进程保留一个差异并遍历
  256×3 个参考位置；测试 SHA256 `ac3ca511a83b78f63bf380b3a0ffe0eb0d0c525d0701cd6464c2b8b4e188c064`。
  定向通过；在本地临时副本对 `p==0`、`c==0`、`1≤ulp≤2` 分别注入错误，三个
  错误有 765/512/5 个运行子断言失败，8 件材料外置到
  `~/Documents/media-kit-validation-archive/artifacts/`
  `lg-p84-target-lease-20261105-pq-half-position-targeted-20261106/`，清单 SHA256
  `5924ce6426406fa90e0e5528fbbd26d2f61007e783861950dda130d73aea613c`。
  最新 16 文件 **99 项**及三实验仓 tracked diff-check 通过，20 件日志外置到
  `~/Documents/media-kit-validation-archive/artifacts/`
  `lg-p84-target-lease-20261105-host-regression-v11-20261106/`，清单 SHA256
  `81bfb40cb24716ae298a39139dea37713f58dfcf3e26399a019747a681865a84`。
  ac3ca 的独立复审已冻结输入并运行，不能提前宣称 P2 关闭。以上均是假 GL/合成
  参考，不是 GPU 证据。
- **真实 renderer 观察包的来源准入（2026-11-06，只读）**：核心源码及预处理器、
  Jinja/MarkupSafe、fast_float 入口文件存在，但五个第三方 checkout 只证与固定
  gitlink 一致，远端最新未证。源树含旧构建与 `.pyc`，Meson 禁后端仍可能发现
  execinfo/atomic/Vulkan 等，Python、compiler cache、系统工具链/runtime 的输入
  边界未闭合；`meson setup` 本身会执行探测，不能当只读预检。待按源码 allowlist、
  传递依赖、路径别名和运行期读写/禁网逐项建立准入；未配置或构建。详见 M0 阻断
  说明 §5.4；不解除项目 debug 源码硬约束，M0/APK/设备验收仍 blocked。
- **PQ 合成参考夹具的聚合抵消修订（2026-11-06，历史中间快照）**：独立 critical 对
  测试 `25cb6a24…` 发现 `1≤ulp≤2` 错误谓词实际 HIT 后仍报 6/5：±0 被漏计、
  跨零两步被误计刚好抵消；reviewer 将每项隔离后观察两类各自失败，故为测试 P2，
  不是编译错误。现只改测试：每次执行真实 main 时，通过临时替身分别设置一个
  参考和单个假读回分量，其余分量均 exact；独立断言 exact、双向 ±0、跨零一步和
  两步、正负同号一步/两步，仍保留真实 `checked_half` 和统计循环。新版测试 SHA256
  `e50f5a0b68b9fd4e56256baea374ed7589588739eac7ad2b765bdd163692bab0`，生产与
  host GL 未变。定向单测通过；在独立临时副本将谓词改为 `1≤ulp≤2`，基线通过，
  错误版由双向零、跨零两步及正负两步五个分场景运行断言检出，日志位于
  `/var/folders/96/wxgz1n_d70g8rfl09q80jych0000gp/T/pq-half-split-mutation-pzsnse1p/`。
  此为合成统计夹具，不代表真实参考域或 GPU；全量回归和新版独立复审进行中。
  25cb 固定快照的独立复审最终确认原四类 CPU-only 旧公式、禁计数、严格边界与
  exact 错误均 HIT 后检出；聚合抵消仍存活，合计 15 变异 14 检出/1 存活。合法
  等价 helper 和谓词、首项 OOM 提前退出通过；362 次编译、2321 次原生运行、0 超时，
  无新增生产 P0/P1。7192 文件及清单逐项校验外置到
  `~/Documents/media-kit-validation-archive/artifacts/`
  `lg-p84-target-lease-20261105-pq-half-followup-review-20261106/`，清单 SHA256
  `ad9affade4a672fcb4f9bd215fd10863e27053ed0a5889913e3a1c5d3d6b95c2`；不能将该
  复审或 99 项结果自动扩展到新 `e50f…` 测试快照。
- **PQ half 旧快照独立复审与新回归（2026-11-06）**：生产 probe SHA256
  `90ab1d164f9b0e3e5f49ffee8b78ca8978f0e1cd5c269ddae7a26c9b795f5f3b`、旧测试
  `d0dbebc2b250060c86d8fb0c0b3552ebcf403cc3763d9118daf9f472ea4f3377` 的独立
  critical 完成：无新增生产 P0/P1；确认旧 CPU fixture 的 768 次距离均大于 1，
  CPU-only 旧公式、禁用 `within1ulp`、`≤1` 改 `<1`、将 exact 计入统计四项变异
  实际 HIT 后仍存活，为测试 P2，不能声明两个调用位置均有独立行为保障。审查枚举
  63488 个有限编码、63486 对不同数值的相邻项与 100 万随机性质样本，UBSan 无异常；
  32 位 int 下最大距离 63486，调用链已检查有限性。旧测试16文件98项通过，334 次
  编译、2167 次原生运行、0 超时；两次 runner 环境错误及两次生成脚本语法错误如实
  保留，未计为有效检出。独立的原 CPU 域 exact/±1/+2 与合成 tail 两种 fixture
  是临时复审证据，不是旧项目持续回归。6798 文件及清单逐项复制和校验后外置到
  `~/Documents/media-kit-validation-archive/artifacts/`
  `lg-p84-target-lease-20261105-pq-half-review-20261106/`，清单 SHA256
  `a6006af8f0c4d105440e6ce95612efab1ac760697b8e738770cb965eeacc567e`。
  其后项目新增合成 tail fixture 的测试 SHA256 `25cb6a24c680a83c5ba845c58c05436676169c7e6313c464be2ac07dacafcef1`；
  16 文件 **99 项通过**，三个实验仓 tracked diff-check 通过。20 个分文件日志、
  diff-check 及摘要逐项复制校验后外置到
  `~/Documents/media-kit-validation-archive/artifacts/`
  `lg-p84-target-lease-20261105-host-regression-v9-20261106/`，清单 SHA256
  `57c752bf8013aad3d8b384d17838e58b6582b7142c6d3822d8bc756085583b70`。
  新快照已冻结并启动独立定向复审；新 fixture 是合成统计样本，不代表真实 PQ/CSC
  输出或 GPU。旧源码的 NDK syntax-only 和 CPU 自测见下条，不能替代设备验收。
- **真实混帧观察包再咨询（2026-11-06，只读）**：推荐独立完整源码快照 + 受控 dummy
  pass backend，以真实 renderer/dispatch 控制流和真实 acquire 失败为首包；仅记录
  参数与路由，不执行 GPU shader，也不证明像素。真实 pass 参数需深拷贝，动态变量
  更新需镜像；dummy 缺 clear/run/destroy，未知操作不得静默成功。首包拟限小尺寸、
  单平面 RGB、progressive、全目标覆盖和 `PL_CLEAR_SKIP`，不用 overlay/hook/compute。
  在真实函数旁追踪参与帧、归一化权重、cache、错误位和 fallback/nearest 出口；
  `info_callback` 单独不足。下一调用不 reset 时须观察持久 fallback；cache hit 可
  合法绕过 acquire。完整源码及依赖、工具链/runtime 准入、隔离输入输出和写入边界
  尚未闭合，不能以共享构建或旧 archive 填洞；尚未构建/实施。四帧 horizon、真实
  custom hook/PRNG 和 mapper 联合属于后续包。详见阻断说明 §2.6；M0 继续 blocked。
- **PQ half 数值步距试修（2026-11-06，历史中间快照）**：保持 `differing`/
  `exact_mismatch` 为 bit 差异，用有限编码 `rank = sign ? -magnitude : magnitude`
  计算半精度步距并合并 ±0；`accuracy.max_ulp` 和 CPU `within1ulp` 均使用该距离，
  没改 double→float→half、小值 RTZ、LUT 或最终 unverified。修前本机完整 main+假 GL
  五次 accuracy 注入 `-0/+0`、`±minsub` 和 `-maxfinite/+minsub`，四个 LUT 实际
  报 `max_ulp=32768`；修后为 `31744`，3 个 bit 差异保留。host 对全部有限 half 编码
  验证排序相邻、与零、正负镜像和边界；CPU-reference 路径另测，两个新增定向测试
  通过。fixture 最初把 CPU reference 的 exact mismatch 误预计为 515，实际为 768；
  修正预期后通过，未把失败伪称有效结果。NDK 27.2 API24 `-fsyntax-only` 和 host CPU
  self-test、16 文件全量 **98 项**及三个实验仓 tracked diff-check 通过；20 个
  日志/摘要逐项复制比对并按清单校验后外置到
  `~/Documents/media-kit-validation-archive/artifacts/`
  `lg-p84-target-lease-20261105-host-regression-v8-20261106/`，清单 SHA256
  `436dac47c43c3a906823ae1c550278f1a760a1fdfade7052d2325fb7e2987cf1`；独立 critical
  初审发现 CPU 参考调用点回退旧公式、禁用 `within1ulp` 和 `<1` 误替 `≤1` 三项
  变异均 HIT 后存活：旧主流程夹具 `within1ulp=0` 不能证明统计路径覆盖。现仅在临时
  生产副本的 `checked_half(want[c], &wh)` 输入注入有限值并调整假读回，保留真实
  half 转换及统计循环；`±0`、`±minsub`、正负相邻、相等与跨零两步使 bit mismatch=6、
  within1ulp=5，新增单项通过。其为合成统计夹具，不证明原 PQ/CSC 可达输出或 GPU。
  独立复审在原 CPU 参考中观察 768 项均非负、最小 half code=12；另仅修改假读回
  对原参考构造 exact/±1/+2 步，观察 `exact_mismatch=576 within1ulp=384`，原三项
  计数门漏检变异被该独立运行断言检出；此对照尚未纳入项目测试，原 CPU 输入域无法
  单靠其观察跨符号旧公式。初审生产公式未因测试漏检被证伪。probe SHA256
  `90ab1d164f9b0e3e5f49ffee8b78ca8978f0e1cd5c269ddae7a26c9b795f5f3b`，初审测试
  `d0dbebc2b250060c86d8fb0c0b3552ebcf403cc3763d9118daf9f472ea4f3377`；新测试
  `25cb6a24c680a83c5ba845c58c05436676169c7e6313c464be2ac07dacafcef1`，host GL
  C/header 仍为 `33e09bab…` / `84ea7f32…`。98 项全量对应初审测试；新夹具随后
  的 99 项回归及独立复审状态以顶部最新条目为准，不是 GPU 精度/四锚点验收。
- **PQ 锚点与数值距离再咨询（2026-11-06，历史只读核查）**：实际 source 四锚点上传 half 为
  `0/1/4.92578125/49.25`，不能直接用未量化名义输入；analytic 与四种 LUT 需各自
  模型，LUT 不应无条件与 analytic 逐位相等。当前 accuracy 的 CPU NaN poison 只能
  检出未写 CPU 分量，假 GL 的每次 RGB=0.5/A=1 常量读回仍可走到 CPU reference；
  没有每次 GPU clear 与独立数值门，有限旧帧或固定错误可假一致。可研究真实 FS 的
  双相位不等 RGB fixture、逐次 GPU 无效 clear、RGBA/alpha 检查、source/LUT 内容与
  绑定 witness；数学 PQ、上传 double→float→half、native small-RTZ、GLSL 和 FBO
  转换须分层，CPU 可枚举声明域内 half 输入的理想 LUT 插值但不能推出 GPU 全链上界。
  GPU pow/sqrt/纹理过滤误差和产品允许预算尚无定量依据，不能拍定 ±1 ULP 或反向
  用观测最大值充当通过阈值；四锚点、彩色、滤波、timer 和最终 GPU 验收均 OPEN。
  此外 `(int16_t)` 位型差不具跨符号单调性：常见二补实现下 `+0/-0` 报 32768
  （合并数值零应为 0），`±minsub` 报 32768（数值 rank 差应为 2），`-maxfinite`
  到 `+minsub` 报 1026（应为 31744）。同号有限值在常见实现上距离可用，现有正常
  灰阶输出主要非负，不能声称全部历史统计受影响；checked_half 可接受负值/负零。
  临时 host C 提取该距离表达式并用本机 clang 运行，实际输出依次为 `32768/32768/1026`，
  同号相邻 `0x3c00/0x3c01` 对照为 `1`；不是 Android/GPU 证据。当时建议对有限
  half 使用有符号数值 rank、保留 bit mismatch；其后试修与复审状态见顶部，最终失败
  门保持。
- **PQ 能力检查 OOM 试修（2026-11-06，限定独立复审完成）**：`has_ext()` 使用 `malloc`
  后未检查 NULL，真实函数提取及完整 main 假 GL 注入重现 SIGSEGV。完整 main 的
  GLES 3.2 前两次、GLES 3.0 前三次能力查询各分配失败共五个场景均崩溃；现检查
  `strlen+4` 溢出和 malloc 结果并返回不支持，五例均报告 `reason=caps`、退出 2，
  未进入计时；测试当时未直接观察 query 的生成/开始。NULL 扩展列表、精确 token
  与前后缀对照通过。定向两项通过，
  全量 16 文件 **96 项通过**，三实验仓 tracked diff-check、NDK 27.2 API24 clang
  `-fsyntax-only` 与 host CPU self-test 通过；复审及全量日志均已按证据约定外置。
  此次源码 SHA256
  `5566fbab63f93d1a326cb97b8cda0465e98ebaeef8244733ed2a748a373bfbc5`；初审测试
  `f67b82b8369b52a3564c9eaa002fd8e16abf91ae9cbba3aa425cad07f0bf52c2`、host GL
  C/header 为 `98c7f7d9…` / `84ea7f32…`。独立初审固定旧快照无新增生产 P0/P1/P2，
  13 项缺陷变异 10 项运行检出、3 项存活：query 生成/开始及溢出 guard；首个能力实际
  缺失后提前退出被测试误拒。模拟 `strlen` 极值可检出溢出 guard 删除，仅是算术模型，
  不能称真实可读字符串极值。12 项能力组合（6 正/6 负）符合预期；GLES 3.0 仅测
  host 能力路径，不能证明其可执行 `#version 310 es` shader。有效旧快照 76 次 clang、
  240 次 C 运行，0 超时；共享 host doubles 漂移后中断的混用轮单独保留、排除统计。
  现在 host GL 增加 query 生成和开始
  账本，测试只要求注入实际命中并检查已分配对象释放，不强制后续查询次数。新 host
  C SHA256 `33e09bab0be88f2fba2b9b0d2d53038ef8414cb4f354f06b28e59195e0e0e152`，
  测试 `0d050a13e93593c34533b4486fb327e69e9c3a6740c4ea4aa15d23c3b761746e`，
  定向 PQ 15 项及修订后的 16 文件全量 **96 项通过**，三实验仓 tracked diff-check
  再次通过。独立定向复审新快照：两项 query 变异在五个 OOM 场景均实际命中并由运行
  账本断言检出；真实首项 OOM 后提前退出、额外成对分配和 `free(NULL)` 对照通过。
  13 项变异中 12 项运行检出，删溢出 guard 仅普通路径命中后存活；独立 `strlen`
  极值 mock 对照可检出删除，但不能代表真实可读对象。12 项能力矩阵、PQ 15 项和
  独立全量 96 项通过，新快照有效 96 次 clang、377 次 C 运行、0 超时；无新增
  P0/P1/P2。独立旧/新复审有效合计 172 次 clang、617 次 C 运行，另有两轮中断
  夹具 28 编译/44 运行单独保留，不计入统计。独立审查的全量回归起初三文件因 `-I`
  启动路径缺少 `tool` 导入失败，修正临时 runner 后通过，原错误保留。3655 个证据
  文件及清单已逐项复制、比对及按清单校验，外置到
  `~/Documents/media-kit-validation-archive/artifacts/`
  `lg-p84-target-lease-20261105-pq-caps-review-20261106/`，清单 SHA256
  `1568d91680eeeb06b9312320b197373da9730f77e1108209b7d7910e5b823b30`。
  20 个全量日志和摘要经逐文件复制、比对与清单校验，
  外置到 `~/Documents/media-kit-validation-archive/artifacts/`
  `lg-p84-target-lease-20261105-host-regression-v7-20261106/`，清单 SHA256
  `a3eafdd7257c95a4ff51e966df7f42309320099553091684b7d6bfd09076500d`。
  能力检查失败不声明完整 EGL 清理，也不是 GPU、APK 或设备验收；最终
  `validation=unverified` 和失败 verdict 不变。
- **消费者与构建防误操作再咨询（2026-11-06，只读）**：`custom_mpv.c` 在后续
  纹理/dispatch 可能失败前已推进 hook frame/PRNG，因此不能假设重试成功等于无副作用；
  mix 出错可持久置错并 nearest 成功，而 preserve-cache 合法命中可不重取已退休 lease。
  建议先设计真实 mix 控制流观察器以记录权重、路由、错误位、acquire/release 与
  hook 次数，不是接线批准。另确认标准 native 构造先创建 output/日志，依赖 make
  写源码树，`MKS_SKIP_APK`/Flutter 参数拒绝不在最前；有限路径/环境拒绝门有现有
  默认兼容影响，不替代执行期隔离或源码闭包，尚未实施。详见 M0 阻断说明 §2.6/§5.3；
  未构建或操作设备，M0 和 APK 继续 blocked。
- **PQ 补测独立复审完成（2026-11-06，限定范围）**：固定测试 `7252aa6a…` 的复审
  确认旧四项变异均 HIT 并检出；发现环境 `LG_PQ_HOST_ACCURACY` 继承和精确要求
  half 溢出数必须进入 converter 两项测试 P2。清除继承 `LG_PQ_HOST_*` 并只约束必须
  在 float cast 前拒绝的 NaN/Inf/±DBL_MAX 后，最终测试 SHA256
  `016fbd5b29dede0f9e97db99320eaab70c547587d7d53eed6abe6718eede13c8`；生产 C 未变。
  定向独立复审 50 次 clang 成功、929 次运行、0 超时：两类合法对照通过，原四变异
  仍有 HIT 后由 Python 资源断言或 C converter 入口断言 SIGABRT 检出；无新增
  P0/P1/P2，首审指定缺口在此范围关闭。两轮材料 2385/2086 文件逐项校验外置到
  `~/Documents/media-kit-validation-archive/artifacts/lg-p84-target-lease-20261105-pq-numerics-followup-20261106/`，
  清单 SHA256 `0f09a2525015ce52ab0706ec5e53a4677aad95e20ffb17a02e68fddfc674f1d0`。
  资源替身不能观察未重定向的 calloc、新旧 allocation 复用后的 stale alias 等，也有
  32 次历史分配容量边界；当前生产只调用受跟踪 malloc，不据此声称未来实现均可检测。
  最新 16 文件 94 项 host 测试通过，不证明真实 GPU；最终 probe verdict 仍强制失败。
- **最新 host 回归（2026-11-06）**：资源账本、四项 OOM 和 converter 入口观察补测
  之后，16 文件共 **94 项通过**，三个实验仓 tracked `git diff --check` 通过。日志
  20 件逐项校验外置到
  `~/Documents/media-kit-validation-archive/artifacts/lg-p84-target-lease-20261105-host-regression-v5-20261106/`，
  清单 SHA256 `cae7720f94912253149cf7dd26e15086fa0fefb85f9c03355274a6e268739c81`；
  新版测试的独立变异复审已限定完成，任何后续修改须重跑受影响项。数据不证明真实 GPU、
  FFmpeg、完整 renderer、APK 或设备验收，未跟踪文件不在 diff-check 范围。
- **构建 bootstrap 再咨询（2026-11-06，只读）**：详见 M0 阻断说明 §5.2。现有
  FT/HB 静态库实际有双向符号引用，但 archive 不把对方对象直接合并；可能存在 seed→
  最终库的有限 bootstrap，仍需验证最终双向功能、生成配置、符号闭包和 seed 未泄漏。
  已有 HarfBuzz 依赖记录与最终 FreeType `.pc` 不一致，不能只增量 ninja。shaderc 旧
  `.pc` 当前本机可解析，空 prefix 缺口是元数据生成、`/usr`/`/usr/local` 别名布局、
  环境覆盖和来源闭包；NDK 的 `libshaderc.a` 依真实 Android.mk 是 combined 的复制品，
  不能只凭文件名判漏。NDK `libz.a`/`libatomic.a`、打包的 `libc++_shared.so`、
  Flutter engine/embedding 的 debug 源码闭包未证，旧依赖 HEAD 对应旧钉定 SHA、
  远端最新未核，当前标准入口未实现隔离/阶段 bootstrap；5.9 GiB 可用不是峰值预算。
  未联网、配置、构建或设备操作，APK 继续 blocked。
- **PQ 数值门固定快照独立初审（2026-11-06）**：生产 `73c18183…`、旧 host
  `9eef956e…`、旧测试 `3aea72e9…`；无新增 P0/P1。35 个指定变异中 31 项行为检出、
  4 项命中后存活（precast guard、`free(acc)`、`free(samples)`、EGL detach），128 次
  clang 成功、3248 次程序运行、0 超时；独立 301 个生产正负对照符合预期。审查精确
  找到旧 `b2b1c612…` 生产快照并对比：2,239,831 个有限值及完整原尺寸 source/四 LUT
  上传字节 hash 与旧版一致；这是 host 对照，不等于 Android/GPU。独立资源/前置门
  新夹具让四个存活变异分别触发 SIGABRT 或账本缺失；旧测试不能声称已检出。两条既有
  `GLQ` 早退仍有 live CPU 对象、未删 query/未 terminate，不属新增局部清理承诺。
  初审材料 9,296 文件逐项校验外置到
  `~/Documents/media-kit-validation-archive/artifacts/lg-p84-target-lease-20261105-pq-numerics-review-20261106/`，
  清单 SHA256 `593f47d017c5be7ed01cc1df05a173fe7a5d00b21adfe76edaeeed5bb14ee90f`。
  此为初审时状态；后续新测试的限定复审结果见顶部，不能把初审四项存活归为旧版已检出。
- **PQ 资源账本补测（2026-11-06，历史中间版本）**：在独立 critical 初审中途发现，原
  主流程 fixture 未能检出删去失败路径 `free(acc)`、samples 清理和 EGL detach 的变异；
  新版 host GL 替身对 probe 的 malloc/free 按指针记录全部 18 次分配和释放，并核验
  EGL detach/query delete/terminate；另逐一注入四个 accuracy 数组分配失败，核验
  其余已成功分配对象的清理。完整 accuracy 主流程与原 canary 对照定向通过，当时
  PQ 13 项 host 测试通过。这是 host 替身，不证明真实 GL 资源全部销毁；当时补测后的
  独立复审尚未完成，最终结果见顶部。中间版资源账本曾重跑全部 16 文件 94 项通过，
  此后追加四个 OOM 分支并重跑 PQ 13 项；最终版本完整重跑结果见顶部。
- **上一版 host 全量回归（2026-11-06）**：顺序执行原 13 文件及新增离线计划、thermal、
  instant 共 16 个测试文件，**94 项通过**：各文件依次为 4/1/1/1/1/1/1/3/1/13/11/7/6/7/28/8。
  其中 PQ 故障注入的 `verdict=fail` 为预期日志；APK verifier 的重复 ZIP warning
  属于负例测试。三个实验仓 `git diff --check` 通过，但不覆盖 untracked 文件。
  当前 PQ 源使用 NDK 27.2 Android API24 的 clang `-fsyntax-only` 通过，未生成或执行
  Android 探针二进制。16 个分文件日志、三个 diff 检查、Android 语法输出、修前反例和
  汇总共 23 件逐文件校验后外置到
  `~/Documents/media-kit-validation-archive/artifacts/lg-p84-target-lease-20261105-host-regression-20261106/`，
  清单 SHA256 `0c8c93b56ab56a01eec20a517d8c1bd32ae3bfdacf50679983d5b7ddc14d7c7d`。
  都是 host/静态检查，不证明真实 GPU/FFmpeg/完整 renderer、APK 或设备验收；当时 PQ
  数值门的独立 critical 尚在运行，最终限定复审见顶部，后续修改需重跑受影响测试。
- **PQ 非有限与溢出失败门（2026-11-06，历史初审版本与后续补测）**：
  `tool/native/lg_pq_lut_probe.c` 的 `f32_to_f16` 对 NaN 给 canonical qNaN；新
  `checked_half` 先拒绝 double 非有限/超过 FLT_MAX，再拒绝 half Inf/NaN，成功才写。
  finite 双舍入、normal RNE 和 small RTZ 不变；65505 仍可按原策略得到最大 finite half。
  analytic 与四个 LUT accuracy 读回每次预填 NaN，按像素检查包括 alpha 在内的所有
  分量，首错打印 read/variant/pixel/component 并退出；CPU reference 的 source/PQ/tail
  转换边界也检查。新数值失败路径释放四个读回数组和 samples、删除 query 并结束 EGL；
  原其他 `GLQ` 早退清理不在此声明范围，源纹理/LUT 上传仍沿旧有限生成假设。
  主流程 host 替身新增 16×16 模式和假 query，让真实 main 到达 accuracy/reference；
  修改前首像素 5 次读回×4 通道×NaN/Inf/大值/跳写的 80 项全部未及时拒绝，修改后
  指定 80 项及 24 个其他像素注入、CPU 参考三个转换边界均进入预期退出；既有完整
  主流程 canary 仍在首 warmup 故意中止。全部 13 项 host 测试和独立 host CPU
  self-test 通过（此前 CPU 注入夹具两次因 unused warning 编译失败，补 `(void)` 后
  才通过；不将编译失败计为检出）。这不是 GPU、真实 GLSL 或定时有效性证明；
  `validation=unverified` 和失败 verdict 保持。生产 SHA256
  `73c18183d0b828a997253579ccd80382c3a7016d302baf1857089e161d651d82`。初审版本
  host GL `9eef956e7156a5044c737dd2c986a2283e29aed7142574a7beab1c7949845eb8`、测试
  `3aea72e9222174e63d992c52f4a796e241466aa92c1a925b56fd3c53076ec2fd`；后续资源
  账本及四项 OOM 补测后 host GL `98c7f7d9ab379c1f30164b19be58d871c52ca6da6a100b3c57e55bc7cdc5a406`、
  头文件 `84ea7f3250cd0e88131a02890ccd80da1d2a591923c3464a39a8c9331902d03d`；测试增加
  converter 入口有界断言后的中间版 SHA256
  `7252aa6adb9536624045f3abaef2f603559b7fbb54c9e94bf94f59c7cfc0616f`；其后测试再次修订，
  最终版本和限定复审结果见顶部。
- **消费者与计时后续只读咨询（2026-11-06）**：`gpu-next` 动态选项使 renderer/queue
  reset，但静态源参数不变时 mapper 保留，暂停后启用 hook/scaler 可复用旧 small；旧
  `gpu` 同 frame ID 可跳过 map、使用静态 image_params。所有用途还包括独立 atlas
  render；fresh 时只检查当前配置不能约束未来用途。消费前预约真实源网格 scratch
  的窄域候选及其 draw/overlay/hook 失败、重建质量与资源约束仍未闭合。四 full pool
  加一 full scratch 名义 281.25 MiB，不含 renderer/codec/swapchain 等，非设备峰值。
  计时 consultation 建议一个 EGL context 唯一 owner 管理非嵌套 elapsed query 和
  disjoint；在发行时绑定 source/queue/lease/map/cache/output/attempt/query 代次，
  将实际执行成本和复用来源分账，split final 在 submit 后还须单列，fused 不得重复计。
  PTS、异步回调、历史 query 和纹理名均不能独自证明同帧内容；清屏/blit/upload 等
  覆盖未闭合时不称完整帧时。候选仅为设计，未改生产计时或运行设备，M0/M2 blocked。
- **离线租约请求计划（2026-11-06，限定独立复审完成）**：
  `tool/lg_p84_lease_control_plan.py` 仅生成显式同 sync 的 3–32 对 AB/BA 请求，固定
  `executionAllowed=false`、`m2Eligible=false`、`not-evaluated`；不接设备入口或旧
  summary。独立初审 41 个变异全部成功编译/运行，27 检出、14 存活（含 TARGET 自引用、
  副作用路径、严格子类和缺键异常）。补独立字面量、边界及观察门后 7 项通过；独立
  复审原 14 项均确认注入与命中，4 项在测试模块顶层 exec 由 audit 异常拒绝、9 项至少
  unittest 断言失败、1 项由运行 KeyError 检出，0 超时/编译失败；基线及三类合法对照
  均 7/7。受观察调用包含两种 sync×3–32 和六个非法组合，并非所有输入；普通功能
  测试部分调用未置观察。另有 `pair_count=None` 的文件写入、底层 fd 输出、额外 audit
  hook 和预存 hook 拒绝注册等 P2 反例，不是 I/O 沙箱；手工 exec 的门不覆盖 loader，
  普通导入还可能生成 pyc。固定版本经源码及限定观察支持“模块逻辑不发起额外 I/O”，
  不代表任何未来变更无副作用，字典亦非防篡改授权。旧 `validCompletedProfile` 仍可
  被外部误读，不能把本 helper 扩大为系统级 M2 准入。模块 SHA256
  `dbe09830273b8e9e7847f427184861e64e098cc783e0f1700aeb1fefdd599687`，新测试
  `eef9b45ed199fd5f8671573b8294946b7e3eb7fd9df25e5d138c37b61f2c80e2`。两轮
  311/171 文件复制并逐项校验至
  `~/Documents/media-kit-validation-archive/artifacts/lg-p84-target-lease-20261105-control-plan-review-20261106/`，
  `SHA256SUMS` 自身 `1011994902f7cef5561b3f4b9f63a43bb5b4a3ef5ae32b3a15d9f5312d4695e6`。
  该计划不证明请求生效、消费、同包或计时，M2 仍未验收。
- **strict cache 比较补测（2026-11-06，限定独立复审完成）**：`tool/test_lg_p84_mix_cache.py`
  在真实 renderer 提取的缓存选择片段加 mapper host 替身中，先创建 A/B/C/D 并使 A
  lease 退休，再单独设置 A cache 的 crop/hash/color/profile 任一失配；strict（关闭
  preserve）须请求 A 并因 consumed/无 lease 失败；非 strict（开启 preserve）仍可命中。
  每类另有全部匹配对照，源尺寸/no-caps 与 target 两种模式均执行；组合测试 1 项通过。
  当前 mix SHA256 `2e420ef5f6f88b0ea6ef751108124259bc38ef417a3df89eadcc09219cf23e24`，
  导入的 surface fixture 保持 `b4f90ffce7d84a638ad2f5d9aad729bbb677a3caec5e44fb7a7b981dfd97f9d0`。
  独立 critical 对 120 个隔离 C 程序全部成功编译：39 次运行断言检出、81 次预期通过，
  无编译/运行超时。四项真实比较单删的完整测试及 no-caps/target 独立场景均检出；
  always/never strict 的完整测试由旧 resize 场景先检出，新增场景分别隔离后才确认
  命中并检出。20 个基线组合均通过；无新 P0/P1/P2。复核材料 492 文件逐项校验后
  外置到 `~/Documents/media-kit-validation-archive/artifacts/`
  `lg-p84-target-lease-20261105-strict-cache-review-20261106/`，原 `sha256.json`
  SHA256 `f605e5f9b09755a7e40b08c12a62c7a902e64fdc3bc24ddf5cdd4d12f0118542`。
  color/profile 比较仍是整数替身，不测试真实结构/ICC 语义、完整 renderer、真实
  queue/权重或 GPU。原 13 文件 49 项全量在这次 mix 新改前通过，修订后暂仅 mix
  定向重跑；不得扩展结论为所有 cache 路径已验。
- **底层缩放错误传播（2026-11-06，限定独立复审完成）**：只读 specialist 确认原 `mp_sws_scale`
  忽略底层 `sws_scale` 的负返回，非对齐目标还会回拷。独立临时 host 真函数/替身注入
  `-22/-12` 重现，非 FFmpeg 实际失败；同版本 ARM32 NEON 某些合法路径成功返回 0，
  不能要求返回值等于目标高。Lead 修改 `perf2-mpv/video/sws_utils.c`：仅负值原样返回、
  在回拷前退出，非负仍照旧回拷并返回 0。新 `tool/test_lg_p84_sws_error.py` 修前两项
  失败，修后三项通过；既有软件截图 host 测试通过，NDK 27.2 `-fsyntax-only` 通过。
  初版测试 SHA256 `ffab017a25aaff75a19ee166dfa20ff0accdf3c554e7fe227086007579e44b8b`，
  生产文件 `2f058c987222c34a2d5303212d16a717ceb02ea3f8e669afcb36e76d87e0954a`。
  独立 critical 首审无新增 P0/P1：24 项非等价变异中 22 项成功编译并在命中后至少
  一个分组断言检出，其中一项另有 SIGSEGV；2 项未命中存活。补 reinit=1、源对齐分配
  失败的独立对照后，测试新 SHA256
  `1d2957f6783fd6e692b8980b0e4bbf77b00df4205e897999cf2fda5643a78eb9`；独立复审
  两项分别在命中后断言/SIGSEGV 检出、合法对照通过，未发现新 P0/P1/P2。两轮原始
  314/37 文件归档至
  `~/Documents/media-kit-validation-archive/artifacts/lg-p84-target-lease-20261105-sws-review-20261106/`，
  源与副本逐文件比对，清单 SHA256
  `a72973cbbaa6de52ce70856cde0ad094d0e8aa668baea438283b1c5a6f2883a7`。
  测试不运行真实 FFmpeg/zimg、像素或设备。直接目标可能部分写入，`vo_kitty`、
  `vo_drm`、`vo_wlshm`、`vo_x11`、`vo_sixel`、`vo_tct` 既有路径忽略返回；
  `sub/draw_bmp.c:439–443,872–883` 尚有失败后对象/变更 ID 提前缓存的既有恢复缺口。
  它们不否定软件截图释放失败目标的局部修复，但不能称全局或所有字幕失败关闭；
  真实 context 失败后复用未证。
- **PQ half 舍入契约只读咨询（2026-11-06）**：`f32_to_f16` 实为 double→float，再
  正规值 RNE/小值 RTZ；小值移位在可达范围正确。`0x33000001` 等 f32 输入处于 half
  小值区间（不意味着它们是 f32 子正规数），按 RTZ 与 RNE 不同；native
  `libplacebo/src/dispatch.c` tail 也显式 small-RTZ，不可把
  各阶段统一改成 RNE。NaN 被函数归为 Inf；有限实际生成域不产生 NaN，不称设备故障。
  `1+2^-11+2^-30` 等 double→float→half 与直接 double→half RNE 不同；本机 libm
  重放 3,569,792 source 像素有 221 个双舍入差异、4096/sqrt LUT 有 1 个差异，限定于
  host，不证明 Android 或 GPU 传播。63,488 个有限 half 的 readback 重编码往返无误，
  NaN 分类和跨符号 ULP 仍不可靠；当前 self-test 的采样不区分 small RTZ/RNE。后续须
  分离上传字节、native tail、目标 FBO 和高精参考模型，不擅自改为统一舍入；真实 GPU
  与四锚点仍未验，probe `validation=unverified`/失败保持。
- **预留 scratch 只读咨询（2026-11-06）**：固定精确源尺寸/格式、同存活 context、
  progressive、串行且不重入时，独立源网格 scratch 可在旧读取命令已提交、cache/queue
  不别名它的条件下复用，消除重建目标的运行时创建；不消除 draw、hook 输出及其他资源
  失败。已退休 A 的 cache miss 没有数据可重建；动态 hook 多 pass 仍分配、尺寸类别
  改变和 context loss 不能靠单槽覆盖，隔行 prev/current/next 可需同时 acquire。
  当前 mapper 先 release codec 再选尺寸/分配，消费前预约未实现；即使提前预约失败可
  改选 full，也不保证 full 成功。4 small+1 full 名义约 165.191 MiB，加入条件式四张
  同尺寸 mix cache 约 274.133 MiB，均不含其他资源/在飞重叠，非实测峰值。此思路不是
  全域可行或接入批准；不放宽单份 lease、退休和用户功能红线，M0 保持 blocked。
- **证据外置（2026-11-06）**：本轮初版 mapper 复核、PQ half 及 sws 只读反例三份
  临时目录复制到 `~/Documents/media-kit-validation-archive/artifacts/`
  `lg-p84-target-lease-20261105-host-consults-20261106/`，分别 274/6/3 文件，复制前后
  源与副本逐文件 SHA256 一致，`SHA256SUMS` 自身为
  `be85a8487f7482375d0abaa0f73c41bad1bc2fb3a4f87ca748bb122d67ce5744`；未删除原件，
  均为 host 复核产物，不是 APK 或设备验收。
- **M2 纯预检范围复核（2026-11-06，只读）**：独立 specialist 确认 instant 的
  `measure_clock()` 在 `thermal.run()` 前触发 ADB，后者又先创建 output 后校验，
  `finally` 还可能读设备；仅在 run 中加新实验参数门不能保证无副作用。当前建议仅
  研究独立纯函数请求计划：显式相同 sync、AB/BA 交错、两组列明的请求属性除 target
  外一致，输出强制 `executionAllowed=false`、`m2Eligible=false`，不生成旧 summary、
  不接两个设备入口；它只能约束请求，不能证明同包、属性读回、实际发布/消费或计时，
  也不能防止外部误读历史 `validCompletedProfile`。该建议后续的离线计划实施及复审
  状态见本节顶部；现有 CLI 和实验语义不变。未来新入口若实施须在 instant/thermal CLI 及直接 run 的任何副作用前固定拒绝，
  未经独立审查不得把它作为设备放行。
- **M2 轮次控制只读咨询（2026-11-06）**：现有默认 sync 实验按 baseline/candidate
  分别选 display-resample/audio，而 `--lease-target` 只额外写属性，直接配对会混入
  sync 变化；publish-flush/input-fbo/fusion-table 又有各自已有语义。specialist 建议
  后续新设独立 lease-target 实验并强制显式同步模式，保留旧接口行为，在接触设备前
  校验组合；请求值、ADB 读回、逐帧发布/采样 witness、计时资格应分开记录。现仅
  请求属性不证明小纹理消费；当前源码的 `lease published` 日志位于发布点但只在
  尺寸变化时输出，不含逐帧/消费身份，不能与历史 F1 copy 前选择日志混为一谈。
  逐轮同包、matched-start、缓存命中、唯一计时所有者与三对有效性均仍需独立门。
  本建议未实现、未测试、不放行设备或 M2；只读结果不证明已完成轮次控制。
- **mapper 目标纹理内容身份补测（2026-11-06，限定独立复审完成）**：初版 surface
  SHA256 `d52e35d91a9451e9db28396c23c06aaa8eab074ca02bf770831b03b023a5d17e`、mix
  `3739412b3c2643091e03b8857aaf9651f69f9787ffb62fbecbc428714b2f6d05`；独立 critical
  完成 81 次隔离 C 编译运行，0 编译失败/超时。mix 在 full/target 指定场景中错画、
  错发布及 B 内容被 D 覆盖等由运行断言检出；surface full-size horizon 对第二/第四
  帧错画、D 覆盖 B 三个 full-only 变异整套存活，均有命中标记。原 fixture 将预设
  `next_timestamp` 当真实 latch 输出，合法 +1ms 误拒；NULL 纹理的合法 free 亦误拒。
  现补 surface full A–D 与 B 重取的 fake-content、实际 latch 返回和 release buffer
  账本，新增非整数 PTS、±1ms、timeout/error/stale 及空纹理清理对照；surface 新
  SHA256 `b4f90ffce7d84a638ad2f5d9aad729bbb677a3caec5e44fb7a7b981dfd97f9d0`，mix
  自身 SHA 不变但导入新 fixture；两项测试各 1 项通过。修订版独立复核 43 个隔离 C
  程序均成功编译，36 故障变异均 HIT 并由运行断言检出，7 个基线/合法对照通过，
  无超时；B 被 D 覆盖经标记确认在 B 成功重取后检出。±1/17/99ms、非整数 PTS、
  已退休帧存在时 latch 错误及分配失败后 NULL 清理均实际进入并通过；三项原 P2
  在限定范围关闭，无新 P0/P1。复核原件 176 文件复制至
  `~/Documents/media-kit-validation-archive/artifacts/lg-p84-target-lease-20261105-mapper-review-v2-20261106/`，
  源与副本逐文件一致，原 `sha256.json` 的 SHA256
  `fd77597a7ce5afcebff851aca1b9868082240345c02091e2df0f19efb95b935f`。fake content
  不是真实像素、FBO 或 GPU 同步，strict crop/hash/color/profile 等 cache 分支仍未
  全验；初版原始证据见本节证据外置条目。
- **构建入口只读咨询（2026-11-06）**：标准 wrapper 在 native/Flutter 前须阻断，
  native `Builder` 构造即创建 output/日志，早于依赖 make；仅在 install 或 verifier
  前设门不能保护写入。当前没有经证明的允许态，specialist 建议研究受控 perf2
  入口与构造器在首个副作用前固定拒绝，不提供环境/receipt 自述解锁。该门只能防误
  操作、不能证明来源，且会影响同入口其他调用，尚未实施或独立复核；不修改通用
  入口以假称解阻。详见 `m0-consumer-and-build-blockers-20261105.md` §4.1。
- **目标消费者独立 critical 设计复核（2026-11-06）**：未确认 P0，但候选仍有 P1
  阻断。实际 renderer 的 cache miss 局部 acquire 失败可设置持久
  `PL_RENDER_ERR_FRAME_MIXING` 并 nearest fallback，后续继续降级；新增 scratch
  分配/draw、overlay 或 witness 失败不能简单送入此路径后宣称混帧不变。动态 shader
  的 WHEN/input size/offset 以及无 hook 的 scaler/noop 分支也可观察物理网格；真实
  full 网格重建不恢复源细节，也不与非线性处理次序等价。还缺临时对象与部分失败的
  owner、全部显示/融合/截图/atlas 入口、table 身份、在飞同步和内存峰值。fresh
  准入须在 codec release 前决定；existing small 尚无满足全部原功能的通用无副作用
  故障回退。可研究脱离生产的纯 host 几何 helper，不放行 opt-in。完整证据与限定见
  `docs/validation/lg-p84-target-lease-20261105/m0-consumer-and-build-blockers-20261105.md`
  §2.3；四帧 horizon 仍是源/目标共有条件式问题，不把它误归因于 small。
- **PQ canary 初审及修订测试（2026-11-06，限定复审完成）**：初次 V2 独立
  critical 未确认当前 probe 新增生产 P0/P1，但原测试的源码提取起止可漏掉真实 main
  的整段 bypass，首行/列和多项 GL 状态调用及 main program 恢复也未被断言。初审
  的 45 项变异中 28 项成功编译后由运行断言检出、15 项存活（其中一项等价）、1 项
  编译失败、1 项 Python 文本门拒绝；额外 bypass 在旧 suite 存活。独立 reviewer 的
  886 个数据/GL 替身注入和全尺寸 CPU checker 测试通过，但不证明 GPU。现增加含
  假 framebuffer 的逐像素/通道 NaN/±Inf/错值/通道交换、旧相位、各 GL 检查点及
  状态账本；并将完整 device `main` 用 host doubles 编译运行至首个 timing draw，
  测试 canary bypass、失败相位和 program 恢复的集成路径。当前 11 项 host 测试通过，
  新测试 SHA256 `df186a6d68ed676d3a70404a68da5ef426edaa6be1f5e30ce75d058ac94906a2`；
  host double 的 `.h` SHA256
  `b06427da135c0e08d4dbb7fa0a9ea3846dbca8a424a06fca213596465e4455c7`。独立复审
  固定旧 `.c` 版本 `e9d3d10b07c0dce05b8724b9577241db58c4b775d14170feef312c9bfae833a0`，
  确认主流程 bypass、首行/列、指定 GL 状态及主 program 恢复变异在成功编译后被
  运行断言/trace 捕获；但发现漏附 FBO、误用默认 FBO、错误 source sampler、未恢复
  source texture 四个变异使完整 11 项仍通过。现已补 FBO/texture/uniform 状态账本，
  `.c` 新 SHA256 `a132791e1b9df5c0a107977470d772897270eb271d5bf54ed5bee0b3fa11b918`，
  11 项通过；四个新变异经独立复测均成功编译后被完整 main 的 trace 断言检出，
  正常流程及重复正确 FBO 绑定通过。reviewer 同时确认替身对等价 `PACK_ALIGNMENT=8`
  和额外未附着 RGBA16F 纹理两种合法流程误拒；这是固定测试序列的 P2 限制，不代表
  真实 GL 问题。假 shader 不执行 GLSL；完整 main 的 read 仍由替身按 phase 生成，
  并非真实 FBO/GPU。主流程故意在首个 warmup draw 返回错误，不能称完整设备 main
  或 timer 通过。三轮独立复核原始证据复制至
  `~/Documents/media-kit-validation-archive/artifacts/lg-p84-target-lease-20261105-pq-host-review-20261106/`，
  逐文件 SHA256 比对通过，清单自身 hash `c49ae4ddd3db7ea485c04c79fbceb6c618ac70cbcb112430c7999f769a2b3d96`。
  生产 C 未改，设备未运行，`validation=unverified` 和失败 verdict 保持。
- **四帧测试及截图失败边界（2026-11-06，限定复核完成）**：原四帧 mapper 测试
  经 critical 变异复核发现 B 重取未核正确纹理/源身份，D map 与 unmap 退休时点、
  fence 及资源身份、源码常量与夹具一致性有缺口；组合测试初步复核另指出 target 模式
  及单轴尺寸变化漏检。已补逐身份/时点断言、纹理 live 账本、常量一致性门及两类尺寸
  请求和独立宽高变化；两项 host 测试通过。组合测试的独立变异复核确认指定补强，
  当时保留 draw 目标身份及 strict crop/hash/color/profile 未执行等限制；前者后续补测
  状态见本节顶部。mapper 复核发现
  retirement fence 可由旧 publish fence 冒充、第二次等待 timeout 无断言，补强后独立
  复核确认两类变异均成功编译后由运行断言检出，合法 fence 状态对照通过。测试仍不运行
  真实 queue、GPU 或 codec，不代表目标消费者可接入。软件截图 fallback 新增缩放负返回
  失败关闭并释放源图/目标图/sws，裁剪 `mp_image_new_ref` 空值时释放源图；真实控制流
  加替身反例修前失败、修后通过，覆盖裁剪及非裁剪缩放失败和成功对照；Android NDK
  syntax-only 通过。独立 critical 在局部失败控制流无阻断 P0/P1；补足对象存活与等尺寸
  免缩放测试后，三个此前漏检变异均成功编译后被运行断言检出，合法 `talloc_free(NULL)`
  通过。引用空值为模拟，不证明真实 OOM 可恢复；底层 `sws_scale` 负值传播及
  限定独立复审见本节顶部，不修复共享 OSD 污染或证明像素/设备正确。mapper 及
  sws 夹具修订后相关 host 回归 **13 文件 49 项通过**（含 PQ canary）；后续又修改
  mix strict cache 测试，当前定向重跑及独立复审状态见本节顶部。三个实验仓库当时
  `git diff --check` 通过但不覆盖 untracked。测试日志
  `/var/folders/96/wxgz1n_d70g8rfl09q80jych0000gp/T/zcode-bash-5CrTpt/sess_a4c232fc-45b5-4360-a90a-68492eeed805/call_twM88VBzUWOIlWiIvofV9pvO-stdout.log`；
  其中 probe 故意输出的 fail/unverified 是测试内容而非 Python 失败。无新 APK 或设备轮。
- **PQ GPU 活性门试修（2026-11-06，初审后补测见上）**：独立探针在正式全尺寸 RGBA16F FBO
  上新增 clear/read、两次不同相位 draw/read，CPU 读缓冲每次以 NaN 污染并逐像素检查
  dyadic 四通道；仅 intended 证明该 clear/draw/read 路径有可观察写入，不证明 PQ、LUT
  或 timer。10 项 host 测试通过（首次 alpha 故障注入意外与 clear 值相同导致测试失败，
  已修正替身）；独立诊断 binary SHA256
  `36893b6df7dea61f8148d3a92068db27b6d080014a4a973ebed085fcff08811e` 已编译和 CPU
  自测，未部署/运行设备。独立 critical 初审已完成，后续补测及复审状态见上；GPU 活性
  尚未实测，四锚点、彩色 tail、
  LUT 精度和设备 timer 未闭合，最终 `unverified` 强制失败保持。
- **构建来源补充核查（2026-11-06，只读）**：旧依赖配方对多项组件指定钉定版本/SHA，
  当前多个 checkout HEAD 与其对应；未联网验证远端最新，不能把复制后重新编译等同遵守
  debug 的非钉定约束。本地 FFmpeg/libplacebo 修改须保留。现行 FreeType/HarfBuzz 已配
  互依赖，空 prefix 的 auto 配置结果未知；标准 shaderc 安装没有生成空树 `.pc`，Flutter
  SDK 与共享 Pub/插件缓存也有写入边界。实际链接/打包有 NDK runtime，不能由 builder
  的记录自动推定豁免。最近空余约 6.3 GiB，不证明隔离 bootstrap 峰值足够；来源、
  特性、受保护路径、独立 Git/缓存和空间预算均未闭合，APK 构建仍 blocked。详细输入
  和待审 bootstrap 分解见 `m0-consumer-and-build-blockers-20261105.md` §5.1。
- **候选目标消费者新设计（2026-11-06，独立设计复核阻断见上）**：specialist 区分源尺寸/目标
  尺寸共有的四帧失败与 small 新增失效。候选保持 queue 的逻辑 crop/signature 和原缓存
  判定，只有真实 acquire 的局部 frame 根据逐帧 witness 转换采样几何/深拷贝 overlay，
  cache hit 不因 lease 退休而额外重取；此为待审方案，不是实现或安全结论。源码级额外
  反例：用户在帧已缩小后启用观察 `HOOKED_size`/`textureSize` 的 hook，即使纯色也可
  区分物理网格；仅 fresh 关优化、修改 crop 或伪造声明不能保证原处理语义。建议研究
  在必要时按真实源逻辑尺寸生成临时重建工作纹理后执行原处理，不称恢复源细节；这会
  额外占用纹理并增加分配/失败域，是否满足资源与生命周期红线尚未复核。需同时比较
  on/off 的队列权重、缓存/重取、retirement 和 fallback 事件序列；不得隐藏字幕、
  关闭 hooks、改混帧或凭 nearest 成功掩盖失败。两 VO 继续不 opt-in。
- **目标消费者混帧阻断细化（2026-11-06）**：独立 specialist 构造源码级四帧 A/B/C/D
  反例：半径 2 的非零翼多帧插值下，A 缓存命中不触发 acquire，D fresh 可在正常 fence
  完成后按现行 FIFO 退休 A；后续严格尺寸失配或视频字幕 redraw 的签名变化要求 A 重取，
  consumed 命中却无 lease 而失败，renderer 可能退 nearest。该风险不依赖目标尺寸，
  本轮未实机复现；默认 preserve=true 多帧 resize 并非必定失效。详细前提和行号见
  `docs/validation/lg-p84-target-lease-20261105/m0-consumer-and-build-blockers-20261105.md`
  §2.1。pin 会改变退休契约，额外 copy/改所有权也各有代价；仍无已证明窄域和资源上界，
  两 VO 保持未 opt-in。另新增 `acceptance-audit-20261106.md` 对 M0–M5/PQ 逐项标注证据与缺口。
- **共享 OSD 独立 critical 设计复核（2026-11-06）**：只恢复对象尺寸和标记不能
  构成无副作用 transient 事务。普通 OSD/packer 可能保留临时尺寸缓存，单独回滚
  `vo_change_id` 可能让变化内容复用旧版本；字幕任意 PTS 的 `update_segment()`
  可销毁旧 decoder、消费待切换数据，外层快照无法撤销。临时 resize 通知须在产生前
  禁止；OSD 锁不覆盖字幕线程，也不能跨同步 VO 派发持有。审查仅为静态源码反例，
  未实机复现；完整缓存/字幕隔离仍 OPEN。仅软件 fallback 窄补丁：在 VO 截图请求
  前快照窗口几何，软件缩放与字幕/OSD 共用，非正尺寸拒绝 scaled 软件回退而不拒绝
  成功 VO 截图；真实函数替身回归修前失败、修后 1 项通过，NDK syntax-only 通过。
  独立 critical 在窄补丁范围未发现新 P0/P1，指出测试缺口后已补 flags、窗口截图、
  等待/采样顺序、零/负尺寸、空帧和资源账本；原 10 个漏检变异现 9 个由运行断言、
  1 个由运行时 SIGSEGV 检出，另两个成功缩放释放变异由断言检出。这不修复共享 OSD
  状态或先前已被污染的值，也不证明真实 talloc/缩放/GPU。
- **M3c owner 路径澄清（2026-11-06）**：显式 LG token 的单 open 策略仍保持；
  自动 managed owner 在 policy 层可能允许同 Session 重开，且内部 token 经 controller
  传入 bridge。源码亦显示 backend 的 `managedYuvCarrier` 可能与按 route 派生的
  controller 值不同；满足 YUV 准入和 FFI 等条件时可能进入 legacy 全局 arm，不是
  无 token 绕过准入。若 stop 后 hwdec owner shutdown，而输出槽重用不再次初始化
  bridge，则存在条件式重开风险；两动作是否实际触发 shutdown、历史轮是否走 fallback
  均未实证。不能简单删除 token、放宽 single-open 或认定重开通过。
- **PQ 单调截止（2026-11-06）**：timer drain 新增单调时钟检查，poll 前后均检查
  20 秒截止，时钟失败/倒退、sleep 失败和原 20,000 轮上限均失败；设备驱动调用本身
  无法由此硬中断。首次独立 critical 在调用最终返回的限定范围无新 P0/P1，指出四项
  测试变异漏检、测试进程无超时及主流程既有时钟读取错误未处理。已补四项反例和测试
  超时，主计时起止遇时钟错误/非法纳秒/倒退退出；9 项 host 测试通过。最新独立诊断
  二进制 `26d81f998e4c9c8eab78e42aa3b3b67712eb6583679279c6636e917e7bf87433`
  已编译和 CPU 自测，未运行设备。修订版独立复核未发现新 P0/P1：此前四项漏检变异
  现均成功编译后被运行断言检出，删除轮询 guard 则由测试自身 5 秒超时检出；主时钟
  错误/倒退定向变异亦由断言检出。统计输出须有完整终态且零退出码才可被考虑，
  `unverified` 强制失败保持。
- **构建来源新增阻断（2026-11-06）**：NDK27 `DUMP_TARGET_OUT` 和 make 规则确认
  shaderc 的 `NDK_APP_OUT=<deps>/shaderc/local` 实际生成 `<deps>/shaderc/local/local/arm64-v8a/libshaderc_combined.a`；
  标准 builder 原先读少一层 `local`，可能复制旧 archive。已修读取路径；两项 host
  回归在修复前分别重现误取旧库及真正输出缺失不失败，修后连同既有用例 7 项通过。
  独立 critical 复核确认局部路径修复和两项变异检出，但同一路径既有陈旧产物仍可能
  被无操作增量构建收录；共享 prefix 写入与环境变量覆盖实际依赖来源也是 P1。
  路径/哈希不能证明全部源码重建；全新 bootstrap、独立 prefix/缓存
  和空间峰值仍未闭合，禁止据此启动或宣称 APK 构建通过。空 prefix bootstrap 的
  FreeType/HarfBuzz 可选互依赖、Flutter SDK/Gradle/Pub 可写缓存及 App NDK28 等
  也未隔离；最近只读空余约 7.7 GiB，不足以据此证明构建峰值安全。
- **M2 计时方案仍未实现（2026-11-06）**：只读 specialist 核实当前 input 仅计
  copy draw，renderer 为历史滚动值，分属不同 session；两套计时器各自读取消耗
  `GL_GPU_DISJOINT_EXT`，不能简单同时开启。建议唯一 context 计时所有者、非嵌套
  命令区间、发行时记录 source/lease/render/submit 身份和完整/缺失账本，再单独
  验证无计时播放与热态；尚无实现，GPU 工作耗时不等于显示延迟或功耗。现有 thermal
  默认 baseline/candidate 改变 `video-sync`，目标 A/B 必须同 mode 只切 lease，不能
  将该默认模式差异混入效果；A/A、扰动和真实呈现反馈仍需单列。
- **M3c 四动作已定位，验收仍 OPEN（2026-11-06）**：P84 探针枚举为
  `PauseHoldResume`、`SeekForwardBack`、`NearEOFReplay`、`StopReopen`。前两项
  只覆盖暂停/暂停态 seek 的特定时序；后两项要求同 Session/Player、同源重开。
  当前 LG owner token 的单次 open 策略与两项重开冲突，不能用新进程冒充通过；
  HOME、双向真实 resize、still 和切到另一源需另证。无新实机轮。
- **截图测试加强（2026-11-06）**：新增提取真实 `update_overlays` 与 screenshot
  的 host 测试。独立 critical 复审最初发现 overlay 行为 false-pass 和合法重建
  误报，之后已补独立预期、上传/下载身份、尺寸、稀疏索引及 parts 存活账本；复核
  的指定变异均成功编译并被运行断言检出，parts 负例另经 ASan/UBSan。840 次调用
  中 210 次无 overlay、名义两类故障注入各 240 次中实际各触发 120 次；atlas
  fixture 的 source rect 不代表可采样的真实几何。该测试仍非真实 OSD、talloc、GPU
  或截图画面验收，共享 OSD 尺寸风险继续 OPEN。
- **PQ 探针进一步限定（2026-11-06）**：source/LUT sampler 显式 highp；修复 ring
  16、批 120 且仅批末 flush 可漏采的问题：每至多 16 个 query 先 flush/drain，不能
  开始计时或出现 disjoint、零值、缓冲不足时失败，set 内计数需闭合。8 项 host 测试
  通过，含提取真实批次块验证 16×7+8 和失败不继续；独立 critical 复核该限定修改
  未发现新 P0/P1，并确认 begin/end GL 错、读取结果后 disjoint、set 末门、drain
  失败和误复位 verdict 六项变异均成功编译后被运行断言检出。最新源码诊断二进制 SHA256
  `3b2671e12edf763e8b161cdb60a289404462ce20498d552d36be65d830021c9e`
  已编译并通过 CPU 自测，未部署/运行设备，GLSL 真机编译、取样和计时精度未知；
  `unverified` 强制失败仍在。现有 drain 是有限轮询，不是 GL 驱动调用的硬超时；
  四锚点目前仅报告不构成门，RGBA 全灰不能检测通道错接。不能使用历史 B 轨或将
  host 结果提升为 GPU 验收。
- **本次接续的失败边界修复（2026-11-05）**：公共 mapper 在 `mp_image_setrefp`
  返回空引用时清空 request 并返回，不再调用 driver；`gpu-next` 的 reconfig 失败后
  release 遇到空 mapper 不再解引用。真实提取函数的 host doubles 测试覆盖空引用、
  旧小退休 lease、后续新帧和失败帧不重复 release/latch/draw；slot、draw、lease
  引用与 publish fence 四类失败在已有退休 lease 时也分别测试。另覆盖非 ra_pl 的
  1–4 平面各包装失败点及 wrapper 销毁先于 unmap。两处生产代码及上述限定断言经
  独立 critical review，未发现阻断问题；纹理/codec 逐对象账本、真实 GL 与完整
  mapper 重建仍未验证。**空引用为替身注入，不等于真实 MediaCodec OOM 可恢复**：
  实际引用计数帧的部分 OOM 路径会 abort。两处 C 文件 Android NDK
  `-fsyntax-only` 通过；未进行完整构建或设备播放。
- **截图 OSD 所有权试修（2026-11-05）**：`video_screenshot()` 改用局部
  `screenshot_osd`，统一在 render/download 成功和失败路径释放局部 atlas 与 parts；
  不再直接重写播放的 `fp->subs`/`p->osd_state`。从真实 screenshot 函数提取的
  host doubles 测试覆盖三种字幕混合模式、scaled/字幕/OSD 开关及 render/download
  结果组合，通过；NDK 语法检查通过。`osd_render()` 本身仍共享 OSD 对象并改变
  内部状态。局部 atlas/parts 所有权和清理经独立 critical 复核无阻断；补充 flags、
  坐标及 source overlay 清零断言后，相关三个变异均成功编译并被运行断言检出。
  独立静态复核另发现既有风险：视频坐标字幕的窗口截图可能将共享 OSD 尺寸改成
  源 crop 尺寸，渲染/下载失败后软件窗口截图回退可能读取该尺寸；尚未实机复现，
  也不能归因于局部 atlas 补丁。全局 OSD 状态恢复、真实纹理/字幕行为仍 OPEN，
  不能宣称完整截图生命周期验收通过。
- **PQ 探针部分修复，仍禁止采信（2026-11-05）**：GLQ 改为单次执行，错误和 timer
  drain 超时立即失败；LUT 端点建表改为 `i/(N-1)` 并对应 half-texel 采样映射。
  五项 host 测试与 CPU 端点自测通过，独立 NDK 诊断二进制构建通过（非 APK）；
  暂以无条件 `validation=unverified`/失败 verdict 阻断误用。clear/draw/read 活性
  canary、四锚点 GPU 断言、timer 真机有效性尚未完成；本次局部补丁经独立 critical
  复核无新增阻断，三个测试盲区通过变异测试关闭，最终完整复审仍待做。历史轨 B 数据
  保持无效，不得因构建通过宣称探针可用。
- **再次只读核验（2026-11-05）**：LG/LYA 均在线，LG 查询时为 Asleep、屏幕 OFF；
  未操作或运行新设备轮，不能据此推断旧恢复失败轮的现场。最近查询本卷可用约 7.1 GiB，
  现有 build 仍指向共享 prefix，隔离 bootstrap/空间峰值未建立。specialist 确认
  native 实际 archive 来自共享依赖而非直接链接 perf2-lp；混帧缓存可绕过 acquire，
  而缓存寿命可能超过 lease，清缓存后重取已消费帧可能失败。截图 atlas 的局部
  所有权已有试修，但全局 OSD 状态、多 render 许可和实际表示 witness 仍待解决，
  不能启用目标消费者。

- **性能信号与方案重排（2026-11-05）**：两名 specialist 独立复算历史有效
  配对轮。稳定窗频率中位 A/B=214/133 MHz，B 多数但非全部采样在 133 MHz；
  按逐样本频率×busy 等权平均的观察代理，input/render 两类轮分别降 17.20%/
  19.58%，不是功率或能量。input copy 的 GPU elapsed 实际降 25.85–36.11%；
  render 实际增 58.54–59.12%，只有乘每轮频率中位数的归一化代理接近（降
  1.11–1.47%）。两阶段不同 session，不得相加当同帧总耗时；详见证据 README。
  这是真实且值得继续的优化信号，但不能宣布 M2 或画质验收通过。用户澄清不要求
  截图/暂停放大恢复源细节后，specialist 及独立 critical 设计审查建议优先
  direct OES→small 单份 lease；接入的几何、字幕/截图所有权、缓存和失败清理
  仍须实施。不能宣称该审查等于修复后的最终复审或实机验证。
- **critical review 已完成；修复和最终复审待做（2026-11-05）**：用户要求的
  workflow + mimo-v2.6-pro 在提供方恢复后完成（`dwfrun-8d1315c5`）。4 项
  P1 经独立静态复核：mapper 复用路径几何声明不一致、video 字幕与 crop 基
  风险、M2/M3a 判读口径错误；代码风险尚未实机复现。11 项 P2 **未做独立
  复核**，不是“复核后不成立”。报告
  `docs/validation/lg-p84-target-lease-20261105/critical-review-workflow-original-20261105.md`
  保留 workflow 原件；报告把跨会话耗时和当作逐帧总时长、建议仅回写
  `dst_params` 等说法亦不作为已证事实，按 README 更正。修复后另做 critical
  复审；原 review 完成不等于 M5 收尾复审通过。
- **M2 PASS 撤回**：copy 频率归一化三对 -60.30/-57.17/-53.92%；跨不同
  session 的 input 与 render 相加得到预登记的合成代理 -20.72/-19.81/-18.80%，
  中位 -19.81%，不是同帧总时长。相加的各轮墙钟中位代理 A≈17.60/17.61/
  17.64ms、B≈22.45/22.72/23.05ms，同样不是实测逐帧总时长。首组 input
  冷锚而 render 热锚，严格同热锚仅两组；DVFS 未控制，不能推出节能或真实
  时延降幅。原始 pair/轮次不改写。
- **M3a PASS 撤回**：保留 6 轮 schema3 capture，但原有每轮分析的 A/B 指同一
  lease 状态内的渲染分支；后续跨轮 raw 对比的限制见下。lease 开时该轮内
  YUV 分支差 81/0/95 像素；不能与先例中间 UV 坐标覆盖 40% 对照得出画质
  通过，也不能当作目标 lease 的直接差异或证明肉眼不可辨。同轮 repeat
  不证明跨轮输入相同。多轮 `restoration-failed`，`screen-state-not-restored`
  的归因和每轮最终屏幕状态未闭环；不得声称是既有行为或均已手动恢复。
  限制包括仅中心 64×64、插桩可能改变 shader、非原始 YUV/面板。
- **F1 观察性证据**：曾记录目标尺寸 `2672x1336` 与融合
  `committed=300/307`，该轮 `completed-observation` 且 restorationVerified；
  日志在 copy 前打印，不能单靠此日志证明每次发布成功。它不覆盖字幕、
  异构尺寸重绘或完整生命周期。收据 `md5-receipts.ndjson` 覆盖 M2 轮，
  不含 F1/M3a；F1/M3a 的包身份不应称为已有同一格式逐轮收据。
- **跨轮补充（探索性，2026-11-05）**：新增 `tool/analyze_lg_p84_lease_rounds.py`
  及 11 项通过的 host 单测；六轮因恢复失败默认拒绝，显式允许后才输出非验收
  结果。首轮独立 review 指出恢复失败可掩盖其他采集失败、A/B/A 锚命名过宽；
  v2 已收窄并重算，两项修正及后续历史成功轮标签补丁均已独立复核关闭；
  该复核不证明历史轮恢复成功或跨进程输入像素身份。工具另新增“调用者输入
  顺序不证明真实采集时序”的提示，已独立复核；既有 v2 输出早于该提示。
  35/600/720s 的 64×64 ROI 中，同分支 A2
  跨轮 YUV 浮点逐位差分别为 4060/3847/4032 像素，B2 为 4062/3847/4033；
  同组归档 shader SHA 相同。缺 A/A 锚，跨进程输入像素一致性未证明，不能归因、
  判断肉眼观感或声称验收；详见证据 README。
- **代码安全隔离（未完成目标功能）**：`hwdec` 新增消费者 opt-in、逐映射 request
  与 lease 绑定几何；既有 `gpu`/`gpu-next` 均未 opt-in，属性打开亦只创建源尺寸
  lease。撤去 gpu-next 原有的共享 mapped 尺寸和 crop 改写；原实验补丁保全为
  `geometry-repair-prepatch-20261105.diff`。目标分配/绘制失败只令后续 fresh
  copy 回源尺寸，当前帧仍可能失败，已有缩小 lease 无法恢复细节。独立 critical
  静态 review 发现的分配失败重复尝试及 request 语义两项已修复并复核关闭；不代表
  实机或目标功能已通过。mapper gate/公共 map-unmap 4 项、FBO GL double 1 项通过；
  新增从真实 mapper 提取控制流的 host 测试 1 项通过，覆盖缩小/源尺寸 lease 退休和
  重绘、空闲 slot 重建、分配/绘制/lease 引用/发布 fence 失败及既有退休 fence
  故障行为，并在真实提取的 teardown 后核对替身 fence/ref 对象及纹理总数闭合。
  另验证 target draw 失败禁用后可采纳旧小 lease、后续 fresh 回源且失败帧不重复
  release；后续已补已有退休 lease 时 slot/draw/lease-ref/publish-fence 失败组合，
  详见本节顶部本次接续记录。新增测试及上述组合已独立复核通过（替身生命周期
  P2 的限定范围已关闭）。仍未覆盖真实 FFmpeg/GL/GPU、逐纹理双重释放、真实
  OOM、完整销毁分支、线程调度和设备。此前逻辑在 `setrefp` 返回 NULL 后仍调用
  driver；现已补返回 NULL 的替身故障注入及早退，不代表真实 OOM 可恢复。
  三区 Android `-fsyntax-only` 通过；尚无目标消费者或真实 resize 验收。
- **消费者接入的边界**：renderer 混帧缓存命中可绕过 acquire；已有小 lease 的源
  细节无法由坐标变换恢复，但用户明确没有要求截图或暂停放大恢复源细节，不以保留
  源尺寸副本作为硬条件，也不能据此认定用户已接受任意画质退化。推荐单份 direct
  OES→small；播放、截图与字幕按真实几何正确处理，画质另验。局部 crop/字幕的
  资源所有权、缓存命中、尺寸变化及失败清理尚待实现和测试，当前消费者未 opt-in。
  源码依据和隔离构建缺口见
  `docs/validation/lg-p84-target-lease-20261105/m0-consumer-and-build-blockers-20261105.md`。
- **后续**：字幕、截图、缓存和目标尺寸消费者实现仍未完成；完整构建依赖共享脏
  checkout/prefix。只读核查确认 mpv 独立 build 仍链接共享 prefix，标准入口需预配
  依赖树，tag 也不能隔离 Flutter 固定输出；全新 bootstrap、写入边界和 7.5 GiB 可用
  空间峰值均未验证，构建保持 blocked，不可复制旧 build 直接执行或覆盖。完成设计、行为测试和隔离构建后
  才能受控功能轮；M3b 观感、M3c 生命周期与真实 resize、
  M4 热态、M5 LYA 和最终 critical 复审均未验收。未知/失败轮、B-R2 无配对
  轮及大文件证据保留；设备恢复现场待核。
- **红线**：帧身份/退休契约、updateTexImage 调度、A/V 同步不动；不伪报尺寸
  绕过 crop 门；等比缩放之外回退源尺寸 lease；≥10% 为验收目标非预测；
  实机冲突等待重试；每轮前 md5 门；收尾前 critical 复审；提交需授权。

## Findings

- 收益模型：copy 面积比 0.484，若线性则 copy 5.83→2.82ms、总 -17.1%、新份额 19.3%
  （specialist 排序首推；模型≠承诺，copy 将从 identity 变真滤波）。
- round2 曾观察到 UNORM16 较 RGBA16F 更慢（copy +44%、融合 +42%，具体条件见
  round2 证据），不能单凭同为 64bpp 推断硬件内部快路径机理；本实验保持 RGBA16F。
- 等比判定：本片 3840×1920 与目标 2672×1336 同为 2.0 全帧，适用；其余几何回退。

## Decisions

- 任务立项（2026-11-05，用户指示新会话开启）；方案文档为事实源。
- **初版 M0 裁决待重审（2026-11-05）**：原取 A1、否决 A2，记录在方案§七。
  review 发现 cur/retired 路径声明失同步，且 `hwdec.h` 的 `dst_params` 初始化
  后不可变契约及 `--vo=gpu` 消费点未被旧方案安全覆盖；原“偏离但安全”撤回。
  方案须改为显式可核验的逐映射几何及消费者 opt-in，未完成前保持默认关。
- 主树 feature/dv 已含 HOME 任务提交（`17174189`），perf2 分支是否变基由用户定，
  不自行合入。

## Review

- mimo workflow 已完成本轮修改的静态 critical review；4 P1 经独立静态复核、
  11 P2 未独立复核。报告原件保留；修复后和 M5 收尾前仍需独立 critical
  复审及相应实机验收。PQ 探针可信性修复为独立小包。
