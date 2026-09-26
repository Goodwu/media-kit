# GPU window 已连接后的 PQ dataspace 探针（2026-09-25）

此前应用自建 SurfaceView 在 `surfaceCreated` 和发布 WID 后请求 PQ/HLG 都被 NDK 返回 `-22`。本实验检查延后到 gpu-next 已连接 window 后，是否改变同一 `ANativeWindow_setBuffersDataSpace` 的结果；不把诊断当成 HDR 输出。

默认关闭的 `debug.media_kit.late_pq_probe=1` 在 `PlatformVideoView` 创建 **无 HDR 初始声明、RGBA_1010102 holder** 的 Surface 后8秒运行一次。JNI 在同一 Surface 读取原 dataspace、尝试 `ADATASPACE_BT2020_PQ`、再次读取；仅若成功且原值可读才恢复原值。callback 检查 view 未 dispose、generation 未变、Surface 有效。测试页另以 `MEDIA_KIT_ANDROID_GPU_SDR_10BIT_PROBE=true` 请求10-bit holder；用 `egl-output-format=rgb10_a2` 才能保证 gpu-next 连接后仍为 format43。生产默认均关闭。

| 包 | 输入/输出 | 有效性 | 结果 |
| --- | --- | --- | --- |
| 11004 | 4K HDR10→BT.709 SDR，gpu-next，硬解；未指定 EGL output format | 有效 format2 诊断，不是10-bit窗口对照 | 8秒后 format2、dataspace 0，PQ `-22` |
| 11005 | 同输入，`egl-output-format=rgb10_a2` | format43诊断有效，但硬解 `acquireLatestImage` 映射报错，不作为连续视频帧证据 | 8秒后 format43、dataspace 0，PQ `-22` |
| 11006 | 854×480 SDR、软件解码、rgb10_a2 | **无效播放轮**：`/sdcard/Download` 源因 scoped storage 权限拒绝，只有1×1占位 buffer | format43、PQ `-22` 不能回答有视频 buffer 时机 |
| 11007 | 同 SDR 源复制到 `/data/local/tmp` 后重建，软件解码、gpu-next、rgb10_a2 | 有效：视频参数 yuv420p/854×480/BT.601，画面截图正常；SF 后续见 `activeBuffer=[854x480:896,RGBA_1010102]` | 8秒后同 window format43、1440×810、before0、PQ `-22`、during0、after0 |

11007 APK `/tmp/media-kit-sdr-late-pq-probe-11007-arm64.apk` SHA-256 `94c384577b452a9c5a8723847fdd84e7c78b15b7d0db626f3b49fe316e62305b`；日志 `/tmp/media-kit-sdr-late-pq-probe-11007-logcat.txt` SHA-256 `b5b5de585ef7878620cf56c8b2ead3845e83ac6dfd106a7ebbe0591253c14b47`；SF `/tmp/media-kit-sdr-late-pq-probe-11007-sf.txt` SHA-256 `e8ee2c71a056d706ebc40720c7540cad8f96fbe7dc940f2118abb2d0394f2d72`；可见画面 `/tmp/media-kit-sdr-late-pq-probe-11007-screen.png` SHA-256 `06861edbee9ab7163ea2e3927bee9c98de7046f83add33da3f1a324d8c1f659f`。日志在 03:32:40 打开源并报视频参数，03:32:47 探针返回；SF 与截图采在其后。没有在探针**之前**冻结 SF 的 activeBuffer 快照，因此严格说仅证实已连接的10-bit GPU window晚设失败和同轮稍后确有视频 buffer，不能用这个日志独自证明首个实际视频 present 早于调用。

结合 11005/11007 的 format43 晚设失败，单纯把设置从 Surface 创建推迟8秒并让 gpu-next 连接，不足以越过这台手机的 PQ dataspace 门禁。它不确定厂商内部拒绝分支、不同 Surface producer 或私有 HDR 路径；下一步应查 Surface HDR support/usage 合约或寻找真实可生产 HDR buffer 的后端，不再仅调整同接口调用时机。测试结束强停应用、属性回读0、移除本轮设备临时 SDR 文件，`adb install -r -d` 恢复10369基线包。
