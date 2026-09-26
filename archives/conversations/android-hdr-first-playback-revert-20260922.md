# Android HDR 首播问题回退经验（2026-09-22）

## 结论

- 用户最终真机反馈：adb 连接的 Android 手机打开 HDR10 视频转圈约 6 秒，打开 Dolby Vision 视频转圈约 11 秒；开始播放后画面下半部分全黑。
- 本轮 PlatformView/Surface 门禁方向未找到根因。即使 SDR 小样本曾显示画面，也不能外推到 HDR10/DV。
- 本轮所有工作区修改已回退，问题保持未解决，后续从干净基线重新定位。

## 验证经验

- 后续必须用同一台真实设备分别验证 SDR、HDR10、DV 的首帧耗时、整帧覆盖和 Surface/解码输出路径。
- 早期冷启动证据曾误把 TextureView 的 `VideoOutput.onSurfaceAvailable id=0,wid=0` 当作 PlatformView 证据；真正的 PlatformView 至少必须看到 `PlatformVideoViewFactory`、`surfaceCreated`、有效 wid 与 `PlatformVideoView.SurfaceAvailable`。
- 即使确认走了 PlatformView，也不能据此证明 HDR/DV 可见输出正确；仍需结合 MediaCodec 输出、Surface 尺寸/裁剪和实际截图判断。
- 增加 Android PlatformView 在 `_visible=false` 时提前挂 Surface 后，HDR10/DV 的 6/11 秒等待和下半屏黑色问题仍存在，说明该启动时序方向不能作为根因结论。

## 工作区状态

- 仓库已恢复到回退前的干净基线。
- 本记录属于项目归档，不写入系统 memory。
