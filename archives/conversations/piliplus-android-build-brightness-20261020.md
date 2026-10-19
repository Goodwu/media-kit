# PiliPlus Android 零改动构建与 screen_brightness 供给修复

## Current State
- 背景: 用户要求用本地 ~/src/media-kit 构建 Android PiliPlus App（参考 ~/src/PiliPlusX 构建方式），构建安装后手势调亮度无效。
- 目标: PiliPlus 源码/pubspec 零改动下完成 Android 构建、安装；修复亮度手势只变数字不变实际亮度。
- 当前状态: 构建管线跑通并装上 LG H870DS；brightness 插件缺供给根因已定位并已在 media_kit_video 恢复依赖契约，待复装验证。
- 关键结论:
  - PiliPlus 直接依赖 screen_brightness_platform_interface 并直呼 MethodChannel；原生实现 screen_brightness_android/ios 一直由旧 media_kit_video fork（bggRGjQaUbCoE native）以依赖声明带入构建，本库缺失导致插件从 GeneratedPluginRegistrant 消失，手势 UI 数字（应用内状态）照常变化但平台通道无应答。
  - 本地 media_kit_video 补回 screen_brightness_android ^2.1.3 / screen_brightness_ios ^2.1.2（解析为 2.1.6/2.1.4，与 PiliPlus 旧 lock 逐版本一致），PiliPlus 保持零改动。
  - PiliPlus Android 构建完整链：Flutter 3.47.7 独立 SDK（pubspec 精确钉定）→ 根级 pubspec_overrides.yaml 全量 path 指向本库 → lib/scripts/patch.ps1 android 的 25 个 SDK 补丁 + 9 个 material_ui 补丁（bash 等价）→ JDK17 flutter build apk --release --split-per-abi --target-platform android-arm64 --android-project-arg dev=1。
  - compat 分支 direction B 兼容层实测消除 PiliPlus lib/ 全部 156 个 API 错误；flutter test 通过；剩余 analyze 报错全在 tool/ohos（Android 构建不编译）。
  - marble（HyperOS）USB 安装被系统"应用安装拦截"，需机主放开，不绕过。
- 下一步:
  - 复装含 brightness 插件的 APK 到 LG 后由用户实机复核手势亮度。
- 接手入口:
  - 依赖契约修复：`media_kit_video/pubspec.yaml`
  - 应用侧构建输入：`/Users/wuweiwei1/src/PiliPlus/pubspec_overrides.yaml`（未提交）
  - 产物：`/Users/wuweiwei1/src/PiliPlus/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`

## Session Log
- S1: 2026-10-20 定位 brightness 失效为插件缺供给（对比新旧 pubspec.lock + .flutter-plugins-dependencies 证实 Android 29 插件无 brightness），在 media_kit_video 恢复旧 fork 依赖声明并提交本修复。

## Findings
- F1: 旧 PiliPlus lock 中 screen_brightness_android 2.1.6 / ios 2.1.4 均为 transitive；GitHub raw 证实来源是 bggRGjQaUbCoE/media-kit@native 的 media_kit_video pubspec（synchronized/wakelock_plus 同在）。本库 media_kit_video 原依赖表无 screen_brightness 任何条目。
- F2: 修复后 .flutter-plugins-dependencies 的 android/ios 插件列表分别出现 screen_brightness_android / screen_brightness_ios，解析版本与旧 lock 一致。
- F3: 首轮构建其余事实：flutter 3.47.2 全局不满足 PiliPlus 精确钉定 3.47.7，独立克隆 ~/flutter-sdks/3.47.7 解决；pub get 曾受残留 Gradle daemon journal-1 锁阻塞，gradlew --stop 后恢复。

## Decisions
- D1: 在 media_kit_video（而非应用 pubspec）恢复 screen_brightness 依赖。
  - 依据：旧 fork 的依赖契约即在此包；保持 PiliPlus 零改动目标；插件为真实实现而非空壳，符合"不造空插件"红线。
  - 备选方案：改应用 pubspec.yaml 直接加依赖（违背零改动）；pubspec_overrides 无法新增包（只能覆盖已有）。
  - 影响：所有依赖本库 media_kit_video 的应用都会带入 screen_brightness 插件注册，与旧 fork 行为一致。

## Action Items
- [ ] A1: LG 实机复核手势调亮度（数字+实际亮度同步变化）。

## Archive Metadata
- date: 2026-10-20
- entry: piliplus-android-build-brightness-20261020
- agent: ZCode (GLM-5.3)
- project: media-kit
- submodule: media_kit_video
