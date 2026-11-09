# P0 关联时序取证：HOME 返回后 surfacetexture bridge 未重新初始化

- 日期：2026-11-02（设备本地时间 Asia/Shanghai）
- 角色：Verifier（只做诊断插桩 + 源码构建 + 实机取证；不修复、不提交）
- 设备：LG H870DS（LG G6，API 24），serial `LGH870DS42e27764`；片源 `/sdcard/Android/data/com.example.media_kit_hdr_lab/files/hokkaido-p84.mp4`（1,232,790,317 B，DV P8.4，SHA256 记录见 `build-identity.json`）
- 构建：`build-identity.json`（Lab APK `76d77667…`、PiliPlus dev APK `c1f6dff8…`，三仓 HEAD/dirty 摘要、define 集、设备回读 SHA）
- 插桩：`instrumentation.diff`（仅 media-kit 5 个文件；mpv 未动，使用其既有 `MKSURF:` 行）
- 每轮证据：`R1/`、`R2-1/`、`R2-2/`、`R2-3/`、`R3/`，各含 `logcat-full.txt`（`exec-out logcat -d -v threadtime -b all`）、`timeline.md`/`timeline.json`（跨层排序 + 锚点 + 差值）、`host-events.ndjson`（每条 adb 命令的主机/设备时间）、`driver.log`
- 驱动脚本：`run_round.sh`；时间轴生成：`make_timeline.py`

## 0. 结论（先读）

**事实**：五轮（Lab 正常 HOME ×1、Lab 快速 HOME ×3、PiliPlus 正常 HOME ×1）全部复现"返回后 bridge 未初始化 → 软解"，进程 PID 全程延续。三层事件在同一设备时钟上的顺序与静态链一致：

HOME → Java `surfaceDestroyed` → Java→Dart `SurfaceDestroyed` → Dart `_detachPlatformSurface` 拿锁 → Dart 写 `vo=null` → mpv 在旧 GL 线程（旧 EGL context）内调用 native `mkst_shutdown`（`initialized`/`owner_key`/`generation` 全部清零）→ Dart 收到 `vo=null` ACK（严格晚于 shutdown 退出 64–111 ms）→ 其余 `wid=0` 链 → detach 释放锁。
返回 → Java **同一个** PlatformVideoView 的 `surfaceCreated`（无 `factory.create`、无 `setLgExperimentOwner`、无 `ensureInitialized`）→ `SurfaceAvailable` → Dart bind → `vo=gpu-next` → mpv 新 VO 在**新 GL 线程 / 新 EGL context** 上调用 `mkst_ensure_init` → 读到 `initialized=0` → `ready=0` → mpv `MKSURF: bridge not initialized` → 无 MediaCodec 创建 → `yuv420p10` 软解。

**判定**：实机时序**支持**静态分析链；未发现与之矛盾的事件。唯一需要修正的细节是叙述顺序："`eglCreateWindowSurface ok` 约 90 ms 后打印 `bridge not initialized`"中的 90 ms 是 mpv 日志经 Dart 转发到 logcat 的延迟（R1 为 96 ms，R2 三轮仅 1–3 ms），不是真实事件间隔；native `ensure_init` 退出与转发的 egl 行相差仅 −47…+3 ms，两者先后无法由转发行判定。

## 1. 方法与时间基准

- 统一前缀 `MKS-HOME-TRACE`。Java（`Log.i` tag）、native（`__android_log_print` tag）、Dart（`debugPrint`，进 `flutter` tag）每行带 `rt=`（CLOCK_REALTIME ms：Java `System.currentTimeMillis`、native `clock_gettime(CLOCK_REALTIME)`、Dart `DateTime.now().millisecondsSinceEpoch`）、`mono=`（Java `SystemClock.uptimeMillis` / native `CLOCK_MONOTONIC`）、`tid`、native 另带 `eglGetCurrentContext()`。时间轴以各层自己写入的 `rt=` 为准；非插桩行（mpv 转发行、ActivityManager 事件、ACodec/MediaCodec）用 logcat 戳。
- 主机 vs 设备时钟：设备比主机快约 +1.1 s（三次采样 +1227/+1135/+1090 ms，RTT 171–373 ms）；仅用于把主机命令时刻映射到设备轴，三层事件本身都在设备时钟上，无需校正。
- `adb logcat -c -b all` 在此设备返回 1（`security` buffer 不可清），改为逐 buffer 清 `main system crash events radio kernel`；dump 使用任务规定的 `exec-out logcat -d -v threadtime -b all`（成功，security 为空）。
- `input keyevent KEYCODE_HOME` 从发出到返回耗时 1.0–2.4 s，`surfaceDestroyed` 发生在命令发出后 0.75–1.7 s；"返回"命令 `am start -n <Activity>`（现有 task 置前，输出 "its current task has been brought to the front"），`surfaceCreated` 在命令返回前后 ±0.2 s 内发生。
- 未改任何系统设置/sysprop（`debug.mks.*` 保持原值：`thermal_sync=display-resample`、`thermal_trace=1`、`yuv_frame_trace=1`，其余 0/空）。

## 2. 轮次总览

| 轮 | 宿主 | 动作 | PID 前→后 | HOME 前硬解 | 返回后 |
|---|---|---|---|---|---|
| R1 | Lab（显式 token） | 冷启→tap 播放 16 s→HOME→10 s→`am start`→观察 20 s | 17022→17022 | `MKSURF create ok`，importer latch=482 帧 | `ensure_init ready=0`，`bridge not initialized`，`yuv420p10`，无 MediaCodec 创建 |
| R2-1 | Lab | 冷启→播放 16 s→HOME→**立即**返回→观察 12 s | 17295→17295 | latch=474 帧 | 同上 |
| R2-2 | Lab（续 R2-1 进程） | HOME→立即返回 | 17295→17295 | **已是软解**（R2-1 遗留），无 importer | `ensure_init ready=0`，`bridge not initialized`，`yuv420p10` |
| R2-3 | Lab（续） | HOME→立即返回 | 17295→17295 | 已是软解 | 同上 |
| R3 | PiliPlus dev（managed 宿主，App 代码无显式 token） | 冷启（deep link B 站 BV1vY4y1N7TY）→30 s→HOME→10 s→`am start`→观察 20 s | 18812→18812 | `MKSURF create ok` + `OMX.qcom.video.decoder.hevc`，latch=737 帧，App 路由日志 `class=dvP84 selected=baseLayerConvert hwdec=surfacetexture` | `ensure_init ready=0`；返回后 0 条 MediaCodec/OMX/ACodec 行（PiliPlus 不转发 mpv 日志，故无 `bridge not initialized` 文本与 VIDEOPARAMS） |

## 3. 关键待证逐条回答

### (1) 正常/快速 HOME 下 `mkst_shutdown` 完成 vs Java `surfaceCreated` 的先后与间隔

**事实**（设备时钟，ms）：

| | R1 正常 | R2-1 快速 | R3 PiliPlus 正常 |
|---|---|---|---|
| `mkst_shutdown` 退出 | 17:20:02.345 | 17:21:56.620 | 17:41:19.043 |
| Java `surfaceCreated` 进入 | 17:20:13.755 | 17:21:57.896 | 17:41:30.013 |
| 差值 shutdown退出 → surfaceCreated | **+11410** | **+1276** | **+10970** |
| 差值 shutdown退出 → 新 importer `ensure_init` 退出 | +11563 | +2461 | +11217 |

三轮 shutdown 均严格早于 surfaceCreated；快速 HOME 最小间隔 1.28 s（受 `am start` 返回链路限制，本轮无法做到 <1 s 的 Java 级间隔）。R2-2/R2-3 无 shutdown（前一轮返回已软解，无 importer 可卸载）。

### (2) Dart 对 `vo=null`/`wid=0` 的 ACK 是否严格晚于 `mkst_shutdown` 退出（屏障）

**事实**：首个 `vo=null` 的 ACK（`property complete vo=null`）晚于 shutdown 退出：R1 **+111 ms**，R2-1 **+64 ms**，R3 **+84 ms**。shutdown 发生在 Dart `property begin vo=null` 之后 69–131 ms（mpv `uninit_video_out` → ACodec "Now uninitialized" → VO uninit → importer uninit → `mkst_shutdown`，均在旧 VO 的 GL 线程、旧 EGL context 上）。整条 `wid=0` 链（surface-size / wid=0 / vo=null / vid=no）在 shutdown 后 2.2–2.7 s 完成，detach 随后释放锁。**屏障成立**。

### (3) 全程是否有第二次 `ensureInitialized`

**事实**：HOME 之后所有轮次 `ensureInitialized` 调用数 = **0**，`factory.create` = **0**，`setLgExperimentOwner` = 0。返回后的 `surfaceCreated` 行明确记录 `ensureInitializedCalledHere=false`、`tokenPresent=true`、`ownerGeneration` 不变（Lab=2，PiliPlus=1），只有 per-view `surfaceGeneration` 递增（Lab 1→2→3→4，PiliPlus 1→2）。Lab 冷启时共 2 次 `ensureInitialized`（见 (4)），均在播放开始前。

### (4) factory 创建时 init 与首个 `surfaceCreated` 的先后

**事实**（R1，pid 17022，均主线程 tid 17022）：
- 17:19:43.861 `factory.create`(viewId=0, ownerGeneration=1) → 43.862 `setLgExperimentOwner` → 43.863 `ensureInitialized(gen=1)` → 43.865 `mkst_init` 绑定 `owner_key=13118931974235331591 generation=1`（`egl_ctx=0x0`）→ 43.866 `ViewCreated` → **43.910 `surfaceCreated`(viewId=0, surfaceGeneration=1)**。init 早于首个 surfaceCreated **45 ms**。
- 45.074 viewId=0 `surfaceDestroyed`(wid=0) → 45.078 `dispose` → 45.109 `factory.create`(viewId=1, ownerGeneration=2, managedYuvCarrier=true) → 45.111 `ensureInitialized(gen=2)` → `mkst_init` **rebind 1→2，rc=0**（无活动 window）→ **45.157 `surfaceCreated`(viewId=1, surfaceGeneration=1, wid=2242)** → 45.413 importer `ensure_init ready=1`（GL 线程 tid 17100，`egl_ctx=0x741a2de780`）→ 45.415 `mkst_create_decoder_window ok`。
- R3（PiliPlus）：47.369 `ensureInitialized(gen=1)` → 47.377 绑定 → **47.457 `surfaceCreated`**（+80 ms）→ 48.498 `ensure_init ready=1` → 48.500 create ok → 48.517 `MediaCodec create`。
**结论**：init 严格先于首个 surfaceCreated，importer 的 verify/create 在 surfaceCreated 之后 0.25–1.1 s。

### (5) 身份值

**事实**：

| 身份 | 来源 | R1 (Lab) | R2-1 (Lab, 新进程) | R3 (PiliPlus) |
|---|---|---|---|---|
| 传给 `ensureInitialized` 的 generation（= `ownerGeneration` = controller/topology generation） | `factory.create` params | 1，然后 2 | 1，然后 2 | 1 |
| `owner_key`（token FNV-1a64，native 无符号） | `mkst_init` | 13118931974235331591（两代同一 token） | 17256112029915847738 | 10559191110119857845 |
| viewId | factory `id` | 0 → 1 | 0 → 1 | 0 |
| per-view `surfaceGeneration` | `surfaceCreated` 计数 | view1：1（HOME 前）→ 2（返回） | 1 → 2（R2-2: 3，R2-3: 4） | 1 → 2 |
| wid | `newGlobalObjectRef` | 2242 → 2162 | 2242 → 2258 → 2254 → 2099394 | 1050978 → 1051082 |
| 旧 VO GL 线程 / EGL ctx（create & shutdown） | native trace | tid 17100 / 0x741a2de780 | tid 17369 / 0x741d3ffc00 | tid 18946 / 0x74118eb880 |
| 新 VO GL 线程 / EGL ctx（返回后 `ensure_init`） | native trace | **tid 17188 / 0x741dbfc600** | **tid 17482 / 0x74181fd980** | **tid 19187 / 0x74116d6e80** |

每次 HOME/返回都是**同一个 view、同一 ownerGeneration、同一 token**，只有 Surface 代数与 wid 变化；bridge 的 `initialized/owner_key/generation` 在 shutdown 后全部为 0，无人再写。

### (6) 快速 HOME 时 destroy/available 是否交错进入 bind 事务

**事实**（R2-1/R2-2/R2-3）：`SurfaceAvailable` 事件在 detach 仍持锁时到达（分别早于 detach 释放锁 **1097 / 405 / 676 ms**），`bind requested` 被记录但 `bind lock acquired` 在 detach `lock released` 之后 **0 / 0 / 1 ms** 才发生；bind 内分支为 `rebind, boundWid=null, stopPreviousFirst=false`。整个过程无 `SurfaceFailed`/`SurfaceRuntimeFailed`、无 `dispose`、无 `swallowed`。**结论：`lock.synchronized` 正确串行化，没有交错进入事务**；快速 HOME 的失败机制与正常 HOME 完全相同（不是竞态，而是缺少重初始化入口）。

## 4. 每轮序关系（ms，设备时钟）

| 序关系 | R1 | R2-1 | R2-2 | R2-3 | R3 |
|---|---|---|---|---|---|
| `mkst_shutdown` 退出 → Java `surfaceCreated` | 11410 | 1276 | —(无 shutdown) | — | 10970 |
| `mkst_shutdown` 退出 → Dart `vo=null` ACK | 111 | 64 | — | — | 84 |
| `mkst_shutdown` 退出 → Dart `wid=0` 链 apply complete | 2225 | 2396 | — | — | 2716 |
| `mkst_shutdown` 退出 → 新 importer `ensure_init` 退出 | 11563 | 2461 | — | — | 11217 |
| Java `surfaceDestroyed` 进入 → shutdown 退出 | 151 | 70 | — | — | 92 |
| Dart `vo=null` begin → shutdown 进入 | 131 | 69 | — | — | 76 |
| Java `surfaceCreated` → Dart bind 拿锁 | 6 | 1123 | 428 | 684 | 5 |
| Dart `SurfaceAvailable` 到达 → detach 释放锁（>0 = 到达时 detach 仍持锁） | −9182 | 1097 | 405 | 676 | −8242 |
| detach 释放锁 → bind 拿锁 | 9182 | 0 | 0 | 1 | 8242 |
| native `ensure_init` 退出 → mpv `bridge not initialized`（logcat 转发） | 96 | 3 | 2 | 1 | —(不转发) |
| Java `surfaceCreated` → 首个 `yuv420p10` VIDEOPARAMS | 824 | 1804 | 972 | 1219 | —(不转发) |

完整按时间排序的事件表见各轮 `timeline.md`（每行带设备时间、Δhome、层、tid、原始行号）。

## 5. 与静态链的符合/不符

- **符合**：HOME→`surfaceDestroyed`→Dart detach→`vo=null`→`uninit_video_out`→importer uninit→`mkst_shutdown` 清 `initialized`；返回→`surfaceCreated`（不调 `ensureInitialized`）→bind→新 VO→importer init→`ensure_init()=0`→失败。全部在实机按该顺序出现，且在显式 token 宿主（Lab）与 managed 宿主（PiliPlus）上一致。
- **需修正的叙述**：`ensure_init` 在新 VO 的 `eglCreateWindowSurface ok` 之后约 90 ms 打印 `bridge not initialized` —— `bridge not initialized` 与 `eglCreateWindowSurface ok` 都是 mpv 日志经 Dart 转发的 logcat 行，有转发延迟；native `ensure_init` 退出（无延迟）与转发的 egl 行相差 R1 −3 ms、R2-1 +47 ms、R2-2 +39 ms、R2-3 +33 ms，`bridge not initialized` 行相对 `ensure_init` 退出滞后 R1 96 ms / R2 1–3 ms。因此"90 ms"是日志链路延迟，egl surface 创建与 `ensure_init` 的真实先后不能由转发行判定；可确定的是 `ensure_init` 在新 GL 线程（新 EGL context）上执行并被拒绝。
- **补充发现**（事实）：Lab 冷启会建两个 view（gen 1 → gen 2，`mkst_init` 作 rebind），说明 `ensureInitialized` 入口本身可以在无活动 window 时重复绑定（`rc=0`）；但该入口只在 `factory.create` 路径被调用，HOME/返回不经过它。
- **推断**（未由本轮直接验证）：shutdown 后 `g_lifecycle` 清零而 Java 侧 `lgOwnerToken/lgOwnerGeneration` 仍保留在 view 实例中，因此返回时 Java 有重新 `ensureInitialized` 所需的全部信息；这是修复方向的线索，不是本轮验收项。

## 6. 偏差、缺口与未验证项

- **R2-2/R2-3 起点是已软解状态**（R2-1 返回后即软解，三次快速 HOME 在同一进程内连续执行）；它们证明"再次 HOME/返回也不会恢复"，但不是三次独立的"硬解→快速 HOME"样本。若需三次独立快速样本，应每次冷启（本轮未做）。
- **快速 HOME 的 Java 级间隔最小 1.28 s**（两条 adb 连发，`input keyevent` 返回慢），未达到 <1 s；但 Dart 侧已出现"Available 在 detach 持锁期间到达"的目标交错场景（(6) 已验证）。
- **R3 用的是 B 站网络 DV 源，不是本地文件**（PiliPlus 无法 deep link 打开本地文件；设备上已有登录态，路由日志确认走了 dvP84/surfacetexture）。PiliPlus 不转发 mpv 日志，返回后"软解"由 `ensure_init ready=0` + 返回后 0 条 MediaCodec/OMX/ACodec 创建行推断，没有 `yuv420p10` 文本直证。
- **未验证**：返回后画面是否推进（未截图/未读帧计数；Lab 侧 VIDEOPARAMS 持续刷新与 mpv 继续工作一致，但不是帧推进直证）；`hwdec-current` 属性值未从进程外读取（Lab 的 `HDR_SESSION_REPORT hwdecCurrent=surfacetexture` 只在 HOME 前出现）。
- define 集偏离既往轮次：未加 `MEDIA_KIT_ANDROID_P84_LIFECYCLE_PROBE`（自动动作驱动器，会干扰手动 HOME）与 `MEDIA_KIT_ANDROID_P84_THERMAL_PROBE`；加 `MEDIA_KIT_ANDROID_SURFACE_TIMELINE=true`（启用 Dart trace）、`MEDIA_KIT_ANDROID_HDR_PREFER_CONVERT=true`（P8.4 走 surfacetexture 路由）、`MEDIA_KIT_ANDROID_HDR_DIAGNOSTICS=true`。
- PiliPlus 第一次构建因全局 Flutter 3.47.2 ≠ 项目钉定 3.47.8 失败（日志 `build-piliplus-attempt1-sdk3.47.2-failed.log`），第二次用机器上已有的独立 SDK `/Users/wuweiwei1/flutter-sdks/3.47.8` 置于 PATH 成功；全局 Flutter 配置未改。
- mpv 未加插桩；mpv 侧时序仅靠既有 `MKSURF:` 行（经 Dart 转发，有延迟）与 native bridge 的 `ensure_init/create/shutdown` 进出点（无延迟）。

## 7. 环境与现场

- 设备结束状态：屏幕 ON、`isStatusBarKeyguard=false`；`screen_brightness=41`、`accelerometer_rotation=1`、`screen_off_timeout=30000`（本轮未改动）；hdr_lab 与 piliplus.dev 已 `force-stop`；两包均为本轮新装（`pm path` 分别为 `-2` 目录，lastUpdateTime 17:13:14 / 17:39:16）。
- 工作树：media-kit 插桩**仍留在工作树**（5 个文件，未 revert、未提交），`git status` 另含 Lead 的归档写入（TASKS.md、两个 summary.json、archives/、docs/plans/），未触碰。mpv、libplacebo、PiliPlus 的既有未提交改动未触碰。

补充（2026-11-02 20:20）：亚秒快速 HOME 驱动与三轮独立硬解起点样本见 `fast-sub1s-summary.md`（`run_round_fast.sh`、`R4-fast-1..3/`、`calib/T1..T10/`；Java sd→sc 736/597/841 ms，shutdown 退出仍先于 surfaceCreated）。
