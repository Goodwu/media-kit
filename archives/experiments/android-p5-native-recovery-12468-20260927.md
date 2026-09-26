# P5 失败后原生 HDR 恢复及阶段耗时（2026-09-27）

- 设备为 LYA-AL00/API29，系统自动亮度。12468 arm64 split APK SHA-256 `7e3e3ec024890f29541f1ce3ac1dc726eb569fe48f5464c069bf122e5a122893`，正确 P5 JAR；RPU=2、raw YUV=1、私有 dataspace=0。固定源依次为官方 P5 1080p24、HDR10 全片、P8.4 全片；诊断页 `MEDIA_KIT_ANDROID_OPEN_PHASE_TRACE=true`，GPU Platform HDR 实验开关关闭，因此 HDR10/P8.4 选择原生 `mediacodec_embed`。
- P5 请求后 `sample_ready` 5.397 s，随后 PQ Surface 被拒绝，明确 `SurfaceFailed`；从请求到失败 5.719 s。该时间包含整片 P5 暂存，不是 Surface ACK 延迟。
- HDR10 恢复：请求到 `sample_ready` 21.908 s；此后输出准备与配置约 0.132 s，轨道确认总计 22.358 s。活动视频层 buffer 3840×1920，SurfaceFlinger/HWC 为 `BT2020_ITU_PQ`、HDR metadata types=3、DEVICE 合成。恢复打开后相隔 3 秒的两张系统截图，视频区域 1,163,502/1,166,400 像素不同；证明该片段持续出现不同画面，不证明逐帧流畅或真人颜色验收。
- P8.4 恢复：请求到 `sample_ready` 51.095 s；此后切换原输出、配置和轨道确认到总计 51.683 s。活动视频层 buffer 3840×1920，SurfaceFlinger/HWC 为 `BT2020_ITU_HLG`、metadata types=0、DEVICE 合成。相隔 3 秒视频区域 1,087,521/1,166,400 像素不同；同样只证明画面继续变化。
- `stageAndroidHdrSample` 对输入逐块 SHA-256 并复制到私有目录，这解释了本轮约 22/51 秒的大头。`sample_ready` 到 `track_verified` 分别约 0.449/0.587 s，但轨道确认或尺寸不等于首个屏幕可见帧，2 秒首帧门槛仍需直接计时。此轮为竖屏诊断页的视频区域，不替代全屏人工验收。
- 结束时强停测试进程，用 `adb install -r -d` 恢复原 10420，三个属性回读 0，自动亮度模式 1，屏幕 OFF。原始 logcat、SF 与截图在本机 `/tmp/media-kit-p5-phase-12468.log`、`/tmp/media-kit-12468-*`；归档只保留必要日志/SF摘录，不向仓库提交视频画面。截图 SHA-256 依次为 HDR10 `31d715c9d5c4d27f0703ea177ab6442981623893a3b25c32546a2044c5f63c78`、`70cc822c63f50a19e367dc0ae0cb3eb502486a926a4af394a290313764a338f3`，P8.4 `5fe27ec88793e7508286fa45a18439d2bf1f572b66aee502293a6fe3e5a0681f`、`8756bd7ec96a4e1c35171c9d45920a44e4bad31441d7ce39beb2d55b7d16fa20`。

关键原始摘录：`android-p5-recovery-phase-12468-focused.txt`、`android-p5-recovery-12468-hdr10-sf-focused.txt`、`android-p5-recovery-12468-dolbyVisionP84-sf-focused.txt`。
