# macOS W0 第二代输出释放（2026-09-27）

- 构建：`media_kit_test` Debug，`MEDIA_KIT_AUTO_LIFECYCLE=true`、`MEDIA_KIT_AUTO_NATIVE_WINDOW=false`、`MEDIA_KIT_AUTO_TEXTURE=false`、`MEDIA_KIT_AUTO_LIFECYCLE_REMOVE_SECONDS=30`。30 秒移除入口默认关闭，只用于此测试。SDR 1280×720 源 SHA-256 `664ad7d5f38db11266a4ee8b9ce650d989548901531d85193d01d1d09f101c44`。
- 目标身份：独立 app 使用 final16 Goodwu mpv 0.41 框架，mpv 二进制 SHA-256 `44112e778650a87160028f4a9efb60e9c02cb506db5da1924605bee492205f24`；重签名深度验证通过，运行 PID `80179` 的 `lsof` 只显示这一份 mpv 和 libplacebo。
- 结果：两代 native Surface 都达到 `framePresented:true`、`active:true`。日志行 549、1144 分别记录两代 handle `501869597136`、`501869285200` 的 factory 释放；行 1680 自动重建，2292 首次 Player dispose 完成，3577 定时移除，3580 第二次 Player dispose 完成。`debugPrint` 大量 Ready 输出会延迟上述 Dart 标记写入，因此行号不能用作跨线程严格时间顺序。完成后进程继续存活，未见 `Broken API use: mpv_render_context_free() not called`、assert 或 SIGABRT。完整日志 `macos-w0-remove-20260927.log.gz`。
- 边界：仅证明测试页两代 SDR 输出在仍存活的进程里释放；未覆盖真实 PiliPlusX 有序退出、快速重入、seek、HDR 或长播。当前桌面环境下，未改动 final16 包与当前 Debug 包同样无法提供可操作窗口，不能把无窗口归因于新屏障。
