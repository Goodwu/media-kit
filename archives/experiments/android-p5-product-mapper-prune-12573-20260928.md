# P5 映射器可选缓存与高频诊断清理短轮（12573）

以 Goodwu/mpv `91554aa` 为基线，在隔离源码中删除默认不用的 `p5_same_frame_cache`、`p5_egl_cache` 分支以及高频 `P5_RETIRE`、`P5_IMAGE_COUNT`、首帧 GL 导入日志。默认 P5 仍按同一 MediaCodec buffer+PTS 从退休队列取回纹理，普通 OES 仍沿用无新 callback 时保留旧纹理的返回语义。V1 审核曾发现删除日志时 `raw_logged` 不再递增，会让非 direct 实验 FBO 路径逐帧打印；已改为最多递增到6，审核复核未发现新的资源所有权或回调退出阻断。`git diff --check`、NDK27 arm64 `libmpv.so` 编译链接通过；源码已提交并推送 Goodwu/mpv `feature/android-p5-sdr-direct-yuv` 的 `33a212e`。旧 Glass 日志门禁的 `--cache` 改为仅在历史诊断需要时显式指定。

新 `libmpv.so` SHA-256 `85237a8bd371ccab8535ec0bf5cd07bd82d630ed15f59ff1be3e7f87a3f6e2a0`；自建 arm64 JAR SHA-256 `3dd2d65d1ece695d69d41e3506699365f5dca8c436e7ede3e5264131aa16d714`。12573 APK SHA-256 `38722d914796543862e35e18e2d920aa0c50cda00b049b5fa1fa229b9c8eae01`，本地 Mystery Box P5、预建横屏全屏 Texture、2560×1440、SDR目标。截图实际沙滩画面，t8 VO3、decoder0，全量日志没有 `acquireLatestImage failed` 或 `Failed rendering frame`。正常 `vo=null` 后 `P5_RETIRE_FINAL maps=1513 reaped=1513 held_after=0`、`P5_IMAGE_FINAL acquired=1513 deleted=1513 retired=0 empty_acquires=0`，Player dispose 完成。设备恢复原12492、自动亮度和熄屏。

证据在 `artifacts/android-p5-product-12573-prune/`。首次Gradle打包因磁盘空间不足失败；清理旧临时实验二进制后重试成功。此轮只播约25秒，证明精简版基本出画与退出资源闭环；不能用它替代12569/12570的全片性能。映射器仍保留 property-gated 原始YUV FBO/PACK10、性能计时、时间线与RPU哈希探针；后续需继续收敛，并对最终源码重跑全片、非P5回退与seek/重入。
