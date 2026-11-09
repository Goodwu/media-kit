# ff-attr：返回首帧延迟归因（PiliPlus dev @ LG-H870DS）

日期：2026-11-03 01:52 – 02:20（Asia/Shanghai）。执行：Verifier（独立复现实例，未改源码/未构建/未提交）。
设备：LG-H870DS（lucye，Android 7.0 / SDK 24），fingerprint `lge/lucye_global_com/lucye:7.0/NRD90U/172921900e77a:user/release-keys`，serial `LGH870DS42e27764`，USB，全程屏 ON 解锁。
被测包：`com.example.piliplus.dev` v2.1.6，`/data/app/com.example.piliplus.dev-1/base.apk`（= 阶段二核对的 `dd07a4a0…cce816` p3c 修后包），`lastUpdateTime=2026-11-02 23:26:08` **轮前轮后两次核对未变**。工作区基线：`baseline-git-status.txt`（分支 feature/dv @ 761e29a8，26 modified + 8 untracked 均为原有 dirty state，本轮未触碰；本轮新增仅 `ff-attr/` 内文件）。

## 0. 结论（先说数）

**DV 源正常 HOME 返回（停留 10 s）：返回命令 → 首个视频帧上屏 = 9960 / 8307 ms（两轮）。**
其中：

| 归因桶 | FF-DV1 | FF-DV2 | FF-SDR1 | 定义 |
|---|---|---|---|---|
| (a) 授权/桥 auth_begin→decoder_window | 247 ms (2.5%) | 219 ms (2.6%) | 0（零授权路径） | **符合预期 <0.4 s** |
| (b) 解码器重建+轨重选（sc→auth_begin + window→Executing） | 110 ms (1.1%) | 139 ms (1.7%) | 282 ms (6.7%) | 含 makeComponentInstance→Executing |
| (c) codec Executing → 首个视频帧 | **8113 ms (81.5%)** | **6451 ms (77.6%)** | **2700 ms (64.0%)** | 输入饥饿 + 关键帧追赶（见 §3 拆分） |
| (d) 返回命令→surfaceCreated（活动恢复） | 1490 ms (15.0%) | 1498 ms (18.0%) | 1238 ms (29.3%) | 其中 adb am 派发 ~1.1–1.4 s 是方法开销 |
| TOTAL 返回→首个视频帧 | 9960 ms | 8307 ms | 4220 ms | |

- **延迟主体是 (c)**：codec 已 Executing 后拿不到首帧。系统侧可再拆两段（事实）：①首次 Executing 用占位配置起步，随后 `codec owns 0/4 input` 输入饥饿，等真实码流格式到达（`output port settings change`）——DV1 5.33 s、DV2 0.32 s、SDR 1.52 s；②真实格式 re-Executing → 首帧——DV1 2.49 s、DV2 5.90 s、SDR 1.08 s。②内部的解码追赶 vs mpv 缓存策略无法再分（mpv 日志不可见，见 §5）。
- **SDR（低码率 720p feed 流）总恢复 4.22 s，段 c 2.70 s，均约为 DV 的 1/2–1/3**，支持"网络/GOP 追赶主导"：同一恢复链在低码率下显著缩短。
- **出现后卡顿（事实）**：首帧后 present 间隔 >2×中位的卡顿窗口：DV1 首帧后 0–3.0 s（最长 gap 230 ms，15 次抖动事件），DV2 首帧后 0–10.9 s（最长 gap 378 ms，5–15 s 区间仍有 ~1 s 周期性 110–220 ms gap，直到首帧后 +4509 ms 才稳定 33 ms 1:1），SDR1 首帧后 0–2.6 s（最长 gap 312 ms）后完全干净。基线（无重建）pause→resume 仅首帧后 0.6 s 内一次 591 ms gap。
- 用户主诉（>5 s 出画面、出来后卡顿几秒、快速返回同样）与本测量一致：DV 8.3–10.0 s 出帧 + 2–4.5 s 卡顿期。

## 1. 方法

- 轮次（均为冷启 deep link `BV1vY4y1N7TY?t=120` 起播、稳定播放 ~32 s、正常 HOME 停留 10 s、`am start` 返回；逐 buffer 清 logcat，轮末全量 dump）：**FF-DV1 / FF-DV2**（DV 4K 3840x1920 源）；**FF-SDR1**（推荐流首卡片，HdrDiag `class=sdr selected=sdrDirect`，1280x720）；**FF-BASE1**（应用内 pause→resume 与 seek 基线，无 HOME）；BASE1B/B2/B3/C 为 seek 方法的失败/污染尝试与补救（§4）。
- 密集采样：返回前 ~1 s 起设备端循环 `ff_sample.sh`（tools/），每次迭代 `dumpsys SurfaceFlinger --latency <层>` + `dumpsys media_session`（包内段落）+ `/proc/uptime` + `EPOCHREALTIME` 自时间戳，持续 24 s。实测周期中位 67–118 ms（≤200 ms 达标），单次最大 231 ms（FF-DV1 一次抖动）。层名 `SurfaceView - com.example.piliplus.dev/com.example.piliplus.MainActivity`。
- 时轴统一：所有事件换算到设备 epoch ms。桥日志 `MKS-HOME-TRACE rt=…(epoch) mono=…(monotonic)` 同行双钟，rt−mono 全程散布 ≤1 ms；SF actualPresentTime 与 mono 同基（SF↔epoch 映射与独立推算差 −7/+4.5/+13 ms，≤1 帧+采样误差）；logcat 墙钟与 rt 同线校准差 0 ms（host/device 同时区）。
- 锚点（logcat）：ActivityManager `START u0`、`java surfaceCreated enter/exit`、dart `authorize begin`、java `authorize result code=ok`、`mkst_ensure_init(lc_verify) exit`、`mkst_create_decoder_window exit …window_active=1`、`makeComponentInstance`、ACodec `Now Executing/Flushing`、`ExecutingState flushing now (codec owns i/4 input…)`、`output port settings change`、`Allocating N meta buffers`。
- **首个视频帧判定**：返回后、surfaceCreated 起，第一条开启"持续串"的 present（800 ms 内 ≥5 条）。排除孤立占位帧：DV1 在 +1786 ms 有 1 条孤立 present（新 surface 上的背景/首合成帧，非视频帧），DV2 在 +1800/+7486 ms 有 2 条。此判定是本报告对"画面出现"的操作化定义。
- `dumpsys media.codec` 在本机（API 24）输出为空（0 行），按任务预案改用 logcat MediaCodec/ACodec 时间戳。
- 每轮 crash 检查：dropbox（data_app_crash/anr/native/SYSTEM_TOMBSTONE）轮前后均 0；pid 轮内不变（25264/27657/30134/1273）。
- 工具（全部在 `tools/`，可复跑）：`ff_sample.sh`（设备端密集采样）、`run_ff_round.sh`（DV/SDR 轮驱动）、`run_ff_base.sh`（BASE 驱动）、`run_ff_base_seek.sh`/`run_ff_base_seek2.sh`（seek 尝试）、`analyze_ff.py`（分析）。每轮产物：dense-samples.txt（或 dense-a/b/b2/c）、logcat-full.txt、host-events.ndjson（host+device 双时间戳）、analysis.json、presents.csv、intervals.csv、sample-*、截图。

## 2. 逐段时间线（相对返回命令 t0=0；epoch ms）

FF-DV1（pid 25264）：

| 事件 | t (ms) | 段 |
|---|---|---|
| （HOME 时 sd_exit −11735 / mkst_shutdown exit −11683，供参照） | | |
| 返回命令 marker | 0 | |
| ActivityManager START u0 | +1389 | am 派发 1389（方法开销） |
| java surfaceCreated enter（surfaceGeneration 1→2） | +1490 | AMS→sc 101 |
| dart authorize begin | +1542 | sc→begin 52 |
| java authorize result code=ok | +1690 | 授权 148 |
| mkst_create_decoder_window exit window_active=1 | +1789 | result→win 99 **(a=247)** |
| makeComponentInstance / Now Executing | +1795 / +1847 | win→exec 58 **(b=110)** |
| （孤立占位 present） | +1786 | 非视频帧 |
| ACodec flush `owns 0/4 input`（输入饥饿结束点） | +7180 | 饥饿 5333 |
| output port settings change → Allocating 16 → Now Executing | +7294 → +7468 | 真实格式到达 |
| **首个视频帧 present** | **+9960** | **(c=8113)** |
| present 稳定 33 ms 1:1 | +12062 | 首帧→稳定 2102 |
| media_session 状态 | −1121 s2（暂停）→ +1487 s3（resume）→ +2059 s6（缓冲，5.53 s）→ +7593 s3 | |

FF-DV2（pid 27657）：START +1415 → sc +1498 → begin +1576 → result +1715 → win +1795 → exec +1856（a=219，b=139）→ flush `owns 0/4` +2175（饥饿 319）→ port change +2279 → re-Executing +2409 → **首帧 +8307（c=6451）** → 稳定 +12816；状态 +1545 s3 → +2088 s6（0.35 s）→ +2437 s3；孤立占位 present +1800/+7486。

FF-SDR1（pid 30134，零授权：全 logcat authorize=0、mkst 行=0）：START +1141 → sc +1238（surfaceChanged 1440x810）→ MediaCodec create +1452 → makeComponentInstance +1465 → Executing +1520（b=282，a=0）→ flush `owns 0/4` +3040（饥饿 1520）→ port change +3099 → re-Executing +3140 → **首帧 +4220（c=2700）** → 稳定 +4602；状态 +1317 s3 → +1823 s6（1.43 s）→ +3252 s3。

基线 FF-BASE1（pid 1273，DV 源，应用内、无 HOME、解码器不重建）：
- **pause→resume**：resume 命令 → 首个新 present **131 ms**；随后一次 591 ms gap，+816 ms 起 33 ms 稳定。窗口内 0 条 authorize/mkst/surfaceCreated/codec 实例化行（chain 完整不触发）。
- **原地 seek（FF-BASE1C，rewind 键实测 +11.6 s 前跳，见 §4 偏差）**：命令后旧画面继续 present 至 +2292 ms → 冻结 1614 ms（+2272→+3886）→ 新位置稳定播放（s3@pos126893 发布于 +2376 ms）；全程无 makeComponentInstance（仅 flush）。可见冻结 ~1.6 s，即"关键帧重取"参照成本。

## 3. 段 (c) 内部拆分（事实与推断分开）

事实（logcat+SF）：

| 轮 | 首次 Executing→flush（输入饥饿时长，flush 时 owns 0/4 input） | port change→re-Executing | re-Executing→首视频帧 | c 合计 |
|---|---|---|---|---|
| FF-DV1 | 5333 ms | ~188 ms | 2492 ms | 8113 ms |
| FF-DV2 | 319 ms | ~314 ms | 5898 ms | 6451 ms |
| FF-SDR1 | 1520 ms | ~41 ms | 1080 ms | 2700 ms |
| 基线 seek | —（0 ms，无需重开流） | — | 冻结 1614 ms | 1614 ms |

- 饥饿段直接证据：flush 行 `codec owns 0/4 input`（三轮返回链全部如此）＝codec 起来后拿不到输入；随后 `output port settings change` + 输出 meta 缓冲重配（DV 13→16、SDR 22→13）＝真实码流格式此刻才到达。DV1 该段 5.3 s、SDR 1.5 s、DV2 仅 0.3 s（网络抖动自然方差）。
- re-Executing→首帧段：DV 2.5–5.9 s vs SDR 1.1 s vs 应用内 seek 1.6 s 冻结。4K 高码率显著更长，与"从关键帧解码追到 resume 点（GOP 追赶）+ mpv 缓冲起播条件"一致。
- 推断（无法从系统侧证实的部分）：②段内部解码耗时与 mpv 起播缓存策略（如 demuxer-cache 等待）的比例不可分；PiliPlus 不转发 mpv 日志，vo/缓存行为不可见。GOP 长度未测（需流侧分析，超出本任务）。

## 4. 偏差、失败尝试与未验证项

1. **adb am start 派发开销**：t0→AMS START = 1389/1415/1141 ms，是脚本方法的固定开销（真实用户点按更快）；真实系统成本为 AMS→surfaceCreated 83–101 ms。d 桶按定义含此开销，已在表中拆出。
2. **BASE1B（seekbar 微拖 ±25 px）无效**：无 seek 发生（present 连续、零 flush、位置不变）——±2 s 需 ~2 px 精度，不可行。BASE1B2：本构建 `media dispatch fast_forward/fast-forword` 均报 `unknown dispatch code`（usage 自身拼写即 fast-forword，LG 构建实际只接受 rewind 等少数键）。保留两目录为失败尝试。
3. **BASE1B3 污染**：rewind 发出前 ~25 s，播放器在无输入窗口（02:07:46–02:08:11，无采样/logcat 覆盖）内位置自行 142008→307812 并进入缓冲，触发未观测。该轮仅记录"远跳+缓冲中 rewind"现象：+12 s 内仅零星 present（无持续串）。**未验证项：该跳变原因。**
4. **BASE1C 的 rewind 键被应用映射为 +11.6 s 前跳**（发布位置 115181→126822，名义 rewind 应后退）——方向/幅度与任务 ±2 s 规格不符，作为"无解码器重建的关键帧重取"参照仍有效，但幅度偏差如实记录。
5. SDR1 返回后 present 中位 49 ms vs 返回前 33 ms（分辨率 1280x720 未变、码流参数行无变化）——帧节奏差异原因未定（可能源帧率/丢帧呈现），如实记录为未解释观察。
6. `media session position` 仅状态切换时发布，不能作连续进度证据（已知局限，密度采样中仅用于状态序列）。
7. SF `--latency` API 24 可用，未触发 PP-E1 的同名空层伪影（SDR1 首帧正常检出）；未动用 screenrecord 备选路径。
8. 唤醒态设备时钟（monotonic 与 epoch）无漂移迹象（rt−mono 散布 ≤1 ms）；若轮中发生 suspend 分析无效——轮中设备全程唤醒（未发生）。
9. 本报告只覆盖 DV 双轮+SDR 单轮+基线；未做快速返回（方法F）密集轮、1080p 以下画质、PiP/听视频（任务范围外）。

## 5. 产物清单（`ff-attr/`）

- `FF-DV1/ FF-DV2/ FF-SDR1/`：dense-samples.txt、logcat-full.txt、logcat-pre-home.txt、host-events.ndjson、driver.log、analysis.json（锚点/段/归因/状态序列）、presents.csv（全 present 序列 epoch+mono）、intervals.csv（首帧后逐间隔）、sample-*（play_start/pre_home/during_home×2/post_return_late）、after-launch/after-return 截图、launch/return-output、focus/screen。
- `FF-BASE1/`（dense-a.txt=resume 相位、dense-b.txt=无效拖拽、analysis.json）、`FF-BASE1B/B2/`（失败尝试保留）、`FF-BASE1B3/`（污染轮+analysis.json 说明）、`FF-BASE1C/`（有效 seek 参照：dense-c.txt、analysis.json、logcat-full.txt、pre/post-seek 截图与 sflatency）。
- `tools/`：见 §1。`baseline-git-status.txt`。
