# P5 公开 PQ 失败路径短轮（2026-09-27）

- 设备：LYA-AL00/API29，固件 `10.1.0.163C00`。原 APK 10420 已留作恢复。测试 APK `versionCode=12464`（Flutter `--build-number=10464` 的 arm64 split 编码），SHA-256 `a25f30176c825cb148181546b4decdbdb0de70ae3afc636a7d005e11ed1106e6`；包内 `libmpv.so` SHA-256 `f1985ce3d9c759369ef7989565e726c7fe4ba7278ec5fdf4e005f73a9fee71ef`，使用本地 P5 JAR SHA-256 `5b9495f72893b8b62bb9085c67c9e87707b04f5910d3f09e9a79df82efcfd2e2`。测试源为 `/data/local/tmp/media-kit-dolby-official-p5-1080p.mp4`，既有 SHA-256 `87fe0115f3002a621d2380a9f91852ef91a15854a446efe26de8744f77ef5346`。构建时保留工作树已有的两处 Android 未提交诊断修改，本次未编辑/提交它们。
- A，三个诊断属性均 0：进程 PID 6029，03:50:11.316 `validate` 报 `P5 RPU attachment and raw YUV pipeline are not enabled`，没有进入 P5 媒体打开。初始化时的普通 Surface 曾创建 WID；它不代表 P5 PQ WID。
- B，`p5_rpu_probe=2`、`p5_raw_yuv=1`、私有`p5_direct_dataspace_probe=0`：进程 PID 6293，初始普通 WID `11158` 在切换输出时于 03:50:35.724 删除；新 10-bit Surface 03:50:35.815 遭 SurfaceFlinger HDR 能力查询权限拒绝，03:50:35.816 `transfer=pq, applied=false`，`surfaceChanged format=43,wid=0`。03:50:45.832 才抛 `TimeoutException after 0:00:10`。该代没有发布错误 PQ WID；失败反馈滞后 10 秒。关键过滤日志：`android-p5-public-fail-12464-focused.txt`。没有取得此轮 P5 可见画面或系统 PQ 合成；同进程 HDR10/P8.4/SDR 恢复未测。
- 结束：强停测试进程，三个属性逐项回读 0，恢复原 APK 10420；亮度自动模式 1（当时设置值 8），手机屏幕关闭。没有保持最高亮度或静态测试画面。

## 12465 失败 ACK 与同进程降级恢复

- APK `versionCode=12465`、SHA-256 `05bd0f29ff60d04e58c7b6f277af50aad18be2fbded51264ea07e741326f7cb8`；同一正确 P5 JAR。诊断属性为 RPU=2、raw YUV=1、私有 dataspace=0，手机保持自动亮度。
- 04:16:35.182 首次 PQ dataspace 设置失败并发出完整身份的 `SurfaceFailed`，该代 `wid=0`；04:16:35.258 Dart 报明确 `initialDataSpaceRejected`，约 76 ms，没有等待旧版 10 秒超时。
- 同进程恢复源 HDR10 于 04:16:57.793、P8.4 于 04:17:54.723 报 `ANDROID_HDR_RECOVERY_OPEN`。该测试包的 `gpuPlatformHdr=false`；策略代码对这两类源选择原生 `mediacodec_embed`，但本轮没有同步采集 SF/HWC 与可见帧，不能仅凭打开成功宣称 PQ/HLG 系统合成已复验。两次恢复耗时较长，仍需阶段日志和首帧呈现证据。
- 结束时强停测试进程，属性均回读 0，用 `adb install -r -d` 恢复 10420；亮度模式 1，屏幕 `Display Power: state=OFF`。原始 logcat 保存在本机 `/tmp/media-kit-p5-surface-12465.log`，关键事件摘录另存归档。

## 12466 GPU PlatformView HDR 恢复对照

- 同代码再开启 `MEDIA_KIT_ANDROID_GPU_PLATFORM_HDR=true`；APK `versionCode=12466`、SHA-256 `fe015e33b04055b0a8539fb9ea799d8c82e6f74d0c94064e35fae951c95e0a28`。
- P5 在 04:20:45.497 `SurfaceFailed`，04:20:45.575 Dart 报错；约 78 ms。随后 HDR10 使用新 10-bit PQ Surface，04:21:08.244 再次 `SurfaceFailed`、`wid=0`，04:21:08.392 恢复循环报具体错误。循环在首次恢复错误后停止，P8.4 未测。此配置的 GPU PQ 路径仍未出图；不覆盖此前采用原生 `mediacodec_embed` 后端的 HDR10/P8.4 人工验收。
- 结束强停并恢复 APK 10420、属性全 0、自动亮度，屏幕 OFF。原始日志本机 `/tmp/media-kit-p5-surface-12466.log`，关键事件另存归档。
