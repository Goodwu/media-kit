# phase3-poc：终版构建 + keyframe-resume PoC 实机验证（PiliPlus dev @ LG-H870DS）

日期：2026-11-03 20:36 – 21:20（Asia/Shanghai）。执行：Verifier（独立验证实例；未改源码、未提交）。
设备：LG-H870DS（lucye，Android 7.0 / SDK 24），fingerprint `lge/lucye_global_com/lucye:7.0/NRD90U/172921900e77a:user/release-keys`，serial `LGH870DS42e27764`，USB，全程屏 ON。中途设备一次 USB 掉线（20:31 前后，总线无设备），用户重插后恢复；掉线期间已完成基线记录与构建启动，无轮次受影响。

## 0. 结论（先说数）

**PoC 的 recovery-seek 在全部 7 轮实机 HOME 返回中一次都没有触发（0 条 `recovery-seek` 日志，含 skip/fail）。**
根因（源码级定位，非推断）：恢复 seek 的触发前提 `hadPreviousOutput = bound != null || previousInFlight != null`（`android_video_controller/real.dart:1597`）在真机 HOME 路径上恒为 false——surface 在 HOME 时被独立的事务 detach（`vid=no`/`vo=null`/`wid=0`，见 KN1 trace `detach decision → apply wid=0 → detach reference released`），返回 rebind 到达时 ledger 已无 bound/in-flight owner（trace：`bind branch=rebind … boundWid=null … previousInFlightWid=null stopPreviousFirst=false`，全部轮次一致）。即使 KF 快速链式返回（方法 F），Java `surfaceDestroyed enter`（marker+1114 ms）→ Dart detach 完成 → `surfaceCreated enter`（+1981 ms）仍先于 rebind，detach 总是赢。
因此：**返回→首帧 ≤1500 ms 目标未达成且未被 PoC 机制触碰**；实测返回→首帧（AMS 口径）KN=5230/4703/9804 ms、KF=12539/12875 ms、KP（暂停保持轮，首帧由 play 键触发）=22671 ms。KN 两轮相对 ff-attr 基线（9960/8307 ms）的改善**不能归因于 PoC**（机制未触发，属网络方差；KN3 即回弹到 9804 ms）。

其余判据全部通过：授权链闭合（Dart begin/result + Java enter/result code=ok）、零 `bridge not initialized`、HEVC MediaCodec 重建（每 HOME 轮恰 2 次 = 起播 1 + 返回 1；KS1 手动 seek 轮 1 次无重建）、轮内同 PID、零 FATAL/ANR、dropbox 零新增；KP1（修正命令后）暂停保持断言通过（返回后 state=2、position 冻结、零视频帧，直到 `media dispatch play`）。

## 1. 构建身份

| 项 | 值 |
|---|---|
| 仓库 HEAD | `761e29a84203e5612e7e715a7796a1ac599bbc5b`（feature/dv）；工作树基线 = A2 终版 + 插桩处置 + PoC，26 modified + 8 untracked 均为原有 dirty state，轮后复查 `git status` 与源文件 SHA256 **完全一致**（`build/source-sha256.txt`，13 个关键文件） |
| PiliPlus dev 构建 | `tool/build-android-test.sh --tag piliplus-p3d-kf --app-dir /Users/wuweiwei1/src/PiliPlus -- --dart-define=MEDIA_KIT_ANDROID_SURFACE_TIMELINE=true`（flutter 3.47.8，JAVA_HOME openjdk@17，ORG_GRADLE_PROJECT_dev=true） |
| PiliPlus APK | `piliplus-p3d-kf-release.apk` SHA256 `8692b33d5c82487528749524ab7fb2d994564ec24f0d3ed1074a043b57e45bf0`（native verification `status=verified`，JAR SHA256 `22bc9306…53fcfd5`） |
| Lab 存档构建 | `--tag p3d-kf-lab --platform-view --local-source /sdcard/Android/data/com.example.media_kit_hdr_lab/files/hokkaido-p84.mp4 -- --dart-define=MEDIA_KIT_ANDROID_SURFACE_TIMELINE=true --dart-define=MEDIA_KIT_ANDROID_HDR_PREFER_CONVERT=true --dart-define=MEDIA_KIT_ANDROID_HDR_DIAGNOSTICS=true`（P0 define 集，见 p0-trace/summary.md L120）；仅存档未装机 |
| Lab APK | `p3d-kf-lab-release.apk` SHA256 `0500739197357e0bcd6b41c0195b05b5c377798cdfe608f5510c406a18b1d707` |
| 装机（LG） | 装前核对：`dd07a4a0…cce816`（p3c）、lastUpdateTime 2026-11-02 23:26:08、`/data/app/…dev-1/base.apk`；装后：`adb install -r` Success、lastUpdateTime **2026-11-03 20:49:21**、`/data/app/…dev-2/base.apk`，pull 回读 SHA256 = `8692b33d…57e45bf0` 与构建产物一致（`build/install-verify-lg.txt`） |
| Java 诊断门 | 装前 `setprop debug.mks.home_trace 1`（getprop 核验 1；重插后曾丢失，重设）；轮后还原 0 并 force-stop |

构建日志：`build/build-piliplus-p3d-kf.log`、`build/build-lab-p3d-kf.log`（首次启动构建因 PATH 含空格项（`/Library/Application Support/Yunshu/…`）未加引号致 `env` 解析失败，已修正重启，最终构建干净）。

## 2. 轮次与判据表

轮次协议：DV 源 deep link `BV1vY4y1N7TY?t=120` 冷启、播放 ~32 s（墙钟；净播放位置见下）、HOME 10 s（KN/KP）或链式快速返回（KF 方法 F：`am start -a MAIN -c HOME --activity-no-animation; am start -n <ACT> --activity-no-animation`）、返回后密集采样 26 s（SF `--latency` + media_session，实测周期中位 64 ms / max 179 ms）。

| 轮 | 触发→sc (ms) | sc→首帧 (ms) | **触发→首帧 (ms)** | codec Exec→首帧 | 首帧→稳定 | 授权 begin→result (ms) | sd→sc (ms) | recovery-seek | 同PID | FATAL/ANR | bridge not init | HEVC MCI |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| KN1 | 927 | 4303 | **5230** | 3985 | 529 | 148 | — | **0 条** | ✓ | 0/0 | 0 | 2 |
| KN2 | 744 | 3959 | **4703** | 3678 | 2269 | 120 | — | **0 条** | ✓ | 0/0 | 0 | 2 |
| KN3 | 655 | 9149 | **9804** | 8873 | 458 | 109 | — | **0 条** | ✓ | 0/0 | 0 | 2 |
| KF1 | 1981 | 10558 | **12539** | 9427 | 3074 | 1 | 867 | **0 条** | ✓ | 0/0 | 0 | 2 |
| KF2 | 2439 | 10436 | **12875** | 9515 | 3038 | 1 | 841 | **0 条** | ✓ | 0/0 | 0 | 2 |
| KP1 | 1166 | （暂停期无帧；play 键后 <0.6 s） | **22671**（t0→首帧，其中暂停保持 ~21 s） | — | 745 | 65 | — | **0 条** | ✓ | 0/0 | 0 | 2 |
| KS1 | —（无重建） | — | **9123**（rewind 键→新帧） | — | — | — | — | 0 条 | ✓ | 0/0 | 0 | 1 |

- 触发→sc（surfaceCreated enter）含 adb `am start` 派发开销（KN ~0.7–0.9 s，KF 链式两跳 ~2.0–2.4 s，AMS 口径固有开销，与 ff-attr 口径一致）。
- KP1 的 22671 ms = 返回后暂停保持 ~21 s + `media dispatch play` 派发→首帧（<0.6 s）；判据看的是暂停保持（通过），不是该总数。play 的 device_ms 时间戳在 adb 返回后打点（偏置 ~0.2–0.5 s），state=3 发布（+22556 ms，pos 138571→138705）与首帧（+22671 ms）实际紧跟真实派发。
- KS1 为对照轮（手动 media 键小跳），rewind 生效（position 发布 139226、s6 缓冲 8.25 s），命令→新帧 9123 ms，其中冻结 7997 ms、旧画面尾巴 1126 ms；**远慢于 phase2 SK-DV-1 的 2993 ms**，差值由本轮网络（缓冲窗口 8.25 s vs SK-DV-1 的 ~0.5 s）主导；落点仍精确（无回退）。手动 seek 修复不在本 PoC，此轮仅记录量级作对照：结论是 PoC 未改变手动 seek 行为（无 recovery-seek 参与、无重建）。
- 净播放位置（触发时刻，来自 HOME 期间 state=2 发布或返回后首个推进 position）：KN1 145.1 s / KN2 146.4 s / KN3 145.9 s / KF1 ~132→142.7 s / KF2 ~137→147.8 s / KP1 138.6 s（pause 键时刻）/ KS1 rewind 落点 139.2 s。任务前置">150 s"未严格达成：起播缓冲吃掉 ~8–15 s，32 s 墙钟对应净播放 ~20–26 s；对结论无影响（均为 GOP 中段、20 min 长源中段）。

## 3. 逐轮判据明细（V2 验收协议）

1. **授权链闭合**：7/7 轮 Dart `authorize begin`+`authorize result code=ok` 与 Java `authorize enter/result code=ok` 齐全；零 `bridge not initialized`；HEVC `makeComponentInstance` 每 HOME 轮恰 2 次（起播+返回重建）、KS1 恰 1 次。KF 轮 begin→java result 1 ms（热路径，enter 行存在）。KN2 另有 4 次 `OMX.google.vorbis.decoder` 实例化（返回后 ~10 s，应用侧音频/广告噪声，非本链）。
2. **恢复 seek 生效**：**全部失败——0 条 begin/complete/skip/fail**。skip reason 无从记录（谓词在 `_seekKeyframeResumeAfterRebind` 调用前为 false，false 分支无日志——可观测性缺口，见 §6）。证据：各轮 `logcat-full.txt` grep 计数 0；`bind branch=rebind … boundWid=null … previousInFlightWid=null`（KN1/KF1 全 trace 见 `analysis-stdout.txt` 与 logcat）。
3. **首帧**：见 §2 表。AMS 口径（触发命令→首新帧 present）最好 4703 ms（KN2），全部 ≫1500 ms 目标。surfaceCreated→首帧：KN 3959–9149 ms、KF 10436–10558 ms——延迟主体仍是 codec Executing→首帧（3678–9515 ms，GOP 追赶+网络），与 ff-attr 归因一致。
4. **回退**：不适用（无 recovery-seek）。事实回退=0：返回后首个推进 position 与恢复前 position（HOME 期间 state=2 发布）差 KN1 +148 / KN2 +19 / KN3 +477 ms（精确恢复，亚秒级，属发布时点差而非回退）。KF 轮分析的 vs_pre_restore +27.5/+32.1 s 是**陈旧发布污染**（pre_restore pos 为起播时刻的旧值 115.2 s，非真实回退），已如实标注。音频可听回退未测（机制未触发，无恢复点）。
5. **稳定性（首帧后 present 间隔）**：首帧后 0–5 s 有 1 次大 gap（max 427/279/459/346/297/181/132 ms），5–15 s 窗口全部干净（中位 33 ms、max ≤198 ms、judder ≤3）。15–22 s 窗口：KN1/KN2 干净（137/155 帧）；KN3/KF1/KF2/KP1 因首帧晚于 +9–13 s、密集采样窗（26 s）提前结束而**无全覆盖**（覆盖 12–15 s，缺口 0–3 s，方法限制如实报告）。KP1 首帧后实际仅 ~2.5 s 在窗内（play 键在 +21.4 s）。
6. **同 PID / FATAL / ANR / 暂停保持**：7/7 轮 flutter pid 单一（26249/30335/2971/6936/9547/17166/19847）、dropbox 轮前后均 0、零 FATAL/ANR。KP1 暂停保持：返回后 +8/+12/+16 s 三次断言 state=2、position=138571 冻结、断言窗内零视频帧；`media dispatch play` 后 position 推进 +134 ms（138705）并上帧（发布→首帧 115 ms）。
7. **对照基线**：ff-attr FF-DV1/FF-DV2 返回→首帧 9960/8307 ms。本 PoC 轮 KN 5230/4703/9804 ms——均值 6579 vs 9134 ms（−28%），但因 recovery-seek 全程未触发，该差异**不可归因 PoC**（网络方差；KN3 与基线持平）。KF 快速返回 12539/12875 ms 反而劣于正常 HOME 基线（detach 清缓存后立即重建，GOP 追赶更长）。

## 4. 方法失败与补救（如实保留）

- **KP1/KS1 attempt1（`*-attempt1-wrong-dispatch-cmd/`）**：任务卡给的 `cmd media_session dispatch pause/rewind` 在本机（API 24）返回 `No shell command implementation.`，为 no-op——KP1-attempt1 的"pause"实际是应用生命周期暂停（HOME 时 state=2 在返回前 ~1 s 才出现，且返回后自动恢复，"仍暂停"断言失败），KS1-attempt1 rewind 零效果（30 fps 连续、无 gap、无 position 变化）。phase2 ff-attr/ff-seek 实际用的是 legacy `media dispatch <key>`（run_seek_round3.sh L169），已改用并重跑（现场先以空闲 app 验证 `media dispatch pause` 生效：state=2、position 冻结）。两 attempt 目录保留为方法失败证据。
- 慢轮（首帧 >9 s）的 15–22 s 稳定窗无全覆盖（§3.5）；KP1 修正轮 `paused-check` 双采样间隔 3 s×2，足以证明 position 冻结。
- KN2 起播段 `position=115181` 等"stale 发布"：PiliPlus 稳定播放中不重复发布 PlaybackState（与 phase2 一致），分析时用 state 变迁时的发布值，KF 轮 pre_restore 污染已标注。

## 5. PoC 未触发的源码级证据链（供 Lead 复核）

1. 谓词：`media_kit_video/lib/src/video_controller/android_video_controller/real.dart:1597` `final hadPreviousOutput = bound != null || previousInFlight != null;`
2. 全轮 trace：`bind branch=rebind wid=<W> boundWid=null boundSurfaceGeneration=null previousInFlightWid=null stopPreviousFirst=false`（`logcat-full.txt` grep `bind branch`）。
3. HOME 侧独立 detach 先行：`event SurfaceDestroyed … → detach requested → detach decision isCurrentOutput=true → apply wid=0 vo=null vid=no（property complete vid=no）→ detach reference released`；KF1 时间线 sd_enter=marker+1114 ms、sc_enter=+1981 ms（sd→sc 867 ms，KF2 841 ms），Dart detach 在窗口内完成。
4. 结论：`vid=no`（HOME detach）确实清了 mpv 缓存视频区间（首帧 4–13 s 的 GOP 追随与 ff-attr 归因一致），但 PoC 的"真实 runtime 重建"判定只看 bind 事务自身的前任 owner，覆盖不了"detach 已在前台外完成"这一真机主路径。修复方向（供 Lead 裁决，本 Verifier 未改代码）：把"最近一次 stop/detach（vid=no）发生过且之后无完整 open"纳入 hadPreviousOutput 语义，或谓词 false 时也发出带 reason 的 trace（可观测性）。

## 6. 偏差与未验证项

- **未验证**：recovery seek 生效时的首帧收益/回退量/audioPts 语义（实机从未触发，PoC 核心主张均无实测数据）；音频可听回退测量方法（依赖触发后的 `audioPts` 采样，未获得样本）。
- **观测缺口**：`shouldSubmitKeyframeResumeSeek` false 分支无日志，无法从日志区分"未考虑"与"考虑后拒绝"（本次靠 bind-branch trace 补证）。
- 触发→首帧的 AMS 口径含 adb 派发 ~0.7–2.4 s（任务已知口径）；本报告未另行扣除。
- 本机构建 `dumpsys media.codec` 为空（API 24，phase2 已知），codec 证据全部来自 logcat MediaCodec/ACodec/OMXMaster 行。
- Lab APK 仅构建存档未装机未跑轮（任务规定）。
- 设备一次 USB 掉线由用户重插恢复（时间点在装机前）；轮次期间无异常断连。
- 工具：`tools/run_poc_round.sh`（轮驱动，含修正后的 `media dispatch`）、`tools/analyze_poc.py`（分析，KS 分支复用 phase2 最长 gap 法）、`tools/ff_sample.sh`（沿用 ff-attr 密集采样器）。每轮产物：`logcat-full.txt`、`dense-samples.txt`、`analysis.json`、`presents.csv`、`intervals.csv`、`driver.log`、`host-events.ndjson`、截图与 sparse samples。

## 7. 设备与工作区还原

- `debug.mks.home_trace` 还原为 0（getprop 复核）；`com.example.piliplus.dev` force-stop；屏幕保持 ON/Awake（未改设置；未改其他系统属性）。
- 设备上保留：p3d-kf 包（未卸载，`/data/app/…dev-2`，lastUpdateTime 2026-11-03 20:49:21）——如需回 p3c 请另行指示。
- 工作区：`git status` 与轮前基线完全一致（仅新增本目录 `phase3-poc/` 内文件）；13 个关键源文件 SHA256 复核不变。未提交任何内容。
