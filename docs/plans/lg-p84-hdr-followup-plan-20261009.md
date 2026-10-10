# LG P8.4 HDR 显示线 · 后续工作计划（2026-10-09，v3 按 Critical Reviewer 审核修订）

> 依据链：综合优化审视原文（DIAG-REPORT.txt「综合优化审视」节）→ v1/v2 成文 →
> **v3：Critical Reviewer V2 审核（提案 fail→受限立项 / 计划 pass-with-issues→修订）+
> 用户裁决移除 C0（收益仅 ALU 级，不满足"明显收益"前提）**。
> 本版为执行事实源；复审触发条件见文末。
>
> 前置状态：P8.4 HDR 显示已人验通过（色彩/亮度/流畅度三好）；euv17-fullrng
> 稳定播放（range=1 FULL 已验收配置）。

## 现状快照

- **已达成**：HLG BT.2020 10-bit → MediaCodec surface 解码 → SurfaceTexture →
  libplacebo HLG→PQ（target-peak=1000）→ RGBA16F 离屏 → BT.2020 NCL full-range
  打包 → NV12 config49（VENUS）window → HWC 视频层合成 → 逐 buffer COLOR_METADATA
  (9/1/16) → SDM hal_hdr 稳定 → 面板 PQ 解码。实时播放 decDrop=0，hal_hdr 单次切换零翻转。
- **审视总体判断**：方案已证明"能正确显示"，尚非可长期运行的产品后端；下一步 =
  拆开功能与诊断、补齐输出 owner 生命周期，再测去插桩后的真实性能。
  验收结论维持成立，遗留问题不追溯否定验收。
- **形态**：POC。诊断插桩内嵌、define 矩阵门控、mkst 桥为实验桥、未入库。
- **根因定律**：metadata 身份三元组必须与 buffer 内容严格一致（euv14-rng2 教训）。

## 证据修正（全员须知的记录口径）

1. **readback 是跨进程混合总数，不是上屏帧计数**（PID11546: 2415 + PID11798: 4485）。
2. **两路线显示路径不同，结论不互套**：E-YUV 视频层=HWC 合成实锤；"GLES 合成"仅属 RGB 路线。
3. **readback 本身扰动性能**（v3 增）：性能结论不得来自带 readback 的运行。
4. **截图与上屏渲染参数可能分叉**（v3 增）：video_screenshot 另建 pl_render_params
   （vo_gpu_next.c:1612,1777），截图/另渲染不能冒充上屏实验证据；证据须取自实际播放的
   离屏 FBO 读回或明确同参数路径。

## 架构级决策（审视原文四项，v3 修订口径）

1. **两段式输出（RGBA16F 离屏 + 末级 pass）暂保留**：融合非近期收益
   （1440×720 离屏 ~8.29MB、往返 ~0.5GB/s 名义访问量为结构估算）。
2. **输入侧更大杠杆：OES→全分辨率 RGBA16F lease**（满配 ~225MiB）；融合需帧身份保持
   设计，属中长期。注意：当前路线已是 OES 导入，但 hwdec_surfacetexture.c:1267 仍做
   源尺寸 GPU copy（draw_copy），lease 融合消的是这个。
3. **产品化三职责边界**：输出策略与授权 / YUV 呈现实现 / 精确固件 metadata 适配器；
   "离屏契约"与"窗口契约"拆为独立字段。（审视成文时窗口=PQ/limited；现验收态=
   离屏 full + 窗口 full + metadata FULL(1)，拆分原则不变。）
4. **10-bit 路线四门顺序探针**：分配 → EGLImage 导入可写 → stride 对齐 → HWC 资格。
   EGL window-config 无已知 10bit YUV 选项（已实证）；EGLImage/gralloc 路线未证伪
   也未证可行。

## C 线 · 性能与缩放实验（审视"再测去插桩后的真实性能"+ 4K30 要求）

> v3 修订：C0 已按用户裁决移除（见下节存档）；C 线=遥测→去插桩→lease→4K30。

### C0 · disable_linear_scaling 实验（已移除，2026-10-09 用户裁决）

审核确认其收益仅为省主缩放前 HLG 线性化的 ALU（4K float 中间纹理带宽不省、非预缩小等价物、矩阵/range 后移假设证伪），"明显收益"前提不成立，按用户裁决从工作线移除。
同期否定：两遍 libplacebo（颜色映射本就在主缩放后，无 4K tone-map 可省，反增交接复杂度）。
**重开条件**：C2 遥测显示主缩放前线性化 ALU 占主导时，可用零代码 mpv 选项
（`linear-downscaling=no linear-upscaling=no`，vo_gpu_next.c:2538 已映射）低成本复测；
届时按审核原案的验收两阶段（高频/斜线/运动样本+线性光基线；性能轮关 readback、
先核实 vo-passes 有效性）执行。

## A 线 · 产品化收口（优先级表 1-2 + P1 修复包）

| # | 任务 | 内容 | 验收门 |
|---|------|------|--------|
| A1 | 拆功能开关与观测（P0 小） | readback/P0 观测拆出；`diag_readback_unsupported` 只抑制日志未跳过 ReadPixels 的缺口修复；define 门收敛，off 恒等性逐位保持 | off 构建与产品基线逐位一致 |
| A2 | owner/generation 产品化（P0 阻断） | mkst 桥升 realizer 正式 backend：owner/generation + 硬门 + hook 全生命周期 + metadata 失败语义；显式 init 取代 pthread_once；窗口绑定授权（消"context 重建不继承授权"缺口）；**封死 1×1 首帧 buffer 注入 metadata 后提交**（实锤缺口，唯一 owner） | 生命周期矩阵全格；竞态用例锁定 |
| A3 | P1 修复包（优先级表 4） | swap 错误传播（eglSwapBuffers 返回值忽略；ready=false 仍 swap）、resize 资源（失败旧纹理名滞留）、GL 状态（viewport 未恢复；binding 单保存丢 read/draw 分离；dequeue 失败仍读输出参数） | 各项独立用例 + 回归锁定 |
| A4 | 契约字段拆分（架构级 3 落地） | 离屏/窗口契约独立字段；metadata 适配器独立模块 | 字段与 buffer 内容一致性断言 |
| A5 | V2 收口补审 | 彩色矩阵 pass、range 修复、placeholder 吸收、metadata 注入 + A1-A4 增量 | 独立 V2 无 P1/P2 阻断 |
| A6 | 回归补全 + 入库 | 生命周期矩阵补全；全量回归；授权后按仓库语义化拆分提交 | 全绿；先更新 TASKS/conversation |

**并行约束（v3 增，审核 P2）**：A1-A4 允许并行调查/测试设计，但 context_android.c
等共享文件按文件指定**单一 writer**：先冻结功能/观测及窗口契约接口，再串行集成；
1×1 首帧修复给唯一 owner（A2），A3 不重复承担。

## B 线 · 10-bit 质量保全（优先级表 8，独立研究）

| # | 任务 | 内容 | 验收门 |
|---|------|------|--------|
| B1 | 四门顺序探针 | ①分配（P010/Y210）→ ②EGLImage 导入可写 → ③stride 对齐 → ④HWC 资格；任一门失败即停 | 每门 pass/fail 均有实锤 |
| B2 | 分流（**措辞收紧**） | 当前候选失败→**只关闭该候选**，记录失败门与剩余未知（不外推"全域 10-bit 不可行"）；四门全过→直通设计文档；**是否接受 8-bit 产品终态由用户另行裁决** | 文档化结论，不含越权定性 |
| B3 | 实施轮 | 末级 pass 位深升级 + 契约同步（range 定律适用） | 人验对比 8-bit 基线 |

### B 附 · NV12 量化/抖动研究（优先级表 7，P2）

8-bit 量化无显式 dithering 契约；末级 NV12 量化在 libplacebo RGBA16F 输出之后，
libplacebo 的 dither 不覆盖这一步。独立小课题，结论反哺 8-bit 终态质量。

## D 线 · 解码侧（优先级表 3；**D2 状态修正**）

| # | 任务 | 内容 | 验收门 |
|---|------|------|--------|
| D1 | VUI RPS/HRD 解析差异修正（P1） | fork 内 hevc/ps.c 镜像解析器对照规范逐项核对 RPS/HRD 差异并修正（保留，不因分类已修复而关闭） | 差异清单 + 修正 + 模糊复验 + harness 断言全过 |
| D2 | 分类修复链产品化（**原"color keys 解除决策"已过期关闭**） | color keys 回写+VUI 探测+dst_params 传播的 decoder-origin 分类修复链已在 phase1-precision 完成并实机验证（MKSCOLORKEYS avctx trc=16）；本轮只做产品化回归与清理，**不重开解除决策** | 回归用例锁定；清理项清单 |
| D3 | 上游化决策 | D1 后评估最小上游补丁形态或 fork 长期携带 | 决策记录 |

## E 线 · 条件触发项（不主动排期）

| # | 触发条件 | 动作 |
|---|----------|------|
| E1 | 再现 hal_hdr↔hal_native 震荡 | HandleHDR 判定输入反汇编（sdmcore-disasm.txt 已存档；grep 为 ugrep 别名，用 python/绝对路径工具） |
| E2 | 产品化轮复现横屏黑屏 | 横屏过渡双 mount platform view 竞态专项（已定性待修） |
| E3 | 显示链异常排查需要 | qdmeta-forensics 取证 |

## F 线 · P2 收尾项（随 A 线顺手）

模块隔离 + 日志注释收敛（注释漂移 5 处）；按架构级 3 三职责落地时一并收敛。
另（v3 增）：TASKS.md 旧顶层 status 摘要与最新验收状态不一致处随手同步
（计划采信最新验收）。

## 推荐排序

**A（P0：A1+A2，共享文件串行）→ D1（P1）→ C2（遥测+vo-passes 核实）→ C1 → C3 →
B1 探针 → C4 → B2/B3**；P2 随线；E 挂起；C0 已移除（重开条件见 C 线）。
（审视原序 D1 在 A3 前、独立探针后置；本排序为 Lead 调度调整，等级不变。）

## 风险与约束

1. **commit/push 未授权**：A6 前不得提交。
2. **设备单点**：LGH870DS42e27764 为唯一验收环境；marble 仅作能力对照。
3. **metadata 契约定律**：触及输出格式/打包的改动必须同步三元组标签（验收否决项）。
4. **证据口径四条**：见"证据修正"节。
5. **euv13 人验与 euv17 复测区分**（v3 增）：euv13=用户人验通过；euv17=同配置技术复测
   稳定，人验复核待用户，不自动视为已关闭。
