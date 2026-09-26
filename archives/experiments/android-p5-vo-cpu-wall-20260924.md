# P5 VO 墙钟与线程 CPU 时间对照（2026-09-24）

## 结果与解释边界

在有效 P5 4K50 硬解/RPU/raw/MRT/early-fence/retire/1440×810 SurfaceTexture 路线上，为 `vo_gpu_next` 增加默认关闭的 `debug.media_kit.p5_vo_cpu_wall=1`。用 `CLOCK_THREAD_CPUTIME_ID` 与单调墙钟计时，仅在每 250 次 flip 后汇总 draw、flip 阶段。arm64 mpv 编译/链接、APK release 构建和实机首帧通过；同一 8331 APK 关/开属性均播放到约 132 秒片尾，decoder 掉帧均为 0。关组 t60/90/120 VO 累计掉帧 39/402/713，开组 396/697/993；开关差距不能归因探针，轮次本已大幅波动，且本次探针可能扰动时序。

开启组 21 个完整 250 帧窗口的中位：draw 墙钟约 1.256 秒、线程 CPU 约 1.059 秒；flip 墙钟约 4.878 秒、线程 CPU 约 0.127 秒。flip 的墙钟减 CPU 约 4.752 秒/250 帧，表明该阶段耗时主要不是 VO 线程在 CPU 上执行。该数字包括 `pl_swapchain_submit_frame` 和 `swap_buffers`，不能区分 VSYNC/BufferQueue 等待、EGL/GPU fence/驱动阻塞或其他主动等待；也不是 GPU 实际执行时间。下一步在同一个低频窗口汇总中分别量提交和 swap，避免用独立轮次的绝对掉帧差解释机制。

## 构建与误包排除

- 原生增量补丁：`android-p5-vo-cpu-wall-20260924.patch`，SHA-256 `89c4a828cfc758d12d6258f95c9dc42a99164395127146639a97b9c9c397f65f`，应用于本地 `/tmp/media-kit-mpv-clean-2194` 既有 P5 工作源码；反向 dry-run 可应用。新计时默认关闭，每帧仅用时钟调用与内存累加，250 帧才打一次日志。
- 8330 首次链接仅用了现有静态库前缀，未换回有效 P5 链的自定义 FFmpeg/libplacebo：实机紫屏、重复 `P5 raw YUV requested without first-frame DOVI metadata`，**不计性能对照**。APK SHA-256 `c29c710dfdfa8a6913e3289e01e4538862d08deb9784640642c358a7b75be303`，缺帧原因比任何掉帧数字优先。
- 8331 修正链接：构建时暂时换入 `/tmp/media-kit-ffmpeg-p5-stream-2215/_build-arm64/libavcodec/libavcodec.a` 及实验 libplacebo，再于 trap 中恢复前缀原库；有效 APK `/tmp/media-kit-p5-vo-cpu-wall-8331-arm64.apk` SHA-256 `03b0cbea82eb798b3dd3a8524e7c598b9ec5dc75c88cbfe9e01da7055a6955c6`，JAR SHA-256 `c9d3a44a1b064d8de04fdd29be8e73c1abacf527ff66dbb70afd34d4ec4a0b4c`，APK 中 libmpv SHA-256 `173be0b6cec397965a6febdc83f656bd152dfa8f0b6f5f7e45b0b32ffb34c574`。安装后确认 versionCode 8331、P5 `ANDROID_HDR_OPEN`、`P5_RETIRE` 持续计数、截图为正常视频场景；单张截图不证明色彩或流畅。

| 8331 轮次 | t18 | t28 | t60 | t90 | t120 | 片尾 |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| CPU/wall 关：VO累计掉帧 | 0 | 0 | 39 | 402 | 713 | 约132秒，920 |
| CPU/wall 开：VO累计掉帧 | 18 | 64 | 396 | 697 | 993 | 约132秒，已自动完成 |

原始 off 日志 `/tmp/media-kit-p5-8331-off-logcat.txt` SHA-256 `16ab1e01d949c7b37200c03b24e646ba884e79a895989874a9677d609b388dfe`；on 日志 `/tmp/media-kit-p5-8331-on-logcat.txt` SHA-256 `86d3311d286b33b6e872e118345a89f32620c4b409a126a9f860cb5810834df8`。实机实验后应用强停，P5 及计时属性均归零。无真人持续可见流畅或独立颜色/HDR 验收。

## 8332 将 flip 拆成 submit 与 swap

在 8331 的低频窗口汇总上额外于 `pl_swapchain_submit_frame` 后取墙钟和线程 CPU 时间，不改播放路径。增量补丁 `android-p5-vo-submit-swap-20260924.patch` SHA-256 `d525d94b3bba3331918d74df44b1814bcc436550440782d7c099286cc85af2cf`，反向 dry-run 可应用；与 8331 相同的自定义 FFmpeg/libplacebo 依赖链接，arm64 编译/链接及 APK release 构建通过。APK `/tmp/media-kit-p5-vo-cpu-wall-8332-arm64.apk` SHA-256 `3fb8f89537ef3cfc2449e3d0efeef48320385f64f85bb0076ab46b9992295fed`，JAR SHA-256 `120f0f2db40f26baa26f0d5ecf5d8088ce2d1c65fda74f4e497a90433440dd2b`，libmpv SHA-256 `b86dde0484b71bd0687d11949ade7179d2ef6599a37fbdaa6180197c328777f9`；设备 versionCode 8332。

有效 P5 硬解/RPU/raw/MRT/early-fence/retire/1440×810 轮：t18/28/60/90/120 VO 累计掉帧 32/60/308/634/924，decoder 均 0、视频位置 6.52/16.52/48.52/78.52/108.54 秒，之后自动到片尾；无首帧 DOVI 元数据缺失错误。21 个完整 250 帧窗口的中位如下，单位为秒/250 帧：

| 阶段 | 墙钟 | 线程 CPU | 解释 |
| --- | ---: | ---: | --- |
| draw | 1.272 | 1.065 | 约 5.1 ms 墙钟/帧，包含准备与渲染调用 |
| submit | 0.00192 | 0.00192 | 提交调用本身很短 |
| swap | 4.789 | 0.122 | 约 19.2 ms 墙钟/帧，大部分时间不占 VO CPU |

排除首个启动窗口，较早第 2–6 窗口 swap 墙钟中位 4.131 秒/250 帧，较晚第 11–21 窗口为 4.867 秒/250 帧；draw 墙钟对应中位约 1.272/1.260 秒，未同向显著增长。晚期每帧约 5.0 ms draw 加 19.5 ms swap，在串行 VO 路径上足以压低 50 fps 吞吐；这比“纯色彩着色计算太重”更符合当前观测。仍不能把 `swap_buffers` 墙钟直接说成 VSYNC、GPU fence 或 BufferQueue 中任一项，也不能用不同包或轮次的掉帧差估计修改收益。此前单改 swap interval 0 在关闭热路径探针时掉帧更差，不能直接把关闭 VSYNC 当作解法。下一步应核对 `swap_buffers` 内部等待/生产者与 Flutter Texture 消费节奏，并设计保留顺序、颜色精度与队列背压的流水线改动，而非再缩小输出或盲调滤镜。

原始日志 `/tmp/media-kit-p5-8332-on-logcat.txt` SHA-256 `3644383bd289565bfd8299e74e6f615e3f1fb5df38c181cf0e3caea08d728432`。单轮 CPU/wall 探针仍会扰动时序；结论限于等待发生在 VO 的 swap 调用边界，不等于无探针时每帧精确耗时，也不替代真人可见流畅验收。

## 8332 EGL 与 swap 后 fence、交换前完成对照

本地 mpv 调用链：`vo_gpu_next.flip_page` → `ra_gl_ctx_swap_buffers` → Android `eglSwapBuffers`，返回后 `ra_gl_ctx_swap_buffers` 才可能等 mpv VSYNC fence。复用 8332 APK，保持有效 P5/raw/MRT/early-fence/retire/1440×810，额外打开已有默认关闭的 `p5_swap_probe=1`，每 50 帧稀疏记录 EGL 调用与 EGL 后 mpv fence。全片轮 t18/28/60/90/120 VO 累计掉帧 0/0/0/170/460，decoder0、到约132秒片尾，Texture累计回调 t60/90/120=2428/3750/4941。前约 3000 帧的 EGL 调用样本中位 0.974 ms，之后约 3000–5900 帧为 18.945 ms；两个阶段 EGL 后 mpv fence 样本中位 2 µs、记录等待次数均为 0。早期无掉帧与仅开 CPU/wall 的 8332 不同，说明该探针显著改变时序；不能据此说正常路径前 60 秒零掉帧。但同一轮的晚期 EGL 调用增长与 VO 掉帧增加方向一致。

再于同一 8332 APK 加 `p5_preswap_finish=1`，在 EGL 交换前强制 `glFinish`：截至约第 2700 帧（t90），finish 稀疏样本中位约 21.5 ms，EGL 调用约 0.47–0.53 ms，EGL 后 mpv fence约 1–2 µs、等待次数0；VO累计掉帧 t18/28/60/90=127/291/850/1350，decoder0。与上一轮不同负载/时序，不能逐帧等量相减或宣称 GPU 着色算术耗时 21 ms；但长等待从 EGL 调用边界移到显式完成点，支持已提交 GL 工作/资源同步参与等待，反对“完全只是 EGL 后 mpv fence”等待。`glFinish` 串行化显著恶化吞吐，不是解决方案；先前 4K 6273/6274 已有同方向结果，本轮在当前 1440×810/MRT 链复核。

无强制完成全片日志 `/tmp/media-kit-p5-8332-swap-split-full-logcat.txt` SHA-256 `894a48949a0a233850728a91b3561daece10b30785070365de577c4bddd01bc2`；强制完成截至 t90 日志 `/tmp/media-kit-p5-8332-preswap-finish-logcat.txt` SHA-256 `b22b9e57c4bf5441139b5292a06854d45ab568d2fc066fd910823f1782a2de01`。下一步针对当前 GPU 命令/资源依赖和输出队列做保持像素质量的异步化或消除重复工作对照，并在无高扰动探针下复验长播；不能把关闭 swap interval、强制 glFinish 或牺牲布局尺寸直接当修复。
