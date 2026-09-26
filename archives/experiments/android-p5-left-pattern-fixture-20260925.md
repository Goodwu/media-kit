# P5 `left` 色度边缘测试片准备与入口门禁（2026-09-25）

从用户提供的 `DV_TestKit_v1.zip` 的 256×144、24fps、24帧无损 P5 合成图案出发。其构造脚本按 2×2 左上角对齐的色度块生成 YUV，原 HEVC VUI 却标为 `center`。本轮在临时副本中只用 FFmpeg `hevc_metadata=chroma_sample_loc_type=0` 将 VUI 改为 `left`，再按 packet copy 循环 13 次，使当前真机离屏读回门槛 PTS≥10.000 可命中；未重编码基础层或重新生成 RPU。首次循环 remux 丢了 MP4 的 `dvcC` 配置，尽管逐帧 RPU 仍在，应用因此报 `Video profile mismatch: expected=5 actual=`；该版本废弃。最终版用包内 `patch_mp4()` 补回 P5 `dvcC`/`dvh1`。生成文件 `artifacts/android-p5-left-patterns-loop-20260925.mp4` SHA-256 `74c2cfb6b28095c4bb3b95a57507de699bb8141d62feaedbcb20b964d51a0a98`，校验清单在同名 `.json`。

本机 `ffprobe` 确认 256×144、yuv420p10le、`chroma_location=left`、`dvh1` 且有 DV stream config、13秒/312帧；312帧均带 Dolby Vision metadata，第240帧 PTS10.000。FFmpeg 软件解码的312帧每帧均与包内原始24帧循环对应的整数 YUV 逐字节相同。第0帧 y=100 的色度边缘例子：luma x=30 的 `(Y,Cb,Cr)=(425,463,513)`，x=32 为 `(280,589,575)`；x=62 为 `(280,589,575)`，x=64 为 `(334,367,590)`。这些已知整数样本可用于判定 4:2:0→4:4:4 采样相位；尚未证明手机应采用哪种滤波器或边界处理。

原8372 APK 的 SHA 白名单曾拒绝派生文件；本轮已在测试应用的样本身份表显式登记最终 SHA 为 P5 诊断样本。Flutter 测试应用使用 OpenJDK17 构建 arm64 Release；isolated mpv 仅将原生离屏读回的 `>=3840×2160` 门槛放宽到 `>=256×144`，使同一 `rgba16hf` 检查点能用于小图案，不是产品默认行为。8375诊断 APK SHA-256 `afa83418c2f2b8c123a815f7f5b8f49e9b72b83a328314e1bb523c2625580d77`，实际 versionCode10374、签名校验通过。两次分别将 `debug.media_kit.p5_raw_chroma_left_probe` 设为0/1，其余属性、APK、文件固定。日志均确认 `AndroidHdrSample.dolbyVisionP5`、256×144 `rgba16hf`、PTS10.000 RPU size237/hash`969415b7`、294,912字节完整读回；关键日志为 `artifacts/android-p5-leftfixture-8375-keylog.txt`。

主机用 FFmpeg n7.1.3 + libplacebo7.365.0/MoltenVK，原输入 `left`，BT.2020/PQ/1000nit、clip/clip、peak检测关闭，输出同PTS10.000的256×144 `gbrpf32le`。测试专用 target 补丁为 `android-p5-leftfixture-host-target-20260925.patch`，不是产品配置。手机 RGBA16F 是 GL 下原点，比较时转换到主机上原点；未做平移、裁切、曝光拟合。三个原始缓冲和两份完整比较 JSON 已归档于 `artifacts/android-p5-leftfixture-*`。

| 相对主机 `left` | R/G/B P99 | R/G/B 最大绝对差 | R/G/B 超过 .05 的分量数 |
| --- | --- | --- | --- |
| 手机原路径 | .06763 / .05893 / .03708 | .40698 / .28662 / .48340 | 402 / 393 / 324 |
| 手机奇数列色度右移探针 | .01199 / .01160 / .01147 | .01408 / .01370 / .01384 | 0 / 0 / 0 |

边缘 y=100、x=31：主机RGB约`(.5381,.3677,.3635)`，手机原路径`(.4309,.4309,.4319)`，探针路径`(.5376,.3674,.3635)`；x=63、95也呈同方向改善，而紧邻偶数列保持原读数。它支持当前 packed10 4:4:4 prepass 对 `left` 色度的奇数列相位有误。探针仍只是工程候选：主机 libplacebo 是工程参考，手机和主机还存在约.012的P99残差，需L2C/原始采样检查点确认剩余差异、裁剪和滤波边界，之后评估额外采样带来的4K50性能成本。

实验时曾暂时用该小文件替换固定自动源；已强停应用、恢复源文件 SHA-256 `328cae5c78ba9b8e579e7352edcfb8f3e9e0c0670849fc8773a8b028d2d1d03e`、以`adb install -r -d`重装手机10369基线并将11项诊断属性回读为0。原始 `/data/local/tmp/media-kit-p5-full.mp4` 也恢复同SHA，应用无运行进程。
