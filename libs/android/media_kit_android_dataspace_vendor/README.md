# [package:media_kit_android_dataspace_vendor](https://github.com/media-kit/media-kit)

Device-vendor Surface dataspace fallback extension for
[package:media_kit_video](https://pub.dev/packages/media_kit_video). Ships
the Huawei LYA-AL00 private window ABI apply path
(`LyaPqDataSpaceExt`, id `lya-pq`) behind an exact SDK + firmware +
dataspace read-only gate (requirement R5 of
`docs/requirements/android-hdr-auto-output.md`).

## 启用条件（三者全部满足才生效）

- `ro.build.version.sdk == 29`；
- `ro.build.fingerprint` 精确等于
  `HUAWEI/LYA-AL00/HWLYA:10/HUAWEILYA-AL00/10.1.0.163C00:user/release-keys`；
- 请求的 dataspace 仅限 BT2020_PQ。

## 门禁与加载语义

- **只读门禁**：适用性仅由读取设备属性判定；从不探测私有 ABI；
  `isApplicable()` 无副作用。
- **默认关闭、不适用零加载**：native 库 `libmedia_kit_dataspace_vendor.so`
  不在静态初始化、插件注册或 `isApplicable()` 时载入；仅在第一次通过
  门禁的 `applyDataSpace` 调用时幂等懒加载。其他设备/固件上零加载。
- **注册方式**：插件 `onAttachedToEngine` 先判 `isApplicable()`，通过才
  经 `PlatformVideoView.setSurfaceDataSpaceExt` 注册；engine 释放时注销。
- **失效表现**：该固件的公开 NDK 路径在 HDR 支持查询阶段即拒绝 PQ；
  无扩展（或不适用）时，`applyDataSpace` 四元组回报
  `{applied: false, path: none, ...}`，会话层判
  `initialDataSpaceRejected` 后沿候选列表降级，播放不中断。
- **符号面**：native 侧仅导出 1 个 apply JNI 符号，并带二次防御门禁
  （native 侧复验 SDK/fingerprint/PQ）与 dataspace 读回校验。诊断探针
  （late PQ、EGL HDR、Vulkan HDR）不在本包，留在 `media_kit_hdr_lab`。

## 使用

仓内 path 依赖（`publish_to: none`），由 `media_kit_video` 的
`PlatformVideoView.SurfaceDataSpaceExt` 注册通道消费；App 侧无需直接
引用本包 API。

## 测试与 CI

- JVM 单测：`cd android && ./gradlew :media_kit_android_dataspace_vendor:testDebugUnitTest`
  （8 项，覆盖门禁三条件、幂等加载、不适用零加载、重复 apply 只加载一次）。
- CI：`hdr-lab-analyze` job（`.github/workflows/ci.yml`）在
  `media_kit_hdr_lab` 上执行上述 JVM 单测与 arm64 构建编译检查。

## License

This package is part of the media-kit repository and governed by the MIT
license found at the repository root ([../../LICENSE](../../LICENSE)).
