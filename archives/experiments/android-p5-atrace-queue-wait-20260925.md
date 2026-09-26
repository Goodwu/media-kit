# 官方 4K P5 正常窗口的 queueBuffer 等待（2026-09-25）

在设备空闲时，`atrace -z -b 1024 -t 2 gfx sync` 成功产出有效trace；此前 2026-09-24 的两次 atrace 报内核 tracing `record-tgid: Out of memory (12)`，故没有沿用“trace不可用”的旧结论。随后复用11042 APK（SHA-256 `2e617b98b63b19ad570d7aee9f4dd81ff7eccd1c03a12b5acaed90cacac74ce8`）和同一Dolby官方Sol Levante 4K/24fps P5、1440宽Texture SDR、MediaCodec/RPU/raw packed10正常窗口路径，启用默认关闭的VO与EGL稀疏计时；执行`atrace -z -b 8192 -t 10 -a com.example.media_kit_test gfx view sched freq sync video`。设备返回约1.98MB压缩trace，可解出约21.82MB事件；没有发现明确的丢失/截断标记。完整trace和同轮logcat分别存于`archives/experiments/artifacts/android-p5-atrace-11042/media-kit-p5-11042-atrace-20260925.txt`、`.../media-kit-p5-11042-atrace-logcat-20260925.txt`，SHA-256分别为`526404425ed2875fb93cfc5b1d6de3238883a58e9f0cc8436315417a4a3aab99`、`b6415cf163158694b51e701ab9a6415472c7b270b72049254b752d5b0a`。解析脚本为`archives/experiments/tools/p5_atrace_slice_summary.py`，固定应用PID19768/VO TID20039重放命令：

`python3 archives/experiments/tools/p5_atrace_slice_summary.py archives/experiments/artifacts/android-p5-atrace-11042/media-kit-p5-11042-atrace-20260925.txt --pid 19768 --tid 20039`

10秒区间中179次完整VO线程slice的CPU墙钟：

| 嵌套调用 | 样本数 | 中位 | p95 | 最大 |
| --- | ---: | ---: | ---: | ---: |
| `eglSwapBuffers` | 179 | 49.369ms | 56.967ms | 66.621ms |
| 其中外层`queueBuffer` | 179 | 48.794ms | 56.290ms | 66.097ms |
| `queueBuffer`内`waitForever` | 179 | 48.483ms | 55.931ms | 65.689ms |
| 同线程另行调用的`dequeueBuffer` | 180 | 0.085ms | 0.184ms | 0.580ms |

一条事件链实例：`eglSwapBuffers`→`queueBuffer`→`SurfaceTexture-0-19768-0`→`waitForever`，后者约50.5ms，随后记录GPU completion fence标记。**本轮长阻塞发生在SurfaceTexture目标的`queueBuffer`中的`waitForever`，不是独立的`dequeueBuffer`，也不是mpv交换之后的vsync fence循环。** 对179次等待结束逐次查找最近的先前事件：176次在0.5ms内、178次在1ms内有Mali `dma_fence_signaled`，同时有对应时间窗的VO线程`sched_wakeup`；342条`hisi_dss`显示fence信号无一次落在这些结束点前1ms内。这是强烈的**GPU fence完成等待时间关联**，比仅凭`waitForever`名称更具体；但trace未把所等待fence ID与信号ID逐一配对，不能从关联单独断言是哪一个渲染pass、哪一帧的GPU工作或排除更深层的间接消费者影响，尤其不能把49ms直接标为shader算术时间。下一步集中核正常窗口GPU提交/完成的跨度和pass，再对照BufferQueue消费者。

trace虽含`dma_fence_wait_start/end`事件，但仅一对且发生在composer线程，不是VO的179次`waitForever`；因此不能用内核等待事件的context/seqno直接配对VO所等fence。

进一步按`timeline/context/seqno`配对同一trace内的Mali `dma_fence_init`与`dma_fence_signaled`：518条完整fence的创建至信号中位57.340ms。179次VO等待结束中，距结束不超过0.5ms的Mali信号有176条，其中175条可找到该信号自身的创建事件；这175条信号创建至完成中位104.127ms，创建至相邻VO等待开始中位55.487ms。**这不是等待fence的逐ID配对**：按时间最近选出的信号可能并非该`waitForever`实际等待的fence，创建到完成也包括排队时间而非纯GPU执行。它提示正常窗口链存在跨多个帧预算的GPU fence在途时间，下一步应建立等待对象ID或在GPU pass边界观测，而不把104ms当作单帧计算耗时。

同一10秒区间，Flutter `1.raster`线程有171次`updateTexImage`开始事件，间隔中位55.159ms。逐次VO `queueBuffer/waitForever`结束到其后最近一次`updateTexImage`开始的间隔中位3.867ms（143/179在5ms内）；SurfaceTexture同名队列计数仅出现0/1（分别171/180条）。这表明在本次慢状态中，Flutter消费事件通常跟在VO的Mali fence近邻等待结束之后，未见该队列计数堆积到2；但计数不代表所有已acquire缓冲，也未证明消费者完全不造成间接背压。原生SurfaceView与Texture的对照仍有价值，前提是保持同一P5 SDR目标、尺寸和渲染配置；现有PlatformView政策会将P5切到PQ并请求本设备已拒绝的HDR dataspace，不能直接拿UI切换当单变量A/B。

同轮稳定VO退出汇总queued2517/draw1709/deadline_drop808、解码RPU主实例outputs/matched2160/errors0；包含启动重开/flush，不能直接拿RPU和VO总数相减推断丢帧。trace只覆盖其中10秒且有诊断开关，不作正式流畅门禁。实验后媒体已删除、属性清零、恢复官方10369并强停，未提交。
