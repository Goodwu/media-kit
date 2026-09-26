# P5 4K50 同压缩帧主机/手机 RGBA 浮点对照（2026-09-25）

目标是给 8370 手机 `pl_render_image_mix` 后的 RGBA16F 整帧建立同压缩源工程参考，不使用 mpv screenshot。原片 `/tmp/media-kit-DV-P5.mp4` SHA-256 `328cae5c78ba9b8e579e7352edcfb8f3e9e0c0670849fc8773a8b028d2d1d03e`；手机 PTS10.000 读回 `/tmp/media-kit-p5-float-8370-pts1000.rgba16f` SHA-256 `7f5f5154ab14fbce3d77dc4110ac25830c403b43be5839591c15532b441c157d`，尺寸 3840×2160，BT.2020/PQ、目标峰值 1000 nit。旧实验已核手机和主机该帧附着 RPU 同为 206 字节、FNV-1a `907c8b42`（`android-p5-post-rpu-phone-20260924.md`）；此轮未重新从主机渲染器读出 RPU hash。

主机在隔离 `/tmp/media-kit-ffmpeg-dvtest-host-20260925` FFmpeg n7.1.3、libplacebo 7.360.1、MoltenVK 1.4.2/Apple M4 上运行；FFmpeg filter 默认生成的 PQ target `max_luma=0`（未知），而手机为 1000 nit，因此仅在临时 `vf_libplacebo.c` 对 3840×2160/PQ 输出显式设 `min_luma=0,max_luma=1000`，不改系统安装或项目产品代码。该临时补丁 diff SHA-256 `b0d28244a7f44264add6eca806555bd05c6ea40f375698caf1aa0d32a92d7a7d`，构建出的 `ffmpeg` SHA-256 `f0950170fe45d29a1834af9130db0efc08e7618089979360dda9cb6daf69a45a`。滤镜固定 `libplacebo=format=gbrpf32le:colorspace=gbr:color_primaries=bt2020:color_trc=smpte2084:range=pc:peak_detect=0:tonemapping=clip:gamut_mode=clip:dithering=none:contrast_recovery=0:upscaler=nearest:downscaler=nearest:sigmoid=0:apply_filmgrain=0`。这是明确的**主机测试 policy**；手机 mpv 报 `tone-mapping=auto,target-peak=auto`，虽然手机隔离开关强制最终 target 1000 nit，未证明全部内部策略与 FFmpeg 完全一致。

从片头顺序解码后用输出侧 `-ss 10 -frames:v 1` 选帧。该命令独立导出的 `yuv420p10le` 基层原始文件 SHA-256 `8a41d06c8b14a313864d04907bf3cca667d6f732fa2b2db281d105c3b833fe44`，与既有 FFmpeg 第500帧/PTS10 软件参考逐字节相同。主机 libplacebo 输出 `/tmp/media-kit-p5-host-pts1000-gbrpf32le.bin` 为 99,532,800 字节、SHA-256 `5674b1c26a9380a112bbc35a542c3bd9b84e36e3b337908cd6c76ca5363a0d42`；输出是 planar G/B/R float32。手机文件是 interleaved R/G/B/A half，GL 读回以下方为原点，而主机输出以上方为原点；相同显示坐标的比较须对主机做 `host_y=2159-phone_y`。未做平移、曝光拟合或裁剪。对比脚本 `tools/p5_float_sameframe_compare.py` 已通过 2×2 人工图的通道/行序零误差自检；完整 JSON 在 `/tmp/media-kit-p5-host-phone-pts1000-compare.json`。

| 通道 | 全帧 MAE | 中位绝对差 | P99 | 最大差 | 差值 >0.01 的像素 |
| --- | ---: | ---: | ---: | ---: | ---: |
| R | 0.000619 | 0.000244 | 0.008911 | 0.184082 | 69,041 / 8,294,400 |
| G | 0.000316 | 0.000244 | 0.003662 | 0.166015 | 13,934 / 8,294,400 |
| B | 0.000813 | 0.000488 | 0.010498 | 0.396484 | 90,414 / 8,294,400 |

直接按文件行序比较的每通道 MAE 为 `0.0338/0.0466/0.0509`；按声明的上下原点转换后降低到表中数值。大多数像素接近 FP16 量化级，但尾部差异明显，**不能判全帧颜色数值通过**。最差蓝色点 `(1751,1189)` 主机接近 0、手机 0.39648。对蓝通道差值 >0.05 的点抽 600 个做仅供诊断的 ±2 像素邻域搜索，RGB 最大分量差的中位数从 0.07886 降至 0.01440，517/600 可降至 <0.05；说明局部空间取样/边缘关系值得优先排查，不能把邻域配准后的值当验收结果。此现象与先前硬解外部 YUV sampler 的局部峰值分歧方向一致，但尚未分离硬解输出、chroma upsampling、GPU采样、RPU 非线性和 tone/gamut 策略的贡献。

下一步应在同一手机帧上增加映射前 L2C 浮点读回，主机也分别导出 L2C 和 L3，并固定两端完全相同的 `policy_id`。先对异常坐标采样原始 YUV/reshape/PQ 检查点及邻域，不改变图像配准或阈值来掩盖差异。现有结果建立了同码流、同基层帧、同 RPU payload 的工程对照及正确的坐标关系，但仍非独立 Dolby golden，也不证明 HDR 显示或连续播放门禁。

## 同帧主机映射策略 A/B

同一临时 FFmpeg/libplacebo 构建增加只读日志，确认 P5 映射源 `BT.2020/PQ`、DoVi 数据存在，source `max_luma=1000.61,min_luma=0.000104341`，target `BT.2020/PQ,max_luma=1000,min_luma=0`。在同一个输出侧 `-ss 10 -frames:v 1`、相同 4K 输入下分别运行：原 `peak_detect=0,tonemapping=clip,gamut_mode=clip`；`peak_detect=0,tonemapping=auto,gamut_mode=perceptual`；以及后者加 `peak_detect=1,smoothing_period=20,scene_threshold_low=1,scene_threshold_high=3`。三份 GBR float32 文件逐字节相同，SHA-256 均为 `5674b1c26a9380a112bbc35a542c3bd9b84e36e3b337908cd6c76ca5363a0d42`。因此这些**主机 libplacebo policy 开关对该帧输出没有数值影响**，不能解释已见的手机尾部误差；不能由此断言手机 mpv 的所有内部处理也相同。重复的两份 99.5MB 输出在 `cmp` 后已删除，保留原始主机参考。

只读日志后的临时 FFmpeg SHA-256 `a21bd869c9c660942e565e7bddbf164122ff21e862bbe8a85703693a1e0014a5`、临时补丁 diff SHA-256 `3f9aa7133434b60269fc6aeda97dfc3339ccde7ff0ef08c2cad9f8f017afae6d`；这两个哈希与上文最初输出所用构建不同，仅多了源参数日志，A/B 结果用输出 SHA 比较。下一步应优先对异常位置的手机原始采样及 L2C 读回，而非继续调这些主机映射选项。
