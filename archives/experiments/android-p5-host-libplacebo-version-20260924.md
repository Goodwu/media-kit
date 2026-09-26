# P5 主机匹配手机 libplacebo 版本对照（2026-09-24）

**后续纠正**：本文件两张原尺寸PNG均使用mpv `video`截图，目标为sRGB而不是窗口BT.1886；版本间九点结论只适用于该sRGB截图。BT.1886 `window`模式重测7.360/7.365对手机MAE分别7.44/7.41、最大均35，版本仅改变九点中的1个分量1级，见`android-p5-screenshot-target-correction-20260924.md`。

疑点：手机P5原尺寸/PTS10 RPU后九点RGB相对主机仍MAE7.52、最大35个8-bit级；手机libplacebo7.365.0，既有Homebrew主机为7.360.1。为了测试版本影响，在`/tmp/media-kit-libplacebo-d4624`同一Android依赖源码`d4624cb`上隔离编译macOS Vulkan/libplacebo7.365.0，再用隔离mpv源码`32a164cc`链接该库。构建使用shaderc、Homebrew FFmpeg9.0.2、Vulkan registry，本地Jinja2仅安装于`/tmp/media-kit-host-pydeps`；未替换系统/Homebrew库。主机新mpv二进制`/tmp/media-kit-mpv-host-7365/mpv` SHA-256 `c29e92ef02e4fd17c81de8bab8a7ef632917b7a939bff7d48f1f07ba959371d3`，libplacebo动态库`/tmp/media-kit-host-7365/lib/libplacebo.365.dylib` SHA `d22071916673b83ba801599c547cafafe81b89e30a22d2cb616bd9c9501cdd3`；`mpv --version`报告libplacebo7.365.0，`otool -L`指向隔离库。

新主机同原片从头顺序解码到PTS10、3840×2160 Vulkan目标、BT.709/BT.1886、bt.2390、bilinear、dither=no、hdr-compute-peak=no等与既有主机轮同设置，IPC确认目标峰值203 nits及上述设置。8-bit RGB `video`截图`/tmp/media-kit-p5-mac-7365-pts10.png` SHA `86fa2b96826ee50660b090007b74549ffc706c61f8a64a98827743e198828301`，生成脚本`/tmp/media-kit-p5-match-host-7365.py`。该PNG与旧主机7.360.1截图SHA`f9bbdb400cd4634befae7b2578b1cd8fd275571678c1f2026532395c1d8444d8`不同、全图差异非空，但与手机比较的原尺寸九点RGB**27/27完全相同**，MAE仍7.52/最大35。因此libplacebo7.360→7.365及此主机构建组合**没有解释所测九点的残余差异**；全图差异说明不能据九点推断整幅图/其他场景完全等价。主机mpv版本/构建选项也不完全等同Homebrew，结果仅约束这组对照。

另测试主机`--fbo-format=rgba8`与`--cocoa-cb-10bit-context=no`：两轮IPC的窗口目标仍`bgr10a2`，输出PNG均与旧基线逐字节同SHA；这两个选项未建立真正8-bit Vulkan swapchain对照，不得称输出位深已匹配手机RGBA8。脚本分别`/tmp/media-kit-p5-match-host-rgba8.py`、`/tmp/media-kit-p5-match-host-no10.py`。本轮未操作手机；P5色彩真值、PQ HDR、长稳与真人可见验收仍开放。
