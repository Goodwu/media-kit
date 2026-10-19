# 最终目标 OHOS 媒体接入与完整应用 Release 编译完成

2026-10-19（Asia/Seoul）。目标固定为 `Goodwu/PiliPlus:feature/ohos`，方向 B；PiliPlusX 仅供参考。SDK 继续原 `compat/piliplus-zero-change-20261018` 分支，不重复开发或另建替代分支。

## 完成的代码和实际产物

应用 `6cf36e3591db01826c15abe5fd95fde91f2a3a0f` 已将媒体暂缓层替换为真实媒体初始化与入口，在既有 OHOS 生成副本中叠加精确方向 B 接入；保留官方 CPF Flutter/Dart 兼容回移、宿主与依赖适配。主视频、直播、音频、Live Photo、截图/WebP 不再因暂缓后端而被禁用。网络、账户、主题及原平台的 Git 主线文件未被改写。SDK 为 `b4cd48cdd900ece7e2628bd3dcc2b40f6dda3c02`。

原生配方 `Goodwu/libmpv-ohos-build:8bc1bd5840b626bebde2d9f37adcbe96dc15235b` 补上原应用 WebP 导出所需 libwebp/libwebpmux、FFmpeg 两种 WebP 编码器及封装器，并从本轮源码真实重编。配置、生成注册表和最终库特性证据绑定原生 manifest 与 SHA256，最终应用 HAP 的 libmpv 必须与本轮构建逐字节一致。

初次实际应用构建在导出 SDK 时错误拒绝 Darwin 共享源符号链接，未进入应用编译。已按 Git mode 校验链接原文，并限制链接目标在 SDK 导出内部；未删除源码保护断言。所有旧失败与修复保留在提交和归档中。

## 最终验证

| 验证 | 实际结果 |
| --- | --- |
| 完整目标应用 HAP | Goodwu/PiliPlus run 39257755406，job 118077226999：全部步骤和上传成功 |
| SDK 仓库独立完整应用复验 | Goodwu/media-kit run 39254578899，第 2 次尝试，job 118082423341：全部步骤和上传成功 |
| 目标官方 CPF 框架完整 SDK 回归 | run 39257755478：1025 通过、3 跳过、0 失败；完整日志已读取 |
| 应用源码与媒体输入检查 | 54 通过，原有 31 项保留 |
| SDK 原生输入/HAP 检查 | 14 通过 |
| 原生 WebP 特性守卫 | 6 通过，CI 39256184859 成功；实际交叉编译亦成功 |
| 原有 SDK 扩展及 parser/UI | SDK 4 项、应用 UI 2 项通过，parser 通过 |
| 完整 lib 分析 | 0 错误、1 警告、41 提示；既有非致命警告策略未更改 |

两个完整构建的回执均确认同一 app/SDK/native 提交集合，各自重新编译原生库。每次产物单独记录摘要，不作两次二进制完全可复现的承诺。独立复验第 1 次确实因旧链接校验失败，不应将其历史状态改成成功。

唯一分析警告是 `lib/pages/video/controller.dart:79:48` 的 `hide Subtitle` 指向未导出名称。它不阻止编译，保留在日志；不宣称整个工程零警告。Git 输入原有 1639 个文件不变，导出副本中 26 个原路径有真实修改；1466 个 SDK 源条目（含 39 个相对链接）与 15 个已解析媒体包来源均通过核验。

## 交付身份

主构建实际原 `lib/main.dart` 产物为 ARM64 Release 未签名 PiliPlus HAP，80,813,873 字节，版本 2.1.6+1，原 bundleName `com.example.piliplus`。这不是 SDK 示例，也不是旧 media-deferred 版本。

HAP SHA256：`0d3f2aa62a5f84be2922d601c942ae4aa1563aa4977ef84f740e8909fe698d23`。
包内与本轮原生构建 libmpv SHA256：`258c683580b6db227095b82d4329033cd778f70855f0ffa894c9f925bd05307f`。
主构建 HAP 和完整证据已下载，本地再次核对 CRC、七个 ARM64 ELF、libmpv 实际字节及全部六阶段日志摘要。

主构建 evidence artifact 12191415531（ZIP SHA256 `6db56307d0d29727435c691d2102572e9c7a83116c47f25c75091b90db08a6b4`）；HAP artifact 12191310510（ZIP SHA256 `32c48fb19eb4285cd74b70a5d65fa0b08f4bb6d64e22090aa8846db8d7612d74`）。
独立 SDK 复验的证据 artifact 12191459097（ZIP SHA256 `f0ec2d2c3716580de271ee84eea76a9e693cd0483c6800d38266a7ab0e0f3fa1`）亦已完整读取，6 个应用命令和日志摘要均通过。该次 HAP SHA256 由 CI 回执记录为 `d5a64d1bbb5d705236e6b1d8345570de392fee434c370af18b0be4c51e8e7a5e`，其本轮 libmpv 为 `3bf36b707e10be573852c873e2a9c51f79c0ebc5cfcbbfc51d47ac3a58c79cd1`；不与主构建产物混用。交付采用已本地复核的主构建 HAP。

## 开放验收与交接

还未进行签名、设备安装、实际播放、HTTP/EDL、切源、跳转、前后台、字幕、画中画、截图、WebP 导出和 HDR 持续显示验收。当前没有已连接设备或签名材料。OHOS 沿用已有 OHOS 输出，不借用 Android HDR 路由验证结论。编译与主机端测试成功不等于这些项目成功。

目标仓的文档提交 `d4f2e57149126a6860ba1102e8a27c2183dff32f` 仅新增/更新三项 docs；完整构建指南在 `docs/ohos/media-build-guide.md`，来源与产物回执在 `docs/ohos/media-integration-validation.json`。SDK 本次收口也只写 docs。原始完整交接按 blob `8c1f0f74d752fcad9da0fd1ccc5aca20c7045434` 原样归档于 `piliplus-ohos-full-app-handoff-20261019.json`，主交接补齐独立复验成功，不丢失先前工作。

下一轮不要重做已完成接入/构建或重新选择目标；新运行代码变更后才做对应新验证。实体设备验收必须基于真实签名与设备环境，不伪造设备通过。
