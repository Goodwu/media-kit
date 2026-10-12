# 双设备最新代码回归轮（2026-10-13，routing/MK-ROUTING-20261011）

## Current State（2026-10-13 收口）

**回归结论：通过（4/5 台设备；1 项新发现间歇性缺陷、2 条人工目视旗标、1 台 blocked 待用户解锁）。** 分支 routing/MK-ROUTING-20261011 @ 5834ce5b + mpv c11426b67a + FFmpeg d4bb79394b 世代（native 层与 10-10 基线逐字节一致，JAR lib 槽位 5f8fc04c）。测试链产四 APK（p5/p84/hdr10/sdr）。设备结果：

- **LYA-AL00**：3/3 绿。路由与 10-10 基线逐格一致（p5 reshape→PQ、p84 HLG 直出、hdr10 baseLayerDirect），全片轮 EOS + dispose 正常，截图真实内容。
- **marble**：p5/p84 绿（nativeDV 默认直达保持，timed/boolean）；hdr10 首跑被**新解码履行复核门竞态**拒绝（HdrDecoderReviewFailure，同路由复跑 marble5 完整通过：time-pos 5.9→87.9 推进、零丢帧、dispose 正常）——间歇性 flake（同路由今日 1/4），待修非确定性回归。p5 post-EOS BACK dispose 缺失为已知问题②。
- **LG H870DS**：3/3 对照 LG 线基线通过。P5 nativeDV verified（=10-09 收口验收路由；最新源码 JAR 在 API24 正常加载）、全片 EOS、丢帧 3。p84=baseLayerConvert+mediacodec-copy（=10-09 YUV HWC 机制，SF 实锤 HWC 合成）+`degrade=dataSpaceApplyFailed`；hdr10=baseLayerDirect（默认策略上探，与 LG 旧严格门下的 convert 不同）。**旗标：p84/hdr10 色彩未经人验，建议 30s 目视复核。**
- **Mi Note 3 (jason)**：2/2 对照 09-30 观察基线通过（P5 toneMapSdr/verified + 84% VO 丢帧=文档在案 SD660 设备限制精确复现；SDR sdrDirect/verified 零丢帧）。
- **Redmi Note 5A (ugg)**：blocked——安全锁屏（`inputRestricted=true`），自动化不可越过，sdr 轮未跑；设备已还原原状，素材就位，**待用户手动解锁后补 1 轮 90s SDR**。

**新发现/修正**：① 新解码履行复核门竞态（见 marble4-hdr10，待修：hdr_decoder_review.dart "Observed decoder changed" 在初始化期误触发）；② 已知问题 post-EOS BACK 不 dispose 本轮在 LG(API24)/jason(API35) 复现——原"HyperOS API35 × post-EOS"归因不成立，修正为设备相关（复现 marble/jason/LG，LYA 通过），共性因子待查；③ `tool/build-android-test.sh` 定稿缺陷修复（flutter 步骤 melos 根必失败，53ede203 引入）；④ LG ROM setprop 32 字符上限——轮次脚本调试属性需 `|| true` 兜底；⑤ tap 协议修正：app 横屏渲染时输入空间为横屏，tap=(输入逻辑短边/2, 短边/2)，轮前旋转设置钉定 1/1、轮后还原（首组六轮因竖屏中心坐标全数作废，根因入 tap-root-cause.md）。

证据目录 `~/src/media-kit-build/evidence/regression-two-device-20261013/`（四 APK/JAR/构建日志/native-candidate.json、tap-root-cause.md、lyaN/marbleN/lghN/jasonN/uggN 各轮 device.log+截图+SF dump+round.out、key-lines*.md、rotation-settings*.log、sanity-*.log）。pixel-judge 本轮未跑（宿主无 PIL；播放实证以 time-pos/计数器为准）。

## 构建链（2026-10-13）

- 默认入口 `tool/build-android-test.sh` 三包（tag regression-latest-20261013-{p5,p84,hdr10}，`--local-source` 分别指向 /data/local/tmp/ 下 p5-mystery-box/p84-full/hdr10-full）。
- **脚本缺陷发现与修复**：53ede203（2026-10-10 21:58 正式化）将 flutter build 步骤留在仓库根（melos workspace，无 lib/main.dart），`flutter build apk` 必失败（`Target file "lib/main.dart" not found.`）；上轮成功构建发生在该提交之前，定稿版从未端到端跑通过。修复：flutter 步骤改为 `(cd media_kit_hdr_lab && flutter build apk ...)` 子 shell。修复后三包全部构建成功（gradle 345.7s/56.6s/54.6s；p5 首构时 gradle 自动装了 NDK 27.0.12077973，与脚本 PATH 钉定的 27.2.12479018 并存无害）。
- 产物（SHA-256）：
  - JAR：p5 `9cf43ebc…aa88b31f73`、p84 `5661f73a…02829779d`、hdr10 `822db1e4…1c820e59`（jarSha256 运行间不可位复现，属 provenance 内嵌；stripped lib 三次同为 `5f8fc04c…069dd`，与上轮基线逐字节一致）
  - APK：p5 `5ff7dbd0…0a82b9`、p84 `4d27f404…5db351`、hdr10 `2b2ddd61…439ea00`（三者 42701635 字节，差异仅 MEDIA_KIT_ANDROID_LOCAL_SOURCE dart-define）
- native-candidate.json 与上轮基线：libSha256/libmpvSha256/FFmpeg 六库 archiveSha256/newSources 三项全部一致；`sourceManifestSha256` 03aaa743…→0133917d…（变化先于本轮发生，出现在失败尝试的 p5 产物中，具体输入项未查，未验证项）。

## 预检

- 素材两机 md5 一致：p5-mystery-box `3b6b8a207e6366d451d66932ea1c0ea7`、p84-full `49841d19824e262b30ebbedbdd2fbbe9`、hdr10-full `7ecb1894c954d5a641a08755bae62a19`。
- marble 还原链：现装包 md5 `0180aff190b26cbb04e7c0398567269c` 与 r30g 备份（3968e6fc）逐字节一致。
- LYA 现装包为 2026-10-11 测试遗留（firstInstall 2026-10-11 23:29），回归后按协议卸载恢复原状。
- 预期路由（上轮对照）：LYA p5=metadataReshape→nativeHdr/PQ（platformView gpu-next）、LYA hdr10/p84=baseLayerDirect 直出（p84 HLG，DV=false 预期）；marble p5/p84=nativeDolbyVision 默认直达、marble hdr10=baseLayerDirect→PQ。全轮 render_failures=0、fatal=0；marble p5 post-EOS dispose 已知问题②。

## 设备轮结果

### 第一组双机六轮（lya3-*/marble3-*）：作废（tap 坐标错误，环境操作事故）
- 现象：六轮全部 OPEN_MISSING，app 停在 `awaiting_tap`（`pause=yes idle-active=yes` 贯穿全程），render_failures=0、fatal=0，LYA dispose 正常、marble 无 dispose。证据保留（round-*.out / device.log / 截图 / SF dump）。
- 根因（Lead 实机定位）：输入显示空间为横屏（marble logicalSize=2400x1080, ROT_270；app 请求 landscapeLeft 成旋转窗口），窗口 touchableRegion=[0,0][1080,2400]，验证工作包按竖屏 `wm size` 中心取 tap（marble 540,1200 / LYA 720,1560）全部落在触摸区外被 InputDispatcher 丢弃。责任在 Lead 的坐标公式（未沿用历史横屏坐标协议，tool/matrix-round.sh:50 历史值 (1560,720) 即横屏空间坐标）。完整链路见证据目录 `tap-root-cause.md`。
- 修正：tap=(输入逻辑短边/2, 短边/2)（marble (540,540) 实测完整开播），并新增旋转设置钉定协议（轮前 accel/user_rotation=1/1，轮后还原）。marble 实测修正坐标下 P5 直达 `nativeDolbyVision verified`。

### 正式组（重跑）：lya4-*/marble4-*（双机）

**六轮 OPEN_OK，五轮与 2026-10-10 基线逐格一致；marble4-hdr10 单轮真实失败（新解码履行复核门竞态），复跑判定中。**

| 轮 | 路由（selected→output/vo，全部 confidence=verified playable=true） | EOS | dispose | render_fail/fatal |
| --- | --- | --- | --- | --- |
| lya4-p5 | metadataReshape→pq/gpu-next platformView | ✓（AUTO_COMPLETED true） | ✓ | 0/0 |
| lya4-p84 | baseLayerDirect→hlg/mediacodec_embed | n/a | ✓ | 0/0 |
| lya4-hdr10 | baseLayerDirect→pq/mediacodec_embed | n/a | ✓ | 0/0 |
| marble4-p5 | nativeDolbyVision→dolbyVision/mediacodec_embed render-mode timed | ✓ | ✗（已知问题②，post-EOS BACK） | 0/0 |
| marble4-p84 | nativeDolbyVision→dolbyVision/mediacodec_embed render-mode boolean | n/a | ✓ | 0/0 |
| marble4-hdr10 | baseLayerDirect→pq/mediacodec_embed（**会话失败，见下**） | 播放至 ~60s 后停 | ✗（BACK 无响应） | 0/0 |

- LYA 三轮与 10-10 基线逐格一致；marble p5/p84 与基线一致；本轮 LYA 截图多 MB（真实内容，对照无效轮 20KB 全黑）。
- **marble4-hdr10 失败定性**：开播 0.35s 时 `PREOPEN_FULLSCREEN_OPEN error=HdrDecoderReviewFailure(Observed decoder changed: current-tracks/video/decoder)`（新解码履行复核门，hdr_decoder_review.dart:264，经 HdrOpenCoordinator.openSource）；VIDEOPARAMS 显示 4K 解码器实际已起（3840x1920 mediacodec），会话处于半回滚状态，t≈60 播放停止（显示 HDR 能力变更事件×4 后 app 零日志、PERF 定时器消失）、BACK 无 dispose。同文件同路由 lya4-hdr10（今日）、marble4-p84（今日）、marble2-hdr10（10-10 基线，当时无此门）均通过——判定为**复核门竞态误触发**，flake 率待 marble5-hdr10 复跑判定。
- 修正证据基线：tap=(输入逻辑短边/2, 短边/2)；轮前 accel/user_rotation=1/1、轮后还原（rotation-settings.log 全记录：LYA 还原 0/0，marble 实验期遗留 1/1 由 Lead 终还原 0/0——accel 原值 0 实证，user_rotation 原值未及读，按默认 0）。
- 还原核验（Lead 终验）：marble 安装包 md5 `0180aff190b26cbb04e7c0398567269c` = r30g 备份逐字节一致；LYA PACKAGE_ABSENT；两机亮度/熄屏还原。

### 扩展三机结果（jason 通过；LG 重跑后通过（附两条目视复核旗标）；ugg blocked）

- **jason（Mi Note 3，lineage API35）**：jason3-p5/jason3-sdr 两轮有效，**对照 09-30 观察基线通过**。P5：`toneMapSdr/verified`（无 HDR 屏预期路由）、texture/gpu-next/mediacodec、全片 EOS、decoder 丢帧 0、render_failures=1（EOS 尾帧一次，09-30 同签名）、fatal=0；VO 丢帧 4987（≈84%）与 09-30 记录的 SD660 展示链设备限制精确一致（非本轮回归）。SDR：`sdrDirect/verified`、零丢帧零失败、EOS 正常。
- **LG（H870DS，API24）**：首轮 lgh3-* 三轮死于脚本 setprop（LG ROM 属性名 32 字符上限，`debug.media_kit.p5_image_timeline` 33 字符，`set -e` 中断）——脚本缺陷，加 `|| true` 修复后 lgh4-* 三轮成功：
  - **p5：对照 LG 线基线通过**——`nativeDolbyVision, verified, playable`（=2026-10-09 LG 收口"P5 直通恢复并默认化"验收路由；测试链最新源码 JAR 在 API24 正常加载，vkweak 疑虑未复现），全片 EOS（time-pos 98.9s）、frame-drop=3（对照 jason 同素材 4987）、render_failures=0、fatal=0。
  - **p84：机制吻合**——`baseLayerConvert + mediacodec-copy + output pq + stripRpu`（=10-09 修复的 YUV HWC 视频层机制），SF 实锤 SurfaceView 经 HWC 合成；REPORT `degrade=dataSpaceApplyFailed`、confidence=unverified——**旗标：色彩/呈现需人工目视复核**（本轮无人验）。
  - **hdr10：路由漂移（可解释）**——默认策略选 `baseLayerDirect/verified/playable`（LYA/marble 验证的矩阵格；LG 线旧构建带 LOCK/PREFER/VISUAL278 严格实验门，本测试构建默认策略无门，偏好序上探），零渲染失败、dispose 正常——**旗标：与 LG 10-09 人验基线（convert）不同，建议 30s 人工目视复核**。
- **ugg（Redmi Note 5A，lineage API37）**：blocked——**安全锁屏**（`inputRestricted=true`，MENU/屏内滑动均不解锁），自动化按规不可越过；两轮（ugg3/ugg4-sdr）均止步 FOCUS_FAILED，无播放数据。sdr 素材已就位，**待用户手动解锁设备后重跑一轮（90s）**。设备已还原原状（卸载、亮度、熄屏、旋转设置）。
- 跨设备观察——**已知问题②范围修正**：post-EOS BACK 不触发 dispose 本轮在 LG(API24) 与 jason(lineage API35) 复现（p5 全片轮 BACK 均 post-EOS；两台 p84/hdr10 pre-EOS BACK dispose 正常）。②原归因"HyperOS API35 × post-EOS"不成立——现数据：复现于 marble(35)/jason(35)/LG(24)，LYA(29) 通过；共性因子待查，非 ROM/API 特异。
- 证据格式变化：路由分支 lab app 的 `ACTUAL=` 行不复存在，actual 语义并入 prediction 行后缀 `presentation=… confidence=… playable=…`。

## 判读

- **通过判据与结论**：每台设备对照其文档在案基线（marble/LYA←10-10 双机矩阵；LG←LG 线 10-09/10 收口验收；jason←09-30 观察记录；ugg←09-30 不可行裁决范围内的 SDR 能力）。marble/LYA/LG/jason 全部通过（marble hdr10 首跑失败经复跑证实为间歇性复核门竞态，记为分支新缺陷待修，不阻塞本轮回归结论）；ugg 因安全锁屏未测，属外部阻塞。
- **不构成本轮失败的事项**：marble p5 post-EOS dispose 缺失（已知问题②）；jason 84% VO 丢帧与 EOS 尾帧一次渲染失败（09-30 在案设备限制）；LG p84 `degrade=dataSpaceApplyFailed`（机制层 HWC 合成实锤在案，色彩人验旗标另补）；pixel-judge 未跑（宿主无 PIL，播放推进以 time-pos/计数器实证）。
- **待办（本轮产出）**：① 修复解码履行复核门竞态（HdrDecoderReviewFailure 误触发，分支内）；② marble5 复跑通过但 marble4 失败现场保留于证据目录供该修复复现；③ ugg SDR 轮待用户解锁；④ LG p84/hdr10 各 30s 人工目视复核；⑤ post-EOS dispose ②归因修正已入档（复现 marble/jason/LG，LYA 通过）。
