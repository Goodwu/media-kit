# P5 单纹理 10-bit YUV 候选接口复核（2026-09-24）

目标仍是让 3840×2160、约 50 fps 的 P5 以硬解、逐帧 RPU reshape 和正确色彩持续流畅播放。当前 raw/MRT 路径将 Y/U/V 写入三张全尺寸 R32F 纹理，单组理论存储为 `3840×2160×3×4 = 99,532,800` 字节。此前 R16F 性能更差；R16 UNORM 在目标机缺扩展，不能比较。单张 RGB10_A2 每像素 4 字节，单组理论存储为 33,177,600 字节；这只是纹理容量差，不是实际显存、带宽或速度测量。

复核本地隔离 mpv 源码 `/tmp/media-kit-mpv-clean-2194`：

- `video/out/opengl/formats.c` 已列 `rgb10_a2`（`GL_RGB10_A2`，ES3 color FBO 条件）；`video/out/gpu/ra.c` 的格式表列 10/10/10/2 UNORM。现有 `video/out/opengl/ra_gl.c` 只将它特殊映射为 RGB30，不能直接把 RGB 语义用于 P5 YUV。
- `video/img_format.c` 的自定义描述可声明 YUV、同一 plane 上三个 10-bit component；`video/out/vo_gpu_next.c` 的硬解路径按描述设置 `frame->num_planes` 和按 bit offset 排序的 `component_mapping`，`hwdec_acquire` 只包装实际提供的 plane。故一张纹理承载 Y/U/V 在接口上可尝试，但须新增独立 YUV 格式，不能重用 RGB30。
- 当前 mapper 一次 draw 向三个 R32F attachment 写原始 Y/U/V，`dst_params.imgfmt=IMGFMT_444PF` 且 `repr.bits` 为 10/10。候选应是一个 RGB10_A2 attachment、一次 draw 输出 `vec4(Y,U,V,1)`、一个 `mapper->tex[0]`、自定义 packed YUV 描述，并继续保留逐帧 DOVI metadata 与 10/10 bits；默认关闭，原路径作为同包对照。

后续已实现候选并完成同包 A/B/A 全片实验，见 `android-p5-packed10-runtime-20260924.md`。该复核保留为实现前的接口依据；独立 10-bit 分量与 RPU reshape 数值、可见颜色和 HDR 激活仍待验收。
