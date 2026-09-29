# P4 独立色彩数值验收：三方同 PTS 比较与 P5 mediacodec 路径颜色回归发现（2026-09-30）

## 结论

同 PTS 独立数值比较完成，**发现当前产品 P5 渲染存在 mediacodec 路径颜色回归**：

- **主机 libplacebo（FFmpeg n7.1.3 + libplacebo 7.360.1 离屏浮点，无截图路径）与 DoViBaker（独立 DV 重塑实现）一致**——中心像素 (0.588,0.669,0.707) vs 链换域 (0.592,0.674,0.714)，量级与 9/25 记录的 MAE 52/65535 相符。两个独立实现互证。
- **设备实际渲染输出（`pl_render_image_mix` 后整帧 RGBA16F GPU 读回）为离群方**：Sol Levante 2160p 帧 240（PTS 10.000）对两参考 MAE ≈ (2726,2603,10212)/65535（R 基本吻合、G 系统性偏、B 偏 15% 且偏置 +10212）；4K50 素材（media-kit-p5-full.mp4，328cae5c）帧 500 对主机 MAE (4716,876,8388)——而 8370 时代（2026-09-25 构建）同一方法设备↔主机仅 (41,21,53)/65535。**回归系 9/25→9/28 P0/P1 产品化窗口引入，约 100 倍恶化。**
- **回归隔离到 mediacodec 解码路径**：`hwdec=no`（纯软解，stock FFmpeg HEVC DOVI 挂载）时设备↔主机 MAE 降至 (1814,1872,1705) 且三通道偏置近零（残差主要来自 dump 帧为 241 与参考帧 240 的相邻帧内容差）；`mediacodec`（直采）与 `mediacodec-copy` 均显著偏差。剩余子候选：fff3ee7 定制 FFmpeg 的 mediacodec 逐帧 RPU 元数据挂载内容 vs MediaCodec 硬解 YUV 输出本身——需专门仪器化调试定位。

## 已排除项

通道顺序（6 种排列全测）、上下翻转（相关性 0.9938 确认）、错镜头 RPU（全片线性矩阵恒定；用 10/60/130/480/1000 帧重塑系数对照均不符）、mpv screenshot 路径（本比较全程不使用——依 mpv #15107 与用户提醒，截图不作真值）。

## 比较架构（参考母版/目标空间/映射策略）

- 目标空间：BT.2020/PQ/full-range/1000 nit（设备 `p5_target_pq=1` 强制；主机 ffmpeg dvtest 滤镜显式 `max_luma=1000`；DoViBaker 输出经 PQ EOTF→RPU `rgb_to_lms` 线性矩阵→HPE LMS→BT.2020→PQ OETF 固定链换域，常数依 libplacebo）。
- 参考实现①主机 libplacebo：`ffmpeg -vf libplacebo=format=gbrpf32le:...tonemapping=clip:gamut_mode=clip:...`（n7.1.3 + dvtest 补丁重建，`/tmp/mkffdv`）。
- 参考实现②DoViBaker：`p5_frame_host`（avisynth+libdovi 重建，输出与 9/25 记录 SHA 逐一相同：帧 240 `f26a086d…`、帧 500 `4ba828ea…`；RPU bin `cde508e9…`、YUV 帧 `df7a9dd5…`/`c68aa841…` 全部与记录 SHA 一致）。
- 设备读回：隔离 mpv（c025cbf + 8370 浮点读回补丁）arm64 重建，`p5_offscreen/native/float/post_rpu_full_dump=1` + `p5_target_pq=1`，PTS≥10 一次性整帧 66,355,200 字节 half-float RGBA；目标参数经日志核实 repr=RGB(12)/prim=BT.2020(6)/trc=PQ(12)/max_luma=1000。

## 重建细节（资产曾于 9/30 清理中被删，本次全部恢复）

- DoViBaker 上游 `erazortt/DoViBaker@ffba398` + dovi_tool 子模块 `83e1fdad`（含 capi cdylib 重建）+ 归档补丁中的 `AvisynthEntryP5.cpp`/`p5_frame_host.cpp`；输出 bit 级复现。
- 主机 libplacebo 参照：FFmpeg n7.1.3 重新克隆 + 归档 dvtest 补丁（`max_luma=1000` + DVTEST 日志）。
- 设备 libmpv：c025cbf 源码（Goodwu/mpv 远端克隆）+ 归档 8370 VO 补丁（手工去重 c025cbf 已有的 `p5_sdr_color_map`）；构建前缀重建（/tmp/media-kit-prefix-clean-2197 库 + 补齐被清理的 FFmpeg/libplacebo/libass 头文件与 pkgconfig，libplacebo 头取自 Goodwu fork `optimize/dovi-linear-decode` 分支 c9fd879）；链接补 `-lc++_shared`（stringstream vtable 未解析问题）；JAR 同步替换 NDK 27.2 的 libc++_shared.so。
- 素材：Sol Levante 2160p P5（Dolby LFS 重下，SHA `dacfd045…` 与记录一致）推至设备 `/data/local/tmp/media-kit-p5-sollevante-2160p.mp4`。

## 包与证据

- 读回轮（每轮恢复原 12492/自动亮度/熄屏、清属性与 dump）：12666（Sol f240 mediacodec）、12668（Sol f504 seek 21s）、12669（copy 模式）、12670（4K50 f500）、12671（软解）；日志/浮点帧 `/tmp/media-kit-p4-float-*`；主机参照 `/tmp/media-kit-host-f240-gbrpf32le.bin`、`/tmp/media-kit-host-4k50-f500-gbrpf32le.bin`；比较脚本 `archives/experiments/tools/p5_device_dovibaker_compare.py`。
- f504 seek 轮确认 dump `pts=21.000000`（探针为一次性 pts≥10 触发，seek 用整数秒 define——`AUTO_SEEK_TARGET_SECONDS` 是 int，20.833 解析失败回退 -1 已踩坑记录）。

## 边界

- 软解轮 dump 触发在帧 241（PTS 10.0417），对照参考为帧 240——同镜头相邻帧，其内容差构成残差下限，但不影响「无系统性偏置」的结论方向。
- 回归对已验收路径的影响：P0/P1/P2 全部人工验收均在含此偏差的渲染上通过（中等暖/冷偏移，无参考并排时不易察觉）——人工通过不推翻本数值发现；修复后需复跑 P0-P2 视觉验收。
- 根因（定制 RPU 挂载 vs 硬解 YUV）未定；DoViBaker 链末级 HPE 矩阵借用 libplacebo 常数（同 9/25 边界），不构成完整独立 Dolby golden。
