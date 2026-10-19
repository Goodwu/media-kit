# 方向 B：播放器接入与构建说明

日期：2026-10-19，Asia/Singapore。

方向 B 已由用户批准。SDK 继续使用 `compat/piliplus-zero-change-20261018`；应用业务、网络、账户及原生宿主不改。应用接入以 SDK 仓内的受控补丁维护，不写入上游 PiliPlus 仓库，不冒称原始应用零补丁。

## 源码入口

SDK 显式入口：`media_kit_video/lib/src/integration/routed_video_playback.dart`、`routed_simple_video.dart`，由 `media_kit_video.dart` 导出。Android 复用 `HdrVideoSession`，视图跟随其控制器通知；其他平台保留普通视频输出，不声称取得 Android 同级 HDR 认证。原 `Player` 不被透明拦截。

应用改动：`tool/piliplus_compat/direction_b/player-integration.patch` 和同目录 `manifest.json`。只允许清单中的七个 Dart 接入文件，修改初始化/打开/控制/释放、主视频与直播的提前挂载、画廊输出及两个已有播放控制调用点。字幕保留原配置和拖动接口，但不缓存已淘汰的控制器。预初始化时输出可在原封面后挂载，不等于自动播放。

当前补丁 SHA256：`2109c3c44c8f93febf04636d557f863d6c05b15fa5a1287ed3f86f2a8474443b`。审查应用提交：`2eaeeb731462dad92246809d5b5ac716c671736b`。这不是永久钉定：CI 每轮先解析最新 main，各平台使用本轮同一应用提交；若七个文件的前像改变，构建明确拒绝并要求重新审查补丁，不能模糊套用。

## 本机构建

准备干净的 SDK 分支 checkout、最新原始 PiliPlus checkout，以及符合应用 pubspec 要求的 Flutter Git checkout。根据平台准备 Android SDK/JDK、Windows 桌面编译工具、Linux 依赖或 Xcode/CocoaPods；可对照 `.github/workflows/piliplus-direction-b-build.yml`。不要在自己的工作源码目录手工套补丁后调用构建器。

```sh
python -m pip install -r /path/to/media-kit/tool/piliplus_compat/requirements.txt
python -B /path/to/media-kit/tool/piliplus_compat/build_direction_b.py \
  --sdk-root /path/to/media-kit \
  --app-root /path/to/original-PiliPlus \
  --flutter-root /path/to/flutter \
  --platform android \
  --output /path/to/new-isolated-build
```

`--platform` 支持 `android/ios/macos/windows/linux`；输出目录必须不存在，且不能与输入目录重叠。构建器创建隔离副本，读取 Git 原始补丁字节，核验摘要与七文件前后像，保存实际差异，生成可追踪的临时应用派生提交，然后调用现有严格构建器。上游 checkout 保持不变。Windows 的 CRLF 检出表示不改变被审查的 Git 字节。

输出根目录的 `direction-b-receipt.json` 明确记录 `zeroPatch:false`、上游应用和派生提交；`direction-b-input.patch` 与 `direction-b-applied.patch` 保留输入及实际应用差异；`validation/` 内保留依赖解析、分析、构建、源码核验回执和日志，产物位于 `validation/app/build/`。

## 两条应用验证线

`Original PiliPlus builds (T1, no source patches)`：原始应用仅替换依赖，保留已完成的兼容门禁。

`Direction B PiliPlus builds (T1B player integration)`：明确应用七文件接入补丁，验证新的实际接入路径。五个平台都必须通过，不能以跳过或原始 T1 成功替代。

本批命令是 Android ARM64 Debug APK、iOS Debug `--no-codesign`、以及 macOS/Windows/Linux Debug。SDK 全量回归及 macOS 专项测试有独立工作流。实际结果以主交接 JSON 的提交和运行编号为准，不用早期绿色结果认证后续代码。

## 未完成的验收范围

编译通过不等于真实视频已正确显示。仍须完成无应用 hint 的完整片源事实准入、其他并发及重建场景、最新 mpv/FFmpeg 等原生源码的各平台构建和最终产物身份核验、Release/签名、原应用功能与 PiP/截图、真机和 HDR 显示路径验证。本批 Linux 系统 libmpv 回归只证明相应接口行为，不证明最新 fork 原生二进制已交付。不要将本批 Debug 包标为可上线版本。

后续接续：先读 `piliplus-zero-change-handoff-20261018.json` 和方向 B 执行记录，继续已有分支。已完成的 P0/P1/P2b 和方向 B 接入不重新开发；不再回到待决 A/B 状态。若新的实现成本明显超出限定接入范围，再列具体取舍与用户讨论。
