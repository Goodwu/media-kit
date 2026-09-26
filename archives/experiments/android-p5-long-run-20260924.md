# P5 Texture SDR 长时间播放对照（2026-09-24）

## 结论

4K50 P5 硬解、RPU/raw/MRT/early-fence/retire、1440×810 SurfaceTexture 路线尚不能稳定实时播放。8328 在 60 秒采样点仅累计 14 个 VO 掉帧，但 90/120 秒增至 281/586；8329 启用 Texture 消费统计后，从 18 秒开始掉帧，120 秒累计 1029。两轮解码掉帧均为 0，播放位置继续推进并到达片尾。短时间成功不能代表长稳或可见流畅，且这不是严格单变量性能对照：8328 未编译 Texture 统计，8329 编译并启用，运行初始状态也可能变化。不能据此认定探针是根因，或归因于 GPU 算术、温度、驱动等待。

## 实验条件与原始结果

- 设备：Huawei LYA-AL00，Android 10，序列号 `3EP7N18C28016072`；固定私有 P5 文件，源 3840×2160/50 fps；编译开关选择 gpu-next、mediacodec、SurfaceTexture、按布局输出尺寸、P5 RPU pipeline 和性能采样。运行属性：`p5_rpu_probe=2`、`p5_raw_yuv=1`、`p5_raw_mrt=1`、`p5_raw_early_fence=1`、`p5_raw_retire=1`。两包 libmpv 均为 SHA-256 `9d034910cfe414d70dc9a8fb42fbf626dc8c511708edefdf0984b87adb243212`。
- 8328：`/tmp/media-kit-p5-long-6328-arm64.apk`，SHA-256 `9c6d55085c5761e9746c3533e158f9562739ec91a359220bc77e3d844fcadd7f`；未编译 `mediaKitTextureConsumerStats`，故消费统计显示 `disabled_by_build_property`。日志 `/tmp/media-kit-p5-8328-t155-logcat.txt`，SHA-256 `4d8885f1320e759d5d0331f81ec5174d6796a45710d703f0c0f9a301b1a2ac8a`。
- 8329：`/tmp/media-kit-p5-long-consumer-6329-arm64.apk`，SHA-256 `82fdbc00f2e8952158b7001aa42447bbf50a03a193b7b5f85cc2d4927614dfa8`；额外编译 `mediaKitTextureConsumerStats=true`。日志 `/tmp/media-kit-p5-8329-final-logcat.txt`，SHA-256 `0499f91a1fb9bd4a26abf8c28ec926a27afaa5f6155f2a10b21b80335c232592`。

| 采样时间 | 8328 视频位置 / VO 累计掉帧 | 8329 视频位置 / VO 累计掉帧 / Texture 累计回调 |
| --- | --- | --- |
| 18 s | 7.36 s / 14 | 7.74 s / 54 / 317 |
| 28 s | 17.36 s / 14 | 17.74 s / 93 / 762 |
| 60 s | 49.36 s / 14 | 49.74 s / 390 / 2047 |
| 90 s | 79.34 s / 281 | 79.74 s / 700 / 3227 |
| 120 s | 109.32 s / 586 | 109.74 s / 1029 / 4376 |
| 150 s | 132.06 s / 786 | 132.08 s / 1251 / 5265 |

150 秒采样时两轮均已到片尾并暂停，不能把 120→150 秒全部作为有效播放窗口。8329 Texture 统计是 `updateTexImage()` 回调，不是面板呈现帧率；120 秒窗口的相邻回调时间中位约 24.95 ms，仅支持消费链吞吐下降。retire 日志到 5350 map 时 `waits=0`，但这不排除其他 GPU/驱动等待。两轮 thermal-status 均为 1，不能证明无热相关影响。没有这两轮的真人持续可见流畅或独立色彩验收。

## 补充与后续

### 8329 同包复测

同一已安装 8329 APK、相同运行属性和统计配置再次全片播放。首次 `am start` 仅停在目录页，150 秒期间无 PERF/媒体打开，已用截图确认并排除；随后点击 `single_player_single_video.dart` 进入有效轮。日志确认 P5 `mediacodec` 3840×2160、Dolby Vision 色彩参数及 1440×810 输出。首帧附近一次 `acquireLatestImage -30001` 后继续映射/播放；没有把这一次错误解释为后期掉速原因。

| 采样时间 | 视频位置 | VO 累计掉帧 | decoder 累计掉帧 | Texture 累计回调 |
| --- | --- | --- | --- | --- |
| 18 s | 7.72 s | 14 | 0 | 370 |
| 28 s | 17.72 s | 14 | 0 | 868 |
| 60 s | 49.72 s | 14 | 0 | 2466 |
| 90 s | 79.70 s | 296 | 0 | 3676 |
| 120 s | 109.66 s | 604 | 0 | 4851 |
| 150 s | 132.00 s / EOF | 832 | 0 | 5730 |

有效轮日志 `/tmp/media-kit-p5-8329-repeat-valid-logcat.txt`，SHA-256 `833ac9ef1816e853e4d91cbda9c4c2e8bd3b5666af8b11b6a5fa8fe2aa4b55d0`。同一包前轮在 t60/90/120 掉帧 390/700/1029，此轮为 14/296/604；起始差异很大，但晚期 60→120 秒新增 590，确认这次有效长播仍明显退化，不能说明退化始终在相同时间点或程度出现。下一步更有价值的是记录同包播放时的 GPU/CPU 频率、温度、VO 阻塞或驱动等待与 Texture 消费同步变化，隔离后期吞吐下降；仅看短轮或泛化为热限频都缺证据。

### 8329 同步设备计数器轮

同一 APK、运行属性与 Texture 统计配置再播全片，同时从主机约每 1.4 秒读取设备的 GPU 当前/最高频率、DDR 当前频率、CPU 三个 policy 当前频率，并用 `P5_RETIRE` 日志确定 VO 为 PID 4151/TID 4334（设备线程名 `Thread-5`），另约每秒采集该线程 `/proc/.../schedstat`。启动进入单视频页后确认 `ANDROID_HDR_OPEN` P5；采样 t18/28/60/90/120 的视频位置为 6.88/16.88/48.86/78.88/108.88 秒，VO 累计掉帧 45/128/561/989/1398，decoder 全程 0，Texture 累计回调 291/693/1844/2894/3967；t150 已在约 132 秒片尾，VO 累计 1695。该轮从早期即严重掉帧，不能作为“第 60 秒才开始退化”的严格复现，但再次证明全片吞吐不足。

计数器窗口从 18:07:18 到 18:10:38，覆盖播放与片尾后阶段。有效播放的大致 30 秒窗口 GPU 当前频率中位数均约 208 MHz，读取的 `gpufreq/max_freq` 始终 720 MHz；DDR 当前频率中位约 1866 MHz，CPU policy 当前频率中位分别约 830/826/1460 MHz。`thermal-status` 在 t18/28/60/90/120 均为 1。VO 独立 100 个调度样本覆盖 105.8 秒；四段约 29.9/28.9/28.9/14.9 秒，CPU 运行约 5.396/5.032/5.197/2.710 秒，可运行排队仅约 0.200/0.174/0.184/0.092 秒。采样命令最初按线程名寻找 `vo/gpu-next`，但设备实际显示 `Thread-5`，该 TSV 的 `vo_tid` 和 `vo_schedstat` 列为空；独立 schedstat 文件使用日志关联的 TID，有效。最高频率未降低、可运行排队少，不支持持续 CPU 抢占饥饿或已观测到 GPU max 限频；瞬时当前频率和 thermal=1 不能排除热、驱动主动等待、EGL/fence 或 GPU 负载，也不是 GPU 利用率。

原始日志 `/tmp/media-kit-p5-8329-synced-logcat.txt` SHA-256 `c32051680b51e54f424db547f1e3fa600472d488eaa691ba8ce53999db17ad07`；频率 TSV `/tmp/media-kit-p5-8329-synced-samples.tsv` SHA-256 `899eff34202cb7141fcbf4d77f9dab0e08afe587fe15235a2a4079ded48ec159`；VO 调度 `/tmp/media-kit-p5-8329-vo-schedstat.txt` SHA-256 `07349f1dcb8cc9a9491e36dea8e0529595cf6c09db744c9246bd358c6533151a`。下一步需要可区分主动等待/GPU 提交与完成的证据，而非继续根据频率猜测着色算力瓶颈。

### 可用等待证据接口审计

8329 短时有效 P5 播放中，由 `P5_RETIRE` 对应的 VO 线程 PID 15197/TID 15303 连续五次读 `/proc/15197/task/15303/wchan` 均为 `0`，同线程 `/proc/.../stack` 返回 `Permission denied`；不能以 wchan 得到内核等待位置。设备有 `simpleperf`，但 shell 执行 `simpleperf stat -e cpu-cycles -a --duration 0.2` 返回 `System wide profiling needs root privilege`；`perf_event_paranoid=3`。atrace 类别有 `gfx`、`sched`、`freq`、`sync`，但无独立 GPU 类别，先前小缓冲 gfx/sync 追踪只见 fence 生命周期，未给出可归因的 VO 等待。GPU devfreq 可读当前/最高频率，`trans_stat`、governor 等文件不授权读取。故现有 shell 外部接口不足以直接辨识 VO 的 EGL/GPU/驱动等待；后续应在已构建的 mpv/libplacebo 路径做低扰动、按阶段聚合的默认关闭计时，或取得有权限的 GPU fence/驱动追踪，不再反复采样不可读的 wchan。短时探针后应用已强停、四项 P5 运行属性归零。

同原生库的 8303（约 75 秒自动停止 VO）此前在两次重放中 t60 累计仅 12 帧掉落，而更早同包关闭 VO 汇总时 t60 累计 284；这与上述长播结果一起证明短窗口和不同轮次波动很大。下一步先在同一 APK、同一统计配置下重复完整长播，外部采集运行状态与 VO/Texture 计数，再针对长播退化定位有证据的等待或吞吐阶段；不要以低掉帧短轮宣布 P5 性能完成。P5 HDR 输出、独立颜色、可见流畅和长稳验收仍开放。
