# P5 1440×810 VO 汇总与频率对照（2026-09-24）

同一 P5 4K50 输入，MediaCodec 硬解、RPU/raw/MRT、SurfaceTexture 1440×810；VO 汇总和 Flutter 消费计数均默认关闭，仅测试包开启。`vo=null` 于约 75 秒主动结束 VO，以便输出一次内存汇总。6299 APK SHA-256 `ccb570456bc6ef3944dafedfce1871d84543d4dfabace68635467cfb842d9bd5`，strip libmpv SHA-256 `be2b15cd2b25871931ecbfc4e4f3502f2213647d7368531a9f5b809992e0ac23`；6300 复用同一 APK，关闭 VO 汇总并额外运行 1 Hz 外部频率、5 秒 Thermal HAL 采样。

| 运行 | VO 汇总 | t18/28/60 累计 VO 掉帧 | t28→60 Flutter 不同纹理回调增量 | 证据 |
| --- | --- | --- | --- | --- |
| 6299 on | 开 | 15/15/40 | 未用于对照 | `/tmp/media-kit-6299-p5-summary-on-logcat.txt` SHA `5b2b8fd28df5f626a6baacf7f84eaf42050c6727974e3de1883c0c02c34f9367` |
| 6299 off | 关 | 12/47/399 | 760→1985，增 1225 | `/tmp/media-kit-6299-p5-summary-off-logcat.txt` SHA `0543e7460a715cbcf60aa96c0113da4ff3c6d9558a8dbe798c1ac2c31a3a94f3` |
| 6300 off | 关 | 42/94/401 | 747→2012，增 1265 | `/tmp/media-kit-6300-p5-freq-thermal-logcat.txt` SHA `afb45cd2d43837160104c21350a7cec42ef5aa29f3b27911a37fdc00fb0c29c8` |

三轮 decoder drops 均为 0、thermal status 为 1、视频时间轴约实时。6299 on 在 t60 后掉帧骤增；主动结束时汇总：deadline drops 191，other drops 0，draw calls 3017，late draws 2；draw CPU wall 平均约 5.39 ms，其中 2513 次在 4–8 ms；故意等待呈现时刻平均约 9.74 ms；flip CPU wall 平均约 5.54 ms，其中 681 次在 16–33 ms。此汇总只统计 VO CPU 时间和截止时间，不是 GPU 执行或屏幕呈现时间。关闭探针的两轮仍在 t28→60 丢 352/307 帧，故探针本身不是严重掉帧的必要条件；顺序、初始温度和设备状态未严格配对，不能据 on/off 差异推断探针收益。

6300 外部采样原始文件 `/tmp/media-kit-6300-p5-freq-thermal.jsonl` SHA `b49b644ea23184a92342dd3dac79aa9b3c6d0b1ee552d8c0732c85f175e45272`。GPU `max_freq` 全程 720 MHz，四个 cooling device 采样档位均为 0；播放中 GPU 当前频率多为约 277–332 MHz，HAL GPU 温度由约 38 升至 53°C。`P5_RETIRE` 每 50 帧的间隔从早期约 1.1 秒渐增至后期约 1.25–1.37 秒，与掉帧增多同向；但 1 Hz 当前频率不是利用率，未测 GPU busy、内存带宽或逐帧 fence。温度上升与吞吐下降相关，尚无已生效热限频的证据，也不能排除其他热/调度机制。

隔离 mpv 的默认关闭 VO 汇总补丁为 `archives/experiments/android-p5-vo-summary-20260924.patch`，SHA-256 `a14afc14fc9006cc0a503ce2aff5f0c7b066a6716a0982001042b12c49a30ddb`。下一步优先做相同状态下的调度/同步对照，并寻找有效 GPU busy 或 fence 时间证据；不将频率、CPU wall 或 Texture 回调直接等同可见流畅度。本轮没有独立颜色、HDR 激活或真人连续播放验收。
