# P5 Glass Texture SDR 片尾紫色视频区域，12492

## Current State

2026-09-27，华为 LYA-AL00/API29、自动亮度1，12492最终测试APK SHA-256 `39493d184b48e055a2c61babe97047c2865b02f9986aaf7399872c3435ace706`，正确arm64 JAR SHA-256 `5b9495f72893b8b62bb9085c67c9e87707b04f5910d3f09e9a79df82efcfd2e2`。指定 Glass P5文件SHA-256 `afb24b77733a3ca9071f0cfea0d0f7871670a7b6119eb44a314cba974541477c`。默认 SurfaceProducer/Texture SDR，竖屏测试页，原片头0播放。没有最高亮度或真全屏。

手机截图在设备epoch1790470692和0793均显示不同的视频画面；原生AImage计数至4250时媒体PTS164.765秒。epoch1790470841视频区域却为均匀 RGB(128,0,255) 紫色，页面其他部分正常。源文件`ffprobe`的视频流时长175.008167秒，容器时长178.112秒；该截图在播放器media_opened约1790470661之后约180秒，位于视频流标称时长之后；实际EOS事件未捕获。主机 FFmpeg 对末尾可解码帧缩小取样均值RGB约(5.9,3.1,24.2)、中心像素(45,37,64)，紫色像素占比0。因此紫色不是片源末帧内容；可能是播放器/Texture结束后的占位或错误色，当前没有EOS事件与Surface释放同刻日志，原因未定。

随后按Back可完成VideoOutput/Player释放，Activity退出；同进程重入的新视频再次出图，无SIGSEGV。该现象与受控退出屏障是否生效分开，不能因为退出顺序正确就认为片尾显示正确。隔离mpv源码`video/out/vo_gpu_next.c`的无效渲染分支会用RGBA(0.5,0,1,1)紫色清空目标，与截图RGB(128,0,255)吻合；但该隔离源码未能重建为与现用JAR逐字节相同的库，因此只能列为强线索，不能据此断言具体分支或原因。还需在同包重复到EOS，记录mpv end-file事件、播放器状态、Texture/Surface生命周期及前后逐帧屏幕内容；对照正常SDR/HDR10素材与不同输出拓扑，确认预期应清黑还是保留最后一帧，再决定修复位置。

原始手机截图见`artifacts/android-auto-player-exit-12492-long/frame-early.png`（SHA-256 `e64b24a9da7ed8e3bc9130279ca140dab1736ce19ab0ed08803b06efba1d5dc5`）、`frame-late.png`（`04e723be578153c3e37c67a4cb54bd0050b66fd85f9be1fc9ae62c0ecbfa0677`）、`frame-after-nominal-duration.png`（`2eef2c4a68832a527b9c82d09128544235e41c24253901270010076798c207df`）、`frame-reentry.png`（`2909c5a65876c63c7095bd505eaef460540aa690bd8eb18373afca427a4bf79b`）。同目录日志SHA-256 `1b36e03af75fd117d99f199ae101a76d7bc56bb9d4c235a21df84d723e907163`。
