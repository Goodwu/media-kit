# P5 热切源期间的输出尺寸缓存（2026-09-28）

## 源码事实

`NativePlayer` 切换媒体时会向 `videoParams` 流发送空的 `VideoParams()`。Android 视频控制器原先在宽高非正时直接返回，留下上一片源的 `_sourceDisplaySize` 与 `_appliedVideoSizeRequest`。这段间隙如果收到视图布局更新，`_applyVideoSizeLocked` 仍会按上一片源的宽高/纵横比计算输出尺寸。

## 候选修改与边界

当前media-kit目录的 `android_video_controller/real.dart` 在空参数事件时清空这两个缓存。随后新片源的有效 `VideoParams` 会重新计算并应用尺寸。`git diff --check` 通过；`dart format` 报告0处格式变更，但退出时因当前沙盒不能更新时间戳于用户目录的遥测文件而报错。

这只是源码推导的竞态修复，尚无热切源实机、双视图或颜色/连续画面验收。ADB本地socket当前不可用；候选未提交。

## Surface 重建边界复核

同一 `AndroidVideoController` 的普通 SurfaceTexture 使用同一 `VideoOutput` 和固定 `wid`，Java `VideoOutput.setSurfaceSize` 保存实际 `bufferWidth/bufferHeight`；SurfaceProducer 的重建则由自身 `setSize`/`onSurfaceAvailable` 维护尺寸和新 Surface 身份。现有 `_appliedVideoSizeRequest` 只跳过相同尺寸的重复请求，未发现仅因普通 Surface 回调就必须清空该缓存的证据。此判断来自源码，不替代 Surface 代次切换实机验收；因此本轮不扩大到 Surface 回调修改。
