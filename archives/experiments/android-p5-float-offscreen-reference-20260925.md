# P5 浮点离屏颜色对照门禁（2026-09-25）

后续三层测试合同见 `android-hdr-dv-three-layer-test-plan-20260925.md`：本文件 8370 `pl_render_image_mix` 后读回是 L3 指定目标结果，L2B/L2C 需要另设映射前读回；即使两端 L3 工程参考一致，也不自动成为 Dolby 标准输出。

用户指出 mpv HDR screenshot 存在已知限制：[mpv #15107](https://github.com/mpv-player/mpv/issues/15107)；[mpv 手册](https://mpv.io/manual/stable/)还区分使用当前 VO 的 `--screenshot-sw=no` 与可能缺少 HDR 渲染能力的软件截图。因此既有 P5 `window` PNG 对手机 RGBA8 读回、Netflix VDM 或 DoViBaker 的数值比较，只保留为路径差异/同画面诊断；截图文件不作 DV renderer 的颜色真值，也不能据其残差判定手机、libplacebo 或母版有误。此前的原始 P5 YUV10 同帧参考与 RPU 结构核查不依赖 mpv screenshot，结论不受此限制。

现有隔离源码 `/tmp/media-kit-mpv-clean-2194/video/out/vo_gpu_next.c` 的 `p5_offscreen_native` 在 `pl_render_image_mix` 后能用 `pl_tex_download` 读回整帧，但其 FBO 被硬编码为 4×8-bit UNORM；`p5_post_rpu_full_dump` 也只写每像素 4 字节。这不是所需 RGBA16F 观察点。下一轮在隔离构建中把目标改为可渲染、可读回的 RGBA16F；如果 GLES/驱动不支持，应明确失败而不是回落 RGBA8。保存原始 half-float buffer、字节序、行序、宽高、PTS/帧索引、源 MP4 SHA、BL 解码帧 SHA、RPU SHA、libplacebo/FFmpeg 版本和全部目标色彩参数，并由主机转为 float RGB 后做比较。整帧读回仅用于暂停单帧实验，不能作为播放性能样本。

优先选固定 BT.2020/PQ/full-range、1000 nit、clip gamut/tone mapping、无 ICC/LUT/抖动的母版域输出；另立 BT.709/BT.1886 SDR 目标试验。输入使用同一个 P5 码流的 FFmpeg 软件 HEVC 基层与同索引 RPU，连续解码至目标帧，显式核 PTS、尺寸和原始 YUV hash；不以播放器 `time-pos` 或截图文件名代替解码帧身份。先做同实现/同配置的可重复性与渲染数值比对，再用 DoViBaker 同基层帧作交叉实现诊断。DoViBaker 与当前比较脚本共享 FFmpeg、RPU 及末级 libplacebo 常数，不能称完整独立 Dolby 真值。

Netflix VDM TIFF 只能在可证实同版母版、坐标/P3/PQ/精度统一后充当母版域参考；当前虽已核对 P5 RPU 与 XML 全片 metadata 关系，压缩图像是否出自同版母版仍未知。Dolby CM Offline 的固定 target 输出可以作为 Dolby 显示映射参考，但现无该工具/golden，而且 libplacebo 未执行 Level 2 trim；不得设逐像素 Dolby CM 相等为现实现的通过阈值。离屏数值通过后，Android HDR dataspace、合成、实际亮度与真人可见播放仍是独立门禁。

## 8370 真机浮点读回

隔离 mpv 的默认关闭开关 `debug.media_kit.p5_offscreen_float=1` 将原尺寸离屏 FBO 改为 `PL_FMT_FLOAT`、4 通道、16-bit host 表示，并要求 `RENDERABLE|HOST_READABLE`；找不到格式就报 bootstrap 失败，不回退 RGBA8。`debug.media_kit.p5_target_pq=1` 为 P5 显式设 BT.2020/PQ、1000 nit。整帧 dump 按每像素 8 字节写 half-float；九点读回和周期检查也改为对应 8 字节。所有新开关默认关闭，代码只在隔离 `/tmp/media-kit-mpv-clean-2194` 中，累计诊断补丁见 `android-p5-float-offscreen-8370-vo-gpu-next.patch`（包含既有 VO 探针，并非可直接并入产品的最小补丁）。arm64 `ninja libmpv.so`、APK zipalign/签名/验签及隔离源码 `git diff --check` 通过。

8370 APK `/tmp/media-kit-p5-float-8370.apk` SHA-256 `ba44a41cd23621b729ea40ef935ae4df4f76698d92e3a0b5599442532abfede2`，包内 strip `libmpv.so` SHA-256 `82f432d0a43c630d440bb5b8a0ecc6fa90ab51cd6e066f1d85402be61bb9e94c`。使用同一 4K/50fps P5 源 `/tmp/media-kit-DV-P5.mp4` SHA-256 `328cae5c78ba9b8e579e7352edcfb8f3e9e0c0670849fc8773a8b028d2d1d03e`，手机 MediaCodec/packed10/`1020/1023`/RPU，**不是 FFmpeg 软件解码输入**。在 PTS 10.000（RPU size206/hash `907c8b42`）日志记录 `fmt=rgba16hf host_readable=1`、目标 `repr=RGB(12), primaries=BT.2020(6), transfer=PQ(12), max_luma=1000`、无 ICC/LUT；`pl_render_image_mix` 成功，九点下载均成功且 GL error0，整帧 3840×2160×4×2 = 66,355,200 字节下载/写出均成功。

原始文件 `/tmp/media-kit-p5-float-8370-pts1000.rgba16f` SHA-256 `7f5f5154ab14fbce3d77dc4110ac25830c403b43be5839591c15532b441c157d`。按 little-endian half-float、3840×2160×4 解释，整帧均为有限值；日志九点的 36 个 half bits 与文件相应坐标 36/36 完全一致，抽样 alpha 全为1。每8像素抽样的 RGB 中位数约 `(0.3904,0.4133,0.4741)`，只作文件完整性检查，不作颜色正确判断。压缩日志在 `artifacts/android-p5-float-offscreen-20260925-8370-logcat.txt.gz`。采集后把日志中 `uint8_t[8]` 转 half 的类型重解释改为 `memcpy`，隔离源码再次编译通过；此清理版**未重新上机**，累计 VO 补丁 SHA-256 `82b282764c9697431d0aacb0b9b8745d724de83a0a03eca87cd8d003947d6277`。

本轮已证实该手机 GLES/libplacebo 路径能在 P5 RPU 后直接提供原尺寸 RGBA16F 数值观察点，绕开 mpv screenshot 文件、OS 合成与截图编码。**尚未与同压缩帧 FFmpeg 软件解码→libplacebo 输出或独立 Dolby golden 对比，不能判 P5 最终颜色通过**；当前 DoViBaker 第240/500帧参考属于另一段官方 Sol Levante 4K/24fps 文件，不能直接对本轮 4K/50fps 帧作数值比较。离屏每帧强制 `pl_gpu_finish`，本轮 VO 掉帧也不能用于性能判断。

采集后强停应用、删除手机上的66MB临时读回文件、将本轮10项调试属性归零，并重装基线10369；回读 `p5_offscreen_float=0`、`versionCode=10369`、无应用进程。原始测试源保留其既有位置。后续已用**同一压缩文件**建立 FFmpeg 软件基层和对应 RPU 的主机离屏 float 工程对照，坐标/误差/尚未锁同的内部 policy 见 `android-p5-float-host-sameframe-20260925.md`。

同压缩源的 FFmpeg 9.0.2 软件解码第500帧/PTS10.000 原始 YUV420P10 已按既有命令重新生成：`/tmp/media-kit-p5-sw-n500.yuv` 24,883,200字节、SHA-256 `8a41d06c8b14a313864d04907bf3cca667d6f732fa2b2db281d105c3b833fe44`，与历史同帧参考哈希一致。它可固定下一轮输入身份，但**只有 BL YUV，不是 RPU 后 RGB 标准**。
