# R4 快速 HOME 亚秒样本（Java 级 <1 s）+ 驱动改进

- 日期：2026-11-02 20:04–20:20（设备本地时间 Asia/Shanghai）
- 角色：Verifier（只做驱动改进 + 实机取样；不改源码、不重新构建、不提交）
- 设备：LG H870DS（API 24），serial `LGH870DS42e27764`；包 `com.example.media_kit_hdr_lab`，Activity `/<pkg>.MainActivity`
- 装机身份核对（两次，均通过）：轮前与 USB 重插后各一次，`pm path` = `/data/app/com.example.media_kit_hdr_lab-2/base.apk`，`lastUpdateTime` 2026-11-02 17:13:14，回读 SHA256 `76d776677994426508d511e72da3bf1a6f5849b41a9ccec70b29d1acbfd10471`（与 `build-identity.json` 一致）。**未重新安装、未重建**。
- 插桩：沿用 P0 现装 Lab 包（同 APK），无任何源码/构建改动。
- 每轮协议与 P0 相同：`force-stop` → 清 logcat（逐 buffer）→ 冷启 `am start` → 4 s → `input tap 1440 720` 播放 → 16 s → HOME/返回（快速驱动）→ 观察 12 s → `exec-out logcat -d -v threadtime -b all`；时间轴用既有 `make_timeline.py`，间隔速查用本轮新增 `fast_interval_check.py`（已对 R2-1 回归验证：sd→sc 1346 ms、shutdown exit 早于 sc 1276 ms，与 summary.md §3(1) 完全一致）。

## 0. 结论（先读）

1. **Java 级 `surfaceDestroyed enter → surfaceCreated enter` 全部 <1000 ms**：R4-fast-1 **736 ms**、R4-fast-2 **597 ms**、R4-fast-3 **841 ms**（P0 最快 1346 ms）。达成 V2 C4 的 <1 s 硬条件。
2. **三轮全部冷启 + 硬解起点**（独立样本，非 R2-2/3 式续进程）：每轮 HOME 前 `HDR_SESSION_REPORT verified=true hwdecCurrent=surfacetexture` + `mkst_create_decoder_window exit initialized=1` + importer latch 推进（latch=301 帧统计行），PID 全程延续（26247/26505/26737，HOME 前后不变）。
3. **`mkst_shutdown` 退出仍严格早于 `surfaceCreated`**（+500/+463/+615 ms）。即使间隔压到 597 ms，**未出现** `surfaceCreated` 早于 shutdown 退出的反例——P0 的设计前提在亚秒区间依然成立。
4. **返回后仍软解**（`ensure_init ready=0` → `bridge not initialized` → `yuv420p10` VIDEOPARAMS 10/72/82 行），`ensureInitialized`/`factory.create` HOME 后 0 次，无 `SurfaceFailed/SurfaceRuntimeFailed/swallowed/dispose`——失败机制与 P0 完全相同（缺重初始化入口，非竞态）。
5. **新观察（P0 未出现）**：亚秒返回下 detach→bind 的锁交接压缩到 <1 ms，2/3 轮出现 **"bind lock acquired" 日志行早于 "detach lock released" 日志行**（μs 戳差 −0.84 ms / −0.10 ms；第三轮 +0.26 ms 正常序）。这是**日志行发射顺序倒置**（released 行在 synchronized 块外补记，异步锁在微任务里把等待者先唤醒），不是锁语义被违反：`SurfaceAvailable` 仍是在 detach 持锁期到达（早 903–1828 ms），bind 仍等待释放后才拿锁，分支 `rebind boundWid=null stopPreviousFirst=false` 与 P0 一致。原文行号见 §3 表。

## 1. 驱动改进：尝试表（Java 级间隔 = HOME 轮 surfaceDestroyed enter rt= → surfaceCreated enter rt=）

全部候选都在单条 `adb shell` 内串联（去掉 P0 两条 adb 连发的往返）；每次尝试都是完整冷启轮（协议同 R4），证据在 `calib/T1..T10/`（各含 logcat-full.txt、host-events.ndjson、return-output.txt 等；T3–T10 当时未落 driver.log，命令与参数记录于本表与 `calib/T*/host-events.ndjson` 的 round_begin note）。

| 试次 | 方法 | 命令（adb shell 内） | Java sd→sc (ms) | 备注 |
|---|---|---|---|---|
| T1 | A | `input keyevent KEYCODE_HOME; am start -n <ACT>` | **987** | 去掉 adb 往返已接近 1 s |
| T2 | C | `am start -a android.intent.action.MAIN -c android.intent.category.HOME; am start -n <ACT>` | 1053 | 返回在 sd 前派发，无收益 |
| T3 | A（复测） | 同 T1 | **998** | A 的方差贴着 1 s |
| T4 | B | `input keyevent KEYCODE_HOME; sleep 0.2; am start -n <ACT>` | 1241 | sleep 只会推迟返回派发，劣化 |
| T5 | D | `am start …HOME; sleep 0.2; am start -n <ACT>` | 1000 | 同上，贴线 |
| T6 | E | `input keyevent KEYCODE_HOME; am start -n <ACT> --activity-no-animation` | 941 | 返回腿去动画，收益有限且方差大 |
| T7 | F | `am start …HOME --activity-no-animation; am start -n <ACT> --activity-no-animation` | **662** | 双侧去动画，大幅改善 |
| T8 | E（复测） | 同 T6 | 1036 | E 不稳定 |
| T9 | F（复测） | 同 T7 | **577** | 稳定 |
| T10 | F（复测） | 同 T7 | **528** | 稳定 |

（对照：P0 `run_round.sh` 快速 HOME 两轮为 1346/1276 ms 级。）

**最终驱动**：`run_round_fast.sh`（本轮新增，未动 `run_round.sh`），方法 F、sleep 参数默认 0：
```
adb -s LGH870DS42e27764 shell 'am start -a android.intent.action.MAIN -c android.intent.category.HOME --activity-no-animation; am start -n com.example.media_kit_hdr_lab/.MainActivity --activity-no-animation'
```

间隔构成（T1/T7 logcat 分解）：间隔 = [sd 后 return 派发延迟] + [`am` 二进制 spawn ≈0.3–0.4 s（app_process VM，API 24 无 `cmd activity start-activity`，实测 "Unknown command"）] + [ActivityManager pause-launcher→resume→surfaceCreated ≈0.15–0.7 s]。`--activity-no-animation` 的收益在双侧：HOME 腿跳过转场动画使 pause/stop 链更快完成且无动画结算期，返回腿跳过 launcher→app 动画使 sd 后 AM 立即处理 bring-to-front。双侧去动画后引擎部分 ≈0.45–0.6 s，是本设备可达下限附近（同参数三次 528–662 ms）。`input keyevent KEYCODE_HOME` 路线（A/B/E）受 input 二进制返回时刻抖动影响贴线不稳；HOME intent（候选 4）+ 双侧 no-animation 为最快组合。未尝试 `monkey`/`--longpress`（预判更慢，A/C 已给出主导项）。

## 2. R4 三轮总览（方法 F，独立冷启）

| 轮 | PID 前→后 | HOME 前硬解证据 | Java sd→sc (ms) | 返回后 |
|---|---|---|---|---|
| R4-fast-1 | 26247→26247 | `HDR_SESSION_REPORT verified=true hwdecCurrent=surfacetexture`；`mkst_create_decoder_window exit`×1；latch=301 | **736** | `ensure_init ready=0`→`bridge not initialized`→`yuv420p10`×10 |
| R4-fast-2 | 26505→26505 | 同上 | **597** | 同上，`yuv420p10`×72 |
| R4-fast-3 | 26737→26737 | 同上 | **841** | 同上，`yuv420p10`×82 |

HOME 前每轮 `ensureInitialized` 共 2 次（冷启 gen1→gen2 rebind，同 P0 §3(4)）、`mkst_shutdown` 0 次；HOME 后 `ensureInitialized`/`factory.create`/`setLgExperimentOwner` 均 0 次。

## 3. 三轮序关系表（ms，设备时钟，`rt=` 权威；与 P0 summary §4 同口径）

| 序关系 | R4-fast-1 | R4-fast-2 | R4-fast-3 | P2 对照（P0 R2-1 快速） |
|---|---|---|---|---|
| Java `surfaceDestroyed` enter → Java `surfaceCreated` enter | **736** | **597** | **841** | 1346 |
| `mkst_shutdown` 退出 → `surfaceCreated` enter（>0 = shutdown 先） | **+500** | **+463** | **+615** | +1276 |
| `surfaceDestroyed` enter → `mkst_shutdown` 退出 | 236 | 134 | 226 | 70 |
| `mkst_shutdown` 退出 → Dart `vo=null` ACK（屏障） | 141 | 135 | 43 | 64 |
| `mkst_shutdown` 退出 → `wid=0` 链 apply complete | 2326 | 2187 | 1573 | 2396 |
| `mkst_shutdown` 退出 → 新 importer `ensure_init` 退出 | 2417 | 2240 | 1617 | 2461 |
| `surfaceCreated` enter → Dart bind 拿锁 | 1840 | 1729 | 960 | 1123 |
| `SurfaceAvailable` 到达 → detach 释放锁（>0 = 到达时 detach 仍持锁） | 1828 | 1724 | 903 | 1097 |
| detach 释放锁 → bind 拿锁（rt= ms 差；见 §0.5 日志行倒置说明） | −1 | 0 | 0 | 0 |
| native `ensure_init` 退出 → mpv `bridge not initialized`（转发） | 1 | 1 | 2 | 3 |
| `surfaceCreated` enter → 首个 `yuv420p10` VIDEOPARAMS | 2416 | 2223 | 1461 | 1804 |

锁交接 μs 级原文（`SURFACE_TIMELINE` 内嵌 DateTime μs 戳，logcat-full.txt 行号）：
- R4-fast-1：L1730 `bind lock acquired` 20:17:32.056305 ← L1732 `detach lock released` 20:17:32.057148（bind 行早 **0.84 ms**）
- R4-fast-2：L1706 `bind lock acquired` 20:18:17.107270 ← L1708 `detach lock released` 20:18:17.107372（bind 行早 **0.10 ms**）
- R4-fast-3：L1687 `detach lock released` 20:19:03.330386 → L1688 `bind lock acquired` 20:19:03.330648（正常序，+0.26 ms）

其余同口径检查：`SurfaceFailed/SurfaceRuntimeFailed/swallowed` 全程 0 条；HOME 后 `dispose` 0 条；bind 分支三轮均 `rebind wid=2258 boundWid=null previousInFlightWid=null stopPreviousFirst=false`；`ensure_init(lc_verify) exit initialized=0 … ready=0` 三轮各 1 次（新 VO 线程/新 EGL ctx：tid 26412/0x7407afe600、26655/0x7418b0d500、26898/0x7418034f80）。

## 4. 与 P0 结论的异同

**一致（亚秒区间复证）**：
- 链路与 P0 §0 完全一致：HOME → sd → detach 持锁 → `vo=null` → 旧 GL 线程 `mkst_shutdown` 清零 → ACK 严格晚于 shutdown 退出（43–141 ms，屏障成立）→ `wid=0` 链 1.6–2.3 s → 释放锁；返回 → 同 view `surfaceCreated`（`ensureInitializedCalledHere=false`）→ `SurfaceAvailable` 在持锁期到达 → bind 释放后即刻拿锁 → 新 VO 新线程 `ensure_init ready=0` → `bridge not initialized` → `yuv420p10`。
- shutdown 退出 → surfaceCreated 最小间隔从 1276 ms 压到 **463 ms** 仍保持"shutdown 先"——A2 设计屏障前提在 <1 s 区间不破。
- 无任何错误链/异常/dispose——失败是缺重初始化入口，不是竞态。

**新增/差异**：
- 间隔 597–841 ms 下 `SurfaceAvailable` 在 detach 持锁期到达得更早（提前量 903–1828 ms vs P0 405–1097 ms），bind 等待时长相应拉长，锁交接压缩至亚毫秒并出现上述日志行序倒置（P0 未出现；对 A2 无影响，但其"detach 释放锁→bind 拿锁 0–1 ms"的表述在亚秒区间应加"日志行序可能倒置"注脚）。
- `surfaceCreated` 早于 `mkst_shutdown` 退出的反例**未出现**：本批最小 sd→shutdown 退出 134 ms（R4-fast-2）而最小 sd→sc 597 ms，反例需要的 sd→sc ≲0.1–0.2 s 远低于本设备 activity 往返引擎下限（≈0.5 s，双侧 no-animation）。

## 5. 环境与偏差

- **USB 断连事故（环境失败，非代码失败）**：约 19:44 主机侧 USB 总线整体掉线（两台手机同时从 ioreg 消失，adb server 重启无效），已通知 Lead，用户重插后 20:03 恢复；恢复后重新核对装机身份（见顶部）与唤醒/解锁，继续执行。受影响的第一次 T1 尝试中断（无产物）。
- **驱动 host-probe 锚点近似**：chained 单 shell 使 `home_sent/return_sent` 探针都在整条命令返回后才记录，`return_sent → surfaceCreated` 的 timeline 值（−240/−324/−581 ms）只说明 sc 发生在 shell 返回前，不作为序关系依据；序关系全部以 `rt=` 为准。
- 亮度读数 41（P0 记录/本轮开局）→ 112（结束）：本驱动不含任何 settings 写入（driver.log/host-events 可审计），判定为自适应亮度自动漂移，未做回写（回写本身即改设置）。
- 设备结束状态：屏幕 ON、`isStatusBarKeyguard=false`、焦点在 launcher、hdr_lab 已 force-stop；`debug.mks.*` sysprops 与开局一致（`thermal_sync=display-resample`、`thermal_trace=1`、`yuv_frame_trace=1`，其余 0/空）；`accelerometer_rotation=1`、`screen_off_timeout=30000` 未动。
- 工作区：本轮（Verifier）未改任何源码（media-kit 5 个插桩文件保持 P0 状态未触碰）、未构建、未提交；本轮新增文件全部在 `docs/validation/home-return-session-restore-20261102/p0-trace/` 下（`run_round_fast.sh`、`fast_interval_check.py`、`calib/T1..T10/`、`R4-fast-1..3/`、本文件）。
- **并行改动（非本 Verifier，未触碰）**：本轮进行中（20:11 起）工作树出现 A2 实现改动——新增 `platformview/BridgeActivationAuthorizer.java`、`android_video_controller/bridge_activation.dart`、`test/bridge_activation_test.dart`、`tool/test_platform_bridge_activation.py`，修改 `MediaKitVideoPlugin.java`、`hdr_video_session.dart`、`platform_video_controller.dart`、`hdr_video_session_test.dart`（与 Lead 侧 A2 实现并行）。对本研究**无影响**：全部轮次跑在现装 P0 APK 上，装机身份在轮前、USB 重插后、**全部轮次结束后**三次核验均为 `76d77667…` / lastUpdateTime 17:13:14，设备端从未被重装。
- 未验证项：与 P0 相同——返回后画面推进未截图直证、`hwdec-current` 未从进程外读；另 `calib/T3..T10` 未保存 driver.log（host-events.ndjson 保留全部命令时刻）。
