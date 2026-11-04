# P3 阶段二 (b)：Lab 全矩阵实机验收（修后包 p3c-a2）

- 日期：2026-11-02（设备本地时间 Asia/Shanghai；轮次执行窗口 22:31–23:03）
- 角色：Verifier（只做复现/测试/证据采集；不改源码、不构建、不提交）
- 设备：LG H870DS（LG G6，Android 7.0 / API 24，NRD90U），serial `LGH870DS42e27764`
- 包：`com.example.media_kit_hdr_lab`（Lab）
- 本目录之外未写任何文件；每轮产物在 `N1..N3, F1..F5, P1, O1, O1b, trial/T0-mediakey/`（`logcat-full.txt`、`timeline.md/json`、`analysis.md/json`、`host-events.ndjson`、`driver.log`、`screen-*.txt`、`focus-after.txt`、`fast-interval.txt`（F 轮）、`sf-pre-home.txt`/`sf-post-return.txt`（N1/F1））
- 修前对照分析（只读 p0-trace 与 p3/phase1/smoke-prefix，不写回原目录）在 `prefix-baseline/`

## 0. 结论（先读）

**10/10 可执行轮全部 PASS**（N1–N3、F1–F5、P1、O1）；O1b 为满足"tap 后 ≤1 s HOME"目标补跑的加严轮，实际发生 **fail-closed 分支**（会话 10 s 超时错误事件、返回后无视频输出、无 bridge 激活、**无崩溃、PID 延续**）——按任务卡要求作为 O1 的实际分支之一如实记录，不判 PASS/FAIL。所有轮同 PID、零 FATAL/ANR/tombstone、零 `bridge not initialized`、零 `yuv420p10`；返回后 `ensure_init ready=1` + `owner_key` 与 HOME 前一致 + MediaCodec/OMX 重建 + `pixelformat: mediacodec` + `active-importer=surfacetexture device_registered=1` + fused 路由恢复。
**判据 3（resume 后帧推进 ≥15 s）在 Lab 上不可满足**：`Video` 组件默认 `pauseUponEnteringBackgroundMode=true` 且 `resumeUponEnteringForegroundMode=false`，Lab 无任何非破坏性 pause/resume 方法（源码核查 + 实测，见 §4）；按任务卡预案记"Lab 无法 resume，帧推进验证由 (c) PiliPlus 承担"，已记录返回后 swap/frame_id 出新帧（重建后 fused 仍帧 2 条，frame_id=34）。

## 1. 装机身份核对（开工时与结束时各一次，三项均未变）

| 项 | 开工（22:26–22:28） | 结束（23:10） |
|---|---|---|
| `pm path` | `/data/app/com.example.media_kit_hdr_lab-2/base.apk` | 同 |
| lastUpdateTime | 2026-11-02 22:11:56 | 同 |
| SHA256（pull 回 Mac 计算） | `46c2215418810497e9c6b7a8a68023cf77a554ae97a63c6a1f75f2690019b3f0` | 同（`/tmp/verifier-p3p2/lab-base-end.apk`） |

## 2. 环境、方法与基线

- 主机：darwin 27.2.0 arm64；adb 与 p0 轮同一工具链。主机/设备时钟差约 +1.1 s（设备快），仅影响 host 命令时刻映射；判据全部使用设备自身 `rt=`（CLOCK_REALTIME ms）。
- 驱动：`run_lab_round.sh`（本目录；由 p0-trace `run_round.sh`/`run_round_fast.sh`/phase1 `run_round_smoke.sh` 合成：**逐 buffer 清** logcat、四种模式 normal/fast/pause/openhome、可选 SF dump 与媒体键注入、dropbox 前后计数）。每轮 `am force-stop` 冷启 → `am start` → 4 s → tap(1440,720) → 播放 `PRE_HOME_WAIT=20 s`（≥15 s 帧推进确认）→ HOME → （正常轮 10 s）→ `am start` 返回 → 观察 `POST_WAIT=22 s` → `exec-out logcat -d -v threadtime -b all`。逐轮前确认唤醒/解锁（`screen-before.txt`）。
- 分析：`analyze_round.py`（每轮 `analysis.md`/`analysis.json`，全部判据带 logcat 行号）；时间轴 `make_timeline.py`（p0-trace 工具原样使用）；快速轮 `fast_interval_check.py`。
- 工作区基线：开工记录 `git status`（25 条，含实现文件 M 状态，为修复合工作的既有 dirty state）+ 4 个关键实现文件 MD5；结束时 `git status` diff 为空、实现文件 MD5 不变（仅本目录新增未跟踪产物）。`/data/tombstones/` 不可读（Permission denied，API 24 无 root），崩溃以 logcat crash buffer（`-b all` dump 内）+ `dumpsys dropbox` 前后计数 + F 级日志行替代，全部为 0。
- 轮前硬解起点确认（见各轮 `analysis.md` Pre-HOME 节）：`HDR_SESSION_REPORT … hwdecCurrent=surfacetexture` + `mkst_create_decoder_window exit … result=ok` + time-pos 冻结值 19.7–20.8 s（P1/T0 同）。O1/O1b 按设计在起点前 HOME（见 §6）。

## 3. 判据表

（`C3` 列为实际记录：Lab 返回后处于暂停，帧推进判据移至 (c)；`O1b` 的 C2 为"无 bind"，非桥未初始化失败。）

### 逐轮判据表

| 轮 | PID | 硬解起点 | C1 时间链 | C2 返回后 | C3 帧推进 | C4 错误 | C5 进程 | C6 HDR | C7 快速轮 | 拆除簇 | 判定 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| N1 | 493 | PASS | PASS | PASS | 暂停(Video widget) 冻结 20.0s; swap 2 帧 frame_id [34] | PASS | PASS | PASS | n/a | 0 | PASS |
| N2 | 1013 | PASS | PASS | PASS | 暂停(Video widget) 冻结 20.0s; swap 2 帧 frame_id [34] | PASS | PASS | PASS | n/a | 0 | PASS |
| N3 | 1543 | PASS | PASS | PASS | 暂停(Video widget) 冻结 20.2s; swap 2 帧 frame_id [34] | PASS | PASS | PASS | n/a | 0 | PASS |
| F1 | 1862 | PASS | PASS | PASS | 暂停(Video widget) 冻结 20.5s; swap 2 帧 frame_id [34] | PASS | PASS | PASS | sd→sc 712 ms | 6 | PASS |
| F2 | 2320 | PASS | PASS | PASS | 暂停(Video widget) 冻结 20.1s; swap 2 帧 frame_id [34] | PASS | PASS | PASS | sd→sc 610 ms | 0 | PASS |
| F3 | 2807 | PASS | PASS | PASS | 暂停(Video widget) 冻结 19.9s; swap 2 帧 frame_id [34] | PASS | PASS | PASS | sd→sc 626 ms | 0 | PASS |
| F4 | 3225 | PASS | PASS | PASS | 暂停(Video widget) 冻结 19.7s; swap 2 帧 frame_id [34] | PASS | PASS | PASS | sd→sc 575 ms | 0 | PASS |
| F5 | 3565 | PASS | PASS | PASS | 暂停(Video widget) 冻结 20.4s; swap 2 帧 frame_id [34] | PASS | PASS | PASS | sd→sc 689 ms | 0 | PASS |
| P1 | 3907 | PASS | PASS | PASS | 暂停(Video widget) 冻结 20.5s; swap 2 帧 frame_id [34] | PASS | PASS | PASS | n/a | 0 | PASS |
| O1 | 4207 | n/a (设计上 HOME 早于起点) | PASS (返回链见 O1/analysis-return-chain.md) | PASS | 暂停(Video widget) 冻结 0.2s; swap 4 帧 frame_id [34, 45] | PASS | PASS | n/a→见 O1 分支 | n/a | 0 | PASS (干净恢复分支) |
| O1b | 4521 | n/a (设计上 HOME 早于起点) | n/a (返回后无 bind) | n/a (无 bind；0 bridge-not-initialized / 0 yuv420p10) | 无视频 (fail-closed) | HdrErrorEvent TimeoutException ×1 (fail-closed 记录) | PASS | n/a | n/a | 无窗口 | FAIL-CLOSED 无崩溃 (按实际记录) |

### 时间链差值表（返回周期；ms；行号 = logcat-full.txt）

| 轮 | wid | vo=null ack | authorize begin (dart) | java enter | java result ok | dart result ok | ensure_init ready=1 | create_window ok | MediaCodec create | OMX Now Loaded | ack→begin | begin→jEnter | jEnter→jResult | jResult→dResult | dResult→ensure | ensure→create | create→MediaCodec | owner_key 同 HOME 前 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| N1 | 1050522 | L1507 48:12.715 | L1760 48:23.808 | L1776 48:23.857 | L1783 48:23.858 | L1789 48:23.886 | L1838 48:23.931 | L1841 48:23.933 | L1842 48:23.934 | L1861 48:23.953 | 11093 | 49 | 1 | 28 | 45 | 2 | 1 | 是 (8793159320474925283) |
| N2 | 1986 | L1471 49:24.558 | L1733 49:36.315 | L1746 49:36.346 | L1753 49:36.346 | L1754 49:36.351 | L1809 49:36.455 | L1813 49:36.456 | L1814 49:36.458 | L1825 49:36.475 | 11757 | 31 | 0 | 5 | 104 | 1 | 2 | 是 (3373717545738814617) |
| N3 | 2099314 | L1462 50:29.578 | L1703 50:40.499 | L1719 50:40.568 | L1726 50:40.569 | L1736 50:40.578 | L1793 50:40.653 | L1797 50:40.654 | L1798 50:40.659 | L1809 50:40.676 | 10921 | 69 | 1 | 9 | 75 | 1 | 5 | 是 (17098553269247067201) |
| F1 | 2258 | L1510 52:22.945 | L1744 52:25.272 | L1746 52:25.273 | L1753 52:25.273 | L1754 52:25.274 | L1790 52:25.326 | L1794 52:25.327 | L1795 52:25.329 | L1822 52:25.352 | 2327 | 1 | 0 | 1 | 52 | 1 | 2 | 是 (5544324211490475549) |
| F2 | 2258 | L1471 53:17.676 | L1679 53:19.620 | L1680 53:19.621 | L1687 53:19.621 | L1688 53:19.622 | L1724 53:19.679 | L1728 53:19.680 | L1731 53:19.683 | L1752 53:19.700 | 1944 | 1 | 0 | 1 | 57 | 1 | 3 | 是 (18445166970016255604) |
| F3 | 2258 | L1495 54:11.483 | L1734 54:13.433 | L1735 54:13.435 | L1742 54:13.436 | L1743 54:13.438 | L1779 54:13.493 | L1783 54:13.495 | L1784 54:13.497 | L1806 54:13.519 | 1950 | 2 | 1 | 2 | 55 | 2 | 2 | 是 (16721639828673806270) |
| F4 | 2258 | L1450 55:04.745 | L1694 55:06.189 | L1695 55:06.190 | L1702 55:06.190 | L1703 55:06.191 | L1739 55:06.249 | L1743 55:06.250 | L1744 55:06.252 | L1763 55:06.266 | 1444 | 1 | 0 | 1 | 58 | 1 | 2 | 是 (15828119071824081213) |
| F5 | 2258 | L1425 55:58.150 | L1694 56:00.217 | L1696 56:00.218 | L1703 56:00.218 | L1705 56:00.219 | L1743 56:00.277 | L1747 56:00.279 | L1748 56:00.281 | L1767 56:00.302 | 2067 | 1 | 0 | 1 | 58 | 2 | 2 | 是 (1159170726756832773) |
| P1 | 1050738 | L1503 57:36.394 | L1754 57:47.647 | L1771 57:47.710 | L1778 57:47.711 | L1779 57:47.712 | L1828 57:47.789 | L1832 57:47.790 | L1833 57:47.793 | L1860 57:47.813 | 11253 | 63 | 1 | 1 | 77 | 1 | 3 | 是 (6554548817045129073) |
| O1 | 2099314 | L1317 23.214 (拆除 ack) | L1513 33.297 | L1528 33.360 | L1535 33.360 | L1540 33.370 | L1598 33.463 | L1602 33.464 | L1603 33.466 | L1618 33.487 | 10083 | 63 | 0 | 10 | 93 | 1 | 2 | 是 (7113845237141439577) |
| O1b | — | 返回后无 authorize/bind（fail-closed） | | | | | | | | | | | | | | | | |

### 快速轮间隔表（方法 F：同一 adb shell 内 `am start HOME --activity-no-animation; am start Lab --activity-no-animation`，sleep 0）

| 轮 | HOME 环 sd 行/时刻 | sc 行/时刻 | sd→sc (ms) | shutdown exit vs surfaceCreated | SurfaceFailed/RuntimeFailed | 冷启 view0→view1 环 sd→sc (ms, 参考) |
|---|---|---|---|---|---|---|
| F1 | L1406 52:22.729 | L1583 52:23.441 | 712 | shutdown_exit BEFORE surfaceCreated by 543 ms (L1503) | 0 | 83 |
| F2 | L1366 53:17.410 | L1535 53:18.020 | 610 | shutdown_exit BEFORE surfaceCreated by 526 ms (L1412) | 0 | 86 |
| F3 | L1403 54:11.264 | L1573 54:11.890 | 626 | shutdown_exit BEFORE surfaceCreated by 525 ms (L1464) | 0 | 84 |
| F4 | L1371 55:04.567 | L1544 55:05.142 | 575 | shutdown_exit BEFORE surfaceCreated by 490 ms (L1417) | 0 | 102 |
| F5 | L1340 55:57.946 | L1522 55:58.635 | 689 | shutdown_exit BEFORE surfaceCreated by 568 ms (L1398) | 0 | 72 |

### 拆除期错误对比表（窗口 = surfaceDestroyed enter −1 s … mkst_shutdown exit +1 s）

| 组 | 轮 | sd→shutdown enter (ms) | latch timeout | Mapping failed | FUSION disabled-after-failure | horizon-overflow | Failed rendering frame | 簇 |
|---|---|---|---|---|---|---|---|---|
| 修后 p3c-a2 | N1 | 74 | 0 | 0 | 0 | 0 | 0 | 否 |
| 修后 p3c-a2 | N2 | 104 | 0 | 0 | 0 | 0 | 0 | 否 |
| 修后 p3c-a2 | N3 | 41 | 0 | 0 | 0 | 0 | 0 | 否 |
| 修后 p3c-a2 | F1 | 169 | 1 | 2 | 1 | 1 | 1 | 是 |
| 修后 p3c-a2 | F2 | 83 | 0 | 0 | 0 | 0 | 0 | 否 |
| 修后 p3c-a2 | F3 | 101 | 0 | 0 | 0 | 0 | 0 | 否 |
| 修后 p3c-a2 | F4 | 71 | 0 | 0 | 0 | 0 | 0 | 否 |
| 修后 p3c-a2 | F5 | 120 | 0 | 0 | 0 | 0 | 0 | 否 |
| 修后 p3c-a2 | P1 | 54 | 0 | 0 | 0 | 0 | 0 | 否 |
| 修后 p3c-a2 | O1 | 715 | 0 | 0 | 0 | 0 | 0 | 否 |
| 修后 p3c-a2 | O1b | 无拆除窗口 | — | — | — | — | — | — |
| 修后 p3c-a2 | T0(trial) | 98 | 0 | 0 | 0 | 0 | 0 | 否 |
| 修前 | R1 | 150 | 0 | 0 | 0 | 0 | 0 | 否 |
| 修前 | R2-1 | 70 | 0 | 0 | 0 | 0 | 0 | 否 |
| 修前 | R2-2 (续进程,已软解) | 无拆除窗口 | — | — | — | — | — | — |
| 修前 | R2-3 (续进程,已软解) | 无拆除窗口 | — | — | — | — | — | — |
| 修前 | R3 (PiliPlus) | 91 | 0 | 0 | 0 | 0 | 0 | 否 |
| 修前 | R4-fast-1 | 236 | 0 | 0 | 0 | 0 | 0 | 否 |
| 修前 | R4-fast-2 | 133 | 0 | 0 | 0 | 0 | 0 | 否 |
| 修前 | R4-fast-3 | 225 | 1 | 2 | 1 | 1 | 1 | 是 |
| 修前 | p3/phase1 smoke-prefix | 193 | 1 | 2 | 1 | 1 | 1 | 是 |

出现轮数/有拆除窗口的总轮数：修后 **1/11**（含 T0 trial；不含 T0 为 1/10）；修前 **2/7**。

## 4. resume 方法（任务卡要求先查源码）

- `media_kit_hdr_lab/lib/tests/01.single_player_single_video.dart`（7169 行）与 `lib/main.dart`（254 行）核查结论：本构建（p3c-a2 define 集 = 脚本基础 defines + SURFACE_TIMELINE/HDR_PREFER_CONVERT/HDR_DIAGNOSTICS）下页面仅有 `Video(controls: null)`（L6820）与 preopen-fullscreen 手势层（L6821–6844，`_preopenFullscreenStarted` 首次 tap 后永久 no-op）；`MEDIA_KIT_ANDROID_HDR_AUTO_RESUME_PROBE`/`_androidHdrAutoResumeProbe`（L4153）**未编入**（define 集无此项）；`_buildNativeDvLifecycleControls`（L2890，含 Pause10Resume/ManualResume 按钮）仅在 native DV session probe 启用时渲染，本构建未启用；`debug.mks.*` 均为只读质量/热探针，无 resume 语义。暂停的来源是 `media_kit_video/lib/src/video/video_texture.dart` L348–366（`AppLifecycleState.paused` → `player.pause()`，不自动 resume）。
- 实测（trial/T0-mediakey 与 P1）：`KEYCODE_MEDIA_PAUSE`/`KEYCODE_MEDIA_PLAY` 注入到达 Lab ViewRoot（logcat `ViewRoot's KeyEvent` 行，T0 L1260/L2048）但无处理路径——PAUSE 后 time-pos 连续推进越过按键时刻（P1：14.05 s@22:57:29.8 → 20.50 s@22:57:38.1，暂停实际发生在 HOME 的 `am_pause_activity` L1358 之后）；PLAY 后 `PERF pause=yes` 且 time-pos 冻结不变。
- **结论：Lab 无法 resume（也无法预暂停）**；帧推进 ≥15 s 验证由 (c) PiliPlus 承担。已记录返回后 swap/frame_id：重建完成后 `MKS-FUSION committed=1…` + `swap-success route=fused frame_id=34 still=0/1` 各 2 条（O1 为 4 条，含 open 期 rgb-final 2 条）。
- P1 的处置：P1 槽位 = "媒体键 pause→HOME→返回→媒体键 resume"的完整尝试轮（协议同 N），预暂停/显式 resume 前提未能建立，其余判据全过；**"用户主动预暂停"语义在 Lab 上未验证（前提缺失）**，且注意每轮 N/F 都天然包含"生命周期暂停先于 surfaceDestroyed 41–169 ms"（见拆除表 sd→shutdown 列，暂停由 `am_on_stop_called` 触发，先于 sd）。

## 5. 拆除期错误（对照修前）

- 窗口定义：`surfaceDestroyed enter` −1 s … `mkst_shutdown exit` +1 s（同一 sd/shutdown 对）。F1 簇 6 条全部落在 sd 后 94–127 ms、shutdown enter 前 42 ms 内（F1 L1458 latch timeout / L1467+L1474 Mapping failed / L1468 disabled-after-failure / L1472 horizon-overflow / L1486 Failed rendering frame）——渲染线程在 sd→shutdown 间隙向已销毁 surface 提交一帧的既有竞争；**返回后不残留**（F1 返回后 `MKS-FUSION committed=1 attempted=4 generation=4` L1924 + `swap-success route=fused`）。
- 相关性：簇出现轮的 sd→shutdown enter 间隔 ≥169 ms（F1 169 / 修前 R4-fast-3 225 / smoke 193），其余轮 41–133 ms 无簇（反例：修前 R4-fast-1 236 ms 无簇）→ 时序竞争，非确定性。
- **修后 1/11（不含 T0 trial 为 1/10）≤ 修前 2/7，不构成需调查项**；作为既有竞争记录在案（O1 的 715 ms 间隙无簇：当时 mapper 已 frames=1 latched=1，无可提交帧）。

## 6. O1 实际分支（两个都发生了，取决于 HOME 落点）

| 轮 | tap→HOME 注入 | HOME 落点 | 分支 |
|---|---|---|---|
| O1 | 1.378 s（`OPEN_HOME_DELAY=0.5` + adb/`input` 开销；tap 注入 L420 22:58:20.662，HOME 注入 L988 22:58:22.040） | session review entry=1 已完成（L773 21.499）、`mkst_create_decoder_window exit ok` 后 42 ms（L953 21.996）、`Mediacodec create` 后 44 ms | **干净恢复**：HOME 拆除（sd L1183、shutdown L1218）与 open 的 rebind 在飞并发（bind complete L1256 22:58:22.895 后又被 vo=null 收敛 L1289/1317）；返回后 authorize ok→ensure_init ready=1（owner_key 与 open 一致 7113845237141439577）→create ok→MediaCodec 重建→`pixelformat: mediacodec` L1668→importer 注册 L1688→fused swap L1692；HDR review entry=2 success、HDR decision applied dvP84/baseLayerConvert/output=pq L1707 |
| O1b | 0.867 s（`OPEN_HOME_DELAY=0`；tap L391 23:02:23.316，HOME keyDown L767 23:02:24.183） | review entry=1 完成后 39 ms（24.144）、view0→view1 换视图窗口内（view1 在 am_on_stop 后 134 ms 才被 factory.create L988，后台无 surface） | **fail-closed**：view1 永无 surfaceCreated→输出 bind 等待 10 s 超时 `HdrErrorEvent(reason: null, TimeoutException …)` L1113 23:02:34.592→`apply vo=null wid=0 android-surface-size=1x1`→返回后（am_resume L1169）view1 被 dispose（L1216），无 surfaceCreated/authorize/decoder，播放器空闲（time-pos 空）；**无崩溃、PID 4521 延续、C5 PASS** |

O1b 观察（供 Lead 判断，非本验收判定）：fail-closed 的错误事件 `reason: null` + `TimeoutException after 0:00:10` 为泛化超时，而非带语义的 reason（如 noSurface）；窗口内 view1 的 ViewCreated 已发生（后台），若产品语义要求"返回后可继续"，此分支或需显式恢复路径。

## 7. HDR / SurfaceFlinger

- 全部可执行轮：`MKSURF-E1: dataspace applied ret=1` 返回后各出现 1 次（行号见各轮 analysis.md C6 节）；HDR decision（pre-HOME 与返回后均为 `class=dvP84 selected=baseLayerConvert presentation=nativeHdr vo=gpu-next hwdec=surfacetexture output=pq topology=platformView`）一致；返回后 `HDR_SESSION_REPORT hwdecCurrent=surfacetexture`（O1 L1697/1711；N/F/P 轮最后报告同样 surfacetexture，返回后无新报告=路由未重跑，符合"与 HOME 前一致"）。
- SF dump（N1/F1 各 2 份）：API 24 的 `dumpsys SurfaceFlinger` **不含 per-layer dataspace 字段**（平台限制，非未采集）；可证：10-bit 视频层 `SurfaceView - …hdr_lab…`（`format=43`=RGBA_1010102，buffer `7FA30C04`，z=21015）在 HOME 前与返回后均存在、均有 ACQUIRED buffer、均经 HWC 合成（HWC 表第 2 行）。BT2020/PQ dataspace 的应用侧证据为 `MKSURF-E1: dataspace applied ret=1` + decision `output=pq`。

## 8. 设备结束状态

- 唤醒、已解锁、焦点在 launcher（Lab 已按轮次协议 force-stop，`pidof` 为空）；`debug.mks.*` 全部保持 p0 基线值（thermal_sync=display-resample、thermal_trace=1、yuv_frame_trace=1、其余 0/空）；dropbox 0 条 crash/anr/tombstone；Lab APK 三项身份未变（§1）。

## 9. 偏差与未验证项

1. **C3 resume 帧推进**：Lab 无 resume 方法（§4），本验收未验证；转 (c) PiliPlus。已记录返回后新帧（fused frame_id=34 ×2）。
2. **P1 "先暂停"语义**：无预暂停手段，P1 实际为"媒体键尝试 + 生命周期自动暂停"轮；用户主动预暂停路径未验证。
3. **O1 tap→HOME ≤1 s**：O1 实测 1.378 s（adb `input` 进程启动开销），为此补跑 O1b（0.867 s，达标）；两分支均已记录。
4. **SF dataspace 字段**：API 24 不可得（§7），BT2020/PQ 以应用侧 E1+decision 证据链为准。
5. **T0/P1 媒体键、O1b fail-closed 后的再次 open**：非破坏性约束下未测试重新 open 的恢复（会触发新 open，超出本矩阵定义）。
6. p0 修前 R2-2/R2-3（续进程、已软解）无拆除窗口，R3 为 PiliPlus 轮（无 Lab 报告行）——对照表已按实际标注。
7. 时间链差值表中 dart 层行使用 `rt=`（自带设备时钟），`MediaCodec create`/`OMX` 行使用 logcat 戳（ms 级、无 rt），跨源差值含 ±数 ms 的打印延迟。
