# P5 基础层同一 AImage 普通 OES / raw YUV 双读回（2026-09-25）

## 输入与运行

LYA-AL00 / Android 10，固定 `OMX.hisi.video.decoder.hevc`，独立 `ImageReader.PRIVATE`、GPU sampled、maxImages2。使用无重编码的前512包 `hvc1` 重封装文件 SHA-256 `08dfce089257b824e60bf38164093691f941edfd29bf2de29df9924f4cfea5a5`；前512包 `size,SHA-256` 与原P5对应包逐项一致，依据 `android-p5-output-mode-sameframe-20260925.md`。此重封装缺原 DV config，仅检查 HEVC 基础层与同一 buffer 的 GPU 采样，不验证 RPU 后颜色。

复用 10369 APK 中 `libmedia_kit_p5_probe.so`（SHA-256 `0787dd39b78f65d89c4d7d804dbb609caaecb7c8f2e63257f893665a1656bbd7`）的 `inspectGpuImport`，将其 Java 类以 `app_process` 独立运行。探针同一次 `eglCreateImageKHR`/`glEGLImageTargetTexture2DOES` 导入后，分别用普通 `samplerExternalOES` 和 `GL_EXT_YUV_target` 的 raw sampler 取样；都在原始大小、原图 crop 下离屏读回。诊断 Java 源与入口在 `artifacts/android-p5-same-image-dual-import/`，原始输出 `output-pts10.txt` SHA-256 `15860077964c2b78e4135d0e1c7a07b1422fdf42164c008eb752eb134ff7af9d`。

## 目标帧与数值

目标 Image timestamp `10,000,000,000 ns`，对应 codec 输出 PTS `10,000,000 μs`、`matchedOutputOrdinal=500`，AHB format805/`0x325`、3840×2160、usage10496。Java Image 回调索引491，不能用该索引代替显示帧号；本轮以完整PTS配对。EGL image创建、OES绑定、raw YUV扩展、RGBA8/RGB10_A2/RGBA16F FBO均成功，报告 GL error0。普通 OES RGB 与 raw YUV来自**同一 HardwareBuffer**，不是两次解码。

以软件 HEVC 第500帧 `yuv420p10le`（SHA-256 `8a41d06c8b14a313864d04907bf3cca667d6f732fa2b2db281d105c3b833fe44`）为工程参考。在 y=1080，x=384/1152/1920/2688/3456 五点，raw sampler的RGB10_A2三分量按 `round(软件码值 × 1023/1020)` 对照：

| x | 软件 Y,Cb,Cr | 预期归一化 | 同AImage raw GPU |
| ---: | --- | --- | --- |
| 384 | 421,502,463 | 422,503,464 | 422,503,464 |
| 1152 | 387,513,484 | 388,515,485 | 388,515,485 |
| 1920 | 415,514,508 | 416,516,509 | 416,516,509 |
| 2688 | 250,508,465 | 251,509,466 | 251,509,466 |
| 3456 | 417,490,451 | 418,491,452 | 418,491,452 |

15/15分量精确匹配该采样/量化合同。普通 OES 的同图RGB10_A2五点见原始输出 `sampleFull`，例如 x=384 为339,461,397；它经过厂商YUV→RGB解释，不能直接拿来与未转换的YUV码值相减。本轮证明同一私有 `0x325` buffer 可通过两种GL路径观察，并给出五点 raw YUV 一致性；**不证明整帧L1 bit-exact，也不解释前轮双平面整帧Y24,348/Cb6,017/Cr6,313个局部差异**。下一步需同AImage密集ROI或整帧 raw YUV/普通OES采样与软件基准对齐，同时固定纹理过滤、坐标及量化合同，不能混用Image回调序号与PTS。

探针只读，设备暂存jar/so/片已清理，产品APK与诊断属性未更动。
