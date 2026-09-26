# Android P5 failure → HDR10 → P8.4 → SDR recovery, 12471

## Current State

2026-09-27, Huawei LYA-AL00, Android 10, release APK build number 10471 (device versionCode 12471), correct local arm64 P5 policy JAR SHA-256 `5b9495f72893b8b62bb9085c67c9e87707b04f5910d3f09e9a79df82efcfd2e2`. Automatic brightness remained enabled. This is a diagnostic page, portrait, not the final full-screen product path.

The P5 GPU PQ Surface failed as expected. In the same process, HDR10 and P8.4 each passed track verification through native `mediacodec_embed`. After switching to the SDR H.264 control source, SurfaceFlinger showed the visible video layer as `BT709 SMPTE_170M Limited range`, `V0_BT709`, HDR metadata types `0`; HWC video layer dataspace was `010c10000`. Screenshots three seconds apart had changed RGB pixels throughout the video region. This establishes SDR signalling reset and moving visible output for this native HDR recovery path. It does not establish GPU HDR Surface reuse, true fullscreen, P5 PQ availability, or the first-frame latency goal.

## Code and checks

- `AndroidHdrOpenCoordinator.dispose()` now stops and resets owned mpv configuration after a successful open, including retry after a transient reset failure.
- The diagnostic `sdr:` recovery command invalidates the previous HDR source intent before its asynchronous handoff, so delayed HDR pause/seek/resume work cannot target the SDR media.
- Focused coordinator tests: 16 passed. `flutter analyze --no-pub` on the three edited Dart files: no issues. `git diff --check`: passed.
- Read-only review noted the separate GPU HDR Surface dataspace reuse risk; this run uses native HDR10/P8.4 output and does not resolve that risk.

## Runtime evidence

- Log: `/tmp/media-kit-12471-logcat.txt`. P5 open failed at 04:58:22.354; HDR10 track verified at 04:58:45.362; P8.4 track verified at 04:59:42.284; SDR open logged at 04:59:47.588, `vo=mediacodec_embed`.
- SurfaceFlinger/HWC: `/tmp/media-kit-12471-sf.txt`, `/tmp/media-kit-12471-hwc.txt`. At capture, visible video was `SurfaceView ... MainActivity#1`, crop 854×480, frame `[0,360,1440,1170]`; its dataspace was BT.709 and HDR metadata types 0.
- Screenshots: `/tmp/media-kit-12471-sdr-a.png` and `-b.png`. RGB difference bounding box within the video region was `(0, 0, 1440, 808)` and average channel differences were about 60.7/55.4/53.7. The PNGs are local diagnostics, not committed artifacts.
- The screenshot pair originally appeared unchanged when Pillow compared RGBA with `ImageChops.getbbox()` because the alpha difference was zero; converting to RGB exposed the real pixel changes.

After the run, original APK 10420 was restored, auto brightness mode `1` verified, and screen state verified OFF. No display brightness maximum setting was used.
