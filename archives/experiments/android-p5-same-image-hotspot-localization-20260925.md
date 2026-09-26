# P5 已知差异热点的独立 AImage raw 采样（2026-09-25）

## 问题与对照

前轮 mpv 的 PTS10/第500帧 packed Y sidecar 对软件 HEVC 参考有24,348个Y样本不同；单靠该输出无法区分 mpv sidecar 打包与更早的 PRIVATE buffer / 厂商纹理路径。本轮在独立 `app_process` + MediaCodec + `ImageReader.PRIVATE` 中对**同一张 AImage**分别采普通 OES RGB 与 `GL_EXT_YUV_target` raw YUV，并选取前轮真实差异中的七个 Y 热点及三个对照点。两次运行验证读数复现；这是定位实验，不计产品性能。

设备 LYA-AL00 / Android 10，`OMX.hisi.video.decoder.hevc`，输入为P5前512个HEVC包无重编码`hvc1`重封装 SHA-256 `08dfce089257b824e60bf38164093691f941edfd29bf2de29df9924f4cfea5a5`。前轮已证明第500包与原P5码流包一致，并在带/不带DV配置的同文件控制中复现了mpv目标 sidecar，见 `android-p5-dvcc-output-control-20260925.md`。本轮探针只验证HEVC基础层，不验证RPU后的颜色。

两轮 Image timestamp 均为`10,000,000,000ns`、`matchedOutputOrdinal=500`、AHB format`0x325`；EGL image、普通OES和raw YUV绑定成功，目标采样FBO及`glReadPixels`报告GL error0。Java回调序号可能跳变，比较只用PTS/输出ordinal。探针 C++ 仅从现有 `p5_gpu_import_probe.cpp` 改为在RGB10_A2目标上采10个固定坐标并打印十进制；源 SHA-256 `c42191c90c6da928882abaa2c7eefc8706a61007fba63328d256ea6ce7e1cafb`。原始两轮输出分别为 `artifacts/android-p5-same-image-hotspots/run-{1,2}.txt` SHA `d31a8c00406e7a95052ac452ec68cd71e0770b32f2fd8a6b3345e9c89acbe817`、`dd8b4e22b446cef2cf23fd00cbbb014981f34ed91d65245a894dfed5561f708d`。

## 结果

软件第500帧`yuv420p10le` SHA `8a41d06c8b14a313864d04907bf3cca667d6f732fa2b2db281d105c3b833fe44`；mpv先前 packed Y SHA `b04220ef51629371d77e5d5eccd9ca773ae063e462d1c3499fcb5a37f048e81f`。raw sampler 输出按既有合同为 `round(10-bit码值 × 1023/1020)`。十个坐标中：

| 坐标 | 软件 Y | mpv sidecar Y | 独立同AImage raw GPU Y | 判断 |
| --- | ---: | ---: | ---: | --- |
| (2577,1221) | 182 | 275 | 276 | GPU等于mpv归一化，偏离软件93 |
| (2576,1221) | 193 | 279 | 280 | 同型 |
| (203,1105) | 726 | 666 | 668 | 同型 |
| (1762,939) | 706 | 648 | 650 | 同型 |
| (2215,1113) | 728 | 671 | 673 | 同型 |
| (1785,963) | 708 | 654 | 656 | 同型 |
| (2577,1220) | 334 | 338 | 339 | 同型 |
| (2577,1222) | 120 | 120 | 120 | 对照匹配 |
| (384,1080) | 421 | 421 | 422 | 对照匹配 |
| (1920,1080) | 415 | 415 | 416 | 对照匹配 |

**10/10个独立GPU Y均等于先前mpv sidecar Y归一化后的整数；七个软件差异坐标全部由独立路径复现，三对照点保持匹配。两轮全部10点raw YUV三分量逐值相同。**完整Y/Cb/Cr及自动检查见 `artifacts/android-p5-same-image-hotspots/compare.json` SHA-256 `2054b0ad372b7d9505f9703f4d2dcb4315a4e17c32e961bf72816d9fec794ee9`；脚本 `tools/p5_same_image_hotspot_compare.py`。固定10个热点是有目的选择，不能用其失败比例外推整帧。

## 结论边界

这些局部差异已在**不经过 mpv 的独立 MediaCodec→同AImage→EGL raw sampler**链上出现，且数值与mpv sidecar相同，因而不能再把它们归因于 mpv 后续的 sidecar打包、RPU或显示映射。仍不能区分华为解码器重构、Surface输出转换、GraphicBuffer backing或厂商 `GL_EXT_YUV_target` raw取样哪一环产生差异；raw sampler不是可直接观察的解码器L1原生整数。普通OES RGB虽在同AImage成功读回，其YUV→RGB转换结果未与独立颜色真值比较。

产品基线APK未改，探针暂存文件已清理。下一步若要进一步分离，需取得获证的私有buffer plane合同/厂商转换输出，或设计能区别Surface转换与raw sampler的受控GPU/CPU检查点；同时P5色彩、4K50实时性、HDR显示门禁继续单列。
