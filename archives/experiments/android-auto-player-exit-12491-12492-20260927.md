# Android 自动单播放器返回前释放屏障，12491/12492

## Current State

2026-09-27，针对12486 一次 Glass P5 长播后重入在 `FinalizerDaemon` 的 `SurfaceTexture.release → ConsumerBase::abandon` SIGSEGV。Flutter 本地 mapping 把崩溃的 `renderer.o.finalize` 解析为 `SurfaceTextureSurfaceProducer.finalize`；旧 Texture 未在 Activity 退出前显式闭合、随后进入 finalizer 是较强假设，但单次崩溃没有对象级所有权与 finalizer 先后证据，不能断言已找到唯一根因。

把诊断页已有的双视图退出 Future 与 `await _disposeTestPlayer()`、HDR 清理完整性检查用于普通 Android `AUTO_SINGLE_PLAYER` 根页。连续 Back 共用 Future，清理失败时保留页面、允许后续重试；HDR 不完整报告会抛出并清除失败的缓存 Future。开始清理后拒绝新的源点击。原地全屏先退出全屏，再由根页 Back 等待清理；scope 全屏原已有 `onBeforePop` 清理屏障。此改动仅覆盖可控测试页路由退出，任意宿主直接 `FlutterEngine.destroy()` 的原生 owner broker 任务仍未完成。

验证用华为 LYA-AL00/API29、自动亮度1、指定 Glass P5 4K59.94原文件 SHA-256 `afb24b77733a3ca9071f0cfea0d0f7871670a7b6119eb44a314cba974541477c`，正确 arm64 JAR SHA-256 `5b9495f72893b8b62bb9085c67c9e87707b04f5910d3f09e9a79df82efcfd2e2`。12491 APK SHA-256 `c2c851dfb301e550415d908ffeb23e3ff97f31be4393b46b2fb2c97a90d9a3b8` 为初版屏障且低日志：

- 未播放直接 Back：旧 VideoOutput `dispose` 后出现 `AUTO_PLAYER_DISPOSE completed`，再退出 Activity；同一进程重入、连续两次 Back 仅完成一次清理。
- P5 打开并确认轨道、AImage 出现后 Back：`VideoOutputManager.dispose` 发生于设备 epoch 1790469924.093；播放器清理完成和退出屏障为1790469929.126；Activity `finishing=true` 为1790469929.205。无本轮 SIGSEGV。
- 另一轮 P5 持续至日志媒体PTS 158.692秒、AImage acquired=4000 后 Back：输出 dispose 为1790470205.669，播放器/屏障完成为1790470210.746，Activity退出为1790470210.795。同一进程随后重入新页面并能创建新 VideoOutput，未见SIGSEGV；该轮没有 EOS 或真人持续可见流畅度验收。

12490 verbose包在测试页约14秒整片准备中按Back，日志洪流遮蔽了退出完成信号，不计为有效屏障证明。V1审查随后指出失败 Future 缓存、清理期再点选和原地全屏路径边界，修订后复审无阻断项。12492最终源码包 SHA-256 `39493d184b48e055a2c61babe97047c2865b02f9986aaf7399872c3435ace706`：Dart format无额外改动、单文件 `flutter analyze` 无问题、arm64 release 构建/安装成功；未播放连续Back与P5打开且AImage到达后Back均见 VideoOutput dispose → `AUTO_PLAYER_DISPOSE completed`/退出屏障 → Activity `finishing=true`，未见SIGSEGV。12492没有重复12491的约159秒长播，不能将其作为最终包长播通过。

2026-09-27 **补齐同一最终包12492的长播证据**：原片头在同一进程启动，三张手机截图分别在设备epoch 1790470692/0793/0841取得。前两张显示不同的吹玻璃实际画面；AImage取得数继续增长至4250、媒体PTS164.765秒。第三张在墙钟时间超过视频流标称时长后显示纯紫色，另见`android-p5-glass-eos-purple-12492-20260927.md`，故本轮不能称为片尾画质正常。随后 Back：旧 VideoOutput dispose 为1790470854.106，`AUTO_PLAYER_DISPOSE completed`和退出屏障均为1790470859.170，Activity `finishing=true` 为1790470859.206。重入仍为同一进程 PID5729，创建新 VideoOutput、再次 `track_verified`，屏幕截图有真实画面；第二次 Back 也先释放 Player 再退出。两轮均未见SIGSEGV。此证据覆盖最终包长播后的受控返回与重入，不覆盖真全屏、逐帧流畅性或任意Engine直接销毁。

证据：`artifacts/android-auto-player-exit-12491-12492/long-play-exit-12491.txt.gz` SHA-256 `ffbe7ced390f1eb884af10a1ae8b478257c19fe5a37a8873f1fe15837c8cd717`；`final-build-exit-12492.txt.gz` SHA-256 `2eebc2dee8352c1233dd232896bf235e586fb6bbb72a078cdbe17eac22318b26`。补充最终长播日志及四张截图见`artifacts/android-auto-player-exit-12492-long/`，日志SHA-256 `1b36e03af75fd117d99f199ae101a76d7bc56bb9d4c235a21df84d723e907163`。改动范围仅测试页 Dart；未修改Flutter Engine、Android插件或mpv。设备实验后四项P5属性0、自动亮度1、屏幕OFF。下一步仍需验证清理中点击/失败重试、全屏组合；任意Engine直接destroy需另做原生owner broker并实机核验。
