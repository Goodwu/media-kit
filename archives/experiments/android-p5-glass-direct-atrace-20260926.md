# GlassBlowing2 4K59.94 P5 直采短时 trace（2026-09-26）

目标是定位直采 `vo render` wall 约17–18ms、GPU render-only时间戳约1ms时，阻塞是否仍落在先前24fps packed10路径的 `eglSwapBuffers/queueBuffer`。使用用户指定GlassBlowing2 P5输入（SHA-256 `afb24b77733a3ca9071f0cfea0d0f7871670a7b6119eb44a314cba974541477c`），同机LYA-AL00、直采诊断APK8340，`p5_raw_yuv=1,p5_direct_yuv=1,p5_rpu_probe=2`，其余性能探针关闭。日志确认 `ANDROID_HDR_OPEN` 后执行10秒 `atrace -z -b 8192 -t 10 -a com.example.media_kit_test gfx view sched freq sync video`。本轮t60 VO丢帧257、媒体时间46.046秒；诊断轮与无atrace正式性能轮不能直接比较。

压缩trace保存于 `artifacts/android-p5-glass-direct-atrace/atrace-compressed-20260926.txt`（SHA-256 `f7ef41507f211e8c7c7ab786b780fdf071ec8f9d844f265471d8d519872a3388`），原始logcat SHA-256 `dac5319a87c42498b53a98ea175a89f269664158e2940fa13a8e5d496d891e44`，关键日志及解析输出同目录。可重放：

`python3 archives/experiments/tools/p5_atrace_slice_summary.py archives/experiments/artifacts/android-p5-glass-direct-atrace/atrace-compressed-20260926.txt --pid 29920 --tid 30190`

VO线程516次完整调用：`eglSwapBuffers`中位0.602ms/P95 0.950ms，嵌套`queueBuffer`中位0.260ms/P95 0.355ms，嵌套`waitForever`中位0.014ms/P95 0.019ms；独立`dequeueBuffer`中位0.107ms。Flutter raster `updateTexImage` 498次、开始间隔中位16.449ms，同名SurfaceTexture队列计数出现0/1/2。此轮没有重现先前Sol Levante 24fps packed10 trace在`queueBuffer/waitForever`中位48ms的阻塞。**因此不能把当前59.94fps直采VO wall大头直接归因于swap/queueBuffer。**

trace中516次短`waitForever`结束均可在前1ms找到Mali fence signal，但这不证明等待对象ID逐个对应；与旧长等待trace的关联强度和意义不同。这里的trace没有对`pl_render_image_mix`、`glFinish`、EGLImage导入逐段打点，故它们仍是下一步待区分的候选。直采当前固定复用一个外部纹理并在unmap执行`glFinish`；已有`raw_retire`只在非直采prepass启用，不能简单改属性套用，因为直采若退役该纹理还需更新libplacebo包装纹理并保证帧生命周期安全。优先加只读范围打点或trace标记，再决定是否实施安全延迟释放。

实验后恢复原4K50 P5文件SHA-256 `328cae5c78ba9b8e579e7352edcfb8f3e9e0c0670849fc8773a8b028d2d1d03e`、APK10369、P5诊断属性0；未提交。
