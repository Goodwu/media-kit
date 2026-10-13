# 最新源码实机回归轮（2026-10-14，routing/MK-ROUTING-20261011）

## Current State（2026-10-14 收口）

**回归结论：目标下限达成——DV P5 / DV P8.4 / HDR10 三样片实机解码测试全部完成（在设备验证路由、零渲染失败/零 fatal、与 10-13 基线一致）；1 项契约预期新行为（LG P8.4 硬失败）定性闭合；marble（dede0cd2）本轮不可达未测，3 轮待设备可见后补。**

- 构建源：routing/MK-ROUTING-20261011 @ **ab1c7ca9**（e40cef8f 无隐式 SDR/去预算 + 40 项测试契约迁移，本地未推送提交）；`tool/build-android-test.sh` 三包（tag regression-latest-20261014-{p5,p84,hdr10}）。native 层与 10-13 基线逐字节一致（stripped lib 槽位 5f8fc04c、libmpv 69d4afff、FFmpeg 六库 archiveSha256 全同）；`sourceManifestSha256` 0133917d→31db7c3f（允许差异，变化先于本轮、具体输入未查）。APK（42701635 字节）：p5 `f6f055fe…`、p84 `2ff61f23…`、hdr10 `ac69ec56…`。
- **LYA-AL00**：3/3 绿且与基线逐格一致——p5 metadataReshape→pq/gpu-next platformView（全片 EOS time-pos 98.79、dispose ✓）、p84 baseLayerDirect→hlg/mediacodec_embed（257s 播放、SF 实锤 BT2020/ITU_HLG 层）、hdr10 baseLayerDirect→pq/mediacodec_embed（257s、SF 实锤 BT2020/SMPTE2084 层）；全部 verified/playable、render_failures=0、fatal=0。
- **LG H870DS**：p5 nativeDolbyVision verified 全片 EOS（post-EOS BACK 不 dispose=已知问题②复现）；hdr10 baseLayerDirect→pq verified 254s 连续推进零丢帧、dispose ✓；**p84 硬失败（新行为，见下）**。
- **Mi Note 3 (jason)**：p5 toneMapSdr→sdr/gpu-next texture verified 全片 EOS——display 报告为确定 SDR-only 空集（SF `hdr10=false hlg=false dv=false`），走新契约的显式 SDR 豁免分支（结局 A）；render_failures=1 为 EOS 尾帧已知签名（+200ms 于 completed）；VO 丢帧 4972≈84%=SD660 在案限制。**新契约"SDR 输出仅 SDR-only display"的豁免分支在实机验证有效。**
- **LG P8.4 硬失败定性（契约预期，非回归）**：lgh5-p84 prediction 选 baseLayerConvert（=基线格）后 `HdrDataSpaceApplyException(pq, reason: dataSpaceApplyFailed)` 无兜底即中止。回读上轮 lgh4-p84 日志实锤：同点失败当时走 `HdrDegradedEvent(dataSpaceApplyFailed, from: baseLayerConvert, to: toneMapSdr)`，**实际播放路由= toneMapSdr→output: sdr**（HDR-capable 显示、baseLayerDirect 本就 displayLacksTransfer）——上轮"通过"完全由本次废除的隐式 SDR 兜底承载（当时色彩旗标与此吻合）。本轮同构建同机 baseLayerDirect/pq（hdr10 轮）正常播放，证明失败仅限 baseLayerConvert 的 PQ dataspace 落盘路径。**开放项：LG P8.4 在现候选模型中无可达 HDR 输出路径（HLG 直出=显示缺报；PQ convert=dataSpaceApplyFailed；10-09 YUV HWC 配方与现 baseLayerConvert 路径不同构）——归 v4 A 包候选表/C2-C4 语义工作项，不以恢复 SDR 兜底"修复"。**
- marble：用户报告在线但本机 adb 全程不可见（USB 列表 + kill-server 后轮询 + mDNS 均无，检测留痕在案），marble6-{p5,p84,hdr10} 三轮未跑（nativeDV p84 boolean/timed、hdr10 已知 flake 复验区）。待设备对本机可见后按同协议重发。
- 已知 flake（HdrDecoderReviewFailure）本轮未复现；lya5-p5 首跑 FOCUS_FAILED 为 keyguard 竞态环境操作（证据保留 *-f1，加固 swipe 后复跑通过）。
- 工具缺陷备忘：`tool/matrix-round.sh:52` 的 `ANDROID_HDR_OPEN sample=` grep 已过时（现行日志 `ANDROID_HDR_OPEN path=`，源码 01.single_player_single_video.dart:3486），轮次按副本 path= 判定；仓库脚本未改。
- 设备还原全部核验：LG/jason 装回还原包逐字节一致、LYA PACKAGE_ABSENT、三台 rotation/亮度原值、全部熄屏。

证据目录 `~/src/media-kit-build/evidence/regression-latest-20261014/`（apks/ 构建三包+日志+native-candidate、precheck.log、round-{lya,lgh,jason}.sh 副本、各轮 round-*.out/device.log/截图/SF dump、lgh5-p84 失败链证据、final-restore-check.log）。

## 构建与预检

- 三包构建 exit 0（3m0s/1m43s/1m37s）；JAR jarSha256 运行间不可位复现（provenance 内嵌，与上轮同性质）。
- 素材 md5 设备侧核验：p5 `3b6b8a20…`（三台）、p84 `49841d19…`（LYA/LG；jason 无此文件按计划跳过）、hdr10 `7ecb1894…`（三台）。
- LG/jason 现装包 sha256 与上轮还原包逐字节一致后才覆盖；LYA 预期 PACKAGE_ABSENT。

## 轮次记录

| 轮 | 路由（verified/playable） | EOS | dispose | fail/fatal | 备注 |
| --- | --- | --- | --- | --- | --- |
| lya5-p5 | metadataReshape→pq/gpu-next platformView | ✓ 98.79s | ✓ | 0/0 | frame-drop 35（上轮 8，非验收项） |
| lya5-p84 | baseLayerDirect→hlg/mediacodec_embed | n/a 257s | ✓ | 0/0 | SF: BT2020 STD-B67/ITU_HLG |
| lya5-hdr10 | baseLayerDirect→pq/mediacodec_embed | n/a 257s | ✓ | 0/0 | SF: BT2020 SMPTE 2084/ITU_PQ |
| lgh5-p5 | nativeDolbyVision→dolbyVision/mediacodec_embed timed | ✓ 98.92s | ✗ 已知② | 0/0 | frame-drop 9 |
| lgh5-p84 | baseLayerConvert 选择后 OPEN 中止 | — | — | 0/0 | **契约预期硬失败**（见 Current State） |
| lgh5-hdr10 | baseLayerDirect→pq/mediacodec_embed | n/a 253.85s | ✓ | 0/0 | 补轮，区分 p84 特有 |
| jason4-p5 | toneMapSdr→sdr/gpu-next texture | ✓ 98.94s | ✓ | 1/0 | SDR-only display 豁免分支实测有效 |

marble6-{p5,p84,hdr10}：未执行（设备不可达，见 Current State）。

## 待办

- [ ] marble 可见后补 marble6 三轮（协议同本轮，restore 用轮前 pull 的现装包）。
- [ ] LG P8.4 无 HDR 输出路径——并入 v4 A 包候选表设计（不恢复 SDR 兜底）。
- [ ] `tool/matrix-round.sh` OPEN 判定 grep 过时（path= 格式），下次触碰 tool 时一并修。
- [ ] ab1c7ca9 推送仍待用户逐次请示批准；推送后 CI 新头复跑。
