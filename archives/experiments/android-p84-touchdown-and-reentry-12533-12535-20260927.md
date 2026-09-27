# P8.4 触摸按下与同进程退出重入（12533–12535，2026-09-27）

## 触摸按下至全屏内容：12533

- 华为 LYA-AL00，Android 10，arm64；固定 P8.4 全片、普通列表点击、同一 Video 横屏全屏、Texture→SDR、`gpu-next`/`mediacodec`。
- Activity 的 `dispatchTouchEvent` 分别记录 ACTION_DOWN、ACTION_UP 的 `elapsedRealtimeNanos`，与 Flutter Surface PixelCopy 首次明显内容使用相同时钟。
- 三次独立进程 ACTION_DOWN→首次明显内容为 **766.833、788.686、680.906 ms**；对应 UP→内容为764.380、783.177、675.971 ms。三轮 `layoutBound=true`，无打开异常。日志 `/private/tmp/media-kit-12533-down-1.txt` 至 `...-3.txt`。
- 输入事件到达应用前的触摸硬件/系统延迟、PixelCopy 之后的显示合成与面板发光仍未测；这些数字不能称为光学首帧。

## 同进程真实退出重入：12534/12535

- 12534 从主菜单进入播放页，播放后按 Back 退出全屏、再按 Back 退出播放页时，`Player.dispose` 完成，但 `VideoFullscreenScope.onBeforePop` 错误要求仅 HDR 事务才有的 `_hdrLastDisposeReport`，报 `Player or output disposal did not complete safely` 并留在黑色视频页。这是测试页门槛误用，不是播放器清理失败。
- 12535 将报告检查限于 HDR 事务。APK SHA-256 `40e9fba86c901cb59d4438e89d86437974ddeed14e5101b8415fa04facd4a5dd`。同一 PID `20750`，第一次播放 ACTION_DOWN→内容 **828.577 ms**。两次 Back 后记录 `DIAG_SCOPE_PAGE_EXIT stop begin`→`AUTO_PLAYER_DISPOSE completed`→`stop complete`，约 **5.100 秒**，返回主菜单，截图 `/private/tmp/media-kit-12535-after-pop.png`。再进入一个全新播放页，初始视频区为黑色，第二次 ACTION_DOWN→内容 **656.213 ms**、`layoutBound=true`；约 2 秒和 5 秒的全屏截图 `/private/tmp/media-kit-12535-reentry2.png`、`...reentry5.png` 显示实际视频进展。第二次首帧无旧帧污染。完整日志 `/private/tmp/media-kit-12535-reentry.txt`。
- 该同进程路径验证了新播放页和新 Player 的退出重入短轮；5.1 秒退出清理值得在生命周期任务中分段定位。两次短轮不构成冷启动分布、长期稳定性、色准、音画同步或光学验收。

测试后恢复原 versionCode 12492、六项诊断属性 0、自动亮度模式 1，屏幕熄灭。
