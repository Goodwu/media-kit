# P8.4 正常列表入口 Texture SDR 首帧（12530，2026-09-27）

## 范围

- 华为 LYA-AL00，Android 10，arm64，测试 APK versionCode 12530；APK SHA-256 `ccbbf132a8c6c5ee35014b51a19acb0a6ec445a7d5fa2d2554ef0a83406e9f1a`。
- P8.4 全片 `/data/local/tmp/media-kit-p84-full.mp4`，此前固定 SHA-256 `7626cac28819ffd1377a712b56c7cc4bbf8677f5db4b39fb0c83f92e58d74443`。入口为已挂载 `Video` 的普通竖屏测试页，点 `Video 0`，直接 `gpu-next` / `mediacodec` / Texture→SDR；不是原生 HLG，也不是全屏。
- 打开回调先启动 Flutter Surface PixelCopy 探针，再调用通用 `prepareAndroidTextureOutput()`，然后 `player.open`。`layoutBound=true` 四轮均成立。

## 结果

| 独立进程 | 探针至首次明显内容 | 备注 |
| --- | ---: | --- |
| 1 | 680.957 ms | 首个 AImage PTS 0 |
| 2 | 461.579 ms | 首个 AImage PTS 0 |
| 3 | 449.147 ms | 首个 AImage PTS 0 |
| 4 | 454.274 ms | 首个 AImage PTS 0；约 2 秒和 5 秒截图为不同实际视频帧 |

四轮最慢 0.681 秒，均低于 1 秒。证据日志为 `/private/tmp/media-kit-12530-p84-normal1.txt` 至 `normal4.txt`；第 4 轮截图为 `/private/tmp/media-kit-12530-normal2.png` 和 `normal5.png`。截图显示普通页面的视频区域随时间变化。探针读回的是 Flutter Surface 内容，无法证明物理面板发光时刻；计时起点在点击回调内，未包含输入派发时间。视频区域之外保留测试页 UI，故不能据此宣称真全屏验收完成。

同一进程播放中再次点 `Video 0` 的探索日志 `/private/tmp/media-kit-12530-p84-reopen.txt` 中，第二次探针首次采样已含旧视频帧，2.925 ms 是旧帧，**不得作为重开首帧**。第二次打开仍显示 `layoutBound=true`、新 AImage PTS 0，未见打开异常，但需用新旧画面身份或先清空旧帧的方式重新量化退出重入。

四轮在首个 AImage 后可见 `acquireLatestImage ... -30001` 的启动期重试；本次未阻止出图，不能据此推断长播稳定性。当前证据还缺触摸到显示、真全屏、Texture SDR 色彩、音画同步和完整退出重入；这些仍是 TASKS 的 SDR 阶段验收门槛。原生 HDR 首帧须在 SDR 阶段完成后独立测量。

测试后恢复 versionCode 12492，六项诊断属性为 0，系统自动亮度为 1，屏幕已熄灭。
