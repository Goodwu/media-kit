# 方向 B 实施结果：接入及五平台 Debug 构建通过

日期：2026-10-19，Asia/Singapore。方向 B 已获用户明确批准；继续 `compat/piliplus-zero-change-20261018`，不重新建立分支、不重新开发 P0/P1/P2b，也不再回到 A/B 待决状态。

## 本批已落地的代码

`RoutedVideoPlayback` 显式复用现有 Android `HdrVideoSession`，`RoutedSimpleVideo` 跟随控制器通知。普通 Player 不被全局拦截，未增加通用透明输出代理。非 Android 保留普通 VideoController 输出，包括 Darwin 的现有纹理/PiP 接口，不因此宣称完整 HDR。

打开和内部重建先保持暂停，验证后才应用最新的播放/暂停/跳转意图。请求代次防止旧打开完成后重新播放；新增回归覆盖“新请求等待上一条 seek 排空期间，旧会话的迟到 verified 报告不能提前放行新请求”。视频切纯音频先释放视频所有者；释放失败保留重试，不在仍被输出占用时销毁底层 Player。

应用的原封面和手动播放层不变，但已有接入对象必须先挂载视频，再等待路由验证；关闭自动播放且开启预初始化时，也能在封面后挂载输出而不启播。字幕不缓存被替换的控制器，保留原字幕配置与拖动接口。初始化失败重置共享 Future，释放尚未发布的资源，保留失败的所有者供后续重试。主视频、直播、画廊和已识别的直接播放调用点已进入这套显式接入。

## 应用修改与交付

维护在 SDK 仓内的 `tool/piliplus_compat/direction_b/player-integration.patch` 及 `manifest.json`，只在隔离构建副本中应用，没有写入上游 PiliPlus 仓库。

最终补丁 SHA256：`2109c3c44c8f93febf04636d557f863d6c05b15fa5a1287ed3f86f2a8474443b`。

核对并构建的最新原始 PiliPlus：`2eaeeb731462dad92246809d5b5ac716c671736b`；结束时重新读取 main，仍是同一提交。routing 分支仍是 `0597c8318ccf50f0824249ceeab310632efb84ab`，已在实施分支历史内。

| 文件 | 接入改动 |
| --- | --- |
| lib/plugin/pl_player/controller.dart | 初始化、打开、播放/暂停/跳转、刷新、错误和释放 |
| lib/plugin/pl_player/view/view.dart | 视频与字幕跟随控制器、后台播放控制 |
| lib/pages/video/view.dart | 输出提前挂载，保留原封面和手动播放层 |
| lib/pages/live_room/view.dart | 直播输出提前挂载 |
| lib/common/widgets/image_viewer/gallery_viewer.dart | 画廊播放、输出与释放 |
| lib/pages/video/introduction/local/controller.dart | 原有循环播放调用通过接入对象执行 |
| lib/pages/video/post_panel/view.dart | 原有播放调用通过播放器控制器执行 |

五个平台的下载回执均验证为七个修改文件、其他 1633 个原始文件不变；选源、网络、账户和原生宿主没有额外改动。实际应用补丁与输入补丁摘要完全一致；原始输入 checkout 保持不变。构建派生提交仅用于追踪隔离副本，不是上游应用提交。

## 实际测试与构建

| 验证 | 实际提交 | GitHub Actions | 结果 |
| --- | --- | --- | --- |
| 完整 media_kit_video 回归 | d42f9ed5 | 39201319384 | 1025 通过、3 跳过、0 失败 |
| 纯 Dart 截图测试、受限导入分析 | d42f9ed5 | 39201319384 | 通过 |
| macOS 视图与方向 B 接入测试 | fee433f1 | 39203008059 | 36 通过、0 失败 |
| 构建工具 | ab2e5402 | 39202905090 | CI 通过；本地完整测试 123 通过 |
| 原始零补丁 T1 五平台 Debug | ab2e5402 | 39202905113 | 五个平台、上传和汇总全部通过 |
| 实际方向 B T1B 五平台 Debug | ab2e5402 | 39202905110 | 五个平台、上传和汇总全部通过 |

T1B 平台为 Android ARM64 Debug APK、iOS Debug --no-codesign、macOS Debug、Windows x64 Debug、Linux x64 Debug。五个平台各自的分析、编译、源码及解析路径核验都通过。已下载并读取全部五份 T1B 证据，逐一比对上游应用/SDK/派生提交、最终补丁摘要、前后像、源码守卫和实际构建日志。具体 job、artifact ID 和 ZIP 摘要已写入主交接 JSON。

SDK 的实际运行及测试代码最后修改在 `d42f9ed5cd82380e24c88be8141c1a6510fd1d34`。比较到 `a2a81360`，没有 media_kit/media_kit_video 运行或测试代码改动；后续是应用补丁、构建工具、macOS 工作流和文档。因此全量 SDK 结果明确对应 d42，而包含最终应用补丁和 Windows 工具修复的五平台构建明确对应 `ab2e54022c53f0aff5c3932c56ef5c72d8f163f8`。最后的交接提交只写文档，不宣称重新测试了整个 HEAD。

## 本批遇到并处理的问题

首轮新测试字段被 Dart 推导成只读接口类型，两份新测试文件无法加载；补上明确的假对象字段类型，保留所有断言。随后测试恢复通过。

Windows 最初在编译前失败：检出的补丁被 autocrlf 转成 CRLF，导致摘要不一致。改为读取 Git 对象中的精确 manifest/patch 字节，写入证据目录后严格应用，不放宽摘要和前后像校验；增加 CRLF 检出及提交内容被篡改的拒绝测试。最终 Windows T1B 已通过。

另在代码审查中修复了预初始化挂载等待、迟到会话报告、旧字幕控制器、初始化失败资源回收和重试边界。旧失败及修复提交仍保留在历史，不能将失败轮次记成成功。

## 尚未完成的范围

本批是方向 B 的首批接入实现和 Debug 编译验收，不是整个 HDR 交付完成。

1. 仍需对无应用 hint 的真实片源准入补齐完整覆盖和实际缺口；已有后端读取实际轨道 codec、DV profile/compatibility/EL，不应再从零重复实现分类器。
2. 仍需完整应用功能、其他切源/取消/重建与初始化失败场景、画中画和截图的运行验证。
3. 尚未按要求完成最新 mpv/FFmpeg 等全部原生源码的各平台重编、ABI 和最终包内产物身份闭环。本批编译仍使用现有原生依赖；系统 libmpv 回归只是接口行为证据。
4. Release、iOS 签名安装、真实设备及 HDR 持续输出/显示验收未完成，不能把本批 Debug 包标为上线版本。

构建用法见 `piliplus-direction-b-build-guide-20261019.md`；后续继续读取主交接 JSON。若新的实现成本明显超过有限接入范围，列具体方案与取舍再与用户讨论，不默默扩大或降低需求。

## 历史索引

首批源快照：Actions 39198005234，artifact12161749495，ZIP SHA256 d4a9607ae4a2c1d6468288112135c13f68d9a97e550bc12814d11b321a792c97。原始首批执行记录保留在提交 d2a40e0619a97f896188ce54e7a1a2dddd1ee137；其中补丁8be7561c版本已被最终2109c3c4版本替代。B 前完整验收历史见43f698958b7acdb4d0c1012d5afa17b8d829dc34的主交接文件。本批完整提交和失败来源见当前主交接 JSON。
