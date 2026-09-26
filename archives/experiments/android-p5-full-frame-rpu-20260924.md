# P5 RPU 后原尺寸整帧对照（2026-09-24）

8367 隔离诊断包在华为 LYA-AL00 上以固定 P5、MediaCodec、packed10、`1020/1023` 尺度校正、逐帧 RPU 和 3840×2160 RGBA8/BT.709/BT.1886 离屏目标播放。默认关闭的 `debug.media_kit.p5_post_rpu_full_dump=1` 在 PTS10.020 对正常 `pl_render_image_mix` 的目标 `pl_tex_download`，日志报告 33,177,600 字节读回并写出；九个读回点与整帧 RGBA 原始文件对应。手机文件 `/tmp/media-kit-p5-phone-full-8367-pts1002.rgba` SHA-256 `04e91fd2a66b0dff6bd1386ba0ef5b585b9078ba875a7d9579a624db435ab841`；包 `/tmp/media-kit-p5-full-dump-8367.apk` SHA `b4c9047ae03de2b0cc77c294e1f18f925fd9773c2f8406655fd6316dd2603719`，日志 `/tmp/media-kit-p5-full-dump-8367-logcat.txt` SHA `72ff0bceaad9059c1a35590c1ee958f21ef415cbb9017ea539dfbd41e71cb213`；隔离 mpv 源码补丁 `android-p5-full-frame-8367-mpv.patch` SHA `30ea2760d3dfe93699668b83c651379c4dc544282a1979e7a883318db0991f3a`，`git diff --check` 通过。

主机同源 libplacebo 7.365 的 mpv 从头解码到 PTS10.020，以 `window` 截图保留 BT.709/BT.1886 目标，3840×2160 PNG `/tmp/media-kit-p5-mac-7365-window-pts1002.png` SHA `4ff6b4f8ee1bea08230805fa7896cddad0bf227516117d3a6e72fbef6085a453`，脚本 `/tmp/media-kit-p5-match-host-7365-window-1002.py`。比较脚本 `/tmp/media-kit-p5-full-compare-1002.py` 将 OpenGL 原始行序上下翻转，与 PNG 对齐；手机九点读回与文件九点 27/27 分量相同。±2 像素水平/垂直平移中零偏移的全通道 MAE 最小（中心裁剪 9.2721/255）；不是简单整帧位置错位。

对齐后全图手机减主机 RGB 平均偏差为 `(+21.704,-1.496,-3.965)`/255，各通道 MAE `(22.099,1.644,4.085)`，绝对差 P95 `(39,3,5)`；顶部四分之一红色均差 `+14.161`，底部四分之一 `+33.888`。九点比较低估了全图红色差异。这些数据提示偏差有空间/亮度依赖，且主要在红色通道；不能仅凭跨 GPU、不同输入采样/窗口截图与 RGBA8 离屏下载判定哪一端颜色正确。诊断轮的同步整帧下载不能用于播放性能或真人画质验收；PQ HDR 出口仍未验证。

供人工查看的缩放并排图 `android-p5-full-frame-compare-20260924.png` 展示手机、主机和每通道绝对差放大四倍，SHA-256 `afe4ff4f4c77fb38a6d1ef326bdb745ec1524f5c643c6fd51b6bd5bb9137a822`。图仅用于观察偏差，数值结论由原尺寸原始文件计算。

另用主机 `--vf=format:fmt=yuv444p10` 实测 `video-out-params.pixelformat=yuv444p10`，Dolby Vision/full/BT.2020/PQ 元数据保留。主机同目标 PTS10 九点与未加滤镜 27/27 相同，但整帧 PNG 有差异；这仅说明主机过滤器确实形成 4:4:4 输入且九点未变化，不等于手机硬件外部 YUV sampler 的色度重建。主机 4:4:4 PNG `/tmp/media-kit-p5-mac-7365-yuv444-window-pts10.png` SHA `667d8a43c93d5c1643e844486a5f2ef47a7d104fe0feaa8a004341cd930e7fda`。

本轮结束已强停测试应用并逐项回读 16 个 P5 `debug.media_kit` 诊断属性均为 0，`pidof` 无进程；包留设备以便复现。下一步先检查主机窗口截图与手机离屏目标的输出编码/红色转换阶段，再用独立参考或同后端对照确定色彩真值；不把当前偏差直接归因缩放或手机错误。
