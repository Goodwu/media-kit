# 无诊断 FFmpeg 的 Reader=3：HDR10 / P8.4 Texture 真机复验（2026-09-25）

## 结论

用固定发布脚本的 FFmpeg 7.1.3 配置和固定 mpv 提交 `32a164c`，移除先前为诊断 FFmpeg 添加的兼容符号后，Reader `maxImages=3` 在华为 LYA-AL00 对完整 HDR10 和 P8.4 两源均完成直连 MediaCodec 输出端口协商：20/19/18 槽被拒，17 槽成功。两轮均读回 `pixelformat=mediacodec`，各采样点 VO/decoder 掉帧0，且间隔截图视频区域变化。这把 `5→3` 候选从含历史 FFmpeg 探针的实验依赖推进到无该探针的依赖，但并不证明 10-bit GPU 数值、色彩、首帧可靠或长稳。

## 构建

- FFmpeg：官方 `n7.1.3` / commit `f46e514491172d15bd74b4abb1814cd2f05a763e`，按 Predidit `libmpv-android-video-build` `v1.2.7` 的 `buildscripts/flavors/default.sh` 配置及 `ffmpeg-hls-kazumi-combined.patch` 编译，NDK 27.2.12479018、Android API 26、arm64；安装至 `/tmp/media-kit-prefix-release-reader3`。`libavcodec.a` SHA-256 `4063a95c8905c5c418564b541af8355ccc4ad031264e24cd8dface93e587cc95`，`nm` 查不到 `media_kit_*`。配置/编译/安装日志在 `/tmp/media-kit-ffmpeg-{configure-release,release-build,release-install}.log`。
- mpv：固定提交 `32a164cc017acab50389f2194f720ccfd0b01a28`，应用 v1.2.7 的 `mpv_lavc_set_java_vm.patch`、`mpv_fence_leak-fix.patch` 和项目最小 Reader `5→3` 补丁；未保留诊断符号定义。`libmpv.so` SHA-256 `56e48164a70159849821ca16f45aad09c4e09386b1b8fe6f1ba4abf96fdd0d05`，`nm -D` 确认存在 `mpv_lavc_set_java_vm`、无 `media_kit_*`。JAR沿用固定包 Android helper，仅替换 arm64 libmpv，SHA-256 `b8ad46c1cd359aa4d3651eeab06dc5ca6994de3dab998afc9e4722e34526d699`。
- 其他静态依赖（含 libplacebo）来自之前的 `/tmp/media-kit-prefix-clean-2197` 拷贝；本轮没有逐个重建或与官方 v1.2.7 二进制逐项比对，因此称为“无诊断 FFmpeg 的发布配置候选”，**不能称完全同官方发布构建**。

## 真机

| 包 / 源 | 输出端口与格式 | 机器采样 | 截图视频ROI `(0,370,1440,1090)` RGB SHA-256 |
| --- | --- | --- | --- |
| 11074 HDR10 3840×1920 / 29.97fps | 20→18槽`-1010`，17槽成功；MediaCodec、BT.2020/PQ | t28 `time-pos=1.301`，t60 `33.300` 秒；VO/decoder掉帧均0；启动一次Reader `-30001` | `a5f8cf5c…`、`842e5b09…` |
| 11075 P8.4 3840×1920 / 29.97fps | 20→18槽`-1010`，17槽成功；MediaCodec、BT.2020/HLG | 大文件暂存使打开晚于t28；t60 `3.036367`、t90 `33.033000` 秒；VO/decoder掉帧均0；启动一次Reader `-30001` | `2dfea5e8…`、`fee373b5…` |

两包使用同一 JAR、Texture/gpu-next、默认直 MediaCodec、目标宽1440、`MEDIA_KIT_ANDROID_PERF_PROBE=true`；仅本地源与版本号不同。日志及截图在 `artifacts/android-hdr-texture-release-reader3-20260925/`，P8.4 APK SHA-256 `06d9062acc64acaaa9b1b536e1ac3d3218251fa5386f8576231ec69faf8f10cb`。构建日志 `/tmp/media-kit-{hdr10,p84}-release-max3-build-1107{4,5}.log` 记录本地JAR身份。截图只证明两次采样画面不同，不能判逐帧present、真实颜色、屏幕HDR状态或全程稳定。

## 下一道门禁

1. 确认通用 OES mapper 导入的 AHB 实际格式、位深和数值；当前 `pixelformat=mediacodec` 仅是 opaque 硬解标记，不等于 10-bit 保真。对固定 HDR10/P8.4 帧建立 GPU 读回与独立解码参考，P8.4 应按 HLG 兼容底层且不消费 DV RPU 判读。
2. 定位启动 `acquireLatestImage=-30001` 的首帧/持图时序，重复冷启动和生命周期测试；做较长连续播放与可见验收。
3. 补齐其他静态依赖的发布构建身份，再决定是否将 Reader 最小补丁纳入正式 Android 库；不能以这两次机器短播替代 S1/S2 完整验收。

设备试验后强停并清除应用私有测试暂存，重新安装基线 `versionCode=10369`，/data 仍约71GiB可用。项目发布依赖未替换。
