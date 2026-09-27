# P5→PQ 首帧探针全屏目标复核（12544）

- 同一 LYA-AL00、同一 P5 全片和自建 arm64 JAR；12544 APK SHA-256 `abb3d4ac2b0e1b13e3f9e8d024349825ec388fe80c7e0bf07771059ef0160a2b`。探针优先选择面积最大的可见原生视频 Surface，只在横屏且宽度至少为窗口一半时读回，并在 `first_content` 记录目标尺寸。
- 首次配置尝试把 RPU 属性误设为 `1`，策略要求 `2`，在媒体打开前明确失败；改为 `debug.media_kit.p5_rpu_probe=2`、`p5_raw_yuv=1` 后重开独立进程，私有 PQ 设置两次回读 `163971072`，`gpu-next`/`mediacodec` 打开成功。
- 有效轮的探针 baseline 为横屏 `2984×1440` 视频 Surface，触摸按下→明显内容读回 `3967.171 ms`，`first_content` 仍为该尺寸；7 秒全屏截图显示实际 Dolby Vision 4K HDR 片头画面。此前 12543 baseline 的 `1440×810` 旧小 Surface 已排除。
- 目标在媒体打开前已经是 `2984×1440`，故仅凭尺寸仍不能证明它在重建后的 Surface owner 身份；也未标记首个 buffer。约 3.97 秒仍含素材黑场，不能直接判播放器首帧超过 2 秒。下一步需把探针与当前 View/Surface generation 绑定，分开记录首个有效视频 buffer 和可辨画面。
- 原始有效轮日志与截图在 `artifacts/android-p5-private-pq-firstframe-12544/`。轮后已恢复原 12492 APK、P5 诊断属性 0、自动亮度模式 1、熄屏。
