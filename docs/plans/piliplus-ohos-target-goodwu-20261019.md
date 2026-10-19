# OHOS 最终应用目标确认与接入方案修订

日期：2026-10-19（Asia/Singapore）。本文件取代此前 OHOS 应用基线待决项；不推翻已批准的方向 B，不重做已完成的接口兼容、请求隔离或 SDK 原生库工作。

## 1. 用户已经确定的目标

最终 OHOS 应用：`Goodwu/PiliPlus` 的 `feature/ohos` 分支。

`Goodwu/PiliPlusX` 不作为构建、交付或失败回退基线；只可参考具体 OHOS 实现。不得再要求用户在新版 PiliPlus 和 PiliPlusX 之间选择。

SDK 继续在 `Goodwu/media-kit:compat/piliplus-zero-change-20261018` 上推进。应用接入以目标 `feature/ohos` 已有的源码保护、构建副本和适配工具为基础，不覆盖主线原文件，也不另起重复实现。

## 2. 本次实际读取到的目标分支

目标 HEAD：`dad64686e82bba879ccd40b60d6bb43a37422e11`。这是本次读取快照，不是后续测试永久钉定值；每轮重新解析明确目标分支的最新 HEAD 并记录实际输入。

已读取：根目录树、`pubspec.yaml`、`docs/ohos/README.md`、`docs/ohos/validation.json`、`tool/ohos/README.md`、`tool/ohos/build_profile.py` 和 `tool/ohos/build.py`。

### 已有工作应直接复用

目标已有 `ohos/` 宿主、系统插件与应用兼容准备工具。Git 中保留上游应用文件；在独立导出副本中做 OHOS 平台、旧 Dart API、依赖和 SDK 补丁适配，并记录源文件前后摘要。

根 `pubspec.yaml` 仍为应用 `2.1.6+1`、Dart `>=3.13.0`、Flutter `3.47.7`。目标准备流程在 OHOS 副本中使用 Dart `>=3.12.0 <4.0.0` 和 Flutter `>=3.44.0 <3.45.0`，配套实际源码回移及依赖接口适配。这不是只改版本字符串；不能跳过准备流程后拿根 pub 的失败判定目标无法构建。

目标 Flutter 配方为官方 `CPF-Flutter/flutter_flutter:oh-3.44.9-dev`，记录提交 `3ffe70c6280cc6ddf613bffa59dd70611f238f7e`，host engine `5a2a6a42cce67f965cf540fcecf616faca624aa1`，OHOS target engine `24497d6833225b0445953e1dd05dc6538c16a8dd`。继续核验目标自带的 SDK 配方；不能把此前 SDK 验证应用所用的 Goodwu Flutter patch 分支自动替换进来。已有锁用于来源复核；如需要更新，先审查实际差异，不能伪装版本或借用旧二进制作为新源码验证。

`docs/ohos/validation.json` 记录完整 `lib/main.dart` 的未签名构建，状态为 `built-unsigned-media-deferred`。记录的源码提交为 `fc0ed189d1194974898b33e1d54cef6f8231feef`；目标 README 另记录等价 Git tree 的已发布提交。此处仅复核仓内记录，尚未重新执行该构建，更不代表当前 media-kit 已接入。

### 应撤回的旧结论

此前“上游应用没有 OHOS 宿主”和直接用 Dart 3.12 解析未适配根 pub 的失败，只针对 `bggRGjQaUbCoE/PiliPlus:main` 的旧预检，不能套用到当前最终目标。

原失败日志完整保留，但不再构成当前目标的基线决策阻塞。PiliPlusX 备选方案已被用户排除。

## 3. 真正需要接通的位置

目标 `build_profile.configure()` 当前执行 `defer_media()`：跳过 `MediaKit.ensureInitialized()` 和原生版本读取，拒绝主播放器和音频初始化/播放，Live Photo 暂退为静图，阻止 WebP；直播保留独立聊天及页面生命周期逻辑。

应以真实媒体接入替换这些占位限制，不是仅增加一个 SDK 依赖，不是保留播放拒绝逻辑却把构建状态改名为成功。

| 区域 | 实施要求 |
| --- | --- |
| `tool/ohos/build_profile.py` | 以已审查的媒体配置替代暂缓配置；恢复初始化、版本读取及实际入口。保留其中仍有用的直播聊天、路由和生命周期处理，避免重复启动聊天或断开聊天流程。 |
| 应用播放器、视频视图、画廊 | 按方向 B 复用 `RoutedVideoPlayback` / `RoutedSimpleVideo`；保留封面和手动播放意图、输出挂载、字幕、切源取消及所有者优先释放。与目标已有平台补丁合并审查，不直接套用另一应用版本的七文件补丁。 |
| 音频、Live Photo、截图/WebP | 解除对应暂缓入口后分别运行验证；纯音频不应被迫初始化视频输出。未实现的具体路径明确报错，不把静态图或空操作算播放成功。 |
| 依赖准备 | 将实际解析的 media-kit 包闭包接到本轮 SDK；保留所有无关 OHOS 插件及其接口补丁，拒绝漏出的旧播放器 fork。 |
| OHOS 原生库 | 复用现有归档路径/SHA256 成对输入和包内校验；使用该轮维护源码构建结果，记录配方、补丁、ABI 和最终 HAP 内库摘要。 |
| `tool/ohos/build.py` 与工作流 | 保留既有 SDK 检查、依赖检查、parser/UI 测试、完整 lib 分析和 `lib/main.dart` HAP 构建；增加媒体入口与库身份验收，状态不能继续是 media-deferred。 |

OHOS 原生宿主和插件适配已经存在，不整体重做。仅在真实接口差异要求时增补最小改动；显著超出接入范围的问题提出具体取舍，再讨论，不重新提出被排除的应用基线。

## 4. 构建入口和 CI 修订原则

完整应用构建必须读取 `Goodwu/PiliPlus:feature/ohos` 的实际提交，并使用该提交自带的 `prepare_sdk.py`、`ohos.py prepare-build`、依赖适配和 `build.py`；原平台路径继续隔离。

不能只是把旧工作流 checkout 的仓库名替换，然后继续执行针对原始上游的 `application_preflight.py`：那会跳过目标已有的 OHOS 源码与依赖转换，产生错误阻塞或错误证据。

目标已准备副本与方向 B 的播放器补丁存在重叠路径。必须记录各层前后像、应用顺序和最终差异；不能使用 `--reject`、模糊锚点、强制旧 hash 或吞掉冲突。新应用 HEAD 变化时重新审查实际受影响路径，不自动改成旧提交来求通过。

现有 SDK-only HAP 检查保留为独立 SDK 检查，原平台 T1/T1B 也保留各自身份。最终目标应用的构建必须明确记录 repository、branch、resolved SHA、SDK SHA、配方与 native hashes，不得再把上游 main 或 PiliPlusX 的结果作为它的交付依据。

## 5. 验收与本轮边界

验收依次为：源码与补丁保护、依赖解析及实际包路径、完整应用分析/测试、包含当前原生库的目标应用 HAP、签名安装、点播/直播/音频/画廊及切源生命周期、字幕/PiP/截图等功能与设备验证。OHOS 普通输出不得写成 Android-equivalent HDR 已验证。

本轮只完成最终目标确认、仓库源码复核与方案/交接修订；未修改应用或播放器运行代码，未修改 CI，未重跑目标 HAP。下一执行点是 target-specific 媒体配置及接入补丁，而不是再次请求应用基线确认。

上一份主交接的完整内容原样归档为 `piliplus-ohos-handoff-before-target-correction-20261019.json`（Git blob `5ee4eaf529bdf19045ea05ce4aef3724607fe45e`）。更早的方向 B 交接继续保留，不丢弃测试失败、修复与来源历史。
