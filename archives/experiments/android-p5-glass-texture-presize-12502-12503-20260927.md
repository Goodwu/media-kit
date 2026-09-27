# P5 Glass Texture 预建尺寸边界，12502–12503

## Current State

2026-09-27，LYA-AL00/API29，指定 Glass P5 本地源，SHA-256 `afb24b77733a3ca9071f0cfea0d0f7871670a7b6119eb44a314cba974541477c`。隔离诊断测试页使用 SurfaceProducer Texture SDR，媒体打开前设定初始 Surface 尺寸并等待非零 wid、`vo=gpu-next`。这些变更没有进入产品代码。屏幕自动亮度；实验后恢复 12492 APK、诊断属性归零，设备睡眠且显示 OFF。

| 诊断包 | 初始尺寸 | 打开返回 | 打开→OMX HEVC 创建 | 固定区域首次非黑 | 结果 |
| --- | --- | ---: | ---: | ---: | --- |
| 12502 | 1×1 | 0.773 秒 | 0.036 秒 | 9 秒内未检出 | 约 86/97 个后续样本近乎均匀，虽然均值随画面变化；该尺寸不能用于产品 |
| 12503 | 1440×810 页面尺寸 | 0.792 秒 | 0.034 秒 | 3.859 秒 | 截图可辨认吹玻璃场景及 16:9 几何，仍未做人工画质验收 |

计时起点是 Dart 点击回调，非物理触摸；终点是约 80–125 毫秒间隔的 Flutter Surface PixelCopy 采样，非物理屏幕扫描。12503 截图发生在播放中，证明有可辨认画面，不证明该轮首次可见帧时间、HDR、RPU 匹配或色彩准确。源片头本身约 2.05 秒黑场。

两轮在 media open 前均取得非零 wid 和 `gpu-next`，OMX HEVC 组件约 34–36 毫秒后创建。后续尺寸更新到源 3840×2160 时 wid 保持同一值；这不证明底层缓冲与色彩无损。12503 Back 后输出统计 `maps=3717 reaped=3715 held_after=0 waits=0 fallbacks=0`、`acquired=3715 deleted=3715 current_image=0`，应用进程未退出；只是一次清理证据，重入和 EOF 未验。

产品代码检查：`AndroidVideoController.waitUntilInitialOutputBound` 对 SurfaceProducer Texture 直接返回，初始 `VideoOutputManager.Create` 可返回 0×0；`_applyVideoSizeLocked` 仅在源尺寸已知后调用 `SetSurfaceSize`。`VideoState._reportTextureLayout` 目前只对旧 SurfaceTexture 且启用布局尺寸匹配时报告布局，SurfaceProducer 分支不报告。因此不能直接把诊断包的固定尺寸写入产品；需要设计媒体打开前的通用布局尺寸获取与 Surface 可用 ACK，并处理无布局、尺寸变化、Surface 重建、失败与释放。

证据：`artifacts/android-firstframe-presize-12502/tiny1.log.gz`；`artifacts/android-firstframe-presize-12503/layout1.log.gz`、`layout1-exit.log.gz`、`layout1.png`（SHA-256 `cb612a329a138c1018ad9a07f7609551b7a5c9be2c0c7002c12b0f137c6024ef`）、`diagnostic.patch.gz`（SHA-256 `3239c64d0ee236bf248595b13c9e6603e8d2e2d75a241c11c920d9bc8785db77`，解压原文 SHA-256 `8dcb77911e1ff2da7c10fd6f135a72e4184ee86989f54147d42aa73eafbf6f5b`）。12502 APK SHA-256 `c6b2d39cbe98c810b3cd795f8964fc511ccfbf63536ffb29bc8436a9c61d0dc0`；12503 APK SHA-256 `4e845e383ae986c2e32c2878d5f455e63db04db75b17acbbc8716ae2baa5b5b8`。
