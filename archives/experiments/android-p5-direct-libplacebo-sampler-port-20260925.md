# P5 直采 libplacebo 的 OpenGL sampler 移植门禁（2026-09-25）

目标：为 `0x325 AHB → EGLImage → GL_TEXTURE_EXTERNAL_OES → libplacebo DV shader` 的去 prepass 性能实验准备 raw YUV 取样。当前产品路径先用 `GL_EXT_YUV_target` prepass 写一张 4K `RGB10_A2`，再由 libplacebo 采样；直接融合理论上能省一张全分辨率中间纹理的写入与随后读取，但还须实测4K50成本和颜色正确性。

本机 OHOS 构建仓已有 `support-external-yuv-zero-copy.patch` 及 `hwdec_ohcodec_gl.c`，证明当前源码家族中存在可借鉴的 `PL_SAMPLER_EXTERNAL_YUV` 接线。Android 实验构建仓 `/Users/wuweiwei1/src/libmpv-android-video-build-dv-experiment` 当前 libplacebo 仅将 `GL_TEXTURE_EXTERNAL_OES` 推断成普通 `samplerExternalOES`。据此只移植 OpenGL 所需的最小部分：新增 `PL_SAMPLER_EXTERNAL_YUV`、`pl_opengl_wrap_params.sampler_type`、`GL_EXT_YUV_target` shader extension 与 `highp __samplerExternal2DY2YEXT` 声明，禁止将此外部纹理视为 FBO；显式 sampler 只接受 `GL_TEXTURE_EXTERNAL_OES` + raw YUV 组合。改动位于该仓 `buildscripts/deps/libplacebo/src/{include/libplacebo/gpu.h,include/libplacebo/opengl.h,opengl/gpu_tex.c,shaders.c,dispatch.c}`；可重放补丁为 `buildscripts/patches/libplacebo/libplacebo_external_yuv_sampler.patch`，`buildscripts/scripts/libplacebo.sh` 已接入幂等应用与冲突失败。

验证：`git apply --cached --check` 确认补丁可应用于源码索引；当前源码 `git apply --reverse --check` 确认已经应用；定向 `git diff --check`、`bash -n` 通过。首次直接 `ninja` 因交互 shell 未带 NDK bin 的 `PATH` 报 `aarch64-linux-android26-clang: command not found`，补上既有 NDK 27.2 toolchain PATH 后 `ninja -C _build-arm64 -j4` 完成并链接 `libplacebo.a`。这只是编译证据，尚未构建 mpv/APK、安装或运行直采。

2026-09-25续进展：外部构建仓的mpv原型已增加单纹理YUV格式、`external_yuv`标记、`pl_opengl_wrap`显式sampler及`p5_direct_yuv`开关，arm64编译链接通过；但该mpv源码未包含当前P5 raw/RPU实验链，不能用它作运行结论。随后把同样接线移到实际P5隔离源码`/tmp/media-kit-mpv-clean-2194`，只在`p5_raw_yuv=1,p5_direct_yuv=1`时绕过raw FBO/prepass，保留逐帧DV元数据、PTS/crop校验与unmap前GPU完成等待。对应libplacebo补丁干净应用于`/tmp/media-kit-libplacebo-p5-gamut-fallback`，补齐隔离Python jinja2依赖后其arm64静态库构建通过；旧库和两个头文件备份在`/tmp/media-kit-libplacebo-p5-gamut-build/pre-direct-backup/`。使用一致Android前缀的`_build-isolated-arm64`全量重编并链接libmpv成功，`strings`可见直采开关和YUV sampler。当前libmpv SHA-256 `5fa83855aab513a26c76fae3c2ea9df92d7a38c0e8703cdfa37f321da2546031`，libplacebo.a SHA-256 `60187c61e1d9de533f4fd1cbcef2a7737fd707051b88ac384e6210e0795fddda`；`git diff --check`通过。构建过程一度缺少Python `jinja2`，安装到临时`PYTHONPATH`后消除；不是C代码失败。

**仍未构建/安装APK，未做真机shader链接、同帧L2C、4K50性能或真人可见验收。**下一步将此候选替换进入既有P5诊断APK，先验证raw/直采两开关是否保留同PTS/RPU与色彩，再做相同输入的性能A/B/A。编译通过不意味着性能或颜色通过；同AHB的局部Y差异和PlatformView PQ dataspace`-22`门禁均未改变。

本轮未改手机或APK，设备仍为10369基线。Android实验构建仓及本项目均保持未提交；不覆盖其余既有dirty工作。

## 真机结果补记（2026-09-25）

以上“未构建/运行”只描述当时构建门禁，后续已完成同机实测。直采候选已打入诊断APK；原4K50 P5同APK、120秒、关闭阶段探针的A/B/A（直采/packed10 prepass/直采）在t120累计VO掉帧分别为1/18/1，解码器掉帧均0，温控状态1。直采可以改善该素材的输出性能，但不是颜色通过：PTS10映射前RGBA16F同帧比较，直采对启用`1020/1023`缩放的prepass RGB平均绝对误差约.002621/.001182/.000710，存在局部大尾差；关缩放后平均误差下降，局部尾差仍在。详细比较见`artifacts/android-p5-direct-vs-prepass-l2c-pts10.json`和`artifacts/android-p5-direct-l2c-scale-ab.json`。直采不需要packed10中间纹理，但私有AHB的raw归一化值与libplacebo码值约定仍须校准。

按用户要求换用`~/Downloads/test-clips/iOS_P5_GlassBlowing2_3840x2160@59.94fps_15200kbps.mp4`（HEVC Main10/DV P5、3840×2160、60000/1001fps、178.112秒、SHA-256 `afb24b77733a3ca9071f0cfea0d0f7871670a7b6119eb44a314cba974541477c`）。同一诊断APK将固定源路径的SHA白名单作等长替换，依次运行直采与packed10 prepass，均关闭GPU阶段探针和RGB dump。120秒累计VO掉帧：直采718、prepass936；t60分别329/419，t90分别517/669；两者解码器掉帧始终0，温控状态1，播放时间持续前进。预处理启动时有一次重新打开视频，统计采用最后一次打开后的连续会话。原始日志SHA及各检查点见`artifacts/android-p5-glass-60fps-summary.json`，关键日志见`artifacts/android-p5-glass-{direct,prepass}-keylog.txt`。这证明直采有收益，但**该机此路径没有达到4K59.94流畅播放**；VO计数及Flutter回调不等于屏幕实际present测量，未作真人可见验收。

4K50另一次开启阶段探针的稀疏样本中，raw prepass CPU提交中位386µs、直采4µs；prepass raw GPU query中位869.5µs；unmap `glFinish`等待直采约10.42ms、prepass约11.45ms；VO render wall约18.83/18.52ms（直采/prepass）。这些是不同测量位置和运行条件，不可直接相加，也不能代替GlassBlowing2的59.94fps分段耗时。详见`artifacts/android-p5-direct-stage-summary.json`。

试验后手机原4K50样本按SHA-256 `328cae5c...`恢复，APK回到版本10369，所有`debug.media_kit.p5_*`数字属性归零。下一步优先在59.94素材上隔离输出节拍、GPU等待与Flutter纹理消费，随后修正直采raw码值/色度约定并复验同帧L2C。

59.94素材直采稀疏计时补测：同一诊断APK打开`p5_raw_perf=1,p5_vo_perf=1`，确认P5/RPU有效后播放。frame50–2500每50帧采样，共50点；`vo render` wall中位17,958.5µs、P95 21,056µs、最大22,828µs，50点中30点超过59.94fps的16,683µs帧预算；raw提交中位4µs，释放时`glFinish`等待中位11,284.5µs、P95 12,614µs。t60累计VO丢帧347、decoder0、thermal1。这是带稀疏探针的另一轮，不可直接与无探针t60=329作严格性能差值。`vo render`计时在`pl_render_image_mix`前后包围渲染调用，CPU wall包含驱动提交及可能的同步等待，不是独立GPU执行时长；raw释放等待也可能与同一GPU工作重叠，不能把两项相加。数据见`artifacts/android-p5-glass-direct-stage-summary.json`，原始log SHA写在JSON中。首轮因忘开`p5_rpu_probe=2`被运行时校验拒绝、空白画面及计数无效，已重启有效会话后重测。补测后再次恢复原片SHA、APK10369及开关。

2026-09-26 GPU/线程时间分离：仍用GlassBlowing2直采，开启`p5_vo_gpu_timer=1`（render-only）及`p5_vo_cpu_wall=1`，其它阶段计时关闭；GL_EXT_disjoint_timer_query可用，timestamp bits=64，791个frame50–4000采样无miss/disjoint，GPU区间落在0/1048/2097µs三个档位，中位1048µs、P95 2097µs。设备时间戳步长约1048µs，不能把0解释为零GPU工作。21个250帧批次的VO draw wall/线程CPU每帧中位17.34/5.10ms，flip wall中位0.585ms。t60/t90累计VO掉帧361/613，decoder0、thermal1。GPU timestamp覆盖`pl_render_image_mix`前后排入同一GL队列的工作；它不覆盖后续submit/swap、系统合成与屏幕present。CPU wall显著大于CPU时间、GPU时间戳也远小于wall，说明当前`vo render`长耗时主要不体现为这一区间的GPU执行时长，下一步应沿`pl_render_image_mix`内的同步/驱动等待、AHB acquire/release及队列深度细分；不据此排除其它GPU或显示链瓶颈。数据及log SHA见`artifacts/android-p5-glass-direct-gputimer-summary.json`。测试后再次恢复原片SHA、APK10369、P5属性0。
