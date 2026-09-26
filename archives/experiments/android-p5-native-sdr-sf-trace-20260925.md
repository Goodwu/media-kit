# P5 原生 SDR/1440 SurfaceFlinger 缓冲接收采样（2026-09-25）

## 结果与边界

复用 SHA-256 `3ff06f70a8a7dc653809fa709ec59310da18feb359af239c0b2029bf7c31ae56` 的 11046 APK、官方 Sol Levante 4K/24fps P5、同一隔离 JAR 与原生 SDR/1440 设置。实际活动视频层为 `SurfaceView - com.example.media_kit_test/com.example.media_kit_test.MainActivity#1`，SurfaceFlinger dump 在采样时回报活动 buffer `1440x810 RGBx_8888`、默认 dataspace、metadata 空；应用 PID 6584。约 10 秒 `atrace gfx view sched` 中目标层对应 240 次生产端 `queueBuffer` 和 SurfaceFlinger 侧 `acquireBuffer`，以及 240 次 `releaseBuffer`。采样内视频 buffer 确实被 SurfaceFlinger 持续接收，比 mpv 时间轴或单张截图更接近显示链。

目标层 `queueBuffer` 间隔中位 41.666ms、P95 42.402ms、最大 43.756ms；SF `acquireBuffer` 间隔中位 48.935ms、P95 49.403ms、最大 49.587ms，最小 32.167ms，符合 24fps 内容在 60Hz 合成节拍上的交替等待。按事件顺序一一配对的 queue→acquire 差中位 8.824ms、范围 0.609–17.078ms；**没有帧 ID 配对证明**，仅作时序辅助。该 10 秒窗口未见 ≥500ms 的缓冲接收停顿，但它不能替代整个 30 分钟窗口，更不能证明每次 buffer 已在物理屏幕被扫描或面板亮度/颜色正确。

`SurfaceFlinger --latency` 对明确的活动视频层 `#1`，清空后等待 5 秒重查仍只返回 `16666666` 纳秒刷新周期；`--timestats` 也无结果。无目标层的默认 `--latency` 会返回显示合成时戳，但那不是目标视频层每次 present，不能拿来冒充 P5 实际物理显示 cadence。trace 中有 `presentAndGetReleaseFences` 调用，但未取得与视频帧 ID 配对的 HWC present fence/光学测量。本轮只把目标层 SF acquire 纳入显示侧初筛，最终 present/首帧门禁仍未通过。

同次应用日志的视频位置在 10:15:04/14/24 从 45.1667→55.1667→65.1667 秒，播放器掉帧属性保持 1、解码器 0（启动时那 1 帧未在 trace 窗口产生）。退出时片尾尚未到达，close summary 的 `inputs=6236, outputs=matched=6225, discarded=11` 含主动停止剩余片段，不作 EOS 尾帧结论。

## 复核

- 原始压缩 atrace：`artifacts/android-p5-native-sdr-1440-11046-sf-trace/atrace.txt`，SHA-256 `b6e49be8382dcb71aeef3afb23b3e6ab5b38cd9b89353c86e58a2a2356c85648`。
- 同轮完整 logcat：`artifacts/android-p5-native-sdr-1440-11046-sf-trace/logcat.txt`，SHA-256 `dbab1b46f54eef79c0f3dec78dfdcfe709acfa8f2eba7207b3b4001e7ac07bf6`。
- 解析命令：`python3 archives/experiments/tools/p5_surface_trace_summary.py archives/experiments/artifacts/android-p5-native-sdr-1440-11046-sf-trace/atrace.txt --layer 'SurfaceView - com.example.media_kit_test/com.example.media_kit_test.MainActivity#1'`。脚本按同一线程的 atrace B/E 嵌套区分该层 `queueBuffer`、`dequeueBuffer`、`acquireBuffer`、`releaseBuffer`，不是把所有 SF 刷新计入该视频层。
- 结束后设备恢复 versionCode 10369、8 个相关诊断属性 0、两份测试源移除、应用未运行。源码与归档未提交。
