# Mystery Box P5→Texture SDR 自动优化实验全片（12561）

隔离实验分支的自建 arm64 JAR SHA-256 `9e4c851f365d2cecbd2df9ba7132025fbae402a67d0a183dbf0c53aa08a47eab`。FFmpeg 对 Profile 5 默认附加逐帧 RPU；mpv 对该流自动走外部 YUV、直接消费和缓冲退休路径，并在 SDR 2560×1440 Texture 目标关闭额外主缩放。四个 P5 调试属性均为0，SurfaceProducer=false，自动亮度，未切换电池性能模式。此轮是**隔离实验包**，不是已提交的清洁产品默认实现。12560 同 JAR 短轮曾记录 `P5_LINEAR_DECODE_FULL_HIT dst=2560x1440` 和实际画面；12561 低日志轮不输出该逐帧命中信息。

Mystery Box 同源 3840×2160、59.94fps、时长98.944秒，从普通页面播放至 `AUTO_COMPLETED completed=true`。Dart `t=28/60/90/120` 对应媒体25.742/57.741/87.738/98.944秒，VO累计掉帧20/20/23/23，decoder均0；t120 `eof-reached=yes`。按5930视频帧计，23约0.39%。GPU 1Hz 共115样本，中位415MHz，107个415MHz、5个208MHz、3个332MHz；thermal-status=1。EOS 截图为素材正常黑底尾卡。

同片未优化基准12546到EOS VO54、decoder0，GPU中位586MHz；本轮掉帧少31，且GPU采样频率更低。两轮热态及日志模式不完全一致，数值说明收益迹象，不证明通用性能门槛或真人流畅度。启动1×1阶段仍有两次 AImageReader `-30001` 映射失败。尚缺清洁依赖抽取、非P5回退、资源闭合与真人动态画质验收。

证据：`artifacts/android-p5-mystery-sdr-auto-12561/` 中全量日志 gzip、EOS后t120补采日志、GPU NDJSON和EOS截图。实验结束后恢复原12492 APK、四属性0、自动亮度模式1、`mWakefulness=Asleep`。
