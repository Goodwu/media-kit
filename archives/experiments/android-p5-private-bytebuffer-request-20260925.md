# P5 厂商格式 ByteBuffer 请求实验（2026-09-25）

目的：检查不经过 Surface/GL 时，向同一华为 HEVC 解码器显式请求 `0x325` 或相邻 `0x324`，能否得到可观察的原生 10-bit 输出。输入是原 P5 前52个 HEVC 包无重编码重封装的 1 秒 `hvc1` 片；该片只验证基础层输出，不验证 DV RPU。独立探针源码及原始输出位于 `artifacts/android-p5-hevc-decoder-probe/PrivateFormatBufferProbe.java`、`private-buffer-0325.txt`、`private-buffer-0324.txt`。

设备 LYA-AL00 / Android 10，解码器 `OMX.hisi.video.decoder.hevc`；`MediaCodec.configure(format, null, null, 0)` 中分别设置 `MediaFormat.KEY_COLOR_FORMAT=805/804`。两次配置均成功，均解出12帧，但配置后和首帧后的实际 `color-format` 均为 `21 (0x15)`，宽高3840×2160、stride3840、slice-height2160，首帧 `BufferInfo.size=12,441,600 = 3840×2160×1.5` 字节。`getOutputBuffer()` 非空。此实验未读取或解释缓冲字节；结合已归档的默认/flexible ByteBuffer 平面检查，实际路径仍是8-bit YUV420输出。

结论：把华为 AHardwareBuffer format `0x324/0x325` 填入 MediaCodec 的 ByteBuffer `color-format` 请求并不会让本机暴露相应的原生10-bit CPU缓冲；codec接受但回退到8-bit `0x15`。这两个 API 的编号域不能直接等同。实验也**不能证明**厂商内部不存在可用的10-bit输出模式，或判定 PRIVATE/Surface 内部误差的具体来源。P5 L1硬解原生10-bit检查点仍未取得，下一步需沿厂商 decoder/mapper 的私有元数据或受控 Surface 输出边界定位，而不是凭 `0x325` 按 P010 解析。

探针由 JDK、Android 35 API jar、d8 `--min-api 29` 编译，通过 `app_process` 在设备运行。设备上的本实验 jar 和输入副本已删除；未改产品 APK。
