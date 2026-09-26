# P5 长播进程/图形内存采样（2026-09-24）

同一 8332 APK、P5 4K50 硬解/RPU/raw/MRT/early-fence/retire、SurfaceTexture 1440×810，关闭 `p5_vo_cpu_wall`、`p5_swap_probe` 和 `p5_preswap_finish`，只用主机约每 10 秒读设备 `dumpsys meminfo -d <pid>`、`/proc/<pid>/status` 与 GPU 当前/最高频率；Flutter Texture 消费统计仍为 APK 内已编译的诊断。进入单视频页后确认有效 P5 打开，进度持续至约 132 秒片尾。没有本轮真人连续流畅或独立颜色验收。

| 采样相对时间 | PSS | VmRSS | GL mtrack | Native Heap PSS | GPU 当前频率 |
| --- | ---: | ---: | ---: | ---: | ---: |
| 0 s（启动初期） | 85.8 MB | 203.9 MB | 11.0 MB | 26.2 MB | 139 MHz |
| 10 s | 227.9 MB | 356.9 MB | 109.8 MB | 63.6 MB | 208 MHz |
| 21 s | 242.0 MB | 371.2 MB | 109.8 MB | 77.3 MB | 208 MHz |
| 31 s | 257.5 MB | 388.3 MB | 109.8 MB | 92.3 MB | 208 MHz |
| 41 s | 263.4 MB | 393.6 MB | 109.8 MB | 98.1 MB | 208 MHz |
| 52 s | 273.3 MB | 404.0 MB | 109.8 MB | 107.9 MB | 208 MHz |
| 62–124 s | 255.3–270.5 MB | 385.9–402.6 MB | 109.8–110.3 MB | 88.3–104.0 MB | 139–208 MHz |

VO 累计掉帧 t18/28/60/90/120=21/49/358/681/1017，decoder 全程 0，Texture 累计回调 t18/28/60/90/120=330/785/2053/3216/4363。t60→120 仍新增 659 VO 掉帧，而 RSS/PSS/GL mtrack 已无单向累积，反对“持续内存泄漏导致晚期线性恶化”的简单解释。启动期 Native Heap PSS 增至约108 MB、VmRSS 增至约404 MB，与掉帧增加存在时间相关，但当前采样不能识别分配对象或因果；也不能排除未计入进程 PSS 的驱动内存/资源压力。GL mtrack 属系统记账指标，不等于 GPU 实际驻留全量。GPU 当前频率采样不是利用率，也未观察到最高频率变化。

有效 APK `/tmp/media-kit-p5-vo-cpu-wall-8332-arm64.apk` SHA-256 `3fb8f89537ef3cfc2449e3d0efeef48320385f64f85bb0076ab46b9992295fed`。原始 15 组设备采样及时间索引 `/tmp/media-kit-p5-8332-memory-run.tar` SHA-256 `a3b7dccb0e5a754af6fec688e8eb4d171762ecc087104b451cbcfced4a09039a`；全片日志 `/tmp/media-kit-p5-8332-memory-logcat.txt` SHA-256 `312c9232b678fafc6c435a51451a71f991d5498d6e814764ee181835a6aaa479`。应用实验结束后强停，P5 属性恢复 0。
