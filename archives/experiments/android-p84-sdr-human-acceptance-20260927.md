# P8.4 Texture→SDR 真机人工验收（2026-09-27）

- 设备：LYA-AL00，Android 10；APK versionCode 12535；固定 P8.4 全片；普通竖屏列表 `Video 0` 点击后进入同一 Video 的真横屏全屏 Texture→SDR 路径。播放短轮结束后恢复原 APK 12492、诊断属性关闭、自动亮度并熄屏。
- 人工画质：用户观察到颜色轻微偏淡，但明确表示可接受；画面流畅、声画同步。该结论限于本机、本片、本输出路径的观看验收，不等同色度仪测量。
- 人工首帧：单独从已显示的竖屏列表点击 `Video 0` 后，用户报告实际画面约 1 秒内出现。同轮 Android Activity 触摸按下至 PixelCopy 明显内容为 843.752604 ms，日志 `/private/tmp/media-kit-12535-human-isolated-tap.txt`；这是系统读回，不是面板光学时间。
- 一次较早的“竖屏黑屏约 2 秒”观察包含自动脚本在点击测试页和点击 `Video 0` 之间故意等待 2 秒，不能作为播放器首帧耗时。隔离点击后重新进行了上述人工观察。
- 播放链：日志 `/private/tmp/media-kit-12535-human-sdr-20260927.txt` 记录 3840×1920、BT.2020/HLG 输入，`hwdec-current=mediacodec`、`vo=gpu-next`；Texture SDR 合成观察记录 `/private/tmp/media-kit-12535-human-sdr-sf.txt`。这些材料不能单独证明精确 SDR 输出色度或传递函数。
- 后续：SDR 阶段按上述范围验收通过。继续独立测原生 P8.4 HLG、HDR10 PQ 的真全屏首帧；按用户补充，P5 自身转 PQ HDR 输出的结果、失败阶段及耗时单列，不借用其他 HDR 源成绩。
