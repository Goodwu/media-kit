# 官方 4K P5 离屏对照的同步边界（2026-09-25）

复用 11042 同一 APK/Sol Levante 4K P5、MediaCodec/RPU/raw packed10 与 1440 宽 Texture 设置，另启已有的 `debug.media_kit.p5_offscreen=1`、关闭额外像素读取；只做短时诊断，不作可见画面或颜色验收。原以为离屏模式保留渲染、跳过窗口 swap 可较干净地测试 Surface 消费背压；源码复核及运行证明该模式每帧在 `pl_render_image_mix` 后强制 `pl_gpu_finish(gpu)`，因此它改变了 GPU 完成时机，**不能当成仅移除 Surface 消费的 A/B**。

运行日志确认离屏目标有效（`P5_OFFSCREEN valid=1`）。帧16–20 的强制完成等待约38–58ms，第50/100/150/200帧分别为116.660/86.277/87.249/51.117ms。结束前稳定 VO queued465/draw227/deadline_drop238、draw累计18720ms、flip0ms；RPU在主实例累计输出/匹配450、错误0。此结果说明即使没有窗口 swap，该模式也会在强制 GPU 完成点等待并掉帧；不能把等待全部归因 GPU 算术，更不能定量减去正常 EGL 耗时，因为 FBO/提交/同步语义均不同。与此前 `p5_preswap_finish` 把等待移到 EGL 前的结果一致，下一步不再用该离屏开关判 Surface 背压；应在正常窗口路径做不会强制串行的生产者/消费者时间线或系统图形跟踪。

日志 `archives/experiments/artifacts/android-p5-offscreen-control-11042/media-kit-p5-offscreen-control-11042-logcat.txt` SHA-256 `dbeabb89cef8765066449720b9fb136e749306b782d0d2e86ef6137f17eb77d2`。设备媒体已移除，诊断属性清零，APK恢复官方10369并强停。未提交。
