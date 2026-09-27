# Glass P5 布局预建路径的 RPU 重开核验（12512）

2026-09-27，华为 LYA-AL00/API29，自动亮度。固定 Glass P5 4K59.94 原文件 SHA-256 `afb24b77733a3ca9071f0cfea0d0f7871670a7b6119eb44a314cba974541477c`。12512 诊断 APK SHA-256 `1afc5054cc202447e3da08357ea9728252b1ea05f6b79f173ad6144e5a89d607`，arm64 JAR SHA-256 `f745146332b532d8baeb162b7a33ddefa03ae8dc0a7731f13a9584ef7e6fa3f9`。沿用 12511 的播放前横屏无 AppBar 诊断页与真实布局 Surface 预建、临时预验证直开入口；本包把 mpv 日志级别设为 verbose。`p5_raw_yuv=1`、`p5_direct_yuv=1`、`p5_rpu_probe=2`、`p5_dr_retire=1`、`p5_presizetex=0` 均在应用进程启动前设置。APK 完整构建、安装、运行。

同一应用 PID 15829 中相隔约 11 秒点击打开三次；三轮均得到预建 `bound=true`、`media_opened` 和 `track_verified`。前两段关闭时，解码器摘要分别为：

| 段 | RPU 输入 | 实际输出 | 匹配 | 错误 | 丢弃 | 未消费 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 642 | 626 | 626 | 0 | 16 | 0 |
| 2 | 641 | 622 | 622 | 0 | 19 | 0 |

本轮 logcat 捕获的 682 条逐帧 `MEDIA_KIT_P5_RPU output` 均为 `status=MATCH`；完整输出计数以两个解码器摘要为准，不能用异步转发的逐帧日志条数替代。前两段 `P5_IMAGE_FINAL` acquired/deleted 为 `380/380`、`390/390`，`P5_RETIRE_FINAL` 的 `held_after=0`、`current_image=0`、`current_egl=0`。第三段也记录图像计数 `380/380` 且这些残留计数为 0，发生在发送 Back **之前**；没有取得第三段 RPU summary，因此只认定两段逐帧边界匹配。发送 Back 后应用进程仍在，本轮不能作为页面退出验收。所存日志未见 `FATAL EXCEPTION` 或 `ANR in`。证据为 [选摘日志](artifacts/android-p5-prebind-rpu-12512/selected-logcat.txt) 和 [应用进程完整日志](artifacts/android-p5-prebind-rpu-12512/app-logcat.txt.gz)。

12509 没有 RPU 摘要是测试包的 `PlayerConfiguration.logLevel=error` 屏蔽了探针消息：同一 SHA 的 JAR 中有 `MEDIA_KIT_P5_RPU summary` 字符串，12512 仅打开 verbose 就收到摘要。这不改变 12509 图像释放结论。本轮 RPU 匹配核验的是媒体输入与实际解码输出的元数据对应关系，**不是独立色彩参考、完整全片、seek/flush 或物理全屏验收**。横屏应用窗口仍为 2984×1440，缺口安全区待直接核验。

结束后已强停诊断应用、恢复属性 0、重装原 12492 APK；自动亮度模式为 1、自动旋转为 1、屏幕休眠且 OFF。隔离构建产物已清理。
