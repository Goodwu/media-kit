# Android API 24 HDR probe

Standalone Java APK for querying display HDR declarations and decoder capabilities, then playing a local video through `MediaPlayer` to a native `SurfaceView` Surface. It does not depend on Flutter or project native libraries.

Build with `./tool/android_hdr_probe/build.sh`. The script uses JDK 17 and installed Android SDK build tools; set `ANDROID_SDK_ROOT`, `ANDROID_BUILD_TOOLS`, `ANDROID_PLATFORM`, or `OUT_DIR` to override defaults. It emits `/tmp/android-hdr-probe/android-hdr-probe.apk` by default. Set `APP_ID=com.example.androidhdrprobe.codecsurface` to create an independent package while preserving an already installed probe and its reports. The build creates a temporary manifest with a fully qualified Activity name; the source manifest and default package are unchanged. Each `OUT_DIR` has its own debug signing key, so preserve it for updates to that package.

Install and grant read access manually when authorized. To play a local clip, launch with an `ACTION_VIEW` file URI or pass `-d file:///sdcard/Download/clip.mp4`; optional `--ei seek_seconds 10` requests a seek after prepare. Optional `--es loadLibraryPath /data/user/0/com.example.androidhdrprobe/files/libmpv.so` runs `System.load` on a background thread and records success or the caught failure. The app writes an append-only `report.txt` under its external-files directory, which can be collected with `adb pull /sdcard/Android/data/com.example.androidhdrprobe/files/report.txt`.

The API24 codec report includes declared profile/level values and `VideoCapabilities` checks for 1080p/4K at 30/60 fps. Android 7 does not expose the later performance-points API, so the report labels that limit. Successful decode or a device HDR declaration alone does not prove that the panel visibly entered HDR mode.

## Direct MediaCodec to Surface comparison

The default `backend=player` retains the existing MediaPlayer route. For an independent API24 decoder/output-path comparison, pass `--es backend codec` and `--es color_mode passthrough|pq|sdr`:

- `passthrough` configures the extracted video track unchanged.
- `pq` sets color-standard BT2020 (6), color-transfer ST2084 (6), and limited range (2). All other extracted keys, including an existing `hdr-static-info` buffer, remain intact. Missing source HDR metadata is not invented.
- `sdr` overrides only color aspects to BT709 (1), SDR_VIDEO (3), and limited range (2). This is a path control: it does not transform pixels or provide valid HDR-to-SDR tone mapping. The compressed bitstream is unchanged (a PQ bitstream remains PQ). Existing source HDR static metadata is retained and logged; a HAL may still treat the output as HDR because of that metadata. Inspect output aspects and compositor evidence rather than assuming the override changed the display mode.

For the independent package, an example launch is:

```sh
adb -s SERIAL shell am start -n com.example.androidhdrprobe.codecsurface/com.example.androidhdrprobe.ProbeActivity \
  -d file:///sdcard/Download/clip.mp4 --es backend codec --es color_mode passthrough
```

Reports are then under `/sdcard/Android/data/com.example.androidhdrprobe.codecsurface/files/report.txt`. The report logs every extractor track's complete `MediaFormat.toString()` and hex bytes for `csd-0`, `csd-1`, `csd-2`, and `hdr-static-info`, the selected track and decoder name, configured format, output format changes, first frame PTS values, one-second progress counters, errors, EOS, and release results. By default it selects a decoder using `findDecoderForFormat`; the selected name is the authority for whether a vendor or software decoder was used. If the finder returns null, no decoder was configured and the run provides no black-screen/output-path comparison.

Optional `--es codec_name OMX.qcom.video.decoder.hevc` explicitly creates that named codec instead of running the finder. The report labels this as a bypass of declaration/profile/level matching. The extracted profile/level and all other keys stay unchanged except the requested `color_mode` aspects; configure/start errors are recorded, with no silent fallback or fabricated level. This distinguishes a capability-declaration rejection from actual configure/drain behavior. Explicit creation does not prove the stream is supported or rendered correctly.

Optional `--es render_mode timed|boolean` compares the two Surface-release APIs; the default is `timed`. The immutable session snapshot records the mode in its start/frame/progress/end logs. Both modes use the same PTS anchor and `waitForPresentation` timing, codec, access units, and Surface. Only the final release call differs: `releaseOutputBuffer(index, releaseNs)` versus `releaseOutputBuffer(index, true)`. Unknown values fail explicitly. A release failure ends the session; it never retries the same buffer through the other API. This diagnoses vendor timestamp behavior without assuming Dolby Vision needs either mode or establishing HDR acceptance.

Codec input/drain and resource release run on one worker thread. Outputs are released to the real Surface on a PTS-based monotonic timeline; progress calls these frames `scheduled`, not visibly presented. Pause, Surface destruction, and replacement intents stop that session and release both codec and extractor. A replacement codec session waits for the old session's cleanup. The play button after pause starts a new session at the original `seek_seconds` target (or the start); it is not seamless resume. Seeking begins at a previous sync sample and skips output before the requested target. The probe handles local unencrypted whole video samples only, no audio sync or DRM. Zero-size Surface buffers may contain frames; an empty EOS buffer is not counted as a rendered frame. Scheduling statistics and successful EOS do not establish visible frames, correct colors, panel HDR mode, or smooth playback; collect compositor evidence and human observation separately.

## Flutter demo diagnostics

`media_kit_hdr_lab` has an optional VM-service probe, enabled only in an Android Debug build with `--dart-define=MEDIA_KIT_ANDROID_SERVICE_PROBE=true`. It follows the page's real source-opening path, including HDR session routing when configured. The probe supports `snapshot`, `open`, `pause`, `play`, and `seek`, and returns mpv properties, bounded timestamped error logs, and the HDR session report. Each source open has a generation; concurrent probe requests are rejected. Keep matrix requests serial and avoid UI or automatic source changes during sampling. A response is a series of property reads, not an atomic native snapshot.

For an authorized test device, start the Debug activity with `--ez disable-service-auth-codes true --ei vm-service-port 8181`, then create `adb -s SERIAL forward tcp:18181 tcp:8181`. This disables VM-service authentication for that diagnostic launch; stop the app and remove the forward after testing. Use `python3 tool/android_hdr_probe/demo_service_probe.py snapshot`, `open --path /data/local/tmp/clip.mp4`, or `seek --seconds 10`. Local test files must be readable by the demo; a file URI on shared storage does not grant permission.

The report's `verified` field means decoder review completed. It does not prove native HDR, correct colors, continuous presentation, or smooth playback. Pair the report with source metadata, multiple rendered frames, compositor evidence, and human observation.

`p5-probe --path /data/local/tmp/clip.mp4` invokes the native P5 diagnostic with one frame. On API24 this must return `UNSUPPORTED` (the ImageReader/HardwareBuffer probe requires API29). This operation verifies the API gate; it is not a playback route.
