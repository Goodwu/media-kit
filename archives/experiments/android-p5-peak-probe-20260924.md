# P5 高代码值位置与尺度校正探针（2026-09-24）

目的：用固定原片全帧软件扫描所得 Y/U/V 峰值位置，检查 packed10 写入前 `1020/1023` 校正在较高代码值和局部快速变化位置的效果。此为 raw prepass 诊断，不是 RPU 最终输出、可见画质或性能验收。

在隔离 mpv 源码加入默认关闭的 `debug.media_kit.p5_raw_peak_probe=1`，只在像素读回开启、九宫格关闭时，于 PTS 18.40、56.62、62.56 秒各读一个固定位置。arm64 `libmpv.so` 构建通过；整合补丁 `android-p5-peak-8346-integrated-mpv-20260924.patch` SHA-256 `138f4e9e574013f7525b0d3596d07d0bb03ba385cef162a513d6205ecc60d6d4`。测试 APK `/tmp/media-kit-p5-peak-8346-arm64.apk` SHA-256 `957e5c43ca2a3fd797be44f97adfb9bee56c4939bd1f75f2b99d94a002210a9b`，包标签8346，内部 versionCode仍8340。使用 LYA-AL00 `3EP7N18C28016072`，同一 APK 切换 `p5_raw_code_scale=1/0`；其余为 P5 MediaCodec/RPU、raw packed10、Texture SDR。两轮均出现 Dolby Vision/full/BT.2020/PQ 帧参数，三个读回点 GL error 均0。

| PTS / FBO坐标 | FFmpeg源 YUV | 校正开 | 校正关 | 结论 |
| --- | --- | --- | --- | --- |
| 18.40 `(1538,714)` | `(399,888,634)` | `(387,833,643)` | `(388,835,645)` | 原片 U 峰值未在该FBO点保留 |
| 56.62 `(2078,1552)` | `(883,518,510)` | `(883,518,510)` | `(886,520,512)` | 原片 Y 峰值及其他两分量逐值匹配 |
| 62.56 `(2388,318)` | `(549,803,902)` | `(494,771,839)` | `(495,773,841)` | 原片 V 峰值未在该FBO点保留 |

三个位置的“校正开”值都等于“校正关”值经约 `1020/1023` 缩放后的量化结果；这证明开关在较高采样值处按预期生效。**不能**由此称原片所有峰值被精确保留：18.40 与62.56秒的源/GPU差异远大于0.294%尺度差。最初单点±16像素搜索曾提示约2像素偏移，后续8347局部网格证明这种解释错误，见下。此前中心/九宫格相等不能推广到高梯度边缘。

8347在相同软件源/硬解/RPU/packed10校正开启路径上，增加默认关闭的`debug.media_kit.p5_raw_local_probe=1`，在18.40和62.56秒各一次`glReadPixels`读回峰值中心7×7，GL error均0；原中心P5_PIXEL三点复现8346开组数值。与FFmpeg相同PTS/数值坐标的49像素比较，18.40秒Y/U/V各45/49严格相等，**同一个2×2块**四个像素三分量不等（Y最大差13，U最大差55，V最大差9）。62.56秒Y/U/V分别19/49、9/49、9/49相等，最大绝对差分别63/40/63；差异是局部区域，其他像素仍有完全相等。按±8像素整数平移搜索两处各通道的全网格均方误差，三通道最佳均为`(dx,dy)=(0,0)`，排除简单全局坐标平移。`GL_NEAREST`已用于外部纹理，但尚无法分离硬件解码输出的局部差异、厂商YUV sampler行为及色度重建。下一步可对同PTS硬解AImage的可映射原始平面或另一输出路径作独立参考；不应通过整体移坐标修复。

8347 APK `/tmp/media-kit-p5-local-8347-arm64.apk` SHA-256 `7d540bcfe9d6ec03b93057e44626bb8f5f66781e1f51ed00017cd3761a9f4cec`，stripped libmpv SHA-256 `79fec05a5f04a0bb428ebd73b5288860d4e458ed636ec44bc7e7f0759892937f`，整合补丁`android-p5-local-8347-integrated-mpv-20260924.patch` SHA-256 `ac4be45534953d99ade392d999584c1895c5194d02712392bd9b984528781254`，日志`/tmp/media-kit-p5-local-8347-logcat.txt` SHA-256 `96e453f1888932add47bd5d8fb1843ae9745ebf20191c998c3851f6bdde7ea2c`。arm64编译、APK对齐/签名/验签、mpv diff-check通过；此包标签8347，内部versionCode仍8340。7×7同步读回不能计性能。应用已强停，新增local属性及其他P5属性逐项置0回读，全0；设备保留8347。

后续参考稳定性与真机重放（同日）：原片第920帧和第3128帧分别以FFmpeg HEVC软件解码`-threads 1`/`8`输出`yuv420p10le`，同帧整帧SHA-256完全相同，分别为`77570774e460adff32f9f389f6fb883d32fbd1b95548e4b774244ddf004f5f14`、`3b366a71a3f7cdda4a5d7968c6af62b8b2557c0e0878f4fa14d7b0d2a94affef`，无解码警告。macOS FFmpeg `-hwaccel videotoolbox`同样导出这两帧，整帧SHA与软件输出逐字节一致；debug日志显示`Format videotoolbox_vld chosen by get_format()`和所需HEVC VideoToolbox初始化。这构成另一硬解参考，但不代表华为硬解路径。8347同配置真机第二轮在18.40/56.62/62.56秒复现全部中心值；18.40和62.56秒两组7×7合计98个位置的Y/U/V与前轮**完全相同**，读回错误仍0。重放日志`/tmp/media-kit-p5-local-8347-repeat-logcat.txt` SHA-256 `88ba759d64fbf812b08d3fd194217a32e85e2cf879d31cb964ccba3a513b33a0`。因此局部差异可稳定复现，且不是软件线程数或VideoToolbox参考的不同结果；仍无法在当前手机上把硬解输出与外部纹理采样两段分开。

接口边界：当前`hwdec_aimagereader.c`以`AIMAGE_FORMAT_PRIVATE`创建`AImageReader`，实际AHardwareBuffer厂商格式`0x325`。本机NDK `NdkImage.h`明确PRIVATE图像平面数为0、应用无法直接读取内容，故不能通过`AImage_getPlaneData`从现有路径取硬解原始YUV作CPU参考。若要分段定位，需独立验证目标机是否支持可访问的10-bit输出路径，或增加另一种不会误解释私有格式的受控采样参考。复测后应用强停，九项P5相关属性均置0并回读。

设备为 Android 10/API29；当前NDK `NdkImage.h`有`AIMAGE_FORMAT_YUV_420_888`和`PRIVATE`，未提供可直接选作此`AImageReader`输出的P010枚举。改用420_888会改变10-bit路径，不能当同条件对照。8347日志显示实际解码器`OMX.hisi.video.decoder.hevc`、bitDepth从8切至10，厂商日志称开启HFBC并转换到linear模式；这些只说明路径配置，不能据此归因局部差异。

以macOS VideoToolbox参考帧`n±2`（五帧）逐帧与8347的7×7 GPU读回算每通道全网格MSE：18.40秒目标`n=920`的Y/U/V误差`12.27/246.94/6.61`，相邻`n=919`为`4262.14/5302.73/98.08`、`n=921`为`1715.67/1626.12/57.94`；目标帧明显最好。62.56秒`n=3128`为`609.69/275.59/703.55`，前帧`800.73/548.06/1004.16`、后帧`879.82/445.04/656.63`；V单通道后帧误差略低但无精确匹配，Y/U目标帧最好。整体不支持简单整帧PTS错位或邻帧替换，局部采样/硬解差异仍待分离。

校正开、关原始 logcat 分别为 `/tmp/media-kit-p5-peak-8346-on-logcat.txt` SHA-256 `92728e17dde846238a5f61325f833602f3a3a7e57488ffb1cb87075e75052bdb`、`/tmp/media-kit-p5-peak-8346-off-logcat.txt` SHA-256 `65221d06c1e0ba4ed346fd2e3688f6e2c9aeffc65a4d7ea503e2ae901f993b5c`。诊断读回同步GPU，不能以这两轮的VO掉帧作校正性能判断。后续应先用局部网格/坐标变换与软件参考分离外部纹理的取样位置及色度滤波，再验证 RPU reshape 后图像；保持校正默认关闭。

8346轮结束后应用强停，`p5_rpu_probe,p5_raw_yuv,p5_raw_mrt,p5_raw_packed10,p5_raw_pixel_probe,p5_raw_spatial_probe,p5_raw_peak_probe,p5_raw_code_scale` 均置0并逐项回读为0；随后8347轮再次清理并替换安装包。
