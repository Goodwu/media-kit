# DV-BUILD-01 实机结果：全链最新源码重建 + 自动路由矩阵（DEVICE）

日期：2026-10-11。角色：DEVICE。中央登记：media-kit PR#4 comment 6109258398（接手）、6109723491（DV001 整改）、6110194338（阶段结果）。构建仓配方：Goodwu/libmpv-android-video-build-dv-experiment PR#1（device/MK-ROUTING-20261011/DV001）。

## 输入向量（实测构建）

见同目录 input-vector.md（r2）。要点：FFmpeg routing 9aba43cf（含 e8df200c）+ mpv media-kit/android tip c11426b67a + libplacebo optimize/dovi-linear-decode tip ea700489 + helper b768ce102，NDK 27.2.12479018，arm64-v8a 全源码重建；JAR `default-arm64-v8a.jar` SHA-256 `cd5fe26befeb6e9f96627692f5883abe860381853bac997f45806139c9851622`；App 输入 PiliPlusX 8bed4a4f6 + media-kit a3cdbda2。App/lab 全部经 `mediaKitLocalArm64Jar` 注入（gradle 日志核对 local jar SHA），钉定未改。

关键 native 指纹：libmpv.so 含 native_dv/nativeDV×39、dovi-p5-pipeline、render-mode（=mpv tip）；符号 avformat_complete_initial_dovi_hvcc（=FFmpeg routing）；**未定义 Vulkan 导入仅 4 个 1.0 符号**——mpv c11426b67a 的 12030b9c39 已把 Properties2 族改为实例解析，两个 1.1 导入消失，vkweak 弱化在新源码上为 no-op（对照 v2026.013 仍带 2 个 w 弱符号）。Android 7 直接可载。

## 实机矩阵结果

### App（PiliPlusX，Bilibili 深链 SDR BV1T7t96BECu，冷启动→播放→帧推进→退出）

| 设备 | 包 | 启动 | 解码 | 结果 |
| --- | --- | --- | --- | --- |
| LG H870DS（API24/msm8996） | A（exp=false） | ok 1.4s / 0 FATAL | OMX.qcom avc Executing | PASS |
| LG H870DS | B（exp=true） | ok 0.9s / 0 FATAL | OMX.qcom avc Executing | PASS（SDR 负向无回归） |
| HUAWEI LYA-AL00（API29/kirin980） | A | ok 0.7s / 0 FATAL | OMX.hisi avc | PASS |
| LYA-AL00 | B | ok 0.8s / 0 FATAL | OMX.hisi avc | PASS |
| Redmi marble（API35/taro） | A | ok 3.0s / 0 FATAL | c2.qti.avc（CCodec） | PASS |
| Xiaomi Mi Note 3（API35/sdm660，SDR 屏） | A | ok 1.8s / 0 FATAL | OMX.qcom avc | PASS |

### lab 矩阵（本地素材，OPEN_ON_TAP，logcat 路由报告）

素材：P5=media-kit-DV-P5.mp4（容器 DOVI 记录在案）；P8.4=mkchk-media-kit-p84-rpu-12s-control.mp4（**仅带内嵌 RPU、无容器 DOVI 记录的 12s 控制片**）；HDR10=lg-pq-1080p；HLG=dvs-hlg。

| 用例 | 设备 | 策略 | 实际路由（logcat HdrRouteAppliedEvent） | 结果 |
| --- | --- | --- | --- | --- |
| p5-G（exp=true） | LG | HDR_GATE_OPEN 确认 | SDR-first→复核重建：OMX.qcom.**dolby-vision** Loaded→Idle→**Executing**，全屏渲染正常 | PASS |
| p5-F（exp=false） | LG | 默认 | 同上（native DV 路由不依赖实验门） | PASS |
| p84-G | LG | HDR_GATE_OPEN 确认 | 重分类为纯 HLG（该片无容器 DOVI 记录，正确不虚构 DV 事实）→baseLayerConvert 尝试→`HdrDegradedEvent(reason: dataSpaceApplyFailed)`→**toneMapSdr** verified，帧推进 | PASS（有界降级，未重复失败依赖） |
| p84-F3 | LG | 默认 | 同最终路由 | PASS |
| hdr10-F | LG | 默认 | **baseLayerDirect**→nativeHdr output=pq，topology=platformView，vo=mediacodec_embed，hwdec=mediacodec，Executing | PASS |
| hlg-F | LG | 默认 | toneMapSdr（面板无 HLG 能力，正确降级） | PASS |
| p5-G | LYA | HDR_GATE_OPEN 确认 | **metadataReshape**→nativeHdr output=pq（dynamic=true，experimental reshape 路由真实执行），画面渲染 | PASS |
| p84-G | LYA | HDR_GATE_OPEN 确认 | **baseLayerDirect**→nativeHdr output=**hlg**（现代面板 HLG 直出） | PASS |
| p84-F | LYA | 默认 | 同上（false 无回归） | PASS |
| p5-G | Mi Note 3（SDR 屏） | HDR_GATE_OPEN 确认 | **toneMapSdr**（SDR 屏对 DV 源正确 tone-map，不虚报 HDR） | PASS |

自动路由按显示能力/设备分派的行为得到跨设备对照：同一 P8.4 源在 LG（无 HLG 面板）降级 toneMapSdr、在 LYA（HLG 面板）baseLayerDirect 直出；同一 P5 源在 LG 走 native DV 解码器直通、在 LYA 走 metadataReshape、在 SDR 屏 tone-map。

## 观察（非缺陷，登记待 CORE 判断）

1. **baseLayerConvert 的计划/执行差距**（LG API24）：上一轮（10-05 证据）baseLayerConvert 在计划期被 `gpuHdrDataSpaceUnavailable` 跳过；本轮能力查询认为可行、在应用期 `dataSpaceApplyFailed` 降级。最终路由相同（toneMapSdr verified），降级有界且未重复失败依赖，符合 B1 语义；但能力探针与 vendor dataspace 应用结果不一致，建议 CORE 复核 LG-pq ext 适用性判定。
2. **无容器 DOVI 记录的 P8.4 控制片分类为纯 HLG**：正确（不虚构 DV 事实，B1b 语义生效）。但矩阵因此缺少「带 DOVI 记录的 P8.4」实机例；上轮使用的 media-kit-p84-full.mp4 已不在设备/素材库。**not_run（素材缺口）**，待补素材后复测。
3. LG 呈现帧率通道仍不可观测（上轮已登记），本轮继续不把提交帧率当呈现率；帧推进以截图差分证明。

## 环境事实与证据

- 证据目录：/Users/wuweiwei1/src/mk-device-20261011/evidence/{LG-smoke-A,LG-smoke-B,LYA-smoke-A,LYA-smoke-B,marble-smoke-A,minote3-smoke-A,LG-matrix,LYA-matrix,MiNote3-matrix}/（logcat、截图、帧差分）。
- LG 已知怪癖遵守：logcat 须 exec-out；激进休眠需 wake+stayon；Google Play 商店弹窗与被测应用无关。
- 工具链与补丁、APK/JAR 哈希见 input-vector.md；矩阵构建脚本与单例跑测脚本见同目录。
- 签名：本机 debug keystore（与既有本地构建一致）；未触碰任何设备账户/签名设置，未清 App 数据（install -r 升级保数据）。

## 状态

- implementation：pushed（build-repo DV001 PR#1；本 docs 分支）
- validation：passed_for_vector（上表全部用例，输入向量 r2）
- integration：pending（等待 CORE 合入 DV001 与本分支后，最新整合向量复测 P5/P8.4 关键路径）
