# P5 同进程自动重建短轮（2026-09-27）

- LYA-AL00/API29；官方 P5 1080p24 源与 10440 相同。10441 APK SHA-256 `378ff9b54a96656c007d2c5b3cea3c04b50d8fbe4a79d900b637c3c8c5bf044f`，本地 arm64 JAR SHA-256 `5b9495f72893b8b62bb9085c67c9e87707b04f5910d3f09e9a79df82efcfd2e2`。沿用 HDR 事务、RPU、PlatformView、1440 最大宽、同页全屏和详细日志；入口改用 `MEDIA_KIT_AUTO_RESIZE=true`，14 秒后以新 key 重建播放器。屏幕保持自动亮度1/设置37。
- 第一段在 `01:10:46.500` 汇总 `inputs=95 outputs=88 matched=88 errors=0 discarded=7 unconsumed=0`；`P5_IMAGE_FINAL acquired=87 deleted=87`、`P5_RETIRE_FINAL maps=87 reaped=87 held_after=0`。`01:10:50.489` 同进程出现 `AUTO_LIFECYCLE_RECREATE generation=2`。
- 第二段 `01:10:58.016` 再次打开 P5，`01:11:00.635` 回收 `acquired=61 deleted=61`、`maps=61 reaped=61 held_after=0`，同一进程仍存活，未见 abort。但第二段没有 RPU 逐帧或结束汇总，不能据此宣布重开后的 RPU 验收通过。源码复核发现 `AUTO_RESIZE` 还会在每个实例启动后第6秒请求窗口缩放、第10秒调用 `_disposeTestPlayer()`，与第14秒重建冲突；Android 报 `AUTO_WINDOW_RESIZE MissingPluginException`。已给入口增加独立的 `MEDIA_KIT_AUTO_LIFECYCLE` 开关，下一轮只做重建。
- 过滤日志 `android-p5-rpu-recreate-10441-20260927.log.gz`，SHA-256 `0c84a3fb7b8facadd531396f8241a3e5d00faf5ccfd13d8d365ab427891954ea`。结束后强停、恢复原 10420，自动亮度1/设置37、三个 P5 属性均0。
