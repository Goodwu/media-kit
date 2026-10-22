# VideoRouteCapabilities 桌面/darwin 显示适配器（video-route-capabilities-darwin-windows）

## Current State（2026-10-22）

- **已实现并本地提交（未推送）；Windows/darwin 实机构建待验**（compat 分支，基于 `e2e6f41c`）。
- 内容：为既有 `VideoRouteCapabilities.Get` 通道补 **darwin 与 Windows 显示适配器**（此前仅 Android）：
  - **macOS**（`common/darwin/Classes/plugin/MediaKitVideoPlugin.swift`，经符号链接同时进 macos/ios 构建）：`NSScreen.screens` 任一屏 `maximumExtendedDynamicRangeColorComponentValue > 1.0` → display `resolved` + `hdrTypes [2,3]`（HDR10(PQ)=2、HLG=3；macOS 不做 DV 直通）；否则 `[]`（明确 SDR）。macOS <10.15 → `queryUnavailable`。
  - **iOS**：无公开显示 HDR 查询 API → `queryUnavailable`（Dart 按未知处理、不置灰）。
  - **Windows**（`windows/media_kit_video_plugin.cc`）：`GetDisplayConfigBufferSizes`/`QueryDisplayConfig` + `DISPLAYCONFIG_DEVICE_INFO_GET_ADVANCED_COLOR_INFO`，任一活动输出 `advancedColorEnabled` → resolved + `[2,3]`；无 → `[]`；查询失败 → `queryUnavailable`。
  - 三端 **sources 一律回显 `censusComplete=false` + 空 decoders**（显式 unknown，遵守 Dart 侧"other platforms return explicit unknown source results, not simulated support"契约）；`hdr` 回空 map（displayHdrTypes 由 Dart 从 display 覆盖注入）。
  - **no-libs stub 变体不加通道**：MissingPluginException → Dart 走 `adapterUnavailable` → 不置灰，维持"宁可漏灰"兜底。
- 动因与消费方：PiliPlus 视频格式置灰（`~/src/PiliPlus` 的 CODEC-CAPABILITY-GRAYING-20261022），显示轮需全平台面板 PQ/DV/HLG 事实；迁移后 App 侧零平台代码（App 的 macOS/Windows Runner 改动全部回退），显示/解码能力统一经 `VideoRouteCapabilities.query`。
- 验收：`swiftc -parse` 通过；schema 人工对齐 Dart 校验（`raw['schema']==1`、`platform` String、`display.status` String + `hdrTypes` List<int>、sources 逐 key 回显、`hdr` Map）。**未验证**：Windows C++ 编译（mac 主机无 MSVC）、darwin/Windows 实机（macOS 构建受阻于宿主磁盘满）。
- 下一步：磁盘清理后 `flutter build macos --debug`（须用 `~/flutter-sdks/3.47.7`）验证 darwin 编译与 EDR 探测；Windows 侧待 Windows 环境编译验收。

## 关键结构事实（复用依据）

- darwin 插件入口唯一：`media_kit_video/common/darwin/Classes/plugin/MediaKitVideoPlugin.swift`，经 `macos|ios/media_kit_video/Sources/media_kit_video/plugin/common/` 符号链接进两端构建（podspec source_files `plugin/**/*.swift`）；通道名 `com.alexmercerind/media_kit_video`，Android/Windows/darwin 三端一致。
- Dart 侧 `VideoRouteCapabilities.query`（`lib/src/routing/video_route_capabilities.dart`）对桌面回包的要求：schema 1 + platform/displa/sources/hdr；`display.status=='resolved'` 时才取 `hdrTypes`，否则 `displayHdrTypes=null`（未知≠无 HDR）。
- Windows 插件 `HandleMethodCall` 为 if/else 链（`media_kit_video_plugin.cc`），新分支插在 `Utils.ExitNativeFullscreen` 之后。
