# P5 色度相位探针 GPU draw 时间（2026-09-25）

同一 8372 APK、同一原片 4K50 P5、同一 MediaCodec/raw packed10/码值缩放/RPU 路径，打开 `debug.media_kit.p5_raw_perf=1`，仅切换 `p5_raw_chroma_left_probe=0/1`。两轮各播放约24秒；前20帧及每50帧稀疏记录 `GL_EXT_disjoint_timer_query` 的 raw prepass `gpu_draw_us`。日志：`artifacts/android-p5-leftphase-gpu-off-8372.log`、`artifacts/android-p5-leftphase-gpu-on-8372.log`。

排除启动帧，对 frame=50,100,…,650 同号13点比较：关闭中位 910µs、均值 927µs、范围 810–1064µs；开启中位 919µs、均值 915µs、范围 871–989µs。所有纳入样本 `disjoint=0`。这组稀疏样本没有显示相位探针令 raw GPU draw 时间明显增加，但只有两轮且计时开启会改变调度，不证明长期端到端零成本。前一轮无计时 A/B/A/B 的 VO 掉帧亦未呈稳定回退，见 `android-p5-leftphase-performance-20260925.md`。

数值验证已由同APK左边缘图案的离屏L3与映射前packed10整帧A/B建立；这里的计时仅用于性能初筛，不能替代显示呈现、L2C颜色或HDR验收。
