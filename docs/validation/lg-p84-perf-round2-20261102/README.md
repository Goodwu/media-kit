# LG DV P8.4 性能优化第二轮证据索引（2026-11-04）

任务：`TASKS.md` §LG-P84-PERF-ROUND2-20261104；方案：`docs/plans/lg-p84-perf-round2-20261102.md`；

## 原始流外置归档（仓库减重约定，见 docs/validation/ARCHIVE.md）

每轮的 `samples.ndjson`（sysfs 原始采样）、`commands.ndjson`（adb 收据）、`thermal-logcat.txt`、
`logcat.stderr` 共 75 文件 / 14MB 已外置：
`~/Documents/media-kit-validation-archive/artifacts/lg-p84-perf-round2-20261102/`（含 `MANIFEST.sha256`，
同构子目录）。库内每轮保留承载计时证据的 `flutter-logcat.txt`（MKS-GPU-SAMPLES/MKS-GPU-PASS/MKSURF/
MKS-FUSION 行）与 `summary.json`/`instant-summary.json`/`original-state.json`/`source-identity.json`。
唯一 context：`archives/conversations/lg-p84-perf-round2-20261104.md`（含 critical 复审五轮全过程与终判）。
分支：`perf2/lg-p84`（media-kit/mpv/libplacebo 三 worktree 隔离开发，未提交待授权）。

## 阶段 1：无表融合基线 GPU 占比（CLOSED，估算模型）

| 轮 | 内容 | 有效性 |
|---|---|---|
| `C1` | 对照锚（融合开、无计时） | completed-observation，温度参考锚 |
| `I1/I2/I3` | `--gpu-timing input --yuv-fusion` | 各 1049 PTS[20,55] 样本，零 disjoint |
| `R1/R2/R3` | `--gpu-timing render --yuv-fusion` | 各 3 检查点 stage=frame index=0 |
| `C2` | 对照（计时扰动检查） | completed-observation |
| `occupancy-aggregate.json` | 三对 share 33.093/33.124/33.475%，中位 33.124% | 复审独立复算一致 |

结果：输入复制 5.80–5.92ms、融合 pass 11.73–11.81ms @214MHz；份额模型与 busy 52–53% 粗略一致。
失败现场：`C1-hot-aborted`（热 cap）、`C1-keyguard-refused`、`C1-restore-failed{,-2}`。

## 阶段 2/3：轨道 A（输入侧）

- `F1/F2-rgba16-functional`：`debug.mks.st_lease_rgba16=1` 功能验证（rgba16 chosen、融合正常）
- `A-I1/B-I1/A-R1/B-R1`：UNORM16 同包 A/B——copy +44%、融合 +42%，**观察性否定、提前停止**
- 形态矩阵：MRT=GL 层不可行；OES 直采=设计级风险；调度重构=高风险未实施
- `F2-rgba16-hot-aborted`、`F2-rgba16-adb-drop`：中止现场

## 阶段 2/3：轨道 B（PQ LUT）

- 探针：`tool/native/lg_pq_lut_probe.c`（六变体共享生产 tail；host 自测含 PQ 锚点/进位边界/序列契约）
- run1/2/3：timer 饿死→GPU 队列楔死（`inflight=15`、SIGKILL 挂内核、设备重启恢复；根因 OPEN）
- run4（`pq-lut-probe-run4/`）：批末 flush 版走完循环、verdict=fail（results 481/2160）；部分计时
  identity 7.279 / analytic 8.319 / lut1024-linear 11.577 / lut1024-sqrt 14.991ms；精度相对与绝对 OPEN
  （全屏差异=0 与构造矛盾）。**B 轨=测量未闭合，不能判定实测证伪**（复审校准口径）。

## 复审

team-reviewer-critical 五轮：最终判定"代码修复完成、实机验证待办"的阶段性负结果；无剩余已报告
代码阻断项。归档放行口径见 topic 文件末节。OPEN 项：同包身份收据链、探针挂起根因、修复版探针
输出有效性、精度测量。三仓改动未提交待授权。
