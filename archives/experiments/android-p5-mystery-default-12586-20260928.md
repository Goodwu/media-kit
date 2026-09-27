# P5→Texture SDR 默认入口 Mystery Box 全片复测 12586（2026-09-28）

在 12585 Glass 属性0、真横屏2560×1440全片补轮后，按 P0 验收再次用 Mystery Box 复测同一默认入口，和该片自身未优化12546全片基准比较。手机 Huawei LYA-AL00，默认电池模式、自动亮度；六个旧 P5 调试属性中的四项标准探针和 `p5_rpu_probe`/`p5_raw_yuv` 均为0。测试后原版12492、自动亮度与熄屏现场恢复。

- APK 12586 SHA-256 `821e9a8dd3c95d7b8cd5356f2ef9194d10d2d4be154506313fbba2056712be1d`；仅 arm64 native 库。自建 JAR SHA-256 `eac6514fd1b3409574f0b77014c9b29989e0d0868d40048cc199a822d94c660f`，与12585相同。源 `/data/local/tmp/media-kit-p5-mystery-box.mp4`，最终版主库已移除旧属性门禁；本隔离 APK 仅在默认关闭的性能探针中增补 completed 时直接读取最终 VO/decoder 掉帧，未改产品解码/渲染路径。
- 构建启用 `MEDIA_KIT_AUTO_TEXTURE=true`、`MEDIA_KIT_ANDROID_SURFACE_PRODUCER=false`、`MEDIA_KIT_ANDROID_TEXTURE_LAYOUT_SIZE=true`、`MEDIA_KIT_ANDROID_HDR_TRANSACTION=true`、`MEDIA_KIT_ANDROID_PREOPEN_FULLSCREEN=true`、命名本地源、`MEDIA_KIT_ANDROID_P5_RPU_PIPELINE_BUILT=true` 与性能探针。运行日志确认 `gpu-next`/`mediacodec`、BT.709/BT.1886、Texture `2560×1440`、`P5_DIRECT_RETIRE enabled=1`；t12 截图为实际 Mystery Box 沙漠片头。
- VO累计掉帧：t8=11、t18=11、t28=13、t60=13、t90=14；EOS 事件即时读取 `frame-drop-count=14`、`decoder-frame-drop-count=0`。无 AImageReader/渲染失败；退出 `P5_IMAGE_FINAL acquired=5909 deleted=5909 current_image=0 retired=0`，退休队列 `held_after=0`，Player dispose 完成。
- 100 个 1秒 GPU 样本：中位415 MHz，92个为415 MHz，6个490 MHz，2个332 MHz；性能探针阶段热状态均为1。旧同片未优化12546全片为EOS VO54、decoder0、GPU中位586 MHz；本轮 VO 减少40（约74%），且 GPU 中位频率更低。不同运行时间/热状态不等于严格同包 A/B，但视频、目标尺寸、硬解/VO和默认电池模式对齐。

证据：`artifacts/android-p5-mystery-default-12586/12586-logcat.txt.gz`、`12586-gpu.ndjson`、`12586-t12.png`。P0 剩余门禁是最终 Glass 真人动态画质确认；此处的截图和日志只能证明自动化可见出帧，不能替代用户观察。P1 PQ 产品首帧/性能也不能直接使用此 Texture SDR 数据。
