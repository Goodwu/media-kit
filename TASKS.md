# TASKS.md

任务事实源：这里只保留当前状态、验收门槛和下一步。清理前的完整任务台账快照：`archives/experiments/tasks-ledger-snapshot-20260927.md`、`archives/experiments/tasks-ledger-snapshot-20261002.md`、`archives/experiments/tasks-ledger-snapshot-20261010.md`（2026-10-10 精简前全文快照）；按各项 `context` 查看持续更新的依据。

**路径映射（2026-10-05 起）**：`archives/experiments/` 已整体迁移至独立仓库 **`~/src/media-kit-experiments`**（实验记录/证据/交接/索引全量归档）。本文件及 conversations 中所有 `archives/experiments/` 前缀路径均映射到该库根目录。**主库历史已剥离该路径（2026-10-06，main 51ef66cc→ee28accd，树零变化）**：剥离前提交历史不再在主库，查备份仓 `Goodwu/media-kit-history-archive`（分支 `pre-strip-20261006`）；旧哈希换算用 `~/src/media-kit-build/history-strip-20261006/commit-map.json`。

## 接手快照（2026-10-10 更新；换 agent 从这里开始）

- **事实源与范围**：本文件是任务状态；`archives/README.md` 是主题导航。主题上下文（各 conversation 顶部 Current State）：Android HDR/P5 主线 `archives/conversations/android-hdr-dv-display-plan-20260922.md`；LG/marble 线 `archives/conversations/lg-h870ds-hdr-demo-20261004.md`；整改主题 `archives/conversations/architecture-review-remediation-20260930.md`。LG followup 单一计划=`docs/plans/lg-p84-hdr-followup-plan-20261009.md`（v4.1，全部出清，触发式候选/重开条件在案）。接手后先重读 Git/设备状态，快照仅是入口。
- **代码状态（四仓库，2026-10-10）**：① media-kit `main` tip `788fc3b2` 已推送（followup v4.1 收口/G1/C3/回归轮收口+测试构建默认正式化+台账精简并入+experiments 存档入账）。② mpv fork `media-kit/android` tip `c11426b67a` 已推送（native DV bridge 内省/surfacetexture 直连/demux hvcc 补全/Vulkan Properties2/render-mode opt-in 五提交）。③ FFmpeg 分支 `lg-p84-d1-vui-fix-20261010`（`d4bb79394b`）已推送；Kazumi HLS 广告补丁不入库（留构建树+genbump 溯源，prefix 重建须有意识携带）；configure hack 不正式化（G1 裁决，清空 dirty=常态机制，字节门验证窗口保持两树清空）。④ libplacebo 钉定 fork `c9fd879`（+external_yuv 补丁，经构建仓 buildscripts/deps 消费）。发布链钉定 v2026.012=mpv `d24c59905b`+FFmpeg `b4d2ea4` 世代；本地测试构建已整体切 genbump prefix 代际（2026-10-10 起，见环境条）。
- **环境与设备**：ADB 双机——**marble（Redmi 23049RAD8C，dede0cd2，API 35/HyperOS）现役 DV/HDR 实机**（displayHdrTypes [1,2,3,4]、c2.dolby.decoder.hevc 声明 profiles 32/16/256、bridge api 1；素材 p5 dacfd045 / p84 7626cac2 已推送核验，2026-10-10 晚补推 p5-mystery-box（3e610d3b）/hdr10-full（e4f869b1）并建 p84-full 规范名副本（7626cac2 同字节）；现装包=r30g（3968e6fc，2026-10-10 21:53 双机回归后还原并字节核验，自动亮度/熄屏已恢复））；LYA-AL00（3EP7N18C28016072）备用。持久化资产：`~/src/mpv`（fork 工作树）；`~/src/media-kit-build/`（jars/apks/evidence/scripts、`lg-api24/` 管线、`LG-DEVICE-LOGCAT-PROTOCOL.md`——本 ROM 交互式 logcat 为空必须 exec-out，设备侧 md5sum 可用/sha256sum 不存在、MKS_DEFINES_OVERRIDE=合并语义、槽位换 .so 须 store+zipalign -p 4096）；`product-ffmpeg-lib/`（fff3ee7 世代持久副本）；整改产品 JAR `media-kit-remediation-final-product.jar`。构建：JDK17（`JAVA_HOME=/opt/homebrew/opt/openjdk@17/...`，勿改全局 Flutter 配置）；`ORG_GRADLE_PROJECT_mediaKitLocalArm64Jar` 为 gradle 正式本地 JAR 注入通道。**测试版构建默认（2026-10-10 裁决，全文在 AGENTS.local.md）**：Android 测试包一律 `tool/build-android-test.sh`（最新源码 ninja→JAR→APK 三步自动），钉定下载 JAR 仅用于发布构建与发布链回归。push 一律逐次请示（osxkeychain 挂起时用 `git -c credential.helper= -c credential.helper='!gh auth git-credential' push`）。2026-10-10 四库当前分支 upstream 已设齐，分支内裸 `git push` 可直达：mpv=origin/media-kit/android（原 fetch refspec 钉死旧分支，已修为全分支并补全跟踪引用）、FFmpeg=origin/lg-p84-d1-vui-fix-20261010、PiliPlusX=personal/fix/darwin-video-output-rebuild-barrier（origin=上游 cnctem 无写权限，勿改指向）、flutter-ohos=github/ohos/media-kit-patches（origin=gitcode 源）。
- **LG/marble 工作线已收口（2026-10-10）**：P8.4 HLG"色彩淡"根因=显示链按 SDR 方式处理 PQ 码值（面板 PQ 能力在，RGB GLES 链无 HDR 呈现路径）；修复=YUV config49 NV12 HWC 视频层+逐 buffer COLOR_METADATA+BT.2020 NCL 打包（HLG→PQ），人工验收通过；P5 直通默认化（dvP5×nativeDV verified）；A 组三格成熟度提升；followup 计划全部出清。详见 Recently Done 对应条目与 followup 计划。
- **双设备最新代码回归轮通过（2026-10-10 晚，LYA+marble 六轮全绿）**：main `a072e964` + mpv HEAD `c11426b67a`（含 5 未推送提交，实际重编译——12:01 genbump2 JAR 缺下午提交内容，"18:02 一致"验证未完成链接）+ FFmpeg `d4bb79394b` 重建 JAR（槽 5f8fc04c，链接字节级可复现）；**dvP5/dvP84×nativeDV 在 marble 默认策略（无 GATE）首次真机直达**（P5 全片丢帧 1 次，直通流畅再证）；LYA 三路由全 verified（P5 reshape→PQ/HDR10 baseLayerDirect/P84 HLG 直出，DV=false 预期）；render_failures/fatal 恒 0。报告：experiments `regression-two-device-latest-20261010.md`（4c65217）；证据本机 `~/src/media-kit-build/evidence/regression-two-device-20261010/`；conversation `archives/conversations/regression-two-device-20261010.md`。
- **设备待办两项（2026-10-10 用户指示入待办，非回归失败，排查待用户裁决）**：①LYA P5 reshape→PQ 稳态 VO 丢帧偏多且轮间差异大（发布 JAR 稳态 8/60s vs 最新 30/60s、复测轮 t≈40–60s 突发 329；decoder 恒 0——4K59.94 gpu-next 重建在 Kirin 980 吞吐边缘，是否 5 个 mpv 新提交加剧未定论）；②marble post-EOS BACK 不触发 dispose（app 侧零日志，三次 P5 全片轮复现含最新构建；同机 pre-EOS 正常、LYA post-EOS 正常——签名 HyperOS API35 × post-EOS 状态）。证据同上目录（lya2-p5/lya2-p5b/marble2-p5 device.log 帧计数序列）。
- **不可行项（维持现状即终态）**：3.1 deleteAsync（无 `EGL_ANDROID_native_fence_sync`）、maxImages 提升（OMX.hisi 拒绝）、撤 `get_req_frames` hack（依赖前两者）；低价值项见整改 conversation 遗留复核节。
- **mpv fork 上游策略（2026-09-30 定）**：跟发布版不跟 master（master 1029 行 libplacebo v7 迁移正面冲突）；等 v0.42 发布→merge-tree 评估（hwdec API+vo_gpu_next dovi 路径）→P5 五项回归→新发布 tag；期间按需 cherry-pick；FFmpeg 安全修复走 CVE cherry-pick 单独机制。
- **P5 修复要点**：华为硬解输出 Main10 10-bit 布局（AHB 0x325），dovi 域按 code/1023 解释→1023/1020 缩放偏色；修复=dovi 元数据就地重标定（mpv fork，k=1023/1020）。教训：误链旧世代 libavcodec 复演 `direct=0`（发布链保持钉定即为此）；读回调试 `debug.media_kit.p5_rpu_probe=2`。
- **历史哈希换算**：主库 2026-10-06 剥离 `archives/experiments/`（main `51ef66cc`→`ee28accd`，tip 树零变化）；旧哈希查 `~/src/media-kit-build/history-strip-20261006/commit-map.json`，旧对象 fetch `Goodwu/media-kit-history-archive`（branch `pre-strip-20261006`）。
- **OHOS 现状**：构建规范化落地（CI 三跑绿+双路径字节一致+镜像切换等价实证）；本地 SDK 固定 `~/src/flutter-ohos`（OHOS 操作一律在此）；模拟器可视播放已打通（HCPP 直通+sw 桥，2026-10-07），真机生命周期验收 blocked 待设备；patch 分支 rebase 上游 tip 首演待办；experiments 库远端=github.com/Goodwu/media-kit-experiments（master 已推送同步 @ f599d27，工作树清空——含回归轮报告 4c65217 与存档收口 f599d27：10-08 三轮证据（EGL 格式探针/real-pq-route-lock PAUSED/visual278 owner+session-only）、D1 MKS VUI harness 归档、台账 20261010 快照、handoff logcat 协议）。

## 当前任务

- [ ] 共享 gpu-next/libplacebo 渲染核心关闭 macOS DV P5 偏色
  - status: in_progress
  - context: docs/requirements/shared-hdr-rendering.md；archives/conversations/macos-shared-hdr-fix-20261005.md（r4 已审切片归档）；PiliPlusX archives/conversations/player-architecture-remediation.md
  - latest: 已审 r4 源码切片（33 交付/13 验证节点，独立 V1/API+V2 审核通过）经 codex/macos-shared-hdr-fix（252c5851）提交并同源并入 main 75743f5c（分支已归一删除）；PiliPlusX 最终候选完成源码/产物绑定与 mpv 0.41 双架构版本、闭包、加载、签名与共享后端门禁。**工作区 v4 前沿（未提交）**：双 Render API 前端+约 2300 行共享 renderer+native adapter，P5 v2 十文件冻结独立复审限定 PASS；真实 CGL 空帧 1500 轮 PASS；真实 P5 出帧（VT[p010] 4K59.94、PTS 推进）——RECT 纹理 shader 编译失败已由 v3 共享 RECT→normalized2D GPU 导入修复，但诊断目标/实播仍 Dropped（不能作颜色或流畅验收）；v4 补 scissor/sRGB 保护和双平面失败测试；Swift 共享桥接候选 opt-in（固定 64/28 字节 ABI、headroom 参考域 snapshot+epoch——headroom 不可视为绝对 nit 校准、成功诊断门禁、锁外 paused redraw）；pool 取 current+占用改锁内 atomic registry claim（所有 early-return 与 completion 归还）独立复审中；Intel 同 v4 源码独立构建成功（未 lipo/未打包新 App）；macOS 桥接失败帧不发布修复已获 V2。**分项**：P5 颜色接受；HDR 输出证据未闭合；P5/HLG/正常 4K 存在卡顿反馈（性能优化留后续专题，不得称完整 DV/HDR 性能修复）；生产 App 尚未重建、错误注入与恢复未验收。不得将参考/PoC、编译通过或 marker 门禁视为产品完成。
  - acceptance: 库内共享P5/HDR色彩核心、真实backend能力门禁、正确硬解导入和一次目标转换；同源同PTS用户颜色/亮度接受，4K60流畅、最终生命周期矩阵和双架构加载签名通过。Pili不补平台色彩实现，Android已通过路径需回归，默认启用需V2审核；未提交推送。

- [ ] Android HDR10 / DV P8.4 显示与原生 HDR 首帧闭环
  - status: in_progress
  - context: archives/conversations/android-hdr-dv-display-plan-20260922.md
  - acceptance: 固定素材和设备能力，核对 HDR10 PQ、P8.4 HLG 的真实后端、Surface 格式、系统合成、连续全屏画面及 SDR 复位；P8.4 无 HLG 路径与原生 DV 能力单独说明。原生 HDR 从触摸到视频内容小于2秒、争取1秒，补冷/热、重入与输出切换。最高亮度只用于短时人工观察，结束立即恢复自动亮度并熄屏。
  - 素材：P5→PQ 输出/首帧/性能用 `~/Downloads/test-clips/Mystery Box Dolby Vision Profile 5.mp4`（SHA-256 `3e610d3b…`，HEVC Main10 4K60 DV P5/RPU，98.944s）；Glass P5 4K59.94（SHA-256 `afb24b77…`）保留作片尾紫屏定点复现。
  - latest: **四仓库归一后播放矩阵六轮全部通过（2026-09-30，12703–12708）**：P5/P8.4/HDR10 × SDR/HDR，全片 EOS（P8.4 为 5 分钟观察窗），输出路径全部符合预期，零渲染错误、资源闭合全对等。证据 `archives/experiments/android-playback-matrix-12703-12708-20260930.md`。第二台设备（Redmi Note 5A，骁龙 425）同矩阵不可行并按用户要求中断（OMX HEVC 不支持 4K、屏幕无 HDR）；第三台设备（Mi Note 3，骁龙 660）4K Main10 硬解/直采/EOS 通过但展示链路 VO 掉帧 84%，EOS 尾帧一次取图失败且回退未触发（设备差异观察项，原因未查）——均见同文件追加节。此前 HDR10、P8.4 全屏画质和流畅性已获用户认可；首帧读回 P8.4 HLG 0.623–0.676s、HDR10 PQ 0.630–0.653s（Surface 读回，非面板光学）。
  - next: 扩充原生 HDR 冷/热、重入、连续帧及 SDR 复位证据；P5 输出和首帧单列于 P1，不以 HDR10/P8.4 代替；P8.4 全片 EOS 按需补跑。可与 4K60 冷机复测（2026-10-02 归因轮唯一残余）合并同一 LYA 会话。
  - latest+ (2026-10-03 凌晨，新 JAR b4d2ea4 世代)：**SDR 复位 ✓**（HDR 轮后 sdrDirect texture 路由、无 HDR 残留、两轮一致）；**冷启动首帧 ×3**（tap→trigger→decoder 事实 verified ~0.6s→路由 applied，路径 ext:lya-pq + SF 读回 BT2020_PQ）；热重入部分（BACK+tap 未触发二次 open，自动化限制；A4 九轮语义证据在旧世代）；系统化冷/热百分位与 4K60 冷机复测顺延（设备整夜解码热负载）。证据 `archives/experiments/android-ffmpeg-p5-rpu-b4d2ea4-verify-20261003.md` app 通道节。
  - next+ (更新): 冷/热百分位矩阵与 4K60 冷机复测待设备冷却后补（可与下次 LYA 会话合并）；重入复跑待 PiliPlusX 长按钩子或人工路径。

## Next（近期候选，最多 10 条）

- [ ] 修复 macOS modern mpv 销毁时未释放 render context 的崩溃
  - status: in_progress（代码修复与隔离验证完成；产品链五场景验证交接中）
  - context: archives/conversations/native-output-rebuild-20260920.md；PiliPlusX 完整交接入口 `/Users/wuweiwei1/src/PiliPlusX/archives/handoffs/macos-player-20261005.md`
  - acceptance: 同一控制器的并发 dispose 共用完成屏障；Player 销毁前完成 native output/render context 释放，dispose 后不再写 active notifier。用 modern mpv 实际播放后退出、快速重入和输出重建，均无 `mpv_render_context_free() not called` abort。
  - latest: darwin wakeup broker/创建销毁仲裁/失败重试 V2 通过；W0 隔离验证完成；工作区代码已入库（2026-10-05，main 75743f5c 含 darwin 全套）；PiliPlusX 修复/交接已推送 58bc84d39（2026-10-10 补推 68edf0ec9 后三笔：依赖钉定等价重写同步/构建脚本归档/tasks 记录）；Release bootstrap 矩阵带限制 PASS（PASS_RELEASE_BOOTSTRAP_MATRIX_WITH_LIMITS）。修复空排队误转 false 的无限输出重建已 V1 PASS（固定 BV 15 秒窗 394 帧出图）。
  - next: 五场景（a 播放≥10s 后 Cmd+Q 有序退出；b 退出→立即重开再播 ×3；c 播放中 seek ≥10 次；d 全屏切换/窗口缩放 ×3；e HDR 素材 ≥5 分钟）由具备 UI 操作能力的执行者或人工逐场景判定（两轮 Verifier UI 自动化被终止，自动化路线不通）；全过则收口并解锁 macOS HDR Phase 2 需求文档。

- [ ] Android native output / 双视图生命周期回归
  - status: queued
  - context: archives/conversations/android-hdr-dv-display-plan-20260922.md
  - acceptance: Surface 重建、Home→前台、退出/重入、oldA→newB 交错和失败重试时，播放器位置与持续可见帧正确，资源最终释放；晚到 Create、Release ACK 丢失及 engine detach 有明确 owner/屏障，不以构建或单次 EOS 代替生命周期验收。
  - latest: P8.4/HDR10/SDR 的 Home→返回、双视图存活 B 回退、释放/绑定失败重试已有实机可见画面证据（12473–12477、12491/12492 各轮）。owner broker 第一步落地——P5 Texture 播放中 destroy 确定性 SIGSEGV 根因（release NativeCallable wakeup 蹦床随 isolate 失效）已修复（12653 播放中销毁 4/4 零崩溃、12654 无回归），无视频裸 Player 终态已证（12647）；broker 现覆盖 wakeup 回调清空与视频输出释放。
  - next: mpv 终止与音频-only 宿主接线是下一增量；核验清理中再次点击、失败重试和全屏组合；通用失败 disposal/global-ref 定量闭合、连续可见帧与 mpv WID 回读；P5 专属项已归 P3 完成。

- [ ] player-set-shuffle(-consecutive) 概率性 flaky 测试处置（上游同源）
  - status: in_progress（Native 修复已推送待 CI 验证；Web 侧机制另立待排期）
  - context: archives/experiments/ci-fix-20261002.md（终验节：机制与证据链）
  - acceptance: 随机洗牌未变序时测试不再误报（本地无法跑 player 套件，需 CI run 验证）；Web 侧处置定案（本地改测试 vs 提报上游）。
  - latest: 机制=setShuffle 状态门控（false→true 跃迁才洗牌），单次 4 项随机排列 1/24 概率回原序被 `_DistinctStream` 吞事件；Native 修复=两测试列表扩至 10 项（碰撞 1/10!≈2.8e-7），CI Linux/macOS 过。Web 失败非碰撞——WebPlayer 自带"洗到不同序为止"守卫，疑似 synchronized 锁等待×网络样片（5→10 项可能加重），失败签名一致（仅初始事件后 Stream closed）。
  - next: Web 侧三选项排期：①测试改非网络 Media；②查 WebPlayer 锁与 open 网络加载交互；③提报上游。Native 修复保留。

- [ ] FFmpeg P5 RPU T3 单帧位移定性（b4d2ea4 世代已知项）
  - status: planned
  - context: archives/experiments/android-ffmpeg-p5-rpu-b4d2ea4-verify-20261003.md（T3 行：机制与证据链）
  - acceptance: ES 级定位该切换帧 RPU 的归属（输入侧 packet 归属 vs 输出侧 pts 源 vs 上游解析差异），给出定性结论与必要时修复；静态元数据下视觉零影响已确认。
  - latest: 300 帧对齐比对 298/300 DOVI_METADATA 逐字节一致；唯一单帧元数据切换 SW(hevc) pts=81、MC(hevc_mediacodec+fork) pts=92；精确 pts 匹配器（mediacodec_dovi.c:360-372）下顺序错位假说排除——两路径对该 RPU 的 AU 归属判定不一致（FFmpeg 任务作者域）。
  - next: 排期后提取 ES 分析切换 RPU NAL 的 AU 边界归属；对照上游 hevc 解析器与 fork 输入侧 parse 的归属差异。

- [ ] PiliPlusX 性能优先/画质优先开关（HDR 路由策略预设）
  - status: planned（2026-10-02 用户登记，暂不实施）
  - context: archives/conversations/android-hdr-auto-output-20261002.md（设计评估记录节）
  - acceptance: 库侧两个命名预设映射现有 HdrRoutingPolicy（性能优先=默认偏好序直出优先+不放宽 experimental 门禁；画质优先=dvP84 reshape 置顶+allowExperimental）；PiliPlusX 只选预设不写平台/设备决策（A8 红线）；运行中可切换（会话原位重建，A5 已验证）；文档显式声明 P5 豁免（必须 reshape）与 HDR10+/HDR Vivid 暂为空操作；不做固定抽帧（自适应 framedrop 已覆盖）。
  - next: 用户排期后立项：库侧两预设+需求文档/dartdoc 补记+PiliPlusX 设置项与会话接线。

- [ ] HDR 能力路由 ②完整目标：动态元数据重建扩展（HDR Vivid/HDR10+）
  - status: planned
  - context: archives/conversations/android-hdr-auto-output-20261002.md
  - acceptance: demuxer 级 SEI 探测绕开 mediacodec 对 CUVA side data 的剥离（需求第 8 节已知限制）；Vivid/HDR10+ 元数据重建链路与真实样片实机验收。
  - latest: 2026-10-10 重组——原"后续三项"中③（HdrCapabilities.query 无 Player 入口+PiliPlusX 单一入口）与②fork 暴露（compat-id/el/hdr-vivid+dovi-p5-pipeline 只读属性 d24c59905b）+方案 B 探针消费链均已交付（2026-10-02 实机 8 轮）；①原生 DV 呈现已由 LG/marble nativeDV 工作线交付（dvP5/dvP84×nativeDV 均 verified，A 组 2026-10-10），该项关闭。
  - next: Vivid/HDR10+ 真实样片收编（先 ffprobe 核对容器记录）与实施排期。

- [ ] macOS（darwin）HDR 能力路由支持（Phase 2）
  - status: planned（前置=上方 macOS render context 崩溃五场景验收，否则重打包复演 final11 SIGABRT）
  - context: docs/requirements/android-hdr-auto-output.md R6（darwin：三事实交集门禁、final24 运行时禁止降档，另立需求）；PiliPlusX final11 崩溃记录
  - acceptance: 另立 darwin 需求文档（EDR/三事实门禁/final24 禁降档）；会话 API 在 darwin 的路由执行与报告；同源同 PTS 亮度对照验收。
  - next: 前置任务收口后立需求文档。

- [ ] OHOS HDR 能力路由支持（Phase 2）
  - status: planned
  - context: docs/requirements/android-hdr-auto-output.md R6（OHOS：VO 动态色彩契约单层写入，另立需求）；archives/conversations/android-hdr-auto-output-20261002.md
  - acceptance: 另立 OHOS 需求文档（会话 API 在 OHOS 的路由执行与报告；VO 动态色彩契约单层写入语义）；PiliPlusX 侧 useHCPP/native-surface 候选路径迁移进会话；实机验收另定设备。
  - next: 先立需求文档再排实施；当前 OHOS 走 R2.5 透传+unsupportedPlatform。

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

- [x] LG P8.4 色彩优化：HLG 在 HDR 屏上的正确呈现：done（2026-10-09 核心人工验收通过 + 2026-10-10 followup 计划 v4.1 全出清收口）。根因=LG 显示链按 SDR 方式处理 PQ 码值（面板 PQ 能力在，RGB GLES 链无 HDR 呈现路径，dataspace 通道不可修复）；修复=YUV config49 NV12 HWC 视频层（SF 实锤 0x7FA30C04）+逐 buffer COLOR_METADATA（primaries=9/range=1/transfer=16）+BT.2020 NCL 打包（HLG→PQ target-peak=1000），用户分项验收"色彩好、亮度好、流畅度好"；genbump FFmpeg prefix 代际升级（修复跨代 avformat token 崩溃）后三内容类型（HDR10/P5/P8.4）30s 人验全过、P5 原文件直通恢复并默认化（dvP5×nativeDV→verified）、A 组三格成熟度提升（dvP84×nativeDV/hdr10×convert/hdr10×reshape）。构建教训入档：字节级符号守门必须对真实链接输入做、静态符号一致≠运行期一致（check_library_versions 版本守卫）；设备协议与构建工具语义见 `~/src/media-kit-build/lg-api24/LG-DEVICE-LOGCAT-PROTOCOL.md`。残余=触发式候选（B 线 10bit/B附/E 线、C0/C3 带重开条件、G1 维持现状）存档 followup 计划；push 残余：mpv 5 提交+media-kit main 3 提交待授权。context: `docs/plans/lg-p84-hdr-followup-plan-20261009.md`、`archives/conversations/lg-h870ds-hdr-demo-20261004.md`
- [x] LG-H870DS API24 HDR 能力检测与 hdr_lab 移植：done（2026-10-10 收口；LG→marble 双设备工作线）。全内容类型（SDR/HDR10/P8.4/P5/nativeDV）实机解码/输出路由/画质验收通过；P8.4 nativeDV 直通链人工终验通过（2026-10-07，LG 四信令穷尽失败在 marble 翻案，FFmpeg 门 0x100 零改动可用）；LG nativeDV 工作线全闭环（R26b 遗留 2026-10-07 用户确认关闭）；失败回退/严格退出/Surface 恢复/全屏/ACK 四分支各子项实机证据在案。残余仅"现代 Vulkan 设备回归"（移入后续低优先级）。context: `archives/conversations/lg-h870ds-hdr-demo-20261004.md`；handoff `~/src/media-kit-experiments/lg-hdr-agent-handoff-20261005.md`、evidence-index 同库（5159 文件）
- [x] 清理不再使用的构建中间产物：done（2026-10-05，清单内缓存/编译目录全删并核验；保留产物、源码、证据与未完成实验）。context: `archives/conversations/intermediate-cleanup-20261005.md`
- [x] FFmpeg P5 RPU 整改版（`b4d2ea4ffb`）按测试计划验证与采纳：done（2026-10-03）。T1/T2/T5(delay_flush)/T6×4/T7/T8(ABAB 不劣化)/T9 双形态/T11/T12 全过，发布链 v2026.012 落地（mpv tag d24c59905b 同点、GitHub release JAR c3bab5fc…、build.gradle 钉定、CI 标识串、libs CHANGELOG、product-ffmpeg-lib 刷新）；T3 单帧位移单列 Next。context: `archives/experiments/android-ffmpeg-p5-rpu-b4d2ea4-verify-20261003.md`
- [x] 全平台会话逻辑一致性审计与未实现平台显式 stub：closed_by_user_decision（2026-10-03 用户确认维持 R2.5 现状）。全部非 Android 平台统一 unsupportedPlatform 报告+透传，无静默假透传（平台×现状表带文件:行号证据见 conversation 审计节）；可选小项=web 桩抛错类型统一（随手）。context: `archives/conversations/android-hdr-auto-output-20261002.md`
- [x] Windows package tests 原生崩溃 + mpv-dev 现代化：done（2026-10-03）。首崩为 player-platform 销毁时 WASAPI 热插拔 COM 回调注销；旧/新夹具均复现，Windows terminate_destroy 期间成对持有 MTA usage cookie 后两组均 81 passed / 15 skipped。夹具钉定 shinchiro 20261002/3186d369f9 + SHA-256，保留 awaited 屏障、全部测试及门禁。全平台 run 64 + OHOS 37 success，失败集合从 run 60 的 Windows/Web/Linux 三项变为空；Web/Linux 改善另归 main f6665609 shuffle 修改。证据：`archives/experiments/windows-ci-mpv-ab-20261003.md`。远期 fork win32 构建件就位后替换钉定。

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

## 后续低优先级

- [ ] LG API24 P5 / HDR10 SDR tone-map 卡顿
  - priority: low（2026-10-04 用户明确后移，R10 HDR10 tone-map 同样后移；PQ 直通路验收后仅为回退路径问题）
  - status: deferred
  - context: archives/conversations/lg-h870ds-hdr-demo-20261004.md
  - evidence: R8 N1 用户确认画面、颜色正常但卡顿；R10 HDR10 实际回退 toneMapSdr，用户确认"画面完整、颜色正常，不流畅"，亮度未确认。**P8.4 量化补充（2026-10-05 EOS 观察轮）**：4K30 HLG 素材 toneMapSdr 路径 44 分钟 wall-time 未完成 19.5 分钟素材；完整性能画像三互证——C2DColorConvert 错误 13955 条/1205.6s≈11.6fps 实际渲染（源 29.97fps、掉帧 61%）、AudioTrack underrun 重启 4824 次（250ms 间隔）、推进 0.39x；软色转 C2D 路径瓶颈，建议排期时按系统性性能问题对待；证据 eos-round/eos-round-evidence.json。
  - preserved-work: Release sampler 8 tests/限定分析通过；page opt-in 与退出 drain 草案、43 源 build draft、GPU/battery/context 工具及独审原日志均保留。暂不新构建、安装或扩大测量。
  - next: 排期后完成已存草案独审并同源同路由 baseline 采样；有可快速验证的修复依据时再处理，人工流畅性通过才关闭。

- [ ] HDR 诊断日志落盘机制（已降级：exec-out 日志通路实证正常，仅为便捷性增强）
  - status: planned（降级）
  - context: archives/experiments/lg-hdr-agent-handoff-20261005.md（独立库 ~/src/media-kit-experiments）；docs/requirements/android-hdr-auto-output.md
  - acceptance: hdr_lab 诊断 define 增加关键 HDR_SESSION/route/错误行的文件落盘（app files 目录，pull 可读）；不影响现有 N4 外部报告机制
  - latest: R26 黑屏定性需求已消失（r26b 根因=构建漏注入 JAR，非日志缺失）；本项仅为便捷性增强。
  - next: 排期后实施（改动+审核+构建+实机验证）。

- [ ] 排查 Android HDR 天空渐变层纹
  - status: deferred_by_user
  - context: archives/conversations/android-hdr-dv-display-plan-20260922.md
  - acceptance: 同 PTS 对照片源、解码/合成、输出位深和屏幕处理；若有可行改法，保持 HDR10/P8.4 的亮暗、颜色与全屏流畅性，再请用户人工确认。
  - latest: 最高亮度全屏验收中 HDR10 天空有层纹、P8.4 较轻，其余画面良好。按用户要求先记录，本轮不修；关闭抖动没有明确性能收益，也不是已验证的层纹修复。

- [ ] 现代 Vulkan 设备回归（LG hdr_lab 工作线唯一残余）
  - status: planned（原记"无设备 blocked"；marble 现可用作回归机，待排期）
  - context: archives/conversations/lg-h870ds-hdr-demo-20261004.md
  - acceptance: 现代 Vulkan 渲染设备上 hdr_lab 全内容类型回归（对照 LG/marble 已验收路由），零渲染失败、严格退出闭合。

- [ ] 整理 `archives` 的主题结构与引用
  - status: planned；context: archives/conversations/android-hdr-dv-display-plan-20260922.md
  - inventory: 2026-09-28 有 `archives/experiments` 顶层221篇Markdown、`archives/conversations` 8篇；实验记录中 P5 约133篇、HDR约27篇、P8.4约18篇、HDR10约13篇，缺统一入口。（2026-10-05 起 archives/experiments 已整体迁 `~/src/media-kit-experiments`，本项范围为该库。）
  - acceptance: 先为每个活跃任务建立从 `TASKS.md` 可直达的主题索引，明确当前结论、证据顺序和旧实验状态；再按主题迁移零散实验文件，保持原始证据与每个topic唯一conversation；同步修正 `TASKS.md`、conversation、脚本和文档内的引用，检查链接与文件数。只有确认新路径和Git历史可追溯后才删除旧位置，不批量丢弃未知记录。
  - priority: 归档先做P5/P3索引，再处理HDR10/P8.4与首帧，最后整理其余历史。
  - next: 生成文件到任务的映射、识别重复记录与外部路径引用，制定最小迁移批次；每批先更新入口和链接，再迁移、核验，最后清除确认冗余的旧文件。
