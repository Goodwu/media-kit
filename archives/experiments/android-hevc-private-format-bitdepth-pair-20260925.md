# 华为 HEVC PRIVATE Surface 8/10-bit 格式对照（2026-09-25）

## 目的与合同

检验同机同解码器、同尺寸/帧率/图案、相同 ImageReader PRIVATE/usage 下，8-bit 与 10-bit 输入是否得到相同 AHardwareBuffer 格式。此实验只判断格式选择与位深的关联，不解析私有 plane，也不测试 P5 实时播放或颜色。

设备 LYA-AL00 / Android 10；解码器固定 `OMX.hisi.video.decoder.hevc`。FFmpeg `testsrc2` 640×360、24 fps、24 帧分别用 libx265 编码为 HEVC Main `yuv420p` 与 Main10 `yuv420p10le`，MP4 `hvc1`。输入 SHA-256 依次为 `5a05fa615fe693a2d923649e537ac8ccb060485ce11916b380b1ddfd22709d14`、`2a2b73e87a41f9e70404531c109217509c5d48912b7a84342f59db3d0ef4bf7f`。探针源码 `artifacts/android-hevc-private-format-pair/FormatProbe.java`，SHA-256 `ee8c8eea786719e6654167705720ec23a2ae6278721aa10aba9a6569a7a2626e`。编为 API29 dex，以 `app_process` 运行；ImageReader `PRIVATE`、maxImages2、usage `GPU_SAMPLED_IMAGE | CPU_READ_RARELY`，逐帧释放 Image。

## 结果

| 输入 | codec报告的 color-format | AHB format | 8张Image | usage |
| --- | --- | --- | --- | --- |
| Main 8-bit | 781 = `0x30d` | 781 = `0x30d` | 全部相同 | 10498 |
| Main10 10-bit | 805 = `0x325` | 805 = `0x325` | 全部相同 | 10498 |

两轮均得到PTS0至291666μs的连续8帧，`Image.getFormat()`均为PRIVATE(34)，Image纳秒timestamp与输出PTS逐帧匹配。原始输出 `artifacts/android-hevc-private-format-pair/main8.txt` SHA `42d80f5e09335e8077ede0b2890613d8d7a792722c6b88012975cbed9d303619`；`main10.txt` SHA `ad7ea34e06e7c87553c730222f04b7163357f3750ef2037bc55f6b4d4ec334c5`。

**本机这组同条件样本表明 `0x325` 与 Main10 输出相关，而不是所有 HEVC PRIVATE buffer 的通用编号。**这比单看 P5 输出 `0x325` 更有判别力。它仍不定义 `0x325` 的线性/压缩 backing、10-bit 打包方式或 `0x324` 的最低位含义；不能把两个不同输入产生的差异解读为精确格式规范。此前 gralloc 静态核对表明 `0x324/0x325` 单独注册，HFBC 另有内部条件标志，见 `android-p5-gralloc-0325-static-audit-20260925.md`。

## 边界与后续

本次样本尺寸640×360，非4K50 P5；无RPU且内容为合成图案。验证 `0x325` 在P5上是否HFBC/linear，仍需要同一输入上的可控layout条件与可观测的厂商handle/日志。P5 GPU与软件参考的局部整数差异仍需分离解码器Surface输出和OES采样。探针只读；设备与主机 `/tmp` 小样本和jar已清理，项目归档保留源码和输出文本。
