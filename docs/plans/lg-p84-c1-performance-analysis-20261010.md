# LG P8.4 · C1 性能分析报告（2026-10-10，followup 计划 v4 C1 交付）

> 数据全部来自去插桩产品构建的实机轮（干净链：216 对象=euv17 期望集、undefined 符号集
> 与金标准双向相等）。本报告区分**实测事实（附文件引用）**与**结构估算/推断**。
> 证据根：`~/src/media-kit-build/lg-api24/`。

## 结论先行

1. **解码→VO 提交链在产品形态下全程实时**：四轮实测（90s P8.4 长片、75s 通道探测轮、
   30s HDR10/P5/P8.4 三内容轮）`decDrop` 与 `voDelayed` 恒零、`vfps` 恒锁源率
   （29.970030/29.970069/24.0）、pos 推进与墙钟同步、零缓冲事件、MKST 违约计数全零。
2. **渲染侧无 per-pass 定量**：vo-passes 属性 string 可读（len=114）但计时采样恒空
   （count=0，18 次读数稳定）——per-pass timing 在本配置不可用（C2 轮判定，V1 审 PASS）。
3. **呈现级定量在本设备不可得（C4 联合收口）**：API 24 设备上全部候选通道逐一实锤死端
   （见 §4）。呈现级验收上限=人工验收（HDR10/P5/P8.4 已通过，2026-10-10）。
4. **链内最大单项名义 GPU 流量=输入侧源尺寸 lease 物化 copy**（约 118MB/帧@3840×1920，
   写+读；结构估算非实测）——即 C3 的候选收益点；其消除需 libplacebo checkpoint 级改动
   （C3 调查结论，见计划文档 §6.4）。

## 1. 数据源（实测轮清单）

| 轮 | 日期 | 素材 | 时长 | 关键数据 |
|----|------|------|------|----------|
| c2-telemetry-r6 | 10-10 凌晨 | p84 长片 | 90s | 46 AVTRACE 样本；104 SF latency 采样；decDrop=0；vfps=29.970030；pos 1.17→91.19（90.02s 时距） |
| c14-chprobe（本轮） | 10-10 下午 | p84 长片 | 75.5s | 38 AVTRACE 样本；pos 1.001→75.008（连续）；decDrop={0}；vfps={29.970030}；全通道探测 52 文件 |
| mt-hdr10-genbump2 | 10-10 中午 | 哔哩哔哩 4K 3840×1920 SMPTE2084 | 30s | decDrop=0 恒零；vfps=29.970069；hal_hdr 单次稳定 |
| mt-p5-genbump2 | 10-10 中午 | P5（dacfd045） | 30s | ACTUAL=nativeDolbyVision；decDrop=0；vfps=24.0（源率） |
| c2-telemetry-genbump2 | 10-10 中午 | p84 长片 | 30s | config49+YUV-P1 armed+A2 拒注入证据行+hal_hdr 单次稳定（12:04:56 进入）+decDrop=0 |

数据文件：
`lg-api24-realtime-gpu-mks-c2-telemetry-r6-run/`（logcat-bound AVTRACE 46 行、
latency-*.txt×104、mksurf-counters.json）、
`lg-api24-realtime-gpu-mks-c14-chprobe-run/`（run-summary.json、channel-verdict.json、
avtrace-lines.txt、各通道 dump）、genbump2 各 run 目录。

## 2. 解码侧（实测）

- **decDrop=0 恒零**：r6 全 46 样本、c14 全 38 样本集合均为 {0}；genbump2 三内容轮同。
- **vfps（estimated-vf-fps，解码→VO 提交链帧率）恒锁源率**：29.970030（p84/HDR10 类
  NTSC 源）、24.0（P5 源）。记录口径：**vfps 非屏幕实际显示帧率**（2026-10-10 用户问询
  更正入档，计划 §3.5）。
- **pos 与墙钟同步**：r6 span 90.02s / 观测窗 90s；c14 span 74.0s / 窗 75.5s；无 >5s
  停顿、无 >5s 日志空洞（c14 sessionHealth.stallsOver5s=0）。
- **无缓冲**：buffering=false 恒定；cacheDur 维持 23–34s 健康水位；vbitrate 活跃
  （5–12.5Mbps，p84 实测值域）。
- **解码器计数器**：`dumpsys media.codec` 在本 ROM 输出 0 字节（r6/r14 一致，ROM 行为），
  解码器侧无系统计数可取；`media.metrics` 服务不存在。

## 3. 渲染侧

- **vo-passes per-pass timing 不可用**（C2 轮核心判定）：属性 string 结构有效
  （len=114）但计时采样 count=0 恒定（18 次读数）→ 无 per-pass GPU 时间数据；
  判读须知：本配置下 stable failure 形态=len=0 而非 error。证据在 C2 轮记录。
- **MKST 桥违约计数全零**（r6 mksurf-counters.json）：frame/horizon-overflow/
  consumed-overflow/idempotent-reacquire/release-failed/nonfinite-pts/latch-ts-invalid/
  stale-drop/identity-violation/fence/retire 全 0——A2 产品化后生命周期纪律无违例。
- **hal_hdr 稳定性**：SDM 单次进入、零翻转（hal_native 仅退出时）——r6/genbump2 轮一致。
- **结构估算（非实测，供 C3 量级参考）**：3840×1920 RGBA16F 单帧 58.98MB；输入侧 lease
  物化 copy 写+读 ≈117.96MB/帧，29.97fps 名义 ≈3.54GB/s——链内最大单项；对比输出侧
  1440×720 RGBA16F 离屏往返 ≈0.5GB/s。GPU 实际 DDR 净流量未经仪器验证（无 GPU timer
  通道），不能由名义值外推帧率收益。

## 4. 呈现级通道死端清单（C4 联合收口，实测）

设备 LG-H870DS（Android 7.0/API 24）播放态逐一探测（c14 轮，channel-verdict.json）：

| 通道 | 识别 | 帧级数据 | 实锤 |
|------|------|----------|------|
| SF `--latency <层>` | 是 | **否** | 3 次采集均仅单行 `16666666`（刷新周期 ns），无帧时间戳三元组；r6 轮 104 采样同 |
| SF `--framestats <层>` | 否 | 否 | 回落默认 dump，无 PROFILEDATA 段（grep=0） |
| SF `--timestats` | 否 | 否 | 回落默认 dump（C4 候选通道死端） |
| SF 完整 dump | 是 | 否 | SurfaceView 层仅瞬时聚合（queued-frames=0 等），无帧序列 |
| `gfxinfo` / `framestats` | 是 | 是（但非视频） | 仅 Flutter UI 线程帧：启动期 5 行逐帧时间戳，60s 播放期间 PROFILEDATA 逐字节冻结；不含 SurfaceView 视频呈现帧 |
| `media.metrics` | — | — | `Can't find service: media.metrics`（服务不存在） |
| `media.codec` | — | — | 输出 0 字节（ROM 行为） |

**结论**：本设备不存在能反映视频呈现路径的系统侧逐帧证据通道。4K30 定量门可达成形态=
解码侧实时定量（§2，已在 4K 3840×1920@29.97 素材 30s/90s 轮达成）+人工验收（已通过）；
呈现级帧率/延迟定量登记为**本设备不可得**（非未做）。

## 5. 已知未知与边界

- 屏幕实际呈现帧率/呈现延迟：无仪器通道，未测，上限=人验（"流畅度好"）。
- GPU per-pass 时间与实际 DDR 流量：无 timer 通道，仅有结构估算。
- gfxinfo 计数器 `Stats since` 与进程年龄不符（1667s vs 进程 4s）：ROM 计数器怪癖，
  已留证（07/28 号文件），不影响本报告结论。
- SDR tone-map 路径的历史卡顿（R25 定性 11.6fps）：独立已知项，不在本产品链（PQ 直通）
  范围内，未在本轮重测。
- `--latency` 对非 SurfaceView 层是否出三元组：未测（超出范围，对本目标无意义）。

## 6. C1 验收对照

计划验收门"性能分析报告成文（含呈现级证据缺口如实登记），数据可溯源"——本报告即交付；
全部数据文件在 `~/src/media-kit-build/lg-api24/` 各 run 目录，通道判定引用到具体文件行。
