# 官方 P5 原生 SDR/1440 连续循环 30 分钟（2026-09-25）

## 结果

11046 在华为 LYA-AL00 上用同一应用进程 PID 31280 从 09:33:15 设置无限单文件循环，09:33:30 首次 HDR 事务打开，09:33:55 因现有启动重建机制重开，直到 10:04:41 主动返回并释放。重开后的主播放实例持续超过 30 分钟，完成 7 次 263.083 秒官方 Sol Levante 4K/24fps P5 正片循环并开始下一轮。187 条有效的每 10 秒 mpv 计数样本分成启动短实例与 7 个完整正片轮次：启动短实例播放器掉帧峰值 1、解码器 0；所有正片轮次播放器及解码器掉帧峰值均 0，轮内相邻视频位置增量 9.958–10.042 秒。该计数只能证明播放器侧时间轴与掉帧属性，不能替代 SurfaceFlinger 实际 present cadence 或真人连续流畅验收。

30 分钟末 Thermal Status 为 1，当前 GPU 44°C、Battery 41°C、GPU cooling 0；约 10、20 分钟采样的当前 GPU 分别约 44、45°C，未见 thermal service 报告 GPU 降温档位。但没有连续 GPU 利用率/频率曲线或热平衡证明；本轮只支持在所采热状态下 30 分钟播放器侧稳定。

10 分钟截图见正常视频场景；20 分钟首次截图视频区全黑，随后的复查图恢复为另一可辨视频画面，日志时间轴仍推进，不能区分素材黑场与瞬时呈现问题；30 分钟截图见片尾 Netflix 字样。这些离散截图既不是逐帧 present，也不是独立色彩真值。当前输出仍为 **BT.709/BT.1886、8-bit SDR 的原生 SurfaceView/1440×810 buffer**，不能算 P5 HDR/PQ 激活、亮度、颜色或音画同步验收。此官方样片无音轨。

后续在相同 APK/源/配置对该黑场做了带时间戳的定点复测：原 20 分钟黑图与新一轮源位置约 129–131 秒的三张黑图，其 1440×810 视频 ROI 的 RGB 字节 SHA-256 **完全相同**，均为 `c92275b7e26122b5e290548177f819f35090d4a60eebb58b8164d007f434c884`。软件解码官方码流的 128.5–131.708 秒连续 78 帧平均 Y <1/1023，复测黑图前后为非黑场。因此原单张黑图有充分素材内容解释，不再把它列为疑似冻结；仍不能由此证明全程无其他异常黑屏。复测时间、图像及限制见`android-p5-native-sdr-source-black-20260925.md`。

每次片尾仍有 3–5 条 RPU 被 flush 为未匹配；应用返回时累计 close summary 为 `inputs=44324, outputs=matched=44285, errors=0, discarded=39, unconsumed=0`，累计计数跨启动短实例和多次循环，不能简单当成某一轮的帧数。尾帧差额仍需单独解决。此前 11043 原生 4K buffer 和 11042 Texture 1440 均大幅掉帧；本轮只验证 11044 发现的原生视图+1440 SDR 组合在低 VO/EGL 探针负载下长播，不代表其他拓扑性能通过。

## 七轮片尾 EOS 对齐

| 正片轮次 | 输入 EOS→输出 EOS | 输出 EOS→RPU flush | 片尾未匹配 RPU | 首条未匹配 PTS | 输出 EOS 时 FFmpeg `hw_pending` | ACodec 首次 flush 时输出槽 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 82 ms | 5 ms | 3 | 262.958333 s | 0 | 11/18 |
| 2 | 120 ms | 4 ms | 5 | 262.875000 s | 1 | 11/18 |
| 3 | 82 ms | 4 ms | 3 | 262.958333 s | 0 | 11/18 |
| 4 | 38 ms | 4 ms | 4 | 262.916667 s | 1 | 11/18 |
| 5 | 120 ms | 4 ms | 5 | 262.875000 s | 0 | 11/18 |
| 6 | 79 ms | 3 ms | 4 | 262.916667 s | 1 | 11/18 |
| 7 | 119 ms | 3 ms | 5 | 262.875000 s | 0 | 11/18 |

七轮每次都先有 `MEDIA_KIT_MC_EOS: queue_input_eos`，再有 `dequeue_output_eos size=0 flags=4` 与 `return_decoder_eof`，之后才清除未匹配 RPU；厂商 `receive eos buffer` 位于输出 EOS 附近。末条未匹配 PTS 均为 263.041667 s。ACodec 报告的 11/18 输出槽占用完全相同，但未匹配数在 3–5 之间变化，不能只凭占用数证明缓冲背压是根因。`hw_pending` 也在 0/1 间变化，没有随丢失数单调对应。下一步若继续追根，应在 EOS 时一次性记录最后输入/输出 PTS、MediaCodec 输出槽释放及 AImageReader/GL 持图状态，或做仅改变片尾消费者占用的受控对照；不能通过延迟清理 RPU 冒充实际视频尾帧已返回。

## 条件与证据

- APK versionCode 11046，SHA-256 `3ff06f70a8a7dc653809fa709ec59310da18feb359af239c0b2029bf7c31ae56`；隔离 arm64 JAR SHA-256 `0a460208ac37cab80358796db6699f83773e49092f39f096b5b4398e2e8e12fe`。同前次 11044 的 P5 MediaCodec/RPU/raw packed10/early fence/retire/code scale 路径，原生 PlatformView SDR，输出宽上限 1440；本轮额外打开测试页单文件循环，VO/EGL 细分计时开关为 0。
- 11045 先暴露测试页 `MEDIA_KIT_ANDROID_LOOP_SOURCE` 只在非 HDR 事务分支生效；修正 HDR 事务分支设置 `PlaylistMode.single` 并回读 `loop-file=inf` 后构建 11046。日志 09:33:15 记 `ANDROID_LOOP_SOURCE mode=single loop-file=inf`，多次 `time-pos` 从片尾回到开头独立验证了实际回环。
- 完整日志：`artifacts/android-p5-native-sdr-1440-11046-30min/logcat.txt`，SHA-256 `9c420ce5a5fb8b8c159b2bdf95ca1476fbbe30102ba16cf0e2dafc1609bc3043`。可复核：`python3 archives/experiments/tools/p5_loop_counter_summary.py archives/experiments/artifacts/android-p5-native-sdr-1440-11046-30min/logcat.txt`。
- 截图均位于同一 artifact 目录，10 分钟 `acef1b0993ab650f0dacc1cb6a7532e3ff34aafb2bba9e82e9d6c1281beafd54`、20 分钟黑场 `2fd34d316cfe1fb0035be466ba9bfd3f98f7469b285aa8ee61232efc50209db5`、20 分钟复查 `b32991c264b5c461cb6b5ac00acd1852e932e9681cb1a49df336a4320e6a946a`、30 分钟片尾 `3b3f7b5277e190c2b37b557f07c8321878e1c827c7aab480c2aa33b19d75558f`。
- 结束后应用强停，8 个相关 `debug.media_kit` 属性均回读 0，设备测试源两份已移除；重新安装并核实 baseline versionCode 10369，应用未运行。源码与归档未提交。
