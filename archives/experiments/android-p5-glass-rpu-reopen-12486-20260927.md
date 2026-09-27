# P5 Glass 同一播放器重复打开及 RPU 核对，12486

## Current State

2026-09-27，华为 LYA-AL00/API29、自动亮度。固定 Glass P5 4K59.94 原文件 SHA-256 `afb24b77733a3ca9071f0cfea0d0f7871670a7b6119eb44a314cba974541477c`，从片头 0 播放。12486 诊断 APK SHA-256 `6a9ff0367cfa160cad7c4cde12463fc741cea55e660289ff4dfabb2bc736fc0c`，arm64 JAR SHA-256 `5b9495f72893b8b62bb9085c67c9e87707b04f5910d3f09e9a79df82efcfd2e2`。APK 仅对 FFmpeg/mpv 日志开启 verbose，并沿用临时预验证固定本地文件入口；它绕过测试页整片哈希复制，不是产品打开路径或通用首帧优化。输出仍为默认 SurfaceProducer、P5 转换到 Texture SDR。诊断属性在应用进程启动**之前**设置为 `p5_raw_yuv=1`、`p5_direct_yuv=1`、`p5_rpu_probe=2`、`p5_dr_retire=1`。

同一 Player/进程在 Video 0 上相隔约 10 秒点击三次，三次 `requested`、`media_opened`、`track_verified` 均出现，没有 `open_failed`。第二次打开关闭前一段解码器时，`MEDIA_KIT_P5_RPU summary inputs=632 outputs=518 matched=518 errors=0 discarded=114 unconsumed=0`；第三次打开关闭前一段时，`inputs=616 outputs=596 matched=596 errors=0 discarded=20 unconsumed=0`。丢弃数与 flush 后不输出的输入记录分开计；这两段**实际输出**的 RPU 对应关系均为完整匹配。第三段退出后没有捕获到 summary，不能计作第三段完成核验；本轮也没有逐帧独立色彩参考或长时间反复重开的证明。日志中仅采到 590 条逐帧 MATCH，完整输出计数以两条解码器 summary 为准。此轮没有屏幕连续帧或首次可见帧计时，不能支持首帧/流畅性结论。

一次错误准备的三次点击发生在已启动的进程中才设置诊断属性；三次均在约 0.21 秒报 `P5 RPU attachment and raw YUV pipeline are not enabled`。该轮没有进入媒体打开，不纳入上述结果。为避免进程缓存属性，之后先强停再设属性/启动。

此前同 APK 运行较长的一次 P5 播放结束后重新进入应用，进程 23671 于 08:23:50 在 Android `FinalizerDaemon` 发生 SIGSEGV：栈由 Flutter `SurfaceTextureWrapper.release/finalize` 经 `SurfaceTexture.release`、系统 `ConsumerBase::abandon` 到 `pthread_mutex_lock`，fault addr `0x660`。当次新页面刚报告 `ANDROID_DIRECT_OPEN awaiting_tap`，尚未再次打开 Glass；随后的新进程能启动。仅有一次该崩溃，具体对象所有权/触发条件尚未确定，不能归因于 RPU 或简单断言是 Flutter 本身缺陷；应归入 Android Texture 生命周期回归继续复现与定位。

证据：`artifacts/android-p5-glass-rpu-reopen-12486/reopen3-logcat.txt.gz`（SHA-256 `5add3b822fce55179de9cd22692e316a0ed6a0e47c4ab88ab9e21ba569e0f162`），`relaunch-crash-extract.txt`（SHA-256 `4314ae92c38f76e1f412bb6ca98f9134a899d2bac06b557b3172f9091c5a5ce8`）。实验后关闭播放器、恢复四项诊断属性 0，自动亮度保持 1，手机熄屏。临时 Dart 预验证入口补丁已撤销；工作区原有的 Java/C++ 修改及图片未触及。
