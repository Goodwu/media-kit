# Changelog

## 1.0.0+1 (2026-10-02)

- docs: 新增 README，说明发布面与使用约束：
  - 扩展启用条件：`ro.build.version.sdk == 29` + 精确 fingerprint
    `HUAWEI/LYA-AL00/HWLYA:10/HUAWEILYA-AL00/10.1.0.163C00:user/release-keys`
    + 仅 BT2020_PQ 请求，三者全部满足才生效。
  - 只读门禁：适用性仅由读取设备属性判定，不探测私有 ABI，`isApplicable()`
    无副作用；不适用时零加载（`.so` 不在注册或查询时载入）。
  - 失效表现：NDK 公开路径拒绝 PQ 且无扩展时，`applyDataSpace` 回报
    `initialDataSpaceRejected`，会话沿候选列表降级，不停播。
  - 单 JNI 符号面：native 侧仅导出 1 个 apply JNI 符号，另含 native 侧
    二次防御门禁与读回校验。
  - JVM 单测（`testDebugUnitTest`，8 项）与 CI 步骤
    （`hdr-lab-analyze` job）。

## 1.0.0 (2026-10-02)

- Initial release: `LyaPqDataSpaceExt` (id `lya-pq`) moved out of
  `media_kit_hdr_lab` as a controlled deliverable (requirement R5).
- Private window ABI (`perform` op 19, BT2020_PQ + readback verification)
  confined to `ro.build.version.sdk == 29` and the exact
  `HUAWEI/LYA-AL00/HWLYA:10/HUAWEILYA-AL00/10.1.0.163C00:user/release-keys`
  fingerprint, judged by read-only checks only. The native library
  `libmedia_kit_dataspace_vendor.so` is loaded lazily and idempotently on
  the first gate-passing `applyDataSpace` — never on other devices, never
  by registration or `isApplicable()`.
- Diagnostics probes (late PQ, EGL HDR, Vulkan HDR) are intentionally not
  part of this package; they remain in `media_kit_hdr_lab`.
