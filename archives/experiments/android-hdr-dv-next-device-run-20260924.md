# Android HDR/DV 下一轮实体机对照

当前状态（2026-09-24，只读核验）：目标 `3EP7N18C28016072` 为 LYA-AL00/API29，现装 `com.example.media_kit_test` versionCode 4154，`/data` 可用约 26G。系统属性 `debug.media_kit.p5_rpu_probe=0`、`debug.media_kit.p5_raw_yuv` 与 `debug.media_kit.p5_raw_perf` 均为空；系统设置 `touch_disable_mode=1`、`stay_on_while_plugged_in=0`。设备应用私有目录的固定 P5/P8.4 SHA 分别为 `328cae5c78ba9b8e579e7352edcfb8f3e9e0c0670849fc8773a8b028d2d1d03e` / `7626cac28819ffd1377a712b56c7cc4bbf8677f5db4b39fb0c83f92e58d74443`，均于本轮重算。

该清单中的 4214/4216/4217 已由后续 6230–6238 候选取代，不作为当前运行入口。按当前任务选用有效候选，并在安装前核对设备、APK/素材 SHA 与属性；故障时停止该轮，结束后恢复 4154 与原设置。

| 顺序 | 对照 | 包与 SHA-256 | 核验重点 |
| --- | --- | --- | --- |
| 1 | P8.4 源600秒直入，Texture SDR | `/tmp/media-kit-p84-600s-direct-start-2214-arm64.apk`，`07b25460d46c0473d5fa6c9e4f4f0636a22cc19eff7647a803e3409a94e8e989` | versionCode4214；实际起播源PTS、至少120秒进度与VO/decoder丢帧、每30秒热状态；与4204全片t600–720对照，区别设备热状态 |
| 2 | P5全片基线，Texture SDR | `/tmp/media-kit-p5-fullstream-2216-arm64.apk`，`0762e99a94b7b94dfc19b1164ada3e3f71fae3914d4a1c2386db87dab97eaf0d` | versionCode4216；设置`debug.media_kit.p5_rpu_probe=2`及`debug.media_kit.p5_raw_yuv=1`，保持`p5_raw_perf`关闭；超过320帧后仍有连续MATCH/attached、真实视频画面与丢帧、颜色，并在基础成功后验seek/flush |
| 3 | P5低频计时，同源同目标 | `/tmp/media-kit-p5-raw-perf-2217-arm64.apk`，`b0dd74d4c61454388b2c2fe14be4865af362183899f5994b413ace740dfe2cfa` | versionCode4217；沿用上述两属性，额外设置`debug.media_kit.p5_raw_perf=1`；按第1/10/50/250帧及后续窗口记录CPU提交与unmap Finish等待，不能把后者当raw pass独占GPU耗时 |

按 versionCode 升序安装以避免不必要的降级；每包启动前核验已安装版本。P8.4实验不启用P5诊断属性。日志使用从启动时间起的限定采集，不清空全局 logcat；保留开始/结束时间、PID、APK与样本SHA、属性、PERF/PTS/POC/图像错误、Surface或Texture截图及终态。自动日志、进度和截图不能替代真人可见颜色与流畅度验收；P5 HDR激活仍需独立显示链证据。

结束后恢复原属性值 `0` / 空 / 空及原系统设置 `1` / `0`。已保留可恢复的4154原生P8.4包 `/tmp/media-kit-p84-platform-full-2154.apk`，SHA `40b471cd49d95ab02dee299b76945c2e1177e983b80deb7e2c31cd1d2c8f5740`；需要回退时使用保留数据的降级安装，不卸载或清除应用数据。恢复后回读versionCode与设置，确认可见视频。
