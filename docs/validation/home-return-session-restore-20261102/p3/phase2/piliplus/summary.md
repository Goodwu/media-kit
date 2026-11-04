# P3 阶段二 (c) PiliPlus managed 宿主实机验收 summary（修后包）

日期：2026-11-03 00:24 – 01:05（Asia/Shanghai）。执行：Verifier（接续前一 agent 装机后中断处）。
设备：LG-H870DS（lucye，Android 7.0 / SDK 24，物理屏 1440x2880），serial `LGH870DS42e27764`，USB 连接，全程唤醒解锁。

## 1. 装机身份

- 本地构建包：`/Users/wuweiwei1/src/PiliPlus/build/app/outputs/flutter-apk/piliplus-p3c-a2-release.apk`
  SHA256 = `dd07a4a0c4be85e16ba0d6e7d1838a52a3230a3060c600a691552c4249cce816`。
- 前一 agent 的 pull 回读：`install-verify/base.apk` SHA256 = `dd07a4a0…cce816`（一致，本轮开始时核对）。
- 设备侧：`dumpsys package com.example.piliplus.dev` → codePath=`/data/app/com.example.piliplus.dev-1`，
  versionName=2.1.6，firstInstallTime=2026-10-20 00:09:17，**lastUpdateTime=2026-11-02 23:26:08**（验收结束时复核未变）。
- 结论：装机身份成立，未被重装或覆盖。

## 2. 方法与工具（`tools/`，全部可复跑）

- `run_pp_round.sh <round_dir> <mode>`：轮次驱动（normal/fast/fullscreen/sdr），逐 buffer 清 logcat，
  每步 host+device 双时间戳（host-events.ndjson），轮末 `exec-out logcat -d -v threadtime -b all`。
- 启动方式：DV 源 deep link `https://www.bilibili.com/video/BV1vY4y1N7TY?t=120`。`?t=` 由 PiliPlus
  `_videoProgress` 解析并**覆盖**观看历史续播（video/controller.dart `args.remove('progress')` 分支），
  保证每轮固定从 2:00 起播（视频总长 19:30，避免历史位置近 EOF 导致轮中自动切下一集）。
- 帧推进证据（核心，Lab 无法验证转来）三路并行，每轮多次采样（`sample-<label>-*`）：
  1. **SF latency 采样**：`dumpsys SurfaceFlinger --latency 'SurfaceView - com.example.piliplus.dev/com.example.piliplus.MainActivity'`
     （层名精确匹配），取最大 actualPresentTime（帧实际上屏时间，单调时钟 ns），多时间点差分；
  2. **渲染/解码线程 CPU 多点对比**：`/proc/<pid>/task/*/stat` utime+stime 差分（设备无 awk，用 cut；
     comm 含空格的线程字段会偏移，仅单 token comm 线程参与判定）；
  3. **media_session PlaybackState**：state（3=playing/2=paused/6=buffering）与 position。
  方法预验证（`tools/frame-evidence-trial/`、`tools/trial-n1/`）：暂停态 SF 冻结+线程近零，播放态
  SF 以 1:1 墙钟速率推进。已知局限：media_session position 仅在状态切换时发布（非连续）；
  SF --latency 按名字取第一个匹配层，SDR 路径存在多个同名 SurfaceView 层时可能命中空层（见 PP-E1）。
- `analyze_pp_round.py` → timeline.json/timeline.md（锚点带 rt=CLOCK_REALTIME ms 与 logcat 行号）；
  `check_chain.py` → chain.md（同 PID / 链序 / 身份 / 预硬解 / 零 FATAL·ANR）；
  `check_frames.py` → frames.md（帧推进判定）。

## 3. 逐轮判据表

| 轮次 | 场景 | 链判定 | 帧推进判定 | 同 PID | FATAL/ANR | 结论 |
|---|---|---|---|---|---|---|
| PP-N1 | DV 源 正常 HOME 10s | PASS 11/11 | PASS 6/6 | 10218=10218 | 0 | **PASS** |
| PP-N2 | DV 源 正常 HOME 10s | PASS 11/11 | PASS 6/6 | 11357=11357 | 0 | **PASS** |
| PP-F1 | DV 源 快速 HOME(方法F, 0ms) | PASS 11/11 | PASS 6/6 | 12419=12419 | 0 | **PASS** |
| PP-F2 | DV 源 快速 HOME(方法F, 0ms) | PASS 11/11 | PASS 6/6 | 13228=13228 | 0 | **PASS** |
| PP-B1 | 后台播放=关(默认) HOME→pause→返回→auto resume | PASS 11/11 | PASS 6/6 | 14050=14050 | 0 | **PASS** |
| PP-B2 | 后台播放=开 HOME 后继续播→返回画面恢复 | PASS 11/11 | PASS 6/6 | 16183=16183 | 0 | **PASS** |
| PP-S1 | 竖屏进全屏→HOME→返回 | PASS 11/11 | PASS 6/6 | 19416=19416 | 0 | **PASS** |
| PP-E1 | SDR 源 HOME（B1 门限回归） | n/a（判据为零授权） | 5/6（测量伪影，见 §6） | 21411=21411 | 0 | **PASS**（按判据） |

每轮 dropbox（data_app_crash/anr/native_crash/SYSTEM_TOMBSTONE）前后均 0。

## 4. 时间链差值（rt=CLOCK_REALTIME ms，返回链）

任务判据链：`mkst_shutdown exit` < Dart `authorize begin` < Java `authorize result code=ok`
< `mkst_ensure_init exit ready=1` < `mkst_create_decoder_window exit ok`(window_active=1) < 新 MediaCodec
实例化（makeComponentInstance → Now Executing）。全部轮次严格递增、同 app pid、身份闭合
（dart/java 同 wid；native 同 owner_key；surfaceGeneration 1→2，wid 换新）。

| 轮次 | shutdown→auth begin | begin→result | result→ready=1 | ready→window ok | window→新OMX |
|---|---|---|---|---|---|
| PP-N1 | 11167ms | 88ms | 54ms | 6ms | 44ms |
| PP-N2 | 11366ms | 159ms | 84ms | 8ms | 56ms |
| PP-F1 | 1896ms | 2ms | 74ms | 8ms | 79ms |
| PP-F2 | 2270ms | 2ms | 73ms | 5ms | 53ms |
| PP-B1 | 11305ms | 54ms | 60ms | 5ms | 46ms |
| PP-B2 | 9773ms | 36ms | 55ms | 6ms | 45ms |
| PP-S1 | 11698ms | 182ms | 130ms | 9ms | 60ms |

（正常 HOME 的 shutdown→begin 差值≈HOME 停留时长，属预期；F 组为 0 停留的紧凑链。）
Java 级 sd→sc（F 组）：surfaceDestroyed→(pause flush/Idle/teardown)→mkst_shutdown→surfaceCreated
（surfaceGeneration+1）→authorize…，全链同 pid，见各轮 timeline.md。

## 5. 预硬解确认（A 组每轮）

- 路由：`HdrDiag HDR predict/decision … class=dvP84 selected=baseLayerConvert presentation=nativeHdr`（每轮 ≥4 条）。
- 解码：`MediaCodec create pid=<app>` → `OMXMaster: makeComponentInstance(OMX.qcom.video.decoder.hevc)
  in mediacodec process` → `ACodec: [OMX.qcom.video.decoder.hevc] Now Executing`（预 HOME 段每轮 5+ 条）。
- 桥：`native mkst_create_decoder_window exit … window_active=1`；trial 截图 OCR 佐证 App 播放器媒体
  覆盖层 `hevc_mediacodec hwdec=surfacetexture 3840x1920 mediacodec`。
- dataspace：本构建无 `MKSURF-E1` tag；等价证据 `PlatformVideoView lgDataSpaceBinding stage=…` +
  `media_kit_vendor_ext lgPqApply stage=perform … invoked=1`（每轮 8 条，check_chain 的
  dataspace_applied_evidence 项）。

## 6. 帧推进证据（返回后自动 resume 为判据核心）

方法见 §2。数字为 SF actualPresentTime 差分（帧时间/墙钟时间）：

| 轮次 | 预 HOME 推进 | HOME 期间 | 返回后推进 1 | 返回后推进 2 |
|---|---|---|---|---|
| PP-N1 | +31.7s/25.7s | 冻结(state=2) | +17.4s/12.2s | +14.0s/14.0s |
| PP-N2 | +32.0s/26.8s | 冻结(state=2) | +17.7s/12.7s | +14.7s/14.6s |
| PP-F1 | +26.6s/26.6s | （0 停留） | +12.7s/12.6s | +14.5s/14.5s |
| PP-F2 | （pre-home 样本见 timeline） | （0 停留） | PASS | PASS |
| PP-B1 | PASS | 冻结(state=2) | PASS | PASS |
| PP-B2 | PASS | state=3（后台继续） | PASS | PASS |
| PP-S1 | PASS | 冻结(state=2) | PASS | PASS |
| PP-E1 | +25.5s/25.5s | 冻结(state=2) | 采样伪影（见下） | +62s（轮后复测持续推进） |

返回后 1:1 墙钟速率连续上屏 = 视频帧持续推进（非单帧/静帧）。线程侧佐证：返回后区间
demux/MediaCodec_loop/JNISurfaceTextu/Thread-9(EGL 渲染) 全部持续耗 CPU；HOME 期间（B1/B2 关态）
仅 Finalizer/HeapTaskDaemon。

PP-E1 帧采样伪影说明：返回后前两个样本（+5s/+15s）SF latency 命中的同名层返回 0 帧（SDR sdrDirect
路径存在多个 SurfaceView 层，--latency 名字查找命中空层；且返回后短暂 state=6 重缓冲）。补救证据：
logcat 显示返回后 +0.3s ACodec `Now Executing`；+29s 样本起 63 帧新上屏；**轮后复测**（01:05:30）
actualPresentTime 已推进至 423537s 且持续（相对 +29s 样本又 +62s），media state=3。E1 判据为
“零授权+播放正常+MediaCodec 正常”，据此判 PASS；帧推进证据链完整但覆盖度低于 A 组（如实记录）。

## 7. 后台播放两态（PP-B1/B2）

- 设置项：设置 → 播放器设置 →「后台播放 / 进入后台时继续播放」（`continuePlayInBackground`），
  UI 切换（uiautomator 语义树定位行与 Switch checked 状态，截图 `tools/b2-ui/10-13*.png`）。
  B2 前切 ON（checked=true 截图佐证），B2 后已还原 OFF（checked=false 复核）。
- B1（关，默认）：HOME → media state 3→2（pause），SF 无新帧，线程近零；返回 → 自动 resume
  （state=3，SF 1:1 推进，完整授权链重建）。
- B2（开）：HOME → state 保持 3，position 141100→149375（后台推进 8.3s），AudioTrack/demux 线程
  持续活动（音频在播）；画面层随 surfaceDestroyed 拆除（SF 0 帧，符合后台无画面）；返回 →
  surface 重建 + 授权链闭合 + 帧恢复推进（+12.7s/11.7s 起）。B2 期间链判定与帧判定均 PASS。

## 8. SDR 零授权（PP-E1，B1 门限回归）

- 源：推荐流首卡片（标题含"…4K HDR自然景观…"，实际播放流 HdrDiag 判定 `source=none class=sdr
  selected=sdrDirect`，即非 HDR 流）。
- 整轮 logcat：`authorize begin`=0，`authorize enter`=0，`mkst_create_decoder_window`=0；
  MediaCodec hevc 正常实例化并 Executing；HOME→pause（state=2）→返回 auto resume；同 pid；零崩溃。
- 判据满足：SDR 播放完全不进入 managed 授权链。

## 9. 设备结束状态

- `com.example.piliplus.dev` 前台（SDR 视频页，state=3 播放中），屏 ON，无锁屏；测试包未卸载（任务约定）。
- `continuePlayInBackground` 已还原为默认 OFF；系统设置/sysprop 未改动。
- 每轮 logcat 逐 buffer 清空、轮末 full dump 落盘；无 prefs 直接改动（设置切换全部走 UI）。

## 10. 偏差、失败尝试与未验证项

1. **PP-S1 尝试 1 失败保留**（`tools/s1-attempt1-fullscreen-not-triggered/`）：竖屏底栏全屏按钮
   存在（源码 `if (!isDesktopPip) .fullscreen`），但 面板自动隐藏(~3s) 与 截图/语义 dump(~1-2s)
   竞态导致首 tapping 未命中（该轮等效为一次 normal 轮，链/帧均正常）。尝试 2 改为单 shell 链式
   “显示面板+点全屏”（0.6s 间隔）后成功：截图 1440x2880→2880x1440，`mRotation=1`，返回后保持全屏。
   语义树无法看到播放器面板按钮（Flutter 未暴露该子树），uiautomator 定位方案对面板无效。
2. **PP-E1 尝试 1 失败保留**（`tools/e1-attempt1-no-video-opened/`）：推荐流双列瀑布，(720,700)
   命中列边界/无效卡，未打开视频（0 锚点，state=0）。尝试 2 改点左卡片 (360,800) 成功。
3. E1 frames.md 自动判定 5/6：采样伪影非播放失败（§6）。
4. SF --latency 多同名层首匹配局限：A 组（platformView 路径）未观察到伪影；SDR 路径已观察（§6）。
5. `MKSURF-E1: dataspace applied` tag 在本构建不存在；以 `lgPqApply stage=perform invoked=1` /
   `lgDataSpaceBinding` 作为 dataspace 应用证据（源码 `MKSURF_LOG_TAG="MKSURF"`，init/create/shutdown 行）。
6. media_session position 非连续发布（仅状态切换），不能单独作帧推进证据；已用 SF latency 补足。
7. 未验证/未做：1080p 以下画质切换下的行为、竖屏固定下长视频 EOF 自动切集与授权链交互、
   PiP/听视频路径（不在任务范围）；PiliPlus 不转发 mpv 日志，vo/缓存等 mpv 侧细节不可见（按任务
   预期以系统与桥日志为锚）。
8. 清单核对：`mkst_latch` 行未逐条分析（判据未要求）；本报告所有判定可在各轮
   `logcat-full.txt / timeline.md / chain.md / frames.md / host-events.ndjson / sample-*` 复核。

## 11. 产物清单

`piliplus/{PP-N1,PP-N2,PP-F1,PP-F2,PP-B1,PP-B2,PP-S1,PP-E1}/`：logcat-full.txt、logcat-pre-home.txt、
timeline.md、timeline.json、chain.md、frames.md、driver.log、host-events.ndjson、sample-*-mediasession/
sflatency/threads.txt、截图（after-launch/after-return 等，S1 另有 after-fullscreen、orientation dump）。
工具与中间产物：`piliplus/tools/`（run_pp_round.sh、analyze_pp_round.py、check_chain.py、check_frames.py、
analyze_screenshot.py、frame-evidence-trial/、trial-n1/、trial-round-N/、b2-ui/、s1-attempt1…/、e1-attempt1…/、
probe/ 为前一 agent 遗留探针产物）。
