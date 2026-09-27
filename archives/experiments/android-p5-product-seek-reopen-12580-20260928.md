# P5→Texture SDR 最终 JAR 的 seek/同播放器重开（12580）

2026-09-28 在测试 App 增加默认关闭的 `MEDIA_KIT_ANDROID_AUTO_SEEK_AT_SECONDS`、`MEDIA_KIT_ANDROID_AUTO_SEEK_TARGET_SECONDS`、`MEDIA_KIT_ANDROID_AUTO_REOPEN_AFTER_SEEK` 探针；Dart 静态分析与 arm64 APK 构建通过。12580 使用已提交 Goodwu/mpv `8e7c23e` 的自建 JAR、Mystery Box P5、预建横屏全屏 Texture→SDR、`gpu-next`/`mediacodec`、2560×1440、默认电池/自动亮度。配置媒体8秒 seek到45秒，确认继续播放2秒以上后，用同一 `Player` 重开同一源，再确认播放2秒以上。

日志：`seek_begin position=8.008 target=45`、`seek_playing position=47.014`、`reopen_begin position=47.014`、`reopen_playing position=2.002`。seek后及重开后截图分别有海岸与飞机实际画面（临时文件 `/private/tmp/media-kit-p5-12580-after-seek.png`、`/private/tmp/media-kit-p5-12580-after-reopen.png`）；重开后的 t28 VO4、decoder0。正常退出 `P5_RETIRE_FINAL held_after=0`、`P5_IMAGE_FINAL acquired=2539 deleted=2539 retired=0`。

seek开始时旧 PTS8.008 的映射仍报一次 `acquireLatestImage failed after retry: -30001` / `Failed rendering frame!`，随后45秒处播放及重开均恢复。故本轮证明基本功能恢复与资源闭合，**不证明 seek 边界无渲染错误或无残影**；该边界问题纳入 P3 生命周期故障。过滤日志 `/private/tmp/media-kit-p5-12580-filtered.log` 为临时文件。测试后确认原APK 12492、自动亮度、熄屏。
