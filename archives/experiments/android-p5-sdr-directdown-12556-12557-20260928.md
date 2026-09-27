# P5→Texture SDR 直接降采样短轮与 Glass 全片（2026-09-28）

## 输入及隔离

- 华为 LYA-AL00/API29，Glass P5 4K59.94 固定设备文件；真横屏窗口 3120×1440，视频 Texture 2560×1440。自动亮度、未切性能模式。
- 隔离 Goodwu/mpv 实验分支 `63a0aa9` 包含外部 YUV/direct AImageReader、缓冲回收和诊断属性；Goodwu/libplacebo `c9fd879` 包含 `optimize_dovi_linear_decode`。本轮在隔离 mpv 的 P5+DV 映射+BT.1886 作用域设 `optimize_dovi_linear_decode=true` 且将主 `downscaler` 设为 `NULL`，使直接降采样候选可触发。此代码尚未抽成清洁产品实现。FFmpeg 使用前次已验证可逐帧附加 RPU 的本地静态库；`p5_rpu_probe=2,p5_raw_yuv=1,p5_direct_yuv=1,p5_dr_retire=1` 仍是诊断依赖。
- 先前 12553 使用默认 SurfaceProducer，虽屏幕视频区为 2560×1440，实际 `setSurfaceSize` 为 3840×2160，故没有 `SAMPLER_DOWN`。本轮测试页同时设置 `MEDIA_KIT_ANDROID_TEXTURE_LAYOUT_SIZE=true`、`MEDIA_KIT_ANDROID_SURFACE_PRODUCER=false`；设备日志确认 `setSurfaceSize 2560 1440`。预建 Texture 初始 1×1，不能把初次优化命中当成正式尺寸命中。

## 短轮命中与画面

- 12556 的 libplacebo 一次性日志同时有 `P5_LINEAR_DECODE_HIT` 和 **`P5_LINEAR_DECODE_FULL_HIT dst=2560x1440`**；输入 `sys=DolbyVision`、PQ、有 RPU，渲染目标 BT.709/BT.1886。视频区截图是实际吹玻璃画面，无洋红残影；媒体 17.384 秒 VO 累计 19、decoder 0。初始 1×1 阶段两次 `acquireLatestImage -30001` / `Failed rendering frame!`，之后持续出画；不能把此短轮判为零错误稳定验收。
- 一次性命中探针只证明该 renderer 曾以 2560×1440 进入优化分支，不证明每帧都命中；对直接降采样的画质目前只有屏幕截图，尚无人眼动态验收或同 PTS 数值比较。

## 低日志 Glass 全片

- 12557 保持同一自建 arm64 JAR SHA-256 `944e5f04e69ffce12eacbb84ae80dbd1020dcce9a203d57d042615d418d61d89`，关闭 mpv verbose，保留每10秒 Dart 计数。APK SHA-256 `ee9c3b99c9bd34706542196d6ce196daacd55a6e38337304c0b25f9bfa6dbf3c`；APK 的实际 `versionCode` 仍为 12553，12557 只是实验轮次标签。
- 媒体 7.69/87.70/167.70/177.78 秒的 VO 累计掉帧分别为 9/16/32/34，decoder 均为0；最后时间停在 177.783 秒，连续三次10秒采样保持不变。约 t87→末端新增18，显著低于旧优化轮 t90→t180 的342，但不同构建、日志与设备频率，不能单独将差异归因于线性解码。没有显式 `end-file` 事件，严格 EOS 仍待补证。
- GPU 频率每2秒采样95次，中位415MHz、范围208–415MHz；此前 Mystery Box 未优化轮中位586MHz，不应跨片比较。片尾截图为 Dolby Vision logo，不是先前紫色清屏；只覆盖这一轮，片尾故障尚未排除。
- 初始 1×1 阶段仍有两次 `acquireLatestImage -30001` / 渲染失败，之后无同类报错或 GL OOM。片尾只有单张截图，缺连续帧与真人观感。不能据此关闭 P0 或 P3。

## 证据与收束

- `artifacts/android-p5-sdr-directdown-12556-12557/` 保存短轮命中日志、低日志全片 logcat、GPU NDJSON、短轮及片尾截图。全片 log SHA-256 `e482d10b7ee11f405bbadcfc17e5d01d08fc6df0f31205b207c2f8a38618f290`，GPU NDJSON SHA-256 `7c39f94d8aba237611ebc7493b28597cee04354e6224bd15490f7a3166904cc1`。
- 实验结束恢复原 12492 APK，四项 P5 诊断属性为0、自动亮度模式1、屏幕熄灭。下一步将外部 YUV、RPU 附加与直接降采样的必要部分抽入清洁 arm64 产品依赖；单独验证其他输入/目标回退、同 PTS 画质和资源，然后跑 Mystery Box 同片比较。
