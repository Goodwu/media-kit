# M2′ 同帧 GPU 总时长测量口径设计（2026-11-08，specialist 设计稿）

状态：**设计稿，未经独立 critical 审查，未实施**。作者：specialist（只读
设计委托）；行号对应 perf2-mpv 工作树（vo_gpu_next.c 快照 64e320ef…）与
perf2-lp 3a13e0ca。本文是 S1–S4 实施切分的依据；实施由 Lead 执行，
S3 完成后必须独立 critical 复审（触及 acquire 生命周期与 swap 路径）。

## 0. 结论摘要

1. 用一个 owner 做分段求和，不用外层大区间。owner 放在 Android ra_ctx
   priv，负责一帧（一张 ticket）内互不重叠的 elapsed 区间：渲染段、copy 段、
   final-yuv 段。CPU 等待点不进任何区间；不在 draw→flip 外套大 query。
2. 11-06 的"ra_ctx 持有 ticket/generation owner"成立；"LP client adapter"
   在 M2′ 不需要（渲染段靠既有 hwdec_acquire/release 回调挂起/恢复，
   LP fork 零改动）。逐 pass 归属与单一活动 query 冲突，仍归旧 render 模式。
3. 新属性值 `debug.mks.gpu_timing=frame`（R1）/ `frame-span`（R2）。已核实现有
   三个属性读取者（mks_gpu_timer_init、LP gpu.c:309-313、VO 4432-4433）遇到
   这些值自动关闭；双读取残余风险靠日志门禁 + 属性读回挡住。
4. ≥10% 绑定：S0 层（fresh-copy、完整账本、同路由）每帧 T_f 的 Mcycles
   中位数；≥3 个 AB/BA 配对每对 ≥10%，且 ms 方向一致、A/A ≤3%（事先登记）、
   结构覆盖率 ≥95%、禁止类未覆盖事件为 0、闭合方程成立、跨口径 copy 校准与
   R1/R2 校准通过、B 侧 copy 段 ≥99% 目标尺寸。
5. 最高风险 R-1（设备）：tiler 延迟 resolve / dequeue 服务端等待落在段边界的
   归属，只能设备校准（R1 vs R2 Σ 差对照）。

## A. 查询所有权（owner 在 ra_ctx）

现状核实：mapper gpu_copy_timer 与 context gpu_yuv_timer 惰性读属性且各自 poll
DISJOINT（mks_gpu_timer.h:117,130）；LP 只认 `render`（gpu.c:309-337，非 render
强制 has_queries=false）；disjoint 标志 context 级共享读一次即清——两个读取者
互吃失效信号。LP 结果是滚动历史不能按帧认领（dispatch.c:1380,2386,1569；
vo_gpu_next.c:1087-1089）。

设计：owner 放 context_android 的 ra_ctx priv（现 gpu_yuv_timer 所处结构，
context_android.c:126），经 ra_ctx_fns 暴露（仿 yuv_fusion_begin/commit 接口
2064-2068）。mapper 经 mapper->owner->ra_ctx 访问（hwdec.h:40；hwdec_
surfacetexture.c:1398 有先例），不用 map_request 传 ticket（无 target 时根本
不传、map 后清零，hwdec.c:191-198——避免与 lease target 语义绑定）。

属性只在 ra_ctx init、context current 之后读一次，固定 mode；仅接受
frame/frame-span；其余值 owner 关闭。旧读取者按值互斥自动关闭[核实]；
yuv_compare 在任何非 0 计时值下拒绝启动（context_android.c:736-741）→
天然互斥[核实]。

生命周期：创建（读属性+EXT 检查+64 query 池，失败输出 supported=0 并关闭）→
开 ticket（vo draw_frame 的 start_frame 成功后，vo_gpu_next.c:3066 后，先 poll；
ticket={seq,gen,frame_id,pts,redraw/repeat/still,mix,fusion_token}）→ 渲染段
（pl_render_image_mix 前/返回后：fused 2660、普通 3363、seed 重试 3384；End 在
pl_gpu_flush 前 2675/3439）→ 回调挂起/恢复（hwdec_acquire 入口/各返回点；
hwdec_release 同）→ copy 段（draw_copy 现有 begin/end 位置 739-742）→
final-yuv 段（yuv_diag_final_pass 现有位置 ca:955-958，仅 split 路由）→
关 ticket（android_swap_buffers 的 eglSwapBuffers 前 ca:1776；出口分类
presented/abandoned/foreign）→ 回收（下次开 ticket 时 poll；全部终态才输出；
环满计 record_ring_full 不覆盖）→ 销毁（uninit poll，在途记 pending_drop）。

不变式 I1–I6：单一活动 query（Begin 前查 CURRENT_QUERY，外来记 foreign_query）；
只 poll 读 DISJOINT（读到则 epoch+1、在途作废、帧标 disjoint）；在途 query id
不复用；只 AVAILABLE 才取 RESULT，不 Flush/Finish/ClientWaitSync/FenceSync；
context 不一致只计数；无 ticket 时拒绝开段并计数（如 unticketed_copy）。

双读取消除：值互斥[核实] + I1 探测旧计时器活动 query + 采信门禁（同轮出现
MKS-GPU kind=*/MKS-GPU-SAMPLES/MKS-GPU-TIMER renderer/MKS-GPU-RENDER/MKS-GPU-PASS
任一则整轮作废；轮末属性读回必须仍为 frame*；新日志前缀 MKS-FGPU 避开旧
分析器正则 analyze_lg_p84_gpu_timing.py:32,38）+ mapper 重建重读属性的读回门禁。

LP client adapter：**不做**。渲染段框住整个 pl_render_image_mix 并扣回调，
LP 内 clear/blit/upload/mixing 全计入，覆盖面大于逐 pass；elapsed 不可嵌套。
未来逐 pass 归属另起设计交 Lead。

## B. 同帧区间定义

执行顺序[核实，fresh copy + fused 生产默认 ca:388-391、table 默认关
vo:4422-4430]：draw_frame → start_frame(3066)→[ticket+poll] → fusion_begin →
pl_queue_update → update_overlays → fusion_render → pl_render_image_mix(2660)
[渲染段开] → pass_init → hwdec_acquire[挂起] → mapper_map: release(1501)→
latch(1535)→draw_copy DrawArrays[copy 段]→publish fence(1689) [恢复] → LP 各
pass → pass_uninit → hwdec_release[挂起/恢复] → [渲染段关] → pl_gpu_flush(2675)
→ wait_until(vo.c:1022，CPU 睡眠) → flip → submit(FenceSync+Flush swapchain.c:
265-270) → swap_buffers[关 ticket] → eglSwapBuffers(ca:1776)。split 路由：渲染
写 offscreen→flush(3439)→swap 时 yuv_diag_final_pass[final 段]→eglSwapBuffers。

计入 T_f = Σ：render 段（含 LP 内部 clear/blit/upload/mixing、fusion fallback
重渲染、seed retry，带标记）、copy 段（与旧 input-copy 同区间）、final_yuv 段
（split）。同帧=同一 ticket 提交；内容身份另记（copy 段记 src_pts/latch_ts/
lease 尺寸，ticket 记 frame_id/pts）。

不计入但记账：release/latch/updateTexImage（挂起窗口内）、publish/retire/submit
fence 与 Flush（命令 GPU 开销可忽略[推断]）、retire_reap ClientWaitSync、
OSD/字幕上传（427-438；M2′ 轮要求 0）、无效帧紫屏(3436)、截图渲染（帧标
foreign）、mapper init 探测 copy（一次性，窗口外）、诊断回读/compare/atlas
（出现即整轮作废）、LP mixing cache 命中帧（标 lp_cache_hit）、mapper lease
复用帧（标 lease_reuse）、合成器（进程外，限制声明）、wait_until/eglSwap
阻塞（区间外——正是禁用外层 query 的原因）。

调度空洞：段内 CPU 卡顿 → 每段记 cpu_issue_ns，elapsed≈CPU 且超中位数标
possible_bubble，分析窗口避开预热（pts 20–55）。段内服务端等待（fused 渲染段
与 split final 段首次写 FBO 0 的 dequeue release fence）→ 风险 R-1，host 不可
验。校准 R2（frame-span）：copy 不单独成段，copy 起点连续到 LP 渲染仅等待点
挂起；R1/R2 同包同配置各一轮，Σ 差超 A/A 噪声则 R1 分项不可直接相加，交
Lead。可选第二期：GL_TIMESTAMP_EXT counter bits>0 时 ticket 开关各打一个
timestamp，span−Σ段 作段外上界标注（Adreno 支持性未核实）。

## C. 覆盖账本

每帧记录：身份 seq/gen/frame_id/pts/fusion_token；类型 copies/reuse/
lp_cache_hit/redraw/repeat/still/mix_frames/interpolated；路由 fused|split|
split_after_fusion_fail|invalid + seed_retry；每次 copy 记 src→lease 尺寸与
target_copy（兼作 B 侧小纹理消费证据）；每段 kind/epoch/cpu_issue_ns/
elapsed_ns/status（resolved|disjoint|pending_drop|refused:*）；未覆盖计数
overlay_uploads/mapper_reinit/latch_timeouts/reap_waits/foreign_work；呈现
presented/submit_ok/swap_ok/skipped_unfresh。

闭合方程（每 session + 每 10s summary 行）：
begin_attempts = issued + Σrefused；issued = resolved + disjoint_drop +
pending_drop + in_flight（final 时 in_flight=0）；tickets_opened = presented +
abandoned + foreign + open_at_uninit；copy 段 issued + unticketed_copy =
mapper fresh copy 计数（交叉核对 thermal lease_copy，surfacetexture.c:1628-
1631）；presented = context swap_ok（ca:1781-1784）。

覆盖率声明：结构覆盖率（gated）= 完整帧 / 窗口内呈现 fresh-copy 帧（完整=预期
段全 resolved、无 refused/disjoint/foreign/possible_bubble、未覆盖 0）；禁止类
未覆盖必须 0、允许类列出且注明不计时；busy 解释率 = Σ段时长/(窗口×busy%)
**只作参照非真值**（busy 含其他进程、时钟不同）。

分层：S0 主统计 = copies=1,reuse=0,lp_cache_hit=0,mix=1,route 同配置,redraw=0,
complete；S1=lease 复用帧；S2=LP cache 命中帧；S_all=每秒 Σ 段时长（最接近
能耗口径）；各层帧数闭合。

## D. 开关与零侵扰

默认关（属性非 frame* 时 owner 关闭；钩子只做指针/标志判断，不发 GL 调用；
每帧不读属性；非 Android ra_ctx 无此函数组）。不改 publish fence/flush 语义
（copy 段位置同旧 input；渲染段 End 在 pl_gpu_flush 前；fence 后 End 只是再
一条入队命令[推断]；不调 Finish/ClientWait/FenceSync）。不新增每帧同步（poll
只查 AVAILABLE；poll 放 start_frame 后，空命令流[推断]；Begin/End 不 flush
[推断]）。不动帧身份/退休契约（mapper 只加两个 owner 调用；VO 包装只加挂起
恢复，不改返回值与失败路径）。不动 A/V 时序（无 CPU 阻塞；CPU 开销=每帧一次
poll + 批量日志 <1KiB/行，A/B 两侧同担，需无计时 vs frame 的 A/A 给边界）。
query 边界放 FBO 切换处，尽量不切开 tiler render pass[推断，需设备 A/A]。

## E. host 测试策略（沿用提取+替身模式）

E1 owner 核心（新纯 inline 头，仿 mks_gpu_timer.h）：I1–I6、R1/R2 段轮转、
挂起/恢复配对、环满、disjoint 三时机、乱序就绪、uninit 在途/异 context、
GL 轨迹 Flush/Finish/ClientWait/FenceSync=0、DISJOINT 只在 poll、闭合方程。
E2 旧读取者不启用（真实 mks_gpu_timer_init + LP/VO 契约正则）。E3 mapper 接线
（真实 draw_copy/mapper_map/unmap + 假 owner）：copy 段严格包住 DrawArrays、
latch 后 fence 前；复用与全部失败路径不开段或成对关闭；**零侵扰**：开/关 frame
的 GL 轨迹去 query 与 owner 调用后逐条相同。E4 VO 回调（真实 acquire/release
+ 假 owner）：5 返回点挂起恢复成对；release 的 !hwdec_mapper 早退也恢复。
E5 draw_frame 契约（源码断言）：ticket 在 start_frame 后；三个 render 调用点
都有渲染段；End 在 flush 前；各出口 abandon；截图标 foreign。E6 分析器
（新 Python）：解析/闭合失败拒绝/旧计时器日志拒绝/属性读回拒绝/分层闭合/
配对统计/A/A 门槛。host 证明不了：Adreno elapsed 语义、dequeue 等待归属、
AVAILABLE 隐式 flush、计时扰动、TIMESTAMP 可用性、DVFS。

## F. 与历史口径关系

三旧模式（input/yuv/render）保持原样、按值互斥；历史 JSON limitations 与
share() 合成**保留为诊断参照**，不与新口径相加。跨口径校准：frame 模式 copy 段
= 旧 input-copy 同区间，同包同配置比 copy 段中位数（ms/Mcycles）与旧 input
（如 A-I1 5.83ms/1.248Mcycles[材料]），差值在 A/A 噪声内才算 owner 无扰动。
M2′ 报告：S0 每帧 T_f 中位数（Mcycles+ms）与分段中位数；覆盖账本全套；S1/S2/
S_all 辅助；上下文（频率按 mono_ns 对齐、busy、busy×频率、CPU%、帧率丢帧、
起温、路由分布、B 侧 lease 尺寸占比、APK md5、属性读回）；计时开销 A/A。

## G. 限制与验收线

仍非 GPU busy 真值：合成器与其他进程不计、驱动排队/binning/GMEM resolve 可能
段外[推断]、服务端 fence 等待可能段内（R-1）[推断]、DVFS（访存受限不按 1/f
缩放；A/B 频率本身随负载变[材料]）、query 开销。GPU 耗时≠功耗≠延迟≠热态。

≥10% 绑定：S0 层 T_f（Mcycles）中位数，pts 20–55 窗口；r=1−M_B/M_A；通过
条件（全部）：同 APK+同配置只切 lease、≥3 个 AB/BA 每对 r≥10%；ms 降幅≥0
（否则标 DVFS-confounded 不采信，定频需 root 未知）；A/A |r|≤事先登记上限
（建议 ≤3%，AB 前定死）；结构覆盖率 ≥95%、disjoint_drop ≤1%、禁止类 0、闭合
成立、无旧计时器日志、属性读回一致；跨口径 copy 校准与 R1/R2 校准通过；B 侧
copy 段 ≥99% 目标尺寸、A 侧源尺寸；起温门槛沿用。措辞："S0 层同帧可计时 GPU
区间（copy+render[+final]）的 Mcycles 中位数下降 r"；不得写"GPU 负载/功耗
下降"；S_all 不得回退（r≥0）否则不放行。

## 最高风险与实施切分

R-1 设备段边界归属（最高）；R-2 挂起/恢复不成对（host 可控，幂等状态机+穷举
返回点）；R-3 每帧 4-5 对 query 的计时扰动（A/A，超噪声退 R2）；R-4 属性中途
变化（门禁）；R-5 DVFS 背离（条件 2）；R-6 日志量/CPU（批量 <1KiB，闭合发现
丢行）。

实施切分：S1 owner 核心+host 测试（不碰生产调用点）→ S2 分析器+合成日志 →
S3 三处接线（context_android/mapper/VO）+E3/E4/E5 → **独立 critical 复审** →
S4 设备（冒烟→开销 A/A→跨口径 copy 校准→R1/R2 校准→A/A→≥3 AB/BA）。
回退：属性置空即全关。交 Lead 重议条件：R1/R2 Σ 差超噪、开销 A/A 超噪、
覆盖率 <95% 无因、counter bits=0 或 EXT 不可用、需逐 pass 归属。

---

# 修订版 r2（2026-11-08，对审查快照 35ce831f 的逐条处置）

> 状态：**修订版，待定向复审**（复审通过前不得进入 S1 实施）。r2 撤回"LP fork
> 零改动"：新增 `pl_opengl_params.mks_disable_timers` + `PL_HAVE_MKS_DISABLE_TIMERS`
> 宏 + 运行时探针（`pl_timer_create` 必须 NULL，否则 owner `supported=0`）。
> 以下为 r2 全文；与 r1 冲突处以 r2 为准。

## 0. 修订记录（逐条处置）

| 编号 | 处置 | 章节 |
|---|---|---|
| P0-1 | 方案 (a)+运行时证明：LP 参数禁用内部 timer；`gpu_next/context.c` 创建 LP 时传冻结 mode；探针验证；E2 能力矩阵 | A.2、A.3、E2 |
| P0-2 | ticket 四轴状态（测量/提交/呈现/回收）；全部接入点改包装函数（hwdec_acquire/release、三处 pl_render_image_mix、draw_frame/flip_page、android_swap_buffers）；逐出口转移表；swap 前只封闭测量；foreign=污损标志非互斥终态；E5 改真实函数提取 | B.3、C.1、E5 |
| P0-3 | copy 计数拆细（copy_calls/draw_submitted/draw_ok/ticketed/unticketed/publish）+ 每 copy 一条记录；不再用 thermal lease_copy 对照；接收端对账协议（唯一 id、批号、截止点、缺 FINAL 判不完整） | C.2、C.3、C.4 |
| P0-4 | R1/R2 各自显式状态机（R2：copy 起段 carried 到 resume 后不重复 Begin；acquire 失败保留 span 至 render_end；ticket invalid）；校准限同工作集合/分层/路由 | B.2、B.5 |
| P1-1 | 属性 init 冻结 + prop_now 每 10s/FINAL 校验；变化即整轮作废；撤回"置空即关"，回退需重建 VO/ra_ctx | A.2、A.4、D.5 |
| P1-2 | 措辞降级为"不新增显式等待/Flush、不移动删除现有 fence/Flush"；E3 轨迹对比扩展到 VO/context swap，逐条保留 fence/Flush | D、E3 |
| P1-3 | 旁路入口清单+检测（atlas render→unwrapped_render→整轮作废；compare arm 前改路由→owner armed=0；截图→unticketed 计数）；lp_cache_hit 观测=acquire 包装计数为 0；分层互斥分区（X-invalid/X-foreign/X-multi/X-seed/S0/S1/S2/X-other） | B.4、C.5 |
| P1-4 | G-1…G-11 参数冻结（A/A ≤3%；R1/R2 Δ≤3% + bootstrap CI ≤2%；扰动门；BOOTTIME 锚点对齐 + 零阶保持 + 可对齐率 ≥90%；bubble 判据 MAD×3；覆盖率 ≥95%；swap_ok ≥98%；S_all r≥0；G-9 主判据） | G |
| P2 | 行号校正（pl_gpu_flush 2678/3444；overlays 3145 先于 queue update 3177；release 1502） | 全文 |

审查确认保留：mapper/context timer 惰性读属性且 frame* 不启用；DISJOINT 读后即清；
`mapper->owner->ra_ctx` 路径；acquire 五返回点/release 早退；copy query 位置；
fusion 默认开；vo.c wait 语义；LP 滚动历史不可按帧认领。

## A. 所有权与 LP 禁用（r2 关键增补）

现状核实补充：LP `has_queries` 由能力检测决定，frame* 不清零（gpu.c:306-312，
utils.c:113-121）；LP pass timer 创建与日志开关无关（dispatch.c:1380）；LP
Begin/End 不检查 CURRENT_QUERY（gpu.c:730-762）→ 嵌套冲突可达。生产 pl_timer
唯一创建者是 dispatch.c:1380；`pl_timer_query(NULL)` 返回 0（gpu.c:1303-1306）。

owner 放 Android ra_ctx priv（context_android.c:126），经 ra_ctx_fns 暴露（仿
yuv_fusion 接口 2064-2068）；仅 VO 线程调用，跨线程计 wrong_thread 不执行。
属性 init 冻结为 off|frame|frame-span；冻结值驱动：LP 参数（context.c:213-229
params 构造处）、mapper 绕过旧 timer（mks_gpu_timer.h:162 只从 begin 进入 init，
mode!=off 时 draw_copy 只调 owner）、final-yuv 同、VO preinit 后强制
`p->gpu_timing=false`（4432 读于 context 创建前需事后覆盖）、compare arm 加冻结
门（context_android.c:736 读当前属性）。

LP fork 改动：L1 opengl.h 新参数+宏；L2 gpu.c:306-338 参数为真强制
has_queries=false/ext_queries=false 不读属性不加载 EXT 桥，输出
`MKS-GPU-TIMER renderer disabled-by-owner=1`，能力判断抽纯函数 `mks_gl_timer_caps`
便于 E2；L3 gl_timer_create 二层保险。缺宏时 owner 强制
`supported=0 reason=lp-cannot-disable`。运行时证明：pl_opengl_create 后
pl_timer_create 探针，非 NULL 即销毁并 `reason=lp-timer-live` 整轮作废。

生命周期：创建（冻结 mode、EXT/counter bits 检查、64 query 池、session id、
INIT 行）→ 启用（探针 NULL 且无 compare/atlas/table/frame-trace 诊断才 armed）→
ticket/poll → 销毁（uninit poll，在途 pending_drop，FINAL；context 不匹配只输出
不删除）。不变式 I1–I6 同 r1（I1 Begin 前查 CURRENT_QUERY；I2 只 poll 读
DISJOINT 且读后复读；I3 在途 id 不复用；I4 只 AVAILABLE 取 RESULT，不
Flush/Finish/Fence/Wait；I5 context 异只计数；I6 拒绝按原因计数）。

双读取者消除：结构消除（冻结值短路四个旧读取者 + LP 参数+探针）+ 证据门
（MKS-GPU kind= supported=1 / MKS-GPU-SAMPLES / EXT bridge enabled=1 /
MKS-GPU-RENDER / MKS-GPU-PASS / 缺 disabled-by-owner / lp_timer 非 null 任一
命中整轮作废）+ 新前缀 MKS-FGPU-*。prop_now 每 10s+FINAL 校验，变化即作废；
harness 是唯一属性写方，轮首尾 ADB 读回。

## B. 区间与状态机（r2 关键增补）

执行顺序[核实]：draw_frame → start_frame(3065-3066)→[ticket] → fusion_begin →
update_overlays(3145；OSD 上传 427-438) → pl_queue_update(3177；map 回调可触发
hwdec_reconfig 930→mapper init+probe draw) → fusion_render → pl_render_image_mix
(2660)[渲染段] → pass_init → acquire(renderer.c:3247-3254 先置 acquired) →
hwdec_acquire(797)：reconfig(807)→mapper_map：release(1502)→latch(1535)→
draw_copy DrawArrays(739-742)→ref(1652-1662)→publish fence+Flush(1689)→
publish(1707) → LP 各 pass（fused 最终 pass 写 FBO 0，2546-2556）→ pass_uninit →
release(878)→retire fence+Flush(1730)、满时 reap(1740→1281-1285) → [渲染段关] →
pl_gpu_flush(2678，仅 rendered) → commit(2718)；[fused 失败]→普通 render(3363)
[→seed 3384]→flush(3444)。vo.c wait_until(1022)。flip_page(3488)→submit(3517)→
swap_buffers(3540)→android_swap_buffers(1706)：[split final 1761-1762]→
eglSwapBuffers(1776)。draw/flip 恒成对（vo.c:1018/1026,1112/1113）。fused 失败
二次 render 的 acquire 经 mapper_unmap retire 后 retired_find adopt，不产生第二
copy [推断，E3 验证]。

R1 状态机：render_begin(k)（ticket open、active=none、susp=0 → Begin；
未开 ticket 计 unticketed_render，被拒照常渲染但 ticket 标 incomplete）→
suspend(acq)（render_entry≠0：End render 压栈；render_entry=0 有 ticket 标
foreign unwrapped_render；无 ticket 计 unticketed_acquire；栈非空 nested_suspend
标 incomplete）→ copy_begin（仅 measure=true 且确定提交 Draw；栈顶 acq、
active=none；否则 copy_outside_acquire/unticketed_copy）→ copy_end（Draw 后原
end 位置）→ resume(acq)（唯一包装出口覆盖五返回点；出栈；render_entry≠0 且栈空
Begin 新子段；active≠copy 未关则强制 End 标 incomplete）→ suspend/resume(rel)
（release 包装覆盖 !hwdec_mapper 早退 888-889；不允许 copy_begin）→
render_end(k,ok)（End+记录返回值；栈非空清栈标 incomplete）→ 二次 render（新 k，
标 fusion_fallback/seed_retry）→ draw_sealed（draw_frame 包装出口；之后
render/copy 拒绝）→ final_begin/end（ca:955-958；`!yuv_diag‖!ready` 早退记
final_absent）→ swap_sealed。acquire 失败：五返回点经同一包装出口 resume 必达；
LP acquire 失败后对已 acquired 帧调 release（renderer.c:3253 先置位）配对；
render_end ok=false，ticket invalid。

四轴状态：测量 open→draw_sealed→swap_sealed；提交 unset→not_called/ok/fail；
呈现 unset→swap_ok/swap_fail/swap_skipped:原因/no_swap:原因；回收 pending→
emitted/dropped:原因。ticket 只在 start_frame 成功后开（3066 后）；只有
eglSwapBuffers TRUE 记 swap_ok（含义=交给合成器，不代表已显示）；foreign=污损
位掩码与四轴正交，带位不进 S0–S2。

draw_frame 出口表（包装函数返回后读 p->frame_pending + compare_started|active 位）：
compare_fatal/compare_started 提前返回(2772,2778)→无 ticket 计 draw_no_ticket；
start_frame 失败(3066-3082)→无 ticket；PL_QUEUE_ERR(3180→done)→draw_sealed 无
渲染段，pending=flush_ok(3484)，invalid；compare_terminal/!a_ready(3350,3353→
3429)→foreign compare invalid；渲染失败(3392)→pending=true invalid；pre-flush
mismatch(3431-3432)→pending=false foreign compare；atlas postflush 失败(3464-
3465)→foreign atlas；正常(3484-3485)→按 C.5 分类。

flip_page 出口：包装出口结算；呈现轴 unset 填 no_swap:<最后 hook 原因>；提交轴
由 3517 单点 hook；无 ticket 计 unticketed_flip（若实际 swap 再计
unticketed_swap）。fusion 守卫且 !pending(3497)→not_called/no_swap:guard；
compare_fatal(3500)→foreign；pre-submit mismatch(3502-3504)→foreign；atlas
presubmit(3508-3511)→foreign；submit 失败有守卫(3517-3526)→fail/no_swap:
submit_fail；失败无守卫→由 swap 结算；atlas postsubmit(3533-3537)→ok/foreign；
swap_buffers(3540)→由 swap 结算。

android_swap_buffers 出口（hook：swap_issue 1776 前执行 swap_sealed；
swap_result 1776 后）：skipped-unfresh(1736-1746)→swap_skipped:unfresh；capture
非当前(1749-1753)/状态不符(1754-1760)→foreign；final 已执行但 capture 非
PENDING(1761-1766)→foreign capture_post_final；final 未 ready 仍 swap(889-890→
1770-1775)→final_absent，split 下帧不完整；eglSwapBuffers(1776)→swap_ok/fail。

回收：呈现轴结算且全部段终态时按 seq 输出；下一 ticket 开启时前一张呈现轴仍
unset 标 no_swap:unknown 计 presentation_unresolved（非 0 整轮作废）；uninit
时 open 的 ticket 记 dropped:uninit。

未计入但记账（P1-3 清单）：release/latch（挂起内，计次数）；fence+Flush（1689、
1730、swapchain.c:265-270）；reap 等待；OSD/字幕上传（427-438，3145 与 3223 两
处调用；S0 窗口内必须 0）；紫屏(3436，invalid)；mapper 重建与 probe draw
（807/930→913/1062 measure=false 不调 owner；ticket 内标 foreign mapper_reinit，
S0 排除）；atlas render(1793)与 atlas read consumer(impl:663)→unwrapped_render
整轮作废；compare arm 前改路由(2513-2519)→owner armed=0；截图(3824 渲染、
3839-3844 下载；通常 ticket 外[推断：控制命令在 render_frame 外处理，wait 不
处理控制命令]，ticket 内被 unwrapped_render 捕获)；seed 渲染(3363+3384)标 seed
S0 排除；诊断回读（构建门禁必须关）；合成器/他进程（限制声明）；wait/swap 阻塞
（段外）。P5 fast path 是参数变更仍走主 render；pl_frames_infer_mix 不调
acquire/render。

R2 状态机：仅一处与 R1 不同——copy 与 acquire 返回后的渲染之间不切段。
render_begin(k) Begin span；suspend(acq) End span（内部 release/latch 有 CPU
等待）压栈；copy_begin（栈顶 acq、active=none）Begin span 置 carried=1；
copy_end **不 End**（copy 记录写当前 span id）；resume(acq) 出栈后
carried=1 且 active=span 不重复 Begin，active=none（失败/复用/未 copy）Begin
span；acquire 失败但 span 已开：保留至 render_end，ticket invalid 不进 S0；
suspend(rel) End span 压栈；resume(rel) 出栈 render_entry≠0 Begin span；
render_end End 活动段；final 与 R1 同（隔 wait_until 无法连续）。R1 S0 帧=
[pre][copy][post][tail]，R2=[pre][copy+post][tail]；R2 span 跨过 publish Flush
(1689)。校准绑定：同 APK/同 lease/同路由(fused)、只 S0 层、统计量 S0 Σ段中位
数及分量 R1(copy+post) vs R2(span)、交替 R1/R2/R1/R2 四轮、门槛 G-2。

## C. 账本与对账（r2 关键增补）

ticket 字段：身份 session/t_seq/vo_frame_id/pts/fusion_token/issue_mono_ns；
四轴；foreign 位（compare/atlas/unwrapped_render/mapper_reinit/foreign_query/
nested_suspend/wrong_thread）；工作量 acquires/releases/copies_ok/reuse_served/
render_calls/render_ok_mask/mix_frames/route/seed；段列表 seg_idx/kind(render.k|
copy|span|final)/epoch/cpu_issue_ns/elapsed_ns/status；未覆盖计数
overlay_uploads/reap_waits/latch_timeouts。

copy 计数拆分：每 measure=true draw_copy 产生一条记录
（c_seq/t_seq|0/src_pts/src→lease/target_copy/outcome/seg_ref）；计数器
copy_calls、pre_draw_fail{fbo,program}、draw_submitted、draw_ok/draw_err、
ticketed/unticketed_draws、R1 copy_seg_attempt/issued/refused、R2
draws_in_span/draws_unspanned、publish_ok/fail{ref,fence}、段
resolved/disjoint/pending_drop/inflight。copy_begin 在 program 检查后
DrawArrays 前(739)。闭合方程（FINAL inflight=0；summary 只在其 through 截止点
内闭合）：(1) copy_calls=Σpre_draw_fail+draw_submitted=记录条数；(2)
draw_submitted=draw_ok+draw_err=ticketed+unticketed；(3) R1
ticketed_draws=attempt=issued+Σrefused，R2 ticketed=draws_in_span+Σunspanned；
(4) 每段 issued=resolved+disjoint+pending_drop+inflight，attempt=issued+Σrefused；
(5) draw_ok=publish_ok+Σpublish_fail；(6) 每 ticket copies_ok=该 t_seq
publish_ok 记录数；(7) tickets_opened=Σ呈现终值+dropped。thermal lease_copy
不再用于对照（1629-1631 受 thermal.enabled 门）。

接收端对账协议：INIT 行（session/mode/armed/reason/bits/lp_timer/prop/双时钟
锚）；ticket 批 MKS-FGPU-T session= b=批号 t=首..末 data=…（严格 t_seq 序、每行
<1KiB、暂存保证有序、暂存环满或等待 >32 张后续以 dropped:hol 显式输出）；copy 批
MKS-FGPU-C 同规则；summary 每 10s MKS-FGPU-S through_t/through_c/batches/
prop_now/双锚/全累计；FINAL complete=1|0 incomplete=原因。分析器拒绝规则：批号/
seq 重复缺失；明细重算与 summary 不等；FINAL 与明细不等；**缺 FINAL 判不完整**；
窗口内多 session；prop_now 不符；A.3 证据门命中。

分层（互斥、按优先级首中）：X-invalid（呈现非 swap_ok 或 route=invalid 或
incomplete）→ X-foreign（任一 foreign 位）→ X-multi（acquires>1 除 fallback
adopt、mix>1、interpolated）→ X-seed → S0（copies_ok=1、acquires=1、route=登记
值、完整）→ S1（copies_ok=0、acquires≥1、reuse_served≥1）→ S2（render_ok、
acquires=0、mix≥1；观测来源=owner 的 acquire 包装计数）→ X-other。各层帧数和
=ticket 总数。S_all=每秒所有 ticket Σ段。

## D. 开关与扰动（r2 措辞）

默认关：mode=off 时包装函数只分支判断，无 GL 调用，不读属性；非 Android ra_ctx
无此函数组。措辞：不新增显式等待（Finish/ClientWait/WaitSync）、不新增显式
Flush、不移动删除现有 FenceSync/Flush/DeleteSync/eglSwapBuffers；render 段 End
在 pl_gpu_flush(2678/3444) 前；copy 段同旧位置；Begin/End 命令本身入流，驱动
是否隐式 flush/拆分 tiler pass 未验证，由 G-3 扰动门约束。帧身份/退休契约：
mapper 只加 owner 调用与计数；包装不改返回值与失败路径。A/V：无 CPU 阻塞；
开销=poll+批量日志，G-3 约束。回退：属性冻结，清空不立即关——需清空后重建
VO/ra_ctx（force-stop 重启），以 INIT mode=off 或无 INIT、LP 无 disabled-by-
owner 确认。

## E. host 测试（r2 修订）

E1 owner 核心（纯 inline 头）：I1–I6、R1/R2 全转移（carried/失败/二次 render/
release/final/nested/未开 ticket）、DISJOINT 只在 poll、owner 不调
Flush/Finish/Fence/Wait、C.2(4) 闭合。E2 能力矩阵：LP 抽 `mks_gl_timer_caps`
纯函数 + gl_timer_create + owner 探针；矩阵 gles{0,20,30,32}×gl{0,30,33}×
ARB×EXT×属性{空,input,yuv,render,frame,frame-span,垃圾}×disable{0,1}；disable=1
强制 false 且不读属性；disable=0 与现 306-337 逐格一致（回归）；探针非 NULL→
armed=0 lp-timer-live；缺宏→lp-cannot-disable；旧 mks_gpu_timer_init 在 frame*
不分配 query；VO gpu_timing 强制 false；compare arm 拒绝。E3 mapper+轨迹：真实
draw_copy/mapper_map/unmap/init + 假 owner + 完整 GL 轨迹；每 measure 调用一条
copy 记录；C.2(1)(2)(3)(5) 在各失败路径成立；复用不开段；probe 不调 owner；
fused 失败二次 acquire 走 adopt 无 copy；轨迹对比 owner 开/关去 owner 调用后
GL 序列逐条相同（Fence/Flush/DeleteSync/ClientWaitSync 位置次数一致）。E4
acquire/release 包装：五返回点+早退配对，栈深归 0。E5 出口 harness：提取真实
flip_page/android_swap_buffers/yuv_diag_final_pass，compare/atlas 宏开关两种
编译，B.3 flip/swap 表逐行驱动，四轴终态一致；swap_ok 只来自 eglSwapBuffers
TRUE；final_absent；Fence/Flush 不增不减。E5b draw_frame：提取真实函数+可脚本
stub（pl_queue/render 结果脚本化）；B.3 draw 表逐行；三处 render 包装；二次
render；pending 一致。不可行回退：交 Lead 决定是否重构 ticket 结算为可单测小
函数，Worker 不得自行降级为纯正则。E6 分析器：C.3 全部拒绝规则、分层闭合、
G 节统计量。host 证明不了：Adreno elapsed 语义、tiler/服务端等待归属、查询
扰动、时钟对齐精度。

## F. 与历史口径关系（r2 同 r1 + 报告指标补齐）

三旧模式原样保留、冻结值互斥；旧 limitations 与 share() 合成只作诊断参照。
跨口径桥接：frame copy 段=旧 input-copy 同区间，中位数差 ≤G-2 阈值（参考
A-I1 5.83ms/1.248Mcycles）。M2′ 报告指标：S0 每帧 T_f 中位数（Mcycles+ms）与
分段中位数；结构覆盖率/未覆盖清单/对账结果；分层帧数 S1/S2/S_all；对齐后频率
/busy/busy×频率/CPU%；swap_ok 速率与丢帧；起温；B 侧 lease 消费比例；APK md5/
冻结 mode/prop_now；扰动 A/A 结果。

## G. 冻结验收参数（P1-4，跑数前冻结，事后不得放宽；修改须新数据前重新登记并
经 Lead 签字，已有数据作废）

G-1 A/A 上限：同 lease 配置两轮 S0 中位数差 Mcycles 与 ms 都 |r|≤3.0%，超限
该组全部无效查因重跑。G-2 R1/R2 与跨口径校准：Δ=med(ΣR2_S0)/med(ΣR1_S0)−1
要求 |Δ|≤3.0%；移动块 bootstrap（块长 1s，10000 次重采样，固定种子）95% CI
半宽 ≤2.0% 否则精度不足无效；跨口径 copy 中位数差 ≤3.0%；Δ 超限 R1 分项不得
相加交 Lead。G-3 扰动（无计时 vs frame 交替各 2 轮）：swap_ok 速率差 ≤1%；丢
帧差 ≤max(3,0.5%)；busy% 中位差 ≤3pp；频率中位差 ≤10%；进程 CPU% 差 ≤3pp；
任一超限 frame 模式无效交 Lead。G-4 时钟对齐：INIT 与每 summary 输出
(mp_time_ns, CLOCK_BOOTTIME) 锚对（osdep/timer.c:28-50、timer-linux.c:43-59
[核实]）；频率采样器用 /proc/uptime（sample_android_gpu_frequency.py:17-43
[核实]）；锚对线性拟合映射 issue_mono_ns→boottime；每帧取时间戳 ≤issue 的最近
频率样本（零阶保持）；距样本超 max(1.5×采样周期,1s) 的帧不可对齐；≥90% 帧可
对齐用逐帧 Mcycles，否则窗口中位频率并标注，两种都报。G-5 possible_bubble：
elapsed ≥0.8×cpu_issue 且 > 该类段 S0 中位+3×MAD 即 bubble，帧移出 S0；比例
>2% 该轮无效。G-6 覆盖与对账：结构覆盖率 ≥95%；disjoint_drop ≤1%；禁止类 0；
C.3 全过；presentation_unresolved=0。G-7 呈现硬门：每轮 swap_ok 速率 ≥98% 名义
帧率；配对内 A/B swap_ok 差 ≤1%，丢帧差符合 G-3。G-8 S_all 硬门：每配对
S_all_B ≤ S_all_A。G-9 主判据：pts 20–55 窗口 S0 每帧 Mcycles 中位数，
r=1−M_B/M_A；≥3 个 AB/BA 交错配对（离线计划生成），同 APK、同 sync、生产默认
配置（fusion 开 table 关）只切 lease；**每对 r≥10%**，ms 方向不得为负，否则
DVFS-confounded 不通过。G-10 lease 消费：B 侧 copy 记录 ≥99% 目标尺寸，A 侧
≥99% 源尺寸。G-11 热门禁沿用 matched-start 与起始温度门。

措辞："S0 层同帧可计时 GPU 区间（copy+render[+final]）的 Mcycles 中位数下降
r"；不得写"GPU 负载下降"或"功耗下降"。

## 最高风险与实施切分（r2）

R-1 设备段边界归属（最高；G-2 校准 + G-5 bubble）；R-2 E5b draw_frame 提取
工程量（不可行按 E5b 交 Lead）；R-3 每帧 4-6 对 query 扰动（G-3，超限交
Lead）；R-4 LP fork 参数需同步进入 libplacebo 与 mpv 隔离构建（缺宏强制
supported=0 不静默失效）；R-5 日志丢行（C.3 对账检测）；R-6 DVFS 背离（G-9
方向门）。

实施切分：S1 owner 核心头文件+E1（host）→ S2 LP 改动 L1-L3 + mks_gl_timer_caps
+ E2 矩阵（host，S3 前置）→ S3 分析器+E6（host）→ S4 全部包装与接线
（context/mapper/VO/gpu_next-context）+E3-E5b → **独立 V2 critical 复审** →
S5 设备（冒烟→G-3→G-2→G-1→G-9）。需要重交 Lead 的条件：G-2/G-3 超限；覆盖率
<95% 无因；counter bits=0 或 EXT 不可用；E5b 不可行；需逐 pass 归属。普通失败
只修对应切片。

---

# r3 增量修订（2026-11-08，对 r2 复审 P0-A/B 与 P1 的处置）

> 状态：**待第三轮定向复审**（只核查 r3 增量）。未列出的章节沿用 r2。
> 新增源码引用已由 specialist 复核：vo_gpu_next.c 1430-1456/1755/2500-2505/
> 2560-2561/4398-4401、yuv_atlas_read_impl.h 614、ra_pl.c 641-651、LP renderer.c
> 3247-3272/3358-3399/3818-3873、lg_p84_thermal_round.py（4127f52d…）。

## 0. r3 修订记录

P0-A1：**唯一方案——配置了 compare/atlas 时 owner 不 armed、不建 ticket**（依据：
compare_started/active 只在 compare_this_frame 置位、要求 compare_enabled(2502)、
atlas/reuse 并入 compare_requested(4399-4400)；armed 时 compare_fail_transaction
不可达[推断]）。两处提交点（1443 submit、1447-1449 abort_no_gl）改为**不变式
探测**：只记录 session 级事实（compare_submit{ok,fail}/abort_no_gl{closed,open}）
并置 invariant_violation=compare-path 整轮作废，不参与 ticket 记账、不用 foreign
改写记录。E5 在此前提下验证。
P0-A2：draw 表拆分 compare_terminal(3349-3350→3428-3429) 与
`compare_active && !compare_a_ready`(3352-3353→done，不一定 terminal)——armed
时均不可达；提交轴只由真实提交调用结果写一次，之后任何事件不改写。
P0-A3：flip/swap 包装增加确定性收口规则（见 B.3-r3），不新增 hook。
P0-B1：呈现轴（7a）与回收轴（7b）分别闭合，跨轴不相加。
P0-B2：HOL 冻结行为——非终态段记 `hol_drop`、query 入隔离区仍占槽（I3）、poll
时 AVAILABLE 则读后丢弃计 late_discarded、DISJOINT 则释放槽位；**迟到结果绝不
写入已输出记录**；seg_ref 校验；hol_drop 不进 S0，G-6 计入未知时长、G-8 保守
填补。
P1-C1：通用 End 规则——仅当段由 owner Begin、Begin 后 CURRENT_QUERY 等于该段
id、当前 context 匹配三者同时成立才发 EndQuery；Begin 被拒后 active 保持 none，
copy_end/resume/render_end 不发 End 只计数；context 不符记 ctx_lost 保留槽、
session 作废。R1/R2 acquire 失败：不另切段，LP 依次 goto error→pass_uninit→对
已置 acquired 的帧 release（renderer.c:3253,3265-3272,3396-3398），release 包装
正常转换，render_end(ok=false)，ticket acquire_fail=1 invalid；R2 carried span
在 suspend(rel) 时 End。r2"resume 时强制 End 标 incomplete"作废。
P1-C2：校准协议冻结——R1a→R2a→R1b→R2b 交替；配对 P1/P2 **各自过门**（合并仅
报告）；总量门 |Δ|≤3.0%（ms 与 Mcycles 都要）；分量门 R1(copy+紧随 render 子段)
vs R2(span) |Δc|≤5.0%（硬门）；bootstrap 块长=round(nominal_fps×1s) 帧、10000
次、种子 20261108、百分位法 95% CI 半宽 ≤2.0%；R1a vs R1b 满足 G-1；跨口径
|med_copy(frame)/med_copy(input)−1| ≤3.0%。
P1-C3：旁路入口直接记账/拒绝——atlas_render(1748)/atlas_consumer_render(impl
~600-680)/compare arm(2560-2640) 入口调 owner.bypass()，armed 时进入即
invariant_violation（**不依赖 acquire 检测**，atlas 可能全命中 LP 缓存
renderer.c:3818-3873）；video_screenshot(3648) 入口 bypass(screenshot) 计
screenshots+1、open ticket 置 foreign（软件帧截图不经过 hwdec acquire）；新增
`hw_frames` 字段（ticket 内 fp->hwdec 非空帧数），`hw_frames<mix_frames` 归
X-other（软件帧不冒充 S2）；pw-configure 未定位——S4 前置项，未定位前不得开始。
P1-C4：对齐算法唯一、A/B 相同、无回退：锚点最小二乘，有效性=|残差|≤2ms、斜率
1±1e-4、相邻锚 Δboottime−Δmono ≤50ms（暂停跳变），任一不满足该轮无效；样本距
issue 超 max(1.5×中位采样间隔,1s) 记不可对齐；S0 不可对齐 >10% → **该配对主
验收数据不足**（窗口中位频率只作辅助，不作替代）；≤10% 时主统计只在可对齐 S0
子集计算（两种单位同分母），全量 ms 作敏感性报告；指标名固定为
**issue-time 频率归一化代理**。
P1-C5：bubble 单次分类程序——段类型 render.pre/copy/render.post/render.tail/
span/final；候选集 C_k=满足 S0 全条件（bubble 条除外）中类型 k 且 resolved 的
段，|C_k|<200 该轮无效；对 C_k 一次算中位 m_k 与原始 MAD_k（下限
max(MAD,0.01×m_k,1000ns)），τ_k=m_k+3×MAD_k；每段只分类一次：elapsed≥0.8×
cpu_issue 且 >τ_k 判 bubble；任一段 bubble 则 ticket 移出 S0；bubble 比例>
2% 该轮无效；敏感性对照保留 bubble ticket 重算 r，符号不同或差 >3pp 标
bubble-sensitive 交 Lead。
P1-C6：G-3 基线改为新增 `frame-count` 模式（owner armed、出全套记录、LP 禁
用、**从不发 GL query**、段记 not_timed）与 frame 交替 2+2 轮；丢帧差分母
N_ref=基线轮窗口内唯一源帧呈现数，阈值 max(3,⌈0.005×N_ref⌉)；G-7 名义帧率=
窗口内 copy 记录 nominal_fps 众数（须有限>0 且 A/B 相同），唯一源帧呈现速率=
swap_ok ticket 的不同 pts 数/窗口 pts 跨度，重复呈现计 repeat_presents 单独
报告；G-11 阈值原值取自 lg_p84_thermal_round.py（batteryC≥45、vtsC≥48.5、
30s hot≥1；matched-start ±0.5/±1.0、cooldown 1800s）并以文件当前版本为准、
哈希变化须重新登记；C.5 S0 显式条件；S_all 未知时长不按零计。
P1-C7：A/V 措辞改为"不新增显式 CPU 等待；query 命令可能引起的驱动侧延迟或
调度变化不作保证，由 G-3 设备扰动门评估"。
D1：措辞改为"GL backend 上 pl_timer_create 一律经 impl->timer_create=L3"；审计
清单：dispatch.c:1380（生产可达）、ra_pl.c:641-651 get_active_timer（仅 RA
timer_start 触发，gpu-next/mapper grep 无调用[推断]，经 L3 亦得 NULL）、LP
tests/bench（非生产）、upload/download timer 参数（mpv 不传[核实]）。
D2：探针 NULL 不能单独证明禁用成功（MAKE_CURRENT 失败同样 NULL，gpu.c:626）；
启用需四项证据同时成立：(i) 构建检测到 PL_HAVE_MKS_DISABLE_TIMERS（receipt
含 LP 源版本）；(ii) INIT 行 lp_disable_param=1；(iii) 同进程 LP 日志有
disabled-by-owner=1 且无 EXT bridge enabled=；(iv) 探针 NULL 且探针前后
eglGetCurrentContext 均为 owner context。缺一整轮作废。

## B.3-r3 四轴写入规则与出口表（armed session 专用）

armed 时 compare/atlas 路径不可达（A.2-r3）；若实际执行由不变式探测整轮作废，
不在 ticket 层打补丁。四轴：测量 open→draw_sealed→swap_sealed（只前进，封闭后
Begin 请求拒绝计 after_seal）；提交 unset→ok/fail/not_called（只写一次）；呈现
unset→swap_ok/swap_fail/swap_skipped:原因/no_swap:原因/unset_uninit（只写一
次；swap_ok 仅指 eglSwapBuffers TRUE，不代表已显示）；回收 normal/hol/uninit
（输出时写，每 ticket 恰一次）。

draw_frame 出口（armed 时）：compare_fatal/compare_started 提前返回(2772,2778)
不可达；start_frame 失败(3066-3082)→无 ticket 计 draw_no_ticket（随后的 flip
计 unticketed_flip）；PL_QUEUE_ERR(3180→done)→draw_sealed 无渲染段，
pending=flush_ok(3484)，invalid；compare_terminal(3349-3350→3428-3429) 不可
达；`compare_active&&!compare_a_ready`(3352-3353→done) 不可达；渲染失败
(3392→done)→draw_sealed，pending=flush_ok，invalid；pre-flush mismatch
(3430-3432) 不可达；atlas postflush(3463-3465) 不可达；正常(3484-3485)→
draw_sealed，pending=flush_ok。

flip 收口（包装入口记 entry_pending/guard，出口按序判定，不新增 hook）：无
ticket→若 swap 包装运行过计 unticketed_swap，结束；测量未到 swap_sealed→置
swap_sealed；提交 unset→not_called；呈现 unset 按序取首中：提交 fail 且 swap
未运行→no_swap:submit_fail；提交 not_called 且 entry_pending=false 且
guard=true→no_swap:guard_unpending(3497)；其他→no_swap:unexpected + 
invariant_violation=flip-path（armed 时剩余提前返回 3500/3503/3510/3535 均为
compare/atlas 出口，应不可达[推断]）。

swap 包装收口：入口记 skipped0=fusion_skipped_swap；swap_issue(1776 前)→
swap_sealed；swap_result(1776 后)→swap_ok/fail；出口呈现仍 unset：
fusion_skipped_swap>skipped0→swap_skipped:unfresh(1736-1746)；否则
swap_skipped:unexpected + invariant_violation=swap-path（armed 时 capture 相关
返回点 1749-1766 不可达[推断：capture.id 只由 compare arm 设置]）。split final
未 ready(889-890→1770-1775)→final_absent，ticket 不完整（不影响提交/呈现事
实）。ticket 交替规则：开新 ticket 时上一张呈现仍 unset→no_swap:unexpected +
invariant_violation=no-flip（draw/flip 恒成对 vo.c:1018/1026,1112/1113[核实]）。

## C.2/C.3-r3 方程与 HOL（关键替换）

7a：tickets_opened = n(swap_ok)+n(swap_fail)+Σn(swap_skipped:*)+Σn(no_swap:*)+
n(unset_uninit)。7b：tickets_opened = n(normal)+n(hol)+n(uninit)=ticket 记录
条数。两轴独立闭合，同一 ticket 两轴各计一次。8：copy 记录 seg_ref 必须在对应
t_seq 的段列表中存在且类型匹配（R1=copy、R2=span、frame-count=not_timed、未开
ticket=0），否则对账失败。

HOL 冻结行为：触发=呈现已结算但其后 32 张 ticket 仍有段未终态、或暂存环满；
终结=非终态段记 hol_drop、reclaim=hol、按 seq 输出；隔离=query id 仍占槽(I3)，
poll 时 AVAILABLE 读后丢弃计 late_discarded、DISJOINT 释放槽位，迟到结果绝不
入账；槽耗尽→refused:ring_full；uninit 隔离余量计 pending_drop 后删除；用途=
hol_drop 不进 S0，G-6 未知时长门、G-8 保守填补。

## C.5-r3 S0/S2 条件（替换 r2 对应两行）

S0 同时满足：hw_frames=mix_frames=1；redraw=repeat=still=0；interpolated=0；
acquires=1、acquire_fail=0、copies_ok=1；route=登记路由（fused）；无 seed 与
fusion_fallback；无 foreign 位、reclaim=normal；全段 resolved、无 final_absent、
无 bubble（G-5-r3）；呈现=swap_ok。S2：hw_frames=mix_frames≥1、acquires=0、
render 成功、呈现=swap_ok（软件帧经 hw_frames 排除）。

## E/E5、G、风险与切分增量

E1 追加：外来 query 时 copy_begin 拒绝后 End 次数=0；context 不符不发 End 记
ctx_lost；R1/R2 acquire 失败全序列（suspend(acq)→resume→suspend(rel)→resume→
render_end(false)）验证 carried 与 invalid；HOL 触发/隔离/迟到丢弃且已输出记录
逐字节不变；frame-count 下 GL query 调用=0。E5 追加：(a) compare/atlas/table/
fault 任一为真→armed=0、owner 调用 0、无 ticket；(b) B.3-r3 每个可达行驱动一
次、四轴终态一致、提交轴二次写入尝试=0；(c) 人为调 compare_fail_transaction→
先前 ticket 事实不变、session invariant_violation、1443/1448 事实分别记录；
(d) flip 收口每分支覆盖；(e) swap skipped0 差值判定覆盖。

G-2：R1a→R2a→R1b→R2b；P1/P2 各自过门（合并只报告）；R1a vs R1b 满足 G-1；
总量门 |Δ|≤3.0%（ms+Mcycles）；分量门 |Δc|≤5.0%；bootstrap（块长=round
(nominal_fps)帧、10000 次、种子 20261108、百分位 95% CI 半宽 ≤2.0%）；跨口径
|比值−1|≤3.0%。G-3：基线 frame-count 与 frame 交替 2+2；唯一源帧呈现速率差
≤1%（G-7 定义）；丢帧差 ≤max(3,⌈0.005×N_ref⌉)；busy ≤3pp；频率 ≤10%；CPU
≤3pp；off 与 frame-count 差异只报告不设门。G-4：单算法无回退；锚点有效性
（残差 ≤2ms、斜率 1±1e-4、Δboottime−Δmono ≤50ms）；不可对齐 >10% 判数据不
足；≤10% 主统计只在可对齐 S0 子集（两单位同分母），全量 ms 作敏感性；指标名
issue-time 频率归一化代理。G-5：单次分类（C_k 构建→一次阈值→一次分类）、
|C_k|<200 无效、MAD 下限、2% 门、敏感性对照。G-6：覆盖率 ≥95%、未知时长
ticket ≤1%、禁止类 0、对账全过、invariant_violation=0。G-7：名义帧率=nominal_
fps 众数、唯一源帧呈现速率=swap_ok 不同 pts 数/跨度、≥98%、A/B 差 ≤1%。
G-8：S_all=已知段+未知段保守填补（B 取层内最大、A 取 0）硬门 S_all_B≤S_all_A，
中位填补点估计一并报告；前提未知比例 ≤1%。G-11：batteryC≥45、vtsC(thermal_
zone39)≥48.5、30s hot≥1；matched-start ±0.5/±1.0、cooldown 1800s；以
lg_p84_thermal_round.py 当前版本为准、哈希变化须重新登记。

新增风险：R-7（armed 前提依赖"不配置 compare 时 compare 路径不可达"的推断，
E5(a)(c) 验证、设备 invariant_violation=0 硬门）；R-8（pw-configure 未定位，
S4 前置项）。切分增量：S1 加 HOL/隔离/frame-count；S3 加 G-2/G-4/G-5/G-8 冻
结程序与固定种子；S4 加提交包装、flip/swap 收口、截图与 atlas 入口记账。

---

# r4 增量修订（2026-11-08，对第三轮复审 HOL 双账 P0 与三项 P1 的处置）

> 状态：**待第四轮定向复审**（只核查 r4 增量）。未列出章节沿用 r3。新增源码
> 引用：ra_pl.c 199-239/608/641-651/674（43570c83…）、gpu/video.c timer_pool_*
> 调用方 3033/3537/3774、context_android.c 1781-1784。

## 0. r4 修订记录

r3-P0-A 措辞：测量轴封闭语义——draw_sealed 后 render/copy/span 的 Begin 拒绝
（refused:after_seal），**split final 仍可 Begin**；swap_sealed 后所有 Begin 拒绝
（final 也计 refused:after_seal）；fused 路由无 final 不受影响。B.3 与 E1 同步。
P0（HOL 双账）：段逻辑账本与 query 资源账本彻底分离（见 C.2.1-C.2.3）；方程⑷
按逻辑账本重写（⑷a/⑷b），hol_drop 成为逻辑终态，uninit 不再改写；资源账本单独
闭合；X1–X6 交叉恒等式 FINAL 逐项核对；seg_ref 改为"非 0 当且仅当指向该 ticket
明细中已存在的逻辑段"，pre_draw_fail/Begin 被拒/R2 未入 span 三种情形给出编码
与 timer 字段。P1-a：速率分母改设备 monotonic 实际经过时间，PTS 只选窗；PTS
密度单独作覆盖指标。P1-b：G-8 冻结第 3 方案——窗口内存在未知时长即判"证据不
足"（不判通过也不判失败），最大值填补只作辅助报告；撤回 r2/r3"经验最大值即保
守上界"；两侧未知均为 0 时 G-8 才作硬门；超半数配对证据不足交 Lead。P1-c：新增
off→frame-count 与 off→frame 两组外部指标硬门（阈值同 G-3）；未执行或未通过须
声明"整体计时扰动未被限制"，G-9 不得放行。小项：G-5 分母=bubble ticket/候选
ticket（非段数）、空段类型跳过样本量门；D1 限定 gpu-next 路径（ra_pl.c:208/234
确实传 get_active_timer，即便调用也被 L3 置 NULL）。

## C.2.1-r4 段逻辑账本

逻辑段两类结果：拒绝（refused:原因，不产生 query、不写 ticket 明细、只累加
summary）；接受（逻辑段 id=(t_seq,seg_idx)，无 ticket 不接受任何请求 I6）。接受
的段分 issued（R1/R2，已 Begin 绑定物理槽）与 not_timed（frame-count，无槽）。
**issued 恰好落入一个逻辑终态**：resolved（poll 读到结果）/disjoint（poll 观察
到标志，段仍在正常在途）/pending_drop（uninit 时正常在途且 context 匹配）/
hol_drop（触发 HOL）/ctx_lost（uninit 或 End 时 context 不匹配 I5，session 无
效——审查四终态之外补充）。方程⑷：⑷a attempt_k = issued_k + not_timed_k +
Σrefused_k；⑷b issued_k = resolved_k + disjoint_k + pending_drop_k + hol_drop_k
+ ctx_lost_k + inflight_k（FINAL inflight_k=0；inflight 指正常在途；hol_drop 不
论物理槽是否占用不计 inflight）。

## C.2.2-r4 query 资源账本

物理槽 R=64 init 一次分配；任意时刻 R = free + busy_normal + busy_quarantine。
计数器：bind（每次 Begin 成功）；释放按 6 原因：rel_result、rel_disjoint_normal、
rel_late（隔离区读到结果后丢弃，即 r3 late_discarded）、rel_disjoint_quarantine、
rel_uninit_normal、rel_uninit_quarantine；另 leak_ctx（uninit context 不匹配不删
query，照 mks_gpu_timer.h:191-200 惯例）。资源闭合：bind = 六种释放 + leak_ctx +
busy_normal + busy_quarantine；FINAL context 匹配时 busy=0 且 free=R，不匹配时
free + leak_ctx = R。HOL 后的迟到回收与 uninit 清理只动资源账本，不改逻辑终态、
不增加逻辑 pending_drop。

## C.2.3-r4 交叉恒等式（FINAL 逐项核对）

X1 Σissued_k = bind；X2 Σresolved = rel_result；X3 Σdisjoint =
rel_disjoint_normal；X4 Σpending_drop = rel_uninit_normal；X5 Σhol_drop =
rel_late + rel_disjoint_quarantine + rel_uninit_quarantine + busy_quarantine
（FINAL 最后一项 0；context 不匹配时隔离槽计入 leak_ctx）；X6 Σctx_lost =
leak_ctx_normal（FINAL 分开输出 leak_ctx_normal 与 leak_ctx_quarantine，X5 右边
加 leak_ctx_quarantine）。分析器重算范围：逻辑账本从 ticket 明细 + summary
refused 重算⑷a/⑷b 与 summary/FINAL 完全一致；资源账本只用 summary/FINAL 核对
闭合式与 X1–X6（明细不记录槽位事件）；任一不一致判对账失败。

## C.2.4-r4 seg_ref 编码（替换方程⑻）

规则：seg_ref≠0 当且仅当指向本条 copy 记录 t_seq 对应 ticket 明细中已存在的逻
辑段；不写明细的拒绝与未发起请求编码为 0，timer 字段写明原因。表：pre_draw_fail
（739 开段位置之前，未发起请求）→ timer=none:pre_draw、seg_ref=0；R1 开段被拒
（任何原因含 no_ticket/after_seal/foreign_query/ring_full/copy_outside_acquire）
→ refused:原因/0；R1 开段被接受（含 Draw 后 GetError 报错 outcome=draw_err）→
seg/段 id（类型 copy）；R2 Draw 时 span 活动（draws_in_span）→ seg/span id；R2
无活动 span 且开段被拒（draws_unspanned）→ refused:原因/0；frame-count → seg/
not_timed 段 id；无 ticket → refused:no_ticket/0。方程⑻-r4：seg_ref≠0 的记录
指向的段存在于同 ticket 明细、类型与模式匹配、t_seq>0；R1 ticketed_draws =
n(timer=seg) + n(timer=refused:*,t_seq>0) 且每 ticket n(timer=seg)=该 ticket
copy 段数；R2 draws_in_span = n(timer=seg)、Σunspanned = n(refused:*)；全模式
n(timer=none:pre_draw) = Σpre_draw_fail。

## E1-r4 追加

封闭语义：draw_sealed 后 render/copy/span Begin 返回 refused:after_seal 且
BeginQuery 次数 0，final Begin 被接受（R1/R2 都测）；swap_sealed 后 final 也拒
绝；fused 全程无 final 请求。HOL 后 uninit 两本账分别闭合：构造 T1 触发 HOL
（逻辑 hol_drop、槽进隔离区）→ 一个隔离槽 available（rel_late）、一个 disjoint
回收（rel_disjoint_quarantine）、一个留到 uninit（rel_uninit_quarantine）；T2 一
段 uninit 时正常在途（逻辑 pending_drop、资源 rel_uninit_normal）。断言：⑷a/
⑷b/资源闭合/X1–X6 全部成立；T1 已输出明细逐字节不变；逻辑 pending_drop 只含
T2 的段。context 不匹配的 uninit 再测：leak_ctx_normal 与 leak_ctx_quarantine
分开计数，X5/X6 成立。seg_ref 编码至少覆盖：(a) pre_draw_fail→none:pre_draw/0；
(b) R1 外来 query 拒绝→refused:foreign_query/0 且 EndQuery 次数 0；(c) R2 无
span 且开段被拒→refused:*/0；(d) R1 draw_err→seg/id 且段进入某逻辑终态；(e)
R2 carried span→span id；(f) frame-count→not_timed id；(g) 无 ticket→
refused:no_ticket/0。

## A.2-r4 D1 段替换

ra_pl 的 upload/download：ra_pl.c:208 与 :234 把 get_active_timer(ra) 填入
pl_tex_transfer_params.timer [核实]；get_active_timer 只在 active_timer 非空时
创建/返回（641-651），active_timer 只由 RA timer_start（608、674）设置；
video/out 中 timer_pool_* 调用方全在旧 gpu/video.c（gl_video 3033/3537/3774），
gpu-next 的 VO 与 mapper 无调用方 [核实 grep；"gpu-next 不会走到"属推断]；即便
走到 pl_timer_create 也经 L3 返回 NULL。措辞：撤回 r2/r3"mpv 侧不传 upload/
download timer"，改为"gpu-next 路径中 ra_pl 传入的 timer 为 NULL[推断]，且任何
经 GL backend 创建的 pl_timer 都被 L3 置 NULL"。

## G-r4（替换 r3 的 G-3/G-5/G-7/G-8；G-1/G-2/G-4/G-6/G-9/G-10/G-11 沿用 r3）

通用窗口定义（G-3/G-7 共用）：PTS 选窗（pts∈[20,55] 的 ticket 集 W）；设备经过
时间 D = issue_mono_ns(W 末) − issue_mono_ns(W 首)，owner 的 mp_time_ns
（MONOTONIC_RAW）。off 模式不输出 ticket：D 和 W 从 harness 同一套外部采样取
（busy%/频率/CPU% + thermal trace 的 swap/swap_ok 计数与 mono 时间
context_android.c:1781-1784）；外部门禁速率一律按外部来源计算（三模式口径一
致）；owner ticket 数据只用于 frame-count 与 frame 之间比较。thermal trace 能否
给出窗口内计数与时间未核实——实施前确认给不出则转交 Lead，不得改用别的口径。

G-3：G-3a frame-count↔frame 交替 2+2（隔离 query 本身影响；数据=owner ticket +
外部采样；硬门：唯一源帧呈现速率差 ≤1%、丢帧差 ≤max(3,⌈0.005·N_ref⌉)（N_ref=
frame-count 轮窗口内唯一源帧呈现数）、busy% 中位差 ≤3pp、频率中位差 ≤10%、
CPU% 中位差 ≤3pp；未过→frame 无效交 Lead）。G-3b off↔frame-count 交替 2+2
（owner 记账与日志影响；只用外部采样；阈值同上，N_ref 取 off 轮外部 swap_ok
数；未执行或未过→声明"整体计时扰动未被限制"，G-9 不得放行）。G-3c off↔frame
（由 a/b 四轮组合直接得到，不另跑；只用外部采样；同 G-3b 后果）。速率 rate =
(n−1)/D，A/B 同公式。

G-5（修订第 2/5 步）：第 2 步只对 C_k 非空的段类型执行 |C_k|<200 检查，空类型
跳过（各路由必需段类型是否齐全由 C.5-r3 S0 定义保证）；第 5 步 bubble 比例 =
bubble ticket 数/候选 ticket 数（满足 S0 全条件不含 bubble 的 ticket），分子分
母都按 ticket 计数，>2% 该轮无效。

G-7：名义帧率沿用 r3（copy 记录 nominal_fps 众数）。主指标 = (n_unique−1)/D
（n_unique = W 中 swap_ok ticket 的不同 pts 数；D 按通用窗口定义）。硬门：每轮
主指标 ≥0.98×名义帧率；配对内 A/B 差 ≤1%。PTS 覆盖与丢帧指标（分开）：pts 覆
盖 = max_pts−min_pts（已呈现唯一源帧，应接近 35s）；pts 密度 = n_unique/覆盖；
pts 缺口 = 相邻唯一 pts 间隔 >1.5/nominal_fps 的次数——三项都报告，覆盖
<34.5s 判该轮无效（防窗口截断），密度与缺口只作丢帧诊断不设门。repeat_presents
沿用 r3。

G-8（冻结第 3 方案）：W 中任一 ticket 含未知时长段（disjoint/pending_drop/
hol_drop/ctx_lost，或拒绝发生在 copy/render 位置且有实际 GPU 工作未计时——
refused:*）→ 该配对 G-8 判"证据不足"（不通过不失败）；此时 S_all 只作辅助报
告（已知部分之和 + 同层同类段最大值填补），**填补不构成上界**（撤回 r2/r3 说
法）；只有 A、B 两侧未知时长 ticket 都为 0 时 G-8 才作硬门：S_all_B ≤ S_all_A
（按秒归一化，分母 D）。配对放行：G-8 证据不足时只依 G-9 及其他各门，报告明示
"S_all 未验证"；全部配对中超过一半证据不足→交 Lead，不得宣告完整口径放行。

## 风险与切分增量（r4）

R-9：G-3b/G-3c 依赖 harness 外部采样在 off 模式给出窗口内 swap 计数与时间——
未核实，S5 前置项；给不出则按 G-3b 声明"整体计时扰动未被限制"。切分：S1 加两
本账、X1–X6、C.2.4 编码、E1-r4 第 1–3 项；S3 加逻辑账本重算、资源账本核对、
⑻-r4、设备经过时间分母、G-7 覆盖门、G-8 第 3 方案判定与超半数升级；S5 顺序：
冒烟 → G-3a/G-3b → G-2 → G-1 → G-9。交 Lead 新增：G-8 证据不足配对超半数；
off 模式外部采样口径无法满足 G-3b。

---

# r5 增量修订（2026-11-08，对第四轮复审 ctx_lost P0、E1 构造与三项 P1 的处置）

> 状态：**待第五轮定向复审**（只核查 r5 增量）。未列出章节沿用 r4。新增源码：
> gpu/shader_cache.c 933-936/1018-1021/1046-1049、opengl/ra_gl.c 1140-1190、
> mks_gpu_timer.h 117-121/129-136。

## 0. r5 修订记录

P0（ctx_lost）：采用审查建议最简策略并冻结——**观察到 context 不匹配即永久停
机**（timing∈{running,halted_ctxlost} 单向不可逆）。停机转移一次性完成（不调
GL）：全部已 issued 未终态段（含活动段）逻辑终态记 ctx_lost；其槽从 busy_normal
转 **busy_ctxlost**；busy_quarantine 保持（段已 hol_drop 不再改）；已输出 ticket
不改写；session halted=ctx_lost 整轮作废。停机后：Begin 全拒计 refused:ctx_lost、
poll 不执行计 poll_skipped_halted（不读 DISJOINT/结果/不收割）、End 不发（context
恢复也不发）、记账照常（段一律 refused）保证账本闭合与 FINAL 完整。uninit 表：
匹配→CURRENT_QUERY 核实是 owner 自己的 query 才发唯一一次 EndQuery（计
uninit_end，结果丢弃），DeleteQueries(R)，绑定账 busy_normal→rel_uninit_normal
（逻辑 pending_drop 仅未停机可能出现）/busy_quarantine→rel_uninit_quarantine/
busy_ctxlost→rel_uninit_ctxlost，gl_deleted=R；不匹配→先停机再 leak_ctxlost/
leak_quarantine，gl_leaked=R（含空闲槽名）。uninit_end 语义（GLES 删除活动
query）未核实→新 R-10，仅 context 匹配+CURRENT_QUERY 确认才执行，停机本身整轮
作废故只影响资源回收。
E1 构造：DISJOINT 是 context 级读即清标志——替身只提供 fake_set_disjoint() 全局
注入，**禁止按 query 注入**；单 T1 三槽构造拆为 A-E 五场景（A：HOL 双槽隔离→
匹配 uninit；B：HOL 隔离 + T3 正常在途，下一次 poll 注入 DISJOINT 同批释放两类；
C：HOL 后 poll1 仅 q1 AVAILABLE（前后 DISJOINT 均假）计 rel_late、poll2 注入
DISJOINT 其余 rel_disjoint_quarantine；D：T2 正常在途匹配 uninit；E：读出结果
后复查设 DISJOINT，按 disjoint 归类、结果不入账，正常/隔离各测一遍）——每场景
断言 ⑷a/⑷b/绑定闭合/GL 对象账/X1–X8 + 已输出记录逐字节不变。ctx_lost 主序列
9 步 + 变体 4b（HOL 槽 + C' 中 uninit→gl_leaked=R）/4c（poll 时首次不匹配双段）/
4d（Begin 时首匹配无在途）/4e（uninit 时 CURRENT_QUERY 为外来 query→EndQuery 0
次照常删除）。
P1-a：seg_ref 编码优先级表（1 pre_draw_fail→2 无 ticket→3 停机→4 其他拒绝→5
接受）；方程⑻-r5 按模式限定范围（frame/frame-span/frame-count 各自的 ticketed
定义；t_seq=0 只允许 none:pre_draw 或 refused:no_ticket）+ 分析器跨模式套用拒绝。
P1-b：G-3 显式 6 轮块 ABC-CBA（off1,fc1,fr1,fr2,fc2,off2），matched-start 统一取
off1 初始样本；配对固定：G-3a=fc1↔fr1 与 fc2↔fr2、G-3b=off1↔fc1 与 off2↔fc2、
G-3c=off1↔fr1 与 off2↔fr2（只复用不新增）；禁令：任一轮无效**整块作废重跑**、
不得事后挑温度组合、不得跨块拼接、不得用 a/b 比例乘积推导 c。
P1-c：G-8 证据不足配对**不计入完整 M2′ 通过**（只报"M2′ 局部结果：S0 降幅 r
（S_all 未验证）"）；升级规则不能反推放行；改验收前置须走验收范围变更签字流程。
小项：G-5 r4 写法确认不改；D1 审计清单补 shader_cache 与 ra_gl 两行并**更正**：
撤回 r3/r4"所有 GL 侧 timer 都被 L3 禁用"的隐含说法——L3 只覆盖 LP pl_timer；
ra_gl timer（ra_gl.c:1140-1190 直接 GenQueries/BeginQuery，开始时同步读
GL_QUERY_RESULT）不经过 L3，可达性同 gl_sc（仅旧 gl_video 路径，gpu-next 不可达
[推断]）。双防措施：E2 源码契约（五个 gpu-next 编译单元断言无 gl_sc_/timer_pool_/
ra_timer）+ 设备硬门 refused:foreign_query=0（I1 在 Begin 时发现外来活动 query）。

## C.2.1-r5 ctx_lost 策略（替换 r4 C.2.1 的 ctx_lost 行，新增 owner 级状态）

owner 计时状态 timing∈{running,halted_ctxlost}，单向不可逆。停机条件：Begin、
End、poll、render_end、seal 强制 End 任一入口首次观察到
eglGetCurrentContext()≠owner.context（frame-count 的 Begin 不调 GL 但同样比较）。
停机转移（不调 GL）：全部 issued 未终态段（含活动段）逻辑终态=ctx_lost；其槽
busy_normal→busy_ctxlost；busy_quarantine 保持（段已 hol_drop）；已输出 ticket
不改写；session halted=ctx_lost 整轮作废。停机后：Begin 全拒 refused:ctx_lost；
poll 不执行计 poll_skipped_halted；End 不发（context 恢复也不发）；记账照常
（段 refused）使账本闭合、FINAL 完整。uninit 表与 uninit_end 见修订记录。

## C.2.2-r5 资源账本（替换 r4 C.2.2）

两本账分工：绑定账 R = free + busy_normal + busy_quarantine + busy_ctxlost；
GL 对象账 gl_deleted + gl_leaked = R（只可能是 (R,0) 或 (0,R)，与 uninit context
一致）。释放/泄漏去向：rel_result、rel_disjoint_normal、rel_late、
rel_disjoint_quarantine、rel_uninit_normal、rel_uninit_quarantine、
rel_uninit_ctxlost、leak_ctxlost、leak_quarantine。poll 判定沿用
mks_gpu_timer.h:129-136"读后复查"：读出结果后才观察到 DISJOINT 的槽按 disjoint
归类、结果丢弃（正常→逻辑 disjoint + rel_disjoint_normal；隔离→
rel_disjoint_quarantine）；同一次 DISJOINT 同时释放全部 busy_normal 与
busy_quarantine，不停机（busy_ctxlost 不释放——停机后不再 poll）。绑定账闭合：
bind = 六种 rel + rel_uninit_ctxlost + leak_ctxlost + leak_quarantine + 三类
busy；FINAL 三类 busy=0 且 free + leak_ctxlost + leak_quarantine = R。free=R 是
绑定账说法（无逻辑槽占用/泄漏），不代表 GL 对象可用；leak_* 只计绑定账泄漏，
GL 对象泄漏只用 gl_leaked。

## C.2.3-r5 交叉恒等式（替换 r4 X4–X6；X1–X3 不变）

X4 Σpending_drop = rel_uninit_normal；X5 Σhol_drop = rel_late +
rel_disjoint_quarantine + rel_uninit_quarantine + leak_quarantine；X6 Σctx_lost =
rel_uninit_ctxlost + leak_ctxlost；X7 若 halted=ctx_lost，停机后 rel_result、
rel_late、两种 rel_disjoint_* 均不再增加——summary 输出 halt_at_counters 快照，
FINAL 与快照完全相等；X8 gl_deleted + gl_leaked = R 且 uninit_end ≤ 1。

## C.2.4-r5 seg_ref 优先级与方程⑻（替换 r4 表头规则与方程⑻-r4）

优先级表（每条 copy 记录首中判定）：1 pre_draw_fail（未发起开段请求）→
none:pre_draw/0/t_seq 有则填否则 0；2 无 ticket→refused:no_ticket/0/0；3 停机→
refused:ctx_lost/0/当前 ticket；4 其他拒绝（after_seal/foreign_query/ring_full/
copy_outside_acquire；R2 开 span 被拒）→refused:原因/0/当前 ticket；5 接受
（frame=copy 段；frame-span=活动或新开 span；frame-count=not_timed 段）→seg/段
id/当前 ticket 且 >0。方程⑻-r5：全模式 n(timer=none:pre_draw)=Σpre_draw_fail
（含有无 ticket）；t_seq=0 的记录 timer 只能是 none:pre_draw 或 refused:no_ticket；
unticketed_draws = n(t_seq=0, refused:no_ticket)；seg_ref≠0 必须指向同 ticket
明细中存在的段、类型与模式一致、t_seq>0。mode=frame（范围 t_seq>0 且
timer≠none:pre_draw）：ticketed_draws = n(seg)+n(refused:*)，每 ticket n(seg)=
该 ticket copy 段数。mode=frame-span 同范围：draws_in_span=n(seg)、
Σunspanned=n(refused:*)。mode=frame-count 同范围：ticketed_draws = n(seg)+
n(refused:*)，每 ticket n(seg)=not_timed 段数。

## E1-r5（替换 r4 E1 第 2 项；1、3 保留，追加 4、5）

替身约束：DISJOINT 只能 fake_set_disjoint() 全局注入（读即清），禁止按 query
注入；AVAILABLE 可按单 query 设置。HOL 五场景 A-E 见修订记录（每场景断言全账
闭合 + 已输出记录逐字节不变）。第 4 项 ctx_lost 主序列 9 步（Begin→切 C' End→
停机断言 EndQuery 0 次/s1=ctx_lost/槽 busy_ctxlost→停机后四类 Begin 全拒 0 次
GL→多次 poll 零 DISJOINT/GetQueryObject→切回 C 仍停机→T1 输出 s1=ctx_lost→C
中 uninit：CURRENT_QUERY 核实后唯一一次 EndQuery + DeleteQueries(R)→
rel_uninit_ctxlost=1、leak=0、gl_deleted=R、X6/X7/X8 成立、free=R）+ 变体 4b
（HOL 槽 + C' uninit→GL 0 次、leak_ctxlost=1、leak_quarantine=1、gl_leaked=R、
X5/X6）/4c（poll 首次不匹配双段 ctx_lost）/4d（Begin 首匹配无在途→Σctx_lost=
0）/4e（uninit CURRENT_QUERY 外来→EndQuery 0 次照常删除）。第 5 项：无 ticket
且 pre_draw_fail→none:pre_draw；停机后 pre_draw_fail→none:pre_draw；三模式各
一组混合记录验证各自方程；frame 方程套 frame-span 数据分析器必须拒绝。

## G-3-r5 轮次计划（替换 r4 G-3 表上方轮次说明；阈值与处置不变）

6 轮块 ABC-CBA：1 off1、2 fc1、3 fr1、4 fr2、5 fc2、6 off2；同 APK 同配置；每轮
过 G-11，matched-start 统一取 off1 初始样本。配对固定：G-3a=fc1↔fr1、fc2↔fr2；
G-3b=off1↔fc1、off2↔fc2；G-3c=off1↔fr1、off2↔fr2（只复用）。禁令：任一轮无
效整块作废重跑（所有块结果都报告）；不得事后挑温度组合；不得跨块拼接；不得用
a/b 比例乘积推导 c。

## G-8-r5 放行规则（替换 r4 G-8 配对放行段）

完整 M2′ 通过：**每一个**配对的 G-8 都作为硬门执行（两侧未知时长 ticket 均为
0）且通过，及其他所有门禁通过。G-8 证据不足的配对不计入完整通过，只报"M2′ 局
部结果：S0 降幅 r（S_all 未验证）"。升级规则不能反推放行。改验收前置条件须走
验收范围变更签字登记。

## A.2-r5 D1 审计清单（追加两行 + 一条更正）

shader_cache.c renderpass timer（timer_pool_create(sc->ra) 933-936、start/stop
1018-1021/1046-1049）：sc->ra 为 ra_pl 时经 L3，为 ra_gl 时**不经过 L3**；
gl_sc_ 使用者仅旧 gl_video 文件组（error_diffusion.c/osd.c/video.c/video_shaders.c/
shader_cache.c），gpu-next 的 VO、gpu_next/context.c、hwdec_surfacetexture.c、
placebo/ra_pl.c 无引用（grep 核实）→对 gpu-next 不可达[推断]。ra_gl timer
（ra_gl.c:1140-1190 直接 GenQueries/BeginQuery(GL_TIME_ELAPSED)，检查自身
timer_active，开始时同步读 GL_QUERY_RESULT）：**不经过 L3**；可达性同上。双防：
E2 源码契约（五个 gpu-next 编译单元断言无 gl_sc_/timer_pool_/ra_timer）+ 设备硬
门 refused:foreign_query=0（I1 发现外来活动 query）。ra_gl 开始时的同步读取不在
owner 控制内，若被触发先被检测、该轮作废。更正：撤回 r3/r4"所有 GL 侧 timer 都
被 L3 禁用"的隐含说法——L3 只覆盖 LP pl_timer。

## 风险与切分增量（r5）

R-10：uninit_end 依赖 GLES 删除活动 query 的语义（未核实）；缓解=仅 context 匹
配+CURRENT_QUERY 确认才执行；停机本身整轮作废，只影响资源回收。R-11：ra_gl
timer 不受 L3 约束，靠源码契约 + foreign_query=0 双防。切分：S1 加停机状态机、
busy_ctxlost、两本账、X4–X8、E1 第 2/4/5 项；S2 加 ra_gl/gl_sc 源码契约；S3 加
方程⑻-r5 按模式分支、halt_at_counters 核对、6 轮块固定配对与整块重跑规则、
"局部结果"标注。

---

# r6 增量修订（2026-11-08，对第五轮复审两项 P1 与小项的处置）

> 状态：**待第六轮定向复审**（只核查 r6 增量，应为最终轮）。未列出章节沿用
> r5。新增源码：placebo/ra_pl.c 583-623/641-651/674、gpu/utils.c 242-290、
> gpu/video_shaders.h、opengl/ra_gl.c ~1169-1172。

## 0. r6 修订记录

P1-1：段字段拆分——业务类型 `kind`（render.pre|copy|render.post|render.tail|
span|final + render_call=k）与计时状态 `tstate`（frame/frame-span 为 issued→
五终态；frame-count 为 not_timed 终态，不绑槽不进资源账）分开。frame-count 状态
机与 R1 转移完全一致（copy 单独成段、无 span），仅 Begin/End 换成生成/关闭
not_timed 段、全程零 GL query；遵守 B.3-r4 封闭规则。方程⑻ 的 frame-count 部分
改为按 copy-kind 段计数。E1 第 5 项改用完整 frame-count 票。
P1-2：D1 双防降级——主保证为**调用边源码契约**（E2 实现）：受检单元全名单
（vo_gpu_next.c+yuv_atlas_read_impl.h、gpu_next/context.c、placebo/ra_pl.c、
placebo/utils.c、gpu/hwdec.c、hwdec/hwdec_surfacetexture.c、opengl/
context_android.c、新增 owner 头、含函数体的 MKS 头 mks_gpu_timer.h/
mks_thermal.h/yuv_fusion_gate.h/yuv_compare_vo.h/yuv_atlas_anchor.h/
yuv_atlas_read.h/opengl/mks_yuv_compare.h）；检查方法=去注释和字符串后匹配**函
数调用表达式**；禁止调用：timer_pool_{create,destroy,start,stop,measure}、任何
gl_sc_*、gpu/video.h 的 gl_video_*、video_shaders.h 的 pass_*/sampler_*（E2 从
头文件解析，当前 11 个）、形如 ->timer_{create,start,stop,destroy}( 的表达式；
允许保留位置表（ra_pl.c 583-623 四个 timer_*_pl **定义**只能在 ra_fns_pl 表
674、不得直接调用；641-651 get_active_timer 定义及其 649 pl_timer_create 调用
经 L3；208/234 仅 tex_upload_pl/tex_download_pl 调用 get_active_timer；名单外
审计记录：ra_gl.c 1130-1190、gpu/utils.c 242-290、gpu/shader_cache.c）。契约能
保证：受检单元无通往 timer_pool/gl_sc/RA timer 入口的直接调用边；active_timer
只能由 timer_start_pl 设置而该调用已被禁 → get_active_timer 只返回 NULL[基于
契约的推断]。不能保证：函数指针/回调/名单外单元的间接路径——靠名单穷尽约束。
foreign_query=0 降为有限运行时补充（只能发现 Begin 时刻恰好活动的外来 query；
检测不到：两次 Begin 之间完整开始结束的、ra_gl 开始时同步 GL_QUERY_RESULT 读取
（ra_gl.c ~1169-1172，发生在外来 query 开始前）、owner query 活动后才进入的）。
撤回 r5"ra_gl timer 触发会先被 I1 检测到"。
小项 a：资源等式分阶段——运行期 R=free+三类 busy（每次 Begin/poll/HOL/停机后
断言）；FINAL 三类 busy=0 且 R=free+leak_ctxlost+leak_quarantine（仅 FINAL 断
言）；绑定账闭合式两阶段都断言；E1 断言必须标阶段，不得混用。小项 b：4d 改为
"Begin 时**第一次发现 context 不匹配**且此前无 issued 段"，预期 halted_ctxlost、
Σctx_lost=0、busy_ctxlost=0、匹配 uninit 时 rel_uninit_ctxlost=0、gl_deleted=R。
小项 c：R-10 收窄——审查方已核实 Khronos EXT 规范 158-166（删除活动 query 名
称立即未使用、底层对象不再活动时删除），"先 End 再 Delete"有规范依据[本稿未独
立复核]；未验证收窄为三项：mpv GL 函数表 EndQuery/DeleteQueries/GetQueryiv 指
向 EXT 还是核心版本、uninit 时刻 context 身份、Adreno 驱动行为。

## C.1-r6 段字段（替换 r3/r4 的段状态枚举）

kind ∈ render.pre|copy|render.post|render.tail|span|final（+render_call=k）；
span 仅 frame-span；frame/frame-count 只出现 render.*、copy、final。tstate：
frame/frame-span=issued→resolved|disjoint|pending_drop|hol_drop|ctx_lost；
frame-count=not_timed（终态，不绑槽、不进资源账）。拒绝不生成逻辑段，按 kind+
原因累加 refused 计数。frame-count 状态机=R1 转移（Begin→生成 not_timed 段、
End→关闭段、零 GL query），遵守封闭规则。方程⑷a 下标 k 指业务 kind：attempt_k
= issued_k + not_timed_k + Σrefused_k。

## C.2.4-r6 方程⑻（替换 r5 编码表第 5 行与按 mode 三段）

第 5 行：开段被接受 → timer=seg，seg_ref 指向的段须满足 mode=frame 时 kind=copy
tstate=issued；frame-span 时 kind=span tstate=issued；frame-count 时 kind=copy
tstate=not_timed。按 mode 方程（范围均为 t_seq>0 且 timer≠none:pre_draw 的 copy
记录；r5 全模式条款保持）：frame——ticketed_draws=n(seg)+n(refused:*)，每
ticket n(seg)=kind=copy 的 issued 段数；frame-span——draws_in_span=n(seg)（seg
均 kind=span）、Σunspanned=n(refused:*)；frame-count——ticketed_draws=n(seg)+
n(refused:*)，每 ticket n(seg)=kind=copy 的 not_timed 段数（render.*/final 的
not_timed 不参与本方程，只参与⑷a 分类型闭合）。

## E1-r6（替换 r5 E1 第 5 项、修正第 4 项 4d）

4d：Begin 时第一次发现 context 不匹配且此前无 issued 段→halted_ctxlost、
Σctx_lost=0、busy_ctxlost=0、匹配 uninit 时 rel_uninit_ctxlost=0、gl_deleted=R。
第 5 项：5a frame-count 完整 fused ticket（render_begin(1)→suspend(acq)→copy 开
/关（Draw 成功 publish 成功）→resume→suspend(rel)→resume→render_end→draw_sealed
→swap→收口；断言 not_timed 依次 render.pre/copy/render.post/render.tail 共 4
段、copy 记录 seg_ref 指向 kind=copy 段、n(seg)=1=copy-kind not_timed 段数）；
5b frame-count split 票带 fused 失败回退（第一次 render 消费 copy 失败、第二次
走 adopt 无 copy、draw_sealed 后 final；断言 not_timed 含两组 render.*（render_
call=1,2）+1 copy+1 final、n(seg)=1）；5c 分析器变异检查（故意改成"n(seg)=全部
not_timed 段数"，在 5a/5b 数据上必须给出不一致结论）；5d 沿用 r5（无 ticket
pre_draw_fail→none:pre_draw/t_seq=0；停机后 pre_draw_fail→none:pre_draw；frame
方程套 frame-span 数据分析器必须拒绝）。5a/5b 共同预期：GL query 调用 0 次、
每 kind ⑷a 闭合、⑻-r6 frame-count 部分成立。

## 风险（r6 增量与替换）

R-10 收窄（替换 r5 R-10）：先 End 再 Delete 有规范依据（审查方核实的 Khronos
EXT 158-166；本稿未独立复核）；未验证仅三项——mpv GL 函数表 EndQuery/
DeleteQueries/GetQueryiv 的 EXT/核心映射、uninit 时刻 context 身份、Adreno 驱
动行为。缓解沿用 r5 + E1 第 4 项。R-11 改写：ra_gl timer 不受 L3 约束；主防线
=A.2-r6 调用边契约（依赖名单穷尽前提）；foreign_query=0 仅有限补充。切分：
S2 把调用边契约写进 E2（名单、禁止表、允许位置）；S1/S3 加 kind/tstate 拆分、
⑻-r6、E1-r6 第 5 项、资源等式阶段区分。

## 附注

specialist 为做 grep 核实在 /tmp/vs_syms.txt 写过临时符号表；不属于交付物、未
写入任何仓库。

---

# r7 增量修订（2026-11-08，对第六轮复审两处定义精化的处置）

> 状态：**待第七轮定向复审**（只核查 r7 增量）。未列出章节沿用 r6。新增源码：
> ra_pl.c 558-566/591/597/608/623/672-675、gpu_next/context.c 163、gpu/context.c
> 287、opengl/context.c 268-273、context_android.c 1989。

## 0. r7 修订记录

修正 1：方程⑻ 的引用与计数条件从"当前 tstate=issued"改为"属于**已成功 issued
的段集合**"。新增只写一次的 `issued` 布尔标志（Begin 成功且通过 CURRENT_QUERY
确认后置真，不再变；frame-count 恒假；被拒请求无此字段）。三 mode 方程同步改
写；E6 新增 a-e 五项（resolved 后校验仍通过、其他终态通过但不进 S0、变异测试、
跨模式拒绝）。5b 措辞改为"copy/publish 成功，随后首次 render 失败"，并新增 5b′
反例（copy 本身失败时不得预设一定 adopt）。
修正 2：允许表补 renderpass_run_pl（ra_pl.c:560-566），函数定义/注册行号精确化
（591-638 定义、672-675 注册）；名单改称**直接调用边回归检查集合（DCE 集合）**，
不声称覆盖全部生产调用图；已知可达但名单外的单元列表 + 间接可达性核查正式化为
证据项 **EV-1**（S2/E2 完成前必须闭合；S1 可先做但标注为待验证前置项）。

## C.1-r7 段字段（r6 C.1 追加）

`issued`：布尔、只写一次。Begin 成功且通过 GL_CURRENT_QUERY 确认后置真。
frame-count 恒假；被拒请求无此字段。关系：issued=真时 tstate∈{issued, resolved,
disjoint, pending_drop, hol_drop, ctx_lost}；issued=假时 tstate=not_timed。输出
约束：段到终态才写明细，明细中 issued=真 的段 tstate 必为终态。

## C.2.4-r7 方程⑻（替换 r6 C.2.4-r6 全部）

优先级表第 5 行：开段被接受 → timer=seg；seg_ref 指向的段须满足：mode=frame 时
kind=copy 且 issued=真（tstate 可为任意合法终态）；frame-span 时 kind=span 且
issued=真；frame-count 时 kind=copy、issued=假、tstate=not_timed。分 mode 方程
（范围 t_seq>0 且 timer≠none:pre_draw 的 copy 记录；r5 全模式条款不变）：
frame——ticketed_draws=n(seg)+n(refused:*)，每 ticket n(seg)=|{kind=copy 且
issued=真 的段}|（不论当前终态）；frame-span——draws_in_span=n(seg)（均 kind=span
且 issued=真）、Σunspanned=n(refused:*)；frame-count——ticketed_draws=n(seg)+
n(refused:*)，每 ticket n(seg)=|{kind=copy 且 tstate=not_timed 的段}|。补充：⑷b
的 issued_k = |{kind=k 且 issued=真 的段}|，与本节同一谓词，分析器必须用同一计
算。

## E1-r7（替换 r6 E1-r6 的 5b；追加 5b′）

5b：首次 render（fused）中 copy 和 publish 都成功，随后首次 render 失败；第二次
render 经 retired adopt 进行（无 copy）；draw_sealed 后执行 final。断言不变：
两组 render.* not_timed 段（render_call=1,2）+1 copy+1 final、n(seg)=1。5b′：
copy 本身失败（draw_err 或 publish 失败）时，第二次 acquire 不保证有可 adopt 的
lease——测试只断言控制流实际结果（adopt/fresh copy/失败），不预设 adopt。

## E6-r7 分析器测试追加（r5 E6 基础上）

E6-a：mode=frame、S0 ticket 中 copy 段 issued=真/tstate=resolved、记录
timer=seg → 方程⑻与 seg_ref 校验通过。E6-b：终态依次换 disjoint/hol_drop/
pending_drop → 方程⑻通过，ticket 因不完整不进 S0。E6-c：frame-span span 段
issued=真/resolved → 通过。E6-d（变异）：谓词故意改成"当前 tstate=issued" →
分析器在 E6-a 上必须拒绝。E6-e：seg_ref 指向的段 issued=假 但 mode=frame → 拒绝。

## A.2-r7 D1 调用边契约（替换 r6 A.2-r6 三段；禁止调用表与运行时补充检测不变）

**名单性质**：r6 名单改称**直接调用边回归检查集合（DCE 集合）**——只做回归检
查（确认不新出现禁止的直接调用），不代表覆盖全部生产调用图，不构成"不存在间接
路径"的证明。成员同 r6。

**已知可达但不在 DCE 集合的单元（交 EV-1 核查）**：gpu_next/context.c:163→
ra_ctx_create（gpu/context.c:287 起）；context_android.c:1989→ra_gl_ctx_init
（opengl/context.c）；正常 swap 经 ra_gl_ctx_swap_buffers（context.c:268-273）→
params.swap_buffers 回 context_android.c；mapper/VO 经 ra_gl_get 等进入 ra_gl
（1130-1190 为 ra_gl timer 实现）；其他基础设施[推断]：opengl/common.c、
opengl/utils.c、opengl/egl_helpers.c、gpu/ra.c、gpu/utils.c（242-290 timer_pool
实现）。

**允许保留表（替换 r6 表）**：ra_pl.c:591-638 四函数定义（timer_create_pl 591、
timer_destroy_pl 597、timer_start_pl 608、timer_stop_pl 623）不允许被直接调用；
ra_pl.c:672-675 四函数指针注册只允许出现在这里；ra_pl.c:641-651 get_active_timer
定义及 649 pl_timer_create（经 L3）；get_active_timer 调用点仅 tex_upload_pl
(208)、tex_download_pl(234)、**renderpass_run_pl(560-566, .timer=get_active_
timer(ra))** 三处；DCE 外 ra_gl.c:1130-1190、gpu/utils.c:242-290、
gpu/shader_cache.c 只作审计。

**已保证/待证明**：已有证据（grep 部分证据）=DCE 内无禁止直接调用；video/out 内
fns->timer_* 仅 gpu/utils.c（timer_pool 实现）；timer_pool_* 调用方仅旧
gpu/video.c 与 gpu/shader_cache.c；gl_sc_* 使用者仅旧 gl_video 文件组。推断=DCE
内 get_active_timer 返回 NULL（active_timer 只由 timer_start_pl 设置，其调用已
禁）。待证明=从 gpu-next 入口经名单外单元/函数指针/回调到达 timer 创建者的路径
——即 EV-1。

**EV-1 间接可达性核查（S2/E2 完成前必须闭合）**：入口节点=gpu-next VO 驱动回调
（preinit/draw_frame/flip_page/control/uninit，取自驱动表）、LP 回调（acquire/
release 包装、info_callback）、使用的 ra_ctx_fns 与 ra_swapchain_fns 表项、
hwdec 驱动表；目标节点=timer_pool_create/start、任何 ra_fns.timer_create/timer_
start 槽调用、gl_sc_create、gl_video_init、pl_timer_create（确认必经 L3）。方法：
NDK 构建单元集上生成直接调用图（clang AST 或 cflow，Worker 选定并记录版本）；
函数指针表人工逐项列出（ra_fns、ra_swapchain_fns、ra_ctx_fns、hwdec mapper 驱动
表及填充/调用点）；求入口→目标可达路径集。闭合条件=路径集为空，或每条路径被证
明只返回 NULL（如经 L3）或 armed 下不可达，附源码依据。产出=路径清单（或无路径
结论）、工具及版本、函数指针表清单、源码 SHA256。未闭合规则：调用边契约只能描
述为"直接调用边回归检查"、S2/E2 不能判完成、S4 接线复审不能开始、设备轮不放行。

## 风险与切分（r7 增量）

R-11（替换 r6）：ra_gl timer 不受 L3 约束——r6"主防线是调用边契约，前提名单穷
尽"撤回；改为 DCE 负责回归检查、EV-1 负责间接可达性证明（**尚未闭合**）、
foreign_query=0 仅有限补充。EV-1 闭合前 ra_gl 隔离只能写"直接调用层面未发现，
间接层面待证"。切分：S1（owner 核心，纯 host）可先做，交付说明标注"EV-1 待验证
前置项，ra_gl/gl_sc 隔离尚未证明"；S2 完成条件新增"EV-1 已闭合"；S3 加 issued
谓词与 E6-a~e；S4/S5 开始前须确认 EV-1 已闭合。交 Lead 新增：EV-1 发现可达路径
且无法证明只返回 NULL 或 armed 下不可达。
