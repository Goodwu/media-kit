# Glass P5 黑底物理全屏首次内容读回（12522）

2026-09-27，华为 LYA-AL00/API29，自动亮度、默认电池模式，物理横屏 3120×1440。固定 Glass P5 源为 `/data/local/tmp/media-kit-p5-glassblowing2-4k5994.mp4`，此前已核 SHA-256 `afb24b77733a3ca9071f0cfea0d0f7871670a7b6119eb44a314cba974541477c`；本轮按受控文件名选择 P5 策略，不在点击时复制或读取整片。APK versionCode 12522 SHA-256 `9f70fa0af019e0bae2673c96b6f7c4fc3a76c9059e6b9656027722c15b39fcaf`，自建 arm64 libmpv JAR SHA-256 `f745146332b532d8baeb162b7a33ddefa03ae8dc0a7731f13a9584ef7e6fa3f9`。APK `lib/` 仅 arm64-v8a，构建未下载预构建 libmpv JAR。

诊断页在挂载黑底、无加载控件的 `Video` 前申请横屏沉浸模式和缺口短边布局；三轮独立进程的 Texture 预建均报告真实窗口 **3120×1440**，媒体出尺寸后再扩到 3840×2160。点击时启动 Android `PixelCopy`，持续取 Flutter Surface 上方中央 `Rect(1360,235-1760,485)`，64×40 采样位图。首样本三轮均 `mean=0, spread=0`；`mean>1 && spread>1` 记首次非黑，`mean>20 && spread>10` 记明显内容。该 ROI 没有加载控件。

| 独立进程 | 探针开始→`media_opened` | 探针开始→首个 AImage | 首次非黑样本 | 明显内容样本 |
| --- | ---: | ---: | ---: | ---: |
| 1 | 0.449 s | 0.871 s | 3.284 s | 3.543 s |
| 2 | 0.343 s | 0.690 s | 3.060 s | 3.374 s |
| 3 | 0.411 s | 0.761 s | 3.350 s | 3.625 s |

首次非黑范围 **3.060–3.350 秒**，明显内容范围 **3.374–3.625 秒**；均未到 2 秒。Glass 片头本身约 2.052 秒黑场，首个 AImage 的 PTS 为 0.05005 秒，因此原生有帧与屏幕可辨画面必须分开。PixelCopy 是 Flutter Surface 读回的离散采样上界，不是物理屏幕光学观察；探针在点击回调内经 MethodChannel 启动，数字未包含触摸事件进入回调前和调用通道的少量时间。不能将 0.69–0.87 秒 AImage 当作用户已见画面，也不能据此宣称常规片源的完整冷/热启动分布。

三轮选摘日志、APK ABI 清单及一次全屏截图在 [artifacts/android-firstframe-black-roi-12522](artifacts/android-firstframe-black-roi-12522/)；截图 SHA-256 `7ec3f92833571dcecb4dc10474f228b004570212e62489949d4fa84c1e060e8d`。短轮后强停诊断应用，恢复原 12492 APK、五项 P5 属性为 0、自动亮度/自动旋转、屏幕 OFF。下一步要区分片头黑场与额外启动等待，并用没有长黑场的 SDR/HDR10/P8.4 样本、冷/热重复及真实可见画面继续验收。
