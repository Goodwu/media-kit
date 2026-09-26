# P5 同帧尾差：原始 YUV、libplacebo 版本与色度位置（2026-09-25）

承接 `android-p5-float-host-sameframe-20260925.md` 的 4K50 P5 PTS10.000 全帧差异。原片 SHA-256 `328cae5c78ba9b8e579e7352edcfb8f3e9e0c0670849fc8773a8b028d2d1d03e`，软件基层第500帧 `yuv420p10le` SHA-256 `8a41d06c8b14a313864d04907bf3cca667d6f732fa2b2db281d105c3b833fe44`；8370 手机 L3 RGBA16F SHA-256 `7f5f5154ab14fbce3d77dc4110ac25830c403b43be5839591c15532b441c157d`。以下均为同码流、同显示帧工程诊断，不是 Dolby 官方 golden，也不把对齐手机当成颜色正确性标准。

## 真机 raw packed10 小网格

在隔离 mpv `/tmp/media-kit-mpv-clean-2194` 的 raw mapper 增加默认关闭 `debug.media_kit.p5_raw_error_probe=1`，仅 PTS10.000 对三个既有 L3 最大异常中心 `(2217,1045)`、`(2580,938)`、`(1751,1189)` 各读 7×7 packed10 YUV。配合既有 `p5_raw_yuv/p5_raw_packed10/p5_raw_code_scale/p5_raw_pixel_probe=1` 与 `p5_rpu_probe=2`，8371 诊断 APK SHA-256 `68f2b5ae55d1b65f1b4b4d42f781849db50da8b8fb2f5242bf357ff83958ec89`，strip 后 `libmpv.so` SHA-256 `a5060f1b72fbd3cf8d1d7d3fa6b0f84e232f66ca00c827c0b6e84e87fc8e3998`。arm64 `ninja libmpv.so`、APK zipalign/签名/验签通过。累计 raw mapper 补丁 `android-p5-error-raw-8371-hwdec.patch` SHA-256 `dafff7e988a42a457c4a5dadf09032d51c8d15a91e15f6a3697ca8e8a1791174`，包含既有诊断改动，不能直接作为产品最小补丁。

147 个读数全部 `PTS=10.000000000`、坐标唯一、GL error `0x0`。raw mapper 坐标与软件 YUV 数组**同向**：直接 `(x,y)` 比较时 Y `146/147`、Cb `147/147`、Cr `147/147` 整数码值相同；若误做上下翻转，Y `0/147` 相同。唯一 Y 差在 `(2216,1047)`，手机 639、软件 650；三个异常中心点自身的 Y/Cb/Cr 均精确相同。手机最终 L3 FBO 则是 GL 下原点，需与主机 RGB 作上下行序转换；两个检查点的坐标合同不同，不能互相套用。真机日志 SHA-256 `0fb1107a5a9cef5d4adcc7dc01e5b69e73846e4952396f8f4bb4d8af732d510e`，归档压缩文件 `artifacts/android-p5-error-raw-20260925-8371-logcat.txt.gz` SHA-256 `c9508c49b0f5b946e4872df20faf16346eec4b033f32f4191e446fb99dd862b3`。

中心点示例：`(2217,1045)` 手机/软件均 `(432,544,544)`；`(2580,938)` 均 `(433,486,471)`；`(1751,1189)` 均 `(302,494,451)`。因此这三点的巨大 L3 差异不能简单归因于硬件基础层整数码值不同；剩余候选包括色度采样位置、4:4:4 再采样、RPU/矩阵处理精度、局部非线性与目标映射。小网格不等于全帧 L1 硬解通过。

采集后强停应用、将本轮六个诊断属性逐项回读为 0、重装 10369 基线并确认无应用进程。原片保留，手机读回临时网格只在日志中，无新增大帧文件。

## 同版主机与色度位置 A/B

Android 静态前缀 `libplacebo.pc` 标 `7.365.0`，而前轮 Homebrew 主机为 `7.360.1`。从既有 v1.2.7 源码提交 `d4624cbf` 独立构建 macOS libplacebo 7.365.0（Vulkan、shaderc、DoVi reshape；无 libdovi），dylib SHA-256 `19434d6641cc02a10b59692b05ad512536aad6d822d7be0753dae7f69365856d`；重链主机 FFmpeg n7.1.3。构建环境/后端与 Android 仍不同，但消除了 libplacebo 源码版本这一变量。输出目标仍 BT.2020/PQ/1000nit、同一主机固定 clip policy，无窗口 GPU readback。FFprobe 对原片报告 `chroma_location=left`。

| 主机输入解释 | R/G/B 全帧 MAE | R/G/B P99 | R/G/B 差值 >0.01 的像素数 |
| --- | --- | --- | --- |
| libplacebo 7.360.1，原 `left` | .000619 / .000316 / .000813 | .008911 / .003662 / .010498 | 69,041 / 13,934 / 90,414 |
| libplacebo 7.365.0，原 `left` | .000617 / .000315 / .000813 | .008789 / .003662 / .010498 | 68,882 / 13,731 / 90,308 |
| libplacebo 7.365.0，**临时改为 `center`** | .000339 / .000208 / .000456 | .000854 / .000488 / .000977 | 3,468 / 10,436 / 570 |

后两轮主机 `gbrpf32le` SHA 分别为 `b3c58d4be3f3db9580c8829605e8466937cfb2cd90f17f79c46b281424510d36` 和 `1764a8ccf47e949f720f66a6231d64ca4604c3ac75a1d66b9c54cef5d0d0ae5a`。比较 JSON 分别为 `/tmp/media-kit-p5-host7365-phone-pts1000-compare.json` 与 `/tmp/media-kit-p5-host7365-center-phone-compare.json`；相同脚本 `tools/p5_float_sameframe_compare.py` 按明确的 GBR/RGBA 通道和上下原点计算，未做平移/裁切/曝光拟合。`center` 轮只通过 FFmpeg `setparams=chroma_location=center` 改**主机输入解释**，没有改压缩码流或手机。

同版改动单独几乎不改变总体尾差；`center` 轮使 `(2217,1045)` 和 `(1751,1189)` 两处中心值接近手机，强烈指向 raw 外部纹理 4:4:4 表示与码流 `left` 色度采样位置之间的相位差。**这不能证明 `center` 是正确的解释**：码流标记为 `left`，要验证手机是否偏离该语义，应另以规范色度位置和已知图案为依据，不能为匹配手机而改元数据。

第三处 `(2580,938)` 在 `center` 轮仍有局部边界差：手机 RGB约 `(0.3975,0.1660,0.00295)`，主机约 `(0.3223,0.000712,0.000249)`，尽管 raw YUV 在该点逐码值相同；相邻上下行大体吻合。它可能是后续纹理采样/亚像素位置或近零裁剪的局部精度问题，当前尚不能定位。下一步在相同真实帧上增加 L2B/L2C 检查点，记录映射前源 crop/采样坐标；并用已知 `left` 色度边缘图案隔离取样相位，再决定是否需要修正手机 4:4:4 prepass。P5 显示颜色、HDR 激活与流畅播放仍需独立验收。
