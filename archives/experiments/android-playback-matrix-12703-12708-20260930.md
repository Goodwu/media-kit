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

## 追加：Redmi Note 5A（a869cea9）尝试（2026-09-30，用户要求中断，未成矩阵）

用户接入第二台设备 Redmi Note 5A（ugg，LineageOS Android 17，arm64-v8a，720×1280@60Hz）要求做同样测试。核验：`displayHdrTypes: []`、HWC `hdr10=false hlg=false`、`hdrOutputType=INVALID`（屏幕无 HDR 输出能力）；三套 4K 素材经华为机中转推送（字节数逐一吻合）。

- **ugg 第 1 轮（P5 Mystery SDR）**：打开事务在解码器配置处失败——`Failed to configure codec OMX.qcom.video.decoder.hevc (status = -542398533) width=3840 height=2160` → `Could not open codec`（骁龙 425 的 OMX HEVC 解码器不支持 4K）。三套素材实测均为 4K HEVC Main10（Mystery 3840×2160 / HDR10、P8.4 3840×1920），其余五轮必复现同一失败，矩阵在该机不可行；SDR/HDR 双向均被硬件能力阻断（HDR 另有屏幕无 HDR 能力）。
- **1080p 降级试播（用户明确"只是试试，不作严格判定"）**：Dolby 官方 P5 1080p（1920×1080 Main10 24fps 263s，重命名 `media-kit-p5-official-1080p.mp4` 推送）SDR 包 `cb27fa48…`。无图像，但根因在测试装置而非解码器：`PREOPEN_FULLSCREEN` 触发竖屏→横屏旋转（Transition #127，720×1280→1280×720），轮脚本按竖屏中心 (360,640) 的 tap 落在旋转过渡期内，`awaiting_tap` 未收到点击、素材未打开——该机 1080p 10-bit 硬解能力本轮**未测得**。用户随即要求中断，未重试（修正方向：等旋转稳定后按横屏坐标 (640,360) 点击）。
- 设备收尾：测试包已卸载、自动亮度恢复、熄屏（用户确认保留自动熄屏特性）。华为机维持 12708 后状态（原 12492、自动亮度、熄屏）。日志：`/tmp/matrix-ugg-p5-sdr-device.log`、`/tmp/matrix-ugg-p5-1080p-device.log`。
- 教训：轮脚本的 tap 坐标与解锁校验字段（`isKeyguardShowing` vs EMUI 的 `isStatusBarKeyguard`）均按机型硬编码，换设备需适配；应用在打开失败后停留失败状态约两分钟才被脚本清理，手持设备场景下观感为"卡死"。
