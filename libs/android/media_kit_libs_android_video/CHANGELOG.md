## libmpv build lock（2026-10-02 更新）

默认 arm64 libmpv 来源固定为 Goodwu fork 发布（其余 ABI 维持上游 Predidit v1.2.7 基线）：

- Release: https://github.com/Goodwu/media-kit/releases/tag/libmpv-android-v2026.011
- mpv: Goodwu/mpv `media-kit/android` @ `d24c59905b`（tag `media-kit-v2026.011`；v2026.10 全部 + 客户端只读属性暴露：`dovi-p5-pipeline` 构建能力属性、`dolby-vision-compatibility-id`/`dolby-vision-el-present`/`hdr-vivid` 事实属性，渲染行为零改动，LYA 实机 8 轮验证通过）
- FFmpeg: Goodwu/FFmpeg `feature/android-mediacodec-p5-rpu` @ `fff3ee7`
- libplacebo: Goodwu/libplacebo `optimize/dovi-linear-decode` @ `c9fd879`
- 构建链: Goodwu/libmpv-android-video-build-dv-experiment @ `91bb42af`（v_mpv 钉定 d24c59905b）
- `media-kit-d24c59905-arm64-v8a.jar` SHA-256 `cafef3a44f7ab6379faf59e352e65dd69fa0b0fce45e80f86bc3026520bfdf21`（默认）
- 历史资产：v2026.10（5f9ddf17 `c0e5d7f0…`）、v2026.09（5e26cf86 `7cb87a5c…`、398d0c3 `dad30ae2…`）见各 release 页
- 版本标识：libmpv.so 内 `P5 direct external YUV sampler enabled` / `dovi rescale k=%.6f` / `dovi-p5-fast-path` / `dovi-p5-pipeline` 标记串（整改后探针已移除，旧 `P5_DOVI_RESCALE`/`P5_BUFFER_RETIRE` 不再存在），CI（ci.yml `libmpv-jar-identity` job）据此校验。

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
