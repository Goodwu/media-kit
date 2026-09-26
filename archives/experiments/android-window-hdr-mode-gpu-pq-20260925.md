# Android window HDR mode 与 GPU PQ Surface 门禁对照（2026-09-25）

结论：在目标华为 LYA-AL00（Android 10）上，显式请求 Activity `COLOR_MODE_HDR` 仍未使测试应用的 10-bit GPU SurfaceView 接受 PQ dataspace。此实验只排除“遗漏 window HDR color mode 是唯一阻碍”这一假设；不能否定其他 Surface producer、厂商私有接口或别的设备的 GPU HDR 能力。两轮都在 Surface 创建时失败，媒体未打开，因此没有视频像素、HDR 显示或播放质量结果。

测试 APK versionCode 11049，SHA-256 `a695a0ae8f18777af728bf5516cdd28ed3f9f033b759cb5e5c37c81d6f1ea29d`。测试 Activity 临时增加默认关闭的 `debug.media_kit.window_hdr_mode=1` 开关，在 `onCreate` 调用 `window.colorMode = ActivityInfo.COLOR_MODE_HDR`，日志确认 `requested=2`。同 APK、同平台 GPU/PQ 路由和 `RGBA_1010102` holder format，分别以属性 0/1 强停再启动；设备显示能力两轮都回报 `{2,3}`。预定输入是设备已有已登记的 `/data/local/tmp/media-kit-hdr10-full.mp4`，但两轮都在打开前因输出绑定超时，故此文件身份不参与对照结果。

| window HDR mode | 请求日志 | GPU Surface PQ 设置 | SurfaceFlinger | 后续 |
|---|---|---|---|---|
| 0 | 无 | `applied=false` | `getHdrCapabilities failed to transact: -1` | `waitReady` 10秒超时，媒体未打开 |
| 1 | `MediaKitWindowHdr requested=2` | `applied=false` | 同样失败 | 同样超时，媒体未打开 |

筛选日志及 SHA：`artifacts/android-window-hdr-mode-11049/window-mode-off.txt` 为 `0a6c0d117515ef55d3407ace9f38856bccf2fbbebbe8ebbd9e4f0959905bd9d9`，`window-mode-on.txt` 为 `ee549fc7d622408b0ab85484e90e5dda686c201dc98e91c55cd6eea03e149578`。首次版本 11047/11048 错用 `MEDIA_KIT_AUTO_SOURCE`（只对 macOS 生效），落入未登记的公开样本而在 SHA 门禁终止，不计有效试验；11049 改用 Android 的 `MEDIA_KIT_ANDROID_LOCAL_SOURCE`。临时 12 秒 HDR10 copy 样本没有加入白名单，亦未用于有效两轮。实验 Kotlin 开关已撤回，未并入产品路径。官方 Android [Window HDR color mode 文档](https://developer.android.com/media/grow/ultra-hdr/display)仅说明该 API 可请求 HDR 窗口；其中 Ultra HDR 图片显示还要求 Android 14，本机 Android 10 的视频 Surface 是否受益必须实测，本轮结果为否。
