# P5 GPU 原始分量与软件解码参考（2026-09-24）

目标：对先前 8340 包的同 PTS GPU raw FBO 读回，找一条**不共享厂商 GPU YUV sampler** 的原始码流参考。目标机 Huawei LYA-AL00；此轮仅在主机上复核已采集的手机日志，未重新运行手机。

原始 `/tmp/media-kit-DV-P5.mp4` 为 3840×2160、50 fps、`yuv420p10le`，SHA-256 `328cae5c78ba9b8e579e7352edcfb8f3e9e0c0670849fc8773a8b028d2d1d03e`。以 FFmpeg 9.0.2 软件解码第 500 帧（PTS 10.000 秒）的单帧命令：

```sh
ffmpeg -hide_banner -loglevel info -threads 8 -i /tmp/media-kit-DV-P5.mp4 -vf "select='eq(n,500)',showinfo" -frames:v 1 -fps_mode passthrough -pix_fmt yuv420p10le -f rawvideo -y /tmp/media-kit-p5-sw-n500.yuv
```

单帧输出 24,883,200 字节、SHA-256 `8a41d06c8b14a313864d04907bf3cca667d6f732fa2b2db281d105c3b833fe44`；`showinfo` 确认 PTS 10.000 秒，含 Dolby Vision RPU 侧数据。随后从既有 `/tmp/media-kit-p5-pixel-8340-r32f-logcat.txt` 提取 PTS 10–11 秒全部 28 个 R32F 读回帧，用 FFmpeg `select` 按 `n=round(PTS×50)` 软件解码相同源帧，通过管道逐帧读取 `yuv420p10le` 的中心 `(1920,1080)` 样本，避免保存约 700 MB 原始数据。28 帧、Y/U/V 共 84 个对照均满足：

```text
software_10bit_code == round(gpu_R32F_normalized * 1020)
max_abs_difference = (0, 0, 0)；nonzero_count = (0, 0, 0)
```

例如 PTS 10.000 秒，软件 `(415,514,508)`，GPU R32F `(0.406862736,0.503921568,0.498039216)`，乘 1020 后取整也是 `(415,514,508)`；PTS 10.140 秒分别是软件 `(427,520,512)`、GPU×1020 `(427,520,512)`。这已证明**该中心点、该时间段、R32F 路径**在经过固定 `1020` 尺度还原后与独立软件解码的原始 10-bit YUV 代码值逐分量相符，而不是先前推测的邻域插值近似。

同 8340 包先前在 packed10 与 R32F 的精确 PTS 交集 24 帧，packed10 的三个 10-bit 代码值均等于 `round(R32F_normalized×1023)`（72/72，见 `android-p5-packed10-pixel-20260924.md`）。因此 packed10 直接存储的是对 vendor sampler 输出的 1023 级重新量化值，**不直接等于原始码流 10-bit 代码值**；例如 10.000 秒 packed10 `(416,516,509)` 对源 `(415,514,508)`。在这些样本中，从 packed10 按 `round(packed_code×1020/1023)` 可还原源代码值，但这不构成全范围可逆证明。GPU 归一化为何以 1020 而非 1023 为尺度、libplacebo 对 10-bit `sample_depth` 的后续解释是否因此产生可见/数值偏差，尚未查明。

源码检查：`hwdec_aimagereader.c` 的 raw mapper 给 libplacebo 传 `sample_depth=color_depth=10`；`libplacebo/src/colorspace.c::pl_color_repr_normalize` 对全范围、同为 10-bit 的表示返回尺度 1，`libplacebo/src/shaders/colorspace.c::pl_shader_decode_color` 在 Dolby Vision reshape 前调用它。因此**从这些代码推断**，现有链路没有补偿测得的 `1020` 分母，RPU reshape 接收的输入相较标准 `code/1023` 约放大 `1023/1020`（约 0.294%）。这是局部数值与代码路径推断，尚未直接读回 reshape 输出，不能宣称已观察到可见色偏。若多位置/代码值范围仍证实该尺度，raw prepass 可候选乘 `1020/1023` 后再写 packed10；这应使已测中心样本量化回源代码值，但需在设备上按门禁复验，不能立即默认启用。

范围：只测中心坐标、28 个源帧，未覆盖边缘、裁剪、不同代码值区间、RPU reshape 后输出、最终可见颜色或 HDR 激活。此参考针对源 BL 解码的 YUV 分量，不能替代 Dolby Vision 最终画质验收。下一步设计多点/极值对照，再验证默认关闭的尺度校正与 RPU 输出；P5 性能已有独立无探针轮，不用读回包重新计时。

## 九宫格诊断包 8341 无效（同日）

已在隔离 mpv 源 `/tmp/media-kit-mpv-clean-2194/video/out/hwdec/hwdec_aimagereader.c` 加默认关闭 `debug.media_kit.p5_raw_spatial_probe=1`：只在 PTS 10.000 秒对 FBO 的 3×3 点 `(W/4,W/2,3W/4) × (H/4,H/2,3H/4)` 读回，保留原 `p5_raw_pixel_probe` 的逐帧中心点行为。arm64 `ninja` 编译与链接、APK zipalign/签名/验签、包内 libmpv SHA 对照均通过。候选包 `/tmp/media-kit-p5-spatial-8341-arm64.apk` SHA-256 `b719dbb42a48b142425991a51d7dd568b214cf2dcff80836aafa6cbce1899007`，libmpv SHA-256 `dd53e000419661353207e222285b6dfec8a0ce7219c0e219c5a5182ad5bb3e2b`。

安装后相同 P5 页面与属性 `p5_rpu_probe=2,p5_raw_yuv=1,p5_raw_mrt=1,p5_raw_pixel_probe=1,p5_raw_spatial_probe=1`，视频参数却为 `bt.2020-ncl/bt.1886`，mapper 每帧报 `P5 raw YUV requested without first-frame DOVI metadata`，没有 `P5_PIXEL`；**这不是可用的九宫格对照**。日志 `/tmp/media-kit-p5-spatial-8341-logcat.txt` SHA-256 `7fff87d38f6907d56435e2de70caeedd4853be4d7fba8d7890b9a94425a8054a`。与有效 8340 包的 libmpv 字符串对照发现，8340 含 `MEDIA_KIT_P5_RPU` 逻辑，而当前隔离前缀的 `libavcodec.a` 与 FFmpeg 工作源码不含该逻辑；旧 RPU 补丁在构建仓 `patches/ffmpeg/ffmpeg_mediacodec_p5_dovi_fullstream_probe.patch`，直接 `git apply --check` 与当前 FFmpeg 源已存在的 stage-probe 修改冲突。下一步必须在保留当前 FFmpeg 脏改动的前提下整合 RPU 补丁，重新链接并先确认 `dolbyvision` 帧参数/逐帧 RPU，再采样九宫格。不能以原生编译/安装成功替代有效媒体路径。

目标机已强停并重新安装已验证有效的 8340 APK（versionCode 8340），本轮设置的 P5 属性恢复为 0。8341 未获得有效数值，前文 28 帧中心点结果仍来自原始有效 8340 包。

## 依赖闭环与有效九宫格 8344（同日续）

8341 失败后，用原始 FFmpeg blob、当前含 stage-probe 的脏改和已有 fullstream RPU patch 作三方合并；只有文件头 include 冲突，保留 stage-probe 并补系统属性 include，其他 RPU 逻辑自动合入。当前 FFmpeg 源的原样备份 `/tmp/media-kit-p5-rpu-merge/current-backup.c` SHA-256 `70dca68253d3bcaf4168472357c4a0b7fee5f57801903910ac33dc1fc6f6ba94`。合并后增量构建 arm64 `libavcodec.a`，在隔离 mpv 前缀替换静态归档前备份为 `/tmp/media-kit-p5-rpu-merge/libavcodec-before.a`。8342 首次重链有 `media_kit_stage_probe_enabled` 未定义，APK 安装但 Dart `dlopen` 失败；隔离 mpv 定义默认关闭的同名原子标志后，8343 能识别 Dolby Vision/RPU，但 R32F wrap 无 sampleable、packed10 缺 `GL_RGB10_A2` 的 libplacebo 映射，均不是有效读回。又将已有、包含 packed10/GLES R32F 格式登记的 arm64 `libplacebo.a` 链入隔离前缀（原归档备份 `/tmp/media-kit-p5-rpu-merge/libplacebo-before.a`），重链成 8344。两个外部源码的当前整合补丁为 `android-p5-rpu-stage-merged-20260924.patch` SHA-256 `ba3b8d5b75e813a00c80c46fbf558a487cfd756a8f55f05e1ec581d813c4b1db`，`android-p5-spatial-8344-integrated-mpv-20260924.patch` SHA-256 `fb392965126a0e977a6c9a37d8fc4d5c14a66f5467619ad220c25c59a982094e`；后者包含既有 raw/packed10 基础，不是仅本轮增量。此前的 libplacebo 格式补丁见 `android-p5-packed10-integrated-libplacebo-20260924.patch`。

8344 是本地包标签，APK 内 `versionCode` 仍为 8340；APK `/tmp/media-kit-p5-spatial-8344-arm64.apk` SHA-256 `d64b82a9d6aa73c0e1d5201324f6c45f1a6265b4c152b153deb13f8d32ba1bb7`，包内 stripped libmpv SHA-256 `c18cc9f46f0c8136a9d870f3dc5a007d2535cf473a57dabcab2e0914ccc0e22e`。签名/zipalign/包内库一致性通过。真机同 P5、`p5_rpu_probe=2,p5_raw_yuv=1,p5_raw_packed10=1,p5_raw_pixel_probe=1,p5_raw_spatial_probe=1`，MediaCodec 视频参数为 3840×2160 Dolby Vision/full/BT.2020/PQ，`ANDROID_HDR_OPEN` 成功，PTS 10.000 秒九宫格 GPU readback 均 GL error 0。其余运行属性保持默认，读回会同步 GPU，不能用该轮掉帧评估性能。

将软件第 500 帧按**相同数值坐标** `(x,y)` 索引，九个点 Y/U/V 共 27 个分量全部满足 `packed10_code=round(software_10bit_code×1023/1020)`，差值全 0；同帧上下两行验证 FBO 读回在此路径按日志数值坐标与软件帧对齐，不能机械地再翻转 y。例如 `(960,540)` 软件 `(428,494,438)`→packed `(429,495,439)`；`(1920,1080)` 软件 `(415,514,508)`→packed `(416,516,509)`；`(2880,1620)` 软件 `(475,469,431)`→packed `(476,470,432)`。这把 1020→1023 尺度关系从中心点扩展到同帧 3×3，仍未覆盖其他时间、边缘或极端代码值。日志 `/tmp/media-kit-p5-spatial-8344-packed-logcat.txt` SHA-256 `e8f30211dc538d39866451b4ea9991c7b360a944b7e9e436a676c8a46526f211`；有效轮至 t28 `time-pos=17.06,pause=no,decoder-frame-drop-count=0`，无 `Failed rendering frame`/RPU 首帧门禁报错。R32F 同版尝试两轮在严格 PTS 10.000 单帧探针未采到（VO 已丢帧），不能作为九宫格 R32F 数值证据；日志 SHA-256 分别 `689dfd32d57d601fcf9c8a077f229725aadc1fc2ddefd0a8f621c7394cc2dae7`、`45acbd47ff4741463364eeda5c2aa9836a93aa4fb458e19201f5f33c67e21383`。

设备当前安装 8344 包但应用强停，本轮 P5 相关属性均置 0。此实验仍只验证 raw 中间分量；后续应扩大 PTS/边缘/高亮代码范围，验证默认关闭的 `1020/1023` 校正对 RPU reshape 与最终 SDR/PQ 输出的数值和显示效果。不能将局部一致性或无 GL 错误等同可见色彩/HDR 验收。
