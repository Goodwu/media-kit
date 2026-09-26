# P5 packed10 色度相位真机 A/B（2026-09-25）

承接 `android-p5-error-raw-chroma-20260925.md`。输入仍是同一 4K50 P5 文件、PTS10.000、RPU 大小 206 字节且 FNV-1a `907c8b42`。手机 8370 原路径将 `GL_EXT_YUV_target` 的 RGB 三分量在同一 `uv` 读出，存入 packed10 4:4:4 中间纹理；FFprobe 报告原码流 `chroma_location=left`。本轮仅给隔离 mpv 的 packed10 shader 增加默认关闭的 `debug.media_kit.p5_raw_chroma_left_probe=1`：奇数 X 的 Y 仍按原 UV 读取，Cb/Cr 从右移一个输出像素的 UV 读取，偶数 X 不变。这是采样相位诊断，不是已确认的规范修复。

arm64 `ninja libmpv.so`、zipalign、APK 签名与验签通过。8372 APK SHA-256 `b5c092ff437106438bd1e884995426119e25a2eca08b72f2082db874d336aebf`；累计 mapper 补丁 `android-p5-chroma-left-8372-hwdec-cumulative.patch` SHA-256 `1feaf3605755cf38102cd19c715862b9170aa9cfb735ef367a9edadfe62f1e2d`，包含之前的 raw mapper 诊断改动，不能直接当产品最小补丁。诊断配置同时启用 raw YUV、packed10、`1020/1023` 缩放、RPU 和 BT.2020/PQ/1000nit 的原生大小 RGBA16F 离屏读回。`P5_POST_RPU_FULL` 确认 PTS10.000、3840×2160、66,355,200 字节完整写出；新缓冲 SHA-256 `5e2f9b44230d73fc704acffed38273183dfb0981dc0a31b401ef4f57863ffd0a`。主机对照为 libplacebo 7.365.0、原始 `left` 解释的同帧 `gbrpf32le`，SHA-256 `b3c58d4be3f3db9580c8829605e8466937cfb2cd90f17f79c46b281424510d36`。比较按手机 GL 下原点与主机上原点转换，未配准或拟合。

| 手机路径相对主机 left | R/G/B MAE | R/G/B P99 | R/G/B 超过 .01 的分量数 |
| --- | --- | --- | --- |
| 8370 原路径 | .000617 / .000315 / .000813 | .008789 / .003662 / .010498 | 68,882 / 13,731 / 90,308 |
| 8372 奇数列色度右移一像素 | .000345 / .000209 / .000464 | .000977 / .000488 / .000977 | 4,403 / 10,258 / 2,047 |

结果支持色度相位解释了绝大多数大尾差。仍有局部边缘残差：最大 R/G 差位于 `(2577,938)`，分别 .0942/.1766；最大 B 差位于 `(1985,1002)`，约 .3157。不能把全帧 P99 改善解读为整帧颜色通过，也不能将同版本 libplacebo 主机输出提升为 Dolby 官方参考。`artifacts/android-p5-chroma-left-8372-vs-hostleft.json` 保存完整统计，`artifacts/android-p5-chroma-left-8372-keylog.txt` 保存关键 PTS/RPU/写出日志；完整手机缓冲暂存 `/tmp/media-kit-p5-chroma-left-8372-pts1000.rgba16f`，未复制 63 MiB 入仓。

下一步用已知色度边缘和明确定义的 left siting 样本校准奇偶列，再对剩余边缘加入 L2C 与采样坐标检查点；确认后才考虑产品代码修正与性能测试。实验后强停应用、11 个诊断属性回读均为 0，重装并核验手机基线 `versionCode=10369`，无应用进程。
