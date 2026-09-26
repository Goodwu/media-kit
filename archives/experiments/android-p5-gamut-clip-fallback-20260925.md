# P5 Android GLES 色域映射回退诊断（2026-09-25）

## 结论与边界

隔离构建的 libplacebo 7.365.0 仅把 `pl_shader_color_map_ex` 在找不到四分量 16-bit 线性 UNORM 格式时的回退函数从 `pl_gamut_map_saturation` 改为 `pl_gamut_map_clip`。同一手机、P5 原片、PTS10.020、3840×2160 RGBA8、BT.709/BT.1886 目标下，整帧与主机同源 libplacebo 7.365 窗口图的 RGB MAE 从基线 `(22.0987,1.6443,4.0848)` 降到 `(1.0646,0.1504,0.4758)` /255；三通道 P95 为 `(3,1,1)`，平均有符号差 `(-0.8754,+0.0745,+0.2867)`。PTS10.000 的九个点与主机 BT.709 图最多差 1 级。与主机目标 BT.2020 图的 MAE 反而为 `(23.1956,1.7489,4.6428)`。这支持原路径缺格式时的 saturation 回退抵消了预期的 BT.2020→BT.709 数值转换，修改后输出与 BT.709 主机目标高度吻合。

这属于**诊断性因果证据**，不能单独证明所有像素的真实显示色彩、HDR 亮度或实时播放性能正确。主机 Vulkan 窗口截图与手机 GLES 离屏 FBO 尚非完全等价，尾部极值仍大（RGB 最大差 `79,47,131`）；逐 360 行统计显示 `>10` 级差异集中在 y=720–1439 的细节区域，顶部 y=0–359 和底部 y=1440–2159 没有这类像素，需再检查其内容/边缘及原因。`clip` 回退可能牺牲原先期望的色域映射策略，不能未经画质/性能验收就把全局 libplacebo 改动作为产品修复。

## 构建与复现

- mpv 隔离源码：`/tmp/media-kit-mpv-clean-2194`，有 P5 packed10/RPU 管线及临时源/目标/整帧读回探针；项目默认构建未接入。
- libplacebo 隔离源码：`/tmp/media-kit-libplacebo-p5-gamut-fallback`，相对原库的单处回退改动见 `archives/experiments/android-p5-gamut-clip-fallback-libplacebo-20260925.patch`。另含前序 GLES `RGB10_A2` 格式注册改动，见 `archives/experiments/android-p5-packed10-integrated-libplacebo-20260924.patch`。
- 初次诊断 APK 首帧报 `Failed mapping iformat 32857` 并崩溃。核对时间戳发现格式注册源码变更晚于新静态库构建；重新运行 Meson/Ninja 只重编 `opengl_formats.c.o` 和库后，重链接 mpv 并重新签包，错误消失。该失败不能用于评价 clip 回退效果。
- 重建 libplacebo 静态库 SHA-256 `965e00a3e74e7bc7081acb46b4a07f3982087dda2dd01351b34aea7c344f7fa8`；剥离后的 libmpv SHA-256 `b44e6f518b1c2ba919cdec0d099d80b6bc1bfbb043286ddd0fd8190b6f931340`；签名 APK `/tmp/media-kit-p5-gamut-clip-8367.apk` SHA-256 `83e99b18d6e2600e86b58d13d8dea35d61daacde14a8b334fcaf53b7008a6283`，`apksigner verify`、`adb install -r` 成功。
- 手机 PTS10.020 日志：源与映射后均 `sys=8` Dolby Vision、`prim=6` BT.2020、`trc=12` PQ、`dovi=1`；渲染源 `prim=6,trc=12`，目标 `sys=12` RGB、`prim=3` BT.709、`trc=1` BT.1886，无源/参数 LUT。整帧下载 `33177600/33177600` bytes。日志 `/tmp/media-kit-p5-gamut-clip-8367-full-logcat.txt`；RGBA `/tmp/media-kit-p5-phone-gamut-clip-8367-pts1002.rgba` SHA-256 `a7a91e4bdcb13cee62883711ae2adc51b449a18f73d24ed3cba4f248550045d7`。基线手机、主机 BT.709/BT.2020 原尺寸样本见 `android-p5-gamut-signature-20260925.md`。
- 设备 `LYA-AL00` / `3EP7N18C28016072`；实验后应用强停，所有当时非零的 `debug.media_kit.*` 属性归零。诊断 APK 留在设备，但当前进程不运行。

## 下一步

用可配置、仅 Android GLES P5 作用域的色域策略替代全局库改动；记录运行时 `pl_find_fmt` 选择及实际 shader 路径，检查极值差位置和原因，再做没有整帧下载/大量日志的持续播放帧节奏、可见色彩及 HDR 亮度验收。全图数值吻合不等同这些验收。

## 作用域收敛复验

随后在同一隔离构建将库改成：无 16-bit 线性 LUT 格式时，仅**显式**选择 `pl_gamut_map_clip` 的调用保留 clip；其他方式继续原有 saturation 回退。mpv 只在 Android/OpenGL、当前帧有 DV 元数据且 SDR 目标 TRC 为 BT.1886 时，对这一帧的 `pl_render_params.color_map_params` 临时副本显式选 clip；不修改共享的默认参数，也不改变非 Android 或 PQ 目标分支。变更分别见 `archives/experiments/android-p5-gamut-scoped-libplacebo-20260925.patch` 与 `archives/experiments/android-p5-gamut-scoped-mpv-20260925.patch`（后者相对本次隔离 mpv 诊断源码）。此处 `dovi` 是诊断代理条件，尚需产品 P5 身份/路由进一步收紧。

签名 APK `/tmp/media-kit-p5-gamut-scoped-8367.apk` SHA-256 `eda0a5453290fbf9def7fe009f4beb15543388b5f1a54071958398c764f89c8d`，安装与 P5 整帧读回成功，无 `iformat 32857` 错误或崩溃。该轮命中 PTS10.000（不同于上一轮 PTS10.020），手机 RGBA `/tmp/media-kit-p5-phone-gamut-scoped-8367-pts1000.rgba` SHA-256 `f59f0de2c4d7f431e0b6c82d2e2fc8ec0fe9eb1be6d66caf8247ecc3df5ac210`，与主机同 PTS BT.709 图的 RGB MAE 为 `(0.9717,0.1509,0.4708)`/255、P95 `(3,1,1)`。日志 `/tmp/media-kit-p5-gamut-scoped-8367-logcat.txt`。这支持作用域收敛后数值特征保留；仍未对非 P5 运行时路径、可见输出和帧节奏验收。设备再次强停，诊断属性归零。

## 参考素材充分性与新增官方样片

主机 mpv 截图不是独立的 Dolby 色彩真值：它和手机路径共享 FFmpeg/libplacebo 的 DV 解析与映射实现；上述比对证明路径一致性，不证明二者都正确。Dolby Laboratories 公开的 [dolby-vision-contents](https://github.com/DolbyLaboratories/dolby-vision-contents) 仓库包含 Sol Levante Profile 5 BL+RPU 样片。已取得其中 1080p/24fps 文件 `/tmp/media-kit-dolby-official-p5-1080p.mp4`；141871521 字节，SHA-256 `87fe0115f3002a621d2380a9f91852ef91a15854a446efe26de8744f77ef5346`，与 Git LFS 声明一致；ffprobe 确认 HEVC/dvhe、1920×1080、24fps、263.083333 秒、DV profile 5/compatibility 0。现用片为 3840×2160/50fps，故官方样片可检验素材普适性和更低分辨率路径，但仓库未提供逐像素 SDR/HDR 标准输出。仍需独立可信的 Dolby 参考渲染/已标定显示或带明确预期值的测试图样，不能把“官方样片”直接称为“标准答案”。

独立参考再筛查：当前华为机的 Display HDR type 记录为 `[2,3]`（Android 定义分别是 HDR10、HLG；Dolby Vision 为 `1`）；运行时 MediaCodecList 与系统/vendor codec XML 未发现 `video/dolby-vision` 解码器，只有 HEVC 视频解码器。这只说明该机**未声明**原生 Dolby Vision 显示/解码能力，不排除未公开厂商路径，但不能把同一手机的原生播放当 P5 真值。公开的 [DVS Profile 5 测试图样页](https://diversifiedvideosolutions.com/dolby-vision.html) 有免费 demo 下载和灰阶、色条、色域图样说明，可用来观察灰阶/裁切/明显色偏；页面及[说明书](https://diversifiedvideosolutions.com/Instruction_Manuals/DVS_UHD_Dolby_Vision_Instruction_Manual.pdf)未给出本项目 BT.709/BT.1886 SDR 映射后的逐像素期望值，仍不能作为独立像素真值。优先寻找具有明确目标显示、映射策略和输出数值的独立 Dolby 渲染结果，再冻结 PTS、比较域和容差；在此之前将独立颜色门禁标为 INCONCLUSIVE。

## 可见播放与第二素材复验

- 8367 作用域包关闭离屏全帧探针后以当前 4K/50fps P5 在 TextureView 可见播放。相同进程 18/60/90/120 秒探针的内容时间为 6.74/48.74/78.76/108.74 秒；mpv `frame-drop-count` 为 2/11/26/36、`decoder-frame-drop-count` 始终 0。120 秒时相对约 5437 帧的粗略累计掉帧比例约 0.66%；Flutter SurfaceTexture 消费回调累计 5212（滚动 4096 样本，时间戳未倒退），最大回调间隔 98.4ms。可见截图 `/tmp/media-kit-p5-gamut-scoped-visible-8367.png` SHA-256 `f3a1cf39faf6851df8a64ea024a189b9ae016291fab43c648671f47eb6c31b74`。这些是播放器/消费侧初筛，非 SurfaceFlinger 实际 present、音画同步或人工流畅度验收；`avsync` 属性为空。日志 `/tmp/media-kit-p5-gamut-scoped-visible-8367-logcat-120s.txt`。
- 为维持测试入口按**字节哈希**辨认内容的防误测约束，将官方样片 LFS SHA 明确登记到 `media_kit_test/lib/common/sources/android_hdr_sample_identity.dart` 的 P5 清单。目标 `dart analyze` 与身份测试 5 项通过。第一次 10368 APK 因新本地 arm64 jar 只含 `libmpv.so`、漏 `libmediakitandroidhelper.so` 而启动失败；从先前同包已验证的 arm64 助手库补入后重新 zipalign/签名/验签，最终 APK `/tmp/media-kit-dolby-official-p5-10368.apk` SHA-256 `9ff040ed3f561c4ed925fb4f946561c7eed0c994b2ee171956bc00d82dabd353`，内置 `libmpv.so` SHA-256 `68fffaee57c85c74b811ebb8e0ade76eb1e3b5a2f047edadbd9ed1189f605a28`。补包前失败不算播放结果。
- 官方样片在 app 私有外部目录中由事务入口识别为 P5；`/sdcard/Download` 原路径因 Android 文件权限拒绝，已移入 app 私有目录。作为冷启动固定源再次运行：`ANDROID_HDR_OPEN sample=dolbyVisionP5`、视频 1920×1080、硬解 `mediacodec`，PTS10 `P5_GAMUT_SOURCE` 中源与映射后均 `sys=8,prim=6,trc=12,dovi=1`，`P5_GAMUT_TARGET` 为 `sys=12,prim=3,trc=1` 且渲染成功；没有首帧崩溃/格式映射错误。两张间隔 5 秒的视频区域截图发生大幅变化（RGB 平均绝对差约 115.9/97.2/62.4），说明该段持续输出不同可见图像；不证明 24fps 节奏或颜色正确。冷启动日志 `/tmp/media-kit-dolby-official-p5-10368-cold-logcat.txt`；两张截图 SHA-256 `fe84b5f4761ac5d833db8912fef699197967ba38a1b3e84ad8056774c7b01d1d` / `dae0641db29ec8aae7495c82bde6891f04380ff2a5826fe952eb20c64fd183aa`。

## 官方 1080p/24fps 样片连续播放初筛

为补上述帧节奏空缺，使用相同隔离 libmpv（APK 内 `libmpv.so` SHA-256 `68fffaee57c85c74b811ebb8e0ade76eb1e3b5a2f047edadbd9ed1189f605a28`）重建只新增固定官方样片源、`MEDIA_KIT_ANDROID_PERF_PROBE=true` 与 Texture 消费探针的 10369 测试包。补齐与 10368 同源的 arm64 helper 后 zipalign/签名/验签，APK `/tmp/media-kit-official-p5-10369.apk` SHA-256 `16d5dee49934d35730ede289b9fa6b100ded2244ef879d4642c12f260d5dbee6`，设备 `versionCode=10369`。运行设置 P5 RPU/raw、尺度校正、packed10、延迟释放、VO 秒级汇总开关；同一包 Texture SDR 固定官方样片冷启，事务日志识别 P5，硬解输出 1920×1080，容器 24fps。

应用启动后第 8 秒才完成视频打开，故 `PERF t=8 time-pos=0.166667` 不算稳定窗口。第 18/28/60/90/120 秒的内容时间分别 `10.208333/20.208333/52.208333/82.208333/112.208333` 秒，mpv 累计 `frame-drop-count` 为 `2/2/2/2/2`，`decoder-frame-drop-count` 均为 0；第 120 秒 `pause=no`、`eof-reached=no`、`idle-active=no`、热状态 1。相较 4K/50fps 原片在 120 秒累计掉 36，这说明当前低分辨率素材在同机同候选路径下没有持续增长的播放器掉帧；不能把两片的复杂度差异归因于分辨率单因子。第 120 秒屏幕截图仍为完整视频画面，SHA-256 `a24fc0ad9881aeb3d832ffdf35353857c9ff19e28c2049e695ce07c3a4d47b54`；对应末段 logcat `/tmp/media-kit-official-p5-10369-perf-120s.log` SHA-256 `719fb082ad4418ea60641f1b5b4268997b7e344ccd31e62f5524072873274343`。Android logcat 环形缓冲在末段已覆盖早期行，早期采样来自运行时实时读取，不将末段文件误称全程日志。`avsync` 为空、Texture 消费探针报告该 Surface producer 上未启用，且未采 SurfaceFlinger present；本轮仍不是实际显示 cadence、人工流畅度或颜色验收。结束后强停应用，六项新设 P5 属性逐项回读均为 0。

随后用同 10369 包再次播放官方样片，尝试直接获取 SurfaceFlinger 呈现序列。`--list` 能列出 `SurfaceView - com.example.media_kit_test/com.example.media_kit_test.MainActivity`，但对该精确名称执行 `--latency` 只得到 `16666666` ns 刷新周期、没有三列帧时间；`--latency-clear` 后继续播放 5 秒重查仍只一行，包含 `#0` 后缀的名称亦相同。无名称的 `--latency` 返回 128 条全零记录，`--timestats` 没有可读结果。文件 `/tmp/media-kit-official-p5-10369-sf-layers.txt`、`...-sf-latency.txt`、`...-sf-latency-default.txt` SHA-256 分别 `fc009d28cb4e2e24c968cda8023ce0076f13c15c8779c6f9114a53892d33ff4b`、`a46ddbff4d0f23a0b17e93076308de4f7951944b9b21cdd818b4ecb16b7bf3bc`、`4be67fba3cb2fb4299c39f1805d2abe7f8c80ddcdd07dfe1145abb2c10b5325f`。故该设备/图层组合的这些接口不能提供本轮视频 present cadence。Flutter SurfaceProducer 也不暴露当前项目的 `SurfaceTexture.updateTexImage` 消费回调统计（代码明确返回 `reason: surface_producer`）；若改用 `MEDIA_KIT_ANDROID_SURFACE_PRODUCER=false` 可测另一种输出拓扑，但不能直接代表当前默认链路。下一步需在当前 SurfaceProducer/Flutter 实际呈现侧建立可靠帧时间或获取可用系统 trace，再作显示节奏验收。第二轮结束亦已强停应用、五项设定的 P5 属性全0。
- 实验后固定路径上的原 4K 样本已按 SHA-256 `328cae5c78ba9b8e579e7352edcfb8f3e9e0c0670849fc8773a8b028d2d1d03e` 恢复；官方样片另留在 app 私有目录供后续重测。设备应用强停、`debug.media_kit.*` 非零项清零。当前 APK仍为诊断包，不是最终产品版本。
