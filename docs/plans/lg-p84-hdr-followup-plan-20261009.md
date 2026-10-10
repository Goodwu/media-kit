# LG P8.4 HDR 显示线 · 后续工作计划（2026-10-09 立项，v4.1 2026-10-10 全量状态合并版）

> **v4 合并说明（2026-10-10）**：本版将散落于 TASKS.md 活跃条目、conversation 归档
> （`archives/conversations/lg-h870ds-hdr-demo-20261004.md` Current State）、需求文档
> `docs/requirements/android-hdr-auto-output.md`（v5）与各轮执行记录中的**计划定义、
> 需求约束与完成状态合并为单一事实源**。此前 v3 只含 C0 存档而缺 C1-C4 细节定义，
> 状态需跨文件拼装——v4 起本文档即全量接手入口。
>
> 依据链：综合优化审视原文（DIAG-REPORT.txt「综合优化审视」节）→ v1/v2 成文 →
> v3：Critical Reviewer V2 审核（提案 fail→受限立项 / 计划 pass-with-issues→修订）+
> 用户裁决移除 C0 → v4：执行至 A/B/D/C2 全收口后的状态合并重写 →
> **v4.1（2026-10-10）：C1/C4/D3 交付收口；C3 调查完成、计划前提证伪（§6.4），
> 剩余形态待用户裁决；设备版本勘误 API 26→API 24（Android 7.0，getprop 实证）**。

## 0. 当前状态总览（2026-10-10，接手先读）

| 线 | 项 | 状态 | 收口证据 |
|----|----|------|----------|
| A | A1 拆功能开关与观测 | ✅ 完成 | off 恒等性三方逐字节一致（context `206f4a28…`/hwdec `a044eaf0…`），/tmp/mks-a1-artifacts/ |
| A | A2 owner/generation 产品化 | ✅ 完成 | 1×1 首帧拒注入实机证据行（genbump2 轮）；生命周期矩阵+JNI 16 项+JUnit 25/25 |
| A | A3 P1 修复包 | ✅ 完成 | 六项重审 3 闭合+3 修复+复审增补（draw_copy read/draw+viewport、resize 纹理滞留） |
| A | A4 契约字段拆分 | ✅ 完成 | HdrRoute.offscreenTransfer 独立字段+四元组 fail-closed 断言+vendor 拆 lg_fw_adapter |
| A | A5 V2 收口补审 | ✅ 完成 | mpv 侧 PASS（R1-R5 全关）；media-kit 侧 P1 全关+P2-1 组合闭包 |
| A | A6 回归+入库 | ✅ 完成并推送 | 三仓提交：FFmpeg d4bb79394b / mpv a040233d3e / media-kit 四笔 9e845e6f→168895f9；push 已获用户授权并执行（media-kit main e35e5cb6） |
| B | B1 四门顺序探针 | ⏸ 用户裁定降级延后（2026-10-10） | 触发式：用户点单再做，不主动排期 |
| B | B2 分流裁决 | ✅ 用户已裁决：8-bit 维持现状 | 2026-10-10 裁决入档（genbump2-closure） |
| B | B3 实施轮 | ⏸ 随 B1/B2 一并延后 | 8-bit 终态既定，无实施对象 |
| B附 | NV12 量化/抖动研究 | ⏸ 未排期（P2 独立小课题） | 结论反哺 8-bit 终态质量，触发式 |
| C | C0 disable_linear_scaling | ❌ 用户裁决移除（2026-09 案→10-09 裁决） | 收益仅 ALU 级不满足前提；重开条件见 C 线 |
| C | C2 遥测+去插桩设备轮 | ✅ 完成 | r6：干净产品构建复现验收路径，90s decDrop=0 恒零、vfps=29.970030 源率、hal_hdr 单次稳定、MKST 违约全零 |
| **C** | **C1 性能分析深化** | ✅ 完成（2026-10-10） | 报告 `docs/plans/lg-p84-c1-performance-analysis-20261010.md`；解码侧四轮 decDrop=0/vfps 锁源率实锤；渲染侧 per-pass timing 不可用（vo-passes count=0）；c14 通道探测轮 52 文件在案 |
| **C** | **C3 lease 融合** | ⏸ 调查完成——**计划前提证伪，剩余形态待用户裁决** | 现状已是源尺寸 RGBA16F 四槽 lease（draw_copy=物化步骤，:1359 非计划的 :1267）；严格消除需改 pinned libplacebo checkpoint——详见 §6.4 |
| **C** | **C4 呈现帧率证据+4K30 门** | ✅ 收口（2026-10-10，通道死端） | API 24 设备全通道逐一实锤无呈现级帧证据（`--timestats`/`--framestats` 不识别、`--latency` 仅回刷新周期、media.metrics 服务缺失、gfxinfo 仅 UI 线程）；4K30 定量=解码侧实时（达成）+人验（通过）；c14 轮 channel-verdict.json |
| D | D1 VUI RPS/HRD 修正 | ✅ 完成并推送 | 差异清单+修正+ASan/UBSan 5×200k+harness 全过；FFmpeg d4bb79394b |
| D | D2 分类修复链产品化 | ✅ 完成（device 待验 3 格登记） | tool/mksvui-regress 收编+7 用例+fuzz PASS+回归矩阵 L0-L5；dev-1/2/3 设备格待验；MKSVUIPROBE/MKSCOLORKEYS 降级与 configure hack 裁决移交 D3 |
| **D** | **D3 上游化决策** | ✅ 完成（2026-10-10） | 决策=fork 长期携带（上游 ps.c 本就正确，无可上游化缺陷；镜像解析器为 fork 特有特性）；D2 移交裁决：MKSVUIPROBE/MKSCOLORKEYS=log 标签保持现状、configure hack=构建树配方保留；`docs/plans/lg-p84-d3-upstream-decision-20261010.md` |
| E | E1/E2/E3 条件触发 | 挂起 | E1 触发条件未再现（hal_hdr 震荡已随 range=1 恢复消失）；E2 横屏黑屏未复现；E3 备用 |
| G | G1 configure hack 正式方案 | ✅ 用户已裁决：不正式化，维持现状 | 清空 dirty=常态机制，验证窗口保留、不用恢复原始文件；操作纪律见 §14；方案 B/A/C 存档 |
| G | G2 Kazumi hls 补丁 | ✅ 用户已裁决：不入库 | 留档构建树工作树+genbump 溯源精确源树；重建须有意识携带，详见 §14 |
| F | P2 收尾 | 部分 | 模块隔离/日志注释随 A 线落地；TASKS 旧 status 摘要同步=随手项 |

**剩余未完成项：仅 C3（调查完成、前提证伪，剩余形态待用户裁决）**；B 线已按用户裁决
出清；C1/C4/D3 已于 2026-10-10 收口；F 线随手。

## 1. 前置状态与验收基线

- P8.4 HDR 显示已人验通过（2026-10-09 用户"色彩好，亮度好，流畅度好"——euv13-stable-long）。
- 验收路线全链：HLG BT.2020 10-bit → MediaCodec surface 解码 → SurfaceTexture →
  libplacebo HLG→PQ（target-peak=1000）→ RGBA16F 离屏 → BT.2020 NCL full-range 打包 →
  NV12 config49（VENUS）window → HWC 视频层合成 → 逐 buffer COLOR_METADATA (9/1/16) →
  SDM hal_hdr 稳定 → 面板 PQ 解码。
- 代际基线（2026-10-10 genbump2 轮后）：FFmpeg 链接单代化到 fork tip（d4bb79394b+dirty），
  mpv 216 对象、undefined 符号集 393=c22e70b6 金标准双向相等；设备装机=genbump2 代
  c2-telemetry 包（2026-10-10 12:04 安装）。
- 设备：LG-H870DS（LGH870DS42e27764，**Android 7.0 / API 24**——2026-10-10 getprop 实证
  勘误，此前文档 API 26 系协议文档头部笔误；vendor lg_fw_adapter 亦按 SDK 24 精确门）
  唯一验收环境；marble 仅能力对照。

## 2. 现状快照与形态

- **已达成**：完整验收路由 baseLayerConvert/platformView/surfacetexture/surface:pq/
  offscreen:pq-full；hal_hdr 单次切换零翻转；实时播放 decDrop=0。
- **审视总体判断**：方案已证明"能正确显示"，A 线后已是产品化后端；剩余工作=真实性能
  深化分析（C1）、输入侧 lease 大杠杆（C3）、呈现级证据（C4）。
- **形态**：A 线后=产品化（诊断与功能开关拆分完毕，feature 门默认 1、诊断门默认 0）。
- **根因定律**：metadata 身份三元组必须与 buffer 内容严格一致（euv14-rng2 教训）。

## 3. 证据修正（全员须知的记录口径）

1. **readback 是跨进程混合总数，不是上屏帧计数**（PID11546: 2415 + PID11798: 4485）。
2. **两路线显示路径不同，结论不互套**：E-YUV 视频层=HWC 合成实锤；"GLES 合成"仅属 RGB 路线。
3. **readback 本身扰动性能**：性能结论不得来自带 readback 的运行。
4. **截图与上屏渲染参数可能分叉**：video_screenshot 另建 pl_render_params
   （vo_gpu_next.c:1612,1777），截图/另渲染不能冒充上屏实验证据。
5. **vfps=estimated-vf-fps 是解码→VO 提交链路帧率（源率锁定），非屏幕实际显示帧率**
   （2026-10-10 用户问询更正入档）——呈现级证据必须走独立通道（C4）。
6. **字节级符号守门必须对真实链接输入做**（genbump 事故教训：查错对象到 prefix 归档，
   真实链接输入是 DPS stash）；静态符号一致≠运行期一致（版本守卫是运行期行为）。

## 4. 架构级决策（审视原文四项，v3 修订口径）

1. **两段式输出（RGBA16F 离屏 + 末级 pass）暂保留**：融合非近期收益
   （1440×720 离屏 ~8.29MB、往返 ~0.5GB/s 名义访问量为结构估算）。
2. **输入侧更大杠杆：OES→全分辨率 RGBA16F lease**（满配 ~225MiB）；当前路线已是 OES
   导入，但 hwdec_surfacetexture.c:1267 仍做源尺寸 GPU copy（draw_copy），**lease 融合
   消的就是这个**——即 C3。融合需帧身份保持设计。
3. **产品化三职责边界**（A4 已落地）：输出策略与授权 / YUV 呈现实现 / 精确固件
   metadata 适配器；"离屏契约"与"窗口契约"已拆为独立字段（HdrRoute.offscreenTransfer）。
4. **10-bit 路线四门顺序探针**（=B1，已降级延后）：分配（P010/Y210）→ EGLImage 导入
   可写 → stride 对齐 → HWC 资格；任一门失败即停。EGL window-config 无已知 10bit YUV
   选项（已实证）；EGLImage/gralloc 路线未证伪也未证可行。

## 5. A 线 · 产品化收口（✅ 全部完成，2026-10-10 收口并推送）

| # | 任务 | 验收门 | 结果 |
|---|------|--------|------|
| A1 | 拆功能开关与观测 | off 构建与产品基线逐位一致 | ✅ 门矩阵收敛（feature 默认 1：MKS_YUV_HOOK/MKS_YUV_P1_INJECT/shader；诊断默认 0：P0_OBSERVE、ST_DIAG_READBACK）；P1=1∧HOOK=0 #error；readback 缺口修复 |
| A2 | owner/generation 产品化 | 生命周期矩阵全格；竞态锁定 | ✅ mkst 桥显式 init 取代 pthread_once；硬门+锁纪律；hook 全生命周期；1×1 首帧拒注入（实机证据行在案）；vendor arm/disarm |
| A3 | P1 修复包 | 各项独立用例+回归锁定 | ✅ swap 错误传播、resize 资源、GL 状态（viewport/read-draw binding）六项闭环 |
| A4 | 契约字段拆分 | 字段与 buffer 一致性断言 | ✅ offscreenTransfer 独立字段+四元组 fail-closed+vendor 拆 lg_fw_adapter（dynsym 冻结集等价） |
| A5 | V2 收口补审 | 独立 V2 无 P1/P2 阻断 | ✅ mpv 侧 PASS；media-kit 侧 P1 全关、P2-1 单 GL 线程模型收口 |
| A6 | 回归+入库 | 全绿；先更新台账 | ✅ 三仓语义化提交+推送（见 §0 A6 行）；过程事件（CR 卡死→哈希机械对比闭合）已透明入档 |

单 writer 串行约束已随 A 线关闭（历史约束，供回溯）。

## 6. C 线 · 性能与缩放（部分完成，C1/C3/C4 未完成）

### C0 · disable_linear_scaling（已移除，存档）

用户裁决移除（收益仅省主缩放前 HLG 线性化 ALU，带宽不省）。**重开条件**：C2 遥测显示
主缩放前线性化 ALU 占主导——零代码 mpv 选项
（`linear-downscaling=no linear-upscaling=no`，vo_gpu_next.c:2538 已映射）可低成本复测；
验收两阶段（高频/斜线/运动样本+线性光基线；性能轮关 readback）。

### C2 · 遥测+去插桩设备轮（✅ 完成，2026-10-10 凌晨）

干净去插桩产品构建（libmpv c22e70b6…，216 对象=euv17 期望集、undefined 集逐符号双向
相等）设备复现完整验收路径：config49 全枚举→NV12 窗口→YUV-P1 armed（9/1/16）→
SDM hal_hdr 单次稳定→90s 实时播放 decDrop=0 恒零、vfps=29.970030、pos 91s、MKST 违约
全零。**vo-passes 判定**：string 可读（len=114）但计时采样恒空（count=0）→
**per-pass timing 本配置不可用**，C1 遥测改走 SF latency + AVTRACE。
证据：`~/src/media-kit-build/lg-api24/lg-api24-realtime-gpu-mks-c2-telemetry-r6-run/`。

### C1 · 性能分析深化（✅ 完成，2026-10-10）

- **定义**：在去插桩产品构建上深化真实性能分析。遥测通道=SF latency（已证死端）+
  AVTRACE；产出=性能分析报告（解码侧、渲染侧、呈现侧各自证据与缺口）。
- **交付**：`docs/plans/lg-p84-c1-performance-analysis-20261010.md`（四轮实测汇总：
  解码侧 decDrop=0 恒零/vfps 锁源率/pos 实时；渲染侧 per-pass timing 不可用+MKST 全零+
  hal_hdr 单次稳定；呈现侧=通道死端见 C4；链内最大单项名义流量=输入侧 lease 物化 copy
  ~3.54GB/s@3840×1920 结构估算）。
- **验收门**：报告成文+数据可溯源——达成。

### C3 · OES→全分辨率 RGBA16F lease（⏸ 调查完成——**计划前提证伪，剩余形态待用户裁决**）

#### 调查结论（2026-10-10，Specialist 只读核查，~/src/mpv @ a040233d3e）

1. **前提证伪**：计划设想"当前路线是 OES 导入+每帧源尺寸 copy，lease 尚不存在"。
   实况=**现有实现已经是源尺寸 RGBA16F 四槽 lease 池**（RGBA16F 优先/RGBA16_UNORM
   备选，hwdec_surfacetexture.c:1119-1158 分配、1191-1220 current/retired 命中复用）；
   draw_copy（实际调用点 :1359，计划所写 :1267 已过时）**就是 lease 的物化步骤**
   （latch OES→恒等 copy 入槽→发布 lease 纹理）。
2. **copy 存在的真实理由**：单一 mutable OES 会被下一次 latch 覆盖——redraw/暂停/
   多 retained frame 需要稳定帧内容；**不是** libplacebo 不能采 OES（pinned
   libplacebo c9fd8798 的 gpu_tex.c:714 已支持 EXTERNAL_OES）。EGLImage/AHB 替换
   不消除该约束（API 24 亦无公共 AHB 分配 API 可作基线）。
3. **剩余可行形态（候选）**：把稳定 lease 落在 **libplacebo 首个源尺寸必要处理 pass 的
   产物**（checkpoint 物化+重放），即 OES→处理结果（=lease）→缩放/转换，消去旧
   identity copy 的写+读（3840×1920 名义 ~118MB/帧 ≈3.54GB/s@29.97fps，链内最大单项）。
   **前提=改 pinned libplacebo（c9fd8798）增加显式 checkpoint/恢复接入**——仅改
   importer 无成立方案（Specialist 明确结论）。
4. **风险**：跨仓改动（buildscripts/deps/libplacebo 进入改动面，波及字节恒等门与
   prefix 重建链）；checkpoint 缓存失效与重复颜色处理（线性 RGB 被当 HLG 再解码/
   DOVI 重复应用=最危险错误）；数值路径变化（mediump 恒等 copy→融合后舍入点变化，
   不承诺逐像素 bit-exact）；经人验显示线的回归风险；收益为名义带宽账，实际净收益
   不保证（无 GPU timer 通道可先验）。
5. **裁决选项**：
   - a) **不实施，登记为已知候选**（现状 lease 已是最优可行形态；与 C0"明显收益"
     前提纪律一致——实际收益不可先验）；
   - b) **立项受限融合候选**：按 Specialist Gate 0（冻结 checkpoint 接口与重放语义，
     Reviewer 独立核对）→ Gate 1 宿主生命周期+off 门 → Gate 2 实机 copy 消失计数
     → Gate 3 性能 A/B → Gate 4 画质人验 走正式轮次。
   Lead 建议：a（同 C0/B1 纪律：收益不可先验、改动面跨 pinned 依赖、人验线回归风险；
   若未来 4K 高帧率素材出现实际卡顿证据，b 的 Gate 0 可低成本低成本重开）。

#### 原始定义（存档）

架构级决策 2 落地：消除 hwdec_surfacetexture.c 源尺寸 GPU copy（draw_copy）。口径
修正（v2 审）：删 360MB/s 旧 copy 时代收益估计。设计约束：帧身份保持（metadata 三元组
定律）；离屏契约（full 归一化 PQ RGBA16F）不变。原验收门：实机证据显示 draw_copy
消除+画质人验不回归。

### C4 · 呈现帧率证据通道+4K30 定量门（✅ 收口，2026-10-10——通道死端）

- **定义**：pos/decDrop/人验不可替代呈现帧率证据（v2 审补）。
- **通道验证结果（c14 探测轮，播放态逐一实测）**：API 24 设备**不存在任何呈现级视频帧
  证据通道**——SF `--latency` 旗标被识别但仅回刷新周期单行 `16666666`（r6 轮 104 采样
  +c14 轮 3 采样一致）；SF `--framestats`/`--timestats` **不被识别**（回落默认 dump，
  无 PROFILEDATA）；`media.metrics` 服务不存在；`media.codec` 输出 0 字节；`gfxinfo`
  仅覆盖 Flutter UI 线程帧（播放期间 PROFILEDATA 逐字节冻结，与 SurfaceView 视频呈现
  无关）。证据：`lg-api24-realtime-gpu-mks-c14-chprobe-run/channel-verdict.json`
  （52 文件）。
- **4K30 定量门收口**：可达成形态=解码侧实时定量（4K 3840×1920@29.97 素材 30s/90s 轮
  decDrop=0+vfps=29.970069/29.970030 源率+pos 实时——达成）+人工验收（流畅性通过——
  达成）；呈现级帧率定量登记为**本设备不可得**（非未做）。

## 7. B 线 · 10-bit 质量保全（⏸ 用户裁定延后，2026-10-10）

| # | 任务 | 状态 |
|---|------|------|
| B1 | 四门顺序探针（分配→EGLImage 导入可写→stride→HWC 资格；任一门失败即停） | ⏸ 用户裁定降级延后：B 线不再主动排期，触发式（用户点单再做） |
| B2 | 分流裁决 | ✅ 已裁决：**8-bit 维持现状**（措辞纪律保留：单候选失败只关该候选，不外推全域不可行） |
| B3 | 实施轮（末级 pass 位深升级+契约同步） | ⏸ 随 B1 延后（8-bit 终态既定，无实施对象） |
| B附 | NV12 量化/抖动研究（8-bit 量化无显式 dithering 契约，libplacebo dither 不覆盖末级 NV12 量化） | ⏸ 未排期，触发式 |

## 8. D 线 · 解码侧

| # | 任务 | 状态 |
|---|------|------|
| D1 | VUI RPS/HRD 解析差异修正 | ✅ 完成：镜像解析器 2 缺陷修正（st_rps used 标志漏读、nal+vcl HRD 单循环）+三方互证差异清单+ASan/UBSan 5×200k 零越界+harness 全过；FFmpeg d4bb79394b 已推送（branch lg-p84-d1-vui-fix-20261010） |
| D2 | 分类修复链产品化 | ✅ 完成：tool/mksvui-regress 收编（487 行，7 用例+fuzz PASS）+回归矩阵 L0-L5+清理清单；**dev-1/2/3 设备格待验**（设备轮顺带）；MKSVUIPROBE/MKSCOLORKEYS 降级建议与 configure hack 保留裁决**移交 D3** |
| D3 | 上游化决策（✅ 完成） | 决策记录 `docs/plans/lg-p84-d3-upstream-decision-20261010.md`：fork 长期携带（上游 hevc/ps.c 本就正确，无可上游化缺陷；镜像解析器= fork 特有特性由 d4bb79394b 首次入库即含修正）；D2 移交裁决：MKSVUIPROBE/MKSCOLORKEYS=log 标签非环境开关、保持现状（回归 harness 依赖）；configure hack=构建树配方成分、保留 |

## 9. E 线 · 条件触发项（挂起）

| # | 触发条件 | 动作 | 状态 |
|---|----------|------|------|
| E1 | 再现 hal_hdr↔hal_native 震荡 | HandleHDR 判定输入反汇编（sdmcore-disasm.txt 已存档） | 挂起（range=1 恢复后未再现） |
| E2 | 产品化轮复现横屏黑屏 | 横屏过渡双 mount platform view 竞态专项 | 挂起（未复现） |
| E3 | 显示链异常排查需要 | qdmeta-forensics 取证 | 备用 |

## 10. F 线 · P2 收尾

- 模块隔离+日志注释收敛：随 A 线三职责落地已完成主体；注释漂移余项随手。
- TASKS.md 旧顶层 status 摘要与最新验收状态不一致处随手同步。

## 11. 推荐排序（v4.1 收口态）

**C1 → C3 → C4 → D3 已全部执行完毕**：C1/C4/D3 交付收口（2026-10-10）；C3 执行至调查
阶段证伪计划前提，剩余形态（libplacebo checkpoint 融合候选）**待用户裁决**（选项与
Lead 建议见 §6.4）。P2 随手；E 挂起；B 线触发式；C0 移除。

## 12. 风险与约束

1. **commit/push**：A6 批次已获授权并推送；**新提交需按仓库惯例更新台账后走语义化
   本地提交，push 逐批请示用户**。
2. **设备单点**：LG-H870DS 唯一验收环境；marble 仅能力对照。设备操作前读
   `~/src/media-kit-build/lg-api24/LG-DEVICE-LOGCAT-PROTOCOL.md`（subagent 必读）。
3. **metadata 契约定律**：触及输出格式/打包的改动必须同步三元组标签（验收否决项）。
4. **证据口径六条**：见 §3。
5. **构建链单代律**（genbump 事故后新增）：FFmpeg 链接配方 avcodec/avformat token 必须
   与 mpv 对象编译头同代（prefix tip）；字节级符号守门对真实链接输入做。
6. **euv13 人验与 euv17 复测区分**：euv13=用户人验通过；euv17=同配置技术复测稳定，
   人验复核待用户，不自动视为已关闭。

## 13. 用户裁决记录（本计划相关，全部已落地）

| 日期 | 裁决 | 落地 |
|------|------|------|
| 2026-10-09 | C0 移除 | 计划 v3 出档；重开条件存档 |
| 2026-10-09 | A 线启动 | A1-A6 执行 |
| 2026-10-10 | P5 直通默认化 | d2fdbc65（dvP5×nativeDV experimental→verified），需求文档 v4 |
| 2026-10-10 | 8-bit 状态维持；B1 降级延后（触发式） | B 线出清，见 §7 |
| 2026-10-10 | 三视频人验通过（HDR10/P5/P8.4 各 30s，genbump2 代际） | 当前代际播放矩阵人工验收关闭 |
| 2026-10-10 | A 组三格成熟度提升 | a0d8c4a3（dvP84×nativeDV、hdr10×baseLayerConvert、hdr10×metadataReshape → verified），需求文档 v5 |
| 2026-10-10 | 三仓提交+推送授权 | A6 批次落地（FFmpeg/mpv/media-kit） |
| 2026-10-10 | configure hack 需正式方案；Kazumi hls 补丁不入库 | §14 G 线登记（G1 待批准实施、G2 关闭） |

## 14. G 线 · 构建链正式方案（2026-10-10 新增，用户裁决驱动）

### G1 · FFmpeg configure hack（FFMPEG_CONFIGURATION 清空）正式方案（✅ 已裁决：不正式化，维持现状，2026-10-10 用户裁决）

**裁决（2026-10-10）**：不做正式修改（方案 B/A/C 均不立项）。清空 dirty 即常态机制：
**需要字节级比对/重建验证的窗口保持两树清空状态，不用时恢复原始 configure 文件即可**。
操作纪律（同 G2 携带纪律）：未来任何 prefix 重建前须核验两树 dirty 在位（字节门依赖
该清空）；验证窗口结束后恢复与否由当轮自行决定，恢复不损失任何功能（该字符串功能
惰性，见下机理）。

**现状**：`~/src/FFmpeg` 与构建仓 `buildscripts/deps/ffmpeg` 两树 configure 各持同一 1 行
未提交改动：config.h 模板 `#define FFMPEG_CONFIGURATION "$(c_escape $FFMPEG_CONFIGURATION)"` → `""`。

**机理（2026-10-10 核实）**：该宏由 libavutil/avformat/avcodec/… 各库 version.c 的
`*_configuration()` 返回，字符串编入 .rodata——内嵌完整 configure 命令行（含绝对路径）使
FFmpeg 归档字节随构建路径/configure 行漂移，破坏字节级复现门。mpv 不消费
`av*_configuration()`（mpv 树 grep 零命中）；与运行期崩溃检查无关（common/av_log.c
`check_library_versions` 仅比版本号 INT，即 genbump 事故根因，另事）。

**方案**：
- **B（推荐）构建仓承载**：清空动作收敛为 buildscripts 对 ffmpeg configure 生成 config.h 的
  确定性定点步骤（configure 调用后 sed 或等效），两 FFmpeg 工作树 configure dirty 撤销回
  pristine；build-mks-r1.py provenance 门记录该步骤。**实施门：重建归档与现役 genbump2 代
  逐字节一致**（现役 config.h 该字符串已为空，理论全等）。优点：构建策略归位、FFmpeg
  分支贴近上游降低 D3/升级成本、消除"哪棵树带 hack"歧义。
- **A（备选）fork 正式提交**：1 行独立 commit 入 fork 分支注明动机；上游化形态
  （configure 增 `--configuration-string=` 类选项）归 D3。缺点：上游冲突面 +1、构建策略散落源树。
- **C（长期）**：向上游 FFmpeg 提正式选项 patch，不阻塞本线。

**过渡**：B 实施前两树 dirty 维持现状（防 prefix 重建路径断裂）；实施后撤销并过字节门。
~~实施涉及构建仓提交与一次重建验证，待用户批准。~~（2026-10-10 用户裁决：不正式化，
维持现状按需保留/恢复，见节首裁决——以下方案 B/A/C 降为存档参考。）

### G2 · Kazumi HLS 广告过滤补丁（✅ 已裁决：不入库）

构建树 deps/ffmpeg 工作树未提交的 hls.c 补丁是活产品特性
（MediaKitConfiguration.adBlocker 每播放器必传），用户裁决**不入库**（不提交进 FFmpeg 仓）。
留档：①构建树工作树（活副本）；②genbump 溯源精确源树
`~/src/media-kit-build/lg-api24/genbump-provenance-20261010/prefix-build/src/libavformat/hls.c`。
约束：未来 prefix 重建须有意识携带（genbump 轮"方案 A 携带补丁重建"先例）；重建脚本与
交接文档不得将其视为可丢弃 dirty。

## 15. 关联文档索引

- 本计划交付文档：C1 报告 `docs/plans/lg-p84-c1-performance-analysis-20261010.md`；
  D3 决策记录 `docs/plans/lg-p84-d3-upstream-decision-20261010.md`
- 需求与策略：`docs/requirements/android-hdr-auto-output.md`（v5，含成熟度表与路由门）
- 主题上下文：`archives/conversations/lg-h870ds-hdr-demo-20261004.md`（Current State 顶部）
- 任务台账：`TASKS.md`（LG P8.4 色彩优化条目 followup-* 系列）
- 设备协议：`~/src/media-kit-build/lg-api24/LG-DEVICE-LOGCAT-PROTOCOL.md`
- 采集工具：`~/src/media-kit-build/lg-api24/lg-api24-realtime-gpu-phase0-20261008/observe-mks.py`
- 证据根：`~/src/media-kit-build/lg-api24/`（各轮 run/build 目录；C1/C4 关键轮=
  c2-telemetry-r6、c14-chprobe、genbump2 系列；通道判定=
  `lg-api24-realtime-gpu-mks-c14-chprobe-run/channel-verdict.json`）；
  归档索引 `~/src/media-kit-experiments/lg-hdr-evidence-index-20261005.json`
- 构建溯源：`~/src/media-kit-build/lg-api24/genbump-provenance-20261010/`
