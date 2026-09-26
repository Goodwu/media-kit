# P5 原尺寸 RPU 后离屏像素对照（2026-09-24）

**后续纠正**：本文件主机原尺寸PNG使用`video`截图模式，该模式在mpv源码中强制sRGB目标，并非手机BT.1886同目标；MAE7.52/最大35仅是跨目标诊断。真正BT.1886 `window`截图重测为MAE7.41/最大35，见`android-p5-screenshot-target-correction-20260924.md`。

目标：响应“缩放可能导致跨端像素差异”，在同一 PTS、同一源尺寸比较完整 Dolby Vision RPU 后的 SDR 图像，不将 raw YUV 比较误当最终色彩验收。固定源 `/tmp/media-kit-DV-P5.mp4`，Huawei LYA-AL00 `3EP7N18C28016072`，MediaCodec/逐帧 RPU/packed10 + `1020/1023`/gpu-next；诊断轮不计性能与可见播放验收。

隔离 mpv 增加默认关闭的 `debug.media_kit.p5_offscreen_native=1`：与 `p5_offscreen=1` 合用，等 3840×2160 源帧出现再建立 3840×2160 `rgba8` host-readable 离屏目标，用整幅目标 crop 渲染，在 `pl_render_image_mix` 成功后 `pl_tex_download` 九点。初版8360在视频前以1×1窗口创建目标，无效；8361虽等待源帧，但预热窗口帧未提交 swapchain，日志报 frame already in progress，无效；8362正确提交预热帧后因窗口从1×1缩放而触发旧离屏尺寸保护，无效；8363忽略原尺寸诊断下的窗口尺寸变化，稳定离屏渲染但 PTS10 严格探针未命中；8364放宽为10秒后首个实际渲染帧，实际命中**PTS10.000**。8360–8363不作像素比较证据。

8364手机离屏日志：`off_w=3840,off_h=2160,off_fmt=rgba8`，目标crop `0,0,3840,2160`，PTS10源 RPU side data `size=206,hash=907c8b42`；最终目标RGB/BT.709/BT.1886、`min_luma=max_luma=0`（未显式峰值）、无ICC/LUT。九点每点`download_ok=1,gl_error=0`，按OpenGL左下原点坐标顺序 (960/1920/2880, 540/1080/1620) 的RGB为 `(106,135,186),(114,144,197),(119,147,197),(63,70,99),(116,114,116),(35,44,67),(104,114,157),(106,117,158),(107,118,155)`。日志在启动附近有一次 `Failed rendering frame!` 后继续正常处理；因此本轮仅作为诊断，不作长稳结论。

主机 Homebrew mpv0.41/libplacebo7.360.1同原片从头顺序解码至PTS10，`vo=gpu-next,gpu-context=macvk,target-prim=bt.709,target-trc=bt.1886,target-colorspace-hint=auto,tone-mapping=bt.2390,scale=dscale=bilinear,dither=no,correct-downscaling=no,linear-downscaling=no,sigmoid-upscaling=no,hdr-compute-peak=no,screenshot-high-bit-depth=no`，IPC确认3840×2160目标BT.709/BT.1886、峰值203 nits；`screenshot-to-file ... video` 得3840×2160 8-bit RGB PNG `/tmp/media-kit-p5-mac-native-options-pts10.png` SHA-256 `f9bbdb400cd4634befae7b2578b1cd8fd275571678c1f2026532395c1d8444d8`，脚本`/tmp/media-kit-p5-match-host-native.py`。按 `y_png=2159-y_gl` 对齐九点，主机RGB为 `(71,138,191),(79,147,202),(87,150,202),(55,71,102),(118,114,116),(26,44,69),(92,115,161),(94,118,162),(95,120,159)`。RGB27项对手机平均绝对差**7.52**个8-bit级，最大**35**级；先前同设置1440×810对照为7.78/35。去除缩放几乎不改变差异，反证“缩放是主要色差来源”的假设。仍不能宣称手机或主机的最终颜色正确/错误，因为libplacebo版本、DV解析后表示、目标峰值内部默认及GPU实现未对齐，主机PNG也不是光学真值。

8364 APK `/tmp/media-kit-p5-native-postrpu-8364.apk` SHA-256 `3dc153cb0c0a7411a835084d3fe05145d2a9e643cfc67baa0dbbf7121a7bc0ca`；日志 `/tmp/media-kit-p5-native-postrpu-8364-logcat.txt` SHA-256 `4faa7d3815b3c7ad4e63f740f04db595c46b9a9afdf25c57a7bd0f497774ca65`；整合补丁 `android-p5-native-postrpu-8364-integrated-mpv-20260924.patch` SHA-256 `f2e8e35e42bbfe222977f9ad77ad8b3e8c5189d4bf7518c2f0d375e1eec1b3ad`。arm64编译、APK签名/验签、隔离mpv diff-check通过。设备实验后强停，14项P5诊断属性逐项回读全0，进程未运行；保留8364包。

下一步：核对两端解析后的 `AVDOVIMetadata`/libplacebo帧表示、目标峰值实际归一化和版本差。若要排除RGBA8最终量化，另做相同色彩目标的高精度离屏对照；不得用本轮九点替代P5全片颜色、PQ HDR或真人可见验收。
