# P2 GPU HDR Surface 格式与设置时机隔离（2026-09-24）

固定目标机 LYA-AL00/API29、已解锁前台、HDR10 源 `/data/local/tmp/media-kit-hdr10-full.mp4` SHA-256 `e4f869b140e3ef322b7fc63fefe015593708f6443fc79060fa3e7f2234816937`。两项测试页诊断开关默认关闭，只隔离 Surface 请求格式或 dataspace 设置时机；生产/正常路径不因诊断而放松首帧门禁。构建使用 JDK17、arm64 Release；定向 `android_hdr_playback_policy_test.dart` 通过，Dart analyze 仅该文件既有 `use_super_parameters` info。

| 轮次 | 唯一目标变量 | 原生库身份 | 结果 |
| --- | --- | --- | --- |
| 6237 基准 | `RGBA_1010102` (`format=43`)，Surface 创建时请求 PQ `0x09c60000` | 原 JAR SHA `e7b4cfefed60052277519a39d4834eb33d35f08342c59610279232878d1036bd` | `setBuffersDataSpace=-22`、实际0，无候选 WID/首帧；见 [前轮记录](android-hdr-p2-6233-6237-device-20260924.md) |
| 6311 | `MEDIA_KIT_ANDROID_GPU_HDR_RGBA8888_SURFACE_PROBE=true`，创建时不请求 10-bit holder；其他与 6237 同 | 同基准 JAR | 实际 `format=4`、1440×810；同 PQ `0x09c60000` 仍 `-22`、实际0，10秒后自动打开超时，无首帧。此轮未运行 sRGB 探针，因为它仅在 10-bit holder 开启 |
| 6312 | `MEDIA_KIT_ANDROID_GPU_HDR_LATE_DATASPACE_PROBE=true`，10-bit holder 先发布 WID，事务在绑定后、打开媒体前调用 PQ | 同基准 JAR | 候选 WID 发布后，gpu-next 初始化触发旧 libplacebo `pl_gpu_finalize` 重复格式断言/SIGABRT，**尚未调用 PQ dataspace**；该轮不能判断设置时机 |
| 6313 | 与 6312 同时机，仅替换为已修复重复格式断言的本地 JAR | 修复 JAR SHA `f5f9d76dac4643edf7c803cfaa46538027fb6a5874c2edec237959d9ad25d16e` | 当前候选 `RGBA_1010102`/1440×810 已发布 WID 11206，后续 PQ `0x09c60000` 仍返回 `-22`、实际0；sRGB 探针/UNKNOWN 复位均成功，事务 `pq Surface dataspace was not applied`，无媒体首帧 |

6311 APK `/tmp/media-kit-hdr10-gpu-rgba8888-6311-arm64.apk` SHA `ce8c399283e040e211347c51d41d0e5c3ed09f6d80b200dec96a6d59bd653095`，设备 versionCode 8311；日志 `/tmp/media-kit-p2-hdr10-6311-logcat.txt` SHA `8d686f727aef1a41ec2b3511ff69964a7acd2883671d1b0b8a30adba27d832f2`，SF SHA `ad2f1930d7aae622938ee265216c81b0cfbeec46efdf2c17baaf85dbc923c70e`，截图 SHA `20c828e9616dca658332a99a810c1501c11274be1ddc4f5ec0a4763b2c001321`。

6312 APK `/tmp/media-kit-hdr10-gpu-late-dataspace-6312-arm64.apk` SHA `ea2f1495eb65e2f5482c9b3c0a40ad76fe63b74f840b51451b3de04098681eb4`，设备 versionCode 8312；其日志 `/tmp/media-kit-p2-hdr10-6312-logcat.txt` SHA `1011e5dd57f7f6069384f12dd6dc59b4537b8bf6fd8ac3ccd1d7a104671ab570` 含 SIGABRT/assert 文本。6312 原生崩溃是已知旧 JAR 问题，不能把它归于延后 dataspace 设置；修复 JAR 曾在 6240 HDR10 Texture 实机消除该断言。

6313 APK `/tmp/media-kit-hdr10-gpu-late-dataspace-fixed-6313-arm64.apk` SHA `221848c6b92ed57bda5b25c5cad2598be07d094d92c29adbe2c02d45cc16fb74`，设备 versionCode 8313；日志 `/tmp/media-kit-p2-hdr10-6313-logcat.txt` SHA `3798c361865bea15287f0faffc159da1309aa295d568b2e9333e2c47ef391c55`，SF SHA `9bd264968cc427ee108c4c600323f4b570891aba1170103ed3d7e6785af17014`，截图 SHA `6793586c731c595c098188476adb99ea2cddabd272a30a972ce9d46d447e5448`。已强停应用，8313 包保留安装。

结论仅限这台设备和现有 Surface/VO 实现：公开 NDK 调用在 `format=43` 与 `format=4`、创建时与当前 WID 绑定后都拒绝 PQ dataspace。HWC/MediaCodec 原生 PQ 阳性、sRGB 探针成功，仍不足以判断厂商为何拒绝应用的 HDR dataspace。6313 改用修复 JAR 与 6237 非严格同二进制配对，但 6310 已以原 JAR证明创建时 `0x11c60000` 也失败；6313 的关键作用是排除旧断言并实际触达后置调用。后续若继续 GPU HDR，应做最小 `ANativeWindow` usage/consumer 合约和首个 buffer 后设置的隔离测试，或更换真正受支持的 HDR buffer 生产路径；不能用 UNKNOWN dataspace/8-bit 画面充当 HDR 验收。
