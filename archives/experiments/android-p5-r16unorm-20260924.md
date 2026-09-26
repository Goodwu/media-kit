# P5 R16 UNORM 中间纹理能力门禁（2026-09-24）

当前 P5 raw/MRT 路径为三个全尺寸 R32F 分量纹理，解码帧 3840×2160 时仅这三张纹理的理论存储约 99.5 MB。R16 UNORM 在数值表示上可保留 10-bit 归一化分量所需量级的精度，且与此前失败的 R16F 是不同格式；但它需要设备支持 `GL_EXT_texture_norm16`，其扩展规范见 [Khronos](https://registry.khronos.org/OpenGL/extensions/EXT/EXT_texture_norm16.txt)。该判断只用于提出候选，不构成独立色彩精度验收。

在本地 mpv 的 P5 raw/MRT 分支做默认关闭的 `debug.media_kit.p5_raw_norm16=1` 候选：显式检查扩展，使用 `GL_R16/GL_UNSIGNED_SHORT` 和 UNORM `ra_format`，保留原 R32F 默认路径。增量补丁 `android-p5-r16unorm-20260924.patch` SHA-256 `4365a5e14ce891203f20c49febb3b546b03bf082aea7a56f702b7a39d357c953`，可在原实验源码上 dry-run 应用；arm64 原生编译/链接和 Flutter release APK 构建通过。APK `/tmp/media-kit-p5-r16unorm-8333-arm64.apk` SHA-256 `4a7b77f16ce8421ef6341668229bff7e68ddab82ec68537deb552e6e58498f19`，JAR SHA-256 `83495617efadeecfa5754a4d0dffc857164258de8e0bede7511fc1f006dd9088`，libmpv SHA-256 `9ac18e8e4851fb768fd58d529673757a5fee302084d7e45c690c4f98e086bee8`；实体机 versionCode 8333。

真机显式开启 `p5_raw_norm16=1` 后，mapper 报 `P5 raw R16 UNORM requires GL_EXT_texture_norm16`，在 FBO 分配和有效首帧前失败；此轮不能用于性能、颜色或长播对照。启动日志 `/tmp/media-kit-p5-r16unorm-8333-start-logcat.txt` SHA-256 `0a9e055f4e157ff5aa100a36f00012aa2224ea109b6d11f4828e252cda891d57`。当前设备的有效 GL 上下文未报告该扩展，R16 UNORM 路线在本机排除；不能泛化为所有设备不支持，也不能据此推断 R16F、R32F 或其他打包格式的性能。应用强停，P5 与候选属性归零；候选源码已撤回到原实验源码，补丁仅供回放/复核。手机重新安装已验证有效的 8332 包并保持强停。后续聚焦现有 R32F 路径的工作/资源依赖或经能力验证的其他等价格式。
