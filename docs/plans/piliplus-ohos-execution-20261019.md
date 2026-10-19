# OHOS 编译与方向 B 适配：构建证据及应用移植边界

日期：2026-10-19（Asia/Singapore）。继续 `compat/piliplus-zero-change-20261018`。方向 B 已批准，不回到透明拦截方案，也不重新开发已有 P0/P1/P2b/B 接入。

## 结论

OHOS 专用原生源码构建、方向 B SDK 验证应用的 ARM64 Release 未签名 HAP、真实 OHOS Flutter 框架上的接入契约测试均通过。完整上游 PiliPlus 的 OHOS 依赖预检失败，尚无该应用的 OHOS HAP。两者不能混称“PiliPlus 鸿蒙版构建通过”。设备安装、实际播放、画中画、截图和 HDR 持续显示均未验收。

本次继续工作没有重新提交已有实现；读取了三个新增 OHOS 提交及其实际 Actions 结果，下载所有 OHOS 证据，复核包内库、源码配方及测试，然后写回本文件和主交接。最后的收口提交只涉及文档，不能把它写成重新编译了整个新 HEAD。

## 已有代码及实际执行

- `edaa5e4b`：OHOS 计划，明确 SDK HAP 与完整应用的独立验收范围。
- `978c7f68`：CMake 外部 libmpv 归档与 SHA256 成对输入；缺失、摘要不符或非法路径立即失败，不覆盖用户输入，不悄悄退回历史二进制。增加 HAP 包内库身份检查和 14 项 CMake/归档测试；加入 `media_kit_test/lib/ohos_routed_playback.dart` 及当前应用预检。该入口实际使用 `RoutedVideoPlayback` / `RoutedSimpleVideo`，不是独立播放器实现。
- `7c9ff573`：在真正的 OHOS Flutter 框架上执行方向 B 播放控制、请求代次和视图测试，不使用普通 Flutter 假扮鸿蒙框架。

### 构建及测试结果

| 检查 | 源码提交 / Actions | 实际结论 |
| --- | --- | --- |
| OHOS 原生源码与 SDK HAP | SDK `978c7f6888c1ca7cd7a94bee4f78ccfad92aa469`；run `39221456265`，job `117957472301` | 原生编译、分析、HAP 构建、包内身份检查及上传全部成功 |
| 完整 PiliPlus 依赖预检 | 同一 run，job `117957473483`；应用 `9b172128beb034e6ba4f9d545c43e3147c0a61ca` | 失败，pub 未通过；没有运行应用 HAP 编译 |
| OHOS Flutter 方向 B 契约 | SDK `7c9ff573f6a2b7693dba6ebd969d112fa211a790`；run `39222397643`，job `117960541514` | 11 通过、0 跳过、0 失败；仅主机端契约，不是真机 |
| 原生输入及 HAP 检查工具 | 已构建 SDK 源快照本地复跑 | 14 通过，退出码 0 |

`39221456265` 整个工作流结论仍为 failure，因为应用预检失败；不得将成功的 SDK 子任务冒充整个工作流或完整应用成功。保留此失败，不跳过或弱化预检。

### 实际工具链与源码

- Flutter OHOS：`3.44.9+ohos`，Dart `3.12.2`；framework `2ece1aaeb4bb386c66708e9992e03aafb8dc73da`，engine `5a2a6a42cce67f965cf540fcecf616faca624aa1`。
- 构建工具仓 `Goodwu/libmpv-ohos-build` main：`102510e8f6a3aa21d9df19fdbc3bc7c7f9de0d41`。
- mpv `mirror/feat-ohos-0.41.0`：`6edeee00a07b9b76f197aa71eee3d029fb090de4`。
- FFmpeg `mirror/feat-ohos-n8.0`：`7dddf74de0346fee1f17bd49563efc5ab9deaf98`。
- libplacebo `mirror/v7.360.1`：`cee9b076f2c63104ccfd497fa79c39a867293ec4`。
- OHOS SDK CLI `26.0.0.621`，配方记录 API `6.0-Release`。

上述四个维护仓/分支及 Flutter patch 分支 HEAD 均再次在线读取，与构建 manifest 一致；配方中 10 个补丁的摘要也逐一校验。它们是 OHOS 专用分支和配方，不据此声称已包含其他平台分支的所有补丁，也不声称重新编译了 Flutter engine。

## 产物与复核

输出文件是 SDK 验证应用 `entry-default-unsigned.hap`，59,827,807 字节；不是 PiliPlus，未签名，需要正式签名后才进行设备安装测试。

- HAP SHA256：`040dd2b7315932945906839b964d888983bf2db75d11697198b2807b1221f11c`。
- libmpv 归档 SHA256：`dc14877df6af56d5b516cc934d92e447baf97bf812fe894a4cbfc3a95104345a`。
- 本轮 libmpv.so 及 HAP 内 `libs/arm64-v8a/libmpv.so` SHA256 均为 `f3967033ee2f703e37496665a1ba30a5f9ba606f3c51a6ecbab4c69afaa5be9c`，实际逐字节一致。
- 包内同时存在 ARM64 ELF 的 `libmediakit_ohos_hdr.so` 和 `libmediakit_ohos_sw.so`。

本地 readelf 静态补充检查：扫描到的 26 个运行代码引用的 libmpv 导出、3 个 HDR 桥导出、10 个软件渲染桥导出均存在。完整历史生成绑定还含 4 个本库不导出的入口：`mpv_detach_destroy`、`mpv_get_sub_api`、`mpv_resume`、`mpv_suspend`；非生成 SDK Dart 源码未引用它们，且生成查找是惰性的。保留完整清单，不把此检查描述为任意应用 FFI 或所有 ABI 已验证。设备 loader、调用签名及运行行为仍需实际执行。

原始证据有一处格式问题：bootstrap 输出写入 `flutter-version.json` 时带有下载日志，`dart-version.txt` 为空。本次保留原文件，并从唯一的实际 JSON 对象提取规范化回执；它与应用预检独立读取的 framework/Dart 版本一致，没有修改或伪装版本。后续整理 bootstrap 输出即可，此问题没有被用于降低应用 SDK 要求。

下载并读取的 artifact：

| artifact | SHA256 |
| --- | --- |
| `12172483324` OHOS SDK/原生源码/HAP 证据 | `e0842a3253f981623c663aaf5650632ccc688d69583aae0f60119b6e3c9dbcc0` |
| `12172111467` 完整应用预检 | `46ff80e17a7938a50c453049909ceb3fc93a7883346f974e21e7505533491d86` |
| `12172222360` OHOS Flutter 11 项契约 | `423f90a4169490b522aa70001ee9f67e87fad70698a2215fff440326fd583e65` |

## 完整应用的具体阻塞与暂停点

实际解析错误：`The current Dart SDK version is 3.12.2. Because PiliPlus requires SDK version >=3.13.0, version solving failed.` 构建时的上游应用没有 OHOS 宿主工程。不得仅把 pubspec 降到 3.12、修改 Flutter 版本标识或删除插件来制造通过。

读取结束时上游 main 已到 `7312ca186e79c3898d35fbc33b1b8e90856a3cb2`，相对预检提交新增两次提交。pubspec 仍是应用 `2.1.6+1`、Dart `>=3.13.0`、Flutter `3.47.7`。比较仅涉及 `lib/pages/live_room/view.dart`、`lib/plugin/pl_player/controller.dart`、`lib/utils/video_utils.dart`，没有新增 OHOS 宿主。前两个文件属于 B 补丁的严格前像保护范围，下一次针对最新应用执行前必须审查并刷新补丁；不能复用旧前像，也不能把 9b172128 的结果标为 7312ca18 的新执行结果。

这是框架/引擎、应用宿主及插件生态的移植范围，不再只是七个播放器接入文件。遵照用户“遇到特别困难处先讨论”的要求，完整应用的大范围 OHOS 移植暂停；已通过的 SDK/原生库工作保留。

可讨论的范围：保留当前上游 PiliPlus，另行处理匹配的 OHOS Flutter/Dart、宿主、插件审计和 B 补丁刷新；或者以已有 `Goodwu/PiliPlusX` 的 `ohos` 分支作为鸿蒙应用基线，再接入当前 SDK。后者的 live pubspec 为 1.1.5，Dart >=3.9.0 <4.0.0、Flutter >=3.35.7，已有 OHOS 专用插件依赖，但它是较旧的不同应用基线，不能不经批准替代当前 PiliPlus。两种方案均不降低真实原生产物、功能和设备验收要求。

## 交接

完整 B 历史交接按原始 blob `d6db6262ae35c957102d0f08f24b46acc0f13d99` 原样保存在 `piliplus-direction-b-handoff-before-ohos-20261019.json`。当前主交接引用它并补充 OHOS 实际结果。不要重复构建基础适配；不要把 OHOS 普通输出写成 Android 路由/HDR 等价验证。设备/功能/HDR 验收和完整应用基线决策仍开放。
