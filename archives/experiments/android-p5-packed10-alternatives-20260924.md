# P5 packed10 的发现依据与下一代路径排序（2026-09-24）

当前问题不是解码器掉帧：有效 R32F/MRT 轮 decoder 掉帧为 0，而长播 VO 大量掉帧。原 raw YUV prepass 对每帧 3840×2160 生成三张 R32F（约99.5 MB/组）；R16F 三平面实测不优，R16 UNORM 在本机缺 `GL_EXT_texture_norm16`。本地 mpv `vo_gpu_next` 能按自定义像素格式把同一 plane 上三个分量映射给 libplacebo，因此提出将 Y/U/V 放进一张 `GL_RGB10_A2` 的 R/G/B 通道。Khronos [OpenGL ES 3.0 规范](https://registry.khronos.org/OpenGL/specs/es/3.0/es_spec_3.0.pdf)列 RGB10_A2 为 10/10/10/2、color-renderable、filterable；[EXT_YUV_target](https://registry.khronos.org/OpenGL/extensions/EXT/EXT_YUV_target.txt)规定 Y2Y 取样输出为 4:4:4 语义并把 Y/U/V 分别放在 R/G/B。设备实际 FBO、libplacebo 包装、同包 A/B/A 全片、同 PTS 读回另见 `android-p5-packed10-runtime-20260924.md` 和 `android-p5-packed10-pixel-20260924.md`。

按当前 **每个 4:4:4 像素保留三个 10-bit 分量** 的前提，信息量下界是30 bit/像素；RGB10_A2 占32 bit/像素，仅多2 bit。这不证明实际显存布局或读写带宽一定最优，但继续换常规单张未压缩纹理已没有明显容量空间。R11F_G11F_B10F 是不同的浮点数值模型、仍32 bit，不能无验证替代10-bit代码值；RGB10_A2UI 同为32 bit且整数采样链不同；RGBA8 手工分配30 bit仍32 bit并增加打包/解包；单张RGBA16F为64 bit。因此不应为单纯再省几个位优先重写已验证的 packed10 路线。

有两类可能更省资源，但实现边界不同：

1. **融合外部 YUV 取样与 DV reshape/输出 shader，消除整张中间纹理。** 这是潜在最大收益。当前 libplacebo 对 `GL_TEXTURE_EXTERNAL_OES` 只标记普通 `PL_SAMPLER_EXTERNAL`，shader 使用 `samplerExternalOES`；它会走普通外部纹理的 RGB 语义，不能直接保持 P5 所需原始 Y/U/V。要融合必须为 `__samplerExternal2DY2YEXT` 建立新 sampler/格式语义，保持逐帧 DOVI metadata、裁剪/PTS、图像所有权与 GPU 完成同步，还要验证 libplacebo 的 reshape 与色彩流水线。此项是架构候选，**不是现成 mpv 选项或已验证设备路径**。
2. **改为可访问的 10-bit 4:2:0 解码平面，例如 P010。** 理论 P010 16-bit 容器的Y全分辨率加UV四分之一分辨率约24 bit/像素，比当前32 bit少25%；但它不是当前 4:4:4 GPU 取样的直接等价物，色度上采样/采样位置须证明一致，且可能改变解码输出/复制路径。当前 ImageReader 是 `AIMAGE_FORMAT_PRIVATE`，实际硬件缓冲为厂商 `0x325`；Android [NDK 文档](https://developer.android.com/ndk/reference/group/media)明确 PRIVATE 图像内容不可由应用直接访问，不能把该缓冲当作公开 P010 平面。若要尝试，须先独立验证此设备 MediaCodec 能否以不牺牲硬解吞吐的方式输出可映射10-bit平面，再验证 RPU 与颜色。

优先级：先完成 packed10 的空间像素与 RPU reshape/独立颜色参考、可见流畅及 PQ 显示出口；若性能在 PQ 路径仍不足，再原型验证融合 shader。仅当设备证实公开10-bit平面可用时评估 P010。任何更省中间纹理的方案都不能解决目前独立的 PlatformView PQ dataspace `-22` 门禁，不能据 Texture SDR 性能宣称 HDR 闭环。
