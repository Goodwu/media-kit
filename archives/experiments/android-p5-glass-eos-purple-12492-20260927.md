# P5 Glass Texture SDR 片尾紫色视频区域，12492

## Current State

2026-09-27，华为 LYA-AL00/API29、自动亮度1，12492最终测试APK SHA-256 `39493d184b48e055a2c61babe97047c2865b02f9986aaf7399872c3435ace706`，正确arm64 JAR SHA-256 `5b9495f72893b8b62bb9085c67c9e87707b04f5910d3f09e9a79df82efcfd2e2`。指定 Glass P5文件SHA-256 `afb24b77733a3ca9071f0cfea0d0f7871670a7b6119eb44a314cba974541477c`。默认 SurfaceProducer/Texture SDR，竖屏测试页，原片头0播放。没有最高亮度或真全屏。

手机截图在设备epoch1790470692和0793均显示不同的视频画面；原生AImage计数至4250时媒体PTS164.765秒。epoch1790470841视频区域却为均匀 RGB(128,0,255) 紫色，页面其他部分正常。源文件`ffprobe`的视频流时长175.008167秒，容器时长178.112秒；该截图在播放器media_opened约1790470661之后约180秒，位于视频流标称时长之后；实际EOS事件未捕获。主机 FFmpeg 对末尾可解码帧缩小取样均值RGB约(5.9,3.1,24.2)、中心像素(45,37,64)，紫色像素占比0。因此紫色不是片源末帧内容。

从设备仍保留的同次 logcat 补取到直接前因：epoch1790470839.860，PID5729 在媒体PTS174.874700秒报`acquireLatestImage failed after retry: -30001`（`callbacks=4425 empty_acquires=30 notification_pending=0 retired=0 maps=4428`）；紧接着报`Mapping hardware decoded surface failed.`和`Failed rendering frame!`。紫色截图在失败后约1.14秒。这把可见紫色与视频流末端的取图/渲染失败关联起来，不能再简单描述为正常EOS占位；但尚无同刻`end-file`事件、帧/Buffer身份和Texture生命周期，不能断言失败由重复释放同一Buffer、EOS或具体清屏分支引起。原始三行日志在`artifacts/android-p5-glass-eos-purple-12492/render-error-logcat.txt`，SHA-256 `13e1e6a2706d973a62f529d9b773c6740d61746a9bfdfdcd09b7610cafe919b2`。

只读源码复核把“同一解码帧重绘时再次release已消费的MediaCodec buffer”列为优先验证的候选：隔离实现的AImageReader mapper每次map均release buffer；旧4K50实验曾逐指针证实同类重复release不会产生新callback，旧同帧缓存可消除该源起播和EOS的`-30001`。但旧缓存与当前延退路径互斥；12492未记录失败帧Buffer身份，不能直接启用旧开关或宣称同因。下一轮只在失败时输出尾段map环形记录，关联reader代次、源帧/codec buffer身份、PTS、release返回、AImage时间戳与callback序号。确认后再设计兼容延退的帧所有权，不以延长retry或单纯改紫色作为根因修复。旧实验见`android-p5-glass-direct-retire-20260926.md`。

随后按Back可完成VideoOutput/Player释放，Activity退出；同进程重入的新视频再次出图，无SIGSEGV。该现象与受控退出屏障是否生效分开，不能因为退出顺序正确就认为片尾显示正确。隔离mpv源码`video/out/vo_gpu_next.c`的无效渲染分支会用RGBA(0.5,0,1,1)紫色清空目标，与截图RGB(128,0,255)吻合；但该隔离源码未能重建为与现用JAR逐字节相同的库，因此只能列为强线索，不能据此断言具体分支或原因。下一步围绕PTS174.874700秒重现，记录每次map的媒体PTS、Buffer身份、Surface回调、`end-file`事件及失败前后逐帧屏幕内容；对照正常SDR/HDR10素材与不同输出拓扑，确认预期应清黑还是保留最后一帧，再决定修复位置。

原始手机截图见`artifacts/android-auto-player-exit-12492-long/frame-early.png`（SHA-256 `e64b24a9da7ed8e3bc9130279ca140dab1736ce19ab0ed08803b06efba1d5dc5`）、`frame-late.png`（`04e723be578153c3e37c67a4cb54bd0050b66fd85f9be1fc9ae62c0ecbfa0677`）、`frame-after-nominal-duration.png`（`2eef2c4a68832a527b9c82d09128544235e41c24253901270010076798c207df`）、`frame-reentry.png`（`2909c5a65876c63c7095bd505eaef460540aa690bd8eb18373afca427a4bf79b`）。同目录日志SHA-256 `1b36e03af75fd117d99f199ae101a76d7bc56bb9d4c235a21df84d723e907163`。
