# P5 同一 AHB 的 GLES/Vulkan Y 取样对照（2026-09-25）

目的：消除前次 Vulkan/GLES 分别解码所留下的“不是同一缓冲区”歧义。独立 `app_process` 程序将华为 HEVC 硬解输出到 `ImageReader.PRIVATE`，在同一次 `ImageReader` 回调中取得**一个** `HardwareBuffer`，先经 EGLImage/`GL_EXT_YUV_target` raw sampler 取样并 `glReadPixels`，然后把这个 Java 对象对应的 AHB 导入 Vulkan1.1 external image，经 full-range `YCBCR_IDENTITY` compute shader 取样到 host-visible SSBO。两条路径均在 Image 关闭前完成读回。探针位于 `artifacts/android-p5-same-ahb-gl-vulkan/`；对照脚本为 `tools/p5_same_ahb_gl_vulkan_compare.py`。仅用于诊断，不接播放器后端。

原始4K P5前512帧 hvc1 诊断副本，在 `timestampNs=10000000000`、`matchedOutputOrdinal=500` 的同一条 `surfaceImages` 记录中同时出现 `gpuImport` 与 `vulkanImport`，AHB format=805/`0x325`、crop=0,0,3840,2160、`timestampMatchesOutputPts=true`。十个预先指定的坐标中，两种API的 Y 值（Vulkan float×1023并取整）**10/10逐码相同**：`276,280,668,650,673,656,339,120,422,416`。前七个是既有软件Y参考不符的热点/邻点，后三个为对照。另一轮同源同帧独立运行也取得同一组十点。最终源码版原始输出 `artifacts/android-p5-same-ahb-gl-vulkan/original-run.txt` SHA-256 `e6a344bb647a62680b84aebbe69d7c23b642c9d3f97d2373077a9a8298fa585b`。

无损P5图案在 `timestampNs=10000000000`、`matchedOutputOrdinal=240` 的同一AHB上也得到10/10相同。y10 的 x233/234/236 输入Y=1011/1020/1023，GLES和Vulkan均读出 `1014/1023/1023`（各自归一化到1023码值）。因此1020与1023的合并并非GLES单侧的中间纹理/FBO处理。`pattern-run.txt` SHA-256 `aeb09854a83fb9e1f05c0ce676e08710f188b92b244d2ccf758a1946cf98f4e8`；机器可读 `compare.json` SHA-256 `becb0396f5241f830bd39b40e8895565c7cbef245f8d75f2f153683a94a22314`，脚本断言每条记录同时存在两种取样、同PTS和无GL读错。

结论：在同一个 `0x325` AHB 上，P5 七个已知异常Y点和图案满码合并都跨 GLES/Vulkan 复现，排除了**只发生在 GLES raw shader/FBO 或不同次解码缓冲区**的解释。仍不能仅凭这项实验区分 MediaCodec 原生重构、Surface/HFBC→LINEAR、或 Mali 两种API共享的外部图像采样单元；第一层整数YUV仍未直接观察。十个有目的选点不证明全帧逐像素一致，也不证明P5完整颜色、HDR显示或4K50性能。下一步若继续根因拆分，应取得硬解原生整数检查点或能绕过共享外部采样单元的独立读数；产品性能方面另测直采libplacebo是否能去掉prepass。

设备实验后删除本轮 `/data/local/tmp` 探针和输入；测试应用保持10369、无进程，HDR探针属性0。没有安装APK、提交源码或修改播放器后端。
