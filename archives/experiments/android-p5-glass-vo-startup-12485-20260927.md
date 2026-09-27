# P5 Glass 首轮解码、映射与 VO 输出时序，12485

## Current State

2026-09-27，继续使用已安装的12485诊断APK（SHA-256 `85b88a8ae600ddc8a817a0d5c129aa00f150922e43fd365a53e77921bbf7639c`）、正确policy-v2 JAR（SHA-256 `5b9495f72893b8b62bb9085c67c9e87707b04f5910d3f09e9a79df82efcfd2e2`）和用户指定 Glass P5 源。默认 Android SurfaceProducer/Texture SDR，原片头从0开始，测试页临时预验证固定文件以避开331 MB复制。仅额外启用 JAR 已存在的 `debug.media_kit.p5_vo_perf=1` 与 `p5_image_timeline=1`，做一次新进程短轮，未换 mpv 库。实验前屏幕解锁、自动亮度1；结束后强停、六项P5属性0、屏幕OFF。

同一 logcat `-v epoch` 时间线：

| 事件 | 距点击回调内PixelCopy起点约 | 说明 |
| --- | ---: | --- |
| 协调器 requested / media_opened | 0.026 / 0.276秒 | 固定源无需复制；`media_opened`不是解码完成 |
| `P5_VO_TIME frame=1`及flip | 1.004秒 | 发生在首个P5 AImage之前，不能当视频首帧 |
| 首个 `release_begin` PTS0.05005 | 1.286秒 | MediaCodec输出送到Surface的开始 |
| 首个callback、`acquire_ok` | 约1.287–1.289秒 | release至取图约2–3毫秒 |
| `P5_VO_TIME frame=2`及flip | 约1.359–1.360秒 | render计时76.718毫秒、submit 1微秒、swap 218微秒；无实际mix PTS/成功视频帧身份 |
| Flutter Surface洋红→黑 | 1.436秒 | frame2之后约77毫秒，但黑像素仍不能证明对应的解码帧 |
| Flutter Surface首次非黑内容 | 4.064秒 | 源前约2.052秒黑场；连续PixelCopy可能扰动性能 |

`media_opened`至首个 `release_begin` 约1.010秒，是本轮已观察到的主要早期等待；它包含加载、MediaCodec准备和首次解码等，现有日志未再拆分。首个release到callback/取图仅毫秒级。帧2的render计时跨越首个图像到达，不能当成“图像到达后又等77毫秒”；`P5_VO_FLIP`记录外层submit/swap耗时，但不含实际mix PTS或 `eglSwapBuffers` 成功值，不能证明帧2就是首张视频图像或物理显示。更不能仅因frame1早于AImage就把frame2自动认作有效视频帧。高频诊断日志及连续PixelCopy可能改变时序，不与12485无VO日志轮作严格性能归因。

`artifacts/android-p5-glass-vo-startup-12485/vo-and-image-timeline.txt`保存原始筛选日志（SHA-256 `46f8b70b74a9db944eb3ca6d9e9436dbee23a88e31ff813545c92dc57667170a`）。设备同轮仍只证明 Flutter Surface buffer 变色/出现内容；首个真实视频帧的PTS、提交成功与物理屏幕显示未闭合。下一步若加原生探针，须在实际mix帧的 `user_data` 取PTS，跨draw/flip/EGL成功同序号关联，并与Android设备单调时钟对齐；限制前几帧日志，保持产品时序可比较。

## 重建基线边界

policy-v2 JAR内未strip `libmpv.so` SHA-256 `b43500e66eaa08bd6d1821bd72ea15b3dd79d86831f61ec55cd60f783fd429ad`，50,069,200字节。`/tmp/media-kit-mpv-p5-replay-2214`缺少当前P5探针，不是该JAR源码。曾在独立工作树以 `a81978b` 基线、`a322dd2` 的另外八个文件及归档累计补丁 `map-variant-policy-cumulative.patch` 重建，NDK27.2/Meson配置、链接通过，但得到的未strip库 SHA-256 为 `81859200c7004bb446bf0843ab097eab6ddfea7d7df6ce2a43bdf667261d5dfa`、50,068,896字节，**不等于现用JAR**。该重建库未封装、未安装、未用于性能结论；不能以此直接加PTS日志并宣称只改变探针。隔离重建的首次配置遗漏既有 `PKG_CONFIG_SYSROOT_DIR`，编译缺Android依赖头文件，重配后修复；另需合入`a322dd2`新增的八个配套源文件才可链接。归档累计补丁SHA-256 `197926dc4e0e65d96bf6a255167737a18ab2a293eca209606c3a6429f83a7e7b`。

这个未匹配的隔离工作树及构建目录已清理；主项目原有未提交的Android修改和图片未触及。
