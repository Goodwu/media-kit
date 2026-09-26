# P5 同进程重建独立入口短轮（2026-09-27）

- LYA-AL00/API29、官方 P5 1080p24 源、本地 arm64 JAR 与 10440 相同；10442 APK SHA-256 `419e530b0d3dcd08d0e954c779b60686331da0bff95bdb88ff1298e774f576b7`。`MEDIA_KIT_AUTO_LIFECYCLE=true` 每14秒以新 key 重建一次，不触发 `AUTO_RESIZE` 的窗口缩放/10秒主动销毁。HDR 事务、RPU 管线、PlatformView、1440 最大宽、同页全屏、详细日志和三个 P5 属性沿用 10440；自动亮度1/设置37。
- `01:14:30.563` 同进程 generation2；旧段 RPU 汇总 `inputs=206 outputs=197 matched=197 errors=0 discarded=9 unconsumed=0`，AImage `196/196`、retire `196/196 held_after=0`。
- 新段 `01:14:37.293` 仍使用 `hevc_mediacodec` 硬解，`01:14:37.521` 再次报告 P5 打开；VideoParams 为1920×1080、Dolby Vision/BT.2020/PQ。播放到图像 PTS 约31.2秒后按返回退出，AImage `750/750`、retire `750/750 held_after=0`，`AUTO_PLAYER_DISPOSE completed`，进程无 abort。新段没有任何 `MEDIA_KIT_P5_RPU` input/output/summary，故不能确认新段 RPU 是否实际附加；需要查属性/解码器初始化与探针状态，不能以图像资源回收推断 RPU 正确。
- 过滤日志 `android-p5-rpu-recreate-10442-20260927.log.gz`，SHA-256 `15e7a05d43c7567fa48962f96a52d6a57946f05dbec1a4abcd312b2ff5a41624`。测试后强停并恢复原10420、自动亮度1/设置37、三个 P5 属性0。
