# Glass P5 布局预建后同进程重复打开与释放（12509）

2026-09-27，华为 LYA-AL00/API29，自动亮度；固定吹玻璃 P5 4K59.94 本地源 SHA-256 `afb24b77733a3ca9071f0cfea0d0f7871670a7b6119eb44a314cba974541477c`。诊断 APK versionCode 12509、SHA-256 `7124423fb55076e77251ca806aa18945e92c7e20a0db45f45674558d0d371fb5`，基于已提交的通用真实布局预建实现，带临时预验证直开入口；arm64 JAR SHA-256 `f745146332b532d8baeb162b7a33ddefa03ae8dc0a7731f13a9584ef7e6fa3f9`。属性 `p5_raw_yuv=1`、`p5_direct_yuv=1`、`p5_rpu_probe=2`、`p5_dr_retire=1`、`p5_presizetex=0` 在启动前设置。

同一应用进程 PID 10075 中，对 Video 0 相隔约 13 秒点击三次。三轮均出现 `ANDROID_TEXTURE_PREPARED comparison=on bound=true`、`media_opened`、`track_verified`，随后各有硬解 `OMX.hisi.video.decoder.hevc` 创建。第二、三轮打开前一段流时，前两轮 `P5_IMAGE_FINAL` 分别为 acquired/deleted `477/477`、`476/476`，`P5_RETIRE_FINAL` 的 `held_after=0`、`current_image=0`、`current_egl=0`。第三轮按 Back 退出后 acquired/deleted `1276/1276`，上述三个残留计数仍为 0。截取日志见 [selected-logcat.txt](artifacts/android-firstframe-prebind-reopen-12509/selected-logcat.txt)。本次截取未见 `FATAL EXCEPTION` 或 `ANR in`。

本 JAR/日志路由**没有输出** `MEDIA_KIT_P5_RPU summary`，不能把属性设置或图像释放计数当作 RPU 逐帧匹配证据。也没有同 PTS 色彩比较、全屏画质或首个物理可见帧计时。本轮只支持：已预建的 P5 路径可在同进程连续打开三次，且每段结束的原生图像对象计数归零。下一步需要用确实能输出 RPU summary 的探针包复核同路径，并做真全屏和旋转/后台恢复。

测试后已强停诊断应用、将上述诊断属性复位为 0，重装原版本 12492；系统亮度模式仍为自动（1），自动旋转为 1，屏幕休眠且显示 OFF。隔离构建产物待清理。
