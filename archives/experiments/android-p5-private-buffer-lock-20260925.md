# P5 厂商 `0x325` 缓冲 CPU 锁定边界（2026-09-25）

## 目的与输入

上一轮请求 `ImageReader(YUV_420_888)` Surface，底层仍返回 `0x325`，且 Java `Image.getPlanes()` 在系统 JNI 中崩溃。本轮使用已有的只读 `AHardwareBuffer_lockPlanes` 诊断函数，不访问未知偏移之外的数据，检查同一硬解 Surface 缓冲是否提供可解释的平面布局。

设备 LYA-AL00 / Android 10，`OMX.hisi.video.decoder.hevc`。输入为 P5 前 512 个 HEVC 包的 `hvc1+dvcC` 诊断重封装，文件 SHA-256 `712a0dea8a521e1c97906ed14263e9bb9bbf9e7c7d3f3167a8ef25b8e17fb9c5`；目标第 500 包 PTS 10.000 s、大小 263461、SHA-256 `0030ffab4d9d435adaa0fa834fa3a366c9ec75a18c5dc23e593a6306b6c47363`，与前两轮目标包一致。容器整体 SHA 可能随 MP4Box 重封装变化，不能以此称整个文件逐字节一致。

独立 `app_process` Java 探针 `artifacts/android-p5-hevc-decoder-probe/lock/P5CodecProbe.java`；native 使用项目已有 `media_kit_test/android/app/src/main/cpp/p5_codec_probe.cpp` 中 `AHardwareBuffer_describe`/`AHardwareBuffer_lockPlanes`/`unlock` 实现。Java 源 SHA `71b753a696dea73a6ce9c04eba83f4d87400b8145cc8a3aad54f7a3956d9fd03`，C++ 源 SHA `f4aca6933334a4b2abc51e9eb2b19f3f42741a179344661c88018ac64d4b4287`。构建为 API29 arm64，`-static-libstdc++`；初次未静态链接 C++ runtime 的诊断库加载失败，未运行解码，修正后才计有效轮次。

## 有效轮次

配置 `ImageReader.PRIVATE`、`USAGE_GPU_SAMPLED_IMAGE | USAGE_CPU_READ_RARELY`、`maxImages=2`。codec 输出格式切换为 `color-format=805`（`0x325`），第 0 帧与 PTS10.000 s 的 Image 时间戳分别为 0、10,000,000,000 ns，输出序号 1/501，crop 均为全画面。两帧 `Image.getFormat()=34`（PRIVATE），`HardwareBuffer.getFormat()=805`。

| 帧 | Buffer描述 | `lockPlanes` | 平面信息 | 前16字节 |
| --- | --- | --- | --- | --- |
| 0 | 3840×2160、stride3840、usage10498 | status0 | 1平面；rowStride0、pixelStride0 | `00100010` 重复 |
| 500 | 同上 | status0 | 1平面；rowStride0、pixelStride0 | `00680068` 重复 |

两次 `unlockStatus=0`，501帧输出完成。原始 stdout 在 `artifacts/android-p5-hevc-decoder-probe/lock/lock-probe-output.txt`，SHA-256 `3bb6c797a323b1896d08be8e01ca4fef57ee5c620859beef775253819275e924`。

**锁定成功不等于获得可解析的原生 YUV 平面。**返回的单平面、零行/像素步长没有公开的 `0x325` 像素布局合同；前16字节只是内存起始处观察，不能按 P010、NV12 或普通线性图像解释，也不能由分配 stride 推断内部像素地址。因此 L1 硬解原生整数检查点仍标记“未直接观察”。此结果与上一轮 `YUV_420_888` 表面值但底层 `0x325`、`getPlanes()` 崩溃一致，收紧了通用 CPU 读回路线的可用性边界，但未证明硬解码值或 OES 取样哪一侧出错。

## 后续方向

优先在现有 `0x325`→EGL/OES→raw packed10 链上做**同一 AImage 的受控双路径采样/读回**，核对局部差异是否随外部取样方式变化，并与无损图案的确定性采样模型比对。若需要直接解析 `0x325`，必须先取得可靠的厂商格式/同步合同；不凭 16 字节头部猜布局。产品修正前继续保留 RPU/L2C 同帧、4K50 性能、HDR 信令和长播门禁。

本轮未安装或修改产品 APK，实验后手机仍为 10369、诊断属性 0、无应用进程；设备和主机本轮临时探针文件清理。
