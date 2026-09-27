# P8.4 列表点击至横屏全屏首帧（12531，2026-09-27）

## 设置与路径

- 华为 LYA-AL00，Android 10，arm64，测试 APK versionCode 12531，SHA-256 `6b012f5c8001c7ef35b8453a0ee60c35af2cf4154697217fd6c0514b86dca30b`。
- 固定 P8.4 全片 `/data/local/tmp/media-kit-p84-full.mp4`，既有 SHA-256 `7626cac28819ffd1377a712b56c7cc4bbf8677f5db4b39fb0c83f92e58d74443`。`gpu-next` / `mediacodec` / Texture→SDR，非原生 HLG。
- 测试页竖屏列表点击 `Video 0` 后，先启动 Flutter Surface PixelCopy 探针，再用同一 Video 的 `VideoFullscreenScope` 进入横屏沉浸式全屏，待布局帧完成后调用通用 Texture 预绑定，然后 `player.open`。全屏是物理 3120×1440 的横屏窗口，视频保留源比例，两侧为正常黑边。

## 独立进程短轮

| 轮次 | 回调内探针至首次明显内容 | 全屏布局完成约时 | 预绑定约时 |
| --- | ---: | ---: | ---: |
| 1 | 862.613 ms | 232 ms | 295 ms |
| 2 | 663.786 ms | 189 ms | 264 ms |
| 3 | 656.403 ms | 169 ms | 243 ms |
| 4 | 662.673 ms | 175 ms | 256 ms |

四轮 `layoutBound=true`，最慢 0.863 秒。第一轮的实际全屏截图 `/private/tmp/media-kit-12531-fullscreen.png` 有视频内容；另一次独立进程在点击后约 2 秒和 5 秒的截图 `/private/tmp/media-kit-12531-2s.png`、`...-5s.png` 显示不同镜头，证明短时持续出图。日志为 `/private/tmp/media-kit-12531-firstframe.txt`、`...fullscreen-2.txt` 至 `...fullscreen-4.txt`、`...continuity.txt`。

同 PID 的全屏 Back→列表→再次点击实验中，第二次进入全屏并重新预绑定 `layoutBound=true`，新解码 AImage PTS 0，之后截图有全屏视频，未见打开异常。第二次 PixelCopy 首采样已含旧帧，32.421 ms **不是**新首帧时延；该次预绑定到返回约 0.96 秒，仍需定位。日志 `/private/tmp/media-kit-12531-reentry.txt`、截图 `/private/tmp/media-kit-12531-reentry.png`。

## 验收边界

计时起点是点击回调内的 native 探针启动，未覆盖 ADB 触摸到回调以及面板光学呈现；这些短轮不是冷启动分布或长播验收。全屏持续画面已有相隔 3 秒的截图，但 Texture SDR 的独立色彩比较、音画同步和有效重入首帧仍缺。用户要求 SDR 验收完成后才测试原生 HDR 首帧，故暂不将这些读回推广至原生 PQ/HLG。

每轮保持系统自动亮度；测试结束后恢复 versionCode 12492，六项诊断属性为 0，自动亮度模式为 1，屏幕已熄灭。
