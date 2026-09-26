# 华为 HFBC→LINEAR 日志所属库定位（2026-09-25）

设备 LYA-AL00 / Android 10，adb只读检查当前 `/vendor/lib64`。实际 mapper 文件为 `/vendor/lib64/hw/android.hardware.graphics.mapper@2.0-impl-2.1.so`，SHA-256 `682feb165446a095e6cfb2bbe2de8e2750cce4d14b62f6d538cc25b64ab84641`；此前按无`-2.1`后缀猜的路径不适用于此设备。

`/vendor/lib64/libOMX.hisi.vdec.core.so` SHA-256 `6e1b24e1dc9514089be60cda56a682ab7df98c1d013c957ac6115babdcf25cf3` 包含 `FormatConverter` 构造/析构、`InitFormatConverter` 及日志模板 `enable hfbc, and set commonblock in HFBC->LINEAR mode`。该字符串位于库内偏移`0x138d0`；反汇编在 `HiDecoder::QueueOutputBuffer` 的`0x388ac`构造其地址，分支`0x38878–0x388bc`满足内部状态检查后设置字段并调用`HiLog`。因此此日志来自解码器核心库的队列输出路径，不是 gralloc 的格式定义，也不能单凭日志断言外露 AHB `0x325` 的物理布局。

同轮复核 gralloc SHA-256 `c56074edfb7c388edf615eee08e7118033f613396d19272bfb36ea693d0ba35d`；`CheckHfbcSupport`分离`0x324/0x325`族字段和额外HFBC条件，`GetYuvHfbcSizeAndDimensions`会读取两者。`GetYuvPx10SizeAndDimensions`虽有动态表项，但可见键是`0x402/0x403`，尚未与`0x324/0x325`建立代码级一一映射；UV/VU假设保留为待验证。未更改设备或系统库，临时提取文件检查后清理。

随后定位到由该解码器库调用的 `libosal.so`，其 `VCodecFormat2HalFormat` 表直接给出内部 `ColorFormat` 3→`0x325`、4→`0x324`；见 `android-p5-libosal-format-map-20260925.md`。这确认外露格式号的转换来源，但仍不提供3/4的UV/VU名称或plane布局。
