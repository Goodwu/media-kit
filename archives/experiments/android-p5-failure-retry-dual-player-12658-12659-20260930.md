# P3 失败重试复测与双播放器双视图（12658–12661，2026-09-30）

## 结论

- **失败重试复测通过（产品路径，12661）**：初始源不存在 → `AUTO_SOURCE ERROR`（staging 校验拒绝）→ 恢复链 `ANDROID_HDR_RECOVERY_OPEN` 打开备用源（已注册 SHA 的 `media-kit-p5-full.mp4`，含 243MB staging，失败后 10 秒完成恢复）→ 播放持续推进（time-pos 29.9→39.9）、退出资源闭合（P5 finals 2201/2201、retired=0）、零崩溃、`AUTO_PLAYER_DISPOSE completed`。broker 与切源候选合入后，产品 `RECOVERY_SOURCES` 失败重试链无回归。
- **双播放器双视图同时显示通过（12659）**：新增默认关闭的双播放器模式（第二 `Player`+`VideoController` 独立播放 Mystery Box，主播放器走 transaction 播 Glass）。日志证实**两个输出同时活动**（两个并存 `setSurfaceSize 720×405` = 左右半屏各自独立输出）；退出时两输出先后 Dispose、主播放器 unregister 到达、P5 finals 326/326、零崩溃；截图经图像识别确认左右两半**同时显示不同的实际画面**（左 Glass 吹管/熔融玻璃，右 Mystery 公园与舞者场景含 DV 水印），非单活动 Surface。

## 过程记录

- 12658（输出 Dispose 注入）为**无效注入形态**：通道层直接 Dispose 输出绕过 Dart 控制器簿记，输出槽复用仍认为输出存活的旧控制器 → 视频区不重绑（黑屏），同时 mpv 播放与资源本身正常（position 推进、2054/2054 闭合、零错误）。该形态产品路径不可达（产品只经控制器自身路径销毁输出）；教训已记：失败注入必须走产品可见的失败面。另该轮 COMMON 漏配 `PREOPEN_FULLSCREEN`，页面为竖屏列表布局。
- 12660（恢复源=Mystery Box）被 staging 校验拒绝（`Unknown sample SHA-256`——Mystery SHA 未注册 fixture 表，PQ 轮均走命名分类），改用已注册 `media-kit-p5-full.mp4`（SHA `328cae5c`）后成功。

## 探针实现（随代码提交）

- `MEDIA_KIT_ANDROID_OUTPUT_FAILURE_AT_SECONDS`：媒体到位后销毁当前输出并 `_openHdrSource` 同路重开（该注入形态经 12658 判定无效，保留探针供后续设计产品可见注入时参考）。
- `MEDIA_KIT_ANDROID_DUAL_PLAYER_VIEW` + `MEDIA_KIT_ANDROID_DUAL_PLAYER_SOURCE`：页面级第二 Player（静音、循环、独立源），双 Expanded Row 布局，页面 dispose 时释放。

## 包与证据

- 12658 SHA `8d62d81a...`、12659 SHA `ece52e12...`、12661 SHA `1002cf3b...`（均 e0102cf+12627 JAR）。
- 日志与截图：`/private/tmp/media-kit-p5-output-failure-12658-*`、`media-kit-p5-dual-player-12659-*`、`media-kit-p5-open-failure-recovery-1266{0,1}-*`。

## 边界

- 12661 为打开失败的恢复链复测；12473–12477 的 ACK 丢失/晚到输出交错注入变体如需复测须重建专用注入开关。
- 双播放器场景第二播放器走非 transaction 普通路径；两播放器的 broker 注册均已覆盖（各自 NativeCallable 句柄注册）。
