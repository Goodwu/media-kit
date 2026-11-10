# P5 无DV设备 reshape 性能定位与优化（LYA 样本）

## Current State

- **立项交接（2026-11-10，自 LG-P84-TARGET-LEASE-20261105 会话派生，Lead 指示换会话继续）**：目标 = 定位并优化 P5-on-LYA metadataReshape 路线的 **0.38fps**（对照同机 P8.4=30fps，80× 异常）。全部背景、端到端流程实证、候选优化清单、红线与环境就绪状态见 `TASKS.md` §P5-NODV-RESHAPE-PERF-20261110（权威）。起始动作 = S1 定位三实验：per-frame 分段时间戳 + 全 instrumentation 关闭对照 + 降分辨率对照。基线证据 `docs/validation/lg-p84-target-lease-20261105/M5-lya-p5-mysterybox/`（外置 `…-m5-lya-p5-20261110`）。设备 LYA 已还原（s5k-lya 在装、属性清空、灭屏）；LG 现装 s5m 不受影响。本文件为新会话唯一上下文；父项目 context 见 `lg-p84-target-lease-20261105.md`。
