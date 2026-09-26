# GlassBlowing2 直采 CPU/等待分段（2026-09-26）

目的：在4K59.94 P5直采路径中分清先前测到的VO绘制wall约17–18ms究竟由GPU算术、Surface交换、AHB操作还是同步等待构成。已有同片trace显示`eglSwapBuffers`中位0.602ms且`queueBuffer`内部wait中位0.014ms；已有GPU render-only时间戳中位约1.048ms（粒度约1.048ms），但这些观测不能直接解释VO绘制wall。

在带RPU的隔离mpv中加入默认关闭的`debug.media_kit.p5_section_perf=1`，在`pl_render_image_mix`及其外部纹理mapper测每250次的wall与线程CPU累计值。改动仅在隔离源码`/tmp/media-kit-mpv-clean-2194`，相对本轮修改前源码的补丁为`artifacts/android-p5-glass-section-vo.patch`和`artifacts/android-p5-glass-section-mapper.patch`。arm64构建链接、APK签名验证通过；有效APK SHA-256 `ed7c7beec77db7031f2efe6ac216e201de5a246063841b3b724bdbed500975b1`。只替换原诊断包中的libmpv，使用相同GlassBlowing2文件（SHA-256 `afb24b77733a3ca9071f0cfea0d0f7871670a7b6119eb44a314cba974541477c`），`p5_raw_yuv=1,p5_direct_yuv=1,p5_rpu_probe=2`，关闭其它阶段/GPU计时。结果与原始log SHA-256 `3850e5d0d6460831185237970a60eb7379dfb60d8c79c03a8ef557efdc74824d`见`artifacts/android-p5-glass-section-summary.json`；t60 VO累计丢帧314、解码丢帧0、温控1，不能与无探针计数作精确性能差值。

稳定窗口14个VO批次、28个mapper批次，**每250次VO渲染大致对应500次mapper生命周期**。各批次中位按单次折算：

| 调用范围 | wall | 线程CPU | 换算到一次VO渲染的wall |
| --- | ---: | ---: | ---: |
| `pl_render_image_mix` | 16.666ms | 4.664ms | 16.666ms |
| mapper释放前`glFinish` | 5.578ms/次 | 0.100ms/次 | 约11.156ms |
| `eglCreateImageKHR` | 1.461ms/次 | 1.272ms/次 | 约2.922ms |
| `glEGLImageTargetTexture2DOES` | 0.416ms/次 | 0.384ms/次 | 约0.832ms |
| `AImageReader_acquireLatestImage`循环 | 0.128ms/次 | 0.033ms/次 | 约0.256ms |

`glFinish`耗时几乎全为线程未执行CPU的时间，且按生命周期折算约占render wall的三分之二；EGLImage创建则主要消耗CPU时间。上述各项来自相邻批次中位并非逐帧配对，不能精确相加或声称剩余差额均属于某个shader。另一方面，它们与render wall/CPU的量级能够相互解释；**当前最值得优化的是每帧约两次的同步释放以及EGLImage反复创建，而不是先改DV色彩shader算术。**

安全优化候选：为直采的每个外部AHB保留独立GL纹理及libplacebo包装，在最后一次采样后建立GPU fence，延迟到fence完成再释放AImage/EGLImage/纹理；必须限制在途图像数、处理seek/close和失败回退，并与当前每帧`glFinish`作同片A/B。已有prepass路径的retire试验曾把等待移到`queueBuffer`且未改善吞吐，因此直采也不能仅凭少一次显式等待就判成功。重复创建EGLImage的缓存或复用需先证明AHB身份和生产者生命周期，不能按表面指针贸然缓存。颜色同帧误差、真实显示节拍和HDR呈现门禁仍独立开放。

曾尝试Android NDK `ATrace_beginSection`标记，先后在播放后和系统trace先启/应用冷启动两种条件下均未录到自定义标记，因此未用那两份trace作分段结论；最终有效证据来自上述壁钟/线程CPU汇总。实验后恢复原4K50文件SHA-256 `328cae5c78ba9b8e579e7352edcfb8f3e9e0c0670849fc8773a8b028d2d1d03e`、APK10369、诊断属性0，无应用进程；未提交。
