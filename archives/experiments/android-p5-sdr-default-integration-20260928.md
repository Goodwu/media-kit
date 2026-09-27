# P5→Texture SDR 默认优化集成首轮（2026-09-28）

## 输入与隔离

- 工作区原有 `surface_dataspace.cpp`、`PlatformVideoView.java` 修改和 `mpv-shot0001.jpg` 未碰。应用从 `media-kit` 提交 `e6e908e` 的独立 worktree 构建；libplacebo 从 Goodwu fork `c9fd879` 独立浅克隆，mpv 从 Goodwu fork `a81978b` 的干净产品分支独立 worktree 构建。只打包 arm64。
- 产品候选在 mpv `vo_gpu_next.c` 将 `optimize_dovi_linear_decode` 默认传给 P5、有 DV 映射、BT.1886 目标；libplacebo 自身继续用 direct/down 等条件回退。可重放的**未验收**候选补丁为 `artifacts/android-p5-sdr-default-candidate-20260928/mpv-default-optin.patch`，SHA-256 `5bbb396327fc596f06eb5b278a5d7cc10125b1eb5d065386f3c74477e6673ff3`。补丁未包含下述临时诊断兼容符号，也未提交到 mpv fork。
- 独立 arm64 libplacebo/mpv 源码编译、链接通过；12548 JAR `19fb0f17…` 对应 mpv 缺 `media_kit_stage_probe_enabled`，因为复用的旧 FFmpeg 静态库含默认关闭的阶段探针，应用启动时 `dlopen` 失败、无播放。该失败不能作为优化效果判断。后续隔离构建临时补上该符号，正式集成应从一致的清洁 FFmpeg 依赖重建。

## 设备短轮

- 设备 Huawei LYA-AL00/API29，自动亮度、未切系统性能模式；Glass P5 本地源 `/data/local/tmp/media-kit-p5-glassblowing2-4k5994.mp4`。12549（无命中日志）横屏全屏 Texture→SDR 短播实际出画，3120×1440 系统截图 `9ae532dd…`，视频 16:9 区域约 2560×1440；约媒体3.09秒 VO累计100、decoder0。此为截图/日志短轮，无全片性能与真人观感验收。
- 12550 在 libplacebo 候选命中处增加每 renderer 一次的 `P5_LINEAR_DECODE_HIT` 日志，并开 mpv verbose；APK SHA-256 `be0b2f67c542d6c03d0218087444ff36655ba3c851c723adb7f9163b020c7e30`，JAR SHA-256 `91d660ce22ccb7584347a295c9e4195c62096ea6a4e2da6d3ed806d0de9dcb60`。`gpu-next`/libplacebo 启动并读取 DV P5 配置，媒体约1.33秒 VO41、decoder0，但没有命中日志。同轮 libplacebo 报 `r16u` 纹理缺 `PL_FMT_CAP_LINEAR`，停用了 scaler；因此不能声称默认优化实际命中，也不能用短轮掉帧评估收益。完整设备日志留在 `/private/tmp/media-kit-p5-hit-12550.log`。
- 产品分支的 AImageReader 仍是上游 OES RGB 包装；此前有效实验分支 `63a0aa9` 含外部 YUV/direct、缓冲回收及其他诊断的大量改动，单 `vo_gpu_next.c` 文件候选不足以复现旧优化路径。两分支在 `hwdec_aimagereader.c` 相差约1800行，须拆出受支持的生产输入与回收实现，排除探针，再核 P5 逐帧元数据、候选命中和画质。

## 下一步与设备收束

1. 先构建一致的 arm64 依赖：以清洁 FFmpeg 和产品 mpv 为基线，只移植 P5 所需的外部 YUV/缓冲所有权路径；不用临时 `media_kit_stage_probe_enabled` 符号充当正式解法。
2. 在相同 Glass→Texture SDR 条件下同时证明 P5、DV 映射、目标、direct/down 与优化命中；未命中先修输入/采样约束。再做回退、Glass 全片及 Mystery Box 同片复测。无命中和全片证据前 P0 保持进行中。
3. 实验结束已强停测试包，使用 `adb install -r -d` 恢复设备原 12492 APK；自动亮度模式1、屏幕OFF。设备原包备份 `/private/tmp/media-kit-p5-original-12492.apk`，SHA-256 `39493d184b48e055a2c61babe97047c2865b02f9986aaf7399872c3435ace706`。
