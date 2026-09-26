# P5 同进程重建后的 RPU 日志路由（2026-09-27）

- 设备 LYA-AL00/API29，官方 P5 1080p24 源、本地 arm64 JAR 与 10440 相同。10444 APK SHA-256 `d6136fe023d7dc2ffcd930e4032540ee1a6865d32e70c901c3a4547e444e36d5`。沿用 HDR 事务、RPU=2、raw_yuv=1、PlatformView、1440 最大宽、自动亮度1/设置37。`MEDIA_KIT_AUTO_LIFECYCLE=true` 在14秒重建，`MEDIA_KIT_AUTO_LIFECYCLE_LOG_REBIND=true` 在重建后9秒创建一个不播放的临时 Player，订阅其日志；每段启动后16秒停止视频并销毁。
- 第一段 RPU `inputs=214 outputs=206 matched=206 errors=0 discarded=8`；AImage `205/205`、retire `205/205 held_after=0`。`01:25:31.370` 重建；`01:25:39.402` 临时 Player 就绪。
- 第二段的 FFmpeg RPU 记录进入临时 Player 的日志流，stop 时汇总 `inputs=234 outputs=227 matched=227 errors=0 discarded=7 unconsumed=0`；AImage `226/226`、retire `226/226 held_after=0`，`AUTO_PLAYER_DISPOSE completed`。这证明本轮第二段实际解码输出均附有匹配 RPU，并将 10442 的“探针失声”定位为日志路由失效，而非已证实的 RPU 丢失。独立颜色及长期重建仍未验收。
- mpv `common/av_log.c` 只允许首实例占有全局 FFmpeg 日志回调；重叠创建的新 Player 未接管，旧实例稍后销毁又恢复默认回调。临时 Player 在旧实例销毁后重新注册，全局日志恢复。由于 FFmpeg 回调本身不能标识所属 mpv，第二段日志落入临时 Player；该诊断是证据收集手段，不能作为产品修复。
- 过滤日志 `android-p5-rpu-rebind-10444-20260927.log.gz`，SHA-256 `8d7e80590293e552b026cb958dfa36f1919341789ec662f48000d58f6c1921bb`。结束后强停并恢复原10420、自动亮度1/设置37、三个 P5 诊断属性0。
