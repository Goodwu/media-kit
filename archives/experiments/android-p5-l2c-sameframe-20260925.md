# P5 同帧 L2C 编码 RGB 对比（2026-09-25）

同一原始 4K50 P5 文件 SHA-256 `328cae5c78ba9b8e579e7352edcfb8f3e9e0c0670849fc8773a8b028d2d1d03e`、PTS10.000。手机诊断 APK `/tmp/media-kit-p5-l2c-8378.apk` SHA-256 `2ff7db8cbc1c21063357bed4f24abf8c7c66e7f97c7f362f11eea4136c4d7a00`，同一 MediaCodec/packed10/`1020/1023`/RPU 路径，仅切换 `p5_raw_chroma_left_probe=0/1`。关闭相位轮日志确认 RPU size206、hash `907c8b42`；开启轮为同APK/同源且DV输入门禁通过，但本轮保存的筛选日志未单独保留其RPU hash，L2C 下载 3840×2160×RGBA16F=66,355,200 字节，`repr=RGB/full`、BT.2020/PQ、色深/采样深度10。`PL_HOOK_RGB` 在 DV 颜色解码后、显示映射前，数值是 **PQ 编码 RGB，不是线性 nit**。

主机 FFmpeg n7.1.3 软件解码同一码流、libplacebo 7.365.0/MoltenVK，在相同 `PL_HOOK_RGB` 阶段下载 RGBA16F；记录同样 RGB/full/BT.2020/PQ 与 3840×2160，主机输入 DoVi 元数据存在，源标称峰值约1000.61nit。主机只是同实现的**工程参考**，并非独立 Dolby 标准。手机和主机该检查点的缓冲在**相同行方向**直接比较，不平移、裁剪或曝光拟合；手机 L3 导出相对于 L2C 则须翻转 Y。比较脚本 `tools/p5_l2c_compare.py` 已用2×2人工数据验证相等通过、单通道故障定位。

Android隔离 mpv `vo_gpu_next.c` arm64编译/链接通过，链接时暂借带RPU的 FFmpeg `libavcodec.a`，随后前缀库 SHA 恢复为原 `36a68423f6736a4e6f5d0b5ccb2a5081ce78a50de1b3aff3a5e506ece167820f`；诊断 libmpv strip 后 SHA `ac0ed9402385dbe7b75f04c168c5c58f78665b16d706c2aee6b6af3fb2de7126`。APK zipalign/签名/验签及安装通过。隔离 mpv/FFmpeg 的**累计**补丁分别为 `android-p5-l2c-8378-vo-cumulative.patch`（SHA `d6744bce47fbf81b8226f8a5c23d877b7cf3db3f2a7014fcfc1473ede38d29cd`）和 `android-p5-l2c-host-ffmpeg-cumulative.patch`（SHA `b5d1d3a110f929edab816e2deaba2d024f53d396883c4c1b4ad486f187eaf9a0`），不能当产品最小补丁。

| 手机相位探针 | RGB P99 绝对误差 | RGB 最大绝对误差 | 各通道差值>0.01的分量数 |
| --- | --- | --- | --- |
| 关闭 | .008911/.003662/.010498 | .15137/.16577/.39648 | 69,228/14,340/90,457 |
| 开启 | .000610/.000244/.000977 | .09424/.17651/.31616 | 4,860/10,850/2,051 |

开启后任一 RGB 分量差值>0.01的像素仍有12,922/8,294,400，其中 X 偶数列5,805、奇数列7,117；>0.05有188像素。最大 R/G 残差在 `(2577,1221)`，最大 B 在 `(1985,1157)`，部分误差集中在单行或窄列，不能简单归为全局缩放。已归档完整比较 JSON `artifacts/android-p5-l2c-8378-phase{off,on}-host-compare.json`、6组17×17三路ROI `artifacts/android-p5-l2c-8378-rois.npz`、运行日志及隔离源码累计补丁。完整缓冲暂存于 `/tmp/media-kit-p5-{l2c-phaseoff-8378,l2c-on-8378,host-l2c}.rgba16f`，SHA-256 分别为 `fad9ba55fc1115131c1223ad53809982eeac8b99badba34ef034eea9d8907a93`、`1262f6f763841418f33a426532d97097ac6f453655ad416a308ac970f8bac23b`、`b6e3bea4a70f218e7b2cf1c7535fa4c8a5ab7b8e28265c78b42ef7373cd9c8d5`。

**导出扰动**：`PL_HOOK_RGB` 的 TEX 输入会让 libplacebo 提前落一次 RGBA16F FBO。手机同 APK 的 L3 hook 开/关差异P99各通道≤.000488，最大蓝差.02418（>0.01仅6点）；主机 L3 hook开/关P99≤.000488、最大蓝差.00502。主机关闭hook的 L3 SHA `b3c58d4be3f3db9580c8829605e8466937cfb2cd90f17f79c46b281424510d36` 与前次7.365.0工程参考完全一致。上述 hook 扰动须计入误差解释，不能称导出完全无扰动。

此结果将主要相位收益及剩余大尾差定位在**显示映射之前**。尚不能区分残余来自厂商 OES 色度插值、我们的 packed10 取样/边界、DV reshape 或其他颜色步骤；下一步在异常ROI核对映射前raw与已知图案的二维边界，必要时再加L2B观察点。L2C工程参考与 Dolby 官方 golden 不同，最终色彩、HDR信令、长期可见流畅度仍未通过。
