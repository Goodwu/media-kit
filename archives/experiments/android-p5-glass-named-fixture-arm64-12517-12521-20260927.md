# Glass P5 固定文件名诊断入口与 arm64 单架构包（12517–12521）

2026-09-27，华为 LYA-AL00/API29，自动亮度。固定文件 `/data/local/tmp/media-kit-p5-glassblowing2-4k5994.mp4` 在 12518 前再次核对 SHA-256 为 `afb24b77733a3ca9071f0cfea0d0f7871670a7b6119eb44a314cba974541477c`；arm64 自建 libmpv JAR SHA-256 为 `f745146332b532d8baeb162b7a33ddefa03ae8dc0a7731f13a9584ef7e6fa3f9`。诊断页在打开前设横屏沉浸模式并挂载黑色 `Video`，点击后走现有 HDR 协调器和通用 Texture 布局预建。测试包的窗口仍受左侧 136 像素缺口安全区限制，预建 2984×1440；没有把 `SHORT_EDGES` 的测试 Activity 设置合入本轮。

12517 保留旧的边复制边计算哈希再播放流程。331 MB 固定视频的 `requested→sample_ready` 为 **14.525 秒**；`media_opened` 为 14.905 秒。画面能播，但这种测试入口开销远超首帧目标。用户明确要求受控测试文件按命名规则区分，不要每次读取内容。12519 因此改为显式诊断开关 `MEDIA_KIT_ANDROID_NAMED_LOCAL_SOURCE`：只接受 `/data/local/tmp/media-kit-{hdr10,hlg,p84,p5}-*.mp4` 的普通文件，由文件名选择已知测试策略，不复制、不在点击时哈希；`AndroidHdrSampleIdentity.sha256` 留空以明确表示本次未做内容验证。普通 HDR 测试入口仍保留原私有副本流程；此命名规则不是任意用户文件的可靠格式识别。

| 包 | 固定文件处理 | 点击→`sample_ready` | 点击→`media_opened` | 点击→首个 AImage | 可见证据 |
| --- | --- | ---: | ---: | ---: | --- |
| 12517 | 复制并计算哈希 | 14.525 s | 14.905 s | 约 15.401 s | 20 秒后截图出图 |
| 12519 | 文件名规则 | 1.199 ms | 0.351 s | 约 0.670 s | 5 秒后截图出图 |
| 12521 | 文件名规则，arm64 单架构 | 1.084 ms | 0.346 s | 约 0.684 s | 5 秒后截图出图 |

上述 AImage 是原生解码/取图节点，不等于物理屏幕首帧。Glass 片头本身约 2.052 秒黑场；本轮没有高频 PixelCopy 或光学测量，**不能宣称首个可辨画面在 2 秒内**。12521 的 `ANDROID_TEXTURE_PREPARED layoutBound=true`、原生图像和屏幕截图共同证明受控入口工作，不能替代全片、颜色或退出重入验收。选摘日志及截图见 [artifacts/android-firstframe-named-fixture-12517-12521](artifacts/android-firstframe-named-fixture-12517-12521/)；12521 APK SHA-256 `bdd9bdd97b581bbcff2a8d0300fdb962074c7283a4fa3fac9ce61a501eb1bb7`，截图 SHA-256 `9abb844a8c1dba66db4e22737a872758826ba6c643d2d38f628a4448671933b5`。

构建发现本地 arm64 JAR 参数过去仅替换 arm64，Gradle 仍下载 v7a/x86/x86_64 预构建 JAR，12518 APK 也包含其它 ABI 的 `libmpv.so`。测试应用现设置 `mediaKitArm64Only=true`，libmpv Gradle 下载任务仅保留 arm64；应用 JNI 打包进一步排除其它 ABI。12521 构建日志无 `Downloading file from`，APK `lib/` 仅有 `arm64-v8a`，40.7 MB；正常库构建未设置该属性时仍保留原有多 ABI 行为。两棵测试构建树里含下载 JAR 的 `media_kit_libs_android_video` 生成目录已删除；复查仓库和隔离树无 `default-*.jar`，保留自建 arm64 JAR 和用于回退的 12492 APK。

每次短轮后均强停测试应用，恢复 12492 APK、五项 P5 属性为 0、自动亮度与自动旋转，确认屏幕 OFF。后续仍需把固定命名规则与任意媒体格式识别分开，并测实际首个可辨画面的分布、旋转/重入和其它代表素材。
