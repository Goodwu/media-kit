# 华为 HEVC 硬解通用输出格式探针（2026-09-25）

目的：确认 LYA-AL00 / Android 10/API29 的 `OMX.hisi.video.decoder.hevc` 是否能让当前 P5 基础层以公开、CPU 可读的 **10-bit** 平面输出，从而避开 PRIVATE/AHardwareBuffer `0x325` 到 OES/packed10 的适配歧义。本实验只查输出能力与前12帧实际配置，**不验证 P5 逐帧 RPU、颜色或4K50持续吞吐**。

独立 Java 探针源码为`artifacts/android-p5-hevc-decoder-probe/{CodecProbe,BufferProbe}.java`，JDK/android-35.jar/d8 `--min-api 29` 编译，设备 `app_process` 运行，不修改项目 APK。`MediaCodecList.ALL_CODECS` 对目标非安全硬解列出 Main/Main10 profile，`colorFormats=[0x7f420888,0x15,0x7f000001]`：前两者分别为公开的 flexible YUV420 与 YUV420 semiplanar，**没有列出公开 P010**；`0x7f000001` 保留为厂商格式，不能从编号推断其布局，也不能与AHardwareBuffer的`0x325`混同。能力 API 报告 `areSizeAndRateSupported(3840,2160,50)=false`，但本实验的前12帧确实能解码，因此该能力标志不能替代实测持续吞吐。完整枚举见`artifacts/android-p5-hevc-decoder-probe/device-output.txt`。

手机 Android `MediaExtractor` 无法从原 `dvh1` P5 MP4 枚举视频轨（应用进程外两条路径均为`no video track`），故用 FFmpeg **无重编码**取最初1秒封成 `hvc1`，仅用于HEVC基础层的输出格式探测。探针片 `/tmp/media-kit-p5-probe-hvc1-1s.mp4` SHA-256 `87cf7e963e7731c357b09899cadc2fc40fedf1303a432ef8544648d8752a7b6b`，52个视频packet的`size,SHA-256`与原片前52包逐项完全一致（清单SHA均`af9e15475feee93db55946079e583feef1e612ed662de17133dd84df0d387b3b`）。封装/CSD 仍可能影响解码器配置，所以此结果只用于判断该码流在这条 ByteBuffer 路径的输出，不代替原 `dvh1` Surface/P5 全程。

| ByteBuffer请求 | 实际`color-format` | 首帧输出字节 | `Image`格式与平面 | 结果 |
| --- | --- | ---: | --- | --- |
| 默认 | `21` (`0x15`) | 12,441,600 | `YUV_420_888`、3平面，Y pixelStride1、UV pixelStride2 | 8-bit 4:2:0 |
| 显式`COLOR_FormatYUV420Flexible` | `21` (`0x15`) | 12,441,600 | 同上 | 8-bit 4:2:0 |

`12,441,600 = 3840×2160×1.5`字节；Y平面容量8,294,400字节，UV的pixelStride为2，证实本次 CPU 可读输出是每样本8-bit，不是 P010 10-bit 容器。两轮均输出12帧，输入format报告HEVC Main10 profile2。原始输出分别见`artifacts/android-p5-hevc-decoder-probe/buffer-hvc1-{default,flexible}.txt`，两者内容相同 SHA-256 `7a996764abea775af764805c20ff108fa6de335ccb75bd3b2271ecc227a79161`。这证明**这台机并非只能输出PRIVATE**，但已验证的公开 ByteBuffer 路径会降至8-bit，不能取代保留10-bit的P5渲染路径。未知的厂商格式和其他MediaCodec配置尚未证明能给公开可读10-bit数据；不要把“未列出P010”外推为硬件物理上绝无其他10-bit输出。

公开下载区的243MB原片副本、1秒探针副本和设备探针jar已删除；手机仍为10369基线、应用无进程。下一步若要区分华为硬解重构与PRIVATE/OES取样，可让同机 ByteBuffer 8-bit 路径解同一PTS并明确10→8-bit量化规则，作为**诊断辅助**；它不能直接作10-bit bit-exact L1。更可靠的10-bit检查点仍需厂商接口或获证的第二条可观察路径。

该同帧 ByteBuffer 诊断随后完成：PTS10.000 的8-bit Y/Cb/Cr与独立软件10-bit逐样本右移2位**全帧一致**；PRIVATE/OES→GPU仍有局部差异。完整方法、结果和配置差别限制见`android-p5-output-mode-sameframe-20260925.md`。
