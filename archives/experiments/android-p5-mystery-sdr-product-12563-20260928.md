# P5→Texture SDR 清洁依赖候选全片（12563）

从 Goodwu/mpv `a81978b` 隔离分支接入外部YUV、直接采样/退休及 SDR 直接线性解码策略；从 FFmpeg `f46e514` 隔离分支保留 Android HEVC Profile5 逐帧RPU绑定，移除阶段计数和属性开关。mpv arm64链接与 FFmpeg 单文件arm64编译通过；APK SHA-256 `0f19739860b4ebf6ee2fccf348bc63c50a1d80f18d061cdae137ee6fac2088c2`，自建arm64 JAR SHA-256 `d3009160d672a98a0d7a6c2481bb4b7450a0e3d3ad34a1675d06e65f21fdc912`。APK只含arm64 `libmpv.so`。四个P5调试属性均0；自动亮度，默认电池模式。

测试页预建横屏全屏Texture，普通命名本地 Mystery Box P5 源；`setSurfaceSize 2560 1440`。截图有实际沙滩画面，片尾截图为素材正常黑底尾卡。媒体时间5.489/15.482/47.481/77.477/98.944秒时累计VO为10/10/11/11/11，解码掉帧均0；`AUTO_COMPLETED completed=true`，t120 `eof-reached=yes`。GPU 1Hz共85样本，中位415MHz，84个415MHz、1个332MHz；采样晚于播放起点约41秒，不能代表启动窗口。旧同片未优化12546全片VO54、GPU中位586MHz；12561实验默认路径VO23、GPU中位415MHz。12563较旧未优化基准低43帧，且该轮无后半片VO增加。

退出补轮：同一APK横屏短播约9秒后按返回键，`P5_RETIRE_FINAL maps=566 reaped=564 held_before=1 held_after=0 waits=3 fallbacks=0 current_image=0 current_egl=0`，`P5_IMAGE_FINAL acquired=564 deleted=564 retired=0`，随后 `ANDROID_AUTO_PLAYER exit player disposed`。这证明本轮mapper持有的AImage/退休队列闭合；日志没有FFmpeg RPU终结汇总，不能宣称整个解码生命周期闭合。

限制：mpv候选AImageReader仍包含大量实验诊断代码，libplacebo构建仍含一次性诊断探针；未证明清洁产品实现和非P5/非SDR回退。PTS0首图像导入成功后重复映射，两次无新AImage报 `-30001` 和render失败，之后连续播放；无法归因于1×1。尚缺Glass全片同路径、完整资源终结统计、真人动态画质及颜色验收。相较基准热态与日志条件不同，不能作严格因果量化。设备结束后恢复12492、四属性0、自动亮度和熄屏。

证据在 `artifacts/android-p5-mystery-sdr-product-12563/`，包括全量/退出日志gzip、GPU NDJSON、全屏中段及EOS截图和两份隔离候选源码补丁。源码已分别提交并推送到 Goodwu/FFmpeg `feature/android-mediacodec-p5-rpu` (`fff3ee7`) 与 Goodwu/mpv `feature/android-p5-sdr-direct-yuv` (`6758565`)；mpv提交明确是仍需收敛诊断的候选。Goodwu/libplacebo此前的 `optimize/dovi-linear-decode` 在 `c9fd879`。
