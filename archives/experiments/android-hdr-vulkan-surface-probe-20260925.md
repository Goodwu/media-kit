# Android 10 同 Surface Vulkan HDR 格式门禁（2026-09-25）

目标：核实华为 LYA-AL00（API 29）声明 `VK_EXT_swapchain_colorspace` 后，应用实际使用的 RGBA_1010102 `SurfaceView` 是否向 Vulkan 暴露 PQ/HLG 格式。此探针只查询，不创建 swapchain 或提交帧。

`adb shell cmd gpu vkjson` 显示一块 Mali-G76 设备、`VK_KHR_android_surface` / `VK_EXT_swapchain_colorspace` 实例扩展与 `VK_KHR_swapchain` 设备扩展；10-bit 和 RGBA16F Vulkan 图像格式具备颜色附件特性。这些设备级能力不代表具体 window surface 可用 HDR colorspace。

在 `media_kit_video/android/src/main/cpp/surface_dataspace.cpp` 加入默认关闭的 `debug.media_kit.vk_hdr_probe=1` 只读诊断：仅在原 NDK dataspace setter 失败时动态加载 `libvulkan.so`，为**同一个** `ANativeWindow` 创建 `VkAndroidSurfaceKHR`，枚举 `vkGetPhysicalDeviceSurfaceFormatsKHR`，记录 PQ/HLG 对应 10-bit/FP16 组合，然后销毁 Vulkan 对象。NDK arm64/API29 `clang++ -std=c++17 -fsyntax-only` 及 Release APK 构建通过。

首次诊断包 11001 的本地 arm64 JAR 漏掉 `libmediakitandroidhelper.so`，播放器在 `TempFile.directory` 报 `Unsupported platform: android`，因而没有触发 Surface 查询；这一轮不能算 HDR 结果。把先前可运行的 10369 包中的 helper 加回同一 JAR 后重建 11002。11002 APK `/tmp/media-kit-hdr10-vulkan-surface-probe-11002-arm64.apk` SHA-256 `7b155887e63bfd6164f978302c974077cc0d082e4bde55b373cf133717f92206`；本地 JAR `/tmp/media-kit-p5-gamut-scoped-arm64-with-helper.jar` SHA-256 `e92bfa1418850c1f63545177341bfa737326662849cffc1c2d96ef042e342952`。固定输入 `/data/local/tmp/media-kit-hdr10-full.mp4`，自动 HDR 事务、PlatformView、GPU HDR 尝试，属性开启后启动。日志 `/tmp/media-kit-hdr10-vulkan-surface-probe-11002-logcat.txt`。

有效观测：`surfaceCreated` 的 holder 请求 RGBA_1010102，实际 `ANativeWindow` format=43、1440×810；`ANativeWindow_setBuffersDataSpace(PQ)` 仍返回 `-22`，actualDataspace=0。Vulkan 同 surface 创建/查询返回0，实例 colorspace 扩展存在，物理设备0返回5个 surface format/colorspace 组合，但 PQ 10-bit=0、HLG 10-bit=0、PQ FP16=0；日志中也没有其他 PQ/HLG 格式。故设备支持 Vulkan 扩展与 10-bit 图像格式，**不等于该应用 SurfaceView 支持 HDR swapchain**。该轮未创建 swapchain、未提交帧、未通过 HDR/首帧/可见色彩验收；不能推广为整个设备无法显示 HDR，MediaCodec 直出视频层已有独立证据。

实验后强停应用，属性回读0；用 `adb install -r -d` 恢复 10369 基线包并核对 versionCode=10369。下一步不应仅基于 `VK_EXT_swapchain_colorspace` 投入 Vulkan GPU HDR 出口；应保留原生 MediaCodec HDR 路线，并继续寻找实际可生产且获 SurfaceFlinger/HWC 认可的 GPU HDR buffer 机制，或明确 GPU 视图 SDR 回退。

## 11003 枚举全部组合

在同一默认关闭探针上补充逐项日志后重新构建，APK `/tmp/media-kit-hdr10-vulkan-surface-probe-11003-arm64.apk` SHA-256 `e8ac760b873da0bf84b972e84d8e2eaa1673829d4644e800e698cba73c8d5be5`；日志 `/tmp/media-kit-hdr10-vulkan-surface-probe-11003-logcat.txt` SHA-256 `83163f75d226ba7e3e7a47d3c968781b277bc66a033e5d8dff4354250f71b07e`。同一应用 RGBA_1010102 SurfaceView、同 HDR10 输入和属性开关，`vkGetPhysicalDeviceSurfaceFormatsKHR` 返回5项：`(format,colorSpace)=(37,0),(43,0),(4,0),(64,0),(97,0)`。Vulkan 头文件中 37 为 R8G8B8A8_UNORM，43 为 B8G8R8A8_UNORM，4 为 R5G6B5_UNORM_PACK16，64 为 A2B10G10R10_UNORM_PACK32，97 为 R16G16B16A16_SFLOAT；所有组合的 `colorSpace=0` 均为 `VK_COLOR_SPACE_SRGB_NONLINEAR_KHR`。因此不是单纯缺少 HDR 对应像素格式，而是该 Surface 枚举未提供任何 HDR colorspace 组合。NDK PQ dataspace 同轮仍 `-22`，actual0。未建 swapchain/提交帧；不能将 10-bit/FP16+sRGB 组合解释成 PQ/HLG 输出。再次强停、属性回读0，并用 `adb install -r -d` 恢复10369基线包。
