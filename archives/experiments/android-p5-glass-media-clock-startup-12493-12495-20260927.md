# P5 Glass 首帧屏幕采样与播放器媒体时间，12493–12495

## Current State

2026-09-27，华为 LYA-AL00/API29，自动亮度1。指定 Glass P5 原文件及设备副本 SHA-256 均为 `afb24b77733a3ca9071f0cfea0d0f7871670a7b6119eb44a314cba974541477c`，从片头0播放；正确 arm64 JAR SHA-256 `5b9495f72893b8b62bb9085c67c9e87707b04f5910d3f09e9a79df82efcfd2e2`。默认 SurfaceProducer/Texture SDR、竖屏测试页，非真全屏。四轮均新进程点击 `Video 0`，实验前设置 P5 raw/direct/RPU/retire 属性为1/1/2/1；结束已全部复位0、强停应用、恢复原12492 APK、自动亮度1、屏幕OFF。

诊断仅在隔离工作树加入旧版洋红底色/Flutter Surface PixelCopy、临时预验证固定文件路径，以及点击后8秒内播放器 `stream.position` 日志。固定路径已在主机与设备分别核对SHA；它跳过测试页每次约10.4秒的整片哈希复制，不是产品优化。12493 每次位置事件都打印，12494/12495 将日志限为每100毫秒一个桶；12495 把PixelCopy回调后的间隔从20毫秒改为80毫秒。三包 APK SHA-256 依次为 `cf2105c51b633fb7f5b2e7c24c75d07cf51811b7357bcfb14e4d1c848180b225`、`3ffef37dccddfa3f814ee2f7179715f7c48da9cec26dd0e2b7c2123a9acd87c0`、`fdffa866250ca411aac354a35a6f98a0b12c633ca1c77b4f079aa5f0d6a66b5b`。起点是点击回调内启动原生采样，不含物理触摸到Dart回调。

| 轮次 | 位置日志 / PixelCopy间隔 | 首个AImage，媒体PTS | 洋红→黑 | 位置首次≥2.1秒 | Surface首次非黑内容 | 位置阈值→内容 |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| 12493 run1 | 每帧 / 20ms | 1.738s，0.050s | 2.091s | 4.082s | 4.415s | 0.333s |
| 12494 run2 | 100ms / 20ms | 2.013s，0.217s | 2.252s | 4.170s | 4.525s | 0.355s |
| 12495 run3 | 100ms / 80ms | 2.034s，0.250s | 1.988s | 4.151s | 4.466s | 0.315s |
| 12495 run4 | 100ms / 80ms | 1.985s，0.250s | 1.929s | 3.987s | 4.282s | 0.295s |

两轮80毫秒取样的首次内容与20毫秒两轮重叠，没有证据表明连续PixelCopy本身解释了全部等待；包版本、日志量与轮间状态仍有差异，不能严格定量其扰动。洋红变黑仍早于首个AImage的至少两轮，不能算视频首帧。原文件0–2.0秒均匀黑，2.1秒左侧已有内容；等待到约4.3–4.5秒才见内容，主要仍需分解媒体启动和首个有效画面提交，而不是只改等待底色。

**播放器 `stream.position` 是媒体时钟，不是已显示帧PTS。** 12494 run2 的位置221ms日志发生在首个AImage之前约0.95秒，直接证明不能以位置事件宣称该帧已经解码/提交/显示。4轮在位置首次达到约2.1秒后0.30–0.36秒才由PixelCopy检出内容，这只限定了时钟事件至当前Flutter Surface buffer可见内容的时间；还包含位置通知延迟、PixelCopy采样间隔和视频/显示队列，不能归因到Flutter或GPU。run2起播有FFmpeg `Could not find ref with POC`错误及ImageReader累计20次空取图，尚未证明其与所有轮的延迟有关。

下一步在保持同JAR基线或重新建立A/B基线的前提下，记录VO实际mix PTS、同序号提交成功及Flutter Surface消费；并分开量化 `media_opened` 到首个decoder release/AImage 的约1–2秒。仍须真全屏、物理屏幕可见、无高频探针的冷/热多轮验收，以及HDR10/P8.4/SDR对照。不能据此宣称2秒首帧已达标或已有产品性能收益。

原始日志：`artifacts/android-firstframe-media-clock-12493/run1-logcat.txt.gz` SHA `a77d053b402c0854c68acfca84fb5d018abd02ff3d583d4880b85d284170ebf2`；`run2-throttled-logcat.txt.gz` SHA `8020a98fd39484637cb8a6511a108b843c918433af759752721ee742ec6ee577`；`run2-startup-details.txt.gz` SHA `74ff5b4dbe8d2d8967d68c0ca0fd0baec9328e0c13040fd342931ea74653fe6c`；`run3-80ms-logcat.txt.gz` SHA `9092f80901c2b5e8b2005d8cf68b1003339c05a99110fa2fbd1b0640b613a7f4`；`run4-80ms-logcat.txt.gz` SHA `4d59d2a5259e6d735f0779eeccb9276faa590d48984e038c27a22a836ac24078`。隔离诊断补丁 `diagnostic-80ms.patch.gz` SHA `0f9fdd1fd7366a39275d0aa251a740f0598d52ad145c55d628ece4a0846de75c`；12493/12494分别为该补丁的逐帧日志/20ms取样变体，未进入产品代码。
