# Android Texture `mediacodec-copy` 位深门禁（2026-09-25）

11059 HDR10 与 11060 P8.4 的真机视频参数都报告 `pixelformat=nv12`、`averageBpp=12`，对应 8-bit 4:2:0；日志中的厂商输出 `eColorFormat 21` 即 Android `COLOR_FormatYUV420SemiPlanar`。锁定的隔离 FFmpeg `libavcodec/mediacodecdec_common.c` 将该格式映射到 `AV_PIX_FMT_NV12`，ByteBuffer copy 格式表无 P010。此前同机原生 MediaCodec ByteBuffer 探针已量到 3840×2160 帧大小为 `width×height×1.5`、color-format 21、未声明可读10-bit格式（计划 Current State 的2079/2081记录）；与当前两轮互相印证。

因此此前两个 Texture `mediacodec-copy` 会话只证明 8-bit copy 条件下的短时吞吐和画面变化，**不能证明** HDR10/P8.4 的10-bit基层保真或后续 SDR tone mapping 的颜色正确性。尽管最终 Texture 目标是 SDR，源在 tone mapping 前已降到8-bit，不能把这条路径设为符合原计划精度门禁的默认实现。

当前测试策略收紧：`AndroidHdrPlaybackPolicy` 默认仍请求直接 `mediacodec`；只有显式 `MEDIA_KIT_ANDROID_TEXTURE_COPY_DIAGNOSTIC=true` 才允许非P5 Texture 使用 `mediacodec-copy`，P5始终维持直接/保留RPU路径。轨道验收继续逐项匹配实际请求。11059/11060/11062/11063 是**改开关之前**的构建，其行为等同新开关开启；本轮策略收紧通过目标单测和 analyze，尚未打包重测。旧直接HDR10 Texture 11057/11058在厂商输出端口重配置时失败`-1010`，所以默认正确性候选当前仍未跑通。

后续应针对厂商 `0x325` 10-bit Surface 缓冲，把隔离P5 raw mapper的解码/导入/颜色域假设分离，建立 HDR10 与 P8.4 HLG 基层的10-bit GPU输入；P8.4不得应用RPU。现有P5 raw mapper在初始化时要求 `repr.dovi`，不能只开P5属性就套到HDR10/P8.4。需先解决直MediaCodec输出端口`-1010`和验证原始10-bit代码，再继续颜色/性能。原始11059/11060日志分别在 `artifacts/android-hdr10-texture-copy-20260925/`、`artifacts/android-p84-texture-copy-20260925/`。
