# 官方 4K P5 的 EGL swap 分段复测（2026-09-25）

复用 11042 APK（SHA-256 `2e617b98b63b19ad570d7aee9f4dd81ff7eccd1c03a12b5acaed90cacac74ce8`）及同一 Dolby 官方 Sol Levante 4K/24fps P5、1440 宽 Texture SDR、MediaCodec/raw packed10/RPU 路径。本轮只另启已有默认关闭的 `debug.media_kit.p5_swap_probe=1`，同时保留 `p5_vo_summary=1`；`p5_preswap_finish=0`，没有强制 `glFinish`。`P5_SWAP_SPLIT` 每50个实际 swap 记录一次 EGL 调用和其后 mpv fence 循环的 CPU 墙钟。启动初期有两次重开/flush，以下用最后稳定 VO 的计数，勿将其与其他实例相加。

这一轮从开始即慢，未重现 11042 原轮约50秒才发生的转折。有效稳定 VO 最终 queued1937/draw1448/deadline_drop489/other_drop0、wait累计1ms、flip累计71702ms；RPU该实例输出/匹配1938、错误0。第50–300实际swap之间6个稀疏样本 `eglSwapBuffers` 中位49.0065ms、范围43.860–49.573ms；第500帧之后20个样本中位48.7385ms、范围46.554–79.586ms。上述26个样本中，EGL之后的mpv fence循环最多4µs，等待fence数均为0。因此**在本轮的`flip_page`长阻塞主要落在 `eglSwapBuffers` 调用里**，不在其后的mpv fence循环。EGL调用可等待先前GPU命令、驱动/BufferQueue/消费者等，CPU墙钟不能直接解释为GPU shader执行时间或显示扫描时间；稀疏探针和热启动也不构成无诊断性能门禁。

完整日志 `archives/experiments/artifacts/android-p5-egl-split-11042/media-kit-p5-egl-split-11042-logcat.txt` SHA-256 `4dd43e6a1b0a0974c6de3a6f56973ef54e7a25d4d470cfb2a8312d810a145516`。下一步应对 EGL 内部可能的生产者/消费者背压做同条件对照，并记录起始热/频率状态；避免再重复证实 mpv fence 为零。实验后删除设备媒体、属性清零、恢复官方10369并强停；未提交。
