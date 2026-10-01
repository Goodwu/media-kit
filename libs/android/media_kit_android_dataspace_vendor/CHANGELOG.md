# Changelog

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
