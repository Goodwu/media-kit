# Dolby 官方 4K P5 Texture 输出尺寸对照（2026-09-25）

同一官方 Sol Levante P5 3840×2160/24fps/6314帧、SHA-256 `dacfd04518accd6367530b650dfeea429227df2be171bd99b4bdad36d31bbf9f`；同一隔离 arm64 JAR SHA-256 `1c9127cd2beec4addd066951e26ffdeb352ef21520308ef54e5619e42bdc31da`、Texture SDR/gpu-next/MediaCodec、`p5_rpu_probe=2,raw_yuv=1,raw_packed10=1,raw_early_fence=1,raw_retire=1,raw_code_scale=1,vo_summary=1`。只改变 Gradle `mediaKitTextureMaxWidth`：11039 为 1440，11040 为 720；11040 真机 `VideoOutput.onSurfaceAvailable` 回读 `720×405`，确认不是仅改了编译参数。

| `P5_RETIRE` 映射区间 | 11039 / 1440 宽 | 11040 / 720 宽 |
| --- | ---: | ---: |
| 100→1800 | 1700/70.833s = **24.00/s** | 1700/78.334s = **21.70/s** |
| 1800→3300 | 1500/82.952s = **18.08/s** | 1500/85.423s = **17.56/s** |
| 3300→4800 | 1500/86.456s = **17.35/s** | 1500/87.742s = **17.10/s** |
| 末次低频映射记录 | 5100 | 4900 |

11040 APK SHA-256 `993786131fb7a8457605207dc6706dd9223848ad14e65a39cd9dd87a6c3bfdcd`。片尾 `MEDIA_KIT_P5_RPU close_summary` 累计 inputs6375（启动重开）、outputs/matched6307、errors0、discarded68、unconsumed0；末次 epoch4 flush 11 条 PTS `262.625000..263.041667s`。11039 对应 outputs/matched6311、末次 flush7。两轮的 raw 映射与解码输出统计域不同，不把差数称为精确丢帧率；但 720 宽的后段映射速度并未改善，单纯最终 Texture 输出尺寸不是当前减速的充分解释。后续优先按时间分别量测硬解输出、VO 入队/淘汰和 raw mapper 耗时。

限制：先 11039 后 11040 顺序执行，第二轮起始热状态并未与第一轮严格一致；日志中的 AP 温度与减速同期升高，但没有可归因的限频记录，不能判为温控根因。两轮都有诊断开关，尚无无探针 A/B。`P5_RETIRE` 每 50 次才打印，量测为 mapper 入口节奏而非屏幕扫描或正式丢帧率；颜色、HDR 和人工可见流畅仍独立未验。11040 完整日志 `archives/experiments/artifacts/android-sollevante-p5-4k-11040/media-kit-sollevante-p5-4k-11040-720-full-logcat.txt` SHA-256 `8c8095da4e1d4b4f1e64497f611098d09cc14d0f4dc132aeec15977c8a1cb5b8`；11039 对照见 `android-sollevante-p5-4k-device-20260925.md`。两轮均恢复设备 10369、P5 属性 0，删除设备媒体。未提交。
