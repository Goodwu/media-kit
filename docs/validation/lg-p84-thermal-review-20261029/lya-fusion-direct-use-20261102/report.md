# LYA 实机验证：无表融合=默认生产包直接使用（2026-11-02）

独立 Verifier 采集。只读验证 + 证据采集，未修改任何仓库源码，未重建 APK，未提交 Git。

## 0. 身份与环境

- 设备：Huawei Mate 20 Pro LYA-AL00（kirin980 / Mali-G76，API 29），serial `3EP7N18C28016072`。全程未触碰 LG（LGH870DS42e27764）。
- 被测 APK：`fusion-prod3-20261102-release.apk`
  - 主机 SHA256：`32b3fd204bb35cc328af3d882c90f9bf180e21fc582d44eb66b331f4a66434f0`
  - 设备 `base.apk` SHA256（pm path + sha256sum）：同上，一致。
  - 安装方式：`adb install -r`（保留数据），`lastUpdateTime=2026-11-02 12:34:35`，未 uninstall。
- 样片：设备 `…/files/hokkaido-p84.mp4`（由同目录 `DV-P8.4.mp4` `cp` 而来）
  - 两文件 SHA256 均为 `7626cac28819ffd1377a712b56c7cc4bbf8677f5db4b39fb0c83f92e58d74443`，与北海道原片一致；`DV-P8.4.mp4` 原样保留（时间戳仍为 2026-10-23）。
  - /sdcard 余量 78G。
- 唤醒与姿态：KEYCODE_WAKEUP + KEYCODE_MENU 唤醒（无密码锁屏），dumpsys power `mWakefulness=Awake`、`Display Power: state=ON`、`isStatusBarKeyguard=false` 核验通过。固定横屏（`accelerometer_rotation=0` + `user_rotation=1`；App 本身强制 landscapeLeft，每轮点屏前 `SurfaceOrientation: 1` 已核验）。亮度固定手动值 120（mode=0），三轮一致。
- 原始系统值（第 0 步记录，已恢复）：brightness=26、brightness_mode=1、accelerometer_rotation=1、user_rotation=0、screen_off_timeout=600000；`debug.mks.*` 原为空。

## 1. 三轮结果（事实）

每轮流程：force-stop → logcat -c → setprop+getprop 核验 → am start → 4s → 确认焦点/横屏/无锁屏 → tap(1560,720) → 确认播放已开（`ANDROID_HDR_OPEN` / `HdrDiag HDR decision` 立即出现，0s 延迟）→ 自开播 ~120s 采样 → 结束核验 → force-stop。三轮焦点窗口全程保持本 App（各 7/7 次采样无外部干扰，未再出现 PiliPlus 类打断）。

三轮共同事实（A/B/C 完全一致）：
- 路由（`HdrDiag HDR decision: phase=applied`）：`class=dvP84 selected=metadataReshape vo=gpu-next hwdec=mediacodec hwdecCurrent=mediacodec output=pq topology=platformView surface=pq peak=500 … requested=pq path=ext:lya-pq readback=DATASPACE_BT2020_PQ verified=true degrade=none`。
- 读回：`HdrDiag HDR readback: requested=pq path=ext:lya-pq applied=true readback=DATASPACE_BT2020_PQ`。
- 解码：硬解 `OMX.hisi.video.decoder.hevc`（ACodec 分配 3840x1920 native window buffer）。
- LYA 扩展自报（A 轮原文）：`ext: HdrDataSpaceExtInfo(id: lya-pq, applicable: true, pqPresentation: HdrPqPresentation(rgbSurface: true, yuvWindow: false), … yuvWindowArmApi: 0 …)` —— 与 Lead 静态预期一致。
- SF 视频层：`SurfaceView - …MainActivity#1`，2880x1440 @ (120,0)，`dataspace=BT2020 SMPTE 2084 Full range`，`activeBuffer=RGBA_1010102`；Flutter 层 #0 为 RGBA_8888（近乎静止）。
- 帧率（SF --latency，视频层，每轮 3 个 ~4.2s 窗口 × 3 轮 = 9 窗口全部一致）：`fps≈29.94–29.96`，中位帧间隔 32.73–32.75ms，p95=32.8ms，**视频层 0 个 >100ms 间隔**。
- 丢帧（SF 计数器轮内增量，+31s→+90s 两 dump 差值）：Total/HWC/GPU missed 增量均为 **0**（三轮同）。
- 健康度：无 FATAL / Fatal signal / ANR / tombstone（dropbox 最新条目停在 2026-10-30，今日无 crash/anr）；logcat crash buffer 空；轮末进程存活（PID 不变：A=32354、B=2030、C=3753）。
- 辅助数据（非验收）：App 进程 CPU%（top，7 样本/轮）A 均值 46.7（41.3–53.5）、B 46.7（44.8–50.0）、C 47.5（44.8–51.7）；`/sys/class/devfreq/gpufreq/cur_freq` 全程 139000000（min；该节点疑似不反映实时频率，仅记录）。GPU 负载节点不可读（mali0/utilisation 不存在）。
- 截图（60s 与 ~123s 各一张，3120x1440）：非黑像素 92.3%（7.69% 黑 = 两侧 120px 黑边，与视频层几何精确吻合），无全白/全黑帧；三轮 60s 截图 MAD（0-255）A↔C=1.0、A↔B=B↔C=5.9（同场景不同帧），~123s 截图内容不同证明帧在推进。视觉判读留给 Lead。

各轮差异（唯一差异项）：
- A（生产默认，`debug.mks.*` 全空）：`MKS-FUSION*`/`MKS-YUV-COMPARE*`/`YUV-DIAG`/`yuvDiag arm` 全部 **0**。
- B（`debug.mks.yuv_fusion=0`）：同 A，全部 **0**。
- C（`debug.mks.yuv_fusion_table=1`）：出现
  - `MPVLOG [vo/gpu-next] error: MKS-YUV-COMPARE event=egl-owner-configured android-current-verified=1 egl-loader-requested=1`
  - `MPVLOG [vo/gpu-next/libplacebo] error: MKS-YUV-COMPARE-LIB event=caps-ready private_ssbo=268435456 renderer_max_buffer=0 renderer_max_ssbo=0 fragment_blocks=35 bindings=70`
  - 其余仍全 0（无 `MKS-FUSION-TABLE` 任何事件、无 `caps-unavailable`、无 YUV-DIAG、无 armed/capture/abort 事件）。
- vendor 日志（`media_kit_vendor_ext`）三轮均仅 2 行 `p5PqFirmwareFallback perform=0 …`（LYA PQ 扩展自身），无任何 "yuvDiag arm"。

## 2. A 与 B 对照（是否等同）

| 观测项 | A（默认） | B（yuv_fusion=0） | 等同? |
|---|---|---|---|
| 路由 selected/topology/output/peak | metadataReshape / platformView / pq / 500 | 同左 | 是 |
| dataspace 读回 | DATASPACE_BT2020_PQ（applied=true） | 同左 | 是 |
| SF 视频层 | #1, 2880x1440, RGBA_1010102, BT2020 SMPTE 2084 Full | 同左 | 是 |
| 帧率 / 帧间隔 | 29.95–29.96fps / 中位 32.73–32.75ms，无 >100ms 间隔 | 同左 | 是 |
| 丢帧增量（Total/HWC/GPU） | 0 / 0 / 0 | 0 / 0 / 0 | 是 |
| CPU%（top 均值） | 46.7 | 46.7 | 是 |
| MKS-FUSION 等融合日志 | 0 条 | 0 条 | 是 |
| 进程存活 / crash / ANR | 存活 / 无 / 无 | 同左 | 是 |

结论（推断）：在 LYA 上 `debug.mks.yuv_fusion` 开关对行为无可观测差异——融合路径根本未介入（无 vendor YUV 窗口载体），A 即为默认安全路径。三轮均无共享层（libplacebo HOOKED_tex/renderer 等）在 Mali 上的渲染错误、丢帧或卡帧迹象。

## 3. C 轮（查表备选）判读要点

- 出现 `MKS-YUV-COMPARE event=egl-owner-configured`（Lead 预期的两个信号之一），随后 `MKS-YUV-COMPARE-LIB event=caps-ready`，说明 `configure_yuv_compare_egl` 在 LYA 上成功、libplacebo 能力探测完成；未出现 `caps-unavailable`（该行仅在 configure 失败时打印，见 ~/src/mpv/video/out/gpu_next/context.c:229-231 附近）。
- 无任何 `MKS-FUSION-TABLE` 事件：与静态预期一致——建表以 `fusion_available` 为前提（vo_gpu_next.c:3149-3152），LYA 上 `android_yuv_fusion_begin` 因 `!yuv_diag` 返回 false，种子路径不可达。
- 卡帧/中止帧迹象：无。视频层 9 个窗口中的 3 个（C 轮）帧间隔中位 32.73–32.74ms、p95=32.8ms、0 个 >100ms 间隔；轮内 SF 丢帧增量 0；无 armed/capture/fatal/force-stop 类 MKS 事件；进程存活。`diagnostic_abort_frame_no_gl` 虽被置 true（table=1 时），但无 YUV-DIAG swap 路径存在，未观察到任何 abort 行为。

## 4. 恢复核验

- `debug.mks.yuv_fusion` / `debug.mks.yuv_fusion_table`：均已清空，getprop 核验为空。
- 亮度模式恢复 auto（mode=1）；`screen_brightness` 字段读数 33（auto 模式下该值由系统实时调整，原记录 26 同为 auto 模式下的瞬时值——非残留手动值）。旋转恢复 accelerometer_rotation=1 / user_rotation=0，熄屏时长恢复 600000。
- 测试 App（prod3）与 `hokkaido-p84.mp4` 副本按用户裁决保留；`DV-P8.4.mp4` 未动。

## 5. 偏离计划与异常

1. **A 轮重跑**：第一次 A 轮（`A-default-run1-partial/`）因采集脚本两个缺陷（SF latency 循环内 adb 吞 stdin；#0/#1 层文件名截断撞名）缺少视频层帧率数据；其 logcat/健康度/路由数据完整且与重跑一致（融合计数同样全 0）。正式 A 轮为 `A-default/`。两份均保留。
2. `user_rotation` 会被系统在轮次结束后重置为 0（Huawei launcher 强制竖屏）；脚本在每轮开始前重设为 1，且 App 自身强制横屏（每轮点屏前 SurfaceOrientation=1 已核验），不影响轮次有效性。
3. Lab 的 `MPVPROP` 属性读回块为定 player 后 4s 的定时器：A 轮触发时播放尚未开始（读到 vo=null 空值），B/C 轮未输出——属测试 harness 时序伪影，不影响路由结论（路由以 `HdrDiag phase=applied` 行为准，三轮齐全）。
4. 唤醒后焦点曾落在 Huawei 钱包 SwipeActivity，按 HOME 回 launcher 后正常；A 轮 logcat 中 5 行 AndroidRuntime 为本验证 `input tap`（uid 2000）自身，非 App 崩溃。
5. `MKSURF: bridge not initialized (verify-only ensure_init; Java side owns init)` 仅在 preflight/A 两次出现（B/C 无）——verify-only 探针行，自带"Java side owns init"说明，后续 `MKSURF: version surfacetexture-poc-r2` 均正常，判为良性竞态，如实记录。
6. 未验证项：GPU 实时频率/负载（devfreq cur_freq 恒为 min、mali0 utilisation 节点不存在）；样片音轨/时长等媒体属性未探测；截图的视觉/PQ 判读留给 Lead；未做长时间（>120s）热态验证。

## 6. 证据文件清单（本目录）

- `summary.json`：机器可读汇总（身份、三轮计数、路由、帧率、CPU、SF 层、丢帧增量）。
- `run_round.sh`、`frame_stats.py`、`frame_stats_video_layers.txt`：采集与分析脚本及帧率汇总输出。
- `A-default/`、`B-fusion0/`、`C-table1/`：每轮 `logcat_full.txt`（完整转储）、`logcat_crash.txt`、`props.txt`（getprop 核验）、`state_prestart.txt`、`state_pretap.txt`、`timeline.txt`、`sf_layers.txt`、`sf_dump_1..3.txt`、`sf_latency_1..3_*.txt`、`top_samples.txt`、`gpufreq_samples.txt`、`focus_samples.txt`、`health_end.txt`、`screencap_60s.png`、`screencap_end.png`。
- `A-default-run1-partial/`：第一次 A 轮（日志/健康度有效，缺视频层 latency）。
- `preflight/`：20s 机械性预检（不计轮）。

## 7. Lead 审核（V0，2026-11-02）

- **抽查复核通过**：三轮 `logcat_full.txt` 独立 grep 复算——MKS-FUSION / MKS-FUSION-TABLE / YUV-DIAG / yuvDiag arm / FATAL / ANR 均 0；C 轮 MKS-YUV-COMPARE 2 行（egl-owner-configured、caps-ready）；三轮 `phase=applied … selected=metadataReshape … topology=platformView surface=pq` 与 OMX.hisi 硬解一致；props.txt 核验与轮次配置一致。
- **SF 双 SurfaceView 澄清**：`MainActivity#1` 为视频层（pos (120,0)、2880x1440、RGBA_1010102、BT2020 SMPTE 2084 Full、可见）。`MainActivity#0` 为全屏 3120x1440、z=-2、不透明、dataspace Default 的静态底层（即两侧黑边来源），B/C 的 `*_N0_` latency 文件（15 帧、2.90fps、2 个 >100ms 间隔）属于该静态层，不是视频帧率；A 轮 latency 文件名截断撞名，但其 127 帧/29.95fps 形态与 B/C 的 `#1` 一致。
- **MKSURF 行与融合属性无关（代码论证）**：`debug.mks.yuv_fusion` 全仓仅在 `~/src/mpv/video/out/opengl/context_android.c:388` 读取，位于 `draw_frame`（`vo_gpu_next.c:2593` 起，2917 调用）内的 `android_yuv_fusion_begin`；A 与 B 在首次绘制前代码路径完全相同（`yuv_fusion_table` 两轮均空）。该行���现在 hwdec 初始化、OMX 分配之前，故 preflight/A 有、B/C 无属初始化时序差异，且三轮播放健康度无差别。
- **视觉判读（team-vision）**：6 张截图均为正常视频内容（60s 雪地狐狸、结束时公园人物），无黑屏/纯色/花屏/马赛克/撕裂/色带/通道错乱/残留叠层，两侧黑边约 120px 符合几何；三轮同一时点场景一致（仅独立播放的帧相位差），60s 与结束帧不同证明帧在推进。PQ 层截屏偏灰属采集特性，不能代表面板 HDR 观感。
- **措辞修正**：§2 结论中“三轮均无共享层（libplacebo HOOKED_tex/renderer 等）在 Mali 上的渲染错误”应收窄为“本轮 metadataReshape 路线在 Mali 上无渲染错误、丢帧或卡帧迹象”。本轮未核实该路线是否经过 `custom_mpv.c` HOOKED_tex 宏路径；按 conversation 记录，该宏改动早于融合任务、非融合新增。
- **判定**：LYA 上融合（无表与查表）结构性不介入，已由实测证实；prod3 生产包在默认态、fusion=0、table=1 三态下 LYA 播放无回归，可直接使用。LYA 不获得融合收益（不存在可融合的末级 YUV pass）。
- **未覆盖**：每轮约 120s，无长时热态与生命周期（HOME/seek/暂停/EOF）；LYA 其它路线（baseLayerConvert、HDR10、HLG、P5、用户 shader）未测；无融合前二进制的 CPU/GPU 基线对照（A/B 同包对照只证明融合开关无影响）；Kirin GPU 频率/负载节点不可用；未做面板人眼观感；仅 Lab，不含 PiliPlus 宿主。
