# HDR10 Texture：固定 mpv 版本的 Reader 3/5 对照（2026-09-25）

## 结论

华为 LYA-AL00、同一 HDR10 4K 源、同一测试页及同一 mpv `32a164cc` 源码/构建依赖下，`AImageReader_newWithUsage` 的 `maxImages=3` 可使厂商 HEVC 解码器在输出端口重配置时降到 17 个 buffer 并继续播放；改回 `5` 时请求 22→19 个 buffer 均被拒绝（`-1010`），硬解失败。这个同构建反向对照把容量变化确立为本设备上该故障的有效修复候选，不等于已完成产品依赖、10-bit 数值、颜色或长期播放验收。

## 构建身份与限制

- 干净 mpv worktree：`/tmp/media-kit-mpv-upstream-reader3`，基线提交 `32a164cc017acab50389f2194f720ccfd0b01a28`。应用固定依赖 v1.2.7 的两项原发布补丁 `mpv_lavc_set_java_vm.patch`、`mpv_fence_leak-fix.patch`；`3`/`5` 两库只改 Reader 常量。
- 链接的 `/tmp/media-kit-prefix-clean-2197` FFmpeg 静态库含历史诊断探针引用，原始干净 mpv 库因缺 `media_kit_stage_probe_enabled` 在 11070 装载失败，**该轮无播放结果**。两有效库在 `player/client.c` 共同定义默认 false 的探针布尔量以满足该链接依赖。因此 A/B 的单变量成立，但并非与正式 v1.2.7 FFmpeg 二进制完全一致；要进入产品还须用无诊断 FFmpeg 重建。
- Reader=3 `libmpv.so` SHA-256 `9f6b847a63bf3418bc56501d66e9bf76c9529bfdb194b4eedd164f33d24ea519`，JAR SHA-256 `ba3bd56df854155e571088ce7af139727fb7b0c28300f7383caa010898918fd0`。Reader=5 JAR SHA-256 `59cb7dace93e2476cd647c1f7568ed04d28ebc20b564a5ae07225fba271ade12`。JAR沿用固定包中的 Android helper，仅替换 arm64 `libmpv.so`。
- 测试包 11072/11073：HDR10 `/data/local/tmp/media-kit-hdr10-full.mp4`，Texture、`gpu-next`、默认直 `mediacodec`、目标宽1440、10秒性能采样。构建命令及 Gradle 本地 JAR SHA 留在 `/tmp/media-kit-hdr10-clean-max{3,5}-build-1107{2,3}.log`。两轮仅版本号与本地 JAR 有别。

## 真机结果

| 轮次 | 输出端口协商 | 运行证据 |
| --- | --- | --- |
| 11072 Reader=3 | 请求20/19/18均`-1010`，17 buffer分配并重新启用端口 | `pixelformat=mediacodec`、BT.2020/PQ；t28 `time-pos=1.001`、t60 `33.033` 秒，VO/decoder报告掉帧均0；两张相隔20秒的屏幕视频ROI SHA不同且有可辨认内容。启动一次 `acquireLatestImage=-30001`。 |
| 11073 Reader=5 | 请求22/21/20/19均`-1010`，`amediacodec` IllegalStateException/硬解输出失败 | t28 `time-pos=0.378` 秒后读到 `pixelformat=yuv420p10` 软件回退；未得到成功直解证据。 |

日志和 11072 截图位于 `artifacts/android-hdr10-clean-reader-ab-20260925/`。截图 ROI `(0,370,1440,1090)` RGB SHA-256 分别为 `f9dbf6d99513e53c9992a8b543ba7b93169ed2faae5e845792066994194b8d28` 和 `aa1e4b793f0a24c80ddcc2149934f82028e6c8b0221a2f86fe5ec3af518266bf`。两截图只证采样画面变化，不证逐帧 present 或颜色正确。

## 后续门禁

1. 用固定发布依赖对应的无诊断 FFmpeg/libplacebo 构建 Reader=3 产品候选，核对动态符号、APK实际so身份并重复 HDR10/P8.4 Texture。
2. 解释/处理启动 `acquireLatestImage=-30001`；验证 AHB 格式与经 GPU 采样后的 10-bit 数值、SDR 转换颜色和实际显示链。
3. 做长播、生命周期及用户可见验收；不能将当前约 33 秒进度/两张截图推广为稳定或色彩通过。

实验结束已 force-stop、清理测试暂存，并重新安装基线 `versionCode=10369`；mpv worktree 当前恢复 Reader=3 源码与产物，未改项目发布依赖。
