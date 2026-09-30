# 四仓库归一后播放矩阵实机验收：P5/HDR10/P8.4 × SDR/HDR（2026-09-30）

## 背景

media-kit `main`（合并上游 236 提交，`a886f556` + 跟进提交）、mpv `media-kit/android`（发布 tag `media-kit-v2026.09`=398d0c3）、FFmpeg `fff3ee7`、libplacebo `c9fd879` 四仓库归一完成后，用户要求编译 demo app，对 DV P5/P8.4、HDR10 视频做 SDR、HDR 播放测试：全屏、最高亮度。设备 `3EP7N18C28016072`（LYA-AL00），六轮均结束恢复原 12492、自动亮度、熄屏（每轮 restore 输出核验 versionCode=12492、brightness_mode=1、mWakefulness=Asleep）。

## 构建与 define

六包均为 `flutter build apk --release --target-platform android-arm64`，JDK17 + `ORG_GRADLE_PROJECT_mediaKitLocalArm64Jar=/tmp/media-kit-p5-colorfix-398d0c3-arm64.jar`（发布基线 JAR，SHA-256 `dad30ae2…42c2a9f7`）。基础 define 集 = 12632 集去起播偏移（`AUTO_SINGLE_PLAYER`/`OPEN_ON_TAP`/`PREOPEN_FULLSCREEN`/`LOCAL_SOURCE`/`NAMED_LOCAL_SOURCE`/`P5_RPU_PIPELINE_BUILT`/`HDR_TRANSACTION`/`SURFACE_PRODUCER=false`/`TEXTURE_LAYOUT_SIZE`/`PERF_PROBE`/`P5_COUNTER_PROBE`/`DIRECT_OPEN_TRACE`）。SDR 轮不加 `PLATFORM_VIEW`（Texture 路径）；HDR 轮加 `PLATFORM_VIEW=true`，其中 P5 PQ 另加 `GPU_PLATFORM_HDR=true`（=12701 组合），HDR10/P8.4 不加（走 mediacodec_embed 直出，即 12537/12538 既有路径；P8.4 gpu-next/HLG 公开 dataspace 本机拒绝，见 12607/12608）。构建脚本 `/tmp/matrix-build.sh`、轮次脚本 `/tmp/matrix-round.sh`（新增最高亮度 255 + 恢复）、像素判定 `/tmp/pixel-judge.py`。

APK SHA-256（`/tmp/matrix-<tag>.apk`）：

| 轮 | tag | 模式 | SHA-256（前 16） |
|---|---|---|---|
| 12703 | p5-sdr | Mystery P5 → Texture SDR | 2620de1746cb1fbb |
| 12704 | p5-pq | Mystery P5 → PQ（gpu-next/RGBA1010102） | 707e65b777d7ef76 |
| 12705 | hdr10-sdr | HDR10 → Texture SDR | 28053ce793195e87 |
| 12706 | hdr10-hdr | HDR10 → mediacodec_embed PQ | 02c5d8b813d0a04d |
| 12707 | p84-sdr | P8.4 → 剥 RPU + Texture SDR | b6283266a937d2b2 |
| 12708 | p84-hdr | P8.4 → mediacodec_embed HLG | bc9613de1adac8be |

素材（设备 `/data/local/tmp/`，时长实测）：`media-kit-p5-mystery-box.mp4` 98.944s、`media-kit-hdr10-full.mp4` 304.768s、`media-kit-p84-full.mp4` 1170.730s。

## 轮次证据

- **12703 P5 SDR 全片**：`ANDROID_HDR_OPEN sample=dolbyVisionP5 gpuPlatformHdr=false`；`P5_SECTION_INIT direct=1` + `P5_DOVI_RESCALE enabled k=1.002941`；EOS `AUTO_COMPLETED completed=true`（~99s 与片长一致）；零渲染失败；退出闭合 `P5_IMAGE_FINAL 5902/5902 retired=0`；t30/90/115 截图像素统计正常画面（t115 为片尾落版）。`ANDROID_TEXTURE_PREPARED fallback=surface_or_layout_unavailable` 与已验收 12700 同字样，非回归。
- **12704 P5 PQ 全片**：`gpuPlatformHdr=true`；direct=1 + RESCALE k=1.002941；SF 视频层 `dataspace=BT2020 SMPTE 2084 Full range`、`defaultPixelFormat=RGBA_1010102`（10 位 PQ 视频层 + 系统合成）；片尾 `P5_TAIL_FALLBACK requested_pts=98.74865 previous=98.731967 delta=16.683ms`（与 12701 同位置命中）且零渲染失败；EOS completed=true；闭合 5423/5423 retired=0（empty_acquires=10 即该次回退的取图失败）；t30/90/115 正常画面。
- **12705 HDR10 SDR 全片**：vo=gpu-next、hwdec=mediacodec、`target-trc=bt.1886`（tone-map 到 SDR）；EOS completed=true（16:57:18，~305s 与片长一致）；零渲染失败；闭合 9127/9127（尾部 empty_acquires=10 与 OMX 卸载同毫秒，无渲染错误）；t30/90/150/240 正常画面，t320 为 EOS 后黑屏（收尾正常）。
- **12706 HDR10 HDR 全片**：vo=mediacodec_embed、hwdec=mediacodec；SF 视频层 `dataspace=BT2020_ITU_PQ` 且 `hdr metadata types=3`（HDR10 静态元数据随层传递）；EOS completed=true；零渲染失败；t30/90/150/240 正常画面。
- **12707 P8.4 SDR（5 分钟观察窗）**：vo=gpu-next、`vf=@media-kit-p84-base:format=dolbyvision=no`（RPU 剥离生效）、`target-trc=bt.1886`、`dolby-vision-profile=8`；零渲染失败；闭合 9706/9706 retired=0；t30/90/150/240/300 全部正常画面。
- **12708 P8.4 HLG HDR（5 分钟观察窗）**：vo=mediacodec_embed、hwdec=mediacodec；SF 视频层 `dataspace=BT2020_ITU_HLG`（STD-B67）；零渲染失败；t30/90/150/240/300 全部正常画面。

P8.4 全片 1170.7s（~19.5 分钟），两模式各播 300 秒观察窗，未追 EOS；P5/HDR10 四轮均全片到 EOS。六轮全屏（PREOPEN_FULLSCREEN）+ 最高亮度 255（每轮核验 `brightness_value=255`）。

## 结论

四仓库归一后的发布链（mpv 398d0c3 + FFmpeg fff3ee7 + libplacebo c9fd879 + media-kit main）在 P5/P8.4/HDR10 三素材 × SDR/HDR 双模式六轮全屏最高亮度播放中全部通过：输出路径与预期一致（P5 SDR 直通重标定、P5 PQ 10 位视频层、HDR10 PQ 直出含静态元数据、P8.4 HLG 直出/剥 RPU SDR），EOS/片尾回退/资源闭合零异常，截图全部正常画面。遗留：P8.4 全片 EOS 与真人观感未在本轮范围（用户此前已认可 P8.4/HDR10 全屏画质与流畅性，12537/12538 及 12616）。

- 证据：`/tmp/matrix-round-<tag>-{device.log,sf-t45.txt,t*.png}`、构建日志 `/tmp/matrix-build-<tag>.log`。

## 追加：Mi Note 3（5b79aada）一轮解码测试（2026-09-30，用户指定单轮）

用户换入第三台设备 Mi Note 3（jason，骁龙 660，LineageOS Android 15，arm64-v8a，1080×1920，无 HDR 显示）并要求"进行一轮解码测试"。核验：HWC `hdr10=false hlg=false`（与用户说明一致）；`OMX.qcom.video.decoder.hevc` 标称 **Main/Main10/Main10HDR10 × Main 5.1**（4K 10-bit 在能力表内）。素材 Mystery Box（361,648,124 字节与华为机一致）；复用 12703 SDR 包（SHA `2620de17…`）；轮脚本 `/tmp/matrix-round-jason.sh`（修复 Redmi 暴露的旋转竞态：tap 后验证 `DIRECT_OPEN trigger`，未命中换横/竖坐标重试；本次首轮命中）。

**结果：4K Main10 硬解通过，展示链路掉帧严重，EOS 尾帧紫屏一次。**

- **解码：通过**。无 CodecException；`P5_SECTION_INIT direct=1`（P5 直通管线激活）、vo=gpu-next/hwdec=mediacodec；`decoder-frame-drop-count=0`，EOS `AUTO_COMPLETED completed=true`，媒体时间 ~实时推进（t60→55.5s、t90→83.8s、t120→98.9s）。
- **展示：掉帧 84%**。EOS 时 `frame-drop-count=4980`（全片约 5937 帧、AImage callbacks 仅 950）——Adreno 512 的 gpu-next 4K 渲染跟不上 60fps，VO 层丢帧但解码与音画时间轴正常（avsync=0）。画面可播但不流畅。
- **丢帧机制判定（应用户追问"是否解码出来超时限被丢弃"核实）**：**是**。证据链：① `decoder-frame-drop-count=0` 且总账闭合——4980（VO 丢弃）+ ~950（实际送显）≈ 5935（全片 98.944s×59.94fps），说明 Venus 解码器把全部帧解出并交给 mpv，无一在解码器内部丢失；② 被丢帧发生在**渲染上传之前**：mp_image 仅携带 AVMediaCodecBuffer，mapper 在 map 时才 `av_mediacodec_release_buffer(buffer, 1)` 推入 AImageReader（`hwdec_aimagereader.c` map 路径），VO 按 display-sync 时限丢弃的帧从未 map、经 FFmpeg 默认释放路径 `render=0` 归还 codec——callbacks 仅 950 正是"只有真正渲染的帧才进过 reader"；③ 掉帧率从开播起恒定 ~48.7 帧/秒（60−~11），为渲染吞吐恒定不足的稳态特征。解码吞吐本身 ~57fps（EOS 用时 ~104s 推算，略低于 60fps 实时，导致 avsync 线性涨至 4.9s、帧系统性迟到），但数量级上主瓶颈是 Adreno 512 的 4K dovi→SDR GLES 渲染（~9.6fps 送显），mpv 为保持播放进度丢弃其余约 5/6。
- **色彩**：无 `P5_DOVI_RESCALE` 行（华为专属 Y2Y /1020 归一化补偿在本机不触发，SD660 输出标准 Main10 布局，符合预期）。t30 截图较华为同片偏暖，但非同 PTS 场景，不作色彩结论。
- **EOS 尾帧问题（观察项，非本轮判定范围）**：最后帧 PTS 98.915 `acquireLatestImage failed after retry: -30001`（empty_acquires=20、retired=1）→ 1 次 `Failed rendering frame`，**相邻帧回退未触发**（P5_TAIL_FALLBACK 计数 0；华为同片 EOS 位置 98.748 能命中回退），EOS 后画面呈纯紫（未初始化纹理，t115 截图 mean=(128,0,255) var=0）。回退条件在本机 EOS 场景未满足的原因未查（候选：末帧相邻 PTS 间隔或 retired 状态差异），与 P3 片尾任务相关，待后续跟进。
- **证据缺口**：退出时 `P5_IMAGE_FINAL` 闭合计数未采集——BACK 后 6 秒 grep 时 NativePlayer.dispose 的 5 秒终止宽限期未走完，logcat 先被轮脚本关闭；无 FATAL/SIGSEGV、force-stop 后卸载成功。
- **解码吞吐复测（应用户"不做渲染的解码速度"要求，纯解码探针轮）**：**达不到 60fps，按用户标准终止推进**。测试页 `P5_CODEC_PROBE` 原生探针（`P5CodecProbe.java`，surface 模式 + ImageReader 即取即弃、无渲染无反压），全片 5930 帧+RPU 全量输入（`rpuMatchedOutputs=5930`、`stalled=false`、`inputEos=true`），5931 帧输出耗时 **133.4s，平均 44.4fps**。该数字含探针自身 Java 喂数开销（MediaExtractor 单线程 + 每输入帧 RPU NAL 扫描），为下界；但结合播放轮实测有效解码速率 ~57fps（5930 帧/104s，且该轮还含渲染停顿），**任何测量口径下均低于 60fps**，且播放轮 avsync 全片线性增长（~52-58ms/s ≈ 5% 恒定缺口、无热恢复）证实非暂时性。结论：Venus（SD660）对 4K HEVC Main10 DV P5 的解码吞吐封顶 <60fps，"严格按时间解码 60fps 源"在该机不可达；渲染侧优化（前述 30fps 路径）随之按用户决定不再推进。探针包 SHA `6987a451…`，轮脚本 `/tmp/decode-probe-round.sh`，日志 `/tmp/matrix-jason-decode-probe-device.log`。
- **用户观感反馈与诊断（HDR10 4K30 轮）**：用户报告开场数个场景画面抖动、绿色横条色块（部分呈左下→右上斜线分隔的撕裂形态），中后段基本正常、偶发绿色色块。截图（t30/90/150/240）逐行绿色检测未捕捉到（瞬态）；日志零渲染失败/零取图错误（OMX set_parameter 报错为各机型通有的良性探测失败）。机制判定：**① 抖动**=开场 29 帧丢失在 30fps 内容上的节奏跳动（启动收敛期，稳态零丢帧后消失），非缺陷；**② 绿块/斜线撕裂**=OES 路径（非 P5 内容 direct=0）缺少 direct 路径的 buffer 生命周期保护——`mapper_unmap` 在 `direct_retire=false` 时既无 sample_fence/retired 持有也无 `gl->Finish()` 屏障，`DestroyImageKHR`+`AImage_delete` 立即归还 buffer；若 GL 异步采样尚未完成而 codec 已重写该 buffer（Adreno 512 无 Mali 式隐式同步），采样读到半写数据→斜线撕裂、读到未初始化区域→绿色（NV12 全零）。时间相关性吻合：开场（丢帧+重绘频繁+buffer 高速循环）密集、稳态干净、偶发重绘触发偶发绿块。待验证区分项：老 Venus 固件启动期前几帧输出本身损坏（codec 问题而非管线竞争）可用探针 `cpuRead` 读回前 30 帧像素区分。修复方向（未实施）：retire+fence 机制扩展到 OES 路径（风险：OES 持有 buffer 延迟 codec 回收，maxImages=3 下需实机 A/B）或 OES unmap 前加 Finish 屏障（有每帧 Finish 开销）。**图像复核（glm-5.3-flash-free 子代理逐张查看，2026-09-30）**：四张定时截图（t30/90/150/240）全部判定正常画面，每张附饱和绿像素扫描交叉验证（命中 0）——t30 为测试片自带的 SDR/HDR 左右分屏演示（片源内容、附文字标注，垂直分割非斜线），t90 绿色帐篷、t150 草地特写均为自然场景内容。瞬态绿块/斜线撕裂未被定时截图捕捉，与"瞬态、集中于开场收敛期"的机制判定一致。素材即矩阵 HDR10 fixture（3840×1920@29.97fps Main10，305s），复用 12705 SDR 包。全片 EOS 准时到达（304.7s 与片长一致）、时间轴 1.0x 无漂移（t270→269.0、t300→299.0）；**全片仅丢 29 帧（~9131 帧的 0.3%），且全部集中在开场前 30 秒的启动收敛期，29s 后至 EOS 零丢帧**；`decoder-frame-drop-count=0`、avsync 全程 ~30 微秒、零渲染失败；截图像素统计全部正常画面（t320 为 EOS 后黑屏）。对比 4K60 P5 轮：30fps 源在解码上限（44–57fps）内且非 dovi 渲染路径更轻，解码与渲染双侧均有余量——**该机 4K30 HEVC Main10 SDR 播放完全可用**。日志 `/tmp/matrix-jason-hdr10-sdr-device.log`。
- 收尾：测试包卸载、亮度 50/自动恢复、熄屏。日志 `/tmp/matrix-jason-p5-sdr-device.log`、截图 `/tmp/matrix-jason-p5-sdr-t*.png`。

## 追加：Redmi Note 5A（a869cea9）尝试（2026-09-30，用户要求中断，未成矩阵）

用户接入第二台设备 Redmi Note 5A（ugg，LineageOS Android 17，arm64-v8a，720×1280@60Hz）要求做同样测试。核验：`displayHdrTypes: []`、HWC `hdr10=false hlg=false`、`hdrOutputType=INVALID`（屏幕无 HDR 输出能力）；三套 4K 素材经华为机中转推送（字节数逐一吻合）。

- **ugg 第 1 轮（P5 Mystery SDR）**：打开事务在解码器配置处失败——`Failed to configure codec OMX.qcom.video.decoder.hevc (status = -542398533) width=3840 height=2160` → `Could not open codec`（骁龙 425 的 OMX HEVC 解码器不支持 4K）。三套素材实测均为 4K HEVC Main10（Mystery 3840×2160 / HDR10、P8.4 3840×1920），其余五轮必复现同一失败，矩阵在该机不可行；SDR/HDR 双向均被硬件能力阻断（HDR 另有屏幕无 HDR 能力）。
- **1080p 降级试播（用户明确"只是试试，不作严格判定"）**：Dolby 官方 P5 1080p（1920×1080 Main10 24fps 263s，重命名 `media-kit-p5-official-1080p.mp4` 推送）SDR 包 `cb27fa48…`。无图像，但根因在测试装置而非解码器：`PREOPEN_FULLSCREEN` 触发竖屏→横屏旋转（Transition #127，720×1280→1280×720），轮脚本按竖屏中心 (360,640) 的 tap 落在旋转过渡期内，`awaiting_tap` 未收到点击、素材未打开——该机 1080p 10-bit 硬解能力本轮**未测得**。用户随即要求中断，未重试（修正方向：等旋转稳定后按横屏坐标 (640,360) 点击）。
- 设备收尾：测试包已卸载、自动亮度恢复、熄屏（用户确认保留自动熄屏特性）。华为机维持 12708 后状态（原 12492、自动亮度、熄屏）。日志：`/tmp/matrix-ugg-p5-sdr-device.log`、`/tmp/matrix-ugg-p5-1080p-device.log`。
- 教训：轮脚本的 tap 坐标与解锁校验字段（`isKeyguardShowing` vs EMUI 的 `isStatusBarKeyguard`）均按机型硬编码，换设备需适配；应用在打开失败后停留失败状态约两分钟才被脚本清理，手持设备场景下观感为"卡死"。
