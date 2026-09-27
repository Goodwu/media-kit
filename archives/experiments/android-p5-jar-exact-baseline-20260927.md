# P5 当前 JAR 的逐字节 libmpv 基线重建

## Current State

2026-09-27，针对首帧实际 mix PTS 探针，先在独立 `/tmp/media-kit-p5-jar-rebuild-20260927` 源码/构建目录重建现用 arm64 JAR。JAR `/tmp/media-kit-p5-policy-v2-arm64.jar` SHA-256 `5b9495f72893b8b62bb9085c67c9e87707b04f5910d3f09e9a79df82efcfd2e2`；其内未strip `libmpv.so` 为50,069,200字节、SHA-256 `b43500e66eaa08bd6d1821bd72ea15b3dd79d86831f61ec55cd60f783fd429ad`。隔离构建的`_build-original-prefix-arm64/libmpv.so`已实测同大小、同SHA。没有封装、安装或实机运行新库。

重建源自mpv提交`a81978bd625c7906808fcc5204886e8279018a3a`，补入`a322dd2`八个非VO配套文件、已归档`artifacts/android-p5-glass-direct-retire/map-variant-policy-cumulative.patch`和`android-p5-full-frame-8367-mpv.patch`中的`mp_image.c` P5_DOVI_MAPPED块；`MPV_VERSION`固定为`v0.41.0-dev-g32a164cc0-dirty`。Meson须在该源树内创建build目录、`--prefix=/usr/local`、NDK `27.2.12479018`。原始`libplacebo.a` SHA-256 `60187c61e1d9de533f4fd1cbcef2a7737fd707051b88ac384e6210e0795fddda`；正确FFmpeg `libavcodec.a` 是`/tmp/media-kit-prefix-clean-2197/lib/libavcodec.a` SHA-256 `36a68423f6736a4e6f5d0b5ccb2a5081ce78a50de1b3aff3a5e506ece167820f`，同时含`media_kit_mc_*`和`MEDIA_KIT_P5_RPU`。此前误选的两份静态库各只含其中一组，不能复现目标ELF。`--prefix`遗漏会把`MPV_CONFDIR`从目标`/usr/local/etc/mpv`变为`/opt/homebrew/etc/mpv`。

**完整从当前源码重新编译仍不能称为逐字节复现。** `video_out_hwdec_hwdec_aimagereader.c.o`用相同源码重新编译时目标函数仍少约120字节；本轮精确链接复用了现存历史object，原始SHA-256 `e10a9f6b077dd4ea70fcd3613d97e86306d312a0ea35d65371df1f899ec8f20d`。该80KB arm64 object 已另存为`artifacts/android-p5-jar-exact-baseline/aimagereader-original-object.o.gz`，gzip SHA-256 `7354e4a256f4b8cef393952fd5b370139cba70d22f5894b5a79c6d19cc236746`。它可供只修改其他VO源文件的诊断重链使用，但不能替代修清该object的源码/编译输入差异；最终通用代码提交仍须从源码构建并独立验收。

当前精确基线只证明构建输入身份和链接结果，不证明新增探针或性能结果。下一步仅修改VO实际mix/提交计时，保持该历史object不变；新增探针默认关闭、限量输出，先同包关/开短轮比较，再做首帧真正呈现与全屏验收。隔离源码和构建产物仍在`/tmp`，可能被系统清理；归档补丁和object用于恢复，不把临时目录当作长期交付。
