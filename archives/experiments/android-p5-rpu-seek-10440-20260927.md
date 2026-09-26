# P5 RPU 前后跳与 flush 短轮（2026-09-27）

- 设备：LYA-AL00/API29，固定官方 P5 1080p24 源 `/data/local/tmp/media-kit-dolby-official-p5-1080p.mp4`，SHA-256 `87fe0115f3002a621d2380a9f91852ef91a15854a446efe26de8744f77ef5346`。10440 APK SHA-256 `a0f6550509eb159b13f2f2fc26a8e085832ff5aad215dc0bc35e605a984ef042`，本地 arm64 JAR SHA-256 `5b9495f72893b8b62bb9085c67c9e87707b04f5910d3f09e9a79df82efcfd2e2`。
- 构建开启 Android HDR 事务、P5 RPU 管线、PlatformView、最大输出宽1440、`VideoFullscreenScope`及详细日志；设备属性 `p5_direct_dataspace_probe=1`、`p5_rpu_probe=2`、`p5_raw_yuv=1`。真横屏全屏，保持原自动亮度模式1，未调到255。
- 播放中 UI seek 前跳到184.232秒，再后跳到46.058秒。日志两次 seek 均实际执行；第一次 flush epoch 0→1→2，第二次 epoch 2→3→4，退出时 epoch 4→5。退出总结 `inputs=2346 outputs=2321 matched=2321 errors=0 discarded=25 unconsumed=0`。这证明本轮实际输出帧均找到已附 RPU；25个 discarded 包含 seek/停止时未输出的输入，不能当显示帧丢RPU。
- 退出时 `P5_RETIRE_FINAL maps=2310 reaped=2310 held_after=0 fallbacks=0`，`P5_IMAGE_FINAL acquired=2310 deleted=2310 current_image=0 retired=0`，约5秒后 `DIAG_SCOPE_PAGE_EXIT stop complete`。本轮只验证两个 seek 与一次页面退出；未覆盖多次同进程重开、长期播放、独立色准或面板亮度。
- 过滤原始同进程日志：`android-p5-rpu-seek-10440-20260927.log.gz`，SHA-256 `8355f189e9fcf9ffb068c72532537973c58baddb41467276539682dbcec43168`。结束后强停并以`adb install -r -d`恢复原10420，自动亮度1/设置37，三个P5属性0。
