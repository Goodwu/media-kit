## libmpv build lock（2026-10-11 更新）

默认 arm64 libmpv 来源固定为 Goodwu fork 发布（其余 ABI 维持上游 Predidit v1.2.7 基线）：

- Release: https://github.com/Goodwu/media-kit/releases/tag/libmpv-android-v2026.013
- mpv: Goodwu/mpv `media-kit/android` @ `d24c59905b`（tag `media-kit-v2026.012` 同点该提交；v2026.013 与其同一二进制）
- FFmpeg: Goodwu/FFmpeg `feature/android-mediacodec-p5-rpu` @ `b4d2ea4ffb`（P5 RPU 整改版：pts 复现元数据整批丢失修复 + 4K 喂数据路径双重拷贝移除；新增 `dovi=auto|on|off` 解码器选项与 RPU 跟踪日志。P0 验证记录 `archives/experiments/android-ffmpeg-p5-rpu-b4d2ea4-verify-20261003.md`；已知登记项：元数据切换帧存在 11 帧位移（298/300 帧逐帧一致），归 FFmpeg 任务后续调查）
- libplacebo: Goodwu/libplacebo `optimize/dovi-linear-decode` @ `c9fd879`
- 构建链: Goodwu/libmpv-android-video-build-dv-experiment @ `3dc4596`（v_ffmpeg 钉定 b4d2ea4ffb、v_mpv 维持 d24c59905b；Kazumi HLS 补丁维持 patches/ffmpeg 机制，对 b4d2ea4ffb 兼容性已验；`72c574d` 起 bundle 打包内置 Vulkan 弱导入步骤）
- **v2026.013 变更（2026-10-11）**：`media-kit-d24c59905-ffmpeg-b4d2ea4-arm64-v8a-vkweak.jar` SHA-256 `0e06f383b580507cb42ab49634a0789fa67707f237d92bb753ce09bec06d3818`（默认）。与 v2026.012 资产（`c3bab5fca4fd81fbf12715d934f298fd0a0c6971bb8cbfd0ce3439cf3de53702`）相比仅 libmpv.so 内 `vkGetPhysicalDeviceProperties2` / `vkGetPhysicalDeviceQueueFamilyProperties2` 两个未定义导入由 STB_GLOBAL 弱化为 STB_WEAK（字节差=2）：Android API 24-27 系统 libvulkan.so 仅含 1.0，全局导入使 dlopen 失败。契约：仅创建 Vulkan 上下文才触达这两个符号，产品 Android 拓扑（Texture/mediacodec-copy/gpu-next-GLES）不创建；若启用 vo=vulkan 需恢复强符号并要求 API 28+。LG H870DS（Android 7.0）实机 dlopen+硬解+帧推进验证通过，派生工具与断言见 dv-experiment 仓 `scripts/make_vkweak_release_jar.sh`。
- 历史资产：v2026.012（d24c59905+b4d2ea4 `c3bab5fc…`）、v2026.011（d24c59905+fff3ee7 `cafef3a4…`）、v2026.10（5f9ddf17 `c0e5d7f0…`）、v2026.09（5e26cf86 `7cb87a5c…`、398d0c3 `dad30ae2…`）见各 release 页
- 版本标识：libmpv.so 内 `P5 direct external YUV sampler enabled` / `dovi rescale k=%.6f` / `dovi-p5-fast-path` / `dovi-p5-pipeline` / `Dolby Vision RPU export enabled`（末位为 b4d2ea4 世代 libavcodec 锁定标记）标记串，CI（ci.yml `libmpv-jar-identity` job）据此校验（.dynsym 弱化不影响标记串）。

## 1.3.8

- build: AGP 8.13.0
- build: bump dependencies
- build: 16KB page size support

## 1.3.7

 - **FIX**: undefined variable.
 - **FIX**: check if is found before md5.
 - **FIX**: md5 check.
 - **FIX**: md5Matches.
 - **FIX**: new gradle logic for downloading.

## 1.3.6

- build: revert dependencies

## 1.3.5

- build: revert dependencies

## 1.3.4

- build: bump dependencies
- fix: DTS support

## 1.3.3

- build: bump dependencies

## 1.3.2

- build: bump dependencies
- fix: DASH having BaseURL(s) with special characters not loading ([#353](https://github.com/media-kit/media-kit/issues/353))

## 1.3.1

- build: bump dependencies

## 1.3.0

- build: bump dependencies
- feat: DASH support
- perf: reduce bundle size
- perf: static link FFmpeg w/ libmpv

## 1.2.0

- build: bump dependencies
- perf: reduce bundle size

## 1.1.1

- fix: add `@Keep` annotation to `MediaKitAndroidHelper`

## 1.1.0

- feat: support for AGP 8.0
- build: bump dependencies

## 1.0.6

- build: bump dependencies

## 1.0.5

- build: bump dependencies

## 1.0.4

- build: bump dependencies

## 1.0.3

- build: bump dependencies

## 1.0.2

- perf: enable `extractNativeLibs`
- fix: package:ffmpeg_kit_flutter compatibility

## 1.0.1

- feat: add `subfont.ttf`

## 1.0.0

- Initial release
