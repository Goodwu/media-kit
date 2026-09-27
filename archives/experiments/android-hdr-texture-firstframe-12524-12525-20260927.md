# HDR10 / P8.4 Texture 首帧短轮（12524 / 12525，2026-09-27）

- 华为 LYA-AL00，Android 10，默认自动亮度；APK 仅 arm64、自建 arm64 libmpv JAR。12524 使用 `/data/local/tmp/media-kit-hdr10-full.mp4`，12525 使用 `/data/local/tmp/media-kit-p84-full.mp4`。两包均启用黑底真物理全屏、已挂载 Video 布局、`prepareAndroidTextureOutput()`；三轮各自独立进程，绑定日志均为 `layoutBound=true`。
- 这是 `gpu-next` **Texture 转 SDR** 输出的首帧时间，不证明原生 PQ/HLG Surface、DV 原生解码、系统 HDR 合成或色准。HDR10/P8.4 的可见截图分别保存于同名目录；仅作素材画面确实显示的辅助证据。
- Flutter Surface `PixelCopy` 在点击回调内启动，取上方 `Rect(1360,235-1760,485)`；黑基线后 `mean>20, spread>10` 判明显内容。离散取样时间是探针起点到读回可辨画面的上界，不含物理触摸至回调，也不是面板光学首帧。单轮 P8.4 点击早于页面就绪，被系统丢弃，已重新启动进程测量，不纳入结果。

| 素材 | 第1轮 | 第2轮 | 第3轮 | 三轮最大 |
| --- | ---: | ---: | ---: | ---: |
| HDR10 full | 684.9 ms | 424.3 ms | 423.0 ms | 684.9 ms |
| P8.4 full | 669.3 ms | 538.1 ms | 445.8 ms | 669.3 ms |

三轮原始关键日志在同名目录。该受控路径两类素材均低于1秒；仍需正常入口、冷/热分布、同源 P5 和触摸到面板口径验收。Glass P5 同式黑底探针三轮可辨内容3.374–3.625秒，故总体2秒目标未过。本轮未做同包关闭预建 A/B，不能把全部时间改善归因于预建。

完成后强停测试页，恢复日常 APK versionCode 12492、五项P5诊断属性0、自动亮度、熄屏。
