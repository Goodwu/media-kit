# 官方 4K P5 的 VO flip 阶段减速（2026-09-25）

上一轮 `frame-drop-count` 定位到解码后 VO 链，但原 `P5_VO_SUMMARY` 只在 VO 退出时经 mpv 日志输出，测试页释放过程中未取得实际 gpu-next 汇总。隔离 mpv `video/out/vo.c` 增加默认受 `debug.media_kit.p5_vo_summary=1` 门控的 Android 直出 `P5_VO_TICK`：每 240 个 VO 入队帧以及 VO 退出时记录 queued/draw/deadline drop/队列过期、draw/wait/flip CPU 墙钟累计值。增量补丁 `archives/experiments/android-p5-vo-tick-candidate-20260925.patch` SHA-256 `89d15e26c4f3e7dafd9603312457237463441963b6a36cb94ce4597747a7f45a`。构建使用一致的 `_build-isolated-arm64`，链接时临时将该轮带 RPU 的隔离 FFmpeg `libavcodec.a` 放入 prefix；链接后 prefix 原库已恢复。**再次重链前必须重新放入正确 FFmpeg 库**，否则不能把新 `libmpv.so` 当作同一 P5 路径。新 arm64 JAR SHA-256 `0a460208ac37cab80358796db6699f83773e49092f39f096b5b4398e2e8e12fe`，其中 `libmpv.so` SHA-256 `9d763fefdf7630e537bfc981a2e0f79f2e8ce61d262b6820b8258aa9b9fb5f19`，字符串核实同时含 `P5_VO_TICK`、`P5_RETIRE`、RPU `close_summary`。该补丁只在隔离源码/JAR，未并入普通发布依赖。

11042 APK SHA-256 `2e617b98b63b19ad570d7aee9f4dd81ff7eccd1c03a12b5acaed90cacac74ce8`，同 Dolby 官方 Sol Levante 4K/24fps P5、1440宽 Texture SDR、MediaCodec/raw packed10/RPU/code_scale/retire，并启用上一轮默认关闭的 10 秒 mpv 属性探针。冷机开始 HAL 当前 GPU 约37°C，运行后日志 AP 温度在减速附近上报43°C；未观测到明确的 cooling/frequency 动作，不能将温度变化定为根因。运行约188秒主动退出，FFmpeg RPU累计 outputs/matched4497、errors0；gpu-next VO 直出最终 queued4488、draw3691、deadline_drop797、other_drop0，Dart `decoder-frame-drop-count`始终0。它们是不同层的计数，不能与屏幕扫描帧直接等同。

按同一 VO 的相邻 240 个入队帧做差（单位毫秒，耗时均为 CPU 墙钟，不直接等于 GPU 执行时间）：

| 入队区间 | 实际 draw | deadline drop | draw 合计 | wait 合计 | flip 合计 | flip/实际 draw |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 960→1200 | 240 | 0 | 1291 | 8205 | 418 | 1.74ms |
| 1200→1440 | 203 | 37 | 1118 | 2909 | 5962 | 29.37ms |
| 1440→1680 | 184 | 56 | 1072 | 1 | 8897 | 48.35ms |
| 1680→1920 | 180 | 60 | 1051 | 0 | 8849 | 49.16ms |
| 1920→2160 | 179 | 61 | 1045 | 0 | 8941 | 49.95ms |
| 3600→3840 | 183 | 57 | 1044 | 1 | 8900 | 48.63ms |

约视频50秒后，`flip_page` 从约1.7ms/实际绘制帧跃至约49–50ms，VO 原本用于等下一帧的 wait 时间归零，随后每 240 入队帧过期约57–61帧；draw 阶段仍约4–6ms/实际绘制帧。**这是当前丢帧的直接时间预算解释**，但 `flip_page` 包含 GPU 提交、EGL/Surface buffer queue 等下游过程，不能仅凭此说 shader 计算或面板呈现耗时49ms。下一步应在 flip 内部对实际 EGL swap/前后 GPU 同步做有界分段取时，或与 Flutter SurfaceConsumer 回调对应，区分生产者提交等待和消费者背压；需同源冷/热重复确认。

完整日志 `archives/experiments/artifacts/android-p5-vo-tick-11042/media-kit-p5-vo-tick-11042-logcat.txt` SHA-256 `390ebfc86549e97e4bc912e444fef22c240d21a391a0094a1dc27c989cb10195`。本轮有 VO 稀疏探针，结果是定位证据，不当作无诊断的最终性能判定。结束时设备媒体已删除、P5属性清零、恢复10369并强停。未提交。
