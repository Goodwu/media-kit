# P5→Texture SDR 默认入口与 Glass 全片补轮（2026-09-28）

目标：最终自建 arm64 JAR 不依赖 P5 调试属性，从测试页正常打开 Glass，按 P0 的真横屏 2560×1440 Texture→SDR 配置播到 EOS，并补记录片尾 VO/资源。手机 Huawei LYA-AL00，默认电池模式、自动亮度。每次设备轮结束均恢复原版 12492、四个 P5 调试属性为 0、自动亮度与熄屏；最后一次已现场核对。

## 默认入口门禁修正

12581 原本是约 28 秒真人观察包，12 秒截图有 Glass 实画面、`gpu-next`/`mediacodec`，但预置 `ANDROID_VO_SUMMARY_STOP` 在媒体约 23 秒停止播放器，不能用来补全片。12583 移除这个短时停止后，以属性 0 打开时被测试页旧 `requireAndroidP5RuntimePipeline` 拒绝；它仍要求 `p5_rpu_probe=2` 与 `p5_raw_yuv=1`，虽最终 JAR 已默认携带 RPU/raw YUV 路径。主库测试页策略/后端删去此过时的调试属性门禁；`MEDIA_KIT_ANDROID_P5_RPU_PIPELINE_BUILT=true` 编译门禁仍在，且必须由自建 JAR 来源另证。四个相关 Dart 文件分析无问题，策略测试 10 项通过。

12584 属性 0 已能打开 Glass，但误用默认 SurfaceProducer，实际 Surface 3840×2160；t8/t18 VO 为 103/308，不属于 2560×1440 的 P0 性能口径，发现后提前终止。12585 增加 `MEDIA_KIT_ANDROID_SURFACE_PRODUCER=false`、`MEDIA_KIT_ANDROID_TEXTURE_LAYOUT_SIZE=true`，实际输出经日志确认为 2560×1440，才纳入 P0 比较。三个无效/短时轮均未计为全片验收。

## 12585 有效轮

- 包 SHA-256 `03578f89f612ec2f199448b47479369d653b01ea91017f94743beb56ff973562`；版本码 12585；APK 仅含 arm64 native 库；本地 JAR SHA-256 `eac6514fd1b3409574f0b77014c9b29989e0d0868d40048cc199a822d94c660f`。Glass 源 `/data/local/tmp/media-kit-p5-glassblowing2-4k5994.mp4`。
- 四个 P5 调试属性为 0。日志见 `P5_DIRECT_RETIRE enabled=1`、`P5_SECTION_INIT direct=1 enabled=0 property=0`，并确认 `vo=gpu-next`、`hwdec-current=mediacodec`、目标 BT.709/BT.1886、`android-surface-size=2560x1440`。t12 截图可辨吹玻璃实画面。
- VO 累计掉帧：t8=9、t18=11、t28=11、t60=11、t90=11、t120=11、t150=21、t180=36；t180 媒体位置 176.482 秒，decoder 掉帧始终 0，热状态读数均为 1。t90→t180 增加 25，优于旧同片优化轮的增加 342；t180 的 36 也明显低于旧轮 EOS 516。`AUTO_COMPLETED completed=true` 在 t180 后约 1 秒出现，但未在 EOS 瞬间再取 `frame-drop-count`，36 不是精确 EOS 总数。
- PTS 174.991 附近一次 `acquireLatestImage failed after retry: -30001`、`Mapping hardware decoded surface failed`、`Failed rendering frame!`，随后到 EOS；与此前 Glass 尾段偶发故障同类，归 P3，不能称全片零渲染错误。VO 停止时 `P5_IMAGE_FINAL acquired=10450 deleted=10450 current_image=0 retired=0`，`P5_RETIRE_FINAL held_after=0`，随后 Player dispose 完成。VO 停止后的截图是黑屏，不是片尾画面证据；此前 12576 在片尾取得过正常 DV logo 截图。

证据：`artifacts/android-p5-glass-default-12581-12585/12585-logcat.txt.gz`、`artifacts/android-p5-glass-default-12581-12585/12585-t12.png`。仍缺最终版的真人动态画质确认；自动读回和截图不能代替该门禁。主库测试页修改在此确认后可单独提交，不应把 P1 隔离工作树的 PQ native 候选合入。
