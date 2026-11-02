# LG P8.4 GPU timing exploratory A/B — 2026-10-30

APK SHA256 `77b1f045c2798de6fe0ef7f819a2bbae2d1ba5f6a0bc3f27b524d13def546d99`; source/native receipt `native-verification.json` and `native-candidate.json`. GPU timing uses mutually exclusive `input`, `yuv`, `render` modes, force-stop/recreate each round. Same verified local source, USB, brightness/backlight64 and 60 s. Each individual controller result completed with state restored and thermal cap gate passed. Renderer output is rolling per-pass 256-sample history; callback frame id is not timed-frame identity. YUV has no PTS. These stages were measured in separate sessions; never add them into per-frame total.

| mode | A mean | B mean | window | notes |
|---|---:|---:|---|---|
| input | 5.540 ms | 5.298 ms | PTS 20–55 s; 1049 samples each | GPU frequency 294.8 vs 301.5 MHz |
| YUV | 5.677 ms | 5.874 ms | 20–55 s relative first timer sample; 1049 each | GPU 308.7 vs 296.1 MHz; first battery 27.2 vs 26.2 C; not source PTS |
| renderer | 8.20 / 8.29 / 8.96 ms | 11.14 / 8.23 / 9.58 ms | rolling 256-sample windows emitted at callback PTS near 29.5/39.5/49.5 s | GPU 308.7 vs 270.8 MHz; rolling summaries, no independent per-frame timings |

Single A/B per category and differing DVFS mean no supported causal attribution or power conclusion. 20–55 s: hardware decode, ~29.97fps, backlight64, PQ target1000/gamma0 and GPU cap0; no additional dropped frames in stable window. Native logged query counters showed no disjoint/ring/nesting/context/begin errors through last periodic snapshot; final cleanup report was not captured due force stop, so full-session coverage cannot be asserted. Renderer last periodic snapshots A 1802 issued/resolved, B 1803, disjoint/dropped0; output is rolling and omits some frames.

Diagnostic-off baseline same APK: 20–55 s sampled frequency 264.5 MHz, busy64.2%, process median59.4% one-core; input-on A 294.8 MHz, busy62.2%, CPU median60.4%, YUV-on A 308.7 MHz/58.6%/58.4% and renderer-on A 308.7 MHz/59.0%/58.1%. One uncontrolled comparison per condition, DVFS and initial temperature differ; overhead not quantified. On/off results are not interchangeable with undisturbed power.

Raw evidence `../gpu-ab-{input,yuv,render}-{A,B}/`, diagnostic off `../gpu-timing-off-A/`; GPU per-query data is in `flutter-logcat.txt`. Controller sampling starts separate from native timestamps; YUV selects relative timer start, so window is approximate and not same source frames. Hardware perf counters remain unverified. Users have not reviewed this new APK for image/brightness/smoothness. Timing modes are default off.
