# P5 全屏 Surface dataspace 重置对照（2026-09-27）

- 设备：`LYA-AL00`，API 29，fingerprint `HUAWEI/LYA-AL00/HWLYA:10/HUAWEILYA-AL00/10.1.0.163C00:user/release-keys`；同一台设备此前公开 NDK PQ setter 返回 `-22`。本轮仅在精确固件和 `debug.media_kit.p5_direct_dataspace_probe=1` 下启用私有 Window ABI 诊断，不是通用产品实现。
- APK：10432 SHA-256 `e375628b11be38045fbb84591d94b9849b6fb227f6da70789375cad3420da363`；本地 arm64 JAR SHA-256 `5b9495f72893b8b62bb9085c67c9e87707b04f5910d3f09e9a79df82efcfd2e2`。固定源为设备 `/data/local/tmp/media-kit-dolby-official-p5-1080p.mp4`，官方 P5 1080p24。测试页使用 PlatformView、P5 RPU 管线、输出宽度上限1440、全屏、手动亮度255。
- 相比10427的固定延时2秒，10432在每个Surface generation发布WID后每200毫秒回读 `ANativeWindow_getBuffersDataSpace`，最多50次；发现 dataspace 不等于请求的PQ时立即通过既有受控探针补设，并继续观察到窗口结束。第6次全屏检查记录 `before=0 expected=163971072 applied=true generation=1 check=6`，前后日志分别为 `p5DirectDataSpaceProbe perform=0 actual=163971072 expected=163971072`。这直接证明全屏Surface重建时生产者把已设置的PQ重置为Default，并在约1秒后被重新设为PQ。
- 重设后全屏 `SurfaceOrientation: 1`，SurfaceFlinger视频层 `z=-1`、`dataspace=BT2020 SMPTE 2084 Full range`、`defaultPixelFormat=RGBA_1010102`；HWC图层 `dataspace=BT2020_PQ (163971072)`、`hdr metadata types=0`。后续复查仍为PQ。图层/信令证据不证明光学亮度、独立颜色正确性或用户肉眼验收；静态HDR元数据仍缺失。10430的左侧旧UI字样消失与否也尚待用户实机确认。
- 结束后强停应用，恢复原10420 APK、自动亮度模式1/设置值37，关闭本轮 `p5_direct_dataspace_probe`、`p5_rpu_probe`、`p5_raw_yuv` 属性。私有 ABI 固件限定、10秒观察窗口和轮询开销都需要产品化评估；不能将此诊断分支推广至其他设备。
