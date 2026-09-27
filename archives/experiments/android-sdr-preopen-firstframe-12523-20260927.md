# Android SDR 物理全屏预建首帧短轮（12523，2026-09-27）

- 设备：华为 LYA-AL00，Android 10；默认自动亮度。测试 APK 仅 arm64，versionCode 12523，SHA-256 `69fea94db9bba4e8fdfe119dd85beb4bd09ab2153893197476f675590663f228`；使用自建 arm64 libmpv JAR。
- 入口：黑底、无加载控件的预先横屏物理全屏 3120×1440 页面；点击后先 `prepareAndroidTextureOutput()` 绑定已挂载 Video 的实际布局，再打开 `/data/local/tmp/media-kit-sdr-control.mp4`（本机 SDR 控制素材）。每轮独立启动进程。`layoutBound=true` 三轮均出现。
- 取样：点击回调内启动 Flutter Surface `PixelCopy`，上方视频区 `Rect(1360,235-1760,485)`；基线全黑。`first_nonblack` 使用 mean>1 且 spread>1，`first_content` 使用 mean>20 且 spread>10。取样时间是可见内容的离散读回上界，未计物理触摸到回调的时间，也不是面板光学计时。

| 独立进程 | 首次非黑 | 明显内容 | 首个 AImage |
| --- | ---: | ---: | ---: |
| 1 | 309.1 ms | 759.5 ms | 约 262 ms |
| 2 | 312.1 ms | 753.6 ms | 约 243 ms |
| 3 | 289.2 ms | 724.1 ms | 约 237 ms |

三轮 `first_content` 最大 0.760 秒，仅证明此 SDR 诊断路径在探针定义下达到 1 秒内；无关 HDR10/P8.4/P5，也不能据此宣布正常应用入口、冷/热分布或所有视频 2 秒门槛通过。P5 Glass 原片头约 2.052 秒黑场，12522 同式探针三轮可辨内容仍为 3.374–3.625 秒。没有同包关闭预建的 SDR A/B，本实验不单独归因预建收益。

原始关键行见同名目录 `run1.log` 至 `run3.log`。本轮结束强停测试页，恢复日常 APK versionCode 12492、五项 P5 诊断属性 0、自动亮度、熄屏。
