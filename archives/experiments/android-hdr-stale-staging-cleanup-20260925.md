# Android HDR 测试暂存回收（2026-09-25）

完整 P8.4 真机复验后发现测试应用私有 `files/android-hdr-staged` 约36 GiB、`cache/file_picker` 约34 GiB 的历史副本，设备 `/data` 空闲仅约1.8 GiB。两者是测试入口生成的暂存或缓存，不是 `/data/local/tmp` 中已核 SHA 的原始媒体。停应用后手工删除这两个目录，原始 HDR10/P8.4 文件保留，空闲升至约71 GiB；详见 [P8.4 复验](android-p84-direct-current-tree-20260925.md)。

现给测试应用增加两处回收：Android 启动时调用 `FilePicker.clearTemporaryFiles()` 清插件自己的缓存；HDR coordinator 创建前清理 `android-hdr-staged` 中不属于**当前 PID**的 `session-*` 目录，新目录使用 `session-<pid>-` 前缀。同进程仍在使用的会话及非 `session-*` 条目保留。清理失败时不继续创建新HDR会话，避免在空间不足状态下悄悄增加副本。文件选择器缓存清理失败只记录错误，不阻断普通测试应用启动。

单测创建旧PID、旧命名、当前PID及无关目录，证实只删除前两项；`android_hdr_sample_identity_test.dart` 6项通过，目标四文件 `flutter analyze` 无问题。真机 versionCode11052 APK SHA-256 `948d3bad6697be3e34ce441f760286ccd01fb03ee7f62948177a8eb52fa8c6f5`；启动前以 debug `run-as` 预置 `files/android-hdr-staged/session-999-fixture/sample.mp4` 和 `cache/file_picker/fixture/cached.mp4`。启动日志 `ANDROID_HDR_STALE_SESSIONS removed=1`，旧两路径均不存在，当前 PID 15223 的 `session-15223-HOKTXO` 保留，并成功打开已登记HDR10源。按返回键后当前目录仍存在，**自然退出回收没有由这轮证实**；随后强停进程、手工清除本轮当前会话并恢复10369基线包，`/data` 空闲约71 GiB。筛选启动日志 `artifacts/android-hdr-stale-cleanup-11052/startup-log.txt` SHA-256 `270c040f57e79b9a12db8270fb76e746b1885c68020c710bf5278668f28111dc`。

限制：PID复用极端情况下旧目录可能被保留到后续启动；多进程同时使用同一 app 私有目录的场景未测试。此逻辑属于 `media_kit_test` 实验入口，不自动解决生产应用的文件生命周期。文件选择器 API 缓存清理的实机证据是预置缓存路径消失；本轮没有量测缓存目录中有真实视频时的耗时或失败行为。
