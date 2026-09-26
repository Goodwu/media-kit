# macOS W0 modern mpv 生命周期验证（2026-09-27）

- 测试对象：`media_kit_test` Debug，`MEDIA_KIT_AUTO_LIFECYCLE=true`、`MEDIA_KIT_AUTO_NATIVE_WINDOW=false`、`MEDIA_KIT_AUTO_TEXTURE=false`。为避免测试包自带 mpv 0.36 与目标库同时加载，将 Goodwu final16 mpv 0.41 框架及依赖放入独立重签名的 app 副本；`codesign --verify --deep --strict` 通过，进程 `lsof` 仅见这一份 mpv 框架。测试视频为 1280×720 SDR 本地 MP4，SHA-256 `664ad7d5f38db11266a4ee8b9ce650d989548901531d85193d01d1d09f101c44`。
- 结果：首次 native output 的 `framePresented:true`、`active:true`、`rgba16Float`、`outputEpoch:2`；日志行 549 记录旧 Surface handle `511133149264` 释放。行 1677 自动重建，新的 handle `511150480976` 再次达到 `framePresented:true`、`active:true`；行 2289 `AUTO_PLAYER_DISPOSE completed`。测试进程持续运行至人工 Quit，未见 `Broken API use: mpv_render_context_free() not called` 或 SIGABRT。完整日志：`macos-w0-modern-isolated-20260927.log.gz`。
- 证据边界：人工 Quit 让进程退出，但日志没有第二个 Surface 的释放 ACK，不能把它当成有序退出证明。测试包不是 PiliPlusX 最终调用链；仅覆盖 SDR、一次重建、一次 Player dispose。快速重入、seek、HDR 亮度和长播仍需验证。
- 排除的无效试验：直接用环境变量给原始测试包指定 Goodwu 框架，进程同时加载 mpv 0.36 和 0.41 并 SIGSEGV；这属于混装试验，不作为产品缺陷或通过证据。
