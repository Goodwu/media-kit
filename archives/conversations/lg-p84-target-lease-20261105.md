# LG P8.4 目标尺寸 lease（perf round 3）

## Current State

- **待办 / 新会话接手入口（2026-11-05）**：方案与环境交接已定稿
  `docs/plans/lg-p84-target-lease-20261105.md`（自包含：worktree/构建链/设备协议/
  round2 事实基础/设计两裁决点/约束清单/M0-M5 阶段门/否决条件）。前置任务
  perf round 2 已归档提交（media-kit `3b7fd8ae`、mpv `0206c931ac`，perf2/lg-p84
  本地未推送；复审与 specialist 全文在 `lg-p84-perf-round2-20261104.md`）。
- **第一步清单**：①核主树 git status（另一 agent 的 HOME 任务是否仍在）与三 worktree
  干净态；②读方案文档§三的两个设计裁决点（lease 下游声明 A1/A2、量化次序数值门），
  对照 `vo_gpu_next.c:1166-1241` 融合门与 libplacebo renderer 采样语义做 M0 裁决；
  ③M1 起按阶段门推进，每段产物回写本文件与方案文档。
- **红线**（继承 round2 复审与用户要求）：帧身份/退休契约、updateTexImage 调度、
  A/V 同步不动；不伪报尺寸绕过 crop 门；等比缩放之外回退源尺寸 lease；≥10% 为验收
  目标非预测；实机冲突等待重试；每轮前 md5 门；收尾前 critical 复审；提交需授权。

## Findings

- 收益模型：copy 面积比 0.484，若线性则 copy 5.83→2.82ms、总 -17.1%、新份额 19.3%
  （specialist 排序首推；模型≠承诺，copy 将从 identity 变真滤波）。
- Adreno530 float16 快路径已证（UNORM16 同带宽 +44%/+42% 否定）→ lease 保持 RGBA16F。
- 等比判定：本片 3840×1920 与目标 2672×1336 同为 2.0 全帧，适用；其余几何回退。

## Decisions

- 任务立项（2026-11-05，用户指示新会话开启）；方案文档为事实源，裁决点 A1/A2 待
  新会话 M0 定夺并回写。

## Review

- 尚未实施；M5 收尾前 team-reviewer-critical 必做；探针可信性修复为并行小包不阻塞。
