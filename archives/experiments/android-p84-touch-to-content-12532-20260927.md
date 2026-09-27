# P8.4 触摸抬手至横屏全屏内容（12532，2026-09-27）

- 设备华为 LYA-AL00，Android 10，arm64；APK versionCode 12532，SHA-256 `7bab9690b5f02856917d490c417746d44dd176826c62dc5ac2ea4154e3a6496e`。
- 素材为固定 P8.4 全片 `/data/local/tmp/media-kit-p84-full.mp4`；普通列表点击后 `VideoFullscreenScope` 同一 Video 切横屏全屏、布局完成后通用 Texture 预绑定、`gpu-next`/`mediacodec` 打开，输出为 Texture→SDR，非原生 HLG。
- 诊断 Activity 在 `dispatchTouchEvent(ACTION_UP)` 记 `elapsedRealtimeNanos`；在点击回调内启动 Flutter Surface PixelCopy。首次明显内容相对触摸抬手三次独立进程为 **792.203、698.661、670.070 ms**；同三轮相对探针启动为 788.695、694.641、666.260 ms。三轮 `layoutBound=true`，无打开异常。日志为 `/private/tmp/media-kit-12532-touch-1.txt` 至 `...-3.txt`。
- 12531 同全屏路径已有物理 3120×1440 截图和相隔 3 秒的不同实际视频帧；本轮把计时起点向输入边界前移约 4 ms。它仍不含触摸按下至抬手的时长，也不测物理面板光学呈现。短轮和系统读回不能替代长播、色彩与音画同步验收。
- 重入时旧画面会污染首次内容阈值，应按新旧帧身份另测。原生 HDR PQ/HLG 首帧仍未开始；遵循先完成 SDR 验收的顺序。
- 测试结束恢复 versionCode 12492、六项诊断属性 0、自动亮度模式 1，手机熄屏。
