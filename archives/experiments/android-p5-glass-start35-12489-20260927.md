# P5 Glass 跳过黑场的诊断性首个内容计时，12489

## Current State

2026-09-27，华为 LYA-AL00/API29、自动亮度1；指定 Glass P5 3840×2160/59.94 原文件 SHA-256 `afb24b77733a3ca9071f0cfea0d0f7871670a7b6119eb44a314cba974541477c`。12489 诊断 APK SHA-256 `cf526f61d0378ee41eb9b8369bf08c2bc0f9edbdb93bc0e4cafa244e35c3297e`，同一正确 arm64 JAR SHA-256 `5b9495f72893b8b62bb9085c67c9e87707b04f5910d3f09e9a79df82efcfd2e2`。沿用12485 的 PixelCopy/洋红底色/临时预验证固定文件诊断补丁，另将 `MEDIA_KIT_ANDROID_PLAYING_START_SECONDS=3.5` 传入点击 Video 0 所用 `_openHdrSource` → coordinator → `Media(start)` 路径，避开0–约2.052秒的片源黑场。这不是产品默认行为，也没有保留为产品改动。

三次冷进程、点击后短播，默认 SurfaceProducer/Texture SDR。PixelCopy 对 Flutter SurfaceView 固定视频区域每约20ms取样，起点是点击回调内启动 Android 探针，不含触摸到回调。三轮都获得 `track_verified` 与 `ANDROID_SELECTED_START seconds=3.5`，无 `open_failed` 或 SIGSEGV：

| 轮次 | 洋红消失、变黑 | 首次非黑内容 | 轨道确认约 | 说明 |
| --- | ---: | ---: | ---: | --- |
| 1 | 2.331秒 | 4.034秒 | 2.512秒 | 非黑区域均值49.66、离散度32.92 |
| 2 | 2.867秒 | 4.245秒 | 2.747秒 | 非黑区域均值49.65、离散度32.93 |
| 3 | 2.547秒 | 3.966秒 | 2.405秒 | 非黑区域均值49.66、离散度32.92 |

12485 原片头0播放的同类PixelCopy三轮首次非黑为4.296/4.482/4.554秒。诊断性从3.5秒开始仅使首次非黑提前约0.3–0.6秒；轨道确认后到首次非黑仍约1.5–1.6秒。两包有起播位置和额外 Dart 日志差异，不能把绝对差值归因于片源黑场本身，也不证明 `Media(start)` 的实际首帧 PTS；应在原生首帧PTS/Flutter提交间继续分段。更不能把跳过片头计入通用首帧优化。

12487 初包遗漏PixelCopy开关，没有产生可用首帧数据；12488 虽开启探针，但点击 Video 0 路径未传3.5秒起播参数，三轮4.461/4.445/4.620秒仍属从片头播放，不是跳过黑场对照。另一次诊断属性缺 RPU 探针导致 P5 门禁拒绝，未进入播放，均未计入上表。

证据：`artifacts/android-p5-glass-start35-12489/pixel-copy-logcat.txt.gz`（SHA-256 `53eba2391ec2d03ee9c4b2e249a9b00099fffbecffca4a9a697c55f275d5c1cc`）及已撤销诊断补丁 `diagnostic.patch.gz`（SHA-256 `3edc68f7066233e79bffe9a37854ce4e60d2ce821d4ef1c873f8ab4a32e39c8e`）。测试后强停应用、恢复四项P5属性0、保持自动亮度1并熄屏。PixelCopy自身可能扰动渲染，样本没有真横屏全屏，也不等于物理面板扫描时间。下一步仍须在正常片头/正式路径追踪首个实际视频帧的PTS、提交与屏幕可见时间。
