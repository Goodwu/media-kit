# PiliPlus 零修改适配：实施交接 2026-10-19 第二轮（pull 9c772a41 后重建重验）

主计划：`docs/plans/piliplus-zero-change-20261018.md`（§11 交接记录）。本轮=用户指令「pull 并重新验证」：对齐远端 80 提交（direction B 集成等）后重建三包并重跑 marble 实机回归。前一轮（基线 5e34eb74，本地提交 1cca105c）按用户指令「本地测试结论没有用了，废弃掉吧」已从分支丢弃；其记录副本存 `~/src/media-kit-build/evidence/compat-marble-20261019/superseded-local-handoff-20261019.md`（仓外留档，提交在 reflog 可达），该轮结论全部作废。

## 任务标识

- 唯一实施分支：`compat/piliplus-zero-change-20261018`
- 本轮基线 HEAD：`9c772a41`（origin/compat/piliplus-zero-change-20261018；含 direction B SDK 集成 6025d405/57a5e991/d42f9ed5、应用补丁配方 40b026dd/ab2e5402、tool/piliplus_compat P0 工具与 OHOS 工作线等 80 提交；工作区干净）
- 上游 upstream 记录：0597c8318（routing）；本轮构建输入=本仓 tracked 源码 + `~/src/mpv` ninja 增量（测试版默认构建链，无钉定下载 JAR）

## 构建记录（tool/build-android-test.sh，三包全 exit 0）

| tag | 素材（设备路径，md5 轮前核验同前） | APK SHA-256 |
| --- | --- | --- |
| compat2-marble-20261019-p5 | /data/local/tmp/media-kit-p5-mystery-box.mp4 | d1acc62dd9c2a0cd…70196 |
| compat2-marble-20261019-p84 | /data/local/tmp/media-kit-p84-full.mp4 | eaa74b1248821848…eabbe |
| compat2-marble-20261019-hdr10 | /data/local/tmp/media-kit-hdr10-full.mp4 | 534031810f998938…5287f |

- **构建前置修复（环境项，非源码改动）**：`media_kit_hdr_lab/.dart_tool/package_config.json` 残留 media_kit_video `languageVersion=2.17`（旧解析产物），新代码 `routed_video_playback.dart` 使用 records/patterns 编译失败；`flutter pub get` 重解析后=3.1，pubspec.lock 零变化、树保持干净。后续在新 HEAD 构建前若遇同类报错先重跑 pub get。
- JAR 溯源：`~/src/media-kit-build/lg-api24/lg-api24-realtime-gpu-mks-compat2-marble-20261019-{p5,p84,hdr10}-build/`（libmpv stripped 8de38a2d…，三包同 native）

## 版本身份证据链（用户要求「再确认一下安装运行的是新版本」）

1. 新旧 APK 哈希不同（compat-marble-20261019-p5=7fe9cd73… vs compat2-…-p5=d1acc62d…），构建时间线 23:48:37–23:49:23 早于轮次。
2. 决定性证据：`adb install -r -d compat2-…-p84-release.apk` 后回读装机 `sha256sum` = **eaa74b12…（与新建 APK 逐字节一致）**（lastUpdateTime 2026-10-19 23:59:45）；adb install 不改写字节，故各轮「install Success→am start」运行的都是 compat2 包。
3. AOT 字符串指纹不可用（direction B 新类未被 lab 引用被树裁、define 门控字符串被常量折叠）——哈希回读为权威判据。

## marble 实机轮次（dede0cd2，脚本同前轮 round-marble.sh）

| 轮 | 结果 | 关键证据 |
| --- | --- | --- |
| compat2-p5 | **PASS（首会话）** | gen=1 `verified=true hwdecCurrent=mediacodec`；EOS `AUTO_COMPLETED completed=true`（time-pos 98.9s）；dispose ✓；render_failures=0；FATAL/ANR=0 |
| compat2-p84 | **PASS（首会话）** | gen=1 `verified=true`（DV P8.4 HLG）；time-pos 5.9→267.9 连续；frame-drop 22 样本全 0；DisplayPowerController `manual [ hdr ]` 链；dispose ✓；0/0 |
| compat2-hdr10 | **PASS（首会话）** | gen=1 `verified=true origin=decoder`（baseLayerDirect→pq/mediacodec_embed）；time-pos 6.0→268.0 连续；frame-drop 22 样本全 0；SF t45 实锤 `BT2020_ITU_PQ (298188800) hdr metadata` 层；`manual [ hdr ]` 进入/退出原文链；dispose ✓；0/0 |

**与上一轮（旧基线，已作废）的对照观察**：hdr10 首开复核门 flake（HdrDecoderReviewFailure）在新 HEAD 未复现（单轮单样本，不作「已修复」断言，仍归 DV004 开放线跟踪）。

- 轮次产物：`~/src/media-kit-build/evidence/compat-marble-20261019/rounds-v2/`（三份 device.log、SF dump、截图、round-*.out）；APK 在 `apks-v2/`
- 设备还原核验：lab 包装回轮前备份（4244fce4… 哈希一致）、自动亮度=1、mWakefulness=Asleep、PiliPlusX 与素材零触碰

## 边界与未运行项

- 本轮通过=lab 样片场景（p5/p84/hdr10）在 marble 的解码/路由/显示/持续播放验收；**不是** PiliPlus 应用编译（T1）、不是 direction B 应用侧 7 文件补丁的设备验收（该补丁打在隔离应用副本，本仓不可见）、不是 T2—T4。
- direction B 状态沿用远端交接 `docs/plans/piliplus-direction-b-handoff-before-ohos-20261019.json`：DIRECTION_B_FIRST_INTEGRATION_BATCH_AND_DEBUG_BUILDS_PASSED、NATIVE_DEVICE_GATES_OPEN；本轮为 SDK 侧新 HEAD 的设备回归证据。
- 主计划 P1—P5 实施状态以远端 80 提交与各 handoff JSON 为准；本文件不重复记账。

## 下一项

direction B 应用侧实机验收（PiliPlus 隔离副本装机）与 T2—T4 分层，按主计划与 direction-b 交接推进；后续轮先读交接、核对远端 HEAD。
