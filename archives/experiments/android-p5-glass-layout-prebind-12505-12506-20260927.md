# P5 Glass 真实布局驱动的 SurfaceProducer 预绑定，12505–12506

## Current State

2026-09-27，LYA-AL00/API29，指定 Glass P5 本地源 SHA-256 `afb24b77733a3ca9071f0cfea0d0f7871670a7b6119eb44a314cba974541477c`。隔离 APK 使用正式库接口 `VideoController.prepareAndroidTextureOutput()`：已挂载 Video 上报物理布局，SurfaceProducer 以布局尺寸建立 Surface，原生尺寸 ACK 返回 Texture ID/wid，Dart 严格完成 mpv 绑定后再打开媒体。视频参数到达后恢复源尺寸。测试页仍为竖屏 Texture SDR、外部预验证固定源、点击回调/PixelCopy 计时；不是正式全屏产品验收。

12505 首轮暴露 Flutter 合法 Texture ID 为 `0`，代码错误要求 ID 大于零，因此在 1440×810 Surface 已产生后以 `SurfaceProducer did not return a bound Surface` 停止打开。改为只拒绝负 ID。12506（APK SHA-256 `9dbb37b53abc2348e963e2487c192ad7a1740ec763dbf348fc2b56152a35f728`）一次冷开：

| 点击回调起算的事件 | 时间 |
| --- | ---: |
| 输出配置复位 | 0.316 秒 |
| 请求 1440×810、绑定完成 | 0.422 秒 |
| 媒体打开返回 | 0.480 秒 |
| OMX HEVC 组件创建 | 约 0.513 秒 |
| 首个 AImage（PTS 0.050） | 约 0.795 秒 |
| 固定区域首次非黑采样 | 3.384 秒 |

原生日志随后记录同一 wid `10450` 上的 3840×2160 尺寸请求；播放约 9 秒后的屏幕截图可辨认吹玻璃画面。首次非黑相对 12501 预建开启轮 3.476 秒方向相近，但不同 APK、单轮与缓存状态不支持精确收益归因。素材本身约 2.05 秒黑场；PixelCopy 不是物理显示时刻。RPU逐帧、同 PTS 色彩、真实全屏、冷/热分布、退出/重入及 EOF 尚未验证。

独立 V1 复核指出布局帧后回调、重复打开尺寸缓存、末个布局 owner 移除，以及后台清理后同尺寸但 wid=0 的边界。当前实现有界等待首布局、owner 清空时重置就绪信号、预建后失效源尺寸缓存；零 wid ACK 返回明确降级而非使播放事务失败。该降级/后台恢复仍需实机覆盖。

本机磁盘在 Flutter 构建末尾复制 APK 时耗尽，`flutter build apk` 返回失败；Gradle 产物 `build/app/outputs/apk/release/app-release.apk` 的版本 12506、APK 签名经 `aapt`/`apksigner` 核验，已安装并实际运行以上轮次。隔离 `build` 已删除释放空间，不能把构建命令视作完整成功。证据：`artifacts/android-firstframe-layout-prebind-12506/run1.log.gz` SHA-256 `a81e1fdfe3d9e304f642141a1f4032d755ac415533ba354469e78544da4d67cd`；`run1.png` SHA-256 `9a334a96c847d0076332f7d73e01c060c265f3e1e5606651b978913fcac343b6`。

结束后强停应用、诊断属性归零、恢复 12492 APK，自动亮度模式 1，设备睡眠且屏幕 OFF。
