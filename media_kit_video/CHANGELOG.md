## 1.3.1+1 (fork)

- **BREAKING**(api): `VideoControllerConfiguration` 平台开关收敛为子对象。迁移：
  - `usePlatformView`/`useHCPP`/`enableAndroidSurfaceProducer`→`android.usePlatformView`/`android.useHCPP`/`android.enableSurfaceProducer`
  - `matchAndroidTextureOutputToLayout`→`android.matchTextureOutputToLayout`
  - `androidAttachSurfaceAfterVideoParameters`→`android.attachSurfaceAfterVideoParameters`
  - `androidGpuApi`→`android.gpuApi`（copyWith 的 `clearAndroidGpuApi`→子对象 `clearGpuApi`）
  - `androidSurfaceTransfer`/`androidSurfacePixelFormat`→`android.surfaceTransfer`/`android.surfacePixelFormat`
  - `useNativeSurface`/`useNativeWindow`→`darwin.useNativeSurface`/`darwin.useNativeWindow`
  - 子对象经 `copyWith(android: config.android.copyWith(...))` 修改。
- **REFACTOR**(darwin): native surface 由 CVDisplayLink/CADisplayLink 按显示刷新率驱动并按生产帧计数门控重绘；Metal blitter 改单一 pre-commit `addCompletedHandler` 异步完成，buffer 归还经 in-flight 跟踪与池 hold 闭环（主线程不再逐帧阻塞）。
- **FEAT**(android): Phase 1 HDR 能力路由（需求 `docs/requirements/android-hdr-auto-output.md` v3）。新增公开 API 均为增量入口，无删除的公开接口：
  - `HdrVideoSession`/`HdrVideo`/`HdrVideoScope`：会话编排（九步开播流程、代次失效与回滚、每代次最多一次解码器复核重建、失败最多再试一条 HDR 候选、dataspace 门禁只认 `applied`）、widget 挂载与内置全屏跟随、路由报告（`report` 即 `HdrOutputReport.actual`）与五类事件流（RouteApplied/Degraded/Reclassified/CapabilityChanged/Error）。
  - `HdrCapabilities`：能力查询（SDK、displayHdrTypes、HEVC 解码器档位、DV 解码器、dataspace bridge 与扩展信息）+ P5 选项探测（`dovi-p5-fast-path`）+ `Changed` 能力变化事件（Phase 1 单会话共享开关）。
  - `HdrSourceDescriptor`/`HdrSourceClassifier`：七字段源描述与分类；DV 兼容 ID 由基础层传输函数推断（pq→8.1、hlg→8.4、bt.1886→8.2）。
  - `HdrStrategy`/`HdrRoutingPolicy`/`HdrRoutePlanner`：策略与成熟度枚举、偏好配置（`allowExperimental`）、开播前预测与执行同源（同一 planner 函数）。
  - `HdrRoute`/`HdrCandidate`/`HdrRoutePrediction`/`HdrDegradeReason`：路由、候选（含跳过原因）、预测与降级原因（含 `unsupportedStrategy`、`p5PipelineUnavailable`）。
  - `HdrOutputPreference`：`auto`/`off` 播放偏好。
  - Android 原生层：`PlatformVideoView` 的 `applyDataSpace` 改为四元组回报 `{applied, path, requested, readback}`；`SurfaceDataSpaceExt` 增加 default `id()`/`isApplicable()`。
  - `HdrOutputDiagnostics`：七层诊断日志（capability/predict/classify/readback/decision/degrade/recover，默认关闭）。
  - 内部：旧 darwin/OHOS 的 `HdrOutputReport` 改名 `HdrTransactionReport`（内部类型，未导出过公开面）。
- **FEAT**(android): 默认偏好与"源 × 策略"成熟度表以需求第 3.4/6 节为准（代码常量表由 S3 解析单测逐格锁定同步；P8.4×`baseLayerConvert` 与 HLG×`baseLayerDirect` 现为 experimental，实机升级轮证据完整、待人工观察画面后升级 verified）。
- **DOCS**: 迁移指南（PiliPlusX 场景三步：`HdrCapabilities.predict` 选档 → `HdrVideoSession`/`HdrVideo` 挂载开播 → 展示 `report.actual`/按 App 策略处理事件）；hint 通道与解码器复核语义（复核仅在代次内做一次，重建最多一次）；dataspace 门禁只认 `applied`，`path`/`readback` 仅作诊断。
- 已知限制：seek 不变量待补验证项（S10 实机记录）；P8.1 升级确认受样片阻塞（公开仅 10 帧 FATE 样片）；Mi Note 3 不在位（displayHdrTypes 空集验证缺实机）；no-HLG 开播前规划相候选跳过以报告候选原因披露、不发 Degraded 的口径决策待确认。
- **DEPRECATED**: 无删除的公开接口；会话 API 是增量入口。R4.4 的 `probeHdrCapabilities` 废弃发生在 PiliPlusX 侧（S12 接入时删除）。

## 1.3.1

- fix(windows): notify `VideoOutput.Resize` on platform thread
- fix(linux): notify `VideoOutput.Resize` on platform thread
- fix(android): `VideoController` implementation
- fix(android): remove deprecated API usage

## 1.3.0

 - **REFACTOR**: screen_brightness -> screen_brightness_platform_interface.
 - **REFACTOR**(android): simplify AndroidVideoController implementation.
 - **REFACTOR**(android): VideoOutput SurfaceTextureEntry -> SurfaceProducer migration.
 - **REFACTOR**: use setProperty API in NativeVideoController.
 - **FIX**: improve responsiveness of showing controls on mobile.
 - **FIX**: bump web to 1.1.0.
 - **FIX**: cast to JSObject.
 - **FIX**: not call super.didChangeAppLifecycleState(state);.
 - **FIX**: not call super.didChangeAppLifecycleState(state);.
 - **FIX**: wakelock print.
 - **FIX**: subtitles not shifting on controls show/hide.
 - **FIX**: set width/height from VideoParams in NativeVideoController.
 - **FIX**: seek inside onPointerMove.
 - **FIX**(windows): automatic IDXGIAdapter selection on windows 10 or greater.
 - **FIX**(android): waitUntilFirstFrameRenderedCompleter.
 - **FIX**(android): --hwdec=auto-safe as default.
 - **FIX**: dispose ValueNotifier(s) in PlatformVideoController.
 - **FIX**: fullscreen.
 - **FIX**: long press video speed reset issue.
 - **FIX**: wrong value in brightness builder callback.
 - **FIX**: Use a Scaffold as the outermost widget on fullscreen video pages.
 - **FEAT**: upgrade volume_controller dependency and refactor related code.
 - **FEAT**: seek on double tap custom duration support.

## 1.2.5
- fix(android): wait for SurfaceControl HDR dataspace transaction commit
- fix: subtitleView not being updated
- fix: mobile double tap areas hidden but still mounted
- fix: mobile center click is delayed
 
- feat: desktop video controls mouse hides with controls
- feat: desktop on tap pause and play
- feat: desktop on double tap fullscreen
- fix: windows crash by @Airyzz [#900](https://github.com/media-kit/media-kit/pull/900)
- feat: auto pass changes to fullscreen without having to call .update

## 1.2.4

- fix: web compile error

## 1.2.3

- feat: `VideoState.update` & `VideoViewParameters`

## 1.2.2

- fix: override `setState` & check `mounted` in `MaterialVideoControls` & `MaterialDesktopVideoControls`

## 1.2.1

- fix(android): clear `android.view.Surface` before playback
- feat: `MaterialVideoControlsThemeData.seekBarAlignment`

## 1.2.0

- fix: `MaterialVideoControls` layout

## 1.1.9

- fix: unmount `CircularProgressIndicator` buffering indicator if invisible
- fix: pass all video attributes to fullscreen route
- fix: prevent controls from hiding during seek
- fix: hide last video's frame upon `Player.open`
- fix: `ThemeData.copyWith` override
- fix(android): `hwdec=auto-safe` w/ `enableHardwareAcceleration=true`
- fix(windows): fullscreen for non-primary monitors
- fix(darwin): `mpv_render_context_free` call
- fix(darwin): memory leaks
- fix(ios): fix `disposeMPV`
- feat: `VideoControllerConfiguration.androidAttachSurfaceAfterVideoParameters`
- feat: center the seek-bar within its parent `Container` for improved tap area
- feat: `backdropColor` argument in `MaterialVideoControlsThemeData`

## 1.1.8

- fix: pass all `*VideoControlsTheme`(s) to fullscreen `context`

## 1.1.7

- fix: add `await` to `maybePop` when exiting fullscreen
- fix: `MaterialVideoControls`/`MaterialDesktopVideoControls` seekbar glitch
- fix(android): S/W rendering fallback
- fix(android): create fresh `android.view.Surface` for every video output

## 1.1.6

- fix: programmatic fullscreen API
- fix(android): pause upon entering fullscreen
- fix(android): `waitUntilFirstFrameRenderedNotify` in `FlutterFragmentActivity`

## 1.1.5

- fix(android): `waitUntilFirstFrameRenderedNotify` fallback & release-mode

## 1.1.4

- feat: `Video` `resumeUponEnteringForegroundMode`
- feat(android): `waitUntilFirstFrameRenderedNotify` implementation

## 1.1.3

- feat(android): `VideoControllerConfiguration.scale`
- fix(android): use `hwdec=auto`
- fix(android): `SurfaceTexture.setDefaultBufferSize` & render race

## 1.1.2

- fix(windows): memory leak in `GetVideoWidth`/`GetVideoHeight`
- fix(linux): `GThread*` leak in S/W render & `video_output_get_(width|height)`
- fix(linux): H/W support for multiple videos
- build(darwin): bump `mpv` headers to `0.36.0`
- build(darwin): use symlinks for `FRAMEWORK_SEARCH_PATHS`, `media_kit_libs_*** >= 1.1.0`
- fix(darwin): remove black screen when switching videos ([#332](https://github.com/media-kit/media-kit/issues/332))
- feat: `Video`: expose `onEnterFullscreen` & `onExitFullscreen`
- feat: feat: `visibleOnMount` `MaterialVideoControls`/`MaterialDesktopVideoControls`
- fix: display `bufferingIndicatorBuilder` even if controls are hidden

## 1.1.1

- chore: `try`/`catch` native calls to hide stray logs
- fix: `MaterialDesktopVideoControls`: do not add `onTapUp` callback if `toggleFullscreenOnDoublePress` is disabled

## 1.1.0

- feat: `SubtitleView`, `SubtitleViewConfiguration`
- feat: `shiftSubtitlesOnControlsVisibilityChange` in `MaterialVideoControls` & `MaterialDesktopVideoControls`
- feat: apply rotation from metadata to video output
- feat: improve wakelock behavior
- feat: `pauseUponEnteringBackgroundMode`
- fix: `bufferingIndicatorBuilder` padding in `MaterialVideoControls` & `MaterialDesktopVideoControls`
- fix(windows): maintain aspect ratio in s/w rendering pixel-buffer size clamping
- fix(linux): maintain aspect ratio in s/w rendering pixel-buffer size clamping
- perf(android): use `hwdec=mediacodec` w/ `enableHardwareAcceleration`
- deps: migrate [`package:wakelock_plus`](https://pub.dev/packages/wakelock_plus)

## 1.0.2

- fix(video/macos): fix fullscreen support

## 1.0.1

- fix: synchronize `VideoController` constructor
- fix: `fullscreen` video controls theme data not being applied

## 1.0.0

- feat: web support
- feat: fullscreen API
- feat: acquire wakelock
- feat: support for AGP 8.0
- feat: pre-built video controls
- feat: `controls` argument in `Video` widget
- feat: `AdaptiveVideoControls`, `MaterialVideoControls`, `MaterialDesktopVideoControls` & `NoVideoControls`

## 0.0.12

- fix(android): improve `Texture` resize handling

## 0.0.11

- fix(android): improve `Texture` resize handling

## 0.0.10

- feat: `VideoControllerConfiguration`
- feat: `VideoController.waitUntilFirstFrameRendered`
- refactor: clean-up package structure
- refactor: remove `VideoController.dispose`
- refactor: `VideoController.create` -> `VideoController` constructor
- fix(android): add `av1` to `hwdec-codecs`
- fix(android): use `--vo=gpu` + `--hwdec=mediacodec-copy` /w `enableHardwareAcceleration`

## 0.0.9

- fix(android): revert to `--vo=mediacodec_embed` in `enableHardwareAcceleration`

## 0.0.8

- fix(android): subtitle rendering
- fix(android): video rendering inside emulators (#149)
- fix(android): video rendering with `enableHardwareAcceleration: false`

## 0.0.7

- fix(linux): VAAPI hardware acceleration
- perf(windows): `VideoOutput::Resize`: delete texture objects in background

## 0.0.6

- fix(windows): synchronize texture object deletion in on unregister _v.i.z_ `VideoOutput::Resize` or `VideoOutput::~VideoOutput`

## 0.0.5

- Android support
- feat: `VideoController.setSize`
- fix: set `vo` to `libmpv` before creating render context
- refactor: `VideoController.create` takes `Player` reference instead of `handle`

## 0.0.4

- fix: use `mkdir` instead of `.gitkeep`

## 0.0.3

- fix: add `.framework` & `.xcframework` for all libs

## 0.0.2

- macOS support:
  - Hardware: MPV_RENDER_API_TYPE_OPENGL + pixel buffer + METAL
  - Software: MPV_RENDER_API_TYPE_SW + pixel buffer
- iOS support:
  - Hardware: MPV_RENDER_API_TYPE_OPENGL + pixel buffer
  - Software: MPV_RENDER_API_TYPE_SW + pixel buffer
- fix(windows): use `TextureRegistrar::UnregisterTexture` release callback to free texture resources
- fix(windows): synchronize texture unregister & release on frame dimensions change
- feat: `aspectRatio` parameter for `Video` widget

## 0.0.1

- Initial release
- Windows support:
  - Hardware: MPV_RENDER_API_TYPE_OPENGL + ANGLE + DirectX 11
  - Software: MPV_RENDER_API_TYPE_SW + pixel buffer
- GNU/Linux support:
  - Hardware: MPV_RENDER_API_TYPE_OPENGL + GDK/GL
  - Software: MPV_RENDER_API_TYPE_SW + pixel buffer
