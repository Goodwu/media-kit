# P5 产品候选普通 SDR 回退与 Mystery Box 全片（12567–12569）

隔离 mpv `91554aa` 在普通 OES 路径遇到没有新 ImageReader callback 的重复绘制时，沿用上游映射器的成功返回语义；P5 直接 YUV 路径仍严格报告取图失败。arm64 `libmpv.so` 编译链接成功，替换到自建 arm64 JAR，JAR SHA-256 `cc6d651935031091c57f9f40098b1164c4e84941e02e4919ead7709457262491`。FFmpeg 为 Goodwu fork `fff3ee7`，libplacebo 为 Goodwu fork `c9fd879`。mpv 修订已推送至 Goodwu/mpv `feature/android-p5-sdr-direct-yuv`。

12567 普通 SDR 本地片短轮：预建横屏全屏 Texture，自动亮度。实际屏幕读回为企鹅画面，媒体时间 5.297 秒时 VO/解码掉帧均 0、声画同步误差约 0.000104 秒；日志未见 `acquireLatestImage failed` 或 `Failed rendering frame`。前一次 12566 用旧 JAR 有一次无新 callback 的启动报错。12567 首次启动未及时点击，自动停止后截图为黑色；证据使用重新启动、及时点击后的第二轮。该轮未完成正常退出资源计数，不能单独证明普通 SDR 资源闭环。

12568 是一次**无效 P5 性能对照**：构建漏传 `gpu-next`、`mediacodec` 及 Texture 2560 限宽，实际为 `vo=gpu`、`hwdec-current=mediacodec-copy`、3840×2160；虽到 EOS、VO85、decoder0，也不计入 P0 复测。

12569 修正测试入口参数，APK SHA-256 `ca8c1f12d252a629abe9198cf63ca4fb5f787d5ecc200eb354f804e389bb4b0d`，versionCode 12569；本地 Mystery Box P5、预建横屏全屏 Texture、实际 `setSurfaceSize 2560 1440`、`vo=gpu-next`、`hwdec-current=mediacodec`、默认电池模式、自动亮度，四项 P5 调试属性保持 0。媒体时间 5.589/25.592/57.591/87.588 秒时 VO 均为 2、decoder 均为 0；`AUTO_COMPLETED completed=true`，t120 `eof-reached=yes`、媒体时间 98.899 秒，VO2、decoder0。GPU 1Hz 共 112 样本，中位 415MHz（415:97、332:13、139:2）。全片日志没有 `acquireLatestImage failed` 或 `Failed rendering frame`。正常 `vo=null` 后 `P5_RETIRE_FINAL maps=5929 reaped=5928 held_after=0`、`P5_IMAGE_FINAL acquired=5928 deleted=5928 retired=0 empty_acquires=0`，Player dispose 完成。旧同片未优化全片 VO54、GPU 中位586MHz；此前同配置的旧候选12563全片 VO11、GPU中位415MHz。VO 差异是不同运行轮次，不应归因于单行 OES 修复。

证据在 `artifacts/android-p5-product-12567-12569/`。每次实机实验后已恢复原 versionCode 12492、P5 调试属性 0、自动亮度并熄屏。12569 到 EOS 和资源闭环成立，但仍缺同版 Glass 全片、非 P5 HDR 回退、seek/重入及真人动态观感；本记录不宣称 P0 全部验收完成。
