# 官方 4K P5 解码与 VO 丢帧计数分层（2026-09-25）

在 Android 测试页加默认关闭的 `MEDIA_KIT_ANDROID_P5_COUNTER_PROBE`，每 10 秒回读 mpv 原生 `time-pos`、`frame-drop-count`、`decoder-frame-drop-count`、`mistimed-frame-count`、`vo-delayed-frame-count`、`avsync`。这些属性已在当前隔离 mpv 的 `player/command.c` 与文档中核对：`frame-drop-count` 是 VO 丢帧，`decoder-frame-drop-count` 是解码器丢帧；后两个显示同步指标只在对应同步模式可解释。开关关闭时无定时查询。构建 11041 成功，Dart 格式无变化；目标 `flutter analyze` 仅报文件第23行既有 `use_super_parameters` info。

真机沿用 Dolby 官方 Sol Levante 4K/24fps P5、同一隔离 JAR、Texture SDR、1440宽、MediaCodec/raw packed10/RPU/code_scale/retire 路线。APK SHA-256 `ef7931d7cc06a02d3925974d89a980191cbe5bc46f0e325c04f842b4b7cb1ba9`。本轮源无音轨，故 `avsync` 回读为空，不是0ms音画差。`mistimed-frame-count` 也为空，`vo-delayed-frame-count=0`不能说明显示实际无延迟。

| 视频时间 | VO `frame-drop-count` | `decoder-frame-drop-count` |
| ---: | ---: | ---: |
| 3.083s | 17 | 0 |
| 33.083s | 194 | 0 |
| 73.125s | 431 | 0 |
| 113.083s | 673 | 0 |
| 133.083s | 796 | 0 |

从 3.083 到 133.083 秒，VO 计数新增 `796-17=779`，对应 130 秒×24fps 的 3120 个源帧，约 **25.0%**；这是该段 mpv VO 丢帧属性的工程估算，远超计划的≤1%门槛，但不是屏幕扫描实际掉帧率。解码器丢帧属性始终0；退出时 FFmpeg RPU `close_summary` 累计 inputs3299（含启动重开）、outputs/matched3222、errors0、discarded77、unconsumed0，不能将累计输出直接作为单次干净播放帧数。raw映射最后低频记录2400次，与 VO 丢帧增长方向一致。此轮从早期便以约每秒6帧增量掉帧，与前两轮减速起点不同，热状态、构建诊断和顺序仍未控制；共同结论是瓶颈在解码输出之后的 VO 处理/调度链，尚不能区分绘制GPU工作、同步等待或时间戳/队列策略。

完整日志 `archives/experiments/artifacts/android-sollevante-p5-4k-11041/media-kit-sollevante-p5-4k-11041-counters-logcat.txt` SHA-256 `5a96b89946ed140104e0e26519c91d7c470f5025b097910eb7b7dc14c9225522`。本轮到约133秒主动退出，没有做263秒完整片尾；只验证这段性能定位。下一步需在同一 VO 线程低频记录入队、过期、接受绘制和 draw/flip/等待耗时，或做不扰动的对应指标回读，按同一时段与硬解输出比较；重复冷机和热稳定条件后再判断根因。结束后移除设备媒体、属性清零，恢复10369基线并强停应用。未提交。
