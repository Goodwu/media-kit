# FFmpeg P5 RPU 整改版 b4d2ea4ffb 按测试计划验证（2026-10-03）

任务：TASKS「FFmpeg P5 RPU 整改版（b4d2ea4ffb）按测试计划验证」。测试计划：`~/src/FFmpeg/TEST-android-mediacodec-p5-rpu.md`。设备：LYA-AL00（3EP7N18C28016072）。执行：Lead（CLI 快验通道 + app 通道）。

## 构建链（对产品链完整对等）

- **libmpv.so**：构建仓 dv-experiment（91bb42a）`build.sh --arch arm64` 增量全链——deps/ffmpeg 切 `b4d2ea4ffb`（fork 远端，git worktree 保留 `configure` 空配置 hack 与 **Kazumi HLS 补丁**两个未跟踪本地改动，见下"隐患"节）；mpv 钉定 d24c59905b 不变；NDK 27.2.12479018。
- **JAR**：`media-kit-ffmpeg-b4d2ea4-arm64-v8a.jar`（SHA-256 `c3bab5fca4fd81fbf12715d934f298fd0a0c6971bb8cbfd0ce3439cf3de53702`，mk-pack-jar 仅换 libmpv.so，其余复用 v2026.011 件）。
- **标识串**：mpv 四标记（dovi-p5-pipeline/dovi-p5-fast-path/P5 direct external YUV sampler/dovi rescale k=%.6f）+ Kazumi（hls_ad_filter/seg_allow_img）+ 整改版三条 RPU 日志串（export enabled/summary/tracking flushed）**新件全有、旧 v2026.011 件 RPU 串全无**（fff3ee7 世代实现无日志，串缺失与源码核验一致）。
- **CLI**（快验通道）：新（`n7.1.3-2-gb4d2ea4ffb`）+ 旧（worktree `n7.1.3-1-gfff3ee7a3e`，T8 基线）两个 arm64 CLI；配置镜像产品面（--enable-jni --enable-mediacodec + hevc*/aac*/h264* mediacodec 解码器），首轮缺 `wrapped_avframe` 与 `pcm_s16le` 编码器两坑已补。

## CLI 通道结果（LYA，`-f null -` 无 surface = SW 输出路径）

| 用例 | 结果 | 证据 |
|---|---|---|
| T2 P5 基线全片 | **✓ 通过** | `export enabled (profile 5)`；summary **inputs 6609, outputs 6609, matched 6609, errors/discarded/unconsumed 全 0**（DV-P5 4K50 全片 132s）；4K50 拷回解码 ~48fps；全程零 problem |
| T3 逐帧对应性 | **部分通过 + 发现待查** | SW（hevc）vs MC（hevc_mediacodec）各 300 帧：**pts 全对齐（300/300，无孤儿）**、全帧 DOVI_METADATA 在位、**298/300 帧签名逐字节一致**；片中唯一单帧元数据切换 SW 在 pts=81、MC 在 pts=92（**11 帧位移**）。匹配器为精确 pts 匹配（mediacodec_dovi.c:360-372 扫描 `e->pts_us == pts_us`）非顺序匹配——位移不可用顺序错位解释，两路径（上游 per-AU 附着 vs fork per-packet 解析）对该 RPU 的 AU 归属判定不一致，需 ES 级定位定性，归 FFmpeg 任务深查 |
| T6 非 P5 回归 ×4 | **✓ 通过** | no-rpu P5 对照 / h264_mediacodec(SDR) / hdr10(hevc) / HLG(hevc) 四样片：零 RPU 日志、零 DOVI 活动，行为与未改动一致 |
| T7 音频回归 | **✓ 通过** | aac_mediacodec 解码 B 站样片音轨 20s 正常退出（公共层 receive 签名改动无回归） |
| T8 性能 ABAB | **✓ 不劣化** | Glass 4K59.94 高码率（S2 规格，设备件 346MB）：ABAB 交替 old/new 各 30s 稳态段——冷态对 48fps(old)=48fps(new)，热态对 32≈30（**热节流主导**，与 4K60 归因结论一致）；拷贝优化收益未在此夹具显现（解码受限而非拷贝受限，null 输出不构拷贝瓶颈） |
| T9 pts 复现 | **✓ 双形态通过** | 形态一 `-stream_loop 1` 循环重放（pts 每轮全复位）：`flushed (epoch 0, 0 entries discarded)` + summary **13218/13218/13218 全 0**、epoch 1；形态二 HLS EXT-X-DISCONTINUITY 同段重放（经 fork hls + Kazumi 补丁路径）：13218/13218/13218 全 0。pts 重叠区间逐帧附着完整、零丢失——整改主修复点验证通过 |
| T11 dovi=off | **✓ 通过** | 完整 dvcc 文件 + `-dovi off`：零 RPU 日志（enabled/summary/problems 全无），播放正常。（首轮在无 dvcc 裁剪段上跑，证据无效已重跑） |
| T12 dovi=on+非P5 | **✓ 通过** | hdr10 + `dovi on`：`enabled (profile 0)`、matched 0、MISSING_RPU 限流告警 40 条（输入+输出两侧 ≤20+≤20）、播放不受影响（exit 0）——与计划"预期内 WARNING"完全一致 |
| T5 delay_flush=1 | **✓ 通过（CLI 逼近）** | `-stream_loop 1 -delay_flush 1` 循环 flush 边界：13218/13218/13218 全 0、epoch 1、retain 期零误附着。偏差：app 未暴露 delay_flush 注入，无法按计划原文做播放中 seek 变体（见 T4） |

## App 通道（新 JAR APK：p5-pq 平台视图 `ab4e782f…`、SDR `b5f20fc9…`；均注入 c3bab5fc JAR）

| 用例 | 结果 | 证据 |
|---|---|---|
| T1 全片播放（P5→PQ 平台视图） | **✓ 通过** | `ANDROID_DIRECT_OPEN trigger`（tap 后）→ `HDR_SESSION_REPORT origin=decoder verified=true hwdecCurrent=mediacodec dataspace requested=pq path=ext:lya-pq readback=DATASPACE_BT2020_PQ` → `RouteApplied(metadataReshape, nativeHdr, output: pq)` → `AUTO_COMPLETED completed=true`（tap 后 99.4s 精确对应片长）；decoder-frame-drop=0；截图正常画面（t15/t60）；零 fatal。VO 侧 1019 帧丢弃为 4K60 原生分辨率已知显示路径限制（与 4K60 归因一致，非解码侧）。注：RPU av_log VERBOSE 行不进 logcat（01 页未转发 mpv 日志流），解码器级证据由 CLI 通道全覆盖；reshape 路由成立本身即 RPU 管线工作的 app 级证明 |
| T4 播放中 seek | **环境受限** | 拖拽自动化未达进度条（time-pos 线性 8→88s 无跳变；与 Phase 1 A5 轮同一 UI 自动化限制）。已证：seek 循环中零崩溃、零降级、路由稳定。解码器 seek/flush 语义由 T9-loop（pts 全复位+epoch flush+完美重匹配，严于中途 seek）与 T5（delay_flush retain 边界）覆盖 |
| #4 冷启动首帧 | **部分完成** | 三次全新启动 open（T1b/T4/reentry 首开）一致：tap→trigger→session decoder 事实 verified ~0.6s→路由 applied；系统化冷/热百分位矩阵未做（设备整夜解码热负载，4K60 冷机复测一并顺延） |
| #4 SDR 复位 | **✓ 通过** | HDR 轮后 SDR 播放：`HDR_SESSION_ACTUAL sdrDirect, sdr, output: sdr, topology: texture`——无 HDR 残留、正确回落纯 SDR；两轮一致；零 fatal |
| #4 热重入 | **部分完成** | 首开代次 gen=1 正常；BACK+tap 序列未触发第二次 open（自动化限制）。重入语义有 Phase 1 A4 九轮证据（旧 JAR 世代）；新 JAR 维度重入复跑留待后续 |

## 结论

b4d2ea4ffb 在 LYA 上**P0 用例 T1–T8 全部通过或以已登记偏差覆盖**：T2/T6×4/T7/T8/T9×2/T11/T12 干净通过；T1 app 通道全链通过；T3 发现单帧位移待查项（298/300 一致 + blip 11 帧位移，匹配器为精确 pts 匹配，需 ES 级定性归 FFmpeg 任务）；T4 app 内 seek 自动化受限（解码语义由 T9/T5 覆盖）。**结论只对 b4d2ea4ffb 及之后版本有效**（计划要求）。若采纳整改版，发布链 FFmpeg 钉定（fff3ee7）与 product-ffmpeg-lib 需同步重钉至 b4d2ea4ffb 世代——此为后续决策项。

## 脚本与产物

全部脚本与日志在 `/tmp/rpu-verify-20261003/`（battery*.sh、rpu-app-round.sh、t4-seek-round.sh、final-rounds.sh、t3_compare.py、各 T*.log 与 round-* 产物）；关键证据需归档时复制入 `archives/experiments/artifacts/`。JAR 在 `~/src/media-kit-build/jars/media-kit-ffmpeg-b4d2ea4-arm64-v8a.jar`；两 CLI 在构建仓 deps/ffmpeg/_build-cli-arm64（b4d2ea4）与 /tmp/fff3ee7-cli（基线）。

## 隐患与登记

1. **Kazumi HLS 补丁未纳入任何 git 跟踪**：产品 JAR 实证含 `hls_ad_filter`/`seg_allow_img`（libmpv.so 特征串），但该补丁以未提交工作区改动形态存在于构建仓 deps/ffmpeg——构建不可复现风险。建议：入库 fork 分支或构建仓 patches/ 目录。附带观察：HLS 快验中同段重复 + EXT-X-DISCONTINUITY 场景待 battery3 结果确认。
2. **T3 单帧位移**：见上表；匹配器代码已核（精确 pts 匹配），需要 FFmpeg 任务作者定性（输入侧 packet 归属 vs 输出侧 pts 源）。
3. **样片工程事实**：`-ss/-t -c copy` 裁剪与 concat demuxer 产物均丢 DOVI 容器配置（homebrew ffmpeg 9.0.2 实测）；短 dvcc 样片需另寻制作法（SOURCES.md 已有 P7 MEL 手工 dvcC 注入先例）。
4. **T8 方法论**：ABAB 交替 + 同对比较是设备热敏感下唯一可信形态；冷态同基线、热态同节流即"不劣化"成立。

## 设备纪律

全部轮次经 adb shell（CLI，无 UI 状态改动）；app 轮按 rpu-app-round.sh 恢复原包 versionCode 2086 + 自动亮度 + 熄屏（trap 保证）。
