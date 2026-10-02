# TASKS.md

任务事实源：这里只保留当前状态、验收门槛和下一步。清理前的完整任务台账快照：`archives/experiments/tasks-ledger-snapshot-20260927.md`、`archives/experiments/tasks-ledger-snapshot-20261002.md`；按各项 `context` 查看持续更新的依据。

## 接手快照（2026-10-02 更新；换 agent 从这里开始）

- **mpv 审整改实机验收完成（2026-10-01，LYA）**：review 立即修四项（P0-1/P0-2/P1-1/P1-2）+ 短期清理全部实机验证通过并已提交 mpv fork；MAE 系统偏差分量与基线一致（8× 块平均全 ≤100）；P0-1 同进程双文件双 dump 通过；4K59.94 SDR 性能不劣于 398d0c3/c025cbf 同夜对照。整改产品 JAR `media-kit-remediation-final-product.jar`（a7f36bd4…）已入 `~/src/media-kit-build/jars/`。详见 `archives/experiments/android-remediation-mae-p0-readback-20261001.md` 与 conversation `architecture-review-remediation-20260930.md` Current State。
- **发布闭环完成（2026-10-02）**：release `libmpv-android-v2026.10`（默认 arm64 libmpv 钉定），mpv `5f9ddf1777` 已推送、dv-experiment 钉定 `baac282`、media-kit 钉定 `0f1b417d`；整改世代 JAR/标识串/build.gradle 三件套已同步。
- **4K60 负载归因完成（2026-10-02）**：**热状态主导、代码世代全排除**（9/30 原始 12700 APK 同字节复测 4808 vs 当时 2102，电池 41°C/GPU capped 277MHz；App 三代×mpv 四代×libplacebo 两代同热一致）。唯一残余：冷机 GPU 需求 586 vs 9/28 记录 415MHz 的差异（快速路径效益或 DVFS 漂移），冷机复测已排定。详见 `archives/experiments/android-4k60-dropload-attribution-20261002.md`。
- **不可行项（维持现状即终态）**：3.1 deleteAsync（LYA 无 `EGL_ANDROID_native_fence_sync`，9/26 已证）、maxImages 提升（OMX.hisi 拒绝，本轮实证）、撤 `get_req_frames` hack（依赖前两者）。低价值项详见 conversation `architecture-review-remediation-20260930.md` 遗留复核节。
- **事实源与范围**：本文件是任务状态，`archives/README.md` 是主题导航，`archives/conversations/android-hdr-dv-display-plan-20260922.md` 顶部 `Current State` 是当前 Android 主题上下文；`archives/conversations/architecture-review-remediation-20260930.md` 是整改主题上下文；`archives/experiments/android-private-tmp-handoff-20260928.md` 是临时工作树路径及补丁入口。以上均为快照，接手后先重新读 Git/设备状态。
- **代码状态（三仓库单线格局）**：① Goodwu/media-kit `main` = 原修复分支全部工作 + 上游 main 236 提交合并（`a886f556`，五项实机验收通过）；② Goodwu/mpv `media-kit/android`（发布 tag `media-kit-v2026.10`→`5f9ddf1777`）；③ FFmpeg `feature/android-mediacodec-p5-rpu`（本地 tip 已前进至 `b4d2ea4ffb`，2026-10-02 整改提交、未推送；台账验证基线、`product-ffmpeg-lib` 与发布链仍 `fff3ee7`，整改版验证缺口见 Next 对应任务）、libplacebo `optimize/dovi-linear-decode`（`c9fd879`）各单分支。废弃分支均以 `archive/*-202609` tag 归档（全清单见 `archives/experiments/android-mpv-fork-branch-consolidation-20260930.md` 追加节）。
- **mpv fork 上游策略（2026-09-30 定）**：**跟发布版不跟 master**。已核实 master 未包含我们任何一项修复；master 的 vo_gpu_next 1029 行 libplacebo v7 迁移与 1100+ 行本地改动正面冲突。下次同步：等 v0.42 发布 → merge-tree 试评估（重点 hwdec API 与 vo_gpu_next dovi 路径）→ P5 五项回归后打新发布 tag；期间个别修复按需 cherry-pick；FFmpeg 安全修复走 CVE 按需 cherry-pick 单独机制。
- **P5 修复要点**：华为硬解输出为 Main10 10-bit 布局（AHB 0x325，驱动 Y2Y 采样按 /1020 归一化，`archives/experiments/android-p5-buffer-bitdepth-mystery-20260930.md`），dovi 域按 code/1023 解释 → 1023/1020 缩放偏色；修复为 dovi 元数据就地重标定（mpv fork，k=1023/1020），数值验收 (47,50,70)/(50,19,58)/65535 ≤100。教训：读回装置旧前缀 FFmpeg 需 `debug.media_kit.p5_rpu_probe=2`；产品链接必须用 fff3ee7 世代 libavcodec（持久副本 `~/src/media-kit-build/product-ffmpeg-lib/`），误链 mkp4prefix 旧版会复演 `direct=0`。详见 `archives/experiments/android-p5-mediacodec-color-fix-20260930.md`。
- **环境**：ADB 可用（设备 `3EP7N18C28016072` / LYA-AL00），每轮结束恢复原 12492、自动亮度、熄屏。**持久化资产（2026-09-30 起；/tmp 副本重启即弃，以下为权威本地副本）**：`~/src/mpv`（mpv fork 完整工作树，`media-kit/android` tip）；`~/src/media-kit-build/`（`mkp4prefix` 构建前缀、`product-ffmpeg-lib` fff3ee7 libavcodec、`jars/` 发布 JAR、`apks/` 验收包、`evidence/` 设备日志、`sources/` 测试源视频、`scripts/` 重链脚本 `mk-relink-product.sh` 等——轮次脚本权威版本在仓库 `tool/`）。读回构建链：mpv 源码 `~/src/mpv` + 前缀 `~/src/media-kit-build/mkp4prefix` + 手工链接需补 `-lc++_shared`；APK 直改重签（lib store + zipalign -p 4096 + debug keystore）。JDK17 构建、`ORG_GRADLE_PROJECT_mediaKitLocalArm64Jar` 注入 JAR 的正式流程不变；media-kit 主仓推送遇挂起时绕过 osxkeychain：`git -c credential.helper= -c credential.helper='!gh auth git-credential' push …`。可复用轮次/构建/分析脚本已收编仓库 `tool/`（使用说明 `tool/README.md`）。

- **HDR 能力路由 Phase 1（S0–S13）完成（2026-10-02）**：会话 API/私有回退子包/诊断日志/hdr_lab 迁移/LYA 27+ 轮实机验收/PiliPlusX 接入全部交付并通过对应等级审核；验收记录 `archives/experiments/android-hdr-auto-output-acceptance-20261002.md`。**三仓状态（2026-10-02 晚更新）**：media-kit main 已与远端同步（`420fba3e..8d8382da` 已推送，②+方案 B 本轮提交随本轮推送）；mpv fork `media-kit/android` 已推送至 `d24c59905b`（远端分支实际存在且原在 `5f9ddf1777`——早前"远端无同名分支"记录有误；发布 tag 流不变）；PiliPlusX `fix/darwin-video-output-rebuild-barrier` 已推送 personal remote `Goodwu/PiliPlusX`（`07f153733..2ce821d4c`；其 origin 指向上游 cnctem 无写权限）。构建仓 dv-experiment `feature/android-dv-build` 已推送 `91bb42af`（`v_mpv=d24c59905b`）；产物 JAR `media-kit-d24c59905-arm64-v8a.jar`（SHA-256 `cafef3a4…`）在 `~/src/media-kit-build/jars/`。CI 标记与 build.gradle 钉定随发布链同步，勿提前加。
## 当前任务

- [ ] Android HDR10 / DV P8.4 显示与原生 HDR 首帧闭环
  - status: in_progress
  - context: archives/conversations/android-hdr-dv-display-plan-20260922.md
  - acceptance: 固定素材和设备能力，核对 HDR10 PQ、P8.4 HLG 的真实后端、Surface 格式、系统合成、连续全屏画面及 SDR 复位；P8.4 无 HLG 路径与原生 DV 能力单独说明。原生 HDR 从触摸到视频内容小于2秒、争取1秒，补冷/热、重入与输出切换。最高亮度只用于短时人工观察，结束立即恢复自动亮度并熄屏。
  - 素材：P5→PQ 输出/首帧/性能用 `~/Downloads/test-clips/Mystery Box Dolby Vision Profile 5.mp4`（SHA-256 `3e610d3b…`，HEVC Main10 4K60 DV P5/RPU，98.944s）；Glass P5 4K59.94（SHA-256 `afb24b77…`）保留作片尾紫屏定点复现。
  - latest: **四仓库归一后播放矩阵六轮全部通过（2026-09-30，12703–12708）**：P5/P8.4/HDR10 × SDR/HDR，全片 EOS（P8.4 为 5 分钟观察窗），输出路径全部符合预期，零渲染错误、资源闭合全对等。证据 `archives/experiments/android-playback-matrix-12703-12708-20260930.md`。第二台设备（Redmi Note 5A，骁龙 425）同矩阵不可行并按用户要求中断（OMX HEVC 不支持 4K、屏幕无 HDR）；第三台设备（Mi Note 3，骁龙 660）4K Main10 硬解/直采/EOS 通过但展示链路 VO 掉帧 84%，EOS 尾帧一次取图失败且回退未触发（设备差异观察项，原因未查）——均见同文件追加节。此前 HDR10、P8.4 全屏画质和流畅性已获用户认可；首帧读回 P8.4 HLG 0.623–0.676s、HDR10 PQ 0.630–0.653s（Surface 读回，非面板光学）。
  - next: 扩充原生 HDR 冷/热、重入、连续帧及 SDR 复位证据；P5 输出和首帧单列于 P1，不以 HDR10/P8.4 代替；P8.4 全片 EOS 按需补跑。可与 4K60 冷机复测（接手快照残余项）合并同一 LYA 会话。
  - temp_reconcile: **已关闭（2026-10-02）**：`media-kit-firstframe-sdr-20260927`/`media-kit-firstframe-mix-20260927` 实测已消失（主机 16 天未重启、最后访问超 3 天，应为 macOS /private/tmp 周期清理），文件级核对不可能；按既有记录结论关闭（868 删除项本就不可重放，产品清理以 Git 历史为准），首帧/输出行为实机回归需求并入上方 next。

## Next（近期候选，最多 10 条）

- [ ] player-set-shuffle(-consecutive) 概率性 flaky 测试处置（上游同源，2026-10-03 定性登记）
  - status: planned（低优先；上游同样偶发）
  - context: archives/experiments/ci-fix-20261002.md（终验节：机制与证据链）
  - acceptance: 随机洗牌未变序时测试不再误报（本地无法跑 player 套件——缺 libmpv 环境，需 CI run 验证）；处置方式（本地改测试 vs 提报上游）定案。
  - latest: Linux/Web CI 偶发失败同一测试（420fba3e 轮 Web 挂姊妹用例 player-set-shuffle）。机制：`player.stream.playlist` 为 `_DistinctStream` 去重，mpv `playlist-shuffle` 4 项有 1/24 概率洗回原序 → 事件被吞 → 测试按"必变序"断言失败（日志实测 Stream closed 无第二事件）。证据：ff780809..420fba3e 窗口 media_kit 根包零提交；测试文件最后变更=a886f556 合并；**上游 media-kit run 36586434948（09-29）Web job 挂的正是同一测试**。
  - next: 排期后处置：候选=测试内对未变序情形重洗/容忍（本地改，注意上游合并冲突面）或提报上游；改动需一次 CI run 验证。

- [ ] Windows package tests 原生崩溃调查 + mpv-dev 夹具现代化（fork 特有回归，自 CI 修复任务分出）
  - status: planned
  - context: archives/experiments/ci-fix-20261002.md（⑥节：崩溃上下文与归因边界）
  - acceptance: 定位崩溃套件与根因并修复（或实证归因为夹具年代伪信号）；`package:media_kit tests (Windows)` 恢复 success；Windows 测试夹具从 2023-08-11 件升级至 libmpv-win32-video-build 最新 release（fork win32 构建件就位后仅换钉定 URL）。
  - latest: **用户决策（2026-10-03）：Windows 是长期产品目标，Windows 构建/测试 job 保留不关**。夹具现代化评估为"对目标有实质推进、非仅消音"：①2023 件为 mpv ~0.36 代、我方 fork 基线 0.41，升级后测试环境行为大幅逼近 fork 现实；②Dart FFI 契约面在 Windows 持续受测、栈不腐烂（参照 web 编译面无编译即一日烂的先例）；③未来 fork win32 构建件就位后，工作流管道/测试套件直接复用，升级是该演进路径第一段。另：Windows 构建 job（x64/ARM64/optional/audio）与 mpv-dev 夹具无关（用 libs 包自带 dll），属纯编译覆盖，任何情况下保留。
  - latest-: 崩溃事实：0xC0000005（access violation）pc 在 libmpv-2.dll（钉定 mpv-dev 2023-08-11 件）内；`asset-loader-encode-asset-key` 通过后约 5s、下一播放类套件崩溃（早于用例名输出，Dart 崩溃处理器走栈失败——现无可用 backtrace，仅故障地址）。上游 media-kit 同 workflow 8b4d3afc（09-29 PR run）Windows tests **success** → fork 特有回归；窗口 ad22c36a（09-01 绿）→ eacc799a（09-30 首败）= 上游合并 a886f556（63 冲突裁定）+ 期间我方提交。本地 macOS 无法复现（media_kit VM 套件缺 Mpv.framework）。已排除方向：media_kit core 无 fork 专属符号引用（dovi/p5 面全在 media_kit_video Android bridge），fork 对 C ABI 是纯加法——老件可正常加载，崩溃属行为交互非符号缺失。
  - next: 诊断优先：①一次 workflow_dispatch 双变体 A/B（同代码分别挂 2023 件与最新上游 mpv-dev；`dart test -j 1 --reporter expanded` 串行定位崩溃套件，可挂 cdb 抓真栈）——新件不崩=夹具年代伪信号，直接升级钉定收口；仍崩=core 改动/合并裁定真 bug（首查 3a4fcaa2 NativePlayer 改动与 a886f556 player/native 冲突裁定，不收敛再分支二分）；②夹具升级随收口执行。Web/Linux 单测 player-set-shuffle 复看已完成（2026-10-03）：与崩溃无关，系上游同源 flaky（已另立条目）。远期（不另立项）：fork win32 构建链（msys2 交叉编译进 CI）。

- [ ] FFmpeg P5 RPU 整改版（`b4d2ea4ffb`）按测试计划验证（2026-10-02 登记）
  - status: planned
  - context: archives/conversations/android-hdr-dv-display-plan-20260922.md（2026-10-02 验证缺口核对节）；测试计划 `~/src/FFmpeg/TEST-android-mediacodec-p5-rpu.md`（FFmpeg 仓未跟踪）
  - acceptance: 推送 `b4d2ea4ffb`；以整改版重建产品 libmpv 链路（现 `~/src/media-kit-build/product-ffmpeg-lib/` 为 fff3ee7 世代）；按测试计划执行 P0 用例 T1–T8 及 T9（pts 复现，整改主修复点），close 时 summary 日志满足计划健康标准；结论只对 `b4d2ea4ffb` 及之后版本出，fff3ee7 世代结论不外推。
  - latest: 整改提交 `b4d2ea4ffb`（2026-10-02 02:39，本地未推送，按 REVIEW 意见整改）：新增 `mediacodec_dovi.c/h`、重构 `mediacodecdec.c`、公共层 receive 签名变化（aac/amr/mp3 共用上下文需回归）、新增解码器 `dovi=auto|on|off` 选项；修复 `fff3ee7a3e` 两已知问题（pts 复现时元数据整批丢失、4K 喂数据路径双重拷贝）。核对结论：此前全部验证均在旧提交 `fff3ee7a3e` 世代完成，测试计划明确"不要用旧提交出结论"；且无任何工作参照过该计划（media-kit 全仓对计划文件名/日志验收点/失败标记零引用，计划成文晚于全部既有验证）。
  - next: 排期后执行：推送整改提交（连同 TEST/REVIEW 两份未跟踪文档处置）→ 产品库重建 → T1–T8 + T9；若采纳整改版，发布链 FFmpeg 钉定（`fff3ee7`）与 `product-ffmpeg-lib` 同步重钉。

- [ ] PiliPlusX 性能优先/画质优先开关（HDR 路由策略预设）
  - status: planned（2026-10-02 用户登记，暂不实施）
  - context: archives/conversations/android-hdr-auto-output-20261002.md（设计评估记录节）
  - acceptance: 库侧提供两个命名策略预设——性能优先 = 默认偏好序（直出优先）+ 不放宽 experimental 门禁；画质优先 = dvP84 reshape 置顶 + `allowExperimental`；PiliPlusX 只选预设、不写平台/设备决策（A8 红线）；运行中可切换（会话原位重建，A5 已验证路径）；文档显式声明 **P5 豁免**（必须 reshape，性能优先对 P5 不生效，R3.3 语义）与 **HDR10+/HDR Vivid metadata 处理未实现**（画质优先对其暂为空操作，前置依赖 ② 完整目标）；**不做固定抽帧**（自适应 framedrop 默认开启已覆盖"性能优先不卡"；gpu-next 路径 4K60 降载如有数据需求走质量参数降档，固定 2:1 抽帧仅作最后手段复议）。
  - latest: 2026-10-02 用户提出原始设想（性能优先：直出+硬件不支持时跳过 P8.4/HDR10+/Vivid 附加 metadata+fps>50 抽帧 2:1；画质优先：优先 metadata 处理+不主动丢帧）；Lead 评估修正后用户认可登记：两预设映射现有 `HdrRoutingPolicy`（库零新机制）、P5 豁免、HDR10+/Vivid 前置依赖、固定抽帧移除（依据 4K60 归因热状态主导 + 直出路径播放器侧低负载 + mpv 无固定抽帧原语只有自适应 framedrop）。
  - next: 用户排期后立项：库侧两预设 + 需求文档/dartdoc 补记 + PiliPlusX 设置项与会话接线。

- [ ] HDR 能力路由后续三项（Phase 1 收尾登记，2026-10-02）
  - status: planned
  - context: archives/conversations/android-hdr-auto-output-20261002.md
  - acceptance: ①原生 DV 呈现（R7 预留项，FFmpeg `video/dolby-vision`+profile 打开解码器/mpv 路由/media-kit 三方，等 DV 设备到位）；②动态元数据重建扩展（HDR Vivid/HDR10+）；③`HdrCapabilities.query` 无 Player 入口 + PiliPlusX app 内 seek 验证。
  - latest: **③ 完成（2026-10-02）**：query player 改可选（186/186；media-kit 1c49c684）；PiliPlusX 删手工兜底走单一入口（2ce821d4c，81/81，构建 46441b40）；实机选档门复跑照常；seek 不变量维持进度条拖拽证据（长按钩子留人工路径）。**② fork 暴露完成（mpv `0f7e6bec32`）**：compat id/EL/ hdr-vivid 三属性 + 构建零错误；剩余：fork JAR/CI → 库消费 → 设备事实轮。①阻塞待 DV 设备。
  - latest+: **用户已批准方案 B（2026-10-02）**：P5 管线探测去 Player 依赖的最终形态 = fork 加专用只读能力属性 + 桥接 .so（media_kit_video_hdr_bridge）加抛弃式 mpv 实例探针（create→initialize→读属性→terminate，无 vo 不碰 EGL，满足 R1.1）+ 插件 engine attach 时跑一次并缓存；与 ② 的专用属性改造合并实施，不做 Dart FFI 临时版。
  - latest++: **②+方案 B 合并实施完成（2026-10-02，V1 PASS）**：fork `d24c59905b`（`dovi-p5-pipeline` 只读属性）已提交推送；bridge 第 5 个 JNI 三态探针 + `MpvPipelineProbe.java` attach 幂等缓存 + 快照 `p5Pipeline` 字段，Dart P5 判定改原生快照单一来源（option-info 代理退役，`query` 无 Player 即权威）；classifier 消费 compat-id/el-present/hdr-vivid 三属性（容器事实优先、推断回退，Vivid 接通 `HdrSourceClass.hdrVivid`）；186→204 全过（+18）、analyze 基线不变、hdr_lab analyze 0。JAR `media-kit-d24c59905-arm64-v8a.jar`（`cafef3a4…`，构建仓 `91bb42af` 已推送，7 标识串全命中）；真实 Vivid 样片收编（`user-hdr-vivid-2160p-hlg-18c7c05a.mp4`，CUVA 005.1 side data 实证）。详见 conversation Current State。
  - latest++: **②+方案 B 全链收口（2026-10-02，代码 e90ada4d + 实机 8 轮）**：代码侧（探针包+消费包，V1 PASS，186→204 测试）已提交推送；JAR `media-kit-d24c59905-arm64-v8a.jar`（构建仓 `91bb42af` 已推送）实机验证——**P5 探针 8/8 全过**（正 result=1 4–8ms/负上游 result=0，快照逐轮一致）；**容器事实通道实机验证**（p81 compat=1 容器直证、P7 FEL el=true 旧版 null 关键区分、上游 JAR 推断回退不崩）；**发现并登记：HDR Vivid 在 mediacodec 路径不可观测**（MediaCodec 剥离 CUVA side data，软解对照实证；路由结果不受影响，需求第 8 节已登记，demuxer 级 SEI 探测归 ② 完整目标）；p84 零回归（R4b）。实验记录 `archives/experiments/android-hdr-planb-device-facts-20261002.md`。教训：指定断言样片前 ffprobe 核对容器记录（mkchk p84 对照样片无 dvcC）。
  - next: 发布链三件套与人工观察两格升 verified 均已收口（2026-10-02 晚，HLG/P8.4 默认路由随之变更）。剩：② 完整目标（Vivid/HDR10+ 元数据重建，含 demuxer 级 SEI 探测绕开 mediacodec 剥离）按需另立实施；①需 DV 设备。

- [x] 待用户确认两（Phase 1 完全关闭，2026-10-02 完成）
  - context: archives/conversations/android-hdr-auto-output-20261002.md
  - ①人工观察：LYA 上看 a1-hlg-gate-85（纯 HLG 直出）与 a6-reshape（P8.4 RPU 重建 PQ）两轮画面；确认后把需求第 6 节 P8.4×baseLayerConvert 与 HLG×baseLayerDirect 升 verified 并同步代码常量表（S3 解析单测锁定两处同步）。
  - ②R3.1 口径文字：开播前规划相的候选跳过以报告候选原因披露、不发 Degraded（A3-2 实测口径，Lead 决策记录在 conversation）——是否落进需求 R3.1 文字由用户定。
  - latest: **两项全部完成（2026-10-02 晚）**。②R3.1 注记落文。①观察执行：graypatch 数值图案无人工判读价值（用户反馈），改用真实 HLG 内容（user-hdr-vivid 样片）+ P8.4 reshape 两轮，均"画面正常"确认；两格升 verified（需求第 6 节+常量表+S3 测试同步），**默认路由随之变更**（HLG 源缺省直出、无 HLG 屏 P8.4 走 convert），6 个旧断言测试改写，204/204 + hdr_lab 48/48。观察日志 `~/src/media-kit-build/evidence/hdr-observation-20261002/`。附带观察：**OHOS CI 与主 ci.yml 多 job 自 10-01 起既有失败**（依赖/环境层，失败集合与改动前基线一致；`libmpv-jar-identity` 新 run success），CI 修复待单列任务。

- [ ] OHOS HDR 能力路由支持（Phase 2，2026-10-02 显式登记）
  - status: planned
  - context: docs/requirements/android-hdr-auto-output.md R6（OHOS：VO 动态色彩契约单层写入，另立需求）；archives/conversations/android-hdr-auto-output-20261002.md
  - acceptance: 另立 OHOS 需求文档（会话 API 在 OHOS 的路由执行与报告；VO 动态色彩契约单层写入语义）；PiliPlusX 侧 useHCPP/native-surface 候选路径（hdr.dart 保留段）迁移进会话；实机验收另定设备。
  - latest: Phase 1 明确只做 Android（R6）；本条为显式登记防止遗漏。当前 OHOS 走 R2.5 透传 + unsupportedPlatform。
  - next: 先立需求文档（含 OHOS 显示/解码能力查询面），再排实施。

- [ ] macOS（darwin）HDR 能力路由支持（Phase 2，2026-10-02 显式登记）
  - status: planned
  - context: docs/requirements/android-hdr-auto-output.md R6（darwin：三事实交集门禁、final24 运行时禁止降档，另立需求）；media-kit TASKS「修复 macOS modern mpv 销毁时未释放 render context 的崩溃」（前置依赖）与 PiliPlusX final11 崩溃记录（render context free 屏障未落地前 macOS HDR 候选不可打包）。
  - acceptance: 另立 darwin 需求文档（EDR/三事实门禁/final24 禁降档）；会话 API 在 darwin 的路由执行与报告；同源同 PTS 亮度对照验收。
  - latest: 前置：macOS render context 销毁屏障（上方 queued 任务）必须先完成，否则重打包即复演 final11 SIGABRT。
  - next: 前置任务完成后立需求文档。

- [ ] 全平台会话逻辑一致性审计与未实现平台显式 stub（2026-10-02 用户指令）
  - status: planned
  - context: docs/requirements/android-hdr-auto-output.md R2.5；archives/conversations/android-hdr-auto-output-20261002.md
  - acceptance: 审计 HdrVideoSession 在每个平台（android/darwin/ohos/linux/windows/web）的当前路径并落表；为暂不实现会话编排的平台加显式 stub（未实现即报错/报告 unsupportedPlatform，不静默假透传），保证调用方在全平台得到一致的逻辑形态；决策与 R2.5"透传+调用方不分平台分支"的取舍由用户确认后落需求修订。
  - latest: 现状：Android=完整会话；darwin/OHOS=透传+unsupportedPlatform（R2.5 Phase 1 规定）；linux/windows/web 路径未审计。注意：darwin/OHOS 的透传是 R2.5 的 Phase 1 决策，若改为报错属需求修订（交用户确认）；从未规划会话的平台（如 web）加报错 stub 不与 R2.5 冲突。
  - next: 出平台×现状表与 stub 方案（哪些报错、哪些保留透传）→ 用户确认 → 实施 + 单测。

- [ ] 修复 macOS modern mpv 销毁时未释放 render context 的崩溃
  - status: queued
  - context: archives/conversations/native-output-rebuild-20260920.md
  - acceptance: 同一控制器的并发 dispose 共用完成屏障；Player 销毁前完成 native output/render context 释放，dispose 后不再写 active notifier。用 modern mpv 实际播放后退出、快速重入和输出重建，均无 `mpv_render_context_free() not called` abort。
  - latest: Darwin Player preTermination 屏障、创建/销毁仲裁及失败重试已通过 V2 静态复审。隔离 Goodwu mpv 0.41 W0 测试包完成 SDR 出图→重建→第二次出图→定时移除：两个 Surface 均有释放记录，两次 Player dispose 完成，进程未见 render-context abort，见 `archives/experiments/macos-w0-remove-20260927.md`。现有 PiliPlusX Debug app 经 LaunchServices `open -n` 可创建 1180×720 Aqua 窗口；这只解除“没有可操作窗口”的环境判断，产品 mpv 0.41 播放调用链仍未验收。
  - next: 在已可打开的 PiliPlusX 窗口中验证产品调用链有序退出、快速重入、seek、输出重建及 HDR 长播；测试页的定时移除证据不能替代这些场景。

- [ ] Android native output / 双视图生命周期回归
  - status: queued
  - context: archives/conversations/android-hdr-dv-display-plan-20260922.md
  - acceptance: Surface 重建、Home→前台、退出/重入、oldA→newB 交错和失败重试时，播放器位置与持续可见帧正确，资源最终释放；晚到 Create、Release ACK 丢失及 engine detach 有明确 owner/屏障，不以构建或单次 EOS 代替生命周期验收。
  - latest: P8.4/HDR10/SDR 的 Home→返回、双视图存活 B 回退、释放/绑定失败重试已有实机可见画面证据（12473–12477、12491/12492 各轮，详见 context）。owner broker 第一步已落地——P5 Texture 播放中直接 destroy 的确定性 SIGSEGV 根因（release NativeCallable wakeup 蹦床随 isolate 失效）已修复（12653 播放中销毁 4/4 零崩溃、12654 正常路径无回归），无视频裸 Player 终态已证（12647）；broker 现覆盖 wakeup 回调清空与视频输出释放，**mpv 终止与音频-only 宿主接线是下一增量**。详见 `archives/experiments/android-p5-engine-destroy-12646-20260929.md`。
  - next: 核验清理中再次点击、失败重试和全屏组合；继续通用失败 disposal/global-ref 定量闭合、连续可见帧与 mpv WID 回读，再决定提前停轨默认值；P5 专属双视图与属性序列故障归入 P3（已完成）。
  - temp_reconcile: **已关闭（2026-10-02）**：`media-kit-mpv-p5-replay-2214`/`media-kit-mpv-p84-rebuild-2213`/`media-kit-mpv-upstream-reader3` 实测已消失（主机 16 天未重启，应为 macOS /private/tmp 周期清理），未提交实验补丁不可恢复；按既有复现记录结论关闭，生命周期验收需求保留在上方 next。

- [ ] 整理 `archives` 的主题结构与引用
  - status: planned；context: archives/conversations/android-hdr-dv-display-plan-20260922.md
  - inventory: 2026-09-28 有 `archives/experiments` 顶层221篇Markdown、`archives/conversations` 8篇；实验记录中 P5 约133篇、HDR约27篇、P8.4约18篇、HDR10约13篇，缺统一入口。
  - acceptance: 先为每个活跃任务建立从 `TASKS.md` 可直达的主题索引，明确当前结论、证据顺序和旧实验状态；再按主题迁移零散实验文件，保持原始证据与每个topic唯一conversation；同步修正 `TASKS.md`、conversation、脚本和文档内的引用，检查链接与文件数。只有确认新路径和Git历史可追溯后才删除旧位置，不批量丢弃未知记录。
  - priority: 归档先做P5/P3索引，再处理HDR10/P8.4与首帧，最后整理其余历史。此任务与临时目录清理一起推进，避免再次出现证据只在 `/private/tmp` 的情况。
  - next: 生成文件到任务的映射、识别重复记录与外部路径引用，制定最小迁移批次；每批先更新入口和链接，再迁移、核验，最后清除确认冗余的旧文件。

- [ ] 排查 Android HDR 天空渐变层纹
  - status: deferred_by_user
  - context: archives/conversations/android-hdr-dv-display-plan-20260922.md
  - acceptance: 同 PTS 对照片源、解码/合成、输出位深和屏幕处理；若有可行改法，保持 HDR10/P8.4 的亮暗、颜色与全屏流畅性，再请用户人工确认。
  - latest: 最高亮度全屏验收中 HDR10 天空有层纹、P8.4 较轻，其余画面良好。按用户要求先记录，本轮不修；关闭抖动没有明确性能收益，也不是已验证的层纹修复。

## Blocked（等待输入或外部条件）

- [ ] 在真实 OHOS 设备上继续验证 native output 生命周期
  - status: blocked_waiting_for_device
  - context: archives/conversations/native-output-rebuild-20260920.md
  - acceptance: 原生输出实际呈现、后台/前台、退出/重入及 Surface 重建后持续播放且资源闭合；区分实体机、模拟器与静态检查证据。
  - latest: 2026-09-27 当前主机 `hdc list targets` 返回 `[Empty]`，没有可连接的真实 OHOS 设备；待设备接入后重新核验身份、包与运行状态，再继续实机验收。

## Closed（结案，未达原门槛）

- [x] 原统一素材范围（含Glass P5）首个可辨画面小于2秒：**未达成并结案；用户现改用P8.4另立上方验收项**。指定Glass P5片头约2.052秒黑场，保持从片头原速播放时仅素材时间即超过2秒；物理全屏受控读回可辨内容三轮3.543/3.374/3.625秒。SDR、HDR10 Texture→SDR、P8.4 Texture→SDR在已预建全屏路径的受控三轮均低于1秒；无同包关闭预建A/B，不能证明未经修改也达标或全部收益来自预建，亦不覆盖普通入口、光学触摸起点或原生HDR。预建通用入口及约1.41秒P5 A/B/A收益保留；详情与证据见`archives/experiments/android-first-visible-two-second-closure-20260927.md`。

## Recently Done（最近完成）

P5 主线（详细流水见 `archives/conversations/android-hdr-dv-display-plan-20260922.md` 与 2026-10-02 台账快照）：

- [x] P0 · P5→Texture SDR 优化默认开启并验证：done（2026-09-28）；Glass/Mystery Box 全片 EOS、真人确认“画面良好，无异常”。
- [x] P1 · P5→PQ 公开产品输出与首帧：done；公开 setter -22 后精确固件回退，触摸→可辨内容约 1.1 秒，PQ→SDR 复位与运行中失效同路重试均验证。
- [x] P2 · P5→PQ 全片性能：done；2560×1440 严格 EOS VO11、decoder0（相对 4K 基线 VO 少约 99.5%），用户真人观感通过。
- [x] P3 · P5 生命周期及片尾故障：done（2026-09-30 收敛）；片尾紫屏以相邻帧回退根治（收敛条件实机验证触发）；直接 Engine 销毁 SIGSEGV 以 owner broker 根因修复（3/3 零崩溃资源闭环）；退出重入/双视图/失败重试/EOF/暂停重绘全子项实机证据。
- [x] P4 · 独立色彩数值验收：done；发现 mediacodec 路径颜色回归（真实 ~0.3%，另立 P5 修复）。`archives/experiments/android-p5-numeric-color-20260930.md`
- [x] P5 · mediacodec 路径颜色回归修复：done（2026-09-30 全链闭环）；dovi 元数据就地重标定（mpv fork `398d0c3`），三方比较 ≤100/65535，产品集成三轮视觉复跑 + 真人确认。`archives/experiments/android-p5-mediacodec-color-fix-20260930.md`

其他已完成：

- [x] CI 修复：主 ci.yml 多 job 失败与 OHOS HAP 依赖解析：done（2026-10-03 收口）；五类根因全修并 CI 实证（lockfile 再生成、vnext release 上游门禁、macOS gpuStartTime 守卫、web/wasm 编译桩、hdr_lab gradle wrapper+JDK17），OHOS 全链绿（lock 引入以来 main push 首次）、`libmpv-jar-identity` 全程绿、无新增失败；残余两项各自登记（Windows 原生崩溃任务、player-set-shuffle 上游同源 flaky）。`archives/experiments/ci-fix-20261002.md`
- [x] HDR 能力查询、路由执行与报告 API + 设备私有回退子包（Phase 1 Android）：done（2026-10-02 完全关闭）；S0–S13 全交付，待用户两项（人工观察两格升 verified + 默认路由变更、R3.1 口径注记）10-02 晚收口，204/204 + hdr_lab 48/48；发布 media_kit_video 1.3.1+1 + vendor 子包 1.0.0+1；PiliPlusX 接入 A7/A8 实机通过；②+方案 B（P5 探针/容器事实消费）随发布链 v2026.011 落地。`archives/conversations/android-hdr-auto-output-20261002.md`
- [x] 架构审查整改（批次 A–H）：done；三个 P0 全部达成、全量静态回归通过、实机验收（2026-10-01 LYA 立即修四项 + 短期清理）。`archives/conversations/architecture-review-remediation-20260930.md`、`archives/experiments/android-remediation-mae-p0-readback-20261001.md`
- [x] media-kit 主仓合并上游 main（236 提交）：done（`a886f556`，63 冲突分层裁定）；P5 五项实机验收（12700–12702）无回归，main 成为唯一维护线。`archives/experiments/android-media-kit-main-merge-acceptance-12700-20260930.md`
- [x] 修复 Mi Note 3 OES 路径花屏：done（mpv `5e26cf86` buffer_retire 持有至 OES 路径）；A/B 基线 1 异常→修复 0 异常、真人确认。`archives/experiments/android-oes-buffer-retire-fix-20260930.md`
- [x] mpv fork 分支归一与发布基线：4 自定义分支收敛为 `media-kit/android` 单分支，发布 tag `media-kit-v2026.09`（398d0c3）+ 发布链固定；av_log 修复 cherry-pick 入主线。`archives/experiments/android-mpv-fork-branch-consolidation-20260930.md`
- [x] 六个已判冗余 P5 临时工作树删除：done（2026-09-29，逐目录复查）。

更早完成（详见 2026-09-27 台账快照）：

- [x] 复核 Android HDR10/DV 回退后 Release 卡顿观察；A/B/C 审查完成，日志开销仅是可能诱因。`archives/conversations/android-hdr-release-vs-debug-review-20260922.md`
- [x] 编译并安装 Android 实机 APK；构建/部署与播放验收分开。`archives/conversations/android-hdr-dv-display-plan-20260922.md`
- [x] 切换 OHOS libmpv 二进制发布来源至 Goodwu 20260920。`archives/conversations/ohos-libmpv-release-20260920.md`
- [x] 修复跨平台 native video output 重建与释放的已定义代码/提交门槛；真实设备长期生命周期由上方任务继续跟踪。`archives/conversations/native-output-rebuild-20260920.md`
- [x] 修复 macOS native output 首帧呈现与 epoch gating 的已定义代码/提交门槛。`archives/conversations/native-output-rebuild-20260920.md`
- [x] 清理本地工作树忽略项。`archives/conversations/native-output-rebuild-20260920.md`

## 规则

- 新任务写入本文件；活跃项保留 `context`、可验证的 `acceptance` 和当前 `latest/next`。
- 实验流水、包身份、日志和历史判断写入对应 conversation 或 experiments，不在任务项重复堆积；清理时先做台账快照。
- 完成项打勾并压缩为一行结论 + context 指针移入 Recently Done；超过近期容量后留存于 context/Git 历史。
- 提交前同步 TASKS 与/或对应 conversation；变更记录以 Git log 为准。
