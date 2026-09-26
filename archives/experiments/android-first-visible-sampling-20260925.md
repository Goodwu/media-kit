# Android 合成屏幕首个视频画面采样（2026-09-25）

为避免把 `video-params` 或 `waitUntilFirstFrameRendered` 当作真实呈现，新增 `archives/experiments/tools/android_first_visible_probe.py`。它记录主机单调时钟下的 UI 点击起止、每次 ADB `screencap` 起止与指定 ROI 的 RGB 均值/方差，并保存 ROI 图像。截图已经过屏幕合成，能证明被采样时画面可见；ADB 往返和截图耗时使它只能给时间区间，不能作为 SurfaceFlinger 精确 present 时间。频繁截图也会扰动性能，正式首帧 KPI 还需先冻结更低扰动的方法及同源原生基线。

11038 调试 APK（SHA-256 `702658b0af98a547a6c24d5a610411411d154f855bf09a22c322e28fd859ba47`）运行临时 SurfaceProducer 测试页，使用已核 SHA `17a30484a12845b7d90adeec45d3f6a776dbdb1dfb2d71fbaccc31e9c6ab627d` 的 10 秒 HDR10 3840×1920 样本。点击测试页入口后，ROI `(400,330)-(900,650)` 的第 0 张仍是前页，第 1–3 张全黑且字节相同；第 4 张首次出现树木画面，第 5 张画面变化。以**点击完成**为零点，第 3 张黑图采集结束在 2.267 秒，第 4 张有视频的采集结束在 3.427 秒，故首次在所采 ROI 可见的时刻只可界定为 `(2.267, 3.427]` 秒。点击包含页面导航，不能替代从 `player.open` 请求计时；该样本存在此前已记录的 HEVC 切片参考警告，也不用于颜色/HDR或流畅验收。

留存 `archives/experiments/artifacts/android-first-visible-11038/` 的 `samples.jsonl` 与第 3–5 张 ROI 图像；其 SHA-256 分别为 `7d8288e4d414bf29d29583da97cd5ec9cee6dfbb2b416b94dc72f994aec8e9dc`、`43ac8b595360ac33790fb15cc8f03ef9267881a17575ad3778eff66bcc852dc8`、`b8a28e836958f0f2ecb247e763328b6d94044730ca566b3be75ac22afec00b9a`、`885af8fba97dbb76468252dd2e2e7c434309e1fd7e9a565c8ff1e1f41e1be756`。全量主机样本和同轮 logcat 暂存 `/tmp/media-kit-first-visible-11038/`、`/tmp/media-kit-first-visible-11038-logcat.txt`；关键小样本已归档。此 APK 的临时入口源码已在上轮撤回；测试后设备恢复 10369、应用强停并删除设备媒体副本。
