# P5 热切源期间的输出尺寸缓存（2026-09-28）

## 源码事实

`NativePlayer` 切换媒体时会向 `videoParams` 流发送空的 `VideoParams()`。Android 视频控制器原先在宽高非正时直接返回，留下上一片源的 `_sourceDisplaySize` 与 `_appliedVideoSizeRequest`。这段间隙如果收到视图布局更新，`_applyVideoSizeLocked` 仍会按上一片源的宽高/纵横比计算输出尺寸。

## 候选修改与边界

当前media-kit目录的 `android_video_controller/real.dart` 在空参数事件时清空这两个缓存。随后新片源的有效 `VideoParams` 会重新计算并应用尺寸。`git diff --check` 通过；`dart format` 报告0处格式变更，但退出时因当前沙盒不能更新时间戳于用户目录的遥测文件而报错。

这只是源码推导的竞态修复，尚无热切源实机、双视图或颜色/连续画面验收。候选未提交。

## 回归前置分析（2026-09-29）

候选的可观测差异只在「同一 `AndroidVideoController` 收到空 `VideoParams` 的间隙内发生视图布局更新」时出现：无候选时 `_applyVideoSizeLocked` 会按旧片源宽高比 + 新布局算出错误的中介输出尺寸并发出 `SetSurfaceSize`；有候选时因 `_sourceDisplaySize == null` 直接跳过。逐一核对现有测试探针，均不能构成该场景：

- `MEDIA_KIT_ANDROID_AUTO_SDR_AFTER_P5_SECONDS`：`_openDirectSdrAfterHdr` 先 dispose 协调器并经 `_hdrOutputSlot.ensure` **重建输出控制器**，新控制器的 `_sourceDisplaySize` 本就是 null，不经过本竞态路径。
- `AUTO_SEEK_REOPEN`（非transaction重开，12639已跑）：重开**同一源**，空参数间隙内旧值与新值相同，尺寸请求结果无差异，只能验证无回归、不能证明修复收益。
- 双视图探针 `_runDualViewLifecycleProbe` 只在 transaction 路径的 `_openHdrSource` 内调度，5 秒相位切换与重开间隙（亚秒级）无法确定性地对齐。
- `MEDIA_KIT_ANDROID_LOCAL_SOURCE` 模式下 `sources` 只有一个条目，无法通过点击第二个源在 transaction 模式做同控制器热切（`_openHdrSource` 同 vo/hwdec 会复用同一输出槽/控制器，这是唯一现成的同控制器切换入口）。

## 热切源 A/B 实机验收（2026-09-29，12641/12642）

按上述前置分析补了默认关闭的热切探针（`MEDIA_KIT_ANDROID_HOT_SWITCH_TARGET` + `MEDIA_KIT_ANDROID_HOT_SWITCH_AT_SECONDS`，非transaction路径 `player.open` 直切 + 100ms 布局 ping 覆盖间隙）。首轮源 Glass P5（3840×2160，16:9），媒体6秒热切至 `media-kit-p84-rpu-12s-control.mp4`（3840×1920，2.0:1，无staging/无transaction校验）。两包除 `real.dart` 候选外完全一致（探针同一 diff；对照包构建于干净 e0102cf 树后已还原）：

- **对照包 12641（无候选，SHA `c58885c8...`）复现 bug**：空 `VideoParams`（22:27:36.755）到 p84 真实参数（37.164）的间隙内，布局 ping 触发了带旧 Glass 16:9 aspect 的中介 `SetSurfaceSize`——`996×560`（16:9，正确值应为 2.0:1 的 `1120×560`），其后另有 `2560×1440`（同样按旧 16:9 计算）；p84 参数到达后才收敛到 `2880×1440`/`1120×560`。
- **候选包 12642（含清空缓存修复，SHA `f6798b98...`）**：同一时间线（空参数 22:29:18.380 → p84 参数 18.813）间隙内**零尺寸请求**；参数到达即刻发出正确的 2.0:1 `2880×1440`，此后 ping 期间全部为正确的 `2880×1440`/`1120×560`。

两轮其余指标一致且全部通过：切源时 AImageReader 闭合（对照 356/356、候选 353/353，retired=0、empty_acquires=0），p84 播至 EOS（`AUTO_COMPLETED completed=true`），VO 停止与 `AUTO_PLAYER_DISPOSE completed` 正常，零取图失败、零渲染错误。截图（t6=Glass、t17/t31=p84）经图像识别确认（见下）。证据：`/private/tmp/media-kit-p5-hotswitch-12641/12642-*` 系列日志与截图。

**双视图回归（12645）**：候选包 + transaction + 双视图探针（竖屏 Row 布局、自动起播、无 preopen）。四个相位全部触发且播放持续；尺寸请求精确跟随槽位布局（全宽槽 `1440×810`、双分栏槽 `720×405`，全部 16:9 正确），播放期间无空参数事件、零取图失败、零渲染错误，退出闭合 2080/2080。12643（preopen 页面优先渲染，双视图布局未出现）与 12644（Flutter 列表项坐标未命中）为配置试错轮，仅日志留存。12642 热切轮本身即横屏全屏布局，全屏场景已覆盖。

结论：**切源间隙中介尺寸请求被候选完全消除，A/B 差异由日志逐条证明**；候选达到其针对问题的实机验收（热切源 A/B、双视图、全屏）。仍属未验：transaction 模式同控制器热切（需双源 fixture 注册）、SurfaceProducer 路径的同场景。

## Surface 重建边界复核

同一 `AndroidVideoController` 的普通 SurfaceTexture 使用同一 `VideoOutput` 和固定 `wid`，Java `VideoOutput.setSurfaceSize` 保存实际 `bufferWidth/bufferHeight`；SurfaceProducer 的重建则由自身 `setSize`/`onSurfaceAvailable` 维护尺寸和新 Surface 身份。现有 `_appliedVideoSizeRequest` 只跳过相同尺寸的重复请求，未发现仅因普通 Surface 回调就必须清空该缓存的证据。此判断来自源码，不替代 Surface 代次切换实机验收；因此本轮不扩大到 Surface 回调修改。
