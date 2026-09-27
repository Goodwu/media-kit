# Mystery Box P5→Texture SDR 全片性能基准（12546）

## 配置

- 华为 LYA-AL00/API29；本地 `/data/local/tmp/media-kit-p5-mystery-box.mp4` 与主机 Mystery Box 文件同名规则传输，设备大小 `361648124` 字节。主机 SHA-256 `3e610d3b1b11e9b802da66d69bd97f6371a2b114ee464a7e8517fe31d706cc9f`，ffprobe 为 HEVC Main10、DV Profile5/RPU、3840×2160、60000/1001 fps、5930视频帧、约98.94秒。按用户要求不在每轮传输后重复读取全片哈希。
- 自建 arm64 JAR SHA-256 `f745146332b532d8baeb162b7a33ddefa03ae8dc0a7731f13a9584ef7e6fa3f9`，不含 `optimize_dovi_linear_decode` / `p5_pq_pipeline` 线性解码候选；12546 APK SHA-256 `ab179319e48ebbb4b3e725fc653c067992c7c4459a3e78475aff8d004628d0bd`。Texture SDR、`gpu-next`/`mediacodec`、BT.709/BT.1886、BT.2390，真横屏视频输出请求 `2560×1440`。RPU/raw/direct/retire 属性 `2/1/1/1`，PQ优化属性0，自动亮度，未修改系统电池性能模式。
- 从普通测试页 `Video 0` 点击后进入横屏全屏，媒体从0正常播放到EOS。GPU频率1Hz，共110样本；Dart性能计时器从页面创建启动，故`t=28/60/90/120`分别对应媒体约2.47/34.47/64.46/94.48秒，不应误读为媒体时间。

## 结果

| 媒体时间 | VO累计掉帧 | decoder累计掉帧 |
| ---: | ---: | ---: |
| 2.47秒 | 45 | 0 |
| 34.47秒 | 47 | 0 |
| 64.46秒 | 51 | 0 |
| 94.48秒 | 54 | 0 |
| EOS约98.87秒 | 54 | 0 |

`AUTO_COMPLETED completed=true`。以5930输入视频帧为分母，累计54约为0.91%；其中媒体约2.47秒时已累计45，随后到EOS只增加9。GPU在播放起点后100个1Hz样本中，76个为586MHz、19个为644MHz、3个为538MHz，另有415/139MHz各1；各30秒窗口中位均586MHz。`thermal-status=1`，不能据此判定是否因温度或策略降频。截图为实际横屏全屏的草地/天空画面；未安排真人流畅度或独立色彩观察。

这是**Mystery Box、优化尚未编入的高频观察轮基准**。旧 Glass 优化轮的EOS VO516出现在另一素材且GPU低频窗口，不能直接比较。后续默认开启优化后，须以同片、相同2560×1440路径、同电池模式及GPU频率分布复测，判断是否回退或改善；单轮不证明热态最慢性能。

原始全量日志、GPU NDJSON和截图在 `artifacts/android-p5-mystery-sdr-baseline-12546/`。测试结束后强停12546，恢复原12492 APK、相关诊断属性0、自动亮度模式1并熄屏。
