# Android SDR 直开首个可见帧探索（2026-09-27）

- 设备 LYA-AL00/API29，默认电池设置、自动亮度，固定 SDR H.264 `/data/local/tmp/media-kit-sdr-control.mp4` SHA-256 `07090b357095a414bc8bfb2229dff1b41f85743597d1fa75fc8397a6141f4fa7`。诊断页直接传路径给 `player.open`，无整片哈希/复制；原生 PlatformView、`mediacodec_embed`/`mediacodec`。
- 10469 APK SHA-256 `bf1e9ed2f27bb0c8b637717350618015f7d14d034473521520f9cf0f6abd731c`，自动打开冷进程轮：单调日志从触发到 Surface 绑定 106 ms，媒体命令返回又 16 ms；约 197 ms 后报 SDR `VideoParams`。这些信号不证明屏幕出图，故不作为2秒门槛成绩。该设备 `dumpsys SurfaceFlinger --latency <video layer>` 仅返回刷新周期，未给逐层呈现历史。
- 10470 APK SHA-256 `ff2d4a55e66d5adfe6eac28298ad080c3dc5aa74d7196d0ccf33025ed6c70b8b`，默认关闭的 `MEDIA_KIT_ANDROID_OPEN_ON_TAP` 让页面先稳定在黑色视频区。实机用 ADB 点击 `Video 0`；单调日志中点击前标记 287367.353 s、Dart打开触发 287367.659 s、媒体命令返回 287367.709 s。短时 scrcpy 录制的视频区在PTS 4.144 s仍黑，4.165 s首次显示可辨认的视频画面；同录屏点击反馈约PTS 4.065 s，反馈到首画面约100 ms。录屏与logcat时钟未严格校准，`TAP_V3`也早于实际输入处理；因此这只证明一次热页面直开很快出图，**不声称已按用户触发到屏幕首帧口径通过2秒正式门槛**。录屏本身可能改变性能。
- 10470录屏本机 `/tmp/media-kit-12470-tap-sdr-v3.mp4`，SHA-256 `c29db8836dc87ff859fd767eb03ccd4186143c1f2ffc6c7f36f5026b8e16055a`；不提交电影画面到仓库。聚焦单调日志 `android-sdr-first-visible-12470-focused.txt`。还需可复现的统一时钟、冷/热多轮和HDR10/P8.4/P5，以及正式全屏路径。
- 结束强停测试进程，用 `adb install -r -d` 恢复原10420，三个P5诊断属性回读0、自动亮度模式1、屏幕OFF。
