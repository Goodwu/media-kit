# TASKS.md

任务事实源：这里只保留当前状态、验收门槛和下一步。清理前的完整任务台账快照：`archives/experiments/tasks-ledger-snapshot-20260927.md`、`archives/experiments/tasks-ledger-snapshot-20261002.md`；按各项 `context` 查看持续更新的依据。

## 接手快照（2026-10-02 更新；换 agent 从这里开始）

- **mpv 审整改实机验收完成（2026-10-01，LYA）**：review 立即修四项（P0-1/P0-2/P1-1/P1-2）+ 短期清理全部实机验证通过并已提交 mpv fork；MAE 系统偏差分量与基线一致（8× 块平均全 ≤100）；P0-1 同进程双文件双 dump 通过；4K59.94 SDR 性能不劣于 398d0c3/c025cbf 同夜对照。整改产品 JAR `media-kit-remediation-final-product.jar`（a7f36bd4…）已入 `~/src/media-kit-build/jars/`。详见 `archives/experiments/android-remediation-mae-p0-readback-20261001.md` 与 conversation `architecture-review-remediation-20260930.md` Current State。
- **发布闭环完成（2026-10-02）**：release `libmpv-android-v2026.10`（默认 arm64 libmpv 钉定），mpv `5f9ddf1777` 已推送、dv-experiment 钉定 `baac282`、media-kit 钉定 `0f1b417d`；整改世代 JAR/标识串/build.gradle 三件套已同步。
- **4K60 负载归因完成（2026-10-02）**：**热状态主导、代码世代全排除**（9/30 原始 12700 APK 同字节复测 4808 vs 当时 2102，电池 41°C/GPU capped 277MHz；App 三代×mpv 四代×libplacebo 两代同热一致）。唯一残余：冷机 GPU 需求 586 vs 9/28 记录 415MHz 的差异（快速路径效益或 DVFS 漂移），冷机复测已排定。详见 `archives/experiments/android-4k60-dropload-attribution-20261002.md`。
- **不可行项（维持现状即终态）**：3.1 deleteAsync（LYA 无 `EGL_ANDROID_native_fence_sync`，9/26 已证）、maxImages 提升（OMX.hisi 拒绝，本轮实证）、撤 `get_req_frames` hack（依赖前两者）。低价值项详见 conversation `architecture-review-remediation-20260930.md` 遗留复核节。
- **事实源与范围**：本文件是任务状态，`archives/README.md` 是主题导航，`archives/conversations/android-hdr-dv-display-plan-20260922.md` 顶部 `Current State` 是当前 Android 主题上下文；`archives/conversations/architecture-review-remediation-20260930.md` 是整改主题上下文；`archives/experiments/android-private-tmp-handoff-20260928.md` 是临时工作树路径及补丁入口。以上均为快照，接手后先重新读 Git/设备状态。
- **代码状态（三仓库单线格局）**：① Goodwu/media-kit `main` = 原修复分支全部工作 + 上游 main 236 提交合并（`a886f556`，五项实机验收通过）；② Goodwu/mpv `media-kit/android`（发布 tag `media-kit-v2026.10`→`5f9ddf1777`）；③ FFmpeg `feature/android-mediacodec-p5-rpu`（`fff3ee7`）、libplacebo `optimize/dovi-linear-decode`（`c9fd879`）各单分支。废弃分支均以 `archive/*-202609` tag 归档（全清单见 `archives/experiments/android-mpv-fork-branch-consolidation-20260930.md` 追加节）。
- **mpv fork 上游策略（2026-09-30 定）**：**跟发布版不跟 master**。已核实 master 未包含我们任何一项修复；master 的 vo_gpu_next 1029 行 libplacebo v7 迁移与 1100+ 行本地改动正面冲突。下次同步：等 v0.42 发布 → merge-tree 试评估（重点 hwdec API 与 vo_gpu_next dovi 路径）→ P5 五项回归后打新发布 tag；期间个别修复按需 cherry-pick；FFmpeg 安全修复走 CVE 按需 cherry-pick 单独机制。
- **P5 修复要点**：华为硬解输出为 Main10 10-bit 布局（AHB 0x325，驱动 Y2Y 采样按 /1020 归一化，`archives/experiments/android-p5-buffer-bitdepth-mystery-20260930.md`），dovi 域按 code/1023 解释 → 1023/1020 缩放偏色；修复为 dovi 元数据就地重标定（mpv fork，k=1023/1020），数值验收 (47,50,70)/(50,19,58)/65535 ≤100。教训：读回装置旧前缀 FFmpeg 需 `debug.media_kit.p5_rpu_probe=2`；产品链接必须用 fff3ee7 世代 libavcodec（持久副本 `~/src/media-kit-build/product-ffmpeg-lib/`），误链 mkp4prefix 旧版会复演 `direct=0`。详见 `archives/experiments/android-p5-mediacodec-color-fix-20260930.md`。
- **环境**：ADB 可用（设备 `3EP7N18C28016072` / LYA-AL00），每轮结束恢复原 12492、自动亮度、熄屏。**持久化资产（2026-09-30 起；/tmp 副本重启即弃，以下为权威本地副本）**：`~/src/mpv`（mpv fork 完整工作树，`media-kit/android` tip）；`~/src/media-kit-build/`（`mkp4prefix` 构建前缀、`product-ffmpeg-lib` fff3ee7 libavcodec、`jars/` 发布 JAR、`apks/` 验收包、`evidence/` 设备日志、`sources/` 测试源视频、`scripts/` 重链脚本 `mk-relink-product.sh` 等——轮次脚本权威版本在仓库 `tool/`）。读回构建链：mpv 源码 `~/src/mpv` + 前缀 `~/src/media-kit-build/mkp4prefix` + 手工链接需补 `-lc++_shared`；APK 直改重签（lib store + zipalign -p 4096 + debug keystore）。JDK17 构建、`ORG_GRADLE_PROJECT_mediaKitLocalArm64Jar` 注入 JAR 的正式流程不变；media-kit 主仓推送遇挂起时绕过 osxkeychain：`git -c credential.helper= -c credential.helper='!gh auth git-credential' push …`。可复用轮次/构建/分析脚本已收编仓库 `tool/`（使用说明 `tool/README.md`）。

## 当前任务

- [ ] Android HDR10 / DV P8.4 显示与原生 HDR 首帧闭环
  - status: in_progress
  - context: archives/conversations/android-hdr-dv-display-plan-20260922.md
  - acceptance: 固定素材和设备能力，核对 HDR10 PQ、P8.4 HLG 的真实后端、Surface 格式、系统合成、连续全屏画面及 SDR 复位；P8.4 无 HLG 路径与原生 DV 能力单独说明。原生 HDR 从触摸到视频内容小于2秒、争取1秒，补冷/热、重入与输出切换。最高亮度只用于短时人工观察，结束立即恢复自动亮度并熄屏。
  - 素材：P5→PQ 输出/首帧/性能用 `~/Downloads/test-clips/Mystery Box Dolby Vision Profile 5.mp4`（SHA-256 `3e610d3b…`，HEVC Main10 4K60 DV P5/RPU，98.944s）；Glass P5 4K59.94（SHA-256 `afb24b77…`）保留作片尾紫屏定点复现。
  - latest: **四仓库归一后播放矩阵六轮全部通过（2026-09-30，12703–12708）**：P5/P8.4/HDR10 × SDR/HDR，全片 EOS（P8.4 为 5 分钟观察窗），输出路径全部符合预期，零渲染错误、资源闭合全对等。证据 `archives/experiments/android-playback-matrix-12703-12708-20260930.md`。第二台设备（Redmi Note 5A，骁龙 425）同矩阵不可行并按用户要求中断（OMX HEVC 不支持 4K、屏幕无 HDR）；第三台设备（Mi Note 3，骁龙 660）4K Main10 硬解/直采/EOS 通过但展示链路 VO 掉帧 84%，EOS 尾帧一次取图失败且回退未触发（设备差异观察项，原因未查）——均见同文件追加节。此前 HDR10、P8.4 全屏画质和流畅性已获用户认可；首帧读回 P8.4 HLG 0.623–0.676s、HDR10 PQ 0.630–0.653s（Surface 读回，非面板光学）。
  - next: 扩充原生 HDR 冷/热、重入、连续帧及 SDR 复位证据；P5 输出和首帧单列于 P1，不以 HDR10/P8.4 代替；P8.4 全片 EOS 按需补跑。
  - temp_reconcile: `/private/tmp/media-kit-firstframe-sdr-20260927` 的5个App/plugin文件、`media-kit-firstframe-mix-20260927` 的9个修改及868个删除状态项尚未与当前代码逐项比较；后者只保存了修改补丁，删除项不可直接重放。先隔离比较真正的首帧/输出行为，再针对SDR、HDR10、P8.4冷/热打开与输出切换做相应实机回归；记录冗余或迁移结论后删除工作树。不要把大量删除当成产品清理。

- [ ] HDR 能力查询、路由执行与报告 API + 设备私有回退子包（PiliPlusX 需求，Phase 1 Android）
  - status: in_progress
  - context: archives/conversations/android-hdr-auto-output-20261002.md；需求 docs/requirements/android-hdr-auto-output.md（v3）；计划 docs/requirements/android-hdr-auto-output-plan.md（S0–S13）；参考实现 media_kit_hdr_lab；实机基线 archives/experiments/android-playback-matrix-12703-12708-20260930.md
  - acceptance: 需求 v3 验收 A1–A8。要点：开播前预测与执行同源；按"源描述 + 策略候选 + 偏好 + 成熟度门禁"选路由，默认先 HDR 输出再 tone-map、HDR 中直出优先；运行时沿候选列表降级，最终 tone-map 继续播放并发事件（P5 管线缺失除外）；路由、候选与状态报告给 App；`HdrVideoSession`/`HdrVideo` 支持控制器替换且全屏跟随；LYA 私有回退做成默认关闭、只读门禁的独立子包；PiliPlusX 只保留策略偏好，无设备代码、无平台决策代码。
  - latest: **Phase 1 全部完成（2026-10-02，S0–S13）**。S0–S10 详见验收记录 `archives/experiments/android-hdr-auto-output-acceptance-20261002.md`；S11 发布 media_kit_video 1.3.1+1 + vendor 子包 1.0.0+1（main 已推送 GitHub 420fba3e）；S12 PiliPlusX 接入（其仓提交 f7470fd09/2995115399/7721a1e92，分支 fix/darwin-video-output-rebuild-barrier）：predict 选档门 + HdrVideoSession 挂载 + 事件/报告展示，A7 实机 BV1vY4y1N7TY P8.4 全链（预测门→HLG 直出 verified→SF HLG 层→拖拽 seek 正常）+ SDR 信息流 sdrDirect ✓；接入首轮抓到 open/视图/输出三方循环等待死锁并修复（先挂后开）。A8 红线 V1 审查 PASS（lib/android 无设备判断）。S13 收尾完成：hdr_lab 旧适配层六文件标记 MIGRATED、TASKS/conversation 终态、后续任务登记。**V1 审核中修复的缺陷**：S5 复核时序（video-params 有界轮询）、S12 接入死锁。**待用户**：人工观察（a1-hlg-gate-85 HLG 直出 / a6-reshape RPU 重建 PQ）确认 P8.4×convert 与 HLG×direct 升 verified（需求第 6 节与常量表同步）；R3.1 no-HLG 开播前跳过不发 Degraded 的口径文字。
  - next: （已结案待人工观察项确认后完全关闭）后续任务见 Next 区三条登记。

## Next（近期候选，最多 10 条）

- [ ] HDR 能力路由后续三项（Phase 1 收尾登记，2026-10-02）
  - status: planned
  - context: archives/conversations/android-hdr-auto-output-20261002.md
  - acceptance: ①原生 DV 呈现（R7 预留项，FFmpeg `video/dolby-vision`+profile 打开解码器/mpv 路由/media-kit 三方，等 DV 设备到位）；②动态元数据重建扩展（HDR Vivid/HDR10+）；③`HdrCapabilities.query` 无 Player 入口 + PiliPlusX app 内 seek 验证。
  - latest: **③ 完成（2026-10-02）**：query player 改可选（186/186；media-kit 1c49c684）；PiliPlusX 删手工兜底走单一入口（2ce821d4c，81/81，构建 46441b40）；实机选档门复跑照常；seek 不变量维持进度条拖拽证据（长按钩子留人工路径）。**② fork 暴露完成（mpv `0f7e6bec32`）**：compat id/EL/ hdr-vivid 三属性 + 构建零错误；剩余：fork JAR/CI → 库消费 → 设备事实轮。①阻塞待 DV 设备。
  - next: ② 剩余步骤按用户排期；①需 DV 设备。

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
  - temp_reconcile: `/private/tmp/media-kit-mpv-p5-replay-2214`（7文件）、`media-kit-mpv-p84-rebuild-2213`（6文件）、`media-kit-mpv-upstream-reader3`（4文件）均是未提交的旧mpv生命周期实验。逐项比对当前产品输出与现有复现记录；若保留修正，先跑双视图B存活、失败重试、Home返回、直接Engine销毁及资源闭合；无独有修正的目录在记录结论后删除。

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
