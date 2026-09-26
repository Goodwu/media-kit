# P3：6235 P8.4 模拟无 HLG 回退真机实验（2026-09-24）

- 设备：`3EP7N18C28016072`，Huawei LYA-AL00，Android 10。APK `versionCode=6235`，SHA-256 `c42eeb250f23ad30af62c5b9e5368d88b3eb62af6db57ce7dadab22719e761b4`；固定 P8.4 输入 SHA-256 `7626cac28819ffd1377a712b56c7cc4bbf8677f5db4b39fb0c83f92e58d74443`。
- 干净轮：强停应用、清空 logcat、启动并进入单视频测试页；只触发自动打开，等待超过 10 秒。最初一次被系统游戏中心欢迎页遮挡，随后手动重复点击导致 `Sample staging cancelled`，这些轮次不作为候选结果。
- 真机报告实际 HDR 能力 `{2,3}`，测试开关 `simulateNoHlgForP84=true`。Flutter `VIDEOPARAMS` 仍为空时，应用创建的 `RGBA_1010102`、1440×810 Surface 请求 PQ dataspace `163971072`（`0x09c60000`），`ANativeWindow_setBuffersDataSpace` 返回 `-22`，`actualDataspace=0`；sRGB 探针返回 0。10 秒后 `prepareOutput` 等待初始输出绑定超时，未出现 `ANDROID_HDR_OPEN`、首帧或可验的 PQ 视频层。超时清理时另有一次 `Android PlatformView disposed before its initial output bound` 未处理异常，应单独检查错误收束。
- 结论：本轮证明模拟无 HLG 开关生效，且被选中的 PQ Surface 尝试仍卡在与 HDR10 PQ 相同的 dataspace 门禁。它没有证明 P8.4 的 HLG→PQ 像素转换、RPU 剥离或真实无 HLG 设备兼容；没有到达这些阶段。后续先解决 HDR Surface 的 consumer/usage 合约或选择设备支持的生产路径，再继续 T2 回退验收。
- 证据：`/tmp/media-kit-p3-p84-6235-logcat.txt` SHA-256 `02db897d15ee83550b8b1755b6e8fcb2df841c868ff4faf7094a2c583ea5b944`；`/tmp/media-kit-p3-p84-6235-sf.txt` SHA-256 `b7149d0618e43f5b7500397215e46db697fc6b40a0f969849b3a28993af26ddd`；`/tmp/media-kit-p3-p84-6235-final.png` SHA-256 `529eb3187a41a2d8b23a4842f8264b79b74f29fcfd94af11992aa7e74513d96c`。

## 8320 清理修正复测

仅在 Android 控制器的初始输出 Future 两个 `completeError` 分支附加错误消费监听，保留原 Future 对实际等待者的错误。以同一本地原生 JAR SHA `e7b4cfefed60052277519a39d4834eb33d35f08342c59610279232878d1036bd`、相同 P8.4 源和模拟回退开关构建 APK `/tmp/media-kit-p84-forced-pq-cleanup-6320-arm64.apk`，SHA-256 `ba255f9a73c8ef34030537dff9ea34fb5b587a78e2d30d580b32c0c7f6aeb864`，设备回读 `versionCode=8320`。

干净真机轮自动打开：能力仍 `{2,3}`、模拟开关 true；PQ dataspace `0x09c60000` 在同样 format43/1440×810 Surface 返回 `-22`、实际0，10秒后同样由 `AUTO_SOURCE` 记录等待超时。采集至超时后约4秒的完整 logcat未再见 `Unhandled Exception` 或 `disposed before its initial output bound`；这仅验证该复现路径上的错误收束，并非所有处置竞态。日志 `/tmp/media-kit-p84-6320-cleanup-logcat.txt` SHA-256 `979048e77b6261960a035ed2d8a1cea69fbb6c62f0c8b90c45e449d620485d2d`。构建成功，目标 Dart analyze仅既有两条 info，`git diff --check`通过。手机保留8320包、应用强停。HDR Surface主阻断未改变。
