# SDR 双视图存活输出回退：10461

- LYA-AL00/API29，手机 `/sdcard/Download/media-kit-sample.mp4` SHA-256 `07090b357095a414bc8bfb2229dff1b41f85743597d1fa75fc8397a6141f4fa7`。ffprobe：H.264、854×480、8-bit `yuv420p`，无显式色彩标签，时长 60.07 秒；作为普通 SDR 演示片使用，不把未知标签当作定量色彩参考。自动亮度模式 1、设置值 37。
- 测试页在显式双视图诊断开关下，普通非 HDR 本地视频 `player.open` 完成后也启动稳定外层 key 的 A→A+B→B→A+B→B 轮换。APK versionCode 10461，SHA-256 `23bac9e5afd4636cd551c59a2a4109263fec08d84855fc91498cd347b1ff644e`；PlatformView、`mediacodec_embed`、MediaCodec，未启用 HDR 事务。
- phase4 于 02:55:15.359，A `wid=11074` 于 .434 释放，B `wid=10342` 于 .438 请求重绑、.493 完成。phase1/2/3/4 媒体位置约 4.754/9.759/14.764/19.769 秒。间隔 5 秒系统截图的视频区域像素不同，证明 B 持续出图。同轮 SurfaceFlinger 回读 `dataspace=UNKNOWN`、HDR metadata types=0；没有观察到 HDR 元数据残留。它不证明精确 SDR 色彩或 SDR→HDR→SDR 全链复位。
- logcat `android-sdr-dual-10461-20260927.log.gz` SHA-256 `373cfcac12d5a6cc4b7a6e87a4e49953651ab32648f195553678fd4a0e97527d`；截图 a/b SHA-256 `a773ed6cf247a57b12ae45b34107d53aa8662ebd8aaa642ecf2682d2d1f214a2` / `a55cb049d6d4f96d267775130a82e5c2bd73bdb42867ae4c67948ac68843344c`；SF dump 压缩件 SHA-256 `337fe2e9a693f31f29d0028ca0c8c53ef1453d31e6e5d86553cf0957d51edf56`。
- 结束恢复原 APK 10420、自动亮度模式 1/设置值 37；删除手机及本机临时片源副本。P5、交错和 engine detach 继续开放。
